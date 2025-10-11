extends Node

# Backgrounds: select and randomize backgrounds

# Configuration
### Configuration
@export_group("Background Randomization")
# randomize_on_ready: Randomize background on ready
@export var randomize_on_ready: bool = true
# randomize_shader_speed: Randomize shader speed for backgrounds
@export var randomize_shader_speed: bool = true
# shader_speed_min: Minimum shader speed
@export var shader_speed_min: float = 0.002
# shader_speed_max: Maximum shader speed
@export var shader_speed_max: float = 0.02
# randomize_direction: Randomize scroll direction for background
@export var randomize_direction: bool = true
# random_flip: Randomly flip background
@export var random_flip: bool = false

@export_group("Debug")
# debug_logging: Toggle for debug print statements
@export var debug_logging: bool = false

#-----------------------------------------------------------------------------
# Engine Hooks
#-----------------------------------------------------------------------------

# Called when the node enters the scene tree for the first time.
func _ready():
	randomize() # Seed RNG
	if randomize_on_ready:
		_find_and_apply() # Apply random background
	get_tree().connect("node_added", Callable(self, "_on_node_added"))


# Called when a new node is added to the scene tree.
func _on_node_added(node: Node) -> void:
	# When a node named 'backgrounds' appears, apply a random choice
	if node and node.name == "backgrounds":
		_choose_random_background(node)

#-----------------------------------------------------------------------------
# Public API
#-----------------------------------------------------------------------------

# Finds a backgrounds node and shows a specific background by name.
func show_background_by_name(requested_name: String) -> bool:
	# Show a specific background by name
	var bg_node = _find_backgrounds_node()
	if not bg_node:
		push_warning("[Backgrounds] Could not find a 'backgrounds' node in the scene.")
		return false
	var landscape = bg_node.get_node_or_null("Landscape")
	if not landscape:
		push_warning("[Backgrounds] 'Landscape' node not found under the 'backgrounds' node.")
		return false
	var found_texture: TextureRect = null
	for child in landscape.get_children():
		if child is TextureRect:
			if child.name == requested_name:
				found_texture = child
			child.visible = false # Hide all textures initially

	if found_texture:
		found_texture.visible = true
		# debug log suppressed
		return true
	else:
		push_warning("[Backgrounds] Background with name '%s' not found." % requested_name)
		return false

#-----------------------------------------------------------------------------
# Internal Logic
#-----------------------------------------------------------------------------

# Finds the 'backgrounds' node in the scene.
func _find_backgrounds_node() -> Node:
	# Find the backgrounds node in the scene
	if self.name == "backgrounds" or has_node("Landscape"):
		return self
	var current_scene = get_tree().current_scene
	if current_scene:
		var bg_node = _recursive_find(current_scene, "backgrounds")
		if bg_node:
			return bg_node
	return _recursive_find(get_tree().get_root(), "backgrounds")


func _recursive_find(start: Node, target_name: String) -> Node:
	if not start:
		return null
	if start.name == target_name:
		return start
	for child in start.get_children():
		if child is Node:
			var found = _recursive_find(child, target_name)
			if found:
				return found
	return null


# Finds the backgrounds node and applies a random background.
func _find_and_apply():
	var bg_node = _find_backgrounds_node()
	if bg_node:
		_choose_random_background(bg_node)
	elif debug_logging:
		# debug log suppressed
		pass


# Chooses and applies a random background texture from the available candidates.
func _choose_random_background(bg_node: Node) -> void:
	if not bg_node:
		return

	var landscape = bg_node.get_node_or_null("Landscape")
	if not landscape:
		push_warning("[Backgrounds] Landscape node not found under backgrounds node")
		return

	var candidates: Array[TextureRect] = []
	for child in landscape.get_children():
		if child is TextureRect:
			candidates.append(child)
			child.visible = false

	if candidates.is_empty():
		push_warning("[Backgrounds] No TextureRect candidates found under Landscape")
		return

	var picked: TextureRect = candidates[randi() % candidates.size()]
	picked.visible = true

	# Make sure the picked texture fills the available area so transparent/rounded corners
	# don't reveal the grey background under the TextureRect. Use expand + cover stretch.
	picked.visible = true
	# Force full-rect anchors so the TextureRect covers its parent
	# Anchors preset 15 corresponds to full rect in exported scenes
	if picked is Control:
		picked.anchors_preset = 15
		# Keep the original stretch_mode (likely STRETCH_TILE) - don't override it

	_apply_random_effects(picked)

	if debug_logging or Engine.is_editor_hint():
		# debug log suppressed
		pass


# Applies randomized shader and flip effects to the chosen background.
func _apply_random_effects(target_texture: TextureRect) -> void:
	# Optionally randomize shader scroll speed and direction
	if randomize_shader_speed and target_texture.material is ShaderMaterial:
		var mat: ShaderMaterial = target_texture.material
		var sx = lerp(shader_speed_min, shader_speed_max, randf())
		var sy = lerp(shader_speed_min, shader_speed_max, randf())
		if randomize_direction:
			sx *= -1.0 if randi() % 2 == 0 else 1.0
			sy *= -1.0 if randi() % 2 == 0 else 1.0
		mat.set_shader_parameter("scroll_speed", Vector2(sx, sy))

	# Optionally flip the texture horizontally/vertically
	if random_flip:
		target_texture.flip_h = (randi() % 2 == 0)
		target_texture.flip_v = (randi() % 2 == 0)
