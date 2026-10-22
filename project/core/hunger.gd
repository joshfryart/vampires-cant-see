class_name Hunger
extends RefCounted
## Ports js/hunger.js (+ js/data/hunger.js through data/hunger.json): village fear, overflow blood and gifts, the three
## powers (Shriek, Mist, Still) with their cooldowns. One Hunger instance is the JS state object.

const SCHEMA := 1
const MAX_GIFTS := 20
const MAX_GRABBED := 500
const MAX_NEXT_BLOOD := 1000.0
const MAX_ESSENCE_BONUS := 1000.0
const STILL_SECS := 5.0
const SAVE_KEYS := ["v", "fear", "over", "giftsTonight", "gifts", "essenceBonus", "nextBlood"]

var fear: float = 0.0
var over: float = 0.0
var gifts_tonight: float = 0.0
var gifts: Array = []
var essence_bonus: float = 0.0
var next_blood: float = 0.0
var grabbed: Array = []
var cd: Dictionary = {"shriek": 0.0, "mist": 0.0, "still": 0.0}
var still_left: float = 0.0


static func _d() -> Dictionary:
	return GameData.get_json("hunger")


static func _is_num(x: Variant) -> bool:
	return (x is float or x is int) and is_finite(float(x))


static func power_by_id(id: String) -> Variant:
	for p in _d()["powers"]:
		if p["id"] == id:
			return p
	return null


static func gift_by_id(id: String) -> Variant:
	for g in _d()["gifts"]:
		if g["id"] == id:
			return g
	return null


static func fear_max() -> float:
	return float(_d()["FEAR_MAX"])


static func create() -> Hunger:
	return Hunger.new()


# ---- overflow ----

## Cost (blood) of the next gift, or -1 when no more gifts tonight (js cost() returns null).
func cost() -> float:
	var d := _d()
	var n: int = int(floor(gifts_tonight))
	if n < 0 or n >= int(d["GIFTS_PER_NIGHT"]) or n >= d["GIFT_COSTS"].size():
		return -1.0
	return float(d["GIFT_COSTS"][n])


func is_open() -> bool:
	return cost() >= 0.0


func over01() -> float:
	var c := cost()
	if c < 0.0 or not is_finite(over):
		return 0.0
	return clampf(over / c, 0.0, 1.0)


## Returns {taken, ready}.
func add_overflow(amt: float) -> Dictionary:
	var c := cost()
	if c < 0.0:
		return {"taken": 0.0, "ready": false}
	if not is_finite(over) or over < 0.0:
		over = 0.0
	var room: float = maxf(0.0, c - over)
	var taken: float = minf(amt, room) if is_finite(amt) and amt > 0.0 else 0.0
	over = minf(c, over + taken)
	return {"taken": taken, "ready": over >= c}


# ---- gifts ----

## Three gift ids to offer (js rollGifts).
func roll_gifts(seed_v: float) -> Array:
	var ids: Array = []
	for g in _d()["gifts"]:
		ids.append(g["id"])
	var n: int = gifts.size()
	var sd: float = floor(seed_v) if is_finite(seed_v) else 0.0
	var rnd := Rng.new(float(JsMath.u32(sd * 2654435761.0 + float(n) * 40503.0 + 12345.0)))
	var count: int = mini(3, ids.size())
	for i in count:
		var j: int = i + int(floor(rnd.next() * (ids.size() - i)))
		var t: Variant = ids[i]
		ids[i] = ids[j]
		ids[j] = t
	return ids.slice(0, count)


## Returns {ok, instant: {fear?, nextBlood?}}.
func take_gift(id: String) -> Dictionary:
	var g: Variant = gift_by_id(id)
	if g == null:
		return {"ok": false, "instant": {}}
	var d := _d()
	if gifts.size() < MAX_GIFTS:
		gifts.append(g["id"])
	gifts_tonight = maxf(0.0, floor(gifts_tonight)) + 1.0
	over = 0.0
	essence_bonus = minf(MAX_ESSENCE_BONUS, essence_bonus + float(d["GIFT_ESSENCE"]))
	var instant := {}
	if g["kind"] == "fear":
		add_fear(float(g["value"]))
		instant["fear"] = g["value"]
	elif g["kind"] == "nextBlood":
		next_blood = minf(MAX_NEXT_BLOOD, next_blood + float(g["value"]))
		instant["nextBlood"] = g["value"]
	return {"ok": true, "instant": instant}


## Effect gifts as [{effect, op, value}] for Meta.effects.
func gift_mods() -> Array:
	var out: Array = []
	for id in gifts:
		var g: Variant = gift_by_id(id)
		if g != null and g["kind"] == "effect":
			out.append({"effect": g["effect"], "op": g["op"], "value": g["value"]})
	return out


# ---- fear ----

## js Math.round for the fear step: halves go up.
func add_fear(n: float) -> float:
	if not is_finite(n):
		return 0.0
	var cur: float = fear if is_finite(fear) else 0.0
	fear = clampf(floor(cur + n + 0.5), 0.0, fear_max())
	return fear


## First grab of a person adds fear once. person_id is any hashable (the game passes "map:id").
func on_grab(person_id: Variant) -> bool:
	if person_id == null:
		return false
	if grabbed.has(person_id):
		return false
	if grabbed.size() < MAX_GRABBED:
		grabbed.append(person_id)
	add_fear(float(_d()["FEAR"]["grab"]))
	return true


## {startleMul, fleeMul, calmMul}.
func fear_mods() -> Dictionary:
	var d := _d()
	var f: float = clampf(fear, 0.0, fear_max()) if is_finite(fear) else 0.0
	var calm: Array = d["FEAR_CALM"] if d.has("FEAR_CALM") else [0.04, 0.6]
	return {
		"startleMul": 1.0 + minf(float(d["FEAR_STARTLE"][1]), float(d["FEAR_STARTLE"][0]) * f),
		"fleeMul": 1.0 + minf(float(d["FEAR_FLEE"][1]), float(d["FEAR_FLEE"][0]) * f),
		"calmMul": 1.0 + minf(float(calm[1]), float(calm[0]) * f),
	}


# ---- powers ----

func _cd_of(id: String) -> float:
	var v: Variant = cd.get(id)
	return float(v) if _is_num(v) and float(v) > 0.0 else 0.0


## "locked" | "cooldown" | "poor" | "ready".
func power_state(id: String, night: float, blood: float) -> String:
	var p: Variant = power_by_id(id)
	if p == null or not is_finite(night) or night < float(p["unlock"]):
		return "locked"
	if _cd_of(id) > 0.0:
		return "cooldown"
	if not is_finite(blood) or blood < float(p["cost"]):
		return "poor"
	return "ready"


func cd_left01(id: String) -> float:
	var p: Variant = power_by_id(id)
	if p == null:
		return 0.0
	return clampf(_cd_of(id) / float(p["cooldown"]), 0.0, 1.0)


## Use a power: {ok, code, cost} (cost is -1 for an unknown power).
func use(id: String, night: float, blood: float) -> Dictionary:
	var p: Variant = power_by_id(id)
	if p == null:
		return {"ok": false, "code": "E_UNKNOWN", "cost": -1.0}
	var s := power_state(id, night, blood)
	if s == "locked":
		return {"ok": false, "code": "E_LOCKED", "cost": float(p["cost"])}
	if s == "cooldown":
		return {"ok": false, "code": "E_COOLDOWN", "cost": float(p["cost"])}
	if s == "poor":
		return {"ok": false, "code": "E_POOR", "cost": float(p["cost"])}
	cd[id] = float(p["cooldown"])
	add_fear(float(p["fear"]))
	if id == "still":
		still_left = STILL_SECS
	return {"ok": true, "code": "", "cost": float(p["cost"])}


func tick(dt: float) -> void:
	if not is_finite(dt):
		return
	var d: float = clampf(dt, 0.0, 0.1)
	for k in cd.keys():
		cd[k] = maxf(0.0, float(cd[k]) - d) if _is_num(cd[k]) else 0.0
	still_left = maxf(0.0, still_left - d) if is_finite(still_left) else 0.0


func is_still() -> bool:
	return is_finite(still_left) and still_left > 0.0


# ---- sleep / persistence ----

## Sleeping calms the town and resets the night; returns the carried "next night" blood.
func on_sleep() -> float:
	add_fear(float(_d()["FEAR"]["sleep"]))
	over = 0.0
	gifts_tonight = 0.0
	grabbed = []
	var nb: float = next_blood if is_finite(next_blood) and next_blood > 0.0 else 0.0
	next_blood = 0.0
	return nb


func serialize() -> Dictionary:
	return {"v": SCHEMA, "fear": fear, "over": over, "giftsTonight": gifts_tonight, "gifts": gifts.duplicate(), "essenceBonus": essence_bonus, "nextBlood": next_blood}


## Validate a serialized Dictionary; returns a fresh state or null.
static func restore(obj: Variant) -> Hunger:
	if not (obj is Dictionary) or obj.size() != SAVE_KEYS.size():
		return null
	for k in SAVE_KEYS:
		if not obj.has(k):
			return null
	if not _is_num(obj["v"]) or int(obj["v"]) != SCHEMA:
		return null
	var d := _d()
	for k in ["fear", "over", "giftsTonight", "essenceBonus", "nextBlood"]:
		if not _is_num(obj[k]) or float(obj[k]) < 0.0:
			return null
	if float(obj["fear"]) > float(d["FEAR_MAX"]) or float(obj["fear"]) != floor(float(obj["fear"])):
		return null
	if float(obj["giftsTonight"]) > float(d["GIFTS_PER_NIGHT"]) or float(obj["giftsTonight"]) != floor(float(obj["giftsTonight"])):
		return null
	if float(obj["essenceBonus"]) > MAX_ESSENCE_BONUS or float(obj["nextBlood"]) > MAX_NEXT_BLOOD:
		return null
	if not (obj["gifts"] is Array) or obj["gifts"].size() > MAX_GIFTS:
		return null
	for g in obj["gifts"]:
		if not (g is String) or gift_by_id(g) == null:
			return null
	var st := Hunger.new()
	st.fear = float(obj["fear"])
	st.gifts_tonight = float(obj["giftsTonight"])
	st.gifts = obj["gifts"].duplicate()
	st.essence_bonus = float(obj["essenceBonus"])
	st.next_blood = float(obj["nextBlood"])
	var c := st.cost()
	st.over = 0.0 if c < 0.0 else minf(float(obj["over"]), c)
	return st
