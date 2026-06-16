## MainMenu : Control — 1:1 port of web MainMenuScene.
## Quit modal extracted to QuitModal.tscn scene.
## CLAUDE.md compliant: no lambdas, strict types, @onready typed.
extends Control

const BG: Array[String] = [
	"res://assets/backgrounds/menu/1.jpg","res://assets/backgrounds/menu/2.jpg",
	"res://assets/backgrounds/menu/3.jpg","res://assets/backgrounds/menu/4.jpg",
	"res://assets/backgrounds/menu/5.jpg","res://assets/backgrounds/menu/6.jpg",
	"res://assets/backgrounds/menu/7.jpg","res://assets/backgrounds/menu/8.jpg",
	"res://assets/backgrounds/menu/9.jpg",
]

var _sel: int = 0
var _items: Array[Control] = []
var _menu_active: bool = false
var _font_tcm: Font = null
var _font_zh_title: Font = null
var _font_en_body: Font = null
var _font_zh_emphasis: Font = null
var _font_en_emphasis: Font = null
var _quit_modal: Control = null
var _parallax_tween: Tween = null
var _overlay_tween: Tween = null  # quit modal dim/restore
var _cleaning_up: bool = false    # guard against re-entrant cleanup on rapid ESC
var _entry_complete: bool = false  # true once the initial _play_entry() has finished

@onready var _bg_root: Control = $BgRoot
@onready var _bg_img: TextureRect = $BgRoot/BgImage
@onready var _bg_gradient: ColorRect = $BgRoot/BgGradient
@onready var _bg_mat: ShaderMaterial = null
@onready var _brand: Control = %Branding
@onready var _brand_sub: Control = %BrandSub
@onready var _brand_line: ColorRect = %BrandLine
@onready var _brand_icon: TextureRect = %BrandIcon
@onready var _menu: Control = %MenuList


func _ready() -> void:
	_font_tcm = load(GameManager.FONT_TCM)
	_font_zh_title = load(GameManager.FONT_ZH_TITLE)
	_font_en_body = load(GameManager.FONT_EN_BODY)
	_font_zh_emphasis = load(GameManager.FONT_ZH_EMPHASIS)
	_font_en_emphasis = load(GameManager.FONT_EN_EMPHASIS)

	# MainMenu is transparent — BackgroundLayer shows through
	_bg_img.texture = null
	_bg_img.visible = false

	_size_all()
	get_tree().root.size_changed.connect(_size_all)
	_setup_branding()
	_build_menu_items()
	_position_menu_items()
	# Small delay lets the scene become visible before animation starts.
	await get_tree().process_frame
	await _play_entry()


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
	if _font_en_body:
		footer.add_theme_font_override("font", _font_en_body)

	var icon: Texture2D = load("res://assets/icons/icon.png")
	if icon:
		_brand_icon.texture = icon

	_add_zh(_brand_sub, "火兰山中学", 36, true)


func _pick_bg() -> void:
	var path: String = GameManager.current_background
	if path.is_empty() or not ResourceLoader.exists(path):
		path = BG[randi() % BG.size()]
	if ResourceLoader.exists(path) and _bg_img:
		var tex: Texture2D = load(path)
		GameManager.current_background = path
		_bg_img.modulate.a = 0.0
		_bg_img.texture = tex
		var tween := create_tween()
		tween.tween_property(_bg_img, "modulate:a", 1.0, 0.6)

# Sync MainMenu bg with shared background rotation (60s timer)
func _on_shared_bg_updated(path: String) -> void:
	if path.is_empty() or not ResourceLoader.exists(path):
		return
	var tex: Texture2D = load(path)
	if tex and _bg_img:
		var tween := create_tween()
		tween.tween_property(_bg_img, "modulate:a", 0.0, 0.35)
		tween.tween_callback(_set_bg_texture.bind(tex))
		tween.tween_property(_bg_img, "modulate:a", 1.0, 0.35)


func _set_bg_texture(tex: Texture2D) -> void:
	if _bg_img:
		_bg_img.texture = tex



var _item_data: Array[Dictionary] = [
			{"en": "New Game",     "zh": "开始游戏"},
		{"en": "Load",         "zh": "继续游戏"},
		{"en": "Rewards",      "zh": "成就"},
		{"en": "Config",       "zh": "设置"},
		{"en": "About",        "zh": "关于"},
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
		w.set_anchors_preset(Control.PRESET_TOP_LEFT)
		w.offset_top = i * 51
		w.offset_bottom = (i + 1) * 51
		w.offset_right = _menu.size.x
		# Start invisible — _play_entry() fades items in sequentially
		w.modulate.a = 0.0


## Two-phase sequential entry animation:
##   Phase 1 — Logo & title: brief pause → background zoom + branding + line
##   Phase 2 — Menu items: stagger in to resting (x=20) position, NO bounce
##   Menu is NOT interactable until every item has finished entering.
func _play_entry() -> void:
	# ── Initial states ──────────────────────────────────────────
	_bg_root.scale = Vector2(1.15, 1.15)
	_brand.modulate.a = 0.0
	var by: float = _brand.position.y
	_brand.position.y = by - 50.0
	_brand_line.size.x = 0.0
	# Menu items: hidden + off-screen right
	for w: Control in _items:
		w.modulate.a = 0.0
		w.position.x = 100.0

	# Brief stillness before animation starts — avoids "instant motion" feel
	await get_tree().create_timer(0.2).timeout

	# ═══════════════════════════════════════════════════════════════
	# Phase 1 — Logo & Title  (parallel: bg zoom + branding + line)
	# ═══════════════════════════════════════════════════════════════
	var t_bg := create_tween()
	t_bg.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	t_bg.tween_property(_bg_root, "scale", Vector2(1.0, 1.0), 1.2)

	var t_brand := create_tween().set_parallel(true)
	t_brand.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	t_brand.tween_property(_brand, "position:y", by, 1.0)
	t_brand.tween_property(_brand, "modulate:a", 1.0, 1.0)

	# Brand line expands after brand is partially visible
	var t_line := create_tween()
	t_line.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	t_line.tween_property(_brand_line, "size:x", 500.0, 0.9).set_delay(0.3)
	await t_line.finished

	# ═══════════════════════════════════════════════════════════════
	# Phase 2 — Menu Items
	#   Each item fades in FAST (0.3s) so the player sees it early,
	#   then slides from x=100→20 over 0.5s while fully visible.
	#   This avoids the "appear halfway through the slide" illusion
	#   that happens when fade & slide share the same easing curve.
	#   After entry, _apply_focus() moves item 0 from 20→-30 — a
	#   single smooth forward slide. Other items stay at 20 — no bounce.
	# ═══════════════════════════════════════════════════════════════
	const MENU_REST_X: float = 20.0
	const FADE_DURATION: float = 0.3
	const SLIDE_DURATION: float = 0.5
	const STAGGER: float = 0.08
	var last_item_tween: Tween = null
	for i: int in range(_items.size()):
		var w: Control = _items[i]
		var d: float = i * STAGGER
		var ti := create_tween().set_parallel(true)
		ti.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
		# Fast fade — item becomes fully visible early in the slide
		ti.tween_property(w, "modulate:a", 1.0, FADE_DURATION).set_delay(d)
		# Smooth slide — player sees the full motion while the item is visible
		ti.tween_property(w, "position:x", MENU_REST_X, SLIDE_DURATION).set_delay(d)
		last_item_tween = ti

	# Await the last item's LONGEST animation (slide, not fade), THEN enable interaction
	if last_item_tween:
		await last_item_tween.finished
	_menu_active = true
	# Defer focus by one frame — lets any pending mouse_entered signals
	# from the slide-in animation flush through so the correct item
	# (under the cursor, or default 0) gets focused. Prevents the
	# "focus item 0 → mouse over item 3 → kill & refocus" glitch.
	await get_tree().process_frame
	_apply_focus()
	_entry_complete = true



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


func _add_zh(parent: Control, text: String, first_fs: int = 24, brand_mode: bool = false) -> void:
	var hb: HBoxContainer = HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_END
	hb.add_theme_constant_override("separation", 2)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(hb)

	var szs: Array[int] = []
	if brand_mode:
		szs.append(28); szs.append(24); szs.append(22); szs.append(24)
	else:
		szs.append(20); szs.append(18); szs.append(16); szs.append(18)
	for i: int in range(text.length()):
		var l: Label = Label.new()
		l.text = text[i]
		l.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		l.size_flags_vertical = Control.SIZE_SHRINK_END  # bottom-align in row
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		l.add_theme_color_override("font_color", Color(1, 1, 1, 0.8))
		if _font_zh_title: l.add_theme_font_override("font", _font_zh_title)
		var fs: int = first_fs if i == 0 else szs[(i - 1) % szs.size()]
		l.add_theme_font_size_override("font_size", fs)
		hb.add_child(l)


var _focus_tween: Tween = null

func _apply_focus() -> void:
	if _focus_tween and _focus_tween.is_valid():
		_focus_tween.kill()

	_focus_tween = create_tween().set_parallel(true)
	_focus_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	for i: int in range(_items.size()):
		var w: Control = _items[i]
		var sweep: ColorRect = w.get_meta("sweep")
		var en: Label = w.get_meta("en")
		var zh_box: Control = w.get_meta("zh_box")
		var foc: bool = i == _sel and _menu_active
		var active_elsewhere: bool = _menu_active and i != _sel

		# Position shift ONLY — no size:x tween (changing layout width causes
		# child reflow + sub-pixel text jitter). The sweep + color change
		# provide sufficient visual focus feedback.
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


func _parallax() -> void:
	var px: float = (_sel - 2.5) * -15.0 - 80.0
	var base_x: float = -get_viewport().get_visible_rect().size.x * 0.125
	if _parallax_tween and _parallax_tween.is_valid():
		_parallax_tween.kill()
	_parallax_tween = create_tween()
	_parallax_tween.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	_parallax_tween.tween_property(_bg_root, "position:x", base_x + px, 0.8)


func _on_hover(idx: int) -> void:
	if _quit_modal or not _menu_active: return
	_sel = idx; _apply_focus(); _parallax(); _sfx()


func _on_click(ev: InputEvent, idx: int) -> void:
	if not _menu_active: return
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


func _input(event: InputEvent) -> void:
	if _quit_modal or not _menu_active:
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


func _show_quit() -> void:
	if _quit_modal or _cleaning_up: return

	var packed: PackedScene = load("res://scenes/modals/QuitModal.tscn") as PackedScene
	if not packed:
		push_error("MainMenu: Failed to load QuitModal scene")
		return

	_quit_modal = packed.instantiate()
	add_child(_quit_modal)

	_quit_modal.confirmed.connect(_on_quit_confirmed)
	_quit_modal.cancelled.connect(_on_quit_cancelled)

	_menu_active = false
	AudioManager.set_menu_mode(true)
	if _focus_tween and _focus_tween.is_valid():
		_focus_tween.kill()

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
	if _quit_modal: return
	_menu_active = true
	_apply_focus()


func _cleanup_quit() -> void:
	var modal: Control = _quit_modal
	if not modal or _cleaning_up: return
	_cleaning_up = true

	AudioManager.set_menu_mode(false)
	if _bg_mat: _bg_mat.set_shader_parameter("blur_amount", 10.0)
	var tbg: Tween = create_tween()
	tbg.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	tbg.tween_property(_bg_root, "scale", Vector2(1.0, 1.0), 0.8)

	if _overlay_tween and _overlay_tween.is_valid():
		_overlay_tween.kill()
	_overlay_tween = create_tween().set_parallel(true)
	_overlay_tween.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	for w: Control in _items:
		_overlay_tween.tween_property(w, "modulate:a", 1.0, 0.3)
	_overlay_tween.tween_property(_brand, "modulate:a", 1.0, 0.3)

	await get_tree().create_timer(0.3).timeout
	if is_instance_valid(modal):
		modal.queue_free()
	if _quit_modal == modal:
		_quit_modal = null
	_cleaning_up = false


# ── SceneManager lifecycle ──────────────────────────────
func _on_exit() -> void:
	_menu_active = false
	_cleaning_up = false
	if _focus_tween and _focus_tween.is_valid():
		_focus_tween.kill()
	if _overlay_tween and _overlay_tween.is_valid():
		_overlay_tween.kill()
	if _parallax_tween and _parallax_tween.is_valid():
		_parallax_tween.kill()
	if _quit_modal:
		_quit_modal.queue_free()
		_quit_modal = null


func _on_enter() -> void:
	_pick_bg()
	# Only activate menu on RE-entry (returning from another scene).
	# On first load, _play_entry() owns the full animation sequence and
	# will enable the menu when it finishes.  Calling _apply_focus() here
	# while entry tweens are still running causes the focus and slide
	# tweens to fight over position:x → deselect/re-select flicker.
	if _entry_complete:
		await get_tree().process_frame
		_menu_active = true
		_apply_focus()


func _sfx() -> void: AudioManager.play_click()


func set_disabled(_v: bool) -> void: pass
