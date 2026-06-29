const std = @import("std");
const c = @import("c.zig").c;
const types = @import("types.zig");
const handleError = @import("error.zig").handleError;

pub const PipewireNode = struct {
    name: []const u8,
    moving_average_runtime_ns: ?f32 = null,
    inps: std.ArrayListUnmanaged(u32) = .empty,
    outs: std.ArrayListUnmanaged(u32) = .empty,

    pub fn deinit(self: *PipewireNode, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        self.inps.deinit(allocator);
        self.outs.deinit(allocator);
    }
};

pub const PipewirePort = struct {
    name: []const u8,
    links: std.ArrayListUnmanaged(u32) = .empty,
};

pub const PipewireLink = struct {
    selected: bool = false,
};

/// A handle for interacting with pipewire
pub const PipewireHandle = struct {
    allocator: std.mem.Allocator,
    loop: *c.pw_loop = undefined,
    context: *c.pw_context = undefined,
    core: *c.pw_core = undefined,
    registry: *c.pw_registry = undefined,
    registry_listener: c.spa_hook = undefined,
    profiler: *c.pw_profiler = undefined,
    profiler_listener: c.spa_hook = undefined,

    /// TODO: Currently, we are conflating the notions of drawing and the notions of getting metadata from
    /// pipewire. This isn't very good in my perspective. I should change that.
    nodes: std.AutoArrayHashMapUnmanaged(u32, types.PipewireNode) = .empty,
    nodes_dirty: bool = true,

    pipewire_nodes: std.AutoArrayHashMapUnmanaged(u32, PipewireNode) = .empty,
    pipewire_links: std.AutoArrayHashMapUnmanaged(u32, PipewireLink) = .empty,
    pipewire_ports: std.AutoArrayHashMapUnmanaged(u32, PipewirePort) = .empty,

    const ProfilerRegistry = struct {
        /// Handle the spa messages coming from pipewire containing the profiling information
        pub fn profile(data: ?*anyopaque, pod: [*c]const c.spa_pod) callconv(.c) void {
            var self: *PipewireHandle = @ptrCast(@alignCast(data));

            if (pod == null) {
                return;
            }

            // Pipewire normally has macros for this. I used my brain + AI to reverse engineer them, and this
            // is what it seems to come down down too. Essentially, we are just skipping the header.
            const pod_ptr = @as([*]const u8, @ptrCast(pod)) + @sizeOf(c.spa_pod);
            const pod_size = pod.*.size;

            var pod_iter = @as([*c]const c.spa_pod, @ptrCast(@alignCast(pod_ptr)));
            while (c.spa_pod_is_inside(pod_ptr, pod_size, pod_iter)) {
                if (c.spa_pod_is_object_type(pod_iter, c.SPA_TYPE_OBJECT_Profiler)) {
                    const prop = @as([*c]const c.spa_pod_object, @ptrCast(pod_iter));

                    var prop_iter = c.spa_pod_prop_first(&prop.*.body);
                    while (c.spa_pod_prop_is_inside(&prop.*.body, prop.*.pod.size, prop_iter)) {
                        prop_loop: switch (prop_iter.*.key) {
                            c.SPA_PROFILER_driverBlock, c.SPA_PROFILER_followerBlock => {
                                const field = &prop_iter.*.value;
                                const field_ptr = @as([*]const u8, @ptrCast(field)) + @sizeOf(c.spa_pod);
                                const field_size = field.*.size;

                                // fields we're looking for
                                var id: ?u32 = null;
                                var awake: ?u64 = null;
                                var finish: ?u64 = null;

                                var field_counter: usize = 0;
                                var field_iter = @as([*c]const c.spa_pod, @ptrCast(@alignCast(field_ptr)));

                                while (c.spa_pod_is_inside(field_ptr, field_size, field_iter)) {
                                    switch (field_counter) {
                                        0 => {
                                            if (field_iter.*.type == c.SPA_TYPE_Int) {
                                                id = @intCast(@as([*c]const c.spa_pod_int, @ptrCast(@alignCast(field_iter))).*.value);
                                            } else {
                                                break :prop_loop;
                                            }
                                        },
                                        4 => {
                                            if (field_iter.*.type == c.SPA_TYPE_Long) {
                                                awake = @intCast(@as([*c]const c.spa_pod_long, @ptrCast(@alignCast(field_iter))).*.value);
                                            } else {
                                                break :prop_loop;
                                            }
                                        },
                                        5 => {
                                            if (field_iter.*.type == c.SPA_TYPE_Long) {
                                                finish = @intCast(@as([*c]const c.spa_pod_long, @ptrCast(@alignCast(field_iter))).*.value);
                                            } else {
                                                break :prop_loop;
                                            }
                                        },
                                        else => {},
                                    }

                                    field_counter += 1;
                                    field_iter = @ptrCast(@alignCast(c.spa_pod_next(field_iter)));
                                }

                                // We're safe to use the optionals here as
                                if (self.nodes.getPtr(id.?)) |node| {
                                    if (finish.? >= awake.?) {
                                        const duration_ns = @as(f32, @floatFromInt(finish.? - awake.?));
                                        if (node.mean_runtime_ns) |*runtime_ns| {
                                            node.mean_runtime_ns = runtime_ns.* * 0.95 + duration_ns * 0.05;
                                        } else {
                                            node.mean_runtime_ns = duration_ns;
                                        }
                                    } else {
                                        std.log.warn(
                                            "unexpected pipewire node finish time '{}' less than awake time '{}'",
                                            .{ finish.?, awake.? },
                                        );
                                    }
                                }
                            },
                            else => {},
                        }

                        prop_iter = @ptrCast(@alignCast(c.spa_pod_prop_next(prop_iter)));
                    }
                }

                pod_iter = @ptrCast(@alignCast(c.spa_pod_next(pod_iter)));
            }
        }

        const registry = c.pw_profiler_events{
            .version = c.PW_VERSION_PROFILER_EVENTS,
            .profile = PipewireHandle.ProfilerRegistry.profile,
        };
    };

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

            const PipewireInterfaceType = enum(u8) {
                CLIENT,
                CORE,
                DEVICE,
                FACTORY,
                LINK,
                MODULE,
                NODE,
                PORT,
                REGISTRY,
                PROFILER,
            };

            const interface_type: PipewireInterfaceType = blk: {
                if (std.mem.eql(u8, type_span, c.PW_TYPE_INTERFACE_Client)) {
                    break :blk PipewireInterfaceType.CLIENT;
                } else if (std.mem.eql(u8, type_span, c.PW_TYPE_INTERFACE_Core)) {
                    break :blk PipewireInterfaceType.CORE;
                } else if (std.mem.eql(u8, type_span, c.PW_TYPE_INTERFACE_Device)) {
                    break :blk PipewireInterfaceType.DEVICE;
                } else if (std.mem.eql(u8, type_span, c.PW_TYPE_INTERFACE_Factory)) {
                    break :blk PipewireInterfaceType.FACTORY;
                } else if (std.mem.eql(u8, type_span, c.PW_TYPE_INTERFACE_Link)) {
                    break :blk PipewireInterfaceType.LINK;
                } else if (std.mem.eql(u8, type_span, c.PW_TYPE_INTERFACE_Module)) {
                    break :blk PipewireInterfaceType.MODULE;
                } else if (std.mem.eql(u8, type_span, c.PW_TYPE_INTERFACE_Node)) {
                    break :blk PipewireInterfaceType.NODE;
                } else if (std.mem.eql(u8, type_span, c.PW_TYPE_INTERFACE_Port)) {
                    break :blk PipewireInterfaceType.PORT;
                } else if (std.mem.eql(u8, type_span, c.PW_TYPE_INTERFACE_Registry)) {
                    break :blk PipewireInterfaceType.REGISTRY;
                } else if (std.mem.eql(u8, type_span, c.PW_TYPE_INTERFACE_Profiler)) {
                    break :blk PipewireInterfaceType.PROFILER;
                }

                std.log.info("Received unmodeled pipewire interface type '{s}', ignoring", .{type_span});
                return;
            };

            switch (interface_type) {
                .CLIENT, .CORE, .DEVICE, .FACTORY, .MODULE, .REGISTRY => {},
                .PROFILER => {
                    const profiler_registry = c.pw_registry_bind(
                        self.registry,
                        id,
                        type_str,
                        c.PW_VERSION_PROFILER,
                        0,
                    );

                    if (profiler_registry) |profiler| {
                        self.profiler = @ptrCast(profiler);

                        // Attach the listener so you actually get the profiling data
                        try handleError(
                            c.pw_profiler_add_listener(
                                self.profiler,
                                &self.profiler_listener,
                                &PipewireHandle.ProfilerRegistry.registry,
                                self,
                            ),
                        );
                    } else {
                        std.log.info("Received nullptr when trying to start profiler, assuming not enabled", .{});
                    }
                },
                .LINK => {
                    const dict = props.*;

                    var out_node_id: ?u32 = null;
                    var out_port_id: ?u32 = null;
                    var inp_node_id: ?u32 = null;
                    var inp_port_id: ?u32 = null;

                    for (0..dict.n_items) |i| {
                        const item = dict.items[i];
                        const item_key = std.mem.span(item.key);
                        const item_value = std.mem.span(item.value);

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

                    self.nodes_dirty = true;
                },
                .NODE => {
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

                    // TODO: old
                    if (self.nodes.getPtr(id)) |existing_node| {
                        std.log.debug("Overwriting existing node with name '{s}'", .{existing_node.name});
                        existing_node.deinit(self.allocator);
                    }

                    try self.nodes.put(self.allocator, id, .{
                        .node_id = id,
                        .name = name_found,
                        .inps = .empty,
                        .outs = .empty,
                        .mean_runtime_ns = null,

                        .port_color = null,
                        .x = null,
                        .y = null,
                    });
                    // TODO: old

                    if (self.pipewire_nodes.getPtr(id)) |node| {
                        std.log.debug("Overwriting existing node with name '{s}'", .{node.name});
                        node.deinit(self.allocator);
                    }

                    try self.pipewire_nodes.put(self.allocator, id, .{
                        .name = name_found,
                    });

                    self.nodes_dirty = true;
                },
                .PORT => {
                    const dict = props.*;

                    var port_name: ?[]const u8 = null;
                    var node_id: ?u32 = null;
                    var is_inp: ?bool = null;

                    for (0..dict.n_items) |i| {
                        const item = dict.items[i];
                        const item_key = std.mem.span(item.key);
                        const item_value = std.mem.span(item.value);

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

                    self.nodes_dirty = true;

                    return;
                },
            }

            _ = permissions;
            _ = version;
        }

        fn onGlobalRemove(data: ?*anyopaque, id: u32) callconv(.c) void {
            var self: *PipewireHandle = @ptrCast(@alignCast(data));

            if (self.nodes.getPtr(id)) |*value| {
                (value.*).deinit(self.allocator);
                if (!self.nodes.orderedRemove(id)) {
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

        _ = try handleError(
            c.pw_context_load_module(self.context, c.PW_EXTENSION_MODULE_PROFILER, null, null),
        );

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
    pub fn drain(self: *PipewireHandle) !void {
        try handleError(
            c.pw_loop_iterate(self.loop, 0),
        );

        if (self.nodes_dirty) {
            try self.update_graph_metadata();
            self.nodes_dirty = false;
        }
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
