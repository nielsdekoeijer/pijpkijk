const std = @import("std");

/// Actual driver clock: rate is seconds per frame, quantum is frames per cycle.
pub const Clock = struct {
    rate_num: u32,
    rate_denom: u32,
    quantum: u64,
};

/// SPA latency components are additive, not alternative representations.
/// Keep the graph-relative parts rather than guessing a clock for idle nodes.
pub const Value = struct {
    quantum: f64 = 0,
    frames: i64 = 0,
    ns: i128 = 0,

    pub fn samples(self: Value, clock: ?Clock) ?f64 {
        var result = @as(f64, @floatFromInt(self.frames));
        if (self.quantum != 0) {
            const timing = clock orelse return null;
            if (timing.quantum == 0) return null;
            result += self.quantum * @as(f64, @floatFromInt(timing.quantum));
        }
        if (self.ns != 0) {
            const timing = clock orelse return null;
            if (timing.rate_num == 0 or timing.rate_denom == 0) return null;
            result += @as(f64, @floatFromInt(self.ns)) * @as(f64, @floatFromInt(timing.rate_denom)) /
                (@as(f64, @floatFromInt(timing.rate_num)) * 1_000_000_000.0);
        }
        return result;
    }

    pub fn format(self: Value, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        var separator: []const u8 = "";
        if (self.quantum != 0) {
            try writer.print("{d}q", .{self.quantum});
            separator = "+";
        }
        if (self.frames != 0) {
            try writer.print("{s}{d}f", .{ separator, self.frames });
            separator = "+";
        }
        if (self.ns != 0) {
            try writer.print("{s}{d}ns", .{ separator, self.ns });
        } else if (separator.len == 0) {
            try writer.writeAll("0f");
        }
    }
};

pub const Range = struct {
    min: Value,
    max: Value,

    pub fn format(self: Range, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        try writer.print("[{f}:{f}]", .{ self.min, self.max });
    }
};

test "sample conversion adds every unit and follows the actual clock" {
    const value = Value{ .quantum = 0.25, .frames = 24, .ns = 1_000_000 };
    const clock = Clock{ .quantum = 192, .rate_num = 1, .rate_denom = 48000 };
    try std.testing.expectEqual(@as(f64, 120), value.samples(clock).?);
    try std.testing.expectEqual(@as(f64, 360), value.samples(.{
        .quantum = 960,
        .rate_num = 1,
        .rate_denom = 96000,
    }).?);
    try std.testing.expectEqual(@as(f64, 120), value.samples(.{
        .quantum = 192,
        .rate_num = 2,
        .rate_denom = 96000,
    }).?);
    try std.testing.expect(value.samples(null) == null);
    try std.testing.expect(value.samples(.{
        .quantum = 192,
        .rate_num = 1,
        .rate_denom = 0,
    }) == null);
    try std.testing.expect(value.samples(.{
        .quantum = 0,
        .rate_num = 1,
        .rate_denom = 48000,
    }) == null);
    try std.testing.expect((Value{ .ns = 1_500_000 }).samples(null) == null);
    try std.testing.expectEqual(@as(f64, 24), (Value{ .frames = 24 }).samples(null).?);
    try std.testing.expectEqual(@as(f64, 0), (Value{}).samples(null).?);
    try std.testing.expectEqual(@as(f64, 2.5), (Value{ .frames = 1, .ns = 31_250 }).samples(clock).?);
}
