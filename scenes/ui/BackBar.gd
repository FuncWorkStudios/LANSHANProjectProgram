## BackBar : Control
## 可复用的 ESC 返回按钮栏。供所有子场景统一使用。
##   鼠标点击或键盘 ESC → 发出 pressed() 信号。
class_name BackBar
extends Control

signal pressed()

var _esc_box: ColorRect
var _esc_label: Label
var _back_label: Label



func _init() -> void:
	_build()


func _build() -> void:

	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	offset_top = -96.0
	offset_bottom = 0.0

	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.6)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var border := ColorRect.new()
	border.color = Color(1, 1, 1, 0.05)
	border.set_anchors_preset(Control.PRESET_TOP_WIDE)
	border.offset_bottom = 1.0
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(border)

	_esc_box = ColorRect.new()
	_esc_box.color = Color.WHITE
	_esc_box.size = Vector2(48, 48)
	_esc_box.position = Vector2(24, 24)
	_esc_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_esc_box)

	_esc_label = Label.new()
	_esc_label.text = "ESC"
	_esc_label.position = Vector2(24, 24)
	_esc_label.size = Vector2(48, 48)
	_esc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_esc_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_esc_label.add_theme_color_override("font_color", Color.BLACK)
	_esc_label.add_theme_font_size_override("font_size", 14)
	_esc_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if GameManager.font_tcm: _esc_label.add_theme_font_override("font", GameManager.font_tcm)
	add_child(_esc_label)

	_back_label = Label.new()
	_back_label.text = tr("返回")
	_back_label.position = Vector2(88, 28)
	_back_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.8))
	_back_label.add_theme_font_size_override("font_size", 24)
	_back_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	@warning_ignore("static_called_on_instance")
	var bl_font: Font = GameManager.select_font(_back_label.text, GameManager.font_zh_title, GameManager.font_tcm)
	if bl_font: _back_label.add_theme_font_override("font", bl_font)
	add_child(_back_label)

	gui_input.connect(_on_click)
	mouse_entered.connect(_on_hover.bind(true))
	mouse_exited.connect(_on_hover.bind(false))


func set_language() -> void:
	_back_label.text = tr("返回")
	@warning_ignore("static_called_on_instance")
	var bl_font: Font = GameManager.select_font(_back_label.text, GameManager.font_zh_title, GameManager.font_tcm)
	if bl_font: _back_label.add_theme_font_override("font", bl_font)


func _on_click(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		AudioManager.play_click()
		pressed.emit()


func _on_hover(hovered: bool) -> void:
	var t := create_tween().set_parallel(true)
	t.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	t.tween_property(_esc_box, "color", Color.BLACK if hovered else Color.WHITE, 0.15)
	t.tween_property(_esc_label, "theme_override_colors/font_color", Color.WHITE if hovered else Color.BLACK, 0.15)
