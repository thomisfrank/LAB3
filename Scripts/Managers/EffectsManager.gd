# EffectManager.gd
extends Node

# We will need references to other managers to execute effects
var game_manager: Node
var card_manager: Node
var turn_manager: Node

# Signal emitted when a peek card is positioned so external systems (or the editor)
# can inspect the computed global position and z-index for debugging.
signal peek_card_positioned(global_pos, z_index)

# Exported debug-friendly properties so you can see the last peek placement in the Inspector
@export var last_peek_card_global_pos: Vector2 = Vector2.ZERO
@export var last_peek_card_z_index: int = 0

# Optional inspector-controlled override: when enabled the EffectsManager will place
# peek cards at `peek_position_override` instead of computing the viewport center.
@export_group("Peek Override")
@export var use_peek_position_override: bool = false
@export var peek_position_override: Vector2 = Vector2.ZERO

# (No debug marker exports here in production.)

# Helper: attempt to resolve CardManager via multiple known locations
func _resolve_card_manager() -> void:
	if card_manager and is_instance_valid(card_manager):
		return
	# Try via GameManager first
	if game_manager and game_manager.has_method("get_manager"):
		card_manager = game_manager.get_manager("CardManager")
	# Scene fallbacks
	if not card_manager:
		card_manager = get_node_or_null("/root/main/Parallax/CardManager")
	if not card_manager:
		card_manager = get_node_or_null("/root/main/Managers/CardManager")
	if not card_manager:
		var cs = get_tree().get_current_scene()
		if cs and cs.has_method("find_node"):
			card_manager = cs.find_node("CardManager", true, false)
	if not card_manager:
		push_warning("EffectManager: CardManager not found via known fallbacks.")

func _ready() -> void:
	# Robust GameManager lookup: support autoload (/root/GameManager), scene path, parent, and current scene find
	var gm: Node = null
	gm = get_node_or_null("/root/GameManager")
	if not gm:
		gm = get_node_or_null("/root/main/Managers/GameManager")
	if not gm:
		var manager_container = get_parent()
		if manager_container:
			gm = manager_container.get_node_or_null("GameManager")
	if not gm:
		var current_scene = get_tree().get_current_scene()
		if current_scene and current_scene.has_method("find_node"):
			gm = current_scene.find_node("GameManager", true, false)

	if not gm:
		# Defer in case GameManager is an autoload or registers later
		push_warning("EffectManager: GameManager not found during _ready; deferring registration and lookup.")
		call_deferred("_deferred_gm_lookup")
		return

	game_manager = gm
	if game_manager and game_manager.has_method("register_manager"):
		game_manager.register_manager("EffectManager", self)

	# Get references to other managers via GameManager if available
	if game_manager and game_manager.has_method("get_manager"):
		card_manager = game_manager.get_manager("CardManager")
		turn_manager = game_manager.get_manager("TurnManager")

func _deferred_gm_lookup() -> void:
	var gm: Node = null
	gm = get_node_or_null("/root/GameManager")
	if not gm:
		gm = get_node_or_null("/root/main/Managers/GameManager")
	if not gm:
		var manager_container = get_parent()
		if manager_container:
			gm = manager_container.get_node_or_null("GameManager")
	if not gm:
		var current_scene = get_tree().get_current_scene()
		if current_scene and current_scene.has_method("find_node"):
			gm = current_scene.find_node("GameManager", true, false)

	if not gm:
		push_error("EffectManager: GameManager not found after deferred lookup; effects may be disabled.")
		return

	game_manager = gm
	if game_manager and game_manager.has_method("register_manager"):
		game_manager.register_manager("EffectManager", self)
	if game_manager and game_manager.has_method("get_manager"):
		card_manager = game_manager.get_manager("CardManager")
		turn_manager = game_manager.get_manager("TurnManager")

# This is the main entry point for resolving any card effect
func resolve_effect(card_node: Node) -> void:
	if not is_instance_valid(card_node) or not "card_data" in card_node:
		push_error("EffectManager: Invalid card node passed.")
		return

	var effect_type = card_node.card_data.get("effect_type", "")

	match effect_type:
		"draw":
			# Kick off async draw
			_execute_draw(card_node)
		"peek_deck":
			_execute_peek_deck(card_node)
		"peek_hand":
			_execute_peek_hand(card_node)
		"swap":
			_execute_swap(card_node)
		_:
			print("No effect found for card: %s" % card_node.card_data.get("name", "Unknown"))

func _execute_draw(card_node: Node) -> void:
	print("Executing DRAW effect for card: ", card_node.card_data.get("name", "Unknown"))

	# Ensure we have a CardManager reference
	_resolve_card_manager()
	if not card_manager:
		push_error("EffectManager: CardManager reference is null.")
		return

	# Only draw and lock the new card; drop zone handles discarding the played card
	var new_card = await card_manager.draw_single_card_to_hand(true)
	if is_instance_valid(new_card) and new_card.has_method("set_locked"):
		new_card.set_locked(true)
		print("New card drawn and locked: ", new_card.card_data.get("name", "Unknown"))

func _execute_peek_deck(card_node: Node) -> void:
	print("Executing PEEK DECK effect for card: ", card_node.card_data.get("name", card_node.name))

	# Ensure we have GameManager and CardManager references (no fallback to /root/GameManager)
	if not game_manager:
		game_manager = get_node_or_null("/root/main/Managers/GameManager")
		if not game_manager:
			push_error("EffectManager: GameManager not found at /root/main/Managers/GameManager when executing peek_deck")
			return

	if not card_manager:
		_resolve_card_manager()

	if not card_manager:
		push_error("EffectManager: CardManager reference is null when executing peek_deck")
		return

	# Instantiate a temporary peek card (does not advance draw_index)
	var temp_card = card_manager.instantiate_top_card_for_peek()
	if not is_instance_valid(temp_card):
		push_error("EffectManager: Failed to instantiate top card for peek")
		return

	

	# Mark as a temporary peek card so other systems (GameManager) can special-case it
	temp_card.set_meta("is_temp_peek", true)

	# Ensure the peek card starts face-down so the showcase flow can flip it face-up
	# (visual flow: deck -> center as face-down, then flip_to_face=true flips it upward)
	# Prefer using the card API if available, otherwise show/hide face/back nodes.
	# We deliberately set start_face_up = false here.
	temp_card.start_face_up = false
	if temp_card.has_method("apply_start_face_up"):
		temp_card.apply_start_face_up()
	else:
		if temp_card.has_node("Visuals/CardViewport/SubViewport/Card/CardFace"):
			var face_node = temp_card.get_node("Visuals/CardViewport/SubViewport/Card/CardFace")
			var back_node = temp_card.get_node_or_null("Visuals/CardViewport/SubViewport/Card/CardBack")
			if face_node:
				face_node.hide()
			if back_node:
				back_node.show()

	# Position the card at the deck visual if available.
	# Honor an optional inspector override so the developer can force a placement.
	var parallax_node = get_node_or_null("/root/main/Parallax")
	var desired_global_pos: Vector2

	if use_peek_position_override:
		desired_global_pos = peek_position_override
	else:
		var deck_node = get_node_or_null("/root/main/Parallax/Deck")
		if deck_node:
			desired_global_pos = deck_node.global_position
		else:
			push_error("EffectsManager: Deck node not found at /root/main/Parallax/Deck and no override is set. Aborting peek.")
			temp_card.queue_free()
			return

	if parallax_node:
		# Parent to Parallax so the peek card moves with the parallax background
		parallax_node.add_child(temp_card)
		temp_card.global_position = desired_global_pos
	else:
		# No parallax container found; put directly in the scene root at the desired position
		var current_scene = get_tree().get_current_scene()
		if current_scene:
			current_scene.add_child(temp_card)
			temp_card.global_position = desired_global_pos

	# Give the peek card a high z-index so it appears above normal cards while showcased
	if temp_card is CanvasItem:
		# Give the peek card a high z-index so it appears above normal cards while showcased
		temp_card.z_index = 2000

		# Update exported debug properties and notify any listeners
		last_peek_card_global_pos = temp_card.global_position
		last_peek_card_z_index = temp_card.z_index
		if use_peek_position_override:
			print("EffectManager: using inspector override for peek placement:", peek_position_override)
		print("EffectManager: positioned peek card at global_pos=", last_peek_card_global_pos, " z_index=", last_peek_card_z_index, " node_path=", get_path())
		emit_signal("peek_card_positioned", last_peek_card_global_pos, last_peek_card_z_index)

	# (Already parented above to either Parallax or the current scene.)

	# Hand off to GameManager to showcase and await completion
	if game_manager.has_method("showcase_card"):
		var options = [
			{
				"label": "KEEP",
				"callback": Callable(self, "_on_peek_deck_keep").bind(temp_card, card_node)
			},
			{
				"label": "REJECT",
				"callback": Callable(self, "_on_peek_deck_reject").bind(temp_card, card_node)
			}
		]
		await game_manager.showcase_card(temp_card, true, options)
	else:
		push_warning("EffectManager: GameManager has no showcase_card method; skipping showcase")

func _execute_peek_hand(card_node: Node) -> void:
	print("Executing PEEK HAND effect for card: ", card_node.card_data.get("name", "Unknown"))

	# Ensure we have GameManager and CardManager references (no fallback to /root/GameManager)
	if not game_manager:
		game_manager = get_node_or_null("/root/main/Managers/GameManager")
		if not game_manager:
			push_error("EffectManager: GameManager not found at /root/main/Managers/GameManager when executing peek_hand")
			return

	if not card_manager:
		_resolve_card_manager()

	if not card_manager:
		push_error("EffectManager: CardManager reference is null when executing peek_hand")
		return

	# 1. Get the list of cards the player can choose from (the opponent's hand)
	var opponent_cards = card_manager.get_hand_cards(false) # false for opponent

	if opponent_cards.is_empty():
		print("Opponent has no cards to peek at.")
		return

	# 2. Tell the GameManager to enter selection mode.
	# We pass it the list of cards and tell it WHICH function to call when one is chosen.
	if game_manager.has_method("enter_selection_mode"):
		# Bind 'card_node' (the PeekHand card) to the callback so the next function receives both cards
		var callback = Callable(self, "_on_peek_card_selected").bind(card_node)
		game_manager.enter_selection_mode(opponent_cards, callback)
		# Do not advance the turn yet; wait until the peek/showcase flow completes.
		return
	else:
		push_error("EffectManager: GameManager has no enter_selection_mode method")


func _on_peek_card_selected(selected_opponent_card: Node, played_card: Node):
	"""This function runs AFTER the player has selected an opponent's card."""
	print("EFFECT MANAGER: Peek selection successful. Creating temp card for showcase.")

	# Create a temporary copy of the selected opponent card for the showcase
	var card_manager_ref = self.card_manager if self.card_manager else get_node_or_null("/root/main/Managers/CardManager")
	if not card_manager_ref:
		push_error("EffectManager: CardManager reference is null when creating temp peek hand card")
		return

	# Create a temp card instance and copy card data
	var temp_card = card_manager_ref.card_scene.instantiate()
	if temp_card.has_method("set_card_data"):
		temp_card.set_card_data(selected_opponent_card.card_data.get("name"))
	temp_card.set_meta("is_temp_peek", true)

	# Ensure the temp card is face up for the showcase
	temp_card.start_face_up = true
	if temp_card.has_method("apply_start_face_up"):
		temp_card.apply_start_face_up()
	# Force face up in case the above is not enough
	if temp_card.has_node("Visuals/CardViewport/SubViewport/Card/CardFace") and temp_card.has_node("Visuals/CardViewport/SubViewport/Card/CardBack"):
		temp_card.get_node("Visuals/CardViewport/SubViewport/Card/CardFace").show()
		temp_card.get_node("Visuals/CardViewport/SubViewport/Card/CardBack").hide()

	# Place temp card at the same position as the real card for smooth animation
	temp_card.global_position = selected_opponent_card.global_position
	temp_card.rotation = selected_opponent_card.rotation

	# Add to the same parent as the real card (or to the scene root if not possible)
	if selected_opponent_card.get_parent():
		selected_opponent_card.get_parent().add_child(temp_card)
	else:
		get_tree().get_current_scene().add_child(temp_card)

	# 1. Define the options we want to show the player.
	var options = [
		{
			"label": "SWAP",
			# We bind BOTH cards to the final swap function (real cards).
			"callback": Callable(self, "_on_peek_hand_swap_chosen").bind(played_card, selected_opponent_card)
		},
		{
			"label": "CANCEL",
			"callback": Callable(self, "_on_peek_hand_cancel_chosen")
		}
	]

	# 2. Call the showcase function WITH the options array, using the temp card
	if game_manager.has_method("showcase_card"):
		await game_manager.showcase_card(temp_card, true, options)
	else:
		push_warning("EffectManager: GameManager has no showcase_card method; cannot showcase temp peek hand card")

func _execute_swap(card_node: Node) -> void:
	print("Executing SWAP effect for card: ", card_node.card_data.get("name", card_node.name))

	# Ensure GameManager and CardManager references (use canonical path)
	if not game_manager:
		game_manager = get_node_or_null("/root/main/Managers/GameManager")
		if not game_manager:
			push_error("EffectManager: GameManager not found at /root/main/Managers/GameManager when executing swap")
			return

	if not card_manager:
		_resolve_card_manager()
	if not card_manager:
		push_error("EffectManager: CardManager reference is null when executing swap")
		return

	var played_card: Node = card_node

	var opponent_cards = card_manager.get_hand_cards(false)

	if opponent_cards.is_empty():
		# The opponent's hand should never be empty. Treat this as a game-state error
		# rather than silently discarding the player's card. Inform the player and
		# return the played card to their hand so they can try a different play.
		var message = "Swap failed: opponent has no cards to swap with."
		print(message)

		# Try to show a user-facing message via InfoScreenManager (best-effort)
		var info_mgr = get_node_or_null("/root/main/Managers/InfoScreenManager")
		if info_mgr and info_mgr.has_method("set_text"):
			info_mgr.set_text(message)
		else:
			# Fallback to pushing an error to the console so it's not silent
			push_error("EffectManager: " + message)

		# Return the played card to the player's hand if possible.
		if card_manager and is_instance_valid(played_card):
			# Safely reparent the card back under CardManager
			var old_parent = played_card.get_parent()
			if old_parent and old_parent.has_method("remove_child"):
				old_parent.remove_child(played_card)
			card_manager.add_child(played_card)

			# Mark as player's card and set its index to the end of the player's hand
			played_card.is_player_card = true
			played_card.card_index = card_manager.get_hand_cards(true).size()

			# If the card supports setting a home position, place it near the expected slot
			if played_card.has_method("set_home_position"):
				var hand_slots_root = card_manager.get_node_or_null("../HandSlots")
				if hand_slots_root:
					var idx = played_card.card_index
					var slots = hand_slots_root.get_children()
					if idx >= 0 and idx < slots.size():
						played_card.set_home_position(slots[idx].global_position, slots[idx].rotation)

			# Finally, ask CardManager to relayout the player's hand so visuals update
			if card_manager.has_method("relayout_hand"):
				card_manager.relayout_hand(true)
		else:
			# As a last resort, keep the node in the main scene so it's not lost
			var scene_root = get_tree().get_current_scene()
			if scene_root and is_instance_valid(played_card):
				var old_parent2 = played_card.get_parent()
				if old_parent2 and old_parent2.has_method("remove_child"):
					old_parent2.remove_child(played_card)
				scene_root.add_child(played_card)

		return

	# Enter selection mode for the opponent's hand.
	# Bind the played_card so the callback receives it as an extra parameter.
	if game_manager.has_method("enter_selection_mode"):
		var cb = Callable(self, "_on_swap_selection_complete").bind(played_card)
		game_manager.enter_selection_mode(opponent_cards, cb)
	else:
		push_error("EffectManager: GameManager has no enter_selection_mode method; cannot perform swap")


func _on_swap_selection_complete(selected_opponent_card: Node, played_card: Node) -> void:
	"""This function runs after the player has chosen an opponent's card to swap with."""
	print("Swap target selected. Starting animation.")

	# Ensure we have GameManager reference
	if not game_manager:
		game_manager = get_node_or_null("/root/main/Managers/GameManager")
		if not game_manager:
			push_error("EffectManager: GameManager not found when attempting to perform swap animation")
			return

	# Ask GameManager to perform the visual swap animation if available
	if game_manager.has_method("_perform_card_swap_animation"):
		await game_manager._perform_card_swap_animation(played_card, selected_opponent_card)
	else:
		push_warning("EffectManager: GameManager has no _perform_card_swap_animation; performing instant swap")
		# Instant swap fallback: exchange card_data between nodes if possible
		if played_card.has_method("set_card_data") and selected_opponent_card.has_method("set_card_data") and played_card.has_method("get") and selected_opponent_card.has_method("get"):
			var p_name = played_card.card_data.get("name", null) if "card_data" in played_card else null
			var o_name = selected_opponent_card.card_data.get("name", null) if "card_data" in selected_opponent_card else null
			if p_name and o_name:
				played_card.set_card_data(o_name)
				selected_opponent_card.set_card_data(p_name)

	# After the swap, relayout both hands to make sure everything is in the right place.
	if card_manager and card_manager.has_method("relayout_hand"):
		card_manager.relayout_hand(true)  # Player hand
		card_manager.relayout_hand(false) # Opponent hand


# The player chose to keep the peeked card. Disintegrate temp card, draw/lock new card, then discard played card, then delay before advancing turn.
func _on_peek_deck_keep(temp_peek_card: Node, played_card: Node):
	print("EFFECT MANAGER: Player chose to KEEP the peeked card: %s" % temp_peek_card.name)

	# 1. Disintegrate and destroy the temp card
	var disintegration_shader = load("res://Scripts/Shader/disintegration.gdshader")
	if temp_peek_card.has_method("apply_disintegration"):
		temp_peek_card.apply_disintegration(disintegration_shader)
		await self._wait_for_temp_peek_discarded(temp_peek_card)
	else:
		temp_peek_card.queue_free()

	# 2. Disintegrate and discard the played card from the drop zone
	if is_instance_valid(played_card):
		if played_card.has_method("apply_disintegration"):
			played_card.apply_disintegration(disintegration_shader)
			await self._wait_for_temp_peek_discarded(played_card)
		else:
			played_card.queue_free()

	# 3. Draw and lock the top card of the deck (the peeked card)
	if not card_manager:
		_resolve_card_manager()

	var new_card = await card_manager.draw_single_card_to_hand(true)
	if is_instance_valid(new_card):
		new_card.set_locked(true)
	if card_manager and card_manager.has_method("relayout_hand"):
		card_manager.relayout_hand(true)

	# 4. Wait at least 1.5 seconds before advancing the turn/round
	await get_tree().create_timer(1.5).timeout

# Helper for awaiting the discard signal

var _temp_peek_discarded_cards := {}
func _wait_for_temp_peek_discarded(card):
	_temp_peek_discarded_cards[card] = false
	card.connect("moved_to_discard", Callable(self, "_on_temp_peek_discarded_flag").bind(card), CONNECT_ONE_SHOT)
	while not _temp_peek_discarded_cards[card]:
		await get_tree().process_frame
	_temp_peek_discarded_cards.erase(card)

func _on_temp_peek_discarded_flag(card):
	_temp_peek_discarded_cards[card] = true

# Dummy handler for moved_to_discard (required for connect)
func _on_temp_peek_discarded(_card, _is_keep):
	pass


func _on_peek_deck_reject(temp_peek_card: Node, played_card: Node):
	"""The player chose to reject the peeked card. Disintegrate temp card, return played card to hand locked and snapped back."""
	print("EFFECT MANAGER: Player chose to REJECT the peeked card: %s" % temp_peek_card.name)

	# 1. Disintegrate and destroy the temp card
	var disintegration_shader = load("res://Scripts/Shader/disintegration.gdshader")
	if temp_peek_card.has_method("apply_disintegration"):
		temp_peek_card.apply_disintegration(disintegration_shader)
		await self._wait_for_temp_peek_discarded(temp_peek_card)
	else:
		temp_peek_card.queue_free()

	# 2. Release the played card, lock it, and snap it back to the hand
	if not card_manager:
		_resolve_card_manager()
	if not card_manager:
		push_error("EffectManager: CardManager reference is null when rejecting peek deck card")
		return

	# Remove from current parent and add to CardManager
	var old_parent = played_card.get_parent()
	if old_parent and old_parent.has_method("remove_child"):
		old_parent.remove_child(played_card)
	card_manager.add_child(played_card)

	# Just mark as player's card and relayout the hand; relayout_hand will animate and assign slots
	played_card.is_player_card = true
	if played_card.has_method("set_locked"):
		played_card.set_locked(true)
	if card_manager.has_method("relayout_hand"):
		card_manager.relayout_hand(true)

	# Lock the card
	if played_card.has_method("set_locked"):
		played_card.set_locked(true)

	# Relayout the hand to update visuals and z-order
	if card_manager.has_method("relayout_hand"):
		card_manager.relayout_hand(true)

func _on_peek_hand_swap_chosen(played_card: Node, opponent_card: Node):
	# 5. Reassign card_index for all cards in both hands to prevent overlap
	if card_manager:
		var player_cards = card_manager.get_hand_cards(true)
		for i in range(player_cards.size()):
			if is_instance_valid(player_cards[i]):
				player_cards[i].card_index = i
		var opp_cards = card_manager.get_hand_cards(false)
		for i in range(opp_cards.size()):
			if is_instance_valid(opp_cards[i]):
				opp_cards[i].card_index = i
	# 5. Reassign card_index for all cards in both hands to prevent overlap
	if card_manager:
		var player_cards = card_manager.get_hand_cards(true)
		for i in range(player_cards.size()):
			if is_instance_valid(player_cards[i]):
				player_cards[i].card_index = i
		var opp_cards = card_manager.get_hand_cards(false)
		for i in range(opp_cards.size()):
			if is_instance_valid(opp_cards[i]):
				opp_cards[i].card_index = i
	"""The player chose to SWAP after peek hand. Disintegrate temp card, then move real cards."""
	print("EFFECT MANAGER: Player chose to SWAP after peek hand.")

	# 1. Disintegrate and destroy the temp card (the showcased card)
	# The cancel handler is now a standalone function below.

	# 2. Move the real opponent card to the player's hand, lock it, and force face up
	var card_manager_ref = self.card_manager if self.card_manager else get_node_or_null("/root/main/Managers/CardManager")
	if is_instance_valid(opponent_card):
		opponent_card.is_player_card = true
		if opponent_card.has_method("set_locked"):
			opponent_card.set_locked(true)
		# Force face up
		opponent_card.start_face_up = true
		if opponent_card.has_method("apply_start_face_up"):
			opponent_card.apply_start_face_up()
		if opponent_card.has_node("Visuals/CardViewport/SubViewport/Card/CardFace") and opponent_card.has_node("Visuals/CardViewport/SubViewport/Card/CardBack"):
			opponent_card.get_node("Visuals/CardViewport/SubViewport/Card/CardFace").show()
			opponent_card.get_node("Visuals/CardViewport/SubViewport/Card/CardBack").hide()
		# Move to player's hand (reparent under CardManager if needed)
		if card_manager_ref:
			if opponent_card.get_parent() != card_manager_ref:
				if opponent_card.get_parent() and opponent_card.get_parent().has_method("remove_child"):
					opponent_card.get_parent().remove_child(opponent_card)
				card_manager_ref.add_child(opponent_card)

	# 3. Move the played card to the opponent's hand, unlock it, and force face down
	if is_instance_valid(played_card):
		played_card.is_player_card = false
		if played_card.has_method("set_locked"):
			played_card.set_locked(false)
		# Force face down
		played_card.start_face_up = false
		if played_card.has_method("apply_start_face_up"):
			played_card.apply_start_face_up()
		if played_card.has_node("Visuals/CardViewport/SubViewport/Card/CardFace") and played_card.has_node("Visuals/CardViewport/SubViewport/Card/CardBack"):
			played_card.get_node("Visuals/CardViewport/SubViewport/Card/CardFace").hide()
			played_card.get_node("Visuals/CardViewport/SubViewport/Card/CardBack").show()
		if card_manager_ref:
			if played_card.get_parent() != card_manager_ref:
				if played_card.get_parent() and played_card.get_parent().has_method("remove_child"):
					played_card.get_parent().remove_child(played_card)
				card_manager_ref.add_child(played_card)

	# 4. Reassign card_index for all cards in both hands to prevent overlap
	if card_manager:
		var player_cards = card_manager.get_hand_cards(true)
		for i in range(player_cards.size()):
			if is_instance_valid(player_cards[i]):
				player_cards[i].card_index = i
		var opp_cards = card_manager.get_hand_cards(false)
		for i in range(opp_cards.size()):
			if is_instance_valid(opp_cards[i]):
				opp_cards[i].card_index = i
		# Now relayout both hands
		card_manager.relayout_hand(true)
		card_manager.relayout_hand(false)

# This function runs when the player chooses to cancel after peeking at an opponent's card.
func _on_peek_hand_cancel_chosen(played_card: Node = null):
	print("EFFECT MANAGER: Player cancelled after peek hand.")
	# 1. Destroy the temp card (the showcased card)
	if is_instance_valid(game_manager) and is_instance_valid(game_manager.showcased_card):
		var temp_card = game_manager.showcased_card
		if temp_card.has_method("disintegrate"):
			temp_card.disintegrate()
		temp_card.queue_free()
		game_manager.showcased_card = null
		# Hide the showcase UI and input catcher layer immediately
		if game_manager.ui_manager and game_manager.ui_manager.has_method("hide_showcase_options"):
			game_manager.ui_manager.hide_showcase_options()
		if game_manager.input_catcher_layer:
			game_manager.input_catcher_layer.hide()
	# 2. Snap the played card back to the player's hand (if provided)
	if played_card and is_instance_valid(played_card):
		played_card.is_player_card = true
		if played_card.has_method("set_locked"):
			played_card.set_locked(true)
		if card_manager:
			if played_card.get_parent() != card_manager:
				if played_card.get_parent() and played_card.get_parent().has_method("remove_child"):
					played_card.get_parent().remove_child(played_card)
				card_manager.add_child(played_card)
			# Set card_index to the end of the player's hand before relayout
			var player_cards = card_manager.get_hand_cards(true)
			played_card.card_index = player_cards.size()
			# Relayout both hands to ensure correct slotting and snap-back
			card_manager.relayout_hand(true)
			card_manager.relayout_hand(false)
