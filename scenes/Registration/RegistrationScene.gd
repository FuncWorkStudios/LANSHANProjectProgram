## RegistrationScene : Control
## Browser-simulated "志愿填报" form for player name input.
extends Control

signal registration_complete(player_name: String)
signal registration_cancelled()

const MAX_DISPLAY_CHARS: int = 8       # characters shown in-game
const MAX_INPUT_CHARS: int = 256      # allowed in the text field

# Preloaded list of registered character names — reject these
const BLOCKED_NAMES: Array[String] = preload("res://scripts/RegisteredNames.gd").NAMES

var _player_name: String = ""
var _show_warning: bool = false
var _interactive: bool = false

var _font_tcm: Font = null
var _font_zh_title: Font = null
var _font_zh_body: Font = null
var _font_en_body: Font = null

@onready var _backdrop: ColorRect = %Backdrop
@onready var _chrome_bar: ColorRect = %ChromeBar
@onready var _tab_label: Label = %TabLabel
@onready var _close_button: Button = %CloseButton
@onready var _content_card: Panel = %ContentCard
@onready var _page_title: Label = %PageTitle
@onready var _page_subtitle: Label = %PageSubtitle
@onready var _form_anchor: Control = %FormAnchor
@onready var _name_input: LineEdit = %NameInput
@onready var _confirm_button: Button = %ConfirmButton
@onready var _warning_banner: Label = %WarningBanner
@onready var _toast: Control = %Toast
@onready var _toast_label: Label = %ToastLabel


func _ready() -> void:
	_load_fonts()
	_setup_chrome()
	_setup_labels()
	_setup_form()
	_setup_interaction()

	_name_input.max_length = MAX_INPUT_CHARS
	_name_input.caret_blink = true
	_name_input.caret_blink_interval = 0.5
	_name_input.grab_focus()


## Called by SceneManager each time the scene becomes active.
## Reset all state so a previous session's data doesn't leak through.
func _on_enter() -> void:
	_player_name = ""
	_name_input.text = ""
	_name_input.editable = true
	_name_input.grab_focus()
	_confirm_button.text = "确定" if GameManager.is_locale("zh") else "CONFIRM"
	_hide_banner()
	_interactive = false
	_animate_enter()


func _on_exit() -> void:
	_interactive = false


func _load_fonts() -> void:
	_font_tcm = load(GameManager.FONT_TCM)
	_font_zh_title = load(GameManager.FONT_ZH_TITLE)
	_font_zh_body = load(GameManager.FONT_ZH_BODY)
	_font_en_body = load(GameManager.FONT_EN_BODY)


# ── Chrome ───────────────────────────────────────────────────────

func _setup_chrome() -> void:
	var is_zh: bool = GameManager.is_locale("zh")

	_tab_label.text = "  " + ("中考志愿填报" if is_zh else "Bori Education Bureau")
	_tab_label.add_theme_color_override("font_color", Color(0.15, 0.16, 0.18))
	_tab_label.add_theme_font_size_override("font_size", 13)
	if is_zh and _font_zh_title:
		_tab_label.add_theme_font_override("font", _font_zh_title)
	elif _font_tcm:
		_tab_label.add_theme_font_override("font", _font_tcm)

	_close_button.text = "X"
	_close_button.flat = true
	_close_button.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_close_button.add_theme_color_override("font_color", Color.BLACK)
	_close_button.add_theme_font_size_override("font_size", 20)
	_close_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if _font_tcm: _close_button.add_theme_font_override("font", _font_tcm)
	_close_button.pressed.connect(_on_cancel)

	var shadow := ColorRect.new()
	shadow.name = "ChromeShadow"
	shadow.layout_mode = 1
	shadow.anchor_left = 0.0; shadow.anchor_right = 1.0
	shadow.offset_top = 48; shadow.offset_bottom = 50
	shadow.color = Color(0, 0, 0, 0.12)
	shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shadow)


# ── Labels ───────────────────────────────────────────────────────

func _setup_labels() -> void:
	var is_zh: bool = GameManager.is_locale("zh")

	_page_title.text = "帛日市教育局 中考志愿填报系统" if is_zh else "Bori Education Bureau"
	_page_subtitle.text = "请确认身份信息。" if is_zh else "Please confirm your identity."

	if is_zh:
		if _font_zh_title: _page_title.add_theme_font_override("font", _font_zh_title)
	elif _font_tcm:
		_page_title.add_theme_font_override("font", _font_tcm)
	_page_title.add_theme_font_size_override("font_size", 28)

	if is_zh:
		if _font_zh_body: _page_subtitle.add_theme_font_override("font", _font_zh_body)
	elif _font_en_body:
		_page_subtitle.add_theme_font_override("font", _font_en_body)
	_page_subtitle.add_theme_font_size_override("font_size", 16)
	_page_subtitle.add_theme_color_override("font_color", Color(0, 0, 0, 0.55))

	_confirm_button.text = "确定" if is_zh else "CONFIRM"
	_confirm_button.add_theme_color_override("font_color", Color.WHITE)
	_confirm_button.add_theme_font_size_override("font_size", 22)
	_confirm_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	if is_zh:
		if _font_zh_title: _confirm_button.add_theme_font_override("font", _font_zh_title)
	elif _font_tcm:
		_confirm_button.add_theme_font_override("font", _font_tcm)
	_confirm_button.pressed.connect(_on_confirm)

	_warning_banner.text = ""
	_warning_banner.add_theme_color_override("font_color", Color(0.85, 0.25, 0.1, 1))
	_warning_banner.add_theme_font_size_override("font_size", 16)
	_warning_banner.custom_minimum_size = Vector2(250, 0)
	_warning_banner.modulate.a = 0.0
	_warning_banner.visible = true
	if is_zh:
		if _font_zh_body: _warning_banner.add_theme_font_override("font", _font_zh_body)
	elif _font_en_body:
		_warning_banner.add_theme_font_override("font", _font_en_body)

	_toast_label.text = "请先在该网页中完成姓名填报内容。" if is_zh else "Please complete the registration content first."
	_toast_label.add_theme_font_size_override("font_size", 16)
	_toast.visible = false
	_toast.modulate.a = 0.0
	if is_zh:
		if _font_zh_body: _toast_label.add_theme_font_override("font", _font_zh_body)
	elif _font_en_body:
		_toast_label.add_theme_font_override("font", _font_en_body)


# ── Form ─────────────────────────────────────────────────────────

func _setup_form() -> void:
	var is_zh: bool = GameManager.is_locale("zh")

	var ft: Control = Control.new()
	ft.name = "FormTable"
	ft.layout_mode = 1
	ft.anchors_preset = Control.PRESET_FULL_RECT
	ft.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_form_anchor.add_child(ft)

	const LEFT_W: float = 180.0

	# Photo panel (left, fixed width)
	var photo_panel := Panel.new()
	photo_panel.name = "PhotoPanel"
	photo_panel.layout_mode = 1
	photo_panel.anchor_left = 0.0; photo_panel.anchor_right = 0.0
	photo_panel.anchor_top = 0.0; photo_panel.anchor_bottom = 1.0
	photo_panel.offset_right = LEFT_W
	ft.add_child(photo_panel)

	var photo_bg := ColorRect.new()
	photo_bg.color = Color(0.69, 0.82, 0.941, 1)
	photo_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	photo_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	photo_panel.add_child(photo_bg)

	var photo_lbl := Label.new()
	photo_lbl.text = "暂无照片" if is_zh else "NO PHOTO"
	photo_lbl.set_anchors_preset(Control.PRESET_CENTER)
	photo_lbl.offset_left = -50.0; photo_lbl.offset_top = -16.0
	photo_lbl.offset_right = 50.0; photo_lbl.offset_bottom = 16.0
	photo_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	photo_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	photo_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if is_zh:
		if _font_zh_title: photo_lbl.add_theme_font_override("font", _font_zh_title)
	elif _font_tcm:
		photo_lbl.add_theme_font_override("font", _font_tcm)
	photo_panel.add_child(photo_lbl)

	# Vertical divider (2px, aligned with left panel edge)
	var divider := ColorRect.new()
	divider.color = Color.BLACK
	divider.layout_mode = 1
	divider.anchor_left = 0.0; divider.anchor_right = 0.0
	divider.anchor_top = 0.0; divider.anchor_bottom = 1.0
	divider.offset_left = LEFT_W; divider.offset_right = LEFT_W + 2.0
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ft.add_child(divider)

	# Right side — rows inside VBoxContainer, starting at the same y as photo
	var rows_box: VBoxContainer = VBoxContainer.new()
	rows_box.name = "RowsBox"
	rows_box.layout_mode = 1
	rows_box.anchor_left = 0.0; rows_box.anchor_right = 1.0
	rows_box.anchor_top = 0.0; rows_box.anchor_bottom = 1.0
	rows_box.offset_left = LEFT_W + 2.0
	rows_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ft.add_child(rows_box)

	var row_data: Array[Dictionary] = [
		{label = "姓名 / NAME",         is_input = true},
		{label = "性别 / GENDER",       value = "男" if is_zh else "MALE"},
		{label = "出生日期 / BIRTHDAY",  value = "2007.02.05"},
		{label = "户籍所在地 / RESIDENCE", value = "帛日市浮城区" if is_zh else "Fucheng Dist, Bori"},
		{label = "第一志愿 / PRIORITY",   value = "帛日火兰山中学" if is_zh else "Bori Lanshan High"},
		{label = "考生号 / ID NO.",      value = "1070020070205114514"},
	]

	for data: Dictionary in row_data:
		var row: Control = _make_form_row(data, is_zh)
		rows_box.add_child(row)


func _make_form_row(data: Dictionary, is_zh: bool) -> Control:
	var row: Control = Control.new()
	row.custom_minimum_size = Vector2(0, 46)
	row.size_flags_horizontal = Control.SIZE_FILL
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var row_bg := ColorRect.new()
	row_bg.color = Color(0.91, 0.941, 1.0, 1)
	row_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	row_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(row_bg)

	# Bottom divider
	var div := ColorRect.new()
	div.color = Color(0.8, 0.82, 0.86, 1)
	div.anchor_left = 0.0; div.anchor_right = 1.0; div.anchor_bottom = 1.0
	div.offset_top = -1.0
	div.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(div)

	# Label
	var lbl := Label.new()
	lbl.text = data.label
	lbl.layout_mode = 1
	lbl.anchor_left = 0.0; lbl.anchor_right = 0.35
	lbl.anchor_top = 0.0; lbl.anchor_bottom = 1.0
	lbl.offset_left = 12.0
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.add_theme_color_override("font_color", Color.BLACK)
	if is_zh:
		if _font_zh_body: lbl.add_theme_font_override("font", _font_zh_body)
	elif _font_en_body:
		lbl.add_theme_font_override("font", _font_en_body)
	row.add_child(lbl)

	if data.get("is_input", false):
		# Reparent the name input into this row
		var old_parent := _name_input.get_parent()
		if old_parent:
			old_parent.remove_child(_name_input)
		_name_input.visible = true
		_name_input.layout_mode = 1
		_name_input.anchor_left = 0.35; _name_input.anchor_right = 1.0
		_name_input.anchor_top = 0.0; _name_input.anchor_bottom = 1.0
		_name_input.offset_left = 8.0; _name_input.offset_right = -12.0
		_name_input.offset_top = 6.0; _name_input.offset_bottom = -6.0
		_name_input.placeholder_text = "请输入姓名" if is_zh else "Enter your name"
		_name_input.add_theme_color_override("font_color", Color.BLACK)
		_name_input.add_theme_color_override("placeholder_color", Color(0.55, 0.55, 0.55, 1))
		_name_input.add_theme_font_size_override("font_size", 20)
		if is_zh:
			if _font_zh_body: _name_input.add_theme_font_override("font", _font_zh_body)
		elif _font_en_body:
			_name_input.add_theme_font_override("font", _font_en_body)
		if not _name_input.text_changed.is_connected(_on_name_changed):
			_name_input.text_changed.connect(_on_name_changed)
		row.add_child(_name_input)
	else:
		var val := Label.new()
		val.text = data.value
		val.layout_mode = 1
		val.anchor_left = 0.35; val.anchor_right = 1.0
		val.anchor_top = 0.0; val.anchor_bottom = 1.0
		val.offset_left = 8.0; val.offset_right = -12.0
		val.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		val.mouse_filter = Control.MOUSE_FILTER_IGNORE
		val.add_theme_font_size_override("font_size", 18)
		val.add_theme_color_override("font_color", Color.BLACK)
		if is_zh:
			if _font_zh_body: val.add_theme_font_override("font", _font_zh_body)
		elif _font_en_body:
			val.add_theme_font_override("font", _font_en_body)
		row.add_child(val)

	return row


# ── Outside-click → warning ──────────────────────────────────────

func _setup_interaction() -> void:
	_content_card.mouse_filter = Control.MOUSE_FILTER_STOP
	_backdrop.gui_input.connect(_on_outside_clicked)
	_chrome_bar.gui_input.connect(_on_outside_clicked)


func _on_outside_clicked(event: InputEvent) -> void:
	if not _interactive: return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if _player_name.strip_edges().is_empty():
			_show_banner("警告：还未输入姓名" if GameManager.is_locale("zh") else "WARNING: NAME REQUIRED")


func _show_banner(msg: String) -> void:
	_show_warning = true
	_warning_banner.text = msg
	_warning_banner.modulate.a = 0.0
	var tween := create_tween().set_parallel(true)
	tween.tween_property(_warning_banner, "modulate:a", 1.0, 0.3)


func _hide_banner() -> void:
	_show_warning = false
	var tween := create_tween()
	tween.tween_property(_warning_banner, "modulate:a", 0.0, 0.25)


# ── Callbacks ────────────────────────────────────────────────────

func _on_name_changed(new_text: String) -> void:
	_player_name = new_text
	if _show_warning and not _player_name.strip_edges().is_empty():
		_hide_banner()


func _on_confirm() -> void:
	var name: String = _player_name.strip_edges()
	if name.is_empty():
		_show_banner("警告：还未输入姓名" if GameManager.is_locale("zh") else "WARNING: NAME REQUIRED")
		_play_click()
		return

	if name.length() > MAX_DISPLAY_CHARS:
		_show_banner("名称长度不匹配" if GameManager.is_locale("zh") else "NAME TOO LONG")
		_play_click()
		return

	# Reject spaces and symbols — allow letters, digits, CJK, kana, bopomofo
	var has_symbol: bool = false
	for ch: String in name:
		var c: int = ch.unicode_at(0)
		var ok: bool = false
		if (c >= 0x41 and c <= 0x5A) or (c >= 0x61 and c <= 0x7A): ok = true  # A-Z a-z
		elif (c >= 0x30 and c <= 0x39): ok = true                               # 0-9
		elif (c >= 0x4E00 and c <= 0x9FFF): ok = true                          # CJK
		elif (c >= 0x3400 and c <= 0x4DBF): ok = true                          # CJK Ext-A
		elif (c >= 0x3040 and c <= 0x309F): ok = true                          # 平假名
		elif (c >= 0x30A0 and c <= 0x30FF): ok = true                          # 片假名
		elif (c >= 0x3100 and c <= 0x312F): ok = true                          # 注音符号
		elif (c >= 0xFF01 and c <= 0xFF5E): ok = true                          # 全角标点/数字
		if not ok:
			has_symbol = true
			break
	if has_symbol:
		_show_banner("名称含无效字符" if GameManager.is_locale("zh") else "INVALID CHARACTERS")
		_play_click()
		return

	for blocked: String in BLOCKED_NAMES:
		if name == blocked:
			_show_banner("未找到该用户" if GameManager.is_locale("zh") else "USER NOT FOUND")
			_name_input.text = ""
			_name_input.grab_focus()
			_play_click()
			return

	_play_click()
	registration_complete.emit(name)


func _on_cancel() -> void:
	_play_click()
	registration_cancelled.emit()


## Truncate display name to MAX_DISPLAY_CHARS for in-game use.


# ── Animation ────────────────────────────────────────────────────

func _animate_enter() -> void:
	modulate.a = 0.0
	_content_card.scale = Vector2(0.96, 0.96)
	var tween := create_tween()
	tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.set_parallel(true)
	tween.tween_property(self, "modulate:a", 1.0, 0.5)
	tween.tween_property(_content_card, "scale", Vector2(1, 1), 0.5)
	tween.chain().tween_callback(_enable_interaction)


func _enable_interaction() -> void:
	_interactive = true


# ── Audio ────────────────────────────────────────────────────────

func _play_click() -> void:
	AudioManager.play_click()


# ── Input ────────────────────────────────────────────────────────

func _input(event: InputEvent) -> void:
	if not event.is_pressed():
		return

	if event.is_action_pressed("ui_cancel"):
		# If LineEdit has focus, unfocus it first (avoid losing typed text)
		if _name_input.has_focus():
			_name_input.release_focus()
			get_viewport().set_input_as_handled()
		else:
			registration_cancelled.emit()
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		if not _name_input.has_focus():
			_on_confirm()
			get_viewport().set_input_as_handled()
