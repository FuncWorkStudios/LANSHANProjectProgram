## BackgroundLayer : Control
## 持久背景层 — 在所有场景过渡中保留。
## 使用两个 TextureRect：一个活跃显示，一个备用。
## 处理模糊、视差、平滑过渡和图像缩放。
extends Control

# ── 双 TextureRect ──
var _bg_a: TextureRect = null
var _bg_b: TextureRect = null

var _fade_tween: Tween = null
var _blur_tween: Tween = null
var _blur_material: ShaderMaterial = null
var _parallax_tween: Tween = null
var _darken_overlay: ColorRect = null
var _darken_tween: Tween = null
var _black_overlay: ColorRect = null


func _ready() -> void:
	EventBus.shared_background_updated.connect(_on_bg_updated)
	EventBus.bg_blur_toggle.connect(_on_blur_toggle)
	EventBus.bg_darken_toggle.connect(_on_darken_toggle)
	EventBus.bg_set_black.connect(_on_set_black)
	EventBus.bg_parallax_offset.connect(_on_parallax)
	_build_layer()
	_apply_current()


# ── 构建 ──────────────────────────────────────────────

func _build_layer() -> void:
	_bg_a = _make_bg_rect("BgImageA")
	_bg_a.modulate.a = 1.0
	add_child(_bg_a)

	_bg_b = _make_bg_rect("BgImageB")
	_bg_b.modulate.a = 0.0
	add_child(_bg_b)

	# 变暗叠加层 — 在背景之上，为子页面切换
	_darken_overlay = ColorRect.new()
	_darken_overlay.name = "DarkenOverlay"
	_darken_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_darken_overlay.color = Color(0, 0, 0, 0.0)
	_darken_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_darken_overlay)

	# 黑色叠加层 — 最顶层，用于关于页面
	_black_overlay = ColorRect.new()
	_black_overlay.name = "BlackOverlay"
	_black_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_black_overlay.color = Color.BLACK
	_black_overlay.modulate.a = 0.0
	_black_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_black_overlay)


func _make_bg_rect(p_name: String) -> TextureRect:
	var r := TextureRect.new()
	r.name = p_name
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.scale = Vector2(1.15, 1.15)
	return r


## 返回当前显示背景的 TextureRect（始终为 _bg_a）。
func _active_rect() -> TextureRect:
	return _bg_a


## 将纹理设置到活跃 rect 上（在 fade_tween 回调中使用）。
func _set_bg_texture(tex: Texture2D) -> void:
	_bg_a.texture = tex


# ── 视差（主菜单选项移动） ───────────────

func _on_parallax(x: float) -> void:
	var active: TextureRect = _active_rect()
	if not active:
		return
	if _parallax_tween and _parallax_tween.is_valid():
		_parallax_tween.kill()
	_parallax_tween = create_tween()
	_parallax_tween.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	_parallax_tween.tween_property(active, "position:x", x, 0.8)


# ── 带平滑过渡的模糊切换 ─────────────────

var _current_blur: float = 0.0

func _on_blur_toggle(enable: bool) -> void:
	var active: TextureRect = _active_rect()
	if not active:
		return
	if _blur_tween and _blur_tween.is_valid():
		_blur_tween.kill()

	if enable:
		if not _blur_material:
			var shader: Shader = load("res://shaders/blur.gdshader")
			if not shader: return
			_blur_material = ShaderMaterial.new()
			_blur_material.shader = shader
			_blur_material.set_shader_parameter("blur_amount", _current_blur)
		_bg_a.material = _blur_material
		_blur_tween = create_tween()
		_blur_tween.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
		_blur_tween.tween_method(_set_blur_amount, _current_blur, 12.0, 0.6)
		_current_blur = 12.0
	else:
		if _blur_material:
			_blur_tween = create_tween()
			_blur_tween.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
			_blur_tween.tween_method(_set_blur_amount, _current_blur, 0.0, 0.4)
			_blur_tween.tween_callback(_clear_blur_material)
		_current_blur = 0.0


func _set_blur_amount(v: float) -> void:
	if _blur_material:
		_blur_material.set_shader_parameter("blur_amount", v)


func _clear_blur_material() -> void:
	_bg_a.material = null
	_blur_material = null
	_current_blur = 0.0


# ── 子页面的变暗叠加层 ─────────────────────

func _on_darken_toggle(enable: bool) -> void:
	if not _darken_overlay: return
	if _darken_tween and _darken_tween.is_valid():
		_darken_tween.kill()
	_darken_tween = create_tween()
	_darken_tween.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	_darken_tween.tween_property(_darken_overlay, "color:a", 0.6 if enable else 0.0, 0.5)


# ── 关于页面的黑色叠加层 ─────────────────────

func _on_set_black() -> void:
	if not _black_overlay: return
	_black_overlay.modulate.a = 1.0


func _clear_black() -> void:
	if not _black_overlay: return
	_black_overlay.modulate.a = 0.0


func hide_background() -> void:
# 淡出共享背景 — 当 VN 使用自己的 VNBackground 接管时使用
	var active: TextureRect = _active_rect()
	if active and active.texture:
		if _fade_tween and _fade_tween.is_valid():
			_fade_tween.kill()
		_fade_tween = create_tween()
		_fade_tween.tween_property(active, "modulate:a", 0.0, 0.3)
		_fade_tween.tween_callback(_clear_texture)


func _clear_texture() -> void:
	var active: TextureRect = _active_rect()
	if active:
		active.texture = null
		active.modulate.a = 1.0


# ── 背景切换 — 参照 MainMenu 的顺序淡入淡出 ──────────

func _apply_current() -> void:
	var path: String = GameManager.current_background
	if not path.is_empty() and ResourceLoader.exists(path):
		var tex: Texture2D = load(path)
		if tex:
			var active: TextureRect = _active_rect()
			if active.texture == null:
				active.modulate.a = 0.0
				active.texture = tex
				var tw := create_tween()
				tw.tween_property(active, "modulate:a", 1.0, 0.35)
			else:
				active.texture = tex


func _on_bg_updated(path: String) -> void:
	if path.is_empty() or not ResourceLoader.exists(path):
		return
	var tex: Texture2D = load(path)
	if not tex:
		return

	# 如果 fade tween 正在运行则不要打断
	if _fade_tween and _fade_tween.is_valid():
		return

	var active: TextureRect = _active_rect()

	# 首次加载：直接设置纹理并淡入
	if active.texture == null:
		active.texture = tex
		active.modulate.a = 0.0
		_fade_tween = create_tween()
		_fade_tween.tween_property(active, "modulate:a", 1.0, 0.35)
		return

	# 顺序淡入淡出：淡出 → 切换纹理 → 淡入（与 MainMenu 相同的可靠方案）
	_fade_tween = create_tween()
	_fade_tween.tween_property(active, "modulate:a", 0.0, 0.35)
	_fade_tween.tween_callback(_set_bg_texture.bind(tex))
	_fade_tween.tween_property(active, "modulate:a", 1.0, 0.35)
