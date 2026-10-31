## MapLoadReveal : Node
## 地图页的「进入加载揭幕」——贴图切成 8×8 共 64 块，初始全黑，
## 每轮随机揭出 16 块，4 轮铺满整张地图；块内从黑平滑过渡到原图。
##
## 只作用于地图贴图本身（MapTexture.material），标题栏 / 返回栏 / 信息面板不受影响。
## 揭幕期间由 Map.gd 锁输入、隐藏地点标记；标记在最后 0.2 淡入，
## 准心与推镜头由 Map.gd 在揭幕结束后再播放。
##
## 首次进入播完整 1s，之后重进播 0.35s 的加速版；任意键可跳过（由 Map.gd 转发 skip）。
class_name MapLoadReveal
extends Node

## 揭幕结束（自然播完或被 skip）
signal finished()

const REVEAL_SHADER: Shader = preload("res://shaders/map_load_reveal.gdshader")

## 网格与节奏。STAGGER / FADE / MARKER_FADE 都是「占总时长」的比例，
## 所以加速版只是把 _total 变短，节奏比例完全一致。
const GRID: int = 8
const ROUNDS: int = 4
## 一轮 0.25 = STAGGER（轮内错峰上限）+ FADE（单块淡入时长），
## 这样第 4 轮最晚开始的那块正好在总时长处变实。
## FADE 0.19 ≈ 完整版 190ms / 加速版 114ms —— 肉眼能看清是"渐显"而不是直接出现。
const STAGGER: float = 0.06
const FADE: float = 0.19
const MARKER_FADE: float = 0.2   # 地点标记在最后这一段里淡入
const FULL_TIME: float = 1.0     # 首次进入的总时长
const FAST_TIME: float = 0.6     # 之后重进的总时长（仍保留可见的逐块渐变）

## 整局游戏只播一次完整版，之后都走 FAST_TIME
static var _played_once: bool = false

# ---------------------------------------------------------------------------
# 状态
# ---------------------------------------------------------------------------
var _texture: TextureRect = null
var _markers: Array[Control] = []
var _starts_tex: ImageTexture = null
var _mat: ShaderMaterial = null
var _elapsed: float = 0.0
var _total: float = FULL_TIME
var _playing: bool = false


# ===================================================================
# 生命周期
# ===================================================================

func setup(texture_rect: TextureRect, markers: Array[Control]) -> void:
	_texture = texture_rect
	_markers = markers
	set_process(false)


## 揭幕是否正在播放（Map.gd 用它判断要不要锁输入）
func is_playing() -> bool:
	return _playing


## 播放入场揭幕：调用后地图立刻变黑，随后逐块显形。
## `priority_point` = 选中地点在贴图上的像素坐标，它所在的区块会被强制塞进第一轮。
## 结束（或被 skip）时发出 finished，由调用方决定之后播什么。
func play(priority_point: Vector2) -> void:
	_begin(priority_point)


## 跳过：立即完成揭幕（ESC / 任意键 / 离开地图）
func skip() -> void:
	if not _playing:
		return
	_finish()


func _process(delta: float) -> void:
	if not _playing:
		return
	_elapsed += delta
	var t: float = clampf(_elapsed / _total, 0.0, 1.0)
	_apply_progress(t)
	if t >= 1.0:
		_finish()


# ===================================================================
# 内部
# ===================================================================

func _begin(priority_point: Vector2) -> bool:
	if _playing or _texture == null or _texture.texture == null:
		return false

	_playing = true
	_total = FULL_TIME if not _played_once else FAST_TIME
	_played_once = true
	_elapsed = 0.0

	if _starts_tex == null:
		_starts_tex = ImageTexture.new()
	_starts_tex.set_image(_build_schedule(_block_index(priority_point)))

	_mat = ShaderMaterial.new()
	_mat.shader = REVEAL_SHADER
	_mat.set_shader_parameter("block_starts", _starts_tex)
	_mat.set_shader_parameter("grid_size", GRID)
	_mat.set_shader_parameter("fade", FADE)
	_mat.set_shader_parameter("progress", 0.0)
	_texture.material = _mat

	_apply_progress(0.0)
	set_process(true)
	return true


func _finish() -> void:
	if not _playing:
		return
	_playing = false
	set_process(false)
	_apply_progress(1.0)
	# 收尾：把材质摘掉，之后贴图恢复成普通绘制，不再有每像素采样开销
	if _texture != null:
		_texture.material = null
	_mat = null
	_set_markers_alpha(1.0)
	finished.emit()


func _apply_progress(t: float) -> void:
	if _mat != null:
		_mat.set_shader_parameter("progress", t)
	_set_markers_alpha(smoothstep(1.0 - MARKER_FADE, 1.0, t))


func _set_markers_alpha(a: float) -> void:
	for m: Control in _markers:
		if is_instance_valid(m):
			m.modulate.a = a


## 选中地点所在区块的下标（y * GRID + x）；没有可用贴图时返回 -1
func _block_index(point: Vector2) -> int:
	if _texture == null or _texture.texture == null:
		return -1
	var tex_size: Vector2 = _texture.texture.get_size()
	if tex_size.x <= 0.0 or tex_size.y <= 0.0:
		return -1
	var bx: int = clampi(int(point.x / tex_size.x * float(GRID)), 0, GRID - 1)
	var by: int = clampi(int(point.y / tex_size.y * float(GRID)), 0, GRID - 1)
	return by * GRID + bx


## 生成随机揭幕表：4 轮 × 16 块，第一轮必含 priority_block，轮内随机错峰。
## 返回一张 8×8 的图，像素 R 通道 = 该块的开始时间（0..1）。
func _build_schedule(priority_block: int) -> Image:
	var total: int = GRID * GRID
	var per_round: int = int(float(total) / float(ROUNDS))

	# 洗牌出全部区块的揭幕顺序；优先块从池里取出、排到第一个
	var pool: Array[int] = []
	for i: int in range(total):
		pool.append(i)
	pool.shuffle()

	var order: Array[int] = []
	if priority_block >= 0 and priority_block < total:
		order.append(priority_block)
		pool.erase(priority_block)
	order.append_array(pool)

	var img: Image = Image.create_empty(GRID, GRID, false, Image.FORMAT_RGBA8)
	var cursor: int = 0
	for r: int in range(ROUNDS):
		var round_start: float = float(r) / float(ROUNDS)
		for _k: int in range(per_round):
			if cursor >= order.size():
				break
			var idx: int = order[cursor]
			cursor += 1
			var start: float = round_start + randf() * STAGGER
			img.set_pixel(idx % GRID, int(float(idx) / float(GRID)), Color(start, 0.0, 0.0, 1.0))
	return img
