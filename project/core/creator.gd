class_name Creator
extends RefCounted
## Ports tools/character-creator-core.js: the character creator's data layer. The look field table, validation and clamping
## (so figures never see a bad look), archetype presets through Forge, randomizing, pose-to-echo set-up, view-state clamping,
## named-character list and JSON export / import. Pure logic, no UI (ui/creator.gd).

const FORMAT_ONE := "vcs-character"
const FORMAT_MANY := "vcs-characters"
const MAX_SAVED := 64
const MAX_TEXT := 262144
const MAX_NAME := 32
const STORE_PATH := "user://creator.json"
const BAD_KEYS := ["__proto__", "constructor", "prototype"]

const DEFAULTS := {
	"height": 1.0, "build": 1.0, "stride": 1.0, "acc": "none", "body": "bean", "head": "round", "hat": "none", "hair": "none", "beard": false,
	"nose": 1.0, "coat": false, "prop": "none", "v": 1, "archetype": "patron", "outfit": "plain", "roleHat": "none", "extra": "none",
	"stoop": 0.0, "shoulder": 1.0, "hem": 0.0, "skin": 0.5,
}
const NUM_KEYS := ["height", "build", "stride", "nose", "stoop", "shoulder", "hem", "skin"]
const BOOL_KEYS := ["beard", "coat"]
const ENUM_KEYS := ["acc", "body", "head", "hat", "hair", "prop", "outfit", "roleHat", "extra"]

## UI groups. "scarf" is a creator-only toggle: the look stores it as acc "scarf" (see derive_acc).
const GROUPS := [
	["Body", ["body", "height", "build", "shoulder", "stoop", "stride"]],
	["Head and face", ["head", "nose", "hair", "beard", "skin"]],
	["Clothes", ["outfit", "hem", "coat", "scarf"]],
	["Headwear", ["hat", "roleHat"]],
	["Carried", ["prop", "extra"]],
]
const LABELS := {
	"body": "Body", "height": "Height", "build": "Build", "shoulder": "Shoulders", "stoop": "Stoop", "stride": "Stride",
	"head": "Head", "nose": "Nose", "hair": "Hair", "beard": "Beard", "skin": "Flush (skin)", "outfit": "Outfit", "hem": "Hem length",
	"coat": "Coat", "scarf": "Scarf", "hat": "Hat", "roleHat": "Role hat", "prop": "Prop", "extra": "Role item",
}
const HINTS := {
	"height": "At or below 0.66 reads as a child", "stoop": "Shows at Effects 1 and 2", "skin": "How strongly the pulse flushes the skin (Effects 2, circulation on)",
	"hem": "0 waist .. 1 ankle (robe, apron, smock, cloak)", "stride": "Walk and flee step size", "roleHat": "Replaces the hat",
	"extra": "Volumetric figures only (Effects 1 and 2)",
}
const POSES := [
	["idle", "Idle"], ["wary", "Wary"], ["chat", "Chat"], ["walk", "Walk"], ["flee", "Flee"], ["startle", "Startle"], ["cower", "Cower"],
	["dazed", "Dazed"], ["seated", "Seated"], ["fed", "Fed (slumped)"], ["held", "Held (struggle)"],
]
const VMODE := {"flee": "flee", "cower": "cower", "fed": "fed", "startle": "startle"}
const VIEW_DEFAULTS := {
	"pose": "idle", "fx": 2, "quality": 3, "zoom": 3, "dist": 2.2, "yaw": 0.0, "spin": false, "play": true, "speed": 1.0, "rim": true,
	"vessels": false, "skel": false, "graph": false, "parts": false, "reduced": false, "struggle": 0.4, "restrain": false, "gameScale": 2,
}


static func _is_num(n: Variant) -> bool:
	return (n is float or n is int) and is_finite(float(n))


static func _round3(n: float) -> float:
	return floorf(n * 1000.0 + 0.5) / 1000.0


static func _id_ok(s: Variant) -> bool:
	return s is String and Forge._id_ok(s)


static func _truthy(v: Variant) -> bool:
	return (v is bool and v) or (v is String and v == "true")


static func _own(o: Variant, k: String) -> Variant:
	if o is Dictionary and o.has(k) and not BAD_KEYS.has(k):
		return o[k]
	return null


## Field table for the UI: [{key, label, group, hint, type "num"|"bool"|"enum", min, max, step, values}].
static func fields() -> Array:
	var e: Dictionary = Forge.enums()
	var r: Dictionary = Forge.ranges()
	var out: Array = []
	for g in GROUPS:
		for k in g[1]:
			var f := {"key": k, "label": LABELS.get(k, k), "group": g[0], "hint": HINTS.get(k, "")}
			if NUM_KEYS.has(k):
				f["type"] = "num"
				f["min"] = float(r[k][0])
				f["max"] = float(r[k][1])
				f["step"] = 0.01
			elif BOOL_KEYS.has(k) or k == "scarf":
				f["type"] = "bool"
			else:
				f["type"] = "enum"
				f["values"] = (e.get(k, []) as Array).duplicate()
			out.append(f)
	return out


## acc is the legacy single accessory; the renderer draws look.hat and look.prop directly and a scarf from acc.
static func derive_acc(look: Dictionary, scarf: bool) -> String:
	if scarf:
		return "scarf"
	if look.get("hat") is String and look["hat"] != "none" and look["hat"] != "":
		return look["hat"]
	if look.get("prop") is String and look["prop"] != "none" and look["prop"] != "":
		return look["prop"]
	return "none"


## Clamp any input into a complete, render-safe look. Returns {look, fixed: [keys changed]}.
static func sanitize(input: Variant, base: Variant = null) -> Dictionary:
	var e: Dictionary = Forge.enums()
	var r: Dictionary = Forge.ranges()
	var b: Dictionary = base if base is Dictionary else DEFAULTS
	var src: Dictionary = input if input is Dictionary else {}
	var out := {}
	var fixed: Array = []
	for k in DEFAULTS:
		var raw: Variant = _own(src, k)
		var fb: Variant = _own(b, k) if _own(b, k) != null else DEFAULTS[k]
		var v: Variant
		if k == "v":
			v = 1
		elif k == "archetype":
			v = raw if _id_ok(raw) else (fb if _id_ok(fb) else "patron")
		elif NUM_KEYS.has(k):
			var rg: Array = r.get(k, [0.0, 1.0])
			if _is_num(raw):
				v = _round3(clampf(float(raw), float(rg[0]), float(rg[1])))
			elif raw is String and (raw as String).strip_edges() != "" and (raw as String).is_valid_float():
				v = _round3(clampf(float(raw), float(rg[0]), float(rg[1])))
			else:
				v = _round3(clampf(float(fb), float(rg[0]), float(rg[1]))) if _is_num(fb) else DEFAULTS[k]
		elif BOOL_KEYS.has(k):
			v = raw if raw is bool else (fb == true)
		elif ENUM_KEYS.has(k):
			var lst: Array = e.get(k, [])
			if raw is String and lst.has(raw):
				v = raw
			else:
				v = fb if lst.has(fb) else DEFAULTS[k]
		else:
			v = DEFAULTS[k]
		if raw != null and k != "v" and not _same(raw, v):
			fixed.append(k)
		out[k] = v
	return {"look": out, "fixed": fixed}


static func _same(a: Variant, b: Variant) -> bool:
	if _is_num(a) and _is_num(b):
		return float(a) == float(b)
	return typeof(a) == typeof(b) and a == b


## Apply one field edit (including the "scarf" toggle) to a look; returns a new sanitized look.
static func set_field(look: Variant, key: String, value: Variant) -> Dictionary:
	var cur: Dictionary = sanitize(look)["look"]
	if key == "scarf":
		cur["acc"] = derive_acc(cur, _truthy(value))
		return cur
	if not DEFAULTS.has(key) or key == "v":
		return cur
	var patch := {}
	if NUM_KEYS.has(key):
		patch[key] = float(value) if _is_num(value) or (value is String and (value as String).is_valid_float()) else NAN
	elif BOOL_KEYS.has(key):
		patch[key] = _truthy(value)
	else:
		patch[key] = str(value)
	var merged := cur.duplicate()
	merged.merge(patch, true)
	var nxt: Dictionary = sanitize(merged, cur)["look"]
	if key == "hat" or key == "prop":
		nxt["acc"] = derive_acc(nxt, cur["acc"] == "scarf")
	return nxt


## Value of a field for the UI (the "scarf" toggle reads acc).
static func get_field(look: Dictionary, key: String) -> Variant:
	if key == "scarf":
		return look.get("acc") == "scarf"
	return look.get(key)


## True when the game's Forge would hide this hair under the hat (tophat, nightcap, hood).
static func hair_hidden(look: Dictionary) -> bool:
	return (look.get("hat") == "nightcap" or look.get("hat") == "hood" or look.get("hat") == "tophat") and look.get("roleHat") == "none"


## [{id, label}] of the Forge archetypes.
static func archetypes() -> Array:
	var out: Array = []
	for id in Forge.list_ids():
		var a: Variant = Forge.archetype(id)
		out.append({"id": id, "label": str(a["label"]) if a is Dictionary and a.get("label") is String else str(id)})
	return out


static func clean_seed(seed_v: Variant) -> int:
	var n: float = floorf(float(seed_v)) if _is_num(seed_v) else 0.0
	return int(clampf(n, 0.0, 65535.0))


## The look the game's Forge gives archetype `id` at `seed` (same context as the dev panel's Forge editor).
static func preset(id: Variant, seed_v: Variant) -> Dictionary:
	var s := clean_seed(seed_v)
	var r := Forge.generate({"archetype": id if id is String else "patron", "seed": s}, {"stateSeed": 0, "index": 0, "accOffset": 0})
	var person: Variant = r.get("person")
	return sanitize(person["look"] if person is Dictionary else {})["look"]


## Randomize a look. mode "wild": every unlocked field uniform over its range or list. mode "archetype": a fresh Forge preset
## of look.archetype at a random seed. locks = keys kept from base. rng: an Rng (default a fresh random one). Returns {look, seed}.
static func randomize(base: Variant, mode: String = "wild", locks: Array = [], rng: Rng = null) -> Dictionary:
	var rnd: Rng = rng if rng != null else Rng.new(float(randi()))
	var b: Dictionary = sanitize(base)["look"]
	var seed_v: int = int(floorf(rnd.next() * 65536.0)) % 65536
	var nxt: Dictionary
	if mode == "archetype":
		nxt = preset(b["archetype"], seed_v)
	else:
		nxt = b.duplicate()
		var e: Dictionary = Forge.enums()
		var r: Dictionary = Forge.ranges()
		for k in NUM_KEYS:
			nxt[k] = float(r[k][0]) + rnd.next() * (float(r[k][1]) - float(r[k][0]))
		for k in ["body", "head", "hat", "hair", "prop", "outfit", "extra"]:
			var l: Array = e.get(k, [])
			var idx: int = int(floorf(rnd.next() * l.size()))
			nxt[k] = l[idx] if idx < l.size() else DEFAULTS[k]
		# Role hats and children are rarer, so a wild roll still looks like a villager most of the time.
		var rh: Array = e.get("roleHat", ["none"])
		if rnd.next() < 0.2:
			var ri: int = 1 + int(floorf(rnd.next() * (rh.size() - 1)))
			nxt["roleHat"] = rh[ri] if ri < rh.size() else "none"
		else:
			nxt["roleHat"] = "none"
		if rnd.next() < 0.8:
			nxt["height"] = 0.82 + rnd.next() * 0.38
		nxt["hem"] = (0.85 + rnd.next() * 0.15) if nxt["outfit"] == "robe" else nxt["hem"]
		nxt["beard"] = rnd.next() < 0.3
		nxt["coat"] = rnd.next() < 0.4
		nxt["acc"] = derive_acc(nxt, rnd.next() < 0.2)
	for k in locks:
		if k == "scarf":
			nxt["acc"] = derive_acc(nxt, b["acc"] == "scarf")
		elif DEFAULTS.has(k):
			nxt[k] = b[k]
	if locks.has("hat") or locks.has("prop"):
		nxt["acc"] = derive_acc(nxt, nxt["acc"] == "scarf")
	return {"look": sanitize(nxt)["look"], "seed": seed_v}


## Echo for EchoLayer.draw_solo: one villager at depth dist, lateral lat, facing yaw (0 = facing the camera), in pose `id`,
## at clock t. o: {t, reduced, yaw, dist, lat, personId, struggle, restrain}. Returns {echo, lock (or null), vmode}.
static func pose_echo(id: String, look: Dictionary, o: Dictionary = {}) -> Dictionary:
	var pid: String = id
	var known := false
	for p in POSES:
		if p[0] == id:
			known = true
	if not known:
		pid = "idle"
	var t: float = float(o["t"]) if _is_num(o.get("t")) else 0.0
	var anim: bool = not bool(o.get("reduced", false))
	var yaw: float = float(o["yaw"]) if _is_num(o.get("yaw")) else 0.0
	var e := {
		"x": float(o["dist"]) if _is_num(o.get("dist")) else 2.2, "y": float(o["lat"]) if _is_num(o.get("lat")) else 0.0,
		"angle": PI + yaw, "lookAngle": 0.0, "phase": 0.0, "phaseRate": 0.0, "personId": int(o["personId"]) if _is_num(o.get("personId")) else 4,
		"t": 0.0, "strength": 1.0, "zMin": 0.0, "zMax": 2.0, "look": look, "fade": 3.0, "mode": "path", "sit": false, "wary": false,
		"chat": false, "modeAge": 9.0,
	}
	var lock: Variant = null
	if pid == "wary":
		e["wary"] = true
	elif pid == "chat":
		e["chat"] = true
	elif pid == "walk":
		e["phase"] = 0.3 + (t * 6.0 if anim else 0.0)
	elif pid == "flee":
		e["mode"] = "flee"
		e["phase"] = 0.3 + (t * 8.0 if anim else 0.0)
	elif pid == "startle":
		e["mode"] = "startle"
		e["modeAge"] = fposmod(t * 0.6, 1.2) if anim else 2.0
	elif pid == "cower":
		e["mode"] = "cower"
	elif pid == "dazed":
		e["mode"] = "dazed"
	elif pid == "seated":
		e["sit"] = true
	elif pid == "fed":
		e["mode"] = "fed"
	elif pid == "held":
		var k: float = clampf(float(o["struggle"]), 0.0, 1.0) if _is_num(o.get("struggle")) else 0.4
		var span: float = 3.0 if k < 0.2 else 6.0
		lock = {"k": k, "age": (0.3 if k < 0.2 else 5.0) + (fposmod(t, span) if anim else 0.0), "rs": 1.0 if o.get("restrain", false) else 0.0, "sp": 9.0}
		e["x"] = 1.25
	return {"echo": e, "lock": lock, "vmode": VMODE.get(pid, "calm")}


## Clamp a view state (pose, effects, quality, zoom, distance, yaw in -pi..pi, speed, toggles).
static func sanitize_view(v: Variant) -> Dictionary:
	var s: Dictionary = v if v is Dictionary else {}
	var out := {}
	var pose_ok := false
	for p in POSES:
		if p[0] == _own(s, "pose"):
			pose_ok = true
	out["pose"] = _own(s, "pose") if pose_ok else "idle"
	for spec in [["fx", 0.0, 2.0, true], ["quality", 1.0, 3.0, true], ["zoom", 1.0, 4.0, true], ["dist", 1.2, 5.0, false], ["speed", 0.0, 2.0, false], ["struggle", 0.0, 1.0, false], ["gameScale", 1.0, 4.0, true]]:
		var raw: Variant = _own(s, spec[0])
		var n: float = float(raw) if _is_num(raw) else float(VIEW_DEFAULTS[spec[0]])
		n = clampf(n, spec[1], spec[2])
		out[spec[0]] = int(floorf(n + 0.5)) if spec[3] else n
	var yaw: float = float(_own(s, "yaw")) if _is_num(_own(s, "yaw")) else 0.0
	yaw = fposmod(fposmod(yaw + PI, TAU) + TAU, TAU) - PI
	out["yaw"] = yaw
	for k in ["spin", "play", "rim", "vessels", "skel", "graph", "parts", "reduced", "restrain"]:
		var rv: Variant = _own(s, k)
		out[k] = rv if rv is bool else VIEW_DEFAULTS[k]
	return out


# ---------------------------------------------------------------- characters, storage, JSON

static func clean_name(name: Variant) -> String:
	if not (name is String):
		return "Unnamed"
	var s := ""
	for i in (name as String).length():
		var c: int = (name as String).unicode_at(i)
		if c < 32 or c == 127 or c == 60 or c == 62:
			continue
		s += char(c)
	var parts := s.split(" ", false)
	s = " ".join(PackedStringArray(parts)).strip_edges()
	s = s.substr(0, MAX_NAME)
	return s if s != "" else "Unnamed"


## A saved character: {name, archetype, seed, look, saved (ms)}.
static func character(name: Variant, look: Variant, meta: Variant = null) -> Dictionary:
	var m: Dictionary = meta if meta is Dictionary else {}
	var l: Dictionary = sanitize(look)["look"]
	var arch: String = m["archetype"] if _id_ok(m.get("archetype")) else l["archetype"]
	var saved: int = int(floorf(float(m["saved"]))) if _is_num(m.get("saved")) and float(m["saved"]) > 0.0 else int(Time.get_unix_time_from_system() * 1000.0)
	return {"name": clean_name(name), "archetype": arch, "seed": clean_seed(m.get("seed")), "look": l, "saved": saved}


## Accepts a saved-character object, or a bare look; returns a sanitized character or null.
static func from_any(o: Variant, i: int = 0) -> Variant:
	if not (o is Dictionary):
		return null
	if _own(o, "look") is Dictionary:
		return character(_own(o, "name"), _own(o, "look"), {"archetype": _own(o, "archetype"), "seed": _own(o, "seed"), "saved": _own(o, "saved")})
	for k in o:
		if DEFAULTS.has(k) and k != "v":
			return character("Imported %d" % (i + 1), o, {})
	return null


static func export_json(chars: Variant) -> String:
	var list: Array = chars if chars is Array else [chars]
	var clean: Array = []
	for i in list.size():
		var c: Variant = from_any(list[i], i)
		if c != null:
			clean.append(c)
	if not (chars is Array) and clean.size() == 1:
		var one: Dictionary = {"format": FORMAT_ONE, "v": 1}
		one.merge(clean[0])
		return JSON.stringify(one, "  ")
	return JSON.stringify({"format": FORMAT_MANY, "v": 1, "list": clean.slice(0, MAX_SAVED)}, "  ")


## Parse exported JSON: one character, a bundle, a plain array, or a bare look. {ok, code, list, skipped}.
## Codes: OK, E_CC_TYPE, E_CC_PARSE, E_CC_LIMIT, E_CC_EMPTY.
static func import_json(text: Variant) -> Dictionary:
	if not (text is String):
		return {"ok": false, "code": "E_CC_TYPE", "list": [], "skipped": 0}
	if (text as String).length() > MAX_TEXT:
		return {"ok": false, "code": "E_CC_LIMIT", "list": [], "skipped": 0}
	var jp := JSON.new()
	if jp.parse(text) != OK:
		return {"ok": false, "code": "E_CC_PARSE", "list": [], "skipped": 0}
	var data: Variant = jp.data
	if data == null:
		return {"ok": false, "code": "E_CC_PARSE", "list": [], "skipped": 0}
	var items: Array
	if data is Array:
		items = data
	elif data is Dictionary and _own(data, "list") is Array:
		items = _own(data, "list")
	elif data is Dictionary:
		items = [data]
	else:
		return {"ok": false, "code": "E_CC_TYPE", "list": [], "skipped": 0}
	if items.size() > MAX_SAVED * 4:
		return {"ok": false, "code": "E_CC_LIMIT", "list": [], "skipped": 0}
	var out: Array = []
	var skipped := 0
	for i in items.size():
		var c: Variant = from_any(items[i], i)
		if c != null and out.size() < MAX_SAVED:
			out.append(c)
		else:
			skipped += 1
	if out.is_empty():
		return {"ok": false, "code": "E_CC_EMPTY", "list": [], "skipped": skipped}
	return {"ok": true, "code": "OK", "list": out, "skipped": skipped}


## Insert or replace (same name, case-insensitive) into a list; newest first, at most MAX_SAVED. Returns a new list.
static func upsert(list: Variant, c: Variant) -> Array:
	var src: Array = list if list is Array else []
	var ch: Variant = from_any(c, 0)
	if ch == null:
		return src.duplicate()
	var key: String = (ch["name"] as String).to_lower()
	var out: Array = [ch]
	for x in src:
		if not (x is Dictionary and x.get("name") is String and (x["name"] as String).to_lower() == key):
			out.append(x)
	return out.slice(0, MAX_SAVED)


static func remove(list: Variant, name: Variant) -> Array:
	var key: String = (name as String).to_lower() if name is String else ""
	var out: Array = []
	for x in (list if list is Array else []):
		if not (x is Dictionary and x.get("name") is String and (x["name"] as String).to_lower() == key):
			out.append(x)
	return out


static func find(list: Variant, name: Variant) -> Variant:
	var key: String = (name as String).to_lower() if name is String else ""
	for x in (list if list is Array else []):
		if x is Dictionary and x.get("name") is String and (x["name"] as String).to_lower() == key:
			return x
	return null


## A name not yet in the list: base, base 2, base 3, ...
static func free_name(list: Variant, base: Variant) -> String:
	var b := clean_name(base)
	if find(list, b) == null:
		return b
	for i in range(2, 1000):
		var n := clean_name(b.substr(0, MAX_NAME - 5) + " " + str(i))
		if find(list, n) == null:
			return n
	return b


## Load the saved characters from user://creator.json (empty list when missing or damaged).
static func load_store(path: String = STORE_PATH) -> Array:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return []
	var r := import_json(f.get_as_text())
	return r["list"] if r["ok"] else []


static func save_store(list: Array, path: String = STORE_PATH) -> bool:
	var clean: Array = []
	for i in list.size():
		var c: Variant = from_any(list[i], i)
		if c != null:
			clean.append(c)
	var text := JSON.stringify({"format": FORMAT_MANY, "v": 1, "list": clean.slice(0, MAX_SAVED)})
	if text.length() > MAX_TEXT:
		return false
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(text)
	return true


## Forge spawn spec for this character: {archetype, seed, overrides}.
static func to_spec(c: Variant) -> Variant:
	var ch: Variant = from_any(c, 0)
	if ch == null:
		return null
	var ov := {}
	for k in DEFAULTS:
		if k != "v" and k != "archetype":
			ov[k] = ch["look"][k]
	var known: String = ch["archetype"] if Forge.archetype(ch["archetype"]) != null else "patron"
	return {"archetype": known, "seed": ch["seed"], "overrides": ov}
