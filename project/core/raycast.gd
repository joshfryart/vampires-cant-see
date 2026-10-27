class_name Raycast
extends RefCounted
## Ports js/raycast.js (DDA). Plain 64-bit floats; world only needs is_solid(x, y).

class Hit:
	extends RefCounted
	var hit: bool = false
	var dist: float = 0.0
	var ray_dist: float = 0.0
	var ray_angle: float = 0.0
	var cell_x: int = 0
	var cell_y: int = 0
	var side: int = 0
	var hit_x: float = 0.0
	var hit_y: float = 0.0
	var wall_x: float = 0.0
	var nx: float = 0.0
	var ny: float = 0.0
	var mat: String = "stone"


## Ports trace (js/raycast.js:8). `world` is any object with cell_solid(cx, cy), width and height (World or GridWorld).
static func trace(world, x: float, y: float, ray_angle: float, max_dist: float) -> Hit:
	var out := Hit.new()
	var dx: float = cos(ray_angle)
	var dy: float = sin(ray_angle)
	var cx: int = int(floor(x))
	var cy: int = int(floor(y))
	out.ray_angle = ray_angle
	if world.cell_solid(cx, cy):
		out.hit = true
		out.cell_x = cx
		out.cell_y = cy
		out.hit_x = x
		out.hit_y = y
		out.nx = -dx
		out.ny = -dy
		return out
	var ddx: float = INF if dx == 0.0 else absf(1.0 / dx)
	var ddy: float = INF if dy == 0.0 else absf(1.0 / dy)
	var step_x: int = -1 if dx < 0.0 else 1
	var step_y: int = -1 if dy < 0.0 else 1
	var sdx: float = INF if dx == 0.0 else ((x - cx) if dx < 0.0 else (cx + 1 - x)) * ddx
	var sdy: float = INF if dy == 0.0 else ((y - cy) if dy < 0.0 else (cy + 1 - y)) * ddy
	var cap: int = 4 * ((world.width if world.width > 0 else 64) + (world.height if world.height > 0 else 64))
	var side: int = 0
	for i in cap:
		var d: float
		if sdx < sdy:
			d = sdx
			sdx += ddx
			cx += step_x
			side = 0
		else:
			d = sdy
			sdy += ddy
			cy += step_y
			side = 1
		if d > max_dist:
			break
		if world.cell_solid(cx, cy):
			var hx: float = x + dx * d
			var hy: float = y + dy * d
			out.hit = true
			out.dist = d
			out.ray_dist = d
			out.cell_x = cx
			out.cell_y = cy
			out.side = side
			out.hit_x = hx
			out.hit_y = hy
			out.wall_x = (hy - floor(hy)) if side == 0 else (hx - floor(hx))
			if side == 0:
				out.nx = -1.0 if dx > 0.0 else 1.0
				out.ny = 0.0
			else:
				out.nx = 0.0
				out.ny = -1.0 if dy > 0.0 else 1.0
			return out
	out.hit = false
	out.nx = 0.0
	out.ny = 0.0
	out.dist = max_dist
	out.ray_dist = max_dist
	out.hit_x = x + dx * max_dist
	out.hit_y = y + dy * max_dist
	return out


## Ports hitOne (js/raycast.js:58): trace plus the hit surface material (world.material_at).
static func hit_one(world, x: float, y: float, ray_angle: float, max_dist: float) -> Hit:
	var h: Hit = trace(world, x, y, ray_angle, max_dist)
	h.mat = "stone"
	if h.hit and world.has_method("material_at"):
		var m: String = world.material_at(float(h.cell_x), float(h.cell_y))
		h.mat = m if m != "" else "stone"
	return h


## Ports castOne (js/raycast.js:66).
static func cast_one(world, x: float, y: float, ray_angle: float, max_dist: float) -> Hit:
	return trace(world, x, y, ray_angle, max_dist)


## Ports cast (js/raycast.js:76): one ray per screen column.
static func cast(world, x: float, y: float, angle: float, fov: float, columns: int, max_dist: float) -> Array[Hit]:
	var res: Array[Hit] = []
	var tan_half: float = tan(fov / 2.0)
	for i in columns:
		var off: float = atan((2.0 * (i + 0.5) / columns - 1.0) * tan_half)
		var h: Hit = trace(world, x, y, angle + off, max_dist)
		if h.hit:
			h.dist = h.ray_dist * cos(off)
		res.append(h)
	return res


## Per-column offsets for a fixed fov: [cos(off), sin(off)] arrays, off = atan((2 (i + 0.5) / columns - 1) tan(fov / 2)).
static func column_offsets(fov: float, columns: int) -> Array:
	var cs := PackedFloat64Array()
	var sn := PackedFloat64Array()
	cs.resize(columns)
	sn.resize(columns)
	var tan_half: float = tan(fov / 2.0)
	for i in columns:
		var off: float = atan((2.0 * (i + 0.5) / columns - 1.0) * tan_half)
		cs[i] = cos(off)
		sn[i] = sin(off)
	return [cs, sn]


## Allocation-free depth buffer: out[i] = distance along the view axis to the wall in column i (max_dist when no hit),
## the same value cast() stores in Hit.dist, within float rounding. Used for occlusion (js r.zbuf), not for parity data.
## tch (optional): out_tch[i] = char code of the tile the column hit (0 when nothing was hit), like js r.tch.
static func depth_columns(world, x: float, y: float, angle: float, col_cos: PackedFloat64Array, col_sin: PackedFloat64Array, max_dist: float, out: PackedFloat32Array, out_tch: PackedByteArray = PackedByteArray()) -> void:
	if not ("solid_grid" in world):
		_depth_columns_slow(world, x, y, angle, col_cos, col_sin, max_dist, out, out_tch)
		return
	var want_tch: bool = out_tch.size() >= col_cos.size() and "tile_grid" in world
	var grid: PackedByteArray = world.solid_grid
	var tiles: PackedInt32Array = world.tile_grid if want_tch else PackedInt32Array()
	var w: int = world.width
	var h: int = world.height
	var ca: float = cos(angle)
	var sa: float = sin(angle)
	var cx0: int = int(floor(x))
	var cy0: int = int(floor(y))
	var cap: int = 4 * (w + h)
	var start_solid: bool = cx0 < 0 or cy0 < 0 or cx0 >= w or cy0 >= h or grid[cy0 * w + cx0] == 1
	var n_cols: int = col_cos.size()
	for i in n_cols:
		if start_solid:
			out[i] = 0.0
			if want_tch:
				out_tch[i] = 0
			continue
		var c: float = col_cos[i]
		var s: float = col_sin[i]
		var dx: float = ca * c - sa * s
		var dy: float = sa * c + ca * s
		var ddx: float = INF if dx == 0.0 else absf(1.0 / dx)
		var ddy: float = INF if dy == 0.0 else absf(1.0 / dy)
		var step_x: int = -1 if dx < 0.0 else 1
		var step_y: int = -1 if dy < 0.0 else 1
		var sdx: float = INF if dx == 0.0 else ((x - cx0) if dx < 0.0 else (cx0 + 1 - x)) * ddx
		var sdy: float = INF if dy == 0.0 else ((y - cy0) if dy < 0.0 else (cy0 + 1 - y)) * ddy
		var cx: int = cx0
		var cy: int = cy0
		var res: float = max_dist
		var hit_ch: int = 0
		for n in cap:
			var d: float
			if sdx < sdy:
				d = sdx
				sdx += ddx
				cx += step_x
			else:
				d = sdy
				sdy += ddy
				cy += step_y
			if d > max_dist:
				break
			if cx < 0 or cy < 0 or cx >= w or cy >= h:
				res = d * c
				if want_tch:
					hit_ch = 35
				break
			var k: int = cy * w + cx
			if grid[k] == 1:
				res = d * c
				if want_tch:
					hit_ch = tiles[k]
				break
		out[i] = res
		if want_tch:
			out_tch[i] = hit_ch


## Contour-correct depth buffer (docs/STYLE.md section 2, "Depth columns"): the same output as depth_columns, but a column stops at the DRAWN smooth outline
## (ContourField segments) instead of the grid face, so sprites are clipped exactly at rounded corners. Same DDA; every visited cell (open corner cells included)
## tests its CSR segments, and the first hit inside the current cell wins. A column that threads a rounded corner keeps walking to the outline behind it (up to max_dist); leaving the map, or max_dist, falls back to the
## grid distance of the first solid cell. `field` is world.contour (ContourField.for_world). out_tch is the grid tile code of the first solid cell, as depth_columns writes it.
## Callers gate on a non-empty world.wall_style and the contour mesh being enabled; classic worlds keep depth_columns.
static func depth_columns_contour(world, field, x: float, y: float, angle: float, col_cos: PackedFloat64Array, col_sin: PackedFloat64Array, max_dist: float, out: PackedFloat32Array, out_tch: PackedByteArray = PackedByteArray()) -> void:
	var want_tch: bool = out_tch.size() >= col_cos.size() and "tile_grid" in world
	var grid: PackedByteArray = world.solid_grid
	var tiles: PackedInt32Array = world.tile_grid if want_tch else PackedInt32Array()
	var cstart: PackedInt32Array = field.cell_start
	var cxy: PackedFloat32Array = _cell_segments(field)
	var w: int = world.width
	var h: int = world.height
	var ca: float = cos(angle)
	var sa: float = sin(angle)
	var cx0: int = int(floor(x))
	var cy0: int = int(floor(y))
	var cap: int = 4 * (w + h)
	var start_solid: bool = cx0 < 0 or cy0 < 0 or cx0 >= w or cy0 >= h or grid[cy0 * w + cx0] == 1
	var n_cols: int = col_cos.size()
	for i in n_cols:
		if start_solid:
			out[i] = 0.0
			if want_tch:
				out_tch[i] = 0
			continue
		var c: float = col_cos[i]
		var s: float = col_sin[i]
		var dx: float = ca * c - sa * s
		var dy: float = sa * c + ca * s
		var ddx: float = INF if dx == 0.0 else absf(1.0 / dx)
		var ddy: float = INF if dy == 0.0 else absf(1.0 / dy)
		var step_x: int = -1 if dx < 0.0 else 1
		var step_y: int = -1 if dy < 0.0 else 1
		var sdx: float = INF if dx == 0.0 else ((x - cx0) if dx < 0.0 else (cx0 + 1 - x)) * ddx
		var sdy: float = INF if dy == 0.0 else ((y - cy0) if dy < 0.0 else (cy0 + 1 - y)) * ddy
		var cx: int = cx0
		var cy: int = cy0
		var res: float = max_dist
		var hit_ch: int = 0
		var grid_d: float = -1.0
		var entry: float = 0.0
		for n in cap:
			var dexit: float = sdx if sdx < sdy else sdy
			# the segments of the current cell: the nearest crossing that lies inside the cell ends the column
			var k: int = cy * w + cx
			var s0: int = cstart[k]
			var s1: int = cstart[k + 1]
			if s1 > s0:
				var best: float = INF
				for q in range(s0 * 4, s1 * 4, 4):
					# Loops keep rock on one side, so only crossings from the open side count (the ray always starts in open space): den < 0.
					var ex: float = cxy[q + 2]
					var ey: float = cxy[q + 3]
					var den: float = dx * ey - dy * ex
					if den >= 0.0:
						continue
					var ax: float = cxy[q] - x
					var ay: float = cxy[q + 1] - y
					# 0 <= u = nu / den <= 1 without dividing; the t division only happens for crossings.
					var nu: float = ax * dy - ay * dx
					if nu > -1e-6 * den or nu < den * 1.000001:
						continue
					var t: float = (ax * ey - ay * ex) / den
					if t > 0.0 and t < best:
						best = t
				if best <= dexit + 1e-6 and best <= max_dist:
					res = best * c
					break
			# advance to the next cell
			entry = dexit
			if sdx < sdy:
				sdx += ddx
				cx += step_x
			else:
				sdy += ddy
				cy += step_y
			if entry > max_dist:
				if grid_d >= 0.0:
					res = grid_d * c
				break
			if cx < 0 or cy < 0 or cx >= w or cy >= h:
				if grid_d < 0.0:
					grid_d = entry
					if want_tch:
						hit_ch = 35
				res = grid_d * c
				break
			if grid_d < 0.0 and grid[cy * w + cx] == 1:
				grid_d = entry
				if want_tch:
					hit_ch = tiles[cy * w + cx]
		out[i] = res
		if want_tch:
			if res < max_dist and hit_ch == 0:
				hit_ch = _first_solid_tch(world, grid, tiles, x, y, dx, dy, cx0, cy0, cap)
			out_tch[i] = hit_ch


## Per-cell segment records (ax, ay, ex, ey) in CSR order (the same ranges as field.cell_start), built once and cached on the field.
static func _cell_segments(field) -> PackedFloat32Array:
	if field.has_meta("cell_xy"):
		return field.get_meta("cell_xy")
	var n: int = field.cell_seg.size()
	var out := PackedFloat32Array()
	out.resize(n * 4)
	for q in n:
		var g: int = field.cell_seg[q] * 4
		var ax: float = field.seg_xy[g]
		var ay: float = field.seg_xy[g + 1]
		out[q * 4] = ax
		out[q * 4 + 1] = ay
		out[q * 4 + 2] = field.seg_xy[g + 2] - ax
		out[q * 4 + 3] = field.seg_xy[g + 3] - ay
	field.set_meta("cell_xy", out)
	return out


## Tile code of the first grid-solid cell along a ray (0 when none): the rs.tch value for columns whose contour hit was found in an open fillet cell.
static func _first_solid_tch(world, grid: PackedByteArray, tiles: PackedInt32Array, x: float, y: float, dx: float, dy: float, cx0: int, cy0: int, cap: int) -> int:
	var w: int = world.width
	var h: int = world.height
	var ddx: float = INF if dx == 0.0 else absf(1.0 / dx)
	var ddy: float = INF if dy == 0.0 else absf(1.0 / dy)
	var sdx: float = INF if dx == 0.0 else ((x - cx0) if dx < 0.0 else (cx0 + 1 - x)) * ddx
	var sdy: float = INF if dy == 0.0 else ((y - cy0) if dy < 0.0 else (cy0 + 1 - y)) * ddy
	var cx: int = cx0
	var cy: int = cy0
	for n in cap:
		if sdx < sdy:
			sdx += ddx
			cx += 1 if dx > 0.0 else -1
		else:
			sdy += ddy
			cy += 1 if dy > 0.0 else -1
		if cx < 0 or cy < 0 or cx >= w or cy >= h:
			return 35
		if grid[cy * w + cx] == 1:
			return tiles[cy * w + cx]
	return 0


static func _depth_columns_slow(world, x: float, y: float, angle: float, col_cos: PackedFloat64Array, col_sin: PackedFloat64Array, max_dist: float, out: PackedFloat32Array, out_tch: PackedByteArray) -> void:
	var want_tch: bool = out_tch.size() >= col_cos.size()
	var ca: float = cos(angle)
	var sa: float = sin(angle)
	var cx0: int = int(floor(x))
	var cy0: int = int(floor(y))
	var cap: int = 4 * (world.width + world.height)
	for i in col_cos.size():
		var c: float = col_cos[i]
		var s: float = col_sin[i]
		var dx: float = ca * c - sa * s
		var dy: float = sa * c + ca * s
		if world.cell_solid(cx0, cy0):
			out[i] = 0.0
			if want_tch:
				out_tch[i] = 0
			continue
		var ddx: float = INF if dx == 0.0 else absf(1.0 / dx)
		var ddy: float = INF if dy == 0.0 else absf(1.0 / dy)
		var step_x: int = -1 if dx < 0.0 else 1
		var step_y: int = -1 if dy < 0.0 else 1
		var sdx: float = INF if dx == 0.0 else ((x - cx0) if dx < 0.0 else (cx0 + 1 - x)) * ddx
		var sdy: float = INF if dy == 0.0 else ((y - cy0) if dy < 0.0 else (cy0 + 1 - y)) * ddy
		var cx: int = cx0
		var cy: int = cy0
		var res: float = max_dist
		var hit_ch := 0
		for n in cap:
			var d: float
			if sdx < sdy:
				d = sdx
				sdx += ddx
				cx += step_x
			else:
				d = sdy
				sdy += ddy
				cy += step_y
			if d > max_dist:
				break
			if world.cell_solid(cx, cy):
				res = d * c
				if want_tch:
					var tc: String = world.tile_at(cx + 0.5, cy + 0.5)
					hit_ch = tc.unicode_at(0) if tc != "" else 0
				break
		out[i] = res
		if want_tch:
			out_tch[i] = hit_ch
