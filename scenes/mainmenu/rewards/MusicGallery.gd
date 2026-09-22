## MusicGallery : Control
## 音乐画廊 — 右侧歌曲列表（OptionRow 行）+ 左侧当前播放信息。
## 列表置于 ScrollContainer 内：滚轮原生滚动列表（不移动焦点），悬停/WASD/方向键移动
## 焦点（选中动画照主页/TabMenu：位移 -50/+10 + 扫白 + 入场错峰滑入），键盘焦点越界时
## 容器滚动跟随；单击/空格/回车播放或停止，ESC 返回。
## 播放中：左侧显示曲名与简介，行内显示 ▶ NOW PLAYING；未播放时二者空白。
## 正在播放的行在播放期间始终处于选中样式（与焦点行可并亮 — 双重选中）。
## 鼠标清除焦点在列表容器级（mouse_exited）：行级退出会与焦点位移形成出入循环 —
## 光标停在行右缘时，行随焦点左移 60px 使光标"离开"该行，反复进出导致行颤抖。
extends Control

signal back_requested()

# ---------------------------------------------------------------------------
# 状态
# ---------------------------------------------------------------------------
var _entries: Array[Dictionary] = []
var _focus_idx: int = 0
var _disabled: bool = false
var _playing_idx: int = -1
var _row_nodes: Array[OptionRow] = []
var _back_bar: BackBar = null
var _subtitle_label: Label = null
var _saved_bgm_path: String = ""
## 键盘导航/列表滚动后抑制悬停抢焦点，直到鼠标再次移动（防容器滚动引发的 mouse_entered 争抢）。
var _await_mouse_motion: bool = false
## 入场错峰进行中标记（_ready 与 _on_enter 双入口防重入）。
var _intro_running: bool = false
## 行入场错峰 tweens（出场统一终止，防 inert 期间暂停残留、重入争抢）。
var _intro_tweens: Array[Tween] = []
## 入场批次代次 — _on_exit 中断后旧计时器回火不再生效（防退出-重入竞态）。
var _intro_gen: int = 0

# 行样式 — OptionRow 画廊模式（左对齐、无副标题、右侧 NOW PLAYING 指示）。
# 位于 ScrollContainer 内：容器左侧留 50px 边距（tscn TrackMargin），焦点位移 -50 不被裁切。
const ROW_TITLE_FONT_SIZE: int = 24
const NOW_PLAYING_TEXT: String = "▶ NOW PLAYING"
# 入场错峰（照 MainMenuList.INTRO_STAGGER）：45 行时延迟封顶，防拖长入场
const INTRO_STAGGER: float = 0.08
const INTRO_STAGGER_CAP: int = 8

# ---------------------------------------------------------------------------
# Onready 节点引用
# ---------------------------------------------------------------------------
@onready var _title_label: Label = %TitleLabel
@onready var _subtitle_container: Control = %SubtitleContainer
@onready var _music_title: Label = %MusicTitle
@onready var _music_desc: Label = %MusicDescription
@onready var _track_list: VBoxContainer = %TrackList
@onready var _grid_scroll: ScrollContainer = %GridScroll


# ===================================================================
# 生命周期
# ===================================================================

func _ready() -> void:
	_setup()
	_animate_enter()
	_begin_entry()


func _on_enter() -> void:
	_begin_entry()


func _refresh_translations() -> void:
	if _subtitle_label:
		_subtitle_label.text = tr("游戏中出现的音乐")
	if _back_bar:
		_back_bar.set_language()


func _on_exit() -> void:
	_disabled = true
	_intro_running = false
	_intro_gen += 1
	# 终止入场错峰 tweens — 场景 inert 期间绑定 tween 会暂停，残留导致重入争抢
	for intro_tween: Tween in _intro_tweens:
		if intro_tween.is_valid():
			intro_tween.kill()
	_intro_tweens.clear()
	# 返回成就页面之前，停止任何正在播放的预览并恢复菜单模式
	if _playing_idx >= 0:
		AudioManager.stop_bgm()
		AudioManager.set_menu_mode(true)
		if not _saved_bgm_path.is_empty():
			AudioManager.play_bgm(_saved_bgm_path, true)
			_saved_bgm_path = ""
		_set_playing(-1)


# ===================================================================
# 设置
# ===================================================================

func _setup() -> void:
	_title_label.text = "Music"
	_title_label.add_theme_font_size_override("font_size", 72)
	if GameManager.font_tcm: _title_label.add_theme_font_override("font", GameManager.font_tcm)

	# 副标题
	for c: Node in _subtitle_container.get_children():
		c.queue_free()
	var sub: Label = Label.new()
	_subtitle_label = sub
	sub.text = tr("游戏中出现的音乐")
	sub.add_theme_font_size_override("font_size", 10)
	sub.add_theme_color_override("font_color", Color(1, 1, 1, 0.4))
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_subtitle_container.add_child(sub)

	# 左侧当前播放信息（初始空白，播放时填充）
	_music_title.add_theme_font_size_override("font_size", 40)
	_music_title.add_theme_color_override("font_color", Color.WHITE)
	_music_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_music_title.clip_text = true
	_music_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if GameManager.font_tcm: _music_title.add_theme_font_override("font", GameManager.font_tcm)

	_music_desc.add_theme_font_size_override("font_size", 22)
	_music_desc.add_theme_color_override("font_color", Color(1, 1, 1, 0.75))
	_music_desc.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_music_desc.clip_text = true
	_music_desc.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# 右侧歌曲列表 — 行宽交给容器填充；滚轮由本场景 _input 逐行处理
	_track_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 鼠标离开整个列表区域才清除焦点（行级 mouse_exited 会与焦点位移形成出入循环 → 颤抖）
	_grid_scroll.mouse_exited.connect(_on_list_mouse_exited)

	# 从预加载数据加载条目
	var music_data: RefCounted = preload("res://scripts/gallery/MusicGalleryData.gd")
	_entries.assign(music_data.ENTRIES)
	if _entries.is_empty():
		push_error("MusicGallery: ENTRIES 为空 — MusicGalleryData 未加载到最新数据（编辑器缓存过期？）")

	_create_rows()
	_setup_back_button()


# ===================================================================
# 列表行创建
# ===================================================================

func _create_rows() -> void:
	for i: int in range(_entries.size()):
		var row: OptionRow = OptionRow.new()
		# 画廊行：左对齐（p_align_end=false）、无副标题、行宽交给容器填充
		row.setup(i, _entries[i].title, "", GameManager.font_tcm, null, 0.0, 0.0, ROW_TITLE_FONT_SIZE, 0, false)
		row.hovered.connect(_on_row_hovered)
		row.activated.connect(_on_row_activated)
		_track_list.add_child(row)
		_row_nodes.append(row)
		# 入场初始态：全透明 + 右移屏外（等待 _play_intro_stagger 逐行滑入）
		row.prepare_intro()


## 统一入场（照 MainMenuList.play_intro_stagger）：行自右侧 x=100 淡入滑到静止位，
## 延迟封顶 — 45 行仅前若干行在视口内，其余拉开无意义；滚动回顶与焦点回第 0 行
## 在入场开始（首帧渲染前）复位 — 重进与首进一致，防按上次滚动位置滑入后跳顶突变；
## 全部完成后应用焦点并开放交互（焦点与入场 tween 串行防争抢）。
## 首进 _ready 与 _on_enter 双入口防重入；重进（自 RewardsScene 返回）重播入场。
## 等待用 process_always 计时器而非 tween.finished：场景 inert（process_mode DISABLED）
## 期间绑定 tween 暂停、finished 不发出会永久挂起 — 计时器不受场景暂停影响。
func _begin_entry() -> void:
	if _intro_running:
		return
	_intro_running = true
	_disabled = true
	_intro_gen += 1
	var my_gen: int = _intro_gen
	# 重进复位：滚动回顶部、焦点回第 0 行 — 与首进一致。必须在入场动画开始前
	# （首帧渲染前）复位；若在入场结束后复位，行会先按上次的滚动位置滑入再整体跳顶
	@warning_ignore("narrowing_conversion")
	_grid_scroll.scroll_vertical = 0.0
	_focus_idx = 0
	_refresh_translations()

	var last_delay: float = minf(float(_row_nodes.size() - 1), float(INTRO_STAGGER_CAP)) * INTRO_STAGGER
	var total_time: float = last_delay + OptionRow.INTRO_SLIDE_DURATION + 0.05
	for i: int in range(_row_nodes.size()):
		_intro_tweens.append(_row_nodes[i].play_intro(minf(float(i), float(INTRO_STAGGER_CAP)) * INTRO_STAGGER))
	await get_tree().create_timer(total_time, true).timeout
	if my_gen != _intro_gen:
		return

	_disabled = false
	_intro_running = false
	_update_focus()


# ===================================================================
# 焦点
# ===================================================================

func _update_focus(p_scroll: bool = false) -> void:
	if _row_nodes.is_empty():
		return
	if _focus_idx >= 0:
		_focus_idx = clampi(_focus_idx, 0, _row_nodes.size() - 1)

	for i: int in range(_row_nodes.size()):
		# 选中动画照主页/TabMenu：焦点行位移 -50（扫白随行左移），其余回 +10
		# （容器左侧 50px 边距保证位移不被裁切）
		# 双重选中：正在播放的行与焦点行可同时保持选中 — 播放期间该行始终被选中
		_row_nodes[i].apply_focus_state(i == _focus_idx or i == _playing_idx, OptionRow.ROW_FOCUS_X, OptionRow.ROW_REST_X)

	if p_scroll and _focus_idx >= 0:
		# 键盘焦点越界时容器直接滚动跟随（平常的滚动，无花哨动画）
		_grid_scroll.ensure_control_visible(_row_nodes[_focus_idx])


func _move_focus(delta: int) -> void:
	if _row_nodes.is_empty():
		return
	# 键盘/滚轮导航期间抑制悬停抢焦点，直到鼠标再次移动
	_await_mouse_motion = true
	if _focus_idx < 0:
		_focus_idx = 0
	else:
		_focus_idx = clampi(_focus_idx + delta, 0, _row_nodes.size() - 1)
	_update_focus(true)
	_play_click()
	get_viewport().set_input_as_handled()


func _on_row_hovered(idx: int) -> void:
	if _disabled or _await_mouse_motion or _focus_idx == idx:
		return
	_focus_idx = idx
	_update_focus()
	_play_click()


## 鼠标离开整个列表区域 — 清除焦点（正在播放的行由 _update_focus 双重选中逻辑保持选中样式）。
func _on_list_mouse_exited() -> void:
	if _disabled or _await_mouse_motion:
		return
	_focus_idx = -1
	_update_focus()


func _on_row_activated(idx: int) -> void:
	if _disabled:
		return
	# 单击即鼠标意图，恢复悬停焦点跟随
	_await_mouse_motion = false
	_focus_idx = idx
	_update_focus()
	_toggle_play(idx)


# ===================================================================
# 播放控制
# ===================================================================

func _toggle_play(index: int) -> void:
	if _disabled:
		return
	_play_click()

	var entry: Dictionary = _entries[index]

	if _playing_idx == index:
		# 停止当前预览 — 恢复菜单音频
		AudioManager.stop_bgm()
		AudioManager.set_menu_mode(true)
		if not _saved_bgm_path.is_empty():
			AudioManager.play_bgm(_saved_bgm_path, true)
			_saved_bgm_path = ""
		_set_playing(-1)
		return

	# 在替换之前保存当前 BGM（仅在第一次预览时）
	if _playing_idx < 0:
		_saved_bgm_path = AudioManager._current_bgm_path
	# 如果从另一首曲目切换，先停止前一首
	if _playing_idx >= 0:
		AudioManager.stop_bgm()

	# 进入预览模式 — 移除菜单低通滤镜，循环播放
	AudioManager.set_menu_mode(false)
	AudioManager.play_bgm(entry.file, true)
	_set_playing(index)


func _set_playing(index: int) -> void:
	_playing_idx = index

	# 行内 NOW PLAYING 指示 — 沿用 OptionRow 现有 refresh_text API（第二参数为空串时隐藏）
	for i: int in range(_row_nodes.size()):
		_row_nodes[i].refresh_text(_entries[i].title, NOW_PLAYING_TEXT if i == index else "")

	# 左侧曲名与简介（未播放时空白）
	if index >= 0 and index < _entries.size():
		var entry: Dictionary = _entries[index]
		_music_title.text = entry.title
		_music_desc.text = tr(entry.desc)
		@warning_ignore("static_called_on_instance")
		_music_desc.add_theme_font_override("font", GameManager.select_font(_music_desc.text, GameManager.font_zh_body, GameManager.font_en_body))
	else:
		_music_title.text = ""
		_music_desc.text = ""

	# 播放/停止/切换后刷新选中状态 — 正在播放的行始终被选中（双重选中）
	_update_focus()


# ===================================================================
# 返回按钮栏
# ===================================================================

func _setup_back_button() -> void:
	_back_bar = BackBar.attach(self)


# ===================================================================
# 输入 — 键盘与滚轮导航
# ===================================================================

func _input(event: InputEvent) -> void:
	# 鼠标移动即恢复悬停焦点跟随
	if event is InputEventMouseMotion:
		_await_mouse_motion = false
		return

	if _disabled or not event.is_pressed():
		return

	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			# 滚轮只滚动列表（原生 ScrollContainer 行为，本处不消费事件），不移动焦点；
			# 滚动引发的 mouse_entered 争抢由 _await_mouse_motion 抑制
			_await_mouse_motion = true
			return

	if event.is_action_pressed("ui_up") or event.is_action_pressed("ui_left"):
		_move_focus(-1)
	elif event.is_action_pressed("ui_down") or event.is_action_pressed("ui_right"):
		_move_focus(1)
	elif event.is_action_pressed("ui_accept"):
		if _focus_idx >= 0:
			_toggle_play(_focus_idx)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel"):
		_play_click()
		back_requested.emit()
		get_viewport().set_input_as_handled()


# ===================================================================
# 动画 / 音频 / 公共接口
# ===================================================================

func _animate_enter() -> void:
	@warning_ignore("static_called_on_instance")
	GameManager.animate_scene_enter(self)


func _play_click() -> void:
	AudioManager.play_click()


func set_disabled(val: bool) -> void:
	_disabled = val
