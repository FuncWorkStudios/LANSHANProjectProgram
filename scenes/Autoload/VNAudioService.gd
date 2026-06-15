## VNAudioService : Node (Autoload)
## Advanced audio service for the VN system.
## Features: crossfade BGM, fade in/out, ambience layering, audio state save/restore.
##
## Works alongside AudioManager — this service handles VN-specific
## high-level audio features while AudioManager handles basic playback and volume.
## For SFX, use AudioManager.play_sfx() directly.
extends Node

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
const DEFAULT_CROSSFADE: float = 1.5
const MAX_AMBIENCE_LAYERS: int = 4

# ---------------------------------------------------------------------------
# BGM crossfade — two players for A/B seamless transitions
# ---------------------------------------------------------------------------
var _bgm_a: AudioStreamPlayer = null
var _bgm_b: AudioStreamPlayer = null
var _active_bgm_player: AudioStreamPlayer = null  # currently-active player reference
var _inactive_bgm_player: AudioStreamPlayer = null  # standby player for crossfade
var _current_bgm_path: String = ""
var _crossfade_tween: Tween = null
var _stop_timer_tween: Tween = null

# ---------------------------------------------------------------------------
# Ambience layers — simultaneous ambient sounds (wind, rain, birds, etc.)
# ---------------------------------------------------------------------------
var _ambience_layers: Array[AudioStreamPlayer] = []
var _ambience_paths: Array[String] = []

# ---------------------------------------------------------------------------
# Audio state for save/load
# ---------------------------------------------------------------------------
var _bgm_playback_position: float = 0.0

# ---------------------------------------------------------------------------
# Ready
# ---------------------------------------------------------------------------

func _ready() -> void:
	var bgm_bus: String = "BGM" if AudioServer.get_bus_index("BGM") != -1 else "Master"

	_bgm_a = _make_player("VNAS_BGM_A", bgm_bus)
	_bgm_b = _make_player("VNAS_BGM_B", bgm_bus)
	_active_bgm_player = _bgm_a
	_inactive_bgm_player = _bgm_b

	for i in MAX_AMBIENCE_LAYERS:
		var p := _make_player("VNAS_Ambience_" + str(i), bgm_bus)
		p.volume_db = -80.0  # silent by default
		_ambience_layers.append(p)
		_ambience_paths.append("")


func _make_player(p_name: String, p_bus: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.name = p_name
	p.bus = p_bus
	add_child(p)
	return p


# ===================================================================
# BGM — basic play / stop (delegates to AudioManager for simple cases)
# ===================================================================

func play_bgm(path: String, loop: bool = true) -> void:
	_kill_crossfade_tween()
	if _current_bgm_path == path and _active_bgm_player.playing:
		return
	var stream := _load(path)
	if not stream:
		return

	# Use the inactive player for a seamless A/B switch — even for "instant"
	# play this eliminates the audible stop→play gap with a 0.15 s crossfade.
	var old_player: AudioStreamPlayer = _active_bgm_player
	var new_player: AudioStreamPlayer = _inactive_bgm_player

	new_player.stop()
	_configure_loop(stream, loop)
	new_player.stream = stream
	new_player.volume_db = linear_to_db(0.001)
	new_player.play()

	_current_bgm_path = path
	_bgm_playback_position = 0.0

	# Quick crossfade (0.15 s) — imperceptible but eliminates gap
	_crossfade_tween = create_tween()
	_crossfade_tween.set_parallel(true)
	_crossfade_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	if old_player.playing:
		_crossfade_tween.tween_property(old_player, "volume_db", linear_to_db(0.001), 0.15)
		# Track the stop-timer so it can be killed if another play_bgm/stop_bgm
		# call arrives before the timer fires (e.g. during fast-forward).
		_stop_timer_tween = create_tween()
		_stop_timer_tween.tween_callback(old_player.stop).set_delay(0.2)

	_crossfade_tween.tween_method(_set_player_volume.bind(new_player), 0.0, 1.0, 0.15)

	# Swap references
	_active_bgm_player = new_player
	_inactive_bgm_player = old_player


func stop_bgm() -> void:
	_kill_crossfade_tween()
	if _active_bgm_player.playing:
		_stop_timer_tween = create_tween()
		_stop_timer_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_stop_timer_tween.tween_property(_active_bgm_player, "volume_db", linear_to_db(0.001), 0.1)
		_stop_timer_tween.tween_callback(_active_bgm_player.stop)
	if _inactive_bgm_player.playing:
		_inactive_bgm_player.stop()
	_current_bgm_path = ""
	_bgm_playback_position = 0.0


# ===================================================================
# BGM — crossfade
# ===================================================================

## Crossfade from current BGM to a new track.
## @param path          Path to the new BGM track.
## @param fade_out_sec  Duration to fade OUT the current BGM (default 1.5s).
## @param fade_in_sec   Duration to fade IN the new BGM (default 1.5s).
func crossfade_bgm(path: String, fade_out_sec: float = DEFAULT_CROSSFADE, fade_in_sec: float = DEFAULT_CROSSFADE) -> void:
	_kill_crossfade_tween()

	if path.is_empty():
		fade_out_bgm(fade_out_sec)
		return

	var stream := _load(path)
	if not stream:
		fade_out_bgm(fade_out_sec)
		return

	# Swap active/inactive
	var old_player: AudioStreamPlayer = _active_bgm_player
	var new_player: AudioStreamPlayer = _inactive_bgm_player

	new_player.stop()
	_configure_loop(stream, true)
	new_player.stream = stream
	new_player.volume_db = linear_to_db(0.001)  # nearly silent
	new_player.play()

	_current_bgm_path = path
	_bgm_playback_position = 0.0

	# Tween both players simultaneously
	_crossfade_tween = create_tween()
	_crossfade_tween.set_parallel(true)
	_crossfade_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	# Fade out old player
	if old_player.playing:
		_crossfade_tween.tween_property(old_player, "volume_db", linear_to_db(0.001), fade_out_sec)
		# Stop old player after fade completes (tracked so rapid calls can kill it)
		_stop_timer_tween = create_tween()
		_stop_timer_tween.tween_callback(old_player.stop).set_delay(fade_out_sec + 0.05)

	# Fade in new player
	_crossfade_tween.tween_method(_set_player_volume.bind(new_player), 0.0, 1.0, fade_in_sec)

	# Swap references
	_active_bgm_player = new_player
	_inactive_bgm_player = old_player


## Fade in BGM from silence. If no BGM is playing, starts the track faded in.
## If crossfading, use crossfade_bgm() instead.
func fade_in_bgm(path: String, duration: float = 2.0) -> void:
	_kill_crossfade_tween()

	var stream := _load(path)
	if not stream:
		return

	if _current_bgm_path == path and _active_bgm_player.playing:
		return

	_active_bgm_player.stop()
	_configure_loop(stream, true)
	_current_bgm_path = path
	_active_bgm_player.stream = stream
	_active_bgm_player.volume_db = linear_to_db(0.001)
	_active_bgm_player.play()
	_bgm_playback_position = 0.0

	var tw := create_tween()
	tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_method(_set_player_volume.bind(_active_bgm_player), 0.0, 1.0, duration)


## Fade out current BGM over @duration seconds, then stop.
func fade_out_bgm(duration: float = 2.0) -> void:
	_kill_crossfade_tween()
	if not _active_bgm_player.playing:
		return

	var player_to_fade: AudioStreamPlayer = _active_bgm_player
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(player_to_fade, "volume_db", linear_to_db(0.001), duration)
	tw.tween_callback(player_to_fade.stop)
	_current_bgm_path = ""
	_bgm_playback_position = 0.0


# ===================================================================
# Ambience — layered environmental sounds
# ===================================================================

## Set an ambience layer to a looping ambient sound.
## @param layer  0–3 (MAX_AMBIENCE_LAYERS - 1). Higher = "closer" / more prominent.
## @param path   Audio file path. Empty string = clear this layer.
## @param volume 0.0–1.0 linear volume for this layer (default 0.5).
func set_ambience_layer(layer: int, path: String, volume: float = 0.5) -> void:
	if layer < 0 or layer >= MAX_AMBIENCE_LAYERS:
		push_warning("VNAudioService: ambience layer out of range — ", layer)
		return

	var player: AudioStreamPlayer = _ambience_layers[layer]
	var old_path: String = _ambience_paths[layer]

	if path == old_path and not path.is_empty():
		# Same path — just adjust volume
		_set_ambience_volume(player, volume)
		return

	_ambience_paths[layer] = path

	if path.is_empty():
		_fade_out_player(player, 1.0)
		return

	var stream := _load(path)
	if not stream:
		return

	player.stop()
	_configure_loop(stream, true)
	player.stream = stream
	player.volume_db = linear_to_db(0.001)
	player.play()
	_set_ambience_volume(player, volume)


## Clear a single ambience layer with optional fade.
func clear_ambience_layer(layer: int, fade_sec: float = 1.0) -> void:
	if layer < 0 or layer >= MAX_AMBIENCE_LAYERS:
		return
	var player: AudioStreamPlayer = _ambience_layers[layer]
	_ambience_paths[layer] = ""
	_fade_out_player(player, fade_sec)


## Clear all ambience layers.
func clear_all_ambience(fade_sec: float = 1.0) -> void:
	for i in MAX_AMBIENCE_LAYERS:
		clear_ambience_layer(i, fade_sec)


# ===================================================================
# State — save / restore for the save-load system
# ===================================================================

## Capture current audio state for save data.
func get_audio_state() -> Dictionary:
	var state: Dictionary = {
		"bgm_path": _current_bgm_path,
		"bgm_position": _active_bgm_player.get_playback_position() if _active_bgm_player.playing else 0.0,
	}
	for i in MAX_AMBIENCE_LAYERS:
		if not _ambience_paths[i].is_empty():
			state["ambience_" + str(i)] = {
				"path": _ambience_paths[i],
				"volume": db_to_linear(_ambience_layers[i].volume_db),
			}
	return state


## Restore audio state from save data.
func restore_audio_state(state: Dictionary) -> void:
	if state.is_empty():
		return

	# Restore BGM
	var bgm_path: String = state.get("bgm_path", "")
	if not bgm_path.is_empty():
		play_bgm(bgm_path, true)
		var pos: float = state.get("bgm_position", 0.0)
		if _active_bgm_player.playing and pos > 0.0:
			_active_bgm_player.seek(pos)

	# Restore ambience layers
	for i in MAX_AMBIENCE_LAYERS:
		var key: String = "ambience_" + str(i)
		if state.has(key):
			var layer_data: Dictionary = state[key]
			set_ambience_layer(i, layer_data.get("path", ""), layer_data.get("volume", 0.5))


# ===================================================================
# Internal helpers
# ===================================================================

func _kill_crossfade_tween() -> void:
	if _crossfade_tween and _crossfade_tween.is_valid():
		_crossfade_tween.kill()
	_crossfade_tween = null
	if _stop_timer_tween and _stop_timer_tween.is_valid():
		_stop_timer_tween.kill()
	_stop_timer_tween = null


## Tween callback — set volume_db from a 0..1 linear value.
## NOTE: tween_method passes the interpolated float FIRST, then bound args.
## Signature must be (v: float, player: AudioStreamPlayer) to match.
func _set_player_volume(v: float, player: AudioStreamPlayer) -> void:
	player.volume_db = linear_to_db(clamp(v, 0.001, 1.0))


func _set_ambience_volume(player: AudioStreamPlayer, volume: float) -> void:
	player.volume_db = linear_to_db(clamp(volume, 0.0, 1.0))


func _fade_out_player(player: AudioStreamPlayer, duration: float) -> void:
	if not player.playing:
		return
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(player, "volume_db", linear_to_db(0.001), duration)
	tw.tween_callback(player.stop)


func _load(path: String) -> AudioStream:
	var normalized: String = path
	if path.begins_with("/Assets/"): normalized = "res://assets/" + path.substr(8)
	elif path.begins_with("/Assests/"): normalized = "res://assets/" + path.substr(9)
	if normalized.is_empty() or not ResourceLoader.exists(normalized):
		return null
	var res := load(normalized)
	if res is AudioStream:
		return res
	push_warning("VNAudioService: not an AudioStream — ", normalized)
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


# ===================================================================
# Convenience — delegate SFX/Voice to AudioManager
# ===================================================================

func play_sfx(path: String) -> void:
	AudioManager.play_sfx(path, false)


func stop_sfx() -> void:
	AudioManager.stop_sfx()


func stop_all() -> void:
	stop_bgm()
	clear_all_ambience(0.5)
	AudioManager.stop_sfx()
	AudioManager.stop_voice()
	AudioManager.stop_ambience()
