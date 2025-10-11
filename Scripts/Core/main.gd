extends Node2D

@export_group("Scene References")
# Path to the Parallax node (set in the Inspector if you move it)
@export var parallax_path: NodePath = NodePath("Parallax")

# How many cards to draw and where to center the hand (editable in the Inspector)
@export var cards_to_draw: int = 5
@export var hand_center_pos: Vector2 = Vector2(600, 500)

@export_group("Discard Pile")
# Drag and drop your DiscardPile node here in the Inspector
@export var discard_pile_node: Node2D

# Adjust these values in the Inspector to change how messy the pile is
@export_range(-45, 45, 0.1) var rotation_range_degrees: float = 15.0
@export var position_offset_range_pixels: Vector2 = Vector2(10, 10)

@onready var parallax_node = get_node_or_null(parallax_path)
@onready var card_manager = null
@onready var deck_node = null

func _init_onready():
	# Helper to resolve onready references which depend on parallax_node
	if parallax_node:
		card_manager = parallax_node.get_node_or_null("CardManager")
		deck_node = parallax_node.get_node_or_null("Deck")

func _ready() -> void:
	# Re-resolve nodes at runtime in case scene tree changed while editing
	if not parallax_node:
		parallax_node = get_node_or_null(parallax_path)
	_init_onready()

func _on_draw_button_pressed():
	if not card_manager:
		push_error("main.gd: CardManager not found under %s" % parallax_path)
		return
	if not deck_node:
		push_error("main.gd: Deck not found under %s" % parallax_path)
		return

	var deck_pos = deck_node.global_position
	card_manager.draw_cards(cards_to_draw, deck_pos, hand_center_pos)


# Call this function when a card is played.
# Pass the card's node to it, and it will be added to the discard pile.
func add_to_discard_pile(card):
	if not is_instance_valid(discard_pile_node):
		pass
		# Discard pile node invalid (suppressed log)
		return
	
	# Delegate to the discard pile's add_card method
	discard_pile_node.add_card(card)

	# After moving a card to discard, relayout both hands to fill gaps
	if parallax_node:
		var cm = parallax_node.get_node_or_null("CardManager")
		if cm and cm.has_method("relayout_hand"):
			cm.relayout_hand(true)  # Relayout player hand
			cm.relayout_hand(false)  # Relayout opponent hand
