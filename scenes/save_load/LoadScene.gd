## LoadScene : Control
## Save/Load screen. 20 cards in a 2-column grid.
##
## Focus animation strategy:
##   1. fill.color tweens dark→white (0.4s QUINT) — the ONLY bg animation.
##   2. Text colors swap via add_theme_color_override after a short delay
##      (0.12s) so the white sweep has covered the text area before text
##      turns dark. On unfocus, text swaps back immediately.
##   3. Accent bars (right + bottom, 2px black) toggle instantly.
##   4. Card scale lifts 1.0→1.02.
extends Control

signal back_requested()
signal save_selected(save: SaveData)

var _slots: Array = []
var _focus_idx: int = 0
var _disabled: bool = false

var _font_tcm: Font
var _font_en_body: Font
var _font_zh_body: Font

const SLOT_WIDTH: float = 540.0
const SLOT_HEIGHT: float = 160.0
const GRID_COLS: int = 2
const GRID_GAP: float = 24.0

@onready var _title_label: Label = %TitleLabel
@onready var _subtitle_container: Control = %SubtitleContainer
@onready var _slots_grid: GridContainer = %SlotsGrid
@onready var _back_button: Control = %BackButton


func _ready() -> void:
	_setup()
	_animate_enter()


func setup(_bg: String = "") -> void:
	pass


func _setup() -> void:
	_font_tcm = load(GameManager.FONT_TCM)
	_font_en_body = load(GameManager.FONT_EN_BODY)
	_font_zh_body = load(GameManager.FONT_ZH_BODY)

	_title_label.text = "Archive"
	_title_label.add_theme_font_size_override("font_size", 72)
	if _font_tcm: _title_label.add_theme_font_override("font", _font_tcm)

	for c in _subtitle_container.get_children():
		c.queue_free()
	var sub := Label.new()
	sub.text = "Memory Matrix / 存储矩阵"
	sub.add_theme_font_size_override("font_size", 10)
	sub.add_theme_color_override("font_color", Color(1, 1, 1, 0.4))
	if _font_tcm: sub.add_theme_font_override("font", _font_tcm)
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_subtitle_container.add_child(sub)

	_slots_grid.add_theme_constant_override("h_separation", int(GRID_GAP))
	_slots_grid.add_theme_constant_override("v_separation", int(GRID_GAP))
	_slots_grid.columns = GRID_COLS
	_slots_grid.size_flags_horizontal = Control.SIZE_FILL
	_slots_grid.size_flags_vertical = Control.SIZE_FILL

	_slots = GameManager.get_save_slots()
	_create_slot_nodes()
	_setup_back_button()


func _create_slot_nodes() -> void:
	for i: int in range(GameManager.MAX_SLOTS):
		var c: Control = _make_card(i)
		_slots_grid.add_child(c)
	_update_focus()


func _make_card(idx: int) -> Control:
	var save: SaveData = _slots[idx] if idx < _slots.size() else null
	var is_zh := TranslationServer.get_locale().begins_with("zh")

	var card := Control.new()
	card.name = "Slot_" + str(idx)
	card.custom_minimum_size = Vector2(SLOT_WIDTH, SLOT_HEIGHT)
	card.mouse_filter = Control.MOUSE_FILTER_STOP

	# ── Layer 0: Background fill ──
	var fill := ColorRect.new()
	fill.name = "Fill"
	fill.color = Color(0, 0, 0, 0.55)
	fill.set_anchors_preset(Control.PRESET_FULL_RECT)
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(fill)

	# ── Layer 1: Right bar (2px black, focus only) ──
	var rbar := ColorRect.new()
	rbar.name = "RBar"
	rbar.color = Color.BLACK
	rbar.anchor_top = 0.0
	rbar.anchor_right = 1.0
	rbar.anchor_bottom = 1.0
	rbar.offset_left = -2.0
	rbar.visible = false
	rbar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(rbar)

	# ── Layer 1: Bottom bar (2px black, focus only) ──
	var bbar := ColorRect.new()
	bbar.name = "BBar"
	bbar.color = Color.BLACK
	bbar.anchor_left = 0.0
	bbar.anchor_right = 1.0
	bbar.anchor_bottom = 1.0
	bbar.offset_top = -2.0
	bbar.visible = false
	bbar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(bbar)

	# ── Layer 2: Watermark (52px, top-left, faint white) ──
	var wm := Label.new()
	wm.name = "WM"
	wm.text = "%02d" % (idx + 1)
	wm.position = Vector2(16, 8)
	wm.add_theme_font_size_override("font_size", 52)
	_set_label_color(wm, false, true)  # is_watermark=true
	if _font_tcm: wm.add_theme_font_override("font", _font_tcm)
	wm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(wm)

	# ── Layer 2: Date (10px, top-right) ──
	var dt := Label.new()
	dt.name = "DT"
	dt.text = save.date if save else "---- / -- / --"
	dt.anchor_right = 1.0
	dt.offset_left = -260.0
	dt.offset_right = -16.0
	dt.offset_top = 14.0
	dt.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	dt.add_theme_font_size_override("font_size", 10)
	_set_label_color(dt, false)
	if _font_en_body: dt.add_theme_font_override("font", _font_en_body)
	dt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(dt)

	# ── Layer 2: Title (24px serif, y=90) ──
	var tt := Label.new()
	tt.name = "TT"
	tt.position = Vector2(16, 90)
	tt.size = Vector2(SLOT_WIDTH - 32, 34)
	tt.clip_text = true
	tt.text = save.title if save else ("空位" if is_zh else "EMPTY")
	tt.add_theme_font_size_override("font_size", 24)
	_set_label_color(tt, false)
	if _font_zh_body: tt.add_theme_font_override("font", _font_zh_body)
	tt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(tt)

	# ── Layer 2: Detail (10px, y=126) ──
	var dl := Label.new()
	dl.name = "DL"
	dl.position = Vector2(16, 126)
	dl.text = ("SEC." + save.plot_id + " // " + save.player_name) if save else ("点击存档" if is_zh else "Click to save")
	dl.add_theme_font_size_override("font_size", 10)
	_set_label_color(dl, false)
	if _font_zh_body: dl.add_theme_font_override("font", _font_zh_body)
	dl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(dl)

	card.mouse_entered.connect(_on_hover.bind(idx))
	card.gui_input.connect(_on_click.bind(idx))
	card.set_meta("fill", fill)
	card.set_meta("rbar", rbar)
	card.set_meta("bbar", bbar)
	card.set_meta("wm", wm)
	card.set_meta("dt", dt)
	card.set_meta("tt", tt)
	card.set_meta("dl", dl)
	# tw meta not set initially (avoid has_meta error)
	return card


# ── Label color helper ─────────────────────────────────────

func _set_label_color(lbl: Label, focused: bool, is_watermark: bool = false) -> void:
	if focused:
		if is_watermark:
			lbl.add_theme_color_override("font_color", Color(0, 0, 0, 0.60))
		else:
			lbl.add_theme_color_override("font_color", Color.BLACK)
	else:
		if is_watermark:
			lbl.add_theme_color_override("font_color", Color(1, 1, 1, 0.15))
		else:
			lbl.add_theme_color_override("font_color", Color.WHITE)


# ── Focus ──────────────────────────────────────────────────

func _update_focus() -> void:
	for i: int in range(_slots_grid.get_child_count()):
		var card: Control = _slots_grid.get_child(i)
		var on: bool = i == _focus_idx

		var fill: ColorRect = card.get_meta("fill")
		var rbar: ColorRect = card.get_meta("rbar")
		var bbar: ColorRect = card.get_meta("bbar")
		var wm: Label = card.get_meta("wm")
		var dt: Label = card.get_meta("dt")
		var tt: Label = card.get_meta("tt")
		var dl: Label = card.get_meta("dl")

		# Kill previous tween
		var prev: Tween = card.get_meta("tw") if card.has_meta("tw") else null
		if prev and prev.is_valid():
			prev.kill()

		var tw := create_tween()
		tw.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
		card.set_meta("tw", tw)

		if on:
			# Focus IN: fill dark→white (0.4s)
			tw.tween_property(fill, "color", Color.WHITE, 0.4)
			# Swap text to dark AFTER sweep covers the text area (0.12s delay)
			tw.tween_callback(_swap_text.bind(card, true)).set_delay(0.12)
		else:
			# Focus OUT: fill white→dark (0.25s)
			tw.tween_property(fill, "color", Color(0, 0, 0, 0.55), 0.25)
			# Swap text to white immediately
			_swap_text(card, false)

		# Accent bars
		rbar.visible = on
		bbar.visible = on

		# Card lift
		var lt := create_tween()
		lt.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
		lt.tween_property(card, "scale",
			Vector2(1.02, 1.02) if on else Vector2(1, 1), 0.35)


func _swap_text(card: Control, focused: bool) -> void:
	var wm: Label = card.get_meta("wm")
	var dt: Label = card.get_meta("dt")
	var tt: Label = card.get_meta("tt")
	var dl: Label = card.get_meta("dl")
	_set_label_color(wm, focused, true)
	_set_label_color(dt, focused, false)
	_set_label_color(tt, focused, false)
	_set_label_color(dl, focused, false)


# ── Interaction ────────────────────────────────────────────

func _on_hover(idx: int) -> void:
	if _disabled or _focus_idx == idx:
		return
	_focus_idx = idx
	_update_focus()
	_play_click()


func _on_click(event: InputEvent, idx: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_confirm(idx)


func _confirm(idx: int) -> void:
	_play_click()
	var sv: SaveData = _slots[idx] if idx < _slots.size() else null
	if sv:
		save_selected.emit(sv)


# ── Back button ────────────────────────────────────────────

func _setup_back_button() -> void:
	_back_button.mouse_filter = Control.MOUSE_FILTER_STOP
	_back_button.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_back_button.offset_top = -96.0
	_back_button.offset_bottom = 0.0

	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.6)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_back_button.add_child(bg)

	var bd := ColorRect.new()
	bd.color = Color(1, 1, 1, 0.05)
	bd.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bd.size.y = 1
	bd.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_back_button.add_child(bd)

	var box := ColorRect.new()
	box.color = Color.WHITE
	box.size = Vector2(48, 48)
	box.position = Vector2(24, 24)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_back_button.add_child(box)

	var esc := Label.new()
	esc.text = "ESC"
	esc.position = Vector2(24, 24)
	esc.size = Vector2(48, 48)
	esc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	esc.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	esc.add_theme_color_override("font_color", Color.BLACK)
	esc.add_theme_font_size_override("font_size", 14)
	esc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_back_button.add_child(esc)

	var is_zh := TranslationServer.get_locale().begins_with("zh")
	var bl := Label.new()
	bl.text = "返回" if is_zh else "BACK"
	bl.position = Vector2(88, 28)
	bl.add_theme_color_override("font_color", Color(1, 1, 1, 0.8))
	bl.add_theme_font_size_override("font_size", 24)
	bl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_back_button.add_child(bl)

	var sl := Label.new()
	sl.text = "取消当前操作" if is_zh else "Cancel current operation"
	sl.position = Vector2(88, 58)
	sl.add_theme_color_override("font_color", Color(1, 1, 1, 0.2))
	sl.add_theme_font_size_override("font_size", 10)
	sl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_back_button.add_child(sl)

	_back_button.gui_input.connect(_on_back_click)
	_back_button.mouse_entered.connect(_on_back_hover.bind(true))
	_back_button.mouse_exited.connect(_on_back_hover.bind(false))
	_back_button.set_meta("box", box)
	_back_button.set_meta("esc", esc)


func _on_back_click(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_play_click()
		back_requested.emit()


func _on_back_hover(h: bool) -> void:
	var box: ColorRect = _back_button.get_meta("box")
	var esc: Label = _back_button.get_meta("esc")
	if box: box.color = Color.BLACK if h else Color.WHITE
	if esc: esc.add_theme_color_override("font_color", Color.WHITE if h else Color.BLACK)


func _play_click() -> void:
	AudioManager.play_sfx(AudioManager.SFX_CLICK)


# ── Enter animation ────────────────────────────────────────

func _animate_enter() -> void:
	modulate.a = 0.0
	scale = Vector2(0.98, 0.98)
	var tw := create_tween()
	tw.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_EXPO)
	tw.tween_property(self, "modulate:a", 1.0, 0.8)
	tw.parallel().tween_property(self, "scale", Vector2(1, 1), 0.8)
	for i: int in range(_slots_grid.get_child_count()):
		var c: Control = _slots_grid.get_child(i)
		c.modulate.a = 0.0
		var st := create_tween()
		st.tween_interval(i * 0.015)
		st.tween_property(c, "modulate:a", 1.0, 0.25).set_ease(Tween.EASE_OUT)


# ── Input ──────────────────────────────────────────────────

func _input(event: InputEvent) -> void:
	if _disabled or not event.is_pressed():
		return
	if event.is_action_pressed("ui_up"):
		_focus_idx = max(0, _focus_idx - GRID_COLS)
		_update_focus(); _play_click()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_down"):
		_focus_idx = min(GameManager.MAX_SLOTS - 1, _focus_idx + GRID_COLS)
		_update_focus(); _play_click()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_left"):
		_focus_idx = max(0, _focus_idx - 1)
		_update_focus(); _play_click()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_right"):
		_focus_idx = min(GameManager.MAX_SLOTS - 1, _focus_idx + 1)
		_update_focus(); _play_click()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel"):
		back_requested.emit()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		_confirm(_focus_idx)
		get_viewport().set_input_as_handled()


func set_disabled(v: bool) -> void:
	_disabled = v
