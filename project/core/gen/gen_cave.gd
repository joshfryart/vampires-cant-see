class_name GenCave
extends RefCounted
## The Hollow (stage 1): seeded cave from authored beat chunks (data/rogue/chunks.json) plus cellular-automaton filler chambers.
## Pipeline per attempt (an attempt that breaks a constraint is discarded and the next attempt uses a derived seed, so the result
## is still a pure function of the seed):
##   1 layout: the chain of 7 beat chunks (coffin nook ... cave mouth) is walked out first, then 1-2 filler chambers (8-9 nodes in all);
##     tree = MST of the node centres with the chain edges forced, so the tree path start -> exit is the beat order (order by depth)
##   2 stamp the chunks (rect protected from later carving), CA blobs for fillers, one small loop through a filler, biased drunk-walk
##     tunnels of width 1-2 between chunk ports
##   3 2-3 blind spurs (end = hidden rest spot), growth towards a target open fraction, prune floor the start cannot reach
##   4 crevice alcoves until every walkable cell is near a rest spot, decoration, critters, def assembly, StageGen.analyze + WorldValidate

const MAX_ATTEMPTS := 200
const FILLER_GAP := 2

static var last_attempts: int = 0
## Why attempts were rejected, by reason key (diagnostics only; not part of the def).
static var fails: Dictionary = {}


static func _fail(k: String) -> Dictionary:
	fails[k] = int(fails.get(k, 0)) + 1
	return {}


static func generate(row: Dictionary, seed: int) -> Dictionary:
	var data := StageGen.chunks()
	if data.is_empty():
		return {}
	for attempt in MAX_ATTEMPTS:
		var rng := Rng.new(StageGen.seed_for(seed, attempt))
		var def := _attempt(row, data, rng, seed, attempt)
		if not def.is_empty():
			last_attempts = attempt + 1
			return def
	last_attempts = MAX_ATTEMPTS
	return {}


static func _attempt(row: Dictionary, data: Dictionary, rng: Rng, seed: int, attempt: int) -> Dictionary:
	var sz: Dictionary = row["size"]
	var w: int = int(sz["w"])
	var h: int = int(sz["h"])
	var chunks: Dictionary = data["chunks"]
	var legend: Dictionary = data["legend"]
	var order: Array = data["order"]
	var nodes_cfg: Dictionary = row["nodes"]
	var n: int = StageGen.rint(rng, int(nodes_cfg["min"]), int(nodes_cfg["max"]))

	# 1+2 layout: the beat chain is walked out first (each chunk rect fits, gap for tunnels), then fillers; the MST of all centres must
	# contain every chain edge, so the tree path from the first to the last beat is the main path in order.
	var lay: Dictionary = {}
	for _l in 40:
		lay = _layout(rng, w, h, n, order, chunks)
		if not lay.is_empty():
			break
	if lay.is_empty():
		return _fail("r1")
	var pts: Array = lay["pts"]
	var rects: Dictionary = lay["rects"]
	var xform: Dictionary = lay["xform"]
	var fillr: Dictionary = lay["fillr"]
	var role: Dictionary = lay["role"]
	var path: Array = lay["path"]
	var forced: Array = []
	for k in range(path.size() - 1):
		forced.append([path[k], path[k + 1]])
	var edges := StageGen.mst(pts, forced)
	var adj: Array = []
	for i in n:
		adj.append([])
	for e in edges:
		adj[e[0]].append(e[1])
		adj[e[1]].append(e[0])

	# 3 stamp, blobs, loop, tunnels
	var plan := StageGen.Plan.new(w, h)
	plan.tiles.fill(0)
	var info: Dictionary = {}   # node -> stamp result
	for i in n:
		if role.has(i):
			var ch2: Dictionary = chunks[role[i]]
			var xf: Array = xform[i]
			var rc: Rect2i = rects[i]
			var res := StageGen.stamp(plan, ch2, legend, rc.position.x, rc.position.y, xf[0], xf[1])
			res["used"] = []
			for _p in res["ports"]:
				res["used"].append(0)
			info[i] = res
			for pk in ch2.get("pockets", []):
				var cl: Array = res["cells"].get(String(pk["cell_char"]), [])
				if not cl.is_empty():
					plan.pockets.append({"zone": String(pk["zone"]), "kind": String(pk["kind"]), "rest": true, "cell": [cl[0].x, cl[0].y]})
	for i in n:
		if fillr.has(i):
			StageGen.carve_ca_blob(plan, rng, pts[i].x, pts[i].y, fillr[i])
	var all_edges: Array = edges.duplicate()
	var loops := _pick_loop(rng, pts, edges, adj, path, role, order, n)
	for l in loops:
		all_edges.append(l)
	for e in all_edges:
		var a: int = e[0]
		var b: int = e[1]
		var sa := _endpoint(info, pts, a, pts[b])
		var sb := _endpoint(info, pts, b, pts[a])
		var width: int = StageGen.rint(rng, 1, 2)
		if not StageGen.carve_tunnel(plan, rng, sa, sb, width):
			return _fail("r4")
	if not _early_order_ok(plan, info, role, order):
		return _fail("r4b")
	var open_before := plan.open_fraction()
	var fr: Dictionary = row["openFraction"]
	if open_before > float(fr["max"]):
		return _fail("r5")

	# 4 spurs
	var shelter: Dictionary = row["shelter"]
	var spurs_cfg: Dictionary = row["spurs"]
	var want_spurs: int = StageGen.rint(rng, int(spurs_cfg["min"]), int(spurs_cfg["max"]))
	var spur_ends: Array = []
	for _s in want_spurs:
		var end := _make_spur(plan, rng, info, pts, fillr, spur_ends.size())
		if end.x >= 0:
			spur_ends.append(end)
	if spur_ends.size() < int(spurs_cfg["min"]):
		return _fail("r6")
	# growth towards the target fraction (organic widening of concavities; chunks, spurs and their rings are protected)
	var target: float = StageGen.rrange(rng, float(fr["min"]) + 0.02, float(fr["max"]) - 0.02)
	var openc: int = plan.floor_count()
	var goal: int = int(ceil(target * float((w - 2) * (h - 2))))
	var cand: Array = []
	var in_cand := PackedByteArray()
	in_cand.resize(w * h)
	for y in range(3, h - 3):
		for x in range(3, w - 3):
			var ci := y * w + x
			if plan.tiles[ci] == 0 and plan.protect[ci] == 0 and (plan.tiles[ci - 1] != 0 or plan.tiles[ci + 1] != 0 or plan.tiles[ci - w] != 0 or plan.tiles[ci + w] != 0):
				cand.append(ci)
				in_cand[ci] = 1
	var guard := 0
	while openc < goal and guard < 40 and not cand.is_empty():
		guard += 1
		var keep: Array = []
		for ci in cand:
			if openc >= goal:
				keep.append(ci)
				continue
			if plan.tiles[ci] != 0:
				continue
			var c8: int = 0
			var c4: int = 0
			for d in StageGen.N8:
				if plan.tiles[ci + d.y * w + d.x] != 0:
					c8 += 1
			for d in StageGen.N4:
				if plan.tiles[ci + d.y * w + d.x] != 0:
					c4 += 1
			if c8 >= 3 and c4 >= 1 and rng.next() < 0.4:
				plan.tiles[ci] = 1
				openc += 1
				for d in StageGen.N4:
					var ni: int = ci + d.y * w + d.x
					var nx: int = ni % w
					var ny: int = ni / w
					if plan.tiles[ni] == 0 and plan.protect[ni] == 0 and in_cand[ni] == 0 and nx >= 3 and ny >= 3 and nx < w - 3 and ny < h - 3:
						in_cand[ni] = 1
						keep.append(ni)
			else:
				keep.append(ci)
		cand = keep
	# prune floor the start cannot reach (CA fragments); chunk floor that is cut off is a failed attempt
	if plan.start.x < 0:
		return _fail("r7")
	var dist := StageGen.bfs(plan, [plan.idx(plan.start.x, plan.start.y)])
	for i in plan.tiles.size():
		if plan.tiles[i] == 1 and dist[i] < 0 and not SOLID_PROP_AT(plan, i):
			if plan.protect[i] != 0 or plan.markers.has(i):
				return _fail("r8")
			plan.tiles[i] = 0
	# 5 crevices until the rest-distance target holds
	_cover(plan, rng, row)
	_decorate(plan, rng, row, pts, fillr, role)
	var def := _assemble(plan, rng, row, seed, attempt, chunks, role, info, path, order, spur_ends, loops.size())
	var rep := StageGen.analyze(def, row)
	if not rep["ok"]:
		for rs in rep["reasons"]:
			_fail("an:" + String(rs).split(" ")[0] + String(rs).split(" ")[1] if String(rs).split(" ").size() > 1 else String(rs))
		return _fail("r9")
	var v := StageGen.validate(def)
	if not v["ok"]:
		return _fail("r10")
	def["gen"]["openFraction"] = rep["open_fraction"]
	def["gen"]["maxRestDist"] = rep["max_rest_dist"]
	return def


## Walk out the chain of chunk rects (each rect fits the map, keeps a gap for tunnels and lies within reach of the previous one), then the
## fillers. Candidate centres are enumerated on a 2-cell lattice and one is picked at random. Returns {} when a node has no candidate.
static func _layout(rng: Rng, w: int, h: int, n: int, order: Array, chunks: Dictionary) -> Dictionary:
	var bounds := Rect2i(3, 3, w - 6, h - 6)
	var pts: Array = []
	var rects: Dictionary = {}
	var xform: Dictionary = {}
	var fillr: Dictionary = {}
	var role: Dictionary = {}
	var path: Array = []
	for k in n:
		var is_chunk: bool = k < order.size()
		var ch: Dictionary = chunks[order[k]] if is_chunk else {}
		var r: int = 0 if is_chunk else StageGen.rint(rng, 4, 5)
		var tr_opts: Array = [false]
		if is_chunk and ch.get("transpose", false) and k > 0:
			tr_opts = [false, true]
		var cands: Array = []
		var placed_rects: Array = rects.values()
		for tr in tr_opts:
			var s: Vector2i = StageGen.chunk_size(ch, tr) if is_chunk else Vector2i(2 * r + 1, 2 * r + 1)
			var y := bounds.position.y
			while y + s.y <= bounds.end.y:
				var x := bounds.position.x + ((y / 2) % 2)
				while x + s.x <= bounds.end.x:
					var rc := Rect2i(x, y, s.x, s.y)
					var ok := true
					for q in placed_rects:
						if rc.grow(FILLER_GAP).intersects(q):
							ok = false
							break
					if ok and k > 0 and (is_chunk or k >= order.size()):
						var c := Vector2(x + s.x / 2, y + s.y / 2)
						var near: float = 1.0e9 if not is_chunk else Vector2(pts[k - 1]).distance_to(c)
						if is_chunk and near > 24.0:
							ok = false
						elif not is_chunk:
							var best := 1.0e9
							for p in pts:
								best = minf(best, Vector2(p).distance_to(c))
							if best > 22.0:
								ok = false
					if ok:
						cands.append([rc, tr])
					x += 2
				y += 2
		if cands.is_empty():
			return {}
		var pick: Array = cands[int(floor(rng.next() * float(cands.size())))]
		var rect: Rect2i = pick[0]
		var c2 := Vector2i(rect.position.x + rect.size.x / 2, rect.position.y + rect.size.y / 2)
		pts.append(c2)
		rects[k] = rect
		if is_chunk:
			var fl: bool = ch.get("flip", false) and rng.next() < 0.5
			xform[k] = [pick[1], fl]
			role[k] = order[k]
			path.append(k)
		else:
			fillr[k] = r
	return {"pts": pts, "rects": rects, "xform": xform, "fillr": fillr, "role": role, "path": path}


## Cheap acceptance test run right after the tunnels: BFS depth from the start must increase along the beat chain.
static func _early_order_ok(plan: StageGen.Plan, info: Dictionary, role: Dictionary, order: Array) -> bool:
	if plan.start.x < 0:
		return false
	var dist := StageGen.bfs(plan, [plan.idx(plan.start.x, plan.start.y)])
	var last := -1
	for b in order:
		for node in role:
			if role[node] == b:
				var c: Vector2i = info[node]["beat_cell"]
				var d: int = dist[c.y * plan.w + c.x]
				if d <= last:
					return false
				last = d
	return true


static func SOLID_PROP_AT(plan: StageGen.Plan, i: int) -> bool:
	return StageGen.SOLID_PROPS.has(plan.prop_cells.get(i, ""))


## One extra edge that closes a small loop (tree distance 2) through a filler chamber, so the order of the beats along the main path
## cannot change: the loop joins a filler to the chain neighbour of the node it hangs from.
static func _pick_loop(_rng: Rng, pts: Array, edges: Array, adj: Array, _path: Array, role: Dictionary, _order: Array, n: int) -> Array:
	var in_tree := {}
	for e in edges:
		in_tree[mini(e[0], e[1]) * 100 + maxi(e[0], e[1])] = true
	var cands: Array = []
	for i in n:
		if role.has(i):
			continue
		for j in n:
			if j == i or in_tree.has(mini(i, j) * 100 + maxi(i, j)):
				continue
			if _hops(adj, n, i, j) != 2:
				continue
			cands.append([Vector2(pts[i]).distance_to(Vector2(pts[j])), i, j])
	cands.sort_custom(func(a, b): return a[0] < b[0] or (a[0] == b[0] and (a[1] < b[1] or (a[1] == b[1] and a[2] < b[2]))))
	if cands.is_empty():
		return []
	return [[cands[0][1], cands[0][2]]]


static func _hops(adj: Array, n: int, a: int, b: int) -> int:
	var dist: Array = []
	for i in n:
		dist.append(-1)
	dist[a] = 0
	var q: Array = [a]
	var head := 0
	while head < q.size():
		var u: int = q[head]
		head += 1
		for v in adj[u]:
			if dist[v] < 0:
				dist[v] = dist[u] + 1
				q.append(v)
	return dist[b]


## Cell where a tunnel leaving node `a` towards `toward` starts: the nearest free chunk port (cell just outside it) or a filler centre.
static func _endpoint(info: Dictionary, pts: Array, a: int, toward: Vector2i) -> Vector2i:
	if not info.has(a):
		return pts[a]
	var res: Dictionary = info[a]
	var best := -1
	var bd := 1.0e18
	for k in res["ports"].size():
		var pr: Dictionary = res["ports"][k]
		var d: float = Vector2(pr["out"]).distance_to(Vector2(toward)) + 1000.0 * float(res["used"][k])
		if d < bd:
			bd = d
			best = k
	res["used"][best] += 1
	return res["ports"][best]["out"]


## Blind spur: 8-14 steps of 1-wide tunnel that never touches other open cells. Returns the end cell or (-1, -1).
static func _make_spur(plan: StageGen.Plan, rng: Rng, info: Dictionary, pts: Array, fillr: Dictionary, idx: int) -> Vector2i:
	var origins: Array = []   # [start cell, direction]
	for i in info:
		var res: Dictionary = info[i]
		for k in res["ports"].size():
			if res["used"][k] == 0:
				var pr: Dictionary = res["ports"][k]
				origins.append([pr["out"], StageGen.DIR_OF[pr["dir"]], pr["cell"]])
	for i in fillr:
		var c: Vector2i = pts[i]
		var d: Vector2i = StageGen.N4[int(floor(rng.next() * 4.0))]
		var cur := c
		var guard := 0
		while plan.tile(cur.x + d.x, cur.y + d.y) != 0 and guard < 12:
			cur += d
			guard += 1
		origins.append([cur + d, d, cur])
	StageGen.shuffle(rng, origins)
	for o in origins:
		for _try in 6:
			var end := _try_spur(plan, rng, o[0], o[1], o[2], idx)
			if end.x >= 0:
				return end
	return Vector2i(-1, -1)


static func _try_spur(plan: StageGen.Plan, rng: Rng, start: Vector2i, dir: Vector2i, parent: Vector2i, idx: int) -> Vector2i:
	if plan.tile(start.x, start.y) != 0 or not StageGen.can_carve(plan, start.x, start.y, 3):
		return Vector2i(-1, -1)
	var length: int = StageGen.rint(rng, 8, 14)
	var cells: Array = [start]
	var used := {start.y * plan.w + start.x: true, parent.y * plan.w + parent.x: true}
	if not _clear_around(plan, start, used):
		return Vector2i(-1, -1)
	var cur := start
	var d := dir
	for _s in length - 1:
		var opts: Array = []
		var r := rng.next()
		if r < 0.65:
			opts = [d, Vector2i(d.y, d.x), Vector2i(-d.y, -d.x)]
		elif r < 0.825:
			opts = [Vector2i(d.y, d.x), d, Vector2i(-d.y, -d.x)]
		else:
			opts = [Vector2i(-d.y, -d.x), d, Vector2i(d.y, d.x)]
		var moved := false
		for nd in opts:
			var nx: int = cur.x + nd.x
			var ny: int = cur.y + nd.y
			var key: int = ny * plan.w + nx
			if used.has(key) or plan.tile(nx, ny) != 0 or not StageGen.can_carve(plan, nx, ny, 3):
				continue
			var recent := {cur.y * plan.w + cur.x: true, parent.y * plan.w + parent.x: true}
			if cells.size() >= 2:
				recent[cells[cells.size() - 2].y * plan.w + cells[cells.size() - 2].x] = true
			if not _clear_around(plan, Vector2i(nx, ny), recent, used):
				continue
			cur = Vector2i(nx, ny)
			d = nd
			cells.append(cur)
			used[key] = true
			moved = true
			break
		if not moved:
			return Vector2i(-1, -1)
	for c in cells:
		plan.tiles[c.y * plan.w + c.x] = 1
	for c in cells:
		for dd in StageGen.N8:
			var x: int = c.x + dd.x
			var y: int = c.y + dd.y
			if plan.inb(x, y):
				plan.protect[y * plan.w + x] = 1
		plan.protect[c.y * plan.w + c.x] = 1
	var end: Vector2i = cells[cells.size() - 1]
	plan.markers[end.y * plan.w + end.x] = "S"
	plan.rest.append({"cell": [end.x, end.y], "kind": "spur", "marker": "S", "safety": 0.8})
	var prev: Vector2i = cells[maxi(0, cells.size() - 2)]
	plan.zones.append({"name": "pocket_spur_%d" % (idx + 1), "kind": "indoor", "x0": mini(end.x, prev.x), "y0": mini(end.y, prev.y), "x1": maxi(end.x, prev.x), "y1": maxi(end.y, prev.y)})
	plan.pockets.append({"zone": "pocket_spur_%d" % (idx + 1), "kind": "spur", "rest": true, "cell": [end.x, end.y]})
	return end


static func _clear_around(plan: StageGen.Plan, c: Vector2i, allowed: Dictionary, pending: Dictionary = {}) -> bool:
	for d in StageGen.N8:
		var x: int = c.x + d.x
		var y: int = c.y + d.y
		if pending.has(y * plan.w + x) and not allowed.has(y * plan.w + x):
			return false
		if plan.tile(x, y) != 0 and not allowed.has(y * plan.w + x):
			return false
	return true


## Crevice alcoves (2 cells deep, 1 wide, dead end) until the farthest walkable cell is within restTarget of a rest spot.
static func _cover(plan: StageGen.Plan, rng: Rng, row: Dictionary) -> void:
	var shelter: Dictionary = row["shelter"]
	var target: int = int(shelter["restTarget"])
	var extra: int = int(shelter["maxExtraCrevices"])
	var made := 0
	var skip := {}
	# always at least one crevice so the stage has a rest spot that is not a chunk or spur
	var forced := 1
	while made < extra:
		var srcs: Array = []
		for r in plan.rest:
			srcs.append(plan.idx(r["cell"][0], r["cell"][1]))
		var dist := StageGen.bfs(plan, srcs)
		var far := -1
		var fd := -1
		for i in dist.size():
			if dist[i] > fd and not skip.has(i):
				fd = dist[i]
				far = i
		if far < 0 or (fd <= target and forced <= 0):
			return
		var near := StageGen.bfs(plan, [far])
		var best := -1
		var best_d := 1 << 30
		var cdirs: Array = StageGen.N4.duplicate()
		StageGen.shuffle(rng, cdirs)
		var best_dir := Vector2i.ZERO
		for i in near.size():
			if near[i] < 0 or near[i] > 12 or near[i] >= best_d:
				continue
			var x: int = i % plan.w
			var y: int = i / plan.w
			if plan.markers.has(i) or plan.prop_cells.has(i):
				continue
			for d in cdirs:
				if _alcove_ok(plan, x, y, d):
					best = i
					best_d = near[i]
					best_dir = d
					break
		if best < 0:
			if forced > 0:
				forced = 0
				continue
			skip[far] = true
			continue
		_carve_crevice(plan, rng, shelter, best % plan.w, best / plan.w, best_dir, made + 1)
		made += 1
		forced = 0


static func _alcove_ok(plan: StageGen.Plan, x: int, y: int, d: Vector2i) -> bool:
	var p := Vector2i(d.y, d.x)
	for k in [1, 2, 3]:
		var cx: int = x + d.x * k
		var cy: int = y + d.y * k
		if plan.tile(cx, cy) != 0 or not StageGen.can_carve(plan, cx, cy, 3):
			return false
		if plan.tile(cx + p.x, cy + p.y) != 0 or plan.tile(cx - p.x, cy - p.y) != 0:
			return false
	return true


static func _carve_crevice(plan: StageGen.Plan, rng: Rng, shelter: Dictionary, x: int, y: int, d: Vector2i, n: int) -> void:
	var a := Vector2i(x + d.x, y + d.y)
	var b := Vector2i(x + 2 * d.x, y + 2 * d.y)
	plan.tiles[a.y * plan.w + a.x] = 1
	plan.tiles[b.y * plan.w + b.x] = 1
	plan.markers[b.y * plan.w + b.x] = "S"
	for c in [a, b]:
		for dd in StageGen.N8:
			var px: int = c.x + dd.x
			var py: int = c.y + dd.y
			if plan.inb(px, py):
				plan.protect[py * plan.w + px] = 1
	var base: float = float(shelter["safety"]["crevice"])
	plan.rest.append({"cell": [b.x, b.y], "kind": "crevice", "marker": "S", "safety": base})
	var zn := "pocket_crevice_%d" % n
	plan.zones.append({"name": zn, "kind": "indoor", "x0": mini(a.x, b.x), "y0": mini(a.y, b.y), "x1": maxi(a.x, b.x), "y1": maxi(a.y, b.y)})
	plan.pockets.append({"zone": zn, "kind": "crevice", "rest": true, "cell": [b.x, b.y]})
	rng.next()


static func _free_cell(plan: StageGen.Plan, rng: Rng, c: Vector2i, r: int, open_min: int) -> Vector2i:
	for _t in 24:
		var x: int = c.x + StageGen.rint(rng, -r, r)
		var y: int = c.y + StageGen.rint(rng, -r, r)
		var i := y * plan.w + x
		if not plan.is_open(x, y) or plan.markers.has(i) or plan.prop_cells.has(i):
			continue
		if plan.start.x >= 0 and Vector2(x, y).distance_to(Vector2(plan.start)) < 4.0:
			continue
		var cnt := 0
		for d in StageGen.N8:
			if plan.is_open(x + d.x, y + d.y):
				cnt += 1
		if cnt >= open_min:
			return Vector2i(x, y)
	return Vector2i(-1, -1)


## Filler chambers get drips (stalactite + anchor), small stalagmites and an occasional glow-worm.
static func _decorate(plan: StageGen.Plan, rng: Rng, row: Dictionary, pts: Array, fillr: Dictionary, _role: Dictionary) -> void:
	var amb: Dictionary = row["ambient"]
	var dr: Array = amb["fillerDripsPerRoom"]
	var extra_gw: Array = amb["extraGlowworms"]
	var gw_left: int = StageGen.rint(rng, int(extra_gw[0]), int(extra_gw[1]))
	var nodes: Array = fillr.keys()
	nodes.sort()
	for i in nodes:
		var r: int = fillr[i]
		for _d in StageGen.rint(rng, int(dr[0]), int(dr[1])):
			var c := _free_cell(plan, rng, pts[i], r, 6)
			if c.x >= 0:
				plan.add_prop("stalactite", c.x, c.y)
				plan.add_anchor("drip", c.x, c.y)
		for _m in StageGen.rint(rng, 1, 2):
			var c2 := _free_cell(plan, rng, pts[i], r, 8)
			if c2.x >= 0:
				plan.add_prop("stalagmite", c2.x, c2.y)
		if gw_left > 0:
			var c3 := _free_cell(plan, rng, pts[i], r, 5)
			if c3.x >= 0:
				plan.add_prop("glowworm", c3.x, c3.y)
				gw_left -= 1
	var prey: Dictionary = row["preyCount"]
	var want: int = mini(StageGen.rint(rng, int(prey["min"]), int(prey["max"])), int(row["caps"]["critters"]))
	var guard := 0
	while plan.spawns.size() < want and guard < 40 and not nodes.is_empty():
		guard += 1
		var i2: int = nodes[guard % nodes.size()]
		var c4 := _free_cell(plan, rng, pts[i2], fillr[i2], 5)
		if c4.x >= 0:
			plan.spawns.append({"species": "rat", "cell": [c4.x, c4.y]})


static func _assemble(plan: StageGen.Plan, rng: Rng, row: Dictionary, seed: int, attempt: int, chunks: Dictionary, role: Dictionary, info: Dictionary, path: Array, order: Array, spur_ends: Array, loops: int) -> Dictionary:
	var shelter: Dictionary = row["shelter"]
	var exit_cfg: Dictionary = row["exit"]
	var rest: Array = []
	for r in plan.rest:
		var kind: String = r["kind"]
		var s: float = float(shelter["safety"].get(kind, r["safety"]))
		if kind != "coffin":
			s = clampf(s + (rng.next() - 0.5) * 0.1, 0.0, 1.0)
		rest.append({"cell": r["cell"], "kind": kind, "marker": r["marker"], "safety": snappedf(s, 0.01)})
	var doors: Array = []
	for d in plan.doors:
		doors.append({"id": exit_cfg["doorId"], "col": d["col"], "row": d["row"], "toMap": exit_cfg["toMap"], "toDoor": exit_cfg["toDoor"], "facing": d["facing"]})
	var door: Dictionary = doors[0] if not doors.is_empty() else {}
	var fv: Vector2i = StageGen.DIR_OF[door.get("facing", "s")]
	# beats in order; the spur beat sits between the pool and the warren
	var by_role := {}
	for node in role:
		by_role[role[node]] = node
	var beats: Array = []
	for b in order:
		if b == "rat_warren":
			beats.append({"id": "dead_end_spurs", "cell": [spur_ends[0].x, spur_ends[0].y]})
		var node: int = by_role[b]
		var bc: Vector2i = info[node]["beat_cell"]
		beats.append({"id": b, "cell": [bc.x, bc.y]})
	var places := {}
	for b in beats:
		places[b["id"]] = b["cell"]
	var lights: Array = []
	for p in plan.props:
		if p["type"] == "glowworm":
			lights.append({"cell": [p["col"], p["row"]], "radius": float(World.DEFAULT_LIGHT["glowworm"]), "kind": "glowworm"})
	var def := {
		"name": String(row["id"]),
		"kind": String(row["kind"]),
		"floor": String(row["floor"]),
		"materials": row["materials"].duplicate(),
		"rows": StageGen.rows_of(plan),
		"doors": doors,
		"props": plan.props,
		"zones": plan.zones,
		"paths": [],
		"hides": [],
		"places": places,
		"stage": String(row["id"]),
		"seed": seed,
		"start": {"cell": [plan.start.x, plan.start.y], "angle": PI / 2.0},
		"exit": {"door": door.get("id", ""), "cell": [door.get("col", 0), door.get("row", 0)], "arrival": [int(door.get("col", 0)) + fv.x, int(door.get("row", 0)) + fv.y], "toMap": exit_cfg["toMap"]},
		"beats": beats,
		"rest": rest,
		"pockets": plan.pockets,
		"ambient": plan.anchors,
		"critters": plan.spawns,
		"lights": lights,
		"gen": {"attempt": attempt, "loops": loops, "spurs": spur_ends.size(), "nodes": path.size()},
	}
	return def
