class_name Listen
extends RefCounted
## Ports js/listen.js: listening at windows (find the window, who is inside, what is said, subtitles). Pure logic; game.gd
## feeds it the world, player and people and plays the speech.

const REACH := 1.2
const FACE := 0.9
const START_SPEED := 1.0
const STOP_SPEED := 1.8
const MOVE_K := 0.5
const MAX_SPEAKERS := 2
const LP_GLASS := 1200.0
const LP_DARK := 600.0
const SUB_DIST := 1.2
const SUB_LIT := 0.15
const SUB_FADE := 0.6
const MUFFLED := "(muffled talking)"
const KINDS_CALM := ["chat", "chat", "question", "laugh", "greet"]
const KINDS_WORRIED := ["murmur", "question", "chat"]
const KINDS_WHISPER := ["murmur", "murmur", "chat"]
const KINDS_WARM := ["chat", "laugh", "question", "chat"]
const KINDS_NEUTRAL := ["chat", "question", "chat"]
const KINDS_CURT := ["argue", "chat", "argue"]
const KINDS_HUSHED := ["murmur", "chat", "question"]

var active: bool = false
var win: Variant = null
var count: int = 0
var silent: bool = false
var mood: String = "calm"
var turn: int = 0
var next_at: float = 0.0
var speaker: int = -1
var cur: Variant = null
var sub: Variant = null
var sub_id: int = 0
var lp_hz: float = LP_GLASS


static func _hypot(x: float, y: float) -> float:
	return sqrt(x * x + y * y)


## The window the player could listen at: {cx, cy, x, y, ix, iy, dist, zone, lit} or null. p: {x, y, angle}.
static func find_window(world: World, p: Dictionary, reach: float = REACH) -> Variant:
	if world.kind_at(p["x"], p["y"]) != "outdoor":
		return null
	var px: int = int(floor(p["x"]))
	var py: int = int(floor(p["y"]))
	var r: int = int(ceil(reach))
	var best: Variant = null
	for cy in range(py - r, py + r + 1):
		for cx in range(px - r, px + r + 1):
			if world.tile_at(cx, cy) != "w":
				continue
			var wx: float = cx + 0.5
			var wy: float = cy + 0.5
			var dx: float = wx - p["x"]
			var dy: float = wy - p["y"]
			var d: float = _hypot(dx, dy)
			if d > reach or (best != null and d >= best["dist"]):
				continue
			var da: float = atan2(dy, dx) - float(p.get("angle", 0.0))
			da = atan2(sin(da), cos(da))
			if absf(da) > FACE and d > 0.6:
				continue
			var sx: int = (1 if dx >= 0.0 else -1) if absf(dx) >= absf(dy) else 0
			var sy: int = 0 if sx != 0 else (1 if dy >= 0.0 else -1)
			var ix: float = wx + sx
			var iy: float = wy + sy
			if world.kind_at(ix, iy) != "indoor":
				continue
			var zone: Variant = world.zone_at(ix, iy)
			if zone == "":
				zone = null
			var lit: float = maxf(world.light_at(wx, wy), world.light_at(ix, iy))
			best = {"cx": cx, "cy": cy, "x": wx, "y": wy, "ix": ix, "iy": iy, "dist": d, "zone": zone, "lit": lit}
	return best


## A lit window within reach (no facing needed): the first-time hint.
static func near_lit_window(world: World, p: Dictionary, reach: float = 2.5) -> bool:
	if world.kind_at(p["x"], p["y"]) != "outdoor":
		return false
	var r: int = int(ceil(reach))
	for cy in range(int(floor(p["y"])) - r, int(floor(p["y"])) + r + 1):
		for cx in range(int(floor(p["x"])) - r, int(floor(p["x"])) + r + 1):
			if world.tile_at(cx, cy) != "w":
				continue
			if _hypot(cx + 0.5 - p["x"], cy + 0.5 - p["y"]) > reach:
				continue
			if world.light_at(cx + 0.5, cy + 0.5) > 0.15:
				return true
	return false


## People inside the zone behind the window and not busy being fed: [{id, x, y, noticed, role}]. people: snapshot dicts
## (Barks.people_snapshot).
static func insiders(world: World, people: Array, w: Variant) -> Array:
	var out: Array = []
	if w == null:
		return out
	for q in people:
		if q["mode"] == "fed" or q["mode"] == "grapple":
			continue
		if world.kind_at(q["x"], q["y"]) != "indoor":
			continue
		if w["zone"] != null and world.zone_at(q["x"], q["y"]) != w["zone"]:
			continue
		var noticed: bool = q["mode"] == "startle" or q["mode"] == "flee" or q["mode"] == "cower" or q["mode"] == "dazed" or float(q.get("wary", 0.0)) > 0.0
		out.append({"id": q["id"], "x": q["x"], "y": q["y"], "noticed": noticed, "role": Barks.role_of(q)})
	return out


static func subtitle_clear(dist: float, lit: float) -> bool:
	return dist <= SUB_DIST and lit > SUB_LIT


## {de, en, muffled} for a line; the muffled marker unless close to a lit window.
static func subtitle_for(seed: Variant, kind: String, mood_s: String, dist: float, lit: float) -> Dictionary:
	if not subtitle_clear(dist, lit):
		return {"de": MUFFLED, "en": "", "muffled": true}
	var t := VoiceData.subtitle(seed, kind, mood_s)
	return {"de": t["de"], "en": t["en"], "muffled": false}


## Opacity 0..1 of a subtitle at time now.
static func sub_alpha(s: Variant, now: float) -> float:
	if s == null:
		return 0.0
	var over: float = now - float(s["end"])
	if over <= 0.0:
		return 1.0
	return maxf(0.0, 1.0 - over / SUB_FADE)


static func mood_for(fear: float) -> String:
	return "whisper" if fear >= 8.0 else ("worried" if fear >= 4.0 else "calm")


static func conversation_kinds(conv: Variant, mood_s: String) -> Array:
	if mood_s == "worried":
		return KINDS_WORRIED
	if mood_s == "whisper":
		return KINDS_WHISPER
	if conv == null:
		return KINDS_CALM
	match conv["mood"]:
		"warm": return KINDS_WARM
		"curt": return KINDS_CURT
		"hushed": return KINDS_HUSHED
	return KINDS_NEUTRAL


func stop_cur() -> void:
	if cur is Dictionary and (cur as Dictionary).get("stop") is Callable:
		(cur["stop"] as Callable).call()
	cur = null
	sub = null


## One tick. ctx: {now, held, holding, speed, world, player {x,y,angle}, people (snapshots), fear, speak Callable(opts)->handle|null,
## speak_length Callable(seed, kind, mood, voice)->s, voice_for Callable(person, seed), pan Callable(x, y), on_change Callable(active, info),
## on_subtitle Callable(sub, who), conversation_for Callable(id)->{partner, kind, mood}|null}.
func step(ctx: Dictionary) -> Listen:
	var was_active: bool = active
	var speed: float = float(ctx.get("speed", 0.0))
	var w: Variant = null
	if ctx.get("held", false) and not ctx.get("holding", false):
		w = find_window(ctx["world"], ctx["player"], REACH)
		if w != null and not was_active and speed > START_SPEED:
			w = null
		if w != null and was_active and speed > STOP_SPEED:
			w = null
	if w == null:
		if was_active:
			stop_cur()
			active = false
			win = null
			count = 0
			if ctx.get("on_change") is Callable:
				(ctx["on_change"] as Callable).call(false, null)
		return self
	var same: bool = win != null and win["cx"] == w["cx"] and win["cy"] == w["cy"]
	win = w
	active = true
	var ins := insiders(ctx["world"], ctx["people"], w)
	count = ins.size()
	silent = false
	for q in ins:
		if q["noticed"]:
			silent = true
	mood = mood_for(float(ctx.get("fear", 0.0)))
	lp_hz = LP_GLASS if w["lit"] > 0.15 else LP_DARK
	var now: float = float(ctx.get("now", 0.0))
	if not was_active or not same:
		next_at = now + 0.6
		turn = 0
		speaker = -1
		if ctx.get("on_change") is Callable:
			(ctx["on_change"] as Callable).call(true, {"count": ins.size(), "zone": w["zone"], "lit": w["lit"]})
	if sub != null and now > float(sub["end"]) + SUB_FADE:
		sub = null
	if silent or ins.is_empty():
		stop_cur()
		return self
	if now < next_at or not (ctx.get("speak") is Callable):
		return self
	ins.sort_custom(func(a, b): return _hypot(a["x"] - w["x"], a["y"] - w["y"]) < _hypot(b["x"] - w["x"], b["y"] - w["y"]))
	var conv: Variant = null
	if ctx.get("conversation_for") is Callable:
		conv = (ctx["conversation_for"] as Callable).call(ins[0]["id"])
	var pool: Array = ins.slice(0, MAX_SPEAKERS)
	if conv != null:
		var mate: Variant = null
		for i in range(1, ins.size()):
			if ins[i]["id"] == conv["partner"]:
				mate = ins[i]
				break
		if mate != null:
			pool = [ins[0], mate]
		else:
			conv = null
	speaker = (speaker + 1) % pool.size() if pool.size() > 1 else 0
	var who: Dictionary = pool[speaker]
	var seed: int = Barks.hash2(Barks.id_num(who["id"]), turn)
	var kinds := conversation_kinds(conv, mood)
	var kind: String
	if conv != null and conv["kind"] == "hello":
		kind = "greet"
	elif turn == 0 and pool.size() > 1 and conv == null:
		kind = "greet"
	else:
		kind = kinds[seed % kinds.size()]
	var d: float = _hypot(who["x"] - w["x"], who["y"] - w["y"]) + w["dist"]
	var gain: float = maxf(0.15, minf(1.0, 1.0 / (1.0 + d * 0.18)))
	var mood_now := mood
	stop_cur()
	var voice: Variant = null
	if ctx.get("voice_for") is Callable:
		voice = (ctx["voice_for"] as Callable).call(who, seed)
	var pan: float = (ctx["pan"] as Callable).call(w["x"], w["y"]) if ctx.get("pan") is Callable else 0.0
	cur = (ctx["speak"] as Callable).call({"voice": voice, "seed": seed, "kind": kind, "mood": mood_now, "pan": pan, "lpHz": lp_hz, "gain": gain})
	var ln := 1.2
	if cur is Dictionary and float((cur as Dictionary).get("end", 0.0)) > 0.0:
		ln = float(cur["end"])
	elif ctx.get("speak_length") is Callable:
		ln = float((ctx["speak_length"] as Callable).call(seed, kind, mood_now, voice))
	var two: bool = pool.size() > 1
	var pause: float = (0.35 if two else 1.6) + (float(Barks.hash2(seed, 99) % 100) / 100.0) * (0.9 if two else 2.4)
	var s := subtitle_for(seed, kind, mood_now, w["dist"], w["lit"])
	s["speaker"] = who["id"]
	s["kind"] = kind
	s["mood"] = mood_now
	s["start"] = now
	s["end"] = now + maxf(0.3, ln)
	sub = s
	sub_id += 1
	if ctx.get("on_subtitle") is Callable:
		(ctx["on_subtitle"] as Callable).call(s, who)
	next_at = now + maxf(0.3, ln) + pause
	turn += 1
	return self
