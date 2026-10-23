extends TestCase
## The second-stage handoff (WP13a): hollow -> wood -> moor through TrekFlow.reach_exit and through RogueMode on a headless Game, each stage entered at
## dusk on its entry door with the previous stage's exit linked to it, walked start to exit by its BFS field, the sun and the pockets of the outdoor
## stages, and the frontier ("To be continued...") after the moor until the road has a generator.

const SEED := 7


func _meta() -> Dictionary:
	return TrekMeta.create()


func _store() -> SaveCodec.Store:
	return SaveCodec.create(SaveCodec.MemoryStorage.new())


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


# ---- TrekFlow ----------------------------------------------------------------------------------------------------------------------------------

func test_trek_flow_hollow_wood_moor_frontier() -> void:
	var st := _store()
	var meta := _meta()
	var f := TrekFlow.begin(meta, SEED, st)
	eq(f.def["exit"]["toMap"], "stage:wood", "hollow exit target")
	f.heat = 1
	f.step(0.1, f.start_cell, false)
	var r := f.reach_exit()
	ok(r["ok"] and not r["ended"], "leaving the hollow continues the trek")
	var d: Dictionary = r["descriptor"]
	eq(d["stage"], "wood", "descriptor stage")
	eq(d["map_name"], "wood", "map name")
	eq(d["name"], "Bramble Wood", "stage name")
	eq(d["index"], 2, "stage index")
	eq(f.leg, 1, "leg 1")
	eq(f.heat, 0, "Heat resets for the new stage")
	eq(f.night.status, "night", "dusk")
	near(f.night.min, 0.0, 1e-9, "clock back to dusk")
	near(f.night.drain_mul, 0.9, 1e-9, "wood drain")
	near(f.miles(), 3.0, 1e-9, "3 miles cleared")
	eq(d["start"], f.start_cell, "start cell")
	eq([d["start"].x, d["start"].y], d["def"]["entry"]["arrival"], "the player arrives on the entry door's cell")
	eq(d["def"]["doors"][0]["id"], "cave", "the wood's door back is named cave (the hollow's toDoor)")
	eq(d["def"]["doors"][0]["toMap"], "stage:hollow", "and leads back to the hollow")
	eq(d["exit"]["toMap"], "stage:moor", "wood exit target")
	eq(f.world.kind, "outdoor", "the wood is outdoors")
	var rc: Array = d["def"]["rest"][0]["cell"]
	ok(not f.cell_outdoor(Vector2i(rc[0], rc[1])), "rest spots are roofed")
	ok(f.cell_outdoor(f.start_cell), "the entry cell is open sky")
	ok(f.dist_to_exit(f.start_cell) > 40, "bfs field from the wood's exit reaches the start (%d)" % f.dist_to_exit(f.start_cell))
	ok(d["rest"].size() >= 3 and d["pockets"].size() >= 3, "rest spots and pockets in the descriptor")
	ok(d["critters"].size() >= 7, "critters in the descriptor")
	ok(st.has("trek"), "checkpoint at the wood's entry")
	eq(st.read("trek")["data"]["stage"], "wood", "checkpoint names the wood")
	var path := _path(f)
	eq(f.dist_to_exit(path[path.size() - 1]), 0, "the path ends at the exit door")
	var last := 0.0
	for c in path:
		f.step(1.0 / 3.0, c, f.cell_outdoor(c))
		ok(f.progress >= last - 1e-12, "progress never drops")
		last = f.progress
	ok(f.alive(), "alive at the wood's exit (blood %.1f)" % f.night.blood)
	near(f.miles(), 6.0, 1e-9, "6 miles at the wood's exit")
	var r2 := f.reach_exit()
	ok(r2["ok"] and not r2["ended"], "leaving the wood continues the trek")
	eq(r2["descriptor"]["stage"], "moor", "descriptor stage")
	eq(f.stage_id, "moor", "moor")
	eq(f.leg, 2, "leg 2")
	eq(r2["descriptor"]["name"], "Gallows Moor", "stage name")
	eq(r2["descriptor"]["def"]["doors"][0]["id"], "wood", "the moor's door back is named wood")
	eq(r2["descriptor"]["exit"]["toMap"], "stage:road", "moor exit target")
	near(f.night.drain_mul, 1.0, 1e-9, "moor drain")
	eq(f.night.status, "night", "dusk again")
	for c in _path(f):
		f.step(1.0 / 3.0, c, f.cell_outdoor(c))
	ok(f.alive(), "alive at the moor's exit")
	near(f.miles(), 9.0, 1e-9, "9 miles at the moor's exit")
	var r3 := f.reach_exit()
	ok(r3["ok"] and r3["ended"], "after the moor the road has no generator: the trek ends")
	var res: Dictionary = r3["result"]
	eq(res["cause"], "frontier", "frontier after the moor")
	eq(res["stageName"], "Gallows Moor", "ended on the moor")
	eq(res["stageIndex"], 3, "stage index 3")
	near(res["miles"], 9.0, 1e-9, "9 miles")
	eq(res["unseen"], 3, "three stages cleared unseen")
	eq(res["soilTotal"], 23, "9 miles + 9 unseen + 5 new best")
	eq(meta["soil"], 23, "soil paid")
	eq(meta["stats"]["bestStage"], 3, "best stage 3")
	ok(meta["reached"].has("wood") and meta["reached"].has("moor"), "reached recorded")
	ok(not st.has("trek"), "checkpoint cleared")
	eq(TrekFlow.next_stage_id("moor"), "road", "moor -> road")
	ok(not TrekFlow.has_generator("road"), "the road has no generator yet")


func test_checkpoint_in_the_wood_resumes_in_the_wood() -> void:
	var g := TrekFlow.begin(_meta(), 21)
	g.reach_exit()
	var snap := g.snapshot()
	eq(snap["stage"], "wood", "snapshot names the wood")
	eq(snap["leg"], 1, "snapshot leg")
	var h := TrekFlow.continue_from(JSON.parse_string(JSON.stringify(snap)), g.meta)
	ok(h != null, "wood checkpoint loads")
	if h != null:
		eq(h.stage_id, "wood", "resumed in the wood")
		eq(h.def["rows"], g.def["rows"], "same wood")
		eq(h.start_cell, g.start_cell, "same start")
		near(h.cleared_miles, 3.0, 1e-9, "cleared miles kept")


func test_dawn_in_the_open_kills_in_a_pocket_does_not() -> void:
	for id in ["wood", "moor"]:
		var f := TrekFlow.begin(_meta(), 5)
		f.reach_exit()
		if id == "moor":
			f.reach_exit()
		eq(f.stage_id, id, "in the " + id)
		var rest: Dictionary = f.def["rest"][0]
		var rcell := Vector2i(int(rest["cell"][0]), int(rest["cell"][1]))
		var g := TrekFlow.begin(_meta(), 5)
		g.reach_exit()
		if id == "moor":
			g.reach_exit()
		# in a pocket: the day comes, the player is roofed and gets the choice
		f.night.skip_to(5, 59)
		var ev := f.step(2.0, rcell, f.cell_outdoor(rcell))
		eq(f.state, "choice", id + ": a roofed rest spot at dawn gives the day choice")
		var has_dawn := false
		for e in ev:
			if e["type"] == "death":
				ok(false, id + ": no death in a pocket")
			if e["type"] == "needs_choice":
				has_dawn = true
		ok(has_dawn, id + ": needs_choice event")
		var sl := f.sleep_at_rest(rcell)
		ok(sl["ok"], id + ": slept in the pocket (%s)" % str(sl.get("result")))
		eq(f.night.status, "night", id + ": dusk again after the sleep")
		# in the open: the sun finds you
		g.night.skip_to(5, 59)
		g.step(2.0, g.start_cell, g.cell_outdoor(g.start_cell))
		eq(g.state, "dead", id + ": dawn on the open start cell kills")
		eq(g.cause, "sun", id + ": by the sun")


# ---- RogueMode on a headless Game ----------------------------------------------------------------------------------------------------------------

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


func _step(g: Game, seconds: float, inp: Dictionary = {}, dt: float = 0.05) -> void:
	for i in int(round(seconds / dt)):
		g.step(dt, inp)


## Teleport along the stage's BFS path to the exit door, open it and step into it; returns true when the trek took the exit.
func _walk_out(g: Game, r: RogueMode) -> bool:
	var f := r.trek
	var from_stage := f.stage_id
	var path := _path(f)
	for i in path.size():
		var c: Vector2i = path[i]
		if i == path.size() - 1:
			g.world.set_door(c.x, c.y, true)
		g.player.place(c.x + 0.5, c.y + 0.5, 0.0)
		if i < path.size() - 1:
			g.step(0.05, {})
			if not r.active or r.trek.stage_id != from_stage:
				break
	g.step(0.05, {})
	return not r.active or r.trek.stage_id != from_stage


func test_game_walks_hollow_wood_moor_to_the_frontier() -> void:
	var g := _game()
	g.rogue.new_trek(SEED)
	var r := g.rogue
	eq(g.map_name, "hollow", "in the Hollow")
	ok(_walk_out(g, r), "left the Hollow")
	ok(r.active and r.trek.alive(), "the trek goes on")
	eq(r.trek.stage_id, "wood", "now in Bramble Wood")
	eq(g.map_name, "wood", "the wood's map is current")
	ok(g.worlds.has("wood") and not g.worlds.has("hollow"), "the hollow's world was dropped")
	eq(g.world.kind, "outdoor", "an outdoor world")
	var st := r.trek.start_cell
	near(g.player.x, st.x + 0.5, 1e-9, "on the entry cell x")
	near(g.player.y, st.y + 0.5, 1e-9, "on the entry cell y")
	ok(r.critters.critters.size() >= 7, "rabbits and deer (%d)" % r.critters.critters.size())
	for c in r.critters.critters:
		ok(c.species == "rabbit" or c.species == "deer", "wood fauna " + c.species)
	var kinds := {}
	for e in r.ambient.emitters:
		kinds[e["kind"]] = true
	ok(kinds.has("owl") and kinds.has("creek") and kinds.has("wind"), "wood ambient " + str(kinds.keys()))
	ok(g.menus.trek_ui.stage_card_visible(), "stage card shown")
	eq(g.night.status, "night", "dusk")
	near(g.night.min, 0.0, 1.0, "clock at dusk")
	ok(g.flow.store.has("trek"), "checkpoint at the wood's entry")
	_step(g, 2.0)
	eq(g.state, "playing", "playing in the wood")
	# the wood wakes: the sun does not (night), a pocket is roofed
	var rest: Dictionary = r.trek.def["rest"][0]
	eq(g.world.kind_at(float(rest["cell"][0]) + 0.5, float(rest["cell"][1]) + 0.5), "indoor", "rest spot under cover")
	ok(_walk_out(g, r), "left the wood")
	eq(r.trek.stage_id, "moor", "now on Gallows Moor")
	eq(g.map_name, "moor", "the moor's map is current")
	ok(not g.worlds.has("wood"), "the wood's world was dropped")
	for c in r.critters.critters:
		ok(c.species == "hare" or c.species == "wolf", "moor fauna " + c.species)
	var mk := {}
	for e in r.ambient.emitters:
		mk[e["kind"]] = true
	ok(mk.has("cricket") and mk.has("wind"), "moor ambient " + str(mk.keys()))
	_step(g, 2.0)
	eq(g.state, "playing", "playing on the moor")
	ok(_walk_out(g, r), "left the moor")
	ok(not r.active, "no road yet: the trek ended at the frontier")
	eq(g.state, "runend", "run end state")
	eq(r.last_result.get("cause"), "frontier", "frontier cause")
	near(float(r.last_result["miles"]), 9.0, 1e-9, "9 miles")
	eq(int(r.last_result["stageIndex"]), 3, "stage index 3")
	eq(int(r.last_result["soilTotal"]), 23, "soil paid")
	eq(TrekUi.rest_text(r.last_result)["title"], "To be continued...", "frontier title")
	_done(g)


func test_game_sun_and_pocket_in_the_wood() -> void:
	var g := _game()
	g.rogue.new_trek(SEED)
	var r := g.rogue
	ok(_walk_out(g, r), "left the Hollow")
	var f := r.trek
	eq(f.stage_id, "wood", "in the wood")
	var rest: Dictionary = f.def["rest"][0]
	var rc := Vector2i(int(rest["cell"][0]), int(rest["cell"][1]))
	g.player.place(rc.x + 0.5, rc.y + 0.5, 0.0)
	g.night.skip_to(5, 59)
	_step(g, 2.0)
	eq(f.state, "choice", "dawn in a pocket gives the day choice")
	ok(r.prompt_open, "the prompt is open")
	g.interact_press = true
	g.step(0.05, {})
	eq(g.state, "sleeping", "E at the pocket's rest spot sleeps")
	_step(g, 3.0)
	eq(g.state, "playing", "awake at dusk in the wood")
	ok(f.heat >= 1, "Heat rose")
	_done(g)
	# and in the open the sun kills
	var g2 := _game()
	g2.rogue.new_trek(SEED)
	ok(_walk_out(g2, g2.rogue), "left the Hollow again")
	g2.night.skip_to(5, 59)
	_step(g2, 2.0)
	ok(g2.rogue.trek.state == "dead" or g2.rogue.trek.state == "ended", "the sun kills on the open entry cell (%s)" % g2.rogue.trek.state)
	eq(g2.rogue.trek.cause, "sun", "by the sun")
	eq(g2.rogue.last_result.get("cause"), "sun", "Laid to Rest by the sun")
	_done(g2)
