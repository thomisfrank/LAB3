extends Node2D

signal draw_started

# --- EXPORT VARIABLES (Set these in the Inspector) ---
@export var card_scene: PackedScene  # Drag your InteractiveCard.tscn file here.

# --- RUNTIME VARIABLES (Set by RoundManager before drawing) ---
var card_size: Vector2 = Vector2(500, 700)  # Set by RoundManager
var card_spacing: float = 150.0  # Set by RoundManager
var fan_angle_degrees: float = 15.0  # Set by RoundManager

var deck: Array[String] = []
var draw_index: int = 0

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
	_initialize_deck()
	print("[CardManager] _ready() called")

func _initialize_deck():
	deck.clear()
	var suits = ["Draw", "PeekHand", "PeekDeck", "Swap"]
	var values = ["2", "4", "6", "8", "10"]
	for suit in suits:
		for value in values:
			deck.append(suit + "_" + value)
	deck.shuffle()
	draw_index = 0
	print("[CardManager] Deck initialized with ", deck.size(), " cards")
	print("[CardManager] First 5 cards: ", deck.slice(0, 5))

func _ensure_card_scene() -> bool:
	if not card_scene:
		push_error("CardManager: card_scene is not set!")
		return false
	return true

func draw_cards(number: int, start_pos: Vector2, _hand_center_pos: Vector2, face_up: bool = true, is_player: bool = true) -> void:
	# Create cards and place them into hand slots (if present) or compute positions
	emit_signal("draw_started")

	if number <= 0:
		return

	if not _ensure_card_scene():
		return

	# Determine which hand slots to use based on player/opponent
	# Use relative path since CardManager is a child of Parallax
	var hand_slots_path = "../HandSlots" if is_player else "../OpponentHandSlots"
	var hand_slots_root = get_node_or_null(hand_slots_path)
	
	# print("[CardManager] draw_cards - is_player=%s, hand_slots_path=%s, hand_slots_root=%s" % [is_player, hand_slots_path, hand_slots_root])

	# Ensure face-up/down state based on player
	if is_player:
		# Spawn player cards face-down then flip them to face-up during the draw animation
		face_up = false
	else:
		# Opponent cards stay face-down
		face_up = false

	# Get hand slot positions - NO FALLBACK, must have slots or fail
	var slot_positions: Array = []
	if not hand_slots_root:
		push_error("[CardManager] ERROR: HandSlots not found at path '%s'! Cards cannot be drawn." % hand_slots_path)
		return
	
	for slot in hand_slots_root.get_children():
		if is_instance_valid(slot):
			slot_positions.append({"pos": slot.global_position, "rot": slot.global_rotation})
	
	if slot_positions.size() == 0:
		push_error("[CardManager] ERROR: No valid hand slots found for %s hand!" % ("player" if is_player else "opponent"))
		return
	
	# print("[CardManager] Found %d slot positions for %s hand" % [slot_positions.size(), "player" if is_player else "opponent"])

	# Instantiate cards and move them to slot positions with tweens
	# Ensure we don't leave an empty running Tween (which errors in Godot if started with no tweeners)
	if hand_tween and hand_tween.is_running():
		hand_tween.kill()
	hand_tween = null

	# Cache Deck node for spawn position and z-index adjustments
	var deck_node = get_node_or_null("/root/main/Parallax/Deck")

	# Sequential draw: instantiate one card, tween to slot, set home, flip, then continue
	for i in range(number):
		var card_instance: Node2D = card_scene.instantiate()
		add_child(card_instance)

		if draw_index < deck.size() and card_instance.has_method("set_card_data"):
			var card_name = deck[draw_index]
			print("[CardManager] Drawing card: ", card_name, " to ", "player" if is_player else "opponent", " hand")
			card_instance.set_card_data(card_name)
			draw_index += 1
		else:
			print("[CardManager] WARNING: No card data available or method missing!")

		# Ensure the card draws above the deck visual: bump z_index relative to deck if present
		if deck_node and card_instance is CanvasItem:
			# use a modest offset to avoid interfering with other UI
			card_instance.z_index = deck_node.z_index + 10
		else:
			# safe default
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
		
		# Flip opponent cards 180 degrees so "Low" points toward player
		if not is_player and card_instance.has_node("Visuals"):
			var visuals = card_instance.get_node("Visuals")
			visuals.rotation = PI  # 180 degrees in radians
			# print("[CardManager] Flipped opponent card %d visuals to PI (%.2f deg)" % [i, rad_to_deg(PI)])
		elif not is_player:
			# No Visuals node for opponent card - keep silent in debug-trimmed mode
			pass

		# scale relative to base
		var base_card_size = Vector2(500, 700)
		card_instance.scale = card_size / base_card_size

		# spawn at deck position (prefer the actual Deck node if present)
		var spawn_pos = start_pos
		if deck_node:
			# Prefer the TopCard child so we spawn exactly at the visible top of the deck
			var top_card = deck_node.get_node_or_null("TopCard")
			if top_card:
				spawn_pos = top_card.global_position + Vector2(0, -12)
			else:
				# fallback: spawn slightly above the deck node origin
				spawn_pos = deck_node.global_position + Vector2(0, -20)
		card_instance.global_position = spawn_pos
		card_instance.rotation = 0.0

		# target slot
		var slot = slot_positions[i] if i < slot_positions.size() else slot_positions[slot_positions.size() - 1]
		var duration = draw_base_duration

		# small spawn pop: start slightly smaller for a magical appear
		card_instance.scale = (card_size / base_card_size) * 0.9

		# create a juicier two-stage arc movement: toward mid-air point then settle into slot
		var arc_height = clamp((spawn_pos.y - slot["pos"].y) * 0.3, -120, -30)
		var mid_pos = Vector2(lerp(spawn_pos.x, slot["pos"].x, 0.5), lerp(spawn_pos.y, slot["pos"].y, 0.5) + arc_height)
		var t1 = duration * 0.55
		var t2 = max(0.01, duration - t1)
		var t = create_tween()
		# stage 1: move to mid-air with a snappy ease, rotate slightly toward target
		t.tween_property(card_instance, "global_position", mid_pos, t1).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		t.parallel().tween_property(card_instance, "rotation", lerp(0.0, slot["rot"] * 0.3, 0.7), t1)
		t.parallel().tween_property(card_instance, "scale", card_size / base_card_size, t1 * 0.6)
		# stage 2: settle into final slot with a nice ease
		t.tween_property(card_instance, "global_position", slot["pos"], t2).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		t.parallel().tween_property(card_instance, "rotation", slot["rot"], t2)
		t.parallel().tween_property(card_instance, "scale", card_size / base_card_size, t2)

		# subtle shadow squash for impact if Visuals/Shadow exists
		var shadow_node = null
		if card_instance.has_node("Visuals/Shadow"):
			shadow_node = card_instance.get_node("Visuals/Shadow")
		if shadow_node:
			# squash shadow while in-flight and expand on impact
			t.parallel().tween_property(shadow_node, "scale", Vector2(0.9, 0.9), t1)
			t.parallel().tween_property(shadow_node, "scale", Vector2(1.1, 1.1), t2)

		# await tween completion
		await t.finished

		# Arrival: small overshoot pop and settle (fire-and-forget so we can overlap next card with flip)
		var pop_t = create_tween()
		pop_t.tween_property(card_instance, "scale", (card_size / base_card_size) * 1.05, 0.08).set_ease(Tween.EASE_OUT)
		pop_t.tween_property(card_instance, "scale", card_size / base_card_size, 0.12).set_delay(0.08).set_ease(Tween.EASE_IN)

		# Set authoritative home position now that card is in slot
		if is_instance_valid(card_instance) and card_instance.has_method("set_home_position"):
			card_instance.set_home_position(slot["pos"], slot["rot"])

		# Flip to reveal immediately (do not await) so next card can start during the flip
		# Only flip player cards - opponent cards stay face-down
		if not face_up and flip_on_player_draw and is_player and card_instance.has_method("flip_card"):
			card_instance.flip_card()

		# Start next card while this one is flipping: wait the configured stagger
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
	# Return an array of dictionaries {pos, rot} for each HandSlot in scene order
	var slots = []
	# Use relative path since CardManager is a child of Parallax
	var hand_slots_path = "../HandSlots" if is_player else "../OpponentHandSlots"
	var hand_slots_root = get_node_or_null(hand_slots_path)
	if not hand_slots_root:
		return slots
	for slot in hand_slots_root.get_children():
		if is_instance_valid(slot):
			slots.append({"pos": slot.global_position, "rot": slot.global_rotation})
	return slots


func relayout_hand(is_player: bool = true) -> void:
	"""Reposition existing cards to fill any gaps using HandSlots.
	This uses authoritative slot transforms and sets each card's home position.
	"""

	# Collect cards that are direct children (preserve scene order by card_index)
	var cards: Array = []
	for child in get_children():
		if child and child.has_method("set_home_position") and child.has_method("is_inside_tree"):
			# Filter by player/opponent card flag if present
			if "is_player_card" in child:
				if is_player and not child.is_player_card:
					continue
				if not is_player and child.is_player_card:
					continue
			else:
				# If no flag, assume it matches the requested type
				pass
			cards.append(child)

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
		t.tween_property(card, "global_position", slot["pos"], relayout_duration).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		t.parallel().tween_property(card, "rotation", slot["rot"], relayout_duration)
		# set home when tween finishes
		_set_home_after_delay(card, slot["pos"], slot["rot"], relayout_duration)
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
