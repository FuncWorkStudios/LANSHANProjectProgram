## FlowManager : Node (Autoload)
## 全局剧情流主管 —— 唯一的"下一段去哪"决定者。
##
## 剧本里不再写目的地：`@return` 只表示"本段到此结束"，`@settime` 只表示"时间推进了"。
## 所有去向都由本单例依据 from_plot + 会话上下文 + 存档变量 决定：
##   · 章节链（CHAPTER_CHAIN）      → 加载下一段剧情（电影式章节过渡由 VN 执行）
##   · 支线段落结束（sidestory）    → 回主线并恢复进支线前的快照
##   · mini 会话结束（mini）        → 关闭 mini VN，回到打开它的界面
##   · 最终章结束（FINAL_PLOTS）    → 回标题
##   · 日期节拍（date_beat）        → 播放日期切换过场，播完 VN 自己续跑
##
## 协议：
##   VN → FlowManager：flow_return 包
##     {"requests": [{"type": "end_segment" | "date_beat"}],
##      "from_plot": "chapter2", "node_index": 749, "context": "main"|"sidestory"|"mini"}
##   FlowManager → VN：execute_flow_load / restore_main_story / exit_mini / play_date_switch
##
## 想改剧情走向（新增章节、支线分流、条件跳场景），只改本文件的 CHAPTER_CHAIN /
## FINAL_PLOTS / _resolve()，不需要动剧本。
extends Node

## 章节推进链：某段结束 → 下一段。新增主线章节只需要改这张表。
const CHAPTER_CHAIN: Dictionary = {
	"intro": "chapter1",
	"chapter1": "chapter2",
	"chapter2": "chapter3",
	"chapter3": "chapter4",
}

## 这些段落结束时回标题
const FINAL_PLOTS: Array[String] = ["chapter4"]

## 会话上下文（由 VNInterface 上报）
const CTX_MAIN: String = "main"
const CTX_SIDESTORY: String = "sidestory"
const CTX_MINI: String = "mini"


## VNInterface.flow_return 信号回调（SceneManager 接线，bind VN 实例）。
func _on_flow_return(package: Dictionary, vn: VNInterface) -> void:
	# 守卫：VN 场景可能在请求送达前被销毁（异常退场等），丢弃并记录
	if not is_instance_valid(vn):
		push_warning("FlowManager: VN 实例已失效，丢弃请求包 — ", package)
		return

	var requests: Array = package.get("requests", [])
	for req: Dictionary in requests:
		_handle(req, package, vn)


func _handle(request: Dictionary, package: Dictionary, vn: VNInterface) -> void:
	match String(request.get("type", "")):
		"date_beat":
			# 日期推进节拍 —— 播放策略集中在这里（将来可做快进/跳过/合并）
			vn.play_date_switch()
		"end_segment":
			_run(_resolve(package), vn)
		_:
			push_error("FlowManager: 未知请求类型 '", request.get("type", ""), "'")


## 路由表：段落结束 → 下一步动作。所有"去哪"的判断都收敛在这里。
func _resolve(package: Dictionary) -> Dictionary:
	var from_plot: String = String(package.get("from_plot", ""))
	var context: String = String(package.get("context", CTX_MAIN))

	if context == CTX_MINI:
		return {"action": "close_mini"}
	if context == CTX_SIDESTORY:
		return {"action": "back_to_main"}
	if CHAPTER_CHAIN.has(from_plot):
		return {"action": "next_plot", "plot_id": CHAPTER_CHAIN[from_plot], "node_index": 0}
	if from_plot in FINAL_PLOTS:
		return {"action": "title"}

	push_error("FlowManager: 段落 '", from_plot, "' 结束但路由表里没有规则（context=", context,
		"）—— 已回标题兜底。请在 CHAPTER_CHAIN / FINAL_PLOTS 里补规则。")
	return {"action": "title"}


func _run(plan: Dictionary, vn: VNInterface) -> void:
	match String(plan.get("action", "")):
		"next_plot":
			vn.execute_flow_load(String(plan.get("plot_id", "")), int(plan.get("node_index", 0)))
		"back_to_main":
			vn.restore_main_story()
		"close_mini":
			vn.exit_mini()
		"goto_scene":
			EventBus.scene_changed.emit(String(plan.get("scene", "")))
		"title":
			EventBus.scene_changed.emit("TITLE")
		_:
			push_error("FlowManager: 非法动作 '", plan.get("action", ""), "'")
