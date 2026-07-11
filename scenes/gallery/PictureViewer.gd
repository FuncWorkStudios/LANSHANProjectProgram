## PictureViewer : Control
## 场景画廊的全屏图片查看器。
## 显示单个背景图像，支持鼠标滚轮缩放
## 和方向键在所有图像间导航（平面列表）。
## ESC 返回场景画廊。
extends Control

signal back_requested()

# ---------------------------------------------------------------------------
# 状态
# ---------------------------------------------------------------------------
var _entries: Array[Dictionary] = []   # [{file: String, name: String}]
var _current_index: int = 0
var _zoom_level: float = 1.0
var _disabled: bool = false
var _base_fit_scale: float = 1.0

# 字体引用
var _font_tcm: Font = null
var _font_zh_title: Font = null
var _font_zh_body: Font = null
var _font_en_body: Font = null

const MIN_ZOOM: float = 0.25
const MAX_ZOOM: float = 5.0
const ZOOM_STEP: float = 0.12

# ---------------------------------------------------------------------------
# Onready 节点引用
# ---------------------------------------------------------------------------
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
# 生命周期
# ===================================================================

func _ready() -> void:
	_setup_hint_bar()
	_animate_enter()


func _on_enter() -> void:
	_disabled = false
	_refresh_translations()


func _refresh_translations() -> void:
	_hint_prev_text.text = tr("上一个")
	_hint_prev_text.add_theme_font_override("font", GameManager.select_font(_hint_prev_text.text, _font_zh_title, _font_en_body))
	_hint_next_text.text = tr("下一个")
	_hint_next_text.add_theme_font_override("font", GameManager.select_font(_hint_next_text.text, _font_zh_title, _font_en_body))
	_hint_esc_text.text = tr("返回")
	_hint_esc_text.add_theme_font_override("font", GameManager.select_font(_hint_esc_text.text, _font_zh_title, _font_en_body))


func _on_exit() -> void:
	_disabled = true


# ===================================================================
# 公共接口 — 由 SceneManager 调用以传递条目数据
# ===================================================================

func setup(entries: Array[Dictionary], start_index: int) -> void:
	_entries = entries
	_current_index = clampi(start_index, 0, maxi(0, _entries.size() - 1))
	_load_current_image()


# ===================================================================
# 图像加载与显示
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

	# 更新文件名标签
	_filename_label.text = entry.name
	_filename_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.45))
	if _font_tcm: _filename_label.add_theme_font_override("font", _font_tcm)

	# 更新提示栏可见性
	_update_hint_bar_visibility()


func _update_image_transform() -> void:
	var tex: Texture2D = _image_rect.texture
	if not tex:
		return

	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	var tex_size: Vector2 = tex.get_size()

	# 计算使图像适应视口的缩放比例
	var fit_x: float = vp_size.x / tex_size.x
	var fit_y: float = vp_size.y / tex_size.y
	_base_fit_scale = minf(fit_x, fit_y)

	var display_size: Vector2 = tex_size * _base_fit_scale * _zoom_level

	_image_rect.size = display_size
	_image_rect.position = (vp_size - display_size) / 2.0


# ===================================================================
# 提示栏（右下角）— MusicGallery / KeyHintBar 风格
# ===================================================================

func _setup_hint_bar() -> void:
	_font_tcm = load(GameManager.FONT_TCM)
	_font_zh_title = load(GameManager.FONT_ZH_TITLE)
	_font_zh_body = load(GameManager.FONT_ZH_BODY)
	_font_en_body = load(GameManager.FONT_EN_BODY)


	# ── 上一个按键框 ──
	_hint_prev_box.color = Color.WHITE
	_hint_prev_box.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_hint_prev_label.text = "←"
	_hint_prev_label.add_theme_color_override("font_color", Color.BLACK)
	_hint_prev_label.add_theme_font_size_override("font_size", 16)
	_hint_prev_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _font_tcm: _hint_prev_label.add_theme_font_override("font", _font_tcm)

	_hint_prev_text.text = tr("上一个")
	_hint_prev_text.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
	_hint_prev_text.add_theme_font_size_override("font_size", 12)
	_hint_prev_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	@warning_ignore("static_called_on_instance")
	_hint_prev_text.add_theme_font_override("font", GameManager.select_font(_hint_prev_text.text, _font_zh_title, _font_en_body))

	# ── 下一个按键框 ──
	_hint_next_box.color = Color.WHITE
	_hint_next_box.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_hint_next_label.text = "→"
	_hint_next_label.add_theme_color_override("font_color", Color.BLACK)
	_hint_next_label.add_theme_font_size_override("font_size", 16)
	_hint_next_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _font_tcm: _hint_next_label.add_theme_font_override("font", _font_tcm)

	_hint_next_text.text = tr("下一个")
	_hint_next_text.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
	_hint_next_text.add_theme_font_size_override("font_size", 12)
	_hint_next_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	@warning_ignore("static_called_on_instance")
	_hint_next_text.add_theme_font_override("font", GameManager.select_font(_hint_next_text.text, _font_zh_title, _font_en_body))

	# ── ESC 按键框 ──
	_hint_esc_box.color = Color.WHITE
	_hint_esc_box.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_hint_esc_label.text = "ESC"
	_hint_esc_label.add_theme_color_override("font_color", Color.BLACK)
	_hint_esc_label.add_theme_font_size_override("font_size", 13)
	_hint_esc_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _font_tcm: _hint_esc_label.add_theme_font_override("font", _font_tcm)

	_hint_esc_text.text = tr("返回")
	_hint_esc_text.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
	_hint_esc_text.add_theme_font_size_override("font_size", 12)
	_hint_esc_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	@warning_ignore("static_called_on_instance")
	_hint_esc_text.add_theme_font_override("font", GameManager.select_font(_hint_esc_text.text, _font_zh_title, _font_en_body))


func _update_hint_bar_visibility() -> void:
	var has_multiple: bool = _entries.size() > 1
	_hint_prev_box.visible = has_multiple
	_hint_prev_label.visible = has_multiple
	_hint_prev_text.visible = has_multiple
	_hint_next_box.visible = has_multiple
	_hint_next_label.visible = has_multiple
	_hint_next_text.visible = has_multiple


# ===================================================================
# 导航
# ===================================================================

func _navigate(delta: int) -> void:
	if _entries.is_empty():
		return
	var new_idx: int = _current_index + delta
	if new_idx < 0 or new_idx >= _entries.size():
		return  # 不循环 — 停在边界处
	_current_index = new_idx
	_play_click()
	_load_current_image()


# ===================================================================
# 输入 — 键盘 + 鼠标滚轮
# ===================================================================

func _input(event: InputEvent) -> void:
	if _disabled:
		return

	# ── 鼠标滚轮缩放 ──
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

	# ── 键盘导航 ──
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
# 动画
# ===================================================================

func _animate_enter() -> void:
	modulate.a = 0.0
	scale = Vector2(0.97, 0.97)
	var tween := create_tween().set_parallel(true)
	tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_EXPO)
	tween.tween_property(self, "modulate:a", 1.0, 0.6)
	tween.tween_property(self, "scale", Vector2(1.0, 1.0), 0.6)


# ===================================================================
# 音频
# ===================================================================

func _play_click() -> void:
	AudioManager.play_click()


# ===================================================================
# 公共接口
# ===================================================================

func set_disabled(val: bool) -> void:
	_disabled = val
