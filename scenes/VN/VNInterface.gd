## VNInterface : Control
## Core visual novel gameplay scene — backgrounds, sprites, dialogue, typewriter.
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
var _is_log_open: bool = false
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
	return GameManager.is_locale("zh")

# Typewriter / wait / auto timers
var _typewriter_timer: float = 0.0
var _typewriter_interval: float = 0.045
var _auto_play_timer: float = 0.0
var _auto_play_delay: float = 2.0
var _wait_timer: float = 0.0
var _is_waiting: bool = false

# Tween references
var _exit_tree_called: bool = false

# Mouse position tracking (fed to VNBackground for parallax)
var _mouse_pos: Vector2 = Vector2.ZERO

# Sub-scene instances
var _save_menu: SaveMenu = null
var _choices_menu: ChoicesMenu = null
var _loading_screen: LoadingScreen = null
var _tab_menu: TabMenu = null
var _log_screen: LogScreen = null

# Dialogue history for Log screen
var _log_entries: Array[Dictionary] = []

# ---------------------------------------------------------------------------
# Onready — core VN nodes
# ---------------------------------------------------------------------------
@onready var _vn_bg: VNBackground = %VNBackground
@onready var _char_rect: TextureRect = %CharacterRect
@onready var _dialogue_box: Panel = %DialogueBox
@onready var _dialogue_text: RichTextLabel = %DialogueText
@onready var _speaker_name_container: Control = %SpeakerNameContainer
@onready var _glitch_overlay: ColorRect = %GlitchOverlay
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

	# Reset VN background state for fresh load
	_current_bg = ""
	_last_speaker_name = ""
	_vn_bg.reset()

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
		_loading_screen = ls_packed.instantiate() as LoadingScreen
		_loading_screen.name = "LoadingScreen"
		add_child(_loading_screen)

	# Choices menu
	var cm_packed: PackedScene = load("res://scenes/vn/ChoicesMenu.tscn") as PackedScene
	if cm_packed:
		_choices_menu = cm_packed.instantiate() as ChoicesMenu
		_choices_menu.name = "ChoicesMenu"
		_choices_menu.visible = false
		_choices_menu.choice_selected.connect(_on_choice_selected)
		add_child(_choices_menu)

	# Save menu
	var sm_packed: PackedScene = load("res://scenes/vn/SaveMenu.tscn") as PackedScene
	if sm_packed:
		_save_menu = sm_packed.instantiate() as SaveMenu
		_save_menu.name = "SaveMenu"
		_save_menu.visible = false
		_save_menu.close_requested.connect(_on_save_menu_closed)
		_save_menu.save_selected.connect(_on_save_slot_selected)
		add_child(_save_menu)

	# Tab menu — built in code (matching QuitConfirm style)
	_tab_menu = TabMenu.new()
	_tab_menu.name = "TabMenu"
	_tab_menu.visible = false
	_tab_menu.back_to_title.connect(_on_tab_back_to_title)
	_tab_menu.close_requested.connect(_on_tab_menu_closed)
	_tab_menu.open_settings.connect(_on_tab_open_settings)
	add_child(_tab_menu)

	# Log screen — loaded from tscn
	var log_packed: PackedScene = load("res://scenes/vn/LogScreen.tscn") as PackedScene
	if log_packed:
		_log_screen = log_packed.instantiate() as LogScreen
		_log_screen.name = "LogScreen"
		_log_screen.visible = false
		_log_screen.close_requested.connect(_on_log_closed)
		add_child(_log_screen)


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
	_apply_node_effects()
	_refresh_controls_hint()

	# Record dialogue immediately (not just on advance)
	if _current_node.type == "text" and not (_current_node.ZH.is_empty() and _current_node.EN.is_empty()):
		_log_entries.append({
			"who": _current_node.who,
			"zh": _current_node.ZH,
			"en": _current_node.EN,
		})


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
	_apply_stop_transition()
	_apply_fade_black()

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
	# --- BGM (via VNAudioService — supports crossfade) ---
	if _current_node.bgm:
		var bgm_cmd: AudioCommand = _current_node.bgm
		if bgm_cmd.stop:
			if bgm_cmd.fade_out_only:
				VNAudioService.fade_out_bgm(bgm_cmd.fade_out_duration)
			else:
				# Legacy stopmusic / stopall — immediate stop
				VNAudioService.stop_bgm()
				AudioManager.stop_bgm()
		elif not bgm_cmd.play.is_empty():
			if bgm_cmd.crossfade:
				VNAudioService.crossfade_bgm(bgm_cmd.play, bgm_cmd.fade_out_duration, bgm_cmd.fade_in_duration)
			else:
				VNAudioService.play_bgm(bgm_cmd.play, bgm_cmd.loop)

	# --- SFX (via AudioManager) ---
	if _current_node.sfx:
		if _current_node.sfx.stop:
			AudioManager.stop_sfx()
		elif not _current_node.sfx.play.is_empty():
			AudioManager.play_sfx(_current_node.sfx.play, _current_node.sfx.loop)

	# --- Ambience (via VNAudioService) ---
	if _current_node.ambience:
		var amb_cmd: AudioCommand = _current_node.ambience
		if amb_cmd.stop:
			VNAudioService.clear_all_ambience(1.0)
		elif not amb_cmd.play.is_empty():
			VNAudioService.set_ambience_layer(0, amb_cmd.play, amb_cmd.ambience_volume)

	# --- Legacy audio field ---
	if not _current_node.audio:
		return
	if _current_node.audio.stop:
		if _current_node.audio.audio_type == "bgm" or _current_node.audio.audio_type.is_empty():
			VNAudioService.stop_bgm()
			AudioManager.stop_bgm()
		elif _current_node.audio.audio_type == "ambience":
			VNAudioService.clear_all_ambience(0.5)
	elif not _current_node.audio.play.is_empty():
		match _current_node.audio.audio_type:
			"bgm":
				VNAudioService.play_bgm(_current_node.audio.play, _current_node.audio.loop)
				AudioManager.play_bgm(_current_node.audio.play, _current_node.audio.loop)
			"sfx":
				AudioManager.play_sfx(_current_node.audio.play, _current_node.audio.loop)
			"voice":
				AudioManager.play_voice(_current_node.audio.play)
			"ambience":
				VNAudioService.set_ambience_layer(0, _current_node.audio.play, 0.5)


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


func _apply_fade_black() -> void:
	if _current_node.fade_black > 0.0:
		_vn_bg.fade_to_black(_current_node.fade_black)


func _apply_stop_transition() -> void:
	# Stop transition: hide dialogue box and speaker name temporarily.
	# They will reappear when the next non-stop node renders.
	if _current_node.stop_transition:
		_dialogue_box.visible = false
		_speaker_name_container.visible = false
	else:
		_dialogue_box.visible = true
		# Speaker name visibility is handled in _update_dialogue_display


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
	_vn_bg.set_bg(normalized)
	_vn_bg.fade_from_black(1.0)
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
	# Apply emphasis and annotation BBCode transforms
	localized_text = _apply_text_styling(localized_text)
	_dialogue_text.text = localized_text
	_dialogue_text.visible_characters = _visible_chars

	# Dialogue font — body text with explicit size
	var body_font_size: int = 24
	if not _is_zh() and _font_en_body:
		_dialogue_text.add_theme_font_override("normal_font", _font_en_body)
		body_font_size = 22
	elif _font_zh_body:
		_dialogue_text.add_theme_font_override("normal_font", _font_zh_body)
		body_font_size = 26
	_dialogue_text.add_theme_font_size_override("normal_font_size", body_font_size)

	# Also set bold / italics / monospace font overrides for BBCode
	if _font_zh_emphasis:
		_dialogue_text.add_theme_font_override("italics_font", _font_zh_emphasis)
		_dialogue_text.add_theme_font_size_override("italics_font_size", body_font_size)
	if _font_en_emphasis:
		_dialogue_text.add_theme_font_override("bold_italics_font", _font_en_emphasis)

	# Text color
	if _current_node.glitch:
		_dialogue_text.add_theme_color_override("default_color", Color(1, 0.3, 0.3, 1))
	else:
		_dialogue_text.add_theme_color_override("default_color", Color.BLACK)

	# Dialogue box style
	_apply_dialogue_box_style(_current_node.glitch)

	# Speaker name
	var who: String = _current_node.who
	if who.is_empty() or who in ["???", "旁白", "Narrator", "narrator", "system", "system_text", "none"]:
		_speaker_name_container.visible = false
	else:
		_speaker_name_container.visible = true
		var speaker_name: String = who
		if who == "player" or who == "我":
			speaker_name = _player_name
		elif _plot:
			speaker_name = _plot.get_character_name(who, TranslationServer.get_locale())
		_build_speaker_name(speaker_name)
		var box_top: float = _dialogue_box.global_position.y
		_speaker_name_container.position.y = box_top - 64.0

	# Show/hide choices
	if _current_node.type == "select" and _choices_menu:
		var fonts: Dictionary = {"tcm": _font_tcm, "zh_title": _font_zh_title, "zh_body": _font_zh_body, "en_body": _font_en_body}
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


var _name_hbox: HBoxContainer = null
var _last_speaker_name: String = ""

func _build_speaker_name(name_text: String) -> void:
	# Only rebuild if the name actually changed
	if name_text == _last_speaker_name:
		return
	_last_speaker_name = name_text

	# Lazy-create the HBox once
	if not _name_hbox:
		_name_hbox = HBoxContainer.new()
		_name_hbox.name = "NameHBox"
		_name_hbox.alignment = BoxContainer.ALIGNMENT_END
		_name_hbox.add_theme_constant_override("separation", 0)
		_name_hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_name_hbox.position = Vector2(20, 0)
		_speaker_name_container.add_child(_name_hbox)

	# Clear and rebuild character labels
	for c in _name_hbox.get_children():
		c.queue_free()

	var is_zh: bool = _is_zh()
	var font: Font = _font_tcm if not is_zh and _font_tcm else _font_zh_title
	var sizes: Array[int] = [28, 24, 22, 24]

	for i: int in range(name_text.length()):
		var ch: String = name_text[i]
		var lbl: Label = Label.new()
		lbl.text = ch
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		lbl.size_flags_vertical = Control.SIZE_SHRINK_END
		var fs: int = sizes[i % sizes.size()]
		lbl.add_theme_font_size_override("font_size", fs)
		lbl.add_theme_color_override("font_color", Color.WHITE)
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if font: lbl.add_theme_font_override("font", font)
		_name_hbox.add_child(lbl)


## Transform emphasis markers into BBCode.
## [em]...[/em] → italic with emphasis font (simfang / timesi).
## [ann=tip]...[/ann] → underlined annotation with tooltip.
func _apply_text_styling(text: String) -> String:
	if text.is_empty():
		return text

	# [em]text[/em] → [i]text[/i]  (rendered with emphasis font via italics_font override)
	var result: String = text.replace("[em]", "[i]").replace("[/em]", "[/i]")

	# [ann=TIP]text[/ann] → [url=TIP]text[/url]  (underline + hover tooltip via meta)
	var ann_regex := RegEx.new()
	ann_regex.compile("\\[ann=(.*?)\\](.*?)\\[/ann\\]")
	result = ann_regex.sub(result, "[url=$1]$2[/url]", true)

	return result


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
	style.shadow_offset = Vector2(0, 24)
	style.shadow_color = Color(0, 0, 0, 0.35)
	style.corner_radius_top_left = 2
	style.corner_radius_top_right = 2
	_dialogue_box.add_theme_stylebox_override("panel", style)


func _get_localized_text() -> String:
	if not _current_node: return ""
	var text: String = _current_node.EN if not _is_zh() and not _current_node.EN.is_empty() else _current_node.ZH
	return text.replace("{player}", _player_name)


# ===================================================================
# Glitch effect (no shake)
# ===================================================================

func _apply_glitch_effect(enable: bool) -> void:
	if not enable:
		_glitch_overlay.visible = false
		_vn_bg.modulate = Color.WHITE
		_apply_dialogue_box_style(false)
		position.x = 0.0
		return

	_glitch_overlay.visible = _settings.shader_quality == "high"
	_vn_bg.modulate = Color(0.1, 0, 0, 1)
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
				if texture: _vn_bg.set_bg(normalized)
			break

	for i: int in range(start_idx, -1, -1):
		var ch: String = _plot.nodes[i].ch
		if not ch.is_empty():
			if ch == "__CLEAR__": _set_character("")
			elif _current_char != ch: _set_character(ch)
			break

	for i: int in range(start_idx, -1, -1):
		var bgm: AudioCommand = _plot.nodes[i].bgm
		if bgm and not bgm.play.is_empty():
			VNAudioService.play_bgm(bgm.play, bgm.loop)
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

	_play_click()

	# Back to title if this node triggers it
	if _current_node.back_to_title:
		back_requested.emit()
		return

	# Auto-jump to another plot if this node has a jump target
	if not _current_node.jump_plot_id.is_empty():
		_plot_id = _current_node.jump_plot_id
		_node_index = _current_node.jump_node_index
		_load_plot()
		return

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
		_save_menu.close_animated()
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
# Controls hint bar (bottom-right: Save / Auto / Skip)
# Mirrors the web version's Action Hints.
# ===================================================================

var _hint_save_lbl: Label = null
var _hint_auto_lbl: Label = null
var _hint_auto_box: ColorRect = null
var _hint_auto_key: Label = null
var _hint_log_lbl: Label = null
var _hint_log_box: ColorRect = null
var _hint_log_key: Label = null


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

	# Save — simple button, toggles save menu
	var save_group: Control = _make_hint_group(_toggle_save_menu)
	hb.add_child(save_group)
	_hint_save_lbl = _add_hint_label(save_group, "Save", false)

	var save_box := ColorRect.new()
	save_box.custom_minimum_size = Vector2(36, 36)
	save_box.color = Color(1, 1, 1, 0.15)
	save_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	save_group.get_child(0).add_child(save_box)
	_add_hint_key(save_box, "S")

	# Auto — toggle, reflects auto_play state
	var auto_group: Control = _make_hint_group(_toggle_auto)
	hb.add_child(auto_group)
	_hint_auto_lbl = _add_hint_label(auto_group, "Auto", _settings.auto_play)

	_hint_auto_box = ColorRect.new()
	_hint_auto_box.custom_minimum_size = Vector2(36, 36)
	_hint_auto_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	auto_group.get_child(0).add_child(_hint_auto_box)
	_hint_auto_key = _add_hint_key(_hint_auto_box, "A")

	# Log — opens dialogue history overlay
	var log_group: Control = _make_hint_group(_toggle_log)
	hb.add_child(log_group)
	_hint_log_lbl = _add_hint_label(log_group, "Log", false)

	_hint_log_box = ColorRect.new()
	_hint_log_box.custom_minimum_size = Vector2(36, 36)
	_hint_log_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	log_group.get_child(0).add_child(_hint_log_box)
	_hint_log_key = _add_hint_key(_hint_log_box, "Z")

	_refresh_controls_hint()


func _make_hint_group(callback: Callable) -> Control:
	var group: Control = Control.new()
	group.custom_minimum_size = Vector2(110, 72)
	group.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	group.mouse_filter = Control.MOUSE_FILTER_STOP
	group.gui_input.connect(_on_hint_clicked.bind(callback))

	var hb: HBoxContainer = HBoxContainer.new()
	hb.anchors_preset = Control.PRESET_FULL_RECT
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 8)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	group.add_child(hb)
	return group


func _add_hint_label(group: Control, text: String, active: bool) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", Color.WHITE if active else Color(1, 1, 1, 0.3))
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not _is_zh() and _font_tcm:
		lbl.add_theme_font_override("font", _font_tcm)
	elif _font_zh_title:
		lbl.add_theme_font_override("font", _font_zh_title)
	group.get_child(0).add_child(lbl)
	return lbl


func _add_hint_key(box: ColorRect, key: String) -> Label:
	var key_lbl := Label.new()
	key_lbl.text = key
	key_lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	key_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	key_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	key_lbl.add_theme_font_size_override("font_size", 16)
	key_lbl.add_theme_color_override("font_color", Color(1, 1, 1, 0.5))
	key_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _font_tcm: key_lbl.add_theme_font_override("font", _font_tcm)
	box.add_child(key_lbl)
	return key_lbl


func _refresh_controls_hint() -> void:
	if not _hint_auto_lbl:
		return

	var is_select: bool = _current_node != null and _current_node.type == "select"

	# Auto — highlighted when auto_play is ON
	var auto_on: bool = _settings.auto_play and not is_select
	_hint_auto_lbl.add_theme_color_override("font_color", Color.WHITE if auto_on else Color(1, 1, 1, 0.3))
	_hint_auto_box.color = Color.WHITE if auto_on else Color(1, 1, 1, 0.15)
	_hint_auto_key.add_theme_color_override("font_color", Color.BLACK if auto_on else Color.WHITE)

	# Log — always available, dimmed at choices
	var log_blocked: bool = is_select or _is_log_open
	_hint_log_lbl.add_theme_color_override("font_color", Color(1, 1, 1, 0.1) if log_blocked else Color(1, 1, 1, 0.3))
	_hint_log_box.color = Color(1, 1, 1, 0.05) if log_blocked else Color(1, 1, 1, 0.15)
	_hint_log_key.add_theme_color_override("font_color", Color.WHITE)

	# Dim disabled hints during choices
	if is_select:
		_hint_auto_lbl.add_theme_color_override("font_color", Color(1, 1, 1, 0.1))
		_hint_auto_box.color = Color(1, 1, 1, 0.05)


func _on_hint_clicked(event: InputEvent, callback: Callable) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_play_click()
		callback.call()


func _toggle_auto() -> void:
	GameManager.set_setting("auto_play", not _settings.auto_play)
	_settings = GameManager.get_settings()
	_refresh_controls_hint()


func _toggle_log() -> void:
	if _is_log_open:
		_log_screen.close()
		_on_log_closed()
	else:
		if not _log_screen: return
		_is_log_open = true
		# Stop BGM but keep SFX / ambience
		VNAudioService.stop_bgm()
		AudioManager.stop_bgm()
		_log_screen.open(_log_entries)
		_log_screen.visible = true
		_play_click()
	_refresh_controls_hint()


func _on_tab_menu_closed() -> void:
	_is_tab_menu_open = false


func _on_tab_open_settings() -> void:
	_is_tab_menu_open = false
	# Tell SceneManager to open Settings and return to VN when done
	scene_changed.emit("SETTINGS_FROM_VN")


func _on_tab_back_to_title() -> void:
	_is_tab_menu_open = false
	back_requested.emit()


func _on_log_closed() -> void:
	_is_log_open = false
	if _log_screen:
		_log_screen.visible = false
	# Resume BGM from current node's sticky BGM (handled naturally by resolve)
	_resolve_sticky_assets()
	_refresh_controls_hint()


# ===================================================================
# Audio
# ===================================================================

func _play_click() -> void:
	AudioManager.play_sfx(AudioManager.SFX_CLICK)


# ===================================================================
# Process
# ===================================================================

func _process(delta: float) -> void:
	# Parallax: delegate to VNBackground
	if _mouse_pos == Vector2.ZERO:
		_mouse_pos = get_viewport().get_mouse_position()
	var vs: Vector2 = get_viewport().get_visible_rect().size
	_vn_bg.update_parallax(_mouse_pos, vs, delta)

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

	if (_settings.auto_play and _is_typing_finished
		and _current_node.type != "select"
		and not _is_skipping
		and not _is_menu_open
		and not _is_tab_menu_open
		and not _is_log_open):
		_auto_play_timer += delta
		if _auto_play_timer >= _auto_play_delay:
			_auto_play_timer = 0.0
			_advance()

	if _is_skipping and _current_node.type != "select" and not _is_menu_open and not _is_tab_menu_open and not _is_log_open:
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

	# Log screen has its own input handling
	if _is_log_open:
		return

	if event.is_action_pressed("vn_tab"):
		_toggle_tab_menu()
		get_viewport().set_input_as_handled()
		return

	if _is_menu_open:
		return

	if _is_tab_menu_open:
		return

	if _current_node and _current_node.type == "select" and _is_typing_finished:
		return

	if event.is_action_pressed("vn_save"):
		_toggle_save_menu()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("vn_log"):
		_toggle_log()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("vn_auto"):
		_toggle_auto()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		_advance()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel"):
		# ESC toggles skip/fast-forward (same as old X key)
		if _current_node and _current_node.type != "select":
			_is_skipping = not _is_skipping
			if _is_skipping and _settings.auto_play:
				GameManager.set_setting("auto_play", false)
				_settings = GameManager.get_settings()
			_play_click()
		get_viewport().set_input_as_handled()


func _gui_input(event: InputEvent) -> void:
	# Track mouse position for parallax
	if event is InputEventMouseMotion:
		_mouse_pos = event.position

	# Mouse left-click anywhere on the VN area advances the dialogue
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if _has_active_overwrite_modal(): return
		if _is_log_open: return
		if _is_menu_open or _is_tab_menu_open: return
		if _current_node and _current_node.type == "select" and _is_typing_finished: return
		_advance()
		accept_event()


# ===================================================================
# Cleanup
# ===================================================================

func _exit_tree() -> void:
	_exit_tree_called = true
	AudioManager.stop_voice()
	AudioManager.stop_ambience()
	AudioManager.set_vn_effect(0)
	AudioManager.reset_effects()
