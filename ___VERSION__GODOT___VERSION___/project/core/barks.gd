class_name Barks
extends RefCounted
## Ports js/barks.js: villager bark decision logic (who speaks what and when). Pure: no audio, no wall clock. People are
## passed as snapshot Dictionaries {id, x, y, mode, wary, bumping, role, sched_role, pool, left, chat_partner, chat_back, dead}
## (see people_snapshot); game.gd plays the result.

const RANGE := 16.0
const DAY_RANGE := 12.0
const MAX_STARTS := 2
const MAX_ACTIVE := 3
const PENDING_TTL := 2.0
const RELIEF_TTL := 8.0
const WHISPER_FEAR := 8.0
const WORRIED_FEAR := 4.0
const ALARM_JUMP := 2.0
const ALARM_WINDOW := 4.0
const BODY_SEEN := 5.0
const STRUGGLE_SLOW := 3.5
const STRUGGLE_EMPTY := 0.02
const RESTRAIN_GAIN := 0.6
const EST_LEN := 1.5
const COOLDOWNS := {
	"notice": [8.0, 12.0], "startle": [6.0, 9.0], "flee": [6.0, 10.0], "cower": [8.0, 12.0], "struggle": [1.0, 2.2],
	"relief": [10.0, 15.0], "alarm": [8.0, 12.0], "daytalk": [9.0, 15.0], "chat": [6.0, 10.0], "hum": [12.0, 15.0],
	"halt": [8.0, 12.0], "guardcall": [10.0, 16.0],
}
const PRIO := {"alarm": 100.0, "startle": 98.0, "flee": 96.0, "halt": 97.0, "struggle": 94.0, "notice": 92.0, "cower": 90.0, "relief": 60.0, "guardcall": 30.0, "daytalk": 20.0, "hum": 10.0}
const FEAR_KIND := ["alarm", "startle", "flee", "struggle", "notice", "cower", "halt"]
const GAIN := {"alarm": 1.0, "startle": 0.95, "flee": 1.0, "struggle": 0.95, "notice": 0.9, "cower": 0.6, "relief": 0.6, "daytalk": 0.65, "hum": 0.4, "halt": 1.0, "guardcall": 0.9}

var seed: int = 1
var v: Dictionary = {}
var active: Array = []
var starts: Array = []
var pair: Dictionary = {}
var last_fear: float = 0.0
var fear_at: float = 0.0
var init: bool = false
var bodies: Dictionary = {}
var total: int = 0
var recent: int = 0
var last_now: float = -INF


static func _hypot(x: float, y: float) -> float:
	return sqrt(x * x + y * y)


## JS hash(a, b): Math.imul mixing of two ints, result unsigned 32.
static func hash2(a: int, b: int) -> int:
	var h: int = (JsMath.imul(a & JsMath.M32, 374761393) + JsMath.imul(b & JsMath.M32, 668265263)) & JsMath.M32
	h = JsMath.imul((h ^ (h >> 13)) & JsMath.M32, 1274126177)
	return (h ^ (h >> 16)) & JsMath.M32


## JS idNum: numbers truncate to int32; anything else string-hashes (h = h*31 + char).
static func id_num(id: Variant) -> int:
	if id is int or id is float:
		return to_i32(int(id))
	var s := str(id)
	var h := 7
	var u := s.to_utf16_buffer()
	for i in range(0, u.size(), 2):
		h = to_i32(JsMath.imul(h & JsMath.M32, 31) + (u[i] | (u[i + 1] << 8)))
	return h


static func to_i32(x: int) -> int:
	x &= JsMath.M32
	return x - 4294967296 if x >= 2147483648 else x


## Seeded unit float from three integers.
static func unit(a: int, b: int, c: int) -> float:
	return float(hash2(hash2(a, b), c)) / 4294967296.0


static func role_of(p: Dictionary) -> String:
	var r: Variant = p.get("role")
	if r is String and r != "":
		return r
	var sr: Variant = p.get("sched_role")
	return sr if sr is String else ""


static func is_guard(p: Dictionary) -> bool:
	var re := RegEx.new()
	re.compile("(?i)guard|watch|soldier")
	return re.search(role_of(p)) != null


static func weak_of(p: Dictionary) -> float:
	var pool: float = float(p.get("pool", 0.0))
	if not (pool > 0.0):
		return 0.0
	var f: float = float(p.get("left", pool)) / pool
	return 1.0 if f <= 0.0 else (0.0 if f >= 1.0 else 1.0 - f)


static func kind_for(p: Dictionary, kind: String) -> String:
	return "halt" if is_guard(p) and (kind == "notice" or kind == "flee" or kind == "startle" or kind == "alarm") else kind


func _init(seed_v: Variant = 1) -> void:
	seed = id_num(seed_v)


func reset() -> void:
	v = {}
	active = []
	starts = []
	pair = {}
	bodies = {}
	init = false
	last_fear = 0.0
	fear_at = 0.0


static func is_wary(p: Dictionary) -> bool:
	return float(p.get("wary", 0.0)) > 0.0


static func silent(p: Dictionary) -> bool:
	return p["mode"] == "fed" or p["mode"] == "dazed" or p.get("dead", false) == true or p.get("drained", false) == true


static func calm(p: Dictionary) -> bool:
	return p["mode"] == "path" and not is_wary(p) and not p.get("bumping", false)


static func tone_for(kind: String, fear: float) -> String:
	if kind == "guardcall":
		return "worried" if fear >= WORRIED_FEAR else "calm"
	if FEAR_KIND.has(kind):
		if kind == "cower" and fear >= WHISPER_FEAR:
			return "whisper"
		return "worried" if fear >= WORRIED_FEAR else "calm"
	return "whisper" if fear >= WHISPER_FEAR else ("worried" if fear >= WORRIED_FEAR else "calm")


static func mood_for(kind: String, tone: String, weak: float) -> String:
	if tone == "whisper":
		return "whisper"
	if kind == "halt":
		return "argue"
	if kind == "guardcall":
		return "call"
	if kind == "struggle":
		return "argue" if weak < 0.3 else "worried"
	if kind == "alarm" or kind == "flee" or kind == "startle" or kind == "notice":
		return "argue"
	if kind == "cower":
		return "worried"
	return "worried" if tone == "worried" else "calm"


func cooldown(vv: Dictionary, kind: String, n: int, weak: float) -> float:
	var r: Array = COOLDOWNS[kind] if COOLDOWNS.has(kind) else COOLDOWNS["daytalk"]
	var base: float = r[0] + (r[1] - r[0]) * unit(seed, vv["key"], n * 7 + 3)
	return base * (1.0 + STRUGGLE_SLOW * pow(weak, 1.5)) if kind == "struggle" else base


## Subtitle {de, en} for a bark dictionary (same seed / kind / tone / role as the speech).
static func subtitle_for(b: Dictionary) -> Dictionary:
	return VoiceData.subtitle(b["seed"], b["kind"], b["tone"], b["role"], b["weak"] if b["kind"] == "struggle" else null)


func _is_active(id: Variant) -> bool:
	for a in active:
		if a["id"] == id:
			return true
	return false


## One tick. ctx: {now, player {x,y}, people [snapshot dicts], fear, enabled, length_fn Callable(seed, kind, mood, role, weak)->s,
## restrained id}. Returns {barks: [...], stop: [ids]}.
func step(ctx: Dictionary) -> Dictionary:
	var res := {"barks": [], "stop": []}
	var now: float = float(ctx.get("now", 0.0))
	var people: Array = ctx.get("people", [])
	var pl: Dictionary = ctx.get("player", {"x": 0.0, "y": 0.0})
	var fear: float = float(ctx.get("fear", 0.0))
	var enabled: bool = ctx.get("enabled", true) != false
	var first: bool = not init
	init = true
	active = active.filter(func(a): return a["end"] > now)
	starts = starts.filter(func(t): return t > now - 1.0)
	if now < last_now:
		active = []
		starts = []
	last_now = now
	var spike := false
	if fear - last_fear >= ALARM_JUMP and now - fear_at > ALARM_WINDOW:
		spike = true
		fear_at = now
	last_fear = fear
	var by_id := {}
	for p in people:
		by_id[p["id"]] = p
	var seen := {}
	var cands: Array = []
	for p in people:
		seen[p["id"]] = true
		var vv: Variant = v.get(p["id"])
		var fresh: bool = vv == null
		if fresh:
			vv = {"key": id_num(p["id"]), "mode": p["mode"], "wary": is_wary(p), "nextAt": 0.0, "lastKind": "", "lastDe": "", "n": 0, "pend": null, "pendUntil": 0.0, "aloneAt": now + 4.0 + 20.0 * unit(seed, id_num(p["id"]), 1)}
			v[p["id"]] = vv
		var prev_mode: String = vv["mode"]
		var prev_wary: bool = vv["wary"]
		vv["mode"] = p["mode"]
		vv["wary"] = is_wary(p)
		if silent(p) or (p["mode"] == "grapple" and weak_of(p) >= 1.0 - STRUGGLE_EMPTY):
			vv["pend"] = null
			if _is_active(p["id"]):
				res["stop"].append(p["id"])
				active = active.filter(func(a): return a["id"] != p["id"])
			continue
		if first or fresh or not enabled:
			vv["pend"] = null
			continue
		var dist: float = _hypot(float(p["x"]) - float(pl["x"]), float(p["y"]) - float(pl["y"]))
		var ev: Variant = null
		if p["mode"] == "startle" and prev_mode != "startle":
			ev = "startle" if p.get("bumping", false) else "notice"
		elif p["mode"] == "flee" and prev_mode != "flee":
			ev = "flee"
		elif p["mode"] == "cower" and prev_mode != "cower":
			ev = "cower"
		elif p["mode"] == "grapple" and prev_mode != "grapple":
			ev = "struggle"
		elif p["mode"] == "path" and (prev_mode == "flee" or prev_mode == "cower" or prev_mode == "startle" or prev_mode == "grapple"):
			ev = "relief"
		elif p["mode"] == "path" and vv["wary"] and not prev_wary and prev_mode == "path":
			ev = "notice"
		if ev != null:
			vv["pend"] = ev
			vv["pendUntil"] = now + (RELIEF_TTL if ev == "relief" else PENDING_TTL)
		if vv["pend"] == null and calm(p) and dist <= RANGE:
			if spike and dist <= DAY_RANGE:
				vv["pend"] = "alarm"
				vv["pendUntil"] = now + PENDING_TTL
			else:
				for q in people:
					if q["mode"] != "fed":
						continue
					var k := "%s:%s" % [str(p["id"]), str(q["id"])]
					if bodies.has(k):
						continue
					if _hypot(float(q["x"]) - float(p["x"]), float(q["y"]) - float(p["y"])) <= BODY_SEEN:
						bodies[k] = true
						vv["pend"] = "alarm"
						vv["pendUntil"] = now + PENDING_TTL
						break
		if vv["pend"] == null and now >= vv["nextAt"] and dist <= RANGE:
			if p["mode"] == "grapple":
				vv["pend"] = "struggle"
			elif p["mode"] == "flee" and unit(seed, vv["key"], vv["n"] + 11) < 0.7:
				vv["pend"] = "flee"
			elif p["mode"] == "cower":
				vv["pend"] = "cower"
			if vv["pend"] != null:
				vv["pendUntil"] = now + PENDING_TTL
		if vv["pend"] != null and now > vv["pendUntil"]:
			vv["pend"] = null
		if vv["pend"] != null and dist <= RANGE:
			var last_calm: bool = vv["lastKind"] == "daytalk" or vv["lastKind"] == "hum" or vv["lastKind"] == ""
			if now >= vv["nextAt"] or (FEAR_KIND.has(vv["pend"]) and last_calm):
				var pk0 := kind_for(p, vv["pend"])
				cands.append({"p": p, "v": vv, "kind": pk0, "dist": dist, "prio": PRIO[pk0] - dist * 0.5, "chatKind": null})
			continue
		var guard := is_guard(p)
		if not calm(p) or dist > (RANGE if guard else DAY_RANGE) or now < vv["nextAt"]:
			continue
		var partner: Variant = by_id.get(p["chat_partner"]) if p.get("chat_partner") != null else null
		if partner != null and not silent(partner) and partner.get("chat_partner") != null and partner["chat_partner"] == p["id"]:
			var pk := "%s|%s" % [str(p["id"]), str(partner["id"])] if p["id"] < partner["id"] else "%s|%s" % [str(partner["id"]), str(p["id"])]
			var pr: Variant = pair.get(pk)
			var mine: bool = (pr["last"] != p["id"] and now >= pr["end"] + 0.4) if pr != null else id_num(p["id"]) <= id_num(partner["id"])
			if mine and not _is_active(partner["id"]):
				cands.append({"p": p, "v": vv, "kind": "daytalk", "dist": dist, "prio": PRIO["daytalk"] - dist * 0.5, "chatKind": pk})
		elif p.get("chat_partner") == null and now >= vv["aloneAt"]:
			var roll := unit(seed, vv["key"], vv["n"] * 13 + 5)
			var ak: String = ("guardcall" if roll < 0.55 else "daytalk") if guard else ("hum" if roll < 0.4 else "daytalk")
			cands.append({"p": p, "v": vv, "kind": ak, "dist": dist, "prio": PRIO[ak] - dist * 0.5 - 5.0, "chatKind": null, "alone": true, "guard": guard})
	for k in v.keys():
		if not seen.has(k):
			v.erase(k)
	# stable sort: priority desc, then id
	cands.sort_custom(func(a, b):
		if a["prio"] != b["prio"]:
			return a["prio"] > b["prio"]
		return id_num(a["p"]["id"]) < id_num(b["p"]["id"]))
	for c in cands:
		if starts.size() >= MAX_STARTS or active.size() >= MAX_ACTIVE:
			break
		if _is_active(c["p"]["id"]):
			continue
		var vv: Dictionary = c["v"]
		var role := role_of(c["p"])
		var tone: String = tone_for(c["kind"], fear)
		var weak: float = weak_of(c["p"]) if c["kind"] == "struggle" else 0.0
		var restrained: bool = c["kind"] == "struggle" and ctx.get("restrained") != null and ctx["restrained"] == c["p"]["id"]
		var sd := 0
		var sub: Variant = null
		for t in 12:
			sd = hash2(vv["key"] ^ seed, vv["n"] * 16 + t + 1)
			var s := VoiceData.subtitle(sd, c["kind"], tone, role, weak if c["kind"] == "struggle" else null)
			if s["de"] != vv["lastDe"]:
				sub = s
				break
		if sub == null:
			vv["pend"] = null
			vv["n"] += 1
			vv["nextAt"] = now + 2.0
			continue
		var mood := mood_for(c["kind"], tone, weak)
		var ln: float = EST_LEN
		if ctx.get("length_fn") is Callable:
			ln = float((ctx["length_fn"] as Callable).call(sd, c["kind"], mood, role, weak if c["kind"] == "struggle" else null))
		var cd_kind: String = "chat" if c["kind"] == "daytalk" and c["chatKind"] != null else c["kind"]
		vv["n"] += 1
		vv["lastKind"] = c["kind"]
		vv["lastDe"] = sub["de"]
		vv["pend"] = null
		vv["nextAt"] = now + maxf(0.3, ln) + cooldown(vv, cd_kind, vv["n"], weak)
		if c.get("alone", false):
			vv["aloneAt"] = (now + 12.0 + 14.0 * unit(seed, vv["key"], vv["n"] * 3 + 9)) if c["guard"] else (now + 20.0 + 25.0 * unit(seed, vv["key"], vv["n"] * 3 + 9))
		if c["chatKind"] != null:
			pair[c["chatKind"]] = {"last": c["p"]["id"], "end": now + maxf(0.3, ln)}
		starts.append(now)
		active.append({"id": c["p"]["id"], "end": now + maxf(0.3, ln)})
		total += 1
		recent += 1
		res["barks"].append({
			"id": c["p"]["id"], "x": float(c["p"]["x"]), "y": float(c["p"]["y"]), "dist": c["dist"], "kind": c["kind"], "seed": sd,
			"tone": tone, "mood": mood, "gain": float(GAIN.get(c["kind"], 0.6)) * (RESTRAIN_GAIN if restrained else 1.0),
			"loud": FEAR_KIND.has(c["kind"]), "role": role, "voiceSeed": vv["key"], "len": ln, "weak": weak, "restrained": restrained})
	return res


## Snapshot of the live people for step() (what game.js hands the JS module).
static func people_snapshot(people: Array) -> Array:
	var out: Array = []
	for p in people:
		out.append({
			"id": p.id, "x": p.x, "y": p.y, "mode": p.mode, "wary": p.wary, "bumping": p.bumping, "role": p.role,
			"sched_role": p.sched["role"] if p.sched != null else null, "pool": p.pool, "left": p.left,
			"chat_partner": p.chat["partner"] if p.chat != null else null})
	return out
