## BackBar : Control
## 可复用的 ESC 返回按钮栏。供所有子场景统一使用。
##   鼠标点击或键盘 ESC → 发出 pressed() 信号。
##   自动处理中/英文副标签差异。
class_name BackBar
extends Control

signal pressed()

var _esc_box: ColorRect
var _esc_label: Label
var _back_label: Label
var _sub_label: Label

var _font_tcm: Font = null
var _font_zh_title: Font = null
var _font_zh_body: Font = null
var _font_en_body: Font = null

var _sub_text: String = ""


func _init(p_sub_text: String = "") -> void:
	_sub_text = p_sub_text
	_build()
	_apply_sub_text()


func _build() -> void:
	_font_tcm = load(GameManager.FONT_TCM)
	_font_zh_title = load(GameManager.FONT_ZH_TITLE)
	_font_zh_body = load(GameManager.FONT_ZH_BODY)
	_font_en_body = load(GameManager.FONT_EN_BODY)

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
	if _font_tcm: _esc_label.add_theme_font_override("font", _font_tcm)
	add_child(_esc_label)

	_back_label = Label.new()
	_back_label.text = tr("返回")
	_back_label.position = Vector2(88, 28)
	_back_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.8))
	_back_label.add_theme_font_size_override("font_size", 24)
	_back_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	@warning_ignore("static_called_on_instance")
	var bl_font: Font = GameManager.select_font(_back_label.text, _font_zh_title, _font_tcm)
	if bl_font: _back_label.add_theme_font_override("font", bl_font)
	add_child(_back_label)

	_sub_label = Label.new()
	_sub_label.text = ""
	_sub_label.position = Vector2(88, 58)
	_sub_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.2))
	_sub_label.add_theme_font_size_override("font_size", 10)
	_sub_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_sub_label)

	gui_input.connect(_on_click)
	mouse_entered.connect(_on_hover.bind(true))
	mouse_exited.connect(_on_hover.bind(false))


func _apply_sub_text() -> void:
	@warning_ignore("shadowed_variable_base_class")
	var show: bool = not GameManager.is_locale("en") and not _sub_text.is_empty()
	_sub_label.text = tr(_sub_text) if show else ""
	_sub_label.visible = show


func set_language() -> void:
	_back_label.text = tr("返回")
	@warning_ignore("static_called_on_instance")
	var bl_font: Font = GameManager.select_font(_back_label.text, _font_zh_title, _font_tcm)
	if bl_font: _back_label.add_theme_font_override("font", bl_font)
	_apply_sub_text()


func _on_click(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		AudioManager.play_click()
		pressed.emit()


func _on_hover(hovered: bool) -> void:
	var t := create_tween().set_parallel(true)
	t.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	t.tween_property(_esc_box, "color", Color.BLACK if hovered else Color.WHITE, 0.15)
	t.tween_property(_esc_label, "theme_override_colors/font_color", Color.WHITE if hovered else Color.BLACK, 0.15)
