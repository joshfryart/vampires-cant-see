extends TestCase
## The Long Night end to end on a headless Game (game/rogue_mode.gd): a trek through the Menus signals, the Hollow walked from the
## coffin to the exit by its BFS path, feeding a critter, critter echoes and glyphs, the cave's ambient sounds, dawn at a rest spot,
## sleeping and waiting out the day (Heat), hunters, the withering death and Laid to Rest, Rise Again, continue from the checkpoint,
## and that classic Five Nights still starts afterwards.

const SEED := 7


func _game() -> Game:
	Game.test_storage = SaveCodec.MemoryStorage.new()
	Game.manual_boot = true
	GameData.clear_generated()
	var g := Game.new()
	g.boot()
	return g


## Free the game and unregister the generated stage so later tests see the plain map set.
func _done(g: Game) -> void:
	g.free()
	GameData.clear_generated()


func _trek(g: Game, seed_v: int = SEED) -> RogueMode:
	g.rogue.new_trek(seed_v)
	return g.rogue


func _step(g: Game, seconds: float, inp: Dictionary = {}, dt: float = 0.05) -> void:
	for i in int(round(seconds / dt)):
		g.step(dt, inp)


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


func _played(g: Game, kind: String) -> bool:
	for e in g.audio.log:
		if e["kind"] == kind:
			return true
	return false


## A free spot about a cell from (x, y), facing it. Returns [px, py, angle].
func _spot_near(g: Game, x: float, y: float) -> Array:
	for o in [Vector2(-0.9, 0), Vector2(0.9, 0), Vector2(0, -0.9), Vector2(0, 0.9), Vector2(-0.6, 0), Vector2(0.6, 0), Vector2(0, -0.6), Vector2(0, 0.6)]:
		if not g.world.blocks(x + o.x, y + o.y, 0.2):
			return [x + o.x, y + o.y, atan2(-o.y, -o.x)]
	return [x, y, 0.0]


func _rest_cell(f: TrekFlow) -> Vector2i:
	var r: Dictionary = f.def["rest"][0]
	return Vector2i(int(r["cell"][0]), int(r["cell"][1]))


func test_version() -> void:
	eq(str(ProjectSettings.get_setting("application/config/version")), "0.21.0", "version 0.21.0")


func test_new_trek_from_the_menu() -> void:
	var g := _game()
	g.flow.seed_param = SEED
	ok(not g.rogue.active, "idle at the title")
	g.menus.trek_new_requested.emit()
	var r := g.rogue
	ok(r.active, "trek active")
	eq(g.state, "playing", "playing")
	eq(g.map_name, "hollow", "in the Hollow")
	ok(g.run_on, "run on")
	ok(g.rogue_on(), "rogue_on")
	ok(g.night == r.trek.night and g.hunger == r.trek.hunger, "HUD reads the trek night and hunger")
	ok(g.systems.has(r), "registered as a systems hook")
	eq(r.trek.stage_id, "hollow", "first stage")
	eq(r.trek.seed, SEED, "seed")
	var st := r.trek.start_cell
	near(g.player.x, st.x + 0.5, 1e-9, "player on the start cell x")
	near(g.player.y, st.y + 0.5, 1e-9, "player on the start cell y")
	ok(r.critters.critters.size() >= 8, "critters spawned (%d)" % r.critters.critters.size())
	ok(not r.ambient.emitters.is_empty(), "ambient anchors")
	ok(g.sonar.protect_last, "player ping protected")
	eq(g.run_seed, SEED, "run_seed follows the trek")
	ok(r._sounds.size() >= 20, "rogue sounds registered (%d)" % r._sounds.size())
	ok(_played(g, "rg_coffin_creak"), "coffin creak at the start")
	ok(_played(g, "rg_stage_arrival"), "stage arrival stinger")
	ok(g.menus.trek_ui.stage_card_visible(), "stage card shown")
	ok(g.flow.store.has("trek"), "checkpoint written at stage entry")
	ok(not g.flow.store.has("run"), "no classic run save")
	# classic saves are bypassed
	ok(not g.flow.save_run("test"), "classic save_run is a no-op during a trek")
	_step(g, 1.0)
	eq(g.state, "playing", "still playing")
	ok(g.night.min > 0.0, "the trek clock runs")
	_done(g)


func test_walk_the_hollow_and_leave() -> void:
	var g := _game()
	var r := _trek(g)
	var f := r.trek
	var path := _path(f)
	eq(f.dist_to_exit(path[path.size() - 1]), 0, "path ends at the exit door")
	var last := 0.0
	for i in path.size():
		var c: Vector2i = path[i]
		if i == path.size() - 1:
			g.world.set_door(c.x, c.y, true)
		g.player.place(c.x + 0.5, c.y + 0.5, 0.0)
		if i < path.size() - 1:
			g.step(0.05, {})
			ok(f.progress >= last - 1e-12, "progress never drops")
			last = f.progress
			if not r.active:
				break
	ok(r.active and f.alive(), "alive at the exit")
	ok(f.progress > 0.9, "progress near 1 (%.3f)" % f.progress)
	ok(f.night.blood > 0.0, "blood left")
	g.step(0.05, {})   # standing in the open door
	ok(not r.active, "the trek ended at the exit (no further stage yet)")
	eq(g.state, "runend", "run end state")
	eq(r.last_result.get("cause"), "frontier", "frontier cause")
	near(float(r.last_result["miles"]), 3.0, 1e-9, "3 miles")
	eq(int(r.last_result["unseen"]), 1, "cleared unseen")
	eq(int(r.last_result["soilTotal"]), 11, "soil paid")
	eq(int(g.menus.trek_meta["soil"]), 11, "Menus meta holds the soil")
	ok(not g.flow.store.has("trek"), "checkpoint cleared")
	ok(not g.systems.has(r), "hook removed")
	var tx := TrekUi.rest_text(r.last_result)
	eq(tx["title"], "To be continued...", "frontier title")
	ok(String(tx["cause"]).find("To be continued...") >= 0, "frontier line")
	ok(_played(g, "rg_laid_to_rest"), "laid to rest toll")
	_done(g)


func test_feed_a_critter() -> void:
	var g := _game()
	var r := _trek(g)
	var c: Critters.Critter = r.critters.critters[0]
	var sp := _spot_near(g, c.x, c.y)
	g.player.place(sp[0], sp[1], sp[2])
	g.night.blood = 30.0
	var n0 := r.critters.critters.size()
	var cf := r.trek.critters_fed
	ok(r.try_feed_critter(), "fed on the critter in reach")
	eq(r.critters.critters.size(), n0 - 1, "prey is gone for good")
	eq(r.trek.critters_fed, cf + 1, "trek counts it")
	ok(g.night.blood > 30.0, "blood gained")
	ok(not r.try_feed_critter() or r.critters.critters.size() < n0 - 1, "only one at a time")
	# the R key path through Game.step feeds too
	var c2: Critters.Critter = r.critters.critters[0]
	var sp2 := _spot_near(g, c2.x, c2.y)
	g.player.place(sp2[0], sp2[1], sp2[2])
	var left := r.critters.critters.size()
	g.feed_press = 1
	g.step(0.016, {})
	ok(r.critters.critters.size() < left or g.drink != null, "feed key drinks a critter in reach")
	_done(g)


func test_critter_echoes_and_glyphs() -> void:
	var g := _game()
	var r := _trek(g)
	var c: Critters.Critter = r.critters.critters[0]
	var sp := _spot_near(g, c.x, c.y)
	g.player.place(sp[0], sp[1], sp[2])
	g.ping_clicks = 1
	g.step(0.05, {})
	_step(g, 0.3)
	ok(not r.critters.echoes.is_empty(), "the ping lights a critter (%d echoes)" % r.critters.echoes.size())
	var canvas := DrawCanvas.new()
	r.draw(g, canvas)
	ok(canvas.ops.size() > 0, "critter glyphs drawn (%d ops)" % canvas.ops.size())
	# every species has a glyph that draws without error
	var cv := DrawCanvas.new()
	for sp_name in Critters.species_table():
		cv.reset()
		CritterDraw.glyph(cv, CritterDraw.kind_of(sp_name), sp_name, 320.0, 200.0, 300.0, 200.0, float(CritterDraw.SIZE.get(sp_name, 1.0)), 1.0, 1.0, 0.5, false, true, "#ffffff")
		ok(cv.ops.size() > 0, "glyph ops for " + sp_name)
		cv.reset()
		CritterDraw.glyph(cv, CritterDraw.kind_of(sp_name), sp_name, 320.0, 200.0, 300.0, 200.0, 1.0, -1.0, 2.0, 0.1, true, false, "#ffffff")
		ok(cv.ops.size() > 0, "resting glyph ops for " + sp_name)
	_done(g)


func test_ambient_drips_sound_and_light() -> void:
	var g := _game()
	var r := _trek(g)
	var drips := 0
	for i in 400:
		g.step(0.05, {})
		drips = int(r.stats["drips"])
		if drips > 0:
			break
	ok(drips > 0, "a drip near the coffin within 20 s")
	ok(_played(g, "rg_drip_cave") or _played(g, "rg_drip_pool"), "drip sound played")
	_done(g)


func test_dawn_sleep_at_a_rest_spot() -> void:
	var g := _game()
	var r := _trek(g)
	var f := r.trek
	var rc := _rest_cell(f)
	g.player.place(rc.x + 0.5, rc.y + 0.5, 0.0)
	g.night.skip_to(5, 0)
	_step(g, 4.0)
	ok(_played(g, "rg_dawn_bell"), "dawn bell")
	ok(g.menus.trek_ui.dawn_state() != "hidden", "dawn countdown shown")
	g.night.skip_to(5, 59)
	_step(g, 2.0)
	eq(f.state, "choice", "the day needs a choice")
	ok(r.prompt_open and g.menus.trek_ui.wait_prompt_visible(), "wait prompt shown")
	ok(_played(g, "rg_dawn_birds"), "dawn birds")
	# movement is locked while the prompt is open
	var px := g.player.x
	_step(g, 0.5, {"forward": 1.0})
	near(g.player.x, px, 1e-9, "input locked by the prompt")
	g.interact_press = true
	g.step(0.05, {})
	eq(g.state, "sleeping", "E at the rest spot sleeps")
	ok(f.heat >= 1, "Heat rose (%d)" % f.heat)
	eq(f.night.status, "night", "dusk")
	near(f.night.min, 0.0, 1.0, "clock at dusk")
	ok(g.flow.store.has("trek"), "slept: checkpoint")
	_step(g, 3.0)
	eq(g.state, "playing", "awake again")
	ok(not r.prompt_open, "prompt closed")
	ok(not g.menus.trek_ui.wait_prompt_visible(), "prompt hidden")
	_done(g)


func test_sleep_needs_a_rest_spot() -> void:
	var g := _game()
	var r := _trek(g)
	var f := r.trek
	# far from every rest spot
	var far: Vector2i = f.start_cell
	var best := -1.0
	for y in g.world.height:
		for x in g.world.width:
			if g.world.blocks(x + 0.5, y + 0.5, 0.2):
				continue
			var dmin := 999.0
			for rr in f.def["rest"]:
				dmin = minf(dmin, Vector2(float(rr["cell"][0]) + 0.5, float(rr["cell"][1]) + 0.5).distance_to(Vector2(x + 0.5, y + 0.5)))
			if dmin > best:
				best = dmin
				far = Vector2i(x, y)
	g.player.place(far.x + 0.5, far.y + 0.5, 0.0)
	g.night.skip_to(5, 59)
	_step(g, 2.0)
	eq(f.state, "choice", "choice")
	g.interact_press = true
	g.step(0.05, {})
	eq(g.state, "playing", "no sleep away from a rest spot")
	eq(f.heat, 0, "no heat")
	_done(g)


func test_wait_out_the_day() -> void:
	var g := _game()
	var r := _trek(g)
	var f := r.trek
	g.night.skip_to(5, 59)
	_step(g, 2.0)
	eq(f.state, "choice", "choice")
	r._begin_wait()
	ok(r.waiting, "waiting")
	ok(g.menus.trek_ui.waiting_visible(), "waiting overlay")
	var guard := 0
	while r.waiting and guard < 4000:
		guard += 1
		g.step(0.05, {})
	ok(not r.waiting, "the wait ended")
	ok(not g.menus.trek_ui.waiting_visible(), "waiting overlay hidden")
	eq(f.heat, 1, "Heat +1")
	eq(f.night.status, "night", "dusk again")
	ok(r.active and f.alive(), "alive")
	_done(g)


func test_stir_ends_a_wait_early() -> void:
	var g := _game()
	var r := _trek(g)
	g.night.skip_to(5, 59)
	_step(g, 2.0)
	r._begin_wait()
	_step(g, 2.0)
	g.menus.trek_ui.wait_interrupted.emit()
	ok(not r.waiting, "stirred")
	eq(r.trek.state, "choice", "the day is still pending")
	eq(r.trek.heat, 0, "no heat for stirring")
	r.interact()
	ok(r.prompt_open, "E opens the prompt again")
	_done(g)


func test_hunters_at_heat_two() -> void:
	var g := _game()
	var r := _trek(g)
	var f := r.trek
	f.heat = 2
	eq(f.hunters_wanted(), 1, "one hunter at Heat 2")
	r._spawn_hunters()
	eq(r.hunter_ids.size(), 1, "hunter spawned")
	var p := g.people.find_person(int(r.hunter_ids[0]))
	ok(p != null, "hunter person")
	if p == null:
		_done(g)
		return
	var field0 := RunFlow.bfs_cells(g.world, floori(g.player.x), floori(g.player.y))
	var d0: int = field0[floori(p.y) * g.world.width + floori(p.x)]
	ok(d0 >= RogueMode.HUNTER_MIN_BFS, "starts far away (%d)" % d0)
	_step(g, 6.0)
	var field1 := RunFlow.bfs_cells(g.world, floori(g.player.x), floori(g.player.y))
	var d1: int = field1[floori(p.y) * g.world.width + floori(p.x)]
	ok(d1 < d0 - 4, "the hunter closes in (%d -> %d)" % [d0, d1])
	# a hunter within 1.2 cells stakes the player
	p.x = g.player.x + 0.5
	p.y = g.player.y
	if g.world.blocks(p.x, p.y, 0.2):
		p.x = g.player.x - 0.5
	var b0: float = g.night.blood
	_step(g, 0.3)
	ok(g.night.blood < b0 - 30.0 or not r.active, "stake hit (%.1f -> %.1f)" % [b0, g.night.blood])
	_done(g)


func test_withered_laid_to_rest_and_rise_again() -> void:
	var g := _game()
	var r := _trek(g)
	var world0 := g.world
	g.night.blood = 0.0
	_step(g, 27.0, {}, 0.1)
	ok(not r.active, "the trek ended")
	eq(g.state, "runend", "run end")
	eq(r.last_result.get("cause"), "withered", "withered")
	ok(g.menus._trek_view == "rest", "Laid to Rest shown")
	ok(not g.flow.store.has("trek"), "permadeath: no checkpoint")
	ok(g.flow.store.has("rogue"), "rogue meta saved")
	eq(int(g.menus.trek_meta["stats"]["deaths"]["withered"]), 1, "death recorded")
	g.menus.rise_again_requested.emit()
	ok(g.rogue.active, "Rise Again starts a new trek")
	eq(g.state, "playing", "playing")
	eq(g.menus._trek_view, "", "Laid to Rest hidden")
	ok(g.world != world0, "a fresh Hollow world replaced the stale one")
	ok(g.world == g.worlds["hollow"], "world is the registered one")
	ok(g.meshes.has("hollow"), "meshes rebuilt")
	_step(g, 1.0)
	# back to the title keeps the checkpoint for Continue
	g.set_state("title")
	ok(not g.rogue.active, "title stops the trek")
	ok(g.flow.store.has("trek"), "checkpoint kept")
	_done(g)


func test_continue_from_the_checkpoint() -> void:
	var g := _game()
	var r := _trek(g, 11)
	var rc := _rest_cell(r.trek)
	g.player.place(rc.x + 0.5, rc.y + 0.5, 0.0)
	_step(g, 2.0)
	g.set_state("title")
	ok(not g.rogue.active, "stopped")
	ok(g.menus.has_trek_checkpoint(), "Continue offered")
	g.menus.trek_continue_requested.emit()
	ok(g.rogue.active, "continued")
	eq(g.rogue.trek.seed, 11, "same seed")
	eq(g.rogue.trek.stage_id, "hollow", "same stage")
	eq(g.state, "playing", "playing")
	near(g.player.x, rc.x + 0.5, 0.6, "back at the checkpoint cell")
	_step(g, 1.0)
	_done(g)


func test_classic_still_starts_after_a_trek() -> void:
	var g := _game()
	var r := _trek(g)
	g.night.blood = 0.0
	_step(g, 27.0, {}, 0.1)
	eq(g.state, "runend", "ended")
	g.flow.seed_param = 5
	ok(g.flow.begin_run(), "classic run begins")
	ok(not g.rogue_on(), "rogue off")
	ok(g.night != r.trek.night, "classic night")
	_step(g, 2.0)
	eq(g.state, "playing", "classic plays")
	ok(g.flow.save_run("test"), "classic saves again")
	_done(g)
