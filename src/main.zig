const std = @import("std");
const Io = std.Io;

pub fn customLogger(
    comptime level: std.log.Level,
    comptime scope: @EnumLiteral(),
    comptime format: []const u8,
    args: anytype,
) void {
    const io = std.Options.debug_io;
    const prev = io.swapCancelProtection(.blocked);
    defer _ = io.swapCancelProtection(prev);

    var buffer: [64]u8 = undefined;
    const stderr = std.debug.lockStderr(&buffer).terminal();
    defer std.debug.unlockStderr();

    // 1. Get current time
    const now = std.Io.Timestamp.now(io, .cpu_process);

    // 2. Print timestamp
    stderr.setColor(.dim) catch {};
    stderr.writer.print("[{d: >10}] ", .{now.toMilliseconds()}) catch {};
    stderr.setColor(.reset) catch {};

    // 3. Existing log logic
    stderr.setColor(switch (level) {
        .err => std.Io.Terminal.Color.red,
        .warn => std.Io.Terminal.Color.yellow,
        .info => std.Io.Terminal.Color.green,
        .debug => std.Io.Terminal.Color.magenta,
    }) catch {};
    stderr.setColor(.bold) catch {};
    stderr.writer.writeAll(level.asText()) catch {};
    stderr.setColor(.reset) catch {};

    stderr.setColor(.dim) catch {};
    stderr.setColor(.bold) catch {};
    if (scope != .default) stderr.writer.print("({t})", .{scope}) catch {};
    stderr.writer.writeAll(": ") catch {};
    stderr.setColor(.reset) catch {};

    stderr.writer.print(format ++ "\n", args) catch {};
}

pub const std_options = std.Options{
    .log_level = if (@import("builtin").mode == .Debug) .debug else .info,
    .logFn = customLogger,
};

const pijpkijk = @import("pijpkijk");

pub fn main(init: std.process.Init) !void {
    {
        const arena: std.mem.Allocator = init.arena.allocator();
        const args = try init.minimal.args.toSlice(arena);
        _ = args;
    }

    const io = init.io;
    const allocator: std.mem.Allocator = init.gpa;

    _ = io;

    var app = try pijpkijk.App.init(allocator);
    defer app.deinit();
    try app.run();
}
