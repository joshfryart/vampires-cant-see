class_name ContourField
extends RefCounted
## Smooth wall outlines for the ink-etched style (docs/STYLE.md sections 1 and 2). Pure and headless.
##
## The exposed faces of solid cells are chained into closed loops (solid on the same side of every edge, out of bounds counts as solid), each loop is
## resampled every 0.25 cell with a forced vertex at every grid corner, convex corners are rounded with an arc inside the rock (radius r), concave corners
## get a small fillet (radius rc, the only place the outline moves out, by at most rc * (sqrt 2 - 1)), and every vertex is displaced inward along its grid
## normal by a bounded noise that is a function of the integer world lattice only (so it does not depend on where a loop starts or in which order loops are found).
## Every vertex keeps an exact grid anchor (a point on the grid boundary): the shader samples sonar light at the anchor, so brightness is the grid's.
## Collision, Raycast.trace, Sonar and the audio never look at this: the field is a drawing aid.
##
## Coordinates are JS (x, y) world cells. The outward normal of an edge with direction d is (d.y, -d.x) (it points into the open cell).

## Face normals in JS (x, y): north, south, west, east (same order as WorldMeshBuilder.SIDES).
const SIDES := [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]
## Style name -> id (docs/STYLE.md "Per-material parameters"). "gibbet" is the fence variant. Unmapped tiles are style 0 (built / legacy).
const STYLE_IDS := {"rock": 1, "thicket": 2, "gorse": 3, "trunk": 4, "cairn": 5, "milestone": 6, "fence": 7, "gibbet": 7, "timber": 8, "drystone": 9}
## Style id -> [A (max inward displacement), r (convex radius), rc (concave fillet radius), noise frequency per cell, octaves].
const PARAMS := [
	[0.0, 0.0, 0.0, 0.0, 0],
	[0.18, 0.30, 0.15, 0.9, 3],
	[0.20, 0.30, 0.15, 1.6, 2],
	[0.15, 0.30, 0.15, 1.6, 2],
	[0.04, 0.30, 0.10, 0.6, 2],
	[0.10, 0.30, 0.10, 1.2, 2],
	[0.0, 0.12, 0.0, 0.0, 0],
	[0.0, 0.0, 0.0, 0.0, 0],
	[0.0, 0.05, 0.0, 0.0, 0],
	[0.05, 0.15, 0.05, 1.0, 2],
]
const SPACING := 0.25
## Hard limits (cells): |p - anchor| and the Hausdorff distance to the grid boundary; the noise itself never exceeds A <= 0.2 per face.
const MAX_ANCHOR := 0.25
const SADDLE_R := 0.1
const THIN_CAP := 0.15
const PILLAR_CAP := 0.10
## Displacement cap on a convex rounding arc, as a fraction of its radius.
const ARC_CAP := 0.6
const BLEND := 0.5
const DOOR_CLEAR := 1.0
const DOOR_RAMP := 0.5
## Arc length offset per loop in UV.x (canonical loop order).
const LOOP_S := 512.0
## COLOR.r of natural faces: signed curvature (1 / cell, convex positive) in +-CURV_RANGE mapped to 0..1.
const CURV_RANGE := 4.0
## Tile codes of doors and windows (D, G, w): the outline stays straight within DOOR_CLEAR of them.
const DOOR_CODES := [68, 71, 119]

class Loop:
	extends RefCounted
	var index: int = 0
	## Anchor perimeter in cells (an integer: the sum of the face edge lengths).
	var length: float = 0.0
	var pos: PackedVector2Array = PackedVector2Array()
	var anchor: PackedVector2Array = PackedVector2Array()
	## Grid normal n_g and visual normal (perpendicular of the central difference); both point into the open cell.
	var ng: PackedVector2Array = PackedVector2Array()
	var nrm: PackedVector2Array = PackedVector2Array()
	## Arc length of the anchors from the loop's first vertex (the lexicographically smallest anchor).
	var s: PackedFloat32Array = PackedFloat32Array()
	## Signed curvature of the displaced outline, 1 / cell, convex (turning toward the rock) positive.
	var curv: PackedFloat32Array = PackedFloat32Array()
	## Per segment i -> i + 1 (the segment starts at vertex i): style id, tile code of its solid cell, link-door flag, face code 0..3 (N S W E).
	var style: PackedByteArray = PackedByteArray()
	var code: PackedInt32Array = PackedInt32Array()
	var link: PackedByteArray = PackedByteArray()
	var ngcode: PackedByteArray = PackedByteArray()
	## Per vertex: 1 at a convex grid corner, 2 at a concave one (the arc midpoint / the sharp vertex), else 0.
	var corner: PackedByteArray = PackedByteArray()
	## Per vertex: 1 where the outline turns sharply and the shading normal must be split (unrounded corners).
	var hard: PackedByteArray = PackedByteArray()
	## Per vertex: 1 on a concave fillet (pinned: never smoothed).
	var fillet: PackedByteArray = PackedByteArray()
	## Per vertex: 1 on a convex rounding arc.
	var arc: PackedByteArray = PackedByteArray()

	func size() -> int:
		return pos.size()

var width: int = 0
var height: int = 0
var map_seed: int = 0
var loops: Array = []
## CSR segment index: the segments of cell k are cell_seg[cell_start[k] .. cell_start[k + 1]) (global segment ids), k = cy * width + cx.
var cell_start: PackedInt32Array = PackedInt32Array()
var cell_seg: PackedInt32Array = PackedInt32Array()
## Per global segment: (x0, y0, x1, y1), its loop and its start vertex in that loop.
var seg_xy: PackedFloat32Array = PackedFloat32Array()
var seg_loop: PackedInt32Array = PackedInt32Array()
var seg_vert: PackedInt32Array = PackedInt32Array()

# ---- build-time scratch (edges of the grid boundary) ----
var _sx: PackedInt32Array = PackedInt32Array()
var _sy: PackedInt32Array = PackedInt32Array()
var _dx: PackedInt32Array = PackedInt32Array()
var _dy: PackedInt32Array = PackedInt32Array()
var _side: PackedInt32Array = PackedInt32Array()
var _estyle: PackedInt32Array = PackedInt32Array()
var _ecode: PackedInt32Array = PackedInt32Array()
var _elink: PackedByteArray = PackedByteArray()
var _ecap: PackedFloat32Array = PackedFloat32Array()


## The field of a world, built once and cached on world.contour.
static func for_world(world: World) -> ContourField:
	if world.contour == null:
		world.contour = build(world)
	return world.contour


static func build(world: World) -> ContourField:
	var f := ContourField.new()
	f.width = world.width
	f.height = world.height
	f.map_seed = world.map_seed
	f._run(world)
	return f


func loop_count() -> int:
	return loops.size()


func vertex_total() -> int:
	var n := 0
	for l in loops:
		n += l.pos.size()
	return n


func segment_total() -> int:
	return seg_loop.size()


## Hash over every array of every loop: equal fingerprints mean byte-identical outlines.
func fingerprint() -> int:
	var buf := PackedByteArray()
	for l in loops:
		buf.append_array(l.pos.to_byte_array())
		buf.append_array(l.anchor.to_byte_array())
		buf.append_array(l.ng.to_byte_array())
		buf.append_array(l.nrm.to_byte_array())
		buf.append_array(l.s.to_byte_array())
		buf.append_array(l.curv.to_byte_array())
		buf.append_array(l.style)
		buf.append_array(l.code.to_byte_array())
		buf.append_array(l.link)
		buf.append_array(l.ngcode)
		buf.append_array(l.corner)
	return hash(buf)


# ---- noise (a function of integer lattice coordinates only) ----

static func _hash01(ix: int, iy: int, sd: int) -> float:
	var h: int = (ix * 374761393 + iy * 668265263 + sd * 1274126177) & 0xFFFFFFFF
	h = ((h ^ (h >> 13)) * 1103515245) & 0xFFFFFFFF
	h = h ^ (h >> 16)
	return float(h & 0xFFFF) / 65536.0


static func _vnoise(x: float, y: float, sd: int) -> float:
	var ix: int = floori(x)
	var iy: int = floori(y)
	var fx: float = x - ix
	var fy: float = y - iy
	var ux: float = fx * fx * (3.0 - 2.0 * fx)
	var uy: float = fy * fy * (3.0 - 2.0 * fy)
	var a: float = _hash01(ix, iy, sd)
	var b: float = _hash01(ix + 1, iy, sd)
	var c: float = _hash01(ix, iy + 1, sd)
	var d: float = _hash01(ix + 1, iy + 1, sd)
	return lerpf(lerpf(a, b, ux), lerpf(c, d, ux), uy)


## Seed of one style's noise.
static func style_seed(map_seed: int, style: int) -> int:
	return (map_seed ^ ((style * 0x9E3779B1) & 0xFFFFFFFF)) & 0xFFFFFFFF


## fbm in 0..1 at the lattice point q = round(anchor * 4).
static func fbm(qx: int, qy: int, freq: float, octaves: int, sd: int) -> float:
	if octaves <= 0:
		return 0.0
	var x: float = qx * 0.25 * freq
	var y: float = qy * 0.25 * freq
	var sum := 0.0
	var amp := 0.5
	var norm := 0.0
	for o in octaves:
		sum += amp * _vnoise(x + o * 17.3, y - o * 9.1, sd + o * 101)
		norm += amp
		x *= 2.03
		y *= 2.03
		amp *= 0.5
	return clampf((sum / norm - 0.2) / 0.6, 0.0, 1.0)


# ---- build ----

func _style_of_cell(world: World, cx: int, cy: int, by_code: Dictionary) -> int:
	var code: int = 35
	if cx >= 0 and cy >= 0 and cx < width and cy < height:
		code = world.tile_grid[cy * width + cx]
	return int(by_code.get(code, 0))


func _run(world: World) -> void:
	var W := width
	var H := height
	var by_code := {}
	for ch in world.wall_style:
		var key := String(ch)
		if key.length() > 0:
			by_code[key.unicode_at(0)] = int(STYLE_IDS.get(String(world.wall_style[ch]), 0))
	# 1. edges of the grid boundary, solid cell on the same side of every edge
	var first := {}
	var second := {}
	for cy in range(-1, H + 1):
		for cx in range(-1, W + 1):
			if not world.cell_solid(cx, cy):
				continue
			for si in 4:
				var n: Vector2i = SIDES[si]
				var nx := cx + n.x
				var ny := cy + n.y
				if nx < 0 or ny < 0 or nx >= W or ny >= H:
					continue
				if world.cell_solid(nx, ny):
					continue
				var d := Vector2i(-n.y, n.x)
				var sx: int = (2 * cx + 1 + n.x - d.x) / 2
				var sy: int = (2 * cy + 1 + n.y - d.y) / 2
				var e := _sx.size()
				_sx.append(sx)
				_sy.append(sy)
				_dx.append(d.x)
				_dy.append(d.y)
				_side.append(si)
				var in_b: bool = cx >= 0 and cy >= 0 and cx < W and cy < H
				_estyle.append(_style_of_cell(world, cx, cy, by_code))
				_ecode.append(world.tile_grid[cy * W + cx] if in_b else 35)
				_elink.append(1 if (in_b and world.is_link_door(cx, cy)) else 0)
				var cap := 1.0
				if not world.cell_solid(cx - n.x, cy - n.y):
					cap = THIN_CAP
				if not (world.cell_solid(cx - 1, cy) or world.cell_solid(cx + 1, cy) or world.cell_solid(cx, cy - 1) or world.cell_solid(cx, cy + 1)):
					cap = minf(cap, PILLAR_CAP)
				_ecap.append(cap)
				var k: int = sy * (W + 1) + sx
				if first.has(k):
					second[k] = e
				else:
					first[k] = e
	# 2. chain into loops; at a saddle take the convex turn so the open space stays connected
	var ne := _sx.size()
	var used := PackedByteArray()
	used.resize(ne)
	var raw: Array = []
	for e0 in ne:
		if used[e0] == 1:
			continue
		var le := PackedInt32Array()
		var e := e0
		while true:
			used[e] = 1
			le.append(e)
			var k: int = (_sy[e] + _dy[e]) * (W + 1) + _sx[e] + _dx[e]
			var c1: int = first.get(k, -1)
			if c1 < 0:
				break
			var nxt := c1
			var c2: int = second.get(k, -1)
			if c2 >= 0:
				if not (_dx[c1] == -_dy[e] and _dy[c1] == _dx[e]):
					nxt = c2
			if nxt == e0 or used[nxt] == 1:
				break
			e = nxt
		raw.append(le)
	# 3. canonical order: rotate to the smallest (y, x, side) start, sort loops by that key
	var keyed: Array = []
	for le in raw:
		var best := 0
		var bk := 1 << 60
		for i in le.size():
			var e: int = le[i]
			var kk: int = (_sy[e] * 4096 + _sx[e]) * 4 + _side[e]
			if kk < bk:
				bk = kk
				best = i
		var rot := PackedInt32Array()
		for i in le.size():
			rot.append(le[(best + i) % le.size()])
		keyed.append([bk, rot])
	keyed.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var specials: Array = []
	for cy in H:
		for cx in W:
			if DOOR_CODES.has(world.tile_grid[cy * W + cx]):
				specials.append(Vector2(cx, cy))
	for li in keyed.size():
		loops.append(_make_loop(world, keyed[li][1], li, specials))
	_index_segments()
	_sx = PackedInt32Array()
	_sy = PackedInt32Array()
	_dx = PackedInt32Array()
	_dy = PackedInt32Array()
	_side = PackedInt32Array()
	_estyle = PackedInt32Array()
	_ecode = PackedInt32Array()
	_elink = PackedByteArray()
	_ecap = PackedFloat32Array()


## Rounding radius at the corner between edge `ein` and edge `eout` (0 for a flush vertex or a sharp style); also returns the corner type via `ty[0]`.
func _corner_radius(world: World, ein: int, eout: int, ty: Array) -> float:
	var t: int = 0
	var cross: int = _dx[ein] * _dy[eout] - _dy[ein] * _dx[eout]
	if cross != 0:
		# convex when the outgoing edge points toward the solid side of the incoming one: (-dy, dx)
		t = 1 if (_dx[eout] == -_dy[ein] and _dy[eout] == _dx[ein]) else 2
	ty[0] = t
	if t == 0:
		return 0.0
	if t == 1:
		var r: float = PARAMS[_estyle[ein]][1]
		var vx: int = _sx[eout]
		var vy: int = _sy[eout]
		var s00: bool = world.cell_solid(vx - 1, vy - 1)
		var s10: bool = world.cell_solid(vx, vy - 1)
		var s01: bool = world.cell_solid(vx - 1, vy)
		var s11: bool = world.cell_solid(vx, vy)
		if (s00 and s11 and not s10 and not s01) or (s10 and s01 and not s00 and not s11):
			r = minf(r, SADDLE_R)
		return r
	return minf(float(PARAMS[_estyle[ein]][2]), float(PARAMS[_estyle[eout]][2]))


func _make_loop(world: World, le: PackedInt32Array, index: int, specials: Array) -> Loop:
	var M := le.size()
	var L := Loop.new()
	L.index = index
	L.length = float(M)
	# corner radius and type per start vertex k (between edge k - 1 and edge k)
	var rk := PackedFloat32Array()
	var tk := PackedInt32Array()
	rk.resize(M)
	tk.resize(M)
	var ty := [0]
	for k in M:
		rk[k] = _corner_radius(world, le[(k - 1 + M) % M], le[k], ty)
		tk[k] = ty[0]
	var pos0 := PackedVector2Array()
	var anchor := PackedVector2Array()
	var ng := PackedVector2Array()
	var vedge := PackedInt32Array()
	var cap := PackedFloat32Array()
	var corner := PackedByteArray()
	var hard := PackedByteArray()
	var fillet := PackedByteArray()
	var arc := PackedByteArray()
	for k in M:
		var ek: int = le[k]
		var km: int = le[(k - 1 + M) % M]
		var V := Vector2(_sx[ek], _sy[ek])
		var din := Vector2(_dx[km], _dy[km])
		var dout := Vector2(_dx[ek], _dy[ek])
		var nin := Vector2(din.y, -din.x)
		var nout := Vector2(dout.y, -dout.x)
		var r: float = rk[k]
		var t: int = tk[k]
		var ccap: float = minf(_ecap[km], _ecap[ek])
		if t != 0 and r > 0.0:
			var center := V + (dout - din) * r
			var nseg: int = 4 if r > 0.2 else 2
			var avg := (nin + nout).normalized()
			var t0 := V - din * r
			for j in nseg + 1:
				var th: float = float(j) / nseg
				var ang: float = th * PI * 0.5
				var dir: Vector2 = (-dout) * cos(ang) + din * sin(ang)
				var a: Vector2
				var g: Vector2
				if j * 2 < nseg:
					a = t0 + din * (r * th * 2.0)
					g = nin.lerp(avg, th * 2.0).normalized()
				elif j * 2 == nseg:
					a = V
					g = avg
				else:
					a = V + dout * (r * (th - 0.5) * 2.0)
					g = avg.lerp(nout, (th - 0.5) * 2.0).normalized()
				pos0.append(center + dir * r)
				anchor.append(a)
				ng.append(g)
				vedge.append(km if j * 2 < nseg else ek)
				# a convex arc keeps its curvature: displacing by more than ~0.6 r folds it (saddles have r = 0.1)
				cap.append(minf(ccap, ARC_CAP * r) if t == 1 else ccap)
				corner.append(t if j * 2 == nseg else 0)
				hard.append(0)
				fillet.append(1 if t == 2 else 0)
				arc.append(1 if t == 1 else 0)
		else:
			pos0.append(V)
			anchor.append(V)
			ng.append((nin + nout).normalized() if t != 0 else nin)
			vedge.append(ek)
			cap.append(ccap)
			corner.append(t)
			hard.append(1 if t != 0 else 0)
			fillet.append(0)
			arc.append(0)
		# interior resample points of edge k
		var ra: float = r if t != 0 else 0.0
		var kn: int = (k + 1) % M
		var rb: float = rk[kn] if tk[kn] != 0 else 0.0
		for ti in range(1, 4):
			var tt: float = ti * SPACING
			if tt > ra + 0.04 and tt < 1.0 - rb - 0.04:
				var q := V + dout * tt
				pos0.append(q)
				anchor.append(q)
				ng.append(nout)
				vedge.append(ek)
				cap.append(_ecap[ek])
				corner.append(0)
				hard.append(0)
				fillet.append(0)
				arc.append(0)
	var n := pos0.size()
	# anchor arc length
	var s := PackedFloat32Array()
	s.resize(n)
	var acum := PackedFloat32Array()
	acum.resize(n)
	var run := 0.0
	for i in n:
		if i > 0:
			run += anchor[i].distance_to(anchor[i - 1])
		acum[i] = run
		s[i] = run
	L.s = s
	# effective amplitude per vertex: style blend, door clearance, thickness cap
	var vstyle := PackedInt32Array()
	vstyle.resize(n)
	for i in n:
		vstyle[i] = _estyle[vedge[i]]
	var amp := PackedFloat32Array()
	amp.resize(n)
	## Style whose noise a vertex uses: its own, or the neighbouring style's when its own has no noise (a built style blending into a natural one).
	var nstyle := PackedInt32Array()
	nstyle.resize(n)
	for i in n:
		var own: int = vstyle[i]
		var a_own: float = PARAMS[own][0]
		var a_eff: float = a_own
		nstyle[i] = own
		var dmin := 99.0
		var other := -1
		var j := (i + 1) % n
		var steps := 0
		while steps < n - 1:
			var dd: float = fposmod(acum[j] - acum[i], L.length)
			if dd >= BLEND:
				break
			if vstyle[j] != own:
				dmin = dd
				other = vstyle[j]
				break
			j = (j + 1) % n
			steps += 1
		j = (i - 1 + n) % n
		steps = 0
		while steps < n - 1:
			var dd2: float = fposmod(acum[i] - acum[j], L.length)
			if dd2 >= BLEND or dd2 >= dmin:
				break
			if vstyle[j] != own:
				dmin = dd2
				other = vstyle[j]
				break
			j = (j - 1 + n) % n
			steps += 1
		if other >= 0:
			var w: float = 0.5 * (1.0 - dmin / BLEND)
			a_eff = lerpf(a_own, PARAMS[other][0], w)
			if int(PARAMS[own][4]) == 0:
				nstyle[i] = other
		a_eff = minf(a_eff, cap[i])
		if a_eff > 0.0 and not specials.is_empty():
			var av := anchor[i]
			var dsp := 99.0
			for sp in specials:
				var ddx: float = maxf(maxf(sp.x - av.x, av.x - (sp.x + 1.0)), 0.0)
				var ddy: float = maxf(maxf(sp.y - av.y, av.y - (sp.y + 1.0)), 0.0)
				dsp = minf(dsp, sqrt(ddx * ddx + ddy * ddy))
			if dsp < DOOR_CLEAR + DOOR_RAMP:
				a_eff *= clampf((dsp - DOOR_CLEAR) / DOOR_RAMP, 0.0, 1.0)
		amp[i] = a_eff
	# displacement, inward only
	var p := PackedVector2Array()
	p.resize(n)
	for i in n:
		var a_eff: float = amp[i]
		if a_eff > 0.0:
			var st: int = nstyle[i]
			var prm: Array = PARAMS[st]
			var q := anchor[i] * 4.0
			var fv := fbm(roundi(q.x), roundi(q.y), prm[3], prm[4], style_seed(map_seed, st))
			p[i] = pos0[i] - ng[i] * (a_eff * fv)
		else:
			p[i] = pos0[i]
	# one [1, 2, 1] / 4 pass over the unpinned vertices
	var sm := p.duplicate()
	for i in n:
		if amp[i] > 0.0 and fillet[i] == 0:
			sm[i] = (p[(i - 1 + n) % n] + p[i] * 2.0 + p[(i + 1) % n]) * 0.25
	p = sm
	# re-clamp: never outward of the face (except on a fillet), and within MAX_ANCHOR of the anchor
	for i in n:
		var d: Vector2 = p[i] - anchor[i]
		if arc[i] == 0 and fillet[i] == 0:
			var dn: float = d.dot(ng[i])
			if dn > 0.0:
				d -= ng[i] * dn
		var ln: float = d.length()
		if ln > MAX_ANCHOR - 1e-4:
			d *= (MAX_ANCHOR - 1e-4) / ln
		p[i] = anchor[i] + d
	L.pos = p
	L.anchor = anchor
	L.ng = ng
	L.corner = corner
	L.hard = hard
	L.fillet = fillet
	L.arc = arc
	# visual normals and curvature from the final outline
	var nrm := PackedVector2Array()
	var curv := PackedFloat32Array()
	nrm.resize(n)
	curv.resize(n)
	for i in n:
		var pm: Vector2 = p[(i - 1 + n) % n]
		var pp: Vector2 = p[(i + 1) % n]
		var tg := pp - pm
		var nv := Vector2(tg.y, -tg.x)
		nrm[i] = nv.normalized() if nv.length_squared() > 1e-12 else ng[i]
		var d1: Vector2 = p[i] - pm
		var d2: Vector2 = pp - p[i]
		var l1 := d1.length()
		var l2 := d2.length()
		if l1 > 1e-6 and l2 > 1e-6:
			curv[i] = atan2(d1.cross(d2), d1.dot(d2)) / (0.5 * (l1 + l2))
		else:
			curv[i] = 0.0
	L.nrm = nrm
	L.curv = curv
	# per segment attributes
	L.style.resize(n)
	L.code.resize(n)
	L.link.resize(n)
	L.ngcode.resize(n)
	for i in n:
		var e: int = vedge[i]
		L.style[i] = _estyle[e]
		L.code[i] = _ecode[e]
		L.link[i] = _elink[e]
		var g: Vector2 = (ng[i] + ng[(i + 1) % n])
		var ax := absf(g.x)
		var ay := absf(g.y)
		if absf(ax - ay) < 1e-3:
			L.ngcode[i] = _side[e]
		elif ay > ax:
			L.ngcode[i] = 0 if g.y < 0.0 else 1
		else:
			L.ngcode[i] = 2 if g.x < 0.0 else 3
	return L


func _index_segments() -> void:
	var total := 0
	for l in loops:
		total += l.pos.size()
	seg_xy.resize(total * 4)
	seg_loop.resize(total)
	seg_vert.resize(total)
	var cells := width * height
	var counts := PackedInt32Array()
	counts.resize(cells + 1)
	var g := 0
	for li in loops.size():
		var l: Loop = loops[li]
		var n := l.pos.size()
		for i in n:
			var a := l.pos[i]
			var b := l.pos[(i + 1) % n]
			seg_xy[g * 4] = a.x
			seg_xy[g * 4 + 1] = a.y
			seg_xy[g * 4 + 2] = b.x
			seg_xy[g * 4 + 3] = b.y
			seg_loop[g] = li
			seg_vert[g] = i
			g += 1
	for pass_i in 2:
		var cursor := PackedInt32Array()
		if pass_i == 1:
			cell_start = PackedInt32Array()
			cell_start.resize(cells + 1)
			var acc := 0
			for k in cells:
				cell_start[k] = acc
				acc += counts[k]
			cell_start[cells] = acc
			cell_seg.resize(acc)
			cursor = cell_start.duplicate()
		for sg in total:
			var x0: float = minf(seg_xy[sg * 4], seg_xy[sg * 4 + 2])
			var x1: float = maxf(seg_xy[sg * 4], seg_xy[sg * 4 + 2])
			var y0: float = minf(seg_xy[sg * 4 + 1], seg_xy[sg * 4 + 3])
			var y1: float = maxf(seg_xy[sg * 4 + 1], seg_xy[sg * 4 + 3])
			var cx0: int = maxi(0, floori(x0))
			var cx1: int = mini(width - 1, floori(x1))
			var cy0: int = maxi(0, floori(y0))
			var cy1: int = mini(height - 1, floori(y1))
			for cy in range(cy0, cy1 + 1):
				for cx in range(cx0, cx1 + 1):
					var k := cy * width + cx
					if pass_i == 0:
						counts[k] += 1
					else:
						cell_seg[cursor[k]] = sg
						cursor[k] += 1
