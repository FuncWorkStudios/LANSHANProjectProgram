## SceneManager : Control
## Root scene controller — manages scene lifecycle, transitions, and routing.
## Scenes are lazy-loaded on first use; hidden scenes are inert
## (process_mode disabled, mouse_filter ignored).
extends Control

enum Scene {
	SPLASH,
	TITLE,
	LOAD,
	SETTINGS,
	ABOUT,
	ACHIEVEMENTS,
	REGISTRATION,
	VN,
	MUSIC_GALLERY,
	SCENE_GALLERY,
	PICTURE_VIEWER,
}

const TRANSITION_DURATION: float = 0.5
const SLIDE_DURATION: float = 0.45
const NEW_GAME_SLIDE_DURATION: float = 1.35  # 3× normal slide — ceremonial feel

# Scene paths (lazy-loaded on first access)
const SCENE_PATHS: Dictionary = {
	Scene.SPLASH:       "res://scenes/menu/SplashScene.tscn",
	Scene.TITLE:        "res://scenes/menu/MainMenu.tscn",
	Scene.LOAD:         "res://scenes/save_load/LoadScene.tscn",
	Scene.SETTINGS:     "res://scenes/settings/SettingsScene.tscn",
	Scene.ABOUT:        "res://scenes/about/AboutScene.tscn",
	Scene.ACHIEVEMENTS:      "res://scenes/achievements/AchievementsScene.tscn",
	Scene.REGISTRATION: "res://scenes/registration/RegistrationScene.tscn",
	Scene.VN:           "res://scenes/vn/VNInterface.tscn",
	Scene.MUSIC_GALLERY: "res://scenes/gallery/MusicGallery.tscn",
	Scene.SCENE_GALLERY: "res://scenes/gallery/SceneGallery.tscn",
	Scene.PICTURE_VIEWER: "res://scenes/gallery/PictureViewer.tscn",
}

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------
var _current_scene: Scene = Scene.SPLASH
var _bg_path: String = ""
var _player_name: String = ""
var _active_save: SaveData = null
var _is_transitioning: bool = false
var _return_to_vn: bool = false
var _return_to_tab_menu: bool = false
var _return_to_achievements: bool = false
var _return_to_scene_gallery: bool = false
var _pending_back: bool = false
var _last_bg_path: String = ""

func _pick_next_bg() -> String:
	var pool: Array = GameManager.BG_POOL.duplicate()
	if pool.size() <= 1:
		return pool[0] if pool.size() > 0 else ""
	# Remove last bg from pool to avoid consecutive repeats
	if pool.has(_last_bg_path) and pool.size() > 1:
		pool.erase(_last_bg_path)
	var picked: String = pool[randi() % pool.size()]
	_last_bg_path = picked
	return picked

var _scene_instances: Dictionary = {}   # Scene enum → Control (lazy)

@onready var _scene_container: Control = %SceneContainer
@onready var _transition_overlay: ColorRect = %TransitionOverlay
var _bg_layer: Control = null
var _pixel_overlay: ColorRect = null
var _pixel_material: ShaderMaterial = null


# ===================================================================
# Lifecycle
# ===================================================================

func _ready() -> void:
	# Background is set later when entering TITLE — avoid double-set flicker
	_bg_path = ""
	GameManager.current_background = ""

	# Create persistent background layer (behind everything, survives transitions)
	var bg_packed: PackedScene = load("res://scenes/ui/BackgroundLayer.tscn") as PackedScene
	if bg_packed:
		_bg_layer = bg_packed.instantiate()
		_bg_layer.name = "BackgroundLayer"
		add_child(_bg_layer)
		move_child(_bg_layer, 0)

	EventBus.scene_changed.connect(_on_scene_changed)

	# Ensure TransitionOverlay renders ON TOP of scene content
	move_child(_transition_overlay, get_child_count() - 1)

	# BackBufferCopy + PixelOverlay for new-game cinematic transition.
	# BackBufferCopy captures the screen so the pixelation shader can sample it.
	var _bb_copy := BackBufferCopy.new()
	_bb_copy.name = "BackBufferCopy"
	_bb_copy.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	add_child(_bb_copy)
	move_child(_bb_copy, get_child_count() - 1)

	_pixel_overlay = ColorRect.new()
	_pixel_overlay.name = "PixelOverlay"
	_pixel_overlay.color = Color(0, 0, 0, 0)
	_pixel_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pixel_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_pixel_overlay.visible = false
	add_child(_pixel_overlay)
	move_child(_pixel_overlay, get_child_count() - 1)

	_hide_transition_overlay()
	_open_scene(Scene.SPLASH)

	AudioManager.unlock_audio()
	AudioManager.play_bgm("res://assets/music/LANSHANProjectDemo.mp3")


# ===================================================================
# Lazy scene access
# ===================================================================

func _get_scene(target: Scene) -> Control:
	if _scene_instances.has(target):
		return _scene_instances[target]

	var path: String = SCENE_PATHS.get(target, "")
	if path.is_empty():
		return null

	var packed: PackedScene = load(path) as PackedScene
	if not packed:
		push_error("SceneManager: Failed to load — ", path)
		return null

	var instance: Control = packed.instantiate()
	instance.visible = false
	instance.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scene_container.add_child(instance)

	# Wire signals
	if instance.has_signal("back_requested"):
		instance.back_requested.connect(_on_scene_back)
	if instance.has_signal("registration_complete"):
		instance.registration_complete.connect(_on_registration_complete)
	if instance.has_signal("registration_cancelled"):
		instance.registration_cancelled.connect(_on_registration_cancelled)
	if instance.has_signal("scene_changed"):
		instance.scene_changed.connect(_on_vn_scene_changed)
	if instance.has_signal("save_selected"):
		instance.save_selected.connect(_on_load_selected)
	if instance.has_signal("gallery_requested"):
		instance.gallery_requested.connect(_on_achievements_gallery_requested)
	if instance.has_signal("picture_requested"):
		instance.picture_requested.connect(_on_scene_gallery_picture_requested)

	_scene_instances[target] = instance
	return instance


# ===================================================================
# Inertness — hidden scenes stop processing
# ===================================================================

func _set_scene_inert(scene: Control, inert: bool) -> void:
	if inert:
		scene.process_mode = Node.PROCESS_MODE_DISABLED
		scene.mouse_filter = Control.MOUSE_FILTER_IGNORE
	else:
		scene.process_mode = Node.PROCESS_MODE_INHERIT
		scene.mouse_filter = Control.MOUSE_FILTER_STOP


# ===================================================================
# Scene switching — instant (no transition)
# ===================================================================

func _open_scene(target: Scene) -> void:
	var target_instance: Control = _get_scene(target)
	if not target_instance:
		push_error("SceneManager: Cannot open scene — ", target)
		return

	# Exit current scene
	var current_instance: Control = _scene_instances.get(_current_scene, null)
	if current_instance and current_instance.has_method("_on_exit"):
		current_instance._on_exit()

	# Hide all scenes
	for scene: Control in _scene_instances.values():
		if scene:
			scene.visible = false
			_set_scene_inert(scene, true)

	# Show target — force full opacity to override any in-progress
	# _animate_enter() fade-in from the scene's _ready().
	target_instance.visible = true
	target_instance.modulate.a = 1.0
	_set_scene_inert(target_instance, false)

	_current_scene = target

	# Enter new scene
	if target_instance.has_method("_on_enter"):
		target_instance._on_enter()


# ===================================================================
# Fade-to-black transition (kept as fallback for minor transitions)
# ===================================================================

func _transition_to(target: Scene) -> void:
	if _is_transitioning:
		return
	_is_transitioning = true
	_pending_back = false
	_transition_overlay.mouse_filter = Control.MOUSE_FILTER_STOP

	# Fade to black
	var tween_out := create_tween()
	tween_out.tween_property(_transition_overlay, "modulate:a", 1.0, TRANSITION_DURATION)
	await tween_out.finished

	# Switch
	_open_scene(target)

	# Fade in
	var tween_in := create_tween()
	tween_in.tween_property(_transition_overlay, "modulate:a", 0.0, TRANSITION_DURATION)
	await tween_in.finished

	_transition_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_is_transitioning = false
	if _pending_back:
		_pending_back = false
		_on_scene_back()


# ===================================================================
# Slide transition — major scene horizontal slide (1:1 web port)
# ===================================================================

## Slide transition between two major scenes.
## Both old and new scenes are visible during the slide.
## Uses tween_property on offset_left/offset_right to shift
## full-rect Controls without changing their width.
func _slide_transition_to(target: Scene, forward: bool = true, duration_override: float = -1.0) -> void:
	if _is_transitioning:
		return
	_is_transitioning = true
	_pending_back = false
	_transition_overlay.mouse_filter = Control.MOUSE_FILTER_STOP

	var slide_dur: float = duration_override if duration_override > 0.0 else SLIDE_DURATION
	var vp_w: float = get_viewport().get_visible_rect().size.x
	var old_inst: Control = _scene_instances.get(_current_scene, null)
	var new_inst: Control = _get_scene(target)

	if not new_inst:
		push_error("SceneManager: Cannot slide to scene — ", target)
		_is_transitioning = false
		_transition_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return

	# Exit old scene
	if old_inst and old_inst.has_method("_on_exit"):
		old_inst._on_exit()

	# Direction: forward=true → new from right (+1), forward=false → new from left (-1)
	var dir: float = 1.0 if forward else -1.0

	# Position off-screen BEFORE visible — avoids one-frame flash
	new_inst.offset_left = dir * vp_w
	new_inst.offset_right = dir * vp_w
	new_inst.visible = true
	# Force full opacity — sub-menus have their own _animate_enter() fade-in
	# tweens (0.8s) that conflict with the slide (0.45s). Without this reset
	# the scene slides in semi-transparent, causing a visible flicker.
	new_inst.modulate.a = 1.0
	_set_scene_inert(new_inst, false)

	# Enter new scene
	if new_inst.has_method("_on_enter"):
		new_inst._on_enter()

	# ── Animate both scenes sliding ──
	var tween := create_tween().set_parallel(true)
	tween.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)

	if old_inst:
		tween.tween_property(old_inst, "offset_left", -dir * vp_w, slide_dur)
		tween.tween_property(old_inst, "offset_right", -dir * vp_w, slide_dur)

	tween.tween_property(new_inst, "offset_left", 0.0, slide_dur)
	tween.tween_property(new_inst, "offset_right", 0.0, SLIDE_DURATION)

	await tween.finished

	# ── Cleanup ──
	if old_inst:
		old_inst.visible = false
		old_inst.offset_left = 0.0
		old_inst.offset_right = 0.0
		_set_scene_inert(old_inst, true)

	_current_scene = target
	_transition_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_is_transitioning = false

	# Process any ESC pressed during transition
	if _pending_back:
		_pending_back = false
		_on_scene_back()


func _hide_transition_overlay() -> void:
	_transition_overlay.modulate.a = 0.0


# ===================================================================
# Signal routing
# ===================================================================

func _on_scene_changed(scene_name: String) -> void:
	match scene_name:
		"SPLASH":
			_open_scene(Scene.SPLASH)
		"TITLE":
			if _current_scene == Scene.SPLASH:
				var menu_bg: String = _pick_next_bg()
				GameManager.current_background = menu_bg
				EventBus.shared_background_updated.emit(menu_bg)
				# Fade-through-black: splash → black → main menu.
				# Smoother than a slide for this transition because the
				# main menu has its own elaborate entry animation.
				_transition_to(Scene.TITLE)
			else:
				_back_to_menu()
		"LOAD":
			EventBus.bg_blur_toggle.emit(true)
			EventBus.bg_darken_toggle.emit(true)
			AudioManager.set_menu_mode(true)
			await get_tree().create_timer(0.12).timeout
			_slide_transition_to(Scene.LOAD, true)
		"SETTINGS":
			EventBus.bg_blur_toggle.emit(true)
			EventBus.bg_darken_toggle.emit(true)
			AudioManager.set_menu_mode(true)
			await get_tree().create_timer(0.12).timeout
			_slide_transition_to(Scene.SETTINGS, true)
		"SETTINGS_FROM_VN":
			_return_to_vn = true
			_return_to_tab_menu = true
			# Restore shared background — VN hides it, but sub-menus need it for blur/darken
			if _bg_layer and _bg_layer.has_method("_apply_current"):
				_bg_layer._apply_current()
			EventBus.bg_blur_toggle.emit(true)
			EventBus.bg_darken_toggle.emit(true)
			AudioManager.set_menu_mode(true)
			await get_tree().create_timer(0.12).timeout
			_slide_transition_to(Scene.SETTINGS, true)
		"ABOUT":
			EventBus.bg_blur_toggle.emit(true)
			EventBus.bg_darken_toggle.emit(true)
			AudioManager.set_menu_mode(true)
			await get_tree().create_timer(0.12).timeout
			_slide_transition_to(Scene.ABOUT, true)
		"ACHIEVEMENTS":
			EventBus.bg_blur_toggle.emit(true)
			EventBus.bg_darken_toggle.emit(true)
			AudioManager.set_menu_mode(true)
			await get_tree().create_timer(0.12).timeout
			_slide_transition_to(Scene.ACHIEVEMENTS, true)
		"REGISTRATION":
			EventBus.bg_blur_toggle.emit(true)
			EventBus.bg_darken_toggle.emit(true)
			AudioManager.set_menu_mode(true)
			await get_tree().create_timer(0.12).timeout
			_start_new_game()
		"VN":
			EventBus.bg_blur_toggle.emit(false)
			EventBus.bg_darken_toggle.emit(false)
			AudioManager.set_menu_mode(false)
			if _bg_layer and _bg_layer.has_method("hide_background"):
				_bg_layer.hide_background()
			await get_tree().create_timer(0.12).timeout
			_start_vn()


# ===================================================================
# Flows
# ===================================================================

func _back_to_menu() -> void:
	# Guard against double-execution during transitions
	if _is_transitioning:
		return

	# Slide the sub-menu away first — keep the background darkened during
	# the slide so the player sees a smooth geometric exit. Clear the
	# darken/blur AFTER the slide, when the main menu is in place.
	AudioManager.set_menu_mode(false)
	if _bg_layer and _bg_layer.has_method("_clear_black"):
		_bg_layer._clear_black()
	VNAudioService.stop_bgm()
	AudioManager.stop_voice()
	AudioManager.stop_ambience()
	AudioManager.unlock_audio()
	AudioManager.play_bgm("res://assets/music/LANSHANProjectDemo.mp3")
	_slide_transition_to(Scene.TITLE, false)
	# Now that the main menu is visible, clear the blur + darken
	EventBus.bg_blur_toggle.emit(false)
	EventBus.bg_darken_toggle.emit(false)


func _start_new_game() -> void:
	AudioManager.stop_bgm()  # registration has no bgm
	_active_save = null
	_player_name = ""
	_new_game_pixel_transition()


## Cinematic new-game transition — mirrors the web version's SVG pixel-disintegrate filter:
##   1. Pixelate screen from 1px → ~80px blocks over 1.0s — input blocked
##   2. Slide to Registration scene at peak pixelation
##   3. Un-pixelate from 80px → 1px over 0.6s
func _new_game_pixel_transition() -> void:
	if _is_transitioning:
		return
	_is_transitioning = true
	_pending_back = false

	const PIXEL_TARGET: float = 80.0
	const PIXEL_IN_DURATION: float = 1.0
	const PIXEL_OUT_DURATION: float = 0.6

	# ── Setup pixelation material ──
	if not _pixel_material:
		var shader: Shader = load("res://shaders/pixelate.gdshader")
		if not shader:
			push_error("SceneManager: Failed to load pixelate shader")
			_is_transitioning = false
			_slide_transition_to(Scene.REGISTRATION, true, NEW_GAME_SLIDE_DURATION)
			return
		_pixel_material = ShaderMaterial.new()
		_pixel_material.shader = shader
		_pixel_material.set_shader_parameter("pixel_size", 1.0)
		_pixel_overlay.material = _pixel_material

	_pixel_material.set_shader_parameter("pixel_size", 1.0)
	_pixel_overlay.visible = true
	_pixel_overlay.mouse_filter = Control.MOUSE_FILTER_STOP

	# ── Phase 1: Pixelate in ──
	var t_in := create_tween()
	t_in.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_IN)
	t_in.tween_method(_set_pixel_size, 1.0, PIXEL_TARGET, PIXEL_IN_DURATION)
	await t_in.finished

	# ── Phase 2: Slide to registration at peak pixelation ──
	_is_transitioning = false
	_slide_transition_to(Scene.REGISTRATION, true, NEW_GAME_SLIDE_DURATION)

	# ── Phase 3: Un-pixelate ──
	var t_out := create_tween()
	t_out.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	t_out.tween_method(_set_pixel_size, PIXEL_TARGET, 1.0, PIXEL_OUT_DURATION)
	t_out.tween_callback(_clear_pixel_overlay)


func _set_pixel_size(v: float) -> void:
	if _pixel_material:
		_pixel_material.set_shader_parameter("pixel_size", v)


func _clear_pixel_overlay() -> void:
	if _pixel_overlay:
		_pixel_overlay.visible = false
		_pixel_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _pixel_material:
		_pixel_material.set_shader_parameter("pixel_size", 1.0)


func _start_vn() -> void:
	AudioManager.stop_bgm()
	AudioManager.set_menu_mode(false)
	# Hide shared background — VN has its own VNBackground
	EventBus.bg_blur_toggle.emit(false)
	EventBus.bg_darken_toggle.emit(false)
	if _bg_layer and _bg_layer.has_method("hide_background"):
		_bg_layer.hide_background()
	# Setup VN BEFORE sliding — ensures correct bg is visible during transition
	var vn_scene: Control = _get_scene(Scene.VN)
	if vn_scene and vn_scene.has_method("setup"):
		vn_scene.setup(_active_save, _player_name)
	_slide_transition_to(Scene.VN, true)


# ===================================================================
# Sub-scene signal handlers
# ===================================================================

func _on_scene_back() -> void:
	if _return_to_scene_gallery:
		_return_to_scene_gallery = false
		_slide_transition_to(Scene.SCENE_GALLERY, false)
		return
	if _return_to_achievements:
		_return_to_achievements = false
		_slide_transition_to(Scene.ACHIEVEMENTS, false)
		return
	if _return_to_vn:
		_return_to_vn = false
		var reopen_tab: bool = _return_to_tab_menu
		_return_to_tab_menu = false
		# Slide first, then clear blur/darken — so the background clears
		# AFTER the VN scene is in place, not during the slide.
		_slide_transition_to(Scene.VN, false)
		EventBus.bg_blur_toggle.emit(false)
		EventBus.bg_darken_toggle.emit(false)
		# Re-hide shared background — VN has its own VNBackground
		if _bg_layer and _bg_layer.has_method("hide_background"):
			_bg_layer.hide_background()
		if reopen_tab:

			# Wait for the slide transition (~0.45 s) then re-open TabMenu
			var timer := Timer.new()
			timer.one_shot = true; timer.wait_time = 0.5
			timer.timeout.connect(_on_reopen_tab_timeout.bind(timer))
			add_child(timer); timer.start()
		return
	# If coming from VN, restore background texture (was cleared by hide_background)
	if _current_scene == Scene.VN:
		if _bg_layer and _bg_layer.has_method("_apply_current"):
			_bg_layer._apply_current()
	_back_to_menu()


func _on_reopen_tab_timeout(timer: Timer) -> void:
	timer.queue_free()
	var vn: Control = _get_scene(Scene.VN)
	if vn and vn.has_method("_open_tab_menu"):
		vn._open_tab_menu()


func _on_vn_scene_changed(new_scene: String) -> void:
	if not new_scene.is_empty():
		EventBus.scene_changed.emit(new_scene)


func _on_registration_complete(p_name: String) -> void:
	_player_name = p_name
	_play_click()
	_start_vn()


func _on_registration_cancelled() -> void:
	_back_to_menu()


func _on_load_selected(save: SaveData) -> void:
	_active_save = save
	_player_name = save.player_name
	_start_vn()


func _on_achievements_gallery_requested(gallery: String) -> void:
	_return_to_achievements = true
	EventBus.bg_blur_toggle.emit(true)
	EventBus.bg_darken_toggle.emit(true)
	AudioManager.set_menu_mode(true)
	await get_tree().create_timer(0.12).timeout
	match gallery:
		"music":
			_slide_transition_to(Scene.MUSIC_GALLERY, true)
		"scene":
			_slide_transition_to(Scene.SCENE_GALLERY, true)


func _on_scene_gallery_picture_requested(entries: Array[Dictionary], start_index: int) -> void:
	_return_to_scene_gallery = true
	# Audio blur is already active from SceneGallery (menu mode stays on)
	await get_tree().create_timer(0.12).timeout
	var viewer: Control = _get_scene(Scene.PICTURE_VIEWER)
	if viewer and viewer.has_method("setup"):
		viewer.setup(entries, start_index)
	_slide_transition_to(Scene.PICTURE_VIEWER, true)


func _on_vn_back() -> void:
	_back_to_menu()


# ===================================================================
# Input — block during transitions
# ===================================================================

func _input(event: InputEvent) -> void:
	if _is_transitioning and event.is_pressed():
		if event.is_action_pressed("ui_cancel"):
			_pending_back = true
		get_viewport().set_input_as_handled()


# ===================================================================
# Audio
# ===================================================================

func _play_click() -> void:
	AudioManager.play_click()
