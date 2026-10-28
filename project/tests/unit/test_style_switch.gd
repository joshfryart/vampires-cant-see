extends TestCase
## S3 (docs/STYLE.md section 6): the ink wall style is switched on. Shader-agnostic checks: generated defs carry wallStyle and cover every solid tile char,
## styled worlds take the contour mesh (and LineStyle ink) while classic maps keep the legacy mesh, the game wires the `styled` uniform per mesh,
## and the shader's per-quality const block (read as text) matches LineStyle.wall_features.

const STAGES := ["hollow", "wood", "moor", "road", "inn"]
const BUILT_CODES := [68, 71, 119]  # D G w: doors and windows keep the legacy look and need no style id
const SHADER := "res://render/shaders/sonar_wall.gdshader"


func test_generated_defs_carry_wall_style() -> void:
	for st in STAGES:
		var row: Dictionary = StageGen.stage_row(st)
		var def: Dictionary = StageGen.generate(st, 7)
		ok(def.has("wallStyle"), st + " def has wallStyle")
		eq(def["wallStyle"], row["wallStyle"], st + " def wallStyle equals the stage row")
		var w := World.from_def(def)
		ok(not w.wall_style.is_empty(), st + " world is styled")
		var missing := {}
		for y in w.height:
			for x in w.width:
				if not w.is_solid(x + 0.5, y + 0.5):
					continue
				var ch: String = w.tile_at(x + 0.5, y + 0.5)
				if BUILT_CODES.has(ch.unicode_at(0)):
					continue
				if not w.wall_style.has(ch):
					missing[ch] = true
		eq(missing.keys(), [], st + ": every solid tile char has a wall style")
		for ch in w.wall_style:
			ok(ContourField.STYLE_IDS.has(String(w.wall_style[ch])), "%s: style name %s is known" % [st, w.wall_style[ch]])


func test_mesh_path_and_ink_follow_the_style() -> void:
	var was := WorldMeshBuilder.contour_enabled
	WorldMeshBuilder.contour_enabled = true
	var styled := World.from_def(StageGen.generate("hollow", 7))
	var classic := World.from_def(GameData.map_def("crypt"))
	var m1 := WorldMeshBuilder.build(styled)
	var m2 := WorldMeshBuilder.build(classic)
	WorldMeshBuilder.contour_enabled = was
	var a1 := m1.surface_get_arrays(0)
	var a2 := m2.surface_get_arrays(0)
	ok(a1[Mesh.ARRAY_TEX_UV2] != null and a1[Mesh.ARRAY_TEX_UV2].size() == a1[Mesh.ARRAY_VERTEX].size(), "styled world: contour mesh (UV2 anchors)")
	ok(a2[Mesh.ARRAY_TEX_UV2] == null or a2[Mesh.ARRAY_TEX_UV2].is_empty(), "classic world: legacy mesh (no UV2)")
	ok(LineStyle.world_ink(styled), "LineStyle ink is on for a styled world")
	ok(not LineStyle.world_ink(classic), "LineStyle ink is off for a classic world")


func test_game_wires_styled_uniform_and_caches_per_map() -> void:
	Game.test_storage = SaveCodec.MemoryStorage.new()
	Game.manual_boot = true
	GameData.clear_generated()
	var g := Game.new()
	g.boot()
	ok(WorldMeshBuilder.contour_enabled, "booting the game switches the contour mesh on")
	g.add_world("hollow", StageGen.generate("hollow", 7))
	ok(g.debug_map("hollow"), "enter the styled map")
	ok(g.walls_inst.get_meta("styled", false), "styled map shows the contour mesh")
	near(float(g.wall_mat.get_shader_parameter("styled")), 1.0)
	var styled_mesh: Mesh = g.walls_inst.mesh
	ok(g.debug_map("town"), "enter a classic map")
	ok(not g.walls_inst.get_meta("styled", false), "classic map keeps the classic mesh")
	near(float(g.wall_mat.get_shader_parameter("styled")), 0.0)
	ok(g.debug_map("hollow"), "back to the styled map")
	ok(g.walls_inst.mesh == styled_mesh, "the styled mesh is cached, not rebuilt")
	near(float(g.wall_mat.get_shader_parameter("styled")), 1.0)
	ok(g.debug_map("town"), "leave it so it can be evicted")
	ok(g.drop_world("hollow"), "the styled world is evicted")
	ok(not g.meshes.has("hollow"), "its meshes are evicted too")
	g.free()
	GameData.clear_generated()


## The shader's const block is the single source of the per-quality switches; read it as text and compare with LineStyle.wall_features.
func test_shader_const_block_matches_line_style() -> void:
	var f := FileAccess.open(SHADER, FileAccess.READ)
	ok(f != null, "shader readable")
	if f == null:
		return
	var txt := f.get_as_text()
	var strata := _vec4(txt, "STRATA_Q")
	var halo := _vec4(txt, "HALO_Q")
	var jag := _vec4(txt, "LIP_JAG_Q")
	eq(strata.size(), 4, "STRATA_Q has four entries")
	eq(halo.size(), 4, "HALO_Q has four entries")
	eq(jag.size(), 4, "LIP_JAG_Q has four entries")
	for q in 4:
		for md in [true, false]:
			var ft: Dictionary = LineStyle.wall_features(q, md)
			var tag := "q%d md=%s" % [q, str(md)]
			eq(strata[q] > 0.5 and md, ft["strata"], tag + " strata")
			eq(strata[q] > 0.5 and md, ft["cracks"], tag + " cracks")
			eq(strata[q] > 0.5 and md, ft["material_ticks"], tag + " material ticks")
			eq(jag[q] > 0.5, ft["lip_jag"], tag + " lip jag")
			var hs := "none"
			if halo[q] > 1.5:
				hs = "full"
			elif halo[q] > 0.5:
				hs = "flash"
			eq(hs, ft["halo"], tag + " halo")


func _vec4(txt: String, name: String) -> Array:
	var rx := RegEx.new()
	rx.compile("const\\s+vec4\\s+" + name + "\\s*=\\s*vec4\\(([^)]*)\\)")
	var m := rx.search(txt)
	var out: Array = []
	if m == null:
		return out
	for p in m.get_string(1).split(","):
		out.append(float(p.strip_edges()))
	return out


## 0.21.4: the vibration stripes soften only for ink materials; the classic five evenly spaced lines stay in the shader for classic maps.
func test_vibration_gating_text() -> void:
	var f := FileAccess.open("res://render/shaders/sonar_wall.gdshader", FileAccess.READ)
	var txt := f.get_as_text()
	ok(txt.contains("if (style == 1) {\n\t\t\t\t\t\t// ink rock: the strata themselves quiver"), "rock vibration reuses the strata")
	ok(txt.contains("for (int j = 0; j < 5; j++) {\n\t\t\t\t\t\t\tfloat f = float(j) * 0.25;"), "classic five-line vibration kept for style 0")
	ok(txt.contains("for (int k = 0; k < 7; k++)"), "seven strata courses")
	# 0.21.9: ink walls shiver shorter, fainter and smaller; classic (style 0) keeps VIB_DUR and full alpha; minor strata thin out with distance
	ok(txt.contains("const float VIB_DUR = 0.9;"), "classic duration kept")
	ok(txt.contains("if (style > 0) {\n\t\t\t\t\t\tif (age_v > VIB_DUR_INK) {"), "ink-only shorter shiver")
	ok(txt.contains("if (style > 0) {\n\t\t\t\t\t\tamp *= VIB_AMP_INK;"), "ink-only smaller swing")
	eq(txt.count("a *= VIB_A_INK;"), 2, "ink-only fainter (rock and the other ink materials)")
	ok(not txt.contains("a *= 0.45;"), "the old ink alpha is gone")
	ok(txt.contains("float w = (k % 3 == 0) ? 1.0 : 0.55 * minor_k;"), "minor courses fade with distance")
	var vt := FileAccess.open("res://render/shaders/sonar_vault.gdshader", FileAccess.READ).get_as_text()
	ok(vt.contains("THIN_NEAR") and vt.contains("bdf *= (int(kb) & 1) != 0"), "the vault bedding thins with distance too")
