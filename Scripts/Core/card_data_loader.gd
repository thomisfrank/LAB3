extends Node

var card_data_dict: Dictionary = {}

func _ready():
	_load_all_card_data()
	print("[CardDataLoader] Loaded ", card_data_dict.size(), " card types")
	print("[CardDataLoader] Available cards: ", card_data_dict.keys())

func _load_all_card_data():
	var dir = DirAccess.open("res://Scripts/CardData/")
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if file_name.ends_with(".json") and file_name != "Back.json":
				var file_path = "res://Scripts/CardData/" + file_name
				var file = FileAccess.open(file_path, FileAccess.READ)
				if file:
					var json_string = file.get_as_text()
					var json = JSON.new()
					var parse_result = json.parse(json_string)
					if parse_result == OK:
						var data = json.data
						if data.has("name"):
							card_data_dict[data["name"]] = data
					file.close()
			file_name = dir.get_next()
		dir.list_dir_end()

func get_card_data(card_name: String) -> Dictionary:
	return card_data_dict.get(card_name, {})
