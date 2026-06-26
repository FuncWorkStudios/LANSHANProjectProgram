## BackgroundLayer : Control
## Persistent background layer — survives all scene transitions.
## Uses A/B dual TextureRects for flicker-free crossfade (no empty gap
## visible behind the darken overlay during auto-rotation).
## Handles blur, parallax, auto-rotation crossfade, and image scaling.
extends Control

# ── A/B dual TextureRects for flicker-free crossfade ──
var _bg_a: TextureRect = null
var _bg_b: TextureRect = null
var _active_bg: int = 0  # 0 = a visible, 1 = b visible

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
	_bg_a = _make_bg_rect("BgImageA")
	_bg_a.modulate.a = 1.0
	add_child(_bg_a)

	_bg_b = _make_bg_rect("BgImageB")
	_bg_b.modulate.a = 0.0
	add_child(_bg_b)

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


func _make_bg_rect(p_name: String) -> TextureRect:
	var r := TextureRect.new()
	r.name = p_name
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.scale = Vector2(1.15, 1.15)
	return r


## Return the currently-visible TextureRect.
func _active_rect() -> TextureRect:
	return _bg_a if _active_bg == 0 else _bg_b


## Return the hidden TextureRect (ready to receive new texture).
func _inactive_rect() -> TextureRect:
	return _bg_b if _active_bg == 0 else _bg_a


## Return both rects as an array.
func _both_rects() -> Array[TextureRect]:
	return [_bg_a, _bg_b]


# ── Parallax (main menu option movement) ───────────────

func _on_parallax(x: float) -> void:
	var active: TextureRect = _active_rect()
	if not active:
		return
	if _parallax_tween and _parallax_tween.is_valid():
		_parallax_tween.kill()
	_parallax_tween = create_tween()
	_parallax_tween.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	_parallax_tween.tween_property(active, "position:x", x, 0.8)


# ── Blur toggle with smooth transition ─────────────────

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
		# Apply material to both rects — covers crossfade period
		_bg_a.material = _blur_material
		_bg_b.material = _blur_material
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
	_bg_b.material = null
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


# ── Background switching — A/B crossfade ──────────────────

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




func _swap_active() -> void:
	_active_bg = 1 - _active_bg
	# Clear old texture from the now-inactive rect so it doesn't
	# keep a reference, and reset its alpha for next use.
	var inactive: TextureRect = _inactive_rect()
	inactive.texture = null
	inactive.modulate.a = 1.0
	_fade_tween = null


func _on_bg_updated(path: String) -> void:
	if path.is_empty() or not ResourceLoader.exists(path):
		return
	var tex: Texture2D = load(path)
	if not tex:
		return

	# Don't interrupt an active crossfade — the tween callback
	# (_swap_active) needs to fire to keep state consistent.
	if _fade_tween and _fade_tween.is_valid():
		if _fade_tween.has_meta("is_crossfade"):
			return
		_fade_tween.kill()

	var active: TextureRect = _active_rect()

	# First load: just fade in (no crossfade needed)
	if active.texture == null or active.modulate.a < 0.01:
		active.texture = tex
		_fade_tween = create_tween()
		_fade_tween.tween_property(active, "modulate:a", 1.0, 0.35)
		return

	# ── A/B crossfade: old fades out while new fades in ──
	var inactive: TextureRect = _inactive_rect()
	inactive.texture = tex
	inactive.modulate.a = 0.0

	_fade_tween = create_tween().set_parallel(true)
	_fade_tween.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	_fade_tween.tween_property(active, "modulate:a", 0.0, 0.35)
	_fade_tween.tween_property(inactive, "modulate:a", 1.0, 0.35)
	_fade_tween.tween_callback(_swap_active)
	_fade_tween.set_meta("is_crossfade", true)

