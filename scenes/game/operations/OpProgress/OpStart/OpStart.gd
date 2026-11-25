## OpStart : Control — 行动开始标题卡（Operation / Start + 行动信息条）。
## 由 SceneManager 挂在 CanvasLayer（layer 99）。播放期间拦截全部输入：
## 入场不可跳过；全部元素进场后（HOLD）任意键立刻退场；退场开始后不可跳过。
## 节点一律按名字递归查找，所以场景层级可以随意嵌套、重排。
## 注意：扫入/扫出是各色块自己的 scale.x，父级扫白会连带缩放子节点 ——
## 当前时间轴里子节点在父级扫白时恰好不可见，所以看不出双重缩放；改时间轴时留意。
extends Control

## 一段播放结束（已复位并隐藏）。行动流程可据此衔接下一步。
signal playback_finished()

## 播放阶段：入场（不可跳过）→ 停留（可按键退场）→ 退场（不可再跳过）。
enum Phase { IDLE, ENTER, HOLD, EXIT }

# ── 视觉 ──

const BACKDROP_ALPHA: float = 0.75
const FONT_UI_LATIN: String = "res://assets/fonts/GOTHIC.TTF"

# ── 入场时间轴（秒，相对 play() 起点：更紧凑、先底后字） ──

const ENTER_BACKDROP_DUR: float = 0.24
const ENTER_BAND_DELAY: float = 0.10
const ENTER_BAND_DUR: float = 0.30
const ENTER_BLOCK_DELAY: float = 0.22
const ENTER_BLOCK_DUR: float = 0.22
const ENTER_BAR_DELAY: float = 0.28
const ENTER_BAR_DUR: float = 0.26

const ENTER_TITLE_DELAY: float = 0.42
const ENTER_TITLE_DUR: float = 0.24
const ENTER_START_DELAY: float = 0.48
const ENTER_START_DUR: float = 0.24
const ENTER_NUMBER_DELAY: float = 0.52
const ENTER_NAME_DELAY: float = 0.58
const ENTER_LINE_DUR: float = 0.20

## 全要素展示完毕后的停留时间（全部进场后按键可提前结束）。
const HOLD_DUR: float = 1.15

# ── 退场时间轴（秒，相对退场起点：文字先退，底板错峰利落收走） ──

const EXIT_LINE_DUR: float = 0.10
const EXIT_INFO_LINE_DELAY: float = 0.0
const EXIT_INFO_BAR_DELAY: float = 0.08
const EXIT_INFO_BAR_DUR: float = 0.24

const EXIT_TITLE_LINE_DELAY: float = 0.18
const EXIT_START_LINE_DELAY: float = 0.21
const EXIT_TITLE_BLOCK_DELAY: float = 0.26
const EXIT_TITLE_BLOCK_DUR: float = 0.22

const EXIT_BAND_DELAY: float = 0.38
const EXIT_BAND_DUR: float = 0.26
const EXIT_BACKDROP_DELAY: float = 0.44
const EXIT_BACKDROP_DUR: float = 0.24

# ── 入场滑动距离（自右向左归位，小幅度更干脆） ──

const TITLE_SLIDE: float = 24.0
const START_SLIDE: float = 28.0
const NUMBER_SLIDE: float = 18.0
const NAME_SLIDE: float = 18.0

## 行动名字号（CJK / 拉丁）
const NAME_FONT_SIZE_ZH: int = 50
const NAME_FONT_SIZE_EN: int = 54

# ── 调试（F7，仅 Debug 构建） ──

const DEBUG_OPERATION_NO: int = 1
const DEBUG_OPERATION_NAME: String = "逃离???"

# ── State ──

var _phase: Phase = Phase.IDLE
var _timeline: Tween = null
var _title_rest_x: float = 0.0
var _start_rest_x: float = 0.0
var _number_rest_x: float = 0.0
var _name_rest_x: float = 0.0

@onready var _backdrop: ColorRect = _find_rect("Backdrop")
@onready var _stage: Control = _find_node("Stage") as Control
@onready var _band: ColorRect = _find_rect("Band")
@onready var _title_block: ColorRect = _find_rect("TitleBlock")
@onready var _title_label: Label = _find_label("TitleLabel")
@onready var _start_label: Label = _find_label("StartLabel")
@onready var _info_bar: ColorRect = _find_rect("InfoBar")
@onready var _number_label: Label = _find_label("InfoNumberLabel")
@onready var _name_label: Label = _find_label("InfoNameLabel")


# ===================================================================
# 节点查找 —— 不依赖场景层级
# ===================================================================

## 按名字递归查找。色块与文字在编辑器里被重新嵌套/重排也不会失联。
func _find_node(p_name: String) -> Node:
	return find_child(p_name, true, false)


func _find_rect(p_name: String) -> ColorRect:
	return _find_node(p_name) as ColorRect


func _find_label(p_name: String) -> Label:
	return _find_node(p_name) as Label


func _validate_structure() -> bool:
	var ok: bool = (_backdrop and _stage and _band and _title_block and _title_label
			and _start_label and _info_bar and _number_label and _name_label)
	if not ok:
		push_error("OpStart: 场景缺少必要节点（Backdrop / Stage / Band / TitleBlock / " +
			"TitleLabel / StartLabel / InfoBar / InfoNumberLabel / InfoNameLabel）")
	return ok


func _ready() -> void:
	# 先校验节点齐全，避免后续连锁空引用
	if not _validate_structure():
		visible = false
		return
	_backdrop.color.a = BACKDROP_ALPHA
	_setup_card_font()
	_stage.visible = false
	_backdrop.visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE


# ===================================================================
# 公共接口
# ===================================================================

func play(p_operation_no: int, p_operation_name: String) -> void:
	if _phase != Phase.IDLE:
		return
	_phase = Phase.ENTER
	_kill_timeline()
	_capture_rest_poses()
	_apply_content(p_operation_no, p_operation_name)
	_prepare_enter_poses()
	_set_active(true)
	_play_enter()


func is_playing() -> bool:
	return _phase != Phase.IDLE


# ===================================================================
# 内容 / 字体
# ===================================================================

func _apply_content(p_operation_no: int, p_operation_name: String) -> void:
	_number_label.text = "Operation %d" % p_operation_no
	_name_label.text = p_operation_name

	@warning_ignore("static_called_on_instance")
	var name_size: int = GameManager.select_font_size(p_operation_name, NAME_FONT_SIZE_ZH, NAME_FONT_SIZE_EN)
	_name_label.add_theme_font_size_override("font_size", name_size)


func _setup_card_font() -> void:
	var latin: Font = load(FONT_UI_LATIN) as Font
	if not latin:
		push_warning("OpStart: missing font ", FONT_UI_LATIN)
		return
	var stack: FontVariation = FontVariation.new()
	stack.base_font = latin
	var body: Font = GameManager.font_zh_body
	if body:
		var fallbacks: Array[Font] = []
		fallbacks.append(body)
		stack.fallbacks = fallbacks

	var labels: Array[Label] = [_title_label, _start_label, _number_label, _name_label]
	for label: Label in labels:
		label.add_theme_font_override("font", stack)


# ===================================================================
# 姿态
# ===================================================================

func _capture_rest_poses() -> void:
	_title_rest_x = _title_label.position.x
	_start_rest_x = _start_label.position.x
	_number_rest_x = _number_label.position.x
	_name_rest_x = _name_label.position.x


func _prepare_enter_poses() -> void:
	_backdrop.modulate.a = 0.0
	_reset_wipe(_band)
	_reset_wipe(_title_block)
	_reset_wipe(_info_bar)
	_reset_line(_title_label, _title_rest_x + TITLE_SLIDE)
	_reset_line(_start_label, _start_rest_x + START_SLIDE)
	_reset_line(_number_label, _number_rest_x + NUMBER_SLIDE)
	_reset_line(_name_label, _name_rest_x + NAME_SLIDE)


func _restore_rest_poses() -> void:
	_band.pivot_offset = Vector2.ZERO
	_title_block.pivot_offset = Vector2.ZERO
	_info_bar.pivot_offset = Vector2.ZERO
	_band.scale = Vector2.ONE
	_title_block.scale = Vector2.ONE
	_info_bar.scale = Vector2.ONE

	_title_label.position.x = _title_rest_x
	_start_label.position.x = _start_rest_x
	_number_label.position.x = _number_rest_x
	_name_label.position.x = _name_rest_x

	_title_label.modulate.a = 1.0
	_start_label.modulate.a = 1.0
	_number_label.modulate.a = 1.0
	_name_label.modulate.a = 1.0


func _reset_wipe(p_rect: ColorRect) -> void:
	p_rect.pivot_offset = Vector2.ZERO
	p_rect.scale = Vector2(0.0, 1.0)


func _reset_line(p_label: Label, p_x: float) -> void:
	p_label.modulate.a = 0.0
	p_label.position.x = p_x


func _swap_pivot_to_right(p_rect: ColorRect) -> void:
	p_rect.pivot_offset = Vector2(p_rect.size.x, 0.0)


func _set_active(p_active: bool) -> void:
	_backdrop.visible = p_active
	_stage.visible = p_active
	mouse_filter = Control.MOUSE_FILTER_STOP if p_active else Control.MOUSE_FILTER_IGNORE


# ===================================================================
# 入场
# ===================================================================

func _play_enter() -> void:
	_timeline = create_tween().set_parallel(true)

	var bg_in: PropertyTweener = _timeline.tween_property(_backdrop, "modulate:a", 1.0, ENTER_BACKDROP_DUR)
	bg_in.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	_add_scan_in(_band, ENTER_BAND_DELAY, ENTER_BAND_DUR)
	_add_scan_in(_title_block, ENTER_BLOCK_DELAY, ENTER_BLOCK_DUR)
	_add_scan_in(_info_bar, ENTER_BAR_DELAY, ENTER_BAR_DUR)

	_add_line_intro(_title_label, _title_rest_x, ENTER_TITLE_DELAY, ENTER_TITLE_DUR)
	_add_line_intro(_start_label, _start_rest_x, ENTER_START_DELAY, ENTER_START_DUR)
	_add_line_intro(_number_label, _number_rest_x, ENTER_NUMBER_DELAY, ENTER_LINE_DUR)
	_add_line_intro(_name_label, _name_rest_x, ENTER_NAME_DELAY, ENTER_LINE_DUR)

	# parallel 段本身就会等到最晚那条完成，直接接回调 = 全部进场即刻进入 HOLD
	_timeline.chain().tween_callback(_start_hold)


func _add_scan_in(p_rect: ColorRect, p_delay: float, p_dur: float) -> void:
	var wipe: PropertyTweener = _timeline.tween_property(p_rect, "scale:x", 1.0, p_dur)
	wipe.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	wipe.set_delay(p_delay)


func _add_line_intro(p_label: Label, p_rest_x: float, p_delay: float, p_dur: float) -> void:
	var move: PropertyTweener = _timeline.tween_property(p_label, "position:x", p_rest_x, p_dur)
	move.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	move.set_delay(p_delay)

	var fade: PropertyTweener = _timeline.tween_property(p_label, "modulate:a", 1.0, p_dur * 0.8)
	fade.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	fade.set_delay(p_delay)


func _start_hold() -> void:
	if _phase != Phase.ENTER:
		return
	_phase = Phase.HOLD
	_kill_timeline()
	_timeline = create_tween()
	_timeline.tween_interval(HOLD_DUR)
	_timeline.tween_callback(_play_exit)


# ===================================================================
# 退场
# ===================================================================

func _play_exit() -> void:
	if _phase == Phase.EXIT or _phase == Phase.IDLE:
		return
	_phase = Phase.EXIT
	_kill_timeline()

	_swap_pivot_to_right(_band)
	_swap_pivot_to_right(_title_block)
	_swap_pivot_to_right(_info_bar)

	_timeline = create_tween().set_parallel(true)

	# 1. Info：文字先淡出，底条随后向右收
	_add_line_outro(_number_label, EXIT_INFO_LINE_DELAY, EXIT_LINE_DUR)
	_add_line_outro(_name_label, EXIT_INFO_LINE_DELAY, EXIT_LINE_DUR)
	_add_scan_out(_info_bar, EXIT_INFO_BAR_DELAY, EXIT_INFO_BAR_DUR)

	# 2. Title：两行标题淡出，黑块随后向右收
	_add_line_outro(_title_label, EXIT_TITLE_LINE_DELAY, EXIT_LINE_DUR)
	_add_line_outro(_start_label, EXIT_START_LINE_DELAY, EXIT_LINE_DUR)
	_add_scan_out(_title_block, EXIT_TITLE_BLOCK_DELAY, EXIT_TITLE_BLOCK_DUR)

	# 3. Band & Backdrop：白带扫出，黑底同步收尾
	_add_scan_out(_band, EXIT_BAND_DELAY, EXIT_BAND_DUR)

	var backdrop_fade: PropertyTweener = _timeline.tween_property(_backdrop, "modulate:a", 0.0, EXIT_BACKDROP_DUR)
	backdrop_fade.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	backdrop_fade.set_delay(EXIT_BACKDROP_DELAY)

	_timeline.chain().tween_callback(_on_playback_finished)


func _add_scan_out(p_rect: ColorRect, p_delay: float, p_dur: float) -> void:
	var wipe: PropertyTweener = _timeline.tween_property(p_rect, "scale:x", 0.0, p_dur)
	wipe.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	wipe.set_delay(p_delay)


func _add_line_outro(p_label: Label, p_delay: float, p_dur: float) -> void:
	var fade: PropertyTweener = _timeline.tween_property(p_label, "modulate:a", 0.0, p_dur)
	fade.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	fade.set_delay(p_delay)


# ===================================================================
# 收尾 / 工具
# ===================================================================

func _on_playback_finished() -> void:
	_timeline = null
	_set_active(false)
	_backdrop.modulate.a = 0.0
	_restore_rest_poses()
	_phase = Phase.IDLE
	playback_finished.emit()


func _kill_timeline() -> void:
	if _timeline and _timeline.is_valid():
		_timeline.kill()
	_timeline = null


# ===================================================================
# 输入
# ===================================================================

func _input(event: InputEvent) -> void:
	if _phase == Phase.IDLE:
		if OS.is_debug_build() and event is InputEventKey:
			var debug_key: InputEventKey = event as InputEventKey
			if debug_key.pressed and not debug_key.echo and debug_key.keycode == KEY_F7:
				play(DEBUG_OPERATION_NO, DEBUG_OPERATION_NAME)
				get_viewport().set_input_as_handled()
		return

	if _phase == Phase.HOLD and _is_dismiss_event(event):
		_request_exit()
	get_viewport().set_input_as_handled()


func _request_exit() -> void:
	if _phase != Phase.HOLD:
		return
	_play_exit()


func _is_dismiss_event(p_event: InputEvent) -> bool:
	if p_event is InputEventKey:
		var key: InputEventKey = p_event as InputEventKey
		return key.pressed and not key.echo
	if p_event is InputEventMouseButton:
		var mb: InputEventMouseButton = p_event as InputEventMouseButton
		return mb.pressed
	return false
