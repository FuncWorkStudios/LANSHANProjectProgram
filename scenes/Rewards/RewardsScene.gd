## RewardsScene : Control
## Rewards/achievements screen with custom progress bar and accent bars.
## Port of RewardsScene from App.tsx.
extends Control

signal back_requested()

var _disabled: bool = false
var _focus_idx: int = 0
var _item_nodes: Array[Control] = []
var _item_data: Array[Dictionary] = []
var _font_tcm: Font
var _font_zh_title: Font

@onready var _title_label: Label = %TitleLabel
@onready var _items_container: VBoxContainer = %ItemsContainer
@onready var _back_button: Control = %BackButton


func _ready() -> void:
	var is_zh: bool = GameManager.get_settings().language == "ZH"
	_title_label.text = "Rewards"
	_font_tcm = load("res://assets/fonts/TCM_____.TTF")
	_font_zh_title = load("res://assets/fonts/SourceHanSerifCN-SemiBold-7.otf")
	_title_label.add_theme_font_size_override("font_size", 72)
	if _font_tcm: _title_label.add_theme_font_override("font", _font_tcm)
	_item_data = [
		{"en": "Rewards", "zh": "成就", "desc_zh": "已经获得的全部游戏成就", "desc_en": "All game achievements earned.", "prog": 75},
	]
	for i: int in range(_item_data.size()):
		var row: Control = _create_item_row(i, _item_data[i])
		_items_container.add_child(row)
		_item_nodes.append(row)
	_update_focus()
	_setup_back_button()
	_animate_enter()


func _create_item_row(index: int, data: Dictionary) -> Control:
	var is_zh: bool = GameManager.get_settings().language == "ZH"
	var container := Control.new()
	container.name = "Item_" + str(index)
	container.custom_minimum_size = Vector2(0, 110)
	container.mouse_filter = Control.MOUSE_FILTER_STOP

	# Sweep background — anchors fill entire row
	var sweep := ColorRect.new()
	sweep.name = "Sweep"
	sweep.color = Color.WHITE
	sweep.set_anchors_preset(Control.PRESET_FULL_RECT)
	sweep.scale = Vector2(0, 1)
	sweep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(sweep)

	# Right accent bar
	var right_bar := ColorRect.new()
	right_bar.name = "RightBar"
	right_bar.color = Color.BLACK
	right_bar.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	right_bar.size = Vector2(2, 0)
	right_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(right_bar)

	# Left active indicator
	var left_bar := ColorRect.new()
	left_bar.name = "LeftBar"
	left_bar.color = Color.BLACK
	left_bar.size = Vector2(2, 110)
	left_bar.visible = false
	left_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(left_bar)

	# Content
	var vbox := VBoxContainer.new()
	vbox.name = "Content"
	vbox.position = Vector2(24, 16)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var sub_label := Label.new()
	sub_label.name = "SubLabel"
	sub_label.text = data.zh
	sub_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.3))
	sub_label.add_theme_font_size_override("font_size", 16)
	if _font_zh_title: sub_label.add_theme_font_override("font", _font_zh_title)
	sub_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(sub_label)

	var title_label := Label.new()
	title_label.name = "TitleLabel"
	title_label.text = data.en
	title_label.add_theme_font_size_override("font_size", 34)
	if _font_tcm: title_label.add_theme_font_override("font", _font_tcm)
	title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(title_label)

	var desc_label := Label.new()
	desc_label.name = "DescLabel"
	desc_label.text = data.desc_zh if is_zh else data.desc_en
	desc_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.4))
	desc_label.add_theme_font_size_override("font_size", 11)
	desc_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(desc_label)

	container.add_child(vbox)

	# Custom progress bar
	if "prog" in data:
		var prog_track := ColorRect.new()
		prog_track.name = "ProgTrack"
		prog_track.color = Color(1, 1, 1, 0.05)
		prog_track.size = Vector2(400, 3)
		prog_track.position = Vector2(24, 100)
		prog_track.mouse_filter = Control.MOUSE_FILTER_IGNORE
		container.add_child(prog_track)

		var prog_fill := ColorRect.new()
		prog_fill.name = "ProgFill"
		prog_fill.color = Color(1, 1, 1, 0.4)
		prog_fill.size = Vector2(400 * data.prog / 100.0, 3)
		prog_fill.position = Vector2(24, 100)
		prog_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		container.add_child(prog_fill)
		container.set_meta("prog_fill", prog_fill)

	container.mouse_entered.connect(_on_hover.bind(index))
	container.set_meta("sweep", sweep)
	container.set_meta("right_bar", right_bar)
	container.set_meta("left_bar", left_bar)
	container.set_meta("title_label", title_label)
	container.set_meta("sub_label", sub_label)
	container.set_meta("desc_label", desc_label)

	return container


func _update_focus() -> void:
	for i: int in range(_item_nodes.size()):
		var row: Control = _item_nodes[i]
		var is_focused: bool = i == _focus_idx
		var sweep: ColorRect = row.get_meta("sweep")
		var right_bar: ColorRect = row.get_meta("right_bar")
		var left_bar: ColorRect = row.get_meta("left_bar")
		var title: Label = row.get_meta("title_label")
		var sub: Label = row.get_meta("sub_label")
		var desc: Label = row.get_meta("desc_label")

		var sweep_tween := create_tween()
		sweep_tween.set_ease(Tween.EASE_OUT)
		sweep_tween.tween_property(sweep, "scale:x", 1.0 if is_focused else 0.0, 0.18)

		var x_tween := create_tween()
		x_tween.set_ease(Tween.EASE_OUT)
		x_tween.tween_property(row, "position:x", 8.0 if is_focused else 0.0, 0.18)

		var rb_tween := create_tween()
		rb_tween.set_ease(Tween.EASE_OUT)
		rb_tween.tween_property(right_bar, "size:y", 110.0 if is_focused else 0.0, 0.18)

		left_bar.visible = is_focused

		title.add_theme_color_override("font_color", Color.BLACK if is_focused else Color.WHITE)
		sub.add_theme_color_override("font_color", Color(0, 0, 0, 0.5) if is_focused else Color(1, 1, 1, 0.3))
		desc.add_theme_color_override("font_color", Color(0, 0, 0, 0.4) if is_focused else Color(1, 1, 1, 0.4))

		if row.has_meta("prog_fill"):
			var prog_fill: ColorRect = row.get_meta("prog_fill")
			prog_fill.color = Color.BLACK if is_focused else Color(1, 1, 1, 0.4)


func _on_hover(index: int) -> void:
	if _disabled or _focus_idx == index: return
	_focus_idx = index; _update_focus(); _play_click()


# ---- Back button bar ----

func _setup_back_button() -> void:
	_back_button.mouse_filter = Control.MOUSE_FILTER_STOP
	_back_button.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_back_button.offset_top = -96.0
	_back_button.offset_bottom = 0.0

	var bar_bg := ColorRect.new()
	bar_bg.name = "BarBg"
	bar_bg.color = Color(0, 0, 0, 0.6)
	bar_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_back_button.add_child(bar_bg)

	var border := ColorRect.new()
	border.name = "Border"
	border.color = Color(1, 1, 1, 0.05)
	border.set_anchors_preset(Control.PRESET_TOP_WIDE)
	border.size.y = 1
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_back_button.add_child(border)

	var esc_box := ColorRect.new()
	esc_box.name = "EscBox"
	esc_box.color = Color.WHITE
	esc_box.size = Vector2(48, 48)
	esc_box.position = Vector2(24, 24)
	esc_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_back_button.add_child(esc_box)

	var esc_label := Label.new()
	esc_label.name = "EscLabel"
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
	back_label.name = "BackLabel"
	back_label.text = "返回" if is_zh else "BACK"
	back_label.position = Vector2(88, 28)
	back_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.8))
	back_label.add_theme_font_size_override("font_size", 24)
	back_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_back_button.add_child(back_label)

	var sub_label := Label.new()
	sub_label.name = "SubLabel"
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
	tween.tween_property(self, "modulate:a", 1.0, 0.18)


func _input(event: InputEvent) -> void:
	if _disabled or not event.is_pressed(): return
	if event.is_action_pressed("ui_up"):
		_focus_idx = max(0, _focus_idx - 1); _update_focus(); _play_click()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_down"):
		_focus_idx = min(_item_nodes.size() - 1, _focus_idx + 1); _update_focus(); _play_click()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel"):
		back_requested.emit(); get_viewport().set_input_as_handled()


func set_disabled(val: bool) -> void:
	_disabled = val
