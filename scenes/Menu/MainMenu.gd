## MainMenu — 1:1 port of web MainMenuScene.
## CLAUDE.md compliant: no lambdas, strict types, @onready typed.
extends Control

const BG: Array[String] = [
	"res://assets/MainBackground/1.jpg","res://assets/MainBackground/2.jpg",
	"res://assets/MainBackground/3.jpg","res://assets/MainBackground/4.jpg",
	"res://assets/MainBackground/5.jpg","res://assets/MainBackground/6.jpg",
	"res://assets/MainBackground/7.jpg","res://assets/MainBackground/8.jpg",
	"res://assets/MainBackground/9.jpg",
]

var _sel: int = 0
var _quit_open: bool = false
var _quit_sel: int = 1
var _items: Array[Control] = []
var _menu_active: bool = false
var _font_tcm: Font = null
var _font_zh_title: Font = null
var _font_zh_option: Font = null

@onready var _bg_root: Control = $BgRoot
@onready var _bg_img: TextureRect = $BgRoot/BgImage
@onready var _bg_gradient: ColorRect = $BgRoot/BgGradient
@onready var _bg_mat: ShaderMaterial = null
@onready var _brand: Control = %Branding
@onready var _brand_sub: Control = %BrandSub
@onready var _brand_line: ColorRect = %BrandLine
@onready var _brand_icon: TextureRect = %BrandIcon
@onready var _menu: Control = %MenuList
@onready var _qmodal: Control = %QuitModal


# ── Ready ──────────────────────────────────────────────

func _ready() -> void:
	_font_tcm = load("res://assets/fonts/TCM_____.TTF")
	_font_zh_title = load("res://assets/fonts/SourceHanSerifCN-SemiBold-7.otf")
	_font_zh_option = load("res://assets/fonts/SourceHanSerifCN-Medium-6.otf")

	var shader: Shader = load("res://scenes/Menu/blur.gdshader")
	if shader:
		_bg_mat = ShaderMaterial.new()
		_bg_mat.shader = shader
		_bg_mat.set_shader_parameter("blur_amount", 10.0)
		_bg_img.material = _bg_mat

	_size_all()
	get_tree().root.size_changed.connect(_size_all)
	_setup_branding()
	_pick_bg()
	_build_menu_items()
	_position_menu_items()
	_play_entry()


func _size_all() -> void:
	var sz: Vector2 = get_viewport().get_visible_rect().size
	_bg_root.position = Vector2(-sz.x * 0.125, -sz.y * 0.125)
	_bg_root.size = Vector2(sz.x * 1.25, sz.y * 1.25)

	var brand_x: float = sz.x - 600.0
	var brand_y: float = 60.0
	_brand.position = Vector2(brand_x, brand_y)
	_brand_line.position.x = 0.0
	_brand_line.position.y = 139.0

	_menu.position = Vector2(sz.x - 680.0, sz.y * 0.15)
	_menu.size = Vector2(620.0, sz.y * 0.7)


func _setup_branding() -> void:
	var brand_title: Label = _brand.get_node("BrandRow/BrandTextCol/BrandTitle")
	brand_title.add_theme_font_override("font", _font_tcm)
	var footer: Label = _brand.get_node("BrandFooter")
	footer.add_theme_font_override("font", _font_tcm)

	var icon: Texture2D = load("res://assets/icons/LSP_icon_big.png")
	if icon:
		_brand_icon.texture = icon

	_add_zh(_brand_sub, "火兰山中学")


func _pick_bg() -> void:
	var path: String = BG[randi() % BG.size()]
	if ResourceLoader.exists(path):
		_bg_img.texture = load(path)


# ── Menu Items ─────────────────────────────────────────

var _item_data: Array[Dictionary] = [
	{"en": "New Game",     "zh": "新游戏"},
	{"en": "Load",         "zh": "读取存档"},
	{"en": "Rewards",      "zh": "成就奖励"},
	{"en": "Config",       "zh": "系统设置"},
	{"en": "About",        "zh": "关于我们"},
	{"en": "Exit",         "zh": "退出游戏"},
]


func _build_menu_items() -> void:
	_items.clear()
	for child in _menu.get_children():
		child.queue_free()

	var data: Array[Dictionary] = _item_data
	for i: int in range(data.size()):
		var wrap: Control = _make_item(i, data[i].en, data[i].zh)
		wrap.mouse_entered.connect(_on_hover.bind(i))
		wrap.gui_input.connect(_on_click.bind(i))
		_menu.add_child(wrap)
		_items.append(wrap)


func _position_menu_items() -> void:
	for i: int in range(_items.size()):
		var w: Control = _items[i]
		w.set_anchors_preset(Control.PRESET_TOP_WIDE)
		w.offset_top = i * 51
		w.offset_bottom = (i + 1) * 51


func _play_entry() -> void:
	_bg_root.scale = Vector2(1.15, 1.15)
	var tbg: Tween = create_tween()
	tbg.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tbg.tween_property(_bg_root, "scale", Vector2(1.0, 1.0), 1.0)

	_brand.modulate.a = 0.0
	var by: float = _brand.position.y
	_brand.position.y = by + 40.0
	var tb: Tween = create_tween()
	tb.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tb.tween_property(_brand, "position:y", by, 0.8).set_delay(0.2)
	tb.tween_property(_brand, "modulate:a", 1.0, 0.8).set_delay(0.2)

	_brand_line.size.x = 0.0
	var tl: Tween = create_tween()
	tl.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tl.tween_property(_brand_line, "size:x", 500.0, 1.2).set_delay(0.5)

	for i: int in range(_items.size()):
		var w: Control = _items[i]
		w.modulate.a = 0.0
		w.position.x = 40.0
		var d: float = 0.6 + i * 0.1
		var ti: Tween = create_tween()
		ti.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
		ti.tween_property(w, "position:x", 0.0, 0.8).set_delay(d)
		ti.tween_property(w, "modulate:a", 1.0, 0.8).set_delay(d)

	_apply_focus()


# ── Item Factory ──────────────────────────────────────

func _make_item(idx: int, en_txt: String, zh_txt: String) -> Control:
	var wrap: Control = Control.new()
	wrap.name = "Item_" + str(idx)
	wrap.custom_minimum_size = Vector2(0, 51)
	wrap.mouse_filter = Control.MOUSE_FILTER_STOP

	var bar: Control = Control.new()
	bar.name = "Bar"
	bar.layout_mode = 1
	bar.anchor_right = 1.0
	bar.anchor_bottom = 1.0
	bar.clip_contents = true
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(bar)

	var bg_f: ColorRect = ColorRect.new()
	bg_f.layout_mode = 1
	bg_f.color = Color(0, 0, 0, 0.2)
	bg_f.anchor_right = 1.0; bg_f.anchor_bottom = 1.0
	bg_f.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(bg_f)

	var bt: ColorRect = ColorRect.new()
	bt.layout_mode = 1
	bt.color = Color(1, 1, 1, 0.2)
	bt.anchor_right = 1.0
	bt.offset_bottom = 1.0
	bt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(bt)

	var bb: ColorRect = ColorRect.new()
	bb.layout_mode = 1
	bb.color = Color(1, 1, 1, 0.2)
	bb.anchor_right = 1.0
	bb.anchor_top = 1.0; bb.anchor_bottom = 1.0
	bb.offset_top = -1.0
	bb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(bb)

	var sweep: ColorRect = ColorRect.new()
	sweep.name = "Sweep"
	sweep.color = Color.WHITE
	sweep.set_anchors_preset(Control.PRESET_FULL_RECT)
	sweep.pivot_offset = Vector2(0, 0)
	sweep.scale.x = 0.0
	sweep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(sweep)

	var hb: HBoxContainer = HBoxContainer.new()
	hb.layout_mode = 1
	hb.anchor_right = 1.0; hb.anchor_bottom = 1.0
	hb.alignment = BoxContainer.ALIGNMENT_END
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var en: Label = Label.new()
	en.text = en_txt
	en.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	en.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	en.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	en.add_theme_font_size_override("font_size", 36)
	en.add_theme_color_override("font_color", Color.WHITE)
	if _font_tcm: en.add_theme_font_override("font", _font_tcm)
	hb.add_child(en)

	var zh_box: Control = Control.new()
	zh_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_add_zh(zh_box, zh_txt)
	hb.add_child(zh_box)

	var sp: Control = Control.new()
	sp.custom_minimum_size = Vector2(150, 0)
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(sp)

	bar.add_child(hb)

	wrap.set_meta("bar", bar)
	wrap.set_meta("sweep", sweep)
	wrap.set_meta("en", en)
	wrap.set_meta("zh_box", zh_box)
	wrap.set_meta("hb", hb)

	return wrap


func _add_zh(parent: Control, text: String) -> void:
	var hb: HBoxContainer = HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_END
	hb.add_theme_constant_override("separation", 2)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(hb)

	var szs: Array[int] = [20, 18, 16, 18]
	for i: int in range(text.length()):
		var l: Label = Label.new()
		l.text = text[i]
		l.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		l.add_theme_color_override("font_color", Color(1, 1, 1, 0.8))
		if _font_zh_option: l.add_theme_font_override("font", _font_zh_option)
		var fs: int = 24 if i == 0 else szs[(i - 1) % szs.size()]
		l.add_theme_font_size_override("font_size", fs)
		hb.add_child(l)


# ── Focus ──────────────────────────────────────────────

func _apply_focus() -> void:
	_menu_active = _sel >= 0 and not _quit_open
	var base_w: float = _menu.size.x
	for i: int in range(_items.size()):
		var w: Control = _items[i]
		var bar: Control = w.get_meta("bar")
		var sweep: ColorRect = w.get_meta("sweep")
		var en: Label = w.get_meta("en")
		var zh_box: Control = w.get_meta("zh_box")
		var foc: bool = i == _sel and _menu_active

		var target_x: float = -30.0 if foc else 20.0

		var t: Tween = create_tween().set_parallel(true)
		t.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		t.tween_property(w, "size:x", base_w * 1.2 if foc else base_w, 0.25)
		t.tween_property(w, "position:x", target_x, 0.25)

		var ts: Tween = create_tween()
		ts.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		if foc: ts.tween_property(sweep, "scale:x", 1.0, 0.25)
		else: ts.tween_property(sweep, "scale:x", 0.0, 0.25)

		var active_elsewhere: bool = _menu_active and i != _sel
		w.modulate.a = 0.3 if active_elsewhere else 1.0

		en.add_theme_color_override("font_color", Color.BLACK if foc else Color.WHITE)
		_update_zh_color(zh_box, Color.BLACK if foc else Color(1, 1, 1, 0.8))


func _update_zh_color(box: Control, col: Color) -> void:
	for c in box.get_children():
		if c is HBoxContainer:
			for l in c.get_children():
				if l is Label:
					l.add_theme_color_override("font_color", col)


func _parallax() -> void:
	var px: float = (_sel - 2.5) * -15.0 - 80.0
	var base_x: float = -get_viewport().get_visible_rect().size.x * 0.125
	var t: Tween = create_tween()
	t.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	t.tween_property(_bg_root, "position:x", base_x + px, 0.5)


func _on_hover(idx: int) -> void:
	if _quit_open: return
	_sel = idx; _apply_focus(); _parallax(); _sfx()


func _on_click(ev: InputEvent, idx: int) -> void:
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and ev.pressed:
		_activate(idx)


func _activate(idx: int) -> void:
	_sfx()
	var ids: Array[String] = ["new_game","load","rewards","config","about","exit"]
	var tgs: Array[String] = ["REGISTRATION","LOAD","REWARDS","SETTINGS","ABOUT",""]
	if ids[idx] == "exit":
		_open_quit()
	elif not tgs[idx].is_empty():
		EventBus.scene_changed.emit(tgs[idx])


# ── Input ──────────────────────────────────────────────

func _input(event: InputEvent) -> void:
	if _quit_open:
		if event.is_action_pressed("ui_up") or event.is_action_pressed("ui_left"):
			_quit_sel = 0; _qrefresh(); _sfx()
		elif event.is_action_pressed("ui_down") or event.is_action_pressed("ui_right"):
			_quit_sel = 1; _qrefresh(); _sfx()
		elif event.is_action_pressed("ui_accept"):
			_sfx()
			if _quit_sel == 0: get_tree().quit()
			else: _close_quit()
		elif event.is_action_pressed("ui_cancel"): _sfx(); _close_quit()
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("ui_up") or event.is_action_pressed("ui_left"):
		_sel = (_sel - 1 + 6) % 6; _apply_focus(); _parallax(); _sfx()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_down") or event.is_action_pressed("ui_right"):
		_sel = (_sel + 1) % 6; _apply_focus(); _parallax(); _sfx()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		_activate(_sel); get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel"):
		_open_quit(); get_viewport().set_input_as_handled()


# ── Quit modal ─────────────────────────────────────────

func _open_quit() -> void:
	_quit_open = true; _quit_sel = 1
	_qmodal.visible = true

	var title_en: Label = _qmodal.get_node("QuitTitleBox/QuitTitleEn")
	title_en.add_theme_font_size_override("font_size", 72)
	title_en.add_theme_color_override("font_color", Color.BLACK)
	if _font_tcm: title_en.add_theme_font_override("font", _font_tcm)

	var band: Control = _qmodal.get_node("QuitBand")
	var bg: ColorRect = _qmodal.get_node("QuitBg")
	bg.modulate.a = 0.0
	band.scale.x = 0.0
	band.pivot_offset.x = band.size.x

	_build_quit_items()
	_qrefresh()
	_apply_focus()

	if _bg_mat: _bg_mat.set_shader_parameter("blur_amount", 15.0)
	var tween := create_tween()
	tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_EXPO)
	tween.set_parallel(true)
	tween.tween_property(bg, "modulate:a", 1.0, 0.35)
	tween.tween_property(band, "scale:x", 1.0, 0.45).from(0.0)


func _close_quit() -> void:
	var band: Control = _qmodal.get_node("QuitBand")
	var bg: ColorRect = _qmodal.get_node("QuitBg")

	if _bg_mat: _bg_mat.set_shader_parameter("blur_amount", 10.0)
	var tween := create_tween()
	tween.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_EXPO)
	tween.set_parallel(true)
	tween.tween_property(bg, "modulate:a", 0.0, 0.25)
	tween.tween_property(band, "scale:x", 0.0, 0.25)
	tween.tween_callback(_on_quit_closed)


func _on_quit_closed() -> void:
	_quit_open = false
	_qmodal.visible = false
	_apply_focus()


func _build_quit_items() -> void:
	var band: Control = _qmodal.get_node("QuitBand")
	var old: Node = band.get_node_or_null("QOpts")
	if old: old.queue_free()

	var box: VBoxContainer = VBoxContainer.new()
	box.name = "QOpts"
	box.layout_mode = 1
	box.anchor_left = 0.55; box.anchor_right = 0.95
	box.anchor_top = 0.15; box.anchor_bottom = 0.85
	band.add_child(box)

	for i: int in range(2):
		var en_txt: String = "Yes" if i == 0 else "No"
		var zh_txt: String = "是" if i == 0 else "否"
		var row: Control = _make_item(i, en_txt, zh_txt)
		if row.mouse_entered.is_connected(_on_hover): row.mouse_entered.disconnect(_on_hover)
		if row.gui_input.is_connected(_on_click): row.gui_input.disconnect(_on_click)
		row.mouse_entered.connect(_on_qhover.bind(i))
		row.gui_input.connect(_on_qclick.bind(i))
		box.add_child(row)


func _qrefresh() -> void:
	var box: Node = _qmodal.get_node_or_null("QuitBand/QOpts")
	if not box: return
	for i: int in range(box.get_child_count()):
		var w: Control = box.get_child(i)
		var sweep: ColorRect = w.get_meta("sweep")
		var en: Label = w.get_meta("en")
		var zh_box: Control = w.get_meta("zh_box")
		var foc: bool = i == _quit_sel

		var ts: Tween = create_tween()
		ts.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		if foc: ts.tween_property(sweep, "scale:x", 1.0, 0.25)
		else: ts.tween_property(sweep, "scale:x", 0.0, 0.25)

		en.add_theme_color_override("font_color", Color.BLACK if foc else Color(1, 1, 1, 1.0))
		_update_zh_color(zh_box, Color.BLACK if foc else Color(1, 1, 1, 1.0))


func _on_qhover(idx: int) -> void: _quit_sel = idx; _qrefresh(); _sfx()


func _on_qclick(ev: InputEvent, idx: int) -> void:
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and ev.pressed:
		_sfx()
		if idx == 0: get_tree().quit()
		else: _close_quit()


# ── Utils ──────────────────────────────────────────────

func _sfx() -> void: AudioManager.play_sfx("res://assets/Sfx/Choose.wav")


func set_disabled(_v: bool) -> void: pass
