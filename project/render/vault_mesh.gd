class_name VaultMesh
extends RefCounted
## The ink cave's rock vault as real geometry (docs/STYLE.md, 0.21.5): a height field over the open cave plus a band of rock beyond the wall outline,
## sampled every STEP cells and drawn by sonar_vault.gdshader. Heights are in wall heights (1 = the wall tops) and come from the zone data
## (FloorFx.ceil_height: echo hall 1.4, squeeze 1.0, drip gallery 1.2, pockets 1.05, others 1.12 +/- 0.05), blended bilinearly between neighbouring
## cells, plus bounded noise (deterministic by World.map_seed). Next to a wall the vault is pinned to exactly 1.0 and rises with a smoothstep over
## BLEND cells, so it meets the wall tops without a gap (the mesh vertices inside the rock are all 1.0, so a triangle that straddles the outline is
## flat there). The signed wall distance is measured against the GRID (the contour is displaced up to 0.25 into the rock, so the visible outline
## always sits where the field is already 1.0).
## Vertex data: VERTEX = (x, H * Z_SCALE, y); COLOR = (indoor weight, wall distance / 3, (H - 1) / 0.5, kind: 0 vault, 0.5 stalactite, 1 drip bead).
## Stalactites (build_stalactites, a second mesh): UV = (angle 0..1, 0 at the ceiling .. 1 at the tip), UV2 = base centre (light sample point),
## NORMAL = outward horizontal direction.

const STEP := 0.5
## cells over which the vault rises from the wall tops to its interior height
const BLEND := 1.3
## cells of rock beyond the grid wall that the vault still covers (it fills the lip jag gaps)
const BAND := 0.6
## signed distance range kept (positive in the open, negative in rock)
const RANGE := 1.6
const NOISE_AMP := 0.05
const SIDES := 6

var world: World
var nx: int = 0            ## vertices along x
var ny: int = 0
var h: PackedFloat32Array = PackedFloat32Array()    ## vault height per vertex, wall heights
var sd: PackedFloat32Array = PackedFloat32Array()   ## signed wall distance per vertex (cells; > 0 open)
var ind: PackedFloat32Array = PackedFloat32Array()  ## 1 indoors, 0 on the outdoor apron (blend over 2 cells)


static func enabled_for(w: World) -> bool:
	return w != null and FloorFx.ceil_style(w) == "cave"


static func build(w: World) -> VaultMesh:
	var v := VaultMesh.new()
	v.world = w
	v._run()
	return v


func _cell_solid(cx: int, cy: int) -> bool:
	if cx < 0 or cy < 0 or cx >= world.width or cy >= world.height:
		return true
	return world.solid_grid[cy * world.width + cx] == 1


## Distance from (x, y) to the nearest closed cell square with the given solid flag within r (r when none).
func _dist_to(x: float, y: float, want_solid: bool, r: float) -> float:
	var best := r
	var x0: int = floori(x - r)
	var x1: int = floori(x + r)
	var y0: int = floori(y - r)
	var y1: int = floori(y + r)
	for cy in range(y0, y1 + 1):
		var dy: float = maxf(maxf(cy - y, y - cy - 1.0), 0.0)
		if dy >= best:
			continue
		for cx in range(x0, x1 + 1):
			if _cell_solid(cx, cy) != want_solid:
				continue
			var dx: float = maxf(maxf(cx - x, x - cx - 1.0), 0.0)
			var d: float = sqrt(dx * dx + dy * dy)
			if d < best:
				best = d
	return best


static func _hash(ix: int, iy: int, sd_: int) -> float:
	var hh: int = (ix * 374761393 + iy * 668265263 + sd_ * 1274126177) & 0xFFFFFFFF
	hh = ((hh ^ (hh >> 13)) * 1274126177) & 0xFFFFFFFF
	return float(hh ^ (hh >> 16)) / 4294967296.0


func _run() -> void:
	var W: int = world.width
	var H: int = world.height
	nx = int(round(W / STEP)) + 1
	ny = int(round(H / STEP)) + 1
	# per cell: Chebyshev distance to the nearest solid cell (cells), the outdoor distance, the base height
	var cd := PackedInt32Array()
	cd.resize(W * H)
	var od := PackedInt32Array()
	od.resize(W * H)
	var hc := PackedFloat32Array()
	hc.resize(W * H)
	var far := 1000
	for cy in H:
		for cx in W:
			var k: int = cy * W + cx
			var solid := _cell_solid(cx, cy)
			cd[k] = 0 if solid else far
			od[k] = 0 if world.kind_at(cx + 0.5, cy + 0.5) == "outdoor" else far
			hc[k] = 0.0 if solid or od[k] == 0 else FloorFx.ceil_height(world, cx + 0.5, cy + 0.5)
	# rock and apron cells take the mean of their open neighbours, so the pinning to the wall tops comes from the distance ramp alone
	var hfill := hc.duplicate()
	for cy in H:
		for cx in W:
			if hc[cy * W + cx] > 0.0:
				continue
			var sum := 0.0
			var cnt := 0
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var ax: int = cx + dx
					var ay: int = cy + dy
					if ax >= 0 and ay >= 0 and ax < W and ay < H and hc[ay * W + ax] > 0.0:
						sum += hc[ay * W + ax]
						cnt += 1
			hfill[cy * W + cx] = sum / cnt if cnt > 0 else 1.12
	hc = hfill
	for cy in H:
		for cx in W:
			if cx == 0 or cy == 0 or cx == W - 1 or cy == H - 1:
				cd[cy * W + cx] = mini(cd[cy * W + cx], 1)
	var fwd_n := [[-1, -1], [0, -1], [1, -1], [-1, 0]]
	var bwd_n := [[1, 1], [0, 1], [-1, 1], [1, 0]]
	for arr in [cd, od]:
		for cy in H:
			for cx in W:
				var k: int = cy * W + cx
				var best: int = arr[k]
				for o in fwd_n:
					var ax: int = cx + o[0]
					var ay: int = cy + o[1]
					if ax >= 0 and ay >= 0 and ax < W and ay < H:
						best = mini(best, arr[ay * W + ax] + 1)
				arr[k] = best
		for cy in range(H - 1, -1, -1):
			for cx in range(W - 1, -1, -1):
				var k: int = cy * W + cx
				var best: int = arr[k]
				for o in bwd_n:
					var ax: int = cx + o[0]
					var ay: int = cy + o[1]
					if ax >= 0 and ay >= 0 and ax < W and ay < H:
						best = mini(best, arr[ay * W + ax] + 1)
				arr[k] = best
	# a cell that touches the map edge is within 1 of the (solid) outside
	var map_seed: int = world.map_seed
	var nsd: int = ContourField.style_seed(map_seed, 21)
	h.resize(nx * ny)
	sd.resize(nx * ny)
	ind.resize(nx * ny)
	for j in ny:
		var y: float = j * STEP
		for i in nx:
			var x: float = i * STEP
			var vi: int = j * nx + i
			# signed wall distance: exact only near walls, capped elsewhere
			var cmin := far
			for oy in [-1, 0]:
				for ox in [-1, 0]:
					var ccx: int = clampi(floori(x) + ox, 0, W - 1)
					var ccy: int = clampi(floori(y) + oy, 0, H - 1)
					cmin = mini(cmin, cd[ccy * W + ccx])
			var s_d: float
			if cmin > 3:
				s_d = RANGE
			else:
				var ds: float = _dist_to(x, y, true, RANGE)
				if ds > 0.0:
					s_d = ds
				else:
					var dop: float = _dist_to(x, y, false, BAND + 0.3)
					s_d = -dop if dop > 0.0 else 0.0
			sd[vi] = s_d
			# indoor weight from the surrounding cells' outdoor distance
			var wsum := 0.0
			for oy in [-1, 0]:
				for ox in [-1, 0]:
					var ccx: int = clampi(floori(x) + ox, 0, W - 1)
					var ccy: int = clampi(floori(y) + oy, 0, H - 1)
					wsum += clampf(float(od[ccy * W + ccx]) / 2.0, 0.0, 1.0)
			ind[vi] = wsum / 4.0
			# base height: bilinear between the cell-centre heights
			var fx: float = x - 0.5
			var fy: float = y - 0.5
			var bx: int = floori(fx)
			var by: int = floori(fy)
			var tx: float = fx - bx
			var ty: float = fy - by
			var h00: float = _hcell(hc, bx, by)
			var h10: float = _hcell(hc, bx + 1, by)
			var h01: float = _hcell(hc, bx, by + 1)
			var h11: float = _hcell(hc, bx + 1, by + 1)
			var h0: float = lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), ty)
			var rise: float = h0 - 1.0
			var nz: float = (ContourField.fbm(int(round(x * 4.0)), int(round(y * 4.0)), 0.45, 2, nsd) * 2.0 - 1.0) * NOISE_AMP * minf(1.0, maxf(rise, 0.0) * 8.0)
			var t: float = clampf(s_d / BLEND, 0.0, 1.0)
			var ramp: float = t * t * (3.0 - 2.0 * t)
			h[vi] = 1.0 + maxf(0.0, rise + nz) * ramp


func _hcell(hc: PackedFloat32Array, cx: int, cy: int) -> float:
	return hc[clampi(cy, 0, world.height - 1) * world.width + clampi(cx, 0, world.width - 1)]


## Vault height (wall heights) at world (x, y): bilinear on the vertex field, 1.0 outside it.
func height_at(x: float, y: float) -> float:
	var fx: float = clampf(x / STEP, 0.0, nx - 1.001)
	var fy: float = clampf(y / STEP, 0.0, ny - 1.001)
	var i: int = int(fx)
	var j: int = int(fy)
	var tx: float = fx - i
	var ty: float = fy - j
	return lerpf(lerpf(h[j * nx + i], h[j * nx + i + 1], tx), lerpf(h[(j + 1) * nx + i], h[(j + 1) * nx + i + 1], tx), ty)


## Signed wall distance (cells, > 0 open) at (x, y), bilinear.
func dist_at(x: float, y: float) -> float:
	var fx: float = clampf(x / STEP, 0.0, nx - 1.001)
	var fy: float = clampf(y / STEP, 0.0, ny - 1.001)
	var i: int = int(fx)
	var j: int = int(fy)
	var tx: float = fx - i
	var ty: float = fy - j
	return lerpf(lerpf(sd[j * nx + i], sd[j * nx + i + 1], tx), lerpf(sd[(j + 1) * nx + i], sd[(j + 1) * nx + i + 1], tx), ty)


## The vault surface: one triangle pair per STEP square that touches the open indoor cave or its rock band.
func build_surface() -> ArrayMesh:
	var zs: float = Coords.Z_SCALE
	var remap := PackedInt32Array()
	remap.resize(nx * ny)
	remap.fill(-1)
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	for j in ny - 1:
		for i in nx - 1:
			var c := [j * nx + i, j * nx + i + 1, (j + 1) * nx + i + 1, (j + 1) * nx + i]
			var any := false
			for vi in c:
				if sd[vi] >= -BAND and ind[vi] > 0.01:
					any = true
					break
			if not any:
				continue
			var q := PackedInt32Array()
			for vi in c:
				if remap[vi] < 0:
					remap[vi] = verts.size()
					var xx: float = (vi % nx) * STEP
					var yy: float = (vi / nx) * STEP
					verts.append(Vector3(xx, h[vi] * zs, yy))
					cols.append(Color(ind[vi], clampf(sd[vi] / 3.0, 0.0, 1.0), clampf((h[vi] - 1.0) / 0.5, 0.0, 1.0), 0.0))
				q.append(remap[vi])
			idx.append_array(PackedInt32Array([q[0], q[1], q[2], q[0], q[2], q[3]]))
	var mesh := ArrayMesh.new()
	if verts.size() > 0:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_COLOR] = cols
		arrays[Mesh.ARRAY_INDEX] = idx
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Per-zone stalactite parameters: [chance per open cell, min wall distance, length lo, length hi, base radius scale, bead chance].
static func stalactite_params(zone: String) -> Array:
	if zone == "echo_hall":
		return [0.30, 0.9, 0.28, 0.55, 1.0, 0.15]
	if zone == "squeeze":
		return [0.30, 0.3, 0.05, 0.12, 0.5, 0.0]
	if zone == "drip_gallery":
		return [0.30, 0.6, 0.15, 0.35, 0.8, 0.7]
	if zone.begins_with("pocket"):
		return [0.12, 0.5, 0.08, 0.2, 0.7, 0.3]
	return [0.12, 0.8, 0.12, 0.30, 0.8, 0.2]


## Stalactite sites (deterministic by map seed): Array of [x, y, length (wall heights), radius (cells), bead 0/1].
func stalactite_sites() -> Array:
	var out: Array = []
	var seed_h: int = ContourField.style_seed(world.map_seed, 22)
	for cy in world.height:
		for cx in world.width:
			if _cell_solid(cx, cy) or world.kind_at(cx + 0.5, cy + 0.5) == "outdoor":
				continue
			var zone: String = world.zone_at(cx + 0.5, cy + 0.5)
			var pr: Array = stalactite_params(zone)
			var x: float = cx + 0.2 + 0.6 * _hash(cx, cy, seed_h + 1)
			var y: float = cy + 0.2 + 0.6 * _hash(cx, cy, seed_h + 2)
			var dd: float = dist_at(x, y)
			if dd < pr[1]:
				continue
			# hang at the chamber centres: the chance grows with the wall distance
			var chance: float = pr[0] * (smoothstep(pr[1], pr[1] + 0.8, dd) * 0.7 + 0.3)
			if _hash(cx, cy, seed_h + 3) >= chance:
				continue
			var ln: float = lerpf(pr[2], pr[3], _hash(cx, cy, seed_h + 4))
			var r: float = (0.07 + 0.3 * ln) * pr[4]
			var bead: int = 1 if _hash(cx, cy, seed_h + 5) < pr[5] else 0
			out.append([x, y, ln, r, bead])
			# a cluster: up to two small neighbours
			var ns: int = int(_hash(cx, cy, seed_h + 6) * 3.0)
			for k in ns:
				var ang: float = TAU * _hash(cx, cy, seed_h + 10 + k)
				var off: float = 0.22 + 0.2 * _hash(cx, cy, seed_h + 20 + k)
				var sx: float = x + cos(ang) * off
				var sy: float = y + sin(ang) * off
				if dist_at(sx, sy) < pr[1] * 0.7:
					continue
				var sl: float = ln * (0.35 + 0.3 * _hash(cx, cy, seed_h + 30 + k))
				out.append([sx, sy, sl, r * 0.55, 0])
	return out


## Hanging stalactites as small cones: SIDES-sided, base ring at the vault, a narrower ring at 55%, a point; a bead below the tip where flagged.
func build_stalactites() -> ArrayMesh:
	var zs: float = Coords.Z_SCALE
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var cols := PackedColorArray()
	var norms := PackedVector3Array()
	var idx := PackedInt32Array()
	for st in stalactite_sites():
		var x: float = st[0]
		var y: float = st[1]
		var ln: float = st[2]
		var r: float = st[3]
		var top: float = height_at(x, y)
		var b0 := verts.size()
		var rings := [[0.0, 1.0], [0.55, 0.62]]
		for rg in rings:
			for k in SIDES + 1:
				var u: float = float(k) / SIDES
				var th: float = u * TAU
				var rr: float = r * rg[1] * (0.85 + 0.3 * _hash(k % SIDES + int(x * 7.0), int(y * 7.0) + int(rg[0] * 10.0), 91))
				verts.append(Vector3(x + cos(th) * rr, (top - ln * rg[0]) * zs, y + sin(th) * rr))
				uvs.append(Vector2(u, rg[0]))
				uv2s.append(Vector2(x, y))
				cols.append(Color(1.0, 0.5, ln, 0.5))
				norms.append(Vector3(cos(th), 0.0, sin(th)))
		var tip := verts.size()
		verts.append(Vector3(x, (top - ln) * zs, y))
		uvs.append(Vector2(0.5, 1.0))
		uv2s.append(Vector2(x, y))
		cols.append(Color(1.0, 0.5, ln, 0.5))
		norms.append(Vector3(0.0, -1.0, 0.0))
		var R: int = SIDES + 1
		for k in SIDES:
			var a0: int = b0 + k
			var a1: int = b0 + k + 1
			var m0: int = b0 + R + k
			var m1: int = b0 + R + k + 1
			idx.append_array(PackedInt32Array([a0, a1, m1, a0, m1, m0]))
			idx.append_array(PackedInt32Array([m0, m1, tip]))
		if st[4] == 1:
			var cyb: float = (top - ln - 0.045) * zs
			var rb: float = 0.017
			var hb: float = 0.026 * zs
			var c0 := verts.size()
			var pts := [Vector3(x, cyb + hb, y), Vector3(x, cyb - hb, y), Vector3(x + rb, cyb, y), Vector3(x, cyb, y + rb), Vector3(x - rb, cyb, y), Vector3(x, cyb, y - rb)]
			for pt in pts:
				verts.append(pt)
				uvs.append(Vector2(0.0, 0.0))
				uv2s.append(Vector2(x, y))
				cols.append(Color(1.0, 0.5, ln, 1.0))
				norms.append(Vector3(0.0, 1.0, 0.0))
			for k in 4:
				idx.append_array(PackedInt32Array([c0, c0 + 2 + k, c0 + 2 + (k + 1) % 4]))
				idx.append_array(PackedInt32Array([c0 + 1, c0 + 2 + (k + 1) % 4, c0 + 2 + k]))
	var mesh := ArrayMesh.new()
	if verts.size() > 0:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_TEX_UV2] = uv2s
		arrays[Mesh.ARRAY_COLOR] = cols
		arrays[Mesh.ARRAY_NORMAL] = norms
		arrays[Mesh.ARRAY_INDEX] = idx
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
