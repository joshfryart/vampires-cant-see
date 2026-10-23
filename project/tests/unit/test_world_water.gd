extends TestCase
## Still water "~" (rays pass, movement blocked), covered pockets (indoor zones inside outdoor maps) and the roguelike prop types.

const ROWS := [
	"##########",
	"#@.......#",
	"#..~~~...#",
	"#..~~~...#",
	"#..~~~..C#",
	"#........#",
	"##########",
]


func _def(kind: String = "indoor") -> Dictionary:
	return {"name": "pool", "kind": kind, "floor": "roughStone", "rows": ROWS.duplicate()}


func test_rays_cross_water() -> void:
	var w := World.from_def(_def())
	ok(not w.cell_solid(4, 3), "water cell is not ray-solid")
	eq(w.solid_grid[3 * w.width + 4], 0, "solid_grid 0 on water")
	var h := Raycast.trace(w, 1.5, 3.5, 0.0, 20.0)
	ok(h.hit, "ray hits the east wall")
	near(h.dist, 7.5, 1e-6, "ray travels across the pool to the wall")
	ok(w.mat_grid[3 * w.width + 4] >= 0, "mat_grid valid on water")
	eq(w.material_at(4.5, 3.5), "water", "water material name")
	ok(Acoustics.mat_of("water").has("rough"), "acoustics fall back safely for water")


func test_blocks_and_line_of_sight() -> void:
	var w := World.from_def(_def())
	ok(w.has_water, "has_water flag")
	ok(w.blocks(4.5, 3.5, 0.0), "blocks on water centre")
	ok(w.blocks(4.5, 3.5, 0.2), "blocks on water with radius")
	ok(w.blocks(2.9, 3.5, 0.2), "circle clipping the pool edge blocks")
	ok(not w.blocks(1.5, 3.5, 0.2), "dry floor beside water is open")
	ok(not w.blocks(7.5, 3.5, 0.2), "dry floor beyond water is open")
	ok(not w.line_blocked(1.5, 3.5, 7.5, 3.5), "line_blocked false across water")


func test_bfs_routes_around_water() -> void:
	var w := World.from_def(_def())
	ok(not People.cell_walkable(w, 4, 3), "water cell not walkable")
	var p := People.Person.new()
	p.x = 1.5
	p.y = 3.5
	var route: Variant = People.bfs_route(w, p, func(cx: int, cy: int) -> bool: return cx == 7 and cy == 3, 40)
	ok(route != null, "route found")
	for c in route:
		ok(not w.blocks(float(c["x"]), float(c["y"]), 0.0), "waypoint dry")
	ok(route.size() > 6, "route is longer than the straight line")


func test_dry_map_unaffected() -> void:
	var w := World.from_def({"name": "dry", "kind": "indoor", "rows": ["###", "#@#", "###"]})
	ok(not w.has_water, "no water flag")
	ok(not w.blocks(1.5, 1.5, 0.2), "open cell open")


func test_covered_pocket_is_not_sunlit() -> void:
	var d := _def("outdoor")
	d["zones"] = [{"name": "burrow", "kind": "indoor", "x0": 7, "y0": 4, "x1": 8, "y1": 4}]
	var w := World.from_def(d)
	eq(w.kind_at(2.5, 1.5), "outdoor", "open ground is outdoor")
	eq(w.kind_at(7.5, 4.5), "indoor", "pocket is indoor")
	eq(w.zone_at(7.5, 4.5), "burrow", "pocket zone name")
	ok(WorldValidate.validate(d)["ok"], "outdoor map with an indoor pocket validates")
	var n := Night.new()
	n.status = "day"
	var ev := n.update(0.05, {"outdoor": w.kind_at(7.5, 4.5) == "outdoor"})
	eq(n.status, "day", "no sunburn in the pocket")
	ok(not ev.has("lost"), "no lost event")
	ev = n.update(0.05, {"outdoor": w.kind_at(2.5, 1.5) == "outdoor"})
	eq(n.status, "lost", "open ground burns")


func test_validate_water_rules() -> void:
	ok(WorldValidate.validate(_def())["ok"], "water map validates")
	var d := _def()
	d["props"] = [{"type": "boulder", "col": 4, "row": 3}]
	ok(not WorldValidate.validate(d)["ok"], "prop on water rejected")
	d = _def()
	d["rows"][0] = "####~#####"
	ok(not WorldValidate.validate(d)["ok"], "water on the border rejected")
	d = _def()
	d["paths"] = [{"points": [[1, 3], [7, 3]]}]
	ok(not WorldValidate.validate(d)["ok"], "path across water rejected")


func test_new_prop_types() -> void:
	var types := ["stalagmite", "stalactite", "coffin", "glowworm", "stump", "boulder", "haybale", "scarecrow", "shrine"]
	var props: Array = []
	for i in types.size():
		props.append({"type": types[i], "col": 1 + i % 8, "row": 5 if i < 8 else 1})
	props[8]["row"] = 1
	props[8]["col"] = 3
	var d := _def()
	d["props"] = props
	var res := WorldValidate.validate(d)
	ok(res["ok"], "all new prop types validate: " + str(res["errors"]))
	var w := World.from_def(d)
	for pr in w.props:
		var nonsolid: bool = pr["type"] == "stalactite" or pr["type"] == "glowworm"
		eq(pr["solid"], not nonsolid, pr["type"] + " solidity")
	ok(w.lights.size() == 1, "glowworm emits light")
	for t in types:
		ok(Sprites.PROP_DEF.has(t), t + " has a sprite def")
		var cv := RecordingCanvas.new()
		Sprites.prop_body(cv, t, 100.0, 200.0, 40.0, 80.0, 1.0, 0.5, "#ffffff", 2.0)
		ok(cv.calls.size() > 3, t + " draws lines")


func test_validate_all_cave_like() -> void:
	var cave := {"name": "cave", "kind": "indoor", "floor": "roughStone",
		"rows": ROWS.duplicate(),
		"props": [{"type": "stalagmite", "col": 1, "row": 5}, {"type": "stalactite", "col": 2, "row": 2}, {"type": "coffin", "col": 8, "row": 1}],
		"zones": [{"name": "pool", "kind": "indoor", "x0": 1, "y0": 1, "x1": 8, "y1": 5}]}
	var res := WorldValidate.validate_all({"startMap": "cave", "maps": {"cave": cave}})
	ok(res["ok"], "cave-like def passes validate_all: " + str(res["errors"]))


func test_leg_clear_respects_water() -> void:
	# No props in the map: only the has_water flag makes leg_clear consult blocks().
	var w := World.from_def(_def())
	eq(w.props.size(), 0, "no props")
	ok(not People.leg_clear(w, 1.5, 3.5, 7.5, 3.5), "a leg across the pool is not clear")
	ok(not People.leg_clear(w, 1.5, 3.5, 4.5, 3.5), "a leg ending in the pool is not clear")
	ok(People.leg_clear(w, 1.5, 1.5, 7.5, 1.5), "a leg along the dry north shore is clear")
	ok(People.leg_clear(w, 1.5, 5.5, 7.5, 5.5), "a leg along the dry south shore is clear")
	ok(not People.leg_clear(w, 1.5, 3.5, 1.5, 0.5), "walls still block")
	var dry := World.from_def({"name": "dry", "kind": "indoor", "floor": "stone", "rows": ["#####", "#@..#", "#####"]})
	ok(not dry.has_water, "no water")
	ok(People.leg_clear(dry, 1.5, 1.5, 3.5, 1.5), "dry map unchanged")
	var p := People.build_path(w, Vector2(1.5, 1.5), {"points": [[1, 1], [7, 1], [7, 5], [1, 5]]}, 0)
	eq(p.size(), 4, "a path around the pool keeps its four points")
	var q := People.build_path(w, Vector2(1.5, 3.5), {"points": [[1, 3], [7, 3]]}, 0)
	eq(q.size(), 1, "a path through the pool falls back to one point")
