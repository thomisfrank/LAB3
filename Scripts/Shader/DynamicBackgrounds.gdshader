shader_type canvas_item;

// scroll_speed: Controls the speed and direction of the background scroll animation
uniform vec2 scroll_speed = vec2(0.02, 0.01);

void fragment() {
	// UV is the texture's coordinate system (from 0.0 to 1.0)
	// TIME is a built-in variable that constantly increases
	// We add a scrolling offset to the UV based on time and our speed
	vec2 new_uv = UV + TIME * scroll_speed;

	// Look up the pixel color from the original texture using our new, moving UVs
	COLOR = texture(TEXTURE, new_uv);
}