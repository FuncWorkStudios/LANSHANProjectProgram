## VNInterface : Control
## Core visual novel gameplay scene with backgrounds, sprites, dialogue,
## typewriter effect, choices, save menu, skip/auto controls, and glitch effects.
## Port of VNScene from App.tsx — improved with dokivn-inspired patterns:
## cursor blink, wait-timers, tween cleanup, proper modal integration.
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
var _focused_choice_idx: int = 0
var _focused_slot_idx: int = -1
var _terminal_status: String = "locked"
var _language: String = "ZH"
var _player_name: String = ""
var _current_bg: String = ""
var _current_char: String = ""
var _settings: AppSettings

# Typewriter / wait / auto timers
var _typewriter_timer: float = 0.0
var _typewriter_interval: float = 0.045
var _auto_play_timer: float = 0.0
var _auto_play_delay: float = 2.0
var _wait_timer: float = 0.0
var _is_waiting: bool = false

# Tween references (for cleanup)
var _shake_tween: Tween = null
var _cursor_blink_tween: Tween = null

# ---------------------------------------------------------------------------
# Scene references
# ---------------------------------------------------------------------------
@onready var _bg_rect: TextureRect = %BackgroundRect
@onready var _char_rect: TextureRect = %CharacterRect
@onready var _dialogue_box: Panel = %DialogueBox
@onready var _dialogue_text: RichTextLabel = %DialogueText
@onready var _speaker_name_container: Control = %SpeakerNameContainer
@onready var _speaker_name_label: Label = %SpeakerNameLabel
@onready var _choices_container: VBoxContainer = %ChoicesContainer
@onready var _save_menu: Control = %SaveMenu
@onready var _save_slots_grid: GridContainer = %SaveSlotsGrid
@onready var _tab_menu: Control = %TabMenu
@onready var _overwrite_modal: Control = %OverwriteModal
@onready var _controls_hint: Control = %ControlsHint
@onready var _glitch_overlay: ColorRect = %GlitchOverlay
@onready var _cursor_blink: ColorRect = %CursorBlink
@onready var _loading_label: Label = %LoadingLabel
@onready var _cinematic_top: ColorRect = %CinematicTop
@onready var _cinematic_bottom: ColorRect = %CinematicBottom


# ===================================================================
# Setup & Loading
# ===================================================================

func setup(initial_save: SaveData, player_name: String) -> void:
	_player_name = player_name
	_settings = GameManager.get_settings()
	_language = _settings.language

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
	_show_loading(false)


func _load_plot() -> void:
	_show_loading(true)

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
		_show_loading(false)
		return

	var parser: ScriptParser = ScriptParser.new(_plot_id)
	_plot = parser.parse(text)

	_node_index = clampi(_node_index, 0, max(0, _plot.nodes.size() - 1))
	_set_current_node(_node_index)
	_show_loading(false)


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
# Node effects (split into focused sub-methods)
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
	# BGM
	if _current_node.bgm:
		if _current_node.bgm.stop:
			AudioManager.stop_bgm()
		elif not _current_node.bgm.play.is_empty():
			AudioManager.play_bgm(_current_node.bgm.play, _current_node.bgm.loop)

	# SFX
	if _current_node.sfx:
		if _current_node.sfx.stop:
			AudioManager.stop_sfx()
		elif not _current_node.sfx.play.is_empty():
			AudioManager.play_sfx(_current_node.sfx.play, _current_node.sfx.loop)

	# Legacy audio field
	if not _current_node.audio:
		return
	if _current_node.audio.stop:
		if _current_node.audio.audio_type == "bgm" or _current_node.audio.audio_type.is_empty():
			AudioManager.stop_bgm()
	elif not _current_node.audio.play.is_empty():
		match _current_node.audio.audio_type:
			"bgm":
				AudioManager.play_bgm(_current_node.audio.play, _current_node.audio.loop)
			"sfx":
				AudioManager.play_sfx(_current_node.audio.play, _current_node.audio.loop)
			"voice":
				AudioManager.play_voice(_current_node.audio.play)
			"ambience":
				AudioManager.play_ambience(_current_node.audio.play, _current_node.audio.loop)


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
		# Don't show dialogue text during wait
		_dialogue_text.visible_characters = 0


# ===================================================================
# Character & Background
# ===================================================================

func _resolve_character_path(who: String) -> String:
	var mapping: Dictionary = {
		"林子欣": "res://assets/Characters/LinZixin/LinZixin_normal.png",
		"LinZixin": "res://assets/Characters/LinZixin/LinZixin_normal.png",
		"???": "",
		"旁白": "",
		"narrator": "",
		"系统": "",
		"system": "",
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
# Asset path normalization (fixes /Assests/ → res://assets/)
# ===================================================================

func _normalize_asset_path(path: String) -> String:
	if path.is_empty():
		return path
	# Fix the typo from web version paths
	if path.begins_with("/Assests/"):
		return "res://assets/" + path.substr(9)
	if path.begins_with("/Assets/"):
		return "res://assets/" + path.substr(8)
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

	# Speaker name
	var who: String = _current_node.who
	if who.is_empty() or who in ["???", "旁白", "Narrator", "narrator", "system", "system_text", "none"]:
		_speaker_name_container.visible = false
	else:
		_speaker_name_container.visible = true
		var speaker_name: String = who
		if who == "player":
			speaker_name = _player_name
		elif _plot:
			speaker_name = _plot.get_character_name(who, _language)
		_speaker_name_label.text = speaker_name

	# Typewriter speed
	var speed_map: Dictionary = {
		"slow": 0.080,
		"normal": 0.045,
		"fast": 0.020,
	}
	var lang_mult: float = 0.65 if _language == "EN" else 1.0
	_typewriter_interval = speed_map.get(_settings.text_speed, 0.045) * lang_mult

	if _current_node.glitch:
		_typewriter_interval = 0.020


func _get_localized_text() -> String:
	if not _current_node:
		return ""
	var text: String = ""
	if _language == "EN" and not _current_node.EN.is_empty():
		text = _current_node.EN
	else:
		text = _current_node.ZH
	text = text.replace("{player}", _player_name)
	return text


# ===================================================================
# Cursor blink animation
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
# Sticky assets
# ===================================================================

func _resolve_sticky_assets() -> void:
	if not _plot or _plot.nodes.is_empty():
		return

	var start_idx: int = mini(_node_index, _plot.nodes.size() - 1)

	# Background
	for i: int in range(start_idx, -1, -1):
		var bg: String = _plot.nodes[i].bg
		if not bg.is_empty():
			var normalized: String = _normalize_asset_path(bg)
			if _current_bg != normalized:
				_current_bg = normalized
				var texture: Texture2D = _load_texture(normalized)
				if texture:
					_bg_rect.texture = texture
			break

	# Character
	for i: int in range(start_idx, -1, -1):
		var ch: String = _plot.nodes[i].ch
		if not ch.is_empty():
			if ch == "__CLEAR__":
				_set_character("")
			elif _current_char != ch:
				_set_character(ch)
			break


# ===================================================================
# Glitch effect (with proper shake tween cleanup)
# ===================================================================

func _apply_glitch_effect(enable: bool) -> void:
	if not enable:
		_glitch_overlay.visible = false
		_bg_rect.modulate = Color.WHITE
		_dialogue_box.get_theme_stylebox("panel").bg_color = Color.WHITE
		# Kill shake tween and reset position
		if _shake_tween and _shake_tween.is_valid():
			_shake_tween.kill()
			_shake_tween = null
		position.x = 0.0
		return

	_glitch_overlay.visible = _settings.shader_quality == "high"
	_bg_rect.modulate = Color(0.1, 0, 0, 1)
	_dialogue_box.get_theme_stylebox("panel").bg_color = Color(0.1, 0, 0, 1)

	# Screen shake — only create if not already shaking
	if not (_shake_tween and _shake_tween.is_valid()):
		_shake_tween = create_tween().set_loops()
		_shake_tween.tween_property(self, "position:x", 15.0, 0.05)
		_shake_tween.tween_property(self, "position:x", -15.0, 0.05)
		_shake_tween.tween_property(self, "position:x", 0.0, 0.05)


# ===================================================================
# Advance / Progression
# ===================================================================

func _advance() -> void:
	if not _plot or not _current_node:
		return

	# If text is still typing, show all text immediately
	if not _is_typing_finished and not _is_waiting:
		_visible_chars = _get_localized_text().length()
		_dialogue_text.visible_characters = _visible_chars
		_is_typing_finished = true
		_start_cursor_blink()
		return

	# If waiting, allow skip by completing wait
	if _is_waiting:
		_is_waiting = false
		_wait_timer = 0.0
		# Now show the dialogue text
		_visible_chars = 0
		_is_typing_finished = false
		_dialogue_text.visible_characters = 0
		_update_dialogue_display()
		return

	# If this is a choice node, don't auto-advance
	if _current_node.type == "select":
		_is_skipping = false
		return

	_stop_cursor_blink()
	_play_click()

	# Advance to next node or back to menu
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
	if not _plot:
		return ""
	for i: int in range(_node_index, -1, -1):
		if _plot.nodes[i].chapter:
			var ch: LocText = _plot.nodes[i].chapter
			return ch.ZH if _language == "ZH" else ch.EN
	return _plot.title.ZH if _language == "ZH" else _plot.title.EN


# ===================================================================
# Choices
# ===================================================================

func _on_choice_selected(choice_index: int) -> void:
	if not _current_node or _current_node.type != "select":
		return
	if choice_index < 0 or choice_index >= _current_node.options.size():
		return

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

	_choices_container.visible = false


func _update_choice_focus() -> void:
	for i: int in range(_choices_container.get_child_count()):
		var child: Control = _choices_container.get_child(i)
		var is_focused: bool = i == _focused_choice_idx

		# Kill previous tween for this child if it exists
		var old_tween: Tween = child.get_meta("focus_tween", null)
		if old_tween and old_tween.is_valid():
			old_tween.kill()

		var tween := create_tween()
		tween.tween_property(child, "modulate:a", 1.0 if is_focused else 0.6, 0.2)
		tween.parallel().tween_property(child, "position:x", 10.0 if is_focused else 0.0, 0.2)
		child.set_meta("focus_tween", tween)


# ===================================================================
# ===================================================================
# Save menu
# ===================================================================

func _toggle_save_menu() -> void:
	_is_menu_open = not _is_menu_open
	_save_menu.visible = _is_menu_open
	if _is_menu_open:
		_focused_slot_idx = 0
		_refresh_save_slots()
		AudioManager.set_menu_mode(true)
	else:
		AudioManager.set_menu_mode(false)


func _refresh_save_slots() -> void:
	for child: Node in _save_slots_grid.get_children():
		child.queue_free()

	var saves: Array = GameManager.get_save_slots()
	for i: int in range(GameManager.MAX_SLOTS):
		var slot: Control = _create_save_slot(i, saves[i])
		_save_slots_grid.add_child(slot)
	_update_save_slot_focus()


func _create_save_slot(index: int, save: SaveData) -> Control:
	var is_zh: bool = _settings.language == "ZH"
	var container := Control.new()
	container.name = "SaveSlot_" + str(index)
	container.custom_minimum_size = Vector2(280, 120)
	container.mouse_filter = Control.MOUSE_FILTER_STOP

	var sweep := ColorRect.new()
	sweep.name = "Sweep"
	sweep.color = Color.WHITE
	sweep.set_anchors_preset(Control.PRESET_FULL_RECT)
	sweep.scale = Vector2(0, 1)
	sweep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(sweep)

	var accent_bar := ColorRect.new()
	accent_bar.name = "AccentBar"
	accent_bar.color = Color.BLACK
	accent_bar.size = Vector2(0, 2)
	accent_bar.anchor_bottom = 1.0
	accent_bar.offset_bottom = 0.0
	accent_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(accent_bar)

	var num_label := Label.new()
	num_label.name = "Number"
	num_label.text = "%02d" % (index + 1)
	num_label.position = Vector2(12, 6)
	num_label.add_theme_font_size_override("font_size", 36)
	num_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.1))
	num_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(num_label)

	var date_label := Label.new()
	date_label.name = "Date"
	date_label.text = save.date if save else "-- / -- / --"
	date_label.position = Vector2(180, 8)
	date_label.add_theme_font_size_override("font_size", 10)
	date_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.4))
	date_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(date_label)

	var title_label := Label.new()
	title_label.name = "Title"
	if save:
		title_label.text = save.title
	else:
		title_label.text = "空位" if is_zh else "EMPTY"
	title_label.position = Vector2(12, 82)
	title_label.add_theme_font_size_override("font_size", 20)
	title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(title_label)

	var detail_label := Label.new()
	detail_label.name = "Detail"
	if save:
		detail_label.text = save.player_name + "  o  " + save.plot_id.to_upper()
	else:
		detail_label.text = "点击存档" if is_zh else "Click to save"
	detail_label.position = Vector2(12, 105)
	detail_label.add_theme_font_size_override("font_size", 10)
	detail_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.3))
	detail_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(detail_label)

	container.mouse_entered.connect(_on_save_slot_hovered.bind(index))
	container.gui_input.connect(_on_save_slot_clicked.bind(index))
	container.set_meta("sweep", sweep)
	container.set_meta("accent_bar", accent_bar)
	container.set_meta("num_label", num_label)
	container.set_meta("date_label", date_label)
	container.set_meta("title_label", title_label)
	container.set_meta("detail_label", detail_label)

	return container


func _update_save_slot_focus() -> void:
	for i: int in range(_save_slots_grid.get_child_count()):
		var slot: Control = _save_slots_grid.get_child(i)
		var is_focused: bool = i == _focused_slot_idx
		var sweep: ColorRect = slot.get_meta("sweep")
		var accent_bar: ColorRect = slot.get_meta("accent_bar")
		var num_label: Label = slot.get_meta("num_label")
		var date_label: Label = slot.get_meta("date_label")
		var title_label: Label = slot.get_meta("title_label")
		var detail_label: Label = slot.get_meta("detail_label")

		var sweep_tween := create_tween()
		sweep_tween.set_ease(Tween.EASE_OUT)
		sweep_tween.tween_property(sweep, "scale:x", 1.0 if is_focused else 0.0, 0.4)

		var bar_tween := create_tween()
		bar_tween.set_ease(Tween.EASE_OUT)
		bar_tween.tween_property(accent_bar, "size:x", 280.0 if is_focused else 0.0, 0.4)

		num_label.add_theme_color_override("font_color", Color.BLACK if is_focused else Color(1, 1, 1, 0.1))
		date_label.add_theme_color_override("font_color", Color(0, 0, 0, 0.5) if is_focused else Color(1, 1, 1, 0.4))
		title_label.add_theme_color_override("font_color", Color.BLACK if is_focused else Color.WHITE)
		detail_label.add_theme_color_override("font_color", Color(0, 0, 0, 0.5) if is_focused else Color(1, 1, 1, 0.3))


func _on_save_slot_hovered(index: int) -> void:
	if _focused_slot_idx == index:
		return
	_focused_slot_idx = index
	_update_save_slot_focus()
	_play_click()


func _on_save_slot_clicked(index: int, event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_confirm_save_on_slot(index)


func _confirm_save_on_slot(index: int) -> void:
	_play_click()
	if not _plot or not _current_node:
		return

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


# Overwrite confirmation (using dedicated OverwriteConfirm modal)
# ===================================================================

func _show_overwrite_modal() -> void:
	var modal_script: GDScript = load("res://scenes/Modals/OverwriteConfirm.gd")
	var modal: Control = modal_script.new()
	modal.name = "OverwriteConfirmInstance"
	modal.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Connect signals with .bind() — no lambdas
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
	# Find and remove any overwrite confirm instances by name
	for child: Node in get_children():
		if child.name == "OverwriteConfirmInstance":
			child.queue_free()


# ===================================================================
# Tab menu
# ===================================================================

func _toggle_tab_menu() -> void:
	_is_tab_menu_open = not _is_tab_menu_open
	_tab_menu.visible = _is_tab_menu_open
	_play_click()


# ===================================================================
# Loading indicator
# ===================================================================

func _show_loading(show: bool) -> void:
	_loading_label.visible = show
	_dialogue_box.visible = not show


# ===================================================================
# Audio
# ===================================================================

func _play_click() -> void:
	AudioManager.play_sfx("res://assets/Sfx/Choose.wav")


# ===================================================================
# Process
# ===================================================================

func _process(delta: float) -> void:
	if not _current_node:
		return

	# Wait timer (for @wait command)
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

	# Typewriter
	if not _is_typing_finished and _visible_chars < text.length():
		_typewriter_timer += delta
		if _typewriter_timer >= _typewriter_interval:
			_typewriter_timer = 0.0
			_visible_chars += 1
			_dialogue_text.visible_characters = _visible_chars
			if _visible_chars >= text.length():
				_is_typing_finished = true
				_start_cursor_blink()

	# Auto-play
	if (_settings.auto_play and _is_typing_finished
		and (_current_node.type != "select")
		and not _is_skipping
		and not _is_menu_open
		and not _is_tab_menu_open):
		_auto_play_timer += delta
		if _auto_play_timer >= _auto_play_delay:
			_auto_play_timer = 0.0
			_advance()

	# Skip timer
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
	if not event.is_pressed():
		return

	# Overwrite modal active — let the modal handle all input
	if _has_active_overwrite_modal():
		return

	# Tab menu toggle (works regardless of menu state)
	if event.is_action_pressed("vn_tab"):
		_toggle_tab_menu()
		get_viewport().set_input_as_handled()
		return

	# Save menu input handling
	if _is_menu_open:
		if event.is_action_pressed("vn_save") or event.is_action_pressed("ui_cancel"):
			_toggle_save_menu()
			_play_click()
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("ui_up"):
			_focused_slot_idx = max(0, _focused_slot_idx - 2)  # 2-col grid
			_update_save_slot_focus(); _play_click()
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("ui_down"):
			_focused_slot_idx = min(GameManager.MAX_SLOTS - 1, _focused_slot_idx + 2)
			_update_save_slot_focus(); _play_click()
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("ui_left"):
			_focused_slot_idx = max(0, _focused_slot_idx - 1)
			_update_save_slot_focus(); _play_click()
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("ui_right"):
			_focused_slot_idx = min(GameManager.MAX_SLOTS - 1, _focused_slot_idx + 1)
			_update_save_slot_focus(); _play_click()
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("ui_accept"):
			_confirm_save_on_slot(_focused_slot_idx)
			get_viewport().set_input_as_handled()
		return

	# Tab menu open — delegate to it
	if _is_tab_menu_open:
		return

	# Choice navigation
	if _current_node and _current_node.type == "select" and _is_typing_finished:
		var opt_count: int = _current_node.options.size()
		if event.is_action_pressed("ui_up"):
			_focused_choice_idx = (_focused_choice_idx - 1 + opt_count) % opt_count
			_update_choice_focus()
			_play_click()
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("ui_down"):
			_focused_choice_idx = (_focused_choice_idx + 1) % opt_count
			_update_choice_focus()
			_play_click()
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("ui_accept"):
			_on_choice_selected(_focused_choice_idx)
			get_viewport().set_input_as_handled()
		return

	# Normal VN controls
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


func _has_active_overwrite_modal() -> bool:
	for child: Node in get_children():
		if child.name == "OverwriteConfirmInstance":
			return true
	return false


# ===================================================================
# GUI interaction
# ===================================================================

func _on_background_clicked() -> void:
	if _is_menu_open or _is_tab_menu_open:
		return
	_advance()


# ===================================================================
# Cleanup
# ===================================================================

func _exit_tree() -> void:
	_stop_cursor_blink()
	if _shake_tween and _shake_tween.is_valid():
		_shake_tween.kill()
		_shake_tween = null
	AudioManager.stop_voice()
	AudioManager.stop_ambience()
	AudioManager.set_vn_effect(0)
	AudioManager.reset_effects()
