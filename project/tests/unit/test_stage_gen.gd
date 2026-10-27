extends TestCase
## StageGen framework + the cave generator (The Hollow): 50 seeds against the constraints in docs/ROGUELIKE.md.

const SEEDS := 50
## Main path in teaching order (strictly increasing walking depth). dead_end_spurs is an optional side beat reported after them.
const MAIN_ORDER := ["coffin_nook", "drip_gallery", "squeeze", "echo_hall", "still_pool", "rat_warren", "cave_mouth"]
const BEAT_ORDER := ["coffin_nook", "drip_gallery", "squeeze", "echo_hall", "still_pool", "rat_warren", "cave_mouth", "dead_end_spurs"]

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
		for id in MAIN_ORDER:
			ok(rep["depths"][id] > last, "seed %d depth increases at %s" % [i + 1, id])
			last = rep["depths"][id]
		# the spur beat is optional and off the path: flagged, reachable, reported last
		var sp: Dictionary = d["beats"][d["beats"].size() - 1]
		eq(sp["id"], "dead_end_spurs", "seed %d spurs reported last" % (i + 1))
		ok(sp.get("optional", false) == true, "seed %d spur beat is optional" % (i + 1))
		ok(rep["depths"]["dead_end_spurs"] >= 0, "seed %d spur mouth reachable" % (i + 1))
		ok(sp.has("end"), "seed %d spur beat has its end cell" % (i + 1))
		# tutorial hints (RogueMode.BEAT_HINTS): squeeze before sun by depth; dead_end only fires at a spur mouth
		ok(rep["depths"]["squeeze"] < rep["depths"]["cave_mouth"], "seed %d squeeze hint precedes sun hint" % (i + 1))
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
		eq(d["kind"], "indoor", tag + " the cave map is indoor")
		var names := {}
		for z in d["zones"]:
			eq(z["kind"], "outdoor" if z["name"] == "cave_apron" else "indoor", tag + " zone kind " + z["name"])
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
		ok(pillars >= 2 and pillars <= 3, tag + " lone pillar cells %d" % pillars)
		# showpiece: stalagmite clusters, stalactite props and drip anchors in the hall
		var mites := 0
		for p in d["props"]:
			if p["type"] == "stalagmite" and _in_zone(hall, [p["col"], p["row"]]):
				mites += 1
		ok(mites >= 6, tag + " hall stalagmites in clusters %d" % mites)
		var hall_anchors := 0
		for a in d["ambient"]:
			if _in_zone(hall, a["cell"]):
				hall_anchors += 1
		ok(hall_anchors >= 2 and hall_anchors <= 4, tag + " hall ambient anchors %d" % hall_anchors)
		var bats := 0
		for c in d["critters"]:
			if c["species"] == "bat":
				bats += 1
		ok(bats >= 2, tag + " bats")
		var stalactites := 0
		for p in d["props"]:
			if p["type"] == "stalactite" and _in_zone(hall, [p["col"], p["row"]]):
				stalactites += 1
		ok(stalactites >= 7, tag + " stalactite props in the hall %d" % stalactites)
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
		# one quiet drip at the far end of the squeeze (in the deeper half)
		var sq_dist := StageGen.bfs(plan, [plan.idx(plan.start.x, plan.start.y)])
		var sq_max := 0
		var sq_near := 1 << 20
		for y in range(sq["y0"], sq["y1"] + 1):
			for x in range(sq["x0"], sq["x1"] + 1):
				if plan.walkable(x, y):
					sq_max = maxi(sq_max, sq_dist[plan.idx(x, y)])
					sq_near = mini(sq_near, sq_dist[plan.idx(x, y)])
		var sq_drips := 0
		for a in d["ambient"]:
			if _in_zone(sq, a["cell"]):
				sq_drips += 1
				eq(a["kind"], "drip", tag + " squeeze anchor is a drip")
				var ad: int = sq_dist[plan.idx(a["cell"][0], a["cell"][1])]
				ok(ad >= sq_near + (sq_max - sq_near) / 2, tag + " squeeze drip at the far end (depth %d of %d..%d)" % [ad, sq_near, sq_max])
		eq(sq_drips, 1, tag + " one squeeze drip")
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
		var wa := 0
		for a in d["ambient"]:
			if _in_zone(war, a["cell"]):
				wa += 1
		ok(wa >= 1 and wa <= 2, tag + " warren anchors %d" % wa)
		# exit
		var door: Dictionary = d["doors"][0]
		eq(door["toMap"], "stage:wood", tag + " exit placeholder")
		eq(String(d["rows"][door["row"]])[door["col"]], "D", tag + " door cell")
		var glow := false
		for l in d["lights"]:
			if Vector2(l["cell"][0], l["cell"][1]).distance_to(Vector2(door["col"], door["row"])) < 9.0:
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
	ok(worst < 400.0, "worst generation %.1f ms stays under 400 ms (target ~300)" % worst)


## The apron: a short outdoor stretch past the cave mouth, inside the same map, with the exit door at its far end.
func test_outdoor_apron() -> void:
	var defs := _all()
	for i in defs.size():
		var d: Dictionary = defs[i]
		var tag := "seed %d" % (i + 1)
		var ap := _zone(d, "cave_apron")
		ok(not ap.is_empty() and ap["kind"] == "outdoor", tag + " apron zone is outdoor")
		if ap.is_empty():
			continue
		var world := World.from_def(d)
		var plan := StageGen.plan_from_def(d)
		var out := 0
		for y in range(ap["y0"], ap["y1"] + 1):
			for x in range(ap["x0"], ap["x1"] + 1):
				if plan.walkable(x, y):
					out += 1
					eq(world.kind_at(x + 0.5, y + 0.5), "outdoor", tag + " apron cell is outdoor")
		ok(out >= 3, tag + " >= 3 outdoor cells (%d)" % out)
		var depth: int = int(ap["y1"]) - int(ap["y0"]) + 1
		ok(depth >= 3 and depth <= 5, tag + " apron is 3-5 cells deep (%d)" % depth)
		var mouth := _zone(d, "cave_mouth")
		ok(not mouth.is_empty() and mouth["kind"] == "indoor", tag + " mouth zone indoor")
		eq(world.kind_at(d["start"]["cell"][0] + 0.5, d["start"]["cell"][1] + 0.5), "indoor", tag + " start roofed")
		var bc: Array = d["places"]["cave_mouth"]
		eq(world.kind_at(bc[0] + 0.5, bc[1] + 0.5), "indoor", tag + " cave mouth beat roofed")
		var door: Dictionary = d["doors"][0]
		var arr: Array = d["exit"]["arrival"]
		ok(_in_zone(ap, arr), tag + " arrival is in the apron")
		eq(absi(door["col"] - arr[0]) + absi(door["row"] - arr[1]), 1, tag + " door is adjacent to the arrival")
		ok(StageGen.analyze(d, _row())["exit_reachable"], tag + " exit reachable through the apron")
		var rows: Array = d["rows"]
		for x in 64:
			eq(String(rows[0])[x], "#", tag + " top border")
			eq(String(rows[47])[x], "#", tag + " bottom border")
		for y in 48:
			eq(String(rows[y])[0], "#", tag + " left border")
			eq(String(rows[y])[63], "#", tag + " right border")


func test_sun_kills_on_the_apron_only() -> void:
	for seed in [7, 11, 23]:
		var f := TrekFlow.begin(TrekMeta.create(), seed)
		var d: Dictionary = f.def
		var arr: Array = d["exit"]["arrival"]
		var cell := Vector2i(arr[0], arr[1])
		ok(f.cell_outdoor(cell), "seed %d apron arrival is outdoor in the World" % seed)
		f.night.skip_to(5, 59)
		f.step(2.0, cell, f.cell_outdoor(cell))
		eq(f.cause, "sun", "seed %d dawn on the apron kills" % seed)
		var g := TrekFlow.begin(TrekMeta.create(), seed)
		var roofed: Array = d["start"]["cell"]
		var rc := Vector2i(roofed[0], roofed[1])
		ok(not g.cell_outdoor(rc), "seed %d start is roofed" % seed)
		var bc: Array = d["places"]["cave_mouth"]
		ok(not g.cell_outdoor(Vector2i(bc[0], bc[1])), "seed %d cave mouth roofed" % seed)
		g.night.skip_to(5, 59)
		g.step(2.0, Vector2i(bc[0], bc[1]), g.cell_outdoor(Vector2i(bc[0], bc[1])))
		ok(g.alive(), "seed %d dawn in the cave mouth is survived" % seed)


## Zones are measured from the carved cave: tight boxes around real floor, and their extents differ between seeds.
func test_zones_measured_per_seed() -> void:
	var defs := _all()
	var shapes := {}
	for d in defs:
		var plan := StageGen.plan_from_def(d)
		for nm in ["echo_hall", "drip_gallery", "still_pool", "rat_warren", "cave_mouth"]:
			var z := _zone(d, nm)
			ok(not z.is_empty(), nm + " zone exists")
			if z.is_empty():
				continue
			var top := false
			var bot := false
			var lef := false
			var rig := false
			for x in range(z["x0"], z["x1"] + 1):
				top = top or plan.tile(x, z["y0"]) != 0
				bot = bot or plan.tile(x, z["y1"]) != 0
			for y in range(z["y0"], z["y1"] + 1):
				lef = lef or plan.tile(z["x0"], y) != 0
				rig = rig or plan.tile(z["x1"], y) != 0
			ok(top and bot and lef and rig, nm + " zone box is tight around floor")
			if not shapes.has(nm):
				shapes[nm] = {}
			shapes[nm]["%d,%d" % [z["x1"] - z["x0"], z["y1"] - z["y0"]]] = true
	var varied := 0
	for nm in shapes:
		if shapes[nm].size() > 1:
			varied += 1
	ok(varied >= 1, "at least one beat zone changes size between seeds (%d of %d)" % [varied, shapes.size()])
