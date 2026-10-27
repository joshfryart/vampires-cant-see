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
	eq(FloorFx.floor_kind_for(null, "wood", "setts"), "plank", "wood floors keep planks")
	eq(FloorFx.floor_kind_for(null, "grass", "ink"), "grass")
	eq(FloorFx.floor_kind_for(null, "stone", "ink"), "brick", "wood and moor stone floors are untouched")
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
