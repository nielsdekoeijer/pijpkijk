const std = @import("std");

pub const CustomLogger = struct {
    var initialized = false;
    var starting_timestamp: ?std.Io.Timestamp = null;
    var io: ?std.Io = null;

    pub fn init(user_io: std.Io) void {
        io = user_io;

        starting_timestamp = std.Io.Timestamp.now(io.?, .awake);

        initialized = true;
    }

    pub fn logFn(
        comptime level: std.log.Level,
        comptime scope: @EnumLiteral(),
        comptime format: []const u8,
        args: anytype,
    ) void {
        if (CustomLogger.initialized) {
            var buffer: [64]u8 = undefined;

            const stderr = (io.?.lockStderr(&buffer, .escape_codes) catch unreachable).terminal();
            defer io.?.unlockStderr();

            const color = switch (level) {
                .err => std.Io.Terminal.Color.red,
                .warn => std.Io.Terminal.Color.yellow,
                .info => std.Io.Terminal.Color.green,
                .debug => std.Io.Terminal.Color.magenta,
            };

            {
                const now = std.Io.Timestamp.now(io.?, .awake);
                const time = now.toMilliseconds() - starting_timestamp.?.toMilliseconds();

                stderr.setColor(.dim) catch unreachable;
                stderr.writer.print("[{d: >10}] ", .{time}) catch unreachable;
                stderr.setColor(.reset) catch unreachable;
            }

            {
                stderr.setColor(.bold) catch unreachable;
                stderr.setColor(color) catch unreachable;
                stderr.writer.writeAll(level.asText()) catch unreachable;
                stderr.setColor(.reset) catch unreachable;
            }

            {
                if (scope != .default) stderr.writer.print("({t})", .{scope}) catch unreachable;
                stderr.writer.writeAll(": ") catch unreachable;
                stderr.writer.print(format ++ "\n", args) catch unreachable;
                stderr.setColor(.reset) catch unreachable;
            }
        }
    }
};
