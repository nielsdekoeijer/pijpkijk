const c = @import("c.zig").c;
const std = @import("std");

/// Helper for colors
pub const VibrantColor = enum(u8) {
    NeonBlaze,
    ElectricCrimson,
    HyperMagenta,
    NeonCoral,
    VoltageOrange,
    LuminousEmber,
    ElectricGold,
    NeonCitrus,
    RadioactiveLime,
    LaserGreen,
    GlowingEmerald,
    NeonAqua,
    ElectricCyan,
    NeonSky,
    HyperBlue,
    VividIndigo,
    ShockwaveViolet,
    ElectricAmethyst,
    NeonOrchid,
    FluorescentFuchsia,

    pub const palette = [_][4]f32{
        .{ 1.000, 0.039, 0.329, 1.0 }, // #FF0A54 - Neon Blaze
        .{ 1.000, 0.125, 0.306, 1.0 }, // #FF204E - Electric Crimson
        .{ 1.000, 0.227, 0.353, 1.0 }, // #FF3A5A - Hyper Magenta
        .{ 1.000, 0.341, 0.408, 1.0 }, // #FF5768 - Neon Coral
        .{ 1.000, 0.435, 0.235, 1.0 }, // #FF6F3C - Voltage Orange
        .{ 1.000, 0.569, 0.000, 1.0 }, // #FF9100 - Luminous Ember
        .{ 1.000, 0.835, 0.000, 1.0 }, // #FFD500 - Electric Gold
        .{ 0.843, 1.000, 0.000, 1.0 }, // #D7FF00 - Neon Citrus
        .{ 0.655, 1.000, 0.000, 1.0 }, // #A7FF00 - Radioactive Lime
        .{ 0.224, 1.000, 0.078, 1.0 }, // #39FF14 - Laser Green
        .{ 0.000, 1.000, 0.294, 1.0 }, // #00FF4B - Glowing Emerald
        .{ 0.000, 1.000, 0.659, 1.0 }, // #00FFA8 - Neon Aqua
        .{ 0.000, 0.973, 1.000, 1.0 }, // #00F8FF - Electric Cyan
        .{ 0.000, 0.749, 1.000, 1.0 }, // #00BFFF - Neon Sky
        .{ 0.000, 0.482, 1.000, 1.0 }, // #007BFF - Hyper Blue
        .{ 0.353, 0.000, 1.000, 1.0 }, // #5A00FF - Vivid Indigo
        .{ 0.651, 0.000, 1.000, 1.0 }, // #A600FF - Shockwave Violet
        .{ 0.902, 0.000, 1.000, 1.0 }, // #E600FF - Electric Amethyst
        .{ 1.000, 0.000, 0.784, 1.0 }, // #FF00C8 - Neon Orchid
        .{ 1.000, 0.000, 0.541, 1.0 }, // #FF008A - Fluorescent Fuchsia
    };

    fn fromIndex(index: usize) VibrantColor {
        const variant_count = @typeInfo(VibrantColor).@"enum".fields.len;
        return @enumFromInt(index % variant_count);
    }

    pub fn get(self: VibrantColor) [4]f32 {
        return palette[@intFromEnum(self)];
    }

    pub fn getRandom(random: std.Random) [4]f32 {
        const index = @as(u8, @intCast(std.Random.uintLessThan(random, u8, @typeInfo(VibrantColor).@"enum".fields.len)));
        return @as(VibrantColor, @enumFromInt(index)).get();
    }

    pub fn getColorByIndex(index: usize) [4]f32 {
        return fromIndex(index).get();
    }
};

pub const FontAtlas = struct {
    pub const Configuration = struct {
        pub const Bounds = struct {
            left: f32,
            bottom: f32,
            right: f32,
            top: f32,
        };

        pub const Glyph = struct {
            unicode: u32,
            advance: f32,
            planeBounds: ?Bounds = null,
            atlasBounds: ?Bounds = null,
        };

        pub const Metrics = struct {
            emSize: f32,
            lineHeight: f32,
            ascender: f32,
            descender: f32,
            underlineY: f32,
            underlineThickness: f32,
        };

        pub const AtlasConfig = struct {
            type: []const u8,
            distanceRange: f32,
            distanceRangeMiddle: f32,
            size: f32,
            width: u32,
            height: u32,
            yOrigin: []const u8,
        };

        atlas: AtlasConfig,
        metrics: Metrics,
        glyphs: []Glyph,
    };

    parsed: std.json.Parsed(Configuration),

    pub fn init(allocator: std.mem.Allocator, json: []const u8) !FontAtlas {
        const parsed = try std.json.parseFromSlice(FontAtlas.Configuration, allocator, json, .{
            .ignore_unknown_fields = true,
        });
        errdefer parsed.deinit();

        return FontAtlas{
            .parsed = parsed,
        };
    }

    pub fn deinit(self: *FontAtlas) void {
        defer self.parsed.deinit();
    }

    pub fn getGlyph(self: FontAtlas, unicode: u32) ?Configuration.Glyph {
        for (self.parsed.value.glyphs) |g| {
            if (g.unicode == unicode) return g;
        }
        return null;
    }
};

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
    color_beg: [4]f32,
    color_end: [4]f32,
    thickness: f32,

    pub fn getVkBindingDiscription() [1]c.VkVertexInputBindingDescription {
        return [_]c.VkVertexInputBindingDescription{.{
            .binding = 0,
            .stride = @sizeOf(BezierVertex),
            .inputRate = c.VK_VERTEX_INPUT_RATE_VERTEX,
        }};
    }

    pub fn getVkAttributeDiscription() [8]c.VkVertexInputAttributeDescription {
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
                .offset = @offsetOf(BezierVertex, "color_beg"),
            },
            .{
                .location = 6,
                .binding = 0,
                .format = c.VK_FORMAT_R32G32B32A32_SFLOAT,
                .offset = @offsetOf(BezierVertex, "color_end"),
            },
            .{
                .location = 7,
                .binding = 0,
                .format = c.VK_FORMAT_R32G32B32A32_SFLOAT,
                .offset = @offsetOf(BezierVertex, "thickness"),
            },
        };
    }
};

/// TextVertex
pub const TextVertex = extern struct {
    pos: [2]f32,
    color: [4]f32,
    uv: [2]f32,

    pub fn getVkBindingDiscription() [1]c.VkVertexInputBindingDescription {
        return [_]c.VkVertexInputBindingDescription{.{
            .binding = 0,
            .stride = @sizeOf(TextVertex),
            .inputRate = c.VK_VERTEX_INPUT_RATE_VERTEX,
        }};
    }

    pub fn getVkAttributeDiscription() [3]c.VkVertexInputAttributeDescription {
        return [_]c.VkVertexInputAttributeDescription{
            .{
                .location = 0,
                .binding = 0,
                .format = c.VK_FORMAT_R32G32_SFLOAT,
                .offset = @offsetOf(TextVertex, "pos"),
            },
            .{
                .location = 1,
                .binding = 0,
                .format = c.VK_FORMAT_R32G32B32A32_SFLOAT,
                .offset = @offsetOf(TextVertex, "color"),
            },
            .{
                .location = 2,
                .binding = 0,
                .format = c.VK_FORMAT_R32G32_SFLOAT,
                .offset = @offsetOf(TextVertex, "uv"),
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
    node_index: usize,
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

    /// Color used for pins and connections
    color: [4]f32 = .{ 1.0, 0.5, 0.0, 1.0 },

    /// X-coordinate of the upper-left corner of the node
    x: f32,

    /// Y-coordinate of the upper-left corner of the node
    y: f32,

    /// Fixed width of the node
    const W_NODE: f32 = 200.0;

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
        {
            const H_BEG: f32 = H_OFFSET_TITLE;
            const W_BEG: f32 = 0;
            for (self.inps, 0..self.inps.len) |pin, i| {
                _ = pin;
                const px = W_BEG + @as(f32, @floatFromInt(i)) * W_OFFSET_OUTER_PIN + W_OFFSET_INNER_PIN;
                const py = H_BEG + @as(f32, @floatFromInt(i)) * H_OFFSET_OUTER_PIN + H_OFFSET_INNER_PIN;
                try appendQuad(
                    allocator,
                    list,
                    self.x + px,
                    self.y + py,
                    W_PIN,
                    H_PIN,
                    self.getInpPinColor(i),
                    .{ 2.5, 2.5, 0.0, 0.0 },
                );
            }
        }

        {
            const H_BEG: f32 = H_OFFSET_TITLE;
            const W_BEG: f32 = W_NODE - W_OFFSET_INNER_PIN * 2 - W_PIN;
            for (self.outs, 0..self.outs.len) |pin, i| {
                _ = pin;
                const px = W_BEG + @as(f32, @floatFromInt(i)) * W_OFFSET_OUTER_PIN + W_OFFSET_INNER_PIN;
                const py = H_BEG + @as(f32, @floatFromInt(i)) * H_OFFSET_OUTER_PIN + H_OFFSET_INNER_PIN;
                try appendQuad(
                    allocator,
                    list,
                    self.x + px,
                    self.y + py,
                    W_PIN,
                    H_PIN,
                    self.getOutPinColor(i),
                    .{ 0.0, 0.0, 2.5, 2.5 },
                );
            }
        }
    }

    fn getInpPinColor(self: Node, index: usize) [4]f32 {
        const base = self.color;
        const burn = 1.0 - 0.8 * @as(f32, @floatFromInt(index)) / @as(f32, @floatFromInt(self.computeMemberCount()));
        return .{ burn * base[0], burn * base[1], burn * base[2], base[3] };
    }

    fn getOutPinColor(self: Node, index: usize) [4]f32 {
        const base = self.color;
        const burn = 1.0 - 0.8 * @as(f32, @floatFromInt(index)) / @as(f32, @floatFromInt(self.computeMemberCount()));
        return .{ burn * base[0], burn * base[1], burn * base[2], base[3] };
    }

    fn getInpPinX(self: Node, _: usize) f32 {
        return self.x;
    }

    fn getOutPinX(self: Node, _: usize) f32 {
        return self.x + W_NODE;
    }

    fn getInpPinY(self: Node, index: usize) f32 {
        return self.y + H_OFFSET_TITLE + (@as(f32, @floatFromInt(index)) * H_OFFSET_OUTER_PIN) + H_OFFSET_INNER_PIN + H_PIN / 2;
    }

    fn getOutPinY(self: Node, index: usize) f32 {
        return self.y + H_OFFSET_TITLE + (@as(f32, @floatFromInt(index)) * H_OFFSET_OUTER_PIN) + H_OFFSET_INNER_PIN + H_PIN / 2;
    }

    // In src/types.zig, inside the Node or a new relevant context:
    pub fn appendVerticesBezier(
        self: Node,
        allocator: std.mem.Allocator,
        nodes: []Node,
        list: *std.ArrayList(BezierVertex),
    ) !void {
        for (self.outs, 0..) |out, i| {
            for (out.connections) |connection| {
                const p0 = [2]f32{ self.getOutPinX(i), self.getOutPinY(i) };
                const p3 = [2]f32{
                    nodes[connection.node_index].getInpPinX(connection.inp_index),
                    nodes[connection.node_index].getInpPinY(connection.inp_index),
                };

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
                    .{
                        .pos = .{ x, y },
                        .p0 = p0,
                        .p1 = p1,
                        .p2 = p2,
                        .p3 = p3,
                        .thickness = thickness,
                        .color_beg = self.getOutPinColor(i),
                        .color_end = nodes[connection.node_index].getInpPinColor(connection.inp_index),
                    },
                    .{
                        .pos = .{ x, y + h },
                        .p0 = p0,
                        .p1 = p1,
                        .p2 = p2,
                        .p3 = p3,
                        .thickness = thickness,
                        .color_beg = self.getOutPinColor(i),
                        .color_end = nodes[connection.node_index].getInpPinColor(connection.inp_index),
                    },
                    .{
                        .pos = .{ x + w, y },
                        .p0 = p0,
                        .p1 = p1,
                        .p2 = p2,
                        .p3 = p3,
                        .thickness = thickness,
                        .color_beg = self.getOutPinColor(i),
                        .color_end = nodes[connection.node_index].getInpPinColor(connection.inp_index),
                    },

                    .{
                        .pos = .{ x + w, y + h },
                        .p0 = p0,
                        .p1 = p1,
                        .p2 = p2,
                        .p3 = p3,
                        .thickness = thickness,
                        .color_beg = self.getOutPinColor(i),
                        .color_end = nodes[connection.node_index].getInpPinColor(connection.inp_index),
                    },
                    .{
                        .pos = .{ x, y + h },
                        .p0 = p0,
                        .p1 = p1,
                        .p2 = p2,
                        .p3 = p3,
                        .thickness = thickness,
                        .color_beg = self.getOutPinColor(i),
                        .color_end = nodes[connection.node_index].getInpPinColor(connection.inp_index),
                    },
                    .{
                        .pos = .{ x + w, y },
                        .p0 = p0,
                        .p1 = p1,
                        .p2 = p2,
                        .p3 = p3,
                        .thickness = thickness,
                        .color_beg = self.getOutPinColor(i),
                        .color_end = nodes[connection.node_index].getInpPinColor(connection.inp_index),
                    },
                };

                try list.appendSlice(allocator, &quad);
            }
        }
    }

    pub const TextAlign = enum { Left, Center, Right };

    pub fn appendAllText(
        self: Node,
        allocator: std.mem.Allocator,
        atlas: FontAtlas,
        list: *std.ArrayList(TextVertex),
    ) !void {
        // 1. Draw Title (Centered, Truncated to fit inside node bounds)
        const title_max_w = W_NODE - 20.0; // 10px padding on each side
        const title_x = self.x + (W_NODE / 2.0); // Exact middle
        const title_y = self.y + 30.0; // Approximate baseline for the 50px header

        try self.appendText(allocator, self.name, atlas, list, title_x, title_y, 16.0, .Center, title_max_w);

        // 2. Draw Input Pins (Left-aligned)
        for (self.inps, 0..) |pin, i| {
            const pin_x = self.x + W_OFFSET_INNER_PIN + W_PIN + 8.0; // Pad right of the pin box
            const pin_y = self.getInpPinY(i) + 4.0; // Drop baseline down slightly from center
            const pin_max_w = (W_NODE / 2.0) - W_PIN - 12.0; // Prevent overlapping with out-pins

            try self.appendText(allocator, pin.name, atlas, list, pin_x, pin_y, 12.0, .Left, pin_max_w);
        }

        // 3. Draw Output Pins (Right-aligned)
        for (self.outs, 0..) |pin, i| {
            const pin_x = self.x + W_NODE - W_OFFSET_INNER_PIN - W_PIN - 8.0; // Pad left of the pin box
            const pin_y = self.getOutPinY(i) + 4.0;
            const pin_max_w = (W_NODE / 2.0) - W_PIN - 12.0;

            try self.appendText(allocator, pin.name, atlas, list, pin_x, pin_y, 12.0, .Right, pin_max_w);
        }
    }

    pub fn appendText(
        self: Node,
        allocator: std.mem.Allocator,
        text: []const u8,
        atlas: FontAtlas,
        list: *std.ArrayList(TextVertex),
        pos_x: f32,
        pos_y: f32,
        font_size: f32,
        align_mode: TextAlign,
        max_w: f32,
    ) !void {
        _ = self;
        const scale = font_size / atlas.parsed.value.metrics.emSize;
        const atlas_w = @as(f32, @floatFromInt(atlas.parsed.value.atlas.width));
        const atlas_h = @as(f32, @floatFromInt(atlas.parsed.value.atlas.height));

        // 1. Pre-measure the text & calculate truncation
        var current_width: f32 = 0.0;
        var dot_width: f32 = 0.0;
        if (atlas.getGlyph('.')) |g| dot_width = g.advance * scale;

        var draw_len: usize = text.len;
        var needs_dots = false;
        var measured_w: f32 = 0.0;

        for (text) |char| {
            const g = atlas.getGlyph(char) orelse continue;
            const adv = g.advance * scale;
            if (current_width + adv > max_w) {
                needs_dots = true;
                break;
            }
            current_width += adv;
            measured_w = current_width;
        }

        // If it exceeded max width, calculate exactly how many chars we can fit IF we append "..."
        if (needs_dots) {
            current_width = 0.0;
            const target_w = max_w - (dot_width * 3.0);
            draw_len = 0;
            if (target_w > 0) {
                for (text) |char| {
                    const g = atlas.getGlyph(char) orelse continue;
                    const adv = g.advance * scale;
                    if (current_width + adv > target_w) break;
                    current_width += adv;
                    draw_len += 1;
                }
            }
            measured_w = current_width + (dot_width * 3.0);
        }

        // 2. Adjust starting X position based on alignment requested
        var cursor_x: f32 = switch (align_mode) {
            .Left => pos_x,
            .Center => pos_x - (measured_w / 2.0),
            .Right => pos_x - measured_w,
        };
        const cursor_y = pos_y;
        const text_color = [_]f32{ 1.0, 1.0, 1.0, 1.0 };

        // 3. Draw Routine
        const dots_to_draw: usize = if (needs_dots) 3 else 0;
        var i: usize = 0;

        while (i < draw_len + dots_to_draw) : (i += 1) {
            const char = if (i < draw_len) text[i] else '.';
            const glyph = atlas.getGlyph(char) orelse continue;

            if (glyph.planeBounds) |pb| {
                if (glyph.atlasBounds) |ab| {
                    const screen_l = cursor_x + (pb.left * scale);
                    const screen_r = cursor_x + (pb.right * scale);
                    const screen_t = cursor_y - (pb.top * scale);
                    const screen_b = cursor_y - (pb.bottom * scale);

                    const uv_l = ab.left / atlas_w;
                    const uv_r = ab.right / atlas_w;
                    const uv_t = (atlas_h - ab.top) / atlas_h;
                    const uv_b = (atlas_h - ab.bottom) / atlas_h;

                    const quads = [_]TextVertex{
                        .{ .pos = .{ screen_l, screen_t }, .uv = .{ uv_l, uv_t }, .color = text_color },
                        .{ .pos = .{ screen_l, screen_b }, .uv = .{ uv_l, uv_b }, .color = text_color },
                        .{ .pos = .{ screen_r, screen_t }, .uv = .{ uv_r, uv_t }, .color = text_color },
                        .{ .pos = .{ screen_r, screen_b }, .uv = .{ uv_r, uv_b }, .color = text_color },
                        .{ .pos = .{ screen_l, screen_b }, .uv = .{ uv_l, uv_b }, .color = text_color },
                        .{ .pos = .{ screen_r, screen_t }, .uv = .{ uv_r, uv_t }, .color = text_color },
                    };
                    try list.appendSlice(allocator, &quads);
                }
            }
            cursor_x += glyph.advance * scale;
        }
    }

    pub fn contains(self: Node, x: f32, y: f32) bool {
        if (x >= self.x and x <= self.x + W_NODE) {
            const H_NODE = self.computeNodeHeight();
            if (y >= self.y and y <= self.y + H_NODE) {
                return true;
            }
        }

        return false;
    }
};
