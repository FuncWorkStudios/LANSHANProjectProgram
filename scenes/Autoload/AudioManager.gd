## AudioManager : Node (Autoload)
## 全局音频播放单例 — 四个独立音轨：
##   1. BGM        — 背景音乐（通过 VNAudioService 进行交叉淡入淡出）
##   2. SFX Long   — 长音效（电影级音效，可循环）
##   3. SFX Short  — 短音效（单次播放）
##   4. Click      — UI 点击音效（始终单次播放，从不阻塞任何内容）
## 每个音轨一个专用播放器 — 四个可以同时播放。
extends Node

const SFX_CLICK: String = "res://assets/sfx/Choose.mp3"
# 音频播放器 — 每个独立音轨一个
var _bgm_player: AudioStreamPlayer
var _sfx_player: AudioStreamPlayer          # 长音效
var _sfx_short_player: AudioStreamPlayer    # 短音效
var _click_player: AudioStreamPlayer
var _voice_player: AudioStreamPlayer
var _ambience_player: AudioStreamPlayer

# 效果总线索引
var _master_bus_idx: int
var _bgm_bus_idx: int
var _sfx_bus_idx: int
var _click_bus_idx: int

# State
var _current_bgm_path: String = ""
var _initialized: bool = false


func _ready() -> void:
	# 确保音频总线存在（如果不存在则创建）
	_master_bus_idx = AudioServer.get_bus_index("Master")
	if AudioServer.get_bus_index("BGM") == -1:
		AudioServer.add_bus(_master_bus_idx + 1)
		AudioServer.set_bus_name(_master_bus_idx + 1, "BGM")
	if AudioServer.get_bus_index("SFX") == -1:
		AudioServer.add_bus(_master_bus_idx + 2)
		AudioServer.set_bus_name(_master_bus_idx + 2, "SFX")
	if AudioServer.get_bus_index("Click") == -1:
		AudioServer.add_bus(_master_bus_idx + 3)
		AudioServer.set_bus_name(_master_bus_idx + 3, "Click")

	_bgm_bus_idx = AudioServer.get_bus_index("BGM")
	_sfx_bus_idx = AudioServer.get_bus_index("SFX")
	_click_bus_idx = AudioServer.get_bus_index("Click")

	_bgm_player = _make_player("BGMPlayer", "BGM")
	_sfx_player = _make_player("SFXLongPlayer", "SFX")
	_sfx_short_player = _make_player("SFXShortPlayer", "SFX")
	_click_player = _make_player("ClickPlayer", "Click")
	_voice_player = _make_player("VoicePlayer", "Master")
	_ambience_player = _make_player("AmbiencePlayer", "BGM")

	_initialized = true


func _make_player(p_name: String, p_bus: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.name = p_name
	p.bus = p_bus
	add_child(p)
	return p


# ===================================================================
# Volume
# ===================================================================

func unlock_audio() -> void:
	apply_volumes()


func apply_volumes() -> void:
	var s := GameManager.get_settings()
	AudioServer.set_bus_volume_db(_master_bus_idx, linear_to_db(s.master_volume))
	if _bgm_bus_idx != _master_bus_idx:
		AudioServer.set_bus_volume_db(_bgm_bus_idx, linear_to_db(s.bgm_volume * s.master_volume))
	if _sfx_bus_idx != _master_bus_idx:
		AudioServer.set_bus_volume_db(_sfx_bus_idx, linear_to_db(s.sfx_volume * s.master_volume))


# ===================================================================
# BGM
# ===================================================================

func play_bgm(path: String, loop: bool = true) -> void:
	if not _initialized:
		return
	if _current_bgm_path == path and _bgm_player.playing:
		return

	var stream := _load(path)
	if not stream:
		return

	if _bgm_player.playing:
		_bgm_player.stop()

	_configure_loop(stream, loop)
	_current_bgm_path = path
	_bgm_player.stream = stream
	_bgm_player.play()


func stop_bgm() -> void:
	if _bgm_player.playing:
		_bgm_player.stop()
	_current_bgm_path = ""


# ===================================================================
# SFX — 长音效（电影级/脚本驱动，可循环）
# ===================================================================

func play_sfx(path: String, loop: bool = false) -> void:
	if not _initialized:
		return
	var stream := _load(path)
	if not stream:
		return
	_sfx_player.stop()
	_configure_loop(stream, loop)
	_sfx_player.stream = stream
	_sfx_player.play()


func stop_sfx() -> void:
	if _sfx_player.playing:
		_sfx_player.stop()


# ===================================================================
# SFX — 短音效（单次播放，独立播放器 — 从不阻塞长音效）
# ===================================================================

## 播放一个短的单次音效。使用 SFX 总线上的专用播放器，
## 因此它从不中断主 SFX 播放器上的长电影级音效。
func play_sfx_short(path: String) -> void:
	if not _initialized:
		return
	var stream := _load(path)
	if not stream:
		return
	# 单次播放：停止之前的短音效（很少还在播放），播放新的
	_sfx_short_player.stop()
	_sfx_short_player.stream = stream
	_sfx_short_player.play()


func stop_sfx_short() -> void:
	if _sfx_short_player.playing:
		_sfx_short_player.stop()


# ===================================================================
# Click — UI 点击音效（专用播放器 + 总线，从不阻塞 SFX）
# ===================================================================

## 播放一个单次点击/UI 音效。使用 "Click" 总线上的专用播放器，
## 因此它从不中断 "SFX" 总线上的长电影级音效。
func play_click(path: String = SFX_CLICK) -> void:
	if not _initialized:
		return
	var stream := _load(path)
	if not stream:
		return
	# 单次播放：停止任何仍在播放的之前点击音效（很少），然后播放
	_click_player.stop()
	_click_player.stream = stream
	_click_player.play()


func stop_click() -> void:
	if _click_player.playing:
		_click_player.stop()


# ===================================================================
# Voice
# ===================================================================

func play_voice(path: String) -> void:
	if not _initialized:
		return
	var stream := _load(path)
	if not stream:
		return
	_voice_player.stop()
	_voice_player.stream = stream
	_voice_player.play()


func stop_voice() -> void:
	if _voice_player.playing:
		_voice_player.stop()


# ===================================================================
# Ambience
# ===================================================================

func play_ambience(path: String, loop: bool = true) -> void:
	if not _initialized:
		return
	var stream := _load(path)
	if not stream:
		return
	_ambience_player.stop()
	_configure_loop(stream, loop)
	_ambience_player.stream = stream
	_ambience_player.play()


func stop_ambience() -> void:
	if _ambience_player.playing:
		_ambience_player.stop()


# ===================================================================
# All
# ===================================================================

func stop_all() -> void:
	stop_bgm()
	stop_sfx()
	stop_sfx_short()
	stop_click()
	stop_voice()
	stop_ambience()


# ===================================================================
# 菜单模式 — 当子菜单覆盖 VN 时减弱 BGM。
# 平滑过渡低通滤波器以获得"湿润"感，
# 不改变总线音量（SFX 不受影响）。
# ===================================================================

const MENU_LP_CUTOFF: float = 800.0    # 菜单模式下的低通截止频率（Hz）
const MENU_LP_OPEN: float = 22000.0    # 完全开放（无过滤）
const MENU_LP_DURATION: float = 0.35   # 过渡动画持续时间

var _menu_lp_tween: Tween = null       # 平滑截止频率过渡动画


func set_menu_mode(active: bool) -> void:
	if _bgm_bus_idx == -1:
		return

	# 确保 BGM 总线上存在 LowPassFilter 效果
	var lp_index: int = -1
	for i in range(AudioServer.get_bus_effect_count(_bgm_bus_idx)):
		if AudioServer.get_bus_effect(_bgm_bus_idx, i) is AudioEffectLowPassFilter:
			lp_index = i
			break
	if lp_index == -1:
		var new_lp := AudioEffectLowPassFilter.new()
		new_lp.cutoff_hz = MENU_LP_OPEN
		new_lp.resonance = 0.2
		AudioServer.add_bus_effect(_bgm_bus_idx, new_lp)
		lp_index = AudioServer.get_bus_effect_count(_bgm_bus_idx) - 1

	var lp: AudioEffectLowPassFilter = AudioServer.get_bus_effect(_bgm_bus_idx, lp_index) as AudioEffectLowPassFilter
	if lp == null:
		return

	# 终止任何进行中的过渡，使新目标生效
	if _menu_lp_tween and _menu_lp_tween.is_valid():
		_menu_lp_tween.kill()

	var target_hz: float = MENU_LP_CUTOFF if active else MENU_LP_OPEN
	_menu_lp_tween = create_tween()
	_menu_lp_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_menu_lp_tween.tween_method(_set_lp_cutoff.bind(lp), lp.cutoff_hz, target_hz, MENU_LP_DURATION)


## tween_method 回调 — 平滑设置低通截止频率。
func _set_lp_cutoff(hz: float, lp: AudioEffectLowPassFilter) -> void:
	lp.cutoff_hz = hz


# ===================================================================
# VN / Glitch 效果（占位符）
# ===================================================================

func set_vn_effect(_intensity: float) -> void:
	pass


func update_glitch_effect(progress: float) -> void:
	if _bgm_bus_idx == -1:
		return
	for i in range(AudioServer.get_bus_effect_count(_bgm_bus_idx)):
		var fx := AudioServer.get_bus_effect(_bgm_bus_idx, i)
		if fx is AudioEffectLowPassFilter:
			var freq := 22000.0 * pow(1.0 - progress, 4)
			(fx as AudioEffectLowPassFilter).cutoff_hz = max(100.0, freq)

	var s := GameManager.get_settings()
	var v := s.bgm_volume * s.master_volume * (1.0 - pow(progress, 3))
	if progress >= 1.0:
		stop_bgm()
	else:
		AudioServer.set_bus_volume_db(_bgm_bus_idx, linear_to_db(max(0.001, v)))


func reset_effects() -> void:
	set_menu_mode(false)
	apply_volumes()


# ===================================================================
# 内部 — 通过 Godot 引擎缓存加载音频
# ===================================================================

func _load(path: String) -> AudioStream:
	if path.is_empty():
		return null

	# 规范化 Web 风格路径
	var normalized: String = path
	if normalized.begins_with("/Assests/"):
		normalized = "res://assets/" + normalized.substr(9)
	elif normalized.begins_with("/Assets/"):
		normalized = "res://assets/" + normalized.substr(8)

	# Try direct load first
	if ResourceLoader.exists(normalized):
		var res := load(normalized)
		if res is AudioStream:
			return res
		push_warning("AudioManager: not an AudioStream — ", path)
		return null

	# Fallback: bare filename resolution
	if not "/" in path and not path.begins_with("res://"):
		var resolved: String = AssetResolver.resolve_any(path)
		if resolved != path and ResourceLoader.exists(resolved):
			var res := load(resolved)
			if res is AudioStream:
				return res

	push_warning("AudioManager: could not load — ", path)
	return null


func _configure_loop(stream: AudioStream, loop: bool) -> void:
	if not loop:
		return
	if stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true
	elif stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	elif stream is AudioStreamWAV:
		(stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
