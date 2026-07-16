## SceneManager : Control
## 根场景控制器 — 管理场景生命周期、过渡和路由。
## 场景在首次使用时延迟加载；隐藏的场景处于惰性状态
## （process_mode 禁用，mouse_filter 被忽略）。
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
	MAP,
	ACHIEVEMENT_LIST,
}

const TRANSITION_DURATION: float = 0.5
const SLIDE_DURATION: float = 0.45
const NEW_GAME_SLIDE_DURATION: float = 1.35  # 3× normal slide — ceremonial feel

# 场景路径（首次访问时延迟加载）
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
	Scene.MAP:            "res://scenes/Map/Map.tscn",
	Scene.ACHIEVEMENT_LIST: "res://scenes/achievements/Achievement.tscn",
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
	# 从池中移除最后一个背景以避免连续重复
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
# 生命周期
# ===================================================================

func _ready() -> void:
	# 背景在进入 TITLE 时稍后设置 — 避免双重设置闪烁
	_bg_path = ""
	GameManager.current_background = ""

	# 创建持久背景层（位于所有内容之后，在过渡中保留）
	var bg_packed: PackedScene = load("res://scenes/ui/BackgroundLayer.tscn") as PackedScene
	if bg_packed:
		_bg_layer = bg_packed.instantiate()
		_bg_layer.name = "BackgroundLayer"
		add_child(_bg_layer)
		move_child(_bg_layer, 0)

	EventBus.scene_changed.connect(_on_scene_changed)

	# 确保 TransitionOverlay 在场景内容上方渲染
	move_child(_transition_overlay, get_child_count() - 1)

	# BackBufferCopy + PixelOverlay 用于新游戏电影级过渡。
	# BackBufferCopy 捕获屏幕以便像素化着色器可以采样。
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

	# 成就达成全局弹窗 — 顶层 CanvasLayer（layer 100），
	# 出现在一切场景元素之上，不拦截其他场景的输入。
	var toast_packed: PackedScene = load("res://scenes/achievements/AchivementReached.tscn") as PackedScene
	if toast_packed:
		var toast_layer := CanvasLayer.new()
		toast_layer.name = "AchievementToastLayer"
		toast_layer.layer = 100
		add_child(toast_layer)
		toast_layer.add_child(toast_packed.instantiate())

	AudioManager.unlock_audio()
	AudioManager.play_bgm("res://assets/music/LANSHANProjectDemo.mp3")


# ===================================================================
# 延迟场景访问
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
# 惰性状态 — 隐藏的场景停止处理
# ===================================================================

func _set_scene_inert(scene: Control, inert: bool) -> void:
	if inert:
		scene.process_mode = Node.PROCESS_MODE_DISABLED
		scene.mouse_filter = Control.MOUSE_FILTER_IGNORE
	else:
		scene.process_mode = Node.PROCESS_MODE_INHERIT
		scene.mouse_filter = Control.MOUSE_FILTER_STOP


# ===================================================================
# 场景切换 — 即时（无过渡）
# ===================================================================

func _open_scene(target: Scene) -> void:
	var target_instance: Control = _get_scene(target)
	if not target_instance:
		push_error("SceneManager: Cannot open scene — ", target)
		return

	# 退出当前场景
	var current_instance: Control = _scene_instances.get(_current_scene, null)
	if current_instance and current_instance.has_method("_on_exit"):
		current_instance._on_exit()

	# 隐藏所有场景
	for scene: Control in _scene_instances.values():
		if scene:
			scene.visible = false
			_set_scene_inert(scene, true)

	# 显示目标 — 强制完全不透明以覆盖场景 _ready() 中任何进行中的
	# _animate_enter() 淡入。
	target_instance.visible = true
	target_instance.modulate.a = 1.0
	_set_scene_inert(target_instance, false)

	_current_scene = target

	# Enter new scene
	if target_instance.has_method("_on_enter"):
		target_instance._on_enter()


# ===================================================================
# 淡入黑色过渡（保留作为次要过渡的后备方案）
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
# 滑动过渡 — 主要场景水平滑动（1:1 网络版移植）
# ===================================================================

## 在两个主要场景之间滑动过渡。
## 滑动期间旧场景和新场景都可见。
## 使用 offset_left/offset_right 上的 tween_property 来移动
## 全矩形控件而不改变其宽度。
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

	# 方向：forward=true → 新场景从右侧来（+1），forward=false → 新场景从左侧来（-1）
	var dir: float = 1.0 if forward else -1.0

	# 在可见之前将位置设置到屏幕外 — 避免一帧闪烁
	new_inst.offset_left = dir * vp_w
	new_inst.offset_right = dir * vp_w
	new_inst.visible = true
	# 强制完全不透明 — 子菜单有自己的 _animate_enter() 淡入
	# 动画（0.8 秒）与滑动（0.45 秒）冲突。没有此重置，
	# 场景会以半透明状态滑入，导致可见闪烁。
	new_inst.modulate.a = 1.0
	_set_scene_inert(new_inst, false)

	# Enter new scene
	if new_inst.has_method("_on_enter"):
		new_inst._on_enter()

	# ── 为两个场景设置滑动动画 ──
	var tween := create_tween().set_parallel(true)
	tween.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)

	if old_inst:
		tween.tween_property(old_inst, "offset_left", -dir * vp_w, slide_dur)
		tween.tween_property(old_inst, "offset_right", -dir * vp_w, slide_dur)

	tween.tween_property(new_inst, "offset_left", 0.0, slide_dur)
	tween.tween_property(new_inst, "offset_right", 0.0, slide_dur)

	await tween.finished

	# ── 清理 ──
	if old_inst:
		old_inst.visible = false
		old_inst.offset_left = 0.0
		old_inst.offset_right = 0.0
		_set_scene_inert(old_inst, true)

	_current_scene = target
	_transition_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_is_transitioning = false

# 处理过渡期间按下的 ESC 键
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
				# 淡入黑色过渡：splash → 黑色 → 主菜单。
				# 对于此过渡比滑动更平滑，因为
				# 主菜单有自己的复杂入场动画。
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
			# 恢复共享背景 — VN 隐藏了它，但子菜单需要它来实现模糊/变暗
			if _bg_layer and _bg_layer.has_method("_apply_current"):
				_bg_layer._apply_current()
			EventBus.bg_blur_toggle.emit(true)
			EventBus.bg_darken_toggle.emit(true)
			AudioManager.set_menu_mode(true)
			await get_tree().create_timer(0.12).timeout
			_slide_transition_to(Scene.SETTINGS, true)
		"MAP_FROM_VN":
			_return_to_vn = true
			_return_to_tab_menu = true
			if _bg_layer and _bg_layer.has_method("_apply_current"):
				_bg_layer._apply_current()
			EventBus.bg_blur_toggle.emit(true)
			EventBus.bg_darken_toggle.emit(true)
			AudioManager.set_menu_mode(true)
			await get_tree().create_timer(0.12).timeout
			_slide_transition_to(Scene.MAP, true)
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
# 流程
# ===================================================================

func _back_to_menu() -> void:
	# 防止过渡期间重复执行
	if _is_transitioning:
		return

	# 首先滑出子菜单 — 在滑动期间保持背景变暗，
	# 以便玩家看到平滑的几何退出。在滑动完成后，
	# 当主菜单就位时清除变暗/模糊。
	AudioManager.set_menu_mode(false)
	if _bg_layer and _bg_layer.has_method("_clear_black"):
		_bg_layer._clear_black()
	VNAudioService.stop_bgm()
	VNAudioService.clear_all_ambience(0.5)
	AudioManager.unlock_audio()
	AudioManager.play_bgm("res://assets/music/LANSHANProjectDemo.mp3")
	_slide_transition_to(Scene.TITLE, false)
	# 现在主菜单已可见，清除模糊 + 变暗
	EventBus.bg_blur_toggle.emit(false)
	EventBus.bg_darken_toggle.emit(false)


func _start_new_game() -> void:
	AudioManager.stop_bgm()  # registration has no bgm
	_active_save = null
	_player_name = ""
	_new_game_pixel_transition()


## 电影级新游戏过渡 — 镜像网络版 SVG 像素分解滤镜：
##   1. 在 1.0 秒内将屏幕从 1px → ~80px 块像素化 — 输入被阻止
##   2. 在峰值像素化时滑动到注册场景
##   3. 在 0.6 秒内从 80px → 1px 去像素化
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

	# ── 阶段 1：像素化进入 ──
	var t_in := create_tween()
	t_in.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_IN)
	t_in.tween_method(_set_pixel_size, 1.0, PIXEL_TARGET, PIXEL_IN_DURATION)
	await t_in.finished

	# ── 阶段 2：在峰值像素化时滑动到注册场景 ──
	_is_transitioning = false
	_slide_transition_to(Scene.REGISTRATION, true, NEW_GAME_SLIDE_DURATION)

	# ── 阶段 3：去像素化 ──
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
	# 隐藏共享背景 — VN 有自己的 VNBackground
	EventBus.bg_blur_toggle.emit(false)
	EventBus.bg_darken_toggle.emit(false)
	if _bg_layer and _bg_layer.has_method("hide_background"):
		_bg_layer.hide_background()
	# 在滑动前设置 VN — 确保过渡期间能看到正确的背景
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

		if reopen_tab:
			# 设置/地图是从 TabMenu 打开的。
			# 在滑动开始前预打开 TabMenu，这样滑动期间玩家看到的是
			# TabMenu 覆盖层随 VN 一起滑入，而非原始 VN 游戏界面的瞬间闪烁。
			var vn: Control = _get_scene(Scene.VN)
			if vn and vn.has_method("_open_tab_menu"):
				vn._open_tab_menu()
			await _slide_transition_to(Scene.VN, false)
			EventBus.bg_blur_toggle.emit(false)
			EventBus.bg_darken_toggle.emit(false)
			if _bg_layer and _bg_layer.has_method("hide_background"):
				_bg_layer.hide_background()
			return

		# 先滑动，然后清除模糊/变暗 — 以便背景在
		# VN 场景就位后才清除，而不是在滑动期间。
		_slide_transition_to(Scene.VN, false)
		EventBus.bg_blur_toggle.emit(false)
		EventBus.bg_darken_toggle.emit(false)
		# Re-hide shared background — VN has its own VNBackground
		if _bg_layer and _bg_layer.has_method("hide_background"):
			_bg_layer.hide_background()
		return
# 如果来自 VN，恢复背景纹理（被 hide_background 清除）
	if _current_scene == Scene.VN:
		if _bg_layer and _bg_layer.has_method("_apply_current"):
			_bg_layer._apply_current()
	_back_to_menu()


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
		"achievements":
			_slide_transition_to(Scene.ACHIEVEMENT_LIST, true)


func _on_scene_gallery_picture_requested(entries: Array[Dictionary], start_index: int) -> void:
	_return_to_scene_gallery = true
# 音频模糊已从 SceneGallery 激活（菜单模式保持开启）
	await get_tree().create_timer(0.12).timeout
	var viewer: Control = _get_scene(Scene.PICTURE_VIEWER)
	if viewer and viewer.has_method("setup"):
		viewer.setup(entries, start_index)
	_slide_transition_to(Scene.PICTURE_VIEWER, true)


func _on_vn_back() -> void:
	_back_to_menu()


# ===================================================================
# 输入 — 过渡期间阻止
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
