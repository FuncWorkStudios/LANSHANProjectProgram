## AboutScene : Control
## About/Credits screen with team info, version, accent bars.
## Port of AboutScene from App.tsx.
extends Control

signal back_requested()

var _disabled: bool = false
var _focus_idx: int = 0
var _credit_nodes: Array[Control] = []
var _credits: Array[Dictionary] = []
var _font_tcm: Font

@onready var _title_label: Label = %TitleLabel
@onready var _subtitle_container: Control = %SubtitleContainer
@onready var _credits_container: VBoxContainer = %CreditsContainer
@onready var _back_button: Control = %BackButton


func _ready() -> void:
	var is_zh: bool = GameManager.get_settings().language == "ZH"
	_font_tcm = load("res://assets/fonts/TCM_____.TTF")
	_title_label.text = "About"
	_title_label.add_theme_font_size_override("font_size", 72)
	if _font_tcm: _title_label.add_theme_font_override("font", _font_tcm)
	_credits = [
		{"en": "FuncWork Studios", "zh": "开发团队" if is_zh else "DEVELOPER", "val": "DIRECTION"},
		{"en": "LSP Collective", "zh": "美术资产" if is_zh else "ASSETS", "val": "VISUALS"},
		{"en": "3.0.0 Experimental", "zh": "引擎版本" if is_zh else "VERSION", "val": "BUILD"},
		{"en": "2026 Q2 Early Access", "zh": "发布计划" if is_zh else "SCHEDULE", "val": "DATE"},
	]
	_create_credit_rows()
	_setup_back_button()
	_animate_enter()


func _create_credit_rows() -> void:
	for i: int in range(_credits.size()):
		var row: Control = _create_credit_row(i, _credits[i])
		_credits_container.add_child(row)
		_credit_nodes.append(row)
	_update_focus()


func _create_credit_row(index: int, data: Dictionary) -> Control:
	var container := Control.new()
	container.name = "Credit_" + str(index)
	container.custom_minimum_size = Vector2(0, 110)
	container.mouse_filter = Control.MOUSE_FILTER_STOP

	var sweep := ColorRect.new()
	sweep.name = "Sweep"
	sweep.color = Color.WHITE
	sweep.set_anchors_preset(Control.PRESET_FULL_RECT)
	sweep.scale = Vector2(0, 1)
	sweep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(sweep)

	var right_bar := ColorRect.new()
	right_bar.name = "RightBar"
	right_bar.color = Color.BLACK
	right_bar.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	right_bar.size = Vector2(2, 0)
	right_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(right_bar)

	var left_bar := ColorRect.new()
	left_bar.name = "LeftBar"
	left_bar.color = Color.BLACK
	left_bar.size = Vector2(2, 110)
	left_bar.visible = false
	left_bar.anchor_left = 0.0
	left_bar.anchor_right = 0.0
	left_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(left_bar)

	var vbox := VBoxContainer.new()
	vbox.name = "Content"
	vbox.position = Vector2(24, 16)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var sub_label := Label.new()
	sub_label.name = "SubLabel"
	sub_label.text = data.zh
	sub_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.3))
	sub_label.add_theme_font_size_override("font_size", 16)
	sub_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(sub_label)

	var title_label := Label.new()
	title_label.name = "TitleLabel"
	title_label.text = data.en
	title_label.add_theme_font_size_override("font_size", 34)
	if _font_tcm:
		title_label.add_theme_font_override("font", _font_tcm)
	title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(title_label)

	container.add_child(vbox)

	var val_label := Label.new()
	val_label.name = "ValLabel"
	val_label.text = data.val
	val_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.2))
	val_label.add_theme_font_size_override("font_size", 10)
	val_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(val_label)

	container.mouse_entered.connect(_on_hover.bind(index))
	container.set_meta("sweep", sweep)
	container.set_meta("right_bar", right_bar)
	container.set_meta("left_bar", left_bar)
	container.set_meta("title_label", title_label)
	container.set_meta("sub_label", sub_label)
	container.set_meta("val_label", val_label)

	return container


func _update_focus() -> void:
	for i: int in range(_credit_nodes.size()):
		var row: Control = _credit_nodes[i]
		var is_focused: bool = i == _focus_idx
		var sweep: ColorRect = row.get_meta("sweep")
		var right_bar: ColorRect = row.get_meta("right_bar")
		var left_bar: ColorRect = row.get_meta("left_bar")
		var title: Label = row.get_meta("title_label")
		var sub: Label = row.get_meta("sub_label")
		var val: Label = row.get_meta("val_label")

		var sweep_tween := create_tween()
		sweep_tween.set_ease(Tween.EASE_OUT)
		sweep_tween.tween_property(sweep, "scale:x", 1.0 if is_focused else 0.0, 0.25)

		var x_tween := create_tween()
		x_tween.set_ease(Tween.EASE_OUT)
		x_tween.tween_property(row, "position:x", 8.0 if is_focused else 0.0, 0.25)

		var rb_tween := create_tween()
		rb_tween.set_ease(Tween.EASE_OUT)
		rb_tween.tween_property(right_bar, "size:y", 110.0 if is_focused else 0.0, 0.25)

		left_bar.visible = is_focused

		title.add_theme_color_override("font_color", Color.BLACK if is_focused else Color.WHITE)
		sub.add_theme_color_override("font_color", Color(0, 0, 0, 0.5) if is_focused else Color(1, 1, 1, 0.3))
		val.add_theme_color_override("font_color", Color(0, 0, 0, 0.4) if is_focused else Color(1, 1, 1, 0.2))
		val.position = Vector2(row.size.x - 120 if row.size.x > 0 else 1100, 40)


func _on_hover(index: int) -> void:
	if _disabled or _focus_idx == index: return
	_focus_idx = index; _update_focus(); _play_click()


func _setup_back_button() -> void:
	_back_button.mouse_filter = Control.MOUSE_FILTER_STOP
	_back_button.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_back_button.offset_top = -96.0
	_back_button.offset_bottom = 0.0

	var bar_bg := ColorRect.new()
	bar_bg.color = Color(0, 0, 0, 0.6)
	bar_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_back_button.add_child(bar_bg)

	var border := ColorRect.new()
	border.color = Color(1, 1, 1, 0.05)
	border.set_anchors_preset(Control.PRESET_TOP_WIDE)
	border.size.y = 1
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_back_button.add_child(border)

	var esc_box := ColorRect.new()
	esc_box.color = Color.WHITE
	esc_box.size = Vector2(48, 48)
	esc_box.position = Vector2(24, 24)
	esc_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_back_button.add_child(esc_box)

	var esc_label := Label.new()
	esc_label.text = "ESC"
	esc_label.position = Vector2(24, 24)
	esc_label.size = Vector2(48, 48)
	esc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	esc_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	esc_label.add_theme_color_override("font_color", Color.BLACK)
	esc_label.add_theme_font_size_override("font_size", 14)
	esc_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_back_button.add_child(esc_label)

	var is_zh: bool = GameManager.get_settings().language == "ZH"
	var back_label := Label.new()
	back_label.text = "返回" if is_zh else "BACK"
	back_label.position = Vector2(88, 28)
	back_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.8))
	back_label.add_theme_font_size_override("font_size", 24)
	back_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_back_button.add_child(back_label)

	var sub_label := Label.new()
	sub_label.text = "取消当前操作" if is_zh else "Cancel current operation"
	sub_label.position = Vector2(88, 58)
	sub_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.2))
	sub_label.add_theme_font_size_override("font_size", 10)
	sub_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_back_button.add_child(sub_label)

	_back_button.gui_input.connect(_on_back_bar_clicked)
	_back_button.mouse_entered.connect(_on_back_bar_hovered.bind(true))
	_back_button.mouse_exited.connect(_on_back_bar_hovered.bind(false))
	_back_button.set_meta("esc_box", esc_box)
	_back_button.set_meta("esc_label", esc_label)


func _on_back_bar_clicked(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_play_click(); back_requested.emit()


func _on_back_bar_hovered(hovered: bool) -> void:
	var esc_box: ColorRect = _back_button.get_meta("esc_box")
	var esc_label: Label = _back_button.get_meta("esc_label")
	if esc_box: esc_box.color = Color.BLACK if hovered else Color.WHITE
	if esc_label: esc_label.add_theme_color_override("font_color", Color.WHITE if hovered else Color.BLACK)


func _play_click() -> void:
	AudioManager.play_sfx("res://assets/Sfx/Choose.wav")


func _animate_enter() -> void:
	modulate.a = 0.0
	var tween := create_tween()
	tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_EXPO)
	tween.tween_property(self, "modulate:a", 1.0, 0.8)


func _input(event: InputEvent) -> void:
	if _disabled or not event.is_pressed(): return
	if event.is_action_pressed("ui_up"):
		_focus_idx = max(0, _focus_idx - 1); _update_focus(); _play_click()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_down"):
		_focus_idx = min(_credit_nodes.size() - 1, _focus_idx + 1); _update_focus(); _play_click()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel"):
		back_requested.emit(); get_viewport().set_input_as_handled()


func set_disabled(val: bool) -> void:
	_disabled = val
