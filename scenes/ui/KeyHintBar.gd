## KeyHintBar : Control
## Reusable ESC back-button bar. Displays "ESC" key hint with a
## descriptive label. Emits pressed() on mouse click or keyboard ESC.
## Used by LoadScene, SettingsScene, AboutScene, RewardsScene.
class_name KeyHintBar
extends Control

signal pressed()

var _esc_box: ColorRect
var _esc_label: Label
var _back_label: Label
var _sub_label: Label

var font_body: Font = null


func _ready() -> void:
	_build()
	_apply_language()


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
	border.size.y = 1
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
	add_child(_esc_label)

	_back_label = Label.new()
	_back_label.position = Vector2(88, 26)
	_back_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.8))
	_back_label.add_theme_font_size_override("font_size", 16)
	_back_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_back_label)

	_sub_label = Label.new()
	_sub_label.position = Vector2(88, 50)
	_sub_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.3))
	_sub_label.add_theme_font_size_override("font_size", 12)
	_sub_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_sub_label)

	gui_input.connect(_on_click)
	mouse_entered.connect(_on_hover.bind(true))
	mouse_exited.connect(_on_hover.bind(false))


func set_language(_hint: String = "") -> void:
	if _back_label:
		_apply_language()


func _apply_language() -> void:
	var is_zh := GameManager.is_locale("zh")
	_back_label.text = "返回" if is_zh else "BACK"
	if font_body:
		_back_label.add_theme_font_override("font", font_body)
	_sub_label.text = "取消当前操作" if is_zh else "Cancel current operation"
	if font_body:
		_sub_label.add_theme_font_override("font", font_body)


func _on_click(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_animate_press()
		pressed.emit()


func _on_hover(hovered: bool) -> void:
	if not _esc_box or not _esc_label:
		return
	var t := create_tween().set_parallel(true)
	t.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	t.tween_property(_esc_box, "color", Color.BLACK if hovered else Color.WHITE, 0.15)
	t.tween_property(_esc_label, "theme_override_colors/font_color", Color.WHITE if hovered else Color.BLACK, 0.15)


func _animate_press() -> void:
	if not _esc_box:
		return
	var t := create_tween()
	t.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(_esc_box, "scale", Vector2(0.82, 0.82), 0.07)
	t.tween_property(_esc_box, "scale", Vector2(1.0, 1.0), 0.14)


func trigger_from_keyboard() -> void:
	_animate_press()
	pressed.emit()
