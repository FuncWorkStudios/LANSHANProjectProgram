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

## SFX command — long cinematic sound effect
@export var sfx: AudioCommand = null

## SFX short command — one-shot short sound effect (independent player, never blocks long SFX)
@export var sfx_short: AudioCommand = null

## Next scene to transition to (only for type "scene")
@export var next_scene: String = ""

## Wait time in seconds (0 = no wait, from @wait command)
@export var wait_time: float = 0.0

## Terminal status change
@export var set_terminal: String = ""

## Chapter title display
@export var chapter: LocText = null

## Stop transition — hide dialogue box, name box, and character for a beat
@export var stop_transition: bool = false

## Ambience command (environmental looping sound layers)
@export var ambience: AudioCommand = null

## BGM fade-out-only flag — fade out BGM without starting a new track (seconds)
@export var fade_out_bgm: float = 0.0

## Auto-jump to another plot without a choice prompt.
## When set, the VN will transition to this plot after the current node.
@export var jump_plot_id: String = ""
@export var jump_node_index: int = 0

## Fade to black: duration in seconds (>0 triggers fade-to-black overlay animation).
@export var fade_black: float = 0.0

## Back to title — emit back_requested to return to main menu.
@export var back_to_title: bool = false

## Rechoose — when true, jump back to the most recent select node
## and let the player re-choose. Used by @rechoose command.
@export var rechoose: bool = false
