## Map : Control
## 学校地图页面。全部 UI 节点在代码中构建。
##   鼠标拖拽 → 平移 / 滚轮 → 缩放 / WASD → 切换地点
extends Control

signal back_requested()

# ---------------------------------------------------------------------------
# 地点数据
# ---------------------------------------------------------------------------
const LOCATIONS: Array[Dictionary] = [
	{"name": "科技楼",       "description": "学校的行政楼。",                          "x": 679,  "y": 363},
	{"name": "逸天楼",       "description": "高一的教学楼。我的教室在这里。",            "x": 574,  "y": 559},
	{"name": "哲贵楼",       "description": "高一的教学楼。",                          "x": 570,  "y": 464},
	{"name": "老校区楼",     "description": "似乎已经作废的地方。",                     "x": 866,  "y": 256},
	{"name": "博雅楼",       "description": "高二的教学楼。",                          "x": 485,  "y": 600},
	{"name": "图书馆",       "description": "学校图书馆。应该能在这看到什么。",          "x": 917,  "y": 691},
	{"name": "食堂",         "description": "学校食堂。挺不便宜的。",                   "x": 860,  "y": 653},
	{"name": "桃园",         "description": "高一部分的寝室。",                        "x": 866,  "y": 359},
	{"name": "李园",         "description": "高二的寝室楼。",                          "x": 714,  "y": 597},
	{"name": "高三校区",     "description": "学校的高三学区。",                        "x": 1053, "y": 188},
	{"name": "操场",         "description": "学校的操场。",                            "x": 824,  "y": 463},
	{"name": "篮球场",       "description": "学校的篮球场。",                          "x": 794,  "y": 559},
	{"name": "乒乓球场",     "description": "乒乓球场，就在操场旁边。",                  "x": 920,  "y": 559},
	{"name": "兰园",         "description": "很大的女生寝室。",                        "x": 725,  "y": 672},
	{"name": "小卖部",       "description": "应该能在这买点东西。",                     "x": 817,  "y": 638},
	{"name": "后山",         "description": "后山公园，现在还正在建设。",                "x": 1174, "y": 678},
	{"name": "体育馆",       "description": "似乎没什么用的体育馆。",                   "x": 1085, "y": 713},
	{"name": "北门",         "description": "大家经常会走的大门。",                     "x": 609,  "y": 396},
	{"name": "南门",         "description": "临近二环路的大门，交通比较方便。",          "x": 964,  "y": 778},
	{"name": "高三校区门",   "description": "高三校区的专用大门。",                     "x": 872,  "y": 167},
]

const MAP_W: float = 1672.0
const MAP_H: float = 941.0
const ZOOM_MIN: float = 0.3
const ZOOM_MAX: float = 3.0
const ZOOM_STEP: float = 1.12
const KEYBOARD_ZOOM: float = 2.0
const DOT_SIZE: float = 14.0
const LABEL_OFFSET_X: float = 16.0
const LABEL_OFFSET_Y: float = -5.0
const DRAG_THRESHOLD: float = 4.0
const SCROLL_MARGIN: float = 100.0

# ---------------------------------------------------------------------------
# 状态
# ---------------------------------------------------------------------------
var _disabled: bool = false
var _menu_active: bool = false
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
var _map_x_before_panel: float = 0.0  # 面板弹出前的地图 X，用于恢复

# ---------------------------------------------------------------------------
# 字体
# ---------------------------------------------------------------------------
var _font_tcm: Font = null
var _font_zh_title: Font = null
var _font_zh_body: Font = null
var _font_en_body: Font = null

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
var _back_bar: BackBar = null


# ===================================================================
# 生命周期
# ===================================================================

func _ready() -> void:
	_font_tcm = load(GameManager.FONT_TCM)
	_font_zh_title = load(GameManager.FONT_ZH_TITLE)
	_font_zh_body = load(GameManager.FONT_ZH_BODY)
	_font_en_body = load(GameManager.FONT_EN_BODY)

	# 字幕标签 — 文本和可见性在运行时确定
	_subtitle_label.text = tr("校园地图")
	if GameManager.is_locale("en"):
		_subtitle_label.visible = false

	# 应用字体到场景中的静态标签
	if _font_tcm:
		_title_label.add_theme_font_override("font", _font_tcm)
		_info_name.add_theme_font_override("font", _font_tcm)
	if _font_zh_title:
		_subtitle_label.add_theme_font_override("font", _font_zh_title)
	if _font_zh_body:
		_info_desc.add_theme_font_override("font", _font_zh_body)

	_build_markers()
	_build_back_bar()
	AudioManager.set_menu_mode(true)





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
	var f: Font = GameManager.select_font(lbl.text, _font_zh_title, _font_tcm)
	if f: lbl.add_theme_font_override("font", f)
	ctrl.add_child(lbl)

	ctrl.gui_input.connect(_on_marker_input.bind(idx))
	ctrl.set_meta("dot", dot)
	ctrl.set_meta("label", lbl)
	return ctrl



# ===================================================================
# 底部返回栏
# ===================================================================

func _build_back_bar() -> void:
	_back_bar = BackBar.new("校园地图")
	_back_bar.pressed.connect(_on_back_pressed)
	add_child(_back_bar)


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

	_selected_idx = idx
	_last_selected_idx = idx

	var marker: Control = _marker_nodes[idx]
	var dot: ColorRect = marker.get_meta("dot")
	dot.color = Color.RED

	if show_info and not (same_location and _info_panel.visible):
		_update_info_panel(idx)
	_scroll_to_location(idx)


func _deselect_location() -> void:
	if _selected_idx < 0:
		return
	var marker: Control = _marker_nodes[_selected_idx]
	var dot: ColorRect = marker.get_meta("dot")
	dot.color = Color.BLACK
	_selected_idx = -1
	_hide_info_panel()
	# 缩小回初始缩放比例 — 同时平移保持在边界内
	var old_zoom: float = _zoom_level
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
	var nf: Font = GameManager.select_font(_info_name.text, _font_zh_title, _font_tcm)
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
	var df: Font = GameManager.select_font(_info_desc.text, _font_zh_body, _font_en_body)
	if df: _info_desc.add_theme_font_override("font", df)
	_info_desc.add_theme_color_override("font_color", Color(1, 1, 1, 0.5))

	if not _info_panel.visible:
		_show_info_panel()


func _show_info_panel() -> void:
	# 提升到最上层 — 覆盖地图标记和标题
	_info_panel.z_index = 10

	# 已经显示中 → 只更新内容，不重播动画
	if _info_panel.visible:
		return

	# 面板从右侧滑入，地图同时略向右移
	var vp_w: float = get_viewport().get_visible_rect().size.x
	const PANEL_SHIFT: float = 80.0

	# 记录地图原始位置，用于退出时精确恢复
	_map_x_before_panel = _map_container.position.x

	_info_panel.offset_left = vp_w
	_info_panel.offset_right = vp_w
	_info_panel.modulate.a = 1.0
	_info_panel.visible = true

	if _panel_tween and _panel_tween.is_valid():
		_panel_tween.kill()

	var map_x: float = _map_x_before_panel - PANEL_SHIFT
	_panel_tween = create_tween().set_parallel(true)
	_panel_tween.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	_panel_tween.tween_property(_info_panel, "offset_left", 0.0, 0.35)
	_panel_tween.tween_property(_info_panel, "offset_right", 0.0, 0.35)
	_panel_tween.tween_property(_map_container, "position:x", map_x, 0.35)


func _hide_info_panel() -> void:
	# 面板向右滑出，地图恢复到面板弹出前的位置
	var vp_w: float = get_viewport().get_visible_rect().size.x

	if _panel_tween and _panel_tween.is_valid():
		_panel_tween.kill()

	_panel_tween = create_tween().set_parallel(true)
	_panel_tween.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	_panel_tween.tween_property(_info_panel, "offset_left", vp_w, 0.3)
	_panel_tween.tween_property(_info_panel, "offset_right", vp_w, 0.3)
	_panel_tween.tween_property(_map_container, "position:x", _map_x_before_panel, 0.3)
	_panel_tween.chain().tween_callback(_on_panel_hidden)

	# 降回默认层级，避免遮挡其他 UI
	_info_panel.z_index = 0


func _on_panel_hidden() -> void:
	_info_panel.visible = false



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


func _center_on_location(idx: int) -> void:
	var data: Dictionary = LOCATIONS[idx]
	var loc_center: Vector2 = Vector2(data.x, data.y)
	var clip_size: Vector2 = _map_clip.size
	if clip_size.x <= 0 or clip_size.y <= 0:
		return

	# 更新缩放并计算居中位置（用目标缩放来算边界）
	var old_zoom: float = _zoom_level
	_zoom_level = KEYBOARD_ZOOM

	# 尽量居中该地点，但不超出图片边界
	var target: Vector2 = clip_size / 2.0 - loc_center * _zoom_level
	target = _guard_pan_bounds(target)
	_animate_pan(target)
	_animate_zoom(old_zoom, KEYBOARD_ZOOM)


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

	if screen_pos.x < margin:
		target.x = _map_container.position.x + margin - screen_pos.x
		needs_scroll = true
	elif screen_pos.x > clip_size.x - margin:
		target.x = _map_container.position.x + (clip_size.x - margin) - screen_pos.x
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


func _animate_pan(target: Vector2) -> void:
	if _pan_tween and _pan_tween.is_valid():
		_pan_tween.kill()
	_pan_tween = create_tween()
	_pan_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_pan_tween.tween_property(_map_container, "position", target, 0.35)


@warning_ignore("unused_parameter")
func _animate_zoom(from_zoom: float, to_zoom: float) -> void:
	if _zoom_tween and _zoom_tween.is_valid():
		_zoom_tween.kill()
	_zoom_tween = create_tween()
	_zoom_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_zoom_tween.tween_property(_map_container, "scale", Vector2(to_zoom, to_zoom), 0.35)


# ===================================================================
# 平移 / 缩放
# ===================================================================

func _on_map_clip_input(event: InputEvent) -> void:
	if _disabled: return

	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
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
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_play_click()
			if _selected_idx == idx:
				_deselect_location()
			else:
				_select_location(idx, true)


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

	if not event.is_pressed():
		return

	# Enter / Space → 弹出当前选中地点的详情框
	if event.is_action_pressed("ui_accept"):
		if _selected_idx >= 0:
			_update_info_panel(_selected_idx)
			_play_click()
		get_viewport().set_input_as_handled()
		return

	# ESC — 两步：先关信息面板，再取消选中，最后返回
	if event.is_action_pressed("ui_cancel"):
		if _selected_idx >= 0:
			if _info_panel.visible:
				_hide_info_panel()
			else:
				_deselect_location()
		else:
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
			var show_info: bool = _info_panel.visible
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
	var old_zoom: float = _zoom_level
	var new_zoom: float = clampf(_zoom_level * factor, _zoom_min, ZOOM_MAX)
	if is_equal_approx(new_zoom, old_zoom):
		return

	var map_anchor: Vector2 = (anchor_screen - _map_container.position) / old_zoom
	_zoom_level = new_zoom
	_map_container.position = anchor_screen - map_anchor * _zoom_level
	_clamp_pan()
	_map_container.scale = Vector2(_zoom_level, _zoom_level)


# ===================================================================
# SceneManager 生命周期
# ===================================================================

func _on_enter() -> void:
	_disabled = false

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

	_select_location(0, false)

func _on_exit() -> void:
	_disabled = true
	_menu_active = false
	AudioManager.set_menu_mode(false)


# ===================================================================
# 辅助
# ===================================================================

func _on_back_pressed() -> void:
	if _disabled: return
	_play_click()
	back_requested.emit()


func _play_click() -> void:
	AudioManager.play_click()


func set_disabled(val: bool) -> void:
	_disabled = val
