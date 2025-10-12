extends Node

#region Showcase Options Dynamic Logic
# -----------------------------------------------------------------------------
# These variables will store the callbacks for the showcase option buttons
var _option_button_1_callback = null
var _option_button_2_callback = null

func show_showcase_options(options: Array):
	if not is_instance_valid(showcase_options_container): 
		push_error("UIManager: ShowcaseOptions container not found.")
		return

	# Disconnect any old signals to prevent them from firing multiple times
	if is_instance_valid(option_button_1) and option_button_1.is_connected("pressed", _on_showcase_button_pressed):
		option_button_1.disconnect("pressed", _on_showcase_button_pressed)
	if is_instance_valid(option_button_2) and option_button_2.is_connected("pressed", _on_showcase_button_pressed):
		option_button_2.disconnect("pressed", _on_showcase_button_pressed)

	# Configure the buttons based on the options array
	if not options.is_empty():
		showcase_options_container.show()
		if is_instance_valid(catcher_button):
			catcher_button.hide() # Hide the background catcher

		var opt1 = options[0]
		var label1 = option_button_1.get_node_or_null("Label")
		if label1 and label1 is Label:
			label1.text = opt1.get("label", "Option 1")
		option_button_1.pressed.connect(_on_showcase_button_pressed.bind(opt1.get("callback")))
		option_button_1.show()

		if options.size() > 1:
			var opt2 = options[1]
			var label2 = option_button_2.get_node_or_null("Label")
			if label2 and label2 is Label:
				label2.text = opt2.get("label", "Option 2")
			option_button_2.pressed.connect(_on_showcase_button_pressed.bind(opt2.get("callback")))
			option_button_2.show()
		else:
			option_button_2.hide()
	else:
		hide_showcase_options()
# -----------------------------------------------------------------------------

## Emitted when the game's start sequence animation finishes.
signal start_sequence_finished
## Emitted when the end-of-round tray is closed by the player.
signal end_round_closed
## Emitted when the "Your Turn" / "Opponent's Turn" message animation finishes.
signal turn_message_finished
## Emitted when a showcase option is selected.
signal showcase_option_selected(callback)

#region Exports
@export_group("Loading")
@export var loading_opacity: float = 0.9

@export_group("Action Panels")
## Alpha used for the "off" state (panels look dim/transparent).
@export var panels_off_alpha: float = 0.03
## Alpha used for the "on" state (panels become fully visible).
@export var panels_on_alpha: float = 1.0

@export_group("End Round Timing")
@export var end_round_card_scale: float = 0.35
@export var end_round_step_delay: float = 0.28
@export var end_round_pop_grow_time: float = 0.12
@export var end_round_pop_flash_time: float = 0.08
@export var end_round_pop_settle_time: float = 0.18
@export var end_round_summary_delay: float = 0.8
@export var end_round_summary_to_score_delay: float = 1.0

@export_group("End Round Awarding")
@export var end_round_award_duration: float = 0.9
@export var end_round_award_step_time: float = 0.04
#endregion

#region Node References (resolved in _ready)
# Main UI Panels and Overlays
@onready var game_state_overlay: Control = get_node_or_null("/root/main/FrontLayerUI/GameStateOverlay")
@onready var end_round_tray: Control = get_node_or_null("/root/main/FrontLayerUI/EndRoundTray")
@onready var end_game_tray: Control = get_node_or_null("/root/main/FrontLayerUI/EndGameTray")
@onready var ui_panel: Control = get_node_or_null("/root/main/FrontLayerUI/UIPanel")
@onready var loading_rect: ColorRect = get_node_or_null("/root/main/FrontLayerUI/UIPanel/Loading")

# UI Panel Child Nodes
@onready var round_label: Label = get_node_or_null("/root/main/FrontLayerUI/UIPanel/PanelBG/VBoxContainer/RoundTitle/Round#")
@onready var player_score_box: Control = get_node_or_null("/root/main/FrontLayerUI/UIPanel/PanelBG/VBoxContainer/TurnEconomy/PlayerUI/Scorebox")
@onready var opponent_score_box: Control = get_node_or_null("/root/main/FrontLayerUI/UIPanel/PanelBG/VBoxContainer/TurnEconomy/OpponentUI/Scorebox")
@onready var player_actions_left_label: Label = get_node_or_null("/root/main/FrontLayerUI/UIPanel/PanelBG/VBoxContainer/TurnEconomy/PlayerUI/ActionDisplay/ActionsLeftLabel")
@onready var opponent_actions_left_label: Label = get_node_or_null("/root/main/FrontLayerUI/UIPanel/PanelBG/VBoxContainer/TurnEconomy/OpponentUI/ActionDisplay/ActionsLeftLabel")
@onready var player_actions_panel: Control = get_node_or_null("/root/main/FrontLayerUI/UIPanel/PanelBG/VBoxContainer/TurnEconomy/PlayerUI")
@onready var opponent_actions_panel: Control = get_node_or_null("/root/main/FrontLayerUI/UIPanel/PanelBG/VBoxContainer/TurnEconomy/OpponentUI")
@onready var player_pass_button: TextureButton = get_node_or_null("/root/main/FrontLayerUI/UIPanel/PanelBG/VBoxContainer/TurnEconomy/PlayerUI/PassButton")
@onready var showcase_options_container = get_node_or_null("/root/main/FrontLayerUI/InputCatcher/ShowcaseOptions")
@onready var option_button_1 = get_node_or_null("/root/main/FrontLayerUI/InputCatcher/ShowcaseOptions/OptionButton1")
@onready var option_button_2 = get_node_or_null("/root/main/FrontLayerUI/InputCatcher/ShowcaseOptions/OptionButton2")
@onready var catcher_button = get_node_or_null("/root/main/FrontLayerUI/InputCatcher/Catcher")
#endregion

var active_end_round_snapshots: Array[Node] = []
var _start_sequence_data: Dictionary = {}

func _ready() -> void:
	# Register this manager with the GameManager singleton if available.
	var gm = _resolve_game_manager()
	if gm and gm.has_method("register_manager"):
		gm.register_manager("UIManager", self)

	# --- Initial UI State Setup ---
	if is_instance_valid(ui_panel):
		ui_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	if is_instance_valid(loading_rect):
		loading_rect.visible = false
		loading_rect.modulate.a = loading_opacity

	if is_instance_valid(player_actions_panel):
		player_actions_panel.modulate.a = panels_off_alpha
	if is_instance_valid(opponent_actions_panel):
		opponent_actions_panel.modulate.a = panels_off_alpha

	# --- Signal Connections ---
	if is_instance_valid(player_pass_button):
		# Ensure we don't double-connect the pressed signal.
		if not player_pass_button.is_connected("pressed", _on_player_pass_pressed):
			player_pass_button.connect("pressed", _on_player_pass_pressed)
		
		# Hover signals are always connected; the handler will check for turn state.
		if not player_pass_button.is_connected("mouse_entered", _on_pass_button_hover):
			player_pass_button.connect("mouse_entered", _on_pass_button_hover)
		if not player_pass_button.is_connected("mouse_exited", _on_pass_button_exit):
			player_pass_button.connect("mouse_exited", _on_pass_button_exit)

	print("UIManager ready.")


#region Public API
# -----------------------------------------------------------------------------
# Methods called by other managers (GameManager, TurnManager, etc.)

func show_loading() -> void:
	if is_instance_valid(loading_rect):
		loading_rect.visible = true

func hide_loading() -> void:
	if is_instance_valid(loading_rect):
		loading_rect.visible = false

func set_pass_button_enabled(enabled: bool) -> void:
	if is_instance_valid(player_pass_button):
		player_pass_button.disabled = not enabled

func set_end_round_mode(enabled: bool) -> void:
	if is_instance_valid(player_actions_panel):
		player_actions_panel.modulate.a = panels_on_alpha if enabled else panels_off_alpha
	if is_instance_valid(opponent_actions_panel):
		opponent_actions_panel.modulate.a = panels_on_alpha if enabled else panels_off_alpha

	if is_instance_valid(player_pass_button):
		player_pass_button.modulate.a = panels_off_alpha if enabled else 1.0
		player_pass_button.disabled = enabled
		player_pass_button.mouse_filter = Control.MOUSE_FILTER_IGNORE if enabled else Control.MOUSE_FILTER_PASS

func show_game_start_sequence(round_number: int, is_player_turn: bool) -> void:
	if not is_instance_valid(game_state_overlay): return
	var label = game_state_overlay.get_node_or_null("CenterContainer/GameState")
	if not is_instance_valid(label): return

	game_state_overlay.visible = true
	label.modulate.a = 0.0

	var turn_text = "Your Turn" if is_player_turn else "Opponent's Turn"
	_start_sequence_data = {
		"label": label,
		"texts": ["Game Start", "Round %d" % round_number, turn_text]
	}
	_advance_start_sequence()

func show_turn_message(is_player_turn: bool) -> void:
	if not is_instance_valid(game_state_overlay): return
	var label = game_state_overlay.get_node_or_null("CenterContainer/GameState")
	if not is_instance_valid(label): return

	game_state_overlay.visible = true
	label.modulate.a = 0.0
	label.text = "Your \nTurn" if is_player_turn else "Opponent's \nTurn"
	
	var tween = create_tween().set_parallel()
	tween.tween_property(label, "modulate:a", 1.0, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.chain().tween_interval(0.9)
	tween.chain().tween_property(label, "modulate:a", 0.0, 0.25)
	tween.chain().tween_callback(func():
		if is_instance_valid(game_state_overlay):
			game_state_overlay.visible = false
		emit_signal("turn_message_finished")
	)

func update_round_display(round_number: int) -> void:
	if is_instance_valid(round_label):
		round_label.text = str(round_number)

func update_scores(scores: Dictionary) -> void:
	_set_scorebox_value(0, scores.get(0, 0))
	_set_scorebox_value(1, scores.get(1, 0))

func set_active_player(is_player_turn: bool) -> void:
	var target_alpha: float = panels_on_alpha if is_player_turn else panels_off_alpha
	if is_instance_valid(player_actions_panel):
		player_actions_panel.modulate.a = target_alpha
	if is_instance_valid(opponent_actions_panel):
		opponent_actions_panel.modulate.a = target_alpha
	
	set_pass_button_enabled(is_player_turn)

func on_first_card_drawn() -> void:
	if is_instance_valid(ui_panel):
		ui_panel.mouse_filter = Control.MOUSE_FILTER_PASS

#endregion

#region End of Round/Game
# -----------------------------------------------------------------------------

func show_end_round_screen(_winner: int, _player_total: int, _opponent_total: int, player_cards_info: Array = [], opponent_cards_info: Array = [], awarded_p1: int = 0, awarded_p2: int = 0) -> void:
	if not is_instance_valid(end_round_tray): return

	var player_lbl = end_round_tray.find_child("PlayerHandTotal", true, false)
	var opp_lbl = end_round_tray.find_child("OpponentHandTotal", true, false)
	var round_summary = end_round_tray.find_child("RoundSummary", true, false)

	# Initialize UI
	if player_lbl is Label: player_lbl.text = "0"
	if opp_lbl is Label: opp_lbl.text = "0"
	if round_summary is Label:
		round_summary.text = ""
		round_summary.visible = false

	end_round_tray.visible = true
	end_round_tray.grab_focus()
	if not end_round_tray.is_connected("gui_input", _on_end_round_tray_input):
		end_round_tray.connect("gui_input", _on_end_round_tray_input)

	# Interleave card reveals for both players
	var displayed_player_total = 0
	var displayed_opponent_total = 0
	var max_len = max(player_cards_info.size(), opponent_cards_info.size())
	
	for i in range(max_len):
		if i < player_cards_info.size():
			var p_info = player_cards_info[i]
			var p_val = int(p_info.get("value", 0))
			displayed_player_total += p_val
			if player_lbl is Label: player_lbl.text = str(displayed_player_total)
			var p_card = _find_card_node(p_info.get("name", ""), true)
			if is_instance_valid(p_card):
				_pop_and_flash_card(p_card, true, i)

		if i < opponent_cards_info.size():
			var o_info = opponent_cards_info[i]
			var o_val = int(o_info.get("value", 0))
			displayed_opponent_total += o_val
			if opp_lbl is Label: opp_lbl.text = str(displayed_opponent_total)
			var o_card = _find_card_node(o_info.get("name", ""), false)
			if is_instance_valid(o_card):
				_pop_and_flash_card(o_card, false, i)

		if end_round_step_delay > 0.0:
			await get_tree().create_timer(end_round_step_delay).timeout

	# Finalize totals and show winner summary
	if player_lbl is Label: player_lbl.text = str(displayed_player_total)
	if opp_lbl is Label: opp_lbl.text = str(displayed_opponent_total)
	
	if _winner != -1 and round_summary is Label:
		if end_round_summary_delay > 0.0: await get_tree().create_timer(end_round_summary_delay).timeout
		round_summary.text = "You win!" if _winner == 0 else "You've lost..."
		round_summary.visible = true

		if end_round_summary_to_score_delay > 0.0: await get_tree().create_timer(end_round_summary_to_score_delay).timeout
		var awarded = awarded_p1 if _winner == 0 else awarded_p2
		if awarded > 0:
			await _animate_award_numeric(_winner, awarded)

func show_game_over_screen(_winner: int, _final_score: int) -> void:
	if is_instance_valid(end_game_tray):
		end_game_tray.visible = true
		# TODO: Update labels in end_game_tray with winner info

func await_end_round_close() -> Signal:
	if not is_instance_valid(end_round_tray) or not end_round_tray.visible:
		return await get_tree().process_frame
	return await end_round_closed

func _close_end_round_tray() -> void:
	if is_instance_valid(end_round_tray):
		if end_round_tray.is_connected("gui_input", _on_end_round_tray_input):
			end_round_tray.disconnect("gui_input", _on_end_round_tray_input)
		
		for snapshot in active_end_round_snapshots:
			if is_instance_valid(snapshot):
				snapshot.queue_free()
		active_end_round_snapshots.clear()
		end_round_tray.visible = false
	
	emit_signal("end_round_closed")

#endregion

#region Internal Helpers
# -----------------------------------------------------------------------------

## Recursively searches for a descendant node by name.
func _find_descendant_by_name(root: Node, target_name: String) -> Node:
	if not is_instance_valid(root): return null
	for child in root.get_children():
		if child.name == target_name:
			return child
		var found = _find_descendant_by_name(child, target_name)
		if is_instance_valid(found):
			return found
	return null

## Finds a card node, preferring CardManager (hands) then the DiscardPile.
func _find_card_node(card_name: String, is_player: bool) -> Node:
	var card_manager = get_node_or_null("/root/main/Parallax/CardManager")
	if is_instance_valid(card_manager):
		for card in card_manager.get_children():
			if "card_name" in card and card.card_name == card_name and "is_player_card" in card and card.is_player_card == is_player:
				return card

	var discard_pile = get_node_or_null("/root/main/DiscardPile")
	if is_instance_valid(discard_pile):
		for card in discard_pile.get_children():
			if "card_name" in card and card.card_name == card_name:
				return card
	return null

func _get_hand_slot_node(is_player: bool, index: int) -> Node:
	var slot_name = ("PlayerHandSlot" if is_player else "OpponentHandSlot") + str(index + 1)
	if is_instance_valid(end_round_tray):
		return end_round_tray.find_child(slot_name, true, false)
	return null

func _pop_and_flash_card(card: Node, is_player: bool, slot_index: int) -> void:
	if not is_instance_valid(card) or not card.has_node("Visuals"): return
	var visuals = card.get_node("Visuals")
	var slot = _get_hand_slot_node(is_player, slot_index)
	if not is_instance_valid(slot): return

	var snapshot: TextureRect = await _create_visual_snapshot(visuals, slot)
	if not is_instance_valid(snapshot): return
	
	active_end_round_snapshots.append(snapshot)
	var final_scale = Vector2.ONE * end_round_card_scale
	snapshot.scale = final_scale * 0.02
	
	var t = create_tween().set_parallel()
	t.tween_property(snapshot, "scale", final_scale * 1.18, end_round_pop_grow_time).set_ease(Tween.EASE_OUT)
	t.tween_property(snapshot, "modulate", Color.WHITE_SMOKE, end_round_pop_flash_time)
	t.chain().tween_property(snapshot, "scale", final_scale, end_round_pop_settle_time).set_ease(Tween.EASE_IN_OUT)
	t.parallel().tween_property(snapshot, "modulate", Color.WHITE, end_round_pop_settle_time)
	await t.finished

## Creates a TextureRect snapshot of a card's visuals and parents it to the specified slot.
func _create_visual_snapshot(visual_node: Node, slot: Node) -> TextureRect:
	if not is_instance_valid(visual_node) or not is_instance_valid(slot): return null

	# Optimization: If the card's visuals already use a SubViewport, just use its texture.
	var sub_viewport = _find_descendant_by_name(visual_node, "SubViewport")
	var texture = sub_viewport.get_texture() if is_instance_valid(sub_viewport) else null

	if not texture:
		# Fallback: Create a temporary SubViewport to render the visuals.
		var vp = SubViewport.new()
		vp.size = Vector2i(500, 700) # Assume default card size
		vp.transparent_bg = true
		vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		add_child(vp)
		vp.add_child(visual_node.duplicate(true))
		
		# Wait a frame for the viewport to render.
		await get_tree().process_frame
		texture = vp.get_texture()
		vp.queue_free()

	if not texture: return null

	var tex_rect = TextureRect.new()
	tex_rect.texture = texture
	tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex_rect.z_index = 100 # Ensure it's on top.
	
	var parent_container = end_round_tray if is_instance_valid(end_round_tray) else slot
	parent_container.add_child(tex_rect)

	# Position the snapshot over the slot.
	var slot_global_pos = slot.get_global_position() if slot is Control else slot.global_position
	var parent_global_pos = parent_container.get_global_position() if parent_container is Control else parent_container.global_position
	var local_pos = slot_global_pos - parent_global_pos
	var tex_size = texture.get_size() * end_round_card_scale
	tex_rect.position = local_pos - tex_size * 0.5

	return tex_rect

func _advance_start_sequence() -> void:
	if not _start_sequence_data: return
	
	var label: Label = _start_sequence_data.get("label")
	var texts: Array = _start_sequence_data.get("texts")

	if texts.is_empty():
		_on_start_sequence_complete()
		return

	label.text = texts.pop_front()
	var tween = create_tween().set_parallel()
	tween.tween_property(label, "modulate:a", 1.0, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.chain().tween_interval(0.9)
	tween.chain().tween_property(label, "modulate:a", 0.0, 0.25)
	tween.chain().tween_callback(_advance_start_sequence)

func _set_scorebox_value(player_index: int, value: int) -> void:
	var box = player_score_box if player_index == 0 else opponent_score_box
	if not is_instance_valid(box): return
	
	var digits_str = "%03d" % value
	var d1 = box.get_node_or_null("#__")
	var d2 = box.get_node_or_null("_#_")
	var d3 = box.get_node_or_null("__#")
	if d1 is Label: d1.text = digits_str[0]
	if d2 is Label: d2.text = digits_str[1]
	if d3 is Label: d3.text = digits_str[2]

func _animate_award_numeric(winner_index: int, awarded_points: int) -> Signal:
	var gm = _resolve_game_manager()
	if not gm:
		return await get_tree().process_frame
		
	var base_total = gm.get_total_score(winner_index)
	var end_val = base_total + awarded_points

	var t = create_tween()
	# Use a property tween on a temporary variable for a smooth count-up effect.
	var countup = {"value": base_total}
	t.tween_property(countup, "value", end_val, end_round_award_duration)
	# On each frame of the tween, update the label text.
	t.tween_method(func(val): _set_scorebox_value(winner_index, int(val)), base_total, end_val, end_round_award_duration)

	# After the animation finishes, update the actual game state.
	t.chain().tween_callback(func():
		_set_scorebox_value(winner_index, end_val)
		if gm.has_method("add_score"):
			gm.add_score(winner_index, awarded_points)
	)
	return t.finished

func _resolve_game_manager() -> Node:
	# Prefer the singleton path if it exists.
	var gm = get_node_or_null("/root/GameManager")
	if not gm:
		gm = get_tree().get_root().find_child("GameManager", true, false)
	return gm
#endregion

#region Signal Handlers
func _on_showcase_button_pressed(callback: Callable):
	# When a button is pressed, tell the GameManager which choice was made.
	emit_signal("showcase_option_selected", callback)
# -----------------------------------------------------------------------------
func _on_player_pass_pressed() -> void:
	var gm = _resolve_game_manager()
	if gm and gm.has_method("get_manager"):
		var tm = gm.get_manager("TurnManager")
		if tm and tm.has_method("pass_current_player"):
			tm.pass_current_player()

func _on_pass_button_hover() -> void:
	var tm = _resolve_game_manager().get_manager("TurnManager")
	# Only show hover message if it is currently the player's turn.
	if not tm or not tm.get_is_player_turn(): return

	var info_manager = _resolve_game_manager().get_manager("InfoScreenManager")
	if info_manager and info_manager.has_method("show_pass_button_hover"):
		var actions_left = int(player_actions_left_label.text) if is_instance_valid(player_actions_left_label) else 0
		info_manager.show_pass_button_hover(actions_left)

func _on_pass_button_exit() -> void:
	var info_manager = _resolve_game_manager().get_manager("InfoScreenManager")
	if info_manager and info_manager.has_method("clear"):
		info_manager.clear()

func _on_start_sequence_complete() -> void:
	if is_instance_valid(game_state_overlay):
		game_state_overlay.visible = false
	emit_signal("start_sequence_finished")

func _on_end_round_tray_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.is_pressed() or event is InputEventKey and event.is_pressed():
		_close_end_round_tray()

func on_showcase_button_pressed(callback: Callable):
	print("Showcase button pressed. Callback: %s" % callback)
	hide_showcase_options()
	emit_signal("showcase_option_selected", callback)

func hide_showcase_options() -> void:
	if is_instance_valid(showcase_options_container):
		showcase_options_container.visible = false
#endregion


func enable_selection_mode_ui():
	"""Prepares the UI for card selection by hiding the main input blocker."""
	if is_instance_valid(catcher_button):
		catcher_button.hide()

func disable_selection_mode_ui():
	"""Restores the UI to its normal state after selection is complete."""
	if is_instance_valid(catcher_button):
		# We don't necessarily show it, just ensure it's not blocking.
		# The showcase logic will show it if needed.
		pass
