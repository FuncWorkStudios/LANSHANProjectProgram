## VNInterface : Control
## Core visual novel gameplay scene â backgrounds, sprites, dialogue, typewriter.
## Sub-scenes (TabMenu, SaveMenu, ChoicesMenu, LoadingScreen) are independent.
extends Control

signal back_requested()
signal scene_changed(new_scene: String)

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------
var _plot: PlotData = null
var _plot_id: String = ""
var _node_index: int = 0
var _current_node: PlotNode = null
var _visible_chars: int = 0
var _is_typing_finished: bool = false
var _is_menu_open: bool = false
var _is_tab_menu_open: bool = false
var _is_skipping: bool = false
var _pending_save_slot: int = -1
var _terminal_status: String = "locked"
var _player_name: String = ""
var _current_bg: String = ""
var _current_char: String = ""
var _settings: AppSettings

# Font resources
var _font_tcm: Font = null
var _font_zh_title: Font = null
var _font_zh_body: Font = null
var _font_zh_emphasis: Font = null
var _font_en_body: Font = null
var _font_en_emphasis: Font = null

# Locale helper
func _is_zh() -> bool:
	return TranslationServer.get_locale().begins_with("zh")

# Typewriter / wait / auto timers
var _typewriter_timer: float = 0.0
var _typewriter_interval: float = 0.045
var _auto_play_timer: float = 0.0
var _auto_play_delay: float = 2.0
var _wait_timer: float = 0.0
var _is_waiting: bool = false

# Tween references
var _cursor_blink_tween: Tween = null
var _exit_tree_called: bool = false

# Sub-scene instances
var _save_menu: Control = null
var _choices_menu: Control = null
var _loading_screen: Control = null
var _tab_menu: Control = null

# ---------------------------------------------------------------------------
# Onready â core VN nodes
# ---------------------------------------------------------------------------
@onready var _bg_rect: TextureRect = %BackgroundRect
@onready var _char_rect: TextureRect = %CharacterRect
@onready var _dialogue_box: Panel = %DialogueBox
@onready var _dialogue_text: RichTextLabel = %DialogueText
@onready var _speaker_name_container: Control = %SpeakerNameContainer
@onready var _speaker_name_label: Label = %SpeakerNameLabel
@onready var _glitch_overlay: ColorRect = %GlitchOverlay
@onready var _cursor_blink: ColorRect = %CursorBlink
@onready var _controls_hint: Control = %ControlsHint
@onready var _overwrite_modal: Control = %OverwriteModal
@onready var _cinematic_top: ColorRect = %CinematicTop
@onready var _cinematic_bottom: ColorRect = %CinematicBottom


# ===================================================================
# Setup & Loading
# ===================================================================

func setup(initial_save: SaveData, player_name: String) -> void:
	_player_name = player_name
	_settings = GameManager.get_settings()

	# Load font resources
	_font_tcm = load(GameManager.FONT_TCM)
	_font_zh_title = load(GameManager.FONT_ZH_TITLE)
	_font_zh_body = load(GameManager.FONT_ZH_BODY)
	_font_zh_emphasis = load(GameManager.FONT_ZH_EMPHASIS)
	_font_en_body = load(GameManager.FONT_EN_BODY)
	_font_en_emphasis = load(GameManager.FONT_EN_EMPHASIS)

	# Instantiate sub-scenes
	_instantiate_sub_scenes()

	if initial_save:
		_plot_id = initial_save.plot_id
		_node_index = initial_save.node_index
		_terminal_status = initial_save.terminal_status
		GameManager.player_name = initial_save.player_name
	else:
		_plot_id = "intro"
		_node_index = 0
		GameManager.player_name = player_name

	_load_plot()
	_hide_loading()
	_create_controls_hint()


func _instantiate_sub_scenes() -> void:
	# Loading screen
	var ls_packed: PackedScene = load("res://scenes/vn/LoadingScreen.tscn") as PackedScene
	if ls_packed:
		_loading_screen = ls_packed.instantiate()
		_loading_screen.name = "LoadingScreen"
		add_child(_loading_screen)

	# Choices menu
	var cm_packed: PackedScene = load("res://scenes/vn/ChoicesMenu.tscn") as PackedScene
	if cm_packed:
		_choices_menu = cm_packed.instantiate()
		_choices_menu.name = "ChoicesMenu"
		_choices_menu.visible = false
		_choices_menu.choice_selected.connect(_on_choice_selected)
		add_child(_choices_menu)

	# Save menu
	var sm_packed: PackedScene = load("res://scenes/vn/SaveMenu.tscn") as PackedScene
	if sm_packed:
		_save_menu = sm_packed.instantiate()
		_save_menu.name = "SaveMenu"
		_save_menu.visible = false
		_save_menu.close_requested.connect(_on_save_menu_closed)
		_save_menu.save_selected.connect(_on_save_slot_selected)
		add_child(_save_menu)

	# Tab menu
	var tm_packed: PackedScene = load("res://scenes/vn/TabMenu.tscn") as PackedScene
	if tm_packed:
		_tab_menu = tm_packed.instantiate()
		_tab_menu.name = "TabMenu"
		_tab_menu.visible = false
		add_child(_tab_menu)


func _load_plot() -> void:
	_show_loading()

	var path: String = "res://assets/plot/" + _plot_id + ".txt"
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	var text: String = ""

	if file:
		text = file.get_as_text()
		file.close()
	else:
		var json_path: String = "res://assets/plot/" + _plot_id + ".json"
		var json_file: FileAccess = FileAccess.open(json_path, FileAccess.READ)
		if json_file:
			text = json_file.get_as_text()
			json_file.close()

	if text.is_empty():
		push_error("VNInterface: Could not load plot '", _plot_id, "'")
		_hide_loading()
		return

	var parser: ScriptParser = ScriptParser.new(_plot_id)
	_plot = parser.parse(text)

	_node_index = clampi(_node_index, 0, max(0, _plot.nodes.size() - 1))
	_set_current_node(_node_index)
	_hide_loading()


# ===================================================================
# Node navigation
# ===================================================================

func _set_current_node(idx: int) -> void:
	if not _plot or idx < 0 or idx >= _plot.nodes.size():
		return
	_node_index = idx
	_current_node = _plot.nodes[idx]
	_visible_chars = 0
	_is_typing_finished = false
	_is_waiting = false
	_wait_timer = 0.0
	_auto_play_timer = 0.0
	_stop_cursor_blink()

	_apply_node_effects()


# ===================================================================
# Node effects
# ===================================================================

func _apply_node_effects() -> void:
	if not _current_node:
		return

	_apply_background()
	_apply_character()
	_apply_audio_effects()
	_apply_terminal_and_scene()
	_apply_glitch()
	_apply_wait()

	_update_dialogue_display()


func _apply_background() -> void:
	if _current_node.bg.is_empty():
		return
	_set_background(_current_node.bg)


func _apply_character() -> void:
	if _current_node.ch == "__CLEAR__":
		_set_character("")
	elif not _current_node.ch.is_empty():
		_set_character(_current_node.ch)
	elif not _current_node.who.is_empty():
		var char_path: String = _resolve_character_path(_current_node.who)
		if not char_path.is_empty():
			_set_character(char_path)


func _apply_audio_effects() -> void:
	if _current_node.bgm:
		if _current_node.bgm.stop:
			AudioManager.stop_bgm()
		elif not _current_node.bgm.play.is_empty():
			AudioManager.play_bgm(_current_node.bgm.play, _current_node.bgm.loop)

	if _current_node.sfx:
		if _current_node.sfx.stop:
			AudioManager.stop_sfx()
		elif not _current_node.sfx.play.is_empty():
			AudioManager.play_sfx(_current_node.sfx.play, _current_node.sfx.loop)

	if not _current_node.audio:
		return
	if _current_node.audio.stop:
		if _current_node.audio.audio_type == "bgm" or _current_node.audio.audio_type.is_empty():
			AudioManager.stop_bgm()
	elif not _current_node.audio.play.is_empty():
		match _current_node.audio.audio_type:
			"bgm": AudioManager.play_bgm(_current_node.audio.play, _current_node.audio.loop)
			"sfx": AudioManager.play_sfx(_current_node.audio.play, _current_node.audio.loop)
			"voice": AudioManager.play_voice(_current_node.audio.play)
			"ambience": AudioManager.play_ambience(_current_node.audio.play, _current_node.audio.loop)


func _apply_terminal_and_scene() -> void:
	if not _current_node.set_terminal.is_empty():
		_terminal_status = _current_node.set_terminal
		EventBus.terminal_status_changed.emit(_terminal_status)

	if _current_node.type == "scene" and not _current_node.next_scene.is_empty():
		scene_changed.emit(_current_node.next_scene)


func _apply_glitch() -> void:
	if _current_node.glitch and _settings.shader_quality == "high":
		_apply_glitch_effect(true)
	else:
		_apply_glitch_effect(false)


func _apply_wait() -> void:
	if _current_node.wait_time > 0.0:
		_is_waiting = true
		_wait_timer = 0.0
		_dialogue_text.visible_characters = 0


# ===================================================================
# Character & Background
# ===================================================================

func _resolve_character_path(who: String) -> String:
	var mapping: Dictionary = {
		"林子欣": "res://assets/characters/LinZixin/LinZixin_normal.png",
		"LinZixin": "res://assets/characters/LinZixin/LinZixin_normal.png",
		"???": "", "旁白": "", "narrator": "", "系统": "", "system": "",
	}
	if _plot and _plot.characters.has(who):
		return _plot.characters[who]
	return mapping.get(who, "")


func _set_background(path: String) -> void:
	var normalized: String = _normalize_asset_path(path)
	if _current_bg == normalized and not normalized.is_empty():
		return
	_current_bg = normalized
	var texture: Texture2D = _load_texture(normalized)
	if texture:
		_bg_rect.texture = texture
		var tween := create_tween()
		tween.tween_property(_bg_rect, "modulate:a", 1.0, 1.5).from(0.0)
	EventBus.background_changed.emit(normalized)


func _set_character(path: String) -> void:
	var normalized: String = _normalize_asset_path(path)
	_current_char = normalized

	if normalized.is_empty():
		_clear_character_sprite()
		return

	var texture: Texture2D = _load_texture(normalized)
	if texture:
		_char_rect.texture = texture
		_char_rect.modulate.a = 0.0
		_char_rect.position.x = -60.0
		var tween := create_tween()
		tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_EXPO)
		tween.set_parallel(true)
		tween.tween_property(_char_rect, "modulate:a", 1.0, 0.8)
		tween.tween_property(_char_rect, "position:x", 0.0, 0.8)
	EventBus.character_changed.emit(normalized)


func _clear_character_sprite() -> void:
	var tween := create_tween()
	tween.tween_property(_char_rect, "modulate:a", 0.0, 0.5)
	tween.tween_callback(_on_character_cleared)


func _on_character_cleared() -> void:
	_char_rect.texture = null


# ===================================================================
# Asset path normalization & loading
# ===================================================================

func _normalize_asset_path(path: String) -> String:
	if path.is_empty(): return path
	if path.begins_with("/Assests/"): return "res://assets/" + path.substr(9)
	if path.begins_with("/Assets/"): return "res://assets/" + path.substr(8)
	return path


func _load_texture(path: String) -> Texture2D:
	var normalized: String = _normalize_asset_path(path)
	if normalized.is_empty() or not ResourceLoader.exists(normalized):
		return null
	return load(normalized)


# ===================================================================
# Dialogue display
# ===================================================================

func _update_dialogue_display() -> void:
	if not _current_node:
		return

	var localized_text: String = _get_localized_text()
	_dialogue_text.text = localized_text
	_dialogue_text.visible_characters = _visible_chars

	# Dialogue font
	if not _is_zh() and _font_en_body:
		_dialogue_text.add_theme_font_override("normal_font", _font_en_body)
	elif _font_zh_body:
		_dialogue_text.add_theme_font_override("normal_font", _font_zh_body)

	# Text color
	if _current_node.glitch:
		_dialogue_text.add_theme_color_override("default_color", Color(1, 0.3, 0.3, 1))
	else:
		_dialogue_text.add_theme_color_override("default_color", Color.BLACK)

	# Dialogue box style
	_apply_dialogue_box_style(_current_node.glitch)

	# Speaker name
	var who: String = _current_node.who
	if who.is_empty() or who in ["???", "æç½", "Narrator", "narrator", "system", "system_text", "none"]:
		_speaker_name_container.visible = false
	else:
		_speaker_name_container.visible = true
		var speaker_name: String = who
		if who == "player":
			speaker_name = _player_name
		elif _plot:
			speaker_name = _plot.get_character_name(who, TranslationServer.get_locale())
		_speaker_name_label.text = speaker_name
		if not _is_zh() and _font_tcm:
			_speaker_name_label.add_theme_font_override("font", _font_tcm)
		elif _font_zh_title:
			_speaker_name_label.add_theme_font_override("font", _font_zh_title)
		_speaker_name_label.add_theme_color_override("font_color", Color.WHITE)
		var box_top: float = _dialogue_box.global_position.y
		_speaker_name_container.position.y = box_top - 64.0

	# Show/hide choices
	if _current_node.type == "select" and _choices_menu:
		var fonts: Dictionary = {"tcm": _font_tcm, "zh_title": _font_zh_title}
		_choices_menu.show_options(_current_node.options, fonts, TranslationServer.get_locale())
	else:
		if _choices_menu:
			_choices_menu.hide_options()

	# Typewriter speed
	var speed_map: Dictionary = {"slow": 0.080, "normal": 0.045, "fast": 0.020}
	var lang_mult: float = 0.65 if not _is_zh() else 1.0
	_typewriter_interval = speed_map.get(_settings.text_speed, 0.045) * lang_mult
	if _current_node.glitch:
		_typewriter_interval = 0.020


func _apply_dialogue_box_style(glitch: bool) -> void:
	var style := StyleBoxFlat.new()
	if glitch:
		style.bg_color = Color(0.102, 0, 0, 1)
		style.border_color = Color(1, 0, 0, 1)
	else:
		style.bg_color = Color.WHITE
		style.border_color = Color(0, 0, 0, 0.1)
	style.border_width_bottom = 8
	style.shadow_size = 30
	style.shadow_offset = Vector2(12, 24)
	style.shadow_color = Color(0, 0, 0, 0.35)
	style.corner_radius_top_left = 2
	style.corner_radius_top_right = 2
	_dialogue_box.add_theme_stylebox_override("panel", style)


func _get_localized_text() -> String:
	if not _current_node: return ""
	var text: String = _current_node.EN if not _is_zh() and not _current_node.EN.is_empty() else _current_node.ZH
	return text.replace("{player}", _player_name)


# ===================================================================
# Cursor blink
# ===================================================================

func _start_cursor_blink() -> void:
	_cursor_blink.visible = true
	_cursor_blink.modulate.a = 1.0
	if _cursor_blink_tween and _cursor_blink_tween.is_valid():
		_cursor_blink_tween.kill()
	_cursor_blink_tween = create_tween().set_loops()
	_cursor_blink_tween.tween_property(_cursor_blink, "modulate:a", 0.2, 0.5)
	_cursor_blink_tween.tween_property(_cursor_blink, "modulate:a", 1.0, 0.5)


func _stop_cursor_blink() -> void:
	_cursor_blink.visible = false
	if _cursor_blink_tween and _cursor_blink_tween.is_valid():
		_cursor_blink_tween.kill()
		_cursor_blink_tween = null


# ===================================================================
# Glitch effect (no shake)
# ===================================================================

func _apply_glitch_effect(enable: bool) -> void:
	if not enable:
		_glitch_overlay.visible = false
		_bg_rect.modulate = Color.WHITE
		_apply_dialogue_box_style(false)
		position.x = 0.0
		return

	_glitch_overlay.visible = _settings.shader_quality == "high"
	_bg_rect.modulate = Color(0.1, 0, 0, 1)
	_apply_dialogue_box_style(true)


# ===================================================================
# Sticky assets
# ===================================================================

func _resolve_sticky_assets() -> void:
	if not _plot or _plot.nodes.is_empty(): return
	var start_idx: int = mini(_node_index, _plot.nodes.size() - 1)

	for i: int in range(start_idx, -1, -1):
		var bg: String = _plot.nodes[i].bg
		if not bg.is_empty():
			var normalized: String = _normalize_asset_path(bg)
			if _current_bg != normalized:
				_current_bg = normalized
				var texture: Texture2D = _load_texture(normalized)
				if texture: _bg_rect.texture = texture
			break

	for i: int in range(start_idx, -1, -1):
		var ch: String = _plot.nodes[i].ch
		if not ch.is_empty():
			if ch == "__CLEAR__": _set_character("")
			elif _current_char != ch: _set_character(ch)
			break


# ===================================================================
# Advance / Progression
# ===================================================================

func _advance() -> void:
	if not _plot or not _current_node: return

	if not _is_typing_finished and not _is_waiting:
		_visible_chars = _get_localized_text().length()
		_dialogue_text.visible_characters = _visible_chars
		_is_typing_finished = true
		_start_cursor_blink()
		return

	if _is_waiting:
		_is_waiting = false
		_wait_timer = 0.0
		_visible_chars = 0
		_is_typing_finished = false
		_dialogue_text.visible_characters = 0
		_update_dialogue_display()
		return

	if _current_node.type == "select":
		_is_skipping = false
		return

	_stop_cursor_blink()
	_play_click()

	if _node_index < _plot.nodes.size() - 1:
		var next_idx: int = _node_index + 1
		_set_current_node(next_idx)
		_resolve_sticky_assets()
		var title: String = _get_node_chapter()
		GameManager.set_auto_save(_plot_id, next_idx, _player_name, title, _get_localized_text().substr(0, 50))
	else:
		_is_skipping = false
		AudioManager.stop_voice()
		AudioManager.stop_ambience()
		back_requested.emit()


func _get_node_chapter() -> String:
	if not _plot: return ""
	for i: int in range(_node_index, -1, -1):
		if _plot.nodes[i].chapter:
			var ch: LocText = _plot.nodes[i].chapter
			return ch.ZH if _is_zh() else ch.EN
	return _plot.title.ZH if _is_zh() else _plot.title.EN


# ===================================================================
# Choices (delegated to ChoicesMenu)
# ===================================================================

func _on_choice_selected(choice_index: int) -> void:
	if not _current_node or _current_node.type != "select": return
	if choice_index < 0 or choice_index >= _current_node.options.size(): return

	var opt: PlotOption = _current_node.options[choice_index]
	_play_click()

	if not opt.target_plot_id.is_empty():
		_plot_id = opt.target_plot_id
		_node_index = opt.target_node_index if opt.target_node_index >= 0 else 0
		_load_plot()
		_resolve_sticky_assets()
	else:
		var target_idx: int = opt.target_node_index if opt.target_node_index >= 0 else 0
		if target_idx >= 0:
			_set_current_node(target_idx)
			_resolve_sticky_assets()


# ===================================================================
# Save menu (delegated to SaveMenu)
# ===================================================================

func _toggle_save_menu() -> void:
	if not _save_menu: return
	_is_menu_open = not _is_menu_open
	if _is_menu_open:
		var fonts: Dictionary = {"tcm": _font_tcm, "zh_body": _font_zh_body, "zh_title": _font_zh_title, "en_body": _font_en_body}
		_save_menu.open(fonts, TranslationServer.get_locale())
		AudioManager.set_menu_mode(true)
	else:
		_save_menu.visible = false
		AudioManager.set_menu_mode(false)


func _on_save_menu_closed() -> void:
	_is_menu_open = false
	_save_menu.visible = false
	AudioManager.set_menu_mode(false)


func _on_save_slot_selected(index: int) -> void:
	if not _plot or not _current_node: return

	var existing: SaveData = GameManager.load_game(index)
	if existing:
		_pending_save_slot = index
		_show_overwrite_modal()
		return

	_do_save_slot(index)
	_toggle_save_menu()


func _do_save_slot(index: int) -> void:
	var title: String = _get_node_chapter()
	GameManager.save_game(index, _plot_id, _node_index, _player_name, title, _get_localized_text(), _terminal_status)


# ===================================================================
# Overwrite confirmation
# ===================================================================

func _show_overwrite_modal() -> void:
	var modal_script: GDScript = load("res://scenes/modals/OverwriteConfirm.gd")
	var modal: Control = modal_script.new()
	modal.name = "OverwriteConfirmInstance"
	modal.set_anchors_preset(Control.PRESET_FULL_RECT)
	modal.confirmed.connect(_on_overwrite_confirmed)
	modal.cancelled.connect(_on_overwrite_cancelled)
	add_child(modal)


func _on_overwrite_confirmed() -> void:
	if _pending_save_slot >= 0 and _plot and _current_node:
		_do_save_slot(_pending_save_slot)
	_remove_overwrite_modal()
	_pending_save_slot = -1
	_toggle_save_menu()


func _on_overwrite_cancelled() -> void:
	_remove_overwrite_modal()
	_pending_save_slot = -1


func _remove_overwrite_modal() -> void:
	for child: Node in get_children():
		if child.name == "OverwriteConfirmInstance":
			child.queue_free()


func _has_active_overwrite_modal() -> bool:
	for child: Node in get_children():
		if child.name == "OverwriteConfirmInstance":
			return true
	return false


# ===================================================================
# Tab menu (delegated to TabMenu)
# ===================================================================

func _toggle_tab_menu() -> void:
	if not _tab_menu: return
	_is_tab_menu_open = not _is_tab_menu_open
	_tab_menu.visible = _is_tab_menu_open
	if _is_tab_menu_open:
		_tab_menu.open(_terminal_status, _current_bg)
	else:
		_tab_menu.close()


# ===================================================================
# Loading (delegated to LoadingScreen)
# ===================================================================

func _show_loading() -> void:
	if _loading_screen:
		_loading_screen.show_loading()
	_dialogue_box.visible = false


func _hide_loading() -> void:
	if _loading_screen:
		_loading_screen.hide_loading()
	_dialogue_box.visible = true


# ===================================================================
# Controls hint bar
# ===================================================================

func _create_controls_hint() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.9)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_controls_hint.add_child(bg)

	var hb: HBoxContainer = HBoxContainer.new()
	hb.set_anchors_preset(Control.PRESET_FULL_RECT)
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 32)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_controls_hint.add_child(hb)

	_add_hint_button(hb, "Save", "S", false, _toggle_save_menu)
	_add_hint_button(hb, "Auto", "A", _settings.auto_play, _toggle_auto)
	_add_hint_button(hb, "Skip", "X", _is_skipping, _toggle_skip)


func _add_hint_button(parent: HBoxContainer, label_text: String, key: String, active: bool, callback: Callable) -> void:
	var group: Control = Control.new()
	group.custom_minimum_size = Vector2(110, 72)
	group.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	group.mouse_filter = Control.MOUSE_FILTER_STOP
	group.gui_input.connect(_on_hint_clicked.bind(callback))
	parent.add_child(group)

	var hb: HBoxContainer = HBoxContainer.new()
	hb.anchors_preset = Control.PRESET_FULL_RECT
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 8)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	group.add_child(hb)

	var lbl := Label.new()
	lbl.text = label_text
	lbl.add_theme_color_override("font_color", Color.WHITE if active else Color(1, 1, 1, 0.3))
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _font_tcm: lbl.add_theme_font_override("font", _font_tcm)
	hb.add_child(lbl)

	var box := ColorRect.new()
	box.custom_minimum_size = Vector2(36, 36)
	if active:
		box.color = Color(1, 0, 0, 1) if key == "X" else Color.WHITE
	else:
		box.color = Color(1, 1, 1, 0.15)
	hb.add_child(box)

	var key_lbl := Label.new()
	key_lbl.text = key
	key_lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	key_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	key_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	key_lbl.add_theme_color_override("font_color", Color.BLACK if active and key != "X" else Color.WHITE)
	key_lbl.add_theme_font_size_override("font_size", 20)
	key_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(key_lbl)


func _on_hint_clicked(event: InputEvent, callback: Callable) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_play_click()
		callback.call()


func _toggle_auto() -> void:
	GameManager.set_setting("auto_play", not _settings.auto_play)
	_settings = GameManager.get_settings()


func _toggle_skip() -> void:
	_is_skipping = not _is_skipping
	_play_click()


# ===================================================================
# Audio
# ===================================================================

func _play_click() -> void:
	AudioManager.play_sfx(AudioManager.SFX_CLICK)


# ===================================================================
# Process
# ===================================================================

func _process(delta: float) -> void:
	if not _current_node: return

	if _is_waiting:
		_wait_timer += delta
		if _wait_timer >= _current_node.wait_time:
			_is_waiting = false
			_wait_timer = 0.0
			_visible_chars = 0
			_is_typing_finished = false
			_update_dialogue_display()
		return

	var text: String = _get_localized_text()

	if not _is_typing_finished and _visible_chars < text.length():
		_typewriter_timer += delta
		if _typewriter_timer >= _typewriter_interval:
			_typewriter_timer = 0.0
			_visible_chars += 1
			_dialogue_text.visible_characters = _visible_chars
			if _visible_chars >= text.length():
				_is_typing_finished = true
				_start_cursor_blink()

	if (_settings.auto_play and _is_typing_finished
		and _current_node.type != "select"
		and not _is_skipping
		and not _is_menu_open
		and not _is_tab_menu_open):
		_auto_play_timer += delta
		if _auto_play_timer >= _auto_play_delay:
			_auto_play_timer = 0.0
			_advance()

	if _is_skipping and _current_node.type != "select" and not _is_menu_open and not _is_tab_menu_open:
		var skip_delay: float = 0.04 if _is_typing_finished else 0.01
		_auto_play_timer += delta
		if _auto_play_timer >= skip_delay:
			_auto_play_timer = 0.0
			_advance()


# ===================================================================
# Input
# ===================================================================

func _input(event: InputEvent) -> void:
	if not event.is_pressed(): return

	if _has_active_overwrite_modal(): return

	if event.is_action_pressed("vn_tab"):
		_toggle_tab_menu()
		get_viewport().set_input_as_handled()
		return

	if _is_menu_open:
		# Save menu handles its own input
		return

	if _is_tab_menu_open:
		# Tab menu handles its own input
		return

	if _current_node and _current_node.type == "select" and _is_typing_finished:
		# Choices menu handles its own input
		return

	if event.is_action_pressed("vn_save"):
		_toggle_save_menu()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("vn_skip"):
		_play_click()
		if _is_skipping:
			_is_skipping = false
		else:
			if _settings.auto_play:
				GameManager.set_setting("auto_play", false)
				_settings = GameManager.get_settings()
			_is_skipping = true
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("vn_auto"):
		_play_click()
		GameManager.set_setting("auto_play", not _settings.auto_play)
		_settings = GameManager.get_settings()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		_advance()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel"):
		back_requested.emit()
		get_viewport().set_input_as_handled()


# ===================================================================
# Cleanup
# ===================================================================

func _exit_tree() -> void:
	_exit_tree_called = true
	_stop_cursor_blink()
	AudioManager.stop_voice()
	AudioManager.stop_ambience()
	AudioManager.set_vn_effect(0)
	AudioManager.reset_effects()
