extends Area2D

@export var disintegration_shader: Shader

@export_category("Fade Animation")
@export_range(0.0, 1.0) var fade_in_alpha: float = 0.4  # Target alpha when card is dragging
# Hand repositioning removed - cards stay in their original positions
@export_range(0.0, 1.0) var fade_out_alpha: float = 0.0  # Target alpha when no drag
@export_range(0.1, 2.0) var fade_in_duration: float = 0.3  # How long fade-in takes
@export_range(0.1, 2.0) var fade_out_duration: float = 0.3  # How long fade-out takes
@export var fade_in_ease: Tween.EaseType = Tween.EASE_OUT
@export var fade_in_trans: Tween.TransitionType = Tween.TRANS_SINE
@export var fade_out_ease: Tween.EaseType = Tween.EASE_IN
@export var fade_out_trans: Tween.TransitionType = Tween.TRANS_SINE

@onready var visual: ColorRect = $Drop  # Reference to the visual ColorRect child

var is_card_dragging: bool = false


@export_category("Shader Animation")
@export_range(0.0, 1.0) var shader_target_progress: float = 1.0
@export_range(0.0, 1.0) var shader_start_progress: float = 0.0
@export_range(0.05, 5.0) var shader_tween_duration: float = 1.5
@export var shader_tween_ease: Tween.EaseType = Tween.EASE_IN
@export var shader_tween_trans: Tween.TransitionType = Tween.TRANS_SINE

@export_category("Shader Params")
@export_range(2, 200) var shader_pixel_amount: int = 50
@export_range(0.0, 0.5) var shader_edge_width: float = 0.04
@export var shader_edge_color: Color = Color(1.5, 1.5, 1.5, 1.0)

func _ready():
	# Don't use area_entered for drop detection anymore
	# We'll use a manual check when cards are released
	
	# Start with the drop zone invisible
	if visual:
		visual.modulate.a = fade_out_alpha
	
	# Add to drop_zones group so cards can find us
	add_to_group("drop_zones")

func _process(_delta: float) -> void:
	# Check if any card is currently being dragged
	var any_card_dragging = false
	for card in get_tree().get_nodes_in_group("cards"):
		# Check if the card or its parent has an is_dragging property
		var check_node = card
		if card.get_parent() and card.get_parent().has_method("get"):
			check_node = card.get_parent()
		
		if check_node.get("is_dragging") == true:
			any_card_dragging = true
			break
	
	# Fade in/out based on drag state
	if any_card_dragging and not is_card_dragging:
		is_card_dragging = true
		_fade_in()
	elif not any_card_dragging and is_card_dragging:
		is_card_dragging = false
		_fade_out()

func _fade_in() -> void:
	if visual:
		var tween = create_tween()
		tween.tween_property(visual, "modulate:a", fade_in_alpha, fade_in_duration).set_ease(fade_in_ease).set_trans(fade_in_trans)

func _fade_out() -> void:
	if visual:
		var tween = create_tween()
		tween.tween_property(visual, "modulate:a", fade_out_alpha, fade_out_duration).set_ease(fade_out_ease).set_trans(fade_out_trans)

# Called by cards when they're released to check if they're over this zone
func contains_global_position(pos: Vector2) -> bool:
	var cs = $CollisionShape2D
	if not cs or not cs.shape:
		return false
	
	var rect_shape = cs.shape as RectangleShape2D
	if rect_shape:
		var local_pos = to_local(pos)
		var size = rect_shape.size
		var rect = Rect2(-size * 0.5, size)
		return rect.has_point(local_pos + cs.position)
	return false

# Called by cards when dropped in this zone
func on_card_dropped(card_node: Node, snap: bool = true, _disintegrate: bool = true) -> void:
	# Remove the card from CardManager (hand) before resolving the effect or discarding
	var card_parent = card_node.get_parent()
	if card_parent and card_parent.name == "CardManager":
		card_parent.remove_child(card_node)
		# Optionally, reparent to the scene root for animation/disintegration
		var scene_root = get_tree().get_current_scene()
		if scene_root:
			scene_root.add_child(card_node)
		# Relayout the hand immediately after removing the card
		var card_manager = get_node_or_null("/root/main/Parallax/CardManager")
		if card_manager and card_manager.has_method("relayout_hand"):
			card_manager.relayout_hand(true)
	# Handle a card being dropped in this zone.
	# snap: if true, reposition the card to the DropZone center; if false, leave it where it is.
	# disintegrate: if true, immediately start the disintegration sequence; if false, skip it.
	# --- Optional snap-to-center ---
	if snap:
		# Move the card to the center of the drop zone's CollisionShape2D for perfect alignment.
		card_node.global_position = $CollisionShape2D.global_position
	else:
		# If not snapping, only accept the drop if the card is currently within our collision shape
		if not contains_global_position(card_node.global_position):
			# Card was not dropped inside this zone; ignore
			return

	# Don't change rotation - let cards keep their current orientation (upside-down for opponent, upright for player)

	# --- NEW LOGIC: Check the effect type BEFORE discarding ---
	var effect_type: String = ""
	if "card_data" in card_node and card_node.card_data:
		effect_type = card_node.card_data.get("effect_type", "")

	# 1. Effect resolution timing:
	# Some effects (like 'swap' or 'peek') need to run before the card is discarded,
	# but draw-type effects should happen after the played card is removed so a
	# hand slot is freed. We'll choose to defer draw effects until after discard.

	# Robust GameManager lookup: support autoload (/root/GameManager), scene path, parent, and scene-wide find
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
			if current_scene.has_method("find_node"):
				gm = current_scene.find_node("GameManager", true, false)
			else:
				gm = _recursive_find_by_name(current_scene, "GameManager")

	if not gm:
		# Don't hard-fail here; GameManager may be an autoload or register later.
		push_warning("DropZone: GameManager not found at expected locations; attempting manager fallbacks.")

	# Try to get the EffectManager via GameManager first, otherwise try scene fallbacks
	var em: Node = null
	if gm and gm.has_method("get_manager"):
		em = gm.get_manager("EffectManager")
	if not em:
		# Fallback: try scene paths directly
		em = get_node_or_null("/root/main/Managers/EffectManager")
	if not em and get_tree().get_current_scene():
		var current_scene = get_tree().get_current_scene()
		if current_scene:
			if current_scene.has_method("find_node"):
				em = current_scene.find_node("EffectManager", true, false)
			else:
				em = _recursive_find_by_name(current_scene, "EffectManager")

	var handled_draw = false
	if em and em.has_method("resolve_effect") and is_instance_valid(card_node) and "card_data" in card_node and card_node.card_data:
		if effect_type == "draw":
			# For draw, resolve the effect first, then discard the played card
			em.resolve_effect(card_node)
			handled_draw = true
		else:
			em.resolve_effect(card_node)
	else:
		# ...existing code for fallback effect manager lookup...
		var scene_root = get_tree().get_current_scene()
		if scene_root:
			var mgrs = scene_root.get_node_or_null("Managers")
			if mgrs:
				for child in mgrs.get_children():
					if child and child.get_script():
						var spath = str(child.get_script().resource_path)
						if spath.find("EffectsManager.gd") != -1 or spath.find("EffectManager.gd") != -1:
							em = child
							break
		if em and em.has_method("resolve_effect"):
			em.resolve_effect(card_node)
		else:
			push_warning("DropZone: EffectManager not found; skipping effect resolution")

	# 2. Only discard/disintegrate if it's NOT a swap, peek_deck, or peek_hand effect.
	if effect_type != "swap" and effect_type != "peek_deck" and effect_type != "peek_hand":
		card_node.z_index = 0
		if _disintegrate and card_node.has_method("apply_disintegration"):
			card_node.apply_disintegration(disintegration_shader, shader_start_progress, shader_target_progress, shader_tween_duration, shader_tween_ease, shader_tween_trans)
		else:
			pass

	# --- existing code to notify TurnManager ---

	var tm: Node = null
	# Prefer GameManager.get_manager, but fall back to scene lookups
	if gm and gm.has_method("get_manager"):
		tm = gm.get_manager("TurnManager")
	if not tm:
		tm = get_node_or_null("/root/main/Managers/TurnManager")
	if not tm:
		tm = get_node_or_null("/root/main/TurnManager")
	if not tm and get_tree().get_current_scene():
		var current_scene = get_tree().get_current_scene()
		if current_scene:
			if current_scene.has_method("find_node"):
				tm = current_scene.find_node("TurnManager", true, false)
			else:
				tm = _recursive_find_by_name(current_scene, "TurnManager")
	if not tm:
		push_warning("DropZone: TurnManager not found; cannot record action_played")
		return
	if tm and tm.has_method("record_action_played"):
		# For some effects that require additional player interaction (selection/swap),
		# we should NOT immediately record the action here. Those effects will call
		# TurnManager.record_action_played when they fully complete. This prevents
		# the turn from advancing while the player is still making a choice.
		var non_instant_effects = ["peek_hand", "swap"]
		if effect_type in non_instant_effects:
			# Skip immediate recording; effect handler will record when done.
			return

		# Determine ownership via card property if available
		var is_player_card = true
		if is_instance_valid(card_node):
			if card_node.has_method("get") and "is_player_card" in card_node:
				is_player_card = card_node.is_player_card
		# Record the action (effects may run before or after this depending on design)
		tm.record_action_played(is_player_card)
	else:
		push_error("DropZone: TurnManager does not expose record_action_played")
		return


## Helper: recursively search children for a node with the given name.
## This avoids calling find_node on nodes that may not implement it.
func _recursive_find_by_name(root: Node, target_name: String) -> Node:
	if not root:
		return null
	if root.name == target_name:
		return root
	for child in root.get_children():
		if child and child is Node:
			var found = _recursive_find_by_name(child, target_name)
			if found:
				return found
	return null
