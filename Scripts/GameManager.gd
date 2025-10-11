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

# --- Public References to Other Managers ---

var card_manager: Node
var round_manager: Node
var turn_manager: Node
var ui_manager: Node
var managers: Dictionary = {}

# --- Persistent Game Data ---
var current_game_state: int = -1  # Start uninitialized so first set_game_state(SETUP) actually runs
# Dictionary to hold the scores: {Player.PLAYER_ONE: score, Player.PLAYER_TWO: score}
var total_scores: Dictionary = {}


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
		
	# Also try to get CardManager from Parallax if not found in Managers
	if not card_manager:
		card_manager = get_node_or_null("/root/main/Parallax/CardManager")

	# If this script is used as an autoload (singleton) then other managers
	# should register themselves using register_manager(). We avoid hard
	# failing here because order of _ready() calls is not guaranteed.
	
	# 3. Start the game setup (deferred so scene nodes can finish _ready and register)
	# print("GameManager: deferring set_game_state(SETUP)")
	call_deferred("set_game_state", GameState.SETUP)


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
		var p_cards = card_manager.get_hand_cards(true)
		for c in p_cards:
			if is_instance_valid(c) and "card_name" in c and c.card_name and card_data_loader:
				var data = card_data_loader.get_card_data(c.card_name)
				var val = 0
				if data and data.has("value"):
					val = int(data["value"])
				player_cards_info.append({"name": c.card_name, "value": val})
		var o_cards = card_manager.get_hand_cards(false)
		for c in o_cards:
			if is_instance_valid(c) and "card_name" in c and c.card_name and card_data_loader:
				var data2 = card_data_loader.get_card_data(c.card_name)
				var val2 = 0
				if data2 and data2.has("value"):
					val2 = int(data2["value"])
				opponent_cards_info.append({"name": c.card_name, "value": val2})

	# 2. Declaration & Compensation: Player with the lowest total wins.
	_process_round_result(p1_score, p2_score)

	# 3. End Round: All cards are discarded.
	if round_manager and round_manager.has_method("discard_hands"):
		await round_manager.discard_hands()

	# 4. Show end-round UI, then check for Game End or start the next round
	if ui_manager and ui_manager.has_method("show_end_round_screen"):
		# Determine winner string for the UI call (0=player)
		var winner = Player.PLAYER_ONE if p1_score < p2_score else Player.PLAYER_TWO if p2_score < p1_score else -1
		ui_manager.show_end_round_screen(winner, p1_score, p2_score, player_cards_info, opponent_cards_info)
		if ui_manager.has_method("await_end_round_close"):
			await ui_manager.await_end_round_close()

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
	total_scores[player] += points
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

func _process_round_result(p1_score: int, p2_score: int) -> void:
	# Objective: Lowest Total WINS the round. Winner adds their total to their Score.
	var info_screen_manager = get_node_or_null("/root/InfoScreenManager")

	if p1_score < p2_score:
		add_score(Player.PLAYER_ONE, p1_score)
		info_screen_manager.display_round_winner(Player.PLAYER_ONE, p1_score)
	elif p2_score < p1_score:
		add_score(Player.PLAYER_TWO, p2_score)
		info_screen_manager.display_round_winner(Player.PLAYER_TWO, p2_score)
	else: # Tie: both players receive their points
		add_score(Player.PLAYER_ONE, p1_score)
		add_score(Player.PLAYER_TWO, p2_score)
		info_screen_manager.display_round_tie(p1_score)

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
