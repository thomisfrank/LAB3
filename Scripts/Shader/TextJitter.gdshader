shader_type canvas_item;

// jitter_rate: Speed of text jitter
uniform float jitter_rate : hint_range(1.0, 30.0) = 8.0;
// jitter_amount: Amount of text jitter
uniform float jitter_amount : hint_range(0.0, 0.02) = 0.003;

// Hash function: gives more "random"-looking values than plain sin
float hash(float n) {
    return fract(sin(n) * 43758.5453123);
}

void fragment() {
    float step = TIME * jitter_rate;

    // Frame steps
    float i0 = floor(step);
    float i1 = i0 + 1.0;
    float f = fract(step); // interpolation factor

    // Random offsets for current and next frame
    vec2 offset0 = vec2(
        hash(i0 * 12.9898) - 0.5,
        hash(i0 * 78.233) - 0.5
    ) * jitter_amount;

    vec2 offset1 = vec2(
        hash(i1 * 19.123) - 0.5,
        hash(i1 * 93.321) - 0.5
    ) * jitter_amount;

    // Smooth bounce: ease with smoothstep instead of linear
    float ease = f * f * (3.0 - 2.0 * f);
    vec2 jitter_offset = mix(offset0, offset1, ease);

    COLOR = texture(TEXTURE, UV + jitter_offset) * COLOR;
}