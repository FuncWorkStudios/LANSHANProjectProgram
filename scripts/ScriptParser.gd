## ScriptParser : RefCounted
## 将 .txt 剧情脚本解析为 PlotData 资源。
##
## 语法规则见 .claude/script.md。
class_name ScriptParser extends RefCounted

var _plot_id: String = ""
var _title: LocText = null
var _characters: Dictionary = {}

const CMD_REGEX: String = "@(\\w+)\\s*(.*)"
const OPT_TARGET_REGEX: String = "(.+?)\\s*->\\s*(.+)"
const META_ID_REGEX: String = "::\\s*(\\w+)\\s*$"


func _init(plot_id: String = "") -> void:
	_plot_id = plot_id
	_title = LocText.new()
	_title.ZH = "新剧本"
	_title.EN = "New Script"


func parse(raw: String) -> PlotData:
	var lines: Array[String] = _preprocess(raw)
	var nodes: Array[PlotNode] = []
	var last_who: String = ""
	var i: int = 0

	while i < lines.size():
		var stripped: String = lines[i].strip_edges()

		if stripped.begins_with("@"):
			var node: PlotNode = _parse_directive(stripped)
			if node: nodes.append(node)
			i += 1
			continue

		if stripped.begins_with("-"):
			var sel_node: PlotNode = _ensure_select_node(nodes)
			var opt: PlotOption = _parse_option(stripped)
			sel_node.options.append(opt)
			i += 1
			var rb: Array = _parse_reactions(lines, i)
			opt.reaction_nodes = rb[0]
			i = rb[1]
			continue

		# 对话或旁白
		var result: Dictionary = _parse_dialogue(stripped, last_who)
		nodes.append(result["node"])
		last_who = result["last_who"]
		i += 1

	var data := PlotData.new()
	data.id = _plot_id
	data.title = _title
	data.characters = _characters
	data.nodes = nodes
	return data


# ═══════════════════════════════════════════════════════════════
# 预处理
# ═══════════════════════════════════════════════════════════════

func _preprocess(raw: String) -> Array[String]:
	var result: Array[String] = []
	for line in raw.split("\n"):
		var stripped := line.strip_edges(false, true)
		if stripped.is_empty(): continue
		if stripped.begins_with("#"): continue
		if stripped.strip_edges().begins_with("::"):
			_parse_meta(stripped.strip_edges())
			continue
		result.append(stripped)
	return result


func _parse_meta(line: String) -> void:
	if not line.begins_with("::"): return
	var id_match := RegEx.create_from_string(META_ID_REGEX).search(line)
	if id_match: _plot_id = id_match.get_string(1); return
	var stripped := line.trim_prefix("::").strip_edges()
	if stripped.begins_with("title "):
		_title.ZH = stripped.trim_prefix("title ").strip_edges()
	elif stripped.begins_with("id "):
		_plot_id = stripped.trim_prefix("id ").strip_edges()


# ═══════════════════════════════════════════════════════════════
# 指令解析
# ═══════════════════════════════════════════════════════════════

func _parse_directive(line: String) -> PlotNode:
	var cmd_match := RegEx.create_from_string(CMD_REGEX).search(line)
	if not cmd_match:
		push_warning("ScriptParser: malformed directive — ", line)
		return null

	var cmd: String = cmd_match.get_string(1).to_lower()
	var raw_args: String = cmd_match.get_string(2).strip_edges()
	# 去掉旧格式遗留的外层括号：@bg(path) → path
	if raw_args.begins_with("(") and raw_args.ends_with(")"):
		raw_args = raw_args.substr(1, raw_args.length() - 2).strip_edges()
	var args: Array[String] = _split_args(raw_args)
	# 每个参数也去掉可能的外层括号
	for a_idx: int in range(args.size()):
		var a: String = args[a_idx]
		if a.begins_with("(") and a.ends_with(")"):
			args[a_idx] = a.substr(1, a.length() - 2).strip_edges()

	var node := PlotNode.new()
	node.ZH = ""; node.EN = ""; node.type = "scene"

	match cmd:
		"bg":
			if args.size() > 0:
				var first: String = args[0]
				if first == "up":
					node.bg_align = "up"
				elif first == "down":
					node.bg_align = "down"
				else:
					node.bg = AssetResolver.resolve_bg(first)
					if args.size() > 1:
						var second: String = args[1]
						if second == "up": node.bg_align = "up"
						elif second == "down": node.bg_align = "down"
		"bgm":          _parse_bgm(node, args)
		"sfx":          _parse_sfx(node, args)
		"ambience":     _parse_ambience(node, args)
		"stopaudio":    _build_stop_audio(node)
		"ch":           _parse_ch(node, args)
		"glitch":
			node.glitch = not (args.size() > 0 and args[0] == "off")
		"wait":
			if args.size() > 0 and args[0].is_valid_float():
				node.wait_time = args[0].to_float()
		"stop":         node.stop_transition = true
		"black":
			node.fade_black = args[0].to_float() if args.size() > 0 and args[0].is_valid_float() else 1.0
		"jump":
			if args.size() > 0: node.jump_plot_id = args[0]; node.jump_node_index = 0
		"title":        node.back_to_title = true
		"rechoose":     node.rechoose = true
		"terminal":
			node.set_terminal = args[0] if args.size() > 0 else ""
		_:
			push_warning("ScriptParser: unknown directive @", cmd, " — skipped")

	return node


func _parse_bgm(node: PlotNode, args: Array[String]) -> void:
	if args.is_empty(): return
	var sub: String = args[0].to_lower()
	var c := AudioCommand.new(); c.loop = true; c.audio_type = "bgm"
	if sub == "fadeout":
		c.stop = true; c.fade_out_only = true
		c.fade_out_duration = args[1].to_float() if args.size() > 1 and args[1].is_valid_float() else 2.0
	elif sub == "crossfade" and args.size() > 1:
		c.play = AssetResolver.resolve_music(args[1]); c.crossfade = true
		c.fade_out_duration = args[2].to_float() if args.size() > 2 and args[2].is_valid_float() else 1.5
		c.fade_in_duration = args[3].to_float() if args.size() > 3 and args[3].is_valid_float() else c.fade_out_duration
	else:
		c.play = AssetResolver.resolve_music(args[0])
	node.bgm = c


func _parse_sfx(node: PlotNode, args: Array[String]) -> void:
	if args.is_empty() or args[0].is_empty(): return
	var c := AudioCommand.new(); c.play = AssetResolver.resolve_sfx(args[0]); c.audio_type = "sfx_short"
	node.sfx_short = c


func _parse_ambience(node: PlotNode, args: Array[String]) -> void:
	if args.is_empty() or args[0].is_empty(): return
	var c := AudioCommand.new()
	c.play = AssetResolver.resolve_ambience(args[0]); c.loop = true; c.audio_type = "ambience"
	c.ambience_volume = args[1].to_float() if args.size() > 1 and args[1].is_valid_float() else 0.5
	node.ambience = c


func _build_stop_audio(node: PlotNode) -> void:
	var a := AudioCommand.new(); a.stop = true; node.bgm = a
	var b := AudioCommand.new(); b.stop = true; node.sfx_short = b
	var c := AudioCommand.new(); c.stop = true; node.ambience = c


func _parse_ch(node: PlotNode, args: Array[String]) -> void:
	if args.is_empty(): return
	if args[0] == "clear": node.ch = "__CLEAR__"
	else: node.ch = AssetResolver.resolve_ch(args[0])


# ═══════════════════════════════════════════════════════════════
# 对话解析
# ═══════════════════════════════════════════════════════════════

func _parse_dialogue(line: String, last_who: String) -> Dictionary:
	var who: String = ""
	var text: String = line
	var colon_idx: int = -1

	for ch_idx: int in range(min(15, line.length())):
		var ch: String = line[ch_idx]
		if ch == ":" or ch == "：": colon_idx = ch_idx; break

	if colon_idx > 0:
		who = line.substr(0, colon_idx).strip_edges()
		text = line.substr(colon_idx + 1).strip_edges()

	var node := PlotNode.new()
	node.ZH = text; node.EN = ""; node.who = who; node.type = "text"

	if who.is_empty():
		if not last_who.is_empty(): node.ch = "__CLEAR__"
	else:
		if who != last_who: node.ch = who

	return {"node": node, "last_who": who}




# ═══════════════════════════════════════════════════════════════
# 选择解析
# ═══════════════════════════════════════════════════════════════

func _ensure_select_node(nodes: Array[PlotNode]) -> PlotNode:
	if nodes.size() > 0:
		var last: PlotNode = nodes[nodes.size() - 1]
		if last.type == "select": return last
	var sel := PlotNode.new()
	sel.type = "select"; sel.ZH = ""; sel.EN = ""; sel.options = []
	nodes.append(sel)
	return sel


func _parse_option(line: String) -> PlotOption:
	var opt := PlotOption.new()
	var content: String = line.substr(1).strip_edges()

	var opt_match := RegEx.create_from_string(OPT_TARGET_REGEX).search(content)
	var text: String
	if opt_match:
		text = opt_match.get_string(1).strip_edges()
		_apply_option_target(opt, opt_match.get_string(2).strip_edges())
	else:
		text = content

	opt.ZH = text; opt.EN = ""
	return opt


func _apply_option_target(option: PlotOption, target: String) -> void:
	var t := target.strip_edges().to_lower()
	if t == "_continue": return
	if t == "_rechoose": option.rechoose = true; return
	option.target_plot_id = target
	option.target_node_index = 0


# ═══════════════════════════════════════════════════════════════
# 反应块（缩进格式）
# ═══════════════════════════════════════════════════════════════

func _parse_reactions(lines: Array[String], start_idx: int) -> Array:
	if start_idx >= lines.size(): return [[], start_idx]
	var reaction_lines: Array[String] = []
	var idx: int = start_idx
	while idx < lines.size():
		var rline: String = lines[idx]
		if rline.begins_with(" ") or rline.begins_with("\t"):
			reaction_lines.append(rline.strip_edges())
			idx += 1
		else:
			break
	return [_parse_reaction_lines(reaction_lines), idx]


func _parse_reaction_lines(rlines: Array[String]) -> Array[PlotNode]:
	var nodes: Array[PlotNode] = []
	var last_who: String = ""
	for line in rlines:
		if line.is_empty(): continue
		if line.begins_with("@"):
			var node: PlotNode = _parse_directive(line)
			if node: nodes.append(node)
			continue
		var result: Dictionary = _parse_dialogue(line, last_who)
		nodes.append(result["node"])
		last_who = result["last_who"]
	return nodes


# ═══════════════════════════════════════════════════════════════
# 工具
# ═══════════════════════════════════════════════════════════════

func _split_args(raw: String) -> Array[String]:
	if raw.is_empty(): return []
	var args: Array[String] = []
	var depth: int = 0; var start: int = 0
	for i: int in range(raw.length()):
		var ch: String = raw[i]
		if ch == "(" or ch == "（": depth += 1
		elif ch == ")" or ch == "）": depth -= 1
		elif ch == "," and depth == 0:
			args.append(raw.substr(start, i - start).strip_edges())
			start = i + 1
	args.append(raw.substr(start).strip_edges())
	return args
