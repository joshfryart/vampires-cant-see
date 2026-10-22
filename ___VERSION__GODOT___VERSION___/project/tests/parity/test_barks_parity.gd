extends TestCase
## Voice data and bark parity against tests/fixtures/barks.json (tools/golden/barks.mjs): syllable lines, subtitles,
## per-person voices, and Barks.step driven by a replay of the people simulation.


func _j(v: Variant) -> String:
	return JsJson.stringify(v)


func test_lines() -> void:
	var fx: Dictionary = load_fixture("barks")
	for e in fx["lines"]:
		var got := VoiceData.line(e["seed"], e["kind"], e["mood"], e["weak"])
		var lbl := "line %s/%s/%s/%s" % [str(e["seed"]), e["kind"], str(e["mood"]), str(e["weak"])]
		eq(got.size(), e["line"].size(), lbl + " len")
		for i in mini(got.size(), e["line"].size()):
			var a: Dictionary = got[i]
			var b: Dictionary = e["line"][i]
			eq(a["vowel"], b["vowel"], lbl + " vowel")
			eq(a["consonant"], b["consonant"], lbl + " cons")
			near(a["dur"], float(b["dur"]), 1e-12, lbl + " dur")
			near(a["pitchMul"], float(b["pitchMul"]), 1e-12, lbl + " pitch")
			near(a["gap"], float(b["gap"]), 1e-12, lbl + " gap")
		near(VoiceData.line_length(got), float(e["len"]), 1e-12, lbl + " length")


func test_subtitles_voices_groups() -> void:
	var fx: Dictionary = load_fixture("barks")
	for e in fx["subs"]:
		var got := VoiceData.subtitle(e["seed"], e["kind"], e["mood"], e["role"], e["weak"] if e.has("weak") else null)
		var lbl := "sub %s/%s/%s/%s" % [str(e["seed"]), e["kind"], str(e["mood"]), str(e["role"])]
		eq(got["de"], e["sub"]["de"], lbl + " de")
		eq(got["en"], e["sub"]["en"], lbl + " en")
	for e in fx["voices"]:
		var got := VoiceData.for_person(e["seed"], e["role"])
		var lbl := "voice %s/%s" % [str(e["seed"]), str(e["role"])]
		eq(VoiceData.preset_for(e["role"]), e["preset"], lbl + " preset")
		for k in ["pitch", "speed", "wobble", "breath", "formantMul"]:
			near(got[k], float(e["voice"][k]), 1e-12, "%s %s" % [lbl, k])
		eq(got["name"], e["voice"]["name"], lbl + " name")
	for e in fx["groups"]:
		eq(VoiceData.group_of(e["r"]), e["g"], "group of '%s'" % e["r"])


func test_bark_runs() -> void:
	var fx: Dictionary = load_fixture("barks")
	var dt: float = fx["dt"]
	var run_no := 0
	for run in fx["runs"]:
		var spec: Dictionary = run["spec"]
		var lbl0 := "bark run %d" % run_no
		run_no += 1
		var def: Dictionary = GameData.map_def(spec["map"])
		var w := World.from_def(def)
		var st := People.create(w, def, {"seed": spec["seed"], "shuffle": false})
		var barks := Barks.new(spec["barkSeed"])
		var pl := {"x": float(spec["player"][0]), "y": float(spec["player"][1])}
		var plctx := {"player": pl, "playerLit": 0.0}
		var fear := 0.0
		var restrained: Variant = null
		var enabled := true
		var ops: Array = spec["ops"]
		var oi := 0
		var t := 0.0
		var li := 0
		var log: Array = run["log"]
		var steps: int = int(round(float(spec["seconds"]) / dt))
		for i in steps:
			while oi < ops.size() and float(ops[oi]["t"]) <= t + 1e-9:
				var o: Dictionary = ops[oi]
				oi += 1
				match o["op"]:
					"player":
						pl = {"x": float(o["x"]), "y": float(o["y"])}
						plctx = {"player": pl, "playerLit": float(o["lit"]) if o.has("lit") else 0.0}
					"fear": fear = float(o["v"])
					"react": st.react(float(o["x"]), float(o["y"]), "sound", plctx, float(o["dist"]) if o.has("dist") else 0.0)
					"grab": st.grab(int(o["id"]))
					"drink": st.drink(int(o["id"]), float(o["amount"]))
					"fed": st.mark_fed(int(o["id"]))
					"release": st.release(int(o["id"]), float(o["x"]), float(o["y"]))
					"restrain": restrained = int(o["id"])
					"unrestrain": restrained = null
					"enable": enabled = bool(o["v"])
			var ctx := {"nightFrac": minf(1.0, t / float(spec["seconds"])), "nightSec": float(spec["seconds"]), "fear": fear}
			ctx.merge(plctx)
			st.update(w, dt, ctx)
			t += dt
			var res := barks.step({
				"now": t, "player": pl, "people": Barks.people_snapshot(st.people), "fear": fear, "enabled": enabled,
				"restrained": restrained,
				"length_fn": func(sd, kind, mood, _role, weak): return VoiceData.line_length(VoiceData.line(sd, kind, mood, weak))})
			if res["barks"].size() > 0 or res["stop"].size() > 0:
				var lbl := "%s t=%.2f" % [lbl0, t]
				if li >= log.size():
					failures.append(lbl + ": unexpected extra bark event")
					checks += 1
					continue
				var want: Dictionary = log[li]
				li += 1
				near(t, float(want["t"]), 1e-6, lbl + " clock")
				eq(res["barks"].size(), want["barks"].size(), lbl + " bark count")
				for k in mini(res["barks"].size(), want["barks"].size()):
					var a: Dictionary = res["barks"][k]
					var b: Dictionary = want["barks"][k]
					eq(a["id"], int(b["id"]), lbl + " id")
					eq(a["kind"], b["kind"], lbl + " kind")
					eq(a["seed"], int(b["seed"]), lbl + " seed")
					eq(a["tone"], b["tone"], lbl + " tone")
					eq(a["mood"], b["mood"], lbl + " mood")
					eq(a["role"], b["role"], lbl + " role")
					eq(a["loud"], b["loud"], lbl + " loud")
					eq(a["restrained"], b["restrained"], lbl + " restrained")
					near(a["gain"], float(b["gain"]), 1e-12, lbl + " gain")
					near(a["len"], float(b["len"]), 1e-12, lbl + " len")
					near(a["weak"], float(b["weak"]), 1e-9, lbl + " weak")
					near(a["dist"], float(b["dist"]), 1e-6, lbl + " dist")
					var sub := Barks.subtitle_for(a)
					eq(sub["de"], want["sub"][k]["de"], lbl + " subtitle")
				eq(res["stop"].size(), want["stop"].size(), lbl + " stop count")
		eq(li, log.size(), lbl0 + " bark event count")
		eq(barks.total, int(run["total"]), lbl0 + " total")
