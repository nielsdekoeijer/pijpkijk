struct FragmentInput {
    float4 position : SV_Position;
    [[vk::location(0)]] float2 p0;
    [[vk::location(1)]] float2 p1;
    [[vk::location(2)]] float2 p2;
    [[vk::location(3)]] float2 p3;
    [[vk::location(4)]] float4 color_beg;
    [[vk::location(5)]] float4 color_end;
    [[vk::location(6)]] float thickness;
    [[vk::location(7)]] float is_selected;
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

// Run Newton-Raphson from a starting t, return best t found
float solve_nearest(float t_start, float2 pixel_pos, float2 p0, float2 p1, float2 p2, float2 p3) {
    float t = t_start;
    for (int i = 0; i < 8; i++) {
        float2 point = get_bezier_point(t, p0, p1, p2, p3);
        float2 deriv = get_bezier_derivative(t, p0, p1, p2, p3);
        float denom = dot(deriv, deriv);
        if (denom < 1e-6) break;
        t -= dot(point - pixel_pos, deriv) / denom;
        t = clamp(t, 0.0, 1.0);
    }
    return t;
}

[shader("fragment")]
float4 main(FragmentInput input) : SV_Target {
    float2 pixel_pos = input.position.xy;

    // Try multiple start points to avoid local minima on strong curves
    float best_t = 0.0;
    float best_dist = 1e10;

    float starts[5] = { 0.0, 0.25, 0.5, 0.75, 1.0 };
    for (int s = 0; s < 5; s++) {
        float t = solve_nearest(starts[s], pixel_pos, input.p0, input.p1, input.p2, input.p3);
        float2 pt = get_bezier_point(t, input.p0, input.p1, input.p2, input.p3);
        float d = length(pixel_pos - pt);
        if (d < best_dist) {
            best_dist = d;
            best_t = t;
        }
    }

    // Anti-aliasing
    float aa_width = 1.5;
    float alpha = 1.0 - smoothstep(input.thickness - aa_width, input.thickness, best_dist);
    if (alpha <= 0.0) discard;

    // Determine the color of the bezier
    float4 base_color = lerp(input.color_beg, input.color_end, best_t);
    if (input.is_selected > 0.5) {
        base_color.rgb = lerp(base_color.rgb, float3(1.0), 0.5);
    }

    return float4(base_color.rgb, base_color.a * alpha);
}
