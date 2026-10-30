## PlotData : Resource
## 包含完整解析的剧情脚本，包含角色、标题和节点序列。
class_name PlotData extends Resource

@export var id: String = ""
@export var title: LocText
@export var characters: Dictionary = {}
@export var nodes: Array[PlotNode] = []

## label 名 → node_index 的快速查找表（解析期填入）
@export var labels: Dictionary = {}


## 解析说话者的显示名（姓名框 / 日志共用）。
## 约定：who 非空时保证返回非空字符串 —— 角色表缺字段就逐级回退，
## 否则姓名框会出现"角色明明定义了却一片空白"。
## @param who: 剧本里写的说话者（可能是角色 id、"我" 或 "player"）
## @param language: 区域设置标识（"zh" / "en" / "zh_CN" 等）
func get_character_name(who: String, language: String) -> String:
	var key: String = who.strip_edges()
	if key.is_empty():
		return ""
	var is_zh: bool = language.begins_with("zh")
	if key == "player" or key == "我":
		var player: String = GameManager.player_name.strip_edges()
		return player if not player.is_empty() else key
	var display: String = _display_name_of(characters.get(key, null), is_zh)
	if display.is_empty():
		return key     # 回退到 id 本身，绝不返回空串
	return display


## 从角色表条目取显示名。
## 条目允许两种形态：LocText（显示名）或 String（立绘路径 — 旧数据格式，无显示名）。
## LocText 缺当前语言时回退另一种语言，再回退 ZH 的译文。
func _display_name_of(entry: Variant, is_zh: bool) -> String:
	var loc: LocText = entry as LocText
	if loc:
		var primary: String = loc.ZH if is_zh else loc.EN
		var secondary: String = loc.EN if is_zh else loc.ZH
		var text: String = primary.strip_edges()
		if text.is_empty():
			text = secondary.strip_edges()
		if text.is_empty() and not loc.ZH.is_empty():
			text = TranslationServer.translate(loc.ZH).strip_edges()
		return text
	# String 条目是立绘路径（历史格式），不含显示名
	return ""
