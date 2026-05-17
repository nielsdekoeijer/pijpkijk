const std = @import("std");
const Io = std.Io;

pub const std_options = std.Options{
    .log_level = .debug,
};

const pijpkijk = @import("pijpkijk");

pub fn main(init: std.process.Init) !void {
    const arena: std.mem.Allocator = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);

    const io = init.io;
    const allocator: std.mem.Allocator = init.gpa;

    _ = args;
    _ = io;

    var app = try pijpkijk.App.init(allocator);
    defer app.deinit();
    try app.run();
}
