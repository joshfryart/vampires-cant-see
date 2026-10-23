extends TestCase
## Echolocation validation for generated stages (WP12, docs/ROGUELIKE.md "Echo validation per environment").
## Every check is a helper _check_*(stage_id, seeds): the test methods enumerate the stages from data/rogue/stages.json
## (rows whose generator is implemented, GENERATORS) and run each helper on seeds 1..SEEDS, so a new stage only needs a row
## and a generator. Today: The Hollow (cave), Bramble Wood (wood) and Gallows Moor (moor).

const SEEDS := 20
const SAMPLES := 200
const ECHO_RANGE := 13.0
const RAYS := 720
const RAY_CHECKS := 500
const RAYS_PER_ORIGIN := 20
const COLUMNS := 48
const FOV := 1.2
const SOAK_SEC := 60.0
const SOAK_DT := 0.05
const GENERATORS := ["cave", "wood", "moor"]

static var _cache: Dictionary = {}


static func _stage_ids() -> Array:
	var out: Array = []
	var d: Variant = GameData.load_rogue("stages")
	if d is Dictionary and d.get("stages") is Array:
		for r in d["stages"]:
			if r is Dictionary and GENERATORS.has(String(r.get("generator", ""))):
				out.append(String(r["id"]))
	return out


static func _seeds() -> Array:
	var out: Array = []
	for s in range(1, SEEDS + 1):
		out.append(s)
	return out


## Generated defs and their Worlds for (stage_id, seeds), built once per process. Entries: {seed, def, world}.
static func _built(stage_id: String, seeds: Array) -> Array:
	var key := "%s:%s" % [stage_id, str(seeds)]
	if not _cache.has(key):
		var out: Array = []
		for s in seeds:
			var def: Dictionary = StageGen.generate(stage_id, int(s))
			var wd: World = World.from_def(def) if not def.is_empty() else null
			out.append({"seed": int(s), "def": def, "world": wd})
		_cache[key] = out
	return _cache[key]


static func _walkable(e: Dictionary, x: int, y: int) -> bool:
	var def: Dictionary = e["def"]
	var world: World = e["world"]
	var row: String = def["rows"][y]
	return ".@CS".find(row[x]) >= 0 and world.solid_grid[y * world.width + x] == 0


static func _walk_cells(e: Dictionary) -> Array:
	var world: World = e["world"]
	var out: Array = []
	for y in world.height:
		for x in world.width:
			if _walkable(e, x, y):
				out.append(Vector2i(x, y))
	return out


## Mirror of the generic branch of Sonar.fill_rays (Raycast.hit_one per ray), stored like the pulse arrays.
static func _generic_rays(world: World, x: float, y: float, rng_range: float, n: int) -> Dictionary:
	var vis := PackedFloat32Array()
	var vmat := PackedByteArray()
	var vnorm := PackedByteArray()
	vis.resize(n)
	vmat.resize(n)
	vnorm.resize(n)
	for i in n:
		var h: Raycast.Hit = Raycast.hit_one(world, x, y, (float(i) / n) * Sonar.TWO_PI, rng_range)
		vis[i] = h.ray_dist
		if h.hit:
			var mi: int = Sonar.MATS.find(h.mat)
			vmat[i] = 0 if mi < 0 else mi
			vnorm[i] = 0 if h.nx > 0.0 else (1 if h.nx < 0.0 else (2 if h.ny > 0.0 else 3))
		else:
			vmat[i] = 0
			vnorm[i] = Sonar.NO_HIT
	return {"vis": vis, "vmat": vmat, "vnorm": vnorm}


## Walkable origins (sub-cell random) spread round-robin over the entries; each origin gets RAYS_PER_ORIGIN rays.
static func _origins(entries: Array, rng: Rng, count: int) -> Array:
	var out: Array = []
	for i in count:
		var e: Dictionary = entries[i % entries.size()]
		var cells := _walk_cells(e)
		if cells.is_empty():
			continue
		var c: Vector2i = cells[int(floor(rng.next() * cells.size()))]
		out.append({"e": e, "x": c.x + rng.next(), "y": c.y + rng.next(), "range": 2.0 + 11.0 * rng.next()})
	return out


# ---- (1) sampled echo coverage -------------------------------------------------------------------------------------------------------------

func _check_echo_sampling(stage_id: String, seeds: Array) -> void:
	var rng := Rng.new(1201)
	var entries := _built(stage_id, seeds)
	var per: int = int(ceil(float(SAMPLES) / float(seeds.size())))
	var n := 0
	var lit := 0
	var hf := 0.0
	var misses: Array = []
	for e in entries:
		var cells := _walk_cells(e)
		var world: World = e["world"]
		ok(not cells.is_empty(), "%s seed %d: no walkable cells" % [stage_id, e["seed"]])
		if cells.is_empty():
			continue
		for k in per:
			var c: Vector2i = cells[int(floor(rng.next() * cells.size()))]
			var p := Sonar.make_pulse(world, c.x + 0.5, c.y + 0.5, 0.0, ECHO_RANGE, Sonar.SONAR_SPEED, 1.0, "ping", 0, RAYS, 0.5, 3.0)
			n += 1
			if Sonar.strongest_echo(p).is_empty():
				if misses.size() < 5:
					misses.append("seed %d cell (%d,%d)" % [e["seed"], c.x, c.y])
			else:
				lit += 1
			hf += float(Sonar.enclosure(p)["hitFrac"])
	ok(float(lit) >= 0.9 * n, "%s: strongest_echo non-empty in %d/%d samples (need 90%%), first misses %s" % [stage_id, lit, n, str(misses)])
	var mean_hf := hf / maxf(1.0, float(n))
	ok(mean_hf >= 0.2, "%s: mean enclosure hitFrac %.3f over %d samples (need >= 0.2)" % [stage_id, mean_hf, n])


func test_echo_sampling() -> void:
	for id in _stage_ids():
		_check_echo_sampling(id, _seeds())


# ---- (2) fast ray path vs generic path, and depth columns vs their slow variant -------------------------------------------------------------

func _check_fast_rays(stage_id: String, seeds: Array) -> void:
	var rng := Rng.new(1202)
	var entries := _built(stage_id, seeds)
	var origins := _origins(entries, rng, RAY_CHECKS / RAYS_PER_ORIGIN)
	var bad := 0
	var rays := 0
	var first := ""
	for o in origins:
		var world: World = o["e"]["world"]
		var gen := _generic_rays(world, o["x"], o["y"], o["range"], RAYS_PER_ORIGIN)
		var fast := Sonar.Pulse.new()
		Sonar._fill_rays_fast(fast, world, o["x"], o["y"], o["range"], RAYS_PER_ORIGIN)
		for i in RAYS_PER_ORIGIN:
			rays += 1
			if fast.vis[i] != gen["vis"][i] or fast.vmat[i] != gen["vmat"][i] or fast.vnorm[i] != gen["vnorm"][i]:
				bad += 1
				if first == "":
					first = "seed %d origin (%.3f,%.3f) range %.3f ray %d: fast d=%s mat=%d norm=%d, generic d=%s mat=%d norm=%d" % [
						o["e"]["seed"], o["x"], o["y"], o["range"], i,
						str(fast.vis[i]), fast.vmat[i], fast.vnorm[i], str(gen["vis"][i]), gen["vmat"][i], gen["vnorm"][i]]
	ok(bad == 0, "%s: %d of %d rays differ between fast and generic paths; first: %s" % [stage_id, bad, rays, first])
	ok(rays >= RAY_CHECKS, "%s: only %d rays compared" % [stage_id, rays])


func _check_depth_columns(stage_id: String, seeds: Array) -> void:
	var rng := Rng.new(1203)
	var entries := _built(stage_id, seeds)
	var origins := _origins(entries, rng, RAY_CHECKS / RAYS_PER_ORIGIN)
	var offs: Array = Raycast.column_offsets(FOV, COLUMNS)
	var cs: PackedFloat64Array = offs[0]
	var sn: PackedFloat64Array = offs[1]
	var worst := 0.0
	var tch_bad := 0
	for o in origins:
		var world: World = o["e"]["world"]
		var angle: float = rng.next() * Sonar.TWO_PI
		var out_a := PackedFloat32Array()
		var out_b := PackedFloat32Array()
		var tch_a := PackedByteArray()
		var tch_b := PackedByteArray()
		out_a.resize(COLUMNS)
		out_b.resize(COLUMNS)
		tch_a.resize(COLUMNS)
		tch_b.resize(COLUMNS)
		Raycast.depth_columns(world, o["x"], o["y"], angle, cs, sn, o["range"], out_a, tch_a)
		Raycast._depth_columns_slow(world, o["x"], o["y"], angle, cs, sn, o["range"], out_b, tch_b)
		for i in COLUMNS:
			worst = maxf(worst, absf(out_a[i] - out_b[i]))
			if tch_a[i] != tch_b[i]:
				tch_bad += 1
	ok(worst <= 1e-4, "%s: depth_columns vs _depth_columns_slow worst diff %s" % [stage_id, str(worst)])
	ok(tch_bad == 0, "%s: %d tile codes differ between depth_columns and its slow variant" % [stage_id, tch_bad])


func test_fast_rays_match_generic() -> void:
	for id in _stage_ids():
		_check_fast_rays(id, _seeds())


func test_depth_columns_match_slow() -> void:
	for id in _stage_ids():
		_check_depth_columns(id, _seeds())


# ---- (3) a ping from the start cell ------------------------------------------------------------------------------------------------------

func _check_start_ping(stage_id: String, seeds: Array) -> void:
	for e in _built(stage_id, seeds):
		var def: Dictionary = e["def"]
		var world: World = e["world"]
		var st: Dictionary = def["start"]
		var sx: int = int(st["cell"][0])
		var sy: int = int(st["cell"][1])
		var s := Sonar.create()
		var fired := s.emit(world, sx + 0.5, sy + 0.5, 0.0, {"facing": float(st["angle"])})
		ok(fired, "%s seed %d: ping from start (%d,%d) refused" % [stage_id, e["seed"], sx, sy])
		ok(s.pulses.size() > 0, "%s seed %d: ping made no pulses" % [stage_id, e["seed"]])
		var with_rays := 0
		for p in s.pulses:
			if p.vis.size() > 0:
				with_rays += 1
		ok(with_rays == s.pulses.size(), "%s seed %d: %d pulses without rays" % [stage_id, e["seed"], s.pulses.size() - with_rays])
		ok(s.last_pulse != null and s.last_pulse.vis.size() == RAYS, "%s seed %d: primary ping ray count" % [stage_id, e["seed"]])


func test_start_ping() -> void:
	for id in _stage_ids():
		_check_start_ping(id, _seeds())


# ---- (4) zone reverb times inside the acoustic bounds ----------------------------------------------------------------------------------------

func _check_zone_t60(stage_id: String, seeds: Array) -> void:
	var ac: Dictionary = Acoustics.a()
	var lo: float = float(ac["t60Min"])
	var hi: float = float(ac["t60Max"])
	var zones := 0
	for e in _built(stage_id, seeds):
		var def: Dictionary = e["def"]
		for z in def["zones"]:
			zones += 1
			var t: float = Acoustics.t60_for(String(z["name"]), String(z.get("kind", "indoor")))
			ok(t >= lo and t <= hi, "%s seed %d zone %s: t60 %.4f outside [%s, %s]" % [stage_id, e["seed"], z["name"], t, str(lo), str(hi)])
	ok(zones > 0, "%s: no zones" % stage_id)


func test_zone_t60_bounds() -> void:
	for id in _stage_ids():
		_check_zone_t60(id, _seeds())


# ---- (5) still water: rays cross it, movement is blocked -----------------------------------------------------------------------------------

func _check_water(stage_id: String, seeds: Array) -> void:
	var total := 0
	var dirs: Array = [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]
	for e in _built(stage_id, seeds):
		var def: Dictionary = e["def"]
		var world: World = e["world"]
		var rows: Array = def["rows"]
		for y in world.height:
			var row: String = rows[y]
			for x in world.width:
				if row[x] != "~":
					continue
				total += 1
				var cx := x + 0.5
				var cy := y + 0.5
				ok(world.blocks(cx, cy, 0.3), "%s seed %d water (%d,%d): blocks() false" % [stage_id, e["seed"], x, y])
				for d in dirs:
					var nb: Vector2i = Vector2i(x, y) + d
					var a: float = atan2(float(d.y), float(d.x))
					var h: Raycast.Hit = Raycast.hit_one(world, cx, cy, a, 3.0)
					if world.solid_grid[nb.y * world.width + nb.x] == 1:
						ok(h.hit and absf(h.ray_dist - 0.5) < 1e-4, "%s seed %d water (%d,%d) dir (%d,%d): wall at neighbour not seen at 0.5 (hit %s d %s)" % [stage_id, e["seed"], x, y, d.x, d.y, str(h.hit), str(h.ray_dist)])
					else:
						ok(not h.hit or h.ray_dist > 0.5 + 1e-4, "%s seed %d water (%d,%d) dir (%d,%d): ray stopped at the water cell" % [stage_id, e["seed"], x, y, d.x, d.y])
	ok(total > 0, "%s: no water cells in %d seeds" % [stage_id, seeds.size()])


func test_water_passes_rays_blocks_movement() -> void:
	for id in _stage_ids():
		_check_water(id, _seeds())


# ---- (6) every cave has light ------------------------------------------------------------------------------------------------------------

func _check_lights(stage_id: String, seeds: Array) -> void:
	for e in _built(stage_id, seeds):
		var def: Dictionary = e["def"]
		ok(def["lights"].size() >= 1, "%s seed %d: no lights" % [stage_id, e["seed"]])


func test_every_cave_has_light() -> void:
	for id in _stage_ids():
		_check_lights(id, _seeds())


# ---- (7) border ring is wall of the expected material ------------------------------------------------------------------------------------

func _check_border(stage_id: String, seeds: Array) -> void:
	for e in _built(stage_id, seeds):
		var def: Dictionary = e["def"]
		var world: World = e["world"]
		var rows: Array = def["rows"]
		var want: String = String(def["materials"]["#"])
		var want_idx: int = Sonar.MATS.find(want)
		var bad := 0
		var first := ""
		for y in world.height:
			for x in world.width:
				if x != 0 and y != 0 and x != world.width - 1 and y != world.height - 1:
					continue
				var k: int = y * world.width + x
				var row: String = rows[y]
				var why := ""
				if row[x] != "#":
					why = "char %s" % row[x]
				elif world.solid_grid[k] != 1:
					why = "not solid"
				elif world.material_at(x + 0.5, y + 0.5) != want:
					why = "material %s" % world.material_at(x + 0.5, y + 0.5)
				elif world.mat_grid[k] != want_idx:
					why = "ray material index %d (want %d)" % [world.mat_grid[k], want_idx]
				if why != "":
					bad += 1
					if first == "":
						first = "(%d,%d) %s" % [x, y, why]
		ok(bad == 0, "%s seed %d: %d border cells off (want '#' %s); first %s" % [stage_id, e["seed"], bad, want, first])


func test_border_material() -> void:
	for id in _stage_ids():
		_check_border(id, _seeds())


# ---- (8) 60 s soak of Ambient with the stage's own anchors ----------------------------------------------------------------------------------

func _check_ambient_soak(stage_id: String, seeds: Array) -> void:
	for e in _built(stage_id, seeds):
		var def: Dictionary = e["def"]
		var world: World = e["world"]
		var st: Dictionary = def["start"]
		var pos := Vector2(int(st["cell"][0]) + 0.5, int(st["cell"][1]) + 0.5)
		var amb := Ambient.new([], {})
		var added := 0
		for an in def["ambient"]:
			if amb.add(an):
				added += 1
		var s := Sonar.create()
		s.emit(world, pos.x, pos.y, 0.0, {"facing": float(st["angle"])})
		var ping: Sonar.Pulse = s.last_pulse
		var rng := Rng.new(7)
		var t := 0.0
		var steps: int = int(round(SOAK_SEC / SOAK_DT))
		var peak := 0
		var ping_lost := false
		var over := false
		for i in steps:
			t += SOAK_DT
			amb.step(world, s, pos, SOAK_DT, rng, t)
			peak = maxi(peak, s.pulses.size())
			if s.pulses.size() > 64:
				over = true
			if not ping_lost and not s.pulses.has(ping):
				ping_lost = true
		ok(not over, "%s seed %d: ring grew past 64 (peak %d, %d anchors)" % [stage_id, e["seed"], peak, added])
		ok(not ping_lost, "%s seed %d: player ping evicted during the 60 s soak" % [stage_id, e["seed"]])
		ok(s.pulses.has(ping), "%s seed %d: player ping absent at the end of the soak" % [stage_id, e["seed"]])
		ok(amb.emitted > 0 or added == 0, "%s seed %d: anchors added but nothing emitted" % [stage_id, e["seed"]])


func test_ambient_soak() -> void:
	for id in _stage_ids():
		_check_ambient_soak(id, _seeds())


# ---- (9) open air: every walkable cell of an outdoor stage has a wall cell within R (wild 6) -----------------------------------------------------

const OPEN_AIR_R := 6.0


func _check_open_air(stage_id: String, seeds: Array) -> void:
	var worst := 0.0
	var n := 0
	for e in _built(stage_id, seeds):
		var def: Dictionary = e["def"]
		if String(def["kind"]) != "outdoor":
			continue
		n += 1
		var oa := GenWild.open_air_max(def)
		worst = maxf(worst, oa)
		ok(oa <= OPEN_AIR_R, "%s seed %d: a walkable cell is %.2f from the nearest wall (limit %.1f)" % [stage_id, e["seed"], oa, OPEN_AIR_R])
	if n > 0:
		print("echo_env: %s open-air worst distance %.2f over %d seeds (limit %.1f)" % [stage_id, worst, n, OPEN_AIR_R])


func test_open_air_rule() -> void:
	var outdoor := 0
	for id in _stage_ids():
		_check_open_air(id, _seeds())
		if String(StageGen.stage_row(id).get("kind", "")) == "outdoor":
			outdoor += 1
	ok(outdoor >= 2, "the outdoor stages (wood, moor) are in the suite")
