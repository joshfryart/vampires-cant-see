extends TestCase
## World.from_def and Player.update parity against tests/fixtures/world_player.json (tools/golden/world_player.mjs).


func test_world_queries() -> void:
	var fx: Dictionary = load_fixture("world_player")
	for wd in fx["worlds"]:
		var w := World.from_def(GameData.map_def(wd["name"]))
		eq(w.width, int(wd["width"]), "%s width" % wd["name"])
		eq(w.height, int(wd["height"]), "%s height" % wd["name"])
		eq(w.kind, wd["kind"], "%s kind" % wd["name"])
		eq(w.floor_mat, wd["floor"], "%s floor" % wd["name"])
		if wd["start"] != null:
			near(w.start.x, float(wd["start"]["x"]), 1e-12, "%s start.x" % wd["name"])
			near(w.start.y, float(wd["start"]["y"]), 1e-12, "%s start.y" % wd["name"])
		for key in ["crypt", "safe", "people", "doors"]:
			eq(w.spots[key].size(), wd["spots"][key].size(), "%s spots.%s" % [wd["name"], key])
		eq(w.props.size(), int(wd["propCount"]), "%s props" % wd["name"])
		for i in w.props.size():
			var pr: Array = wd["props"][i]
			eq(w.props[i]["type"], pr[0], "%s prop %d type" % [wd["name"], i])
			near(w.props[i]["x"], float(pr[1]), 1e-12, "prop x")
			eq(1 if w.props[i]["solid"] else 0, int(pr[3]), "prop solid")
		for q in wd["pts"]:
			var x := float(q[0])
			var y := float(q[1])
			var lbl := "%s (%s,%s)" % [wd["name"], str(x), str(y)]
			eq(w.tile_at(x, y), q[2], lbl + " tile")
			eq(1 if w.is_solid(x, y) else 0, int(q[3]), lbl + " solid")
			eq(w.material_at(x, y), q[4], lbl + " material")
			eq(1 if w.blocks(x, y, 0.2) else 0, int(q[5]), lbl + " blocks0.2")
			eq(1 if w.blocks(x, y, 0.45) else 0, int(q[6]), lbl + " blocks0.45")
		for d in wd["doorsClosed"]:
			var c := int(d[0])
			var r := int(d[1])
			eq(1 if w.is_solid(c + 0.5, r + 0.5) else 0, int(d[2]), "%s door %d,%d closed solid" % [wd["name"], c, r])
			eq(1 if w.set_door(c, r, true) else 0, int(d[3]), "set_door")
			eq(1 if w.is_solid(c + 0.5, r + 0.5) else 0, int(d[4]), "open solid")
			eq(1 if w.is_door_open(c, r) else 0, int(d[5]), "is_door_open")
		for a in wd["arrivals"]:
			var got: Variant = w.arrival(a["id"])
			near(got["x"], float(a["a"]["x"]), 1e-12, "arrival x")
			near(got["y"], float(a["a"]["y"]), 1e-12, "arrival y")
			near(got["angle"], float(a["a"]["angle"]), 1e-9, "arrival angle")


func test_player_traces() -> void:
	var fx: Dictionary = load_fixture("world_player")
	for pd in fx["players"]:
		var w := World.from_def(GameData.map_def(pd["map"]))
		var p := Player.create(float(pd["start"][0]), float(pd["start"][1]), float(pd["angle0"]))
		var patterns: Array = pd["patterns"]
		var trace: Array = pd["trace"]
		var k := 0
		for i in 600:
			var inp: Dictionary = patterns[(i / 25) % patterns.size()]
			var dt: float = 0.5 if i % 37 == 0 else (0.033 if i % 5 == 0 else 0.016)
			p.update(w, inp, dt)
			if i % 10 == 9:
				var row: Array = trace[k]
				k += 1
				near(p.x, float(row[0]), 1e-9, "%s step %d x" % [pd["map"], i])
				near(p.y, float(row[1]), 1e-9, "%s step %d y" % [pd["map"], i])
				near(p.angle, float(row[2]), 1e-9, "%s step %d angle" % [pd["map"], i])
		eq(k, trace.size(), "%s trace length" % pd["map"])


func test_norm_angle() -> void:
	var fx: Dictionary = load_fixture("world_player")
	for a in fx["angles"]:
		near(Player.create(1.0, 1.0, float(a[0])).angle, float(a[1]), 1e-9, "angle %s" % str(a[0]))
