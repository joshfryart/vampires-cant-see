class_name GenRoad
extends RefCounted
## Stages 4 and 5 of the trek (WP13b, docs/ROGUELIKE.md "Road stages"), one file for both kinds:
##   road  The Old Road: a long winding east-west cobbled road with grass verges, field edges, `I` fence posts, `B` milestones, ditches (`~`), a wayside
##         shrine (prop `shrine` in a 5x5 alcove; the 3x3 around it is a zone of kind `holy`, which drains blood: TrekFlow.HOLY_DPS), covered pockets
##         (wayside crypt, culvert, bramble hollow), travellers (a pilgrim pair, a carter) and two watchers walking short posts. Cart rumble, shrine bell.
##   inn   Crossroads Inn: an outdoor yard with the timber inn (common room, kitchen, cellar), a stable and a woodshed. Patrons live schedules (innkeeper,
##         drunk, regulars, merchant) or sit at the tables; hearth, singing. Pockets: cellar (hostile owner: safety 0.4), stable, woodshed, the common room.
## Both are pure functions of (stage id, seed), 64x48, enter on the west edge and leave on the east edge, and keep the open-air rule R = 5 (every
## walkable cell has a wall cell within 5; GenRoad.open_air_max is the exact check). Hunters are not spawned here: TrekFlow / RogueMode do that.

const MAX_ATTEMPTS := 60
const OPEN_R := 5.0
const COVER_R := 5.0
const G_GRASS := 0
const G_COBBLE := 1
const G_WOOD := 2
## road pocket kind -> the GenWild pocket shape/wall it is stamped with
const UNDER := {"wayside_crypt": "barrow", "culvert": "peat_cut", "bramble_hollow": "hollow_tree"}
const SOLID_LIGHT := {"torch": 3.0, "brazier": 3.5, "glowworm": 1.5}

static var last_attempts: int = 0
static var fails: Dictionary = {}


class RP:
	extends GenWild.WP
	var ground := PackedByteArray()
	var places: Dictionary = {}
	var people: Array = []   # {cell: Vector2i, def: Dictionary}

	func _init(w_: int, h_: int, g0: int = 0) -> void:
		super._init(w_, h_)
		ground.resize(w_ * h_)
		ground.fill(g0)


static func _fail(k: String) -> Dictionary:
	fails[k] = int(fails.get(k, 0)) + 1
	return {}


static func generate(row: Dictionary, seed: int, style: String) -> Dictionary:
	for attempt in MAX_ATTEMPTS:
		var rng := Rng.new(StageGen.seed_for(seed, attempt))
		var def: Dictionary = _road(row, rng, seed, attempt) if style == "road" else _inn(row, rng, seed, attempt)
		if not def.is_empty():
			last_attempts = attempt + 1
			return def
	last_attempts = MAX_ATTEMPTS
	return {}


# ---- shared helpers -------------------------------------------------------------------------------------------------------------------------

static func _base(row: Dictionary, g0: int) -> RP:
	var sz: Dictionary = row["size"]
	var plan := RP.new(int(sz["w"]), int(sz["h"]), g0)
	for y in range(1, plan.h - 1):
		for x in [1, 2, plan.w - 3, plan.w - 2]:
			plan.protect[y * plan.w + x] = 1
	return plan


static func _open(plan: RP, x: int, y: int, ground: int) -> void:
	var i: int = y * plan.w + x
	plan.tiles[i] = 1
	plan.wall[i] = 0
	plan.ground[i] = ground


static func _wall(plan: RP, x: int, y: int, ch: int) -> void:
	var i: int = y * plan.w + x
	plan.tiles[i] = 0
	plan.wall[i] = 0 if ch == 35 else ch
	plan.prop_cells.erase(i)


static func _doors(plan: RP, row: Dictionary, ey: int, xy: int) -> void:
	plan.doors.append({"id": row["entry"]["doorId"], "col": 2, "row": ey, "facing": "e"})
	plan.doors.append({"id": row["exit"]["doorId"], "col": plan.w - 3, "row": xy, "facing": "w"})
	plan.start = Vector2i(3, ey)
	plan.markers[plan.idx(3, ey)] = "@"
	for c in [Vector2i(3, ey), Vector2i(plan.w - 4, xy)]:
		plan.protect[plan.idx(c.x, c.y)] = 1


static func _free(plan: RP, x: int, y: int) -> bool:
	var i: int = y * plan.w + x
	return plan.walkable(x, y) and not plan.markers.has(i) and not plan.prop_cells.has(i)


static func _prot(plan: RP, c: Vector2i) -> void:
	plan.protect[c.y * plan.w + c.x] = 1


static func _mark_person(plan: RP, cell: Vector2i, def: Dictionary) -> bool:
	if not _free(plan, cell.x, cell.y):
		return false
	plan.markers[plan.idx(cell.x, cell.y)] = "P"
	plan.people.append({"cell": cell, "def": def})
	return true


## Seated or walking person: path def with the spawn cell first.
static func _pdef(points: Array, waits: Array, arche: String, sd: int, speed: float = 1.0, home: Variant = null, sit: bool = false) -> Dictionary:
	var d := {"points": points, "waits": waits, "speed": speed, "archetype": arche, "seed": sd}
	if home != null:
		d["home"] = home
	if sit:
		d["sit"] = true
	return d


## Straight leg between two cells clear of walls, water and solid props (same sampling as WorldValidate).
static func _leg_ok(plan: RP, a: Vector2i, b: Vector2i) -> bool:
	var n: int = maxi(1, int(ceil(Vector2(a).distance_to(Vector2(b)) / 0.1)))
	for s in n + 1:
		var f: float = float(s) / float(n)
		var x: float = float(a.x) + 0.5 + (float(b.x - a.x)) * f
		var y: float = float(a.y) + 0.5 + (float(b.y - a.y)) * f
		var cx: int = int(floor(x))
		var cy: int = int(floor(y))
		if plan.tile(cx, cy) != 1:
			return false
		for dx in [-1, 0, 1]:
			for dy in [-1, 0, 1]:
				var k: int = (cy + dy) * plan.w + cx + dx
				if plan.prop_cells.has(k) and StageGen.SOLID_PROPS.has(plan.prop_cells[k]):
					var ddx: float = x - (float(cx + dx) + 0.5)
					var ddy: float = y - (float(cy + dy) + 0.5)
					if ddx * ddx + ddy * ddy < 0.09:
						return false
	return true


static func _obs_char(rng: Rng, inside: bool) -> int:
	if inside:
		return 87   # timber post
	var r: float = rng.next()
	return 66 if r < 0.4 else (73 if r < 0.8 else 0)   # B milestone stub, I fence post, bush


## Drop solid obstacles on the walkable cell farthest from any wall until every walkable cell is within COVER_R of one (the chamfer distance bounds the
## true one from above). `inside` marks the inn building: timber posts there.
static func _open_air_fill(plan: RP, rng: Rng, inside: Rect2i, entry: Vector2i, exitc: Vector2i) -> bool:
	var w: int = plan.w
	var h: int = plan.h
	var dt := StageGen.distance_transform(plan)
	var cand: Array = []
	for i in dt.size():
		if plan.tiles[i] == 1 and dt[i] > COVER_R:
			cand.append(i)
	var offs := GenWild._offsets()
	var iters := 0
	while not cand.is_empty() and iters < 500:
		var bi := -1
		var bv := COVER_R
		for i in cand:
			if dt[i] > bv and plan.tiles[i] == 1:
				bv = dt[i]
				bi = i
		if bi < 0:
			break
		var ax: int = bi % w
		var ay: int = bi / w
		var qx := -1
		var qy := -1
		for o in offs:
			if GenWild._can_obstacle(plan, ax + o.x, ay + o.y, entry, exitc):
				qx = ax + o.x
				qy = ay + o.y
				break
		if qx < 0:
			return false
		GenWild._set_obstacle(plan, qx, qy, _obs_char(rng, inside.has_point(Vector2i(qx, qy))))
		for yy in range(qy - 7, qy + 8):
			for xx in range(qx - 7, qx + 8):
				if xx >= 0 and yy >= 0 and xx < w and yy < h:
					var dd: float = sqrt(float((xx - qx) * (xx - qx) + (yy - qy) * (yy - qy)))
					var j: int = yy * w + xx
					if dd < dt[j]:
						dt[j] = dd
		iters += 1
		if iters % 8 == 0:
			var keep: Array = []
			for i in cand:
				if plan.tiles[i] == 1 and dt[i] > COVER_R:
					keep.append(i)
			cand = keep
	for i in dt.size():
		if plan.tiles[i] == 1 and dt[i] > COVER_R:
			return false
	return true


## Largest distance from a walkable cell (floor of any kind, markers) to the nearest wall cell centre. The rule holds when it is <= OPEN_R.
static func open_air_max(def: Dictionary) -> float:
	var rows: Array = def["rows"]
	var h: int = rows.size()
	var w: int = String(rows[0]).length()
	var wallc := PackedByteArray()
	wallc.resize(w * h)
	for y in h:
		var s: String = rows[y]
		for x in w:
			if "#BWIw".contains(s[x]):
				wallc[y * w + x] = 1
	var worst := 0.0
	var r: int = int(ceil(OPEN_R)) + 1
	for y in h:
		var s2: String = rows[y]
		for x in w:
			if not ".,gSCP@".contains(s2[x]):
				continue
			var best := 1.0e9
			for yy in range(maxi(0, y - r), mini(h, y + r + 1)):
				for xx in range(maxi(0, x - r), mini(w, x + r + 1)):
					if wallc[yy * w + xx] == 1:
						var d2: float = float((xx - x) * (xx - x) + (yy - y) * (yy - y))
						if d2 < best:
							best = d2
			worst = maxf(worst, sqrt(best) if best < 1.0e8 else 99.0)
	return worst


static func _rows(plan: RP) -> Array:
	var rows: Array = []
	for y in plan.h:
		var s := ""
		for x in plan.w:
			var i: int = y * plan.w + x
			var ch := ""
			if plan.tiles[i] == 0:
				ch = "#" if plan.wall[i] == 0 else char(plan.wall[i])
			elif plan.tiles[i] == 2:
				ch = "~"
			else:
				ch = "." if plan.ground[i] == G_COBBLE else ("," if plan.ground[i] == G_WOOD else "g")
			if plan.markers.has(i):
				ch = plan.markers[i]
			for d in plan.doors:
				if d["col"] == x and d["row"] == y:
					ch = "D"
			s += ch
		rows.append(s)
	return rows


static func _lights(plan: RP) -> Array:
	var out: Array = []
	for p in plan.props:
		var t: String = p["type"]
		if p.has("light") or SOLID_LIGHT.has(t):
			out.append({"cell": [p["col"], p["row"]], "radius": float(p.get("light", SOLID_LIGHT.get(t, 1.5))), "kind": t})
	return out


static func _assemble(plan: RP, row: Dictionary, style: String, seed: int, attempt: int, extra: Dictionary) -> Dictionary:
	var entry_cfg: Dictionary = row["entry"]
	var exit_cfg: Dictionary = row["exit"]
	var doors: Array = []
	for d in plan.doors:
		var cfg: Dictionary = entry_cfg if d["facing"] == "e" else exit_cfg
		doors.append({"id": cfg["doorId"], "col": d["col"], "row": d["row"], "toMap": cfg["toMap"], "toDoor": cfg["toDoor"], "facing": d["facing"]})
	var ed: Dictionary = doors[0]
	var xd: Dictionary = doors[1]
	var ef: Array = World.FACING[ed["facing"]]
	var xf: Array = World.FACING[xd["facing"]]
	var rest: Array = []
	for r in plan.rest:
		rest.append({"cell": r["cell"], "kind": r["kind"], "marker": r["marker"], "safety": r["safety"]})
	# people: the i-th P marker (row-major) takes the i-th path def
	var order: Array = plan.people.duplicate()
	order.sort_custom(func(a, b): return a["cell"].y < b["cell"].y or (a["cell"].y == b["cell"].y and a["cell"].x < b["cell"].x))
	var paths: Array = []
	for pe in order:
		paths.append(pe["def"])
	var places: Dictionary = plan.places.duplicate()
	places["entry"] = [plan.start.x, plan.start.y]
	places["exit"] = [int(xd["col"]) + int(xf[0]), int(xd["row"]) + int(xf[1])]
	var gen := {"attempt": attempt, "style": style, "pockets": plan.pockets.size(), "people": paths.size()}
	gen.merge(extra, true)
	return {
		"name": String(row["id"]),
		"kind": String(row["kind"]),
		"floor": String(row["floor"]),
		"materials": row["materials"].duplicate(),
		"rows": _rows(plan),
		"doors": doors,
		"props": plan.props,
		"zones": plan.zones,
		"paths": paths,
		"hides": [],
		"places": places,
		"stage": String(row["id"]),
		"seed": seed,
		"start": {"cell": [plan.start.x, plan.start.y], "angle": float(ef[2])},
		"entry": {"door": ed["id"], "cell": [ed["col"], ed["row"]], "arrival": [int(ed["col"]) + int(ef[0]), int(ed["row"]) + int(ef[1])], "toMap": ed["toMap"]},
		"exit": {"door": xd["id"], "cell": [xd["col"], xd["row"]], "arrival": [int(xd["col"]) + int(xf[0]), int(xd["row"]) + int(xf[1])], "toMap": xd["toMap"]},
		"beats": [],
		"rest": rest,
		"pockets": plan.pockets,
		"ambient": plan.anchors,
		"critters": plan.spawns,
		"lights": _lights(plan),
		"gen": gen,
	}


static func _finish(plan: RP, row: Dictionary, style: String, seed: int, attempt: int, extra: Dictionary) -> Dictionary:
	var def := _assemble(plan, row, style, seed, attempt, extra)
	var rep := StageGen.analyze(def, row)
	if not rep["ok"]:
		for rs in rep["reasons"]:
			_fail("an:" + String(rs).split(" ")[0])
		return _fail("analyze")
	if int(rep["max_rest_dist"]) > int(row["shelter"]["restTarget"]) + 10:
		return _fail("rest_dist")
	if def["paths"].size() > int(row["caps"]["people"]):
		return _fail("people_cap")
	if open_air_max(def) > OPEN_R:
		return _fail("open_air")
	var v := StageGen.validate(def)
	if not v["ok"]:
		return _fail("validate:" + str(v["errors"][0]["message"]))
	def["gen"]["openFraction"] = rep["open_fraction"]
	def["gen"]["maxRestDist"] = rep["max_rest_dist"]
	return def


# ---- the Old Road ---------------------------------------------------------------------------------------------------------------------------

static func _road(row: Dictionary, rng: Rng, seed: int, attempt: int) -> Dictionary:
	var plan := _base(row, G_GRASS)
	var w: int = plan.w
	var h: int = plan.h
	var ey: int = StageGen.rint(rng, 14, h - 15)
	# centreline: a gentle double sine, slope limited to one row per column
	var a1: float = StageGen.rrange(rng, 3.0, 4.5)
	var k1: float = StageGen.rrange(rng, 0.09, 0.13)
	var p1: float = rng.next() * TAU
	var a2: float = StageGen.rrange(rng, 0.8, 1.4)
	var k2: float = StageGen.rrange(rng, 0.25, 0.33)
	var p2: float = rng.next() * TAU
	var xend: int = StageGen.rint(rng, 12, h - 13)
	var cy := PackedInt32Array()
	cy.resize(w)
	var prev := ey
	for x in range(3, w - 3):
		var t: float = float(x - 3) / float(w - 7)
		var env: float = minf(1.0, minf(float(x - 3) / 10.0, float(w - 4 - x) / 10.0))
		var y: float = lerpf(float(ey), float(xend), t) + env * (a1 * sin(k1 * float(x) + p1) + a2 * sin(k2 * float(x) + p2))
		var yi: int = clampi(int(round(y)), 9, h - 10)
		yi = clampi(yi, prev - 1, prev + 1)
		cy[x] = yi
		prev = yi
	var xy: int = cy[w - 4]
	# verge widths: random walks in {3, 4}
	var vu := PackedInt32Array()
	var vd := PackedInt32Array()
	vu.resize(w)
	vd.resize(w)
	var du := 3
	var dd := 3
	for x in range(3, w - 3):
		if rng.next() < 0.12:
			du = 7 - du
		if rng.next() < 0.12:
			dd = 7 - dd
		vu[x] = du
		vd[x] = dd
	for x in range(3, w - 3):
		for d in range(-vu[x], vd[x] + 1):
			var y2: int = cy[x] + d
			_open(plan, x, y2, G_COBBLE if absi(d) <= 1 else G_GRASS)
			if absi(d) <= 1:
				plan.protect[y2 * w + x] = 1
	# field edges: ragged ellipses open on both sides of the road
	var nf: int = StageGen.rint(rng, 3, 5)
	for _f in nf:
		var fx: int = StageGen.rint(rng, 9, w - 10)
		var side: int = 1 if rng.next() < 0.5 else -1
		var rx: float = float(StageGen.rint(rng, 4, 7))
		var ry: float = float(StageGen.rint(rng, 3, 5))
		var edge: int = vd[fx] if side > 0 else vu[fx]
		var fcy: int = cy[fx] + side * (edge + int(ry) - 1)
		for dy in range(-int(ry) - 1, int(ry) + 2):
			for dx in range(-int(rx) - 1, int(rx) + 2):
				var ex: float = float(dx) / rx
				var ee: float = float(dy) / ry
				var px: int = fx + dx
				var py: int = fcy + dy
				if ex * ex + ee * ee <= 1.0 and rng.next() < 0.93 and px >= 6 and px <= w - 7 and py >= 4 and py <= h - 5:
					var k: int = py * w + px
					if plan.protect[k] == 0 and plan.tiles[k] == 0:
						_open(plan, px, py, G_GRASS)
	var entry := Vector2i(3, ey)
	var exitc := Vector2i(w - 4, xy)
	# the doors and their approach stay open
	for c in [entry, exitc]:
		for yy in range(c.y - 2, c.y + 3):
			for xx in range(c.x - 2, c.x + 3):
				if xx >= 3 and xx <= w - 4 and yy >= 1 and yy <= h - 2 and plan.tiles[yy * w + xx] == 0:
					_open(plan, xx, yy, G_GRASS)
	_doors(plan, row, ey, xy)
	_prune(plan, entry)
	# the wayside shrine in an alcove with holy ground
	if not _shrine(plan, rng, cy, vu, vd):
		return _fail("shrine")
	# covered pockets
	if not _pockets(plan, rng, row, entry, exitc):
		return _fail("pockets")
	# ditches
	var nd := 0
	for _t in 6:
		if nd >= 3:
			break
		if _ditch(plan, rng, cy, vu, vd, entry):
			nd += 1
	if nd < 1:
		return _fail("ditch")
	# fence posts and milestones along the road
	_roadside(plan, rng, cy, vu, vd)
	# open air
	if not _open_air_fill(plan, rng, Rect2i(), entry, exitc):
		return _fail("cover")
	if not _road_decor(plan, rng, row, cy, entry, exitc):
		return _fail("people")
	return _finish(plan, row, "road", seed, attempt, {"ditches": nd, "fields": nf})


## The wind the player hears at the start: 6-10 cells from the entry door (the ambient soak needs an anchor within 12 cells of the start).
static func _first_wind(plan: RP, rng: Rng) -> void:
	for _t in 80:
		var ang: float = rng.next() * TAU
		var rr: float = StageGen.rrange(rng, 6.0, 10.0)
		var wx: int = int(round(float(plan.start.x) + cos(ang) * rr))
		var wy: int = int(round(float(plan.start.y) + sin(ang) * rr))
		if wx >= 5 and wy >= 3 and wx < plan.w - 5 and wy < plan.h - 3 and _free(plan, wx, wy):
			plan.add_anchor("wind", wx, wy)
			return


static func _prune(plan: RP, entry: Vector2i) -> void:
	var dist := StageGen.bfs(plan, [plan.idx(entry.x, entry.y)])
	for i in plan.tiles.size():
		if plan.tiles[i] == 1 and dist[i] < 0:
			plan.tiles[i] = 0
			plan.wall[i] = 0


static func _shrine(plan: RP, rng: Rng, cy: PackedInt32Array, vu: PackedInt32Array, vd: PackedInt32Array) -> bool:
	var w: int = plan.w
	for _t in 40:
		var sx: int = StageGen.rint(rng, 16, w - 17)
		var side: int = 1 if rng.next() < 0.5 else -1
		var edge: int = vd[sx] if side > 0 else vu[sx]
		var scy: int = cy[sx] + side * (edge + 3)
		if scy < 5 or scy > plan.h - 6:
			continue
		var okb := true
		for yy in range(scy - 3, scy + 4):
			for xx in range(sx - 3, sx + 4):
				if plan.protect[yy * w + xx] != 0 and (absi(xx - sx) <= 2 and absi(yy - scy) <= 2):
					okb = false
		if not okb:
			continue
		for yy in range(scy - 2, scy + 3):
			for xx in range(sx - 2, sx + 3):
				_open(plan, xx, yy, G_GRASS)
				plan.protect[yy * w + xx] = 1
		# the alcove must meet the road corridor
		plan.props.append({"type": "shrine", "col": sx, "row": scy, "light": 2.0})
		plan.prop_cells[scy * w + sx] = "shrine"
		plan.zones.append({"name": "shrine_holy", "kind": "holy", "x0": sx - 1, "y0": scy - 1, "x1": sx + 1, "y1": scy + 1})
		plan.places["shrine"] = [sx, scy]
		var bell := Vector2i(sx, scy - side * 2)
		plan.add_anchor("bell", bell.x, bell.y)
		return true
	return false


static func _pockets(plan: RP, rng: Rng, row: Dictionary, entry: Vector2i, exitc: Vector2i) -> bool:
	var sh: Dictionary = row["shelter"]
	var kinds: Array = sh["kinds"]
	var pmin: int = int(sh["pockets"]["min"])
	var pmax: int = int(sh["maxPockets"])
	var target: int = int(sh["restTarget"])
	var made := 0
	var dead := {}
	var guard := 0
	while made < pmax and guard < pmax + 16:
		guard += 1
		var srcs: Array = []
		if plan.rest.is_empty():
			srcs.append(plan.idx(entry.x, entry.y))
		else:
			for r in plan.rest:
				srcs.append(plan.idx(r["cell"][0], r["cell"][1]))
		var dist := StageGen.bfs(plan, srcs)
		var far := -1
		var fd := -1
		for i in dist.size():
			if dist[i] > fd and plan.tiles[i] == 1 and not dead.has(i):
				fd = dist[i]
				far = i
		if far < 0:
			break
		if made >= pmin and fd <= target:
			break
		var cands := GenWild._near_cells(plan, far, 12)
		StageGen.shuffle(rng, cands)
		var placed := false
		var dirs: Array = StageGen.N4.duplicate()
		var tries := 0
		for ci in cands:
			if tries > 120:
				break
			tries += 1
			var e := Vector2i(int(ci) % plan.w, int(ci) / plan.w)
			StageGen.shuffle(rng, dirs)
			for d in dirs:
				var ks: Array = kinds.duplicate()
				StageGen.shuffle(rng, ks)
				for k in ks:
					var under: String = UNDER[k]
					if GenWild._try_pocket(plan, rng, row, under, e, d, made + 1, entry, exitc):
						_rename_last(plan, rng, row, under, String(k), made + 1)
						placed = true
						break
				if placed:
					break
			if placed:
				break
		if placed:
			made += 1
		else:
			dead[far] = true
	return made >= pmin


static func _rename_last(plan: RP, rng: Rng, row: Dictionary, under: String, kind: String, n: int) -> void:
	var zn: String = "pocket_%s_%d" % [kind, n]
	plan.zones[plan.zones.size() - 1]["name"] = zn
	var base: float = float(row["shelter"]["safety"].get(kind, 0.5))
	var r: Dictionary = plan.rest[plan.rest.size() - 1]
	r["kind"] = kind
	r["safety"] = snappedf(clampf(base + (rng.next() - 0.5) * 0.1, 0.0, 1.0), 0.01)
	var p: Dictionary = plan.pockets[plan.pockets.size() - 1]
	p["zone"] = zn
	p["kind"] = kind
	if kind == "wayside_crypt":
		var z: Dictionary = plan.zones[plan.zones.size() - 1]
		for y in range(z["y0"], z["y1"] + 1):
			for x in range(z["x0"], z["x1"] + 1):
				if plan.tiles[y * plan.w + x] == 1:
					plan.ground[y * plan.w + x] = G_COBBLE


## A run of ditch water along the outer verge row on one side; kept only when everything that was reachable stays reachable.
static func _ditch(plan: RP, rng: Rng, cy: PackedInt32Array, vu: PackedInt32Array, vd: PackedInt32Array, entry: Vector2i) -> bool:
	var w: int = plan.w
	var x0: int = StageGen.rint(rng, 9, w - 20)
	var len: int = StageGen.rint(rng, 5, 10)
	var side: int = 1 if rng.next() < 0.5 else -1
	var cells: Array = []
	for x in range(x0, mini(x0 + len, w - 8)):
		var edge: int = vd[x] if side > 0 else vu[x]
		var y: int = cy[x] + side * edge
		var i: int = y * w + x
		if plan.tiles[i] == 1 and plan.protect[i] == 0 and not plan.markers.has(i) and not plan.prop_cells.has(i):
			cells.append(i)
	if cells.size() < 4:
		return false
	var before := StageGen.bfs(plan, [plan.idx(entry.x, entry.y)])
	var nb := 0
	for i in before.size():
		if before[i] >= 0:
			nb += 1
	for i in cells:
		plan.tiles[i] = 2
	var after := StageGen.bfs(plan, [plan.idx(entry.x, entry.y)])
	var na := 0
	for i in after.size():
		if after[i] >= 0:
			na += 1
	if na != nb - cells.size():
		# the loss must be exactly the ditch cells: nothing else was cut off
		for i in cells:
			plan.tiles[i] = 1
		return false
	var mid: int = cells[cells.size() / 2]
	plan.add_anchor("ripple", mid % w, mid / w)
	return true


static func _roadside(plan: RP, rng: Rng, cy: PackedInt32Array, vu: PackedInt32Array, vd: PackedInt32Array) -> void:
	var w: int = plan.w
	var last_ms := -99
	var nms := 0
	var x: int = 6
	while x < w - 6:
		for side in [-1, 1]:
			var edge: int = vd[x] if side > 0 else vu[x]
			var y: int = cy[x] + side * 3
			if edge < 3:
				continue
			var i: int = y * w + x
			if plan.tiles[i] != 1 or plan.protect[i] != 0 or plan.markers.has(i) or plan.prop_cells.has(i):
				continue
			if plan.tile(x, y - side * 1) != 1:
				continue
			var ms: bool = nms < 5 and x - last_ms >= 10 and rng.next() < 0.2
			if ms:
				_wall(plan, x, y, 66)
				last_ms = x
				nms += 1
			elif x % 3 == 0 and rng.next() < 0.75:
				_wall(plan, x, y, 73)
		x += 1


static func _road_decor(plan: RP, rng: Rng, row: Dictionary, cy: PackedInt32Array, entry: Vector2i, exitc: Vector2i) -> bool:
	var w: int = plan.w
	var fa: Dictionary = row["fauna"]
	# fields: haybales, a scarecrow, boulders
	var plist := [["haybale", StageGen.rint(rng, 3, 5)], ["scarecrow", StageGen.rint(rng, 1, 2)], ["boulder", StageGen.rint(rng, 2, 3)]]
	for pe in plist:
		for _k in int(pe[1]):
			var c := GenWild._free_prop_cell(plan, rng, entry, exitc, true)
			if c.x >= 0 and plan.protect[c.y * w + c.x] == 0:
				plan.add_prop(String(pe[0]), c.x, c.y)
	# fireflies
	var nl: int = StageGen.rint(rng, int(row["lights"]["min"]) - 1, int(row["lights"]["max"]) - 1)
	for _l in nl:
		var c2 := GenWild._free_prop_cell(plan, rng, entry, exitc, false)
		if c2.x >= 0:
			plan.props.append({"type": "glowworm", "col": c2.x, "row": c2.y, "light": 2.0})
			plan.prop_cells[c2.y * w + c2.x] = "glowworm"
	# critters: crows and the occasional hare
	var taken: Array = []
	var prey: Dictionary = row["preyCount"]
	var total: int = mini(StageGen.rint(rng, int(prey["min"]), int(prey["max"])), int(row["caps"]["critters"]))
	var nbig: int = StageGen.rint(rng, int(fa["bigCount"][0]), int(fa["bigCount"][1]))
	for b in nbig:
		var c3 := GenWild._spread_cell(plan, rng, taken, 10.0, 12.0, entry)
		if c3.x >= 0 and not GenWild._in_pocket(plan, c3):
			taken.append(c3)
			plan.spawns.append({"species": fa["big"], "cell": [c3.x, c3.y]})
	var guard := 0
	while plan.spawns.size() < total and guard < 80:
		guard += 1
		var c4 := GenWild._spread_cell(plan, rng, taken, 4.0, 8.0, entry)
		if c4.x >= 0 and not GenWild._in_pocket(plan, c4):
			taken.append(c4)
			plan.spawns.append({"species": fa["small"], "cell": [c4.x, c4.y]})
	# ambient: cart rumble on the road, wind, crickets on the verges
	var amb: Dictionary = row["ambient"]
	var ncart: int = StageGen.rint(rng, int(amb["carts"][0]), int(amb["carts"][1]))
	var ctaken: Array = []
	for _c in ncart:
		for _t in 40:
			var x: int = StageGen.rint(rng, 14, w - 12)
			var y: int = cy[x]
			if plan.walkable(x, y) and GenWild._far_from(ctaken, x, y, 18.0):
				plan.add_anchor("cart", x, y)
				ctaken.append([x, y])
				break
	_first_wind(plan, rng)
	var dt := StageGen.distance_transform(plan)
	var wtaken: Array = []
	for _wi in StageGen.rint(rng, int(amb["wind"][0]), int(amb["wind"][1])):
		for _t in 60:
			var xx: int = StageGen.rint(rng, 6, w - 7)
			var yy: int = StageGen.rint(rng, 4, plan.h - 5)
			if plan.walkable(xx, yy) and dt[yy * w + xx] >= 2.0 and GenWild._far_from(wtaken, xx, yy, 14.0):
				plan.add_anchor("wind", xx, yy)
				wtaken.append([xx, yy])
				break
	var cr: Array = []
	for _cr in StageGen.rint(rng, int(amb["crickets"][0]), int(amb["crickets"][1])):
		for _t in 60:
			var x4: int = StageGen.rint(rng, 6, w - 7)
			var y4: int = StageGen.rint(rng, 4, plan.h - 5)
			if plan.walkable(x4, y4) and GenWild._far_from(cr, x4, y4, 7.0) and Vector2(x4, y4).distance_to(Vector2(entry)) > 6.0:
				plan.add_anchor("cricket", x4, y4)
				cr.append([x4, y4])
				break
	# people: a pilgrim pair, a carter, two watchers on short posts
	var sd: int = int(rng.next() * 1000.0)
	var ax: int = StageGen.rint(rng, 10, 20)
	var span: int = StageGen.rint(rng, 18, 24)
	var pts_a: Array = []
	var xs: Array = []
	var xx2: int = ax
	while xx2 <= ax + span:
		xs.append(xx2)
		xx2 += 2
	for x5 in xs:
		pts_a.append([x5, cy[x5]])
	_add_walker(plan, pts_a, "patron", sd, 1.0)
	for off in [1, -1]:
		var pts_b: Array = []
		for x5 in xs:
			pts_b.append([x5, cy[x5] + off])
		if _add_walker(plan, pts_b, "patron", sd + 1, 1.0):
			break
	var cx0: int = StageGen.rint(rng, w / 2 + 2, w - 24)
	var pts_c: Array = []
	var x6: int = cx0
	while x6 <= cx0 + 14:
		pts_c.append([x6, cy[x6] - 1])
		x6 += 2
	_add_walker(plan, pts_c, "merchant", sd + 2, 0.9)
	var wx1: int = StageGen.rint(rng, 22, 30)
	var wx2: int = StageGen.rint(rng, 42, 50)
	for wk in [[wx1, 5], [wx2, 6]]:
		var pw: Array = []
		for dx in [0, 2, 4]:
			pw.append([int(wk[0]) + dx, cy[int(wk[0]) + dx]])
		_add_walker(plan, pw, "guard", sd + int(wk[1]), 0.9, 3.0)
	return plan.people.size() >= 5


## Ping-pong path along a list of cells (first = spawn); skipped when a leg is not clear or the spawn cell is taken.
static func _add_walker(plan: RP, pts: Array, arche: String, sd: int, speed: float, wait: float = 2.0) -> bool:
	if pts.size() < 2:
		return false
	for k in pts.size() - 1:
		if not _leg_ok(plan, Vector2i(pts[k][0], pts[k][1]), Vector2i(pts[k + 1][0], pts[k + 1][1])):
			return false
	var loop: Array = pts.duplicate()
	for k in range(pts.size() - 2, 0, -1):
		loop.append(pts[k])
	var waits: Array = []
	for k in loop.size():
		waits.append(wait if (k == 0 or k == pts.size() - 1) else 0.0)
	return _mark_person(plan, Vector2i(pts[0][0], pts[0][1]), _pdef(loop, waits, arche, sd, speed))


# ---- Crossroads Inn -------------------------------------------------------------------------------------------------------------------------

static func _rect_walls(plan: RP, x0: int, y0: int, x1: int, y1: int, ch: int) -> void:
	for x in range(x0, x1 + 1):
		_wall(plan, x, y0, ch)
		_wall(plan, x, y1, ch)
	for y in range(y0, y1 + 1):
		_wall(plan, x0, y, ch)
		_wall(plan, x1, y, ch)


static func _rect_floor(plan: RP, x0: int, y0: int, x1: int, y1: int, g: int) -> void:
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			_open(plan, x, y, g)


static func _gap(plan: RP, x: int, y: int) -> void:
	_open(plan, x, y, G_WOOD)
	for dy in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			plan.protect[(y + dy) * plan.w + x + dx] = 1


static func _prop(plan: RP, type: String, c: Vector2i, light: float = -1.0) -> void:
	var p := {"type": type, "col": c.x, "row": c.y}
	if light >= 0.0:
		p["light"] = light
	plan.props.append(p)
	plan.prop_cells[plan.idx(c.x, c.y)] = type


static func _place(plan: RP, name: String, c: Vector2i) -> void:
	plan.places[name] = [c.x, c.y]
	plan.protect[plan.idx(c.x, c.y)] = 1


static func _zone(plan: RP, name: String, x0: int, y0: int, x1: int, y1: int) -> void:
	plan.zones.append({"name": name, "kind": "indoor", "x0": x0, "y0": y0, "x1": x1, "y1": y1})


static func _rest(plan: RP, row: Dictionary, rng: Rng, kind: String, c: Vector2i, zone: String) -> void:
	plan.markers[plan.idx(c.x, c.y)] = "S"
	var base: float = float(row["shelter"]["safety"].get(kind, 0.5))
	plan.rest.append({"cell": [c.x, c.y], "kind": kind, "marker": "S", "safety": snappedf(clampf(base + (rng.next() - 0.5) * 0.06, 0.0, 1.0), 0.01)})
	plan.pockets.append({"zone": zone, "kind": kind, "rest": true, "cell": [c.x, c.y]})


static func _pond(plan: RP, rng: Rng, ys0: int, ys1: int, exitc: Vector2i) -> Vector2i:
	for _t in 60:
		var x: int = StageGen.rint(rng, 14, plan.w - 15)
		var y: int = StageGen.rint(rng, ys0 + 3, ys1 - 4)
		var okc := true
		for yy in range(y - 2, y + 3):
			for xx in range(x - 3, x + 4):
				var i: int = yy * plan.w + xx
				if plan.tiles[i] != 1 or plan.protect[i] != 0 or plan.markers.has(i) or plan.prop_cells.has(i):
					okc = false
		if okc and Vector2(x, y).distance_to(Vector2(plan.start)) > 8.0 and Vector2(x, y).distance_to(Vector2(exitc)) > 8.0:
			for yy in range(y, y + 2):
				for xx in range(x, x + 3):
					plan.tiles[yy * plan.w + xx] = 2
			return Vector2i(x + 1, y)
	return Vector2i(-1, -1)


static func _inn(row: Dictionary, rng: Rng, seed: int, attempt: int) -> Dictionary:
	var plan := _base(row, G_COBBLE)
	var w: int = plan.w
	var bx0: int = StageGen.rint(rng, 8, 16)
	var bw: int = StageGen.rint(rng, 26, 30)
	var bx1: int = bx0 + bw - 1
	var by0: int = StageGen.rint(rng, 6, 8)
	var by1: int = by0 + 15
	var ys0: int = by1 + 1
	var ys1: int = StageGen.rint(rng, 38, 40)
	var xw: int = bx1 - 7
	var ym: int = by0 + 7
	var fx: int = bx0 + StageGen.rint(rng, 6, bw - 16)
	# yard
	_rect_floor(plan, 3, ys0, w - 4, ys1, G_COBBLE)
	for _g in 40:
		var gx: int = StageGen.rint(rng, 3, w - 4)
		var gy: int = StageGen.rint(rng, ys1 - 2, ys1)
		plan.ground[gy * w + gx] = G_GRASS
	var ey: int = StageGen.rint(rng, ys0 + 2, ys1 - 8)
	var xy: int = StageGen.rint(rng, ys0 + 2, ys1 - 2)
	_doors(plan, row, ey, xy)
	# the inn
	_rect_floor(plan, bx0, by0, bx1, by1, G_WOOD)
	_rect_walls(plan, bx0, by0, bx1, by1, 87)
	for y in range(by0, by1 + 1):
		_wall(plan, xw, y, 87)
	for x in range(xw, bx1 + 1):
		_wall(plan, x, ym, 87)
	_gap(plan, xw, by0 + 3)       # common room <-> cellar
	_gap(plan, xw, ym + 3)        # common room <-> kitchen
	_gap(plan, fx, by1)           # the front doorway
	for x in range(bx0 + 3, bx1 - 1, 4):
		if absi(x - fx) > 1 and x != xw:
			_wall(plan, x, by0, 119)
	for x in range(bx0 + 3, xw - 1, 4):
		if absi(x - fx) > 1:
			_wall(plan, x, by1, 119)
	# bar counter, hearth, tables
	for x in range(bx0 + 2, bx0 + 9):
		_wall(plan, x, by0 + 3, 87)
	_prop(plan, "brazier", Vector2i(xw - 2, by0 + 2))
	_place(plan, "tavern_hearth", Vector2i(xw - 2, by0 + 3))
	_place(plan, "tavern_a", Vector2i(bx0 + 3, by0 + 2))
	_place(plan, "tavern_b", Vector2i(bx0 + 8, by0 + 2))
	_place(plan, "tavern_c", Vector2i(xw - 3, by0 + 7))
	_prot(plan, Vector2i(xw - 3, by0 + 8))
	_prot(plan, Vector2i(xw - 3, by0 + 9))
	var tables: Array = []
	for i in 5:
		var ty: int = by0 + (StageGen.rint(rng, 8, 9) if i < 3 else StageGen.rint(rng, 11, 12))
		var tx: int = bx0 + 4 + 5 * i if i < 3 else bx0 + 6 + 5 * (i - 3)
		tables.append(Vector2i(tx, ty))
		_prop(plan, "table", Vector2i(tx, ty))
		_prot(plan, Vector2i(tx, ty + 1))
		_prot(plan, Vector2i(tx, ty + 2))
	_place(plan, "tavern_t", tables[3] + Vector2i(0, 1))
	_place(plan, "tavern_t2", tables[4] + Vector2i(0, 1))
	_place(plan, "square", Vector2i(fx, by1 + 2))
	for mx in range(fx + 3, fx + 6):
		_prot(plan, Vector2i(mx, by1 + 2))
	for tx2 in [bx0 + 2, bx0 + 5, xw - 5]:
		_prop(plan, "torch", Vector2i(tx2, by0 + 1), 4.0)
	_prop(plan, "torch", Vector2i(xw - 2, by0 + 8), 4.0)
	# cellar (hostile owner) and kitchen
	_prop(plan, "barrel", Vector2i(xw + 2, by0 + 2))
	_prop(plan, "barrel", Vector2i(xw + 3, by0 + 2))
	_prop(plan, "barrel", Vector2i(xw + 2, by0 + 5))
	_prop(plan, "brazier", Vector2i(bx1 - 1, by0 + 8))
	_prop(plan, "barrel", Vector2i(bx1 - 1, by0 + 14))
	_place(plan, "tavern_hearth2", Vector2i(bx1 - 2, by0 + 8))
	_place(plan, "tavern_bed", Vector2i(xw + 2, by0 + 13))
	_place(plan, "tavern_bed2", Vector2i(xw + 4, by0 + 13))
	_place(plan, "tavern_bed3", Vector2i(xw + 5, by0 + 11))
	_place(plan, "tavern_table", Vector2i(xw + 2, by0 + 10))
	_place(plan, "tavern_work", Vector2i(xw + 4, by0 + 9))
	_zone(plan, "tavern", bx0, by0, xw, by1)
	_zone(plan, "cellar", xw, by0, bx1, ym)
	_zone(plan, "kitchen", xw, ym, bx1, by1)
	_rest(plan, row, rng, "cellar", Vector2i(bx1 - 1, by0 + 1), "cellar")
	plan.pockets.append({"zone": "tavern", "kind": "common_room", "rest": false, "cell": [bx0 + 2, by0 + 1]})
	# stable (east yard) and woodshed (west yard) built into the south hedge
	var sx0: int = StageGen.rint(rng, 48, 50)
	var sx1: int = sx0 + 8
	var sy0: int = ys1 - 6
	_rect_floor(plan, sx0, sy0, sx1, ys1, G_WOOD)
	_rect_walls(plan, sx0, sy0, sx1, ys1, 87)
	var sdoor: int = StageGen.rint(rng, sy0 + 2, ys1 - 2)
	_gap(plan, sx0, sdoor)
	_zone(plan, "stable", sx0, sy0, sx1, ys1)
	for hc in [Vector2i(sx1 - 1, ys1 - 1), Vector2i(sx1 - 2, ys1 - 1)]:
		_prop(plan, "haybale", hc)
	_prop(plan, "haybale", Vector2i(sx1 - 1, sy0 + 1))
	_prop(plan, "bench", Vector2i(sx0 + 2, sy0 + 1))
	_prop(plan, "torch", Vector2i(sx0 - 1, sdoor - 1), 3.5)
	_rest(plan, row, rng, "stable", Vector2i(sx1 - 1, ys1 - 2), "stable")
	var hx0: int = StageGen.rint(rng, 6, 9)
	var hy0: int = ys1 - 4
	_rect_floor(plan, hx0, hy0, hx0 + 4, ys1, G_WOOD)
	_rect_walls(plan, hx0, hy0, hx0 + 4, ys1, 87)
	_gap(plan, hx0 + 4, hy0 + 2)
	_zone(plan, "woodshed", hx0, hy0, hx0 + 4, ys1)
	_prop(plan, "barrel", Vector2i(hx0 + 3, ys1 - 1))
	_rest(plan, row, rng, "woodshed", Vector2i(hx0 + 1, hy0 + 1), "woodshed")
	# yard: a well, barrels, torches by the front door
	var well := Vector2i(fx + StageGen.rint(rng, 6, 9), by1 + StageGen.rint(rng, 4, 6))
	_prop(plan, "well", well)
	for tc in [Vector2i(fx - 2, by1 + 1), Vector2i(fx + 2, by1 + 1)]:
		_prop(plan, "torch", tc, 4.0)
	for _b in StageGen.rint(rng, 2, 4):
		var c := GenWild._free_prop_cell(plan, rng, plan.start, Vector2i(w - 4, xy), true)
		if c.x >= 0 and plan.protect[c.y * w + c.x] == 0 and c.y > ys0:
			_prop(plan, "barrel", c)
	# a horse trough / pond in the open yard (still water: rays cross it, nobody walks on it)
	var pond := _pond(plan, rng, ys0, ys1, Vector2i(w - 4, xy))
	if pond.x < 0:
		return _fail("pond")
	plan.add_anchor("ripple", pond.x, pond.y)
	# open air: timber posts in the common room, fence posts and stubs in the yard
	if not _open_air_fill(plan, rng, Rect2i(bx0, by0, bw, 16), plan.start, Vector2i(w - 4, xy)):
		return _fail("cover")
	# people
	var sd: int = int(rng.next() * 1000.0)
	var seats: Array = []
	for t in tables:
		seats.append(t + Vector2i(0, 1))
	_mark_person(plan, Vector2i(bx0 + 3, by0 + 2), _pdef([[bx0 + 3, by0 + 2], [bx0 + 8, by0 + 2]], [2.0, 2.0], "innkeeper", sd, 1.0, "tavern"))
	_mark_person(plan, Vector2i(xw - 3, by0 + 7), _pdef([[xw - 3, by0 + 7], [xw - 3, by0 + 9]], [2.0, 2.0], "drunk", sd + 1, 1.0, "tavern"))
	for k in [3, 4]:
		var s: Vector2i = seats[k]
		_mark_person(plan, s, _pdef([[s.x, s.y], [s.x, s.y + 1]], [2.0, 2.0], "regular", sd + 2 + k, 1.0, "tavern"))
	for k in [0, 1, 2]:
		var s2: Vector2i = seats[k]
		_mark_person(plan, s2, _pdef([[s2.x, s2.y], [s2.x, s2.y + 1]], [1.0, 1.0], "patron", sd + 10 + k, 1.0, null, true))
	_mark_person(plan, Vector2i(fx + 3, by1 + 2), _pdef([[fx + 3, by1 + 2], [fx + 5, by1 + 2]], [3.0, 3.0], "merchant", sd + 20, 1.0, "tavern"))
	# rats in the cellar and the yard; hearth, singing, wind and crickets
	plan.spawns.append({"species": "rat", "cell": [xw + 3, by0 + 5]})
	plan.spawns.append({"species": "rat", "cell": [xw + 4, by0 + 4]})
	var rc := GenWild._spread_cell(plan, rng, [], 4.0, 10.0, plan.start)
	if rc.x >= 0 and rc.y > ys0:
		plan.spawns.append({"species": "rat", "cell": [rc.x, rc.y]})
	plan.add_anchor("hearth", xw - 2, by0 + 3)
	plan.add_anchor("hearth", bx1 - 2, by0 + 8)
	plan.add_anchor("singing", (bx0 + xw) / 2, by0 + 10)
	_first_wind(plan, rng)
	var wt: Array = []
	for _wi in 2:
		for _t in 60:
			var wx: int = StageGen.rint(rng, 6, w - 7)
			var wy: int = StageGen.rint(rng, ys0 + 1, ys1 - 1)
			if plan.walkable(wx, wy) and GenWild._far_from(wt, wx, wy, 16.0):
				plan.add_anchor("wind", wx, wy)
				wt.append([wx, wy])
				break
	for _ci in 2:
		for _t in 60:
			var kx: int = StageGen.rint(rng, 8, w - 9)
			var ky: int = StageGen.rint(rng, ys0 + 1, ys1 - 1)
			if plan.walkable(kx, ky) and plan.protect[ky * w + kx] == 0 and Vector2(kx, ky).distance_to(Vector2(plan.start)) > 6.0:
				plan.add_anchor("cricket", kx, ky)
				break
	return _finish(plan, row, "inn", seed, attempt, {"building": [bx0, by0, bx1, by1]})
