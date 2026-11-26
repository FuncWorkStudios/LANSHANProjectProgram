## OpAcc : Control — 行动完成标题卡（Operation / Accomplished + 行动信息条）。
## 关卡完成时的过场，分两个阶段：
##   阶段 1 — Operation / Accomplished 扫入 + 信息条（沿用 OpStart 的动画语言）；
##   阶段 2 — 旧控件滑到 OpAcc2 版式（白带收到右侧、InfoBar 上移变薄），
##            面板 → 白条 → 列表逐行 → 底栏依次入场；按住任意键列表加速。
## 阶段 1 的 HOLD 到点自动进入阶段 2（按任意键可提前）；阶段 2 完成后按任意键
## （或点底栏）退场，播完发 playback_finished。
## 阶段 2 的摆位来自 OpAcc2.tscn —— 它只是版式模板：根节点不挂脚本、不参与运行，
## 改完编辑器里的摆位运行时直接生效（见 _setup_stage2_template()）。
## 节点一律按名字递归查找，所以场景层级可以随意嵌套、重排。
## 注意：扫入/扫出是各色块自己的 scale.x，父级扫白会连带缩放子节点 ——
## 当前时间轴里子节点在父级扫白时恰好不可见，所以看不出双重缩放；改时间轴时留意。
extends Control

## 一段播放结束（已复位并隐藏）。行动流程可据此衔接下一步。
signal playback_finished()

## 播放阶段：
##   IDLE → ENTER（不可跳过）→ HOLD（到点自动 / 按键提前，进入阶段 2）
##        → STAGE2_ENTER（旧控件滑位 + 面板/白条入场）→ STAGE2_LIST（逐行入场，按住加速）
##        → STAGE2_IDLE（等任意键退场）→ EXIT（不可再跳过）。
enum Phase { IDLE, ENTER, HOLD, STAGE2_ENTER, STAGE2_LIST, STAGE2_IDLE, EXIT }

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

## 确认列表占位内容 —— 正式流程接入前，F7 预览与空列表都回退到这组数据。
## 行格式与 MainMenuList 一致：title（拉丁字形，字体 TCM）+ subtitle（中文，衬线体）。
const DEBUG_CONFIRM_ITEMS: Array[Dictionary] = [
	{"title": "TARGET", "subtitle": "已完成 目标确认"},
	{"title": "EVIDENCE", "subtitle": "已完成 证据回收"},
	{"title": "CORDON", "subtitle": "已完成 现场封锁"},
	{"title": "ROLL CALL", "subtitle": "已完成 人员清点"},
	{"title": "ARCHIVE", "subtitle": "已完成 记录归档"},
	{"title": "SETTLEMENT", "subtitle": "已完成 行动结算"},
	{"title": "WITNESS", "subtitle": "已完成 证人问询"},
	{"title": "RECORDING", "subtitle": "已完成 影像留档"},
	{"title": "SEAL", "subtitle": "已完成 证物封存"},
	{"title": "DEBRIEF", "subtitle": "已完成 事前简报"},
	{"title": "TRANSPORT", "subtitle": "已完成 转运交接"},
	{"title": "CLEARANCE", "subtitle": "已完成 权限注销"},
	{"title": "TARGET", "subtitle": "已完成 目标确认"},
	{"title": "EVIDENCE", "subtitle": "已完成 证据回收"},
	{"title": "CORDON", "subtitle": "已完成 现场封锁"},
	{"title": "ROLL CALL", "subtitle": "已完成 人员清点"},
	{"title": "ARCHIVE", "subtitle": "已完成 记录归档"},
	{"title": "SETTLEMENT", "subtitle": "已完成 行动结算"},
	{"title": "WITNESS", "subtitle": "已完成 证人问询"},
	{"title": "RECORDING", "subtitle": "已完成 影像留档"},
	{"title": "SEAL", "subtitle": "已完成 证物封存"},
	{"title": "DEBRIEF", "subtitle": "已完成 事前简报"},
	{"title": "TRANSPORT", "subtitle": "已完成 转运交接"},
	{"title": "CLEARANCE", "subtitle": "已完成 权限注销"},
	{"title": "TARGET", "subtitle": "已完成 目标确认"},
	{"title": "EVIDENCE", "subtitle": "已完成 证据回收"},
	{"title": "CORDON", "subtitle": "已完成 现场封锁"},
	{"title": "ROLL CALL", "subtitle": "已完成 人员清点"},
	{"title": "ARCHIVE", "subtitle": "已完成 记录归档"},
	{"title": "SETTLEMENT", "subtitle": "已完成 行动结算"},
	{"title": "WITNESS", "subtitle": "已完成 证人问询"},
	{"title": "RECORDING", "subtitle": "已完成 影像留档"},
	{"title": "SEAL", "subtitle": "已完成 证物封存"},
	{"title": "DEBRIEF", "subtitle": "已完成 事前简报"},
	{"title": "TRANSPORT", "subtitle": "已完成 转运交接"},
	{"title": "CLEARANCE", "subtitle": "已完成 权限注销"},
	{"title": "TARGET", "subtitle": "已完成 目标确认"},
	{"title": "EVIDENCE", "subtitle": "已完成 证据回收"},
	{"title": "CORDON", "subtitle": "已完成 现场封锁"},
	{"title": "ROLL CALL", "subtitle": "已完成 人员清点"},
	{"title": "ARCHIVE", "subtitle": "已完成 记录归档"},
	{"title": "SETTLEMENT", "subtitle": "已完成 行动结算"},
	{"title": "WITNESS", "subtitle": "已完成 证人问询"},
	{"title": "RECORDING", "subtitle": "已完成 影像留档"},
	{"title": "SEAL", "subtitle": "已完成 证物封存"},
	{"title": "DEBRIEF", "subtitle": "已完成 事前简报"},
	{"title": "TRANSPORT", "subtitle": "已完成 转运交接"},
	{"title": "CLEARANCE", "subtitle": "已完成 权限注销"},
	{"title": "TARGET", "subtitle": "已完成 目标确认"},
	{"title": "EVIDENCE", "subtitle": "已完成 证据回收"},
	{"title": "CORDON", "subtitle": "已完成 现场封锁"},
	{"title": "ROLL CALL", "subtitle": "已完成 人员清点"},
	{"title": "ARCHIVE", "subtitle": "已完成 记录归档"},
	{"title": "SETTLEMENT", "subtitle": "已完成 行动结算"},
	{"title": "WITNESS", "subtitle": "已完成 证人问询"},
	{"title": "RECORDING", "subtitle": "已完成 影像留档"},
	{"title": "SEAL", "subtitle": "已完成 证物封存"},
	{"title": "DEBRIEF", "subtitle": "已完成 事前简报"},
	{"title": "TRANSPORT", "subtitle": "已完成 转运交接"},
	{"title": "CLEARANCE", "subtitle": "已完成 权限注销"},
]

# ── 第二阶段（OpAcc2 版式）──

## 版式模板 —— 只当坐标来源 + 新控件来源，不参与运行（见 _setup_stage2_template()）。
const STAGE2_TEMPLATE: String = "res://scenes/game/operations/OpProgress/OpAcc/OpAcc2.tscn"

## 阶段 1 HOLD 的停留时间：到点自动进阶段 2（按任意键可提前）。
const STAGE2_HOLD_DUR: float = 1.35

## 旧控件滑到第二阶段版式（白带右移收窄，黑块跟着收）。
const S2_MOVE_DUR: float = 0.60
## InfoBar：上移 + 变薄 + 字号缩小（条里的 Label 锚在中心，会自己跟着条走）。
## 模板里这两个 Label 的字号只用于编辑器预览 —— 运行时按这里的比例缩，
## 这样 CJK / 拉丁两种名号（50 / 54）都能等比收进 54 高的条里。
const S2_INFO_DELAY: float = 0.06
const S2_INFO_DUR: float = 0.54
const S2_INFO_FONT_SCALE: float = 0.72

## ConfirmListStage：淡入 + 左推（不用 scale.x —— 面板里的文字会被父级缩放压扁）。
const S2_PANEL_DELAY: float = 0.46
const S2_PANEL_DUR: float = 0.34
const S2_PANEL_SLIDE: float = 56.0

## 白条 + 标题字。
const S2_TITLE_DELAY: float = 0.62
const S2_TITLE_DUR: float = 0.22
const S2_TITLE_LABEL_DELAY: float = 0.10
const S2_TITLE_LABEL_DUR: float = 0.18
const S2_TITLE_SLIDE: float = 40.0
const S2_TITLE_LABEL_SLIDE: float = 24.0

## 列表行：沿用 OptionRow 的入场（+100 → 静止位），只改错峰与按住加速倍数。
const S2_ROW_STAGGER: float = 0.07
const S2_FAST_SCALE: float = 3.0

## 底栏：最后入场、从下往上；退场向下走出去。
const S2_BAR_DELAY: float = 0.10
const S2_BAR_DUR: float = 0.28
const S2_BAR_SLIDE: float = 24.0

## 第二阶段退场（相对退场起点）。
const S2_EXIT_LIST_DUR: float = 0.18
const S2_EXIT_TITLE_LABEL_DUR: float = 0.12
const S2_EXIT_PANEL_DELAY: float = 0.06
const S2_EXIT_PANEL_DUR: float = 0.22
const S2_EXIT_PANEL_SLIDE: float = 40.0
const S2_EXIT_STAGE_DELAY: float = 0.16
const S2_EXIT_STAGE_DUR: float = 0.34
const S2_EXIT_STAGE_SLIDE: float = 96.0
const S2_EXIT_BACKDROP_DUR: float = 0.30

# ── State ──

var _phase: Phase = Phase.IDLE
var _timeline: Tween = null
var _title_rest_x: float = 0.0
var _start_rest_x: float = 0.0
var _number_rest_x: float = 0.0
var _name_rest_x: float = 0.0

# ── 第二阶段 State ──
var _has_stage2: bool = false           # 模板读成功才有第二阶段
var _s2_active: bool = false
var _s2_tween: Tween = null
var _s2_targets: Dictionary = {}        # 节点 → { 属性名: 第二阶段目标值 }
var _s1_rest: Dictionary = {}           # 节点 → { 属性名: 第一阶段原值（复位用） }
var _confirm_stage: ColorRect = null
var _confirm_title: ColorRect = null
var _confirm_title_label: Label = null
var _confirm_list: MainMenuList = null
var _confirm_scroll: ScrollContainer = null
var _auto_follow: bool = true           # 入场期间自动把视口带到列表底部
var _scroll_tween: Tween = null
var _back_bar: BackBar = null
var _confirm_stage_rest_x: float = 0.0
var _confirm_title_rest_x: float = 0.0
var _confirm_title_label_rest_x: float = 0.0
var _back_bar_rest_y: float = 0.0
var _row_tweens: Array[Tween] = []
var _bar_tween: Tween = null
var _held_inputs: Dictionary = {}       # 按住中的键/鼠标（按住加速用）
var _confirm_items: Array[Dictionary] = []
var _number_font_rest: int = 0
var _name_font_rest: int = 0

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
		push_error("OpAcc: 场景缺少必要节点（Backdrop / Stage / Band / TitleBlock / " +
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
	# 阶段 1 的字号原值 —— 阶段 2 按比例缩小、播完复位
	_number_font_rest = _number_label.get_theme_font_size("font_size")
	await _setup_stage2_template()


# ===================================================================
# 公共接口
# ===================================================================

## p_confirm_items：确认列表内容 [{ "title": String, "subtitle": String }]（空则用占位数据）。
func play(p_operation_no: int, p_operation_name: String,
		p_confirm_items: Array[Dictionary] = []) -> void:
	if _phase != Phase.IDLE:
		return
	_phase = Phase.ENTER
	_kill_timeline()
	_confirm_items = p_confirm_items
	_s2_active = false
	_capture_rest_poses()
	_prepare_stage2_poses()
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
	_name_font_rest = name_size


func _setup_card_font() -> void:
	var stack: Font = _build_card_font()
	if not stack:
		return
	var labels: Array[Label] = [_title_label, _start_label, _number_label, _name_label]
	for label: Label in labels:
		label.add_theme_font_override("font", stack)


## GOTHIC 只有拉丁字形 —— 叠一层中文正文做 fallback，中文行动名才不会变豆腐块。
func _build_card_font() -> Font:
	var latin: Font = load(FONT_UI_LATIN) as Font
	if not latin:
		push_warning("OpAcc: missing font ", FONT_UI_LATIN)
		return null
	var stack: FontVariation = FontVariation.new()
	stack.base_font = latin
	var body: Font = GameManager.font_zh_body
	if body:
		var fallbacks: Array[Font] = []
		fallbacks.append(body)
		stack.fallbacks = fallbacks
	return stack


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
	# 有第二阶段就停留到点自动推进（按键可提前）；没有就沿用原来的自动退场。
	_timeline.tween_interval(STAGE2_HOLD_DUR if _has_stage2 else HOLD_DUR)
	_timeline.tween_callback(_on_hold_timeout)


func _on_hold_timeout() -> void:
	if _phase != Phase.HOLD:
		return
	_timeline = null   # 别在自己的回调里 kill 自己
	_begin_stage2()


# ===================================================================
# 退场
# ===================================================================

func _play_exit() -> void:
	if _phase == Phase.EXIT or _phase == Phase.IDLE:
		return
	if _s2_active:
		_play_stage2_exit()
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
# 第二阶段 — 模板 / 姿态 / 时间轴
# ===================================================================

## 读 OpAcc2 的摆位当目标，并把第二阶段专属控件（ConfirmListStage / BackBar）搬进来。
## OpAcc2 只是版式模板：根节点不挂脚本、不参与运行；改完编辑器里的摆位运行时直接生效。
## 模板缺失 / 缺节点时退化成单阶段卡（HOLD 到点直接退场），不会卡死。
func _setup_stage2_template() -> void:
	var packed: PackedScene = load(STAGE2_TEMPLATE) as PackedScene
	if not packed:
		push_error("OpAcc: 第二阶段模板加载失败 — ", STAGE2_TEMPLATE)
		return
	var tpl: Control = packed.instantiate() as Control
	if not tpl:
		push_error("OpAcc: 第二阶段模板实例化失败 — ", STAGE2_TEMPLATE)
		return
	# 透明而不是 visible = false —— 保证这一帧锚点/尺寸一定算出来（可见性不影响布局，
	# 但 alpha=0 的节点更不容易踩到"首帧还没排完版"的边界）。这一帧整卡还没播，看不出来。
	tpl.modulate.a = 0.0
	tpl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(tpl)
	await get_tree().process_frame   # 等锚点 / 尺寸落定后再读绝对位置

	var tpl_band: ColorRect = tpl.find_child("Band", true, false) as ColorRect
	var tpl_block: ColorRect = tpl.find_child("TitleBlock", true, false) as ColorRect
	var tpl_title: Label = tpl.find_child("TitleLabel", true, false) as Label
	var tpl_start: Label = tpl.find_child("StartLabel", true, false) as Label
	var tpl_info: ColorRect = tpl.find_child("InfoBar", true, false) as ColorRect
	var tpl_panel: ColorRect = tpl.find_child("ConfirmListStage", true, false) as ColorRect
	if not (tpl_band and tpl_block and tpl_title and tpl_start and tpl_info and tpl_panel):
		push_error("OpAcc: 第二阶段模板缺少必要节点（Band / TitleBlock / TitleLabel / " +
			"StartLabel / InfoBar / ConfirmListStage）")
		tpl.queue_free()
		return

	# 目标姿态（第二阶段的 offset）+ 第一阶段原值（播完复位用）。
	# 竖直方向只由 InfoBar 的 top/bottom 决定 —— 两个标题的竖直零头已在模板里归零。
	_s2_targets = {
		_band: {"offset_left": tpl_band.offset_left},
		_title_block: {
			"offset_left": tpl_block.offset_left,
			"offset_right": tpl_block.offset_right,
		},
		_title_label: {
			"offset_left": tpl_title.offset_left,
			"offset_top": tpl_title.offset_top,
			"offset_right": tpl_title.offset_right,
			"offset_bottom": tpl_title.offset_bottom,
		},
		_start_label: {
			"offset_left": tpl_start.offset_left,
			"offset_top": tpl_start.offset_top,
			"offset_right": tpl_start.offset_right,
			"offset_bottom": tpl_start.offset_bottom,
		},
		_info_bar: {
			"offset_top": tpl_info.offset_top,
			"offset_bottom": tpl_info.offset_bottom,
		},
	}
	_s1_rest = {}
	for p_node: Control in _s2_targets:
		var rest: Dictionary = {}
		for prop: String in _s2_targets[p_node]:
			rest[prop] = p_node.get(prop)
		_s1_rest[p_node] = rest

	# 面板挪到 Stage 下（和会移动的白带解耦），负锚点归一成左上。
	var panel_rect: Rect2 = tpl_panel.get_global_rect()
	tpl_panel.reparent(_stage, false)
	tpl_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	tpl_panel.position = panel_rect.position
	tpl_panel.size = panel_rect.size
	_confirm_stage = tpl_panel
	_confirm_stage_rest_x = _confirm_stage.position.x

	_confirm_title = _confirm_stage.find_child("ConfirmTitle", true, false) as ColorRect
	_confirm_title_label = _confirm_stage.find_child("ConfirmTitleLabel", true, false) as Label
	_confirm_list = _confirm_stage.find_child("ConfirmList", true, false) as MainMenuList
	_confirm_scroll = _confirm_stage.find_child("ConfirmScroll", true, false) as ScrollContainer
	if _confirm_title:
		_confirm_title_rest_x = _confirm_title.position.x
	if _confirm_title_label:
		_confirm_title_label_rest_x = _confirm_title_label.position.x
		var title_font: Font = _build_card_font()
		if title_font:
			_confirm_title_label.add_theme_font_override("font", title_font)
	# 列表在模板里已套 ScrollContainer（滚动条常显），裁剪/滚动都由它负责。

	# 底栏换成「␣ 确认」：只发 pressed，不把 ui_cancel 透给身后的场景。
	var tpl_bar: BackBar = tpl.find_child("BackBar", true, false) as BackBar
	if tpl_bar:
		tpl_bar.reparent(_stage, false)
		tpl_bar.set_simulate_cancel(false)
		tpl_bar.pressed.connect(_on_back_bar_pressed)
		tpl_bar.set_hint("␣", tr("确认"))
		_back_bar = tpl_bar
		_back_bar_rest_y = _back_bar.position.y

	# 新控件先藏起来等第二阶段；模板其余部分（重复的共享节点）丢弃。
	_confirm_stage.visible = false
	if _back_bar:
		_back_bar.visible = false
	tpl.queue_free()
	_has_stage2 = true


## 第二阶段元素的初始态：面板 / 白条置为透明并左偏，底栏收起，列表行预置成"未入场"。
func _prepare_stage2_poses() -> void:
	_s2_active = false
	_held_inputs.clear()
	_row_tweens.clear()
	_stage.modulate.a = 1.0
	_stage.position.x = 0.0
	if not _has_stage2:
		return
	_confirm_stage.visible = false
	_confirm_stage.modulate.a = 0.0
	_confirm_stage.position.x = _confirm_stage_rest_x - S2_PANEL_SLIDE
	if _confirm_title:
		_confirm_title.modulate.a = 0.0
		_confirm_title.position.x = _confirm_title_rest_x - S2_TITLE_SLIDE
	if _confirm_title_label:
		_confirm_title_label.modulate.a = 0.0
		_confirm_title_label.position.x = _confirm_title_label_rest_x - S2_TITLE_LABEL_SLIDE
	if _confirm_list:
		_confirm_list.modulate.a = 1.0
	if _confirm_scroll:
		_confirm_scroll.scroll_vertical = 0
	_auto_follow = true
	_cancel_scroll_tween()
	if _back_bar:
		_back_bar.visible = false
		_back_bar.modulate.a = 1.0
		_back_bar.position.y = _back_bar_rest_y


## 阶段 1 → 阶段 2。阶段 1 的 HOLD 到点自动进（按任意键可提前）。
func _begin_stage2() -> void:
	if _phase != Phase.HOLD:
		return
	if not _has_stage2:
		_play_exit()
		return
	_phase = Phase.STAGE2_ENTER
	_s2_active = true
	_kill_timeline()
	_build_confirm_rows()
	await get_tree().process_frame   # 等 VBox 排序，再摆行的初始位
	if _phase != Phase.STAGE2_ENTER:
		return
	if _confirm_list:
		_confirm_list.prepare_intro()
	_play_stage2_enter()


func _build_confirm_rows() -> void:
	if not _confirm_list:
		return
	var entries: Array[Dictionary] = _confirm_items
	if entries.is_empty():
		entries = DEBUG_CONFIRM_ITEMS
	_confirm_list.set_fonts(GameManager.font_tcm, GameManager.font_zh_title)
	_confirm_list.set_interactive(false)
	# 列表不参与交互：鼠标全部让给 ScrollContainer —— 行是 MOUSE_FILTER_STOP，
	# 停在行上会把滚轮事件截断（见 OptionRow 画廊行用 PASS 的原因）。
	_confirm_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_confirm_list.rebuild(entries)
	for p_child: Node in _confirm_list.get_children():
		var row: OptionRow = p_child as OptionRow
		if row:
			row.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _play_stage2_enter() -> void:
	_s2_tween = create_tween().set_parallel(true)
	_s2_tween.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN_OUT)

	# 1. 旧控件滑到第二阶段版式（白带右移收窄，黑块跟着收，标题字平移）
	for p_node: Control in _s2_targets:
		if p_node == _info_bar:
			continue
		for prop: String in _s2_targets[p_node]:
			_s2_tween.tween_property(p_node, prop, _s2_targets[p_node][prop], S2_MOVE_DUR)

	# 2. InfoBar 上移变薄 + 字号缩小（条里的 Label 锚在中心，会自己跟着条走）
	for prop: String in _s2_targets[_info_bar]:
		var info_tw: PropertyTweener = _s2_tween.tween_property(
			_info_bar, prop, _s2_targets[_info_bar][prop], S2_INFO_DUR)
		info_tw.set_delay(S2_INFO_DELAY).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_add_info_font_tween(_number_label, int(round(_number_font_rest * S2_INFO_FONT_SCALE)))
	_add_info_font_tween(_name_label, int(round(_name_font_rest * S2_INFO_FONT_SCALE)))

	# 3. 面板 → 白条 → 标题字
	_confirm_stage.visible = true
	var panel_fade: PropertyTweener = _s2_tween.tween_property(
		_confirm_stage, "modulate:a", 1.0, S2_PANEL_DUR)
	panel_fade.set_delay(S2_PANEL_DELAY).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	var panel_move: PropertyTweener = _s2_tween.tween_property(
		_confirm_stage, "position:x", _confirm_stage_rest_x, S2_PANEL_DUR + 0.08)
	panel_move.set_delay(S2_PANEL_DELAY).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if _confirm_title:
		var title_fade: PropertyTweener = _s2_tween.tween_property(
			_confirm_title, "modulate:a", 1.0, S2_TITLE_DUR)
		title_fade.set_delay(S2_TITLE_DELAY).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		var title_move: PropertyTweener = _s2_tween.tween_property(
			_confirm_title, "position:x", _confirm_title_rest_x, S2_TITLE_DUR)
		title_move.set_delay(S2_TITLE_DELAY).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if _confirm_title_label:
		var label_delay: float = S2_TITLE_DELAY + S2_TITLE_LABEL_DELAY
		var label_fade: PropertyTweener = _s2_tween.tween_property(
			_confirm_title_label, "modulate:a", 1.0, S2_TITLE_LABEL_DUR)
		label_fade.set_delay(label_delay).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		var label_move: PropertyTweener = _s2_tween.tween_property(
			_confirm_title_label, "position:x", _confirm_title_label_rest_x, S2_TITLE_LABEL_DUR)
		label_move.set_delay(label_delay).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	# 4. 面板 / 白条就位后，列表逐行入场
	_s2_tween.chain().tween_callback(_start_list_intro)


func _add_info_font_tween(p_label: Label, p_target_size: int) -> void:
	var from_size: float = float(p_label.get_theme_font_size("font_size"))
	var font_tw: MethodTweener = _s2_tween.tween_method(
		_set_info_font_size.bind(p_label), from_size, float(p_target_size), S2_INFO_DUR)
	font_tw.set_delay(S2_INFO_DELAY)


func _set_info_font_size(p_size: float, p_label: Label) -> void:
	p_label.add_theme_font_size_override("font_size", int(round(p_size)))


## 逐行入场。按住任意键 → 整个列表 ×S2_FAST_SCALE（松开恢复）。
func _start_list_intro() -> void:
	if _phase != Phase.STAGE2_ENTER:
		return
	_phase = Phase.STAGE2_LIST
	_row_tweens.clear()
	if not _confirm_list:
		_on_rows_done()
		return
	var fast: bool = not _held_inputs.is_empty()
	var rows: Array[Node] = _confirm_list.get_children()
	var last_tween: Tween = null
	for i: int in range(rows.size()):
		var row: OptionRow = rows[i] as OptionRow
		if not row:
			continue
		var row_tween: Tween = row.play_intro(i * S2_ROW_STAGGER, 0.0)
		if fast:
			row_tween.set_speed_scale(S2_FAST_SCALE)
		_row_tweens.append(row_tween)
		last_tween = row_tween
	_start_scroll_follow(rows.size())
	if last_tween:
		last_tween.finished.connect(_on_rows_done)
	else:
		_on_rows_done()


func _on_rows_done() -> void:
	if _phase != Phase.STAGE2_LIST:
		return
	_phase = Phase.STAGE2_IDLE
	# 完成后再"按一下"才算确认 —— 清掉按住状态，避免按住加速直接退场。
	_held_inputs.clear()
	_apply_row_speed()
	# 自动跟随收尾：保证停在最底部（加速 / 时长差一点都能落到头）。
	if _auto_follow:
		_follow_bottom()
	_play_back_bar_intro()


## 底栏最后入场：从下往上。
func _play_back_bar_intro() -> void:
	if not _back_bar:
		return
	_back_bar.visible = true
	_back_bar.modulate.a = 0.0
	_back_bar.position.y = _back_bar_rest_y + S2_BAR_SLIDE
	var bar_tween: Tween = create_tween().set_parallel(true)
	_bar_tween = bar_tween
	var fade: PropertyTweener = bar_tween.tween_property(_back_bar, "modulate:a", 1.0, S2_BAR_DUR)
	fade.set_delay(S2_BAR_DELAY)
	var move: PropertyTweener = bar_tween.tween_property(
		_back_bar, "position:y", _back_bar_rest_y, S2_BAR_DUR)
	move.set_delay(S2_BAR_DELAY).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


## 按住加速：按下记一笔、松开划掉；列表当前是否加速只看集合是否为空。
## 滚轮 / 触控板滑动不算（它们没有松开事件，记下来会一直卡在加速态）。
func _track_hold_input(p_event: InputEvent) -> void:
	if _is_scroll_event(p_event):
		return
	if p_event is InputEventKey:
		var key: InputEventKey = p_event as InputEventKey
		if key.echo:
			return
		var key_id: String = "k%d" % key.keycode
		if key.pressed:
			_held_inputs[key_id] = true
		else:
			_held_inputs.erase(key_id)
	elif p_event is InputEventMouseButton:
		var mb: InputEventMouseButton = p_event as InputEventMouseButton
		var mouse_id: String = "m%d" % mb.button_index
		if mb.pressed:
			_held_inputs[mouse_id] = true
		else:
			_held_inputs.erase(mouse_id)
	else:
		return
	_apply_row_speed()


func _apply_row_speed() -> void:
	var speed: float = S2_FAST_SCALE if not _held_inputs.is_empty() else 1.0
	for tw: Tween in _row_tweens:
		if tw and tw.is_valid():
			tw.set_speed_scale(speed)
	if _scroll_tween and _scroll_tween.is_valid():
		_scroll_tween.set_speed_scale(speed)


## 自动跟随：入场期间把视口从顶部一路带到列表最底部。
## 用户一旦自己滚轮（_cancel_auto_follow），就不再把人拽回去。
func _start_scroll_follow(p_row_count: int) -> void:
	_cancel_scroll_tween()
	if not _auto_follow or not _confirm_scroll or not _confirm_list:
		return
	_confirm_scroll.scroll_vertical = 0
	var max_scroll: int = _scroll_max()
	if max_scroll <= 0:
		return
	# 时长贴着入场节奏：最后一行滑完时正好到底
	var duration: float = maxf(0.20, float(p_row_count - 1) * S2_ROW_STAGGER + 0.45)
	_scroll_tween = create_tween()
	var follow: PropertyTweener = _scroll_tween.tween_property(
		_confirm_scroll, "scroll_vertical", max_scroll, duration)
	follow.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_scroll_tween.set_speed_scale(S2_FAST_SCALE if not _held_inputs.is_empty() else 1.0)


func _follow_bottom() -> void:
	_cancel_scroll_tween()
	if _confirm_scroll:
		_confirm_scroll.scroll_vertical = _scroll_max()


## 列表能滚多远（内容高 - 视口高，没有溢出就是 0）。
## 取 size 与最小尺寸的较大者：滚动区还没重排时 size 可能仍是旧值，最小尺寸已经含了全部行高。
func _scroll_max() -> int:
	if not _confirm_scroll or not _confirm_list:
		return 0
	var content_height: float = maxf(_confirm_list.size.y, _confirm_list.get_combined_minimum_size().y)
	return int(maxf(0.0, content_height - _confirm_scroll.size.y))


func _cancel_scroll_tween() -> void:
	if _scroll_tween and _scroll_tween.is_valid():
		_scroll_tween.kill()
	_scroll_tween = null


## 用户自己动了滚轮 → 停掉自动跟随，之后不再把人拽回底部。
func _cancel_auto_follow() -> void:
	_auto_follow = false
	_cancel_scroll_tween()


## 阶段 2 退场：列表 / 白条 / 面板 / 底栏先收，白带整组右移淡出，背景最后淡出。
func _play_stage2_exit() -> void:
	_phase = Phase.EXIT
	if _s2_tween and _s2_tween.is_valid():
		_s2_tween.kill()
	if _bar_tween and _bar_tween.is_valid():
		_bar_tween.kill()
	_bar_tween = null
	_s2_tween = create_tween().set_parallel(true)
	_s2_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)

	# 1. 列表 / 白条 / 标题字先收
	if _confirm_list:
		_s2_tween.tween_property(_confirm_list, "modulate:a", 0.0, S2_EXIT_LIST_DUR)
	if _confirm_title_label:
		_s2_tween.tween_property(_confirm_title_label, "modulate:a", 0.0, S2_EXIT_TITLE_LABEL_DUR)
	if _confirm_title:
		var title_fade: PropertyTweener = _s2_tween.tween_property(
			_confirm_title, "modulate:a", 0.0, S2_EXIT_PANEL_DUR)
		title_fade.set_delay(S2_EXIT_PANEL_DELAY)

	# 2. 面板淡出 + 左推
	var panel_fade: PropertyTweener = _s2_tween.tween_property(
		_confirm_stage, "modulate:a", 0.0, S2_EXIT_PANEL_DUR)
	panel_fade.set_delay(S2_EXIT_PANEL_DELAY)
	var panel_move: PropertyTweener = _s2_tween.tween_property(
		_confirm_stage, "position:x", _confirm_stage_rest_x - S2_EXIT_PANEL_SLIDE,
		S2_EXIT_PANEL_DUR)
	panel_move.set_delay(S2_EXIT_PANEL_DELAY)

	# 3. 底栏向下走出去
	if _back_bar:
		var bar_fade: PropertyTweener = _s2_tween.tween_property(
			_back_bar, "modulate:a", 0.0, S2_EXIT_PANEL_DUR)
		bar_fade.set_delay(S2_EXIT_PANEL_DELAY)
		var bar_move: PropertyTweener = _s2_tween.tween_property(
			_back_bar, "position:y", _back_bar_rest_y + S2_BAR_SLIDE * 2.0, S2_EXIT_PANEL_DUR)
		bar_move.set_delay(S2_EXIT_PANEL_DELAY)

	# 4. 舞台整组右移淡出 + 背景淡出
	var stage_fade: PropertyTweener = _s2_tween.tween_property(
		_stage, "modulate:a", 0.0, S2_EXIT_STAGE_DUR)
	stage_fade.set_delay(S2_EXIT_STAGE_DELAY)
	var stage_move: PropertyTweener = _s2_tween.tween_property(
		_stage, "position:x", S2_EXIT_STAGE_SLIDE, S2_EXIT_STAGE_DUR)
	stage_move.set_delay(S2_EXIT_STAGE_DELAY)
	var bg_fade: PropertyTweener = _s2_tween.tween_property(
		_backdrop, "modulate:a", 0.0, S2_EXIT_BACKDROP_DUR)
	bg_fade.set_delay(S2_EXIT_STAGE_DELAY)

	_s2_tween.chain().tween_callback(_on_playback_finished)


## 复位第二阶段改造过的一切（下一轮 play() 从阶段 1 的原样重新开始）。
func _restore_stage2_poses() -> void:
	_held_inputs.clear()
	_row_tweens.clear()
	if _s2_tween and _s2_tween.is_valid():
		_s2_tween.kill()
	_s2_tween = null
	if _bar_tween and _bar_tween.is_valid():
		_bar_tween.kill()
	_bar_tween = null
	_cancel_scroll_tween()
	_auto_follow = true
	_stage.modulate.a = 1.0
	_stage.position.x = 0.0
	for p_node: Control in _s1_rest:
		for prop: String in _s1_rest[p_node]:
			p_node.set(prop, _s1_rest[p_node][prop])
	_number_label.add_theme_font_size_override("font_size", _number_font_rest)
	_name_label.add_theme_font_size_override("font_size", _name_font_rest)
	if not _has_stage2:
		return
	_confirm_stage.visible = false
	_confirm_stage.modulate.a = 1.0
	_confirm_stage.position.x = _confirm_stage_rest_x
	if _confirm_title:
		_confirm_title.modulate.a = 1.0
		_confirm_title.position.x = _confirm_title_rest_x
	if _confirm_title_label:
		_confirm_title_label.modulate.a = 1.0
		_confirm_title_label.position.x = _confirm_title_label_rest_x
	if _confirm_list:
		_confirm_list.modulate.a = 1.0
	if _back_bar:
		_back_bar.visible = false
		_back_bar.modulate.a = 1.0
		_back_bar.position.y = _back_bar_rest_y


func _on_back_bar_pressed() -> void:
	if _phase == Phase.STAGE2_IDLE:
		_play_exit()


# ===================================================================
# 收尾 / 工具
# ===================================================================

func _on_playback_finished() -> void:
	_timeline = null
	_s2_tween = null
	_set_active(false)
	_backdrop.modulate.a = 0.0
	_restore_stage2_poses()
	_restore_rest_poses()
	_s2_active = false
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
		# F7 调试预览（仅 Debug 构建）
		if OS.is_debug_build() and event is InputEventKey:
			var debug_key: InputEventKey = event as InputEventKey
			if debug_key.pressed and not debug_key.echo and debug_key.keycode == KEY_F7:
				play(DEBUG_OPERATION_NO, DEBUG_OPERATION_NAME, DEBUG_CONFIRM_ITEMS)
				get_viewport().set_input_as_handled()
		return

	match _phase:
		Phase.HOLD:
			if _is_dismiss_event(event):
				_begin_stage2()
		Phase.STAGE2_ENTER, Phase.STAGE2_LIST:
			# 按住加速：按下开始、松开停止（提前按住也会带进列表）
			_track_hold_input(event)
		Phase.STAGE2_IDLE:
			if _is_exit_key(event):
				_play_exit()

	# 滚轮 / 触控板滑动放行给列表自己的 ScrollContainer（它们不参与"按住加速"）；
	# 用户一滚就停掉自动跟随，之后视口交给他。面板入场期间不接管滚轮。
	if _is_scroll_event(event) and (_phase == Phase.STAGE2_LIST or _phase == Phase.STAGE2_IDLE):
		_cancel_auto_follow()
		return
	# 阶段 2 完成态把鼠标事件放行给底栏（可点确认）与滚动条；其余照旧全部吃掉。
	if _phase == Phase.STAGE2_IDLE and (event is InputEventMouseButton or event is InputEventMouseMotion):
		return
	get_viewport().set_input_as_handled()


## 滚轮 / 触控板滑动 —— 交给 ScrollContainer 原生滚动，不参与加速、也不算确认。
func _is_scroll_event(p_event: InputEvent) -> bool:
	if p_event is InputEventPanGesture:
		return true
	if p_event is InputEventMouseButton:
		var mb: InputEventMouseButton = p_event as InputEventMouseButton
		return mb.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN,
			MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]
	return false


## 完成态：任意键退场（底栏点击另走 _on_back_bar_pressed()）。
## 只认键盘、不认鼠标 —— 鼠标要留给滚动条拖动和底栏。
func _is_exit_key(p_event: InputEvent) -> bool:
	if p_event is InputEventKey:
		var key: InputEventKey = p_event as InputEventKey
		return key.pressed and not key.echo
	return false


func _is_dismiss_event(p_event: InputEvent) -> bool:
	if p_event is InputEventKey:
		var key: InputEventKey = p_event as InputEventKey
		return key.pressed and not key.echo
	if p_event is InputEventMouseButton:
		var mb: InputEventMouseButton = p_event as InputEventMouseButton
		return mb.pressed
	return false
