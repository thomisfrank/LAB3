extends Node

@export var move_offset: Vector2 = Vector2(150, 0)
@export var lift_height: float = 80.0
@export var lift_duration: float = 0.3
@export var rotate_duration: float = 0.3
@export var move_duration: float = 0.6

var game_manager: Node = null
var card_manager: Node = null


func _ready() -> void:
	game_manager = get_node_or_null("/root/GameManager")
	if game_manager and game_manager.has_method("register_manager"):
		game_manager.register_manager("AIManager", self)


func _resolve_card_manager() -> void:
	if game_manager and game_manager.has_method("get_manager"):
		card_manager = game_manager.get_manager("CardManager")
	if not card_manager:
		card_manager = get_node_or_null("/root/main/Parallax/CardManager")
	if not card_manager:
		card_manager = get_node_or_null("/root/main/Managers/CardManager")


func on_ai_turn() -> void:
	_resolve_card_manager()
	if not card_manager:
		push_error("AIManager: CardManager not found; cannot move card.")
		return

	var card_node = null
	for c in card_manager.get_children():
		if c and "is_player_card" in c and not c.is_player_card:
			card_node = c
			break
	if not card_node:
		return

	var main_node = get_node_or_null("/root/main")
	if main_node and card_node.get_parent() != main_node:
		card_node.reparent(main_node)

	var vp_rect = get_viewport().get_visible_rect()
	var target_position = vp_rect.position + vp_rect.size * 0.5 + move_offset

	# PHASE 1: Lift and Rotate
	var start_position = card_node.global_position
	var lifted_position = start_position + Vector2(0, -lift_height)
	var target_rotation = 0  # Change if you want a specific angle, e.g. deg_to_rad(15)

	var t = create_tween()

	# Lift
	t.tween_property(card_node, "global_position", lifted_position, lift_duration)\
		.set_trans(Tween.TRANS_SINE)\
		.set_ease(Tween.EASE_OUT)

	# Rotate (at the same time as lift)
	t.parallel().tween_property(card_node, "rotation", target_rotation, rotate_duration)\
		.set_trans(Tween.TRANS_SINE)\
		.set_ease(Tween.EASE_IN_OUT)

	# PHASE 2: Arc Move after the lift finishes
	t.tween_callback(func ():
		_move_card_in_arc(card_node, lifted_position, target_position)
	)


func _move_card_in_arc(card_node: Node2D, start: Vector2, target: Vector2) -> void:
	var control_point = (start + target) / 2 + Vector2(0, -150)  # curve upward
	var t = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)

	# Flip the card about 1/3 of the way through the arc
	var flip_delay = move_duration * 0.33
	t.tween_callback(func():
		if card_node.has_method("flip_card"):
			card_node.flip_card()
	).set_delay(flip_delay)

	# Animate along an arc using a custom callback
	t.parallel().tween_method(func(progress):
		var p1 = start.lerp(control_point, progress)
		var p2 = control_point.lerp(target, progress)
		card_node.global_position = p1.lerp(p2, progress)
	, 0.0, 1.0, move_duration)
