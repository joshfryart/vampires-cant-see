extends TestCase
## People with the vessel flag on, against tests/fixtures/people_vessels.json (tools/golden/people_vessels.mjs): vheart echoes
## carry the pulse snapshot, count the beat on the next t_prev edge and live until their vessel wave has faded.


func test_runs() -> void:
	var fx: Dictionary = load_fixture("people_vessels")
	var dt: float = fx["dt"]
	People.vessels_on = true
	var run_no := 0
	for run in fx["runs"]:
		var spec: Dictionary = run["spec"]
		var def: Dictionary = GameData.map_def(spec["map"])
		var w := World.from_def(def)
		var st := People.create(w, def, {"seed": spec["seed"], "noForge": true})
		var sonar := Sonar.create()
		var beats: Array = spec["beats"]
		var done := {}
		var t := 0.0
		var next := 0.25
		var snap_i := 0
		for i in int(round(float(spec["seconds"]) / dt)):
			for bi in beats.size():
				var b: Dictionary = beats[bi]
				if float(b["t"]) <= t + 1e-9 and not done.has(bi):
					done[bi] = true
					var p: People.Person = st.people[int(b["id"])]
					p.heart_bpm = b["bpm"]
					p.heart_state_k = b["stateK"]
					p.heart_periph_k = b["periphK"]
					p.heart_head_k = b["headK"]
					sonar.emit_sound(w, p.x, p.y, t, {"kind": "vheart", "z": 0.65, "range": b["range"], "strength": b["strength"], "bounces": 0})
			st.update(w, dt, null)
			var t_prev := t
			t += dt
			st.update_echoes(sonar, t_prev, t)
			sonar.prune(t)
			if t >= next - 1e-9:
				next += 0.25
				var snap: Dictionary = run["snaps"][snap_i]
				snap_i += 1
				var lbl := "run %d t=%s" % [run_no, str(snap["t"])]
				eq(st.echoes.size(), snap["echoes"].size(), lbl + " echo count")
				for ei in mini(st.echoes.size(), snap["echoes"].size()):
					var e: People.Echo = st.echoes[ei]
					var want: Array = snap["echoes"][ei]
					var got := [e.person_id, e.kind, e.x, e.y, e.t, e.dist, e.strength, e.z_min, e.z_max, e.fade, e.bpm if e.kind == "vheart" else null, e.state_k if e.kind == "vheart" else null, e.periph_k if e.kind == "vheart" else null, e.head_k if e.kind == "vheart" else null]
					deep(got, want, "%s echo %d" % [lbl, ei], 1e-6)
		run_no += 1
	People.vessels_on = false
