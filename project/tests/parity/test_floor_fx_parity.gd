extends TestCase
## Ground and air drawing parity against tests/fixtures/floor_fx.json (tools/golden/floor_fx.mjs): the draw-call log hash of each
## FloorFx function must equal what js/render.js produced for the same scene.


func test_entries() -> void:
	var fx: Dictionary = load_fixture("floor_fx")
	var bad := 0
	var by_fn := {}
	for e in fx["entries"]:
		var spec: Dictionary = e["spec"]
		var def: Dictionary = GameData.map_def(spec["map"])
		var w := World.from_def(def)
		for d in spec.get("doors", []):
			w.set_door(int(d[0]), int(d[1]), true)
		var sonar := Sonar.create()
		for p in spec["pulses"]:
			if p["k"] == "ping":
				sonar.emit(w, float(p["x"]), float(p["y"]), float(p["t0"]), {"facing": float(p["facing"])})
			else:
				sonar.emit_sound(w, float(p["x"]), float(p["y"]), float(p["t0"]), p["opts"])
		var rs := RenderState.new()
		rs.reduced = bool(spec.get("reduced", false))
		rs.quality = int(spec["quality"]) if spec.has("quality") else 3
		rs.fx = int(spec["fx"]) if spec.has("fx") else 0
		if spec.has("matDetail") and spec["matDetail"] == false:
			rs.mat_detail = false
		rs.horizon = rs.oh / 2.0
		var t: float = float(spec["t"])
		rs.update_boil(t)
		for i in rs.cols:
			rs.zbuf[i] = float(e["zbuf"][i])
		var pl := {"x": float(spec["player"]["x"]), "y": float(spec["player"]["y"]), "angle": float(spec["player"]["angle"])}
		var cv := RecordingCanvas.new()
		var th: float = rs.tan_half()
		match e["fn"]:
			"drawRipple": FloorFx.draw_ripple(rs, cv, w, sonar, t, pl, th)
			"drawAirRings": FloorFx.draw_air_rings(rs, cv, w, sonar, t, pl, th)
			"drawFloorTexture": FloorFx.draw_floor_texture(rs, cv, w, sonar, t, pl, th)
			"drawFloorFront": FloorFx.draw_floor_front(rs, cv, w, sonar, t, pl, th)
			"drawFootRings": FloorFx.draw_foot_rings(rs, cv, sonar, t, pl, th)
			"drawRings":
				var ring := RippleFx.Rings.new()
				for g in e["extra"]["rings"]:
					ring.spawn(float(g["x"]), float(g["y"]), float(g["t0"]), g["opts"])
				FloorFx.draw_rings(rs, cv, ring.rings, t, pl, th)
		var h := cv.log_hash()
		var ok_entry: bool = h == e["hash"] and cv.calls.size() == int(e["calls"])
		if not by_fn.has(e["fn"]):
			by_fn[e["fn"]] = [0, 0]
		by_fn[e["fn"]][0] += 1
		if not ok_entry:
			by_fn[e["fn"]][1] += 1
			bad += 1
			if bad <= 8:
				var msg := "%s: calls %d/%d hash %s/%s" % [e["key"], cv.calls.size(), int(e["calls"]), h, e["hash"]]
				if e.has("log"):
					var lines := cv.lines()
					for i in mini(lines.size(), e["log"].size()):
						if lines[i] != e["log"][i]:
							msg += "\n  first diff at call %d:\n   got  %s\n   want %s" % [i, lines[i], e["log"][i]]
							break
				failures.append(msg)
		checks += 1
	if bad > 8:
		failures.append("... %d entries mismatched in total: %s" % [bad, str(by_fn)])
