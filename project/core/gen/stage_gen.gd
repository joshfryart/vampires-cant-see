class_name StageGen
extends RefCounted
## Stage generator framework for the roguelike mode (docs/ROGUELIKE.md, "stages.json schema").
## generate(stage_id, seed) is a pure function: the same (id, seed) always returns an identical def (all randomness is mulberry32 from core/rng.gd).
## The def is a data/maps.json map entry (rows, kind, floor, materials, doors, props, zones, paths, hides, places) plus extra keys that
## World.from_def ignores: stage, seed, start, exit, beats, rest, pockets, ambient, critters, lights, gen.
## Tile grid values: 0 wall, 1 floor, 2 still water. Markers (@ C S), props, anchors, spawns and doors are layered on top by the Plan.

const MAX_W := 64
const MAX_H := 48
const CHUNKS_PATH := "res://data/rogue/chunks.json"
const T_WALL := 0
const T_FLOOR := 1
const T_WATER := 2
const DIR_OF := {"n": Vector2i(0, -1), "s": Vector2i(0, 1), "e": Vector2i(1, 0), "w": Vector2i(-1, 0)}
const N4 := [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]
const N8 := [Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0), Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1)]
const SOLID_PROPS := ["stalagmite", "coffin", "boulder", "stump"]
## Walkable cells per second of the player (Player.DEFAULT_CFG moveSpeed) and the default night length in seconds (Night.DEFAULTS nightSec).
## Cover rule: a rest spot must be within COVER_FRAC of a night's walk, i.e. 0.4 * 480 s * 3 cells/s = 576 BFS cells (see cover_limit).
const COVER_FRAC := 0.4

static var _chunks: Variant = null
static var _stages: Variant = null


static func chunks() -> Dictionary:
	if _chunks == null:
		var f := FileAccess.open(CHUNKS_PATH, FileAccess.READ)
		_chunks = JSON.parse_string(f.get_as_text()) if f != null else {}
	return _chunks


static func stage_row(stage_id: String) -> Dictionary:
	var d: Variant = GameData.load_rogue("stages")
	if d is Dictionary and d.get("stages") is Array:
		for r in d["stages"]:
			if r is Dictionary and r.get("id") == stage_id:
				return r
	return {}


## Pure function of (stage_id, seed). Returns {} for an unknown stage or if no attempt satisfied every constraint.
static func generate(stage_id: String, seed: int) -> Dictionary:
	var row := stage_row(stage_id)
	if row.is_empty():
		return {}
	match String(row.get("generator", "")):
		"cave":
			return GenCave.generate(row, seed)
		"wood", "moor":
			return GenWild.generate(row, seed, String(row["generator"]))
	return {}


## Validation hook: WorldValidate on the def (single map; the cross-map door link is checked by validate_all with a stub).
static func validate(def: Dictionary) -> Dictionary:
	return WorldValidate.validate(def, null, null, {"requireStart": true})


## Walk speed in cells/s and night length in s used by the cover rule.
static func night_walk_cells() -> float:
	return float(Night.DEFAULTS["nightSec"]) * float(Player.DEFAULT_CFG["moveSpeed"])


static func cover_limit(frac: float = COVER_FRAC) -> int:
	return int(floor(night_walk_cells() * frac))


# ---- rng helpers --------------------------------------------------------------------------------------------------------------------------

static func seed_for(seed: int, attempt: int) -> float:
	var a: int = JsMath.imul(seed & JsMath.M32, 0x9E3779B1)
	var b: int = JsMath.imul((attempt * 0x85EBCA6B + 0x1234567) & JsMath.M32, 0xC2B2AE35)
	return float((a ^ b) & JsMath.M32)


## Inclusive integer in [lo, hi].
static func rint(rng: Rng, lo: int, hi: int) -> int:
	return lo + int(floor(rng.next() * float(hi - lo + 1)))


static func rrange(rng: Rng, lo: float, hi: float) -> float:
	return lo + (hi - lo) * rng.next()


static func shuffle(rng: Rng, a: Array) -> void:
	var i := a.size() - 1
	while i > 0:
		var j: int = int(floor(rng.next() * float(i + 1)))
		var t: Variant = a[i]
		a[i] = a[j]
		a[j] = t
		i -= 1


# ---- the plan: a mutable grid plus everything layered on it ---------------------------------------------------------------------------------

class Plan:
	extends RefCounted
	var w: int
	var h: int
	var tiles := PackedByteArray()
	var protect := PackedByteArray()
	var markers: Dictionary = {}   # idx -> "@" | "C" | "S"
	var doors: Array = []          # {id, col, row, facing}
	var props: Array = []          # {type, col, row}
	var prop_cells: Dictionary = {}  # idx -> type
	var anchors: Array = []        # {cell: [x, y], kind}
	var spawns: Array = []         # {species, cell: [x, y]}
	var rest: Array = []           # {cell: [x, y], kind, marker, safety}
	var zones: Array = []
	var pockets: Array = []        # {zone, kind, rest, cell: [x, y]}
	var beats: Array = []          # {id, cell: [x, y]}
	var start := Vector2i(-1, -1)
	var start_angle: float = 0.0

	func _init(w_: int, h_: int) -> void:
		w = w_
		h = h_
		tiles.resize(w * h)
		protect.resize(w * h)

	func idx(x: int, y: int) -> int:
		return y * w + x

	func inb(x: int, y: int) -> bool:
		return x >= 0 and y >= 0 and x < w and y < h

	func tile(x: int, y: int) -> int:
		return tiles[y * w + x] if inb(x, y) else 0

	func is_open(x: int, y: int) -> bool:
		return inb(x, y) and tiles[y * w + x] == 1

	func is_solid_prop(x: int, y: int) -> bool:
		return SOLID_PROPS.has(prop_cells.get(y * w + x, ""))

	## Walkable for the player: floor (markers included), not a solid prop.
	func walkable(x: int, y: int) -> bool:
		return inb(x, y) and tiles[y * w + x] == 1 and not is_solid_prop(x, y)

	func add_prop(type: String, x: int, y: int) -> void:
		props.append({"type": type, "col": x, "row": y})
		prop_cells[idx(x, y)] = type

	func add_anchor(kind: String, x: int, y: int) -> void:
		anchors.append({"cell": [x, y], "kind": kind})

	func floor_count() -> int:
		var n := 0
		for i in tiles.size():
			if tiles[i] != 0:
				n += 1
		return n

	## Share of non-wall cells in the interior (the border ring is always wall).
	func open_fraction() -> float:
		return float(floor_count()) / float((w - 2) * (h - 2))


# ---- BFS / distance transform ------------------------------------------------------------------------------------------------------------

## Multi-source BFS over walkable cells (4-neighbour). sources are cell indices. Returns Int32 distances, -1 where unreachable.
## The border ring is always wall, so index arithmetic never wraps.
static func bfs(plan: Plan, sources: Array) -> PackedInt32Array:
	var n: int = plan.w * plan.h
	var w: int = plan.w
	var ok := PackedByteArray()
	ok.resize(n)
	for i in n:
		ok[i] = 1 if plan.tiles[i] == 1 else 0
	for k in plan.prop_cells:
		if SOLID_PROPS.has(plan.prop_cells[k]):
			ok[k] = 0
	var dist := PackedInt32Array()
	dist.resize(n)
	dist.fill(-1)
	var queue := PackedInt32Array()
	queue.resize(n)
	var tail := 0
	for s in sources:
		if dist[s] < 0:
			dist[s] = 0
			queue[tail] = s
			tail += 1
	var head := 0
	while head < tail:
		var cur: int = queue[head]
		head += 1
		var nd: int = dist[cur] + 1
		var nb: int = cur - 1
		if ok[nb] == 1 and dist[nb] < 0:
			dist[nb] = nd
			queue[tail] = nb
			tail += 1
		nb = cur + 1
		if ok[nb] == 1 and dist[nb] < 0:
			dist[nb] = nd
			queue[tail] = nb
			tail += 1
		nb = cur - w
		if ok[nb] == 1 and dist[nb] < 0:
			dist[nb] = nd
			queue[tail] = nb
			tail += 1
		nb = cur + w
		if ok[nb] == 1 and dist[nb] < 0:
			dist[nb] = nd
			queue[tail] = nb
			tail += 1
	return dist


## Distance in cells from every cell to the nearest wall cell (2-pass chamfer 1 / 1.414). Walls are 0. Water counts as open.
static func distance_transform(plan: Plan) -> PackedFloat32Array:
	var n := plan.w * plan.h
	var dt := PackedFloat32Array()
	dt.resize(n)
	var big := 1.0e9
	for i in n:
		dt[i] = 0.0 if plan.tiles[i] == 0 else big
	var dg := 1.41421356
	for y in plan.h:
		for x in plan.w:
			var i := y * plan.w + x
			if dt[i] == 0.0:
				continue
			var v: float = dt[i]
			if x > 0:
				v = minf(v, dt[i - 1] + 1.0)
			if y > 0:
				v = minf(v, dt[i - plan.w] + 1.0)
				if x > 0:
					v = minf(v, dt[i - plan.w - 1] + dg)
				if x < plan.w - 1:
					v = minf(v, dt[i - plan.w + 1] + dg)
			dt[i] = v
	for y in range(plan.h - 1, -1, -1):
		for x in range(plan.w - 1, -1, -1):
			var i := y * plan.w + x
			if dt[i] == 0.0:
				continue
			var v: float = dt[i]
			if x < plan.w - 1:
				v = minf(v, dt[i + 1] + 1.0)
			if y < plan.h - 1:
				v = minf(v, dt[i + plan.w] + 1.0)
				if x < plan.w - 1:
					v = minf(v, dt[i + plan.w + 1] + dg)
				if x > 0:
					v = minf(v, dt[i + plan.w - 1] + dg)
			dt[i] = v
	return dt


# ---- carve helpers -----------------------------------------------------------------------------------------------------------------------

## True when a cell may be carved: inside the margin ring and not protected by a stamped chunk.
static func can_carve(plan: Plan, x: int, y: int, margin: int = 2) -> bool:
	return x >= margin and y >= margin and x < plan.w - margin and y < plan.h - margin and plan.protect[y * plan.w + x] == 0


static func carve(plan: Plan, x: int, y: int, margin: int = 2) -> bool:
	if not can_carve(plan, x, y, margin):
		return false
	if plan.tiles[y * plan.w + x] == 0:
		plan.tiles[y * plan.w + x] = 1
	return true


static func carve_disc(plan: Plan, cx: int, cy: int, r: float) -> void:
	var ri: int = int(ceil(r))
	for y in range(cy - ri, cy + ri + 1):
		for x in range(cx - ri, cx + ri + 1):
			if (x - cx) * (x - cx) + (y - cy) * (y - cy) <= r * r:
				carve(plan, x, y)


## Cellular-automaton blob inside a disc (init fill p, `passes` smoothing passes of the 4-5 rule), keeping the component of the centre.
static func carve_ca_blob(plan: Plan, rng: Rng, cx: int, cy: int, r: int, fill: float = 0.58, passes: int = 4) -> void:
	var size := 2 * r + 1
	var buf := PackedByteArray()
	buf.resize(size * size)
	for y in size:
		for x in size:
			var dx := x - r
			var dy := y - r
			if dx * dx + dy * dy <= r * r:
				buf[y * size + x] = 1 if (rng.next() < fill or dx * dx + dy * dy <= 2) else 0
	for _p in passes:
		var nb := buf.duplicate()
		for y in size:
			for x in size:
				var dx := x - r
				var dy := y - r
				if dx * dx + dy * dy > r * r:
					continue
				var cnt := 0
				for d in N8:
					var nx: int = x + d.x
					var ny: int = y + d.y
					if nx >= 0 and ny >= 0 and nx < size and ny < size and buf[ny * size + nx] == 1:
						cnt += 1
				nb[y * size + x] = 1 if (cnt >= 5 or (buf[y * size + x] == 1 and cnt >= 4)) else 0
				if dx * dx + dy * dy <= 2:
					nb[y * size + x] = 1
		buf = nb
	var seen := PackedByteArray()
	seen.resize(size * size)
	var stack: Array = [r * size + r]
	seen[r * size + r] = 1
	while not stack.is_empty():
		var cur: int = stack.pop_back()
		var x: int = cur % size
		var y: int = cur / size
		for d in N4:
			var nx: int = x + d.x
			var ny: int = y + d.y
			if nx >= 0 and ny >= 0 and nx < size and ny < size and buf[ny * size + nx] == 1 and seen[ny * size + nx] == 0:
				seen[ny * size + nx] = 1
				stack.append(ny * size + nx)
	for y in size:
		for x in size:
			if seen[y * size + x] == 1:
				carve(plan, cx - r + x, cy - r + y)


## Biased drunk walk from a to b carving width 1 or 2. Falls back to a BFS carve around protected cells. Returns false if no route exists.
static func carve_tunnel(plan: Plan, rng: Rng, a: Vector2i, b: Vector2i, width: int, bias: float = 0.68) -> bool:
	var cur := a
	var side: int = 1 if rng.next() < 0.5 else -1
	carve(plan, cur.x, cur.y)
	var steps := 0
	var limit: int = 4 * (absi(b.x - a.x) + absi(b.y - a.y)) + 60
	while cur != b and steps < limit:
		steps += 1
		var dx: int = b.x - cur.x
		var dy: int = b.y - cur.y
		var pref := Vector2i(signi(dx), 0) if absi(dx) >= absi(dy) else Vector2i(0, signi(dy))
		var other := Vector2i(0, signi(dy)) if absi(dx) >= absi(dy) else Vector2i(signi(dx), 0)
		var cands: Array = []
		var r := rng.next()
		if r < bias:
			cands = [pref, other, N4[int(floor(rng.next() * 4.0))]]
		elif r < bias + 0.2:
			cands = [N4[int(floor(rng.next() * 4.0))], pref, other]
		else:
			cands = [other, pref, N4[int(floor(rng.next() * 4.0))]]
		var moved := false
		for d in cands:
			if d == Vector2i.ZERO:
				continue
			var nx: int = cur.x + d.x
			var ny: int = cur.y + d.y
			if can_carve(plan, nx, ny):
				cur = Vector2i(nx, ny)
				carve(plan, nx, ny)
				if width >= 2:
					carve(plan, nx + d.y * side, ny + d.x * side)
				moved = true
				break
		if not moved:
			break
	if cur == b:
		return true
	return _carve_route(plan, cur, b, width)


static func _carve_route(plan: Plan, a: Vector2i, b: Vector2i, width: int) -> bool:
	var prev := PackedInt32Array()
	prev.resize(plan.w * plan.h)
	prev.fill(-2)
	var q: Array = [a.y * plan.w + a.x]
	prev[q[0]] = -1
	var head := 0
	var goal: int = b.y * plan.w + b.x
	while head < q.size() and prev[goal] == -2:
		var cur: int = q[head]
		head += 1
		for d in N4:
			var nx: int = cur % plan.w + d.x
			var ny: int = cur / plan.w + d.y
			if can_carve(plan, nx, ny) and prev[ny * plan.w + nx] == -2:
				prev[ny * plan.w + nx] = cur
				q.append(ny * plan.w + nx)
	if prev[goal] == -2:
		return false
	var c: int = goal
	while c >= 0:
		var x: int = c % plan.w
		var y: int = c / plan.w
		carve(plan, x, y)
		if width >= 2:
			carve(plan, x + 1, y)
		c = prev[c]
	return true


# ---- minimum spanning tree ----------------------------------------------------------------------------------------------------------------

## Kruskal MST over points (Vector2i); `forced` edges ([i, j]) are taken first. Returns [[i, j], ...] with n-1 edges.
static func mst(pts: Array, forced: Array = []) -> Array:
	var n := pts.size()
	var parent: Array = []
	for i in n:
		parent.append(i)
	var edges: Array = []
	for f in forced:
		var ra := _find(parent, f[0])
		var rb := _find(parent, f[1])
		if ra != rb:
			parent[ra] = rb
			edges.append([f[0], f[1]])
	var all: Array = []
	for i in n:
		for j in range(i + 1, n):
			all.append([Vector2(pts[i]).distance_squared_to(Vector2(pts[j])), i, j])
	all.sort_custom(func(a, b): return a[0] < b[0] or (a[0] == b[0] and (a[1] < b[1] or (a[1] == b[1] and a[2] < b[2]))))
	for e in all:
		var ra2 := _find(parent, e[1])
		var rb2 := _find(parent, e[2])
		if ra2 != rb2:
			parent[ra2] = rb2
			edges.append([e[1], e[2]])
	return edges


static func _find(parent: Array, a: int) -> int:
	while parent[a] != a:
		parent[a] = parent[parent[a]]
		a = parent[a]
	return a


# ---- chunk stamping -----------------------------------------------------------------------------------------------------------------------

static func _xdir(d: String, transpose: bool, flip: bool) -> String:
	var o := d
	if transpose:
		o = {"n": "w", "w": "n", "s": "e", "e": "s"}[o]
	if flip:
		o = {"e": "w", "w": "e", "n": "n", "s": "s"}[o]
	return o


## Template size after the transform.
static func chunk_size(ch: Dictionary, transpose: bool) -> Vector2i:
	return Vector2i(int(ch["h"]), int(ch["w"])) if transpose else Vector2i(int(ch["w"]), int(ch["h"]))


## Stamp a chunk template with its top-left at (ox, oy). Walls inside the rect are written too; the rect is protected from later carving.
## Returns {ports: [{cell: Vector2i, out: Vector2i (cell just outside), dir}], beat_cell: Vector2i, rect: Rect2i, spawns/anchors count}.
static func stamp(plan: Plan, ch: Dictionary, legend: Dictionary, ox: int, oy: int, transpose: bool, flip: bool) -> Dictionary:
	var tw: int = int(ch["w"])
	var th: int = int(ch["h"])
	var sz := chunk_size(ch, transpose)
	var rows: Array = ch["rows"]
	var out := {"ports": [], "rect": Rect2i(ox, oy, sz.x, sz.y), "beat_cell": Vector2i(-1, -1), "cells": {}}
	for ty in th:
		var row: String = rows[ty]
		for tx in tw:
			var c: String = row[tx]
			var lg: Dictionary = legend.get(c, {})
			if lg.is_empty() or lg.get("skip", false):
				continue
			var p := _xcell(tx, ty, sz, transpose, flip)
			var x: int = ox + p.x
			var y: int = oy + p.y
			var i := y * plan.w + x
			var t: String = lg.get("tile", "#")
			plan.tiles[i] = 0 if t == "#" else (2 if t == "~" else 1)
			plan.protect[i] = 1
			if t == "D":
				plan.tiles[i] = 0
			if lg.has("marker"):
				plan.markers[i] = lg["marker"]
				if lg["marker"] == "@":
					plan.start = Vector2i(x, y)
			if lg.has("prop"):
				plan.add_prop(String(lg["prop"]), x, y)
			if lg.has("anchor"):
				plan.add_anchor(String(lg["anchor"]), x, y)
			if lg.has("spawn"):
				plan.spawns.append({"species": String(lg["spawn"]), "cell": [x, y]})
			if lg.has("rest"):
				plan.rest.append({"cell": [x, y], "kind": String(lg["rest"]), "marker": String(lg.get("marker", "S")), "safety": float(lg.get("safety", 0.5))})
			if lg.get("door", false):
				var dd: Dictionary = ch.get("door", {})
				plan.doors.append({"id": String(dd.get("id", "exit")), "col": x, "row": y, "facing": String(dd.get("facing", "s"))})
			if not out["cells"].has(c):
				out["cells"][c] = []
			out["cells"][c].append(Vector2i(x, y))
	for pr in ch.get("ports", []):
		var q := _xcell(int(pr[0]), int(pr[1]), sz, transpose, flip)
		var dn := _xdir(String(pr[2]), transpose, flip)
		var cell := Vector2i(ox + q.x, oy + q.y)
		out["ports"].append({"cell": cell, "out": cell + DIR_OF[dn], "dir": dn})
	var ba: Array = ch.get("beat_at", [0, 0])
	var bq := _xcell(int(ba[0]), int(ba[1]), sz, transpose, flip)
	out["beat_cell"] = Vector2i(ox + bq.x, oy + bq.y)
	for z in ch.get("zones", []):
		var r: Array = z["rect"]
		var a := _xcell(int(r[0]), int(r[1]), sz, transpose, flip)
		var b := _xcell(int(r[2]), int(r[3]), sz, transpose, flip)
		plan.zones.append({"name": String(z["name"]), "kind": "indoor", "x0": ox + mini(a.x, b.x), "y0": oy + mini(a.y, b.y), "x1": ox + maxi(a.x, b.x), "y1": oy + maxi(a.y, b.y)})
	return out


static func _xcell(x: int, y: int, sz: Vector2i, transpose: bool, flip: bool) -> Vector2i:
	var px := x
	var py := y
	if transpose:
		px = y
		py = x
	if flip:
		px = sz.x - 1 - px
	return Vector2i(px, py)


# ---- def assembly -------------------------------------------------------------------------------------------------------------------------

static func rows_of(plan: Plan) -> Array:
	var rows: Array = []
	for y in plan.h:
		var s := ""
		for x in plan.w:
			var i := y * plan.w + x
			var ch := "#" if plan.tiles[i] == 0 else ("~" if plan.tiles[i] == 2 else ".")
			if plan.markers.has(i):
				ch = plan.markers[i]
			for d in plan.doors:
				if d["col"] == x and d["row"] == y:
					ch = "D"
			s += ch
		rows.append(s)
	return rows


# ---- analysis (used by the generator as its acceptance test and by tests/unit/test_stage_gen.gd) ------------------------------------------------

## Rebuild a Plan (tiles, markers, props) from a def so BFS and the distance transform work on a finished map.
static func plan_from_def(def: Dictionary) -> Plan:
	var rows: Array = def["rows"]
	var plan := Plan.new(String(rows[0]).length(), rows.size())
	for y in plan.h:
		var s: String = rows[y]
		for x in plan.w:
			var c := s[x]
			var i := y * plan.w + x
			match c:
				"#", "D", "G", "B", "W", "I", "w":
					plan.tiles[i] = 0
				"~":
					plan.tiles[i] = 2
				_:
					plan.tiles[i] = 1
					if c == "@" or c == "C" or c == "S":
						plan.markers[i] = c
	for p in def.get("props", []):
		plan.prop_cells[plan.idx(int(p["col"]), int(p["row"]))] = String(p["type"])
	var st: Variant = def.get("start")
	if st is Dictionary:
		plan.start = Vector2i(int(st["cell"][0]), int(st["cell"][1]))
	return plan


## Acceptance report for a stage def. `row` (the stages.json row) enables the row-specific limits; ok is false when any reason is listed.
static func analyze(def: Dictionary, row: Dictionary = {}) -> Dictionary:
	var reasons: Array = []
	var plan := plan_from_def(def)
	var rep := {"ok": false, "reasons": reasons, "exit_reachable": false, "unreachable": 0, "open_fraction": 0.0, "max_rest_dist": -1, "depths": {}}
	if plan.start.x < 0 or not plan.walkable(plan.start.x, plan.start.y):
		reasons.append("no start")
		return rep
	var dist := bfs(plan, [plan.idx(plan.start.x, plan.start.y)])
	var unreach := 0
	var walk_cells := 0
	for i in dist.size():
		if plan.tiles[i] == 1 and not SOLID_PROPS.has(plan.prop_cells.get(i, "")):
			walk_cells += 1
			if dist[i] < 0:
				unreach += 1
	rep["unreachable"] = unreach
	rep["walkable"] = walk_cells
	if unreach > 0:
		reasons.append("%d unreachable floor cells" % unreach)
	var ex: Variant = def.get("exit")
	if ex is Dictionary:
		var a: Array = ex["arrival"]
		var ai: int = int(a[1]) * plan.w + int(a[0])
		rep["exit_reachable"] = plan.inb(int(a[0]), int(a[1])) and dist[ai] >= 0
	if not rep["exit_reachable"]:
		reasons.append("exit not reachable")
	rep["open_fraction"] = plan.open_fraction()
	# beat depth order (spurs hang off the path, so they are not ordered)
	var last := -1
	var order_ok := true
	for b in def.get("beats", []):
		var bi: int = int(b["cell"][1]) * plan.w + int(b["cell"][0])
		rep["depths"][b["id"]] = dist[bi]
		if b["id"] == "dead_end_spurs":
			continue
		if dist[bi] <= last:
			order_ok = false
		last = dist[bi]
	if not order_ok:
		reasons.append("beats not in depth order")
	# rest spots and the cover rule
	var srcs: Array = []
	for r in def.get("rest", []):
		srcs.append(int(r["cell"][1]) * plan.w + int(r["cell"][0]))
	if srcs.is_empty():
		reasons.append("no rest spots")
	else:
		var rd := bfs(plan, srcs)
		var mx := 0
		for i in rd.size():
			if plan.tiles[i] == 1 and not SOLID_PROPS.has(plan.prop_cells.get(i, "")):
				if rd[i] < 0:
					mx = 1 << 30
				else:
					mx = maxi(mx, rd[i])
		rep["max_rest_dist"] = mx
		var frac: float = float(row.get("shelter", {}).get("coverFrac", COVER_FRAC))
		if mx > cover_limit(frac):
			reasons.append("rest spot too far (%d > %d)" % [mx, cover_limit(frac)])
	if not row.is_empty():
		var fr: Dictionary = row["openFraction"]
		if rep["open_fraction"] < float(fr["min"]) or rep["open_fraction"] > float(fr["max"]):
			reasons.append("open fraction %.3f" % rep["open_fraction"])
		var caps: Dictionary = row["caps"]
		if def.get("props", []).size() > int(caps["props"]):
			reasons.append("too many props")
		if def.get("lights", []).size() > int(caps["lights"]):
			reasons.append("too many lights")
		if def.get("ambient", []).size() > int(caps["ambient"]):
			reasons.append("too many ambient anchors")
		if def.get("critters", []).size() > int(caps["critters"]):
			reasons.append("too many critters")
		var lt: Dictionary = row["lights"]
		var nl: int = def.get("lights", []).size()
		if nl < int(lt["min"]) or nl > int(lt["max"]):
			reasons.append("light count %d" % nl)
		var sh: Dictionary = row["shelter"]
		if def.get("pockets", []).size() < int(sh["pockets"]["min"]):
			reasons.append("too few pockets")
		var sc := 0
		for r in def.get("rest", []):
			if r["kind"] != "coffin":
				sc += 1
		if sc < int(sh["restSpots"]["min"]):
			reasons.append("too few rest spots")
	rep["ok"] = reasons.is_empty()
	return rep
