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
	ok(g.hint_text.find("You rise. You cannot see. Listen.") == 0, "the waking line: " + g.hint_text)
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
	ok(g.hint_text.find("Space") >= 0, "it names Space")
	_ping(g)
	eq(_cur(g), "rings", "a ping advances to what the rings mean")
	_step(g, 6.0)
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
	_go(g, r, "dead_end_spurs")
	_step(g, 0.5)
	eq(_cur(g), "dead_end", "7: a dead end rings short and bright")
	_done(g)


func test_skip_completes_and_persists() -> void:
	var g := _game()
	_trek(g)
	_step(g, 0.5)
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
	var out: Array = []
	for on in [true, false]:
		var g := _game()
		g.menus._tm()["tutorialDone"] = not on
		_trek(g)
		_step(g, 6.0, {"forward": 1.0})
		g.ping_clicks = 1
		_step(g, 3.0, {"forward": 1.0, "turn": 0.4})
		out.append([g.player.x, g.player.y, g.player.angle, g.night.blood, g.sonar.pulses.size(), g.rogue.critters.critters.size()])
		eq(g.tut.rogue_active, on, "tutorial %s" % on)
		_done(g)
	eq(out[0], out[1], "same player, blood, pulses and critters with the tutorial on or off")
