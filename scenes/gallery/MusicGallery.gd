## MusicGallery : Control
## Music gallery screen — 2-column card grid of all game music tracks.
## Click or press Enter to preview a track; click again to stop.
extends Control

signal back_requested()

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------
var _entries: Array[Dictionary] = []
var _focus_idx: int = 0
var _disabled: bool = false
var _playing_idx: int = -1
var _card_nodes: Array[Control] = []
var _back_button: Control = null
var _saved_bgm_path: String = ""

# Font references
var _font_tcm: Font = null
var _font_zh_title: Font = null
var _font_zh_body: Font = null
var _font_en_body: Font = null

const GRID_COLS: int = 2
const CARD_WIDTH: float = 540.0
const CARD_HEIGHT: float = 110.0
const GRID_GAP: float = 16.0

# ---------------------------------------------------------------------------
# Onready
# ---------------------------------------------------------------------------
@onready var _title_label: Label = %TitleLabel
@onready var _subtitle_container: Control = %SubtitleContainer
@onready var _tracks_grid: GridContainer = %TracksGrid
@onready var _grid_scroll: ScrollContainer = $GridScroll


# ===================================================================
# Lifecycle
# ===================================================================

func _ready() -> void:
	_setup()
	_animate_enter()


func _on_enter() -> void:
	_disabled = false
	_update_focus()


func _on_exit() -> void:
	_disabled = true
	# Stop any playing preview and restore menu mode before returning to achievements
	if _playing_idx >= 0:
		AudioManager.stop_bgm()
		AudioManager.set_menu_mode(true)
		if not _saved_bgm_path.is_empty():
			AudioManager.play_bgm(_saved_bgm_path, true)
			_saved_bgm_path = ""
		_set_playing_indicator(-1)


# ===================================================================
# Setup
# ===================================================================

func _setup() -> void:
	_font_tcm = load(GameManager.FONT_TCM)
	_font_zh_title = load(GameManager.FONT_ZH_TITLE)
	_font_zh_body = load(GameManager.FONT_ZH_BODY)
	_font_en_body = load(GameManager.FONT_EN_BODY)

	var is_zh: bool = GameManager.is_locale("zh")

	_title_label.text = "Music"
	_title_label.add_theme_font_size_override("font_size", 72)
	if _font_tcm: _title_label.add_theme_font_override("font", _font_tcm)

	# Subtitle
	for c: Node in _subtitle_container.get_children():
		c.queue_free()
	var sub := Label.new()
	sub.text = "游戏中出现的音乐 / Music Gallery"
	sub.add_theme_font_size_override("font_size", 10)
	sub.add_theme_color_override("font_color", Color(1, 1, 1, 0.4))
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if is_zh:
		if _font_zh_title: sub.add_theme_font_override("font", _font_zh_title)
	elif _font_tcm:
		sub.add_theme_font_override("font", _font_tcm)
	_subtitle_container.add_child(sub)

	# Grid setup
	_tracks_grid.add_theme_constant_override("h_separation", int(GRID_GAP))
	_tracks_grid.add_theme_constant_override("v_separation", int(GRID_GAP))
	_tracks_grid.columns = GRID_COLS
	_tracks_grid.size_flags_horizontal = Control.SIZE_FILL
	_tracks_grid.size_flags_vertical = Control.SIZE_FILL

	# Load entries from preloaded data
	var music_data: RefCounted = preload("res://scripts/gallery/MusicGalleryData.gd")
	_entries.assign(music_data.ENTRIES)

	_create_cards()
	_setup_back_button()


# ===================================================================
# Card creation
# ===================================================================

func _create_cards() -> void:
	for i: int in range(_entries.size()):
		var card: Control = _make_card(i)
		_tracks_grid.add_child(card)
		_card_nodes.append(card)
	_update_focus()


func _make_card(idx: int) -> Control:
	var entry: Dictionary = _entries[idx]
	var _is_zh: bool = GameManager.is_locale("zh")

	var card := Control.new()
	card.name = "Track_" + str(idx)
	card.custom_minimum_size = Vector2(CARD_WIDTH, CARD_HEIGHT)
	card.mouse_filter = Control.MOUSE_FILTER_STOP

	# ── Layer 0: Background fill ──
	var fill := ColorRect.new()
	fill.name = "Fill"
	fill.color = Color(0.15, 0.15, 0.15, 0.8)
	fill.set_anchors_preset(Control.PRESET_FULL_RECT)
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(fill)

	# ── Layer 1: Accent bars ──
	var rbar := ColorRect.new()
	rbar.name = "RBar"
	rbar.color = Color.BLACK
	rbar.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	rbar.size = Vector2(2, 0)
	rbar.visible = false
	rbar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(rbar)

	var bbar := ColorRect.new()
	bbar.name = "BBar"
	bbar.color = Color.BLACK
	bbar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bbar.offset_top = -2.0
	bbar.size = Vector2(0, 2)
	bbar.visible = false
	bbar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(bbar)

	# ── Layer 2: Track number watermark ──
	var num := Label.new()
	num.name = "Number"
	num.text = "%02d" % (idx + 1)
	num.position = Vector2(16, 20)
	num.size = Vector2(60, 52)
	num.add_theme_font_size_override("font_size", 52)
	num.add_theme_color_override("font_color", Color(1, 1, 1, 0.08))
	num.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _font_tcm: num.add_theme_font_override("font", _font_tcm)
	card.add_child(num)


	# ── Layer 4: Title EN ──
	var title_en := Label.new()
	title_en.name = "TitleEN"
	title_en.text = entry.title
	title_en.position = Vector2(88, 32)
	title_en.size = Vector2(CARD_WIDTH - 104, 30)
	title_en.add_theme_font_size_override("font_size", 26)
	title_en.add_theme_color_override("font_color", Color.WHITE)
	title_en.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _font_tcm: title_en.add_theme_font_override("font", _font_tcm)
	card.add_child(title_en)

	# ── Layer 5: Playing indicator ──
	var playing := Label.new()
	playing.name = "Playing"
	playing.text = "▶ NOW PLAYING"
	playing.position = Vector2(CARD_WIDTH - 200, 54)
	playing.size = Vector2(180, 20)
	playing.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	playing.add_theme_font_size_override("font_size", 14)
	playing.add_theme_color_override("font_color", Color(1, 1, 1, 0.65))
	playing.mouse_filter = Control.MOUSE_FILTER_IGNORE
	playing.visible = false
	if _font_tcm: playing.add_theme_font_override("font", _font_tcm)
	card.add_child(playing)

	# ── Store meta ──
	card.set_meta("fill", fill)
	card.set_meta("rbar", rbar)
	card.set_meta("bbar", bbar)
	card.set_meta("title_en", title_en)
	card.set_meta("playing", playing)
	card.set_meta("num", num)

	# ── Signals ──
	card.mouse_entered.connect(_on_hover.bind(idx))
	card.mouse_exited.connect(_on_unhover)
	card.gui_input.connect(_on_card_clicked.bind(idx))

	return card


# ===================================================================
# Focus & animation
# ===================================================================

func _update_focus(p_scroll: bool = false) -> void:
	if _card_nodes.is_empty():
		return
	if _focus_idx >= 0:
		_focus_idx = clampi(_focus_idx, 0, _card_nodes.size() - 1)

	for i: int in range(_card_nodes.size()):
		var card: Control = _card_nodes[i]
		var is_focused: bool = i == _focus_idx

		# Kill any running tweens on this card
		if card.has_meta("focus_tween"):
			var tw: Tween = card.get_meta("focus_tween") as Tween
			if tw and tw.is_valid():
				tw.kill()

		var fill: ColorRect = card.get_meta("fill")
		var rbar: ColorRect = card.get_meta("rbar")
		var bbar: ColorRect = card.get_meta("bbar")
		var _title_en: Label = card.get_meta("title_en")
		var _num: Label = card.get_meta("num")

		var target_fill: Color = Color(0.35, 0.35, 0.35, 0.85) if is_focused else Color(0.15, 0.15, 0.15, 0.8)
		var target_scale: float = 1.02 if is_focused else 1.0

		var t := create_tween().set_parallel(true)
		t.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
		t.tween_property(fill, "color", target_fill, 0.25)
		t.tween_property(card, "scale", Vector2(target_scale, target_scale), 0.2)


		rbar.visible = is_focused
		bbar.visible = is_focused

		card.set_meta("focus_tween", t)

	if p_scroll and _focus_idx >= 0:
		var focused_card: Control = _card_nodes[_focus_idx]
		_grid_scroll.ensure_control_visible(focused_card)



func _on_hover(index: int) -> void:
	if _disabled or _focus_idx == index:
		return
	_focus_idx = index
	_update_focus()
	_play_click()


func _on_unhover() -> void:
	if _disabled:
		return
	_focus_idx = -1
	_update_focus()


# ===================================================================
# Card interaction
# ===================================================================

func _on_card_clicked(event: InputEvent, index: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_toggle_play(index)


func _toggle_play(index: int) -> void:
	if _disabled:
		return
	_play_click()

	var entry: Dictionary = _entries[index]

	if _playing_idx == index:
		# Stop current preview — restore menu audio blur
		AudioManager.stop_bgm()
		AudioManager.set_menu_mode(true)
		if not _saved_bgm_path.is_empty():
			AudioManager.play_bgm(_saved_bgm_path, true)
			_saved_bgm_path = ""
		_set_playing_indicator(-1)
		return

	# Save current BGM before replacing it (only on first preview)
	if _playing_idx < 0:
		_saved_bgm_path = AudioManager._current_bgm_path
	# If switching from another track, stop previous first
	if _playing_idx >= 0:
		AudioManager.stop_bgm()

	# Enter preview mode — remove menu low-pass filter, play with loop
	AudioManager.set_menu_mode(false)
	var file: String = entry.file
	AudioManager.play_bgm(file, true)
	_set_playing_indicator(index)


func _set_playing_indicator(index: int) -> void:
	# Hide previous indicator
	if _playing_idx >= 0 and _playing_idx < _card_nodes.size():
		var old_card: Control = _card_nodes[_playing_idx]
		var old_playing: Label = old_card.get_meta("playing")
		if old_playing: old_playing.visible = false

	_playing_idx = index

	# Show new indicator
	if index >= 0 and index < _card_nodes.size():
		var new_card: Control = _card_nodes[index]
		var new_playing: Label = new_card.get_meta("playing")
		if new_playing: new_playing.visible = true


# ===================================================================
# Back button bar
# ===================================================================

func _setup_back_button() -> void:
	_back_button = Control.new()
	_back_button.name = "BackButton"
	_back_button.mouse_filter = Control.MOUSE_FILTER_STOP
	_back_button.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_back_button.offset_top = -96.0
	_back_button.offset_bottom = 0.0
	add_child(_back_button)

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
	border.offset_bottom = 1.0
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
	if _font_tcm: esc_label.add_theme_font_override("font", _font_tcm)
	_back_button.add_child(esc_label)

	var is_zh: bool = GameManager.is_locale("zh")
	var back_label := Label.new()
	back_label.name = "BackLabel"
	back_label.text = "返回" if is_zh else "BACK"
	back_label.position = Vector2(88, 28)
	back_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.8))
	back_label.add_theme_font_size_override("font_size", 24)
	back_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if is_zh:
		if _font_zh_title: back_label.add_theme_font_override("font", _font_zh_title)
	elif _font_tcm:
		back_label.add_theme_font_override("font", _font_tcm)
	_back_button.add_child(back_label)

	var sub_label := Label.new()
	sub_label.name = "SubLabel"
	sub_label.text = "返回成就页面" if is_zh else "Return to achievements"
	sub_label.position = Vector2(88, 58)
	sub_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.2))
	sub_label.add_theme_font_size_override("font_size", 10)
	sub_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if is_zh:
		if _font_zh_body: sub_label.add_theme_font_override("font", _font_zh_body)
	elif _font_en_body:
		sub_label.add_theme_font_override("font", _font_en_body)
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
	if esc_box: esc_box.color = Color.BLACK if hovered else Color.WHITE
	if esc_label: esc_label.add_theme_color_override("font_color", Color.WHITE if hovered else Color.BLACK)


# ===================================================================
# Input — keyboard navigation
# ===================================================================

func _input(event: InputEvent) -> void:
	if _disabled or not event.is_pressed():
		return

	if event.is_action_pressed("ui_up"):
		_focus_idx = maxi(0, _focus_idx - GRID_COLS)
		_update_focus(true)
		_play_click()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_down"):
		_focus_idx = mini(_card_nodes.size() - 1, _focus_idx + GRID_COLS)
		_update_focus(true)
		_play_click()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_left"):
		_focus_idx = maxi(0, _focus_idx - 1)
		_update_focus(true)
		_play_click()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_right"):
		_focus_idx = mini(_card_nodes.size() - 1, _focus_idx + 1)
		_update_focus(true)
		_play_click()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		_toggle_play(_focus_idx)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel"):
		_play_click()
		back_requested.emit()
		get_viewport().set_input_as_handled()


# ===================================================================
# Animation
# ===================================================================

func _animate_enter() -> void:
	modulate.a = 0.0
	scale = Vector2(0.98, 0.98)
	var tween := create_tween().set_parallel(true)
	tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_EXPO)
	tween.tween_property(self, "modulate:a", 1.0, 0.8)
	tween.tween_property(self, "scale", Vector2(1.0, 1.0), 0.8)


# ===================================================================
# Audio
# ===================================================================

func _play_click() -> void:
	AudioManager.play_click()


# ===================================================================
# Public
# ===================================================================

func set_disabled(val: bool) -> void:
	_disabled = val
