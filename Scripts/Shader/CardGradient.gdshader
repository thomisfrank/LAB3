shader_type canvas_item;

// three key colors
uniform vec4 color_light : source_color = vec4(0.506, 0.878, 0.576, 1.0);
uniform vec4 color_mid   : source_color = vec4(0.153, 0.682, 0.376, 1.0);
uniform vec4 color_dark  : source_color = vec4(0.063, 0.322, 0.173, 1.0);

// --- NEW CONTROLS ---
// These are now editable in the Inspector.
// I've pushed the dark radius up for you as a starting point.
uniform float radius_light : hint_range(0.0, 1.0) = 0.40;
uniform float radius_mid   : hint_range(0.0, 1.0) = 0.40;
uniform float radius_dark  : hint_range(0.0, 1.0) = 0.70;

// motion / blending controls
uniform float swirl_speed = 0.30;
uniform float softness = 0.70;
uniform float diffusion = 2.20;
uniform float glow = 0.50;

// subtle line controls
uniform float line_freq = 36.0;   // spacing of the lines, higher is tighter
uniform float line_amp = 0.08;    // strength of the lines, keep small
uniform float line_speed = 0.22;  // how fast the lines drift
uniform float noise_scale = 2.4;  // global noise scale
const int FBM_OCTAVES = 4;        // fbm detail

// hash / noise / fbm (small, cheap implementations)
float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1,311.7))) * 43758.5453123);
}

float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    float a = hash(i + vec2(0.0,0.0));
    float b = hash(i + vec2(1.0,0.0));
    float c = hash(i + vec2(0.0,1.0));
    float d = hash(i + vec2(1.0,1.0));
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 p) {
    float v = 0.0;
    float amp = 0.5;
    float freq = 1.0;
    for (int i = 0; i < FBM_OCTAVES; i++) {
        v += amp * noise(p * freq);
        freq *= 2.0;
        amp *= 0.5;
    }
    return v;
}

// soft gaussian-like field for each color zone
float field(vec2 uv, vec2 center, float radius) {
    float d = length(uv - center);
    return exp(-pow(d / radius, diffusion));
}

void fragment() {
    vec2 uv = UV;
    float t = TIME * swirl_speed;

    // moving centers with tiny fbm perturbation for organic motion
    vec2 c1 = vec2(0.5 + sin(t * 0.6) * 0.35, 0.5 + cos(t * 0.4) * 0.35);
    c1 += (fbm(c1 * noise_scale + vec2(12.0, 4.0)) - 0.5) * 0.08;

    vec2 c2 = vec2(0.5 + cos(t * 0.5) * 0.4, 0.5 + sin(t * 0.7) * 0.3);
    c2 += (fbm(c2 * noise_scale + vec2(7.0, 9.0)) - 0.5) * 0.08;

    vec2 c3 = vec2(0.5 + sin(t * 0.9) * 0.45, 0.5 + cos(t * 0.8) * 0.25);
    c3 += (fbm(c3 * noise_scale + vec2(3.0, 6.0)) - 0.5) * 0.08;

    // base field influences now use the new uniform variables
    float f1 = field(uv, c1, radius_light);
    float f2 = field(uv, c2, radius_mid);
    float f3 = field(uv, c3, radius_dark);

    // build a flow vector from fbm, center it around zero and normalize mildly
    vec2 flow = vec2(fbm(uv * noise_scale + vec2(0.0, 0.0)),
                     fbm(uv * noise_scale + vec2(5.2, 1.3)));
    flow = (flow - 0.5) * 2.0;
    float flow_len = length(flow);
    vec2 ng = (flow_len > 0.001) ? (flow / (flow_len + 0.0001)) : vec2(1.0, 0.0);

    // stripe phase along the local flow, with extra jitter from fbm
    float phase = dot(uv, ng) * line_freq
                + fbm(uv * noise_scale * 1.5) * 2.0
                + TIME * line_speed;

    // stripe shape, sharpen but keep soft with a pow
    float stripe = pow(abs(sin(phase)), 1.5);
    float line = stripe * line_amp; // final line amplitude, keep tiny

    // gently modulate each field by the line so ridges appear without hard edges
    f1 *= 1.0 + line * 0.28;
    f2 *= 1.0 + line * 0.20;
    f3 *= 1.0 + line * 0.24;

    // weighted blend across three colors
    vec4 col = color_light * f1 + color_mid * f2 + color_dark * f3;
    float total = f1 + f2 + f3 + 0.0001;
    col /= total;

    // apply subtle tonal contrast driven by the line, this makes the stripe visible
    // while staying soft. tweak the multipliers to get lighter or darker ridges.
    col.rgb = mix(col.rgb * (1.0 - line * 0.20), col.rgb * (1.0 + line * 0.06), 0.5);

    // glow from overlaps
    float glow_factor = pow(total, 1.3) * glow;
    col.rgb += glow_factor * 0.12;

    // final tone curve for softness
    col.rgb = pow(col.rgb, vec3(1.0 / (1.0 + softness)));

    COLOR = col;
}