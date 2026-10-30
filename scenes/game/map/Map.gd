## Map : Control
## 学校地图页面。全部 UI 节点在代码中构建。
##   鼠标拖拽 → 平移 / 滚轮 → 缩放 / WASD → 切换地点
##   选中地点 → 动态生成屏幕空间十字准星（四臂从屏幕四边交于该点）+ 推近镜头
##   取消选中 → 准星倒放收回 / 切换地点 → 旧准心退场、新准心重新生成
extends Control

signal back_requested()
signal goto_location_requested(location_name: String)

# ---------------------------------------------------------------------------
# 地点数据 — 上移至 scripts/resources/MapData.gd（地点系统共享：@locate / API 校验）
# ---------------------------------------------------------------------------
const LOCATIONS: Array[Dictionary] = MapData.LOCATIONS

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
const SCROLL_MARGIN: float = 100.0
const GOTO_REST_ALPHA: float = 0.75
const STAGGER_OFFSET: float = 50.0
const PANEL_IN_TIME: float = 0.28
const PANEL_OUT_TIME: float = 0.2

# ── 选中准星（屏幕空间的横平竖直两条线，压在标点之下；标记选中即变红）──
const CROSS_ZOOM_DELAY: float = 0.15               # 选中后先让准心起手，再推镜头（要短，否则按下去像没反应）
const ENTRY_ZOOM: float = 1.5                      # 进入地图时聚焦当前地点的缩放
const ENTRY_ZOOM_DELAY: float = 0.5                # 等场景滑入完成后再推镜头
const ENTRY_PAN_TIME: float = 0.65

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
var _pan_tween: Tween = null
var _zoom_tween: Tween = null
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
var _goto_wrap: Panel = null
var _goto_sweep: ColorRect = null
var _goto_border_style: StyleBoxFlat = null
var _goto_rest_x: float = 0.0
var _goto_hover_tween: Tween = null
var _goto_enabled: bool = false

# ── 选中准星（每次选中动态生成，见 _sync_crosshair）──
var _crosshair: MapCrosshair = null
var _crosshair_idx: int = -1
var _selection_delay: float = 0.0

# ---------------------------------------------------------------------------
# 字体
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# UI 节点 — 静态节点在 Map.tscn 中，代码通过 @onready 引用
# ---------------------------------------------------------------------------
@onready var _title_label: Label = $TitleLabel
@onready var _subtitle_label: Label = $SubtitleLabel
@onready var _map_clip: Control = $MapClip
@onready var _map_container: Control = $MapClip/MapContainer
@onready var _info_panel: Control = $InfoPanel
@onready var _info_name: Label = $InfoPanel/NameLabel
@onready var _info_desc: Label = $InfoPanel/DescLabel
@onready var _info_suggest: Label = $InfoPanel/SuggestLabel
@onready var _info_border: ColorRect = $InfoPanel/BorderBot
@onready var _goto_label: Label = $InfoPanel/Goto
var _back_bar: BackBar = null


# ===================================================================
# 生命周期
# ===================================================================

func _ready() -> void:

	# 字幕标签 — 文本和可见性在运行时确定
	_subtitle_label.text = tr("校园地图")
	if GameManager.is_locale("en"):
		_subtitle_label.visible = false

	# 应用字体到场景中的静态标签
	if GameManager.font_tcm:
		_title_label.add_theme_font_override("font", GameManager.font_tcm)
		_info_name.add_theme_font_override("font", GameManager.font_tcm)
	if GameManager.font_zh_title:
		_subtitle_label.add_theme_font_override("font", GameManager.font_zh_title)
	if GameManager.font_zh_body:
		_info_desc.add_theme_font_override("font", GameManager.font_zh_body)

	_build_markers()
	_build_goto()
	_build_back_bar()
	_map_clip.gui_input.connect(_on_map_clip_input)
	# 注意：不在此管理 AudioManager.set_menu_mode —— Map 作为 Tab 菜单的
	# 子页面，音频模糊归 SceneManager 路由（MAP_FROM_VN）与 Tab 菜单
	# 生命周期统一管理（与 SettingsScene 同一模式），否则返回 Tab 时
	# _on_exit 会错误解除 Tab 菜单仍需要的低通滤波。





# ===================================================================
# 地点标记
# ===================================================================

func _build_markers() -> void:
	for i: int in range(LOCATIONS.size()):
		var loc: Dictionary = LOCATIONS[i]
		var marker: Control = _create_marker(i, loc)
		_map_container.add_child(marker)
		_marker_nodes.append(marker)


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
	dot.color = Color.BLACK
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ctrl.add_child(dot)

	# 名称标签 — 黑色 + 白色描边
	var lbl: Label = Label.new()
	lbl.name = "Label"
	lbl.text = data.name
	lbl.position = Vector2(LABEL_OFFSET_X, LABEL_OFFSET_Y)
	lbl.add_theme_color_override("font_color", Color.BLACK)
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.add_theme_color_override("font_outline_color", Color(1, 1, 1, 0.7))
	lbl.add_theme_constant_override("outline_size", 3)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	@warning_ignore("static_called_on_instance")
	var f: Font = GameManager.select_font(lbl.text, GameManager.font_zh_title, GameManager.font_tcm)
	if f: lbl.add_theme_font_override("font", f)
	ctrl.add_child(lbl)

	ctrl.gui_input.connect(_on_marker_input.bind(idx))
	ctrl.set_meta("dot", dot)
	ctrl.set_meta("label", lbl)
	return ctrl


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
	var c: MapCrosshair = MapCrosshair.new()
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
		if child is MapCrosshair:
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

	_goto_hover_tween = create_tween().set_parallel(true)
	_goto_hover_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_goto_hover_tween.tween_property(_goto_sweep, "scale:x", 1.0 if hovered else 0.0, 0.25)
	_goto_hover_tween.tween_property(_goto_wrap, "position:x", _goto_rest_x - 50.0 if hovered else _goto_rest_x + 10.0, 0.25)
	_goto_hover_tween.tween_property(_goto_wrap, "modulate:a", 1.0 if hovered else GOTO_REST_ALPHA, 0.25)

	_goto_label.add_theme_color_override("font_color", Color.BLACK if hovered else Color.WHITE)
	@warning_ignore("incompatible_ternary")
	_goto_wrap.add_theme_stylebox_override("panel", _goto_border_style if not hovered else StyleBoxEmpty.new())


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
		t_goto.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
		t_goto.tween_property(_goto_wrap, "position:x", _goto_rest_x, 0.5)
		t_goto.tween_property(_goto_wrap, "modulate:a", GOTO_REST_ALPHA, 0.5)


# ===================================================================
# 选中 / 取消选中
# ===================================================================

func _select_location(idx: int, show_info: bool = false) -> void:
	if idx < 0 or idx >= LOCATIONS.size() or _marker_nodes.size() == 0:
		return

	var same_location: bool = (idx == _selected_idx)

	if _selected_idx >= 0 and not same_location and _selected_idx < _marker_nodes.size():
		var prev: Control = _marker_nodes[_selected_idx]
		var prev_dot: ColorRect = prev.get_meta("dot")
		prev_dot.color = Color.BLACK

	# 从无到有的选中：等准心四臂交会后再推镜头；连续切换直接跟手
	_selection_delay = 0.0 if _crosshair != null else CROSS_ZOOM_DELAY

	_selected_idx = idx
	_last_selected_idx = idx

	# 标点及时变红 —— 选中即生效，不等准心
	var marker: Control = _marker_nodes[idx]
	var dot: ColorRect = marker.get_meta("dot")
	dot.color = Color.RED

	_sync_crosshair(idx)

	if show_info and not (same_location and _panel_shown):
		_update_info_panel(idx)
	_scroll_to_location(idx)


func _deselect_location() -> void:
	if _selected_idx < 0:
		return
	var marker: Control = _marker_nodes[_selected_idx]
	var dot: ColorRect = marker.get_meta("dot")
	dot.color = Color.BLACK
	_selected_idx = -1
	# 准心倒放：四臂缩回屏幕四边
	_retire_crosshair()
	# 面板若还在滑出就立即收尾，别让"面板滑出"和"镜头缩回"两段动画叠在一起
	_finish_panel_hide()
	_hide_info_panel()
	# 缩小回初始缩放比例 — 同时平移保持在边界内。
	# 以容器真实缩放为基准：推镜动画可能还在延迟中，_zoom_level 已指向目标值。
	var old_zoom: float = maxf(_map_container.scale.x, 0.0001)
	_zoom_level = _zoom_min
	var clip_size: Vector2 = _map_clip.size
	if clip_size.x > 0 and clip_size.y > 0:
		# 保持当前画面中心不变，但遵守新的边界约束
		var world_center: Vector2 = (clip_size / 2.0 - _map_container.position) / old_zoom
		var target: Vector2 = clip_size / 2.0 - world_center * _zoom_min
		target = _guard_pan_bounds(target)
		_animate_pan(target)
	_animate_zoom(old_zoom, _zoom_min)


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

	# 不判断 visible —— 面板正在滑出时也要能原路滑回来
	_show_info_panel()


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
	var vp_w: float = get_viewport().get_visible_rect().size.x

	if was_hidden:
		_info_panel.offset_left = vp_w
		_info_panel.offset_right = vp_w
		_info_panel.modulate.a = 1.0
	_info_panel.visible = true

	_panel_tween = create_tween().set_parallel(true)
	_panel_tween.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
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

	# BorderBot — 分割线横向展开
	_info_border.scale = Vector2(0.0, 1.0)
	var t_border := create_tween()
	t_border.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	t_border.tween_property(_info_border, "scale:x", 1.0, 0.5).set_delay(0.12)
	_info_intro_tweens.append(t_border)

	# NameLabel — 右侧滑入 + 淡入
	_info_name.position.x = _info_rest_name + 50.0
	_info_name.modulate.a = 0.0
	var t_name := create_tween().set_parallel(true)
	t_name.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	t_name.tween_property(_info_name, "position:x", _info_rest_name, 0.5).set_delay(0.20)
	t_name.tween_property(_info_name, "modulate:a", 1.0, 0.5).set_delay(0.20)
	_info_intro_tweens.append(t_name)

	# DescLabel — 右侧滑入 + 淡入
	_info_desc.position.x = _info_rest_desc + 50.0
	_info_desc.modulate.a = 0.0
	var t_desc := create_tween().set_parallel(true)
	t_desc.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	t_desc.tween_property(_info_desc, "position:x", _info_rest_desc, 0.5).set_delay(0.28)
	t_desc.tween_property(_info_desc, "modulate:a", 1.0, 0.5).set_delay(0.28)
	_info_intro_tweens.append(t_desc)

	# SuggestLabel — 右侧滑入 + 淡入
	_info_suggest.position.x = _info_rest_suggest + 50.0
	_info_suggest.modulate.a = 0.0
	var t_suggest := create_tween().set_parallel(true)
	t_suggest.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	t_suggest.tween_property(_info_suggest, "position:x", _info_rest_suggest, 0.5).set_delay(0.36)
	t_suggest.tween_property(_info_suggest, "modulate:a", 1.0, 0.5).set_delay(0.36)
	_info_intro_tweens.append(t_suggest)

	# Goto 按钮 — 仅在启用时跟随入场（参照 Notebook 内容元素动画）
	if _goto_enabled:
		_goto_wrap.position.x = _goto_rest_x + STAGGER_OFFSET
		_goto_wrap.modulate.a = 0.0
		_goto_wrap.visible = true
		var t_goto := create_tween().set_parallel(true)
		t_goto.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
		t_goto.tween_property(_goto_wrap, "position:x", _goto_rest_x, 0.5).set_delay(0.44)
		t_goto.tween_property(_goto_wrap, "modulate:a", GOTO_REST_ALPHA, 0.5).set_delay(0.44)
		_info_intro_tweens.append(t_goto)


## 掐掉面板内部元素的入场动画（快速 ESC / 空格打断时防止状态累积）
func _kill_info_intro() -> void:
	for tw: Tween in _info_intro_tweens:
		if tw and tw.is_valid():
			tw.kill()
	_info_intro_tweens.clear()


func _hide_info_panel() -> void:
	# 目标态已经是"隐藏"（或面板已消失）→ 无操作，连按 ESC 不会重启动画
	if not _panel_shown:
		return
	_panel_shown = false

	# 面板向右滑出
	var vp_w: float = get_viewport().get_visible_rect().size.x

	if _panel_tween and _panel_tween.is_valid():
		_panel_tween.kill()

	_panel_tween = create_tween().set_parallel(true)
	_panel_tween.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	_panel_tween.tween_property(_info_panel, "offset_left", vp_w, PANEL_OUT_TIME)
	_panel_tween.tween_property(_info_panel, "offset_right", vp_w, PANEL_OUT_TIME)
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
	var vp_w: float = get_viewport().get_visible_rect().size.x
	_info_panel.offset_left = vp_w
	_info_panel.offset_right = vp_w
	_info_panel.z_index = 0
	_on_panel_hidden()


func _on_panel_hidden() -> void:
	_info_panel.visible = false
	_panel_shown = false
	# 重置 Goto 按钮位置，为下次入场动画做准备
	if _goto_wrap:
		if _goto_hover_tween and _goto_hover_tween.is_valid():
			_goto_hover_tween.kill()
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

func _clamp_pan() -> void:
	var clip_size: Vector2 = _map_clip.size
	var map_w: float = MAP_W * _zoom_level
	var map_h: float = MAP_H * _zoom_level
	var min_x: float = clip_size.x - map_w
	var min_y: float = clip_size.y - map_h
	_map_container.position.x = clampf(_map_container.position.x, min_x, 0.0)
	_map_container.position.y = clampf(_map_container.position.y, min_y, 0.0)


func _center_on_location(idx: int, zoom: float = KEYBOARD_ZOOM, delay: float = -1.0, duration: float = 0.35) -> void:
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
	var old_zoom: float = _zoom_level
	var new_zoom: float = clampf(zoom, _zoom_min, ZOOM_MAX)
	_zoom_level = new_zoom

	# 尽量居中该地点，但不超出图片边界
	var target: Vector2 = clip_size / 2.0 - loc_center * _zoom_level
	# 若信息面板已显示（含正在滑入），向左偏移以补偿面板占用的右侧空间，
	# 确保地点出现在可视区域的中心而非被面板遮挡。
	if _panel_shown:
		target.x -= PANEL_SHIFT
	target = _guard_pan_bounds(target)
	_animate_pan(target, wait, duration)
	_animate_zoom(old_zoom, new_zoom, wait, duration)


## 确保平移目标不超出地图边界 — "尽量居中，遇边界则贴边"。
func _guard_pan_bounds(target: Vector2) -> Vector2:
	var clip_size: Vector2 = _map_clip.size
	var map_w: float = MAP_W * _zoom_level
	var map_h: float = MAP_H * _zoom_level
	var clamped: Vector2 = target
	clamped.x = clampf(clamped.x, clip_size.x - map_w, 0.0)
	clamped.y = clampf(clamped.y, clip_size.y - map_h, 0.0)
	return clamped


func _scroll_to_location(idx: int) -> void:
	var data: Dictionary = LOCATIONS[idx]
	var loc_center: Vector2 = Vector2(data.x, data.y)
	var screen_pos: Vector2 = loc_center * _zoom_level + _map_container.position

	var clip_size: Vector2 = _map_clip.size
	if clip_size.x <= 0 or clip_size.y <= 0:
		return

	var margin: float = SCROLL_MARGIN
	var target: Vector2 = _map_container.position
	var needs_scroll: bool = false

	# 信息面板显示时右侧可视区域收窄，增大右边界触发距离
	var right_limit: float = clip_size.x - (margin + PANEL_SHIFT if _panel_shown else margin)
	if screen_pos.x < margin:
		target.x = _map_container.position.x + margin - screen_pos.x
		needs_scroll = true
	elif screen_pos.x > right_limit:
		target.x = _map_container.position.x + right_limit - screen_pos.x
		needs_scroll = true

	if screen_pos.y < margin:
		target.y = _map_container.position.y + margin - screen_pos.y
		needs_scroll = true
	elif screen_pos.y > clip_size.y - margin:
		target.y = _map_container.position.y + (clip_size.y - margin) - screen_pos.y
		needs_scroll = true

	if needs_scroll:
		# 确保滚动目标也不会超出边界
		var map_w: float = MAP_W * _zoom_level
		var map_h: float = MAP_H * _zoom_level
		target.x = clampf(target.x, clip_size.x - map_w, 0.0)
		target.y = clampf(target.y, clip_size.y - map_h, 0.0)
		_animate_pan(target)


func _animate_pan(target: Vector2, delay: float = 0.0, duration: float = 0.35) -> void:
	if _pan_tween and _pan_tween.is_valid():
		_pan_tween.kill()
	_pan_tween = create_tween()
	_pan_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if delay > 0.0:
		_pan_tween.tween_interval(delay)
	_pan_tween.tween_property(_map_container, "position", target, duration)

@warning_ignore("unused_parameter")
func _animate_zoom(from_zoom: float, to_zoom: float, delay: float = 0.0, duration: float = 0.35) -> void:
	if _zoom_tween and _zoom_tween.is_valid():
		_zoom_tween.kill()
	_zoom_tween = create_tween()
	_zoom_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if delay > 0.0:
		_zoom_tween.tween_interval(delay)
	_zoom_tween.tween_property(_map_container, "scale", Vector2(to_zoom, to_zoom), duration)


# ===================================================================
# 平移 / 缩放
# ===================================================================

func _on_map_clip_input(event: InputEvent) -> void:
	if _disabled: return

	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				# 手动拖拽优先 — 打断入场推镜头 / 自动滚动
				_stop_map_motion()
				_dragging = false
				_drag_start = mb.position
				_pan_start = _map_container.position
			else:
				if not _dragging and _selected_idx >= 0:
					_deselect_location()
				_dragging = false

	elif event is InputEventMouseMotion:
		var mm: InputEventMouseMotion = event as InputEventMouseMotion
		if mm.button_mask & 1:
			var delta: Vector2 = mm.position - _drag_start
			if not _dragging and delta.length() > DRAG_THRESHOLD:
				_dragging = true
			if _dragging:
				_map_container.position = _pan_start + delta
			_clamp_pan()


# ===================================================================
# 标记点击
# ===================================================================

func _on_marker_input(event: InputEvent, idx: int) -> void:
	if _disabled: return
	# Forward drag motion to map panning
	if event is InputEventMouseMotion and (event as InputEventMouseMotion).button_mask & 1:
		_on_map_clip_input(event)
		return
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
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
	# 以容器实际缩放为基准：推镜动画可能仍在延迟中，而 _zoom_level 已指向目标值
	var old_zoom: float = maxf(_map_container.scale.x, 0.0001)
	var new_zoom: float = clampf(old_zoom * factor, _zoom_min, ZOOM_MAX)
	if is_equal_approx(new_zoom, old_zoom):
		return
	# 滚轮优先 — 打断入场推镜头 / 自动滚动，避免延迟 tween 事后抢回缩放
	_stop_map_motion()

	var map_anchor: Vector2 = (anchor_screen - _map_container.position) / old_zoom
	_zoom_level = new_zoom
	_map_container.position = anchor_screen - map_anchor * _zoom_level
	_clamp_pan()
	_map_container.scale = Vector2(_zoom_level, _zoom_level)


## 打断进行中的平移 / 缩放动画（用户手动拖拽或滚轮时调用）。
func _stop_map_motion() -> void:
	if _pan_tween and _pan_tween.is_valid():
		_pan_tween.kill()
	_pan_tween = null
	if _zoom_tween and _zoom_tween.is_valid():
		_zoom_tween.kill()
	_zoom_tween = null


# ===================================================================
# SceneManager 生命周期
# ===================================================================

func _on_enter() -> void:
	_disabled = false
	# 上次离开时残留的平移 / 面板 / 准星状态先清空，保证每次进入都是入场动画
	_stop_map_motion()
	_reset_info_panel_now()
	_clear_crosshairs()

	# 等待一帧使布局生效，然后计算初始缩放：地图至少填满裁剪区 → 无黑边
	await get_tree().process_frame
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

	# 首次选中 = 当前地点（存档作用域 current_location）；
	# 未设置 / 不在地图上 → 默认北门（LOCATIONS 第一项）。选择浏览不回写。
	var loc_idx: int = MapData.get_index(GameManager.get_current_location())
	var idx: int = loc_idx if loc_idx >= 0 else 0
	_select_location(idx, false)
	# 四臂从屏幕四边交于当前地点（如第一章开场的校门），交会后再推近镜头
	_center_on_location(idx, ENTRY_ZOOM, ENTRY_ZOOM_DELAY, ENTRY_PAN_TIME)

func _on_exit() -> void:
	_disabled = true
	_menu_active = false
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
