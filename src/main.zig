const std = @import("std");
const pijpkijk = @import("pijpkijk");
const build_options = @import("build_options");
const CustomLogger = @import("logger.zig").CustomLogger;

extern "c" fn setenv(name: [*:0]const u8, value: [*:0]const u8, overwrite: c_int) c_int;

pub const std_options = std.Options{
    .log_level = if (@import("builtin").mode == .Debug) .debug else .info,
    .logFn = CustomLogger.logFn,
};

const RemoteTunnel = struct {
    io: std.Io,
    allocator: std.mem.Allocator,
    socket_dir: [:0]u8,
    child: std.process.Child,

    fn init(allocator: std.mem.Allocator, io: std.Io, host: []const u8) !RemoteTunnel {
        const socket_dir = try createTempDir(allocator, io);
        errdefer {
            std.Io.Dir.cwd().deleteTree(io, socket_dir) catch {};
            allocator.free(socket_dir);
        }

        const socket_path = try std.fmt.allocPrintSentinel(allocator, "{s}/pipewire-0", .{socket_dir}, 0);
        defer allocator.free(socket_path);

        const destination = if (std.mem.indexOfScalar(u8, host, '@') == null)
            try std.fmt.allocPrint(allocator, "root@{s}", .{host})
        else
            try allocator.dupe(u8, host);
        defer allocator.free(destination);
        const forward = try std.fmt.allocPrint(
            allocator,
            "{s}:/run/pipewire/pipewire-0",
            .{socket_path},
        );
        defer allocator.free(forward);

        std.log.info("Forwarding PipeWire from {s}", .{destination});
        var child = try std.process.spawn(io, .{
            .argv = &.{
                build_options.ssh_path,
                "-nNT",
                "-o",
                "ExitOnForwardFailure=yes",
                "-o",
                "StreamLocalBindUnlink=yes",
                "-L",
                forward,
                destination,
            },
            .stdin = .ignore,
        });
        errdefer child.kill(io);

        // libpipewire reads the process environment directly through libc.
        if (setenv("PIPEWIRE_RUNTIME_DIR", socket_dir.ptr, 1) != 0)
            return error.SetEnvironmentFailed;

        // Avoid racing PipeWire initialization with SSH creating the socket.
        for (0..200) |_| {
            std.Io.Dir.accessAbsolute(io, socket_path, .{}) catch |err| switch (err) {
                error.FileNotFound => {
                    try std.Io.sleep(io, .fromMilliseconds(50), .awake);
                    continue;
                },
                else => return err,
            };
            return .{
                .io = io,
                .allocator = allocator,
                .socket_dir = socket_dir,
                .child = child,
            };
        }
        return error.SshTunnelTimedOut;
    }

    fn deinit(self: *RemoteTunnel) void {
        self.child.kill(self.io);
        std.Io.Dir.cwd().deleteTree(self.io, self.socket_dir) catch |err|
            std.log.warn("Could not remove temporary SSH socket directory: {}", .{err});
        self.allocator.free(self.socket_dir);
        self.* = undefined;
    }

    fn createTempDir(allocator: std.mem.Allocator, io: std.Io) ![:0]u8 {
        for (0..100) |attempt| {
            const path = try std.fmt.allocPrintSentinel(
                allocator,
                "/tmp/pijpkijk-{d}-{d}",
                .{ std.os.linux.getpid(), attempt },
                0,
            );
            std.Io.Dir.createDirAbsolute(io, path, .default_dir) catch |err| switch (err) {
                error.PathAlreadyExists => {
                    allocator.free(path);
                    continue;
                },
                else => {
                    allocator.free(path);
                    return err;
                },
            };
            return path;
        }
        return error.CouldNotCreateTempDir;
    }
};

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    CustomLogger.init(io);

    const allocator: std.mem.Allocator = init.gpa;

    var args = try std.process.Args.Iterator.initAllocator(init.minimal.args, allocator);
    defer args.deinit();
    _ = args.skip();

    const remote_host = args.next();
    if (args.next() != null) {
        std.log.err("Usage: pijpkijk [IP or user@host]", .{});
        return error.InvalidArguments;
    }

    var remote_tunnel: ?RemoteTunnel = if (remote_host) |host|
        try .init(allocator, io, host)
    else
        null;
    defer if (remote_tunnel) |*tunnel| tunnel.deinit();

    std.log.info("Using SDL3 backend", .{});
    var app = try pijpkijk.App.init(allocator, io);
    defer app.deinit();
    try app.run();
}
