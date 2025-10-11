// Shader for applying monitor effects (gleam, curve, etc.) to an existing texture.
shader_type canvas_item;

// ## Shader Parameters ##
uniform vec4 gleam_color : source_color = vec4(1.0, 1.0, 1.0, 0.1);
uniform float gleam_speed : hint_range(0.0, 1.0) = 0.15;
uniform float gleam_width : hint_range(0.0, 1.0) = 0.2;
uniform float curvature_amount : hint_range(0.0, 0.5) = 0.1;
uniform float vignette_intensity : hint_range(0.0, 1.0) = 0.5;
uniform float vignette_softness : hint_range(0.1, 2.0) = 0.8;
uniform float dirt_intensity : hint_range(0.0, 1.0) = 0.05;
uniform float dirt_scale : hint_range(1.0, 100.0) = 50.0;
uniform float white_protection_threshold : hint_range(0.8, 1.0) = 0.98;

// --- NEW STATIC PARAMETERS ---
uniform vec4 static_color : source_color = vec4(0.7, 0.8, 0.75, 0.03); // Faint greenish-white static color and alpha
uniform float static_intensity : hint_range(0.0, 0.1) = 0.03;         // How strong the static effect is
uniform float static_scale : hint_range(1.0, 200.0) = 150.0;          // Size/graininess of the static

float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
    // --- 1. Screen Curvature ---
    vec2 centered_uv = UV - 0.5;
    float dist_from_center = length(centered_uv);
    vec2 warped_uv = 0.5 + centered_uv * (1.0 + curvature_amount * dist_from_center * dist_from_center);

    // --- 2. Texture Sampling ---
    vec4 base_color = texture(TEXTURE, warped_uv);
    
    if (base_color.a > 0.0) {
        
        // --- Check if the pixel is 'white' ---
        bool is_white = (base_color.r > white_protection_threshold && 
                         base_color.g > white_protection_threshold && 
                         base_color.b > white_protection_threshold);

        // --- 3. Gleam Effect (applied to everything) ---
        float gleam_path = warped_uv.x + warped_uv.y;
        float animated_path = fract((gleam_path - TIME * gleam_speed) * 0.5) * 2.0;
        float gleam_intensity = smoothstep(0.0, gleam_width, animated_path) - smoothstep(gleam_width, gleam_width * 2.0, animated_path);
        base_color.rgb = mix(base_color.rgb, gleam_color.rgb, gleam_intensity * gleam_color.a);

        // --- Only apply darkening effects if the pixel is NOT white ---
        if (!is_white) {
            // --- 4. Vignette Effect ---
            float vignette = 1.0 - pow(length(centered_uv * 1.414), vignette_softness) * vignette_intensity;
            base_color.rgb *= vignette;

            // --- 5. Dirty Glass Effect ---
            float dirt_noise = hash(UV * dirt_scale);
            base_color.rgb -= dirt_noise * dirt_intensity;
        }
        
        // --- 6. NEW: Color Static / Gaussian Overlay ---
        // Generates animated noise and mixes it with the base color.
        float static_noise = hash(UV * static_scale + TIME * 2.0) - 0.5; // Offset by -0.5 to get values from -0.5 to 0.5
        vec3 static_overlay = static_color.rgb * static_noise * static_intensity;
        
        // Blend the static_overlay with the base_color.
        // We use a small 'static_color.a' (alpha) to control its overall opacity.
        base_color.rgb = mix(base_color.rgb, base_color.rgb + static_overlay, static_color.a);

        COLOR = base_color;

    } else {
        COLOR = vec4(0.0); 
    }
}