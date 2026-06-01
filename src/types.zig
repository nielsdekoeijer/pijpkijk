const std = @import("std");
const c = @import("c.zig").c;

/// Helper type representing a 4x4 matrix
pub const Mat4 = extern struct {
    data: [16]f32,
};

/// Helper type representing a 4 vector
pub const Vec4 = extern struct {
    x: f32,
    y: f32,
    z: f32,
    w: f32,
};

/// Helper type representing a 3 vector
pub const Vec3 = extern struct {
    x: f32,
    y: f32,
    z: f32,
};

/// Uniform buffer
pub const Uniform = extern struct {
    screen_size: [2]f32,

    /// Upper-left corner of the camera we are viewing the world with
    camera_pos: [2]f32,

    /// Zoom
    scale: f32,

    /// Padding
    _: u32 = 0,
};

/// QuadVertex buffer
pub const QuadVertex = extern struct {
    pos: [2]f32,
    color: [4]f32,
    local_pos: [2]f32,
    half_size: [2]f32,
    radii: [4]f32,

    pub fn getVkBindingDiscription() [1]c.VkVertexInputBindingDescription {
        return [_]c.VkVertexInputBindingDescription{
            .{
                .binding = 0,
                .stride = @sizeOf(QuadVertex),
                .inputRate = c.VK_VERTEX_INPUT_RATE_VERTEX,
            },
        };
    }

    pub fn getVkAttributeDiscription() [5]c.VkVertexInputAttributeDescription {
        return [_]c.VkVertexInputAttributeDescription{
            .{
                .location = 0,
                .binding = 0,
                .format = c.VK_FORMAT_R32G32_SFLOAT,
                .offset = @offsetOf(QuadVertex, "pos"),
            },
            .{
                .location = 1,
                .binding = 0,
                .format = c.VK_FORMAT_R32G32B32A32_SFLOAT,
                .offset = @offsetOf(QuadVertex, "color"),
            },
            .{
                .location = 2,
                .binding = 0,
                .format = c.VK_FORMAT_R32G32_SFLOAT,
                .offset = @offsetOf(QuadVertex, "local_pos"),
            },
            .{
                .location = 3,
                .binding = 0,
                .format = c.VK_FORMAT_R32G32_SFLOAT,
                .offset = @offsetOf(QuadVertex, "half_size"),
            },
            .{
                .location = 4,
                .binding = 0,
                .format = c.VK_FORMAT_R32G32B32A32_SFLOAT,
                .offset = @offsetOf(QuadVertex, "radii"),
            },
        };
    }
};

/// BezierVertex buffer
pub const BezierVertex = extern struct {
    pos: [2]f32,
    p0: [2]f32,
    p1: [2]f32,
    p2: [2]f32,
    p3: [2]f32,
    thickness: f32,
    color: [4]f32,

    pub fn getVkBindingDiscription() [1]c.VkVertexInputBindingDescription {
        return [_]c.VkVertexInputBindingDescription{.{
            .binding = 0,
            .stride = @sizeOf(BezierVertex),
            .inputRate = c.VK_VERTEX_INPUT_RATE_VERTEX,
        }};
    }

    pub fn getVkAttributeDiscription() [6]c.VkVertexInputAttributeDescription {
        return [_]c.VkVertexInputAttributeDescription{
            .{
                .location = 0,
                .binding = 0,
                .format = c.VK_FORMAT_R32G32_SFLOAT,
                .offset = @offsetOf(BezierVertex, "pos"),
            },
            .{
                .location = 1,
                .binding = 0,
                .format = c.VK_FORMAT_R32G32_SFLOAT,
                .offset = @offsetOf(BezierVertex, "p0"),
            },
            .{
                .location = 2,
                .binding = 0,
                .format = c.VK_FORMAT_R32G32_SFLOAT,
                .offset = @offsetOf(BezierVertex, "p1"),
            },
            .{
                .location = 3,
                .binding = 0,
                .format = c.VK_FORMAT_R32G32_SFLOAT,
                .offset = @offsetOf(BezierVertex, "p2"),
            },
            .{
                .location = 4,
                .binding = 0,
                .format = c.VK_FORMAT_R32G32_SFLOAT,
                .offset = @offsetOf(BezierVertex, "p3"),
            },
            .{
                .location = 5,
                .binding = 0,
                .format = c.VK_FORMAT_R32G32B32A32_SFLOAT,
                .offset = @offsetOf(BezierVertex, "color"),
            },
        };
    }
};

/// Representation of an input pin
pub const InpPin = struct {
    name: []const u8,
};

/// Representation of an output pin
pub const OutPin = struct {
    name: []const u8,
    connections: []const Connection,
};

/// Representation of a connection bewteen an output pin and an input pin
pub const Connection = struct {
    node: *Node,
    inp_index: usize,
};

/// Representation of a node of our pipewire graph
pub const Node = struct {
    /// Name of the node itself
    name: []const u8,

    /// Ordered list of inputs
    inps: []const InpPin,

    /// Ordered list of outputs
    outs: []const OutPin,

    /// X-coordinate of the upper-left corner of the node
    x: f32,

    /// Y-coordinate of the upper-left corner of the node
    y: f32,

    /// Fixed width of the node
    const W_NODE: f32 = 100.0;

    /// Fixed offset w.r.t. the top of the node, reserved space for the title
    const H_OFFSET_TITLE: f32 = 50.0;
    const W_OFFSET_TITLE: f32 = 0.0;

    /// Fixed offset w.r.t. the title or previous pin w.r.t. the top of the node
    const H_OFFSET_OUTER_PIN: f32 = 50.0;
    const W_OFFSET_OUTER_PIN: f32 = 0.0;

    const H_PIN: f32 = 25;
    const H_OFFSET_INNER_PIN: f32 = 12.5;

    const W_PIN: f32 = 12.5;
    const W_OFFSET_INNER_PIN: f32 = 0.0;

    /// Helper function to append a quad of a solid color to an ArrayList of vertices
    fn appendQuad(
        allocator: std.mem.Allocator,
        list: *std.ArrayList(QuadVertex),
        x: f32,
        y: f32,
        w: f32,
        h: f32,
        color: [4]f32,
        radii: [4]f32,
    ) !void {
        const hx = w / 2.0;
        const hy = h / 2.0;
        const hs = [_]f32{ hx, hy };

        // Triangle A
        try list.append(allocator, .{
            .pos = .{ x, y },
            .local_pos = .{ -hx, -hy },
            .half_size = hs,
            .color = color,
            .radii = radii,
        });
        try list.append(allocator, .{
            .pos = .{ x, y + h },
            .local_pos = .{ -hx, hy },
            .half_size = hs,
            .color = color,
            .radii = radii,
        });
        try list.append(allocator, .{
            .pos = .{ x + w, y },
            .local_pos = .{ hx, -hy },
            .half_size = hs,
            .color = color,
            .radii = radii,
        });

        // Triangle B
        try list.append(allocator, .{
            .pos = .{ x + w, y + h },
            .local_pos = .{ hx, hy },
            .half_size = hs,
            .color = color,
            .radii = radii,
        });
        try list.append(allocator, .{
            .pos = .{ x, y + h },
            .local_pos = .{ -hx, hy },
            .half_size = hs,
            .color = color,
            .radii = radii,
        });
        try list.append(allocator, .{
            .pos = .{ x + w, y },
            .local_pos = .{ hx, -hy },
            .half_size = hs,
            .color = color,
            .radii = radii,
        });
    }

    fn computeMemberCount(self: Node) usize {
        return @max(self.inps.len, self.outs.len);
    }

    fn computeNodeHeight(self: Node) f32 {
        const member_count = self.computeMemberCount();
        return H_OFFSET_TITLE + (H_OFFSET_OUTER_PIN * @as(f32, @floatFromInt(member_count)));
    }

    pub fn appendVerticesNode(self: Node, allocator: std.mem.Allocator, list: *std.ArrayList(QuadVertex)) !void {
        const color: [4]f32 = .{ 0.2, 0.2, 0.2, 1.0 };
        try appendQuad(allocator, list, self.x, self.y, W_NODE, self.computeNodeHeight(), color, .{ 10.0, 10.0, 10.0, 10.0 });
    }

    pub fn appendVerticesPins(self: Node, allocator: std.mem.Allocator, list: *std.ArrayList(QuadVertex)) !void {
        const color: [4]f32 = .{ 1.0, 0.5, 0.0, 1.0 };

        {
            const H_BEG: f32 = H_OFFSET_TITLE;
            const W_BEG: f32 = 0;
            for (self.inps, 0..self.inps.len) |pin, i| {
                _ = pin;
                // const burn = 1.0 - 0.3 * @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(self.computeMemberCount() - 1));
                const burn = 1.0;

                const px = W_BEG + @as(f32, @floatFromInt(i)) * W_OFFSET_OUTER_PIN + W_OFFSET_INNER_PIN;
                const py = H_BEG + @as(f32, @floatFromInt(i)) * H_OFFSET_OUTER_PIN + H_OFFSET_INNER_PIN;
                try appendQuad(
                    allocator,
                    list,
                    self.x + px,
                    self.y + py,
                    W_PIN,
                    H_PIN,
                    .{ burn * color[0], burn * color[1], burn * color[2], color[3] },
                    .{ 2.5, 2.5, 0.0, 0.0 },
                );
            }
        }

        {
            const H_BEG: f32 = H_OFFSET_TITLE;
            const W_BEG: f32 = W_NODE - W_OFFSET_INNER_PIN * 2 - W_PIN;
            for (self.outs, 0..self.outs.len) |pin, i| {
                _ = pin;
                // const burn = 1.0 - 0.3 * @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(self.computeMemberCount() - 1));
                const burn = 1.0;

                const px = W_BEG + @as(f32, @floatFromInt(i)) * W_OFFSET_OUTER_PIN + W_OFFSET_INNER_PIN;
                const py = H_BEG + @as(f32, @floatFromInt(i)) * H_OFFSET_OUTER_PIN + H_OFFSET_INNER_PIN;
                try appendQuad(
                    allocator,
                    list,
                    self.x + px,
                    self.y + py,
                    W_PIN,
                    H_PIN,
                    .{ burn * color[0], burn * color[1], burn * color[2], color[3] },
                    .{ 0.0, 0.0, 2.5, 2.5 },
                );
            }
        }
    }

    fn getInpPinX(self: *const Node, _: usize) f32 {
        return self.x;
    }

    fn getOutPinX(self: *const Node, _: usize) f32 {
        return self.x + W_NODE;
    }

    fn getInpPinY(self: *const Node, index: usize) f32 {
        return self.y + H_OFFSET_TITLE + (@as(f32, @floatFromInt(index)) * H_OFFSET_OUTER_PIN) + H_OFFSET_INNER_PIN + H_PIN / 2;
    }

    fn getOutPinY(self: *const Node, index: usize) f32 {
        return self.y + H_OFFSET_TITLE + (@as(f32, @floatFromInt(index)) * H_OFFSET_OUTER_PIN) + H_OFFSET_INNER_PIN + H_PIN / 2;
    }

    // In src/types.zig, inside the Node or a new relevant context:
    pub fn appendVerticesBezier(
        self: Node,
        allocator: std.mem.Allocator,
        list: *std.ArrayList(BezierVertex),
        color: [4]f32,
    ) !void {
        for (self.outs, 0..) |out, i| {
            for (out.connections) |connection| {
                const p0 = [2]f32{ self.getOutPinX(i), self.getOutPinY(i) };
                const p3 = [2]f32{ connection.node.getInpPinX(connection.inp_index), connection.node.getInpPinY(connection.inp_index) };

                const mid_x = (p0[0] + p3[0]) / 2.0;

                const p1 = [2]f32{ mid_x, p0[1] };
                const p2 = [2]f32{ mid_x, p3[1] };

                const min_x = @min(p0[0], @min(p3[0], @min(p1[0], p2[0])));
                const max_x = @max(p0[0], @max(p3[0], @max(p1[0], p2[0])));
                const min_y = @min(p0[1], @min(p3[1], @min(p1[1], p2[1])));
                const max_y = @max(p0[1], @max(p3[1], @max(p1[1], p2[1])));

                const thickness = 4.0;
                const padding = 10.0;

                const x = min_x - padding;
                const y = min_y - padding;
                const w = (max_x - min_x) + (padding * 2);
                const h = (max_y - min_y) + (padding * 2);

                const quad = [_]BezierVertex{
                    .{ .pos = .{ x, y }, .p0 = p0, .p1 = p1, .p2 = p2, .p3 = p3, .thickness = thickness, .color = color },
                    .{ .pos = .{ x, y + h }, .p0 = p0, .p1 = p1, .p2 = p2, .p3 = p3, .thickness = thickness, .color = color },
                    .{ .pos = .{ x + w, y }, .p0 = p0, .p1 = p1, .p2 = p2, .p3 = p3, .thickness = thickness, .color = color },

                    .{ .pos = .{ x + w, y + h }, .p0 = p0, .p1 = p1, .p2 = p2, .p3 = p3, .thickness = thickness, .color = color },
                    .{ .pos = .{ x, y + h }, .p0 = p0, .p1 = p1, .p2 = p2, .p3 = p3, .thickness = thickness, .color = color },
                    .{ .pos = .{ x + w, y }, .p0 = p0, .p1 = p1, .p2 = p2, .p3 = p3, .thickness = thickness, .color = color },
                };

                try list.appendSlice(allocator, &quad);
            }
        }
    }
};
