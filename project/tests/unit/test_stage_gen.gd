extends TestCase
## StageGen framework + the cave generator (The Hollow): 50 seeds against the constraints in docs/ROGUELIKE.md.

const SEEDS := 50
const BEAT_ORDER := ["coffin_nook", "drip_gallery", "squeeze", "echo_hall", "still_pool", "dead_end_spurs", "rat_warren", "cave_mouth"]

static var _defs: Array = []
static var _ms: Array = []


func _all() -> Array:
	if _defs.is_empty():
		for s in range(1, SEEDS + 1):
			var t0 := Time.get_ticks_usec()
			_defs.append(StageGen.generate("hollow", s))
			_ms.append((Time.get_ticks_usec() - t0) / 1000.0)
	return _defs


func _row() -> Dictionary:
	return StageGen.stage_row("hollow")


func _zone(def: Dictionary, name: String) -> Dictionary:
	for z in def["zones"]:
		if z["name"] == name:
			return z
	return {}


func _in_zone(z: Dictionary, c: Array) -> bool:
	return c[0] >= z["x0"] and c[0] <= z["x1"] and c[1] >= z["y0"] and c[1] <= z["y1"]


func _stub_next(door_to: String) -> Dictionary:
	return {"name": "stage:wood", "kind": "outdoor", "floor": "grass", "rows": ["#####", "#@..#", "#..D#", "#####"],
		"doors": [{"id": "cave", "col": 3, "row": 2, "toMap": door_to, "toDoor": "mouth", "facing": "w"}]}


func test_stage_row_schema() -> void:
	var r := _row()
	ok(not r.is_empty(), "hollow row in stages.json")
	eq(r["generator"], "cave", "generator")
	near(float(r["drainMul"]), 0.8, 1e-9, "drainMul")
	eq(int(r["miles"]), 3, "miles")
	for k in ["preyCount", "lights", "size", "openFraction", "nodes", "spurs", "shelter", "caps", "exit", "materials"]:
		ok(r.has(k), "row key " + k)
	eq(int(r["shelter"]["pockets"]["min"]), 3, "min pockets")
	eq(int(r["shelter"]["restSpots"]["min"]), 2, "min rest spots")
	ok(StageGen.stage_row("nope").is_empty(), "unknown stage")
	ok(StageGen.generate("nope", 1).is_empty(), "unknown stage generates nothing")
	var c := StageGen.chunks()
	for b in BEAT_ORDER:
		if b != "dead_end_spurs":
			ok(c["chunks"].has(b), "chunk " + b)


func test_cover_constants() -> void:
	near(StageGen.night_walk_cells(), 480.0 * 3.0, 1e-9, "night length x walk speed")
	eq(StageGen.cover_limit(), 576, "0.4 of a night walk in cells")


func test_seeds_validate_and_reach() -> void:
	var defs := _all()
	eq(defs.size(), SEEDS, "all seeds generated")
	var row := _row()
	for i in defs.size():
		var d: Dictionary = defs[i]
		var tag := "seed %d" % (i + 1)
		ok(not d.is_empty(), tag + " generated")
		if d.is_empty():
			continue
		var v := StageGen.validate(d)
		ok(v["ok"], tag + " validate: " + str(v["errors"]).left(160))
		var all := {"startMap": d["name"], "maps": {d["name"]: d, "stage:wood": _stub_next(d["name"])}, "links": []}
		var va := WorldValidate.validate_all(all)
		ok(va["ok"], tag + " validate_all: " + str(va["errors"]).left(200))
		var rep := StageGen.analyze(d, row)
		ok(rep["ok"], tag + " analyze: " + str(rep["reasons"]))
		ok(rep["exit_reachable"], tag + " exit reachable from start")
		eq(rep["unreachable"], 0, tag + " no cut-off floor")
		eq(d["rows"].size(), 48, tag + " height")
		eq(String(d["rows"][0]).length(), 64, tag + " width")
		eq(d["stage"], "hollow", tag + " stage id")
		eq(d["seed"], i + 1, tag + " seed echoed")


func test_beats_in_order() -> void:
	var defs := _all()
	for i in defs.size():
		var d: Dictionary = defs[i]
		var ids: Array = []
		for b in d["beats"]:
			ids.append(b["id"])
		eq(ids, BEAT_ORDER, "seed %d beat list" % (i + 1))
		var rep := StageGen.analyze(d, _row())
		var last := -1
		for id in ids:
			if id == "dead_end_spurs":
				continue
			ok(rep["depths"][id] > last, "seed %d depth increases at %s" % [i + 1, id])
			last = rep["depths"][id]
		eq(rep["depths"]["coffin_nook"], 0, "start is at the coffin nook")


func test_shelter() -> void:
	var defs := _all()
	for i in defs.size():
		var d: Dictionary = defs[i]
		var tag := "seed %d" % (i + 1)
		var s_count := 0
		var c_count := 0
		for r in "\n".join(d["rows"]):
			if r == "S":
				s_count += 1
			elif r == "C":
				c_count += 1
		ok(s_count >= 1, tag + " has a safe spot")
		eq(c_count, 1, tag + " one crypt spot")
		var kinds := {}
		for r in d["rest"]:
			kinds[r["kind"]] = int(kinds.get(r["kind"], 0)) + 1
			ok(float(r["safety"]) >= 0.0 and float(r["safety"]) <= 1.0, tag + " safety in 0..1")
			var ch: String = String(d["rows"][r["cell"][1]])[r["cell"][0]]
			eq(ch, r["marker"], tag + " rest marker on the map")
		eq(kinds.get("coffin", 0), 1, tag + " coffin rest")
		ok(kinds.get("roost", 0) >= 1, tag + " roost ledge")
		ok(d["rest"].size() - 1 >= 2, tag + " >= 2 non-coffin rest spots")
		ok(d["pockets"].size() >= 3, tag + " >= 3 covered pockets")
		var rest_pockets := 0
		for p in d["pockets"]:
			var z := _zone(d, p["zone"])
			ok(not z.is_empty() and z["kind"] == "indoor", tag + " pocket zone " + p["zone"])
			if not z.is_empty():
				ok(_in_zone(z, p["cell"]), tag + " pocket cell inside its zone")
			if p["rest"]:
				rest_pockets += 1
		ok(rest_pockets >= 3, tag + " pockets that are rest spots")
		# coffin nook: upright coffin on the north wall, start next to it, drip two cells ahead
		var coffin: Dictionary = {}
		for p in d["props"]:
			if p["type"] == "coffin":
				coffin = p
		ok(not coffin.is_empty(), tag + " coffin prop")
		if not coffin.is_empty():
			eq(String(d["rows"][coffin["row"] - 1])[coffin["col"]], "#", tag + " coffin stands against the north wall")
			var st: Array = d["start"]["cell"]
			eq(st[0], coffin["col"], tag + " start is below the coffin")
			eq(st[1], coffin["row"] + 1, tag + " start is one cell south of the coffin")
			var drip := false
			for a in d["ambient"]:
				if a["kind"] == "drip" and a["cell"][0] == st[0] and a["cell"][1] == st[1] + 2:
					drip = true
			ok(drip, tag + " drip anchor 2 cells ahead of the start")


func test_cover_distance_rule() -> void:
	var defs := _all()
	var limit := StageGen.cover_limit()
	var row := _row()
	var target: int = int(row["shelter"]["restTarget"])
	var worst := 0
	for i in defs.size():
		var rep := StageGen.analyze(defs[i], row)
		worst = maxi(worst, rep["max_rest_dist"])
		ok(rep["max_rest_dist"] >= 0 and rep["max_rest_dist"] <= limit, "seed %d rest within %d cells (got %d)" % [i + 1, limit, rep["max_rest_dist"]])
		ok(rep["max_rest_dist"] <= target + 12, "seed %d design target %d (got %d)" % [i + 1, target, rep["max_rest_dist"]])
	print("stage_gen: worst rest distance over %d seeds = %d cells (rule limit %d, design target %d)" % [defs.size(), worst, limit, target])


func test_caps_and_fractions() -> void:
	var defs := _all()
	var row := _row()
	var lo := 1.0
	var hi := 0.0
	var species := Critters.species_table()
	for i in defs.size():
		var d: Dictionary = defs[i]
		var tag := "seed %d" % (i + 1)
		var plan := StageGen.plan_from_def(d)
		eq(d["paths"].size(), 0, tag + " no people paths")
		ok(not "\n".join(d["rows"]).contains("P"), tag + " no people spots")
		ok(d["critters"].size() <= 12, tag + " critters <= 12")
		ok(d["critters"].size() >= int(row["preyCount"]["min"]) - 1, tag + " prey count")
		for c in d["critters"]:
			ok(species.has(c["species"]), tag + " known species " + str(c["species"]))
			ok(plan.walkable(c["cell"][0], c["cell"][1]), tag + " critter on walkable floor")
		ok(d["props"].size() <= 60, tag + " props <= 60")
		ok(d["lights"].size() <= 16, tag + " lights <= 16")
		ok(d["lights"].size() >= 3, tag + " has glow-worm lights")
		ok(d["ambient"].size() <= 24, tag + " ambient anchors <= 24")
		var f: float = StageGen.analyze(d, row)["open_fraction"]
		lo = minf(lo, f)
		hi = maxf(hi, f)
		ok(f >= 0.30 and f <= 0.38, tag + " open fraction %.3f" % f)
		eq(d["kind"], "indoor", tag + " whole cave is indoor")
		var names := {}
		for z in d["zones"]:
			eq(z["kind"], "indoor", tag + " zone kind")
			ok(not names.has(z["name"]), tag + " unique zone " + z["name"])
			names[z["name"]] = true
		eq(d["materials"]["#"], "roughStone", tag + " rough stone walls")
	print("stage_gen: open fraction over %d seeds %.3f .. %.3f (counted over the 62x46 interior, water included)" % [defs.size(), lo, hi])


func test_beat_features() -> void:
	var defs := _all()
	for i in defs.size():
		var d: Dictionary = defs[i]
		var tag := "seed %d" % (i + 1)
		var plan := StageGen.plan_from_def(d)
		# echo hall: radius 7 open, T60 zone, pillars, bats under stalactites
		var hall := _zone(d, "echo_hall")
		ok(not hall.is_empty(), tag + " echo_hall zone")
		var hc: Array = d["places"]["echo_hall"]
		var open7 := 0
		for y in range(hc[1] - 7, hc[1] + 8):
			for x in range(hc[0] - 7, hc[0] + 8):
				if (x - hc[0]) * (x - hc[0]) + (y - hc[1]) * (y - hc[1]) <= 49 and plan.tile(x, y) != 0:
					open7 += 1
		ok(open7 >= 120, tag + " hall radius 7 is open (%d of about 154)" % open7)
		var pillars := 0
		for y in range(hall["y0"], hall["y1"] + 1):
			for x in range(hall["x0"], hall["x1"] + 1):
				if plan.tile(x, y) == 0 and plan.tile(x - 1, y) != 0 and plan.tile(x + 1, y) != 0 and plan.tile(x, y - 1) != 0 and plan.tile(x, y + 1) != 0:
					pillars += 1
		ok(pillars >= 2 and pillars <= 3, tag + " pillar cells %d" % pillars)
		var bats := 0
		for c in d["critters"]:
			if c["species"] == "bat":
				bats += 1
		ok(bats >= 2, tag + " bats")
		var stalactites := 0
		for p in d["props"]:
			if p["type"] == "stalactite" and _in_zone(hall, [p["col"], p["row"]]):
				stalactites += 1
		ok(stalactites >= 2, tag + " stalactites over the bats")
		near(Acoustics.t60_for("echo_hall", "indoor"), 2.2, 0.1, "echo hall T60")
		# squeeze: 1-wide corridor of about 31 cells
		var sq := _zone(d, "squeeze")
		var walk := 0
		for y in range(sq["y0"], sq["y1"] + 1):
			for x in range(sq["x0"], sq["x1"] + 1):
				if plan.walkable(x, y):
					walk += 1
					var nb := 0
					for dd in StageGen.N4:
						if plan.walkable(x + dd.x, y + dd.y) and _in_zone(sq, [x + dd.x, y + dd.y]):
							nb += 1
					ok(nb <= 2, tag + " squeeze cell is 1 wide")
		ok(walk >= 28 and walk <= 36, tag + " squeeze length %d" % walk)
		# pool
		var pool := _zone(d, "still_pool")
		var water := 0
		for y in range(pool["y0"], pool["y1"] + 1):
			for x in range(pool["x0"], pool["x1"] + 1):
				if plan.tile(x, y) == 2:
					water += 1
		ok(water >= 20, tag + " pool water %d" % water)
		var rip := 0
		var drips := 0
		var draft := 0
		for a in d["ambient"]:
			if a["kind"] == "ripple":
				rip += 1
				ok(_in_zone(pool, a["cell"]), tag + " ripple in pool zone")
			elif a["kind"] == "drip":
				drips += 1
			elif a["kind"] == "draft":
				draft += 1
		ok(rip >= 2, tag + " pool ripples")
		ok(drips >= 5, tag + " drips (nook + gallery + fillers)")
		eq(draft, 1, tag + " one draft anchor")
		var gal := _zone(d, "drip_gallery")
		var gd := 0
		for a in d["ambient"]:
			if a["kind"] == "drip" and _in_zone(gal, a["cell"]):
				gd += 1
		ok(gd >= 3 and gd <= 4, tag + " gallery drips %d" % gd)
		var shore_rats := 0
		for c in d["critters"]:
			if c["species"] == "rat" and _in_zone(pool, c["cell"]):
				shore_rats += 1
		ok(shore_rats >= 1, tag + " rats on the shore")
		var war := _zone(d, "rat_warren")
		var wr := 0
		for c in d["critters"]:
			if c["species"] == "rat" and _in_zone(war, c["cell"]):
				wr += 1
		ok(wr >= 3 and wr <= 4, tag + " warren rats %d" % wr)
		# exit
		var door: Dictionary = d["doors"][0]
		eq(door["toMap"], "stage:wood", tag + " exit placeholder")
		eq(String(d["rows"][door["row"]])[door["col"]], "D", tag + " door cell")
		var glow := false
		for l in d["lights"]:
			if Vector2(l["cell"][0], l["cell"][1]).distance_to(Vector2(door["col"], door["row"])) < 6.0:
				glow = true
		ok(glow, tag + " glow-worm light by the mouth")
		# spurs are dead ends
		var spur_pockets := 0
		for p in d["pockets"]:
			if p["kind"] == "spur":
				spur_pockets += 1
				var nb2 := 0
				for dd in StageGen.N4:
					if plan.walkable(p["cell"][0] + dd.x, p["cell"][1] + dd.y):
						nb2 += 1
				eq(nb2, 1, tag + " spur end is a dead end")
		ok(spur_pockets >= 2 and spur_pockets <= 3, tag + " 2-3 spurs")


func test_deterministic_and_distinct() -> void:
	var defs := _all()
	for s in [1, 17, 50]:
		var again := StageGen.generate("hollow", s)
		ok(again == defs[s - 1], "seed %d regenerates identically" % s)
	var seen := {}
	for d in defs:
		seen[str(d["rows"]).hash()] = true
	eq(seen.size(), defs.size(), "all 50 seeds give different maps")
	var other := StageGen.generate("hollow", 1000003)
	ok(other["rows"] != defs[0]["rows"], "far seed differs")


func test_utilities() -> void:
	var p := StageGen.Plan.new(9, 7)
	for y in range(1, 6):
		for x in range(1, 8):
			p.tiles[p.idx(x, y)] = 1
	p.add_prop("stalagmite", 4, 3)
	var d := StageGen.bfs(p, [p.idx(1, 1)])
	eq(d[p.idx(1, 1)], 0, "bfs source")
	eq(d[p.idx(7, 5)], 10, "bfs corner to corner")
	eq(d[p.idx(4, 3)], -1, "solid prop blocks the bfs")
	var dt := StageGen.distance_transform(p)
	near(dt[p.idx(1, 1)], 1.0, 1e-5, "next to the wall")
	near(dt[p.idx(5, 3)], 3.0, 1e-5, "centre row of a 7x5 room")
	near(dt[p.idx(0, 0)], 0.0, 1e-5, "wall is 0")
	var pts: Array = [Vector2i(0, 0), Vector2i(10, 0), Vector2i(20, 0), Vector2i(1, 5)]
	var e := StageGen.mst(pts)
	eq(e.size(), 3, "mst edge count")
	var ef := StageGen.mst(pts, [[0, 2]])
	eq(ef.size(), 3, "forced mst edge count")
	ok(ef.has([0, 2]), "forced edge kept")
	var r := Rng.new(5)
	var lo := 99
	var hi := -99
	for _i in 200:
		var v := StageGen.rint(r, 2, 4)
		lo = mini(lo, v)
		hi = maxi(hi, v)
	eq([lo, hi], [2, 4], "rint inclusive range")
	var a: Array = [1, 2, 3, 4, 5]
	StageGen.shuffle(Rng.new(3), a)
	a.sort()
	eq(a, [1, 2, 3, 4, 5], "shuffle is a permutation")
	var q := StageGen.Plan.new(20, 20)
	q.protect[q.idx(10, 10)] = 1
	ok(not StageGen.carve(q, 10, 10), "protected cell not carved")
	ok(not StageGen.carve(q, 1, 5), "margin ring not carved")
	ok(StageGen.carve(q, 5, 5), "free cell carved")
	ok(StageGen.carve_tunnel(q, Rng.new(1), Vector2i(3, 3), Vector2i(16, 16), 1), "tunnel around a protected cell")
	ok(StageGen.bfs(q, [q.idx(3, 3)])[q.idx(16, 16)] >= 26, "tunnel connects the endpoints")


func test_stamp_transforms() -> void:
	var c := StageGen.chunks()
	var plan := StageGen.Plan.new(30, 30)
	var ch: Dictionary = c["chunks"]["squeeze"]
	var res := StageGen.stamp(plan, ch, c["legend"], 5, 5, true, false)
	eq(res["rect"], Rect2i(5, 5, 7, 15), "transposed rect")
	eq(res["ports"].size(), 2, "ports")
	for pr in res["ports"]:
		ok(plan.is_open(pr["cell"].x, pr["cell"].y), "port cell is floor")
		ok(["n", "s"].has(pr["dir"]), "transposed port direction " + pr["dir"])
	var plan2 := StageGen.Plan.new(30, 30)
	var res2 := StageGen.stamp(plan2, c["chunks"]["coffin_nook"], c["legend"], 3, 3, false, true)
	eq(plan2.start, Vector2i(3 + 9 - 1 - 4, 3 + 2), "flipped start (symmetric nook)")
	eq(plan2.rest.size(), 1, "coffin rest recorded")
	eq(plan2.prop_cells.size(), 1, "coffin prop recorded")
	eq(res2["beat_cell"], plan2.start, "beat cell is the start")


func test_register_and_build_world() -> void:
	var d: Dictionary = _all()[2]
	GameData.register_map("hollow_gen_test", d)
	var def: Dictionary = GameData.map_def("hollow_gen_test")
	var w := World.from_def(def)
	eq(w.width, 64, "world width")
	eq(w.height, 48, "world height")
	ok(w.start != null, "start marker")
	var st: Vector2 = w.start
	ok(not w.blocks(st.x, st.y, 0.25), "start is open")
	eq(w.spots["crypt"].size(), 1, "one crypt spot")
	ok(w.spots["safe"].size() >= 3, "safe spots")
	ok(w.has_water, "water tile present")
	ok(w.lights.size() >= 3 and w.lights.size() <= 16, "glow-worm lights built")
	eq(w.kind_at(st.x, st.y), "indoor", "indoor at the start")
	var door: Dictionary = d["doors"][0]
	var arr: Variant = w.arrival(door["id"])
	ok(arr != null and not w.blocks(arr["x"], arr["y"], 0.25), "arrival is open")
	eq(w.mat_table["#"], "roughStone", "wall material override")
	eq(w.zone_at(st.x, st.y), "coffin_nook", "start zone")
	ok(GameData.unregister_map("hollow_gen_test"), "unregister")


func test_generation_time() -> void:
	_all()
	var tot := 0.0
	var worst := 0.0
	for m in _ms:
		tot += m
		worst = maxf(worst, m)
	print("stage_gen: %d seeds, avg %.1f ms, worst %.1f ms" % [_ms.size(), tot / maxf(1.0, float(_ms.size())), worst])
	ok(worst < 5000.0, "generation stays under 5 s")
