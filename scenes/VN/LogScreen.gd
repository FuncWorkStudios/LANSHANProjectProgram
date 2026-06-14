## LogScreen : Control
## Dialogue history overlay.
class_name LogScreen
extends Control

signal close_requested()

var _entries: Array[Dictionary] = []
var _is_open: bool = false
var _anim_tween: Tween = null

# Cached font resources (loaded once in _ready)
var _cached_fz_body: Font = null
var _cached_fz_title: Font = null
var _cached_fen_body: Font = null
var _cached_ftcm: Font = null

@onready var _backdrop: ColorRect = $Backdrop
@onready var _title_label: Label = $TitleLabel
@onready var _scroll: ScrollContainer = $EntryScroll
@onready var _list: VBoxContainer = $EntryScroll/EntryList
@onready var _hint_bar: Control = $HintBar


func _ready() -> void:
	_cached_fz_body = load(GameManager.FONT_ZH_BODY)
	_cached_fz_title = load(GameManager.FONT_ZH_TITLE)
	_cached_fen_body = load(GameManager.FONT_EN_BODY)
	_cached_ftcm = load(GameManager.FONT_TCM)
	_setup_title()
	_setup_hint_bar()
	visible = false
	mouse_filter = MOUSE_FILTER_STOP
	gui_input.connect(_swallow)


func _setup_title() -> void:
	_title_label.add_theme_font_size_override("font_size", 16)
	_title_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.4))
	if _cached_fz_title: _title_label.add_theme_font_override("font", _cached_fz_title)


func _setup_hint_bar() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.9)
	bg.set_anchors_preset(PRESET_FULL_RECT)
	bg.mouse_filter = MOUSE_FILTER_IGNORE
	_hint_bar.add_child(bg)

	var hb := HBoxContainer.new()
	hb.set_anchors_preset(PRESET_FULL_RECT)
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 32)
	hb.mouse_filter = MOUSE_FILTER_IGNORE
	_hint_bar.add_child(hb)

	_add_hint(hb, "ESC", "Close")
	_add_hint(hb, "Z", "Close")
	_add_hint(hb, "Wheel", "Scroll")


func _add_hint(parent: HBoxContainer, key: String, label: String) -> void:
	var g := HBoxContainer.new()
	g.custom_minimum_size = Vector2(110, 72)
	g.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	g.add_theme_constant_override("separation", 8)
	g.mouse_filter = MOUSE_FILTER_IGNORE
	parent.add_child(g)

	var box := ColorRect.new()
	box.custom_minimum_size = Vector2(36, 36)
	box.color = Color(1, 1, 1, 0.15)
	box.mouse_filter = MOUSE_FILTER_IGNORE
	g.add_child(box)

	var kl := Label.new()
	kl.text = key
	kl.set_anchors_preset(PRESET_FULL_RECT)
	kl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	kl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	kl.add_theme_font_size_override("font_size", 16)
	kl.add_theme_color_override("font_color", Color.WHITE)
	kl.mouse_filter = MOUSE_FILTER_IGNORE
	box.add_child(kl)

	var lbl := Label.new()
	lbl.text = label
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", Color(1, 1, 1, 0.3))
	lbl.mouse_filter = MOUSE_FILTER_IGNORE
	g.add_child(lbl)


func open(entries: Array[Dictionary]) -> void:
	_entries = entries
	_is_open = true
	visible = true
	_kill_anim()

	if get_parent():
		position = Vector2.ZERO
		size = get_parent().size

	for c in _list.get_children():
		c.queue_free()

	_list.add_theme_constant_override("separation", 6)

	if _entries.is_empty():
		var noop := Label.new()
		noop.text = "No data"
		noop.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		noop.custom_minimum_size = Vector2(0, 200)
		noop.size_flags_horizontal = Control.SIZE_FILL
		noop.add_theme_font_size_override("font_size", 24)
		noop.add_theme_color_override("font_color", Color(1, 1, 1, 0.25))
		noop.mouse_filter = MOUSE_FILTER_IGNORE
		_list.add_child(noop)
	else:
		_build_entries()

	modulate.a = 0.0
	_anim_tween = create_tween()
	_anim_tween.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	_anim_tween.tween_property(self, "modulate:a", 1.0, 0.3)

	if not _entries.is_empty():
		await get_tree().process_frame
		for c in _list.get_children():
			if c is Control and c.has_meta("tl"):
				var tl: Label = c.get_meta("tl")
				c.custom_minimum_size.y = tl.get_minimum_size().y + 2
		await get_tree().process_frame
		_scroll.scroll_vertical = _scroll.get_v_scroll_bar().max_value


func close() -> void:
	_is_open = false
	_kill_anim()
	_anim_tween = create_tween()
	_anim_tween.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	_anim_tween.tween_property(self, "modulate:a", 0.0, 0.2)
	_anim_tween.tween_callback(_on_close_done)


func _on_close_done() -> void:
	visible = false
	close_requested.emit()


func _build_entries() -> void:
	var is_zh := _is_zh()
	var fz_body: Font = _cached_fz_body
	var fz_title: Font = _cached_fz_title
	var fen_body: Font = _cached_fen_body
	var ftcm: Font = _cached_ftcm

	for i: int in range(_entries.size()):
		var entry := _entries[i]
		var who: String = entry.get("who", "")
		var text: String = entry.get("zh", "") if is_zh else entry.get("en", "")
		if text.is_empty():
			text = entry.get("zh", "")

		# Row: name label + text label, fixed layout
		var row := Control.new()
		row.layout_mode = 1
		row.anchor_left = 0.0
		row.anchor_right = 1.0
		row.mouse_filter = MOUSE_FILTER_IGNORE

		var name_lbl := Label.new()
		name_lbl.text = who
		name_lbl.layout_mode = 1
		name_lbl.anchor_left = 0.0
		name_lbl.anchor_right = 0.0
		name_lbl.anchor_top = 0.0
		name_lbl.anchor_bottom = 1.0
		name_lbl.offset_right = 140
		name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		name_lbl.add_theme_font_size_override("font_size", 17)
		name_lbl.add_theme_color_override("font_color", Color(1, 1, 1, 0.5))
		name_lbl.mouse_filter = MOUSE_FILTER_IGNORE
		if not is_zh and ftcm:
			name_lbl.add_theme_font_override("font", ftcm)
		elif fz_title:
			name_lbl.add_theme_font_override("font", fz_title)
		row.add_child(name_lbl)

		var text_lbl := Label.new()
		text_lbl.text = text
		text_lbl.layout_mode = 1
		text_lbl.anchor_left = 0.0
		text_lbl.anchor_right = 1.0
		text_lbl.anchor_top = 0.0
		text_lbl.anchor_bottom = 1.0
		text_lbl.offset_left = 152
		text_lbl.offset_right = 0
		text_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text_lbl.add_theme_font_size_override("font_size", 19)
		text_lbl.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
		text_lbl.mouse_filter = MOUSE_FILTER_IGNORE
		if not is_zh and fen_body:
			text_lbl.add_theme_font_override("font", fen_body)
		elif fz_body:
			text_lbl.add_theme_font_override("font", fz_body)
		row.add_child(text_lbl)
		row.set_meta("tl", text_lbl)
		_list.add_child(row)

		if i < _entries.size() - 1:
			var sep := ColorRect.new()
			sep.custom_minimum_size = Vector2(0, 14)
			sep.size_flags_horizontal = Control.SIZE_FILL
			sep.color = Color(1, 1, 1, 0.04)
			sep.mouse_filter = MOUSE_FILTER_IGNORE
			_list.add_child(sep)




func _smooth_scroll_to(target: float) -> void:
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_property(_scroll, "scroll_vertical", target, 0.25)


func _input(event: InputEvent) -> void:
	if not _is_open: return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("vn_log"):
		close()
		get_viewport().set_input_as_handled()
		return
	if not event.is_pressed(): return
	if event.is_action_pressed("ui_up"):
		var bar := _scroll.get_v_scroll_bar()
		_smooth_scroll_to(max(bar.min_value, bar.value - 60.0))
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_down"):
		var bar := _scroll.get_v_scroll_bar()
		_smooth_scroll_to(min(bar.max_value, bar.value + 60.0))
		get_viewport().set_input_as_handled()
	if event is InputEventMouseButton:
		var bar := _scroll.get_v_scroll_bar()
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_smooth_scroll_to(max(bar.min_value, bar.value - 120.0))
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_smooth_scroll_to(min(bar.max_value, bar.value + 120.0))


func _is_zh() -> bool:
	return GameManager.is_locale("zh")


func _swallow(_e: InputEvent) -> void:
	pass


func _kill_anim() -> void:
	if _anim_tween and _anim_tween.is_valid():
		_anim_tween.kill()
	_anim_tween = null
