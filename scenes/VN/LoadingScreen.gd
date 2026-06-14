## LoadingScreen : Control
## Full-screen black loading overlay with pulsing text.
extends Control

@onready var _label: Label = %LoadingLabel
@onready var _bg: ColorRect = %Bg


func _ready() -> void:
	visible = false


func show_loading() -> void:
	visible = true
	var tween := create_tween().set_loops()
	tween.tween_property(_label, "modulate:a", 0.3, 0.8)
	tween.tween_property(_label, "modulate:a", 1.0, 0.8)


func hide_loading() -> void:
	visible = false
