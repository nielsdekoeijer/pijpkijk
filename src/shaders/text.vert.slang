[[vk::binding(0, 0)]]
cbuffer ViewUniforms {
    float2 screen_size;
    float2 camera_pos;
    float scale;
}

struct VertexInput {
    [[vk::location(0)]] float3 position : POSITION;
    [[vk::location(1)]] float4 color : COLOR;
    [[vk::location(2)]] float2 uv : TEXCOORD0; 
};

struct VertexOutput {
    float4 position : SV_Position;
    [[vk::location(0)]] float4 color : COLOR;
    [[vk::location(1)]] float2 uv : TEXCOORD0; 
};

[shader("vertex")]
VertexOutput main(VertexInput input) {
    VertexOutput output;

    // Transform the coordiantes into clip space, since our z component is [0, MAX_NODES] we must normalize it
    // by dividing by an arbitrarily large number.
    float2 transformed_pos = (input.position.xy - camera_pos) * scale;
    float2 ndc = (transformed_pos / screen_size) * 2.0 - 1.0;
    output.position = float4(ndc.x, ndc.y, input.position.z / 100000, 1.0);

    output.color = input.color;
    output.uv = input.uv;

    return output;
}
