class_name Flags
extends RefCounted
## Ports the useful part of js/flags.js: named boolean feature flags and numeric tunables (with ranges) that the F9 panel
## edits and that persist in user://flags.json. Vessels are not ported, so only the flags below exist.

const PATH := "user://flags.json"

static var flags: Dictionary = {}
static var flag_info: Dictionary = {}
static var tuns: Dictionary = {}
static var tun_info: Dictionary = {}
static var loaded := false


static func _init_defaults() -> void:
	if loaded:
		return
	loaded = true
	register("dev.showFps", false, "Show the FPS/debug overlay (F3)")
	register_tun("figure", "budgetMs", 2.5, 0.5, 8.0, 0.25, "Volumetric figure draw budget per frame (ms); the rest draw as lines")
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f != null:
		var v: Variant = JSON.parse_string(f.get_as_text())
		if v is Dictionary:
			var fl: Variant = v.get("flags", {})
			if fl is Dictionary:
				for k in fl:
					if flag_info.has(k) and fl[k] is bool:
						flags[k] = fl[k]
			var tn: Variant = v.get("tuns", {})
			if tn is Dictionary:
				for k in tn:
					if tun_info.has(k) and (tn[k] is float or tn[k] is int):
						tuns[k] = clampf(float(tn[k]), tun_info[k]["min"], tun_info[k]["max"])


static func register(id: String, default: bool, desc: String) -> void:
	flag_info[id] = {"default": default, "desc": desc}
	if not flags.has(id):
		flags[id] = default


static func register_tun(sys: String, key: String, default: float, mn: float, mx: float, step: float, desc: String) -> void:
	var id := "%s.%s" % [sys, key]
	tun_info[id] = {"default": default, "min": mn, "max": mx, "step": step, "desc": desc}
	if not tuns.has(id):
		tuns[id] = default


static func get_flag(id: String) -> bool:
	_init_defaults()
	return flags.get(id, false) == true


static func tun(sys: String, key: String, fallback: float = 0.0) -> float:
	_init_defaults()
	return float(tuns.get("%s.%s" % [sys, key], fallback))


static func set_flag(id: String, on: bool) -> void:
	_init_defaults()
	if not flag_info.has(id):
		return
	flags[id] = on
	_save()


static func set_tun(id: String, v: float) -> void:
	_init_defaults()
	if not tun_info.has(id):
		return
	tuns[id] = clampf(v, tun_info[id]["min"], tun_info[id]["max"])
	_save()


static func reset_all() -> void:
	_init_defaults()
	for k in flag_info:
		flags[k] = flag_info[k]["default"]
	for k in tun_info:
		tuns[k] = tun_info[k]["default"]
	_save()


static func _save() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"flags": flags, "tuns": tuns}))
