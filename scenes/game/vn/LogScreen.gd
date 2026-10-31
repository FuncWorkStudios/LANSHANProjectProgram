## LogScreen : Control
## 对话历史叠加层 —— VN 内按 Z 打开。
##
## 视觉构成（自下而上）：
##   BlurBackdrop  全屏背景模糊（shaders/backdrop_blur.gdshader 采样屏幕纹理），
##                 两趟渐进模糊 + 一趟 BackBufferCopy；只负责绘制 →
##                 mouse_filter = IGNORE，不吃滚轮/点击。
##   Backdrop      半透明黑幕（tscn 里已设为 IGNORE）。
##   标题 / 条目 / 提示栏
##
## 开启动画：背景由「清晰」渐变到「虚化」——只动模糊半径（0 → 目标），
## 黑幕与正文同时淡入；关闭时反向退回清晰。
##
## 条目排版：每段对话一行 = 右对齐的说话者列 + 富文本正文列，
## 用容器排版让富文本换行后行高自动撑开。段与段之间只留间距，
## 不画任何分割线。
##
## 正文走与 VNInterface 对话框完全相同的管线（顺序也不能变）：
##   {player}        → 玩家名
##   *文字*          → [i]文字[/i]            （斜体：simfang / timesi）
##   ==文字（注释）== → [url=注释]文字[/url]    （悬停弹出注释气泡）
##   非中文语种再把 CJK 片段包进 [font=…] 回退字体
class_name LogScreen
extends Control

signal close_requested()

# ── 背景模糊 ──────────────────────────────────────────────
## 毛玻璃组件 —— 与 TabMenu 共用同一份实现，两个菜单的背景观感必须一致

# ── 条目排版 ──────────────────────────────────────────────
## 段与段之间的间距 —— 取代原先的白色分割线
const ENTRY_SEPARATION: int = 22
## 说话者列宽（右对齐）与它到正文的间距
const NAME_COLUMN_WIDTH: float = 140.0
const NAME_TEXT_GAP: int = 12
## 字号：姓名 / 正文
const NAME_FONT_SIZE: int = 17
const BODY_FONT_SIZE: int = 19
## 注释气泡最大宽度（视口比例）与上限
const TOOLTIP_MAX_RATIO: float = 0.4
const TOOLTIP_MAX_WIDTH: float = 500.0
## 气泡的最小宽度，避免极短注释变成一条细线
const TOOLTIP_MIN_WIDTH: float = 72.0
## 气泡内边距之和（与 _make_tooltip() 里 stylebox 的左右 content_margin 一致）
const TOOLTIP_PAD_X: float = 24.0

var _entries: Array[Dictionary] = []
var _is_open: bool = false
var _anim_tween: Tween = null

# 背景模糊层 —— 脚本创建（和 Backdrop 一样只画不接受输入）
var _blur: BackdropBlur = null
# 注释气泡 —— 第一次悬停时创建
var _tooltip: Label = null

# 缓存的字体资源（在 _ready 中一次加载）
var _cached_fz_body: Font = null
var _cached_fz_title: Font = null
var _cached_fen_body: Font = null
var _cached_ftcm: Font = null
var _cached_fz_em: Font = null
var _cached_fen_em: Font = null
var _em_regex: RegEx = null
var _ann_regex: RegEx = null

@onready var _backdrop: ColorRect = $Backdrop
@onready var _title_label: Label = $TitleLabel
@onready var _scroll: ScrollContainer = $EntryScroll
@onready var _list: VBoxContainer = $EntryScroll/EntryList
@onready var _hint_bar: Control = $HintBar


func _ready() -> void:
	_cached_fz_body = load(GameManager.FONT_ZH_BODY)
	_cached_fz_title = load(GameManager.FONT_ZH_TITLE)
	_cached_fen_body = load(GameManager.FONT_EN_BODY)
	_cached_ftcm = load(GameManager.FONT_TCM)
	_cached_fz_em = load(GameManager.FONT_ZH_EMPHASIS)
	_cached_fen_em = load(GameManager.FONT_EN_EMPHASIS)
	_em_regex = RegEx.new()
	_em_regex.compile(r"\*(.+?)\*")
	_ann_regex = RegEx.new()
	_ann_regex.compile(r"==(.+?)[\(（](.+?)[\)）]==")
	_setup_title()
	_setup_hint_bar()
	_setup_blur_backdrop()
	_apply_scrim_alpha()
	_setup_scroll()
	visible = false
	mouse_filter = MOUSE_FILTER_STOP
	gui_input.connect(_swallow)


# ===================================================================
# 背景模糊 —— 半透明黑幕后面的画面
# ===================================================================

## 造一层全屏毛玻璃，垫在 Backdrop 与所有文字之下。
##
## 实现全部在共用组件 BackdropBlur 里（两趟渐进模糊 + BackBufferCopy），
## TabMenu 用的是同一个组件 —— 两个菜单的背景必须完全一致。
## 组件自身 mouse_filter = IGNORE，绝不会吃掉本列表的滚轮与点击。
func _setup_blur_backdrop() -> void:
	_blur = BackdropBlur.new()
	_blur.name = "BlurBackdrop"
	add_child(_blur)
	# 垫在 Backdrop / 标题 / 列表 / 提示栏之下
	move_child(_blur, 0)


## 黑幕不透明度取共用常量 —— 与 TabMenu 保持同一个值，别再各写一份。
func _apply_scrim_alpha() -> void:
	_backdrop.color.a = BackdropBlur.SCRIM_ALPHA


func _setup_scroll() -> void:
	# 段间距 —— 唯一的「分隔」手段
	_list.add_theme_constant_override("separation", ENTRY_SEPARATION)
	# 正文自动换行，不需要横向滚动；关掉可避免长行把条目撑出屏幕
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED


func _setup_title() -> void:
	_title_label.add_theme_font_size_override("font_size", 22)
	_title_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.4))
	@warning_ignore("static_called_on_instance")
	var tf: Font = GameManager.select_font(_title_label.text, _cached_fz_title, _cached_ftcm)
	if tf: _title_label.add_theme_font_override("font", tf)


func _setup_hint_bar() -> void:
	if not _hint_bar:
		return

	# 使用统一 HintBar 组件 — key_first（键框在前）、组间距 32、自带 0.9 黑背景、居中、组 110×72
	var hb := HintBar.new()
	hb.setup(true, 32, true, 0.9, true, Vector2(110, 72))
	hb.set_anchors_preset(Control.PRESET_FULL_RECT)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint_bar.add_child(hb)

	hb.add_hint("esc", "ESC", tr("Close"), 36.0, 13)
	hb.connect_hint_action("esc", "ui_cancel")
	hb.add_hint("z", "Z", tr("Close"))
	hb.connect_hint_action("z", "vn_log")

	# 白底黑键 + 说明文字
	hb.set_hint_colors("esc", Color(1, 1, 1, 0.3), Color.WHITE, Color.BLACK)
	hb.set_hint_colors("z", Color(1, 1, 1, 0.3), Color.WHITE, Color.BLACK)

	var desc_font: Font = _cached_ftcm if _cached_ftcm else GameManager.font_tcm
	if desc_font:
		hb.set_desc_font("esc", desc_font)
		hb.set_desc_font("z", desc_font)


func open(entries: Array[Dictionary]) -> void:
	_entries = entries
	_is_open = true
	visible = true
	_kill_anim()
	_hide_tooltip()

	if get_parent():
		position = Vector2.ZERO
		size = get_parent().size

	# 每次打开都从「清晰」起跑（分辨率/全屏状态也可能变过）
	_blur.set_amount(0.0)

	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()

	if _entries.is_empty():
		_list.add_child(_make_empty_label())
	else:
		_build_entries()

	modulate.a = 0.0
	_anim_tween = create_tween()
	_anim_tween.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	_anim_tween.tween_property(self, "modulate:a", 1.0, 0.3)
	# 清晰 → 模糊：只动半径，黑幕与正文同步淡入
	_blur.blur_in()

	if not _entries.is_empty():
		# 富文本的行高要等布局算完才准 —— 放两帧再贴底
		await get_tree().process_frame
		await get_tree().process_frame
		if not _is_open:
			return
		_scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)


func close() -> void:
	_is_open = false
	_hide_tooltip()
	_kill_anim()
	_anim_tween = create_tween()
	_anim_tween.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	_anim_tween.tween_property(self, "modulate:a", 0.0, 0.2)
	_anim_tween.tween_callback(_on_close_done)
	# 模糊 → 清晰
	_blur.blur_out()


func _on_close_done() -> void:
	visible = false
	close_requested.emit()


# ===================================================================
# 条目构建
# ===================================================================

func _build_entries() -> void:
	var is_zh: bool = _is_zh()
	for entry: Dictionary in _entries:
		_list.add_child(_make_entry_row(entry, is_zh))


## 一段对话 = 一行：说话者列（固定宽、右对齐）+ 正文列（富文本、自动换行）。
## 用容器排版，正文换行后行高由 RichTextLabel.fit_content 自动撑开，
## 不需要再手动量字宽/字高。
func _make_entry_row(entry: Dictionary, is_zh: bool) -> HBoxContainer:
	var who: String = str(entry.get("who", ""))
	var text: String = str(entry.get("en", "")) if not is_zh else str(entry.get("zh", ""))
	if text.is_empty():
		text = str(entry.get("zh", ""))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", NAME_TEXT_GAP)
	row.mouse_filter = MOUSE_FILTER_IGNORE
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	row.add_child(_make_name_label(who, is_zh))
	row.add_child(_make_body_label(text, is_zh))
	return row


func _make_name_label(who: String, is_zh: bool) -> Label:
	var name_lbl := Label.new()
	name_lbl.text = who
	name_lbl.custom_minimum_size = Vector2(NAME_COLUMN_WIDTH, 0.0)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	# 顶部对齐 + 不拉伸：名字永远贴着第一行文字，不被长正文拉到底部
	name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	name_lbl.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	name_lbl.add_theme_font_size_override("font_size", NAME_FONT_SIZE)
	name_lbl.add_theme_color_override("font_color", Color(1, 1, 1, 0.5))
	name_lbl.mouse_filter = MOUSE_FILTER_IGNORE

	# 字体回退：带有 CJK 字符的名称需要 CJK 字体，无论地区如何
	var has_cjk: bool = false
	for ch in who:
		@warning_ignore("static_called_on_instance")
		if GameManager._is_cjk(ch):
			has_cjk = true
			break
	if has_cjk or is_zh:
		if _cached_fz_title: name_lbl.add_theme_font_override("font", _cached_fz_title)
	elif _cached_ftcm:
		name_lbl.add_theme_font_override("font", _cached_ftcm)
	return name_lbl


## 正文 RichTextLabel —— 布局要点：
##   · fit_content = true       高度随内容（含换行）撑开，容器排版不会压行
##   · EXPAND_FILL              拿满剩余宽度，换行点才正确
##   · scroll_active = false    自己是正文不是滚动区，滚轮留给 ScrollContainer
##   · mouse_filter = PASS      需要鼠标悬停才能弹注释气泡（IGNORE 就收不到了）
func _make_body_label(raw: String, is_zh: bool) -> RichTextLabel:
	var body := RichTextLabel.new()
	body.bbcode_enabled = true
	body.scroll_active = false
	body.fit_content = true
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_FILL
	body.mouse_filter = MOUSE_FILTER_PASS
	body.add_theme_color_override("default_color", Color(1, 1, 1, 0.85))
	body.add_theme_font_size_override("normal_font_size", BODY_FONT_SIZE)

	# 正文字体：中文用 CJK 正文，英文用拉丁正文字体（CJK 由 BBCode 回退）
	var normal_font: Font = _cached_fz_body if is_zh else _cached_fen_body
	if normal_font == null:
		normal_font = _cached_fz_body
	if normal_font:
		body.add_theme_font_override("normal_font", normal_font)

	# 强调字体：与 VNInterface 完全一致（[i] → 中文仿宋 / 拉丁斜体）
	if _cached_fz_em:
		body.add_theme_font_override("italics_font", _cached_fz_em)
		body.add_theme_font_size_override("italics_font_size", BODY_FONT_SIZE)
	if _cached_fen_em:
		body.add_theme_font_override("bold_italics_font", _cached_fen_em)
		body.add_theme_font_size_override("bold_italics_font_size", BODY_FONT_SIZE)

	body.text = _format_body(raw, is_zh)
	body.meta_hover_started.connect(_on_annotation_hover_started)
	body.meta_hover_ended.connect(_on_annotation_hover_ended)
	return body


func _make_empty_label() -> Label:
	var noop := Label.new()
	noop.text = "No data"
	noop.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	noop.custom_minimum_size = Vector2(0, 200)
	noop.size_flags_horizontal = Control.SIZE_FILL
	noop.add_theme_font_size_override("font_size", 24)
	noop.add_theme_color_override("font_color", Color(1, 1, 1, 0.25))
	noop.mouse_filter = MOUSE_FILTER_IGNORE
	@warning_ignore("static_called_on_instance")
	var nf: Font = GameManager.select_font(noop.text, _cached_fz_title, _cached_ftcm)
	if nf: noop.add_theme_font_override("font", nf)
	return noop


# ===================================================================
# 富文本 —— 与 VNInterface._update_dialogue_display() 同一套管线
# ===================================================================

## 强调 / 注释标记 → BBCode，顺序与主场景一致（先强调，再注释，
## 最后才做 CJK 字体回退 —— 否则回退标签里的 "=" 会干扰注释正则）。
func _format_body(raw: String, is_zh: bool) -> String:
	if raw.is_empty():
		return raw
	var text: String = raw.replace("{player}", GameManager.player_name)
	if _em_regex:
		text = _em_regex.sub(text, "[i]$1[/i]", true)
	if _ann_regex:
		text = _ann_regex.sub(text, "[url=$2]$1[/url]", true)
	if not is_zh:
		text = GameManager.wrap_font_fallback(text, GameManager.FONT_EN_BODY, GameManager.FONT_ZH_BODY)
	return text


# ===================================================================
# 注释气泡 —— 悬停 [url] 标签时显示
# ===================================================================

func _on_annotation_hover_started(meta: Variant) -> void:
	var tip: String = str(meta).strip_edges()
	if tip.is_empty():
		_hide_tooltip()
		return
	if _tooltip == null:
		_tooltip = _make_tooltip()
	if _tooltip == null:
		return
	_tooltip.text = tip
	_place_tooltip()
	_tooltip.visible = true


func _on_annotation_hover_ended(_meta: Variant = "") -> void:
	_hide_tooltip()


func _make_tooltip() -> Label:
	var tip := Label.new()
	tip.name = "AnnotationTooltip"
	tip.z_index = 100
	tip.visible = false
	tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip.add_theme_color_override("font_color", Color.BLACK)
	tip.add_theme_font_size_override("font_size", 16)
	if _cached_fz_body:
		tip.add_theme_font_override("font", _cached_fz_body)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(1, 1, 1, 0.96)
	style.border_color = Color(0, 0, 0, 0.35)
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 0
	style.corner_radius_top_right = 0
	style.corner_radius_bottom_left = 0
	style.corner_radius_bottom_right = 0
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	style.shadow_size = 8
	style.shadow_offset = Vector2(3, 3)
	style.shadow_color = Color(0, 0, 0, 0.3)
	tip.add_theme_stylebox_override("normal", style)

	add_child(tip)
	return tip


## 贴光标放置：优先光标上方，放不下就放下方；整体钳在视口内。
##
## 宽度必须自己算，不能用 get_minimum_size().x —— 中文在 AUTOWRAP_WORD_SMART
## 下"每个字都能断行"，最小宽度只有**一个字**那么宽，直接拿来当宽度就会变成
## 竖排一条（旧 bug）。正确做法：
##   1) 宽度取「不换行」的自然宽度 + 内边距，超过上限才截断；
##   2) 宽度定下来之后再量换行高度（此时 get_minimum_size().y 才是对的）。
func _place_tooltip() -> void:
	if _tooltip == null:
		return
	var vs: Vector2 = get_viewport().get_visible_rect().size
	var mp: Vector2 = get_viewport().get_mouse_position()
	var max_w: float = minf(vs.x * TOOLTIP_MAX_RATIO, TOOLTIP_MAX_WIDTH)
	var max_h: float = vs.y * 0.5

	# 1) 宽度
	var want_w: float = max_w
	var font: Font = _tooltip.get_theme_font("font")
	if font:
		var fsize: int = _tooltip.get_theme_font_size("font_size")
		want_w = font.get_string_size(
				_tooltip.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x + TOOLTIP_PAD_X
	var width: float = clampf(want_w, TOOLTIP_MIN_WIDTH, max_w)

	# 2) 高度（宽度定下来之后）
	_tooltip.size = Vector2(width, 0.0)
	var height: float = clampf(_tooltip.get_minimum_size().y, 0.0, max_h)
	_tooltip.size = Vector2(width, height)

	# 3) 位置
	const MARGIN: float = 8.0
	var py: float = mp.y - height - MARGIN
	if py < MARGIN:
		py = mp.y + 24.0
	py = clampf(py, MARGIN, maxf(MARGIN, vs.y - height - MARGIN))
	var px: float = clampf(mp.x + 16.0, MARGIN, maxf(MARGIN, vs.x - width - MARGIN))
	_tooltip.position = Vector2(px, py)


func _hide_tooltip() -> void:
	if _tooltip:
		_tooltip.visible = false


# ===================================================================
# 滚动 & 输入
# ===================================================================

func _smooth_scroll_to(target: float) -> void:
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_property(_scroll, "scroll_vertical", target, 0.25)


func _input(event: InputEvent) -> void:
	if not _is_open: return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("vn_log"):
		close()
		get_viewport().set_input_as_handled()
		return
	if not event.is_pressed(): return
	if event.is_action_pressed("ui_up"):
		var bar := _scroll.get_v_scroll_bar()
		_hide_tooltip()
		_smooth_scroll_to(max(bar.min_value, bar.value - 60.0))
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_down"):
		var bar := _scroll.get_v_scroll_bar()
		_hide_tooltip()
		_smooth_scroll_to(min(bar.max_value, bar.value + 60.0))
		get_viewport().set_input_as_handled()
	if event is InputEventMouseButton:
		var bar := _scroll.get_v_scroll_bar()
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_hide_tooltip()
			_smooth_scroll_to(max(bar.min_value, bar.value - 120.0))
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_hide_tooltip()
			_smooth_scroll_to(min(bar.max_value, bar.value + 120.0))


func _is_zh() -> bool:
	return GameManager.is_locale("zh")


## 背景（黑幕 + 模糊）不接收鼠标 —— 点在这里什么都不发生，
## 也不让点击穿透到后面的 VN（叠加层是模态的）。
func _swallow(_e: InputEvent) -> void:
	pass


func _kill_anim() -> void:
	if _anim_tween and _anim_tween.is_valid():
		_anim_tween.kill()
	_anim_tween = null
