const std = @import("std");
const c = @import("c.zig").c;
const types = @import("types.zig");

// Internal representations for tracking async objects
const PwNode = struct {
    id: u32,
    name: []const u8,
    color: [4]f32,
    x: f32,
    y: f32,
};

const PwPort = struct {
    id: u32,
    node_id: u32,
    name: []const u8,
    is_input: bool,
};

const PwLink = struct {
    id: u32,
    out_node_id: u32,
    out_port_id: u32,
    in_node_id: u32,
    in_port_id: u32,
};

pub const PwGraph = struct {
    allocator: std.mem.Allocator,
    thread_loop: *c.pw_thread_loop,
    context: *c.pw_context,
    core: *c.pw_core,
    registry: *c.pw_registry,

    registry_listener: c.spa_hook = undefined,

    prng: std.Random.Xoshiro256,

    // Internal async state
    pw_nodes: std.AutoHashMap(u32, PwNode),
    pw_ports: std.AutoHashMap(u32, PwPort),
    pw_links: std.AutoHashMap(u32, PwLink),

    pub fn init(allocator: std.mem.Allocator, io: std.Io) !*PwGraph {
        c.pw_init(null, null);

        const self = try allocator.create(PwGraph);
        self.* = .{
            .allocator = allocator,
            .thread_loop = undefined,
            .context = undefined,
            .core = undefined,
            .registry = undefined,
            .prng = std.Random.Xoshiro256.init(@intCast(std.Io.Timestamp.now(io, .cpu_process).nanoseconds)),
            .pw_nodes = std.AutoHashMap(u32, PwNode).init(allocator),
            .pw_ports = std.AutoHashMap(u32, PwPort).init(allocator),
            .pw_links = std.AutoHashMap(u32, PwLink).init(allocator),
        };

        // 1. Thread Loop
        self.thread_loop = c.pw_thread_loop_new("pijpkijk-pw-loop", null) orelse return error.PwLoopFailed;

        // 2. Context
        self.context = c.pw_context_new(c.pw_thread_loop_get_loop(self.thread_loop), null, 0) orelse return error.PwContextFailed;

        // 3. Start Thread
        if (c.pw_thread_loop_start(self.thread_loop) < 0) return error.PwThreadStartFailed;

        // 4. Connect to Daemon (must be locked)
        c.pw_thread_loop_lock(self.thread_loop);
        defer c.pw_thread_loop_unlock(self.thread_loop);

        self.core = c.pw_context_connect(self.context, null, 0) orelse return error.PwConnectFailed;
        self.registry = c.pw_core_get_registry(self.core, c.PW_VERSION_REGISTRY, 0) orelse return error.PwRegistryFailed;

        // 5. Listen to Registry
        const registry_events = try allocator.create(c.pw_registry_events);
        registry_events.* = .{
            .version = c.PW_VERSION_REGISTRY_EVENTS,
            .global = onGlobal,
            .global_remove = onGlobalRemove,
        };

        _ = c.pw_registry_add_listener(self.registry, &self.registry_listener, registry_events, self);

        return self;
    }

    pub fn deinit(self: *PwGraph) void {
        c.pw_thread_loop_stop(self.thread_loop);
        c.pw_thread_loop_destroy(self.thread_loop);

        // Clean up duplicated strings
        var node_it = self.pw_nodes.iterator();
        while (node_it.next()) |n| self.allocator.free(n.value_ptr.name);

        var port_it = self.pw_ports.iterator();
        while (port_it.next()) |p| self.allocator.free(p.value_ptr.name);

        self.pw_nodes.deinit();
        self.pw_ports.deinit();
        self.pw_links.deinit();
        self.allocator.destroy(self);
        c.pw_deinit();
    }

    /// Pulls current async state and builds a clean `[]types.Node` array for rendering.
    /// Uses the provided arena allocator so the caller can wipe it every frame.
    pub fn buildRenderNodes(self: *PwGraph, arena: std.mem.Allocator) ![]types.Node {
        var result = try std.ArrayList(types.Node).initCapacity(arena, self.pw_nodes.count());

        // Map: PipeWire Node ID -> Index in our result array
        var id_to_idx = std.AutoHashMap(u32, usize).init(arena);

        // 1. Create Base Nodes
        var node_it = self.pw_nodes.iterator();
        while (node_it.next()) |entry| {
            const pw_n = entry.value_ptr.*;
            try id_to_idx.put(pw_n.id, result.items.len);

            result.appendAssumeCapacity(.{
                .name = pw_n.name,
                .color = pw_n.color,
                .x = pw_n.x,
                .y = pw_n.y,
                .inps = &.{}, // Populated in next step
                .outs = &.{}, // Populated in next step
            });
        }

        // 2. Attach Ports
        var inps_lists = try arena.alloc(std.ArrayList(types.InpPin), result.items.len);
        var outs_lists = try arena.alloc(std.ArrayList(types.OutPin), result.items.len);

        // Map: PipeWire Port ID -> Index in its parent node's inps/outs array
        var port_to_local_idx = std.AutoHashMap(u32, usize).init(arena);

        for (0..result.items.len) |i| {
            inps_lists[i] = try std.ArrayList(types.InpPin).initCapacity(arena, 0);
            outs_lists[i] = try std.ArrayList(types.OutPin).initCapacity(arena, 0);
        }

        var port_it = self.pw_ports.iterator();
        while (port_it.next()) |entry| {
            const pw_p = entry.value_ptr.*;
            if (id_to_idx.get(pw_p.node_id)) |node_idx| {
                if (pw_p.is_input) {
                    try port_to_local_idx.put(pw_p.id, inps_lists[node_idx].items.len);
                    try inps_lists[node_idx].append(arena, .{ .name = pw_p.name });
                } else {
                    try port_to_local_idx.put(pw_p.id, outs_lists[node_idx].items.len);
                    try outs_lists[node_idx].append(arena, .{
                        .name = pw_p.name,
                        .connections = &.{}, // Populated in link step
                    });
                }
            }
        }

        // 3. Attach Links (Connections)
        var connections_lists = std.AutoHashMap(u32, std.ArrayList(types.Connection)).init(arena);

        var link_it = self.pw_links.iterator();
        while (link_it.next()) |entry| {
            const link = entry.value_ptr.*;

            // Resolve IDs to local indices
            const out_node_idx = id_to_idx.get(link.out_node_id) orelse continue;
            _ = out_node_idx;
            const in_node_idx = id_to_idx.get(link.in_node_id) orelse continue;
            const in_port_local_idx = port_to_local_idx.get(link.in_port_id) orelse continue;

            const conn = types.Connection{
                .node_index = in_node_idx,
                .inp_index = in_port_local_idx,
            };

            // Group connections by output port ID
            var list = connections_lists.get(link.out_port_id) orelse try std.ArrayList(types.Connection).initCapacity(arena, 0);
            try list.append(arena, conn);
            try connections_lists.put(link.out_port_id, list);
        }

        // 4. Finalize arrays into the result
        for (0..result.items.len) |node_idx| {
            // Assign Inputs
            result.items[node_idx].inps = inps_lists[node_idx].items;

            // Assign Outputs & Their Connections
            for (outs_lists[node_idx].items, 0..) |*out_pin, local_out_idx| {
                // We need the original PW Port ID to find connections. It's tedious to reverse look up,
                // so we just iterate ports again for this node.
                var p_it = self.pw_ports.iterator();
                while (p_it.next()) |p_entry| {
                    const pw_p = p_entry.value_ptr.*;

                    // Actually, let's just find the port ID that matches this local_out_idx
                    if (!pw_p.is_input and id_to_idx.get(pw_p.node_id) == node_idx) {
                        if (port_to_local_idx.get(pw_p.id) == local_out_idx) {
                            if (connections_lists.get(pw_p.id)) |conns| {
                                out_pin.connections = conns.items;
                            }
                            break;
                        }
                    }
                }
            }
            result.items[node_idx].outs = outs_lists[node_idx].items;
        }

        return result.items;
    }

    // --- C Callbacks ---

    fn dictLookup(dict: [*c]const c.spa_dict, key: []const u8) ?[]const u8 {
        if (dict == null) return null;
        const d = dict.*;
        for (0..d.n_items) |i| {
            const k = std.mem.span(d.items[i].key);
            if (std.mem.eql(u8, k, key)) return std.mem.span(d.items[i].value);
        }
        return null;
    }

    fn onGlobal(
        data: ?*anyopaque,
        id: u32,
        permissions: u32,
        type_str: [*c]const u8,
        version: u32,
        props: [*c]const c.spa_dict,
    ) callconv(.c) void {
        _ = permissions;
        _ = version;
        const self: *PwGraph = @ptrCast(@alignCast(data));
        const t = std.mem.span(type_str);

        if (std.mem.eql(u8, t, c.PW_TYPE_INTERFACE_Node)) {
            const raw_name = dictLookup(props, c.PW_KEY_NODE_DESCRIPTION) orelse dictLookup(props, c.PW_KEY_NODE_NAME) orelse "Unknown Node";

            const name = self.allocator.dupe(u8, raw_name) catch return;

            // Random layout cascade
            const rand_x = @as(f32, @floatFromInt(self.prng.random().intRangeAtMost(u16, 0, 2000)));
            const rand_y = @as(f32, @floatFromInt(self.prng.random().intRangeAtMost(u16, 0, 2000)));

            self.pw_nodes.put(id, .{
                .id = id,
                .name = name,
                .color = types.VibrantColor.getRandom(self.prng.random()),
                .x = rand_x,
                .y = rand_y,
            }) catch {};
        } else if (std.mem.eql(u8, t, c.PW_TYPE_INTERFACE_Port)) {
            const raw_name = dictLookup(props, c.PW_KEY_PORT_NAME) orelse "port";
            const name = self.allocator.dupe(u8, raw_name) catch return;

            const node_id_str = dictLookup(props, c.PW_KEY_NODE_ID) orelse return;
            const node_id = std.fmt.parseInt(u32, node_id_str, 10) catch return;

            const dir_str = dictLookup(props, c.PW_KEY_PORT_DIRECTION) orelse "in";
            const is_input = std.mem.eql(u8, dir_str, "in");

            self.pw_ports.put(id, .{
                .id = id,
                .node_id = node_id,
                .name = name,
                .is_input = is_input,
            }) catch {};
        } else if (std.mem.eql(u8, t, c.PW_TYPE_INTERFACE_Link)) {
            const out_node_str = dictLookup(props, c.PW_KEY_LINK_OUTPUT_NODE) orelse return;
            const out_port_str = dictLookup(props, c.PW_KEY_LINK_OUTPUT_PORT) orelse return;
            const in_node_str = dictLookup(props, c.PW_KEY_LINK_INPUT_NODE) orelse return;
            const in_port_str = dictLookup(props, c.PW_KEY_LINK_INPUT_PORT) orelse return;

            self.pw_links.put(id, .{
                .id = id,
                .out_node_id = std.fmt.parseInt(u32, out_node_str, 10) catch return,
                .out_port_id = std.fmt.parseInt(u32, out_port_str, 10) catch return,
                .in_node_id = std.fmt.parseInt(u32, in_node_str, 10) catch return,
                .in_port_id = std.fmt.parseInt(u32, in_port_str, 10) catch return,
            }) catch {};
        }
    }

    fn onGlobalRemove(data: ?*anyopaque, id: u32) callconv(.c) void {
        const self: *PwGraph = @ptrCast(@alignCast(data));

        if (self.pw_nodes.fetchRemove(id)) |kv| self.allocator.free(kv.value.name);
        if (self.pw_ports.fetchRemove(id)) |kv| self.allocator.free(kv.value.name);
        _ = self.pw_links.remove(id);
    }
};
