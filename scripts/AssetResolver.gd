## AssetResolver : RefCounted
## Resolves bare filenames (with or without extension) to full asset paths.
## Context-aware: uses the command type to search in the right directories.
## Full paths (starting with / or res://) pass through unchanged.
##
## Filename matching is case-insensitive and separator-agnostic:
##   LinZixin_Happy ≡ linzixin-happy ≡ LINZIXIN HAPPY ≡ linzixinhappy
class_name AssetResolver extends RefCounted

# ── Search directories per asset type ──────────────────────────────

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

# Top-level fallback — search everything under assets/
const FALLBACK_DIRS: Array[String] = [
	"res://assets/",
]

# ── Extensions ─────────────────────────────────────────────────────

const IMAGE_EXTS: Array[String] = [".png", ".jpg", ".jpeg", ".webp", ".bmp"]
const AUDIO_EXTS: Array[String] = [".mp3", ".ogg", ".wav", ".mp4"]

# ── Cache ──────────────────────────────────────────────────────────

static var _cache: Dictionary = {}
static var _dir_listing_cache: Dictionary = {}

# ── Public API ─────────────────────────────────────────────────────

## Resolve a background image path.
static func resolve_bg(path: String) -> String:
	return _resolve(path, BG_DIRS, IMAGE_EXTS)


## Resolve a character sprite path.
static func resolve_ch(path: String) -> String:
	return _resolve(path, CHAR_DIRS, IMAGE_EXTS)


## Resolve a music (BGM) path.
static func resolve_music(path: String) -> String:
	return _resolve(path, MUSIC_DIRS, AUDIO_EXTS)


## Resolve a long SFX path.
static func resolve_sfx(path: String) -> String:
	return _resolve(path, SFX_DIRS, AUDIO_EXTS)


## Resolve a short SFX path.
static func resolve_sfx_short(path: String) -> String:
	return _resolve(path, SFX_DIRS, AUDIO_EXTS)


## Resolve an ambience path.
static func resolve_ambience(path: String) -> String:
	return _resolve(path, AMBIENCE_DIRS, AUDIO_EXTS)


## Generic resolve — tries all common asset directories with both image
## and audio extensions.
static func resolve_any(path: String) -> String:
	var result: String = _resolve(path, BG_DIRS, IMAGE_EXTS)
	if result != path:
		return result
	result = _resolve(path, CHAR_DIRS, IMAGE_EXTS)
	if result != path:
		return result
	result = _resolve(path, MUSIC_DIRS, AUDIO_EXTS)
	if result != path:
		return result
	result = _resolve(path, SFX_DIRS, AUDIO_EXTS)
	if result != path:
		return result
	return path


## Clear all caches (call when assets change at runtime).
static func clear_cache() -> void:
	_cache.clear()
	_dir_listing_cache.clear()


# ── Fuzzy-name helpers ─────────────────────────────────────────────

## Normalize a filename for fuzzy comparison:
## lowercase + strip separators (_, -, space).
static func _normalize_name(s: String) -> String:
	return s.to_lower().replace("_", "").replace("-", "").replace(" ", "")


## Return the index of the last dot in @s, or -1 if none.
static func _last_dot_index(s: String) -> int:
	var idx: int = s.rfind(".")
	if idx < 0:
		return -1
	return idx


## Get the extension (including dot) from @s, or "" if none.
static func _get_ext(s: String) -> String:
	var idx: int = _last_dot_index(s)
	if idx < 0:
		return ""
	return s.substr(idx).to_lower()


## Get the base name (without extension) from @s.
static func _get_base(s: String) -> String:
	var idx: int = _last_dot_index(s)
	if idx < 0:
		return s
	return s.substr(0, idx)


## List all files in a directory.  When @recurse is true, also includes
## files from immediate subdirectories (one level deep), prefixed with
## the subdirectory name (e.g. "LinZixin/LinZixin_normal.png").
## Results are cached per (dir_path, recurse) pair.
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
				# One level deep — scan subdirectory
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


# ── Internal resolve ───────────────────────────────────────────────

## Core resolution logic.
##
## Matching rules (by input shape):
##   res://...  or  /...    → pass through unchanged (full path)
##   name.ext               → exact match only (extension given)
##   sub/name.ext           → exact match only (path + extension given)
##   sub/name               → exact match only (path given, no ext)
##   barename               → exact then fuzzy (bare name, no ext, no /)
##
## Fuzzy = case-insensitive + separator-agnostic (see _normalize_name).
static func _resolve(path: String, dirs: Array[String], exts: Array[String]) -> String:
	if path.is_empty():
		return path

	# Full paths pass through unchanged
	if path.begins_with("res://") or path.begins_with("/"):
		return path

	# Cache hit
	if _cache.has(path):
		return _cache[path]

	var input_ext: String = _get_ext(path)
	var input_base: String = _get_base(path)
	var has_known_ext: bool = input_ext in exts
	var has_separator: bool = "/" in path

	# ── Exact-match fast path ──
	if has_known_ext:
		var result: String = _search_exact(path, dirs)
		if result != path:
			return result
		# Extension given → EXACT ONLY, no fuzzy fallback.
		# Fall through to fallback dirs (exact only), then warn.
	elif has_separator:
		var result: String = _search_exact_with_exts(path, dirs, exts)
		if result != path:
			return result
		# Path given → EXACT ONLY, no fuzzy fallback.
		# Fall through to fallback dirs (exact only), then warn.
	else:
		# Bare name (no ext, no /) — exact first, then fuzzy.
		var result: String = _search_exact_with_exts(path, dirs, exts)
		if result != path:
			return result

		# ── Fuzzy-match (bare-name only) ──
		for ext in exts:
			result = _search_fuzzy(path, input_base, ext, dirs)
			if result != path:
				return result

		# Fallback: fuzzy search whole assets tree
		if dirs != FALLBACK_DIRS:
			for ext in exts:
				result = _search_fuzzy(path, input_base, ext, FALLBACK_DIRS)
				if result != path:
					return result

		return path

	# ── Exact-only fallback for paths/extensions — search whole assets ──
	if dirs != FALLBACK_DIRS:
		if has_known_ext:
			var result: String = _search_exact(path, FALLBACK_DIRS)
			if result != path:
				return result
		else:
			var result: String = _search_exact_with_exts(path, FALLBACK_DIRS, exts)
			if result != path:
				return result

	push_warning("AssetResolver: Could not resolve '", path, "'")
	return path


# ── Exact matching ─────────────────────────────────────────────────

## Try exact ResourceLoader.exists() matches in each directory.
static func _search_exact(filename: String, dirs: Array[String]) -> String:
	for dir in dirs:
		var full: String = dir + filename
		if ResourceLoader.exists(full):
			_cache[filename] = full
			return full
		var fname: String = filename.get_file()
		if fname != filename:
			full = dir + fname
			if ResourceLoader.exists(full):
				_cache[filename] = full
				return full
	return filename


## Try exact match with each extension appended.
static func _search_exact_with_exts(base: String, dirs: Array[String], exts: Array[String]) -> String:
	for dir in dirs:
		for ext in exts:
			var full: String = dir + base + ext
			if ResourceLoader.exists(full):
				_cache[base] = full
				return full
		var fname: String = base.get_file()
		if fname != base:
			for ext in exts:
				var full: String = dir + fname + ext
				if ResourceLoader.exists(full):
					_cache[base] = full
					return full
	return base


# ── Fuzzy matching ─────────────────────────────────────────────────

## Search directories for a file whose normalized name matches
## @input_base + @wanted_ext.  @original_key is the unmodified user
## input, used as the cache key.
## Uses recursive listing for directories that typically have subdirs
## (characters, top-level assets).
static func _search_fuzzy(original_key: String, input_base: String, wanted_ext: String, dirs: Array[String]) -> String:
	var norm: String = _normalize_name(input_base)

	for dir in dirs:
		# Use recursive listing for directories that contain subdirectories
		var recurse: bool = dir in CHAR_DIRS or dir in FALLBACK_DIRS
		var files: Array[String] = _list_dir(dir, recurse)
		for f in files:
			if _get_ext(f) != wanted_ext:
				continue
			# Compare only the file-name portion (after the last /),
			# so "LinZixin/LinZixin_happy.png" matches "LinZixin_happy".
			var file_part: String = f.get_file()
			if _normalize_name(_get_base(file_part)) == norm:
				var full: String = dir + f
				_cache[original_key] = full
				return full

	return original_key  # not found — return original input as signal
