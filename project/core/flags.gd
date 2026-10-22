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
## Command-line overrides (js URL flags): `--sys=a.b:on,c:off` and `--tun=sys.key:0.5` after `--` on the Godot command line.
## Precedence: command line > saved file > default (same as js).
static var cmd_flags: Dictionary = {}
static var cmd_tuns: Dictionary = {}


static func _init_defaults() -> void:
	if loaded:
		return
	loaded = true
	var cmd := parse_args(OS.get_cmdline_user_args())
	cmd_flags = cmd["sys"]
	cmd_tuns = cmd["tun"]
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
	if cmd_flags.has(id):
		flags[id] = cmd_flags[id]


static func register_tun(sys: String, key: String, default: float, mn: float, mx: float, step: float, desc: String) -> void:
	var id := "%s.%s" % [sys, key]
	tun_info[id] = {"default": default, "min": mn, "max": mx, "step": step, "desc": desc}
	if not tuns.has(id):
		tuns[id] = default
	if cmd_tuns.has(id):
		tuns[id] = clampf(float(cmd_tuns[id]), mn, mx)


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


static func reset_tun(id: String) -> void:
	_init_defaults()
	if tun_info.has(id):
		set_tun(id, tun_info[id]["default"])


static func reset_flag(id: String) -> void:
	_init_defaults()
	if flag_info.has(id):
		set_flag(id, flag_info[id]["default"])


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


static func _apply_cmd() -> void:
	for k in cmd_flags:
		if flag_info.has(k):
			flags[k] = cmd_flags[k]
	for k in cmd_tuns:
		if tun_info.has(k):
			tuns[k] = clampf(float(cmd_tuns[k]), tun_info[k]["min"], tun_info[k]["max"])


# ---------------------------------------------------------------- js-compatible parsing and json (flags.js parseSys/parseTun/toJSON/fromJSON)

const _BAD := ["__proto__", "constructor", "prototype"]


static func safe_name(s: String) -> bool:
	if s.length() == 0 or s.length() >= 80:
		return false
	for i in s.length():
		var c := s.unicode_at(i)
		var ok := (c >= 48 and c <= 57) or (c >= 65 and c <= 90) or (c >= 97 and c <= 122) or c == 95 or c == 46 or c == 45
		if not ok:
			return false
	for part in s.split("."):
		if part in _BAD:
			return false
	return true


static func parse_bool(s: String) -> Variant:
	var t := s.to_lower()
	if t == "on" or t == "1" or t == "true":
		return true
	if t == "off" or t == "0" or t == "false":
		return false
	return null


## "a.b:on,c.d:off" -> {id: bool}. Bad entries are skipped.
static func parse_sys(text: String) -> Dictionary:
	var out := {}
	for part in text.split(","):
		var i := part.rfind(":")
		if i < 1:
			continue
		var id := part.substr(0, i).strip_edges()
		var b: Variant = parse_bool(part.substr(i + 1).strip_edges())
		if safe_name(id) and b != null:
			out[id] = b
	return out


## "sys.key:0.5,..." -> {"sys.key": float} (last dot splits system from key).
static func parse_tun(text: String) -> Dictionary:
	var out := {}
	for part in text.split(","):
		var i := part.rfind(":")
		if i < 1:
			continue
		var path := part.substr(0, i).strip_edges()
		var raw := part.substr(i + 1).strip_edges()
		if path.rfind(".") < 1 or not safe_name(path) or raw == "" or not raw.is_valid_float():
			continue
		out[path] = raw.to_float()
	return out


## User args (after `--`): {sys: {...}, tun: {...}}; later args override earlier ones.
static func parse_args(args: PackedStringArray) -> Dictionary:
	var sys := {}
	var tun := {}
	for a in args:
		if a.begins_with("--sys="):
			sys.merge(parse_sys(a.substr(6)), true)
		elif a.begins_with("--tun="):
			tun.merge(parse_tun(a.substr(6)), true)
	return {"sys": sys, "tun": tun}


## js shape {flags: {id: bool}, tun: {sys: {key: n}}} with only the values that differ from the default.
static func to_json() -> Dictionary:
	_init_defaults()
	var o := {"flags": {}, "tun": {}}
	for id in flag_info:
		if flags[id] != flag_info[id]["default"]:
			o["flags"][id] = flags[id]
	for id in tun_info:
		if not is_equal_approx(float(tuns[id]), float(tun_info[id]["default"])):
			var d := (id as String).rfind(".")
			var s := (id as String).substr(0, d)
			if not o["tun"].has(s):
				o["tun"][s] = {}
			o["tun"][s][(id as String).substr(d + 1)] = tuns[id]
	return o


## Apply a to_json shape (Dictionary or JSON text). Unknown or unsafe entries are ignored. Returns the count applied.
static func from_json(input: Variant) -> int:
	_init_defaults()
	var o: Variant = input
	if o is String:
		var j := JSON.new()
		if j.parse(o) != OK:
			return 0
		o = j.data
	if not (o is Dictionary):
		return 0
	var n := 0
	var fo: Variant = o.get("flags", {})
	if fo is Dictionary:
		for id in fo:
			if id is String and safe_name(id) and fo[id] is bool and flag_info.has(id):
				flags[id] = fo[id]
				n += 1
	var to: Variant = o.get("tun", {})
	if to is Dictionary:
		for s in to:
			if not (s is String) or not safe_name(s) or not (to[s] is Dictionary):
				continue
			for k in to[s]:
				var id := "%s.%s" % [s, k]
				if k is String and safe_name(k) and tun_info.has(id) and (to[s][k] is float or to[s][k] is int):
					tuns[id] = clampf(float(to[s][k]), tun_info[id]["min"], tun_info[id]["max"])
					n += 1
	if n > 0:
		_save()
	return n
