## SaveData : Resource
## 表示单个存档槽位的数据。
class_name SaveData extends Resource

@export var id: String = ""
@export var timestamp: int = 0
@export var date: String = ""
@export var title: String = ""
@export var desc: String = ""
@export var player_name: String = ""
@export var plot_id: String = ""
@export var node_index: int = 0
@export var thumbnail: String = ""

## 运行时变量快照 — 存档作用域变量（save vars）
@export var variables: Dictionary = {}


## 持久化字段清单 — 存档序列化的唯一真值。
## 新增字段只需加到这里 + 上面的 @export，GameManager 的读写处不必再逐字段改。
const FIELDS: Array[String] = [
	"id", "timestamp", "date", "title", "desc",
	"player_name", "plot_id", "node_index", "thumbnail", "variables",
]


## 导出为可写进 ConfigFile 的字典。
## variables 做深拷贝，避免 ConfigFile 持有调用方字典的引用。
func to_dict() -> Dictionary:
	var out: Dictionary = {}
	for field: String in SaveData.FIELDS:
		var value: Variant = get(field)
		out[field] = value.duplicate(true) if value is Dictionary else value
	return out


## 从字典还原。缺失键保留字段默认值，因此旧存档仍可读。
static func from_dict(data: Dictionary) -> SaveData:
	var save: SaveData = SaveData.new()
	for field: String in SaveData.FIELDS:
		if data.has(field):
			save.set(field, data[field])
	return save


## 从 ConfigFile 的一个 section 还原。
static func from_config(config: ConfigFile, section: String) -> SaveData:
	var save: SaveData = SaveData.new()
	for field: String in SaveData.FIELDS:
		if config.has_section_key(section, field):
			save.set(field, config.get_value(section, field))
	return save


## 写入 ConfigFile 的一个 section。
func write_to_config(config: ConfigFile, section: String) -> void:
	for field: String in SaveData.FIELDS:
		config.set_value(section, field, get(field))
