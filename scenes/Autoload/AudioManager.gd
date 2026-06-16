## AudioManager : Node (Autoload)
## Global singleton for audio playback — four independent tracks:
##   1. BGM        — background music (crossfade via VNAudioService)
##   2. SFX Long   — long cinematic sound effects (can loop)
##   3. SFX Short  — short one-shot sound effects
##   4. Click      — UI click sounds (always one-shot, never blocks anything)
## One dedicated player per track — all four can play simultaneously.
extends Node

const SFX_CLICK: String = "res://assets/sfx/Choose.wav"
# Audio players — one per independent track
var _bgm_player: AudioStreamPlayer
var _sfx_player: AudioStreamPlayer          # long SFX
var _sfx_short_player: AudioStreamPlayer    # short SFX
var _click_player: AudioStreamPlayer
var _voice_player: AudioStreamPlayer
var _ambience_player: AudioStreamPlayer

# Effect bus indices
var _master_bus_idx: int
var _bgm_bus_idx: int
var _sfx_bus_idx: int
var _click_bus_idx: int

# State
var _current_bgm_path: String = ""
var _initialized: bool = false


func _ready() -> void:
	# Ensure audio buses exist (create if missing)
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
# SFX — Long (cinematic / script-driven, can loop)
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
# SFX — Short (one-shot, independent player — never blocks long SFX)
# ===================================================================

## Play a short one-shot SFX. Uses a dedicated player on the SFX bus
## so it never interrupts long cinematic SFX on the main SFX player.
func play_sfx_short(path: String) -> void:
	if not _initialized:
		return
	var stream := _load(path)
	if not stream:
		return
	# One-shot: stop previous short SFX (rarely still playing), fire new
	_sfx_short_player.stop()
	_sfx_short_player.stream = stream
	_sfx_short_player.play()


func stop_sfx_short() -> void:
	if _sfx_short_player.playing:
		_sfx_short_player.stop()


# ===================================================================
# Click — UI click sounds (dedicated player + bus, never blocks SFX)
# ===================================================================

## Play a one-shot click / UI sound. Uses a dedicated player on the
## "Click" bus so it never interrupts long cinematic SFX on the "SFX" bus.
func play_click(path: String = SFX_CLICK) -> void:
	if not _initialized:
		return
	var stream := _load(path)
	if not stream:
		return
	# One-shot: stop any previous click that is still playing (rare), then fire
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
# Menu mode — dampen BGM when a sub-menu overlays the VN.
# Smoothly transitions a low-pass filter for a "wet" feel,
# without changing bus volume (SFX remain unaffected).
# ===================================================================

const MENU_LP_CUTOFF: float = 800.0    # low-pass cutoff in menu mode (Hz)
const MENU_LP_OPEN: float = 22000.0    # fully open (no filtering)
const MENU_LP_DURATION: float = 0.35   # tween duration for the transition

var _menu_lp_tween: Tween = null       # smooth cutoff transition tween


func set_menu_mode(active: bool) -> void:
	if _bgm_bus_idx == -1:
		return

	# Ensure a LowPassFilter effect exists on the BGM bus
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

	# Kill any in-progress transition so the new target wins
	if _menu_lp_tween and _menu_lp_tween.is_valid():
		_menu_lp_tween.kill()

	var target_hz: float = MENU_LP_CUTOFF if active else MENU_LP_OPEN
	_menu_lp_tween = create_tween()
	_menu_lp_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_menu_lp_tween.tween_method(_set_lp_cutoff.bind(lp), lp.cutoff_hz, target_hz, MENU_LP_DURATION)


## tween_method callback — smoothly sets the low-pass cutoff.
func _set_lp_cutoff(hz: float, lp: AudioEffectLowPassFilter) -> void:
	lp.cutoff_hz = hz


# ===================================================================
# VN / Glitch effects (placeholder)
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
# Internal — load audio via Godot's engine cache
# ===================================================================

func _load(path: String) -> AudioStream:
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	var res := load(path)
	if res is AudioStream:
		return res
	push_warning("AudioManager: not an AudioStream — ", path)
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
