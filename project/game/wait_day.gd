class_name WaitDay
extends RefCounted
## "Wait out the day": the player sits on a roofed cell in daylight and fast-forwards to dusk (docs/ROGUELIKE.md, Core rules).
## Self-contained and deterministic: all randomness comes from the Rng passed in, time from step(dt) calls. Sleeping at a rest spot
## is the separate skip `sleep_at`. Heat is only RETURNED (outcome.heat_add); the trek flow stores it.
##
## Interface: WaitDay.new(world, people, critters, rng, params); start(player_pos, blood, drain_rate, hides, opts); step(dt) -> outcome;
## resume(); run_to_end(through_interrupts); sleep_at(spot, heat) -> outcome. `people` / `critters` may be null.
## Tunables: data/rogue/wait.json, overridden per key by `params`. Extra param "emitter": Callable(world, x, y, t, opts), default none;
## pass `sonar.emit_sound` to hear faint pulses (tests pass a stub).
##
## drain_rate = blood per game second at normal (night) drain. Waiting drains drain_rate * wait_drain_mul (0.4), sleeping * sleep_drain_mul (0.15).
## step(dt): dt is real seconds, sim time = dt * speed, simulated in fixed coarse chunks of step_sec (1.5 s of game time) so results do not
## depend on how dt is sliced. People/Schedule are driven by an adapter: the day is mapped onto the schedule's 0..1 clock (nightFrac =
## day_t / day_sec) and People.update is sub-stepped at <= people_sub (it clamps dt to 0.1). The player is NOT passed to People (no
## flight / bump logic): discovery is rolled here instead.
##
## Outcome: {result: "running"|"dusk"|"interrupted"|"noticed"|"withered", state (same as result), elapsed (game s), blood_after, heat_add,
## events[], day_left, by (person id, noticed only), reason (interrupted only: occupant_in_room | occupant_near | guard_near)}.
## heat_add is 1 on the first non-running outcome of a day and 0 on later ones (after resume()) so the flow can just add it.

const DATA_PATH := "res://data/rogue/wait.json"
const GUARD_ROLES := ["guard", "hunter", "dog"]
const DEFAULTS := {
	"speed": 8.0, "step_sec": 1.5, "day_sec": 360.0, "wait_drain_mul": 0.4, "sleep_drain_mul": 0.15, "people_sub": 0.1, "hear_range": 7.0,
	"listen_period": 1.6, "listen_idle_mul": 3.0, "listen_strength": 0.12, "listen_range": 3.0, "near_dist": 2.5, "guard_dist": 6.0,
	"room_max_cells": 900, "see_dist": 6.0, "day_sight_bonus": 1.25, "notice_rate": 0.25, "hide_mul": 0.2, "dark_mul": 0.5,
	"sleep_discover": 0.2, "sleep_heat_k": 0.25, "heat_add": 1, "max_events": 256,
}

static var _cache: Dictionary = {}

var world = null
var people: People = null
var critters: Critters = null
var rng: Rng = null
var p: Dictionary = {}
var emitter: Callable = Callable()

var state: String = "idle"  # idle | running | interrupted | noticed | withered | dusk
var player_pos: Vector2 = Vector2.ZERO
var blood: float = 0.0
var drain_rate: float = 0.0
var hidden: bool = false
var dark: bool = false
var elapsed: float = 0.0
var day_t: float = 0.0
var events: Array = []
var by: int = -1
var reason: String = ""
var heat_charged: bool = false
var room: Dictionary = {}
var zone: Variant = null
var _acc: float = 0.0
var _near: Dictionary = {}
var _next_listen: Dictionary = {}


static func load_params() -> Dictionary:
	if _cache.is_empty():
		_cache = DEFAULTS.duplicate()
		var f := FileAccess.open(DATA_PATH, FileAccess.READ)
		if f != null:
			var d: Variant = JSON.parse_string(f.get_as_text())
			if d is Dictionary:
				for k in d:
					_cache[k] = d[k]
	return _cache


func _init(w = null, ppl: People = null, crit: Critters = null, rng_: Rng = null, params: Dictionary = {}) -> void:
	world = w
	people = ppl
	critters = crit
	rng = rng_ if rng_ != null else Rng.new(1.0)
	p = load_params().duplicate()
	for k in params:
		if k == "emitter":
			emitter = params[k]
		else:
			p[k] = params[k]


## Begin a wait. hides: bool, or an Array of hide cells ([x, y] / Vector2i / {x, y}) the player stands in one of.
## opts: {dark: bool (dark corner), day_sec, day_t (clock already elapsed), zone: Rect2 in cells}.
func start(pos: Vector2, blood_: float, drain_rate_: float, hides_: Variant = false, opts: Dictionary = {}) -> void:
	player_pos = pos
	blood = blood_
	drain_rate = drain_rate_
	dark = bool(opts.get("dark", false))
	hidden = _in_hides(hides_, pos)
	if opts.has("day_sec"):
		p["day_sec"] = float(opts["day_sec"])
	day_t = float(opts.get("day_t", 0.0))
	zone = opts.get("zone")
	elapsed = 0.0
	events = []
	by = -1
	reason = ""
	heat_charged = false
	_acc = 0.0
	_near = {}
	_next_listen = {}
	room = _flood_room(pos)
	state = "running"


func _in_hides(h: Variant, pos: Vector2) -> bool:
	if h is bool:
		return h
	if not (h is Array):
		return false
	var c := Vector2i(int(floor(pos.x)), int(floor(pos.y)))
	for e in h:
		if e is Vector2i and e == c:
			return true
		if e is Vector2 and Vector2i(int(floor(e.x)), int(floor(e.y))) == c:
			return true
		if e is Array and e.size() >= 2 and int(floor(float(e[0]))) == c.x and int(floor(float(e[1]))) == c.y:
			return true
		if e is Dictionary and int(floor(float(e.get("x", -1)))) == c.x and int(floor(float(e.get("y", -1)))) == c.y:
			return true
	return false


## Cells reachable from the player's cell without crossing a wall or closed door (the player's "room"), capped at room_max_cells.
func _flood_room(pos: Vector2) -> Dictionary:
	var seen := {}
	if world == null:
		return seen
	var w: int = world.width
	var cap: int = int(p["room_max_cells"])
	var q: Array = [Vector2i(int(floor(pos.x)), int(floor(pos.y)))]
	seen[q[0].y * w + q[0].x] = true
	var qi := 0
	while qi < q.size() and seen.size() < cap:
		var c: Vector2i = q[qi]
		qi += 1
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if world.cell_solid(n.x, n.y):
				continue
			var k: int = n.y * w + n.x
			if not seen.has(k):
				seen[k] = true
				q.append(n)
	return seen


func _in_room(x: float, y: float) -> bool:
	return room.has(int(floor(y)) * world.width + int(floor(x)))


func resume() -> bool:
	if state != "interrupted":
		return false
	state = "running"
	reason = ""
	return true


func _outcome() -> Dictionary:
	var done: bool = state != "running" and state != "idle"
	var heat := 0
	if done and not heat_charged:
		heat = int(p["heat_add"])
		heat_charged = true
	var st: String = "running" if state == "idle" else state
	var o := {
		"result": st, "state": st, "elapsed": elapsed, "blood_after": blood, "heat_add": heat, "events": events,
		"day_left": maxf(0.0, float(p["day_sec"]) - day_t),
	}
	if state == "noticed":
		o["by"] = by
	if state == "interrupted":
		o["reason"] = reason
	return o


func _log(e: Dictionary) -> void:
	e["t"] = day_t
	if events.size() < int(p["max_events"]):
		events.append(e)


## Advance by dt real seconds (sim time dt * speed). Stops at the first terminal or interrupting event; call resume() to continue.
func step(dt: float) -> Dictionary:
	if state != "running":
		return _outcome()
	_acc += dt * float(p["speed"])
	while state == "running":
		var chunk: float = minf(float(p["step_sec"]), maxf(0.0, float(p["day_sec"]) - day_t))
		if _acc + 1e-9 < chunk:
			break
		_acc = maxf(0.0, _acc - chunk)
		_advance(chunk)
	return _outcome()


## Headless helper: step until the wait is over. through_interrupts auto-resumes interrupts. Returns the final outcome.
func run_to_end(through_interrupts: bool = false) -> Dictionary:
	var o := {}
	var guard := 0
	while guard < 1000000:
		guard += 1
		o = step(float(p["step_sec"]) / float(p["speed"]))
		if o["result"] == "interrupted" and through_interrupts:
			resume()
			continue
		if o["result"] != "running":
			break
	return o


func _advance(dt: float) -> void:
	day_t += dt
	elapsed += dt
	blood = maxf(0.0, blood - drain_rate * float(p["wait_drain_mul"]) * dt)
	if critters != null:
		critters.step(player_pos, dt, true)
	_step_people(dt)
	_listen()
	if blood <= 0.0:
		state = "withered"
		_log({"type": "withered"})
		return
	if _discover(dt):
		return
	if day_t + 1e-9 >= float(p["day_sec"]):
		state = "dusk"
		_log({"type": "dusk"})
		return
	_check_interrupts()


## Adapter: map the day onto the schedule clock and sub-step People.update (which clamps dt to 0.1). No player in the ctx.
func _step_people(dt: float) -> void:
	if people == null:
		return
	var n: int = maxi(1, int(ceil(dt / float(p["people_sub"]) - 1e-9)))
	var sub: float = dt / n
	var day_sec: float = float(p["day_sec"])
	for i in n:
		var f: float = clampf((day_t - dt + sub * (i + 1)) / day_sec, 0.0, 1.0)
		people.update(world, sub, {"nightFrac": f, "nightSec": day_sec, "fear": 0.0})


func _listen() -> void:
	if people == null:
		return
	var hr: float = float(p["hear_range"])
	for q in people.people:
		var d: float = Vector2(q.x, q.y).distance_to(player_pos)
		if d > hr or q.mode == "fed" or q.mode == "grapple":
			continue
		if day_t < float(_next_listen.get(q.id, 0.0)):
			continue
		var moving: bool = q.state == "walk" or q.mode == "flee"
		var per: float = float(p["listen_period"]) * (1.0 if moving else float(p["listen_idle_mul"]))
		_next_listen[q.id] = day_t + per * (0.75 + 0.5 * rng.next())
		var opts := {"kind": "listen", "strength": float(p["listen_strength"]), "range": float(p["listen_range"]), "z": 0.4, "visRays": 90}
		_log({"type": "listen", "person": q.id, "x": q.x, "y": q.y, "dist": d, "moving": moving})
		if emitter.is_valid():
			emitter.call(world, q.x, q.y, day_t, opts)


## Visibility multiplier for the player: 1 in the open, reduced when hidden / in a dark corner.
func vis_mul() -> float:
	var m := 1.0
	if hidden:
		m *= float(p["hide_mul"])
	if dark:
		m *= float(p["dark_mul"])
	return m


## Asleep in bed: occupants on a "sleep" stop do not notice anyone.
func _asleep(q: People.Person) -> bool:
	if q.sched == null or not q.seated:
		return false
	var si: int = int(q.sched["si"])
	return si >= 0 and si < q.sched["stops"].size() and q.sched["stops"][si]["act"] == "sleep"


func _discover(dt: float) -> bool:
	if people == null:
		return false
	var see: float = float(p["see_dist"]) * float(p["day_sight_bonus"])
	var m: float = vis_mul()
	for q in people.people:
		if q.mode == "fed" or q.mode == "grapple" or q.mode == "dazed" or _asleep(q):
			continue
		var d: float = Vector2(q.x, q.y).distance_to(player_pos)
		if d > see or not People.segment_clear(world, q.x, q.y, player_pos.x, player_pos.y):
			continue
		var prob: float = minf(1.0, float(p["notice_rate"]) * dt * (0.3 + (1.0 - d / see)) * m)
		if rng.next() < prob:
			state = "noticed"
			by = q.id
			_log({"type": "noticed", "by": q.id, "dist": d})
			return true
	return false


func _is_guard(q: People.Person) -> bool:
	return q.watch or GUARD_ROLES.has(q.role) or GUARD_ROLES.has(q.archetype)


func _check_interrupts() -> void:
	if people == null:
		return
	var has_zone: bool = zone is Rect2
	for q in people.people:
		var d: float = Vector2(q.x, q.y).distance_to(player_pos)
		var why := ""
		if _in_room(q.x, q.y) or (has_zone and (zone as Rect2).has_point(Vector2(q.x, q.y))):
			why = "occupant_in_room"
		elif d <= float(p["near_dist"]):
			why = "occupant_near"
		elif _is_guard(q) and d <= float(p["guard_dist"]):
			why = "guard_near"
		var was: bool = _near.get(q.id, false)
		_near[q.id] = why != ""
		if why != "" and not was and state == "running":
			state = "interrupted"
			reason = why
			_log({"type": "interrupt", "reason": why, "person": q.id, "dist": d})


## Sleep at a rest spot: skip the rest of the day at sleep_drain_mul drain with one discovery roll by the spot's safety (0..1, higher is
## safer): p = sleep_discover * (1 - safety) * (1 + heat * sleep_heat_k). Noticed ends the sleep part-way (by = -1). `spot`: {safety, x?, y?}.
## Call start() first (blood, drain_rate, and day_t for a sleep that begins mid-day).
func sleep_at(spot: Dictionary, heat: float = 0.0) -> Dictionary:
	if state == "idle":
		start(Vector2(float(spot.get("x", 0.0)), float(spot.get("y", 0.0))), 0.0, 0.0)
	var left: float = maxf(0.0, float(p["day_sec"]) - day_t)
	var rate: float = drain_rate * float(p["sleep_drain_mul"])
	var safety: float = clampf(float(spot.get("safety", 0.5)), 0.0, 1.0)
	var prob: float = clampf(float(p["sleep_discover"]) * (1.0 - safety) * (1.0 + maxf(0.0, heat) * float(p["sleep_heat_k"])), 0.0, 1.0)
	var span: float = left
	var found: bool = rng.next() < prob
	if found:
		span = left * rng.next()
	day_t += span
	elapsed += span
	blood = maxf(0.0, blood - rate * span)
	if blood <= 0.0:
		state = "withered"
		_log({"type": "withered"})
	elif found:
		state = "noticed"
		by = -1
		_log({"type": "noticed", "by": -1, "sleeping": true})
	else:
		state = "dusk"
		_log({"type": "dusk", "sleeping": true})
	return _outcome()
