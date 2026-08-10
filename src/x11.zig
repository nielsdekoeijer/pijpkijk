const c = @import("c.zig").c;
const xcb_c = @import("c.zig").xcb;
const std = @import("std");
const handleError = @import("error.zig").handleError;

const KeyState = enum {
    PRESSED,
    RELEASED,
    REPEATED,
};

pub const X11Handle = struct {
    pub const State = struct {
        width: u32 = 800,
        height: u32 = 600,
        should_close: bool = false,
        frame_ready: bool = true,
        /// Fractional scale factor as numerator with denominator 120 (120 = 1.0x)
        /// X11 doesn't support fractional scaling, so this stays at 120
        fractional_scale: u32 = 120,

        input: struct {
            key_escape: ?KeyState = null,
            key_w: ?KeyState = null,
            key_a: ?KeyState = null,
            key_s: ?KeyState = null,
            key_d: ?KeyState = null,
            key_q: ?KeyState = null,
            key_r: ?KeyState = null,
            key_delete: ?KeyState = null,
            key_question: ?KeyState = null,
            key_slash: ?KeyState = null,
            key_h: ?KeyState = null,
            key_return: ?KeyState = null,
            key_up: ?KeyState = null,
            key_down: ?KeyState = null,
            key_backspace: ?KeyState = null,
            key_greater: ?KeyState = null,
            key_less: ?KeyState = null,
            typed_codepoint: ?u21 = null,

            mouse_x: ?f32 = null,
            mouse_y: ?f32 = null,
            mouse_dx: f32 = 0,
            mouse_dy: f32 = 0,
            scroll_x: f32 = 0,
            scroll_y: f32 = 0,
            scroll_is_finger: bool = false,
            pinch_scale: f32 = 0,
            mouse_down_l: bool = false,
            mouse_down_r: bool = false,
            shift_held: bool = false,
        } = .{},
    };

    connection: *xcb_c.xcb_connection_t,
    screen: *xcb_c.xcb_screen_t,
    window: xcb_c.xcb_window_t,
    wm_delete_window: xcb_c.xcb_atom_t,
    xkb_context: *xcb_c.struct_xkb_context,
    xkb_keymap: ?*xcb_c.struct_xkb_keymap = null,
    xkb_state_obj: ?*xcb_c.struct_xkb_state = null,
    core_device_id: i32 = 0,
    state: State = .{},
    /// Snapshot of App.scale for pinch gesture base reference
    scale_snapshot: f32 = 1.0,

    pub fn init(self: *X11Handle) !void {
        std.log.info("Trying to init X11 handle...", .{});
        errdefer std.log.err("Trying to init X11 handle failed", .{});

        self.* = X11Handle{
            .connection = undefined,
            .screen = undefined,
            .window = undefined,
            .wm_delete_window = undefined,
            .xkb_context = undefined,
        };

        // Connect to X server
        var screen_num: c_int = 0;
        const conn = xcb_c.xcb_connect(null, &screen_num) orelse return error.X11ConnectionFailed;
        if (xcb_c.xcb_connection_has_error(conn) != 0) {
            return error.X11ConnectionFailed;
        }
        self.connection = conn;

        // Get the screen
        const setup = xcb_c.xcb_get_setup(conn);
        var iter = xcb_c.xcb_setup_roots_iterator(setup);
        var i: c_int = 0;
        while (i < screen_num) : (i += 1) {
            xcb_c.xcb_screen_next(&iter);
        }
        self.screen = iter.data;

        // Initialize XKB extension
        var xkb_base_event: u8 = 0;
        var xkb_base_error: u8 = 0;
        const xkb_ret = xcb_c.xkb_x11_setup_xkb_extension(
            conn,
            xcb_c.XKB_X11_MIN_MAJOR_XKB_VERSION,
            xcb_c.XKB_X11_MIN_MINOR_XKB_VERSION,
            xcb_c.XKB_X11_SETUP_XKB_EXTENSION_NO_FLAGS,
            null,
            null,
            &xkb_base_event,
            &xkb_base_error,
        );
        if (xkb_ret == 0) {
            return error.X11XkbSetupFailed;
        }

        // Select XKB events (state notify for modifier tracking)
        const required_map_parts: u16 =
            xcb_c.XCB_XKB_MAP_PART_KEY_TYPES |
            xcb_c.XCB_XKB_MAP_PART_KEY_SYMS |
            xcb_c.XCB_XKB_MAP_PART_MODIFIER_MAP |
            xcb_c.XCB_XKB_MAP_PART_EXPLICIT_COMPONENTS |
            xcb_c.XCB_XKB_MAP_PART_KEY_ACTIONS |
            xcb_c.XCB_XKB_MAP_PART_VIRTUAL_MODS |
            xcb_c.XCB_XKB_MAP_PART_VIRTUAL_MOD_MAP;

        const required_events: u16 =
            xcb_c.XCB_XKB_EVENT_TYPE_NEW_KEYBOARD_NOTIFY |
            xcb_c.XCB_XKB_EVENT_TYPE_MAP_NOTIFY |
            xcb_c.XCB_XKB_EVENT_TYPE_STATE_NOTIFY;

        const details = xcb_c.xcb_xkb_select_events_details_t{
            .affectNewKeyboard = required_map_parts,
            .newKeyboardDetails = required_map_parts,
            .affectState = xcb_c.XCB_XKB_STATE_PART_MODIFIER_BASE |
                xcb_c.XCB_XKB_STATE_PART_MODIFIER_LATCH |
                xcb_c.XCB_XKB_STATE_PART_MODIFIER_LOCK |
                xcb_c.XCB_XKB_STATE_PART_GROUP_BASE |
                xcb_c.XCB_XKB_STATE_PART_GROUP_LATCH |
                xcb_c.XCB_XKB_STATE_PART_GROUP_LOCK,
            .stateDetails = xcb_c.XCB_XKB_STATE_PART_MODIFIER_BASE |
                xcb_c.XCB_XKB_STATE_PART_MODIFIER_LATCH |
                xcb_c.XCB_XKB_STATE_PART_MODIFIER_LOCK |
                xcb_c.XCB_XKB_STATE_PART_GROUP_BASE |
                xcb_c.XCB_XKB_STATE_PART_GROUP_LATCH |
                xcb_c.XCB_XKB_STATE_PART_GROUP_LOCK,
        };

        _ = xcb_c.xcb_xkb_select_events_aux_checked(
            conn,
            xcb_c.XCB_XKB_ID_USE_CORE_KBD,
            required_events,
            0,
            0,
            required_map_parts,
            required_map_parts,
            &details,
        );

        // Create XKB context
        self.xkb_context = xcb_c.xkb_context_new(xcb_c.XKB_CONTEXT_NO_FLAGS) orelse return error.X11XkbContextFailed;

        // Get core keyboard device ID
        self.core_device_id = xcb_c.xkb_x11_get_core_keyboard_device_id(conn);
        if (self.core_device_id == -1) {
            return error.X11XkbDeviceFailed;
        }

        // Create keymap and state from X11
        self.xkb_keymap = xcb_c.xkb_x11_keymap_new_from_device(
            self.xkb_context,
            conn,
            self.core_device_id,
            xcb_c.XKB_KEYMAP_COMPILE_NO_FLAGS,
        );
        if (self.xkb_keymap == null) {
            return error.X11XkbKeymapFailed;
        }

        self.xkb_state_obj = xcb_c.xkb_x11_state_new_from_device(
            self.xkb_keymap,
            conn,
            self.core_device_id,
        );
        if (self.xkb_state_obj == null) {
            return error.X11XkbStateFailed;
        }

        std.log.info("Trying to init X11 handle OK", .{});
    }

    pub fn flush_blocking(self: X11Handle) !void {
        _ = xcb_c.xcb_flush(self.connection);
        // X11 doesn't have a roundtrip equivalent, but we can poll for events
        while (true) {
            const event = xcb_c.xcb_poll_for_event(self.connection);
            if (event == null) break;
            std.c.free(event);
        }
    }

    pub fn start_core(self: *X11Handle) !void {
        _ = self;
        // X11 connection already established in init
    }

    pub fn core_ready(self: X11Handle) bool {
        _ = self;
        return true; // X11 is ready immediately after connect
    }

    pub fn seat_ready(self: X11Handle) bool {
        _ = self;
        return true; // X11 input is ready immediately
    }

    pub fn start_surface(self: *X11Handle) !void {
        // Create the window
        self.window = xcb_c.xcb_generate_id(self.connection);

        const event_mask: u32 =
            xcb_c.XCB_EVENT_MASK_EXPOSURE |
            xcb_c.XCB_EVENT_MASK_STRUCTURE_NOTIFY |
            xcb_c.XCB_EVENT_MASK_KEY_PRESS |
            xcb_c.XCB_EVENT_MASK_KEY_RELEASE |
            xcb_c.XCB_EVENT_MASK_BUTTON_PRESS |
            xcb_c.XCB_EVENT_MASK_BUTTON_RELEASE |
            xcb_c.XCB_EVENT_MASK_POINTER_MOTION;

        _ = xcb_c.xcb_create_window(
            self.connection,
            xcb_c.XCB_COPY_FROM_PARENT,
            self.window,
            self.screen.root,
            0,
            0,
            @intCast(self.state.width),
            @intCast(self.state.height),
            0,
            xcb_c.XCB_WINDOW_CLASS_INPUT_OUTPUT,
            self.screen.root_visual,
            xcb_c.XCB_CW_EVENT_MASK,
            &event_mask,
        );

        // Set window title
        _ = xcb_c.xcb_change_property(
            self.connection,
            xcb_c.XCB_PROP_MODE_REPLACE,
            self.window,
            xcb_c.XCB_ATOM_WM_NAME,
            xcb_c.XCB_ATOM_STRING,
            8,
            "pijpkijk".len,
            "pijpkijk",
        );

        // Subscribe to WM_DELETE_WINDOW
        const wm_protocols_cookie = xcb_c.xcb_intern_atom(self.connection, 1, "WM_PROTOCOLS".len, "WM_PROTOCOLS");
        const wm_delete_cookie = xcb_c.xcb_intern_atom(self.connection, 0, "WM_DELETE_WINDOW".len, "WM_DELETE_WINDOW");

        const wm_protocols_reply = xcb_c.xcb_intern_atom_reply(self.connection, wm_protocols_cookie, null);
        const wm_delete_reply = xcb_c.xcb_intern_atom_reply(self.connection, wm_delete_cookie, null);

        if (wm_protocols_reply != null and wm_delete_reply != null) {
            self.wm_delete_window = wm_delete_reply.*.atom;
            _ = xcb_c.xcb_change_property(
                self.connection,
                xcb_c.XCB_PROP_MODE_REPLACE,
                self.window,
                wm_protocols_reply.*.atom,
                4, // XCB_ATOM_ATOM
                32,
                1,
                &wm_delete_reply.*.atom,
            );
            std.c.free(wm_protocols_reply);
            std.c.free(wm_delete_reply);
        }

        // Map (show) the window
        _ = xcb_c.xcb_map_window(self.connection, self.window);
        _ = xcb_c.xcb_flush(self.connection);

        // Force a roundtrip to ensure the X server has processed the map request.
        // Without this, Vulkan may try to create a swapchain against an unmapped window,
        // which causes VK_ERROR_INITIALIZATION_FAILED on some drivers (e.g. RADV).
        const cookie = xcb_c.xcb_get_input_focus(self.connection);
        const reply = xcb_c.xcb_get_input_focus_reply(self.connection, cookie, null);
        if (reply) |r| std.c.free(r);
    }

    pub fn surface_ready(self: X11Handle) bool {
        // The roundtrip in start_surface guarantees the server processed the map.
        // That's sufficient for Vulkan — no need to wait for expose (some WMs delay it).
        _ = self;
        return true;
    }

    pub fn request_frame_callback(self: *X11Handle) void {
        // X11 has no frame callback; Vulkan FIFO present mode throttles instead
        _ = self;
    }

    // === Backend abstraction methods ===

    pub fn getFd(self: *X11Handle) i32 {
        return xcb_c.xcb_get_file_descriptor(self.connection);
    }

    pub fn dispatch(self: *X11Handle) !void {
        self.pollEvents();
    }

    pub fn dispatchPending(self: *X11Handle) void {
        self.pollEvents();
    }

    pub fn flushDisplay(self: *X11Handle) !void {
        _ = xcb_c.xcb_flush(self.connection);
    }

    pub fn createVkSurface(self: *X11Handle, instance: c.VkInstance) !c.VkSurfaceKHR {
        var surface: xcb_c.VkSurfaceKHR = undefined;

        const create_info = xcb_c.VkXcbSurfaceCreateInfoKHR{
            .sType = xcb_c.VK_STRUCTURE_TYPE_XCB_SURFACE_CREATE_INFO_KHR,
            .pNext = null,
            .flags = 0,
            .connection = self.connection,
            .window = self.window,
        };

        // Cast between the two cImport VkInstance types (identical layout, different Zig types)
        try handleError(xcb_c.vkCreateXcbSurfaceKHR(@ptrCast(instance), &create_info, null, &surface));
        return @ptrCast(surface);
    }

    pub fn getVkExtent(self: *X11Handle, capabilities: c.VkSurfaceCapabilitiesKHR) c.VkExtent2D {
        // X11 doesn't have fractional scaling, use window size directly
        return c.VkExtent2D{
            .width = std.math.clamp(
                self.state.width,
                capabilities.minImageExtent.width,
                capabilities.maxImageExtent.width,
            ),
            .height = std.math.clamp(
                self.state.height,
                capabilities.minImageExtent.height,
                capabilities.maxImageExtent.height,
            ),
        };
    }

    pub fn getVkInstanceExtensionName() [*:0]const u8 {
        return "VK_KHR_xcb_surface";
    }

    fn pollEvents(self: *X11Handle) void {
        while (true) {
            const event = xcb_c.xcb_poll_for_event(self.connection);
            if (event == null) break;
            defer std.c.free(event);

            const response_type = event.*.response_type & 0x7F;
            switch (response_type) {
                xcb_c.XCB_CONFIGURE_NOTIFY => {
                    const config: *xcb_c.xcb_configure_notify_event_t = @ptrCast(event);
                    if (config.width > 0 and config.height > 0) {
                        self.state.width = config.width;
                        self.state.height = config.height;
                    }
                },
                xcb_c.XCB_CLIENT_MESSAGE => {
                    const client_msg: *xcb_c.xcb_client_message_event_t = @ptrCast(event);
                    if (client_msg.data.data32[0] == self.wm_delete_window) {
                        self.state.should_close = true;
                    }
                },
                xcb_c.XCB_KEY_PRESS => {
                    const key_event: *xcb_c.xcb_key_press_event_t = @ptrCast(event);
                    self.handleKey(key_event.detail, .PRESSED);
                },
                xcb_c.XCB_KEY_RELEASE => {
                    const key_event: *xcb_c.xcb_key_release_event_t = @ptrCast(event);
                    self.handleKey(key_event.detail, .RELEASED);
                },
                xcb_c.XCB_BUTTON_PRESS => {
                    const btn: *xcb_c.xcb_button_press_event_t = @ptrCast(event);
                    switch (btn.detail) {
                        1 => self.state.input.mouse_down_l = true,
                        3 => self.state.input.mouse_down_r = true,
                        4 => self.state.input.scroll_y -= 15.0, // Scroll up
                        5 => self.state.input.scroll_y += 15.0, // Scroll down
                        6 => self.state.input.scroll_x -= 15.0, // Scroll left
                        7 => self.state.input.scroll_x += 15.0, // Scroll right
                        else => {},
                    }
                },
                xcb_c.XCB_BUTTON_RELEASE => {
                    const btn: *xcb_c.xcb_button_release_event_t = @ptrCast(event);
                    switch (btn.detail) {
                        1 => self.state.input.mouse_down_l = false,
                        3 => self.state.input.mouse_down_r = false,
                        else => {},
                    }
                },
                xcb_c.XCB_MOTION_NOTIFY => {
                    const motion: *xcb_c.xcb_motion_notify_event_t = @ptrCast(event);
                    const x: f32 = @floatFromInt(motion.event_x);
                    const y: f32 = @floatFromInt(motion.event_y);

                    if (self.state.input.mouse_x) |mx| self.state.input.mouse_dx += x - mx;
                    if (self.state.input.mouse_y) |my| self.state.input.mouse_dy += y - my;

                    self.state.input.mouse_x = x;
                    self.state.input.mouse_y = y;
                },
                else => {
                    // Check for XKB events (they have the xkb base event type)
                    // XKB state notify events are handled here
                    self.handleXkbEvent(event);
                },
            }
        }
    }

    fn handleXkbEvent(self: *X11Handle, event: *xcb_c.xcb_generic_event_t) void {
        // XKB events use a different type code range; check xkb_state for modifier updates
        _ = event;
        if (self.xkb_state_obj) |st| {
            self.state.input.shift_held = xcb_c.xkb_state_mod_name_is_active(
                st,
                xcb_c.XKB_MOD_NAME_SHIFT,
                xcb_c.XKB_STATE_MODS_EFFECTIVE,
            ) > 0;
        }
    }

    fn handleKey(self: *X11Handle, keycode: u8, val: KeyState) void {
        if (self.xkb_state_obj) |xkb_state| {
            // X11 keycodes are already X11 keycodes (no +8 offset needed)
            const keysym = xcb_c.xkb_state_key_get_one_sym(xkb_state, keycode);

            switch (keysym) {
                xcb_c.XKB_KEY_Escape => self.state.input.key_escape = val,
                xcb_c.XKB_KEY_w => self.state.input.key_w = val,
                xcb_c.XKB_KEY_a => self.state.input.key_a = val,
                xcb_c.XKB_KEY_s => self.state.input.key_s = val,
                xcb_c.XKB_KEY_d => self.state.input.key_d = val,
                xcb_c.XKB_KEY_q => self.state.input.key_q = val,
                xcb_c.XKB_KEY_r => self.state.input.key_r = val,
                xcb_c.XKB_KEY_h => self.state.input.key_h = val,
                xcb_c.XKB_KEY_Delete => self.state.input.key_delete = val,
                xcb_c.XKB_KEY_question => self.state.input.key_question = val,
                xcb_c.XKB_KEY_slash => self.state.input.key_slash = val,
                xcb_c.XKB_KEY_Return => self.state.input.key_return = val,
                xcb_c.XKB_KEY_Up => self.state.input.key_up = val,
                xcb_c.XKB_KEY_Down => self.state.input.key_down = val,
                xcb_c.XKB_KEY_BackSpace => self.state.input.key_backspace = val,
                xcb_c.XKB_KEY_greater => self.state.input.key_greater = val,
                xcb_c.XKB_KEY_less => self.state.input.key_less = val,
                else => {},
            }

            // Capture typed character for text input
            if (val == .PRESSED or val == .REPEATED) {
                const cp = xcb_c.xkb_state_key_get_utf32(xkb_state, keycode);
                if (cp >= 0x20 and cp < 0x7F) {
                    self.state.input.typed_codepoint = @intCast(cp);
                }
            }

            // Update modifier state
            _ = xcb_c.xkb_state_update_key(xkb_state, keycode, if (val == .RELEASED)
                xcb_c.XKB_KEY_UP
            else
                xcb_c.XKB_KEY_DOWN);
            self.state.input.shift_held = xcb_c.xkb_state_mod_name_is_active(
                xkb_state,
                xcb_c.XKB_MOD_NAME_SHIFT,
                xcb_c.XKB_STATE_MODS_EFFECTIVE,
            ) > 0;
        }
    }

    pub fn deinit(self: *X11Handle) void {
        if (self.xkb_state_obj) |s| xcb_c.xkb_state_unref(s);
        if (self.xkb_keymap) |s| xcb_c.xkb_keymap_unref(s);
        xcb_c.xkb_context_unref(self.xkb_context);

        _ = xcb_c.xcb_destroy_window(self.connection, self.window);
        xcb_c.xcb_disconnect(self.connection);

        std.log.info("Deinit X11Handle OK", .{});
    }
};

pub const Handle = X11Handle;
