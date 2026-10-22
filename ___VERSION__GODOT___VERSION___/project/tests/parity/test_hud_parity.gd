extends TestCase
## HUD and icon drawing parity against tests/fixtures/hud.json (tools/golden/hud.mjs): the draw-call log hash of every scene must
## equal what js/hud.js and js/icons.js produced.


func _run(e: Dictionary, cv: RecordingCanvas) -> Variant:
	var spec: Dictionary = e["spec"]
	var key: String = e["key"]
	var hud := HudDraw.new()
	if key.begins_with("hud/"):
		hud.draw_hud(cv, spec)
		return null
	if key.begins_with("card/"):
		HudDraw.draw_card(cv, spec["text"], float(spec["age"]), float(spec["t"]), bool(spec["boil"]), String(spec["sub"]) if spec["sub"] != null else "", bool(spec["large"]))
		return null
	if key.begins_with("hint/"):
		HudDraw.draw_hint(cv, spec["text"], float(spec["age"]), HudDraw.HINT_DUR, bool(spec["large"]))
		return null
	if key.begins_with("icon/"):
		return Icons.draw(cv, spec["name"], float(spec["size"]), float(spec["t"]), spec["o"])
	if key.begins_with("tomb/"):
		return Icons.draw_tombstone(cv, float(spec["w"]), float(spec["h"]), float(spec["t"]))
	if key.begins_with("crypt/"):
		return Icons.draw_crypt_menu(cv, 640.0, 360.0, float(spec["t"]))
	return null


func test_entries() -> void:
	var fx: Dictionary = load_fixture("hud")
	var bad := 0
	for e in fx["entries"]:
		var cv := RecordingCanvas.new()
		var ret: Variant = _run(e, cv)
		var h := cv.log_hash()
		var ok_e: bool = h == e["hash"] and cv.calls.size() == int(e["calls"])
		if e["ret"] != null and ret != null:
			ok_e = ok_e and ret == e["ret"]
		if not ok_e:
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
		failures.append("... %d entries mismatched in total" % bad)
