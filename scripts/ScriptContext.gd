## ScriptContext : RefCounted
## 运行时变量容器，提供 global / local 两级作用域。
##
## global — 跨场景持久（好感度、关键 flag 等）
## local  — 当前场景内（临时计数器、一次性 flag）
## 查找时先 local 后 global；@set 默认写入 local。
class_name ScriptContext extends RefCounted

var _global_vars: Dictionary = {}
var _local_vars: Dictionary = {}


## 获取变量值 — 先查 local，再查 global，都不存在返回 0。
func get_var(name: String) -> Variant:
	if _local_vars.has(name):
		return _local_vars[name]
	if _global_vars.has(name):
		return _global_vars[name]
	return 0


## 直接写入 local 作用域。
func set_var(name: String, value: Variant) -> void:
	_local_vars[name] = value


## 解析并执行赋值表达式，如 "affection += 10" 或 "flag = true"。
## global = false → 写入 local（默认）；global = true → 写入 global（跨场景持久）。
func apply_expression(expr: String, global_scope: bool = false) -> void:
	if expr.is_empty():
		return

	# 解析 var op value 格式
	var parsed: Dictionary = _parse_assignment(expr)
	if parsed.is_empty():
		push_warning("ScriptContext: cannot parse expression — ", expr)
		return

	var var_name: String = parsed["var"]
	var op: String = parsed["op"]
	var value_expr: String = parsed["value"]

	# 求值右侧表达式
	var rhs: Variant = ScriptExpression.evaluate(value_expr, self)

	# 根据作用域选存储位置
	var target: Dictionary = _global_vars if global_scope else _local_vars
	var current: Variant = target.get(var_name, 0) if op != "=" else 0

	# 应用运算符
	match op:
		"=":
			target[var_name] = rhs
		"+=", "-=", "*=", "/=":
			# current 从目标作用域取（而非 get_var 的 local→global 回退）
			match op:
				"+=": target[var_name] = current + rhs
				"-=": target[var_name] = current - rhs
				"*=": target[var_name] = current * rhs
				"/=": target[var_name] = current / rhs
		_:
			push_warning("ScriptContext: unknown operator ", op, " in — ", expr)


## 解析 "var op value" 为 { var, op, value } 字典。
func _parse_assignment(expr: String) -> Dictionary:
	# 支持的运算符（按长度降序，避免 += 被误匹配为 =）
	var ops: Array[String] = ["+=", "-=", "*=", "/=", "="]
	for op_str: String in ops:
		var op_idx: int = expr.find(op_str)
		if op_idx > 0:
			var var_name: String = expr.substr(0, op_idx).strip_edges()
			var value_expr: String = expr.substr(op_idx + op_str.length()).strip_edges()
			return {"var": var_name, "op": op_str, "value": value_expr}
	return {}


## 场景切换时清空 local 变量。
func clear_local() -> void:
	_local_vars.clear()


## 序列化为存档格式。
func to_dict() -> Dictionary:
	return {
		"global": _global_vars.duplicate(),
		"local": _local_vars.duplicate(),
	}


## 从存档恢复。
func from_dict(d: Dictionary) -> void:
	if d.is_empty():
		return
	_global_vars = d.get("global", {}).duplicate()
	_local_vars = d.get("local", {}).duplicate()
