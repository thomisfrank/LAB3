// Shader for applying a gleam effect to an existing texture (like your PNG).
shader_type canvas_item;

// ## Shader Parameters ##
// The gleam effect parameters remain the same.
uniform vec4 gleam_color : source_color = vec4(1.0, 1.0, 1.0, 0.1);       // Color and intensity of the gleam (default: faint white)
uniform float gleam_speed : hint_range(0.0, 1.0) = 0.15;                 // How fast the gleam moves
uniform float gleam_width : hint_range(0.0, 1.0) = 0.2;                  // Width of the gleam band

void fragment() {
    // 1. Get the color of the underlying texture (your PNG image).
    vec4 base_color = texture(TEXTURE, UV);
    
    // Check if the pixel is part of the image (i.e., not transparent).
    // We only want to apply the gleam where the image actually exists.
    if (base_color.a > 0.0) {
        
        // --- Gleam Effect Logic (same as before) ---
        // 1. Define a diagonal line based on the UV coordinates.
        float gleam_path = UV.x + UV.y;
        
        // 2. Animate the path over time.
        float animated_path = fract(gleam_path - TIME * gleam_speed * 2.0);

        // 3. Create a soft band using smoothstep. This calculates the gleam's intensity.
        float gleam_intensity = smoothstep(0.0, gleam_width, animated_path) - smoothstep(gleam_width, gleam_width * 2.0, animated_path);
        
        // 4. Blend the gleam color with the base texture color.
        // We use mix() to blend the gleam on top of the texture's color, 
        // controlled by the calculated intensity and the gleam's alpha (gleam_color.a).
        base_color.rgb = mix(base_color.rgb, gleam_color.rgb, gleam_intensity * gleam_color.a);
        
        // Set the final color
        COLOR = base_color;

    } else {
        // The pixel is transparent (outside your image shape), so keep it transparent.
        COLOR = vec4(0.0); 
    }
}