extends Node

signal start_sequence_finished
signal end_round_closed
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
	# UIManager ready (debug suppressed)
	# Resolve references whether this script is attached to UIPanel or lives under Managers
	# If UIManager is attached to UIPanel, prefer local lookups via the node itself
	if name == "UIPanel":
		pass
		# Attached to UIPanel (suppressed)
		ui_panel = self
		var front_layer = ui_panel.get_parent()
		if front_layer:
			game_state_overlay = front_layer.get_node_or_null("GameStateOverlay")
			end_round_tray = front_layer.get_node_or_null("EndRoundTray")
			end_game_tray = front_layer.get_node_or_null("EndGameTray")
	else:
		pass
		# Not attached to UIPanel; resolving UI elements (suppressed)
		# Try to get main node first
		var main_node = get_node_or_null("/root/main")
		if main_node:
			var front_layer = main_node.get_node_or_null("FrontLayerUI")
			# front_layer resolved (suppressed)
			if front_layer:
				game_state_overlay = front_layer.get_node_or_null("GameStateOverlay")
				end_round_tray = front_layer.get_node_or_null("EndRoundTray")
				end_game_tray = front_layer.get_node_or_null("EndGameTray")
				ui_panel = front_layer.get_node_or_null("UIPanel")
				# UI elements found (suppressed)

	if not game_state_overlay or not end_round_tray or not end_game_tray or not ui_panel:
		push_error("UIManager: Could not find one or more UI elements!")
		if not game_state_overlay:
			pass
			# missing game_state_overlay (suppressed)
		if not end_round_tray:
			pass
			# missing end_round_tray (suppressed)
		if not end_game_tray:
			pass
			# missing end_game_tray (suppressed)
		if not ui_panel:
			pass
			# missing ui_panel (suppressed)
	else:
		pass
		# UI elements ready (suppressed)
		# Extra diagnostics suppressed
		var fl = ui_panel.get_parent()
		if fl:
			pass
			# front_layer path available (suppressed)
		else:
			pass
			# front_layer path null (suppressed)
		# Check overlay label presence
		var overlay_label = game_state_overlay.get_node_or_null("CenterContainer/GameState") if game_state_overlay else null
		if overlay_label:
			pass
			# overlay label found (suppressed)
		else:
			pass
			# overlay label not found (suppressed)


	# If GameManager is autoloaded or present in the scene, register this UIManager so GameManager can find it
	var gm_paths = ["/root/GameManager", "/root/main/Managers/GameManager", "/root/main/GameManager"]
	var gm: Node = null
	for p in gm_paths:
		gm = get_node_or_null(p)
		if gm:
			pass
			# GameManager located (suppressed)
			break
	if gm and gm.has_method("register_manager"):
		pass
		# registering with GameManager (suppressed)
		gm.register_manager("UIManager", self)
	else:
		pass
		# GameManager registration skipped (suppressed)
	
	# Get child nodes from UIPanel for scores, round display, etc.
	if ui_panel:
		var base = ui_panel.get_node_or_null("PanelBG/VBoxContainer")
		if base:
			round_label = base.get_node_or_null("RoundTitle/Round#")
			if round_label:
				pass
				# round_label found (suppressed)
			else:
				pass
				# round_label not found (suppressed)
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
				# Always connect hover signals (handler will check turn)
				if not pass_button.is_connected("mouse_entered", Callable(self, "_on_pass_button_hover")):
					pass_button.connect("mouse_entered", Callable(self, "_on_pass_button_hover"))
				if not pass_button.is_connected("mouse_exited", Callable(self, "_on_pass_button_exit")):
					pass_button.connect("mouse_exited", Callable(self, "_on_pass_button_exit"))
			# store for external control
			self.set("_player_pass_button", pass_button)
			if pass_button:
				pass
				# stored player pass button (suppressed)
			else:
				pass
				# pass button not found (suppressed)

				# Loading overlay (full panel child)
				loading_rect = ui_panel.get_node_or_null("Loading")
				if loading_rect:
					pass
					# loading rect found (suppressed)
					# ensure it's initially hidden and use configured opacity
					loading_rect.visible = false
					loading_rect.modulate.a = loading_opacity
				else:
					pass
					# loading rect not found (suppressed)

		# Keep backwards-compatible names used elsewhere
		player_score_label = player_score_box
		opponent_score_label = opponent_score_box

	# Disable UI panel inputs initially
	ui_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

## Called when the player's Pass button is pressed
func _on_player_pass_pressed() -> void:
	pass
	# player pass pressed (suppressed)
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
		# TurnManager not found to handle pass (suppressed)

func _on_pass_button_hover() -> void:
	var game_manager = get_node_or_null("/root/GameManager")
	if not game_manager or game_manager.current_game_state != game_manager.GameState.IN_ROUND:
		return
	# Only show hover message during player's turn
	var turn_manager = get_node_or_null("/root/main/Managers/TurnManager")
	if not turn_manager or not turn_manager.has_method("get_is_player_turn") or not turn_manager.get_is_player_turn():
		return
	var info_manager = get_node_or_null("/root/main/Managers/InfoScreenManager")
	if info_manager and info_manager.has_method("show_pass_button_hover"):
		# Get the current actions left value from the label
		var actions_left = 0
		if player_actions_left_label and player_actions_left_label.text != "":
			actions_left = int(player_actions_left_label.text)
		# show hover message for pass button
		# actions_left captured
		info_manager.show_pass_button_hover(actions_left)

func _on_pass_button_exit() -> void:
	var game_manager = get_node_or_null("/root/GameManager")
	if not game_manager or game_manager.current_game_state != game_manager.GameState.IN_ROUND:
		return
	var info_manager = get_node_or_null("/root/main/Managers/InfoScreenManager")
	if info_manager and info_manager.has_method("clear"):
		info_manager.clear()



## Simple static Loading overlay API (show/hide)
func show_loading() -> void:
	if not loading_rect:
		pass
		# show_loading called but loading_rect is null (suppressed)
		return
	loading_rect.visible = true
	loading_rect.modulate.a = loading_opacity
	# loading visible (suppressed)

func hide_loading() -> void:
	if not loading_rect:
		pass
		# hide_loading called but loading_rect is null (suppressed)
		return
	loading_rect.visible = false
	loading_rect.modulate.a = loading_opacity
	# loading hidden (suppressed)

## Allow other managers to enable/disable the player's pass button
func set_pass_button_enabled(enabled: bool) -> void:
	var pb = null
	if self.has_method("get"):
		pb = self.get("_player_pass_button")
	if pb:
		pb.disabled = not enabled
		# pass button enabled/disabled (suppressed)
		return
	# Try fallback lookup
	var base = ui_panel.get_node_or_null("PanelBG/VBoxContainer") if ui_panel else null
	if base:
		var pass_button = base.get_node_or_null("TurnEconomy/PlayerUI/PassButton")
		if pass_button:
			pass_button.disabled = not enabled
			# pass button fallback set (suppressed)
			return
	# no pass button found fallback (suppressed)



# === GAME STATE OVERLAY METHODS ===

# Shows sequential messages: "Game Start" -> "Round X" -> "Your Turn"
func show_game_start_sequence(round_number: int, is_player_turn: bool) -> void:
	pass
	# show_game_start_sequence called (suppressed)
	if not game_state_overlay:
		pass
		# game_state_overlay is null (suppressed)
		return
	var label = game_state_overlay.get_node_or_null("CenterContainer/GameState")
	if not label:
		pass
		# label is null (suppressed)
		return

	game_state_overlay.visible = true
	label.modulate.a = 0.0

	var turn_text = "Your Turn" if is_player_turn else "Opponent's Turn"
	_start_sequence_data = {
		"label": label,
		"texts": ["Game Start", "Round %d" % round_number, turn_text]
	}
	# start sequence data initialized (suppressed)

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
	# on_start_sequence_complete called (suppressed)
	if game_state_overlay:
		game_state_overlay.visible = false
	emit_signal("start_sequence_finished")


var _start_sequence_data: Dictionary

func _advance_start_sequence() -> void:
	if not _start_sequence_data:
		pass
		# start sequence data null (suppressed)
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
		# advancing start sequence (suppressed)

	var tween = create_tween()
	tween.tween_property(label, "modulate:a", 1.0, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_interval(0.9)
	tween.tween_property(label, "modulate:a", 0.0, 0.25)
	tween.tween_callback(Callable(self, "_advance_start_sequence"))


# === UI PANEL METHODS ===

# Updates the persistent round # display in the UI Panel
func update_round_display(round_number: int) -> void:
	pass
	# update round display called (suppressed)
	if round_label:
		round_label.text = str(round_number)
	else:
		pass
		# round label not found fallback (suppressed)


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

	# score update completed (suppressed)


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
	
	# Connect/disconnect pass button hover signals based on whose turn it is
	var pass_button = self.get("_player_pass_button")
	# set_active_player called; updating pass button connections
	if pass_button:
		set_pass_button_enabled(_is_player_turn)
		# Disconnect existing hover connections if any
		if pass_button.is_connected("mouse_entered", Callable(self, "_on_pass_button_hover")):
			pass_button.disconnect("mouse_entered", Callable(self, "_on_pass_button_hover"))
		if pass_button.is_connected("mouse_exited", Callable(self, "_on_pass_button_exit")):
			pass_button.disconnect("mouse_exited", Callable(self, "_on_pass_button_exit"))
		
		# Reconnect hover signals only if it's the player's turn
		if _is_player_turn:
			pass_button.connect("mouse_entered", Callable(self, "_on_pass_button_hover"))
			pass_button.connect("mouse_exited", Callable(self, "_on_pass_button_exit"))


# === END ROUND TRAY METHODS ===

# Shows the end round screen with card reveal animation
func show_end_round_screen(_winner: int, _player_total: int, _opponent_total: int, player_cards_info: Array = [], opponent_cards_info: Array = []) -> void:
	if not end_round_tray:
		return

	# Labels on the tray
	var player_lbl = end_round_tray.get_node_or_null("PlayerHandTotal")
	var opp_lbl = end_round_tray.get_node_or_null("OpponentHandTotal")
	var round_summary = end_round_tray.get_node_or_null("RoundSummary")

	# Initialize displayed totals to 0 for the animated count-up
	if player_lbl and player_lbl is Label:
		player_lbl.text = "0"
	if opp_lbl and opp_lbl is Label:
		opp_lbl.text = "0"

	# Show the tray and overlay
	end_round_tray.visible = true
	if end_round_tray.has_method("grab_focus"):
		end_round_tray.grab_focus()
	if not end_round_tray.is_connected("gui_input", Callable(self, "_on_end_round_tray_input")):
		end_round_tray.connect("gui_input", Callable(self, "_on_end_round_tray_input"))
	if game_state_overlay:
		game_state_overlay.visible = true

	# Helper: find discard pile and its children (cards were moved there already)
	var discard_node = null
	var main_node = get_node_or_null("/root/main")
	if main_node and "discard_pile_node" in main_node:
		discard_node = main_node.discard_pile_node
	if not discard_node:
		discard_node = get_tree().get_root().find_node("DiscardPile", true, false)

	# Animate player cards one-by-one: flash the card in the discard pile and increment the displayed total
	var displayed_player_total = 0
	for card_info in player_cards_info:
		var val = int(card_info.get("value", 0))
		# Find a matching card in discard pile (by name) if possible
		var found_card = null
		if discard_node:
			for child in discard_node.get_children():
				if child and "card_name" in child and child.card_name == card_info.get("name", ""):
					found_card = child
					break

		# Flash the card visually if found
		if is_instance_valid(found_card):
			_flash_card(found_card)

		# Increment displayed total with a small animation delay
		displayed_player_total += val
		if player_lbl and player_lbl is Label:
			player_lbl.text = str(displayed_player_total)
		await get_tree().create_timer(0.28).timeout

	# Animate opponent cards
	var displayed_opponent_total = 0
	for card_info in opponent_cards_info:
		var val2 = int(card_info.get("value", 0))
		var found_card2 = null
		if discard_node:
			for child2 in discard_node.get_children():
				if child2 and "card_name" in child2 and child2.card_name == card_info.get("name", ""):
					found_card2 = child2
					break
		if is_instance_valid(found_card2):
			_flash_card(found_card2)
		displayed_opponent_total += val2
		if opp_lbl and opp_lbl is Label:
			opp_lbl.text = str(displayed_opponent_total)
		await get_tree().create_timer(0.28).timeout

	# After counting finishes, declare a winner message
	if round_summary and round_summary is Label:
		var msg = "It's a Tie..."
		if _winner == -1:
			msg = "It's a Tie..."
		elif _winner == 0:
			msg = "You Win the Round!"
		else:
			msg = "Opponent Wins the Round"
		round_summary.text = msg

	# Done — now UI awaits dismissal by the player (click/key) via existing handler


# === END GAME TRAY METHODS ===

# Shows the game over screen with final winner
func show_game_over_screen(_winner: int, _final_score: int) -> void:
	if not end_game_tray:
		return
	
	end_game_tray.visible = true
	
	# TODO: Update labels in end_game_tray with winner info
	# game over display (suppressed)


# Enable inputs when the first card is drawn
func on_first_card_drawn() -> void:
	ui_panel.mouse_filter = Control.MOUSE_FILTER_PASS


func _on_end_round_tray_input(ev) -> void:
	# Close on any mouse click or key press
	if ev and (ev is InputEventMouseButton and ev.pressed or ev is InputEventKey and ev.pressed):
		_close_end_round_tray()

func _flash_card(card: Node) -> void:
	# Simple flash: scale up slightly and flash modulate on the Visuals node if present
	if not is_instance_valid(card):
		return
	if not card.has_node("Visuals"):
		return
	var visuals = card.get_node("Visuals")
	var orig_scale = visuals.scale
	var t = create_tween()
	t.tween_property(visuals, "scale", orig_scale * 1.18, 0.12).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(visuals, "modulate", Color(1.8, 1.8, 1.8, 1.0), 0.08)
	t.chain().tween_property(visuals, "scale", orig_scale, 0.18).set_ease(Tween.EASE_IN_OUT)
	t.parallel().tween_property(visuals, "modulate", Color(1, 1, 1, 1), 0.18)


func _close_end_round_tray() -> void:
	if end_round_tray:
		if end_round_tray.is_connected("gui_input", Callable(self, "_on_end_round_tray_input")):
			end_round_tray.disconnect("gui_input", Callable(self, "_on_end_round_tray_input"))
		end_round_tray.visible = false
	if game_state_overlay:
		game_state_overlay.visible = false
	emit_signal("end_round_closed")


func await_end_round_close() -> void:
	# Helper for code that wants to wait until the tray is dismissed.
	if not end_round_tray or not end_round_tray.visible:
		return
	await self.end_round_closed

# Added logic to suppress hover-triggered commentary when it's not the player's turn
func suppress_hover_commentary(is_player_turn: bool) -> void:
	var info_manager = get_node_or_null("/root/main/Managers/InfoScreenManager")
	if info_manager:
		if not is_player_turn:
			info_manager.clear()
