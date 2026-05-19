const std = @import("std");
const c = @import("c.zig").c;

pub const Mat4 = extern struct {
    data: [16]f32,
};

pub const Vec4 = extern struct {
    x: f32,
    y: f32,
    z: f32,
    w: f32,
};

pub const Vec3 = extern struct {
    x: f32,
    y: f32,
    z: f32,
};

pub const Uniform = struct {
    screen_size: [2]f32,
    cube_pos: [2]f32, 
};

pub const Vertex = extern struct {
    pos: [2]f32,
    color: [4]f32,

    pub fn getVkBindingDiscription() [1]c.VkVertexInputBindingDescription {
        return [_]c.VkVertexInputBindingDescription{
            .{
                .binding = 0,
                .stride = @sizeOf(Vertex),
                .inputRate = c.VK_VERTEX_INPUT_RATE_VERTEX,
            },
        };
    }

    pub fn getVkAttributeDiscription() [2]c.VkVertexInputAttributeDescription {
        return [_]c.VkVertexInputAttributeDescription{
            // Location 0: Position (float2)
            .{
                .location = 0,
                .binding = 0,
                .format = c.VK_FORMAT_R32G32_SFLOAT,
                .offset = @offsetOf(Vertex, "pos"),
            },
            // Location 1: Color (float4)
            .{
                .location = 1,
                .binding = 0,
                .format = c.VK_FORMAT_R32G32B32A32_SFLOAT,
                .offset = @offsetOf(Vertex, "color"),
            },
        };
    }
};
