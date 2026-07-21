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

# 默认配色 — 白色正方形键框 + 黑键名；使用方可用 set_hint_colors 覆盖
const DEFAULT_DESC_COLOR: Color = Color(1, 1, 1, 0.3)
const DEFAULT_BOX_COLOR: Color = Color.WHITE
const DEFAULT_KEY_COLOR: Color = Color.BLACK

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
	# 用 HBoxContainer 作为组容器，使其自然包裹内容（键框 + 说明文字），
	# 避免 Control + 锚定内层 HBox 的循环依赖导致宽度坍缩为零。
	var group := HBoxContainer.new()
	group.name = "Hint_" + id
	if _group_min_size != Vector2.ZERO:
		group.custom_minimum_size = _group_min_size
	group.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	group.alignment = BoxContainer.ALIGNMENT_CENTER
	group.add_theme_constant_override("separation", 8)
	group.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# 键位方框 — ColorRect + draw 信号绘边框实现 "反色时白边" 效果
	var box := ColorRect.new()
	box.name = "KeyBox"
	box.custom_minimum_size = Vector2(key_box_width, KEY_BOX_HEIGHT)
	box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.color = DEFAULT_BOX_COLOR
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.draw.connect(_on_key_box_draw.bind(box))

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
	desc_lbl.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	desc_lbl.add_theme_font_size_override("font_size", DESC_FONT_SIZE)
	desc_lbl.add_theme_color_override("font_color", DEFAULT_DESC_COLOR)
	desc_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE

	if _key_first:
		group.add_child(box)
		group.add_child(desc_lbl)
	else:
		group.add_child(desc_lbl)
		group.add_child(box)

	_hbox.add_child(group)
	_groups[id] = {"group": group, "box": box, "key": key_lbl, "desc": desc_lbl}


## 使提示组可点击 — 点击播放统一音效后调用 callback（命名函数）。
func connect_hint(id: String, callback: Callable) -> void:
	if not _groups.has(id):
		return
	var group: Control = _groups[id]["group"]
	group.mouse_filter = Control.MOUSE_FILTER_STOP
	group.gui_input.connect(_on_group_input.bind(callback))


## 使提示组可点击 — 点击时派发输入动作事件，与按键走相同的 _input() 路径。
func connect_hint_action(id: String, action_name: String) -> void:
	if not _groups.has(id):
		return
	var group: Control = _groups[id]["group"]
	group.mouse_filter = Control.MOUSE_FILTER_STOP
	group.gui_input.connect(_on_group_action_input.bind(action_name))


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


func _on_group_action_input(event: InputEvent, action_name: String) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		AudioManager.play_click()
		var ev := InputEventAction.new()
		ev.action = action_name
		ev.pressed = true
		Input.parse_input_event(ev)


## 设置状态类键位的激活态 — 反色（黑底白字）+ 白色细边框。
## 取消激活时仅移除边框，颜色由 set_hint_colors 恢复。
func set_hint_active(id: String, active: bool) -> void:
	if not _groups.has(id):
		return
	var box: ColorRect = _groups[id]["box"]
	var key: Label = _groups[id]["key"]

	if active:
		box.color = Color.BLACK
		key.add_theme_color_override("font_color", Color.WHITE)
		box.set_meta("_hb_active", true)
	else:
		box.set_meta("_hb_active", false)
	box.queue_redraw()


## draw 信号回调 — 在激活态的键框上绘制 1px 白色边框。
func _on_key_box_draw(box: ColorRect) -> void:
	if not box.has_meta("_hb_active") or not box.get_meta("_hb_active"):
		return
	box.draw_rect(Rect2(Vector2.ZERO, box.size), Color.WHITE, false, 1.0)
