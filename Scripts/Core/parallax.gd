extends Control

# Parallax motion settings
@export_group("Parallax Motion")
@export var max_offset: Vector2 = Vector2(25, 25)

@export_group("Parallax Smoothing")
# How smoothly the background follows the mouse. Higher is faster.
@export var smoothing: float = 2.0

func _process(delta: float):
	# Get the viewport size and its center point.
	var viewport_size = get_viewport_rect().size
	var center = viewport_size / 2.0
	
	# Calculate how far the mouse is from the center.
	var dist_from_center = get_global_mouse_position() - center
	
	# Normalize the distance to a range of -1.0 to 1.0 for both axes.
	var offset_percent = dist_from_center / center
	
	# Calculate the target position by moving in the OPPOSITE direction of the mouse.
	var target_pos = -offset_percent * max_offset
	
	# Smoothly move this node's position towards the target.
	# Since all other game nodes are its children, they will move along with it.
	position = position.lerp(target_pos, smoothing * delta)
