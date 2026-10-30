## BackgroundLayer : Control
## 持久背景层 — 在所有场景过渡中保留。
## 使用两个 TextureRect：一个活跃显示，一个备用。
## 处理模糊、视差、平滑过渡和图像缩放。
extends Control

## 背景图的基础缩放（overscan）。视差与「叠加层后退」都在这上面乘。
const BG_BASE_SCALE: float = 1.15
## 叠加层（退出确认等）打开时的后退时长 —— 变焦要"走一段"，但别拖
const ZOOM_DURATION: float = 0.4
## 主菜单选项变化时的视差平移时长
const PARALLAX_TIME: float = 0.8
## 后退的最小倍率。静止位置会按这一档做边界 guard（见 _rest_position），
## 所以调小它 → 背景能退得更狠，代价是静止构图会被 guard 推得离中心更远。
const ZOOM_MIN: float = 0.94

# ── 双 TextureRect ──
var _bg_a: TextureRect = null
var _bg_b: TextureRect = null

var _fade_tween: Tween = null
var _blur_tween: Tween = null
var _blur_material: ShaderMaterial = null
var _parallax_tween: Tween = null
var _zoom_tween: Tween = null
var _darken_overlay: ColorRect = null
var _darken_tween: Tween = null
var _black_overlay: ColorRect = null

## 常规状态下的视差位移（平滑后的值，由 _refresh 写进 position）
var _parallax_now: float = 0.0
## 视差目标位移
var _parallax_x: float = 0.0
## 叠加层后退进度：0 = 常规构图，1 = 屏幕居中后退
var _overlay_t: float = 0.0
## 后退状态的目标倍率
var _zoom_target: float = 1.0


func _ready() -> void:
	EventBus.shared_background_updated.connect(_on_bg_updated)
	EventBus.bg_blur_toggle.connect(_on_blur_toggle)
	EventBus.bg_darken_toggle.connect(_on_darken_toggle)
	EventBus.bg_parallax_offset.connect(_on_parallax)
	EventBus.bg_zoom.connect(_on_zoom)
	_build_layer()
	_apply_current()
	# 尺寸（首次布局 / 窗口变化）确定后要重新算一次覆盖余量
	resized.connect(_on_layer_resized)
	_on_layer_resized.call_deferred()


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
	r.scale = Vector2(BG_BASE_SCALE, BG_BASE_SCALE)
	return r


## 返回当前显示背景的 TextureRect（始终为 _bg_a）。
func _active_rect() -> TextureRect:
	return _bg_a


## 将纹理设置到活跃 rect 上（在 fade_tween 回调中使用）。
func _set_bg_texture(tex: Texture2D) -> void:
	_bg_a.texture = tex


# ── 背景图变换：静止构图 + 绕屏幕中心的叠加层后退 ──────────────────
#
# 静止（_overlay_t = 0）：上边留 BG_TOP_INSET_RATIO 的余量 + 视差平移。
# 后退（_overlay_t > 0）：以**屏幕中心**为基点整体缩放：
#     p → 屏幕中心 + (p - 屏幕中心) × z
#   屏幕中心那一点不动 → 没有位移，纯粹原地往中心收。
# 因为静止时上方留了余量、右下本来就有 overscan，任何 z ≥ ZOOM_MIN 都盖得满屏幕。
#
# 注意：视差与后退进度各自由一条补间驱动**标量**，再由 _refresh() 统一写
# 位置/缩放 —— 之前两条补间抢同一个 rect.position，后一条会把前一条杀掉。

func _on_parallax(x: float) -> void:
	_parallax_x = x
	if _parallax_tween and _parallax_tween.is_valid():
		_parallax_tween.kill()
	_parallax_tween = create_tween()
	_parallax_tween.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	_parallax_tween.tween_method(_set_parallax_now, _parallax_now, x, PARALLAX_TIME)


func _set_parallax_now(v: float) -> void:
	_parallax_now = v
	_refresh()


## 叠加层打开（factor < 1）→ 缩到 factor 倍率；factor = 1 → 回到静止构图。
func _on_zoom(factor: float) -> void:
	var opening: bool = factor < 0.999
	if opening:
		_zoom_target = clampf(factor, ZOOM_MIN, 1.0)
	if _zoom_tween and _zoom_tween.is_valid():
		_zoom_tween.kill()
	_zoom_tween = create_tween()
	# 曲线：SINE / EASE_OUT —— 一开就动、尾段平滑收住。
	# QUINT/EASE_OUT 峰值速度是均速的 5 倍（冲），SINE 只有 1.57 倍（推镜头）。
	_zoom_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_zoom_tween.tween_method(_set_overlay_t, _overlay_t, 1.0 if opening else 0.0, ZOOM_DURATION)


func _set_overlay_t(v: float) -> void:
	_overlay_t = v
	_refresh()


## 自身尺寸变化（首次布局 / 窗口变化）→ 重算一次。
## 延后一帧：resized 触发时子节点（背景 rect）的锚点布局可能还没跟上。
func _on_layer_resized() -> void:
	_refresh.call_deferred()


## 唯一写 transform 的地方：由当前状态算出两张背景图的缩放与位置。
## 倍率在**对数空间**插值： z = target ^ t。
## 人眼感知的变焦是「每单位时间变化固定比例」（镜头的焦距），不是固定像素差；
## 直接线性插值倍率会让整段变焦"先慢后急"，看起来不像推镜头。
func _refresh() -> void:
	var view: Vector2 = size
	if view.x <= 0.0:
		return
	var z: float = 1.0 if _overlay_t <= 0.0 else pow(_zoom_target, _overlay_t)
	var s: float = BG_BASE_SCALE * z
	_apply_rect(_bg_a, view, s, z)
	_apply_rect(_bg_b, view, s, z)


## 以**屏幕中心**为基点缩放。
##
## 做法两步（先算静止偏移，再按 z 缩这份偏移）：
##   1. 静止基点 = _rest_position()（视差目标 + 边界 guard）
##   2. 偏移 = 静止基点 − 屏幕中心；缩放后位置 = 屏幕中心 + 偏移 × z
## 即 p → 屏幕中心 + (p − 屏幕中心)·z，屏幕中心那一点恒定不动 —— 零位移。
## 覆盖由 _rest_position() 的 guard 一次保证：静止位置本身就按「缩到 ZOOM_MIN
## 也不露边」选出来的，之后 z 只会往回长，所以整段动画都盖得满屏幕。
func _apply_rect(rect: TextureRect, view: Vector2, s: float, z: float) -> void:
	if rect == null:
		return
	rect.scale = Vector2(s, s)

	var screen_center: Vector2 = view * 0.5
	var offset: Vector2 = _rest_position(rect, view) - screen_center
	rect.position = screen_center + offset * z


## 静止（z = 1）时背景图左上角的位置：视差目标 + 边界 guard。
##
## guard 先于缩放开算：位置要保证「缩到最狠那一档（ZOOM_MIN）时背景仍盖满屏幕」。
## 缩到 z 时左/上边会被拉到 中心 + (位置 - 中心)·z，所以位置允许区间是
##   左上角 ≥ 中心 - 中心/guard_z           （左边不出屏）
##   左上角 ≤ 中心 + (视口 - 中心)/guard_z - 画出尺寸   （右边不出屏）
## 落在区间外（比如视差还是 0、图左边贴死屏幕）时会被拉进来 —— 这就是先前
## 缩起来露黑边的原因：位置没先走 guard。
func _rest_position(rect: TextureRect, view: Vector2) -> Vector2:
	var painted: Vector2 = rect.size * BG_BASE_SCALE
	# 一档安全量，防浮点误差在边上留一条缝
	var guard_z: float = ZOOM_MIN - 0.01
	var c: Vector2 = view * 0.5
	var lo: Vector2 = c - c / guard_z
	var hi: Vector2 = c + (view - c) / guard_z - painted

	var wanted := Vector2(_parallax_now, 0.0)
	return Vector2(
			clampf(wanted.x, minf(hi.x, lo.x), maxf(hi.x, lo.x)),
			clampf(wanted.y, minf(hi.y, lo.y), maxf(hi.y, lo.y)))


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
