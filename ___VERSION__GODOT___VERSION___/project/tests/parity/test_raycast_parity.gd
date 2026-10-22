extends TestCase
## Ray-cast parity against tests/fixtures/raycast.json (tools/golden/raycast.mjs). Tolerance 1e-9
## (cos/sin/atan can differ by an ulp between V8 and the C library).

const EPS := 1e-9


func _check(h: Raycast.Hit, row: Array, fields: Array, label: String) -> void:
	var got := {
		"hit": 1 if h.hit else 0, "dist": h.dist, "rayDist": h.ray_dist, "rayAngle": h.ray_angle,
		"cellX": h.cell_x, "cellY": h.cell_y, "side": h.side, "hitX": h.hit_x, "hitY": h.hit_y,
		"wallX": h.wall_x, "nx": h.nx, "ny": h.ny,
	}
	for i in fields.size():
		var k: String = fields[i]
		near(float(got[k]), float(row[i]), EPS, "%s %s" % [label, k])


func test_single_rays_and_axis_rays() -> void:
	var fx: Dictionary = load_fixture("raycast")
	var fields: Array = fx["fields"]
	for m in fx["maps"]:
		var w := GridWorld.from_flags(int(m["w"]), int(m["h"]), m["flags"])
		for group in ["singles", "axis"]:
			var n := 0
			for r in m[group]:
				var h := Raycast.cast_one(w, float(r["x"]), float(r["y"]), float(r["ang"]), float(r["maxDist"]))
				_check(h, r["h"], fields, "%s %s #%d" % [m["name"], group, n])
				n += 1


func test_column_casts() -> void:
	var fx: Dictionary = load_fixture("raycast")
	var fields: Array = fx["fields"]
	for m in fx["maps"]:
		var w := GridWorld.from_flags(int(m["w"]), int(m["h"]), m["flags"])
		var n := 0
		for c in m["casts"]:
			var hits := Raycast.cast(w, float(c["x"]), float(c["y"]), float(c["angle"]), float(c["fov"]), int(c["columns"]), float(c["maxDist"]))
			eq(hits.size(), int(c["columns"]), "%s cast #%d columns" % [m["name"], n])
			for i in hits.size():
				_check(hits[i], c["hits"][i], fields, "%s cast #%d col %d" % [m["name"], n, i])
			n += 1
