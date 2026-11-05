## TabMenu : Control
## 游戏内Tab菜单 — 重新设计以匹配 QuitConfirm 模态框风格。
## 多级菜单：主菜单 → 系统 → 配置。按Tab键打开，ESC键关闭。
## 选项行（主列表与返回标题确认对话框）为 scenes/ui/OptionRow 统一组件。
class_name TabMenu
extends Control

enum MenuLevel { MAIN, SYSTEM, SIDESTORY }

signal close_requested()
signal back_to_title()
signal open_settings()
signal open_map()
signal open_calendar()
signal open_sidestory(story_id: String)
signal sidestory_back_requested()

# ---------------------------------------------------------------------------
# 状态
# ---------------------------------------------------------------------------
var _level: MenuLevel = MenuLevel.MAIN
var _focus_idx: int = 0
var _is_open: bool = false
var _restricted: bool = false   # true 时仅允许 System 层级菜单（序章未完结）
var _anim_tween: Tween = null
var _entry_tweens: Array[Tween] = []

# ── 层级选择记忆 ──────────────────────────────────
## 每层各自记住上次的选中项（int(MenuLevel) → 选项下标）。
## 「返回上级」和「再次进入某层」都从这里恢复 —— 不再每处写死「要找哪一项」，
## 也不会出现「从 SYSTEM 返回后焦点跳回第一项」这种半对的行为。
var _focus_memory: Dictionary = {}
## 把控制权交给子页面（设置 / 地图 / 日历）时所在的层级。
## 子页面返回时 reopen_from_subpage() 据此重开；_has_return_level 表示「有没有记过」。
var _return_level: MenuLevel = MenuLevel.MAIN
var _has_return_level: bool = false

# ── 入场焦点保护 ──
var _entrance_focus_token: int = 0

# ── 返回标题确认对话框 ──────────────────────────────
var _confirm_active: bool = false
var _confirm_sel: int = 1          # 默认选中 "No 否"
var _confirm_option_nodes: Array[OptionRow] = []
var _confirm_band: Control = null
var _confirm_interactive: bool = false

const CONFIRM_OPTIONS: Array[Dictionary] = [
	{"id": "yes", "title": "Yes", "label": "是"},
	{"id": "no",  "title": "No",  "label": "否"},
]


var _main_options: Array[Dictionary] = []
var _system_options: Array[Dictionary] = []
var _sidestory_options: Array[Dictionary] = []
var _sidestory_mode: bool = false
var _sidestory_list: Array[Dictionary] = []

## 背景毛玻璃 —— 与 LogScreen（Z 键对话历史）共用同一个组件
var _blur: BackdropBlur = null

# ── 品牌框滚动 ──
## 大字外面的裁剪层（滚动时遮掉框外部分）
var _branding_clip: Control = null
var _branding_tween: Tween = null
## 大字的基准 y（裁掉滚动位移后的静止位置）
var _branding_label_y: float = 32.0
## 上一次显示大字时的层级，-1 = 还没显示过（首次不滚）
var _branding_level: int = -1

# UI 节点（来自 .tscn — 静态结构）
@onready var _darken_overlay: ColorRect = $DarkenBg
@onready var _band: Control = $Band
@onready var _branding: Control = $Branding
@onready var _branding_shadow: ColorRect = $Branding/BrandingShadow
@onready var _branding_box: ColorRect = $Branding/BrandingBox
@onready var _branding_label: Label = $Branding/BrandingLabel
@onready var _level_label: Label = $LevelLabel
@onready var _title_label: Label = $TitleLabel
@onready var _subtitle_label: Label = $SubtitleLabel
@onready var _desc_label: Label = $DescLabel
@onready var _options_container: VBoxContainer = $OptionsContainer

const BAND_PAD: float = 64.0

## 白色品牌框（BrandingBox）宽度与标题基准字号 —— 见 tscn 的 200x120 / 72
const BRANDING_BOX_WIDTH: float = 200.0
const BRANDING_FONT_SIZE: int = 72
## 长词缩字号的下限，防止极端情况下糊成一团
const BRANDING_MIN_FONT_SIZE: int = 32
## 层级切换时大字「码表刻度」式滚动的时长
const BRANDING_ROLL_TIME: float = 0.28


# ===================================================================
# 生命周期
# ===================================================================

func _ready() -> void:

	# 阻止所有输入传递到后面的界面。
	# TSCN 中已连接，代码连接作为兜底（兼容 TabMenu.new()）
	if not gui_input.is_connected(_swallow_input):
		gui_input.connect(_swallow_input)

	_setup_backdrop_blur()
	_darken_overlay.color.a = BackdropBlur.SCRIM_ALPHA
	_setup_options()
	_apply_layout()
	_apply_fonts()
	_setup_branding_clip()
	_build_confirm_dialog()


## 建背景毛玻璃并垫到最底层（DarkenBg 之下）。
## 组件内部 mouse_filter = IGNORE，不会抢菜单的鼠标输入。
func _setup_backdrop_blur() -> void:
	_blur = BackdropBlur.new()
	_blur.name = "BackdropBlur"
	add_child(_blur)
	move_child(_blur, 0)


func _setup_options() -> void:
	_main_options = [
		{"id": "Item",       "name": "物品", "desc": "查看现有的物品。"},
		{"id": "Terminal",   "name": "终端", "desc": "访问终端。"},
		{"id": "Profile",    "name": "档案", "desc": "记录有关人物的背景资料。"},
		{"id": "Story",      "name": "故事", "desc": "回顾已经历过的剧情节点。"},
		{"id": "Data",       "name": "资料", "desc": "整理收集到的线索。"},
		{"id": "Calendar",   "name": "日程", "desc": "查看日程表。"},
		{"id": "Map",        "name": "地图", "desc": "查看校园地图。"},
		{"id": "System",     "name": "系统", "desc": "管理游戏选项。"},
	]
	if _sidestory_mode:
		_system_options = [
			{"id": "Config", "name": "设置",     "desc": "变更游戏设定。"},
			{"id": "Back",   "name": "返回主线", "desc": "退出支线剧情，返回主线剧情。"},
		]
	else:
		_system_options = [
			{"id": "Config",   "name": "设置",     "desc": "变更游戏设定。"},
			{"id": "Back",     "name": "返回菜单", "desc": "返回上一级菜单。"},
			{"id": "Title",    "name": "返回标题", "desc": "返回主界面。"},
		]
		_sidestory_options = _sidestory_list.duplicate()
		# 没有已注册的支线时隐藏"资料"入口
		if _sidestory_list.is_empty():
			var filtered: Array[Dictionary] = []
			for o in _main_options:
				if o.id != "Data":
					filtered.append(o)
			_main_options = filtered


# ===================================================================
# 静态节点初始化（视口相关位置 + 字体）
# ===================================================================

func _apply_layout() -> void:
	var vp_h: float = get_viewport().get_visible_rect().size.y
	_branding.position = Vector2(48, vp_h / 2.0 - BAND_PAD - 48)
	_branding_shadow.size = _branding_box.size
	_level_label.position = Vector2(48, vp_h / 2.0 + BAND_PAD + 20)
	_title_label.position = Vector2(48, vp_h / 2.0 + BAND_PAD + 36)
	_subtitle_label.position = Vector2(48, vp_h / 2.0 + BAND_PAD + 76)
	_desc_label.position = Vector2(48, vp_h / 2.0 + BAND_PAD + 100)


func _apply_fonts() -> void:
	if GameManager.font_tcm:
		_branding_label.add_theme_font_override("font", GameManager.font_tcm)
		_level_label.add_theme_font_override("font", GameManager.font_tcm)
		_title_label.add_theme_font_override("font", GameManager.font_tcm)

	if GameManager.font_zh_title:
		_subtitle_label.add_theme_font_override("font", GameManager.font_zh_title)

	if GameManager.font_zh_body:
		_desc_label.add_theme_font_override("font", GameManager.font_zh_body)


# ===================================================================
# 打开 / 关闭
# ===================================================================

func open(terminal_status: String = "locked", full_menu: bool = true, _bg_path: String = "", sidestory_list: Array[Dictionary] = [], restore_return: bool = false) -> void:
	_is_open = true
	_restricted = not full_menu
	_sidestory_list = sidestory_list

	# 常规入口层：受限 / 支线模式只能进 System，否则从主菜单开始
	var default_level: MenuLevel = MenuLevel.SYSTEM if (_sidestory_mode or _restricted) else MenuLevel.MAIN
	# 从子页面返回 → 回到离开时那一层（而不是一律退回主菜单）
	var use_memory: bool = restore_return and _has_return_level
	var target_level: MenuLevel = _return_level if use_memory else default_level
	_has_return_level = false
	# 全新打开 = 全新一轮：清空层级记忆。只有同一轮内的前进/后退才沿用记忆，
	# 否则下次按 Tab 打开会莫名其妙停在上一轮的地方。
	if not use_memory:
		_focus_memory.clear()

	# 强制尺寸填满视口 — 这对鼠标输入拦截至关重要
	var vs := get_viewport().get_visible_rect().size
	position = Vector2.ZERO
	size = vs

	_setup_options()
	if terminal_status == "locked":
		var f: Array[Dictionary] = []
		for o in _main_options:
			if o.id != "Terminal": f.append(o)
		_main_options = f

	# 受限模式下保留 Back —— 行为改为 close()，文案改为返回游戏
	if _restricted:
		for o in _system_options:
			if o.id == "Back":
				o.name = "返回游戏"

	# 焦点放到选项表重建之后：_memory_index() 读的是当前层的选项表，顺序不能反
	_level = target_level
	_focus_idx = _memory_index() if use_memory else 0

	_refresh_options()
	_animate_enter()


## 从子页面（设置 / 地图 / 日历）返回时重开：回到离开时那一层与那一项。
## 参数与 open() 保持一致，便于两处调用点直接替换 —— 唯一差别就是「沿用上次状态」。
func reopen_from_subpage(terminal_status: String = "locked", full_menu: bool = true, bg_path: String = "", sidestory_list: Array[Dictionary] = []) -> void:
	open(terminal_status, full_menu, bg_path, sidestory_list, true)


func close() -> void:
	_is_open = false
	_kill_anim()

	_anim_tween = create_tween()
	_anim_tween.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	_anim_tween.tween_property(self, "modulate:a", 0.0, 0.25)
	_anim_tween.tween_callback(_on_close_done)
	# 背景：模糊 → 清晰
	if _blur:
		_blur.blur_out()


func _on_close_done() -> void:
	visible = false
	close_requested.emit()


# ===================================================================
# 动画
# ===================================================================

func _animate_enter() -> void:
	visible = true
	_kill_anim()

	# 立即设置不透明状态（黑幕不透明度与 Z 键对话历史共用同一个常量）
	_darken_overlay.color.a = BackdropBlur.SCRIM_ALPHA
	_band.scale.x = 1.0

	# 背景：清晰 → 模糊（与 LogScreen 同一套组件、同一组参数）
	if _blur:
		_blur.set_amount(0.0)
		_blur.blur_in()

	# Fade self + options in smoothly
	modulate.a = 0.0
	_entry_tweens.clear()
	_anim_tween = create_tween().set_parallel(true)
	_anim_tween.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	_anim_tween.tween_property(self, "modulate:a", 1.0, 0.3)
	for i: int in range(_options_container.get_child_count()):
		var c := _options_container.get_child(i)
		c.modulate.a = 0.0
		var st := create_tween()
		st.tween_interval(0.2 + i * 0.04)
		st.tween_property(c, "modulate:a", 1.0, 0.2)
		_entry_tweens.append(st)

	# 焦点延迟设置 — 用 token 防止用户操作后又被强行拉回
	var token: int = _entrance_focus_token + 1
	_entrance_focus_token = token
	var row_count: int = _options_container.get_child_count()
	var focus_delay: float = 0.46 + row_count * 0.04
	var focus_tween := create_tween()
	focus_tween.tween_interval(focus_delay)
	focus_tween.tween_callback(func():
		if _entrance_focus_token == token:  # 没有被取消
			_update_focus()
	)
	_entry_tweens.append(focus_tween)



# ===================================================================
# 选项
# ===================================================================

func _refresh_options() -> void:
	for c in _options_container.get_children():
		_options_container.remove_child(c)
		c.queue_free()

	var opts := _get_current_options()
	var vp_w: float = get_viewport().get_visible_rect().size.x
	_options_container.position = Vector2(vp_w - 520, get_viewport().get_visible_rect().size.y / 2.0 - OptionRow.ROW_HEIGHT * opts.size() / 2.0)

	for i: int in range(opts.size()):
		var row := _make_row(i, opts[i])
		_options_container.add_child(row)

	_update_level_display()
	_update_focus()


func _get_current_options() -> Array[Dictionary]:
	match _level:
		MenuLevel.MAIN:      return _main_options
		MenuLevel.SYSTEM:    return _system_options
		MenuLevel.SIDESTORY: return _sidestory_options
	return []


func _make_row(idx: int, data: Dictionary) -> OptionRow:
	var sub_text: String = "" if GameManager.is_locale("en") else tr(data.name)
	@warning_ignore("static_called_on_instance")
	var sub_font: Font = GameManager.select_font(sub_text, GameManager.font_zh_title, GameManager.font_tcm)
	var row := OptionRow.new()
	row.setup(idx, data.id, sub_text, GameManager.font_tcm, sub_font, 480.0)
	row.hovered.connect(_on_hover)
	row.activated.connect(_on_row_activated)
	return row


# ===================================================================
# 层级显示
# ===================================================================

## 白色品牌框里的大字 —— 跟着当前层级走，不该永远是 "Menu"
func _level_title() -> String:
	match _level:
		MenuLevel.SYSTEM:    return "System"
		MenuLevel.SIDESTORY: return "Story"
		_:                   return "Menu"


## 品牌框只有 200px 宽：长词（System）按宽度等比缩字号，短词（Menu）保持 72。
## 只缩不涨，所以默认界面观感不变。
func _branding_font_size_for(text: String) -> int:
	var font: Font = GameManager.font_tcm
	if font == null:
		return BRANDING_FONT_SIZE
	var text_w: float = font.get_string_size(
			text, HORIZONTAL_ALIGNMENT_LEFT, -1, BRANDING_FONT_SIZE).x
	if text_w <= BRANDING_BOX_WIDTH:
		return BRANDING_FONT_SIZE
	return maxi(BRANDING_MIN_FONT_SIZE,
			int(float(BRANDING_FONT_SIZE) * BRANDING_BOX_WIDTH / text_w))


func _update_branding_title() -> void:
	var text: String = _level_title()
	@warning_ignore("shadowed_variable_base_class")
	var size: int = _branding_font_size_for(text)

	# 首次显示 / 文字没变：直接设，不滚
	if _branding_level < 0 or text == _branding_label.text:
		_branding_label.text = text
		_branding_label.add_theme_font_size_override("font_size", size)
		_branding_level = int(_level)
		return

	# 往深一层走 → 往上滚（新字从下方进来），返回 → 往下滚
	var roll_up: bool = int(_level) > _branding_level
	_branding_level = int(_level)
	_roll_branding(text, size, roll_up)


## 给品牌框套一层裁剪，并把大字移进去 —— 「码表刻度」效果靠它遮掉框外部分。
func _setup_branding_clip() -> void:
	_branding_clip = Control.new()
	_branding_clip.name = "BrandingClip"
	_branding_clip.clip_contents = true
	_branding_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 水平各放宽 8px：标签本身带 -4 的偏移，按白框死裁会切到字形左边
	_branding_clip.position = _branding_box.position + Vector2(-8, 0)
	_branding_clip.size = _branding_box.size + Vector2(16, 0)
	_branding.add_child(_branding_clip)

	# 手动把标签挪进裁剪层：不依赖 reparent 的全局变换推断，位置确定可复现
	var local_pos: Vector2 = _branding_label.position
	_branding_label.reparent(_branding_clip, false)
	_branding_label.position = local_pos - _branding_clip.position
	_branding_label_y = _branding_label.position.y


## 码表式滚动：旧字滚出裁剪框，新字从另一侧滚进来。
@warning_ignore("shadowed_variable_base_class")
func _roll_branding(text: String, size: int, up: bool) -> void:
	if _branding_clip == null:
		_branding_label.text = text
		_branding_label.add_theme_font_size_override("font_size", size)
		return

	if _branding_tween and _branding_tween.is_valid():
		_branding_tween.kill()
	# 上一轮可能还没滚完：清掉非当前标签，并把当前标签归位
	for c in _branding_clip.get_children():
		if c != _branding_label:
			c.queue_free()
	_branding_label.position.y = _branding_label_y

	var dist: float = _branding_clip.size.y * (1.0 if up else -1.0)
	var outgoing: Label = _branding_label
	var incoming: Label = _branding_label.duplicate() as Label
	incoming.text = text
	incoming.add_theme_font_size_override("font_size", size)
	incoming.position.y = _branding_label_y + dist
	_branding_clip.add_child(incoming)
	_branding_label = incoming

	_branding_tween = create_tween()
	_branding_tween.set_parallel(true)
	_branding_tween.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	_branding_tween.tween_property(outgoing, "position:y", _branding_label_y - dist, BRANDING_ROLL_TIME)
	_branding_tween.tween_property(incoming, "position:y", _branding_label_y, BRANDING_ROLL_TIME)
	_branding_tween.set_parallel(false)
	_branding_tween.tween_callback(outgoing.queue_free)


func _update_level_display() -> void:
	match _level:
		MenuLevel.MAIN:      _level_label.text = "MAIN"
		MenuLevel.SYSTEM:    _level_label.text = "SYSTEM"
		MenuLevel.SIDESTORY: _level_label.text = "SIDESTORY"

	_update_branding_title()

	var opts := _get_current_options()
	if _focus_idx >= 0 and _focus_idx < opts.size():
		var d := opts[_focus_idx]
		_title_label.text = d.get("id", "")
		_subtitle_label.text = "" if GameManager.is_locale("en") else tr(d.name)
		@warning_ignore("static_called_on_instance")
		_subtitle_label.add_theme_font_override("font", GameManager.select_font(_subtitle_label.text, GameManager.font_zh_title, GameManager.font_tcm))
		_desc_label.text = tr(d.desc)
		@warning_ignore("static_called_on_instance")
		_desc_label.add_theme_font_override("font", GameManager.select_font(_desc_label.text, GameManager.font_zh_body, GameManager.font_en_body))


# ===================================================================
# 焦点
# ===================================================================

func _update_focus() -> void:
	var opts := _get_current_options()
	for i: int in range(opts.size()):
		var row := _options_container.get_child(i) as OptionRow
		var on := i == _focus_idx
		# "终端 Terminal" 未选中时也比其他选项更亮，保持视觉突出
		var is_terminal: bool = (opts[i].get("id", "") == "Terminal")
		var unsel_alpha: float = 0.65 if is_terminal else 0.35
		var unsel_zh_color: Color = Color(1, 1, 1, 0.75) if is_terminal else Color(1, 1, 1, 0.5)
		row.apply_focus_state(on, OptionRow.ROW_FOCUS_X, OptionRow.ROW_REST_X, unsel_alpha, unsel_zh_color)

	_update_level_display()


# ===================================================================
# 交互
# ===================================================================

func _on_hover(idx: int) -> void:
	if _focus_idx == idx: return
	_entrance_focus_token += 1
	_focus_idx = idx; _update_focus(); _play_click()


func _on_row_activated(idx: int) -> void:
	_focus_idx = idx; _update_focus(); _handle_action(0); _play_click()


func _handle_action(dir: int) -> void:
	_play_click()
	# dir: 0=鼠标点击, 1=Enter/Space/→, -1=←
	# MAIN / SYSTEM 没有 +/- 调节语义，全部方向都视为确认选择
	var confirm: bool = (dir == 0 or dir == 1)
	match _level:
		MenuLevel.MAIN:
			var o := _main_options[_focus_idx]
			if o.id == "System" and confirm:
				_enter_level(MenuLevel.SYSTEM)
			if o.id == "Calendar" and confirm:
				_hand_off_to_subpage()
				open_calendar.emit()
			if o.id == "Map" and confirm:
				_hand_off_to_subpage()
				open_map.emit()
			if o.id == "Data" and confirm:
				_enter_level(MenuLevel.SIDESTORY)
		MenuLevel.SYSTEM:
			var o := _system_options[_focus_idx]
			match o.id:
				"Config":
					if confirm:
						_hand_off_to_subpage()
						open_settings.emit()
				"Back":
					if confirm:
						if _sidestory_mode:
							_is_open = false
							visible = false
							close_requested.emit()
							sidestory_back_requested.emit()
						elif _restricted:
							close()
						else:
							_enter_level(MenuLevel.MAIN)
				"Title":
					if confirm: _show_confirm()
		MenuLevel.SIDESTORY:
			var o := _sidestory_options[_focus_idx]
			if confirm:
				_is_open = false
				visible = false
				open_sidestory.emit(o.id)


# ===================================================================
# 输入
# ===================================================================

func _input(event: InputEvent) -> void:
	if not _is_open or not event.is_pressed(): return

	# ── 确认对话框输入接管 ──
	if _confirm_active:
		_handle_confirm_input(event)
		return

	if event.is_action_pressed("ui_cancel"):
		match _level:
			MenuLevel.SYSTEM:
				if _sidestory_mode or _restricted:
					close(); get_viewport().set_input_as_handled(); return
				_enter_level(MenuLevel.MAIN)
				_play_click(); get_viewport().set_input_as_handled(); return
			MenuLevel.SIDESTORY:
				_enter_level(MenuLevel.MAIN)
				_play_click(); get_viewport().set_input_as_handled(); return
			MenuLevel.MAIN:    close(); get_viewport().set_input_as_handled(); return
	elif event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_right"):
		_handle_action(1); get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_left"):
		_handle_action(-1); get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_up"):
		_entrance_focus_token += 1   # 取消入场焦点
		_focus_idx = max(0, _focus_idx - 1); _update_focus(); _play_click(); get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_down"):
		_entrance_focus_token += 1
		var sz := _get_current_options().size()
		_focus_idx = min(sz - 1, _focus_idx + 1); _update_focus(); _play_click(); get_viewport().set_input_as_handled()


# ===================================================================
# 辅助函数
# ===================================================================

func _play_click() -> void:
	AudioManager.play_click()


func _swallow_input(_event: InputEvent) -> void:
	pass  # 阻止所有输入传递到后面的视觉小说界面

func _kill_anim() -> void:
	if _anim_tween and _anim_tween.is_valid():
		_anim_tween.kill()
	_anim_tween = null
	for tw: Tween in _entry_tweens:
		if tw and tw.is_valid():
			tw.kill()
	_entry_tweens.clear()


# ===================================================================
# 层级导航（前进 / 后退）
# ===================================================================

## 切到另一层：先记下当前层的选择，再恢复目标层上次的选择。
## 钻进去和退回来走同一条路 —— 「返回上级选中刚才那项」与「再进某层还在那项」
## 是同一个记忆机制的两个方向，不用在两处分别写要找哪个 id。
func _enter_level(target: MenuLevel) -> void:
	_remember_focus()
	_level = target
	_focus_idx = _memory_index()
	_refresh_options()


## 把当前层的选中项记进记忆（离开该层、交棒给子页面时调用）。
func _remember_focus() -> void:
	_focus_memory[int(_level)] = _focus_idx


## 当前层记忆里的选中项。没有记忆 → 0；记忆越界（选项表变了，如终端未解锁 /
## 支线列表为空导致「资料」被隐藏）→ 收敛到合法范围。
func _memory_index() -> int:
	var opts := _get_current_options()
	if opts.is_empty():
		return 0
	if not _focus_memory.has(int(_level)):
		return 0
	return clampi(int(_focus_memory[int(_level)]), 0, opts.size() - 1)


## 交出控制权给子页面（设置 / 地图 / 日历）：记下回来该回哪一层、哪一项，
## 然后立刻隐藏 —— 后续由子页面的滑入接管画面。
func _hand_off_to_subpage() -> void:
	_remember_focus()
	_return_level = _level
	_has_return_level = true
	_is_open = false
	visible = false
	close_requested.emit()


# ===================================================================
# 返回标题确认对话框
# ===================================================================

func _build_confirm_dialog() -> void:
	# ── 额外暗化层（叠加在现有 DarkenBg 之上）──
	var confirm_dim := ColorRect.new()
	confirm_dim.name = "ConfirmDim"
	confirm_dim.color = Color(0, 0, 0, 0.3)
	confirm_dim.modulate.a = 0.0
	confirm_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	confirm_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	confirm_dim.gui_input.connect(_on_confirm_dim_clicked)
	add_child(confirm_dim)

	# ── 中央 Band（clip_contents 使子元素随 scaleX 自然裁剪）──
	var band := Control.new()
	_confirm_band = band
	band.name = "ConfirmBand"
	band.set_anchors_preset(Control.PRESET_FULL_RECT)
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	band.clip_contents = true
	band.visible = false
	add_child(band)

	var band_bg := ColorRect.new()
	band_bg.name = "BandBg"
	band_bg.color = Color(0, 0, 0, 0.95)
	band_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	band_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	band.add_child(band_bg)

	var top_border := ColorRect.new()
	top_border.name = "TopBorder"
	top_border.color = Color(1, 1, 1, 0.2)
	top_border.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top_border.offset_bottom = 2.0
	top_border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	band.add_child(top_border)

	var bottom_border := ColorRect.new()
	bottom_border.name = "BottomBorder"
	bottom_border.color = Color(1, 1, 1, 0.2)
	bottom_border.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom_border.offset_top = -2.0
	bottom_border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	band.add_child(bottom_border)

	# ── 品牌框 "Confirm" + "确认" ──
	var vp_h: float = get_viewport().get_visible_rect().size.y
	var branding := Control.new()
	branding.name = "ConfirmBranding"
	branding.position = Vector2(48, vp_h / 2.0 - BAND_PAD - 48)
	branding.mouse_filter = Control.MOUSE_FILTER_IGNORE
	band.add_child(branding)

	var shadow := ColorRect.new()
	shadow.name = "Shadow"
	shadow.color = Color(1, 1, 1, 0.1)
	shadow.position = Vector2(10, 10)
	shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	branding.add_child(shadow)

	var box_bg := ColorRect.new()
	box_bg.name = "BoxBg"
	box_bg.color = Color.WHITE
	box_bg.size = Vector2(260, 156)
	box_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	branding.add_child(box_bg)
	shadow.size = box_bg.size

	var en_title := Label.new()
	en_title.name = "EnTitle"
	en_title.text = "Confirm"
	en_title.add_theme_color_override("font_color", Color.BLACK)
	en_title.add_theme_font_size_override("font_size", 72)
	en_title.position = Vector2(14, 16)
	en_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if GameManager.font_tcm: en_title.add_theme_font_override("font", GameManager.font_tcm)
	branding.add_child(en_title)

	var zh_title := Label.new()
	zh_title.name = "ZhTitle"
	zh_title.text = "" if GameManager.is_locale("en") else tr("确认")
	zh_title.add_theme_color_override("font_color", Color.BLACK)
	zh_title.add_theme_font_size_override("font_size", 32)
	zh_title.position = Vector2(20, 104)
	zh_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if GameManager.font_zh_title: zh_title.add_theme_font_override("font", GameManager.font_zh_title)
	branding.add_child(zh_title)

	# ── 问题文本 ──
	var question := Label.new()
	question.name = "ConfirmQuestion"
	question.text = tr("是否退出？未保存的游戏将在退出后作废。")
	question.position = Vector2(48, vp_h - BAND_PAD - 48)
	question.add_theme_color_override("font_color", Color(1, 1, 1, 0.8))
	question.add_theme_font_size_override("font_size", 28)
	question.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if GameManager.font_zh_body: question.add_theme_font_override("font", GameManager.font_zh_body)
	band.add_child(question)

	# ── 选项 VBoxContainer ──
	var opt_container := VBoxContainer.new()
	opt_container.name = "ConfirmOptions"
	opt_container.alignment = BoxContainer.ALIGNMENT_CENTER
	var vp_w: float = get_viewport().get_visible_rect().size.x
	opt_container.position = Vector2(vp_w - 520, vp_h / 2.0 - OptionRow.ROW_HEIGHT)
	opt_container.custom_minimum_size = Vector2(480, OptionRow.ROW_HEIGHT * CONFIRM_OPTIONS.size())
	opt_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	band.add_child(opt_container)

	for i: int in range(CONFIRM_OPTIONS.size()):
		var data: Dictionary = CONFIRM_OPTIONS[i]
		var item: Control = _make_confirm_option(i, data)
		opt_container.add_child(item)
		_confirm_option_nodes.append(item)

	# 初始隐藏确认 UI（band 和 dim；band 子元素随之不可见）
	_confirm_band.visible = false
	confirm_dim.visible = false


func _make_confirm_option(index: int, data: Dictionary) -> OptionRow:
	var zh_text: String = "" if GameManager.is_locale("en") else tr(data.label)
	var row := OptionRow.new()
	row.setup(index, data.title, zh_text, GameManager.font_tcm, GameManager.font_zh_title, 480.0)
	row.hovered.connect(_on_confirm_option_hovered)
	row.activated.connect(_on_confirm_option_activated)
	return row


func _show_confirm() -> void:
	_confirm_active = true
	_confirm_sel = 1
	_confirm_interactive = false
	# 取消后要回到打开确认框之前的那一项（就是刚才按下的「返回标题」），
	# 这里先把 SYSTEM 层的选择钉进记忆 —— 否则取消后焦点会被改写，
	# 连带污染「再进 System 该选哪一项」的记忆。
	_remember_focus()

	# ── 初始状态 ──
	# ConfirmDim（sibling）从透明开始，入场时淡入
	var confirm_dim := get_node_or_null("ConfirmDim") as ColorRect
	if confirm_dim:
		confirm_dim.modulate.a = 0.0
		confirm_dim.visible = true

	# Band 从右侧缩放到 0（pivot 在右边缘），子元素随之裁剪
	_confirm_band.pivot_offset.x = _confirm_band.size.x
	_confirm_band.scale.x = 0.0
	_confirm_band.visible = true

	# Branding 右移 + 透明（restore targets 在动画中反向 tween）
	var branding := _confirm_band.get_node_or_null("ConfirmBranding") as Control
	var brand_rest_x: float = branding.position.x if branding else 0.0
	if branding:
		branding.position.x += 50.0
		branding.modulate.a = 0.0

	# Question 右移 + 透明
	var question := _confirm_band.get_node_or_null("ConfirmQuestion") as Label
	var q_rest_x: float = question.position.x if question else 0.0
	if question:
		question.position.x += 50.0
		question.modulate.a = 0.0

	# Footer 透明
	var footer := _confirm_band.get_node_or_null("ConfirmFooter") as Label
	if footer:
		footer.modulate.a = 0.0

	# ── 阶段 1：Dim 淡入 + Band 展开（并行，0.35s）──
	var t_main := create_tween().set_parallel(true)
	t_main.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	if confirm_dim:
		t_main.tween_property(confirm_dim, "modulate:a", 1.0, 0.35)
	t_main.tween_property(_confirm_band, "scale:x", 1.0, 0.45).from(0.0)

	# ── 阶段 2：Branding 滑入（延迟 0.15s，0.45s）──
	if branding:
		var t_brand := create_tween().set_parallel(true)
		t_brand.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
		t_brand.tween_property(branding, "position:x", brand_rest_x, 0.45).set_delay(0.15)
		t_brand.tween_property(branding, "modulate:a", 1.0, 0.45).set_delay(0.15)

	# ── 阶段 3：Question 滑入（延迟 0.25s，0.45s）──
	if question:
		var t_q := create_tween().set_parallel(true)
		t_q.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
		t_q.tween_property(question, "position:x", q_rest_x, 0.45).set_delay(0.25)
		t_q.tween_property(question, "modulate:a", 1.0, 0.45).set_delay(0.25)

	# ── 阶段 4：Options 逐行错峰入场（OptionRow.play_intro，延迟 0.35 + i*0.08）──
	for i: int in range(_confirm_option_nodes.size()):
		var d: float = 0.35 + i * 0.08
		_confirm_option_nodes[i].play_intro(d)

	# ── 阶段 5：Footer 淡入（延迟 0.45s）──
	if footer:
		var t_ft := create_tween()
		t_ft.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
		t_ft.tween_property(footer, "modulate:a", 1.0, 0.3).set_delay(0.45)

	# ── 收尾：入场结束后应用焦点 → 启用交互（焦点与入场 tween 串行防争抢）──
	var row_intro_end: float = 0.35 + float(_confirm_option_nodes.size() - 1) * 0.08 + OptionRow.INTRO_SLIDE_DURATION
	var t_final := create_tween()
	t_final.tween_callback(_update_confirm_focus).set_delay(row_intro_end + 0.05)
	t_final.tween_callback(_enable_confirm_interaction)


## 退场动画 — 入场的反向：元素按出场相反顺序逐级右滑 + 淡出
func _hide_confirm(on_done: Callable) -> void:
	_confirm_interactive = false

	# 立刻杀死焦点动画，防止退出时焦点动画继续运行
	for w: OptionRow in _confirm_option_nodes:
		w.kill_focus_anim()

	var confirm_dim := get_node_or_null("ConfirmDim") as ColorRect
	var branding := _confirm_band.get_node_or_null("ConfirmBranding") as Control
	var question := _confirm_band.get_node_or_null("ConfirmQuestion") as Label
	var footer := _confirm_band.get_node_or_null("ConfirmFooter") as Label

	# ── 阶段 1：Footer 先走（t=0，0.15s）──
	if footer:
		var t_ft := create_tween()
		t_ft.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_IN)
		t_ft.tween_property(footer, "modulate:a", 0.0, 0.15)

	# ── 阶段 2：Options 逐行反向滑出（No→Yes，错峰 0.07s，0.25s）──
	for i: int in range(_confirm_option_nodes.size() - 1, -1, -1):
		var w: Control = _confirm_option_nodes[i]
		var d: float = 0.05 + (_confirm_option_nodes.size() - 1 - i) * 0.07
		var ti := create_tween().set_parallel(true)
		ti.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_IN)
		ti.tween_property(w, "position:x", 80.0, 0.25).set_delay(d)
		ti.tween_property(w, "modulate:a", 0.0, 0.25).set_delay(d)

	# ── 阶段 3：Question 右滑 + 淡出（delay 0.20s，0.25s）──
	if question:
		var q_rest: float = question.position.x
		var t_q := create_tween().set_parallel(true)
		t_q.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_IN)
		t_q.tween_property(question, "position:x", q_rest + 50.0, 0.25).set_delay(0.20)
		t_q.tween_property(question, "modulate:a", 0.0, 0.25).set_delay(0.20)

	# ── 阶段 4：Branding 右滑 + 淡出（delay 0.28s，0.25s）──
	if branding:
		var b_rest: float = branding.position.x
		var t_b := create_tween().set_parallel(true)
		t_b.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_IN)
		t_b.tween_property(branding, "position:x", b_rest + 50.0, 0.25).set_delay(0.28)
		t_b.tween_property(branding, "modulate:a", 0.0, 0.25).set_delay(0.28)

	# ── 阶段 5：Band 收缩 + Dim 淡出（delay 0.36s，收束）──
	var t_close := create_tween().set_parallel(true)
	t_close.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_IN)
	if confirm_dim:
		t_close.tween_property(confirm_dim, "modulate:a", 0.0, 0.2).set_delay(0.36)
	t_close.tween_property(_confirm_band, "scale:x", 0.0, 0.25).set_delay(0.36)
	t_close.tween_callback(_on_confirm_hidden).set_delay(0.36 + 0.25)
	t_close.tween_callback(on_done).set_delay(0.36 + 0.25)


func _on_confirm_hidden() -> void:
	_confirm_active = false
	_confirm_band.visible = false
	var confirm_dim := get_node_or_null("ConfirmDim") as ColorRect
	if confirm_dim:
		confirm_dim.visible = false

	# 重置退出动画中偏移的位置，确保下次入场从正确位置开始
	var branding := _confirm_band.get_node_or_null("ConfirmBranding") as Control
	if branding:
		branding.position.x -= 50.0
	var question := _confirm_band.get_node_or_null("ConfirmQuestion") as Label
	if question:
		question.position.x -= 50.0
	for w: OptionRow in _confirm_option_nodes:
		w.reset_visual_state()


func _enable_confirm_interaction() -> void:
	_confirm_interactive = true


func _handle_confirm_input(event: InputEvent) -> void:
	if not _confirm_interactive:
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("ui_up") or event.is_action_pressed("ui_left"):
		_confirm_sel = 0
		_update_confirm_focus()
		_play_click()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_down") or event.is_action_pressed("ui_right"):
		_confirm_sel = 1
		_update_confirm_focus()
		_play_click()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		_play_click()
		if _confirm_sel == 0:
			_hide_confirm(_on_confirm_yes)
		else:
			_hide_confirm(_on_confirm_no)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel"):
		_play_click()
		_hide_confirm(_on_confirm_no)
		get_viewport().set_input_as_handled()


func _update_confirm_focus() -> void:
	for i: int in range(_confirm_option_nodes.size()):
		_confirm_option_nodes[i].apply_focus_state(i == _confirm_sel)


func _on_confirm_option_hovered(index: int) -> void:
	if not _confirm_interactive: return
	if _confirm_sel != index:
		_confirm_sel = index
		_update_confirm_focus()
		_play_click()


func _on_confirm_option_activated(index: int) -> void:
	if not _confirm_interactive: return
	_play_click()
	if index == 0:
		_hide_confirm(_on_confirm_yes)
	else:
		_hide_confirm(_on_confirm_no)


func _on_confirm_dim_clicked(event: InputEvent) -> void:
	if not _confirm_interactive: return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_play_click()
		_hide_confirm(_on_confirm_no)


func _on_confirm_yes() -> void:
	_is_open = false
	visible = false
	back_to_title.emit()


func _on_confirm_no() -> void:
	# 取消 → 回到打开确认框之前选中的那一项（记忆里的值），而不是写死跳到「返回菜单」
	_focus_idx = _memory_index()
	_update_focus()
