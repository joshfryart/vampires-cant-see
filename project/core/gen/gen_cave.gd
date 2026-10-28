class_name GenCave
extends RefCounted
## The Hollow (stage 1): seeded cave from authored beat chunks (data/rogue/chunks.json) plus cellular-automaton filler chambers.
## Pipeline per attempt (an attempt that breaks a constraint is discarded and the next attempt uses a derived seed, so the result
## is still a pure function of the seed):
##   1 layout: the chain of 7 beat chunks (coffin nook ... cave mouth) is walked out first, then 1-2 filler chambers (8-9 nodes in all);
##     tree = MST of the node centres with the chain edges forced, so the tree path start -> exit is the beat order (order by depth).
##     The brief form (repeat runs, generate(..., brief = true)) keeps the 7 beat chunks only: no fillers, so a pure beat chain; since
##     0.22.0 its beats may also use a second authored chunk (variant_pick, per seed) and its breadcrumb trail must be clean (_crumbs_clean)
##   2 stamp the chunks (rect protected from later carving), CA blobs for fillers, one small loop through a filler, biased drunk-walk
##     tunnels of width 1-2 between chunk ports
##   3 2-3 blind spurs (end = hidden rest spot), growth towards a target open fraction, prune floor the start cannot reach
##   4 crevice alcoves until every walkable cell is near a rest spot, decoration, critters, def assembly, StageGen.analyze + WorldValidate

const MAX_ATTEMPTS := 200
const FILLER_GAP := 2
## Greatest distance between the centres of two consecutive beat chunks: the first-run cave, and the brief (repeat-run) cave, whose beats
## sit closer together so the walk from the coffin to the mouth is shorter.
const CHAIN_REACH := 22
const BRIEF_REACH := 18

static var last_attempts: int = 0
## Why attempts were rejected, by reason key (diagnostics only; not part of the def).
static var fails: Dictionary = {}


static func _fail(k: String) -> Dictionary:
	fails[k] = int(fails.get(k, 0)) + 1
	return {}


## brief = the repeat-run Hollow: the beat chain alone (no filler chambers, so no filler loop, filler drips or filler rats). brief = false is
## the first-run layout, bit-identical to the generator before the flag existed (same chunks, same rng draws in the same order): the guided
## first night always teaches in the authored cave.
## variants (0.22.0, brief only): each beat that has alternative chunks (chunks.json "variants") uses the one variant_pick chose for this seed,
## and the attempt must also lay a clean breadcrumb trail (_crumbs_clean). variants = false is the 0.21.8-0.21.9 brief cave, byte-identical,
## kept so a repeat-run checkpoint saved before 0.22.0 (no night.trek "variants" key) continues in the cave it was saved in.
static func generate(row: Dictionary, seed: int, brief: bool = false, variants: Variant = VARIANT_LEVEL) -> Dictionary:
	var data := StageGen.chunks()
	if data.is_empty():
		return {}
	var level := int(variants)   # false 0, true 1 (the four 0.22.0 beats), 2 (all seven)
	var strict: bool = brief and level > 0
	var pick := variant_pick(String(row.get("id", "")), seed, brief, level) if level > 0 else {}
	var def := _attempts(row, with_variants(data, pick), seed, brief, strict)
	if not def.is_empty() or pick.is_empty():
		if not def.is_empty() and strict:
			def["gen"]["variants"] = pick
		return def
	# a variant set that never fits (not seen over the tested seeds) falls back to the authored chunks, so a seed still always has a cave
	def = _attempts(row, data, seed, brief, strict)
	if not def.is_empty():
		def["gen"]["variants"] = {}
	return def


static func _attempts(row: Dictionary, data: Dictionary, seed: int, brief: bool, strict: bool = false) -> Dictionary:
	for attempt in MAX_ATTEMPTS:
		var rng := Rng.new(StageGen.seed_for(seed, attempt))
		var def := _attempt(row, data, rng, seed, attempt, brief, strict)
		if not def.is_empty():
			last_attempts = attempt + 1
			return def
	last_attempts = MAX_ATTEMPTS
	return {}


## Salt for the variant draw (its own rng stream, so picking variants never shifts the layout rng).
const VARIANT_SALT := 0x5EED7A
## Chance that a beat with alternatives uses one of them (each alternative equally likely) instead of its authored chunk.
const VARIANT_CHANCE := 0.5
## Variant levels: 1 = the beats that had variants at 0.22.0 (draws unchanged, so a 0.22.0 checkpoint keeps its cave), 2 = also the squeeze, rat warren
## and cave mouth (0.22.1). New treks use VARIANT_LEVEL and save it.
const VARIANT_LEVEL := 2
const VARIANT_V1_BEATS := ["coffin_nook", "drip_gallery", "echo_hall", "still_pool"]


## Which chunk variant each beat uses: {beat id: chunk name} for every beat that has alternatives in chunks.json "variants" (the authored
## chunk's own name when it was kept). A pure function of (stage id, seed, brief) on its own rng stream. Empty for the first run
## (brief = false): the guided night's cave never varies its chunks, so its layout stays byte-identical to the one the tutorial was tuned on.
static func variant_pick(stage_id: String, seed: int, brief: bool, level: int = VARIANT_LEVEL) -> Dictionary:
	if not brief:
		return {}
	var vars: Dictionary = StageGen.chunks().get("variants", {})
	if vars.is_empty():
		return {}
	var rng := Rng.new(StageGen.seed_for((seed ^ stage_id.hash()) & JsMath.M32, VARIANT_SALT))
	var out := {}
	for b in StageGen.chunks()["order"]:
		if not vars.has(b) or (level < 2 and not VARIANT_V1_BEATS.has(b)):
			continue
		var alts: Array = vars[b]
		var r := rng.next()
		out[b] = b
		if r < VARIANT_CHANCE and not alts.is_empty():
			out[b] = String(alts[mini(alts.size() - 1, int(floor(r / VARIANT_CHANCE * float(alts.size()))))])
	return out


## The chunk data with each picked beat's chunk swapped for its variant (a shallow copy; the shared chunks.json data is not touched).
## The variant keeps the beat id, so roles, zones, beats and the tutorial all still speak of the beat by its name.
static func with_variants(data: Dictionary, pick: Dictionary) -> Dictionary:
	if pick.is_empty():
		return data
	var chunks: Dictionary = (data["chunks"] as Dictionary).duplicate()
	for b in pick:
		var nm: String = pick[b]
		if nm != b and chunks.has(nm):
			chunks[b] = chunks[nm]
	var out := data.duplicate()
	out["chunks"] = chunks
	return out


static func _attempt(row: Dictionary, data: Dictionary, rng: Rng, seed: int, attempt: int, brief: bool = false, strict: bool = false) -> Dictionary:
	var sz: Dictionary = row["size"]
	var w: int = int(sz["w"])
	var h: int = int(sz["h"])
	var chunks: Dictionary = data["chunks"]
	var legend: Dictionary = data["legend"]
	var order: Array = data["order"]
	var nodes_cfg: Dictionary = row["nodes"]
	var n: int = StageGen.rint(rng, int(nodes_cfg["min"]), int(nodes_cfg["max"]))
	if brief:
		n = order.size()   # the draw above still happens, so both forms consume the rng alike up to here

	# 1+2 layout: the beat chain is walked out first (each chunk rect fits, gap for tunnels), then fillers; the MST of all centres must
	# contain every chain edge, so the tree path from the first to the last beat is the main path in order.
	var lay: Dictionary = {}
	for _l in 6:
		lay = _layout(rng, w, h, n, order, chunks, BRIEF_REACH if brief else CHAIN_REACH)
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
	var crumb_from: Array = []   # per chain edge: [beat node, first tunnel cell leaving it] (the glow-worm breadcrumb trail)
	var loops := _pick_loop(rng, pts, edges, adj, path, role, order, n)
	for l in loops:
		all_edges.append(l)
	var chain_n: int = path.size() - 1
	for ei in all_edges.size():
		var e: Array = all_edges[ei]
		var a: int = e[0]
		var b: int = e[1]
		var sa := _endpoint(info, pts, a, pts[b])
		var sb := _endpoint(info, pts, b, pts[a])
		var width: int = StageGen.rint(rng, 1, 2)
		if ei < chain_n:
			# funnel: the tunnel that leads on from a beat is always 2 wide (spurs stay 1 wide), so the true way reads as the broad one
			width = 2
			crumb_from.append([a, sa])
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
	# the squeeze is the only way from the first half to the echo hall: with its rect blocked the hall must be unreachable (growth, loops and
	# wandering tunnels used to open bypasses in about one seed in six)
	if not _squeeze_gates(plan, rects, role, info):
		return _fail("r12")
	# 5 crevices until the rest-distance target holds
	_cover(plan, rng, row)
	_decorate(plan, rng, row, pts, fillr, role)
	_squeeze_anchor(plan, rects, role)
	_measure_zones(plan, rects, role)
	var def := _assemble(plan, rng, row, seed, attempt, chunks, role, info, path, order, spur_ends, loops.size(), crumb_from, rects)
	if def.is_empty():
		return _fail("r11")
	if not _spur_clear_of_beats(def):
		return _fail("r14")
	if strict and not _crumbs_clean(plan, def):
		return _fail("r13")
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
	if brief:
		# only the short form carries these keys, so a first-run def is unchanged to the byte
		def["gen"]["brief"] = true
		def["gen"]["fillers"] = fillr.size()
	return def


## The tutorial's "dead end" step fires within 4.5 cells of the spur mouth or a spur rest spot, so in the compact Hollow no main-path beat
## may sit that close, or the hint would fire before the beat it belongs after.
const SPUR_BEAT_GAP := 6.0


static func _spur_clear_of_beats(def: Dictionary) -> bool:
	var spot: Array = []
	for b in def["beats"]:
		if b["id"] == "dead_end_spurs":
			spot.append(Vector2(float(b["cell"][0]) + 0.5, float(b["cell"][1]) + 0.5))
	for r in def.get("rest", []):
		if String(r.get("kind", "")) == "spur":
			spot.append(Vector2(float(r["cell"][0]) + 0.5, float(r["cell"][1]) + 0.5))
	for b in def["beats"]:
		if b["id"] == "dead_end_spurs":
			continue
		var bc := Vector2(float(b["cell"][0]) + 0.5, float(b["cell"][1]) + 0.5)
		for p in spot:
			if bc.distance_to(p) < SPUR_BEAT_GAP:
				return false
	return true


## Walk out the chain of chunk rects (each rect fits the map, keeps a gap for tunnels and lies within reach of the previous one), then the
## fillers. Candidate centres are enumerated on a 2-cell lattice and one is picked at random; a node with no candidate (or whose successors
## cannot be placed) backtracks into up to 3 alternative picks of the node before it, within a fixed expansion budget. Returns {} on failure.
static func _layout(rng: Rng, w: int, h: int, n: int, order: Array, chunks: Dictionary, reach: int = CHAIN_REACH) -> Dictionary:
	var st := {"pts": [], "rects": {}, "xform": {}, "fillr": {}, "role": {}, "path": [], "budget": 80, "bounds": Rect2i(3, 3, w - 6, h - 6), "reach": reach}
	if not _place(rng, 0, n, order, chunks, st):
		return {}
	return {"pts": st["pts"], "rects": st["rects"], "xform": st["xform"], "fillr": st["fillr"], "role": st["role"], "path": st["path"]}


static func _place(rng: Rng, k: int, n: int, order: Array, chunks: Dictionary, st: Dictionary) -> bool:
	if k >= n:
		return true
	var bounds: Rect2i = st["bounds"]
	var reach: int = int(st["reach"])
	var pts: Array = st["pts"]
	var rects: Dictionary = st["rects"]
	var is_chunk: bool = k < order.size()
	var ch: Dictionary = chunks[order[k]] if is_chunk else {}
	var r: int = 0 if is_chunk else StageGen.rint(rng, 4, 5)
	var tr_opts: Array = [false]
	if is_chunk and ch.get("transpose", false) and k > 0:
		tr_opts = [false, true]
	var cands: Array = []
	var grown: Array = []
	for q in rects.values():
		grown.append([q.position.x, q.position.y, q.end.x, q.end.y])
	for tr in tr_opts:
		var s: Vector2i = StageGen.chunk_size(ch, tr) if is_chunk else Vector2i(2 * r + 1, 2 * r + 1)
		# chunks must lie within `reach` cells of the previous centre: scan only that window (same lattice, same candidate order as a full scan)
		var ylo: int = bounds.position.y
		var yhi: int = bounds.end.y
		var xlo: int = bounds.position.x
		var xhi: int = bounds.end.x
		if is_chunk and k > 0:
			var pc: Vector2i = pts[k - 1]
			ylo = maxi(ylo, pc.y - reach - s.y / 2 - 1)
			yhi = mini(yhi, pc.y + reach - s.y / 2 + s.y + 1)
			xlo = maxi(xlo, pc.x - reach - s.x / 2 - 1)
			xhi = mini(xhi, pc.x + reach - s.x / 2 + s.x + 1)
		var y := bounds.position.y + 2 * int(ceil(float(ylo - bounds.position.y) / 2.0))
		while y + s.y <= yhi:
			var x := bounds.position.x + ((y / 2) % 2)
			if x < xlo:
				x += 2 * int(ceil(float(xlo - x) / 2.0))
			while x + s.x <= xhi:
				var ok := true
				for q in grown:
					# rc.grow(FILLER_GAP).intersects(q), written out on ints (this is the hot loop of the layout)
					if x - FILLER_GAP < q[2] and x + s.x + FILLER_GAP > q[0] and y - FILLER_GAP < q[3] and y + s.y + FILLER_GAP > q[1]:
						ok = false
						break
				if ok and k > 0 and (is_chunk or k >= order.size()):
					var c := Vector2(x + s.x / 2, y + s.y / 2)
					if is_chunk:
						if Vector2(pts[k - 1]).distance_to(c) > float(reach):
							ok = false
					else:
						var best := 1.0e9
						for p in pts:
							best = minf(best, Vector2(p).distance_to(c))
						if best > 22.0:
							ok = false
				if ok:
					cands.append([Rect2i(x, y, s.x, s.y), tr])
				x += 2
			y += 2
	var tries: int = mini(3, cands.size())
	for _t in tries:
		if int(st["budget"]) <= 0:
			return false
		st["budget"] = int(st["budget"]) - 1
		var ix: int = int(floor(rng.next() * float(cands.size())))
		var pick: Array = cands[ix]
		cands.remove_at(ix)
		var rect: Rect2i = pick[0]
		pts.append(Vector2i(rect.position.x + rect.size.x / 2, rect.position.y + rect.size.y / 2))
		rects[k] = rect
		if is_chunk:
			var fl: bool = ch.get("flip", false) and rng.next() < 0.5
			st["xform"][k] = [pick[1], fl]
			st["role"][k] = order[k]
			st["path"].append(k)
		else:
			st["fillr"][k] = r
		if _place(rng, k + 1, n, order, chunks, st):
			return true
		pts.pop_back()
		rects.erase(k)
		st["xform"].erase(k)
		st["role"].erase(k)
		st["fillr"].erase(k)
		if is_chunk:
			st["path"].pop_back()
	return false


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


## True when the echo hall cannot be reached from the start without crossing the squeeze rect (the rect is blocked in a throw-away copy).
static func _squeeze_gates(plan: StageGen.Plan, rects: Dictionary, role: Dictionary, info: Dictionary) -> bool:
	var sq := -1
	var hall := -1
	for n in role:
		if role[n] == "squeeze":
			sq = n
		elif role[n] == "echo_hall":
			hall = n
	if sq < 0 or hall < 0:
		return true
	var blocked := StageGen.Plan.new(plan.w, plan.h)
	blocked.tiles = plan.tiles.duplicate()
	var rc: Rect2i = rects[sq]
	for y in range(rc.position.y, rc.end.y):
		for x in range(rc.position.x, rc.end.x):
			blocked.tiles[y * plan.w + x] = 0
	var hc: Vector2i = info[hall]["beat_cell"]
	return StageGen.bfs(blocked, [plan.idx(plan.start.x, plan.start.y)])[hc.y * plan.w + hc.x] < 0


## One quiet drip at the far end of the squeeze (the end with the greater walking depth from the start), so the corridor has a distant sound
## to steer by. Placed 1 cell inside the far port.
static func _squeeze_anchor(plan: StageGen.Plan, rects: Dictionary, role: Dictionary) -> void:
	var node := -1
	for n in role:
		if role[n] == "squeeze":
			node = n
	if node < 0 or plan.start.x < 0:
		return
	var rc: Rect2i = rects[node]
	var dist := StageGen.bfs(plan, [plan.idx(plan.start.x, plan.start.y)])
	var mx := -1
	for y in range(rc.position.y, rc.end.y):
		for x in range(rc.position.x, rc.end.x):
			mx = maxi(mx, dist[y * plan.w + x])
	if mx < 2:
		return
	for y in range(rc.position.y, rc.end.y):
		for x in range(rc.position.x, rc.end.x):
			var i := y * plan.w + x
			if dist[i] == mx - 1 and not plan.markers.has(i) and not plan.prop_cells.has(i):
				plan.add_anchor("drip", x, y)
				return


## Zones are measured from the carved cave instead of the template rectangles: every beat zone becomes the bounding box of the open cells
## in its chunk plus the open cells (tunnel mouths, widened ground) connected to them within 2 cells outside the rect, never entering another
## chunk. The squeeze stays tight (its 1-wide length is the beat). The apron is an `outdoor` zone (the sun rule uses World.kind_at), all
## other zones stay indoor. Acoustics T60 is looked up by zone name, so the echo hall keeps its 2.2 s whatever its measured size.
static func _measure_zones(plan: StageGen.Plan, rects: Dictionary, role: Dictionary) -> void:
	var by_name := {}
	for n in role:
		by_name[role[n]] = n
	var apron := Rect2i()
	for z in plan.zones:
		if String(z["name"]) == "cave_apron":
			apron = Rect2i(int(z["x0"]), int(z["y0"]), int(z["x1"]) - int(z["x0"]) + 1, int(z["y1"]) - int(z["y0"]) + 1)
	for z in plan.zones:
		if String(z["name"]) == "cave_apron":
			z["kind"] = "outdoor"
			continue
		if not by_name.has(z["name"]) or z["name"] == "squeeze":
			continue
		var own: int = by_name[z["name"]]
		var zr := Rect2i(int(z["x0"]), int(z["y0"]), int(z["x1"]) - int(z["x0"]) + 1, int(z["y1"]) - int(z["y0"]) + 1)
		var lim := zr.grow(2)
		var seen := {}
		var q: Array = []
		for y in range(zr.position.y, zr.end.y):
			for x in range(zr.position.x, zr.end.x):
				if plan.tile(x, y) != 0:
					seen[y * plan.w + x] = true
					q.append(Vector2i(x, y))
		if q.is_empty():
			continue
		var qi := 0
		while qi < q.size():
			var c: Vector2i = q[qi]
			qi += 1
			for d in StageGen.N4:
				var nc: Vector2i = c + d
				var ni: int = nc.y * plan.w + nc.x
				if seen.has(ni) or not lim.has_point(nc) or plan.tile(nc.x, nc.y) == 0:
					continue
				var foreign: bool = apron.has_point(nc)
				for k in rects:
					if k != own and rects[k].has_point(nc):
						foreign = true
				if foreign:
					continue
				seen[ni] = true
				q.append(nc)
		var x0 := 1 << 20
		var y0 := 1 << 20
		var x1 := -1
		var y1 := -1
		for c in q:
			x0 = mini(x0, c.x)
			y0 = mini(y0, c.y)
			x1 = maxi(x1, c.x)
			y1 = maxi(y1, c.y)
		z["x0"] = x0
		z["y0"] = y0
		z["x1"] = x1
		z["y1"] = y1
	# zone rectangles are painted in list order (later wins): the outdoor apron goes last so no widened bounding box can roof it over
	for k in plan.zones.size():
		if String(plan.zones[k]["name"]) == "cave_apron":
			plan.zones.append(plan.zones.pop_at(k))
			break


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
	# the tell: a stalactite over the mouth (the dull dead-air drip anchor is added by _spur_tells once the zones are measured)
	plan.add_prop("stalactite", start.x, start.y)
	var end: Vector2i = cells[cells.size() - 1]
	plan.markers[end.y * plan.w + end.x] = "S"
	plan.rest.append({"cell": [end.x, end.y], "kind": "spur", "marker": "S", "safety": 0.8})
	var prev: Vector2i = cells[maxi(0, cells.size() - 2)]
	plan.zones.append({"name": "pocket_spur_%d" % (idx + 1), "kind": "indoor", "x0": mini(end.x, prev.x), "y0": mini(end.y, prev.y), "x1": maxi(end.x, prev.x), "y1": maxi(end.y, prev.y)})
	plan.pockets.append({"zone": "pocket_spur_%d" % (idx + 1), "kind": "spur", "rest": true, "cell": [end.x, end.y], "mouth": [start.x, start.y]})
	return end


## Dead-air anchor of each spur: a `drip` anchor flagged `dead` (a muffled drip; ambient.json has no dedicated kind, W1 can lower the gain of
## dead anchors) on the first spur cell, from the third on, that lies in no measured beat zone, so the per-zone anchor counts stay as designed.
## The spur is a 1-wide corridor, so it is followed cell by cell from its mouth.
static func _spur_tells(plan: StageGen.Plan) -> void:
	for pk in plan.pockets:
		if pk.get("kind") != "spur":
			continue
		var cur := Vector2i(int(pk["mouth"][0]), int(pk["mouth"][1]))
		var end := Vector2i(int(pk["cell"][0]), int(pk["cell"][1]))
		var prev := Vector2i(-99, -99)
		var cells: Array = [cur]
		while cur != end and cells.size() < 40:
			var nxt := Vector2i(-99, -99)
			for d in StageGen.N4:
				var n: Vector2i = cur + d
				if n != prev and plan.walkable(n.x, n.y):
					nxt = n
					break
			if nxt.x == -99:
				break
			prev = cur
			cur = nxt
			cells.append(cur)
		var pick: Vector2i = cells[mini(2, cells.size() - 1)]
		for k in range(2, cells.size()):
			var inside := false
			for z in plan.zones:
				if not String(z["name"]).begins_with("pocket_") and cells[k].x >= int(z["x0"]) and cells[k].x <= int(z["x1"]) and cells[k].y >= int(z["y0"]) and cells[k].y <= int(z["y1"]):
					inside = true
					break
			if not inside:
				pick = cells[k]
				break
		plan.anchors.append({"cell": [pick.x, pick.y], "kind": "drip", "dead": true})


## Glow-worm breadcrumbs: one glow-worm prop on the tunnel that leads on from each main-path beat (all but the last), CRUMB_DEPTH cells past
## the cell just outside the chunk port, never inside a chunk rect, on a free walkable cell and more than CRUMB_SPUR_GAP cells (Chebyshev)
## from every spur mouth. A trail cell is taken at the preferred depth first, then deeper, then shallower. Returns the cells in beat order
## (shorter than crumb_from when a beat has no spot, which fails the attempt); def.gen.crumbs carries them.
const CRUMB_DEPTH := 2
const CRUMB_SPUR_GAP := 3


static func _breadcrumbs(plan: StageGen.Plan, crumb_from: Array, rects: Dictionary) -> Array:
	var mouths: Array = []
	for pk in plan.pockets:
		if pk.get("kind") == "spur":
			mouths.append(Vector2i(int(pk["mouth"][0]), int(pk["mouth"][1])))
	var out: Array = []
	var taken := {}
	for sp in plan.spawns:
		taken[int(sp["cell"][1]) * plan.w + int(sp["cell"][0])] = true
	for an in plan.anchors:
		taken[int(an["cell"][1]) * plan.w + int(an["cell"][0])] = true
	var from_start := StageGen.bfs(plan, [plan.idx(plan.start.x, plan.start.y)])
	for cf in crumb_from:
		var start: Vector2i = cf[1]
		# walk on along the shortest paths from the start (each step is one deeper), so the trail always leads onward, never back
		var seen := {start.y * plan.w + start.x: 0}
		var q: Array = [start]
		var qi := 0
		var by_depth := {}   # depth -> [best cell, its open neighbour count]
		while qi < q.size():
			var c: Vector2i = q[qi]
			qi += 1
			var ci: int = c.y * plan.w + c.x
			var dc: int = seen[ci]
			if plan.walkable(c.x, c.y) and not plan.markers.has(ci) and not plan.prop_cells.has(ci) and not taken.has(ci):
				var near_spur := false
				for m in mouths:
					if maxi(absi(m.x - c.x), absi(m.y - c.y)) <= CRUMB_SPUR_GAP:
						near_spur = true
				if not near_spur:
					var open := 0
					for d in StageGen.N8:
						if plan.walkable(c.x + d.x, c.y + d.y):
							open += 1
					if not by_depth.has(dc) or open > int(by_depth[dc][1]):
						by_depth[dc] = [c, open]
			if dc >= 8:
				continue
			for d in StageGen.N4:
				var nc: Vector2i = c + d
				var ni: int = nc.y * plan.w + nc.x
				if seen.has(ni) or not plan.walkable(nc.x, nc.y) or from_start[ni] != from_start[ci] + 1:
					continue
				var inside := false
				for k in rects:
					if rects[k].has_point(nc):
						inside = true
						break
				if inside:
					continue
				seen[ni] = dc + 1
				q.append(nc)
		# preferred depth first, then deeper, then shallower; a spot in a 2-wide stretch (>= 3 open neighbours) beats one in a 1-wide stretch
		var try_order: Array = [CRUMB_DEPTH, 3, 4, 5, 6, 7, 8, 1, 0]
		var pick := Vector2i(-1, -1)
		for want in [3, 0]:
			for dd in try_order:
				if by_depth.has(dd) and int(by_depth[dd][1]) >= want:
					pick = by_depth[dd][0]
					break
			if pick.x >= 0:
				break
		if pick.x < 0:
			return out
		plan.add_prop("glowworm", pick.x, pick.y)
		taken[pick.y * plan.w + pick.x] = true
		out.append([pick.x, pick.y])
	return out


## Strict breadcrumb acceptance (brief caves with variants, 0.22.0): every crumb lies deeper than the crumb before it and past the beat before
## its own (so the trail never points back), on a cell with at least 3 walkable neighbours (a funnelled 2-wide stretch, not a 1-wide
## pinch). _breadcrumbs only prefers these; about 2% of seeds miss them (first-run seeds keep that for byte-identity; see CAVE_ITERATIONS.md).
static func _crumbs_clean(plan: StageGen.Plan, def: Dictionary) -> bool:
	var dist := StageGen.bfs(plan, [plan.idx(plan.start.x, plan.start.y)])
	var crumbs: Array = def["gen"]["crumbs"]
	var beats: Array = def["beats"]
	var last := -1
	for k in crumbs.size():
		var c: Array = crumbs[k]
		var dc: int = dist[plan.idx(int(c[0]), int(c[1]))]
		if dc <= last:
			return false
		if k > 0 and dc <= dist[plan.idx(int(beats[k - 1]["cell"][0]), int(beats[k - 1]["cell"][1]))]:
			return false
		last = dc
		var open := 0
		for d in StageGen.N8:
			if plan.walkable(int(c[0]) + d.x, int(c[1]) + d.y):
				open += 1
		if open < 3:
			return false
	return true


static func _clear_around(plan: StageGen.Plan, c: Vector2i, allowed: Dictionary, pending: Dictionary = {}) -> bool:
	for d in StageGen.N8:
		var x: int = c.x + d.x
		var y: int = c.y + d.y
		if pending.has(y * plan.w + x) and not allowed.has(y * plan.w + x):
			return false
		if plan.tile(x, y) != 0 and not allowed.has(y * plan.w + x):
			return false
	return true


## Walkable mask for the BFS helpers below (floor that is not a solid prop); the border ring is wall so index arithmetic never wraps.
static func _walk_mask(plan: StageGen.Plan) -> PackedByteArray:
	var ok := PackedByteArray()
	ok.resize(plan.w * plan.h)
	for i in ok.size():
		ok[i] = 1 if plan.tiles[i] == 1 else 0
	for k in plan.prop_cells:
		if StageGen.SOLID_PROPS.has(plan.prop_cells[k]):
			ok[k] = 0
	return ok


## Incremental multi-source BFS: lowers `dist` (-1 = unreached) to the walking distance from `srcs`, expanding only where that improves it
## and not past `limit`. On a fresh -1 array it is a plain BFS (same result as StageGen.bfs), so adding one rest spot costs a local update
## instead of a whole-map pass.
static func _spread(ok: PackedByteArray, dist: PackedInt32Array, w: int, srcs: Array, limit: int = 1 << 30) -> void:
	var queue: Array = []
	for s in srcs:
		if dist[s] != 0:
			dist[s] = 0
			queue.append(s)
	var head := 0
	while head < queue.size():
		var cur: int = queue[head]
		head += 1
		var nd: int = dist[cur] + 1
		if nd > limit:
			continue
		for nb in [cur - 1, cur + 1, cur - w, cur + w]:
			if ok[nb] == 1 and (dist[nb] < 0 or dist[nb] > nd):
				dist[nb] = nd
				queue.append(nb)


## Crevice alcoves (2 cells deep, 1 wide, dead end) until the farthest walkable cell is within restTarget of a rest spot.
static func _cover(plan: StageGen.Plan, rng: Rng, row: Dictionary) -> void:
	var shelter: Dictionary = row["shelter"]
	var target: int = int(shelter["restTarget"])
	var extra: int = int(shelter["maxExtraCrevices"])
	var made := 0
	var skip := {}
	# always at least one crevice so the stage has a rest spot that is not a chunk or spur
	var forced := 1
	var ok := _walk_mask(plan)
	var n: int = plan.w * plan.h
	var dist := PackedInt32Array()
	dist.resize(n)
	dist.fill(-1)
	var srcs: Array = []
	for r in plan.rest:
		srcs.append(plan.idx(r["cell"][0], r["cell"][1]))
	_spread(ok, dist, plan.w, srcs)
	while made < extra:
		var far := -1
		var fd := -1
		for i in n:
			if dist[i] > fd and not skip.has(i):
				fd = dist[i]
				far = i
		if far < 0 or (fd <= target and forced <= 0):
			return
		var near := PackedInt32Array()
		near.resize(n)
		near.fill(-1)
		_spread(ok, near, plan.w, [far], 12)
		var best := -1
		var best_d := 1 << 30
		var cdirs: Array = StageGen.N4.duplicate()
		StageGen.shuffle(rng, cdirs)
		var best_dir := Vector2i.ZERO
		for i in n:
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
		var cb: Vector2i = Vector2i(best % plan.w, best / plan.w) + best_dir * 2
		var ca: Vector2i = Vector2i(best % plan.w, best / plan.w) + best_dir
		ok[ca.y * plan.w + ca.x] = 1
		ok[cb.y * plan.w + cb.x] = 1
		_spread(ok, dist, plan.w, [cb.y * plan.w + cb.x])
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


static func _assemble(plan: StageGen.Plan, rng: Rng, row: Dictionary, seed: int, attempt: int, chunks: Dictionary, role: Dictionary, info: Dictionary, path: Array, order: Array, spur_ends: Array, loops: int, crumb_from: Array = [], rects: Dictionary = {}) -> Dictionary:
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
	# beats: the main path in teaching order (strictly increasing walking depth, checked by StageGen.analyze), then the optional side beat
	# dead_end_spurs (off the path, flagged "optional", excluded from the order check; its cell is the first spur cell, i.e. its mouth on the
	# path, and "end" is the hidden rest spot). Tutorial hints (RogueMode.BEAT_HINTS) fire within 4 cells of a beat cell: squeeze -> "squeeze"
	# and cave_mouth -> "sun" lie on the main path in that depth order, dead_end_spurs -> "dead_end" only fires when the player walks past the
	# mouth of a spur, so no hint can fire before its beat is reachable and the two path hints cannot invert.
	var by_role := {}
	for node in role:
		by_role[role[node]] = node
	var beats: Array = []
	for b in order:
		var node: int = by_role[b]
		var bc: Vector2i = info[node]["beat_cell"]
		beats.append({"id": b, "cell": [bc.x, bc.y]})
	if not spur_ends.is_empty():
		var sm: Array = [spur_ends[0].x, spur_ends[0].y]
		for pk in plan.pockets:
			if pk.get("kind") == "spur" and pk["cell"] == sm:
				sm = pk["mouth"]
		beats.append({"id": "dead_end_spurs", "cell": sm, "end": [spur_ends[0].x, spur_ends[0].y], "optional": true})
	var places := {}
	for b in beats:
		places[b["id"]] = b["cell"]
	var crumbs := _breadcrumbs(plan, crumb_from, rects)
	if crumbs.size() != crumb_from.size():
		return {}
	_spur_tells(plan)
	var lights: Array = []
	for p in plan.props:
		if p["type"] == "glowworm":
			lights.append({"cell": [p["col"], p["row"]], "radius": float(World.DEFAULT_LIGHT["glowworm"]), "kind": "glowworm"})
	var def := {
		"name": String(row["id"]),
		"kind": String(row["kind"]),
		"floor": String(row["floor"]),
		"materials": row["materials"].duplicate(),
		"wallStyle": row.get("wallStyle", {}),
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
		"gen": {"attempt": attempt, "loops": loops, "spurs": spur_ends.size(), "nodes": path.size(), "crumbs": crumbs},
	}
	return def
