extends Button

@onready var card_face = $CardFace
@onready var card_icon = $CardFace/Icon
@onready var value_label = $CardFace/ValueLabel
@onready var value_label2 = $CardFace/ValueLabel2
@onready var suit_label = $CardFace/SuitLabel
@onready var suit_label2 = $CardFace/SuitLabel2
@onready var background = $CardFace/Background

func set_card_data(data_name: String) -> void:
	var card_data_loader = get_node_or_null("/root/CardDataLoader")
	if not card_data_loader:
		push_error("[Card] ERROR: CardDataLoader not found!")
		return
	
	var data = card_data_loader.get_card_data(data_name)
	if data.is_empty():
		push_error("[Card] ERROR: No data found for: %s" % data_name)
		return
	
	# Applying card data silently
	
	if data.has("icon_path"):
		var texture = load("res://Assets/CardFramework/" + data["icon_path"])
		if texture:
			card_icon.texture = texture
	
	if data.has("value"):
		value_label.text = data["value"]
		value_label2.text = data["value"]
	
	if data.has("suit"):
		suit_label.text = data["suit"]
		suit_label2.text = data["suit"]
	
	# Set the shader colors if all three exist in the data
	if background.material and data.has("color_a") and data.has("color_b") and data.has("color_c"):
		background.material = background.material.duplicate()
		var color_a = Color(data["color_a"][0], data["color_a"][1], data["color_a"][2], data["color_a"][3])
		var color_b = Color(data["color_b"][0], data["color_b"][1], data["color_b"][2], data["color_b"][3])
		var color_c = Color(data["color_c"][0], data["color_c"][1], data["color_c"][2], data["color_c"][3])
		# Shader uses color_light, color_mid, color_dark parameter names
		background.material.set_shader_parameter("color_mid", color_a)
		background.material.set_shader_parameter("color_light", color_b)
		background.material.set_shader_parameter("color_dark", color_c)
