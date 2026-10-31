## SettingsCycleRow : SettingsRow
## 循环选项设置行 — 左侧标签 + 右侧「< 值 >」步进组（值区定宽居中、箭头贴住值区，
## 整组右缘对齐行内边距）。值区 clip_text，长文案（英文 UNLIMITED 等）不会把行撑破。
## 代码构建子节点（项目惯例：BackBar 同模式）；不向外暴露内部节点，只发 stepped 信号。
class_name SettingsCycleRow
extends "res://scenes/mainmenu/settings/SettingsRow.gd"

# ── Signals ────────────────────────────────────────────

## 步进请求（direction = -1 / +1）。
signal stepped(row_id: String, direction: int)

# ── Constants ──────────────────────────────────────────

const VALUE_WIDTH: float = 150.0
const VALUE_FONT_SIZE_ZH: int = 20
const VALUE_FONT_SIZE_EN: int = 22
const CHEVRON_FONT_SIZE: int = 20
const CHEVRON_WIDTH: float = 24.0
const GROUP_GAP: float = 16.0
const VALUE_REST_COLOR: Color = Color(1, 1, 1, 0.8)
const VALUE_FOCUS_COLOR: Color = Color(1, 1, 1, 1)
const CHEVRON_REST_COLOR: Color = Color(1, 1, 1, 0.35)
const CHEVRON_FOCUS_COLOR: Color = Color(1, 1, 1, 0.8)

# ── State ──────────────────────────────────────────────

var _val_label: Label = null
var _prev_btn: Button = null
var _next_btn: Button = null


func _init() -> void:
	_build()


func _build() -> void:
	_build_shell()

	_add_expanding_spacer()
	_add_fixed_spacer(GROUP_GAP, "GapPrev")

	_prev_btn = _make_chevron_button("PrevBtn", "<", -1)
	_content_row.add_child(_prev_btn)

	_val_label = Label.new()
	_val_label.name = "ValLabel"
	_val_label.custom_minimum_size = Vector2(VALUE_WIDTH, 0)
	_val_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_val_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_val_label.clip_text = true
	_val_label.add_theme_font_size_override("font_size", VALUE_FONT_SIZE_ZH)
	_val_label.add_theme_color_override("font_color", VALUE_REST_COLOR)
	_val_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content_row.add_child(_val_label)

	_add_fixed_spacer(GROUP_GAP, "GapNext")

	_next_btn = _make_chevron_button("NextBtn", ">", 1)
	_content_row.add_child(_next_btn)


# ── Public API ─────────────────────────────────────────

func configure(p_row_id: String, p_label: String, p_display_text: String) -> void:
	row_id = p_row_id
	_set_primary_text(p_label)
	_set_display_text(p_display_text)


func refresh_locale(data: Dictionary) -> void:
	_set_primary_text(str(data["zh"]))


func refresh_value(_settings: AppSettings, p_display_text: String) -> void:
	_set_display_text(p_display_text)


func step_value(delta: float) -> void:
	stepped.emit(row_id, 1 if delta > 0.0 else -1)


# ── 内部 ───────────────────────────────────────────────

## 值文本：按内容选字体/字号；值区宽度固定，超长由 clip_text 裁切。
func _set_display_text(p_text: String) -> void:
	_val_label.text = p_text
	@warning_ignore("static_called_on_instance")
	var font: Font = GameManager.select_font(p_text, GameManager.font_zh_body, GameManager.font_tcm)
	if font:
		_val_label.add_theme_font_override("font", font)
	@warning_ignore("static_called_on_instance")
	var font_size: int = GameManager.select_font_size(p_text, VALUE_FONT_SIZE_ZH, VALUE_FONT_SIZE_EN)
	_val_label.add_theme_font_size_override("font_size", font_size)


## 箭头按钮：扁平无框，只留字形与颜色（悬停/按下都不出底色）。
func _make_chevron_button(p_name: String, p_text: String, p_dir: int) -> Button:
	var btn: Button = Button.new()
	btn.name = p_name
	btn.text = p_text
	btn.flat = true
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(CHEVRON_WIDTH, 0)
	btn.add_theme_font_size_override("font_size", CHEVRON_FONT_SIZE)
	btn.add_theme_color_override("font_color", CHEVRON_REST_COLOR)
	var empty_style: StyleBoxEmpty = StyleBoxEmpty.new()
	btn.add_theme_stylebox_override("normal", empty_style)
	btn.add_theme_stylebox_override("hover", empty_style)
	btn.add_theme_stylebox_override("pressed", empty_style)
	btn.add_theme_stylebox_override("focus", empty_style)
	btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	btn.pressed.connect(_on_step.bind(p_dir))
	return btn


func _on_step(p_dir: int) -> void:
	stepped.emit(row_id, p_dir)


func _tween_focus_colors(p_tween: Tween, p_focused: bool) -> void:
	var value_color: Color = VALUE_FOCUS_COLOR if p_focused else VALUE_REST_COLOR
	var chevron_color: Color = CHEVRON_FOCUS_COLOR if p_focused else CHEVRON_REST_COLOR
	p_tween.tween_property(_val_label, "theme_override_colors/font_color",
		value_color, FOCUS_DURATION)
	p_tween.tween_property(_prev_btn, "theme_override_colors/font_color",
		chevron_color, FOCUS_DURATION)
	p_tween.tween_property(_next_btn, "theme_override_colors/font_color",
		chevron_color, FOCUS_DURATION)


func _reset_value_colors() -> void:
	if _val_label:
		_val_label.add_theme_color_override("font_color", VALUE_REST_COLOR)
	if _prev_btn:
		_prev_btn.add_theme_color_override("font_color", CHEVRON_REST_COLOR)
	if _next_btn:
		_next_btn.add_theme_color_override("font_color", CHEVRON_REST_COLOR)
