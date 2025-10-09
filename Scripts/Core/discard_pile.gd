extends Node2D

# Adjust these values in the Inspector to change how messy the pile is
@export_range(-45, 45, 0.1) var rotation_range_degrees: float = 15.0
@export var position_offset_range_pixels: Vector2 = Vector2(10, 10)

# Wiggle settings
@export_group("Wiggle Effect")
@export_category("Pop Animation")
@export_range(0.1, 2.0) var pop_start_scale: float = 0.5
@export_range(1.0, 2.0) var pop_overshoot_scale: float = 1.2
@export_range(0.05, 0.5) var pop_scale_up_duration: float = 0.2
@export_range(0.05, 0.5) var pop_scale_settle_duration: float = 0.15
@export var pop_scale_ease: Tween.EaseType = Tween.EASE_OUT
@export var pop_scale_trans: Tween.TransitionType = Tween.TRANS_BACK

@export_category("Flash Animation")
@export_range(1.0, 5.0) var flash_brightness: float = 3.0
@export_range(1.0, 4.0) var flash_mid_brightness: float = 2.5
@export_range(0.01, 0.3) var flash_initial_duration: float = 0.08
@export_range(0.1, 0.5) var flash_fade_duration: float = 0.25
@export var flash_ease: Tween.EaseType = Tween.EASE_IN_OUT

@export_category("Wiggle Animation")
@export var wiggle_enabled: bool = true
@export var wiggle_offset: Vector2 = Vector2(8, 3)
@export_range(0.1, 1.0) var wiggle_duration: float = 0.29


func add_card(card: Node) -> void:
	"""Add a card to the discard pile with polish effects."""
	if not is_instance_valid(card):
		print("DiscardPile: Card is not valid.")
		return
	
	if not card.is_inside_tree():
		print("DiscardPile: Card is not in the scene tree.")
		return

	# Remove the card from its current parent
	var old_parent = card.get_parent()
	if old_parent:
		old_parent.remove_child(card)

	# Add the card to the discard pile
	add_child(card)
	
	# Lock down the card - disable all interactions
	if card.has_method("set_process"):
		card.set_process(false)
	if card.has_method("set_process_input"):
		card.set_process_input(false)
	if card.has_method("set"):
		card.set("is_mouse_over", false)
		card.set("is_dragging", false)
	# Disable mouse filter on the display container to prevent hover
	if card.has_node("Visuals/CardViewport"):
		var display_container = card.get_node("Visuals/CardViewport")
		display_container.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Randomize Rotation
	var random_rotation = randf_range(-rotation_range_degrees, rotation_range_degrees)
	card.rotation_degrees = random_rotation

	# Randomize Position Offset
	var random_offset_x = randf_range(-position_offset_range_pixels.x, position_offset_range_pixels.x)
	var random_offset_y = randf_range(-position_offset_range_pixels.y, position_offset_range_pixels.y)
	card.position = Vector2(random_offset_x, random_offset_y)

	# Pop-up arrival animation with flash
	if card.has_node("Visuals"):
		var visuals = card.get_node("Visuals")
		
		# Reset the display container material (remove disintegration shader)
		if card.has_node("Visuals/CardViewport"):
			var display_container = card.get_node("Visuals/CardViewport")
			display_container.material = null  # Clear the shader
		
		visuals.scale = Vector2(pop_start_scale, pop_start_scale)  # Start small
		visuals.modulate = Color(flash_brightness, flash_brightness, flash_brightness, 0.0)  # Start invisible with bright flash (overbright white)
		
		# Create a tween for the pop-up effect
		var tween = create_tween()
		tween.set_parallel(true)  # Run scale and fade at the same time
		
		# Pop scale: small -> overshoot -> settle
		tween.tween_property(visuals, "scale", Vector2(pop_overshoot_scale, pop_overshoot_scale), pop_scale_up_duration).set_ease(pop_scale_ease).set_trans(pop_scale_trans)
		# Fade in while keeping bright white flash
		tween.tween_property(visuals, "modulate", Color(flash_mid_brightness, flash_mid_brightness, flash_mid_brightness, 1.0), flash_initial_duration).set_ease(Tween.EASE_OUT)
		
		# Then fade from bright white to normal color
		tween.chain().tween_property(visuals, "modulate", Color(1.0, 1.0, 1.0, 1.0), flash_fade_duration).set_ease(flash_ease)
		# Settle scale to normal
		tween.parallel().tween_property(visuals, "scale", Vector2(1.0, 1.0), pop_scale_settle_duration).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	
	# Wiggle the pile
	if wiggle_enabled:
		_wiggle()


func _wiggle() -> void:
	"""Makes the discard pile wiggle when a card is added."""
	# Store original position
	var original_pos = position
	
	# Create a wiggle tween
	var tween = create_tween()
	tween.set_parallel(false)
	
	# Quick shake left-right-left with slight vertical bounce
	var offset_x = wiggle_offset.x
	var offset_y = wiggle_offset.y
	
	tween.tween_property(self, "position", original_pos + Vector2(-offset_x, -offset_y), 0.05).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "position", original_pos + Vector2(offset_x, -offset_y * 0.66), 0.08).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(self, "position", original_pos + Vector2(-offset_x * 0.5, -offset_y * 0.33), 0.06).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(self, "position", original_pos, 0.1).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
