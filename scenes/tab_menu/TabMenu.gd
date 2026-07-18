## TabMenu : Control
## 游戏内Tab菜单 — 重新设计以匹配 QuitConfirm 模态框风格。
## 多级菜单：主菜单 → 系统 → 配置。按Tab键打开，ESC键关闭。
class_name TabMenu
extends Control

enum MenuLevel { MAIN, SYSTEM }

signal close_requested()
signal back_to_title()
signal open_settings()
signal open_map()

# ---------------------------------------------------------------------------
# 状态
# ---------------------------------------------------------------------------
var _level: MenuLevel = MenuLevel.MAIN
var _focus_idx: int = 0
var _is_open: bool = false
var _anim_tween: Tween = null
var _entry_tweens: Array[Tween] = []


var _main_options: Array[Dictionary] = []
var _system_options: Array[Dictionary] = []

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

const OPTION_HEIGHT: float = 51.0
const BAND_PAD: float = 64.0


# ===================================================================
# 生命周期
# ===================================================================

func _ready() -> void:

	# 阻止所有输入传递到后面的界面。
	# TSCN 中已连接，代码连接作为兜底（兼容 TabMenu.new()）
	if not gui_input.is_connected(_swallow_input):
		gui_input.connect(_swallow_input)

	_setup_options()
	_apply_layout()
	_apply_fonts()


func _setup_options() -> void:
	_main_options = [
		{"id": "Item",       "name": "物品", "desc": "查看现有的物品。"},
		{"id": "Terminal",   "name": "终端", "desc": "访问终端。"},
		{"id": "Profile",    "name": "档案", "desc": "记录有关人物的背景资料。"},
		{"id": "Story",      "name": "故事", "desc": "回顾已经历过的剧情节点。"},
		{"id": "Data",       "name": "资料", "desc": "整理收集到的线索。"},
		{"id": "Map",        "name": "地图", "desc": "查看校园地图。"},
		{"id": "System",     "name": "系统", "desc": "管理游戏选项。"},
	]
	_system_options = [
		{"id": "Config",   "name": "设置",     "desc": "变更游戏设定。"},
		{"id": "Back",     "name": "返回菜单", "desc": "返回上一级菜单。"},
		{"id": "Title",    "name": "返回标题", "desc": "返回主界面。"},
	]


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

func open(terminal_status: String = "locked", _bg_path: String = "") -> void:
	_is_open = true
	_level = MenuLevel.MAIN; _focus_idx = 0

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

	_refresh_options()
	_animate_enter()


func close() -> void:
	_is_open = false
	_kill_anim()

	_anim_tween = create_tween()
	_anim_tween.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	_anim_tween.tween_property(self, "modulate:a", 0.0, 0.25)
	_anim_tween.tween_callback(_on_close_done)


func _on_close_done() -> void:
	visible = false
	close_requested.emit()


# ===================================================================
# 动画
# ===================================================================

func _animate_enter() -> void:
	visible = true
	_kill_anim()

	# 立即设置不透明状态 — 无透明效果
	_darken_overlay.color.a = 0.55
	_band.scale.x = 1.0

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

	# 在所有行完成淡入后重新应用焦点，
	# 这样第一个选项会可见地高亮显示（白色扫过+位移）。
	var focus_tween := create_tween()
	focus_tween.tween_interval(0.55)
	focus_tween.tween_callback(_update_focus)
	_entry_tweens.append(focus_tween)



# ===================================================================
# 选项
# ===================================================================

func _refresh_options() -> void:
	for c in _options_container.get_children():
		c.queue_free()

	var opts := _get_current_options()
	var vp_w: float = get_viewport().get_visible_rect().size.x
	_options_container.position = Vector2(vp_w - 520, get_viewport().get_visible_rect().size.y / 2.0 - OPTION_HEIGHT * opts.size() / 2.0)

	for i: int in range(opts.size()):
		var row := _make_row(i, opts[i])
		_options_container.add_child(row)

	_update_level_display()
	_update_focus()


func _get_current_options() -> Array[Dictionary]:
	match _level:
		MenuLevel.MAIN:    return _main_options
		MenuLevel.SYSTEM:  return _system_options
	return []


func _make_row(idx: int, data: Dictionary) -> Control:
	var row_wrap := Control.new()
	row_wrap.custom_minimum_size = Vector2(480, OPTION_HEIGHT)
	row_wrap.mouse_filter = MOUSE_FILTER_STOP

	var sweep := ColorRect.new()
	sweep.color = Color.WHITE; sweep.size = Vector2(480, OPTION_HEIGHT)
	sweep.scale.x = 0.0; sweep.mouse_filter = MOUSE_FILTER_IGNORE
	row_wrap.add_child(sweep)

	var hb := HBoxContainer.new()
	hb.size = Vector2(480, OPTION_HEIGHT); hb.alignment = BoxContainer.ALIGNMENT_END
	hb.mouse_filter = MOUSE_FILTER_IGNORE
	row_wrap.add_child(hb)

	# Spacer
	var sp := Control.new(); sp.custom_minimum_size = Vector2(16, 0); sp.mouse_filter = MOUSE_FILTER_IGNORE
	hb.add_child(sp)

	# 英文标签（始终为英文 — 设计元素）
	var id := Label.new()
	id.text = data.id
	id.add_theme_font_size_override("font_size", 42)
	id.mouse_filter = MOUSE_FILTER_IGNORE
	if GameManager.font_tcm: id.add_theme_font_override("font", GameManager.font_tcm)
	hb.add_child(id)

	var sp2 := Control.new(); sp2.custom_minimum_size = Vector2(12, 0); sp2.mouse_filter = MOUSE_FILTER_IGNORE
	hb.add_child(sp2)

	# 翻译后的标签 — 使用 tr() 以便非中文本地化模式显示正确文本
	@warning_ignore("shadowed_variable_base_class")
	var name := Label.new()
	name.text = "" if GameManager.is_locale("en") else tr(data.name)
	name.add_theme_font_size_override("font_size", 24)
	name.mouse_filter = MOUSE_FILTER_IGNORE
	@warning_ignore("static_called_on_instance")
	name.add_theme_font_override("font", GameManager.select_font(name.text, GameManager.font_zh_title, GameManager.font_tcm))
	hb.add_child(name)

	row_wrap.mouse_entered.connect(_on_hover.bind(idx))
	row_wrap.gui_input.connect(_on_click.bind(idx))
	row_wrap.set_meta("sweep", sweep)
	row_wrap.set_meta("en_label", id)
	row_wrap.set_meta("name_label", name)
	row_wrap.set_meta("option_id", data.get("id", ""))
	return row_wrap


# ===================================================================
# 层级显示
# ===================================================================

func _update_level_display() -> void:
	match _level:
		MenuLevel.MAIN:   _level_label.text = "MAIN"
		MenuLevel.SYSTEM: _level_label.text = "SYSTEM"

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
	for i: int in range(_options_container.get_child_count()):
		var row := _options_container.get_child(i) as Control
		var on := i == _focus_idx
		var sweep: ColorRect = row.get_meta("sweep")
		var en: Label = row.get_meta("en_label")
		var zh: Label = row.get_meta("name_label")

		# "终端 Terminal" 未选中时也比其他选项更亮，保持视觉突出
		var is_terminal: bool = (row.get_meta("option_id") == "Terminal")
		var unsel_alpha: float = 0.65 if is_terminal else 0.35
		var unsel_zh_color: Color = Color(1, 1, 1, 0.75) if is_terminal else Color(1, 1, 1, 0.5)

		var tw := create_tween().set_parallel(true)
		tw.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(sweep, "scale:x", 1.0 if on else 0.0, 0.25)
		tw.tween_property(row, "position:x", -50.0 if on else 10.0, 0.25)
		tw.tween_property(row, "modulate:a", 1.0 if on else unsel_alpha, 0.25)

		en.add_theme_color_override("font_color", Color.BLACK if on else Color.WHITE)
		zh.add_theme_color_override("font_color", Color(0, 0, 0, 0.6) if on else unsel_zh_color)

	_update_level_display()


# ===================================================================
# 交互
# ===================================================================

func _on_hover(idx: int) -> void:
	if _focus_idx == idx: return
	_focus_idx = idx; _update_focus(); _play_click()


func _on_click(event: InputEvent, idx: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
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
				_level = MenuLevel.SYSTEM; _focus_idx = 0; _refresh_options()
			if o.id == "Map" and confirm:
				_is_open = false
				visible = false
				open_map.emit()
		MenuLevel.SYSTEM:
			var o := _system_options[_focus_idx]
			match o.id:
				"Config":
					if confirm:
						_is_open = false
						visible = false
						open_settings.emit()
				"Back":
					if confirm: _level = MenuLevel.MAIN; _focus_idx = _main_options.size() - 1; _refresh_options()
				"Title":
					if confirm: close(); back_to_title.emit()


# ===================================================================
# 输入
# ===================================================================

func _input(event: InputEvent) -> void:
	if not _is_open or not event.is_pressed(): return
	if event.is_action_pressed("ui_cancel"):
		match _level:
			MenuLevel.SYSTEM:  _level = MenuLevel.MAIN
			MenuLevel.MAIN:    close(); get_viewport().set_input_as_handled(); return
		_focus_idx = 0; _refresh_options(); _play_click(); get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_up"):
		_focus_idx = max(0, _focus_idx - 1); _update_focus(); _play_click(); get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_down"):
		var sz := _get_current_options().size()
		_focus_idx = min(sz - 1, _focus_idx + 1); _update_focus(); _play_click(); get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_right"):
		_handle_action(1); get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_left"):
		_handle_action(-1); get_viewport().set_input_as_handled()


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
