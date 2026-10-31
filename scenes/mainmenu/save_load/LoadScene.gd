## LoadScene : Control
## 存档/读档屏幕。20个存档槽，2列网格布局。
##
## 焦点动画策略：
##   1. fill.color 从暗→白渐变（0.4秒 QUINT）— 这是唯一的背景动画。
##   2. 文本颜色在短暂延迟后通过 add_theme_color_override 切换
##      （0.12秒），这样白色扫过效果在文本变暗之前已经覆盖文本区域。
##      失去焦点时，文本颜色立即切换回来。
##   3. 装饰条（右侧+底部，2像素黑色）即时显示/隐藏。
##   4. 卡片缩放从 1.0→1.02。
extends Control

## 统一标题栏装饰器。用 preload 常量而不是全局类名：新增脚本的 class_name 需要
## 编辑器扫描一次才进全局类缓存，preload 不依赖它（编辑器里也照样有补全）。
const TITLE_BAR = preload("res://scenes/ui/SceneTitleBar.gd")

signal back_requested()
signal save_selected(save: SaveData)

var _slots: Array = []
var _focus_idx: int = 0
var _disabled: bool = false


const SLOT_W: float = 540.0
const SLOT_H: float = 160.0
const GRID_COLS: int = 2
const GRID_GAP: float = 24.0

@onready var _title_label: Label = %TitleLabel
@onready var _slots_grid: GridContainer = %SlotsGrid
@onready var _slot_scroll: ScrollContainer = $SlotScroll


func _ready() -> void:
	_setup()
	_animate_enter()


func setup(_bg: String = "") -> void:
	pass


func _setup() -> void:


	TITLE_BAR.apply(_title_label, "Archive", tr("读档"),
		GameManager.font_tcm, GameManager.font_zh_title, 1232.0)
	
	_slots_grid.add_theme_constant_override("h_separation", int(GRID_GAP))
	_slots_grid.add_theme_constant_override("v_separation", int(GRID_GAP))
	_slots_grid.columns = GRID_COLS
	_slots_grid.size_flags_horizontal = Control.SIZE_FILL
	_slots_grid.size_flags_vertical = Control.SIZE_FILL

	_slots = GameManager.get_save_slots()
	_create_slot_nodes()
	_setup_hint_bar()


func _create_slot_nodes() -> void:
	for i: int in range(GameManager.MAX_SLOTS):
		var c: Control = _make_card(i)
		_slots_grid.add_child(c)
	_update_focus()


func _make_card(idx: int) -> Control:
	var save: SaveData = _slots[idx] if idx < _slots.size() else null

	var card := Control.new()
	card.name = "Slot_" + str(idx)
	card.custom_minimum_size = Vector2(SLOT_W, SLOT_H)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.pivot_offset = Vector2(SLOT_W / 2.0, SLOT_H / 2.0)

	# ── 图层 0：背景填充 ──
	var fill := ColorRect.new()
	fill.name = "Fill"
	fill.color = Color(0.15, 0.15, 0.15, 0.8)
	fill.set_anchors_preset(Control.PRESET_FULL_RECT)
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(fill)

	# ── 图层 2：水印编号（52px，左上角）──
	var wm := Label.new()
	wm.name = "WM"
	wm.text = "%02d" % (idx + 1)
	wm.position = Vector2(16, 8)
	wm.add_theme_font_size_override("font_size", 52)
	wm.add_theme_color_override("font_color", Color(1, 1, 1, 0.2))
	if GameManager.font_tcm: wm.add_theme_font_override("font", GameManager.font_tcm)
	wm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(wm)

	# ── 图层 2：现实日期（10px，右上角）──
	var dt := Label.new()
	dt.name = "DT"
	dt.text = save.date if save else "---- / -- / --"
	dt.anchor_right = 1.0
	dt.offset_left = -260.0
	dt.offset_right = -16.0
	dt.offset_top = 14.0
	dt.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	dt.add_theme_font_size_override("font_size", 10)
	dt.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
	if GameManager.font_en_body: dt.add_theme_font_override("font", GameManager.font_en_body)
	dt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(dt)

	# ── 图层 2：标题 = 游戏内时间（22px，y=74；数字用 TCM，中文用衬线）──
	# 右上角只留现实日期，游戏内时间挪到标题位，所以这里取代了原来的章节名。
	var tt := RichTextLabel.new()
	tt.name = "TT"
	tt.position = Vector2(16, 74)
	tt.size = Vector2(SLOT_W - 32, 28)
	tt.clip_contents = true
	tt.bbcode_enabled = true
	tt.scroll_active = false
	tt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tt.add_theme_font_size_override("normal_font_size", 22)
	tt.add_theme_color_override("default_color", Color(1, 1, 1, 0.92))
	if GameManager.font_zh_title:
		tt.add_theme_font_override("normal_font", GameManager.font_zh_title)
	if save:
		var time_text: String = save.game_date_text()
		if time_text.is_empty():
			time_text = save.title  # 老存档没有日期记录 → 回退章节名
		tt.text = GameManager.wrap_digit_font(time_text, GameManager.FONT_TCM)
	else:
		tt.text = tr("空位")
	card.add_child(tt)

	# ── 图层 2：对话行（13px，y=104）──
	var dialogue_label := Label.new()
	dialogue_label.name = "Dialogue"
	dialogue_label.position = Vector2(16, 104)
	dialogue_label.size = Vector2(SLOT_W - 32, 20)
	dialogue_label.clip_text = true
	dialogue_label.text = save.desc if save else ""
	dialogue_label.add_theme_font_size_override("font_size", 13)
	dialogue_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.65))
	@warning_ignore("static_called_on_instance")
	var dlg_font: Font = GameManager.select_font(dialogue_label.text, GameManager.font_zh_body, GameManager.font_en_body)
	if dlg_font: dialogue_label.add_theme_font_override("font", dlg_font)
	dialogue_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(dialogue_label)

	# ── 图层 2：详情行（10px，y=130）—— 游戏内地点 // 玩家名 ──
	var dl := Label.new()
	dl.name = "DL"
	dl.position = Vector2(16, 130)
	if save:
		var loc: String = save.location_text()
		dl.text = (loc if not loc.is_empty() else "—") + " // " + save.player_name
	else:
		dl.text = tr("点击存档")
	dl.add_theme_font_size_override("font_size", 10)
	dl.add_theme_color_override("font_color", Color(1, 1, 1, 0.45))
	@warning_ignore("static_called_on_instance")
	var dl_font: Font = GameManager.select_font(dl.text, GameManager.font_zh_body, GameManager.font_en_body)
	if dl_font: dl.add_theme_font_override("font", dl_font)
	dl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(dl)

	# ── 元数据 ──
	card.set_meta("fill", fill)
	card.set_meta("wm", wm)
	card.set_meta("dt", dt)
	card.set_meta("tt", tt)
	card.set_meta("dl", dl)

	card.mouse_entered.connect(_on_hover.bind(idx))
	card.gui_input.connect(_on_click.bind(idx))
	return card
func _update_focus(p_scroll: bool = false) -> void:
	for i: int in range(_slots_grid.get_child_count()):
		var card: Control = _slots_grid.get_child(i)
		var on: bool = (i == _focus_idx)
		_animate_card(card, on)

		# 自动滚动仅用于键盘导航 — 鼠标悬停不应使视图跳转
		if on and p_scroll and _slot_scroll:
			_slot_scroll.ensure_control_visible(card)


## 将单个卡片动画到聚焦/非聚焦状态。
## 每个卡片通过元数据拥有自己的 tween，因此终止一个卡片的
## tween 不会中断另一个卡片的动画。
func _animate_card(card: Control, on: bool) -> void:
	var fill: ColorRect = card.get_meta("fill")

	# 终止此特定卡片上任何正在进行的 tween
	if card.has_meta("focus_tween"):
		var old: Tween = card.get_meta("focus_tween")
		if old and old.is_valid():
			old.kill()

	var tw := create_tween().set_parallel(true)
	tw.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)

	var target: Color = Color(0.35, 0.35, 0.35, 0.85) if on else Color(0.15, 0.15, 0.15, 0.8)
	tw.tween_property(fill, "color", target, 0.2)

	tw.tween_property(card, "scale", Vector2(1.02, 1.02) if on else Vector2(1, 1), 0.2)

	card.set_meta("focus_tween", tw)

func _on_hover(idx: int) -> void:
	if _disabled or _focus_idx == idx:
		return
	_focus_idx = idx
	_update_focus()
	_play_click()


func _on_click(event: InputEvent, idx: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_confirm(idx)


func _confirm(idx: int) -> void:
	_play_click()
	var sv: SaveData = _slots[idx] if idx < _slots.size() else null
	if sv:
		save_selected.emit(sv)


var _back_bar: BackBar = null


func _setup_hint_bar() -> void:
	_back_bar = BackBar.attach(self)


func _play_click() -> void:
	AudioManager.play_click()


# ── 进入动画 ────────────────────────────────────────

func _animate_enter() -> void:
	@warning_ignore("static_called_on_instance")
	GameManager.animate_scene_enter(self)
	for i: int in range(_slots_grid.get_child_count()):
		var c: Control = _slots_grid.get_child(i)
		c.modulate.a = 0.0
		var st := create_tween()
		st.tween_interval(i * 0.015)
		st.tween_property(c, "modulate:a", 1.0, 0.25).set_ease(Tween.EASE_OUT)


# ── SceneManager 生命周期 ──────────────────────────────────

func _on_exit() -> void:
	_disabled = true


func _on_enter() -> void:
	_disabled = false
	_refresh_translations()
	_update_focus()


func _refresh_translations() -> void:
	TITLE_BAR.apply(_title_label, "Archive", tr("读档"),
		GameManager.font_tcm, GameManager.font_zh_title, 1232.0)
	for i: int in range(_slots_grid.get_child_count()):
		var card: Control = _slots_grid.get_child(i) as Control
		var sv: SaveData = _slots[i] if i < _slots.size() else null
		if not sv:
			var tt: RichTextLabel = card.get_meta("tt")
			var dl: Label = card.get_meta("dl")
			tt.text = tr("空位")
			dl.text = tr("没有存档")
			@warning_ignore("static_called_on_instance")
			var tt_font: Font = GameManager.select_font(tt.text, GameManager.font_zh_title, GameManager.font_tcm)
			if tt_font: tt.add_theme_font_override("normal_font", tt_font)
			@warning_ignore("static_called_on_instance")
			var dl_font: Font = GameManager.select_font(dl.text, GameManager.font_zh_body, GameManager.font_en_body)
			if dl_font: dl.add_theme_font_override("font", dl_font)
	if _back_bar:
		_back_bar.set_language()


# ── 输入处理 ──────────────────────────────────────────────────

func _input(event: InputEvent) -> void:
	if _disabled or not event.is_pressed():
		return
	if event.is_action_pressed("ui_up"):
		_focus_idx = max(0, _focus_idx - GRID_COLS)
		_update_focus(true); _play_click()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_down"):
		_focus_idx = min(GameManager.MAX_SLOTS - 1, _focus_idx + GRID_COLS)
		_update_focus(true); _play_click()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_left"):
		_focus_idx = max(0, _focus_idx - 1)
		_update_focus(true); _play_click()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_right"):
		_focus_idx = min(GameManager.MAX_SLOTS - 1, _focus_idx + 1)
		_update_focus(true); _play_click()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel"):
		back_requested.emit()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		_confirm(_focus_idx)
		get_viewport().set_input_as_handled()

	if event is InputEventMouseButton and _slot_scroll:
		var bar: ScrollBar = _slot_scroll.get_v_scroll_bar()
		var target: float = bar.value
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			target = max(bar.min_value, bar.value - 200.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			target = min(bar.max_value, bar.value + 200.0)
		if target != bar.value:
			var tw := create_tween()
			tw.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
			tw.tween_property(_slot_scroll, "scroll_vertical", target, 0.35)


func set_disabled(v: bool) -> void:
	_disabled = v
