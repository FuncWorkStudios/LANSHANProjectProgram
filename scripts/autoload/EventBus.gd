## EventBus : Node (Autoload)
## 场景间解耦通信的全局信号中心。
## 用法：EventBus.scene_changed.emit("TITLE")
extends Node

# --- 场景管理 ---
@warning_ignore("unused_signal")
signal scene_changed(scene_name: String)

# --- 游戏性 ---
# (plot_loaded, node_advanced, choice_made reserved for future use)

# --- 地点 ---
@warning_ignore("unused_signal")
signal location_changed(location_name: String)

# --- 音频 ---
# (audio_unlock_requested reserved for future use)

# --- 共享背景 ---
@warning_ignore("unused_signal")
signal shared_background_updated(bg_path: String)
@warning_ignore("unused_signal")
signal bg_blur_toggle(enable: bool)
@warning_ignore("unused_signal")
signal bg_darken_toggle(enable: bool)
@warning_ignore("unused_signal")
signal bg_parallax_offset(x: float)
## 叠加层（退出确认等）让背景后退/还原：factor 是相对基础缩放的倍率（1.0 = 原样）
@warning_ignore("unused_signal")
signal bg_zoom(factor: float)

# --- 成就 ---
@warning_ignore("unused_signal")
signal achievement_unlocked(achievement_id: String)

# --- VN 特定 ---
@warning_ignore("unused_signal")
signal character_changed(character_path: String)
@warning_ignore("unused_signal")
signal background_changed(bg_path: String)
