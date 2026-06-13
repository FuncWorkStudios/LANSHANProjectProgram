## PlotNode : Resource
## A single node in the visual novel plot — dialogue, narration, choice, or scene command.
class_name PlotNode extends Resource

## Who is speaking ("" for narration, "???" for unknown)
@export var who: String = ""

## Chinese text
@export var ZH: String = ""

## English text
@export var EN: String = ""

## Background image path (sticky — persists until changed)
@export var bg: String = ""

## Character sprite path (null = clear character, empty = unchanged)
@export var ch: String = ""

## Optional note/annotation
@export var note: String = ""

## Glitch visual effect enabled
@export var glitch: bool = false

## Node type: "text", "select", or "scene"
@export var type: String = "text"

## Choice options (only for type "select")
@export var options: Array[PlotOption] = []

## Audio command (legacy format)
@export var audio: AudioCommand = null

## BGM command
@export var bgm: AudioCommand = null

## SFX command
@export var sfx: AudioCommand = null

## Next scene to transition to (only for type "scene")
@export var next_scene: String = ""

## Wait time in seconds (0 = no wait, from @wait command)
@export var wait_time: float = 0.0

## Terminal status change
@export var set_terminal: String = ""

## Chapter title display
@export var chapter: LocText = null
