[[vk::binding(1, 0)]] Sampler2D<float4> font_atlas;

struct FragmentInput {
    float4 position : SV_Position;
    [[vk::location(0)]] float4 color : COLOR;
    [[vk::location(1)]] float2 uv : TEXCOORD0; 
};

// Helper function to find the middle value of the 3 color channels
float median(float r, float g, float b) {
    return max(min(r, g), min(max(r, g), b));
}

[shader("fragment")]
float4 main(FragmentInput input) : SV_Target {
    // 1. Sample the multi-channel distance field
    float4 sample = font_atlas.Sample(input.uv);
    
    // 2. The true edge is the median of the RGB channels
    float sd = median(sample.r, sample.g, sample.b);
    
    // 3. Gold-standard MSDF anti-aliasing 
    // This value MUST match the '-pxrange' flag in your build.zig (we used 4.0)
    float px_range = 4.0; 
    
    // Get the physical dimensions of the texture atlas
    uint tex_w, tex_h;
    font_atlas.GetDimensions(tex_w, tex_h);
    float2 atlas_size = float2(tex_w, tex_h);
    
    // Calculate how physical screen pixels map to texture UVs
    // fwidth() tells us how much the UV changes from one pixel to the next
    float2 msdf_unit = px_range / atlas_size;
    float screen_px_range = max(0.5 * dot(msdf_unit, 1.0 / fwidth(input.uv)), 1.0);
    
    // The distance is normalized 0.0 to 1.0, where 0.5 is exactly on the font outline
    float screen_px_distance = screen_px_range * (sd - 0.5);
    
    // Clamp to get our final anti-aliased alpha
    float alpha = clamp(screen_px_distance + 0.5, 0.0, 1.0);
    
    if (alpha <= 0.0) discard;
    
    // NOTE: Because we generated an MTSDF, the alpha channel (sample.a) contains 
    // a true SDF. You can use sample.a to easily draw shadows or outlines later!
    
    return float4(input.color.rgb, input.color.a * alpha);
}
