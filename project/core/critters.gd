class_name Critters
extends RefCounted
## Lightweight animals (bats, rats, rabbits, deer ...) that are NOT People.Person figures. Pure core logic, deterministic from a seed
## (Rng = mulberry32). Critter state is never saved. Species live in data/rogue/critters.json.
## `world` is duck-typed: needs blocks(x, y, r), width, height. `sonar` is duck-typed: needs emit_sound(world, x, y, t, opts).
##
## HUNTING API (what rogue_mode should call; all pure, deterministic):
##   step(player_pos, dt, is_day, loud := {}, sneak := false)  every tick. sneak = player is creeping or standing still (speed < SNEAK_SPEED
##       = 1.6 cells/s); scales every species' flee radius by its catchable.sneak_mult (0.25-0.4). Old 4-arg calls behave as before.
##   on_ping(player_pos, radius := PING_FREEZE_RADIUS) -> int   when the player pings. Awake critters within ~4 cells freeze for ~1 s
##       (startle-freeze) instead of bolting. Call it INSTEAD of hear() for the player's own ping; keep hear() / the step `loud` dict for
##       really loud events (shouts, doors, big sounds): hear() cancels freeze and makes critters flee as before.
##   lunge(player_pos, reach := LUNGE_REACH) -> Critter|null   when R is pressed: returns (and snaps to feedable range, 0.25 s lunge) the
##       nearest live, visible, line-of-sight critter within reach that is not fleeing at full speed (frozen, wandering, roosting, sleeping,
##       or tired all qualify). Then call feed(c) as usual. Null = nothing catchable, fall back to nearest_feedable().
## Fleeing speed = min(speed * catchable.flee_mult, 1.6 x PLAYER_SPEED); after catchable.tire_after s of fleeing it drops to tired_mult (0.6).
## "Rest" (roost / hide / sleep) applies when is_day == species.nocturnal: nocturnal species rest by day, day species rest at night.

const DATA_PATH := "res://data/rogue/critters.json"
const DEFAULT_CAP := 12
const BODY_R := 0.2
const FEED_REACH := 0.9
const PLAYER_SPEED := 3.0
const MAX_FLEE_RATIO := 1.6
const SNEAK_SPEED := 1.6
const PING_FREEZE_RADIUS := 4.0
const FREEZE_TIME := 1.0
const LUNGE_REACH := 2.0
const LUNGE_TIME := 0.25
const DEFAULT_CATCH := {"flee_mult": 1.5, "sneak_mult": 0.4, "tire_after": 4.0, "tired_mult": 0.6, "freeze_s": 1.0}

static var _table: Dictionary = {}
static var _cap: int = DEFAULT_CAP


class Critter:
	extends RefCounted
	var id: int = 0
	var species: String = ""
	var x: float = 0.0
	var y: float = 0.0
	var home_x: float = 0.0
	var home_y: float = 0.0
	## wander | flee | roost | hide | sleep (dead critters are removed from the live list).
	var state: String = "wander"
	var heading: float = 0.0
	var moving: bool = true
	var phase_t: float = 0.0
	var squeak_t: float = 0.0
	var alarm_t: float = 0.0
	## Startle-freeze time left (s): the critter stands still and does not flee while > 0.
	var freeze_t: float = 0.0
	## Seconds spent fleeing (stamina); recovers while not fleeing.
	var flee_t: float = 0.0
	var blood: int = 0
	var dead: bool = false
	## False while hidden (rats by day): not drawn, not echoed.
	var visible: bool = true


## A snapshot of a critter as a sonar ring crossed it (minimal People.Echo equivalent).
class Echo:
	extends RefCounted
	var critter_id: int = 0
	var species: String = ""
	var x: float = 0.0
	var y: float = 0.0
	var t: float = 0.0
	var strength: float = 1.0


var world = null
var rng: Rng = null
var critters: Array[Critter] = []
var echoes: Array[Echo] = []
var time: float = 0.0
var cap: int = DEFAULT_CAP
var eaten: int = 0
var _next_id: int = 1


func _init(w = null, seed_: float = 1.0) -> void:
	world = w
	rng = Rng.new(seed_)
	cap = species_cap()


static func _load() -> void:
	if not _table.is_empty():
		return
	var f := FileAccess.open(DATA_PATH, FileAccess.READ)
	if f == null:
		return
	var d: Variant = JSON.parse_string(f.get_as_text())
	if d is Dictionary:
		_table = d.get("species", {})
		_cap = int(d.get("cap", DEFAULT_CAP))


static func species_table() -> Dictionary:
	_load()
	return _table


static func species_cap() -> int:
	_load()
	return _cap


static func spec(species: String) -> Dictionary:
	_load()
	return _table.get(species, {})


## True when this species should be resting (roost / hide / sleep) right now.
static func resting(species: String, is_day: bool) -> bool:
	var s := spec(species)
	if s.is_empty():
		return false
	return is_day == bool(s["nocturnal"])


## Catchability tuning for a species (json "catchable" merged over DEFAULT_CATCH).
static func catch_tuning(species: String) -> Dictionary:
	var t: Dictionary = DEFAULT_CATCH.duplicate()
	var s := spec(species)
	var ov: Variant = s.get("catchable", {})
	if ov is Dictionary:
		for k in ov:
			t[k] = ov[k]
	return t


## Current fleeing speed (cells/s) of a critter: capped to 1.6x the player, slowed once tired.
static func flee_speed(c: Critter) -> float:
	var s := spec(c.species)
	var t := catch_tuning(c.species)
	var sp: float = minf(float(s["speed"]) * float(t["flee_mult"]), PLAYER_SPEED * MAX_FLEE_RATIO)
	if c.flee_t > float(t["tire_after"]):
		sp *= float(t["tired_mult"])
	return sp


## Place a critter at the centre of `cell`. Returns null for an unknown species, a blocked cell, or when the cap is reached.
func spawn(species: String, cell: Vector2i, is_day: bool = false) -> Critter:
	var s := spec(species)
	if s.is_empty() or critters.size() >= cap:
		return null
	var cx: float = cell.x + 0.5
	var cy: float = cell.y + 0.5
	if world != null and world.blocks(cx, cy, BODY_R):
		return null
	var c := Critter.new()
	c.id = _next_id
	_next_id += 1
	c.species = species
	c.x = cx
	c.y = cy
	c.home_x = cx
	c.home_y = cy
	c.blood = int(s["blood"])
	c.heading = rng.next() * TAU
	c.phase_t = 0.5 + rng.next() * 1.5
	var sq: Dictionary = s["squeak"]
	c.squeak_t = float(sq["interval"]) * (0.3 + rng.next() * 0.7)
	_apply_rest(c, is_day)
	critters.append(c)
	return c


## Scatter up to n critters of a species over random free cells (seeded). Returns how many were placed.
func populate(species: String, n: int, is_day: bool = false) -> int:
	var placed := 0
	var tries := 0
	while placed < n and tries < n * 30 and critters.size() < cap and world != null:
		tries += 1
		var cell := Vector2i(int(rng.next() * world.width), int(rng.next() * world.height))
		if spawn(species, cell, is_day) != null:
			placed += 1
	return placed


func _apply_rest(c: Critter, is_day: bool) -> void:
	var s := spec(c.species)
	if resting(c.species, is_day):
		c.state = String(s["rest"])
		c.visible = c.state != "hide"
	else:
		c.state = "wander"
		c.visible = true


func _try_move(c: Critter, ang: float, dist: float) -> bool:
	var dx: float = cos(ang) * dist
	var dy: float = sin(ang) * dist
	if world == null or not world.blocks(c.x + dx, c.y + dy, BODY_R):
		c.x += dx
		c.y += dy
		return true
	# slide along one axis
	if not world.blocks(c.x + dx, c.y, BODY_R):
		c.x += dx
		return true
	if not world.blocks(c.x, c.y + dy, BODY_R):
		c.y += dy
		return true
	return false


## Frighten critters within `radius` of (x, y) (a loud pulse): they flee for a few seconds. radius 0 = twice their flee radius x loudness.
func hear(x: float, y: float, loudness: float = 1.0, radius: float = 0.0) -> int:
	var n := 0
	for c in critters:
		var s := spec(c.species)
		var r: float = radius if radius > 0.0 else float(s["flee_radius"]) * 2.0 * loudness
		if c.state == "hide":
			continue
		if Vector2(c.x - x, c.y - y).length() <= r:
			c.alarm_t = 3.0
			c.freeze_t = 0.0
			if c.state == "roost" or c.state == "sleep":
				c.state = "flee"
			n += 1
	return n


## Advance all critters. player_pos is a Vector2 (cell units). loud (optional) is {x, y, strength} of a loud pulse this tick.
func step(player_pos: Vector2, dt: float, is_day: bool, loud: Dictionary = {}, sneak: bool = false) -> void:
	time += dt
	if not loud.is_empty():
		hear(float(loud["x"]), float(loud["y"]), float(loud.get("strength", 1.0)))
	for c in critters:
		var s := spec(c.species)
		var pd := Vector2(c.x - player_pos.x, c.y - player_pos.y)
		var dist: float = pd.length()
		var tune := catch_tuning(c.species)
		var fr: float = float(s["flee_radius"]) * (float(tune["sneak_mult"]) if sneak else 1.0)
		var frozen: bool = c.freeze_t > 0.0
		var frightened: bool = (dist < fr and not frozen) or c.alarm_t > 0.0
		c.freeze_t = maxf(0.0, c.freeze_t - dt)
		c.alarm_t = maxf(0.0, c.alarm_t - dt)
		if frozen and c.alarm_t <= 0.0:
			c.moving = false
			c.flee_t = maxf(0.0, c.flee_t - dt * 0.5)
			if c.state == "flee":
				c.state = "wander"
			if c.state == "wander":
				continue
		c.squeak_t -= dt
		if resting(c.species, is_day):
			if c.state == "hide":
				c.visible = false
				continue
			if c.state == "roost" or c.state == "sleep":
				# wake only when the player is very close or something was heard
				if dist < float(s["rest_wake_radius"]) or c.alarm_t > 0.0:
					c.state = "flee"
				else:
					continue
			elif c.state != "flee":
				# time to settle: walk home, then rest
				var hd := Vector2(c.home_x - c.x, c.home_y - c.y)
				if hd.length() < 0.3:
					c.x = c.home_x
					c.y = c.home_y
					c.state = String(s["rest"])
					c.visible = c.state != "hide"
					continue
				_try_move(c, hd.angle(), minf(float(s["speed"]) * dt, hd.length()))
				continue
		else:
			if c.state == "roost" or c.state == "hide" or c.state == "sleep":
				c.state = "wander"
				c.visible = true
		if frightened:
			c.state = "flee"
		if c.state == "flee":
			if not frightened:
				c.state = "wander"
			else:
				c.flee_t += dt
				var away: float = pd.angle() if dist > 0.001 else rng.next() * TAU
				var sp: float = flee_speed(c) * dt
				var moved := false
				for off in [0.0, 0.6, -0.6, 1.2, -1.2, 1.9, -1.9]:
					if _try_move(c, away + off, sp):
						moved = true
						break
				if not moved:
					c.alarm_t = 0.0
				continue
		c.flee_t = maxf(0.0, c.flee_t - dt * 0.5)
		# wander: alternate short walks and pauses, tethered to home
		c.phase_t -= dt
		if c.phase_t <= 0.0:
			c.moving = rng.next() < 0.7
			c.phase_t = 0.4 + rng.next() * 1.6
			c.heading = rng.next() * TAU
			var tr := Vector2(c.home_x - c.x, c.home_y - c.y)
			if tr.length() > float(s["wander_radius"]):
				c.heading = tr.angle()
		if c.moving:
			if not _try_move(c, c.heading, float(s["speed"]) * 0.5 * dt):
				c.heading = rng.next() * TAU
				c.phase_t = 0.1


## Emit small sonar pulses for critters whose squeak timer has expired (awake, species that squeak). Returns pulses emitted.
func squeak(sonar, t: float = NAN) -> int:
	var now: float = time if is_nan(t) else t
	var n := 0
	for c in critters:
		var s := spec(c.species)
		var sq: Dictionary = s["squeak"]
		var iv: float = float(sq["interval"])
		if iv <= 0.0 or c.squeak_t > 0.0 or c.state == "roost" or c.state == "hide" or c.state == "sleep":
			continue
		sonar.emit_sound(world, c.x, c.y, now, {"strength": float(sq["strength"]), "kind": String(sq["kind"]), "range": float(sq["range"]), "z": 0.3})
		c.squeak_t = iv * (0.7 + rng.next() * 0.6)
		n += 1
	return n


## Critters a pulse can currently reveal (in range, ray-visible, not hidden). Pass the ring window (t_prev, t) to only take critters the
## wavefront crossed in that window; the default takes everyone in range. Appends to `echoes` and returns the new ones.
func echo_snapshot_visible(pulse, t_prev: float = -INF, t: float = INF) -> Array[Echo]:
	var made: Array[Echo] = []
	if pulse == null or pulse.strength <= 0.01:
		return made
	var windowed: bool = not (is_inf(t_prev) and is_inf(t))
	for c in critters:
		if not c.visible:
			continue
		var dx: float = c.x - pulse.x
		var dy: float = c.y - pulse.y
		if dx * dx + dy * dy > pulse.range * pulse.range:
			continue
		if not Sonar.visible_from(pulse, c.x, c.y):
			continue
		var la: float = pulse.t0
		if windowed:
			la = Sonar.lit_at(pulse, c.x, c.y)
			if not (la > t_prev and la <= t):
				continue
		var e := Echo.new()
		e.critter_id = c.id
		e.species = c.species
		e.x = c.x
		e.y = c.y
		e.t = la
		e.strength = pulse.strength
		made.append(e)
		echoes.append(e)
	return made


## Drop echoes older than `fade` seconds.
func prune_echoes(t: float, fade: float = 3.0) -> void:
	var keep: Array[Echo] = []
	for e in echoes:
		if t - e.t <= fade:
			keep.append(e)
	echoes = keep


## Nearest living, non-hidden critter within reach of (x, y), or null.
func nearest_feedable(x: float, y: float, reach: float = FEED_REACH) -> Critter:
	var best: Critter = null
	var bd := reach
	for c in critters:
		if c.dead or not c.visible:
			continue
		var d: float = Vector2(c.x - x, c.y - y).length()
		if d <= bd:
			bd = d
			best = c
	return best


## Drink: returns the blood amount, marks the critter dead and removes it for good (prey never respawns). 0 when already dead.
func feed(c: Critter) -> int:
	if c == null or c.dead:
		return 0
	c.dead = true
	var b: int = c.blood
	c.blood = 0
	critters.erase(c)
	var keep: Array[Echo] = []
	for e in echoes:
		if e.critter_id != c.id:
			keep.append(e)
	echoes = keep
	eaten += 1
	return b


## The player pinged: awake critters within `radius` cells freeze for ~1 s (startle-freeze) rather than bolting. Fleeing ones keep running.
## Returns how many froze.
func on_ping(player_pos: Vector2, radius: float = PING_FREEZE_RADIUS) -> int:
	var n := 0
	for c in critters:
		if c.dead or not c.visible or c.state == "flee" or c.state == "hide":
			continue
		if Vector2(c.x - player_pos.x, c.y - player_pos.y).length() > radius:
			continue
		c.freeze_t = float(catch_tuning(c.species)["freeze_s"])
		c.moving = false
		n += 1
	return n


func _line_clear(ax: float, ay: float, bx: float, by: float) -> bool:
	if world == null:
		return true
	var n := int(ceil(Vector2(bx - ax, by - ay).length() / 0.25))
	for i in range(1, n):
		var f := float(i) / float(n)
		if world.blocks(ax + (bx - ax) * f, ay + (by - ay) * f, 0.05):
			return false
	return true


## A 0.25 s lunge: the nearest live, visible critter within `reach` with a clear line that is not fleeing at full speed is snapped to
## feedable range (and held for the lunge) and returned; otherwise null. Caller then feeds it.
func lunge(player_pos: Vector2, reach: float = LUNGE_REACH) -> Critter:
	var best: Critter = null
	var bd := reach
	for c in critters:
		if c.dead or not c.visible:
			continue
		if c.state == "flee" and c.freeze_t <= 0.0 and c.flee_t <= float(catch_tuning(c.species)["tire_after"]):
			continue
		var d: float = Vector2(c.x - player_pos.x, c.y - player_pos.y).length()
		if d <= bd and _line_clear(player_pos.x, player_pos.y, c.x, c.y):
			bd = d
			best = c
	if best != null:
		if bd > FEED_REACH * 0.8:
			var dir := Vector2(best.x - player_pos.x, best.y - player_pos.y).normalized()
			var tx: float = player_pos.x + dir.x * FEED_REACH * 0.6
			var ty: float = player_pos.y + dir.y * FEED_REACH * 0.6
			if world == null or not world.blocks(tx, ty, BODY_R):
				best.x = tx
				best.y = ty
		best.freeze_t = LUNGE_TIME
		best.alarm_t = 0.0
	return best
