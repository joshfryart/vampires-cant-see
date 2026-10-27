extends TestCase
## S2 (docs/STYLE.md): LineStyle helper values in both modes, taper geometry, and that adopting it leaves classic output untouched.


func _rs(ink: bool) -> RenderState:
	var rs := RenderState.new()
	rs.world = World.from_def({"name": "t", "kind": "indoor", "floor": "roughStone", "rows": ["#####", "#@..#", "#####"]})
	if ink:
		rs.world.set("wall_style", {"#": "rock"})
	return rs


func _strokes(c: RecordingCanvas) -> Array:
	var out: Array = []
	for e in c.calls:
		if e["fn"] == "stroke":
			out.append(e["lw"])
	return out


func test_ink_for() -> void:
	ok(not LineStyle.ink_for(_rs(false)), "classic world is not ink")
	ok(not LineStyle.ink_for(RenderState.new()), "no world is not ink")
	ok(not LineStyle.world_ink(null), "null")
	var o := RefCounted.new()
	ok(not LineStyle.world_ink(o), "object without wall_style")
	# a stand-in world carrying a wall_style property
	var holder := _Holder.new()
	ok(not LineStyle.world_ink(holder), "empty wall_style")
	holder.wall_style = {"#": "rock"}
	ok(LineStyle.world_ink(holder), "non-empty wall_style is ink")


class _Holder:
	extends RefCounted
	var wall_style: Dictionary = {}


func test_width_table_classic() -> void:
	near(LineStyle.contour_width(1.0, false), 1.5)
	near(LineStyle.contour_width(1.49, false), 1.5)
	near(LineStyle.contour_width(1.5, false), 1.0)
	near(LineStyle.contour_width(3.0, false, 2.0), 2.0)
	near(LineStyle.detail_width(false), 0.7)
	near(LineStyle.detail_width(false, 2.0, 1.5), 3.0)
	near(LineStyle.figure_width(0.5, true, false, 2.0), 3.2)
	near(LineStyle.figure_width(0.5, false, false), 1.5)
	near(LineStyle.limb_mul(false), 1.7)
	near(LineStyle.boil_amp(false, 2.0), 1.4)
	near(LineStyle.thin_width(1.0, false), 0.7)
	near(LineStyle.hud_width("primary", false, 1.3), 1.3)
	near(LineStyle.hud_width("emphasis", false, 2.4), 2.4)
	for b in [0.05, 0.3, 0.8, 1.0]:
		for d in [0.5, 2.0, 7.0]:
			eq(LineStyle.ping_lit(b, d, false), Sprites.line_alpha(b, d), "classic ping_lit is line_alpha")


func test_width_table_ink() -> void:
	near(LineStyle.contour_width(0.5, true), 1.75)
	near(LineStyle.contour_width(1.0, true), 1.75)
	near(LineStyle.contour_width(1.75, true), 1.25 + 0.5 * 0.5, 1e-9)
	near(LineStyle.contour_width(2.5, true), 1.25)
	near(LineStyle.contour_width(9.0, true), 1.25)
	near(LineStyle.contour_width(1.75, true, 2.0), 2.0 * 1.5)
	near(LineStyle.detail_width(true), 0.8)
	near(LineStyle.figure_width(0.5, true, true), 2.0)
	near(LineStyle.figure_width(9.0, false, true), 1.25)
	near(LineStyle.limb_mul(true), 1.6)
	near(LineStyle.boil_amp(true), 0.5)
	near(LineStyle.thin_width(2.0, true), 0.7)
	near(LineStyle.flash_width(1.0, 0.5, 2.0), 1.5)
	near(LineStyle.hud_width("frame", true, 7.0), 0.8)
	near(LineStyle.hud_width("primary", true), 1.25)
	near(LineStyle.hud_width("detail", true), 1.0)
	near(LineStyle.hud_width("emphasis", true), 2.0)
	var b := 0.5
	near(LineStyle.ping_lit(b, 3.0, true), minf(1.0, maxf(1.15 * pow(b, 0.65), 0.2 + 0.6 * b)) / 1.3, 1e-12)
	near(LineStyle.ping_lit(0.0, 0.0, true), 0.2, 1e-12)


func test_wall_features() -> void:
	var f3: Dictionary = LineStyle.wall_features(3, true)
	ok(f3["strata"] and f3["cracks"] and f3["material_ticks"], "q3 with mat_detail has strata")
	ok(not LineStyle.wall_features(3, false)["strata"], "mat_detail off drops strata")
	ok(not LineStyle.wall_features(2, true)["strata"], "q2 no strata")
	eq(LineStyle.wall_features(3, true)["halo"], "full")
	eq(LineStyle.wall_features(2, true)["halo"], "flash")
	eq(LineStyle.wall_features(1, true)["halo"], "none")
	eq(LineStyle.wall_features(1, true)["width"], 1.25)
	eq(LineStyle.wall_features(0, true)["width"], 1.0)
	eq(LineStyle.wall_features(3, true)["arcs"], 4)
	eq(LineStyle.wall_features(2, true)["arcs"], 2)
	ok(not LineStyle.wall_features(1, true)["vibration"], "q1 vibration off")


func test_taper_geometry() -> void:
	var c := RecordingCanvas.new()
	var pts := PackedVector2Array([Vector2(0, 0), Vector2(50, 0), Vector2(100, 0)])
	LineStyle.taper(c, pts, 2.0, true)
	var lws := _strokes(c)
	eq(lws.size(), 3, "open 100 px polyline: 3 strokes")
	near(lws[0], 1.2, 1e-9)
	near(lws[1], 2.0, 1e-9)
	near(lws[2], 1.2, 1e-9)
	# the pieces tile the polyline: first ends at 14, last starts at 86
	var move_x: Array = []
	var line_x: Array = []
	for e in c.calls:
		if e["fn"] == "moveTo":
			move_x.append(e["args"][0])
		elif e["fn"] == "lineTo":
			line_x.append(e["args"][0])
	near(move_x[0], 0.0, 1e-9)
	near(move_x[1], 14.0, 1e-9)
	near(move_x[2], 86.0, 1e-9)
	near(line_x[0], 14.0, 1e-9)
	near(line_x[line_x.size() - 1], 100.0, 1e-9)
	# the middle piece keeps the interior vertex
	ok(line_x.has(50.0), "interior vertex kept")
	# short, closed and classic strokes are one stroke
	var c2 := RecordingCanvas.new()
	LineStyle.taper(c2, PackedVector2Array([Vector2(0, 0), Vector2(9.9, 0)]), 2.0, true)
	eq(_strokes(c2).size(), 1, "shorter than 10 px: 1 stroke")
	var c3 := RecordingCanvas.new()
	LineStyle.taper(c3, PackedVector2Array([Vector2(0, 0), Vector2(20, 0), Vector2(20, 20), Vector2(0, 0)]), 2.0, true)
	eq(_strokes(c3).size(), 1, "closed: 1 stroke")
	var c4 := RecordingCanvas.new()
	LineStyle.taper(c4, pts, 2.0, false)
	eq(_strokes(c4).size(), 1, "classic: 1 stroke")
	near(_strokes(c4)[0], 2.0)


func test_fill_silhouette() -> void:
	var c := RecordingCanvas.new()
	LineStyle.fill_silhouette(c, false)
	eq(c.calls.size(), 0, "classic fill is a no-op")
	c.global_alpha = 0.4
	LineStyle.fill_silhouette(c, true)
	eq(c.calls.size(), 1, "ink fill emits one fill")
	eq(c.calls[0]["fn"], "fill")
	near(c.global_alpha, 0.4, 1e-12, "alpha restored")
	eq(c.fill_style, "#040306")


func test_critter_glyph_classic_unchanged_and_ink_differs() -> void:
	var a := RecordingCanvas.new()
	var b := RecordingCanvas.new()
	CritterDraw.glyph(a, "rat", "rat", 100.0, 200.0, 40.0, 60.0, 1.0, 1.0, 0.0, 0.0, false, false, "#fff")
	CritterDraw.glyph(b, "rat", "rat", 100.0, 200.0, 40.0, 60.0, 1.0, 1.0, 0.0, 0.0, false, false, "#fff", false)
	eq(a.log_hash(), b.log_hash(), "ink=false default is classic")
	var i := RecordingCanvas.new()
	CritterDraw.glyph(i, "rat", "rat", 100.0, 200.0, 40.0, 60.0, 1.0, 1.0, 0.0, 0.0, false, false, "#fff", true)
	ok(i.log_hash() != a.log_hash(), "ink rat differs (fill + tapered tail)")
	var fills := 0
	for e in i.calls:
		if e["fn"] == "fill":
			fills += 1
	ok(fills >= 1, "ink rat body is filled")
	var h := RecordingCanvas.new()
	CritterDraw.glyph(h, "hare", "hare", 100.0, 200.0, 40.0, 60.0, 1.0, 1.0, 0.0, 0.0, false, false, "#fff", true)
	ok(_strokes(h).size() > 3, "ink hare has tapered ear strokes")


func test_hud_widths_follow_ink() -> void:
	var hud := HudDraw.new()
	var c := RecordingCanvas.new()
	hud.draw_vial(c, 0.5, 0.0, 0.0, false, 0.0)
	var classic: Array = _strokes(c)
	hud.ink = true
	var c2 := RecordingCanvas.new()
	hud.draw_vial(c2, 0.5, 0.0, 0.0, false, 0.0)
	var inked: Array = _strokes(c2)
	eq(classic.size(), inked.size(), "same stroke count")
	ok(classic != inked, "ink changes the vial widths")
	for w in inked:
		ok(w in [0.8, 1.0, 1.25, 2.0], "ink vial width %s is a role width" % w)
	hud.ink = false
	var c3 := RecordingCanvas.new()
	hud.draw_vial(c3, 0.5, 0.0, 0.0, false, 0.0)
	eq(c3.log_hash(), c.log_hash(), "back to classic is identical")
