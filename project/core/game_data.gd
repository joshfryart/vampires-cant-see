class_name GameData
extends RefCounted
## Cached access to project/data/*.json (generated from js/data by tools/export-data.mjs; do not hand-edit).

static var _cache: Dictionary = {}


static func get_json(name: String) -> Variant:
	if not _cache.has(name):
		var f := FileAccess.open("res://data/%s.json" % name, FileAccess.READ)
		_cache[name] = JSON.parse_string(f.get_as_text()) if f != null else null
	return _cache[name]


static var _rogue_cache: Dictionary = {}
## Names registered through register_map (not present in data/maps.json).
static var _generated: Array = []
static var _extra_merged: bool = false


static func maps() -> Dictionary:
	return get_json("maps")


static func map_def(name: String) -> Dictionary:
	return maps()["maps"][name]


## Make a generated map def resolve through map_def()/maps() like the data/maps.json ones. Replaces a same-named generated def.
static func register_map(name: String, def: Dictionary) -> void:
	maps()["maps"][name] = def
	if not _generated.has(name):
		_generated.append(name)


## Remove a generated def. Maps from data/maps.json are never removed. Returns true when something was removed.
static func unregister_map(name: String) -> bool:
	if not _generated.has(name):
		return false
	_generated.erase(name)
	maps()["maps"].erase(name)
	return true


static func clear_generated() -> void:
	for n in _generated.duplicate():
		maps()["maps"].erase(n)
	_generated.clear()


static func generated_names() -> Array:
	return _generated.duplicate()


## project/data/rogue/<name>.json (roguelike data), cached; null when missing.
static func load_rogue(name: String) -> Variant:
	if not _rogue_cache.has(name):
		var f := FileAccess.open("res://data/rogue/%s.json" % name, FileAccess.READ)
		_rogue_cache[name] = JSON.parse_string(f.get_as_text()) if f != null else null
	return _rogue_cache[name]


## Recursively copy keys of src into dst that dst does not have yet. Existing keys are never overwritten.
static func fill_missing(dst: Dictionary, src: Dictionary) -> void:
	for k in src:
		if not dst.has(k):
			dst[k] = src[k].duplicate(true) if (src[k] is Dictionary or src[k] is Array) else src[k]
		elif dst[k] is Dictionary and src[k] is Dictionary:
			fill_missing(dst[k], src[k])


static func sounds() -> Dictionary:
	var s: Dictionary = get_json("sounds")
	if not _extra_merged:
		_extra_merged = true
		var ex: Variant = load_rogue("acoustics_extra")
		if ex is Dictionary and s.get("acoustics") is Dictionary:
			fill_missing(s["acoustics"], ex)
	return s
