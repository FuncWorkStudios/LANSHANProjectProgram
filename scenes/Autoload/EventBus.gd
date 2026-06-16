## EventBus : Node (Autoload)
## Global signal hub for decoupled communication between scenes.
## Usage: EventBus.scene_changed.emit("TITLE")
extends Node

# --- Scene management ---
@warning_ignore("unused_signal")
signal scene_changed(scene_name: String)

# --- Gameplay ---
# (plot_loaded, node_advanced, choice_made reserved for future use)

# --- Audio ---
# (audio_unlock_requested reserved for future use)

# --- Save/Load ---
@warning_ignore("unused_signal")
signal game_saved(slot: int)
signal game_loaded(slot: int)

@warning_ignore("unused_signal")
signal settings_changed(setting_name: String, value: Variant)
@warning_ignore("unused_signal")
signal shared_background_updated(bg_path: String)
@warning_ignore("unused_signal")
signal bg_blur_toggle(enable: bool)
signal bg_darken_toggle(enable: bool)
signal bg_set_black()
signal bg_parallax_offset(x: float)

# --- VN-specific ---
signal terminal_status_changed(new_status: String)
signal character_changed(character_path: String)
signal background_changed(bg_path: String)
