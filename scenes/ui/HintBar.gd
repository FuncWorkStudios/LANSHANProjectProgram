## HintBar : Control
## 可复用按键提示栏 — "键位白框 + 键名 + 说明文字"成组水平排列。
## 供 VNInterface（底部控制提示：可点击、状态着色）与
## PictureViewer（右下角导航提示：静态）等场景复用。
## 组件保持无业务逻辑：分组通过 id 存取，状态颜色由使用方驱动。
## 点击音由组件统一播放（同 BackBar 约定），回调内不要重复调用 play_click。
class_name HintBar
extends Control

const KEY_BOX_HEIGHT: float = 36.0
const KEY_FONT_SIZE_DEFAULT: int = 16
const DESC_FONT_SIZE: int = 12

# 默认配色 — 与 VNInterface 原实现一致；使用方可用 set_hint_colors 覆盖
const DEFAULT_DESC_COLOR: Color = Color(1, 1, 1, 0.3)
const DEFAULT_BOX_COLOR: Color = Color(1, 1, 1, 0.15)
const DEFAULT_KEY_COLOR: Color = Color(1, 1, 1, 0.5)

var _hbox: HBoxContainer = null
var _key_first: bool = true
var _group_min_size: Vector2 = Vector2.ZERO
var _groups: Dictionary = {}   # id: String → {"group": Control, "box": ColorRect, "key": Label, "desc": Label}


## 初始化布局。必须在 add_hint 之前调用一次。
##   p_key_first  — true: [键框][说明]（画廊风格）；false: [说明][键框]（VN 风格）
##   p_separation — 组间距
##   p_with_bg    — 是否自建整条背景（使用方已有背景时传 false）
##   p_bg_alpha   — 背景不透明度（p_with_bg 为 true 时生效）
##   p_centered   — 组整体居中（false 为靠左）
##   p_group_min_size — 每组最小尺寸（Vector2.ZERO 表示自适应）
func setup(p_key_first: bool, p_separation: int, p_with_bg: bool,
		p_bg_alpha: float, p_centered: bool,
		p_group_min_size: Vector2 = Vector2.ZERO) -> void:
	_key_first = p_key_first
	_group_min_size = p_group_min_size

	if p_with_bg:
		var bg := ColorRect.new()
		bg.name = "HintBg"
		bg.color = Color(0, 0, 0, p_bg_alpha)
		bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(bg)

	_hbox = HBoxContainer.new()
	_hbox.name = "HintGroups"
	_hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hbox.alignment = BoxContainer.ALIGNMENT_CENTER if p_centered else BoxContainer.ALIGNMENT_BEGIN
	_hbox.add_theme_constant_override("separation", p_separation)
	_hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hbox)


## 追加一个提示组。key_box_width 允许宽键帽（如 "ESC" 用 48）。
func add_hint(id: String, key_text: String, desc_text: String,
		key_box_width: float = KEY_BOX_HEIGHT,
		key_font_size: int = KEY_FONT_SIZE_DEFAULT) -> void:
	var group := Control.new()
	group.name = "Hint_" + id
	if _group_min_size != Vector2.ZERO:
		group.custom_minimum_size = _group_min_size
	group.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	group.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var inner := HBoxContainer.new()
	inner.name = "Inner"
	inner.set_anchors_preset(Control.PRESET_FULL_RECT)
	inner.alignment = BoxContainer.ALIGNMENT_CENTER
	inner.add_theme_constant_override("separation", 8)
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	group.add_child(inner)

	# 键位框 + 键名
	var box := ColorRect.new()
	box.name = "KeyBox"
	box.custom_minimum_size = Vector2(key_box_width, KEY_BOX_HEIGHT)
	box.color = DEFAULT_BOX_COLOR
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var key_lbl := Label.new()
	key_lbl.name = "KeyLabel"
	key_lbl.text = key_text
	key_lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	key_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	key_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	key_lbl.add_theme_font_size_override("font_size", key_font_size)
	key_lbl.add_theme_color_override("font_color", DEFAULT_KEY_COLOR)
	key_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if GameManager.font_tcm:
		key_lbl.add_theme_font_override("font", GameManager.font_tcm)
	box.add_child(key_lbl)

	# 说明文字
	var desc_lbl := Label.new()
	desc_lbl.name = "DescLabel"
	desc_lbl.text = desc_text
	desc_lbl.add_theme_font_size_override("font_size", DESC_FONT_SIZE)
	desc_lbl.add_theme_color_override("font_color", DEFAULT_DESC_COLOR)
	desc_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE

	if _key_first:
		inner.add_child(box)
		inner.add_child(desc_lbl)
	else:
		inner.add_child(desc_lbl)
		inner.add_child(box)

	_hbox.add_child(group)
	_groups[id] = {"group": group, "box": box, "key": key_lbl, "desc": desc_lbl}


## 使提示组可点击 — 点击播放统一音效后调用 callback（命名函数）。
func connect_hint(id: String, callback: Callable) -> void:
	if not _groups.has(id):
		return
	var group: Control = _groups[id]["group"]
	group.mouse_filter = Control.MOUSE_FILTER_STOP
	group.gui_input.connect(_on_group_input.bind(callback))


func set_hint_visible(id: String, p_visible: bool) -> void:
	if not _groups.has(id):
		return
	(_groups[id]["group"] as Control).visible = p_visible


## 状态着色 — 说明 / 键位框 / 键名 三色一次设置。
func set_hint_colors(id: String, desc_color: Color, box_color: Color, key_color: Color) -> void:
	if not _groups.has(id):
		return
	(_groups[id]["desc"] as Label).add_theme_color_override("font_color", desc_color)
	(_groups[id]["box"] as ColorRect).color = box_color
	(_groups[id]["key"] as Label).add_theme_color_override("font_color", key_color)


func set_desc_text(id: String, text: String) -> void:
	if not _groups.has(id):
		return
	(_groups[id]["desc"] as Label).text = text


func set_desc_font(id: String, font: Font) -> void:
	if not _groups.has(id) or font == null:
		return
	(_groups[id]["desc"] as Label).add_theme_font_override("font", font)


func _on_group_input(event: InputEvent, callback: Callable) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		AudioManager.play_click()
		callback.call()
