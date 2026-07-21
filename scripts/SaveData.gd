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
@export var terminal_status: String = "locked"
@export var thumbnail: String = ""

## 运行时变量快照 — { "global": {...}, "local": {...} }
@export var variables: Dictionary = {}
