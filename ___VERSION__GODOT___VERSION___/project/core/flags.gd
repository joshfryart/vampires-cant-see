class_name Flags
extends RefCounted
## Ports the useful part of js/flags.js: named boolean feature flags and numeric tunables (with ranges) that the F9 panel
## edits and that persist in user://flags.json. Vessel flag and tunables are registered below.

const PATH := "user://flags.json"

static var flags: Dictionary = {}
static var flag_info: Dictionary = {}
static var tuns: Dictionary = {}
static var tun_info: Dictionary = {}
static var loaded := false
## Tests turn this off so a developer's flags file never changes a parity result.
static var persist := true


static func _init_defaults() -> void:
	if loaded:
		return
	loaded = true
	register("dev.showFps", false, "Show the FPS/debug overlay (F3)")
	register("vis.vessels", true, "Circulatory pulse on villagers")
	register_tun("vessels", "alpha", 0.75, 0.0, 1.0, 0.05, "Vessel node base alpha")
	register_tun("vessels", "size", 0.9, 0.3, 3.0, 0.1, "Vessel dot size")
	register_tun("vessels", "hot", 1.0, 0.0, 2.0, 0.1, "Hotspot bloom scale (carotid, femoral, radial)")
	register_tun("vessels", "veins", 0.6, 0.0, 1.0, 0.05, "Vein alpha vs arteries")
	register_tun("vessels", "halo", 0.2, 0.0, 1.0, 0.05, "Soft halo alpha at quality 2+")
	register_tun("vessels", "pwvScale", 1.75, 1.0, 3.0, 0.05, "Pulse wave slow-down (travel delay x this)")
	register_tun("vessels", "minQuality", 1.0, 1.0, 3.0, 1.0, "Lowest render quality that draws vessels")
	register_tun("vessels", "edges", 0.45, 0.0, 1.0, 0.05, "Vessel edge line alpha (quality 2+)")
	register_tun("vessels", "window", 0.35, 0.0, 1.0, 0.05, "Vessel alpha seen through a window (x distance falloff)")
	register_tun("vessels", "windowRange", 2.5, 0.5, 5.0, 0.25, "Cells within which vessels show through glass")
	register_tun("vessels", "lowGamma", 0.5, 0.2, 1.0, 0.05, "Ease weak hearts (stateK < 1) so the core still shows when nearly drained")
	register_tun("vessels", "highlight", 1.0, 0.0, 2.0, 0.1, "Travelling highlight alpha along the edges")
	register_tun("figure", "budgetMs", 2.5, 0.5, 8.0, 0.25, "Volumetric figure draw budget per frame (ms); the rest draw as lines")
	var f := FileAccess.open(PATH, FileAccess.READ) if persist else null
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
	var f := FileAccess.open(PATH, FileAccess.WRITE) if persist else null
	if f != null:
		f.store_string(JSON.stringify({"flags": flags, "tuns": tuns}))
	People.vessels_on = flags.get("vis.vessels", true) == true
