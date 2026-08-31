const std = @import("std");
const c = @import("c.zig").c;

const KeyState = enum { PRESSED, RELEASED, REPEATED };

pub const SDLHandle = struct {
    var vulkan_extensions: [16][*:0]const u8 = undefined;

    pub const State = struct {
        width: u32 = 800,
        height: u32 = 600,
        should_close: bool = false,
        frame_ready: bool = true,
        fractional_scale: u32 = 120,
        input: struct {
            key_escape: ?KeyState = null,
            key_w: ?KeyState = null,
            key_a: ?KeyState = null,
            key_s: ?KeyState = null,
            key_d: ?KeyState = null,
            key_q: ?KeyState = null,
            key_r: ?KeyState = null,
            key_l: ?KeyState = null,
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

    window: *c.SDL_Window,
    state: State = .{},
    scale_snapshot: f32 = 1.0,

    pub fn init(self: *SDLHandle) !void {
        if (!c.SDL_Init(c.SDL_INIT_VIDEO)) return sdlError("SDL_Init");
        errdefer c.SDL_Quit();

        const window = c.SDL_CreateWindow(
            "pijpkijk",
            800,
            600,
            c.SDL_WINDOW_VULKAN | c.SDL_WINDOW_RESIZABLE,
        ) orelse return sdlError("SDL_CreateWindow");

        self.* = .{ .window = window };
        self.updateWindowMetrics();
        _ = c.SDL_StartTextInput(window);
    }

    fn sdlError(operation: []const u8) error{SDLError} {
        std.log.err("{s} failed: {s}", .{ operation, c.SDL_GetError() });
        return error.SDLError;
    }

    pub fn start_core(_: *SDLHandle) !void {}
    pub fn core_ready(_: SDLHandle) bool {
        return true;
    }
    pub fn seat_ready(_: SDLHandle) bool {
        return true;
    }
    pub fn start_surface(_: *SDLHandle) !void {}
    pub fn surface_ready(_: SDLHandle) bool {
        return true;
    }
    pub fn flush_blocking(_: SDLHandle) !void {}
    pub fn request_frame_callback(self: *SDLHandle) void {
        self.state.frame_ready = true;
    }
    pub fn idle(_: *SDLHandle) void {
        c.SDL_Delay(8);
    }

    pub fn getVkInstanceExtensions() ![]const [*:0]const u8 {
        var count: u32 = 0;
        const names = c.SDL_Vulkan_GetInstanceExtensions(&count) orelse return sdlError("SDL_Vulkan_GetInstanceExtensions");
        if (count > vulkan_extensions.len) return error.SDLError;
        for (0..count) |i| {
            if (names[i] == null) return error.SDLError;
            vulkan_extensions[i] = @ptrCast(names[i]);
        }
        return vulkan_extensions[0..count];
    }

    pub fn createVkSurface(self: *SDLHandle, instance: c.VkInstance) !c.VkSurfaceKHR {
        var surface: c.VkSurfaceKHR = undefined;
        if (!c.SDL_Vulkan_CreateSurface(self.window, instance, null, &surface)) {
            return sdlError("SDL_Vulkan_CreateSurface");
        }
        return surface;
    }

    pub fn getVkExtent(self: *SDLHandle, capabilities: c.VkSurfaceCapabilitiesKHR) c.VkExtent2D {
        self.updateWindowMetrics();
        if (capabilities.currentExtent.width != std.math.maxInt(u32)) return capabilities.currentExtent;
        var width: c_int = 0;
        var height: c_int = 0;
        if (!c.SDL_GetWindowSizeInPixels(self.window, &width, &height)) {
            width = @intCast(self.state.width);
            height = @intCast(self.state.height);
        }
        return .{
            .width = std.math.clamp(@as(u32, @intCast(@max(width, 1))), capabilities.minImageExtent.width, capabilities.maxImageExtent.width),
            .height = std.math.clamp(@as(u32, @intCast(@max(height, 1))), capabilities.minImageExtent.height, capabilities.maxImageExtent.height),
        };
    }

    fn updateWindowMetrics(self: *SDLHandle) void {
        var width: c_int = 0;
        var height: c_int = 0;
        if (c.SDL_GetWindowSize(self.window, &width, &height)) {
            self.state.width = @intCast(@max(width, 1));
            self.state.height = @intCast(@max(height, 1));
        }
        const scale = c.SDL_GetWindowDisplayScale(self.window);
        if (scale > 0) self.state.fractional_scale = @intFromFloat(scale * 120.0);
    }

    pub fn dispatch(self: *SDLHandle) !bool {
        var handled = false;
        var event: c.SDL_Event = undefined;
        while (c.SDL_PollEvent(&event)) {
            handled = true;
            switch (event.type) {
                c.SDL_EVENT_QUIT, c.SDL_EVENT_WINDOW_CLOSE_REQUESTED => self.state.should_close = true,
                c.SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED, c.SDL_EVENT_WINDOW_DISPLAY_SCALE_CHANGED => self.updateWindowMetrics(),
                c.SDL_EVENT_MOUSE_MOTION => {
                    self.state.input.mouse_x = event.motion.x;
                    self.state.input.mouse_y = event.motion.y;
                    self.state.input.mouse_dx += event.motion.xrel;
                    self.state.input.mouse_dy += event.motion.yrel;
                },
                c.SDL_EVENT_MOUSE_BUTTON_DOWN, c.SDL_EVENT_MOUSE_BUTTON_UP => {
                    const down = event.type == c.SDL_EVENT_MOUSE_BUTTON_DOWN;
                    if (event.button.button == c.SDL_BUTTON_LEFT) self.state.input.mouse_down_l = down;
                    if (event.button.button == c.SDL_BUTTON_RIGHT) self.state.input.mouse_down_r = down;
                    self.state.input.mouse_x = event.button.x;
                    self.state.input.mouse_y = event.button.y;
                },
                c.SDL_EVENT_MOUSE_WHEEL => {
                    self.state.input.scroll_x += event.wheel.x;
                    self.state.input.scroll_y -= event.wheel.y;
                    self.state.input.scroll_is_finger = event.wheel.which == c.SDL_TOUCH_MOUSEID;
                },
                c.SDL_EVENT_KEY_DOWN, c.SDL_EVENT_KEY_UP => self.handleKey(event.key),
                c.SDL_EVENT_TEXT_INPUT => {
                    const text = std.mem.span(event.text.text);
                    if (text.len > 0) self.state.input.typed_codepoint = std.unicode.utf8Decode(text) catch null;
                },
                else => {},
            }
        }
        return handled;
    }

    fn handleKey(self: *SDLHandle, event: c.SDL_KeyboardEvent) void {
        const value: KeyState = if (!event.down) .RELEASED else if (event.repeat) .REPEATED else .PRESSED;
        const input = &self.state.input;
        input.shift_held = (event.mod & c.SDL_KMOD_SHIFT) != 0;
        switch (event.scancode) {
            c.SDL_SCANCODE_ESCAPE => input.key_escape = value,
            c.SDL_SCANCODE_W => input.key_w = value,
            c.SDL_SCANCODE_A => input.key_a = value,
            c.SDL_SCANCODE_S => input.key_s = value,
            c.SDL_SCANCODE_D => input.key_d = value,
            c.SDL_SCANCODE_Q => input.key_q = value,
            c.SDL_SCANCODE_R => input.key_r = value,
            c.SDL_SCANCODE_L => input.key_l = value,
            c.SDL_SCANCODE_H => input.key_h = value,
            c.SDL_SCANCODE_DELETE => input.key_delete = value,
            c.SDL_SCANCODE_SLASH => if (input.shift_held) {
                input.key_question = value;
            } else {
                input.key_slash = value;
            },
            c.SDL_SCANCODE_RETURN, c.SDL_SCANCODE_KP_ENTER => input.key_return = value,
            c.SDL_SCANCODE_UP => input.key_up = value,
            c.SDL_SCANCODE_DOWN => input.key_down = value,
            c.SDL_SCANCODE_BACKSPACE => input.key_backspace = value,
            c.SDL_SCANCODE_PERIOD => {
                if (input.shift_held) input.key_greater = value;
            },
            c.SDL_SCANCODE_COMMA => {
                if (input.shift_held) input.key_less = value;
            },
            else => {},
        }
    }

    pub fn deinit(self: *SDLHandle) void {
        _ = c.SDL_StopTextInput(self.window);
        c.SDL_DestroyWindow(self.window);
        c.SDL_Quit();
    }
};

pub const Handle = SDLHandle;
