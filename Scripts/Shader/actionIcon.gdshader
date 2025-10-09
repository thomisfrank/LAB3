shader_type canvas_item;

uniform vec4 border_color : source_color = vec4(0.9, 0.9, 0.9, 1.0);
uniform vec4 fill_color   : source_color = vec4(0.2, 0.7, 0.3, 1.0);
uniform float corner_radius : hint_range(0.0, 0.5) = 0.15;
uniform float border_thickness : hint_range(0.0, 0.5) = 0.05;
uniform float fill_alpha : hint_range(0.0, 1.0) = 1.0;

float rounded_box_sdf(vec2 p, vec2 size, float radius) {
    vec2 q = abs(p) - size + radius;
    return length(max(q, 0.0)) - radius;
}

void fragment() {
    // UV centered at (0,0)
    vec2 uv = UV * 2.0 - 1.0;

    // Adjust shape to stay within visible area
    vec2 outer_size = vec2(1.0 - border_thickness);
    float outer_radius = corner_radius;

    // Outer and inner box distances
    float outer = rounded_box_sdf(uv, outer_size, outer_radius);
    float inner = rounded_box_sdf(uv, outer_size - vec2(border_thickness), outer_radius - border_thickness);

    float aa = fwidth(outer) * 1.5; // anti-alias width

    // Border mask (the ring between outer and inner)
    float border_mask = smoothstep(aa, -aa, outer) - smoothstep(aa, -aa, inner);

    // Fill mask (inside the inner shape)
    float fill_mask = smoothstep(aa, -aa, inner);

    // Compose colors
    vec4 border_col = border_color * border_mask;
    vec4 fill_col = vec4(fill_color.rgb, fill_color.a * fill_alpha) * fill_mask;

    // Blend fill over border
    COLOR = mix(border_col, fill_col, fill_col.a);
}
