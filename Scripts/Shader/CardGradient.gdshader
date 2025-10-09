shader_type canvas_item;

uniform float speed = 0.3;
uniform vec4 color_a : source_color = vec4(1.0, 0.5, 0.8, 1.0);
uniform vec4 color_b : source_color = vec4(0.3, 0.6, 1.0, 1.0);
uniform float scale = 2.5;

void fragment() {
    vec2 center = UV - vec2(0.5);
    float dist = length(center) * scale;
    float t = 0.5 + 0.5 * sin(dist - TIME * speed);
    COLOR = mix(color_a, color_b, t);
}
