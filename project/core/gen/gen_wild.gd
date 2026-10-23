class_name GenWild
extends RefCounted
## The two outdoor stages after the Hollow, one file for both kinds (docs/ROGUELIKE.md "Wild stages"):
##   wood  Bramble Wood: `#` grass thicket (cellular automaton), `W` trunks, a meandering creek `~` that is crossable only at fords, rabbits and deer,
##         owls, creek and wind; covered pockets are hollow trees (ring of `W`) and fox burrows (earth bank of `#`)
##   moor  Gallows Moor: wide open grass, `B` cairns, `I` gibbets, gorse `#`, bog pools `~`, hares and wolves, wind and crickets (the crickets go
##         silent near the player: Ambient `quiet`); covered pockets are barrows (ring of `B`) and peat cuts (bank of `#`)
## Both are `kind: outdoor` (sun kills), start at dusk on the cell in front of the west entry door, leave through a door on the east edge, and share
## the same shelter and open-air machinery:
##   pockets   small indoor zones stamped into the open ground, every one with a rest spot `S`. Pockets are added at the farthest walkable cell from the
##             rest spots until it is within `shelter.restTarget` BFS cells (the hard rule is StageGen.cover_limit = 576).
##   open air  every walkable cell has a wall cell within OPEN_R = 6 (docs: wild 6). Solid obstacles (trunks / cairns / gibbets / bush) are dropped on the
##             walkable cell farthest from any wall (distance transform, updated locally) until none is farther than COVER_R = 5.5 (the chamfer distance
##             is an upper bound of the true Euclidean one, so the true distance is <= 5.5). Obstacles always have eight floor neighbours, so they cannot cut a path.
## An attempt that breaks a constraint is discarded and attempt+1 runs: the result is a pure function of (stage id, seed).

const MAX_ATTEMPTS := 60
const OPEN_R := 6.0
const COVER_R := 5.5
const MARGIN_X := 4
const MARGIN_Y := 2
## Shapes in (depth, lateral) cells from the entrance cell `e` into the pocket (depth 1 = the doorway). "rest" is the S cell.
const SHAPES := {
	"wide": {
		"walls": [[1, -2], [1, -1], [1, 1], [1, 2], [2, -2], [2, 2], [3, -2], [3, -1], [3, 0], [3, 1], [3, 2]],
		"floor": [[1, 0], [2, -1], [2, 0], [2, 1]], "rest": [2, 0], "dmax": 3, "lat": 2,
	},
	"narrow": {
		"walls": [[1, -1], [1, 1], [2, -1], [2, 1], [3, -1], [3, 0], [3, 1]],
		"floor": [[1, 0], [2, 0]], "rest": [2, 0], "dmax": 3, "lat": 1,
	},
}
const POCKET_KINDS := {
	"hollow_tree": {"shape": "wide", "wall": "W"},
	"burrow": {"shape": "narrow", "wall": "#"},
	"barrow": {"shape": "wide", "wall": "B"},
	"peat_cut": {"shape": "narrow", "wall": "#"},
}

static var last_attempts: int = 0
## Why attempts were rejected, by reason key (diagnostics only).
static var fails: Dictionary = {}
static var _offs: Array = []


## A plan whose wall cells remember their character (# W B I).
class WP:
	extends StageGen.Plan
	var wall := PackedByteArray()
	var pool_cells: Array = []   # [[x, y], ...] centre cell of every pool (moor)
	var ford_rows: Array = []

	func _init(w_: int, h_: int) -> void:
		super._init(w_, h_)
		wall.resize(w_ * h_)


static func _fail(k: String) -> Dictionary:
	fails[k] = int(fails.get(k, 0)) + 1
	return {}


static func generate(row: Dictionary, seed: int, style: String) -> Dictionary:
	for attempt in MAX_ATTEMPTS:
		var rng := Rng.new(StageGen.seed_for(seed, attempt))
		var def := _attempt(row, rng, seed, attempt, style)
		if not def.is_empty():
			last_attempts = attempt + 1
			return def
	last_attempts = MAX_ATTEMPTS
	return {}


static func _attempt(row: Dictionary, rng: Rng, seed: int, attempt: int, style: String) -> Dictionary:
	var sz: Dictionary = row["size"]
	var w: int = int(sz["w"])
	var h: int = int(sz["h"])
	var moor: bool = style == "moor"
	var plan := WP.new(w, h)
	for y in range(1, h - 1):
		for x in range(1, w - 1):
			plan.tiles[y * w + x] = 1
		for x in [1, 2, w - 3, w - 2]:
			plan.tiles[y * w + x] = 0
			plan.protect[y * w + x] = 1
	var entry_cfg: Dictionary = row["entry"]
	var exit_cfg: Dictionary = row["exit"]
	var ey: int = StageGen.rint(rng, 8, h - 9)
	var xy: int = StageGen.rint(rng, 8, h - 9)
	var entry := Vector2i(3, ey)
	var exitc := Vector2i(w - 4, xy)
	plan.start = entry
	plan.markers[plan.idx(entry.x, entry.y)] = "@"
	plan.doors.append({"id": entry_cfg["doorId"], "col": 2, "row": ey, "facing": "e"})
	plan.doors.append({"id": exit_cfg["doorId"], "col": w - 3, "row": xy, "facing": "w"})

	# 1 terrain
	var terr: Dictionary = row.get("terrain", {})
	var info: Dictionary = {}
	if moor:
		_clear_around(plan, entry, 3)
		_clear_around(plan, exitc, 3)
		_moor_terrain(plan, rng, terr, entry, exitc)
	else:
		_wood_ca(plan, rng, terr)
		_clear_around(plan, entry, 3)
		_clear_around(plan, exitc, 3)
		info = _creek(plan, rng, terr, entry, exitc)
	# 2 only what the start can reach stays open
	var dist := StageGen.bfs(plan, [plan.idx(entry.x, entry.y)])
	for i in plan.tiles.size():
		if plan.tiles[i] == 1 and dist[i] < 0:
			plan.tiles[i] = 0
	if dist[plan.idx(exitc.x, exitc.y)] < 0:
		return _fail("exit")
	# 3 covered pockets
	if not _pockets(plan, rng, row, entry, exitc):
		return _fail("pockets")
	# 4 obstacles: scatter, then the open-air coverage
	if not _obstacles(plan, rng, style, entry, exitc):
		return _fail("cover")
	# 5 decoration, critters, ambient, lights
	_decorate(plan, rng, row, style, info, entry, exitc)
	var def := _assemble(plan, row, style, seed, attempt, info)
	var rep := StageGen.analyze(def, row)
	if not rep["ok"]:
		for rs in rep["reasons"]:
			_fail("an:" + String(rs).split(" ")[0])
		return _fail("analyze")
	var target: int = int(row["shelter"]["restTarget"])
	if int(rep["max_rest_dist"]) > target + 10:
		return _fail("rest_dist")
	var v := StageGen.validate(def)
	if not v["ok"]:
		return _fail("validate")
	def["gen"]["openFraction"] = rep["open_fraction"]
	def["gen"]["maxRestDist"] = rep["max_rest_dist"]
	return def


# ---- terrain --------------------------------------------------------------------------------------------------------------------------------

static func _clear_around(plan: WP, c: Vector2i, r: float) -> void:
	var ri: int = int(ceil(r))
	for y in range(c.y - ri, c.y + ri + 1):
		for x in range(c.x - ri, c.x + ri + 1):
			if x >= 3 and x <= plan.w - 4 and y >= 1 and y <= plan.h - 2 and (x - c.x) * (x - c.x) + (y - c.y) * (y - c.y) <= r * r:
				if plan.tiles[y * plan.w + x] == 0:
					plan.tiles[y * plan.w + x] = 1


## Thicket by cellular automaton (random fill, 4-5 rule).
static func _wood_ca(plan: WP, rng: Rng, terr: Dictionary) -> void:
	var w: int = plan.w
	var h: int = plan.h
	var fl: Array = terr.get("fill", [0.36, 0.42])
	var fill: float = StageGen.rrange(rng, float(fl[0]), float(fl[1]))
	var passes: int = int(terr.get("passes", 3))
	var buf := PackedByteArray()
	buf.resize(w * h)
	for y in h:
		for x in w:
			var edge: bool = x < 3 or x > w - 4 or y == 0 or y == h - 1
			buf[y * w + x] = 1 if edge else (1 if rng.next() < fill else 0)
	for _p in passes:
		var nb := buf.duplicate()
		for y in range(1, h - 1):
			for x in range(3, w - 3):
				var i: int = y * w + x
				var cnt: int = buf[i - w - 1] + buf[i - w] + buf[i - w + 1] + buf[i - 1] + buf[i + 1] + buf[i + w - 1] + buf[i + w] + buf[i + w + 1]
				nb[i] = 1 if cnt >= 5 else (0 if cnt <= 3 else buf[i])
		buf = nb
	for y in range(1, h - 1):
		for x in range(3, w - 3):
			plan.tiles[y * w + x] = 0 if buf[y * w + x] == 1 else 1


## A vertical creek 2 cells wide that meanders across the whole map, with fords (2 cells tall gaps with cleared, protected banks) and trails to them.
static func _creek(plan: WP, rng: Rng, terr: Dictionary, entry: Vector2i, exitc: Vector2i) -> Dictionary:
	var w: int = plan.w
	var h: int = plan.h
	var cxr := PackedInt32Array()
	cxr.resize(h)
	var xc: int = StageGen.rint(rng, 27, 36)
	for y in range(1, h - 1):
		cxr[y] = xc
		var r: float = rng.next()
		if r < 0.28:
			xc -= 1
		elif r < 0.56:
			xc += 1
		xc = clampi(xc, 23, 40)
	for y in range(1, h - 1):
		for x in [cxr[y], cxr[y] + 1]:
			plan.tiles[y * w + x] = 2
	var nford: int = int(terr.get("fords", 2))
	var fords: Array = []
	var f1: int = StageGen.rint(rng, 6, 18)
	fords.append(f1)
	if nford >= 2:
		fords.append(StageGen.rint(rng, 29, 40))
	var spans: Array = []
	for fy in fords:
		var lo: int = mini(cxr[fy], cxr[fy + 1]) - 3
		var hi: int = maxi(cxr[fy], cxr[fy + 1]) + 4
		for y in range(fy - 1, fy + 3):
			for x in range(lo, hi + 1):
				var i: int = y * w + x
				if y == fy or y == fy + 1:
					plan.tiles[i] = 1
					plan.protect[i] = 1
				elif plan.tiles[i] != 2:
					plan.tiles[i] = 1
		spans.append([lo, hi, fy])
		plan.ford_rows.append(fy)
	for s in spans:
		StageGen.carve_tunnel(plan, rng, entry, Vector2i(int(s[0]) - 1, int(s[2])), 2)
		StageGen.carve_tunnel(plan, rng, Vector2i(int(s[1]) + 1, int(s[2])), exitc, 2)
	return {"creek": cxr, "fords": fords, "spans": spans}


static func _moor_terrain(plan: WP, rng: Rng, terr: Dictionary, entry: Vector2i, exitc: Vector2i) -> void:
	var w: int = plan.w
	var h: int = plan.h
	var npool: int = StageGen.rint(rng, int(terr.get("pools", [2, 3])[0]), int(terr.get("pools", [2, 3])[1]))
	var guard := 0
	while plan.pool_cells.size() < npool and guard < 60:
		guard += 1
		var cx: int = StageGen.rint(rng, 10, w - 11)
		var cy: int = StageGen.rint(rng, 7, h - 8)
		if Vector2(cx, cy).distance_to(Vector2(entry)) < 12.0 or Vector2(cx, cy).distance_to(Vector2(exitc)) < 12.0:
			continue
		var far := true
		for pc in plan.pool_cells:
			if Vector2(cx, cy).distance_to(Vector2(int(pc[0]), int(pc[1]))) < 14.0:
				far = false
		if not far:
			continue
		var a: float = StageGen.rrange(rng, 2.2, 3.4)
		var b: float = StageGen.rrange(rng, 1.3, 2.2)
		for dy in range(-3, 4):
			for dx in range(-4, 5):
				if (float(dx) / a) * (float(dx) / a) + (float(dy) / b) * (float(dy) / b) <= 1.0:
					plan.tiles[(cy + dy) * w + cx + dx] = 2
		plan.pool_cells.append([cx, cy])
	var blobs: int = StageGen.rint(rng, int(terr.get("blobs", [6, 9])[0]), int(terr.get("blobs", [6, 9])[1]))
	guard = 0
	var made := 0
	while made < blobs and guard < 80:
		guard += 1
		var bx: int = StageGen.rint(rng, 8, w - 9)
		var by: int = StageGen.rint(rng, 4, h - 5)
		if Vector2(bx, by).distance_to(Vector2(entry)) < 8.0 or Vector2(bx, by).distance_to(Vector2(exitc)) < 8.0:
			continue
		var rx: float = StageGen.rrange(rng, 1.4, 3.4)
		var ry: float = StageGen.rrange(rng, 1.2, 2.8)
		for dy in range(-3, 4):
			for dx in range(-4, 5):
				if (float(dx) / rx) * (float(dx) / rx) + (float(dy) / ry) * (float(dy) / ry) <= 1.0 and rng.next() < 0.88:
					var i: int = (by + dy) * w + bx + dx
					if plan.tiles[i] == 1 and plan.protect[i] == 0:
						plan.tiles[i] = 0
		made += 1


# ---- pockets --------------------------------------------------------------------------------------------------------------------------------

static func _pockets(plan: WP, rng: Rng, row: Dictionary, entry: Vector2i, exitc: Vector2i) -> bool:
	var sh: Dictionary = row["shelter"]
	var kinds: Array = sh["kinds"]
	var pmin: int = int(sh["pockets"]["min"])
	var pmax: int = int(sh["maxPockets"])
	var target: int = int(sh["restTarget"])
	var made := 0
	var dead := {}
	var guard := 0
	while made < pmax and guard < pmax + 14:
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
		var cands := _near_cells(plan, far, 12)
		StageGen.shuffle(rng, cands)
		var placed := false
		var dirs: Array = StageGen.N4.duplicate()
		var tries := 0
		for ci in cands:
			if tries > 90:
				break
			tries += 1
			var e := Vector2i(int(ci) % plan.w, int(ci) / plan.w)
			StageGen.shuffle(rng, dirs)
			for d in dirs:
				var ks: Array = kinds.duplicate()
				StageGen.shuffle(rng, ks)
				for k in ks:
					if _try_pocket(plan, rng, row, String(k), e, d, made + 1, entry, exitc):
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


## BFS-order cells within `radius` steps of `src` (walkable cells only).
static func _near_cells(plan: WP, src: int, radius: int) -> Array:
	var seen := {src: 0}
	var q: Array = [src]
	var head := 0
	while head < q.size():
		var cur: int = q[head]
		head += 1
		var d: int = seen[cur]
		if d >= radius:
			continue
		for o in StageGen.N4:
			var nx: int = cur % plan.w + o.x
			var ny: int = cur / plan.w + o.y
			if plan.walkable(nx, ny):
				var ni: int = ny * plan.w + nx
				if not seen.has(ni):
					seen[ni] = d + 1
					q.append(ni)
	return q


static func _pocket_cell(e: Vector2i, d: Vector2i, depth: int, lat: int) -> Vector2i:
	var p := Vector2i(-d.y, d.x)
	return e + d * depth + p * lat


static func _try_pocket(plan: WP, rng: Rng, row: Dictionary, kind: String, e: Vector2i, d: Vector2i, n: int, entry: Vector2i, exitc: Vector2i) -> bool:
	var pk: Dictionary = POCKET_KINDS[kind]
	var shape: Dictionary = SHAPES[pk["shape"]]
	var w: int = plan.w
	if not plan.walkable(e.x, e.y) or plan.protect[e.y * w + e.x] != 0 or plan.markers.has(e.y * w + e.x):
		return false
	if Vector2(e).distance_to(Vector2(entry)) < 6.0 or Vector2(e).distance_to(Vector2(exitc)) < 6.0:
		return false
	var dmax: int = int(shape["dmax"])
	var lat: int = int(shape["lat"])
	var x0: int = 1 << 20
	var y0: int = 1 << 20
	var x1: int = -(1 << 20)
	var y1: int = -(1 << 20)
	for dep in [1, dmax]:
		for lt in [-lat, lat]:
			var c := _pocket_cell(e, d, dep, lt)
			x0 = mini(x0, c.x)
			y0 = mini(y0, c.y)
			x1 = maxi(x1, c.x)
			y1 = maxi(y1, c.y)
	if x0 < MARGIN_X or y0 < MARGIN_Y or x1 > w - 1 - MARGIN_X or y1 > plan.h - 1 - MARGIN_Y:
		return false
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var i: int = y * w + x
			if plan.protect[i] != 0 or plan.tiles[i] == 2 or plan.markers.has(i) or plan.prop_cells.has(i):
				return false
	# the ring around the footprint: its open cells must form one arc, so closing the footprint cannot cut any path
	var ring: Array = []
	for x in range(x0 - 1, x1 + 1):
		ring.append(Vector2i(x, y0 - 1))
	for y in range(y0 - 1, y1 + 1):
		ring.append(Vector2i(x1 + 1, y))
	for x in range(x1 + 1, x0 - 1, -1):
		ring.append(Vector2i(x, y1 + 1))
	for y in range(y1 + 1, y0 - 1, -1):
		ring.append(Vector2i(x0 - 1, y))
	var runs := 0
	var prev_open: bool = plan.tiles[ring[ring.size() - 1].y * w + ring[ring.size() - 1].x] == 1
	var e_open := false
	for rc in ring:
		var op: bool = plan.tiles[rc.y * w + rc.x] == 1
		if op and not prev_open:
			runs += 1
		prev_open = op
		if rc == e:
			e_open = op
	if runs > 1 or not e_open:
		return false
	# stamp
	var wall_ch: int = String(pk["wall"]).unicode_at(0)
	for wc in shape["walls"]:
		var c := _pocket_cell(e, d, int(wc[0]), int(wc[1]))
		var i: int = c.y * w + c.x
		plan.tiles[i] = 0
		plan.wall[i] = 0 if wall_ch == 35 else wall_ch
		plan.protect[i] = 1
	for fc in shape["floor"]:
		var c := _pocket_cell(e, d, int(fc[0]), int(fc[1]))
		var i: int = c.y * w + c.x
		plan.tiles[i] = 1
		plan.protect[i] = 1
	plan.protect[e.y * w + e.x] = 1
	var rc2 := _pocket_cell(e, d, int(shape["rest"][0]), int(shape["rest"][1]))
	plan.markers[rc2.y * w + rc2.x] = "S"
	var base: float = float(row["shelter"]["safety"].get(kind, 0.6))
	var zn: String = "pocket_%s_%d" % [kind, n]
	plan.rest.append({"cell": [rc2.x, rc2.y], "kind": kind, "marker": "S", "safety": snappedf(clampf(base + (rng.next() - 0.5) * 0.1, 0.0, 1.0), 0.01)})
	plan.zones.append({"name": zn, "kind": "indoor", "x0": x0, "y0": y0, "x1": x1, "y1": y1})
	plan.pockets.append({"zone": zn, "kind": kind, "rest": true, "cell": [rc2.x, rc2.y]})
	return true


# ---- obstacles and open air -----------------------------------------------------------------------------------------------------------------

static func _obs_char(rng: Rng, style: String) -> int:
	var r: float = rng.next()
	if style == "moor":
		return 66 if r < 0.5 else (73 if r < 0.75 else 0)   # B, I, bush
	return 87 if r < 0.85 else 0                             # W, bush


static func _offsets() -> Array:
	if _offs.is_empty():
		var l: Array = []
		for dy in range(-3, 4):
			for dx in range(-3, 4):
				if dx * dx + dy * dy <= 9:
					l.append([dx * dx + dy * dy, dy, dx])
		l.sort()
		for t in l:
			_offs.append(Vector2i(int(t[2]), int(t[1])))
	return _offs


## A cell that may take a solid obstacle: floor with eight floor neighbours (so it can never pinch a path), not protected, not a marker or prop.
static func _can_obstacle(plan: WP, x: int, y: int, entry: Vector2i, exitc: Vector2i) -> bool:
	if x < MARGIN_X or y < MARGIN_Y or x > plan.w - 1 - MARGIN_X or y > plan.h - 1 - MARGIN_Y:
		return false
	var i: int = y * plan.w + x
	if plan.tiles[i] != 1 or plan.protect[i] != 0 or plan.markers.has(i) or plan.prop_cells.has(i):
		return false
	for o in StageGen.N8:
		var j: int = i + o.y * plan.w + o.x
		if plan.tiles[j] != 1 or plan.protect[j] != 0:
			return false
	return Vector2(x, y).distance_to(Vector2(entry)) >= 3.0 and Vector2(x, y).distance_to(Vector2(exitc)) >= 3.0


static func _set_obstacle(plan: WP, x: int, y: int, ch: int) -> void:
	var i: int = y * plan.w + x
	plan.tiles[i] = 0
	plan.wall[i] = ch


static func _obstacles(plan: WP, rng: Rng, style: String, entry: Vector2i, exitc: Vector2i) -> bool:
	var w: int = plan.w
	var h: int = plan.h
	var nrand: int = StageGen.rint(rng, 22, 34) if style == "wood" else StageGen.rint(rng, 10, 16)
	for _k in nrand:
		for _t in 12:
			var x: int = StageGen.rint(rng, MARGIN_X, w - 1 - MARGIN_X)
			var y: int = StageGen.rint(rng, MARGIN_Y, h - 1 - MARGIN_Y)
			if _can_obstacle(plan, x, y, entry, exitc):
				_set_obstacle(plan, x, y, _obs_char(rng, style))
				break
	var dt := StageGen.distance_transform(plan)
	var cand: Array = []
	for i in dt.size():
		if plan.tiles[i] == 1 and dt[i] > COVER_R:
			cand.append(i)
	var offs := _offsets()
	var iters := 0
	while not cand.is_empty() and iters < 400:
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
			if _can_obstacle(plan, ax + o.x, ay + o.y, entry, exitc):
				qx = ax + o.x
				qy = ay + o.y
				break
		if qx < 0:
			return false
		_set_obstacle(plan, qx, qy, _obs_char(rng, style))
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


## Largest distance (cells, exact Euclidean to the nearest wall cell centre, radius-limited search) from a walkable cell to a wall cell. Tests use it:
## the rule holds when it is <= OPEN_R. Walls are the `#BWIw` characters (the border ring included).
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
			if not ".@CS".contains(s2[x]):
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


# ---- decoration, critters, ambient ------------------------------------------------------------------------------------------------------------

static func _free_prop_cell(plan: WP, rng: Rng, entry: Vector2i, exitc: Vector2i, solid: bool) -> Vector2i:
	for _t in 40:
		var x: int = StageGen.rint(rng, MARGIN_X, plan.w - 1 - MARGIN_X)
		var y: int = StageGen.rint(rng, MARGIN_Y, plan.h - 1 - MARGIN_Y)
		var i: int = y * plan.w + x
		if plan.tiles[i] != 1 or plan.protect[i] != 0 or plan.markers.has(i):
			continue
		if Vector2(x, y).distance_to(Vector2(entry)) < 3.0 or Vector2(x, y).distance_to(Vector2(exitc)) < 3.0:
			continue
		var ok := true
		for o in StageGen.N8:
			var j: int = i + o.y * plan.w + o.x
			if plan.prop_cells.has(j) or (solid and plan.tiles[j] != 1):
				ok = false
				break
		if ok and not plan.prop_cells.has(i):
			return Vector2i(x, y)
	return Vector2i(-1, -1)


static func _spread_cell(plan: WP, rng: Rng, taken: Array, min_gap: float, min_start: float, entry: Vector2i) -> Vector2i:
	for _t in 60:
		var x: int = StageGen.rint(rng, MARGIN_X, plan.w - 1 - MARGIN_X)
		var y: int = StageGen.rint(rng, MARGIN_Y, plan.h - 1 - MARGIN_Y)
		if not plan.walkable(x, y):
			continue
		var i: int = y * plan.w + x
		if plan.markers.has(i) or plan.prop_cells.has(i):
			continue
		var c := Vector2(x, y)
		if c.distance_to(Vector2(entry)) < min_start:
			continue
		var ok := true
		for t in taken:
			if c.distance_to(Vector2(t)) < min_gap:
				ok = false
				break
		if ok:
			return Vector2i(x, y)
	return Vector2i(-1, -1)


static func _in_pocket(plan: WP, c: Vector2i) -> bool:
	for z in plan.zones:
		if c.x >= z["x0"] - 1 and c.x <= z["x1"] + 1 and c.y >= z["y0"] - 1 and c.y <= z["y1"] + 1:
			return true
	return false


static func _decorate(plan: WP, rng: Rng, row: Dictionary, style: String, info: Dictionary, entry: Vector2i, exitc: Vector2i) -> void:
	var fa: Dictionary = row["fauna"]
	var amb: Dictionary = row["ambient"]
	# solid decoration: boulders and stumps (World treats both as solid props, StageGen.SOLID_PROPS knows both)
	var nst: int = StageGen.rint(rng, int(fa["stumps"][0]), int(fa["stumps"][1]))
	for _s in nst:
		var c := _free_prop_cell(plan, rng, entry, exitc, true)
		if c.x >= 0:
			plan.add_prop("stump", c.x, c.y)
	var nbo: int = StageGen.rint(rng, int(fa["boulders"][0]), int(fa["boulders"][1]))
	for _b in nbo:
		var c2 := _free_prop_cell(plan, rng, entry, exitc, true)
		if c2.x >= 0:
			plan.add_prop("boulder", c2.x, c2.y)
	# lights: fireflies (wood) / will-o'-the-wisps (moor) are glowworm props with their own radius
	var nl: int = StageGen.rint(rng, int(row["lights"]["min"]), int(row["lights"]["max"]))
	var lr: float = float(amb.get("lightRadius", 2.0))
	var lcells: Array = []
	if style == "moor":
		for pc in plan.pool_cells:
			if lcells.size() < nl:
				var c3 := _near_free_floor(plan, Vector2i(int(pc[0]), int(pc[1])))
				if c3.x >= 0:
					lcells.append(c3)
	while lcells.size() < nl:
		var c4 := _free_prop_cell(plan, rng, entry, exitc, false)
		if c4.x < 0:
			break
		if plan.prop_cells.has(c4.y * plan.w + c4.x):
			continue
		lcells.append(c4)
	for lc in lcells:
		if not plan.prop_cells.has(lc.y * plan.w + lc.x):
			plan.props.append({"type": "glowworm", "col": lc.x, "row": lc.y, "light": lr})
			plan.prop_cells[lc.y * plan.w + lc.x] = "glowworm"
	_critters(plan, rng, row, style, entry)
	_anchors(plan, rng, row, style, info, entry)


static func _near_free_floor(plan: WP, c: Vector2i) -> Vector2i:
	for sc in [1, 2]:
		for o in _offsets():
			var x: int = c.x + o.x * sc
			var y: int = c.y + o.y * sc
			if plan.walkable(x, y) and plan.protect[y * plan.w + x] == 0 and not plan.markers.has(y * plan.w + x) and not plan.prop_cells.has(y * plan.w + x):
				return Vector2i(x, y)
	return Vector2i(-1, -1)


static func _critters(plan: WP, rng: Rng, row: Dictionary, style: String, entry: Vector2i) -> void:
	var prey: Dictionary = row["preyCount"]
	var fa: Dictionary = row["fauna"]
	var total: int = mini(StageGen.rint(rng, int(prey["min"]), int(prey["max"])), int(row["caps"]["critters"]))
	var big: String = String(fa["big"])
	var small: String = String(fa["small"])
	var nbig: int = mini(StageGen.rint(rng, int(fa["bigCount"][0]), int(fa["bigCount"][1])), total - 3)
	var taken: Array = []
	var gap_big: float = 12.0 if style == "wood" else 9.0
	var start_big: float = 10.0 if style == "wood" else 18.0
	for _b in nbig:
		for _try in 6:
			var c := _spread_cell(plan, rng, taken, gap_big, start_big, entry)
			if c.x >= 0 and not _in_pocket(plan, c):
				taken.append(c)
				plan.spawns.append({"species": big, "cell": [c.x, c.y]})
				break
	var ns: int = total - plan.spawns.size()
	var guard := 0
	while ns > 0 and guard < 80:
		guard += 1
		var c2 := _spread_cell(plan, rng, taken, 4.0, 8.0, entry)
		if c2.x >= 0 and not _in_pocket(plan, c2):
			taken.append(c2)
			plan.spawns.append({"species": small, "cell": [c2.x, c2.y]})
			ns -= 1


static func _anchors(plan: WP, rng: Rng, row: Dictionary, style: String, info: Dictionary, entry: Vector2i) -> void:
	var amb: Dictionary = row["ambient"]
	var w: int = plan.w
	var taken: Array = []
	# wind: open cells, far apart
	var dt := StageGen.distance_transform(plan)
	var nw: int = StageGen.rint(rng, int(amb["wind"][0]), int(amb["wind"][1]))
	# the first wind is the one the player hears at the start: 6-10 cells from the entry door
	for _t in 80:
		var ang: float = rng.next() * TAU
		var rr: float = StageGen.rrange(rng, 6.0, 10.0)
		var wx: int = int(round(float(entry.x) + cos(ang) * rr))
		var wy: int = int(round(float(entry.y) + sin(ang) * rr))
		if wx >= 5 and wy >= 3 and wx < w - 5 and wy < plan.h - 3 and plan.walkable(wx, wy) and dt[wy * w + wx] >= 1.5:
			plan.add_anchor("wind", wx, wy)
			taken.append([wx, wy])
			break
	for _k in nw - taken.size():
		for _t in 60:
			var x: int = StageGen.rint(rng, 6, w - 7)
			var y: int = StageGen.rint(rng, 4, plan.h - 5)
			if plan.walkable(x, y) and dt[y * w + x] >= 2.5 and _far_from(taken, x, y, 14.0):
				plan.add_anchor("wind", x, y)
				taken.append([x, y])
				break
	if style == "wood":
		var creek: PackedInt32Array = info["creek"]
		var y2: int = 4 + StageGen.rint(rng, 0, 3)
		var nc := 0
		while y2 < plan.h - 3 and nc < int(amb["creekMax"]):
			if plan.tiles[y2 * w + creek[y2]] != 2:
				y2 += 2   # a ford row: the anchor goes on water
				continue
			plan.add_anchor("creek", creek[y2], y2)
			nc += 1
			y2 += int(amb["creekEvery"])
		# owls: a floor cell beside a trunk
		var no: int = StageGen.rint(rng, int(amb["owls"][0]), int(amb["owls"][1]))
		var otaken: Array = []
		for _o in no:
			for _t in 120:
				var x3: int = StageGen.rint(rng, 6, w - 7)
				var y3: int = StageGen.rint(rng, 3, plan.h - 4)
				if not plan.walkable(x3, y3) or not _far_from(otaken, x3, y3, 12.0):
					continue
				var beside := false
				for o in StageGen.N4:
					var j: int = (y3 + o.y) * w + x3 + o.x
					if plan.tiles[j] == 0 and plan.wall[j] == 87:
						beside = true
				if beside:
					plan.add_anchor("owl", x3, y3)
					otaken.append([x3, y3])
					break
	else:
		var ncr: int = StageGen.rint(rng, int(amb["crickets"][0]), int(amb["crickets"][1]))
		var ctaken: Array = []
		for _c in ncr:
			for _t in 60:
				var x4: int = StageGen.rint(rng, 5, w - 6)
				var y4: int = StageGen.rint(rng, 3, plan.h - 4)
				if plan.walkable(x4, y4) and _far_from(ctaken, x4, y4, 6.0) and Vector2(x4, y4).distance_to(Vector2(entry)) > 5.0:
					plan.add_anchor("cricket", x4, y4)
					ctaken.append([x4, y4])
					break
		for pc in plan.pool_cells:
			plan.add_anchor("ripple", int(pc[0]), int(pc[1]))


static func _far_from(taken: Array, x: int, y: int, gap: float) -> bool:
	for t in taken:
		if Vector2(x, y).distance_to(Vector2(int(t[0]), int(t[1]))) < gap:
			return false
	return true


# ---- def assembly ---------------------------------------------------------------------------------------------------------------------------

static func _rows(plan: WP) -> Array:
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
				ch = "."
			if plan.markers.has(i):
				ch = plan.markers[i]
			for d in plan.doors:
				if d["col"] == x and d["row"] == y:
					ch = "D"
			s += ch
		rows.append(s)
	return rows


static func _assemble(plan: WP, row: Dictionary, style: String, seed: int, attempt: int, info: Dictionary) -> Dictionary:
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
	var lights: Array = []
	for p in plan.props:
		if p["type"] == "glowworm":
			lights.append({"cell": [p["col"], p["row"]], "radius": float(p.get("light", World.DEFAULT_LIGHT["glowworm"])), "kind": "glowworm"})
	var rest: Array = []
	for r in plan.rest:
		rest.append({"cell": r["cell"], "kind": r["kind"], "marker": r["marker"], "safety": r["safety"]})
	var places := {"entry": [plan.start.x, plan.start.y], "exit": [int(xd["col"]) + int(xf[0]), int(xd["row"]) + int(xf[1])]}
	if info.has("fords"):
		for k in info["fords"].size():
			var fy: int = info["fords"][k]
			places["ford_%d" % (k + 1)] = [int(info["creek"][fy]), fy]
	var mats: Dictionary = row["materials"].duplicate()
	return {
		"name": String(row["id"]),
		"kind": String(row["kind"]),
		"floor": String(row["floor"]),
		"materials": mats,
		"rows": _rows(plan),
		"doors": doors,
		"props": plan.props,
		"zones": plan.zones,
		"paths": [],
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
		"lights": lights,
		"gen": {"attempt": attempt, "style": style, "pockets": plan.pockets.size(), "fords": info.get("fords", []).size()},
	}
