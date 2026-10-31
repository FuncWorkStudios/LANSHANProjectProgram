## BackgroundLayer : Control
## 持久背景层 — 在所有场景过渡中保留。
## 使用两个 TextureRect：一个活跃显示，一个备用。
## 处理模糊、视差、平滑过渡和图像缩放。
extends Control

## 静止构图的基础缩放（overscan）。视差与「叠加层后退」都在这上面乘。
const BG_BASE_SCALE: float = 1.15
## 换图时前后两层的交叉淡入时长。够短才不会在快速点选时拖队列，够长才不硬切。
const BG_FADE_TIME: float = 0.3
## 叠加层（退出确认等）打开时的后退时长 —— 变焦要"走一段"，但别拖
const ZOOM_DURATION: float = 0.4
## 主菜单选项变化时的视差平移时长
const PARALLAX_TIME: float = 0.8
## 后退的最小倍率。静止位置会按这一档做边界 guard（见 _rest_position），
## 所以调小它 → 背景能退得更狠，代价是静止构图会被 guard 推得离中心更远。
const ZOOM_MIN: float = 0.94

# ── 启动揭幕 ──
# 只在游戏启动、第一次拿到标题页背景时播一次：背景从模糊逐渐变清晰。
# 缩放（0.94 → 1.0）和压暗都已撤掉：这块大贴图做慢速连续缩放会出几 pt 的采样抖动，
# 做快了又显得硬 —— 索性只留模糊。要恢复其中一条：
#   缩放：在 play_intro 里加回 tween_method(_set_intro_scale, ZOOM_MIN, 1.0, 0.8)
#   压暗：把 INTRO_DARKEN 从 0.0 改回 0.8
const INTRO_DELAY: float = 0.4
const INTRO_DARKEN: float = 0.0        # 0 = 不压暗
const INTRO_DARKEN_TIME: float = 0.9
const INTRO_BLUR: float = 8.0
const INTRO_BLUR_TIME: float = 0.95


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

## 启动揭幕的额外缩放（1.0 = 无），叠在 BG_BASE_SCALE 上生效
var _intro_scale: float = 1.0
var _intro_played: bool = false
var _intro_tween: Tween = null

## 常规状态下的视差位移（平滑后的值，由 _refresh 写进 position）
var _parallax_now: float = 0.0
## 视差目标位移
var _parallax_x: float = 0.0
## 叠加层后退进度：0 = 常规构图，1 = 屏幕居中后退
var _overlay_t: float = 0.0
## 后退状态的目标倍率
var _zoom_target: float = 1.0

## 交叉淡入的两层：_front = 当前显示的那层，另一层拿去淡入新图
var _front: TextureRect = null
## 淡入途中又来了新图 → 记下最新一张，等这段跑完再切（快速连点不会硬切、不会闪着切）
var _pending_tex: Texture2D = null


func _ready() -> void:
	EventBus.shared_background_updated.connect(_on_bg_updated)
	EventBus.bg_blur_toggle.connect(_on_blur_toggle)
	EventBus.bg_darken_toggle.connect(_on_darken_toggle)
	EventBus.bg_parallax_offset.connect(_on_parallax)
	EventBus.bg_zoom.connect(_on_zoom)
	_build_layer()
	_apply_current()
	# 预热模糊材质：blur=0 与不挂材质视觉一致，但能把着色器编译提前到进入标题页之前，
	# 否则揭幕第一帧要现场编译 —— 那一下卡顿看起来就是"画面抖了一下"。
	if _ensure_blur_material():
		_apply_blur_material()
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

	_front = _bg_a

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


## 返回当前显示背景的 TextureRect（交叉淡入中为前层）。
func _active_rect() -> TextureRect:
	if _front:
		return _front
	return _bg_a


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
	# 曲线：QUINT / EASE_IN_OUT —— 两端平缓、中段陡；SINE 的尾巴太"圆"，
	# 到 90% 时间点还有 31% 速度，最后一帧会像急停。
	_zoom_tween.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_IN_OUT)
	_zoom_tween.tween_method(_set_overlay_t, _overlay_t, 1.0 if opening else 0.0, ZOOM_DURATION)


func _set_overlay_t(v: float) -> void:
	_overlay_t = v
	_refresh()


# ── 启动揭幕（标题页） ──────────────────────

## 背景从「略小 + 压暗 + 模糊」推到现有构图（和主页 ESC 菜单的后退档同一倍率）。
## 由 SceneManager 切到 TITLE 时调用；只在第一次生效（之后回标题页不再重播）。
func play_intro() -> void:
	if _intro_played:
		return
	_intro_played = true

	# 起始态立刻摆好（此时还在黑幕下面，看不到跳变），补间延迟 INTRO_DELAY 再跑
	if _darken_overlay:
		_darken_overlay.color = Color(0, 0, 0, INTRO_DARKEN)
	var mat: ShaderMaterial = _ensure_blur_material()
	if mat:
		mat.set_shader_parameter("blur_amount", INTRO_BLUR)
		_bg_a.material = mat
		_bg_b.material = mat

	if _intro_tween and _intro_tween.is_valid():
		_intro_tween.kill()
	_intro_tween = create_tween()
	_intro_tween.set_parallel(true)
	# 只保留模糊：QUINT / EASE_IN_OUT，两端平缓、中段陡，起步不"啪"一下糊没。
	_intro_tween.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_IN_OUT)
	if mat:
		_intro_tween.tween_method(_set_blur_amount, INTRO_BLUR, 0.0, INTRO_BLUR_TIME) \
				.set_delay(INTRO_DELAY)
	if _darken_overlay and INTRO_DARKEN > 0.0:
		_intro_tween.tween_property(_darken_overlay, "color:a", 0.0, INTRO_DARKEN_TIME) \
				.set_delay(INTRO_DELAY)
	_intro_tween.set_parallel(false)
	_intro_tween.tween_callback(_clear_blur_material)



func _set_intro_scale(v: float) -> void:
	_intro_scale = v
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
	var z: float = (1.0 if _overlay_t <= 0.0 else pow(_zoom_target, _overlay_t)) 
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

	# 启动揭幕：绕**图片自身中心**缩放。
	# 不能直接折进上面的屏幕中心公式 —— 静止构图相对屏幕中心是偏的（guard 把左上角
	# 推到约 -48/-27），绕屏幕中心推近会让整幅图同时平移约 3px，看起来像画面在晃。
	if not is_equal_approx(_intro_scale, 1.0):
		var painted: Vector2 = rect.size * s
		var grow: Vector2 = painted * (1.0 - _intro_scale) * 0.5
		rect.scale = Vector2(s * _intro_scale, s * _intro_scale)
		rect.position += grow


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
		if not _ensure_blur_material():
			return
		_apply_blur_material()
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


## 惰性创建模糊材质（启动揭幕和 bg_blur_toggle 共用）。
func _ensure_blur_material() -> ShaderMaterial:
	if _blur_material:
		return _blur_material
	var shader: Shader = load("res://shaders/blur.gdshader")
	if not shader:
		return null
	_blur_material = ShaderMaterial.new()
	_blur_material.shader = shader
	_blur_material.set_shader_parameter("blur_amount", _current_blur)
	return _blur_material


func _clear_blur_material() -> void:
	_bg_a.material = null
	_bg_b.material = null
	_blur_material = null
	_current_blur = 0.0


## 把模糊材质挂到**两层**背景上：交叉淡入时前后两层都要糊着，
## 否则正在淡入的那层会是清晰的，看起来像背景"闪了一下清晰图"。
func _apply_blur_material() -> void:
	if _blur_material == null:
		return
	_bg_a.material = _blur_material
	_bg_b.material = _blur_material


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
		_pending_tex = null
		if _fade_tween and _fade_tween.is_valid():
			_fade_tween.kill()
		# 交叉淡入可能还留着半透明的一层，一并收掉
		var other: TextureRect = _bg_b if active == _bg_a else _bg_a
		if other:
			other.modulate.a = 0.0
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
	if path.is_empty() or not ResourceLoader.exists(path):
		return
	var tex: Texture2D = load(path)
	if not tex:
		return

	# 场景切换收回背景所有权：丢弃没跑完的切入和待切的那张
	_pending_tex = null
	if _fade_tween and _fade_tween.is_valid():
		_fade_tween.kill()

	var active: TextureRect = _active_rect()
	if active == null:
		return
	var other: TextureRect = _bg_b if active == _bg_a else _bg_a
	if other:
		other.modulate.a = 0.0
	move_child(active, 1)

	var had_tex: bool = active.texture != null
	active.texture = tex
	if had_tex:
		active.modulate.a = 1.0
	else:
		active.modulate.a = 0.0
		var tw := create_tween()
		tw.tween_property(active, "modulate:a", 1.0, 0.35)


## 换背景：双 TextureRect 交叉淡入 —— 新图叠在旧图上面淡进来，旧图保持不动。
## 淡入途中又来的新图只记「最新一张」，等这一段跑完再接上：
## 快速连点只会收敛到最后一张，不会硬切、也不会每张都闪一下。
func _on_bg_updated(path: String) -> void:
	if path.is_empty() or not ResourceLoader.exists(path):
		return
	var tex: Texture2D = load(path)
	if not tex:
		return
	_pending_tex = tex
	if _fade_tween and _fade_tween.is_valid():
		return
	_start_cross_fade()


## 开始一段交叉淡入（取 _pending_tex 里最新那张）。
func _start_cross_fade() -> void:
	var tex: Texture2D = _pending_tex
	_pending_tex = null
	if tex == null:
		return
	var front: TextureRect = _active_rect()
	if front == null:
		return

	if _fade_tween and _fade_tween.is_valid():
		_fade_tween.kill()

	# 首张：直接在前层淡入（下面没有旧图可叠）
	if front.texture == null:
		front.texture = tex
		front.modulate.a = 0.0
		_fade_tween = create_tween()
		_fade_tween.tween_property(front, "modulate:a", 1.0, BG_FADE_TIME)
		return

	var incoming: TextureRect = _bg_b if front == _bg_a else _bg_a
	incoming.texture = tex
	incoming.modulate.a = 0.0
	incoming.visible = true
	# 新图必须叠在旧图之上；两层都固定在前两个子节点（上面还有变暗/黑幕层）
	move_child(incoming, 1)

	_fade_tween = create_tween()
	_fade_tween.tween_property(incoming, "modulate:a", 1.0, BG_FADE_TIME)
	_fade_tween.tween_callback(_on_cross_faded.bind(front, incoming))


## 交叉淡入结束：前层换成刚淡进来的那层、旧层收掉；期间若又来了新图就接着切。
func _on_cross_faded(p_old: TextureRect, p_new: TextureRect) -> void:
	_front = p_new
	if p_old:
		p_old.modulate.a = 0.0
	if _pending_tex:
		_start_cross_fade()
