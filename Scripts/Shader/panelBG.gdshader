// Shader for a chaotic, swirling liquid smoke effect.
shader_type canvas_item;

// ## Shader Parameters ##
// You can change these values in the Godot Inspector to customize the effect.
uniform vec4 color1 : source_color = vec4(0.05, 0.05, 0.15, 1.0); // Dark metallic blue
uniform vec4 color2 : source_color = vec4(0.6, 0.7, 0.8, 1.0);   // Light steel blue
uniform float speed : hint_range(0.0, 0.5) = 0.08;              // How fast the smoke swirls
uniform float zoom : hint_range(1.0, 10.0) = 4.0;                // The scale of the smoke pattern
uniform float distortion : hint_range(0.0, 2.0) = 0.5;           // How intense the swirling motion is
uniform int octaves : hint_range(1, 8) = 5;                      // How many layers of noise to add for detail

// 2D Random function
float random(vec2 st) {
    return fract(sin(dot(st.xy, vec2(12.9898, 78.233))) * 43758.5453123);
}

// 2D Simplex Noise function
float noise(vec2 st) {
    vec2 i = floor(st);
    vec2 f = fract(st);
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(random(i + vec2(0.0, 0.0)), random(i + vec2(1.0, 0.0)), u.x),
               mix(random(i + vec2(0.0, 1.0)), random(i + vec2(1.0, 1.0)), u.x), u.y);
}

// Fractal Brownian Motion (FBM) - layers multiple noise patterns for detail.
float fbm(vec2 st) {
    float value = 0.0;
    float amplitude = 0.5;
    for (int i = 0; i < octaves; i++) {
        value += amplitude * noise(st);
        st *= 2.0;
        amplitude *= 0.5;
    }
    return value;
}

// Main function that runs for every pixel.
void fragment() {
    // Get the pixel's coordinate, scaled by the zoom factor.
    vec2 uv = UV * zoom;

    // --- Chaotic Swirl Logic ---
    // Instead of moving the UVs in one direction, we will distort them
    // using another animated noise pattern. This creates a turbulent, swirling motion.
    
    // 1. Create two separate time-shifted coordinates for the distortion noise.
    vec2 motion_uv1 = uv + vec2(TIME * speed, TIME * speed);
    vec2 motion_uv2 = uv + vec2(TIME * -speed, TIME * -speed + 15.0); // Offset to de-correlate
    
    // 2. Calculate two noise values to create a distortion vector.
    float motion_x = fbm(motion_uv1);
    float motion_y = fbm(motion_uv2);

    // 3. Apply the distortion to the original UV coordinates.
    // The 'distortion' parameter controls the strength of the effect.
    vec2 distorted_uv = uv + vec2(motion_x, motion_y) * distortion;

    // 4. Calculate the final smoke pattern using the distorted coordinates.
    float noise_value = fbm(distorted_uv);
    
    // Mix the two colors based on the final noise value to create the gradient.
    vec4 final_color = mix(color1, color2, noise_value);

    // Set the pixel's color.
    COLOR = final_color;
}