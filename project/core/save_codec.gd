class_name SaveCodec
extends RefCounted
## Ports js/save.js: the save envelope {app, kind, v, game, sum, data} with an FNV-1a checksum, safe parsing, run
## sanitising/migration, export/import text, the atomic write (tmp + verify + .bak) store and the two-instance lock.
##
## Checksums are computed over the *raw compact text* of `data` (whitespace outside strings removed), so a save written by
## the JS game verifies here byte for byte, and ours verifies in JS (JsJson prints numbers the way JS does). Godot's JSON
## parser is not correctly rounded for doubles, so parsed values are used for the game state but never re-printed for a
## checksum of someone else's text.

const KEY_RUN := "vcs.run"
const KEY_META := "vcs.meta"
const TAB_KEY := "vcs.tab"
const TAB_STALE_MS := 12000
const MAX_BYTES := 65536
const MAX_IMPORT := 131072
const RUN_SCHEMA := 4
const MAX_DEPTH := 12
const BAD_KEYS := ["__proto__", "constructor", "prototype"]
const ENV_KEYS := ["app", "kind", "v", "game", "sum", "data"]
const IMPORT_KEYS := ["app", "kind", "v", "game", "meta", "run"]
const RUN_KEYS := ["v", "map", "player", "doors", "people", "night", "run", "rocks", "forge"]
const RUN_RUN_KEYS := ["seed", "boons", "closedSafe", "pendingBoons"]
const KEY_ROGUE := "vcs.rogue"
const KEY_TREK := "vcs.trek"
const ROGUE_SCHEMA := 1
const TREK_SCHEMA := 1
const ROGUE_KEYS := ["v", "soil", "unlocks", "stats", "reached", "legacyImported"]
## Keys a rogue save may carry on top of ROGUE_KEYS (older saves lack them; a present value must be a bool).
const ROGUE_OPTIONAL_KEYS := ["tutorialDone"]
const ROGUE_STAT_KEYS := ["treks", "bestMiles", "bestStage", "deaths", "fedHumans", "fedCritters", "soilEarned"]
const ROGUE_DEATH_KEYS := ["sun", "withered", "staked", "holy"]
const TREK_KEYS := ["v", "seed", "stage", "leg", "miles", "progress", "heat", "night", "hunger", "unlocksUsed", "deathsAvoided"]
const HUNGER_KEYS := ["v", "fear", "over", "giftsTonight", "gifts", "essenceBonus", "nextBlood"]

## Shown in the `game` field of an envelope (js Log.VERSION).
static var game_version: String = "godot"


static func _is_num(x: Variant) -> bool:
	return (x is float or x is int) and is_finite(float(x))


static func _is_int(x: Variant) -> bool:
	return (x is int) or (x is float and is_finite(x) and floor(x) == x)


static func _exact_keys(o: Dictionary, keys: Array) -> bool:
	if o.size() != keys.size():
		return false
	for k in keys:
		if not o.has(k):
			return false
	return true


## FNV-1a 32-bit over UTF-16 code units, 8 lowercase hex chars (js checksum).
static func checksum(text: String) -> String:
	var h: int = 0x811c9dc5
	for i in text.length():
		var cp: int = text.unicode_at(i)
		if cp > 0xFFFF:
			var v: int = cp - 0x10000
			var units := [0xD800 + (v >> 10), 0xDC00 + (v & 0x3FF)]
			for u in units:
				h = ((h ^ u) * 16777619) & 0xFFFFFFFF
		else:
			h = ((h ^ cp) * 16777619) & 0xFFFFFFFF
	return "%08x" % h


# ---------------------------------------------------------------- raw text helpers

## Remove insignificant whitespace from JSON text (outside string literals), like JSON.stringify output.
static func compact(raw: String) -> String:
	var out := PackedStringArray()
	var in_str := false
	var esc := false
	var start := 0
	for i in raw.length():
		var c: String = raw[i]
		if in_str:
			if esc:
				esc = false
			elif c == "\\":
				esc = true
			elif c == "\"":
				in_str = false
			continue
		if c == "\"":
			in_str = true
		elif c == " " or c == "\n" or c == "\t" or c == "\r":
			if i > start:
				out.append(raw.substr(start, i - start))
			start = i + 1
	if raw.length() > start:
		out.append(raw.substr(start))
	return "".join(out)


## Split a JSON object's text into key -> raw value text (compacted). Empty Dictionary when not an object.
static func split_object(raw: String) -> Dictionary:
	var res := {}
	var n: int = raw.length()
	var i := 0
	while i < n and raw[i] in [" ", "\n", "\t", "\r"]:
		i += 1
	if i >= n or raw[i] != "{":
		return res
	i += 1
	while true:
		while i < n and raw[i] in [" ", "\n", "\t", "\r", ","]:
			i += 1
		if i >= n or raw[i] == "}":
			break
		if raw[i] != "\"":
			return {}
		var ks := i
		i += 1
		while i < n and raw[i] != "\"":
			i += 2 if raw[i] == "\\" else 1
		var key_text: String = raw.substr(ks, i - ks + 1)
		var key: Variant = JSON.parse_string(key_text)
		i += 1
		while i < n and raw[i] in [" ", "\n", "\t", "\r", ":"]:
			i += 1
		var vs := i
		var depth := 0
		var in_str := false
		while i < n:
			var c: String = raw[i]
			if in_str:
				if c == "\\":
					i += 1
				elif c == "\"":
					in_str = false
			else:
				if c == "\"":
					in_str = true
				elif c == "{" or c == "[":
					depth += 1
				elif c == "}" or c == "]":
					if depth == 0:
						break
					depth -= 1
				elif c == "," and depth == 0:
					break
			i += 1
		res[str(key)] = compact(raw.substr(vs, i - vs))
	return res


# ---------------------------------------------------------------- parse

static func _depth_ok(v: Variant) -> bool:
	var stack: Array = [[v, 1]]
	var guard := 0
	while not stack.is_empty():
		var it: Array = stack.pop_back()
		var x: Variant = it[0]
		if x is Dictionary or x is Array:
			if it[1] > MAX_DEPTH:
				return false
			guard += 1
			if guard > 200000:
				return false
			if x is Dictionary:
				for k in x.keys():
					stack.append([x[k], it[1] + 1])
			else:
				for item in x:
					stack.append([item, it[1] + 1])
	return true


static func _has_bad_key(v: Variant) -> bool:
	if v is Dictionary:
		for k in v.keys():
			if BAD_KEYS.has(str(k)) or _has_bad_key(v[k]):
				return true
	elif v is Array:
		for item in v:
			if _has_bad_key(item):
				return true
	return false


## Parse JSON text safely: {ok, value, code}.
static func safe_parse(text: Variant) -> Dictionary:
	if not (text is String):
		return {"ok": false, "value": null, "code": "E_SAVE_PARSE"}
	var j := JSON.new()
	if j.parse(text) != OK:
		return {"ok": false, "value": null, "code": "E_SAVE_PARSE"}
	var value: Variant = j.data
	if _has_bad_key(value):
		return {"ok": false, "value": null, "code": "E_SAVE_BAD_KEY"}
	if not _depth_ok(value):
		return {"ok": false, "value": null, "code": "E_SAVE_SCHEMA"}
	return {"ok": true, "value": value, "code": ""}


# ---------------------------------------------------------------- envelope

## The envelope Dictionary for data (js wrap; renamed because wrap() is a GDScript built-in).
static func envelope(kind: String, v: int, data: Variant) -> Dictionary:
	return {"app": "vcs", "kind": kind, "v": v, "game": game_version, "sum": checksum(JsJson.stringify(data)), "data": data}


## Envelope text: compact JSON.
static func wrap_text(kind: String, v: int, data: Variant) -> String:
	return JsJson.stringify(envelope(kind, v, data))


## Validate a parsed envelope against the raw compact text of its data (js unwrap).
static func unwrap(env: Variant, kind: String, data_raw: String) -> Dictionary:
	if not (env is Dictionary) or not _exact_keys(env, ENV_KEYS):
		return {"ok": false, "v": 0, "data": null, "code": "E_SAVE_SCHEMA"}
	if env["app"] != "vcs" or env["kind"] != kind or not _is_int(env["v"]) or float(env["v"]) < 0.0 or not (env["sum"] is String):
		return {"ok": false, "v": 0, "data": null, "code": "E_SAVE_SCHEMA"}
	if checksum(data_raw) != env["sum"]:
		return {"ok": false, "v": 0, "data": null, "code": "E_SAVE_CHECKSUM"}
	return {"ok": true, "v": int(env["v"]), "data": env["data"], "code": ""}


## Parse and validate the text of a stored/imported envelope: {ok, env, v, data, raw_env, code}.
static func check(text: Variant, kind: String, max_bytes: int = MAX_BYTES) -> Dictionary:
	if text == null:
		return {"ok": false, "code": "E_SAVE_NONE"}
	if text.length() > max_bytes:
		return {"ok": false, "code": "E_SAVE_TOO_BIG"}
	var p := safe_parse(text)
	if not p["ok"]:
		return {"ok": false, "code": p["code"]}
	var parts := split_object(text)
	var raw: String = parts.get("data", "")
	var u := unwrap(p["value"], kind, raw)
	if not u["ok"]:
		return {"ok": false, "code": u["code"]}
	return {"ok": true, "env": p["value"], "v": u["v"], "data": u["data"], "raw_env": compact(text), "code": ""}


# ---------------------------------------------------------------- storage

class MemoryStorage:
	extends RefCounted
	var items := {}

	func get_item(k: String) -> Variant:
		return items.get(k)

	func set_item(k: String, v: String) -> void:
		items[k] = v

	func remove_item(k: String) -> void:
		items.erase(k)


class FileStorage:
	extends RefCounted
	var dir: String = "user://"

	func _init(directory: String = "user://") -> void:
		dir = directory
		DirAccess.make_dir_recursive_absolute(directory)

	func _path(k: String) -> String:
		return dir.path_join(k.replace(".", "_") + ".json")

	func get_item(k: String) -> Variant:
		var f := FileAccess.open(_path(k), FileAccess.READ)
		return f.get_as_text() if f != null else null

	func set_item(k: String, v: String) -> void:
		var f := FileAccess.open(_path(k), FileAccess.WRITE)
		if f == null:
			push_error("save: cannot write %s" % _path(k))
			return
		f.store_string(v)

	func remove_item(k: String) -> void:
		if FileAccess.file_exists(_path(k)):
			DirAccess.remove_absolute(_path(k))


class Store:
	extends RefCounted
	## js Save.create: a store over a storage object with atomic writes (tmp, verify, rotate to .bak) and a backup
	## fallback on read.
	var persistent: bool = true
	var _st: Object
	var _max_bytes: int = MAX_BYTES

	func _init(storage: Object, max_bytes: int = MAX_BYTES) -> void:
		_max_bytes = max_bytes
		_st = storage
		if not _probe(storage):
			_st = MemoryStorage.new()
			persistent = false

	static func _probe(storage: Object) -> bool:
		if storage == null or not storage.has_method("get_item") or not storage.has_method("set_item") or not storage.has_method("remove_item"):
			return false
		storage.set_item("vcs.probe", "1")
		var ok: bool = storage.get_item("vcs.probe") == "1"
		storage.remove_item("vcs.probe")
		return ok

	static func key_of(kind: String) -> String:
		match kind:
			"run":
				return KEY_RUN
			"meta":
				return KEY_META
			"rogue":
				return KEY_ROGUE
			"trek":
				return KEY_TREK
		return ""

	func _fetch(k: String) -> Variant:
		var v: Variant = _st.get_item(k)
		return v if v is String else null

	func write(kind: String, v: int, data: Variant) -> Dictionary:
		var key := key_of(kind)
		if key == "":
			return {"ok": false, "code": "E_SAVE_SCHEMA"}
		var text := SaveCodec.wrap_text(kind, v, data)
		if text.length() > _max_bytes:
			return {"ok": false, "code": "E_SAVE_TOO_BIG"}
		var tmp := key + ".tmp"
		_st.set_item(tmp, text)
		if _st.get_item(tmp) != text:
			_st.remove_item(tmp)
			return {"ok": false, "code": "E_SAVE_VERIFY"}
		var cur: Variant = _fetch(key)
		if cur != null and SaveCodec.check(cur, kind, _max_bytes)["ok"]:
			_st.set_item(key + ".bak", cur)
		_st.set_item(key, text)
		_st.remove_item(tmp)
		return {"ok": true, "code": ""}

	func _read_full(kind: String) -> Dictionary:
		var key := key_of(kind)
		if key == "":
			return {"ok": false, "v": 0, "data": null, "raw_env": "", "source": "none", "code": "E_SAVE_SCHEMA"}
		var m := SaveCodec.check(_fetch(key), kind, _max_bytes)
		if m["ok"]:
			return {"ok": true, "v": m["v"], "data": m["data"], "raw_env": m["raw_env"], "source": "main", "code": ""}
		var bak_text: Variant = _fetch(key + ".bak")
		var b := SaveCodec.check(bak_text, kind, _max_bytes)
		if b["ok"]:
			_st.set_item(key, bak_text)
			return {"ok": true, "v": b["v"], "data": b["data"], "raw_env": b["raw_env"], "source": "bak", "code": m["code"]}
		return {"ok": false, "v": 0, "data": null, "raw_env": "", "source": "none", "code": m["code"]}

	## {ok, v, data, source: main|bak|none, code}
	func read(kind: String) -> Dictionary:
		var r := _read_full(kind)
		return {"ok": r["ok"], "v": r["v"], "data": r["data"], "source": r["source"], "code": r["code"]}

	## Compact text of the valid stored envelope, or "" (used by export so checksums stay byte exact).
	func read_text(kind: String) -> String:
		var r := _read_full(kind)
		return r["raw_env"] if r["ok"] else ""

	func remove(kind: String, keep_bak: bool = false) -> void:
		var key := key_of(kind)
		if key == "":
			return
		_st.remove_item(key)
		if not keep_bak:
			_st.remove_item(key + ".bak")
		_st.remove_item(key + ".tmp")

	func restore_bak(kind: String) -> bool:
		var key := key_of(kind)
		if key == "":
			return false
		var bak_text: Variant = _fetch(key + ".bak")
		if not SaveCodec.check(bak_text, kind, _max_bytes)["ok"]:
			return false
		_st.set_item(key, bak_text)
		return true

	func has(kind: String) -> bool:
		return read(kind)["ok"]


static func create(storage: Object = null, max_bytes: int = MAX_BYTES) -> Store:
	return Store.new(storage, max_bytes)


# ---------------------------------------------------------------- export / import

## The export text: {app, kind: "export", v: 1, game, meta: <envelope|null>, run: <envelope|null>} (compact; whitespace is
## free for the JS importer).
static func export_text(store: Store) -> String:
	var meta := store.read_text("meta")
	var run := store.read_text("run")
	return "{\"app\":\"vcs\",\"kind\":\"export\",\"v\":1,\"game\":%s,\"meta\":%s,\"run\":%s}" % [JsJson.stringify(game_version), meta if meta != "" else "null", run if run != "" else "null"]


## Parse and verify export text: {ok, meta: {v, data}, run: {v, data}|null, code}.
static func parse_import(text: Variant) -> Dictionary:
	var fail := func(code: String) -> Dictionary: return {"ok": false, "meta": null, "run": null, "code": code}
	if not (text is String) or text.length() > MAX_IMPORT:
		return fail.call("E_SAVE_TOO_BIG")
	var p := safe_parse(text)
	if not p["ok"]:
		return fail.call(p["code"])
	var top: Variant = p["value"]
	if not (top is Dictionary) or not _exact_keys(top, IMPORT_KEYS):
		return fail.call("E_SAVE_SCHEMA")
	if top["app"] != "vcs" or top["kind"] != "export" or not _is_num(top["v"]) or float(top["v"]) != 1.0:
		return fail.call("E_SAVE_SCHEMA")
	var parts := split_object(text)
	var meta_raw := split_object(parts.get("meta", ""))
	var m := unwrap(top["meta"], "meta", meta_raw.get("data", ""))
	if not m["ok"]:
		return fail.call(m["code"])
	var run: Variant = null
	if top["run"] != null:
		var run_raw := split_object(parts.get("run", ""))
		var r := unwrap(top["run"], "run", run_raw.get("data", ""))
		if not r["ok"]:
			return fail.call(r["code"])
		run = {"v": r["v"], "data": r["data"]}
	return {"ok": true, "meta": {"v": m["v"], "data": m["data"]}, "run": run, "code": ""}


# ---------------------------------------------------------------- run migrate / sanitize

static func _copy_plain(src: Dictionary) -> Dictionary:
	var out := {}
	for k in src.keys():
		if BAD_KEYS.has(str(k)):
			continue
		out[k] = src[k]
	return out


static func migrate_run(v: Variant, data: Variant) -> Dictionary:
	if not _is_int(v) or float(v) < 1.0 or not (data is Dictionary):
		return {"ok": false, "data": null, "code": "E_SAVE_SCHEMA"}
	var ver := int(v)
	if ver > RUN_SCHEMA:
		return {"ok": false, "data": null, "code": "E_SAVE_VERSION"}
	if ver == 4:
		return {"ok": true, "data": data, "code": ""}
	var out := _copy_plain(data)
	out["v"] = 4
	if ver == 3:
		if not (data.get("run") is Dictionary):
			return {"ok": false, "data": null, "code": "E_SAVE_SCHEMA"}
		out["run"] = _copy_plain(data["run"])
		out["run"]["hunger"] = null
		return {"ok": true, "data": out, "code": ""}
	out["run"] = {"seed": 1, "boons": [], "closedSafe": {}, "pendingBoons": null, "hunger": null}
	if ver == 1:
		out.erase("night")
	return {"ok": true, "data": out, "code": ""}


static func _cell(c: Variant) -> Variant:
	if not (c is Array) or c.size() != 2 or not _is_int(c[0]) or not _is_int(c[1]):
		return null
	return [int(c[0]), int(c[1])]


static func _cells(arr: Variant, max_n: int) -> Variant:
	if not (arr is Array) or arr.size() > max_n:
		return null
	var out: Array = []
	for item in arr:
		var c: Variant = _cell(item)
		if c == null:
			return null
		out.append(c)
	return out


static func _cell_map(obj: Variant, max_n: int) -> Variant:
	if not (obj is Dictionary):
		return null
	var out := {}
	for k in obj.keys():
		if BAD_KEYS.has(str(k)):
			continue
		var c: Variant = _cells(obj[k], max_n)
		if c == null:
			return null
		out[k] = c
	return out


static func _str_list(arr: Variant, max_len: int, max_item: int) -> Variant:
	if not (arr is Array) or arr.size() > max_len:
		return null
	var out: Array = []
	for item in arr:
		if not (item is String) or item.length() > max_item:
			return null
		out.append(item)
	return out


static func _clean_hunger(h: Variant) -> Variant:
	if not (h is Dictionary) or not _exact_keys(h, HUNGER_KEYS):
		return null
	var out := {}
	for k in HUNGER_KEYS:
		if k == "gifts":
			var g: Variant = _str_list(h["gifts"], 20, 24)
			if g == null:
				return null
			out["gifts"] = g
		else:
			if not _is_num(h[k]) or float(h[k]) < 0.0:
				return null
			out[k] = h[k]
	return out


static func _clone_json(v: Variant, depth: int) -> Variant:
	if depth > MAX_DEPTH:
		return null
	if v == null or v is String or v is bool or v is int:
		return v
	if v is float:
		return v if is_finite(v) else null
	if v is Array:
		var a: Array = []
		for item in v:
			if item == null:
				a.append(null)
				continue
			var c: Variant = _clone_json(item, depth + 1)
			if c == null and item != null:
				return null
			a.append(c)
		return a
	if v is Dictionary:
		var out := {}
		for k in v.keys():
			if BAD_KEYS.has(str(k)):
				continue
			var c2: Variant = _clone_json(v[k], depth + 1)
			if c2 == null and v[k] != null:
				return null
			out[k] = c2
		return out
	return null


static func _forge_id_ok(s: String) -> bool:
	var re := RegEx.new()
	re.compile("^[a-z][a-z0-9_]{1,23}$")
	return re.search(s) != null


static func _clamp_num(n: float, lo: float, hi: float) -> float:
	return lo if n < lo else (hi if n > hi else n)


## Validate the optional run.forge block; null when invalid (looks are validated by Forge.validate_look).
static func sanitize_forge(f: Variant) -> Variant:
	if not (f is Dictionary) or f.size() != 2 or not f.has("v") or not f.has("maps"):
		return null
	if not _is_num(f["v"]) or float(f["v"]) != 1.0 or not (f["maps"] is Dictionary):
		return null
	var names: Array = f["maps"].keys()
	if names.size() > 4:
		return null
	var maps := {}
	for name in names:
		var nm := str(name)
		if BAD_KEYS.has(nm) or nm.length() < 1 or nm.length() > 32:
			return null
		var m: Variant = f["maps"][name]
		if not (m is Dictionary):
			return null
		for k in m.keys():
			if k != "spawned" and k != "altered":
				return null
		var spawned: Array = []
		var altered: Array = []
		if m.has("spawned"):
			if not (m["spawned"] is Array) or m["spawned"].size() > 4:
				return null
			for e in m["spawned"]:
				if not (e is Dictionary) or not (e.get("a") is String) or not _forge_id_ok(e["a"]):
					return null
				if not _is_int(e.get("s")) or float(e["s"]) < 0.0 or float(e["s"]) > 4294967295.0:
					return null
				if not _is_num(e.get("x")) or not _is_num(e.get("y")) or not _is_num(e.get("ang")):
					return null
				spawned.append({"a": e["a"], "s": e["s"], "x": _clamp_num(float(e["x"]), 0.0, 64.0), "y": _clamp_num(float(e["y"]), 0.0, 64.0), "ang": _clamp_num(float(e["ang"]), -7.0, 7.0)})
		if m.has("altered"):
			if not (m["altered"] is Array) or m["altered"].size() > 16:
				return null
			for e in m["altered"]:
				if not (e is Dictionary) or not _is_int(e.get("id")) or float(e["id"]) < 0.0 or float(e["id"]) > 255.0:
					return null
				var r: Variant = Forge.validate_look(e.get("look"), true)
				if not (r is Dictionary) or not r.get("ok") or not (r.get("value") is Dictionary):
					return null
				altered.append({"id": e["id"], "look": r["value"].duplicate()})
		maps[name] = {"spawned": spawned, "altered": altered}
	return {"v": 1, "maps": maps}


## Validate a run payload at the current schema: the clean run Dictionary, or null (js sanitizeRun).
static func sanitize_run(data: Variant) -> Variant:
	if not (data is Dictionary):
		return null
	if not data.has("v") or not _is_num(data["v"]) or int(data["v"]) != RUN_SCHEMA:
		return null
	var map: Variant = data.get("map")
	if not (map is String) or map.length() < 1 or map.length() > 32:
		return null
	var pl: Variant = data.get("player")
	if not (pl is Dictionary) or not pl.has("x") or not pl.has("y") or not pl.has("angle"):
		return null
	if not _is_num(pl["x"]) or not _is_num(pl["y"]) or not _is_num(pl["angle"]):
		return null
	var doors: Variant = _cell_map(data.get("doors"), 512)
	if doors == null:
		return null
	var pe: Variant = data.get("people")
	if not (pe is Dictionary):
		return null
	var people := {}
	for k in pe.keys():
		if BAD_KEYS.has(str(k)):
			continue
		if not _is_num(pe[k]):
			return null
		people[k] = pe[k]
	var r: Variant = data.get("run")
	if not (r is Dictionary):
		return null
	for k in RUN_RUN_KEYS:
		if not r.has(k):
			return null
	if not _is_int(r["seed"]) or float(r["seed"]) < 0.0 or float(r["seed"]) > 4294967295.0:
		return null
	var boons: Variant = _str_list(r["boons"], 20, 24)
	if boons == null:
		return null
	var closed_safe: Variant = _cell_map(r["closedSafe"], 16)
	if closed_safe == null:
		return null
	var hunger: Variant = null
	if r.has("hunger") and r["hunger"] != null:
		hunger = _clean_hunger(r["hunger"])
		if hunger == null:
			return null
		if Hunger.restore(hunger) == null:
			return null
	var pending_gifts: Variant = null
	if r.has("pendingGifts") and r["pendingGifts"] != null:
		pending_gifts = _str_list(r["pendingGifts"], 3, 24)
		if pending_gifts == null:
			return null
	var pending: Variant = null
	if r["pendingBoons"] != null:
		pending = _str_list(r["pendingBoons"], 3, 24)
		if pending == null:
			return null
	var out := {"v": 4, "map": map, "player": {"x": pl["x"], "y": pl["y"], "angle": pl["angle"]}, "doors": doors, "people": people}
	if _is_int(data.get("rocks")) and float(data["rocks"]) >= 0.0 and float(data["rocks"]) <= 99.0:
		out["rocks"] = int(data["rocks"])
	if data.has("night"):
		if not (data["night"] is Dictionary):
			return null
		var n: Variant = _clone_json(data["night"], 1)
		if n == null:
			return null
		if Night.restore(_clone_json(n, 1)) == null:
			return null
		out["night"] = n
	if data.has("forge"):
		var fg: Variant = sanitize_forge(data["forge"])
		if fg != null:
			out["forge"] = fg
	out["run"] = {"seed": r["seed"], "boons": boons, "closedSafe": closed_safe, "pendingBoons": pending, "hunger": hunger, "pendingGifts": pending_gifts}
	return out


## migrate + sanitize without writing: {ok, code}.
static func validate_run(data: Variant, v: Variant = null) -> Dictionary:
	var ver: Variant = v if _is_int(v) else (data.get("v") if data is Dictionary and _is_int(data.get("v")) else RUN_SCHEMA)
	var m := migrate_run(ver, data)
	if not m["ok"]:
		return {"ok": false, "code": m["code"]}
	if sanitize_run(m["data"]) == null:
		return {"ok": false, "code": "E_SAVE_SCHEMA"}
	return {"ok": true, "code": ""}


# ---------------------------------------------------------------- rogue (The Coffin) / trek saves

static func _nn_int(x: Variant, max_v: float) -> bool:
	return _is_int(x) and float(x) >= 0.0 and float(x) <= max_v


static func migrate_rogue(v: Variant, data: Variant) -> Dictionary:
	if not _is_int(v) or float(v) < 1.0 or not (data is Dictionary):
		return {"ok": false, "data": null, "code": "E_SAVE_SCHEMA"}
	if int(v) > ROGUE_SCHEMA:
		return {"ok": false, "data": null, "code": "E_SAVE_VERSION"}
	return {"ok": true, "data": data, "code": ""}


## Exact-key structural check of a rogue save; returns a cleaned copy or null.
static func sanitize_rogue(data: Variant) -> Variant:
	if not (data is Dictionary):
		return null
	var opt := 0
	for k in ROGUE_OPTIONAL_KEYS:
		if data.has(k):
			if not (data[k] is bool):
				return null
			opt += 1
	if data.size() != ROGUE_KEYS.size() + opt:
		return null
	for k in ROGUE_KEYS:
		if not data.has(k):
			return null
	if not _is_num(data["v"]) or int(data["v"]) != ROGUE_SCHEMA:
		return null
	if not _nn_int(data["soil"], 1000000000.0) or not (data["legacyImported"] is bool):
		return null
	var ul: Variant = data["unlocks"]
	if not (ul is Dictionary) or ul.size() > 64:
		return null
	var unlocks := {}
	for k in ul.keys():
		if not (k is String) or k.length() > 24 or BAD_KEYS.has(k) or not _nn_int(ul[k], 9.0):
			return null
		unlocks[k] = int(ul[k])
	var st: Variant = data["stats"]
	if not (st is Dictionary) or not _exact_keys(st, ROGUE_STAT_KEYS):
		return null
	var stats := {}
	for k in ROGUE_STAT_KEYS:
		if k == "deaths":
			var d: Variant = st["deaths"]
			if not (d is Dictionary) or not _exact_keys(d, ROGUE_DEATH_KEYS):
				return null
			var deaths := {}
			for dk in ROGUE_DEATH_KEYS:
				if not _nn_int(d[dk], 1000000000.0):
					return null
				deaths[dk] = int(d[dk])
			stats["deaths"] = deaths
		elif k == "bestMiles":
			if not _is_num(st[k]) or float(st[k]) < 0.0 or float(st[k]) > 1000000000.0:
				return null
			stats[k] = st[k]
		else:
			if not _nn_int(st[k], 1000000000.0):
				return null
			stats[k] = int(st[k])
	var reached: Variant = _str_list(data["reached"], 64, 32)
	if reached == null:
		return null
	var out := {"v": ROGUE_SCHEMA, "soil": int(data["soil"]), "unlocks": unlocks, "stats": stats, "reached": reached, "legacyImported": data["legacyImported"]}
	if opt > 0:
		out["tutorialDone"] = data["tutorialDone"]
	return out


static func validate_rogue(data: Variant, v: Variant = null) -> Dictionary:
	var ver: Variant = v if _is_int(v) else (data.get("v") if data is Dictionary and _is_int(data.get("v")) else ROGUE_SCHEMA)
	var m := migrate_rogue(ver, data)
	if not m["ok"]:
		return {"ok": false, "code": m["code"]}
	if sanitize_rogue(m["data"]) == null:
		return {"ok": false, "code": "E_SAVE_SCHEMA"}
	return {"ok": true, "code": ""}


static func migrate_trek(v: Variant, data: Variant) -> Dictionary:
	if not _is_int(v) or float(v) < 1.0 or not (data is Dictionary):
		return {"ok": false, "data": null, "code": "E_SAVE_SCHEMA"}
	if int(v) > TREK_SCHEMA:
		return {"ok": false, "data": null, "code": "E_SAVE_VERSION"}
	return {"ok": true, "data": data, "code": ""}


## Exact-key structural check of a trek (in-progress run) save; returns a cleaned copy or null.
static func sanitize_trek(data: Variant) -> Variant:
	if not (data is Dictionary) or not _exact_keys(data, TREK_KEYS):
		return null
	if not _is_num(data["v"]) or int(data["v"]) != TREK_SCHEMA:
		return null
	if not _nn_int(data["seed"], 4294967295.0) or not _nn_int(data["leg"], 1000000.0) or not _nn_int(data["deathsAvoided"], 1000.0):
		return null
	var stage: Variant = data["stage"]
	if not (stage is String) or stage.length() < 1 or stage.length() > 32:
		return null
	for k in ["miles", "progress", "heat"]:
		if not _is_num(data[k]) or float(data[k]) < 0.0 or float(data[k]) > 1000000.0:
			return null
	var night: Variant = null
	if data["night"] != null:
		if not (data["night"] is Dictionary):
			return null
		night = _clone_json(data["night"], 1)
		if night == null:
			return null
	var hunger: Variant = null
	if data["hunger"] != null:
		hunger = _clean_hunger(data["hunger"])
		if hunger == null:
			return null
	var used: Variant = _str_list(data["unlocksUsed"], 32, 24)
	if used == null:
		return null
	return {"v": TREK_SCHEMA, "seed": int(data["seed"]), "stage": stage, "leg": int(data["leg"]), "miles": data["miles"], "progress": data["progress"], "heat": data["heat"], "night": night, "hunger": hunger, "unlocksUsed": used, "deathsAvoided": int(data["deathsAvoided"])}


static func validate_trek(data: Variant, v: Variant = null) -> Dictionary:
	var ver: Variant = v if _is_int(v) else (data.get("v") if data is Dictionary and _is_int(data.get("v")) else TREK_SCHEMA)
	var m := migrate_trek(ver, data)
	if not m["ok"]:
		return {"ok": false, "code": m["code"]}
	if sanitize_trek(m["data"]) == null:
		return {"ok": false, "code": "E_SAVE_SCHEMA"}
	return {"ok": true, "code": ""}


# ---------------------------------------------------------------- two-instance lock

## Claim the lock (heartbeat): the storage holds {id, t}.
static func tab_lock(storage: Object, id: String, now: float) -> bool:
	if storage == null or id == "" or not is_finite(now):
		return false
	storage.set_item(TAB_KEY, JsJson.stringify({"id": id, "t": now}))
	return true


## Is another instance alive? {other: bool, id?: String}.
static func tab_check(storage: Object, id: String, now: float) -> Dictionary:
	if storage == null or not is_finite(now):
		return {"other": false}
	var raw: Variant = storage.get_item(TAB_KEY)
	if not (raw is String) or raw.length() > 256:
		return {"other": false}
	var p: Variant = JSON.parse_string(raw)
	if not (p is Dictionary) or not (p.get("id") is String) or not _is_num(p.get("t")):
		return {"other": false}
	if p["id"] == id:
		return {"other": false}
	var age: float = now - float(p["t"])
	if age < TAB_STALE_MS and age > -TAB_STALE_MS:
		return {"other": true, "id": String(p["id"]).substr(0, 40)}
	return {"other": false}
