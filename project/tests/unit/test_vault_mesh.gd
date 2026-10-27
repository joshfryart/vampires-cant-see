extends TestCase
## The ink cave's rock vault (0.21.5, render/vault_mesh.gd): builds for the cave stage with sane geometry, heights follow the zones, deterministic by map
## seed, classic worlds untouched, wall tops and vault meet, the shader's quality block matches the wall shader, the game wires the instances.

const STAGES := ["hollow", "wood", "moor", "road", "inn"]


func _zone_cell(w: World, name: String) -> Vector2:
	for y in w.height:
		for x in w.width:
			if w.zone_at(x + 0.5, y + 0.5) == name and not w.is_solid(x + 0.5, y + 0.5) and w.kind_at(x + 0.5, y + 0.5) != "outdoor":
				var ok_cell := true
				for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
					if w.is_solid(x + 0.5 + d.x, y + 0.5 + d.y):
						ok_cell = false
				if ok_cell or name == "squeeze":
					return Vector2(x + 0.5, y + 0.5)
	return Vector2(-1, -1)


## Every triangle of an ArrayMesh surface: finite, non-degenerate; returns the triangle count.
func _check_mesh(m: ArrayMesh, lbl: String) -> int:
	if m.get_surface_count() == 0:
		return 0
	var a := m.surface_get_arrays(0)
	var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
	var bad := 0
	for p in v:
		if is_nan(p.x) or is_nan(p.y) or is_nan(p.z) or is_inf(p.x) or is_inf(p.y) or is_inf(p.z):
			bad += 1
	eq(bad, 0, lbl + ": finite vertices")
	var degenerate := 0
	var oob := 0
	for t in idx.size() / 3:
		var i0 := idx[t * 3]
		var i1 := idx[t * 3 + 1]
		var i2 := idx[t * 3 + 2]
		if i0 >= v.size() or i1 >= v.size() or i2 >= v.size():
			oob += 1
			continue
		if (v[i1] - v[i0]).cross(v[i2] - v[i0]).length() < 1e-9:
			degenerate += 1
	eq(oob, 0, lbl + ": indices in range")
	eq(degenerate, 0, lbl + ": no degenerate triangles")
	return idx.size() / 3


func test_vault_builds_for_all_stages_and_only_the_cave_gets_one() -> void:
	for st in STAGES:
		var w := World.from_def(StageGen.generate(st, 7))
		eq(VaultMesh.enabled_for(w), st == "hollow", st + ": only the hollow has a mesh vault")
		if st != "hollow":
			continue
		var vm := VaultMesh.build(w)
		var tris := _check_mesh(vm.build_surface(), st + " surface")
		ok(tris > 500, "the vault has triangles (%d)" % tris)
		var stal := vm.build_stalactites()
		var st_tris := _check_mesh(stal, st + " stalactites")
		ok(st_tris > 20, "the cave has stalactites (%d)" % st_tris)
		ok(tris + st_tris < 60000, "bounded triangle count")
	# every stage builds without errors even when the builder is asked for a non-cave world (the game gates on enabled_for)
	for st in STAGES:
		var w2 := World.from_def(StageGen.generate(st, 3))
		var vm2 := VaultMesh.build(w2)
		var m2 := vm2.build_surface()
		_check_mesh(m2, st + " surface (forced)")
		_check_mesh(vm2.build_stalactites(), st + " stalactites (forced)")


func test_height_follows_the_zones_and_stays_above_the_wall_tops() -> void:
	var w := World.from_def(StageGen.generate("hollow", 7))
	var vm := VaultMesh.build(w)
	var hall := _zone_cell(w, "echo_hall")
	var tight := _zone_cell(w, "squeeze")
	ok(hall.x >= 0 and tight.x >= 0, "hollow has a hall and a squeeze")
	var hh := 0.0
	for y in w.height:
		for x in w.width:
			if w.zone_at(x + 0.5, y + 0.5) == "echo_hall" and not w.is_solid(x + 0.5, y + 0.5):
				hh = maxf(hh, vm.height_at(x + 0.5, y + 0.5))
	var ht := vm.height_at(tight.x, tight.y)
	ok(hh > ht + 0.15, "echo hall vault (%.3f) above the squeeze (%.3f)" % [hh, ht])
	ok(ht <= 1.03, "squeeze is flush with the wall tops (%.3f)" % ht)
	ok(hh <= 1.5 and hh >= 1.25, "hall height near 1.4 (%.3f)" % hh)
	var lo := 10.0
	var hi := 0.0
	for k in vm.h.size():
		if vm.sd[k] >= -0.5:
			lo = minf(lo, vm.h[k])
			hi = maxf(hi, vm.h[k])
	ok(lo >= 1.0 - 1e-6, "the vault never drops under the wall tops (%.4f)" % lo)
	ok(hi < 1.6, "bounded (%.3f)" % hi)


func test_deterministic_by_map_seed() -> void:
	var d1 := StageGen.generate("hollow", 7)
	var a := VaultMesh.build(World.from_def(d1))
	var b := VaultMesh.build(World.from_def(StageGen.generate("hollow", 7)))
	eq(a.h, b.h, "same seed, same heights")
	eq(a.build_stalactites().surface_get_arrays(0)[Mesh.ARRAY_VERTEX], b.build_stalactites().surface_get_arrays(0)[Mesh.ARRAY_VERTEX], "same stalactites")
	var w3 := World.from_def(StageGen.generate("hollow", 7))
	w3.map_seed += 13
	var c := VaultMesh.build(w3)
	ok(c.h != a.h, "another map seed changes the noise")


func test_seam_with_the_wall_tops() -> void:
	# at every wall-outline vertex the vault is within epsilon of the wall top (1.0); walls are the contour mesh
	var w := World.from_def(StageGen.generate("hollow", 7))
	var vm := VaultMesh.build(w)
	var cf := ContourField.for_world(w)
	var worst := 0.0
	var n := 0
	for L: ContourField.Loop in cf.loops:
		for p in L.pos:
			if w.kind_at(p.x, p.y) == "outdoor":
				continue
			worst = maxf(worst, vm.height_at(p.x, p.y) - 1.0)
			n += 1
	ok(n > 200, "outline vertices checked (%d)" % n)
	ok(worst < 0.02, "vault meets the wall tops, worst gap %.4f wall heights" % worst)
	# the mesh covers the rock beside the walls so the lip jag never shows a hole
	var near := 0
	for L: ContourField.Loop in cf.loops:
		for p in L.pos:
			if w.kind_at(p.x, p.y) != "outdoor" and vm.dist_at(p.x, p.y) > -VaultMesh.BAND:
				near += 1
	ok(near > 200, "the outline lies inside the covered band")


func test_game_wiring_and_classic_untouched() -> void:
	Game.test_storage = SaveCodec.MemoryStorage.new()
	Game.manual_boot = true
	GameData.clear_generated()
	var g := Game.new()
	g.boot()
	g.add_world("hollow", StageGen.generate("hollow", 7))
	ok(g.debug_map("hollow"), "enter the hollow")
	eq(g.meshes["hollow"].size(), 5, "walls, floor, ring pass, vault surface, stalactites")
	ok(g.world.has_meta("vault_mesh"), "the world is tagged so the canvas ceiling skips its vault marks")
	ok(g.debug_map("town"), "enter a classic map")
	eq(g.meshes["town"].size(), 3, "classic map: walls, floor, flat ceiling")
	ok(not g.world.has_meta("vault_mesh"), "classic world not tagged")
	var cm: ArrayMesh = g.meshes["town"][2].mesh
	eq(cm.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size(), 4, "classic ceiling is the plane")
	ok(g.debug_map("town"), "leave")
	ok(g.drop_world("hollow"), "evict")
	eq(g.meshes.has("hollow"), false)
	g.free()
	GameData.clear_generated()


func test_shader_quality_block_matches_the_wall_shader() -> void:
	var consts := {}
	for path in ["res://render/shaders/sonar_wall.gdshader", "res://render/shaders/sonar_vault.gdshader"]:
		var f := FileAccess.open(path, FileAccess.READ)
		ok(f != null, path + " readable")
		if f == null:
			return
		for line in f.get_as_text().split("\n"):
			if line.begins_with("const vec4 STRATA_Q"):
				consts[path] = line.get_slice("=", 1).get_slice("//", 0).strip_edges()
	eq(consts["res://render/shaders/sonar_vault.gdshader"], consts["res://render/shaders/sonar_wall.gdshader"], "vault uses the same STRATA_Q")
