## VNBackground : Control
## 双层背景，支持 A/B 交叉淡入淡出和鼠标驱动的视差。
## 替换单个 TextureRect — 作为 VNInterface 的子节点实例化。
class_name VNBackground
extends Control

# ---------------------------------------------------------------------------
# 用于无缝交叉淡入淡出的双层背景
# ---------------------------------------------------------------------------
var _layer_a: TextureRect
var _layer_b: TextureRect
var _active_layer: TextureRect   # 当前可见的层
var _inactive_layer: TextureRect # 下一轮交叉淡入淡出的备用层
var _current_bg: String = ""
var _crossfade_tween: Tween = null

# ---------------------------------------------------------------------------
# 黑色叠加层 — 用于场景过渡的淡入/淡出黑色
# ---------------------------------------------------------------------------
var _black_overlay: ColorRect
var _black_tween: Tween = null

# ---------------------------------------------------------------------------
# 视差状态
# ---------------------------------------------------------------------------
var _mouse_pos: Vector2 = Vector2.ZERO
var _parallax_target: Vector2 = Vector2.ZERO
# 最大视差摆动 = 75 px — 与主菜单的选择驱动视差相同的总范围。
# 37.5 × 2 = 75 px 边到边。
const PARALLAX_RANGE: float = 37.5
const PARALLAX_SPEED: float = 900.0
var _viewport_size: Vector2 = Vector2.ZERO
var _setup_done: bool = false


# ===================================================================
# 生命周期
# ===================================================================

func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	set_anchors_preset(PRESET_FULL_RECT)

	_layer_a = _make_layer()
	_layer_b = _make_layer()
	_layer_b.modulate.a = 0.0
	_active_layer = _layer_a
	_inactive_layer = _layer_b

# 场景过渡的黑色叠加层（开始时隐藏）
	_black_overlay = ColorRect.new()
	_black_overlay.color = Color.BLACK
	_black_overlay.modulate.a = 0.0
	_black_overlay.set_anchors_preset(PRESET_FULL_RECT)
	_black_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_black_overlay)


func _make_layer() -> TextureRect:
	@warning_ignore("shadowed_variable_base_class")
	var tr := TextureRect.new()
	@warning_ignore("int_as_enum_without_cast", "int_as_enum_without_match")
	tr.layout_mode = 0
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	add_child(tr)
	move_child(tr, 0)  # 位于所有内容之后
	return tr


# ===================================================================
# 公共 API
# ===================================================================

## 设置背景图像，从当前图像交叉淡入淡出。
func set_bg(path: String) -> void:
	var normalized: String = _normalize_path(path)
	if normalized == _current_bg:
		return

	var texture: Texture2D = _load_texture(normalized)
	if not texture:
		return

	_current_bg = normalized
	_kill_crossfade()

# 加载到非活动层，然后交叉淡入淡出
	_inactive_layer.texture = texture
	_apply_parallax_sizing(_inactive_layer)
	_inactive_layer.modulate.a = 0.0

	_crossfade_tween = create_tween().set_parallel(true)
	_crossfade_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_crossfade_tween.tween_property(_active_layer, "modulate:a", 0.0, 1.2)
	_crossfade_tween.tween_property(_inactive_layer, "modulate:a", 1.0, 1.2)

# 交换
	var prev: TextureRect = _active_layer
	_active_layer = _inactive_layer
	_inactive_layer = prev


## 重置 — 为新游戏或读档清除所有状态。
func reset() -> void:
	_kill_crossfade()
	_current_bg = ""
	_active_layer.texture = null
	_active_layer.modulate.a = 1.0
	_inactive_layer.texture = null
	_inactive_layer.modulate.a = 0.0


## 清除为黑色（无背景）。
func clear_bg() -> void:
	_kill_crossfade()
	_current_bg = ""
	_active_layer.texture = null
	_inactive_layer.texture = null
	_active_layer.modulate.a = 1.0
	_inactive_layer.modulate.a = 0.0


## 每帧提供鼠标位置用于视差。
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

# 使用线性逼近驱动两个层（避免 lerp 渐近爬行）
	_active_layer.position = _active_layer.position.move_toward(_parallax_target, PARALLAX_SPEED * delta)
	_inactive_layer.position = _inactive_layer.position.move_toward(_parallax_target, PARALLAX_SPEED * delta)


# ===================================================================
# 内部
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
# 裸文件名或相对路径 — 尝试使用 AssetResolver 解析背景
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
# 场景过渡 — 淡入/淡出黑色
# ===================================================================

## 在 @duration 秒内将全屏淡入黑色。
func fade_to_black(duration: float = 1.0) -> void:
	_kill_black_tween()
	_black_tween = create_tween()
	_black_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_black_tween.tween_property(_black_overlay, "modulate:a", 1.0, duration)


## 从黑色淡出回到当前背景。
func fade_from_black(duration: float = 1.0) -> void:
	_kill_black_tween()
	_black_tween = create_tween()
	_black_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_black_tween.tween_property(_black_overlay, "modulate:a", 0.0, duration)


## 立即设置为全黑（无动画）。
func set_black() -> void:
	_kill_black_tween()
	_black_overlay.modulate.a = 1.0


func _kill_black_tween() -> void:
	if _black_tween and _black_tween.is_valid():
		_black_tween.kill()
	_black_tween = null
