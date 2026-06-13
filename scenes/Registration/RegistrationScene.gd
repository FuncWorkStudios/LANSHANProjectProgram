## RegistrationScene : Control
## Browser-simulated registration form for player name input.
## Port of RegistrationScene from App.tsx — redesigned with browser chrome,
## confirm button shadow, and input field focus highlight.
extends Control

signal registration_complete(player_name: String)
signal registration_cancelled()

# ---------------------------------------------------------------------------
# Internal state
# ---------------------------------------------------------------------------
var _player_name: String = ""
var _show_warning: bool = false
var _is_focused: bool = false

@onready var _name_input: LineEdit = %NameInput
@onready var _confirm_button: Button = %ConfirmButton
@onready var _cancel_button: Button = %CancelButton
@onready var _warning_label: Label = %WarningLabel
@onready var _browser_title: Label = %BrowserTitle
@onready var _page_title: Label = %PageTitle
@onready var _page_subtitle: Label = %PageSubtitle


# ===================================================================
# Lifecycle
# ===================================================================

func _ready() -> void:
	_create_browser_chrome()
	_create_button_shadow()
	_setup_ui()
	_name_input.grab_focus()
	_name_input.focus_entered.connect(_on_input_focused)
	_name_input.focus_exited.connect(_on_input_unfocused)


# ===================================================================
# Browser chrome (tab bar + address bar)
# ===================================================================

func _create_browser_chrome() -> void:
	# --- Tab bar ---
	var tab_bar := ColorRect.new()
	tab_bar.name = "TabBar"
	tab_bar.color = Color(0.871, 0.882, 0.902)   # #DEE1E6
	tab_bar.size = Vector2(size.x, 40)
	tab_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(tab_bar)

	# Tab bar bottom border
	var tab_border := ColorRect.new()
	tab_border.name = "TabBorder"
	tab_border.color = Color(0.714, 0.725, 0.745)   # #B6B9BE
	tab_border.size = Vector2(size.x, 1)
	tab_border.position = Vector2(0, 39)
	tab_border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(tab_border)

	# Active tab (simulated)
	var active_tab := ColorRect.new()
	active_tab.name = "ActiveTab"
	active_tab.color = Color.WHITE
	active_tab.size = Vector2(180, 32)
	active_tab.position = Vector2(60, 8)
	active_tab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(active_tab)

	var tab_label := Label.new()
	tab_label.name = "TabLabel"
	tab_label.text = "中考志愿填报"
	tab_label.position = Vector2(72, 12)
	tab_label.add_theme_color_override("font_color", Color(0.235, 0.251, 0.263))   # #3C4043
	tab_label.add_theme_font_size_override("font_size", 12)
	tab_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(tab_label)

	# Blue rotated square icon (simplified — just a blue square)
	var blue_dot := ColorRect.new()
	blue_dot.name = "BlueIcon"
	blue_dot.color = Color(0.259, 0.522, 0.957)   # #4285F4
	blue_dot.size = Vector2(12, 12)
	blue_dot.position = Vector2(222, 18)
	blue_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(blue_dot)

	# --- Address bar ---
	var addr_bar := ColorRect.new()
	addr_bar.name = "AddressBar"
	addr_bar.color = Color.WHITE
	addr_bar.size = Vector2(size.x, 48)
	addr_bar.position = Vector2(0, 40)
	addr_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(addr_bar)

	var addr_border := ColorRect.new()
	addr_border.name = "AddrBorder"
	addr_border.color = Color(0.91, 0.918, 0.925)   # #E8EAED
	addr_border.size = Vector2(size.x, 1)
	addr_border.position = Vector2(0, 87)
	addr_border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(addr_border)

	# URL input area (rounded)
	var url_bg := ColorRect.new()
	url_bg.name = "UrlBg"
	url_bg.color = Color(0.945, 0.953, 0.957)   # #F1F3F4
	url_bg.size = Vector2(500, 30)
	url_bg.position = Vector2(80, 49)
	url_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(url_bg)

	var url_label := Label.new()
	url_label.name = "UrlLabel"
	url_label.text = "     https://bori.gov.cn:6111/education/zhiyuantianbao?stu=1070020070205114514"
	url_label.position = Vector2(92, 52)
	url_label.add_theme_color_override("font_color", Color(0.235, 0.251, 0.263))
	url_label.add_theme_font_size_override("font_size", 13)
	url_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(url_label)

	# Lock icon (simplified as a blue label)
	var lock_icon := Label.new()
	lock_icon.name = "LockIcon"
	lock_icon.text = "🔒"
	lock_icon.position = Vector2(86, 50)
	lock_icon.add_theme_color_override("font_color", Color(0.102, 0.451, 0.91))   # #1A73E8
	lock_icon.add_theme_font_size_override("font_size", 14)
	lock_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(lock_icon)

	# --- Page background ---
	var page_bg := ColorRect.new()
	page_bg.name = "PageBg"
	page_bg.color = Color(0.941, 0.953, 0.961)   # #F0F3F5
	page_bg.size = Vector2(size.x, size.y - 88)
	page_bg.position = Vector2(0, 88)
	page_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(page_bg)


# ===================================================================
# Confirm button drop shadow
# ===================================================================

func _create_button_shadow() -> void:
	# Shadow behind confirm button (4px down-right)
	var shadow := ColorRect.new()
	shadow.name = "BtnShadow"
	shadow.color = Color(0, 0, 0, 0.1)
	shadow.size = _confirm_button.size
	var btn_pos: Vector2 = _confirm_button.position
	shadow.position = Vector2(btn_pos.x + 4, btn_pos.y + 4)
	shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Add shadow just behind the confirm button in the scene tree
	add_child(shadow)
	move_child(shadow, _confirm_button.get_index())


# ===================================================================
# UI Setup
# ===================================================================

func _setup_ui() -> void:
	var is_zh: bool = GameManager.get_settings().language == "ZH"
	_browser_title.text = "中考志愿填报" if is_zh else "Volunteer Registration System"
	_page_title.text = "帛日市教育局 中考志愿填报系统" if is_zh else "Bori Education Bureau - Entrance Exam Registration"
	_page_subtitle.text = "请确认身份信息。" if is_zh else "Please confirm your identity information."
	_confirm_button.text = "确定" if is_zh else "CONFIRM"
	_cancel_button.text = "取消" if is_zh else "CANCEL"
	_warning_label.text = "警告：还未输入姓名" if is_zh else "WARNING: NAME REQUIRED"
	_warning_label.visible = false

	# Style confirm button
	_confirm_button.add_theme_color_override("font_color", Color.WHITE)
	_confirm_button.add_theme_font_size_override("font_size", 24)
	_confirm_button.flat = false

	# Style cancel button
	_cancel_button.add_theme_font_size_override("font_size", 18)

	# Style input field
	_name_input.add_theme_font_size_override("font_size", 28)
	_name_input.add_theme_color_override("font_color", Color.BLACK)
	_name_input.placeholder_text = "请输入姓名" if is_zh else "Enter your name"

	_name_input.text_changed.connect(_on_name_changed)
	_confirm_button.pressed.connect(_on_confirm)
	_cancel_button.pressed.connect(_on_cancel)


# ===================================================================
# Input focus highlight
# ===================================================================

func _on_input_focused() -> void:
	# Highlight background to light blue
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.91, 0.941, 1.0)   # #E8F0FE
	style.set_corner_radius_all(4)
	_name_input.add_theme_stylebox_override("normal", style)


func _on_input_unfocused() -> void:
	_name_input.add_theme_stylebox_override("normal", null)


# ===================================================================
# Callbacks
# ===================================================================

func _on_name_changed(new_text: String) -> void:
	_player_name = new_text
	if _show_warning and not _player_name.strip_edges().is_empty():
		_show_warning = false
		_warning_label.visible = false


func _on_confirm() -> void:
	var name: String = _player_name.strip_edges()
	if name.is_empty():
		_show_warning = true
		_warning_label.visible = true
		_play_click()
		return
	_play_click()
	registration_complete.emit(name)


func _on_cancel() -> void:
	_play_click()
	registration_cancelled.emit()


# ===================================================================
# Audio
# ===================================================================

func _play_click() -> void:
	AudioManager.play_sfx("res://assets/Sfx/Choose.wav")


# ===================================================================
# Input
# ===================================================================

func _input(event: InputEvent) -> void:
	if not event.is_pressed():
		return

	if event.is_action_pressed("ui_cancel"):
		registration_cancelled.emit()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		if not _name_input.has_focus():
			_on_confirm()
			get_viewport().set_input_as_handled()
