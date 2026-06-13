## ScriptParser : RefCounted
## Parses .txt plot scripts into PlotData resources.
## Format matches the web version's ScriptParser:
##   [Title: My Story] / [ID: my_id] — metadata
##   @bg(path)              — change background
##   @music(path)           — start looping BGM
##   @stopmusic             — stop BGM
##   @play(path)            — play SFX
##   @stopall               — stop all audio
##   @chapter(zh, en)       — chapter title
##   @ch(path)              — show character sprite
##   @glitch()              — enable glitch effect
##   // comment             — ignored
##   Name: Dialogue         — character dialogue
##   Narration text         — narration (no speaker)
##   ? Question text        — choice prompt
##   > Option -> target     — choice option
class_name ScriptParser extends RefCounted

var _plot_id: String = ""
var _title: LocText
var _characters: Dictionary = {}


func _init(plot_id: String = "", title: LocText = null) -> void:
	_plot_id = plot_id
	if title:
		_title = title
	else:
		_title = LocText.new()
		_title.ZH = "新剧本"
		_title.EN = "New Script"


func parse(raw: String) -> PlotData:
	var lines: Array[String] = []
	for line in raw.split("\n"):
		var trimmed := line.strip_edges()
		if trimmed.is_empty() or trimmed.begins_with("//") or trimmed.begins_with("#"):
			continue
		lines.append(trimmed)

	var nodes: Array[PlotNode] = []
	var last_who: String = ""

	# Metadata extraction for first few lines
	var i := 0
	while i < lines.size() and i < 5:
		var meta_regex := RegEx.new()
		meta_regex.compile("\\[(Title|ID):\\s*(.*)\\]")
		var meta_match := meta_regex.search(lines[i])
		if meta_match:
			var key: String = meta_match.get_string(1).to_lower()
			var val: String = meta_match.get_string(2)
			if key == "title":
				_title = LocText.new()
				_title.ZH = val
				_title.EN = val
			elif key == "id":
				_plot_id = val
			lines.remove_at(i)
		else:
			i += 1

	var pending_commands: Dictionary = {}

	for line in lines:
		if line.begins_with("@"):
			_parse_command(line, pending_commands)
			continue

		# Check for choice prompt
		if line.begins_with("?") and not ":" in line.substr(0, min(15, line.length())):
			var select_node := PlotNode.new()
			select_node.type = "select"
			select_node.ZH = line.substr(1).strip_edges()
			select_node.EN = select_node.ZH
			select_node.options = []
			_apply_commands(select_node, pending_commands)
			nodes.append(select_node)
			pending_commands.clear()
			continue

		# Check for choice option
		if line.begins_with(">") and nodes.size() > 0:
			var last_node := nodes[nodes.size() - 1]
			if last_node.type == "select":
				var opt_regex := RegEx.new()
				opt_regex.compile(">\\s*(.*?)\\s*->\\s*(.*)")
				var opt_match := opt_regex.search(line)
				if opt_match:
					var label: String = opt_match.get_string(1).strip_edges()
					var target: String = opt_match.get_string(2).strip_edges()
					var option := PlotOption.new()
					option.ZH = label
					option.EN = label

					if "@" in target:
						var parts := target.split("@")
						option.target_plot_id = parts[0]
						if parts.size() > 1 and parts[1].is_valid_int():
							option.target_node_index = parts[1].to_int()
					elif target.is_valid_int():
						option.target_node_index = target.to_int()

					last_node.options.append(option)
					continue

		# Dialogue or Narration
		var who: String = ""
		var text: String = line

		var colon_idx := line.find(":")
		if colon_idx > 0 and colon_idx < 15:
			who = line.substr(0, colon_idx).strip_edges()
			text = line.substr(colon_idx + 1).strip_edges()
		elif line.begins_with("："):
			# Full-width colon — still narration
			text = line.substr(1).strip_edges()

		var node := PlotNode.new()
		node.ZH = text
		node.EN = text
		node.who = who
		node.type = "text"
		_apply_commands(node, pending_commands)

		# Handle character logic
		if who.is_empty():
			# Narration: clear character if someone was speaking
			if not last_who.is_empty() and node.ch.is_empty():
				node.ch = "__CLEAR__"  # Signal to clear character
			last_who = ""
		else:
			# Dialogue: show character if new speaker
			if who != last_who and node.ch.is_empty():
				node.ch = who
			last_who = who

		nodes.append(node)
		pending_commands.clear()

	# Handle leftover commands at end
	if not pending_commands.is_empty():
		var leftover := PlotNode.new()
		leftover.ZH = ""
		leftover.EN = ""
		leftover.type = "scene"
		_apply_commands(leftover, pending_commands)
		nodes.append(leftover)

	var data := PlotData.new()
	data.id = _plot_id
	data.title = _title
	data.characters = _characters
	data.nodes = nodes
	return data


func _parse_command(line: String, pending: Dictionary) -> void:
	var cmd_regex := RegEx.new()
	cmd_regex.compile("@(\\w+)\\((.*)\\)")
	var cmd_match := cmd_regex.search(line)

	if cmd_match:
		var cmd: String = cmd_match.get_string(1).to_lower()
		var params: String = cmd_match.get_string(2)
		var args: Array[String] = []
		for a in params.split(","):
			args.append(a.strip_edges())

		match cmd:
			"bg":
				if args.size() > 0:
					pending["bg"] = args[0]
			"music":
				if args.size() > 0:
					var bgm_cmd := AudioCommand.new()
					bgm_cmd.play = args[0]
					bgm_cmd.loop = true
					bgm_cmd.audio_type = "bgm"
					pending["bgm"] = bgm_cmd
			"stopmusic":
				var stop_cmd := AudioCommand.new()
				stop_cmd.stop = true
				pending["bgm"] = stop_cmd
			"play":
				if args.size() > 0:
					var sfx_cmd := AudioCommand.new()
					sfx_cmd.play = args[0]
					sfx_cmd.audio_type = "sfx"
					pending["sfx"] = sfx_cmd
			"stopall":
				var stop_bgm := AudioCommand.new()
				stop_bgm.stop = true
				pending["bgm"] = stop_bgm
				var stop_sfx := AudioCommand.new()
				stop_sfx.stop = true
				pending["sfx"] = stop_sfx
			"chapter":
				var chapter_loc := LocText.new()
				chapter_loc.ZH = args[0] if args.size() > 0 else ""
				chapter_loc.EN = args[1] if args.size() > 1 else args[0] if args.size() > 0 else ""
				pending["chapter"] = chapter_loc
			"ch":
				if args.size() > 1:
					pending["ch"] = args[1]
				elif args.size() > 0:
					pending["ch"] = args[0]
			"glitch":
				pending["glitch"] = true
			"wait":
				if args.size() > 0 and args[0].is_valid_float():
					pending["wait_time"] = args[0].to_float()
	else:
		# No-arg commands
		var bare := line.strip_edges().to_lower()
		if bare == "@glitch":
			pending["glitch"] = true
		elif bare == "@stopmusic":
			var stop_cmd := AudioCommand.new()
			stop_cmd.stop = true
			pending["bgm"] = stop_cmd
		elif bare == "@stopall":
			var stop_bgm := AudioCommand.new()
			stop_bgm.stop = true
			pending["bgm"] = stop_bgm
			var stop_sfx := AudioCommand.new()
			stop_sfx.stop = true
			pending["sfx"] = stop_sfx


func _apply_commands(node: PlotNode, commands: Dictionary) -> void:
	for key in commands:
		var val = commands[key]
		match key:
			"bg":
				node.bg = val
			"bgm":
				node.bgm = val
			"sfx":
				node.sfx = val
			"chapter":
				node.chapter = val
			"ch":
				node.ch = val
			"glitch":
				node.glitch = val
			"wait_time":
				node.wait_time = val
