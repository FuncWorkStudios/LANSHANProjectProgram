## LoadScene : Control
## Save/Load screen with 20-slot grid, keyboard/grid navigation, and selection.
## Port of LoadScene from App.tsx — redesigned with bottom accent bars,
## font hierarchy, and staggered entry animation.
extends Control

signal back_requested()
signal save_selected(save: SaveData)

# ---------------------------------------------------------------------------
# Internal state
# ---------------------------------------------------------------------------
var _slots: Array = []
var _focus_idx: int = 0
var _disabled: bool = false
var _background_path: String = ""

var _font_tcm: Font

const SLOT_WIDTH: float = 400.0
const SLOT_HEIGHT: float = 160.0
const GRID_COLS: int = 2

@onready var _title_label: Label = %TitleLabel
@onready var _subtitle_container: Control = %SubtitleContainer
@onready var _slots_grid: GridContainer = %SlotsGrid
@onready var _back_button: Control = %BackButton


# ===================================================================
# Lifecycle
# ===================================================================

func _ready() -> void:
	_setup()
	_animate_enter()


func setup(bg_path: String = "") -> void:
	_background_path = bg_path


func _setup() -> void:
	_font_tcm = load("res://assets/fonts/TCM_____.TTF")
	_title_label.text = "Archive"
	_title_label.add_theme_font_size_override("font_size", 72)
	if _font_tcm: _title_label.add_theme_font_override("font", _font_tcm)
	_slots = GameManager.get_save_slots()
	_create_slot_nodes()
	_setup_back_button()


# ===================================================================
# Slot creation
# ===================================================================

func _create_slot_nodes() -> void:
	for i: int in range(GameManager.MAX_SLOTS):
		var slot_btn: Control = _create_slot_button(i)
		_slots_grid.add_child(slot_btn)
	_update_slot_focus()


func _create_slot_button(index: int) -> Control:
	var save: SaveData = _slots[index] if index < _slots.size() else null
	var is_zh: bool = GameManager.get_settings().language == "ZH"

	var container := Control.new()
	container.name = "Slot_" + str(index)
	container.custom_minimum_size = Vector2(SLOT_WIDTH, SLOT_HEIGHT)
	container.mouse_filter = Control.MOUSE_FILTER_STOP

	# --- Sweep background (explicit size, renders behind content) ---
	var sweep := ColorRect.new()
	sweep.name = "Sweep"
	sweep.color = Color.WHITE
	sweep.size = Vector2(SLOT_WIDTH, SLOT_HEIGHT)
	sweep.scale = Vector2(0, 1)
	sweep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(sweep)

	# --- Bottom accent bar (grows on focus) ---
	var accent_bar := ColorRect.new()
	accent_bar.name = "AccentBar"
	accent_bar.color = Color.BLACK
	accent_bar.size = Vector2(0, 2)
	accent_bar.position = Vector2(0, SLOT_HEIGHT - 2)
	accent_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(accent_bar)

	# --- Slot number: top-left, large, italic weight ---
	var num_label := Label.new()
	num_label.name = "Number"
	num_label.text = "%02d" % (index + 1)
	num_label.position = Vector2(16, 4)
	num_label.add_theme_font_size_override("font_size", 48)
	if _font_tcm: num_label.add_theme_font_override("font", _font_tcm)
	num_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.1))
	num_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(num_label)

	# --- Date: top-right, anchored right ---
	var date_label := Label.new()
	date_label.name = "Date"
	date_label.text = save.date if save else "-- / -- / --"
	date_label.anchor_right = 1.0
	date_label.offset_right = -16.0
	date_label.offset_top = 14.0
	date_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	date_label.add_theme_font_size_override("font_size", 11)
	date_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.4))
	date_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(date_label)

	# --- Title: bottom area, serif style ---
	var title_label := Label.new()
	title_label.name = "SlotTitle"
	if save:
		title_label.text = save.title
	else:
		title_label.text = "空位" if is_zh else "EMPTY"
	title_label.position = Vector2(16, 98)
	title_label.add_theme_font_size_override("font_size", 24)
	title_label.add_theme_color_override("font_color", Color.WHITE)
	title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(title_label)

	# --- Detail: player + scene info, below title ---
	var detail_label := Label.new()
	detail_label.name = "Detail"
	if save:
		detail_label.text = save.player_name + "  •  " + save.plot_id.to_upper()
	else:
		detail_label.text = "无可用同步数据" if is_zh else "NO SYNC DATA"
	detail_label.position = Vector2(16, 128)
	detail_label.add_theme_font_size_override("font_size", 10)
	detail_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.3))
	detail_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(detail_label)

	# --- Interaction ---
	container.mouse_entered.connect(_on_slot_hovered.bind(index))
	container.gui_input.connect(_on_slot_pressed_event.bind(index))
	container.set_meta("sweep", sweep)
	container.set_meta("accent_bar", accent_bar)
	container.set_meta("num_label", num_label)
	container.set_meta("date_label", date_label)
	container.set_meta("title_label", title_label)
	container.set_meta("detail_label", detail_label)

	return container


# ===================================================================
# Focus management
# ===================================================================

func _update_slot_focus() -> void:
	for i: int in range(_slots_grid.get_child_count()):
		var slot: Control = _slots_grid.get_child(i)
		var is_focused: bool = i == _focus_idx
		var sweep: ColorRect = slot.get_meta("sweep")
		var accent_bar: ColorRect = slot.get_meta("accent_bar")
		var num_label: Label = slot.get_meta("num_label")
		var date_label: Label = slot.get_meta("date_label")
		var title_label: Label = slot.get_meta("title_label")
		var detail_label: Label = slot.get_meta("detail_label")

		# Sweep width animation
		var sweep_tween := create_tween()
		sweep_tween.set_ease(Tween.EASE_OUT)
		sweep_tween.tween_property(sweep, "scale:x", 1.0 if is_focused else 0.0, 0.18)

		# Accent bar width animation
		var bar_tween := create_tween()
		bar_tween.set_ease(Tween.EASE_OUT)
		bar_tween.tween_property(accent_bar, "size:x", SLOT_WIDTH if is_focused else 0.0, 0.18)

		# Text colors swap on focus
		num_label.add_theme_color_override("font_color", Color.BLACK if is_focused else Color(1, 1, 1, 0.1))
		date_label.add_theme_color_override("font_color", Color(0, 0, 0, 0.5) if is_focused else Color(1, 1, 1, 0.4))
		title_label.add_theme_color_override("font_color", Color.BLACK if is_focused else Color.WHITE)
		detail_label.add_theme_color_override("font_color", Color(0, 0, 0, 0.5) if is_focused else Color(1, 1, 1, 0.3))


# ===================================================================
# Interaction
# ===================================================================

func _on_slot_hovered(index: int) -> void:
	if _disabled or _focus_idx == index:
		return
	_focus_idx = index
	_update_slot_focus()
	_play_click()


func _on_slot_pressed_event(index: int, event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_confirm_slot(index)


func _confirm_slot(index: int) -> void:
	_play_click()
	var save: SaveData = _slots[index] if index < _slots.size() else null
	if save:
		save_selected.emit(save)


# ===================================================================
# Back button bar
# ===================================================================

func _setup_back_button() -> void:
	_back_button.mouse_filter = Control.MOUSE_FILTER_STOP
	_back_button.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_back_button.offset_top = -96.0
	_back_button.offset_bottom = 0.0
	_back_button.size.y = 96

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
		_play_click()
		back_requested.emit()


func _on_back_bar_hovered(hovered: bool) -> void:
	var esc_box: ColorRect = _back_button.get_meta("esc_box")
	var esc_label: Label = _back_button.get_meta("esc_label")
	if esc_box:
		esc_box.color = Color.BLACK if hovered else Color.WHITE
	if esc_label:
		esc_label.add_theme_color_override("font_color", Color.WHITE if hovered else Color.BLACK)


# ===================================================================
# Audio
# ===================================================================

func _play_click() -> void:
	AudioManager.play_sfx("res://assets/Sfx/Choose.wav")


# ===================================================================
# Animation
# ===================================================================

func _animate_enter() -> void:
	modulate.a = 0.0
	scale = Vector2(0.98, 0.98)
	var tween := create_tween()
	tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_EXPO)
	tween.tween_property(self, "modulate:a", 1.0, 0.8)
	tween.parallel().tween_property(self, "scale", Vector2(1, 1), 0.8)

	# Stagger slot entries
	for i: int in range(_slots_grid.get_child_count()):
		var slot: Control = _slots_grid.get_child(i)
		slot.modulate.a = 0.0
		var stagger := create_tween()
		var delay: float = i * 0.01
		stagger.tween_interval(delay)
		stagger.tween_property(slot, "modulate:a", 1.0, 0.25).set_ease(Tween.EASE_OUT)


# ===================================================================
# Input
# ===================================================================

func _input(event: InputEvent) -> void:
	if _disabled or not event.is_pressed():
		return

	if event.is_action_pressed("ui_up"):
		_focus_idx = max(0, _focus_idx - GRID_COLS)
		_update_slot_focus()
		_play_click()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_down"):
		_focus_idx = min(GameManager.MAX_SLOTS - 1, _focus_idx + GRID_COLS)
		_update_slot_focus()
		_play_click()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_left"):
		_focus_idx = max(0, _focus_idx - 1)
		_update_slot_focus()
		_play_click()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_right"):
		_focus_idx = min(GameManager.MAX_SLOTS - 1, _focus_idx + 1)
		_update_slot_focus()
		_play_click()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel"):
		back_requested.emit()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		_confirm_slot(_focus_idx)
		get_viewport().set_input_as_handled()


# ===================================================================
# Public
# ===================================================================

func set_disabled(val: bool) -> void:
	_disabled = val
