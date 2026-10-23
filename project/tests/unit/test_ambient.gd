extends TestCase
## Ambient emitters (core/ambient.gd) and Sonar.protect_last.


func _world() -> World:
	return World.from_def(GameData.map_def("test"))


func _open_spot(w: World) -> Vector2:
	for y in range(2, w.height - 2):
		for x in range(2, w.width - 2):
			if w.solid_grid[y * w.width + x] == 0:
				return Vector2(x + 0.5, y + 0.5)
	return Vector2(2.5, 2.5)


func _amb(kind: String, n: int, at: Vector2, opts: Dictionary = {}) -> Ambient:
	var a := Ambient.new([], opts)
	for i in n:
		a.add({"cell": [int(at.x), int(at.y)], "kind": kind})
	return a


func test_data_and_drip_params() -> void:
	var k: Dictionary = Ambient.load_kinds()
	for name in ["drip", "ripple", "draft", "wind", "cricket", "owl", "creek", "fountain", "hearth"]:
		ok(k.has(name), "kind " + name)
	var d: Dictionary = k["drip"]
	eq(d["range"], 2.5)
	eq(d["strength"], 0.35)
	eq(int(d["visRays"]), 180)
	eq(int(d["bounces"]), 0)
	var w := _world()
	var pos := _open_spot(w)
	var s := Sonar.create()
	var a := _amb("drip", 1, pos)
	var rng := Rng.new(5)
	for i in 400:
		a.step(w, s, pos, 0.05, rng)
	ok(s.pulses.size() > 0, "drip emitted")
	var p: Sonar.Pulse = s.pulses[0]
	eq(p.kind, "drip")
	near(p.range, 2.5)
	near(p.fade, 1.2)
	eq(p.vis.size(), 180)
	# Drip Ear multiplier.
	var s2 := Sonar.create()
	var a2 := _amb("drip", 1, pos, {"drip_ear": 1.5})
	var rng2 := Rng.new(5)
	for i in 400:
		a2.step(w, s2, pos, 0.05, rng2)
	near(s2.pulses[0].range, 3.75)


func test_period_scheduling() -> void:
	var w := _world()
	var pos := _open_spot(w)
	var kinds := {"tick": {"range": 1.0, "strength": 0.2, "z": 0.0, "fade": 0.1, "visRays": 16, "bounces": 0, "period": [2.0, 2.0], "jitter": 0.0, "within": 12}}
	var a := _amb("tick", 1, pos, {"kinds": kinds})
	var s := Sonar.create()
	var rng := Rng.new(1)
	var times: Array = []
	for i in 600:
		if a.step(w, s, pos, 0.1, rng) > 0:
			times.append(a.clock)
	ok(times.size() >= 28 and times.size() <= 31, "about 30 emits in 60 s, got %d" % times.size())
	for i in range(1, times.size()):
		near(times[i] - times[i - 1], 2.0, 0.11, "period")
	# Draft: about every 4 s.
	var d := _amb("draft", 1, pos)
	var s2 := Sonar.create()
	var rng2 := Rng.new(2)
	var n := 0
	for i in 1200:
		n += d.step(w, s2, pos, 0.1, rng2)
	ok(n >= 25 and n <= 33, "draft about every 4 s over 120 s, got %d" % n)


func test_gating_within_12_cells() -> void:
	var w := _world()
	var pos := _open_spot(w)
	var a := _amb("drip", 3, pos)
	var s := Sonar.create()
	var rng := Rng.new(3)
	var far := pos + Vector2(12.5, 0.0)
	for i in 600:
		a.step(w, s, far, 0.1, rng)
	eq(a.emitted, 0, "silent beyond 12 cells")
	var near_p := pos + Vector2(11.9, 0.0)
	for i in 600:
		a.step(w, s, near_p, 0.1, rng)
	ok(a.emitted > 0, "audible within 12 cells")


func test_budget_caps() -> void:
	var w := _world()
	var pos := _open_spot(w)
	var a := _amb("drip", 16, pos)
	var s := Sonar.create()
	var rng := Rng.new(4)
	var max_live := 0
	for i in 1200:
		var before: int = a.emitted
		a.step(w, s, pos, 0.05, rng)
		ok(a.emitted - before <= 1, "at most one 180-ray cast per step")
		max_live = maxi(max_live, a.live_count(s))
	ok(max_live <= Ambient.MAX_LIVE, "live cap, got %d" % max_live)
	ok(max_live >= 1, "some emitted")


func test_determinism() -> void:
	var w := _world()
	var pos := _open_spot(w)
	var runs: Array = []
	for r in 2:
		var a := Ambient.new([])
		for i in 8:
			a.add({"cell": [int(pos.x), int(pos.y)], "kind": ["drip", "ripple", "wind", "cricket"][i % 4]})
		var s := Sonar.create()
		var rng := Rng.new(99)
		var log: Array = []
		for i in 800:
			if a.step(w, s, pos, 0.05, rng) > 0:
				log.append([i, s.pulses.back().kind])
		runs.append(log)
	eq(runs[0], runs[1], "same seed same schedule")
	ok(runs[0].size() > 0)


func test_soak_protects_player_ping() -> void:
	var w := _world()
	var pos := _open_spot(w)
	var a := _amb("drip", 16, pos)
	var s := Sonar.create()
	var rng := Rng.new(7)
	# Fill the ring near the cap with long-lived filler so ambient pulses overflow it.
	for i in 62:
		s.emit_sound(w, pos.x, pos.y, 0.0, {"kind": "filler", "range": 2.0, "visRays": 8, "fade": 1000.0})
	var t := 0.0
	s.emit(w, pos.x, pos.y, t, {"bounces": 0})
	var ping: Sonar.Pulse = s.last_pulse
	for i in 1200:
		t += 0.05
		a.step(w, s, pos, 0.05, rng, t)
		ok(s.pulses.size() <= 64, "ring <= 64")
		if not s.pulses.has(ping):
			failures.append("player ping evicted at step %d" % i)
			break
	ok(s.pulses.has(ping), "ping present after 60 s")
	ok(a.emitted > 0, "soak emitted drips")


func test_protect_default_off() -> void:
	var w := _world()
	var pos := _open_spot(w)
	var s := Sonar.create({"maxPulses": 20})
	s.emit(w, pos.x, pos.y, 0.0, {"bounces": 0})
	var first: Sonar.Pulse = s.last_pulse
	for i in 20:
		s.emit_sound(w, pos.x, pos.y, 0.1, {"visRays": 8, "bounces": 0})
	ok(not s.pulses.has(first), "unprotected: oldest evicted as before")
	eq(s.pulses.size(), 20)
	var s2 := Sonar.create({"maxPulses": 20})
	s2.protect_last = true
	s2.emit(w, pos.x, pos.y, 0.0, {"bounces": 0})
	var f2: Sonar.Pulse = s2.last_pulse
	for i in 20:
		s2.emit_sound(w, pos.x, pos.y, 0.1, {"visRays": 8, "bounces": 0})
	ok(s2.pulses.has(f2), "protected survives")
	eq(s2.pulses.size(), 20)
