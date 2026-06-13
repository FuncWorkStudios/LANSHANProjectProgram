# meow_mcp_bridge.gd -- Game-side MCP bridge companion autoload
# Runs in the GAME process. Receives commands from editor via EngineDebugger,
# executes input injection and viewport capture, sends results back.
extends Node

# Log file forwarding: read game's log file and forward new lines via debugger channel
const LOG_POLL_INTERVAL: float = 0.2  # 200ms polling for sub-1s capture
var _log_file_path: String = ""
var _log_read_pos: int = 0
var _log_poll_timer: float = 0.0

func _ready():
	if not EngineDebugger.is_active():
		queue_free()
		return
	EngineDebugger.register_message_capture("meow_mcp", _on_message)
	EngineDebugger.send_message("meow_mcp:ready", [])

	# Initialize log file reader: resolve path and seek to end of current file
	_log_file_path = OS.get_user_data_dir().path_join("logs/godot.log")
	if FileAccess.file_exists(_log_file_path):
		var f = FileAccess.open(_log_file_path, FileAccess.READ)
		if f:
			f.seek_end(0)
			_log_read_pos = f.get_position()
			f.close()
	set_process(true)

func _process(delta: float) -> void:
	_log_poll_timer += delta
	if _log_poll_timer < LOG_POLL_INTERVAL:
		return
	_log_poll_timer = 0.0
	_forward_new_log_lines()

func _forward_new_log_lines() -> void:
	if _log_file_path.is_empty() or not FileAccess.file_exists(_log_file_path):
		return
	var f = FileAccess.open(_log_file_path, FileAccess.READ)
	if f == null:
		return
	var file_len = f.get_length()
	if file_len <= _log_read_pos:
		f.close()
		return
	f.seek(_log_read_pos)
	var new_text = f.get_buffer(file_len - _log_read_pos).get_string_from_utf8()
	_log_read_pos = file_len
	f.close()
	var lines = new_text.split("\n", false)
	if lines.is_empty():
		return
	var texts: Array = []
	var levels: Array = []
	for line in lines:
		var level: String = "info"
		if line.begins_with("ERROR:") or line.begins_with("   at:") or line.begins_with("   GDScript backtrace"):
			level = "error"
		elif line.begins_with("WARNING:"):
			level = "warning"
		texts.append(line)
		levels.append(level)
	EngineDebugger.send_message("meow_mcp:game_log", [texts, levels])

func _exit_tree():
	if EngineDebugger.is_active():
		EngineDebugger.unregister_message_capture("meow_mcp")

func _on_message(message: String, data: Array) -> bool:
	match message:
		"inject_key":
			return _inject_key(data)
		"inject_mouse_click":
			_inject_mouse_click(data)
			return true
		"inject_mouse_move":
			return _inject_mouse_move(data)
		"inject_mouse_scroll":
			return _inject_mouse_scroll(data)
		"inject_action":
			return _inject_action(data)
		"capture_viewport":
			return _capture_viewport()
		"click_node":
			_handle_click_node(data)
			return true
		"get_node_rect":
			return _handle_get_node_rect(data)
		"get_node_property":
			return _handle_get_node_property(data)
		"eval_in_game":
			return _handle_eval_in_game(data)
		"get_game_scene_tree":
			return _handle_get_game_scene_tree(data)
		"inject_sequence":
			_handle_inject_sequence(data)
			return true
		"inject_text":
			_handle_inject_text(data)
			return true
	return false

func _inject_key(data: Array) -> bool:
	var keycode_str: String = data[0]
	var pressed: bool = data[1]
	var event = InputEventKey.new()
	event.keycode = OS.find_keycode_from_string(keycode_str)
	event.physical_keycode = event.keycode
	event.pressed = pressed
	Input.parse_input_event(event)
	EngineDebugger.send_message("meow_mcp:input_result", [true, ""])
	return true

func _inject_mouse_click(data: Array) -> void:
	var x: float = data[0]
	var y: float = data[1]
	var button_str: String = data[2]
	var auto_cycle: bool = data[3] if data.size() > 3 and data[3] is bool and data[3] == true else false
	var button_map = {
		"left": MOUSE_BUTTON_LEFT,
		"right": MOUSE_BUTTON_RIGHT,
		"middle": MOUSE_BUTTON_MIDDLE
	}
	var btn = button_map.get(button_str, MOUSE_BUTTON_LEFT)

	if auto_cycle:
		# Press
		var press_event = InputEventMouseButton.new()
		press_event.position = Vector2(x, y)
		press_event.global_position = Vector2(x, y)
		press_event.button_index = btn
		press_event.pressed = true
		Input.parse_input_event(press_event)

		# 50ms delay
		await get_tree().create_timer(0.05).timeout

		# Release
		var release_event = InputEventMouseButton.new()
		release_event.position = Vector2(x, y)
		release_event.global_position = Vector2(x, y)
		release_event.button_index = btn
		release_event.pressed = false
		Input.parse_input_event(release_event)

		EngineDebugger.send_message("meow_mcp:input_result", [true, ""])
	else:
		# Original single-fire behavior (data[3] is pressed bool)
		var pressed: bool = data[3]
		var event = InputEventMouseButton.new()
		event.position = Vector2(x, y)
		event.global_position = Vector2(x, y)
		event.button_index = btn
		event.pressed = pressed
		Input.parse_input_event(event)
		EngineDebugger.send_message("meow_mcp:input_result", [true, ""])

func _inject_mouse_move(data: Array) -> bool:
	var x: float = data[0]
	var y: float = data[1]
	var event = InputEventMouseMotion.new()
	event.position = Vector2(x, y)
	event.global_position = Vector2(x, y)
	Input.parse_input_event(event)
	EngineDebugger.send_message("meow_mcp:input_result", [true, ""])
	return true

func _inject_mouse_scroll(data: Array) -> bool:
	var x: float = data[0]
	var y: float = data[1]
	var direction_str: String = data[2]
	var event = InputEventMouseButton.new()
	event.position = Vector2(x, y)
	event.global_position = Vector2(x, y)
	event.button_index = MOUSE_BUTTON_WHEEL_UP if direction_str == "up" else MOUSE_BUTTON_WHEEL_DOWN
	event.pressed = true
	Input.parse_input_event(event)
	EngineDebugger.send_message("meow_mcp:input_result", [true, ""])
	return true

func _inject_action(data: Array) -> bool:
	var action_name: String = data[0]
	var pressed: bool = data[1]
	var event = InputEventAction.new()
	event.action = action_name
	event.pressed = pressed
	event.strength = 1.0 if pressed else 0.0
	Input.parse_input_event(event)
	EngineDebugger.send_message("meow_mcp:input_result", [true, ""])
	return true

func _resolve_node(node_path: String) -> Node:
	var scene_root = get_tree().current_scene
	if scene_root == null:
		return null
	if node_path.is_empty():
		return scene_root
	return scene_root.get_node_or_null(node_path)

func _handle_click_node(data: Array) -> void:
	var node_path: String = data[0]
	var node = _resolve_node(node_path)

	if node == null:
		EngineDebugger.send_message("meow_mcp:click_node_result",
			[false, "Node not found: " + node_path, 0.0, 0.0])
		return

	if not (node is Control):
		EngineDebugger.send_message("meow_mcp:click_node_result",
			[false, "Node is not a Control (type: " + node.get_class() + ")", 0.0, 0.0])
		return

	if not node.is_visible_in_tree():
		EngineDebugger.send_message("meow_mcp:click_node_result",
			[false, "Node is not visible in tree", 0.0, 0.0])
		return

	var rect: Rect2 = node.get_global_rect()
	var center_x: float = rect.position.x + rect.size.x / 2.0
	var center_y: float = rect.position.y + rect.size.y / 2.0

	# Press
	var press_event = InputEventMouseButton.new()
	press_event.position = Vector2(center_x, center_y)
	press_event.global_position = Vector2(center_x, center_y)
	press_event.button_index = MOUSE_BUTTON_LEFT
	press_event.pressed = true
	Input.parse_input_event(press_event)

	# 50ms delay
	await get_tree().create_timer(0.05).timeout

	# Release
	var release_event = InputEventMouseButton.new()
	release_event.position = Vector2(center_x, center_y)
	release_event.global_position = Vector2(center_x, center_y)
	release_event.button_index = MOUSE_BUTTON_LEFT
	release_event.pressed = false
	Input.parse_input_event(release_event)

	EngineDebugger.send_message("meow_mcp:click_node_result",
		[true, "", center_x, center_y])

func _handle_get_node_rect(data: Array) -> bool:
	var node_path: String = data[0]
	var node = _resolve_node(node_path)

	if node == null:
		EngineDebugger.send_message("meow_mcp:node_rect_result",
			[false, "Node not found: " + node_path, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
		return true

	if not (node is Control):
		EngineDebugger.send_message("meow_mcp:node_rect_result",
			[false, "Node is not a Control (type: " + node.get_class() + ")",
			 0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
		return true

	if not node.is_visible_in_tree():
		EngineDebugger.send_message("meow_mcp:node_rect_result",
			[false, "Node is not visible in tree", 0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
		return true

	var rect: Rect2 = node.get_global_rect()
	var global_pos: Vector2 = node.get_global_position()
	EngineDebugger.send_message("meow_mcp:node_rect_result",
		[true, "", rect.position.x, rect.position.y, rect.size.x, rect.size.y,
		 global_pos.x, global_pos.y])
	return true

func _capture_viewport() -> bool:
	var image = get_viewport().get_texture().get_image()
	if image == null or image.is_empty():
		EngineDebugger.send_message("meow_mcp:viewport_data", ["", 0, 0])
		return true
	var png_data = image.save_png_to_buffer()
	var base64_str = Marshalls.raw_to_base64(png_data)
	EngineDebugger.send_message("meow_mcp:viewport_data",
		[base64_str, image.get_width(), image.get_height()])
	return true

# --- Phase 13: Runtime State Query handlers ---

func _handle_get_node_property(data: Array) -> bool:
	var node_path: String = data[0]
	var property_name: String = data[1]
	var node = _resolve_node(node_path)

	if node == null:
		EngineDebugger.send_message("meow_mcp:node_property_result",
			[false, "Node not found: " + node_path, "", ""])
		return true

	var prop_list = node.get_property_list()
	var found = false
	for prop in prop_list:
		if prop["name"] == property_name:
			found = true
			break

	if not found:
		EngineDebugger.send_message("meow_mcp:node_property_result",
			[false, "Property not found: " + property_name + " on node: " + node_path, "", ""])
		return true

	var value = node.get(property_name)
	var type_name = type_string(typeof(value))
	var value_str = var_to_str(value) if value != null else "null"

	EngineDebugger.send_message("meow_mcp:node_property_result",
		[true, "", value_str, type_name])
	return true

func _handle_eval_in_game(data: Array) -> bool:
	var expression_str: String = data[0]
	var expr = Expression.new()
	var error = expr.parse(expression_str)

	if error != OK:
		EngineDebugger.send_message("meow_mcp:eval_result",
			[false, "Parse error: " + expr.get_error_text(), ""])
		return true

	var result = expr.execute([], get_tree().current_scene)

	if expr.has_execute_failed():
		EngineDebugger.send_message("meow_mcp:eval_result",
			[false, "Execute error: " + expr.get_error_text(), ""])
		return true

	var result_str = var_to_str(result) if result != null else "null"
	EngineDebugger.send_message("meow_mcp:eval_result",
		[true, "", result_str])
	return true

func _handle_get_game_scene_tree(data: Array) -> bool:
	var max_depth: int = data[0]
	var scene_root = get_tree().current_scene

	if scene_root == null:
		EngineDebugger.send_message("meow_mcp:game_scene_tree_result",
			[false, "No current scene", ""])
		return true

	var tree_data = _serialize_node(scene_root, 0, max_depth)
	var json_str = JSON.stringify(tree_data)
	EngineDebugger.send_message("meow_mcp:game_scene_tree_result",
		[true, "", json_str])
	return true

func _serialize_node(node: Node, depth: int, max_depth: int) -> Dictionary:
	var result = {
		"name": node.name,
		"type": node.get_class(),
		"path": str(node.get_path()),
	}

	if node.get_script() != null:
		result["script"] = node.get_script().resource_path

	if node is Control:
		result["visible"] = node.is_visible_in_tree()
	elif node is CanvasItem:
		result["visible"] = node.is_visible_in_tree()
	elif node is Node3D:
		result["visible"] = node.is_visible_in_tree()

	if max_depth < 0 or depth < max_depth:
		var children_arr = []
		for child in node.get_children():
			children_arr.append(_serialize_node(child, depth + 1, max_depth))
		if children_arr.size() > 0:
			result["children"] = children_arr

	return result

# === Input Sequence ===

func _handle_inject_sequence(data: Array) -> void:
	var steps_json: String = data[0]
	var parsed = JSON.parse_string(steps_json)
	if parsed == null or not (parsed is Array):
		EngineDebugger.send_message("meow_mcp:input_sequence_result", [false, 0, "Invalid steps JSON"])
		return

	var steps: Array = parsed
	var executed := 0

	for step in steps:
		if not (step is Dictionary):
			continue

		if step.has("action"):
			var action_name: String = step["action"]
			var duration_ms: int = step.get("duration", 50)
			# Press
			var press_evt = InputEventAction.new()
			press_evt.action = action_name
			press_evt.pressed = true
			press_evt.strength = 1.0
			Input.parse_input_event(press_evt)
			# Hold
			await get_tree().create_timer(duration_ms / 1000.0).timeout
			# Release
			var release_evt = InputEventAction.new()
			release_evt.action = action_name
			release_evt.pressed = false
			release_evt.strength = 0.0
			Input.parse_input_event(release_evt)
			executed += 1

		elif step.has("key"):
			var keycode_str: String = step["key"]
			var duration_ms: int = step.get("duration", 50)
			var key_event = InputEventKey.new()
			key_event.keycode = OS.find_keycode_from_string(keycode_str)
			key_event.physical_keycode = key_event.keycode
			key_event.pressed = true
			Input.parse_input_event(key_event)
			await get_tree().create_timer(duration_ms / 1000.0).timeout
			var release_key = InputEventKey.new()
			release_key.keycode = key_event.keycode
			release_key.physical_keycode = key_event.keycode
			release_key.pressed = false
			Input.parse_input_event(release_key)
			executed += 1

		elif step.has("mouse"):
			var mouse_action: String = step["mouse"]
			var pos = Vector2.ZERO
			if step.has("position") and step["position"] is Dictionary:
				pos = Vector2(step["position"].get("x", 0), step["position"].get("y", 0))
			if mouse_action == "click":
				var btn = MOUSE_BUTTON_LEFT
				var press_m = InputEventMouseButton.new()
				press_m.position = pos
				press_m.global_position = pos
				press_m.button_index = btn
				press_m.pressed = true
				Input.parse_input_event(press_m)
				await get_tree().create_timer(0.05).timeout
				var release_m = InputEventMouseButton.new()
				release_m.position = pos
				release_m.global_position = pos
				release_m.button_index = btn
				release_m.pressed = false
				Input.parse_input_event(release_m)
			elif mouse_action == "move":
				var move_evt = InputEventMouseMotion.new()
				move_evt.position = pos
				move_evt.global_position = pos
				Input.parse_input_event(move_evt)
			executed += 1

		elif step.has("wait"):
			var wait_ms: int = step["wait"]
			await get_tree().create_timer(wait_ms / 1000.0).timeout
			executed += 1

	EngineDebugger.send_message("meow_mcp:input_sequence_result", [true, executed, ""])

# === Text Injection ===

func _handle_inject_text(data: Array) -> void:
	var node_path: String = data[0]
	var text: String = data[1]

	var node = _resolve_node(node_path)
	if node == null:
		EngineDebugger.send_message("meow_mcp:inject_text_result",
			[false, "Node not found: " + node_path])
		return

	if node is LineEdit:
		node.text = text
		node.text_changed.emit(text)
		EngineDebugger.send_message("meow_mcp:inject_text_result", [true, ""])
	elif node is TextEdit:
		node.text = text
		node.text_changed.emit()
		EngineDebugger.send_message("meow_mcp:inject_text_result", [true, ""])
	else:
		# Try setting text property directly
		if "text" in node:
			node.set("text", text)
			EngineDebugger.send_message("meow_mcp:inject_text_result", [true, ""])
		else:
			EngineDebugger.send_message("meow_mcp:inject_text_result",
				[false, "Node '" + node_path + "' is not a text input (LineEdit/TextEdit) and has no 'text' property"])
