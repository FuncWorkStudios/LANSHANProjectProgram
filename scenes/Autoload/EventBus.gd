## EventBus : Node (Autoload)
## Global signal hub for decoupled communication between scenes.
## Usage: EventBus.scene_changed.emit("TITLE")
extends Node

# --- Scene management ---
signal scene_changed(scene_name: String)
signal scene_transition_started(from_scene: String, to_scene: String)

# --- Gameplay ---
signal plot_loaded(plot_id: String)
signal node_advanced(node_index: int)
signal choice_made(option_index: int)

# --- Audio ---
signal audio_unlock_requested()

# --- Save/Load ---
signal game_saved(slot: int)
signal game_loaded(slot: int)
signal settings_changed(setting_name: String, value: Variant)

# --- VN-specific ---
signal terminal_status_changed(new_status: String)
signal character_changed(character_path: String)
signal background_changed(bg_path: String)
