extends TestCase
## Hunting model (core/critters.gd): sneak radius, ping freeze, lunge, stamina, speed cap, and deterministic bots on StageGen hollow caves.

const DT := 0.1
const CREEP := 1.5
const RUN := 3.0


func _arena() -> World:
	var rows: Array = []
	for y in 20:
		var r := ""
		for x in 40:
			r += "#" if (x == 0 or y == 0 or x == 39 or y == 19) else "."
		rows.append(r)
	return World.from_def({"name": "t", "kind": "indoor", "rows": rows, "floor": "stone"})


func _walkable(w: World, c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < w.width and c.y < w.height and not w.blocks(c.x + 0.5, c.y + 0.5, 0.25)


## BFS distance field (4-neighbour, cell -> steps) from `src` over walkable cells.
func _field(w: World, src: Vector2i) -> Dictionary:
	var dist := {src: 0}
	var q: Array = [src]
	var qi := 0
	while qi < q.size():
		var c: Vector2i = q[qi]
		qi += 1
		for d in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if not dist.has(n) and _walkable(w, n):
				dist[n] = int(dist[c]) + 1
				q.append(n)
	return dist


## Hunt rats for `secs`; returns rats drunk. creep=true: runs when far, creeps (sneak) within 8 cells and pings within 4.5; false: runs flat out, no ping.
func _hunt(def: Dictionary, creep: bool, secs: float) -> Array:
	var w := World.from_def(def)
	var cs := Critters.new(w, 11.0)
	for s in def["critters"]:
		cs.spawn(String(s["species"]), Vector2i(int(s["cell"][0]), int(s["cell"][1])), false)
	var st: Dictionary = def["start"]
	var pos := Vector2(float(st["cell"][0]) + 0.5, float(st["cell"][1]) + 0.5)
	var caught: Array = []
	var ping_cd := 0.0
	var t := 0.0
	var target: Critters.Critter = null
	var field: Dictionary = {}
	var field_cell := Vector2i(-1, -1)
	while t < secs:
		t += DT
		ping_cd -= DT
		if target == null or target.dead:
			target = null
			var best := 1 << 30
			var pc := Vector2i(int(pos.x), int(pos.y))
			var pf := _field(w, pc)
			for c in cs.critters:
				if c.species != "rat":
					continue
				var d: int = int(pf.get(Vector2i(int(c.x), int(c.y)), 1 << 29))
				if d < best:
					best = d
					target = c
			field_cell = Vector2i(-1, -1)
		var sneak := false
		if target != null:
			var bd: float = Vector2(target.x - pos.x, target.y - pos.y).length()
			var speed := RUN
			if creep and bd < 8.0:
				speed = CREEP
				sneak = true
			if creep and bd < 4.5 and ping_cd <= 0.0:
				cs.on_ping(pos)
				ping_cd = 1.6
			var tc := Vector2i(int(target.x), int(target.y))
			if tc != field_cell:
				field = _field(w, tc)
				field_cell = tc
			var wp := Vector2(target.x, target.y)
			if bd >= 1.5:
				var pc2 := Vector2i(int(pos.x), int(pos.y))
				var bestd: int = int(field.get(pc2, 1 << 29))
				for d in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]:
					var n: Vector2i = pc2 + d
					if int(field.get(n, 1 << 29)) < bestd:
						bestd = int(field[n])
						wp = Vector2(n.x + 0.5, n.y + 0.5)
			var dir := wp - pos
			if dir.length() > 0.001:
				var step_v := dir.normalized() * minf(speed * DT, dir.length())
				for cand in [step_v, Vector2(step_v.x, 0), Vector2(0, step_v.y)]:
					if not w.blocks(pos.x + cand.x, pos.y + cand.y, 0.25):
						pos += cand
						break
			var got := cs.lunge(pos)
			if got != null:
				cs.feed(got)
				if got.species == "rat":
					caught.append(t)
		cs.step(pos, DT, false, {}, sneak)
	return caught


func test_bots_creep_beats_run_on_hollow() -> void:
	var creep_total := 0
	var run_total := 0
	for sd in [1, 2, 3]:
		var def: Dictionary = StageGen.generate("hollow", sd)
		var ca := _hunt(def, true, 120.0)
		var cb := _hunt(def, false, 120.0)
		var a := _count_by(ca, 60.0)
		var b := _count_by(cb, 60.0)
		print("critter_catch: seed %d creep+ping %d rats in 120 s (%d by 60 s), runner %d (%d by 60 s)" % [sd, ca.size(), a, cb.size(), b])
		ok(ca.size() >= 3, "seed %d creeping bot catches >= 3 rats in 120 s (got %d)" % [sd, ca.size()])
		ok(a >= b, "seed %d runner not better by 60 s (creep %d, run %d)" % [sd, a, b])
		creep_total += a
		run_total += b
	ok(run_total < creep_total, "running bot catches fewer overall in the first 60 s (%d < %d)" % [run_total, creep_total])


func _count_by(times: Array, limit: float) -> int:
	var n := 0
	for v in times:
		if float(v) <= limit:
			n += 1
	return n


func test_bot_deterministic() -> void:
	var def: Dictionary = StageGen.generate("hollow", 2)
	eq(_hunt(def, true, 40.0), _hunt(def, true, 40.0), "same seed same catch times")


func test_sneak_scales_flee_radius() -> void:
	var cs := Critters.new(_arena(), 3)
	var c = cs.spawn("rat", Vector2i(20, 10), false)
	var p := Vector2(c.x - 2.0, c.y)
	for i in 5:
		cs.step(p, 0.1, false, {}, true)
	ok(c.state != "flee", "rat at 2 cells does not flee from a sneaking player (radius 3 x 0.4)")
	cs.step(p, 0.1, false, {}, false)
	eq(c.state, "flee", "same distance flees from a normal player")


func test_ping_freezes_not_flees() -> void:
	var cs := Critters.new(_arena(), 3)
	var c = cs.spawn("rat", Vector2i(20, 10), false)
	var p := Vector2(c.x - 2.5, c.y)
	eq(cs.on_ping(p), 1, "rat within 4 cells froze")
	var x0: float = c.x
	for i in 8:
		cs.step(p, 0.1, false)
	eq(c.state, "wander", "not fleeing while frozen")
	near(c.x, x0, 1e-9, "stands still while frozen")
	for i in 5:
		cs.step(p, 0.1, false)
	eq(c.state, "flee", "flees once the freeze ends and the player is still close")
	var far = cs.spawn("rat", Vector2i(35, 15), false)
	eq(cs.on_ping(p), 0, "fleeing rat and distant rat do not freeze")
	ok(far.freeze_t == 0.0, "far rat unaffected")


func test_loud_hear_cancels_freeze() -> void:
	var cs := Critters.new(_arena(), 3)
	var c = cs.spawn("rat", Vector2i(20, 10), false)
	cs.on_ping(Vector2(c.x - 2.0, c.y))
	cs.step(Vector2(-50, -50), 0.1, false, {"x": c.x - 1.0, "y": c.y, "strength": 1.0})
	eq(c.state, "flee", "loud event still flees a frozen rat")


func test_lunge() -> void:
	var cs := Critters.new(_arena(), 3)
	var c = cs.spawn("rat", Vector2i(20, 10), false)
	var p := Vector2(c.x - 1.8, c.y)
	ok(cs.lunge(p) == c, "wandering rat within 2 cells is lunged")
	ok(Vector2(c.x - p.x, c.y - p.y).length() <= Critters.FEED_REACH, "snapped within feed reach")
	eq(cs.nearest_feedable(p.x, p.y).id, c.id, "feedable after lunge")
	ok(cs.lunge(Vector2(c.x - 3.0, c.y)) == null, "out of reach")
	var d = cs.spawn("deer", Vector2i(10, 5), false)
	var q := Vector2(d.x - 2.5, d.y)
	for i in 3:
		cs.step(q, 0.1, false)
	eq(d.state, "flee", "deer fleeing at speed")
	ok(cs.lunge(Vector2(d.x - 1.0, d.y)) == null, "cannot lunge a fresh fast fleer")
	var b = cs.spawn("bat", Vector2i(30, 5), true)
	eq(b.state, "roost", "bat roosting by day")
	ok(cs.lunge(Vector2(b.x - 1.5, b.y)) == b, "roosting bat catchable")


func test_stamina_slows_fleeing() -> void:
	var cs := Critters.new(_arena(), 3)
	var c = cs.spawn("rat", Vector2i(5, 10), false)
	var fresh := Critters.flee_speed(c)
	c.flee_t = 10.0
	var tired := Critters.flee_speed(c)
	near(tired, fresh * 0.6, 1e-9, "tired = 0.6x")
	# a rat chased for 12 s tires out and then flees at 0.6x
	var cs2 := Critters.new(_arena(), 3)
	var r = cs2.spawn("rat", Vector2i(12, 10), false)
	for i in 120:
		cs2.step(Vector2(r.x - 1.0, r.y), 0.1, false)
	ok(r.flee_t > float(Critters.catch_tuning("rat")["tire_after"]), "chased rat accumulates fatigue")
	near(Critters.flee_speed(r), Critters.spec("rat")["speed"] * 1.5 * 0.6, 1e-9, "tired rat flees at 0.6x")
	# fatigue recovers once left alone
	for i in 400:
		cs2.step(Vector2(-50, -50), 0.1, false)
	ok(r.flee_t < 1.0, "fatigue recovers")


func test_no_species_exceeds_speed_cap() -> void:
	for sp in Critters.species_table().keys():
		var c := Critters.Critter.new()
		c.species = sp
		var v := Critters.flee_speed(c)
		ok(v <= Critters.PLAYER_SPEED * 1.6 + 1e-9, "%s flee speed %.2f <= 4.8" % [sp, v])
		var t := Critters.catch_tuning(sp)
		ok(float(t["sneak_mult"]) <= 0.4 + 1e-9, "%s sneak radius scaled" % sp)
	var hare := Critters.Critter.new()
	hare.species = "hare"
	ok(float(Critters.spec("hare")["flee_radius"]) * float(Critters.catch_tuning("hare")["sneak_mult"]) <= Critters.LUNGE_REACH, "hare sneaking radius within lunge reach")
