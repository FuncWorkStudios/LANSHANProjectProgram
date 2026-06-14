## AudioCommand : Resource
## Describes an audio play/stop command within a plot node.
class_name AudioCommand extends Resource

@export var play: String = ""
@export var stop: bool = false
@export var loop: bool = false
@export var audio_type: String = ""

## Crossfade duration — when > 0, crossfade instead of immediate switch.
## fade_out is the duration to fade OUT current BGM, fade_in for the new track.
@export var crossfade: bool = false
@export var fade_out_duration: float = 1.5
@export var fade_in_duration: float = 1.5

## Fade-out-only mode: when set, fade out current BGM without starting a new track.
@export var fade_out_only: bool = false

## Ambience layer volume (0.0–1.0), used when audio_type == "ambience".
@export var ambience_volume: float = 0.5
