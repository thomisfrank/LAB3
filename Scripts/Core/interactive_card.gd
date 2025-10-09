extends Node2D

# --- Node References & Exports ---
@onready var visuals = $Visuals
@onready var shadow = $Visuals/Shadow
@onready var display_container: SubViewportContainer = $Visuals/CardViewport
@onready var card_viewport = $Visuals/CardViewport/SubViewport
@onready var card = $Visuals/CardViewport/SubViewport/Card
@onready var card_back = $Visuals/CardViewport/SubViewport/Card/CardBack
@onready var card_face = $Visuals/CardViewport/SubViewport/Card/CardFace


# --- Card Appearance ---
@export var start_face_up: bool = true  # If true, starts showing card face; if false, shows back

# --- Card Ownership ---
@export var is_player_card: bool = true  # If true, player can drag this card; if false, only hover effects

# --- Interactions ---
@export_category("Interactions")
@export var max_tilt_angle: float = 20.0
@export var hover_scale: float = 1.1

@export_group("Drag Feel")
@export var drag_smoothing: float = 1.0  # 1.0 = instant, lower = smoother/floatier
@export var drag_lerp_speed: float = 20.0  # Only used if drag_smoothing < 1.0

@export_group("Shadow Control")
@export var shadow_follow_speed: float = 8.0
@export var max_shadow_offset: float = 50.0
@export var shadow_y_offset: float = 15.0
@export var shadow_instant_follow: bool = false  # If true, shadow follows instantly without lerp

@export_group("Wobble Control")
@export var wobble_speed: float = 15.0  # How fast the card wobbles back and forth.
@export var wobble_angle: float = 3.0  # The maximum angle in degrees the card will wobble.
@export var wobble_smoothing: float = 5.0  # How quickly the wobble fades in and out. Higher is snappier.

@export_group("Flip Animation")
@export var flip_duration: float = 0.25  # Duration of each half of the flip
@export var flip_ease: Tween.EaseType = Tween.EASE_IN_OUT
@export var flip_trans: Tween.TransitionType = Tween.TRANS_SINE
@export var flip_pop_scale: float = 1.05  # How much to scale up after flip
@export var flip_pop_duration: float = 0.3  # How long the pop animation takes


# --- State Variables ---
var is_mouse_over: bool = false
var is_dragging: bool = false
var hover_tween: Tween
var prev_global_position: Vector2 = Vector2.ZERO
var drag_offset: Vector2 = Vector2.ZERO
var wobble_time: float = 0.0 # NEW: For the oscillator

# --- Snap back variables ---
var home_position: Vector2 = Vector2.ZERO  # The card's designated position in hand
var home_rotation: float = 0.0  # The card's designated rotation in hand
var snap_back_tween: Tween

@export_category("Per-card Disintegration Override")
@export var use_disintegration_override: bool = false
@export_range(2, 200) var override_pixel_amount: int = 50
@export_range(0.0, 0.5) var override_edge_width: float = 0.04
@export var override_edge_color: Color = Color(1.5, 1.5, 1.5, 1.0)
@export var override_shader_tween_duration: float = 1.5
@export var override_shader_start_progress: float = 0.0
@export var override_shader_target_progress: float = 1.0
@export var override_shader_tween_ease: Tween.EaseType = Tween.EASE_IN
@export var override_shader_tween_trans: Tween.TransitionType = Tween.TRANS_SINE

# --- Godot Functions ---

func _ready() -> void:
	print("card ready")
	# Create or ensure a CollisionArea exists in the main scene tree so physics Area overlap works
	# (cards' visuals live in a SubViewport, so put the Area2D on this InteractiveCard node instead)
	if not has_node("CollisionArea"):
		var area = Area2D.new()
		area.name = "CollisionArea"
		# Put area on a default layer that DropZone will also use (adjust if you use layers differently)
		area.collision_layer = 1
		area.collision_mask = 1

		var rect_shape = RectangleShape2D.new()
		# Try to size the shape to the display container size; fallback to a reasonable default
		var shape_size = Vector2(200, 280)
		if display_container and display_container.custom_minimum_size:
			shape_size = display_container.custom_minimum_size
		rect_shape.size = shape_size

		var cs = CollisionShape2D.new()
		cs.shape = rect_shape

		# Position the area to coincide with the visible card center used during dragging.
		# The drag logic computes visual center as `global_position + visuals.position + Vector2(250,350)`
		# so we place the CollisionArea at that visual offset relative to this node.
		area.position = visuals.position + Vector2(250, 350)

		area.add_child(cs)
		add_child(area)
		# Mark the Area2D itself as a card so DropZone's area.is_in_group("cards") check succeeds.
		area.add_to_group("cards")

	# Also add the InteractiveCard itself to the group in case other code expects it
	add_to_group("cards")

	prev_global_position = global_position
	# Create a unique material instance for this card so shader changes don't affect other cards
	if display_container.material:
		display_container.material = display_container.material.duplicate()
	
	# Set initial card visibility based on export
	if start_face_up:
		card_face.show()
		card_back.hide()
	else:
		card_face.hide()
		card_back.show()
	
	# Check if signals are connected
	if display_container:
		var mf = display_container.mouse_filter
		var mf_name = "UNKNOWN"
		if mf == Control.MOUSE_FILTER_STOP:
			mf_name = "STOP"
		elif mf == Control.MOUSE_FILTER_PASS:
			mf_name = "PASS"
		elif mf == Control.MOUSE_FILTER_IGNORE:
			mf_name = "IGNORE"
		print("has display_container, mouse_filter=", mf, "(", mf_name, ")")
		# Debug: print rect and whether signals are connected
		if display_container.has_method("get_rect"):
			var r = display_container.get_rect()
			print("display_container rect:", r)
		print("connected mouse_entered:", display_container.is_connected("mouse_entered", Callable(self, "_on_display_mouse_entered")))
		print("connected mouse_exited:", display_container.is_connected("mouse_exited", Callable(self, "_on_display_mouse_exited")))

func _process(delta: float) -> void:
	# Run all our per-frame logic
	drag_logic()
	handle_shadow()
	handle_tilt(delta)
	handle_wobble(delta) # NEW: Call the wobble logic
	
	# Debug: check mouse position
	if display_container and display_container.get_rect().has_point(display_container.get_local_mouse_position()):
		if Input.is_action_just_pressed("click"):
			print("click inside card rect")

func flip_card():
	var tween = create_tween().set_ease(flip_ease).set_trans(flip_trans)
	
	var visible_side = card_back if card_back.is_visible() else card_face
	var hidden_side = card_face if card_back.is_visible() else card_back

	# --- Part 1: First Half of Flip (Card AND Shadow together) ---
	# Squash the visible side of the card
	tween.tween_property(visible_side, "scale:x", 0.0, flip_duration)
	# Squash the shadow AT THE SAME TIME
	tween.parallel().tween_property(shadow, "scale:x", 0.0, flip_duration)
	
	# --- Part 2: The Swap ---
	tween.tween_callback(func():
		visible_side.hide()
		hidden_side.show()
		hidden_side.scale.x = 0.0
	)
	
	# --- Part 3: Second Half of Flip (Card AND Shadow together) ---
	# Un-squash the new side of the card
	tween.tween_property(hidden_side, "scale:x", 1.0, flip_duration)
	# Un-squash the shadow AT THE SAME TIME
	tween.parallel().tween_property(shadow, "scale:x", 1.0, flip_duration)
	
	# --- Part 4: Pop effect after flip completes ---
	# Scale up
	tween.tween_property(display_container, "scale", Vector2(flip_pop_scale, flip_pop_scale), flip_pop_duration * 0.5).set_ease(Tween.EASE_OUT)
	# Scale back down
	tween.tween_property(display_container, "scale", Vector2.ONE, flip_pop_duration * 0.5).set_ease(Tween.EASE_IN)


# --- Signal Handlers ---

func _on_display_mouse_entered() -> void:
	print("hover")
	is_mouse_over = true
	if not is_dragging:
		if hover_tween and hover_tween.is_running():
			hover_tween.kill()
		hover_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_ELASTIC)
		hover_tween.tween_property(display_container, "scale", Vector2(hover_scale, hover_scale), 0.5)

func _on_display_mouse_exited() -> void:
	is_mouse_over = false
	if not is_dragging:
		if hover_tween and hover_tween.is_running():
			hover_tween.kill()
		hover_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		hover_tween.tween_property(display_container, "scale", Vector2.ONE, 0.4)

# --- Helper Functions ---

func drag_logic() -> void:
	# Only allow dragging for player cards
	if is_mouse_over and Input.is_action_just_pressed("click") and is_player_card:
		is_dragging = true
		# Don't update home position here - it's set by CardManager
		
		# Calculate offset accounting for where the visuals actually are
		# The card center is visually at global_position + visuals.position offset
		var visual_center = global_position + visuals.position + Vector2(250, 350)
		drag_offset = get_global_mouse_position() - visual_center
		if hover_tween and hover_tween.is_running():
			hover_tween.kill()
		hover_tween = create_tween().set_ease(Tween.EASE_OUT)
		hover_tween.tween_property(display_container, "scale", Vector2.ONE, 0.2)

	if is_dragging and Input.is_action_just_released("click"):
		is_dragging = false
		# Check if we released over a drop zone
		_check_drop_zones()

	if is_dragging:
		# Target is mouse position minus offset, adjusted back for visual center
		var visual_center_target = get_global_mouse_position() - drag_offset
		var target_position = visual_center_target - visuals.position - Vector2(250, 350)
		if drag_smoothing >= 1.0:
			# Instant/snappy drag
			global_position = target_position
		else:
			# Smooth/floaty drag - lerp_speed and smoothing control responsiveness
			var lerp_weight = clamp(drag_lerp_speed * drag_smoothing * 0.01, 0.0, 0.99)
			global_position = global_position.lerp(target_position, lerp_weight)

func _check_drop_zones() -> void:
	# Check if any drop zones contain our current position
	for zone in get_tree().get_nodes_in_group("drop_zones"):
		if zone.has_method("contains_global_position"):
			if zone.contains_global_position(global_position):
				# Trigger the drop
				if zone.has_method("on_card_dropped"):
					zone.on_card_dropped(self)
				return
	
	# No valid drop zone found - snap back to original position with bounce
	snap_back_to_original_position()

func set_home_position(pos: Vector2, rot: float) -> void:
	"""Call this to set the card's designated home position in the hand"""
	home_position = pos
	home_rotation = rot

func snap_back_to_original_position() -> void:
	# Kill any existing snap back tween
	if snap_back_tween and snap_back_tween.is_running():
		snap_back_tween.kill()
	
	# Create bouncy snap-back animation
	snap_back_tween = create_tween()
	snap_back_tween.set_parallel(true)
	
	# Bounce back to home position with overshoot
	snap_back_tween.tween_property(self, "global_position", home_position, 0.5).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	snap_back_tween.tween_property(self, "rotation", home_rotation, 0.5).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	
	# Add a little scale bounce for extra juice
	snap_back_tween.tween_property(display_container, "scale", Vector2(1.1, 1.1), 0.25).set_ease(Tween.EASE_OUT)
	snap_back_tween.tween_property(display_container, "scale", Vector2.ONE, 0.25).set_ease(Tween.EASE_IN).set_delay(0.25)

func handle_shadow() -> void:
	var center_x: float = get_viewport_rect().size.x / 2.0
	var distance_from_center: float = global_position.x - center_x
	var distance_percent: float = distance_from_center / center_x
	
	var target_x = -distance_percent * max_shadow_offset
	
	# Use the shadow_instant_follow export to control behavior
	if shadow_instant_follow:
		# Instant shadow follow (no lerp)
		shadow.position.x = target_x
	else:
		# Smooth shadow follow using shadow_follow_speed
		# Ensure numeric values for lerp
		var from_x = float(shadow.position.x)
		var to_x = float(target_x)
		var w = float(shadow_follow_speed) * get_process_delta_time()
		shadow.position.x = lerp(from_x, to_x, w)
	
	shadow.position.y = shadow_y_offset

func handle_tilt(delta: float) -> void:
	var mat = display_container.material as ShaderMaterial
	if not mat:
		return
	if is_mouse_over and not is_dragging:
		var card_size: Vector2 = display_container.size
		var mouse_pos: Vector2 = display_container.get_local_mouse_position()
		var percent_x = (mouse_pos.x / card_size.x) - 0.5
		var percent_y = (mouse_pos.y / card_size.y) - 0.5
		
		var rot_y = percent_x * max_tilt_angle * -2.0
		var rot_x = percent_y * max_tilt_angle * 2.0
		
		mat.set_shader_parameter("y_rot", rot_y)
		mat.set_shader_parameter("x_rot", rot_x)
	else:
		var current_rot_y = mat.get_shader_parameter("y_rot")
		var current_rot_x = mat.get_shader_parameter("x_rot")
		# Coerce shader params to floats or default to 0.0
		if typeof(current_rot_y) == TYPE_INT or typeof(current_rot_y) == TYPE_FLOAT:
			current_rot_y = float(current_rot_y)
		else:
			current_rot_y = 0.0
		if typeof(current_rot_x) == TYPE_INT or typeof(current_rot_x) == TYPE_FLOAT:
			current_rot_x = float(current_rot_x)
		else:
			current_rot_x = 0.0
		mat.set_shader_parameter("y_rot", lerp(current_rot_y, 0.0, delta * 5.0))
		mat.set_shader_parameter("x_rot", lerp(current_rot_x, 0.0, delta * 5.0))

# --- NEW: Wobble Function ---
func handle_wobble(delta: float) -> void:
	# Calculate velocity (how fast and in what direction we moved)
	var velocity = (global_position - prev_global_position) / delta
	var speed = velocity.length()
	
	# The target rotation is 0 if we're not moving
	var target_rotation_rad = 0.0

	# If we are moving, calculate a wobble based on movement
	if speed > 1.0 and is_dragging:
		wobble_time += delta * wobble_speed
		var max_angle_rad = deg_to_rad(wobble_angle)
		var wobble_offset = sin(wobble_time) * max_angle_rad
		
		# Tilt perpendicular to movement direction (like a pendulum)
		target_rotation_rad = wobble_offset

	# Smoothly move the visuals rotation towards the target rotation
	# This rotates both the card AND the shadow together
	visuals.rotation = lerp_angle(visuals.rotation, target_rotation_rad, delta * wobble_smoothing)
	
	# Update the position for the next frame
	prev_global_position = global_position


func _on_flip_pressed() -> void:
	flip_card()


# Called by DropZone to trigger the disintegration effect on this card.
func apply_disintegration(disintegration_shader: Shader, _start_progress: float = 0.0, target_progress: float = 1.0, duration: float = 1.5, ease_type: int = Tween.EASE_IN, trans_type: int = Tween.TRANS_SINE, shader_pixel_amount: int = 50, shader_edge_width: float = 0.04, shader_edge_color: Color = Color(1.5,1.5,1.5,1.0)) -> void:
	# Ensure we have a material we can modify on the display container (SubViewportContainer).
	if not display_container:
		print("No display_container on card; cannot apply disintegration.")
		return

	if not disintegration_shader:
		print("No disintegration shader provided")
		return

	# Create a new ShaderMaterial with the disintegration shader
	var mat = ShaderMaterial.new()
	mat.shader = disintegration_shader
	
	# Set initial progress from parameter
	mat.set_shader_parameter("progress", _start_progress)
	
	# Apply the material to the display container
	display_container.material = mat

	# Apply shader uniforms (prefer per-card overrides)
	if use_disintegration_override:
		mat.set_shader_parameter("pixel_amount", override_pixel_amount)
		mat.set_shader_parameter("edge_width", override_edge_width)
		mat.set_shader_parameter("edge_color", override_edge_color)
	else:
		mat.set_shader_parameter("pixel_amount", shader_pixel_amount)
		mat.set_shader_parameter("edge_width", shader_edge_width)
		mat.set_shader_parameter("edge_color", shader_edge_color)

	# Animate the shader parameter 'progress' (uses parameters passed from DropZone)
	var tween = create_tween()
	tween.tween_property(mat, "shader_parameter/progress", target_progress, duration).set_ease(ease_type).set_trans(trans_type)
	tween.tween_callback(func():
		# After shader tween completes, either play a 'digital_decay' AnimationPlayer animation
		# and wait for its completion, or immediately add this card to the discard pile.
		if has_node("AnimationPlayer"):
			var ap = $AnimationPlayer
			if ap and ap.has_animation("digital_decay"):
				var cb = Callable(self, "_on_animation_player_animation_finished")
				if not ap.is_connected("animation_finished", cb):
					ap.animation_finished.connect(cb)
				ap.play("digital_decay")
				return
		# Fallback: directly move to discard pile if main provides the API
		_move_to_discard_pile()
	)


func _move_to_discard_pile() -> void:
	"""Helper to move this card to the discard pile via the main scene."""
	var scene_root = get_tree().get_current_scene()
	if scene_root and scene_root.has_method("add_to_discard_pile"):
		# Important: card must still be in the tree when add_to_discard_pile is called
		if is_instance_valid(self) and is_inside_tree():
			scene_root.add_to_discard_pile(self)
		else:
			print("InteractiveCard: card is not valid or not in tree when trying to move to discard pile")
			queue_free()
	else:
		print("InteractiveCard: main.add_to_discard_pile not found; freeing card")
		queue_free()


func _on_animation_player_animation_finished(anim_name: String) -> void:
	if anim_name == "digital_decay":
		_move_to_discard_pile()
