class_name Schedule
extends RefCounted
## Ports js/schedule.js: night schedules (where each role is until which fraction of the night, and what they do there)
## and the chat roll between two villagers. Pure data and maths; people.gd owns walking.
## The night clock runs 20:00 (0) -> 06:00 (1); 01:00 is 0.5. Place tokens: a map place name ("well") or "@kind" = the
## villager's own home place ("@bed" -> "<home>_bed"). Person schedule state is a Dictionary
## {role, home, stops, si, target, en, retarget}; a stop is {place, x, y, at, until, act}.

const SEATED := ["sleep", "eat", "sit", "mend", "spin", "drink", "pray", "whittle"]
const POSTS := ["square", "street_w", "well", "street_mid", "street_e", "lane_s", "road_s", "street_far"]
const WATCH_STOPS := 12
const CURFEW := 0.5
const CHAT_KINDS := ["chat", "hello", "ignore"]
const CHAT := {
	"family": {"w": [0.7, 0.25, 0.05], "mood": "warm"},
	"default": {"w": [0.25, 0.4, 0.35], "mood": "neutral"},
	"pairs": {
		"drunk|priest": {"w": [0.15, 0.25, 0.6], "mood": "curt"},
		"drunk|guard": {"w": [0.1, 0.3, 0.6], "mood": "curt"},
		"guard|guard": {"w": [0.3, 0.5, 0.2], "mood": "neutral"},
		"elder|priest": {"w": [0.6, 0.3, 0.1], "mood": "warm"},
		"innkeeper|regular": {"w": [0.6, 0.3, 0.1], "mood": "warm"},
		"drunk|innkeeper": {"w": [0.4, 0.3, 0.3], "mood": "neutral"},
		"insomniac|insomniac": {"w": [0.4, 0.4, 0.2], "mood": "neutral"},
	},
	"chatSec": [4.0, 10.0],
	"helloSec": [1.5, 3.0],
}

static var _roles: Dictionary = {}
static var _loaded: bool = false


## role -> schedule template (Array) or "watch", from the archetype data.
static func roles() -> Dictionary:
	if not _loaded:
		_loaded = true
		for a in GameData.get_json("archetypes")["list"]:
			if not (a.get("role") is String) or a["role"] == "" or a.get("schedule") == null:
				continue
			if a["schedule"] is String and a["schedule"] == "watch":
				_roles[a["role"]] = "watch"
			elif a["schedule"] is Array:
				_roles[a["role"]] = a["schedule"]
	return _roles


static func has_role(role: Variant) -> bool:
	return role is String and roles().has(role)


static func is_seated(act: String) -> bool:
	return SEATED.has(act)


## The watch walks the posts all night; slot picks the direction and starting post.
static func watch_role(slot: int) -> Array:
	var n: int = POSTS.size()
	var out: Array = []
	for i in WATCH_STOPS:
		var k: int = ((((-i if slot % 2 != 0 else i) + slot * 3) % n) + n) % n
		out.append([[POSTS[k]], float(i + 1) / WATCH_STOPS, "watch"])
	return out


## Candidate place names for a token: "well" -> ["well"]; "@bed" + home "h2" -> h2_bed, h2_bed2, h2_bed3 (those that exist).
static func candidates(token: String, places: Dictionary, home: Variant) -> Array:
	var base: String
	if token.begins_with("@"):
		base = (str(home) + "_" + token.substr(1)) if (home != null and str(home) != "") else ""
	else:
		base = token
	if base == "":
		return []
	var out: Array = []
	for n in [base, base + "2", base + "3"]:
		if places.has(n):
			out.append(n)
	return out


## Ports build (js/schedule.js:68). places {name: {x, y}}, spawn {x, y} or null, opts {home, slot}; rng is an Rng.
## Returns the stop list or null.
static func build(role: Variant, places: Variant, spawn: Variant, rng: Rng, opts: Dictionary = {}) -> Variant:
	if not has_role(role) or not (places is Dictionary):
		return null
	var slot: int = int(floor(float(opts["slot"]))) if opts.get("slot") is float or opts.get("slot") is int else 0
	var tpl_src: Variant = roles()[role]
	var tpl: Array = watch_role(slot) if tpl_src is String else tpl_src
	var stops: Array = []
	var prev := 0.0
	for i in tpl.size():
		var last: bool = i == tpl.size() - 1
		var to: float = float(tpl[i][1])
		var jitter: float = (rng.next() - 0.5) * 0.03
		if not last:
			to = minf(0.98, maxf(prev + 0.02, to + jitter))
		else:
			to = 1.0
		var names: Array = []
		for t in tpl[i][0]:
			names.append_array(candidates(t, places, opts.get("home")))
		if names.is_empty():
			continue
		var name: String
		if stops.is_empty() and spawn != null:
			var best := INF
			name = names[0]
			for nm in names:
				var d: float = sqrt((places[nm]["x"] - spawn["x"]) * (places[nm]["x"] - spawn["x"]) + (places[nm]["y"] - spawn["y"]) * (places[nm]["y"] - spawn["y"]))
				if d < best:
					best = d
					name = nm
		else:
			name = names[absi(slot) % names.size()]
		var act: String = tpl[i][2] if tpl[i].size() > 2 and tpl[i][2] != null and tpl[i][2] != "" else "wait"
		stops.append({"place": name, "x": places[name]["x"], "y": places[name]["y"], "at": prev if not stops.is_empty() else 0.0, "until": to, "act": act})
		prev = to
	if stops.is_empty():
		return null
	stops[0]["at"] = 0.0
	stops[stops.size() - 1]["until"] = 1.0
	return stops


## Index of the stop active at night fraction f (clamped to 0..1).
static func stop_at(stops: Array, f: float) -> int:
	if stops.is_empty():
		return -1
	if not is_finite(f):
		return 0
	var ff: float = clampf(f, 0.0, 1.0)
	for i in stops.size():
		if ff < float(stops[i]["until"]):
			return i
	return stops.size() - 1


## Per-person schedule state, or null when the role has no stops.
static func make(role: Variant, places: Variant, spawn: Variant, rng: Rng, opts: Dictionary = {}) -> Variant:
	var stops: Variant = build(role, places, spawn, rng, opts)
	if stops == null:
		return null
	return {"role": role, "home": opts.get("home") if opts.get("home") != null and str(opts.get("home")) != "" else null, "stops": stops, "si": -1, "target": -1, "en": false, "retarget": false}


## Drop interior waypoints on a straight run (route cells -> fewer, longer legs). Points are {x, y, ...}.
static func simplify(route: Array) -> Array:
	if route.size() < 3:
		return route
	var out: Array = [route[0]]
	for i in range(1, route.size() - 1):
		var a: Dictionary = out[out.size() - 1]
		var b: Dictionary = route[i]
		var c: Dictionary = route[i + 1]
		if (b["x"] - a["x"]) * (c["y"] - b["y"]) - (b["y"] - a["y"]) * (c["x"] - b["x"]) != 0.0:
			out.append(b)
	out.append(route[route.size() - 1])
	return out


## Seconds until the stop at index si ends (debug readout).
static func eta(stops: Array, si: int, f: float, night_sec: float) -> float:
	if si < 0 or si >= stops.size() or not is_finite(f) or not is_finite(night_sec):
		return 0.0
	return maxf(0.0, (float(stops[si]["until"]) - f) * night_sec)


static func chat_entry(role_a: String, role_b: String, same_home: bool) -> Dictionary:
	if same_home:
		return CHAT["family"]
	var key: String = (role_a + "|" + role_b) if role_a < role_b else (role_b + "|" + role_a)
	return CHAT["pairs"][key] if CHAT["pairs"].has(key) else CHAT["default"]


## Pick "chat" | "hello" | "ignore" with r1 in [0,1); duration via r2: {kind, mood, sec}.
static func chat_roll(role_a: String, role_b: String, same_home: bool, r1: float, r2: float) -> Dictionary:
	var e := chat_entry(role_a, role_b, same_home)
	var acc := 0.0
	var k := 2
	for i in 3:
		acc += float(e["w"][i])
		if r1 < acc:
			k = i
			break
	var kind: String = CHAT_KINDS[k]
	var rg: Array = CHAT["chatSec"] if kind == "chat" else CHAT["helloSec"]
	return {"kind": kind, "mood": e["mood"], "sec": 0.0 if kind == "ignore" else float(rg[0]) + (float(rg[1]) - float(rg[0])) * r2}
