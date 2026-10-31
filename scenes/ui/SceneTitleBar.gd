## SceneTitleBar : RefCounted
## 统一标题栏样式 —— 左侧 72px 英文大标题，右侧基线对齐的中文副标题，可选 1px 细线。
## 以「装饰已有 TitleLabel」的方式工作：中文副标题与细线都是标题 Label 的子节点，
## 因此自动跟随标题的 modulate / position 一起淡入淡出，各场景的入场动画不用改。
##   const TITLE_BAR = preload("res://scenes/ui/SceneTitleBar.gd")
##   TITLE_BAR.apply(_title_label, "Config", "设置",
##       GameManager.font_tcm, GameManager.font_zh_title, 1152.0)
## EN 语言下中文副标题隐藏（与设置页左栏分类项一致）；切语言后重新调用一次即可（幂等）。
## 细线宽度传 0 表示不画 —— 内容紧贴标题的场景（关于页 / 三个画廊）用它们自己的副标题。
## 字体由调用方注入：静态工具不直接读 GameManager，避免依赖自动加载单例的可用时机。
class_name SceneTitleBar
extends RefCounted

# ── Constants ──────────────────────────────────────────

const TITLE_FONT_SIZE: int = 72
const ZH_FONT_SIZE: int = 26
## 中文副标题与大标题文本之间的水平间距。
const ZH_GAP: float = 20.0
## 细线在大标题下方多远。
const RULE_GAP: float = 18.0
const ZH_COLOR: Color = Color(1, 1, 1, 0.55)
const RULE_COLOR: Color = Color(1, 1, 1, 0.12)

const ZH_NODE: String = "TitleZh"
const RULE_NODE: String = "TitleRule"


# ── Public API ─────────────────────────────────────────

## 套用标题栏样式。幂等：重复调用只会更新文字 / 可见性 / 位置。
## p_title 为场景里已有的英文大标题 Label；p_zh 为右侧中文副标题；
## p_rule_width > 0 时在标题下方画一条该宽度的 1px 细线（从标题左缘往右量）。
static func apply(p_title: Label, p_en: String, p_zh: String,
		p_title_font: Font, p_zh_font: Font, p_rule_width: float = 0.0) -> void:
	p_title.text = p_en
	p_title.add_theme_font_size_override("font_size", TITLE_FONT_SIZE)
	p_title.add_theme_color_override("font_color", Color.WHITE)
	if p_title_font:
		p_title.add_theme_font_override("font", p_title_font)

	var zh: Label = p_title.get_node_or_null(ZH_NODE) as Label
	if zh == null:
		zh = Label.new()
		zh.name = ZH_NODE
		zh.mouse_filter = Control.MOUSE_FILTER_IGNORE
		zh.add_theme_font_size_override("font_size", ZH_FONT_SIZE)
		zh.add_theme_color_override("font_color", ZH_COLOR)
		p_title.add_child(zh)
	if p_zh_font:
		zh.add_theme_font_override("font", p_zh_font)

	var rule: ColorRect = p_title.get_node_or_null(RULE_NODE) as ColorRect
	if p_rule_width > 0.0 and rule == null:
		rule = ColorRect.new()
		rule.name = RULE_NODE
		rule.color = RULE_COLOR
		rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p_title.add_child(rule)

	# TranslationServer 是引擎级单例，静态函数里可安全访问（不经过 GameManager）
	var show_zh: bool = not p_zh.is_empty() and not TranslationServer.get_locale().begins_with("en")
	_layout(p_title, zh, rule, p_zh, show_zh, p_rule_width)


# ── 内部 ───────────────────────────────────────────────

static func _layout(p_title: Label, p_zh: Label, p_rule: ColorRect,
		p_zh_text: String, p_show_zh: bool, p_rule_width: float) -> void:
	# 标题文本尺寸（与 tscn 里给标题的 400×72 rect 无关，取的是实际文本宽）
	var title_size: Vector2 = p_title.get_minimum_size()

	if p_zh:
		p_zh.text = p_zh_text
		p_zh.visible = p_show_zh
		if p_show_zh:
			p_zh.size = p_zh.get_minimum_size()
			p_zh.position = Vector2(title_size.x + ZH_GAP, _baseline_offset(p_title, p_zh))

	if p_rule:
		p_rule.visible = p_rule_width > 0.0
		p_rule.position = Vector2(0.0, title_size.y + RULE_GAP)
		p_rule.size = Vector2(maxf(p_rule_width, 0.0), 1.0)


## 让中文副标题的基线与大标题基线对齐：偏移 = 大标题 ascent − 副标题 ascent。
static func _baseline_offset(p_title: Label, p_zh: Label) -> float:
	var title_font: Font = p_title.get_theme_font("font")
	var zh_font: Font = p_zh.get_theme_font("font")
	var title_ascent: float = title_font.get_ascent(TITLE_FONT_SIZE) if title_font else 0.0
	var zh_ascent: float = zh_font.get_ascent(ZH_FONT_SIZE) if zh_font else 0.0
	return title_ascent - zh_ascent
