## AboutScene : Control
## Movie-credits style scrolling display of about.txt.
## Auto-scrolls; any key (except ESC) speeds up scrolling.
## ESC or click back button to exit.
extends Control

signal back_requested()

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------
var _scroll_position: float = 0.0
var _base_speed: float = 28.0        # pixels per second
var _boost_speed: float = 180.0      # speed when key held
var _current_speed: float = 28.0
var _is_boosting: bool = false
var _can_interact: bool = false
var _scroll_finished: bool = false
var _total_height: float = 0.0       # total text height from RichTextLabel
var _viewport_height: float = 0.0

# Font references
var _font_tcm: Font = null
var _font_zh_title: Font = null
var _font_zh_body: Font = null
var _font_en_body: Font = null

# ---------------------------------------------------------------------------
# Onready
# ---------------------------------------------------------------------------
@onready var _title_label: Label = %TitleLabel
@onready var _credits_viewport: Control = %CreditsViewport
@onready var _credits_text: RichTextLabel = %CreditsText
@onready var _back_button: Control = %BackButton


# ===================================================================
# Lifecycle
# ===================================================================

func _ready() -> void:
	# Pure black background — About page overrides shared bg
	var black_bg := ColorRect.new()
	black_bg.name = "BlackBg"
	black_bg.color = Color(0, 0, 0, 1)
	black_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	black_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(black_bg)
	move_child(black_bg, 0)

	_font_tcm = load(GameManager.FONT_TCM)
	_font_zh_title = load(GameManager.FONT_ZH_TITLE)
	_font_zh_body = load(GameManager.FONT_ZH_BODY)
	_font_en_body = load(GameManager.FONT_EN_BODY)

	_title_label.text = "About"
	_title_label.add_theme_font_size_override("font_size", 72)
	if _font_tcm: _title_label.add_theme_font_override("font", _font_tcm)

	_load_and_format_credits()
	_setup_back_button()


func _on_enter() -> void:
	# Reset scroll state on every visit
	_scroll_position = 0.0
	_scroll_finished = false
	_is_boosting = false
	_current_speed = _base_speed
	_can_interact = false
	_viewport_height = _credits_viewport.size.y
	await get_tree().process_frame
	_total_height = _credits_text.get_content_height()
	_credits_text.position.y = _viewport_height
	_scroll_position = _viewport_height
	_animate_enter()


func _on_exit() -> void:
	_can_interact = false


# ===================================================================
# Text loading & BBCode formatting
# ===================================================================

func _load_and_format_credits() -> void:
	# Preloaded .gd file — works in editor AND exported builds
	var about_data: RefCounted = preload("res://scripts/AboutText.gd")
	var raw_text: String = about_data.TEXT

	var lines: PackedStringArray = raw_text.split("\n")
	var bbcode: String = _format_as_bbcode(lines)

	_credits_text.bbcode_enabled = true
	_credits_text.text = bbcode
	_credits_text.fit_content = true
	_credits_text.scroll_active = false   # we control scrolling manually
	_credits_text.set_meta("formatted", true)


func _format_as_bbcode(lines: PackedStringArray) -> String:
	const FONT_TCM: String = "res://assets/fonts/TCM_____.TTF"
	const _FONT_ZH_TITLE: String = "res://assets/fonts/SourceHanSerifCN-SemiBold-7.otf"
	const FONT_ZH_BODY: String = "res://assets/fonts/SourceHanSerifCN-Medium-6.otf"

	var result: String = ""
	result += "\n\n"

	for line: String in lines:
		var stripped: String = line.strip_edges()

		if stripped.is_empty():
			result += "\n"
		elif stripped.begins_with("==") and stripped.ends_with("=="):
			# Main title — centered, TCM font, large
			var title_text: String = stripped.trim_prefix("==").trim_suffix("==").strip_edges()
			result += "[center][font=" + FONT_TCM + "][font_size=42]"
			result += title_text
			result += "[/font_size][/font][/center]\n\n"
		elif stripped.begins_with("---") and stripped.ends_with("---"):
			# Section header — centered, TCM font, medium
			var header_text: String = stripped.trim_prefix("---").trim_suffix("---").strip_edges()
			result += "[center][font=" + FONT_TCM + "][font_size=30]"
			result += header_text
			result += "[/font_size][/font][/center]\n"
		elif stripped.begins_with("- "):
			# Credit line — centered, body font
			var name_text: String = stripped.trim_prefix("- ").strip_edges()
			result += "[center][font=" + FONT_ZH_BODY + "][font_size=22]"
			result += name_text
			result += "[/font_size][/font][/center]\n"
		else:
			# Other lines (like the final "A FuncWork Production")
			result += "[center][font=" + FONT_TCM + "][font_size=28]"
			result += stripped
			result += "[/font_size][/font][/center]\n"

	result += "\n\n\n\n\n"
	return result


# ===================================================================
# Back button bar (same pattern as other scenes)
# ===================================================================

func _setup_back_button() -> void:
	_back_button.mouse_filter = Control.MOUSE_FILTER_STOP
	_back_button.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_back_button.offset_top = -96.0
	_back_button.offset_bottom = 0.0

	var bar_bg := ColorRect.new()
	bar_bg.color = Color(0, 0, 0, 0.6)
	bar_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_back_button.add_child(bar_bg)

	var border := ColorRect.new()
	border.color = Color(1, 1, 1, 0.05)
	border.set_anchors_preset(Control.PRESET_TOP_WIDE)
	border.offset_bottom = 1.0
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_back_button.add_child(border)

	var esc_box := ColorRect.new()
	esc_box.color = Color.WHITE
	esc_box.size = Vector2(48, 48)
	esc_box.position = Vector2(24, 24)
	esc_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_back_button.add_child(esc_box)

	var esc_label := Label.new()
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

	var is_zh: bool = GameManager.is_locale("zh")
	var back_label := Label.new()
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

	var sub_label := Label.new()
	sub_label.text = "取消滚动字幕" if is_zh else "Stop credits scroll"
	sub_label.position = Vector2(88, 58)
	sub_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.2))
	sub_label.add_theme_font_size_override("font_size", 10)
	sub_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if is_zh:
		if _font_zh_body: sub_label.add_theme_font_override("font", _font_zh_body)
	elif _font_en_body:
		sub_label.add_theme_font_override("font", _font_en_body)
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
	if esc_box: esc_box.color = Color.BLACK if hovered else Color.WHITE
	if esc_label: esc_label.add_theme_color_override("font_color", Color.WHITE if hovered else Color.BLACK)


# ===================================================================
# Animation
# ===================================================================

func _animate_enter() -> void:
	modulate.a = 0.0
	var tween := create_tween()
	tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_EXPO)
	tween.tween_property(self, "modulate:a", 1.0, 0.8)
	tween.tween_callback(_enable_interaction)


func _enable_interaction() -> void:
	_can_interact = true


# ===================================================================
# Process — auto-scroll
# ===================================================================

func _process(delta: float) -> void:
	if not _can_interact:
		return

	# Determine speed
	_current_speed = _boost_speed if _is_boosting else _base_speed

	# Already finished — waiting for auto-return
	if _scroll_finished:
		return

	# Scroll upward: decrease position.y (moves text up)
	_scroll_position -= _current_speed * delta
	_credits_text.position.y = _scroll_position

	# When all text has scrolled past the top, auto-return to main menu
	var text_bottom: float = _scroll_position + _total_height
	if text_bottom < 0.0:
		_scroll_finished = true
		# Brief pause at end, then fade out and go back
		var t_pause: Tween = create_tween()
		t_pause.tween_interval(1.2)
		t_pause.tween_callback(_auto_return)


func _auto_return() -> void:
	back_requested.emit()


# ===================================================================
# Input — hold any key (except ESC) to speed up
# ===================================================================

func _input(event: InputEvent) -> void:
	if not _can_interact:
		return

	# ESC always exits
	if event.is_action_pressed("ui_cancel"):
		_play_click()
		back_requested.emit()
		get_viewport().set_input_as_handled()
		return

	# Any other key press/release toggles speed boost
	if event.is_pressed():
		if event is InputEventKey or event is InputEventMouseButton:
			_is_boosting = true
	else:
		# Released — check if any keys are still held
		if event is InputEventKey or event is InputEventMouseButton:
			_is_boosting = false


# ===================================================================
# Audio
# ===================================================================

func _play_click() -> void:
	AudioManager.play_click()


# ===================================================================
# Public
# ===================================================================

func set_disabled(val: bool) -> void:
	_can_interact = not val
