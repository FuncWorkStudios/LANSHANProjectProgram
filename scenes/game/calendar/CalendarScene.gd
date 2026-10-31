## CalendarScene : Control
## 游戏内日历系统 — 2022年8月至11月战术日程面板。
## 静态 UI 节点在 CalendarScene.tscn 中；动态内容（日期格、字体、动画）在代码构建。
extends Control

signal back_requested()

const MONTHS_EN: Array[String] = ["", "JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]
const MONTH_MIN: int = 8
const MONTH_MAX: int = 11
const YEAR: int = 2022
const CELL_COUNT: int = 42

# 格子尺寸由代码决定（格子是 _create_cell 里 new 出来的），其余矩形都在 tscn 里调。
# 注意：DayGrid 的 h_separation / WeekdayRow 的 separation 必须和「7×CELL_W + 6×间距」
# 一致（当前 7×108 + 6×4 = 780），否则星期行和网格会错位。
const CELL_W: float = 108.0
const CELL_H: float = 64.0

# 月份标题的「码表」滚动：裁剪框宽度 / 滚动时长（对齐 TabMenu 的白框大标题）
const MONTH_CLIP_W: float = 400.0
const MONTH_ROLL_TIME: float = 0.28

# 月份行的排版：月名 64 / 日期 24
const MONTH_FONT_SIZE: int = 64
const DATE_FONT_SIZE: int = 24
## 日期压在大字右半段的层叠排版：日期起点 = 月名实际字宽 × 该比例（0 = 不重叠）
const DATE_OVERLAP: float = 0.45

# 日号 / 事件点颜色
const C_TEXT: Color = Color(1, 1, 1, 1)
const C_SUN: Color = Color(1, 0.102, 0.102, 1)
const C_ADJ: Color = Color(1, 1, 1, 0.35)
const C_OUT: Color = Color(1, 1, 1, 0.18)
const C_SELECTED: Color = Color(0, 0, 0, 1)
const C_DOT: Color = Color(1, 0.102, 0.102, 0.85)
const HOVER_ALPHA: float = 0.08

# 「今天」的 1pt 细框：未选中时白框，落在白带上时改黑框（否则白框在白底上看不见）
const TODAY_FRAME_COLOR: Color = Color(1, 1, 1, 0.9)
const TODAY_FRAME_ON_SELECTED: Color = Color(0, 0, 0, 0.65)
const TODAY_FRAME_WIDTH: float = 1.0

# ---------------------------------------------------------------------------
# 状态
# ---------------------------------------------------------------------------
var _month: int = 9
var _selected: String = ""
## 存档里的「当前日期」（game_month / game_day），没上下文时为空 —— 只用来画今天那格细框。
var _today_date: String = ""
var _focus_idx: int = -1
var _cell_nodes_a: Array[Control] = []
var _cell_nodes_b: Array[Control] = []
var _current_cells: Array[Control] = []
var _using_grid_a: bool = true
var _is_animating: bool = false
@warning_ignore("unused_private_class_variable")
var _info_panel_shown: bool = false
var _panel_tween: Tween = null
var _grid_tween: Tween = null
var _label_tween: Tween = null
## 月份标题的裁剪层 + 承载「月名 + 日期」两个标签的 plate（码表滚动用）
var _month_clip: Control = null
var _month_plate: Control = null
## 右侧日程卡文字的淡入 tween（切日期时轻轻出现，避免整块文字瞬间跳变）。
var _detail_tween: Tween = null
var _is_first_enter: bool = true
var _can_go_back: bool = true

# ---------------------------------------------------------------------------
# @onready 节点引用
# ---------------------------------------------------------------------------
@onready var _month_header: Control = $MonthHeader
@onready var _month_lbl: Label = $MonthHeader/MonthLabel
@onready var _date_lbl: Label = $MonthHeader/DateLabel
@onready var _nav_prev: Button = $NavPrev
@onready var _nav_next: Button = $NavNext
@onready var _today_btn: Button = $TodayBtn
@warning_ignore("unused_private_class_variable")
@onready var _grid_area: Control = $GridArea
@onready var _weekday_row: HBoxContainer = $GridArea/WeekdayRow
@onready var _grid_a: GridContainer = $GridArea/DayGrid
@onready var _info_panel: Control = $InfoPanel
@onready var _info_name: Label = $InfoPanel/NameLabel
@onready var _info_desc: Label = $InfoPanel/DescLabel
@onready var _info_border: ColorRect = $InfoPanel/BorderBot
var _grid_clip: Control = null
var _grid_b: GridContainer = null
var _back_bar := BackBar.new()


# ===================================================================
# 生命周期
# ===================================================================

func _ready() -> void:
	_init_state()
	_setup_month_roll()
	_setup_grid_clip()
	_apply_fonts()
	_connect_signals()
	_build_static_runtime_ui()
	_refresh_view()
	_setup_backbar()


func _init_state() -> void:
	_selected = "2022-09-15"


func _setup_grid_clip() -> void:
	var parent := _grid_a.get_parent()

	_grid_clip = Control.new()
	_grid_clip.name = "GridClip"
	_grid_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(_grid_clip)

	_grid_a.reparent(_grid_clip)
	_grid_a.name = "DayGridA"

	_grid_b = GridContainer.new()
	_grid_b.name = "DayGridB"
	_grid_b.columns = 7
	_grid_b.position = Vector2(0, _grid_a.position.y)
	_grid_b.add_theme_constant_override("h_separation", 4)
	_grid_b.add_theme_constant_override("v_separation", 4)
	_grid_b.visible = false
	_grid_clip.add_child(_grid_b)


func _connect_signals() -> void:
	_nav_prev.pressed.connect(_on_nav.bind(-1))
	_nav_next.pressed.connect(_on_nav.bind(1))
	_today_btn.pressed.connect(_on_today_pressed)


func _build_static_runtime_ui() -> void:
	_build_weekday_row()
	_create_cell_pool(_grid_a, _cell_nodes_a)
	_create_cell_pool(_grid_b, _cell_nodes_b)
	_current_cells = _cell_nodes_a


func _refresh_view() -> void:
	_layout_header()
	_refresh_all_cells()
	_find_focus_for_selected()
	_refresh_detail()


func _setup_backbar() -> void:
	_back_bar = BackBar.attach(self)


func _on_enter() -> void:
	_reset_month_roll()
	_apply_global_date()
	if _is_first_enter:
		_is_first_enter = false
		_animate_first_entrance()
	else:
		_update_focus_two_cells(-1, _focus_idx)
		_show_info_panel()


## 从存档作用域读取 game_month / game_day，聚焦到指定日期。
func _apply_global_date() -> void:
	var ctx: ScriptContext = GameManager.script_context
	if not ctx:
		return
	var m: int = int(ctx.get_var("game_month"))
	var d: int = int(ctx.get_var("game_day"))
	if m < MONTH_MIN or m > MONTH_MAX or d < 1 or d > 31:
		return
	_month = m
	_selected = "%d-%02d-%02d" % [YEAR, m, d]
	_today_date = _selected
	_refresh_view()


func _on_exit() -> void:
	_hide_info_panel()


## 控制场景是否可通过 ESC / BackBar 返回上一级。
func set_can_go_back(can: bool) -> void:
	_can_go_back = can
	_back_bar.visible = can


func set_disabled(_v: bool) -> void:
	pass


# ===================================================================
# 字体
# ===================================================================

func _apply_fonts() -> void:
	if GameManager.font_tcm:
		_month_lbl.add_theme_font_override("font", GameManager.font_tcm)
		_date_lbl.add_theme_font_override("font", GameManager.font_tcm)
		_nav_prev.add_theme_font_override("font", GameManager.font_tcm)
		_nav_next.add_theme_font_override("font", GameManager.font_tcm)
		_today_btn.add_theme_font_override("font", GameManager.font_tcm)
		_info_name.add_theme_font_override("font", GameManager.font_tcm)

		if GameManager.font_en_body:
			_info_desc.add_theme_font_override("font", GameManager.font_en_body)



# ===================================================================
# 顶栏 — 月份标签 + 导航
# ===================================================================

func _on_nav(dir: int) -> void:
	if _is_animating:
		return
	AudioManager.play_click()
	var m := _month + dir
	if m < MONTH_MIN or m > MONTH_MAX:
		return
	_month = m
	_animate_month_label(dir)
	_animate_month_switch(dir)


## 回到存档里的“当前日期”（game_month / game_day）。
## 跨月时走一次和箭头完全相同的翻月动画（网格滑动 + 标题滑入），落点再用白带选中，
## 不再是「啪」一下整页跳过去；同月时只移动选中。翻月动画途中忽略。
func _on_today_pressed() -> void:
	if _is_animating:
		return
	if _today_date.is_empty():
		return
	AudioManager.play_click()

	var parts := _today_date.split("-")
	var target_month: int = parts[1].to_int()

	if target_month == _month:
		var data: Array = _gen_grid()
		for i: int in data.size():
			if data[i].date == _today_date:
				_select_by_idx(i)
				return
		return

	var dir: int = 1 if target_month > _month else -1
	_selected = _today_date
	_month = target_month
	_animate_month_label(dir)
	_animate_month_switch(dir)


## 月份标题的裁剪层：把「月名 + 日期」搬进 clip 里的 plate，clip 只露一行高度。
## 参照 TabMenu._setup_branding_clip —— 码表滚动靠它遮掉框外部分。
func _setup_month_roll() -> void:
	_month_clip = Control.new()
	_month_clip.name = "MonthClip"
	_month_clip.clip_contents = true
	_month_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_month_clip.position = Vector2.ZERO
	_month_clip.size = Vector2(MONTH_CLIP_W, 84.0)
	_month_header.add_child(_month_clip)

	_month_plate = Control.new()
	_month_plate.name = "MonthPlate"
	_month_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_month_plate.size = _month_clip.size
	_month_clip.add_child(_month_plate)

	# 手动搬进 plate：不依赖 reparent 的全局坐标推断，位置确定可复现
	var m_pos: Vector2 = _month_lbl.position
	var d_pos: Vector2 = _date_lbl.position
	_month_header.remove_child(_month_lbl)
	_month_header.remove_child(_date_lbl)
	# 日期先加 → 画在大字下面（层叠排版的「压字」效果）
	_month_plate.add_child(_date_lbl)
	_month_plate.add_child(_month_lbl)
	_month_lbl.position = m_pos
	_date_lbl.position = d_pos


## 复位码表（入场 / 中途退出后）：清掉副本、当前 plate 回到底部。
func _reset_month_roll() -> void:
	if _label_tween and _label_tween.is_valid():
		_label_tween.kill()
	_month_header.modulate.a = 1.0
	if _month_clip == null or _month_plate == null:
		return
	for c: Node in _month_clip.get_children():
		if c != _month_plate:
			c.queue_free()
	_month_plate.position.y = 0.0


## 月份行：AUG（64）+ 日期（24，压在大字右半段、基线对齐、画在月名之下）。
## 箭头 / TODAY 的位置由 CalendarScene.tscn 决定（代码不再覆盖，改 tscn 立刻生效）。
func _layout_header() -> void:
	_layout_plate(_month_lbl, _date_lbl)
	# 裁剪框高度直接按字体行高算：翻月时旧字要完整滚出、新字从下沿滚入
	var line_h: float = 80.0
	if GameManager.font_tcm:
		line_h = GameManager.font_tcm.get_height(MONTH_FONT_SIZE)
	if _month_clip:
		_month_clip.size = Vector2(MONTH_CLIP_W, line_h + 4.0)
	if _month_plate:
		_month_plate.size = _month_clip.size


## 把一对「月名 / 日期」标签摆到当前月份。
## 日期贴在大字的基线上、起点压到月名宽度的 DATE_OVERLAP 处（层叠排版，日期在月名之下）。
func _layout_plate(p_month: Label, p_date: Label) -> void:
	p_month.text = MONTHS_EN[_month]
	p_date.text = "%d.%02d" % [YEAR, _month]
	if GameManager.font_tcm:
		p_month.add_theme_font_override("font", GameManager.font_tcm)
		p_date.add_theme_font_override("font", GameManager.font_tcm)
	# 字号也在这里落实：副本刚 duplicate 出来还没进树时，不依赖 Label 自身缓存的尺寸
	p_month.add_theme_font_size_override("font_size", MONTH_FONT_SIZE)
	p_date.add_theme_font_size_override("font_size", DATE_FONT_SIZE)
	p_date.position = Vector2(roundf(_month_text_width() * DATE_OVERLAP), _date_baseline_offset())


## 月名的实际字宽：直接从字体量（Label 的 get_minimum_size 在离树副本上不可靠）。
func _month_text_width() -> float:
	if GameManager.font_tcm:
		return GameManager.font_tcm.get_string_size(
				MONTHS_EN[_month], HORIZONTAL_ALIGNMENT_LEFT, -1, MONTH_FONT_SIZE).x
	return 120.0


## 24px 日期与 64px 月名的基线对齐偏移。
func _date_baseline_offset() -> float:
	if not GameManager.font_tcm:
		return 0.0
	return GameManager.font_tcm.get_ascent(MONTH_FONT_SIZE) \
			- GameManager.font_tcm.get_ascent(DATE_FONT_SIZE)


## 翻月：月名 + 日期整块做「码表」式上下滚动 —— 旧字滚出裁剪框，新字从另一侧滚进来。
## dir > 0（往后翻）向上滚，dir < 0 向下滚，和 TabMenu 的白框大标题一致。
func _animate_month_label(dir: int) -> void:
	if _month_clip == null or _month_plate == null:
		_layout_header()
		return
	if _label_tween and _label_tween.is_valid():
		_label_tween.kill()
	# 上一轮可能还没滚完：清掉副本，当前 plate 归位
	for c: Node in _month_clip.get_children():
		if c != _month_plate:
			c.queue_free()
	_month_plate.position.y = 0.0

	var dist: float = _month_clip.size.y * (1.0 if dir > 0 else -1.0)
	var outgoing: Control = _month_plate
	var incoming: Control = _month_plate.duplicate() as Control
	var p_month: Label = incoming.get_node("MonthLabel") as Label
	var p_date: Label = incoming.get_node("DateLabel") as Label
	_layout_plate(p_month, p_date)
	incoming.position = Vector2(0.0, dist)
	_month_clip.add_child(incoming)
	_month_plate = incoming
	_month_lbl = p_month
	_date_lbl = p_date

	_label_tween = create_tween().set_parallel(true)
	_label_tween.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	_label_tween.tween_property(outgoing, "position:y", -dist, MONTH_ROLL_TIME)
	_label_tween.tween_property(incoming, "position:y", 0.0, MONTH_ROLL_TIME)
	_label_tween.set_parallel(false)
	_label_tween.tween_callback(outgoing.queue_free)


# ===================================================================
# 星期行
# ===================================================================

func _build_weekday_row() -> void:
	const WEEKDAYS: Array[String] = ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"]

	for i: int in 7:
		var sun: bool = i == 0

		# 只留文字：不再给星期做底色块（旧版 SUN 暗红块 + 其余灰块像表格补丁）
		var c := Control.new()
		c.custom_minimum_size = Vector2(CELL_W, 24)
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_weekday_row.add_child(c)

		var lbl := Label.new()
		lbl.text = WEEKDAYS[i]
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.set_anchors_preset(PRESET_FULL_RECT)
		lbl.add_theme_font_size_override("font_size", 16)
		lbl.add_theme_color_override("font_color",
			Color(1, 0.102, 0.102, 0.8) if sun else Color(1, 1, 1, 0.45))
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if GameManager.font_tcm:
			lbl.add_theme_font_override("font", GameManager.font_tcm)
		c.add_child(lbl)


# ===================================================================
# Cell 池 — 42 格复用，两个 Grid 各一份
# ===================================================================

func _create_cell_pool(grid: GridContainer, into: Array[Control]) -> void:
	for _i: int in CELL_COUNT:
		var cell := _create_cell()
		grid.add_child(cell)
		into.append(cell)


## 单格：白带（选中）+ 悬停底 + 日号 + 事件点，全部铺在格子左下 12/16 的固定网格上。
## 不再有单元格底色和 9px 小日期 —— 旧版的 0.02/0.031/0.039 三档底只在部分行出现，
## 看起来像补丁；小日期与日号信息重复。
func _create_cell() -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(CELL_W, CELL_H)
	c.mouse_filter = Control.MOUSE_FILTER_STOP
	c.gui_input.connect(_on_cell_click.bind(c))
	c.mouse_entered.connect(_on_cell_hover.bind(c, true))
	c.mouse_exited.connect(_on_cell_hover.bind(c, false))

	# 选中白带 —— 必须在文字图层之下（旧版加在 content 之后，白色压在日号上）
	var sweep := ColorRect.new()
	sweep.name = "Sweep"
	sweep.color = Color(1, 1, 1, 0)
	sweep.set_anchors_preset(PRESET_FULL_RECT)
	sweep.pivot_offset = Vector2.ZERO
	sweep.scale = Vector2(0, 1)
	sweep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(sweep)

	# 悬停底（比选中更淡，仅提示可点）
	var hover := ColorRect.new()
	hover.name = "Hover"
	hover.color = Color(1, 1, 1, 0)
	hover.set_anchors_preset(PRESET_FULL_RECT)
	hover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(hover)

	# 「今天」的 1pt 细框 —— 叠在白带之上（选中时改黑框，白框在白底上会消失）
	var frame := Control.new()
	frame.name = "TodayFrame"
	frame.set_anchors_preset(PRESET_FULL_RECT)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.visible = false
	frame.draw.connect(_draw_today_frame.bind(frame))
	c.add_child(frame)

	var dn := Label.new()
	dn.name = "Day"
	dn.position = Vector2(14, 16)
	dn.add_theme_font_size_override("font_size", 26)
	dn.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if GameManager.font_tcm:
		dn.add_theme_font_override("font", GameManager.font_tcm)
	c.add_child(dn)

	# 事件日标记：格子右上角 5×5 红方块（选中时转黑）
	var dot := ColorRect.new()
	dot.name = "Dot"
	dot.color = C_DOT
	dot.size = Vector2(5, 5)
	dot.position = Vector2(CELL_W - 17.0, 18.0)
	dot.visible = false
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(dot)

	c.set_meta("sweep", sweep)
	c.set_meta("hover", hover)
	return c


# ===================================================================
# Cell 数据更新 — 含字体颜色（选中/sweep 动画不覆盖）
# ===================================================================

## 单格状态 → 颜色。层级只有三档：范围内本月 / 范围内非本月 / 范围外，
## 不再用 modulate 压暗（旧版的 alpha 叠加和格子底色互相打架）。
func _apply_cell_data(cell: Control, cd: Dictionary) -> void:
	var out: bool = not _is_valid(cd.date)
	var evt: bool = cd.entry.get("event", false)
	var cur: bool = cd.cur
	var sun: bool = cd.sun

	_kill_cell_tween(cell)
	if cell.has_meta("hover_tween"):
		var ht: Tween = cell.get_meta("hover_tween")
		if ht and ht.is_valid():
			ht.kill()
	var sweep: ColorRect = cell.get_meta("sweep")
	if sweep:
		sweep.scale.x = 0.0
		sweep.color.a = 0.0
	var hover: ColorRect = cell.get_meta("hover")
	if hover:
		hover.color.a = 0.0

	var day_color: Color = C_TEXT
	if out:
		day_color = C_OUT
	elif not cur:
		day_color = C_ADJ
	elif sun:
		day_color = C_SUN

	var day: Label = cell.get_node_or_null("Day") as Label
	if day:
		day.text = "%02d" % int(cd.day)
		day.add_theme_color_override("font_color", day_color)

	var dot: ColorRect = cell.get_node_or_null("Dot") as ColorRect
	if dot:
		dot.visible = evt and not out
		dot.color = C_DOT

	# 「今天」细框：只有存档当前日期那一格显示，颜色随选中状态切换
	var today: bool = not _today_date.is_empty() and str(cd.date) == _today_date
	var frame: Control = cell.get_node_or_null("TodayFrame") as Control
	if frame:
		frame.visible = today
		frame.set_meta("frame_color", TODAY_FRAME_COLOR)
		frame.queue_redraw()
	cell.set_meta("today", today)

	cell.modulate.a = 1.0
	cell.visible = true
	cell.set_meta("date", cd.date)
	cell.set_meta("out", out)
	cell.set_meta("sun", sun)
	cell.set_meta("cur", cur)
	cell.set_meta("day_color", day_color)
	cell.set_meta("focused", false)


func _hide_cell(cell: Control) -> void:
	cell.visible = false


## 「今天」细框：在格子边界内画 1pt 矩形（+.5 对齐，缩放后仍是细线）。
func _draw_today_frame(frame: Control) -> void:
	if frame.size.x <= 1.0 or frame.size.y <= 1.0:
		return
	var col: Color = frame.get_meta("frame_color", TODAY_FRAME_COLOR)
	var half: float = TODAY_FRAME_WIDTH * 0.5
	var rect := Rect2(half, half, frame.size.x - TODAY_FRAME_WIDTH, frame.size.y - TODAY_FRAME_WIDTH)
	frame.draw_rect(rect, col, false, TODAY_FRAME_WIDTH)


## 今天那格细框的配色：选中（白带）时换黑框，未选中回到白框 —— 否则白框会糊在白带上。
func _set_today_frame_dark(cell: Control, selected: bool) -> void:
	if not bool(cell.get_meta("today", false)):
		return
	var frame: Control = cell.get_node_or_null("TodayFrame") as Control
	if not frame:
		return
	var col: Color = TODAY_FRAME_ON_SELECTED if selected else TODAY_FRAME_COLOR
	frame.set_meta("frame_color", col)
	frame.queue_redraw()


func _refresh_all_cells() -> void:
	var data: Array = _gen_grid()
	for i: int in CELL_COUNT:
		if i < data.size():
			_apply_cell_data(_current_cells[i], data[i])
		else:
			_hide_cell(_current_cells[i])


# ===================================================================
# 焦点白带 — 选中整格反色；悬停只提亮不选中
# ===================================================================

func _update_focus_two_cells(old_idx: int, new_idx: int) -> void:
	if old_idx == new_idx:
		return
	if old_idx >= 0 and old_idx < CELL_COUNT:
		_animate_cell_deselect(_current_cells[old_idx])
	if new_idx >= 0 and new_idx < CELL_COUNT:
		_animate_cell_select(_current_cells[new_idx])


## 选中：整格白带自左扫入 + 日号/事件点转黑（与设置页、主菜单的焦点行同一套语言）。
func _animate_cell_select(cell: Control) -> void:
	if not cell.visible:
		return

	_kill_cell_tween(cell)
	if cell.has_meta("hover_tween"):
		var ht: Tween = cell.get_meta("hover_tween")
		if ht and ht.is_valid():
			ht.kill()
	var sweep: ColorRect = cell.get_meta("sweep")
	var hover: ColorRect = cell.get_meta("hover")
	sweep.scale.x = 0.0
	sweep.color.a = 1.0
	_set_today_frame_dark(cell, true)

	var tw := create_tween().set_parallel(true)
	tw.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	tw.tween_property(sweep, "scale:x", 1.0, 0.18)
	if hover:
		tw.tween_property(hover, "color:a", 0.0, 0.12)
	var day: Label = cell.get_node_or_null("Day") as Label
	if day:
		tw.tween_property(day, "theme_override_colors/font_color", C_SELECTED, 0.14)
	var dot: ColorRect = cell.get_node_or_null("Dot") as ColorRect
	if dot and dot.visible:
		tw.tween_property(dot, "color", C_SELECTED, 0.14)
	cell.set_meta("sweep_tween", tw)
	cell.set_meta("focused", true)


## 取消选中：白带淡出，日号回到该格的基础色（周日红 / 非本月 0.35 / 范围外 0.18）。
func _animate_cell_deselect(cell: Control) -> void:
	if not cell.visible:
		return

	_kill_cell_tween(cell)
	var sweep: ColorRect = cell.get_meta("sweep")
	var tw := create_tween().set_parallel(true)
	tw.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	tw.tween_property(sweep, "color:a", 0.0, 0.16)
	_set_today_frame_dark(cell, false)
	var day: Label = cell.get_node_or_null("Day") as Label
	if day:
		tw.tween_property(day, "theme_override_colors/font_color",
			cell.get_meta("day_color", C_TEXT), 0.16)
	var dot: ColorRect = cell.get_node_or_null("Dot") as ColorRect
	if dot:
		tw.tween_property(dot, "color", C_DOT, 0.16)
	cell.set_meta("sweep_tween", tw)
	cell.set_meta("focused", false)


## 悬停只提亮、不选中 —— 日历里 hover 即选中会让鼠标划过时疯狂切日期。
func _on_cell_hover(cell: Control, entered: bool) -> void:
	if not cell.visible:
		return
	if bool(cell.get_meta("out", true)) or bool(cell.get_meta("focused", false)):
		return
	var hover: ColorRect = cell.get_meta("hover")
	if not hover:
		return
	if cell.has_meta("hover_tween"):
		var old: Tween = cell.get_meta("hover_tween")
		if old and old.is_valid():
			old.kill()
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	var target: float = HOVER_ALPHA if entered else 0.0
	tw.tween_property(hover, "color:a", target, 0.14)
	cell.set_meta("hover_tween", tw)


func _kill_cell_tween(cell: Control) -> void:
	if not cell.has_meta("sweep_tween"):
		return
	var old: Tween = cell.get_meta("sweep_tween")
	if old and old.is_valid():
		old.kill()



func _find_focus_for_selected() -> void:
	var data: Array = _gen_grid()
	var old: int = _focus_idx
	_focus_idx = -1
	for i: int in data.size():
		if data[i].date == _selected:
			_focus_idx = i
			break
	_update_focus_two_cells(old, _focus_idx)


# ===================================================================
# 键盘 / 鼠标导航
# ===================================================================

## 从 from_idx 沿 (dx, dy) 方向寻找下一个有效日期。
## 返回有效索引，或 -1（无有效目标）。
func _find_valid_in_direction(from_idx: int, dx: int, dy: int) -> int:
	var data: Array = _gen_grid()
	var count: int = data.size()
	if count == 0:
		return -1
	var total_rows: int = ceili(float(count) / 7.0)
	const MAX_ITER: int = 42

	var col: int = from_idx % 7
	@warning_ignore("integer_division")
	var row: int = from_idx / 7
	col += dx
	row += dy

	for _iter: int in MAX_ITER:
		if col < 0 or col >= 7 or row < 0 or row >= total_rows:
			return -1
		var idx: int = row * 7 + col
		if idx >= count:
			return -1
		if _is_valid(data[idx].date):
			return idx
		col += dx
		row += dy

	return -1


func _navigate_focus(dx: int, dy: int) -> void:
	if _focus_idx < 0:
		# 无焦点 → 选中当前月份第一个有效日期
		var data: Array = _gen_grid()
		for i: int in data.size():
			if _is_valid(data[i].date):
				_select_by_idx(i)
				return
		return

	var target: int = _find_valid_in_direction(_focus_idx, dx, dy)
	if target >= 0:
		_select_by_idx(target)


func _select_by_idx(idx: int) -> void:
	var data: Array = _gen_grid()
	if idx < 0 or idx >= data.size():
		return
	var ds: String = data[idx].date
	if not _is_valid(ds):
		return

	# 跨月导航 → 切换到目标月份
	var parts := ds.split("-")
	var clicked_month: int = parts[1].to_int()
	if clicked_month != _month and not _is_animating:
		_selected = ds
		_on_nav(1 if clicked_month > _month else -1)
		return

	var old_focus: int = _focus_idx
	_selected = ds
	_focus_idx = idx

	_update_focus_two_cells(old_focus, _focus_idx)
	_refresh_detail()



func _on_cell_click(event: InputEvent, cell: Control) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	var ds: String = cell.get_meta("date", "")
	if ds.is_empty() or not _is_valid(ds):
		return
	var parts := ds.split("-")
	var clicked_month: int = parts[1].to_int()
	if clicked_month != _month and not _is_animating:
		_selected = ds
		_on_nav(1 if clicked_month > _month else -1)
		return
	for i: int in _current_cells.size():
		if _current_cells[i] == cell:
			AudioManager.play_click()
			_select_by_idx(i)
			break

# ===================================================================
# 输入 — ESC / 方向键 / WASD
# ===================================================================

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if _can_go_back:
			_request_back()
		get_viewport().set_input_as_handled()
		return

	if not event.is_pressed():
		return

	if event.is_action_pressed("ui_up"):
		_navigate_focus(0, -1); get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_down"):
		_navigate_focus(0, 1); get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_left"):
		_navigate_focus(-1, 0); get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_right"):
		_navigate_focus(1, 0); get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_page_up"):
		_on_nav(-1); get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_page_down"):
		_on_nav(1); get_viewport().set_input_as_handled()

	# WASD 已通过 Godot 默认 Input Map 映射到 ui_* 动作，无需单独处理


# ===================================================================
# 月份切换 — 双 Grid 滑入滑出
# ===================================================================

func _other_grid() -> GridContainer:
	return _grid_b if _using_grid_a else _grid_a


func _other_cells() -> Array[Control]:
	return _cell_nodes_b if _using_grid_a else _cell_nodes_a


func _animate_month_switch(dir: int) -> void:
	if _is_animating:
		return
	_is_animating = true

	var next_grid: GridContainer = _other_grid()
	var next_cells: Array[Control] = _other_cells()
	var cur_grid: GridContainer = _grid_a if _using_grid_a else _grid_b

	var data: Array = _gen_grid()
	for i: int in CELL_COUNT:
		if i < data.size():
			_apply_cell_data(next_cells[i], data[i])
		else:
			_hide_cell(next_cells[i])

	var slide_in_from: float = dir * 80.0
	next_grid.position.x = slide_in_from
	next_grid.modulate.a = 0.0
	next_grid.visible = true

	if _grid_tween and _grid_tween.is_valid():
		_grid_tween.kill()

	_grid_tween = create_tween().set_parallel(true)
	_grid_tween.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	_grid_tween.tween_property(cur_grid, "position:x", -slide_in_from, 0.22)
	_grid_tween.tween_property(cur_grid, "modulate:a", 0.0, 0.18)
	_grid_tween.tween_property(next_grid, "position:x", 0.0, 0.22)
	_grid_tween.tween_property(next_grid, "modulate:a", 1.0, 0.22)
	await _grid_tween.finished

	cur_grid.visible = false
	cur_grid.position.x = 0.0
	cur_grid.modulate.a = 1.0

	_using_grid_a = not _using_grid_a
	_current_cells = next_cells
	_focus_idx = -1
	_find_focus_for_selected()
	# 翻到的月份里没有原来的选中日 → 自动选该月第一个可交互日期。
	# 必须在 _is_animating 仍为 true 时做：_select_by_idx 遇到「非本月」日期会再翻一页，
	# 而新月份的前置格子里往往正是上个月的合法日期 → 会被弹回原页。
	if _focus_idx < 0:
		_select_first_valid()
	_is_animating = false


## 选中当前月份里第一个可交互日期。
## 只看 cur = true 的格子：前置/后置的相邻月份日期虽然合法，但不是本月，不能选。
func _select_first_valid() -> void:
	var data: Array = _gen_grid()
	for i: int in data.size():
		var cd: Dictionary = data[i]
		if not cd.cur:
			continue
		if _is_valid(cd.date):
			_select_by_idx(i)
			return


# ===================================================================
# 首次入场 — 按行（6 Tween）错峰淡入
# ===================================================================

func _animate_first_entrance() -> void:
	var data: Array = _gen_grid()
	for i: int in CELL_COUNT:
		if i < data.size():
			var cell := _cell_nodes_a[i]
			_apply_cell_data(cell, data[i])
			cell.set_meta("target_alpha", cell.modulate.a)
			cell.modulate.a = 0.0
		else:
			_hide_cell(_cell_nodes_a[i])

	for row: int in 6:
		var t_row := create_tween()
		for col: int in 7:
			var i: int = row * 7 + col
			if i >= CELL_COUNT or i >= data.size():
				break
			var cell := _cell_nodes_a[i]
			var target: float = cell.get_meta("target_alpha", 1.0)
			t_row.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
			t_row.tween_property(cell, "modulate:a", target, 0.15)
		t_row.tween_interval(row * 0.04)

	_find_focus_for_selected()

	var t_info := create_tween()
	t_info.tween_interval(0.10)
	t_info.tween_callback(_show_info_panel)


# ===================================================================
# 网格数据
# ===================================================================

func _gen_grid() -> Array:
	var r: Array = []
	var fd := _dow(_month, 1)
	var dim := _days_in(_month)

	if fd > 0:
		var pm := _month - 1 if _month > 1 else 12
		var pd := _days_in(pm)
		for i: int in range(fd - 1, -1, -1):
			r.append(_cell_data(pm, pd - i, false))

	for d: int in range(1, dim + 1):
		r.append(_cell_data(_month, d, true))

	var t := r.size()
	# 固定铺满 6 行（42 格）：翻月时表格高度不跳，月末多出的格子由下月日期补，
	# 超出游戏日期范围的会在 _apply_cell_data 里压到 0.18。
	var n: int = CELL_COUNT - t
	if n > 0:
		var nm := _month + 1 if _month < 12 else 1
		for d: int in range(1, n + 1):
			r.append(_cell_data(nm, d, false))
	return r


func _cell_data(m: int, d: int, cur: bool) -> Dictionary:
	var ds := _fmt(YEAR, m, d)
	return {"day": d, "month": m, "date": ds, "cur": cur, "sun": _dow(m, d) == 0,
			"entry": CalendarData.get_entry(ds)}



# ===================================================================
# InfoPanel
# ===================================================================

func _show_info_panel() -> void:
	if _detail_tween and _detail_tween.is_valid():
		_detail_tween.kill()
	var vp_w: float = get_viewport().get_visible_rect().size.x

	_info_panel.offset_left = vp_w
	_info_panel.offset_right = vp_w
	_info_panel.modulate.a = 1.0
	_info_panel.visible = true

	_info_border.scale = Vector2(0.0, 1.0)
	var name_target_x: float = _info_name.position.x
	_info_name.position.x += 50.0
	_info_name.modulate.a = 0.0
	var desc_target_x: float = _info_desc.position.x
	_info_desc.position.x += 50.0
	_info_desc.modulate.a = 0.0

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color.WHITE
	sb.shadow_size = 0
	sb.shadow_offset = Vector2(8, 6)
	sb.shadow_color = Color(1, 1, 1, 0.1)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	_info_name.add_theme_stylebox_override("normal", sb)

	if _panel_tween and _panel_tween.is_valid():
		_panel_tween.kill()

	_panel_tween = create_tween().set_parallel(true)
	_panel_tween.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	_panel_tween.tween_property(_info_panel, "offset_left", 0.0, 0.35)
	_panel_tween.tween_property(_info_panel, "offset_right", 0.0, 0.35)

	var t_border := create_tween()
	t_border.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	t_border.tween_property(_info_border, "scale:x", 1.0, 0.5).set_delay(0.12)

	var t_name := create_tween().set_parallel(true)
	t_name.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	t_name.tween_property(_info_name, "position:x", name_target_x, 0.5).set_delay(0.20)
	t_name.tween_property(_info_name, "modulate:a", 1.0, 0.5).set_delay(0.20)

	var t_desc := create_tween().set_parallel(true)
	t_desc.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	t_desc.tween_property(_info_desc, "position:x", desc_target_x, 0.5).set_delay(0.1)
	t_desc.tween_property(_info_desc, "modulate:a", 1.0, 0.5).set_delay(0.1)


func _hide_info_panel() -> void:
	if not _info_panel.visible:
		return

	var vp_w: float = get_viewport().get_visible_rect().size.x
	if _panel_tween and _panel_tween.is_valid():
		_panel_tween.kill()

	_panel_tween = create_tween().set_parallel(true)
	_panel_tween.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	_panel_tween.tween_property(_info_panel, "offset_left", vp_w, 0.3)
	_panel_tween.tween_property(_info_panel, "offset_right", vp_w, 0.3)
	_panel_tween.chain().tween_callback(_on_panel_hidden)


func _on_panel_hidden() -> void:
	_info_panel.visible = false


func _refresh_detail() -> void:
	_update_detail_text()


func _update_detail_text() -> void:
	var e := CalendarData.get_entry(_selected)
	var parts := _selected.split("-")
	var y: int = parts[0].to_int()
	var m: int = parts[1].to_int()
	var d: int = parts[2].to_int()
	var dn := ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"]

	_info_name.text = "%d %s %02d  %s" % [y, MONTHS_EN[m], d, dn[_dow(m, d)]]
	@warning_ignore("static_called_on_instance")
	if GameManager.font_tcm:
		_info_name.add_theme_font_override("font", GameManager.font_tcm)

	var things: String = str(e.get("things", "")) if not e.is_empty() else ""
	var event_text: String = "〓 EVENT 〓" if e.get("event", false) else ""

	var desc_lines: String = ""
	if not event_text.is_empty():
		desc_lines += event_text + "\n"
	desc_lines += things
	_info_desc.text = desc_lines
	_flash_detail()


## 切日期时让右侧文字轻轻浮现，避免整块内容瞬间替换。
## 日期条只淡「字色」（白底条保持不动），正文整块淡入；位置动画留给 _show_info_panel。
func _flash_detail() -> void:
	if not _info_panel.visible:
		return
	if _detail_tween and _detail_tween.is_valid():
		_detail_tween.kill()
	_info_name.add_theme_color_override("font_color", Color(0, 0, 0, 0.35))
	_info_desc.modulate.a = 0.45
	_detail_tween = create_tween().set_parallel(true)
	_detail_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_detail_tween.tween_property(_info_name, "theme_override_colors/font_color",
		Color(0, 0, 0, 1), 0.22)
	_detail_tween.tween_property(_info_desc, "modulate:a", 1.0, 0.22)


# ===================================================================
# 工具
# ===================================================================

func _is_valid(ds: String) -> bool:
	return ds >= CalendarData.MIN_DATE_STR and ds <= CalendarData.MAX_DATE_STR


func _fmt(y: int, m: int, d: int) -> String:
	return "%d-%02d-%02d" % [y, m, d]


## 星期几（0 = 周日）。基准日 2022-08-28 是周日，用 posmod 做正模 ——
## 旧版 `total % 7` 对 8 月 1 日算出 -6，导致 8 月整月错位一列、周日也不会变红。
func _dow(month: int, day: int) -> int:
	var total := 0
	for mm: int in range(8, month):
		total += _days_in(mm)
	total += day - 28
	return posmod(total, 7)


func _days_in(month: int) -> int:
	if month in [1, 3, 5, 7, 8, 10, 12]:
		return 31
	if month in [4, 6, 9, 11]:
		return 30
	return 28


# ===================================================================
# 返回
# ===================================================================

func _request_back() -> void:
	AudioManager.play_click()
	back_requested.emit()
