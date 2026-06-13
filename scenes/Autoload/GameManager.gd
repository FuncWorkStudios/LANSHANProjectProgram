## GameManager : Node (Autoload)
## Global singleton for game state, save/load, and settings persistence.
## Replaces the web version's saveService.ts and localStorage.
extends Node

const SAVES_PATH: String = "user://saves.cfg"
const SETTINGS_PATH: String = "user://settings.cfg"
const AUTOSAVE_KEY: String = "autosave"
const MAX_SLOTS: int = 20

var player_name: String = ""
var current_plot_id: String = ""
var current_node_index: int = 0
var terminal_status: String = "locked"
var current_title: String = ""

var _settings: AppSettings
var _saves: Array  # Array[SaveData | null] size MAX_SLOTS
var _save_config: ConfigFile


func _ready() -> void:
	_load_settings()
	_load_saves()


# --- Settings ---

func get_settings() -> AppSettings:
	return _settings


func set_setting(key: String, value: Variant) -> void:
	match key:
		"language":
			_settings.language = value
		"text_speed":
			_settings.text_speed = value
		"master_volume":
			_settings.master_volume = value
		"bgm_volume":
			_settings.bgm_volume = value
		"sfx_volume":
			_settings.sfx_volume = value
		"auto_play":
			_settings.auto_play = value
		"shader_quality":
			_settings.shader_quality = value
		"display_mode":
			_settings.display_mode = value
	_save_settings()
	EventBus.settings_changed.emit(key, value)


func update_settings(new_settings: Dictionary) -> void:
	for key in new_settings:
		set_setting(key, new_settings[key])


func _load_settings() -> void:
	_settings = AppSettings.new().get_default()
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) == OK:
		for key in ["language", "text_speed", "master_volume", "bgm_volume", "sfx_volume", "auto_play", "shader_quality", "display_mode"]:
			if config.has_section_key("settings", key):
				_settings.set(key, config.get_value("settings", key))


func _save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("settings", "language", _settings.language)
	config.set_value("settings", "text_speed", _settings.text_speed)
	config.set_value("settings", "master_volume", _settings.master_volume)
	config.set_value("settings", "bgm_volume", _settings.bgm_volume)
	config.set_value("settings", "sfx_volume", _settings.sfx_volume)
	config.set_value("settings", "auto_play", _settings.auto_play)
	config.set_value("settings", "shader_quality", _settings.shader_quality)
	config.set_value("settings", "display_mode", _settings.display_mode)
	config.save(SETTINGS_PATH)


# --- Save / Load ---

func get_save_slots() -> Array:
	return _saves


func save_game(slot: int, plot_id: String, node_idx: int, pname: String, title: String, desc: String, term_status: String = "locked") -> void:
	if slot < 0 or slot >= MAX_SLOTS:
		return
	var save := SaveData.new()
	save.id = _generate_id()
	save.timestamp = Time.get_unix_time_from_system()
	save.date = Time.get_datetime_string_from_system(false)
	save.title = title
	save.desc = desc.substr(0, min(desc.length(), 50)) + ("..." if desc.length() > 50 else "")
	save.player_name = pname
	save.plot_id = plot_id
	save.node_index = node_idx
	save.terminal_status = term_status
	_saves[slot] = save
	_persist_saves()
	EventBus.game_saved.emit(slot)


func load_game(slot: int) -> SaveData:
	if slot < 0 or slot >= MAX_SLOTS:
		return null
	return _saves[slot]


func set_auto_save(plot_id: String, node_idx: int, pname: String, title: String, desc: String) -> void:
	var save := SaveData.new()
	save.plot_id = plot_id
	save.node_index = node_idx
	save.player_name = pname
	save.title = title
	save.desc = desc
	save.date = Time.get_datetime_string_from_system(false)
	var config := ConfigFile.new()
	config.set_value(AUTOSAVE_KEY, "plot_id", save.plot_id)
	config.set_value(AUTOSAVE_KEY, "node_index", save.node_index)
	config.set_value(AUTOSAVE_KEY, "player_name", save.player_name)
	config.set_value(AUTOSAVE_KEY, "title", save.title)
	config.set_value(AUTOSAVE_KEY, "desc", save.desc)
	config.set_value(AUTOSAVE_KEY, "date", save.date)
	config.save("user://autosave.cfg")


func get_auto_save() -> SaveData:
	var config := ConfigFile.new()
	if config.load("user://autosave.cfg") != OK:
		return null
	var save := SaveData.new()
	save.plot_id = config.get_value(AUTOSAVE_KEY, "plot_id", "")
	save.node_index = config.get_value(AUTOSAVE_KEY, "node_index", 0)
	save.player_name = config.get_value(AUTOSAVE_KEY, "player_name", "")
	save.title = config.get_value(AUTOSAVE_KEY, "title", "")
	save.desc = config.get_value(AUTOSAVE_KEY, "desc", "")
	save.date = config.get_value(AUTOSAVE_KEY, "date", "")
	return save


func _load_saves() -> void:
	_saves = []
	_saves.resize(MAX_SLOTS)
	_save_config = ConfigFile.new()
	if _save_config.load(SAVES_PATH) == OK:
		for i in range(MAX_SLOTS):
			var section := "slot_" + str(i)
			if _save_config.has_section(section):
				var save := SaveData.new()
				save.id = _save_config.get_value(section, "id", "")
				save.timestamp = _save_config.get_value(section, "timestamp", 0)
				save.date = _save_config.get_value(section, "date", "")
				save.title = _save_config.get_value(section, "title", "")
				save.desc = _save_config.get_value(section, "desc", "")
				save.player_name = _save_config.get_value(section, "player_name", "")
				save.plot_id = _save_config.get_value(section, "plot_id", "")
				save.node_index = _save_config.get_value(section, "node_index", 0)
				save.terminal_status = _save_config.get_value(section, "terminal_status", "locked")
				_saves[i] = save


func _persist_saves() -> void:
	var config := ConfigFile.new()
	for i in range(MAX_SLOTS):
		var save: SaveData = _saves[i]
		if save:
			var section := "slot_" + str(i)
			config.set_value(section, "id", save.id)
			config.set_value(section, "timestamp", save.timestamp)
			config.set_value(section, "date", save.date)
			config.set_value(section, "title", save.title)
			config.set_value(section, "desc", save.desc)
			config.set_value(section, "player_name", save.player_name)
			config.set_value(section, "plot_id", save.plot_id)
			config.set_value(section, "node_index", save.node_index)
			config.set_value(section, "terminal_status", save.terminal_status)
	config.save(SAVES_PATH)


func _generate_id() -> String:
	return str(Time.get_unix_time_from_system()) + "_" + str(randi() % 10000)
