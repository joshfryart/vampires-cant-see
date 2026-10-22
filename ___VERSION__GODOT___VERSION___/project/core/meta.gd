class_name Meta
extends RefCounted
## Ports js/meta.js (+ js/data/upgrades.js through data/upgrades.json): the persistent meta state (essence, upgrade
## tiers, stats), run recording and the effect table. The meta state is a plain Dictionary
## {v, essence, upgrades: {id: tier}, stats: {...}} exactly as saved, so Save codec and tests treat it as data.

const SCHEMA := 1
const MAX_ESSENCE := 1000000
const MAX_STAT := 1000000000
const MAX_TIER := 3
const STAT_KEYS := ["runs", "wins", "nightsSurvived", "peopleFed", "bestNights", "essenceEarned"]
const TOP_KEYS := ["v", "essence", "upgrades", "stats"]


static func _d() -> Dictionary:
	return GameData.get_json("upgrades")


static func _is_num(x: Variant) -> bool:
	return (x is float or x is int) and is_finite(float(x))


static func upgrade_by_id(id: Variant) -> Variant:
	if not (id is String):
		return null
	for u in _d()["upgrades"]:
		if u["id"] == id:
			return u
	return null


static func boon_by_id(id: Variant) -> Variant:
	if not (id is String):
		return null
	for b in _d()["boons"]:
		if b["id"] == id:
			return b
	return null


static func create() -> Dictionary:
	var ups := {}
	for u in _d()["upgrades"]:
		ups[u["id"]] = 0
	return {"v": SCHEMA, "essence": 0, "upgrades": ups, "stats": {"runs": 0, "wins": 0, "nightsSurvived": 0, "peopleFed": 0, "bestNights": 0, "essenceEarned": 0}}


## Non-negative number -> floored int clamped to max; -1 when not a non-negative number (js toInt returns null).
static func _to_int(x: Variant, max_v: float) -> int:
	if not _is_num(x) or float(x) < 0.0:
		return -1
	var f: float = floor(float(x))
	return int(max_v) if f > max_v else int(f)


## Ports sanitize: a clean meta Dictionary, or null when the input is unusable.
static func sanitize(obj: Variant) -> Variant:
	if not (obj is Dictionary):
		return null
	if not obj.has("v") or not _is_num(obj["v"]) or float(obj["v"]) != float(SCHEMA):
		return null
	var essence: int = _to_int(obj["essence"], MAX_ESSENCE) if obj.has("essence") else -1
	if essence < 0:
		return null
	var out := create()
	out["essence"] = essence
	if obj.has("upgrades"):
		var up: Variant = obj["upgrades"]
		if not (up is Dictionary):
			return null
		for k in up.keys():
			if upgrade_by_id(k) == null:
				continue
			var t: int = _to_int(up[k], MAX_TIER)
			if t < 0:
				return null
			out["upgrades"][k] = t
	if obj.has("stats"):
		var st: Variant = obj["stats"]
		if not (st is Dictionary):
			return null
		for k in st.keys():
			if not STAT_KEYS.has(k):
				continue
			var n: int = _to_int(st[k], MAX_STAT)
			if n < 0:
				return null
			out["stats"][k] = n
	return out


## Ports migrate: {ok, data, code}. v0 saves had {essence, bought: [ids]}.
static func migrate(v: Variant, data: Variant) -> Dictionary:
	if not _is_num(v) or float(v) < 0.0 or float(v) != floor(float(v)):
		return {"ok": false, "data": null, "code": "E_SAVE_SCHEMA"}
	if float(v) > float(SCHEMA):
		return {"ok": false, "data": null, "code": "E_SAVE_VERSION"}
	if float(v) == 1.0:
		return {"ok": true, "data": data, "code": ""}
	if float(v) == 0.0:
		if not (data is Dictionary) or not data.has("essence") or not _is_num(data["essence"]) or not data.has("bought") or not (data["bought"] is Array):
			return {"ok": false, "data": null, "code": "E_SAVE_SCHEMA"}
		var m := create()
		m["essence"] = data["essence"]
		for id in data["bought"]:
			if id is String and upgrade_by_id(id) != null:
				m["upgrades"][id] = 1
		return {"ok": true, "data": m, "code": ""}
	return {"ok": false, "data": null, "code": "E_SAVE_SCHEMA"}


static func tier_of(meta: Variant, id: String) -> int:
	if not (meta is Dictionary) or not (meta.get("upgrades") is Dictionary) or not meta["upgrades"].has(id) or upgrade_by_id(id) == null:
		return 0
	var t: Variant = meta["upgrades"][id]
	return clampi(int(floor(float(t))), 0, MAX_TIER) if _is_num(t) else 0


## Cost of the next tier, or -1 at max / unknown (js costOf returns null).
static func cost_of(meta: Variant, id: String) -> int:
	var u: Variant = upgrade_by_id(id)
	if u == null:
		return -1
	var t := tier_of(meta, id)
	return -1 if t >= MAX_TIER else int(u["costs"][t])


## Buy the next tier: {ok, code, cost} (cost -1 when none).
static func buy(meta: Variant, id: String) -> Dictionary:
	if upgrade_by_id(id) == null:
		return {"ok": false, "code": "E_META_UNKNOWN", "cost": -1}
	if not (meta is Dictionary) or not (meta.get("upgrades") is Dictionary):
		return {"ok": false, "code": "E_META_UNKNOWN", "cost": -1}
	var cost := cost_of(meta, id)
	if cost < 0:
		return {"ok": false, "code": "E_META_MAX", "cost": -1}
	if not _is_num(meta.get("essence")) or float(meta["essence"]) < cost:
		return {"ok": false, "code": "E_META_POOR", "cost": cost}
	meta["essence"] = float(meta["essence"]) - cost
	meta["upgrades"][id] = tier_of(meta, id) + 1
	return {"ok": true, "code": "OK", "cost": cost}


static func _clean_int(x: Variant) -> int:
	return mini(int(floor(float(x))), MAX_STAT) if _is_num(x) and float(x) > 0.0 else 0


## Essence earned by a run {nights, fed, won}.
static func essence_for(run: Variant) -> int:
	if not (run is Dictionary):
		return 0
	return _clean_int(run.get("nights")) * 4 + _clean_int(run.get("fed")) + (15 if run.get("won") else 0)


## Record a finished run into the meta stats; returns the essence earned.
static func record_run(meta: Variant, run: Variant) -> int:
	if not (meta is Dictionary) or not (meta.get("stats") is Dictionary):
		return 0
	var r: Dictionary = run if run is Dictionary else {}
	var nights := _clean_int(r.get("nights"))
	var fed := _clean_int(r.get("fed"))
	var won: bool = bool(r.get("won", false))
	var bonus: int = mini(1000, _clean_int(r.get("bonus")))
	var earned: int = essence_for({"nights": nights, "fed": fed, "won": won}) + bonus
	var s: Dictionary = meta["stats"]
	meta["essence"] = mini(MAX_ESSENCE, _clean_int(meta.get("essence")) + earned)
	s["runs"] = mini(MAX_STAT, _clean_int(s.get("runs")) + 1)
	s["wins"] = mini(MAX_STAT, _clean_int(s.get("wins")) + (1 if won else 0))
	s["nightsSurvived"] = mini(MAX_STAT, _clean_int(s.get("nightsSurvived")) + nights)
	s["peopleFed"] = mini(MAX_STAT, _clean_int(s.get("peopleFed")) + fed)
	s["bestNights"] = maxi(_clean_int(s.get("bestNights")), nights)
	s["essenceEarned"] = mini(MAX_STAT, _clean_int(s.get("essenceEarned")) + earned)
	return earned


static func _apply(fx: Dictionary, effect: Variant, op: Variant, val: Variant) -> void:
	if not (effect is String) or not fx.has(effect) or not _is_num(val):
		return
	if op == "mul":
		fx[effect] = float(fx[effect]) * float(val)
	elif op == "add":
		fx[effect] = float(fx[effect]) + float(val)


## The effect table for a meta state, the run's boon ids and extra [{effect, op, value}] (hunger gifts).
static func effects(meta: Variant, boons: Variant, extra: Variant) -> Dictionary:
	var d := _d()
	var fx := {}
	for k in d["EFFECT_DEFAULTS"]:
		fx[k] = float(d["EFFECT_DEFAULTS"][k])
	for u in d["upgrades"]:
		var t := tier_of(meta, u["id"])
		if t > 0:
			_apply(fx, u["effect"], u["op"], u["tiers"][t - 1])
	if boons is Array:
		for id in boons:
			var b: Variant = boon_by_id(id)
			if b != null:
				_apply(fx, b["effect"], b["op"], b["value"])
	if extra is Array:
		for e in extra:
			if e is Dictionary and e.get("effect") is String and e["effect"] != "bloodNow":
				_apply(fx, e["effect"], e.get("op"), e.get("value"))
	for k in d["EFFECT_LIMITS"]:
		var lim: Array = d["EFFECT_LIMITS"][k]
		fx[k] = maxf(float(lim[0]), minf(float(lim[1]), float(fx[k])))
	return fx


## Three boon ids to offer (js rollBoons).
static func roll_boons(seed_v: float, taken: Variant) -> Array:
	var tk: Array = taken if taken is Array else []
	var pool: Array = []
	for b in _d()["boons"]:
		if b["repeat"] or not tk.has(b["id"]):
			pool.append(b["id"])
	var rng := Rng.new(seed_v if is_finite(seed_v) else 0.0)
	var n: int = mini(3, pool.size())
	for i in n:
		var j: int = i + int(floor(rng.next() * (pool.size() - i)))
		var tmp: Variant = pool[i]
		pool[i] = pool[j]
		pool[j] = tmp
	return pool.slice(0, n)
