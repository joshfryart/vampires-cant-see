extends TestCase
## Struggle pose parity against tests/fixtures/struggle.json (tools/golden/struggle.mjs).


func test_poses() -> void:
	var fx: Dictionary = load_fixture("struggle")
	var sc: Array = fx["sc"]
	var pr: Array = fx["pr"]
	var out := Struggle.create()
	var n := 0
	for c in fx["cases"]:
		var o: Dictionary = c["o"]
		Struggle.pose(out, o)
		var want: Array = c["p"]
		var lbl := "pose %d pid=%s bl=%s g=%s sp=%s rs=%s anim=%s" % [n, str(o["pid"]), str(o["bl"]), str(o["g"]), str(o["sp"]), str(o["rs"]), str(o["anim"])]
		n += 1
		var i := 0
		for k in sc:
			near(out[k], float(want[i]), 1e-8, "%s %s" % [lbl, k])
			i += 1
		for k in pr:
			near(out[k][0], float(want[i]), 1e-8, "%s %s0" % [lbl, k])
			near(out[k][1], float(want[i + 1]), 1e-8, "%s %s1" % [lbl, k])
			i += 2
