## SceneGallery : Control
## Scene/background gallery screen — 2-column card grid styled
## like MusicGallery.  Scans assets/backgrounds/scenes/ at runtime
## and groups by filename prefix.  Clicking a card opens the
## PictureViewer for that image.
extends Control

signal back_requested()
signal picture_requested(entries: Array[Dictionary], start_index: int)

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------
var _groups: Array[Dictionary] = []
var _all_cards: Array[Control] = []       # flat list for focus tracking
var _card_entries: Array[Dictionary] = [] # [{file, name, group_files, group_index}]
var _focus_idx: int = 0
var _disabled: bool = false

const GRID_COLS: int = 2
const CARD_WIDTH: float = 540.0
const CARD_HEIGHT: float = 110.0
const GRID_GAP: float = 16.0
const SECTION_GAP: float = 28.0

# ---------------------------------------------------------------------------
# Onready
# ---------------------------------------------------------------------------
@onready var _title_label: Label = %TitleLabel
@onready var _subtitle_container: Control = %SubtitleContainer
@onready var _content_container: VBoxContainer = %ContentContainer
@onready var _gallery_scroll: ScrollContainer = $GalleryScroll


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


# ===================================================================
# Setup
# ===================================================================

func _setup() -> void:
	_title_label.text = tr("scene_gallery_title")
	_title_label.add_theme_font_size_override("font_size", 72)
	_title_label.add_theme_font_override("font", GameManager.font_title)

	# Subtitle
	for c: Node in _subtitle_container.get_children():
		c.queue_free()
	var sub := Label.new()
	sub.text = tr("scene_gallery_sub")
	sub.add_theme_font_size_override("font_size", 10)
	sub.add_theme_color_override("font_color", Color(1, 1, 1, 0.4))
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sub.add_theme_font_override("font", GameManager.font_body)
	_subtitle_container.add_child(sub)

	# Load groups from SceneGalleryData
	var scene_data: RefCounted = preload("res://scripts/gallery/SceneGalleryData.gd")
	_groups.assign(scene_data.get_grouped_scenes())

	_create_sections()
	_setup_back_button()


# ===================================================================
# Section building
# ===================================================================

func _create_sections() -> void:
	for g: Dictionary in _groups:
		var files: Array[Dictionary] = g.files as Array[Dictionary]
		if files.is_empty():
			continue

		# Spacer before section (except first)
		if _content_container.get_child_count() > 0:
			var spacer := Control.new()
			spacer.name = "Spacer"
			spacer.custom_minimum_size = Vector2(0, SECTION_GAP)
			spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_content_container.add_child(spacer)

		# Section header
		var header := _make_section_header(g.group_id)
		_content_container.add_child(header)

		# 2-column card grid (MusicGallery style)
		var grid := GridContainer.new()
		grid.name = "Grid_" + g.group_id
		grid.columns = GRID_COLS
		grid.add_theme_constant_override("h_separation", int(GRID_GAP))
		grid.add_theme_constant_override("v_separation", int(GRID_GAP))
		grid.size_flags_horizontal = Control.SIZE_FILL
		_content_container.add_child(grid)

		for file_idx: int in range(files.size()):
			var f: Dictionary = files[file_idx]
			# Build enriched entry with group context for navigation
			var card_entry: Dictionary = {
				"file": f.file,
				"name": f.name,
				"group_files": files,
				"group_index": file_idx,
			}
			var card: Control = _make_card(card_entry)
			grid.add_child(card)
			_all_cards.append(card)
			_card_entries.append(card_entry)


func _make_section_header(group_id: String) -> Control:
	var header := Control.new()
	header.name = "Header_" + group_id
	header.custom_minimum_size = Vector2(0, 40)
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Dot indicator
	var dot := ColorRect.new()
	dot.name = "Dot"
	dot.color = Color.WHITE
	dot.size = Vector2(6, 6)
	dot.position = Vector2(4, 6)
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(dot)

	# Group label
	var label := Label.new()
	label.name = "Label"
	label.text = tr("scene_group_" + group_id)
	label.position = Vector2(20, 6)
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", GameManager.font_body_cjk)
	header.add_child(label)

	return header


# ===================================================================
# Card creation (MusicGallery style)
# ===================================================================

func _make_card(entry: Dictionary) -> Control:
	var card := Control.new()
	card.name = "Card_" + entry.name
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

	# ── Layer 2: Scene name as ZH title ──
	var title_zh := Label.new()
	title_zh.name = "TitleZH"
	title_zh.text = entry.name
	title_zh.position = Vector2(88, 24)
	title_zh.size = Vector2(CARD_WIDTH - 104, 24)
	title_zh.add_theme_font_size_override("font_size", 22)
	title_zh.add_theme_color_override("font_color", Color.WHITE)
	title_zh.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_zh.clip_text = true
	title_zh.add_theme_font_override("font", GameManager.font_title)
	card.add_child(title_zh)

	# ── Layer 3: File path hint as EN subtitle ──
	var title_en := Label.new()
	title_en.name = "TitleEN"
	title_en.text = entry.file.trim_prefix("res://assets/backgrounds/scenes/")
	title_en.position = Vector2(88, 54)
	title_en.size = Vector2(CARD_WIDTH - 104, 18)
	title_en.add_theme_font_size_override("font_size", 13)
	title_en.add_theme_color_override("font_color", Color(1, 1, 1, 0.45))
	title_en.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_en.clip_text = true
	title_en.add_theme_font_override("font", GameManager.font_body)
	card.add_child(title_en)

	# ── Layer 4: Variant number watermark ──
	var num := Label.new()
	num.name = "Number"
	num.text = "%02d" % (entry.group_index + 1)
	num.position = Vector2(16, 20)
	num.size = Vector2(60, 52)
	num.add_theme_font_size_override("font_size", 52)
	num.add_theme_color_override("font_color", Color(1, 1, 1, 0.08))
	num.mouse_filter = Control.MOUSE_FILTER_IGNORE
	num.add_theme_font_override("font", GameManager.font_title)
	card.add_child(num)

	# ── Store meta ──
	card.set_meta("fill", fill)
	card.set_meta("rbar", rbar)
	card.set_meta("bbar", bbar)
	card.set_meta("title_zh", title_zh)
	card.set_meta("title_en", title_en)
	card.set_meta("num", num)

	# ── Signals ──
	var idx: int = _all_cards.size()  # index before this card is appended
	card.mouse_entered.connect(_on_hover.bind(idx))
	card.gui_input.connect(_on_card_clicked.bind(idx))

	return card


# ===================================================================
# Focus & animation
# ===================================================================

func _update_focus(p_scroll: bool = false) -> void:
	if _all_cards.is_empty():
		return
	_focus_idx = clampi(_focus_idx, 0, _all_cards.size() - 1)

	for i: int in range(_all_cards.size()):
		var card: Control = _all_cards[i]
		var is_focused: bool = i == _focus_idx

		# Kill any running tweens on this card
		if card.has_meta("focus_tween"):
			var tw: Tween = card.get_meta("focus_tween") as Tween
			if tw and tw.is_valid():
				tw.kill()

		var fill: ColorRect = card.get_meta("fill")
		var rbar: ColorRect = card.get_meta("rbar")
		var bbar: ColorRect = card.get_meta("bbar")
		var _title_zh: Label = card.get_meta("title_zh")
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
		var focused_card: Control = _all_cards[_focus_idx]
		_gallery_scroll.ensure_control_visible(focused_card)


func _on_hover(index: int) -> void:
	if _disabled or _focus_idx == index:
		return
	_focus_idx = index
	_update_focus()
	_play_click()


# ===================================================================
# Card interaction
# ===================================================================

func _on_card_clicked(event: InputEvent, index: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_open_picture_viewer(index)


func _open_picture_viewer(index: int) -> void:
	if _disabled:
		return
	if index < 0 or index >= _card_entries.size():
		return

	_play_click()

	var entry: Dictionary = _card_entries[index]
	var group_files: Array[Dictionary] = entry.get("group_files", []) as Array[Dictionary]
	var group_index: int = entry.get("group_index", 0)

	if group_files.is_empty():
		return

	picture_requested.emit(group_files, group_index)


# ===================================================================
# Back button bar (shared pattern from MusicGallery / AchievementsScene)
# ===================================================================

var _back_button: Control = null

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
	esc_label.add_theme_font_override("font", GameManager.font_title)
	_back_button.add_child(esc_label)

	var back_label := Label.new()
	back_label.name = "BackLabel"
	back_label.text = tr("back")
	back_label.position = Vector2(88, 28)
	back_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.8))
	back_label.add_theme_font_size_override("font_size", 24)
	back_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	back_label.add_theme_font_override("font", GameManager.font_title)
	_back_button.add_child(back_label)

	var sub_label := Label.new()
	sub_label.name = "SubLabel"
	sub_label.text = tr("gallery_back_sub")
	sub_label.position = Vector2(88, 58)
	sub_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.2))
	sub_label.add_theme_font_size_override("font_size", 10)
	sub_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sub_label.add_theme_font_override("font", GameManager.font_body)
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
		_focus_idx = mini(_all_cards.size() - 1, _focus_idx + GRID_COLS)
		_update_focus(true)
		_play_click()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_left"):
		_focus_idx = maxi(0, _focus_idx - 1)
		_update_focus(true)
		_play_click()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_right"):
		_focus_idx = mini(_all_cards.size() - 1, _focus_idx + 1)
		_update_focus(true)
		_play_click()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		_open_picture_viewer(_focus_idx)
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
