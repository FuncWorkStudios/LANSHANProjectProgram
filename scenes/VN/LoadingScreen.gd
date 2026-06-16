## LoadingScreen : Control
## Full-screen black loading overlay with pulsing text.
extends Control

@onready var _label: Label = %LoadingLabel
@warning_ignore("unused_private_class_variable")
@onready var _bg: ColorRect = %Bg

var _font_tcm: Font = null
var _font_zh_title: Font = null
var _pulse_tween: Tween = null


func _ready() -> void:
	visible = false
	_font_tcm = load(GameManager.FONT_TCM)
	_font_zh_title = load(GameManager.FONT_ZH_TITLE)


func setup_fonts() -> void:
	var is_zh: bool = GameManager.is_locale("zh")
	if not is_zh and _font_tcm:
		_label.add_theme_font_override("font", _font_tcm)
	elif _font_zh_title:
		_label.add_theme_font_override("font", _font_zh_title)
	_label.add_theme_font_size_override("font_size", 32)


func show_loading() -> void:
	setup_fonts()
	visible = true
	if _pulse_tween and _pulse_tween.is_valid():
		_pulse_tween.kill()
	_pulse_tween = create_tween().set_loops()
	_pulse_tween.tween_property(_label, "modulate:a", 0.3, 0.8)
	_pulse_tween.tween_property(_label, "modulate:a", 1.0, 0.8)


func hide_loading() -> void:
	visible = false
	if _pulse_tween and _pulse_tween.is_valid():
		_pulse_tween.kill()
	_pulse_tween = null
