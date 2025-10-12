# RoundManager.gd
extends Node

# --- References (Set by GameManager on _ready) ---
var game_manager: Node
var card_manager: Node
var ui_manager: Node
var turn_manager: Node

# --- Round Data ---
var current_round_number: int = 0
var current_starter: int = 0 # Tracks who starts the current round
var last_starter: int = 1   # Tracks who started the previous round

# --- Player Hand ---
@export_group("Player Hand")
@export var player_card_count: int = 4
@export var player_start_pos: Vector2 = Vector2(705, 860)
@export var player_hand_spacing: float = 120.0
@export var player_fan_angle_degrees: float = 10.0
@export var player_card_size: Vector2 = Vector2(500, 700)

# --- Opponent Hand ---
@export_group("Opponent Hand")
@export var opponent_card_count: int = 4
@export var opponent_start_pos: Vector2 = Vector2(1215, 860)
@export var opponent_hand_spacing: float = 120.0
@export var opponent_fan_angle_degrees: float = -10.0
@export var opponent_card_size: Vector2 = Vector2(500, 700)

# --- Calculated hand centers (set dynamically) ---
var player_hand_center: Vector2
var opponent_hand_center: Vector2

# --- Animation speed overrides (optional; if zero, CardManager defaults are used)
@export_group("Draw Timing Overrides")
@export var override_draw_base_duration: float = 0.0
@export var override_draw_stagger: float = 0.0

# --- Hand Offsets ---
@export_group("Hand Offsets")
@export var player_hand_offset_x: float = -75.0 # Nudge player hand left
@export var opponent_hand_offset_x: float = 75.0 # Nudge opponent hand right


func _ready() -> void:
	pass
	# ready
	
	# NEW: Calculate the hand positions based on screen size first.
	_calculate_hand_positions()
	
	# Try to get GameManager via autoload (singleton) first
	# Robust lookup for GameManager: try common locations and fall back to a deferred retry
	var gm: Node = null

	# 1) Autoload singleton path
	gm = get_node_or_null("/root/GameManager")
	# 2) Main scene Managers container (legacy path)
	if not gm:
		gm = get_node_or_null("/root/main/Managers/GameManager")
	# 3) Parent container lookup
	if not gm:
		var manager_container = get_parent()
		if manager_container:
			gm = manager_container.get_node_or_null("GameManager")
	# 4) Scene-wide search
	if not gm:
		var current_scene = get_tree().get_current_scene()
		if current_scene:
			gm = current_scene.find_node("GameManager", true, false)

	if not gm:
		push_warning("RoundManager: GameManager not found during _ready; deferring lookup and retrying shortly.")
		call_deferred("_deferred_gm_lookup")
		return

	game_manager = gm

	# Try to obtain CardManager, UIManager, and TurnManager from GameManager
	if game_manager and game_manager.has_method("get_manager"):
		card_manager = game_manager.get_manager("CardManager")
		ui_manager = game_manager.get_manager("UIManager")
		turn_manager = game_manager.get_manager("TurnManager")
		# managers retrieved from GameManager (suppressed logs)

	# Fallback to scene lookups if still null
	if not card_manager:
		card_manager = get_node_or_null("/root/main/Parallax/CardManager")
	if not ui_manager:
		# UI may be registered later; keep trying later
		pass

	# If we have a GameManager autoload, register ourselves so GameManager can reference us
	if game_manager and game_manager.has_method("register_manager"):
		pass
		# registering with GameManager (suppressed log)
		game_manager.register_manager("RoundManager", self)
	else:
		pass
		# GameManager register step unavailable (suppressed log)

	# Ensure we have at least the critical references
	if not game_manager:
		push_error("RoundManager: GameManager not found (autoload or parent).")
	if not card_manager:
		push_error("RoundManager: CardManager not found.")
	if not ui_manager:
		pass
		# print("RoundManager: UIManager not found (will try to fetch later).")
	if not turn_manager:
		pass
		# print("RoundManager: TurnManager not found (will try to fetch later).")


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
		if current_scene:
			gm = current_scene.find_node("GameManager", true, false)

	if not gm:
		push_error("RoundManager: GameManager not found after deferred lookup. Cannot start rounds.")
		return

	game_manager = gm

	# Try re-fetching managers now that GameManager is available
	if game_manager and game_manager.has_method("get_manager"):
		card_manager = game_manager.get_manager("CardManager")
		ui_manager = game_manager.get_manager("UIManager")
		turn_manager = game_manager.get_manager("TurnManager")

	# If autoload supports register_manager, register ourselves
	if game_manager and game_manager.has_method("register_manager"):
		game_manager.register_manager("RoundManager", self)


# NEW: This function calculates hand positions dynamically.
func _calculate_hand_positions() -> void:
	"""
	Calculates the center positions for player and opponent hands based on the
	camera's visible area, making it robust against camera offsets or zoom.
	"""
	# Get the rectangle of the world that the camera can currently see.
	var visible_rect = get_viewport().get_visible_rect()
	
	# Calculate the horizontal center based on the camera's view.
	var center_x = visible_rect.position.x + visible_rect.size.x / 2.0
	
	# --- Player Hand (Bottom) ---
	var bottom_edge_y = visible_rect.position.y + visible_rect.size.y
	# Includes the vertical fix AND the new horizontal offset, plus 5px down to keep cards off-screen
	var player_y = bottom_edge_y - (player_card_size.y / 6.0) + (player_card_size.y / 2.0) + 5.0
	player_hand_center = Vector2(center_x + player_hand_offset_x, player_y)
	
	# --- Opponent Hand (Top) ---
	var top_edge_y = visible_rect.position.y
	# Includes the new horizontal offset
	var opponent_y = top_edge_y + (opponent_card_size.y / 6.0)
	opponent_hand_center = Vector2(center_x + opponent_hand_offset_x, opponent_y)

	# camera and hand centers calculated




# Called by the GameManager to begin a new round.
func start_new_round(starter: int) -> void:
	# Add a safeguard to prevent multiple calls during the same round
	if current_round_number > 0:
		push_warning("RoundManager: start_new_round called multiple times for the same round.")
		return
	
	# Re-fetch managers from GameManager in case they weren't ready during _ready()
	if game_manager and game_manager.has_method("get_manager"):
		if not ui_manager:
			ui_manager = game_manager.get_manager("UIManager")
			# re-fetched ui_manager (suppressed log)
		if not card_manager:
			card_manager = game_manager.get_manager("CardManager")
	
	if not card_manager or not ui_manager:
		push_error("RoundManager cannot start round: Manager references are null.")
		# manager state (suppressed logs)
		# We can transition to GAME_OVER or stop if we can't run.
		return

	current_round_number += 1
	
	# 1. Determine and store the starting player for this round
	_set_starter_for_next_round(starter)
	
	# =========================================================================
	# 2. UI Updates
	# =========================================================================
	
	# Update the permanent UI display (e.g., the "Round #" text in the corner)
	ui_manager.update_round_display(current_round_number)

	# Show loading overlay while we prepare to draw cards
	if ui_manager and ui_manager.has_method("show_loading"):
		ui_manager.show_loading()
	
	# Ensure action panels start in the 'off' state if UIManager supports it
	if ui_manager and ui_manager.has_method("set_active_player"):
		# Pass false to indicate panels should be in the 'off' visual
		ui_manager.set_active_player(false)
	
	# TODO: Display the round start overlay/dialogue when InfoScreenManager is ready
	# var starter_name = "YOU" if current_starter == game_manager.Player.PLAYER_ONE else "OPPONENT"
	# var message = "Round #%d\n%s goes first!" % [current_round_number, starter_name]
	
	# =========================================================================
	
	# 3. Draw initial hands using CardManager.draw_cards
	if card_manager and card_manager.has_method("draw_cards"):
		# Optionally override CardManager animation speeds
		var prev_base = card_manager.draw_base_duration
		var prev_stagger = card_manager.draw_stagger
		if override_draw_base_duration > 0.0:
			card_manager.draw_base_duration = override_draw_base_duration
		if override_draw_stagger > 0.0:
			card_manager.draw_stagger = override_draw_stagger

		# Try to use the Deck node as the visual origin for draws so cards look like
		# they're coming from the deck. Fall back to the exported start positions.
		var deck_node = get_node_or_null("/root/main/Parallax/Deck")
		var actual_player_start: Vector2 = player_start_pos
		var actual_opponent_start: Vector2 = opponent_start_pos
		if deck_node:
			actual_player_start = deck_node.global_position
			actual_opponent_start = deck_node.global_position

		# drawing player cards
		card_manager.card_spacing = player_hand_spacing
		card_manager.fan_angle_degrees = player_fan_angle_degrees
		card_manager.card_size = player_card_size
		# card_manager values set
		card_manager.draw_cards(player_card_count, actual_player_start, player_hand_center, true, true)  # face_up=true, is_player=true

		# Small buffer before dealing opponent (so animations don't overlap awkwardly)
		var buffer_time = 0.15
		# Draw opponent hand face-down after a short delay
		# scheduling opponent draw
		var tween = create_tween()
		tween.tween_interval(buffer_time)
		tween.tween_callback(func(): _draw_opponent_delayed(opponent_card_count, actual_opponent_start, opponent_hand_center))
		# The UI loading overlay is hidden by GameManager when CardManager emits draw_started.
		# RoundManager no longer schedules a separate hide to avoid overlapping animations.

		# Restore previous animation settings
		card_manager.draw_base_duration = prev_base
		card_manager.draw_stagger = prev_stagger
	else:
		pass
		# card_manager.draw_cards not available - skipping

func _draw_opponent_delayed(count: int, start_pos: Vector2, hand_center: Vector2) -> void:
	if not card_manager:
		return
	# drawing opponent cards
	card_manager.card_spacing = opponent_hand_spacing
	card_manager.fan_angle_degrees = opponent_fan_angle_degrees
	card_manager.card_size = opponent_card_size
	card_manager.draw_cards(count, start_pos, hand_center, false, false)  # face_up=false, is_player=false

	# 4. Activate TurnManager and hand off control
	# Try a fresh lookup in case TurnManager registered after _ready()
	if not turn_manager and game_manager and game_manager.has_method("get_manager"):
		turn_manager = game_manager.get_manager("TurnManager")

	# Scene fallback (common layout)
	if not turn_manager:
		turn_manager = get_node_or_null("/root/main/Managers/TurnManager")

	if turn_manager and turn_manager.has_method("start_turn_management"):
		pass
		# activating TurnManager
		turn_manager.start_turn_management(current_starter)
	else:
		pass
		# TurnManager not available, scheduling retry
		# Give other nodes a short moment to finish _ready() and register
		var retry_tween = create_tween()
		retry_tween.tween_interval(0.1)
		retry_tween.tween_callback(func():
			if game_manager and game_manager.has_method("get_manager"):
				turn_manager = game_manager.get_manager("TurnManager")
				
			if not turn_manager:
				turn_manager = get_node_or_null("/root/main/Managers/TurnManager")
			
			if turn_manager and turn_manager.has_method("start_turn_management"):
				pass
				# Deferred activation found TurnManager
				turn_manager.start_turn_management(current_starter)
			else:
				pass
				# print("RoundManager: ERROR - TurnManager still not available after deferred attempt")
		)

	# print("RoundManager: Round", current_round_number, "setup complete, transitioning to IN_ROUND")
	game_manager.set_game_state(game_manager.GameState.IN_ROUND)


# Calculates the total value of all cards in a player's hand.
func calculate_player_score(player_id: int) -> int:
	# Include both the cards currently in the player's hand AND any of their cards
	# that have already been moved to the discard pile. This ensures score
	# calculation matches what the end-round UI displays (which combines
	# hand + discard entries).
	if not card_manager:
		return 9999

	var is_player = (player_id == 0) # Corresponds to GameManager.Player.PLAYER_ONE
	var combined_nodes: Array = []

	# 1) Add all current hand cards
	var hand_nodes: Array = card_manager.get_hand_cards(is_player)
	for hn in hand_nodes:
		combined_nodes.append(hn)

	# 2) Try to find the discard pile and include any of the player's cards there
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
			# only include cards that belong to the player we're calculating for
			if child and "is_player_card" in child and child.is_player_card == is_player:
				combined_nodes.append(child)

	# 3) Sum values using the CardDataLoader
	var card_data_loader = get_node_or_null("/root/CardDataLoader")
	if not card_data_loader:
		push_error("CardDataLoader not found!")
		return 9999

	var total_value: int = 0
	for card_node in combined_nodes:
		if not is_instance_valid(card_node):
			continue
		if "card_name" in card_node:
			var card_name = card_node.card_name
			if card_name:
				var card_data = card_data_loader.get_card_data(card_name)
				if card_data and card_data.has("value"):
					total_value += int(card_data["value"])

	return total_value


# Called by GameManager at the end of the round to clear the table.
func discard_hands() -> void:
	if card_manager and card_manager.has_method("discard_all_hands"):
		# Await the card manager's discard animation sequence so callers can wait
		# for the visual hand clearing to finish before proceeding.
		await card_manager.discard_all_hands()


# --- Private Logic Helpers ---

# Implements the rule: "Alternate who goes first each round."
func _set_starter_for_next_round(previous_starter: int) -> void:
	# Respect the starter value passed in by the caller.
	# The caller (GameManager / start_new_round) passes the intended starter for this round.
	# Previously this function inverted the value, causing the wrong player to start.
	current_starter = previous_starter
	# Record who started this round for bookkeeping
	last_starter = previous_starter
