## ScriptParser : RefCounted
## Parses .txt plot scripts into PlotData resources.
## Format matches the web version's ScriptParser:
##   [Title: My Story] / [ID: my_id] — metadata
##   @bg(path)              — change background
##   @music(path)           — start looping BGM
##   @stopmusic             — stop BGM
##   @play(path)            — play long SFX
##   @playshort(path)        — play short one-shot SFX
##   @stopall               — stop all audio
##   @chapter(zh, en)       — chapter title
##   @ch(path)              — show character sprite
##   @glitch()              — enable glitch effect
##   @rechoose()            — loop back to the most recent choice
##   // comment             — ignored
##   Name: Dialogue         — character dialogue
##   Narration text         — narration (no speaker)
##   ? Question text        — choice prompt
##   > Option -> target     — choice option
class_name ScriptParser extends RefCounted

var _plot_id: String = ""
var _title: LocText
var _characters: Dictionary = {}

# Pre-compiled regex patterns (created once, reused across all parse calls)
const META_REGEX_PATTERN: String = "\\[(Title|ID):\\s*(.*)\\]"
const OPT_REGEX_PATTERN: String = ">\\s*(.*?)\\s*->\\s*(.*)"
const CMD_REGEX_PATTERN: String = "@(\\w+)\\((.*)\\)"

var _meta_regex: RegEx
var _opt_regex: RegEx
var _cmd_regex: RegEx


func _init(plot_id: String = "", title: LocText = null) -> void:
	_plot_id = plot_id
	if title:
		_title = title
	else:
		_title = LocText.new()
		_title.ZH = "新剧本"
		_title.EN = "New Script"

	# Pre-compile regex patterns once at construction time
	_meta_regex = RegEx.new()
	_meta_regex.compile(META_REGEX_PATTERN)
	_opt_regex = RegEx.new()
	_opt_regex.compile(OPT_REGEX_PATTERN)
	_cmd_regex = RegEx.new()
	_cmd_regex.compile(CMD_REGEX_PATTERN)


func parse(raw: String) -> PlotData:
	var lines: Array[String] = []
	for line in raw.split("\n"):
		var trimmed := line.strip_edges()
		if trimmed.is_empty() or trimmed.begins_with("//") or trimmed.begins_with("#"):
			continue
		lines.append(trimmed)

	var nodes: Array[PlotNode] = []
	var last_who: String = ""

	# Metadata extraction for first few lines (max 5)
	var i := 0
	while i < lines.size() and i < 5:
		var meta_match := _meta_regex.search(lines[i])
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
	var line_idx: int = 0

	while line_idx < lines.size():
		var line: String = lines[line_idx]

		if line.begins_with("@"):
			_parse_command(line, pending_commands)
			# @stop creates its own scene node immediately
			if pending_commands.has("stop"):
				var stop_node := PlotNode.new()
				stop_node.ZH = ""
				stop_node.EN = ""
				stop_node.type = "scene"
				stop_node.stop_transition = true
				_apply_commands(stop_node, pending_commands)
				nodes.append(stop_node)
				pending_commands.clear()
			# @jump creates its own scene node immediately
			if pending_commands.has("jump_plot_id"):
				var jump_node := PlotNode.new()
				jump_node.ZH = ""
				jump_node.EN = ""
				jump_node.type = "scene"
				jump_node.jump_plot_id = pending_commands.get("jump_plot_id", "")
				jump_node.jump_node_index = pending_commands.get("jump_node_index", 0)
				_apply_commands(jump_node, pending_commands)
				nodes.append(jump_node)
				pending_commands.clear()
			# @black creates its own scene node immediately
			if pending_commands.has("fade_black"):
				var black_node := PlotNode.new()
				black_node.ZH = ""
				black_node.EN = ""
				black_node.type = "scene"
				black_node.fade_black = pending_commands.get("fade_black", 1.0)
				_apply_commands(black_node, pending_commands)
				nodes.append(black_node)
				pending_commands.clear()
			# @title creates its own scene node immediately
			if pending_commands.has("back_to_title"):
				var title_node := PlotNode.new()
				title_node.ZH = ""
				title_node.EN = ""
				title_node.type = "scene"
				title_node.back_to_title = true
				_apply_commands(title_node, pending_commands)
				nodes.append(title_node)
				pending_commands.clear()
			# @rechoose creates its own scene node immediately
			if pending_commands.has("rechoose"):
				var rechoose_node := PlotNode.new()
				rechoose_node.ZH = ""
				rechoose_node.EN = ""
				rechoose_node.type = "scene"
				rechoose_node.rechoose = true
				_apply_commands(rechoose_node, pending_commands)
				nodes.append(rechoose_node)
				pending_commands.clear()
			line_idx += 1
			continue

		# Check for choice prompt (supports both ? and ？)
		if (line.begins_with("?") or line.begins_with("？")) and not ":" in line.substr(0, min(15, line.length())) and not "：" in line.substr(0, min(15, line.length())):
			var select_node := PlotNode.new()
			select_node.type = "select"
			select_node.ZH = line.substr(1).strip_edges()
			select_node.EN = select_node.ZH
			select_node.options = []
			_apply_commands(select_node, pending_commands)
			nodes.append(select_node)
			pending_commands.clear()
			line_idx += 1
			continue

		# Check for choice option (with optional reaction block)
		if line.begins_with(">") and nodes.size() > 0:
			var last_node := nodes[nodes.size() - 1]
			if last_node.type == "select":
				var opt_match := _opt_regex.search(line)
				var option := PlotOption.new()

				if opt_match:
					# Format: > label -> target
					option.ZH = opt_match.get_string(1).strip_edges()
					option.EN = option.ZH
					_apply_option_target(option, opt_match.get_string(2).strip_edges())
				else:
					# Format: > label   (no target → defaults to _continue)
					option.ZH = line.substr(1).strip_edges()
					option.EN = option.ZH
					# target fields stay at defaults → _continue at runtime

				last_node.options.append(option)
				line_idx += 1

				# ── Reaction block:  ( content )  or （ content ） ──
				var rb_result: Array = _try_parse_reaction_block(lines, line_idx)
				option.reaction_nodes = rb_result[0]
				line_idx = rb_result[1]
				continue

		# Dialogue or Narration
		# Supports both half-width (:) and full-width (：) colons for speaker detection.
		var who: String = ""
		var text: String = line

		var half_colon_idx: int = line.find(":")
		var full_colon_idx: int = line.find("：")
		var colon_idx: int = -1

		# Find the earliest colon within the valid name range (< 15 chars)
		if half_colon_idx > 0 and half_colon_idx < 15:
			colon_idx = half_colon_idx
		if full_colon_idx > 0 and full_colon_idx < 15:
			if colon_idx == -1 or full_colon_idx < colon_idx:
				colon_idx = full_colon_idx

		if colon_idx > 0:
			who = line.substr(0, colon_idx).strip_edges()
			text = line.substr(colon_idx + 1).strip_edges()
		elif line.begins_with("："):
			# Leading full-width colon — narration
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
		line_idx += 1

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
	var cmd_match := _cmd_regex.search(line)

	if cmd_match:
		var cmd: String = cmd_match.get_string(1).to_lower()
		var params: String = cmd_match.get_string(2)
		var args: Array[String] = []
		for a in params.split(","):
			args.append(a.strip_edges())

		match cmd:
			"bg":
				if args.size() > 0 and not args[0].is_empty():
					pending["bg"] = AssetResolver.resolve_bg(args[0])
			"music":
				if args.size() > 0 and not args[0].is_empty():
					var bgm_cmd := AudioCommand.new()
					bgm_cmd.play = AssetResolver.resolve_music(args[0])
					bgm_cmd.loop = true
					bgm_cmd.audio_type = "bgm"
					pending["bgm"] = bgm_cmd
			"stopmusic":
				var stop_cmd := AudioCommand.new()
				stop_cmd.stop = true
				pending["bgm"] = stop_cmd
			"crossfade":
				if args.size() > 0 and not args[0].is_empty():
					var cf_cmd := AudioCommand.new()
					cf_cmd.play = AssetResolver.resolve_music(args[0])
					cf_cmd.loop = true
					cf_cmd.audio_type = "bgm"
					cf_cmd.crossfade = true
					cf_cmd.fade_out_duration = args[1].to_float() if args.size() > 1 and args[1].is_valid_float() else 1.5
					cf_cmd.fade_in_duration = args[2].to_float() if args.size() > 2 and args[2].is_valid_float() else cf_cmd.fade_out_duration
					pending["bgm"] = cf_cmd
			"fadeout":
				var fo_cmd := AudioCommand.new()
				fo_cmd.stop = true
				fo_cmd.fade_out_only = true
				fo_cmd.fade_out_duration = args[0].to_float() if args.size() > 0 and args[0].is_valid_float() else 2.0
				pending["bgm"] = fo_cmd
			"fadein":
				if args.size() > 0 and not args[0].is_empty():
					var fi_cmd := AudioCommand.new()
					fi_cmd.play = AssetResolver.resolve_music(args[0])
					fi_cmd.loop = true
					fi_cmd.audio_type = "bgm"
					fi_cmd.crossfade = true
					fi_cmd.fade_out_duration = 0.0
					fi_cmd.fade_in_duration = args[1].to_float() if args.size() > 1 and args[1].is_valid_float() else 2.0
					pending["bgm"] = fi_cmd
			"play":
				if args.size() > 0 and not args[0].is_empty():
					var sfx_cmd := AudioCommand.new()
					sfx_cmd.play = AssetResolver.resolve_sfx(args[0])
					sfx_cmd.audio_type = "sfx"
					pending["sfx"] = sfx_cmd
			"playshort":
				if args.size() > 0 and not args[0].is_empty():
					var s_cmd := AudioCommand.new()
					s_cmd.play = AssetResolver.resolve_sfx_short(args[0])
					s_cmd.audio_type = "sfx_short"
					pending["sfx_short"] = s_cmd
			"ambience":
				if args.size() > 0 and not args[0].is_empty():
					var amb_cmd := AudioCommand.new()
					amb_cmd.play = AssetResolver.resolve_ambience(args[0])
					amb_cmd.loop = true
					amb_cmd.audio_type = "ambience"
					amb_cmd.ambience_volume = args[1].to_float() if args.size() > 1 and args[1].is_valid_float() else 0.5
					pending["ambience"] = amb_cmd
			"stopambience":
				var amb_stop := AudioCommand.new()
				amb_stop.stop = true
				amb_stop.audio_type = "ambience"
				pending["ambience"] = amb_stop
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
				if args.size() > 1 and not args[1].is_empty():
					pending["ch"] = AssetResolver.resolve_ch(args[1])
				elif args.size() > 0 and not args[0].is_empty():
					pending["ch"] = AssetResolver.resolve_ch(args[0])
			"glitch":
				pending["glitch"] = true
			"wait":
				if args.size() > 0 and args[0].is_valid_float():
					pending["wait_time"] = args[0].to_float()
			"chclear":
				pending["ch"] = "__CLEAR__"
			"stop":
				pending["stop"] = true
			"jump":
				# Always jump to the beginning (node 0) of the target plot.
				if args.size() > 0:
					pending["jump_plot_id"] = args[0]
					pending["jump_node_index"] = 0
			"black":
				pending["fade_black"] = args[0].to_float() if args.size() > 0 and args[0].is_valid_float() else 1.0
			"rechoose":
				pending["rechoose"] = true
			"title":
				pending["back_to_title"] = true
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
		elif bare == "@chclear":
			pending["ch"] = "__CLEAR__"
		elif bare == "@stop":
			pending["stop"] = true
		elif bare == "@stopambience":
			var amb_stop := AudioCommand.new()
			amb_stop.stop = true
			amb_stop.audio_type = "ambience"
			pending["ambience"] = amb_stop
		elif bare == "@fadeout":
			var fo_cmd := AudioCommand.new()
			fo_cmd.stop = true
			fo_cmd.fade_out_only = true
			fo_cmd.fade_out_duration = 2.0
			pending["bgm"] = fo_cmd
		elif bare == "@rechoose":
			pending["rechoose"] = true
		elif bare == "@title":
			pending["back_to_title"] = true


# ── Option target resolver ───────────────────────────────────────────────

## Parse and apply a choice-option target string.
##   chapter1@15  → plot = chapter1, node = 0
##   5            → same plot,      node = 0
##   chapter1     → plot = chapter1, node = 0
##   _continue    → stay on current plot (leave defaults)
##   _rechoose    → loop back to the select node to re-choose
func _apply_option_target(option: PlotOption, target: String) -> void:
	if "@" in target:
		option.target_plot_id = target.split("@")[0]
		option.target_node_index = 0
	elif target.is_valid_int():
		option.target_node_index = 0
	elif target.strip_edges().to_lower() == "_continue":
		pass  # leave fields at defaults → _continue
	elif target.strip_edges().to_lower() == "_rechoose":
		option.rechoose = true
	else:
		option.target_plot_id = target
		option.target_node_index = 0


# ── Reaction block parser ────────────────────────────────────────────────

## If @start_idx points to a line that begins with （ or (, consume
## lines until the matching ） or ) and parse the enclosed content as
## PlotNodes.  Returns [Array[PlotNode], int] — the reaction nodes and
## the updated line index.  If no reaction block is found, returns
## [ [], @start_idx ] unchanged.
func _try_parse_reaction_block(lines: Array[String], start_idx: int) -> Array:
	if start_idx >= lines.size():
		return [[], start_idx]

	var next_line: String = lines[start_idx]
	if not (next_line.begins_with("（") or next_line.begins_with("(")):
		return [[], start_idx]

	var reaction_lines: Array[String] = []
	var idx: int = start_idx

	# First line — strip opening paren
	var first: String = next_line.substr(1).strip_edges()
	if not first.is_empty():
		reaction_lines.append(first)
	idx += 1

	# Collect until closing paren
	while idx < lines.size():
		var rline: String = lines[idx]
		idx += 1
		if rline.ends_with("）") or rline.ends_with(")"):
			var last: String = rline.substr(0, rline.length() - 1).strip_edges()
			if not last.is_empty():
				reaction_lines.append(last)
			break
		else:
			reaction_lines.append(rline)

	return [_parse_reaction_lines(reaction_lines), idx]

## Parse a mini-script of reaction lines (from a choice's parenthesized
## block) into PlotNodes.  Supports @commands and dialogue/narration.
## Does NOT support nested choice prompts or further reaction blocks.
func _parse_reaction_lines(reaction_lines: Array[String]) -> Array[PlotNode]:
	var reaction_nodes: Array[PlotNode] = []
	var pending: Dictionary = {}
	var last_who: String = ""

	for line in reaction_lines:
		if line.is_empty():
			continue

		if line.begins_with("@"):
			_parse_command(line, pending)
			# Handle @rechoose inside reaction block — emit immediately
			if pending.has("rechoose"):
				var rechoose_node := PlotNode.new()
				rechoose_node.ZH = ""
				rechoose_node.EN = ""
				rechoose_node.type = "scene"
				rechoose_node.rechoose = true
				_apply_commands(rechoose_node, pending)
				reaction_nodes.append(rechoose_node)
				pending.clear()
			continue

		# Dialogue or Narration (same logic as main parser)
		var who: String = ""
		var text: String = line

		var half_colon_idx: int = line.find(":")
		var full_colon_idx: int = line.find("：")
		var colon_idx: int = -1

		if half_colon_idx > 0 and half_colon_idx < 15:
			colon_idx = half_colon_idx
		if full_colon_idx > 0 and full_colon_idx < 15:
			if colon_idx == -1 or full_colon_idx < colon_idx:
				colon_idx = full_colon_idx

		if colon_idx > 0:
			who = line.substr(0, colon_idx).strip_edges()
			text = line.substr(colon_idx + 1).strip_edges()
		elif line.begins_with("："):
			text = line.substr(1).strip_edges()

		var node := PlotNode.new()
		node.ZH = text
		node.EN = text
		node.who = who
		node.type = "text"
		_apply_commands(node, pending)

		if who.is_empty():
			if not last_who.is_empty() and node.ch.is_empty():
				node.ch = "__CLEAR__"
			last_who = ""
		else:
			if who != last_who and node.ch.is_empty():
				node.ch = who
			last_who = who

		reaction_nodes.append(node)
		pending.clear()

	# Flush any dangling commands as a scene node
	if not pending.is_empty():
		var leftover := PlotNode.new()
		leftover.ZH = ""
		leftover.EN = ""
		leftover.type = "scene"
		_apply_commands(leftover, pending)
		reaction_nodes.append(leftover)

	return reaction_nodes


func _apply_commands(node: PlotNode, commands: Dictionary) -> void:
	for key in commands:
		var val: Variant = commands[key]
		match key:
			"bg":
				node.bg = val
			"bgm":
				node.bgm = val
			"sfx":
				node.sfx = val
			"sfx_short":
				node.sfx_short = val
			"chapter":
				node.chapter = val
			"ch":
				node.ch = val
			"glitch":
				node.glitch = val
			"wait_time":
				node.wait_time = val
			"stop":
				node.stop_transition = val
			"ambience":
				node.ambience = val
			"fade_out_bgm":
				node.fade_out_bgm = val
			"jump_plot_id":
				node.jump_plot_id = val
			"jump_node_index":
				node.jump_node_index = val
			"fade_black":
				node.fade_black = val
			"back_to_title":
				node.back_to_title = val
			"rechoose":
				node.rechoose = val
