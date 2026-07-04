## VNAudioService : Node (Autoload)
## 这是视觉小说所使用的音频系统。
## 包括音频调用、存储状态、声音效果，等等等等。
##
## 与 AudioManager 配合使用 — 此服务处理 VN 特定的
## 高级音频功能，而 AudioManager 处理基本播放和音量。
## 点击音效始终使用 AudioManager.play_sfx() 。
extends Node

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
const DEFAULT_CROSSFADE: float = 1.5
const MAX_AMBIENCE_LAYERS: int = 4

# ---------------------------------------------------------------------------
# BGM 交叉淡入淡出 — 两个播放器实现 A/B 无缝过渡
# ---------------------------------------------------------------------------
var _bgm_a: AudioStreamPlayer = null
var _bgm_b: AudioStreamPlayer = null
var _active_bgm_player: AudioStreamPlayer = null  # 当前活动的播放器引用
var _inactive_bgm_player: AudioStreamPlayer = null  # 交叉淡入淡出备用播放器
var _current_bgm_path: String = ""
var _crossfade_tween: Tween = null
var _stop_timer_tween: Tween = null

# ---------------------------------------------------------------------------
# 环境音层 — 同时播放的环境声音（风、雨、鸟等）
# ---------------------------------------------------------------------------
var _ambience_layers: Array[AudioStreamPlayer] = []
var _ambience_paths: Array[String] = []

# ---------------------------------------------------------------------------
# 存档/读档的音频状态
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
# BGM — 基本播放 / 停止（简单情况委托给 AudioManager）
# ===================================================================

func play_bgm(path: String, loop: bool = true) -> void:
	_kill_crossfade_tween()
	if _current_bgm_path == path and _active_bgm_player.playing:
		return
	var stream := _load(path)
	if not stream:
		return

	# 使用非活动播放器实现无缝 A/B 切换 — 即使是"即时"
	# 播放也通过 0.15 秒交叉淡入淡出消除可听的停止→播放间隙。
	var old_player: AudioStreamPlayer = _active_bgm_player
	var new_player: AudioStreamPlayer = _inactive_bgm_player

	new_player.stop()
	_configure_loop(stream, loop)
	new_player.stream = stream
	new_player.volume_db = linear_to_db(0.001)
	new_player.play()

	_current_bgm_path = path
	_bgm_playback_position = 0.0

	# 快速交叉淡入淡出（0.15 秒）— 几乎无法察觉但消除间隙
	_crossfade_tween = create_tween()
	_crossfade_tween.set_parallel(true)
	_crossfade_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	if old_player.playing:
		_crossfade_tween.tween_property(old_player, "volume_db", linear_to_db(0.001), 0.15)
		# 跟踪停止计时器，以便在计时器触发前有另一个 play_bgm/stop_bgm
		# 调用到达时可以终止它（例如在快进期间）。
		_stop_timer_tween = create_tween()
		_stop_timer_tween.tween_callback(old_player.stop).set_delay(0.2)

	_crossfade_tween.tween_method(_set_player_volume.bind(new_player), 0.0, 1.0, 0.15)

	# 交换引用
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

## 从当前 BGM 交叉淡入淡出到新曲目。
## @param path          新 BGM 曲目的路径。
## @param fade_out_sec  当前 BGM 淡出的持续时间（默认 1.5 秒）。
## @param fade_in_sec   新 BGM 淡入的持续时间（默认 1.5 秒）。
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
	new_player.volume_db = linear_to_db(0.001)  # 几乎静音
	new_player.play()

	_current_bgm_path = path
	_bgm_playback_position = 0.0

	# 同时为两个播放器设置动画
	_crossfade_tween = create_tween()
	_crossfade_tween.set_parallel(true)
	_crossfade_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	# 淡出旧播放器
	if old_player.playing:
		_crossfade_tween.tween_property(old_player, "volume_db", linear_to_db(0.001), fade_out_sec)
		# 淡出完成后停止旧播放器（被跟踪以便快速调用时可以终止它）
		_stop_timer_tween = create_tween()
		_stop_timer_tween.tween_callback(old_player.stop).set_delay(fade_out_sec + 0.05)

	# 淡入新播放器
	_crossfade_tween.tween_method(_set_player_volume.bind(new_player), 0.0, 1.0, fade_in_sec)

	# 交换引用
	_active_bgm_player = new_player
	_inactive_bgm_player = old_player


## 从静音淡入 BGM。如果没有正在播放的 BGM，则以淡入方式启动曲目。
## 如果要交叉淡入淡出，请使用 crossfade_bgm()。
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


## 在 @duration 秒内淡出当前 BGM，然后停止。
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
# 环境音 — 分层环境声音
# ===================================================================

## 将环境音层设置为循环环境音。
## @param layer  0–3（MAX_AMBIENCE_LAYERS - 1）。数值越高 = "越近"/越突出。
## @param path   音频文件路径。空字符串 = 清除此层。
## @param volume 此层的线性音量 0.0–1.0（默认 0.5）。
func set_ambience_layer(layer: int, path: String, volume: float = 0.5) -> void:
	if layer < 0 or layer >= MAX_AMBIENCE_LAYERS:
		push_warning("VNAudioService: ambience layer out of range — ", layer)
		return

	var player: AudioStreamPlayer = _ambience_layers[layer]
	var old_path: String = _ambience_paths[layer]

	if path == old_path and not path.is_empty():
		# 相同路径 — 仅调整音量
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


## 清除单个环境音层，可选淡出。
func clear_ambience_layer(layer: int, fade_sec: float = 1.0) -> void:
	if layer < 0 or layer >= MAX_AMBIENCE_LAYERS:
		return
	var player: AudioStreamPlayer = _ambience_layers[layer]
	_ambience_paths[layer] = ""
	_fade_out_player(player, fade_sec)


## 清除所有环境音层。
func clear_all_ambience(fade_sec: float = 1.0) -> void:
	for i in MAX_AMBIENCE_LAYERS:
		clear_ambience_layer(i, fade_sec)


# ===================================================================
# 状态 — 存档/读档系统的保存/恢复
# ===================================================================

## 捕获当前音频状态用于存档数据。
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


## 从存档数据恢复音频状态。
func restore_audio_state(state: Dictionary) -> void:
	if state.is_empty():
		return

	# 恢复 BGM
	var bgm_path: String = state.get("bgm_path", "")
	if not bgm_path.is_empty():
		play_bgm(bgm_path, true)
		var pos: float = state.get("bgm_position", 0.0)
		if _active_bgm_player.playing and pos > 0.0:
			_active_bgm_player.seek(pos)

	# 恢复环境音层
	for i in MAX_AMBIENCE_LAYERS:
		var key: String = "ambience_" + str(i)
		if state.has(key):
			var layer_data: Dictionary = state[key]
			set_ambience_layer(i, layer_data.get("path", ""), layer_data.get("volume", 0.5))


# ===================================================================
# 内部辅助函数
# ===================================================================

func _kill_crossfade_tween() -> void:
	if _crossfade_tween and _crossfade_tween.is_valid():
		_crossfade_tween.kill()
	_crossfade_tween = null
	if _stop_timer_tween and _stop_timer_tween.is_valid():
		_stop_timer_tween.kill()
	_stop_timer_tween = null


## Tween 回调 — 从 0..1 线性值设置 volume_db。
## 注意：tween_method 首先传递插值的浮点数，然后是绑定的参数。
## 签名必须是 (v: float, player: AudioStreamPlayer) 才能匹配。
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
	if path.is_empty():
		return null

	var normalized: String = path
	if path.begins_with("/Assets/"):
		normalized = "res://assets/" + path.substr(8)
	elif path.begins_with("/Assests/"):
		normalized = "res://assets/" + path.substr(9)

	# 首先尝试直接加载
	if ResourceLoader.exists(normalized):
		var res := load(normalized)
		if res is AudioStream:
			return res
		push_warning("VNAudioService: not an AudioStream — ", normalized)
		return null

	# 回退：通过 AssetResolver 进行裸文件名解析
	if not "/" in path and not path.begins_with("res://"):
		var resolved: String = AssetResolver.resolve_any(path)
		if resolved != path and ResourceLoader.exists(resolved):
			var res := load(resolved)
			if res is AudioStream:
				return res

	push_warning("VNAudioService: could not load — ", path)
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
# 便捷方法 — 将 SFX / Click / Voice 委托给 AudioManager
# ===================================================================

func play_sfx(path: String) -> void:
	AudioManager.play_sfx(path, false)


func stop_sfx() -> void:
	AudioManager.stop_sfx()


func play_sfx_short(path: String) -> void:
	AudioManager.play_sfx_short(path)


func stop_sfx_short() -> void:
	AudioManager.stop_sfx_short()


func play_click(path: String = AudioManager.SFX_CLICK) -> void:
	AudioManager.play_click(path)


func stop_click() -> void:
	AudioManager.stop_click()


func stop_all() -> void:
	stop_bgm()
	clear_all_ambience(0.5)
	AudioManager.stop_sfx()
	AudioManager.stop_sfx_short()
	AudioManager.stop_click()
	AudioManager.stop_voice()
	AudioManager.stop_ambience()
