[[vk::binding(0, 0)]]
cbuffer ViewUniforms {
    float2 screen_size;
    float2 cube_pos;
}

struct VertexInput {
    [[vk::location(0)]] float2 position : POSITION;
    [[vk::location(1)]] float4 color : COLOR;
};

struct VertexOutput {
    float4 position : SV_Position;
    [[vk::location(0)]] float4 color : COLOR;
};

[shader("vertex")]
VertexOutput main(VertexInput input) {
    VertexOutput output;
    
    float2 transformed_pos = input.position + cube_pos;
    float2 ndc = (transformed_pos / screen_size) * 2.0 - 1.0;
    output.position = float4(ndc.x, ndc.y, 0.0, 1.0);
    output.color = input.color;
    
    return output;
}
