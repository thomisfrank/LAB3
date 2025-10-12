extends Node

# --- Enums for Game State and Players ---

enum GameState {
	SETUP,          # Initializing managers, shuffling deck, dealing hands
	ROUND_START,    # Transition between rounds, deciding who goes first
	IN_ROUND,       # The main loop where turns happen
	ROUND_END,      # Calculating scores, updating player totals
	GAME_OVER       # Deck is depleted, final score check
}

enum Player {
	PLAYER_ONE, # You
	PLAYER_TWO  # Opponent
}

# --- Signals (used for loose coupling between managers) ---
signal game_state_changed(new_state)
signal showcase_closed

# --- Public References to Other Managers ---

var card_manager: Node
var round_manager: Node
var turn_manager: Node
var ui_manager: Node
var effect_manager: Node
var managers: Dictionary = {}

# --- Persistent Game Data ---
var current_game_state: int = -1  # Start uninitialized so first set_game_state(SETUP) actually runs
# Dictionary to hold the scores: {Player.PLAYER_ONE: score, Player.PLAYER_TWO: score}
var total_scores: Dictionary = {}

# Showcase helpers
var showcased_card: Node = null # The card currently in the center of the screen
var return_info: Dictionary = {} # To store the card's original position, parent, etc.
var showcase_marker: Marker2D = null

# Explicit input catcher nodes (no fallbacks)
@onready var input_catcher_button = get_node_or_null("/root/main/FrontLayerUI/InputCatcher/Catcher")
@onready var input_catcher_layer = get_node_or_null("/root/main/FrontLayerUI/InputCatcher")


# --- ADD these new powerful variables ---
var is_in_selection_mode: bool = false
var selection_callback: Callable # This will store WHAT to do after a selection is made
var selectable_cards: Array = [] # This will store WHICH cards can be selected

# --- Showcase Settings (editable in the Inspector) ---
@export_group("Showcase Settings")
@export var require_showcase_marker: bool = false


# --- Initialization and Start (GDScript _ready function) ---

func _ready() -> void:
	# 1. Initialize scores
	total_scores[Player.PLAYER_ONE] = 0
	total_scores[Player.PLAYER_TWO] = 0
	
	# 2. Find other managers in the scene 
	# Try to resolve managers from the scene tree (if GameManager is placed in-scene)
	var manager_container = get_parent()
	if manager_container:
		card_manager = manager_container.get_node_or_null("CardManager")
		round_manager = manager_container.get_node_or_null("RoundManager")
		turn_manager = manager_container.get_node_or_null("TurnManager")
		ui_manager = manager_container.get_node_or_null("UIManager")

		# If GameManager is running as an autoload (parent is root), try to locate
		# the scene's Managers container and register any managers found there so
		# other scripts can call get_manager("Foo") reliably without brittle paths.
		if manager_container == get_tree().get_root():
			var scene_managers = get_node_or_null("/root/main/Managers")
			if scene_managers:
				if not card_manager:
					card_manager = scene_managers.get_node_or_null("CardManager")
				if not round_manager:
					round_manager = scene_managers.get_node_or_null("RoundManager")
				if not turn_manager:
					turn_manager = scene_managers.get_node_or_null("TurnManager")
				if not ui_manager:
					ui_manager = scene_managers.get_node_or_null("UIManager")

			# Register any managers we discovered so get_manager() will work for others
			if card_manager:
				register_manager("CardManager", card_manager)
			if round_manager:
				register_manager("RoundManager", round_manager)
			if turn_manager:
				register_manager("TurnManager", turn_manager)
			if ui_manager:
				register_manager("UIManager", ui_manager)

			# Ensure EffectManager exists: try to discover or instantiate it so scene code can find it
			if not managers.has("EffectManager"):
				var mgrs_container = get_node_or_null("/root/main/Managers")
				if mgrs_container:
					# Try common node name variants first
					var existing_em = mgrs_container.get_node_or_null("EffectManager")
					if not existing_em:
						existing_em = mgrs_container.get_node_or_null("EffectsManager")
					if existing_em:
						register_manager("EffectManager", existing_em)
					else:
						# Try to load the script and instantiate it under Managers so it can register
						var em_script_path = "res://Scripts/Managers/EffectsManager.gd"
						if FileAccess.file_exists(em_script_path):
							var em_script = load(em_script_path)
							if em_script:
								var em_node = Node.new()
								em_node.set_script(em_script)
								em_node.name = "EffectsManager"
								mgrs_container.add_child(em_node)
								# it will register itself in its _ready; we still pre-register to be safe
								register_manager("EffectManager", em_node)

			# If an EffectsManager is present, don't automatically sync showcase_position.
			# GameManager uses a ShowcaseMarker node (placed in the scene) as the authoritative target.
		
	# Also try to get CardManager from Parallax if not found in Managers
	if not card_manager:
		card_manager = get_node_or_null("/root/main/Parallax/CardManager")

	# If this script is used as an autoload (singleton) then other managers
	# should register themselves using register_manager(). We avoid hard
	# failing here because order of _ready() calls is not guaranteed.
	
	# 3. Start the game setup (deferred so scene nodes can finish _ready and register)
	# print("GameManager: deferring set_game_state(SETUP)")
	call_deferred("set_game_state", GameState.SETUP)

	# Connect input catcher button if present, and ensure the layer starts hidden
	if input_catcher_button:
		if not input_catcher_button.is_connected("pressed", Callable(self, "_on_showcase_closed")):
			input_catcher_button.connect("pressed", Callable(self, "_on_showcase_closed"))
	if input_catcher_layer:
		input_catcher_layer.hide()

	print("GameManager ready. Is UIManager valid? ", is_instance_valid(ui_manager))

	# --- Showcase Option Signal Connection ---
	if ui_manager and not ui_manager.is_connected("showcase_option_selected", Callable(self, "_on_showcase_option_pressed")):
		ui_manager.connect("showcase_option_selected", Callable(self, "_on_showcase_option_pressed"))


# --- State Handler ---

# Changes the current state of the game and calls the corresponding entry method.
func set_game_state(new_state: int) -> void:
	if current_game_state == new_state:
		return

	# print("GameManager: Game State Transition: %s -> %s" % [GameState.keys()[current_game_state], GameState.keys()[new_state]])
	current_game_state = new_state
	
	# Emit a signal so other managers can react to state changes
	emit_signal("game_state_changed", new_state)

	match new_state:
		GameState.SETUP:
			_handle_setup()
		GameState.ROUND_START:
			_handle_round_start()
		GameState.IN_ROUND:
			_handle_in_round()
		GameState.ROUND_END:
			_handle_round_end()
		GameState.GAME_OVER:
			_handle_game_over()


# --- State Handler Methods (Private) ---

func _handle_setup() -> void:
	# 1. Card deck initialization not needed - CardManager draws cards on demand
	# print("GameManager: _handle_setup, card_manager is:", card_manager)
	
	# 2. If there's a UIManager, play the start sequence and wait for it to finish
	# Ensure ui_manager is resolved (try registered managers if autoloaded)
	if not ui_manager and has_method("get_manager"):
		ui_manager = get_manager("UIManager")

	if not ui_manager:
		# Fallback: try scene path
		ui_manager = get_node_or_null("/root/main/FrontLayerUI/UIPanel")

	# print("GameManager: _handle_setup, ui_manager is:", ui_manager)

	# Show the static loading overlay at setup if UIManager supports it
	if ui_manager and ui_manager.has_method("show_loading"):
		ui_manager.show_loading()

	# Ensure action panels start in the 'off' state if UIManager supports it
	if ui_manager and ui_manager.has_method("set_active_player"):
		# Pass false to indicate panels should be in the 'off' visual
		ui_manager.set_active_player(false)

	# Connect CardManager.draw_started to hide the static loading overlay
	if card_manager and card_manager.has_method("connect") and ui_manager and ui_manager.has_method("hide_loading"):
		if not card_manager.is_connected("draw_started", Callable(self, "_on_draw_started")):
			card_manager.connect("draw_started", Callable(self, "_on_draw_started"))

	if ui_manager and ui_manager.has_method("show_game_start_sequence"):
		# Show sequence: pass first round number and who starts (default to player)
		var is_player_start = true
		# print("GameManager: calling show_game_start_sequence on UIManager")
		ui_manager.connect("start_sequence_finished", Callable(self, "_on_start_sequence_finished"))
		ui_manager.show_game_start_sequence(1, is_player_start)
	else:
		# 3. Move to the first round start immediately
		set_game_state(GameState.ROUND_START)


## EffectsManager signals are intentionally not auto-synced. Use a ShowcaseMarker node.


func _on_start_sequence_finished() -> void:
	# Unregister the signal if needed and proceed
	if ui_manager:
		ui_manager.disconnect("start_sequence_finished", Callable(self, "_on_start_sequence_finished"))
	set_game_state(GameState.ROUND_START)


func _on_draw_started() -> void:
	# Called when CardManager begins drawing cards. Hide the static loading overlay
	# print("GameManager: detected draw_started from CardManager; hiding loading overlay")
	if ui_manager and ui_manager.has_method("hide_loading"):
		ui_manager.hide_loading()

	# Turn on action panels (make them visible) when drawing starts
	if ui_manager and ui_manager.has_method("set_active_player"):
		# Pass true to indicate panels should be in the 'on' visual
		ui_manager.set_active_player(true)

func _handle_round_start() -> void:
	# The RoundManager handles card drawing and deciding the first player.
	if round_manager:
		var starting_player: int = _determine_starting_player()
		# print("GameManager: instructing RoundManager to start new round with starter=", starting_player)
		round_manager.start_new_round(starting_player) # Assuming a method named 'start_new_round'

	# Once RoundManager is done with setup, it calls back:
	# GameManager.set_game_state(GameManager.GameState.IN_ROUND)

func _handle_in_round() -> void:
	# The TurnManager takes over the loop from here.
	if turn_manager:
		# TurnManager is activated by RoundManager after dealing; no action needed here.
		# If you want GameManager to explicitly start turns, call turn_manager.start_turn_management(starting_player)
		pass

	# The TurnManager will eventually call back:
	# GameManager.set_game_state(GameManager.GameState.ROUND_END)

func _handle_round_end() -> void:
	if not round_manager or not card_manager or not ui_manager:
		push_error("Missing manager for round end logic.")
		return
		
	# 1. Calculation: Players’ cards are revealed and counted up.
	var p1_score: int = round_manager.calculate_player_score(Player.PLAYER_ONE)
	var p2_score: int = round_manager.calculate_player_score(Player.PLAYER_TWO)

	# Capture the card lists (name + value) for the end-round UI before we discard them
	var player_cards_info: Array = []
	var opponent_cards_info: Array = []
	var card_data_loader = get_node_or_null("/root/CardDataLoader")
	if card_manager and card_manager.has_method("get_hand_cards"):
		# Gather cards from both the active hand and the discard pile so played cards
		# (which may already have been moved to the DiscardPile) are included.
		var hand_nodes = card_manager.get_hand_cards(true)
		var combined_player_nodes: Array = []
		for n in hand_nodes:
			combined_player_nodes.append(n)

		# Try to include any player's cards that have already been moved to the discard pile
		var discard_node = null
		var main_node = get_node_or_null("/root/main")
		if main_node and "discard_pile_node" in main_node:
			discard_node = main_node.discard_pile_node
		if not discard_node:
			var current_scene = get_tree().get_current_scene()
			if current_scene:
				discard_node = current_scene.find_node("DiscardPile", true, false)
		if discard_node:
			for child in discard_node.get_children():
				if child and "is_player_card" in child and child.is_player_card:
					combined_player_nodes.append(child)

		print("[GameManager] combined player nodes count:", combined_player_nodes.size())
		for idx in range(combined_player_nodes.size()):
			var node = combined_player_nodes[idx]
			if not is_instance_valid(node):
				print("[GameManager] combined player node", idx, "is invalid")
				continue
			print("[GameManager] combined player node", idx, "card_name:", node.card_name if "card_name" in node else "<no name>")
		for c in combined_player_nodes:
			if is_instance_valid(c) and "card_name" in c and c.card_name and card_data_loader:
				var data = card_data_loader.get_card_data(c.card_name)
				var val = 0
				if data and data.has("value"):
					val = int(data["value"])
				player_cards_info.append({"name": c.card_name, "value": val})

		# Opponent: combine hand and discard pile entries
		var o_hand_nodes = card_manager.get_hand_cards(false)
		var combined_opponent_nodes: Array = []
		for n2 in o_hand_nodes:
			combined_opponent_nodes.append(n2)
		if discard_node:
			for child2 in discard_node.get_children():
				if child2 and "is_player_card" in child2 and not child2.is_player_card:
					combined_opponent_nodes.append(child2)

		print("[GameManager] combined opponent nodes count:", combined_opponent_nodes.size())
		for idx3 in range(combined_opponent_nodes.size()):
			var node3 = combined_opponent_nodes[idx3]
			if not is_instance_valid(node3):
				print("[GameManager] combined opponent node", idx3, "is invalid")
				continue
			print("[GameManager] combined opponent node", idx3, "card_name:", node3.card_name if "card_name" in node3 else "<no name>")
		for c in combined_opponent_nodes:
			if is_instance_valid(c) and "card_name" in c and c.card_name and card_data_loader:
				var data2 = card_data_loader.get_card_data(c.card_name)
				var val2 = 0
				if data2 and data2.has("value"):
					val2 = int(data2["value"])
				opponent_cards_info.append({"name": c.card_name, "value": val2})

	# 2. Declaration & Compensation: Player with the lowest total wins.
	_process_round_result(p1_score, p2_score)

	# Give the InfoScreen message a moment to be seen before continuing
	# (round end visual work should start about 1s after the message).
	var info_screen_manager = get_node_or_null("/root/InfoScreenManager")
	if info_screen_manager:
		# Wait a short moment so the player can register the info screen text
		await get_tree().create_timer(1.0).timeout

	# 3. End Round: All cards are discarded.
	if round_manager and round_manager.has_method("discard_hands"):
		await round_manager.discard_hands()

	# 4. Show end-round UI, then check for Game End or start the next round
	if ui_manager and ui_manager.has_method("show_end_round_screen"):
		# Put UIPanel into end-round mode: both action panels visible but pass buttons locked
		if ui_manager.has_method("set_end_round_mode"):
			ui_manager.set_end_round_mode(true)
		# Determine winner string for the UI call (0=player)
		var winner: int
		if p1_score < p2_score:
			winner = Player.PLAYER_ONE
		elif p2_score < p1_score:
			winner = Player.PLAYER_TWO
		else:
			winner = -1
		# Debug: log the scores and card info passed to the UI
		print("[GameManager] show_end_round_screen -> winner:", winner, "p1_score:", p1_score, "p2_score:", p2_score)
		print("[GameManager] player_cards_info (size):", player_cards_info.size(), "contents:", player_cards_info)
		print("[GameManager] opponent_cards_info (size):", opponent_cards_info.size(), "contents:", opponent_cards_info)
		# Determine awarded points for UI animation: winner receives their round total (loser gets 0)
		var awarded_p1 = 0
		var awarded_p2 = 0
		if p1_score < p2_score:
			awarded_p1 = p1_score
		elif p2_score < p1_score:
			awarded_p2 = p2_score
		ui_manager.show_end_round_screen(winner, p1_score, p2_score, player_cards_info, opponent_cards_info, awarded_p1, awarded_p2)
		if ui_manager.has_method("await_end_round_close"):
			await ui_manager.await_end_round_close()
		# Restore UIPanel state
		if ui_manager.has_method("set_end_round_mode"):
			ui_manager.set_end_round_mode(false)

	# After the end-round UI is dismissed, proceed
	if card_manager.is_deck_depleted():
		set_game_state(GameState.GAME_OVER)
	else:
		set_game_state(GameState.ROUND_START) # Start the next round

func _handle_game_over() -> void:
	var winner: int = _get_overall_winner()
	
	# Announce winner through the UI Manager
	if ui_manager:
		ui_manager.show_game_over_screen(winner, total_scores[winner])


# --- Public Utility Methods ---

# Adds points to a player's total score after a round win.
func add_score(player: int, points: int) -> void:
	# Safety: do not award non-positive points (defensive guard)
	if points <= 0:
		print("[GameManager] add_score called with non-positive points, ignoring ->", points)
		return

	total_scores[player] += points
	print("[GameManager] add_score -> player:", player, "points:", points, "new_total:", total_scores[player])
	if ui_manager:
		ui_manager.update_scores(total_scores) # Notify UI to refresh


# Managers registration API (useful when GameManager is an autoload singleon)
func register_manager(mgr_name: String, node: Node) -> void:
	managers[mgr_name] = node
	# print("GameManager: register_manager -> ", mgr_name, node)
	match mgr_name:
		"CardManager":
			card_manager = node
			# CardManager registered
		"RoundManager":
			round_manager = node
		"TurnManager":
			turn_manager = node
		"UIManager":
			ui_manager = node
			# UIManager registered

func get_manager(mgr_name: String) -> Node:
	return managers.get(mgr_name, null)

# Gets the current total score for a player.
func get_total_score(player: int) -> int:
	return total_scores.get(player, 0)

# --- Private Logic Helpers ---

func _determine_starting_player() -> int:
	# TODO: Implement alternating logic in RoundManager and retrieve here.
	# For the first round, let's return Player One.
	return Player.PLAYER_ONE 

func _process_round_result(p1_score: int, p2_score: int) -> Dictionary:
	# Decide the round winner and the awarded points without mutating totals.
	# Returns a dictionary: {"winner": int, "awarded_p1": int, "awarded_p2": int}
	var info_screen_manager = get_node_or_null("/root/InfoScreenManager")
	var awarded_p1 = 0
	var awarded_p2 = 0
	var winner = -1

	if p1_score < p2_score:
		awarded_p1 = p1_score
		winner = Player.PLAYER_ONE
		if info_screen_manager:
			info_screen_manager.display_round_winner(Player.PLAYER_ONE, p1_score)
	elif p2_score < p1_score:
		awarded_p2 = p2_score
		winner = Player.PLAYER_TWO
		if info_screen_manager:
			info_screen_manager.display_round_winner(Player.PLAYER_TWO, p2_score)
	else:
		# Tie: no points awarded
		winner = -1
		if info_screen_manager:
			info_screen_manager.display_round_tie(0)

	return {"winner": winner, "awarded_p1": awarded_p1, "awarded_p2": awarded_p2}

func _get_overall_winner() -> int:
	# Highest total score at game end WINS the game.
	var p1_total: int = total_scores[Player.PLAYER_ONE]
	var p2_total: int = total_scores[Player.PLAYER_TWO]
	
	if p1_total > p2_total:
		return Player.PLAYER_ONE
	elif p2_total > p1_total:
		return Player.PLAYER_TWO
	else:
		# Tie-break logic can go here; default to Player One on a tie.
		return Player.PLAYER_ONE


func _clear_showcase_options() -> void:
	var options_container = get_node_or_null("/root/main/FrontLayerUI/InputCatcher/ShowcaseOptions")
	if options_container:
		for child in options_container.get_children():
			child.queue_free()


func close_showcase() -> void:
	if not is_instance_valid(showcased_card):
		return

	# Hide the input catcher layer immediately
	if input_catcher_layer:
		input_catcher_layer.hide()

	# Clear any existing option buttons
	_clear_showcase_options()

	# Disintegrate the showcased card and delete it completely
	if showcased_card.has_method("disintegrate"):
		showcased_card.disintegrate()
	showcased_card.queue_free()

	showcased_card = null  # Clear the reference

	emit_signal("showcase_closed")



func showcase_card(card_node: Node, flip_to_face: bool, options: Array = []):
	"""Animates a card to the center and activates the UI."""
	if not is_instance_valid(card_node):
		return

	print("GM received options: ", options)
	showcased_card = card_node

	# Store the card's original state
	return_info = {
		"pos": card_node.global_position,
		"rot": card_node.rotation,
		"scale": card_node.scale,
		"parent": card_node.get_parent(),
		"z_index": card_node.z_index,
	}

	# --- FIX STARTS HERE ---
	# Reparent the card to the main scene to free it from its container
	var main_scene = get_tree().get_current_scene()
	if is_instance_valid(return_info.parent):
		return_info.parent.remove_child(card_node)
	main_scene.add_child(card_node)
	
	# After reparenting, it keeps its global position. Now, we force its
	# rotation and scale to a neutral state BEFORE animating.
	if card_node.has_method("set_rotation_and_scale_to_neutral"):
		card_node.set_rotation_and_scale_to_neutral()
	# --- FIX ENDS HERE ---

	if card_node.has_meta("is_temp_peek"):
		card_node.z_index = 3000
	else:
		card_node.z_index = 100

	# Animate to the Showcase Marker
	var target_pos
	if not is_instance_valid(showcase_marker):
		showcase_marker = get_node_or_null("/root/main/FrontLayerUI/InputCatcher/Catcher/ShowcaseMarker")
	
	if is_instance_valid(showcase_marker):
		target_pos = showcase_marker.global_position
	else:
		push_error("GameManager: 'ShowcaseMarker' not found. Aborting showcase.")
		return
		
	var tween = create_tween().set_parallel()
	tween.tween_property(card_node, "global_position", target_pos, 0.4).set_trans(Tween.TRANS_CUBIC)
	
	# --- The rest of the function remains the same ---
	await tween.finished

	# Only flip if not a temp peek card (which should always be face up)
	if card_node.has_meta("is_temp_peek"):
		# Force face up after animation
		if card_node.has_node("Visuals/CardViewport/SubViewport/Card/CardFace") and card_node.has_node("Visuals/CardViewport/SubViewport/Card/CardBack"):
			card_node.get_node("Visuals/CardViewport/SubViewport/Card/CardFace").show()
			card_node.get_node("Visuals/CardViewport/SubViewport/Card/CardBack").hide()
		card_node.start_face_up = true
		if card_node.has_method("apply_start_face_up"):
			card_node.apply_start_face_up()
	else:
		if flip_to_face and card_node.has_method("flip_card"):
			var flip_tween = card_node.flip_card()
			if flip_tween:
				await flip_tween.finished

	if ui_manager and ui_manager.has_method("show_showcase_options"):
		ui_manager.show_showcase_options(options)
	
	if input_catcher_layer:
		input_catcher_layer.show()

	# REMOVE THE DEADLOCK: The 'await showcase_closed' line is removed from this function.
	# The function's job is now done. It waits for the user's click.


func enter_selection_mode(cards_to_select_from: Array, on_selection_callback: Callable):
	"""Enters selection mode and DIRECTLY connects to the selectable cards."""
	is_in_selection_mode = true
	selection_callback = on_selection_callback
	selectable_cards = cards_to_select_from

	# --- NEW CONNECTION LOGIC ---
	for card in selectable_cards:
		if card.has_method("set_peek_hover_enabled"):
			card.set_peek_hover_enabled(true)
		# Connect this card's signal to our resolver function.
		# We use CONNECT_ONE_SHOT so the signal disconnects automatically after firing once.
		card.card_was_clicked.connect(resolve_selection, CONNECT_ONE_SHOT)
		print("[GameManager] Connected card_was_clicked for card:", card, "name=", card.card_name if "card_name" in card else "?", "path=", card.get_path())

	if ui_manager and ui_manager.has_method("enable_selection_mode_ui"):
		ui_manager.enable_selection_mode_ui()

	print("GAME MANAGER: Entered selection mode.")


# --- RENAME resolve_peek() to resolve_selection() and update it ---
func resolve_selection(selected_card: Node):
	# --- ADD THIS DEBUG BLOCK ---
	print("--- DEBUG: Checking Selection ---")
	print("Card clicked: ", selected_card.get_path())
	print("Is in selection mode? ", is_in_selection_mode)
	print("Selectable cards list contains:")
	for card_in_list in selectable_cards:
		print("  - ", card_in_list.get_path())
	print("Does the list contain the clicked card? ", selected_card in selectable_cards)
	print("--- END DEBUG ---")
	# --- END DEBUG BLOCK ---
	"""Called by a card when it's clicked. Resolves the selection if valid."""

	# Debug: print all selectable cards and the selected card
	print("[resolve_selection] selectable_cards:")
	for c in selectable_cards:
		print("  ", c, " path=", c.get_path())
	print("[resolve_selection] selected_card:", selected_card, " path=", selected_card.get_path())

	# Ignore clicks if not in selection mode or if the card isn't a valid choice
	if not is_in_selection_mode or not selected_card in selectable_cards:
		print("[resolve_selection] Card not in selectable_cards or not in selection mode!")
		return

	print("GAME MANAGER: Player selected card: ", selected_card.card_data.get("name", "Unknown"))

	# Do NOT show the real selected card in the showcase; EffectsManager will handle temp card showcase for peek_hand

	# Execute the stored callback function, passing the selected card to it
	if selection_callback and selection_callback.is_valid():
		selection_callback.call(selected_card)

	# The selection is done, so exit the mode
	exit_selection_mode()


# --- CREATE a new function to clean up ---
func exit_selection_mode():
	"""Cleans up selection mode and disconnects any lingering signals."""
	# This function now also serves as a cleanup in case selection is cancelled.
	for card in selectable_cards:
		if is_instance_valid(card):
			if card.has_method("set_peek_hover_enabled"):
				card.set_peek_hover_enabled(false)
			# Disconnect the signal to ensure we're no longer listening.
			if card.is_connected("card_was_clicked", resolve_selection):
				card.card_was_clicked.disconnect(resolve_selection)

	is_in_selection_mode = false
	selection_callback = Callable()
	selectable_cards.clear()
	
	if ui_manager and ui_manager.has_method("disable_selection_mode_ui"):
		ui_manager.disable_selection_mode_ui()
	
	print("GAME MANAGER: Exited selection mode.")


func _perform_card_swap_animation(played_card: Node, opponent_card: Node) -> void:
	"""Handles the visual swapping of two cards, avoiding rotation issues.

	This function reparents the cards to the current scene for clean global
	animations, tweens their positions/rotations, then reparents them back to
	the CardManager and updates ownership/lock state.
	"""
	if not is_instance_valid(played_card) or not is_instance_valid(opponent_card):
		push_error("GameManager: Invalid cards passed to _perform_card_swap_animation")
		return

	# 1. Store the target destinations (use opponent card's current transform)
	var p_target_pos = opponent_card.global_position
	var p_target_rot = opponent_card.rotation

	# For the opponent card's destination, require a HandSlots node to exist.
	var hand_slots_node = get_node_or_null("/root/main/HandSlots")
	if not hand_slots_node or not hand_slots_node is Node2D:
		push_error("GameManager: HandSlots node not found at /root/main/HandSlots - required for swap animation")
		return
	var o_target_pos = hand_slots_node.global_position

	# 2. Reparent both cards to the main scene for the animation
	var main_scene = get_tree().get_current_scene()
	if not main_scene:
		push_error("GameManager: Current scene not found for swap animation")
		return

	# Helper: safe reparent inline
	if is_instance_valid(played_card) and is_instance_valid(main_scene):
		var old_p = played_card.get_parent()
		if old_p and old_p.has_method("remove_child"):
			old_p.remove_child(played_card)
		main_scene.add_child(played_card)
	if is_instance_valid(opponent_card) and is_instance_valid(main_scene):
		var old_o = opponent_card.get_parent()
		if old_o and old_o.has_method("remove_child"):
			old_o.remove_child(opponent_card)
		main_scene.add_child(opponent_card)
	played_card.z_index = 100
	opponent_card.z_index = 100

	# 3. Animate the swap
	var tween = create_tween().set_parallel()
	var duration = 0.5
	tween.tween_property(played_card, "global_position", p_target_pos, duration).set_trans(Tween.TRANS_SINE)
	tween.tween_property(played_card, "rotation", p_target_rot, duration)
	tween.tween_property(opponent_card, "global_position", o_target_pos, duration).set_trans(Tween.TRANS_SINE)
	tween.tween_property(opponent_card, "rotation", 0, duration)

	await tween.finished

	# 4. Reparent cards back under CardManager. Require CardManager to be registered.
	if not card_manager or not is_instance_valid(card_manager):
		push_error("GameManager: CardManager not available/registered - required to reparent cards after swap")
		return

	if is_instance_valid(played_card):
		var old_p2 = played_card.get_parent()
		if old_p2 and old_p2.has_method("remove_child"):
			old_p2.remove_child(played_card)
		card_manager.add_child(played_card)
	if is_instance_valid(opponent_card):
		var old_o2 = opponent_card.get_parent()
		if old_o2 and old_o2.has_method("remove_child"):
			old_o2.remove_child(opponent_card)
		card_manager.add_child(opponent_card)

	# 5. Update ownership and lock status
	if played_card.has_method("update_ownership"):
		played_card.update_ownership(false) # now opponent's card
	elif "is_player_card" in played_card:
		played_card.is_player_card = false

	if opponent_card.has_method("update_ownership"):
		opponent_card.update_ownership(true) # now player's card
	elif "is_player_card" in opponent_card:
		opponent_card.is_player_card = true

	if opponent_card.has_method("set_locked"):
		opponent_card.set_locked(true)

# --- Handle Showcase Option Pressed ---
func _on_showcase_option_pressed(callback: Callable):
	# This function runs when the UIManager tells us a button was clicked.
	if not is_instance_valid(showcased_card): return
	# 1. Execute the game logic (e.g., run the _on_peek_deck_keep function)
	if callback.is_valid():
		callback.call()
	# 2. Now, run the full cleanup process.
	_on_showcase_closed()

# --- Showcase Cleanup ---
func _on_showcase_closed():
	"""Called to clean up the entire showcase UI and card."""
	if not is_instance_valid(showcased_card):
		return
	# Hide the UI immediately.
	if input_catcher_layer:
		input_catcher_layer.hide()
	if ui_manager and ui_manager.has_method("hide_showcase_options"):
		ui_manager.hide_showcase_options()
	# If the card was a temporary peek, it should be deleted.
	if showcased_card.has_meta("is_temp_peek"):
		# Do not queue_free here; EffectsManager will handle disintegration and cleanup.
		pass
	else:
		# (This is where the logic to animate a card back to the hand would go)
		pass
	# Clean up state.
	showcased_card = null
