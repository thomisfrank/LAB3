// Shader for an analog display box with an animated gleam effect.
shader_type canvas_item;

// ## Shader Parameters ##
uniform vec4 box_color : source_color = vec4(0.2, 0.18, 0.22, 1.0);     // Dark grayish-brown for the main box
uniform vec4 line_color : source_color = vec4(0.35, 0.35, 0.38, 1.0);    // Slightly lighter gray for lines
uniform float corner_radius : hint_range(0.0, 0.5) = 0.1;               // How rounded the corners are
uniform float line_thickness : hint_range(0.001, 0.01) = 0.003;         // Thickness of the dividing lines
uniform float line_position1 : hint_range(0.0, 1.0) = 0.33;             // Position of the first line
uniform float line_position2 : hint_range(0.0, 1.0) = 0.67;             // Position of the second line

// New parameters for the gleam effect
uniform vec4 gleam_color : source_color = vec4(1.0, 1.0, 1.0, 0.1);      // Color and intensity of the gleam (default: faint white)
uniform float gleam_speed : hint_range(0.0, 1.0) = 0.15;                // How fast the gleam moves
uniform float gleam_width : hint_range(0.0, 1.0) = 0.2;                 // Width of the gleam band

void fragment() {
    vec2 pos = UV - vec2(0.5); 
    vec2 size = TEXTURE_PIXEL_SIZE * SCREEN_PIXEL_SIZE;
    float aspect_ratio = size.x / size.y;
    vec2 scaled_pos = pos;
    scaled_pos.x *= aspect_ratio; 
    float half_width = 0.5 * aspect_ratio; 
    float half_height = 0.5;
    float r = corner_radius * min(half_width, half_height);
    vec2 corner_dist = abs(scaled_pos) - vec2(half_width - r, half_height - r);
    float dist = length(max(corner_dist, 0.0)) + min(max(corner_dist.x, corner_dist.y), 0.0) - r;

    if (dist < 0.0) {
        COLOR = box_color;
        float current_x_uv = UV.x; 
        if (abs(current_x_uv - line_position1) < line_thickness / 2.0 ||
            abs(current_x_uv - line_position2) < line_thickness / 2.0) {
            COLOR = line_color;
        }

        // --- Gleam Effect Logic ---
        // 1. Define a diagonal line based on the UV coordinates.
        //    Adding UV.x and UV.y creates a value that's constant along a diagonal.
        float gleam_path = UV.x + UV.y;
        
        // 2. Animate the path over time. We use `fract()` to make the gleam loop.
        //    The '2.0' in the expression stretches the path so the gleam fully crosses the screen.
        float animated_path = fract((gleam_path - TIME * gleam_speed) * 0.5) * 2.0;

        // 3. Create a soft band using smoothstep. This calculates the gleam's intensity.
        //    It fades in and out smoothly instead of having hard edges.
        float gleam_intensity = smoothstep(0.0, gleam_width, animated_path) - smoothstep(gleam_width, gleam_width * 2.0, animated_path);
        
        // 4. Add the gleam color to the existing color.
        //    We use mix() to blend the gleam on top of the box/line color.
        COLOR.rgb = mix(COLOR.rgb, gleam_color.rgb, gleam_intensity * gleam_color.a);

    } else {
        COLOR = vec4(0.0); // Transparent
    }
}