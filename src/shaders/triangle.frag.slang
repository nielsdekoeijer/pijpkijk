[[vk::binding(0, 0)]]
cbuffer ViewUniforms {
    float2 screen_size;
    float2 camera_pos;
}

struct FragmentInput {
    float4 position : SV_Position;
    [[vk::location(0)]] float4 color : COLOR;
    [[vk::location(1)]] float2 local_pos : TEXCOORD0;
    [[vk::location(2)]] float2 half_size : TEXCOORD1;
    [[vk::location(3)]] float4 radii : RADIUS;
};

[shader("fragment")]
float4 main(FragmentInput input) : SV_Target {
    float2 p = input.local_pos;
    float2 b = input.half_size;

    // Pick the right radius based on the quadrant: { bottom-right, top-right, bottom-left, top-left }
    float2 r_xy = (p.x > 0.0) ? input.radii.xy : input.radii.zw;
    float r_final = (p.y > 0.0) ? r_xy.x : r_xy.y;

    // Compute exact Signed Distance for rounded boxes
    float2 q = abs(p) - b + r_final;
    float dist = min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r_final;

    // Smooth anti-aliased edge scaled exactly to physical pixels
    float pixel_size = 1.0;
    float alpha = smoothstep(pixel_size, -pixel_size, dist);

    if (alpha <= 0.0) discard;

    return float4(input.color.rgb, input.color.a * alpha);
}
