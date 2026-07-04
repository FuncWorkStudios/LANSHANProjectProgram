## ChoicesMenu : Control
## 选择覆盖层 — 当剧情到达选择节点时显示。
##   键盘 ↑↓ 导航，Enter 确认，鼠标点击选择。
##   自动根据当前语言显示对应的选项文本。
class_name ChoicesMenu
extends Control

signal choice_selected(index: int)

var _focused_idx: int = 0
var _option_count: int = 0
var _rows: Array[Control] = []

var _font_tcm: Font = null
var _font_zh_body: Font = null
var _font_en_body: Font = null

const ROW_HEIGHT: float = 64.0
const FOCUS_SWEEP_DUR: float = 0.22


func show_options(options: Array[PlotOption], fonts: Dictionary) -> void:
	_font_tcm = fonts.get("tcm", null)
	_font_zh_body = fonts.get("zh_body", null)
	_font_en_body = fonts.get("en_body", null)
	_focused_idx = 0
	_option_count = options.size()

	for c in get_children():
		c.queue_free()
	_rows.clear()

	# 半透明黑色全屏遮罩
	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.55)
	overlay.set_anchors_preset(PRESET_FULL_RECT)
	overlay.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(overlay)

	# 选项垂直居中
	var vbox := VBoxContainer.new()
	vbox.name = "ChoicesVBox"
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.set_anchors_preset(PRESET_FULL_RECT)
	vbox.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(vbox)

	var is_zh: bool = GameManager.is_locale("zh")

	for i: int in range(_option_count):
		var opt: PlotOption = options[i]
		var text: String
		if is_zh:
			text = opt.ZH
		elif not opt.EN.is_empty():
			text = opt.EN
		else:
			text = tr(opt.ZH)
		var row: Control = _make_row(i, text)
		vbox.add_child(row)
		_rows.append(row)

	visible = true
	_update_focus()


func hide_options() -> void:
	visible = false


# ═══════════════════════════════════════════════════════════════
# 行构建
# ═══════════════════════════════════════════════════════════════

func _make_row(idx: int, text: String) -> Control:
	var row := Control.new()
	row.name = "Choice_" + str(idx)
	row.custom_minimum_size = Vector2(520, ROW_HEIGHT)
	row.mouse_filter = MOUSE_FILTER_STOP

	# 白色扫入背景
	var sweep := ColorRect.new()
	sweep.name = "Sweep"
	sweep.color = Color.WHITE
	sweep.set_anchors_preset(PRESET_FULL_RECT)
	sweep.pivot_offset = Vector2.ZERO
	sweep.scale.x = 0.0
	sweep.mouse_filter = MOUSE_FILTER_IGNORE
	row.add_child(sweep)

	# 内容行
	var hb := HBoxContainer.new()
	hb.set_anchors_preset(PRESET_FULL_RECT)
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 16)
	hb.mouse_filter = MOUSE_FILTER_IGNORE
	row.add_child(hb)

	# 左间隔
	var sp := Control.new(); sp.custom_minimum_size = Vector2(32, 0)
	sp.mouse_filter = MOUSE_FILTER_IGNORE
	hb.add_child(sp)

	# 序号
	var num := Label.new()
	num.text = "%02d" % (idx + 1)
	num.add_theme_font_size_override("font_size", 26)
	if _font_tcm: num.add_theme_font_override("font", _font_tcm)
	num.mouse_filter = MOUSE_FILTER_IGNORE
	hb.add_child(num)

	# 选项文本
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 24)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	@warning_ignore("static_called_on_instance")
	lbl.add_theme_font_override("font", GameManager.select_font(text, _font_zh_body, _font_en_body))
	lbl.mouse_filter = MOUSE_FILTER_IGNORE
	hb.add_child(lbl)

	# 右间隔
	var sp2 := Control.new(); sp2.custom_minimum_size = Vector2(32, 0)
	sp2.mouse_filter = MOUSE_FILTER_IGNORE
	hb.add_child(sp2)

	row.mouse_entered.connect(_on_hover.bind(idx))
	row.gui_input.connect(_on_click.bind(idx))
	row.set_meta("sweep", sweep)
	row.set_meta("num", num)
	row.set_meta("lbl", lbl)
	return row


# ═══════════════════════════════════════════════════════════════
# 焦点动画
# ═══════════════════════════════════════════════════════════════

func _update_focus() -> void:
	for i: int in range(_rows.size()):
		var row: Control = _rows[i]
		var on: bool = i == _focused_idx
		var sweep: ColorRect = row.get_meta("sweep")
		var num: Label = row.get_meta("num")
		var lbl: Label = row.get_meta("lbl")

		var tw := create_tween().set_parallel(true)
		tw.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(sweep, "scale:x", 1.0 if on else 0.0, FOCUS_SWEEP_DUR)
		tw.tween_property(row, "position:x", 16.0 if on else 0.0, FOCUS_SWEEP_DUR)

		num.add_theme_color_override("font_color", Color(0, 0, 0, 0.45) if on else Color(1, 1, 1, 0.4))
		lbl.add_theme_color_override("font_color", Color.BLACK if on else Color(1, 1, 1, 0.85))


# ═══════════════════════════════════════════════════════════════
# 交互
# ═══════════════════════════════════════════════════════════════

func _on_hover(idx: int) -> void:
	if _focused_idx == idx: return
	_focused_idx = idx
	_update_focus()
	AudioManager.play_click()


func _on_click(event: InputEvent, idx: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		AudioManager.play_click()
		choice_selected.emit(idx)


func _input(event: InputEvent) -> void:
	if not visible or not event.is_pressed():
		return

	if event.is_action_pressed("ui_up"):
		_focused_idx = (_focused_idx - 1 + _option_count) % _option_count
		_update_focus()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_down"):
		_focused_idx = (_focused_idx + 1) % _option_count
		_update_focus()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		AudioManager.play_click()
		choice_selected.emit(_focused_idx)
		get_viewport().set_input_as_handled()
