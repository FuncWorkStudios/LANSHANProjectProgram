## ScriptParser : RefCounted
## 将 .gd 剧本字符串解析为 PlotData 资源。
##
## 语法规则：
##   :: title <标题> [| <English title>]          元信息 — 剧情标题
##   :: id <plot_id>                              元信息 — 剧情 id
##   :: char <id> = <显示名> [| <English name>]   元信息 — 角色显示名（姓名框 / 日志）
##   @bg / @bgm / @sfx / @ambience / @stopaudio / @ch / @wait / @black / @stop /
##   @glitch / @locate                                          表现类指令
##   @settime / @timeset / @sidesettime / @sidetimeset           日期推进节拍
##   @return                                                     段落到此结束
##   @label / @goto / @set / @persist / @if / @else / @endif     流程控制
##   <名字>：<台词>                对话（冒号可为半角 : 或全角 ：）
##   <文本>                        旁白
##   - <文本> { 表达式; ... }       选项（可选 -> _rechoose）；缩进在下方的是反应块
##
## 调度约定：剧本里没有"去哪"。@return 只表示"本段到此结束"，下一段剧情 / 场景 /
## 标题全部由 FlowManager 依据 from_plot + 变量 + 上下文决定。带目的地的语法
## （@return <plot>、@title、@end、选项目标 ->）已删除。
##
## 设计要点：
##   · 全程不使用 RegEx —— 指令 / 说话者 / 选项目标的切分都是单次线性扫描。
##     原实现每行都要 RegEx.create_from_string()（含每行编译一次对话正则），
##     这是解析器里唯一的弱点。
##   · 保留源文件行号：_preprocess 会丢掉空行与注释行，所以不能再拿"数组下标 + 1"
##     当行号（原实现报错定位常常偏移）。
##   · 解析器实例可复用：每次 parse() 都会重置内部状态。
##   · 说话者判定分两步：先切出"冒号前候选"，再看候选是不是"已知说话者 + 叙述片段"
##     （`何肖白了他一眼：…`）。第二步靠本篇内自洽的说话者 token 集合，不需要手写名册。
class_name ScriptParser extends RefCounted

## 说话者名字最大长度（与旧正则 {1,20} 一致）
const MAX_SPEAKER_LEN: int = 20

## 名字里不允许出现的字符 —— 出现即说明冒号前是叙述文字而不是名字。
## 引号与句读都是叙述句法特征；全角/半角冒号只是双保险。
## 注意：不排除 ！？ —— 剧本里 "？？？" 是合法的"未知说话者"标签。
const SPEAKER_REJECT_CHARS: String = "\"'“”‘’「」『』，。；、…—：:"

## "已知说话者 + 叙述片段"判定的例外后缀首字：
## 的/得/地/之 → 修饰关系（漆诚的声音）；/ 、 与 和 & + → 组合说话者（马武 / 曾允峰）
const CLAUSE_TAIL_EXCLUDE: String = "的得地之/、与和&+×"

## 流程指令集合 —— O(1) 查表（原来是 Array.has 线性扫描）
const FLOW_COMMANDS: Dictionary = {
	"if": true,
	"else": true,
	"endif": true,
	"label": true,
	"goto": true,
	"set": true,
	"persist": true,
}

## 反应块里禁止出现的收尾/节拍指令 —— 反应节点不经过 _advance，事件会被静默丢弃
const REACTION_FORBIDDEN: Array[String] = [
	"return", "settime", "timeset", "sidesettime", "sidetimeset",
]

# 常用码点 —— 用 unicode_at() 比较，避免逐字符分配 String
const CP_TAB: int = 0x09
const CP_SPACE: int = 0x20
const CP_DQUOTE: int = 0x22
const CP_SQUOTE: int = 0x27
const CP_LPAREN: int = 0x28
const CP_RPAREN: int = 0x29
const CP_COMMA: int = 0x2C
const CP_DASH: int = 0x2D
const CP_COLON: int = 0x3A
const CP_AT: int = 0x40
const CP_LPAREN_WIDE: int = 0xFF08
const CP_RPAREN_WIDE: int = 0xFF09
const CP_COLON_WIDE: int = 0xFF1A
const CP_IDEO_SPACE: int = 0x3000

var _plot_id: String = ""
var _default_plot_id: String = ""
var _title: LocText = null
var _characters: Dictionary = {}
## 本篇内"独立出现过"的说话者 token → 出现次数（预扫描填）
var _speaker_tokens: Dictionary = {}


func _init(plot_id: String = "") -> void:
	_default_plot_id = plot_id
	_reset()


# ═══════════════════════════════════════════════════════════════
# 顶层解析入口
# ═══════════════════════════════════════════════════════════════

func parse(raw: String) -> PlotData:
	_reset()

	var lines: Array[String] = []
	var line_nos: Array[int] = []
	_preprocess(raw, lines, line_nos)
	# 预扫描说话者 token：用于识别"名字 + 叙述短语"被误当对话的行
	_speaker_tokens = _collect_speaker_tokens(lines)

	var nodes: Array[PlotNode] = []
	var cond_stack: Array[Dictionary] = []   # [{if_node, if_idx, else_idx, if_line}]
	var last_who: String = ""
	var i: int = 0

	while i < lines.size():
		var line_no: int = line_nos[i]
		var line: String = lines[i].strip_edges()
		if line.is_empty():
			i += 1
			continue
		var head: int = line.unicode_at(0)

		# ── 指令（流程指令 / 常规指令）──
		if head == CP_AT:
			var cmd_args: PackedStringArray = _split_command(line)
			var cmd: String = cmd_args[0]
			if FLOW_COMMANDS.has(cmd):
				_parse_flow_directive(cmd, cmd_args[1], nodes, cond_stack, line_no)
			else:
				var node: PlotNode = _parse_directive(cmd, cmd_args[1], line_no)
				if node:
					_append_node(nodes, node)
			i += 1
			continue

		# ── 选项 ──
		if head == CP_DASH:
			var sel_node: PlotNode = _ensure_select_node(nodes)
			var option: PlotOption = _parse_option(line, line_no)
			sel_node.options.append(option)
			i += 1
			var reactions: Dictionary = _parse_reactions(lines, line_nos, i)
			option.reaction_nodes = reactions["nodes"]
			i = reactions["next"]
			continue

		# ── 对话或旁白 ──
		var text_node: PlotNode = _parse_dialogue(line, last_who, line_no)
		_append_node(nodes, text_node)
		last_who = text_node.who
		i += 1

	# ── 未闭合的 @if：报错并补 endif，保证 jump_to 永远指向合法节点 ──
	if not cond_stack.is_empty():
		_close_dangling_ifs(nodes, cond_stack)

	var data: PlotData = PlotData.new()
	data.id = _plot_id
	data.title = _title
	data.characters = _characters
	data.nodes = nodes

	# ── 二次解析：label 收集 ──
	for ni: int in range(nodes.size()):
		var n: PlotNode = nodes[ni]
		if n.type == "label" and not n.label.is_empty():
			if data.labels.has(n.label):
				push_error("ScriptParser: duplicate label '", n.label, "' at line ", n.line_number,
					" (first at node ", data.labels[n.label], ") — 先定义者生效")
				continue
			data.labels[n.label] = ni

	# ── 二次解析：@goto 决议 ──
	for ni: int in range(nodes.size()):
		var n: PlotNode = nodes[ni]
		if n.type == "goto":
			if data.labels.has(n.goto_label):
				n.jump_to = data.labels[n.goto_label]
			else:
				push_error("ScriptParser: @goto '", n.goto_label, "' target not found (line ", n.line_number, ")")

	return data


# ═══════════════════════════════════════════════════════════════
# 预处理
# ═══════════════════════════════════════════════════════════════

## 拆分原始文本：只去掉行尾空白与空行/注释行，保留行首缩进（反应块的语法标记），
## 同时输出每行在源文件中的真实行号。
func _preprocess(raw: String, out_lines: Array[String], out_line_nos: Array[int]) -> void:
	var raw_lines: PackedStringArray = raw.split("\n")
	for idx: int in range(raw_lines.size()):
		var line: String = raw_lines[idx].strip_edges(false, true)
		if line.is_empty():
			continue
		var content: String = line.strip_edges(true, false)
		if content.begins_with("#"):
			continue
		if content.begins_with("::"):
			_parse_meta(content, idx + 1)
			continue
		out_lines.append(line)
		out_line_nos.append(idx + 1)


## 解析 ":: key value" 元信息行。
func _parse_meta(line: String, line_no: int = 0) -> void:
	var body: String = line.substr(2).strip_edges()
	if body.is_empty():
		return
	var cut: int = _first_whitespace(body)
	var key: String = body if cut < 0 else body.substr(0, cut)
	var value: String = "" if cut < 0 else body.substr(cut + 1).strip_edges()
	match key.to_lower():
		"title":
			_set_title(value)
		"id":
			_plot_id = value
		"char", "character":
			_add_character(value, line_no)
		_:
			if value.is_empty():
				_plot_id = key   # 旧格式：裸 ":: plot_id"
			else:
				push_warning("ScriptParser: unknown meta ':: ", key, "' ignored (line ", line_no, ")")


## "第一章：开学第一天" 或 "石晴雯 路线 | Shi Qingwen Route"
func _set_title(value: String) -> void:
	if value.is_empty():
		return
	var bar: int = value.find("|")
	if bar >= 0:
		_title.ZH = value.substr(0, bar).strip_edges()
		_title.EN = value.substr(bar + 1).strip_edges()
	else:
		_title.ZH = value
		# 必须清掉占位英文名，否则 EN 区域下章节标题永远是 "New Script"
		_title.EN = ""


## ":: char 林子欣 = 林子欣 | Lin Zixin"
func _add_character(value: String, line_no: int = 0) -> void:
	var eq: int = value.find("=")
	if eq <= 0:
		push_error("ScriptParser: :: char 需要 'id = 显示名' 格式 (line ", line_no, "): ", value)
		return
	var char_id: String = value.substr(0, eq).strip_edges()
	var display: String = value.substr(eq + 1).strip_edges()
	if char_id.is_empty() or display.is_empty():
		push_error("ScriptParser: :: char id/显示名为空 (line ", line_no, "): ", value)
		return
	var loc: LocText = LocText.new()
	var bar: int = display.find("|")
	if bar >= 0:
		loc.ZH = display.substr(0, bar).strip_edges()
		loc.EN = display.substr(bar + 1).strip_edges()
	else:
		loc.ZH = display
		loc.EN = ""
	if _characters.has(char_id):
		push_warning("ScriptParser: duplicate :: char '", char_id, "' (line ", line_no, ") — 后者覆盖")
	_characters[char_id] = loc


func _reset() -> void:
	_plot_id = _default_plot_id
	_characters = {}
	_speaker_tokens = {}
	_title = LocText.new()
	_title.ZH = "新剧本"
	_title.EN = ""


# ═══════════════════════════════════════════════════════════════
# 流程指令解析
# ═══════════════════════════════════════════════════════════════

## 处理 @label / @goto / @set / @persist / @if / @else / @endif
func _parse_flow_directive(cmd: String, raw_args: String, nodes: Array[PlotNode], cond_stack: Array[Dictionary], line_no: int) -> void:
	match cmd:
		"label":
			if raw_args.is_empty():
				push_error("ScriptParser: @label missing name (line ", line_no, ")")
				return
			var label_node: PlotNode = _make_node("label", line_no)
			label_node.label = raw_args
			_append_node(nodes, label_node)

		"goto":
			if raw_args.is_empty():
				push_error("ScriptParser: @goto missing label (line ", line_no, ")")
				return
			var goto_node: PlotNode = _make_node("goto", line_no)
			goto_node.goto_label = raw_args
			# jump_to 在二次解析中填入
			_append_node(nodes, goto_node)

		"set", "persist":
			var set_node: PlotNode = _make_node(cmd, line_no)
			set_node.expression = raw_args
			if raw_args.is_empty():
				push_warning("ScriptParser: @", cmd, " missing expression (line ", line_no, ")")
			_append_node(nodes, set_node)

		"if":
			var if_node: PlotNode = _make_node("if", line_no)
			if_node.expression = raw_args
			if raw_args.is_empty():
				push_warning("ScriptParser: @if missing condition (line ", line_no, ") — 条件恒为 false")
			# jump_to 在 @else / @endif 时回填
			var idx: int = _append_node(nodes, if_node)
			cond_stack.append({"if_node": if_node, "if_idx": idx, "else_idx": -1, "if_line": line_no})

		"else":
			if cond_stack.is_empty():
				push_error("ScriptParser: @else without matching @if (line ", line_no, ")")
				return
			var top: Dictionary = cond_stack[cond_stack.size() - 1]
			if int(top["else_idx"]) >= 0:
				push_error("ScriptParser: duplicate @else for @if at line ", top["if_line"],
					" (line ", line_no, ")")
				return
			var else_node: PlotNode = _make_node("else", line_no)
			# jump_to 在 @endif 时回填
			top["else_idx"] = _append_node(nodes, else_node)

		"endif":
			if cond_stack.is_empty():
				push_error("ScriptParser: @endif without matching @if (line ", line_no, ")")
				return
			var closed: Dictionary = cond_stack.pop_back()
			# 先取 endif 位置再追加节点，两者相等
			var endif_idx: int = nodes.size()
			_append_node(nodes, _make_node("endif", line_no))
			_link_if(closed, endif_idx, nodes)

		_:
			push_warning("ScriptParser: unknown flow directive @", cmd, " (line ", line_no, ")")


## 回填 if / else 的 jump_to —— @endif 与"文件末尾自动闭合"共用。
func _link_if(entry: Dictionary, endif_idx: int, nodes: Array[PlotNode]) -> void:
	var if_node: PlotNode = entry["if_node"]
	var else_idx: int = entry["else_idx"]
	if else_idx >= 0:
		# 有 @else：条件为假 → 进 else 体；else 体执行完 → 跳到 endif
		if_node.jump_to = else_idx + 1
		nodes[else_idx].jump_to = endif_idx
	else:
		if_node.jump_to = endif_idx


## 文件结束时仍未闭合的 @if —— 报错，并为每个未闭合块补一个 endif 节点。
## 这样 jump_to 始终指向合法节点，运行时不会因为 -1 越界而中断执行。
func _close_dangling_ifs(nodes: Array[PlotNode], cond_stack: Array[Dictionary]) -> void:
	while not cond_stack.is_empty():
		var entry: Dictionary = cond_stack.pop_back()
		var if_node: PlotNode = entry["if_node"]
		push_error("ScriptParser: unclosed @if (line ", entry["if_line"], ") — auto-closed at end of file")
		var endif_idx: int = nodes.size()
		_append_node(nodes, _make_node("endif", if_node.line_number))
		_link_if(entry, endif_idx, nodes)


# ═══════════════════════════════════════════════════════════════
# 常规指令解析
# ═══════════════════════════════════════════════════════════════

## @param cmd: 已小写化的指令名（不含 @）
## @param raw_args: 指令后的原始参数串
func _parse_directive(cmd: String, raw_args: String, line_no: int = 0) -> PlotNode:
	# 旧格式 @bg(path, arg) 的外层括号要先整串剥掉，再按逗号切
	var args: Array[String] = _split_args(_unwrap_parens(raw_args))
	for a_idx: int in range(args.size()):
		args[a_idx] = _unwrap_parens(args[a_idx])

	var node: PlotNode = _make_node("scene", line_no)

	match cmd:
		"bg":
			if args.is_empty() or args[0].is_empty():
				push_warning("ScriptParser: @bg missing background (line ", line_no, ")")
				return null
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
		"bgm":
			if not _parse_bgm(node, args, line_no):
				return null
		"sfx":
			if not _parse_sfx(node, args, line_no):
				return null
		"ambience":
			if not _parse_ambience(node, args, line_no):
				return null
		"stopaudio":
			_build_stop_audio(node)
		"ch":
			if not _parse_ch(node, args, line_no):
				return null
		"glitch":
			node.glitch = not (args.size() > 0 and args[0].to_lower() == "off")
		"wait":
			if args.is_empty():
				push_warning("ScriptParser: @wait missing duration (line ", line_no, ")")
			elif not args[0].is_valid_float():
				push_warning("ScriptParser: @wait expects a number, got '", args[0], "' (line ", line_no, ")")
			else:
				node.wait_time = args[0].to_float()
		"stop":
			node.stop_transition = true
		"black":
			node.fade_black = _float_arg(args, 0, 1.0)
		"return":
			# 段落结束事件 —— 不携带目的地，由 FlowManager 决定下一段
			if not raw_args.is_empty():
				push_error("ScriptParser: @return 不再接受参数 (line ", line_no,
					") —— 调度已收归 FlowManager，参数被忽略: ", raw_args)
			node.request = {"type": "end_segment"}
		"settime":
			if not _parse_settime(node, args, line_no, false):
				return null
		"timeset":
			if not _parse_settime(node, args, line_no, false):
				return null
		"sidesettime":
			if not _parse_settime(node, args, line_no, true):
				return null
		"sidetimeset":
			if not _parse_settime(node, args, line_no, true):
				return null
		"locate":
			if args.is_empty() or args[0].is_empty():
				push_warning("ScriptParser: @locate missing location (line ", line_no, ")")
				return null
			node.location = args[0]
		"title", "end":
			# 目的地语法已删除 —— 段落结束统一走 @return
			push_error("ScriptParser: @", cmd, " 已移除 (line ", line_no,
				") —— 请改用 @return，去哪儿由 FlowManager 决定")
			return null
		"rechoose":
			node.rechoose = true
		_:
			# 未知指令不再塞一个空壳节点进节点表（原来会留下一个无效果的 scene 节点）
			push_warning("ScriptParser: unknown directive @", cmd, " — skipped (line ", line_no, ")")
			return null

	return node


func _parse_bgm(node: PlotNode, args: Array[String], line_no: int = 0) -> bool:
	if args.is_empty() or args[0].is_empty():
		push_warning("ScriptParser: @bgm missing argument (line ", line_no, ")")
		return false
	var sub: String = args[0].to_lower()
	var cmd: AudioCommand = AudioCommand.new()
	cmd.loop = true
	cmd.audio_type = "bgm"
	if sub == "fadeout":
		cmd.stop = true
		cmd.fade_out_only = true
		cmd.fade_out_duration = _float_arg(args, 1, 2.0)
	elif sub == "crossfade":
		if args.size() < 2 or args[1].is_empty():
			push_error("ScriptParser: @bgm crossfade missing track (line ", line_no, ")")
			return false
		cmd.play = AssetResolver.resolve_music(args[1])
		cmd.crossfade = true
		cmd.fade_out_duration = _float_arg(args, 2, 1.5)
		cmd.fade_in_duration = _float_arg(args, 3, cmd.fade_out_duration)
	else:
		cmd.play = AssetResolver.resolve_music(args[0])
	node.bgm = cmd
	return true


func _parse_sfx(node: PlotNode, args: Array[String], line_no: int = 0) -> bool:
	if args.is_empty() or args[0].is_empty():
		push_warning("ScriptParser: @sfx missing argument (line ", line_no, ")")
		return false
	var cmd: AudioCommand = AudioCommand.new()
	cmd.play = AssetResolver.resolve_sfx(args[0])
	cmd.audio_type = "sfx_short"
	node.sfx_short = cmd
	return true


func _parse_ambience(node: PlotNode, args: Array[String], line_no: int = 0) -> bool:
	if args.is_empty() or args[0].is_empty():
		push_warning("ScriptParser: @ambience missing argument (line ", line_no, ")")
		return false
	var cmd: AudioCommand = AudioCommand.new()
	cmd.play = AssetResolver.resolve_ambience(args[0])
	cmd.loop = true
	cmd.audio_type = "ambience"
	cmd.ambience_volume = _float_arg(args, 1, 0.5)
	node.ambience = cmd
	return true


func _build_stop_audio(node: PlotNode) -> void:
	var bgm_cmd: AudioCommand = AudioCommand.new()
	bgm_cmd.stop = true
	node.bgm = bgm_cmd
	var sfx_cmd: AudioCommand = AudioCommand.new()
	sfx_cmd.stop = true
	node.sfx_short = sfx_cmd
	var amb_cmd: AudioCommand = AudioCommand.new()
	amb_cmd.stop = true
	node.ambience = amb_cmd


func _parse_ch(node: PlotNode, args: Array[String], line_no: int = 0) -> bool:
	if args.is_empty() or args[0].is_empty():
		push_warning("ScriptParser: @ch missing character (line ", line_no, ")")
		return false
	if args[0].to_lower() == "clear":
		node.ch = "__CLEAR__"
	else:
		node.ch = AssetResolver.resolve_ch(args[0])
	return true


## @settime / @timeset / @sidesettime / @sidetimeset
## 只声明"时间推进到这个日期"，日期切换过场由 FlowManager 决定何时播放。
## 日期串支持 MM-DD / YY-MM-DD，分隔符 "-" 或 "."。
func _parse_settime(node: PlotNode, args: Array[String], line_no: int, is_side: bool) -> bool:
	if args.is_empty() or args[0].is_empty():
		push_warning("ScriptParser: @settime 系列缺少日期 (line ", line_no, ")")
		return false
	node.type = "settime"
	node.expression = args[0]
	node.note = "side" if is_side else ""
	return true


# ═══════════════════════════════════════════════════════════════
# 对话解析
# ═══════════════════════════════════════════════════════════════

## 解析一行对话 / 旁白。
##
## 说话者判定（四条同时满足才算对话）：
##   1. 行首 MAX_SPEAKER_LEN 个字符内出现冒号（半角 : 或全角 ：）
##   2. 冒号前的内容不含引号与句读（叙述文字的特征字符）
##   3. 冒号后的正文非空
##   4. 冒号前不是"已知说话者 + 叙述片段"（`何肖白了他一眼：…` 这类旁白）
## 第 3 条：`然后他对全班说：` 若被当成对话，会生成"有说话者但正文为空"的节点 ——
## 对话框与姓名框都拿不到可显示内容。
func _parse_dialogue(line: String, last_who: String, line_no: int = 0) -> PlotNode:
	var who: String = ""
	var text: String = line

	var parts: PackedStringArray = _split_speaker(line)
	if not parts.is_empty() and not _is_clause_prefix(parts[0]):
		who = parts[0]
		text = parts[1]

	var node: PlotNode = _make_node("text", line_no)
	node.ZH = text
	node.who = who

	# 旁白：从对话切到旁白时清掉立绘（历史行为）
	# 注意：说话者不再写进 ch —— 立绘只由 @ch 与 VNInterface 的角色映射决定
	if who.is_empty() and not last_who.is_empty():
		node.ch = "__CLEAR__"

	return node


## 把一行切成 [说话者, 正文]；不是对话行返回空数组。
## 只做语法切分，不做"是否叙述片段"的判断（见 _is_clause_prefix）。
func _split_speaker(line: String) -> PackedStringArray:
	var sep: int = _find_speaker_colon(line)
	if sep <= 0:
		return PackedStringArray()
	var candidate: String = line.substr(0, sep).strip_edges()
	var body: String = line.substr(sep + 1).strip_edges()
	if body.is_empty() or _starts_with_ascii_quote(body) or not _is_valid_speaker(candidate):
		return PackedStringArray()
	return PackedStringArray([candidate, body])


## 预扫描：收集本篇中"独立出现过"的说话者 token。
## 只有能单独成名的写法才进集合 —— `何肖：…` 让 `何肖` 成为 token，
## 于是 `何肖白了他一眼：…` 就能被识别成旁白。
func _collect_speaker_tokens(lines: Array[String]) -> Dictionary:
	var tokens: Dictionary = {}
	for i: int in range(lines.size()):
		var line: String = lines[i].strip_edges()
		if line.is_empty():
			continue
		var head: int = line.unicode_at(0)
		if head == CP_AT or head == CP_DASH:
			continue
		var parts: PackedStringArray = _split_speaker(line)
		if parts.is_empty():
			continue
		var token: String = parts[0]
		tokens[token] = int(tokens.get(token, 0)) + 1
	return tokens


## 候选是不是"已知说话者 + 叙述片段"（`何肖白了他一眼`、`我换了个提议`）。
## 判定：候选可以拆成 <本篇出现过的说话者 token> + <以汉字开头的片段>。
## 例外（保留为说话者）：token 后接 的/得/地/之（`漆诚的声音`）、
## 接符号（`马武 / 曾允峰`）、接字母数字（`女生A`、`男生B` 这类变体标签）。
func _is_clause_prefix(candidate: String) -> bool:
	if _speaker_tokens.is_empty() or candidate.length() < 2:
		return false
	var last: int = candidate.length() - 1
	for k: int in range(1, last + 1):
		var prefix: String = candidate.substr(0, k)
		if not _speaker_tokens.has(prefix):
			continue
		var rest: String = candidate.substr(k).strip_edges()
		if rest.is_empty():
			continue
		var rest_head: String = rest[0]
		if CLAUSE_TAIL_EXCLUDE.find(rest_head) >= 0:
			continue
		if not _is_cjk_ideograph(rest_head.unicode_at(0)):
			continue
		return true
	return false


## CJK 表意文字（区分"叙述片段"与"变体标签后缀"）
func _is_cjk_ideograph(cp: int) -> bool:
	return (cp >= 0x4E00 and cp <= 0x9FFF) or (cp >= 0x3400 and cp <= 0x4DBF)


## 在行首 MAX_SPEAKER_LEN + 1 范围内找第一个冒号，找不到返回 -1。
func _find_speaker_colon(line: String) -> int:
	var limit: int = mini(line.length(), MAX_SPEAKER_LEN + 1)
	for i: int in range(limit):
		var cp: int = line.unicode_at(i)
		if cp == CP_COLON or cp == CP_COLON_WIDE:
			return i
	return -1


## 冒号前的内容是否像"说话者名字"而不是叙述文字。
func _is_valid_speaker(candidate: String) -> bool:
	if candidate.is_empty() or candidate.length() > MAX_SPEAKER_LEN:
		return false
	for i: int in range(candidate.length()):
		if SPEAKER_REJECT_CHARS.find(candidate[i]) >= 0:
			return false
	return true


## 正文以 ASCII 引号开头 → 说明冒号前是叙述（他说："……"），整行按旁白处理。
## 全角引号（“”「」）在中文剧本里常直接当台词引号，不作为旁白判据。
func _starts_with_ascii_quote(text: String) -> bool:
	if text.is_empty():
		return false
	var cp: int = text.unicode_at(0)
	return cp == CP_DQUOTE or cp == CP_SQUOTE


# ═══════════════════════════════════════════════════════════════
# 选择解析
# ═══════════════════════════════════════════════════════════════

## 连续的 "- " 行共用同一个 select 节点（节点表里它们紧挨着）。
func _ensure_select_node(nodes: Array[PlotNode]) -> PlotNode:
	if not nodes.is_empty():
		var last: PlotNode = nodes[nodes.size() - 1]
		if last.type == "select":
			return last
	var sel: PlotNode = _make_node("select")
	sel.options = []
	_append_node(nodes, sel)
	return sel


## "- 文本 { expr1; expr2 }"（可选 -> _rechoose）
func _parse_option(line: String, line_no: int = 0) -> PlotOption:
	var option: PlotOption = PlotOption.new()
	var content: String = line.substr(1).strip_edges()

	# 先剥花括号 actions 块（rfind 保证是最后一个 "{"）
	var brace_start: int = content.rfind("{")
	if brace_start >= 0 and content.ends_with("}"):
		var actions_block: String = content.substr(brace_start + 1, content.length() - brace_start - 2)
		content = content.substr(0, brace_start).strip_edges()
		for action: String in actions_block.split(";"):
			var expr: String = action.strip_edges()
			if not expr.is_empty():
				option.actions.append(expr)

	var text: String = content
	var arrow: int = content.find("->")
	if arrow > 0:
		text = content.substr(0, arrow).strip_edges()
		_apply_option_marker(option, content.substr(arrow + 2).strip_edges(), line_no)
	elif arrow == 0:
		push_warning("ScriptParser: option missing text before '->' (line ", line_no, ")")
		text = content.substr(2).strip_edges()

	option.ZH = text
	option.EN = ""
	if text.is_empty():
		push_warning("ScriptParser: empty option text (line ", line_no, ")")
	return option


## 选项目标语法已删除 —— 选项只能写状态（actions），去哪由段末 @return 交给 FlowManager。
## 仅保留两个本地标记：->_continue（无操作，可读性用）与 ->_rechoose（退回最近选择）。
func _apply_option_marker(option: PlotOption, target: String, line_no: int = 0) -> void:
	var marker: String = target.strip_edges().to_lower()
	if marker.is_empty() or marker == "_continue":
		return
	if marker == "_rechoose":
		option.rechoose = true
		return
	push_error("ScriptParser: 选项目标 '-> ", target, "' 已删除 (line ", line_no,
		") —— 请用 { 状态表达式 } 记录选择，段末用 @return 交给 FlowManager")


# ═══════════════════════════════════════════════════════════════
# 反应块（缩进格式）
# ═══════════════════════════════════════════════════════════════

## 收集 option 行之后所有缩进行，解析为反应节点。
## 返回 {"nodes": Array[PlotNode], "next": 下一个未消费的行下标}
func _parse_reactions(lines: Array[String], line_nos: Array[int], start_idx: int) -> Dictionary:
	var reaction_lines: Array[String] = []
	var reaction_nos: Array[int] = []
	var idx: int = start_idx
	while idx < lines.size():
		var raw_line: String = lines[idx]
		if not _is_indented(raw_line):
			break
		reaction_lines.append(raw_line.strip_edges())
		reaction_nos.append(line_nos[idx])
		idx += 1

	if reaction_lines.is_empty():
		var empty: Array[PlotNode] = []
		return {"nodes": empty, "next": start_idx}

	return {"nodes": _parse_reaction_lines(reaction_lines, reaction_nos), "next": idx}


func _parse_reaction_lines(rlines: Array[String], rnos: Array[int]) -> Array[PlotNode]:
	var nodes: Array[PlotNode] = []
	# 反应块独立条件栈 —— 避免与外层剧本的 @if/@endif 交叉闭合
	var cond_stack: Array[Dictionary] = []
	var last_who: String = ""

	for ri: int in range(rlines.size()):
		var line: String = rlines[ri]
		if line.is_empty():
			continue
		var line_no: int = rnos[ri]
		var head: int = line.unicode_at(0)

		if head == CP_AT:
			var cmd_args: PackedStringArray = _split_command(line)
			var cmd: String = cmd_args[0]
			if FLOW_COMMANDS.has(cmd):
				_parse_flow_directive(cmd, cmd_args[1], nodes, cond_stack, line_no)
				continue
			if cmd in REACTION_FORBIDDEN:
				push_error("ScriptParser: 指令 @", cmd, " 不允许出现在反应块中 (line ", line_no, ")")
				continue
			var node: PlotNode = _parse_directive(cmd, cmd_args[1], line_no)
			if node:
				_append_node(nodes, node)
			continue

		# 选项不能出现在反应块中
		if head == CP_DASH:
			push_warning("ScriptParser: options (-) are not allowed inside reaction blocks (line ",
				line_no, "): ", line)
			continue

		var text_node: PlotNode = _parse_dialogue(line, last_who, line_no)
		_append_node(nodes, text_node)
		last_who = text_node.who

	if not cond_stack.is_empty():
		_close_dangling_ifs(nodes, cond_stack)
	return nodes


func _is_indented(line: String) -> bool:
	if line.is_empty():
		return false
	var cp: int = line.unicode_at(0)
	return cp == CP_SPACE or cp == CP_TAB or cp == CP_IDEO_SPACE


# ═══════════════════════════════════════════════════════════════
# 节点辅助
# ═══════════════════════════════════════════════════════════════

func _make_node(type: String, line_no: int = 0) -> PlotNode:
	var node: PlotNode = PlotNode.new()
	node.type = type
	node.line_number = line_no
	node.ZH = ""
	node.EN = ""
	return node


## 追加节点并返回它在 nodes 中的下标。
## （原实现带 cond_stack 分支但两个分支完全一样 —— @if 内部也是平铺模型）
func _append_node(nodes: Array[PlotNode], node: PlotNode) -> int:
	nodes.append(node)
	return nodes.size() - 1


# ═══════════════════════════════════════════════════════════════
# 工具
# ═══════════════════════════════════════════════════════════════

## "@bg city up" → ["bg", "city up"]（命令名统一小写）
func _split_command(line: String) -> PackedStringArray:
	var body: String = line.substr(1)
	var cut: int = body.length()
	for i: int in range(body.length()):
		var cp: int = body.unicode_at(i)
		if cp == CP_SPACE or cp == CP_TAB or cp == CP_IDEO_SPACE:
			cut = i
			break
	var cmd: String = body.substr(0, cut).to_lower()
	return PackedStringArray([cmd, body.substr(cut).strip_edges()])


## 参数串里第一个空白字符的位置，没有返回 -1。
func _first_whitespace(text: String) -> int:
	for i: int in range(text.length()):
		var cp: int = text.unicode_at(i)
		if cp == CP_SPACE or cp == CP_TAB or cp == CP_IDEO_SPACE:
			return i
	return -1


## 去掉旧格式遗留的外层括号：@bg(path) → path
func _unwrap_parens(text: String) -> String:
	if text.length() < 2:
		return text
	var first: int = text.unicode_at(0)
	var last: int = text.unicode_at(text.length() - 1)
	var open: bool = first == CP_LPAREN or first == CP_LPAREN_WIDE
	var close: bool = last == CP_RPAREN or last == CP_RPAREN_WIDE
	if open and close:
		return text.substr(1, text.length() - 2).strip_edges()
	return text


## 取第 idx 个参数为 float，缺失或非法时用 fallback。
func _float_arg(args: Array[String], idx: int, fallback: float) -> float:
	if idx >= 0 and idx < args.size() and args[idx].is_valid_float():
		return args[idx].to_float()
	return fallback


## 按逗号切参数，括号内的逗号不切。
func _split_args(raw: String) -> Array[String]:
	var args: Array[String] = []
	if raw.is_empty():
		return args
	var depth: int = 0
	var start: int = 0
	for i: int in range(raw.length()):
		var cp: int = raw.unicode_at(i)
		if cp == CP_LPAREN or cp == CP_LPAREN_WIDE:
			depth += 1
		elif cp == CP_RPAREN or cp == CP_RPAREN_WIDE:
			depth = maxi(0, depth - 1)   # 修复：多余的 ')' 不再让后续逗号失效
		elif cp == CP_COMMA and depth == 0:
			args.append(raw.substr(start, i - start).strip_edges())
			start = i + 1
	args.append(raw.substr(start).strip_edges())
	return args
