extends Node2D

signal draw_started

# --- EXPORT VARIABLES (Set these in the Inspector) ---
@export var card_scene: PackedScene  # Drag your InteractiveCard.tscn file here.

# --- RUNTIME VARIABLES (Set by RoundManager before drawing) ---
var card_size: Vector2 = Vector2(500, 700)  # Set by RoundManager
var card_spacing: float = 150.0  # Set by RoundManager
var fan_angle_degrees: float = 15.0  # Set by RoundManager

var deck: Array = []
var draw_index: int = 0
var last_deck_remaining: int = -1
var deck_counter_tween = null

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

# Deck counter flicker tuning (editable in Inspector)
@export_group("Deck Counter - Flicker")
@export var flicker_steps: int = 8
@export var flicker_step_time: float = 0.04
@export var flicker_stagger: float = 0.06
@export var flicker_blank_chance: float = 0.2
@export var flicker_final_pause: float = 0.04

func _ready():
	_initialize_deck()

func _initialize_deck():
	# Try the common autoload path first, then fall back to a global search in the scene tree.
	var card_data_loader = get_node_or_null("/root/CardDataLoader")
	if not card_data_loader:
		var current_scene = get_tree().get_current_scene()
		if current_scene:
			card_data_loader = current_scene.find_node("CardDataLoader", true, false)
	
	if card_data_loader:
		deck = card_data_loader.get_deck_composition()
		# Deck composition loaded from CardDataLoader
		if typeof(deck) != TYPE_ARRAY or deck.size() == 0:
			push_warning("[CardManager] Deck composition is empty after loading from CardDataLoader!")
		else:
			# Debug/info log: deck loaded successfully
			print("[CardManager] Deck composition loaded: %d cards" % deck.size())
			deck.shuffle()
	else:
		push_error("[CardManager] CardDataLoader node not found - deck will be empty")

	draw_index = 0
	# Update on-screen deck counter if present
	_update_deck_counter()

func _ensure_card_scene() -> bool:
	if not card_scene:
		push_error("CardManager: card_scene is not set!")
		return false
	return true

func draw_cards(number: int, start_pos: Vector2, _hand_center_pos: Vector2, face_up: bool = true, is_player: bool = true) -> void:
	emit_signal("draw_started")
	
	# Clear the loading message when cards start being drawn
	var info_manager = get_node_or_null("/root/main/Managers/InfoScreenManager")
	if info_manager and info_manager.has_method("clear"):
		info_manager.clear()

	if number <= 0:
		return

	if not _ensure_card_scene():
		return

	# Determine hand slots based on player/opponent
	var hand_slots_path = "../HandSlots" if is_player else "../OpponentHandSlots"
	var hand_slots_root = get_node_or_null(hand_slots_path)
	
	# draw_cards called

	# Player cards flip face-up, opponent cards stay face-down
	face_up = false if is_player else false

	# Get hand slot positions
	var slot_positions: Array = []
	if not hand_slots_root:
		push_error("[CardManager] ERROR: HandSlots not found at path '%s'" % hand_slots_path)
		return
	
	for slot in hand_slots_root.get_children():
		if is_instance_valid(slot):
			# found slot
			slot_positions.append(slot)
	
	if slot_positions.size() == 0:
		push_error("[CardManager] ERROR: No valid hand slots found for %s!" % ("player" if is_player else "opponent"))
		return
	
	# drawing cards into slots

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
		
		if draw_index < deck.size() and card_instance.has_method("set_card_data"):
			var card_name = deck[draw_index]
			card_instance.set_card_data(card_name)
			draw_index += 1
			_update_deck_counter()
		else:
			# Silent warning: missing card data or method; use push_warning so it's visible in the editor output
			push_warning("[CardManager] WARNING: No card data available or method missing!")
		
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
	# card positioned

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


func _update_deck_counter() -> void:
	# Update the DeckCounter UI in the Deck scene (if present)
	var deck_node = get_node_or_null("/root/main/Parallax/Deck")
	if not deck_node:
		return
	var counter = deck_node.get_node_or_null("DeckCounter")
	if not counter:
		return
	var remaining = 0
	if deck and typeof(deck) == TYPE_ARRAY:
		remaining = max(0, deck.size() - draw_index)
	# Format as two digits for the two labels
	var tens = int((remaining / 10) % 10)
	var ones = int(remaining % 10)
	# Update labels if they exist
	var no_label = counter.get_node_or_null("HBoxContainer/NoValueLabel")
	var d1_label = counter.get_node_or_null("HBoxContainer/DeckDigit1Label")
	var d2_label = counter.get_node_or_null("HBoxContainer/DeckDigit2Label")
	# The NoValueLabel should always display 0 (design decision)
	if no_label and no_label is Label:
		no_label.text = "0"
	if d1_label and d1_label is Label:
		d1_label.text = str(tens)
	if d2_label and d2_label is Label:
		d2_label.text = str(ones)

	# If the remaining count changed, play a dying-gauge flicker on the digit labels
	if last_deck_remaining != remaining:
		last_deck_remaining = remaining
		# Pick the two digit labels and flicker them like an old electronic gauge
		if d1_label and d1_label is Label:
			# stagger the two digits slightly for a more vintage feel
			_flicker_gauge_label(d1_label, int(tens), 0.0)
		if d2_label and d2_label is Label:
			_flicker_gauge_label(d2_label, int(ones), flicker_stagger)


func _flicker_gauge_label(lbl: Label, final_digit: int, delay: float = 0.0) -> void:
	# Emulate an old 7-seg dying gauge: rapid jitter through digits, occasional blanks, then settle.
	# Non-blocking: use a tween and timers to schedule updates.
	if not lbl or not lbl.is_inside_tree():
		return
	# Cancel any ongoing tweens on the label
	var t = create_tween()
	# Start after delay
	if delay > 0.0:
		t.tween_interval(delay)

	# Sequence of jitter updates: alternate between random digits and blanks
	for i in range(flicker_steps):
		var dt = flicker_step_time
		var show_blank = randf() < flicker_blank_chance
		var rnd_digit = str(randi() % 10)
		if show_blank:
			t.tween_callback(func():
				if is_instance_valid(lbl):
					lbl.text = " "
			)
		else:
			t.tween_callback(func():
				if is_instance_valid(lbl):
					lbl.text = rnd_digit
			)
		t.tween_interval(dt)

	# Final settle to the actual digit (short pause then set)
	t.tween_interval(flicker_final_pause)
	t.tween_callback(func():
		if is_instance_valid(lbl):
			lbl.text = str(final_digit)
	)


func get_hand_cards(is_player: bool = true) -> Array:
	var cards: Array = []
	for child in get_children():
		if child and "is_player_card" in child and child.is_player_card == is_player:
			cards.append(child)
	return cards


func draw_single_card_to_hand(is_player: bool) -> Node2D:
	"""Draws one card from the deck to the next open hand slot."""
	if is_deck_depleted():
		print("Deck is empty, cannot draw.")
		return null

	# 1. Find the next available hand slot
	var hand_slots_path = "../HandSlots" if is_player else "../OpponentHandSlots"
	var hand_slots_root = get_node_or_null(hand_slots_path)
	if not hand_slots_root:
		push_error("CardManager: Cannot find hand slots at %s" % hand_slots_path)
		return null

	var existing_cards_count = get_hand_cards(is_player).size()
	var all_slots = hand_slots_root.get_children()

	if existing_cards_count >= all_slots.size():
		# Diagnostic: print counts to help debug races where a played card hasn't been removed yet
		print("No open hand slots. existing_cards_count=", existing_cards_count, "slots=", all_slots.size())
		# Optionally list slot names for debugging
		var slot_names = []
		for s in all_slots:
			slot_names.append(str(s.name))
		print("Hand slots:", slot_names)
		return null

	var target_slot = all_slots[existing_cards_count]

	# 2. Instantiate and set up the new card
	var card_instance: Node2D = card_scene.instantiate()
	# Ensure consistent visual scale for drawn cards (match interactiveCard.tscn scale)
	card_instance.scale = Vector2(0.4, 0.4)
	add_child(card_instance)

	# Set card data from the deck
	if draw_index < deck.size():
		var card_name = deck[draw_index]
		card_instance.set_card_data(card_name)
		draw_index += 1
		_update_deck_counter()

	card_instance.is_player_card = is_player
	card_instance.card_index = existing_cards_count

	# 3. Animate the card from the deck to the slot
	var deck_node = get_node_or_null("/root/main/Parallax/Deck")
	card_instance.global_position = deck_node.global_position if deck_node else self.global_position

	var tween = create_tween()
	tween.tween_property(card_instance, "global_position", target_slot.global_position, 0.6).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(card_instance, "rotation", target_slot.rotation, 0.6)

	await tween.finished

	# Set its final home position after the animation
	if card_instance.has_method("set_home_position"):
		card_instance.set_home_position(target_slot.global_position, target_slot.rotation)

	return card_instance


func instantiate_top_card_for_peek() -> Node2D:
	"""Creates a temporary instance of the top card of the deck."""
	if is_deck_depleted():
		return null

	var card_instance: Node2D = card_scene.instantiate()
	var card_name = deck[draw_index]
	if card_instance.has_method("set_card_data"):
		card_instance.set_card_data(card_name)

	# Mark this card so we know to delete it later
	card_instance.set_meta("is_temp_peek", true)

	# It's not yet in the scene tree; caller should add it where appropriate
	return card_instance


func is_deck_depleted() -> bool:
	"""Return true when there are no more cards left to draw from the deck."""
	if typeof(deck) != TYPE_ARRAY:
		return true
	return draw_index >= deck.size()


func discard_all_hands() -> void:
	"""
	Animate all cards from both hands into the discard pile, and return when
	all move/disintegration animations have completed and the cards have been
	handed off to the discard pile.

	This function is awaitable by callers because it uses `await` internally.
	"""
	var player_cards = get_hand_cards(true)
	var opponent_cards = get_hand_cards(false)
	var all_cards = []
	for c in player_cards:
		all_cards.append(c)
	for c in opponent_cards:
		all_cards.append(c)

	if all_cards.size() == 0:
		return

	var main_node = get_node_or_null("/root/main")
	var discard_node = null
	if main_node and "discard_pile_node" in main_node:
		discard_node = main_node.discard_pile_node
	if not discard_node:
		var current_scene = get_tree().get_current_scene()
		if current_scene:
			discard_node = current_scene.find_node("DiscardPile", true, false)

	# Target position fallback (center of discard node or the scene center)
	var target_global_pos = Vector2.ZERO
	if discard_node and discard_node is Node2D:
		target_global_pos = discard_node.global_position
	else:
		var vp = get_viewport().get_visible_rect()
		target_global_pos = vp.position + vp.size * 0.5

	# Stagger times between cards (used by the arc fallback)
	var move_duration = 0.36

	# Launch disintegration for all cards that support it, and start arc
	# animations in parallel for cards that don't. Then wait until all
	# cards have been handed off to the discard pile (or timeout).
	var dz_shader = null
	for zone in get_tree().get_nodes_in_group("drop_zones"):
		if zone and zone.has_method("on_card_dropped") and "disintegration_shader" in zone:
			dz_shader = zone.disintegration_shader
			break

	var anim_tweens: Array = []
	var disintegrating_cards: Array = []

	var scene_root = get_tree().get_current_scene()

	for card in all_cards:
		if not is_instance_valid(card):
			continue

		# Ensure card is reparented to the current scene root so global_position tweens work
		if scene_root and card.get_parent() != scene_root:
			card.get_parent().remove_child(card)
			scene_root.add_child(card)

		if card.has_method("apply_disintegration"):
			# Trigger disintegration simultaneously
			card.apply_disintegration(dz_shader, 0.0, 1.0, 0.9, Tween.EASE_IN, Tween.TRANS_SINE)
			disintegrating_cards.append(card)
		else:
			# Fallback: animate arc-to-discard in parallel
			var spawn_pos = card.global_position
			var mid_pos = Vector2(lerp(spawn_pos.x, target_global_pos.x, 0.5), lerp(spawn_pos.y, target_global_pos.y, 0.5) - 120)
			var t = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
			t.tween_method(func(progress):
				var p1 = spawn_pos.lerp(mid_pos, progress)
				var p2 = mid_pos.lerp(target_global_pos, progress)
				if is_instance_valid(card):
					card.global_position = p1.lerp(p2, progress)
			, 0.0, 1.0, move_duration)
			if card is CanvasItem:
				t.parallel().tween_property(card, "scale", card.scale * 0.92, move_duration * 0.6)
				t.parallel().tween_property(card, "rotation", card.rotation + deg_to_rad(6.0), move_duration)
			anim_tweens.append({"tween": t, "card": card})

	# Wait for all non-disintegration tweens to finish, then hand off those cards
	for entry in anim_tweens:
		var tw = entry["tween"]
		var c = entry["card"]
		await tw.finished
		if main_node and main_node.has_method("add_to_discard_pile") and is_instance_valid(c):
			main_node.add_to_discard_pile(c)
		elif discard_node and discard_node.has_method("add_card") and is_instance_valid(c):
			discard_node.add_card(c)
		else:
			if is_instance_valid(c):
				c.queue_free()

	# Now wait for disintegrating cards to be handed to the discard node
	var waited_total = 0.0
	var poll_dt = 0.05
	var timeout_total = 6.0
	if disintegrating_cards.size() > 0:
		while waited_total < timeout_total:
			var all_done = true
			for dcard in disintegrating_cards:
				if not is_instance_valid(dcard):
					continue
				if discard_node:
					if dcard.get_parent() != discard_node:
						all_done = false
						break
				else:
					# If there's no discard node to poll, assume the card will free
					# itself or be reparented by the card logic; just wait a short time
					all_done = false
					break
			if all_done:
				break
			await get_tree().create_timer(poll_dt).timeout
			waited_total += poll_dt
		# If no discard_node, give a small grace period to let cards finish
		if not discard_node:
			await get_tree().create_timer(0.9).timeout

	# Finally, ensure both hands are relaid out
	relayout_hand(true)
	relayout_hand(false)


func relayout_hand(is_player: bool = true) -> void:
	"""Reposition existing cards to fill gaps using HandSlots."""
	
	# relayout_hand called

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

	# Sort: unlocked cards first, then locked cards, each group by card_index
	cards.sort_custom(Callable(self, "_sort_hand_cards"))

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
		# Always set home position before tween to ensure snap-back works
		card.set_home_position(slot["global_pos"], slot["rot"])
		# tween card to slot
		var t = create_tween()
		t.tween_property(card, "global_position", slot["global_pos"], relayout_duration).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		t.parallel().tween_property(card, "rotation", slot["rot"], relayout_duration)
		# set home when tween finishes (redundant but safe)
		_set_home_after_delay(card, slot["global_pos"], slot["rot"], relayout_duration)
		# z_index: unlocked cards always above locked, and later cards above earlier
		if card.has_method("set_locked") and "is_locked" in card:
			# Unlocked cards get higher z_index
			card.z_index = 200 + i if not card.is_locked else 100 + i
		else:
			card.z_index = 200 + i
		# small stagger between each card start
		if relayout_stagger > 0:
			await get_tree().create_timer(relayout_stagger).timeout

# Custom sort: unlocked cards first, then locked, each by card_index
func _sort_hand_cards(a, b) -> int:
	var a_locked = ("is_locked" in a and a.is_locked)
	var b_locked = ("is_locked" in b and b.is_locked)
	if a_locked == b_locked:
		var ai = 0
		var bi = 0
		if "card_index" in a:
			ai = int(a.card_index)
		if "card_index" in b:
			bi = int(b.card_index)
		return ai - bi
	return int(a_locked) - int(b_locked)


func _sort_by_card_index(a, b) -> int:
	var ai = 0
	var bi = 0
	if "card_index" in a:
		ai = int(a.card_index)
	if "card_index" in b:
		bi = int(b.card_index)
	return ai - bi
