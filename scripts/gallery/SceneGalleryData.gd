## SceneGalleryData : RefCounted
## 场景/背景画廊数据 — 扫描 assets/backgrounds/scenes/
## 并按文件名前缀分组，用于场景画廊屏幕。
##
## GROUP_PREFIXES 是唯一需手动维护的列表（分组白名单 + 显示顺序）。
## 文件条目和分组结果全部由运行时扫描派生，无需手动同步。
extends RefCounted

# 分组前缀白名单，同时决定显示顺序（大小写不敏感，最长匹配获胜）。
# 未匹配任何前缀的文件归入 "Other" 组。
const GROUP_PREFIXES: Array[String] = [
	"Autumn",
	"BackMountain",
	"BasketballGround",
	"Book",
	"Building",
	"BuildingDay",
	"BuildingInside",
	"Campus",
	"CityDay",
	"CityNight",
	"Classroom",
	"Cloud",
	"CountrySpring",
	"Countryside",
	"CountrysideMarket",
	"CountrysideNight",
	"CountrysideSchool",
	"CountrysideSpring",
	"Desk",
	"DiningHall",
	"DormitoryBuilding",
	"DormitoryGate",
	"FrontGate",
	"Green1",
	"KejiBuilding",
	"Library",
	"LibraryBack",
	"LibraryBehind",
	"LibraryNight",
	"LibrarySkyWindows",
	"LibraryStairs",
	"MainRoad",
	"Morning",
	"Night",
	"NightBuilding",
	"NightLibrary",
	"NightMountain",
	"OldBuilding",
	"OutOfSchool",
	"Outside",
	"OutsideOfTheSchool",
	"Path",
	"PathNight",
	"Pic4",
	"Pic5",
	"Pic16",
	"Playground",
	"PlaygroundNight",
	"Rain",
	"RainBuilding",
	"RainCity",
	"RainDay",
	"RainPath",
	"RedHouse",
	"Room",
	"RoomDay",
	"RoomNight",
	"RoomNightWithLight",
	"SchoolRoad",
	"Sky",
	"SkyWindow1",
	"SportsMeeting",
	"Street",
	"Sun",
	"SunBubbles",
	"Sunset",
	"TeachingBuilding",
	"TeachingBuildingNight",
	"Tree",
	"Upstairs",
]

const SCAN_DIR: String = "res://assets/backgrounds/scenes/"


# ===================================================================
# 公共 API
# ===================================================================

## 返回全部场景文件的扁平列表（按变体编号排序）。
## 替代旧的手动 ENTRIES 常量 — 运行时扫描，无需同步维护。
static func get_flat_entries() -> Array[Dictionary]:
	var raw_files: Array[String] = _scan_dir(SCAN_DIR, ".webp")
	var entries: Array[Dictionary] = []
	for fname: String in raw_files:
		entries.append({"name": _strip_ext(fname), "file": SCAN_DIR + fname})
	entries.sort_custom(_by_variant)
	return entries


## 扫描背景目录并返回分组结果。
## 返回：Array[{group_id: String, files: Array[{file: String, name: String}]}]
static func get_grouped_scenes() -> Array[Dictionary]:
	var grouped: Array[Dictionary] = []

	# 扫描目录查找 .webp 文件
	var raw_files: Array[String] = _scan_dir(SCAN_DIR, ".webp")

	# 按前缀分组文件（最长前缀匹配获胜）
	var group_map: Dictionary = {}  # prefix → Array[{file, name}]
	var unmatched_files: Array[Dictionary] = []

	for fname: String in raw_files:
		var matched_prefix: String = _find_prefix(fname)
		if matched_prefix.is_empty():
			unmatched_files.append({"file": SCAN_DIR + fname, "name": _strip_ext(fname)})
		else:
			if not group_map.has(matched_prefix):
				var typed: Array[Dictionary] = []
				group_map[matched_prefix] = typed
			group_map[matched_prefix].append({"file": SCAN_DIR + fname, "name": _strip_ext(fname)})

	# 按 GROUP_PREFIXES 顺序构建结果
	for prefix: String in GROUP_PREFIXES:
		if group_map.has(prefix):
			var files: Array[Dictionary] = group_map[prefix] as Array[Dictionary]
			files.sort_custom(_by_variant)
			grouped.append({
				"group_id": prefix,
				"files": files,
			})

	# 将未匹配的文件追加为 "Other"
	if unmatched_files.size() > 0:
		unmatched_files.sort_custom(_by_name)
		grouped.append({
			"group_id": "Other",
			"files": unmatched_files,
		})

	return grouped


# ===================================================================
# 内部工具
# ===================================================================

## 为给定文件名查找 GROUP_PREFIXES 中最长的匹配前缀。
## 使用不区分大小写的前缀匹配，从文件名开头匹配。
static func _find_prefix(fname: String) -> String:
	var best: String = ""
	var best_len: int = 0
	var fname_lower: String = fname.to_lower()
	for prefix: String in GROUP_PREFIXES:
		if fname_lower.begins_with(prefix.to_lower()):
			if prefix.length() > best_len:
				best = prefix
				best_len = prefix.length()
	return best


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


static func _by_name(a: Dictionary, b: Dictionary) -> bool:
	return a.name < b.name


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
