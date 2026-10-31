## SettingsSliderRow : SettingsRow
## 滑块设置行 — 左侧标签 + 右侧轨道/填充/拇指 + 百分比读数（整组右缘对齐行内边距）。
## 轨道/拇指用 ColorRect 自绘（HSlider 本体透明，只负责鼠标拖动），焦点行整体提亮；
## 拇指不再用 24px 黑色方块 —— 浅色焦点带上会隐形。
## 拖动期间高频写值：value_changed 只进内存（GameManager.set_setting(..., false)），
## 停止调整 COMMIT_DELAY 后发一次 value_committed 落盘 —— 否则每帧写一次 settings.cfg。
class_name SettingsSliderRow
extends "res://scenes/mainmenu/settings/SettingsRow.gd"

# ── Signals ────────────────────────────────────────────

## 值变化（拖动中每帧都会发，消费方只更新内存/音量，不要落盘）。
signal value_changed(value: float, row_id: String)
## 调整结束（停手 COMMIT_DELAY 后 / 键盘步进立刻）—— 消费方在此落盘一次。
signal value_committed(value: float, row_id: String)

# ── Constants ──────────────────────────────────────────

const TRACK_WIDTH: float = 340.0
const TRACK_HEIGHT: float = 3.0
const THUMB_SIZE: float = 12.0
const TRACK_HOST_HEIGHT: float = 24.0
const PCT_WIDTH: float = 88.0
const PCT_GAP: float = 16.0
const VALUE_FONT_SIZE: int = 20
const COMMIT_DELAY: float = 0.3
const TRACK_REST_BG: Color = Color(1, 1, 1, 0.12)
const TRACK_FOCUS_BG: Color = Color(1, 1, 1, 0.24)
const TRACK_REST_FILL: Color = Color(1, 1, 1, 0.55)
const TRACK_FOCUS_FILL: Color = Color(1, 1, 1, 0.92)
const THUMB_REST_COLOR: Color = Color(1, 1, 1, 0.95)
const THUMB_FOCUS_COLOR: Color = Color(1, 1, 1, 1)
const PCT_REST_COLOR: Color = Color(1, 1, 1, 0.55)
const PCT_FOCUS_COLOR: Color = Color(1, 1, 1, 0.95)

# ── State ──────────────────────────────────────────────

var _setting_key: String = ""
var _track_bg: ColorRect = null
var _track_fill: ColorRect = null
var _thumb: ColorRect = null
var _slider: HSlider = null
var _pct_label: Label = null
var _commit_timer: Timer = null
## 有值已写进内存但还没落盘（防抖窗口内）—— flush_pending 据此决定是否立刻提交。
var _has_pending_commit: bool = false


func _init() -> void:
	_build()


func _build() -> void:
	_build_shell()

	_add_expanding_spacer()

	# 轨道宿主：定宽、高 24，垂直居中；内部三个 ColorRect + 一层透明 HSlider
	var track_host: Control = Control.new()
	track_host.name = "SliderTrack"
	track_host.custom_minimum_size = Vector2(TRACK_WIDTH, TRACK_HOST_HEIGHT)
	track_host.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	track_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content_row.add_child(track_host)

	var track_y: float = (TRACK_HOST_HEIGHT - TRACK_HEIGHT) * 0.5
	var thumb_y: float = (TRACK_HOST_HEIGHT - THUMB_SIZE) * 0.5

	_track_bg = ColorRect.new()
	_track_bg.name = "TrackBg"
	_track_bg.color = TRACK_REST_BG
	_track_bg.size = Vector2(TRACK_WIDTH, TRACK_HEIGHT)
	_track_bg.position = Vector2(0, track_y)
	_track_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track_host.add_child(_track_bg)

	_track_fill = ColorRect.new()
	_track_fill.name = "TrackFill"
	_track_fill.color = TRACK_REST_FILL
	_track_fill.size = Vector2(0, TRACK_HEIGHT)
	_track_fill.position = Vector2(0, track_y)
	_track_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track_host.add_child(_track_fill)

	_thumb = ColorRect.new()
	_thumb.name = "Thumb"
	_thumb.color = THUMB_REST_COLOR
	_thumb.size = Vector2(THUMB_SIZE, THUMB_SIZE)
	_thumb.position = Vector2(0, thumb_y)
	_thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track_host.add_child(_thumb)

	# 透明 HSlider：只负责鼠标拖动（键盘由场景统一处理，focus_mode 关掉防抢焦点）
	_slider = HSlider.new()
	_slider.name = "HSlider"
	_slider.position = Vector2.ZERO
	_slider.size = Vector2(TRACK_WIDTH, TRACK_HOST_HEIGHT)
	_slider.min_value = 0.0
	_slider.max_value = 1.0
	_slider.step = 0.01
	_slider.focus_mode = Control.FOCUS_NONE
	_slider.modulate.a = 0.0
	_slider.add_theme_stylebox_override("slider", StyleBoxEmpty.new())
	_slider.add_theme_stylebox_override("grabber_area", StyleBoxEmpty.new())
	_slider.add_theme_stylebox_override("grabber_area_highlight", StyleBoxEmpty.new())
	_slider.add_theme_stylebox_override("grabber", StyleBoxEmpty.new())
	_slider.add_theme_stylebox_override("grabber_highlight", StyleBoxEmpty.new())
	track_host.add_child(_slider)

	_add_fixed_spacer(PCT_GAP, "GapPct")

	_pct_label = Label.new()
	_pct_label.name = "PctLabel"
	_pct_label.custom_minimum_size = Vector2(PCT_WIDTH, 0)
	_pct_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_pct_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_pct_label.add_theme_font_size_override("font_size", VALUE_FONT_SIZE)
	_pct_label.add_theme_color_override("font_color", PCT_REST_COLOR)
	_pct_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if GameManager.font_zh_body:
		_pct_label.add_theme_font_override("font", GameManager.font_zh_body)
	_content_row.add_child(_pct_label)

	# 落盘防抖：停手 COMMIT_DELAY 后提交一次
	_commit_timer = Timer.new()
	_commit_timer.name = "CommitTimer"
	_commit_timer.one_shot = true
	_commit_timer.wait_time = COMMIT_DELAY
	_commit_timer.timeout.connect(_on_commit_timeout)
	add_child(_commit_timer)

	_slider.value_changed.connect(_on_slider_changed)


# ── Public API ─────────────────────────────────────────

func configure(p_row_id: String, p_label: String, p_initial_value: float, p_setting_key: String) -> void:
	row_id = p_row_id
	_setting_key = p_setting_key
	_set_primary_text(p_label)
	_slider.set_value_no_signal(p_initial_value)
	_update_track(p_initial_value)


func refresh_locale(data: Dictionary) -> void:
	_set_primary_text(str(data["zh"]))


func refresh_value(settings: AppSettings, _display_text: String) -> void:
	var value: float = settings.get_prop(_setting_key)
	_slider.set_value_no_signal(value)
	_update_track(value)


## 键盘步进：走与鼠标相同的一条更新链，并立刻落盘（离散操作不需要防抖）。
func step_value(delta: float) -> void:
	_slider.value = clampf(_slider.value + delta, 0.0, 1.0)
	_commit_now()


func get_value() -> float:
	return _slider.value


## 收尾钩子：切分类/退出场景时把还没提交的值立刻落盘
## （场景隐藏后 Timer 会随 process_mode 暂停，不及时提交就等于丢值）。
func flush_pending() -> void:
	if _has_pending_commit:
		_commit_now()


# ── 内部 ───────────────────────────────────────────────

func _on_slider_changed(value: float) -> void:
	_update_track(value)
	value_changed.emit(value, row_id)
	_has_pending_commit = true
	if _commit_timer:
		_commit_timer.start()


func _on_commit_timeout() -> void:
	_has_pending_commit = false
	value_committed.emit(_slider.value, row_id)


func _commit_now() -> void:
	_has_pending_commit = false
	if _commit_timer:
		_commit_timer.stop()
	value_committed.emit(_slider.value, row_id)


## 唯一写轨道/拇指/读数的地方（value 已在 0..1）。
func _update_track(value: float) -> void:
	var clamped: float = clampf(value, 0.0, 1.0)
	var fill_width: float = TRACK_WIDTH * clamped
	_track_fill.size.x = fill_width
	_thumb.position.x = clampf(fill_width - THUMB_SIZE * 0.5, 0.0, TRACK_WIDTH - THUMB_SIZE)
	_pct_label.text = str(roundi(clamped * 100.0)) + "%"


func _tween_focus_colors(p_tween: Tween, p_focused: bool) -> void:
	var bg_color: Color = TRACK_FOCUS_BG if p_focused else TRACK_REST_BG
	var fill_color: Color = TRACK_FOCUS_FILL if p_focused else TRACK_REST_FILL
	var thumb_color: Color = THUMB_FOCUS_COLOR if p_focused else THUMB_REST_COLOR
	var pct_color: Color = PCT_FOCUS_COLOR if p_focused else PCT_REST_COLOR
	p_tween.tween_property(_track_bg, "color", bg_color, FOCUS_DURATION)
	p_tween.tween_property(_track_fill, "color", fill_color, FOCUS_DURATION)
	p_tween.tween_property(_thumb, "color", thumb_color, FOCUS_DURATION)
	p_tween.tween_property(_pct_label, "theme_override_colors/font_color",
		pct_color, FOCUS_DURATION)


func _reset_value_colors() -> void:
	if _track_bg:
		_track_bg.color = TRACK_REST_BG
	if _track_fill:
		_track_fill.color = TRACK_REST_FILL
	if _thumb:
		_thumb.color = THUMB_REST_COLOR
	if _pct_label:
		_pct_label.add_theme_color_override("font_color", PCT_REST_COLOR)
