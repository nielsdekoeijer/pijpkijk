const std = @import("std");
const pijpkijk = @import("pijpkijk");
const CustomLogger = @import("logger.zig").CustomLogger;

pub const std_options = std.Options{
    .log_level = if (@import("builtin").mode == .Debug) .debug else .info,
    .logFn = CustomLogger.logFn,
};

fn getenv(name: [*:0]const u8) ?[*:0]const u8 {
    const val = std.c.getenv(name);
    if (val) |v| return v;
    return null;
}

fn detectBackend() pijpkijk.BackendKind {
    // Check for env var override first
    if (getenv("PIJPKIJK_BACKEND")) |backend_str| {
        const s = std.mem.span(backend_str);
        if (std.mem.eql(u8, s, "wayland")) return .wayland;
        if (std.mem.eql(u8, s, "x11")) return .x11;
        std.log.warn("Unknown PIJPKIJK_BACKEND value '{s}', auto-detecting...", .{s});
    }

    // Auto-detect: if WAYLAND_DISPLAY is set, use wayland
    if (getenv("WAYLAND_DISPLAY")) |_| {
        return .wayland;
    }

    // Fallback to X11
    return .x11;
}

fn runApp(comptime BackendHandle: type, allocator: std.mem.Allocator, io: std.Io) !void {
    var app = try pijpkijk.AppImpl(BackendHandle).init(allocator, io);
    defer app.deinit();
    try app.run();
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    CustomLogger.init(io);

    const allocator: std.mem.Allocator = init.gpa;

    const backend = detectBackend();
    std.log.info("Using {s} backend", .{@tagName(backend)});

    switch (backend) {
        .wayland => try runApp(pijpkijk.wayland.Handle, allocator, io),
        .x11 => try runApp(pijpkijk.x11.Handle, allocator, io),
    }
}
