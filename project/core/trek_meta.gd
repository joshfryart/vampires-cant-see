class_name TrekMeta
extends RefCounted
## Roguelike meta-progression (The Coffin): soil, unlock tiers, lifetime stats, the stages reached. Separate from the
## parity-locked classic Meta. State is a plain Dictionary exactly as saved under `vcs.rogue`:
## {v, soil, unlocks{id:tier}, stats{treks, bestMiles, bestStage, deaths{sun,withered,staked,holy}, fedHumans,
## fedCritters, soilEarned}, reached[stageIds], legacyImported, tutorialDone (additive, optional in saves)}. Data: data/rogue/unlocks.json.

const SCHEMA := 1
const MAX_SOIL := 1000000000
const MAX_STAT := 1000000000
const MAX_REACHED := 64
const DEATH_KEYS := ["sun", "withered", "staked", "holy"]

static var _cache: Variant = null


static func _d() -> Dictionary:
	if _cache == null:
		var f := FileAccess.open("res://data/rogue/unlocks.json", FileAccess.READ)
		_cache = JSON.parse_string(f.get_as_text()) if f != null else {"EFFECT_DEFAULTS": {}, "EFFECT_LIMITS": {}, "upgrades": []}
	return _cache


static func _is_num(x: Variant) -> bool:
	return (x is float or x is int) and is_finite(float(x))


static func _clean_int(x: Variant, max_v: int = MAX_STAT) -> int:
	return mini(int(floor(float(x))), max_v) if _is_num(x) and float(x) > 0.0 else 0


static func unlock_by_id(id: Variant) -> Variant:
	if not (id is String):
		return null
	for u in _d()["upgrades"]:
		if u["id"] == id:
			return u
	return null


static func max_tier(id: String) -> int:
	var u: Variant = unlock_by_id(id)
	return 0 if u == null else (u["tiers"] as Array).size()


static func create() -> Dictionary:
	var ul := {}
	for u in _d()["upgrades"]:
		ul[u["id"]] = 0
	return {"v": SCHEMA, "soil": 0, "unlocks": ul,
		"stats": {"treks": 0, "bestMiles": 0.0, "bestStage": 0, "deaths": {"sun": 0, "withered": 0, "staked": 0, "holy": 0}, "fedHumans": 0, "fedCritters": 0, "soilEarned": 0},
		"reached": [], "legacyImported": false, "tutorialDone": false}


## Repair arbitrary data into a valid meta; null only when it is not a Dictionary of this schema.
static func sanitize(d: Variant) -> Variant:
	if not (d is Dictionary):
		return null
	if not d.has("v") or not _is_num(d["v"]) or float(d["v"]) != float(SCHEMA):
		return null
	var out := create()
	out["soil"] = _clean_int(d.get("soil"), MAX_SOIL)
	var ul: Variant = d.get("unlocks")
	if ul is Dictionary:
		for k in ul.keys():
			var u: Variant = unlock_by_id(k)
			if u != null:
				out["unlocks"][k] = clampi(_clean_int(ul[k], 99), 0, (u["tiers"] as Array).size())
	var st: Variant = d.get("stats")
	if st is Dictionary:
		var s: Dictionary = out["stats"]
		for k in ["treks", "bestStage", "fedHumans", "fedCritters", "soilEarned"]:
			s[k] = _clean_int(st.get(k))
		s["bestMiles"] = minf(float(MAX_STAT), maxf(0.0, float(st["bestMiles"]))) if _is_num(st.get("bestMiles")) else 0.0
		var dt: Variant = st.get("deaths")
		if dt is Dictionary:
			for k in DEATH_KEYS:
				s["deaths"][k] = _clean_int(dt.get(k))
	var rc: Variant = d.get("reached")
	if rc is Array:
		for id in rc:
			if id is String and id.length() >= 1 and id.length() <= 32 and not out["reached"].has(id) and out["reached"].size() < MAX_REACHED:
				out["reached"].append(id)
	var li: Variant = d.get("legacyImported")
	out["legacyImported"] = li is bool and li
	# `tutorialDone` (first-night tutorial finished or skipped) is additive: a save without it (written before the tutorial existed)
	# counts as done when the player has already made a trek, otherwise the tutorial is still to come.
	var td: Variant = d.get("tutorialDone")
	out["tutorialDone"] = td if td is bool else int(out["stats"]["treks"]) > 0
	return out


## {ok, data, code}. v1 is the identity; scaffold for later schema versions.
static func migrate(v: Variant, data: Variant) -> Dictionary:
	if not _is_num(v) or float(v) < 1.0 or float(v) != floor(float(v)) or not (data is Dictionary):
		return {"ok": false, "data": null, "code": "E_SAVE_SCHEMA"}
	if float(v) > float(SCHEMA):
		return {"ok": false, "data": null, "code": "E_SAVE_VERSION"}
	var ver := int(v)
	var cur: Dictionary = data
	# if ver < 2: cur = _v1_to_v2(cur); ver = 2   (future steps chain here)
	return {"ok": true, "data": cur, "code": ""}


static func tier_of(meta: Variant, id: String) -> int:
	if not (meta is Dictionary) or not (meta.get("unlocks") is Dictionary) or not meta["unlocks"].has(id) or unlock_by_id(id) == null:
		return 0
	var t: Variant = meta["unlocks"][id]
	return clampi(int(floor(float(t))), 0, max_tier(id)) if _is_num(t) else 0


## Cost of the next tier, or -1 at max / unknown.
static func cost_of(meta: Variant, id: String) -> int:
	var u: Variant = unlock_by_id(id)
	if u == null:
		return -1
	var t := tier_of(meta, id)
	return -1 if t >= (u["tiers"] as Array).size() else int(u["costs"][t])


## First unmet prerequisite {id, tier}, or null.
static func missing_prereq(meta: Variant, id: String) -> Variant:
	var u: Variant = unlock_by_id(id)
	if u == null:
		return null
	for r in u["requires"]:
		if tier_of(meta, r["id"]) < int(r["tier"]):
			return r
	return null


## Buy the next tier: {ok, code, cost}. Codes: OK, E_META_UNKNOWN, E_META_MAX, E_META_LOCKED, E_META_POOR.
static func buy(meta: Variant, id: String) -> Dictionary:
	if unlock_by_id(id) == null or not (meta is Dictionary) or not (meta.get("unlocks") is Dictionary):
		return {"ok": false, "code": "E_META_UNKNOWN", "cost": -1}
	var cost := cost_of(meta, id)
	if cost < 0:
		return {"ok": false, "code": "E_META_MAX", "cost": -1}
	if missing_prereq(meta, id) != null:
		return {"ok": false, "code": "E_META_LOCKED", "cost": cost}
	if not _is_num(meta.get("soil")) or float(meta["soil"]) < cost:
		return {"ok": false, "code": "E_META_POOR", "cost": cost}
	meta["soil"] = int(meta["soil"]) - cost
	meta["unlocks"][id] = tier_of(meta, id) + 1
	return {"ok": true, "code": "OK", "cost": cost}


## Soil for a run {miles, humans, critters, unseen (stages cleared unseen), newBest (bool)}; meta (optional) supplies the
## Soil Pouch multiplier.
static func soil_for_run(stats: Variant, meta: Variant = null) -> int:
	if not (stats is Dictionary):
		return 0
	var base: int = _clean_int(stats.get("miles")) + 2 * _clean_int(stats.get("humans")) + _clean_int(stats.get("critters")) / 2 \
		+ 3 * _clean_int(stats.get("unseen")) + (5 if (stats.get("newBest") is bool and stats["newBest"]) else 0)
	var mul := 1.0 + float(effects(meta)["soilMul"]) if meta != null else 1.0
	return mini(MAX_SOIL, int(floor(float(base) * mul + 1e-9)))


## Record a finished trek {miles, humans, critters, unseen, stageIndex (1-based best reached), reached [ids], death
## (sun|withered|staked|holy or ""/survived)}; returns the soil earned.
static func record_run(meta: Variant, run: Variant) -> int:
	if not (meta is Dictionary) or not (meta.get("stats") is Dictionary):
		return 0
	var r: Dictionary = run if run is Dictionary else {}
	var s: Dictionary = meta["stats"]
	var stage_idx := _clean_int(r.get("stageIndex"), 1000)
	var miles: float = minf(float(MAX_STAT), maxf(0.0, float(r["miles"]))) if _is_num(r.get("miles")) else 0.0
	var humans := _clean_int(r.get("humans"))
	var critters := _clean_int(r.get("critters"))
	var new_best := stage_idx > _clean_int(s.get("bestStage"))
	var earned := soil_for_run({"miles": miles, "humans": humans, "critters": critters, "unseen": r.get("unseen"), "newBest": new_best}, meta)
	meta["soil"] = mini(MAX_SOIL, _clean_int(meta.get("soil"), MAX_SOIL) + earned)
	s["treks"] = mini(MAX_STAT, _clean_int(s.get("treks")) + 1)
	s["bestMiles"] = maxf(float(s["bestMiles"]) if _is_num(s.get("bestMiles")) else 0.0, miles)
	s["bestStage"] = maxi(_clean_int(s.get("bestStage")), stage_idx)
	s["fedHumans"] = mini(MAX_STAT, _clean_int(s.get("fedHumans")) + humans)
	s["fedCritters"] = mini(MAX_STAT, _clean_int(s.get("fedCritters")) + critters)
	s["soilEarned"] = mini(MAX_STAT, _clean_int(s.get("soilEarned")) + earned)
	var death: Variant = r.get("death")
	if death is String and DEATH_KEYS.has(death):
		if not (s.get("deaths") is Dictionary):
			s["deaths"] = {"sun": 0, "withered": 0, "staked": 0, "holy": 0}
		s["deaths"][death] = mini(MAX_STAT, _clean_int(s["deaths"].get(death)) + 1)
	if not (meta.get("reached") is Array):
		meta["reached"] = []
	if r.get("reached") is Array:
		for id in r["reached"]:
			if id is String and id.length() >= 1 and id.length() <= 32 and not meta["reached"].has(id) and meta["reached"].size() < MAX_REACHED:
				meta["reached"].append(id)
	return earned


## The effect table, shaped like Meta.effects (defaults + upgrades, clamped) so RunFlow.compute_fx can use it; the same
## optional boon/extra arguments are not used here (trek has no boons), but extra [{effect, op, value}] is honoured.
static func effects(meta: Variant, extra: Variant = null) -> Dictionary:
	var d := _d()
	var fx := {}
	for k in d["EFFECT_DEFAULTS"]:
		fx[k] = float(d["EFFECT_DEFAULTS"][k])
	for u in d["upgrades"]:
		var t := tier_of(meta, u["id"])
		if t > 0:
			_apply(fx, u["effect"], u["op"], u["tiers"][t - 1])
	if extra is Array:
		for e in extra:
			if e is Dictionary and e.get("effect") is String and e["effect"] != "bloodNow":
				_apply(fx, e["effect"], e.get("op"), e.get("value"))
	for k in d["EFFECT_LIMITS"]:
		var lim: Array = d["EFFECT_LIMITS"][k]
		fx[k] = maxf(float(lim[0]), minf(float(lim[1]), float(fx[k])))
	return fx


static func _apply(fx: Dictionary, effect: Variant, op: Variant, val: Variant) -> void:
	if not (effect is String) or not fx.has(effect) or not _is_num(val):
		return
	if op == "mul":
		fx[effect] = float(fx[effect]) * float(val)
	elif op == "add":
		fx[effect] = float(fx[effect]) + float(val)


## Convert the classic meta's Essence into Soil 1:1, once. Returns the soil added (0 when already imported or unusable).
static func import_legacy_essence(meta: Variant, classic_meta: Variant) -> int:
	if not (meta is Dictionary) or (meta.get("legacyImported") is bool and meta["legacyImported"]):
		return 0
	if not (classic_meta is Dictionary) or not _is_num(classic_meta.get("essence")):
		return 0
	var add := _clean_int(classic_meta["essence"], MAX_SOIL)
	var before := _clean_int(meta.get("soil"), MAX_SOIL)
	var now := mini(MAX_SOIL, before + add)
	meta["soil"] = now
	meta["legacyImported"] = true
	return now - before
