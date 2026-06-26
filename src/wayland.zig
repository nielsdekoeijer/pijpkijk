const c = @import("c.zig").c;
const std = @import("std");
const handleError = @import("error.zig").handleError;

const KeyState = enum {
    PRESSED,
    RELEASED,
    REPEATED,
};

pub const WaylandHandle = struct {
    pub const Core = struct {
        display: *c.struct_wl_display = undefined,
        registry: *c.struct_wl_registry = undefined,
        xkb_context: *c.struct_xkb_context = undefined,
    };

    pub const State = struct {
        width: u32 = 800,
        height: u32 = 600,
        should_close: bool = false,
        frame_ready: bool = true,

        input: struct {
            key_escape: ?KeyState = null,
            key_w: ?KeyState = null,
            key_a: ?KeyState = null,
            key_s: ?KeyState = null,
            key_d: ?KeyState = null,
            key_q: ?KeyState = null,
            key_r: ?KeyState = null,
            key_delete: ?KeyState = null,

            mouse_x: ?f32 = null,
            mouse_y: ?f32 = null,
            mouse_dx: f32 = 0,
            mouse_dy: f32 = 0,
            scroll_y: f32 = 0,
            mouse_down_l: bool = false,
            mouse_down_r: bool = false,
        } = .{},
    };

    pub const FrameCallback = struct {
        fn onDone(data: ?*anyopaque, callback: ?*c.struct_wl_callback, time: u32) callconv(.c) void {
            _ = time;
            const handle: *WaylandHandle = @ptrCast(@alignCast(data));

            if (callback) |cb| {
                c.wl_callback_destroy(cb);
            }

            handle.state.frame_ready = true;
        }

        pub const listener = c.struct_wl_callback_listener{
            .done = onDone,
        };
    };

    pub const RegistrySurface = struct {
        configured: bool = false,

        surface: ?*c.struct_wl_surface = null,
        xdg_surface: ?*c.struct_xdg_surface = null,

        // The compositor informing us that it is ready for us by providing us a serial number
        fn onConfigure(
            data: ?*anyopaque,
            xdg_surface: ?*c.struct_xdg_surface,
            serial: u32,
        ) callconv(.c) void {
            const handle: *WaylandHandle = @ptrCast(@alignCast(data));

            std.log.info("Trying to configure surface...", .{});

            c.xdg_surface_ack_configure(xdg_surface, serial);
            handle.registry_surface.configured = true;

            defer std.log.info("Trying to configure surface OK", .{});
        }

        const listener = c.struct_xdg_surface_listener{
            .configure = onConfigure,
        };
    };

    pub const RegistryTopLevel = struct {
        xdg_toplevel: ?*c.struct_xdg_toplevel = null,

        /// Compositor configures us telling us the width and height of the window
        fn onConfigure(
            data: ?*anyopaque,
            xdg_toplevel: ?*c.struct_xdg_toplevel,
            width: i32,
            height: i32,
            states: [*c]c.struct_wl_array,
        ) callconv(.c) void {
            const handle: *WaylandHandle = @ptrCast(@alignCast(data));

            std.log.info("Trying to configure toplevel...", .{});

            if (width != 0 and height != 0) {
                handle.state.width = @intCast(width);
                handle.state.height = @intCast(height);
            }
            std.log.info("Configuring with ({}, {})", .{ width, height });

            _ = xdg_toplevel;
            _ = states;

            std.log.info("Trying to configure toplevel OK", .{});
        }

        /// Compositor requesting us to close
        fn onClose(data: ?*anyopaque, xdg_toplevel: ?*c.struct_xdg_toplevel) callconv(.c) void {
            const handle: *WaylandHandle = @ptrCast(@alignCast(data));

            std.log.info("Trying to schedule close...", .{});

            handle.state.should_close = true;
            _ = xdg_toplevel;

            std.log.info("Trying to schedule close OK", .{});
        }

        /// Compositor tells us bounds (max size) of the window
        fn onConfigureBounds(
            data: ?*anyopaque,
            xdg_toplevel: ?*c.struct_xdg_toplevel,
            width: i32,
            height: i32,
        ) callconv(.c) void {
            _ = data;
            _ = xdg_toplevel;
            _ = width;
            _ = height;
        }

        /// Compositor advertises the capabilities it supports
        fn onWmCapabilities(
            data: ?*anyopaque,
            xdg_toplevel: ?*c.struct_xdg_toplevel,
            capabilities: [*c]c.struct_wl_array,
        ) callconv(.c) void {
            _ = data;
            _ = xdg_toplevel;
            _ = capabilities;
        }

        const listener = c.struct_xdg_toplevel_listener{
            .configure = WaylandHandle.RegistryTopLevel.onConfigure,
            .close = WaylandHandle.RegistryTopLevel.onClose,
            .configure_bounds = WaylandHandle.RegistryTopLevel.onConfigureBounds,
            .wm_capabilities = WaylandHandle.RegistryTopLevel.onWmCapabilities,
        };
    };

    pub const RegistryGlobal = struct {
        seat: ?*c.struct_wl_seat = null,
        compositor: ?*c.struct_wl_compositor = null,
        wm_base: ?*c.struct_xdg_wm_base = null,

        /// We get told what global objects exist
        fn onRegistryGlobal(
            data: ?*anyopaque,
            registry: ?*c.struct_wl_registry,
            id: u32,
            interface: [*c]const u8,
            version: u32,
        ) callconv(.c) void {
            const handle: *WaylandHandle = @ptrCast(@alignCast(data));

            errdefer {
                std.log.err("Trying to handle global registry callback failed", .{});
                @panic("Unrecoverable");
            }

            _ = version;

            const iface = std.mem.span(interface);

            if (std.mem.eql(u8, iface, "wl_compositor")) {
                handle.registry_global.compositor = @ptrCast(c.wl_registry_bind(registry, id, &c.wl_compositor_interface, 1));
                if (handle.registry_global.compositor == null) {
                    std.log.err("Failed to bind interface '{s}' to registry", .{iface});
                    return error.WaylandError;
                }

                std.log.info("Bound interface '{s}' to registry", .{iface});
            } else if (std.mem.eql(u8, iface, "xdg_wm_base")) {
                handle.registry_global.wm_base = @ptrCast(c.wl_registry_bind(registry, id, &c.xdg_wm_base_interface, 1));
                if (handle.registry_global.wm_base == null) {
                    std.log.err("Failed to bind interface '{s}' to registry", .{iface});
                    return error.WaylandError;
                }

                try handleError(
                    c.xdg_wm_base_add_listener(handle.registry_global.wm_base, &WaylandHandle.RegistryWmBase.listener, handle),
                );

                std.log.info("Bound interface '{s}' to registry", .{iface});
            } else if (std.mem.eql(u8, iface, "wl_seat")) {
                handle.registry_global.seat = @ptrCast(c.wl_registry_bind(registry, id, &c.wl_seat_interface, 1));
                if (handle.registry_global.seat == null) {
                    std.log.err("Failed to bind interface '{s}' to registry", .{iface});
                    return error.WaylandError;
                }

                try handleError(
                    c.wl_seat_add_listener(handle.registry_global.seat, &WaylandHandle.RegistrySeat.listener, handle),
                );

                std.log.info("Bound interface '{s}' to registry", .{iface});
            }

            return;
        }

        /// If a global object disappears (like a monitor unplugging)
        fn onRegistryGlobalRemove(
            data: ?*anyopaque,
            registry: ?*c.struct_wl_registry,
            id: u32,
        ) callconv(.c) void {
            const handle: *WaylandHandle = @ptrCast(@alignCast(data));

            _ = handle;
            _ = registry;
            _ = id;
        }

        const listener = c.struct_wl_registry_listener{
            .global = WaylandHandle.RegistryGlobal.onRegistryGlobal,
            .global_remove = WaylandHandle.RegistryGlobal.onRegistryGlobalRemove,
        };
    };

    pub const RegistrySeat = struct {
        pointer: ?*c.struct_wl_pointer = null,
        keyboard: ?*c.struct_wl_keyboard = null,

        /// We are told what input devices are availible
        fn onSeatCapabilities(
            data: ?*anyopaque,
            seat: ?*c.struct_wl_seat,
            capabilities: u32,
        ) callconv(.c) void {
            const handle: *WaylandHandle = @ptrCast(@alignCast(data));

            errdefer {
                std.log.err("Trying to handle global registry callback failed", .{});
                @panic("Unrecoverable");
            }

            errdefer std.log.err("Trying to handle seat registry callback failure", .{});

            if ((capabilities & c.WL_SEAT_CAPABILITY_POINTER) != 0 and handle.registry_seat.pointer == null) {
                std.log.info("Found pointer", .{});
                handle.registry_seat.pointer = c.wl_seat_get_pointer(seat);
                try handleError(
                    c.wl_pointer_add_listener(handle.registry_seat.pointer, &RegistryPointer.listener, handle),
                );
            }

            if ((capabilities & c.WL_SEAT_CAPABILITY_KEYBOARD) != 0 and handle.registry_seat.keyboard == null) {
                std.log.info("Found keyboard", .{});
                handle.registry_seat.keyboard = c.wl_seat_get_keyboard(seat);
                try handleError(
                    c.wl_keyboard_add_listener(handle.registry_seat.keyboard, &RegistryKeyboard.listener, handle),
                );
            }
        }

        /// Human readable name of the seat
        fn onSeatName(
            data: ?*anyopaque,
            seat: ?*c.struct_wl_seat,
            name: [*c]const u8,
        ) callconv(.c) void {
            _ = data;
            _ = seat;

            std.log.info("Received seat name '{s}'", .{name});
        }

        const listener = c.struct_wl_seat_listener{
            .capabilities = WaylandHandle.RegistrySeat.onSeatCapabilities,
            .name = WaylandHandle.RegistrySeat.onSeatName,
        };
    };

    pub const RegistryPointer = struct {
        /// When the mouse enters the window
        fn onEnter(
            data: ?*anyopaque,
            pointer: ?*c.struct_wl_pointer,
            serial: u32,
            surface: ?*c.struct_wl_surface,
            surface_x: c.wl_fixed_t,
            surface_y: c.wl_fixed_t,
        ) callconv(.c) void {
            _ = data;
            _ = pointer;
            _ = serial;
            _ = surface;
            _ = surface_x;
            _ = surface_y;
        }

        /// When the mouse enters the window
        fn onLeave(
            data: ?*anyopaque,
            pointer: ?*c.struct_wl_pointer,
            serial: u32,
            surface: ?*c.struct_wl_surface,
        ) callconv(.c) void {
            _ = data;
            _ = pointer;
            _ = serial;
            _ = surface;
        }

        /// When the mouse moves
        fn onMotion(
            data: ?*anyopaque,
            pointer: ?*c.struct_wl_pointer,
            time: u32,
            surface_x: c.wl_fixed_t,
            surface_y: c.wl_fixed_t,
        ) callconv(.c) void {
            _ = time;
            _ = pointer;

            const handle: *WaylandHandle = @ptrCast(@alignCast(data));
            const x = @as(f32, @floatCast(c.wl_fixed_to_double(surface_x)));
            const y = @as(f32, @floatCast(c.wl_fixed_to_double(surface_y)));

            // FIX: Accumulate the deltas using += instead of =
            if (handle.state.input.mouse_x) |mx| handle.state.input.mouse_dx += x - mx;
            if (handle.state.input.mouse_y) |my| handle.state.input.mouse_dy += y - my;

            handle.state.input.mouse_x = x;
            handle.state.input.mouse_y = y;
        }

        /// When the mouse is clicked
        fn onButton(
            data: ?*anyopaque,
            pointer: ?*c.struct_wl_pointer,
            serial: u32,
            time: u32,
            button: u32,
            state: u32,
        ) callconv(.c) void {
            _ = pointer;
            _ = serial;
            _ = time;

            const handle: *WaylandHandle = @ptrCast(@alignCast(data));

            // 272 is BTN_LEFT, 273 is BTN_RIGHT
            switch (button) {
                272 => {
                    handle.state.input.mouse_down_l =
                        (state == c.WL_POINTER_BUTTON_STATE_PRESSED);

                    if (handle.state.input.mouse_down_l) {
                        std.log.debug("Registered 'MOUSE_BUTTON_L' button press", .{});
                    }
                },
                273 => {
                    handle.state.input.mouse_down_r =
                        (state == c.WL_POINTER_BUTTON_STATE_PRESSED);

                    if (handle.state.input.mouse_down_r) {
                        std.log.debug("Registered 'MOUSE_BUTTON_R' button press", .{});
                    }
                },
                else => std.log.warn("Unsupported button press with code '{}'", .{button}),
            }
        }

        /// On mouse scroll
        fn onAxis(
            data: ?*anyopaque,
            pointer: ?*c.struct_wl_pointer,
            time: u32,
            axis: u32,
            value: c.wl_fixed_t,
        ) callconv(.c) void {
            _ = pointer;
            _ = time;
            const handle: *WaylandHandle = @ptrCast(@alignCast(data));

            if (axis == c.WL_POINTER_AXIS_VERTICAL_SCROLL) {
                handle.state.input.scroll_y += @as(f32, @floatCast(c.wl_fixed_to_double(value)));
                std.log.debug("Registered 'SCROLL' with value {}", .{value});
            }
        }

        /// Grouped events
        fn onFrame(
            data: ?*anyopaque,
            pointer: ?*c.struct_wl_pointer,
        ) callconv(.c) void {
            _ = data;
            _ = pointer;
        }

        /// Can be ignored
        fn onAxisSource(
            data: ?*anyopaque,
            pointer: ?*c.struct_wl_pointer,
            axis_source: u32,
        ) callconv(.c) void {
            _ = data;
            _ = pointer;
            _ = axis_source;
        }

        /// Can be ignored
        fn onAxisStop(
            data: ?*anyopaque,
            pointer: ?*c.struct_wl_pointer,
            time: u32,
            axis: u32,
        ) callconv(.c) void {
            _ = data;
            _ = pointer;
            _ = time;
            _ = axis;
        }

        /// Can be ignored
        fn onAxisDiscrete(
            data: ?*anyopaque,
            pointer: ?*c.struct_wl_pointer,
            axis: u32,
            discrete: i32,
        ) callconv(.c) void {
            _ = data;
            _ = pointer;
            _ = axis;
            _ = discrete;
        }

        /// Can be ignored
        fn onAxisValue120(
            data: ?*anyopaque,
            pointer: ?*c.struct_wl_pointer,
            axis: u32,
            value120: i32,
        ) callconv(.c) void {
            _ = data;
            _ = pointer;
            _ = axis;
            _ = value120;
        }

        /// Can be ignored
        fn onAxisRelativeDirection(
            data: ?*anyopaque,
            pointer: ?*c.struct_wl_pointer,
            axis: u32,
            direction: u32,
        ) callconv(.c) void {
            _ = data;
            _ = pointer;
            _ = axis;
            _ = direction;
        }

        const listener = c.struct_wl_pointer_listener{
            .enter = WaylandHandle.RegistryPointer.onEnter,
            .leave = WaylandHandle.RegistryPointer.onLeave,
            .motion = WaylandHandle.RegistryPointer.onMotion,
            .button = WaylandHandle.RegistryPointer.onButton,
            .axis = WaylandHandle.RegistryPointer.onAxis,
            .frame = WaylandHandle.RegistryPointer.onFrame,
            .axis_source = WaylandHandle.RegistryPointer.onAxisSource,
            .axis_stop = WaylandHandle.RegistryPointer.onAxisStop,
            .axis_discrete = WaylandHandle.RegistryPointer.onAxisDiscrete,
            .axis_value120 = WaylandHandle.RegistryPointer.onAxisValue120,
            .axis_relative_direction = WaylandHandle.RegistryPointer.onAxisRelativeDirection,
        };
    };

    pub const RegistryKeyboard = struct {
        xkb_keymap: ?*c.struct_xkb_keymap = null,
        xkb_state: ?*c.struct_xkb_state = null,

        /// Compositor gives us a fd to read the system keyboard layout, thereby configuring libxkbcommon
        fn onKeymap(
            data: ?*anyopaque,
            keyboard: ?*c.struct_wl_keyboard,
            format: u32,
            fd: i32,
            size: u32,
        ) callconv(.c) void {
            _ = keyboard;

            std.log.info("Trying to handle new keymapping...", .{});

            const handle: *WaylandHandle = @ptrCast(@alignCast(data));
            defer _ = c.close(fd);

            if (format != c.WL_KEYBOARD_KEYMAP_FORMAT_XKB_V1) {
                return;
            }

            const map_ptr = c.mmap(null, size, c.PROT_READ, c.MAP_PRIVATE, fd, 0);
            if (map_ptr == c.MAP_FAILED) @panic("Could not mmap keymap fd");
            defer _ = c.munmap(map_ptr, size);

            if (handle.registry_keyboard.xkb_state) |s| c.xkb_state_unref(s);
            if (handle.registry_keyboard.xkb_keymap) |s| c.xkb_keymap_unref(s);

            handle.registry_keyboard.xkb_keymap = c.xkb_keymap_new_from_string(
                handle.core.xkb_context,
                @ptrCast(map_ptr),
                c.XKB_KEYMAP_FORMAT_TEXT_V1,
                c.XKB_KEYMAP_COMPILE_NO_FLAGS,
            );

            handle.registry_keyboard.xkb_state = c.xkb_state_new(handle.registry_keyboard.xkb_keymap);

            defer std.log.info("Trying to handle new keymapping OK", .{});
        }

        /// On app gaining keyboard focus
        fn onEnter(
            data: ?*anyopaque,
            keyboard: ?*c.struct_wl_keyboard,
            serial: u32,
            surface: ?*c.struct_wl_surface,
            keys: [*c]c.struct_wl_array,
        ) callconv(.c) void {
            _ = data;
            _ = keyboard;
            _ = serial;
            _ = surface;
            _ = keys;
        }

        /// On app losing keyboard focus
        fn onLeave(
            data: ?*anyopaque,
            keyboard: ?*c.struct_wl_keyboard,
            serial: u32,
            surface: ?*c.struct_wl_surface,
        ) callconv(.c) void {
            _ = data;
            _ = keyboard;
            _ = serial;
            _ = surface;
        }

        /// On key press
        fn onKey(
            data: ?*anyopaque,
            keyboard: ?*c.struct_wl_keyboard,
            serial: u32,
            time: u32,
            key: u32,
            state_val: u32,
        ) callconv(.c) void {
            _ = keyboard;
            _ = serial;
            _ = time;

            const handle: *WaylandHandle = @ptrCast(@alignCast(data));

            if (handle.registry_keyboard.xkb_state) |xkb_state| {
                const keysym = c.xkb_state_key_get_one_sym(xkb_state, key + 8);

                const val = switch (state_val) {
                    c.WL_KEYBOARD_KEY_STATE_PRESSED => KeyState.PRESSED,
                    c.WL_KEYBOARD_KEY_STATE_RELEASED => KeyState.RELEASED,
                    c.WL_KEYBOARD_KEY_STATE_REPEATED => KeyState.REPEATED,
                    else => unreachable,
                };

                switch (keysym) {
                    c.XKB_KEY_Escape => handle.state.input.key_escape = val,
                    c.XKB_KEY_w => handle.state.input.key_w = val,
                    c.XKB_KEY_a => handle.state.input.key_a = val,
                    c.XKB_KEY_s => handle.state.input.key_s = val,
                    c.XKB_KEY_d => handle.state.input.key_d = val,
                    c.XKB_KEY_q => handle.state.input.key_q = val,
                    c.XKB_KEY_r => handle.state.input.key_r = val,
                    c.XKB_KEY_Delete => handle.state.input.key_delete = val,
                    else => {},
                }
            }

            std.log.debug("Key activity handled", .{});
        }

        /// On shift, etc.
        fn onModifiers(
            data: ?*anyopaque,
            keyboard: ?*c.struct_wl_keyboard,
            serial: u32,
            mods_depressed: u32,
            mods_latched: u32,
            mods_locked: u32,
            group: u32,
        ) callconv(.c) void {
            _ = keyboard;
            _ = serial;

            const handle: *WaylandHandle = @ptrCast(@alignCast(data));

            if (handle.registry_keyboard.xkb_state) |st| {
                _ = c.xkb_state_update_mask(st, mods_depressed, mods_latched, mods_locked, 0, 0, group);
            }

            defer std.log.debug("Handled modifier press", .{});
        }

        /// How the OS is handling repeats
        fn onRepeatInfo(
            data: ?*anyopaque,
            keyboard: ?*c.struct_wl_keyboard,
            rate: i32,
            delay: i32,
        ) callconv(.c) void {
            _ = data;
            _ = keyboard;
            _ = rate;
            _ = delay;
        }

        const listener = c.struct_wl_keyboard_listener{
            .keymap = WaylandHandle.RegistryKeyboard.onKeymap,
            .enter = WaylandHandle.RegistryKeyboard.onEnter,
            .leave = WaylandHandle.RegistryKeyboard.onLeave,
            .key = WaylandHandle.RegistryKeyboard.onKey,
            .modifiers = WaylandHandle.RegistryKeyboard.onModifiers,
            .repeat_info = WaylandHandle.RegistryKeyboard.onRepeatInfo,
        };
    };

    pub const RegistryWmBase = struct {
        // Wayland checking if our app is responsive
        fn OnPing(data: ?*anyopaque, wm_base: ?*c.struct_xdg_wm_base, serial: u32) callconv(.c) void {
            _ = data;

            std.log.debug("Sending wayland pong...", .{});
            c.xdg_wm_base_pong(wm_base, serial);
        }

        const listener = c.struct_xdg_wm_base_listener{
            .ping = WaylandHandle.RegistryWmBase.OnPing,
        };
    };

    core: Core = .{},
    state: State = .{},
    registry_global: RegistryGlobal = .{},
    registry_seat: RegistrySeat = .{},
    registry_wm_base: RegistryWmBase = .{},
    registry_keyboard: RegistryKeyboard = .{},
    registry_pointer: RegistryPointer = .{},
    registry_surface: RegistrySurface = .{},
    registry_top_level: RegistryTopLevel = .{},

    pub fn init(self: *WaylandHandle) !void {
        std.log.info("Trying to init wayland handle...", .{});
        errdefer std.log.err("Trying to init wayland handle failed", .{});

        self.* = WaylandHandle{};

        self.core.display = try handleError(
            c.wl_display_connect(null),
        );

        self.core.registry = try handleError(
            c.wl_display_get_registry(self.core.display),
        );

        self.core.xkb_context = try handleError(
            c.xkb_context_new(c.XKB_CONTEXT_NO_FLAGS),
        );

        defer std.log.info("Trying to init wayland handle OK", .{});
    }

    pub fn flush_blocking(self: WaylandHandle) !void {
        std.log.info("Trying to perform blocking flush...", .{});
        errdefer std.log.err("Trying to perform blocking flush failed", .{});

        try handleError(c.wl_display_roundtrip(self.core.display));

        defer std.log.info("Trying to perform blocking flush OK", .{});
    }

    pub fn start_core(self: *WaylandHandle) !void {
        std.log.info("Trying to start wayland core...", .{});
        errdefer std.log.err("Trying to start wayland core failed", .{});

        try handleError(
            c.wl_registry_add_listener(self.core.registry, &WaylandHandle.RegistryGlobal.listener, self),
        );

        defer std.log.info("Trying to start wayland core OK", .{});
    }

    pub fn core_ready(self: WaylandHandle) bool {
        if (self.registry_global.seat == null) {
            return false;
        }

        if (self.registry_global.compositor == null) {
            return false;
        }

        if (self.registry_global.wm_base == null) {
            return false;
        }

        return true;
    }

    pub fn seat_ready(self: WaylandHandle) bool {
        if (self.registry_seat.pointer == null) {
            return false;
        }

        if (self.registry_seat.keyboard == null) {
            return false;
        }

        return true;
    }

    pub fn start_surface(self: *WaylandHandle) !void {
        std.log.info("Trying to start wayland surfaces...", .{});

        if (!self.core_ready()) {
            std.log.err("Failed to create surface as handle wasn't ready", .{});
            return error.WaylandError;
        }

        self.registry_surface.surface = try handleError(
            c.wl_compositor_create_surface(self.registry_global.compositor),
        );

        self.registry_surface.xdg_surface = try handleError(
            c.xdg_wm_base_get_xdg_surface(self.registry_global.wm_base, self.registry_surface.surface),
        );

        try handleError(
            c.xdg_surface_add_listener(self.registry_surface.xdg_surface, &WaylandHandle.RegistrySurface.listener, self),
        );

        self.registry_top_level.xdg_toplevel = try handleError(
            c.xdg_surface_get_toplevel(self.registry_surface.xdg_surface),
        );

        try handleError(
            c.xdg_toplevel_add_listener(self.registry_top_level.xdg_toplevel, &WaylandHandle.RegistryTopLevel.listener, self),
        );

        c.xdg_toplevel_set_title(self.registry_top_level.xdg_toplevel, "pijpkijk");
        c.wl_surface_commit(self.registry_surface.surface);

        std.log.info("Trying to start wayland surfaces OK", .{});
    }

    pub fn surface_ready(self: WaylandHandle) bool {
        return self.registry_surface.configured;
    }

    pub fn request_frame_callback(self: *WaylandHandle) void {
        const cb = c.wl_surface_frame(self.registry_surface.surface.?);
        _ = c.wl_callback_add_listener(cb, &FrameCallback.listener, self);
        self.state.frame_ready = false;
    }

    pub fn deinit(self: *WaylandHandle) void {
        if (self.registry_keyboard.xkb_state) |s| c.xkb_state_unref(s);
        if (self.registry_keyboard.xkb_keymap) |s| c.xkb_keymap_unref(s);
        c.xkb_context_unref(self.core.xkb_context);

        if (self.registry_seat.keyboard) |s| c.wl_keyboard_destroy(s);
        if (self.registry_seat.pointer) |s| c.wl_pointer_destroy(s);
        if (self.registry_global.seat) |s| c.wl_seat_destroy(s);
        if (self.registry_top_level.xdg_toplevel) |s| c.xdg_toplevel_destroy(s);
        if (self.registry_surface.xdg_surface) |s| c.xdg_surface_destroy(s);
        if (self.registry_surface.surface) |s| c.wl_surface_destroy(s);
        if (self.registry_global.wm_base) |s| c.xdg_wm_base_destroy(s);
        if (self.registry_global.compositor) |s| c.wl_compositor_destroy(s);

        c.wl_registry_destroy(self.core.registry);
        c.wl_display_disconnect(self.core.display);

        std.log.info("Deinit WaylandHandle OK", .{});
    }
};
