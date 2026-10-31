## SettingsRow : Control
## 设置行基类 — 统一「行外壳」（扫白 + 焦点竖条 + 标题 + 值控件挂载点 + 底部细线）
## 与焦点/入场动画；子类只负责右侧值控件与自身颜色。
## 交互语言照 scenes/ui/OptionRow.gd：单个 tween 先杀再建，场景侧对每一行调用
## apply_focus_state 即得全量刷新语义（防半程 kill 残留中间态）；颜色走 theme_override
## 的 tween_property（被 kill 后下一次从当前值继续，快速划过无跳变）。
## 视觉取「低调版」（右栏只是设置，白色强调留给左栏 SettingsCategoryItem）：
## 焦点行白色带 0.12 + 左侧 2px 白竖条 + 标题/数值提亮，未聚焦行内容压到 0.5。
## 入场：prepare_intro 摆初始态（透明），play_intro 在 await 一帧后滑入。
## 位移做在行内部的 ContentRow 上 —— 行自己是 VBoxContainer 的子节点，
## position.x 会被容器排序覆写回 0（滑入因此偶发整段不出现）。
## 纯组件：不直接读写设置，只发信号，由 SettingsScene 编排。
class_name SettingsRow
extends Control

# ── Signals ────────────────────────────────────────────

## 鼠标进入（携带 row_id，场景侧据此切换焦点）。
signal hovered(row_id: String)

# ── Constants ──────────────────────────────────────────

const ROW_HEIGHT: float = 56.0
const SIDE_PADDING: float = 32.0
const FOCUS_DURATION: float = 0.22
const SWEEP_ALPHA: float = 0.15
const UNFOCUSED_CONTENT_ALPHA: float = 0.5
const TICK_WIDTH: float = 2.0
const LABEL_FONT_SIZE_ZH: int = 20
const LABEL_FONT_SIZE_EN: int = 22
const LABEL_REST_COLOR: Color = Color(1, 1, 1, 0.9)
const LABEL_FOCUS_COLOR: Color = Color(1, 1, 1, 1)
const DIVIDER_COLOR: Color = Color(1, 1, 1, 0.08)
const INTRO_START_X: float = 24.0
const INTRO_FADE_DURATION: float = 0.26
const INTRO_SLIDE_DURATION: float = 0.34

# ── State ──────────────────────────────────────────────

## 行标识符（对应 _categories[].rows[].id）。
var row_id: String = ""

var _sweep: ColorRect = null
var _tick: ColorRect = null
var _content_row: HBoxContainer = null
var _primary_label: Label = null
var _divider: ColorRect = null
var _focus_tween: Tween = null
var _intro_tween: Tween = null


# ── 构建（子类在 _build() 开头调用一次）────────────────

## 建行外壳：白带（左缘 pivot）+ 焦点竖条 + 内容 HBox（左右内边距）+ 标题 + 底部细线。
## 子类随后向 _content_row 追加弹间隔与自己的值控件。
func _build_shell() -> void:
	custom_minimum_size = Vector2(0, ROW_HEIGHT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	# 白色扫入（聚焦时 scale.x 0→1，pivot 左缘；只做浅带，不反色）
	_sweep = ColorRect.new()
	_sweep.name = "Sweep"
	_sweep.color = Color(1, 1, 1, 0)
	_sweep.set_anchors_preset(Control.PRESET_FULL_RECT)
	_sweep.pivot_offset = Vector2.ZERO
	_sweep.scale = Vector2(0, 1)
	_sweep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_sweep)

	# 焦点竖条（行左缘 2px，聚焦时浮现）
	_tick = ColorRect.new()
	_tick.name = "FocusTick"
	_tick.color = Color.WHITE
	_tick.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	_tick.offset_right = TICK_WIDTH
	_tick.modulate = Color(1, 1, 1, 0)
	_tick.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_tick)

	# 内容行（垂直方向撑满，标签自身垂直居中；左右留 SIDE_PADDING）
	_content_row = HBoxContainer.new()
	_content_row.name = "ContentRow"
	_content_row.set_anchors_preset(Control.PRESET_FULL_RECT)
	_content_row.offset_left = SIDE_PADDING
	_content_row.offset_right = -SIDE_PADDING
	_content_row.alignment = BoxContainer.ALIGNMENT_BEGIN
	_content_row.modulate = Color(1, 1, 1, UNFOCUSED_CONTENT_ALPHA)
	_content_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_content_row)

	_primary_label = Label.new()
	_primary_label.name = "PrimaryLabel"
	_primary_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_primary_label.add_theme_color_override("font_color", LABEL_REST_COLOR)
	_primary_label.add_theme_font_size_override("font_size", LABEL_FONT_SIZE_ZH)
	_primary_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content_row.add_child(_primary_label)

	# 底部细线（锚点定宽，别再用 size=(0,1) —— 那种写法永远不会画出来）
	_divider = ColorRect.new()
	_divider.name = "Divider"
	_divider.color = DIVIDER_COLOR
	_divider.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_divider.offset_top = -1.0
	_divider.offset_left = SIDE_PADDING
	_divider.offset_right = -SIDE_PADDING
	_divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_divider)

	mouse_entered.connect(_emit_hovered)


## 行标题（中英文同一入口：按内容选字体与字号）。
func _set_primary_text(p_text: String) -> void:
	_primary_label.text = p_text
	@warning_ignore("static_called_on_instance")
	var font: Font = GameManager.select_font(p_text, GameManager.font_zh_body, GameManager.font_tcm)
	if font:
		_primary_label.add_theme_font_override("font", font)
	@warning_ignore("static_called_on_instance")
	var font_size: int = GameManager.select_font_size(p_text, LABEL_FONT_SIZE_ZH, LABEL_FONT_SIZE_EN)
	_primary_label.add_theme_font_size_override("font_size", font_size)


## 追加吃掉剩余宽度的弹性间隔（把值控件推到右缘）。
func _add_expanding_spacer() -> void:
	var spacer := Control.new()
	spacer.name = "Spacer"
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content_row.add_child(spacer)


## 追加固定宽度间隔（值控件之间的呼吸）。
func _add_fixed_spacer(p_width: float, p_name: String) -> void:
	var spacer := Control.new()
	spacer.name = p_name
	spacer.custom_minimum_size = Vector2(p_width, 0)
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content_row.add_child(spacer)


# ── Public API ─────────────────────────────────────────

## 焦点状态：先杀本行上一轮 tween 再重建（无半程残留）。全部属性走同一条 parallel
## tween —— 白带展开、竖条显隐、内容调暗、标题色一起收敛；重入时从当前值继续。
## 三元先预计算（实参内联三元在 GDScript 里有解析陷阱，见 OptionRow 同款注释）。
func apply_focus_state(p_focused: bool) -> void:
	if _focus_tween and _focus_tween.is_valid():
		_focus_tween.kill()
	_focus_tween = create_tween().set_parallel(true)
	_focus_tween.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)

	var target_scale: float = 1.0 if p_focused else 0.0
	var target_sweep_alpha: float = SWEEP_ALPHA if p_focused else 0.0
	var target_tick_alpha: float = 1.0 if p_focused else 0.0
	var target_content_alpha: float = 1.0 if p_focused else UNFOCUSED_CONTENT_ALPHA
	var target_label_color: Color = LABEL_FOCUS_COLOR if p_focused else LABEL_REST_COLOR

	_focus_tween.tween_property(_sweep, "scale:x", target_scale, FOCUS_DURATION)
	_focus_tween.tween_property(_sweep, "color:a", target_sweep_alpha, FOCUS_DURATION)
	_focus_tween.tween_property(_tick, "modulate:a", target_tick_alpha, FOCUS_DURATION)
	_focus_tween.tween_property(_content_row, "modulate:a", target_content_alpha, FOCUS_DURATION)
	_focus_tween.tween_property(_primary_label, "theme_override_colors/font_color",
		target_label_color, FOCUS_DURATION)
	_tween_focus_colors(_focus_tween, p_focused)


## 入场前初始态：复位视觉并全透明。位置由 VBox 决定，play_intro 时再摆。
func prepare_intro() -> void:
	kill_animations()
	_reset_shell_visuals()
	modulate.a = 0.0


## 入场错峰单行动画：内容右移 INTRO_START_X → 0 + 淡入。
## 位移做在行内部的 ContentRow 上 —— 行本身是 VBoxContainer 的子节点，
## `position.x` 随时会被容器排序覆写回 0，那正是"滑入有时整段不出现"的原因。
func play_intro(p_delay: float) -> Tween:
	if _intro_tween and _intro_tween.is_valid():
		_intro_tween.kill()
	modulate.a = 0.0
	_content_row.offset_left = SIDE_PADDING + INTRO_START_X
	_content_row.offset_right = -SIDE_PADDING + INTRO_START_X
	_intro_tween = create_tween().set_parallel(true)
	_intro_tween.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	_intro_tween.tween_property(self, "modulate:a", 1.0, INTRO_FADE_DURATION).set_delay(p_delay)
	_intro_tween.tween_property(_content_row, "offset_left", SIDE_PADDING, INTRO_SLIDE_DURATION) \
			.set_delay(p_delay)
	_intro_tween.tween_property(_content_row, "offset_right", -SIDE_PADDING, INTRO_SLIDE_DURATION) \
			.set_delay(p_delay)
	return _intro_tween


## 瞬时复位视觉状态（场景重进/切分类前）—— 消除被 kill 的 tween 残留中间值。
func reset_visual_state() -> void:
	kill_animations()
	_reset_shell_visuals()
	modulate.a = 1.0
	position.x = 0.0


## 终止本行全部动画（场景退出/切分类时调用）。
func kill_animations() -> void:
	if _focus_tween and _focus_tween.is_valid():
		_focus_tween.kill()
	_focus_tween = null
	if _intro_tween and _intro_tween.is_valid():
		_intro_tween.kill()
	_intro_tween = null


## 语言 / 区域设置切换时调用。子类覆盖以更新显示文本。
@warning_ignore("unused_parameter")
func refresh_locale(data: Dictionary) -> void:
	pass


## 设置值变更后调用（display_text 为预先算好的显示文本，滑块行忽略它自读数值）。
@warning_ignore("unused_parameter")
func refresh_value(settings: AppSettings, display_text: String) -> void:
	pass


## 键盘左/右键步进。子类覆盖。
@warning_ignore("unused_parameter")
func step_value(delta: float) -> void:
	pass


## 行被移除/场景退出前的收尾钩子（滑块行在此把未提交的值落盘）。默认无。
func flush_pending() -> void:
	pass


# ── 子类钩子 ───────────────────────────────────────────

## 把值控件的颜色渐变挂到 p_tween（已 set_parallel(true)）。默认无。
@warning_ignore("unused_parameter")
func _tween_focus_colors(p_tween: Tween, p_focused: bool) -> void:
	pass


## 把值控件颜色瞬时复位到未聚焦态（入场/重进前调用，杜绝中间色残留）。
func _reset_value_colors() -> void:
	pass


# ── 内部 ───────────────────────────────────────────────

## 外壳（白带/竖条/内容透明度/标题色）瞬时复位到未聚焦态。不碰 modulate.a。
func _reset_shell_visuals() -> void:
	if _sweep:
		_sweep.scale.x = 0.0
		_sweep.color.a = 0.0
	if _tick:
		_tick.modulate.a = 0.0
	if _content_row:
		_content_row.modulate.a = UNFOCUSED_CONTENT_ALPHA
		_content_row.offset_left = SIDE_PADDING
		_content_row.offset_right = -SIDE_PADDING
	if _primary_label:
		_primary_label.add_theme_color_override("font_color", LABEL_REST_COLOR)
	_reset_value_colors()


func _emit_hovered() -> void:
	hovered.emit(row_id)
