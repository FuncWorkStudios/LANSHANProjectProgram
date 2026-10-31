## SettingsScene : Control
## 设置/配置屏幕 — 左侧分类导航（SettingsCategoryItem，OptionRow 语言：白扫 + 文字反黑 +
## 内容右移 + 未选中调暗）+ 右侧纯设置列表（SettingsRow 低调焦点：白带 + 左竖条 + 数值提亮）。
## 数据驱动 + 组件化（SettingsCategoryItem / SettingsSliderRow / SettingsCycleRow）；
## 切语言不重建行节点，只 refresh。栅格见 SettingsScene.tscn：
## 标题 64、卡片 64..1216 / 152..624（底部与 BackBar 顶齐平）、左栏 320、行内边距 32。
## 焦点模型：hover/键盘只改 _focus_idx，随后对**每一行**调 apply_focus_state（全量刷新，
## 与 MainMenuList 同法），不让场景直接改行内文字色 —— 否则会和行的 tween 抢同一属性。
extends Control

## 统一标题栏装饰器。用 preload 常量而不是全局类名：新增脚本的 class_name 需要
## 编辑器扫描一次才进全局类缓存，preload 不依赖它（编辑器里也照样有补全）。
const TITLE_BAR = preload("res://scenes/ui/SceneTitleBar.gd")

# ── Signals ────────────────────────────────────────────

signal back_requested()

# ── Constants ──────────────────────────────────────────

const RAIL_INTRO_STAGGER: float = 0.05
const ROW_INTRO_STAGGER: float = 0.04
## 标题栏细线宽度：标题左缘 24 → 右边距 24，与读档 / 历程等子页面完全一致。
const TITLE_RULE_WIDTH: float = 1232.0

# ── State ──────────────────────────────────────────────

var _focus_idx: int = 0
var _disabled: bool = false
var _active_category: int = 0
## 入场是否已完成（切分类的错峰入场只在入场之后播）
var _entered: bool = false
var _categories: Array[Dictionary] = []
var _settings: AppSettings
var _row_nodes: Array[SettingsRow] = []
var _row_id_to_index: Dictionary = {}
var _rail_items: Array[SettingsCategoryItem] = []
var _back_bar: BackBar = null

# ── Onready ────────────────────────────────────────────

@onready var _title_label: Label = %TitleLabel
@onready var _configs_container: VBoxContainer = %ConfigsContainer
@onready var _sidebar_list: VBoxContainer = %SidebarList


func _ready() -> void:
	_settings = GameManager.get_settings()
	_build_categories()
	_build_sidebar()
	_show_category(0)
	_setup_back_button()


# ── 数据 ────────────────────────────────────────────────

func _build_categories() -> void:
	_categories = [
		{
			"id": "AUDIO", "label": "AUDIO", "zh": tr("音频"), "desc": tr("控制音频输出与音量大小"),
			"rows": [
				{"id": "master", "zh": tr("主音量"), "is_slider": true, "setting_key": "master_volume"},
				{"id": "bgm", "zh": tr("背景音乐音量"), "is_slider": true, "setting_key": "bgm_volume"},
				{"id": "ambience", "zh": tr("环境音音量"), "is_slider": true, "setting_key": "ambience_volume"},
				{"id": "sfx", "zh": tr("音效音量"), "is_slider": true, "setting_key": "sfx_volume"},
			]
		},
		{
			"id": "GAMEPLAY", "label": "GAMEPLAY", "zh": tr("游戏"), "desc": tr("控制剧情推进与交互行为"),
			"rows": [
				{"id": "text_speed", "zh": tr("文本滚动速度"), "is_slider": false,
					"setting_key": "text_speed",
					"options": ["slow", "normal", "fast"],
					"option_labels": {"slow": "慢", "normal": "中", "fast": "快"}},
				{"id": "auto_play", "zh": tr("自动剧情"), "is_slider": false,
					"setting_key": "auto_play",
					"options": [false, true],
					"option_labels": {"false": "关闭", "true": "开启"}},
			]
		},
		{
			"id": "SYSTEM", "label": "SYSTEM", "zh": tr("系统"), "desc": tr("显示与性能相关设置"),
			"rows": [
				{"id": "language", "zh": tr("界面语言"), "is_slider": false,
					"setting_key": "language",
					"options": ["ZH", "EN"],
					"option_labels": {"ZH": "简体中文", "EN": "ENGLISH"}, "is_language": true},
				{"id": "display_mode", "zh": tr("显示模式"), "is_slider": false,
					"setting_key": "display_mode",
					"options": ["windowed", "fullscreen"],
					"option_labels": {"windowed": "窗口", "fullscreen": "全屏"}, "has_display_side_effect": true},
				{"id": "quality", "zh": tr("性能模式"), "is_slider": false,
					"setting_key": "quality",
					"options": ["low", "high"],
					"option_labels": {"low": "开启", "high": "关闭"}},
				{"id": "framerate", "zh": tr("帧率"), "is_slider": false,
					"setting_key": "framerate",
					"options": ["fps30", "fps60", "fps120", "fps240", "vsync", "unlimited"],
					"option_labels": {"fps30": "30 FPS", "fps60": "60 FPS", "fps120": "120 FPS",
						"fps240": "240 FPS", "vsync": "垂直同步", "unlimited": "帧率无上限"}},
			]
		},
	]

	TITLE_BAR.apply(_title_label, "Config", tr("设置"),
		GameManager.font_tcm, GameManager.font_zh_title, TITLE_RULE_WIDTH)


# ── 左栏 ────────────────────────────────────────────────

func _build_sidebar() -> void:
	_rail_items.clear()
	var is_en: bool = GameManager.is_locale("en")
	for i: int in range(_categories.size()):
		var cat: Dictionary = _categories[i]
		var item: SettingsCategoryItem = SettingsCategoryItem.new()
		item.setup(i, str(cat["label"]), str(cat["zh"]),
			GameManager.font_tcm, GameManager.font_zh_title, not is_en)
		item.activated.connect(_on_rail_activated)
		# 首帧就隐藏，等容器排序完再 play_intro（否则会先闪一帧）
		item.modulate.a = 0.0
		_sidebar_list.add_child(item)
		_rail_items.append(item)


## 左栏全量状态刷新（每个分类项自己先杀后建）。
func _update_rail_state() -> void:
	for i: int in range(_rail_items.size()):
		_rail_items[i].set_active(i == _active_category)


func _update_rail_texts() -> void:
	var is_en: bool = GameManager.is_locale("en")
	for i: int in range(_rail_items.size()):
		if i >= _categories.size():
			break
		var cat: Dictionary = _categories[i]
		_rail_items[i].refresh_locale(str(cat["label"]), str(cat["zh"]), not is_en)


func _on_rail_activated(p_index: int) -> void:
	if _disabled or p_index == _active_category:
		return
	_play_click()
	_show_category(p_index)


# ── 分类切换（动态实例化）────────────────────────────────

func _show_category(p_index: int) -> void:
	_active_category = p_index
	_clear_panel()
	_populate_panel()
	_focus_idx = 0
	_update_row_focus()
	_update_rail_state()
	if _entered:
		_play_rows_intro()


func _clear_panel() -> void:
	# 先 remove_child 再 queue_free：否则旧行会多活一帧，和新行一起参与 VBox 排序
	for child: Node in _configs_container.get_children():
		if child is SettingsRow:
			(child as SettingsRow).flush_pending()
		_configs_container.remove_child(child)
		child.queue_free()
	_row_nodes.clear()
	_row_id_to_index.clear()


func _populate_panel() -> void:
	var cat: Dictionary = _categories[_active_category]
	var rows: Array = cat["rows"]
	for row_data: Dictionary in rows:
		var row: SettingsRow = _create_config_row(row_data)
		row.prepare_intro()
		_configs_container.add_child(row)
		_row_nodes.append(row)
		_row_id_to_index[str(row_data["id"])] = _row_nodes.size() - 1


func _create_config_row(cfg: Dictionary) -> SettingsRow:
	var row_key: String = str(cfg["id"])
	var label_text: String = str(cfg["zh"])

	if bool(cfg.get("is_slider", false)):
		var slider_row: SettingsSliderRow = SettingsSliderRow.new()
		var initial_value: float = _settings.get_prop(str(cfg["setting_key"]))
		slider_row.configure(row_key, label_text, initial_value, str(cfg["setting_key"]))
		slider_row.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		slider_row.value_changed.connect(_on_slider_value_changed)
		slider_row.value_committed.connect(_on_slider_value_committed)
		slider_row.hovered.connect(_on_row_hovered_by_id)
		return slider_row

	var cycle_row: SettingsCycleRow = SettingsCycleRow.new()
	cycle_row.configure(row_key, label_text, _get_option_display(row_key))
	cycle_row.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	cycle_row.stepped.connect(_on_step_option)
	cycle_row.hovered.connect(_on_row_hovered_by_id)
	return cycle_row


# ── 数据查找辅助 ──────────────────────────────────────────

func _find_row_config(p_row_id: String) -> Dictionary:
	for cat: Dictionary in _categories:
		var rows: Array = cat["rows"]
		for row: Dictionary in rows:
			if str(row["id"]) == p_row_id:
				return row
	return {}


func _get_current_rows() -> Array[Dictionary]:
	if _active_category < 0 or _active_category >= _categories.size():
		return []
	var rows: Array[Dictionary] = []
	rows.assign(_categories[_active_category]["rows"])
	return rows


func _find_row_config_by_index(p_index: int) -> Dictionary:
	var rows: Array[Dictionary] = _get_current_rows()
	if p_index < 0 or p_index >= rows.size():
		return {}
	return rows[p_index]


# ── 值读取 ────────────────────────────────────────────────

func _get_option_display(p_row_id: String) -> String:
	var cfg: Dictionary = _find_row_config(p_row_id)
	if cfg.is_empty():
		return ""

	if bool(cfg.get("is_language", false)):
		var loc: String = GameManager.get_locale()
		var locale_label: String = str(GameManager.LOCALE_LABELS.get(loc, "ENGLISH"))
		return tr(locale_label)

	var current_value: Variant = _settings.get_prop(str(cfg["setting_key"]))
	var labels: Dictionary = cfg.get("option_labels", {})
	var lookup_key: String = str(current_value).to_lower()
	var raw: String = str(labels.get(lookup_key, ""))
	if raw.is_empty():
		raw = str(labels.get(current_value, str(current_value)))
	return tr(raw)


# ── 信号处理 ──────────────────────────────────────────────

## 拖动中：只写内存 + 立刻改音量（不落盘）。
func _on_slider_value_changed(value: float, p_row_id: String) -> void:
	var cfg: Dictionary = _find_row_config(p_row_id)
	if cfg.is_empty():
		return
	GameManager.set_setting(str(cfg["setting_key"]), value, false)
	AudioManager.apply_volumes()


## 停手/键盘步进后：落盘一次（见 GameManager.set_setting 的 p_save）。
func _on_slider_value_committed(value: float, p_row_id: String) -> void:
	var cfg: Dictionary = _find_row_config(p_row_id)
	if cfg.is_empty():
		return
	GameManager.set_setting(str(cfg["setting_key"]), value, true)


func _on_step_option(p_row_id: String, direction: int) -> void:
	_play_click()

	var cfg: Dictionary = _find_row_config(p_row_id)
	if cfg.is_empty():
		return

	var options: Array = cfg["options"]
	var current_value: Variant = _settings.get_prop(str(cfg["setting_key"]))
	var current_index: int = options.find(current_value)
	var next_value: Variant = options[(current_index + direction + options.size()) % options.size()]

	GameManager.set_setting(str(cfg["setting_key"]), next_value)
	_settings = GameManager.get_settings()

	if bool(cfg.get("has_display_side_effect", false)):
		_apply_display_mode(str(next_value))
	elif bool(cfg.get("is_language", false)):
		_on_language_changed()

	_update_display_values()


func _apply_display_mode(p_mode: String) -> void:
	if p_mode == "fullscreen":
		if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_FULLSCREEN:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)


func _on_row_hovered_by_id(p_row_id: String) -> void:
	var idx: int = int(_row_id_to_index.get(p_row_id, -1))
	if idx >= 0:
		_on_row_hovered(idx)


# ── 语言切换：不重建节点，只 refresh ─────────────────────

func _on_language_changed() -> void:
	_build_categories()
	_update_rail_texts()
	_update_row_labels()
	_update_display_values()
	if _back_bar:
		_back_bar.set_language()


func _update_row_labels() -> void:
	var rows: Array[Dictionary] = _get_current_rows()
	for i: int in range(_row_nodes.size()):
		if i >= rows.size():
			break
		_row_nodes[i].refresh_locale(rows[i])


func _update_display_values() -> void:
	var rows: Array[Dictionary] = _get_current_rows()
	for i: int in range(_row_nodes.size()):
		if i >= rows.size():
			break
		_row_nodes[i].refresh_value(_settings, _get_option_display(str(rows[i]["id"])))


# ── 焦点与导航 ────────────────────────────────────────────

## 全量行焦点刷新（OptionRow / MainMenuList 同法）：每行自己先杀后建，
## 全量而非「上一行 + 新行」保证快速划过时所有行都收敛到终值。
func _update_row_focus() -> void:
	for i: int in range(_row_nodes.size()):
		_row_nodes[i].apply_focus_state(i == _focus_idx)


func _on_row_hovered(p_index: int) -> void:
	if _disabled or _focus_idx == p_index:
		return
	_focus_idx = p_index
	_update_row_focus()
	_play_click()


func _setup_back_button() -> void:
	_back_bar = BackBar.attach(self)


func _play_click() -> void:
	AudioManager.play_click()


# ── 入场动画 ──────────────────────────────────────────────

## 首次进入：标题淡入 → 等一帧让 VBox 完成排序 → 左栏 / 右栏错峰滑入。
## （行与分类项的 position.x 会被容器排序覆写，必须在排序之后再摆初始位。）
func _animate_first_entrance() -> void:
	_title_label.modulate.a = 0.0
	var title_tween: Tween = create_tween()
	title_tween.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	title_tween.tween_property(_title_label, "modulate:a", 1.0, 0.4)

	await get_tree().process_frame
	if _disabled or not is_inside_tree():
		return

	for i: int in range(_rail_items.size()):
		_rail_items[i].play_intro(float(i) * RAIL_INTRO_STAGGER)
	_start_rows_intro(_row_nodes)


## 右栏错峰入场：先快照再 await 一帧（切分类很快时旧行已经被 free，逐行校验跳过）。
func _play_rows_intro() -> void:
	var rows: Array[SettingsRow] = []
	rows.assign(_row_nodes)
	await get_tree().process_frame
	if _disabled or not is_inside_tree():
		return
	_start_rows_intro(rows)


func _start_rows_intro(rows: Array[SettingsRow]) -> void:
	for i: int in range(rows.size()):
		var row: SettingsRow = rows[i]
		if not is_instance_valid(row) or row.is_queued_for_deletion():
			continue
		row.play_intro(float(mini(i, 8)) * ROW_INTRO_STAGGER)


# ── SceneManager 生命周期 ──────────────────────────────────

func _on_exit() -> void:
	_disabled = true
	for row: SettingsRow in _row_nodes:
		row.flush_pending()
		row.kill_animations()
	for item: SettingsCategoryItem in _rail_items:
		item.kill_animations()


func _on_enter() -> void:
	_disabled = false
	_entered = true

	# 每次进入都走完整的入场动画。原来只在"首次进入"播一次，第二次起直接到位，
	# 看起来就像"这个动画有时出现有时没有"；先把上次被 kill 的残留复位，再重播。
	for row: SettingsRow in _row_nodes:
		row.reset_visual_state()
	for item: SettingsCategoryItem in _rail_items:
		item.reset_visual_state()
	_update_row_focus()
	_update_rail_state()
	_animate_first_entrance()


func _input(event: InputEvent) -> void:
	if _disabled or not event.is_pressed():
		return

	if event.is_action_pressed("ui_up") or event.is_action_pressed("ui_page_up"):
		if _focus_idx == 0 and _active_category > 0:
			_show_category(_active_category - 1)
			_focus_idx = _row_nodes.size() - 1
			_update_row_focus()
		else:
			_focus_idx = maxi(0, _focus_idx - 1)
			_update_row_focus()
		_play_click()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_down") or event.is_action_pressed("ui_page_down"):
		if _focus_idx >= _row_nodes.size() - 1 and _active_category < _categories.size() - 1:
			_show_category(_active_category + 1)
			_focus_idx = 0
			_update_row_focus()
		else:
			_focus_idx = mini(_row_nodes.size() - 1, _focus_idx + 1)
			_update_row_focus()
		_play_click()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_left"):
		if not _row_nodes.is_empty():
			var cfg: Dictionary = _find_row_config_by_index(_focus_idx)
			var row: SettingsRow = _row_nodes[_focus_idx]
			if not cfg.is_empty() and bool(cfg.get("is_slider", false)):
				row.step_value(-0.05)
			else:
				row.step_value(-1.0)
			_play_click()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_right"):
		if not _row_nodes.is_empty():
			var cfg: Dictionary = _find_row_config_by_index(_focus_idx)
			var row: SettingsRow = _row_nodes[_focus_idx]
			if not cfg.is_empty() and bool(cfg.get("is_slider", false)):
				row.step_value(0.05)
			else:
				row.step_value(1.0)
			_play_click()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel"):
		back_requested.emit()
		get_viewport().set_input_as_handled()


func set_disabled(p_value: bool) -> void:
	_disabled = p_value
