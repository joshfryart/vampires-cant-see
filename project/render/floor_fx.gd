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


## Ink-world floor style (docs/STYLE.md section 1, "Floors"), or "" for classic worlds: "rubble" (cave: hollow rock) or "setts" (road, inn yard).
## Water sheen applies to every ink world. Gated on world.wall_style only, so classic floors are unchanged.
static func ink_floor_style(world: World) -> String:
	if world == null or world.wall_style.is_empty():
		return ""
	var vals: Array = world.wall_style.values()
	if vals.has("rock"):
		return "rubble"
	if vals.has("drystone") or vals.has("fence") or vals.has("milestone"):
		return "setts"
	return "ink"


## floor_tex_kind for a world: the ink floors replace stone brick joints (hollow: rubble; road and inn yard: setts) and give water its sheen.
static func floor_kind_for(world: World, mat: String, style: String) -> String:
	if style == "":
		return floor_tex_kind(mat)
	if mat == "water":
		return "water"
	if style == "rubble" and (mat == "stone" or mat == "roughStone"):
		return "rubble"
	if style == "setts" and (mat == "stone" or mat == "cobble" or mat == "roughStone"):
		return "sett"
	if mat == "stone" or mat == "roughStone":
		return "rubble" # ink worlds never draw brick joints: loose rubble instead
	if mat == "wood":
		return "plank_ink" # broken boards, not long straight joints
	return floor_tex_kind(mat)


## Ceiling marks for the zone at (x, y): its ceiling material from the acoustics data, else brick.
static func ceil_tex_kind(world: World, x: float, y: float) -> String:
	var zone := world.zone_at(x, y)
	var k := floor_tex_kind(Acoustics.ceiling_for(zone if zone != "" else world.name)["mat"])
	return k if k != "" else "brick"


## Ink-world ceiling style (docs/STYLE.md, 0.21.4), or "" for classic worlds: "cave" (hollow), "inn", "wood", "moor", "road".
static func ceil_style(world: World) -> String:
	if world == null or world.wall_style.is_empty():
		return ""
	var vals: Array = world.wall_style.values()
	if vals.has("rock"):
		return "cave"
	if vals.has("timber"):
		return "inn"
	if vals.has("fence") or vals.has("milestone"):
		return "road"
	if vals.has("gorse"):
		return "moor"
	if vals.has("trunk"):
		return "wood"
	return "moor"


## Ceiling mark kind for an ink world at (x, y): outdoor cells get sky (canopy over the wood, stars elsewhere), indoor cells their chamber's
## ceiling (cave: rock vault, tall in the echo hall, tight in the squeeze; inn: timber rafters; pockets elsewhere: vault).
static func ceil_kind_styled(world: World, x: float, y: float) -> String:
	var cs := ceil_style(world)
	if cs == "":
		return ""
	if world.kind_at(x, y) == "outdoor":
		return "canopy" if cs == "wood" else "stars"
	if cs == "inn":
		return "rafter"
	var zone := world.zone_at(x, y)
	if zone == "echo_hall":
		return "vault_hall"
	if zone == "squeeze":
		return "vault_tight"
	return "vault"


## Ceiling height of an ink world at (x, y) in wall heights (1 = flush with the wall tops). Cave chambers differ by zone: the echo hall is
## the highest vault, the squeeze sits flush with the wall tops. Sky marks (outdoor) pick their own height per mark; 2 is returned for them.
static func ceil_height(world: World, x: float, y: float) -> float:
	var cs := ceil_style(world)
	if cs == "":
		return 1.0
	if world.kind_at(x, y) == "outdoor":
		return 2.0
	var zone := world.zone_at(x, y)
	if cs == "cave":
		if zone == "echo_hall":
			return 1.4
		if zone == "squeeze":
			return 1.0
		if zone == "drip_gallery":
			return 1.2
		if zone.begins_with("pocket"):
			return 1.05
		var cx: int = int(floor(x))
		var cy: int = int(floor(y))
		return 1.12 + 0.1 * (hash01(cx * 191 + 7, cy * 193 + 11) - 0.5)
	if cs == "inn" and zone == "tavern":
		return 1.15
	return 1.0


## Height of the ceiling plane mesh: the ink cave vault sits above the wall tops.
static func ceil_mesh_mul(world: World) -> float:
	return 1.12 if ceil_style(world) == "cave" else 1.0


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
	## ceiling height in wall heights (ink worlds; 1 = the wall tops)
	var hmul: float = 1.0
	var ow: float
	var oh: float

	func pt(wx: float, wy: float) -> bool:
		var dx: float = wx - player_x
		var dy: float = wy - player_y
		var fwd: float = dx * ca + dy * sa
		if fwd < 0.3:
			return false
		px = half_w + ((-dx * sa + dy * ca) / fwd) * focal
		py = horizon - half * hmul / fwd if up else horizon + half / fwd
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


## Stone u-ranges of the three sett rows (staggered by a quarter cell on the middle row).
const SETT_ROWS := [[0.0, 0.5, 0.5, 1.0], [0.0, 0.25, 0.25, 0.75, 0.75, 1.0], [0.0, 0.5, 0.5, 1.0]]
static var _sett_pts: PackedFloat32Array = PackedFloat32Array([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])


## One cell of setts: three staggered rows of rounded rects (7 stones, a gap between them). The projection is inlined (the plain FloorProj.pt costs
## more than the stones); cells nearer than 4 chamfer their corners, the rest draw quads.
static func _add_setts(c: Canvas, p: FloorProj, cx: int, cy: int) -> void:
	var dx0: float = cx - p.player_x
	var dy0: float = cy - p.player_y
	var f0: float = dx0 * p.ca + dy0 * p.sa
	var l0: float = -dx0 * p.sa + dy0 * p.ca
	var fc: float = f0 + 0.5 * (p.ca + p.sa)
	if minf(minf(f0, f0 + p.ca), minf(f0 + p.sa, f0 + p.ca + p.sa)) < 0.3:
		return
	var n: int = 8 if fc < 4.0 else 4
	var pts: PackedFloat32Array = _sett_pts
	var ch: float = 0.05
	for row in 3:
		var v0: float = row / 3.0 + 0.025
		var v1: float = (row + 1) / 3.0 - 0.025
		var us: Array = SETT_ROWS[row]
		for k in range(0, us.size(), 2):
			var a: float = us[k] + 0.03
			var b: float = us[k + 1] - 0.03
			if n == 8:
				pts[0] = a + ch
				pts[1] = v0
				pts[2] = b - ch
				pts[3] = v0
				pts[4] = b
				pts[5] = v0 + ch
				pts[6] = b
				pts[7] = v1 - ch
				pts[8] = b - ch
				pts[9] = v1
				pts[10] = a + ch
				pts[11] = v1
				pts[12] = a
				pts[13] = v1 - ch
				pts[14] = a
				pts[15] = v0 + ch
			else:
				pts[0] = a
				pts[1] = v0
				pts[2] = b
				pts[3] = v0
				pts[4] = b
				pts[5] = v1
				pts[6] = a
				pts[7] = v1
			for q in n:
				var u: float = pts[q * 2]
				var v: float = pts[q * 2 + 1]
				var f: float = f0 + u * p.ca + v * p.sa
				var px: float = p.half_w + ((l0 - u * p.sa + v * p.ca) / f) * p.focal
				var py: float = p.horizon - p.half / f if p.up else p.horizon + p.half / f
				if q == 0:
					c.move_to(px, py)
				else:
					c.line_to(px, py)
			c.close_path()


## A polyline through (u, v) cell-space points; a point that does not project ends the stroke.
static func _poly(c: Canvas, p: FloorProj, pts: Array) -> void:
	var pen := false
	for q in pts:
		if not p.pt(q[0], q[1]):
			pen = false
			continue
		if pen:
			c.line_to(p.px, p.py)
		else:
			c.move_to(p.px, p.py)
			pen = true


## Ink floor planks: boards run along the cell but the joints are short, broken and jittered (no long straight lines).
static func _add_planks_ink(c: Canvas, p: FloorProj, cx: int, cy: int) -> void:
	for i in 3:
		if hash01(cx * 229 + i, cy * 233 + 9) < 0.28:
			continue
		var v: float = (i + 0.2 + 0.6 * hash01(cx * 191 + i, cy * 197 + 3)) / 3.0
		var a: float = 0.3 * hash01(cx * 199 + i, cy * 211 + 5)
		var b: float = 0.55 + 0.45 * hash01(cx * 223 + i, cy * 227 + 7)
		p.seg(c, cx, cy, a, v, b, v + 0.02 * (hash01(cx * 239 + i, cy * 241 + 2) - 0.5))
	if hash01(cx * 251 + 1, cy * 257 + 3) < 0.6:
		var j: float = 0.15 + 0.7 * hash01(cx * 263 + 2, cy * 269 + 4)
		var v0: float = hash01(cx * 271 + 3, cy * 277 + 5) * 0.5
		p.seg(c, cx, cy, j, v0, j, v0 + 0.25)


## Cave ceiling cell (ink): irregular crack zigzags, a dip-aligned stratum dash, stalactite clusters and drip points.
## mode 0 = ordinary chamber, 1 = echo hall (sparse, long stalactites), 2 = squeeze (dense, short and tight).
static func _add_vault(c: Canvas, p: FloorProj, cx: int, cy: int, mode: int) -> void:
	# rock bosses: irregular closed contour loops, like the wall outline seen from underneath
	if hash01(cx * 569 + 2, cy * 571 + 6) < [0.3, 0.22, 0.4][mode]:
		var bu: float = cx + 0.25 + 0.5 * hash01(cx * 577 + 2, cy * 581 + 7)
		var bv: float = cy + 0.25 + 0.5 * hash01(cx * 587 + 3, cy * 593 + 8)
		var r0: float = 0.08 + 0.12 * hash01(cx * 599 + 4, cy * 601 + 9)
		var ph: float = hash01(cx * 607 + 5, cy * 613 + 1) * TWO_PI
		var lp: Array = []
		for k in 15:
			var th: float = TWO_PI * (k % 14) / 14.0
			var rk: float = r0 * (1.0 + 0.35 * sin(2.0 * th + ph) + 0.25 * (hash01(cx * 617 + k % 14, cy * 619 + 2) - 0.5))
			lp.append([bu + cos(th) * rk * 1.3, bv + sin(th) * rk])
		_poly(c, p, lp)
	# cracks: short, many-jointed
	var ncr: int = 1 if mode != 2 else 2
	for i in ncr:
		if hash01(cx * 281 + i, cy * 283 + 5) < 0.5:
			var u: float = cx + 0.1 + 0.8 * hash01(cx * 293 + i, cy * 307 + 1)
			var v: float = cy + 0.1 + 0.8 * hash01(cx * 311 + i, cy * 313 + 2)
			var ang: float = hash01(cx * 317 + i, cy * 331 + 3) * TWO_PI
			var pts: Array = [[u, v]]
			for k in 4:
				ang += (hash01(cx * 337 + i * 4 + k, cy * 347 + 4) - 0.5) * 2.4
				var l: float = 0.04 + 0.07 * hash01(cx * 349 + i * 4 + k, cy * 353 + 6)
				u += cos(ang) * l
				v += sin(ang) * l
				pts.append([u, v])
			_poly(c, p, pts)
	# grain
	for i in 2:
		if hash01(cx * 621 + i, cy * 623 + 3) < 0.55:
			if p.pt(cx + hash01(cx * 627 + i, cy * 629 + 4), cy + hash01(cx * 631 + i, cy * 633 + 5)):
				c.move_to(p.px + 0.7, p.py)
				c.ellipse(p.px, p.py, 0.7, 0.5, 0.0, 0.0, TWO_PI)
	# bedding: the dip direction is shared across 6 cells, so the dashes line up in drifts rather than a grid
	if hash01(cx * 359 + 1, cy * 367 + 2) < 0.3:
		var da: float = hash01(int(floor(cx / 6.0)) * 373 + 1, int(floor(cy / 6.0)) * 379 + 3) * PI
		var su: float = cx + 0.15 + 0.5 * hash01(cx * 383 + 4, cy * 389 + 5)
		var sv: float = cy + 0.15 + 0.7 * hash01(cx * 397 + 5, cy * 401 + 6)
		var sl: float = 0.15 + 0.2 * hash01(cx * 409 + 6, cy * 419 + 7)
		var wob: float = (hash01(cx * 421 + 7, cy * 431 + 8) - 0.5) * 0.3
		_poly(c, p, [[su, sv], [su + cos(da + wob) * sl * 0.5, sv + sin(da + wob) * sl * 0.5], [su + cos(da) * sl, sv + sin(da) * sl]])
	var pst: float = [0.3, 0.2, 0.55][mode]
	if hash01(cx * 433 + 8, cy * 439 + 9) < pst:
		var ku: float = cx + 0.2 + 0.6 * hash01(cx * 443 + 9, cy * 449 + 1)
		var kv: float = cy + 0.2 + 0.6 * hash01(cx * 457 + 1, cy * 461 + 2)
		var n: int = 2 + int(hash01(cx * 463 + 2, cy * 467 + 3) * (2.2 if mode != 2 else 3.2))
		for i in n:
			var u2: float = ku + (hash01(cx * 479 + i, cy * 487 + 3) - 0.5) * 0.28
			var v2: float = kv + (hash01(cx * 491 + i, cy * 499 + 4) - 0.5) * 0.28
			if not p.pt(u2, v2):
				continue
			var ln: float = ([0.08, 0.16, 0.06][mode] + [0.12, 0.22, 0.08][mode] * hash01(cx * 503 + i, cy * 509 + 5)) * p.half / p.f
			ln = minf(ln, 36.0)
			var hw: float = clampf(0.025 * p.f2, 0.8, 4.0)
			if ln < 1.5:
				continue
			var tip: float = (hash01(cx * 521 + i, cy * 523 + 6) - 0.5) * hw * 0.6
			c.move_to(p.px - hw, p.py)
			c.line_to(p.px + tip, p.py + ln)
			c.line_to(p.px + hw, p.py)
			if i == 0 and hash01(cx * 541 + 1, cy * 547 + 2) < 0.3:
				# a drip bead hanging under the first tip
				c.move_to(p.px + tip + 1.0, p.py + ln + 3.5)
				c.ellipse(p.px + tip, p.py + ln + 3.5, 1.0, 1.4, 0.0, 0.0, TWO_PI)


## Wood canopy (ink): small leaf V-ticks and a short twig, at varied heights above the thicket tops.
static func _add_canopy(c: Canvas, p: FloorProj, cx: int, cy: int) -> void:
	for i in 4:
		var u: float = cx + hash01(cx * 557 + i, cy * 563 + 1)
		var v: float = cy + hash01(cx * 569 + i, cy * 571 + 2)
		p.hmul = 1.25 + 0.4 * hash01(cx * 577 + i, cy * 587 + 3)
		if not p.pt(u, v):
			continue
		var sz: float = clampf(p.f2 * 0.05, 1.5, 5.0)
		var lean: float = (hash01(cx * 593 + i, cy * 599 + 4) - 0.5) * 1.2
		c.move_to(p.px - sz, p.py - sz * 0.7 + lean)
		c.line_to(p.px, p.py)
		c.line_to(p.px + sz, p.py - sz * 0.7 - lean)
	if hash01(cx * 601 + 1, cy * 607 + 2) < 0.4:
		p.hmul = 1.3
		var tu: float = cx + 0.1 + 0.5 * hash01(cx * 613 + 1, cy * 617 + 3)
		var tv: float = cy + 0.2 + 0.6 * hash01(cx * 619 + 2, cy * 631 + 4)
		var ta: float = hash01(cx * 641 + 3, cy * 643 + 5) * PI
		_poly(c, p, [[tu, tv], [tu + cos(ta) * 0.2, tv + sin(ta) * 0.2], [tu + cos(ta + 0.5) * 0.35, tv + sin(ta + 0.5) * 0.35]])


## Night sky (moor, road, inn yard, cave apron): a few stars per cell at high heights.
static func _add_stars(c: Canvas, p: FloorProj, cx: int, cy: int) -> void:
	var n: int = (1 if hash01(cx * 647 + 1, cy * 653 + 2) < 0.55 else 0) + (1 if hash01(cx * 659 + 2, cy * 661 + 3) < 0.18 else 0)
	for i in n:
		var u: float = cx + hash01(cx * 673 + i, cy * 677 + 4)
		var v: float = cy + hash01(cx * 683 + i, cy * 691 + 5)
		p.hmul = 1.9 + 2.0 * hash01(cx * 701 + i, cy * 709 + 6)
		if not p.pt(u, v):
			continue
		c.move_to(p.px + 0.8, p.py)
		c.ellipse(p.px, p.py, 0.8, 0.8, 0.0, 0.0, TWO_PI)


## Inn rafters (ink): a pair of beam lines along every second row with occasional broken joints, and tie beams every third column.
static func _add_rafters(c: Canvas, p: FloorProj, cx: int, cy: int) -> void:
	if cy % 2 == 0 and hash01(cx * 719 + 1, cy * 727 + 2) > 0.1:
		p.seg(c, cx, cy, 0.0, 0.42, 1.0, 0.42)
		p.seg(c, cx, cy, 0.0, 0.58, 1.0, 0.58)
	if cx % 3 == 0 and hash01(cx * 733 + 3, cy * 739 + 4) < 0.5:
		p.seg(c, cx, cy, 0.0, 0.0, 0.0, 1.0)


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
	elif kind == "rubble":
		# two pebbles and one scratch per cell (stone loses its brick joints in ink worlds)
		for i in 2:
			var ru: float = cx + 0.15 + 0.7 * hash01(cx * 71 + i, cy * 73 + 1)
			var rv: float = cy + 0.15 + 0.7 * hash01(cx * 79 + i, cy * 83 + 2)
			if not p.pt(ru, rv):
				continue
			var rrx: float = (0.05 + 0.04 * hash01(cx * 89 + i, cy * 97 + 4)) * p.f2
			if rrx < 0.8:
				continue
			c.move_to(p.px + rrx, p.py)
			c.ellipse(p.px, p.py, rrx, rrx * 0.5, 0.0, 0.0, TWO_PI)
		var su: float = 0.1 + 0.5 * hash01(cx * 101 + 3, cy * 103 + 7)
		var sv: float = 0.15 + 0.7 * hash01(cx * 107 + 5, cy * 109 + 9)
		var sa: float = hash01(cx * 113 + 1, cy * 127 + 2) * PI
		var sl: float = 0.12 + 0.12 * hash01(cx * 131 + 6, cy * 137 + 3)
		p.seg(c, cx, cy, su, sv, su + cos(sa) * sl, sv + sin(sa) * sl)
	elif kind == "sett":
		_add_setts(c, p, cx, cy)
	elif kind == "water":
		# two or three short sheen dashes per cell, lateral to the view so they read as horizontal screen lines
		var nd: int = 2 + int(hash01(cx * 139 + 1, cy * 149 + 5) * 2.0)
		for i in nd:
			var wu: float = 0.1 + 0.55 * hash01(cx * 151 + i, cy * 157 + 3)
			var wv: float = (i + 0.3 + 0.4 * hash01(cx * 163 + i, cy * 167 + 8)) / nd
			var wl: float = 0.18 + 0.18 * hash01(cx * 173 + i, cy * 179 + 2)
			p.seg(c, cx, cy, wu - 0.5 * wl * -p.sa, wv - 0.5 * wl * p.ca, wu + 0.5 * wl * -p.sa, wv + 0.5 * wl * p.ca)
	elif kind == "plank_ink":
		_add_planks_ink(c, p, cx, cy)
	elif kind.begins_with("vault"):
		_add_vault(c, p, cx, cy, 1 if kind == "vault_hall" else (2 if kind == "vault_tight" else 0))
	elif kind == "canopy":
		_add_canopy(c, p, cx, cy)
	elif kind == "stars":
		_add_stars(c, p, cx, cy)
	elif kind == "rafter":
		_add_rafters(c, p, cx, cy)
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
	var fstyle: String = "" if up else ink_floor_style(world)
	var styled_up: bool = up and ceil_style(world) != ""
	var vault_mesh_on: bool = styled_up and world.has_meta("vault_mesh")
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
					var kind: String
					var hm := 1.0
					if styled_up:
						kind = ceil_kind_styled(world, mx, my)
						if vault_mesh_on and kind.begins_with("vault"):
							continue # the rock vault is geometry (VaultMesh + sonar_vault.gdshader), not canvas marks
						hm = ceil_height(world, mx, my)
					else:
						kind = floor_kind_for(world, world.material_at(mx, my), fstyle) if fstyle != "" else floor_tex_kind(world.material_at(mx, my))
						if kind == "":
							continue
						if up:
							if world.kind_at(mx, my) == "outdoor":
								continue
							kind = ceil_tex_kind(world, mx, my)
					var bk: int = mini(TEX_BUCKETS - 1, int(floor(g * TEX_BUCKETS * 1.2)))
					sets[bk].append([cx, cy, kind, hm])
					budget -= 4 if kind == "sett" else 1
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
			c.global_alpha = minf(0.9, base * (0.3 + 0.7 * (float(b + 1) / TEX_BUCKETS)) * 0.8 * (0.7 if styled_up else 1.0))
			c.begin_path()
			var water: Array = []
			for cell in s:
				if cell[2] == "water":
					water.append(cell)
				else:
					p.hmul = cell[3]
					add_floor_cell(c, p, cell[2], cell[0], cell[1], half)
			p.hmul = 1.0
			if water.size() < s.size():
				c.stroke()
			if not water.is_empty():
				# water sheen in the bounce blue (docs/STYLE.md: 7FA6FF), its own stroke
				c.stroke_style = "#7fa6ff"
				c.begin_path()
				for cell in water:
					add_floor_cell(c, p, "water", cell[0], cell[1], half)
				c.stroke()
				c.stroke_style = "#d8ecff"
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
