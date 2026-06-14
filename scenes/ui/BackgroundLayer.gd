## BackgroundLayer : Control
## Persistent background layer — survives all scene transitions.
## Handles blur, parallax, auto-rotation crossfade, and image scaling.
extends Control

var _bg_rect: TextureRect = null
var _fade_tween: Tween = null
var _blur_tween: Tween = null
var _blur_material: ShaderMaterial = null
var _parallax_tween: Tween = null


func _ready() -> void:
	EventBus.shared_background_updated.connect(_on_bg_updated)
	EventBus.bg_blur_toggle.connect(_on_blur_toggle)
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
	_bg_rect.scale = Vector2(1.12, 1.12)  # overscan for parallax without black edges
	add_child(_bg_rect)


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

func _on_blur_toggle(enable: bool) -> void:
	if not _bg_rect:
		return
	if _blur_tween and _blur_tween.is_valid():
		_blur_tween.kill()

	if enable:
		if not _blur_material:
			var shader: Shader = load("res://shaders/blur.gdshader")
			if not shader:
				return
			_blur_material = ShaderMaterial.new()
			_blur_material.shader = shader
			_blur_material.set_shader_parameter("blur_amount", 0.0)
			_bg_rect.material = _blur_material
		_blur_tween = create_tween()
		_blur_tween.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
		_blur_tween.tween_method(_set_blur_amount, 0.0, 12.0, 0.6)
	else:
		if _blur_material:
			_blur_tween = create_tween()
			_blur_tween.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
			_blur_tween.tween_method(_set_blur_amount, 12.0, 0.0, 0.4)
			_blur_tween.tween_callback(_clear_blur_material)


func _set_blur_amount(v: float) -> void:
	if _blur_material:
		_blur_material.set_shader_parameter("blur_amount", v)


func _clear_blur_material() -> void:
	_bg_rect.material = null
	_blur_material = null


# ── Background switching ───────────────────────────────

func _apply_current() -> void:
	var path: String = GameManager.current_background
	if not path.is_empty() and ResourceLoader.exists(path):
		var tex: Texture2D = load(path)
		if tex:
			_bg_rect.texture = tex


func _on_bg_updated(path: String) -> void:
	if path.is_empty() or not ResourceLoader.exists(path):
		return
	var tex: Texture2D = load(path)
	if not tex or not _bg_rect:
		return

	if _bg_rect.texture:
		if _fade_tween and _fade_tween.is_valid():
			_fade_tween.kill()
		_fade_tween = create_tween()
		_fade_tween.tween_property(_bg_rect, "modulate:a", 0.0, 0.35)
		_fade_tween.tween_callback(_swap_texture.bind(tex))
		_fade_tween.tween_property(_bg_rect, "modulate:a", 1.0, 0.35)
	else:
		_bg_rect.texture = tex


func _swap_texture(tex: Texture2D) -> void:
	if _bg_rect:
		_bg_rect.texture = tex
