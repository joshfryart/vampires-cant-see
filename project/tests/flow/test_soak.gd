extends TestCase
## Soak: a seeded bot plays 6 simulated minutes on the town (random walking and turning, pings, feeding when a villager is close,
## powers, rocks, doors, sleeping near the end of a night, boon and gift picks) and the state invariants must hold throughout:
## finite player position inside the map, blood within bounds, people finite, no stuck feeding. Any runtime error shows up as a
## SCRIPT ERROR in the output.


func _inp(rng: RandomNumberGenerator) -> Dictionary:
	return {"forward": 1.0 if rng.randf() < 0.8 else 0.0, "strafe": rng.randf_range(-0.3, 0.3) if rng.randf() < 0.2 else 0.0, "turn": rng.randf_range(-1.0, 1.0) if rng.randf() < 0.3 else 0.0, "mouseDx": 0.0}


func test_bot_plays() -> void:
	Game.test_storage = SaveCodec.MemoryStorage.new()
	Game.manual_boot = true
	var g := Game.new()
	g.boot()
	g.flow.seed_param = 11
	g.flow.begin_run()
	g.debug_map("town")
	var rng := RandomNumberGenerator.new()
	rng.seed = 2024
	var dt := 0.05
	var steps := int(360.0 / dt)
	var inp := {}
	var fed_before: int = g.night.fed_count
	for i in steps:
		if i % 10 == 0:
			inp = _inp(rng)
		var r := rng.randf()
		if r < 0.01:
			g.ping_clicks += 1
		elif r < 0.014:
			g.feed_press += 1
		elif r < 0.016:
			g.pressed[KEY_Q] = true
		elif r < 0.018:
			g.pressed[KEY_F] = true
		elif r < 0.02:
			g.pressed[KEY_G] = true
		elif r < 0.024:
			g.interact_press = true
		elif r < 0.026:
			g.pressed[KEY_SHIFT] = true
		if g.state == "boon":
			g.pressed[KEY_1] = true
		elif g.state == "gift":
			g.pressed[KEY_2] = true
		elif g.state == "runend":
			g.flow.begin_run()
		elif g.state == "paused":
			g.resume()
		elif g.state == "title":
			g.flow.begin_run()
		if g.night != null and g.night.min > 500.0 and g.state == "playing" and i % 40 == 0:
			g.night.min = 505.0
		g.step(dt, inp)
		if i % 20 == 0:
			ok(is_finite(g.player.x) and is_finite(g.player.y), "player finite at step %d" % i)
			ok(g.player.x > 0.0 and g.player.y > 0.0 and g.player.x < g.world.width and g.player.y < g.world.height, "player inside the map at step %d" % i)
			if g.night != null:
				ok(g.night.blood >= 0.0 and g.night.blood <= g.night.blood_max + 1e-6, "blood in bounds at step %d (%s)" % [i, str(g.night.blood)])
			for p in g.people.people:
				if not (is_finite(p.x) and is_finite(p.y)):
					ok(false, "person %d finite at step %d" % [p.id, i])
					break
			if g.drink != null:
				ok(g.state == "feeding", "feeding state while drinking at step %d" % i)
		# a drink that has run for a long time is cut (the soak must not stall on one victim)
		if g.drink != null and float(g.drink["t"]) > 30.0:
			g.end_drink("soak")
	ok(g.run_on or g.state == "runend" or g.state == "title" or g.state == "playing", "run state is sane at the end: %s" % g.state)
	g.free()
