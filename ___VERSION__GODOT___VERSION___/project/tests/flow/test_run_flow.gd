extends TestCase
## Whole-run flow on a headless Game: title -> run -> night clock and drain -> sleep -> boon -> next night -> win, the sun
## loss, the pause/continue save round trip, and the meta stats. Logic parity of the modules is in tests/parity.


func _game() -> Game:
	Game.test_storage = SaveCodec.MemoryStorage.new()
	Game.manual_boot = true
	var g := Game.new()
	g.boot()
	return g


func _step(g: Game, seconds: float, dt: float = 0.05) -> void:
	for i in int(round(seconds / dt)):
		g.step(dt, {})


func _go_to_bed(g: Game) -> void:
	var spots: Array = g.world.spots["crypt"]
	var sp: Variant = spots[0] if spots.size() > 0 else g.world.spots["safe"][0]
	g.player.place(sp.x, sp.y, 0.0)


func test_full_run_to_victory() -> void:
	var g := _game()
	eq(g.state, "title", "starts at the title")
	g.flow.seed_param = 42
	ok(g.flow.begin_run(), "run begins")
	eq(g.state, "playing", "playing")
	eq(g.night.night, 1, "night 1")
	var b0: float = g.night.blood
	_step(g, 20.0)
	ok(g.night.blood < b0, "blood drains")
	ok(g.night.min > 0.0, "clock runs")
	for n in 5:
		eq(g.night.night, n + 1, "night %d" % (n + 1))
		g.night.skip_to(5, 0)
		_go_to_bed(g)
		g.interact_press = true
		_step(g, 0.1)
		eq(g.state, "sleeping", "sleeping on night %d" % (n + 1))
		_step(g, 3.0)
		if n < 4:
			eq(g.state, "boon", "boon choice after night %d" % (n + 1))
			eq((g.flow.run["pendingBoons"] as Array).size(), 3, "three boons")
			g.pressed[KEY_1] = true
			_step(g, 0.05)
			eq(g.state, "playing", "back to playing")
			eq(g.flow.run["boons"].size(), n + 1, "boon taken")
		else:
			eq(g.state, "runend", "victory ends the run")
	eq(g.flow.run_result["kind"], "won", "won")
	ok(g.flow.meta["essence"] > 0, "essence earned")
	eq(g.flow.meta["stats"]["wins"], 1, "win counted")
	ok(not g.flow.store.has("run"), "run save cleared")
	g.free()


func test_sun_loss() -> void:
	var g := _game()
	g.flow.seed_param = 7
	g.flow.begin_run()
	g.debug_map("town")
	g.night.skip_to(5, 59)
	_step(g, 4.0)
	eq(g.state, "runend", "the sun ends the run outdoors")
	eq(g.flow.run_result["kind"], "lost", "lost")
	eq(g.flow.meta["stats"]["runs"], 1, "run counted")
	g.free()


func test_pause_and_continue() -> void:
	var g := _game()
	g.flow.seed_param = 99
	g.flow.begin_run()
	_step(g, 15.0)
	var m: float = g.night.min
	var pos := Vector2(g.player.x, g.player.y)
	g.pause()
	eq(g.state, "paused", "paused")
	ok(g.flow.store.has("run"), "pause saves the run")
	g.run_on = false
	g.set_state("title")
	ok(g.flow.continue_run(), "continue works")
	eq(g.state, "playing", "playing after continue")
	near(g.night.min, m, 1e-9, "night minute restored")
	near(g.player.x, pos.x, 1e-9, "player x")
	eq(g.flow.run["seed"], 99, "seed kept")
	g.free()


func test_export_import_and_abandon() -> void:
	var g := _game()
	g.flow.seed_param = 7
	g.flow.begin_run()
	_step(g, 5.0)
	g.pause()
	ok(g.flow.save_run("test"), "run saved")
	g.flow.meta["essence"] = 33
	g.flow.save_meta()
	var path := "user://test_export.json"
	ok(g.flow.export_save_to(path), "exported")
	var text := FileAccess.get_file_as_string(path)
	var g2 := _game()
	ok(g2.flow.import_text(text), "imported")
	eq(int(g2.flow.meta["essence"]), 33, "meta essence imported")
	ok(g2.flow.has_run, "run imported")
	var runs0: int = int(g2.flow.meta["stats"]["runs"])
	g2.flow.abandon_stored()
	ok(not g2.flow.has_run, "run removed on abandon")
	eq(int(g2.flow.meta["stats"]["runs"]), runs0 + 1, "abandoned run counted")
	ok(not g2.flow.import_text("{not json"), "bad import rejected")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	g.free()
	g2.free()
