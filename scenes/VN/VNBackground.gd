## VNBackground : Control
## Dual-layer background with A/B crossfade and mouse-driven parallax.
## Replace a single TextureRect — instantiate as child of VNInterface.
class_name VNBackground
extends Control

# ---------------------------------------------------------------------------
# Dual background layers for seamless crossfade
# ---------------------------------------------------------------------------
var _layer_a: TextureRect
var _layer_b: TextureRect
var _active_layer: TextureRect   # currently-visible layer
var _inactive_layer: TextureRect # standby for next crossfade
var _current_bg: String = ""
var _crossfade_tween: Tween = null

# ---------------------------------------------------------------------------
# Black overlay — fade to / from black for scene transitions
# ---------------------------------------------------------------------------
var _black_overlay: ColorRect
var _black_tween: Tween = null

# ---------------------------------------------------------------------------
# Parallax state
# ---------------------------------------------------------------------------
var _mouse_pos: Vector2 = Vector2.ZERO
var _parallax_target: Vector2 = Vector2.ZERO
# Max parallax swing = 75 px — same total range as the main menu's
# selection-driven parallax.  37.5 × 2 = 75 px edge-to-edge.
const PARALLAX_RANGE: float = 37.5
const PARALLAX_SPEED: float = 220.0
var _viewport_size: Vector2 = Vector2.ZERO
var _setup_done: bool = false


# ===================================================================
# Lifecycle
# ===================================================================

func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	set_anchors_preset(PRESET_FULL_RECT)

	_layer_a = _make_layer()
	_layer_b = _make_layer()
	_layer_b.modulate.a = 0.0
	_active_layer = _layer_a
	_inactive_layer = _layer_b

	# Black overlay for scene transitions (starts hidden)
	_black_overlay = ColorRect.new()
	_black_overlay.color = Color.BLACK
	_black_overlay.modulate.a = 0.0
	_black_overlay.set_anchors_preset(PRESET_FULL_RECT)
	_black_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_black_overlay)


func _make_layer() -> TextureRect:
	var tr := TextureRect.new()
	@warning_ignore("int_as_enum_without_cast", "int_as_enum_without_match")
	tr.layout_mode = 0
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	add_child(tr)
	move_child(tr, 0)  # behind everything
	return tr


# ===================================================================
# Public API
# ===================================================================

## Set the background image, crossfading from the current one.
func set_bg(path: String) -> void:
	var normalized: String = _normalize_path(path)
	if normalized == _current_bg:
		return

	var texture: Texture2D = _load_texture(normalized)
	if not texture:
		return

	_current_bg = normalized
	_kill_crossfade()

	# Load onto inactive layer, then crossfade
	_inactive_layer.texture = texture
	_apply_parallax_sizing(_inactive_layer)
	_inactive_layer.modulate.a = 0.0

	_crossfade_tween = create_tween().set_parallel(true)
	_crossfade_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_crossfade_tween.tween_property(_active_layer, "modulate:a", 0.0, 1.2)
	_crossfade_tween.tween_property(_inactive_layer, "modulate:a", 1.0, 1.2)

	# Swap
	var prev: TextureRect = _active_layer
	_active_layer = _inactive_layer
	_inactive_layer = prev


## Reset — clear all state for a new game or load.
func reset() -> void:
	_kill_crossfade()
	_current_bg = ""
	_active_layer.texture = null
	_active_layer.modulate.a = 1.0
	_inactive_layer.texture = null
	_inactive_layer.modulate.a = 0.0


## Clear to black (no background).
func clear_bg() -> void:
	_kill_crossfade()
	_current_bg = ""
	_active_layer.texture = null
	_inactive_layer.texture = null
	_active_layer.modulate.a = 1.0
	_inactive_layer.modulate.a = 0.0


## Feed mouse position each frame for parallax.
func update_parallax(mouse_pos: Vector2, viewport_size: Vector2, delta: float) -> void:
	_mouse_pos = mouse_pos
	_viewport_size = viewport_size

	if not _setup_done and viewport_size.x > 0:
		_setup_done = true
		_apply_parallax_sizing(_layer_a)
		_apply_parallax_sizing(_layer_b)

	if viewport_size.x <= 0:
		return

	var center: Vector2 = viewport_size / 2.0
	var ratio: Vector2 = (_mouse_pos - center) / center
	var base_pos: Vector2 = -(viewport_size * 0.09)
	_parallax_target = base_pos + ratio * PARALLAX_RANGE

	# Drive both layers with linear approach (avoids lerp asymptotic creep)
	_active_layer.position = _active_layer.position.move_toward(_parallax_target, PARALLAX_SPEED * delta)
	_inactive_layer.position = _inactive_layer.position.move_toward(_parallax_target, PARALLAX_SPEED * delta)


# ===================================================================
# Internal
# ===================================================================

func _apply_parallax_sizing(layer: TextureRect) -> void:
	var vs: Vector2 = _viewport_size
	if vs.x <= 0:
		return
	var overscan: Vector2 = vs * 0.18
	layer.size = vs + overscan
	layer.position = -(vs * 0.09)


func _kill_crossfade() -> void:
	if _crossfade_tween and _crossfade_tween.is_valid():
		_crossfade_tween.kill()
	_crossfade_tween = null


func _normalize_path(path: String) -> String:
	if path.is_empty(): return path
	if path.begins_with("/Assests/"): return "res://assets/" + path.substr(9)
	if path.begins_with("/Assets/"): return "res://assets/" + path.substr(8)
	if path.begins_with("res://"): return path
	# Bare filename or relative path — try AssetResolver for backgrounds
	if not "/" in path:
		var resolved: String = AssetResolver.resolve_bg(path)
		if resolved != path and ResourceLoader.exists(resolved):
			return resolved
	return path


func _load_texture(path: String) -> Texture2D:
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	var res := load(path)
	if res is Texture2D:
		return res
	return null


# ===================================================================
# Scene transition — fade to / from black
# ===================================================================

## Fade the full screen to black over @duration seconds.
func fade_to_black(duration: float = 1.0) -> void:
	_kill_black_tween()
	_black_tween = create_tween()
	_black_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_black_tween.tween_property(_black_overlay, "modulate:a", 1.0, duration)


## Fade from black back to the current background.
func fade_from_black(duration: float = 1.0) -> void:
	_kill_black_tween()
	_black_tween = create_tween()
	_black_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_black_tween.tween_property(_black_overlay, "modulate:a", 0.0, duration)


## Instantly set to full black (no animation).
func set_black() -> void:
	_kill_black_tween()
	_black_overlay.modulate.a = 1.0


func _kill_black_tween() -> void:
	if _black_tween and _black_tween.is_valid():
		_black_tween.kill()
	_black_tween = null
