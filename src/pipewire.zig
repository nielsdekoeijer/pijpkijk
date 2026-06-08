const std = @import("std");
const c = @import("c.zig").c;
const types = @import("types.zig");
const handleError = @import("error.zig").handleError;

// =Pipewire===========================================================================================================
pub const PipewireHandle = struct {
    loop: *c.pw_loop = undefined,
    context: *c.pw_context = undefined,
    core: *c.pw_core = undefined,
    registry: *c.pw_registry = undefined,
    registry_listener: c.spa_hook = undefined,
    allocator: std.mem.Allocator,
    nodes: std.AutoHashMapUnmanaged(u32, types.PipewireNode) = .empty,

    const GlobalRegistry = struct {
        fn onGlobal(
            data: ?*anyopaque,
            id: u32,
            permissions: u32,
            type_str: [*c]const u8,
            version: u32,
            props: [*c]const c.spa_dict,
        ) callconv(.c) void {
            var self: *PipewireHandle = @ptrCast(@alignCast(data));

            errdefer {
                @panic("Unrecoverable throw in C-style callback");
            }

            const type_span = std.mem.span(type_str);
            if (props == null) {
                std.log.warn("PipewireHandle got unexpected null property dict", .{});
                return;
            }

            if (std.mem.eql(u8, type_span, c.PW_TYPE_INTERFACE_Client)) {
                // std.log.debug("PipewireHandle treating as Client", .{});
                // Currently, no implementation
            }
            if (std.mem.eql(u8, type_span, c.PW_TYPE_INTERFACE_Core)) {
                // std.log.debug("PipewireHandle treating as Core", .{});
                // Currently, no implementation
            }
            if (std.mem.eql(u8, type_span, c.PW_TYPE_INTERFACE_Device)) {
                // std.log.debug("PipewireHandle treating as Device", .{});
                // Currently, no implementation
            }
            if (std.mem.eql(u8, type_span, c.PW_TYPE_INTERFACE_Factory)) {
                // std.log.debug("PipewireHandle treating as Factory", .{});
                // Currently, no implementation
            }
            if (std.mem.eql(u8, type_span, c.PW_TYPE_INTERFACE_Link)) {
                // std.log.debug("PipewireHandle treating as Link", .{});
                const dict = props.*;

                var out_node_id: ?u32 = null;
                var out_port_id: ?u32 = null;
                var inp_node_id: ?u32 = null;
                var inp_port_id: ?u32 = null;

                for (0..dict.n_items) |i| {
                    const item = dict.items[i];
                    const item_key = std.mem.span(item.key);
                    const item_value = std.mem.span(item.value);
                    // std.log.debug("--> '{s}:{s}'", .{ item_key, item_value });

                    if (std.mem.eql(u8, item_key, c.PW_KEY_LINK_OUTPUT_NODE)) {
                        out_node_id = try std.fmt.parseInt(u32, item_value, 10);
                    } else if (std.mem.eql(u8, item_key, c.PW_KEY_LINK_OUTPUT_PORT)) {
                        out_port_id = try std.fmt.parseInt(u32, item_value, 10);
                    } else if (std.mem.eql(u8, item_key, c.PW_KEY_LINK_INPUT_NODE)) {
                        inp_node_id = try std.fmt.parseInt(u32, item_value, 10);
                    } else if (std.mem.eql(u8, item_key, c.PW_KEY_LINK_INPUT_PORT)) {
                        inp_port_id = try std.fmt.parseInt(u32, item_value, 10);
                    }
                }

                var out_node_id_found: u32 = undefined;
                if (out_node_id) |found| {
                    out_node_id_found = found;
                } else {
                    std.log.err("Expected id for pipewire out node, not found", .{});
                    return error.PipewireError;
                }

                var out_port_id_found: u32 = undefined;
                if (out_port_id) |found| {
                    out_port_id_found = found;
                } else {
                    std.log.err("Expected out port id for pipewire link, not found", .{});
                    return error.PipewireError;
                }

                var inp_node_id_found: u32 = undefined;
                if (inp_node_id) |found| {
                    inp_node_id_found = found;
                } else {
                    std.log.err("Expected inp node id for pipewire link, not found", .{});
                    return error.PipewireError;
                }

                var inp_port_id_found: u32 = undefined;
                if (inp_port_id) |found| {
                    inp_port_id_found = found;
                } else {
                    std.log.err("Expected inp port id for pipewire link, not found", .{});
                    return error.PipewireError;
                }

                std.log.debug("PipewireHandle creating new link '{}'", .{id});

                if (self.nodes.getPtr(out_node_id_found)) |out_node| {
                    if (out_node.outs.getPtr(out_port_id_found)) |out_port| {
                        try out_port.connections.put(self.allocator, id, .{
                            .node_id = inp_node_id_found,
                            .port_id = inp_port_id_found,
                            .link_id = id,
                        });
                    } else {
                        std.log.err("Output port id '{}' not found on node '{}' while adding link", .{ out_port_id_found, out_node_id_found });
                        return error.PipewireError;
                    }
                } else {
                    std.log.err("Output node id '{}' not found while adding link", .{out_node_id_found});
                    return error.PipewireError;
                }

                if (self.nodes.getPtr(inp_node_id_found)) |inp_node| {
                    if (inp_node.inps.getPtr(inp_port_id_found)) |inp_port| {
                        try inp_port.connections.put(self.allocator, id, .{
                            .node_id = out_node_id_found,
                            .port_id = out_port_id_found,
                            .link_id = id,
                        });
                    } else {
                        std.log.err("Input port id '{}' not found on node '{}' while adding link", .{ inp_port_id_found, inp_node_id_found });
                        return error.PipewireError;
                    }
                } else {
                    std.log.err("Input node id '{}' not found while adding link", .{inp_node_id_found});
                    return error.PipewireError;
                }

                return;
            }
            if (std.mem.eql(u8, type_span, c.PW_TYPE_INTERFACE_Module)) {
                // std.log.debug("PipewireHandle treating as Module", .{});
                // Currently, no implementation
            }
            if (std.mem.eql(u8, type_span, c.PW_TYPE_INTERFACE_Node)) {
                // std.log.debug("PipewireHandle treating as Node", .{});
                const dict = props.*;

                var node_nick: ?[]const u8 = null;
                var node_name: ?[]const u8 = null;

                for (0..dict.n_items) |i| {
                    const item = dict.items[i];
                    const item_key = std.mem.span(item.key);
                    const item_value = std.mem.span(item.value);
                    // std.log.debug("--> '{s}:{s}'", .{ item_key, item_value });

                    if (std.mem.eql(u8, item_key, c.PW_KEY_NODE_NICK)) {
                        node_nick = item_value;
                    }

                    if (std.mem.eql(u8, item_key, c.PW_KEY_NODE_NAME)) {
                        node_name = item_value;
                    }
                }

                var name_found: []const u8 = undefined;
                if (node_nick) |name| {
                    name_found = try self.allocator.dupe(u8, name);
                } else if (node_name) |name| {
                    name_found = try self.allocator.dupe(u8, name);
                } else {
                    name_found = try self.allocator.dupe(u8, "Unknown Node");
                }

                std.log.debug("PipewireHandle creating new node '{s}'", .{name_found});

                try self.nodes.put(self.allocator, id, .{
                    .node_id = id,
                    .name = name_found,
                    .inps = .empty,
                    .outs = .empty,

                    .port_color = null,
                    .x = null,
                    .y = null,
                });

                return;
            }

            if (std.mem.eql(u8, type_span, c.PW_TYPE_INTERFACE_Port)) {
                // std.log.debug("PipewireHandle treating as Port", .{});
                const dict = props.*;

                var port_name: ?[]const u8 = null;
                var node_id: ?u32 = null;
                var is_inp: ?bool = null;

                for (0..dict.n_items) |i| {
                    const item = dict.items[i];
                    const item_key = std.mem.span(item.key);
                    const item_value = std.mem.span(item.value);
                    // std.log.debug("--> '{s}:{s}'", .{ item_key, item_value });

                    if (std.mem.eql(u8, item_key, c.PW_KEY_PORT_NAME)) {
                        port_name = item_value;
                    }

                    if (std.mem.eql(u8, item_key, c.PW_KEY_NODE_ID)) {
                        node_id = try std.fmt.parseInt(u32, item_value, 10);
                    }

                    if (std.mem.eql(u8, item_key, c.PW_KEY_PORT_DIRECTION)) {
                        if (std.mem.eql(u8, item_value, "in")) {
                            is_inp = true;
                        } else if (std.mem.eql(u8, item_value, "out")) {
                            is_inp = false;
                        } else {
                            std.log.err("Expected valid pipewire direction", .{});
                            return error.PipewireError;
                        }
                    }
                }

                var name_found: []const u8 = undefined;
                if (port_name) |name| {
                    name_found = try self.allocator.dupe(u8, name);
                } else {
                    name_found = try self.allocator.dupe(u8, "Unknown Node");
                }

                var node_id_found: u32 = undefined;
                if (node_id) |found| {
                    node_id_found = found;
                } else {
                    std.log.err("Expected id for pipewire port, not found", .{});
                    return error.PipewireError;
                }

                var is_inp_found: bool = undefined;
                if (is_inp) |found| {
                    is_inp_found = found;
                } else {
                    std.log.err("Expected port direction to be specified", .{});
                    return error.PipewireError;
                }

                std.log.debug("PipewireHandle creating new port '{s}'", .{name_found});

                if (self.nodes.getPtr(node_id_found)) |node| {
                    if (is_inp_found) {
                        try node.inps.put(self.allocator, id, .{
                            .name = name_found,
                        });
                    } else {
                        try node.outs.put(self.allocator, id, .{
                            .name = name_found,
                            .connections = .empty,
                        });
                    }
                } else {
                    std.log.err("Node id '{}' not found while adding port", .{node_id_found});
                    return error.PipewireError;
                }

                return;
            }

            if (std.mem.eql(u8, type_span, c.PW_TYPE_INTERFACE_Registry)) {
                // std.log.debug("PipewireHandle treating as Registry", .{});
                // Currently, no implementation
                return;
            }

            _ = permissions;
            _ = version;
        }

        fn onGlobalRemove(
            data: ?*anyopaque,
            id: u32,
        ) callconv(.c) void {
            // std.log.debug("PipewireHandle global remove called", .{});
            _ = data;
            _ = id;
        }

        const registry = c.pw_registry_events{
            .version = c.PW_VERSION_REGISTRY_EVENTS,
            .global = PipewireHandle.GlobalRegistry.onGlobal,
            .global_remove = PipewireHandle.GlobalRegistry.onGlobalRemove,
        };
    };

    /// Reconsider the graph as presented by the nodes hashmap, and determine appropriate coordinates based on
    /// underlying connections.
    ///
    /// For plotting left to right, I have decided to place all unconnected nodes first. Then, I place all inputs.
    /// Then, I aim to plot all remaining nodes PREVENTING any feedback paths. This essentially amounts to drawing a
    /// node in the current column iff all of its inputs are in the preceding columns.
    pub fn update_graph_metadata(self: *PipewireHandle) !void {
        // keep track of all nodes we have already placed
        var completed: std.AutoHashMapUnmanaged(u32, void) = .empty;
        defer completed.deinit(self.allocator);

        var x_current: f32 = 0;
        var y_current: f32 = 0;

        {
            var node_it = self.nodes.iterator();
            while (node_it.next()) |*node| {
                node.value_ptr.port_color = types.VibrantColor.getColorByIndex(node.value_ptr.node_id);
            }
        }

        {
            var node_it = self.nodes.iterator();
            while (node_it.next()) |*node| {
                if (completed.contains(node.value_ptr.node_id)) {
                    continue;
                }

                var inp_count: usize = 0;
                var inp_it = node.value_ptr.inps.iterator();
                while (inp_it.next()) |*inp| {
                    inp_count += inp.value_ptr.connections.size;
                }

                var out_count: usize = 0;
                var out_it = node.value_ptr.outs.iterator();
                while (out_it.next()) |*out| {
                    out_count += out.value_ptr.connections.size;
                }

                if (inp_count == 0 and out_count == 0) {
                    node.value_ptr.x = x_current;

                    node.value_ptr.y = y_current;
                    y_current += node.value_ptr.computeNodeHeight() + types.H_NODE_SPACING;

                    try completed.put(self.allocator, node.value_ptr.node_id, {});
                }
            }
        }

        x_current += types.PipewireNode.W_NODE + types.W_NODE_SPACING;
        y_current = 0;

        {
            var to_be_completed: std.ArrayListUnmanaged(u32) = .empty;
            defer to_be_completed.deinit(self.allocator);

            while (completed.size != self.nodes.size) {
                const completed_start_size = completed.size;

                var node_it = self.nodes.iterator();
                while (node_it.next()) |*node| {
                    if (completed.contains(node.value_ptr.node_id)) {
                        continue;
                    }

                    var all_deps_met = true;
                    var inp_it = node.value_ptr.inps.iterator();
                    inp_loop: while (inp_it.next()) |*inp| {
                        var conn_it = inp.value_ptr.connections.iterator();
                        while (conn_it.next()) |*conn| {
                            if (!completed.contains(conn.value_ptr.node_id)) {
                                all_deps_met = false;
                                break :inp_loop;
                            }
                        }
                    }

                    if (all_deps_met) {
                        node.value_ptr.x = x_current;

                        node.value_ptr.y = y_current;
                        y_current += node.value_ptr.computeNodeHeight() + types.H_NODE_SPACING;

                        try to_be_completed.append(self.allocator, node.value_ptr.node_id);
                    }
                }

                for (to_be_completed.items) |item| {
                    try completed.put(self.allocator, item, {});
                }

                // If no nodes were placed this pass, there is a cyclical dependency (feedback loop)
                // We break to prevent hanging the Wayland loop.
                if (completed.size == completed_start_size) {
                    std.log.warn("Detected cyclical dependencies in PipeWire graph, halting layout pass", .{});
                    break;
                }

                x_current += types.PipewireNode.W_NODE + types.W_NODE_SPACING;
                y_current = 0;

            }
        }
    }

    /// Returns file descriptor to udnerlying pipewire loop
    pub fn fd(self: *const PipewireHandle) i32 {
        return c.pw_loop_get_fd(self.loop);
    }

    pub fn init(self: *PipewireHandle, allocator: std.mem.Allocator) !void {
        std.log.info("Trying to init pipewire handle...", .{});
        errdefer std.log.err("Trying to init pipewire handle failed", .{});

        self.* = PipewireHandle{
            .allocator = allocator,
        };

        c.pw_init(null, null);

        self.loop = try handleError(
            c.pw_loop_new(null),
        );

        self.context = try handleError(
            c.pw_context_new(self.loop, null, 0),
        );

        self.core = try handleError(
            c.pw_context_connect(self.context, null, 0),
        );

        self.registry = try handleError(
            c.pw_core_get_registry(self.core, c.PW_VERSION_REGISTRY, 0),
        );

        try handleError(
            c.pw_registry_add_listener(self.registry, &self.registry_listener, &PipewireHandle.GlobalRegistry.registry, self),
        );

        std.log.info("Trying to init pipewire handle OK", .{});
    }

    pub fn deinit(self: *PipewireHandle) void {
        _ = self;
    }
};
