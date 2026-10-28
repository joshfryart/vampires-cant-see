extends SceneTree
## ASCII dump + layout checks for generated Hollow caves (a design aid, not part of the test suite).
## Usage: godot --headless --path project -s res://tests/tools/cave_ascii.gd -- --seeds=1,2,3 [--stage=hollow] [--brief]
## --brief dumps the repeat-run (brief) form, whose beats may use chunk variants (printed as "variants:").
## Markers: 1-9 beats (in generator order), @ start, X exit, B bat, R rat, ? other critter, s rest spot, a ambient anchor, # wall, ~ water.
## Checks: the squeeze cannot be bypassed (BFS coffin -> echo hall with squeeze zone cells blocked), beat order by BFS depth,
## dead_end_spurs must not branch off the Coffin Nook, plus per-zone emptiness counts. Prints WARN lines.

const N4 := [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]


func _init() -> void:
	var seeds: Array = [1, 2, 3]
	var stage := "hollow"
	var brief := false
	for a in OS.get_cmdline_user_args():
		if a == "--brief":
			brief = true
		if a.begins_with("--seeds="):
			seeds = []
			for p in a.substr(8).split(","):
				if p.strip_edges().is_valid_int():
					seeds.append(int(p))
		elif a.begins_with("--stage="):
			stage = a.substr(8)
	var warns := 0
	for sd in seeds:
		warns += _report(stage, int(sd), brief)
	print("CAVE_ASCII done, %d warning(s)" % warns)
	quit(0)


func _beat(def: Dictionary, id: String) -> Dictionary:
	for b in def["beats"]:
		if String(b["id"]) == id:
			return b
	return {}


func _zone(def: Dictionary, id: String) -> Dictionary:
	for z in def["zones"]:
		if String(z["name"]) == id:
			return z
	return {}


func _in_zone(z: Dictionary, c: Vector2i, pad: int = 0) -> bool:
	return not z.is_empty() and c.x >= int(z["x0"]) - pad and c.x <= int(z["x1"]) + pad and c.y >= int(z["y0"]) - pad and c.y <= int(z["y1"]) + pad


func _walk(w: World, c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < w.width and c.y < w.height and not w.blocks(c.x + 0.5, c.y + 0.5, 0.2)


func _bfs(w: World, src: Vector2i, blocked: Dictionary = {}) -> Dictionary:
	var dist := {src: 0}
	var q: Array = [src]
	var qi := 0
	while qi < q.size():
		var c: Vector2i = q[qi]
		qi += 1
		for d in N4:
			var n: Vector2i = c + d
			if not dist.has(n) and not blocked.has(n) and _walk(w, n):
				dist[n] = int(dist[c]) + 1
				q.append(n)
	return dist


func _cell(a: Variant) -> Vector2i:
	return Vector2i(int(a[0]), int(a[1]))


func _report(stage: String, sd: int, brief: bool = false) -> int:
	var def: Dictionary = StageGen.generate(stage, sd, brief)
	if def.is_empty():
		print("seed %d: NO DEF" % sd)
		return 1
	var w := World.from_def(def)
	var rows: Array = def["rows"]
	var grid: Array = []
	for r in rows:
		grid.append(String(r).replace("S", ".").replace("C", ".").replace("D", ".").replace("@", "."))
	var put := func(c: Vector2i, ch: String) -> void:
		if c.y >= 0 and c.y < grid.size() and c.x >= 0 and c.x < String(grid[c.y]).length():
			var s: String = grid[c.y]
			grid[c.y] = s.substr(0, c.x) + ch + s.substr(c.x + 1)
	for an in def["ambient"]:
		put.call(_cell(an["cell"]), "a")
	for r in def["rest"]:
		put.call(_cell(r["cell"]), "s")
	for cr in def["critters"]:
		var sp := String(cr["species"])
		put.call(_cell(cr["cell"]), "B" if sp == "bat" else ("R" if sp == "rat" else "?"))
	var crumbs: Array = def["gen"].get("crumbs", [])
	var mouths: Array = []
	for pk in def["pockets"]:
		if String(pk["kind"]) == "spur":
			mouths.append(_cell(pk["mouth"]))
			put.call(_cell(pk["mouth"]), "M")
	for an in def["ambient"]:
		if an.get("dead", false):
			put.call(_cell(an["cell"]), "A")
	for cr2 in crumbs:
		put.call(_cell(cr2), "*")
	var ex: Vector2i = _cell(def["exit"]["cell"])
	put.call(ex, "X")
	var start: Vector2i = _cell(def["start"]["cell"])
	put.call(start, "@")
	var legend := []
	var i := 1
	for b in def["beats"]:
		put.call(_cell(b["cell"]), str(i))
		legend.append("%d=%s" % [i, b["id"]])
		i += 1
	print("=== %s seed %d%s  (%dx%d) ===" % [stage, sd, " brief" if brief else "", w.width, w.height])
	if def["gen"].has("variants"):
		print("variants: " + str(def["gen"]["variants"]))
	for r in grid:
		print(r)
	print("legend: " + ", ".join(legend) + " | @ start X exit B bat R rat s rest a ambient A dead-air * crumb M spur mouth")
	var warns := 0
	var dist := _bfs(w, start)

	# beat order by BFS depth
	var depths := []
	for b in def["beats"]:
		var c := _cell(b["cell"])
		depths.append([int(dist.get(c, -1)), String(b["id"])])
		if not dist.has(c):
			print("WARN seed %d: beat %s unreachable from start" % [sd, b["id"]])
			warns += 1
	# the optional side beat (dead_end_spurs) is reported after the main path and excluded from the order check
	var main_depths := []
	for d in depths:
		if d[1] != "dead_end_spurs":
			main_depths.append(d)
	var sorted := main_depths.duplicate()
	sorted.sort_custom(func(a, b): return a[0] < b[0])
	var gen_order := []
	var depth_order := []
	for d in depths:
		gen_order.append("%s@%d" % [d[1], d[0]])
	for d in sorted:
		depth_order.append(String(d[1]))
	print("beat BFS depth (generator order; dead_end_spurs is optional): " + ", ".join(gen_order))
	var ids_order := []
	for d in main_depths:
		ids_order.append(String(d[1]))
	if ids_order != depth_order:
		print("WARN seed %d: main-path beats are not in depth order: %s" % [sd, " > ".join(depth_order)])
		warns += 1

	# squeeze bypass: block the squeeze zone cells, coffin -> echo hall
	var sq := _zone(def, "squeeze")
	var hall := _beat(def, "echo_hall")
	if sq.is_empty() or hall.is_empty():
		print("WARN seed %d: no squeeze zone or echo_hall beat" % sd)
		warns += 1
	else:
		var blocked := {}
		for y in range(int(sq["y0"]), int(sq["y1"]) + 1):
			for x in range(int(sq["x0"]), int(sq["x1"]) + 1):
				blocked[Vector2i(x, y)] = true
		var d2 := _bfs(w, start, blocked)
		var hc := _cell(hall["cell"])
		if d2.has(hc):
			print("WARN seed %d: squeeze can be BYPASSED: coffin -> echo hall is %d steps with the squeeze zone blocked (%d with it open)" % [sd, d2[hc], dist.get(hc, -1)])
			warns += 1
		else:
			print("ok seed %d: echo hall unreachable with the squeeze blocked (open path %d steps)" % [sd, dist.get(hc, -1)])

	# dead_end_spurs vs the coffin nook
	var nook := _zone(def, "coffin_nook")
	var spur := _beat(def, "dead_end_spurs")
	if not spur.is_empty() and not nook.is_empty():
		var cur := _cell(spur.get("end", spur["cell"]))
		var prev := Vector2i(-99, -99)
		var steps := 0
		var junction := cur
		while steps < 200:
			var nb: Array = []
			for d in N4:
				var n: Vector2i = cur + d
				if n != prev and _walk(w, n):
					nb.append(n)
			if nb.size() != 1:
				junction = cur
				break
			prev = cur
			cur = nb[0]
			steps += 1
		var near_nook := _in_zone(nook, junction, 1)
		var dn := int(dist.get(_cell(spur.get("end", spur["cell"])), -1))
		print("dead_end_spurs: corridor of %d cells ends at junction %s (spur beat depth %d)" % [steps, junction, dn])
		if near_nook:
			print("WARN seed %d: dead_end_spurs grows out of the Coffin Nook (junction %s inside the nook zone)" % [sd, junction])
			warns += 1

	# wayfinding: one crumb per main-path beat but the last, increasing depth, more than 3 cells from every spur mouth, spur tells present
	if crumbs.size() != 6:
		print("WARN seed %d: %d breadcrumbs (want 6)" % [sd, crumbs.size()])
		warns += 1
	var last_cd := -1
	var ci := 0
	for cc in crumbs:
		var cd := int(dist.get(_cell(cc), -1))
		if cd <= last_cd:
			print("WARN seed %d: breadcrumb %d at depth %d is not deeper than the previous (%d)" % [sd, ci, cd, last_cd])
			warns += 1
		last_cd = cd
		for m in mouths:
			if maxi(absi(m.x - _cell(cc).x), absi(m.y - _cell(cc).y)) <= 3:
				print("WARN seed %d: breadcrumb %d is within 3 cells of spur mouth %s" % [sd, ci, m])
				warns += 1
		ci += 1
	var dead_n := 0
	for an in def["ambient"]:
		if an.get("dead", false):
			dead_n += 1
	if dead_n != mouths.size():
		print("WARN seed %d: %d dead-air anchors for %d spur mouths" % [sd, dead_n, mouths.size()])
		warns += 1
	print("wayfinding: %d crumbs at depths %s, %d spur mouths, %d dead-air anchors, %d lights, %d anchors" % [crumbs.size(), str(crumbs.map(func(c2): return int(dist.get(_cell(c2), -1)))), mouths.size(), dead_n, def["lights"].size(), def["ambient"].size()])

	# emptiness per zone
	var anch: Array = def["ambient"]
	for zid in ["echo_hall", "still_pool", "drip_gallery", "squeeze", "rat_warren"]:
		var z := _zone(def, zid)
		if z.is_empty():
			continue
		var floor_n := 0
		for y in range(int(z["y0"]), int(z["y1"]) + 1):
			for x in range(int(z["x0"]), int(z["x1"]) + 1):
				if _walk(w, Vector2i(x, y)):
					floor_n += 1
		var na := 0
		for an in anch:
			if _in_zone(z, _cell(an["cell"])):
				na += 1
		var nc := 0
		for cr in def["critters"]:
			if _in_zone(z, _cell(cr["cell"])):
				nc += 1
		var nr := 0
		for r in def["rest"]:
			if _in_zone(z, _cell(r["cell"])):
				nr += 1
		print("zone %-12s floor %3d  anchors %d  critters %d  rest %d" % [zid, floor_n, na, nc, nr])
		if (zid == "squeeze" or zid == "rat_warren") and na == 0:
			print("WARN seed %d: %s has no ambient anchor" % [sd, zid])
			warns += 1
		if zid == "echo_hall" and na == 0:
			print("WARN seed %d: echo hall has no ambient anchor (critters inside: %d; %d floor cells)" % [sd, nc, floor_n])
			warns += 1
	var apron := _zone(def, "cave_apron")
	if apron.is_empty() or String(apron["kind"]) != "outdoor":
		print("WARN seed %d: no outdoor apron zone" % sd)
		warns += 1
	else:
		print("apron: outdoor zone (%d,%d)-(%d,%d), exit arrival %s" % [apron["x0"], apron["y0"], apron["x1"], apron["y1"], def["exit"]["arrival"]])
	var walk_n := 0
	for y in w.height:
		for x in w.width:
			if _walk(w, Vector2i(x, y)):
				walk_n += 1
	print("walkable %d cells, %d anchors, %d critters, %d rest spots, anchor density %.1f/100 cells" % [walk_n, anch.size(), def["critters"].size(), def["rest"].size(), 100.0 * anch.size() / maxf(1.0, walk_n)])
	return warns
