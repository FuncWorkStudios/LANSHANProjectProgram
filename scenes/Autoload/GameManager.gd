## GameManager : Node (Autoload)
## Global singleton for game state, save/load, and settings persistence.
## Replaces the web version's saveService.ts and localStorage.
extends Node

const SAVES_PATH: String = "user://saves.cfg"
const SETTINGS_PATH: String = "user://settings.cfg"
const AUTOSAVE_KEY: String = "autosave"
const MAX_SLOTS: int = 20
const BG_ROTATE_INTERVAL: float = 60.0

# Combined pool of all background images available for rotation
const BG_POOL: Array[String] = [
	"res://assets/backgrounds/menu/1.jpg",
	"res://assets/backgrounds/menu/2.jpg",
	"res://assets/backgrounds/menu/3.jpg",
	"res://assets/backgrounds/menu/4.jpg",
	"res://assets/backgrounds/menu/5.jpg",
	"res://assets/backgrounds/menu/6.jpg",
	"res://assets/backgrounds/menu/7.jpg",
	"res://assets/backgrounds/menu/8.jpg",
	"res://assets/backgrounds/menu/9.jpg",
]


# Centralized font paths — load once, use everywhere
const FONT_TCM: String = "res://assets/fonts/TCM_____.TTF"
const FONT_ZH_TITLE: String = "res://assets/fonts/SourceHanSerifCN-SemiBold-7.otf"
const FONT_ZH_BODY: String = "res://assets/fonts/SourceHanSerifCN-Medium-6.otf"
const FONT_ZH_EMPHASIS: String = "res://assets/fonts/simfang.ttf"
const FONT_EN_BODY: String = "res://assets/fonts/times.ttf"
const FONT_EN_EMPHASIS: String = "res://assets/fonts/timesi.ttf"

var player_name: String = ""
var current_plot_id: String = ""
var current_node_index: int = 0
var terminal_status: String = "locked"
var current_title: String = ""
var current_background: String = ""    # shared bg for sub-scenes — mirrors main menu

var _settings: AppSettings
var _saves: Array  # Array[SaveData | null] size MAX_SLOTS
var _save_config: ConfigFile
var _bg_timer: Timer = null
var _bg_last_index: int = -1


func _ready() -> void:
	_load_settings()
	_load_saves()
	_start_bg_rotation()
	_apply_locale()


# ===================================================================
# Background rotation — pick a new background every 60s
# ===================================================================

func _start_bg_rotation() -> void:
	if _bg_timer:
		return
	_bg_timer = Timer.new()
	_bg_timer.name = "BgRotateTimer"
	_bg_timer.wait_time = BG_ROTATE_INTERVAL
	_bg_timer.one_shot = false
	_bg_timer.timeout.connect(_on_bg_rotate)
	add_child(_bg_timer)
	_bg_timer.start()


func _on_bg_rotate() -> void:
	var new_path: String = _pick_different_bg()
	if new_path.is_empty():
		return
	current_background = new_path
	EventBus.shared_background_updated.emit(new_path)


## Pick a random background that differs from the current one.
func _pick_different_bg() -> String:
	if BG_POOL.is_empty():
		return ""
	if BG_POOL.size() == 1:
		return BG_POOL[0]

	var idx: int = randi() % BG_POOL.size()
	# Avoid picking the same image twice in a row
	var attempts: int = 0
	while idx == _bg_last_index and attempts < 10:
		idx = randi() % BG_POOL.size()
		attempts += 1
	_bg_last_index = idx
	return BG_POOL[idx]


# --- Settings ---

func get_settings() -> AppSettings:
	return _settings


func set_setting(key: String, value: Variant) -> void:
	match key:
		"language":
			_settings.language = value
			_apply_locale()
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


# -------------------------------------------------------------------
# Locale — map internal language code to Godot locale and apply
# -------------------------------------------------------------------

# -------------------------------------------------------------------
# Locale framework — extensible to any language
# -------------------------------------------------------------------

## Ordered list of supported locales. Add new languages here.
const SUPPORTED_LOCALES: Array[String] = ["zh", "en"]

## Human-readable labels for each locale (shown in settings UI).
const LOCALE_LABELS: Dictionary = {
	"zh": "简体中文",
	"en": "ENGLISH",
}

func get_locale() -> String:
	return _settings.language.to_lower()

## Check if the active locale matches a given code (prefix match).
func is_locale(code: String) -> bool:
	return TranslationServer.get_locale().begins_with(code)

## Get display text from a locale->text dictionary.
## Falls back through: requested locale -> "en" -> first available value.
func localized(dict: Dictionary) -> String:
	var loc: String = get_locale()
	if dict.has(loc):
		return dict[loc]
	if dict.has("en"):
		return dict["en"]
	for key in dict:
		return dict[key]
	return ""

## Cycle to the next supported locale.
func next_locale() -> String:
	var cur: String = get_locale()
	var idx: int = SUPPORTED_LOCALES.find(cur)
	if idx < 0:
		return SUPPORTED_LOCALES[0]
	return SUPPORTED_LOCALES[(idx + 1) % SUPPORTED_LOCALES.size()]

func _apply_locale() -> void:
	var loc: String = _settings.language.to_lower()
	TranslationServer.set_locale(loc)
	ProjectSettings.set_setting("internationalization/locale/locale", loc)


func _generate_id() -> String:
	return str(Time.get_unix_time_from_system()) + "_" + str(randi() % 10000)
