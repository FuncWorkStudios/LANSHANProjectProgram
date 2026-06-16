## SettingsScene : Control
## Settings/config screen. Locale-aware: EN shows only English (no Chinese).
extends Control

signal back_requested()

var _focus_idx: int = 0
var _disabled: bool = false
var _all_rows: Array[Dictionary] = []
var _settings: AppSettings
var _row_nodes: Array[Control] = []

var _font_tcm: Font
var _font_en_body: Font
var _font_zh_title: Font
var _font_zh_body: Font

const SLIDER_TRACK_W: float = 400.0
const SLIDER_THUMB_SIZE: float = 24.0

@onready var _title_label: Label = %TitleLabel
@onready var _subtitle_container: Control = %SubtitleContainer
@onready var _configs_container: VBoxContainer = %ConfigsContainer
@onready var _back_button: Control = %BackButton


func _ready() -> void:
	_settings = GameManager.get_settings()
	_font_tcm = load(GameManager.FONT_TCM)
	_font_en_body = load(GameManager.FONT_EN_BODY)
	_font_zh_title = load(GameManager.FONT_ZH_TITLE)
	_font_zh_body = load(GameManager.FONT_ZH_BODY)
	_build_rows()
	_create_all_rows()
	_setup_back_button()
	_animate_enter()


func _build_rows() -> void:
	var is_zh: bool = GameManager.is_locale("zh")

	_all_rows = [
		{"type": "section", "label": "AUDIO", "zh": "音频", "desc": "控制音频输出与音量大小" if is_zh else "Adjust audio output volume levels"},
		{"type": "row", "id": "master", "label": "MASTER", "zh": "主音量", "is_slider": true},
		{"type": "row", "id": "bgm", "label": "BGM", "zh": "背景音乐音量", "is_slider": true},
		{"type": "row", "id": "sfx", "label": "SFX", "zh": "音效音量", "is_slider": true},
		{"type": "section", "label": "GAMEPLAY", "zh": "游戏", "desc": "控制剧情推进与交互行为" if is_zh else "Control narrative progression and interaction behavior"},
		{"type": "row", "id": "text_speed", "label": "TEXT SPEED", "zh": "文本滚动速度", "is_slider": false, "options": ["slow", "normal", "fast"]},
		{"type": "row", "id": "auto_play", "label": "AUTO PLAY", "zh": "自动剧情", "is_slider": false, "options": [false, true]},
		{"type": "row", "id": "language", "label": "LANGUAGE", "zh": "界面语言", "is_slider": false, "options": ["ZH", "EN"]},
		{"type": "section", "label": "SYSTEM", "zh": "系统", "desc": "显示与性能相关设置" if is_zh else "Display and performance settings"},
		{"type": "row", "id": "display_mode", "label": "DISPLAY", "zh": "显示模式", "is_slider": false, "options": ["windowed", "fullscreen"]},
		{"type": "row", "id": "shader_quality", "label": "SHADERS", "zh": "着色器效果", "is_slider": false, "options": ["low", "high"]},
	]

	_title_label.text = "Config"
	_title_label.add_theme_font_size_override("font_size", 72)
	if _font_tcm: _title_label.add_theme_font_override("font", _font_tcm)


func _create_all_rows() -> void:
	_row_nodes.clear()
	for i: int in range(_all_rows.size()):
		var entry: Dictionary = _all_rows[i]
		if entry.type == "section":
			var header: Control = _create_section_header(entry)
			_configs_container.add_child(header)
		else:
			var row: Control = _create_config_row(_row_nodes.size(), entry)
			_configs_container.add_child(row)
			_row_nodes.append(row)
	_update_row_focus()


func _create_section_header(data: Dictionary) -> Control:
	var is_first: bool = _all_rows.find(data) == 0
	var is_zh: bool = GameManager.is_locale("zh")

	var container := Control.new()
	container.name = "Section_" + data.label
	container.custom_minimum_size = Vector2(0, 56)
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE

	if not is_first:
		var spacer := Control.new()
		spacer.custom_minimum_size = Vector2(0, 24)
		container.add_child(spacer)

	var dot := ColorRect.new()
	dot.name = "Dot"
	dot.color = Color.WHITE
	dot.size = Vector2(8, 8)
	dot.position = Vector2(24, 12)
	container.add_child(dot)

	var en_label := Label.new()
	en_label.name = "SectionEn"
	en_label.text = data.label
	en_label.position = Vector2(44, 6)
	en_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.4))
	en_label.add_theme_font_size_override("font_size", 18)
	if _font_tcm: en_label.add_theme_font_override("font", _font_tcm)
	container.add_child(en_label)

	# Chinese section label only in ZH mode
	if is_zh:
		var zh_label := Label.new()
		zh_label.name = "SectionZh"
		zh_label.text = data.zh
		zh_label.position = Vector2(140, 8)
		zh_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.4))
		zh_label.add_theme_font_size_override("font_size", 16)
		if _font_zh_title: zh_label.add_theme_font_override("font", _font_zh_title)
		container.add_child(zh_label)

	if data.has("desc") and not str(data.desc).is_empty():
		var desc_label := Label.new()
		desc_label.name = "SectionDesc"
		desc_label.text = data.desc
		desc_label.position = Vector2(44, 34)
		desc_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.3))
		desc_label.add_theme_font_size_override("font_size", 13)
		if is_zh:
			if _font_zh_body: desc_label.add_theme_font_override("font", _font_zh_body)
		elif _font_en_body:
			desc_label.add_theme_font_override("font", _font_en_body)
		container.add_child(desc_label)

	return container


func _create_config_row(index: int, cfg: Dictionary) -> Control:
	var is_zh := GameManager.is_locale("zh")

	var container := Control.new()
	container.name = "ConfigRow_" + str(index)
	container.custom_minimum_size = Vector2(0, 68)
	container.mouse_filter = Control.MOUSE_FILTER_STOP

	var highlight := ColorRect.new()
	highlight.name = "Highlight"
	highlight.set_anchors_preset(Control.PRESET_FULL_RECT)
	highlight.color = Color(1, 1, 1, 0.0)
	highlight.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(highlight)

	var divider := ColorRect.new()
	divider.name = "Divider"
	divider.color = Color(1, 1, 1, 0.05)
	divider.size = Vector2(0, 1)
	divider.position = Vector2(24, 67)
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(divider)

	# Label side — primary only in EN, primary + secondary in ZH
	var label_container := VBoxContainer.new()
	label_container.name = "Labels"
	label_container.position = Vector2(44, 12)
	label_container.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var primary_label := Label.new()
	primary_label.name = "PrimaryLabel"
	primary_label.text = cfg.zh if is_zh else cfg.label
	primary_label.add_theme_color_override("font_color", Color.WHITE)
	if is_zh:
		primary_label.add_theme_font_size_override("font_size", 22)
		if _font_zh_body: primary_label.add_theme_font_override("font", _font_zh_body)
	else:
		primary_label.add_theme_font_size_override("font_size", 26)
		if _font_tcm: primary_label.add_theme_font_override("font", _font_tcm)
	primary_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label_container.add_child(primary_label)

	# Secondary hint label only in ZH mode (shows English)
	if is_zh:
		var secondary_label := Label.new()
		secondary_label.name = "SecondaryLabel"
		secondary_label.text = cfg.label
		secondary_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.2))
		secondary_label.add_theme_font_size_override("font_size", 14)
		if _font_en_body: secondary_label.add_theme_font_override("font", _font_en_body)
		secondary_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label_container.add_child(secondary_label)

	container.add_child(label_container)

	if cfg.is_slider:
		_create_slider_control(container, cfg)
	else:
		_create_cycle_control(container, index, cfg)

	container.mouse_entered.connect(_on_row_hovered.bind(index))
	container.set_meta("highlight", highlight)
	container.set_meta("primary_label", primary_label)
	container.set_meta("divider", divider)

	return container


func _create_slider_control(parent: Control, cfg: Dictionary) -> void:
	var track_container := Control.new()
	track_container.name = "SliderTrack"
	track_container.position = Vector2(700, 22)
	track_container.size = Vector2(SLIDER_TRACK_W, SLIDER_THUMB_SIZE)
	track_container.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var track_bg := ColorRect.new()
	track_bg.name = "TrackBg"
	track_bg.color = Color(1, 1, 1, 0.1)
	track_bg.size = Vector2(SLIDER_TRACK_W, 4)
	track_bg.position = Vector2(0, 10)
	track_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track_container.add_child(track_bg)

	var track_fill := ColorRect.new()
	track_fill.name = "TrackFill"
	track_fill.color = Color(1, 1, 1, 0.6)
	track_fill.size = Vector2(SLIDER_TRACK_W * _get_slider_value(cfg.id), 4)
	track_fill.position = Vector2(0, 10)
	track_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track_container.add_child(track_fill)

	var thumb_glow := ColorRect.new()
	thumb_glow.name = "ThumbGlow"
	thumb_glow.color = Color(1, 1, 1, 0.15)
	thumb_glow.size = Vector2(32, 32)
	thumb_glow.position = Vector2(clampf(SLIDER_TRACK_W * _get_slider_value(cfg.id) - 4.0, -4.0, SLIDER_TRACK_W - 28.0), -4)
	thumb_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track_container.add_child(thumb_glow)

	var thumb := ColorRect.new()
	thumb.name = "Thumb"
	thumb.color = Color.BLACK
	thumb.size = Vector2(SLIDER_THUMB_SIZE, SLIDER_THUMB_SIZE)
	thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track_container.add_child(thumb)

	var slider := HSlider.new()
	slider.name = "HSlider"
	slider.size = Vector2(SLIDER_TRACK_W, SLIDER_THUMB_SIZE)
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.01
	slider.value = _get_slider_value(cfg.id)
	slider.modulate.a = 0.0
	slider.add_theme_stylebox_override("slider", StyleBoxEmpty.new())
	slider.add_theme_stylebox_override("grabber", StyleBoxEmpty.new())
	slider.add_theme_stylebox_override("grabber_highlight", StyleBoxEmpty.new())
	slider.value_changed.connect(_on_slider_value_changed.bind(cfg.id, track_fill, thumb, thumb_glow))
	track_container.add_child(slider)

	parent.add_child(track_container)
	parent.set_meta("track_fill", track_fill)
	parent.set_meta("thumb", thumb)
	parent.set_meta("thumb_glow", thumb_glow)
	_update_thumb_position(_get_slider_value(cfg.id), thumb, thumb_glow)


func _on_slider_value_changed(value: float, id: String, track_fill: ColorRect, thumb: ColorRect, thumb_glow: ColorRect) -> void:
	match id:
		"master": GameManager.set_setting("master_volume", value)
		"bgm": GameManager.set_setting("bgm_volume", value)
		"sfx": GameManager.set_setting("sfx_volume", value)
	AudioManager.apply_volumes()
	track_fill.size.x = SLIDER_TRACK_W * value
	_update_thumb_position(value, thumb, thumb_glow)


func _update_thumb_position(value: float, thumb: ColorRect, glow: ColorRect) -> void:
	var cx: float = SLIDER_TRACK_W * value
	thumb.position.x = clampf(cx - SLIDER_THUMB_SIZE / 2.0, 0.0, SLIDER_TRACK_W - SLIDER_THUMB_SIZE)
	glow.position.x = clampf(cx - 16.0, -4.0, SLIDER_TRACK_W - 28.0)


func _create_cycle_control(parent: Control, index: int, cfg: Dictionary) -> void:
	var is_zh: bool = GameManager.is_locale("zh")
	var hbox := HBoxContainer.new()
	hbox.name = "CycleBox"
	hbox.position = Vector2(700, 16)
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var prev_btn := Button.new()
	prev_btn.name = "PrevBtn"
	prev_btn.text = "<"
	prev_btn.flat = true
	prev_btn.add_theme_color_override("font_color", Color(1, 1, 1, 0.3))
	prev_btn.add_theme_font_size_override("font_size", 28)
	prev_btn.mouse_entered.connect(_on_chevron_hovered.bind(prev_btn, true))
	prev_btn.mouse_exited.connect(_on_chevron_hovered.bind(prev_btn, false))
	prev_btn.pressed.connect(_on_step_option.bind(cfg.id, -1))
	hbox.add_child(prev_btn)

	var val_label := Label.new()
	val_label.name = "ValLabel"
	val_label.text = _get_option_display(cfg.id)
	val_label.custom_minimum_size = Vector2(180, 0)
	val_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	val_label.add_theme_font_size_override("font_size", 22)
	val_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not is_zh and _font_tcm:
		val_label.add_theme_font_override("font", _font_tcm)
	elif _font_zh_body:
		val_label.add_theme_font_override("font", _font_zh_body)
	hbox.add_child(val_label)

	var next_btn := Button.new()
	next_btn.name = "NextBtn"
	next_btn.text = ">"
	next_btn.flat = true
	next_btn.add_theme_color_override("font_color", Color(1, 1, 1, 0.3))
	next_btn.add_theme_font_size_override("font_size", 28)
	next_btn.mouse_entered.connect(_on_chevron_hovered.bind(next_btn, true))
	next_btn.mouse_exited.connect(_on_chevron_hovered.bind(next_btn, false))
	next_btn.pressed.connect(_on_step_option.bind(cfg.id, 1))
	hbox.add_child(next_btn)

	parent.add_child(hbox)
	parent.set_meta("val_label", val_label)
	parent.set_meta("prev_btn", prev_btn)
	parent.set_meta("next_btn", next_btn)


func _on_chevron_hovered(btn: Button, hovered: bool) -> void:
	btn.add_theme_color_override("font_color", Color.WHITE if hovered else Color(1, 1, 1, 0.3))


func _get_slider_value(id: String) -> float:
	match id:
		"master": return _settings.master_volume
		"bgm": return _settings.bgm_volume
		"sfx": return _settings.sfx_volume
	return 0.0


func _get_option_display(id: String) -> String:
	var is_zh: bool = GameManager.is_locale("zh")
	match id:
		"language":
			return GameManager.LOCALE_LABELS.get(GameManager.get_locale(), GameManager.get_locale().to_upper())
		"text_speed":
			match _settings.text_speed:
				"slow": return "慢" if is_zh else "Slow"
				"normal": return "中" if is_zh else "Normal"
				"fast": return "快" if is_zh else "Fast"
		"auto_play":
			return ("开启" if is_zh else "ON") if _settings.auto_play else ("关闭" if is_zh else "OFF")
		"display_mode":
			return "窗口" if _settings.display_mode == "windowed" else "全屏"
		"shader_quality":
			return "性能" if _settings.shader_quality == "low" else "HIGH"
	return ""


func _on_step_option(id: String, dir: int) -> void:
	_play_click()

	match id:
		"language":
			var next_lang: String = GameManager.next_locale().to_upper()
			GameManager.set_setting("language", next_lang)
			_settings = GameManager.get_settings()
			_rebuild_ui()
		"text_speed":
			var opts: Array[String] = ["slow", "normal", "fast"]
			var cur: int = opts.find(_settings.text_speed)
			var next_speed: String = opts[(cur + dir + opts.size()) % opts.size()]
			GameManager.set_setting("text_speed", next_speed)
			_settings = GameManager.get_settings()
		"auto_play":
			GameManager.set_setting("auto_play", not _settings.auto_play)
			_settings = GameManager.get_settings()
		"display_mode":
			var next_mode: String = "fullscreen" if _settings.display_mode == "windowed" else "windowed"
			GameManager.set_setting("display_mode", next_mode)
			_settings = GameManager.get_settings()
			if next_mode == "fullscreen":
				if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_FULLSCREEN:
					DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
			else:
				if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
					DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		"shader_quality":
			var next_quality: String = "high" if _settings.shader_quality == "low" else "low"
			GameManager.set_setting("shader_quality", next_quality)
			_settings = GameManager.get_settings()

	_update_display_values()


# Full rebuild on language change (section labels, row labels are locale-aware)
func _rebuild_ui() -> void:
	_build_rows()
	for c in _configs_container.get_children():
		c.queue_free()
	_row_nodes.clear()
	_create_all_rows()


func _update_display_values() -> void:
	for i: int in range(_row_nodes.size()):
		var row: Control = _row_nodes[i]
		if not row.has_meta("val_label"):
			continue
		var val_label: Label = row.get_meta("val_label")
		var row_idx: int = 0
		for entry: Dictionary in _all_rows:
			if entry.type == "row":
				if row_idx == i:
					val_label.text = _get_option_display(entry.id)
					break
				row_idx += 1


func _update_row_focus() -> void:
	for i: int in range(_row_nodes.size()):
		var row: Control = _row_nodes[i]
		var is_focused: bool = i == _focus_idx
		var highlight: ColorRect = row.get_meta("highlight")
		var primary: Label = row.get_meta("primary_label")

		var hl_tween := create_tween()
		hl_tween.set_ease(Tween.EASE_OUT)
		hl_tween.tween_property(highlight, "color:a", 0.05 if is_focused else 0.0, 0.25)

		var x_tween := create_tween()
		x_tween.set_ease(Tween.EASE_OUT)
		x_tween.tween_property(row, "position:x", 10.0 if is_focused else 0.0, 0.25)

		primary.add_theme_color_override("font_color", Color.WHITE if is_focused else Color(1, 1, 1, 0.6))

		if row.has_meta("val_label"):
			var val_label: Label = row.get_meta("val_label")
			val_label.add_theme_color_override("font_color", Color.WHITE if is_focused else Color(1, 1, 1, 0.8))


func _on_row_hovered(index: int) -> void:
	if _disabled or _focus_idx == index:
		return
	_focus_idx = index
	_update_row_focus()
	_play_click()


func _setup_back_button() -> void:
	var is_zh: bool = GameManager.is_locale("zh")

	_back_button.mouse_filter = Control.MOUSE_FILTER_STOP
	_back_button.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_back_button.offset_top = -96.0
	_back_button.offset_bottom = 0.0
	_back_button.size.y = 96

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
	border.size.y = 1
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
	back_label.text = "返回" if is_zh else "BACK"
	back_label.position = Vector2(88, 28)
	back_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.8))
	back_label.add_theme_font_size_override("font_size", 24)
	back_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if is_zh:
		if _font_zh_title: back_label.add_theme_font_override("font", _font_zh_title)
	elif _font_tcm:
		back_label.add_theme_font_override("font", _font_tcm)
	_back_button.add_child(back_label)

	if is_zh:
		var sub_label := Label.new()
		sub_label.name = "SubLabel"
		sub_label.text = "取消当前操作"
		sub_label.position = Vector2(88, 58)
		sub_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.2))
		sub_label.add_theme_font_size_override("font_size", 10)
		sub_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if _font_zh_body: sub_label.add_theme_font_override("font", _font_zh_body)
		_back_button.add_child(sub_label)
	else:
		var sub_label := Label.new()
		sub_label.name = "SubLabel"
		sub_label.text = "Cancel current operation"
		sub_label.position = Vector2(88, 58)
		sub_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.2))
		sub_label.add_theme_font_size_override("font_size", 10)
		sub_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if _font_en_body: sub_label.add_theme_font_override("font", _font_en_body)
		_back_button.add_child(sub_label)

	_back_button.gui_input.connect(_on_back_bar_clicked)
	_back_button.mouse_entered.connect(_on_back_bar_hovered.bind(true))
	_back_button.mouse_exited.connect(_on_back_bar_hovered.bind(false))
	_back_button.set_meta("esc_box", esc_box)
	_back_button.set_meta("esc_label", esc_label)


func _on_back_bar_clicked(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_play_click()
		back_requested.emit()


func _on_back_bar_hovered(hovered: bool) -> void:
	var esc_box: ColorRect = _back_button.get_meta("esc_box")
	var esc_label: Label = _back_button.get_meta("esc_label")
	if esc_box:
		esc_box.color = Color.BLACK if hovered else Color.WHITE
	if esc_label:
		esc_label.add_theme_color_override("font_color", Color.WHITE if hovered else Color.BLACK)


func _play_click() -> void:
	AudioManager.play_click()


func _animate_enter() -> void:
	modulate.a = 0.0
	scale = Vector2(0.98, 0.98)
	var tween := create_tween()
	tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_EXPO)
	tween.tween_property(self, "modulate:a", 1.0, 0.8)
	tween.parallel().tween_property(self, "scale", Vector2(1, 1), 0.8)


# ── SceneManager lifecycle ──────────────────────────────────

func _on_exit() -> void:
	_disabled = true


func _on_enter() -> void:
	_disabled = false
	_update_row_focus()


func _input(event: InputEvent) -> void:
	if _disabled or not event.is_pressed():
		return
	if event.is_action_pressed("ui_up") or event.is_action_pressed("ui_page_up"):
		_focus_idx = max(0, _focus_idx - 1)
		_update_row_focus(); _play_click()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_down") or event.is_action_pressed("ui_page_down"):
		_focus_idx = min(_row_nodes.size() - 1, _focus_idx + 1)
		_update_row_focus(); _play_click()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_left"):
		var cfg: Dictionary = _get_focused_config()
		if not cfg.is_empty():
			if cfg.is_slider:
				var row: Control = _row_nodes[_focus_idx]
				var slider: HSlider = row.get_node_or_null("SliderTrack/HSlider")
				if slider:
					slider.value = clampf(slider.value - slider.step * 5.0, slider.min_value, slider.max_value)
					_play_click()
			else:
				_on_step_option(cfg.id, -1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_right"):
		var cfg: Dictionary = _get_focused_config()
		if not cfg.is_empty():
			if cfg.is_slider:
				var row: Control = _row_nodes[_focus_idx]
				var slider: HSlider = row.get_node_or_null("SliderTrack/HSlider")
				if slider:
					slider.value = clampf(slider.value + slider.step * 5.0, slider.min_value, slider.max_value)
					_play_click()
			else:
				_on_step_option(cfg.id, 1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel"):
		back_requested.emit()
		get_viewport().set_input_as_handled()


func _get_focused_config() -> Dictionary:
	var row_idx: int = 0
	for entry: Dictionary in _all_rows:
		if entry.type == "row":
			if row_idx == _focus_idx:
				return entry
			row_idx += 1
	return {}


func set_disabled(val: bool) -> void:
	_disabled = val
