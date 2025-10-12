# TurnManager.gd
extends Node

# --- References (Set by GameManager on _ready) ---
var game_manager: Node
var ui_manager: Node
var card_manager: Node
var _deferred_ai_mgr: Node = null

# --- Turn State ---
var current_player: int = 0  # Use GameManager.Player enum semantics: 0 = PLAYER_ONE (you), 1 = PLAYER_TWO (opponent)
var is_player_turn: bool = true

# Track whether each side has taken their turn this round. When both true, round should end.
var player_had_turn: bool = false
var opponent_had_turn: bool = false

# Delay after final pass before ending round
@export_group("Round Timing")
@export var end_round_delay_after_pass: float = 1.5
@export var play_effect_delay: float = 0.0 # delay to simulate a card effect / play (was hard-coded 3s)
@export var post_phase_delay: float = 1.0  # delay after discard/message before advancing turn (was hard-coded 1s)

# --- Action Tracking ---
@export_group("Turn Settings")
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
	# print("TurnManager: scheduling turn transition in", delay, "seconds (id=", this_id, ")")
	# Defer to a helper that awaits a scene-tree timer so we don't block
	call_deferred("_delayed_transition", delay, this_id)

func _delayed_transition(delay: float, id: int) -> void:
	# Wait for the timer to time out, then execute if still valid
	await get_tree().create_timer(delay).timeout
	_execute_scheduled_transition(id)

func _execute_scheduled_transition(id: int) -> void:
	if id != _turn_transition_id:
		return

	# Ensure ui_manager is resolved (registration order may vary)
	if not ui_manager and game_manager and game_manager.has_method("get_manager"):
		ui_manager = game_manager.get_manager("UIManager")
	if not ui_manager:
		ui_manager = get_node_or_null("/root/main/FrontLayerUI/UIPanel")

	if not is_player_turn:
		_handle_opponent_action()
	else:
		# Existing logic for player turn
		if show_turn_overlay:
			var upcoming_is_player_turn = not is_player_turn
			if ui_manager and ui_manager.has_method("show_turn_message"):
				ui_manager.show_turn_message(upcoming_is_player_turn)

		next_turn()

# --- UI Opacity Settings ---
@export_group("UI Opacity Settings")
@export var active_player_opacity: float = 1.0
@export var inactive_player_opacity: float = 0.4
@export var opacity_transition_duration: float = 0.3

# --- Action icon pop tuning ---
@export_group("Action Icon Pop")
@export var action_pop_scale: float = 1.35
@export var action_pop_rotation_degrees: float = 12.0
@export var action_pop_grow_time: float = 0.09
@export var action_pop_settle_time: float = 0.2

@export_group("Misc")
# If false, action icons will be visually unfilled at game/round start even if counts are full
@export var fill_icons_on_start: bool = false
@export var end_of_actions_delay: float = 2.0

# Particle used for opponent pass feedback (optional: set in Inspector)
@export_group("Pass Effect")
@export var pass_particle_texture: Texture2D
@export var pass_particle_amount: int = 28
@export var pass_particle_lifetime: float = 0.9
@export var pass_particle_speed: float = 260.0
@export var pass_particle_spread_degrees: float = 180.0
@export var pass_particle_gravity: Vector3 = Vector3(0, 98, 0)
@export var pass_particle_scale_min: float = 0.1
@export var pass_particle_scale_max: float = 0.3
@export var pass_particle_color: Color = Color.WHITE

func _ready() -> void:
	# Robust GameManager lookup: try common locations (autoload path, scene path, parent),
	# then fall back to a scene-wide find. If still not found, defer and retry once.
	# This avoids hard failing when registration order varies between autoloads and scene nodes.
	var gm: Node = null

	# 1) Autoload singleton (most reliable when GameManager is an autoload)
	gm = get_node_or_null("/root/GameManager")
	# 2) Main scene Managers container (common when GameManager is a child of the main scene)
	if not gm:
		gm = get_node_or_null("/root/main/Managers/GameManager")
	# 3) Parent container lookup (if this TurnManager is a sibling under a Managers node)
	if not gm:
		var manager_container = get_parent()
		if manager_container:
			gm = manager_container.get_node_or_null("GameManager")
	# 4) Scene-wide search as a last resort
	if not gm:
		var current_scene = get_tree().get_current_scene()
		if current_scene:
			gm = current_scene.find_node("GameManager", true, false)

	if not gm:
		# Defer one retry to give the scene/autoload ordering a chance to resolve
		push_warning("TurnManager: GameManager not found during _ready; deferring lookup and retrying shortly.")
		call_deferred("_deferred_gm_lookup")
		return

	# Store found GameManager and finish initialization
	game_manager = gm
	_finish_initialization()

## Called by RoundManager or GameManager to start turn management
func start_turn_management(starting_player: int) -> void:
	# Called by RoundManager or GameManager to start turn management
	current_player = starting_player
	# Consider PLAYER_ONE (0) as the local player
	is_player_turn = (current_player == 0)

	# Reset per-round 'had turn' flags when beginning turn management (new round)
	player_had_turn = false
	opponent_had_turn = false

	# Give actions only to the active player: active gets full pool, inactive gets 0
	if is_player_turn:
		player_actions_remaining = actions_per_turn
		opponent_actions_remaining = 0
	else:
		player_actions_remaining = 0
		opponent_actions_remaining = actions_per_turn

	# Update UI and action displays
	_update_ui_opacity()
	_update_action_ui()


## Deferred lookup helper for GameManager (called if initial lookup failed)
func _deferred_gm_lookup() -> void:
	# Try the same resolution again but after the scene has had a chance to finish loading
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
		push_error("TurnManager: GameManager not found after deferred lookup. Certain features will be disabled.")
		return

	game_manager = gm
	_finish_initialization()


func _finish_initialization() -> void:
	# Try to obtain other managers from GameManager
	if game_manager and game_manager.has_method("get_manager"):
		ui_manager = game_manager.get_manager("UIManager")
		card_manager = game_manager.get_manager("CardManager")

	# If we have a GameManager with a register method, register ourselves
	if game_manager and game_manager.has_method("register_manager"):
		game_manager.register_manager("TurnManager", self)

	# Log warnings if critical refs are still missing (non-fatal)
	if not game_manager:
		push_error("TurnManager: GameManager not found (autoload or parent).")
	if not ui_manager:
		# UIManager may register later; it's non-fatal
		push_warning("TurnManager: UIManager not resolved on init; will attempt later lookups.")
	# Resolve CardManager proactively (try several common locations)
	_resolve_card_manager()

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


## --- Late-resolution helpers ---
func _resolve_card_manager() -> void:
	# Try registration via GameManager first
	if game_manager and game_manager.has_method("get_manager"):
		card_manager = game_manager.get_manager("CardManager")

	# Fallback scene lookups
	if not card_manager:
		card_manager = get_node_or_null("/root/main/Parallax/CardManager")
	if not card_manager:
		card_manager = get_node_or_null("/root/main/Managers/CardManager")

	# If still not found, schedule a deferred retry to reduce warning spam
	if not card_manager:
		call_deferred("_deferred_card_manager_lookup")


func _deferred_card_manager_lookup() -> void:
	# One more attempt after the scene has fully initialized
	if game_manager and game_manager.has_method("get_manager"):
		card_manager = game_manager.get_manager("CardManager")
	if not card_manager:
		card_manager = get_node_or_null("/root/main/Parallax/CardManager")
	if not card_manager:
		card_manager = get_node_or_null("/root/main/Managers/CardManager")
	if not card_manager:
		push_warning("TurnManager: CardManager still not found after deferred lookup; some features may be disabled.")

## Switch to the next player's turn
func next_turn() -> void:
	# Switch player
	# Record that the previous player has completed their turn
	var prev_player = current_player
	if prev_player == 0:
		player_had_turn = true
	else:
		opponent_had_turn = true

	# Toggle between 0 (PLAYER_ONE) and 1 (PLAYER_TWO)
	current_player = 1 if current_player == 0 else 0
	is_player_turn = (current_player == 0)
	
	# print("TurnManager: Switched to player", current_player, "turn")
	
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
	# If it's the opponent's turn, notify AIManager (if present)
	if not is_player_turn:
		# Show overlay and wait for it to finish before proceeding with AI action
		var ai_mgr = null
		if game_manager and game_manager.has_method("get_manager"):
			ai_mgr = game_manager.get_manager("AIManager")
		if not ai_mgr:
			ai_mgr = get_node_or_null("/root/main/Managers/AIManager")
		# If we have a UIManager overlay, show it and wait for completion before acting
		if ui_manager and ui_manager.has_method("show_turn_message"):
			ui_manager.show_turn_message(false)
			# Wait for UIManager signal if available, otherwise fallback to the configured delay
			if ui_manager.has_signal("turn_message_finished"):
				# Connect a one-shot handler that continues the flow when the overlay finishes.
				_deferred_ai_mgr = ai_mgr
				# Use Callable-based connect for compatibility with project patterns
				if not ui_manager.is_connected("turn_message_finished", Callable(self, "_on_turn_message_finished")):
					ui_manager.connect("turn_message_finished", Callable(self, "_on_turn_message_finished"))
			else:
				# fallback: schedule delayed continuation after end_of_actions_delay
				_deferred_ai_mgr = ai_mgr
				_call_delayed_post_overlay(end_of_actions_delay)
		# If no UI overlay, proceed immediately (but still call AI)
		if not ui_manager or not ui_manager.has_signal("turn_message_finished"):
			# If we scheduled a delayed continuation above, it will call AI; otherwise call now
			if not _deferred_ai_mgr:
				if ai_mgr and ai_mgr.has_method("on_ai_turn"):
					ai_mgr.on_ai_turn()
	# TODO: Add turn-based logic here (card play restrictions, etc.)

## Update UI opacity based on whose turn it is
func _update_ui_opacity() -> void:
	pass
	# print("TurnManager: Updating UI opacity - Player turn:", is_player_turn)

	# Decide opacities for each side
	var player_opacity = active_player_opacity if is_player_turn else inactive_player_opacity
	var opponent_opacity = active_player_opacity if not is_player_turn else inactive_player_opacity

	# Also inform UIManager (if present) for immediate effect
	if ui_manager and ui_manager.has_method("set_active_player"):
		pass
		# print("TurnManager: calling ui_manager.set_active_player(", is_player_turn, ")")
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

	# Additionally, ensure the opponent's pass button is not interactive for the player
	# Find the opponent pass button and disable input when it's the player's turn
	var opp_pass_button = get_node_or_null("/root/main/FrontLayerUI/UIPanel/PanelBG/VBoxContainer/TurnEconomy/OpponentUI/PassButton")
	if opp_pass_button:
		# If it's the player's turn, prevent hovering/clicking the opponent's pass button
		if is_player_turn:
			# For Control nodes, set mouse_filter to ignore and disabled if present
			if opp_pass_button is Control:
				opp_pass_button.mouse_filter = Control.MOUSE_FILTER_IGNORE
				if "disabled" in opp_pass_button:
					opp_pass_button.disabled = true
			else:
				# For Node2D fallbacks, set visible=false for its input area or disable signals as needed
				# We'll leave visual intact; just avoid user interactions
				if opp_pass_button.has_method("set_pickable"):
					opp_pass_button.set_pickable(false)
		else:
			# When it's not the player's turn, restore interactivity so AI effects still animate
			if opp_pass_button is Control:
				opp_pass_button.mouse_filter = Control.MOUSE_FILTER_PASS
				if "disabled" in opp_pass_button:
					opp_pass_button.disabled = false
			else:
				if opp_pass_button.has_method("set_pickable"):
					opp_pass_button.set_pickable(true)

	# print("TurnManager: action UI updated -> player_actions_remaining:", player_actions_remaining, "opponent_actions_remaining:", opponent_actions_remaining, "is_player_turn:", is_player_turn)

## Set action icons and label for a side
func _set_action_ui(side_name: String, remaining: int, total: int) -> void:
	pass
	# print("TurnManager: _set_action_ui called for", side_name, "remaining:", remaining, "total:", total)
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
		var _label_path = "<unknown>"
		if actions_label.has_method("get_path"):
			_label_path = str(actions_label.get_path())
		# print("TurnManager: found actions_label for", side_name, "->", actions_label, "path:", label_path)

		# If there are no actions configured for this mode, hide the label text
		if total <= 0:
			if actions_label.has_method("set_text"):
				actions_label.set_text("")
			else:
				actions_label.text = ""
			# print("TurnManager: actions_per_turn is 0, hiding actions label for", side_name)
		else:
			var new_text = "%d/%d" % [remaining, total]
			# Prefer calling set_text if present, else set property
			if actions_label.has_method("set_text"):
				actions_label.set_text(new_text)
			else:
				actions_label.text = new_text
			# print("TurnManager: Updated actions_label (", side_name, ") to:", new_text)
	else:
		pass
		# print("TurnManager: No actions_label found for", side_name)

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


## Move a visible card to the center of the screen (used after overlays/turn messages)
func _move_card_to_center() -> void:
	# Try to locate a card to move. Prefer opponent cards, then any card in CardManager children.
	var card_node: Node = null
	if card_manager:
		for c in card_manager.get_children():
			if not c:
				continue
			if "is_player_card" in c:
				if not c.is_player_card:
					card_node = c
					break
			else:
				# pick first child if no flag present
				card_node = c
				break

	# Fallback scene search
	if not card_node:
		var scene_cards = get_tree().get_nodes_in_group("cards")
		for c in scene_cards:
			if not c:
				continue
			if "is_player_card" in c and not c.is_player_card:
				card_node = c
				break
		if not card_node and scene_cards.size() > 0:
			card_node = scene_cards[0]

	if not card_node:
		return

	# Compute center of the visible viewport in global coordinates
	var vp_rect = get_viewport().get_visible_rect()
	var center = vp_rect.position + vp_rect.size * 0.5

	# Tween the card's global_position to the center
	if card_node and card_node is Node2D:
		var t = create_tween()
		t.tween_property(card_node, "global_position", center, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


## Called when UIManager emits turn_message_finished
func _on_turn_message_finished() -> void:
	# Disconnect to keep it one-shot
	if ui_manager and ui_manager.is_connected("turn_message_finished", Callable(self, "_on_turn_message_finished")):
		ui_manager.disconnect("turn_message_finished", Callable(self, "_on_turn_message_finished"))
	_call_delayed_post_overlay(0.3)


func _call_delayed_post_overlay(delay: float) -> void:
	# Wait 'delay' seconds, then move a card and notify AI (if deferred)
	# Use a tween-based timer to avoid await/yield compatibility issues
	var t = create_tween()
	t.tween_interval(delay)
	t.tween_callback(func():
		_move_card_to_center()
		if _deferred_ai_mgr and _deferred_ai_mgr.has_method("on_ai_turn"):
			_deferred_ai_mgr.on_ai_turn()
		_deferred_ai_mgr = null
	)

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
			pass
			# print("TurnManager: player attempted to play with no actions remaining")
	else:
		if opponent_actions_remaining > 0:
			opponent_actions_remaining -= 1
			_pop_action_icon_for_side("OpponentUI", opponent_actions_remaining)
			# If opponent just used their last action, schedule turn transition
			if opponent_actions_remaining == 0:
				_schedule_turn_transition(end_of_actions_delay)
		else:
			pass
			# print("TurnManager: opponent attempted to play with no actions remaining")

	_update_action_ui()

func pass_current_player() -> void:
	if is_player_turn:
		player_actions_remaining = 0
		player_had_turn = true
	else:
		opponent_actions_remaining = 0
		opponent_had_turn = true
		_trigger_opponent_pass_effects()

	_update_action_ui()

	if player_had_turn and opponent_had_turn:
		var gm = get_node_or_null("/root/main/Managers/GameManager")
		if not gm:
			push_error("TurnManager: GameManager not found at /root/main/Managers/GameManager")
			return
		if gm and gm.has_method("set_game_state"):
			await get_tree().create_timer(end_round_delay_after_pass).timeout
			gm.set_game_state(gm.GameState.ROUND_END)
			return

	_schedule_turn_transition(end_of_actions_delay)

func _trigger_opponent_pass_effects() -> void:
	# Trigger visual feedback for opponent's pass button
	var pass_button = get_node_or_null("/root/main/FrontLayerUI/UIPanel/PanelBG/VBoxContainer/TurnEconomy/OpponentUI/PassButton")
	if pass_button:
		# Animate button press with a dark flash
		var tween = create_tween()
		tween.tween_property(pass_button, "modulate", Color.GRAY, 0.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tween.tween_property(pass_button, "modulate", Color.WHITE, 0.2).set_delay(0.1)

		# Spawn a one-shot GPUParticles2D burst centered on the pass button
		var center_pos = Vector2.ZERO
		if pass_button is Control and pass_button.has_method("get_global_rect"):
			var gr = pass_button.get_global_rect()
			center_pos = gr.position + gr.size * 0.5
		elif "global_position" in pass_button:
			center_pos = pass_button.global_position
		else:
			if "rect_global_position" in pass_button and "rect_size" in pass_button:
				center_pos = pass_button.rect_global_position + pass_button.rect_size * 0.5

		var particles = GPUParticles2D.new()
		particles.one_shot = true
		particles.amount = pass_particle_amount
		particles.lifetime = pass_particle_lifetime
		particles.emitting = true

		# Configure a basic ProcessMaterial for velocity/angle
		var pm = ParticleProcessMaterial.new()
		pm.direction = Vector3(0, -1, 0)
		pm.spread = deg_to_rad(pass_particle_spread_degrees)
		pm.initial_velocity_min = pass_particle_speed
		pm.initial_velocity_max = pass_particle_speed
		pm.gravity = pass_particle_gravity
		pm.scale_min = pass_particle_scale_min
		pm.scale_max = pass_particle_scale_max
		pm.color = pass_particle_color
		particles.process_material = pm

		if pass_particle_texture:
			particles.texture = pass_particle_texture

		particles.position = center_pos
		
		var front_layer = get_node_or_null("/root/main/FrontLayerUI")
		if front_layer:
			front_layer.add_child(particles)
		else:
			add_child(particles)

		var free_delay = pass_particle_lifetime + 0.2
		var particle_timer = get_tree().create_timer(free_delay)
		await particle_timer.timeout
		if is_instance_valid(particles):
			particles.queue_free()

	var info_manager = get_node_or_null("/root/main/Managers/InfoScreenManager")
	if info_manager and info_manager.has_method("show_opponent_pass_commentary"):
		info_manager.show_opponent_pass_commentary()
		if info_manager.has_signal("typing_finished"):
			await info_manager.typing_finished
			await get_tree().create_timer(1.0).timeout

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
			pass
			# print("TurnManager: Found %s via UIManager" % side_name)

	# Preferred scene location (current layout)
	if not panel:
		var base_path = "/root/main/FrontLayerUI/UIPanel/PanelBG/VBoxContainer/TurnEconomy/"
		panel = get_node_or_null(base_path + side_name)
		if panel:
			pass
			# print("TurnManager: Found %s at %s" % [side_name, base_path + side_name])
	# Legacy fallback
	if not panel:
		var legacy_base = "/root/main/PanelBG/VBoxContainer/TurnEconomy/"
		panel = get_node_or_null(legacy_base + side_name)
		if panel:
			pass
			# print("TurnManager: Found %s at %s" % [side_name, legacy_base + side_name])

	if not panel:
		pass
		# print("TurnManager: Could not find %s in any known location" % side_name)
		return

	# print("TurnManager: Setting %s opacity to" % side_name, opacity)
	_animate_ui_opacity(panel, opacity)

	# Also try to dim any action icons (ColorRect children with ShaderMaterial) under an ActionIcons container
	_adjust_action_icons(panel, opacity_transition_duration)

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

func _handle_opponent_action() -> void:
	if opponent_actions_remaining == 1:
		# Automatically pass as the second action
		pass_current_player()
	else:
		# Perform the opponent's first action (e.g., play a card or other logic)
		opponent_actions_remaining -= 1
		_update_action_ui()

		# Simulate opponent playing a card effect: show a message while the effect
		# plays for 3s, then begin the discard sequence. After discard completes
		# and/or the message period finishes, wait 1s and then end the AI turn.
		var info_manager = get_node_or_null("/root/main/Managers/InfoScreenManager")
		if info_manager and info_manager.has_method("set_text"):
			info_manager.set_text("Opponent is playing...")

		# Simulated effect duration (configurable)
		if play_effect_delay > 0.0:
			await get_tree().create_timer(play_effect_delay).timeout

		# Request the engine to mark the opponent's phase complete. The TurnManager
		# should not unilaterally set the game state to ROUND_END; instead we mark
		# the opponent as finished and let the GameManager/RoundManager decide
		# whether the round should end.
		complete_opponent_phase()

		# Wait for discard_hands to complete if RoundManager exposes it (best-effort)
		var round_mgr = null
		var gm = get_node_or_null("/root/main/Managers/GameManager")
		if not gm:
			push_error("TurnManager: GameManager not found at /root/main/Managers/GameManager")
			return
		if gm and gm.has_method("get_manager"):
			round_mgr = gm.get_manager("RoundManager")
		if not round_mgr:
			round_mgr = get_node_or_null("/root/main/Managers/RoundManager")
		if round_mgr and round_mgr.has_method("discard_hands"):
			# If discard is already in progress this will await its completion
			await round_mgr.discard_hands()

		# Wait an extra delay (configurable) after discard/message before ending the AI turn
		if post_phase_delay > 0.0:
			await get_tree().create_timer(post_phase_delay).timeout

		# End AI turn by advancing to the next turn (player's turn)
		next_turn()


## Mark opponent phase complete and ask the GameManager to end the round if both sides have acted.
func complete_opponent_phase() -> void:
	opponent_had_turn = true
	# If both had their turns, request a round end; otherwise no action here.
	if player_had_turn and opponent_had_turn:
		var gm = get_node_or_null("/root/main/Managers/GameManager")
		if not gm:
			push_error("TurnManager: GameManager not found at /root/main/Managers/GameManager")
			return
		if gm and gm.has_method("set_game_state"):
			gm.set_game_state(gm.GameState.ROUND_END)
