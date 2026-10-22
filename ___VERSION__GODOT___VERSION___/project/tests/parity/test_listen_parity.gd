extends TestCase
## Listening-at-windows parity against tests/fixtures/listen.json (tools/golden/listen.mjs).


func test_find_window_and_pure_helpers() -> void:
	var fx: Dictionary = load_fixture("listen")
	var def: Dictionary = GameData.map_def("town")
	var w := World.from_def(def)
	for e in fx["finds"]:
		var p: Dictionary = e["p"]
		var got: Variant = Listen.find_window(w, p, 1.2)
		var lbl := "find (%s,%s,%s)" % [str(p["x"]), str(p["y"]), str(p["angle"])]
		eq(got == null, e["win"] == null, lbl + " null-ness")
		if got != null and e["win"] != null:
			for k in ["cx", "cy"]:
				eq(got[k], int(e["win"][k]), lbl + " " + k)
			for k in ["x", "y", "ix", "iy", "dist", "lit"]:
				near(got[k], float(e["win"][k]), 1e-9, lbl + " " + k)
			eq(got["zone"], e["win"]["zone"], lbl + " zone")
		eq(Listen.near_lit_window(w, p, 2.5), e["near"], lbl + " near lit")
	for e in fx["subs"]:
		var got := Listen.subtitle_for(e["seed"], e["kind"], e["mood"], float(e["dist"]), float(e["lit"]))
		eq(got["de"], e["sub"]["de"], "listen sub de")
		eq(got["en"], e["sub"]["en"], "listen sub en")
		eq(got["muffled"], e["sub"]["muffled"], "listen sub muffled")
	for e in fx["alpha"]:
		near(Listen.sub_alpha(e["s"], float(e["now"])), float(e["a"]), 1e-12, "sub alpha")
	for e in fx["kinds"]:
		eq(Listen.conversation_kinds(e["conv"], e["mood"]), e["res"], "conversation kinds")
	for e in fx["moods"]:
		eq(Listen.mood_for(float(e["f"])), e["m"], "mood for fear %s" % str(e["f"]))


func test_session() -> void:
	var fx: Dictionary = load_fixture("listen")
	var dt: float = fx["dt"]
	var def: Dictionary = GameData.map_def("town")
	for sess in fx["sessions"]:
		var spec: Dictionary = sess["spec"]
		var w := World.from_def(def)
		var st := People.create(w, def, {"seed": spec["seed"], "shuffle": false})
		var ls := Listen.new()
		var t := 0.0
		var ops: Array = spec["ops"]
		var oi := 0
		var held := false
		var holding := false
		var speed := 0.0
		var fear := 0.0
		var player := {"x": float(spec["player"][0]), "y": float(spec["player"][1]), "angle": float(spec["player"][2])}
		var calls: Array = []
		var steps: int = int(round(float(spec["seconds"]) / dt))
		var log: Array = sess["log"]
		for i in steps:
			while oi < ops.size() and float(ops[oi]["t"]) <= t + 1e-9:
				var o: Dictionary = ops[oi]
				oi += 1
				match o["op"]:
					"held": held = bool(o["v"])
					"holding": holding = bool(o["v"])
					"speed": speed = float(o["v"])
					"fear": fear = float(o["v"])
					"player": player = {"x": float(o["x"]), "y": float(o["y"]), "angle": float(o["a"])}
			st.update(w, dt, {"nightFrac": minf(1.0, t / float(spec["seconds"])), "nightSec": float(spec["seconds"]), "fear": fear})
			t += dt
			var changes: Array = []
			var now := t
			ls.step({
				"now": t, "held": held, "holding": holding, "speed": speed, "world": w, "player": player,
				"people": Barks.people_snapshot(st.people), "fear": fear,
				"speak": func(o): calls.append({"t": now, "seed": o["seed"], "kind": o["kind"], "mood": o["mood"], "pan": o["pan"], "lpHz": o["lpHz"], "gain": o["gain"], "voice": o["voice"]}); return {"end": 0.0},
				"speak_length": func(sd, kind, mood_s, _voice): return VoiceData.line_length(VoiceData.line(sd, kind, mood_s)),
				"voice_for": func(p, _sd): return p["role"] if p["role"] != "" else "man",
				"pan": func(x, _y): return (x - player["x"]) * 0.1,
				"on_change": func(a, info): changes.append([a, info["count"] if info != null else -1]),
				"conversation_for": func(id): return st.conversation_for(id),
				"on_subtitle": func(s, who): changes.append(["sub", s["de"], s["en"], who["id"]])})
			var want: Dictionary = log[i]
			var lbl := "session t=%.1f" % t
			eq(ls.active, want["active"], lbl + " active")
			eq(ls.count, int(want["count"]), lbl + " count")
			eq(ls.silent, want["silent"], lbl + " silent")
			eq(ls.mood, want["mood"], lbl + " mood")
			eq(ls.turn, int(want["turn"]), lbl + " turn")
			eq(ls.speaker, int(want["speaker"]), lbl + " speaker")
			if want["active"]:
				near(ls.lp_hz, float(want["lpHz"]), 1e-9, lbl + " lpHz")
				near(ls.next_at, float(want["nextAt"]), 1e-9, lbl + " nextAt")
			eq(ls.win == null, want["win"] == null, lbl + " win null")
			if ls.win != null and want["win"] != null:
				eq([ls.win["cx"], ls.win["cy"]], [int(want["win"][0]), int(want["win"][1])], lbl + " win")
			eq(ls.sub == null, want["sub"] == null, lbl + " sub null")
			if ls.sub != null and want["sub"] != null:
				eq(ls.sub["de"], want["sub"][0], lbl + " sub de")
			eq(changes.size(), want["changes"].size(), lbl + " changes")
		eq(calls.size(), sess["calls"].size(), "speak calls")
		for k in mini(calls.size(), sess["calls"].size()):
			var a: Dictionary = calls[k]
			var b: Dictionary = sess["calls"][k]
			eq(a["seed"], int(b["seed"]), "call %d seed" % k)
			eq(a["kind"], b["kind"], "call %d kind" % k)
			eq(a["mood"], b["mood"], "call %d mood" % k)
			eq(a["voice"], b["voice"], "call %d voice" % k)
			near(a["gain"], float(b["gain"]), 1e-9, "call %d gain" % k)
			near(a["pan"], float(b["pan"]), 1e-9, "call %d pan" % k)
			near(a["t"], float(b["t"]), 1e-6, "call %d t" % k)
