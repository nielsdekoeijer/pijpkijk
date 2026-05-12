const std = @import("std");
const Io = std.Io;

const pijpkijk = @import("pijpkijk");

pub fn main(init: std.process.Init) !void {
    const arena: std.mem.Allocator = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);

    const io = init.io;
    const allocator: std.mem.Allocator = init.gpa;

    _ = args;
    _ = io;
    _ = allocator;

    var app = try pijpkijk.App.init();
    defer app.deinit();
    try app.run();
}
