## SceneGalleryData : RefCounted
## Scene/background gallery data — scans assets/backgrounds/scenes/
## and groups files by filename prefix for the Scene Gallery screen.
extends RefCounted

# Group definitions: filename prefix → translation key suffix
const GROUPS: Array[Dictionary] = [
	{"prefix": "Autumn",             "id": "Autumn"},
	{"prefix": "BackMountain",       "id": "BackMountain"},
	{"prefix": "BasketballGround",   "id": "BasketballGround"},
	{"prefix": "Book",               "id": "Book"},
	{"prefix": "Building",           "id": "Building"},
	{"prefix": "BuildingDay",        "id": "BuildingDay"},
	{"prefix": "BuildingInside",     "id": "BuildingInside"},
	{"prefix": "Campus",             "id": "Campus"},
	{"prefix": "CityDay",            "id": "CityDay"},
	{"prefix": "CityNight",          "id": "CityNight"},
	{"prefix": "Classroom",          "id": "Classroom"},
	{"prefix": "Cloud",              "id": "Cloud"},
	{"prefix": "CountrySpring",      "id": "CountrySpring"},
	{"prefix": "Countryside",        "id": "Countryside"},
	{"prefix": "CountrysideMarket",  "id": "CountrysideMarket"},
	{"prefix": "CountrysideNight",   "id": "CountrysideNight"},
	{"prefix": "CountrysideSchool",  "id": "CountrysideSchool"},
	{"prefix": "CountrysideSpring",  "id": "CountrysideSpring"},
	{"prefix": "Desk",               "id": "Desk"},
	{"prefix": "DiningHall",         "id": "DiningHall"},
	{"prefix": "DormitoryBuilding",  "id": "DormitoryBuilding"},
	{"prefix": "DormitoryGate",      "id": "DormitoryGate"},
	{"prefix": "FrontGate",          "id": "FrontGate"},
	{"prefix": "Green1",             "id": "Green1"},
	{"prefix": "KejiBuilding",       "id": "KejiBuilding"},
	{"prefix": "Library",            "id": "Library"},
	{"prefix": "LibraryBack",        "id": "LibraryBack"},
	{"prefix": "LibraryBehind",      "id": "LibraryBehind"},
	{"prefix": "LibraryNight",       "id": "LibraryNight"},
	{"prefix": "LibrarySkyWindows",  "id": "LibrarySkyWindows"},
	{"prefix": "LibraryStairs",      "id": "LibraryStairs"},
	{"prefix": "MainRoad",           "id": "MainRoad"},
	{"prefix": "Morning",            "id": "Morning"},
	{"prefix": "Night",              "id": "Night"},
	{"prefix": "NightBuilding",      "id": "NightBuilding"},
	{"prefix": "NightLibrary",       "id": "NightLibrary"},
	{"prefix": "NightMountain",      "id": "NightMountain"},
	{"prefix": "OldBuilding",        "id": "OldBuilding"},
	{"prefix": "OutOfSchool",        "id": "OutOfSchool"},
	{"prefix": "Outside",            "id": "Outside"},
	{"prefix": "OutsideOfTheSchool", "id": "OutsideOfTheSchool"},
	{"prefix": "Path",               "id": "Path"},
	{"prefix": "PathNight",          "id": "PathNight"},
	{"prefix": "Pic4",               "id": "Pic4"},
	{"prefix": "Pic5",               "id": "Pic5"},
	{"prefix": "Pic16",              "id": "Pic16"},
	{"prefix": "Playground",         "id": "Playground"},
	{"prefix": "PlaygroundNight",    "id": "PlaygroundNight"},
	{"prefix": "Rain",               "id": "Rain"},
	{"prefix": "RainBuilding",       "id": "RainBuilding"},
	{"prefix": "RainCity",           "id": "RainCity"},
	{"prefix": "RainDay",            "id": "RainDay"},
	{"prefix": "RainPath",           "id": "RainPath"},
	{"prefix": "RedHouse",           "id": "RedHouse"},
	{"prefix": "Room",               "id": "Room"},
	{"prefix": "RoomDay",            "id": "RoomDay"},
	{"prefix": "RoomNight",          "id": "RoomNight"},
	{"prefix": "RoomNightWithLight", "id": "RoomNightWithLight"},
	{"prefix": "SchoolRoad",         "id": "SchoolRoad"},
	{"prefix": "Sky",                "id": "Sky"},
	{"prefix": "SkyWindow1",         "id": "SkyWindow1"},
	{"prefix": "SportsMeeting",      "id": "SportsMeeting"},
	{"prefix": "Street",             "id": "Street"},
	{"prefix": "Sun",                "id": "Sun"},
	{"prefix": "SunBubbles",         "id": "SunBubbles"},
	{"prefix": "Sunset",             "id": "Sunset"},
	{"prefix": "TeachingBuilding",   "id": "TeachingBuilding"},
	{"prefix": "TeachingBuildingNight", "id": "TeachingBuildingNight"},
	{"prefix": "Tree",               "id": "Tree"},
	{"prefix": "Upstairs",           "id": "Upstairs"},
]

const SCAN_DIR: String = "res://assets/backgrounds/scenes/"


## Scan the backgrounds directory and return grouped results.
## Returns: Array[{group_id: String, files: Array[{file: String, name: String}]}]
static func get_grouped_scenes() -> Array[Dictionary]:
	var grouped: Array[Dictionary] = []

	# Build lookup: normalized prefix → display names
	var prefix_lookup: Dictionary = {}
	for g: Dictionary in GROUPS:
		var prefix: String = g.prefix
		prefix_lookup[prefix] = g

	# Scan directory for .jpg files
	var raw_files: Array[String] = _scan_dir(SCAN_DIR, ".jpg")
	if raw_files.is_empty():
		raw_files = _scan_dir(SCAN_DIR, ".jpeg")

	# Group files by prefix (longest prefix match wins)
	var group_map: Dictionary = {}  # prefix → Array[{file, name}]
	var unmatched_files: Array[Dictionary] = []

	for fname: String in raw_files:
		var matched_prefix: String = _find_prefix(fname, GROUPS)
		if matched_prefix.is_empty():
			unmatched_files.append({"file": SCAN_DIR + fname, "name": _strip_ext(fname)})
		else:
			if not group_map.has(matched_prefix):
				var typed: Array[Dictionary] = []
				group_map[matched_prefix] = typed
			group_map[matched_prefix].append({"file": SCAN_DIR + fname, "name": _strip_ext(fname)})

	# Build result in GROUPS order
	for g: Dictionary in GROUPS:
		var prefix: String = g.prefix
		if group_map.has(prefix):
			var files: Array[Dictionary] = group_map[prefix] as Array[Dictionary]
			files.sort_custom(_by_variant)
			grouped.append({
				"group_id": g.id,
				"files": files,
			})

	# Append unmatched as "Other"
	if unmatched_files.size() > 0:
		unmatched_files.sort_custom(_by_name)
		grouped.append({
			"group_id": "Other",
			"files": unmatched_files,
		})

	return grouped


## Find the longest matching prefix from GROUPS for a given filename.
## Uses case-insensitive prefix match at the start of the filename .
static func _find_prefix(fname: String, groups: Array[Dictionary]) -> String:
	var best: String = ""
	var best_len: int = 0
	var fname_lower: String = fname.to_lower()
	for g: Dictionary in groups:
		var prefix: String = g.prefix
		if fname_lower.begins_with(prefix.to_lower()):
			if prefix.length() > best_len:
				best = prefix
				best_len = prefix.length()
	return best


## Strip file extension from filename.
static func _strip_ext(fname: String) -> String:
	var dot: int = fname.rfind(".")
	if dot > 0:
		return fname.substr(0, dot)
	return fname


## Sort files by variant number: base first, then 1, 2, 3...
static func _by_variant(a: Dictionary, b: Dictionary) -> bool:
	var a_name: String = a.name
	var b_name: String = b.name
	# Extract trailing numbers for sorting
	var a_num: int = _extract_variant(a_name)
	var b_num: int = _extract_variant(b_name)
	if a_num != b_num:
		return a_num < b_num
	return a_name < b_name


static func _by_name(a: Dictionary, b: Dictionary) -> bool:
	return a.name < b.name


## Extract trailing numeric variant from a filename (e.g. "Autumn3" → 3, "Library" → 0).
static func _extract_variant(s: String) -> int:
	var i: int = s.length() - 1
	while i >= 0 and s[i].is_valid_int():
		i -= 1
	if i < s.length() - 1:
		return s.substr(i + 1).to_int()
	return 0


## List files in a directory with the given extension (case-insensitive).
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
