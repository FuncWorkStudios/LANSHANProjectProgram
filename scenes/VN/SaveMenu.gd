## SaveMenu : Control
## In-game save overlay. Same slot-card design as LoadScene.
extends Control

signal close_requested()
signal save_selected(slot_index: int)

var _slots: Array = []
var _focus_idx: int = 0
var _anim_tween: Tween = null

var _font_tcm: Font
var _font_en_body: Font
var _font_zh_body: Font
var _font_zh_title: Font

const SLOT_W: float = 540.0
const SLOT_H: float = 160.0
const COLS: int = 2
const GAP: float = 24.0

@onready var _backdrop: ColorRect = $Backdrop
@onready var _title_label: Label = $TitleLabel
@onready var _slots_grid: GridContainer = $Scroll/SlotsGrid
@onready var _close_btn: Button = $CloseBtn
@onready var _hint_bar: Control = $HintBar
@onready var _scroll: ScrollContainer = $Scroll


func open(fonts: Dictionary, _hint: String = "") -> void:
	_font_tcm = fonts.get("tcm")
	_font_zh_body = fonts.get("zh_body")
	_font_zh_title = fonts.get("zh_title")
	_font_en_body = fonts.get("en_body")
	_focus_idx = 0
	_refresh()
	if _close_btn:
		_close_btn.visible = false
		if _font_tcm: _close_btn.add_theme_font_override("font", _font_tcm)
	_animate_in()


func close_animated() -> void:
	_kill_anim()
	_anim_tween = create_tween().set_parallel(true)
	_anim_tween.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	_anim_tween.tween_property(_backdrop, "modulate:a", 0.0, 0.25)
	_anim_tween.tween_property(self, "modulate:a", 0.0, 0.25)
	_anim_tween.tween_callback(_on_close_done)


func _refresh() -> void:
	_title_label.text = "Archive"
	_title_label.add_theme_font_size_override("font_size", 72)
	if _font_tcm: _title_label.add_theme_font_override("font", _font_tcm)

	_slots_grid.add_theme_constant_override("h_separation", int(GAP))
	_slots_grid.add_theme_constant_override("v_separation", int(GAP))
	_slots_grid.columns = COLS
	_slots_grid.size_flags_horizontal = Control.SIZE_FILL
	_slots_grid.size_flags_vertical = Control.SIZE_FILL

	for c in _slots_grid.get_children():
		c.queue_free()

	_slots = GameManager.get_save_slots()
	for i: int in range(GameManager.MAX_SLOTS):
		_slots_grid.add_child(_make_card(i))
	_update_focus()


func _make_card(idx: int) -> Control:
	var save: SaveData = _slots[idx] if idx < _slots.size() else null
	var is_zh := GameManager.is_locale("zh")

	var card := Control.new()
	card.name = "Slot_" + str(idx)
	card.custom_minimum_size = Vector2(SLOT_W, SLOT_H)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.pivot_offset = Vector2(SLOT_W / 2.0, SLOT_H / 2.0)

	var fill := ColorRect.new()
	fill.name = "Fill"
	fill.color = Color(0.15, 0.15, 0.15, 0.8)
	fill.set_anchors_preset(Control.PRESET_FULL_RECT)
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(fill)

	var rbar := ColorRect.new()
	rbar.name = "RBar"
	rbar.color = Color.BLACK
	rbar.anchor_top = 0.0; rbar.anchor_right = 1.0; rbar.anchor_bottom = 1.0
	rbar.offset_left = -2.0
	rbar.visible = false
	rbar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(rbar)

	var bbar := ColorRect.new()
	bbar.name = "BBar"
	bbar.color = Color.BLACK
	bbar.anchor_left = 0.0; bbar.anchor_right = 1.0; bbar.anchor_bottom = 1.0
	bbar.offset_top = -2.0
	bbar.visible = false
	bbar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(bbar)

	var wm := Label.new()
	wm.text = "%02d" % (idx + 1)
	wm.position = Vector2(16, 8)
	wm.add_theme_font_size_override("font_size", 52)
	wm.add_theme_color_override("font_color", Color(1, 1, 1, 0.2))
	if _font_tcm: wm.add_theme_font_override("font", _font_tcm)
	wm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(wm)

	var dt := Label.new()
	dt.text = save.date if save else "---- / -- / --"
	dt.anchor_right = 1.0
	dt.offset_left = -260.0; dt.offset_right = -16.0; dt.offset_top = 14.0
	dt.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	dt.add_theme_font_size_override("font_size", 10)
	dt.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
	if _font_en_body: dt.add_theme_font_override("font", _font_en_body)
	dt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(dt)

	var tt := Label.new()
	tt.position = Vector2(16, 74)
	tt.size = Vector2(SLOT_W - 32, 28)
	tt.clip_text = true
	tt.text = save.title if save else ("空位" if is_zh else "EMPTY")
	tt.add_theme_font_size_override("font_size", 22)
	tt.add_theme_color_override("font_color", Color(1, 1, 1, 0.92))
	# Chapter title — use title-level fonts
	if is_zh:
		if _font_zh_title: tt.add_theme_font_override("font", _font_zh_title)
	elif _font_tcm:
		tt.add_theme_font_override("font", _font_tcm)
	tt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(tt)

	# Dialogue line — shows where in the story this save was made
	var dialogue_label := Label.new()
	dialogue_label.position = Vector2(16, 104)
	dialogue_label.size = Vector2(SLOT_W - 32, 20)
	dialogue_label.clip_text = true
	dialogue_label.text = save.desc if save else ""
	dialogue_label.add_theme_font_size_override("font_size", 13)
	dialogue_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.65))
	if is_zh:
		if _font_zh_body: dialogue_label.add_theme_font_override("font", _font_zh_body)
	elif _font_en_body:
		dialogue_label.add_theme_font_override("font", _font_en_body)
	dialogue_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(dialogue_label)

	var dl := Label.new()
	dl.position = Vector2(16, 130)
	dl.text = ("SEC." + save.plot_id + " // " + save.player_name) if save else ("点击存档" if is_zh else "Click to save")
	dl.add_theme_font_size_override("font_size", 10)
	dl.add_theme_color_override("font_color", Color(1, 1, 1, 0.45))
	if is_zh:
		if _font_zh_body: dl.add_theme_font_override("font", _font_zh_body)
	elif _font_en_body:
		dl.add_theme_font_override("font", _font_en_body)
	dl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(dl)

	card.mouse_entered.connect(_on_hover.bind(idx))
	card.gui_input.connect(_on_click.bind(idx))
	card.set_meta("fill", fill)
	card.set_meta("rbar", rbar); card.set_meta("bbar", bbar)
	card.set_meta("wm", wm); card.set_meta("dt", dt)
	card.set_meta("tt", tt); card.set_meta("dl", dl)
	return card

func _update_focus(p_scroll: bool = false) -> void:
	for i: int in range(_slots_grid.get_child_count()):
		var card: Control = _slots_grid.get_child(i)
		var on: bool = (i == _focus_idx)
		_animate_card(card, on)

		# Auto-scroll only for keyboard navigation — mouse hover should not jump the view
		if on and p_scroll and _scroll:
			_scroll.ensure_control_visible(card)


## Animate a single card to focused / unfocused state.
## Each card owns its tween via metadata so killing one card's
## tween never interrupts another card's animation.
func _animate_card(card: Control, on: bool) -> void:
	var fill: ColorRect = card.get_meta("fill")
	var rbar: ColorRect = card.get_meta("rbar")
	var bbar: ColorRect = card.get_meta("bbar")

	# Kill any in-progress tween on this specific card
	if card.has_meta("focus_tween"):
		var old: Tween = card.get_meta("focus_tween")
		if old and old.is_valid():
			old.kill()

	var tw := create_tween().set_parallel(true)
	tw.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)

	var target_fill: Color = Color(0.35, 0.35, 0.35, 0.85) if on else Color(0.15, 0.15, 0.15, 0.8)
	tw.tween_property(fill, "color", target_fill, 0.2)

	rbar.visible = on
	bbar.visible = on

	tw.tween_property(card, "scale", Vector2(1.015, 1.015) if on else Vector2(1, 1), 0.2)

	card.set_meta("focus_tween", tw)




func _on_hover(idx: int) -> void:
	if _focus_idx == idx: return
	_focus_idx = idx
	_update_focus()
	_play_click()


func _on_click(event: InputEvent, idx: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_play_click()
		save_selected.emit(idx)


func _on_close() -> void:
	close_animated()


func _animate_in() -> void:
	visible = true
	modulate.a = 1.0
	_setup_hint_bar()
	_kill_anim()
	_backdrop.modulate.a = 0.0
	modulate.a = 0.0
	_anim_tween = create_tween().set_parallel(true)
	_anim_tween.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	_anim_tween.tween_property(_backdrop, "modulate:a", 1.0, 0.4)
	_anim_tween.tween_property(self, "modulate:a", 1.0, 0.35)
	for i: int in range(_slots_grid.get_child_count()):
		var c: Control = _slots_grid.get_child(i)
		c.modulate.a = 0.0
		var st := create_tween()
		st.tween_interval(i * 0.015)
		st.tween_property(c, "modulate:a", 1.0, 0.25).set_ease(Tween.EASE_OUT)


func _on_close_done() -> void:
	visible = false
	modulate.a = 1.0
	close_requested.emit()


var _back_bar: Control = null
var _back_esc_box: ColorRect = null
var _back_esc_label: Label = null


func _setup_hint_bar() -> void:
	if _back_bar:  # already created — VNInterface caches SaveMenu
		return
	if _hint_bar:
		_hint_bar.visible = false
	var is_zh: bool = GameManager.is_locale("zh")
	_back_bar = Control.new()
	_back_bar.name = "BackBar"
	_back_bar.mouse_filter = Control.MOUSE_FILTER_STOP
	_back_bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_back_bar.offset_top = -96.0
	_back_bar.offset_bottom = 0.0
	add_child(_back_bar)

	var bar_bg := ColorRect.new()
	bar_bg.color = Color(0, 0, 0, 0.6)
	bar_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_back_bar.add_child(bar_bg)

	var border := ColorRect.new()
	border.color = Color(1, 1, 1, 0.05)
	border.set_anchors_preset(Control.PRESET_TOP_WIDE)
	border.offset_bottom = 1.0
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_back_bar.add_child(border)

	_back_esc_box = ColorRect.new()
	_back_esc_box.color = Color.WHITE
	_back_esc_box.size = Vector2(48, 48)
	_back_esc_box.position = Vector2(24, 24)
	_back_esc_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_back_bar.add_child(_back_esc_box)

	_back_esc_label = Label.new()
	_back_esc_label.text = "ESC"
	_back_esc_label.position = Vector2(24, 24)
	_back_esc_label.size = Vector2(48, 48)
	_back_esc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_back_esc_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_back_esc_label.add_theme_color_override("font_color", Color.BLACK)
	_back_esc_label.add_theme_font_size_override("font_size", 14)
	_back_esc_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _font_tcm: _back_esc_label.add_theme_font_override("font", _font_tcm)
	_back_bar.add_child(_back_esc_label)

	var back_label := Label.new()
	back_label.text = "返回" if is_zh else "BACK"
	back_label.position = Vector2(88, 26)
	back_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.8))
	back_label.add_theme_font_size_override("font_size", 16)
	back_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if is_zh:
		if _font_zh_title: back_label.add_theme_font_override("font", _font_zh_title)
	elif _font_tcm:
		back_label.add_theme_font_override("font", _font_tcm)
	_back_bar.add_child(back_label)

	var sub_label := Label.new()
	sub_label.text = "取消当前操作" if is_zh else "Cancel current operation"
	sub_label.position = Vector2(88, 50)
	sub_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.3))
	sub_label.add_theme_font_size_override("font_size", 12)
	sub_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if is_zh:
		if _font_zh_body: sub_label.add_theme_font_override("font", _font_zh_body)
	elif _font_en_body:
		sub_label.add_theme_font_override("font", _font_en_body)
	_back_bar.add_child(sub_label)

	_back_bar.gui_input.connect(_on_back_bar_clicked)
	_back_bar.mouse_entered.connect(_on_back_hover.bind(true))
	_back_bar.mouse_exited.connect(_on_back_hover.bind(false))


func _on_back_bar_clicked(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_play_click()
		_on_close()


func _on_back_hover(hovered: bool) -> void:
	if not _back_esc_box or not _back_esc_label: return
	_back_esc_box.color = Color.BLACK if hovered else Color.WHITE
	_back_esc_label.add_theme_color_override("font_color", Color.WHITE if hovered else Color.BLACK)


func _kill_anim() -> void:
	if _anim_tween and _anim_tween.is_valid():
		_anim_tween.kill()
	_anim_tween = null


func _input(event: InputEvent) -> void:
	if not visible or not event.is_pressed(): return
	if event.is_action_pressed("ui_cancel"):
		close_animated()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_up"):
		_focus_idx = max(0, _focus_idx - COLS)
		_update_focus(true); _play_click()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_down"):
		_focus_idx = min(GameManager.MAX_SLOTS - 1, _focus_idx + COLS)
		_update_focus(true); _play_click()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_left"):
		_focus_idx = max(0, _focus_idx - 1)
		_update_focus(true); _play_click()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_right"):
		_focus_idx = min(GameManager.MAX_SLOTS - 1, _focus_idx + 1)
		_update_focus(true); _play_click()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		_play_click()
		save_selected.emit(_focus_idx)
		get_viewport().set_input_as_handled()

	if event is InputEventMouseButton and _scroll:
		var bar: ScrollBar = _scroll.get_v_scroll_bar()
		var target: float = bar.value
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			target = max(bar.min_value, bar.value - 200.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			target = min(bar.max_value, bar.value + 200.0)
		if target != bar.value:
			var tw := create_tween()
			tw.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
			tw.tween_property(_scroll, "scroll_vertical", target, 0.35)


func _play_click() -> void:
	AudioManager.play_click()
