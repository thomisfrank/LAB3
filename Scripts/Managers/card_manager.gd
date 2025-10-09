extends Node2D

signal draw_started

# --- EXPORT VARIABLES (Set these in the Inspector) ---
@export var card_scene: PackedScene  # Drag your InteractiveCard.tscn file here.

# --- RUNTIME VARIABLES (Set by RoundManager before drawing) ---
var card_size: Vector2 = Vector2(500, 700)  # Set by RoundManager
var card_spacing: float = 150.0  # Set by RoundManager
var fan_angle_degrees: float = 15.0  # Set by RoundManager

# --- Draw animation tuning ---
@export var draw_base_duration: float = 0.5
@export var draw_stagger: float = 0.075

# --- Flip tuning ---
@export var flip_on_player_draw: bool = true
@export var flip_during_fraction: float = 0.6
@export var flip_pre_pop_scale: float = 1.08
@export var flip_pre_pop_duration: float = 0.06
@export var flip_time_jitter: float = 0.03

var hand_tween: Tween

## Public API: Re-layout the hand after a card is removed (shifts cards to fill gap)
func relayout_hand(hand_center_pos: Vector2, is_player: bool = true) -> void:
	# Get all remaining card instances (children of this CardManager node)
	var cards_in_hand: Array = []
	for child in get_children():
		# Filter out cards that are being destroyed or don't match player ownership
		if is_instance_valid(child) and child.is_inside_tree():
			if "is_player_card" in child and child.is_player_card == is_player:
				# Skip if card is marked for destruction or has disintegration active
				if child.has_method("get") and child.get("is_disintegrating") == true:
					continue
				cards_in_hand.append(child)
	
	var number = cards_in_hand.size()
	if number == 0:
		return
	
	# Calculate new positions (same logic as draw_cards but for existing cards)
	var total_hand_width = float(number - 1) * card_spacing
	var start_x = hand_center_pos.x - total_hand_width / 2.0
	
	if hand_tween and hand_tween.is_running():
		hand_tween.kill()
	
	hand_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	
	for i in range(number):
		var card = cards_in_hand[i]
		var fan_angle_rad = deg_to_rad(fan_angle_degrees)
		var final_rot_rad = 0.0
		if number > 1:
			final_rot_rad = lerp(-fan_angle_rad, fan_angle_rad, float(i) / float(number - 1))
		
		var final_pos = Vector2(start_x + i * card_spacing, hand_center_pos.y)
		
		# Tween to new position and rotation
		hand_tween.parallel().tween_property(card, "position", final_pos, 0.3)
		hand_tween.parallel().tween_property(card, "rotation", final_rot_rad, 0.3)
		
		# Update home position after move
		if card.has_method("set_home_position"):
			var set_home = func():
				if is_instance_valid(card) and card.is_inside_tree():
					card.set_home_position(card.global_position, card.rotation)
			hand_tween.tween_callback(set_home)

func _ready():
	pass

func _ensure_card_scene() -> bool:
	if not card_scene:
		push_error("CardManager: card_scene is not set!")
		return false
	return true

func _set_home_after_delay(card_instance: Node, delay: float) -> void:
	var t = create_tween()
	t.tween_interval(delay)
	t.tween_callback(func():
		if is_instance_valid(card_instance) and card_instance.is_inside_tree():
			if card_instance.has_method("set_home_position"):
				card_instance.set_home_position(card_instance.global_position, card_instance.rotation)
	)

func draw_cards(number: int, start_pos: Vector2, hand_center_pos: Vector2, face_up: bool = true, is_player: bool = true) -> void:

	# Emit once at the start so UI can hide the loading overlay
	emit_signal("draw_started")

	if number <= 0:
		print("CardManager: No cards to draw (number <= 0), skipping")
		return

	if not _ensure_card_scene():
		return

	if hand_tween and hand_tween.is_running():
		hand_tween.kill()

	hand_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)

	var total_hand_width = float(number - 1) * card_spacing
	var start_x = hand_center_pos.x - total_hand_width / 2.0

	for i in range(number):
		var card_instance: Node2D = card_scene.instantiate()

		if "start_face_up" in card_instance:
			card_instance.start_face_up = false
		if "is_player_card" in card_instance:
			card_instance.is_player_card = is_player

		add_child(card_instance)

		var base_card_size = Vector2(500, 700)
		card_instance.scale = card_size / base_card_size

		card_instance.global_position = start_pos

		var fan_angle_rad = deg_to_rad(fan_angle_degrees)
		var final_rot_rad = 0.0
		if number > 1:
			final_rot_rad = lerp(-fan_angle_rad, fan_angle_rad, float(i) / float(number - 1))
		if not face_up:
			final_rot_rad += PI

		var final_pos = Vector2(start_x + i * card_spacing, hand_center_pos.y)
		card_instance.set_meta("base_rotation", final_rot_rad)

		var duration = draw_base_duration + i * draw_stagger
		hand_tween.parallel().tween_property(card_instance, "position", final_pos, duration)
		hand_tween.parallel().tween_property(card_instance, "rotation", final_rot_rad, duration)

		_set_home_after_delay(card_instance, duration)

		if face_up and flip_on_player_draw and card_instance.has_method("flip_card"):
			var rng = RandomNumberGenerator.new()
			rng.randomize()
			var jitter = rng.randf_range(-flip_time_jitter, flip_time_jitter)
			var flip_time = max(0.01, duration * flip_during_fraction + jitter)

			var pre_pop_t = create_tween()
			pre_pop_t.tween_interval(max(0.01, flip_time - (flip_pre_pop_duration * 0.5)))
			pre_pop_t.tween_callback(func():
				if is_instance_valid(card_instance) and card_instance.is_inside_tree():
					var pop_t = create_tween()
					pop_t.tween_property(card_instance, "scale", card_instance.scale * flip_pre_pop_scale, flip_pre_pop_duration * 0.5).set_ease(Tween.EASE_OUT)
					pop_t.tween_property(card_instance, "scale", card_instance.scale, flip_pre_pop_duration * 0.5).set_ease(Tween.EASE_IN)
			)

			var flip_t = create_tween()
			flip_t.tween_interval(flip_time)
			flip_t.tween_callback(func():
				if is_instance_valid(card_instance) and card_instance.is_inside_tree():
					card_instance.flip_card()
			)
