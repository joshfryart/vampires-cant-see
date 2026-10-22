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
static func depth_columns(world, x: float, y: float, angle: float, col_cos: PackedFloat64Array, col_sin: PackedFloat64Array, max_dist: float, out: PackedFloat32Array) -> void:
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
				break
		out[i] = res
