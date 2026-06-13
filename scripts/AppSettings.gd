## AppSettings : Resource
## Application-wide settings for language, audio, display, and gameplay.
class_name AppSettings extends Resource

@export var language: String = "ZH"
@export var text_speed: String = "normal"
@export var master_volume: float = 1.0
@export var bgm_volume: float = 0.7
@export var sfx_volume: float = 0.8
@export var auto_play: bool = false
@export var shader_quality: String = "high"
@export var display_mode: String = "windowed"


func get_default() -> AppSettings:
	var s := AppSettings.new()
	s.language = "ZH"
	s.text_speed = "normal"
	s.master_volume = 1.0
	s.bgm_volume = 0.7
	s.sfx_volume = 0.8
	s.auto_play = false
	s.shader_quality = "high"
	s.display_mode = "windowed"
	return s
