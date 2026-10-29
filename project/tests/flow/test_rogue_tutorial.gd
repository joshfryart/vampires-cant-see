extends TestCase
## The guided first night of The Long Night (game/tutorial.gd Tutorial.rogue_*): step 1 on the first run, steps gated on pings, beats and
## feeding, Tab skips and persists, a second run shows nothing, the Settings toggle replays, resume by beats reached, the day prompt,
## the one-time Laid to Rest explanation, old saves without `tutorialDone`, and that the sim and classic mode are untouched.

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


func _cur(g: Game) -> String:
	return g.tut.rogue_cur


func _beat(r: RogueMode, id: String) -> Vector2:
	for b in r.trek.def["beats"]:
		if b["id"] == id:
			return Vector2(float(b["cell"][0]) + 0.5, float(b["cell"][1]) + 0.5)
	return Vector2(NAN, NAN)


func _go(g: Game, r: RogueMode, id: String) -> void:
	var p := _beat(r, id)
	g.player.place(p.x, p.y, 0.0)


## Ping through the real path once the cooldown allows it.
func _ping(g: Game) -> void:
	_step(g, 1.0)
	ok(g.pulse(), "the player pings")
	_step(g, 0.1)


func _texts(root: Node) -> String:
	var out := ""
	for n in root.find_children("*", "Label", true, false):
		out += (n as Label).text + "\n"
	return out


func test_first_run_shows_step_one() -> void:
	var g := _game()
	ok(g.menus.tutorial_enabled(), "a fresh save has the tutorial on")
	var r := _trek(g)
	ok(g.tut.rogue_active, "guided night on")
	_step(g, 0.3)
	eq(_cur(g), "wake", "step 1: waking")
	eq(g.hint_text, "", "the stage card has the screen to itself first (0.21.9)")
	_step(g, Tutorial.OPEN_HOLD)
	ok(g.hint_text.find("The lid creaks. So do your knees. You cannot see. Listen.") == 0, "the waking line: " + g.hint_text)
	ok(g.hint_text.find("Tab: skip") > 0, "the skip hint is on the line")
	ok(r.active, "trek active")
	_done(g)


func test_texts_fit_one_hud_line() -> void:
	for s in Tutorial.ROGUE_STEPS:
		var t: String = String(s["text"])
		ok(t.length() <= Tutorial.MAX_TEXT, "%s fits (%d)" % [s["id"], t.length()])
		ok((t + Tutorial.SKIP_SUFFIX).length() <= 90, "%s plus skip fits the hint line" % s["id"])


func test_gating_follows_the_player() -> void:
	var g := _game()
	var r := _trek(g)
	# 1 waking waits for the first drip (about 1.5 s)
	_step(g, 6.0)
	ok(r.stats["drips"] > 0, "a drip was heard")
	eq(_cur(g), "ping", "2: after the drip, the ping prompt")
	_step(g, 4.0)
	eq(_cur(g), "ping", "the ping prompt waits for the ping, not the clock")
	ok(g.hint_text.find("Click or Space to ping") == 0, "it names both ways to ping: " + g.hint_text)
	_ping(g)
	eq(_cur(g), "rings", "a ping advances to what the rings mean")
	_step(g, 6.0)
	eq(_cur(g), "sense_intro", "the V line right after the rings")
	_step(g, 7.0)
	eq(_cur(g), "drips", "3: drips and passive hearing")
	_go(g, r, "drip_gallery")
	_step(g, 0.3)
	eq(_cur(g), "squeeze", "reaching the drip gallery advances to the squeeze")
	_go(g, r, "squeeze")
	_step(g, 0.2)
	eq(_cur(g), "squeeze", "being at the squeeze is not enough: ping to steer")
	_ping(g)
	ok(g.tut.rogue_done.has("squeeze"), "pinging at the squeeze completes it")
	_go(g, r, "echo_hall")
	_step(g, 0.3)
	eq(_cur(g), "hall", "5: the echo hall")
	ok(g.hint_text.find("bats") >= 0, "bats are food")
	_step(g, 6.0)
	eq(_cur(g), "feed", "first feed objective")
	ok(g.hint_text.find("R to lunge") >= 0, "creep, ping, R")
	# feed a critter for real
	var c: Critters.Critter = r.critters.critters[0]
	g.player.place(c.x - 0.9, c.y, 0.0)
	if g.world.blocks(c.x - 0.9, c.y, 0.2):
		g.player.place(c.x + 0.9, c.y, PI)
	g.night.blood = 30.0
	ok(r.try_feed_critter(), "fed a critter")
	g.card_text = ""
	_step(g, 0.3)
	g.card_text = ""
	_step(g, 0.2)
	eq(_cur(g), "vial", "feeding advances to the blood meter explanation")
	_step(g, 7.0)
	eq(_cur(g), "pool", "6: pool")
	_go(g, r, "still_pool")
	_ping(g)
	ok(g.tut.rogue_done.has("pool"), "pinging by the pool completes it")
	_go(g, r, "cave_mouth")
	_step(g, 0.5)
	eq(_cur(g), "mouth", "9: the cave mouth, the sun")
	ok(g.hint_text.find("Outside, the sun can find you") == 0, "sun line")
	_done(g)


func test_dead_end_step() -> void:
	var g := _game()
	var r := _trek(g)
	_step(g, 6.0)
	_ping(g)
	_step(g, 6.0)
	_go(g, r, "still_pool")
	_step(g, 0.3)
	_ping(g)   # the pool step ends on a ping beside the water; in the compact Hollow the spur no longer lies deeper than the warren, so it cannot skip it
	_go(g, r, "dead_end_spurs")
	_step(g, 0.5)
	eq(_cur(g), "dead_end", "7: a dead end rings short and bright")
	_done(g)


func test_skip_completes_and_persists() -> void:
	var g := _game()
	_trek(g)
	_step(g, Tutorial.OPEN_HOLD + 0.5)
	ok(g.hint_text != "", "step 1 showing")
	var px := g.player.x
	g.pressed[Tutorial.SKIP_KEY] = true
	g.step(0.05, {})
	ok(not g.tut.rogue_active, "Tab stops the tutorial")
	eq(g.hint_text, "", "the line is gone")
	ok(not g.menus.tutorial_enabled(), "marked done")
	var r: Dictionary = g.flow.store.read("rogue")
	ok(r["ok"], "rogue save written")
	eq(r["data"]["tutorialDone"], true, "persisted in the rogue slot")
	near(g.player.x, px, 0.2, "skipping moved nobody")
	_step(g, 1.0)
	eq(g.hint_text, "", "nothing comes back")
	# a second new run shows none
	g.set_state("title")
	g.rogue.new_trek(SEED + 1)
	ok(not g.tut.rogue_active, "second new run: no tutorial")
	_step(g, 2.0)
	eq(g.hint_text.find("Tab: skip"), -1, "no guided line on the second run")
	_done(g)


func test_toggle_in_settings_replays() -> void:
	var g := _game()
	_trek(g)
	g.pressed[Tutorial.SKIP_KEY] = true
	g.step(0.05, {})
	ok(not g.menus.tutorial_enabled(), "done after skip")
	g.set_state("title")
	g.menus._view = "settings"
	g.menus.sync(g)
	var cb: Variant = g.menus.find_child("TutorialToggle", true, false)
	ok(cb is CheckBox, "settings have the tutorial toggle")
	if cb is CheckBox:
		ok(not (cb as CheckBox).button_pressed, "toggle reads Off after completion")
		eq((cb as CheckBox).text, "Off", "labelled Off")
		(cb as CheckBox).button_pressed = true
		ok(g.menus.tutorial_enabled(), "turning it On clears the flag")
		eq((cb as CheckBox).text, "On", "labelled On")
		var saved: Dictionary = g.flow.store.read("rogue")
		eq(saved["data"]["tutorialDone"], false, "persisted")
	g.menus._view = "main"
	g.rogue.new_trek(SEED + 2)
	ok(g.tut.rogue_active, "the next new run replays the tutorial")
	_step(g, 0.3)
	eq(_cur(g), "wake", "from step 1")
	# turning it Off mid-run stops the live tutorial
	g.menus.set_tutorial_enabled(false)
	ok(not g.tut.rogue_active, "Off stops it now")
	eq(g.hint_text, "", "line cleared")
	_done(g)


func test_resume_by_beats_reached() -> void:
	var g := _game()
	var r := _trek(g)
	_go(g, r, "still_pool")
	g.tut.rogue_begin(false)   # what continue_trek does: not a fresh run
	_step(g, 0.3)
	eq(_cur(g), "pool", "resumed at the pool step")
	ok(g.tut.rogue_done.has("wake") and g.tut.rogue_done.has("ping"), "earlier steps are done")
	ok(g.tut.rogue_done.has("squeeze") and g.tut.rogue_done.has("feed"), "steps behind the player are skipped")
	# and the real continue path starts at the checkpoint: past the waking, on the drips
	g.set_state("title")
	g.menus.trek_continue_requested.emit()
	ok(g.tut.rogue_active, "continued run still guided")
	_step(g, 0.3)
	eq(_cur(g), "drips", "continue: waking and ping are behind, drips next")
	_done(g)


func test_day_prompt_steps() -> void:
	var g := _game()
	var r := _trek(g)
	var rc: Array = r.trek.def["rest"][0]["cell"]
	g.player.place(float(rc[0]) + 0.5, float(rc[1]) + 0.5, 0.0)
	g.night.skip_to(5, 0)
	_step(g, 4.0)
	eq(_cur(g), "dawn", "dawn interrupts the queue")
	ok(g.hint_text.find("roof") >= 0, "any roof is safe")
	g.night.skip_to(5, 59)
	_step(g, 2.0)
	ok(r.prompt_open, "day prompt open")
	eq(_cur(g), "choice", "sleep vs wait explained over the prompt")
	g.card_text = ""   # the "sun is up" card hides the line while it is up
	_step(g, 0.1)
	ok(g.hint_text.find("1 waits") >= 0, "names 1")
	# input is frozen by the prompt; the tutorial neither adds nor removes that
	var pp := Vector2(g.player.x, g.player.y)
	_step(g, 0.5, {"forward": 1.0})
	near(g.player.x, pp.x, 1e-9, "still frozen")
	near(g.player.y, pp.y, 1e-9, "still frozen")
	_done(g)


func test_death_explains_soil_once_and_finishes() -> void:
	var g := _game()
	var r := _trek(g)
	g.night.blood = 0.0
	_step(g, 27.0, {}, 0.1)
	eq(g.state, "playing", "the guided night forgives the first withering (0.21.9)")
	g.night.blood = 0.0
	_step(g, 27.0, {}, 0.1)
	eq(g.state, "runend", "ended")
	eq(r.last_result.get("tutorial"), true, "the result carries the tutorial flag")
	ok(_texts(g.menus).find("Grave Soil is what") >= 0, "Grave Soil explained: " + _texts(g.menus))
	ok(_texts(g.menus).find("The Coffin spends it") >= 0, "The Coffin explained")
	ok(not g.menus.tutorial_enabled(), "the run end completes the tutorial")
	g.menus.rise_again_requested.emit()
	ok(not g.tut.rogue_active, "no tutorial on the next run")
	g.night.blood = 0.0
	_step(g, 27.0, {}, 0.1)
	ok(r.last_result.get("tutorial") != true, "the explanation is shown the first time only")
	eq(_texts(g.menus).find("Grave Soil is what"), -1, "not again")
	_done(g)


func test_skipped_run_gets_no_death_explanation() -> void:
	var g := _game()
	var r := _trek(g)
	g.pressed[Tutorial.SKIP_KEY] = true
	g.step(0.05, {})
	g.night.blood = 0.0
	_step(g, 27.0, {}, 0.1)
	eq(g.state, "runend", "ended")
	ok(r.last_result.get("tutorial") != true, "skipped: no explanation")
	_done(g)


func test_old_save_without_the_flag() -> void:
	var old := TrekMeta.create()
	old.erase("tutorialDone")
	ok(SaveCodec.sanitize_rogue(old) != null, "the codec accepts the v1 save without the flag")
	ok(SaveCodec.validate_rogue(old)["ok"], "validate_rogue too")
	var fresh: Dictionary = TrekMeta.sanitize(old)
	eq(fresh["tutorialDone"], false, "never trekked: the tutorial is still to come")
	var played := old.duplicate(true)
	played["stats"]["treks"] = 3
	eq(TrekMeta.sanitize(played)["tutorialDone"], true, "a veteran save counts as done")
	var with_flag := TrekMeta.create()
	with_flag["tutorialDone"] = true
	ok(SaveCodec.sanitize_rogue(with_flag) != null, "flag accepted")
	eq(SaveCodec.sanitize_rogue(with_flag)["tutorialDone"], true, "flag kept")
	with_flag["tutorialDone"] = "yes"
	eq(SaveCodec.sanitize_rogue(with_flag), null, "a non-bool flag is refused by the codec")
	eq(TrekMeta.sanitize(with_flag)["tutorialDone"], false, "TrekMeta repairs a non-bool flag")
	var extra := TrekMeta.create()
	extra["bonus"] = 1
	eq(SaveCodec.sanitize_rogue(extra), null, "other extra keys are still refused")
	var missing := TrekMeta.create()
	missing.erase("legacyImported")
	eq(SaveCodec.sanitize_rogue(missing), null, "required keys are still required")
	# through the store into a booted game
	Game.test_storage = SaveCodec.MemoryStorage.new()
	Game.manual_boot = true
	var g := Game.new()
	g.boot()
	var w: Dictionary = g.flow.store.write("rogue", 1, old)
	ok(w["ok"], "an old-shaped save writes")
	g.menus.trek_meta = {}
	ok(g.menus.tutorial_enabled(), "loaded: tutorial on")
	ok(g.menus.trek_meta.has("tutorialDone"), "migrated: the flag is there")
	g.free()
	GameData.clear_generated()


func test_classic_unaffected() -> void:
	var g := _game()
	g.flow.seed_param = 5
	ok(g.flow.begin_run(), "classic run begins")
	ok(not g.rogue_on(), "rogue off")
	ok(not g.tut.rogue_active, "no guided night in classic")
	_step(g, 2.0)
	ok(g.hint_text.find("Tab: skip") < 0, "classic hints are the legacy ones: " + g.hint_text)
	g.pressed[Tutorial.SKIP_KEY] = true
	g.step(0.05, {})
	ok(g.menus.tutorial_enabled(), "Tab in classic does not touch the rogue flag")
	_done(g)


func test_tutorial_does_not_touch_the_sim() -> void:
	# the tutorial flag also picks the Hollow layout (repeat runs get the brief cave), so both treks start on the first-run layout and the
	# guided night is then turned off for one of them: what is compared is the hints, not the map
	var out: Array = []
	for on in [true, false]:
		var g := _game()
		_trek(g)
		if not on:
			g.menus._tm()["tutorialDone"] = true
			g.tut.rogue_begin(true)
		ok(not g.rogue.trek.brief, "first-run layout in both")
		_step(g, 6.0, {"forward": 1.0})
		g.ping_clicks = 1
		_step(g, 3.0, {"forward": 1.0, "turn": 0.4})
		out.append([g.player.x, g.player.y, g.player.angle, g.night.blood, g.sonar.pulses.size(), g.rogue.critters.critters.size()])
		eq(g.tut.rogue_active, on, "tutorial %s" % on)
		_done(g)
	eq(out[0], out[1], "same player, blood, pulses and critters with the tutorial on or off")


# ---------------------------------------------------------------- 0.21.8 opening and ping step

func test_a_ping_during_the_waking_line_counts() -> void:
	var g := _game()
	var r := _trek(g)
	_step(g, 0.3)
	eq(_cur(g), "wake", "waking line up")
	_ping(g)   # the player pings before being asked to
	_step(g, 6.0)
	ok(r.stats["drips"] > 0, "a drip was heard")
	ok(g.tut.rogue_done.has("ping"), "the ping step is already done")
	ok(_cur(g) == "rings" or _cur(g) == "sense_intro", "on to what the rings mean, not stuck on the ping prompt: " + _cur(g))
	ok(g.hint_text.find("to ping") < 0, "the ping prompt is not up: " + g.hint_text)
	_done(g)


func test_a_ping_before_the_step_still_needs_one_when_none_was_made() -> void:
	var g := _game()
	_trek(g)
	_step(g, 6.0)
	eq(_cur(g), "ping", "no ping yet: the prompt shows")
	_step(g, 3.0)
	eq(_cur(g), "ping", "and waits")
	_done(g)


func test_ping_text_names_click_and_space() -> void:
	var t: String = String(Tutorial.new(null, false).step_def("ping")["text"])
	ok(t.begins_with("Click or Space"), t)
	ok(t.length() <= Tutorial.MAX_TEXT, "fits")
	ok(String(Tutorial.new(null, false).step_def("wake")["text"]).find("You cannot see") > 0, "the waking line keeps the premise")


func test_brief_cave_on_repeat_runs_only() -> void:
	var g := _game()
	_trek(g)
	ok(not g.rogue.trek.brief, "first run: the full Hollow")
	ok(not g.rogue.trek.def["gen"].has("brief"), "first-run def has no brief key")
	g.pressed[Tutorial.SKIP_KEY] = true
	g.step(0.05, {})
	ok(not g.menus.tutorial_enabled(), "tutorial done")
	ok(not g.rogue.trek.brief, "skipping mid-run keeps this trek's layout")
	var snap: Dictionary = g.rogue.trek.snapshot()
	ok(not (snap["night"]["trek"] as Dictionary).has("brief"), "a first-run checkpoint carries no brief key")
	g.set_state("title")
	g.rogue.new_trek(SEED + 1)
	ok(g.rogue.trek.brief, "next trek: the brief Hollow")
	eq(g.rogue.trek.def["gen"].get("brief"), true, "the def says so")
	eq(int(g.rogue.trek.def["gen"]["fillers"]), 0, "no filler chambers")
	var pure := StageGen.generate("hollow", TrekFlow.stage_seed(SEED + 1, 0), true)
	eq(g.rogue.trek.def["rows"], pure["rows"], "the same pure function the generator gives")
	eq(g.rogue.trek.def["beats"], pure["beats"], "same beats")
	var snap2: Dictionary = g.rogue.trek.snapshot()
	eq(snap2["night"]["trek"]["brief"], true, "saved with the checkpoint")
	# a continue regenerates the same brief layout even after the tutorial is turned back on
	g.set_state("title")
	g.menus.set_tutorial_enabled(true)
	ok(g.rogue.continue_trek(), "continued")
	ok(g.rogue.trek.brief, "still brief")
	eq(g.rogue.trek.def["rows"], StageGen.generate("hollow", TrekFlow.stage_seed(SEED + 1, 0), true)["rows"], "same rows after continue")
	# and a save without the key (every save before 0.21.8) loads the full layout it was made with
	(snap2["night"]["trek"] as Dictionary).erase("brief")
	var old := TrekFlow.continue_from(snap2, g.rogue._meta(), null)
	ok(old != null and not old.brief, "old save: full layout")
	_done(g)


# ---------------------------------------------------------------- 0.21.8 quirks (cards only)

func test_echo_hall_says_a_word_once_on_the_guided_night() -> void:
	var g := _game()
	var r := _trek(g)
	_go(g, r, "echo_hall")
	g.card_text = ""
	_ping(g)
	eq(g.card_text, RogueMode.ECHO_WORD, "the hall answers")
	eq(g.card_sub, RogueMode.ECHO_WORD_SUB)
	ok(RogueMode.ECHO_WORD_SUB.length() <= 60, "short")
	g.card_text = ""
	_ping(g)
	eq(g.card_text, "", "only once")
	_done(g)
	# off the hall: nothing
	var g2 := _game()
	_trek(g2)
	g2.card_text = ""
	_ping(g2)
	ok(g2.card_text != RogueMode.ECHO_WORD, "not at the coffin")
	_done(g2)
	# a repeat run (no guided night): no card in the hall
	var g3 := _game()
	g3.menus._tm()["tutorialDone"] = true
	var r3 := _trek(g3)
	_go(g3, r3, "echo_hall")
	g3.card_text = ""
	_ping(g3)
	eq(g3.card_text, "", "repeat runs stay quiet")
	_done(g3)


func test_the_first_rat_complains() -> void:
	var g := _game()
	var r := _trek(g)
	var subs: Array = []
	for c in r.critters.critters.duplicate():
		if c.species != "rat" or subs.size() >= 2:
			continue
		g.player.place(c.x - 0.9, c.y, 0.0)
		if g.world.blocks(c.x - 0.9, c.y, 0.2):
			g.player.place(c.x + 0.9, c.y, PI)
		g.night.blood = 30.0
		var before: int = int(r.stats["critters_fed"])
		if r.try_feed_critter() and int(r.stats["critters_fed"]) == before + 1 and g.card_sub.begins_with("Rat"):
			subs.append(g.card_sub)
		g.card_text = ""
	eq(subs.size(), 2, "two rats fed")
	if subs.size() == 2:
		eq(subs[0], RogueMode.RAT_QUIP, "the first one complains")
		eq(subs[1], "Rat", "the rest just are rats")
	_done(g)


# ---------------------------------------------------------------- 0.21.9 opening order and the free revive

func test_opening_holds_the_line_for_the_stage_card() -> void:
	var g := _game()
	var r := _trek(g)
	_step(g, 0.3)
	ok(g.menus.trek_ui.stage_card_visible(), "the stage card is up")
	ok(g.tut.opening_held(), "the guided line is held")
	eq(g.hint_text, "", "no line under the card")
	_step(g, Tutorial.OPEN_HOLD - 0.6)
	eq(g.hint_text, "", "still held just before the card fades")
	_step(g, 0.6)
	ok(not g.tut.opening_held(), "hold over")
	ok(g.hint_text.find("The lid creaks") == 0, "then the waking line: " + g.hint_text)
	ok(r.stats["drips"] > 0, "a drip came during the hold")
	_step(g, 1.5)
	eq(_cur(g), "wake", "the waking line still gets its own minimum on screen after the hold")
	_step(g, 1.5)
	eq(_cur(g), "ping", "then the ping prompt")
	# a continued run holds its first line as well (its stage card shows too)
	g.set_state("title")
	g.menus.trek_continue_requested.emit()
	ok(g.tut.rogue_active, "continued, guided")
	_step(g, 0.3)
	eq(g.hint_text, "", "held on continue")
	_step(g, Tutorial.OPEN_HOLD)
	ok(g.hint_text.find("Tab: skip") > 0, "then the line: " + g.hint_text)
	_done(g)


func test_guided_night_forgives_the_first_withering() -> void:
	var g := _game()
	var r := _trek(g)
	_step(g, 1.0, {"forward": 1.0})
	var rest: Vector2i = r.trek.last_rest
	g.night.blood = 0.0
	_step(g, 27.0, {}, 0.1)
	eq(g.state, "playing", "alive")
	ok(r.trek.guided_revived, "the free revive is spent")
	eq(r.trek.deaths_avoided, 0, "no Second Coffin used")
	eq(g.card_text, RogueMode.GUIDED_REVIVE_TITLE, "the card")
	eq(g.card_sub, RogueMode.GUIDED_REVIVE_SUB)
	ok(RogueMode.GUIDED_REVIVE_SUB.length() <= Tutorial.MAX_TEXT and RogueMode.GUIDED_REVIVE_TITLE.length() <= Tutorial.MAX_TEXT, "short lines")
	near(g.player.x, rest.x + 0.5, 0.6, "back at the last rest spot (x)")
	near(g.player.y, rest.y + 0.5, 0.6, "back at the last rest spot (y)")
	ok(g.night.blood > 25.0, "second-coffin blood (%.1f)" % g.night.blood)
	ok(g.tut.rogue_active, "still the guided night")
	eq(int(g.menus.trek_meta["stats"]["treks"]), 0, "no run recorded")
	eq(int(g.menus.trek_meta["soil"]), 0, "no Soil")
	# quit and continue: still spent
	g.set_state("title")
	ok(g.rogue.continue_trek(), "continued")
	ok(g.rogue.trek.guided_revived, "restored as spent")
	g.night.blood = 0.0
	_step(g, 27.0, {}, 0.1)
	eq(g.state, "runend", "the second withering ends the run")
	eq(int(g.menus.trek_meta["stats"]["deaths"]["withered"]), 1, "one death")
	_done(g)


func test_no_free_revive_once_the_guided_night_is_skipped() -> void:
	var g := _game()
	var r := _trek(g)
	g.pressed[Tutorial.SKIP_KEY] = true
	g.step(0.05, {})
	ok(not g.tut.rogue_active, "skipped")
	g.night.blood = 0.0
	_step(g, 27.0, {}, 0.1)
	eq(g.state, "runend", "Tab-skipped: withering is death")
	ok(not r.trek.guided_revived, "nothing spent")
	_done(g)
