## PictureViewer : Control
## Fullscreen picture viewer for Scene Gallery.
## Displays a single background image, supports mouse-wheel zoom
## and arrow-key navigation through ALL images (flat list).
## ESC returns to the Scene Gallery.
extends Control

signal back_requested()

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------
var _entries: Array[Dictionary] = []   # [{file: String, name: String}]
var _current_index: int = 0
var _zoom_level: float = 1.0
var _disabled: bool = false
var _base_fit_scale: float = 1.0

# Font references
var _font_tcm: Font = null
var _font_zh_title: Font = null
var _font_zh_body: Font = null
var _font_en_body: Font = null

const MIN_ZOOM: float = 0.25
const MAX_ZOOM: float = 5.0
const ZOOM_STEP: float = 0.12

# ---------------------------------------------------------------------------
# Onready
# ---------------------------------------------------------------------------
@onready var _image_container: Control = %ImageContainer
@onready var _image_rect: TextureRect = %ImageViewer
@onready var _filename_label: Label = %FilenameLabel
@onready var _hint_prev_box: ColorRect = %HintPrevBox
@onready var _hint_prev_label: Label = %HintPrevLabel
@onready var _hint_prev_text: Label = %HintPrevText
@onready var _hint_next_box: ColorRect = %HintNextBox
@onready var _hint_next_label: Label = %HintNextLabel
@onready var _hint_next_text: Label = %HintNextText
@onready var _hint_esc_box: ColorRect = %HintEscBox
@onready var _hint_esc_label: Label = %HintEscLabel
@onready var _hint_esc_text: Label = %HintEscText


# ===================================================================
# Lifecycle
# ===================================================================

func _ready() -> void:
	_setup_hint_bar()
	_animate_enter()


func _on_enter() -> void:
	_disabled = false


func _on_exit() -> void:
	_disabled = true


# ===================================================================
# Public — called by SceneManager to pass entry data
# ===================================================================

func setup(entries: Array[Dictionary], start_index: int) -> void:
	_entries = entries
	_current_index = clampi(start_index, 0, maxi(0, _entries.size() - 1))
	_load_current_image()


# ===================================================================
# Image loading & display
# ===================================================================

func _load_current_image() -> void:
	if _entries.is_empty() or _current_index < 0 or _current_index >= _entries.size():
		return

	var entry: Dictionary = _entries[_current_index]
	var path: String = entry.file
	if path.is_empty():
		return

	if not ResourceLoader.exists(path):
		push_warning("PictureViewer: image not found — ", path)
		return

	var tex: Texture2D = load(path) as Texture2D
	if not tex:
		push_warning("PictureViewer: not a valid texture — ", path)
		return

	_image_rect.texture = tex
	_zoom_level = 1.0
	_update_image_transform()

	# Update filename label
	_filename_label.text = entry.name
	_filename_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.45))
	if _font_tcm: _filename_label.add_theme_font_override("font", _font_tcm)

	# Update hint bar visibility
	_update_hint_bar_visibility()


func _update_image_transform() -> void:
	var tex: Texture2D = _image_rect.texture
	if not tex:
		return

	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	var tex_size: Vector2 = tex.get_size()

	# Calculate the scale to fit the image within the viewport
	var fit_x: float = vp_size.x / tex_size.x
	var fit_y: float = vp_size.y / tex_size.y
	_base_fit_scale = minf(fit_x, fit_y)

	var display_size: Vector2 = tex_size * _base_fit_scale * _zoom_level

	_image_rect.size = display_size
	_image_rect.position = (vp_size - display_size) / 2.0


# ===================================================================
# Hint bar (bottom-right) — MusicGallery / KeyHintBar style
# ===================================================================

func _setup_hint_bar() -> void:
	_font_tcm = load(GameManager.FONT_TCM)
	_font_zh_title = load(GameManager.FONT_ZH_TITLE)
	_font_zh_body = load(GameManager.FONT_ZH_BODY)
	_font_en_body = load(GameManager.FONT_EN_BODY)

	var is_zh: bool = GameManager.is_locale("zh")

	# ── Previous key box ──
	_hint_prev_box.color = Color.WHITE
	_hint_prev_box.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_hint_prev_label.text = "←"
	_hint_prev_label.add_theme_color_override("font_color", Color.BLACK)
	_hint_prev_label.add_theme_font_size_override("font_size", 16)
	_hint_prev_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _font_tcm: _hint_prev_label.add_theme_font_override("font", _font_tcm)

	_hint_prev_text.text = tr("gallery_prev")
	_hint_prev_text.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
	_hint_prev_text.add_theme_font_size_override("font_size", 12)
	_hint_prev_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if is_zh:
		if _font_zh_title: _hint_prev_text.add_theme_font_override("font", _font_zh_title)
	elif _font_en_body:
		_hint_prev_text.add_theme_font_override("font", _font_en_body)

	# ── Next key box ──
	_hint_next_box.color = Color.WHITE
	_hint_next_box.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_hint_next_label.text = "→"
	_hint_next_label.add_theme_color_override("font_color", Color.BLACK)
	_hint_next_label.add_theme_font_size_override("font_size", 16)
	_hint_next_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _font_tcm: _hint_next_label.add_theme_font_override("font", _font_tcm)

	_hint_next_text.text = tr("gallery_next")
	_hint_next_text.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
	_hint_next_text.add_theme_font_size_override("font_size", 12)
	_hint_next_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if is_zh:
		if _font_zh_title: _hint_next_text.add_theme_font_override("font", _font_zh_title)
	elif _font_en_body:
		_hint_next_text.add_theme_font_override("font", _font_en_body)

	# ── ESC key box ──
	_hint_esc_box.color = Color.WHITE
	_hint_esc_box.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_hint_esc_label.text = "ESC"
	_hint_esc_label.add_theme_color_override("font_color", Color.BLACK)
	_hint_esc_label.add_theme_font_size_override("font_size", 13)
	_hint_esc_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _font_tcm: _hint_esc_label.add_theme_font_override("font", _font_tcm)

	_hint_esc_text.text = tr("gallery_exit")
	_hint_esc_text.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
	_hint_esc_text.add_theme_font_size_override("font_size", 12)
	_hint_esc_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if is_zh:
		if _font_zh_title: _hint_esc_text.add_theme_font_override("font", _font_zh_title)
	elif _font_en_body:
		_hint_esc_text.add_theme_font_override("font", _font_en_body)


func _update_hint_bar_visibility() -> void:
	var has_multiple: bool = _entries.size() > 1
	_hint_prev_box.visible = has_multiple
	_hint_prev_label.visible = has_multiple
	_hint_prev_text.visible = has_multiple
	_hint_next_box.visible = has_multiple
	_hint_next_label.visible = has_multiple
	_hint_next_text.visible = has_multiple


# ===================================================================
# Navigation
# ===================================================================

func _navigate(delta: int) -> void:
	if _entries.is_empty():
		return
	var new_idx: int = _current_index + delta
	if new_idx < 0 or new_idx >= _entries.size():
		return  # Don't wrap — stay at boundaries
	_current_index = new_idx
	_play_click()
	_load_current_image()


# ===================================================================
# Input — keyboard + mouse wheel
# ===================================================================

func _input(event: InputEvent) -> void:
	if _disabled:
		return

	# ── Mouse wheel zoom ──
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_zoom_level = minf(MAX_ZOOM, _zoom_level + ZOOM_STEP)
			_update_image_transform()
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_zoom_level = maxf(MIN_ZOOM, _zoom_level - ZOOM_STEP)
			_update_image_transform()
			get_viewport().set_input_as_handled()

	if not event.is_pressed():
		return

	# ── Keyboard navigation ──
	if event.is_action_pressed("ui_left") or event.is_action_pressed("ui_up"):
		_navigate(-1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_right") or event.is_action_pressed("ui_down"):
		_navigate(1)
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
	scale = Vector2(0.97, 0.97)
	var tween := create_tween().set_parallel(true)
	tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_EXPO)
	tween.tween_property(self, "modulate:a", 1.0, 0.6)
	tween.tween_property(self, "scale", Vector2(1.0, 1.0), 0.6)


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
