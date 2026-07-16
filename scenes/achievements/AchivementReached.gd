## AchivementReached : Control
## 成就达成全局弹窗 — 由 SceneManager 挂载在顶层 CanvasLayer，
## 出现在一切场景之上，不拦截其他场景的输入。
## 监听 EventBus.achievement_unlocked：右上角滑入提示，
## 停留 5 秒后自动滑出；鼠标悬停时暂停倒计时（移开后继续）。
## 样式与 ESC 返回栏一致：NameLabel 白底黑字，悬停时黑白反色。
extends Control

const SHOW_DUR: float = 0.3
const HIDE_DUR: float = 0.25
const HOLD_TIME: float = 5.0
const SLIDE_OFFSET: float = 48.0

var _queue: Array[String] = []
var _showing: bool = false
var _hovered: bool = false
var _slide_tween: Tween = null
var _hover_tween: Tween = null
var _hold_timer: Timer = null
var _tip_rest_x: float = 0.0

var _font_tcm: Font = null
var _font_zh_title: Font = null
var _font_zh_body: Font = null
var _font_en_body: Font = null

@onready var _tip: Control = $ReachTip
@onready var _name_box: ColorRect = $ReachTip/NameBox
@onready var _name_label: Label = $ReachTip/NameLabel
@onready var _desc_label: Label = $ReachTip/DescLabel


func _ready() -> void:
	_font_tcm = load(GameManager.FONT_TCM)
	_font_zh_title = load(GameManager.FONT_ZH_TITLE)
	_font_zh_body = load(GameManager.FONT_ZH_BODY)
	_font_en_body = load(GameManager.FONT_EN_BODY)

	# 根节点不拦截任何输入 — 不影响其他场景
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tip.visible = false
	_tip_rest_x = _tip.position.x

	# 停留倒计时 — 悬停时暂停
	_hold_timer = Timer.new()
	_hold_timer.name = "HoldTimer"
	_hold_timer.one_shot = true
	_hold_timer.wait_time = HOLD_TIME
	_hold_timer.timeout.connect(_dismiss)
	add_child(_hold_timer)

	_tip.mouse_entered.connect(_on_tip_hover.bind(true))
	_tip.mouse_exited.connect(_on_tip_hover.bind(false))
	EventBus.achievement_unlocked.connect(_on_achievement_unlocked)


# ===================================================================
# 队列 — 连续达成多个成就时依次展示
# ===================================================================

func _on_achievement_unlocked(achievement_id: String) -> void:
	_queue.append(achievement_id)
	if not _showing:
		_show_next()


func _show_next() -> void:
	if _queue.is_empty():
		return
	_showing = true
	var achievement_id: String = _queue.pop_front()

	_name_label.text = tr("已达成成就：")
	_desc_label.text = tr(achievement_id)
	@warning_ignore("static_called_on_instance")
	var name_font: Font = GameManager.select_font(_name_label.text, _font_zh_title, _font_tcm)
	if name_font: _name_label.add_theme_font_override("font", name_font)
	@warning_ignore("static_called_on_instance")
	var desc_font: Font = GameManager.select_font(_desc_label.text, _font_zh_body, _font_en_body)
	if desc_font: _desc_label.add_theme_font_override("font", desc_font)

	_apply_hover_colors(false, true)

	# 滑入 — 与 ESC 返回栏同款 TRANS_EXPO 缓动
	_tip.visible = true
	_tip.modulate.a = 0.0
	_tip.position.x = _tip_rest_x + SLIDE_OFFSET
	if _slide_tween and _slide_tween.is_valid():
		_slide_tween.kill()
	_slide_tween = create_tween().set_parallel(true)
	_slide_tween.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	_slide_tween.tween_property(_tip, "modulate:a", 1.0, SHOW_DUR)
	_slide_tween.tween_property(_tip, "position:x", _tip_rest_x, SHOW_DUR)
	_slide_tween.chain().tween_callback(_start_hold)


func _start_hold() -> void:
	_hold_timer.start()
	# 滑入期间鼠标已悬停 → 立即暂停倒计时
	_hold_timer.paused = _hovered


func _dismiss() -> void:
	if _slide_tween and _slide_tween.is_valid():
		_slide_tween.kill()
	_slide_tween = create_tween().set_parallel(true)
	_slide_tween.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	_slide_tween.tween_property(_tip, "modulate:a", 0.0, HIDE_DUR)
	_slide_tween.tween_property(_tip, "position:x", _tip_rest_x + SLIDE_OFFSET, HIDE_DUR)
	_slide_tween.chain().tween_callback(_on_dismissed)


func _on_dismissed() -> void:
	_tip.visible = false
	_tip.position.x = _tip_rest_x
	_showing = false
	_show_next()


# ===================================================================
# 悬停 — 暂停倒计时 + ESC 栏同款黑白反色
# ===================================================================

func _on_tip_hover(hovered: bool) -> void:
	_hovered = hovered
	if _showing and not _hold_timer.is_stopped():
		_hold_timer.paused = hovered
	_apply_hover_colors(hovered, false)


func _apply_hover_colors(hovered: bool, instant: bool) -> void:
	var box_color: Color = Color.BLACK if hovered else Color.WHITE
	var name_color: Color = Color.WHITE if hovered else Color.BLACK
	if _hover_tween and _hover_tween.is_valid():
		_hover_tween.kill()
	if instant:
		_name_box.color = box_color
		_name_label.add_theme_color_override("font_color", name_color)
		return
	_hover_tween = create_tween().set_parallel(true)
	_hover_tween.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	_hover_tween.tween_property(_name_box, "color", box_color, 0.15)
	_hover_tween.tween_property(_name_label, "theme_override_colors/font_color", name_color, 0.15)
