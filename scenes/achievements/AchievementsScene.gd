## AchievementsScene : Control
## 成就/奖励屏幕，包含音乐和场景画廊的子菜单。

extends Control

signal back_requested()
signal gallery_requested(gallery: String)

const REST_X: float = 20.0
const FOCUS_X: float = -30.0
const FOCUS_DUR: float = 0.2

var _disabled: bool = false
var _focus_idx: int = 0
var _item_nodes: Array[Control] = []
var _item_data: Array[Dictionary] = []
var _font_tcm: Font
var _font_zh_title: Font
var _font_zh_body: Font
var _font_en_body: Font
var _focus_tween: Tween = null
var _entry_complete: bool = false
var _menu_active: bool = false

@onready var _title_label: Label = %TitleLabel
@onready var _items_container: VBoxContainer = %ItemsContainer
@onready var _back_button: Control = %BackButton


func _ready() -> void:
	_title_label.text = "Achievements"
	_font_tcm = load(GameManager.FONT_TCM)
	_font_zh_title = load(GameManager.FONT_ZH_TITLE)
	_font_zh_body = load(GameManager.FONT_ZH_BODY)
	_font_en_body = load(GameManager.FONT_EN_BODY)
	_title_label.add_theme_font_size_override("font_size", 72)
	if _font_tcm: _title_label.add_theme_font_override("font", _font_tcm)

	_item_data = [
		{"en": "Achievements", "zh": "成就", "desc_zh": "已经获得的全部游戏成就", "desc_en": "All game achievements earned.", "prog": 75},
		{"en": "Music", "zh": "音乐", "desc_zh": "游戏中出现的音乐", "desc_en": "Music appearing in the game."},
		{"en": "Scenes", "zh": "场景", "desc_zh": "游戏中出现的场景", "desc_en": "Scenes appearing in the game."},
	]
	for i: int in range(_item_data.size()):
		var row: Control = _create_item_row(i, _item_data[i])
		_items_container.add_child(row)
		_item_nodes.append(row)

	_setup_back_button()

	# ── 入场动画的初始状态 ──
	_title_label.modulate.a = 0.0
	_back_button.modulate.a = 0.0
	for w: Control in _item_nodes:
		w.modulate.a = 1.0
		w.position.x = REST_X

	await get_tree().process_frame
	await _play_entry()


func _create_item_row(index: int, data: Dictionary) -> Control:
	var container := Control.new()
	container.name = "Item_" + str(index)
	container.custom_minimum_size = Vector2(0, 110)
	container.mouse_filter = Control.MOUSE_FILTER_STOP

	# 扫描背景 — 获得焦点时从左边缘扩展的白色填充
	var sweep := ColorRect.new()
	sweep.name = "Sweep"
	sweep.color = Color.WHITE
	sweep.set_anchors_preset(Control.PRESET_FULL_RECT)
	sweep.pivot_offset = Vector2(0, 0)
	sweep.scale = Vector2(0, 1)
	sweep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(sweep)

	# 左侧活动指示器条
	var left_bar := ColorRect.new()
	left_bar.name = "LeftBar"
	left_bar.color = Color.BLACK
	left_bar.size = Vector2(2, 110)
	left_bar.modulate.a = 0.0
	left_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(left_bar)

	# 内容 vbox
	var vbox := VBoxContainer.new()
	vbox.name = "Content"
	vbox.position = Vector2(24, 16)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var sub_label := Label.new()
	sub_label.name = "SubLabel"
	sub_label.text = "" if GameManager.is_locale("en") else tr(data.zh)
	sub_label.visible = not GameManager.is_locale("en")
	sub_label.add_theme_font_size_override("font_size", 16)
	if _font_zh_title: sub_label.add_theme_font_override("font", _font_zh_title)
	sub_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(sub_label)

	var title_label := Label.new()
	title_label.name = "TitleLabel"
	title_label.text = data.en
	title_label.add_theme_font_size_override("font_size", 34)
	if _font_tcm: title_label.add_theme_font_override("font", _font_tcm)
	title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(title_label)

	var desc_label := Label.new()
	desc_label.name = "DescLabel"
	desc_label.text = tr(data.desc_zh)
	desc_label.add_theme_font_size_override("font_size", 11)
	desc_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(desc_label)

	container.add_child(vbox)

	# 进度条 — 可见轨道 + 填充，获得焦点时颜色动画
	if "prog" in data:
		var prog_track := ColorRect.new()
		prog_track.name = "ProgTrack"
		prog_track.color = Color(1, 1, 1, 0.15)
		prog_track.size = Vector2(400, 4)
		prog_track.position = Vector2(24, 100)
		prog_track.mouse_filter = Control.MOUSE_FILTER_IGNORE
		container.add_child(prog_track)

		var prog_fill := ColorRect.new()
		prog_fill.name = "ProgFill"
		prog_fill.color = Color(1, 1, 1, 0.5)
		prog_fill.size = Vector2(400 * data.prog / 100.0, 4)
		prog_fill.position = Vector2(24, 100)
		prog_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		container.add_child(prog_fill)
		container.set_meta("prog_track", prog_track)
		container.set_meta("prog_fill", prog_fill)

		# 百分比标签 — 右对齐，TCM 字体
		var prog_pct := Label.new()
		prog_pct.name = "ProgPct"
		prog_pct.text = str(data.prog) + "%"
		prog_pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		prog_pct.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		prog_pct.add_theme_font_size_override("font_size", 28)
		if _font_tcm: prog_pct.add_theme_font_override("font", _font_tcm)
		prog_pct.mouse_filter = Control.MOUSE_FILTER_IGNORE
		prog_pct.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
		prog_pct.offset_left = -120.0
		prog_pct.offset_right = -24.0
		prog_pct.offset_top = 16.0
		prog_pct.offset_bottom = 50.0
		container.add_child(prog_pct)
		container.set_meta("prog_pct", prog_pct)

	container.mouse_entered.connect(_on_hover.bind(index))
	container.gui_input.connect(_on_item_clicked.bind(index))
	container.set_meta("sweep", sweep)
	container.set_meta("left_bar", left_bar)
	container.set_meta("title_label", title_label)
	container.set_meta("sub_label", sub_label)
	container.set_meta("desc_label", desc_label)

	return container


# ═══════════════════════════════════════════════════════════════
# 入场动画 — 标题 + 返回按钮淡入（项目立即出现）
# ═══════════════════════════════════════════════════════════════

func _play_entry() -> void:
	# 动画开始前的短暂暂停
	await get_tree().create_timer(0.15).timeout

	# 阶段 1 — 标题淡入
	var t_title := create_tween()
	t_title.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	t_title.tween_property(_title_label, "modulate:a", 1.0, 0.35)

	# 阶段 2 — 返回按钮淡入
	var t_back := create_tween()
	t_back.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	t_back.tween_property(_back_button, "modulate:a", 1.0, 0.25)

	_menu_active = true
	await get_tree().process_frame
	_apply_focus()
	_entry_complete = true


# ═══════════════════════════════════════════════════════════════
# 焦点 — 统一并行 tween（MainMenu 风格）
# ═══════════════════════════════════════════════════════════════

func _apply_focus() -> void:
	if _focus_tween and _focus_tween.is_valid():
		_focus_tween.kill()

	_focus_tween = create_tween().set_parallel(true)
	_focus_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	for i: int in range(_item_nodes.size()):
		var row: Control = _item_nodes[i]
		var foc: bool = i == _focus_idx and _menu_active
		var active_elsewhere: bool = _menu_active and i != _focus_idx

		var sweep: ColorRect = row.get_meta("sweep")
		var left_bar: ColorRect = row.get_meta("left_bar")
		var title_label: Label = row.get_meta("title_label")
		var sub_label: Label = row.get_meta("sub_label")
		var desc_label: Label = row.get_meta("desc_label")

		# 位置 + 变暗
		_focus_tween.tween_property(row, "position:x", FOCUS_X if foc else REST_X, FOCUS_DUR)
		_focus_tween.tween_property(row, "modulate:a", 0.55 if active_elsewhere else 1.0, FOCUS_DUR)

		# 扫描 — 白色填充从左侧扩展
		_focus_tween.tween_property(sweep, "scale:x", 1.0 if foc else 0.0, FOCUS_DUR)

		# 左侧指示器条
		_focus_tween.tween_property(left_bar, "modulate:a", 1.0 if foc else 0.0, FOCUS_DUR)

		# 文本颜色 — self_modulate 在白色扫描背景上从白色过渡到黑色
		_focus_tween.tween_property(title_label, "self_modulate", Color.BLACK if foc else Color.WHITE, FOCUS_DUR)
		_focus_tween.tween_property(sub_label, "self_modulate", Color(0, 0, 0, 0.5) if foc else Color.WHITE, FOCUS_DUR)
		_focus_tween.tween_property(desc_label, "self_modulate", Color(0, 0, 0, 0.4) if foc else Color(1, 1, 1, 0.4), FOCUS_DUR)

		# 进度条 — 轨道和填充在明暗之间切换以形成对比
		if row.has_meta("prog_fill"):
			var prog_track: ColorRect = row.get_meta("prog_track")
			var prog_fill: ColorRect = row.get_meta("prog_fill")
			_focus_tween.tween_property(prog_track, "color", Color(0, 0, 0, 0.12) if foc else Color(1, 1, 1, 0.15), FOCUS_DUR)
			_focus_tween.tween_property(prog_fill, "color", Color.BLACK if foc else Color(1, 1, 1, 0.5), FOCUS_DUR)
			if row.has_meta("prog_pct"):
				var prog_pct: Label = row.get_meta("prog_pct")
				_focus_tween.tween_property(prog_pct, "self_modulate", Color.BLACK if foc else Color.WHITE, FOCUS_DUR)


# ── 交互 ────────────────────────────────────────────

func _on_hover(index: int) -> void:
	if _disabled or not _menu_active or _focus_idx == index: return
	_focus_idx = index; _apply_focus(); _play_click()


func _on_item_clicked(event: InputEvent, index: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_activate_item(index)


func _activate_item(index: int) -> void:
	if _disabled:
		return
	var data: Dictionary = _item_data[index]
	if data.has("prog"):
		return
	_play_click()
	match index:
		1: gallery_requested.emit("music")
		2: gallery_requested.emit("scene")


# ── 返回按钮栏 ────────────────────────────────────────

func _setup_back_button() -> void:
	_back_button.mouse_filter = Control.MOUSE_FILTER_STOP
	_back_button.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_back_button.offset_top = -96.0
	_back_button.offset_bottom = 0.0

	var bar_bg := ColorRect.new()
	bar_bg.name = "BarBg"
	bar_bg.color = Color(0, 0, 0, 0.6)
	bar_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_back_button.add_child(bar_bg)

	var border := ColorRect.new()
	border.name = "Border"
	border.color = Color(1, 1, 1, 0.05)
	border.set_anchors_preset(Control.PRESET_TOP_WIDE)
	border.offset_bottom = 1.0
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_back_button.add_child(border)

	var esc_box := ColorRect.new()
	esc_box.name = "EscBox"
	esc_box.color = Color.WHITE
	esc_box.size = Vector2(48, 48)
	esc_box.position = Vector2(24, 24)
	esc_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_back_button.add_child(esc_box)

	var esc_label := Label.new()
	esc_label.name = "EscLabel"
	esc_label.text = "ESC"
	esc_label.position = Vector2(24, 24)
	esc_label.size = Vector2(48, 48)
	esc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	esc_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	esc_label.add_theme_color_override("font_color", Color.BLACK)
	esc_label.add_theme_font_size_override("font_size", 14)
	esc_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _font_tcm: esc_label.add_theme_font_override("font", _font_tcm)
	_back_button.add_child(esc_label)

	var back_label := Label.new()
	back_label.name = "BackLabel"
	back_label.text = tr("返回")
	back_label.position = Vector2(88, 28)
	back_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.8))
	back_label.add_theme_font_size_override("font_size", 24)
	back_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_back_button.add_child(back_label)

	if not GameManager.is_locale("en"):
		var sub_label := Label.new()
		sub_label.name = "SubLabel"
		sub_label.text = tr("取消当前操作")
		sub_label.position = Vector2(88, 58)
		sub_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.2))
		sub_label.add_theme_font_size_override("font_size", 10)
		sub_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_back_button.add_child(sub_label)

	_back_button.gui_input.connect(_on_back_bar_clicked)
	_back_button.mouse_entered.connect(_on_back_bar_hovered.bind(true))
	_back_button.mouse_exited.connect(_on_back_bar_hovered.bind(false))
	_back_button.set_meta("esc_box", esc_box)
	_back_button.set_meta("esc_label", esc_label)


func _on_back_bar_clicked(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_play_click(); back_requested.emit()


func _on_back_bar_hovered(hovered: bool) -> void:
	var esc_box: ColorRect = _back_button.get_meta("esc_box")
	var esc_label: Label = _back_button.get_meta("esc_label")
	if esc_box: esc_box.color = Color.BLACK if hovered else Color.WHITE
	if esc_label: esc_label.add_theme_color_override("font_color", Color.WHITE if hovered else Color.BLACK)


func _play_click() -> void:
	AudioManager.play_click()


# ── SceneManager 生命周期 ──────────────────────────────────

func _on_exit() -> void:
	_disabled = true
	_menu_active = false
	if _focus_tween and _focus_tween.is_valid():
		_focus_tween.kill()


func _on_enter() -> void:
	_disabled = false
	if _entry_complete:
		await get_tree().process_frame
		_menu_active = true
		_apply_focus()


func _input(event: InputEvent) -> void:
	if _disabled or not _menu_active or not event.is_pressed(): return
	if event.is_action_pressed("ui_up"):
		_focus_idx = max(0, _focus_idx - 1); _apply_focus(); _play_click()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_down"):
		_focus_idx = min(_item_nodes.size() - 1, _focus_idx + 1); _apply_focus(); _play_click()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		_activate_item(_focus_idx)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel"):
		back_requested.emit(); get_viewport().set_input_as_handled()


func set_disabled(val: bool) -> void:
	_disabled = val
