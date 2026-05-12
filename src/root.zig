const std = @import("std");
const Io = std.Io;
const c = @import("c.zig").c;
const handleSDLError = @import("error.zig").handleSDLError;

pub const App = struct {
    window: ?*c.struct_SDL_Window,
    renderer: ?*c.struct_SDL_Renderer,

    const version = "0.1.0";
    const name = "pijpkijk";
    const identifier = "com.nielsdekoeijer.pijpkijk";

    pub fn init() !App {
        var app: App = .{
            .window = null,
            .renderer = null,
        };

        try handleSDLError(c.SDL_SetAppMetadata(name, version, identifier));
        try handleSDLError(c.SDL_Init(c.SDL_INIT_VIDEO | c.SDL_INIT_AUDIO));

        try handleSDLError(c.SDL_CreateWindowAndRenderer(
            name,
            640,
            480,
            c.SDL_WINDOW_RESIZABLE,
            &app.window,
            &app.renderer,
        ));

        try handleSDLError(c.SDL_SetRenderLogicalPresentation(
            app.renderer,
            640,
            480,
            c.SDL_LOGICAL_PRESENTATION_LETTERBOX,
        ));

        return app;
    }

    pub fn run(self: *App) !void {
        try handleSDLError(c.SDL_RenderClear(self.renderer));
        try handleSDLError(c.SDL_RenderPresent(self.renderer));
        program_loop: while (true) {
            var event: c.SDL_Event = undefined;
            while (c.SDL_PollEvent(&event)) {
                switch (event.type) {
                    c.SDL_EVENT_QUIT => {
                        break :program_loop;
                    },
                    c.SDL_EVENT_KEY_DOWN => {
                        switch (event.key.scancode) {
                            c.SDL_SCANCODE_ESCAPE => {
                                break :program_loop;
                            },
                            else => {},
                        }
                    },
                    else => {},
                }
            }
        }
    }

    pub fn deinit(self: *App) void {
        c.SDL_DestroyRenderer(self.renderer);
        c.SDL_DestroyWindow(self.window);
        c.SDL_Quit();
        self.window = null;
        self.renderer = null;
    }
};
