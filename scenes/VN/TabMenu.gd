## TabMenu : Control
## In-game tab menu — redesigned to match QuitConfirm modal style.
## Multi-level: MAIN → SYSTEM → CONFIG.  Tab key to open, ESC to close.
class_name TabMenu
extends Control

enum MenuLevel { MAIN, SYSTEM, CONFIG }

signal close_requested()
signal back_to_title()
signal open_settings()

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------
var _level: MenuLevel = MenuLevel.MAIN
var _focus_idx: int = 0
var _is_open: bool = false
var _anim_tween: Tween = null
var _entry_tweens: Array[Tween] = []   # per-child + delayed focus tweens from _animate_enter

var _font_tcm: Font = null
var _font_zh_title: Font = null
var _font_zh_body: Font = null
var _font_en_body: Font = null

var _main_options: Array[Dictionary] = []
var _system_options: Array[Dictionary] = []
var _config_options: Array[Dictionary] = []

# UI nodes (built in code)
var _darken_overlay: ColorRect
var _band: Control
var _branding: Control
var _level_label: Label
var _title_label: Label
var _subtitle_label: Label
var _desc_label: Label
var _options_container: VBoxContainer

const OPTION_HEIGHT: float = 51.0
const BAND_PAD: float = 64.0


# ===================================================================
# Lifecycle
# ===================================================================

func _ready() -> void:
	_font_tcm = load(GameManager.FONT_TCM)
	_font_zh_title = load(GameManager.FONT_ZH_TITLE)
	_font_zh_body = load(GameManager.FONT_ZH_BODY)
	_font_en_body = load(GameManager.FONT_EN_BODY)

	set_anchors_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_STOP
	visible = false

	# Block all input from reaching VN behind
	gui_input.connect(_swallow_input)

	_setup_options()
	_build_blurred_background()
	_build_band()
	_build_branding()
	_build_labels()
	_build_options_container()


func _setup_options() -> void:
	_main_options = [
		{"id": "item",       "en": "Item",     "zh": "物品", "desc": "查看现有的物品。",         "desc_en": "Examine collected items."},
		{"id": "terminal",   "en": "Terminal", "zh": "终端", "desc": "访问系统终端。",           "desc_en": "Access core terminal."},
		{"id": "profile",    "en": "Profile",  "zh": "档案", "desc": "记录有关人物的背景资料。", "desc_en": "View background data."},
		{"id": "story",      "en": "Story",    "zh": "故事", "desc": "回顾已经历过的剧情节点。", "desc_en": "Review past story nodes."},
		{"id": "data",       "en": "Data",     "zh": "资料", "desc": "整理收集到的线索。",       "desc_en": "Organize collected clues."},
		{"id": "system",     "en": "System",   "zh": "系统", "desc": "管理游戏选项。",           "desc_en": "Manage game-wide configurations."},
	]
	_system_options = [
		{"id": "config",   "en": "Settings",      "zh": "设置",     "desc": "变更游戏设定。",       "desc_en": "Change game settings."},
		{"id": "back",     "en": "Back",          "zh": "返回菜单", "desc": "返回上一级菜单。",     "desc_en": "Return to previous menu."},
		{"id": "title",    "en": "Exit to Title", "zh": "返回标题", "desc": "返回主界面。",         "desc_en": "Return to title screen."},
	]
	_config_options = [
		{"id": "master",         "label": "MASTER",     "zh": "主音量"},
		{"id": "bgm",            "label": "BGM",        "zh": "背景音乐"},
		{"id": "sfx",            "label": "SFX",        "zh": "音效音量"},
		{"id": "text_speed",     "label": "TEXT SPEED", "zh": "文本速度"},
		{"id": "auto_play",      "label": "AUTO",       "zh": "自动播放"},
		{"id": "shader_quality", "label": "SHADERS",    "zh": "渲染质量"},
		{"id": "display_mode",   "label": "DISPLAY",    "zh": "显示模式"},
		{"id": "language",       "label": "LANGUAGE",   "zh": "系统语言"},
	]


# ===================================================================
# UI Construction
# ===================================================================

func _build_blurred_background() -> void:
	# Darken overlay — fully opaque black, blocks VN behind
	_darken_overlay = ColorRect.new()
	_darken_overlay.name = "DarkenBg"
	_darken_overlay.set_anchors_preset(PRESET_FULL_RECT)
	_darken_overlay.color = Color(0, 0, 0, 0.55)
	_darken_overlay.mouse_filter = MOUSE_FILTER_STOP
	add_child(_darken_overlay)


func _build_band() -> void:
	_band = Control.new()
	_band.set_anchors_preset(PRESET_FULL_RECT)
	_band.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(_band)

	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.95)
	bg.set_anchors_preset(PRESET_FULL_RECT)
	bg.mouse_filter = MOUSE_FILTER_IGNORE
	_band.add_child(bg)

	var top := ColorRect.new()
	top.color = Color(1, 1, 1, 0.2); top.set_anchors_preset(PRESET_TOP_WIDE)
	top.offset_bottom = 2; top.mouse_filter = MOUSE_FILTER_IGNORE
	_band.add_child(top)

	var bot := ColorRect.new()
	bot.color = Color(1, 1, 1, 0.2); bot.set_anchors_preset(PRESET_BOTTOM_WIDE)
	bot.offset_top = -2; bot.mouse_filter = MOUSE_FILTER_IGNORE
	_band.add_child(bot)


func _build_branding() -> void:
	_branding = Control.new()
	_branding.position = Vector2(48, get_viewport().get_visible_rect().size.y / 2.0 - BAND_PAD - 48)
	_branding.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(_branding)

	var shadow := ColorRect.new()
	shadow.color = Color(1, 1, 1, 0.1); shadow.position = Vector2(10, 10)
	shadow.mouse_filter = MOUSE_FILTER_IGNORE
	_branding.add_child(shadow)

	var box := ColorRect.new()
	box.color = Color.WHITE; box.size = Vector2(200, 120)
	box.mouse_filter = MOUSE_FILTER_IGNORE
	_branding.add_child(box)

	var en := Label.new()
	en.text = "TAB"; en.position = Vector2(32, 16)
	en.add_theme_color_override("font_color", Color.BLACK)
	en.add_theme_font_size_override("font_size", 72)
	en.mouse_filter = MOUSE_FILTER_IGNORE
	if _font_tcm: en.add_theme_font_override("font", _font_tcm)
	_branding.add_child(en)

	var zh := Label.new()
	zh.text = "菜单"; zh.position = Vector2(36, 90)
	zh.add_theme_color_override("font_color", Color.BLACK)
	zh.add_theme_font_size_override("font_size", 28)
	zh.mouse_filter = MOUSE_FILTER_IGNORE
	if _font_zh_title: zh.add_theme_font_override("font", _font_zh_title)
	_branding.add_child(zh)

	shadow.size = box.size


func _build_labels() -> void:
	_level_label = Label.new()
	_level_label.position = Vector2(48, get_viewport().get_visible_rect().size.y / 2.0 + BAND_PAD + 20)
	_level_label.text = "MAIN"
	_level_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.4))
	_level_label.add_theme_font_size_override("font_size", 12)
	_level_label.mouse_filter = MOUSE_FILTER_IGNORE
	if _font_tcm: _level_label.add_theme_font_override("font", _font_tcm)
	add_child(_level_label)

	_title_label = Label.new()
	_title_label.position = Vector2(48, get_viewport().get_visible_rect().size.y / 2.0 + BAND_PAD + 36)
	_title_label.add_theme_color_override("font_color", Color.WHITE)
	_title_label.add_theme_font_size_override("font_size", 36)
	_title_label.mouse_filter = MOUSE_FILTER_IGNORE
	if _font_tcm: _title_label.add_theme_font_override("font", _font_tcm)
	add_child(_title_label)

	_subtitle_label = Label.new()
	_subtitle_label.position = Vector2(48, get_viewport().get_visible_rect().size.y / 2.0 + BAND_PAD + 76)
	_subtitle_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.5))
	_subtitle_label.add_theme_font_size_override("font_size", 18)
	_subtitle_label.mouse_filter = MOUSE_FILTER_IGNORE
	if _font_zh_title: _subtitle_label.add_theme_font_override("font", _font_zh_title)
	add_child(_subtitle_label)

	_desc_label = Label.new()
	_desc_label.position = Vector2(48, get_viewport().get_visible_rect().size.y / 2.0 + BAND_PAD + 100)
	_desc_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.35))
	_desc_label.add_theme_font_size_override("font_size", 14)
	_desc_label.mouse_filter = MOUSE_FILTER_IGNORE
	if _font_zh_body: _desc_label.add_theme_font_override("font", _font_zh_body)
	add_child(_desc_label)


func _build_options_container() -> void:
	_options_container = VBoxContainer.new()
	_options_container.alignment = BoxContainer.ALIGNMENT_CENTER
	_options_container.custom_minimum_size = Vector2(480, 0)
	_options_container.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(_options_container)


# ===================================================================
# Open / Close
# ===================================================================

func open(terminal_status: String = "locked", _bg_path: String = "") -> void:
	_is_open = true
	_level = MenuLevel.MAIN; _focus_idx = 0

	# Force size to fill viewport — critical for mouse blocking
	var vs := get_viewport().get_visible_rect().size
	position = Vector2.ZERO
	size = vs

	_setup_options()
	if terminal_status == "locked":
		var f: Array[Dictionary] = []
		for o in _main_options:
			if o.id != "terminal": f.append(o)
		_main_options = f

	_refresh_options()
	_animate_enter()


func close() -> void:
	_is_open = false
	_kill_anim()

	_anim_tween = create_tween()
	_anim_tween.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	_anim_tween.tween_property(self, "modulate:a", 0.0, 0.25)
	_anim_tween.tween_callback(_on_close_done)


func _on_close_done() -> void:
	visible = false
	close_requested.emit()


# ===================================================================
# Animation
# ===================================================================

func _animate_enter() -> void:
	visible = true
	_kill_anim()

	# Set opaque state immediately — no see-through
	_darken_overlay.color.a = 0.55
	_band.scale.x = 1.0

	# Fade self + options in smoothly
	modulate.a = 0.0
	_entry_tweens.clear()
	_anim_tween = create_tween().set_parallel(true)
	_anim_tween.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	_anim_tween.tween_property(self, "modulate:a", 1.0, 0.3)
	for i: int in range(_options_container.get_child_count()):
		var c := _options_container.get_child(i)
		c.modulate.a = 0.0
		var st := create_tween()
		st.tween_interval(0.2 + i * 0.04)
		st.tween_property(c, "modulate:a", 1.0, 0.2)
		_entry_tweens.append(st)

	# Re-apply focus after all rows have finished fading in so
	# the first option is visibly highlighted (white sweep + shift).
	var focus_tween := create_tween()
	focus_tween.tween_interval(0.55)
	focus_tween.tween_callback(_update_focus)
	_entry_tweens.append(focus_tween)



# ===================================================================
# Options
# ===================================================================

func _refresh_options() -> void:
	for c in _options_container.get_children():
		c.queue_free()

	var opts := _get_current_options()
	var vp_w: float = get_viewport().get_visible_rect().size.x
	_options_container.position = Vector2(vp_w - 520, get_viewport().get_visible_rect().size.y / 2.0 - OPTION_HEIGHT * opts.size() / 2.0)

	for i: int in range(opts.size()):
		var row := _make_row(i, opts[i])
		_options_container.add_child(row)

	_update_level_display()
	_update_focus()


func _get_current_options() -> Array[Dictionary]:
	match _level:
		MenuLevel.MAIN:    return _main_options
		MenuLevel.SYSTEM:  return _system_options
		MenuLevel.CONFIG:  return _config_options
	return []


func _make_row(idx: int, data: Dictionary) -> Control:
	@warning_ignore("shadowed_global_identifier")
	var wrap := Control.new()
	wrap.custom_minimum_size = Vector2(480, OPTION_HEIGHT)
	wrap.mouse_filter = MOUSE_FILTER_STOP

	var sweep := ColorRect.new()
	sweep.color = Color.WHITE; sweep.size = Vector2(480, OPTION_HEIGHT)
	sweep.scale.x = 0.0; sweep.mouse_filter = MOUSE_FILTER_IGNORE
	wrap.add_child(sweep)

	var hb := HBoxContainer.new()
	hb.size = Vector2(480, OPTION_HEIGHT); hb.alignment = BoxContainer.ALIGNMENT_END
	hb.mouse_filter = MOUSE_FILTER_IGNORE
	wrap.add_child(hb)

	# Spacer
	var sp := Control.new(); sp.custom_minimum_size = Vector2(16, 0); sp.mouse_filter = MOUSE_FILTER_IGNORE
	hb.add_child(sp)

	# EN label
	var en := Label.new()
	if _level == MenuLevel.CONFIG:
		en.text = data.label
	else:
		en.text = data.en
	en.add_theme_font_size_override("font_size", 42)
	en.mouse_filter = MOUSE_FILTER_IGNORE
	if _font_tcm: en.add_theme_font_override("font", _font_tcm)
	hb.add_child(en)

	var sp2 := Control.new(); sp2.custom_minimum_size = Vector2(12, 0); sp2.mouse_filter = MOUSE_FILTER_IGNORE
	hb.add_child(sp2)

	# ZH label
	var zh := Label.new()
	zh.text = data.zh
	zh.add_theme_font_size_override("font_size", 24)
	zh.mouse_filter = MOUSE_FILTER_IGNORE
	if _font_zh_title: zh.add_theme_font_override("font", _font_zh_title)
	hb.add_child(zh)

	# Value label + arrows for CONFIG
	if _level == MenuLevel.CONFIG:
		var val := Label.new()
		val.text = _get_config_value(data.id)
		val.custom_minimum_size = Vector2(150, 0)
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		val.add_theme_font_size_override("font_size", 22)
		val.mouse_filter = MOUSE_FILTER_IGNORE
		if _font_en_body: val.add_theme_font_override("font", _font_en_body)
		hb.add_child(val)
		wrap.set_meta("val_label", val)

		var lb := Button.new()
		lb.text = "<"; lb.flat = true
		lb.add_theme_color_override("font_color", Color(1, 1, 1, 0.3))
		lb.add_theme_font_size_override("font_size", 24)
		lb.pressed.connect(_on_config_left.bind(idx))
		lb.mouse_filter = MOUSE_FILTER_STOP
		hb.add_child(lb)

		var rb := Button.new()
		rb.text = ">"; rb.flat = true
		rb.add_theme_color_override("font_color", Color(1, 1, 1, 0.3))
		rb.add_theme_font_size_override("font_size", 24)
		rb.pressed.connect(_on_config_right.bind(idx))
		rb.mouse_filter = MOUSE_FILTER_STOP
		hb.add_child(rb)

	wrap.mouse_entered.connect(_on_hover.bind(idx))
	wrap.gui_input.connect(_on_click.bind(idx))
	wrap.set_meta("sweep", sweep)
	wrap.set_meta("en_label", en)
	wrap.set_meta("zh_label", zh)
	return wrap


# ===================================================================
# Level display
# ===================================================================

func _update_level_display() -> void:
	match _level:
		MenuLevel.MAIN:   _level_label.text = "MAIN"
		MenuLevel.SYSTEM: _level_label.text = "SYSTEM"
		MenuLevel.CONFIG: _level_label.text = "CONFIG"

	var opts := _get_current_options()
	if _focus_idx >= 0 and _focus_idx < opts.size():
		var d := opts[_focus_idx]
		_title_label.text = d.get("en", d.get("label", ""))
		var is_zh := GameManager.is_locale("zh")
		_subtitle_label.text = d.zh
		_desc_label.text = d.get("desc_en" if not is_zh else "desc", "")
		# Update description font to match locale
		if not is_zh and _font_en_body:
			_desc_label.add_theme_font_override("font", _font_en_body)
		elif _font_zh_body:
			_desc_label.add_theme_font_override("font", _font_zh_body)


# ===================================================================
# Focus
# ===================================================================

func _update_focus() -> void:
	for i: int in range(_options_container.get_child_count()):
		var row := _options_container.get_child(i) as Control
		var on := i == _focus_idx
		var sweep: ColorRect = row.get_meta("sweep")
		var en: Label = row.get_meta("en_label")
		var zh: Label = row.get_meta("zh_label")

		var tw := create_tween().set_parallel(true)
		tw.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(sweep, "scale:x", 1.0 if on else 0.0, 0.25)
		tw.tween_property(row, "position:x", -50.0 if on else 10.0, 0.25)
		tw.tween_property(row, "modulate:a", 1.0 if on else 0.35, 0.25)

		en.add_theme_color_override("font_color", Color.BLACK if on else Color.WHITE)
		zh.add_theme_color_override("font_color", Color(0, 0, 0, 0.6) if on else Color(1, 1, 1, 0.5))

		if row.has_meta("val_label"):
			var val: Label = row.get_meta("val_label")
			val.add_theme_color_override("font_color", Color.BLACK if on else Color(1, 1, 1, 0.7))

	_update_level_display()


# ===================================================================
# CONFIG values
# ===================================================================

func _get_config_value(id: String) -> String:
	var s := GameManager.get_settings()
	var zh := GameManager.is_locale("zh")
	match id:
		"master":         return str(int(s.master_volume * 100)) + "%"
		"bgm":            return str(int(s.bgm_volume * 100)) + "%"
		"sfx":            return str(int(s.sfx_volume * 100)) + "%"
		"text_speed":
			match s.text_speed:
				"slow":   return "慢" if zh else "Slow"
				"normal": return "中" if zh else "Normal"
				"fast":   return "快" if zh else "Fast"
		"auto_play":      return ("开启" if zh else "ON") if s.auto_play else ("关闭" if zh else "OFF")
		"display_mode":   return s.display_mode.to_upper()
		"shader_quality": return s.shader_quality.to_upper()
		"language":       return GameManager.LOCALE_LABELS.get(GameManager.get_locale(), GameManager.get_locale().to_upper())
	return ""


func _on_config_left(idx: int) -> void:
	_focus_idx = idx; _handle_action(-1)


func _on_config_right(idx: int) -> void:
	_focus_idx = idx; _handle_action(1)


# ===================================================================
# Interaction
# ===================================================================

func _on_hover(idx: int) -> void:
	if _focus_idx == idx: return
	_focus_idx = idx; _update_focus(); _play_click()


func _on_click(event: InputEvent, idx: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_focus_idx = idx; _update_focus(); _handle_action(0); _play_click()


func _handle_action(dir: int) -> void:
	_play_click()
	match _level:
		MenuLevel.MAIN:
			var o := _main_options[_focus_idx]
			if o.id == "system" and dir == 0:
				_level = MenuLevel.SYSTEM; _focus_idx = 0; _refresh_options()
		MenuLevel.SYSTEM:
			var o := _system_options[_focus_idx]
			match o.id:
				"config":
					if dir == 0: close(); open_settings.emit()
				"back":
					if dir == 0: _level = MenuLevel.MAIN; _focus_idx = _main_options.size() - 1; _refresh_options()
				"title":
					if dir == 0: close(); back_to_title.emit()
		MenuLevel.CONFIG:
			_handle_config(dir)


func _handle_config(dir: int) -> void:
	var cfg := _config_options[_focus_idx]
	var step := 1 if dir == 0 else dir
	var s := GameManager.get_settings()
	match cfg.id:
		"language":
			GameManager.set_setting("language", GameManager.next_locale().to_upper())
		"auto_play":
			GameManager.set_setting("auto_play", not s.auto_play)
		"text_speed":
			var opts := ["slow", "normal", "fast"]
			var cur := opts.find(s.text_speed)
			GameManager.set_setting("text_speed", opts[(cur + step + opts.size()) % opts.size()])
		"shader_quality":
			GameManager.set_setting("shader_quality", "high" if s.shader_quality == "low" else "low")
		"display_mode":
			var n := "fullscreen" if s.display_mode == "windowed" else "windowed"
			GameManager.set_setting("display_mode", n)
			if n == "fullscreen": DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
			else: DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		"master":
			var d := 0.1 * dir if dir != 0 else 0.1
			var v := s.master_volume + d
			if dir == 0 and v > 1.05: v = 0.0
			GameManager.set_setting("master_volume", clamp(v, 0.0, 1.0))
			AudioManager.apply_volumes()
		"bgm":
			var d := 0.1 * dir if dir != 0 else 0.1
			var v := s.bgm_volume + d
			if dir == 0 and v > 1.05: v = 0.0
			GameManager.set_setting("bgm_volume", clamp(v, 0.0, 1.0))
			AudioManager.apply_volumes()
		"sfx":
			var d := 0.1 * dir if dir != 0 else 0.1
			var v := s.sfx_volume + d
			if dir == 0 and v > 1.05: v = 0.0
			GameManager.set_setting("sfx_volume", clamp(v, 0.0, 1.0))
			AudioManager.apply_volumes()
	_refresh_options()


# ===================================================================
# Input
# ===================================================================

func _input(event: InputEvent) -> void:
	if not _is_open or not event.is_pressed(): return
	if event.is_action_pressed("ui_cancel"):
		match _level:
			MenuLevel.CONFIG:  _level = MenuLevel.SYSTEM
			MenuLevel.SYSTEM:  _level = MenuLevel.MAIN
			MenuLevel.MAIN:    close(); get_viewport().set_input_as_handled(); return
		_focus_idx = 0; _refresh_options(); _play_click(); get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_up"):
		_focus_idx = max(0, _focus_idx - 1); _update_focus(); _play_click(); get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_down"):
		var sz := _get_current_options().size()
		_focus_idx = min(sz - 1, _focus_idx + 1); _update_focus(); _play_click(); get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_right"):
		_handle_action(1); get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_left"):
		_handle_action(-1); get_viewport().set_input_as_handled()


# ===================================================================
# Helpers
# ===================================================================

func _play_click() -> void:
	AudioManager.play_click()


func _swallow_input(_event: InputEvent) -> void:
	pass  # Blocks all input from reaching VN behind

func _kill_anim() -> void:
	if _anim_tween and _anim_tween.is_valid():
		_anim_tween.kill()
	_anim_tween = null
	for tw: Tween in _entry_tweens:
		if tw and tw.is_valid():
			tw.kill()
	_entry_tweens.clear()
