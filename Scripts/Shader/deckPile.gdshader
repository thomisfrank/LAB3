shader_type canvas_item;

uniform vec4 fill_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 outline_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float pixel_grid_size : hint_range(1.0, 128.0) = 32.0; 
uniform int corner_size : hint_range(0, 16) = 3;

// Helper function to determine if a given coordinate is inside the shape.
float is_inside_shape(vec2 coord) {
	// Boundary check for the main rectangle
	if (coord.x < 0.0 || coord.x >= pixel_grid_size || coord.y < 0.0 || coord.y >= pixel_grid_size) {
		return 0.0; // Outside
	}
	
	float corner = float(corner_size);
	
	// --- Symmetrical Corner Checks ---
	// Create a mirrored coordinate for each corner and test it.
	vec2 tc = coord; // Top-left
	vec2 mirrored_tc = vec2(pixel_grid_size - 1.0 - coord.x, coord.y); // Top-right
	
	if (tc.x < corner && tc.y < corner && tc.x + tc.y < corner) { return 0.0; }
	if (mirrored_tc.x < corner && mirrored_tc.y < corner && mirrored_tc.x + mirrored_tc.y < corner) { return 0.0; }
	
	tc = vec2(coord.x, pixel_grid_size - 1.0 - coord.y); // Bottom-left
	mirrored_tc = vec2(pixel_grid_size - 1.0 - coord.x, pixel_grid_size - 1.0 - coord.y); // Bottom-right
	
	if (tc.x < corner && tc.y < corner && tc.x + tc.y < corner) { return 0.0; }
	if (mirrored_tc.x < corner && mirrored_tc.y < corner && mirrored_tc.x + mirrored_tc.y < corner) { return 0.0; }
	
	return 1.0; // Inside
}


void fragment() {
	vec2 pixel_coord = floor(UV * pixel_grid_size);
	
	// Check if the current pixel is inside the shape. If not, discard it.
	if (is_inside_shape(pixel_coord) < 0.5) {
		discard;
	}
	
	// Check the four direct neighbors to determine if this is a border pixel.
	float total = 0.0;
	total += is_inside_shape(pixel_coord + vec2(0, 1));
	total += is_inside_shape(pixel_coord + vec2(0, -1));
	total += is_inside_shape(pixel_coord + vec2(1, 0));
	total += is_inside_shape(pixel_coord + vec2(-1, 0));
	
	// If the sum is less than 4, at least one neighbor was outside the shape.
	if (total < 4.0) {
		COLOR = outline_color;
	} else {
		COLOR = fill_color;
	}
}