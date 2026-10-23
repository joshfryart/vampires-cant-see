extends TestCase
## The trek flow (game/trek_flow.gd) headless: begin, walking the Hollow start to exit, the four deaths, dawn and the day choice, Heat,
## second coffin, checkpoint save/restore through SaveCodec, permadeath, the frontier end, determinism.

const SEED := 7


func _meta(unlocks: Dictionary = {}) -> Dictionary:
	var m := TrekMeta.create()
	for k in unlocks:
		m["unlocks"][k] = unlocks[k]
	return m


func _store() -> SaveCodec.Store:
	return SaveCodec.create(SaveCodec.MemoryStorage.new())


func _flow(unlocks: Dictionary = {}, store: Object = null, seed_: int = SEED) -> TrekFlow:
	return TrekFlow.begin(_meta(unlocks), seed_, store)


## reach_exit, then end the run as "frontier" by hand when a further stage generator exists (so the Soil maths stays testable).
func _exit_end(f: TrekFlow) -> Dictionary:
	var r := f.reach_exit()
	if r["ok"] and not r["ended"]:
		return {"ok": true, "ended": true, "result": f.end_run("frontier")}
	return r


func _path(f: TrekFlow) -> Array:
	var c: Vector2i = f.start_cell
	var out: Array = [c]
	var guard := 0
	while f.dist_to_exit(c) > 0 and guard < 5000:
		guard += 1
		var d := f.dist_to_exit(c)
		var nxt := c
		for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			if f.dist_to_exit(c + o) == d - 1:
				nxt = c + o
				break
		if nxt == c:
			break
		c = nxt
		out.append(c)
	return out


func _has(ev: Array, type: String) -> bool:
	for e in ev:
		if e["type"] == type:
			return true
	return false


func _dawn_roofed(f: TrekFlow) -> Array:
	f.night.skip_to(5, 59)
	return f.step(2.0, f.at_cell, false)


func test_begin() -> void:
	var f := _flow()
	ok(f != null, "begin returns a flow")
	eq(f.state, "playing", "playing")
	eq(f.stage_id, "hollow", "first stage")
	ok(f.descriptor["ok"], "descriptor ok")
	eq(f.descriptor["map_name"], "hollow", "map name")
	eq(f.night.min, 0.0, "dusk")
	eq(f.night.status, "night", "night")
	eq(f.heat, 0, "heat 0")
	near(f.miles(), 0.0, 1e-9, "0 miles")
	eq(f.hunters_wanted(), 0, "no hunters")
	eq(f.descriptor["start"], f.start_cell, "start cell")
	eq(f.descriptor["card"]["stage_name"], "The Hollow", "card name")
	ok(f.dist_to_exit(f.start_cell) > 10, "bfs field from the exit reaches the start")
	near(f.night.blood, 60.0, 1e-9, "start blood")
	near(f.night.drain_mul, 0.8, 1e-9, "stage drain mul")
	var f2 := _flow({"slow_thirst": 1, "full_veins": 1, "thick_blood": 1})
	near(f2.night.drain_mul, 0.8 * 0.9, 1e-9, "drain effect")
	near(f2.night.blood, 70.0, 1e-9, "full veins")
	near(f2.night.blood_max, 110.0, 1e-9, "thick blood")
	ok(TrekFlow.begin(_meta(), SEED) != null, "no store is fine")


func test_walk_the_cave_to_the_exit() -> void:
	var st := _store()
	var meta := _meta()
	var f := TrekFlow.begin(meta, SEED, st)
	var path := _path(f)
	eq(f.dist_to_exit(path[path.size() - 1]), 0, "path ends at the exit door")
	var last := 0.0
	var seen_half := false
	for c in path:
		f.step(1.0 / 3.0, c, false)
		ok(f.progress >= last - 1e-12, "progress never drops")
		last = f.progress
		if f.progress > 0.5:
			seen_half = true
	ok(seen_half, "progress passed half")
	ok(f.alive(), "alive at the exit")
	near(f.miles(), 3.0, 1e-9, "3 miles at the exit")
	ok(f.at_exit(path[path.size() - 1]), "at exit")
	ok(f.night.blood > 0.0, "still has blood")
	var r := f.reach_exit()
	ok(r["ok"], "exit taken")
	if not r["ended"]:
		# a next stage generator exists now (wilderness work): end the run here by hand to check the Soil
		r = {"ok": true, "ended": true, "result": f.end_run("frontier")}
		near(f.miles(), 3.0, 3.0, "miles after the exit")
	var res: Dictionary = r["result"]
	eq(res["cause"], "frontier", "frontier cause")
	near(res["miles"], 3.0, 1e-9, "result miles")
	eq(res["unseen"], 1, "cleared unseen")
	ok(res["newBest"], "new best")
	eq(res["soil_breakdown"]["miles"], 3, "miles soil")
	eq(res["soil_breakdown"]["unseen"], 3, "unseen soil")
	eq(res["soil_breakdown"]["newBest"], 5, "best soil")
	eq(res["soilTotal"], 11, "3 + 3 + 5 soil")
	eq(meta["soil"], 11, "soil paid into the meta")
	eq(f.state, "ended", "ended")
	ok(not st.has("trek"), "checkpoint cleared")
	var saved: Dictionary = st.read("rogue")
	ok(saved["ok"] and int(saved["data"]["soil"]) == 11, "rogue meta saved")
	eq(f.end_run("sun"), res, "end_run is idempotent")
	eq(meta["soil"], 11, "no double pay")
	near(res["bestMiles"], 3.0, 1e-9, "best miles")


func test_withered() -> void:
	var f := _flow()
	f.night.blood = 0.0
	var ev := f.step(0.5, f.start_cell, false)
	ok(_has(ev, "withering"), "withering starts")
	ok(f.alive(), "not dead yet")
	ev = f.step(24.0, f.start_cell, false)
	ok(f.alive(), "alive at 24.5 s")
	ev = f.step(1.0, f.start_cell, false)
	ok(_has(ev, "death"), "death event")
	eq(f.state, "dead", "dead")
	eq(f.cause, "withered", "withered")
	var r := f.end_run()
	eq(r["cause"], "withered", "result cause")
	eq(f.meta["stats"]["deaths"]["withered"], 1, "death counted")
	# eating resets the timer
	var g := _flow()
	g.night.blood = 0.0
	g.step(20.0, g.start_cell, false)
	ok(g.on_feed_critter("rat") > 0.0, "fed")
	g.step(10.0, g.start_cell, false)
	ok(g.alive(), "blood resets the withering")
	# long wither extends
	var h := _flow({"long_wither": 3})
	h.night.blood = 0.0
	h.step(27.0, h.start_cell, false)
	ok(h.alive(), "witherSlow extends 25 s to 45 s")
	h.step(20.0, h.start_cell, false)
	eq(h.cause, "withered", "still withers")


func test_sun_outdoors_at_dawn() -> void:
	var f := _flow()
	f.night.skip_to(5, 59)
	var ev := f.step(2.0, f.start_cell, true)
	ok(_has(ev, "death"), "death")
	eq(f.state, "dead", "dead")
	eq(f.cause, "sun", "sun")
	var r := f.end_run()
	eq(r["cause"], "sun", "sun result")
	eq(f.meta["stats"]["deaths"]["sun"], 1, "sun counted")
	# walking out into the day from a choice also kills
	var g := _flow()
	_dawn_roofed(g)
	eq(g.state, "choice", "choice first")
	g.step(0.5, g.start_cell, true)
	eq(g.cause, "sun", "stepping outdoors in daylight")


func test_dawn_warning_and_choice() -> void:
	var f := _flow()
	f.night.skip_to(4, 5)
	ok(f.dawn_in() > 90.0, "still far from dawn")
	var ev := f.step(0.5, f.start_cell, false)
	ok(not _has(ev, "dawn_warning"), "no warning yet")
	ok(not f.dawn_warning(), "flag off")
	f.night.skip_to(4, 10)
	ok(f.dawn_in() < 90.0, "within 90 s")
	ev = f.step(0.5, f.start_cell, false)
	ok(_has(ev, "dawn_warning"), "warning fires")
	ok(f.dawn_warning(), "flag on")
	ev = f.step(0.5, f.start_cell, false)
	ok(not _has(ev, "dawn_warning"), "warning fires once")
	ev = _dawn_roofed(f)
	ok(_has(ev, "dawn") and _has(ev, "needs_choice"), "dawn and needs_choice on a roofed cell")
	eq(f.state, "choice", "choice state")
	ok(f.needs_choice(), "needs choice")
	near(f.dawn_in(), 0.0, 1e-9, "no dawn countdown by day")
	# wait it out: dusk, same stage, Heat +1
	var stage_before := f.stage_id
	var r := f.wait_out_day()
	ok(r["ok"], "wait ok")
	eq(r["result"], "dusk", "reached dusk")
	eq(f.state, "playing", "playing again")
	eq(f.stage_id, stage_before, "same stage")
	eq(f.heat, 1, "Heat 1")
	eq(f.night.status, "night", "night")
	eq(f.night.min, 0.0, "dusk clock")
	eq(f.night.night, 2, "second night")
	ok(f.night.blood > 0.0, "survived the wait")


func test_heat_spawns_hunters() -> void:
	ok(TrekFlow.hunters_for_heat(0) == 0 and TrekFlow.hunters_for_heat(1) == 0, "heat 0/1: none")
	eq(TrekFlow.hunters_for_heat(2), 1, "heat 2: one")
	eq(TrekFlow.hunters_for_heat(3), 2, "heat 3: two")
	eq(TrekFlow.hunters_for_heat(9), 2, "capped at two")
	var f := _flow()
	var want := [0, 1, 2]
	for i in 3:
		f.night.blood = f.night.blood_max
		_dawn_roofed(f)
		var ev_heat: int = f.heat
		var r := f.wait_out_day()
		eq(r["result"], "dusk", "day %d ends in dusk" % (i + 1))
		eq(f.heat, ev_heat + 1, "heat +1")
		eq(f.hunters_wanted(), want[i], "hunters after day %d" % (i + 1))
		ok(_has(r["events"], "dusk"), "dusk event")
		var d: Dictionary = r["events"][0]
		eq(d["hunters"], want[i], "dusk event reports hunters")
	eq(f.heat, 3, "Heat 3 after three days")
	# a new stage would reset heat: enter_stage zeroes it
	f.enter_stage("hollow")
	eq(f.heat, 0, "stage entry resets heat")


func test_sleep_at_rest() -> void:
	var st := _store()
	var f := TrekFlow.begin(_meta(), SEED, st)
	ok(not f.sleep_at_rest(f.start_cell)["ok"], "cannot sleep at night")
	_dawn_roofed(f)
	ok(not f.sleep_at_rest(Vector2i(0, 0))["ok"], "not a rest spot")
	var rest: Array = f.def["rest"]
	var cell := Vector2i(int(rest[0]["cell"][0]), int(rest[0]["cell"][1]))
	var b0: float = f.night.blood
	var r := f.sleep_at_rest(cell)
	ok(r["ok"], "sleep ok")
	ok(["dusk", "noticed"].has(r["result"]), "dusk or found")
	ok(f.heat >= 1, "Heat added")
	eq(f.state, "playing", "playing")
	eq(f.night.status, "night", "night again")
	ok(f.night.blood < b0, "drained a little")
	eq(f.last_rest, cell, "rest spot remembered")
	var rd: Dictionary = st.read("trek")
	ok(rd["ok"], "checkpoint saved on sleep")
	eq(int(rd["data"]["heat"]), f.heat, "saved heat")
	var g := TrekFlow.continue_from(rd["data"], f.meta, st)
	ok(g != null, "continue ok")
	eq(g.at_cell, cell, "resumes at the rest spot")
	eq(g.heat, f.heat, "heat restored")


func test_staked() -> void:
	var f := _flow()
	f.night.blood = 40.0
	var c := f.start_cell
	var hunter := {"x": c.x + 1.0, "y": c.y + 0.5, "noticing": true}
	var ev := f.step(0.1, c, false, {"hunters": [hunter]})
	ok(_has(ev, "death"), "death")
	eq(f.cause, "staked", "staked")
	# healthy: -45, then the cooldown protects
	var g := _flow()
	g.night.blood = 100.0
	ev = g.step(0.1, c, false, {"hunters": [hunter]})
	ok(_has(ev, "stake_hit"), "hit")
	near(g.night.blood, 100.0 - 45.0 - 0.1 * g.night.blood_max / g.night.night_sec * g.night.drain_mul, 1e-6, "-45 blood")
	ev = g.step(1.0, c, false, {"hunters": [hunter]})
	ok(not _has(ev, "stake_hit"), "cooldown")
	# not noticing, too far, or Mist: no hit
	var h := _flow()
	h.night.blood = 40.0
	h.step(0.2, c, false, {"hunters": [{"x": c.x + 1.0, "y": c.y + 0.5, "noticing": false}]})
	ok(h.alive(), "unnoticing hunter is harmless")
	h.step(0.2, c, false, {"hunters": [{"x": c.x + 3.0, "y": c.y + 0.5}]})
	ok(h.alive(), "far hunter is harmless")
	h.step(0.2, c, false, {"hunters": [hunter], "mist": true})
	ok(h.alive(), "Mist protects")
	# stake callus ignores the first
	var k := _flow({"stake_callus": 1})
	k.night.blood = 40.0
	ev = k.step(0.1, c, false, {"hunters": [hunter]})
	ok(_has(ev, "stake_ignored") and k.alive(), "first stake ignored")
	k.step(4.0, c, false, {"hunters": [hunter]})
	eq(k.cause, "staked", "second one kills")


func test_holy_ground() -> void:
	var f := _flow()
	f.night.blood = 30.0
	var ev := f.step(2.0, f.start_cell, false, {"holy": true})
	ok(_has(ev, "holy"), "holy event")
	ok(f.night.blood < 30.0 - 15.0, "-8 blood per second")
	ok(f.alive(), "alive after 2 s")
	f.step(3.0, f.start_cell, false, {"holy": true})
	eq(f.cause, "holy", "holy death")
	eq(f.end_run()["cause"], "holy", "result")
	eq(f.meta["stats"]["deaths"]["holy"], 1, "counted")


func test_second_coffin() -> void:
	var f := _flow({"second_coffin": 1})
	var rest := Vector2i(int(f.def["rest"][0]["cell"][0]), int(f.def["rest"][0]["cell"][1]))
	f.note_rest(rest)
	f.night.skip_to(5, 59)
	var ev := f.step(2.0, f.start_cell, true)
	ok(_has(ev, "revived"), "revived")
	ok(f.alive(), "alive")
	eq(f.deaths_avoided, 1, "used")
	eq(f.at_cell, rest, "at the last rest spot")
	near(f.night.blood, 30.0, 1e-9, "30 blood")
	eq(f.state, "choice", "dawn choice again")
	f.step(0.5, rest, true)
	eq(f.cause, "sun", "second death sticks")
	eq(f.state, "dead", "dead")
	# starvation also revives once
	var g := _flow({"second_coffin": 1})
	g.night.blood = 0.0
	g.step(26.0, g.start_cell, false)
	ok(g.alive() and g.deaths_avoided == 1, "revived from withering")
	near(g.night.blood, 30.0, 0.1, "blood back")


func test_feeding_counts_and_soil() -> void:
	var f := _flow()
	f.night.blood = 20.0
	var gain := f.on_feed_critter("rat")
	near(gain, 8.0, 1e-9, "rat blood")
	f.on_feed_critter("bat")
	f.on_feed_critter("rat")
	f.on_feed_critter("rat")
	var h := f.on_feed_human()
	near(h, 40.0, 1e-9, "human blood")
	f.night.skip_to(5, 59)
	f.step(2.0, f.start_cell, true)
	var r := f.end_run()
	eq(r["humans"], 1, "humans")
	eq(r["critters"], 4, "critters")
	eq(r["soil_breakdown"]["humans"], 2, "2 per human")
	eq(r["soil_breakdown"]["critters"], 2, "critters / 2")
	ok(r["soilTotal"] >= 4 + 5, "soil includes new best")
	eq(r["unseen"], 0, "nothing cleared")
	# soil pouch multiplier
	var p := _flow({"soil_pouch": 2})
	p.humans_fed = 5
	p.step(0.1, p.start_cell, false)
	p.night.skip_to(5, 59)
	p.step(2.0, p.start_cell, true)
	var pr := p.end_run()
	eq(pr["soilTotal"], int(floor(float(10 + 5) * 1.2 + 1e-9)), "pouch x1.2")
	eq(pr["soil_breakdown"]["pouch"], pr["soilTotal"] - 15, "pouch part")


func test_notice_costs_unseen() -> void:
	var f := _flow()
	f.on_notice(3)
	var r := _exit_end(f)
	eq(r["result"]["unseen"], 0, "noticed stage is not unseen")
	eq(r["result"]["cause"], "frontier", "frontier")


func test_checkpoint_roundtrip() -> void:
	var st := _store()
	var meta := _meta({"slow_thirst": 1})
	var f := TrekFlow.begin(meta, SEED, st)
	var rd: Dictionary = st.read("trek")
	ok(rd["ok"], "checkpoint at stage entry")
	ok(SaveCodec.validate_trek(rd["data"])["ok"], "validates as a trek save")
	var path := _path(f)
	for i in 40:
		f.step(1.0 / 3.0, path[i], false)
	f.on_feed_critter("rat")
	f.on_feed_human()
	var snap := f.snapshot()
	ok(SaveCodec.validate_trek(snap)["ok"], "live snapshot validates")
	var g := TrekFlow.continue_from(JSON.parse_string(JSON.stringify(snap)), meta, st)
	ok(g != null, "restored through a JSON round trip")
	eq(g.stage_id, f.stage_id, "stage")
	eq(g.seed, f.seed, "seed")
	eq(g.def["rows"], f.def["rows"], "same cave")
	near(g.night.blood, f.night.blood, 1e-9, "blood")
	near(g.night.min, f.night.min, 1e-9, "clock")
	near(g.progress, f.progress, 1e-9, "progress")
	eq(g.heat, f.heat, "heat")
	eq(g.humans_fed, 1, "humans")
	eq(g.critters_fed, 1, "critters")
	eq(g.at_cell, f.at_cell, "position")
	eq(g.descriptor["start"], f.at_cell, "descriptor resumes at the saved cell")
	near(g.night.drain_mul, f.night.drain_mul, 1e-9, "drain")
	eq(g.state, "playing", "state")
	eq(g.snapshot()["night"]["trek"], snap["night"]["trek"], "extras round trip")
	# a bad save is refused
	var bad := snap.duplicate(true)
	bad["stage"] = 5
	ok(TrekFlow.continue_from(bad, meta) == null, "invalid save refused")
	bad = snap.duplicate(true)
	bad["night"].erase("blood")
	ok(TrekFlow.continue_from(bad, meta) == null, "invalid night refused")
	# a saved day choice survives
	var h := _flow()
	_dawn_roofed(h)
	var h2 := TrekFlow.continue_from(JSON.parse_string(JSON.stringify(h.snapshot())), h.meta)
	eq(h2.state, "choice", "choice restored")


func test_permadeath_clears_the_checkpoint() -> void:
	var st := _store()
	var f := TrekFlow.begin(_meta(), SEED, st)
	ok(st.has("trek"), "checkpoint exists")
	f.night.blood = 0.0
	f.step(30.0, f.start_cell, false)
	eq(f.state, "dead", "dead")
	ok(st.has("trek"), "still there until end_run")
	var r := f.end_run()
	ok(not st.has("trek"), "gone after end_run")
	ok(r["saved"], "rogue meta saved")
	ok(st.has("rogue"), "rogue slot written")
	eq(int(st.read("rogue")["data"]["stats"]["treks"]), 1, "trek counted")
	ok(not f.alive(), "not alive")
	eq(f.step(1.0, f.start_cell, false).size(), 0, "no events after the end")


func test_frontier_pays_soil_with_pouch() -> void:
	var meta := _meta({"soil_pouch": 1})
	var f := TrekFlow.begin(meta, SEED)
	for c in _path(f):
		f.step(0.3, c, false)
	var r := _exit_end(f)
	var res: Dictionary = r["result"]
	eq(res["cause"], "frontier", "frontier")
	eq(res["soilTotal"], int(floor(11.0 * 1.1 + 1e-9)), "pouch applies to a frontier end")
	eq(meta["soil"], res["soilTotal"], "paid")
	ok(int(meta["stats"]["bestStage"]) >= 1, "best stage recorded")
	ok(meta["reached"].has("hollow"), "reached recorded")
	eq(TrekFlow.next_stage_id("hollow"), "wood", "next stage from the row")
	ok(TrekFlow.stage_order().size() >= 13, "stage order list")


func test_determinism() -> void:
	var a := _flow({}, null, 11)
	var b := _flow({}, null, 11)
	var c := _flow({}, null, 12)
	eq(a.def["rows"], b.def["rows"], "same seed, same cave")
	eq(a.start_cell, b.start_cell, "same start")
	eq(a.dist, b.dist, "same distance field")
	ok(a.def["rows"] != c.def["rows"], "different seed, different cave")
	var sa := JSON.stringify(a.snapshot())
	var sb := JSON.stringify(b.snapshot())
	eq(sa, sb, "same snapshot")
	# same sleep outcome
	_dawn_roofed(a)
	_dawn_roofed(b)
	var cell := Vector2i(int(a.def["rest"][0]["cell"][0]), int(a.def["rest"][0]["cell"][1]))
	var ra := a.sleep_at_rest(cell)
	var rb := b.sleep_at_rest(cell)
	eq(ra["result"], rb["result"], "same sleep result")
	near(ra["blood"], rb["blood"], 1e-12, "same blood")


func test_eaten_and_wither_survive_a_quit_save() -> void:
	var st := _store()
	var f := _flow({}, st)
	f.mark_eaten(3)
	f.mark_eaten(3)
	f.mark_eaten(5)
	eq(f.eaten.size(), 2, "eaten indices are unique")
	f.night.blood = 0.0
	f.step(6.0, f.start_cell, false, {"hunters": []})
	var left := f.withering_left()
	ok(left > 0.0 and left < 19.5, "wither running (%.1f)" % left)
	var far: Vector2i = _path(f)[20]
	f.update_position(far)
	ok(f.quit_checkpoint(), "quit checkpoint written")
	var rd: Dictionary = st.read("trek")
	var g := TrekFlow.continue_from(rd["data"], f.meta, st)
	ok(g != null, "loads")
	eq(g.eaten, [3, 5], "eaten list restored")
	near(g.withering_left(), left, 0.01, "wither timer restored")
	eq(g.at_cell, f.start_cell, "position is the checkpoint, not where you quit")
	ok(g.progress > 0.0, "best progress is kept")
	# a new stage forgets the list
	ok(TrekFlow.begin(_meta(), SEED, st).eaten.is_empty(), "fresh trek: nothing eaten")


func test_frozen_step_holds_everything() -> void:
	var f := _flow()
	var b0 := f.night.blood
	var m0 := f.night.min
	var ev := f.step(5.0, f.start_cell, false, {"frozen": true, "player_pos": Vector2(f.start_cell.x + 0.5, f.start_cell.y + 0.5), "hunters": [{"x": f.start_cell.x + 0.5, "y": f.start_cell.y + 0.5}]})
	eq(ev.size(), 0, "no events")
	near(f.night.blood, b0, 1e-9, "no drain or stake")
	near(f.night.min, m0, 1e-9, "clock held")


func test_noticed_asleep_is_one_heat() -> void:
	var f := _flow()
	f.night.skip_to(5, 59)
	f.step(2.0, f.start_cell, false, {})
	var rc := Vector2i(int(f.def["rest"][0]["cell"][0]), int(f.def["rest"][0]["cell"][1]))
	var best := 99
	for seed_ in 40:
		var h := _flow({}, null, seed_ + 1)
		h.night.skip_to(5, 59)
		h.step(2.0, h.start_cell, false, {})
		var c := Vector2i(int(h.def["rest"][0]["cell"][0]), int(h.def["rest"][0]["cell"][1]))
		var r := h.sleep_at_rest(c)
		if r.get("ok", false):
			best = mini(best, h.heat)
			ok(h.heat <= 1, "sleep adds at most +1 Heat (%s -> %d)" % [r["result"], h.heat])
	ok(best <= 1, "sampled")
