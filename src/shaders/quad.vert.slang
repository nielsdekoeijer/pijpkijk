// Define global state, bound at (binding point 0, descriptor set 0)
[[vk::binding(0, 0)]]
cbuffer ViewUniforms {
    float2 screen_size;
    float2 camera_pos;
    float scale;
}

struct VertexInput {
    [[vk::location(0)]] float3 position : POSITION;
    [[vk::location(1)]] float4 color : COLOR;
    [[vk::location(2)]] float2 local_pos : TEXCOORD0;
    [[vk::location(3)]] float2 half_size : TEXCOORD1;
    [[vk::location(4)]] float4 radii : RADIUS;
};

struct VertexOutput {
    float4 position : SV_Position;
    [[vk::location(0)]] float4 color : COLOR;
    [[vk::location(1)]] float2 local_pos : TEXCOORD0;
    [[vk::location(2)]] float2 half_size : TEXCOORD1;
    [[vk::location(3)]] float4 radii : RADIUS;
};

 [shader("vertex")]

VertexOutput main(VertexInput input) {
    VertexOutput output;

    // Transform the coordiantes into clip space, since our z component is [0, MAX_NODES] we must normalize it
    // by dividing by an arbitrarily large number.
    float2 transformed_pos = (input.position.xy - camera_pos) * scale;
    float2 ndc = (transformed_pos / screen_size) * 2.0 - 1.0;
    output.position = float4(ndc.xy, input.position.z / 100000, 1.0);

    // Scale to apply zoom
    output.local_pos = input.local_pos * scale;
    output.half_size = input.half_size * scale;
    output.radii = input.radii * scale;

    output.color = input.color;

    return output;
}
