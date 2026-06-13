## PlotData : Resource
## Contains a full parsed plot script with characters, title, and node sequence.
class_name PlotData extends Resource

@export var id: String = ""
@export var title: LocText
@export var characters: Dictionary = {}
@export var nodes: Array[PlotNode] = []


func get_character_name(who: String, language: String) -> String:
	if who.is_empty():
		return ""
	if who == "player":
		return GameManager.player_name if not GameManager.player_name.is_empty() else who
	var char_data: LocText = characters.get(who, null)
	if char_data:
		return char_data.ZH if language == "ZH" else char_data.EN
	return who
