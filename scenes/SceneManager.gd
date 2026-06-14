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
	REWARDS,
	REGISTRATION,
	VN,
}

const BACKGROUNDS: Array[String] = [
	"res://assets/backgrounds/scenes/Autumn.jpg",
	"res://assets/backgrounds/scenes/Autumn1.jpg",
	"res://assets/backgrounds/scenes/Autumn2.jpg",
	"res://assets/backgrounds/scenes/Autumn3.jpg",
	"res://assets/backgrounds/scenes/Autumn4.jpg",
	"res://assets/backgrounds/scenes/Autumn5.jpg",
	"res://assets/backgrounds/scenes/Autumn6.jpg",
	"res://assets/backgrounds/scenes/Autumn7.jpg",
	"res://assets/backgrounds/scenes/Autumn8.jpg",
]

const TRANSITION_DURATION: float = 0.5
const SLIDE_DURATION: float = 0.45

# Scene paths (lazy-loaded on first access)
const SCENE_PATHS: Dictionary = {
	Scene.SPLASH:       "res://scenes/menu/SplashScene.tscn",
	Scene.TITLE:        "res://scenes/menu/MainMenu.tscn",
	Scene.LOAD:         "res://scenes/save_load/LoadScene.tscn",
	Scene.SETTINGS:     "res://scenes/settings/SettingsScene.tscn",
	Scene.ABOUT:        "res://scenes/about/AboutScene.tscn",
	Scene.REWARDS:      "res://scenes/rewards/RewardsScene.tscn",
	Scene.REGISTRATION: "res://scenes/registration/RegistrationScene.tscn",
	Scene.VN:           "res://scenes/vn/VNInterface.tscn",
}

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------
var _current_scene: Scene = Scene.SPLASH
var _bg_path: String = ""
var _player_name: String = ""
var _active_save: SaveData = null
var _is_transitioning: bool = false

var _scene_instances: Dictionary = {}   # Scene enum → Control (lazy)

@onready var _scene_container: Control = %SceneContainer
@onready var _transition_overlay: ColorRect = %TransitionOverlay
var _bg_layer: Control = null


# ===================================================================
# Lifecycle
# ===================================================================

func _ready() -> void:
	# Init background — pick from shared pool
	if not GameManager.BG_POOL.is_empty():
		_bg_path = GameManager.BG_POOL[randi() % GameManager.BG_POOL.size()]
		GameManager.current_background = _bg_path

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

	_hide_transition_overlay()
	_open_scene(Scene.SPLASH)

	AudioManager.unlock_audio()
	AudioManager.play_bgm("res://assets/music/LANSHANProject.mp3")


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

	# Show target
	target_instance.visible = true
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


# ===================================================================
# Slide transition — major scene horizontal slide (1:1 web port)
# ===================================================================

## Slide transition between two major scenes.
## Both old and new scenes are visible during the slide.
## Uses tween_property on offset_left/offset_right to shift
## full-rect Controls without changing their width.
func _slide_transition_to(target: Scene, forward: bool = true) -> void:
	if _is_transitioning:
		return
	_is_transitioning = true
	_transition_overlay.mouse_filter = Control.MOUSE_FILTER_STOP

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

	# Position new scene off-screen (keeping its full width)
	new_inst.visible = true
	_set_scene_inert(new_inst, false)
	new_inst.offset_left = dir * vp_w
	new_inst.offset_right = dir * vp_w

	# Enter new scene
	if new_inst.has_method("_on_enter"):
		new_inst._on_enter()

	# ── Animate both scenes sliding ──
	var tween := create_tween().set_parallel(true)
	tween.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)

	if old_inst:
		tween.tween_property(old_inst, "offset_left", -dir * vp_w, SLIDE_DURATION)
		tween.tween_property(old_inst, "offset_right", -dir * vp_w, SLIDE_DURATION)

	tween.tween_property(new_inst, "offset_left", 0.0, SLIDE_DURATION)
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
				_slide_transition_to(Scene.TITLE, true)
			else:
				_back_to_menu()
		"LOAD":
			EventBus.bg_blur_toggle.emit(true)
			_slide_transition_to(Scene.LOAD, true)
		"SETTINGS":
			EventBus.bg_blur_toggle.emit(true)
			_slide_transition_to(Scene.SETTINGS, true)
		"ABOUT":
			EventBus.bg_blur_toggle.emit(false)
			_slide_transition_to(Scene.ABOUT, true)
		"REWARDS":
			EventBus.bg_blur_toggle.emit(true)
			_slide_transition_to(Scene.REWARDS, true)
		"REGISTRATION":
			EventBus.bg_blur_toggle.emit(false)
			_start_new_game()
		"VN":
			EventBus.bg_blur_toggle.emit(false)
			_start_vn()


# ===================================================================
# Flows
# ===================================================================

func _back_to_menu() -> void:
	EventBus.bg_blur_toggle.emit(false)
	AudioManager.stop_voice()
	AudioManager.stop_ambience()
	AudioManager.unlock_audio()
	AudioManager.play_bgm("res://assets/music/LANSHANProject.mp3")
	_slide_transition_to(Scene.TITLE, false)  # back — from left


func _start_new_game() -> void:
	AudioManager.stop_bgm()  # registration has no bgm
	_active_save = null
	_player_name = ""
	_slide_transition_to(Scene.REGISTRATION, true)  # forward — from right


func _start_vn() -> void:
	AudioManager.stop_bgm()  # VN plot scripts will start their own bgm
	_slide_transition_to(Scene.VN, true)  # forward — from right
	var vn_scene: Control = _scene_instances.get(Scene.VN, null)
	if vn_scene and vn_scene.has_method("setup"):
		vn_scene.setup(_active_save, _player_name)


# ===================================================================
# Sub-scene signal handlers
# ===================================================================

func _on_scene_back() -> void:
	_back_to_menu()


func _on_vn_scene_changed(new_scene: String) -> void:
	if not new_scene.is_empty():
		EventBus.scene_changed.emit(new_scene)


func _on_registration_complete(name: String) -> void:
	_player_name = name
	_play_click()
	_start_vn()


func _on_registration_cancelled() -> void:
	_back_to_menu()


func _on_load_selected(save: SaveData) -> void:
	_active_save = save
	_player_name = save.player_name
	_start_vn()


func _on_vn_back() -> void:
	_back_to_menu()


# ===================================================================
# Input — block during transitions
# ===================================================================

func _input(event: InputEvent) -> void:
	if _is_transitioning and event.is_pressed():
		get_viewport().set_input_as_handled()


# ===================================================================
# Audio
# ===================================================================

func _play_click() -> void:
	AudioManager.play_sfx(AudioManager.SFX_CLICK)
