## SceneGalleryData : RefCounted
## 场景/背景画廊数据 — 运行时扫描 assets/backgrounds/scenes/ 派生平面列表。
## 条目结构：{name, file, desc}；desc 为场景简介（当前为测试占位空串，后续填充）。
## 旧的分组扫描实现见 ScenesData.gd（暂时无关，保留待用）。
extends RefCounted

const SCAN_DIR: String = "res://assets/backgrounds/scenes/"


# ===================================================================
# 公共 API
# ===================================================================

## 返回全部场景文件的扁平列表（按变体编号排序）。
## 运行时扫描派生，无需手动同步；desc 暂为空串占位。
static func get_flat_entries() -> Array[Dictionary]:
	var raw_files: Array[String] = _scan_dir(SCAN_DIR, ".webp")
	var entries: Array[Dictionary] = []
	for fname: String in raw_files:
		entries.append({"name": _strip_ext(fname), "file": SCAN_DIR + fname, "desc": ""})
	entries.sort_custom(_by_variant)
	return entries


# ===================================================================
# 内部工具
# ===================================================================

## 从文件名中去除扩展名。
static func _strip_ext(fname: String) -> String:
	var dot: int = fname.rfind(".")
	if dot > 0:
		return fname.substr(0, dot)
	return fname


## 按变体编号排序文件：基础版本优先，然后是 1, 2, 3...
static func _by_variant(a: Dictionary, b: Dictionary) -> bool:
	var a_name: String = a.name
	var b_name: String = b.name
	var a_num: int = _extract_variant(a_name)
	var b_num: int = _extract_variant(b_name)
	if a_num != b_num:
		return a_num < b_num
	return a_name < b_name


## 从文件名中提取末尾数字变体（例如 "Autumn3" → 3，"Library" → 0）。
static func _extract_variant(s: String) -> int:
	var i: int = s.length() - 1
	while i >= 0 and s[i].is_valid_int():
		i -= 1
	if i < s.length() - 1:
		return s.substr(i + 1).to_int()
	return 0


## 列出目录中具有给定扩展名的文件（不区分大小写）。
static func _scan_dir(dir_path: String, ext: String) -> Array[String]:
	var files: Array[String] = []
	var da := DirAccess.open(dir_path)
	if not da:
		push_warning("SceneGalleryData: Cannot open directory — ", dir_path)
		return files

	da.list_dir_begin()
	var f: String = da.get_next()
	while not f.is_empty():
		if not da.current_is_dir():
			if f.to_lower().ends_with(ext.to_lower()):
				if not f.ends_with(".import"):
					files.append(f)
		f = da.get_next()
	da.list_dir_end()

	return files
