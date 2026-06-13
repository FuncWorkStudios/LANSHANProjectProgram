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
	"res://assets/Scenes/Autumn.jpg",
	"res://assets/Scenes/Autumn1.jpg",
	"res://assets/Scenes/Autumn2.jpg",
	"res://assets/Scenes/Autumn3.jpg",
	"res://assets/Scenes/Autumn4.jpg",
	"res://assets/Scenes/Autumn5.jpg",
	"res://assets/Scenes/Autumn6.jpg",
	"res://assets/Scenes/Autumn7.jpg",
	"res://assets/Scenes/Autumn8.jpg",
]

const TRANSITION_DURATION: float = 0.5

# Scene paths (lazy-loaded on first access)
const SCENE_PATHS: Dictionary = {
	Scene.SPLASH:       "res://scenes/Menu/SplashScene.tscn",
	Scene.TITLE:        "res://scenes/Menu/MainMenu.tscn",
	Scene.LOAD:         "res://scenes/SaveLoad/LoadScene.tscn",
	Scene.SETTINGS:     "res://scenes/Settings/SettingsScene.tscn",
	Scene.ABOUT:        "res://scenes/About/AboutScene.tscn",
	Scene.REWARDS:      "res://scenes/Rewards/RewardsScene.tscn",
	Scene.REGISTRATION: "res://scenes/Registration/RegistrationScene.tscn",
	Scene.VN:           "res://scenes/VN/VNInterface.tscn",
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


# ===================================================================
# Lifecycle
# ===================================================================

func _ready() -> void:
	_bg_path = BACKGROUNDS[randi() % BACKGROUNDS.size()]

	EventBus.scene_changed.connect(_on_scene_changed)

	# Ensure TransitionOverlay renders ON TOP of scene content
	move_child(_transition_overlay, get_child_count() - 1)

	_hide_transition_overlay()
	_open_scene(Scene.SPLASH)

	AudioManager.unlock_audio()
	AudioManager.play_bgm("res://assets/Music/LANSHANProject.mp3")


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
# Scene switching
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


func _transition_to(target: Scene) -> void:
	if _is_transitioning:
		return
	_is_transitioning = true
	# Block input during transition
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

	# Allow input again
	_transition_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_is_transitioning = false


func _hide_transition_overlay() -> void:
	_transition_overlay.modulate.a = 0.0


# ===================================================================
# Signal routing
# ===================================================================

func _on_scene_changed(scene_name: String) -> void:
	match scene_name:
		"SPLASH":     _transition_to(Scene.SPLASH)
		"TITLE":      _back_to_menu()
		"LOAD":       _transition_to(Scene.LOAD)
		"SETTINGS":   _transition_to(Scene.SETTINGS)
		"ABOUT":      _transition_to(Scene.ABOUT)
		"REWARDS":    _transition_to(Scene.REWARDS)
		"REGISTRATION": _start_new_game()
		"VN":         _open_scene(Scene.VN)


# ===================================================================
# Flows
# ===================================================================

func _back_to_menu() -> void:
	AudioManager.stop_voice()
	AudioManager.stop_ambience()
	AudioManager.unlock_audio()
	AudioManager.play_bgm("res://assets/Music/LANSHANProject.mp3")
	_transition_to(Scene.TITLE)


func _start_new_game() -> void:
	_active_save = null
	_player_name = ""
	_transition_to(Scene.REGISTRATION)


func _start_vn() -> void:
	_open_scene(Scene.VN)
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
	AudioManager.play_sfx("res://assets/Sfx/Choose.wav")
