class_name People
extends RefCounted
## Ports js/people.js. One People instance is the JS people `state`.
## Phase 1 scope: path walking, sound/sight reactions (startle, flee, hide, cower, wary), feeding hooks, echo snapshots.
## Forge-generated villagers with night schedules (person.sched), conversations, spawn/despawn/alter are included. Pass
## opts.noForge = true to create() to get the plain walkers of a JS run without Forge/Schedule loaded (the golden traces of
## people.json use that mode).
## Logic uses plain floats; people carry x, y as floats, never Vector2.

const TWO_PI := JsMath.TWO_PI
const LOOK_MAX := 0.6
const DEFAULT_SPEED := 1.2
const DEFAULT_WAIT := 1.0
const REACT_DEFAULTS := {
	"startleDist": 3.0, "seeDist": 8.0, "seeCone": 2.0944, "bumpDist": 1.0, "fleeMul": 1.6,
	"calmAfter": 10.0, "screamGap": 2.0, "startleTime": 1.0, "arriveGrace": 1.0, "lightSeen": 0.3, "dazedTime": 3.0,
	"bumpArc": 1.7453, "bumpBackDist": 0.5, "bumpFreeze": 0.4, "waryTime": 20.0, "fleeCap": 2.55, "lightPref": 1.0,
}
const HIDE_MAX_STEPS := 30
const LIT_MAX_STEPS := 15
const LIT_MIN := 0.3
const WARY_SEE_MUL := 0.5
const WHIMPER_GAP := 1.5
const MAX_EVENTS := 64
const HIDE_UNUSED := 0
const FEAR_HOME := 8.0
const CHAT_DIST := 1.5
const TABLE_DIST := 2.8
const CHAT_SCAN := 0.25
const CHAT_COOL := [10.0, 22.0]
const CHAT_FEAR := 3.0
const FOREVER := 1e9
const MAX_PEOPLE := 24
const ACCESSORIES := ["tophat", "nightcap", "bonnet", "cane", "scarf", "lantern", "hood", "umbrella", "cap", "basket"]
const HATS := ["tophat", "nightcap", "bonnet", "cap", "hood"]
const PROPS := ["cane", "lantern", "umbrella", "basket"]
const BODIES := ["bean", "pear", "stick", "round", "box"]
const HEADS := ["round", "egg", "square", "long"]
const HAIRS := ["none", "tuft", "bun", "spiky", "curls", "bob"]


class Person:
	extends RefCounted
	var pool: float = 0.0
	var left: float = 0.0
	var dazed_left: float = 0.0
	var role: String = ""
	var archetype: String = "patron"
	var watch: bool = false
	var feedable: bool = true
	var gait: String = "walk"
	var id: int = 0
	var x: float = 0.0
	var y: float = 0.0
	var angle: float = 0.0
	var speed: float = DEFAULT_SPEED
	var path: Array = []
	var idx: int = 0
	var state: String = "idle"
	var idle_left: float = 0.0
	var look_angle: float = 0.0
	var look_target: float = 0.0
	var look_in: float = 0.0
	var phase: float = 0.0
	var walked: float = 0.0
	var look: Dictionary = {}
	var steps: int = 0
	var steps_reported: int = 0
	var mode: String = "path"
	var mode_left: float = 0.0
	var flee_x: float = 0.0
	var flee_y: float = 0.0
	var calm_left: float = 0.0
	var fdir: int = 1
	var block_count: int = 0
	var pre_state: String = "idle"
	var sit: bool = false
	var route: Variant = null
	var ri: int = 0
	var ret: Variant = null
	var ri2: int = 0
	var bumping: bool = false
	var wary: float = 0.0
	var whimper_in: float = WHIMPER_GAP
	# Pose bookkeeping for the renderer.
	var mode_prev: String = ""
	var mode_age: float = 0.0
	var ph0: float = 0.0
	var phase_rate: float = 0.0
	var seated: bool = false
	var sched: Variant = null
	var chat: Variant = null
	var chat_cool: float = 0.0


class Echo:
	extends RefCounted
	var person_id: int = 0
	var kind: String = "ping"
	var x: float = 0.0
	var y: float = 0.0
	var angle: float = 0.0
	var look_angle: float = 0.0
	var phase: float = 0.0
	var moving: bool = false
	var t: float = 0.0
	var dist: float = 0.0
	var strength: float = 0.0
	var pan: float = 0.0
	var look: Dictionary = {}
	var theta: float = 0.0
	var z_min: float = 0.0
	var z_max: float = 1.2
	var fade: float = 3.0
	var mode: String = "path"
	var sit: bool = false
	var wary: bool = false
	var chat: bool = false
	var mode_age: float = 0.0
	var phase_rate: float = 0.0


var people: Array[Person] = []
var echoes: Array[Echo] = []
var seed_value: float = 1.0
var rng: Rng
var chat_rng: Rng
var max_echoes: int = 24
var radius: float = 0.2
var hides: Array = []
var time: float = 0.0
var night_frac: float = 0.0
var night_sec: float = 0.0
var fear: float = 0.0
var last_scream: float = -INF
var events: Array = []
var world: World = null
var rp: Dictionary = {}
var acc_offset: int = 0
var next_id: int = 0
var base_count: int = 0
var pool_min: float = 30.0
var pool_max: float = 50.0
var chat_in: float = 0.0
var route_calls: int = 0
var walk_cache: PackedByteArray = PackedByteArray()
var cost_cache: PackedFloat64Array = PackedFloat64Array()
var places: Dictionary = {}
var map_def: Dictionary = {}
var use_forge: bool = true
var forge_log: Dictionary = {"spawned": [], "altered": []}
var forge_fired: int = 0
var forge_reinf: Array = []
var forge_lantern: bool = false
var forge_in: float = 0.0
var last_state_ref: bool = false


static func normalize_look_seed(seed: float, pid: int) -> float:
	return float(JsMath.u32(float(JsMath.u32(seed)) * 2654435761.0 + float(pid + 1) * 40503.0 + 977.0))


## Ports makeLookLocal (js/people.js:75), the look used when Forge is not loaded.
static func make_look(seed: float, id: int, acc_offset: int) -> Dictionary:
	var r := Rng.new(normalize_look_seed(seed, id))
	var height: float = 0.9 + r.next() * 0.15
	var build: float = 0.9 + r.next() * 0.25
	var stride: float = 0.9 + r.next() * 0.25
	var n: int = ACCESSORIES.size()
	var acc: String = ACCESSORIES[(((acc_offset + 3 * id) % n) + n) % n]
	var body: String = BODIES[int(floor(r.next() * BODIES.size()))]
	var head: String = HEADS[int(floor(r.next() * HEADS.size()))]
	var hat: String = acc if HATS.has(acc) else "none"
	var hair: String = HAIRS[int(floor(r.next() * HAIRS.size()))]
	if hat == "nightcap" or hat == "hood" or hat == "tophat":
		hair = "none"
	var beard: bool = r.next() < 0.3
	var nose: float = 0.7 + r.next() * 0.7
	var coat: bool = r.next() < 0.45
	var prop: String = acc if PROPS.has(acc) else "none"
	return {"height": height, "build": build, "stride": stride, "acc": acc, "body": body, "head": head, "hat": hat, "hair": hair, "beard": beard, "nose": nose, "coat": coat, "prop": prop}


static func _blocked(w: World, x: float, y: float, r: float) -> bool:
	return w.blocks(x, y, r)


static func segment_clear(w: World, ax: float, ay: float, bx: float, by: float) -> bool:
	var length: float = sqrt((bx - ax) * (bx - ax) + (by - ay) * (by - ay))
	var n: int = maxi(1, int(ceil(length / 0.1)))
	for i in n + 1:
		var f: float = float(i) / n
		if w.is_solid(ax + (bx - ax) * f, ay + (by - ay) * f):
			return false
	return true


## Path legs may pass through doors (people open them) but not walls or solid props.
static func leg_clear(w: World, ax: float, ay: float, bx: float, by: float) -> bool:
	var length: float = sqrt((bx - ax) * (bx - ax) + (by - ay) * (by - ay))
	var n: int = maxi(1, int(ceil(length / 0.1)))
	var has_blocks: bool = w.props.size() > 0
	for i in n + 1:
		var f: float = float(i) / n
		var x: float = ax + (bx - ax) * f
		var y: float = ay + (by - ay) * f
		if w.is_solid(x, y):
			var t := w.tile_at(x, y)
			if t != "D" and t != "G":
				return false
		elif has_blocks and w.blocks(x, y, 0.0):
			return false
	return true


## Ports buildPath (js/people.js:137): validated path, falling back to a one-point path at the spawn.
static func build_path(w: World, spawn: Vector2, def: Variant, id: int) -> Array:
	var one: Array = [{"x": spawn.x, "y": spawn.y, "wait": DEFAULT_WAIT}]
	var pts: Variant = def.get("points") if def is Dictionary else null
	var waits: Array = def.get("waits", []) if def is Dictionary and def.get("waits") is Array else []
	if not (pts is Array) or pts.is_empty():
		return one
	var path: Array = []
	for i in pts.size():
		var p: Variant = pts[i]
		if not (p is Array) or p.size() < 2:
			return one
		var wt: float = float(waits[i]) if i < waits.size() and (waits[i] is float or waits[i] is int) and float(waits[i]) >= 0.0 else DEFAULT_WAIT
		path.append({"x": float(p[0]) + 0.5, "y": float(p[1]) + 0.5, "wait": wt})
	if absf(path[0]["x"] - spawn.x) > 1e-6 or absf(path[0]["y"] - spawn.y) > 1e-6:
		return one
	for i in path.size():
		var a: Dictionary = path[i]
		var b: Dictionary = path[(i + 1) % path.size()]
		if w.is_solid(a["x"], a["y"]) or not leg_clear(w, a["x"], a["y"], b["x"], b["y"]):
			return one
	return path


static func sanitize_hides(w: World, map_def: Dictionary) -> Array:
	var out: Array = []
	var src: Array = map_def.get("hides", []) if map_def.get("hides") is Array else []
	var i := 0
	while i < src.size() and out.size() < 256:
		var h: Variant = src[i]
		i += 1
		if not (h is Array) or h.size() < 2:
			continue
		var x: float = floor(float(h[0])) + 0.5
		var y: float = floor(float(h[1])) + 0.5
		if w == null or w.is_solid(x, y):
			continue
		out.append({"x": x, "y": y})
	return out


static func cell_walkable(w: World, cx: int, cy: int) -> bool:
	var x: float = cx + 0.5
	var y: float = cy + 0.5
	if not w.is_solid(x, y):
		return not w.blocks(x, y, 0.0)
	var t := w.tile_at(x, y)
	return t == "D" or t == "G"


static func lit_at(w: World, x: float, y: float) -> float:
	return w.light_at(x, y) if w != null else 0.0


static func lit_around(w: World, x: float, y: float) -> bool:
	return lit_at(w, x, y) >= LIT_MIN or lit_at(w, x + 1, y) >= LIT_MIN or lit_at(w, x - 1, y) >= LIT_MIN \
		or lit_at(w, x, y + 1) >= LIT_MIN or lit_at(w, x, y - 1) >= LIT_MIN


## BFS over walkable cells from p; goal(cx, cy) picks the target. Returns cell-centre waypoints (start excluded) or null.
static func bfs_route(w: World, p: Person, goal: Callable, max_steps: int) -> Variant:
	var sx: int = int(floor(p.x))
	var sy: int = int(floor(p.y))
	var prev := {}
	var key := func(cx: int, cy: int) -> int: return (cy + 1000) * 100000 + (cx + 1000)
	var frontier: Array = [[sx, sy]]
	prev[key.call(sx, sy)] = null
	var found: Variant = null
	var step := 0
	while step <= max_steps and frontier.size() > 0 and found == null:
		var nxt: Array = []
		for c in frontier:
			if (c[0] != sx or c[1] != sy) and goal.call(c[0], c[1]):
				found = c
				break
			var nb := [[c[0] + 1, c[1]], [c[0] - 1, c[1]], [c[0], c[1] + 1], [c[0], c[1] - 1]]
			for k in 4:
				var kk: int = key.call(nb[k][0], nb[k][1])
				if prev.has(kk) or not cell_walkable(w, nb[k][0], nb[k][1]):
					continue
				prev[kk] = c
				nxt.append(nb[k])
		frontier = nxt
		step += 1
	if found == null:
		return null
	var cells: Array = []
	var c: Variant = found
	while c != null:
		cells.append(c)
		c = prev[key.call(c[0], c[1])]
	cells.reverse()
	cells.pop_front()
	var route_out: Array = []
	for cc in cells:
		route_out.append({"x": cc[0] + 0.5, "y": cc[1] + 0.5})
	return route_out


## Ports create (js/people.js:389) for walkers without Forge/Schedule. opts: seed, maxEchoes, poolMin, poolMax, shuffle.
static func create(w: World, map_def: Dictionary, opts: Dictionary = {}) -> People:
	var s := People.new()
	var sd: float = float(opts["seed"]) if (opts.get("seed") is float or opts.get("seed") is int) and is_finite(float(opts["seed"])) else 1.0
	s.seed_value = sd
	s.rng = Rng.new(sd)
	s.chat_rng = Rng.new(float(JsMath.u32(sd * 131.0 + 7.0)))
	s.max_echoes = int(floor(float(opts["maxEchoes"]))) if (opts.get("maxEchoes") is float or opts.get("maxEchoes") is int) and float(opts["maxEchoes"]) > 0.0 else 24
	s.hides = sanitize_hides(w, map_def)
	s.world = w
	s.rp = REACT_DEFAULTS.duplicate()
	var pmin: float = float(opts["poolMin"]) if (opts.get("poolMin") is float or opts.get("poolMin") is int) and float(opts["poolMin"]) > 0.0 else 30.0
	var pmax: float = float(opts["poolMax"]) if (opts.get("poolMax") is float or opts.get("poolMax") is int) and float(opts["poolMax"]) >= pmin else maxf(pmin, 50.0)
	var acc_off: int = int(floor(Rng.new(float(JsMath.u32(sd * 7919.0 + 13.0))).next() * ACCESSORIES.size()))
	s.use_forge = opts.get("noForge") != true
	s.map_def = map_def
	var spawns: Array = w.spots["people"]
	var defs: Array = map_def.get("paths", []) if map_def.get("paths") is Array else []
	if s.use_forge and map_def.get("places") is Dictionary:
		for k in map_def["places"]:
			var c: Variant = map_def["places"][k]
			if c is Array and c.size() >= 2 and (c[0] is float or c[0] is int) and (c[1] is float or c[1] is int) and not w.is_solid(float(c[0]) + 0.5, float(c[1]) + 0.5):
				s.places[k] = {"x": float(c[0]) + 0.5, "y": float(c[1]) + 0.5}
	for i in spawns.size():
		var def: Variant = defs[i] if i < defs.size() else null
		var path: Array = build_path(w, spawns[i], def, i)
		var spd: float = float(def["speed"]) if def is Dictionary and (def.get("speed") is float or def.get("speed") is int) and float(def["speed"]) > 0.0 else DEFAULT_SPEED
		var ang := 0.0
		if path.size() > 1:
			ang = atan2(path[1]["y"] - path[0]["y"], path[1]["x"] - path[0]["x"])
		var sit: bool = def is Dictionary and def.get("sit") == true
		var pool: float = pmin + (pmax - pmin) * s.rng.next()
		var p := Person.new()
		p.pool = pool
		p.left = pool
		var role_s: String = def["role"] if def is Dictionary and def.get("role") is String else ""
		var gp: Variant = null
		if s.use_forge:
			var arch_id: String = def["archetype"] if def is Dictionary and def.get("archetype") is String else ""
			if arch_id == "" and role_s != "":
				var ba: Variant = Forge.by_role(role_s)
				arch_id = ba["id"] if ba != null and ba.get("id") != null else ""
			var spec := {"archetype": arch_id if arch_id != "" else "patron"}
			if def is Dictionary and def.get("seed") != null:
				spec["seed"] = def["seed"]
			if def is Dictionary and def.get("home") != null:
				spec["home"] = def["home"]
			var gen := Forge.generate(spec, {"stateSeed": sd, "index": float(i), "accOffset": float(acc_off)})
			gp = gen["person"] if gen["person"] != null else null
		p.role = (gp["role"] if gp != null and gp["role"] != "" else role_s)
		p.archetype = gp["archetype"] if gp != null else "patron"
		p.watch = gp["watch"] if gp != null else role_s == "guard"
		p.feedable = gp["feedable"] if gp != null else true
		p.gait = gp["gait"] if gp != null else ("mail" if role_s == "guard" else "walk")
		p.id = i
		p.x = path[0]["x"]
		p.y = path[0]["y"]
		p.angle = ang
		p.speed = spd
		p.path = path
		p.idx = 1 if path.size() > 1 and not sit else 0
		p.state = "idle"
		p.idle_left = path[0]["wait"]
		p.look_in = 0.5 + s.rng.next() * 0.6
		p.look = gp["look"] if gp != null else make_look(sd, i, acc_off)
		p.sit = sit
		s.people.append(p)
		# a role with a night schedule walks routed trips between named places instead of its hand-made loop
		var sched_role: Variant = gp["schedRole"] if gp != null else (role_s if role_s != "" else null)
		if s.use_forge and not sit and def is Dictionary and sched_role != null and Schedule.has_role(sched_role):
			p.sched = Schedule.make(sched_role, s.places, {"x": path[0]["x"], "y": path[0]["y"]}, Rng.new(float(JsMath.u32(sd * 31.0 + float(i) * 977.0 + 5.0))), {"home": def.get("home"), "slot": i})
			if p.sched != null:
				p.idle_left = 0.0
				face_tables(p.sched, map_def)
	if opts.get("shuffle") == true:
		# v0.8: shuffle draws come after all per-person draws so unshuffled streams are unchanged.
		for p in s.people:
			var n: int = p.path.size()
			if n <= 1 or p.sit or p.sched != null:
				continue
			var k: int = mini(n - 1, int(floor(s.rng.next() * n)))
			if s.rng.next() < 0.5:
				p.path = p.path.duplicate()
				p.path.reverse()
			p.x = p.path[k]["x"]
			p.y = p.path[k]["y"]
			p.idx = (k + 1) % n
			p.idle_left = p.path[k]["wait"]
			p.angle = atan2(p.path[p.idx]["y"] - p.y, p.path[p.idx]["x"] - p.x)
	s.acc_offset = acc_off
	s.pool_min = pmin
	s.pool_max = pmax
	s.next_id = s.people.size()
	s.base_count = s.people.size()
	return s


static func norm_diff(a: float) -> float:
	var d: float = fmod(a, TWO_PI)
	if d > PI:
		d -= TWO_PI
	elif d < -PI:
		d += TWO_PI
	return d


## Copy ctx.react (or defaults) into the scratch params (js fillReact).
func fill_react(react: Variant) -> Dictionary:
	for k in REACT_DEFAULTS:
		var v: Variant = react.get(k) if react is Dictionary else null
		rp[k] = float(v) if (v is float or v is int) and is_finite(float(v)) and float(v) >= 0.0 else REACT_DEFAULTS[k]
	return rp


static func sees(person: Person, w: World, px: float, py: float, r: Dictionary) -> bool:
	var dx: float = px - person.x
	var dy: float = py - person.y
	var d2: float = dx * dx + dy * dy
	var sd: float = r["seeDist"] if r.has("seeDist") else REACT_DEFAULTS["seeDist"]
	if d2 > sd * sd:
		return false
	if d2 > 1e-12:
		var cone: float = r["seeCone"] if r.has("seeCone") else REACT_DEFAULTS["seeCone"]
		var diff: float = norm_diff(atan2(dy, dx) - (person.angle + person.look_angle))
		if absf(diff) > cone / 2.0:
			return false
	return segment_clear(w, person.x, person.y, px, py)


## 0 = not seen, 1 = seen (light + cone + line of sight), 2 = bump-noticed (touching).
static func is_seen(p: Person, w: World, px: float, py: float, lit: float, r: Dictionary) -> int:
	var dx: float = px - p.x
	var dy: float = py - p.y
	var d2: float = dx * dx + dy * dy
	var is_lit: bool = lit >= r["lightSeen"]
	if is_lit:
		var sd: float = r["seeDist"]
		if d2 <= sd * sd and sees(p, w, px, py, r):
			return 1
	if r["bumpDist"] > 0.0 and d2 <= r["bumpDist"] * r["bumpDist"]:
		var near_: bool = is_lit or d2 <= 1e-12
		if not near_:
			near_ = absf(norm_diff(atan2(dy, dx) - (p.angle + p.look_angle))) <= r["bumpArc"]
		var back: float = minf(r["bumpBackDist"], r["bumpDist"])
		if near_ or d2 <= back * back:
			return 2
	return 0


## is_seen with the wary person's halved sight (rp is shared scratch, restored after).
static func is_seen_by(p: Person, w: World, px: float, py: float, lit: float, r: Dictionary) -> int:
	if not (p.wary > 0.0):
		return is_seen(p, w, px, py, lit, r)
	var sd: float = r["seeDist"]
	r["seeDist"] = sd * WARY_SEE_MUL
	var res: int = is_seen(p, w, px, py, lit, r)
	r["seeDist"] = sd
	return res


func push_event(type: String, p: Person) -> void:
	if events.size() >= MAX_EVENTS:
		events.pop_front()
	events.append({"type": type, "id": p.id, "x": p.x, "y": p.y})


static func farthest_waypoint(p: Person, px: float, py: float) -> int:
	var best := -1
	var best_d: float = (px - p.x) * (px - p.x) + (py - p.y) * (py - p.y) + 1e-6
	for i in p.path.size():
		var dx: float = p.path[i]["x"] - px
		var dy: float = p.path[i]["y"] - py
		var d: float = dx * dx + dy * dy
		if d > best_d:
			best_d = d
			best = i
	return best


## Choose the loop direction toward waypoint g given the next waypoint each way; sets idx and fdir (js route).
static func route_loop(p: Person, g: int, nf: int, nb: int, px: float, py: float) -> void:
	var n: int = p.path.size()
	var cf: int = (g - nf + n) % n
	var cb: int = (nb - g + n) % n
	var fwd: bool = cf < cb
	if cf == cb:
		var f: Dictionary = p.path[nf]
		var b: Dictionary = p.path[nb]
		fwd = (f["x"] - px) * (f["x"] - px) + (f["y"] - py) * (f["y"] - py) >= (b["x"] - px) * (b["x"] - px) + (b["y"] - py) * (b["y"] - py)
	p.fdir = 1 if fwd else -1
	p.idx = nf if fwd else nb


## Pick a refuge: nearest LIT cell farther from the player, else nearest hide spot. Sets p.route / p.ret (js pickHide).
func pick_hide(p: Person, px: float, py: float, r: Dictionary) -> bool:
	p.route = null
	p.ri = 0
	if world == null:
		return false
	var dp: float = (p.x - px) * (p.x - px) + (p.y - py) * (p.y - py)
	var far := func(cx: int, cy: int) -> bool: return (cx + 0.5 - px) * (cx + 0.5 - px) + (cy + 0.5 - py) * (cy + 0.5 - py) > dp
	var found: Variant = null
	if r["lightPref"] > 0.0:
		found = bfs_route(world, p, func(cx: int, cy: int) -> bool: return far.call(cx, cy) and lit_at(world, cx + 0.5, cy + 0.5) >= LIT_MIN, LIT_MAX_STEPS)
	if found == null and hides.size() > 0:
		var want := {}
		for h in hides:
			var cx: int = int(floor(h["x"]))
			var cy: int = int(floor(h["y"]))
			if far.call(cx, cy):
				want[cy * 100000 + cx] = true
		if want.size() > 0:
			found = bfs_route(world, p, func(cx: int, cy: int) -> bool: return want.has(cy * 100000 + cx), HIDE_MAX_STEPS)
	if found == null:
		return false
	p.route = found
	if found.is_empty():
		return true
	var back: Array = []
	var i: int = found.size() - 2
	while i >= 0:
		back.append(found[i])
		i -= 1
	back.append({"x": p.x, "y": p.y})
	p.ret = back
	p.ri2 = 0
	return true


static func start_cower(p: Person, px: float, py: float) -> void:
	p.route = null
	p.mode = "cower"
	p.state = "idle"
	p.block_count = 0
	p.whimper_in = WHIMPER_GAP
	p.angle = atan2(p.y - py, p.x - px)


func enter_flee(p: Person, px: float, py: float, r: Dictionary, quiet: bool = false) -> void:
	var n: int = p.path.size()
	if p.chat != null:
		end_chat(p)
	if p.mode == "path" or p.mode == "startle" or p.mode == "dazed":
		p.flee_x = px
		p.flee_y = py
		p.calm_left = r["calmAfter"]
		p.block_count = 0
		p.mode_left = 0.0
		p.bumping = false
		p.mode = "flee"
		p.dazed_left = 0.0
		if not quiet and time - last_scream >= r["screamGap"]:
			last_scream = time
			push_event("scream", p)
		push_event("flee", p)
		p.route = null
		p.ret = null
		if pick_hide(p, px, py, r):
			if p.route.is_empty():
				start_cower(p, px, py)
				return
			p.state = "walk"
			p.look_target = 0.0
			return
		var g: int = farthest_waypoint(p, px, py) if n > 1 else -1
		if g < 0:
			start_cower(p, px, py)
			return
		route_loop(p, g, p.idx, (p.idx - 1 + n) % n, px, py)
		p.state = "walk"
		p.look_target = 0.0


## Bump notice: freeze for bumpFreeze (mode "startle"), then flee.
func start_bump(p: Person, px: float, py: float, r: Dictionary) -> void:
	if p.chat != null:
		end_chat(p)
	p.mode = "startle"
	p.bumping = true
	p.mode_left = r["bumpFreeze"]
	p.pre_state = p.state
	p.state = "idle"
	p.angle = atan2(py - p.y, px - p.x)
	push_event("startle", p)


## Move p toward (tx, ty) by up to step; returns distance moved (v0.5 movement rules).
func walk_toward(p: Person, dx: float, dy: float, dist: float, step: float, r: float) -> float:
	p.angle = atan2(dy, dx)
	var mx: float = (dx / dist) * step
	var my: float = (dy / dist) * step
	var ox: float = p.x
	var oy: float = p.y
	if not _blocked(world, p.x + mx, p.y, r):
		p.x += mx
	if not _blocked(world, p.x, p.y + my, r):
		p.y += my
	var moved: float = sqrt((p.x - ox) * (p.x - ox) + (p.y - oy) * (p.y - oy))
	p.walked += moved
	var ph_before: float = p.phase
	p.phase += moved * 9.0
	# A foot plants at the extremes of the leg swing: phase = PI/2 + k*PI (two per cycle).
	p.steps += int(floor((p.phase - PI / 2.0) / PI)) - int(floor((ph_before - PI / 2.0) / PI))
	if p.phase > TWO_PI * 1000.0:
		p.phase -= TWO_PI * 1000.0
	return moved


## Seated eat/drink stops face the nearest table prop (within 1.6 cells) and remember their table group (js faceTables).
static func face_tables(sc: Dictionary, map_def_d: Dictionary) -> void:
	var props_d: Array = map_def_d.get("props", []) if map_def_d.get("props") is Array else []
	var re := RegEx.new()
	re.compile("\\d+$")
	for st in sc["stops"]:
		if st["act"] != "eat" and st["act"] != "drink":
			continue
		st["group"] = re.sub(st["place"], "")
		var best := 2.56
		for pr in props_d:
			if pr["type"] != "table":
				continue
			var d: float = (float(pr["col"]) + 0.5 - st["x"]) * (float(pr["col"]) + 0.5 - st["x"]) + (float(pr["row"]) + 0.5 - st["y"]) * (float(pr["row"]) + 0.5 - st["y"])
			if d < best:
				best = d
				st["face"] = atan2(float(pr["row"]) + 0.5 - st["y"], float(pr["col"]) + 0.5 - st["x"])


## End p's conversation (and its partner's, if it points back).
func end_chat(p: Person) -> void:
	var c: Variant = p.chat
	if c == null:
		return
	p.chat = null
	var q := find_person(int(c["partner"]))
	if q != null and q.chat != null and int(q.chat["partner"]) == p.id:
		q.chat = null
	p.chat_cool = time + float(CHAT_COOL[0]) + (float(CHAT_COOL[1]) - float(CHAT_COOL[0])) * chat_rng.next()


func chat_ready(p: Person) -> bool:
	return p.chat == null and p.mode == "path" and not (p.wary > 0.0) and not p.bumping and p.ret == null and not (p.chat_cool > time) and not p.sit


func start_chat(a: Person, b: Person, kind: String, until: float, table: bool) -> void:
	a.chat = {"partner": b.id, "kind": kind, "until": until, "table": table, "mood": "warm" if table else "neutral"}
	b.chat = {"partner": a.id, "kind": kind, "until": until, "table": table, "mood": "warm" if table else "neutral"}
	if not table:
		a.angle = atan2(b.y - a.y, b.x - a.x)
		b.angle = atan2(a.y - b.y, a.x - b.x)


## Proximity scan (throttled): tablemates chat while seated; calm pairs within CHAT_DIST roll a meeting.
func scan_chats(w: World) -> void:
	if fear >= CHAT_FEAR:
		return
	var t2: float = TABLE_DIST * TABLE_DIST
	var c2: float = CHAT_DIST * CHAT_DIST
	for i in people.size():
		var a: Person = people[i]
		if a.sched == null or a.chat != null:
			continue
		for j in range(i + 1, people.size()):
			var b: Person = people[j]
			if b.sched == null or b.chat != null:
				continue
			var dx: float = a.x - b.x
			var dy: float = a.y - b.y
			var d2: float = dx * dx + dy * dy
			if d2 > t2:
				continue
			if a.seated and b.seated:
				var sa: Variant = a.sched["stops"][a.sched["si"]] if a.sched["si"] >= 0 and a.sched["si"] < a.sched["stops"].size() else null
				var sb: Variant = b.sched["stops"][b.sched["si"]] if b.sched["si"] >= 0 and b.sched["si"] < b.sched["stops"].size() else null
				if sa != null and sb != null and sa.get("group") != null and sa["group"] == sb.get("group") and not a.sched["en"] and not b.sched["en"] and a.mode == "path" and b.mode == "path" and not (a.wary > 0.0) and not (b.wary > 0.0):
					start_chat(a, b, "chat", FOREVER, true)
					break
				continue
			if d2 > c2 or a.seated or b.seated:
				continue
			if not chat_ready(a) or not chat_ready(b):
				continue
			if not segment_clear(w, a.x, a.y, b.x, b.y):
				continue
			var same: bool = a.sched["home"] != null and a.sched["home"] == b.sched["home"]
			var roll := Schedule.chat_roll(str(a.sched["role"]), str(b.sched["role"]), same, chat_rng.next(), chat_rng.next())
			var cool: float = time + float(CHAT_COOL[0]) + (float(CHAT_COOL[1]) - float(CHAT_COOL[0])) * chat_rng.next()
			if roll["kind"] == "ignore":
				a.chat_cool = cool
				b.chat_cool = cool
				continue
			start_chat(a, b, roll["kind"], time + float(roll["sec"]), false)
			a.chat["mood"] = roll["mood"]
			b.chat["mood"] = roll["mood"]
			break


## Standing meeting: face the partner, stop walking, end on time. Tablemates (c.table) are not held here.
func chat_hold(p: Person, dt: float) -> bool:
	var c: Dictionary = p.chat
	var q := find_person(int(c["partner"]))
	if q == null or time >= float(c["until"]):
		end_chat(p)
		return false
	p.angle = atan2(q.y - p.y, q.x - p.x)
	p.look_angle += (0.0 - p.look_angle) * minf(1.0, 4.0 * dt)
	p.phase *= maxf(0.0, 1.0 - 8.0 * dt)
	if p.phase < 0.01:
		p.phase = 0.0
	return true


## Lit-street cost: cells whose own light is >= LIT_MIN are cheap, dark cells cost more. Cached per state.
func step_cost(w: World, cx: int, cy: int, pref: float) -> float:
	if not (pref > 0.0):
		return 1.0
	var k: int = cy * w.width + cx
	var c: float = cost_cache[k]
	if c < 0.0:
		c = 1.0 if lit_at(w, cx + 0.5, cy + 0.5) >= LIT_MIN else 1.0 + pref
		cost_cache[k] = c
	return c


## Cheapest walkable route (4-connected, doors open) from p to cell (tx, ty), preferring lit cells. Cell centres, start
## excluded; null when unreachable. The binary heap and tie order follow the JS so routes are identical; distances and
## predecessors live in flat arrays and walkability is cached per cell (props never move).
func route_to(w: World, p: Person, tx: int, ty: int, pref: float) -> Variant:
	route_calls += 1
	var sx: int = int(floor(p.x))
	var sy: int = int(floor(p.y))
	if sx == tx and sy == ty:
		return []
	var gw: int = w.width
	var gh: int = w.height
	var n: int = gw * gh
	if walk_cache.size() != n:
		walk_cache = PackedByteArray()
		walk_cache.resize(n)
		cost_cache = PackedFloat64Array()
		cost_cache.resize(n)
		cost_cache.fill(-1.0)
	var dist := PackedFloat64Array()
	dist.resize(n)
	dist.fill(INF)
	var prev := PackedInt32Array()
	prev.resize(n)
	prev.fill(-2)
	var start: int = sy * gw + sx
	dist[start] = 0.0
	prev[start] = -1
	var heap: Array = [[0.0, sx, sy]]
	var guard := 0
	var dxs := [1, -1, 0, 0]
	var dys := [0, 0, 1, -1]
	while heap.size() > 0 and guard < 20000:
		guard += 1
		var top: Array = heap[0]
		var last: Array = heap.pop_back()
		if heap.size() > 0:
			heap[0] = last
			var i := 0
			while true:
				var l: int = i * 2 + 1
				var r: int = l + 1
				var m: int = i
				if l < heap.size() and heap[l][0] < heap[m][0]:
					m = l
				if r < heap.size() and heap[r][0] < heap[m][0]:
					m = r
				if m == i:
					break
				var t: Array = heap[m]
				heap[m] = heap[i]
				heap[i] = t
				i = m
		var cx: int = top[1]
		var cy: int = top[2]
		if top[0] > dist[cy * gw + cx]:
			continue
		if cx == tx and cy == ty:
			break
		for k in 4:
			var nx: int = cx + dxs[k]
			var ny: int = cy + dys[k]
			if nx < 0 or ny < 0 or nx >= gw or ny >= gh:
				# off-grid cells are solid in the JS world: not walkable
				continue
			var nk: int = ny * gw + nx
			var wk: int = walk_cache[nk]
			if wk == 0:
				wk = 1 if cell_walkable(w, nx, ny) else 2
				walk_cache[nk] = wk
			if wk == 2:
				continue
			var nd: float = top[0] + step_cost(w, nx, ny, pref)
			if dist[nk] <= nd:
				continue
			dist[nk] = nd
			prev[nk] = cy * gw + cx
			heap.append([nd, nx, ny])
			var j: int = heap.size() - 1
			while j > 0:
				var up: int = (j - 1) >> 1
				if heap[up][0] <= heap[j][0]:
					break
				var t2: Array = heap[up]
				heap[up] = heap[j]
				heap[j] = t2
				j = up
	var tk: int = ty * gw + tx
	if tx < 0 or ty < 0 or tx >= gw or ty >= gh or prev[tk] == -2:
		return null
	var cells: Array = []
	var c: int = tk
	while c != -1:
		cells.append(c)
		c = prev[c]
	cells.reverse()
	cells.pop_front()
	var out: Array = []
	for cc in cells:
		out.append({"x": float(cc % gw) + 0.5, "y": float(cc / gw) + 0.5})
	return out


## Waypoint reached on a scheduled trip: keep walking the route, or settle at the stop.
func sched_arrive(p: Person) -> void:
	var s_: Dictionary = p.sched
	if p.idx < p.path.size() - 1:
		p.idx += 1
		return
	settle(p, int(s_["target"]))


## At the stop for good: idle there, seated when the act is a sitting one.
func settle(p: Person, si: int) -> void:
	var s_: Dictionary = p.sched
	s_["en"] = false
	s_["si"] = si
	s_["retarget"] = false
	p.state = "idle"
	p.idle_left = 0.0
	var stop: Variant = s_["stops"][si] if si >= 0 and si < s_["stops"].size() else null
	p.seated = stop != null and Schedule.is_seated(stop["act"])
	if p.seated and stop != null and stop.get("face") is float:
		p.angle = stop["face"]
		p.look_angle = 0.0
		p.look_target = 0.0


## Idle with a schedule: dwell until the night clock moves on (or a flight broke the trip), then route to the stop.
func sched_idle(w: World, p: Person) -> void:
	var s_: Dictionary = p.sched
	if s_["en"]:
		p.state = "walk"
		return
	# High village fear sends everyone but the watch home for the rest of the night (the last stop is bed).
	if not s_.get("homeEarly", false) and fear >= FEAR_HOME and not p.watch:
		s_["homeEarly"] = true
	var want: int = s_["stops"].size() - 1 if s_.get("homeEarly", false) else Schedule.stop_at(s_["stops"], night_frac)
	if want == int(s_["si"]) and not s_["retarget"]:
		return
	var stop: Dictionary = s_["stops"][want]
	s_["target"] = want
	s_["retarget"] = false
	var cells: Variant = route_to(w, p, int(floor(stop["x"])), int(floor(stop["y"])), 0.6 if rp["lightPref"] > 0.0 else 0.0)
	if cells == null or cells.is_empty():
		settle(p, want)
		return
	var trip: Array = [{"x": p.x, "y": p.y, "wait": 0.0}]
	for c in cells:
		trip.append({"x": c["x"], "y": c["y"], "wait": 0.0})
	p.path = Schedule.simplify(trip)
	p.idx = 1
	p.seated = false
	s_["en"] = true
	p.state = "walk"
	p.look_target = 0.0


## Flight route on a scheduled trip: the path is open (start to stop), so never wrap from its end back to its start.
static func route_open(p: Person, g: int, stay: bool = false) -> void:
	if g > p.idx:
		p.fdir = 1
		if not stay and p.idx < p.path.size() - 1:
			p.idx += 1
	elif g < p.idx:
		p.fdir = -1
		p.idx -= 1
	else:
		p.fdir = 1
	if p.idx < 0:
		p.idx = 0


func step_path(p: Person, dt: float, r: float) -> void:
	if p.chat != null and not p.chat["table"] and chat_hold(p, dt):
		return
	if p.ret != null:
		if p.ri2 >= p.ret.size():
			p.ret = null
		else:
			var rt: Dictionary = p.ret[p.ri2]
			var rx: float = rt["x"] - p.x
			var ry: float = rt["y"] - p.y
			var rd: float = sqrt(rx * rx + ry * ry)
			var rs: float = p.speed * dt
			p.look_angle += (0.0 - p.look_angle) * minf(1.0, 4.0 * dt)
			if rd <= rs or rd <= 0.02:
				p.x = rt["x"]
				p.y = rt["y"]
				p.walked += rd
				p.ri2 += 1
				p.block_count = 0
				return
			if walk_toward(p, rx, ry, rd, rs, r) < rs * 0.05:
				p.block_count += 1
				if p.block_count >= 3:
					p.ret = null
					p.block_count = 0
			else:
				p.block_count = 0
			return
	if p.state == "idle":
		p.idle_left -= dt
		p.look_in -= dt
		if p.look_in <= 0.0:
			p.look_target = (rng.next() * 2.0 - 1.0) * LOOK_MAX
			p.look_in = 0.8 + rng.next() * 0.6
		p.look_angle += (p.look_target - p.look_angle) * minf(1.0, 3.0 * dt)
		p.phase *= maxf(0.0, 1.0 - 8.0 * dt)
		if p.phase < 0.01:
			p.phase = 0.0
		if p.sched != null:
			sched_idle(world, p)
			return
		if p.idle_left <= 0.0 and p.path.size() > 1 and (not p.sit or p.idx != 0 or sqrt((p.path[0]["x"] - p.x) * (p.path[0]["x"] - p.x) + (p.path[0]["y"] - p.y) * (p.path[0]["y"] - p.y)) > 0.05):
			p.state = "walk"
			p.look_target = 0.0
		return
	var tgt: Dictionary = p.path[p.idx]
	var dx: float = tgt["x"] - p.x
	var dy: float = tgt["y"] - p.y
	var dist: float = sqrt(dx * dx + dy * dy)
	var step: float = p.speed * dt
	p.look_angle += (0.0 - p.look_angle) * minf(1.0, 4.0 * dt)
	if dist <= step or dist <= 0.02:
		p.x = tgt["x"]
		p.y = tgt["y"]
		p.walked += dist
		if p.sched != null:
			sched_arrive(p)
			return
		p.state = "idle"
		p.idle_left = tgt["wait"] * (0.85 + 0.3 * rng.next())
		p.idx = 0 if p.sit else (p.idx + 1) % p.path.size()
		return
	var moved: float = walk_toward(p, dx, dy, dist, step, r)
	if moved < step * 0.05:
		# Stuck against a wall (bad path); give up on this leg.
		if p.sched != null:
			p.sched["en"] = false
			p.sched["retarget"] = true
			p.state = "idle"
			p.idle_left = 1.0
			return
		p.state = "idle"
		p.idle_left = tgt["wait"]
		p.idx = 0 if p.sit else (p.idx + 1) % p.path.size()


static func flee_step(p: Person, r: Dictionary, dt: float) -> float:
	return minf(p.speed * r["fleeMul"], r["fleeCap"]) * dt


## Run along p.route to a hide spot, then cower there.
func step_hide(p: Person, dt: float, r: float, rpar: Dictionary) -> void:
	var px: float = p.flee_x
	var py: float = p.flee_y
	p.look_angle += (0.0 - p.look_angle) * minf(1.0, 4.0 * dt)
	var rt: Variant = p.route
	if rt == null or p.ri >= rt.size():
		start_cower(p, px, py)
		return
	var step: float = flee_step(p, rpar, dt)
	var tgt: Dictionary = rt[p.ri]
	var dx: float = tgt["x"] - p.x
	var dy: float = tgt["y"] - p.y
	var dist: float = sqrt(dx * dx + dy * dy)
	if dist <= step or dist <= 0.02:
		p.x = tgt["x"]
		p.y = tgt["y"]
		p.walked += dist
		p.block_count = 0
		p.ri += 1
		if p.ri >= rt.size():
			start_cower(p, px, py)
		return
	var moved: float = walk_toward(p, dx, dy, dist, step, r)
	if moved < step * 0.05:
		p.block_count += 1
		if p.block_count >= 3:
			start_cower(p, px, py)
	else:
		p.block_count = 0


func step_flee(p: Person, dt: float, r: float, rpar: Dictionary) -> void:
	if p.route != null:
		step_hide(p, dt, r, rpar)
		return
	var n: int = p.path.size()
	var px: float = p.flee_x
	var py: float = p.flee_y
	var tgt: Dictionary = p.path[p.idx]
	var dx: float = tgt["x"] - p.x
	var dy: float = tgt["y"] - p.y
	var dist: float = sqrt(dx * dx + dy * dy)
	var step: float = flee_step(p, rpar, dt)
	p.look_angle += (0.0 - p.look_angle) * minf(1.0, 4.0 * dt)
	if dist <= step or dist <= 0.02:
		p.x = tgt["x"]
		p.y = tgt["y"]
		p.walked += dist
		p.block_count = 0
		var g: int = farthest_waypoint(p, px, py)
		if g < 0:
			start_cower(p, px, py)
			return
		if p.sched != null:
			if g == p.idx:
				start_cower(p, px, py)
			else:
				route_open(p, g)
			return
		route_loop(p, g, (p.idx + 1) % n, (p.idx - 1 + n) % n, px, py)
		return
	var moved: float = walk_toward(p, dx, dy, dist, step, r)
	if moved < step * 0.05:
		p.block_count += 1
		if p.block_count >= 2:
			start_cower(p, px, py)
			return
		var g2: int = farthest_waypoint(p, px, py)
		if g2 < 0:
			start_cower(p, px, py)
			return
		if p.sched != null:
			route_open(p, g2, true)
			return
		route_loop(p, g2, p.idx, (p.idx - p.fdir + n + n) % n, px, py)
	else:
		p.block_count = 0


## Lit waypoint (surroundings lit) farthest from (px, py); -1 when none or lightPref is 0.
func lit_waypoint(p: Person, px: float, py: float, r: Dictionary) -> int:
	if not (r["lightPref"] > 0.0) or world == null:
		return -1
	var best := -1
	var best_d := -1.0
	for i in p.path.size():
		var w: Dictionary = p.path[i]
		if not lit_around(world, w["x"], w["y"]):
			continue
		var d: float = (w["x"] - px) * (w["x"] - px) + (w["y"] - py) * (w["y"] - py)
		if d > best_d:
			best_d = d
			best = i
	return best


func resume_path(p: Person, r: Dictionary) -> void:
	var n: int = p.path.size()
	p.mode = "path"
	p.route = null
	p.calm_left = 0.0
	p.block_count = 0
	p.look_target = 0.0
	p.wary = r["waryTime"] if r["waryTime"] > 0.0 else 0.0
	if p.sched != null:
		# Scheduled people re-plan the trip to their current stop from wherever the flight left them.
		p.sched["en"] = false
		p.sched["retarget"] = true
		p.seated = false
		p.state = "idle"
		p.idle_left = 0.0
		return
	if p.sit:
		p.idx = 0
		if n > 1 and sqrt((p.path[0]["x"] - p.x) * (p.path[0]["x"] - p.x) + (p.path[0]["y"] - p.y) * (p.path[0]["y"] - p.y)) > 0.05:
			p.state = "walk"
			return
		p.state = "idle"
		p.idle_left = p.path[0]["wait"]
		return
	if p.wary > 0.0 and n > 1:
		var g: int = lit_waypoint(p, p.flee_x, p.flee_y, r)
		if g < 0:
			g = farthest_waypoint(p, p.flee_x, p.flee_y)
		if g >= 0:
			p.idx = g
			p.state = "walk"
			return
	if n > 1:
		var a: Dictionary = p.path[p.idx]
		var b: Dictionary = p.path[(p.idx - p.fdir + n + n) % n]
		var da: float = (a["x"] - p.x) * (a["x"] - p.x) + (a["y"] - p.y) * (a["y"] - p.y)
		var db: float = (b["x"] - p.x) * (b["x"] - p.x) + (b["y"] - p.y) * (b["y"] - p.y)
		if db < da:
			p.idx = (p.idx - p.fdir + n + n) % n
		p.state = "walk"
	else:
		p.state = "idle"
		p.idle_left = p.path[0]["wait"]


## Advance all people by dt seconds (clamped to 0.1). ctx (optional): player {x, y}, playerLit, react, grace, nightFrac, fear, nightSec.
func update(w: World, dt_in: float, ctx: Variant = null) -> void:
	if not (dt_in > 0.0):
		return
	var dt: float = minf(dt_in, 0.1)
	var r: float = radius
	time += dt
	world = w
	var rpar := fill_react(ctx.get("react") if ctx is Dictionary else null)
	var pl: Variant = ctx.get("player") if ctx is Dictionary else null
	var has_player: bool = pl is Dictionary and is_finite(float(pl["x"])) and is_finite(float(pl["y"])) and not (ctx is Dictionary and float(ctx.get("grace", 0.0)) > 0.0)
	var lit: float = float(ctx["playerLit"]) if ctx is Dictionary and (ctx.get("playerLit") is float or ctx.get("playerLit") is int) else 0.0
	if ctx is Dictionary and (ctx.get("nightFrac") is float or ctx.get("nightFrac") is int) and is_finite(float(ctx["nightFrac"])):
		night_frac = float(ctx["nightFrac"])
	fear = float(ctx["fear"]) if ctx is Dictionary and (ctx.get("fear") is float or ctx.get("fear") is int) and is_finite(float(ctx["fear"])) else 0.0
	if ctx is Dictionary and (ctx.get("nightSec") is float or ctx.get("nightSec") is int) and is_finite(float(ctx["nightSec"])):
		night_sec = float(ctx["nightSec"])
	for p in people:
		if p.mode != p.mode_prev:
			p.mode_prev = p.mode
			p.mode_age = 0.0
		else:
			p.mode_age += dt
		p.ph0 = p.phase
	for p in people:
		if p.chat != null and (p.mode != "path" or p.wary > 0.0 or fear >= CHAT_FEAR or (p.chat["table"] and not (p.seated and not p.sched["en"]))):
			end_chat(p)
	chat_in -= dt
	if chat_in <= 0.0:
		chat_in = CHAT_SCAN
		scan_chats(w)
	for p in people:
		var mode: String = p.mode
		if mode == "fed" or mode == "grapple":
			continue
		if mode == "dazed":
			p.look_angle += (0.0 - p.look_angle) * minf(1.0, 4.0 * dt)
			p.phase *= maxf(0.0, 1.0 - 8.0 * dt)
			if p.phase < 0.01:
				p.phase = 0.0
			p.dazed_left -= dt
			p.whimper_in -= dt
			if p.whimper_in <= 0.0:
				p.whimper_in += WHIMPER_GAP
				push_event("whimper", p)
			if p.dazed_left <= 0.0:
				enter_flee(p, p.flee_x, p.flee_y, rpar, true)
			continue
		if p.wary > 0.0:
			p.wary = maxf(0.0, p.wary - dt)
		if mode == "startle" and p.bumping:
			p.look_angle += (0.0 - p.look_angle) * minf(1.0, 4.0 * dt)
			p.phase *= maxf(0.0, 1.0 - 8.0 * dt)
			if p.phase < 0.01:
				p.phase = 0.0
			p.mode_left -= dt
			if p.mode_left <= 0.0:
				p.bumping = false
				if has_player:
					enter_flee(p, float(pl["x"]), float(pl["y"]), rpar)
				else:
					p.mode = "path"
					p.state = p.pre_state
			continue
		var seen: int = is_seen_by(p, w, float(pl["x"]), float(pl["y"]), lit, rpar) if has_player else 0
		if mode == "path":
			if seen == 2 and rpar["bumpFreeze"] > 0.0:
				start_bump(p, float(pl["x"]), float(pl["y"]), rpar)
				continue
			if seen != 0:
				enter_flee(p, float(pl["x"]), float(pl["y"]), rpar)
				continue
			step_path(p, dt, r)
		elif mode == "startle":
			if seen != 0:
				enter_flee(p, float(pl["x"]), float(pl["y"]), rpar)
				continue
			p.look_angle += (0.0 - p.look_angle) * minf(1.0, 4.0 * dt)
			p.phase *= maxf(0.0, 1.0 - 8.0 * dt)
			if p.phase < 0.01:
				p.phase = 0.0
			p.mode_left -= dt
			if p.mode_left <= 0.0:
				p.mode = "path"
				p.state = p.pre_state
		else:
			# flee or cower
			if seen != 0:
				p.calm_left = rpar["calmAfter"]
				p.flee_x = float(pl["x"])
				p.flee_y = float(pl["y"])
			else:
				p.calm_left -= dt
				if p.calm_left <= 0.0:
					resume_path(p, rpar)
					continue
			if mode == "flee":
				step_flee(p, dt, r, rpar)
			else:
				p.look_angle += (0.0 - p.look_angle) * minf(1.0, 4.0 * dt)
				p.phase *= maxf(0.0, 1.0 - 8.0 * dt)
				if p.phase < 0.01:
					p.phase = 0.0
				p.angle = atan2(p.y - p.flee_y, p.x - p.flee_x)
				p.whimper_in -= dt
				if p.whimper_in <= 0.0:
					p.whimper_in += WHIMPER_GAP
					push_event("whimper", p)
	for p in people:
		var d: float = p.phase - p.ph0
		p.phase_rate = d / dt if d > 0.0 and d < 10.0 else 0.0


## A sound at (x, y): people in path mode within startleDist freeze and turn toward it; if the player is lit and visible they flee.
func react(x: float, y: float, kind: String, ctx: Variant = null, dist: float = 0.0) -> void:
	if world == null or not is_finite(x) or not is_finite(y):
		return
	var rpar := fill_react(ctx.get("react") if ctx is Dictionary else null)
	if dist > 0.0 and is_finite(dist):
		rpar["startleDist"] = dist
	var pl: Variant = ctx.get("player") if ctx is Dictionary else null
	var has_player: bool = pl is Dictionary and is_finite(float(pl["x"])) and is_finite(float(pl["y"])) and not (ctx is Dictionary and float(ctx.get("grace", 0.0)) > 0.0)
	var lit: float = float(ctx["playerLit"]) if ctx is Dictionary and (ctx.get("playerLit") is float or ctx.get("playerLit") is int) else 0.0
	var r2: float = rpar["startleDist"] * rpar["startleDist"]
	for p in people:
		if p.mode != "path":
			continue
		var dx: float = p.x - x
		var dy: float = p.y - y
		if dx * dx + dy * dy > r2:
			continue
		var sees_you := false
		if has_player and lit >= rpar["lightSeen"]:
			var sd: float = rpar["seeDist"]
			if p.wary > 0.0:
				rpar["seeDist"] = sd * WARY_SEE_MUL
			sees_you = sees(p, world, float(pl["x"]), float(pl["y"]), rpar)
			rpar["seeDist"] = sd
		if sees_you:
			enter_flee(p, float(pl["x"]), float(pl["y"]), rpar)
			continue
		if p.chat != null:
			end_chat(p)
		p.mode = "startle"
		p.mode_left = rpar["startleTime"]
		p.pre_state = p.state
		p.state = "idle"
		p.angle = atan2(y - p.y, x - p.x)
		push_event("startle", p)


## Events since the last call; clears them.
func drain_events() -> Array:
	var out := events
	events = []
	return out


func clear_echoes() -> void:
	echoes.clear()


static func is_feedable(person: Person) -> bool:
	return person != null and person.feedable and (person.mode == "path" or person.mode == "startle" or person.mode == "flee" or person.mode == "cower" or person.mode == "dazed")


func find_person(id: int) -> Person:
	for p in people:
		if p.id == id:
			return p
	return null


## Grab person id for drinking: becomes inert "grapple".
func grab(id: int) -> bool:
	var p := find_person(id)
	if p == null or not is_feedable(p):
		return false
	p.mode = "grapple"
	p.bumping = false
	p.state = "idle"
	p.phase = 0.0
	p.mode_left = 0.0
	p.block_count = 0
	return true


## Release a grappled person: "dazed" for dazedTime, then flees quietly from (from_x, from_y).
func release(id: int, from_x: float, from_y: float) -> bool:
	var p := find_person(id)
	if p == null or p.mode != "grapple":
		return false
	if is_finite(from_x) and is_finite(from_y):
		p.flee_x = from_x
		p.flee_y = from_y
	var dz: float = rp["dazedTime"] if rp.has("dazedTime") and rp["dazedTime"] >= 0.0 else REACT_DEFAULTS["dazedTime"]
	p.mode = "dazed"
	p.state = "idle"
	p.dazed_left = dz
	p.whimper_in = WHIMPER_GAP
	p.phase = 0.0
	return true


## Drain amount from person id's blood pool. Returns the new left (>= 0), or -1 for an unknown person.
func drink(id: int, amount: float) -> float:
	var p := find_person(id)
	if p == null:
		return -1.0
	if is_finite(amount) and amount > 0.0:
		p.left = maxf(0.0, p.left - amount)
	return p.left


## Nearest feedable person within reach of (x, y) and within +-arc of angle, or null.
func feed_target(x: float, y: float, ang: float, reach: float = 1.5, arc: float = PI / 3.0) -> Person:
	if not (is_finite(x) and is_finite(y) and is_finite(ang)):
		return null
	var rch: float = reach if reach > 0.0 else 1.5
	var ar: float = arc if arc > 0.0 else PI / 3.0
	var best: Person = null
	var best_d := INF
	for p in people:
		if not is_feedable(p):
			continue
		var dx: float = p.x - x
		var dy: float = p.y - y
		var d: float = sqrt(dx * dx + dy * dy)
		if d > rch:
			continue
		if d > 1e-6 and absf(norm_diff(atan2(dy, dx) - ang)) > ar:
			continue
		if d < best_d:
			best_d = d
			best = p
	return best


## Mark person id as fed: inert for the rest of the night.
func mark_fed(id: int) -> bool:
	var p := find_person(id)
	if p == null:
		return false
	p.mode = "fed"
	p.state = "idle"
	p.phase = 0.0
	p.mode_left = 0.0
	return true


## Lit height band [zMin, zMax] of a person at (x, y) once pulse pu has reached its full radius (js heightBandOf).
static func height_band_of(pu: Sonar.Pulse, x: float, y: float) -> PackedFloat64Array:
	var t_full: float = pu.t0 + pu.range / pu.speed
	var hb := Sonar.height_band(pu, t_full, x, y)
	var out := PackedFloat64Array([0.0, 1.2])
	if hb.is_empty():
		# Person sits at the very edge of the ring: only a thin slice at the source height.
		out[0] = maxf(0.0, pu.z - 0.15)
		out[1] = minf(1.2, pu.z + 0.15)
	else:
		out[0] = hb[0]
		out[1] = hb[1]
	if (pu.kind == "step" or pu.kind == "personStep") and out[1] > 0.22:
		out[1] = 0.22
	if pu.kind == "vheart":
		out[0] = 0.45
		out[1] = 0.85
	return out


## Record echo snapshots for every person a wavefront crossed between t_prev and t. Returns the new echoes.
func update_echoes(sonar: Sonar, t_prev: float, t: float) -> Array[Echo]:
	var made: Array[Echo] = []
	for pu in sonar.pulses:
		var str_: float = pu.strength
		if str_ <= 0.01:
			continue
		for p in people:
			var ex: float = p.x - pu.x
			var ey: float = p.y - pu.y
			if ex * ex + ey * ey > pu.range * pu.range:
				continue
			var la: float = Sonar.lit_at(pu, p.x, p.y)
			var lo: bool = la > t_prev
			if not (lo and la <= t):
				continue
			var dist: float = (la - pu.t0) * pu.speed
			if dist > pu.range:
				continue
			if str_ < 0.12 and dist > 6.0:
				continue
			if not Sonar.visible_from(pu, p.x, p.y):
				continue
			var strength: float = minf(1.0, (1.0 - 0.5 * dist / pu.range) * str_ * Sonar.beam_at(pu, atan2(ey, ex)))
			var dup := -1
			var m: int = echoes.size() - 1
			while m >= 0:
				if echoes[m].person_id == p.id and absf(echoes[m].t - la) < 0.5 and (echoes[m].kind == "vheart") == (pu.kind == "vheart"):
					dup = m
					break
				m -= 1
			if dup >= 0 and echoes[dup].strength >= strength:
				continue
			var band := height_band_of(pu, p.x, p.y)
			var efade: float = pu.fade if pu.fade > 0.0 else (sonar.fade if sonar.fade > 0.0 else 3.0)
			if dup >= 0:
				var old: Echo = echoes[dup]
				band[0] = minf(band[0], old.z_min)
				band[1] = maxf(band[1], old.z_max)
			var e := Echo.new()
			e.person_id = p.id
			e.kind = pu.kind
			e.x = p.x
			e.y = p.y
			e.angle = p.angle
			e.look_angle = p.look_angle
			e.phase = p.phase
			e.moving = p.state == "walk"
			e.t = la
			e.dist = dist
			e.strength = strength
			e.look = p.look
			e.theta = atan2(ey, ex) - pu.facing if pu.has_facing else 0.0
			e.z_min = band[0]
			e.z_max = band[1]
			e.fade = efade
			e.mode = p.mode
			e.sit = p.sit or p.seated
			e.wary = p.wary > 0.0
			e.chat = p.chat != null
			e.mode_age = p.mode_age
			e.phase_rate = p.phase_rate
			if dup >= 0:
				echoes.remove_at(dup)
			echoes.append(e)
			made.append(e)
	var fade: float = sonar.fade if sonar != null else 3.0
	var keep: Array[Echo] = []
	for e in echoes:
		var life: float = e.fade if e.fade > 0.0 else fade
		if t - e.t < life:
			keep.append(e)
	echoes = keep
	var hearts := 0
	for e in echoes:
		if e.kind == "vheart":
			hearts += 1
	while echoes.size() - hearts > max_echoes:
		var gone := -1
		for i in echoes.size():
			if echoes[i].kind != "vheart":
				gone = i
				break
		if gone < 0:
			break
		echoes.remove_at(gone)
	while hearts > 8:
		var gone2 := -1
		for i in echoes.size():
			if echoes[i].kind == "vheart":
				gone2 = i
				break
		if gone2 < 0:
			break
		echoes.remove_at(gone2)
		hearts -= 1
	return made


## Foot-plant events since the last call: [{x, y, id, gait, pace, angle, foot}] (two per walk cycle, none while idle).
func step_events() -> Array:
	var out: Array = []
	for p in people:
		var todo: int = mini(4, p.steps - p.steps_reported)
		p.steps_reported = p.steps
		for k in todo:
			var gait := "walk"
			if p.mode == "flee":
				gait = "run"
			elif p.gait == "mail":
				gait = "mail"
			elif p.wary > 0.0:
				gait = "sneak"
			out.append({"x": p.x, "y": p.y, "id": p.id, "angle": p.angle, "foot": (p.steps - todo + k) & 1, "gait": gait, "pace": p.speed / DEFAULT_SPEED})
	return out


## Brightness 0..1 of an echo snapshot at time t.
static func echo_brightness(echo: Echo, t: float, fade: float) -> float:
	var f: float = echo.fade if echo.fade > 0.0 else fade
	var age: float = t - echo.t
	if age < 0.0 or age >= f:
		return 0.0
	return pow(1.0 - age / f, 1.4) * echo.strength


static func echo_age(echo: Echo, t: float) -> float:
	return t - echo.t


## Who a villager is talking to: {partner, kind, mood} or null. Mood hint: warm | neutral | curt | hushed (fear up).
func conversation_for(id: int) -> Variant:
	var p := find_person(id)
	if p == null or p.chat == null:
		return null
	var c: Dictionary = p.chat
	return {"partner": c["partner"], "kind": c["kind"], "mood": "hushed" if fear >= 1.5 else c["mood"]}


## Mid-night spawn. spec {archetype, seed?, home?, ang?}; at {x, y}. Returns {ok, code, id}.
func spawn(w: World, spec: Variant, at: Variant) -> Dictionary:
	if not (spec is Dictionary) or not (spec.get("archetype") is String) or not (at is Dictionary):
		return {"ok": false, "code": "E_PEOPLE_ARGS", "id": -1}
	var ax: float = float(at["x"]) if at.get("x") is float or at.get("x") is int else NAN
	var ay: float = float(at["y"]) if at.get("y") is float or at.get("y") is int else NAN
	if not is_finite(ax) or not is_finite(ay):
		return {"ok": false, "code": "E_PEOPLE_ARGS", "id": -1}
	var ww: World = w if w != null else world
	if people.size() >= MAX_PEOPLE:
		return {"ok": false, "code": "E_FORGE_LIMIT", "id": -1}
	if ww == null or ww.is_solid(ax, ay):
		return {"ok": false, "code": "E_PEOPLE_SOLID", "id": -1}
	var raw: float = float(spec["seed"]) if spec.get("seed") is float or spec.get("seed") is int else NAN
	var sd: float = fposmod(floor(absf(raw)), 4294967296.0) if is_finite(raw) else 0.0
	var sdi: int = int(sd)
	var entry: int = ((sdi >> 16) ^ sdi) & 0xFFFF
	var gen := Forge.generate({"archetype": spec["archetype"], "seed": entry, "home": spec.get("home")}, {"stateSeed": seed_value, "index": float(next_id), "accOffset": float(acc_offset)})
	if not gen["ok"] or gen["person"] == null:
		return {"ok": false, "code": gen["code"] if gen["code"] != "OK" else "E_FORGE_UNKNOWN", "id": -1}
	var gp: Dictionary = gen["person"]
	var prng := Rng.new(sd)
	var pmin: float = pool_min if pool_min > 0.0 else 30.0
	var pmax: float = pool_max if pool_max > 0.0 else maxf(pmin, 50.0)
	var pool: float = pmin + (pmax - pmin) * prng.next()
	var id: int = next_id
	next_id += 1
	var arch: Variant = Forge.archetype(gp["archetype"])
	var speed: float = float(arch["speed"]) if arch != null and (arch.get("speed") is float or arch.get("speed") is int) and float(arch["speed"]) > 0.0 else DEFAULT_SPEED
	var ang: float = float(spec["ang"]) if spec.get("ang") is float or spec.get("ang") is int else 0.0
	var p := Person.new()
	p.pool = pool
	p.left = pool
	p.role = gp["role"]
	p.archetype = gp["archetype"]
	p.watch = bool(gp["watch"])
	p.feedable = gp["feedable"] != false
	p.gait = gp["gait"]
	p.id = id
	p.x = ax
	p.y = ay
	p.angle = ang
	p.speed = speed
	p.path = [{"x": ax, "y": ay, "wait": DEFAULT_WAIT}]
	p.idx = 0
	p.idle_left = DEFAULT_WAIT
	p.look_in = 0.5 + prng.next() * 0.6
	p.look = gp["look"]
	if gp["schedRole"] != null and Schedule.has_role(gp["schedRole"]):
		p.sched = Schedule.make(gp["schedRole"], places, {"x": ax, "y": ay}, prng, {"home": gp["home"], "slot": id})
		if p.sched != null:
			p.idle_left = 0.0
			face_tables(p.sched, map_def)
	people.append(p)
	forge_log["spawned"].append({"a": gp["archetype"], "s": sd, "x": ax, "y": ay, "ang": ang, "id": id})
	return {"ok": true, "code": "OK", "id": id}


## Remove a person (not while grappled, dazed or fed). Their echoes stay.
func despawn(id: int) -> Dictionary:
	var p := find_person(id)
	if p == null:
		return {"ok": false, "code": "E_PEOPLE_NONE"}
	if p.mode == "grapple" or p.mode == "dazed" or p.mode == "fed":
		return {"ok": false, "code": "E_FORGE_BUSY"}
	if p.chat != null:
		end_chat(p)
	people.erase(p)
	forge_log["spawned"] = forge_log["spawned"].filter(func(e): return int(e["id"]) != id)
	forge_log["altered"] = forge_log["altered"].filter(func(e): return int(e["id"]) != id)
	return {"ok": true, "code": "OK"}


## Patch a person look through Forge.alter. The look is replaced by a new Dictionary; old echoes keep the old one.
func alter(id: int, patch: Variant) -> Dictionary:
	var p := find_person(id)
	if p == null:
		return {"ok": false, "code": "E_PEOPLE_NONE"}
	var r := Forge.alter(p.look, patch)
	if not r["ok"]:
		return {"ok": false, "code": r["code"] if r["code"] != "OK" else "E_FORGE_TYPE"}
	p.look = r["look"]
	var ch := {}
	for k in r["changed"]:
		ch[k] = r["look"][k]
	var e: Variant = null
	for it in forge_log["altered"]:
		if int(it["id"]) == id:
			e = it
	if e != null:
		e["look"].merge(ch, true)
	elif forge_log["altered"].size() < 16:
		forge_log["altered"].append({"id": id, "look": ch})
	return {"ok": true, "code": "OK"}


## Compact record of mid-night spawns and look alters for the run snapshot; altered ids are renumbered to the ids a replay
## assigns (base_count + spawn index).
func forge_state() -> Dictionary:
	var remap := {}
	var i := 0
	for e in forge_log["spawned"]:
		remap[int(e["id"])] = base_count + i
		i += 1
	var spawned: Array = []
	for e in forge_log["spawned"]:
		spawned.append({"a": e["a"], "s": e["s"], "x": e["x"], "y": e["y"], "ang": e["ang"]})
	var altered: Array = []
	for e in forge_log["altered"]:
		altered.append({"id": remap.get(int(e["id"]), int(e["id"])), "look": e["look"].duplicate()})
	return {"spawned": spawned, "altered": altered}
