## BackBar : Control
## 可复用的 ESC 返回按钮栏。供所有子场景统一使用。
##   鼠标点击 → 派发 ui_cancel 输入事件，与按下 ESC 键走完全相同的 _input() 路径。
## set_hint() 可改键帽文字与说明文字（如 "␣" + "确认"）；set_simulate_cancel(false)
## 关掉取消语义，只发 pressed 信号 —— 过场动画里的"确认"栏用这个模式。
class_name BackBar
extends Control

## 点击左键（已过滤按下沿）。默认同时模拟 ui_cancel；关掉后由调用方接这个信号。
signal pressed()

## 点击时是否派发 ui_cancel（默认开 —— 各返回栏的既有行为）。
var _simulate_cancel: bool = true

var _esc_box: ColorRect
var _esc_label: Label
var _back_label: Label


func _init() -> void:
	_build()


func _build() -> void:

	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	offset_top = -96.0
	offset_bottom = 0.0

	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.6)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var border := ColorRect.new()
	border.color = Color(1, 1, 1, 0.05)
	border.set_anchors_preset(Control.PRESET_TOP_WIDE)
	border.offset_bottom = 1.0
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(border)

	# 键帽：白底方块 + 居中键名（宽度由 set_hint 按文字量出来）
	_esc_box = ColorRect.new()
	_esc_box.color = Color.WHITE
	_esc_box.position = Vector2(24, 24)
	_esc_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_esc_box.draw.connect(_on_esc_box_draw.bind(_esc_box))
	add_child(_esc_box)

	_esc_label = Label.new()
	_esc_label.position = Vector2(24, 24)
	_esc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_esc_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_esc_label.add_theme_color_override("font_color", Color.BLACK)
	_esc_label.add_theme_font_size_override("font_size", 14)
	_esc_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var key_font: Font = _build_key_font()
	if key_font:
		_esc_label.add_theme_font_override("font", key_font)
	add_child(_esc_label)

	_back_label = Label.new()
	_back_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.8))
	_back_label.add_theme_font_size_override("font_size", 24)
	_back_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_back_label)

	gui_input.connect(_on_click)
	mouse_entered.connect(_on_hover.bind(true))
	mouse_exited.connect(_on_hover.bind(false))

	set_hint("ESC", tr("返回"))


## 参数化键帽文字与说明文字（如 "␣" + "确认"）。键帽宽度按文字自适应：
## 单字符（␣ 这类符号）放大成一个方形键帽，多字符（ESC / SPACE）按字宽拉长。
func set_hint(p_key_text: String, p_label_text: String) -> void:
	var glyph_size: int = 22 if p_key_text.length() <= 1 else 14
	_esc_label.text = p_key_text
	_esc_label.add_theme_font_size_override("font_size", glyph_size)

	var text_width: float = 0.0
	var key_font: Font = _esc_label.get_theme_font("font")
	if key_font:
		text_width = key_font.get_string_size(p_key_text, HORIZONTAL_ALIGNMENT_LEFT, -1, glyph_size).x
	# +16 内缩：ESC（约 3 字符）仍收在原来的 48px 方键帽里，不改变各场景既有观感
	var box_width: float = maxf(48.0, ceilf(text_width) + 16.0)
	_esc_box.size = Vector2(box_width, 48.0)
	_esc_label.size = Vector2(box_width, 48.0)

	_back_label.text = p_label_text
	_back_label.position = Vector2(24.0 + box_width + 16.0, 28.0)
	_apply_back_font()


## 关闭"点击模拟 ui_cancel"：过场里的确认栏只需要 pressed 信号，
## 不该把取消语义透给身后的场景。
func set_simulate_cancel(p_enabled: bool) -> void:
	_simulate_cancel = p_enabled


func set_language() -> void:
	set_hint(_esc_label.text, tr("返回"))


## 工厂：创建 BackBar 并挂载到 parent。返回路径经注入的 ui_cancel 走场景 _input，
## 与 ESC 完全一致，无需回调连接；点击音由 BackBar 自身播放。
static func attach(parent: Control) -> BackBar:
	var bar: BackBar = BackBar.new()
	parent.add_child(bar)
	return bar


## 键帽字体：TCM 只有拉丁字形 —— "␣" 这类符号要靠中文正文兜底，否则是豆腐块。
func _build_key_font() -> Font:
	var base: Font = GameManager.font_tcm
	var fallback: Font = GameManager.font_zh_body
	if base and fallback:
		var stack := FontVariation.new()
		stack.base_font = base
		var fallbacks: Array[Font] = [fallback]
		stack.fallbacks = fallbacks
		return stack
	return base


## 说明文字字体按当前文本选（中文用标题字重，拉丁用 TCM）。
func _apply_back_font() -> void:
	@warning_ignore("static_called_on_instance")
	var font: Font = GameManager.select_font(_back_label.text, GameManager.font_zh_title, GameManager.font_tcm)
	if font:
		_back_label.add_theme_font_override("font", font)


func _on_click(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		AudioManager.play_click()
		pressed.emit()
		if not _simulate_cancel:
			return
		# 模拟 ui_cancel 按键事件，使鼠标点击与按下 ESC 走完全相同的 _input() 路径
		var ev := InputEventAction.new()
		ev.action = "ui_cancel"
		ev.pressed = true
		Input.parse_input_event(ev)


func _on_hover(hovered: bool) -> void:
	var t := create_tween().set_parallel(true)
	t.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	t.tween_property(_esc_box, "color", Color.BLACK if hovered else Color.WHITE, 0.15)
	t.tween_property(_esc_label, "theme_override_colors/font_color", Color.WHITE if hovered else Color.BLACK, 0.15)
	_esc_box.set_meta("_bb_hovered", hovered)
	_esc_box.queue_redraw()


func _on_esc_box_draw(box: ColorRect) -> void:
	if not box.has_meta("_bb_hovered") or not box.get_meta("_bb_hovered"):
		return
	box.draw_rect(Rect2(Vector2.ZERO, box.size), Color.WHITE, false, 1.0)
