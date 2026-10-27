class_name FloorFx
extends RefCounted
## Ports the ground and air drawing of js/render.js onto a Canvas: drawRipple (wavy dotted pulse rings on floor and ceiling),
## drawAirRings (hollow circles leaving the mouth), drawFloorTexture (grass blades, brick joints, planks, cobbles under the
## wavefront, floor and ceiling), drawFloorFront (the thin front arc with stipple), drawFootRings and drawRings.

const TWO_PI := JsMath.TWO_PI
const FLASH_AGE := 0.12
const RING_SAMPLES := 270
const SEC_SAMPLES := 90
const FRONT_SEG := 40
const FRONT_DOTS := 40
const FOOT_SEG := 44
const TEX_MAX_CELLS := 520
const TEX_BUCKETS := 3
const AIR_OFFS := [0.0, 1.1, 2.2]
const AIR_ALPHA := [1.0, 0.65, 0.35]
const AIR_GROW := 11.0 * PI / 180.0
const AIR_MAX := 58.0 * PI / 180.0
const COL_RING_PERSON := "#ffb3a6"
const COL_RING_MARKER := "#dcd0ff"
const COL_RING_OTHER := "#e8f2ff"


## Seeded 0..1 value from two integers (js hash01).
static func hash01(a: int, b: int) -> float:
	var h: int = (JsMath.imul(a & JsMath.M32, 374761393) + JsMath.imul(b & JsMath.M32, 668265263)) & JsMath.M32
	h = JsMath.imul((h ^ (h >> 13)) & JsMath.M32, 1274126177)
	return float((h ^ (h >> 16)) & JsMath.M32) / 4294967296.0


static func round_js(x: float) -> int:
	return int(floor(x + 0.5))


## Visual beam gain (0.15..1) for an angle off the aim (js beamGain).
static func beam_gain(rel: float) -> float:
	if is_nan(rel):
		return 1.0
	return Acoustics.vis_factor(Acoustics.beam(rel))


## Reach of a ping (cells) at beam gain gb: 30% of range behind, full range on axis.
static func beam_reach(rng_: float, gb: float) -> float:
	return rng_ * (0.3 + 0.7 * gb)


## Facing of a ping, fixed the first time it is seen.
static func aim_of(pu: Sonar.Pulse, player: Dictionary) -> float:
	if pu.has_facing and is_finite(pu.facing):
		return pu.facing
	if is_nan(pu.aim_cache):
		pu.aim_cache = float(player["angle"])
	return pu.aim_cache


static func is_indoor(world: World, player: Dictionary) -> bool:
	if world == null:
		return true
	return world.kind_at(player["x"], player["y"]) != "outdoor"


## Air-ring / surface-vibration detail allowed (quality and the matDetail auto-off).
static func air_on(rs: RenderState) -> bool:
	return rs.quality >= 2 and rs.mat_detail


## Swell factor 0.3..1.8 of one dot: its own rhythm (1.2-5.4 Hz), drifting with distance.
static func air_swell(i: int, n: int, rr: float, ph: int, t: float) -> float:
	var key: int = int(floor(float(i) / n * 140.0)) * 7 + ph * 131
	var f: float = 1.2 + hash01(key, 11) * 4.2
	var p0: float = hash01(key, 12) * TWO_PI
	var g: float = 0.8 + hash01(key, 13) * 2.2
	return 0.3 + 1.5 * (0.5 + 0.5 * sin(t * f + rr * g + p0))


## Speckle scale for a surface roughness 0..1: {n: dot-count multiplier, back: how far behind the front the dots linger}.
static func speckle(rough: float) -> Dictionary:
	var k: float = 1.0 if rough > 1.0 else (rough if rough > 0.0 else 0.0)
	return {"n": 0.5 + 1.5 * k, "back": 0.25 + 0.5 * k}


## Mean roughness of the walls a pulse hit (every 8th ray) mixed 50/50 with the floor under its origin; cached on the pulse.
static func pulse_rough(world: World, pu: Sonar.Pulse) -> float:
	if not is_nan(pu.rough):
		return pu.rough
	var floor_r: float = 0.2
	if world != null:
		floor_r = Acoustics.rough_of(world.material_at(pu.x, pu.y))
	var total := 0.0
	var n := 0
	if pu.vmat.size() > 0 and pu.vnorm.size() > 0:
		var i := 0
		while i < pu.vis.size():
			if pu.vnorm[i] == Sonar.NO_HIT or not (pu.vis[i] > 0.0):
				i += 8
				continue
			total += Acoustics.rough_of(Sonar.MATS[pu.vmat[i]])
			n += 1
			i += 8
	pu.rough = 0.5 * floor_r + 0.5 * (total / n) if n > 0 else floor_r
	return pu.rough


static func _is_ring_kind(kind: String) -> bool:
	return kind == "step" or kind == "personStep" or kind == "vheart"


# ---------------------------------------------------------------- drawRipple

## Draw each pulse ring as a wavy dotted arc on the floor and a fainter one on the ceiling.
static func draw_ripple(rs: RenderState, c: Canvas, world: World, sonar: Sonar, t: float, player: Dictionary, tan_half: float) -> void:
	var pulses: Array = sonar.pulses
	if pulses.is_empty():
		return
	var half_w: float = rs.ow / 2.0
	var focal: float = half_w / tan_half
	var ca: float = cos(player["angle"])
	var sa: float = sin(player["angle"])
	var horizon: float = rs.horizon
	var half: float = rs.oh / 2.0
	var dot: float = 2.2 * rs.wscale
	var hd: float = dot / 2.0
	var boil: bool = rs.boil_on
	var indoor := is_indoor(world, player)
	for k in pulses.size():
		var pu: Sonar.Pulse = pulses[k]
		if _is_ring_kind(pu.kind):
			continue
		var rr: float = Sonar.ring_radius(pu, t)
		if rr < 0.2 or rr > pu.range:
			continue
		var bounce: bool = pu.gen > 0
		if pu.gen > 1 and rs.quality < 3:
			continue
		var alpha: float = 0.85 * (1.0 - rr / pu.range) * minf(1.0, pu.strength * 1.3)
		var dotk: float = 0.7 if bounce else 1.0
		if pu.weak > 0.0:
			var wk0: float = 1.0 if pu.weak > 1.0 else pu.weak
			alpha *= 0.7 if rs.reduced else 1.0 - 0.3 * wk0 * (0.5 + 0.5 * sin(t * 15.0 + k))
			dotk *= 1.0 - 0.35 * wk0
		if alpha <= 0.04:
			continue
		var samples: int = (RING_SAMPLES >> 1) if bounce else RING_SAMPLES
		var wk: float = 5.0 + (k % 3)
		var wphase: float = t * 1.4 + k
		var ceil_ok: bool = not (pu.z < 0.3)
		c.fill_style = "#7fa6ff" if bounce else "#e8f2ff"
		var beamed: bool = pu.kind == "ping" and not bounce
		var aim: float = aim_of(pu, player) if beamed else 0.0
		var passes: int = 2 if rs.quality >= 2 and not bounce and ceil_ok and indoor else 1
		for pass_i in passes:
			c.global_alpha = alpha if pass_i == 0 else alpha * 0.4
			c.begin_path()
			var any := false
			for s in samples:
				var th: float = (float(s) / samples) * TWO_PI
				var dk: float = dotk
				if beamed:
					var gb: float = beam_gain(th - aim)
					if rr > beam_reach(pu.range, gb) or alpha * gb < 0.03:
						continue
					dk = dotk * (0.55 + 0.45 * gb)
				var rw: float = RippleFx.wavy_radius(rr, th, wphase, wk, 0.04)
				var wx: float = pu.x + cos(th) * rw
				var wy: float = pu.y + sin(th) * rw
				var dx: float = wx - player["x"]
				var dy: float = wy - player["y"]
				var fwd: float = dx * ca + dy * sa
				if fwd <= 0.15:
					continue
				var right: float = -dx * sa + dy * ca
				var sx: float = half_w + (right / fwd) * focal
				if sx < 0.0 or sx >= rs.ow:
					continue
				var col: int = mini(rs.cols - 1, int(floor(sx / rs.col_w)))
				if fwd > rs.zbuf[col] + 0.05:
					continue
				if not Sonar.visible_from(pu, wx, wy):
					continue
				var off: float = half / fwd
				var y: float = (horizon + off if pass_i == 0 else horizon - off) + (rs.j(s + k * 17, 1) * 0.5 * rs.wscale if boil else 0.0)
				if y < 0.0 or y >= rs.oh:
					continue
				var xj: float = rs.j(s + k * 17, 0) * 0.5 * rs.wscale if boil else 0.0
				c.rect(sx + xj - hd * dk, y - hd * dk, dot * dk, dot * dk)
				any = true
			if any:
				c.fill()
	c.global_alpha = 1.0


# ---------------------------------------------------------------- drawAirRings

static var _trig: Dictionary = {}


## cos then sin of the n sample angles phi = i / n * 2 pi + ri * pi / 4 of an air ring (cached: n and ri repeat every frame).
static func _ring_trig(n: int, ri: int) -> PackedFloat64Array:
	var key: int = n * 4 + ri
	var a: Variant = _trig.get(key)
	if a != null:
		return a
	var out := PackedFloat64Array()
	out.resize(n * 2)
	for i in n:
		var phi: float = float(i) / n * TWO_PI + ri * 0.25 * PI
		out[i] = cos(phi)
		out[n + i] = sin(phi)
	_trig[key] = out
	return out


## Air rings: a ping shows as 3 hollow circles leaving the mouth and opening outward.
static func draw_air_rings(rs: RenderState, c: Canvas, world: World, sonar: Sonar, t: float, player: Dictionary, tan_half: float) -> void:
	var pulses: Array = sonar.pulses
	if pulses.is_empty() or not air_on(rs):
		return
	var half_w: float = rs.ow / 2.0
	var focal: float = half_w / tan_half
	var half: float = rs.oh / 2.0
	var mouth_y: float = rs.horizon + half * 0.5
	var ca: float = cos(player["angle"])
	var sa: float = sin(player["angle"])
	var sc: float = rs.ow / 800.0
	var indoor := is_indoor(world, player)
	c.line_width = maxf(1.0, 1.2 * sc)
	c.stroke_style = "#9fe6ff"
	for k in pulses.size():
		var pu: Sonar.Pulse = pulses[k]
		if pu.kind != "ping" or pu.gen > 0:
			continue
		var rr: float = Sonar.ring_radius(pu, t)
		if rr < 0.3 or rr > pu.range:
			continue
		var fade: float = (1.0 - rr / pu.range) * minf(1.0, pu.strength * 1.2)
		var rel0: float = float(player["angle"]) - aim_of(pu, player)
		for ri in 3:
			var rrr: float = rr - AIR_OFFS[ri]
			var al: float = rrr * AIR_GROW
			if rrr < 0.3 or al < 0.02 or al > AIR_MAX:
				continue
			var a0: float = AIR_ALPHA[ri] * fade
			if a0 < 0.03:
				continue
			var ta: float = tan(al)
			var sal: float = sin(al)
			var z_d: float = rrr * cos(al)
			var n: int = mini(160, maxi(48, round_js(al * focal * TWO_PI / (9.0 * sc))))
			c.global_alpha = minf(1.0, a0)
			c.begin_path()
			var any := false
			for i in n:
				var phi: float = float(i) / n * TWO_PI + ri * 0.25 * PI
				var cp: float = cos(phi)
				var sp: float = sin(phi)
				var x: float = rrr * sal * cp
				var v: float = -0.3 + rrr * sal * sp / 0.5
				if v < -1.0 or (indoor and v > 1.0):
					continue
				var gb: float = beam_gain(rel0 + atan2(x, z_d))
				if rrr > beam_reach(pu.range, gb) or a0 * gb < 0.03:
					continue
				var sx: float = half_w + ta * cp * focal
				var sy: float = mouth_y - ta * sp * focal
				if sx < 0.0 or sx >= rs.ow or sy < 0.0 or sy >= rs.oh:
					continue
				var col: int = mini(rs.cols - 1, int(floor(sx / rs.col_w)))
				if z_d > rs.zbuf[col] + 0.05:
					continue
				var wx: float = player["x"] + z_d * ca - x * sa
				var wy: float = player["y"] + z_d * sa + x * ca
				if not Sonar.visible_from(pu, wx, wy):
					continue
				var sz: float = 3.2 * sc * (0.55 + 0.45 * gb) * minf(1.4, 0.7 + al * 2.2)
				if not rs.reduced:
					sz *= air_swell(i, n, rrr, ri + k, t)
				if sz < 0.6:
					continue
				c.move_to(sx + sz, sy)
				c.arc(sx, sy, sz, 0.0, TWO_PI)
				any = true
			if any:
				c.stroke()
	c.global_alpha = 1.0


# ---------------------------------------------------------------- floor and ceiling texture

## Floor texture kind for a material name, or "" when it is not a floor.
static func floor_tex_kind(mat: String) -> String:
	if mat == "grass":
		return "grass"
	if mat == "stone":
		return "brick"
	if mat == "wood":
		return "plank"
	if mat == "cobble" or mat == "roughStone":
		return "cobble"
	return ""


## Ceiling marks for the zone at (x, y): its ceiling material from the acoustics data, else brick.
static func ceil_tex_kind(world: World, x: float, y: float) -> String:
	var zone := world.zone_at(x, y)
	var k := floor_tex_kind(Acoustics.ceiling_for(zone if zone != "" else world.name)["mat"])
	return k if k != "" else "brick"


## Perspective projection of floor (or ceiling) points used by the texture cells.
class FloorProj:
	extends RefCounted
	var px: float = 0.0
	var py: float = 0.0
	var f: float = 0.0
	var f2: float = 0.0
	var player_x: float
	var player_y: float
	var ca: float
	var sa: float
	var half_w: float
	var focal: float
	var horizon: float
	var half: float
	var up: bool
	var ow: float
	var oh: float

	func pt(wx: float, wy: float) -> bool:
		var dx: float = wx - player_x
		var dy: float = wy - player_y
		var fwd: float = dx * ca + dy * sa
		if fwd < 0.3:
			return false
		px = half_w + ((-dx * sa + dy * ca) / fwd) * focal
		py = horizon - half / fwd if up else horizon + half / fwd
		f = fwd
		f2 = focal / fwd
		return px > -40.0 and px < ow + 40.0 and (py > -oh * 2.0 if up else py < oh * 3.0)

	func seg(c: Canvas, cx: float, cy: float, u0: float, v0: float, u1: float, v1: float) -> void:
		if not pt(cx + u0, cy + v0):
			return
		var x0: float = px
		var y0: float = py
		if not pt(cx + u1, cy + v1):
			return
		c.move_to(x0, y0)
		c.line_to(px, py)


## Add one floor cell's marks (blades / brick joints / planks / pebbles) to the current path.
static func add_floor_cell(c: Canvas, p: FloorProj, kind: String, cx: int, cy: int, hs: float) -> void:
	if kind == "grass":
		for i in 9:
			var u: float = cx + hash01(cx * 31 + i, cy * 17 + 3)
			var v: float = cy + hash01(cx * 13 + i, cy * 29 + 5)
			if not p.pt(u, v):
				continue
			var lean: float = (hash01(cx * 7 + i, cy * 11 + 9) - 0.5) * 0.06
			var h: float = minf(22.0, (0.045 + 0.06 * hash01(cx * 5 + i, cy * 3 + 1)) * 2.0 * hs / p.f)
			c.move_to(p.px, p.py)
			c.line_to(p.px + lean * p.f2, p.py - h)
	elif kind == "brick":
		p.seg(c, cx, cy, 0.0, 0.0, 1.0, 0.0)
		p.seg(c, cx, cy, 0.0, 0.5, 1.0, 0.5)
		p.seg(c, cx, cy, 0.5, 0.0, 0.5, 0.5)
		p.seg(c, cx, cy, 0.0, 0.5, 0.0, 1.0)
	elif kind == "plank":
		for i in 3:
			var v2: float = i / 3.0
			p.seg(c, cx, cy, 0.0, v2, 1.0, v2)
			var j: float = 0.2 + 0.6 * hash01(cx * 19 + i, cy * 23 + 2)
			p.seg(c, cx, cy, j, v2, j, v2 + 1.0 / 3.0)
	else:
		for i in 4:
			var u2: float = cx + 0.15 + 0.7 * hash01(cx * 41 + i, cy * 43 + 1)
			var v3: float = cy + 0.15 + 0.7 * hash01(cx * 47 + i, cy * 53 + 2)
			if not p.pt(u2, v3):
				continue
			var rx: float = (0.1 + 0.07 * hash01(cx * 59 + i, cy * 61 + 4)) * p.f2
			var ry: float = rx * 0.5
			if rx < 0.8:
				continue
			c.move_to(p.px + rx, p.py)
			c.ellipse(p.px, p.py, rx, ry, 0.0, 0.0, TWO_PI)


static func draw_floor_texture(rs: RenderState, c: Canvas, world: World, sonar: Sonar, t: float, player: Dictionary, tan_half: float, budget_cells: int = TEX_MAX_CELLS) -> void:
	_draw_surface_texture(rs, c, world, sonar, t, player, tan_half, false, budget_cells)
	if world != null:
		_draw_surface_texture(rs, c, world, sonar, t, player, tan_half, true, budget_cells)


## One surface of draw_floor_texture; up = the ceiling (mirrored about the horizon) over indoor cells only.
static func _draw_surface_texture(rs: RenderState, c: Canvas, world: World, sonar: Sonar, t: float, player: Dictionary, tan_half: float, up: bool, budget_cells: int) -> void:
	var pulses: Array = sonar.pulses
	if pulses.is_empty() or not air_on(rs) or world == null:
		return
	var half_w: float = rs.ow / 2.0
	var focal: float = half_w / tan_half
	var ca: float = cos(player["angle"])
	var sa: float = sin(player["angle"])
	var half: float = rs.oh / 2.0
	var p := FloorProj.new()
	p.player_x = player["x"]
	p.player_y = player["y"]
	p.ca = ca
	p.sa = sa
	p.half_w = half_w
	p.focal = focal
	p.horizon = rs.horizon
	p.half = half
	p.up = up
	p.ow = rs.ow
	p.oh = rs.oh
	c.line_width = LineStyle.detail_width(LineStyle.ink_for(rs), 1.0, 1.0)
	c.stroke_style = "#d8ecff"
	var budget: int = budget_cells
	var k := 0
	while k < pulses.size() and budget > 0:
		var pu: Sonar.Pulse = pulses[k]
		k += 1
		if pu.gen > 0 or _is_ring_kind(pu.kind):
			continue
		if pu.z > 0.7:
			continue
		var rr: float = Sonar.ring_radius(pu, t)
		if rr < 0.5:
			continue
		var fade: float = pu.fade if pu.fade > 0.0 else sonar.fade
		var dur: float = Pose.glow_dur(fade) * 1.5
		var band: float = dur * pu.speed
		var r_max: float = minf(rr, pu.range)
		var base: float = 0.85 * minf(1.0, pu.strength * 1.3)
		if pu.weak > 0.0:
			base *= 0.7 if rs.reduced else 1.0 - 0.3 * minf(1.0, pu.weak)
		var x0: int = maxi(0, int(floor(minf(player["x"], pu.x) - r_max - 1.0)))
		var x1: int = int(ceil(maxf(player["x"], pu.x) + r_max + 1.0))
		var y0: int = maxi(0, int(floor(minf(player["y"], pu.y) - r_max - 1.0)))
		var y1: int = int(ceil(maxf(player["y"], pu.y) + r_max + 1.0))
		var sets: Array = []
		for b in TEX_BUCKETS:
			sets.append([])
		var lo: float = maxf(0.0, rr - band)
		# Only the annulus lo <= d <= r_max can pass the exact distance test below, so each row scans just the cell columns that
		# can fall inside it (bounds widened by EPS; the exact test stays). Cell order is unchanged: left to right.
		var px_: float = player["x"]
		var py_: float = player["y"]
		var r_max2: float = r_max * r_max
		var lo2: float = lo * lo
		var cy := y0
		while cy <= y1:
			var my: float = cy + 0.5
			var ddy: float = my - pu.y
			var rem: float = r_max2 - ddy * ddy
			if rem < -1e-6:
				cy += 1
				continue
			var w_hi: float = sqrt(maxf(rem, 0.0)) + 1e-4
			var w_lo: float = 0.0
			var rem_lo: float = lo2 - ddy * ddy
			if rem_lo > 1e-4:
				w_lo = sqrt(rem_lo) - 1e-4
			var a0: int = maxi(x0, int(ceil(pu.x - w_hi - 0.5)))
			var b0: int = mini(x1, int(floor(pu.x + w_hi - 0.5)))
			var a1: int = 1
			var b1: int = 0
			if w_lo > 0.01:
				b0 = mini(b0, int(floor(pu.x - w_lo - 0.5)))
				a1 = maxi(x0, int(ceil(pu.x + w_lo - 0.5)))
				b1 = mini(x1, int(floor(pu.x + w_hi - 0.5)))
			for seg in 2:
				var ca_: int = a0 if seg == 0 else a1
				var cb_: int = b0 if seg == 0 else b1
				for cx in range(ca_, cb_ + 1):
					var mx: float = cx + 0.5
					var d: float = sqrt((mx - pu.x) * (mx - pu.x) + ddy * ddy)
					if d > r_max or d < lo:
						continue
					var dxp: float = mx - px_
					var dyp: float = my - py_
					var fwd: float = dxp * ca + dyp * sa
					if fwd < 0.3:
						continue
					var g: float = Pose.glow((rr - d) / pu.speed, dur) * base * (1.0 - d / pu.range)
					if g < 0.05:
						continue
					var sx: float = half_w + ((-dxp * sa + dyp * ca) / fwd) * focal
					if sx < -40.0 or sx > rs.ow + 40.0:
						continue
					var col: int = maxi(0, mini(rs.cols - 1, int(floor(sx / rs.col_w))))
					if fwd > rs.zbuf[col] + 0.05 or not Sonar.visible_from(pu, mx, my):
						continue
					if world.is_solid(mx, my):
						continue
					var kind: String = floor_tex_kind(world.material_at(mx, my))
					if kind == "":
						continue
					if up:
						if world.kind_at(mx, my) == "outdoor":
							continue
						kind = ceil_tex_kind(world, mx, my)
					var bk: int = mini(TEX_BUCKETS - 1, int(floor(g * TEX_BUCKETS * 1.2)))
					sets[bk].append([cx, cy, kind])
					budget -= 1
					if budget <= 0:
						break
				if budget <= 0:
					break
			if budget <= 0:
				break
			cy += 1
		for b in TEX_BUCKETS:
			var s: Array = sets[b]
			if s.is_empty():
				continue
			c.global_alpha = minf(0.9, base * (0.3 + 0.7 * (float(b + 1) / TEX_BUCKETS)) * 0.8)
			c.begin_path()
			for cell in s:
				add_floor_cell(c, p, cell[2], cell[0], cell[1], half)
			c.stroke()
	c.global_alpha = 1.0


# ---------------------------------------------------------------- floor front

## Begin a path and trace one floor-front arc of radius rr around pulse pu (perspective-projected, occluded).
static func trace_front(rs: RenderState, c: Canvas, pu: Sonar.Pulse, rr: float, player: Dictionary, ca: float, sa: float, half_w: float, focal: float, horizon: float, half: float) -> void:
	c.begin_path()
	var pen := false
	for s in FRONT_SEG + 1:
		var th: float = (float(s) / FRONT_SEG) * TWO_PI
		var wx: float = pu.x + cos(th) * rr
		var wy: float = pu.y + sin(th) * rr
		var dx: float = wx - player["x"]
		var dy: float = wy - player["y"]
		var fwd: float = dx * ca + dy * sa
		var ok: bool = fwd > 0.2
		var sx := 0.0
		var y := 0.0
		if ok:
			sx = half_w + ((-dx * sa + dy * ca) / fwd) * focal
			y = horizon + half / fwd
			if sx < -20.0 or sx > rs.ow + 20.0 or y > rs.oh * 4.0:
				ok = false
			else:
				var col: int = maxi(0, mini(rs.cols - 1, int(floor(sx / rs.col_w))))
				if fwd > rs.zbuf[col] + 0.05 or not Sonar.visible_from(pu, wx, wy):
					ok = false
		if not ok:
			pen = false
			continue
		if not pen:
			c.move_to(sx, y)
			pen = true
		else:
			c.line_to(sx, y)


static func draw_floor_front(rs: RenderState, c: Canvas, world: World, sonar: Sonar, t: float, player: Dictionary, tan_half: float) -> void:
	var pulses: Array = sonar.pulses
	if pulses.is_empty() or rs.quality < 2:
		return
	var half_w: float = rs.ow / 2.0
	var focal: float = half_w / tan_half
	var ca: float = cos(player["angle"])
	var sa: float = sin(player["angle"])
	var horizon: float = rs.horizon
	var half: float = rs.oh / 2.0
	c.stroke_style = "#e8f2ff"
	c.fill_style = "#e8f2ff"
	c.line_width = LineStyle.detail_width(LineStyle.ink_for(rs), 1.0, 1.5)
	for k in pulses.size():
		var pu: Sonar.Pulse = pulses[k]
		if pu.gen > 0 or _is_ring_kind(pu.kind):
			continue
		if pu.z > 0.7:
			continue
		var rr: float = Sonar.ring_radius(pu, t)
		if rr < 0.3 or rr > pu.range:
			continue
		var fade: float = pu.fade if pu.fade > 0.0 else sonar.fade
		var age: float = t - pu.t0
		var a: float = 0.5 * (1.0 - rr / pu.range) * minf(1.0, pu.strength * 1.3) * (maxf(0.0, 1.0 - age / (fade * 2.0)) if fade > 0.0 else 1.0)
		if pu.weak > 0.0:
			a *= 0.7 if rs.reduced else 1.0 - 0.3 * minf(1.0, pu.weak) * (0.5 + 0.5 * sin(t * 15.0 + k))
		if a < 0.04:
			continue
		c.global_alpha = a
		trace_front(rs, c, pu, rr, player, ca, sa, half_w, focal, horizon, half)
		c.stroke()
		if rs.fx >= 1:
			for q in 2:
				var rq: float = rr - 0.06 * (q + 1)
				if rq < 0.3:
					break
				c.global_alpha = a * (0.45 if q == 0 else 0.2)
				trace_front(rs, c, pu, rq, player, ca, sa, half_w, focal, horizon, half)
				c.stroke()
		var seed_v: int = round_js(pu.t0 * 1000.0) + k * 7919
		var nd: int = FRONT_DOTS if rs.quality >= 3 else (FRONT_DOTS >> 1)
		var span := 0.5
		var dw := 1.0
		var dh := 1.0
		if air_on(rs):
			var sp := speckle(pulse_rough(world, pu))
			nd = mini(FRONT_DOTS * 2, round_js(nd * sp["n"]))
			span = sp["back"]
			var fm: String = world.material_at(pu.x, pu.y) if world != null else "stone"
			if fm == "grass":
				dh = 2.0
			elif fm == "wood":
				dw = 2.0
		c.global_alpha = a * 0.7
		c.begin_path()
		var any := false
		for d in nd:
			var th: float = hash01(seed_v, d * 2) * TWO_PI
			var back: float = 0.06 + span * hash01(seed_v, d * 2 + 1)
			var rd: float = rr * (1.0 - back)
			var wx: float = pu.x + cos(th) * rd
			var wy: float = pu.y + sin(th) * rd
			var dx: float = wx - player["x"]
			var dy: float = wy - player["y"]
			var fwd: float = dx * ca + dy * sa
			if fwd <= 0.25:
				continue
			var sx: float = half_w + ((-dx * sa + dy * ca) / fwd) * focal
			var y: float = horizon + half / fwd
			if sx < 0.0 or sx >= rs.ow or y >= rs.oh:
				continue
			var col: int = mini(rs.cols - 1, int(floor(sx / rs.col_w)))
			if fwd > rs.zbuf[col] + 0.05 or not Sonar.visible_from(pu, wx, wy):
				continue
			c.rect(sx - 0.5, y - 0.5, dw, dh)
			any = true
		if any:
			c.fill()
	c.global_alpha = 1.0


# ---------------------------------------------------------------- footstep rings and secondary rings

## Footstep ripples on the floor: 2-3 wobbly concentric rings around each step's origin.
static func draw_foot_rings(rs: RenderState, c: Canvas, sonar: Sonar, t: float, player: Dictionary, tan_half: float) -> void:
	var pulses: Array = sonar.pulses
	if pulses.is_empty() or rs.quality < 1:
		return
	var half_w: float = rs.ow / 2.0
	var focal: float = half_w / tan_half
	var ca: float = cos(player["angle"])
	var sa: float = sin(player["angle"])
	var horizon: float = rs.horizon
	var half: float = rs.oh / 2.0
	var boil: bool = rs.boil_on
	var nr: int = 3 if rs.quality >= 2 else 2
	for k in pulses.size():
		var pu: Sonar.Pulse = pulses[k]
		if pu.kind != "step" and pu.kind != "personStep":
			continue
		var age: float = t - pu.t0
		var fade: float = pu.fade if pu.fade > 0.0 else sonar.fade
		if age < 0.0 or age >= fade:
			continue
		var str_: float = pu.strength
		var own: bool = pu.kind == "personStep"
		var nrk: int = mini(nr, 2) if own else nr
		c.stroke_style = COL_RING_PERSON if own else "#e8f2ff"
		for m in nrk:
			var rr: float = RippleFx.foot_ring(age, fade, pu.range * 1.8, m)
			if rr < 0.0:
				continue
			var a: float = minf(1.0, RippleFx.foot_ring_alpha(age, fade, m) * minf(1.0, str_ * 4.0) * (0.7 if own else 1.2))
			if a < 0.03:
				continue
			c.global_alpha = a
			c.line_width = (1.7 if m == 0 else 1.3) * rs.wscale
			c.begin_path()
			var pen := false
			var ph: float = k * 1.7 + m * 2.1
			for s in FOOT_SEG + 1:
				var th: float = (float(s) / FOOT_SEG) * TWO_PI
				var rw: float = RippleFx.wavy_radius(rr, th, t * 3.0 + ph, 5.0, 0.06)
				var wx: float = pu.x + cos(th) * rw
				var wy: float = pu.y + sin(th) * rw
				if own and not is_nan(pu.hd):
					var lx: float = cos(th) * rw * 1.2
					var ly: float = sin(th) * rw * 0.5
					var ch: float = cos(pu.hd)
					var sh: float = sin(pu.hd)
					wx = pu.x + lx * ch - ly * sh
					wy = pu.y + lx * sh + ly * ch
				var dx: float = wx - player["x"]
				var dy: float = wy - player["y"]
				var fwd: float = dx * ca + dy * sa
				var ok: bool = fwd > 0.2
				var sx := 0.0
				var y := 0.0
				if ok:
					var right: float = -dx * sa + dy * ca
					sx = half_w + (right / fwd) * focal
					y = horizon + half / fwd
					if sx < -20.0 or sx > rs.ow + 20.0 or y > rs.oh * 4.0:
						ok = false
					else:
						var col: int = maxi(0, mini(rs.cols - 1, int(floor(sx / rs.col_w))))
						if fwd > rs.zbuf[col] + 0.05:
							ok = false
				if not ok:
					pen = false
					continue
				if boil:
					sx += rs.j(s + m * 32 + k * 5, 0) * 0.35 * rs.wscale
					y += rs.j(s + m * 32 + k * 5, 1) * 0.35 * rs.wscale
				if not pen:
					c.move_to(sx, y)
					pen = true
				else:
					c.line_to(sx, y)
			c.stroke()
	c.global_alpha = 1.0


## Secondary echo rings (from struck people and markers) as wavy dotted floor circles. Returns how many were drawn.
static func draw_rings(rs: RenderState, c: Canvas, rings: Array, t: float, player: Dictionary, tan_half: float) -> int:
	if rings.is_empty() or rs.quality < 2:
		return 0
	var half_w: float = rs.ow / 2.0
	var focal: float = half_w / tan_half
	var ca: float = cos(player["angle"])
	var sa: float = sin(player["angle"])
	var horizon: float = rs.horizon
	var half: float = rs.oh / 2.0
	var dot: float = 2.0 * rs.wscale
	var hd: float = dot / 2.0
	var boil: bool = rs.boil_on
	var drawn := 0
	for k in rings.size():
		var rg: Dictionary = rings[k]
		var a: float = RippleFx.Rings.alpha(rg, t)
		if a <= 0.01:
			continue
		var rr: float = RippleFx.Rings.radius(rg, t)
		c.fill_style = COL_RING_PERSON if rg["kind"] == "person" else (COL_RING_MARKER if rg["kind"] == "marker" else COL_RING_OTHER)
		c.global_alpha = a * 0.8 if rg["kind"] == "person" else a
		c.begin_path()
		var any := false
		for s in SEC_SAMPLES:
			var th: float = (float(s) / SEC_SAMPLES) * TWO_PI
			var rw: float = RippleFx.wavy_radius(rr, th, t * 1.6 + k, 6.0, 0.05)
			var wx: float = rg["x"] + cos(th) * rw
			var wy: float = rg["y"] + sin(th) * rw
			var dx: float = wx - player["x"]
			var dy: float = wy - player["y"]
			var fwd: float = dx * ca + dy * sa
			if fwd <= 0.15:
				continue
			var right: float = -dx * sa + dy * ca
			var sx: float = half_w + (right / fwd) * focal
			if sx < 0.0 or sx >= rs.ow:
				continue
			var col: int = mini(rs.cols - 1, int(floor(sx / rs.col_w)))
			if fwd > rs.zbuf[col] + 0.05:
				continue
			var y: float = horizon + half / fwd + (rs.j(s + k * 11, 1) * 0.5 * rs.wscale if boil else 0.0)
			if y < 0.0 or y >= rs.oh:
				continue
			c.rect(sx + (rs.j(s + k * 11, 0) * 0.5 * rs.wscale if boil else 0.0) - hd, y - hd, dot, dot)
			any = true
		if any:
			c.fill()
			drawn += 1
	c.global_alpha = 1.0
	return drawn
