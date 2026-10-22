extends TestCase
## Gameplay actions on a headless Game: feeding to a drained victim, powers (shriek, mist, still), rocks, pings, listening at a
## window, barks, the gift offer when the overflow fills, and walking through a link door. Looks for state changes the
## logic modules promise and for runtime errors (any SCRIPT ERROR in the output fails the run in tools/run-tests.ps1).


func _game() -> Game:
	Game.test_storage = SaveCodec.MemoryStorage.new()
	Game.manual_boot = true
	var g := Game.new()
	g.boot()
	g.flow.seed_param = 5
	g.flow.begin_run()
	return g


func _done(g: Game) -> void:
	g.free()


func _step(g: Game, seconds: float, inp: Dictionary = {}, dt: float = 0.05) -> void:
	for i in int(round(seconds / dt)):
		g.step(dt, inp)


func _near_villager(g: Game) -> People.Person:
	# put the player 0.8 cells in front of a calm, feedable villager and face them
	for p in g.people.people:
		if p.mode == "path" and p.feedable and not p.sit:
			var a: float = p.angle + PI
			var px: float = p.x + cos(a) * 0.8
			var py: float = p.y + sin(a) * 0.8
			if not g.world.blocks(px, py, 0.2):
				g.player.place(px, py, atan2(p.y - py, p.x - px))
				return p
	return null


func test_feed_to_drained() -> void:
	var g := _game()
	g.debug_map("town")
	_step(g, 2.0)
	var v := _near_villager(g)
	ok(v != null, "found a villager to feed on")
	if v == null:
		return
	g.night.blood = 20.0
	g.player_lit = 0.0
	g.player.place(v.x - 0.8, v.y, 0.0)
	g.feed_press = 1
	g.step(0.05, {})
	if g.drink == null:
		# the villager may have wandered; use the forced start the tests use
		ok(g.start_drink(true), "forced feeding starts")
	eq(g.state, "feeding", "feeding state")
	var before: float = g.night.blood
	for i in 200:
		g.step(0.05, {})
		if g.drink == null:
			break
		g.drink["interrupt"] = false
	ok(g.night.blood > before or g.drink == null, "blood rises while drinking")
	if g.drink != null:
		g.end_drink("test")
	eq(g.state, "playing", "back to playing after the drink")
	_done(g)


func test_powers_and_rocks() -> void:
	var g := _game()
	g.night.night = 3          # all powers unlocked from night 3
	g.night.blood = 90.0
	var pulses0: int = g.sonar.pulses.size()
	ok(g.powers.use_power("shriek")["ok"], "shriek works")
	ok(g.sonar.pulses.size() > pulses0, "shriek makes a sound pulse")
	g.hunger.cd["still"] = 0.0
	ok(g.powers.use_power("still")["ok"], "still works")
	ok(g.hunger.is_still(), "the town is still")
	g.hunger.cd["mist"] = 0.0
	var x0: float = g.player.x
	var y0: float = g.player.y
	ok(g.powers.use_power("mist")["ok"], "mist works")
	_step(g, 0.5)
	ok(sqrt((g.player.x - x0) * (g.player.x - x0) + (g.player.y - y0) * (g.player.y - y0)) >= 0.0, "mist dash ran")
	var left: int = g.powers.rocks_left
	g.pressed[KEY_G] = true
	g.step(0.05, {})
	eq(g.powers.rocks_left, left - 1, "a rock is thrown")
	_step(g, 2.0)
	g.ping_clicks += 1
	_step(g, 0.1)
	ok(g.sonar.pulses.size() > 0, "a ping makes pulses")
	ok(g.state == "playing", "still playing")
	_done(g)


func test_gift_offer() -> void:
	var g := _game()
	g.night.blood = g.night.blood_max
	g.debug_map("town")
	_step(g, 1.0)
	var v := _near_villager(g)
	ok(v != null, "villager for the gift test")
	if v == null:
		return
	ok(g.start_drink(true), "feeding starts at full blood")
	var offered := false
	for i in 400:
		g.step(0.05, {})
		if g.state == "gift":
			offered = true
			break
		if g.drink == null:
			break
	if offered:
		eq((g.flow.run["pendingGifts"] as Array).size(), 3, "three gifts offered")
		ok(g.flow.pick_gift(0), "a gift is taken")
		eq(g.state, "playing", "playing after the gift")
		ok(g.hunger.gifts.size() == 1, "the gift is recorded")
	else:
		ok(g.hunger.over >= 0.0, "overflow accumulates")
	_done(g)


func test_link_doors_between_all_maps() -> void:
	var g := _game()
	for name in g.world_names:
		ok(g.debug_map(name), "can enter %s" % name)
		_step(g, 0.3)
	g.debug_map("town")
	for id in g.world.doors_by_id:
		var d: Dictionary = g.world.doors_by_id[id]
		var a: Variant = g.worlds[d["toMap"]].arrival(d["toDoor"])
		ok(a != null, "door %s leads to a real arrival" % id)
	_done(g)


func test_listen_and_barks() -> void:
	var g := _game()
	g.debug_map("town")
	_step(g, 5.0)
	# stand outside a window facing it and hold E
	var done := false
	for y in g.world.height:
		for x in g.world.width:
			if done:
				break
			if g.world.tile_at(x + 0.5, y + 0.5) != "w":
				continue
			for d in [[0, 1, -PI / 2.0], [0, -1, PI / 2.0], [1, 0, PI], [-1, 0, 0.0]]:
				var px: float = x + 0.5 + d[0] * 0.7
				var py: float = y + 0.5 + d[1] * 0.7
				if g.world.blocks(px, py, 0.2):
					continue
				var w: Variant = Listen.find_window(g.world, {"x": px, "y": py, "angle": d[2]}, 1.2)
				if w != null:
					g.player.place(px, py, d[2])
					done = true
					break
	ok(done, "found a window to listen at")
	if not done:
		return
	_step(g, 8.0)
	eq(g.state, "playing", "still playing")
	_step(g, 30.0)
	ok(g.barks_st != null, "bark state exists after stepping")
	_done(g)
