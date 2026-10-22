class_name GameData
extends RefCounted
## Cached access to project/data/*.json (generated from js/data by tools/export-data.mjs; do not hand-edit).

static var _cache: Dictionary = {}


static func get_json(name: String) -> Variant:
	if not _cache.has(name):
		var f := FileAccess.open("res://data/%s.json" % name, FileAccess.READ)
		_cache[name] = JSON.parse_string(f.get_as_text()) if f != null else null
	return _cache[name]


static func maps() -> Dictionary:
	return get_json("maps")


static func map_def(name: String) -> Dictionary:
	return maps()["maps"][name]


static func sounds() -> Dictionary:
	return get_json("sounds")
