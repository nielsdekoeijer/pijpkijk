const std = @import("std");
const pijpkijk = @import("pijpkijk");
const CustomLogger = @import("logger.zig").CustomLogger;

pub const std_options = std.Options{
    .log_level = if (@import("builtin").mode == .Debug) .debug else .info,
    .logFn = CustomLogger.logFn,
};

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    CustomLogger.init(io);

    const allocator: std.mem.Allocator = init.gpa;
    var app = try pijpkijk.App.init(allocator, io);
    defer app.deinit();
    try app.run();
}
