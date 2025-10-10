extends Node2D

signal draw_started

# --- EXPORT VARIABLES (Set these in the Inspector) ---
@export var card_scene: PackedScene  # Drag your InteractiveCard.tscn file here.

# --- RUNTIME VARIABLES (Set by RoundManager before drawing) ---
var card_size: Vector2 = Vector2(500, 700)  # Set by RoundManager
var card_spacing: float = 150.0  # Set by RoundManager
var fan_angle_degrees: float = 15.0  # Set by RoundManager

# --- Draw animation tuning ---
@export_group("Draw Animation")
@export var draw_base_duration: float = 0.5
@export var draw_stagger: float = 0.075
@export var relayout_duration: float = 0.28
@export var relayout_stagger: float = 0.02

# --- Flip tuning ---
@export_group("Flip / Reveal")
@export var flip_on_player_draw: bool = true
@export var flip_during_fraction: float = 0.6
@export var flip_pre_pop_scale: float = 1.08
@export var flip_pre_pop_duration: float = 0.06
@export var flip_time_jitter: float = 0.03

var hand_tween: Tween = null

func _ready():
	pass

func _ensure_card_scene() -> bool:
	if not card_scene:
		push_error("CardManager: card_scene is not set!")
		return false
	return true

func draw_cards(number: int, start_pos: Vector2, _hand_center_pos: Vector2, face_up: bool = true, is_player: bool = true) -> void:
	emit_signal("draw_started")

	if number <= 0:
		return

	if not _ensure_card_scene():
		return

	# Determine hand slots based on player/opponent
	var hand_slots_path = "../HandSlots" if is_player else "../OpponentHandSlots"
	var hand_slots_root = get_node_or_null(hand_slots_path)
	
	# print("[CardManager] draw_cards - is_player=%s, hand_slots_path=%s, found=%s" % [is_player, hand_slots_path, hand_slots_root != null])

	# Player cards flip face-up, opponent cards stay face-down
	face_up = false if is_player else false

	# Get hand slot positions
	var slot_positions: Array = []
	if not hand_slots_root:
		push_error("[CardManager] ERROR: HandSlots not found at path '%s'" % hand_slots_path)
		return
	
	for slot in hand_slots_root.get_children():
		if is_instance_valid(slot):
			# print("[CardManager] Found slot: %s at pos %v" % [slot.name, slot.global_position])
			slot_positions.append(slot)
	
	if slot_positions.size() == 0:
		push_error("[CardManager] ERROR: No valid hand slots found for %s!" % ("player" if is_player else "opponent"))
		return
	
	# print("[CardManager] Drawing %d cards for %s into %d slots" % [number, "player" if is_player else "opponent", slot_positions.size()])

	# Instantiate cards and move them to slot positions with tweens
	# Ensure we don't leave an empty running Tween (which errors in Godot if started with no tweeners)
	if hand_tween and hand_tween.is_running():
		hand_tween.kill()
	hand_tween = null

	# Cache Deck node for spawn position and z-index adjustments
	var deck_node = get_node_or_null("/root/main/Parallax/Deck")

	# Sequential draw: instantiate one card, animate from deck to slot, then reparent to slot
	for i in range(number):
		var card_instance: Node2D = card_scene.instantiate()
		# Start as child of CardManager for the animation
		add_child(card_instance)
		
		# Get the target slot for this card
		var target_slot = slot_positions[i] if i < slot_positions.size() else slot_positions[slot_positions.size() - 1]
		
		# Ensure the card draws above the deck visual
		if deck_node and card_instance is CanvasItem:
			card_instance.z_index = deck_node.z_index + 10
		else:
			if card_instance is CanvasItem:
				card_instance.z_index = 100

		if "start_face_up" in card_instance:
			card_instance.start_face_up = face_up
			if card_instance.has_method("apply_start_face_up"):
				card_instance.apply_start_face_up()
		if "is_player_card" in card_instance:
			card_instance.is_player_card = is_player
		if "card_index" in card_instance:
			card_instance.card_index = i

		# scale relative to base
		var base_card_size = Vector2(500, 700)
		card_instance.scale = (card_size / base_card_size) * 0.9

		# spawn at deck position
		var spawn_pos = start_pos
		if deck_node:
			var top_card = deck_node.get_node_or_null("TopCard")
			if top_card:
				spawn_pos = top_card.global_position + Vector2(0, -12)
			else:
				spawn_pos = deck_node.global_position + Vector2(0, -20)
		card_instance.global_position = spawn_pos
		card_instance.rotation = 0.0

		# Animate to slot's global position (both spawn and slot need same coordinate space)
		var slot_global_pos = target_slot.global_position
		var slot_global_rot = target_slot.global_rotation
		var duration = draw_base_duration

		# create a juicier two-stage arc movement
		var arc_height = clamp((spawn_pos.y - slot_global_pos.y) * 0.3, -120, -30)
		var mid_pos = Vector2(lerp(spawn_pos.x, slot_global_pos.x, 0.5), lerp(spawn_pos.y, slot_global_pos.y, 0.5) + arc_height)
		var t1 = duration * 0.55
		var t2 = max(0.01, duration - t1)
		var t = create_tween()
		# stage 1: move to mid-air
		t.tween_property(card_instance, "global_position", mid_pos, t1).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		t.parallel().tween_property(card_instance, "rotation", lerp(0.0, slot_global_rot * 0.3, 0.7), t1)
		t.parallel().tween_property(card_instance, "scale", card_size / base_card_size, t1 * 0.6)
		# stage 2: settle into slot - use global_position for consistency
		t.tween_property(card_instance, "global_position", slot_global_pos, t2).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		t.parallel().tween_property(card_instance, "rotation", slot_global_rot, t2)
		t.parallel().tween_property(card_instance, "scale", card_size / base_card_size, t2)

		# subtle shadow squash
		if card_instance.has_node("Visuals/Shadow"):
			var shadow_node = card_instance.get_node("Visuals/Shadow")
			t.parallel().tween_property(shadow_node, "scale", Vector2(0.9, 0.9), t1)
			t.parallel().tween_property(shadow_node, "scale", Vector2(1.1, 1.1), t2)

		# await tween completion
		await t.finished

		# Card is now at slot position
	# print("[CardManager] Card %d positioned - pos: %v, rot: %.2f deg" % [i, card_instance.global_position, rad_to_deg(card_instance.rotation)])

		# Arrival pop animation
		var pop_t = create_tween()
		pop_t.tween_property(card_instance, "scale", (card_size / base_card_size) * 1.05, 0.08).set_ease(Tween.EASE_OUT)
		pop_t.tween_property(card_instance, "scale", card_size / base_card_size, 0.12).set_delay(0.08).set_ease(Tween.EASE_IN)

		# Set home position to slot position (use global coordinates)
		if is_instance_valid(card_instance) and card_instance.has_method("set_home_position"):
			card_instance.set_home_position(slot_global_pos, slot_global_rot)

		# Flip to reveal (only player cards)
		if not face_up and flip_on_player_draw and is_player and card_instance.has_method("flip_card"):
			card_instance.flip_card()

		# Stagger next card
		if draw_stagger > 0:
			await get_tree().create_timer(draw_stagger).timeout


func _set_home_after_delay(card_instance: Node2D, final_pos: Vector2, final_rot: float, delay: float) -> void:
	# Schedule setting the card's home position after a delay (safe: uses authoritative slot transform)
	if not is_instance_valid(card_instance):
		return
	var t = create_tween()
	t.tween_interval(delay)
	t.tween_callback(func():
		if is_instance_valid(card_instance) and card_instance.is_inside_tree():
			if card_instance.has_method("set_home_position"):
				card_instance.set_home_position(final_pos, final_rot)
			else:
				# fallback: directly set global transform
				card_instance.global_position = final_pos
				card_instance.rotation = final_rot
	)


func _get_hand_slot_positions(is_player: bool = true) -> Array:
	var slots = []
	var hand_slots_path = "../HandSlots" if is_player else "../OpponentHandSlots"
	var hand_slots_root = get_node_or_null(hand_slots_path)
	if not hand_slots_root:
		return slots
	for slot in hand_slots_root.get_children():
		if is_instance_valid(slot):
			slots.append({"global_pos": slot.global_position, "rot": slot.rotation})
	return slots


func relayout_hand(is_player: bool = true) -> void:
	"""Reposition existing cards to fill gaps using HandSlots."""
	
	# print("[CardManager] relayout_hand called for %s hand" % ("player" if is_player else "opponent"))

	# Collect cards for the specified hand
	var cards: Array = []
	for child in get_children():
		if child and child.has_method("set_home_position") and child.has_method("is_inside_tree"):
			# Filter by player/opponent flag
			if "is_player_card" in child:
				if is_player and not child.is_player_card:
					continue
				if not is_player and child.is_player_card:
					continue
			cards.append(child)
	
	# print("[CardManager] Found %d cards to relayout for %s" % [cards.size(), "player" if is_player else "opponent"])

	# Sort by card_index if available to preserve intended order
	cards.sort_custom(Callable(self, "_sort_by_card_index"))

	# Get slot positions for the appropriate hand
	var slots = _get_hand_slot_positions(is_player)
	if slots.size() == 0:
		# No hand slots: nothing to do
		return

	# Create a staggered tween to move cards into their slot positions
	for i in range(cards.size()):
		var card = cards[i]
		if not is_instance_valid(card):
			continue
		# assign new index
		if "card_index" in card:
			card.card_index = i
		# choose slot (clamp)
		var slot = slots[i] if i < slots.size() else slots[slots.size() - 1]
		# tween card to slot
		var t = create_tween()
		t.tween_property(card, "global_position", slot["global_pos"], relayout_duration).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		t.parallel().tween_property(card, "rotation", slot["rot"], relayout_duration)
		# set home when tween finishes
		_set_home_after_delay(card, slot["global_pos"], slot["rot"], relayout_duration)
		# small stagger between each card start
		if relayout_stagger > 0:
			# wait a tiny bit before starting next card to create a pleasing cascade
			await get_tree().create_timer(relayout_stagger).timeout


func _sort_by_card_index(a, b) -> int:
	var ai = 0
	var bi = 0
	if "card_index" in a:
		ai = int(a.card_index)
	if "card_index" in b:
		bi = int(b.card_index)
	return ai - bi
