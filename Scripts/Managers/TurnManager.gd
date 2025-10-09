# TurnManager.gd
extends Node

# --- References (Set by GameManager on _ready) ---
var game_manager: Node
var ui_manager: Node
var card_manager: Node

# --- Turn State ---
var current_player: int = 0  # Use GameManager.Player enum semantics: 0 = PLAYER_ONE (you), 1 = PLAYER_TWO (opponent)
var is_player_turn: bool = true

# --- Action Tracking ---
@export var actions_per_turn: int = 2
var player_actions_remaining: int = 0
var opponent_actions_remaining: int = 0

@export var show_turn_overlay: bool = false
# Turn transition scheduling: incrementing id invalidates previous scheduled transitions
var _turn_transition_id: int = 0

func _schedule_turn_transition(delay: float) -> void:
	# Increment id to invalidate previous schedules
	_turn_transition_id += 1
	var this_id = _turn_transition_id
	print("TurnManager: scheduling turn transition in", delay, "seconds (id=", this_id, ")")
	# Defer to a helper that awaits a scene-tree timer so we don't block
	call_deferred("_delayed_transition", delay, this_id)

func _delayed_transition(delay: float, id: int) -> void:
	# Wait for the timer to time out, then execute if still valid
	await get_tree().create_timer(delay).timeout
	_execute_scheduled_transition(id)

func _execute_scheduled_transition(id: int) -> void:
	# Only execute if id matches latest
	if id != _turn_transition_id:
		print("TurnManager: scheduled transition id", id, "cancelled (current=", _turn_transition_id, ")")
		return
	print("TurnManager: executing scheduled transition id", id)
	# Ensure ui_manager is resolved (registration order may vary)
	if not ui_manager and game_manager and game_manager.has_method("get_manager"):
		ui_manager = game_manager.get_manager("UIManager")
	if not ui_manager:
		# Fallback scene path
		ui_manager = get_node_or_null("/root/main/FrontLayerUI/UIPanel")

	# Optionally show the turn overlay for the upcoming player (if enabled)
	if show_turn_overlay:
		var upcoming_is_player_turn = not is_player_turn
		if ui_manager and ui_manager.has_method("show_turn_message"):
			ui_manager.show_turn_message(upcoming_is_player_turn)

	next_turn()

# --- UI Opacity Settings ---
@export var active_player_opacity: float = 1.0
@export var inactive_player_opacity: float = 0.4
@export var opacity_transition_duration: float = 0.3

# --- Action icon pop tuning ---
@export var action_pop_scale: float = 1.35
@export var action_pop_rotation_degrees: float = 12.0
@export var action_pop_grow_time: float = 0.09
@export var action_pop_settle_time: float = 0.2

# If false, action icons will be visually unfilled at game/round start even if counts are full
@export var fill_icons_on_start: bool = false
@export var end_of_actions_delay: float = 2.0

func _ready() -> void:
	print("TurnManager: _ready called")
	
	# Try to get GameManager via autoload (singleton) first
	game_manager = get_node_or_null("/root/GameManager")

	# If not an autoload, try parent container lookup
	if not game_manager:
		var manager_container = get_parent()
		if manager_container:
			game_manager = manager_container.get_node_or_null("GameManager")

	# Try to obtain other managers from GameManager
	if game_manager and game_manager.has_method("get_manager"):
		ui_manager = game_manager.get_manager("UIManager")
		card_manager = game_manager.get_manager("CardManager")
		print("TurnManager: ui_manager from GameManager =", ui_manager)
		print("TurnManager: card_manager from GameManager =", card_manager)

	# If we have a GameManager autoload, register ourselves
	if game_manager and game_manager.has_method("register_manager"):
		print("TurnManager: registering with GameManager")
		game_manager.register_manager("TurnManager", self)
	else:
		print("TurnManager: GameManager not found on register step or no register method")

	# Ensure we have critical references
	if not game_manager:
		push_error("TurnManager: GameManager not found (autoload or parent).")
	if not ui_manager:
		print("TurnManager: UIManager not found (will try to fetch later).")
	if not card_manager:
		print("TurnManager: CardManager not found (will try to fetch later).")

	# Immediately clear action icon fills on ready to avoid any initial green flash
	if not fill_icons_on_start:
		# Try cached UIManager panels first
		if ui_manager:
			if ui_manager.player_actions_panel:
				_force_set_action_icons_fill(ui_manager.player_actions_panel, 0.0)
			if ui_manager.opponent_actions_panel:
				_force_set_action_icons_fill(ui_manager.opponent_actions_panel, 0.0)
		else:
			# Fallback to known scene paths
			var base_path = "/root/main/FrontLayerUI/UIPanel/PanelBG/VBoxContainer/TurnEconomy/"
			var ppanel = get_node_or_null(base_path + "PlayerUI")
			var oppanel = get_node_or_null(base_path + "OpponentUI")
			if ppanel:
				_force_set_action_icons_fill(ppanel, 0.0)
			if oppanel:
				_force_set_action_icons_fill(oppanel, 0.0)

## Called by RoundManager or GameManager to start turn management
func start_turn_management(starting_player: int) -> void:
	print("TurnManager: Starting turn management with player", starting_player)
	current_player = starting_player
	# Consider PLAYER_ONE (0) as the local player
	is_player_turn = (current_player == 0)

	# Give actions only to the active player: active gets full pool, inactive gets 0
	if is_player_turn:
		player_actions_remaining = actions_per_turn
		opponent_actions_remaining = 0
	else:
		player_actions_remaining = 0
		opponent_actions_remaining = actions_per_turn

	print("TurnManager: initial state -> current_player:", current_player, "is_player_turn:", is_player_turn, "player_actions:", player_actions_remaining, "opponent_actions:", opponent_actions_remaining)

	_update_ui_opacity()
	_update_action_ui()

	# Optionally force the icons to appear unfilled at launch while keeping counts intact
	if not fill_icons_on_start:
		# Try using UIManager cached panels first
		if ui_manager:
			if ui_manager.player_actions_panel:
				_force_set_action_icons_fill(ui_manager.player_actions_panel, 0.0)
			if ui_manager.opponent_actions_panel:
				_force_set_action_icons_fill(ui_manager.opponent_actions_panel, 0.0)
		else:
			# Fallback to scene paths
			var base_path = "/root/main/FrontLayerUI/UIPanel/PanelBG/VBoxContainer/TurnEconomy/"
			var ppanel = get_node_or_null(base_path + "PlayerUI")
			var oppanel = get_node_or_null(base_path + "OpponentUI")
			if ppanel:
				_force_set_action_icons_fill(ppanel, 0.0)
			if oppanel:
				_force_set_action_icons_fill(oppanel, 0.0)

## Instantly set the shader fill_alpha for action icons without tweening to avoid initial flash
func _force_set_action_icons_fill(panel: Node, target_opacity: float) -> void:
	if not panel:
		return
	var icons_container = panel.get_node_or_null("ActionIcons")
	if not icons_container:
		icons_container = panel.find_node("ActionIcons", true, false)
	if not icons_container:
		return

	for child in icons_container.get_children():
		if not child:
			continue
		var mat = null
		if child.has_method("get"):
			mat = child.material if "material" in child else null
		if mat and mat is ShaderMaterial:
			# Directly set shader parameter to avoid any tween animation
			mat.set_shader_parameter("fill_alpha", target_opacity)

## Switch to the next player's turn
func next_turn() -> void:
	# Switch player
	# Toggle between 0 (PLAYER_ONE) and 1 (PLAYER_TWO)
	current_player = 1 if current_player == 0 else 0
	is_player_turn = (current_player == 0)
	
	print("TurnManager: Switched to player", current_player, "turn")
	
	# Update UI opacity
	_update_ui_opacity()

	# Reset action counts for the new turn: active player gets full actions, inactive gets 0
	if is_player_turn:
		player_actions_remaining = actions_per_turn
		opponent_actions_remaining = 0
	else:
		player_actions_remaining = 0
		opponent_actions_remaining = actions_per_turn

	_update_action_ui()
	
	# TODO: Add turn-based logic here (card play restrictions, etc.)

## Update UI opacity based on whose turn it is
func _update_ui_opacity() -> void:
	print("TurnManager: Updating UI opacity - Player turn:", is_player_turn)

	# Decide opacities for each side
	var player_opacity = active_player_opacity if is_player_turn else inactive_player_opacity
	var opponent_opacity = active_player_opacity if not is_player_turn else inactive_player_opacity

	# Also inform UIManager (if present) for immediate effect
	if ui_manager and ui_manager.has_method("set_active_player"):
		print("TurnManager: calling ui_manager.set_active_player(", is_player_turn, ")")
		ui_manager.set_active_player(is_player_turn)

	_set_side_ui_opacity("PlayerUI", player_opacity)
	_set_side_ui_opacity("OpponentUI", opponent_opacity)

## Update the action UI (icons + labels) for both sides
func _update_action_ui() -> void:
	# Player
	_set_action_ui("PlayerUI", player_actions_remaining, actions_per_turn)
	# Opponent
	_set_action_ui("OpponentUI", opponent_actions_remaining, actions_per_turn)

	# Enable/disable pass button for the local player: enabled when it's their turn and they have actions remaining
	if ui_manager and ui_manager.has_method("set_pass_button_enabled"):
		var enable_pass = is_player_turn and player_actions_remaining > 0
		ui_manager.set_pass_button_enabled(enable_pass)

	print("TurnManager: action UI updated -> player_actions_remaining:", player_actions_remaining, "opponent_actions_remaining:", opponent_actions_remaining, "is_player_turn:", is_player_turn)

## Set action icons and label for a side
func _set_action_ui(side_name: String, remaining: int, total: int) -> void:
	print("TurnManager: _set_action_ui called for", side_name, "remaining:", remaining, "total:", total)
	# Try UIManager cached references first
	var actions_panel: Node = null
	var actions_label: Node = null
	if ui_manager:
		if side_name == "PlayerUI":
			actions_panel = ui_manager.player_actions_panel
			actions_label = ui_manager.player_actions_left_label
		else:
			actions_panel = ui_manager.opponent_actions_panel
			actions_label = ui_manager.opponent_actions_left_label

	# Fallback to scene lookups
	if not actions_panel:
		var base_path = "/root/main/FrontLayerUI/UIPanel/PanelBG/VBoxContainer/TurnEconomy/"
		actions_panel = get_node_or_null(base_path + side_name)
		if not actions_panel:
			actions_panel = get_node_or_null("/root/main/PanelBG/VBoxContainer/TurnEconomy/" + side_name)

	# If the UIManager didn't give us the label, try to locate it under the panel (ActionDisplay/ActionsLeftLabel)
	if not actions_label and actions_panel:
		# Common subpath inside each side panel
		var label_node = actions_panel.get_node_or_null("ActionDisplay/ActionsLeftLabel")
		if not label_node:
			# recursive find
			label_node = actions_panel.find_node("ActionsLeftLabel", true, false)
		if label_node:
			actions_label = label_node

	# Update label
	if actions_label:
		# Debug: report the label node and its path if possible
		var label_path = "<unknown>"
		if actions_label.has_method("get_path"):
			label_path = str(actions_label.get_path())
		print("TurnManager: found actions_label for", side_name, "->", actions_label, "path:", label_path)

		# If there are no actions configured for this mode, hide the label text
		if total <= 0:
			if actions_label.has_method("set_text"):
				actions_label.set_text("")
			else:
				actions_label.text = ""
			print("TurnManager: actions_per_turn is 0, hiding actions label for", side_name)
		else:
			var new_text = "%d/%d" % [remaining, total]
			# Prefer calling set_text if present, else set property
			if actions_label.has_method("set_text"):
				actions_label.set_text(new_text)
			else:
				actions_label.text = new_text
			print("TurnManager: Updated actions_label (", side_name, ") to:", new_text)
	else:
		print("TurnManager: No actions_label found for", side_name)

	# Update icons fill
	if actions_panel:
		_set_action_icons_fill(actions_panel, remaining, total)

## Set the shader fill of action icons inside a panel
func _set_action_icons_fill(panel: Node, remaining: int, _total: int) -> void:
	if not panel:
		return
	# Find the ActionIcons container
	var icons_container = panel.get_node_or_null("ActionIcons")
	if not icons_container:
		icons_container = panel.find_node("ActionIcons", true, false)
	if not icons_container:
		return

	var i: int = 0
	for child in icons_container.get_children():
		if i < remaining:
			# set filled
			if child and child is CanvasItem:
				var mat = child.material if "material" in child else null
				if mat and mat is ShaderMaterial:
					var t = create_tween()
					t.tween_property(mat, "shader_parameter/fill_alpha", 1.0, opacity_transition_duration)
		else:
			# set empty
			if child and child is CanvasItem:
				var mat2 = child.material if "material" in child else null
				if mat2 and mat2 is ShaderMaterial:
					var t2 = create_tween()
					t2.tween_property(mat2, "shader_parameter/fill_alpha", 0.0, opacity_transition_duration)
		i += 1

	# Ensure icon scales reset to 1.0 to avoid leftover transforms
	for c in icons_container.get_children():
		if not c:
			continue
		# Prefer rect_scale for Controls if present, otherwise use generic scale
		if "rect_scale" in c:
			c.rect_scale = Vector2.ONE
		elif "scale" in c:
			c.scale = Vector2.ONE
		# Reset rotation if present to avoid leftover tilt
		if "rotation_degrees" in c:
			c.rotation_degrees = 0
		elif "rotation" in c:
			c.rotation = 0

## Public API: record that an action was played (e.g., a card dropped into the drop zone)
func record_action_played(is_player_card: bool) -> void:
	if is_player_card:
		if player_actions_remaining > 0:
			# decrement then pop the icon corresponding to the new remaining count
			player_actions_remaining -= 1
			_pop_action_icon_for_side("PlayerUI", player_actions_remaining)
			# If this was the last action, schedule a transition to the next turn after the configured delay
			if player_actions_remaining == 0:
				_schedule_turn_transition(end_of_actions_delay)
		else:
			print("TurnManager: player attempted to play with no actions remaining")
	else:
		if opponent_actions_remaining > 0:
			opponent_actions_remaining -= 1
			_pop_action_icon_for_side("OpponentUI", opponent_actions_remaining)
			# If opponent just used their last action, schedule turn transition
			if opponent_actions_remaining == 0:
				_schedule_turn_transition(end_of_actions_delay)
		else:
			print("TurnManager: opponent attempted to play with no actions remaining")

	_update_action_ui()

## Public API: current player presses pass (forgo remaining actions)
func pass_current_player() -> void:
	if is_player_turn:
		player_actions_remaining = 0
	else:
		opponent_actions_remaining = 0

	_update_action_ui()
	# When a player passes, schedule the next turn after a short delay
	_schedule_turn_transition(2.0)

## Set opacity for opponent UI panel
func _set_side_ui_opacity(side_name: String, opacity: float) -> void:
	# Generic resolver: try UIManager cached panels, then FrontLayerUI path, then legacy path
	var panel: Node = null
	if ui_manager:
		if side_name == "PlayerUI" and ui_manager.player_actions_panel:
			panel = ui_manager.player_actions_panel
		elif side_name == "OpponentUI" and ui_manager.opponent_actions_panel:
			panel = ui_manager.opponent_actions_panel
		if panel:
			print("TurnManager: Found %s via UIManager" % side_name)

	# Preferred scene location (current layout)
	if not panel:
		var base_path = "/root/main/FrontLayerUI/UIPanel/PanelBG/VBoxContainer/TurnEconomy/"
		panel = get_node_or_null(base_path + side_name)
		if panel:
			print("TurnManager: Found %s at %s" % [side_name, base_path + side_name])
	# Legacy fallback
	if not panel:
		var legacy_base = "/root/main/PanelBG/VBoxContainer/TurnEconomy/"
		panel = get_node_or_null(legacy_base + side_name)
		if panel:
			print("TurnManager: Found %s at %s" % [side_name, legacy_base + side_name])

	if not panel:
		print("TurnManager: Could not find %s in any known location" % side_name)
		return

	print("TurnManager: Setting %s opacity to" % side_name, opacity)
	_animate_ui_opacity(panel, opacity)

	# Also try to dim any action icons (ColorRect children with ShaderMaterial) under an ActionIcons container
	_adjust_action_icons(panel, opacity)

## Animate a UI element's opacity
func _animate_ui_opacity(ui_element: Node, target_opacity: float) -> void:
	if not ui_element:
		return
	
	var tween = create_tween()
	tween.tween_property(ui_element, "modulate:a", target_opacity, opacity_transition_duration)


func _adjust_action_icons(panel: Node, target_opacity: float) -> void:
	if not panel:
		return
	# Look for a container named ActionIcons under the panel
	var icons_container = panel.get_node_or_null("ActionIcons")
	if not icons_container:
		# Try a recursive search for common name
		icons_container = panel.find_node("ActionIcons", true, false)
	if not icons_container:
		return

	# For each child ColorRect in the container, tween the shader's fill_alpha if present
	for child in icons_container.get_children():
		if not child:
			continue
		# If the child has a ShaderMaterial assigned, tween its fill_alpha parameter
		if child.has_method("get") and child.has_meta("material") == false:
			# Some serialized scenes put material directly on the node as 'material'
			pass
		var mat = null
		if child.has_method("get"):
			mat = child.material if "material" in child else null
		if mat and mat is ShaderMaterial:
			# Tween shader_parameter/fill_alpha property on the material
			var t = create_tween()
			t.tween_property(mat, "shader_parameter/fill_alpha", target_opacity, opacity_transition_duration)


## Pop the action icon at a 0-based index inside the given side's ActionIcons container
func _pop_action_icon_for_side(side_name: String, index: int) -> void:
	if index < 0:
		return

	# Resolve panel via UIManager or scene path
	var panel: Node = null
	if ui_manager:
		if side_name == "PlayerUI" and ui_manager.player_actions_panel:
			panel = ui_manager.player_actions_panel
		elif side_name == "OpponentUI" and ui_manager.opponent_actions_panel:
			panel = ui_manager.opponent_actions_panel

	if not panel:
		var base_path = "/root/main/FrontLayerUI/UIPanel/PanelBG/VBoxContainer/TurnEconomy/"
		panel = get_node_or_null(base_path + side_name)
		if not panel:
			panel = get_node_or_null("/root/main/PanelBG/VBoxContainer/TurnEconomy/" + side_name)
	if not panel:
		return

	# Find icons container
	var icons_container = panel.get_node_or_null("ActionIcons")
	if not icons_container:
		icons_container = panel.find_node("ActionIcons", true, false)
	if not icons_container:
		return

	var children = icons_container.get_children()
	if index >= children.size():
		return
	var target = children[index]
	if not target:
		return

	# Ensure starting scale is 1 using property checks
	if "rect_scale" in target:
		target.rect_scale = Vector2.ONE
	elif "scale" in target:
		target.scale = Vector2.ONE

	# Do pop tween (quick grow then settle). Add slight opposing rotation based on index parity
	var rotation_amount = (action_pop_rotation_degrees if (index % 2) == 0 else -action_pop_rotation_degrees)
	# Apply rotation if possible
	var rotate_property = null
	if "rotation_degrees" in target:
		rotate_property = "rotation_degrees"
	elif "rotation" in target:
		rotate_property = "rotation"

	if "rect_scale" in target:
		var tween = create_tween()
		# rotate then pop scale and return rotation
		if rotate_property:
			tween.tween_property(target, rotate_property, rotation_amount, action_pop_grow_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(target, "rect_scale", Vector2(action_pop_scale, action_pop_scale), action_pop_grow_time).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.tween_property(target, "rect_scale", Vector2(1.0, 1.0), action_pop_settle_time).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		if rotate_property:
			tween.tween_property(target, rotate_property, 0, action_pop_settle_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	elif "scale" in target:
		var tween2 = create_tween()
		if rotate_property:
			tween2.tween_property(target, rotate_property, rotation_amount, action_pop_grow_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween2.tween_property(target, "scale", Vector2(action_pop_scale, action_pop_scale), action_pop_grow_time).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween2.tween_property(target, "scale", Vector2(1.0, 1.0), action_pop_settle_time).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		if rotate_property:
			tween2.tween_property(target, rotate_property, 0, action_pop_settle_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

## Get current turn info
func get_current_player() -> int:
	return current_player

func get_is_player_turn() -> bool:
	return is_player_turn
