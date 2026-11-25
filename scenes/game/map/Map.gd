## Map : Control
## 学校地图页面。全部 UI 节点在代码中构建。
##   鼠标拖拽 → 平移（带惯性）/ 滚轮 → 缩放（平滑跟手）/ WASD → 切换地点
##   进入 → 加载揭幕（8×8 区块 4 轮从黑渐显，见 MapLoadReveal），结束后才播准心与推镜头
##   选中地点 → 动态生成屏幕空间十字准星（四臂从屏幕四边交于该点）+ 推近镜头
##   取消选中 → 准星倒放收回 / 切换地点 → 旧准心退场、新准心重新生成
##
## 动效约定（实测「生硬」主要是曲线前重后轻导致的：QUINT/CUBIC EASE_OUT 在 60fps 下
## 第一帧就走掉 14% 位移，看起来像"猛地一顿再慢慢飘"；但一味放缓又会"软绵绵、不跟手"）：
##   · 相机（平移 + 缩放）走 _animate_camera —— 两者共用一条 tween / 同一进度 /
##     QUAD EASE_IN_OUT（首帧约 0.6%，峰值 2 倍均速），时长按行程自适应且封顶 0.4s。
##   · 滚轮不走 tween，走 _process 里的指数逼近：只改目标、不重建动画，跟手且能连续滚。
##   · 轻量 UI 元素才用 EASE_OUT；面板滑入只走自身宽度（约 422px），不要用视口宽（1280px）。
extends Control

signal back_requested()
signal goto_location_requested(location_name: String)

# ---------------------------------------------------------------------------
# 地点数据 — 上移至 scripts/resources/MapData.gd（地点系统共享：@locate / API 校验）
# ---------------------------------------------------------------------------
const LOCATIONS: Array[Dictionary] = MapData.LOCATIONS

# 子脚本一律用 preload 取用，不依赖全局 class_name 缓存 —— 脚本在编辑器外新建时
# 缓存可能还没刷新，直接运行游戏会报 "Could not find type ..."。
const CrosshairScript = preload("res://scenes/game/map/MapCrosshair.gd")
const RevealScript = preload("res://scenes/game/map/MapLoadReveal.gd")
const TITLE_BAR = preload("res://scenes/ui/SceneTitleBar.gd")

## 标题栏细线宽度（从标题左缘起算；右侧被 InfoPanel 盖住的部分看不见，与其它页保持同值）
const TITLE_RULE_WIDTH: float = 1232.0

const MAP_W: float = 1672.0
const MAP_H: float = 941.0
const ZOOM_MIN: float = 0.3
const ZOOM_MAX: float = 3.0
const ZOOM_STEP: float = 1.12
const KEYBOARD_ZOOM: float = 2.0
const PANEL_SHIFT: float = 80.0
const DOT_SIZE: float = 10.0
const LABEL_OFFSET_X: float = 16.0
const LABEL_OFFSET_Y: float = -5.0
const DRAG_THRESHOLD: float = 4.0
const GOTO_REST_ALPHA: float = 0.75
const STAGGER_OFFSET: float = 50.0

# ── 信息面板（右侧滑入）──
## 滑入行程 = 面板自身宽度 + 这点余量（只多走这么点，别用视口宽）。
const PANEL_EDGE_PAD: float = 2.0
const PANEL_IN_TIME: float = 0.32
const PANEL_OUT_TIME: float = 0.22
## 内部元素错峰：第 0 项从 PANEL_BASE_DELAY 起手，之后每项 +PANEL_STEP，单项时长统一。
const PANEL_BASE_DELAY: float = 0.08
const PANEL_STEP: float = 0.05
const PANEL_ITEM_TIME: float = 0.30
## 切地点时正文「轻轻浮现」的时长（对齐日历页 _flash_detail）。
const INFO_FLASH_TIME: float = 0.22
## Goto 按钮在面板入口里单独入场 / 悬停时的位移时长。
const GOTO_IN_TIME: float = 0.35
const GOTO_HOVER_TIME: float = 0.25

# ── 相机 ──
## 时长按行程自适应：挪得远 / 缩得多就慢一点，微调就快一点。
## 上限压到 0.4s：再长就会"软绵绵"（手已经停了，画面还在慢慢飘）。
const CAM_MIN_TIME: float = 0.20
const CAM_MAX_TIME: float = 0.40
const CAM_SPEED: float = 2000.0          # 折算行程的巡航速度（px/s）
const CAM_ZOOM_WEIGHT: float = 420.0     # 1 倍缩放折算成多少 px 位移（与平移同量纲）
## 取消选中时"拉回全景"的时长 —— 比普通推镜慢一点，读起来是主动退回而不是被弹回去。
const CAM_RETURN_TIME: float = 0.46

# ── 滚轮缩放（指数逼近，不是 tween）──
## 速率 1/s：30 ≈ 33ms 到 63%、100ms 到 95%。越快越跟手，太慢就会"软"。
const ZOOM_SMOOTH_RATE: float = 30.0
## 差距小于目标缩放的这个比例就直接吸附并停止 _process。
const ZOOM_SNAP_EPS: float = 0.0015

# ── 拖拽 ──
const FLING_DECAY: float = 0.15          # 甩动距离 = 松手速度 × 这个系数
const FLING_MIN_SPEED: float = 480.0     # 低于这个速度不甩（px/s）
const FLING_TIME: float = 0.36
const FLING_MAX_SPEED: float = 6000.0

# ── 地点标记 ──
const DOT_IDLE: Color = Color.BLACK
const DOT_SELECTED: Color = Color.RED
const DOT_HOVER_SCALE: float = 1.55
const DOT_SELECT_SCALE: float = 1.9
const LABEL_HOVER_SHIFT: float = 4.0
const MARKER_HOVER_TIME: float = 0.12
const MARKER_SELECT_TIME: float = 0.22

# ── 选中准星（屏幕空间的横平竖直两条线，压在标点之下；标记选中即变红）──
const CROSS_ZOOM_DELAY: float = 0.08               # 选中后先让准心起手，再推镜头（要短，否则按下去像没反应）
const ENTRY_ZOOM: float = 1.5                      # 进入地图时聚焦当前地点的缩放
const ENTRY_ZOOM_DELAY: float = 0.15               # 准心长到约 70% 时开始推镜（滑入已被加载揭幕覆盖）
const ENTRY_PAN_TIME: float = 0.6

# ---------------------------------------------------------------------------
# 状态
# ---------------------------------------------------------------------------
var _disabled: bool = false
var _menu_active: bool = false
var _can_go_back: bool = true
var _selected_idx: int = 0
var _last_selected_idx: int = -1
var _marker_nodes: Array[Control] = []
var _zoom_level: float = 1.0
var _zoom_min: float = 1.0
var _dragging: bool = false
var _drag_start: Vector2 = Vector2.ZERO
var _pan_start: Vector2 = Vector2.ZERO
## 松手甩动的速度估算（平滑后的容器坐标 px/s）
var _drag_vel: Vector2 = Vector2.ZERO
var _drag_last_pos: Vector2 = Vector2.ZERO
var _drag_last_ms: int = 0
var _pan_tween: Tween = null
## 滚轮缩放：光标下的世界点整轮保持不动。显示值 _zoom_vis 指数逼近 _zoom_goal ——
## 每一格滚轮只改目标、不重建动画，所以没有"起步停顿"，也不会每格掉速。
var _zoom_goal: float = 1.0
var _zoom_vis: float = 1.0
var _zoom_smoothing: bool = false
var _zoom_anchor_screen: Vector2 = Vector2.ZERO
var _zoom_anchor_world: Vector2 = Vector2.ZERO
var _panel_tween: Tween = null
## 信息面板的目标态 —— true = 显示中/正在滑入。用它（而不是 visible）判定
## 面板是否还"该出现"，否则滑出动画未结束时的按键会被吞掉或重启动画。
var _panel_shown: bool = false
## 面板内部元素的静止 X 与入场动画 —— 被打断时能回到原位重播
var _info_rest_name: float = 0.0
var _info_rest_desc: float = 0.0
var _info_rest_suggest: float = 0.0
var _info_rest_saved: bool = false
var _info_intro_tweens: Array[Tween] = []
## 切地点时正文的浮现动画（与入场动画分开管理，互不打断）
var _detail_tween: Tween = null
var _goto_wrap: Panel = null
var _goto_sweep: ColorRect = null
var _goto_border_style: StyleBoxFlat = null
var _goto_rest_x: float = 0.0
var _goto_hover_tween: Tween = null
## 悬停混合值：0 = 白字描边态，1 = 黑字白底态。文字色靠它跟 sweep 同步渐变。
var _goto_hover_blend: float = 0.0
var _goto_enabled: bool = false

# ── 选中准星（每次选中动态生成，见 _sync_crosshair）──
var _crosshair: CrosshairScript = null
var _crosshair_idx: int = -1
var _selection_delay: float = 0.0

# ---------------------------------------------------------------------------
# 字体
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# UI 节点 — 静态节点在 Map.tscn 中，代码通过 @onready 引用
# ---------------------------------------------------------------------------
@onready var _title_label: Label = $TitleLabel
@onready var _title_bg: ColorRect = $TitleBg
@onready var _map_clip: Control = $MapClip
@onready var _map_container: Control = $MapClip/MapContainer
@onready var _map_texture: TextureRect = $MapClip/MapContainer/MapTexture
@onready var _info_panel: Control = $InfoPanel
@onready var _info_name: Label = $InfoPanel/NameLabel
@onready var _info_desc: Label = $InfoPanel/DescLabel
@onready var _info_suggest: Label = $InfoPanel/SuggestLabel
@onready var _info_border: ColorRect = $InfoPanel/BorderBot
@onready var _goto_label: Label = $InfoPanel/Goto
var _back_bar: BackBar = null
## 进入地图的加载揭幕（8×8 区块从黑渐显），见 MapLoadReveal
var _load_reveal: RevealScript = null


# ===================================================================
# 生命周期
# ===================================================================

func _ready() -> void:

	# 统一标题栏：72px 英文大标题 + 26px 中文副标题（基线对齐）+ 1px 细线。
	# EN 语言下副标题自动隐藏；副标题 / 细线是标题 Label 的子节点，会跟着标题的动画走。
	TITLE_BAR.apply(_title_label, "MAP", tr("校园地图"),
			GameManager.font_tcm, GameManager.font_zh_title, TITLE_RULE_WIDTH)

	# 黑色标题带跟着标题栏收口：带子下缘 = 1px 细线所在高度 + 1，
	# 这样换字体（行高变化）时细线也不会浮在带子外面或和带子边缘叠成两条。
	var rule_y: float = _title_label.position.y + _title_label.get_minimum_size().y \
			+ TITLE_BAR.RULE_GAP
	_title_bg.offset_bottom = rule_y + 1.0

	# 应用字体到场景中的静态标签
	if GameManager.font_tcm:
		_info_name.add_theme_font_override("font", GameManager.font_tcm)
	if GameManager.font_zh_body:
		_info_desc.add_theme_font_override("font", GameManager.font_zh_body)

	_build_markers()
	_build_goto()
	_build_back_bar()
	_build_load_reveal()
	_map_clip.gui_input.connect(_on_map_clip_input)
	# 滚轮平滑只在有效时开 _process，平时完全不占帧
	set_process(false)
	# 注意：不在此管理 AudioManager.set_menu_mode —— Map 作为 Tab 菜单的
	# 子页面，音频模糊归 SceneManager 路由（MAP_FROM_VN）与 Tab 菜单
	# 生命周期统一管理（与 SettingsScene 同一模式），否则返回 Tab 时
	# _on_exit 会错误解除 Tab 菜单仍需要的低通滤波。


## 滚轮缩放的指数逼近：每一帧朝 _zoom_goal 靠近固定比例。
## 相比"每格重建 tween"，好处是永远不做速度重置 —— 连续滚轮时缩放不会一顿一顿，
## 松手后也只剩几帧收尾，不会出现"手停了还在慢慢飘"。
func _process(delta: float) -> void:
	if not _zoom_smoothing:
		set_process(false)
		return
	_zoom_vis = lerpf(_zoom_vis, _zoom_goal, 1.0 - exp(-ZOOM_SMOOTH_RATE * delta))
	if absf(_zoom_goal - _zoom_vis) <= _zoom_goal * ZOOM_SNAP_EPS:
		_zoom_vis = _zoom_goal
		_stop_zoom_smoothing()
	_apply_zoom_step(_zoom_vis)





# ===================================================================
# 地点标记
# ===================================================================

func _build_markers() -> void:
	for i: int in range(LOCATIONS.size()):
		var loc: Dictionary = LOCATIONS[i]
		var marker: Control = _create_marker(i, loc)
		_map_container.add_child(marker)
		_marker_nodes.append(marker)
	# 标签要等排版完才量得准（字体来自运行时覆盖）→ 命中区下一帧再收窄
	_fit_marker_hit_areas.call_deferred()


## 命中区收窄到标签实际宽度 —— 默认多留的 120px 会让密集地点互相抢 hover。
func _fit_marker_hit_areas() -> void:
	var floor_w: float = DOT_SIZE * 2.0 + LABEL_OFFSET_X
	for marker: Control in _marker_nodes:
		if not is_instance_valid(marker):
			continue
		var lbl: Label = marker.get_meta("label")
		if lbl == null:
			continue
		marker.size.x = maxf(LABEL_OFFSET_X + lbl.get_minimum_size().x + 4.0, floor_w)


func _create_marker(idx: int, data: Dictionary) -> Control:
	var ctrl: Control = Control.new()
	ctrl.name = "Marker_" + str(idx)
	ctrl.position = Vector2(data.x - DOT_SIZE / 2.0, data.y - DOT_SIZE / 2.0)
	ctrl.size = Vector2(DOT_SIZE + LABEL_OFFSET_X + 120.0, maxf(DOT_SIZE, 22.0))
	ctrl.mouse_filter = Control.MOUSE_FILTER_STOP
	@warning_ignore("int_as_enum_without_cast", "int_as_enum_without_match")
	ctrl.mouse_default_cursor_shape = 2

	# 圆点
	var dot: ColorRect = ColorRect.new()
	dot.name = "Dot"
	dot.size = Vector2(DOT_SIZE, DOT_SIZE)
	dot.color = DOT_IDLE
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 缩放围绕自身中心 —— 悬停 / 选中的"长大"不能把圆点拽偏
	dot.pivot_offset = Vector2(DOT_SIZE / 2.0, DOT_SIZE / 2.0)
	ctrl.add_child(dot)

	# 名称标签 — 黑色 + 白色描边
	var lbl: Label = Label.new()
	lbl.name = "Label"
	lbl.text = data.name
	lbl.position = Vector2(LABEL_OFFSET_X, LABEL_OFFSET_Y)
	lbl.add_theme_color_override("font_color", DOT_IDLE)
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.add_theme_color_override("font_outline_color", Color(1, 1, 1, 0.7))
	lbl.add_theme_constant_override("outline_size", 3)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	@warning_ignore("static_called_on_instance")
	var f: Font = GameManager.select_font(lbl.text, GameManager.font_zh_title, GameManager.font_tcm)
	if f: lbl.add_theme_font_override("font", f)
	ctrl.add_child(lbl)

	ctrl.gui_input.connect(_on_marker_input.bind(idx))
	ctrl.mouse_entered.connect(_on_marker_hover.bind(true, idx))
	ctrl.mouse_exited.connect(_on_marker_hover.bind(false, idx))
	ctrl.set_meta("dot", dot)
	ctrl.set_meta("label", lbl)
	ctrl.set_meta("label_rest_x", LABEL_OFFSET_X)
	return ctrl


# ===================================================================
# 标记状态 — 颜色 / 缩放的唯一出口（hover 与选中不会互相打架）
# ===================================================================

## 统一改标记的视觉状态。绝不碰 marker.modulate.a —— 加载揭幕正在用它做整组淡入。
func _paint_marker(idx: int, selected: bool, hovered: bool, animate: bool = true) -> void:
	if idx < 0 or idx >= _marker_nodes.size():
		return
	var marker: Control = _marker_nodes[idx]
	var dot: ColorRect = marker.get_meta("dot")
	var lbl: Label = marker.get_meta("label")
	if dot == null or lbl == null:
		return

	var dot_scale: float = DOT_SELECT_SCALE if selected \
			else (DOT_HOVER_SCALE if hovered else 1.0)
	var dot_color: Color = DOT_SELECTED if selected else DOT_IDLE
	# 选中态优先：已经变红的点不再跟着 hover 挪标签
	var lbl_x: float = float(marker.get_meta("label_rest_x", LABEL_OFFSET_X)) \
			+ (LABEL_HOVER_SHIFT if hovered and not selected else 0.0)

	# 注意：Godot 4 里 set_meta(key, null) 会「删掉」这条 meta，get_meta(key, null) 的
	# null 默认值又会被当成"没给默认值"直接报错。所以这条一律 has_meta 判存在。
	var old_tw: Tween = null
	if marker.has_meta("hover_tween"):
		old_tw = marker.get_meta("hover_tween")
	if old_tw and old_tw.is_valid():
		old_tw.kill()

	if not animate:
		dot.scale = Vector2(dot_scale, dot_scale)
		dot.color = dot_color
		lbl.position.x = lbl_x
		if marker.has_meta("hover_tween"):
			marker.remove_meta("hover_tween")
		return

	var span: float = MARKER_SELECT_TIME if selected else MARKER_HOVER_TIME
	var tw: Tween = create_tween().set_parallel(true)
	tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	# 选中用 BACK 回弹一下，读起来像"锁定"；hover 只做轻微放大（沿用 SINE）
	if selected:
		tw.tween_property(dot, "scale", Vector2(dot_scale, dot_scale), span) \
				.set_trans(Tween.TRANS_BACK)
	else:
		tw.tween_property(dot, "scale", Vector2(dot_scale, dot_scale), span)
	tw.tween_property(dot, "color", dot_color, MARKER_HOVER_TIME)
	tw.tween_property(lbl, "position:x", lbl_x, MARKER_HOVER_TIME)
	marker.set_meta("hover_tween", tw)


func _on_marker_hover(hovered: bool, idx: int) -> void:
	if _disabled or _reveal_active():
		return
	if idx < 0 or idx >= _marker_nodes.size():
		return
	# 记住 hover 态 —— 取消选中 / 切到别的点时，这支标记可能还在鼠标下，
	# 没有 mouse_entered 再补一次，得靠它把圆点放回 hover 尺寸。
	_marker_nodes[idx].set_meta("hovered", hovered)
	_paint_marker(idx, idx == _selected_idx, hovered)


## 该标记此刻是否被悬停（没有记录时按"否"处理）。
func _marker_hovered(idx: int) -> bool:
	if idx < 0 or idx >= _marker_nodes.size():
		return false
	return bool(_marker_nodes[idx].get_meta("hovered", false))


## 立即把所有标记复位（进入地图时用，不播动画）。
func _reset_markers_now() -> void:
	for i: int in range(_marker_nodes.size()):
		_marker_nodes[i].set_meta("hovered", false)
		_paint_marker(i, false, false, false)


# ===================================================================
# 进入加载揭幕
# ===================================================================

## 运行时挂一个揭幕驱动器（不改场景结构），只作用于地图贴图本身。
func _build_load_reveal() -> void:
	_load_reveal = RevealScript.new()
	_load_reveal.name = "LoadReveal"
	add_child(_load_reveal)
	_load_reveal.setup(_map_texture, _marker_nodes)


## 揭幕是否正在播放 —— 期间锁住拖拽 / 滚轮 / WASD / 标记点击
func _reveal_active() -> bool:
	return _load_reveal != null and _load_reveal.is_playing()


# ===================================================================
# 选中准星 —— 屏幕空间、横平竖直的十字叉（每次选中动态生成一个）
# ===================================================================

## 选中变化时同步准星：同一地点不重刷；换地点 → 旧准心退场，新准心重新生成。
func _sync_crosshair(idx: int) -> void:
	if idx < 0 or idx >= LOCATIONS.size():
		return
	if _crosshair != null and _crosshair_idx == idx:
		return

	# 旧准心自行播放退场动画（缩回四边后自毁），新准心同时从四边生长
	if _crosshair != null:
		_crosshair.play_retract()
		_crosshair = null

	var data: Dictionary = LOCATIONS[idx]
	var c: CrosshairScript = CrosshairScript.new()
	c.name = "Crosshair_" + str(idx)
	c.map_container = _map_container
	c.view_clip = _map_clip
	c.world_pos = Vector2(data.x, data.y)
	_map_container.add_child(c)
	# 层级：MapTexture(0) → 准星(1) → 地点标记（线压在标点之下）
	_map_container.move_child(c, 1)
	_crosshair = c
	_crosshair_idx = idx
	c.play_grow()


## 让当前准心退场（取消选中时）
func _retire_crosshair() -> void:
	if _crosshair == null:
		return
	_crosshair.play_retract()
	_crosshair = null
	_crosshair_idx = -1


## 清掉所有准星（进出地图时用，避免动画残留到下次进入）
func _clear_crosshairs() -> void:
	_crosshair = null
	_crosshair_idx = -1
	for child: Node in _map_container.get_children():
		if child.get_script() == CrosshairScript:
			child.queue_free()


# ===================================================================
# 底部返回栏
# ===================================================================

func _build_back_bar() -> void:
	_back_bar = BackBar.attach(self)


# ===================================================================
# Goto 按钮 — 包装器 + sweep 动画（参照 Notebook GotoNext）
# ===================================================================

func _build_goto() -> void:
	var parent: Node = _goto_label.get_parent()

	_goto_wrap = Panel.new()
	_goto_wrap.name = "GotoWrap"
	_goto_wrap.mouse_filter = Control.MOUSE_FILTER_STOP
	_goto_wrap.clip_contents = true

	_goto_wrap.anchor_left = _goto_label.anchor_left
	_goto_wrap.anchor_top = _goto_label.anchor_top
	_goto_wrap.anchor_right = _goto_label.anchor_right
	_goto_wrap.anchor_bottom = _goto_label.anchor_bottom
	_goto_wrap.offset_left = _goto_label.offset_left
	_goto_wrap.offset_top = _goto_label.offset_top
	_goto_wrap.offset_right = _goto_label.offset_right
	_goto_wrap.offset_bottom = _goto_label.offset_bottom

	_goto_border_style = StyleBoxFlat.new()
	_goto_border_style.bg_color = Color(0, 0, 0, 0)
	_goto_border_style.border_width_left = 1
	_goto_border_style.border_width_right = 1
	_goto_border_style.border_width_top = 1
	_goto_border_style.border_width_bottom = 1
	_goto_border_style.border_color = Color(1, 1, 1, 0.3)
	_goto_wrap.add_theme_stylebox_override("panel", _goto_border_style)

	parent.remove_child(_goto_label)
	parent.add_child(_goto_wrap)

	_goto_sweep = ColorRect.new()
	_goto_sweep.name = "Sweep"
	_goto_sweep.color = Color.WHITE
	_goto_sweep.set_anchors_preset(Control.PRESET_FULL_RECT)
	_goto_sweep.scale.x = 0.0
	_goto_sweep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_goto_wrap.add_child(_goto_sweep)

	var hb := HBoxContainer.new()
	hb.set_anchors_preset(Control.PRESET_FULL_RECT)
	hb.alignment = BoxContainer.ALIGNMENT_BEGIN
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_goto_wrap.add_child(hb)

	_goto_label.add_theme_font_size_override("font_size", 24)
	_goto_label.add_theme_color_override("font_color", Color.WHITE)
	_goto_label.visible = true
	hb.add_child(_goto_label)

	@warning_ignore("static_called_on_instance")
	var goto_font: Font = GameManager.select_font(_goto_label.text, GameManager.font_zh_title, GameManager.font_tcm)
	if goto_font:
		_goto_label.add_theme_font_override("font", goto_font)

	_goto_rest_x = _goto_wrap.position.x

	_goto_wrap.mouse_entered.connect(_on_goto_hover.bind(true))
	_goto_wrap.mouse_exited.connect(_on_goto_hover.bind(false))
	_goto_wrap.gui_input.connect(_on_goto_click)

	# 初始隐藏 — 由 set_goto_enabled() 或 _show_info_panel() 控制可见性
	_goto_wrap.position.x = _goto_rest_x + STAGGER_OFFSET
	_goto_wrap.modulate.a = 0.0
	_goto_wrap.visible = false


func _on_goto_hover(hovered: bool) -> void:
	# 用目标态判断：面板正在滑出时点击"前往"不应再生效
	if not _goto_enabled or not _panel_shown:
		return

	if _goto_hover_tween and _goto_hover_tween.is_valid():
		_goto_hover_tween.kill()

	var target_blend: float = 1.0 if hovered else 0.0
	_goto_hover_tween = create_tween().set_parallel(true)
	_goto_hover_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_goto_hover_tween.tween_property(_goto_sweep, "scale:x", target_blend, GOTO_HOVER_TIME)
	_goto_hover_tween.tween_property(_goto_wrap, "position:x",
			_goto_rest_x - 50.0 if hovered else _goto_rest_x + 10.0, GOTO_HOVER_TIME)
	_goto_hover_tween.tween_property(_goto_wrap, "modulate:a",
			1.0 if hovered else GOTO_REST_ALPHA, GOTO_HOVER_TIME)
	# 文字色跟着 sweep 一起渐变 —— 瞬切会在 sweep 覆盖到文字前出现"黑字压黑底"
	_goto_hover_tween.tween_method(_set_goto_hover_blend, _goto_hover_blend, target_blend, GOTO_HOVER_TIME)

	@warning_ignore("incompatible_ternary")
	_goto_wrap.add_theme_stylebox_override("panel", _goto_border_style if not hovered else StyleBoxEmpty.new())


## 悬停混合值 → 文字色（0 = 白字描边态，1 = 黑字白底态）。
func _set_goto_hover_blend(k: float) -> void:
	_goto_hover_blend = clampf(k, 0.0, 1.0)
	_goto_label.add_theme_color_override("font_color", Color.WHITE.lerp(Color.BLACK, _goto_hover_blend))


func _on_goto_click(event: InputEvent) -> void:
	if not _goto_enabled or not _panel_shown:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if _selected_idx < 0 or _selected_idx >= LOCATIONS.size():
			return
		AudioManager.play_click()
		goto_location_requested.emit(LOCATIONS[_selected_idx].name)
		# 地点系统："前往" = 显式操作，经 API 写入当前地点（浏览/选择不回写）
		GameManager.set_current_location(LOCATIONS[_selected_idx].name)


func set_goto_enabled(enabled: bool) -> void:
	_goto_enabled = enabled
	if not _goto_enabled:
		# 立即隐藏
		if _goto_hover_tween and _goto_hover_tween.is_valid():
			_goto_hover_tween.kill()
		_goto_hover_blend = 0.0
		_goto_label.add_theme_color_override("font_color", Color.WHITE)
		_goto_wrap.visible = false
		_goto_wrap.position.x = _goto_rest_x + STAGGER_OFFSET
		_goto_wrap.modulate.a = 0.0
		_goto_sweep.scale.x = 0.0
	elif _panel_shown:
		# 面板已显示 → 立即动画入场
		_goto_wrap.position.x = _goto_rest_x + STAGGER_OFFSET
		_goto_wrap.modulate.a = 0.0
		_goto_wrap.visible = true
		var t_goto := create_tween().set_parallel(true)
		t_goto.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		t_goto.tween_property(_goto_wrap, "position:x", _goto_rest_x, GOTO_IN_TIME)
		t_goto.tween_property(_goto_wrap, "modulate:a", GOTO_REST_ALPHA, GOTO_IN_TIME)


# ===================================================================
# 选中 / 取消选中
# ===================================================================

func _select_location(idx: int, show_info: bool = false) -> void:
	if idx < 0 or idx >= LOCATIONS.size() or _marker_nodes.size() == 0:
		return

	var same_location: bool = (idx == _selected_idx)

	if _selected_idx >= 0 and not same_location and _selected_idx < _marker_nodes.size():
		_paint_marker(_selected_idx, false, _marker_hovered(_selected_idx))

	# 从无到有的选中：等准心四臂交会后再推镜头；连续切换直接跟手
	_selection_delay = 0.0 if _crosshair != null else CROSS_ZOOM_DELAY

	_selected_idx = idx
	_last_selected_idx = idx

	# 标点及时变红 / 弹出 —— 选中即生效，不等准心
	_paint_marker(idx, true, false)

	_sync_crosshair(idx)

	if show_info and not (same_location and _panel_shown):
		_update_info_panel(idx)
	# 注意：这里不再做"贴边滚动"—— 调用方紧跟的 _center_on_location 一定会把地点
	# 摆到画面中心（并补偿信息面板），旧的滚动 tween 只会被立刻杀掉，
	# 还会让 _animate_camera 误判为"相机正在移动"，把手感切到 EASE_OUT。


func _deselect_location() -> void:
	if _selected_idx < 0:
		return
	var prev_idx: int = _selected_idx
	_selected_idx = -1
	_paint_marker(prev_idx, false, _marker_hovered(prev_idx))
	# 准心倒放：四臂缩回屏幕四边
	_retire_crosshair()
	# 面板若还在滑出就立即收尾，别让"面板滑出"和"镜头缩回"两段动画叠在一起
	_finish_panel_hide()
	_hide_info_panel()
	# 缩小回初始缩放比例 — 同时平移保持在边界内。
	# 以容器真实缩放为基准：推镜动画可能还在延迟中，_zoom_level 已指向目标值。
	var old_zoom: float = maxf(_map_container.scale.x, 0.0001)
	var clip_size: Vector2 = _map_clip.size
	if clip_size.x <= 0 or clip_size.y <= 0:
		return
	# 保持当前画面中心不变，但遵守新的边界约束。_guard_pan_bounds 读 _zoom_level，
	# 所以先把它指向目标缩放。
	var world_center: Vector2 = (clip_size / 2.0 - _map_container.position) / old_zoom
	var target_zoom: float = _zoom_min
	_zoom_level = target_zoom
	var target: Vector2 = clip_size / 2.0 - world_center * target_zoom
	target = _guard_pan_bounds(target)
	_animate_camera(target, target_zoom, 0.0, CAM_RETURN_TIME)


# ===================================================================
# 信息面板
# ===================================================================

func _update_info_panel(idx: int) -> void:
	var data: Dictionary = LOCATIONS[idx]
	_info_name.text = data.name
	@warning_ignore("static_called_on_instance")
	var nf: Font = GameManager.select_font(_info_name.text, GameManager.font_zh_title, GameManager.font_tcm)
	if nf: _info_name.add_theme_font_override("font", nf)
	# 白色背景 + 黑色文字 + 阴影（匹配 ESC 菜单品牌框风格）
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color.WHITE
	sb.shadow_size = 0
	sb.shadow_offset = Vector2(8, 6)
	sb.shadow_color = Color(1, 1, 1, 0.1)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	_info_name.add_theme_color_override("font_color", Color.BLACK)
	_info_name.add_theme_stylebox_override("normal", sb)

	_info_desc.text = data.description
	@warning_ignore("static_called_on_instance")
	var df: Font = GameManager.select_font(_info_desc.text, GameManager.font_zh_body, GameManager.font_en_body)
	if df: _info_desc.add_theme_font_override("font", df)
	_info_desc.add_theme_color_override("font_color", Color(1, 1, 1, 0.5))

	# 面板已经开着 → 内容换了，让文字轻轻浮现一下（整块瞬替看起来像卡了一帧）
	if _panel_shown and _info_panel.visible:
		_flash_info_text()
	# 不判断 visible —— 面板正在滑出时也要能原路滑回来
	_show_info_panel()


## 切地点时让右侧文字轻轻浮现，避免整块内容瞬间替换（对齐日历页 _flash_detail）。
## 名称是黑字压白底：只淡字色，别动 modulate，否则白色标题条会一起闪。
func _flash_info_text() -> void:
	if not _info_panel.visible:
		return
	if _detail_tween and _detail_tween.is_valid():
		_detail_tween.kill()
	_info_name.add_theme_color_override("font_color", Color(0, 0, 0, 0.35))
	_info_desc.modulate.a = 0.45
	_detail_tween = create_tween().set_parallel(true)
	_detail_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_detail_tween.tween_method(_set_info_name_alpha, 0.35, 1.0, INFO_FLASH_TIME)
	_detail_tween.tween_property(_info_desc, "modulate:a", 1.0, INFO_FLASH_TIME)


## tween_method 专用 —— 不依赖「theme override 是否可被 tween_property」这一未验证行为。
func _set_info_name_alpha(a: float) -> void:
	_info_name.add_theme_color_override("font_color", Color(0, 0, 0, clampf(a, 0.0, 1.0)))


## 面板完全移出右侧所需的偏移 —— 只需自身宽度（约 422px），不需要整屏宽。
## 旧版用视口宽 1280px，多走了 858px，滑入速度被迫快 3 倍，看起来像被甩进来。
func _panel_hidden_offset() -> float:
	return maxf(_info_panel.size.x, 1.0) + PANEL_EDGE_PAD


func _show_info_panel() -> void:
	# 提升到最上层 — 覆盖地图标记和标题
	_info_panel.z_index = 10

	# 已经显示中（且没被请求隐藏）→ 只更新内容，不重播动画
	if _panel_shown and _info_panel.visible:
		return

	# 正在滑出（刚按过 ESC）→ 从当前位置原路滑回；完全隐藏 → 从右侧屏外入场
	var was_hidden: bool = not _info_panel.visible
	_panel_shown = true

	if _panel_tween and _panel_tween.is_valid():
		_panel_tween.kill()

	# 面板从右侧滑入（只动画面板自身，不碰地图位移）
	@warning_ignore("shadowed_variable_base_class")
	var hidden: float = _panel_hidden_offset()

	if was_hidden:
		_info_panel.offset_left = hidden
		_info_panel.offset_right = hidden
		_info_panel.modulate.a = 1.0
	_info_panel.visible = true

	_panel_tween = create_tween().set_parallel(true)
	_panel_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_panel_tween.tween_property(_info_panel, "offset_left", 0.0, PANEL_IN_TIME)
	_panel_tween.tween_property(_info_panel, "offset_right", 0.0, PANEL_IN_TIME)

	# 只有从"完全隐藏"入场才重播内部元素；滑出被打断时内部元素本来就在原位
	if not was_hidden:
		return

	# ── 内部元素逐级入场（对齐 QuitModal 模式：右侧滑入 + 淡入）──
	# 先掐掉上一次没播完的入场动画，并回到静止位 —— 否则快速 ESC / 空格
	# 打断入场后，标签会以"当前位置"作为新目标，位置逐次累积偏移。
	_kill_info_intro()
	if not _info_rest_saved:
		_info_rest_name = _info_name.position.x
		_info_rest_desc = _info_desc.position.x
		_info_rest_suggest = _info_suggest.position.x
		_info_rest_saved = true
	_info_name.position.x = _info_rest_name
	_info_desc.position.x = _info_rest_desc
	_info_suggest.position.x = _info_rest_suggest
	_info_name.modulate.a = 1.0
	_info_desc.modulate.a = 1.0
	_info_suggest.modulate.a = 1.0

	# 节奏：从 PANEL_BASE_DELAY 起手，每项 +PANEL_STEP，单项 PANEL_ITEM_TIME。
	# 旧版 0.5s × 80ms 步长整段要 0.94s —— 读起来是"一下全出现，然后慢慢爬"。
	var d_border: float = PANEL_BASE_DELAY
	var d_name: float = PANEL_BASE_DELAY + PANEL_STEP
	var d_desc: float = PANEL_BASE_DELAY + PANEL_STEP * 2.0
	var d_suggest: float = PANEL_BASE_DELAY + PANEL_STEP * 3.0
	var d_goto: float = PANEL_BASE_DELAY + PANEL_STEP * 4.0

	# BorderBot — 分割线横向展开
	_info_border.scale = Vector2(0.0, 1.0)
	var t_border := create_tween()
	t_border.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t_border.tween_property(_info_border, "scale:x", 1.0, PANEL_ITEM_TIME).set_delay(d_border)
	_info_intro_tweens.append(t_border)

	# NameLabel — 右侧滑入 + 淡入
	_info_name.position.x = _info_rest_name + 50.0
	_info_name.modulate.a = 0.0
	var t_name := create_tween().set_parallel(true)
	t_name.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t_name.tween_property(_info_name, "position:x", _info_rest_name, PANEL_ITEM_TIME).set_delay(d_name)
	t_name.tween_property(_info_name, "modulate:a", 1.0, PANEL_ITEM_TIME).set_delay(d_name)
	_info_intro_tweens.append(t_name)

	# DescLabel — 右侧滑入 + 淡入
	_info_desc.position.x = _info_rest_desc + 50.0
	_info_desc.modulate.a = 0.0
	var t_desc := create_tween().set_parallel(true)
	t_desc.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t_desc.tween_property(_info_desc, "position:x", _info_rest_desc, PANEL_ITEM_TIME).set_delay(d_desc)
	t_desc.tween_property(_info_desc, "modulate:a", 1.0, PANEL_ITEM_TIME).set_delay(d_desc)
	_info_intro_tweens.append(t_desc)

	# SuggestLabel — 右侧滑入 + 淡入
	_info_suggest.position.x = _info_rest_suggest + 50.0
	_info_suggest.modulate.a = 0.0
	var t_suggest := create_tween().set_parallel(true)
	t_suggest.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t_suggest.tween_property(_info_suggest, "position:x", _info_rest_suggest, PANEL_ITEM_TIME).set_delay(d_suggest)
	t_suggest.tween_property(_info_suggest, "modulate:a", 1.0, PANEL_ITEM_TIME).set_delay(d_suggest)
	_info_intro_tweens.append(t_suggest)

	# Goto 按钮 — 仅在启用时跟随入场（参照 Notebook 内容元素动画）
	if _goto_enabled:
		_goto_wrap.position.x = _goto_rest_x + STAGGER_OFFSET
		_goto_wrap.modulate.a = 0.0
		_goto_wrap.visible = true
		var t_goto := create_tween().set_parallel(true)
		t_goto.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		t_goto.tween_property(_goto_wrap, "position:x", _goto_rest_x, PANEL_ITEM_TIME).set_delay(d_goto)
		t_goto.tween_property(_goto_wrap, "modulate:a", GOTO_REST_ALPHA, PANEL_ITEM_TIME).set_delay(d_goto)
		_info_intro_tweens.append(t_goto)


## 掐掉面板内部元素的入场 / 浮现动画（快速 ESC / 空格打断时防止状态累积）
func _kill_info_intro() -> void:
	for tw: Tween in _info_intro_tweens:
		if tw and tw.is_valid():
			tw.kill()
	_info_intro_tweens.clear()
	if _detail_tween and _detail_tween.is_valid():
		_detail_tween.kill()
	_detail_tween = null
	_info_name.add_theme_color_override("font_color", Color.BLACK)
	_info_desc.modulate.a = 1.0


func _hide_info_panel() -> void:
	# 目标态已经是"隐藏"（或面板已消失）→ 无操作，连按 ESC 不会重启动画
	if not _panel_shown:
		return
	_panel_shown = false

	# 滑出前掐掉没播完的入场 —— 否则面板在退、里面的字还在往里飘
	_kill_info_intro()

	# 面板向右滑出
	if _panel_tween and _panel_tween.is_valid():
		_panel_tween.kill()

	@warning_ignore("shadowed_variable_base_class")
	var hidden: float = _panel_hidden_offset()
	_panel_tween = create_tween().set_parallel(true)
	_panel_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_panel_tween.tween_property(_info_panel, "offset_left", hidden, PANEL_OUT_TIME)
	_panel_tween.tween_property(_info_panel, "offset_right", hidden, PANEL_OUT_TIME)
	_panel_tween.chain().tween_callback(_on_panel_hidden)

	# 降回默认层级，避免遮挡其他 UI
	_info_panel.z_index = 0

	# 面板退场后右侧空间空出来了 —— 把选中地点挪回"没有面板时"的画面中心
	_recenter_selected(PANEL_OUT_TIME + 0.1)


## 面板收起后把选中地点重新摆回画面中心（保持当前缩放，不改变推镜倍率）
func _recenter_selected(duration: float = 0.3) -> void:
	if _selected_idx < 0 or _selected_idx >= LOCATIONS.size():
		return
	_center_on_location(_selected_idx, _zoom_level, 0.0, duration)


## 把"正在滑出"的面板立即收尾 —— 下一步动作（取消选中 / 切地点）不该和它叠在一起。
## 注意：面板完整显示时不做处理，那条路径走正常的滑出动画。
func _finish_panel_hide() -> void:
	if _panel_shown or not _info_panel.visible:
		return
	if _panel_tween and _panel_tween.is_valid():
		_panel_tween.kill()
	@warning_ignore("shadowed_variable_base_class")
	var hidden: float = _panel_hidden_offset()
	_info_panel.offset_left = hidden
	_info_panel.offset_right = hidden
	_info_panel.z_index = 0
	_on_panel_hidden()


func _on_panel_hidden() -> void:
	_info_panel.visible = false
	_panel_shown = false
	# 重置 Goto 按钮位置，为下次入场动画做准备
	if _goto_wrap:
		if _goto_hover_tween and _goto_hover_tween.is_valid():
			_goto_hover_tween.kill()
		_goto_hover_blend = 0.0
		_goto_wrap.position.x = _goto_rest_x + STAGGER_OFFSET
		_goto_wrap.modulate.a = 0.0
		_goto_wrap.visible = false
		_goto_sweep.scale.x = 0.0
		_goto_label.add_theme_color_override("font_color", Color.WHITE)
		_goto_wrap.add_theme_stylebox_override("panel", _goto_border_style)


## 立即把信息面板收回初始状态（进入地图时清理上次残留，不播动画）。
func _reset_info_panel_now() -> void:
	if _panel_tween and _panel_tween.is_valid():
		_panel_tween.kill()
	_kill_info_intro()
	if _info_rest_saved:
		_info_name.position.x = _info_rest_name
		_info_desc.position.x = _info_rest_desc
		_info_suggest.position.x = _info_rest_suggest
		_info_name.modulate.a = 1.0
		_info_desc.modulate.a = 1.0
		_info_suggest.modulate.a = 1.0
		_info_border.scale = Vector2.ONE
	_info_panel.offset_left = 0.0
	_info_panel.offset_right = 0.0
	_info_panel.z_index = 0
	_panel_shown = false
	if _info_panel.visible:
		_on_panel_hidden()


# ===================================================================
# 自动滚动
# ===================================================================

## 硬边界：地图永远盖满裁剪区，任何方向都不许露出地图外的空白。
## 注意别再改成"越界阻尼/回弹"——那会在拖到边缘时把地图外的背景露出来。
func _clamp_pan() -> void:
	var clip_size: Vector2 = _map_clip.size
	var map_w: float = MAP_W * _zoom_level
	var map_h: float = MAP_H * _zoom_level
	var min_x: float = minf(clip_size.x - map_w, 0.0)
	var min_y: float = minf(clip_size.y - map_h, 0.0)
	_map_container.position.x = clampf(_map_container.position.x, min_x, 0.0)
	_map_container.position.y = clampf(_map_container.position.y, min_y, 0.0)


func _center_on_location(idx: int, zoom: float = KEYBOARD_ZOOM, delay: float = -1.0, duration: float = -1.0) -> void:
	var data: Dictionary = LOCATIONS[idx]
	var loc_center: Vector2 = Vector2(data.x, data.y)
	var clip_size: Vector2 = _map_clip.size
	if clip_size.x <= 0 or clip_size.y <= 0:
		return

	# delay < 0 → 自动：从无到有的选中先等准心四臂交会，再推镜头（"先锁定后放大"）
	var wait: float = delay
	if wait < 0.0:
		wait = _selection_delay

	# 更新缩放并计算居中位置（用目标缩放来算边界）
	var new_zoom: float = clampf(zoom, _zoom_min, ZOOM_MAX)
	_zoom_level = new_zoom

	# 尽量居中该地点，但不超出图片边界
	var target: Vector2 = clip_size / 2.0 - loc_center * _zoom_level
	# 若信息面板已显示（含正在滑入），向左偏移以补偿面板占用的右侧空间，
	# 确保地点出现在可视区域的中心而非被面板遮挡。
	if _panel_shown:
		target.x -= PANEL_SHIFT
	target = _guard_pan_bounds(target)
	# duration < 0 → 按行程自动定时长
	_animate_camera(target, new_zoom, wait, duration)


## 确保平移目标不超出地图边界 — "尽量居中，遇边界则贴边"。
func _guard_pan_bounds(target: Vector2) -> Vector2:
	var clip_size: Vector2 = _map_clip.size
	var map_w: float = MAP_W * _zoom_level
	var map_h: float = MAP_H * _zoom_level
	var clamped: Vector2 = target
	clamped.x = clampf(clamped.x, minf(clip_size.x - map_w, 0.0), 0.0)
	clamped.y = clampf(clamped.y, minf(clip_size.y - map_h, 0.0), 0.0)
	return clamped


## 相机统一入口 —— 位置与缩放共用一条 tween、同一时长 / 延时 / 曲线。
## 这是「被追踪地点在屏幕上纹丝不动」的前提：两条通道进度一致时，
## 屏幕坐标 pos + world * zoom 对进度是线性的，插值过程中焦点不会漂。
##   decel = true → 给惯性滑行用（QUAD EASE_OUT，从起手就减速）
## 被打断（按住 WASD 连续切点 / 连点不同地点）时改用 EASE_OUT：此时相机本来就在动，
## 再从静止重新起步会每 30ms 顿一下 —— 按住方向键会变成"慢慢挪"。
func _animate_camera(target: Vector2, target_zoom: float, delay: float = 0.0,
		duration: float = -1.0, decel: bool = false) -> void:
	var resuming: bool = _pan_tween != null and _pan_tween.is_valid()
	if resuming:
		_pan_tween.kill()
	_stop_zoom_smoothing()

	# 以容器真实缩放为基准：上一次动画可能被拖拽 / 滚轮打断
	var from_zoom: float = maxf(_map_container.scale.x, 0.0001)
	var dur: float = duration
	if dur <= 0.0:
		dur = _camera_time(_map_container.position, from_zoom, target, target_zoom)
	_zoom_level = clampf(target_zoom, _zoom_min, ZOOM_MAX)
	_zoom_goal = _zoom_level

	_pan_tween = create_tween().set_parallel(true)
	if decel or resuming:
		_pan_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	else:
		# QUAD EASE_IN_OUT：首帧位移约 0.6%（不会"弹一下"），但峰值速度是均速的 2 倍，
		# 中段比 SINE 更"敢走"——只换成 SINE 会软绵绵、跟不上手。
		_pan_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	# 并行组里只有 set_delay 会真正推迟起步（tween_interval 不会影响同组兄弟）
	_pan_tween.tween_property(_map_container, "position", target, dur).set_delay(delay)
	_pan_tween.tween_property(_map_container, "scale",
			Vector2(_zoom_level, _zoom_level), dur).set_delay(delay)


## 相机时长按行程自适应：挪得远 / 缩得多就慢一点，微调就快一点。
func _camera_time(from_pos: Vector2, from_zoom: float, to_pos: Vector2, to_zoom: float) -> float:
	var travel: float = (to_pos - from_pos).length()
	travel += absf(log(maxf(to_zoom, 0.0001) / maxf(from_zoom, 0.0001))) * CAM_ZOOM_WEIGHT
	return clampf(CAM_MIN_TIME + travel / CAM_SPEED, CAM_MIN_TIME, CAM_MAX_TIME)


## 滚轮缩放的每一帧：以「光标下的世界点」为不动点重算平移。
func _apply_zoom_step(v: float) -> void:
	_zoom_level = v
	_map_container.scale = Vector2(v, v)
	_map_container.position = _zoom_anchor_screen - _zoom_anchor_world * v
	_clamp_pan()


# ===================================================================
# 平移 / 缩放
# ===================================================================

func _on_map_clip_input(event: InputEvent) -> void:
	if _disabled or _reveal_active(): return

	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				# 手动拖拽优先 — 打断入场推镜头 / 自动滚动 / 甩动惯性
				_begin_drag(_viewport_mouse())
			else:
				var was_dragging: bool = _dragging
				_dragging = false
				if was_dragging:
					_release_drag()
				elif _selected_idx >= 0:
					_deselect_location()

	elif event is InputEventMouseMotion:
		var mm: InputEventMouseMotion = event as InputEventMouseMotion
		if mm.button_mask & 1:
			_update_drag(_viewport_mouse())


## 拖拽一律用视口鼠标坐标。
## 标记转发过来的事件是「标记局部 + 地图缩放」空间 —— gui_input 里的 position 与
## global_position 都被控件变换改写过，直接用会让 delta 缩水、起手还跳一下。
func _viewport_mouse() -> Vector2:
	return get_viewport().get_mouse_position()


## 按下：记录拖拽起点（视口坐标，见 _viewport_mouse）。
func _begin_drag(pos: Vector2) -> void:
	_stop_map_motion()
	_dragging = false
	_drag_start = pos
	_pan_start = _map_container.position
	_drag_last_pos = pos
	_drag_last_ms = Time.get_ticks_msec()
	_drag_vel = Vector2.ZERO


## 拖动中：跟手 + 估算松手速度。边界一律硬夹，拖到边缘地图就停住，不会露出图外。
func _update_drag(pos: Vector2) -> void:
	var delta: Vector2 = pos - _drag_start
	if not _dragging and delta.length() > DRAG_THRESHOLD:
		_dragging = true
		# 起手瞬间可能还挂着推镜 tween（标记按下会先居中）→ 掐掉并以当前位置为新基准，
		# 否则 tween 会和拖拽抢 position，表现为"一拖就跳一下"
		_stop_map_motion()
		_drag_start = pos
		_pan_start = _map_container.position
		_drag_last_pos = pos
		_drag_last_ms = Time.get_ticks_msec()
		_drag_vel = Vector2.ZERO
		delta = Vector2.ZERO
	if _dragging:
		var now: int = Time.get_ticks_msec()
		var elapsed: int = now - _drag_last_ms
		var dt: float = clampf(float(elapsed) / 1000.0, 0.008, 0.05)
		var step: Vector2 = pos - _drag_last_pos
		# 停顿超过 120ms 再动 → 上一段速度已失效，别接着甩
		if elapsed > 120:
			_drag_vel = Vector2.ZERO
		else:
			_drag_vel = _drag_vel.lerp(step / dt, 0.35).limit_length(FLING_MAX_SPEED)
		_drag_last_pos = pos
		_drag_last_ms = now
		_map_container.position = _pan_start + delta
	_clamp_pan()


## 松手：有速度就按惯性滑一段（目标同样过边界夹取，滑到边缘就停）。
func _release_drag() -> void:
	var speed: float = _drag_vel.length()
	if Time.get_ticks_msec() - _drag_last_ms > 100:
		# 松手前已经停住 → 不甩
		speed = 0.0
	if speed > FLING_MIN_SPEED:
		var target: Vector2 = _guard_pan_bounds(_map_container.position + _drag_vel * FLING_DECAY)
		_animate_camera(target, _zoom_level, 0.0, FLING_TIME, true)
	_drag_vel = Vector2.ZERO


# ===================================================================
# 标记点击
# ===================================================================

func _on_marker_input(event: InputEvent, idx: int) -> void:
	if _disabled or _reveal_active(): return
	# 从标记上起手也能拖地图 —— 按下 / 拖动 / 松手都转给同一套拖拽逻辑。
	# 标记是 MapContainer 的子节点，事件坐标是「标记局部 + 地图缩放」空间，
	# 所以拖拽内部只用 _viewport_mouse()，不读事件里的 position。
	if event is InputEventMouseMotion and (event as InputEventMouseMotion).button_mask & 1:
		_on_map_clip_input(event)
		return
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if not mb.pressed:
			var was_dragging: bool = _dragging
			_dragging = false
			if was_dragging:
				_release_drag()
			return
		_begin_drag(_viewport_mouse())
		_play_click()
		if _selected_idx == idx:
			_deselect_location()
		else:
			_select_location(idx, true)
			_center_on_location(idx)


# ===================================================================
# 键盘 / 滚轮 输入
# ===================================================================

func _input(event: InputEvent) -> void:
	if _disabled or not _menu_active:
		return

	# ── 加载揭幕期间：键盘任意键直接跳到揭幕完成，其余输入全部吞掉 ──
	# （地图此时还在逐块显形，拖拽 / 缩放 / 开面板都该被锁住）
	if _reveal_active():
		if event is InputEventKey and event.is_pressed():
			_load_reveal.skip()
		get_viewport().set_input_as_handled()
		return

	# ── 滚轮缩放（_input 中处理确保不被拦截）──
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_apply_zoom(ZOOM_STEP, mb.position)
			return
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_apply_zoom(1.0 / ZOOM_STEP, mb.position)
			return
		return

	if event is InputEventMouseMotion:
		return

	if not event.is_pressed():
		return

	# 键盘自动重复（按住不放）只允许驱动 WASD 连续切换地点；
	# "开面板 / 返回"这类离散动作必须一次按键一次 —— 否则按住 ESC 会在几十毫秒内
	# 连续走完「关面板 → 取消选中 → 返回」三步，看起来就像按键失控。
	if event.is_echo() and (event.is_action("ui_accept") or event.is_action("ui_cancel")):
		get_viewport().set_input_as_handled()
		return

	# Enter / Space → 弹出当前选中地点的详情框（无选中时恢复上次选中）
	if event.is_action_pressed("ui_accept"):
		if _selected_idx >= 0:
			_update_info_panel(_selected_idx)
			# 重新居中当前地点，不需要等准心（它早已展开）
			_center_on_location(_selected_idx, KEYBOARD_ZOOM, 0.0)
		elif _last_selected_idx >= 0:
			_select_location(_last_selected_idx, true)
			_center_on_location(_last_selected_idx)
		_play_click()
		get_viewport().set_input_as_handled()
		return

	# ESC — 三步：先关信息面板，再取消选中，最后返回。
	# 用目标态 _panel_shown 判定（而不是面板 visible）：面板正在滑出时再按 ESC
	# 会直接进入下一步，不会被动画期间的防抖吞掉、也不会让视角停在放大状态。
	if event.is_action_pressed("ui_cancel"):
		if _panel_shown:
			_hide_info_panel()
		elif _selected_idx >= 0:
			_deselect_location()
		elif _can_go_back:
			back_requested.emit()

		get_viewport().set_input_as_handled()
		return

	# WASD / 方向键
	var dx: int = 0
	var dy: int = 0
	if event.is_action_pressed("ui_up"):    dy = -1
	elif event.is_action_pressed("ui_down"):  dy = 1
	elif event.is_action_pressed("ui_left"):  dx = -1
	elif event.is_action_pressed("ui_right"): dx = 1

	if dx != 0 or dy != 0:
		if _selected_idx < 0:
			var start_idx: int = _last_selected_idx if _last_selected_idx >= 0 else 0
			_select_location(start_idx)
			_center_on_location(start_idx)
		else:
			var new_idx: int = _find_nearest_in_direction(dx, dy)
			# 用目标态判断：面板正在滑出时切换地点不应该又把它拉回来
			var show_info: bool = _panel_shown
			if new_idx >= 0:
				_play_click()
				_select_location(new_idx, show_info)
				_center_on_location(new_idx)
			else:
				# 死路 — 无地点可跳转，重新选中当前位置使其居中
				_play_click()
				_select_location(_selected_idx, show_info)
				_center_on_location(_selected_idx)
		get_viewport().set_input_as_handled()


func _find_nearest_in_direction(dx: int, dy: int) -> int:
	var cur: Dictionary = LOCATIONS[_selected_idx]
	var cx: float = cur.x
	var cy: float = cur.y
	var best_idx: int = -1
	var best_dist: float = INF

	for i: int in range(LOCATIONS.size()):
		if i == _selected_idx:
			continue
		var loc: Dictionary = LOCATIONS[i]
		var lx: float = loc.x
		var ly: float = loc.y
		var x_diff: float = lx - cx
		var y_diff: float = ly - cy

		# 方向过滤
		if dx < 0 and x_diff >= 0: continue
		if dx > 0 and x_diff <= 0: continue
		if dy < 0 and y_diff >= 0: continue
		if dy > 0 and y_diff <= 0: continue

		# 加权距离 — 主轴全权重，垂直轴 ×3 惩罚
		var dist: float = 0.0
		if dx != 0:
			dist = absf(x_diff) + absf(y_diff) * 3.0
		else:
			dist = absf(y_diff) + absf(x_diff) * 3.0

		if best_idx < 0 or dist < best_dist:
			best_dist = dist
			best_idx = i

	return best_idx


func _apply_zoom(factor: float, anchor_screen: Vector2) -> void:
	# 连续滚动：目标继续累加；显示值由指数逼近追上去。
	# 每一格都立刻改变目标 → 缩放手感跟手，不会"手停了画面还在慢慢挪"。
	var goal_base: float = _zoom_goal if _zoom_smoothing else maxf(_map_container.scale.x, 0.0001)
	var new_goal: float = clampf(goal_base * factor, _zoom_min, ZOOM_MAX)
	if is_equal_approx(new_goal, goal_base) and not _zoom_smoothing:
		return

	# 滚轮优先 — 打断入场推镜头 / 自动滚动 / 甩动惯性
	_stop_map_motion()

	if not _zoom_smoothing:
		_zoom_vis = maxf(_map_container.scale.x, 0.0001)
	# 每格都按"此刻的光标"重新锚定：地图始终绕着鼠标缩放
	_zoom_anchor_screen = anchor_screen
	_zoom_anchor_world = (anchor_screen - _map_container.position) / _zoom_vis
	_zoom_goal = new_goal
	_zoom_smoothing = true
	set_process(true)


## 停掉滚轮平滑（相机 tween / 拖拽 / 离开页面时都要先接管缩放）。
func _stop_zoom_smoothing() -> void:
	if not _zoom_smoothing:
		return
	_zoom_smoothing = false
	set_process(false)


## 打断进行中的平移 / 缩放动画（用户手动拖拽或滚轮时调用）。
## 关键：把 _zoom_level 拉回「实际停在的缩放」—— 否则 _clamp_pan 会用目标缩放算边界，
## 中途打断再拖拽就能把地图拖出画面（黑边）。
func _stop_map_motion() -> void:
	if _pan_tween and _pan_tween.is_valid():
		_pan_tween.kill()
	_pan_tween = null
	_stop_zoom_smoothing()
	_zoom_level = maxf(_map_container.scale.x, 0.0001)
	_zoom_goal = _zoom_level
	_zoom_vis = _zoom_level
	_clamp_pan()


# ===================================================================
# SceneManager 生命周期
# ===================================================================

func _on_enter() -> void:
	_disabled = false
	# 上次离开时残留的平移 / 面板 / 标记 / 准星状态先清空，保证每次进入都是入场动画
	_stop_map_motion()
	_reset_info_panel_now()
	_reset_markers_now()
	_clear_crosshairs()

	# 首次选中 = 当前地点（存档作用域 current_location）；
	# 未设置 / 不在地图上 → 默认北门（LOCATIONS 第一项）。选择浏览不回写。
	var loc_idx: int = MapData.get_index(GameManager.get_current_location())
	var idx: int = loc_idx if loc_idx >= 0 else 0

	# 进入加载揭幕：先把地图扣成黑块，与整页滑入同时开始（不额外叠加时长），
	# 避免进入首帧先闪一下整张地图。
	if _load_reveal != null:
		var data: Dictionary = LOCATIONS[idx]
		_load_reveal.play(Vector2(data.x, data.y))

	# 等待一帧使布局生效，然后计算初始缩放：地图至少填满裁剪区 → 无黑边
	await get_tree().process_frame
	if _disabled:
		return
	var clip_size: Vector2 = _map_clip.size
	if clip_size.x > 0 and clip_size.y > 0:
		var fit_x: float = clip_size.x / MAP_W
		var fit_y: float = clip_size.y / MAP_H
		_zoom_min = maxf(fit_x, fit_y)
		_zoom_level = _zoom_min
		_map_container.scale = Vector2(_zoom_level, _zoom_level)
		# 居中
		_map_container.position = (clip_size - Vector2(MAP_W, MAP_H) * _zoom_level) / 2.0

	_menu_active = true

	# 揭幕还在播 → 等它铺满整张地图（期间输入被锁，任意键可跳过）
	if _load_reveal != null and _load_reveal.is_playing():
		await _load_reveal.finished
		if not _menu_active:
			return

	_select_location(idx, false)
	# 四臂从屏幕四边交于当前地点（如第一章开场的校门），交会后再推近镜头
	_center_on_location(idx, ENTRY_ZOOM, ENTRY_ZOOM_DELAY, ENTRY_PAN_TIME)

func _on_exit() -> void:
	_disabled = true
	_menu_active = false
	# 平移 / 缩放 / 甩动惯性全部停掉 —— 页面正在滑出，别让 tween 跨页存活
	_stop_map_motion()
	# 揭幕还在播（含正在等它 await 的入场流程）→ 立刻收尾，避免协程卡住
	if _load_reveal != null:
		_load_reveal.skip()
	# 准星直接清掉 — 页面正在滑出，无需播放回收动画，也避免残留到下次进入
	_clear_crosshairs()
	# 音频模糊保持不变 —— 返回路径上 Tab 菜单已重新打开（_open_tab_menu
	# 先于本回调执行），此处若关闭菜单模式会覆盖 Tab 菜单刚开启的低通滤波。
	# 最终关闭由 VNInterface._on_tab_menu_closed / _back_to_menu 负责。


# ===================================================================
# 辅助
# ===================================================================

func _play_click() -> void:
	AudioManager.play_click()


## 控制场景是否可通过 ESC / BackBar 返回上一级。
## 当 @return scene:MAP 经 FlowManager 直接从剧本跳转且无法返回时，设为 false。
func set_can_go_back(can: bool) -> void:
	_can_go_back = can
	if _back_bar:
		_back_bar.visible = can


func set_disabled(val: bool) -> void:
	_disabled = val
