## RegistrationScene : Control
## 模拟浏览器的"志愿填报"表单，用于玩家姓名输入。
extends Control

signal registration_complete(player_name: String)
signal registration_cancelled()

const MAX_DISPLAY_CHARS: int = 8       # 游戏中显示的字符数
const MAX_INPUT_CHARS: int = 256      # 文本字段允许的字符数

# 预加载的已注册角色名称列表 — 拒绝这些名称
const BLOCKED_NAMES: Array[String] = preload("res://scripts/RegisteredNames.gd").NAMES

var _player_name: String = ""
var _show_warning: bool = false
var _interactive: bool = false


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
	_setup_chrome()
	_setup_labels()
	_setup_form()
	_setup_interaction()

	_name_input.max_length = MAX_INPUT_CHARS
	_name_input.caret_blink = true
	_name_input.caret_blink_interval = 0.5
	_name_input.grab_focus()


## 每次场景激活时由 SceneManager 调用。
## 重置所有状态，防止上一次会话的数据泄露。
func _on_enter() -> void:
	_player_name = ""
	_name_input.text = ""
	_name_input.editable = true
	_name_input.grab_focus()
	_refresh_translations()
	_hide_banner()
	_interactive = false
	_animate_enter()


func _refresh_translations() -> void:
	# @onready 节点 — 直接更新
	_tab_label.text = tr("中考志愿填报")
	@warning_ignore("static_called_on_instance")
	_tab_label.add_theme_font_override("font", GameManager.select_font(_tab_label.text, GameManager.font_zh_title, GameManager.font_tcm))
	_page_title.text = tr("帛日市教育局 中考志愿填报系统")
	@warning_ignore("static_called_on_instance")
	_page_title.add_theme_font_override("font", GameManager.select_font(_page_title.text, GameManager.font_zh_title, GameManager.font_tcm))
	_page_subtitle.text = tr("请确认身份信息。")
	@warning_ignore("static_called_on_instance")
	_page_subtitle.add_theme_font_override("font", GameManager.select_font(_page_subtitle.text, GameManager.font_zh_body, GameManager.font_en_body))
	_confirm_button.text = tr("确定")
	@warning_ignore("static_called_on_instance")
	_confirm_button.add_theme_font_override("font", GameManager.select_font(_confirm_button.text, GameManager.font_zh_title, GameManager.font_tcm))
	_toast_label.text = tr("请先在该网页中完成姓名填报内容。")
	@warning_ignore("static_called_on_instance")
	_toast_label.add_theme_font_override("font", GameManager.select_font(_toast_label.text, GameManager.font_zh_body, GameManager.font_en_body))
	_name_input.placeholder_text = tr("请输入姓名")
	# 表单部分 — 重建（先清除 _form_anchor 的子节点）
	for child in _form_anchor.get_children():
		child.queue_free()
	_setup_form()


func _on_exit() -> void:
	_interactive = false


# ── 浏览器装饰 ───────────────────────────────────────────────────────

func _setup_chrome() -> void:
	_tab_label.text = "  " + tr("中考志愿填报")
	_tab_label.add_theme_color_override("font_color", Color(0.15, 0.16, 0.18))
	_tab_label.add_theme_font_size_override("font_size", 13)
	@warning_ignore("static_called_on_instance")
	_tab_label.add_theme_font_override("font", GameManager.select_font(_tab_label.text, GameManager.font_zh_title, GameManager.font_tcm))

	_close_button.text = "X"
	_close_button.flat = true
	_close_button.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_close_button.add_theme_color_override("font_color", Color.BLACK)
	_close_button.add_theme_font_size_override("font_size", 20)
	_close_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if GameManager.font_tcm: _close_button.add_theme_font_override("font", GameManager.font_tcm)
	_close_button.pressed.connect(_on_cancel)

	var shadow := ColorRect.new()
	shadow.name = "ChromeShadow"
	@warning_ignore("int_as_enum_without_cast", "int_as_enum_without_match")
	shadow.layout_mode = 1
	shadow.anchor_left = 0.0; shadow.anchor_right = 1.0
	shadow.offset_top = 48; shadow.offset_bottom = 50
	shadow.color = Color(0, 0, 0, 0.12)
	shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shadow)


# ── 标签 ───────────────────────────────────────────────────────

func _setup_labels() -> void:
	_page_title.text = tr("帛日市教育局 中考志愿填报系统")
	_page_subtitle.text = tr("请确认身份信息。")

	_page_title.add_theme_font_size_override("font_size", 28)
	@warning_ignore("static_called_on_instance")
	_page_title.add_theme_font_override("font", GameManager.select_font(_page_title.text, GameManager.font_zh_title, GameManager.font_tcm))

	_page_subtitle.add_theme_font_size_override("font_size", 16)
	_page_subtitle.add_theme_color_override("font_color", Color(0, 0, 0, 0.55))
	@warning_ignore("static_called_on_instance")
	_page_subtitle.add_theme_font_override("font", GameManager.select_font(_page_subtitle.text, GameManager.font_zh_body, GameManager.font_en_body))

	_confirm_button.text = tr("确定")
	_confirm_button.add_theme_color_override("font_color", Color.WHITE)
	_confirm_button.add_theme_font_size_override("font_size", 22)
	@warning_ignore("static_called_on_instance")
	_confirm_button.add_theme_font_override("font", GameManager.select_font(_confirm_button.text, GameManager.font_zh_title, GameManager.font_tcm))
	_confirm_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	_confirm_button.pressed.connect(_on_confirm)

	_warning_banner.text = ""
	_warning_banner.add_theme_color_override("font_color", Color(0.85, 0.25, 0.1, 1))
	_warning_banner.add_theme_font_size_override("font_size", 16)
	@warning_ignore("static_called_on_instance")
	_warning_banner.add_theme_font_override("font", GameManager.select_font("", GameManager.font_zh_body, GameManager.font_en_body))
	_warning_banner.custom_minimum_size = Vector2(250, 0)
	_warning_banner.modulate.a = 0.0
	_warning_banner.visible = true

	_toast_label.text = tr("请先在该网页中完成姓名填报内容。")
	_toast_label.add_theme_font_size_override("font_size", 16)
	@warning_ignore("static_called_on_instance")
	_toast_label.add_theme_font_override("font", GameManager.select_font(_toast_label.text, GameManager.font_zh_body, GameManager.font_en_body))
	_toast.visible = false
	_toast.modulate.a = 0.0


# ── 表单 ─────────────────────────────────────────────────────────

func _setup_form() -> void:
	var ft: Control = Control.new()
	ft.name = "FormTable"
	@warning_ignore("int_as_enum_without_cast", "int_as_enum_without_match")
	ft.layout_mode = 1
	ft.anchors_preset = Control.PRESET_FULL_RECT
	ft.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_form_anchor.add_child(ft)

	const LEFT_W: float = 180.0

	# 照片面板（左侧，固定宽度）
	var photo_panel := Panel.new()
	photo_panel.name = "PhotoPanel"
	@warning_ignore("int_as_enum_without_cast", "int_as_enum_without_match")
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
	photo_lbl.text = tr("暂无照片")
	photo_lbl.set_anchors_preset(Control.PRESET_CENTER)
	photo_lbl.offset_left = -50.0; photo_lbl.offset_top = -16.0
	photo_lbl.offset_right = 50.0; photo_lbl.offset_bottom = 16.0
	photo_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	photo_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	photo_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	@warning_ignore("static_called_on_instance")
	photo_lbl.add_theme_font_override("font", GameManager.select_font(photo_lbl.text, GameManager.font_zh_title, GameManager.font_tcm))
	photo_panel.add_child(photo_lbl)

	# 垂直分隔线（2像素，与左侧面板边缘对齐）
	var divider := ColorRect.new()
	divider.color = Color.BLACK
	@warning_ignore("int_as_enum_without_cast", "int_as_enum_without_match")
	divider.layout_mode = 1
	divider.anchor_left = 0.0; divider.anchor_right = 0.0
	divider.anchor_top = 0.0; divider.anchor_bottom = 1.0
	divider.offset_left = LEFT_W; divider.offset_right = LEFT_W + 2.0
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ft.add_child(divider)

	# 右侧 — VBoxContainer 内的行，起始 y 坐标与照片相同
	var rows_box: VBoxContainer = VBoxContainer.new()
	rows_box.name = "RowsBox"
	@warning_ignore("int_as_enum_without_cast", "int_as_enum_without_match")
	rows_box.layout_mode = 1
	rows_box.anchor_left = 0.0; rows_box.anchor_right = 1.0
	rows_box.anchor_top = 0.0; rows_box.anchor_bottom = 1.0
	rows_box.offset_left = LEFT_W + 2.0
	rows_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ft.add_child(rows_box)

	var row_data: Array[Dictionary] = [
		{label = tr("姓名"),         is_input = true},
		{label = tr("性别"),         value = tr("男")},
		{label = tr("出生日期"),      value = "2007.02.05"},
		{label = tr("户籍所在地"),     value = tr("帛日市浮城区")},
		{label = tr("第一志愿"),      value = tr("帛日火兰山中学")},
		{label = tr("考生号"),        value = "1070020070205114514"},
	]

	for data: Dictionary in row_data:
		var row: Control = _make_form_row(data)
		rows_box.add_child(row)


func _make_form_row(data: Dictionary) -> Control:
	var row: Control = Control.new()
	row.custom_minimum_size = Vector2(0, 46)
	row.size_flags_horizontal = Control.SIZE_FILL
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var row_bg := ColorRect.new()
	row_bg.color = Color(0.91, 0.941, 1.0, 1)
	row_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	row_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(row_bg)

	# 底部分隔线
	var div := ColorRect.new()
	div.color = Color(0.8, 0.82, 0.86, 1)
	div.anchor_left = 0.0; div.anchor_right = 1.0; div.anchor_bottom = 1.0
	div.offset_top = -1.0
	div.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(div)

	# Label
	var lbl := Label.new()
	lbl.text = data.label
	@warning_ignore("int_as_enum_without_cast", "int_as_enum_without_match")
	lbl.layout_mode = 1
	lbl.anchor_left = 0.0; lbl.anchor_right = 0.35
	lbl.anchor_top = 0.0; lbl.anchor_bottom = 1.0
	lbl.offset_left = 12.0
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.add_theme_color_override("font_color", Color.BLACK)
	row.add_child(lbl)

	if data.get("is_input", false):
		# 将姓名输入框重新父化到此行
		var old_parent := _name_input.get_parent()
		if old_parent:
			old_parent.remove_child(_name_input)
		_name_input.visible = true
		@warning_ignore("int_as_enum_without_cast", "int_as_enum_without_match")
		_name_input.layout_mode = 1
		_name_input.anchor_left = 0.35; _name_input.anchor_right = 1.0
		_name_input.anchor_top = 0.0; _name_input.anchor_bottom = 1.0
		_name_input.offset_left = 8.0; _name_input.offset_right = -12.0
		_name_input.offset_top = 6.0; _name_input.offset_bottom = -6.0
		_name_input.placeholder_text = tr("请输入姓名")
		_name_input.add_theme_color_override("font_color", Color.BLACK)
		_name_input.add_theme_color_override("placeholder_color", Color(0.55, 0.55, 0.55, 1))
		_name_input.add_theme_font_size_override("font_size", 20)
		if not _name_input.text_changed.is_connected(_on_name_changed):
			_name_input.text_changed.connect(_on_name_changed)
		row.add_child(_name_input)
	else:
		var val := Label.new()
		val.text = data.value
		@warning_ignore("int_as_enum_without_cast", "int_as_enum_without_match")
		val.layout_mode = 1
		val.anchor_left = 0.35; val.anchor_right = 1.0
		val.anchor_top = 0.0; val.anchor_bottom = 1.0
		val.offset_left = 8.0; val.offset_right = -12.0
		val.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		val.mouse_filter = Control.MOUSE_FILTER_IGNORE
		val.add_theme_font_size_override("font_size", 18)
		val.add_theme_color_override("font_color", Color.BLACK)
		row.add_child(val)

	return row


# ── 点击外部 → 警告 ──────────────────────────────────────

func _setup_interaction() -> void:
	_content_card.mouse_filter = Control.MOUSE_FILTER_STOP
	_backdrop.gui_input.connect(_on_outside_clicked)
	_chrome_bar.gui_input.connect(_on_outside_clicked)


func _on_outside_clicked(event: InputEvent) -> void:
	if not _interactive: return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if _player_name.strip_edges().is_empty():
			_show_banner(tr("警告：还未输入姓名"))


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


# ── 回调函数 ────────────────────────────────────────────────────

func _on_name_changed(new_text: String) -> void:
	_player_name = new_text
	if _show_warning and not _player_name.strip_edges().is_empty():
		_hide_banner()


func _on_confirm() -> void:
	@warning_ignore("shadowed_variable_base_class")
	var name: String = _player_name.strip_edges()
	if name.is_empty():
		_show_banner(tr("警告：还未输入姓名"))
		_play_click()
		return

	if name.length() > MAX_DISPLAY_CHARS:
		_show_banner(tr("名称长度不匹配"))
		_play_click()
		return

	# 拒绝空格和符号 — 允许字母、数字、CJK、假名、注音符号
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
		_show_banner(tr("名称含无效字符"))
		_play_click()
		return

	for blocked: String in BLOCKED_NAMES:
		if name == blocked:
			_show_banner(tr("未找到该用户"))
			_name_input.text = ""
			_name_input.grab_focus()
			_play_click()
			return

	_play_click()
	registration_complete.emit(name)


func _on_cancel() -> void:
	_play_click()
	registration_cancelled.emit()


## 将显示名称截断到 MAX_DISPLAY_CHARS 以便在游戏中使用。


# ── 动画 ────────────────────────────────────────────────────

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


# ── 音频 ────────────────────────────────────────────────────────

func _play_click() -> void:
	AudioManager.play_click()


# ── 输入 ────────────────────────────────────────────────────────

func _input(event: InputEvent) -> void:
	if not event.is_pressed():
		return

	if event.is_action_pressed("ui_cancel"):
		# 如果 LineEdit 获得焦点，先取消焦点（避免丢失已输入文本）
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
