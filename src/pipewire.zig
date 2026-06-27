const std = @import("std");
const c = @import("c.zig").c;
const types = @import("types.zig");
const handleError = @import("error.zig").handleError;

/// A handle for interacting with pipewire
pub const PipewireHandle = struct {
    allocator: std.mem.Allocator,
    loop: *c.pw_loop = undefined,
    context: *c.pw_context = undefined,
    core: *c.pw_core = undefined,
    registry: *c.pw_registry = undefined,
    registry_listener: c.spa_hook = undefined,

    /// TODO: Currently, we are conflating the notions of drawing and the notions of getting metadata from 
    /// pipewire. This isn't very good in my perspective. I should change that.
    nodes: std.AutoArrayHashMapUnmanaged(u32, types.PipewireNode) = .empty,

    /// Registry of functions that should fire based on pipewire events
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
                errdefer self.allocator.free(name_found);

                std.log.debug("PipewireHandle creating new node '{s}'", .{name_found});

                if (self.nodes.getPtr(id)) |existing_node| {
                    std.log.debug("Overwriting existing node with name '{s}'", .{existing_node.name});
                    existing_node.deinit(self.allocator);
                }

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

        fn onGlobalRemove(data: ?*anyopaque, id: u32) callconv(.c) void {
            var self: *PipewireHandle = @ptrCast(@alignCast(data));


            if (self.nodes.getPtr(id)) |*value| {
                (value.*).deinit(self.allocator);
                if(!self.nodes.orderedRemove(id)) {
                    unreachable;
                }

                std.log.debug("Node {d} removed", .{id});
                return;
            }

            var node_it = self.nodes.iterator();
            node_loop: while (node_it.next()) |node| {
                var out_it = node.value_ptr.outs.iterator();
                while (out_it.next()) |port| {
                    if (port.value_ptr.connections.swapRemove(id)) {
                        std.log.debug("Link {d} removed from output port", .{id});
                        continue :node_loop;
                    }
                }

                var inp_it = node.value_ptr.inps.iterator();
                while (inp_it.next()) |port| {
                    if (port.value_ptr.connections.swapRemove(id)) {
                        std.log.debug("Link {d} removed from input port", .{id});
                        continue :node_loop;
                    }
                }
            }
        }

        const registry = c.pw_registry_events{
            .version = c.PW_VERSION_REGISTRY_EVENTS,
            .global = PipewireHandle.GlobalRegistry.onGlobal,
            .global_remove = PipewireHandle.GlobalRegistry.onGlobalRemove,
        };
    };

    /// Construct the handle to pipewire
    pub fn init(allocator: std.mem.Allocator) !*PipewireHandle {
        std.log.info("Trying to init pipewire handle...", .{});
        errdefer std.log.err("Trying to init pipewire handle failed", .{});

        var self = try allocator.create(PipewireHandle);

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

        defer std.log.info("Trying to init pipewire handle OK", .{});
        return self;
    }

    pub fn start_core(self: *PipewireHandle) !void {
        std.log.info("Trying to start pipewire handle...", .{});
        errdefer std.log.info("Trying to start pipewire handle unsuccesful, can be retried", .{});

        self.core = try handleError(
            c.pw_context_connect(self.context, null, 0),
        );

        self.registry = try handleError(
            c.pw_core_get_registry(self.core, c.PW_VERSION_REGISTRY, 0),
        );

        try handleError(
            c.pw_registry_add_listener(
                self.registry,
                &self.registry_listener,
                &PipewireHandle.GlobalRegistry.registry,
                self,
            ),
        );

        std.log.info("Trying to start pipewire handle OK", .{});
    }

    /// Reconsider the graph as presented by the nodes hashmap, and determine appropriate coordinates based on
    /// underlying connections. This method updates the `self.nodes` field to be up to date.
    ///
    /// For plotting left to right, I have decided to place all unconnected nodes first. Then, I place all inputs.
    /// Then, I aim to plot all remaining nodes PREVENTING any feedback paths. This essentially amounts to drawing a
    /// node in the current column iff all of its inputs are in the preceding columns.
    pub fn update_graph_metadata(self: *PipewireHandle) !void {
        // keep track of all nodes we have already placed
        var completed: std.AutoHashMapUnmanaged(u32, void) = .empty;
        defer completed.deinit(self.allocator);

        // Ensure all nodes have a port color associated with them
        {
            var node_it = self.nodes.iterator();
            while (node_it.next()) |*node| {
                node.value_ptr.port_color = types.VibrantColor.getColorByIndex(node.value_ptr.node_id);
            }
        }

        var x_current: f32 = 0;
        var y_current: f32 = 0;

        // First pass: draw the nodes that have NO connections in the first column
        {
            var node_it = self.nodes.iterator();
            while (node_it.next()) |*node| {
                if (completed.contains(node.value_ptr.node_id)) {
                    continue;
                }

                var inp_count: usize = 0;
                var inp_it = node.value_ptr.inps.iterator();
                while (inp_it.next()) |*inp| {
                    inp_count += inp.value_ptr.connections.count();
                }

                var out_count: usize = 0;
                var out_it = node.value_ptr.outs.iterator();
                while (out_it.next()) |*out| {
                    out_count += out.value_ptr.connections.count();
                }

                if (inp_count == 0 and out_count == 0) {
                    node.value_ptr.x = x_current;
                    node.value_ptr.y = y_current;

                    // We draw the nodes in inverse order. This is currently to do with the fact we do stupid
                    // anti-aliaising. Essentially, the draw order matters, we must draw bottom to top... so we
                    // rely implicitly on the order of the nodes! Bad and dumb, but we do it this way.
                    node.value_ptr.z = @floatFromInt(99999 - node.value_ptr.node_id);
                    y_current += node.value_ptr.computeNodeHeight() + types.H_NODE_SPACING;

                    try completed.put(self.allocator, node.value_ptr.node_id, {});
                }
            }
        }

        // Second pass: draw the rest of the nodes
        {
            // Keep going until all nodes placed OR we find a cyclical dependency. In that case we just return
            while (completed.count() != self.nodes.count()) {
                // Next column...
                x_current += types.PipewireNode.W_NODE + types.W_NODE_SPACING;
                y_current = 0;

                // In order to properly place our nodes, we keep track of some metadata
                const NodeInfo = struct { id: u32, center_of_mass: f32 };

                // Dynamic array that tracks metadata
                // TODO: dynamic = shit --> can improve
                var to_be_completed: std.ArrayListUnmanaged(NodeInfo) = .empty;
                defer to_be_completed.deinit(self.allocator);

                // Number of nodes we had drawn at the start
                const completed_start_size = completed.count();

                // For each node...
                var node_it = self.nodes.iterator();
                while (node_it.next()) |*node| {
                    // If node already placed, we skip
                    if (completed.contains(node.value_ptr.node_id)) {
                        continue;
                    }

                    // We only place node if all its dependencies are already placed
                    var all_inputs_placed = true;
                    {
                        var inp_it = node.value_ptr.inps.iterator();
                        inp_loop: while (inp_it.next()) |*inp| {
                            var conn_it = inp.value_ptr.connections.iterator();
                            while (conn_it.next()) |*conn| {
                                if (!completed.contains(conn.value_ptr.node_id)) {
                                    all_inputs_placed = false;
                                    break :inp_loop;
                                }
                            }
                        }
                    }

                    // If all inputs are placed, we schedule a node to be added
                    if (all_inputs_placed) {
                        var locs = try std.ArrayListUnmanaged(f32).initCapacity(self.allocator, 0);
                        defer locs.deinit(self.allocator);

                        // Approximate median wire position and use it as "center of mass" to place the node
                        var center_of_mass: f32 = 0.0;
                        {
                            {
                                var inp_it = node.value_ptr.inps.iterator();
                                while (inp_it.next()) |*inp| {
                                    var conn_it = inp.value_ptr.connections.iterator();
                                    while (conn_it.next()) |*conn| {
                                        try locs.append(self.allocator, self.nodes.get(conn.value_ptr.node_id).?.y.?);
                                    }
                                }
                            }

                            std.mem.sort(f32, locs.items, {}, std.sort.asc(f32));

                            if (locs.items.len > 0) {
                                std.mem.sort(f32, locs.items, {}, std.sort.asc(f32));
                                center_of_mass = locs.items[locs.items.len / 2];
                            }
                        }

                        try to_be_completed.append(self.allocator, .{
                            .id = node.value_ptr.node_id,
                            .center_of_mass = center_of_mass,
                        });
                    }
                }

                // Draw nodes in order of center of mass, this reduces the distance between connections
                std.mem.sort(
                    NodeInfo,
                    to_be_completed.items,
                    {},
                    struct {
                        pub fn lessThanFn(_: void, lhs: NodeInfo, rhs: NodeInfo) bool {
                            return lhs.center_of_mass < rhs.center_of_mass;
                        }
                    }.lessThanFn,
                );

                for (to_be_completed.items) |item| {
                    const node = self.nodes.getPtr(item.id).?;
                    node.x = x_current;
                    node.y = y_current;

                    // We draw the nodes in inverse order. This is currently to do with the fact we do stupid
                    // anti-aliaising. Essentially, the draw order matters, we must draw bottom to top... so we
                    // rely implicitly on the order of the nodes! Bad and dumb, but we do it this way.
                    node.z = @floatFromInt(99999 - node.node_id);
                    y_current += node.computeNodeHeight() + types.H_NODE_SPACING;

                    try completed.put(self.allocator, item.id, {});
                }

                // If no nodes were placed this pass, there is a cyclical dependency (feedback loop)
                // We break to prevent hanging the Wayland loop.
                if (completed.count() == completed_start_size) {
                    std.log.warn("Detected cyclical dependencies in PipeWire graph, halting layout pass", .{});
                    return error.PipewireCyclicalDependency;
                }
            }
        }
    }

    /// Returns file descriptor to underlying pipewire loop
    pub fn fd(self: *const PipewireHandle) i32 {
        return c.pw_loop_get_fd(self.loop);
    }

    /// Drain all events from the registry
    pub fn drain(self: *const PipewireHandle) !void {
        try handleError(
            c.pw_loop_iterate(self.loop, 0),
        );
    }

    pub fn deinit(self: *PipewireHandle) void {
        var node_it = self.nodes.iterator();
        while (node_it.next()) |entry| {
            const node = entry.value_ptr;
            node.deinit(self.allocator);
        }

        self.nodes.deinit(self.allocator);
    }
};
