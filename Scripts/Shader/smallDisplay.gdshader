// Shader for an analog display box with curvature, vignette, and a gleam effect.
shader_type canvas_item;

// ## Shader Parameters ##
uniform vec4 box_color : source_color = vec4(0.2, 0.18, 0.22, 1.0);     // Dark grayish-brown for the main box
uniform vec4 line_color : source_color = vec4(0.35, 0.35, 0.38, 1.0);    // Slightly lighter gray for lines
uniform float corner_radius : hint_range(0.0, 0.5) = 0.1;               // How rounded the corners are
uniform float line_thickness : hint_range(0.001, 0.01) = 0.003;         // Thickness of the dividing lines
uniform float line_position1 : hint_range(0.0, 1.0) = 0.33;             // Position of the first line
uniform float line_position2 : hint_range(0.0, 1.0) = 0.67;             // Position of the second line

// Gleam effect parameters
uniform vec4 gleam_color : source_color = vec4(1.0, 1.0, 1.0, 0.1);      // Color and intensity of the gleam
uniform float gleam_speed : hint_range(0.0, 1.0) = 0.15;                // How fast the gleam moves
uniform float gleam_width : hint_range(0.0, 1.0) = 0.2;                 // Width of the gleam band

// Monitor effect parameters
uniform float curvature_amount : hint_range(0.0, 0.5) = 0.1;            // How much the screen curves inwards
uniform float vignette_intensity : hint_range(0.0, 1.0) = 0.5;          // How dark the corners and edges are
uniform float vignette_softness : hint_range(0.1, 2.0) = 0.8;           // The falloff curve of the vignette

// --- NEW DIRTY GLASS PARAMETERS ---
uniform float dirt_intensity : hint_range(0.0, 1.0) = 0.05;             // How visible the dirt/scratches are
uniform float dirt_scale : hint_range(1.0, 100.0) = 50.0;               // The scale/graininess of the dirt

// We need a simple hash function for the dirt effect.
float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
    // --- 1. Screen Curvature (Inverted) ---
    // MODIFIED: Changed the formula to create an inward "pincushion" curve.
    vec2 centered_uv = UV - 0.5;
    float dist_from_center = length(centered_uv);
    vec2 warped_uv = 0.5 + centered_uv * (1.0 + curvature_amount * dist_from_center * dist_from_center);
    
    // Now we proceed with the original logic, but using 'warped_uv' instead of 'UV'.
    vec2 pos = warped_uv - vec2(0.5);
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
        // --- 2. Draw Box and Lines ---
        COLOR = box_color;
        float current_x_uv = warped_uv.x; 
        if (abs(current_x_uv - line_position1) < line_thickness / 2.0 ||
            abs(current_x_uv - line_position2) < line_thickness / 2.0) {
            COLOR = line_color;
        }

        // --- 3. Gleam Effect ---
        float gleam_path = warped_uv.x + warped_uv.y;
        float animated_path = fract((gleam_path - TIME * gleam_speed) * 0.5) * 2.0;
        float gleam_intensity = smoothstep(0.0, gleam_width, animated_path) - smoothstep(gleam_width, gleam_width * 2.0, animated_path);
        COLOR.rgb = mix(COLOR.rgb, gleam_color.rgb, gleam_intensity * gleam_color.a);
        
        // --- 4. Vignette Effect ---
        float vignette = 1.0 - pow(length(centered_uv * 1.414), vignette_softness) * vignette_intensity;
        COLOR.rgb *= vignette;

        // --- 5. NEW: Dirty Glass Effect ---
        // Adds a layer of fine-grained noise to simulate dust or scratches.
        float dirt_noise = hash(UV * dirt_scale);
        COLOR.rgb -= dirt_noise * dirt_intensity;

    } else {
        COLOR = vec4(0.0); // Transparent
    }
}