extends Node

signal start_sequence_finished
signal turn_message_finished

@export_group("Loading")
@export var loading_opacity: float = 0.9

@export_group("Action Panels")
# Alpha used for the "off" state (panels look dim/transparent at game start)
@export var panels_off_alpha: float = 0.03
# Alpha used for the "on" state (panels become fully visible when cards draw)
@export var panels_on_alpha: float = 1.0

# References to UI elements (set in _ready from the scene tree)
var game_state_overlay: Node  # GameStateOverlay node
var end_round_tray: Node       # EndRoundTray node
var end_game_tray: Node        # EndGameTray node
var ui_panel: Node             # UIPanel node (if UIManager is NOT attached to it)

# UI Panel child nodes (for scores, round display, etc.)
var round_label: Node
var player_score_label: Node
var opponent_score_label: Node
var player_actions_panel: Node
var opponent_actions_panel: Node
var player_score_box: Node
var opponent_score_box: Node
var player_actions_left_label: Node
var opponent_actions_left_label: Node
var loading_rect: Node

func _ready() -> void:
	pass
	# print("UIManager: _ready called.")
	# Resolve references whether this script is attached to UIPanel or lives under Managers
	# If UIManager is attached to UIPanel, prefer local lookups via the node itself
	if name == "UIPanel":
		pass
		# print("UIManager: I AM the UIPanel node, using self")
		ui_panel = self
		var front_layer = ui_panel.get_parent()
		if front_layer:
			game_state_overlay = front_layer.get_node_or_null("GameStateOverlay")
			end_round_tray = front_layer.get_node_or_null("EndRoundTray")
			end_game_tray = front_layer.get_node_or_null("EndGameTray")
	else:
		pass
		# print("UIManager: I am NOT UIPanel (name=", name, "), looking up UI elements")
		# Try to get main node first
		var main_node = get_node_or_null("/root/main")
		# print("UIManager: main_node =", main_node)
		
		if main_node:
			var front_layer = main_node.get_node_or_null("FrontLayerUI")
			# print("UIManager: front_layer =", front_layer)
			
			if front_layer:
				game_state_overlay = front_layer.get_node_or_null("GameStateOverlay")
				end_round_tray = front_layer.get_node_or_null("EndRoundTray")
				end_game_tray = front_layer.get_node_or_null("EndGameTray")
				ui_panel = front_layer.get_node_or_null("UIPanel")
				
				# print("UIManager: game_state_overlay =", game_state_overlay)
				# print("UIManager: end_round_tray =", end_round_tray)
				# print("UIManager: end_game_tray =", end_game_tray)
				# print("UIManager: ui_panel =", ui_panel)

	if not game_state_overlay or not end_round_tray or not end_game_tray or not ui_panel:
		push_error("UIManager: Could not find one or more UI elements!")
		if not game_state_overlay:
			pass
			# print("UIManager: Missing game_state_overlay")
		if not end_round_tray:
			pass
			# print("UIManager: Missing end_round_tray")
		if not end_game_tray:
			pass
			# print("UIManager: Missing end_game_tray")
		if not ui_panel:
			pass
			# print("UIManager: Missing ui_panel")
	else:
		pass
		# print("UIManager: All UI elements found.")
		# Extra diagnostics: print node paths and initial label states
		# print("UIManager: ui_panel path:", ui_panel.get_path())
		var fl = ui_panel.get_parent()
		if fl:
			pass
			# print("UIManager: front_layer path:", str(fl.get_path()))
		else:
			pass
			# print("UIManager: front_layer path: null")
		# print("UIManager: game_state_overlay:", game_state_overlay.get_path())
		# print("UIManager: end_round_tray:", end_round_tray.get_path())
		# print("UIManager: end_game_tray:", end_game_tray.get_path())
		# Check overlay label presence
		var overlay_label = game_state_overlay.get_node_or_null("CenterContainer/GameState") if game_state_overlay else null
		if overlay_label:
			pass
			# print("UIManager: overlay label found, text=", overlay_label.text, "modulate.a=", overlay_label.modulate.a)
		else:
			pass
			# print("UIManager: overlay label NOT found at CenterContainer/GameState")


	# If GameManager is autoloaded or present in the scene, register this UIManager so GameManager can find it
	var gm_paths = ["/root/GameManager", "/root/main/Managers/GameManager", "/root/main/GameManager"]
	var gm: Node = null
	for p in gm_paths:
		gm = get_node_or_null(p)
		if gm:
			pass
			# print("UIManager: found GameManager at", p)
			break
	if gm and gm.has_method("register_manager"):
		pass
		# print("UIManager: registering with GameManager")
		gm.register_manager("UIManager", self)
	else:
		pass
		# print("UIManager: GameManager not found or has no register_manager")
	
	# Get child nodes from UIPanel for scores, round display, etc.
	if ui_panel:
		var base = ui_panel.get_node_or_null("PanelBG/VBoxContainer")
		if base:
			round_label = base.get_node_or_null("RoundTitle/Round#")
			if round_label:
				pass
				# print("UIManager: round_label found at", round_label.get_path(), "initial text=", round_label.text)
			else:
				pass
				# print("UIManager: round_label not found under PanelBG/VBoxContainer/RoundTitle/Round#")
			# Scoreboxes (each contains three digit labels)
			player_score_box = base.get_node_or_null("TurnEconomy/PlayerUI/Scorebox")
			opponent_score_box = base.get_node_or_null("TurnEconomy/OpponentUI/Scorebox")
			# Actions left labels
			player_actions_left_label = base.get_node_or_null("TurnEconomy/PlayerUI/ActionDisplay/ActionsLeftLabel")
			opponent_actions_left_label = base.get_node_or_null("TurnEconomy/OpponentUI/ActionDisplay/ActionsLeftLabel")
			# Panels for modulate when active/inactive
			player_actions_panel = base.get_node_or_null("TurnEconomy/PlayerUI")
			opponent_actions_panel = base.get_node_or_null("TurnEconomy/OpponentUI")

			# Ensure panels start in the 'off' visual state unless something else sets them
			if player_actions_panel:
				player_actions_panel.modulate.a = panels_off_alpha
			if opponent_actions_panel:
				opponent_actions_panel.modulate.a = panels_off_alpha
			# Pass button wiring
			var pass_button = base.get_node_or_null("TurnEconomy/PlayerUI/PassButton")
			if pass_button:
				# Ensure we don't double-connect
				var already_connected = false
				for conn in pass_button.get_signal_connection_list("pressed"):
					if conn.target == self:
						already_connected = true
						break
				if not already_connected:
					pass_button.connect("pressed", Callable(self, "_on_player_pass_pressed"))
					# print("UIManager: Connected PassButton to _on_player_pass_pressed")
			# store for external control
			self.set("_player_pass_button", pass_button)
			if pass_button:
				pass
				# print("UIManager: stored _player_pass_button ->", pass_button.get_path())
			else:
				pass
				# print("UIManager: _player_pass_button is null (PassButton not found)")

				# Loading overlay (full panel child)
				loading_rect = ui_panel.get_node_or_null("Loading")
				if loading_rect:
					pass
					# print("UIManager: found Loading rect at", loading_rect.get_path())
					# ensure it's initially hidden and use configured opacity
					loading_rect.visible = false
					loading_rect.modulate.a = loading_opacity
				else:
					pass
					# print("UIManager: Loading rect not found under UIPanel")

		# Keep backwards-compatible names used elsewhere
		player_score_label = player_score_box
		opponent_score_label = opponent_score_box

## Called when the player's Pass button is pressed
func _on_player_pass_pressed() -> void:
	pass
	# print("UIManager: Player Pass pressed")
	# Notify TurnManager via GameManager if available
	var gm = get_node_or_null("/root/GameManager")
	var tm: Node = null
	if gm and gm.has_method("get_manager"):
		tm = gm.get_manager("TurnManager")
	if not tm:
		tm = get_node_or_null("/root/main/Managers/TurnManager")
	if tm and tm.has_method("pass_current_player"):
		tm.pass_current_player()
	else:
		pass
		# print("UIManager: TurnManager not found to handle pass")


## Simple static Loading overlay API (show/hide)
func show_loading() -> void:
	if not loading_rect:
		pass
		# print("UIManager: show_loading called but loading_rect is null")
		return
	loading_rect.visible = true
	loading_rect.modulate.a = loading_opacity
	# print("UIManager: show_loading -> visible")

func hide_loading() -> void:
	if not loading_rect:
		pass
		# print("UIManager: hide_loading called but loading_rect is null")
		return
	loading_rect.visible = false
	loading_rect.modulate.a = loading_opacity
	# print("UIManager: hide_loading -> hidden")

## Allow other managers to enable/disable the player's pass button
func set_pass_button_enabled(enabled: bool) -> void:
	var pb = null
	if self.has_method("get"):
		pb = self.get("_player_pass_button")
	if pb:
		pb.disabled = not enabled
		# print("UIManager: set_pass_button_enabled -> (stored) ", enabled)
		return
	# Try fallback lookup
	var base = ui_panel.get_node_or_null("PanelBG/VBoxContainer") if ui_panel else null
	if base:
		var pass_button = base.get_node_or_null("TurnEconomy/PlayerUI/PassButton")
		if pass_button:
			pass_button.disabled = not enabled
			# print("UIManager: set_pass_button_enabled -> (fallback) ", enabled)
			return
	# print("UIManager: set_pass_button_enabled -> no pass button found to set to", enabled)



# === GAME STATE OVERLAY METHODS ===

# Shows sequential messages: "Game Start" -> "Round X" -> "Your Turn"
func show_game_start_sequence(round_number: int, is_player_turn: bool) -> void:
	pass
	# print("UIManager: show_game_start_sequence called.")
	if not game_state_overlay:
		pass
		# print("UIManager: game_state_overlay is null.")
		return
	var label = game_state_overlay.get_node_or_null("CenterContainer/GameState")
	if not label:
		pass
		# print("UIManager: label is null.")
		return

	game_state_overlay.visible = true
	label.modulate.a = 0.0

	var turn_text = "Your Turn" if is_player_turn else "Opponent's Turn"
	_start_sequence_data = {
		"label": label,
		"texts": ["Game Start", "Round %d" % round_number, turn_text]
	}
	# print("UIManager: _start_sequence_data initialized: ", _start_sequence_data)

	_advance_start_sequence()


# Shows "Round X" message with fade animation
func show_round_start_overlay(message: String) -> void:
	if not game_state_overlay:
		return
	
	game_state_overlay.visible = true
	var label = game_state_overlay.get_node_or_null("CenterContainer/GameState")
	if label:
		label.text = message
	
	# TODO: Add fade in/out tween animation


# Shows "Your Turn" or "Opponent's Turn"
func show_turn_message(is_player_turn: bool) -> void:
	if not game_state_overlay:
		return
	
	var label = game_state_overlay.get_node_or_null("CenterContainer/GameState")
	if not label:
		return

	game_state_overlay.visible = true
	label.modulate.a = 0.0
	
	var turn_text = "Your \nTurn" if is_player_turn else "Opponent's \nTurn"
	label.text = turn_text
	
	var tween = create_tween()
	tween.tween_property(label, "modulate:a", 1.0, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_interval(0.9)
	tween.tween_property(label, "modulate:a", 0.0, 0.25)
	tween.tween_callback(func():
		game_state_overlay.visible = false
		emit_signal("turn_message_finished")
	)


func _set_label_text(label: Label, text: String) -> void:
	if label:
		label.text = text

func _on_start_sequence_complete() -> void:
	pass
	# print("UIManager: _on_start_sequence_complete called.")
	if game_state_overlay:
		game_state_overlay.visible = false
	emit_signal("start_sequence_finished")


var _start_sequence_data: Dictionary

func _advance_start_sequence() -> void:
	if not _start_sequence_data:
		pass
		# print("UIManager: _advance_start_sequence called but _start_sequence_data is null.")
		return
		
	var label: Label = _start_sequence_data.get("label")
	var texts: Array = _start_sequence_data.get("texts")

	if texts.is_empty():
		_on_start_sequence_complete()
		return

	var next_text = texts.pop_front()
	_start_sequence_data["texts"] = texts
	if label:
		label.text = next_text
		# print("UIManager: Advancing sequence, showing text: ", next_text)

	var tween = create_tween()
	tween.tween_property(label, "modulate:a", 1.0, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_interval(0.9)
	tween.tween_property(label, "modulate:a", 0.0, 0.25)
	tween.tween_callback(Callable(self, "_advance_start_sequence"))


# === UI PANEL METHODS ===

# Updates the persistent round # display in the UI Panel
func update_round_display(round_number: int) -> void:
	pass
	# print("UIManager: update_round_display called with", round_number)
	if round_label:
		round_label.text = str(round_number)
	else:
		pass
		# print("UI Manager: Round label not found, displaying: Round %d" % round_number)


# Updates the total scores in the UI Panel
func update_scores(scores: Dictionary) -> void:
	var p1_score = scores.get(0, 0)
	var p2_score = scores.get(1, 0)
	# Format scores into 3 digits and update the scoreboxes
	var p1_digits = _format_digits(p1_score, 3)
	var p2_digits = _format_digits(p2_score, 3)

	if player_score_box:
		var d1 = player_score_box.get_node_or_null("#__")
		var d2 = player_score_box.get_node_or_null("_#_")
		var d3 = player_score_box.get_node_or_null("__#")
		if d1: d1.text = str(p1_digits[0])
		if d2: d2.text = str(p1_digits[1])
		if d3: d3.text = str(p1_digits[2])

	if opponent_score_box:
		var od1 = opponent_score_box.get_node_or_null("#__")
		var od2 = opponent_score_box.get_node_or_null("_#_")
		var od3 = opponent_score_box.get_node_or_null("__#")
		if od1: od1.text = str(p2_digits[0])
		if od2: od2.text = str(p2_digits[1])
		if od3: od3.text = str(p2_digits[2])

	# print("UI Manager: Updating scores. Player: %d, Opponent: %d" % [p1_score, p2_score])


func _format_digits(value: int, length: int) -> Array:
	var s = str(value)
	while s.length() < length:
		s = "0" + s
	var out: Array = []
	for i in range(length):
		out.append(s[i])
	return out


# Sets transparency on action panels to show whose turn it is
func set_active_player(_is_player_turn: bool) -> void:
	# When called with 'true' we switch panels to the visible/on alpha.
	# When called with 'false' we set them to the dim/off alpha.
	# This function is used at startup (false) and when cards draw (true).
	var target_alpha: float = panels_on_alpha if _is_player_turn else panels_off_alpha

	if player_actions_panel:
		player_actions_panel.modulate.a = target_alpha

	if opponent_actions_panel:
		opponent_actions_panel.modulate.a = target_alpha


# === END ROUND TRAY METHODS ===

# Shows the end round screen with card reveal animation
func show_end_round_screen(_winner: int, _player_total: int, _opponent_total: int) -> void:
	if not end_round_tray:
		return
	
	end_round_tray.visible = true
	
	# TODO: Implement card-by-card reveal animation
	# TODO: Show "You Win!" / "You've Lost..." / "It's a Tie" message
	# print("End Round: Winner=%d, Player=%d, Opponent=%d" % [winner, player_total, opponent_total])


# === END GAME TRAY METHODS ===

# Shows the game over screen with final winner
func show_game_over_screen(_winner: int, _final_score: int) -> void:
	if not end_game_tray:
		return
	
	end_game_tray.visible = true
	
	# TODO: Update labels in end_game_tray with winner info
	# print("Game Over: Winner=%d, Score=%d" % [winner, final_score])
