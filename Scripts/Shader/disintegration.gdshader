shader_type canvas_item;

// Controls the size of the pixel blocks
uniform int pixel_amount : hint_range(2, 200) = 50;

// ✨ Controls the dissolve effect from 0.0 (visible) to 1.0 (gone)
uniform float progress : hint_range(0.0, 1.0) = 0.0;

// Defines a bright color for the edge of the dissolving area
uniform vec4 edge_color : source_color = vec4(1.5, 1.5, 1.5, 1.0); // Brighter than white for a "bloom" effect
uniform float edge_width : hint_range(0.0, 0.1) = 0.04;

// A simple pseudo-random number generator
float rand(vec2 co){
    return fract(sin(dot(co.xy, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	// 1. Calculate the UV for the pixelated grid.
	// This makes sure we operate on whole "blocks" of pixels.
	vec2 grid_uv = round(UV * float(pixel_amount)) / float(pixel_amount);
	
	// 2. Sample the original texture using the pixelated UV.
	vec4 color = texture(TEXTURE, grid_uv);
	
	// 3. Generate a random, stable threshold for each pixel block.
	float threshold = rand(grid_uv);
	
	// 4. Compare the progress to the block's threshold to decide its state.
	if (progress > threshold) {
		// If progress has passed the threshold, this pixel disappears.
		color.a = 0.0;
	} else if (progress > threshold - edge_width) {
		// If we are on the "edge" of dissolving, mix in the bright edge color.
		color.rgb = mix(color.rgb, edge_color.rgb, edge_color.a);
	}
	
	COLOR = color;
}