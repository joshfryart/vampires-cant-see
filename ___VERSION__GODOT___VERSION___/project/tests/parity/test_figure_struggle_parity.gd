extends TestCase
## Line-figure parity against tests/fixtures/figure_struggle.json (tools/golden/figure_struggle.mjs), with core/struggle.gd driving held victims: every scene's draw-call log
## (canonical text, FNV-1a hash) from EchoLayer.draw_solo must equal what js/render.js drawSolo produced at effects 0.


func test_scenes() -> void:
	Pose.use_struggle = true
	var fx: Dictionary = load_fixture("figure_struggle")
	var bad := 0
	for sc in fx["scenes"]:
		var inp: Dictionary = sc["in"]
		var rs := RenderState.new()
		rs.reduced = inp["reduced"]
		var cv := RecordingCanvas.new()
		var e: Dictionary = (inp["echo"] as Dictionary).duplicate()
		var o := {"quality": inp["quality"], "t": inp["t"], "age": inp["age"], "b": inp["b"], "player": {"x": float(inp["player"]["x"]), "y": float(inp["player"]["y"]), "angle": float(inp["player"]["angle"])}}
		if inp["lock"] != null:
			o["lock"] = inp["lock"]
		var drawn := EchoLayer.draw_solo(rs, cv, e, o)
		var got_hash := cv.log_hash()
		var ok_scene: bool = got_hash == sc["hash"] and cv.calls.size() == int(sc["calls"]) and drawn == sc["drawn"]
		if not ok_scene:
			bad += 1
			if bad <= 12:
				var msg := "%s: drawn %s/%s calls %d/%d hash %s/%s" % [sc["key"], str(drawn), str(sc["drawn"]), cv.calls.size(), int(sc["calls"]), got_hash, sc["hash"]]
				if sc.has("log"):
					var lines := cv.lines()
					for i in mini(lines.size(), sc["log"].size()):
						if lines[i] != sc["log"][i]:
							msg += "\n  first diff at call %d:\n   got  %s\n   want %s" % [i, lines[i], sc["log"][i]]
							break
				failures.append(msg)
		checks += 1
	if bad > 12:
		failures.append("... %d scenes mismatched in total" % bad)
