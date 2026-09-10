## OptionRow : Control
## 跨场景复用的选项行组件 — 统一 MainMenuList / QuitModal / TabMenu（主列表 +
## 确认对话框）/ OverwriteConfirm / ChoicesMenu 的选项行 UI/UX：
## sweep 扫白 + 行 position.x 位移 + 调暗；焦点由本行自身 tween 先杀后建，
## 调用方对全部行调用 apply_focus_state 即得全量刷新语义（防半程 kill 残留中间态）。
## 文字颜色渐变（tween_method，与扫白并行同 duration）：聚焦 EASE_IN 晚切黑 —
## 纯黑背景（确认菜单 band）上扫白盖到文本前文字仍偏浅可读；失焦 EASE_OUT 早切白。
## kill 安全：重入时新渐变从当前色继续（无跳变），外部 kill_focus_anim 收敛到
## 目标色（完成态）— 杜绝被 kill 的颜色渐变残留中间色。
## 行结构两种形态由多参数 setup 覆盖：
##   菜单行（默认）：EN 标题 + 中文副标题（42/24px）；
##   VN 选项行（反例）：单文本标签（标题传空即跳过，字号/字体/尾部间隔经参数覆写）。
## 纯组件：不触碰 GameManager/EventBus/AudioManager，字体与颜色经参数传入；
## 容器布局（VBox / 锚点 / 固定宽度）由调用方在 setup 后自行设定。
class_name OptionRow
extends Control

# ── Signals ────────────────────────────────────────────

## 鼠标进入（index 为 setup 时传入的索引）。
signal hovered(index: int)
## 鼠标左键点击（已过滤按键与按下沿）。
signal activated(index: int)

# ── Constants（菜单行默认样式，照 TabMenu 选项 / MainMenuList）──

const ROW_HEIGHT: float = 51.0
const ROW_FOCUS_X: float = -50.0
const ROW_REST_X: float = 10.0
const UNFOCUSED_MODULATE: float = 0.35
const TITLE_FONT_SIZE: int = 42
const ZH_FONT_SIZE: int = 24
const UNFOCUSED_ZH_COLOR: Color = Color(1, 1, 1, 0.5)
const FOCUSED_ZH_COLOR: Color = Color(0, 0, 0, 0.6)
const SWEEP_COLOR: Color = Color.WHITE
const FOCUS_DURATION: float = 0.25
const LEAD_SPACER_WIDTH: float = 16.0
const MID_SPACER_WIDTH: float = 12.0
const INTRO_START_X: float = 100.0
const INTRO_FADE_DURATION: float = 0.3
const INTRO_SLIDE_DURATION: float = 0.5

# ── State ──────────────────────────────────────────────

var _index: int = 0
var _sweep: ColorRect = null
var _title_label: Label = null
var _subtitle_label: Label = null
var _focus_tween: Tween = null
var _dim_tween: Tween = null
## 文字颜色渐变 tween（tween_method 逐帧覆写 theme override 色，与扫白并行）。
var _color_tween: Tween = null
## 当前文字色 — 渐变起点（每次重入从当前色继续，悬停快速切换无跳变）。
var _title_color: Color = Color.WHITE
var _subtitle_color: Color = UNFOCUSED_ZH_COLOR
## 目标文字色 — 外部 kill_focus_anim 收敛终点（完成态，杜绝中间色残留）。
var _title_target_color: Color = Color.WHITE
var _subtitle_target_color: Color = UNFOCUSED_ZH_COLOR
## 最近一次未聚焦副标题色 — reset_visual_state 复位文字色用（VN 行白 0.85 等覆写值）。
var _last_unfocused_subtitle_color: Color = UNFOCUSED_ZH_COLOR


# ── Public API ─────────────────────────────────────────

## 构建行内容（每行只调一次；重复调用需先清空子节点）：
## sweep + 内容 HBox（前导 16 + 标题 + 间隔 12 + 副标题 + 可选尾部间隔，END 靠右）。
## p_title 为空时跳过标题（VN 选项行单标签形态）。
## p_width > 0 时设定最小宽度（TabMenu/ChoicesMenu 480）；0 由容器决定。
## p_trailing_width > 0 时在末尾加间隔（VN 选项行右侧 24 内缩）。
func setup(p_index: int, p_title: String, p_subtitle: String, p_title_font: Font = null, p_subtitle_font: Font = null, p_width: float = 0.0, p_trailing_width: float = 0.0, p_title_font_size: int = TITLE_FONT_SIZE, p_subtitle_font_size: int = ZH_FONT_SIZE) -> void:
	_index = p_index
	name = "Option_" + str(p_index)
	custom_minimum_size = Vector2(p_width, ROW_HEIGHT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_entered.connect(_on_mouse_entered)
	gui_input.connect(_on_gui_input)

	# 白色扫入（聚焦时 scale.x 0→1，pivot 左缘）
	_sweep = ColorRect.new()
	_sweep.name = "Sweep"
	_sweep.color = SWEEP_COLOR
	_sweep.set_anchors_preset(Control.PRESET_FULL_RECT)
	_sweep.pivot_offset = Vector2(0, 0)
	_sweep.scale.x = 0.0
	_sweep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_sweep)

	var content_row: HBoxContainer = HBoxContainer.new()
	content_row.set_anchors_preset(Control.PRESET_FULL_RECT)
	content_row.alignment = BoxContainer.ALIGNMENT_END
	content_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(content_row)

	var lead_spacer: Control = Control.new()
	lead_spacer.custom_minimum_size = Vector2(LEAD_SPACER_WIDTH, 0)
	lead_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content_row.add_child(lead_spacer)

	if not p_title.is_empty():
		_title_label = Label.new()
		_title_label.name = "TitleLabel"
		_title_label.text = p_title
		_title_label.add_theme_font_size_override("font_size", p_title_font_size)
		_title_label.add_theme_color_override("font_color", Color.WHITE)
		_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if p_title_font:
			_title_label.add_theme_font_override("font", p_title_font)
		content_row.add_child(_title_label)

		var mid_spacer: Control = Control.new()
		mid_spacer.custom_minimum_size = Vector2(MID_SPACER_WIDTH, 0)
		mid_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content_row.add_child(mid_spacer)

	_subtitle_label = Label.new()
	_subtitle_label.name = "SubtitleLabel"
	_subtitle_label.text = p_subtitle
	_subtitle_label.add_theme_font_size_override("font_size", p_subtitle_font_size)
	_subtitle_label.add_theme_color_override("font_color", UNFOCUSED_ZH_COLOR)
	_subtitle_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if p_subtitle_font:
		_subtitle_label.add_theme_font_override("font", p_subtitle_font)
	content_row.add_child(_subtitle_label)

	if p_trailing_width > 0.0:
		var trailing_spacer: Control = Control.new()
		trailing_spacer.custom_minimum_size = Vector2(p_trailing_width, 0)
		trailing_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content_row.add_child(trailing_spacer)


## 文本刷新（重进场景复用行时不重建节点；英文模式 p_subtitle 传空）。
func refresh_text(p_title: String, p_subtitle: String) -> void:
	if _title_label:
		_title_label.text = p_title
	_subtitle_label.text = p_subtitle


## 焦点状态：先杀本行上一轮 tween 再重建（无半程残留）。位移/调暗/未聚焦色/聚焦色
## 均可覆写（VN 选项行：+30/0、不调暗、白 0.85/纯黑）。文字颜色走渐变
## （tween_method，与扫白并行同 duration，从当前色渐变到目标色）：
## 聚焦 EASE_IN 晚切黑 — 纯黑背景（确认菜单 band）上扫白盖到文本前文字仍偏浅可读，
## 扫白盖到文本左缘时文字已转深（白底可读），无隐形窗口；失焦 EASE_OUT 早切白。
func apply_focus_state(p_focused: bool, p_focus_x: float = ROW_FOCUS_X, p_rest_x: float = ROW_REST_X, p_unfocused_alpha: float = UNFOCUSED_MODULATE, p_unfocused_subtitle_color: Color = UNFOCUSED_ZH_COLOR, p_focused_subtitle_color: Color = FOCUSED_ZH_COLOR) -> void:
	_kill_focus_tweens(false)
	_last_unfocused_subtitle_color = p_unfocused_subtitle_color
	var target_x: float = p_focus_x if p_focused else p_rest_x
	var target_alpha: float = 1.0 if p_focused else p_unfocused_alpha
	var target_sweep_scale: float = 1.0 if p_focused else 0.0
	var target_title_color: Color = Color.BLACK if p_focused else Color.WHITE
	var target_subtitle_color: Color = p_focused_subtitle_color if p_focused else p_unfocused_subtitle_color
	_title_target_color = target_title_color
	_subtitle_target_color = target_subtitle_color
	_focus_tween = create_tween().set_parallel(true)
	_focus_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_focus_tween.tween_property(_sweep, "scale:x", target_sweep_scale, FOCUS_DURATION)
	_focus_tween.tween_property(self, "position:x", target_x, FOCUS_DURATION)
	_focus_tween.tween_property(self, "modulate:a", target_alpha, FOCUS_DURATION)
	# 文字颜色渐变（与扫白并行）：聚焦 EASE_IN 晚切黑、失焦 EASE_OUT 早切白
	# （三元先预计算 — 实参内联三元在 GDScript 中是解析陷阱）。
	var color_ease: Tween.EaseType = Tween.EASE_IN if p_focused else Tween.EASE_OUT
	_color_tween = create_tween().set_parallel(true)
	_color_tween.set_trans(Tween.TRANS_CUBIC).set_ease(color_ease)
	if _title_label:
		_color_tween.tween_method(_set_title_color, _title_color, target_title_color, FOCUS_DURATION)
	_color_tween.tween_method(_set_subtitle_color, _subtitle_color, target_subtitle_color, FOCUS_DURATION)


## 杀本行焦点 tween（列表关闭/出场前调用，防残留动画覆盖调暗等）；
## 颜色渐变一并收敛到目标色（完成态）— 杜绝被 kill 的颜色渐变残留中间色。
func kill_focus_anim() -> void:
	_kill_focus_tweens(true)


## 杀焦点运动/颜色 tween。p_snap_color 是否将文字色收敛到目标值：
## apply_focus_state 重入不收敛（新渐变从当前色继续，悬停快速切换无跳变）；
## 外部 kill（出场/关列表）收敛，防中间色残留。
func _kill_focus_tweens(p_snap_color: bool) -> void:
	if _focus_tween and _focus_tween.is_valid():
		_focus_tween.kill()
	_focus_tween = null
	if _color_tween and _color_tween.is_valid():
		_color_tween.kill()
	_color_tween = null
	if p_snap_color:
		_set_title_color(_title_target_color)
		_set_subtitle_color(_subtitle_target_color)


## 终止本行全部动画（焦点/调暗）。
func kill_anims() -> void:
	kill_focus_anim()
	if _dim_tween and _dim_tween.is_valid():
		_dim_tween.kill()
	_dim_tween = null


## 入场初始态（照 MainMenuList.prepare_intro）：全透明并右移屏外。
## 注意：VBox 排序在空闲时执行会覆写 position.x — 调用方 await 一帧后需重设。
func prepare_intro() -> void:
	modulate.a = 0.0
	position.x = INTRO_START_X


## 入场错峰单行动画（照 MainMenuList.play_intro_stagger）：快速淡入先于滑动完成。
## 返回本行 tween，调用方 await 最后一行以在入场结束后应用焦点。
func play_intro(p_delay: float) -> Tween:
	modulate.a = 0.0
	position.x = INTRO_START_X
	var row_tween: Tween = create_tween().set_parallel(true)
	row_tween.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	row_tween.tween_property(self, "modulate:a", 1.0, INTRO_FADE_DURATION).set_delay(p_delay)
	row_tween.tween_property(self, "position:x", ROW_REST_X, INTRO_SLIDE_DURATION).set_delay(p_delay)
	return row_tween


## 瞬时复位视觉状态 — 消除被 kill 的 tween 残留中间值（场景重进/模态隐藏后）。
## 文字色一并复位为未聚焦态：上次聚焦残留的黑色文字在纯黑背景（确认菜单）上重入会隐形。
func reset_visual_state() -> void:
	kill_focus_anim()
	position.x = 0.0
	_sweep.scale.x = 0.0
	modulate.a = 1.0
	# 文字色复位为未聚焦态并同步目标值（确认行复用重入防残留黑字隐形）。
	_title_target_color = Color.WHITE
	_subtitle_target_color = _last_unfocused_subtitle_color
	_set_title_color(Color.WHITE)
	_set_subtitle_color(_last_unfocused_subtitle_color)


## 退出模态调暗/恢复（amount=1.0 恢复）。
func set_dim(p_amount: float, p_duration: float) -> void:
	if _dim_tween and _dim_tween.is_valid():
		_dim_tween.kill()
	_dim_tween = create_tween()
	_dim_tween.tween_property(self, "modulate:a", p_amount, p_duration)


# ── 文字色（theme override 覆写；同步记录当前色作下一次渐变起点）──

func _set_title_color(p_color: Color) -> void:
	_title_color = p_color
	if _title_label:
		_title_label.add_theme_color_override("font_color", p_color)


func _set_subtitle_color(p_color: Color) -> void:
	_subtitle_color = p_color
	_subtitle_label.add_theme_color_override("font_color", p_color)


# ── Input（命名函数，无 lambda）────────────────────────

func _on_mouse_entered() -> void:
	hovered.emit(_index)


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		activated.emit(_index)
