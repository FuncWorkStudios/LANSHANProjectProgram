## AppSettings : Resource
## 应用程序范围的语言、音频、显示和游戏设置。
class_name AppSettings extends Resource

@export var language: String = "ZH"
@export var text_speed: String = "normal"
@export var master_volume: float = 1.0
@export var bgm_volume: float = 0.7
@export var sfx_volume: float = 0.8
@export var ambience_volume: float = 0.5
@export var auto_play: bool = false
@export var quality: String = "high"
@export var display_mode: String = "windowed"
@export var framerate: String = "vsync"


## 设置项的持久化 key 清单 — 唯一真值。
## 新增设置项只需加到这里 + 上面的 @export，
## GameManager 的 _load_settings / _save_settings 会自动跟上。
const KEYS: Array[String] = [
	"language", "text_speed", "master_volume", "bgm_volume", "sfx_volume",
	"ambience_volume", "auto_play", "quality", "display_mode", "framerate",
]


## 用 key 字符串读取设置值（供数据驱动的 SettingsScene 使用）。
## 仅接受 KEYS 中的键，其余返回 null —— 避免 Resource 自带属性被误读。
func get_prop(key: String) -> Variant:
	if not AppSettings.KEYS.has(key):
		return null
	return get(key)
