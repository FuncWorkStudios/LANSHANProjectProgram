## BackgroundLayer : Control
## Persistent background layer — survives all scene transitions.
## Handles blur, parallax, auto-rotation crossfade, and image scaling.
extends Control

var _bg_rect: TextureRect = null
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


# ── Build ──────────────────────────────────────────────

func _build_layer() -> void:
	_bg_rect = TextureRect.new()
	_bg_rect.name = "BgImage"
	_bg_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bg_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_bg_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg_rect.scale = Vector2(1.12, 1.12)
	add_child(_bg_rect)

	# Darken overlay — on top of bg, toggled for sub-pages
	_darken_overlay = ColorRect.new()
	_darken_overlay.name = "DarkenOverlay"
	_darken_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_darken_overlay.color = Color(0, 0, 0, 0.0)
	_darken_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_darken_overlay)

	# Black overlay — topmost, for About page
	_black_overlay = ColorRect.new()
	_black_overlay.name = "BlackOverlay"
	_black_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_black_overlay.color = Color.BLACK
	_black_overlay.modulate.a = 0.0
	_black_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_black_overlay)


# ── Parallax (main menu option movement) ───────────────

func _on_parallax(x: float) -> void:
	if not _bg_rect:
		return
	if _parallax_tween and _parallax_tween.is_valid():
		_parallax_tween.kill()
	_parallax_tween = create_tween()
	_parallax_tween.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	_parallax_tween.tween_property(_bg_rect, "position:x", x, 0.8)


# ── Blur toggle with smooth transition ─────────────────

var _current_blur: float = 0.0

func _on_blur_toggle(enable: bool) -> void:
	if not _bg_rect:
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
			_bg_rect.material = _blur_material
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
	_bg_rect.material = null
	_blur_material = null
	_current_blur = 0.0


# ── Darken overlay for sub-pages ─────────────────────

func _on_darken_toggle(enable: bool) -> void:
	if not _darken_overlay: return
	if _darken_tween and _darken_tween.is_valid():
		_darken_tween.kill()
	_darken_tween = create_tween()
	_darken_tween.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	_darken_tween.tween_property(_darken_overlay, "color:a", 0.6 if enable else 0.0, 0.5)


# ── Black overlay for About page ─────────────────────

func _on_set_black() -> void:
	if not _black_overlay: return
	_black_overlay.modulate.a = 1.0


func _clear_black() -> void:
	if not _black_overlay: return
	_black_overlay.modulate.a = 0.0


func hide_background() -> void:
	# Fade out shared bg — used when VN takes over with its own VNBackground
	if _bg_rect and _bg_rect.texture:
		if _fade_tween and _fade_tween.is_valid():
			_fade_tween.kill()
		_fade_tween = create_tween()
		_fade_tween.tween_property(_bg_rect, "modulate:a", 0.0, 0.3)
		_fade_tween.tween_callback(_clear_texture)


func _clear_texture() -> void:
	if _bg_rect:
		_bg_rect.texture = null
		_bg_rect.modulate.a = 1.0


# ── Background switching ───────────────────────────────

func _apply_current() -> void:
	var path: String = GameManager.current_background
	if not path.is_empty() and ResourceLoader.exists(path):
		var tex: Texture2D = load(path)
		if tex:
			_bg_rect.modulate.a = 0.0
			_bg_rect.texture = tex
			var tw := create_tween()
			tw.tween_property(_bg_rect, "modulate:a", 1.0, 0.8)


func _on_bg_updated(path: String) -> void:
	if path.is_empty() or not ResourceLoader.exists(path):
		return
	var tex: Texture2D = load(path)
	if not tex or not _bg_rect:
		return

	if _fade_tween and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = create_tween()
	_fade_tween.tween_property(_bg_rect, "modulate:a", 0.0, 0.8)
	_fade_tween.tween_callback(_swap_texture.bind(tex))
	_fade_tween.tween_property(_bg_rect, "modulate:a", 1.0, 0.8)


func _swap_texture(tex: Texture2D) -> void:
	if _bg_rect:
		_bg_rect.texture = tex
