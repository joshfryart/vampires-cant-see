class_name Forge
extends RefCounted
## Ports js/forge.js: turns data archetypes plus a seed into a villager spec (look, voice, schedule role, flags), validates
## looks / archetypes / specs / libraries, alters a look, and rolls reinforcements. Seed-deterministic. Results are
## Dictionaries like the JS objects: {ok, code, person|value|look, errors}.
## The custom archetype library is process-wide (static), as in the JS module state.

const MAX_CUSTOM := 16
const LIBRARY_MAX_BYTES := 16384
const BAD_KEYS := ["__proto__", "constructor", "prototype"]
const ACCESSORIES := ["tophat", "nightcap", "bonnet", "cane", "scarf", "lantern", "hood", "umbrella", "cap", "basket"]
const HATS := ["tophat", "nightcap", "bonnet", "cap", "hood"]
const PROPS := ["cane", "lantern", "umbrella", "basket"]
const NUM_KEYS := ["height", "build", "stride", "nose", "stoop", "shoulder", "hem", "skin"]
const BOOL_KEYS := ["beard", "coat"]
const ENUM_KEYS := ["acc", "body", "head", "hat", "hair", "prop", "outfit", "roleHat", "extra"]
const ARCH_KEYS := ["id", "role", "label", "legacy", "voice", "talk", "schedule", "watch", "feedable", "gait", "speed", "recipe", "extras"]
const DEFAULTS := {
	"height": 1.0, "build": 1.0, "stride": 1.0, "acc": "none", "body": "bean", "head": "round", "hat": "none", "hair": "none", "beard": false,
	"nose": 1.0, "coat": false, "prop": "none", "v": 1, "archetype": "patron", "outfit": "plain", "roleHat": "none", "extra": "none",
	"stoop": 0.0, "shoulder": 1.0, "hem": 0.0, "skin": 0.5,
}
## Marks a key that is absent (JS `undefined`), distinct from an explicit null.
const UNDEF := &"__undefined__"

static var _custom: Dictionary = {}


static func _ad() -> Dictionary:
	return GameData.get_json("archetypes")


static func _is_num(n: Variant) -> bool:
	return (n is float or n is int) and is_finite(float(n))


static func _is_plain(o: Variant) -> bool:
	return o is Dictionary


static func _read(o: Variant, k: String) -> Variant:
	if o is Dictionary and o.has(k):
		return o[k]
	return UNDEF


static func _undef(v: Variant) -> bool:
	return v is StringName and v == UNDEF


static func _clampf(n: float, lo: float, hi: float) -> float:
	return lo if n < lo else (hi if n > hi else n)


static func _in_list(lst: Variant, v: Variant) -> bool:
	return lst is Array and lst.has(v)


static func _id_ok(s: Variant) -> bool:
	if not (s is String):
		return false
	var re := RegEx.new()
	re.compile("^[a-z][a-z0-9_]{1,23}$")
	return re.search(s) != null


static func look_keys() -> Array:
	return _ad()["LOOK_KEYS"]


static func enums() -> Dictionary:
	return _ad()["LOOK_ENUMS"]


static func ranges() -> Dictionary:
	return _ad()["LOOK_RANGES"]


static func legacy_recipe() -> Dictionary:
	return _ad()["LEGACY_RECIPE"]


## Same seed derivation as the legacy makeLook, with pid := entry_seed.
static func look_seed(state_seed: float, entry_seed: float) -> int:
	var sd: float = state_seed if is_finite(state_seed) else 0.0
	var pid: float = floor(entry_seed) if is_finite(entry_seed) else 0.0
	return JsMath.u32(float(JsMath.u32(sd)) * 2654435761.0 + (pid + 1.0) * 40503.0 + 977.0)


static func _pick(lst: Array, r: float) -> Variant:
	return lst[int(floor(r * lst.size()))]


## Verbatim body of the v0.13 People.makeLook.
static func legacy_look(seed_v: float, id: float, acc_offset: float) -> Dictionary:
	return People.make_look(seed_v, int(floor(id)) if is_finite(id) else 0, int(floor(acc_offset)) if is_finite(acc_offset) else 0)


# ---------------------------------------------------------------- validation

static func _fresh_defaults(partial: bool) -> Dictionary:
	return {} if partial else DEFAULTS.duplicate()


## hat/prop follow acc; hair is hidden under tophat, nightcap and hood. patch null = derive everything.
static func _apply_rules(look: Dictionary, patch: Variant) -> void:
	var has_acc: bool = patch is Dictionary and patch.has("acc")
	if patch == null or (has_acc and not patch.has("hat")):
		look["hat"] = look["acc"] if HATS.has(look["acc"]) else "none"
	if patch == null or (has_acc and not patch.has("prop")):
		look["prop"] = look["acc"] if PROPS.has(look["acc"]) else "none"
	if look["hat"] == "nightcap" or look["hat"] == "hood" or look["hat"] == "tophat":
		look["hair"] = "none"


static func validate_look(obj: Variant, partial: bool = false) -> Dictionary:
	var errors: Array = []
	if not (obj is Dictionary):
		return {"ok": false, "code": "E_FORGE_TYPE", "value": _fresh_defaults(partial), "errors": ["look must be an object"]}
	var e := enums()
	var r := ranges()
	var keys := look_keys()
	var bad := false
	for k in obj.keys():
		if BAD_KEYS.has(str(k)) or not keys.has(k):
			bad = true
			errors.append("bad key: " + str(k).left(32))
	if bad:
		return {"ok": false, "code": "E_FORGE_BAD_KEY", "value": _fresh_defaults(partial), "errors": errors}
	var out := {}
	for k in keys:
		var has: bool = obj.has(k)
		if not has and partial:
			continue
		var raw: Variant = obj[k] if has else UNDEF
		var def: Variant = DEFAULTS[k]
		if k == "v":
			out["v"] = 1
		elif k == "archetype":
			if _id_ok(raw):
				out[k] = raw
			else:
				if has:
					errors.append("archetype")
				if not partial:
					out[k] = def
		elif NUM_KEYS.has(k):
			var rg: Array = r[k] if r.has(k) else [0.0, 1.0]
			if _is_num(raw):
				out[k] = _clampf(float(raw), float(rg[0]), float(rg[1]))
			else:
				if has:
					errors.append(k)
				if not partial:
					out[k] = def
		elif BOOL_KEYS.has(k):
			if raw is bool:
				out[k] = raw
			else:
				if has:
					errors.append(k)
				if not partial:
					out[k] = def
		elif ENUM_KEYS.has(k):
			if raw is String and _in_list(e.get(k), raw):
				out[k] = raw
			else:
				if has:
					errors.append(k)
				if not partial:
					out[k] = def
		elif not partial:
			out[k] = def
	if not partial:
		_apply_rules(out, null)
	return {"ok": true, "code": "OK", "value": out, "errors": errors}


static func validate_recipe(rc: Variant) -> Variant:
	var base := legacy_recipe()
	if not (rc is Dictionary):
		return null
	var out := {}
	var pairs := [["height", 0.5, 1.2, 0.7], ["build", 0.7, 1.4, 0.7], ["stride", 0.7, 1.4, 0.7], ["nose", 0.5, 1.6, 1.1]]
	for p in pairs:
		var k: String = p[0]
		var v: Variant = _read(rc, k)
		if _undef(v):
			out[k] = base[k].duplicate()
			continue
		if not (v is Array) or v.size() != 2 or not _is_num(v[0]) or not _is_num(v[1]):
			return null
		out[k] = [_clampf(float(v[0]), float(p[1]), float(p[2])), _clampf(float(v[1]), 0.0, float(p[3]))]
	var e := enums()
	for pair in [["bodies", "body"], ["heads", "head"], ["hairs", "hair"]]:
		var k2: String = pair[0]
		var v2: Variant = _read(rc, k2)
		if _undef(v2):
			out[k2] = base[k2].duplicate()
			continue
		if not (v2 is Array) or v2.size() < 1 or v2.size() > 16:
			return null
		for item in v2:
			if not _in_list(e[pair[1]], item):
				return null
		out[k2] = v2.duplicate()
	for k3 in ["beardP", "coatP"]:
		var v3: Variant = _read(rc, k3)
		out[k3] = _clampf(float(v3), 0.0, 1.0) if _is_num(v3) else base[k3]
	var acc: Variant = _read(rc, "acc")
	if _undef(acc) or (acc is String and acc == "cycle"):
		out["acc"] = "cycle"
	elif acc is String and _in_list(e["acc"], acc):
		out["acc"] = acc
	else:
		return null
	return out


static func validate_extras(x: Variant) -> Dictionary:
	var e := enums()
	var r := ranges()
	var out := {}
	var src: Dictionary = x if x is Dictionary else {}
	for k in ["outfit", "roleHat", "extra"]:
		var v: Variant = src.get(k)
		out[k] = v if v is String and _in_list(e[k], v) else DEFAULTS[k]
	for k in ["stoop", "shoulder", "hem", "skin"]:
		var v2: Variant = src.get(k)
		var rg: Array = r[k] if r.has(k) else [0.0, 1.0]
		if _is_num(v2):
			out[k] = _clampf(float(v2), float(rg[0]), float(rg[1]))
		elif v2 is Array and v2.size() == 2 and _is_num(v2[0]) and _is_num(v2[1]):
			out[k] = [_clampf(float(v2[0]), float(rg[0]), float(rg[1])), _clampf(float(v2[1]), 0.0, float(rg[1]) - float(rg[0]))]
		else:
			out[k] = DEFAULTS[k]
	return out


## {ok, value}: null / "watch" / a template (1..12 stops of [places, until, act]).
static func validate_schedule(s: Variant) -> Dictionary:
	if s == null or (s is StringName and s == UNDEF):
		return {"ok": true, "value": null}
	if s is String and s == "watch":
		return {"ok": true, "value": "watch"}
	if not (s is Array) or s.size() < 1 or s.size() > 12:
		return {"ok": false}
	var out: Array = []
	for t in s:
		if not (t is Array) or t.size() != 3 or not (t[0] is Array) or t[0].size() < 1 or t[0].size() > 8:
			return {"ok": false}
		if not _is_num(t[1]) or not (t[2] is String) or t[2].length() > 16:
			return {"ok": false}
		var places: Array = []
		for p in t[0]:
			if not (p is String) or p.length() > 24:
				return {"ok": false}
			places.append(p)
		out.append([places, _clampf(float(t[1]), 0.0, 1.0), t[2]])
	return {"ok": true, "value": out}


static func validate_archetype(a: Variant) -> Dictionary:
	if not (a is Dictionary):
		return {"ok": false, "code": "E_FORGE_TYPE", "value": null, "errors": ["archetype must be an object"]}
	var errors: Array = []
	for k in a.keys():
		if BAD_KEYS.has(str(k)) or not ARCH_KEYS.has(k):
			errors.append("bad key: " + str(k).left(32))
	if not errors.is_empty():
		return {"ok": false, "code": "E_FORGE_BAD_KEY", "value": null, "errors": errors}
	var id: Variant = _read(a, "id")
	if not _id_ok(id):
		return {"ok": false, "code": "E_FORGE_TYPE", "value": null, "errors": ["bad id"]}
	var role: Variant = _read(a, "role")
	var role_undef: bool = role is StringName and role == UNDEF
	if not role_undef and (not (role is String) or role.length() > 24):
		return {"ok": false, "code": "E_FORGE_TYPE", "value": null, "errors": ["bad role"]}
	var voice: Variant = _read(a, "voice")
	var presets: Dictionary = GameData.get_json("voices")["PRESETS"]
	if not (voice is String) or voice.length() > 24 or not presets.has(voice):
		return {"ok": false, "code": "E_FORGE_TYPE", "value": null, "errors": ["bad voice"]}
	var talk: Variant = _read(a, "talk")
	if not (talk is String) or talk.length() > 24:
		return {"ok": false, "code": "E_FORGE_TYPE", "value": null, "errors": ["bad talk"]}
	var sch := validate_schedule(_read(a, "schedule"))
	if not sch["ok"]:
		return {"ok": false, "code": "E_FORGE_TYPE", "value": null, "errors": ["bad schedule"]}
	var gait: Variant = _read(a, "gait")
	var recipe_in: Variant = _read(a, "recipe")
	var recipe_undef: bool = recipe_in is StringName and recipe_in == UNDEF
	var recipe: Variant = legacy_recipe() if recipe_undef else validate_recipe(recipe_in)
	if recipe == null:
		return {"ok": false, "code": "E_FORGE_TYPE", "value": null, "errors": ["bad recipe"]}
	var speed: Variant = _read(a, "speed")
	var label: Variant = _read(a, "label")
	var value := {
		"id": id,
		"role": role if (role is String and role != "") else "",
		"label": String(label).left(32) if label is String else id,
		"legacy": false,
		"voice": voice,
		"talk": talk,
		"schedule": sch["value"],
		"watch": _read(a, "watch") == true,
		"feedable": _read(a, "feedable") != false,
		"gait": "mail" if gait is String and gait == "mail" else "walk",
		"speed": _clampf(float(speed), 0.5, 2.0) if _is_num(speed) else 1.0,
		"recipe": recipe.duplicate(true),
		"extras": validate_extras(_read(a, "extras") if not (_read(a, "extras") is StringName) else null),
	}
	return {"ok": true, "code": "OK", "value": value, "errors": errors}


static func validate_spec(s: Variant) -> Dictionary:
	if not (s is Dictionary):
		return {"ok": false, "code": "E_FORGE_TYPE", "value": null, "errors": ["spec must be an object"]}
	for k in s.keys():
		if BAD_KEYS.has(str(k)) or not ["archetype", "seed", "home", "overrides"].has(k):
			return {"ok": false, "code": "E_FORGE_BAD_KEY", "value": null, "errors": ["bad key: " + str(k).left(32)]}
	var arch: Variant = _read(s, "archetype")
	if not _id_ok(arch):
		return {"ok": false, "code": "E_FORGE_TYPE", "value": null, "errors": ["bad archetype"]}
	var value := {"archetype": arch}
	var seed_v: Variant = _read(s, "seed")
	if _is_num(seed_v):
		value["seed"] = floor(_clampf(float(seed_v), 0.0, 4294967295.0))
	var home: Variant = _read(s, "home")
	if not (home is StringName and home == UNDEF) and home != null:
		if not (home is String) and not _is_num(home):
			return {"ok": false, "code": "E_FORGE_TYPE", "value": null, "errors": ["bad home"]}
		value["home"] = String(home).left(24) if home is String else home
	var ov: Variant = _read(s, "overrides")
	if not (ov is StringName and ov == UNDEF):
		var r := validate_look(ov, true)
		if not r["ok"]:
			return {"ok": false, "code": r["code"], "value": null, "errors": r["errors"]}
		value["overrides"] = r["value"]
	return {"ok": true, "code": "OK", "value": value, "errors": []}


static func validate_library(lib: Variant) -> Dictionary:
	if not (lib is Dictionary):
		return {"ok": false, "code": "E_FORGE_TYPE", "value": null, "errors": ["library must be an object"]}
	for k in lib.keys():
		if BAD_KEYS.has(str(k)) or (k != "v" and k != "list"):
			return {"ok": false, "code": "E_FORGE_BAD_KEY", "value": null, "errors": ["bad key: " + str(k).left(32)]}
	if not _is_num(_read(lib, "v")) or float(_read(lib, "v")) != 1.0:
		return {"ok": false, "code": "E_FORGE_TYPE", "value": null, "errors": ["bad version"]}
	var lst: Variant = _read(lib, "list")
	if not (lst is Array):
		return {"ok": false, "code": "E_FORGE_TYPE", "value": null, "errors": ["list must be an array"]}
	if lst.size() > MAX_CUSTOM:
		return {"ok": false, "code": "E_FORGE_LIMIT", "value": null, "errors": ["too many archetypes"]}
	var out: Array = []
	for item in lst:
		var r := validate_archetype(item)
		if not r["ok"]:
			return {"ok": false, "code": r["code"], "value": null, "errors": r["errors"]}
		out.append(r["value"])
	return {"ok": true, "code": "OK", "value": {"v": 1, "list": out}, "errors": []}


## validate("look" | "archetype" | "spec" | "library", obj, partial).
static func validate(kind: String, obj: Variant, partial: bool = false) -> Dictionary:
	match kind:
		"look": return validate_look(obj, partial)
		"archetype": return validate_archetype(obj)
		"spec": return validate_spec(obj)
		"library": return validate_library(obj)
	return {"ok": false, "code": "E_FORGE_UNKNOWN", "value": null, "errors": ["unknown kind"]}


# ---------------------------------------------------------------- archetypes (built-in + custom overlay)

static func _builtin_by_id(id: String) -> Variant:
	for a in _ad()["list"]:
		if a["id"] == id:
			return a
	return null


static func _builtin_by_role(role: String) -> Variant:
	var found: Variant = null
	for a in _ad()["list"]:
		if a["role"] == role:
			found = a  # the JS map keeps the last archetype per role
	return found


static func archetype(id: Variant) -> Variant:
	if not (id is String) or BAD_KEYS.has(id):
		return null
	var b: Variant = _builtin_by_id(id)
	if b != null:
		return b
	return _custom.get(id)


static func list_ids() -> Array:
	var out: Array = []
	for a in _ad()["list"]:
		out.append(a["id"])
	for k in _custom.keys():
		out.append(k)
	return out


static func by_role(role: Variant) -> Variant:
	if not (role is String) or BAD_KEYS.has(role):
		return null
	var b: Variant = _builtin_by_role(role)
	if b != null:
		return b
	for k in _custom.keys():
		if _custom[k]["role"] == role and role != "":
			return _custom[k]
	return null


static func register(arch: Variant) -> Dictionary:
	var r := validate_archetype(arch)
	if not r["ok"]:
		return {"ok": false, "code": r["code"]}
	var id: String = r["value"]["id"]
	if _builtin_by_id(id) != null:
		return {"ok": false, "code": "E_FORGE_BAD_KEY"}
	if not _custom.has(id) and _custom.size() >= MAX_CUSTOM:
		return {"ok": false, "code": "E_FORGE_LIMIT"}
	_custom[id] = r["value"]
	return {"ok": true, "code": "OK"}


## Clears the custom library (tests).
static func reset_custom() -> void:
	_custom.clear()


# ---------------------------------------------------------------- generate / alter

## generate(spec, ctx): {ok, code, person}. spec {archetype, seed?, home?, overrides?}, ctx {stateSeed, index, accOffset}.
static func generate(spec: Variant, ctx: Variant) -> Dictionary:
	var sp: Dictionary = spec if spec is Dictionary else {}
	var cx: Dictionary = ctx if ctx is Dictionary else {}
	var id: String = sp["archetype"] if sp.get("archetype") is String else "patron"
	var arch: Variant = archetype(id)
	var ok := true
	var code := "OK"
	if arch == null:
		ok = false
		code = "E_FORGE_UNKNOWN"
		arch = archetype("patron")
	if arch == null:
		return {"ok": false, "code": "E_FORGE_UNKNOWN", "person": null}
	return {"ok": ok, "code": code, "person": _build(arch, sp, cx)}


static func _build(arch: Dictionary, sp: Dictionary, cx: Dictionary) -> Dictionary:
	var raw_seed: Variant = sp.get("seed")
	var index: float = floor(float(cx["index"])) if _is_num(cx.get("index")) else 0.0
	var entry_seed: float = float(raw_seed) if _is_num(raw_seed) and floor(float(raw_seed)) == float(raw_seed) and float(raw_seed) >= 0.0 and float(raw_seed) <= 65535.0 else index
	var state_seed: float = float(cx["stateSeed"]) if _is_num(cx.get("stateSeed")) else 0.0
	var acc_offset: float = floor(float(cx["accOffset"])) if _is_num(cx.get("accOffset")) else 0.0
	var ls: int = look_seed(state_seed, entry_seed)
	var rng := Rng.new(float(ls))
	var rc: Dictionary = arch["recipe"] if arch.get("recipe") != null else legacy_recipe()
	var e := enums()
	var height: float = float(rc["height"][0]) + rng.next() * float(rc["height"][1])
	var bld: float = float(rc["build"][0]) + rng.next() * float(rc["build"][1])
	var stride: float = float(rc["stride"][0]) + rng.next() * float(rc["stride"][1])
	var acc: String
	if rc["acc"] == "cycle":
		var n: int = ACCESSORIES.size()
		acc = ACCESSORIES[int(fposmod(fposmod(acc_offset + 3.0 * entry_seed, float(n)) + n, float(n)))]
	else:
		acc = rc["acc"]
	var body: String = _pick(rc["bodies"], rng.next())
	var head: String = _pick(rc["heads"], rng.next())
	var hat: String = acc if HATS.has(acc) else "none"
	var hair: String = _pick(rc["hairs"], rng.next())
	if hat == "nightcap" or hat == "hood" or hat == "tophat":
		hair = "none"
	var beard: bool = rng.next() < float(rc["beardP"])
	var nose: float = float(rc["nose"][0]) + rng.next() * float(rc["nose"][1])
	var coat: bool = rng.next() < float(rc["coatP"])
	var prop: String = acc if PROPS.has(acc) else "none"
	var look := {"height": height, "build": bld, "stride": stride, "acc": acc, "body": body, "head": head, "hat": hat, "hair": hair, "beard": beard, "nose": nose, "coat": coat, "prop": prop}
	var ex: Dictionary = arch["extras"] if arch.get("extras") is Dictionary else {}
	var er := Rng.new(float((ls ^ 0x9E3779B9) & JsMath.M32))
	var drawn := func(k: String) -> float:
		var v: Variant = ex.get(k)
		if v is Array:
			return float(v[0]) + er.next() * float(v[1])
		return float(v) if _is_num(v) else float(DEFAULTS[k])
	var shoulder: float = drawn.call("shoulder")
	var skin: float = drawn.call("skin")
	var stoop: float = drawn.call("stoop")
	var hem: float = drawn.call("hem")
	look["v"] = 1
	look["archetype"] = arch["id"]
	look["outfit"] = ex["outfit"] if _in_list(e["outfit"], ex.get("outfit")) else "plain"
	look["roleHat"] = ex["roleHat"] if _in_list(e["roleHat"], ex.get("roleHat")) else "none"
	look["extra"] = ex["extra"] if _in_list(e["extra"], ex.get("extra")) else "none"
	look["stoop"] = _clampf(stoop, 0.0, 0.4)
	look["shoulder"] = _clampf(shoulder, 0.8, 1.25)
	look["hem"] = _clampf(hem, 0.0, 1.0)
	look["skin"] = _clampf(skin, 0.0, 1.0)
	var ov: Variant = sp.get("overrides")
	if ov is Dictionary:
		var r := validate_look(ov, true)
		if r["ok"]:
			look.merge(r["value"], true)
			_apply_rules(look, r["value"])
	look["archetype"] = arch["id"]
	look["v"] = 1
	var home: Variant = sp.get("home")
	var sched: Variant = arch.get("schedule")
	return {
		"archetype": arch["id"], "role": arch["role"] if arch.get("role") != null else "", "look": look, "voice": arch["voice"], "talk": arch["talk"],
		"schedRole": arch["role"] if sched != null and arch.get("role") != null and arch["role"] != "" else null,
		"home": home, "watch": bool(arch.get("watch", false)), "feedable": arch.get("feedable") != false, "gait": arch["gait"] if arch.get("gait") != null else "walk",
	}


## alter(look, patch): {ok, code, look, changed}.
static func alter(look: Variant, patch: Variant) -> Dictionary:
	var base := validate_look(look, false)
	if not (look is Dictionary):
		return {"ok": false, "code": "E_FORGE_TYPE", "look": base["value"], "changed": []}
	var src := {}
	for k in look_keys():
		if look.has(k):
			src[k] = look[k]
	var cur: Dictionary = validate_look(src, true)["value"]
	var start: Dictionary = base["value"].duplicate()
	start.merge(cur, true)
	var p := validate_look(patch, true)
	if not p["ok"]:
		return {"ok": false, "code": p["code"], "look": start, "changed": []}
	var nxt: Dictionary = start.duplicate()
	nxt.merge(p["value"], true)
	_apply_rules(nxt, p["value"])
	nxt["v"] = 1
	var changed: Array = []
	for k in nxt.keys():
		if nxt[k] != start.get(k):
			changed.append(k)
	return {"ok": true, "code": "OK", "look": nxt, "changed": changed}


# ---------------------------------------------------------------- library

static func export_library() -> String:
	var out: Array = []
	for k in _custom.keys():
		out.append(_custom[k].duplicate(true))
	return JsJson.stringify({"v": 1, "list": out})


static func import_validated(lib: Variant) -> Dictionary:
	var r := validate_library(lib)
	if not r["ok"]:
		return {"ok": false, "code": r["code"], "n": 0}
	var fresh := 0
	for a in r["value"]["list"]:
		if not _custom.has(a["id"]):
			fresh += 1
	if _custom.size() + fresh > MAX_CUSTOM:
		return {"ok": false, "code": "E_FORGE_LIMIT", "n": 0}
	var n := 0
	for a in r["value"]["list"]:
		if register(a)["ok"]:
			n += 1
	return {"ok": true, "code": "OK", "n": n}


static func import_library(text: Variant) -> Dictionary:
	if not (text is String):
		return {"ok": false, "code": "E_FORGE_TYPE", "n": 0}
	if text.length() > LIBRARY_MAX_BYTES:
		return {"ok": false, "code": "E_FORGE_LIMIT", "n": 0}
	var j := JSON.new()
	if j.parse(text) != OK:
		return {"ok": false, "code": "E_FORGE_PARSE", "n": 0}
	return import_validated(j.data)


# ---------------------------------------------------------------- reinforcements

## reinforcement({fear, night, runSeed, fired}): {archetype, seed, card} or null.
static func reinforcement(o: Variant) -> Variant:
	if not (o is Dictionary):
		return null
	var table: Array = _ad()["REINFORCE"]
	var fear: float = float(o["fear"]) if _is_num(o.get("fear")) else 0.0
	var night: float = floor(float(o["night"])) if _is_num(o.get("night")) else 0.0
	var run_seed: float = floor(float(o["runSeed"])) if _is_num(o.get("runSeed")) else 0.0
	var fired: int = int(floor(float(o["fired"]))) if _is_num(o.get("fired")) else 0
	if fired < 0 or fired >= table.size():
		return null
	var entry: Dictionary = table[fired]
	if not (fear >= float(entry["fear"])):
		return null
	return {"archetype": entry["archetype"], "seed": JsMath.u32(run_seed * 31.0 + night * 977.0 + float(fired) * 7919.0), "card": entry["card"]}
