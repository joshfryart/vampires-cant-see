extends TestCase
## S4 floors (docs/STYLE.md section 1, "Floors"): the ink worlds replace stone brick joints (hollow rubble, road and inn setts) and give water a sheen;
## classic worlds keep today's marks exactly (the floor_fx parity suite covers the byte-level draw log).

const ROWS := ["##############", "#............#", "#............#", "#...~~~~~....#", "#............#", "#............#", "##############"]


func _world(style: Variant) -> World:
	var d := {"name": "floor_ink_test", "rows": ROWS}
	if style != null:
		d["wallStyle"] = style
	return World.from_def(d)


func _proj() -> FloorFx.FloorProj:
	var p := FloorFx.FloorProj.new()
	p.player_x = 3.0
	p.player_y = 3.5
	p.ca = 1.0
	p.sa = 0.0
	p.half_w = 320.0
	p.focal = 320.0 / tan(0.6)
	p.horizon = 180.0
	p.half = 180.0
	p.up = false
	p.ow = 640.0
	p.oh = 360.0
	return p


func test_style_per_stage() -> void:
	eq(FloorFx.ink_floor_style(_world(null)), "", "classic")
	eq(FloorFx.ink_floor_style(_world({"#": "rock"})), "rubble", "hollow")
	eq(FloorFx.ink_floor_style(_world({"#": "thicket", "B": "milestone", "I": "fence", "W": "trunk"})), "setts", "road")
	eq(FloorFx.ink_floor_style(_world({"#": "drystone", "W": "timber"})), "setts", "inn")
	eq(FloorFx.ink_floor_style(_world({"#": "thicket", "W": "trunk"})), "ink", "wood")
	eq(FloorFx.ink_floor_style(null), "", "null world")
	for id in ["hollow", "road", "inn"]:
		var d: Dictionary = StageGen.generate(id, 1)
		var w := World.from_def(d)
		var want: String = {"hollow": "rubble", "road": "setts", "inn": "setts"}[id]
		eq(FloorFx.ink_floor_style(w), want, "%s generated world" % id)


func test_kind_mapping() -> void:
	for m in ["stone", "wood", "grass", "cobble", "roughStone", "brick", "water"]:
		eq(FloorFx.floor_kind_for(null, m, ""), FloorFx.floor_tex_kind(m), "classic %s" % m)
	eq(FloorFx.floor_kind_for(null, "stone", "rubble"), "rubble")
	eq(FloorFx.floor_kind_for(null, "stone", "setts"), "sett")
	eq(FloorFx.floor_kind_for(null, "cobble", "setts"), "sett")
	eq(FloorFx.floor_kind_for(null, "wood", "setts"), "plank_ink", "inn wood floors: broken boards, no long joints")
	eq(FloorFx.floor_tex_kind("wood"), "plank", "classic wood floors keep planks")
	eq(FloorFx.floor_kind_for(null, "grass", "ink"), "grass")
	eq(FloorFx.floor_kind_for(null, "stone", "ink"), "rubble", "ink worlds never draw brick joints")
	eq(FloorFx.floor_kind_for(null, "roughStone", "ink"), "rubble")
	eq(FloorFx.floor_kind_for(null, "wood", "ink"), "plank_ink", "broken boards in ink worlds")
	eq(FloorFx.floor_kind_for(null, "water", "ink"), "water")
	eq(FloorFx.floor_tex_kind("water"), "", "classic water has no marks")


func _cell_calls(kind: String) -> Array:
	var cv := RecordingCanvas.new()
	cv.begin_path()
	FloorFx.add_floor_cell(cv, _proj(), kind, 6, 3, 180.0)
	return cv.calls


func _count(calls: Array, fn: String) -> int:
	var n := 0
	for c in calls:
		if c["fn"] == fn:
			n += 1
	return n


func test_cell_marks() -> void:
	var r := _cell_calls("rubble")
	eq(_count(r, "ellipse"), 2, "rubble: two pebbles")
	eq(_count(r, "lineTo"), 1, "rubble: one scratch")
	var b := _cell_calls("brick")
	eq(_count(b, "ellipse"), 0, "brick is unchanged: no pebbles")
	var s := _cell_calls("sett")
	eq(_count(s, "closePath"), 7, "setts: 2 + 3 + 2 stones over three staggered rows")
	ok(_count(s, "lineTo") >= 7 * 3, "setts are polygons")
	var w := _cell_calls("water")
	ok(_count(w, "lineTo") >= 2 and _count(w, "lineTo") <= 3, "water: two or three dashes, got %d" % _count(w, "lineTo"))
	for c in w:
		if c["fn"] == "moveTo":
			continue
	# every dash is horizontal on the floor, so it projects to a horizontal screen line
	var ys: Array = []
	for c in w:
		if c["fn"] == "moveTo" or c["fn"] == "lineTo":
			ys.append(c["args"][1])
	for i in range(0, ys.size() - 1, 2):
		near(ys[i], ys[i + 1], 1e-6, "dash %d level" % i)


func _draw(world: World) -> RecordingCanvas:
	var sonar := Sonar.create()
	sonar.emit(world, 3.5, 3.5, 0.0, {"facing": 0.0})
	var rs := RenderState.new()
	rs.quality = 3
	rs.fx = 2
	rs.horizon = rs.oh / 2.0
	rs.zbuf.fill(1e9)
	var cv := RecordingCanvas.new()
	FloorFx.draw_floor_texture(rs, cv, world, sonar, 0.45, {"x": 3.5, "y": 3.5, "angle": 0.0}, rs.tan_half())
	return cv


func test_draw_floor_texture_ink_vs_classic() -> void:
	var classic := _draw(_world(null))
	var ink := _draw(_world({"#": "rock"}))
	var inn := _draw(_world({"#": "drystone", "W": "timber"}))
	ok(classic.calls.size() > 0, "classic draws brick marks")
	eq(_count(classic.calls, "ellipse"), 0, "classic stone floor: joints only")
	ok(_count(ink.calls, "ellipse") > 0, "hollow floor: rubble pebbles")
	ok(_count(inn.calls, "closePath") > 0, "inn yard floor: setts")
	var blue := 0
	for c in ink.calls:
		if c["stroke"] == "#7fa6ff" and c["fn"] == "lineTo":
			blue += 1
	ok(blue > 0, "water sheen drawn in the bounce blue")
	for c in classic.calls:
		ok(c["stroke"] != "#7fa6ff", "classic water has no sheen")


# ---------------------------------------------------------------- ceilings (0.21.4)

func test_ceiling_style_per_stage() -> void:
	eq(FloorFx.ceil_style(null), "")
	eq(FloorFx.ceil_style(_world(null)), "", "classic")
	var want := {"hollow": "cave", "wood": "wood", "moor": "moor", "road": "road", "inn": "inn"}
	for id in want:
		eq(FloorFx.ceil_style(World.from_def(StageGen.generate(id, 3))), want[id], "%s ceiling style" % id)
	eq(FloorFx.ceil_height(_world(null), 3.5, 3.5), 1.0, "classic ceiling is flush")
	eq(FloorFx.ceil_mesh_mul(_world(null)), 1.0, "classic ceiling mesh unchanged")
	eq(FloorFx.ceil_kind_styled(_world(null), 3.5, 3.5), "", "classic has no styled ceiling kind")


func _zone_cell(w: World, name: String) -> Vector2:
	for y in w.height:
		for x in w.width:
			if w.zone_at(x + 0.5, y + 0.5) == name and not w.is_solid(x + 0.5, y + 0.5):
				return Vector2(x + 0.5, y + 0.5)
	return Vector2(-1, -1)


func test_cave_ceiling_varies_by_chamber() -> void:
	var w := World.from_def(StageGen.generate("hollow", 7))
	var hall := _zone_cell(w, "echo_hall")
	var tight := _zone_cell(w, "squeeze")
	ok(hall.x >= 0 and tight.x >= 0, "hollow has an echo hall and a squeeze")
	ok(FloorFx.ceil_height(w, hall.x, hall.y) > FloorFx.ceil_height(w, tight.x, tight.y) + 0.2, "echo hall vault is higher than the squeeze")
	ok(FloorFx.ceil_height(w, tight.x, tight.y) <= 1.0 + 1e-9, "squeeze is flush with the wall tops")
	eq(FloorFx.ceil_kind_styled(w, hall.x, hall.y), "vault_hall")
	eq(FloorFx.ceil_kind_styled(w, tight.x, tight.y), "vault_tight")
	ok(FloorFx.ceil_mesh_mul(w) > 1.0, "ceiling plane sits above the wall tops")
	var apron := _zone_cell(w, "cave_apron")
	if apron.x >= 0:
		eq(FloorFx.ceil_kind_styled(w, apron.x, apron.y), "stars", "the apron is open sky")
	# ordinary chambers vary a little per cell but stay between the squeeze and the hall
	var seen := {}
	for y in w.height:
		for x in w.width:
			if w.zone_at(x + 0.5, y + 0.5) == "" and not w.is_solid(x + 0.5, y + 0.5):
				var hh := FloorFx.ceil_height(w, x + 0.5, y + 0.5)
				ok(hh > 1.0 and hh < 1.4, "plain cave cell height %f" % hh)
				seen[snappedf(hh, 0.001)] = true
	ok(seen.size() > 3, "per-cell variation")


func test_ceiling_kind_per_stage() -> void:
	var inn := World.from_def(StageGen.generate("inn", 3))
	var tav := _zone_cell(inn, "tavern")
	eq(FloorFx.ceil_kind_styled(inn, tav.x, tav.y), "rafter", "inn rafters")
	var wood := World.from_def(StageGen.generate("wood", 3))
	var moor := World.from_def(StageGen.generate("moor", 3))
	var road := World.from_def(StageGen.generate("road", 3))
	var found := {}
	for pair in [[wood, "canopy"], [moor, "stars"], [road, "stars"]]:
		var w: World = pair[0]
		for y in w.height:
			for x in w.width:
				if w.kind_at(x + 0.5, y + 0.5) == "outdoor" and not w.is_solid(x + 0.5, y + 0.5):
					eq(FloorFx.ceil_kind_styled(w, x + 0.5, y + 0.5), pair[1], "%s sky" % w.name)
					found[w.name] = true
					break
			if found.has(w.name):
				break
	eq(found.size(), 3, "each outdoor stage has open sky cells")


func _up_calls(kind: String, hmul: float) -> Array:
	var p := _proj()
	p.up = true
	p.hmul = hmul
	var cv := RecordingCanvas.new()
	cv.begin_path()
	FloorFx.add_floor_cell(cv, p, kind, 6, 3, 180.0)
	return cv.calls.filter(func(c): return c["fn"] == "moveTo" or c["fn"] == "lineTo")


func test_ceiling_cell_marks() -> void:
	for kind in ["vault", "vault_hall", "vault_tight", "canopy", "stars", "rafter"]:
		var n := 0
		for cx in range(2, 12):
			var p := _proj()
			p.up = true
			var cv := RecordingCanvas.new()
			cv.begin_path()
			FloorFx.add_floor_cell(cv, p, kind, cx, 3, 180.0)
			n += cv.calls.size()
			for c in cv.calls:
				if c["fn"] == "moveTo" or c["fn"] == "lineTo":
					ok(c["args"][1] < 180.0 + 40.0, "%s mark above the horizon (plus stalactite drop)" % kind)
		ok(n > 0, "%s draws something over 10 cells" % kind)
	# a higher vault projects nearer the horizon-top: same cell, smaller y
	var lo := _up_calls("rafter", 1.0)
	var hi := _up_calls("rafter", 1.4)
	ok(lo.size() > 0 and hi.size() == lo.size(), "same marks at both heights")
	if lo.size() > 0:
		ok(hi[0]["args"][1] < lo[0]["args"][1], "taller ceiling draws higher on screen")
	# FloorProj.hmul = 1 is the old formula exactly
	var p2 := _proj()
	p2.up = true
	ok(p2.pt(7.0, 3.0), "projects")
	eq(p2.py, 180.0 - 180.0 / 4.0, "hmul 1 is the classic ceiling projection")


func test_cave_ceiling_has_no_long_straight_lines() -> void:
	# no vault mark spans more than a cell: every lineTo stays within 0.5 cell of its moveTo on the ground plane (checked in screen px at 4 cells)
	for kind in ["vault", "vault_hall", "vault_tight"]:
		var last := Vector2.ZERO
		for cx in range(4, 12):
			var p := _proj()
			p.up = true
			var cv := RecordingCanvas.new()
			cv.begin_path()
			FloorFx.add_floor_cell(cv, p, kind, cx, 3, 180.0)
			for c in cv.calls:
				if c["fn"] == "moveTo":
					last = Vector2(c["args"][0], c["args"][1])
				elif c["fn"] == "lineTo":
					ok(Vector2(c["args"][0], c["args"][1]).distance_to(last) < 120.0, "%s segment stays short" % kind)
					last = Vector2(c["args"][0], c["args"][1])


func test_styled_ceiling_draw_gates() -> void:
	var ink := World.from_def({"name": "ceil_ink", "rows": ROWS, "wallStyle": {"#": "rock"}, "zones": [{"name": "echo_hall", "kind": "indoor", "x0": 1, "y0": 1, "x1": 12, "y1": 5}]})
	var classic := _world(null)
	var a := _draw(ink)
	var b := _draw(classic)
	ok(a.calls.size() > 0 and b.calls.size() > 0, "both draw")
	var ellipses_ink := _count(a.calls, "ellipse")
	ok(ellipses_ink > 0, "ink cave: rubble and drip beads")
	eq(_count(b.calls, "ellipse"), 0, "classic stone world: joints only")
	# the classic ceiling (brick joints) must be identical to a plain draw of the same classic world
	eq(_draw(classic).calls.size(), b.calls.size(), "classic draw is deterministic")
