extends Button

@export_group("Card Reference")
@export var card_node_path: NodePath  # Assign the InteractiveCard scene in the Inspector.

# This function is connected via the editor's "Node -> Signals" tab.
func _on_pressed() -> void:
	# Get the card node and call its flip function.
	if not card_node_path:
		push_warning("Flip Button: 'card_node_path' is not set.")
		return

	var card = get_node_or_null(card_node_path)
	if card == null:
		push_warning("Flip Button: Could not find node at path: %s" % str(card_node_path))
		return

	if card.has_method("perform_flip"):
		card.perform_flip()
	else:
		# Use the correct method name from our previous conversation.
		if card.has_method("flip_card"):
			card.flip_card()
		else:
			push_warning("Flip Button: Target node does not have a flip_card() method.")