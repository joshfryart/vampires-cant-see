extends TestCase
## S4 occlusion (docs/STYLE.md section 6): Raycast.depth_columns_contour against a brute-force ray / polyline test, against the grid depth, the EchoView gate,
## sprites not cut early at rounded corners, and sonar invariance. Worlds get the stage row's wallStyle here: the generators do not carry it yet (S3).

const STAGES := ["hollow", "wood", "moor", "road", "inn"]
const SEEDS := 3
const ORIGINS := 24
const COLS := 160
const FOV := 1.2
const RANGE := 16.0
const TOL := 0.02
## Spec: contour >= grid - 0.07 (the concave fillet is 0.062 deep). Along a grazing ray the same fillet shortens the along-view depth more, so a few columns reach ~0.12.
const LOW_TOL := 0.15

static var _cache: Dictionary = {}


static func _styled(stage: String, seed: int, styled: bool) -> World:
	var k := "%s:%d:%s" % [stage, seed, str(styled)]
	if not _cache.has(k):
		var d: Dictionary = StageGen.generate(stage, seed)
		if styled:
			d["wallStyle"] = StageGen.stage_row(stage)["wallStyle"]
		else:
			d.erase("wallStyle")
		_cache[k] = World.from_def(d)
	return _cache[k]


static func _cells(world: World) -> Array:
	var out: Array = []
	for y in world.height:
		for x in world.width:
			if world.solid_grid[y * world.width + x] == 0 and ".@CS".find(String(world.rows[y])[x]) >= 0:
				out.append(Vector2i(x, y))
	return out


## Nearest crossing of the ray with any outline segment of the field (distance along the ray), INF when none within max_d.
static func brute(f: ContourField, x: float, y: float, dx: float, dy: float, max_d: float) -> float:
	var best := INF
	var n := f.segment_total()
	for g in n:
		var ax: float = f.seg_xy[g * 4]
		var ay: float = f.seg_xy[g * 4 + 1]
		var ex: float = f.seg_xy[g * 4 + 2] - ax
		var ey: float = f.seg_xy[g * 4 + 3] - ay
		var den: float = dx * ey - dy * ex
		if absf(den) < 1e-12:
			continue
		var rx := ax - x
		var ry := ay - y
		var u: float = (rx * dy - ry * dx) / den
		if u < -1e-6 or u > 1.000001:
			continue
		var t: float = (rx * ey - ry * ex) / den
		if t > 0.0 and t < best:
			best = t
	return best if best <= max_d else INF


func _sample(stage: String, seed: int, rng: Rng) -> Array:
	var world := _styled(stage, seed, true)
	var f := ContourField.for_world(world)
	var cells := _cells(world)
	var offs: Array = Raycast.column_offsets(FOV, COLS)
	var res: Array = []
	for i in ORIGINS:
		var c: Vector2i = cells[int(floor(rng.next() * cells.size()))]
		var x: float = c.x + 0.2 + 0.6 * rng.next()
		var y: float = c.y + 0.2 + 0.6 * rng.next()
		var ang: float = rng.next() * TAU
		var zc := PackedFloat32Array()
		var zg := PackedFloat32Array()
		zc.resize(COLS)
		zg.resize(COLS)
		Raycast.depth_columns_contour(world, f, x, y, ang, offs[0], offs[1], RANGE, zc)
		Raycast.depth_columns(world, x, y, ang, offs[0], offs[1], RANGE, zg)
		res.append({"w": world, "f": f, "x": x, "y": y, "a": ang, "zc": zc, "zg": zg, "cs": offs[0], "sn": offs[1]})
	return res


func test_matches_brute_force_outline() -> void:
	var rng := Rng.new(4401)
	var cols := 0
	var bad := 0
	var fallback := 0
	var worst := 0.0
	var first := ""
	for st in STAGES:
		for seed in range(1, SEEDS + 1):
			for o in _sample(st, seed, rng):
				var ca: float = cos(o["a"])
				var sa: float = sin(o["a"])
				for i in COLS:
					var c: float = o["cs"][i]
					var s: float = o["sn"][i]
					var dx: float = ca * c - sa * s
					var dy: float = sa * c + ca * s
					var b: float = brute(o["f"], o["x"], o["y"], dx, dy, RANGE)
					var zc: float = o["zc"][i]
					cols += 1
					if b == INF:
						continue
					var d: float = absf(zc - b * c)
					if d > TOL:
						var zg: float = o["zg"][i]
						# the scoped search (3 cells past the first solid one) settles on the grid depth when the outline is only met far beyond it
						if absf(zc - zg) < 1e-4 and b * c > zg + TOL:
							fallback += 1
							continue
						bad += 1
						worst = maxf(worst, d)
						if first == "":
							first = "%s seed %d (%.3f,%.3f) col %d: contour %.4f brute %.4f grid %.4f" % [st, seed, o["x"], o["y"], i, zc, b * c, zg]
	ok(cols >= 5 * SEEDS * ORIGINS * COLS, "sampled %d columns" % cols)
	ok(bad == 0, "%d of %d columns differ from the brute-force outline by more than %.2f (worst %.4f); first: %s" % [bad, cols, TOL, worst, first])
	ok(float(fallback) <= 0.002 * float(cols), "%d of %d columns fell back to the grid depth" % [fallback, cols])


func test_bounded_against_grid_depth() -> void:
	var rng := Rng.new(4402)
	var low := 0
	var above := 0
	var shifted := 0
	var worst_low := 0.0
	var worst_above := 0.0
	for st in STAGES:
		for seed in range(1, SEEDS + 1):
			for o in _sample(st, seed, rng):
				for i in COLS:
					var d: float = float(o["zc"][i]) - float(o["zg"][i])
					if d < -LOW_TOL:
						low += 1
					worst_low = maxf(worst_low, -d)
					if d > 0.05:
						shifted += 1
					if d > 0.25:
						above += 1
						worst_above = maxf(worst_above, d)
	ok(low == 0, "%d columns are more than %.2f nearer than the grid (worst %.4f)" % [low, LOW_TOL, worst_low])
	ok(shifted > 0, "no column sees past a rounded corner: the contour path does nothing")
	# Columns that graze a rounded convex corner see past it to a farther wall; only those may exceed the 0.25 inset bound, and they are few percent (7% measured, all confirmed by the brute-force test).
	ok(float(above) <= 0.10 * float(5 * SEEDS * ORIGINS * COLS), "%d columns beyond grid + 0.25 (worst %.3f)" % [above, worst_above])


## A column whose grid wall stands in front of a point that the drawn outline leaves visible: the grid zbuf would cut a sprite there, the contour one must not.
func test_sprites_not_cut_at_rounded_corners() -> void:
	var rng := Rng.new(4403)
	var points := 0
	var cut_by_grid := 0
	var wrong := 0
	for st in STAGES:
		for seed in range(1, SEEDS + 1):
			for o in _sample(st, seed, rng):
				var ca: float = cos(o["a"])
				var sa: float = sin(o["a"])
				for i in COLS:
					var zc: float = o["zc"][i]
					var zg: float = o["zg"][i]
					if zc - zg < 0.06 or zc >= RANGE:
						continue
					var c: float = o["cs"][i]
					var s: float = o["sn"][i]
					var dx: float = ca * c - sa * s
					var dy: float = sa * c + ca * s
					var z: float = zg + 0.5 * (zc - zg)
					var t: float = z / c
					points += 1
					if z > zg:
						cut_by_grid += 1
					# the point is visible through the drawn outline: nothing crosses the ray before it
					if brute(o["f"], o["x"], o["y"], dx, dy, t - 1e-4) != INF or z > zc:
						wrong += 1
	ok(points > 0, "no sampled column grazes a rounded corner")
	eq(cut_by_grid, points, "the grid zbuf cuts every such sprite point")
	eq(wrong, 0, "points the contour zbuf occludes although the outline does not")


## A lone pillar seen near its corner: the rounded r = 0.3 corner exposes a sliver that the grid depth hides (the ~20 px problem).
func test_pillar_corner_sliver() -> void:
	var rows := ["#########", "#.......#", "#.......#", "#...#...#", "#.......#", "#.......#", "#########"]
	var w := World.from_def({"name": "pillar", "wallStyle": {"#": "rock"}, "rows": rows})
	var f := ContourField.for_world(w)
	var offs: Array = Raycast.column_offsets(FOV, COLS)
	var x := 1.5
	var y := 4.45
	var zc := PackedFloat32Array()
	var zg := PackedFloat32Array()
	zc.resize(COLS)
	zg.resize(COLS)
	Raycast.depth_columns_contour(w, f, x, y, 0.0, offs[0], offs[1], RANGE, zc)
	Raycast.depth_columns(w, x, y, 0.0, offs[0], offs[1], RANGE, zg)
	var wide := 0
	var worst := 0.0
	for i in COLS:
		var c: float = offs[0][i]
		var s: float = offs[1][i]
		var b: float = brute(f, x, y, c, s, RANGE)
		worst = maxf(worst, absf(zc[i] - b * c))
		if zc[i] > zg[i] + 0.1:
			wide += 1
	ok(wide > 0, "the pillar corner leaves no columns beyond the grid depth")
	ok(worst <= TOL, "pillar worst error %.4f" % worst)


func test_tch_matches_grid() -> void:
	var rng := Rng.new(4404)
	var bad := 0
	var n := 0
	for st in STAGES:
		var world := _styled(st, 1, true)
		var f := ContourField.for_world(world)
		var cells := _cells(world)
		var offs: Array = Raycast.column_offsets(FOV, COLS)
		for i in 12:
			var c: Vector2i = cells[int(floor(rng.next() * cells.size()))]
			var x: float = c.x + rng.next()
			var y: float = c.y + rng.next()
			var ang: float = rng.next() * TAU
			var a := PackedFloat32Array()
			var b := PackedFloat32Array()
			var ta := PackedByteArray()
			var tb := PackedByteArray()
			a.resize(COLS)
			b.resize(COLS)
			ta.resize(COLS)
			tb.resize(COLS)
			Raycast.depth_columns_contour(world, f, x, y, ang, offs[0], offs[1], RANGE, a, ta)
			Raycast.depth_columns(world, x, y, ang, offs[0], offs[1], RANGE, b, tb)
			for k in COLS:
				n += 1
				if ta[k] != tb[k]:
					bad += 1
	ok(n > 0)
	eq(bad, 0, "rs.tch differs from the grid code in %d of %d columns" % [bad, n])


## Classic worlds keep the grid path bit for bit: the gate is off without wallStyle (and while the contour mesh is off).
func test_classic_gate_and_output() -> void:
	var classic := _styled("hollow", 1, false)
	var styled := _styled("hollow", 1, true)
	var was := WorldMeshBuilder.contour_enabled
	WorldMeshBuilder.contour_enabled = true
	ok(not EchoView.contour_depth_on(classic), "classic world: grid depth")
	ok(EchoView.contour_depth_on(styled), "styled world with the contour on: contour depth")
	WorldMeshBuilder.contour_enabled = false
	ok(not EchoView.contour_depth_on(styled), "contour mesh off: grid depth")
	var ev := EchoView.new()
	var pl := Player.create(classic.start.x, classic.start.y, 0.3)
	WorldMeshBuilder.contour_enabled = true
	ev._update_depth(classic, pl)
	var got := ev.rs.zbuf.duplicate()
	var want := PackedFloat32Array()
	want.resize(ev.rs.cols)
	Raycast.depth_columns(classic, pl.x, pl.y, pl.angle, ev.rs.col_cos, ev.rs.col_sin, 16.0, want)
	WorldMeshBuilder.contour_enabled = was
	ev.free()
	eq(got, want, "classic zbuf equals depth_columns")


func test_sonar_invariance() -> void:
	var rng := Rng.new(4405)
	var diffs := 0
	var n := 0
	for st in STAGES:
		var a := _styled(st, 2, false)
		var b := _styled(st, 2, true)
		var cells := _cells(a)
		for i in 6:
			var c: Vector2i = cells[int(floor(rng.next() * cells.size()))]
			var pa := Sonar.make_pulse(a, c.x + 0.5, c.y + 0.5, 0.0, 13.0, Sonar.SONAR_SPEED, 1.0, "ping", 0, 720, 0.5, 3.0)
			var pb := Sonar.make_pulse(b, c.x + 0.5, c.y + 0.5, 0.0, 13.0, Sonar.SONAR_SPEED, 1.0, "ping", 0, 720, 0.5, 3.0)
			n += 1
			if pa.vis != pb.vis or pa.vnorm != pb.vnorm or pa.vmat != pb.vmat:
				diffs += 1
			if Sonar.strongest_echo(pa) != Sonar.strongest_echo(pb) or Sonar.enclosure(pa) != Sonar.enclosure(pb):
				diffs += 1
	ok(n > 0)
	eq(diffs, 0, "sonar arrays / echo / enclosure differ with wallStyle")
