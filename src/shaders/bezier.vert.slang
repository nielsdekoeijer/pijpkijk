[[vk::binding(0, 0)]]
cbuffer ViewUniforms {
    float2 screen_size;
    float2 camera_pos;
    float scale;
}

struct VertexInput {
    [[vk::location(0)]] float2 pos : POSITION;
    [[vk::location(1)]] float2 p0 : P0;
    [[vk::location(2)]] float2 p1 : P1;
    [[vk::location(3)]] float2 p2 : P2;
    [[vk::location(4)]] float2 p3 : P3;
    [[vk::location(5)]] float4 color : COLOR;
    [[vk::location(6)]] float thickness: THICKNESS;
};

struct VertexOutput {
    float4 position : SV_Position;
    [[vk::location(0)]] float2 p0 : P0;
    [[vk::location(1)]] float2 p1 : P1;
    [[vk::location(2)]] float2 p2 : P2;
    [[vk::location(3)]] float2 p3 : P3;
    [[vk::location(4)]] float4 color : COLOR;
    [[vk::location(5)]] float thickness: THICKNESS;
};

[shader("vertex")]
VertexOutput main(VertexInput input) {
    VertexOutput output;

    // Apply global camera transform
    float2 transformed_pos = (input.pos - camera_pos) * scale;
    float2 ndc = (transformed_pos / screen_size) * 2.0 - 1.0;
    output.position = float4(ndc.x, ndc.y, 0.0, 1.0);

    // Transform control points to screen space for the frag shader
    output.p0 = (input.p0 - camera_pos) * scale;
    output.p1 = (input.p1 - camera_pos) * scale;
    output.p2 = (input.p2 - camera_pos) * scale;
    output.p3 = (input.p3 - camera_pos) * scale;
    output.thickness = input.thickness * scale;
    
    output.color = input.color;
    return output;
}
