shader_type canvas_item;

// The main color of the shape.
uniform vec4 fill_color : source_color = vec4(0.2, 0.26, 0.35, 1.0);
// The resolution of the virtual pixel grid. For a 32x32 sprite, set this to 32 for a perfect 1:1 pixel effect.
uniform float pixel_grid_size : hint_range(1.0, 128.0) = 32.0; 
// How many "pixels" deep the corner cut should be. A value of 3 matches your image.
uniform int corner_size : hint_range(0, 16) = 3; 

void fragment() {
	// Calculate our position on the virtual pixel grid (e.g., from (0,0) to (31,31)).
	vec2 pixel_coord = floor(UV * pixel_grid_size);
	
	// Convert corner_size to a float for calculations.
	float corner = float(corner_size);

	// --- Check Top-Left Corner ---
	// Is the current pixel within the top-left corner's bounding box?
	if (pixel_coord.x < corner && pixel_coord.y < corner) {
		// If its coordinates added together are less than the size, it's part of the cut.
		if (pixel_coord.x + pixel_coord.y < corner) {
			discard; // Make the pixel transparent.
		}
	}
	
	// --- Check Top-Right Corner ---
	float px_from_right = pixel_grid_size - pixel_coord.x - 1.0;
	if (px_from_right < corner && pixel_coord.y < corner) {
		if (px_from_right + pixel_coord.y < corner) {
			discard;
		}
	}
	
	// --- Check Bottom-Left Corner ---
	float px_from_bottom = pixel_grid_size - pixel_coord.y - 1.0;
	if (pixel_coord.x < corner && px_from_bottom < corner) {
		if (pixel_coord.x + px_from_bottom < corner) {
			discard;
		}
	}
	
	// --- Check Bottom-Right Corner ---
	if (px_from_right < corner && px_from_bottom < corner) {
		if (px_from_right + px_from_bottom < corner) {
			discard;
		}
	}

	// If the pixel wasn't discarded, draw it with the fill color.
	COLOR = fill_color;
}