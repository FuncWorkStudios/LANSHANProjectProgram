## MainMenu — 1:1 port of web MainMenuScene.
## Quit modal extracted to QuitModal.tscn scene.
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
var _items: Array[Control] = []
var _menu_active: bool = false
var _font_tcm: Font = null
var _font_zh_title: Font = null
var _font_zh_option: Font = null
var _quit_modal: Control = null
var _parallax_tween: Tween = null
var _overlay_tween: Tween = null  # quit modal dim/restore

@onready var _bg_root: Control = $BgRoot
@onready var _bg_img: TextureRect = $BgRoot/BgImage
@onready var _bg_gradient: ColorRect = $BgRoot/BgGradient
@onready var _bg_mat: ShaderMaterial = null
@onready var _brand: Control = %Branding
@onready var _brand_sub: Control = %BrandSub
@onready var _brand_line: ColorRect = %BrandLine
@onready var _brand_icon: TextureRect = %BrandIcon
@onready var _menu: Control = %MenuList


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
	# Small delay lets the scene become visible before animation starts.
	# Without this, _ready runs during instantiate() when scene is still hidden.
	await get_tree().process_frame
	_play_entry()


func _size_all() -> void:
	var sz: Vector2 = get_viewport().get_visible_rect().size
	_bg_root.position = Vector2(-sz.x * 0.125, -sz.y * 0.125)
	_bg_root.size = Vector2(sz.x * 1.25, sz.y * 1.25)

	# Branding at top-right (web: top-12 right-12 lg:right-32)
	var brand_x: float = sz.x - 600.0
	var brand_y: float = 60.0
	_brand.position = Vector2(brand_x, brand_y)
	_brand_line.position.x = 0.0
	_brand_line.position.y = 139.0

	# Menu items positioned at right side (web: pr-12 lg:pr-32, max-w-xl)
	_menu.position = Vector2(sz.x - 680.0, sz.y * 0.28)
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
		wrap.modulate.a = 0.0  # start invisible — _play_entry fades in
		wrap.mouse_entered.connect(_on_hover.bind(i))
		wrap.gui_input.connect(_on_click.bind(i))
		_menu.add_child(wrap)
		_items.append(wrap)


func _position_menu_items() -> void:
	for i: int in range(_items.size()):
		var w: Control = _items[i]
		# PRESET_TOP_LEFT (not WIDE): anchor_right=0 → position:x = pure CSS translateX.
		# Fixed width set via offset_right so size:x tweens work correctly later.
		w.set_anchors_preset(Control.PRESET_TOP_LEFT)
		w.offset_top = i * 51
		w.offset_bottom = (i + 1) * 51
		w.offset_right = _menu.size.x


func _play_entry() -> void:
	# Background zoom-in entry (web: scale 1.15 → 1.0)
	_bg_root.scale = Vector2(1.15, 1.15)
	var tbg: Tween = create_tween()
	tbg.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	tbg.tween_property(_bg_root, "scale", Vector2(1.0, 1.0), 1.0)

	# Branding fade + slide down (web: y: -50→0, opacity: 0→1)
	_brand.modulate.a = 0.0
	var by: float = _brand.position.y
	_brand.position.y = by - 50.0
	var tb: Tween = create_tween()
	tb.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	tb.tween_property(_brand, "position:y", by, 1.0)
	tb.tween_property(_brand, "modulate:a", 1.0, 1.0)

	# Separator line expand (web: width 0 → 500)
	_brand_line.size.x = 0.0
	var tl: Tween = create_tween()
	tl.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	tl.tween_property(_brand_line, "size:x", 500.0, 1.2).set_delay(0.5)

	# Menu items — slide in from right, CSS translateX behaviour.
	# PRESET_TOP_LEFT so position:x = pure translation (no width change).
	# TRANS_CUBIC ≈ web cubic-bezier(0.16, 1, 0.3, 1).
	var last_delay: float = 0.0
	for i: int in range(_items.size()):
		var w: Control = _items[i]
		w.position.x = 100.0
		var d: float = 0.3 + i * 0.10
		last_delay = d
		var ti: Tween = create_tween().set_parallel(true)
		ti.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		ti.tween_property(w, "position:x", 0.0, 0.7).set_delay(d)
		ti.tween_property(w, "modulate:a", 1.0, 0.7).set_delay(d)

	# Delay focus until after the last entry tween finishes
	# (last delay 0.8s + duration 0.7s = 1.5s), then activate
	var t_entry_done: Tween = create_tween()
	t_entry_done.tween_callback(_on_entry_complete).set_delay(last_delay + 0.8)


func _on_entry_complete() -> void:
	_menu_active = true
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

	# Dark background (web: bg-black/20)
	var bg_f: ColorRect = ColorRect.new()
	bg_f.layout_mode = 1
	bg_f.color = Color(0, 0, 0, 0.2)
	bg_f.anchor_right = 1.0; bg_f.anchor_bottom = 1.0
	bg_f.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(bg_f)

	# Top border (web: border-y border-white/20)
	var bt: ColorRect = ColorRect.new()
	bt.layout_mode = 1
	bt.color = Color(1, 1, 1, 0.2)
	bt.anchor_right = 1.0
	bt.offset_bottom = 1.0
	bt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(bt)

	# Bottom border
	var bb: ColorRect = ColorRect.new()
	bb.layout_mode = 1
	bb.color = Color(1, 1, 1, 0.2)
	bb.anchor_right = 1.0
	bb.anchor_top = 1.0; bb.anchor_bottom = 1.0
	bb.offset_top = -1.0
	bb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(bb)

	# White sweep fill (web: bg-white, scaleX from left origin)
	var sweep: ColorRect = ColorRect.new()
	sweep.name = "Sweep"
	sweep.color = Color.WHITE
	sweep.set_anchors_preset(Control.PRESET_FULL_RECT)
	sweep.pivot_offset = Vector2(0, 0)
	sweep.scale.x = 0.0
	sweep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(sweep)

	# HBox for text content (web: flex items-end justify-between)
	var hb: HBoxContainer = HBoxContainer.new()
	hb.layout_mode = 1
	hb.anchor_right = 1.0; hb.anchor_bottom = 1.0
	hb.alignment = BoxContainer.ALIGNMENT_END
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# English title
	var en: Label = Label.new()
	en.text = en_txt
	en.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	en.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	en.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	en.add_theme_font_size_override("font_size", 36)
	en.add_theme_color_override("font_color", Color.WHITE)
	if _font_tcm: en.add_theme_font_override("font", _font_tcm)
	hb.add_child(en)

	# Chinese subtitle
	var zh_box: Control = Control.new()
	zh_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_add_zh(zh_box, zh_txt)
	hb.add_child(zh_box)

	# Right spacer
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
		l.size_flags_vertical = Control.SIZE_SHRINK_END  # bottom-align in row
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		l.add_theme_color_override("font_color", Color(1, 1, 1, 0.8))
		if _font_zh_option: l.add_theme_font_override("font", _font_zh_option)
		var fs: int = 24 if i == 0 else szs[(i - 1) % szs.size()]
		l.add_theme_font_size_override("font_size", fs)
		hb.add_child(l)


# ── Focus — tweened transition (web: 0.2s quint ease-out) ──

var _focus_tween: Tween = null

func _apply_focus() -> void:
	# The _on_hover guard (idx==_sel check) prevents redundant calls.
	# Kill only happens on genuine focus changes → safe at human speed.
	if _focus_tween and _focus_tween.is_valid():
		_focus_tween.kill()

	_focus_tween = create_tween().set_parallel(true)
	_focus_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	var base_w: float = _menu.size.x
	for i: int in range(_items.size()):
		var w: Control = _items[i]
		var sweep: ColorRect = w.get_meta("sweep")
		var en: Label = w.get_meta("en")
		var zh_box: Control = w.get_meta("zh_box")
		var foc: bool = i == _sel and _menu_active
		var active_elsewhere: bool = _menu_active and i != _sel

		_focus_tween.tween_property(w, "size:x", base_w * 1.2 if foc else base_w, 0.2)
		_focus_tween.tween_property(w, "position:x", -30.0 if foc else 20.0, 0.2)
		_focus_tween.tween_property(w, "modulate:a", 0.55 if active_elsewhere else 1.0, 0.2)
		_focus_tween.tween_property(sweep, "scale:x", 1.0 if foc else 0.0, 0.2)
		_focus_tween.tween_property(en, "self_modulate", Color.BLACK if foc else Color.WHITE, 0.2)
		_tween_zh_modulate(_focus_tween, zh_box, Color.BLACK if foc else Color.WHITE, 0.2)


func _tween_zh_modulate(tw: Tween, box: Control, col: Color, dur: float) -> void:
	for c in box.get_children():
		if c is HBoxContainer:
			for l in c.get_children():
				if l is Label:
					tw.tween_property(l, "self_modulate", col, dur)


# ── Parallax (web: (selectedIndex - 2.5) * -15 - 80) ──

func _parallax() -> void:
	var px: float = (_sel - 2.5) * -15.0 - 80.0
	var base_x: float = -get_viewport().get_visible_rect().size.x * 0.125
	if _parallax_tween and _parallax_tween.is_valid():
		_parallax_tween.kill()
	_parallax_tween = create_tween()
	_parallax_tween.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	_parallax_tween.tween_property(_bg_root, "position:x", base_x + px, 0.8)


func _on_hover(idx: int) -> void:
	if _quit_modal: return
	if idx == _sel: return  # already focused — skip redundant apply
	_sel = idx; _apply_focus(); _parallax(); _sfx()


func _on_click(ev: InputEvent, idx: int) -> void:
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and ev.pressed:
		_activate(idx)


func _activate(idx: int) -> void:
	_sfx()
	var ids: Array[String] = ["new_game","load","rewards","config","about","exit"]
	var tgs: Array[String] = ["REGISTRATION","LOAD","REWARDS","SETTINGS","ABOUT",""]
	if ids[idx] == "exit":
		_show_quit()
	elif not tgs[idx].is_empty():
		EventBus.scene_changed.emit(tgs[idx])


# ── Input ──────────────────────────────────────────────

func _input(event: InputEvent) -> void:
	if _quit_modal or not _menu_active:
		# QuitModal active → it handles its own input
		# Entry animation still playing → block input to prevent tween conflicts
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
		_show_quit(); get_viewport().set_input_as_handled()


# ── Quit Modal — instantiates external QuitModal scene ─

func _show_quit() -> void:
	if _quit_modal: return

	# Load and instantiate the quit modal scene
	var packed: PackedScene = load("res://scenes/Modals/QuitModal.tscn") as PackedScene
	if not packed:
		push_error("MainMenu: Failed to load QuitModal scene")
		return

	_quit_modal = packed.instantiate()
	add_child(_quit_modal)

	# Connect signals
	_quit_modal.confirmed.connect(_on_quit_confirmed)
	_quit_modal.cancelled.connect(_on_quit_cancelled)

	# Disable menu input; QuitModal handles its own _input
	_menu_active = false
	# Kill focus tween before overlay dim — avoids competing tweens on modulate:a
	if _focus_tween and _focus_tween.is_valid():
		_focus_tween.kill()

	# Dim menu items + branding in sync (web: menu→0.15, brand→0.3, blurred bg)
	if _overlay_tween and _overlay_tween.is_valid():
		_overlay_tween.kill()
	_overlay_tween = create_tween().set_parallel(true)
	_overlay_tween.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	for w: Control in _items:
		_overlay_tween.tween_property(w, "modulate:a", 0.15, 0.4)
	_overlay_tween.tween_property(_brand, "modulate:a", 0.3, 0.4)

	if _bg_mat: _bg_mat.set_shader_parameter("blur_amount", 15.0)
	var tbg: Tween = create_tween()
	tbg.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	tbg.tween_property(_bg_root, "scale", Vector2(1.15, 1.15), 0.8)


func _on_quit_confirmed() -> void:
	await _cleanup_quit()
	get_tree().quit()


func _on_quit_cancelled() -> void:
	await _cleanup_quit()
	_menu_active = true
	_apply_focus()


func _cleanup_quit() -> void:
	if not _quit_modal: return

	# Restore background blur and scale
	if _bg_mat: _bg_mat.set_shader_parameter("blur_amount", 10.0)
	var tbg: Tween = create_tween()
	tbg.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	tbg.tween_property(_bg_root, "scale", Vector2(1.0, 1.0), 0.8)

	# Restore menu items and branding together
	if _overlay_tween and _overlay_tween.is_valid():
		_overlay_tween.kill()
	_overlay_tween = create_tween().set_parallel(true)
	_overlay_tween.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	for w: Control in _items:
		_overlay_tween.tween_property(w, "modulate:a", 1.0, 0.3)
	_overlay_tween.tween_property(_brand, "modulate:a", 1.0, 0.3)

	# Wait for QuitModal exit animation, then free
	await get_tree().create_timer(0.3).timeout
	if _quit_modal:
		_quit_modal.queue_free()
		_quit_modal = null


# ── Utils ──────────────────────────────────────────────

func _sfx() -> void: AudioManager.play_sfx("res://assets/Sfx/Choose.wav")


func set_disabled(_v: bool) -> void: pass
