extends TestCase
## Lightweight critters (core/critters.gd): wander, flee, roost, feed, cap, squeak, determinism.


class StubSonar:
	extends RefCounted
	var calls: Array = []

	func emit_sound(_w, x: float, y: float, t: float, opts: Dictionary = {}):
		calls.append({"x": x, "y": y, "t": t, "opts": opts})
		return null


func _world() -> World:
	var rows: Array = []
	for y in 20:
		var r := ""
		for x in 30:
			r += "#" if (x == 0 or y == 0 or x == 29 or y == 19 or (x == 15 and y < 12)) else "."
		rows.append(r)
	return World.from_def({"name": "t", "kind": "indoor", "rows": rows, "floor": "stone"})


func _snap(seed_: float) -> Array:
	var cs := Critters.new(_world(), seed_)
	cs.populate("rat", 5)
	cs.populate("bat", 3)
	for i in 200:
		cs.step(Vector2(5, 5), 0.1, i % 100 < 50)
	var snap: Array = []
	for c in cs.critters:
		snap.append([c.species, c.x, c.y, c.state])
	return snap


func test_wander_stays_walkable() -> void:
	var w := _world()
	var cs := Critters.new(w, 7)
	cs.populate("rat", 6)
	cs.populate("bat", 4)
	var far := Vector2(-100, -100)
	var bad := 0
	for i in 600:
		cs.step(far, 0.1, false)
		for c in cs.critters:
			if w.blocks(c.x, c.y, Critters.BODY_R):
				bad += 1
	eq(bad, 0, "critters never on blocked cells")
	var moved := 0
	for c in cs.critters:
		if Vector2(c.x - c.home_x, c.y - c.home_y).length() > 0.3:
			moved += 1
	ok(moved > 0, "some critters wandered")


func test_flee_increases_distance() -> void:
	var cs := Critters.new(_world(), 3)
	var c = cs.spawn("rabbit", Vector2i(20, 10), true)
	ok(c != null, "spawned")
	var p := Vector2(c.x - 2.0, c.y)
	var d0 := Vector2(c.x, c.y).distance_to(p)
	for i in 10:
		cs.step(p, 0.1, true)
	ok(Vector2(c.x, c.y).distance_to(p) > d0, "farther after fleeing")


func test_loud_pulse_scares() -> void:
	var cs := Critters.new(_world(), 3)
	var c = cs.spawn("deer", Vector2i(20, 10), false)
	cs.step(Vector2(-50, -50), 0.1, false, {"x": c.x - 3.0, "y": c.y, "strength": 1.0})
	eq(c.state, "flee", "loud pulse flees")


func test_determinism() -> void:
	eq(_snap(42), _snap(42), "same seed same result")
	ok(_snap(42) != _snap(43), "different seed differs")


func test_roost_by_day() -> void:
	var cs := Critters.new(_world(), 5)
	var bat = cs.spawn("bat", Vector2i(20, 10), true)
	var rat = cs.spawn("rat", Vector2i(22, 10), true)
	var rabbit = cs.spawn("rabbit", Vector2i(24, 10), true)
	eq(bat.state, "roost", "bat roosts by day")
	eq(rat.state, "hide", "rat hides by day")
	ok(not rat.visible, "hidden rat not visible")
	var bx: float = bat.x
	var by: float = bat.y
	for i in 100:
		cs.step(Vector2(-50, -50), 0.1, true)
	near(bat.x, bx, 1e-9, "roosting bat does not move x")
	near(bat.y, by, 1e-9, "roosting bat does not move y")
	ok(rabbit.state != "sleep", "day animal active by day")
	for i in 30:
		cs.step(Vector2(-50, -50), 0.1, false)
	eq(bat.state, "wander", "bat wakes at night")
	ok(rat.visible, "rat emerges at night")
	eq(rabbit.state, "sleep", "day animal sleeps at night")
	for i in 3000:
		cs.step(Vector2(-50, -50), 0.1, true)
	eq(bat.state, "roost", "bat returns to roost")


func test_feed_gives_blood_and_removes() -> void:
	var cs := Critters.new(_world(), 5)
	var bat = cs.spawn("bat", Vector2i(20, 10), false)
	var rat = cs.spawn("rat", Vector2i(22, 10), false)
	eq(cs.feed(bat), 6, "bat blood")
	eq(cs.feed(rat), 8, "rat blood")
	eq(cs.feed(bat), 0, "no second drink")
	ok(bat.dead, "marked dead")
	eq(cs.critters.size(), 0, "removed")
	for i in 100:
		cs.step(Vector2(0, 0), 0.1, false)
	eq(cs.critters.size(), 0, "never respawns")
	eq(cs.eaten, 2, "eaten count")


func test_cap_enforced() -> void:
	var cs := Critters.new(_world(), 9)
	var n := 0
	for i in 20:
		if cs.spawn("rat", Vector2i(17 + i % 10, 2 + i / 10)) != null:
			n += 1
	eq(n, 12, "12 max")
	eq(cs.populate("bat", 5), 0, "populate respects cap")
	ok(cs.spawn("unicorn", Vector2i(20, 10)) == null, "unknown species")
	var cs2 := Critters.new(_world(), 9)
	ok(cs2.spawn("rat", Vector2i(0, 0)) == null, "blocked cell")


func test_squeak_emits_via_stub() -> void:
	var cs := Critters.new(_world(), 5)
	cs.spawn("bat", Vector2i(20, 10), false)
	cs.spawn("deer", Vector2i(22, 10), false)
	var st := StubSonar.new()
	eq(cs.squeak(st, 0.0), 0, "nothing due yet")
	for i in 40:
		cs.step(Vector2(-50, -50), 0.1, false)
	var n := cs.squeak(st, 4.0)
	eq(n, 1, "only the bat squeaks")
	eq(st.calls.size(), 1, "stub got one pulse")
	eq(st.calls[0]["opts"]["kind"], "squeak", "kind")
	ok(st.calls[0]["opts"]["strength"] < 0.5, "small pulse")
	eq(cs.squeak(st, 4.1), 0, "not again immediately")


func test_echo_snapshot_visible() -> void:
	var w := _world()
	var cs := Critters.new(w, 5)
	var bat = cs.spawn("bat", Vector2i(20, 10), false)
	var rat = cs.spawn("rat", Vector2i(22, 10), true)
	var far = cs.spawn("deer", Vector2i(26, 16), false)
	var sonar := Sonar.create({"range": 8.0})
	var pu := sonar.emit_sound(w, 18.5, 10.5, 0.0, {"range": 8.0, "strength": 1.0})
	var made := cs.echo_snapshot_visible(pu)
	var ids: Array = []
	for e in made:
		ids.append(e.critter_id)
	ok(ids.has(bat.id), "bat seen")
	ok(not ids.has(rat.id), "hidden rat not seen")
	ok(not ids.has(far.id), "out of range not seen")
	cs.feed(bat)
	eq(cs.echoes.size(), 0, "echo dropped with the critter")
