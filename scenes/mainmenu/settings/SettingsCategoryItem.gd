## SettingsCategoryItem : Control
## 左栏分类项 — OptionRow 语言的两行菜单项：白扫 + 文字反黑 + 内容右移 + 未选中调暗。
## 与 OptionRow 的差异（左栏只有 320 宽）：
##   · 文字右对齐（贴内容栏分隔线），EN/中文两行堆叠（一行放不下「GAMEPLAY 游戏」）；
##   · 位移取 +16 向右（向内容栏靠，不会像 OptionRow 那样退出面板）；
##   · 调暗值 0.45（设置页字号小，比 OptionRow 的 0.35 更容易读）。
## 交互：hover 只提亮，点击才切分类（避免鼠标扫过左栏时误切）；只有当前分类是白底黑字。
## 纯组件：不碰 GameManager，只发 activated；字体由 setup 注入。
class_name SettingsCategoryItem
extends Control

# ── Signals ────────────────────────────────────────────

## 点击（已过滤按键与按下沿）。
signal activated(index: int)

# ── Layout ─────────────────────────────────────────────

const ROW_HEIGHT: float = 80.0
const LEFT_PADDING: float = 28.0
const RIGHT_PADDING: float = 44.0
const EN_ZH_GAP: int = 2
const EN_FONT_SIZE: int = 38
const ZH_FONT_SIZE: int = 22
const FOCUS_SHIFT: float = 16.0

# ── Motion / Colors ────────────────────────────────────

const FOCUS_DURATION: float = 0.22
const UNFOCUSED_ALPHA: float = 0.45
const HOVER_ALPHA: float = 0.72
const EN_REST_COLOR: Color = Color(1, 1, 1, 0.88)
const EN_FOCUS_COLOR: Color = Color(0, 0, 0, 1)
const ZH_REST_COLOR: Color = Color(1, 1, 1, 0.45)
const ZH_FOCUS_COLOR: Color = Color(0, 0, 0, 0.55)

# ── Intro ──────────────────────────────────────────────

const INTRO_START_X: float = 24.0
const INTRO_FADE_DURATION: float = 0.3
const INTRO_SLIDE_DURATION: float = 0.4

# ── State ──────────────────────────────────────────────

var _index: int = 0
var _active: bool = false
var _hovered: bool = false

var _sweep: ColorRect = null
var _content: VBoxContainer = null
var _en_label: Label = null
var _zh_label: Label = null
var _state_tween: Tween = null
var _intro_tween: Tween = null
## 内容横向偏移的两个分量（内边距之外）：焦点位移 / 入场位移。
## 各自用补间驱动一个标量再合成 —— 两条动画不会抢同一对 offset，
## 也不碰容器管理的 position.x（VBox 排序会覆写，入场滑入会因此整段消失）。
var _focus_shift: float = 0.0
var _intro_offset: float = 0.0


# ── Public API ─────────────────────────────────────────

## 构建一项（每项只调一次；重复调用需先清空子节点）。
## p_show_zh=false 时只显示英文（EN 语言），两行容器仍保持垂直居中。
func setup(p_index: int, p_en: String, p_zh: String, p_en_font: Font, p_zh_font: Font, p_show_zh: bool = true) -> void:
	_index = p_index
	name = "Category_" + str(p_index)
	custom_minimum_size = Vector2(0, ROW_HEIGHT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	# 白扫（铺满整项，pivot 左缘；活动项整行变白）
	_sweep = ColorRect.new()
	_sweep.name = "Sweep"
	_sweep.color = Color(1, 1, 1, 0)
	_sweep.set_anchors_preset(Control.PRESET_FULL_RECT)
	_sweep.pivot_offset = Vector2.ZERO
	_sweep.scale = Vector2(0, 1)
	_sweep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_sweep)

	# 内容（两行右对齐）。位移不要 tween position —— 布局尚未完成时 position 会在
	# 零宽父节点上重算 offset，把内边距整个冲掉（文字溢出白带）。这里只 tween
	# offset_left / offset_right 的绝对值，它们与父节点尺寸无关，永远安全。
	_content = VBoxContainer.new()
	_content.name = "Content"
	_content.set_anchors_preset(Control.PRESET_FULL_RECT)
	_content.offset_left = LEFT_PADDING
	_content.offset_right = -RIGHT_PADDING
	_content.alignment = BoxContainer.ALIGNMENT_CENTER
	_content.add_theme_constant_override("separation", EN_ZH_GAP)
	_content.modulate = Color(1, 1, 1, UNFOCUSED_ALPHA)
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_content)

	_en_label = _make_label("EnLabel", p_en, p_en_font, EN_FONT_SIZE, EN_REST_COLOR)
	_content.add_child(_en_label)

	_zh_label = _make_label("ZhLabel", p_zh, p_zh_font, ZH_FONT_SIZE, ZH_REST_COLOR)
	_zh_label.visible = p_show_zh
	_content.add_child(_zh_label)

	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	gui_input.connect(_on_gui_input)


## 活动态（当前分类）：白扫铺满 + 文字反黑 + 内容右移；非活动项按 hover 决定调暗程度。
func set_active(p_active: bool) -> void:
	_active = p_active
	_apply_state()


## 语言切换：更新两行文本与中文行可见性（节点复用，不重建）。
func refresh_locale(p_en: String, p_zh: String, p_show_zh: bool) -> void:
	_en_label.text = p_en
	_zh_label.text = p_zh
	_zh_label.visible = p_show_zh


## 瞬时复位（场景重进/重贴状态前）—— 消除被 kill 的 tween 残留中间值。
func reset_visual_state() -> void:
	kill_animations()
	modulate.a = 1.0
	_sweep.scale.x = 0.0
	_sweep.color.a = 0.0
	_content.modulate.a = UNFOCUSED_ALPHA
	_focus_shift = 0.0
	_intro_offset = 0.0
	_apply_content_x()
	_en_label.add_theme_color_override("font_color", EN_REST_COLOR)
	_zh_label.add_theme_color_override("font_color", ZH_REST_COLOR)


## 终止本项全部动画（场景退出时调用）。
func kill_animations() -> void:
	if _state_tween and _state_tween.is_valid():
		_state_tween.kill()
	_state_tween = null
	if _intro_tween and _intro_tween.is_valid():
		_intro_tween.kill()
	_intro_tween = null


## 入场错峰（右移 INTRO_START_X → 0 + 淡入）。
## 位移走 _intro_offset（与焦点位移合成），不再写 position.x。
func play_intro(p_delay: float) -> Tween:
	if _intro_tween and _intro_tween.is_valid():
		_intro_tween.kill()
	modulate.a = 0.0
	_intro_offset = INTRO_START_X
	_apply_content_x()
	_intro_tween = create_tween().set_parallel(true)
	_intro_tween.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	_intro_tween.tween_property(self, "modulate:a", 1.0, INTRO_FADE_DURATION).set_delay(p_delay)
	_intro_tween.tween_method(_set_intro_offset, INTRO_START_X, 0.0, INTRO_SLIDE_DURATION) \
			.set_delay(p_delay)
	return _intro_tween


func _set_intro_offset(p_value: float) -> void:
	_intro_offset = p_value
	_apply_content_x()


func _set_focus_shift(p_value: float) -> void:
	_focus_shift = p_value
	_apply_content_x()


## 内容横向位置 = 内边距 + 焦点位移 + 入场位移（三者独立合成，谁也不覆写谁）。
func _apply_content_x() -> void:
	if _content == null:
		return
	var x: float = _focus_shift + _intro_offset
	_content.offset_left = LEFT_PADDING + x
	_content.offset_right = -RIGHT_PADDING + x


# ── 内部 ───────────────────────────────────────────────

## 状态收敛：活动（白扫 + 反黑 + 右移）> 悬停提亮 > 静止调暗。
## 单一 parallel tween，先 kill 再建；重入从当前值继续（快速划过不跳变）。
func _apply_state() -> void:
	if _state_tween and _state_tween.is_valid():
		_state_tween.kill()

	var shift: float = FOCUS_SHIFT if _active else 0.0
	var rest_alpha: float = HOVER_ALPHA if _hovered else UNFOCUSED_ALPHA
	var target_sweep_scale: float = 1.0 if _active else 0.0
	var target_sweep_alpha: float = 1.0 if _active else 0.0
	var target_content_alpha: float = 1.0 if _active else rest_alpha
	var target_en_color: Color = EN_FOCUS_COLOR if _active else EN_REST_COLOR
	var target_zh_color: Color = ZH_FOCUS_COLOR if _active else ZH_REST_COLOR

	_state_tween = create_tween().set_parallel(true)
	_state_tween.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	_state_tween.tween_property(_sweep, "scale:x", target_sweep_scale, FOCUS_DURATION)
	_state_tween.tween_property(_sweep, "color:a", target_sweep_alpha, FOCUS_DURATION)
	_state_tween.tween_property(_content, "modulate:a", target_content_alpha, FOCUS_DURATION)
	_state_tween.tween_method(_set_focus_shift, _focus_shift, shift, FOCUS_DURATION)
	_state_tween.tween_property(_en_label, "theme_override_colors/font_color",
		target_en_color, FOCUS_DURATION)
	_state_tween.tween_property(_zh_label, "theme_override_colors/font_color",
		target_zh_color, FOCUS_DURATION)


func _make_label(p_name: String, p_text: String, p_font: Font, p_font_size: int, p_color: Color) -> Label:
	var label: Label = Label.new()
	label.name = p_name
	label.text = p_text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.clip_text = true
	label.add_theme_font_size_override("font_size", p_font_size)
	label.add_theme_color_override("font_color", p_color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if p_font:
		label.add_theme_font_override("font", p_font)
	return label


func _on_mouse_entered() -> void:
	_hovered = true
	if not _active:
		_apply_state()


func _on_mouse_exited() -> void:
	_hovered = false
	if not _active:
		_apply_state()


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		activated.emit(_index)

