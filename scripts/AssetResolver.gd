## AssetResolver : RefCounted
## 将裸文件名（带或不带扩展名）解析为完整资源路径。
## 上下文感知：根据命令类型在正确的目录中搜索。
## 完整路径（以 / 或 res:// 开头）保持不变通过。
##
## 文件名匹配不区分大小写且与分隔符无关：
##   LinZixin_Happy ≡ linzixin-happy ≡ LINZIXIN HAPPY ≡ linzixinhappy
class_name AssetResolver extends RefCounted

# ── 按资源类型划分的搜索目录 ──────────────────────────────

const BG_DIRS: Array[String] = [
	"res://assets/backgrounds/scenes/",
	"res://assets/backgrounds/menu/",
	"res://assets/backgrounds/",
]

const CHAR_DIRS: Array[String] = [
	"res://assets/characters/",
]

const MUSIC_DIRS: Array[String] = [
	"res://assets/music/",
]

const SFX_DIRS: Array[String] = [
	"res://assets/sfx/",
]

const AMBIENCE_DIRS: Array[String] = [
	"res://assets/sfx/",
]

# 顶级回退 — 搜索 assets/ 下的所有内容
const FALLBACK_DIRS: Array[String] = [
	"res://assets/",
]

# ── 扩展名 ─────────────────────────────────────────────────────

const IMAGE_EXTS: Array[String] = [".png", ".jpg", ".jpeg", ".webp", ".bmp"]
const AUDIO_EXTS: Array[String] = [".mp3", ".ogg", ".wav", ".mp4"]

# ── 缓存 ──────────────────────────────────────────────────────────

static var _cache: Dictionary = {}
static var _dir_listing_cache: Dictionary = {}

# ── 公共 API ─────────────────────────────────────────────────────

## 解析背景图片路径。
static func resolve_bg(path: String) -> String:
	return _resolve(path, BG_DIRS, IMAGE_EXTS, "bg")


## 解析角色精灵路径。
static func resolve_ch(path: String) -> String:
	return _resolve(path, CHAR_DIRS, IMAGE_EXTS, "ch")


## 解析音乐（BGM）路径。
static func resolve_music(path: String) -> String:
	return _resolve(path, MUSIC_DIRS, AUDIO_EXTS, "music")


## 解析长音效路径。
static func resolve_sfx(path: String) -> String:
	return _resolve(path, SFX_DIRS, AUDIO_EXTS, "sfx")


## 解析短音效路径。
static func resolve_sfx_short(path: String) -> String:
	return _resolve(path, SFX_DIRS, AUDIO_EXTS, "sfx_short")


## 解析环境音路径。
static func resolve_ambience(path: String) -> String:
	return _resolve(path, AMBIENCE_DIRS, AUDIO_EXTS, "ambience")


## 通用解析 — 尝试所有常见资源目录，使用图片和音频扩展名。
static func resolve_any(path: String) -> String:
	var result: String = _resolve(path, BG_DIRS, IMAGE_EXTS, "any_bg")
	if result != path:
		return result
	result = _resolve(path, CHAR_DIRS, IMAGE_EXTS, "any_ch")
	if result != path:
		return result
	result = _resolve(path, MUSIC_DIRS, AUDIO_EXTS, "any_music")
	if result != path:
		return result
	result = _resolve(path, SFX_DIRS, AUDIO_EXTS, "any_sfx")
	if result != path:
		return result
	return path


## 清除所有缓存（在运行时资源更改时调用）。
static func clear_cache() -> void:
	_cache.clear()
	_dir_listing_cache.clear()


# ── 模糊名称辅助函数 ─────────────────────────────────────────────

## 规范化文件名用于模糊比较：
## 小写 + 去除分隔符（_, -, 空格）。
static func _normalize_name(s: String) -> String:
	return s.to_lower().replace("_", "").replace("-", "").replace(" ", "")


## 返回 @s 中最后一个点的索引，如果没有则返回 -1。
static func _last_dot_index(s: String) -> int:
	var idx: int = s.rfind(".")
	if idx < 0:
		return -1
	return idx


## 从 @s 获取扩展名（包括点），如果没有则返回 ""。
static func _get_ext(s: String) -> String:
	var idx: int = _last_dot_index(s)
	if idx < 0:
		return ""
	return s.substr(idx).to_lower()


## 从 @s 获取基础名称（不含扩展名）。
static func _get_base(s: String) -> String:
	var idx: int = _last_dot_index(s)
	if idx < 0:
		return s
	return s.substr(0, idx)


## 列出目录中的所有文件。当 @recurse 为 true 时，还包括
## 直接子目录（一层深）中的文件，前缀为子目录名（例如 "LinZixin/LinZixin_normal.png"）。
## 结果按 (dir_path, recurse) 对进行缓存。
static func _list_dir(dir_path: String, recurse: bool = false) -> Array[String]:
	var cache_key: String = dir_path + ("__r" if recurse else "__f")
	if _dir_listing_cache.has(cache_key):
		return _dir_listing_cache[cache_key]

	var files: Array[String] = []
	var da := DirAccess.open(dir_path)
	if not da:
		_dir_listing_cache[cache_key] = files
		return files

	da.list_dir_begin()
	var f: String = da.get_next()
	while not f.is_empty():
		if da.current_is_dir():
			if recurse:
				# 一层深 — 扫描子目录
				var sub_path: String = dir_path + f + "/"
				var sub_da := DirAccess.open(sub_path)
				if sub_da:
					sub_da.list_dir_begin()
					var sf: String = sub_da.get_next()
					while not sf.is_empty():
						if not sub_da.current_is_dir():
							files.append(f + "/" + sf)
						sf = sub_da.get_next()
					sub_da.list_dir_end()
		else:
			files.append(f)
		f = da.get_next()
	da.list_dir_end()

	_dir_listing_cache[cache_key] = files
	return files


# ── 内部解析 ───────────────────────────────────────────────

## 核心解析逻辑。
##
## 匹配规则（按输入形状）：
##   res://... 或 /...    → 保持不变通过（完整路径）
##   name.ext               → 仅精确匹配（给定扩展名）
##   sub/name.ext           → 仅精确匹配（给定路径 + 扩展名）
##   sub/name               → 仅精确匹配（给定路径，无扩展名）
##   barename               → 精确匹配后模糊匹配（裸名称，无扩展名，无 /）
##
## 模糊匹配 = 不区分大小写 + 与分隔符无关（见 _normalize_name）。
static func _resolve(path: String, dirs: Array[String], exts: Array[String], cache_prefix: String = "") -> String:
	if path.is_empty():
		return path

	# 完整路径保持不变通过
	if path.begins_with("res://") or path.begins_with("/"):
		return path

	# 缓存命中 — 使用带类型前缀的 key，防止 bg/sfx/music 同名冲突
	var cache_key: String = cache_prefix + ":" + path if not cache_prefix.is_empty() else path
	if _cache.has(cache_key):
		return _cache[cache_key]

	var input_ext: String = _get_ext(path)
	var input_base: String = _get_base(path)
	var has_known_ext: bool = input_ext in exts
	var has_separator: bool = "/" in path

	# ── 精确匹配快速路径 ──
	if has_known_ext:
		var result: String = _search_exact(path, dirs, cache_key)
		if result != path:
			return result
		# 给定扩展名 → 仅精确匹配，无模糊回退。
		# 回退到备用目录（仅精确匹配），然后警告。
	elif has_separator:
		var result: String = _search_exact_with_exts(path, dirs, exts, cache_key)
		if result != path:
			return result
		# 给定路径 → 仅精确匹配，无模糊回退。
		# 回退到备用目录（仅精确匹配），然后警告。
	else:
		# 裸名称（无扩展名，无 /）— 先精确匹配，然后模糊匹配。
		var result: String = _search_exact_with_exts(path, dirs, exts, cache_key)
		if result != path:
			return result

		# ── 模糊匹配（仅裸名称）──
		for ext in exts:
			result = _search_fuzzy(path, input_base, ext, dirs, cache_key)
			if result != path:
				return result

		# 回退：模糊搜索整个资源树
		if dirs != FALLBACK_DIRS:
			for ext in exts:
				result = _search_fuzzy(path, input_base, ext, FALLBACK_DIRS, cache_key)
				if result != path:
					return result

		return path

	# ── 路径/扩展名的仅精确匹配回退 — 搜索整个资源 ──
	if dirs != FALLBACK_DIRS:
		if has_known_ext:
			var result: String = _search_exact(path, FALLBACK_DIRS, cache_key)
			if result != path:
				return result
		else:
			var result: String = _search_exact_with_exts(path, FALLBACK_DIRS, exts, cache_key)
			if result != path:
				return result

	push_warning("AssetResolver: Could not resolve '", path, "'")
	return path


# ── 精确匹配 ─────────────────────────────────────────────────

## 在每个目录中尝试精确的 ResourceLoader.exists() 匹配。
static func _search_exact(filename: String, dirs: Array[String], cache_key: String = "") -> String:
	var ck: String = cache_key if not cache_key.is_empty() else filename
	for dir in dirs:
		var full: String = dir + filename
		if ResourceLoader.exists(full):
			_cache[ck] = full
			return full
		var fname: String = filename.get_file()
		if fname != filename:
			full = dir + fname
			if ResourceLoader.exists(full):
				_cache[ck] = full
				return full
	return filename


## 尝试追加每个扩展名的精确匹配。
static func _search_exact_with_exts(base: String, dirs: Array[String], exts: Array[String], cache_key: String = "") -> String:
	var ck: String = cache_key if not cache_key.is_empty() else base
	for dir in dirs:
		for ext in exts:
			var full: String = dir + base + ext
			if ResourceLoader.exists(full):
				_cache[ck] = full
				return full
		var fname: String = base.get_file()
		if fname != base:
			for ext in exts:
				var full: String = dir + fname + ext
				if ResourceLoader.exists(full):
					_cache[ck] = full
					return full
	return base


# ── 模糊匹配 ─────────────────────────────────────────────────

## 搜索目录中规范化名称匹配 @input_base + @wanted_ext 的文件。
## @original_key 是未修改的用户输入，用作缓存键。
## 对于通常有子目录的目录（角色、顶级资源）使用递归列表。
static func _search_fuzzy(original_key: String, input_base: String, wanted_ext: String, dirs: Array[String], cache_key: String = "") -> String:
	var ck: String = cache_key if not cache_key.is_empty() else original_key
	var norm: String = _normalize_name(input_base)

	for dir in dirs:
		# 对于包含子目录的目录使用递归列表
		var recurse: bool = dir in CHAR_DIRS or dir in FALLBACK_DIRS
		var files: Array[String] = _list_dir(dir, recurse)
		for f in files:
			if _get_ext(f) != wanted_ext:
				continue
			# 仅比较文件名部分（最后一个 / 之后），
			# 因此 "LinZixin/LinZixin_happy.png" 匹配 "LinZixin_happy"。
			var file_part: String = f.get_file()
			if _normalize_name(_get_base(file_part)) == norm:
				var full: String = dir + f
				_cache[ck] = full
				return full

	return original_key  # not found — return original input as signal
