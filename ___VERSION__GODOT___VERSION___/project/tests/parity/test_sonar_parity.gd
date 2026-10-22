extends TestCase
## Sonar parity against tests/fixtures/sonar.json (tools/golden/sonar.mjs).

const EPS := 1e-9
const EPS32 := 1e-6


func _digits(arr: PackedByteArray, norm: bool) -> String:
	var s := ""
	for b in arr:
		s += "x" if (norm and b == 255) else str(b)
	return s


func test_scenes() -> void:
	var fx: Dictionary = load_fixture("sonar")
	var sn := 0
	for sc in fx["scenes"]:
		var lbl := "scene %d (%s)" % [sn, sc["map"]]
		sn += 1
		var w := World.from_def(GameData.map_def(sc["map"]))
		var s := Sonar.create()
		var t0: float = sc["t0"]
		var opts := {"facing": float(sc["facing"])}
		for k in sc["opts"]:
			opts[k] = sc["opts"][k]
		eq(s.emit(w, float(sc["x"]), float(sc["y"]), t0, opts), sc["emitOk"], lbl + " emit")
		eq(s.emit(w, float(sc["x"]), float(sc["y"]), t0 + 0.5, {"facing": float(sc["facing"])}), sc["emitAgain"], lbl + " emit during cooldown")
		near(s.cooldown_left(t0 + 0.3), float(sc["cooldownLeft"]), EPS, lbl + " cooldown_left")
		var primary: Sonar.Pulse = s.last_pulse
		near(Sonar.nearest_dist(primary), float(sc["nearest"]), EPS32, lbl + " nearest")
		eq(s.pulses.size(), int(sc["pulseCount"]), lbl + " pulse count")

		for i in mini(s.pulses.size(), sc["pulses"].size()):
			var p: Sonar.Pulse = s.pulses[i]
			var e: Dictionary = sc["pulses"][i]
			var pl := "%s pulse %d" % [lbl, i]
			near(p.x, float(e["x"]), EPS, pl + " x")
			near(p.y, float(e["y"]), EPS, pl + " y")
			near(p.z, float(e["z"]), EPS, pl + " z")
			near(p.t0, float(e["t0"]), EPS, pl + " t0")
			near(p.range, float(e["range"]), EPS, pl + " range")
			near(p.fade, float(e["fade"]), EPS, pl + " fade")
			near(p.strength, float(e["strength"]), EPS, pl + " strength")
			eq(p.gen, int(e["gen"]), pl + " gen")
			eq(p.mat, e["mat"], pl + " mat")
			eq(p.vis.size(), int(e["n"]), pl + " ray count")
			var thin: Array = e["visThin"]
			for j in thin.size():
				near(p.vis[j * 5], float(thin[j]), EPS32, "%s vis[%d]" % [pl, j * 5])
			var sum := 0.0
			for d in p.vis:
				sum += d
			near(sum, float(e["visSum"]), 1e-3, pl + " vis sum")
			eq(_digits(p.vmat, false), e["vmat"], pl + " vmat")
			eq(_digits(p.vnorm, true), e["vnorm"], pl + " vnorm")
			if e["vbeamSum"] != null:
				var bs := 0.0
				for d in p.vbeam:
					bs += d
				near(bs, float(e["vbeamSum"]), 1e-3, pl + " vbeam sum")

		var pt_n := 0
		for q in sc["points"]:
			var px := float(q["x"])
			var py := float(q["y"])
			for ti in sc["times"].size():
				var t: float = t0 + float(sc["times"][ti])
				var exp: Array = q["t"][ti]
				var got := s.sample2(px, py, t)
				var pl2 := "%s pt(%s,%s) t%d" % [lbl, str(px), str(py), ti]
				near(got[0], float(exp[0]), EPS32, pl2 + " b0")
				near(got[1], float(exp[1]), EPS32, pl2 + " b1")
				near(got[2], float(exp[2]), EPS32, pl2 + " age")
				near(got[3], float(exp[3]), EPS, pl2 + " fade")
				near(s.brightness_at(px, py, t), float(exp[4]), EPS32, pl2 + " brightness")
				near(s.age_at(px, py, t), float(exp[5]), EPS32, pl2 + " ageAt")
			pt_n += 1

		for v in sc["visibleFrom"]:
			eq(Sonar.visible_from(primary, float(v["x"]), float(v["y"])), v["v"], lbl + " visible_from")
			near(Sonar.lit_at(primary, float(v["x"]), float(v["y"])), float(v["lit"]), EPS, lbl + " lit_at")
		var rd: Array = [0.1, 0.7]
		for i in rd.size():
			near(Sonar.ring_radius(primary, t0 + rd[i]), float(sc["ring"][i]), EPS, lbl + " ring")
		for b in sc["bands"]:
			var hb := Sonar.height_band(primary, t0 + float(b["dt"]), float(sc["x"]) + 1.1, float(sc["y"]) + 0.4)
			eq(not hb.is_empty(), b["hit"], lbl + " band hit")
			if b["hit"]:
				near(hb[0], float(b["o"][0]), EPS, lbl + " band lo")
				near(hb[1], float(b["o"][1]), EPS, lbl + " band hi")
		var ed: Array = [0.5, 3.0, 9.9]
		for i in ed.size():
			near(Sonar.echo_delay(ed[i]), float(sc["echoDelay"][i]), EPS, lbl + " echo_delay")
		s.prune(t0 + 20.0)
		eq(s.pulses.size(), int(sc["pruneAfter"]), lbl + " prune")
