## BackdropBlur : Control
## 全屏叠加层背后的「毛玻璃」—— 采样屏幕做两趟渐进模糊。
##
## 为什么不用 shaders/blur.gdshader：
##   那个模糊的是「节点自己的 TEXTURE」，只能用于有贴图的背景图层；
##   叠加层本身没有贴图，透过它看到的是屏幕，所以必须采样屏幕纹理
##   （shaders/backdrop_blur.gdshader）。
##
## 为什么要两趟：
##   单趟大半径 = 抽头间距被拉大（这里能到 8~10 物理像素），间距超过信号带宽
##   就会欠采样，背景里的噪点 / 文字笔画会折叠成规则网格 —— 也就是颗粒感。
##   正确做法是先用小半径密采样压掉高频，再用大半径稀采样；
##   两趟之间必须插一个 BackBufferCopy，否则第二趟读到的还是第一趟之前的画面。
##
## 供 TabMenu 与 LogScreen（Z 键对话历史）共用：两个菜单的背景观感必须完全
## 一致，所以模糊半径、趟数、黑幕不透明度都只在这里定义一份。
##
## 组件只负责画：mouse_filter = IGNORE，绝不吃滚轮与点击。
##
## 动画用 _process 自己推进（不走 Tween）：叠加层开场/关闭时调用 blur_in() /
## blur_out()，强度按指数逼近目标，与帧率无关、不过冲，中途反向也连续。
class_name BackdropBlur
extends Control

const SHADER_PATH: String = "res://shaders/backdrop_blur.gdshader"

## 第一趟：小半径、密采样 —— 先把噪点 / 笔画这类高频压掉
const FINE_RADIUS: float = 4.0
## 第二趟：大半径 —— 输入已被第一趟平滑，稀采样也不会有网格纹
const WIDE_RADIUS: float = 12.0
## 清晰 → 模糊 / 模糊 → 清晰 的默认时长
const OPEN_TIME: float = 0.45
const CLOSE_TIME: float = 0.2
## 叠加层黑幕不透明度 —— TabMenu 与 LogScreen 共用同一个值，别再各写一份。
const SCRIM_ALPHA: float = 0.9
## 指数逼近：3 个时间常数 ≈ 收敛到 95%
const EASE_TAU: float = 3.0
## 动画起点不取 0 —— 万一 _process 没跑起来，至少还是「微糊」而不是完全没效果
const OPEN_FROM: float = 0.2

var _fine: ShaderMaterial = null
var _wide: ShaderMaterial = null
## 当前强度 / 目标强度（0 = 清晰，1 = 目标模糊）
var _amount: float = 0.0
var _target: float = 0.0
## 逼近速度（每时间常数），由 blur_in/blur_out 的 duration 反推
var _speed: float = 8.0
## 物理像素 / 逻辑像素（半径按逻辑像素定义，采样用物理像素）
var _scale: float = 1.0
var _warned: bool = false
var _logged: bool = false


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE

	var shader: Shader = load(SHADER_PATH) as Shader
	if shader == null:
		return

	_fine = _add_pass("PassFine", shader)
	# 两趟之间的屏幕重新拷贝
	add_child(_make_screen_copy())
	_wide = _add_pass("PassWide", shader)

	_scale = _screen_scale()
	_match_viewport()
	_amount = 0.0
	_target = 0.0


# ===================================================================
# 对外 API
# ===================================================================

## 清晰 → 模糊（叠加层打开时调用）
func blur_in(duration: float = OPEN_TIME) -> void:
	_scale = _screen_scale()
	_match_viewport()
	_amount = OPEN_FROM
	_target = 1.0
	_speed = EASE_TAU / maxf(duration, 0.05)
	set_amount(_amount)
	# 一行诊断（每次进场只打一次）：万一模糊不生效，这行能区分
	# 「脚本没算对半径」和「着色器没画」。
	if OS.is_debug_build() and not _logged:
		_logged = true


## 模糊 → 清晰（叠加层关闭时调用）
func blur_out(duration: float = CLOSE_TIME) -> void:
	_target = 0.0
	_speed = EASE_TAU / maxf(duration, 0.05)


## 立即设定模糊强度（0 = 清晰，1 = 目标模糊），不走动画
func set_amount(amount: float) -> void:
	_amount = clampf(amount, 0.0, 1.0)
	if _fine == null and _wide == null:
		if not _warned:
			_warned = true
		return
	if _fine:
		_fine.set_shader_parameter("blur_radius", FINE_RADIUS * _scale * _amount)
	if _wide:
		_wide.set_shader_parameter("blur_radius", WIDE_RADIUS * _scale * _amount)


## 当前强度（0..1）—— 调试用
func get_amount() -> float:
	return _amount


# ===================================================================
# 每帧推进动画
# ===================================================================

func _process(delta: float) -> void:
	if is_equal_approx(_amount, _target):
		return
	# 指数逼近：与帧率无关、不过冲，反向时直接从当前位置继续
	_amount = lerpf(_amount, _target, 1.0 - exp(-_speed * delta))
	if absf(_amount - _target) < 0.004:
		_amount = _target
	set_amount(_amount)


# ===================================================================
# 构建
# ===================================================================

## 加一趟全屏模糊，返回它的材质。
## color 取全透明：万一着色器编译失败，引擎退回默认 canvas 着色器画的就是这个
## color（alpha 0 = 看不见），不会变成黑幕或白屏挡住后面。正常运行时着色器
## 自己输出 alpha = 1，与这个 color 无关。
func _add_pass(pass_name: String, shader: Shader) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = shader

	var rect := ColorRect.new()
	rect.name = pass_name
	rect.mouse_filter = MOUSE_FILTER_IGNORE
	rect.color = Color(0, 0, 0, 0)
	rect.material = mat
	add_child(rect)
	return mat


## 强制把当前屏幕重新拷进缓冲。没有它，第二趟采样到的仍是第一趟之前的画面，
## 两趟就等于只有一趟（颗粒感照旧）。
func _make_screen_copy() -> BackBufferCopy:
	var copy := BackBufferCopy.new()
	copy.name = "PassCopy"
	copy.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	return copy


## 显式对齐视口 —— 不依赖锚点解析。
## 本组件在叠加层 _ready 期间就建好了，那时父级控件可能还是 0 尺寸；
## 用锚点会在首帧出现 0 尺寸全屏图（= 什么都画不出来）。
func _match_viewport() -> void:
	var vp: Viewport = get_viewport()
	if vp == null:
		return
	var vp_size: Vector2 = vp.get_visible_rect().size
	position = Vector2.ZERO
	size = vp_size
	for child in get_children():
		if child is Control:
			var rect := child as Control
			rect.position = Vector2.ZERO
			rect.size = vp_size


# ===================================================================
# 分辨率换算
# ===================================================================

## 物理像素 / 逻辑像素。
## 屏幕纹理按物理分辨率采样（SCREEN_PIXEL_SIZE），而工程是拉伸全屏
## （display/window/size/mode=3, stretch=canvas_items），所以半径要乘上这个
## 系数，不同分辨率下的模糊观感才一致。
func _screen_scale() -> float:
	var vp: Viewport = get_viewport()
	if vp == null:
		return 1.0
	var logical: float = vp.get_visible_rect().size.x
	if logical <= 0.0:
		return 1.0
	var win: Window = get_window()
	if win == null:
		return 1.0
	# 窗口比逻辑分辨率还小的极端情况下也留个下限，别把半径算到 0
	return clampf(float(win.size.x) / logical, 0.5, 4.0)
