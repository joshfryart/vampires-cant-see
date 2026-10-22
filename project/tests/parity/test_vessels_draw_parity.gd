extends TestCase
## Circulatory overlay parity against tests/fixtures/vessels_draw.json (tools/golden/vessels_draw.mjs): every scene's draw-call log
## (canonical text, FNV-1a hash) from EchoLayer.draw_person with the vessels flag on must equal what js/render.js drawPerson drew.


func test_scenes() -> void:
	Pose.use_struggle = false
	Flags.persist = false
	Flags.reset_all()
	var fx: Dictionary = load_fixture("vessels_draw")
	var worlds := {}
	var bad := 0
	for sc in fx["scenes"]:
		var inp: Dictionary = sc["in"]
		var scene: Dictionary = inp["scene"]
		var mp: String = scene["map"]
		if not worlds.has(mp):
			worlds[mp] = World.from_def(GameData.map_def(mp))
		var w: World = worlds[mp]
		var rs := RenderState.new()
		rs.reduced = scene.get("reduced", false)
		rs.quality = int(scene.get("quality", 3))
		rs.fx = int(scene.get("fx", 2))
		var pl := {"x": float(scene["player"]["x"]), "y": float(scene["player"]["y"]), "angle": float(scene["player"]["angle"])}
		rs.horizon = rs.oh / 2.0
		rs.update_boil(float(scene.get("t", 12.34)))
		Raycast.depth_columns(w, pl["x"], pl["y"], pl["angle"], rs.col_cos, rs.col_sin, 16.0, rs.zbuf, rs.tch)
		rs.lights = w.lights
		rs.world = w
		rs.fig_budget = 1e9
		var locked: bool = inp["lock"] != null
		if locked:
			rs.lock_id = int(inp["echo"].get("personId", 0))
			rs.lock_k = float(inp["lock"]["k"])
			rs.lock_age = float(inp["lock"]["age"])
			rs.lock_sp = 9.0
			rs.lock_rs = float(inp["lock"].get("rs", 0.0))
		var cv := RecordingCanvas.new()
		var p := Pose.new()
		var drawn := EchoLayer.draw_person(rs, cv, p, pl, rs.tan_half(), inp["echo"], float(inp["b"]), float(inp["age"]), false, float(inp["now"]), locked)
		var got_hash := cv.log_hash()
		var ok_scene: bool = got_hash == sc["hash"] and cv.calls.size() == int(sc["calls"]) and drawn == sc["drawn"] and rs.vessel_nodes == int(sc["nodes"])
		if not ok_scene:
			bad += 1
			if bad <= 10:
				var msg := "%s: drawn %s/%s calls %d/%d nodes %d/%d hash %s/%s" % [sc["key"], str(drawn), str(sc["drawn"]), cv.calls.size(), int(sc["calls"]), rs.vessel_nodes, int(sc["nodes"]), got_hash, sc["hash"]]
				if sc.has("log"):
					var lines := cv.lines()
					for i in mini(lines.size(), sc["log"].size()):
						if lines[i] != sc["log"][i]:
							msg += "\n  first diff at call %d:\n   got  %s\n   want %s" % [i, lines[i], sc["log"][i]]
							break
				failures.append(msg)
		checks += 1
	if bad > 10:
		failures.append("... %d scenes mismatched in total" % bad)
	Flags.persist = true
