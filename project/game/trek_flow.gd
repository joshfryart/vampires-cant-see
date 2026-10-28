class_name TrekFlow
extends RefCounted
## The roguelike trek (run) flow as a headless state machine (docs/ROGUELIKE.md). It owns the night clock, blood, Heat, miles, deaths,
## the day choice (sleep / wait), checkpoints and the Laid to Rest result. It never touches Game: WP9 feeds it the player's cell and
## reads events and descriptors back. Classic Night/Hunger logic is reused unchanged; upgrades come from TrekMeta.effects(meta).
##
## State (`state`): "playing" (night, or day on a roofed cell with no choice pending) | "choice" (day has come, player is roofed:
## sleep at a rest spot or wait it out) | "dead" (cause set; call end_run) | "ended" (result built, checkpoint cleared).
##
## Construct: TrekFlow.begin(meta, seed, store) / TrekFlow.continue_from(trek_save, meta, store). `store` is an optional
## SaveCodec.Store (checkpoints write kind "trek", end_run writes kind "rogue" and removes "trek"). `meta` is the TrekMeta dict
## (the SAME object Menus.trek_meta uses: end_run mutates it).
## Drive: step(dt, cell, on_outdoor, ctx) -> Array of events {type, ...}. ctx keys (all optional): player_pos Vector2, holy bool
## (default: world kind at the cell == "holy"), mist bool (Mist active: hunters cannot stake), hunters [{x, y, noticing := true}].
## Event types: chime, washout, dawn_warning {left}, dawn, needs_choice, dusk {heat, hunters}, withering {left}, stake_hit {blood},
## stake_ignored, holy, revived {cell}, death {cause}.

const GENERATORS := ["cave", "wood", "moor", "road", "inn"]
const START_BLOOD := 60.0
const WARN_SEC := 90.0
const WITHER_SEC := 25.0
const STAKE_DIST := 1.2
const STAKE_DMG := 45.0
const STAKE_CD := 3.0
const HOLY_DPS := 8.0
const REVIVE_BLOOD := 30.0
const SUB_STEP := 0.1
const MAX_HEAT_HUNTERS := 2
const SAVE_EXTRA := "trek"

var meta: Dictionary = {}
var fx: Dictionary = {}
var store: Object = null
var seed: int = 0
var leg: int = 0
var cleared_miles: float = 0.0
var progress: float = 0.0
var heat: int = 0
var night: Night = null
var hunger: Hunger = null
var deaths_avoided: int = 0
var humans_fed: int = 0
var critters_fed: int = 0
var senses: int = 0               ## Sense uses this run (additive, optional key in the night.trek extension)
## Repeat run: the Long Night tutorial was done when this trek began, so stages that have a short form use it (the brief Hollow: no filler
## chambers, beats closer together). Fixed for the whole trek and saved (night.trek "brief", written only when true) so a continue
## regenerates the very same layout even if the tutorial flag changed since.
var brief: bool = false
var stages_unseen: int = 0
var noticed: bool = false
var state: String = "idle"
var cause: String = ""
var result: Dictionary = {}
var stage_id: String = ""
var row: Dictionary = {}
var def: Dictionary = {}
var world: World = null
var dist: PackedInt32Array = PackedInt32Array()
var entry_dist: int = 0
var start_cell: Vector2i = Vector2i.ZERO
var exit_cell: Vector2i = Vector2i.ZERO
var last_rest: Vector2i = Vector2i.ZERO
var at_cell: Vector2i = Vector2i.ZERO
var player_pos: Vector2 = Vector2.ZERO
var day_t: float = 0.0
var cleared: Array = []
var reached: Array = []
var descriptor: Dictionary = {}
var people: People = null         ## optional occupants for the wait / sleep sim (null in the cave)
var critter_sys: Critters = null
var emitter: Callable = Callable()
var _warned: bool = false
var _wither_t: float = 0.0
var _stake_cd: float = 0.0
var _stake_ignored: int = 0
var _stage_done: bool = false
var _wait: WaitDay = null
## Spawn indices (into descriptor["critters"]) of prey eaten on this stage: continue must not respawn them (saved in night.trek).
var eaten: Array = []
var _ck_at: Vector2i = Vector2i.ZERO   ## the last checkpoint position (stage entry or the rest spot slept at)
var _revived: bool = false


# ---------------------------------------------------------------- construction

## Start a new trek at the first stage. Returns null if the stage cannot be generated.
static func begin(meta_: Dictionary, seed_: int, store_: Object = null) -> TrekFlow:
	var f := TrekFlow.new()
	f.meta = meta_
	f.store = store_
	f.seed = seed_ & JsMath.M32
	f.fx = TrekMeta.effects(meta_)
	f.brief = meta_.get("tutorialDone", false) == true
	f.night = f._make_night()
	f.hunger = Hunger.create()
	var order := stage_order()
	var d := f.enter_stage(order[0] if order.size() > 0 else "hollow")
	return f if d.get("ok", false) else null


## Resume from a "trek" save (validated and cleaned by SaveCodec.sanitize_trek). Null when invalid. The stage is regenerated from
## (seed, leg); the player starts at the checkpoint cell (stage entry or the rest spot slept at).
static func continue_from(save: Variant, meta_: Dictionary, store_: Object = null) -> TrekFlow:
	var s: Variant = SaveCodec.sanitize_trek(save)
	if s == null:
		return null
	var f := TrekFlow.new()
	f.meta = meta_
	f.store = store_
	f.fx = TrekMeta.effects(meta_)
	f.seed = int(s["seed"])
	f.leg = int(s["leg"])
	f.cleared_miles = float(s["miles"])
	f.progress = float(s["progress"])
	f.heat = int(floor(float(s["heat"])))
	f.deaths_avoided = int(s["deathsAvoided"])
	var nd: Dictionary = (s["night"] as Dictionary).duplicate(true) if s["night"] is Dictionary else {}
	var ex: Dictionary = nd.get(SAVE_EXTRA, {}) if nd.get(SAVE_EXTRA) is Dictionary else {}
	nd.erase(SAVE_EXTRA)
	var proto := f._make_night()
	f.night = Night.restore(nd, {"nightSec": proto.night_sec, "nights": 1000, "bloodMax": proto.blood_max, "drainMul": proto.drain_mul}) if not nd.is_empty() else null
	if f.night == null:
		return null
	f.hunger = Hunger.restore(s["hunger"]) if s["hunger"] != null else null
	if f.hunger == null:
		f.hunger = Hunger.create()
	f.humans_fed = int(ex.get("humans", 0))
	f.critters_fed = int(ex.get("critters", 0))
	f.stages_unseen = int(ex.get("unseenStages", 0))
	f.senses = clampi(int(ex.get("senses", 0)), 0, 100000)
	f.brief = ex.get("brief", false) == true   # older saves (and first-run treks) have no key: the full layout they were made with
	f.noticed = bool(ex.get("noticed", false))
	f.day_t = float(ex.get("day_t", 0.0))
	f._stake_ignored = int(ex.get("stakeIgnored", 0))
	f.cleared = (ex.get("cleared", []) as Array).duplicate() if ex.get("cleared") is Array else []
	f.reached = (ex.get("reached", []) as Array).duplicate() if ex.get("reached") is Array else []
	f._warned = bool(ex.get("warned", false))
	f._wither_t = maxf(0.0, float(ex.get("wither_t", 0.0)))
	if ex.get("eaten") is Array:
		for i in ex["eaten"]:
			if (i is int or i is float) and f.eaten.size() < 256 and int(i) >= 0 and not f.eaten.has(int(i)):
				f.eaten.append(int(i))
	var st := String(ex.get("state", "playing"))
	if not _load_stage_ok(f, String(s["stage"])):
		return null
	f.night.drain_mul = float(f.row.get("drainMul", 1.0)) * float(f.fx["drain"])
	f.state = st if st == "choice" else "playing"
	f.at_cell = _cell_of(ex.get("at"), f.start_cell)
	f.last_rest = _cell_of(ex.get("rest"), f.start_cell)
	f.player_pos = Vector2(f.at_cell.x + 0.5, f.at_cell.y + 0.5)
	f.descriptor = f._descriptor()
	f.descriptor["start"] = f.at_cell
	f._ck_at = f.at_cell
	return f


static func _load_stage_ok(f: TrekFlow, id: String) -> bool:
	return f._load_stage(id)


static func _cell_of(v: Variant, fallback: Vector2i) -> Vector2i:
	if v is Array and v.size() >= 2:
		return Vector2i(int(v[0]), int(v[1]))
	return fallback


# ---------------------------------------------------------------- stage data

static func stage_order() -> Array:
	var d: Variant = GameData.load_rogue("stages")
	var out: Array = []
	if d is Dictionary and d.get("order") is Array:
		for id in d["order"]:
			out.append(String(id))
	elif d is Dictionary and d.get("stages") is Array:
		for r in d["stages"]:
			out.append(String(r.get("id", "")))
	return out


static func has_generator(id: String) -> bool:
	var r := StageGen.stage_row(id)
	return not r.is_empty() and GENERATORS.has(String(r.get("generator", "")))


## The stage after `id`: the row's `next`, else the next entry of the order list, else "".
static func next_stage_id(id: String) -> String:
	var r := StageGen.stage_row(id)
	if r.has("next"):
		return String(r["next"])
	var order := stage_order()
	var i := order.find(id)
	return String(order[i + 1]) if i >= 0 and i + 1 < order.size() else ""


static func stage_seed(seed_: int, leg_: int) -> int:
	return (seed_ + leg_ * 7919) & JsMath.M32


static func hunters_for_heat(h: int) -> int:
	return 0 if h < 2 else mini(MAX_HEAT_HUNTERS, h - 1)


func hunters_wanted() -> int:
	return int(row.get("hunterBase", 0)) + hunters_for_heat(heat)


func _make_night() -> Night:
	var mx: float = 100.0 + float(fx["bloodMax"])
	var n := Night.create({
		"nightSec": float(Night.DEFAULTS["nightSec"]) * float(fx["nightLen"]), "nights": 1000, "bloodMax": mx,
		"bloodStart": minf(mx, START_BLOOD + float(fx["startBlood"])), "drainMul": float(fx["drain"]),
	})
	return n


func _load_stage(id: String) -> bool:
	row = StageGen.stage_row(id)
	if row.is_empty() or not GENERATORS.has(String(row.get("generator", ""))):
		return false
	def = StageGen.generate(id, stage_seed(seed, leg), brief)
	if def.is_empty():
		return false
	stage_id = id
	world = World.from_def(def)
	var ex: Array = def["exit"]["cell"]
	exit_cell = Vector2i(int(ex[0]), int(ex[1]))
	var sc: Array = def["start"]["cell"]
	start_cell = Vector2i(int(sc[0]), int(sc[1]))
	dist = RunFlow.bfs_cells(world, exit_cell.x, exit_cell.y)
	entry_dist = maxi(1, dist[start_cell.y * world.width + start_cell.x])
	return true


## Enter a stage: generate it, reset the clock to dusk and Heat to 0, checkpoint. Returns the descriptor
## {ok, stage, name, index, def, map_name, start (Vector2i), angle, exit{door, cell, arrival, toMap}, card, drain_mul, hunters,
## entry_dist, rest, pockets, critters, lights, ambient, seed, miles}; {ok: false, frontier: true} when the stage has no generator yet.
func enter_stage(id: String) -> Dictionary:
	if not has_generator(id):
		return {"ok": false, "frontier": true, "stage": id}
	if not _load_stage(id):
		return {"ok": false, "stage": id}
	night.drain_mul = float(row.get("drainMul", 1.0)) * float(fx["drain"])
	night.min = 0.0
	night.fired = {"chime": false, "washout": false, "dawn": false}
	night.status = "night"
	night.reason = ""
	heat = 0
	progress = 0.0
	noticed = false
	day_t = 0.0
	_warned = false
	_wither_t = 0.0
	_stake_cd = 0.0
	_stage_done = false
	_wait = null
	eaten = []
	state = "playing"
	last_rest = start_cell
	at_cell = start_cell
	player_pos = Vector2(start_cell.x + 0.5, start_cell.y + 0.5)
	if not reached.has(id):
		reached.append(id)
	descriptor = _descriptor()
	checkpoint()
	return descriptor


func _descriptor() -> Dictionary:
	return {
		"ok": true, "stage": stage_id, "name": String(row.get("name", stage_id)), "index": int(row.get("index", leg + 1)), "def": def,
		"map_name": String(def.get("name", stage_id)), "start": start_cell, "angle": float(def["start"].get("angle", 0.0)),
		"exit": {"door": def["exit"]["door"], "cell": exit_cell, "arrival": def["exit"]["arrival"], "toMap": def["exit"]["toMap"]},
		"card": stage_card(), "drain_mul": night.drain_mul, "hunters": hunters_wanted(), "entry_dist": entry_dist,
		"rest": def.get("rest", []), "pockets": def.get("pockets", []), "critters": def.get("critters", []), "lights": def.get("lights", []),
		"ambient": def.get("ambient", []), "seed": stage_seed(seed, leg), "miles": miles(),
	}


## Args for TrekUi.show_stage_card(index, stage_name, miles, time_of_day, seconds).
func stage_card() -> Dictionary:
	return {"index": int(row.get("index", leg + 1)), "stage_name": String(row.get("name", stage_id)), "miles": cleared_miles, "time_of_day": "dusk", "seconds": 4.0}


# ---------------------------------------------------------------- position, miles, clock

func _idx(c: Vector2i) -> int:
	return c.y * world.width + c.x


## Distance (BFS cells) from the exit door; -1 when unreachable or outside the map.
func dist_to_exit(c: Vector2i) -> int:
	if world == null or c.x < 0 or c.y < 0 or c.x >= world.width or c.y >= world.height:
		return -1
	return dist[_idx(c)]


const _DOWNHILL := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]


## The cell `k` steps along the shortest way to the exit: walks the `dist` field downhill (first neighbour in the fixed order
## E, W, S, N with the strictly lowest distance, so it is deterministic). Result: k steps closer, or the exit cell itself when it is
## fewer than k steps away. A cell with no distance (rock, outside, unreachable) returns itself. Wayfinding (draft, breath, Sense) reads this.
func next_toward_exit(cell: Vector2i, k: int) -> Vector2i:
	var d := dist_to_exit(cell)
	if d < 0:
		return cell
	var cur := cell
	var left := k
	while left > 0 and d > 0:
		var best := cur
		var bd := d
		for o in _DOWNHILL:
			var n: Vector2i = cur + o
			var dn := dist_to_exit(n)
			if dn >= 0 and dn < bd:
				best = n
				bd = dn
		if best == cur:
			break
		cur = best
		d = bd
		left -= 1
	return cur


## Record the player's cell; progress only ever rises. Returns the best progress.
func update_position(c: Vector2i, pos: Vector2 = Vector2.INF) -> float:
	at_cell = c
	player_pos = pos if pos != Vector2.INF else Vector2(c.x + 0.5, c.y + 0.5)
	var d := dist_to_exit(c)
	if d >= 0:
		progress = maxf(progress, clampf(1.0 - float(d) / float(entry_dist), 0.0, 1.0))
	return progress


func at_exit(c: Vector2i) -> bool:
	var d := dist_to_exit(c)
	return d >= 0 and d <= 1


## Miles from the Coffin: cleared stages plus this stage's miles x best progress.
func miles() -> float:
	return cleared_miles + (0.0 if _stage_done else float(row.get("miles", 0.0)) * progress)


func note_rest(c: Vector2i) -> void:
	last_rest = c


func cell_outdoor(c: Vector2i) -> bool:
	return world != null and world.kind_at(c.x + 0.5, c.y + 0.5) == "outdoor"


## Seconds until dawn (0 once it is day).
func dawn_in() -> float:
	if night.status != "night":
		return 0.0
	return (Night.NIGHT_MIN - night.min) / Night.NIGHT_MIN * night.night_sec


func dawn_warning() -> bool:
	return night.status == "night" and dawn_in() <= WARN_SEC


func needs_choice() -> bool:
	return state == "choice"


func alive() -> bool:
	return state == "playing" or state == "choice"


func blood() -> float:
	return night.blood


func drain_rate() -> float:
	return night.blood_max / night.night_sec * night.drain_mul


func on_notice(_by: int = -1) -> void:
	noticed = true


# ---------------------------------------------------------------- stepping

func step(dt: float, player_cell: Vector2i, on_outdoor: bool, ctx: Dictionary = {}) -> Array:
	var ev: Array = []
	if not alive() or not is_finite(dt) or bool(ctx.get("frozen", false)):
		return ev   # frozen: a prompt is open, the world holds still (no clock, drain, stakes or withering)
	var pp: Variant = ctx.get("player_pos")
	update_position(player_cell, pp if pp is Vector2 else Vector2.INF)
	var left := maxf(0.0, dt)
	while left > 1e-9 and alive():
		var d := minf(SUB_STEP, left)
		left -= d
		_sub(d, on_outdoor, ctx, ev)
		if _revived:
			break   # the caller teleports the player to the rest spot; its cell for the rest of this dt is stale
	_revived = false
	return ev


func _sub(d: float, outdoor: bool, ctx: Dictionary, ev: Array) -> void:
	var nev := night.update(d, {"outdoor": outdoor})
	for e in nev:
		match e:
			"chime", "washout":
				ev.append({"type": e})
			"dawn":
				if night.status != "lost":
					state = "choice"
					day_t = 0.0
					ev.append({"type": "dawn"})
					ev.append({"type": "needs_choice"})
			"lost":
				_die("sun", ev)
				return
	if not _warned and night.status == "night" and dawn_in() <= WARN_SEC:
		_warned = true
		ev.append({"type": "dawn_warning", "left": dawn_in()})
	if night.status == "day" and state == "choice":
		day_t += d
		if day_t >= float(WaitDay.load_params()["day_sec"]):
			_new_night(1, ev)
			return
	var ppos: Vector2 = player_pos
	# holy ground
	var holy: bool = bool(ctx["holy"]) if ctx.has("holy") else (world != null and world.kind_at(ppos.x, ppos.y) == "holy")
	if holy:
		night.blood = maxf(0.0, night.blood - HOLY_DPS * d)
		ev.append({"type": "holy"})
		if night.blood <= 0.0:
			_die("holy", ev)
			return
	# hunters
	_stake_cd = maxf(0.0, _stake_cd - d)
	var hs: Variant = ctx.get("hunters")
	if hs is Array and not bool(ctx.get("mist", false)) and _stake_cd <= 0.0:
		for h in hs:
			if not (h is Dictionary) or not bool(h.get("noticing", true)):
				continue
			if Vector2(float(h["x"]), float(h["y"])).distance_to(ppos) > STAKE_DIST:
				continue
			_stake_cd = STAKE_CD
			if _stake_ignored < int(floor(float(fx["stakeResist"]))):
				_stake_ignored += 1
				ev.append({"type": "stake_ignored"})
			else:
				night.blood = maxf(0.0, night.blood - STAKE_DMG)
				ev.append({"type": "stake_hit", "blood": night.blood})
				if night.blood <= 0.0:
					_die("staked", ev)
					return
			break
	# withering
	if night.blood <= 0.0:
		var span: float = WITHER_SEC / maxf(0.01, float(fx["witherSlow"]))
		if _wither_t <= 0.0:
			ev.append({"type": "withering", "left": span})
		_wither_t += d
		if _wither_t >= span:
			_die("withered", ev)
	else:
		_wither_t = 0.0


func withering_left() -> float:
	if night == null or night.blood > 0.0:
		return -1.0
	return maxf(0.0, WITHER_SEC / maxf(0.01, float(fx["witherSlow"])) - _wither_t)


func _die(why: String, ev: Array) -> void:
	if int(floor(float(fx["secondCoffin"]))) >= 1 and deaths_avoided < 1:
		deaths_avoided += 1
		night.blood = minf(night.blood_max, REVIVE_BLOOD)
		_wither_t = 0.0
		_stake_cd = STAKE_CD
		night.reason = ""
		night.status = "day" if night.min >= Night.NIGHT_MIN else "night"
		state = "choice" if night.status == "day" else "playing"
		at_cell = last_rest
		player_pos = Vector2(last_rest.x + 0.5, last_rest.y + 0.5)
		_revived = true
		ev.append({"type": "revived", "cell": last_rest, "was": why})
		if state == "choice":
			ev.append({"type": "needs_choice"})
		return
	state = "dead"
	cause = why
	ev.append({"type": "death", "cause": why})


## A new night of the same stage: Heat up, clock back to dusk. (Prey does not respawn: the caller keeps its critters.)
func _new_night(heat_add: int, ev: Array) -> void:
	night.sleep()
	night.status = "night"
	heat += maxi(0, heat_add)
	day_t = 0.0
	_warned = false
	_wither_t = 0.0
	_wait = null
	state = "playing"
	ev.append({"type": "dusk", "heat": heat, "hunters": hunters_wanted()})


# ---------------------------------------------------------------- the day: sleep or wait

func _rng_for_day() -> Rng:
	return Rng.new(float((seed + leg * 131 + night.night * 17 + heat * 7 + 1) & JsMath.M32))


## Sleep at a rest spot (cell of an entry in descriptor["rest"]; roofed by construction). Skips to dusk at the sleep drain, rolls
## discovery by the spot's safety, adds Heat, then checkpoints. Returns {ok, result: dusk|noticed|withered, events, heat, blood}.
func sleep_at_rest(cell: Vector2i) -> Dictionary:
	if state != "choice":
		return {"ok": false, "code": "not_day"}
	var spot: Variant = null
	for r in def.get("rest", []):
		if int(r["cell"][0]) == cell.x and int(r["cell"][1]) == cell.y:
			spot = r
	if spot == null:
		return {"ok": false, "code": "not_rest"}
	var wd := WaitDay.new(world, people, critter_sys, _rng_for_day(), {"emitter": emitter} if emitter.is_valid() else {})
	var pos := Vector2(cell.x + 0.5, cell.y + 0.5)
	wd.start(pos, night.blood, drain_rate(), false, {"day_t": day_t})
	var o := wd.sleep_at({"x": pos.x, "y": pos.y, "safety": float(spot.get("safety", 0.5))}, float(heat))
	last_rest = cell
	at_cell = cell
	player_pos = pos
	var ev: Array = []
	night.blood = float(o["blood_after"])
	var res := String(o["result"])
	if res == "withered":
		_die("withered", ev)
	else:
		var add := int(o["heat_add"])
		if res == "noticed":
			noticed = true   # found asleep: the +1 Heat of the sleep itself is all (docs/ROGUELIKE.md)
		_new_night(add, ev)
		checkpoint()
	return {"ok": true, "result": res, "events": ev, "heat": heat, "blood": night.blood}


## Begin waiting out the day on the current (roofed) cell. Returns the WaitDay to drive (step / resume), then call apply_wait.
## opts {hides: bool or Array, dark: bool, zone: Rect2}.
func begin_wait(opts: Dictionary = {}) -> WaitDay:
	if state != "choice":
		return null
	var params := {}
	if emitter.is_valid():
		params["emitter"] = emitter
	_wait = WaitDay.new(world, people, critter_sys, _rng_for_day(), params)
	var o2 := {"day_t": day_t, "dark": bool(opts.get("dark", false))}
	if opts.has("zone"):
		o2["zone"] = opts["zone"]
	_wait.start(player_pos, night.blood, drain_rate(), opts.get("hides", false), o2)
	return _wait


## Fold a WaitDay outcome into the trek. dusk -> new night (+Heat); withered -> death; noticed -> Heat added, day stays pending
## (deal with it, then begin_wait again or sleep); interrupted/running -> only blood and the day clock are updated.
func apply_wait(o: Dictionary) -> Dictionary:
	var ev: Array = []
	night.blood = float(o.get("blood_after", night.blood))
	if _wait != null:
		day_t = _wait.day_t
	var res := String(o.get("result", "running"))
	var add := int(o.get("heat_add", 0))
	match res:
		"withered":
			_die("withered", ev)
		"dusk":
			_new_night(add, ev)
		"noticed":
			noticed = true
			heat += add
			ev.append({"type": "noticed", "by": o.get("by", -1)})
	return {"ok": true, "result": res, "events": ev, "heat": heat, "blood": night.blood}


## Headless: wait out the whole day (auto-resuming interrupts).
func wait_out_day(opts: Dictionary = {}) -> Dictionary:
	var wd := begin_wait(opts)
	if wd == null:
		return {"ok": false, "code": "not_day"}
	return apply_wait(wd.run_to_end(true))


# ---------------------------------------------------------------- feeding

## Drink a critter (amount defaults to the species' blood). Returns the blood gained.
func on_feed_critter(species: String, amount: float = -1.0) -> float:
	var base: float = amount if amount >= 0.0 else float(Critters.spec(species).get("blood", 6))
	critters_fed += 1
	return night.add_blood(base * float(row.get("bloodGain", 1.0)))


func on_feed_human(amount: float = -1.0) -> float:
	var base: float = amount if amount >= 0.0 else night.feed_gain
	humans_fed += 1
	return night.add_blood(base * float(row.get("bloodGain", 1.0)))


# ---------------------------------------------------------------- exit and end

## Leave through the exit door: clears the stage (+miles, +1 unseen if nobody noticed) and enters the next stage, or ends the trek with
## cause "frontier" when the next stage has no generator yet. Returns {ok, ended, descriptor?, result?}.
func reach_exit() -> Dictionary:
	if not alive():
		return {"ok": false, "ended": state == "ended"}
	cleared_miles += float(row.get("miles", 0.0))
	cleared.append(stage_id)
	if not noticed:
		stages_unseen += 1
	_stage_done = true
	progress = 0.0
	var nxt := next_stage_id(stage_id)
	if nxt != "" and has_generator(nxt):
		leg += 1
		var d := enter_stage(nxt)
		if d.get("ok", false):
			return {"ok": true, "ended": false, "descriptor": d, "miles": miles()}
		leg -= 1
	var r := end_run("frontier")
	return {"ok": true, "ended": true, "result": r}


## Finish the trek: pay Soil, record stats, save the rogue meta, clear the checkpoint (permadeath). Idempotent. cause defaults to the
## death cause; "frontier" (end of the built stages) and "victory" are survivals. Result keys: cause, stageName, miles, humans, critters,
## unseen, newBest, soil_breakdown, soilTotal, bestMiles (+ stageIndex, heat, saved).
func end_run(cause_: String = "") -> Dictionary:
	if state == "ended":
		return result
	var why := cause_ if cause_ != "" else cause
	var idx := int(row.get("index", leg + 1))
	var mi := miles()
	var stats: Dictionary = meta.get("stats", {})
	var new_best := idx > int(stats.get("bestStage", 0))
	var death := why if TrekMeta.DEATH_KEYS.has(why) else ""
	var earned := TrekMeta.record_run(meta, {"miles": mi, "humans": humans_fed, "critters": critters_fed, "unseen": stages_unseen, "stageIndex": idx, "reached": reached, "death": death})
	var base := int(floor(mi)) + 2 * humans_fed + critters_fed / 2 + 3 * stages_unseen + (5 if new_best else 0)
	var saved := true
	if store != null:
		var w: Dictionary = store.write("rogue", SaveCodec.ROGUE_SCHEMA, meta)
		saved = bool(w.get("ok", false))
		store.remove("trek")
	result = {
		"cause": why, "stageName": String(row.get("name", stage_id)), "miles": mi, "humans": humans_fed, "critters": critters_fed,
		"unseen": stages_unseen, "newBest": new_best,
		"soil_breakdown": {"miles": int(floor(mi)), "humans": 2 * humans_fed, "critters": critters_fed / 2, "unseen": 3 * stages_unseen, "newBest": 5 if new_best else 0, "pouch": earned - base},
		"soilTotal": earned, "bestMiles": float(meta["stats"]["bestMiles"]), "stageIndex": idx, "heat": heat, "saved": saved,
	}
	state = "ended"
	cause = why
	return result


# ---------------------------------------------------------------- save

## quit: the position is the last checkpoint's (stage entry / rest spot), everything else (blood, clock, eaten prey, wither timer) is as is.
func snapshot(quit: bool = false) -> Dictionary:
	var nd := night.serialize()
	var at: Vector2i = _ck_at if quit else at_cell
	nd[SAVE_EXTRA] = {
		"humans": humans_fed, "critters": critters_fed, "unseenStages": stages_unseen, "noticed": noticed, "state": state, "day_t": day_t,
		"at": [at.x, at.y], "rest": [last_rest.x, last_rest.y], "stakeIgnored": _stake_ignored, "cleared": cleared.duplicate(),
		"reached": reached.duplicate(), "warned": _warned, "eaten": eaten.duplicate(), "wither_t": _wither_t, "senses": senses,
	}
	if brief:
		nd[SAVE_EXTRA]["brief"] = true   # only when set, so a first-run checkpoint is unchanged
	var used: Array = []
	for id in (meta.get("unlocks", {}) as Dictionary):
		if TrekMeta.tier_of(meta, id) > 0 and used.size() < 32:
			used.append(id)
	return {"v": SaveCodec.TREK_SCHEMA, "seed": seed, "stage": stage_id, "leg": leg, "miles": cleared_miles, "progress": progress, "heat": heat,
		"night": nd, "hunger": hunger.serialize(), "unlocksUsed": used, "deathsAvoided": deaths_avoided}


## Alias of snapshot(), for symmetry with continue_from.
func restore_snapshot(save: Variant) -> TrekFlow:
	return continue_from(save, meta, store)


## Write the checkpoint (kind "trek") when a store is attached. Called at stage entry and by sleep_at_rest.
func checkpoint() -> bool:
	_ck_at = at_cell
	if store == null:
		return true
	var w: Dictionary = store.write("trek", SaveCodec.TREK_SCHEMA, snapshot())
	return bool(w.get("ok", false))


## Remember that the critter spawned at index `idx` of descriptor["critters"] was drunk dry (never respawns on continue).
func mark_eaten(idx: int) -> void:
	if idx >= 0 and not eaten.has(idx) and eaten.size() < 256:
		eaten.append(idx)


## Quit / close: save a checkpoint-safe state (see snapshot(true)). A live WaitDay (the one begin_wait returned)'s blood and day clock are folded in first.
func quit_checkpoint(live_wait: WaitDay = null) -> bool:
	if live_wait != null and _wait == live_wait:
		apply_wait({"result": "running", "blood_after": live_wait.blood})
	if store == null:
		return true
	var w: Dictionary = store.write("trek", SaveCodec.TREK_SCHEMA, snapshot(true))
	return bool(w.get("ok", false))
