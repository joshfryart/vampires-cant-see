class_name Night
extends RefCounted
## Ports js/night.js: the night clock, blood drain, feeding, dawn and the sun. One Night instance is the JS state object.
## A "night" runs 20:00 -> 06:00 (600 game minutes over nightSec real seconds).

const NIGHT_MIN := 600.0
const CHIME_MIN := 540.0
const WASH_MIN := 570.0
const WASH_SPAN := 30.0
const DAWN_SPAN := 60.0
const WEAK_BELOW := 25.0
const STATUSES := ["night", "day", "won", "lost"]
const ST_KEYS := ["v", "night", "min", "blood", "status", "reason", "fired", "fedCount"]
const FIRED_KEYS := ["chime", "washout", "dawn"]
const MAX_FED := 1000000
const MAX_REASON := 32
const DEFAULTS := {"nightSec": 480.0, "nights": 5.0, "bloodMax": 100.0, "bloodStart": 60.0, "feedGain": 40.0}

var drain_mul: float = 1.0
var ramp: float = 0.0
var night: int = 1
var nights: int = 5
var night_sec: float = 480.0
var min: float = 0.0
var blood: float = 60.0
var blood_max: float = 100.0
var feed_gain: float = 40.0
var status: String = "night"
var reason: String = ""
var fired: Dictionary = {"chime": false, "washout": false, "dawn": false}
var fed_count: int = 0


static func _is_num(x: Variant) -> bool:
	return (x is float or x is int) and is_finite(float(x))


static func _is_int(x: Variant) -> bool:
	return _is_num(x) and floor(float(x)) == float(x)


## Ports create (js/night.js:40). Bad option values fall back to the defaults.
static func create(opts: Dictionary = {}) -> Night:
	var out := {}
	for k in DEFAULTS:
		var v: Variant = opts.get(k)
		if v == null:
			out[k] = DEFAULTS[k]
			continue
		var ok: bool = _is_num(v) and float(v) > 0.0
		if ok and k == "nights":
			ok = _is_int(v) and float(v) <= 1000.0
		if ok and k == "nightSec":
			ok = float(v) <= 86400.0
		if not ok and k == "bloodStart" and _is_num(v) and float(v) == 0.0:
			ok = true
		out[k] = float(v) if ok else DEFAULTS[k]
	if out["bloodStart"] > out["bloodMax"]:
		out["bloodStart"] = out["bloodMax"]
	var s := Night.new()
	if _is_num(opts.get("drainMul")) and float(opts["drainMul"]) > 0.0:
		s.drain_mul = float(opts["drainMul"])
	if _is_num(opts.get("ramp")) and float(opts["ramp"]) >= 0.0:
		s.ramp = float(opts["ramp"])
	s.nights = int(out["nights"])
	s.night_sec = out["nightSec"]
	s.blood = out["bloodStart"]
	s.blood_max = out["bloodMax"]
	s.feed_gain = out["feedGain"]
	return s


func active() -> bool:
	return status == "night" or status == "day"


## Advance the night by dt seconds (clamped to 0.1). ctx {outdoor: bool}. Returns the events fired: chime, washout, dawn, lost.
func update(dt: float, ctx: Variant = null) -> Array:
	var events: Array = []
	if not active():
		return events
	var d: float = clampf(dt if is_finite(dt) else 0.0, 0.0, 0.1)
	var outdoor: bool = ctx is Dictionary and ctx.get("outdoor") == true
	min = minf(NIGHT_MIN, min + (d * NIGHT_MIN) / night_sec)
	blood = maxf(0.0, blood - (d * blood_max) / night_sec * drain_mul * (1.0 + ramp * (float(night) - 1.0)))
	if min >= CHIME_MIN and not fired["chime"]:
		fired["chime"] = true
		events.append("chime")
	if min >= WASH_MIN and not fired["washout"]:
		fired["washout"] = true
		events.append("washout")
	if min >= NIGHT_MIN and not fired["dawn"]:
		fired["dawn"] = true
		status = "day"
		events.append("dawn")
	if status == "day" and outdoor:
		status = "lost"
		reason = "sun"
		events.append("lost")
	return events


## Feed: returns blood gained (0 if not active).
func feed() -> float:
	if not active():
		return 0.0
	var before := blood
	blood = minf(blood_max, blood + feed_gain)
	fed_count += 1
	return blood - before


## Add blood (drinking). Returns the actual gain, clamped to blood_max; 0 when inactive or amt is bad.
func add_blood(amt: float) -> float:
	if not active() or not is_finite(amt) or amt <= 0.0:
		return 0.0
	var before := blood
	blood = minf(blood_max, blood + amt)
	return blood - before


## Sleep: "next" | "won" | "none".
func sleep() -> String:
	if not active():
		return "none"
	if night < nights:
		night += 1
		min = 0.0
		fired = {"chime": false, "washout": false, "dawn": false}
		status = "night"
		reason = ""
		return "next"
	status = "won"
	return "won"


static func _pad2(n: int) -> String:
	return ("0" if n < 10 else "") + str(n)


## Clock for the HUD: {hour, minute, text, frac}.
func clock() -> Dictionary:
	var m: float = clampf(min if is_finite(min) else 0.0, 0.0, NIGHT_MIN)
	var total: int = (1200 + int(floor(m))) % 1440
	var hour: int = total / 60
	var minute: int = total % 60
	return {"hour": hour, "minute": minute, "text": _pad2(hour) + ":" + _pad2(minute), "frac": m / NIGHT_MIN}


func weakness() -> float:
	return clampf(1.0 - blood / WEAK_BELOW, 0.0, 1.0) if blood < WEAK_BELOW else 0.0


func wash_k() -> float:
	return clampf((min - WASH_MIN) / WASH_SPAN, 0.0, 1.0)


func dawn_k() -> float:
	return clampf((min - CHIME_MIN) / DAWN_SPAN, 0.0, 1.0)


func is_day() -> bool:
	return status == "day"


## Debug: jump to a clock time within 20:00..06:00.
func skip_to(hour: float, minute: float) -> bool:
	if not active():
		return false
	if not _is_int(hour) or not _is_int(minute) or minute < 0 or minute > 59 or hour < 0 or hour > 23:
		return false
	var m: float
	if hour >= 20.0:
		m = (hour - 20.0) * 60.0 + minute
	elif hour < 6.0:
		m = (hour + 4.0) * 60.0 + minute
	elif hour == 6.0 and minute == 0.0:
		m = NIGHT_MIN
	else:
		return false
	min = m
	if m < CHIME_MIN:
		fired["chime"] = false
	if m < WASH_MIN:
		fired["washout"] = false
	if m < NIGHT_MIN:
		fired["dawn"] = false
		if status == "day":
			status = "night"
			reason = ""
	return true


func serialize() -> Dictionary:
	return {
		"v": 1, "night": night, "min": min, "blood": blood, "status": status, "reason": reason,
		"fired": {"chime": bool(fired["chime"]), "washout": bool(fired["washout"]), "dawn": bool(fired["dawn"])},
		"fedCount": fed_count,
	}


## Validate a serialized Dictionary; returns a fresh state or null. Never throws.
static func restore(obj: Variant, opts: Dictionary = {}) -> Night:
	if not (obj is Dictionary):
		return null
	for k in obj.keys():
		if not ST_KEYS.has(k):
			return null
	var st := create(opts)
	if not _is_num(obj.get("v")) or float(obj["v"]) != 1.0:
		return null
	var n: Variant = obj.get("night")
	if not _is_int(n) or float(n) < 1.0 or float(n) > st.nights:
		return null
	var mn: Variant = obj.get("min")
	if not _is_num(mn) or float(mn) < 0.0 or float(mn) > NIGHT_MIN:
		return null
	var bl: Variant = obj.get("blood")
	if not _is_num(bl) or float(bl) < 0.0 or float(bl) > st.blood_max:
		return null
	if not (obj.get("status") is String) or not STATUSES.has(obj["status"]):
		return null
	if not (obj.get("reason") is String) or String(obj["reason"]).length() > MAX_REASON:
		return null
	var fc: Variant = obj.get("fedCount")
	if not _is_int(fc) or float(fc) < 0.0 or float(fc) > MAX_FED:
		return null
	var f: Variant = obj.get("fired")
	if not (f is Dictionary):
		return null
	for k in f.keys():
		if not FIRED_KEYS.has(k):
			return null
	for k in FIRED_KEYS:
		if not (f.get(k) is bool):
			return null
	if obj["status"] == "day" and float(mn) < NIGHT_MIN:
		return null
	st.night = int(n)
	st.min = float(mn)
	st.blood = float(bl)
	st.status = obj["status"]
	st.reason = obj["reason"]
	st.fired = {"chime": f["chime"], "washout": f["washout"], "dawn": f["dawn"]}
	st.fed_count = int(fc)
	return st
