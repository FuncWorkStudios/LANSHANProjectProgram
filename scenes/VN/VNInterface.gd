## VNInterface : Control
## Core visual novel gameplay scene — backgrounds, sprites, dialogue, typewriter.
## Sub-scenes (TabMenu, SaveMenu, ChoicesMenu, LoadingScreen) are independent.
extends Control

# Story text — preloaded at compile time from generated .gd files.
# Source .txt files live in assets/plot/. Run tempp/regen_stories.sh to sync.
const STORY_TEXTS: Dictionary = {
	"intro":    preload("res://scripts/story/Story_Intro.gd"),
	"chapter1": preload("res://scripts/story/Story_Chapter1.gd"),
	"chapter2": preload("res://scripts/story/Story_Chapter2.gd"),
	"chapter3": preload("res://scripts/story/Story_Chapter3.gd"),
	"chapter4": preload("res://scripts/story/Story_Chapter4.gd"),
}


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

# Pre-compiled regex — avoids per-node allocation (optimisation)
var _ann_regex: RegEx
var _em_marker_regex: RegEx
var _ann_marker_regex: RegEx

# Annotation tooltip — shown on hover over [url] tags
var _annotation_tooltip: Label = null

# Pre-built font/style resources — avoids per-node Dictionary allocation
var _font_dict: Dictionary = {}
var _dialogue_style_normal: StyleBoxFlat
var _dialogue_style_glitch: StyleBoxFlat
var _last_locale_was_zh: bool  # tracks when locale changes to skip redundant font overrides

# Tween references
var _exit_tree_called: bool = false

# Auto-advance chain — drives chapter transitions without user input
var _is_auto_advancing: bool = false

# Skip indicator — shown in the top-right corner while fast-forward is active
var _skip_indicator: Label = null

# Mouse position tracking (fed to VNBackground for parallax)
var _mouse_pos: Vector2 = Vector2.ZERO

# CTRL key edge-detection for skip toggle (fallback when _input doesn't fire)
var _ctrl_was_down: bool = false

# Sub-scene instances
var _save_menu: Control = null
var _choices_menu: Control = null
var _loading_screen: Control = null
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

	# ── Reset all session-level state for a clean start ──
	_plot = null; _plot_id = ""; _node_index = 0; _current_node = null
	_visible_chars = 0; _is_typing_finished = false
	_is_menu_open = false; _is_tab_menu_open = false; _is_log_open = false
	_is_skipping = false; _pending_save_slot = -1
	_terminal_status = "locked"
	_current_bg = ""; _current_char = ""
	_char_rect.texture = null; _char_rect.visible = true
	_char_rect.modulate.a = 1.0; _char_rect.position.x = 0.0
	_log_entries.clear()
	_exit_tree_called = false; _ctrl_was_down = false
	_typewriter_timer = 0.0; _auto_play_timer = 0.0
	_wait_timer = 0.0; _is_waiting = false; _is_auto_advancing = false
	_last_speaker_name = ""

	# Load font resources
	_font_tcm = load(GameManager.FONT_TCM)
	_font_zh_title = load(GameManager.FONT_ZH_TITLE)
	_font_zh_body = load(GameManager.FONT_ZH_BODY)
	_font_zh_emphasis = load(GameManager.FONT_ZH_EMPHASIS)
	_font_en_body = load(GameManager.FONT_EN_BODY)
	_font_en_emphasis = load(GameManager.FONT_EN_EMPHASIS)

	# ── Pre-build cached resources (avoids per-node allocation) ──
	if not _ann_regex:
		_ann_regex = RegEx.new()
		_ann_regex.compile("\\[ann=(.*?)\\](.*?)\\[/ann\\]")
		# *text* → [i]text[/i]  (emphasis)
		_em_marker_regex = RegEx.new()
		_em_marker_regex.compile("\\*(.+?)\\*")
		# ==text（annotation）== or ==text(annotation)==  (annotation with tooltip)
		_ann_marker_regex = RegEx.new()
		_ann_marker_regex.compile("==(.+?)[\\(（](.+?)[\\)）]==")
		# Connect tooltip signals on the dialogue RichTextLabel
		if _dialogue_text:
			_dialogue_text.meta_hover_started.connect(_on_annotation_hover_started)
			_dialogue_text.meta_hover_ended.connect(_on_annotation_hover_ended)
			_dialogue_text.meta_clicked.connect(_on_annotation_hover_ended)  # dismiss on click
	_font_dict["tcm"] = _font_tcm
	_font_dict["en_body"] = _font_en_body
	_font_dict["zh_body"] = _font_zh_body
	_font_dict["zh_title"] = _font_zh_title
	_build_dialogue_styles()
	_setup_crt_overlay()

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
	_create_skip_indicator()


func _instantiate_sub_scenes() -> void:
	# Already created — VNInterface is cached and reused across sessions
	if _save_menu:
		return

	# Loading screen
	var ls_packed: PackedScene = load("res://scenes/vn/LoadingScreen.tscn") as PackedScene
	if ls_packed:
		_loading_screen = ls_packed.instantiate() as Control
		_loading_screen.name = "LoadingScreen"
		add_child(_loading_screen)

	# Choices menu
	var cm_packed: PackedScene = load("res://scenes/vn/ChoicesMenu.tscn") as PackedScene
	if cm_packed:
		_choices_menu = cm_packed.instantiate() as Control
		_choices_menu.name = "ChoicesMenu"
		_choices_menu.visible = false
		_choices_menu.choice_selected.connect(_on_choice_selected)
		add_child(_choices_menu)

	# Save menu
	var sm_packed: PackedScene = load("res://scenes/vn/SaveMenu.tscn") as PackedScene
	if sm_packed:
		_save_menu = sm_packed.instantiate() as Control
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

	var text: String = ""

	# Primary: load story text from preloaded .gd scripts (compiled into bytecode).
	# This is the most reliable method — works in editor AND exported builds.
	var story_gd: RefCounted = STORY_TEXTS.get(_plot_id, null)
	if story_gd:
		text = story_gd.TEXT

	if text.is_empty():
		push_error("VNInterface: Could not load plot '", _plot_id, "'")
		_hide_loading()
		return

	var parser: ScriptParser = ScriptParser.new(_plot_id)
	_plot = parser.parse(text)

	if _plot.nodes.is_empty():
		push_error("VNInterface: Plot '", _plot_id, "' parsed with zero nodes")
		_hide_loading()
		return

	_node_index = clampi(_node_index, 0, max(0, _plot.nodes.size() - 1))
	_set_current_node(_node_index)
	_hide_loading()

## Show a user-visible error popup when plot loading fails (critical in exported builds).
func _show_load_error(message: String) -> void:
	var popup: AcceptDialog = AcceptDialog.new()
	popup.name = "LoadErrorDialog"
	popup.title = "剧情加载失败"
	popup.dialog_text = message
	popup.size = Vector2(480, 200)
	popup.exclusive = true
	popup.always_on_top = true
	popup.confirmed.connect(popup.queue_free)
	popup.canceled.connect(popup.queue_free)
	add_child(popup)
	popup.popup_centered()


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

	# Auto-advance through pure transition nodes (stop / black / jump chain)
	if not _exit_tree_called:
		_check_auto_advance()


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
		elif not bgm_cmd.play.is_empty():
			if bgm_cmd.crossfade:
				VNAudioService.crossfade_bgm(bgm_cmd.play, bgm_cmd.fade_out_duration, bgm_cmd.fade_in_duration)
			else:
				VNAudioService.play_bgm(bgm_cmd.play, bgm_cmd.loop)

	# --- SFX (long, via AudioManager) ---
	if _current_node.sfx:
		if _current_node.sfx.stop:
			AudioManager.stop_sfx()
		elif not _current_node.sfx.play.is_empty():
			AudioManager.play_sfx(_current_node.sfx.play, _current_node.sfx.loop)

	# --- SFX Short (one-shot, independent player — never blocks long SFX) ---
	if _current_node.sfx_short:
		if _current_node.sfx_short.stop:
			AudioManager.stop_sfx_short()
		elif not _current_node.sfx_short.play.is_empty():
			AudioManager.play_sfx_short(_current_node.sfx_short.play)

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
		elif _current_node.audio.audio_type == "ambience":
			VNAudioService.clear_all_ambience(0.5)
	elif not _current_node.audio.play.is_empty():
		match _current_node.audio.audio_type:
			"bgm":
				VNAudioService.play_bgm(_current_node.audio.play, _current_node.audio.loop)
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
		return
	# Keep dialogue box hidden for pure transition nodes (scene type, no text).
	# The dialogue box will be re-shown when a node with actual content is
	# reached, or explicitly by _execute_chapter_transition() after fade-in.
	if _current_node.type == "scene" and _get_localized_text().is_empty():
		return
	_dialogue_box.visible = true
	_dialogue_box.modulate.a = 1.0
	# Speaker name visibility is handled in _update_dialogue_display


# ===================================================================
# Character & Background
# ===================================================================

## Resolve a character name to a sprite path.
## Checks the plot's character dictionary first, then a built-in mapping,
## then tries AssetResolver for bare filenames.
## Returns "" when no sprite is available (character is hidden gracefully).
func _resolve_character_path(who: String) -> String:
	# Non-displayable speakers — narration, unknown, system
	var non_display: Array[String] = ["???", "旁白", "narrator", "Narrator", "系统", "system", "none"]
	if who in non_display:
		return ""

	# Built-in character → default sprite mapping (PascalCase dir names)
	var mapping: Dictionary = {
		"林子欣": "res://assets/characters/LinZixin/LinZixin_normal.png",
		"LinZixin": "res://assets/characters/LinZixin/LinZixin_normal.png",
		"江诗轩": "res://assets/characters/JiangShixuan/JiangShixuan_normal.png",
		"JiangShixuan": "res://assets/characters/JiangShixuan/JiangShixuan_normal.png",
		"石晴雯": "res://assets/characters/ShiQingwen/ShiQingwen_normal.png",
		"ShiQingwen": "res://assets/characters/ShiQingwen/ShiQingwen_normal.png",
		"漆诚": "res://assets/characters/QiCheng/QiCheng_normal.png",
		"QiCheng": "res://assets/characters/QiCheng/QiCheng_normal.png",
		"何肖": "res://assets/characters/HeXiao/HeXiao_normal.png",
		"HeXiao": "res://assets/characters/HeXiao/HeXiao_normal.png",
		"肖逸言": "res://assets/characters/XiaoYiyan/XiaoYiyan_normal.png",
		"XiaoYiyan": "res://assets/characters/XiaoYiyan/XiaoYiyan_normal.png",
	}

	# 1. Plot-level character dictionary takes priority
	if _plot and _plot.characters.has(who):
		var plot_path: String = _plot.characters[who]
		if not plot_path.is_empty():
			return _normalize_asset_path(plot_path)

	# 2. Built-in mapping
	if mapping.has(who):
		var mapped: String = mapping[who]
		if ResourceLoader.exists(mapped):
			return mapped

	# 3. Try AssetResolver with the raw name (handles bare filenames)
	if not "/" in who and not who.begins_with("res://"):
		var resolved: String = AssetResolver.resolve_ch(who)
		if resolved != who and ResourceLoader.exists(resolved):
			return resolved

	# 4. Character sprite not found — graceful degradation
	return ""


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

	# Same character, same pose — skip animation to avoid flashing
	if _current_char == normalized:
		return

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
	if path.begins_with("res://"): return path
	# Bare filename or relative path — try AssetResolver
	if not "/" in path or not path.begins_with("/"):
		var resolved: String = AssetResolver.resolve_any(path)
		if resolved != path and ResourceLoader.exists(resolved):
			return resolved
	return path


func _load_texture(path: String) -> Texture2D:
	var normalized: String = _normalize_asset_path(path)
	if normalized.is_empty() or not ResourceLoader.exists(normalized):
		# Fallback: try bare name resolution for character sprites
		if not "/" in path and not path.begins_with("res://"):
			normalized = AssetResolver.resolve_ch(path)
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
	# Font fallback: wrap CJK characters in zh_body font when the primary
	# dialogue font is Latin-only (EN mode).  CJK fonts already cover Latin.
	if not _is_zh():
		localized_text = GameManager.wrap_font_fallback(localized_text, GameManager.FONT_EN_BODY, GameManager.FONT_ZH_BODY)
	_dialogue_text.text = localized_text
	_dialogue_text.visible_characters = _visible_chars

	# Dialogue font — set once, only update on locale change
	var is_zh_now: bool = _is_zh()
	if _last_locale_was_zh != is_zh_now:
		_last_locale_was_zh = is_zh_now
		var body_font_size: int = 24
		if not is_zh_now and _font_en_body:
			_dialogue_text.add_theme_font_override("normal_font", _font_en_body)
			body_font_size = 22
		elif _font_zh_body:
			_dialogue_text.add_theme_font_override("normal_font", _font_zh_body)
			body_font_size = 26
		_dialogue_text.add_theme_font_size_override("normal_font_size", body_font_size)
		if _font_zh_emphasis:
			_dialogue_text.add_theme_font_override("italics_font", _font_zh_emphasis)
			_dialogue_text.add_theme_font_size_override("italics_font_size", body_font_size)
		if _font_en_emphasis:
			_dialogue_text.add_theme_font_override("bold_italics_font", _font_en_emphasis)

	# Text color (glitch toggles infrequently — cheap to set every node)
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
		_choices_menu.show_options(_current_node.options, _font_dict, TranslationServer.get_locale())
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
	var primary_font: Font = _font_tcm if not is_zh and _font_tcm else _font_zh_title
	var fallback_font: Font = _font_zh_title
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
		# Per-character font fallback: CJK chars need a CJK font
		if GameManager._is_cjk(ch) and fallback_font:
			lbl.add_theme_font_override("font", fallback_font)
		elif primary_font:
			lbl.add_theme_font_override("font", primary_font)
		_name_hbox.add_child(lbl)


## Transform emphasis / annotation markers into BBCode.
##
## Supported formats (all compatible with each other):
##   *text*                   → [i]text[/i]  (italic, simfang / timesi)
##   ==text(annotation)==     → [url=annotation]text[/url]  (underline + tooltip)
##   ==text（annotation）==   → same (full-width parens)
##
## Legacy BBCode (backward compatible):
##   [em]text[/em]            → [i]text[/i]
##   [ann=TIP]text[/ann]      → [url=TIP]text[/url]
func _apply_text_styling(text: String) -> String:
	if text.is_empty():
		return text

	var result: String = text

	# 1. *text* → [i]text[/i]  (markdown-style emphasis)
	if _em_marker_regex:
		result = _em_marker_regex.sub(result, "[i]$1[/i]", true)

	# 2. ==text（annotation）== or ==text(annotation)== → [url=annotation]text[/url]
	if _ann_marker_regex:
		result = _ann_marker_regex.sub(result, "[url=$2]$1[/url]", true)

	# 3. Legacy [em]text[/em] → [i]text[/i]  (backward compatible)
	result = result.replace("[em]", "[i]").replace("[/em]", "[/i]")

	# 4. Legacy [ann=TIP]text[/ann] → [url=TIP]text[/url]  (backward compatible)
	if _ann_regex:
		result = _ann_regex.sub(result, "[url=$1]$2[/url]", true)

	return result


func _apply_dialogue_box_style(glitch: bool) -> void:
	# Swap pre-built styles instead of allocating new StyleBoxFlat every node
	_dialogue_box.add_theme_stylebox_override("panel", _dialogue_style_glitch if glitch else _dialogue_style_normal)


## Pre-build the two dialogue box StyleBoxFlat variants (normal / glitch).
func _build_dialogue_styles() -> void:
	_dialogue_style_normal = _make_dialogue_style(Color.WHITE, Color(0, 0, 0, 0.1))
	_dialogue_style_glitch = _make_dialogue_style(Color(0.102, 0, 0, 1), Color(1, 0, 0, 1))


func _make_dialogue_style(bg: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.border_width_bottom = 8
	style.shadow_size = 30
	style.shadow_offset = Vector2(0, 24)
	style.shadow_color = Color(0, 0, 0, 0.35)
	style.corner_radius_top_left = 2
	style.corner_radius_top_right = 2
	return style


func _get_localized_text() -> String:
	if not _current_node: return ""
	var text: String = _current_node.EN if not _is_zh() and not _current_node.EN.is_empty() else _current_node.ZH
	return text.replace("{player}", _player_name)


# ===================================================================
# CRT retro monitor effect (replaces old red glitch overlay)
# ===================================================================

## Load the CRT shader and assign it to GlitchOverlay once per session.
## The overlay covers the full viewport and samples SCREEN_TEXTURE
## to apply curvature, scanlines, chromatic aberration, and VHS noise.
func _setup_crt_overlay() -> void:
	if not _glitch_overlay:
		return

	# Already set up — shader material persists across sessions
	if _glitch_overlay.material and _glitch_overlay.material is ShaderMaterial:
		return

	var shader: Shader = load("res://shaders/crt_effect.gdshader") as Shader
	if not shader:
		push_warning("VNInterface: failed to load CRT shader")
		return

	var mat := ShaderMaterial.new()
	mat.shader = shader
	_glitch_overlay.material = mat

	# Ensure the overlay renders above everything else
	_glitch_overlay.z_index = 10
	_glitch_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE


## Enable / disable the full-screen CRT post-processing shader.
## The GlitchOverlay ColorRect samples SCREEN_TEXTURE and applies
## curvature, scanlines, chromatic aberration, and VHS noise.
func _apply_glitch_effect(enable: bool) -> void:
	if not enable:
		_glitch_overlay.visible = false
		_apply_dialogue_box_style(false)
		return

	if _settings.shader_quality == "high":
		_glitch_overlay.visible = true
	else:
		_glitch_overlay.visible = false
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
		# Auto-advance if this wait was on a transition node (no text to read)
		if _get_localized_text().is_empty():
			_check_auto_advance()
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
	# Delegate to the cinematic chapter transition coroutine
	if not _current_node.jump_plot_id.is_empty():
		_execute_chapter_transition()
		return

	# Rechoose — loop back to the most recent choice
	if _current_node.rechoose:
		_do_rechoose()
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

	# ── Reaction nodes: insert after the select node, then advance ──
	if not opt.reaction_nodes.is_empty() or opt.rechoose:
		var insert_at: int = _node_index + 1
		for i: int in range(opt.reaction_nodes.size()):
			_plot.nodes.insert(insert_at + i, opt.reaction_nodes[i])
		# If the option targets _rechoose, append a rechoose node after reactions
		if opt.rechoose:
			var rc_node := PlotNode.new()
			rc_node.ZH = ""
			rc_node.EN = ""
			rc_node.type = "scene"
			rc_node.rechoose = true
			_plot.nodes.insert(insert_at + opt.reaction_nodes.size(), rc_node)
		# Hide choices menu, advance to the first reaction node
		if _choices_menu:
			_choices_menu.hide_options()
		_set_current_node(insert_at)
		_resolve_sticky_assets()
		return

	# _continue — advance to the next node in the current plot
	if opt.target_plot_id.is_empty() and opt.target_node_index < 0:
		if _plot and _node_index < _plot.nodes.size() - 1:
			_set_current_node(_node_index + 1)
			_resolve_sticky_assets()
		return

	if not opt.target_plot_id.is_empty():
		_plot_id = opt.target_plot_id
		_node_index = opt.target_node_index if opt.target_node_index >= 0 else 0
		_load_plot()
		_resolve_sticky_assets()
	else:
		# Current-plot jump (always node 0)
		_set_current_node(0)
		_resolve_sticky_assets()

## Jump back to the most recent select node, removing any reaction
## nodes that were inserted between the select and the current position.
## Called when a PlotNode with rechoose=true is reached.
func _do_rechoose() -> void:
	if not _plot:
		return

	# Find the most recent select node by scanning backwards
	var select_idx: int = -1
	for i: int in range(_node_index - 1, -1, -1):
		if _plot.nodes[i].type == "select":
			select_idx = i
			break

	if select_idx < 0:
		push_warning("VNInterface: _do_rechoose called but no select node found")
		# Fallback: just advance to next node
		if _node_index < _plot.nodes.size() - 1:
			_set_current_node(_node_index + 1)
		return

	# Remove reaction nodes between select and current (inclusive of current)
	var remove_count: int = _node_index - select_idx
	for _i: int in range(remove_count):
		_plot.nodes.remove_at(select_idx + 1)

	# Jump back to the select node — re-shows choices
	_set_current_node(select_idx)
	_resolve_sticky_assets()

# ===================================================================
# Save menu (delegated to SaveMenu)
# ===================================================================

func _toggle_save_menu() -> void:
	if not _save_menu: return
	_is_menu_open = not _is_menu_open
	if _is_menu_open:
		_save_menu.open(_font_dict, TranslationServer.get_locale())
		AudioManager.set_menu_mode(true)
		EventBus.bg_blur_toggle.emit(true)
		EventBus.bg_darken_toggle.emit(true)
	else:
		_save_menu.close_animated()
		AudioManager.set_menu_mode(false)
		EventBus.bg_blur_toggle.emit(false)
		EventBus.bg_darken_toggle.emit(false)


func _on_save_menu_closed() -> void:
	_is_menu_open = false
	_save_menu.visible = false
	AudioManager.set_menu_mode(false)
	EventBus.bg_blur_toggle.emit(false)
	EventBus.bg_darken_toggle.emit(false)


func _on_save_slot_selected(index: int) -> void:
	if not _plot or not _current_node: return

	var existing: SaveData = GameManager.load_game(index)
	if existing:
		_pending_save_slot = index
		_show_overwrite_modal()
		return

	_do_save_slot(index)
	# Refresh cards in-place so the new save appears immediately
	if _save_menu:
		_save_menu._refresh()


func _do_save_slot(index: int) -> void:
	var title: String = _get_node_chapter()
	var desc: String = _get_localized_text()
	# Prepend speaker name for context, e.g. "林子欣：你好啊"
	if not _current_node.who.is_empty() and _current_node.who != "player" and _current_node.who != "我":
		desc = _current_node.who + "：" + desc
	GameManager.save_game(index, _plot_id, _node_index, _player_name, title, desc, _terminal_status)


# ===================================================================
# Overwrite confirmation
# ===================================================================

func _show_overwrite_modal() -> void:
	# Prevent stacking — only one overwrite modal at a time
	if _has_active_overwrite_modal():
		return
	# Hide the save menu behind the modal so its _input() / gui_input
	# don't steal keyboard or mouse events from the confirmation dialog.
	if _save_menu:
		_save_menu.visible = false

	var modal_script: GDScript = load("res://scenes/modals/OverwriteConfirm.gd")
	if not modal_script:
		push_error("VNInterface: Failed to load OverwriteConfirm.gd")
		return
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
	# Re-show save menu with refreshed cards
	if _save_menu:
		_save_menu.visible = true
		_save_menu._refresh()


func _on_overwrite_cancelled() -> void:
	_remove_overwrite_modal()
	_pending_save_slot = -1
	# Re-show save menu
	if _save_menu:
		_save_menu.visible = true


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
		AudioManager.set_menu_mode(true)
		EventBus.bg_blur_toggle.emit(true)
		EventBus.bg_darken_toggle.emit(true)
		_tab_menu.open(_terminal_status, _current_bg)
	else:
		AudioManager.set_menu_mode(false)
		EventBus.bg_blur_toggle.emit(false)
		EventBus.bg_darken_toggle.emit(false)
		_tab_menu.close()


## Called by SceneManager when returning from Settings that was
## opened via the tab menu — re-opens the tab menu unconditionally.
func _open_tab_menu() -> void:
	if not _tab_menu: return
	_is_tab_menu_open = true
	AudioManager.set_menu_mode(true)
	_tab_menu.open(_terminal_status, _current_bg)


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
	_dialogue_box.modulate.a = 1.0


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
	if _hint_save_lbl:  # already created
		return
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


# ── Skip indicator (top-right corner) ──────────────────────────

func _create_skip_indicator() -> void:
	if _skip_indicator:  # already created
		return
	_skip_indicator = Label.new()
	_skip_indicator.name = "SkipIndicator"
	_skip_indicator.text = "加速中 >>>   再按 Ctrl 停止"
	_skip_indicator.visible = false
	_skip_indicator.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_skip_indicator.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_skip_indicator.add_theme_font_size_override("font_size", 22)
	_skip_indicator.add_theme_color_override("font_color", Color(1, 0.84, 0, 0.9))
	_skip_indicator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_skip_indicator.z_index = 5

	# Position: top-right, anchored to the right edge
	_skip_indicator.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_skip_indicator.offset_left = -520.0
	_skip_indicator.offset_right = -32.0
	_skip_indicator.offset_top = 16.0
	_skip_indicator.offset_bottom = 48.0

	if _font_zh_body:
		_skip_indicator.add_theme_font_override("font", _font_zh_body)

	add_child(_skip_indicator)


func _update_skip_indicator() -> void:
	if _skip_indicator:
		_skip_indicator.visible = _is_skipping


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
		# Dampen BGM + blur/darken background — same strategy as Tab/Save menus
		AudioManager.set_menu_mode(true)
		EventBus.bg_blur_toggle.emit(true)
		EventBus.bg_darken_toggle.emit(true)
		_log_screen.open(_log_entries)
		_log_screen.visible = true
		_play_click()
	_refresh_controls_hint()


func _on_tab_menu_closed() -> void:
	_is_tab_menu_open = false
	AudioManager.set_menu_mode(false)
	EventBus.bg_blur_toggle.emit(false)
	EventBus.bg_darken_toggle.emit(false)


func _on_tab_open_settings() -> void:
	_is_tab_menu_open = false
	# SceneManager will keep the dampened audio during the transition
	scene_changed.emit("SETTINGS_FROM_VN")


func _on_tab_back_to_title() -> void:
	_is_tab_menu_open = false
	AudioManager.set_menu_mode(false)
	EventBus.bg_blur_toggle.emit(false)
	EventBus.bg_darken_toggle.emit(false)
	back_requested.emit()


func _on_log_closed() -> void:
	_is_log_open = false
	if _log_screen:
		_log_screen.visible = false
	# Restore BGM + background — same strategy as Tab/Save menus
	AudioManager.set_menu_mode(false)
	EventBus.bg_blur_toggle.emit(false)
	EventBus.bg_darken_toggle.emit(false)
	_refresh_controls_hint()


# ===================================================================
# Audio
# ===================================================================

func _play_click() -> void:
	AudioManager.play_click()


# ===================================================================
# Process
# ===================================================================

func _process(delta: float) -> void:
	# ── CTRL skip toggle: _input() guards against stopping skip when Ctrl
	# ── is held, and _process() provides edge-detected toggle via polling.
	# ── Both use Input.is_key_pressed(KEY_CTRL) — the only reliable method
	# ── for modifier keys on Windows.
	var ctrl_down: bool = Input.is_key_pressed(KEY_CTRL)
	if ctrl_down and not _ctrl_was_down:
		_try_toggle_skip()
	_ctrl_was_down = ctrl_down

	# Sync skip indicator visibility every frame
	if _skip_indicator and _skip_indicator.visible != _is_skipping:
		_skip_indicator.visible = _is_skipping

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
			# Auto-advance if this wait was on a transition node (no text)
			if _get_localized_text().is_empty():
				_check_auto_advance()
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
		and not _is_auto_advancing
		and not _is_menu_open
		and not _is_tab_menu_open
		and not _is_log_open):
		_auto_play_timer += delta
		if _auto_play_timer >= _auto_play_delay:
			_auto_play_timer = 0.0
			_advance()

	if _is_skipping and not _is_auto_advancing and _current_node.type != "select" and not _is_menu_open and not _is_tab_menu_open and not _is_log_open:
		var skip_delay: float = 0.02 if _is_typing_finished else 0.005
		_auto_play_timer += delta
		if _auto_play_timer >= skip_delay:
			_auto_play_timer = 0.0
			_advance()


# ===================================================================
# Input
# ===================================================================

func _input(event: InputEvent) -> void:
	if not event.is_pressed(): return

	# Any input during skip mode stops skipping — unless Ctrl is currently
	# held (checked via Input singleton, same as _process polling).
	# We use Input.is_key_pressed() instead of trying to match event.keycode
	# because modifier-key events often don't carry a usable keycode.
	if _is_skipping and not Input.is_key_pressed(KEY_CTRL):
		_is_skipping = false
		_play_click()
		return

	# Block all input during chapter transitions
	if _is_auto_advancing:
		get_viewport().set_input_as_handled()
		return

	if _has_active_overwrite_modal(): return

	# Log screen has its own input handling
	if _is_log_open:
		return

	if event.is_action_pressed("vn_tab") or event.is_action_pressed("ui_cancel"):
		# Tab key or ESC — open the tab menu
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


func _gui_input(event: InputEvent) -> void:
	# Block mouse clicks during chapter transitions
	if _is_auto_advancing: return

	# Any mouse click during skip stops skipping
	if _is_skipping and event is InputEventMouseButton and event.pressed:
		_is_skipping = false
		_play_click()
		return

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
# Auto-advance chain — drives chapter transitions without user input
# ===================================================================

## Check whether the current node is a pure transition node (no dialogue
## text) and, if so, kick off the auto-advance chain that sequences stop →
## fade-to-black → chapter-title → load → fade-in without user clicks.
func _check_auto_advance() -> void:
	if _is_auto_advancing: return
	if _is_waiting: return
	if not _current_node: return
	if not _get_localized_text().is_empty(): return
	if _current_node.type == "select": return
	if _current_node.back_to_title: return

	# Only trigger for nodes that are part of a transition chain
	var is_transition: bool = (
		_current_node.stop_transition or
		_current_node.fade_black > 0.0 or
		not _current_node.jump_plot_id.is_empty() or
		(_current_node.type == "scene" and _current_node.next_scene.is_empty())
	)
	if not is_transition: return

	_is_auto_advancing = true
	_auto_advance_chain()


## Sequentially walk the stop → black → jump chain without user input.
## Each phase awaits the appropriate visual delay, then calls _advance()
## to move to the next node.  When the jump node is reached the full
## cinematic chapter-transition coroutine takes over.
func _auto_advance_chain() -> void:
	# ── Phase 1: stop-transition node ──
	if _current_node and _current_node.stop_transition:
		await get_tree().create_timer(0.35).timeout
		if _exit_tree_called:
			_is_auto_advancing = false
			return
		_is_typing_finished = true
		_advance()

	if not _current_node:
		_is_auto_advancing = false
		return

	# ── Phase 2: fade-to-black node ──
	if _current_node.fade_black > 0.0:
		# Wait exactly for the fade-to-black to finish (plus a one-frame buffer)
		await get_tree().create_timer(_current_node.fade_black + 0.05).timeout
		if _exit_tree_called:
			_is_auto_advancing = false
			return
		_is_typing_finished = true
		_advance()

	if not _current_node:
		_is_auto_advancing = false
		return

	# ── Phase 3: jump node → cinematic chapter transition ──
	if not _current_node.jump_plot_id.is_empty():
		_is_auto_advancing = false
		await _execute_chapter_transition()
		return

	# ── Phase 4: generic scene node (no dialogue, no jump) ──
	if _current_node.type == "scene" and _get_localized_text().is_empty():
		await get_tree().create_timer(0.1).timeout
		if _exit_tree_called:
			_is_auto_advancing = false
			return
		_is_typing_finished = true
		_advance()

	_is_auto_advancing = false


# ===================================================================
# Cinematic chapter transition
# ===================================================================

## Full cinematic chapter-transition sequence:
##   1. Ensure fully black (preceding @black node already faded)
##   2. Hide UI behind black
##   3. Silently load the new plot behind the black overlay
##   4. Fade from black to reveal the new chapter (~1.0 s)
##   5. Fade in UI elements smoothly — no instant snap
##   6. Start the new chapter's first node
##
## Together with the 1.0 s fade-to-black from the preceding @black node,
## the total transition time is ~2.0 seconds.
func _execute_chapter_transition() -> void:
	_play_click()
	_is_auto_advancing = true

	# Disable skip during transition
	_is_skipping = false

	# 1. Ensure full black (preceding @black node already faded to ~1.0 alpha)
	_vn_bg.set_black()

	# 2. Hide all UI instantly behind the black overlay
	_dialogue_box.visible = false
	_speaker_name_container.visible = false
	_char_rect.modulate.a = 0.0
	_char_rect.visible = false
	_controls_hint.modulate.a = 0.0
	_controls_hint.visible = false

	# 3. Load new plot silently behind black
	var new_plot_id: String = _current_node.jump_plot_id
	var new_node_index: int = _current_node.jump_node_index
	_load_plot_silent(new_plot_id, new_node_index)

	# 4. Fade from black to reveal new chapter (1.0 s)
	_vn_bg.fade_from_black(1.0)
	await get_tree().create_timer(1.0).timeout
	if _exit_tree_called:
		_is_auto_advancing = false
		return

	# 5. Restore UI with smooth fade-in — no instant snap
	_dialogue_box.visible = true
	_dialogue_box.modulate.a = 0.0
	_speaker_name_container.visible = true
	_speaker_name_container.modulate.a = 0.0
	_char_rect.visible = true
	_controls_hint.visible = true

	var ui_tween := create_tween().set_parallel(true)
	ui_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	ui_tween.tween_property(_dialogue_box, "modulate:a", 1.0, 0.4)
	ui_tween.tween_property(_speaker_name_container, "modulate:a", 1.0, 0.4)
	ui_tween.tween_property(_char_rect, "modulate:a", 1.0, 0.5)
	ui_tween.tween_property(_controls_hint, "modulate:a", 1.0, 0.4)

	await ui_tween.finished
	if _exit_tree_called:
		_is_auto_advancing = false
		return

	# 6. Start the new chapter's first node
	_set_current_node(_node_index)

	_is_auto_advancing = false



# ===================================================================
# Silent plot load (no loading screen)
# ===================================================================

## Load a plot without showing the loading screen — used during
## chapter transitions when the screen is already fully black.
func _load_plot_silent(plot_id: String, start_node_index: int) -> void:
	var text: String = ""
	var story_gd: RefCounted = STORY_TEXTS.get(plot_id, null)
	if story_gd:
		text = story_gd.TEXT

	if text.is_empty():
		push_error("VNInterface: Could not load plot '", plot_id, "'")
		return

	var parser: ScriptParser = ScriptParser.new(plot_id)
	_plot = parser.parse(text)

	if _plot.nodes.is_empty():
		push_error("VNInterface: Plot '", plot_id, "' parsed with zero nodes")
		return

	_plot_id = plot_id
	_node_index = clampi(start_node_index, 0, max(0, _plot.nodes.size() - 1))

	# Reset VN state
	_visible_chars = 0
	_is_typing_finished = false
	_is_waiting = false
	_wait_timer = 0.0
	_auto_play_timer = 0.0
	_typewriter_timer = 0.0
	_current_bg = ""
	_current_char = ""
	_char_rect.texture = null
	_char_rect.modulate.a = 1.0
	_char_rect.position.x = 0.0
	_char_rect.visible = false
	_last_speaker_name = ""
	_log_entries.clear()

	# Pre-apply the first node's background behind the black overlay
	# so it's ready when we fade in
	if not _plot.nodes.is_empty():
		var first_node: PlotNode = _plot.nodes[0]
		if not first_node.bg.is_empty():
			var normalized: String = _normalize_asset_path(first_node.bg)
			_current_bg = normalized
			_vn_bg.set_bg(normalized)

	_current_node = _plot.nodes[_node_index]


# ===================================================================
# Ctrl skip toggle helpers
# ===================================================================

## Toggle skip mode on/off.  Guards: no-op at choice nodes or when any
## overlay menu is open.
func _try_toggle_skip() -> void:
	if _current_node and _current_node.type != "select" and not _is_menu_open and not _is_tab_menu_open and not _is_log_open:
		_is_skipping = not _is_skipping
		if _is_skipping and _settings.auto_play:
			GameManager.set_setting("auto_play", false)
			_settings = GameManager.get_settings()
		_play_click()


# ===================================================================
# Annotation tooltip — hover over [url] tags
# ===================================================================

## Show a tooltip near the mouse when the player hovers over an
## annotation ([url=TIP]text[/url]).  The tooltip displays only the
## annotation content, not the underlined body text.
func _on_annotation_hover_started(meta: Variant) -> void:
	var tip: String = str(meta)
	if tip.is_empty():
		return

	# Lazy-create the tooltip label
	if not _annotation_tooltip:
		_annotation_tooltip = Label.new()
		_annotation_tooltip.name = "AnnotationTooltip"
		_annotation_tooltip.z_index = 100
		_annotation_tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_annotation_tooltip.add_theme_color_override("font_color", Color.BLACK)
		_annotation_tooltip.add_theme_font_size_override("font_size", 18)

		# Style: semi-transparent white background with rounded corners
		var tooltip_style := StyleBoxFlat.new()
		tooltip_style.bg_color = Color(1, 1, 1, 0.92)
		tooltip_style.border_color = Color(0, 0, 0, 0.3)
		tooltip_style.border_width_left = 1
		tooltip_style.border_width_right = 1
		tooltip_style.border_width_top = 1
		tooltip_style.border_width_bottom = 1
		tooltip_style.corner_radius_top_left = 4
		tooltip_style.corner_radius_top_right = 4
		tooltip_style.corner_radius_bottom_left = 4
		tooltip_style.corner_radius_bottom_right = 4
		tooltip_style.content_margin_left = 10
		tooltip_style.content_margin_right = 10
		tooltip_style.content_margin_top = 6
		tooltip_style.content_margin_bottom = 6
		_annotation_tooltip.add_theme_stylebox_override("normal", tooltip_style)

		# Font: use the body font for the tooltip
		if _font_zh_body:
			_annotation_tooltip.add_theme_font_override("font", _font_zh_body)

		add_child(_annotation_tooltip)

	_annotation_tooltip.text = tip
	_annotation_tooltip.visible = true

	# Position near the mouse cursor, slightly offset to the right
	var mouse_pos: Vector2 = get_viewport().get_mouse_position()
	var tooltip_size: Vector2 = _annotation_tooltip.get_minimum_size()
	var offset := Vector2(16, -tooltip_size.y - 8)
	_annotation_tooltip.position = mouse_pos + offset


func _on_annotation_hover_ended(_meta: Variant = "") -> void:
	if _annotation_tooltip:
		_annotation_tooltip.visible = false


# ===================================================================
# Cleanup
# ===================================================================

func _exit_tree() -> void:
	_exit_tree_called = true
	AudioManager.stop_voice()
	AudioManager.stop_ambience()
	AudioManager.set_vn_effect(0)
	AudioManager.reset_effects()
