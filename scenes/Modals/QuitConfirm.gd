## QuitConfirm : Control
## Self-contained modal dialog for confirming quit/exit.
## Creates all UI dynamically — simply instantiate and add_child.
## Port of QuitConfirmModal from App.tsx.
class_name QuitConfirm
extends Control

signal confirmed()
signal cancelled()

# ---------------------------------------------------------------------------
# Internal state
# ---------------------------------------------------------------------------
var _selected_index: int = 1   # Default to "No"
var _interactive: bool = false
var _band: Control
var _branding_box: Control
var _option_nodes: Array[Control] = []
var _options: Array[Dictionary] = [
	{"id": "yes", "title": "Yes", "zh": "是"},
	{"id": "no", "title": "No", "zh": "否"},
]

# Font resources — loaded in _ready()
var _font_tcm: Font = null
var _font_zh_title: Font = null
var _font_zh_body: Font = null
var _font_en_body: Font = null

const BAND_PADDING: float = 64.0
const OPTION_HEIGHT: float = 51.0


# ===================================================================
# Lifecycle
# ===================================================================

func _ready() -> void:
	# Load font resources
	_font_tcm = load(GameManager.FONT_TCM)
	_font_zh_title = load(GameManager.FONT_ZH_TITLE)
	_font_zh_body = load(GameManager.FONT_ZH_BODY)
	_font_en_body = load(GameManager.FONT_EN_BODY)

	AudioManager.set_menu_mode(true)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_create_backdrop()
	_create_band()
	_create_branding_box()
	_create_question()
	_create_options()
	_create_footer()
	_animate_enter()


# ===================================================================
# Backdrop (full-screen dark overlay)
# ===================================================================

func _create_backdrop() -> void:
	var backdrop := ColorRect.new()
	backdrop.name = "Backdrop"
	backdrop.color = Color(0, 0, 0, 0.6)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)


# ===================================================================
# Central band
# ===================================================================

func _create_band() -> void:
	_band = Control.new()
	_band.name = "Band"
	_band.set_anchors_preset(Control.PRESET_FULL_RECT)
	_band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_band)

	# Band background
	var band_bg := ColorRect.new()
	band_bg.name = "BandBg"
	band_bg.color = Color(0, 0, 0, 0.95)
	band_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	band_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_band.add_child(band_bg)

	# Top border line
	var top_border := ColorRect.new()
	top_border.name = "TopBorder"
	top_border.color = Color(1, 1, 1, 0.2)
	top_border.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top_border.size.y = 2
	top_border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_band.add_child(top_border)

	# Bottom border line
	var bottom_border := ColorRect.new()
	bottom_border.name = "BottomBorder"
	bottom_border.color = Color(1, 1, 1, 0.2)
	bottom_border.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom_border.size.y = 2
	bottom_border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_band.add_child(bottom_border)


# ===================================================================
# Branding box (overlapping top edge of band)
# ===================================================================

func _create_branding_box() -> void:
	_branding_box = Control.new()
	_branding_box.name = "BrandingBox"
	# Position: top-left, overlapping band top border
	_branding_box.position = Vector2(48, size.y / 2.0 - BAND_PADDING - 48)
	_branding_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_branding_box)

	# Shadow offset (10px right, 10px down, 10% white)
	var shadow := ColorRect.new()
	shadow.name = "Shadow"
	shadow.color = Color(1, 1, 1, 0.1)
	shadow.position = Vector2(10, 10)
	shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_branding_box.add_child(shadow)

	# White box
	var box_bg := ColorRect.new()
	box_bg.name = "BoxBg"
	box_bg.color = Color.WHITE
	box_bg.size = Vector2(0, 0)
	box_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_branding_box.add_child(box_bg)

	# English title → TCM font
	var en_title := Label.new()
	en_title.name = "EnTitle"
	en_title.text = "Quit"
	en_title.add_theme_color_override("font_color", Color.BLACK)
	en_title.add_theme_font_size_override("font_size", 72)
	en_title.position = Vector2(32, 16)
	en_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _font_tcm: en_title.add_theme_font_override("font", _font_tcm)
	_branding_box.add_child(en_title)

	# Chinese title → SemiBold font
	var zh_title := Label.new()
	zh_title.name = "ZhTitle"
	zh_title.text = "退出"
	zh_title.add_theme_color_override("font_color", Color.BLACK)
	zh_title.add_theme_font_size_override("font_size", 32)
	zh_title.position = Vector2(36, 104)
	zh_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _font_zh_title: zh_title.add_theme_font_override("font", _font_zh_title)
	_branding_box.add_child(zh_title)

	# Size the box to fit content
	box_bg.size = Vector2(220, 156)
	shadow.size = box_bg.size


# ===================================================================
# Question text
# ===================================================================

func _create_question() -> void:
	var question := Label.new()
	question.name = "Question"
	question.text = "确定退出吗？"
	question.position = Vector2(48, size.y - BAND_PADDING - 48)
	question.add_theme_color_override("font_color", Color(1, 1, 1, 0.8))
	question.add_theme_font_size_override("font_size", 28)
	question.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _font_zh_body: question.add_theme_font_override("font", _font_zh_body)
	add_child(question)


# ===================================================================
# Option items (Yes / No)
# ===================================================================

func _create_options() -> void:
	var container := VBoxContainer.new()
	container.name = "OptionsContainer"
	container.alignment = BoxContainer.ALIGNMENT_CENTER
	container.position = Vector2(size.x - 520, size.y / 2.0 - OPTION_HEIGHT)
	container.custom_minimum_size = Vector2(480, OPTION_HEIGHT * _options.size())
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(container)

	for i: int in range(_options.size()):
		var data: Dictionary = _options[i]
		var item: Control = _create_option_item(i, data)
		container.add_child(item)
		_option_nodes.append(item)

	_update_focus()


func _create_option_item(index: int, data: Dictionary) -> Control:
	var container := Control.new()
	container.name = "Option_" + str(index)
	container.custom_minimum_size = Vector2(480, OPTION_HEIGHT)
	container.mouse_filter = Control.MOUSE_FILTER_STOP

	# Sweep fill (white background that slides in)
	var sweep := ColorRect.new()
	sweep.name = "Sweep"
	sweep.color = Color.WHITE
	sweep.size = Vector2(480, OPTION_HEIGHT)
	sweep.scale = Vector2(0, 1)
	sweep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(sweep)

	# Content row
	var hbox := HBoxContainer.new()
	hbox.name = "Content"
	hbox.size = Vector2(480, OPTION_HEIGHT)
	hbox.alignment = BoxContainer.ALIGNMENT_END
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(hbox)

	# Spacer
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(16, 0)
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(spacer)

	# English option title → TCM font
	var title_label := Label.new()
	title_label.name = "Title"
	title_label.text = data.title
	title_label.add_theme_font_size_override("font_size", 42)
	title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _font_tcm: title_label.add_theme_font_override("font", _font_tcm)
	hbox.add_child(title_label)

	var spacer2 := Control.new()
	spacer2.custom_minimum_size = Vector2(12, 0)
	spacer2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(spacer2)

	# Chinese option label → SemiBold font
	var zh_label := Label.new()
	zh_label.name = "ZhLabel"
	zh_label.text = data.zh
	zh_label.add_theme_font_size_override("font_size", 24)
	zh_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _font_zh_title: zh_label.add_theme_font_override("font", _font_zh_title)
	hbox.add_child(zh_label)

	# Interaction
	container.mouse_entered.connect(_on_option_hovered.bind(index))
	container.gui_input.connect(_on_option_clicked.bind(index))
	container.set_meta("sweep", sweep)
	container.set_meta("title_label", title_label)
	container.set_meta("zh_label", zh_label)

	return container


# ===================================================================
# Footer
# ===================================================================

func _create_footer() -> void:
	var footer := Label.new()
	footer.name = "Footer"
	footer.text = "LANSHANProject 3.0.0  (C) FuncWork Studios"
	footer.position = Vector2(48, size.y - BAND_PADDING - 20)
	footer.add_theme_color_override("font_color", Color(1, 1, 1, 0.4))
	footer.add_theme_font_size_override("font_size", 12)
	footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _font_en_body: footer.add_theme_font_override("font", _font_en_body)
	add_child(footer)


# ===================================================================
# Focus management
# ===================================================================

func _update_focus() -> void:
	for i: int in range(_option_nodes.size()):
		var child: Control = _option_nodes[i]
		var sweep: ColorRect = child.get_meta("sweep")
		var title: Label = child.get_meta("title_label")
		var zh: Label = child.get_meta("zh_label")
		var is_focused: bool = i == _selected_index

		var sweep_tween := create_tween()
		sweep_tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUINT)
		if is_focused:
			sweep_tween.tween_property(sweep, "scale:x", 1.2, 0.3).from(0.0)
			sweep_tween.parallel().tween_property(sweep, "position:x", -60.0, 0.3)
		else:
			sweep_tween.tween_property(sweep, "scale:x", 0.0, 0.3)
			sweep_tween.parallel().tween_property(sweep, "position:x", 0.0, 0.3)

		title.add_theme_color_override("font_color", Color.BLACK if is_focused else Color.WHITE)
		zh.add_theme_color_override("font_color", Color.BLACK if is_focused else Color(1, 1, 1, 0.8))
		child.modulate.a = 1.0 if is_focused else 0.4


# ===================================================================
# Interaction
# ===================================================================

func _on_option_hovered(index: int) -> void:
	if not _interactive: return
	if _selected_index != index:
		_selected_index = index
		_update_focus()
		_play_click()


func _on_option_clicked(index: int, event: InputEvent) -> void:
	if not _interactive: return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_play_click()
		if index == 0:
			confirmed.emit()
		else:
			cancelled.emit()


func _input(event: InputEvent) -> void:
	if not _interactive: return
	if not event.is_pressed():
		return

	if event.is_action_pressed("ui_up") or event.is_action_pressed("ui_left"):
		_selected_index = 0
		_update_focus()
		_play_click()
		get_viewport().set_input_as_handled()

	elif event.is_action_pressed("ui_down") or event.is_action_pressed("ui_right"):
		_selected_index = 1
		_update_focus()
		_play_click()
		get_viewport().set_input_as_handled()

	elif event.is_action_pressed("ui_accept"):
		_play_click()
		if _selected_index == 0:
			confirmed.emit()
		else:
			cancelled.emit()
		get_viewport().set_input_as_handled()

	elif event.is_action_pressed("ui_cancel"):
		_play_click()
		cancelled.emit()
		get_viewport().set_input_as_handled()


# ===================================================================
# Animation
# ===================================================================

func _animate_enter() -> void:
	if not _band:
		return
	# Scale from right edge (pivot at x=1)
	_band.pivot_offset.x = _band.size.x
	_band.scale.x = 0.0
	modulate.a = 0.0

	var tween := create_tween()
	tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUINT)
	tween.tween_property(_band, "scale:x", 1.0, 0.4)
	tween.parallel().tween_property(self, "modulate:a", 1.0, 0.4)
	tween.tween_callback(_enable_interaction)


func _enable_interaction() -> void:
	_interactive = true


# ===================================================================
# Audio
# ===================================================================

func _play_click() -> void:
	AudioManager.play_sfx(AudioManager.SFX_CLICK)


# ===================================================================
# Cleanup
# ===================================================================

func _exit_tree() -> void:
	AudioManager.set_menu_mode(false)
