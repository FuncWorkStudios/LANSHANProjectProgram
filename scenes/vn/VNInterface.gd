## VNInterface : Control
## 核心视觉小说游戏场景 — 背景、角色、对话、打字机效果。
## 子场景（TabMenu、SaveMenu、ChoicesMenu、LoadingScreen）是独立的。
extends Control

# 剧情文本 — 在编译时从生成的 .gd 文件预加载。
# 源 .txt 文件位于 assets/plot/。运行 tempp/regen_stories.sh 同步。
const STORY_TEXTS: Dictionary = {
	"intro":    preload("res://scripts/story/Story_Intro.gd"),
	"chapter1": preload("res://scripts/story/Story_Chapter1.gd"),
	"chapter2": preload("res://scripts/story/Story_Chapter2.gd"),
	"chapter3": preload("res://scripts/story/Story_Chapter3.gd"),
	"chapter4": preload("res://scripts/story/Story_Chapter4.gd"),
}


signal back_requested()
signal scene_changed(new_scene: String)

# ---------------------------------------------------------------------------
# 状态
# ---------------------------------------------------------------------------
var _plot: PlotData = null
var _plot_id: String = ""
var _node_index: int = 0
var _current_node: PlotNode = null
var _visible_chars: int = 0
var _is_typing_finished: bool = false
var _is_menu_open: bool = false
var _is_tab_menu_open: bool = false
var _is_log_open: bool = false
var _is_skipping: bool = false
var _pending_save_slot: int = -1
var _player_name: String = ""
var _current_bg: String = ""
var _current_char: String = ""
var _settings: AppSettings

# 字体资源

# 区域设置辅助函数
func _is_zh() -> bool:
	return GameManager.is_locale("zh")


## 从存档作用域变量读取终端解锁状态，转为 TabMenu 所需字符串。
func _get_terminal_status() -> String:
	if _context and _context.get_var("terminal_unlocked"):
		return "unlocked"
	return "locked"


## 序章完结前 Tab 菜单仅允许 System 层级；完结后（tab_menu_unlocked=true）开放完整菜单。
func _is_tab_menu_full() -> bool:
	if _context and _context.get_var("tab_menu_unlocked"):
		return true
	return false


# 打字机 / 等待 / 自动播放计时器
var _typewriter_timer: float = 0.0
var _typewriter_interval: float = 0.045
var _auto_play_timer: float = 0.0
var _auto_play_delay: float = 2.0
var _wait_timer: float = 0.0
var _is_waiting: bool = false

# 预编译正则表达式 — 避免每个节点分配（优化）
var _em_marker_regex: RegEx
var _ann_marker_regex: RegEx

# 注释工具提示 — 悬停在 [url] 标签上时显示
var _annotation_tooltip: Label = null

# 预构建字体/样式资源 — 避免每个节点分配 Dictionary
var _font_dict: Dictionary = {}
var _dialogue_style_normal: StyleBoxFlat
var _dialogue_style_glitch: StyleBoxFlat
var _last_locale_was_zh: bool  # 跟踪区域设置变化以跳过冗余字体覆盖

# Tween 引用
var _exit_tree_called: bool = false

# 自动推进链 — 无需用户输入驱动章节过渡
var _is_auto_advancing: bool = false

# 跳过指示器 — 快进时显示在右上角
var _skip_indicator: Label = null

# 鼠标位置跟踪（传给 VNBackground 用于视差效果）
var _mouse_pos: Vector2 = Vector2.ZERO

# CTRL 键边缘检测用于切换跳过（_input 不触发时的后备方案）
var _ctrl_was_down: bool = false

# 子场景实例
var _save_menu: Control = null
var _choices_menu: Control = null
var _loading_screen: Control = null
var _tab_menu: TabMenu = null
var _log_screen: LogScreen = null

# 日志屏幕的对话历史
var _log_entries: Array[Dictionary] = []

# 选择反应系统 — 选择后，反应节点入队依次播放，播放完后执行目标
var _reaction_queue: Array[PlotNode] = []
var _pending_target: Dictionary = {}   # {type: "continue"|"jump"|"rechoose", plot_id, node_idx}

# V2 运行时变量上下文
var _context: ScriptContext = null

# V2 流程控制 — 连续执行控制节点时防止无限循环
const FLOW_SAFETY_LIMIT: int = 1000

# ---------------------------------------------------------------------------
# Onready — 核心 VN 节点
# ---------------------------------------------------------------------------
@onready var _vn_bg: VNBackground = %VNBackground
@onready var _char_rect: TextureRect = %CharacterRect
@onready var _dialogue_box: Panel = %DialogueBox
@onready var _dialogue_text: RichTextLabel = %DialogueText
@onready var _speaker_name_container: Control = %SpeakerNameContainer
@onready var _glitch_overlay: ColorRect = %GlitchOverlay
@onready var _controls_hint: Control = %ControlsHint
@warning_ignore("unused_private_class_variable")
@onready var _cinematic_top: ColorRect = %CinematicTop
@warning_ignore("unused_private_class_variable")
@onready var _cinematic_bottom: ColorRect = %CinematicBottom


# ===================================================================
# 设置与加载
# ===================================================================

func setup(initial_save: SaveData, player_name: String) -> void:
	_player_name = player_name
	_settings = GameManager.get_settings()

	# ── 重置所有会话级状态以确保干净的开始 ──
	_plot = null; _plot_id = ""; _node_index = 0; _current_node = null
	_visible_chars = 0; _is_typing_finished = false
	_is_menu_open = false; _is_tab_menu_open = false; _is_log_open = false
	_is_skipping = false; _pending_save_slot = -1
	_current_bg = ""; _current_char = ""
	_char_rect.texture = null; _char_rect.visible = true
	_speaker_name_container.clip_contents = true
	# 确保 RichTextLabel 能接收鼠标事件以触发 meta_clicked / meta_hover
	_dialogue_text.mouse_filter = Control.MOUSE_FILTER_PASS
	_char_rect.modulate.a = 1.0; _char_rect.position.x = 0.0
	_log_entries.clear()
	_reaction_queue.clear(); _pending_target.clear()
	_context = ScriptContext.new()
	GameManager.script_context = _context
	_context.persist_var_set = GameManager._on_persist_var_set
	_context.set_persist_vars(GameManager._persist_vars)
	_exit_tree_called = false; _ctrl_was_down = false
	_typewriter_timer = 0.0; _auto_play_timer = 0.0
	_wait_timer = 0.0; _is_waiting = false; _is_auto_advancing = false
	_last_speaker_name = ""

	# 加载字体资源

	# ── 预构建缓存资源（避免每个节点分配）──
	if not _em_marker_regex:
		# *text* → [i]text[/i]  (强调)
		_em_marker_regex = RegEx.new()
		_em_marker_regex.compile("\\*(.+?)\\*")
		# ==text（annotation）== 或 ==text(annotation)== （带工具提示的注释）
		_ann_marker_regex = RegEx.new()
		_ann_marker_regex.compile("==(.+?)[\\(（](.+?)[\\)）]==")
		# 连接对话 RichTextLabel 的工具提示信号
		if _dialogue_text:
			_dialogue_text.meta_hover_started.connect(_on_annotation_hover_started)
			_dialogue_text.meta_hover_ended.connect(_on_annotation_hover_ended)
			_dialogue_text.meta_clicked.connect(_on_annotation_hover_ended)  # dismiss on click
	_font_dict["tcm"] = GameManager.font_tcm
	_font_dict["en_body"] = GameManager.font_en_body
	_font_dict["zh_body"] = GameManager.font_zh_body
	_font_dict["zh_title"] = GameManager.font_zh_title
	_build_dialogue_styles()
	_setup_crt_overlay()

	# 实例化子场景
	_instantiate_sub_scenes()

	# 重置 VN 背景状态以进行新加载
	_current_bg = ""
	_last_speaker_name = ""
	_vn_bg.reset()

	if initial_save:
		_plot_id = initial_save.plot_id
		_node_index = initial_save.node_index
		GameManager.player_name = initial_save.player_name
		if not initial_save.variables.is_empty():
			_context.from_dict(initial_save.variables)
	else:
		_plot_id = "intro"
		_node_index = 0
		GameManager.player_name = player_name

	_load_plot()
	_hide_loading()
	_create_controls_hint()
	_create_skip_indicator()


func _instantiate_sub_scenes() -> void:
	# 已创建 — VNInterface 在会话之间被缓存和重用
	if _save_menu:
		return

	# 加载屏幕
	var ls_packed: PackedScene = load("res://scenes/vn/LoadingScreen.tscn") as PackedScene
	if ls_packed:
		_loading_screen = ls_packed.instantiate() as Control
		_loading_screen.name = "LoadingScreen"
		add_child(_loading_screen)

	# 选择菜单
	var cm_packed: PackedScene = load("res://scenes/vn/ChoicesMenu.tscn") as PackedScene
	if cm_packed:
		_choices_menu = cm_packed.instantiate() as Control
		_choices_menu.name = "ChoicesMenu"
		_choices_menu.visible = false
		_choices_menu.choice_selected.connect(_on_choice_selected)
		add_child(_choices_menu)

	# 存档菜单
	var sm_packed: PackedScene = load("res://scenes/vn/SaveMenu.tscn") as PackedScene
	if sm_packed:
		_save_menu = sm_packed.instantiate() as Control
		_save_menu.name = "SaveMenu"
		_save_menu.visible = false
		_save_menu.close_requested.connect(_on_save_menu_closed)
		_save_menu.save_selected.connect(_on_save_slot_selected)
		add_child(_save_menu)

	# Tab 菜单 — 从场景实例化，支持在其他场景中复用
	var tab_packed: PackedScene = load("res://scenes/tab_menu/TabMenu.tscn") as PackedScene
	if tab_packed:
		_tab_menu = tab_packed.instantiate() as TabMenu
		_tab_menu.name = "TabMenu"
		_tab_menu.visible = false
		_tab_menu.back_to_title.connect(_on_tab_back_to_title)
		_tab_menu.close_requested.connect(_on_tab_menu_closed)
		_tab_menu.open_settings.connect(_on_tab_open_settings)
		_tab_menu.open_map.connect(_on_tab_open_map)
		add_child(_tab_menu)

	# 日志屏幕 — 从 tscn 加载
	var log_packed: PackedScene = load("res://scenes/vn/LogScreen.tscn") as PackedScene
	if log_packed:
		_log_screen = log_packed.instantiate() as LogScreen
		_log_screen.name = "LogScreen"
		_log_screen.visible = false
		_log_screen.close_requested.connect(_on_log_closed)
		add_child(_log_screen)


func _load_plot() -> void:
	_show_loading()

	var text: String = ""

	# 主要方式：从预加载的 .gd 脚本加载剧情文本（已编译为字节码）。
# 这是最可靠的方法 — 在编辑器和导出构建中都能工作。
	var story_gd: RefCounted = STORY_TEXTS.get(_plot_id, null)
	if story_gd:
		text = story_gd.TEXT

	if text.is_empty():
		push_error("VNInterface: Could not load plot '", _plot_id, "'")
		_hide_loading()
		return

	var parser: ScriptParser = ScriptParser.new(_plot_id)
	_plot = parser.parse(text)
	# 防失误：STORY_TEXTS key 必须与脚本内 :: id 一致，否则 @jump 找错文件
	if _plot.id != "" and _plot.id != _plot_id:
		push_error("VNInterface: :: id mismatch — STORY_TEXTS key '", _plot_id,
			"' vs parsed '", _plot.id, "'. Fix Story_*.gd or STORY_TEXTS.")

	if _plot.nodes.is_empty():
		push_error("VNInterface: Plot '", _plot_id, "' parsed with zero nodes")
		_hide_loading()
		return

	_node_index = clampi(_node_index, 0, max(0, _plot.nodes.size() - 1))
	_set_current_node(_node_index)
	_hide_loading()

## 当剧情加载失败时显示用户可见的错误弹窗（在导出构建中至关重要）。
func _show_load_error(message: String) -> void:
	var popup: AcceptDialog = AcceptDialog.new()
	popup.name = "LoadErrorDialog"
	popup.title = tr("剧情加载失败")
	popup.dialog_text = message
	popup.size = Vector2(480, 200)
	popup.exclusive = true
	popup.always_on_top = true
	popup.confirmed.connect(popup.queue_free)
	popup.canceled.connect(popup.queue_free)
	add_child(popup)
	popup.popup_centered()


# ===================================================================
# 节点导航
# ===================================================================

func _set_current_node(idx: int) -> void:
	if not _plot or idx < 0 or idx >= _plot.nodes.size():
		return
	_node_index = idx
	_current_node = _plot.nodes[idx]
	_visible_chars = 0
	_is_typing_finished = false
	_is_waiting = false
	_wait_timer = 0.0
	_auto_play_timer = 0.0
	_apply_node_effects()
	_refresh_controls_hint()

	# 立即记录对话（不仅仅在推进时）
	if _current_node.type == "text" and not (_current_node.ZH.is_empty() and _current_node.EN.is_empty()):
		_log_entries.append({
			"who": _current_node.who,
			"zh": _current_node.ZH,
			"en": _current_node.EN,
		})

	# 自动推进纯过渡节点（stop / black / jump 链）
	if not _exit_tree_called:
		_check_auto_advance()


# ===================================================================
# 节点效果
# ===================================================================

func _apply_node_effects() -> void:
	if not _current_node:
		return

	_apply_background()
	_apply_character()
	_apply_audio_effects()
	_apply_terminal_and_scene()
	_apply_glitch()
	_apply_wait()
	_apply_stop_transition()
	_apply_fade_black()

	_update_dialogue_display()


func _apply_background() -> void:
	# 仅对齐变更（@bg up / @bg down）
	if _current_node.bg.is_empty():
		if not _current_node.bg_align.is_empty():
			_vn_bg.set_align(_current_node.bg_align)
		return
	_set_background(_current_node.bg, _current_node.bg_align)


func _apply_character() -> void:
	if _current_node.ch == "__CLEAR__":
		_set_character("")
	elif not _current_node.ch.is_empty():
		_set_character(_current_node.ch)
	elif not _current_node.who.is_empty():
		var char_path: String = _resolve_character_path(_current_node.who)
		if not char_path.is_empty():
			_set_character(char_path)


func _apply_audio_effects() -> void:
	# --- BGM（通过 VNAudioService — 支持交叉淡入淡出）---
	if _current_node.bgm:
		var bgm_cmd: AudioCommand = _current_node.bgm
		if bgm_cmd.stop:
			if bgm_cmd.fade_out_only:
				VNAudioService.fade_out_bgm(bgm_cmd.fade_out_duration)
			else:
				# 旧版 stopmusic / stopall — 立即停止
				VNAudioService.stop_bgm()
		elif not bgm_cmd.play.is_empty():
			if bgm_cmd.crossfade:
				VNAudioService.crossfade_bgm(bgm_cmd.play, bgm_cmd.fade_out_duration, bgm_cmd.fade_in_duration)
			else:
				VNAudioService.play_bgm(bgm_cmd.play, bgm_cmd.loop)

		# --- SFX（短一次性音效，通过 AudioManager）---
		if _current_node.sfx_short:
			if _current_node.sfx_short.stop:
				AudioManager.stop_sfx()
			elif not _current_node.sfx_short.play.is_empty():
				AudioManager.play_sfx(_current_node.sfx_short.play)

	# --- 环境音效（通过 VNAudioService）---
	if _current_node.ambience:
		var amb_cmd: AudioCommand = _current_node.ambience
		if amb_cmd.stop:
			VNAudioService.clear_all_ambience(1.0)
		elif not amb_cmd.play.is_empty():
			VNAudioService.set_ambience_layer(0, amb_cmd.play, amb_cmd.ambience_volume)

	# --- 旧版音频字段 ---
	if not _current_node.audio:
		return
	if _current_node.audio.stop:
		if _current_node.audio.audio_type == "bgm" or _current_node.audio.audio_type.is_empty():
			VNAudioService.stop_bgm()
		elif _current_node.audio.audio_type == "ambience":
			VNAudioService.clear_all_ambience(0.5)
	elif not _current_node.audio.play.is_empty():
		match _current_node.audio.audio_type:
			"bgm":
				VNAudioService.play_bgm(_current_node.audio.play, _current_node.audio.loop)
			"sfx":
				AudioManager.play_sfx(_current_node.audio.play)
			"ambience":
				VNAudioService.set_ambience_layer(0, _current_node.audio.play, 0.5)


func _apply_terminal_and_scene() -> void:

	if _current_node.type == "scene" and not _current_node.next_scene.is_empty():
		scene_changed.emit(_current_node.next_scene)


func _apply_glitch() -> void:
	if _current_node.glitch and _settings.shader_quality == "high":
		_apply_glitch_effect(true)
	else:
		_apply_glitch_effect(false)


func _apply_wait() -> void:
	if _current_node.wait_time > 0.0:
		_is_waiting = true
		_wait_timer = 0.0
		_dialogue_text.visible_characters = 0


func _apply_fade_black() -> void:
	if _current_node.fade_black > 0.0:
		_vn_bg.fade_to_black(_current_node.fade_black)


func _apply_stop_transition() -> void:
	# stop 过渡：显式隐藏。其余情况由 _update_dialogue_display 根据文本有无决定。
	if _current_node.stop_transition:
		_dialogue_box.visible = false
		_speaker_name_container.visible = false


# ===================================================================
# 角色与背景
# ===================================================================

## 将角色名称解析为精灵路径。
## 首先检查剧情的角色字典，然后检查内置映射，
## 最后尝试使用 AssetResolver 解析裸文件名。
## 当没有可用精灵时返回 ""（角色优雅地隐藏）。
func _resolve_character_path(who: String) -> String:
	# 不可显示的说话者 — 旁白、未知、系统
	var non_display: Array[String] = ["???", "旁白", "narrator", "Narrator", "系统", "system", "none"]
	if who in non_display:
		return ""

	# 内置角色 → 默认精灵映射（PascalCase 目录名）
	var mapping: Dictionary = {
		"林子欣": "res://assets/characters/LinZixin/LinZixin_normal.webp",
		"LinZixin": "res://assets/characters/LinZixin/LinZixin_normal.webp",
		"江诗轩": "res://assets/characters/JiangShixuan/JiangShixuan_normal.webp",
		"JiangShixuan": "res://assets/characters/JiangShixuan/JiangShixuan_normal.webp",
		"石晴雯": "res://assets/characters/ShiQingwen/ShiQingwen_normal.webp",
		"ShiQingwen": "res://assets/characters/ShiQingwen/ShiQingwen_normal.webp",
		"漆诚": "res://assets/characters/QiCheng/QiCheng_normal.webp",
		"QiCheng": "res://assets/characters/QiCheng/QiCheng_normal.webp",
		"何肖": "res://assets/characters/HeXiao/HeXiao_normal.webp",
		"HeXiao": "res://assets/characters/HeXiao/HeXiao_normal.webp",
		"肖逸言": "res://assets/characters/XiaoYiyan/XiaoYiyan_normal.webp",
		"XiaoYiyan": "res://assets/characters/XiaoYiyan/XiaoYiyan_normal.webp",
	}

	# 1. 剧情级角色字典优先
	if _plot and _plot.characters.has(who):
		var plot_path: String = _plot.characters[who]
		if not plot_path.is_empty():
			return _normalize_asset_path(plot_path)

	# 2. 内置映射
	if mapping.has(who):
		var mapped: String = mapping[who]
		if ResourceLoader.exists(mapped):
			return mapped

	# 3. 使用原始名称尝试 AssetResolver（处理裸文件名）
	if not "/" in who and not who.begins_with("res://"):
		var resolved: String = AssetResolver.resolve_ch(who)
		if resolved != who and ResourceLoader.exists(resolved):
			return resolved

	# 4. 未找到角色精灵 — 优雅降级
	return ""


func _set_background(path: String, align: String = "") -> void:
	var normalized: String = _normalize_asset_path(path)
	if _current_bg == normalized and align == "" and not normalized.is_empty():
		return
	_current_bg = normalized
	_vn_bg.set_bg(normalized, align)
	if not normalized.is_empty():
		_vn_bg.fade_from_black(1.0)
	EventBus.background_changed.emit(normalized)


func _set_character(path: String) -> void:
	var normalized: String = _normalize_asset_path(path)

	# 相同角色，相同姿势 — 跳过动画以避免闪烁
	if _current_char == normalized:
		return

	_current_char = normalized

	if normalized.is_empty():
		_clear_character_sprite()
		return

	var texture: Texture2D = _load_texture(normalized)
	if texture:
		_char_rect.texture = texture
		_char_rect.modulate.a = 0.0
		_char_rect.position.x = -60.0
		var tween := create_tween()
		tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_EXPO)
		tween.set_parallel(true)
		tween.tween_property(_char_rect, "modulate:a", 1.0, 0.8)
		tween.tween_property(_char_rect, "position:x", 0.0, 0.8)
	EventBus.character_changed.emit(normalized)


func _clear_character_sprite() -> void:
	var tween := create_tween()
	tween.tween_property(_char_rect, "modulate:a", 0.0, 0.5)
	tween.tween_callback(_on_character_cleared)


func _on_character_cleared() -> void:
	_char_rect.texture = null


# ===================================================================
# 资源路径规范化与加载
# ===================================================================

func _normalize_asset_path(path: String) -> String:
	if path.is_empty(): return path
	var normalized: String = AssetResolver.normalize_web_path(path)
	if normalized.begins_with("res://"): return normalized
	# 裸文件名或相对路径 — 尝试 AssetResolver
	if not "/" in normalized or not normalized.begins_with("/"):
		var resolved: String = AssetResolver.resolve_any(normalized)
		if resolved != normalized and ResourceLoader.exists(resolved):
			return resolved
	return normalized


func _load_texture(path: String) -> Texture2D:
	var normalized: String = _normalize_asset_path(path)
	if normalized.is_empty() or not ResourceLoader.exists(normalized):
		# 后备方案：尝试角色精灵的裸名称解析
		if not "/" in path and not path.begins_with("res://"):
			normalized = AssetResolver.resolve_ch(path)
	if normalized.is_empty() or not ResourceLoader.exists(normalized):
		return null
	return load(normalized)


# ===================================================================
# 对话显示
# ===================================================================

func _update_dialogue_display() -> void:
	if not _current_node:
		return

	var localized_text: String = _get_localized_text()
	# 应用强调和注释 BBCode 转换
	localized_text = _apply_text_styling(localized_text)
	# 字体后备：当主要对话字体仅支持拉丁字符时（EN 模式），将 CJK 字符用 zh_body 字体包裹。
	# CJK 字体已经覆盖了拉丁字符。
	if not _is_zh():
		localized_text = GameManager.wrap_font_fallback(localized_text, GameManager.FONT_EN_BODY, GameManager.FONT_ZH_BODY)
	_dialogue_text.text = localized_text
	_dialogue_text.visible_characters = _visible_chars

	# 对话字体 — 设置一次，仅在区域设置变化时更新
	var is_zh_now: bool = _is_zh()
	if _last_locale_was_zh != is_zh_now:
		_last_locale_was_zh = is_zh_now
		var body_font_size: int = 24
		if not is_zh_now and GameManager.font_en_body:
			_dialogue_text.add_theme_font_override("normal_font", GameManager.font_en_body)
			body_font_size = 22
		elif GameManager.font_zh_body:
			_dialogue_text.add_theme_font_override("normal_font", GameManager.font_zh_body)
			body_font_size = 26
		_dialogue_text.add_theme_font_size_override("normal_font_size", body_font_size)
		if GameManager.font_zh_emphasis:
			_dialogue_text.add_theme_font_override("italics_font", GameManager.font_zh_emphasis)
			_dialogue_text.add_theme_font_size_override("italics_font_size", body_font_size)
		if GameManager.font_en_emphasis:
			_dialogue_text.add_theme_font_override("bold_italics_font", GameManager.font_en_emphasis)

	# 文本颜色（glitch 不常切换 — 每个节点设置成本低）
	if _current_node.glitch:
		_dialogue_text.add_theme_color_override("default_color", Color(1, 0.3, 0.3, 1))
	else:
		_dialogue_text.add_theme_color_override("default_color", Color.BLACK)

	# 对话框样式
	_apply_dialogue_box_style(_current_node.glitch)

	# 说话者名称
	var who: String = _current_node.who
	if who.is_empty() or who in ["???", "旁白", "Narrator", "narrator", "system", "system_text", "none"]:
		_speaker_name_container.visible = false
	else:
		var speaker_name: String = who
		if who == "player" or who == "我":
			speaker_name = _player_name
		elif _plot:
			speaker_name = _plot.get_character_name(who, TranslationServer.get_locale())
		if speaker_name.is_empty():
			_speaker_name_container.visible = false
		else:
			_speaker_name_container.visible = true
			_build_speaker_name(speaker_name)
			var box_top: float = _dialogue_box.global_position.y
			_speaker_name_container.position.y = box_top - 64.0




	# 对话框和姓名框只在有文本或等待时显示
	var has_text: bool = not _get_localized_text().is_empty()
	if has_text or _is_waiting:
		_dialogue_box.visible = true
		_dialogue_box.modulate.a = 1.0
	else:
		_dialogue_box.visible = false
		_speaker_name_container.visible = false


	# 显示/隐藏选项
	if _current_node.type == "select" and _choices_menu:
		_choices_menu.show_options(_current_node.options, _font_dict)
	else:
		if _choices_menu:
			_choices_menu.hide_options()

	# 打字机速度
	var speed_map: Dictionary = {"slow": 0.080, "normal": 0.045, "fast": 0.020}
	var lang_mult: float = 0.65 if not _is_zh() else 1.0
	_typewriter_interval = speed_map.get(_settings.text_speed, 0.045) * lang_mult
	if _current_node.glitch:
		_typewriter_interval = 0.020


var _name_hbox: HBoxContainer = null
var _last_speaker_name: String = ""

func _build_speaker_name(name_text: String) -> void:
	# 仅在名称实际改变时重建
	if name_text == _last_speaker_name:
		return
	_last_speaker_name = name_text

	# 延迟创建 HBox 一次
	if not _name_hbox:
		_name_hbox = HBoxContainer.new()
		_name_hbox.name = "NameHBox"
		_name_hbox.alignment = BoxContainer.ALIGNMENT_END
		_name_hbox.add_theme_constant_override("separation", 0)
		_name_hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_name_hbox.position = Vector2(20, 0)
		_speaker_name_container.add_child(_name_hbox)
		_name_hbox.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

	# 清除并重建字符标签
	# 先 remove_child 再 queue_free 避免新旧子节点共存导致换行
	for c in _name_hbox.get_children():
		_name_hbox.remove_child(c)
		c.queue_free()

	var is_zh: bool = _is_zh()
	var primary_font: Font = GameManager.font_tcm if not is_zh and GameManager.font_tcm else GameManager.font_zh_title
	var fallback_font: Font = GameManager.font_zh_title
	var sizes: Array[int] = [28, 24, 22, 24]

	for i: int in range(name_text.length()):
		var ch: String = name_text[i]
		var lbl: Label = Label.new()
		lbl.text = ch
		lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		lbl.size_flags_vertical = Control.SIZE_SHRINK_END
		var fs: int = sizes[i % sizes.size()]
		lbl.add_theme_font_size_override("font_size", fs)
		lbl.add_theme_color_override("font_color", Color.WHITE)
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# Per-character font fallback: CJK chars need a CJK font
		@warning_ignore("static_called_on_instance")
		if GameManager._is_cjk(ch) and fallback_font:
			lbl.add_theme_font_override("font", fallback_font)
		elif primary_font:
			lbl.add_theme_font_override("font", primary_font)
		_name_hbox.add_child(lbl)


## 将强调/注释标记转换为 BBCode。
##
## 支持的格式（彼此兼容）：
##   *text*                   → [i]text[/i]  (斜体，simfang / timesi)
##   ==text(annotation)==     → [url=annotation]text[/url]  (下划线 + 工具提示)
##   ==text（annotation）==   → 相同（全角括号）
##
func _apply_text_styling(text: String) -> String:
	if text.is_empty():
		return text

	var result: String = text

	# 1. *text* → [i]text[/i]  (markdown 风格强调)
	if _em_marker_regex:
		result = _em_marker_regex.sub(result, "[i]$1[/i]", true)

	# 2. ==text（annotation）== 或 ==text(annotation)== → [url=annotation]text[/url]
	if _ann_marker_regex:
		result = _ann_marker_regex.sub(result, "[url=$2]$1[/url]", true)


	return result


## 剥离所有 BBCode 标签，返回纯文本用于存档台词预览。
func _strip_bbcode(text: String) -> String:
	if text.is_empty():
		return text
	var result: String = text
	# 去掉 [tag=...]...[/tag] 和 [tag]...[/tag] 标签，保留内部文本
	var bbcode_re := RegEx.new()
	bbcode_re.compile("\\[/?[^\\]]*\\]")
	result = bbcode_re.sub(result, "", true)
	return result


func _apply_dialogue_box_style(glitch: bool) -> void:
	# 交换预构建样式而不是每个节点分配新的 StyleBoxFlat
	_dialogue_box.add_theme_stylebox_override("panel", _dialogue_style_glitch if glitch else _dialogue_style_normal)


## 预构建两种对话框 StyleBoxFlat 变体（普通 / glitch）。
func _build_dialogue_styles() -> void:
	_dialogue_style_normal = _make_dialogue_style(Color.WHITE, Color(0, 0, 0, 0.1))
	_dialogue_style_glitch = _make_dialogue_style(Color(0.102, 0, 0, 1), Color(1, 0, 0, 1))


func _make_dialogue_style(bg: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.border_width_bottom = 8
	style.shadow_size = 30
	style.shadow_offset = Vector2(0, 24)
	style.shadow_color = Color(0, 0, 0, 0.35)
	style.corner_radius_top_left = 2
	style.corner_radius_top_right = 2
	return style


func _get_localized_text() -> String:
	if not _current_node: return ""
	var text: String
	if _is_zh():
		text = _current_node.ZH
	elif not _current_node.EN.is_empty():
		text = _current_node.EN
	else:
		text = tr(_current_node.ZH)  # 从 .po 获取翻译
	return text.replace("{player}", _player_name)


# ===================================================================
# CRT 复古显示器效果（替代旧的红色 glitch 覆盖层）
# ===================================================================

## 每次会话加载一次 CRT 着色器并分配给 GlitchOverlay。
## 覆盖层覆盖整个视口并采样 SCREEN_TEXTURE，
## 以应用曲率、扫描线、色差和 VHS 噪点效果。
func _setup_crt_overlay() -> void:
	if not _glitch_overlay:
		return

	# 已设置 — 着色器材质在会话之间持久化
	if _glitch_overlay.material and _glitch_overlay.material is ShaderMaterial:
		return

	var shader: Shader = load("res://shaders/crt_effect.gdshader") as Shader
	if not shader:
		push_warning("VNInterface: failed to load CRT shader")
		return

	var mat := ShaderMaterial.new()
	mat.shader = shader
	_glitch_overlay.material = mat

	# 确保覆盖层渲染在所有内容之上
	_glitch_overlay.z_index = 10
	_glitch_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE


## 启用/禁用全屏 CRT 后处理着色器。
## GlitchOverlay ColorRect 采样 SCREEN_TEXTURE 并应用
## 曲率、扫描线、色差和 VHS 噪点效果。
func _apply_glitch_effect(enable: bool) -> void:
	if not enable:
		_glitch_overlay.visible = false
		_apply_dialogue_box_style(false)
		return

	if _settings.shader_quality == "high":
		_glitch_overlay.visible = true
	else:
		_glitch_overlay.visible = false
	_apply_dialogue_box_style(true)


# ===================================================================
# 粘性资源（Sticky assets）
# ===================================================================

func _resolve_sticky_assets() -> void:
	if not _plot or _plot.nodes.is_empty(): return
	var start_idx: int = mini(_node_index, _plot.nodes.size() - 1)

	for i: int in range(start_idx, -1, -1):
		var bg: String = _plot.nodes[i].bg
		if not bg.is_empty():
			var normalized: String = _normalize_asset_path(bg)
			if _current_bg != normalized:
				_current_bg = normalized
				var texture: Texture2D = _load_texture(normalized)
				if texture: _vn_bg.set_bg(normalized)
			break

	for i: int in range(start_idx, -1, -1):
		var ch: String = _plot.nodes[i].ch
		if not ch.is_empty():
			if ch == "__CLEAR__": _set_character("")
			elif _current_char != ch: _set_character(ch)
			break

	for i: int in range(start_idx, -1, -1):
		var bgm: AudioCommand = _plot.nodes[i].bgm
		if bgm and not bgm.play.is_empty():
			VNAudioService.play_bgm(bgm.play, bgm.loop)
			break

	for i: int in range(start_idx, -1, -1):
		var amb: AudioCommand = _plot.nodes[i].ambience
		if amb:
			if amb.stop:
				break  # @stopaudio — 不恢复 ambience
			if not amb.play.is_empty():
				VNAudioService.set_ambience_layer(0, amb.play, amb.ambience_volume)
				break




# ===================================================================
# 推进 / 进度
# ===================================================================

func _advance() -> void:
	# 如果在反应队列中，先处理完反应节点
	if not _reaction_queue.is_empty():
		if not _is_typing_finished:
			_visible_chars = _get_localized_text().length()
			_dialogue_text.visible_characters = _visible_chars
			_is_typing_finished = true
			return
		_process_reaction_queue()
		return

	if not _plot or not _current_node: return

	# V2 流程控制 — 连续执行 label/goto/set/if/else/endif 节点
	if _execute_flow_control():
		return

	if not _is_typing_finished and not _is_waiting:
		_visible_chars = _get_localized_text().length()
		_dialogue_text.visible_characters = _visible_chars
		_is_typing_finished = true
		return

	if _is_waiting:
		_is_waiting = false
		_wait_timer = 0.0
		# 手动点击直接跳过等待，前进到下一个节点
		if _node_index < _plot.nodes.size() - 1:
			_set_current_node(_node_index + 1)
			_resolve_sticky_assets()
			_skip_plain_scenes()
		return

	if _current_node.type == "select":
		_is_skipping = false
		return

	_play_click()

	# 如果此节点触发返回标题
	if _current_node.back_to_title:
		back_requested.emit()
		return

	# 如果此节点有跳转目标，自动跳转到另一个剧情
	# 委托给电影式章节过渡协程
	if not _current_node.jump_plot_id.is_empty():
		_execute_chapter_transition()
		return

	# 重新选择 — 回退到最近的选择
	if _current_node.rechoose:
		_do_rechoose()
		return

	if _node_index < _plot.nodes.size() - 1:
		var next_idx: int = _node_index + 1
		_set_current_node(next_idx)
		_resolve_sticky_assets()
		# 跳过纯场景节点（@bg, @bgm, @chapter 等），直到遇到文本或特殊过渡节点
		_skip_plain_scenes()
		var title: String = _get_node_chapter()
		GameManager.set_auto_save(_plot_id, _node_index, _player_name, title, _strip_bbcode(_apply_text_styling(_get_localized_text())).substr(0, 50), _context.to_dict())
	else:
		_is_skipping = false
		VNAudioService.clear_all_ambience(0.5)
		back_requested.emit()


## V2 流程控制 — while 循环连续执行无 UI 的控制节点
## （label / goto / set / if / else / endif），
## 直到遇到需要用户交互的节点（text / select / scene）。
## 返回 true 表示已处理并推进，调用者应 return。
func _execute_flow_control() -> bool:
	if not _current_node:
		return false

	var safety: int = 0
	var did_execute: bool = false

	while safety < FLOW_SAFETY_LIMIT:
		if not _current_node:
			break

		var handled: bool = true

		match _current_node.type:
			"label":
				if _node_index < _plot.nodes.size() - 1:
					_node_index += 1
					_set_current_node(_node_index)
					_resolve_sticky_assets()
				else:
					break

			"goto":
				var target: int = _current_node.jump_to
				if target >= 0 and target < _plot.nodes.size():
					_node_index = target
					_set_current_node(_node_index)
					_resolve_sticky_assets()
				else:
					push_warning("VNInterface: @goto '", _current_node.goto_label, "' resolved to invalid index ", target)
					break

			"set":
				if not _current_node.expression.is_empty():
					_context.apply_expression(_current_node.expression, false)
				if _node_index < _plot.nodes.size() - 1:
					_node_index += 1
					_set_current_node(_node_index)
					_resolve_sticky_assets()
				else:
					break

			"persist":
				if not _current_node.expression.is_empty():
					_context.apply_expression(_current_node.expression, true)
				if _node_index < _plot.nodes.size() - 1:
					_node_index += 1
					_set_current_node(_node_index)
					_resolve_sticky_assets()
				else:
					break

			"if":
				var cond_result: Variant = ScriptExpression.evaluate(_current_node.expression, _context)
				if cond_result:
					# true → 继续下一个节点（then 分支）
					if _node_index < _plot.nodes.size() - 1:
						_node_index += 1
						_set_current_node(_node_index)
						_resolve_sticky_assets()
					else:
						break
				else:
					# false → 跳到 jump_to
					var target_idx: int = _current_node.jump_to
					if target_idx >= 0 and target_idx < _plot.nodes.size():
						_node_index = target_idx
						_set_current_node(_node_index)
						_resolve_sticky_assets()
					else:
						push_warning("VNInterface: @if jump_to=", target_idx, " out of range")
						break

			"else":
				# 从 true 分支顺序到达 → 跳过 else 体
				var target_idx: int = _current_node.jump_to
				if target_idx >= 0 and target_idx < _plot.nodes.size():
					_node_index = target_idx
					_set_current_node(_node_index)
					_resolve_sticky_assets()
				else:
					break

			"endif":
				# 无操作，继续
				if _node_index < _plot.nodes.size() - 1:
					_node_index += 1
					_set_current_node(_node_index)
					_resolve_sticky_assets()
				else:
					break

			_:
				handled = false

		if not handled:
			break

		did_execute = true
		safety += 1

	if safety >= FLOW_SAFETY_LIMIT:
		push_error("VNInterface: flow control loop exceeded safety limit (", FLOW_SAFETY_LIMIT, ")")

	return did_execute


## 跳过连续的纯场景节点（@bg, @bgm, @chapter 等无文本、无特殊效果的节点），
## 直到遇到有文本的节点或特殊过渡节点（stop/black/jump）。
func _skip_plain_scenes() -> void:
	if _is_auto_advancing: return
	var safety: int = 0
	while _current_node and _get_localized_text().is_empty() and _current_node.type != "select" and safety < 100:
		# 特殊节点——不跳过
		if _current_node.stop_transition or _current_node.fade_black > 0.0 or not _current_node.jump_plot_id.is_empty() or _current_node.wait_time > 0.0:
			return
		if _current_node.back_to_title or _current_node.rechoose:
			return
		# V2 流程控制节点 — 不跳过
		if _current_node.type in ["label", "goto", "set", "persist", "if", "else", "endif"]:
			return
		# 纯场景节点——直接跳过
		if _node_index < _plot.nodes.size() - 1:
			_node_index += 1
			_set_current_node(_node_index)
			safety += 1
		else:
			break


func _get_node_chapter() -> String:
	if not _plot: return ""
	if _is_zh(): return _plot.title.ZH
	if not _plot.title.EN.is_empty(): return _plot.title.EN
	return tr(_plot.title.ZH)


# ===================================================================
# 选项（委托给 ChoicesMenu）
# ===================================================================

func _on_choice_selected(choice_index: int) -> void:
	if not _current_node or _current_node.type != "select": return
	if choice_index < 0 or choice_index >= _current_node.options.size(): return

	var opt: PlotOption = _current_node.options[choice_index]
	_play_click()
	_choices_menu.hide_options()

	# V2: 执行选项附带的变量变更表达式
	for action: String in opt.actions:
		if not action.is_empty():
			_context.apply_expression(action)

	# 将反应节点入队（不修改 _plot.nodes）
	_reaction_queue = opt.reaction_nodes.duplicate()

	# 确定最终目标
	if opt.rechoose:
		_pending_target = {"type": "rechoose"}
	elif not opt.target_plot_id.is_empty():
		_pending_target = {"type": "jump", "plot_id": opt.target_plot_id, "node_idx": opt.target_node_index}
	else:
		_pending_target = {"type": "continue"}

	# 立即开始处理反应队列
	_process_reaction_queue()


## 逐条播放反应队列中的节点，全部处理完后自动执行最终目标。
func _process_reaction_queue() -> void:
	while not _reaction_queue.is_empty():
		var node: PlotNode = _reaction_queue.pop_front()
		_apply_reaction_node(node)
	_execute_pending_target()


func _apply_reaction_node(node: PlotNode) -> void:
	# 复用现有的节点效果系统 — 临时替换 _current_node 后调用标准流程
	_visible_chars = 0
	_is_typing_finished = false
	var saved_node: PlotNode = _current_node
	_current_node = node
	_apply_node_effects()
	_current_node = saved_node
	_dialogue_box.visible = true
	_dialogue_box.modulate.a = 1.0
	# 反应文本立即全部显示，无需额外点击
	var rtext: String = _get_localized_text()
	if not rtext.is_empty():
		_visible_chars = rtext.length()
		_dialogue_text.visible_characters = _visible_chars
		_is_typing_finished = true
	_log_entries.append({"who": node.who, "zh": node.ZH, "en": node.EN})


func _execute_pending_target() -> void:
	var target: Dictionary = _pending_target
	_pending_target = {}

	match target.get("type", "continue"):
		"rechoose":
			_do_rechoose()
		"jump":
			_plot_id = target["plot_id"]
			_node_index = target["node_idx"] if target["node_idx"] >= 0 else 0
			_load_plot()
			_resolve_sticky_assets()
		"continue", _:
			if _plot and _node_index < _plot.nodes.size() - 1:
				_set_current_node(_node_index + 1)
				_resolve_sticky_assets()

	# 选择后跳过等待、打完字机、跨过纯场景节点，确保新文本立即可见
	if _is_waiting:
		_is_waiting = false
		_wait_timer = 0.0
	var ntext: String = _get_localized_text()
	if ntext.is_empty():
		_skip_plain_scenes()
		ntext = _get_localized_text()
	if not ntext.is_empty():
		_visible_chars = ntext.length()
		_dialogue_text.visible_characters = _visible_chars
		_is_typing_finished = true

func _do_rechoose() -> void:
	if not _plot: return
	for i: int in range(_node_index - 1, -1, -1):
		if _plot.nodes[i].type == "select":
			_set_current_node(i)
			_resolve_sticky_assets()
			return

	push_warning("VNInterface: _do_rechoose — no select node found")
	if _node_index < _plot.nodes.size() - 1:
		_set_current_node(_node_index + 1)

# ===================================================================
# 存档菜单（委托给 SaveMenu）
# ===================================================================

func _toggle_save_menu() -> void:
	if not _save_menu: return
	_is_menu_open = not _is_menu_open
	if _is_menu_open:
		_save_menu.open(_font_dict, TranslationServer.get_locale())
		GameManager.set_overlay_mode(true)
	else:
		_save_menu.close_animated()
		GameManager.set_overlay_mode(false)


func _on_save_menu_closed() -> void:
	_is_menu_open = false
	_save_menu.visible = false
	GameManager.set_overlay_mode(false)


func _on_save_slot_selected(index: int) -> void:
	if not _plot or not _current_node: return

	var existing: SaveData = GameManager.load_game(index)
	if existing:
		_pending_save_slot = index
		_show_overwrite_modal()
		return

	_do_save_slot(index)
	# 就地刷新卡片，使新存档立即显示
	if _save_menu:
		_save_menu._refresh()


func _do_save_slot(index: int) -> void:
	var title: String = _get_node_chapter()
	var desc: String = _strip_bbcode(_apply_text_styling(_get_localized_text()))
	# 添加说话者名称作为上下文，例如 "林子欣：你好啊"
	if not _current_node.who.is_empty() and _current_node.who != "player" and _current_node.who != "我":
		desc = _current_node.who + "：" + desc
	GameManager.save_game(index, _plot_id, _node_index, _player_name, title, desc, _context.to_dict())


# ===================================================================
# 覆盖确认
# ===================================================================

func _show_overwrite_modal() -> void:
	# 防止堆叠 — 同一时间只显示一个覆盖模态框
	if _has_active_overwrite_modal():
		return
	# 将存档菜单隐藏在模态框后面，使其 _input() / gui_input
	# 不会从确认对话框中窃取键盘或鼠标事件。
	if _save_menu:
		_save_menu.visible = false

	var modal_script: GDScript = load("res://scenes/modals/OverwriteConfirm.gd")
	if not modal_script:
		push_error("VNInterface: Failed to load OverwriteConfirm.gd")
		return
	var modal: Control = modal_script.new()
	modal.name = "OverwriteConfirmInstance"
	modal.set_anchors_preset(Control.PRESET_FULL_RECT)
	modal.confirmed.connect(_on_overwrite_confirmed)
	modal.cancelled.connect(_on_overwrite_cancelled)
	add_child(modal)


func _on_overwrite_confirmed() -> void:
	if _pending_save_slot >= 0 and _plot and _current_node:
		_do_save_slot(_pending_save_slot)
	_remove_overwrite_modal()
	_pending_save_slot = -1
	# 重新显示存档菜单并刷新卡片
	if _save_menu:
		_save_menu.visible = true
		_save_menu._refresh()


func _on_overwrite_cancelled() -> void:
	_remove_overwrite_modal()
	_pending_save_slot = -1
	# 重新显示存档菜单
	if _save_menu:
		_save_menu.visible = true


func _remove_overwrite_modal() -> void:
	for child: Node in get_children():
		if child.name == "OverwriteConfirmInstance":
			child.queue_free()


func _has_active_overwrite_modal() -> bool:
	for child: Node in get_children():
		if child.name == "OverwriteConfirmInstance":
			return true
	return false


# ===================================================================
# Tab 菜单（委托给 TabMenu）
# ===================================================================

func _toggle_tab_menu() -> void:
	if not _tab_menu: return
	_is_tab_menu_open = not _is_tab_menu_open
	if _is_tab_menu_open:
		GameManager.set_overlay_mode(true)
		_tab_menu.open(_get_terminal_status(), _is_tab_menu_full(), _current_bg)
	else:
		GameManager.set_overlay_mode(false)
		_tab_menu.close()


## 当从通过 tab 菜单打开的设置返回时，由 SceneManager 调用 — 无条件重新打开 tab 菜单。
func _open_tab_menu() -> void:
	if not _tab_menu: return
	_is_tab_menu_open = true
	# 三件套原子开启：blur/darken 在 SETTINGS/MAP_FROM_VN 路由中已为 true，
	# 重复发射无副作用；返回滑动完成后 SceneManager 会清除 blur/darken，
	# TabMenu 自带 DarkenBg 维持视觉暗化 — 净行为与原单独 set_menu_mode 等价。
	GameManager.set_overlay_mode(true)
	_tab_menu.open(_get_terminal_status(), _is_tab_menu_full(), _current_bg)


# ===================================================================
# 加载（委托给 LoadingScreen）
# ===================================================================

func _show_loading() -> void:
	if _loading_screen:
		_loading_screen.show_loading()
	_dialogue_box.visible = false


func _hide_loading() -> void:
	if _loading_screen:
		_loading_screen.hide_loading()
	_dialogue_box.visible = true
	_dialogue_box.modulate.a = 1.0


# ===================================================================
# 控制提示栏（右下角：保存 / 自动 / 跳过）
# 镜像网页版的操作提示。
# ===================================================================

var _hint_bar: HintBar = null


func _create_controls_hint() -> void:
	if _hint_bar:  # already created
		return
	_hint_bar = HintBar.new()
	# 键框在前说明在后、组间距 32、自带 0.9 黑背景、居中、组 110×72
	_hint_bar.setup(true, 32, true, 0.9, true, Vector2(110, 72))
	_hint_bar.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hint_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_controls_hint.add_child(_hint_bar)

	# 说明字体 — 沿用原实现：非中文环境用 TCM，中文环境用中文标题字体
	var desc_font: Font = GameManager.font_tcm if not _is_zh() else GameManager.font_zh_title

	# 保存 — 简单按钮，切换存档菜单
	_hint_bar.add_hint("save", "S", "Save")
	_hint_bar.connect_hint("save", _toggle_save_menu)
	_hint_bar.set_desc_font("save", desc_font)

	# 自动 — 切换，反映 auto_play 状态
	_hint_bar.add_hint("auto", "A", "Auto")
	_hint_bar.connect_hint("auto", _toggle_auto)
	_hint_bar.set_desc_font("auto", desc_font)

	# 日志 — 打开对话历史覆盖层
	_hint_bar.add_hint("log", "Z", "Log")
	_hint_bar.connect_hint("log", _toggle_log)
	_hint_bar.set_desc_font("log", desc_font)

	_refresh_controls_hint()


func _refresh_controls_hint() -> void:
	if not _hint_bar:
		return

	var is_select: bool = _current_node != null and _current_node.type == "select"

	# 保存 — 常态白色方框 + 黑键
	_hint_bar.set_hint_colors("save", Color(1, 1, 1, 0.3), Color.WHITE, Color.BLACK)

	# 自动 — auto_play 开启时高亮；选择期间禁用变暗
	var auto_on: bool = _settings.auto_play and not is_select
	if is_select:
		_hint_bar.set_hint_colors("auto", Color(1, 1, 1, 0.1), Color(1, 1, 1, 0.05), Color(1, 1, 1, 0.3))
	else:
		_hint_bar.set_hint_colors("auto",
			Color.WHITE if auto_on else Color(1, 1, 1, 0.3),
			Color.WHITE,
			Color.BLACK)
	_hint_bar.set_hint_active("auto", auto_on)

	# 日志 — 常态白色方框 + 黑键；选择/日志已打开时变暗
	var log_blocked: bool = is_select or _is_log_open
	_hint_bar.set_hint_colors("log",
		Color(1, 1, 1, 0.1) if log_blocked else Color(1, 1, 1, 0.3),
		Color(1, 1, 1, 0.05) if log_blocked else Color.WHITE,
		Color(1, 1, 1, 0.3) if log_blocked else Color.BLACK)


# ── 跳过指示器（右上角）──────────────────────────

func _create_skip_indicator() -> void:
	if _skip_indicator:  # already created
		return
	_skip_indicator = Label.new()
	_skip_indicator.name = "SkipIndicator"
	_skip_indicator.text = tr("加速中 >>>   再按 Ctrl 停止")
	_skip_indicator.visible = false
	_skip_indicator.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_skip_indicator.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_skip_indicator.add_theme_font_size_override("font_size", 22)
	_skip_indicator.add_theme_color_override("font_color", Color(1, 0.84, 0, 0.9))
	_skip_indicator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_skip_indicator.z_index = 5

	# 位置：右上角，锚定到右边缘
	_skip_indicator.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_skip_indicator.offset_left = -520.0
	_skip_indicator.offset_right = -32.0
	_skip_indicator.offset_top = 16.0
	_skip_indicator.offset_bottom = 48.0

	if GameManager.font_zh_body:
		_skip_indicator.add_theme_font_override("font", GameManager.font_zh_body)

	add_child(_skip_indicator)


func _update_skip_indicator() -> void:
	if _skip_indicator:
		_skip_indicator.visible = _is_skipping


func _toggle_auto() -> void:
	GameManager.set_setting("auto_play", not _settings.auto_play)
	_settings = GameManager.get_settings()
	_refresh_controls_hint()


func _toggle_log() -> void:
	if _is_log_open:
		_log_screen.close()
		_on_log_closed()
	else:
		if not _log_screen: return
		_is_log_open = true
		# 减弱 BGM + 模糊/变暗背景 — 与 Tab/Save 菜单相同的策略
		GameManager.set_overlay_mode(true)
		_log_screen.open(_log_entries)
		_log_screen.visible = true
		_play_click()
	_refresh_controls_hint()


func _on_tab_menu_closed() -> void:
	_is_tab_menu_open = false
	GameManager.set_overlay_mode(false)


func _on_tab_open_settings() -> void:
	_is_tab_menu_open = false
	# SceneManager 在过渡期间会保持减弱的音频
	scene_changed.emit("SETTINGS_FROM_VN")


func _on_tab_open_map() -> void:
	_is_tab_menu_open = false
	scene_changed.emit("MAP_FROM_VN")


func _on_tab_back_to_title() -> void:
	_is_tab_menu_open = false
	GameManager.set_overlay_mode(false)
	back_requested.emit()


func _on_log_closed() -> void:
	_is_log_open = false
	if _log_screen:
		_log_screen.visible = false
	# 恢复 BGM + 背景 — 与 Tab/Save 菜单相同的策略
	GameManager.set_overlay_mode(false)
	_refresh_controls_hint()


# ===================================================================
# 音频
# ===================================================================

func _play_click() -> void:
	AudioManager.play_click()


# ===================================================================
# 进程
# ===================================================================

func _process(delta: float) -> void:
	_vn_bg.set_skip_mode(_is_skipping)
	# ── CTRL 跳过切换：_input() 防止在按住 Ctrl 时停止跳过，
	# ── _process() 通过轮询提供边缘检测切换。
	# ── 两者都使用 Input.is_key_pressed(KEY_CTRL) — Windows 上修饰键的唯一可靠方法。
	var ctrl_down: bool = Input.is_key_pressed(KEY_CTRL)
	if ctrl_down and not _ctrl_was_down:
		_try_toggle_skip()
	_ctrl_was_down = ctrl_down

	# 每帧同步跳过指示器可见性
	if _skip_indicator and _skip_indicator.visible != _is_skipping:
		_skip_indicator.visible = _is_skipping

	# 视差效果：每帧从视口获取鼠标位置（_gui_input 不一定触发）
	_mouse_pos = get_viewport().get_mouse_position()
	var vs: Vector2 = get_viewport().get_visible_rect().size
	_vn_bg.update_parallax(_mouse_pos, vs, delta)

	if not _current_node: return

	if _is_waiting:
		# 快进时等待时间减半；自动模式下正常等待
		_wait_timer += delta * (2.0 if _is_skipping else 1.0)
		if _wait_timer >= _current_node.wait_time:
			_is_waiting = false
			_wait_timer = 0.0
			_visible_chars = 0
			_is_typing_finished = false
			_update_dialogue_display()
			# 如果等待在过渡节点上（无文本），自动推进
			if _get_localized_text().is_empty():
				_check_auto_advance()
		return

	var text: String = _get_localized_text()

	if not _is_typing_finished and _visible_chars < text.length():
		_typewriter_timer += delta
		if _typewriter_timer >= _typewriter_interval:
			_typewriter_timer = 0.0
			_visible_chars += 1
			_dialogue_text.visible_characters = _visible_chars
			if _visible_chars >= text.length():
				_is_typing_finished = true

	if (_settings.auto_play and _is_typing_finished
		and _current_node.type != "select"
		and not _is_skipping
		and not _is_auto_advancing
		and not _is_menu_open
		and not _is_tab_menu_open
		and not _is_log_open):
		_auto_play_timer += delta
		if _auto_play_timer >= _auto_play_delay:
			_auto_play_timer = 0.0
			_advance()

	if _is_skipping and not _is_auto_advancing and not _is_menu_open and not _is_tab_menu_open and not _is_log_open and (_current_node.type != "select" or not _reaction_queue.is_empty()):
		var skip_delay: float = 0.02 if _is_typing_finished else 0.005
		_auto_play_timer += delta
		if _auto_play_timer >= skip_delay:
			_auto_play_timer = 0.0
			_advance()


# ===================================================================
# 输入
# ===================================================================

func _input(event: InputEvent) -> void:
	if not event.is_pressed(): return

	# 跳过模式期间的任何输入都会停止跳过 — 除非当前按住 Ctrl
	#（通过 Input 单例检查，与 _process 轮询相同）。
	# 我们使用 Input.is_key_pressed() 而不是尝试匹配 event.keycode，
	# 因为修饰键事件通常不携带可用的 keycode。
	if _is_skipping and not Input.is_key_pressed(KEY_CTRL):
		_is_skipping = false
		_play_click()
		return

	# 章节过渡期间阻止所有输入
	if _is_auto_advancing:
		get_viewport().set_input_as_handled()
		return

	if _has_active_overwrite_modal(): return

	# 日志屏幕有自己的输入处理
	if _is_log_open:
		return

	if event.is_action_pressed("vn_tab") or event.is_action_pressed("ui_cancel"):
		# Tab 键或 ESC — 打开 tab 菜单
		_toggle_tab_menu()
		get_viewport().set_input_as_handled()
		return

	if _is_menu_open:
		return

	if _is_tab_menu_open:
		return

	if _current_node and _current_node.type == "select" and _is_typing_finished:
		return

	if event.is_action_pressed("vn_save"):
		_toggle_save_menu()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("vn_log"):
		_toggle_log()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("vn_auto"):
		_toggle_auto()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		_advance()
		get_viewport().set_input_as_handled()


func _gui_input(event: InputEvent) -> void:
	# 章节过渡期间阻止鼠标点击
	if _is_auto_advancing: return

	# 跳过期间的任何鼠标点击都会停止跳过
	if _is_skipping and event is InputEventMouseButton and event.pressed:
		_is_skipping = false
		_play_click()
		return

	# 跟踪鼠标位置用于视差效果
	if event is InputEventMouseMotion:
		_mouse_pos = event.position

	# 在 VN 区域的任何位置单击鼠标左键都会推进对话
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if _has_active_overwrite_modal(): return
		if _is_log_open: return
		if _is_menu_open or _is_tab_menu_open: return
		if _current_node and _current_node.type == "select" and _is_typing_finished: return
		_advance()
		accept_event()


# ===================================================================
# 自动推进链 — 无需用户输入驱动章节过渡
# ===================================================================

## 检查当前节点是否为纯过渡节点（无对话文本），如果是，则启动自动推进链，
## 按顺序执行停止 → 淡入黑屏 → 章节标题 → 加载 → 淡入，无需用户点击。
func _check_auto_advance() -> void:
	if _is_auto_advancing: return
	if not _reaction_queue.is_empty(): return  # 反应节点需手动推进
	if _is_waiting: return
	if not _current_node: return
	if not _get_localized_text().is_empty(): return
	if _current_node.type == "select": return
	if _current_node.back_to_title: return

	# V2 流程控制节点 — 立即执行，无需动画
	if _current_node.type in ["label", "goto", "set", "persist", "if", "else", "endif"]:
		_advance()
		return

	# 仅对特殊过渡节点触发（stop/black/jump），不包括纯场景节点
	var is_transition: bool = (
		_current_node.stop_transition or
		_current_node.fade_black > 0.0 or
		not _current_node.jump_plot_id.is_empty() or
		_current_node.back_to_title or
		_current_node.rechoose
	)
	if not is_transition: return

	_is_auto_advancing = true
	_auto_advance_chain()


## 无需用户输入，按顺序执行停止 → 黑屏 → 跳转链。
## 每个阶段等待适当的视觉延迟，然后调用 _advance()
## 移动到下一个节点。当到达跳转节点时，完整的电影式章节过渡协程接管。
func _auto_advance_chain() -> void:
	# ── 阶段 1：停止过渡节点 ──
	if _current_node and _current_node.stop_transition:
		await get_tree().create_timer(0.35).timeout
		if _exit_tree_called:
			_is_auto_advancing = false
			return
		_is_typing_finished = true
		_advance()

	if not _current_node:
		_is_auto_advancing = false
		return

	# ── 阶段 2：淡入黑屏节点 ──
	if _current_node.fade_black > 0.0:
		# 精确等待淡入黑屏完成（加上一帧缓冲）
		await get_tree().create_timer(_current_node.fade_black + 0.05).timeout
		if _exit_tree_called:
			_is_auto_advancing = false
			return
		_is_typing_finished = true
		_advance()

	if not _current_node:
		_is_auto_advancing = false
		return

	# ── 阶段 3：跳转节点 → 电影式章节过渡 ──
	if not _current_node.jump_plot_id.is_empty():
		_is_auto_advancing = false
		await _execute_chapter_transition()
		return

	# ── 阶段 4：通用场景节点（无对话，无跳转）──
	if _current_node.type == "scene" and _get_localized_text().is_empty():
		await get_tree().create_timer(0.1).timeout
		if _exit_tree_called:
			_is_auto_advancing = false
			return
		_is_typing_finished = true
		_advance()

	_is_auto_advancing = false


# ===================================================================
## 在黑屏后面将 _node_index 推进到第一个有实际文本的节点，
## 应用经过节点的背景/角色/音频效果，但不更新 UI 可见性。
func _advance_to_first_text() -> void:
	if not _plot or _plot.nodes.is_empty(): return
	while _node_index < _plot.nodes.size():
		var node: PlotNode = _plot.nodes[_node_index]
		# 应用背景、角色、音频效果
		if not node.bg.is_empty(): _set_background(node.bg)
		if node.ch == "__CLEAR__": _set_character("")
		elif not node.ch.is_empty(): _set_character(node.ch)
		if node.bgm: _apply_audio_bgm(node.bgm)
		if node.ambience and not node.ambience.play.is_empty():
			VNAudioService.set_ambience_layer(0, node.ambience.play, node.ambience.ambience_volume)
		if node.sfx_short and not node.sfx_short.play.is_empty():
			AudioManager.play_sfx(node.sfx_short.play)
		# V2 flow nodes — @set 立即执行，其余停下交给 _execute_flow_control
		if node.type == "set":
			if not node.expression.is_empty():
				_context.apply_expression(node.expression, false)
			_node_index += 1
			continue
		if node.type == "persist":
			if not node.expression.is_empty():
				_context.apply_expression(node.expression, true)
			_node_index += 1
			continue
		if node.type in ["label", "goto", "if", "else", "endif"]:
			_current_node = node
			return
		# 有文本或特殊节点时停止
		var text: String = node.EN if not _is_zh() and not node.EN.is_empty() else node.ZH
		if not text.is_empty() or node.stop_transition or node.fade_black > 0.0 or not node.jump_plot_id.is_empty() or node.wait_time > 0.0:
			_current_node = node
			# 预填充文本但不显示
			text = _apply_text_styling(text)
			if not _is_zh(): text = GameManager.wrap_font_fallback(text, GameManager.FONT_EN_BODY, GameManager.FONT_ZH_BODY)
			_dialogue_text.text = text
			_apply_dialogue_box_style(node.glitch)
			if node.glitch: _dialogue_text.add_theme_color_override("default_color", Color(1, 0.3, 0.3, 1))
			else: _dialogue_text.add_theme_color_override("default_color", Color.BLACK)
			_visible_chars = text.length()
			_dialogue_text.visible_characters = -1
			_is_typing_finished = true
			# 说话者名称也预填充
			if node.who.is_empty() or node.who in ["???", "旁白", "Narrator", "narrator", "system", "system_text", "none"]:
				_speaker_name_container.visible = false
			else:
				var sp: String = node.who
				if sp == "player" or sp == "我": sp = _player_name
				elif _plot: sp = _plot.get_character_name(sp, TranslationServer.get_locale())
				if sp.is_empty():
					_speaker_name_container.visible = false
				else:
					_speaker_name_container.visible = true
					_build_speaker_name(sp)
			_log_entries.append({"who": node.who, "zh": node.ZH, "en": node.EN})
			return
		_node_index += 1
	# 所有节点都没有文本——停在最后一个
	_current_node = _plot.nodes[_plot.nodes.size() - 1]


func _apply_audio_bgm(c: AudioCommand) -> void:
	if c.stop:
		if c.fade_out_only: VNAudioService.fade_out_bgm(c.fade_out_duration)
		else: VNAudioService.stop_bgm()
	elif not c.play.is_empty():
		if c.crossfade: VNAudioService.crossfade_bgm(c.play, c.fade_out_duration, c.fade_in_duration)
		else: VNAudioService.play_bgm(c.play, c.loop)


# 电影式章节过渡
# ===================================================================

## 完整的电影式章节过渡序列：
##   1. 确保完全黑屏（前面的 @black 节点已经淡出）
##   2. 将 UI 隐藏在黑屏后面
##   3. 在黑屏覆盖层后面静默加载新剧情
##   4. 从黑屏淡出以显示新章节（约 1.0 秒）
##   5. 平滑淡入 UI 元素 — 无瞬间闪烁
##   6. 启动新章节的第一个节点
##
## 加上前面 @black 节点的 1.0 秒淡入黑屏，
## 总过渡时间约为 2.0 秒。
func _execute_chapter_transition() -> void:
	_play_click()
	_is_auto_advancing = true

	# 过渡期间禁用跳过
	_is_skipping = false

	# 1. 确保完全黑屏（前面的 @black 节点已经淡出到 ~1.0 alpha）
	_vn_bg.set_black()

	# 2. 立即将所有 UI 隐藏在黑屏覆盖层后面 — 同时清除旧内容以防止淡入时闪烁
	_dialogue_box.visible = false
	_speaker_name_container.visible = false
	_dialogue_text.text = ""
	if _name_hbox:
		for c in _name_hbox.get_children():
			c.queue_free()
	_last_speaker_name = ""
	_char_rect.modulate.a = 0.0
	_char_rect.visible = false
	_controls_hint.modulate.a = 0.0
	_controls_hint.visible = false

	# 3. 在黑屏后面静默加载新剧情
	var new_plot_id: String = _current_node.jump_plot_id
	var new_node_index: int = _current_node.jump_node_index
	_load_plot_silent(new_plot_id, new_node_index)

	# 4. 在黑屏后静默跳到第一个有文本的节点，不触发显示
	_advance_to_first_text()

	# 5. 从黑屏淡出（1.0 秒）
	_vn_bg.fade_from_black(1.0)
	await get_tree().create_timer(1.0).timeout
	if _exit_tree_called:
		_is_auto_advancing = false
		return

	# 6. 平滑淡入 UI — 文本和姓名框已由 _advance_to_first_text 设置好
	_dialogue_box.visible = true
	_dialogue_box.modulate.a = 0.0
	if _speaker_name_container.visible:
		_speaker_name_container.modulate.a = 0.0
	_char_rect.visible = true
	_controls_hint.visible = true

	var ui_tween := create_tween().set_parallel(true)
	ui_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	ui_tween.tween_property(_dialogue_box, "modulate:a", 1.0, 0.4)
	if _speaker_name_container.visible:
		ui_tween.tween_property(_speaker_name_container, "modulate:a", 1.0, 0.4)
	ui_tween.tween_property(_char_rect, "modulate:a", 1.0, 0.5)
	ui_tween.tween_property(_controls_hint, "modulate:a", 1.0, 0.4)

	await ui_tween.finished
	_is_auto_advancing = false



# ===================================================================
# 静默剧情加载（无加载屏幕）
# ===================================================================


## 不显示加载屏幕加载剧情 — 在章节过渡期间使用，此时屏幕已经完全黑屏。
func _load_plot_silent(plot_id: String, start_node_index: int) -> void:
	var text: String = ""
	var story_gd: RefCounted = STORY_TEXTS.get(plot_id, null)
	if story_gd:
		text = story_gd.TEXT

	if text.is_empty():
		push_error("VNInterface: Could not load plot '", plot_id, "'")
		return

	var parser: ScriptParser = ScriptParser.new(plot_id)
	_plot = parser.parse(text)
	# 防失误：STORY_TEXTS key 必须与脚本内 :: id 一致
	if _plot.id != "" and _plot.id != plot_id:
		push_error("VNInterface: :: id mismatch — STORY_TEXTS key '", plot_id,
			"' vs parsed '", _plot.id, "'. Fix Story_*.gd or STORY_TEXTS.")

	if _plot.nodes.is_empty():
		push_error("VNInterface: Plot '", plot_id, "' parsed with zero nodes")
		return

	_plot_id = plot_id
	_node_index = clampi(start_node_index, 0, max(0, _plot.nodes.size() - 1))

	# 重置 VN 状态
	_visible_chars = 0
	_is_typing_finished = false
	_is_waiting = false
	_wait_timer = 0.0
	_auto_play_timer = 0.0
	_typewriter_timer = 0.0
	_current_bg = ""
	_current_char = ""
	_char_rect.texture = null
	_char_rect.modulate.a = 1.0
	_char_rect.position.x = 0.0
	_char_rect.visible = false
	_last_speaker_name = ""
	_log_entries.clear()

	# 在黑屏覆盖层后面预应用第一个节点的背景，
	# 这样淡入时就已经准备好了
	if not _plot.nodes.is_empty():
		var first_node: PlotNode = _plot.nodes[0]
		if not first_node.bg.is_empty():
			var normalized: String = _normalize_asset_path(first_node.bg)
			_current_bg = normalized
			_vn_bg.set_bg(normalized)

	_current_node = _plot.nodes[_node_index]


# ===================================================================
# Ctrl 跳过切换辅助函数
# ===================================================================

## 切换跳过模式的开启/关闭。保护：在选择节点或任何覆盖菜单打开时无操作。
func _try_toggle_skip() -> void:
	if _current_node and _current_node.type != "select" and not _is_menu_open and not _is_tab_menu_open and not _is_log_open:
		_is_skipping = not _is_skipping
		if _is_skipping and _settings.auto_play:
			GameManager.set_setting("auto_play", false)
			_settings = GameManager.get_settings()
		_play_click()


# ===================================================================
# 注释工具提示 — 悬停在 [url] 标签上
# ===================================================================

## 当玩家悬停在注释（[url=TIP]text[/url]）上时，在鼠标附近显示工具提示。
## 工具提示只显示注释内容，不显示带下划线的正文文本。
func _on_annotation_hover_started(meta: Variant) -> void:
	var tip: String = str(meta)
	if tip.is_empty():
		return

	# 延迟创建工具提示标签
	if not _annotation_tooltip:
		_annotation_tooltip = Label.new()
		_annotation_tooltip.name = "AnnotationTooltip"
		_annotation_tooltip.z_index = 100
		_annotation_tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_annotation_tooltip.add_theme_color_override("font_color", Color.BLACK)
		_annotation_tooltip.add_theme_font_size_override("font_size", 18)
		_annotation_tooltip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_annotation_tooltip.custom_minimum_size.x = 350

		# 样式：半透明白色背景，带圆角
		var tooltip_style := StyleBoxFlat.new()
		tooltip_style.bg_color = Color(1, 1, 1, 0.92)
		tooltip_style.border_color = Color(0, 0, 0, 0.3)
		tooltip_style.border_width_left = 1
		tooltip_style.border_width_right = 1
		tooltip_style.border_width_top = 1
		tooltip_style.border_width_bottom = 1
		tooltip_style.corner_radius_top_left = 4
		tooltip_style.corner_radius_top_right = 4
		tooltip_style.corner_radius_bottom_left = 4
		tooltip_style.corner_radius_bottom_right = 4
		tooltip_style.content_margin_left = 10
		tooltip_style.content_margin_right = 10
		tooltip_style.content_margin_top = 6
		tooltip_style.content_margin_bottom = 6
		_annotation_tooltip.add_theme_stylebox_override("normal", tooltip_style)

		# 字体：为工具提示使用正文字体
		if GameManager.font_zh_body:
			_annotation_tooltip.add_theme_font_override("font", GameManager.font_zh_body)

		add_child(_annotation_tooltip)

	_annotation_tooltip.text = tip
	_annotation_tooltip.visible = true

	# 定位在鼠标光标附近，略微向右偏移
	var mouse_pos: Vector2 = get_viewport().get_mouse_position()
	var tooltip_size: Vector2 = _annotation_tooltip.get_minimum_size()
	var offset := Vector2(16, -tooltip_size.y - 8)
	_annotation_tooltip.position = mouse_pos + offset


func _on_annotation_hover_ended(_meta: Variant = "") -> void:
	if _annotation_tooltip:
		_annotation_tooltip.visible = false


# ===================================================================
# 清理
# ===================================================================

func _exit_tree() -> void:
	_exit_tree_called = true
	VNAudioService.clear_all_ambience(0.5)
	AudioManager.set_vn_effect(0)
	AudioManager.reset_effects()
