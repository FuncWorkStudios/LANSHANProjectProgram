## ChoicesMenu : Control
## Full-screen choice overlay with numbered option buttons.
## Instantiated by VNInterface when a select node is active.
extends Control

signal choice_selected(index: int)

var _focused_idx: int = 0
var _font_tcm: Font = null
var _font_zh_title: Font = null

@onready var _overlay: ColorRect = %Overlay
@onready var _container: VBoxContainer = %Container


func show_options(options: Array, fonts: Dictionary, _language_hint: String = "") -> void:
	_font_tcm = fonts.get("tcm", null)
	_font_zh_title = fonts.get("zh_title", null)
	_focused_idx = 0

	# Clear old
	for c in _container.get_children():
		c.queue_free()

	for i: int in range(options.size()):
		var row: Control = _make_row(i, options[i])
		_container.add_child(row)

	visible = true
	_update_focus()


func hide_options() -> void:
	visible = false


func _make_row(idx: int, opt) -> Control:
	var wrap: Control = Control.new()
	wrap.name = "Choice_" + str(idx)
	wrap.custom_minimum_size = Vector2(0, 72)
	wrap.size_flags_horizontal = Control.SIZE_FILL
	wrap.mouse_filter = Control.MOUSE_FILTER_STOP

	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.9)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(bg)

	var sweep := ColorRect.new()
	sweep.name = "Sweep"
	sweep.color = Color.WHITE
	sweep.set_anchors_preset(Control.PRESET_FULL_RECT)
	sweep.pivot_offset = Vector2(0, 0)
	sweep.scale.x = 0.0
	sweep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(sweep)

	var hb: HBoxContainer = HBoxContainer.new()
	hb.set_anchors_preset(Control.PRESET_FULL_RECT)
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 24)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(hb)

	# Left spacer
	var sp1 := Control.new()
	sp1.custom_minimum_size = Vector2(24, 0)
	sp1.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(sp1)

	# Number prefix
	var num := Label.new()
	num.text = "0%d" % (idx + 1)
	if _font_tcm: num.add_theme_font_override("font", _font_tcm)
	num.add_theme_color_override("font_color", Color(1, 1, 1, 0.4))
	num.add_theme_font_size_override("font_size", 28)
	num.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(num)

	# Text
	var lbl := Label.new()
	lbl.text = opt.ZH if TranslationServer.get_locale().begins_with("zh") or opt.EN.is_empty() else opt.EN
	if _font_zh_title: lbl.add_theme_font_override("font", _font_zh_title)
	lbl.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	lbl.add_theme_font_size_override("font_size", 28)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(lbl)

	var sp2 := Control.new()
	sp2.custom_minimum_size = Vector2(24, 0)
	sp2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(sp2)

	wrap.mouse_entered.connect(_on_hover.bind(idx))
	wrap.gui_input.connect(_on_click.bind(idx))
	wrap.set_meta("sweep", sweep)
	wrap.set_meta("num", num)
	wrap.set_meta("lbl", lbl)
	return wrap


func _update_focus() -> void:
	for i: int in range(_container.get_child_count()):
		var child: Control = _container.get_child(i)
		var is_focused: bool = i == _focused_idx
		var sweep: ColorRect = child.get_meta("sweep")
		var num: Label = child.get_meta("num")
		var lbl: Label = child.get_meta("lbl")

		var tween := create_tween().set_parallel(true)
		tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.tween_property(sweep, "scale:x", 1.0 if is_focused else 0.0, 0.3)
		tween.tween_property(child, "modulate:a", 1.0 if is_focused else 0.5, 0.3)
		tween.tween_property(child, "position:x", 10.0 if is_focused else 0.0, 0.3)

		num.add_theme_color_override("font_color", Color(0, 0, 0, 0.4) if is_focused else Color(1, 1, 1, 0.4))
		lbl.add_theme_color_override("font_color", Color.BLACK if is_focused else Color(1, 1, 1, 0.85))


func _on_hover(idx: int) -> void:
	if _focused_idx == idx: return
	_focused_idx = idx
	_update_focus()


func _on_click(event: InputEvent, idx: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_focused_idx = idx
		AudioManager.play_sfx(AudioManager.SFX_CLICK)
		choice_selected.emit(idx)


func _input(event: InputEvent) -> void:
	if not visible or not event.is_pressed():
		return

	if event.is_action_pressed("ui_up"):
		var count: int = _container.get_child_count()
		_focused_idx = (_focused_idx - 1 + count) % count
		_update_focus()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_down"):
		var count: int = _container.get_child_count()
		_focused_idx = (_focused_idx + 1) % count
		_update_focus()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		AudioManager.play_sfx(AudioManager.SFX_CLICK)
		choice_selected.emit(_focused_idx)
		get_viewport().set_input_as_handled()
