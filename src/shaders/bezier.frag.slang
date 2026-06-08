struct FragmentInput {
    float4 position : SV_Position;
    [[vk::location(0)]] float2 p0;
    [[vk::location(1)]] float2 p1;
    [[vk::location(2)]] float2 p2;
    [[vk::location(3)]] float2 p3;
    [[vk::location(4)]] float4 color_beg;
    [[vk::location(5)]] float4 color_end;
    [[vk::location(6)]] float thickness;
};

// Evaluate Cubic Bezier at t
float2 get_bezier_point(float t, float2 p0, float2 p1, float2 p2, float2 p3) {
    float inv_t = 1.0 - t;
    return inv_t * inv_t * inv_t * p0 + 
           3.0 * inv_t * inv_t * t * p1 + 
           3.0 * inv_t * t * t * p2 + 
           t * t * t * p3;
}

// Derivative of Cubic Bezier for Newton-Raphson
float2 get_bezier_derivative(float t, float2 p0, float2 p1, float2 p2, float2 p3) {
    float inv_t = 1.0 - t;
    return 3.0 * inv_t * inv_t * (p1 - p0) + 
           6.0 * inv_t * t * (p2 - p1) + 
           3.0 * t * t * (p3 - p2);
}

[shader("fragment")]
float4 main(FragmentInput input) : SV_Target {
    float2 pixel_pos = input.position.xy;
    
    // 1. Initial guess for t (project pixel onto the P0-P3 line)
    float t = 0.5; 
    
    // 2. Newton-Raphson iterations to find the closest point on curve
    for (int i = 0; i < 8; i++) {
        float2 point = get_bezier_point(t, input.p0, input.p1, input.p2, input.p3);
        float2 deriv = get_bezier_derivative(t, input.p0, input.p1, input.p2, input.p3);
        
        // Minimize distance function f(t) = dot(point - pixel, deriv)
        float2 diff = point - pixel_pos;
        t -= dot(diff, deriv) / dot(deriv, deriv);
        t = clamp(t, 0.0, 1.0);
    }

    // 3. Distance calculation
    float2 closest = get_bezier_point(t, input.p0, input.p1, input.p2, input.p3);
    float dist = length(pixel_pos - closest);
    
    // 4. Anti-aliasing
    float aa_width = 1.5;
    float alpha = 1.0 - smoothstep(input.thickness - aa_width, input.thickness, dist);
    
    if (alpha <= 0.0) discard;

    float4 base_color = lerp(input.color_beg, input.color_end, t);
    return float4(base_color.rgb, base_color.a * alpha);
}
