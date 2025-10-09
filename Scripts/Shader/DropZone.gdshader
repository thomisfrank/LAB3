shader_type canvas_item;

// --- Uniforms from CardBorder.gdshader ---
uniform vec4 fill_color : source_color = vec4(0.2, 0.26, 0.35, 1.0);
uniform float pixel_grid_size : hint_range(1.0, 128.0) = 32.0;
uniform int corner_size : hint_range(0, 16) = 3;
// ✨ New uniform to control the softness of the shape's edges
uniform float edge_feather : hint_range(0.0, 5.0) = 1.5;

// --- Uniforms from DigitalFilter.gdshader ---
uniform float strength : hint_range(0.0, 1.0) = 0.1;
uniform float aberration_amount : hint_range(0.0, 0.05) = 0.01;
uniform float opacity : hint_range(0.0, 1.0) = 1.0;
uniform float feather_amount : hint_range(0.0, 1.0) = 0.4;


// --- Helper Functions ---

// Pseudo-random number generator from DigitalFilter
float rand(vec2 co){
    return fract(sin(dot(co.xy ,vec2(12.9898,78.233))) * 43758.5453);
}

// This function is modified from your CardBorder logic.
// It now returns a smooth alpha (0.0 to 1.0) instead of a hard color,
// creating a soft-edged, anti-aliased shape.
float get_shape_alpha(vec2 sample_uv) {
	// Prevent wrapping artifacts
	if (sample_uv.x < 0.0 || sample_uv.x > 1.0 || sample_uv.y < 0.0 || sample_uv.y > 1.0) {
		return 0.0; // Fully transparent outside the shape
	}

	vec2 continuous_coord = sample_uv * pixel_grid_size;
	float corner = float(corner_size);

	// Start with full alpha
	float alpha = 1.0;

	// --- Corner Checks with smoothstep for soft transitions ---
	// Top-left
	if (continuous_coord.x < corner && continuous_coord.y < corner) {
		float dist = continuous_coord.x + continuous_coord.y;
		alpha *= smoothstep(corner - edge_feather, corner, dist);
	}
	// Top-right
	float px_from_right = pixel_grid_size - continuous_coord.x;
	if (px_from_right < corner && continuous_coord.y < corner) {
		float dist = px_from_right + continuous_coord.y;
		alpha *= smoothstep(corner - edge_feather, corner, dist);
	}
	// Bottom-left
	float px_from_bottom = pixel_grid_size - continuous_coord.y;
	if (continuous_coord.x < corner && px_from_bottom < corner) {
		float dist = continuous_coord.x + px_from_bottom;
		alpha *= smoothstep(corner - edge_feather, corner, dist);
	}
	// Bottom-right
	if (px_from_right < corner && px_from_bottom < corner) {
		float dist = px_from_right + px_from_bottom;
		alpha *= smoothstep(corner - edge_feather, corner, dist);
	}
	
	// --- Feather the four main edges of the rectangle ---
	vec2 dist_to_edge = min(continuous_coord, vec2(pixel_grid_size) - continuous_coord);
	float edge_alpha = smoothstep(0.0, edge_feather, min(dist_to_edge.x, dist_to_edge.y));
	alpha *= edge_alpha;

	return alpha;
}


// The main logic is from DigitalFilter.gdshader, now updated
void fragment() {
    // --- Feathering Logic to create the border mask ---
    vec2 center_dist = abs(UV - 0.5) * 2.0;
    float edge_dist = max(center_dist.x, center_dist.y);
    float feather_start = 1.0 - feather_amount;
    // This mask is 1.0 at the edge and fades to 0.0 towards the center
    float border_mask = 1.0 - smoothstep(feather_start, 1.0, edge_dist);

    float modified_strength = strength * border_mask;

    vec4 final_color;
    float random_val = rand(UV + TIME);
	
    if (random_val < modified_strength) {
        // --- Glitch Effect ---
        vec2 offset = vec2(rand(UV * TIME) - 0.5, rand(UV - TIME) - 0.5) * 0.1;
		
        // Sample our SOFT procedural shape with chromatic aberration
        float r_alpha = get_shape_alpha(UV + offset - vec2(aberration_amount));
        float g_alpha = get_shape_alpha(UV + offset);
        float b_alpha = get_shape_alpha(UV + offset + vec2(aberration_amount));
		
        // Combine the alphas with the fill color
        final_color = vec4(fill_color.r * r_alpha, fill_color.g * g_alpha, fill_color.b * b_alpha, 1.0);
		// The final alpha is a combination of the shape, the border mask, and the max channel alpha
		final_color.a = max(r_alpha, max(g_alpha, b_alpha)) * border_mask;
		
    } else {
        // If not glitching, get the normal shape alpha
        float shape_alpha = get_shape_alpha(UV);
        // Combine the shape alpha with the border mask to keep the center transparent
        final_color = vec4(fill_color.rgb, shape_alpha * border_mask);
    }

    // Apply our final opacity control at the very end
    COLOR = final_color;
    COLOR.a *= opacity;
}