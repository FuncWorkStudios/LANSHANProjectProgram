## AudioManager : Node (Autoload)
## Global singleton for audio playback — BGM, SFX, voice, and ambience.
## Replaces the web version's audioService.ts with Web Audio API effects.
extends Node

# Audio players
var _bgm_player: AudioStreamPlayer
var _sfx_player: AudioStreamPlayer
var _voice_player: AudioStreamPlayer
var _ambience_player: AudioStreamPlayer

# Effect buses
var _master_bus_idx: int
var _bgm_bus_idx: int
var _sfx_bus_idx: int

# State
var _current_bgm_path: String = ""
var _is_menu_mode: bool = false
var _initialized: bool = false


func _ready() -> void:
	_setup_audio_buses()
	_create_players()


func _setup_audio_buses() -> void:
	# Master, BGM, SFX buses should be set up in the editor's Audio Bus Layout
	# Here we just store their indices
	_master_bus_idx = AudioServer.get_bus_index("Master")
	_bgm_bus_idx = AudioServer.get_bus_index("BGM")
	_sfx_bus_idx = AudioServer.get_bus_index("SFX")
	if _bgm_bus_idx == -1:
		_bgm_bus_idx = _master_bus_idx
	if _sfx_bus_idx == -1:
		_sfx_bus_idx = _master_bus_idx


func _create_players() -> void:
	_bgm_player = AudioStreamPlayer.new()
	_bgm_player.bus = "BGM" if AudioServer.get_bus_index("BGM") != -1 else "Master"
	_bgm_player.name = "BGMPlayer"
	add_child(_bgm_player)

	_sfx_player = AudioStreamPlayer.new()
	_sfx_player.bus = "SFX" if AudioServer.get_bus_index("SFX") != -1 else "Master"
	_sfx_player.name = "SFXPlayer"
	add_child(_sfx_player)

	_voice_player = AudioStreamPlayer.new()
	_voice_player.bus = "Master"
	_voice_player.name = "VoicePlayer"
	add_child(_voice_player)

	_ambience_player = AudioStreamPlayer.new()
	_ambience_player.bus = "BGM" if AudioServer.get_bus_index("BGM") != -1 else "Master"
	_ambience_player.name = "AmbiencePlayer"
	add_child(_ambience_player)

	_initialized = true


func unlock_audio() -> void:
	# In Godot, audio works immediately — no need for Web Audio unlock
	apply_volumes()


func apply_volumes() -> void:
	var settings := GameManager.get_settings()
	var master_db := linear_to_db(settings.master_volume)
	var bgm_db := linear_to_db(settings.bgm_volume * settings.master_volume)
	var sfx_db := linear_to_db(settings.sfx_volume * settings.master_volume)

	AudioServer.set_bus_volume_db(_master_bus_idx, master_db)
	if _bgm_bus_idx != _master_bus_idx:
		AudioServer.set_bus_volume_db(_bgm_bus_idx, bgm_db)
	if _sfx_bus_idx != _master_bus_idx:
		AudioServer.set_bus_volume_db(_sfx_bus_idx, sfx_db)


# --- BGM ---

func play_bgm(path: String, loop: bool = true) -> void:
	if not _initialized:
		return

	# Skip if already playing the same track
	if _current_bgm_path == path and _bgm_player.playing:
		return

	stop_bgm()
	_current_bgm_path = path

	var file := _load_audio_stream(path)
	if file:
		_bgm_player.stream = file
		if loop:
			# For looping, we'll use the AudioStream's loop properties
			if file is AudioStreamMP3:
				(file as AudioStreamMP3).loop = true
			elif file is AudioStreamOggVorbis:
				(file as AudioStreamOggVorbis).loop = true
			elif file is AudioStreamWAV:
				(file as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
		_bgm_player.play()


func stop_bgm() -> void:
	if _bgm_player.playing:
		_bgm_player.stop()
	_current_bgm_path = ""


# --- SFX ---

func play_sfx(path: String, loop: bool = false) -> void:
	if not _initialized:
		return
	var file := _load_audio_stream(path)
	if file:
		_sfx_player.stream = file
		_sfx_player.play()


func stop_sfx() -> void:
	if _sfx_player.playing:
		_sfx_player.stop()


# --- Voice ---

func play_voice(path: String) -> void:
	if not _initialized:
		return
	stop_voice()
	var file := _load_audio_stream(path)
	if file:
		_voice_player.stream = file
		_voice_player.play()


func stop_voice() -> void:
	if _voice_player.playing:
		_voice_player.stop()


# --- Ambience ---

func play_ambience(path: String, loop: bool = true) -> void:
	if not _initialized:
		return
	stop_ambience()
	var file := _load_audio_stream(path)
	if file:
		_ambience_player.stream = file
		if loop and file is AudioStreamMP3:
			(file as AudioStreamMP3).loop = true
		_ambience_player.play()


func stop_ambience() -> void:
	if _ambience_player.playing:
		_ambience_player.stop()


# --- All ---

func stop_all() -> void:
	stop_bgm()
	stop_sfx()
	stop_voice()
	stop_ambience()
	_current_bgm_path = ""


# --- Menu effect ---

func set_menu_mode(active: bool) -> void:
	_is_menu_mode = active
	if active:
		# Apply low-pass filter to BGM bus for muffled menu sound
		_apply_menu_effect(true)
	else:
		_apply_menu_effect(false)


func _apply_menu_effect(enable: bool) -> void:
	# This is a simplified version — for full effect, use AudioEffectFilter on the BGM bus
	# In editor, add an AudioEffectLowPassFilter to the BGM bus and toggle it here
	if _bgm_bus_idx == -1:
		return
	var effect_count := AudioServer.get_bus_effect_count(_bgm_bus_idx)
	for i in range(effect_count):
		var effect := AudioServer.get_bus_effect(_bgm_bus_idx, i)
		if effect is AudioEffectLowPassFilter:
			var lp := effect as AudioEffectLowPassFilter
			lp.cutoff_hz = 400.0 if enable else 22000.0


# --- Voice/SFX effect (glitch effect override — now does nothing per web version update) ---

func set_vn_effect(_intensity: float) -> void:
	# The web version canceled VN glitch audio effects — keep audio clear
	pass


# --- Glitch transition effect ---

func update_glitch_effect(progress: float) -> void:
	if _bgm_bus_idx == -1:
		return
	# Apply increasing low-pass and volume fade during pixel transition
	var effect_count := AudioServer.get_bus_effect_count(_bgm_bus_idx)
	for i in range(effect_count):
		var effect := AudioServer.get_bus_effect(_bgm_bus_idx, i)
		if effect is AudioEffectLowPassFilter:
			var lp := effect as AudioEffectLowPassFilter
			var freq := 22000.0 * pow(1.0 - progress, 4)
			lp.cutoff_hz = max(100.0, freq)

	# Volume fade
	var settings := GameManager.get_settings()
	var fade_vol := settings.bgm_volume * settings.master_volume * (1.0 - pow(progress, 3))
	if progress >= 1.0:
		stop_bgm()
	else:
		AudioServer.set_bus_volume_db(_bgm_bus_idx, linear_to_db(max(0.001, fade_vol)))


func reset_effects() -> void:
	_apply_menu_effect(false)
	apply_volumes()


# --- Utility ---

func _load_audio_stream(path: String) -> AudioStream:
	if path.is_empty():
		return null
	if not ResourceLoader.exists(path):
		push_warning("AudioManager: File not found — ", path)
		return null

	# Try loading as an already-imported resource
	var resource := load(path)
	if resource is AudioStream:
		return resource

	# Fallback: load from raw file data
	if path.ends_with(".mp3"):
		var stream := AudioStreamMP3.new()
		stream.data = FileAccess.get_file_as_bytes(path)
		return stream
	elif path.ends_with(".ogg"):
		var ogg_seq := OggPacketSequence.new()
		ogg_seq.data = FileAccess.get_file_as_bytes(path)
		var stream := AudioStreamOggVorbis.new()
		stream.packet_sequence = ogg_seq
		return stream
	elif path.ends_with(".wav"):
		var stream := AudioStreamWAV.new()
		stream.data = FileAccess.get_file_as_bytes(path)
		return stream

	push_warning("AudioManager: Could not load audio stream from — ", path)
	return null
