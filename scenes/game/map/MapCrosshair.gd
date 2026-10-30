## MapCrosshair : Control
## 地图「选中地点」的十字准星 —— 运行时由 Map.gd 动态创建（非场景节点）。
##
## 挂在 MapContainer 里（层级压在贴图之上、地点标记之下），但每帧用反向变换抵消
## 地图的平移 / 缩放：线本身固定于屏幕、横平竖直，不随地图移动、也不随缩放变粗，
## 只有交点 center 按地图变换解算，落在选中地点的屏幕位置上。
##
## 视觉：
##   黑线横贯整个屏幕，透明度沿线段变化 —— 屏幕边缘最实，越靠近交点越透明，
##   在标点周围自动留出一圈干净留白，线不会压住标记和标签。
##
## 一次选中 = 一个新准星：四臂从屏幕四边同时向内伸展；退场时四臂缩回四边并淡出，
## 动画结束后自毁。
class_name MapCrosshair
extends Control

const GROW_TIME: float = 0.55
const RETRACT_TIME: float = 0.3

## 线条以屏幕像素计（反向变换后本地单位 == 屏幕像素，与地图缩放无关）
const CORE_WIDTH: float = 2
const CORE_COLOR := Color(0.0, 0.0, 0.0, 1.0)

## 透明度剖面：边缘（最实）→ 中段 → 交点（全透明）
const ALPHA_EDGE: float = 0.9
const ALPHA_MID: float = 0.42
const ALPHA_CORE: float = 0.0
## 剖面拐点位置（整条臂的百分比）
const ALPHA_SPLIT: float = 0.5

# ---------------------------------------------------------------------------
# 状态
# ---------------------------------------------------------------------------

## 地图容器 —— 用来抵消其变换，并把地点坐标换算成屏幕坐标
var map_container: Control = null
## 地图裁剪区 —— 准星线铺满它的尺寸（= 整个屏幕）
var view_clip: Control = null
## 选中地点的地图坐标
var world_pos: Vector2 = Vector2.ZERO
## 交点屏幕坐标（已对齐像素中心，只读）
var center: Vector2 = Vector2.ZERO

## 四臂伸展进度：0 = 贴在屏幕四边，1 = 交于交点
var arm: float = 0.0:
	set(value):
		arm = clampf(value, 0.0, 1.0)
		queue_redraw()

## 整体不透明度
var alpha: float = 1.0:
	set(value):
		alpha = clampf(value, 0.0, 1.0)
		queue_redraw()

var _anim: Tween = null


# ===================================================================
# 生命周期
# ===================================================================

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sync_layout()
	_sync_center()
	queue_redraw()


func _process(_delta: float) -> void:
	_sync_layout()
	_sync_center()


## 抵消 MapContainer 的平移 / 缩放 —— 本地坐标 == 屏幕坐标，
## 因此线宽恒为屏幕像素，地图缩小放大都不会变粗变细。
func _sync_layout() -> void:
	if map_container == null:
		return
	var s: float = maxf(map_container.scale.x, 0.0001)
	position = -map_container.position / s
	scale = Vector2(1.0 / s, 1.0 / s)
	if view_clip != null and size != view_clip.size:
		size = view_clip.size


## 交点 = 选中地点在地图变换下的屏幕坐标。
## 顺便对齐像素：奇数宽线落半像素、偶数宽线落整像素，两条边缘都正好压在整像素上，
## 这样 1px / 2px / 3px 都不会因为亚像素位置发虚或变粗。
func _sync_center() -> void:
	if map_container == null:
		return
	var c: Vector2 = map_container.position + world_pos * map_container.scale.x
	var off: float = CORE_WIDTH * 0.5 - floorf(CORE_WIDTH * 0.5)
	c = c.floor() + Vector2(off, off)
	if c != center:
		center = c
		queue_redraw()


# ===================================================================
# 动画
# ===================================================================

## 入场：四臂从屏幕四边伸展到交点
func play_grow() -> void:
	_kill_anim()
	arm = 0.0
	alpha = 1.0
	_sync_layout()
	_sync_center()
	_anim = create_tween()
	_anim.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	_anim.tween_property(self, "arm", 1.0, GROW_TIME)


## 退场：四臂缩回屏幕四边并淡出，动画结束后自毁
func play_retract() -> void:
	_kill_anim()
	_anim = create_tween().set_parallel(true)
	_anim.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_anim.tween_property(self, "arm", 0.0, RETRACT_TIME)
	_anim.tween_property(self, "alpha", 0.0, RETRACT_TIME)
	_anim.chain().tween_callback(_free_self)


func _free_self() -> void:
	queue_free()


func _kill_anim() -> void:
	if _anim and _anim.is_valid():
		_anim.kill()
	_anim = null


# ===================================================================
# 绘制
# ===================================================================

func _draw() -> void:
	if alpha <= 0.004 or arm <= 0.0:
		return

	var w: float = maxf(size.x, 1.0)
	var h: float = maxf(size.y, 1.0)

	var c: Vector2 = center
	# 四臂：从屏幕四边同时向内伸向交点
	_draw_arm(Vector2(0.0, c.y), c, arm)          # 左
	_draw_arm(Vector2(w, c.y), c, arm)            # 右
	_draw_arm(Vector2(c.x, 0.0), c, arm)          # 上
	_draw_arm(Vector2(c.x, h), c, arm)            # 下


## 一条臂：outer（屏幕边缘）→ center（交点），按 arm 进度只画前一段。
## 透明度沿整条臂的剖面走，越靠边缘越实、越靠交点越透。
func _draw_arm(outer: Vector2, target: Vector2, prog: float) -> void:
	var t_end: float = clampf(prog, 0.0, 1.0)
	if t_end <= 0.0:
		return

	var dir: Vector2 = target - outer
	var len_sq: float = dir.length_squared()
	if len_sq < 0.0001:
		return
	var n: Vector2 = Vector2(-dir.y, dir.x) / sqrt(len_sq) * (CORE_WIDTH * 0.5)

	var tip: Vector2 = outer.lerp(target, t_end)
	if t_end <= ALPHA_SPLIT:
		_draw_seg(outer, tip, n, _arm_alpha(0.0), _arm_alpha(t_end))
		return
	var mid: Vector2 = outer.lerp(target, ALPHA_SPLIT)
	_draw_seg(outer, mid, n, _arm_alpha(0.0), _arm_alpha(ALPHA_SPLIT))
	_draw_seg(mid, tip, n, _arm_alpha(ALPHA_SPLIT), _arm_alpha(t_end))


## 透明度剖面：0（边缘，最实）→ ALPHA_MID（中段）→ ALPHA_CORE（交点，全透明）
func _arm_alpha(t: float) -> float:
	if t <= ALPHA_SPLIT:
		return lerpf(ALPHA_EDGE, ALPHA_MID, t / ALPHA_SPLIT)
	return lerpf(ALPHA_MID, ALPHA_CORE, (t - ALPHA_SPLIT) / (1.0 - ALPHA_SPLIT))


## 一段带透明度渐变的细线（用顶点色做渐变；两端透明度不同）
func _draw_seg(from: Vector2, to: Vector2, n: Vector2, a_from: float, a_to: float) -> void:
	if a_from <= 0.002 and a_to <= 0.002:
		return
	var c_from: Color = Color(CORE_COLOR, CORE_COLOR.a * a_from * alpha)
	var c_to: Color = Color(CORE_COLOR, CORE_COLOR.a * a_to * alpha)
	draw_polygon(
		PackedVector2Array([from + n, to + n, to - n, from - n]),
		PackedColorArray([c_from, c_to, c_to, c_from])
	)
