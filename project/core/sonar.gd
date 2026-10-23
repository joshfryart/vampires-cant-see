class_name Sonar
extends RefCounted
## Ports js/sonar.js (Phase 1 subset). One Sonar instance is the JS sonar `state`.
## Ray tables use Packed*32 arrays on purpose: JS stores them in Float32Array, so values quantise the same way.
## Not yet ported: sample3/brightnessAt3 helpers.

const TWO_PI := JsMath.TWO_PI
const TOL := 0.35
const SONAR_SPEED := 12.0
const MAX_PER_SOUND := 12
const NO_HIT := 255
## Hit surface materials by index into Pulse.vmat (js/sonar.js MATS).
const MATS := ["stone", "brick", "wood", "iron", "glass", "cobble", "roughStone", "grass"]
const DEFAULTS := {"speed": SONAR_SPEED, "range": 10.0, "fade": 3.0, "cooldown": 0.8, "maxPulses": 64, "visRays": 720, "reflectors": 6, "bounces": 2}


class Pulse:
	extends RefCounted
	var x: float = 0.0
	var y: float = 0.0
	var z: float = 0.5
	var fade: float = 3.0
	var t0: float = 0.0
	var range: float = 10.0
	var speed: float = SONAR_SPEED
	var strength: float = 1.0
	var kind: String = "ping"
	var gen: int = 0
	var vis: PackedFloat32Array = PackedFloat32Array()
	var vmat: PackedByteArray = PackedByteArray()
	var vnorm: PackedByteArray = PackedByteArray()
	var has_facing: bool = false
	var facing: float = 0.0
	## Empty when the pulse has no mouth beam.
	var vbeam: PackedFloat32Array = PackedFloat32Array()
	var mat: String = ""
	var weak: float = 0.0
	## Render caches and hints: mean roughness (js pu.rough), fixed aim (pu._aim), walking heading of a person step ring (pu.hd).
	var rough: float = NAN
	var aim_cache: float = NAN
	var hd: float = NAN
	## PulseTextures cache: this pulse's vis_tex row as a MAX_RAYS x 1 RGF image ((vis, beam), zero padded) and floor material code (-1 = not computed).
	var tex_img: Image = null
	var tex_fm: int = -1


var pulses: Array[Pulse] = []
var last_emit: float = -INF
var last_pulse: Pulse = null
var speed: float = SONAR_SPEED
var range_: float = 10.0
var fade: float = 3.0
var cooldown: float = 0.8
var max_pulses: int = 64
var vis_rays: int = 720
var reflectors: int = 6
var bounces: int = 2
## Opt-in (Ambient sets it): when the ring overflows max_pulses, last_pulse (the player's latest ping) is never the one evicted.
var protect_last: bool = false

# Result of the last scan (js module-level scanAge / scanFade / scanIdx).
var scan_age: float = -1.0
var scan_fade: float = 0.0
var scan_idx: int = -1


## Ports create (js/sonar.js:20). opts keys as in DEFAULTS.
static func create(opts: Dictionary = {}) -> Sonar:
	var s := Sonar.new()
	var v := {}
	for k in DEFAULTS:
		var o: Variant = opts.get(k)
		v[k] = float(o) if (o is float or o is int) and is_finite(float(o)) and float(o) > 0.0 else float(DEFAULTS[k])
	s.speed = v["speed"]
	s.range_ = v["range"]
	s.fade = v["fade"]
	s.cooldown = v["cooldown"]
	s.max_pulses = int(floor(v["maxPulses"]))
	s.vis_rays = maxi(8, int(floor(v["visRays"])))
	s.reflectors = int(floor(v["reflectors"]))
	var b: Variant = opts.get("bounces")
	s.bounces = mini(2, int(floor(float(b)))) if (b is float or b is int) and is_finite(float(b)) and float(b) >= 0.0 else int(DEFAULTS["bounces"])
	return s


func reset() -> void:
	pulses.clear()
	last_pulse = null


func cooldown_left(t: float) -> float:
	return maxf(0.0, cooldown - (t - last_emit))


## Ports fillRays (js/sonar.js:56): n rays out of (x, y), per-ray distance, material index and normal code.
static func fill_rays(pulse: Pulse, world, x: float, y: float, rng_range: float, n: int) -> void:
	if "mat_grid" in world and "solid_grid" in world:
		_fill_rays_fast(pulse, world, x, y, rng_range, n)
		return
	pulse.vis.resize(n)
	pulse.vmat.resize(n)
	pulse.vnorm.resize(n)
	for i in n:
		var h: Raycast.Hit = Raycast.hit_one(world, x, y, (float(i) / n) * TWO_PI, rng_range)
		pulse.vis[i] = h.ray_dist
		if h.hit:
			var mi: int = MATS.find(h.mat)
			pulse.vmat[i] = 0 if mi < 0 else mi
			pulse.vnorm[i] = 0 if h.nx > 0.0 else (1 if h.nx < 0.0 else (2 if h.ny > 0.0 else 3))
		else:
			pulse.vmat[i] = 0
			pulse.vnorm[i] = NO_HIT


static var _trig: Dictionary = {}


## cos/sin of (i / n) * 2 pi for i in 0..n-1 (same doubles the per-ray cos()/sin() calls produce), cached per n.
static func _trig_for(n: int) -> Array:
	var t: Variant = _trig.get(n)
	if t == null:
		var cs := PackedFloat64Array()
		var sn := PackedFloat64Array()
		cs.resize(n)
		sn.resize(n)
		for i in n:
			var a: float = (float(i) / n) * TWO_PI
			cs[i] = cos(a)
			sn[i] = sin(a)
		t = [cs, sn]
		_trig[n] = t
	return t


## fill_rays for World-like grids (solid_grid, mat_grid, width, height): the DDA of Raycast.trace inlined, no Hit allocation.
## Results are bit identical to the generic path.
static func _fill_rays_fast(pulse: Pulse, world, x: float, y: float, max_dist: float, n: int) -> void:
	var grid: PackedByteArray = world.solid_grid
	var mats: PackedByteArray = world.mat_grid
	var w: int = world.width
	var h: int = world.height
	var cap: int = 4 * ((w if w > 0 else 64) + (h if h > 0 else 64))
	var tr: Array = _trig_for(n)
	var cs: PackedFloat64Array = tr[0]
	var sn: PackedFloat64Array = tr[1]
	var vis := PackedFloat32Array()
	var vmat := PackedByteArray()
	var vnorm := PackedByteArray()
	vis.resize(n)
	vmat.resize(n)
	vnorm.resize(n)
	var cx0: int = int(floor(x))
	var cy0: int = int(floor(y))
	var start_in: bool = cx0 >= 0 and cy0 >= 0 and cx0 < w and cy0 < h
	var start_solid: bool = (not start_in) or grid[cy0 * w + cx0] == 1
	for i in n:
		var dx: float = cs[i]
		var dy: float = sn[i]
		if start_solid:
			vis[i] = 0.0
			vmat[i] = mats[cy0 * w + cx0] if start_in else 0
			var snx: float = -dx
			var sny: float = -dy
			vnorm[i] = 0 if snx > 0.0 else (1 if snx < 0.0 else (2 if sny > 0.0 else 3))
			continue
		var ddx: float = INF if dx == 0.0 else absf(1.0 / dx)
		var ddy: float = INF if dy == 0.0 else absf(1.0 / dy)
		var step_x: int = -1 if dx < 0.0 else 1
		var step_y: int = -1 if dy < 0.0 else 1
		var sdx: float = INF if dx == 0.0 else ((x - cx0) if dx < 0.0 else (cx0 + 1 - x)) * ddx
		var sdy: float = INF if dy == 0.0 else ((y - cy0) if dy < 0.0 else (cy0 + 1 - y)) * ddy
		var cx: int = cx0
		var cy: int = cy0
		var side: int = 0
		var found: bool = false
		var d: float = 0.0
		var m: int = 0
		for _s in cap:
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
			if cx < 0 or cy < 0 or cx >= w or cy >= h:
				found = true
				break
			var k: int = cy * w + cx
			if grid[k] == 1:
				found = true
				m = mats[k]
				break
		if found:
			vis[i] = d
			vmat[i] = m
			if side == 0:
				vnorm[i] = 1 if dx > 0.0 else 0
			else:
				vnorm[i] = 3 if dy > 0.0 else 2
		else:
			vis[i] = max_dist
			vmat[i] = 0
			vnorm[i] = NO_HIT
	pulse.vis = vis
	pulse.vmat = vmat
	pulse.vnorm = vnorm


## Ports makePulse (js/sonar.js:79). facing = NAN for no mouth beam.
static func make_pulse(world, x: float, y: float, t0: float, rng_range: float, spd: float, strength: float, kind: String, gen: int, n: int, z: float, fd: float, facing: float = NAN) -> Pulse:
	var p := Pulse.new()
	p.x = x
	p.y = y
	p.z = z
	p.fade = fd
	p.t0 = t0
	p.range = rng_range
	p.speed = spd
	p.strength = strength
	p.kind = kind
	p.gen = gen
	fill_rays(p, world, x, y, rng_range, n)
	if not is_nan(facing):
		p.has_facing = true
		p.facing = facing
		p.vbeam.resize(n)
		var vb := PackedFloat32Array()
		vb.resize(n)
		Acoustics.fill_beam_vis(vb, n, facing)
		p.vbeam = vb
	return p


## Ports pickReflectors (js/sonar.js:94): returns [{a, d}] nearest first.
static func pick_reflectors(pulse: Pulse, max_n: int) -> Array:
	var v: PackedFloat32Array = pulse.vis
	var n: int = v.size()
	var cand: Array = []
	var lim: float = pulse.range - 1e-4
	for i in n:
		var d: float = v[i]
		if d >= lim:
			continue
		var prev: float = v[i - 1 if i > 0 else n - 1]
		var nxt: float = v[i + 1 if i + 1 < n else 0]
		if d <= prev and d < nxt:
			cand.append({"a": (float(i) / n) * TWO_PI, "d": d})
	# JS Array.sort is stable; GDScript sort_custom is not, so break ties by candidate order.
	for i in cand.size():
		cand[i]["i"] = i
	cand.sort_custom(func(p, q): return p["d"] < q["d"] or (p["d"] == q["d"] and p["i"] < q["i"]))
	var min_sep: float = (20.0 * PI) / 180.0
	var out: Array = []
	var i := 0
	while i < cand.size() and out.size() < max_n:
		var ok := true
		for o in out:
			var da: float = absf(cand[i]["a"] - o["a"])
			if da > PI:
				da = TWO_PI - da
			if da < min_sep:
				ok = false
				break
		if ok:
			out.append({"a": cand[i]["a"], "d": cand[i]["d"]})
		i += 1
	return out


static func ray_index(pulse: Pulse, ang: float) -> int:
	var n: int = pulse.vis.size()
	var a: float = fmod(ang, TWO_PI)
	if a < 0.0:
		a += TWO_PI
	var i: int = int(floor((a / TWO_PI) * n + 0.5))
	if i >= n:
		i -= n
	return i


## Ports emitSound (js/sonar.js:124). opts: kind, range, strength, bounces, visRays, z, fade, facing. No cooldown here.
func emit_sound(world, x: float, y: float, t: float, opts: Dictionary = {}) -> Pulse:
	if world == null or is_nan(x) or is_nan(y) or is_inf(x) or is_inf(y):
		return null
	var o_range: Variant = opts.get("range")
	var rng_range: float = float(o_range) if (o_range is float or o_range is int) and float(o_range) > 0.0 else range_
	var o_str: Variant = opts.get("strength")
	var strength: float = float(o_str) if (o_str is float or o_str is int) and is_finite(float(o_str)) else 1.0
	strength = maxf(0.0, minf(1.0, strength))
	var o_b: Variant = opts.get("bounces")
	var nb: int = mini(2, int(floor(float(o_b)))) if (o_b is float or o_b is int) and float(o_b) > 0.0 else 0
	var o_r: Variant = opts.get("visRays")
	var rays: int = int(floor(float(o_r))) if (o_r is float or o_r is int) and float(o_r) >= 8.0 else 360
	var kind: String = opts["kind"] if opts.get("kind") is String else "ping"
	var o_z: Variant = opts.get("z")
	var z: float = maxf(0.0, minf(1.2, float(o_z))) if (o_z is float or o_z is int) and is_finite(float(o_z)) else 0.5
	var o_f: Variant = opts.get("fade")
	var fd: float = float(o_f) if (o_f is float or o_f is int) and is_finite(float(o_f)) and float(o_f) > 0.0 else fade
	var o_fc: Variant = opts.get("facing")
	var facing: float = float(o_fc) if (o_fc is float or o_fc is int) and is_finite(float(o_fc)) else NAN
	var primary := make_pulse(world, x, y, t, rng_range, speed, strength, kind, 0, rays, z, fd, facing)
	var made: Array[Pulse] = [primary]
	if nb > 0:
		var max_refl: int = reflectors if reflectors != 0 else 6
		var layer: Array[Pulse] = [primary]
		var gen := 1
		while gen <= nb and made.size() < MAX_PER_SOUND:
			var nxt: Array[Pulse] = []
			var li := 0
			while li < layer.size() and made.size() < MAX_PER_SOUND:
				var par: Pulse = layer[li]
				var refl: Array = pick_reflectors(par, max_refl)
				var r := 0
				while r < refl.size() and made.size() < MAX_PER_SOUND:
					var cr: float = par.range - refl[r]["d"]
					if cr >= 1.5:
						var ca: float = refl[r]["a"]
						var hx: float = par.x + cos(ca) * refl[r]["d"]
						var hy: float = par.y + sin(ca) * refl[r]["d"]
						var ox: float = hx - cos(ca) * 0.08
						var oy: float = hy - sin(ca) * 0.08
						var bm := 1.0
						if par.vbeam.size() > 0:
							var bi: int = int(floor((ca / TWO_PI) * par.vbeam.size() + 0.5))
							if bi >= par.vbeam.size():
								bi -= par.vbeam.size()
							bm = par.vbeam[bi]
						var child := make_pulse(world, ox, oy, par.t0 + refl[r]["d"] / par.speed, cr, par.speed, par.strength * 0.45 * bm, kind, gen, 180, par.z, par.fade * 0.8)
						child.mat = MATS[par.vmat[ray_index(par, ca)]]
						made.append(child)
						nxt.append(child)
					r += 1
				li += 1
			layer = nxt
			gen += 1
	for p in made:
		pulses.append(p)
	if pulses.size() > max_pulses:
		if protect_last and last_pulse != null and pulses.has(last_pulse):
			var drop: int = pulses.size() - max_pulses
			var kept: Array[Pulse] = []
			for p in pulses:
				if drop > 0 and p != last_pulse:
					drop -= 1
				else:
					kept.append(p)
			pulses = kept
		else:
			pulses = pulses.slice(pulses.size() - max_pulses)
	return primary


## Ports emit (js/sonar.js:176): the click ping; false while cooling down.
func emit(world, x: float, y: float, t: float, opts: Dictionary = {}) -> bool:
	if t - last_emit < cooldown:
		return false
	var o := {"kind": "ping", "range": range_, "strength": 1.0, "bounces": bounces, "visRays": vis_rays}
	for k in ["z", "fade", "facing"]:
		if opts.get(k) is float or opts.get(k) is int:
			o[k] = opts[k]
	var pulse := emit_sound(world, x, y, t, o)
	if pulse == null:
		return false
	last_emit = t
	last_pulse = pulse
	return true


static func nearest_dist(pulse: Pulse) -> float:
	var m := INF
	for d in pulse.vis:
		if d < m:
			m = d
	return m


## Ports scan (js/sonar.js:204): best brightness at (px, py, pz); age/fade/index land in scan_*.
func scan(px: float, py: float, pz: float, t: float) -> float:
	var best := 0.0
	scan_age = -1.0
	scan_fade = 0.0
	scan_idx = -1
	for i in pulses.size():
		var p: Pulse = pulses[i]
		var dx: float = px - p.x
		var dy: float = py - p.y
		var dh2: float = dx * dx + dy * dy
		var dz: float = pz - p.z
		var d2: float = dh2 + dz * dz
		if d2 > p.range * p.range:
			continue
		var rr: float = (t - p.t0) * p.speed
		if rr < 0.0 or d2 > rr * rr:
			continue
		var d: float = sqrt(d2)
		var age: float = t - (p.t0 + d / p.speed)
		if age >= p.fade:
			continue
		var n: int = p.vis.size()
		var a: float = atan2(dy, dx)
		if a < 0.0:
			a += TWO_PI
		var idx: int = int(floor(a / TWO_PI * n + 0.5))
		if idx >= n:
			idx -= n
		if sqrt(dh2) > p.vis[idx] + TOL:
			continue
		var b: float = 1.0 - age / p.fade
		b = b * b * (1.0 - 0.5 * d / p.range)
		b *= p.strength
		if p.vbeam.size() > 0:
			b *= p.vbeam[idx]
		if b > best:
			best = b
			scan_age = age
			scan_fade = p.fade
			scan_idx = i
	return best


## Ports sample2 (js/sonar.js:263): returns [b0, b1, age, fade] for a wall point at floor (z=0) and ceiling (z=1).
func sample2(px: float, py: float, t: float) -> PackedFloat64Array:
	var b0 := 0.0
	var b1 := 0.0
	var a0 := -1.0
	var a1 := -1.0
	var f0 := 0.0
	var f1 := 0.0
	for p in pulses:
		var rr: float = (t - p.t0) * p.speed
		if rr < 0.0:
			continue
		var dx: float = px - p.x
		var dy: float = py - p.y
		var dh2: float = dx * dx + dy * dy
		var rg: float = p.range
		if dh2 > rg * rg or dh2 > rr * rr + 1.5:
			continue
		var n: int = p.vis.size()
		var a: float = atan2(dy, dx)
		if a < 0.0:
			a += TWO_PI
		var idx: int = int(floor(a / TWO_PI * n + 0.5))
		if idx >= n:
			idx -= n
		if sqrt(dh2) > p.vis[idx] + TOL:
			continue
		var mul: float = p.strength * (p.vbeam[idx] if p.vbeam.size() > 0 else 1.0)
		for e in 2:
			var dz: float = e - p.z
			var d2: float = dh2 + dz * dz
			if d2 > rg * rg or d2 > rr * rr:
				continue
			var d: float = sqrt(d2)
			var age: float = t - (p.t0 + d / p.speed)
			if age >= p.fade:
				continue
			var b: float = 1.0 - age / p.fade
			b = b * b * (1.0 - 0.5 * d / rg) * mul
			if e == 0:
				if b > b0:
					b0 = b
					a0 = age
					f0 = p.fade
			elif b > b1:
				b1 = b
				a1 = age
				f1 = p.fade
	var lit: bool = b0 > 0.0 or b1 > 0.0
	var use_lo: bool = b0 >= b1
	return PackedFloat64Array([b0, b1, (a0 if use_lo else a1) if lit else -1.0, (f0 if use_lo else f1) if lit else 0.0])


## Brightness at eye height 0.5 (js brightnessAt).
func brightness_at(px: float, py: float, t: float) -> float:
	return scan(px, py, 0.5, t)


## Age since the wavefront arrived at (px, py, 0.5), -1 if unlit (js ageAt).
func age_at(px: float, py: float, t: float) -> float:
	return scan_age if scan(px, py, 0.5, t) > 0.0 else -1.0


## Ports heightBand: [zLow, zHigh] lit on the vertical line at (px, py), or empty when not reached.
static func height_band(pulse: Pulse, t: float, px: float, py: float) -> PackedFloat64Array:
	var dx: float = px - pulse.x
	var dy: float = py - pulse.y
	var dh2: float = dx * dx + dy * dy
	var r: float = (t - pulse.t0) * pulse.speed
	if r > pulse.range:
		r = pulse.range
	if r > 0.0 and r * r > dh2:
		var dz: float = sqrt(r * r - dh2)
		var lo: float = pulse.z - dz
		var hi: float = pulse.z + dz
		return PackedFloat64Array([0.0 if lo < 0.0 else lo, 1.2 if hi > 1.2 else hi])
	return PackedFloat64Array()


static func visible_from(pulse: Pulse, x: float, y: float) -> bool:
	if pulse.vis.is_empty():
		return true
	var dx: float = x - pulse.x
	var dy: float = y - pulse.y
	var d: float = sqrt(dx * dx + dy * dy)
	var a: float = atan2(dy, dx)
	if a < 0.0:
		a += TWO_PI
	var n: int = pulse.vis.size()
	var idx: int = int(floor(a / TWO_PI * n + 0.5))
	if idx >= n:
		idx -= n
	return d <= pulse.vis[idx] + TOL


static func lit_at(pulse: Pulse, x: float, y: float) -> float:
	var dx: float = x - pulse.x
	var dy: float = y - pulse.y
	return pulse.t0 + sqrt(dx * dx + dy * dy) / pulse.speed


static func ring_radius(pulse: Pulse, t: float) -> float:
	return (t - pulse.t0) * pulse.speed


## Remove pulses that have fully faded (js prune).
func prune(t: float) -> void:
	var keep: Array[Pulse] = []
	for p in pulses:
		if t - p.t0 <= p.range / p.speed + p.fade:
			keep.append(p)
	pulses = keep


static func echo_delay(d: float, spd: float = SONAR_SPEED) -> float:
	var v: float = spd if spd > 0.0 else SONAR_SPEED
	return (2.0 * d) / v


static func beam_at(pulse: Pulse, ang: float) -> float:
	return pulse.vbeam[ray_index(pulse, ang)] if pulse.vbeam.size() > 0 else 1.0


## Surface hit along world angle `ang` (nearest ray) for visuals and audio (js hitInfo):
## {hit, dist, mat, rough, nx, ny, cosInc, beam}.
static func hit_info(pulse: Pulse, ang: float) -> Dictionary:
	var i: int = ray_index(pulse, ang)
	var d: float = pulse.vis[i]
	var code: int = pulse.vnorm[i] if pulse.vnorm.size() > 0 else NO_HIT
	var hit: bool = code != NO_HIT
	var mat: String = MATS[pulse.vmat[i]] if hit else ""
	var nx: float = 1.0 if code == 0 else (-1.0 if code == 1 else 0.0)
	var ny: float = 1.0 if code == 2 else (-1.0 if code == 3 else 0.0)
	var ra: float = (float(i) / pulse.vis.size()) * TWO_PI
	return {
		"hit": hit, "dist": d, "mat": mat, "rough": Acoustics.rough_of(mat) if hit else 0.0, "nx": nx, "ny": ny,
		"cosInc": maxf(0.0, -(cos(ra) * nx + sin(ra) * ny)) if hit else 0.0,
		"beam": pulse.vbeam[i] if pulse.vbeam.size() > 0 else 1.0,
	}


## The loudest wall return of a pulse heard from its origin (js strongestEcho): {dist, angle, theta, mat, rough, level, cosInc}
## or an empty Dictionary when no wall is in range. facing defaults to the pulse facing.
static func strongest_echo(pulse: Pulse, facing: float = NAN) -> Dictionary:
	if pulse == null or pulse.vis.is_empty():
		return {}
	var f: float = facing if not is_nan(facing) else (pulse.facing if pulse.has_facing else 0.0)
	var n: int = pulse.vis.size()
	Acoustics.wall_echo_init()
	var vis: PackedFloat32Array = pulse.vis
	var vnorm: PackedByteArray = pulse.vnorm
	var vmat: PackedByteArray = pulse.vmat
	var tr: Array = _trig_for(n)
	var cs: PackedFloat64Array = tr[0]
	var sn: PackedFloat64Array = tr[1]
	var lim: float = pulse.range - 1e-4
	var have: bool = false
	var best_level: float = 0.0
	var best_i: int = 0
	var best_cos: float = 0.0
	var best_theta: float = 0.0
	var ln10: float = log(10.0)
	for i in n:
		var d: float = vis[i]
		if not (d > 0.0) or d >= lim:
			continue
		# hit_info(pulse, angle) with ray_index(angle) == i: code, material and incidence cosine of ray i.
		var code: int = vnorm[i] if vnorm.size() > 0 else NO_HIT
		if code == NO_HIT:
			continue
		var nx: float = 1.0 if code == 0 else (-1.0 if code == 1 else 0.0)
		var ny: float = 1.0 if code == 2 else (-1.0 if code == 3 else 0.0)
		var cos_inc: float = maxf(0.0, -(cs[i] * nx + sn[i] * ny))
		var angle: float = (float(i) / n) * TWO_PI
		var theta: float = angle - f
		var level: float = Acoustics.wall_echo_level(d, theta, vmat[i]) + 20.0 * log(maxf(cos_inc, 0.25)) / ln10
		if not have or level > best_level:
			have = true
			best_level = level
			best_i = i
			best_cos = cos_inc
			best_theta = theta
	if not have:
		return {}
	var mat: String = MATS[vmat[best_i]]
	return {"dist": vis[best_i], "angle": (float(best_i) / n) * TWO_PI, "theta": best_theta, "mat": mat, "rough": Acoustics.rough_of(mat), "level": best_level, "cosInc": best_cos}


## Enclosure of a pulse as heard from its origin (js enclosure): {hitFrac, meanAlpha}.
static func enclosure(pulse: Pulse) -> Dictionary:
	if pulse == null or pulse.vis.is_empty():
		return {"hitFrac": 0.0, "meanAlpha": 0.0}
	var n: int = pulse.vis.size()
	var hits := 0
	var alpha := 0.0
	for i in n:
		var d: float = pulse.vis[i]
		if not (d > 0.0) or d >= pulse.range - 1e-4:
			continue
		if pulse.vnorm.size() > 0 and pulse.vnorm[i] == NO_HIT:
			continue
		hits += 1
		if pulse.vmat.size() > 0:
			alpha += float(Acoustics.mat_of(MATS[pulse.vmat[i]])["alpha"])
	return {"hitFrac": float(hits) / n, "meanAlpha": alpha / hits if hits > 0 else 0.0}


## Water-ripple arcs on a wall point (js wallArc): for k in 0..trail-1 the ring radius is ring - k*0.35; returns an Array of
## trail entries, each [zLow, zHigh] or empty when the ring has not reached the face.
static func wall_arc(pulse: Pulse, t: float, hit_x: float, hit_y: float, trail: int) -> Array:
	var dx: float = hit_x - pulse.x
	var dy: float = hit_y - pulse.y
	var dh2: float = dx * dx + dy * dy
	var ring: float = (t - pulse.t0) * pulse.speed
	var out: Array = []
	for k in trail:
		var r: float = ring - k * 0.35
		if r * r > dh2 and r > 0.0:
			var dz: float = sqrt(r * r - dh2)
			var lo: float = pulse.z - dz
			var hi: float = pulse.z + dz
			out.append([0.0 if lo < 0.0 else lo, 1.0 if hi > 1.0 else hi])
		else:
			out.append([])
	return out
