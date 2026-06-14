## SaveMenu : Control
## Full-screen save/load interface with 20-slot grid.
## Instantiated by VNInterface.
extends Control

signal close_requested()
signal save_selected(slot_index: int)

var _focused_slot_idx: int = 0
var _language: String = "ZH"
var _font_tcm: Font = null
var _font_zh_body: Font = null
var _font_zh_title: Font = null
var _font_en_body: Font = null

@onready var _backdrop: ColorRect = %Backdrop
@onready var _header: Control = %Header
@onready var _close_btn: Button = %CloseBtn
@onready var _slots_grid: GridContainer = %SlotsGrid


func open(fonts: Dictionary, language: String) -> void:
	_font_tcm = fonts.get("tcm", null)
	_font_zh_body = fonts.get("zh_body", null)
	_font_zh_title = fonts.get("zh_title", null)
	_font_en_body = fonts.get("en_body", null)
	_language = language
	_focused_slot_idx = 0

	_setup_header()
	_refresh_slots()
	_close_btn.pressed.connect(_on_close)
	visible = true


func _setup_header() -> void:
	for c in _header.get_children():
		c.queue_free()

	var sub := Label.new()
	sub.text = "Memory Matrix / 存储矩阵"
	sub.add_theme_color_override("font_color", Color(1, 1, 1, 0.4))
	sub.add_theme_font_size_override("font_size", 10)
	if _font_tcm: sub.add_theme_font_override("font", _font_tcm)
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_header.add_child(sub)

	var title := Label.new()
	title.text = "Archive"
	title.offset_top = 20.0
	title.add_theme_color_override("font_color", Color.WHITE)
	title.add_theme_font_size_override("font_size", 56)
	if _font_tcm: title.add_theme_font_override("font", _font_tcm)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_header.add_child(title)


func _refresh_slots() -> void:
	for c in _slots_grid.get_children():
		c.queue_free()

	var saves: Array = GameManager.get_save_slots()
	for i: int in range(GameManager.MAX_SLOTS):
		var slot: Control = _create_slot(i, saves[i] if i < saves.size() else null)
		_slots_grid.add_child(slot)
	_update_focus()


func _create_slot(index: int, save: SaveData) -> Control:
	var is_zh: bool = _language == "ZH"
	var container := Control.new()
	container.name = "Slot_" + str(index)
	container.custom_minimum_size = Vector2(360, 150)
	container.mouse_filter = Control.MOUSE_FILTER_STOP

	var bg := ColorRect.new()
	bg.color = Color(1, 1, 1, 0.05)
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(bg)

	var sweep := ColorRect.new()
	sweep.name = "Sweep"
	sweep.color = Color.WHITE
	sweep.anchor_right = 1.0
	sweep.anchor_bottom = 1.0
	sweep.pivot_offset = Vector2(0, 0)
	sweep.scale.x = 0.0
	sweep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(sweep)

	var right_bar := ColorRect.new()
	right_bar.name = "RightBar"
	right_bar.color = Color.BLACK
	right_bar.anchor_right = 1.0
	right_bar.anchor_bottom = 1.0
	right_bar.offset_left = -2.0
	right_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(right_bar)

	var bottom_bar := ColorRect.new()
	bottom_bar.name = "BottomBar"
	bottom_bar.color = Color.BLACK
	bottom_bar.anchor_left = 0.0
	bottom_bar.anchor_right = 1.0
	bottom_bar.anchor_bottom = 1.0
	bottom_bar.offset_top = -2.0
	bottom_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(bottom_bar)

	var num_label := Label.new()
	num_label.text = "%02d" % (index + 1)
	num_label.offset_left = 16.0
	num_label.offset_top = 8.0
	num_label.add_theme_font_size_override("font_size", 52)
	num_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.12))
	if _font_tcm: num_label.add_theme_font_override("font", _font_tcm)
	num_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(num_label)

	var date_label := Label.new()
	date_label.text = save.date if save else ("可用 / AVAILABLE" if is_zh else "AVAILABLE")
	date_label.anchor_right = 1.0
	date_label.offset_left = -260.0
	date_label.offset_top = 14.0
	date_label.offset_right = -16.0
	date_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	date_label.add_theme_font_size_override("font_size", 10)
	date_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.4))
	if _font_en_body: date_label.add_theme_font_override("font", _font_en_body)
	date_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(date_label)

	var title_label := Label.new()
	if save:
		title_label.text = save.title
	else:
		title_label.text = "空位" if is_zh else "EMPTY"
	title_label.offset_left = 16.0
	title_label.offset_top = 90.0
	title_label.add_theme_font_size_override("font_size", 24)
	if _font_zh_body: title_label.add_theme_font_override("font", _font_zh_body)
	title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(title_label)

	var detail_label := Label.new()
	if save:
		detail_label.text = save.player_name + "  •  " + save.plot_id.to_upper()
	else:
		detail_label.text = "点击存档" if is_zh else "Click to save"
	detail_label.offset_left = 16.0
	detail_label.offset_top = 120.0
	detail_label.add_theme_font_size_override("font_size", 10)
	detail_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.3))
	if _font_zh_body: detail_label.add_theme_font_override("font", _font_zh_body)
	detail_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(detail_label)

	container.mouse_entered.connect(_on_hover.bind(index))
	container.gui_input.connect(_on_click.bind(index))
	container.set_meta("sweep", sweep)
	container.set_meta("right_bar", right_bar)
	container.set_meta("bottom_bar", bottom_bar)
	container.set_meta("num_label", num_label)
	container.set_meta("date_label", date_label)
	container.set_meta("title_label", title_label)
	container.set_meta("detail_label", detail_label)

	return container


func _update_focus() -> void:
	for i: int in range(_slots_grid.get_child_count()):
		var slot: Control = _slots_grid.get_child(i)
		var is_focused: bool = i == _focused_slot_idx
		var sweep: ColorRect = slot.get_meta("sweep")
		var right_bar: ColorRect = slot.get_meta("right_bar")
		var bottom_bar: ColorRect = slot.get_meta("bottom_bar")
		var num_label: Label = slot.get_meta("num_label")
		var date_label: Label = slot.get_meta("date_label")
		var title_label: Label = slot.get_meta("title_label")
		var detail_label: Label = slot.get_meta("detail_label")

		var tween := create_tween().set_parallel(true)
		tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		tween.tween_property(sweep, "scale:x", 1.0 if is_focused else 0.0, 0.35)
		tween.tween_property(right_bar, "size:y", slot.size.y if is_focused else 0.0, 0.35)
		tween.tween_property(bottom_bar, "size:x", slot.size.x if is_focused else 0.0, 0.35)

		num_label.add_theme_color_override("font_color", Color.BLACK if is_focused else Color(1, 1, 1, 0.12))
		date_label.add_theme_color_override("font_color", Color(0, 0, 0, 0.5) if is_focused else Color(1, 1, 1, 0.4))
		title_label.add_theme_color_override("font_color", Color.BLACK if is_focused else Color.WHITE)
		detail_label.add_theme_color_override("font_color", Color(0, 0, 0, 0.5) if is_focused else Color(1, 1, 1, 0.3))


func _on_hover(idx: int) -> void:
	if _focused_slot_idx == idx: return
	_focused_slot_idx = idx
	_update_focus()


func _on_click(idx: int, event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		save_selected.emit(idx)


func _on_close() -> void:
	close_requested.emit()


func _input(event: InputEvent) -> void:
	if not visible or not event.is_pressed():
		return

	if event.is_action_pressed("ui_cancel"):
		close_requested.emit()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_up"):
		_focused_slot_idx = max(0, _focused_slot_idx - 2)
		_update_focus()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_down"):
		_focused_slot_idx = min(GameManager.MAX_SLOTS - 1, _focused_slot_idx + 2)
		_update_focus()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_left"):
		_focused_slot_idx = max(0, _focused_slot_idx - 1)
		_update_focus()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_right"):
		_focused_slot_idx = min(GameManager.MAX_SLOTS - 1, _focused_slot_idx + 1)
		_update_focus()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		save_selected.emit(_focused_slot_idx)
		get_viewport().set_input_as_handled()
