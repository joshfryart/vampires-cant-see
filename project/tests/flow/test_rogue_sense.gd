extends TestCase
## Hollow wayfinding (game/rogue_mode.gd, trek_flow.gd, core/ambient.gd): next_toward_exit, the panned draft, the lost tracker and the
## assist ladder, the breath beads, the tutorial draft / sense steps, and the Sense key (V): free in the Hollow, blood after it, refused
## when too weak, cooldown, bearing, the cue timer, hints, the one-time notice, frozen input, classic untouched.

const SEED := 7


func _game() -> Game:
	Game.test_storage = SaveCodec.MemoryStorage.new()
	Game.manual_boot = true
	GameData.clear_generated()
	var g := Game.new()
	g.boot()
	return g


func _done(g: Game) -> void:
	g.free()
	GameData.clear_generated()


func _trek(g: Game, seed_v: int = SEED) -> RogueMode:
	g.rogue.new_trek(seed_v)
	return g.rogue


func _step(g: Game, seconds: float, inp: Dictionary = {}, dt: float = 0.05) -> void:
	for i in int(round(seconds / dt)):
		g.step(dt, inp)


## A walkable cell at least `min_d` BFS steps from the exit (the first one in scan order).
func _far_cell(f: TrekFlow, min_d: int) -> Vector2i:
	for y in f.world.height:
		for x in f.world.width:
			if f.dist_to_exit(Vector2i(x, y)) >= min_d and not f.world.blocks(x + 0.5, y + 0.5, 0.2):
				return Vector2i(x, y)
	return Vector2i(-1, -1)


func _place(g: Game, c: Vector2i, angle: float = 0.0) -> void:
	g.player.place(c.x + 0.5, c.y + 0.5, angle)


# ---------------------------------------------------------------- P1 next_toward_exit

func test_next_toward_exit_walks_downhill() -> void:
	var g := _game()
	var f := _trek(g).trek
	var checked := 0
	for y in f.world.height:
		for x in f.world.width:
			var c := Vector2i(x, y)
			var d := f.dist_to_exit(c)
			if d < 0:
				eq(f.next_toward_exit(c, 6), c, "a cell with no distance stays put")
				continue
			for k in [1, 3, 6]:
				var r := f.next_toward_exit(c, k)
				eq(f.dist_to_exit(r), maxi(0, d - k), "k=%d from %s is k steps closer or the exit" % [k, str(c)])
				eq(r, f.next_toward_exit(c, k), "deterministic")
			checked += 1
	ok(checked > 100, "walked many cells (%d)" % checked)
	eq(f.next_toward_exit(f.exit_cell, 6), f.exit_cell, "the exit stays the exit")
	var s := f.start_cell
	eq(f.next_toward_exit(s, 0), s, "k = 0 stays")
	_done(g)


# ---------------------------------------------------------------- P2 the panned draft

func test_draft_pan_flips_with_a_half_turn_and_gain_is_capped() -> void:
	var g := _game()
	var r := _trek(g)
	var f := r.trek
	var c := _far_cell(f, 10)
	var src := f.next_toward_exit(c, RogueMode.WIND_AHEAD)
	var sp := Vector2(src.x + 0.5, src.y + 0.5)
	var pp := Vector2(c.x + 0.5, c.y + 0.5)
	var to := atan2(sp.y - pp.y, sp.x - pp.x)
	_place(g, c, to - PI / 2.0)   # the way out is on the right
	r._step_wind(0.05)
	ok(r.wind_pan_now > 0.3, "the draft is on the right: %f" % r.wind_pan_now)
	near(r.wind_src.x, sp.x, 1e-6)
	_place(g, c, to - PI / 2.0 + PI)   # turned 180 degrees
	r._step_wind(0.05)
	ok(r.wind_pan_now < -0.3, "after a half turn it is on the left: %f" % r.wind_pan_now)
	_place(g, c, to)
	r._step_wind(0.05)
	near(r.wind_pan_now, 0.0, 0.01, "straight ahead is centred")
	near(RogueMode.wind_pan(pp, 0.7, sp), -RogueMode.wind_pan(pp, 0.7 + PI, sp), 1e-9, "pan is odd in a half turn")
	# gain never passes the cap: near the door, floor at every level, a Sense swell
	var worst := 0.0
	for lv in [0, 1, 2]:
		r.assist = lv
		for cell in [f.exit_cell, c, f.start_cell]:
			_place(g, cell)
			for i in 80:
				r._step_wind(0.05)
				worst = maxf(worst, r._wind_level)
	r.sense_t = RogueMode.SENSE_CUE_S
	for i in 40:
		r.sense_t = RogueMode.SENSE_CUE_S - 0.5
		r._step_wind(0.05)
		worst = maxf(worst, r._wind_level)
	ok(worst <= RogueMode.WIND_CAP + 1e-9, "level %f stays within WIND_CAP" % worst)
	ok(worst > RogueMode.WIND_FLOOR, "and it does swell")
	near(RogueMode.wind_floor(0), 0.0)
	near(RogueMode.wind_floor(1), 0.06)
	near(RogueMode.wind_floor(2), 0.12)
	_done(g)


func test_floor_makes_the_draft_audible_far_from_the_door() -> void:
	var g := _game()
	var r := _trek(g)
	var c := _far_cell(r.trek, 40)
	if c.x < 0:
		c = _far_cell(r.trek, 25)
	_place(g, c)
	r.sense_t = 0.0
	r.assist = 0
	for i in 100:
		r._step_wind(0.1)
	near(r._wind_level, 0.0, 1e-9, "silent far from the door at level 0")
	r.assist = 2
	for i in 100:
		r._step_wind(0.1)
	near(r._wind_level, RogueMode.WIND_FLOOR, 1e-6, "level 2 floor")
	_done(g)


# ---------------------------------------------------------------- P3 lost tracker and the assist ladder

func test_assist_thresholds() -> void:
	var fx := {"sonarRange": 1.0}
	eq(RogueMode.assist_level(0.0, fx, true, 0, 0), 0)
	eq(RogueMode.assist_level(24.9, fx, true, 0, 0), 0)
	eq(RogueMode.assist_level(25.0, fx, true, 0, 0), 1, "level 1 at 25 s with the tutorial on")
	eq(RogueMode.assist_level(49.9, fx, true, 0, 0), 1)
	eq(RogueMode.assist_level(50.0, fx, true, 0, 0), 2, "level 2 at 50 s")
	# tutorial off or done: x1.5
	eq(RogueMode.assist_level(37.4, fx, false), 0)
	eq(RogueMode.assist_level(37.5, fx, false), 1)
	eq(RogueMode.assist_level(74.9, fx, false), 1)
	eq(RogueMode.assist_level(75.0, fx, false), 2)
	# far_echo (sonarRange) x2
	var far := {"sonarRange": 1.25}
	eq(RogueMode.assist_level(49.9, far, true), 0)
	eq(RogueMode.assist_level(50.0, far, true), 1)
	eq(RogueMode.assist_level(100.0, far, true), 2)
	# stage index >= 1: x2, and they multiply
	eq(RogueMode.assist_level(49.9, fx, true, 1), 0)
	eq(RogueMode.assist_level(50.0, fx, true, 1), 1)
	eq(RogueMode.assist_level(100.0, fx, true, 1), 2)
	eq(RogueMode.assist_level(149.9, fx, false, 1), 1)
	eq(RogueMode.assist_level(150.0, fx, false, 1), 2)
	near(RogueMode.assist_thresholds(far, false, 1).x, 150.0, 1e-9, "1.5 x 2 x 2 x 25")
	# Heat 3: never level 2
	eq(RogueMode.assist_level(500.0, fx, true, 0, 2), 2)
	eq(RogueMode.assist_level(500.0, fx, true, 0, 3), 1)
	eq(RogueMode.assist_level(10.0, fx, true, 0, 3), 0)


func test_lost_grows_and_resets_on_progress() -> void:
	var g := _game()
	var r := _trek(g)
	var f := r.trek
	g.card_text = ""
	_step(g, 10.0)
	ok(r.lost_t > 8.0 and r.lost_t < 11.0, "standing still: lost %f" % r.lost_t)
	eq(r.assist, 0)
	_step(g, 16.0)
	eq(r.assist, 1, "level 1 after 25 s lost (tutorial on)")
	# a step backwards is not progress
	var c := f.start_cell
	var back := c
	for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if f.dist_to_exit(c + o) > f.dist_to_exit(c):
			back = c + o
	_place(g, back)
	_step(g, 0.2)
	ok(r.lost_t > 20.0, "going back does not reset the timer")
	# a new best does
	_place(g, f.next_toward_exit(c, 3))
	_step(g, 0.1)
	ok(r.lost_t < 0.5, "a new best distance resets it: %f" % r.lost_t)
	eq(r.assist, 0, "and the assist drops")
	_done(g)


# ---------------------------------------------------------------- P4 breath beads

func test_no_beads_at_level_zero() -> void:
	var g := _game()
	var r := _trek(g)
	g.card_text = ""
	_step(g, 15.0)
	eq(r.assist, 0)
	eq(int(r.stats.get("breaths", 0)), 0, "none emitted")
	for p in g.sonar.pulses:
		ok(String(p.kind) != "breath", "no breath pulse live")
	_done(g)


func test_beads_lead_toward_the_exit_within_budget() -> void:
	var g := _game()
	var r := _trek(g)
	var f := r.trek
	g.menus.set_tutorial_enabled(false)
	g.tut.rogue_stop()
	_place(g, _far_cell(f, 12))
	var seen_kinds := 0
	var t := 0.0
	var worst_live := 0
	var worst_rays := 0
	while t < 80.0:
		g.step(0.05, {})
		t += 0.05
		var here := Vector2i(floori(g.player.x), floori(g.player.y))
		var rays := 0
		for p in g.sonar.pulses:
			if String(p.kind) == "breath":
				var bc := Vector2i(floori(p.x), floori(p.y))
				ok(f.dist_to_exit(bc) < f.dist_to_exit(here), "a bead lies closer to the exit than the player")
				seen_kinds += 1
		worst_live = maxi(worst_live, r.ambient.live_count(g.sonar))
		worst_rays = maxi(worst_rays, r.ambient.rays_step)
	ok(int(r.stats["breaths"]) >= 2, "beads were emitted: %d" % int(r.stats["breaths"]))
	ok(seen_kinds > 0, "and they are in the sonar")
	ok(worst_live <= Ambient.MAX_LIVE, "at most 4 live ambient pulses (%d)" % worst_live)
	ok(worst_rays <= Ambient.MAX_RAYS, "at most 180 rays a step (%d)" % worst_rays)
	_done(g)


func test_emit_at_respects_the_budget() -> void:
	var w := World.from_def(GameData.map_def("test"))
	var s := Sonar.create()
	var kinds := {
		"big": {"range": 2.0, "strength": 0.2, "z": 0.0, "fade": 3.0, "visRays": 180, "bounces": 0, "period": [0.05, 0.05], "jitter": 0.0, "within": 99},
		"breath": Ambient.load_kinds()["breath"],
	}
	var a := Ambient.new([], {"kinds": kinds})
	var pos := Vector2(2.5, 2.5)
	for y in range(2, w.height - 2):
		for x in range(2, w.width - 2):
			if w.solid_grid[y * w.width + x] == 0 and pos == Vector2(2.5, 2.5):
				pos = Vector2(x + 0.5, y + 0.5)
	a.add({"cell": [int(pos.x), int(pos.y)], "kind": "big"})
	var rng := Rng.new(3)
	for i in 6:
		a.step(w, s, pos, 0.05, rng)
	ok(a.emitted >= 1 and a.rays_step <= 180, "an anchor fired")
	var skipped := a.skipped_budget
	if a.rays_step + 40 > Ambient.MAX_RAYS:
		ok(not a.emit_at("breath", w, s, pos.x, pos.y), "the ray budget refuses a bead after a 180-ray pulse")
		ok(a.skipped_budget > skipped, "and counts it")
	# four live pulses: full
	var a2 := Ambient.new([], {"kinds": kinds})
	var s2 := Sonar.create()
	a2.clock = 1.0
	var n := 0
	for i in 8:
		if a2.emit_at("breath", w, s2, pos.x, pos.y):
			n += 1
		a2.rays_step = 0
	eq(n, Ambient.MAX_LIVE, "no more than 4 live")
	ok(not a2.emit_at("breath", w, s2, pos.x, pos.y), "the fifth is refused")
	var bd: Dictionary = Ambient.load_kinds()["breath"]
	near(float(bd["range"]), 2.5)
	near(float(bd["strength"]), 0.08)
	eq(int(bd["visRays"]), 40)
	eq(int(bd["within"]), 99)


func test_a_bead_never_drops_the_players_ping() -> void:
	var g := _game()
	var r := _trek(g)
	g.menus.set_tutorial_enabled(false)
	g.tut.rogue_stop()
	_place(g, _far_cell(r.trek, 12))
	_step(g, 80.0)   # lost: level 2, beads every 3 s
	ok(r.assist >= 1, "assisted")
	_step(g, 1.0)
	ok(g.pulse(), "the player pings")
	for i in 60:
		g.step(0.05, {})
		ok(g.sonar.pulses.has(g.sonar.last_pulse) or g.clock - g.sonar.last_emit > 3.0, "the ping survives the beads")
	_done(g)


# ---------------------------------------------------------------- P6 the tutorial draft and sense steps

func test_tutorial_texts_fit() -> void:
	for id in ["sense", "draft"]:
		var t := String(Tutorial.new(null, false).step_def(id)["text"])
		ok(t.length() > 0 and t.length() <= Tutorial.MAX_TEXT, "%s fits (%d)" % [id, t.length()])
		ok((t + Tutorial.SKIP_SUFFIX).length() <= 90, "%s plus skip fits the line" % id)
	eq(String(Tutorial.new(null, false).step_def("draft")["text"]), "Feel that draft? Air wants out. So do you.")
	ok(String(Tutorial.new(null, false).step_def("sense")["text"]).begins_with("V: sense the way. Free in the cave"))


func test_draft_step_fires_once_when_lost_and_tab_skips() -> void:
	var g := _game()
	var r := _trek(g)
	g.card_text = ""
	_step(g, 20.0)
	ok(not g.tut.rogue_done.has("draft") and g.tut.rogue_cur != "draft", "not before the player is lost")
	_step(g, 8.0)   # lost 28 s: level 1 -> the V line
	eq(g.tut.rogue_cur, "sense", "the first time lost: how to sense")
	ok(g.hint_text.begins_with("V: sense the way."), g.hint_text)
	_step(g, 8.0)   # that step is timed 7 s
	_step(g, 16.0)  # lost about 52 s: level 2
	eq(r.assist, 2)
	eq(g.tut.rogue_cur, "draft", "level 2: the draft line")
	ok(g.hint_text.begins_with("Feel that draft? Air wants out. So do you."), g.hint_text)
	_step(g, 7.0)
	ok(g.tut.rogue_done.has("draft"), "it completes")
	_step(g, 20.0)
	ok(g.tut.rogue_cur != "draft", "and never comes back this run")
	_done(g)


func test_tab_skips_the_draft_step() -> void:
	var g := _game()
	var r := _trek(g)
	g.card_text = ""
	_step(g, 56.0)
	ok(g.tut.rogue_active, "still guided")
	g.pressed[KEY_TAB] = true
	g.step(0.05, {})
	ok(not g.tut.rogue_active, "Tab ends it")
	eq(g.hint_text, "", "no line")
	ok(r.assist >= 1, "the wind and beads carry on")
	_done(g)


func test_sim_is_identical_with_the_tutorial_on_and_off() -> void:
	var out: Array = []
	for tut_on in [true, false]:
		var g := _game()
		if not tut_on:
			g.menus.set_tutorial_enabled(false)
		var r := _trek(g)
		g.card_text = ""
		_step(g, 90.0, {"forward": 0.0})
		out.append([g.player.x, g.player.y, g.clock, r.trek.night.blood, r.trek.night.min, r.critters.critters.size()])
		_done(g)
	eq(out[0], out[1], "the tutorial never touches the sim")


# ---------------------------------------------------------------- Sense

func test_sense_is_free_in_the_hollow() -> void:
	var g := _game()
	var r := _trek(g)
	g.card_text = ""
	g.night.blood = 20.0
	var res := r.try_sense()
	ok(res["ok"], "sense works")
	near(g.night.blood, 20.0, 1e-9, "no blood spent")
	eq(r.trek.senses, 1, "counted")
	eq(int(r.stats["senses"]), 1)
	g.night.blood = 1.0
	_step(g, 8.5)
	g.night.blood = 1.0
	ok(r.try_sense()["ok"], "free even when weak")
	_done(g)


func _into_wood(g: Game, r: RogueMode) -> void:
	_place(g, r.trek.exit_cell)
	ok(r.on_exit_door(), "through the cave mouth")
	g.card_text = g.card_text   # keep the notice for the test that looks at it


func test_sense_costs_blood_after_the_cave_and_needs_a_margin() -> void:
	var g := _game()
	var r := _trek(g)
	_into_wood(g, r)
	eq(r.trek.stage_id, "wood")
	near(r.sense_cost(), 4.0, 1e-9, "4 x 0.9 rounds up to 4")
	g.card_text = ""
	g.night.blood = 50.0
	var res := r.try_sense()
	ok(res["ok"], "affordable")
	near(g.night.blood, 46.0, 1e-9, "4 blood")
	_step(g, 8.5)
	g.night.blood = 8.9   # below cost + 5
	var b0: float = g.night.blood
	var weak := r.try_sense()
	ok(not weak["ok"] and weak["code"] == "weak", "too weak")
	near(g.night.blood, b0, 1e-9, "nothing spent when refused")
	eq(g.card_text, "Too weak to sense")
	g.night.blood = 9.0
	ok(r.try_sense()["ok"], "cost + 5 exactly is enough")
	near(g.night.blood, 5.0, 1e-9)
	# the documented scaling per stage
	for pair in [["wood", 4.0], ["moor", 4.0], ["road", 5.0], ["inn", 5.0]]:
		var row := StageGen.stage_row(String(pair[0]))
		near(ceilf(RogueMode.SENSE_COST_BASE * float(row["drainMul"]) - 0.0001), float(pair[1]), 1e-9, String(pair[0]))
	_done(g)


func test_sense_cooldown() -> void:
	var g := _game()
	var r := _trek(g)
	g.card_text = ""
	ok(r.try_sense()["ok"])
	var again := r.try_sense()
	ok(not again["ok"] and again["code"] == "cooldown", "refused during the cooldown")
	eq(r.trek.senses, 1)
	_step(g, 7.0)
	ok(not r.try_sense()["ok"], "still cooling at 7 s")
	_step(g, 1.2)
	ok(r.try_sense()["ok"], "ready after 8 s")
	eq(r.trek.senses, 2)
	_done(g)


func test_sense_bearing_for_eight_headings() -> void:
	var g := _game()
	var r := _trek(g)
	var f := r.trek
	var c := _far_cell(f, 12)
	var tc := f.next_toward_exit(c, RogueMode.SENSE_AHEAD)
	eq(f.dist_to_exit(tc), f.dist_to_exit(c) - RogueMode.SENSE_AHEAD, "the target is on the way out")
	var pp := Vector2(c.x + 0.5, c.y + 0.5)
	var dir := atan2(tc.y + 0.5 - pp.y, tc.x + 0.5 - pp.x)
	for k in 8:
		var heading := float(k) * PI / 4.0
		_place(g, c, heading)
		var rel := r.sense_bearing()
		ok(rel > -PI - 1e-9 and rel <= PI + 1e-9, "range")
		near(cos(rel + heading - dir), 1.0, 1e-9, "heading %d points at the way out" % k)
		near(sin(rel + heading - dir), 0.0, 1e-9)
	_place(g, c, dir)
	near(r.sense_bearing(), 0.0, 1e-9, "facing the way out: ahead")
	_place(g, c, dir - PI / 2.0)
	near(r.sense_bearing(), PI / 2.0, 1e-9, "way out on the right: +90")
	_place(g, c, dir + PI / 2.0)
	near(r.sense_bearing(), -PI / 2.0, 1e-9, "on the left: -90")
	_place(g, c, dir + PI)
	near(absf(r.sense_bearing()), PI, 1e-9, "behind")
	_done(g)


func test_sense_cue_shows_and_hides_by_timer() -> void:
	var g := _game()
	var r := _trek(g)
	g.card_text = ""
	ok(r.sense_cue().is_empty(), "no cue before")
	ok(r.try_sense()["ok"])
	near(r.sense_t, RogueMode.SENSE_CUE_S, 1e-9)
	_step(g, 0.4)
	var cue := r.sense_cue()
	ok(not cue.is_empty() and float(cue["a"]) > 0.9, "the cue is up")
	_step(g, 1.0)
	ok(not r.sense_cue().is_empty(), "still up at 1.4 s")
	_step(g, 0.8)
	ok(r.sense_cue().is_empty(), "gone after 2 s")
	near(r.sense_t, 0.0, 1e-9)
	_done(g)


func test_sense_swells_the_draft_toward_the_way_out() -> void:
	var g := _game()
	var r := _trek(g)
	g.card_text = ""
	_place(g, _far_cell(r.trek, 30) if _far_cell(r.trek, 30).x >= 0 else _far_cell(r.trek, 14))
	_step(g, 2.0)
	var calm := r._wind_level
	ok(r.try_sense()["ok"])
	var peak := 0.0
	for i in 30:
		g.step(0.05, {})
		peak = maxf(peak, r._wind_level)
	ok(peak > calm + 0.2, "the draft swells (%f -> %f)" % [calm, peak])
	ok(peak <= RogueMode.WIND_CAP + 1e-9, "never past the cap")
	_done(g)


func test_the_v_key_triggers_sense_through_the_game_step() -> void:
	var g := _game()
	var r := _trek(g)
	g.card_text = ""
	g.pressed[KEY_V] = true
	g.step(0.05, {})
	ok(r.sense_t > 0.0, "V exhales")
	eq(r.trek.senses, 1)
	_done(g)


func test_hints_per_stage() -> void:
	var g := _game()
	var r := _trek(g)
	eq(r.sense_hint(), "V sense (free)", "Hollow")
	_into_wood(g, r)
	eq(r.sense_hint(), "V sense (-4 blood)", "after the cave")
	_done(g)


func test_the_cost_notice_shows_once() -> void:
	var g := _game()
	var r := _trek(g)
	ok(not r.sense_notice_shown, "not in the Hollow")
	_into_wood(g, r)
	eq(g.card_text, "The cold air")
	eq(g.card_sub, "Beyond the cave, sensing costs blood.")
	ok(r.sense_notice_shown)
	g.card_text = ""
	r._enter_descriptor(r.trek.descriptor)   # entering again (continue / next stage) does not repeat it
	eq(g.card_text, "", "one time only")
	_done(g)


func test_frozen_input_blocks_sense() -> void:
	var g := _game()
	var r := _trek(g)
	g.card_text = ""
	r.prompt_open = true
	var res := r.try_sense()
	ok(not res["ok"] and res["code"] == "frozen", "the day prompt freezes it")
	g.pressed[KEY_V] = true
	g.step(0.05, {})
	eq(r.trek.senses, 0, "the key does nothing while frozen")
	eq(r.sense_t, 0.0)
	r.prompt_open = false
	r.waiting = true
	eq(r.try_sense()["code"], "frozen", "nor while waiting out the day")
	r.waiting = false
	_done(g)


func test_classic_mode_is_unaffected() -> void:
	var g := _game()
	ok(not g.rogue.active, "no trek")
	eq(g.rogue.sense_hint(), "", "no hint in classic")
	var res := g.rogue.try_sense()
	ok(not res["ok"] and res["code"] == "off", "Sense is off in classic")
	_done(g)


func test_senses_are_saved_additively() -> void:
	var g := _game()
	var r := _trek(g)
	r.trek.senses = 3
	var snap := r.trek.snapshot()
	eq(int(snap["night"]["trek"]["senses"]), 3, "in the trek extension")
	var back := TrekFlow.continue_from(snap, r._meta(), null)
	ok(back != null, "loads")
	eq(back.senses, 3)
	var old := r.trek.snapshot()
	(old["night"]["trek"] as Dictionary).erase("senses")
	var back2 := TrekFlow.continue_from(old, r._meta(), null)
	ok(back2 != null and back2.senses == 0, "an older save without the key loads with 0")
	_done(g)


# ---------------------------------------------------------------- 0.21.7 discoverability

func test_sense_intro_follows_the_ping_and_rings_steps() -> void:
	var ids: Array = []
	for s in Tutorial.ROGUE_STEPS:
		ids.append(s["id"])
	var i: int = ids.find("sense_intro")
	ok(i > ids.find("rings") and i < ids.find("drips"), "intro sits after the rings and before the drip gallery: %s" % str(ids))
	ok(ids.find("sense") > i, "the lost reminder stays")
	ok(not bool(Tutorial.new(null, false).step_def("sense_intro").get("interrupt", false)), "the intro never jumps the queue")
	ok(String(Tutorial.new(null, false).step_def("sense_intro")["text"]).begins_with("V: sense the way. Free in the cave"))


func test_sense_intro_shows_once_after_the_ping_step() -> void:
	var g := _game()
	var r := _trek(g)
	g.card_text = ""
	_step(g, 6.0)
	eq(g.tut.rogue_cur, "ping")
	g.tut.rogue_done["ping"] = true
	g.tut.rogue_cur = ""
	_step(g, 0.2)
	eq(g.tut.rogue_cur, "rings")
	_step(g, 6.0)
	eq(g.tut.rogue_cur, "sense_intro", "after the rings: V")
	ok(g.hint_text.begins_with("V: sense the way."), g.hint_text)
	ok(g.hint_text.find("Tab: skip") > 0, "still skippable")
	_step(g, 7.0)
	ok(g.tut.rogue_done.has("sense_intro"))
	ok(g.tut.rogue_cur != "sense_intro", "shown once")
	_done(g)


func test_sense_intro_is_skipped_when_already_sensed_or_resumed() -> void:
	var g := _game()
	var r := _trek(g)
	g.card_text = ""
	g.pressed[KEY_V] = true
	g.step(0.05, {})
	eq(r.trek.senses, 1)
	g.tut.rogue_done["wake"] = true
	g.tut.rogue_done["ping"] = true
	g.tut.rogue_done["rings"] = true
	g.tut.rogue_cur = ""
	_step(g, 0.5)
	ok(g.tut.rogue_cur != "sense_intro", "no lesson for someone who found V")
	ok(g.tut.rogue_done.has("sense_intro"), "marked done")
	_step(g, 40.0)
	ok(not g.tut.rogue_done.has("sense") or g.tut.rogue_cur != "sense", "no reminder either once sensed")
	_done(g)


func test_hint_is_bright_and_pulses_early_then_rests() -> void:
	var g := _game()
	var r := _trek(g)
	var l0: Dictionary = r.sense_hint_look()
	ok(float(l0["bright"]) >= 1.0, "bright at the start")
	_step(g, 2.0)
	ok(float(r.sense_hint_look()["pulse"]) > 0.0, "pulsing in the first seconds")
	_step(g, 7.0)
	eq(float(r.sense_hint_look()["pulse"]), 0.0, "no pulse after about 8 s")
	ok(float(r.sense_hint_look()["bright"]) >= 1.0, "still bright at 9 s")
	_step(g, 56.0)
	eq(float(r.sense_hint_look()["bright"]), 0.0, "dim after a minute")
	_done(g)


func test_hint_goes_dim_once_sense_is_used() -> void:
	var g := _game()
	var r := _trek(g)
	ok(float(r.sense_hint_look()["bright"]) >= 1.0)
	g.pressed[KEY_V] = true
	g.step(0.05, {})
	eq(float(r.sense_hint_look()["bright"]), 0.0, "used once: dim")
	eq(float(r.sense_hint_look()["pulse"]), 0.0)
	_done(g)


func test_hint_after_the_cave_names_the_blood_cost() -> void:
	var g := _game()
	var r := _trek(g)
	_into_wood(g, r)
	ok(r.sense_hint().begins_with("V sense (-"), r.sense_hint())
	ok(r.sense_hint().ends_with("blood)"))
	_done(g)


func test_how_to_play_and_pause_list_sense_and_the_powers() -> void:
	var g := _game()
	g.menus.sync(g)
	g.menus._view = "guide"
	g.set_state("title")
	g.menus.sync(g)
	var t := ""
	for n in g.menus.find_children("*", "Label", true, false):
		t += (n as Label).text + "\n"
	ok(t.find("V - Sense the way (free in the cave, costs blood beyond)") >= 0, "guide lists V: " + t.substr(0, 400))
	ok(t.find("R - Lunge") >= 0, "guide lists R")
	ok(t.find("Q shriek, Shift or C mist, F still") >= 0, "guide lists the powers")
	_done(g)
