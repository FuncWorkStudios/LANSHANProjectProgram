## TabMenu : Control
## In-game tab menu with multi-level navigation (MAIN → SYSTEM → CONFIG).
## Port of TabMenu.tsx from components/ — redesigned with proper binding,
## section dividers, and CONFIG-level value controls.
extends Control

enum MenuLevel { MAIN, SYSTEM, CONFIG }

signal close_requested()
signal back_to_title()

# ---------------------------------------------------------------------------
# Internal state
# ---------------------------------------------------------------------------
var _level: MenuLevel = MenuLevel.MAIN
var _focus_idx: int = 0
var _is_open: bool = false
var _menu_animating: bool = false
var _font_tcm: Font = null
var _font_zh_title: Font = null
var _font_en_body: Font = null

var _main_options: Array[Dictionary] = []
var _system_options: Array[Dictionary] = []
var _config_options: Array[Dictionary] = []

const OPTION_HEIGHT: float = 51.0

@onready var _level_label: Label = %LevelLabel
@onready var _title_label: Label = %CurrentTitleLabel
@onready var _subtitle_label: Label = %CurrentSubtitleLabel
@onready var _desc_label: Label = %CurrentDescLabel
@onready var _options_container: VBoxContainer = %OptionsContainer
@onready var _close_button: Control = %CloseButton
@onready var _bg_overlay: ColorRect = %BgOverlay
@onready var _bg_image: TextureRect = %BgImage


# ===================================================================
# Lifecycle
# ===================================================================

func _ready() -> void:
	_font_tcm = load("res://assets/fonts/TCM_____.TTF")
	_font_zh_title = load("res://assets/fonts/SourceHanSerifCN-SemiBold-7.otf")
	_font_en_body = load("res://assets/fonts/times.ttf")
	_setup_options()
	visible = false


func _setup_options() -> void:
	_main_options = [
		{"id": "item", "en": "Item", "zh": "物品", "desc_zh": "查看现有的物品。", "desc_en": "Examine collected items.", "group": "interact"},
		{"id": "terminal", "en": "Terminal", "zh": "终端", "desc_zh": "访问系统终端。", "desc_en": "Access core terminal.", "group": "interact"},
		{"id": "profile", "en": "Profile", "zh": "档案", "desc_zh": "记录有关人物的背景资料。", "desc_en": "View background data.", "group": "interact"},
		{"id": "story", "en": "Story", "zh": "故事", "desc_zh": "回顾已经历过的剧情节点。", "desc_en": "Review past story nodes.", "group": "review"},
		{"id": "data", "en": "Data", "zh": "资料", "desc_zh": "整理收集到的线索。", "desc_en": "Organize collected clues.", "group": "review"},
		{"id": "system", "en": "System", "zh": "系统", "desc_zh": "管理游戏选项。", "desc_en": "Manage game-wide configurations.", "group": "system"},
	]

	_system_options = [
		{"id": "config", "en": "Settings", "zh": "设置", "desc_zh": "变更游戏设定。", "desc_en": "Change game settings."},
		{"id": "tutorial", "en": "Tutorial", "zh": "教学", "desc_zh": "回顾游戏操作方法。", "desc_en": "Review gameplay instructions."},
		{"id": "back", "en": "Back", "zh": "返回菜单", "desc_zh": "返回上一级菜单。", "desc_en": "Return to previous menu."},
		{"id": "title", "en": "Exit to Title", "zh": "返回标题", "desc_zh": "返回主界面。", "desc_en": "Return to title screen."},
	]

	_config_options = [
		{"id": "master", "label": "MASTER", "zh": "主音量"},
		{"id": "bgm", "label": "BGM", "zh": "背景音乐"},
		{"id": "sfx", "label": "SFX", "zh": "音效音量"},
		{"id": "text_speed", "label": "TEXT SPEED", "zh": "文本速度"},
		{"id": "auto_play", "label": "AUTO", "zh": "自动播放"},
		{"id": "shader_quality", "label": "SHADERS", "zh": "渲染质量"},
		{"id": "display_mode", "label": "DISPLAY", "zh": "显示模式"},
		{"id": "language", "label": "LANGUAGE", "zh": "系统语言"},
	]


# ===================================================================
# Open / Close
# ===================================================================

func open(terminal_status: String = "locked", bg_path: String = "") -> void:
	_is_open = true
	_level = MenuLevel.MAIN
	_focus_idx = 0

	# Rebuild main options to filter locked terminal
	_setup_options()   # reset
	if terminal_status == "locked":
		var filtered: Array[Dictionary] = []
		for opt: Dictionary in _main_options:
			if opt.id != "terminal":
				filtered.append(opt)
		_main_options = filtered

	if not bg_path.is_empty() and ResourceLoader.exists(bg_path):
		_bg_image.texture = load(bg_path)

	visible = true
	AudioManager.set_menu_mode(true)
	_animate_enter()
	_refresh_options()


func close() -> void:
	_is_open = false
	AudioManager.set_menu_mode(false)
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.3)
	tween.tween_callback(_on_close_complete)


func _on_close_complete() -> void:
	visible = false
	modulate.a = 1.0


# ===================================================================
# Animation
# ===================================================================

func _animate_enter() -> void:
	modulate.a = 0.0
	_options_container.position.x = 100.0
	var tween := create_tween()
	tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_EXPO)
	tween.set_parallel(true)
	tween.tween_property(self, "modulate:a", 1.0, 0.6)
	tween.tween_property(_options_container, "position:x", 0.0, 0.8)


# ===================================================================
# Options display
# ===================================================================

func _refresh_options() -> void:
	for child: Node in _options_container.get_children():
		child.queue_free()

	var options: Array[Dictionary] = _get_current_options()
	var prev_group: String = ""

	for i: int in range(options.size()):
		var data: Dictionary = options[i]

		# Add group divider between different MAIN menu groups
		if _level == MenuLevel.MAIN and data.has("group"):
			var group: String = data.group
			if prev_group != "" and prev_group != group:
				var divider: Control = _create_group_divider()
				_options_container.add_child(divider)
			prev_group = group

		var row: Control = _create_option_row(i, data)
		_options_container.add_child(row)

	_update_level_display()
	_update_focus()


func _create_group_divider() -> Control:
	var divider := Control.new()
	divider.name = "GroupDivider"
	divider.custom_minimum_size = Vector2(0, 4)
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return divider


func _get_current_options() -> Array[Dictionary]:
	match _level:
		MenuLevel.MAIN: return _main_options
		MenuLevel.SYSTEM: return _system_options
		MenuLevel.CONFIG: return _config_options
	return []


# ===================================================================
# Row creation
# ===================================================================

func _create_option_row(index: int, data: Dictionary) -> Control:
	var container := Control.new()
	container.name = "Option_" + str(index)
	container.custom_minimum_size = Vector2(0, OPTION_HEIGHT)
	container.mouse_filter = Control.MOUSE_FILTER_STOP

	var sweep := ColorRect.new()
	sweep.name = "Sweep"
	sweep.color = Color.WHITE
	sweep.size = Vector2(0, OPTION_HEIGHT)
	sweep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(sweep)

	var hbox := HBoxContainer.new()
	hbox.name = "Content"
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hbox.alignment = BoxContainer.ALIGNMENT_END
	container.add_child(hbox)

	var en_label := Label.new()
	en_label.name = "EnLabel"
	en_label.text = data.get("en", data.get("label", ""))
	en_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	en_label.add_theme_font_size_override("font_size", 28)
	if _font_tcm: en_label.add_theme_font_override("font", _font_tcm)
	hbox.add_child(en_label)

	var zh_label := Label.new()
	zh_label.name = "ZhLabel"
	zh_label.text = data.get("zh", "")
	zh_label.add_theme_font_size_override("font_size", 18)
	if _font_zh_title: zh_label.add_theme_font_override("font", _font_zh_title)
	hbox.add_child(zh_label)

	# Value display for CONFIG level
	if _level == MenuLevel.CONFIG:
		var val_label := Label.new()
		val_label.name = "ValLabel"
		val_label.text = _get_config_value(data.id)
		val_label.custom_minimum_size = Vector2(150, 0)
		val_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		val_label.add_theme_font_size_override("font_size", 22)
		if _font_en_body: val_label.add_theme_font_override("font", _font_en_body)
		hbox.add_child(val_label)
		container.set_meta("val_label", val_label)

		# Direction arrows for CONFIG
		var left_btn := Button.new()
		left_btn.name = "LeftBtn"
		left_btn.text = "<"
		left_btn.flat = true
		left_btn.add_theme_color_override("font_color", Color(1, 1, 1, 0.3))
		left_btn.add_theme_font_size_override("font_size", 24)
		left_btn.pressed.connect(_on_config_left.bind(index))
		left_btn.mouse_filter = Control.MOUSE_FILTER_STOP
		hbox.add_child(left_btn)

		var right_btn := Button.new()
		right_btn.name = "RightBtn"
		right_btn.text = ">"
		right_btn.flat = true
		right_btn.add_theme_color_override("font_color", Color(1, 1, 1, 0.3))
		right_btn.add_theme_font_size_override("font_size", 24)
		right_btn.pressed.connect(_on_config_right.bind(index))
		right_btn.mouse_filter = Control.MOUSE_FILTER_STOP
		hbox.add_child(right_btn)

	# Store meta
	container.set_meta("sweep", sweep)
	container.set_meta("en_label", en_label)
	container.set_meta("zh_label", zh_label)

	# Signal connections — use .bind() with named methods, NOT anonymous lambdas
	container.mouse_entered.connect(_on_row_hovered.bind(index))
	container.gui_input.connect(_on_row_clicked.bind(index))

	return container


# ===================================================================
# CONFIG value helpers
# ===================================================================

func _get_config_value(id: String) -> String:
	var s: AppSettings = GameManager.get_settings()
	var is_zh: bool = s.language == "ZH"
	match id:
		"master": return str(int(s.master_volume * 100)) + "%"
		"bgm": return str(int(s.bgm_volume * 100)) + "%"
		"sfx": return str(int(s.sfx_volume * 100)) + "%"
		"text_speed":
			match s.text_speed:
				"slow": return "慢" if is_zh else "Slow"
				"normal": return "中" if is_zh else "Normal"
				"fast": return "快" if is_zh else "Fast"
		"auto_play": return ("开启" if is_zh else "ON") if s.auto_play else ("关闭" if is_zh else "OFF")
		"display_mode": return s.display_mode.to_upper()
		"shader_quality": return s.shader_quality.to_upper()
		"language": return "简体中文" if s.language == "ZH" else "ENGLISH"
	return ""


func _on_config_left(index: int) -> void:
	_focus_idx = index
	_handle_action(-1)


func _on_config_right(index: int) -> void:
	_focus_idx = index
	_handle_action(1)


# ===================================================================
# Level display
# ===================================================================

func _update_level_display() -> void:
	match _level:
		MenuLevel.MAIN: _level_label.text = "MAIN"
		MenuLevel.SYSTEM: _level_label.text = "SYSTEM"
		MenuLevel.CONFIG: _level_label.text = "CONFIG"
	if _font_tcm: _level_label.add_theme_font_override("font", _font_tcm)

	var options: Array[Dictionary] = _get_current_options()
	if _focus_idx >= 0 and _focus_idx < options.size():
		var item: Dictionary = options[_focus_idx]
		_title_label.text = item.get("en", item.get("label", ""))
		if _font_tcm: _title_label.add_theme_font_override("font", _font_tcm)
		_subtitle_label.text = item.get("zh", "")
		if _font_zh_title: _subtitle_label.add_theme_font_override("font", _font_zh_title)
		var is_zh: bool = GameManager.get_settings().language == "ZH"
		_desc_label.text = item.get("desc_zh" if is_zh else "desc_en", "")


# ===================================================================
# Focus management
# ===================================================================

func _update_focus() -> void:
	for i: int in range(_options_container.get_child_count()):
		var child: Node = _options_container.get_child(i)
		if not child.has_meta("sweep"):
			continue   # skip dividers
		var row: Control = child as Control
		var is_focused: bool = i == _focus_idx
		var sweep: ColorRect = row.get_meta("sweep")
		var en: Label = row.get_meta("en_label")
		var zh: Label = row.get_meta("zh_label")

		var tween := create_tween()
		tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		if is_focused:
			tween.tween_property(sweep, "scale:x", 1.05, 0.3).from(0.0)
			tween.parallel().tween_property(row, "position:x", -40.0, 0.2)
		else:
			tween.tween_property(sweep, "scale:x", 0.0, 0.3)
			tween.parallel().tween_property(row, "position:x", 10.0, 0.2)

		en.add_theme_color_override("font_color", Color.BLACK if is_focused else Color.WHITE)
		zh.add_theme_color_override("font_color", Color(0, 0, 0, 0.6) if is_focused else Color(1, 1, 1, 0.5))
		row.modulate.a = 1.0 if is_focused else 0.3

		# Focused value label styling
		var val_label: Label = row.get_meta("val_label")
		if val_label:
			val_label.add_theme_color_override("font_color", Color.BLACK if is_focused else Color(1, 1, 1, 0.7))

	_update_level_display()


# ===================================================================
# Interaction (named methods for signal binding)
# ===================================================================

func _on_row_hovered(index: int) -> void:
	if _menu_animating or _focus_idx == index:
		return
	_focus_idx = index
	_update_focus()
	_play_click()


func _on_row_clicked(index: int, event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_focus_idx = index
		_update_focus()
		_handle_action(0)
		_play_click()


# ===================================================================
# Action handling
# ===================================================================

func _handle_action(dir: int) -> void:
	_play_click()
	match _level:
		MenuLevel.MAIN:
			var opt: Dictionary = _main_options[_focus_idx]
			if opt.id == "system" and dir == 0:
				_level = MenuLevel.SYSTEM
				_focus_idx = 0
				_refresh_options()
		MenuLevel.SYSTEM:
			var opt: Dictionary = _system_options[_focus_idx]
			match opt.id:
				"config":
					if dir == 0:
						_level = MenuLevel.CONFIG
						_focus_idx = 0
						_refresh_options()
				"back":
					if dir == 0:
						_level = MenuLevel.MAIN
						_focus_idx = _main_options.size() - 1
						_refresh_options()
				"title":
					if dir == 0:
						close()
						back_to_title.emit()
		MenuLevel.CONFIG:
			_handle_config_action(dir)


func _handle_config_action(dir: int) -> void:
	var cfg: Dictionary = _config_options[_focus_idx]
	var step: int = 1 if dir == 0 else dir
	var s: AppSettings = GameManager.get_settings()

	match cfg.id:
		"language":
			var next_lang: String = "EN" if s.language == "ZH" else "ZH"
			GameManager.set_setting("language", next_lang)
		"auto_play":
			GameManager.set_setting("auto_play", not s.auto_play)
		"text_speed":
			var opts: Array[String] = ["slow", "normal", "fast"]
			var cur: int = opts.find(s.text_speed)
			GameManager.set_setting("text_speed", opts[(cur + step + opts.size()) % opts.size()])
		"shader_quality":
			var next_quality: String = "high" if s.shader_quality == "low" else "low"
			GameManager.set_setting("shader_quality", next_quality)
		"display_mode":
			var next_mode: String = "fullscreen" if s.display_mode == "windowed" else "windowed"
			GameManager.set_setting("display_mode", next_mode)
			if next_mode == "fullscreen":
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
			else:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		"master":
			var d: float = 0.1 * dir if dir != 0 else 0.1
			var next_val: float = s.master_volume + d
			if dir == 0 and next_val > 1.05: next_val = 0.0
			GameManager.set_setting("master_volume", clampf(next_val, 0.0, 1.0))
			AudioManager.apply_volumes()
		"bgm":
			var d: float = 0.1 * dir if dir != 0 else 0.1
			var next_val: float = s.bgm_volume + d
			if dir == 0 and next_val > 1.05: next_val = 0.0
			GameManager.set_setting("bgm_volume", clampf(next_val, 0.0, 1.0))
			AudioManager.apply_volumes()
		"sfx":
			var d: float = 0.1 * dir if dir != 0 else 0.1
			var next_val: float = s.sfx_volume + d
			if dir == 0 and next_val > 1.05: next_val = 0.0
			GameManager.set_setting("sfx_volume", clampf(next_val, 0.0, 1.0))
			AudioManager.apply_volumes()

	_refresh_options()


# ===================================================================
# Audio
# ===================================================================

func _play_click() -> void:
	AudioManager.play_sfx("res://assets/Sfx/Choose.wav")


# ===================================================================
# Input
# ===================================================================

func _input(event: InputEvent) -> void:
	if not _is_open or not event.is_pressed():
		return

	if event.is_action_pressed("ui_cancel"):
		match _level:
			MenuLevel.CONFIG:
				_level = MenuLevel.SYSTEM
			MenuLevel.SYSTEM:
				_level = MenuLevel.MAIN
			MenuLevel.MAIN:
				close()
				get_viewport().set_input_as_handled()
				return
		_focus_idx = 0
		_refresh_options()
		_play_click()
		get_viewport().set_input_as_handled()

	elif event.is_action_pressed("ui_up"):
		var options: Array[Dictionary] = _get_current_options()
		_focus_idx = max(0, _focus_idx - 1)
		_update_focus()
		_play_click()
		get_viewport().set_input_as_handled()

	elif event.is_action_pressed("ui_down"):
		var options: Array[Dictionary] = _get_current_options()
		_focus_idx = min(options.size() - 1, _focus_idx + 1)
		_update_focus()
		_play_click()
		get_viewport().set_input_as_handled()

	elif event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_right"):
		_handle_action(1)
		get_viewport().set_input_as_handled()

	elif event.is_action_pressed("ui_left"):
		_handle_action(-1)
		get_viewport().set_input_as_handled()
