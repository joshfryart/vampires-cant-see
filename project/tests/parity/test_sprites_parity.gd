extends TestCase
## Marker sprites and props parity against tests/fixtures/sprites.json (tools/golden/sprites.mjs): the draw-call log hash of
## Sprites.draw_markers + draw_props must equal what js/render.js drawSprite and drawProps produced.


func test_scenes() -> void:
	var fx: Dictionary = load_fixture("sprites")
	var bad := 0
	for sc in fx["scenes"]:
		var spec: Dictionary = sc["spec"]
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
		rs.horizon = rs.oh / 2.0
		rs.update_boil(float(spec["t"]))
		for i in rs.cols:
			rs.zbuf[i] = float(sc["zbuf"][i])
		var pl := {"x": float(spec["player"]["x"]), "y": float(spec["player"]["y"]), "angle": float(spec["player"]["angle"])}
		var cv := RecordingCanvas.new()
		var th: float = rs.tan_half()
		var drawn := Sprites.draw_markers(rs, cv, w, pl, sonar, float(spec["t"]), th)
		var n_sprite: int = cv.calls.size()
		drawn += Sprites.draw_props(rs, cv, w, pl, sonar, float(spec["t"]), th)
		var h := cv.log_hash()
		var ok_scene: bool = h == sc["hash"] and cv.calls.size() == int(sc["calls"]) and n_sprite == int(sc["spriteCalls"]) and drawn == int(sc["drawn"])
		if not ok_scene:
			bad += 1
			if bad <= 10:
				var msg := "%s: drawn %d/%d calls %d/%d sprite calls %d/%d hash %s/%s" % [sc["key"], drawn, int(sc["drawn"]), cv.calls.size(), int(sc["calls"]), n_sprite, int(sc["spriteCalls"]), h, sc["hash"]]
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
