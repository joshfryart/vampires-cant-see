extends TestCase
## People parity against tests/fixtures/people.json (tools/golden/people.mjs): replays the same scripted runs
## (people.update + sonar clock + updateEchoes) and compares a snapshot every second.

const EPS := 1e-7


func _check_person(p: People.Person, e: Array, lbl: String) -> void:
	near(p.x, float(e[0]), EPS, lbl + " x")
	near(p.y, float(e[1]), EPS, lbl + " y")
	near(p.angle, float(e[2]), EPS, lbl + " angle")
	eq(p.idx, int(e[3]), lbl + " idx")
	eq(p.state, e[4], lbl + " state")
	near(p.idle_left, float(e[5]), EPS, lbl + " idleLeft")
	near(p.look_angle, float(e[6]), EPS, lbl + " lookAngle")
	near(p.phase, float(e[7]), EPS, lbl + " phase")
	eq(p.steps, int(e[8]), lbl + " steps")
	near(p.walked, float(e[9]), EPS, lbl + " walked")
	eq(p.mode, e[10], lbl + " mode")
	near(p.left, float(e[11]), EPS, lbl + " left")
	near(p.wary, float(e[12]), EPS, lbl + " wary")
	near(p.calm_left, float(e[13]), EPS, lbl + " calmLeft")
	near(p.mode_left, float(e[14]), EPS, lbl + " modeLeft")
	eq(p.fdir, int(e[15]), lbl + " fdir")
	eq(p.block_count, int(e[16]), lbl + " blockCount")
	eq(p.route.size() if p.route != null else -1, int(e[17]), lbl + " route len")
	eq(p.ret.size() if p.ret != null else -1, int(e[18]), lbl + " ret len")
	eq(p.ri, int(e[19]), lbl + " ri")
	eq(p.ri2, int(e[20]), lbl + " ri2")


func _check_echo(e: People.Echo, x: Array, lbl: String) -> void:
	eq(e.person_id, int(x[0]), lbl + " personId")
	eq(e.kind, x[1], lbl + " kind")
	near(e.x, float(x[2]), EPS, lbl + " x")
	near(e.y, float(x[3]), EPS, lbl + " y")
	near(e.angle, float(x[4]), EPS, lbl + " angle")
	near(e.t, float(x[5]), EPS, lbl + " t")
	near(e.dist, float(x[6]), EPS, lbl + " dist")
	near(e.strength, float(x[7]), 1e-6, lbl + " strength")
	near(e.z_min, float(x[8]), 1e-6, lbl + " zMin")
	near(e.z_max, float(x[9]), 1e-6, lbl + " zMax")
	near(e.fade, float(x[10]), EPS, lbl + " fade")
	eq(e.mode, x[11], lbl + " mode")
	near(e.theta, float(x[12]), 1e-6, lbl + " theta")
	near(e.look_angle, float(x[13]), EPS, lbl + " lookAngle")
	near(e.phase, float(x[14]), EPS, lbl + " phase")


func test_looks_match() -> void:
	var fx: Dictionary = load_fixture("people")
	for run in fx["runs"]:
		var spec: Dictionary = run["spec"]
		var def: Dictionary = GameData.map_def(spec["map"])
		var w := World.from_def(def)
		var st := People.create(w, def, {"seed": spec["seed"], "shuffle": spec["shuffle"]})
		eq(st.people.size(), run["looks"].size(), "%s seed %s people" % [spec["map"], str(spec["seed"])])
		for i in mini(st.people.size(), run["looks"].size()):
			var l: Dictionary = run["looks"][i]
			var g: Dictionary = st.people[i].look
			for k in ["acc", "body", "head", "hat", "hair", "prop"]:
				eq(g[k], l[k], "look %d %s" % [i, k])
			for k in ["beard", "coat"]:
				eq(g[k], l[k], "look %d %s" % [i, k])
			for k in ["height", "build", "stride", "nose"]:
				near(g[k], float(l[k]), 1e-12, "look %d %s" % [i, k])


func test_runs() -> void:
	var fx: Dictionary = load_fixture("people")
	var dt: float = fx["dt"]
	var run_no := 0
	for run in fx["runs"]:
		var spec: Dictionary = run["spec"]
		var lbl0 := "run %d (%s seed %s)" % [run_no, spec["map"], str(spec["seed"])]
		run_no += 1
		var def: Dictionary = GameData.map_def(spec["map"])
		var w := World.from_def(def)
		var st := People.create(w, def, {"seed": spec["seed"], "shuffle": spec["shuffle"]})
		var sonar := Sonar.create()
		var ops: Array = spec["ops"]
		var oi := 0
		var ctx: Variant = null
		var t := 0.0
		var steps: int = int(round(float(spec["seconds"]) / dt))
		var next_snap := 1
		var snap_i := 0
		for i in steps:
			while oi < ops.size() and float(ops[oi]["t"]) <= t + 1e-9:
				var o: Dictionary = ops[oi]
				oi += 1
				match o["op"]:
					"player": ctx = {"player": {"x": float(o["x"]), "y": float(o["y"])}, "playerLit": float(o["lit"])}
					"noplayer": ctx = null
					"react": st.react(float(o["x"]), float(o["y"]), "sound", ctx, float(o["dist"]) if o.has("dist") else 0.0)
					"ping": sonar.emit(w, float(o["x"]), float(o["y"]), t, {"facing": float(o["facing"])})
					"grab": eq(st.grab(int(o["id"])), o["res"], lbl0 + " grab result")
					"release": eq(st.release(int(o["id"]), float(o["x"]), float(o["y"])), o["res"], lbl0 + " release result")
					"drink": near(st.drink(int(o["id"]), float(o["amount"])), float(o["res"]), EPS, lbl0 + " drink result")
					"fed": eq(st.mark_fed(int(o["id"])), o["res"], lbl0 + " fed result")
					"target":
						var f := st.feed_target(float(o["x"]), float(o["y"]), float(o["angle"]), float(o["reach"]), float(o["arc"]))
						eq(f.id if f != null else -1, int(o["res"]), lbl0 + " target result")
			st.update(w, dt, ctx)
			var t_prev := t
			t += dt
			st.update_echoes(sonar, t_prev, t)
			sonar.prune(t)
			if t >= next_snap - 1e-9:
				next_snap += 1
				var snap: Dictionary = run["snaps"][snap_i]
				snap_i += 1
				var lbl := "%s t=%s" % [lbl0, str(snap["t"])]
				near(t, float(snap["t"]), 1e-6, lbl + " clock")
				for pi in st.people.size():
					_check_person(st.people[pi], snap["people"][pi], "%s person %d" % [lbl, pi])
				eq(st.echoes.size(), snap["echoes"].size(), lbl + " echo count")
				for ei in mini(st.echoes.size(), snap["echoes"].size()):
					_check_echo(st.echoes[ei], snap["echoes"][ei], "%s echo %d" % [lbl, ei])
				var ev: Array = st.drain_events()
				eq(ev.size(), snap["events"].size(), lbl + " event count")
				for k in mini(ev.size(), snap["events"].size()):
					var se: Array = snap["events"][k]
					eq(ev[k]["type"], se[0], lbl + " event type")
					eq(ev[k]["id"], int(se[1]), lbl + " event id")
					near(ev[k]["x"], float(se[2]), EPS, lbl + " event x")
				eq(st.step_events().size(), int(snap["steps"]), lbl + " step events")
		eq(snap_i, run["snaps"].size(), lbl0 + " snapshot count")
