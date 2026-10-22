extends TestCase
## Gaps found by the JS-parity audit of game.gd / run_flow.gd: sonar cooldown effects, feedToggle release, saved gift offers,
## enter_map resets, gate interaction, denied sleep, the save-failure notice, the transition length and inputs not leaking.


func _game() -> Game:
	Game.test_storage = SaveCodec.MemoryStorage.new()
	Game.manual_boot = true
	var g := Game.new()
	g.boot()
	g.flow.seed_param = 5
	g.flow.begin_run()
	return g


func _step(g: Game, seconds: float, inp: Dictionary = {}, dt: float = 0.05) -> void:
	for i in int(round(seconds / dt)):
		g.step(dt, inp)


func _near_villager(g: Game) -> People.Person:
	for p in g.people.people:
		if p.mode == "path" and p.feedable and not p.sit:
			var a: float = p.angle + PI
			var px: float = p.x + cos(a) * 0.8
			var py: float = p.y + sin(a) * 0.8
			if not g.world.blocks(px, py, 0.2):
				g.player.place(px, py, atan2(p.y - py, p.x - px))
				return p
	return null


func test_sonar_cooldown_fx() -> void:
	var g := _game()
	var base: float = float(g.cfg["sonarCooldown"])
	near(g.sonar.cooldown, base, 1e-9, "base cooldown")
	ok(g.hunger.take_gift("g_quick")["ok"], "gift taken")
	g.flow.apply_fx()
	near(g.sonar.cooldown, base * 0.95, 1e-9, "g_quick applied")
	ok(g.sonar.cooldown < base - 1e-6, "gift shortens the cooldown")
	g.free()


func test_feed_toggle_release() -> void:
	var g := _game()
	g.debug_map("town")
	_step(g, 1.0)
	var v := _near_villager(g)
	ok(v != null, "villager to feed on")
	if v == null:
		g.free()
		return
	g.feed_toggle = true
	g.player_lit = 0.0
	ok(g.start_drink(false), "unforced drink starts")
	_step(g, 0.2)
	ok(g.drink != null, "toggle mode keeps drinking without the key held")
	g.feed_press = 1
	g.step(0.05, {})
	ok(g.drink == null, "second press ends the drink")
	eq(g.state, "playing", "back to playing")
	g.free()


func test_pending_gifts_round_trip() -> void:
	var g := _game()
	var ids: Array = g.hunger.roll_gifts(3.0)
	ok(ids.size() > 0, "gifts rolled")
	g.flow.run["pendingGifts"] = ids
	g.set_state("gift")
	ok(g.flow.save_run("test"), "gift offer saved")
	var snap: Dictionary = g.flow.get_snapshot()
	eq(snap["run"]["pendingGifts"], ids, "snapshot carries the offer")
	g.run_on = false
	g.set_state("title")
	g.flow.run = null
	ok(g.flow.continue_run(), "continue works")
	eq(g.state, "gift", "gift panel reopens")
	eq(g.flow.run["pendingGifts"], ids, "same offer after continue")
	ok(g.flow.pick_gift(0), "gift can be taken")
	eq(g.state, "playing", "playing after the pick")
	g.free()


func test_enter_map_resets() -> void:
	var g := _game()
	g.hud_a = 0.7
	g.bob_amp = 0.5
	g.landings.append(5.0)
	g.powers.rocks.append({"x": 1.0, "y": 1.0, "at": 9.0})
	g.lis_px = 3.0
	g.lis_py = 3.0
	g.lis_speed = 2.0
	g.bark_sub = {"de": "x", "en": "y", "muffled": false, "speaker": 1, "dist": 1.0, "start": 0.0, "end": 9.0}
	g.enter_map(g.map_name, g.player.x, g.player.y, g.player.angle, "")
	near(g.hud_a, 0.0, 1e-9, "hud_a")
	near(g.bob_amp, 0.0, 1e-9, "bob_amp")
	eq(g.landings.size(), 0, "landings cleared")
	eq(g.powers.rocks.size(), 0, "rocks cleared")
	ok(is_nan(g.lis_px) and is_nan(g.lis_py), "listen position reset")
	near(g.lis_speed, 0.0, 1e-9, "listen speed reset")
	ok(g.bark_sub == null and g.bark_spk.is_empty(), "barks ended")
	g.free()


func test_gate_interact() -> void:
	var g := _game()
	g.debug_map("town")
	var gate := Vector2i(-1, -1)
	for y in g.world.height:
		for x in g.world.width:
			if g.world.tile_at(x + 0.5, y + 0.5) == "G":
				gate = Vector2i(x, y)
	ok(gate.x >= 0, "town has a gate")
	if gate.x < 0:
		g.free()
		return
	var placed := false
	for o in [Vector2(0.5, -0.5), Vector2(0.5, 1.5), Vector2(-0.5, 0.5), Vector2(1.5, 0.5)]:
		var px: float = gate.x + o.x
		var py: float = gate.y + o.y
		if not g.world.blocks(px, py, g.player.radius):
			g.player.place(px, py, atan2(gate.y + 0.5 - py, gate.x + 0.5 - px))
			placed = true
			break
	ok(placed, "free cell beside the gate")
	ok(not g.world.is_door_open(gate.x, gate.y), "gate starts closed")
	eq(g.interact(), "door", "E on a gate toggles it")
	ok(g.world.is_door_open(gate.x, gate.y), "gate open")
	g.free()


func test_denied_sleep_is_blocked() -> void:
	var g := _game()
	var spots: Array = g.world.spots.get("crypt", [])
	if spots.is_empty():
		g.debug_map("crypt")
		spots = g.world.spots["crypt"]
	var sp: Variant = spots[0]
	g.player.place(sp.x, sp.y, 0.0)
	g.night.skip_to(1, 0)
	var pulses := g.sonar.pulses.size()
	eq(g.interact(), "blocked", "too early: blocked, no interact pulse")
	ok(g.flow.sleep_denied, "sleep_denied set")
	eq(g.sonar.pulses.size(), pulses, "no interact pulse emitted")
	g.free()


func test_save_failure_notice_once() -> void:
	var g := _game()
	var n0: int = g.flow.notices.size()
	g.flow._store_fail("E_TEST")
	g.flow._store_fail("E_TEST")
	eq(g.flow.notices.size(), n0 + 1, "one notice per session")
	ok(g.flow.notices[n0].begins_with("Could not save (E_TEST)"), "notice text")
	ok(g.flow.save_failed, "dot on")
	g.flow._store_ok()
	ok(not g.flow.save_failed, "dot cleared by a good write")
	g.free()


func test_transition_length_from_config() -> void:
	var g := _game()
	g.debug_map("town")
	g.cfg["transitionMs"] = 50.0
	var door: Variant = null
	for id in g.world.doors_by_id:
		door = g.world.doors_by_id[id]
		break
	if door == null:
		g.free()
		return
	ok(g.change_map(str(door["toMap"]), str(door["toDoor"])), "transition starts")
	near(float(g.transition["dur"]), 0.1, 1e-9, "transitionMs is floored at 100")
	g.free()


func test_menu_clicks_do_not_leak() -> void:
	var g := _game()
	g.set_state("paused")
	g.ping_clicks = 2
	g.feed_press = 1
	g.interact_press = true
	g.step(0.05, {})
	eq(g.ping_clicks, 0, "ping clicks cleared")
	eq(g.feed_press, 0, "feed presses cleared")
	ok(not g.interact_press, "interact cleared")
	g.free()


func test_bark_voices_stop_on_state_change() -> void:
	var g := _game()
	var stopped := [0]
	g.bark_spk.append({"id": 1, "h": {"end": 5.0, "stop": func(): stopped[0] += 1}, "end": 99.0})
	g.bark_spk.append({"id": 2, "h": {"end": 5.0, "stop": func(): stopped[0] += 1}, "end": 99.0})
	g.stop_bark_voice(2)
	eq(stopped[0], 1, "stop one voice by id")
	eq(g.bark_spk.size(), 1, "one left")
	g.set_state("paused")
	eq(stopped[0], 2, "state change stops the rest")
	eq(g.bark_spk.size(), 0, "none left")
	g.free()
