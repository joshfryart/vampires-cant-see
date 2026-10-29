extends TestCase
## S1 contour geometry (docs/STYLE.md section 2 and the S1 acceptance list): ContourField.build / for_world and the contour mesh path of WorldMeshBuilder.
## Since 0.21.3 (S3) the game switches WorldMeshBuilder.contour_enabled on at boot and the generators carry wallStyle; these tests set the switch explicitly.

const STAGES := ["hollow", "wood", "moor", "road", "inn"]
## 50 seeds x 5 stages for the cheap per-vertex checks; the expensive ones (rebuild compare, self-intersection, mesh) use fewer.
const SEEDS := 50
const FEW := 10
## Pre-change hashes of the classic wall mesh (vertex, normal, color, uv, index bytes), captured before WorldMeshBuilder was touched.
const CLASSIC_HASH := {"crypt": 3992633256, "test": 208008445, "town": 2024417853}
## hollow re-pinned in 0.21.6 (cave wayfinding: breadcrumbs, spur tells, 2-wide tunnels changed the generated layout); the other stages are unchanged.
const CLASSIC_STAGE_HASH := {"hollow": 327397900, "wood": 918674218, "moor": 1415106364, "road": 4057627582, "inn": 3587000798}

static var _cache: Dictionary = {}


func _def(stage: String, seed: int, styled: bool = true) -> Dictionary:
	var d: Dictionary = StageGen.generate(stage, seed)
	if styled:
		d["wallStyle"] = StageGen.stage_row(stage)["wallStyle"]
	else:
		d.erase("wallStyle")   # the generators carry wallStyle since 0.21.3
	return d


func _world(stage: String, seed: int) -> World:
	var k := "%s:%d" % [stage, seed]
	if not _cache.has(k):
		var w := World.from_def(_def(stage, seed))
		w.contour = ContourField.build(w)
		_cache[k] = w
	return _cache[k]


func _mesh_hash(m: ArrayMesh) -> int:
	if m.get_surface_count() == 0:
		return 0
	var a := m.surface_get_arrays(0)
	var buf := PackedByteArray()
	for k in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_COLOR, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_INDEX]:
		buf.append_array(a[k].to_byte_array())
	return hash(buf)


# ---- world wiring ----

func test_world_style_and_seed() -> void:
	var w := World.from_def({"name": "a", "rows": ["###", "#@#", "###"]})
	ok(w.wall_style.is_empty(), "no wallStyle: classic")
	eq(w.map_seed, World.name_seed("a"), "seed falls back to the name hash")
	ok(World.name_seed("a") != World.name_seed("b"), "name hash differs")
	var w2 := World.from_def({"name": "a", "seed": 1234, "wallStyle": {"#": "rock"}, "rows": ["###", "#@#", "###"]})
	eq(w2.map_seed, 1234, "def seed wins")
	eq(w2.wall_style, {"#": "rock"}, "wallStyle read from the def")
	ok(w2.contour == null, "contour is lazy")
	var f := ContourField.for_world(w2)
	ok(w2.contour == f, "for_world caches on the world")
	ok(ContourField.for_world(w2) == f, "second call reuses it")


func test_stage_rows_have_wall_style() -> void:
	var want := {
		"hollow": {"#": "rock"},
		"wood": {"#": "thicket", "W": "trunk"},
		"moor": {"#": "gorse", "B": "cairn", "I": "gibbet"},
		"road": {"#": "thicket", "B": "milestone", "I": "fence", "W": "trunk"},
		"inn": {"#": "drystone", "W": "timber", "B": "milestone", "I": "fence"},
	}
	for st in STAGES:
		var ws: Variant = StageGen.stage_row(st).get("wallStyle")
		eq(ws, want[st], st + " wallStyle")
		for name in ws.values():
			ok(ContourField.STYLE_IDS.has(name), "known style " + str(name))


# ---- determinism ----

func test_rebuild_is_byte_identical() -> void:
	for st in STAGES:
		for seed in range(1, FEW + 1):
			var w := _world(st, seed)
			var again := ContourField.build(w)
			eq(again.fingerprint(), w.contour.fingerprint(), "%s %d rebuild" % [st, seed])
			eq(again.loop_count(), w.contour.loop_count(), "loops")
	var w1 := _world("hollow", 3)
	var m1 := WorldMeshBuilder.build_contour(w1)
	var w2 := World.from_def(_def("hollow", 3))
	var m2 := WorldMeshBuilder.build_contour(w2)
	eq(_mesh_hash(m1), _mesh_hash(m2), "contour mesh bytes identical on rebuild")


func test_other_seed_differs() -> void:
	for st in STAGES:
		var w := _world(st, 1)
		var w2 := World.from_def(_def(st, 1))
		w2.map_seed = w.map_seed ^ 0x5A5A5A
		var other := ContourField.build(w2)
		ok(other.fingerprint() != w.contour.fingerprint(), st + ": a different map seed changes the outline")
		eq(other.loop_count(), w.contour.loop_count(), st + ": topology does not depend on the seed")


## An island far from everything else changes no existing loop (noise is keyed on lattice coordinates, not traversal).
func test_far_island_leaves_loops_identical() -> void:
	for st in STAGES:
		var d := _def(st, 2)
		var base := World.from_def(d)
		var spot := _open_spot(base, 2)
		ok(spot != Vector2i(-1, -1), st + ": found open ground for an island")
		if spot.x < 0:
			continue
		var rows: Array = d["rows"].duplicate()
		for dy in 2:
			var row: String = rows[spot.y + dy]
			rows[spot.y + dy] = row.substr(0, spot.x) + "##" + row.substr(spot.x + 2)
		var d2: Dictionary = d.duplicate()
		d2["rows"] = rows
		var w2 := World.from_def(d2)
		var f0 := ContourField.build(base)
		var f1 := ContourField.build(w2)
		eq(f1.loop_count(), f0.loop_count() + 1, st + ": one more loop")
		var matched := 0
		for l0: ContourField.Loop in f0.loops:
			for l1: ContourField.Loop in f1.loops:
				if l0.pos == l1.pos and l0.anchor == l1.anchor and l0.nrm == l1.nrm and l0.curv == l1.curv and l0.s == l1.s:
					matched += 1
					break
		eq(matched, f0.loop_count(), st + ": every existing loop is identical")


## Top-left of a size x size block of open cells with a 1-cell open margin all around (far from every wall).
func _open_spot(w: World, size: int) -> Vector2i:
	for y in range(3, w.height - size - 3):
		for x in range(3, w.width - size - 3):
			var clear := true
			for dy in range(-1, size + 1):
				for dx in range(-1, size + 1):
					if w.cell_solid(x + dx, y + dy) or w.tile_grid[(y + dy) * w.width + x + dx] == 126:
						clear = false
						break
				if not clear:
					break
			if clear:
				return Vector2i(x, y)
	return Vector2i(-1, -1)


# ---- geometry bounds ----

func _on_boundary(w: World, a: Vector2) -> bool:
	var eps := 1e-4
	if absf(a.x - roundf(a.x)) < eps:
		var xi := int(roundf(a.x))
		for off in [1e-3, -1e-3]:
			var yy := int(floor(a.y + off))
			if w.cell_solid(xi - 1, yy) != w.cell_solid(xi, yy):
				return true
	if absf(a.y - roundf(a.y)) < eps:
		var yi := int(roundf(a.y))
		for off in [1e-3, -1e-3]:
			var xx := int(floor(a.x + off))
			if w.cell_solid(xx, yi - 1) != w.cell_solid(xx, yi):
				return true
	return false


func test_anchor_and_displacement_bounds() -> void:
	var worst_p := 0.0
	var worst_face := 0.0
	var worst_out := 0.0
	var verts := 0
	var bad_anchor := 0
	var bad_solid := 0
	for st in STAGES:
		for seed in range(1, SEEDS + 1):
			var w := _world(st, seed)
			for l: ContourField.Loop in w.contour.loops:
				for i in l.size():
					verts += 1
					var a := l.anchor[i]
					var p := l.pos[i]
					if not _on_boundary(w, a):
						bad_anchor += 1
					var d := p - a
					worst_p = maxf(worst_p, d.length())
					if l.arc[i] == 0 and l.fillet[i] == 0:
						var dn := d.dot(l.ng[i])
						worst_face = maxf(worst_face, -dn)
						worst_out = maxf(worst_out, dn)
					# in a solid cell (probed a hair inward), or on a concave fillet within 0.063 of the corner
					var probe := p - l.ng[i] * 1e-3
					if not w.cell_solid(floori(probe.x), floori(probe.y)):
						var corner := Vector2(roundf(a.x), roundf(a.y))
						if not (l.fillet[i] == 1 and p.distance_to(corner) <= 0.063):
							bad_solid += 1
	ok(verts > 100000, "checked many vertices (%d)" % verts)
	eq(bad_anchor, 0, "every anchor lies on the grid boundary")
	eq(bad_solid, 0, "every vertex is in a solid cell or within 0.063 of a concave corner")
	ok(worst_p <= 0.25 + 1e-4, "|p - anchor| <= 0.25 (worst %f)" % worst_p)
	ok(worst_face <= 0.2 + 1e-4, "face displacement <= 0.2 (worst %f)" % worst_face)
	ok(worst_out <= 1e-4, "straight faces never move outward (worst %f)" % worst_out)


func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var l2 := ab.length_squared()
	if l2 < 1e-18:
		return p.distance_to(a)
	return p.distance_to(a + ab * clampf((p - a).dot(ab) / l2, 0.0, 1.0))


func _clearance(f: ContourField, p: Vector2) -> float:
	var best := 9.0
	var cx := floori(p.x)
	var cy := floori(p.y)
	for yy in range(cy - 1, cy + 2):
		for xx in range(cx - 1, cx + 2):
			if xx < 0 or yy < 0 or xx >= f.width or yy >= f.height:
				continue
			var k := yy * f.width + xx
			for si in range(f.cell_start[k], f.cell_start[k + 1]):
				var g := f.cell_seg[si]
				best = minf(best, _seg_dist(p, Vector2(f.seg_xy[g * 4], f.seg_xy[g * 4 + 1]), Vector2(f.seg_xy[g * 4 + 2], f.seg_xy[g * 4 + 3])))
	return best


func test_walkable_clearance() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var worst := 9.0
	var n := 0
	for st in STAGES:
		for seed in range(1, 11):
			var w := _world(st, seed)
			for t in 300:
				var p := Vector2(rng.randf_range(0.0, w.width), rng.randf_range(0.0, w.height))
				if w.blocks(p.x, p.y, 0.2):
					continue
				n += 1
				worst = minf(worst, _clearance(w.contour, p))
	ok(n > 5000, "sampled walkable positions (%d)" % n)
	ok(worst >= 0.13, "walkable positions keep >= 0.13 from the outline (min %f)" % worst)


## The narrowest squeeze: a zigzag corridor one cell wide, every walkable position of the 0.2 player on a 0.02 grid.
func test_one_wide_squeeze_clearance() -> void:
	var rows := [
		"##########",
		"#@.#######",
		"##.#######",
		"##...#####",
		"####.#####",
		"####..#.##",
		"#####.#.##",
		"#####...##",
		"##########",
	]
	var w := World.from_def({"name": "squeeze", "seed": 5, "wallStyle": {"#": "rock"}, "rows": rows})
	var f := ContourField.for_world(w)
	var worst := 9.0
	var worst_corner := 9.0
	var corner_pts: Array = []
	for l: ContourField.Loop in f.loops:
		for i in l.size():
			if l.corner[i] == 2:
				corner_pts.append(l.pos[i])
	ok(corner_pts.size() >= 8, "squeeze has concave corners (%d)" % corner_pts.size())
	var n := 0
	var y := 0.0
	while y < w.height:
		var x := 0.0
		while x < w.width:
			if not w.blocks(x, y, 0.2):
				n += 1
				var p := Vector2(x, y)
				worst = minf(worst, _clearance(f, p))
				for c in corner_pts:
					worst_corner = minf(worst_corner, p.distance_to(c))
			x += 0.02
		y += 0.02
	ok(n > 1000, "walkable samples in the squeeze (%d)" % n)
	ok(worst >= 0.2 - 1e-3, "clearance to the outline >= the 0.2 collision radius (min %f)" % worst)
	ok(worst_corner >= 0.22, "clearance to a concave fillet >= 0.22 (min %f)" % worst_corner)


func _crosses(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> bool:
	var d1 := (b - a).cross(c - a)
	var d2 := (b - a).cross(d - a)
	var d3 := (d - c).cross(a - c)
	var d4 := (d - c).cross(b - c)
	return ((d1 > 1e-9 and d2 < -1e-9) or (d1 < -1e-9 and d2 > 1e-9)) and ((d3 > 1e-9 and d4 < -1e-9) or (d3 < -1e-9 and d4 > 1e-9))


func test_loops_never_self_intersect() -> void:
	var tested := 0
	for st in STAGES:
		for seed in range(1, FEW + 1):
			var w := _world(st, seed)
			var f: ContourField = w.contour
			var hits := 0
			for k in f.width * f.height:
				var s0 := f.cell_start[k]
				var s1 := f.cell_start[k + 1]
				for i in range(s0, s1):
					var gi := f.cell_seg[i]
					for j in range(i + 1, s1):
						var gj := f.cell_seg[j]
						if f.seg_loop[gi] == f.seg_loop[gj]:
							var n: int = f.loops[f.seg_loop[gi]].size()
							var dv: int = absi(f.seg_vert[gi] - f.seg_vert[gj])
							if dv <= 1 or dv >= n - 1:
								continue
						tested += 1
						if _crosses(Vector2(f.seg_xy[gi * 4], f.seg_xy[gi * 4 + 1]), Vector2(f.seg_xy[gi * 4 + 2], f.seg_xy[gi * 4 + 3]), Vector2(f.seg_xy[gj * 4], f.seg_xy[gj * 4 + 1]), Vector2(f.seg_xy[gj * 4 + 2], f.seg_xy[gj * 4 + 3])):
							hits += 1
			eq(hits, 0, "%s %d: no segment crossings" % [st, seed])
	ok(tested > 10000, "segment pairs tested (%d)" % tested)


# ---- segment index ----

func test_segment_index_covers_every_segment() -> void:
	var w := _world("wood", 4)
	var f: ContourField = w.contour
	var seen := {}
	for i in f.cell_seg.size():
		seen[f.cell_seg[i]] = true
	eq(f.cell_start[f.width * f.height], f.cell_seg.size(), "CSR total")
	var inside := 0
	for g in f.segment_total():
		var cx := floori(f.seg_xy[g * 4])
		var cy := floori(f.seg_xy[g * 4 + 1])
		if cx >= 0 and cy >= 0 and cx < f.width and cy < f.height:
			inside += 1
			var k := cy * f.width + cx
			var found := false
			for si in range(f.cell_start[k], f.cell_start[k + 1]):
				if f.cell_seg[si] == g:
					found = true
			ok(found, "segment %d listed in its start cell" % g)
	ok(inside > 0, "segments inside the map")


# ---- mesh ----

func test_classic_mesh_unchanged() -> void:
	var was := WorldMeshBuilder.contour_enabled
	for name in CLASSIC_HASH:
		var w := World.from_def(GameData.map_def(name))
		eq(_mesh_hash(WorldMeshBuilder.build(w)), CLASSIC_HASH[name], name + " classic mesh bytes")
		WorldMeshBuilder.contour_enabled = true
		eq(_mesh_hash(WorldMeshBuilder.build(w)), CLASSIC_HASH[name], name + " classic mesh bytes with the contour switch on")
		WorldMeshBuilder.contour_enabled = was
	for st in STAGES:
		var w := World.from_def(_def(st, 7, false))
		eq(_mesh_hash(WorldMeshBuilder.build(w)), CLASSIC_STAGE_HASH[st], st + " generated map without wallStyle")
		WorldMeshBuilder.contour_enabled = true
		eq(_mesh_hash(WorldMeshBuilder.build(w)), CLASSIC_STAGE_HASH[st], st + " without wallStyle, switch on")
		WorldMeshBuilder.contour_enabled = was
		var ws := World.from_def(_def(st, 7, true))
		WorldMeshBuilder.contour_enabled = false
		eq(_mesh_hash(WorldMeshBuilder.build(ws)), CLASSIC_STAGE_HASH[st], st + " with wallStyle but the switch off: dormant")
		WorldMeshBuilder.contour_enabled = was


func test_contour_switch_selects_contour_path() -> void:
	var was := WorldMeshBuilder.contour_enabled
	var w := World.from_def(_def("hollow", 7))
	WorldMeshBuilder.contour_enabled = false   # explicit: an earlier test's Game boot leaves the switch on in the full suite
	var classic := WorldMeshBuilder.build(w)
	WorldMeshBuilder.contour_enabled = true
	var ink := WorldMeshBuilder.build(w)
	WorldMeshBuilder.contour_enabled = was
	ok(_mesh_hash(ink) != _mesh_hash(classic), "switch on + wallStyle builds the contour mesh")
	var a := ink.surface_get_arrays(0)
	ok(a[Mesh.ARRAY_TEX_UV2] != null and a[Mesh.ARRAY_TEX_UV2].size() == a[Mesh.ARRAY_VERTEX].size(), "UV2 present for every vertex")


func test_mesh_attributes() -> void:
	var w := _world("inn", 3)
	var m := WorldMeshBuilder.build_contour(w)
	var a := m.surface_get_arrays(0)
	var verts: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var cols: PackedColorArray = a[Mesh.ARRAY_COLOR]
	var uv2: PackedVector2Array = a[Mesh.ARRAY_TEX_UV2]
	eq(verts.size(), w.contour.segment_total() * 4, "4 vertices per outline segment")
	var styles := {}
	for i in verts.size():
		var g := roundi(cols[i].g * 255.0)
		styles[g >> 2] = true
		ok((g & 3) < 4, "face code in range")
		ok(cols[i].r >= 0.0 and cols[i].r <= 1.0, "COLOR.r in range")
		if i % 4 < 2:
			ok(absf(verts[i].y) < 1e-6, "bottom vertices at h = 0")
		else:
			near(verts[i].y, Coords.Z_SCALE, 1e-5, "top vertices at wall height")
		if i < 400:
			ok(Vector2(verts[i].x, verts[i].z).distance_to(uv2[i]) <= 0.25 + 1e-3, "UV2 anchor within 0.25 of the vertex")
	ok(styles.has(9) and styles.has(8), "inn: drystone (9) and timber (8) present")
	ok(styles.has(0), "inn: doors / windows keep style 0")
	for k in styles:
		ok(k == 0 or k == 6 or k == 7 or k == 8 or k == 9, "no foreign style id %d" % k) # the inn yard has milestones (6) and fences (7) since 0.21.3
	var hw := _world("hollow", 3)
	var ah := WorldMeshBuilder.build_contour(hw).surface_get_arrays(0)
	var ids := {}
	for c in ah[Mesh.ARRAY_COLOR]:
		ids[roundi(c.g * 255.0) >> 2] = true
	ok(ids.has(1), "hollow rock is style 1")


func test_stage_meshes_have_no_degenerate_triangles() -> void:
	var tris := 0
	for st in STAGES:
		for seed in range(1, 6):
			var w := _world(st, seed)
			var m := WorldMeshBuilder.build_contour(w)
			ok(m.get_surface_count() == 1, "%s %d has a surface" % [st, seed])
			var a := m.surface_get_arrays(0)
			var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
			var nrm: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
			var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
			var degenerate := 0
			var nan := 0
			for t in idx.size() / 3:
				var p0 := v[idx[t * 3]]
				var p1 := v[idx[t * 3 + 1]]
				var p2 := v[idx[t * 3 + 2]]
				if (p1 - p0).cross(p2 - p0).length() * 0.5 < 1e-6:
					degenerate += 1
			tris += idx.size() / 3
			for i in v.size():
				if is_nan(v[i].x) or is_nan(v[i].z) or absf(nrm[i].length() - 1.0) > 1e-3:
					nan += 1
			eq(degenerate, 0, "%s %d: degenerate triangles" % [st, seed])
			eq(nan, 0, "%s %d: NaN positions or non-unit normals" % [st, seed])
	ok(tris > 50000, "triangles checked (%d)" % tris)


func test_build_time_64x48() -> void:
	var worst := 0.0
	var worst_mesh := 0.0
	var parts := []
	for st in STAGES:
		var w := World.from_def(_def(st, 11))
		eq(w.width * w.height, 40 * 28 if st == "hollow" else 64 * 48, st + " is 64x48 (the Hollow 40x28)")
		var best := 1e9
		var bm := 1e9
		for r in 3:
			var w2 := World.from_def(_def(st, 11))
			var t0 := Time.get_ticks_usec()
			var f := ContourField.for_world(w2)
			var t1 := Time.get_ticks_usec()
			WorldMeshBuilder.build_contour(w2)
			var t2 := Time.get_ticks_usec()
			best = minf(best, (t1 - t0) / 1000.0)
			bm = minf(bm, (t2 - t1) / 1000.0)
			ok(f.loop_count() > 0, "loops")
		worst = maxf(worst, best)
		worst_mesh = maxf(worst_mesh, bm)
		parts.append("%s %.1f+%.1f" % [st, best, bm])
	print("contour build ms (field+mesh, best of 3): ", ", ".join(parts))
	ok(worst <= 80.0, "contour field build <= 80 ms per 64x48 map (worst %.1f ms)" % worst)
