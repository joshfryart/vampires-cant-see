extends TestCase
## WaitDay (game/wait_day.gd): wait out the day, sleep skip, interrupts, discovery, withering, determinism, resume.

const DAY := 60.0


class StubEmitter:
	extends RefCounted
	var calls: Array = []

	func emit(_w, x: float, y: float, t: float, opts: Dictionary = {}):
		calls.append({"x": x, "y": y, "t": t, "opts": opts})
		return null


## Two chambers (x1..8 and x10..18) joined by a door at (9, 5).
func _two_rooms() -> World:
	var rows: Array = []
	for y in 11:
		var r := ""
		for x in 20:
			var ch := "."
			if x == 0 or x == 19 or y == 0 or y == 10:
				ch = "#"
			elif x == 9:
				ch = "D" if y == 5 else "#"
			r += ch
		rows.append(r)
	return World.from_def({"name": "t", "kind": "indoor", "rows": rows, "floor": "stone"})


func _open_room() -> World:
	var rows: Array = []
	for y in 11:
		var r := ""
		for x in 24:
			r += "#" if (x == 0 or x == 23 or y == 0 or y == 10) else "."
		rows.append(r)
	return World.from_def({"name": "t", "kind": "indoor", "rows": rows, "floor": "stone"})


func _person(id: int, x: float, y: float, stops: Array = []) -> People.Person:
	var q := People.Person.new()
	q.id = id
	q.x = x
	q.y = y
	q.role = "farmer"
	q.path = [{"x": x, "y": y, "wait": 1.0}]
	q.idx = 0
	q.state = "idle"
	q.look_in = 1.0
	if not stops.is_empty():
		q.sched = {"role": "farmer", "home": null, "stops": stops, "si": -1, "target": -1, "en": false, "retarget": false}
	return q


func _people(w: World, persons: Array) -> People:
	var ppl := People.new()
	ppl.rng = Rng.new(5.0)
	ppl.chat_rng = Rng.new(9.0)
	ppl.world = w
	for q in persons:
		ppl.people.append(q)
	return ppl


func _stop(x: float, y: float, at: float, until: float, act: String = "work") -> Dictionary:
	return {"place": "p", "x": x, "y": y, "at": at, "until": until, "act": act}


## Occupant sits in the right chamber, then walks through the door into the player's chamber.
func _visitor_scene(seed_: float, params: Dictionary = {}) -> WaitDay:
	var w := _two_rooms()
	var q := _person(1, 15.5, 5.5, [_stop(15.5, 5.5, 0.0, 0.3), _stop(5.5, 5.5, 0.3, 1.0)])
	var ppl := _people(w, [q])
	var pr := {"day_sec": DAY}
	pr.merge(params, true)
	var wd := WaitDay.new(w, ppl, null, Rng.new(seed_), pr)
	wd.start(Vector2(3.5, 5.5), 50.0, 0.05, false)
	w.set_door(9, 5, true)
	return wd


func test_no_occupants_reaches_dusk() -> void:
	var wd := WaitDay.new(_open_room(), null, null, Rng.new(1.0), {"day_sec": DAY})
	wd.start(Vector2(3.5, 5.5), 50.0, 0.05, false)
	var o := wd.run_to_end()
	eq(o["result"], "dusk", "dusk")
	near(o["elapsed"], DAY, 1e-6, "elapsed full day")
	near(o["blood_after"], 50.0 - 0.05 * 0.4 * DAY, 1e-6, "drain x0.4")
	eq(o["heat_add"], 1, "heat +1")
	eq(wd.run_to_end()["heat_add"], 0, "heat charged once")


func test_step_slicing_does_not_change_result() -> void:
	var a := WaitDay.new(_open_room(), null, null, Rng.new(1.0), {"day_sec": DAY})
	a.start(Vector2(3.5, 5.5), 50.0, 0.05)
	var b := WaitDay.new(_open_room(), null, null, Rng.new(1.0), {"day_sec": DAY})
	b.start(Vector2(3.5, 5.5), 50.0, 0.05)
	a.run_to_end()
	var o := {}
	for i in 100000:
		o = b.step(0.013)
		if o["result"] != "running":
			break
	near(o["blood_after"], a.blood, 1e-9, "same blood")
	eq(o["result"], "dusk", "dusk")


func test_scheduled_occupant_interrupts() -> void:
	var wd := _visitor_scene(3.0, {"see_dist": 0.1})
	var o := wd.run_to_end()
	eq(o["result"], "interrupted", "interrupted")
	eq(o["reason"], "occupant_in_room", "reason")
	ok(o["elapsed"] > 0.3 * DAY and o["elapsed"] < DAY, "after the schedule moved them")
	eq(o["heat_add"], 1, "heat reported on first outcome")


func test_resume_after_interrupt() -> void:
	var wd := _visitor_scene(3.0, {"see_dist": 0.1})
	var o := wd.run_to_end()
	eq(o["result"], "interrupted", "interrupted first")
	var t1: float = o["elapsed"]
	ok(wd.resume(), "resume ok")
	eq(wd.step(0.01)["result"], "running", "running again (no instant re-interrupt)")
	var o2 := wd.run_to_end()
	eq(o2["result"], "dusk", "reaches dusk after resume")
	ok(o2["elapsed"] > t1, "kept going")
	eq(o2["heat_add"], 0, "heat not double counted")
	near(o2["blood_after"], 50.0 - 0.05 * 0.4 * DAY, 1e-6, "total drain unaffected by the pause")
	ok(not wd.resume(), "nothing to resume at dusk")


func test_near_and_guard_interrupts() -> void:
	var w := _open_room()
	var ppl := _people(w, [_person(1, 6.0, 5.5)])
	var wd := WaitDay.new(w, ppl, null, Rng.new(1.0), {"day_sec": DAY, "see_dist": 0.1})
	wd.start(Vector2(3.5, 5.5), 50.0, 0.05, false)
	wd.room = {}
	eq(wd.run_to_end()["reason"], "occupant_near", "within near_dist")
	var g := _person(2, 8.5, 5.5)
	g.watch = true
	var ppl2 := _people(w, [g])
	var wd2 := WaitDay.new(w, ppl2, null, Rng.new(1.0), {"day_sec": DAY, "see_dist": 0.1})
	wd2.start(Vector2(3.5, 5.5), 50.0, 0.05, false)
	wd2.room = {}
	eq(wd2.run_to_end()["reason"], "guard_near", "guard path nears")


func _noticed(seed_: float, hidden: bool) -> bool:
	var w := _open_room()
	var ppl := _people(w, [_person(1, 8.5, 5.5)])
	var wd := WaitDay.new(w, ppl, null, Rng.new(seed_), {"day_sec": 20.0})
	wd.start(Vector2(3.5, 5.5), 50.0, 0.05, hidden)
	return wd.run_to_end(true)["result"] == "noticed"


func test_hidden_player_is_noticed_less() -> void:
	var vis := 0
	var hid := 0
	for s in 40:
		if _noticed(float(s), false):
			vis += 1
		if _noticed(float(s), true):
			hid += 1
	ok(vis >= 34, "visible player usually noticed (%d/40)" % vis)
	ok(hid < vis - 6, "hidden noticed far less (%d vs %d)" % [hid, vis])
	var w := _open_room()
	var wd := WaitDay.new(w, _people(w, [_person(7, 8.5, 5.5)]), null, Rng.new(0.0), {"day_sec": 20.0})
	wd.start(Vector2(3.5, 5.5), 50.0, 0.05, false)
	var o := wd.run_to_end(true)
	eq(o["result"], "noticed", "seed 0 notices")
	eq(o["by"], 7, "by person id")
	ok(not _noticed(0.0, false) == false, "same seed same answer")
	# a hide cell list counts too, a wall blocks sight
	var w2 := _two_rooms()
	var wd2 := WaitDay.new(w2, _people(w2, [_person(1, 15.5, 5.5)]), null, Rng.new(0.0), {"day_sec": 20.0})
	wd2.start(Vector2(3.5, 5.5), 50.0, 0.05, [[3, 5]])
	ok(wd2.hidden, "hides list matched")
	eq(wd2.run_to_end(true)["result"], "dusk", "no line of sight through the wall")


func test_withers() -> void:
	var wd := WaitDay.new(_open_room(), null, null, Rng.new(1.0), {"day_sec": DAY})
	wd.start(Vector2(3.5, 5.5), 0.5, 1.0, false)
	var o := wd.run_to_end()
	eq(o["result"], "withered", "withered")
	near(o["blood_after"], 0.0, 1e-9, "no blood")
	ok(o["elapsed"] < DAY, "cut short")


func test_sleep_cheaper_than_waiting() -> void:
	var a := WaitDay.new(_open_room(), null, null, Rng.new(1.0), {"day_sec": DAY})
	a.start(Vector2(3.5, 5.5), 50.0, 0.05)
	var waited := a.run_to_end()
	var b := WaitDay.new(_open_room(), null, null, Rng.new(1.0), {"day_sec": DAY})
	b.start(Vector2(3.5, 5.5), 50.0, 0.05)
	var slept := b.sleep_at({"safety": 1.0}, 0.0)
	eq(slept["result"], "dusk", "slept to dusk")
	near(slept["blood_after"], 50.0 - 0.05 * 0.15 * DAY, 1e-6, "drain x0.15")
	ok(slept["blood_after"] > waited["blood_after"], "sleep costs less than waiting")
	eq(slept["heat_add"], 1, "sleep adds heat too")


func _sleep_noticed(seed_: float, safety: float, heat: float) -> bool:
	var wd := WaitDay.new(_open_room(), null, null, Rng.new(seed_), {"day_sec": DAY})
	wd.start(Vector2(3.5, 5.5), 50.0, 0.05)
	return wd.sleep_at({"safety": safety}, heat)["result"] == "noticed"


func test_sleep_discovery_honours_safety() -> void:
	var lo := 0
	var hi := 0
	var hot := 0
	var perfect := 0
	for s in 300:
		if _sleep_noticed(float(s), 0.1, 0.0):
			lo += 1
		if _sleep_noticed(float(s), 0.9, 0.0):
			hi += 1
		if _sleep_noticed(float(s), 0.1, 3.0):
			hot += 1
		if _sleep_noticed(float(s), 1.0, 3.0):
			perfect += 1
	ok(lo > hi, "unsafe spot found more often (%d vs %d)" % [lo, hi])
	ok(lo > 20 and lo < 100, "about 18%% at safety 0.1 (%d/300)" % lo)
	ok(hot >= lo, "heat raises the roll (%d vs %d)" % [hot, lo])
	eq(perfect, 0, "safety 1.0 is never found")


func test_listening_pulses() -> void:
	var stub := StubEmitter.new()
	var wd := _visitor_scene(3.0, {"emitter": stub.emit, "see_dist": 0.1})
	wd.run_to_end(true)
	ok(stub.calls.size() > 0, "occupants gave listening pulses")
	var short := true
	for c in stub.calls:
		if c["opts"]["kind"] != "listen" or float(c["opts"]["range"]) > 4.0 or float(c["opts"]["strength"]) > 0.2:
			short = false
	ok(short, "faint, short range")
	var heard := 0
	for e in wd.events:
		if e["type"] == "listen":
			heard += 1
	eq(heard, stub.calls.size(), "every pulse logged as an event")


func _snap(seed_: float) -> Array:
	var wd := _visitor_scene(seed_, {"see_dist": 0.1})
	var o := wd.run_to_end(true)
	return [o["result"], o["elapsed"], o["blood_after"], str(o["events"])]


func test_determinism() -> void:
	eq(_snap(11.0), _snap(11.0), "same seed same run")
	ok(str(_snap(11.0)[3]) != str(_snap(12.0)[3]), "different seed differs (listen jitter)")


func test_critters_rest_during_the_day() -> void:
	var w := _open_room()
	var cs := Critters.new(w, 4.0)
	var bat = cs.spawn("bat", Vector2i(20, 5), true)
	ok(bat != null, "bat spawned")
	var wd := WaitDay.new(w, null, cs, Rng.new(1.0), {"day_sec": DAY})
	wd.start(Vector2(3.5, 5.5), 50.0, 0.05)
	var o := wd.run_to_end()
	eq(o["result"], "dusk", "dusk")
	eq(bat.state, "roost", "bat still roosting")
	near(cs.time, DAY, 1e-6, "critters ran the whole day")
