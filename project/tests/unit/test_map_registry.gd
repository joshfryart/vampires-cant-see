extends TestCase
## Runtime map registry (GameData.register_map, Game.add_world / drop_world) and the Game.systems hook list.

class Hook:
	extends RefCounted
	var log: Array
	var tag: String

	func _init(l: Array, t: String) -> void:
		log = l
		tag = t

	func step(_g, _dt: float) -> void:
		log.append(tag + ":step")

	func on_pulse(_g, _p) -> void:
		log.append(tag + ":pulse")

	func draw(_g, _c) -> void:
		log.append(tag + ":draw")


class StepOnly:
	extends RefCounted
	var n: int = 0

	func step(_g, _dt: float) -> void:
		n += 1


func _game() -> Game:
	Game.test_storage = SaveCodec.MemoryStorage.new()
	Game.manual_boot = true
	var g := Game.new()
	g.boot()
	return g


func _def() -> Dictionary:
	return {
		"name": "gen_test",
		"rows": ["########", "#..@...#", "#......#", "#...C..#", "########"],
	}


func test_game_data_registry() -> void:
	var n0: int = GameData.maps()["maps"].size()
	GameData.register_map("gen_a", _def())
	eq(GameData.map_def("gen_a")["name"], "gen_test", "resolves through map_def")
	ok(GameData.maps()["maps"].has("gen_a"), "in maps()")
	eq(GameData.generated_names(), ["gen_a"], "tracked")
	ok(not GameData.unregister_map("test"), "data maps are not unregistered")
	ok(GameData.unregister_map("gen_a"), "unregister")
	ok(not GameData.maps()["maps"].has("gen_a"), "gone")
	GameData.register_map("gen_b", _def())
	GameData.register_map("gen_c", _def())
	GameData.clear_generated()
	eq(GameData.maps()["maps"].size(), n0, "clear_generated restores the data maps")
	eq(GameData.generated_names().size(), 0, "none tracked")


func test_rogue_loader_and_fill_missing() -> void:
	var st: Variant = GameData.load_rogue("stages")
	ok(st is Dictionary and st.has("stages"), "stages.json stub loads")
	ok(GameData.load_rogue("no_such_file") == null, "missing file is null")
	var dst := {"a": 1, "n": {"x": 1}}
	GameData.fill_missing(dst, {"a": 2, "b": 3, "n": {"x": 9, "y": 4}})
	eq(dst["a"], 1, "existing key kept")
	eq(dst["b"], 3, "missing key filled")
	eq(dst["n"]["x"], 1, "nested existing kept")
	eq(dst["n"]["y"], 4, "nested missing filled")


func test_add_enter_drop_world() -> void:
	var g := _game()
	var names_before: Array = g.world_names.duplicate()
	var w := g.add_world("gen_test", _def())
	ok(w != null and g.worlds.has("gen_test"), "world cached")
	eq(GameData.map_def("gen_test")["name"], "gen_test", "def registered")
	eq(g.world_names, names_before, "classic world_names untouched")
	var start := g.map_name
	g.enter_map("gen_test", 2.5, 1.5, 0.0, "")
	eq(g.map_name, "gen_test", "entered")
	ok(g.meshes.has("gen_test"), "mesh built")
	ok(g.light_textures.has("gen_test"), "light texture built")
	g.people_for("gen_test")
	ok(g.people_by_map.has("gen_test"), "people cached")
	ok(not g.drop_world("gen_test"), "cannot drop the current map")
	g.enter_map(start, g.player.x, g.player.y, 0.0, "")
	var insts: Array = g.meshes["gen_test"].duplicate()
	ok(g.drop_world("gen_test"), "dropped")
	ok(not g.worlds.has("gen_test"), "world evicted")
	ok(not g.meshes.has("gen_test"), "mesh evicted")
	ok(not g.light_images.has("gen_test"), "light image evicted")
	ok(not g.light_textures.has("gen_test"), "light texture evicted")
	ok(not g.people_by_map.has("gen_test"), "people evicted")
	ok(not GameData.maps()["maps"].has("gen_test"), "def unregistered")
	ok(not g.drop_world(start), "classic worlds cannot be dropped")
	ok(g.worlds.has(start), "classic world still there")
	for i in insts:
		ok(i.is_queued_for_deletion() or not is_instance_valid(i), "mesh instance freed")
	g.free()


func test_systems_hook_order() -> void:
	var g := _game()
	g.flow.seed_param = 7
	ok(g.flow.begin_run(), "run begins")
	g.step(0.05, {})  # empty list: no-op
	var log: Array = []
	var so := StepOnly.new()
	g.systems = [Hook.new(log, "a"), so, Hook.new(log, "b")]
	g.step(0.05, {})
	eq(log, ["a:step", "b:step"], "step order, optional methods skipped")
	eq(so.n, 1, "partial hook stepped")
	log.clear()
	g.cool = 0.0
	g.ping_clicks = 1
	g.step(0.05, {})
	ok(log.has("a:pulse") and log.has("b:pulse"), "on_pulse fired for the ping")
	ok(log.find("a:pulse") < log.find("b:pulse"), "pulse order")
	log.clear()
	g._render_systems()
	eq(log, ["a:draw", "b:draw"], "draw hooks in order")
	g.systems = []
	log.clear()
	g.step(0.05, {})
	eq(log.size(), 0, "empty list is a no-op")
	g.free()


func test_clear_generated_after_game() -> void:
	var g := _game()
	g.add_world("gen_x", _def())
	g.add_world("gen_y", _def())
	GameData.clear_generated()
	ok(not GameData.maps()["maps"].has("gen_x"), "defs cleared")
	ok(g.drop_world("gen_x") and g.drop_world("gen_y"), "worlds still droppable")
	g.free()
