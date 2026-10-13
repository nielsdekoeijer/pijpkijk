const std = @import("std");
const c = @import("c.zig").c;
const types = @import("types.zig");
const latency = @import("latency.zig");
const handleError = @import("error.zig").handleError;

extern "c" fn pijpkijk_latency_parse(pod: *const c.spa_pod, info: *c.spa_latency_info) c_int;
extern "c" fn pijpkijk_profiler_clock_parse(pod: *const c.spa_pod, rate: *c.spa_fraction, quantum: *u64) c_int;

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

const PortListenerData = struct {
    handle: *PipewireHandle,
    node_id: u32,
    port_id: u32,
    is_inp: bool,
    proxy: ?*c.pw_port = null,
    listener: c.spa_hook = std.mem.zeroes(c.spa_hook),

    fn deinit(self: *PortListenerData) void {
        if (self.proxy) |proxy| c.pw_proxy_destroy(@ptrCast(proxy));
        self.handle.allocator.destroy(self);
    }
};

const NodeListenerData = struct {
    handle: *PipewireHandle,
    node_id: u32,
    proxy: ?*c.pw_node = null,
    listener: c.spa_hook = std.mem.zeroes(c.spa_hook),

    fn deinit(self: *NodeListenerData) void {
        if (self.proxy) |proxy| c.pw_proxy_destroy(@ptrCast(proxy));
        self.handle.allocator.destroy(self);
    }
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
    latency_labels_dirty: bool = true,

    port_listeners: std.ArrayListUnmanaged(*PortListenerData) = .empty,
    node_listeners: std.ArrayListUnmanaged(*NodeListenerData) = .empty,

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
                    var clock_rate: c.spa_fraction = undefined;
                    var clock_quantum: u64 = undefined;
                    const graph_clock: ?latency.Clock = if (pijpkijk_profiler_clock_parse(pod_iter, &clock_rate, &clock_quantum) >= 0)
                        .{ .rate_num = clock_rate.num, .rate_denom = clock_rate.denom, .quantum = clock_quantum }
                    else
                        null;

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

                                const node_id = id orelse break :prop_loop;
                                const start = awake orelse break :prop_loop;
                                const end = finish orelse break :prop_loop;
                                if (self.nodes.getPtr(node_id)) |node| {
                                    const clock = if (node.running) graph_clock else null;
                                    if (!std.meta.eql(node.clock, clock)) {
                                        node.clock = clock;
                                        self.latency_labels_dirty = true;
                                        if (clock) |timing| std.log.debug("Latency clock node={} quantum={} rate={}/{}", .{
                                            node_id, timing.quantum, timing.rate_num, timing.rate_denom,
                                        });
                                    }
                                    if (end >= start) {
                                        const duration_ns = @as(f32, @floatFromInt(end - start));
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

    const PortEvents = struct {
        fn onInfo(data: ?*anyopaque, info: [*c]const c.pw_port_info) callconv(.c) void {
            if (info == null or info.*.change_mask & c.PW_PORT_CHANGE_MASK_PARAMS == 0) return;
            for (0..info.*.n_params) |i| {
                const param = info.*.params[i];
                if (param.id == c.SPA_PARAM_Latency and param.flags & c.SPA_PARAM_INFO_READ != 0) return;
            }
            onParam(data, 0, c.SPA_PARAM_Latency, 0, 0, null);
        }

        fn onParam(data: ?*anyopaque, _: c_int, id: u32, _: u32, _: u32, param_pod: [*c]const c.spa_pod) callconv(.c) void {
            if (id != c.SPA_PARAM_Latency) return;
            const port_data: *PortListenerData = @ptrCast(@alignCast(data));
            const node = port_data.handle.nodes.getPtr(port_data.node_id) orelse return;
            const port = (if (port_data.is_inp) node.inps.getPtr(port_data.port_id) else node.outs.getPtr(port_data.port_id)) orelse return;
            const pod: *const c.spa_pod = param_pod orelse {
                port.setLatency(true, null);
                port.setLatency(false, null);
                port_data.handle.latency_labels_dirty = true;
                return;
            };
            var info: c.spa_latency_info = undefined;
            if (pijpkijk_latency_parse(pod, &info) < 0) return;
            const range = latency.Range{
                .min = .{ .quantum = info.min_quantum, .frames = info.min_rate, .ns = info.min_ns },
                .max = .{ .quantum = info.max_quantum, .frames = info.max_rate, .ns = info.max_ns },
            };
            // The latency object's direction, not the physical port direction,
            // determines whether it describes upstream or downstream delay.
            const target = if (info.direction == c.SPA_DIRECTION_OUTPUT) &port.upstream else &port.downstream;
            if (std.meta.eql(target.*, @as(?latency.Range, range))) return;
            port.setLatency(info.direction == c.SPA_DIRECTION_OUTPUT, range);
            port_data.handle.latency_labels_dirty = true;
            std.log.debug("Latency node={} port={} {s}: {f}", .{
                port_data.node_id,                                          port_data.port_id,
                if (info.direction == c.SPA_DIRECTION_OUTPUT) "U" else "D", range,
            });
        }

        const events = c.pw_port_events{
            .version = c.PW_VERSION_PORT_EVENTS,
            .info = PipewireHandle.PortEvents.onInfo,
            .param = PipewireHandle.PortEvents.onParam,
        };
    };

    const NodeEvents = struct {
        fn onInfo(data: ?*anyopaque, info: [*c]const c.pw_node_info) callconv(.c) void {
            if (info == null or info.*.change_mask & c.PW_NODE_CHANGE_MASK_STATE == 0) return;
            const listener: *NodeListenerData = @ptrCast(@alignCast(data));
            const node = listener.handle.nodes.getPtr(listener.node_id) orelse return;
            node.running = info.*.state == c.PW_NODE_STATE_RUNNING;
            if (!node.running and node.clock != null) {
                node.clock = null;
                listener.handle.latency_labels_dirty = true;
            }
        }

        const events = c.pw_node_events{
            .version = c.PW_VERSION_NODE_EVENTS,
            .info = onInfo,
            .param = null,
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

                    // Gracefully handle event ordering races: link may arrive before
                    // its referenced nodes/ports. Skip instead of panicking.
                    const out_node = self.nodes.getPtr(out_node_id_found) orelse {
                        std.log.warn("Output node id '{}' not found while adding link '{}', skipping (event race?)", .{ out_node_id_found, id });
                        return;
                    };
                    const out_port = out_node.outs.getPtr(out_port_id_found) orelse {
                        std.log.warn("Output port id '{}' not found on node '{}' while adding link '{}', skipping (event race?)", .{ out_port_id_found, out_node_id_found, id });
                        return;
                    };
                    try out_port.connections.put(self.allocator, id, .{
                        .node_id = inp_node_id_found,
                        .port_id = inp_port_id_found,
                        .link_id = id,
                    });

                    const inp_node = self.nodes.getPtr(inp_node_id_found) orelse {
                        std.log.warn("Input node id '{}' not found while adding link '{}', skipping (event race?)", .{ inp_node_id_found, id });
                        return;
                    };
                    const inp_port = inp_node.inps.getPtr(inp_port_id_found) orelse {
                        std.log.warn("Input port id '{}' not found on node '{}' while adding link '{}', skipping (event race?)", .{ inp_port_id_found, inp_node_id_found, id });
                        return;
                    };
                    try inp_port.connections.put(self.allocator, id, .{
                        .node_id = out_node_id_found,
                        .port_id = out_port_id_found,
                        .link_id = id,
                    });

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

                        .port_color = types.VibrantColor.getColorByIndex(id),
                        .x = null,
                        .y = null,
                    });

                    bind_node: {
                        const proxy: *c.pw_node = @ptrCast(c.pw_registry_bind(self.registry, id, type_str, c.PW_VERSION_NODE, 0) orelse break :bind_node);
                        const node_data = self.allocator.create(NodeListenerData) catch {
                            c.pw_proxy_destroy(@ptrCast(proxy));
                            break :bind_node;
                        };
                        node_data.* = .{ .handle = self, .node_id = id, .proxy = proxy };
                        self.node_listeners.append(self.allocator, node_data) catch {
                            node_data.deinit();
                            break :bind_node;
                        };
                        _ = c.pw_node_add_listener(proxy, &node_data.listener, &NodeEvents.events, node_data);
                    }

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

                    // Bind port to subscribe to latency params
                    bind_port: {
                        const proxy: *c.pw_port = @ptrCast(c.pw_registry_bind(self.registry, id, type_str, c.PW_VERSION_PORT, 0) orelse break :bind_port);
                        const port_data = self.allocator.create(PortListenerData) catch {
                            c.pw_proxy_destroy(@ptrCast(proxy));
                            break :bind_port;
                        };
                        port_data.* = .{ .handle = self, .node_id = node_id_found, .port_id = id, .is_inp = is_inp_found, .proxy = proxy };
                        self.port_listeners.append(self.allocator, port_data) catch {
                            port_data.deinit();
                            break :bind_port;
                        };

                        _ = c.pw_port_add_listener(proxy, &port_data.listener, &PipewireHandle.PortEvents.events, port_data);

                        var param_ids = [_]u32{c.SPA_PARAM_Latency};
                        _ = c.pw_port_subscribe_params(proxy, &param_ids, 1);
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

            var listener_index: usize = 0;
            while (listener_index < self.port_listeners.items.len) {
                const listener = self.port_listeners.items[listener_index];
                if (listener.port_id == id or listener.node_id == id) {
                    _ = self.port_listeners.swapRemove(listener_index);
                    listener.deinit();
                } else {
                    listener_index += 1;
                }
            }
            listener_index = 0;
            while (listener_index < self.node_listeners.items.len) {
                const listener = self.node_listeners.items[listener_index];
                if (listener.node_id == id) {
                    _ = self.node_listeners.swapRemove(listener_index);
                    listener.deinit();
                } else {
                    listener_index += 1;
                }
            }

            if (self.nodes.getPtr(id)) |*value| {
                (value.*).deinit(self.allocator);
                if (!self.nodes.orderedRemove(id)) {
                    unreachable;
                }

                std.log.debug("Node {d} removed", .{id});
                self.nodes_dirty = true;
                return;
            }

            // Check if the removed ID is a port
            var node_it = self.nodes.iterator();
            while (node_it.next()) |node| {
                if (node.value_ptr.inps.getPtr(id)) |port| {
                    port.deinit(self.allocator);
                    _ = node.value_ptr.inps.orderedRemove(id);
                    std.log.debug("Input port {d} removed", .{id});
                    self.nodes_dirty = true;
                    return;
                }
                if (node.value_ptr.outs.getPtr(id)) |port| {
                    port.deinit(self.allocator);
                    _ = node.value_ptr.outs.orderedRemove(id);
                    std.log.debug("Output port {d} removed", .{id});
                    self.nodes_dirty = true;
                    return;
                }
            }

            // Check if the removed ID is a link
            node_it = self.nodes.iterator();
            var found_link = false;
            while (node_it.next()) |node| {
                var out_it = node.value_ptr.outs.iterator();
                while (out_it.next()) |port| {
                    if (port.value_ptr.connections.swapRemove(id)) {
                        std.log.debug("Link {d} removed from output port", .{id});
                        found_link = true;
                    }
                }

                var inp_it = node.value_ptr.inps.iterator();
                while (inp_it.next()) |port| {
                    if (port.value_ptr.connections.swapRemove(id)) {
                        std.log.debug("Link {d} removed from input port", .{id});
                        found_link = true;
                    }
                }
            }
            if (found_link) self.nodes_dirty = true;
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
        var column_width: f32 = 0;

        // First pass: place unconnected nodes that have NO input ports in the first column.
        // Unconnected nodes WITH input ports are deferred to the last column.
        var deferred_sink_nodes: std.ArrayListUnmanaged(u32) = .empty;
        defer deferred_sink_nodes.deinit(self.allocator);
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
                    if (node.value_ptr.inps.count() > 0) {
                        // Has input ports but no connections — defer to last column
                        try deferred_sink_nodes.append(self.allocator, node.value_ptr.node_id);
                        continue;
                    }

                    node.value_ptr.x = x_current;
                    node.value_ptr.y = y_current;
                    column_width = @max(column_width, node.value_ptr.width);

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
                x_current += column_width + types.W_NODE_SPACING;
                column_width = 0;
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

                var min_y: f32 = 0;
                for (to_be_completed.items) |item| {
                    const node = self.nodes.getPtr(item.id).?;
                    const node_height = node.computeNodeHeight();
                    const ideal_y = item.center_of_mass - node_height / 2;
                    node.x = x_current;
                    node.y = @max(ideal_y, min_y);
                    column_width = @max(column_width, node.width);

                    // We draw the nodes in inverse order. This is currently to do with the fact we do stupid
                    // anti-aliaising. Essentially, the draw order matters, we must draw bottom to top... so we
                    // rely implicitly on the order of the nodes! Bad and dumb, but we do it this way.
                    node.z = @floatFromInt(99999 - node.node_id);
                    min_y = node.y.? + node_height + types.H_NODE_SPACING;

                    try completed.put(self.allocator, item.id, {});
                }

                // If no nodes were placed this pass, there is a cyclical dependency (feedback loop)
                // Place all remaining nodes in the current empty column and break.
                if (completed.count() == completed_start_size) {
                    std.log.warn("Detected cyclical dependencies in PipeWire graph, placing remaining nodes", .{});
                    y_current = 0;

                    var remaining_it = self.nodes.iterator();
                    while (remaining_it.next()) |*remaining| {
                        if (completed.contains(remaining.value_ptr.node_id)) continue;
                        remaining.value_ptr.x = x_current;
                        remaining.value_ptr.y = y_current;
                        column_width = @max(column_width, remaining.value_ptr.width);
                        remaining.value_ptr.z = @floatFromInt(99999 - remaining.value_ptr.node_id);
                        y_current += remaining.value_ptr.computeNodeHeight() + types.H_NODE_SPACING;
                        try completed.put(self.allocator, remaining.value_ptr.node_id, {});
                    }
                    break;
                }
            }
        }

        // Last column: place unconnected sink nodes (have input ports but no connections)
        if (deferred_sink_nodes.items.len > 0) {
            x_current += column_width + types.W_NODE_SPACING;
            y_current = 0;

            for (deferred_sink_nodes.items) |node_id| {
                const node = self.nodes.getPtr(node_id).?;
                node.x = x_current;
                node.y = y_current;
                node.z = @floatFromInt(99999 - node.node_id);
                y_current += node.computeNodeHeight() + types.H_NODE_SPACING;

                try completed.put(self.allocator, node_id, {});
            }
        }
    }

    /// Create a PipeWire link between an output port and an input port
    pub fn createLink(self: *PipewireHandle, out_node: u32, out_port: u32, inp_node: u32, inp_port: u32) void {
        var out_node_buf: [16]u8 = undefined;
        var out_port_buf: [16]u8 = undefined;
        var inp_node_buf: [16]u8 = undefined;
        var inp_port_buf: [16]u8 = undefined;

        const out_node_str = std.fmt.bufPrintZ(&out_node_buf, "{d}", .{out_node}) catch return;
        const out_port_str = std.fmt.bufPrintZ(&out_port_buf, "{d}", .{out_port}) catch return;
        const inp_node_str = std.fmt.bufPrintZ(&inp_node_buf, "{d}", .{inp_node}) catch return;
        const inp_port_str = std.fmt.bufPrintZ(&inp_port_buf, "{d}", .{inp_port}) catch return;

        const items = [_]c.spa_dict_item{
            .{ .key = c.PW_KEY_LINK_OUTPUT_NODE, .value = out_node_str.ptr },
            .{ .key = c.PW_KEY_LINK_OUTPUT_PORT, .value = out_port_str.ptr },
            .{ .key = c.PW_KEY_LINK_INPUT_NODE, .value = inp_node_str.ptr },
            .{ .key = c.PW_KEY_LINK_INPUT_PORT, .value = inp_port_str.ptr },
            .{ .key = c.PW_KEY_OBJECT_LINGER, .value = "true" },
        };

        const props = c.spa_dict{
            .flags = 0,
            .n_items = items.len,
            .items = &items,
        };

        _ = c.pw_core_create_object(
            self.core,
            "link-factory",
            c.PW_TYPE_INTERFACE_Link,
            c.PW_VERSION_LINK,
            &props,
            0,
        );
    }

    /// Returns file descriptor to underlying pipewire loop
    pub fn fd(self: *const PipewireHandle) i32 {
        return c.pw_loop_get_fd(self.loop);
    }

    /// Assign default positions to nodes that have no position yet.
    fn initNewNodes(self: *PipewireHandle) void {
        var max_y: f32 = 0;
        var node_it = self.nodes.iterator();
        while (node_it.next()) |entry| {
            if (entry.value_ptr.y) |y| {
                const bottom = y + entry.value_ptr.computeNodeHeight() + types.H_NODE_SPACING;
                if (bottom > max_y) max_y = bottom;
            }
        }

        node_it = self.nodes.iterator();
        while (node_it.next()) |entry| {
            const node = entry.value_ptr;
            if (node.x == null) node.x = 0;
            if (node.y == null) {
                node.y = max_y;
                max_y += node.computeNodeHeight() + types.H_NODE_SPACING;
            }
            if (node.z == null) node.z = @floatFromInt(99999 - node.node_id);
        }
    }

    /// Drain all events from the registry
    pub fn drain(self: *PipewireHandle, auto_layout: bool, atlas: types.FontAtlas) !void {
        try handleError(
            c.pw_loop_iterate(self.loop, 0),
        );

        if (self.latency_labels_dirty or self.nodes_dirty) {
            const advance = atlas.getGlyph('0').?.advance * types.PipewireNode.PORT_FONT_SIZE / atlas.parsed.value.metrics.emSize;
            for (self.nodes.values()) |*node| {
                var widths = [2]f32{ 0, 0 };
                inline for (.{ node.inps, node.outs }) |ports| {
                    for (ports.values()) |*port| {
                        port.updateLatencyText(node.clock);
                        inline for (0..2) |index| {
                            widths[index] = @max(widths[index], @as(f32, @floatFromInt(port.latencyText(index).len)) * advance);
                        }
                    }
                }
                const row_width = widths[0] + widths[1] + 2.0 * types.PipewireNode.PORT_COLUMN_GAP +
                    types.PipewireNode.PORT_NAME_WIDTH + 2.0 * (types.PipewireNode.W_PIN + 8.0);
                const has_inputs = node.inps.count() != 0;
                const has_outputs = node.outs.count() != 0;
                const node_width = @max(types.PipewireNode.W_NODE, if (has_inputs and has_outputs) 2.0 * row_width else if (has_inputs or has_outputs) row_width else 0);
                if (node.width != node_width) self.nodes_dirty = true;
                node.width = node_width;
                node.latency_widths = widths;
            }
            self.latency_labels_dirty = false;
        }

        if (self.nodes_dirty) {
            if (auto_layout) {
                try self.update_graph_metadata();
            }

            // Always ensure new nodes have positions (even if auto_layout
            // already ran — initNewNodes is a no-op for nodes with positions)
            self.initNewNodes();
            self.nodes_dirty = false;
        }
    }

    pub fn deinit(self: *PipewireHandle) void {
        var node_it = self.nodes.iterator();
        while (node_it.next()) |entry| {
            const node = entry.value_ptr;
            node.deinit(self.allocator);
        }

        for (self.port_listeners.items) |port_data| {
            port_data.deinit();
        }
        self.port_listeners.deinit(self.allocator);
        for (self.node_listeners.items) |node_data| node_data.deinit();
        self.node_listeners.deinit(self.allocator);

        self.nodes.deinit(self.allocator);
    }
};

test "port latency preserves every component and both directions independently" {
    const allocator = std.testing.allocator;
    var handle = PipewireHandle{ .allocator = allocator };
    defer handle.deinit();
    try handle.nodes.put(allocator, 1, .{
        .node_id = 1,
        .name = try allocator.dupe(u8, "node"),
        .mean_runtime_ns = null,
    });
    const node = handle.nodes.getPtr(1).?;
    try node.inps.put(allocator, 2, .{ .name = try allocator.dupe(u8, "first") });
    try node.inps.put(allocator, 3, .{ .name = try allocator.dupe(u8, "second") });
    var listener = PortListenerData{ .handle = &handle, .node_id = 1, .port_id = 2, .is_inp = true };

    // A real SPA Object pod: header followed by seven aligned properties.
    var words align(8) = [_]u32{
        176,                            c.SPA_TYPE_Object, c.SPA_TYPE_OBJECT_ParamLatency, c.SPA_PARAM_Latency,
        c.SPA_PARAM_LATENCY_direction,  0,                 4,                              c.SPA_TYPE_Id,
        c.SPA_DIRECTION_OUTPUT,         0,                 c.SPA_PARAM_LATENCY_minQuantum, 0,
        4,                              c.SPA_TYPE_Float,  @bitCast(@as(f32, 0.25)),       0,
        c.SPA_PARAM_LATENCY_maxQuantum, 0,                 4,                              c.SPA_TYPE_Float,
        @bitCast(@as(f32, 1.5)),        0,                 c.SPA_PARAM_LATENCY_minRate,    0,
        4,                              c.SPA_TYPE_Int,    17,                             0,
        c.SPA_PARAM_LATENCY_maxRate,    0,                 4,                              c.SPA_TYPE_Int,
        113,                            0,                 c.SPA_PARAM_LATENCY_minNs,      0,
        8,                              c.SPA_TYPE_Long,   1000,                           0,
        c.SPA_PARAM_LATENCY_maxNs,      0,                 8,                              c.SPA_TYPE_Long,
        2000,                           0,
    };
    const pod: *const c.spa_pod = @ptrCast(&words);
    PipewireHandle.PortEvents.onParam(&listener, 0, c.SPA_PARAM_Latency, 0, 0, pod);
    const expected = latency.Range{
        .min = .{ .quantum = 0.25, .frames = 17, .ns = 1000 },
        .max = .{ .quantum = 1.5, .frames = 113, .ns = 2000 },
    };
    try std.testing.expectEqualDeep(expected, node.inps.get(2).?.upstream.?);
    try std.testing.expect(node.inps.get(2).?.downstream == null);

    words[8] = c.SPA_DIRECTION_INPUT;
    words[26] = 51;
    PipewireHandle.PortEvents.onParam(&listener, 0, c.SPA_PARAM_Latency, 0, 0, pod);
    try std.testing.expectEqualDeep(expected, node.inps.get(2).?.upstream.?);
    try std.testing.expectEqual(@as(i64, 51), node.inps.get(2).?.downstream.?.min.frames);

    listener.port_id = 3;
    PipewireHandle.PortEvents.onParam(&listener, 0, c.SPA_PARAM_Latency, 0, 0, pod);
    try std.testing.expect(node.inps.get(3).?.upstream == null);
    try std.testing.expectEqualDeep(expected, node.inps.get(2).?.upstream.?);
    PipewireHandle.PortEvents.onParam(&listener, 0, c.SPA_PARAM_Latency, 0, 0, null);
    try std.testing.expect(node.inps.get(3).?.downstream == null);
    try std.testing.expect(node.inps.get(2).?.downstream != null);

    listener.port_id = 2;
    words[1] = c.SPA_TYPE_Int; // A non-object must not be reinterpreted as properties.
    PipewireHandle.PortEvents.onParam(&listener, 0, c.SPA_PARAM_Latency, 0, 0, pod);
    try std.testing.expectEqualDeep(expected, node.inps.get(2).?.upstream.?);
}

test "stopping a node invalidates the clock until fresh profiler data arrives" {
    const allocator = std.testing.allocator;
    var handle = PipewireHandle{ .allocator = allocator };
    defer handle.deinit();
    try handle.nodes.put(allocator, 1, .{
        .node_id = 1,
        .name = try allocator.dupe(u8, "node"),
        .mean_runtime_ns = null,
        .running = true,
        .clock = .{ .rate_num = 1, .rate_denom = 48000, .quantum = 192 },
    });
    var listener = NodeListenerData{ .handle = &handle, .node_id = 1 };
    var info = std.mem.zeroes(c.pw_node_info);
    info.change_mask = c.PW_NODE_CHANGE_MASK_STATE;
    info.state = c.PW_NODE_STATE_IDLE;
    PipewireHandle.NodeEvents.onInfo(&listener, &info);
    try std.testing.expect(handle.nodes.get(1).?.clock == null);
    try std.testing.expect(!handle.nodes.get(1).?.running);
    info.state = c.PW_NODE_STATE_RUNNING;
    PipewireHandle.NodeEvents.onInfo(&listener, &info);
    try std.testing.expect(handle.nodes.get(1).?.running);
    try std.testing.expect(handle.nodes.get(1).?.clock == null);
}
