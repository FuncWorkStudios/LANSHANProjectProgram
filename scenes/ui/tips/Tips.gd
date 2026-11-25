## Tips : Control
## 教程弹窗 — 由 SceneManager 挂载在 CanvasLayer（layer 99，位于 AchievementReached 下方），
## 用于在游戏中显示多页教程提示。弹窗居中，缩放淡入。
## 标题固定为 "Tips"。弹窗期间拦截一切操作，只能推进/回退 tip。
## A / W / ← / ↑ / 滚轮上 → 上一页；
## 其余任意键、鼠标点击、滚轮下 → 下一页（末页时关闭）。
## 页面间内容平滑过渡，无闪烁。F8 调试触发预设页面（F7 已让给行动开始卡 OpStart）。
## 入场与退场共用同一份步骤表：退场是入场的严格倒放
## （延迟镜像、缓动取反 EASE_OUT→EASE_IN、起止值互换），因此两者在时间轴上完全相反。
extends Control

signal dismissed()

const TIP_BG_FADE_DUR: float = 0.6        # 背景淡入淡出时长（柔和过渡）
const TIP_PANEL_DUR: float = 0.4          # 面板缩放 + 淡入/淡出时长
const TIP_STAGGER_DUR: float = 0.5        # 内部元素错峰动画时长
const TIP_BOX_DELAY: float = 0.06         # TitleBox 白条展开延迟
const TIP_TITLE_DELAY: float = TIP_BOX_DELAY + 0.04   # TitleLabel 延迟
const TIP_DESC_DELAY: float = 0.08        # DescLabel 延迟
const TIP_PAGE_DELAY: float = 0.10        # PageLabel 延迟
const TIP_ENTER_SCALE: float = 0.85       # 入场起始缩放（退场回落到同一值）
const TIP_CROSSFADE_DUR: float = 0.15     # 翻页时内容交叉淡入淡出时长

const DEBUG_PAGES: Array[Dictionary] = [
	{"desc": "欢迎来到兰山计划。\n这是一个教程示例。"},
	{"desc": "ESC 键可以打开菜单。\n在视觉小说中，点击或按空格键继续对话。"},
	{"desc": "在地图界面，使用鼠标拖拽移动视角。\n点击地点图标可以查看详情。"},
]

var _tip_pages: Array[Dictionary] = []
var _tip_current_page: int = -1
var _tip_active: bool = false
var _tip_closing: bool = false        # 退场动画进行中，忽略一切输入
var _tip_first_show: bool = true
var _tip_show_tween: Tween = null     # 入场动画
var _tip_hide_tween: Tween = null     # 退场动画（入场的倒放）
var _tip_page_tweens: Array[Tween] = []  # 翻页交叉淡入
var _debug_armed: bool = false       # 首次场景切换后才允许 F8，避免主菜单冲突

@onready var _backdrop: ColorRect = $Backdrop
@onready var _panel: Control = $TipPanel
@onready var _title_box: ColorRect = $TipPanel/TitleBox
@onready var _title_label: Label = $TipPanel/TitleLabel
@onready var _desc_label: Label = $TipPanel/DescLabel
@onready var _page_label: Label = $TipPanel/PageLabel


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_backdrop.visible = false
	_panel.visible = false
	EventBus.scene_changed.connect(_on_tips_scene_changed)


# ===================================================================
# 输入 — 弹窗期间拦截一切操作
# ===================================================================

func _input(event: InputEvent) -> void:
	# F8 调试（仅 Debug 构建，首次场景切换后才允许，避免主菜单冲突）
	if OS.is_debug_build() and event is InputEventKey:
		var dk: InputEventKey = event as InputEventKey
		if dk.pressed and not dk.echo and dk.keycode == KEY_F8:
			if not _tip_active and _debug_armed:
				_on_show_tips(DEBUG_PAGES)
			return

	if not _tip_active:
		return

	# 退场动画期间：只吃掉输入，不再翻页（否则会打断倒放）
	if _tip_closing:
		get_viewport().set_input_as_handled()
		return

	# 弹窗期间拦截一切输入 — 只处理翻页，其余全部吃掉
	if event is InputEventKey:
		var key: InputEventKey = event as InputEventKey
		if not key.pressed or key.echo:
			get_viewport().set_input_as_handled()
			return

		match key.keycode:
			# A / W / ← / ↑ → 上一页
			KEY_A, KEY_W, KEY_LEFT, KEY_UP:
				_tip_go_prev()
			# 其余任意键 → 下一页
			_:
				_tip_go_next()

		get_viewport().set_input_as_handled()
		return

	# 鼠标点击 → 下一页；滚轮上 → 上一页，滚轮下 → 下一页
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		# 双击会额外产生一个 double_click 事件，跳过它避免一次双击翻两页
		if mb.pressed and not mb.double_click:
			match mb.button_index:
				MOUSE_BUTTON_WHEEL_UP:
					_tip_go_prev()
				_:
					_tip_go_next()
		get_viewport().set_input_as_handled()
		return

	# 其余（鼠标移动等）全部吃掉
	get_viewport().set_input_as_handled()


# ===================================================================
# 公共接口
# ===================================================================

func _on_tips_scene_changed(_name: String) -> void:
	_debug_armed = true
func _on_show_tips(pages: Array[Dictionary]) -> void:
	if pages.is_empty():
		return
	_tip_pages = pages.duplicate(true)
	_tip_current_page = 0
	_tip_first_show = true
	_tip_closing = false
	_tip_show_current_page()


# ===================================================================
# 翻页
# ===================================================================

func _tip_go_prev() -> void:
	if _tip_current_page > 0:
		_tip_current_page -= 1
		_tip_first_show = false
		_tip_show_current_page()


func _tip_go_next() -> void:
	if _tip_current_page < _tip_pages.size() - 1:
		_tip_current_page += 1
		_tip_first_show = false
		_tip_show_current_page()
	else:
		_tip_dismiss()


func _tip_show_current_page() -> void:
	if _tip_pages.is_empty() or _tip_current_page < 0 or _tip_current_page >= _tip_pages.size():
		return

	_tip_active = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	var page: Dictionary = _tip_pages[_tip_current_page]

	_title_label.text = "Tips"
	_desc_label.text = page.get("desc", "")
	_page_label.text = "%d / %d" % [_tip_current_page + 1, _tip_pages.size()]

	if GameManager.font_tcm:
		_title_label.add_theme_font_override("font", GameManager.font_tcm)
	@warning_ignore("static_called_on_instance")
	var desc_font: Font = GameManager.select_font(_desc_label.text, GameManager.font_zh_body, GameManager.font_en_body)
	if desc_font: _desc_label.add_theme_font_override("font", desc_font)

	if _tip_first_show:
		# ── 首次入场：完整动画 ──
		_tip_kill_anim_tweens()
		_tip_play_intro()
	else:
		# ── 翻页：内容交叉淡入淡出，面板和背景不动 ──
		_tip_kill_page_tweens()
		_tip_settle_intro()
		_desc_label.modulate.a = 0.0
		var t_desc: Tween = create_tween()
		t_desc.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
		t_desc.tween_property(_desc_label, "modulate:a", 1.0, TIP_CROSSFADE_DUR)
		_tip_page_tweens.append(t_desc)

		_page_label.modulate.a = 0.0
		var t_page: Tween = create_tween()
		t_page.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
		t_page.tween_property(_page_label, "modulate:a", 1.0, TIP_CROSSFADE_DUR).set_delay(0.04)
		_tip_page_tweens.append(t_page)


# ===================================================================
# 入场 / 退场 — 同一份步骤表，互为倒放
# ===================================================================

## 入场动画步骤：每条 = 一个属性的「起始值 from → 结束值 to」（外加时长与延迟）。
## 退场不另写动画，直接把这张表倒放，所以两段动画天然对称。
func _tip_intro_steps() -> Array[Dictionary]:
	var label_dur: float = TIP_STAGGER_DUR * 0.7
	var steps: Array[Dictionary] = [
		{"node": _backdrop, "prop": "modulate:a",
			"from": 0.0, "to": 1.0, "dur": TIP_BG_FADE_DUR, "delay": 0.0},
		{"node": _panel, "prop": "modulate:a",
			"from": 0.0, "to": 1.0, "dur": TIP_PANEL_DUR, "delay": 0.0},
		{"node": _panel, "prop": "scale",
			"from": Vector2(TIP_ENTER_SCALE, TIP_ENTER_SCALE), "to": Vector2.ONE,
			"dur": TIP_PANEL_DUR, "delay": 0.0},
		# TitleBox 白条展开
		{"node": _title_box, "prop": "scale:x",
			"from": 0.0, "to": 1.0, "dur": TIP_STAGGER_DUR, "delay": TIP_BOX_DELAY},
		# TitleLabel 淡入
		{"node": _title_label, "prop": "modulate:a",
			"from": 0.0, "to": 1.0, "dur": label_dur, "delay": TIP_TITLE_DELAY},
		# DescLabel 淡入
		{"node": _desc_label, "prop": "modulate:a",
			"from": 0.0, "to": 1.0, "dur": label_dur, "delay": TIP_DESC_DELAY},
		# PageLabel 淡入
		{"node": _page_label, "prop": "modulate:a",
			"from": 0.0, "to": 1.0, "dur": TIP_STAGGER_DUR * 0.5, "delay": TIP_PAGE_DELAY},
	]
	return steps


## 整段动画的总时长（最晚结束的那一条）。
func _tip_steps_duration(steps: Array[Dictionary]) -> float:
	var total: float = 0.0
	for step: Dictionary in steps:
		total = maxf(total, float(step["delay"]) + float(step["dur"]))
	return total


## 按步骤表生成 tween。
## reverse = false：入场，延迟按原样、EASE_OUT（减速进场）。
## reverse = true ：退场，延迟镜像为「总时长 - 延迟 - 时长」、EASE_IN（加速离场）、终点取 from。
## 这样入场最后完成的元素，退场时第一个开始，时间轴严格相反。
func _tip_build_tween(steps: Array[Dictionary], reverse: bool) -> Tween:
	var total: float = _tip_steps_duration(steps)
	var tween: Tween = create_tween().set_parallel(true)
	tween.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_IN if reverse else Tween.EASE_OUT)
	for step: Dictionary in steps:
		var delay: float = float(step["delay"])
		var dur: float = float(step["dur"])
		var node: Object = step["node"] as Object
		var target: Variant = step["from"] if reverse else step["to"]
		var start: float = (total - delay - dur) if reverse else delay
		tween.tween_property(node, step["prop"] as String, target, dur).set_delay(start)
	return tween


## 把步骤表某一端（from / to）直接写成当前值 — 用于「立即摆好姿势」。
func _tip_apply_steps(steps: Array[Dictionary], use_from: bool) -> void:
	for step: Dictionary in steps:
		var node: Object = step["node"] as Object
		node.set_indexed(step["prop"] as String, step["from"] if use_from else step["to"])


func _tip_play_intro() -> void:
	var steps: Array[Dictionary] = _tip_intro_steps()
	_panel.pivot_offset = _panel.size / 2.0   # 以面板中心为缩放轴
	_tip_apply_steps(steps, true)             # 先把各元素摆到起始状态
	_backdrop.visible = true
	_panel.visible = true
	_tip_show_tween = _tip_build_tween(steps, false)


## 翻页前把入场动画收尾，避免残留 tween 与翻页动画抢同一个属性。
func _tip_settle_intro() -> void:
	if _tip_show_tween and _tip_show_tween.is_running():
		_tip_show_tween.kill()
	_tip_show_tween = null
	_tip_apply_steps(_tip_intro_steps(), false)


# ===================================================================
# 关闭
# ===================================================================

func _tip_dismiss() -> void:
	if _tip_closing:
		return
	_tip_closing = true
	_tip_kill_anim_tweens()
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	# 退场 = 入场倒放：从当前状态开始，按镜像延迟依次收回
	_tip_hide_tween = _tip_build_tween(_tip_intro_steps(), true)
	# chain 确保整段倒放结束后才回调（parallel 里的 callback 是即时的！）
	_tip_hide_tween.chain().tween_callback(_tip_on_dismissed)


func _tip_on_dismissed() -> void:
	_panel.visible = false
	_backdrop.visible = false
	# 复位所有动画状态 — 下次从干净状态入场
	_tip_apply_steps(_tip_intro_steps(), false)
	_tip_active = false
	_tip_closing = false
	_tip_pages.clear()
	_tip_current_page = -1
	dismissed.emit()


# ===================================================================
# 动画辅助
# ===================================================================

func _tip_kill_anim_tweens() -> void:
	if _tip_show_tween and _tip_show_tween.is_valid():
		_tip_show_tween.kill()
	if _tip_hide_tween and _tip_hide_tween.is_valid():
		_tip_hide_tween.kill()
	_tip_show_tween = null
	_tip_hide_tween = null
	_tip_kill_page_tweens()


func _tip_kill_page_tweens() -> void:
	for t: Tween in _tip_page_tweens:
		if t and t.is_valid():
			t.kill()
	_tip_page_tweens.clear()
