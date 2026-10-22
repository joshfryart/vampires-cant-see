class_name FigureVolDraw
extends RefCounted
## Ports the drawing half of js/figure.js: Figure.draw (contact shadow, sorted body parts with occlusion fill, contour, wrap lines,
## shade and rim), the line-figure details redrawn on top (face, hair, hats, hem, scarf, props, fingers...), drawExtras (outfits,
## role hats and items) and drawGrabArmsVol. Geometry lives in figure_vol.gd; every call goes through the Canvas abstraction so
## the draw log can be hashed against the JS.

const TWO_PI := TAU
const PI_ := PI

## Options for one figure (js o): fx effects level, lw line width, alpha, rim light {side, k}, depth, reduced motion.
class Opts:
	extends RefCounted
	var fx: int = 0
	var lw: float = 1.0
	var alpha: float = 1.0
	var rim_side: float = 1.0
	var rim_k: float = 0.0
	var depth: float = 0.0
	var reduced: bool = false
	var sa: float = 1.0
	var style: String = "#ffffff"


static var HID := PackedByteArray()
static var _hat_x: float = 0.0
static var _hat_y: float = 0.0
static var _hat_tilt: float = 0.0
static var _fp_x: float = 0.0
static var _fp_y: float = 0.0
static var _fp_d: float = 0.0
static var draw_n: int = 0
static var ex_gx: float = 0.0
static var ex_gy: float = 0.0
static var ex_tx: float = 0.0
static var ex_ty: float = 0.0


static func _face(o: Dictionary) -> Dictionary:
	var d := {"ew": 1.0, "eh": 1.0, "gap": 1.0, "ev": 0.0, "bl": 0.0, "bt": 0.0, "bw": 1.0, "heavy": 0.0, "nose": 0.0, "mw": 1.0, "mc": 0.0, "lop": 0.0, "lid": 0.0, "bag": 0.0, "wr": 0.0, "ck": 0.0, "lash": 0.0, "rb": 0.0}
	for k in o:
		d[k] = float(o[k])
	return d


static var FACE_DEF: Dictionary
static var FACE: Dictionary


static func _init_faces() -> void:
	if not FACE.is_empty():
		return
	FACE_DEF = _face({})
	FACE = {
		"patron": _face({"mc": 0.01}),
		"innkeeper": _face({"nose": 1, "mw": 1.3, "mc": 0.035, "ck": 1, "ew": 0.9}),
		"drunk": _face({"lid": 1, "nose": 3, "lop": 1, "mw": 1.15, "mc": 0.02, "ck": 1, "bl": 0.03}),
		"regular": _face({"nose": 4, "mw": 0.9, "ev": 0.02, "bt": -0.02}),
		"priest": _face({"bl": -0.05, "bw": 1.15, "nose": 4, "mw": 0.7, "mc": -0.04, "ew": 0.9, "eh": 0.85, "bt": -0.04}),
		"elder": _face({"ew": 0.78, "eh": 0.8, "bt": -0.06, "nose": 2, "mw": 0.85, "mc": -0.065, "wr": 1, "bag": 1}),
		"farmer": _face({"nose": 3, "mw": 1.3, "mc": 0.04, "ck": 1, "gap": 1.06, "heavy": 1}),
		"mother": _face({"lash": 1, "bl": -0.04, "mc": 0.03, "bt": -0.03, "nose": 1, "gap": 0.96}),
		"insomniac": _face({"ew": 1.18, "eh": 1.25, "bag": 1, "bl": -0.05, "mc": -0.06, "mw": 0.8}),
		"gravedigger": _face({"bag": 1, "nose": 4, "mc": -0.085, "mw": 0.85, "bl": 0.04, "heavy": 1, "eh": 0.85}),
		"guard": _face({"heavy": 1, "bl": 0.05, "bt": 0.05, "mc": -0.05, "mw": 1.1, "eh": 0.8, "gap": 1.05}),
		"child": _face({"nose": 1, "ck": 1, "mc": 0.03, "ew": 1.05, "eh": 1.1}),
		"merchant": _face({"rb": 1, "lop": 1, "nose": 4, "mw": 1.05, "mc": 0.02, "eh": 0.9}),
		"hunter": _face({"eh": 0.68, "heavy": 1, "bt": 0.07, "bl": 0.03, "nose": 2, "mc": -0.04, "mw": 0.9}),
	}


## Mood from the pose: 0 calm, 1 wide-eyed (startle, flee, held), 2 squeezed (cower), 3 closed (fed), 4 wary.
static func mood(p: Pose) -> int:
	var md: String = p.mode
	if md == "fed":
		return 3
	if md == "cower":
		return 2
	if md == "startle" or md == "flee" or md == "grapple" or p.flee:
		return 1
	if md == "wary":
		return 4
	return 0


static func lerp_(a: float, b: float, t: float) -> float:
	return a + (b - a) * t


static func _sgn(v: float) -> float:
	return -1.0 if v < 0.0 else 1.0


# ---------------------------------------------------------------- outline helpers

## Smooth closed outline of part p: quadratic segments through its points, joining edge midpoints.
static func emit_poly(c: Canvas, p: FigureVol.Part) -> void:
	var n: int = p.n
	if n < 3:
		return
	var px := p.px
	var py := p.py
	c.move_to((px[n - 1] + px[0]) * 0.5, (py[n - 1] + py[0]) * 0.5)
	for i in n:
		var j: int = 0 if i == n - 1 else i + 1
		c.quad_to(px[i], py[i], (px[i] + px[j]) * 0.5, (py[i] + py[j]) * 0.5)
	c.close_path()


## Limb roots: mark (HID) the outline points of an arm or leg near its root that lie inside the torso hull. Returns the count.
static func mask_root(p: FigureVol.Part, torso: FigureVol.Part) -> int:
	var n: int = p.n
	var K: int = p.ns
	if HID.size() < FigureVol.MAXPTS:
		HID.resize(FigureVol.MAXPTS)
	for i in n:
		HID[i] = 0
	if torso == null or not (K > 1) or n != 2 * K + 8:
		return 0
	var rs: int = int(ceil(K * 0.4))
	var hid := 0
	for i in n:
		var root: bool = i <= rs or i >= 2 * K + 4 - rs
		if root and FigureVol.contains(torso, p.px[i], p.py[i]):
			HID[i] = 1
			hid += 1
	return hid


## Torso hull: mark (HID) its lower points (outline points 8..14) that lie inside a leg drawn over it. Returns the count.
static func mask_pelvis(p: FigureVol.Part, l0: FigureVol.Part, l1: FigureVol.Part) -> int:
	var n: int = p.n
	if HID.size() < FigureVol.MAXPTS:
		HID.resize(FigureVol.MAXPTS)
	for i in n:
		HID[i] = 0
	if n != 2 * FigureVol.NT + 2 or (l0 == null and l1 == null):
		return 0
	var hid := 0
	for i in range(8, 15):
		var x: float = p.px[i]
		var y: float = p.py[i]
		if (l0 != null and FigureVol.contains(l0, x, y)) or (l1 != null and FigureVol.contains(l1, x, y)):
			HID[i] = 1
			hid += 1
	return hid


## Open outline of p through the points not marked in HID (same curve as emit_poly).
static func emit_masked(c: Canvas, p: FigureVol.Part) -> void:
	var n: int = p.n
	var px := p.px
	var py := p.py
	var pen := false
	for i in n:
		if HID[i] != 0:
			pen = false
			continue
		var a: int = n - 1 if i == 0 else i - 1
		var b: int = 0 if i == n - 1 else i + 1
		if not pen:
			c.move_to((px[a] + px[i]) * 0.5, (py[a] + py[i]) * 0.5)
			pen = true
		c.quad_to(px[i], py[i], (px[i] + px[b]) * 0.5, (py[i] + py[b]) * 0.5)


## Rim: the runs of the outline whose outward normal faces the light side (+1 = screen right), tops not bottoms.
static func rim_part(c: Canvas, p: FigureVol.Part, side: float, masked: bool) -> void:
	var n: int = p.n
	if n < 3:
		return
	var px := p.px
	var py := p.py
	var area := 0.0
	for i in n:
		var j: int = 0 if i == n - 1 else i + 1
		area += px[i] * py[j] - px[j] * py[i]
	var o: float = 1.0 if area > 0.0 else -1.0
	var pen := false
	for i in n:
		var a: int = n - 1 if i == 0 else i - 1
		var b: int = 0 if i == n - 1 else i + 1
		var tx: float = px[b] - px[a]
		var ty: float = py[b] - py[a]
		var L: float = sqrt(tx * tx + ty * ty) + 1e-9
		var nx: float = ty / L * o
		var ny: float = -tx / L * o
		var lit: bool = nx * side > 0.3 and ny < 0.75 and not (masked and HID[i] != 0)
		if lit:
			if not pen:
				c.move_to((px[a] + px[i]) * 0.5, (py[a] + py[i]) * 0.5)
				pen = true
			c.quad_to(px[i], py[i], (px[i] + px[b]) * 0.5, (py[i] + py[b]) * 0.5)
		else:
			pen = false


static func wrap_ring(c: Canvas, p: FigureVol.Part, q: int, minor_k: float) -> void:
	var r: float = p.wr[q]
	var ang: float = p.wa[q]
	var cx: float = p.wx[q]
	var cy: float = p.wy[q]
	c.move_to(cx + r * cos(ang + PI * 0.5), cy + r * sin(ang + PI * 0.5))
	c.ellipse(cx, cy, maxf(0.01, r), maxf(0.01, r * minor_k), ang + PI * 0.5, 0.0, PI, true)


## Sleeve / trouser cuff ring on this limb (not under robes or cloaks, not on mail sleeves).
static func cuff_ok(p: FigureVol.Part, look: Dictionary, robe: bool) -> bool:
	var k: String = p.kind
	var outfit: Variant = look.get("outfit")
	return (k == "leg" or k == "arm") and p.nw > 2 and not robe and outfit != "cloak" and not (k == "arm" and outfit == "mail")


## Cloth creases fanning up from the belt line.
static func torso_folds(c: Canvas, p: FigureVol.Part, m: FigureVol.Meas, lw: float, alpha: float) -> void:
	var ax: float = p.bx - p.ax
	var ay: float = p.by - p.ay
	var L: float = sqrt(ax * ax + ay * ay)
	if L < 8.0:
		return
	var ux: float = ax / L
	var uy: float = ay / L
	var dx: float = m.beltX1 - m.beltX0
	var dy: float = m.beltY1 - m.beltY0
	var bw: float = sqrt(dx * dx + dy * dy)
	if bw < 4.0:
		return
	c.global_alpha = alpha * 0.45
	c.line_width = lw * 0.7
	c.begin_path()
	for i in 3:
		var f: float = 0.28 + i * 0.22
		var sx: float = m.beltX0 + dx * f
		var sy: float = m.beltY0 + dy * f
		var sgn: float = -1.0 if i == 0 else (1.0 if i == 2 else 0.0)
		var ln: float = L * (0.2 + 0.05 * (i % 2))
		var ex: float = sx - ux * ln + dx * sgn * 0.08
		var ey: float = sy - uy * ln + dy * sgn * 0.08
		var bow: float = bw * 0.06 * (1.0 if i == 1 else -sgn)
		c.move_to(sx, sy)
		c.quad_to((sx + ex) * 0.5 - uy * bow, (sy + ey) * 0.5 + ux * bow, ex, ey)
	c.stroke()
	c.line_width = lw
	c.global_alpha = alpha


## Hem height on screen for the robe / apron / smock / cloak, from look.hem (0 waist .. 1 ankle).
static func hem_y(m: FigureVol.Meas, look: Dictionary, dflt: float) -> float:
	var hem: float = clampf(FigureVol.num(look.get("hem"), dflt), 0.0, 1.0)
	var hip_u: float = m.hipU
	var u: float = lerp_(hip_u - 0.17 * m.lh, 0.04 * m.lh, hem)
	return m.hy + (hip_u - u) * m.vsy


## Where a hat sits: on the head, or on the floor beside a fed villager.
static func set_hat(p: Pose, mode: String, hat: String, tilt: float, m: FigureVol.Meas) -> void:
	var X := p.X
	var Y := p.Y
	var fed: bool = mode == "fed" and hat != "hood"
	if fed:
		_hat_x = X[9] + m.hr * 2.6
		_hat_y = maxf(Y[8], Y[9]) - m.hry * 0.35
		_hat_tilt = 0.9
	else:
		_hat_x = X[0]
		_hat_y = Y[0]
		_hat_tilt = FigureVol.num(tilt, 0.0)


# ---------------------------------------------------------------- draw

## Draw one figure. sa = strip alpha, style = stroke colour, p = the posed Pose, look = its look dict, o = Opts.
static func draw(c: Canvas, sa_in: float, style: String, p: Pose, look: Dictionary, o: Opts) -> bool:
	FigureVol._init_tables()
	var X := p.X
	var Y := p.Y
	if X.size() < 24 or Y.size() < 24:
		return false
	var sa: float = FigureVol.num(sa_in, 1.0)
	var fx: int = 2 if o.fx >= 2 else (1 if o.fx >= 1 else 0)
	var lw: float = maxf(0.5, FigureVol.num(o.lw, 1.0))
	var alpha: float = clampf(FigureVol.num(o.alpha, 1.0) * sa, 0.0, 1.0)
	var depth: float = o.depth
	var near: bool = depth < 6.0
	var rim_k: float = o.rim_k
	var rim_side: float = -1.0 if o.rim_side < 0.0 else 1.0
	var lod: int = p.lod
	var cut: float = p.min_x
	var cut_w: float = p.max_x - cut

	var pool: Array = FigureVol.POOL
	var n: int = FigureVol.parts(X, Y, p.Z, p, look, pool)
	draw_n = n
	var m: FigureVol.Meas = FigureVol.M
	var outfit: Variant = look.get("outfit")
	var robe: bool = outfit == "robe"
	var robe_y: float = hem_y(m, look, 1.0) if robe else 0.0

	c.save()
	c.line_join = "round"
	c.line_cap = "round"
	c.stroke_style = style

	# Contact shadow.
	var fxm: float = (X[8] + X[9]) * 0.5
	var fym: float = maxf(Y[8], Y[9]) + maxf(0.5, m.vs * 0.004)
	var srx: float = maxf(1.0, 0.12 * m.hs * m.bw)
	var sry: float = maxf(0.4, srx * 0.18)
	if fx >= 2 and near:
		c.global_alpha = 0.4 * sa
		c.fill_style = FigureVol.BLACK
		c.begin_path()
		FigureVol.ell(c, fxm, fym, srx, sry, 0.0)
		c.fill()
	c.global_alpha = clampf(0.2 * sa, 0.0, 1.0)
	c.line_width = lw
	c.begin_path()
	c.move_to(fxm - srx, fym)
	c.ellipse(fxm, fym, srx, sry, 0.0, PI, TWO_PI, true)
	c.stroke()

	FigureVol.sort_back_to_front(pool, n)
	var torso_p: FigureVol.Part = null
	var leg_a: FigureVol.Part = null
	var leg_b: FigureVol.Part = null
	for i in n:
		var q: FigureVol.Part = pool[i]
		if q.kind == "torso":
			torso_p = q
		elif q.kind == "leg" and torso_p != null:
			if leg_a != null:
				leg_b = q
			else:
				leg_a = q
	var sy: float = p.nose_x
	var minor_k: float = 0.15 + 0.35 * minf(1.0, absf(sy))
	for i in n:
		var q: FigureVol.Part = pool[i]
		var leg: bool = q.kind == "leg"
		var clipped := false
		if robe and leg:
			# Legs show below the hem only.
			if q.y1 <= robe_y:
				continue
			if q.y0 < robe_y:
				c.save()
				c.begin_path()
				c.rect(cut, robe_y, cut_w, 1e5)
				c.clip()
				clipped = true
		var masked := false
		if fx >= 1 and near:
			if leg or q.kind == "arm":
				masked = mask_root(q, torso_p) > 0
			elif q == torso_p and not robe:
				masked = mask_pelvis(q, leg_a, leg_b) > 0
		c.begin_path()
		emit_poly(c, q)
		if fx >= 2 and near and q.kind != "extra":
			c.global_alpha = minf(1.0, 0.55 * sa)
			c.fill_style = FigureVol.BLACK
			c.fill()
		if masked:
			c.begin_path()
			emit_masked(c, q)
		c.global_alpha = alpha
		c.stroke_style = style
		c.line_width = lw
		if fx >= 1 and near and q.nw > 0 and (q.kind == "torso" or leg or q.kind == "arm"):
			# fx 1: one ring per torso, leg and arm (upper half); fx 2: also the lower half of each limb.
			var dx: float = q.bx - q.ax
			var dy: float = q.by - q.ay
			if dx * dx + dy * dy > q.r0 * q.r0 * 2.0:
				wrap_ring(c, q, 0, minor_k)
				# The lower ring sits right above the cuff; only draw it where no cuff follows.
				if fx >= 2 and q.nw > 1 and not (lod >= 1 and cuff_ok(q, look, robe)):
					wrap_ring(c, q, 1, minor_k)
		c.stroke()
		if fx >= 1 and near and q.kind != "extra" and q.kind != "head":
			# Shade side: a heavier contour on the side away from the light gives the flat outline some roundness.
			c.global_alpha = clampf(0.55 * alpha, 0.0, 1.0)
			c.line_width = lw * 1.9
			c.begin_path()
			rim_part(c, q, -rim_side, masked)
			c.stroke()
			c.line_width = lw
			c.global_alpha = alpha
		if lod >= 1 and fx >= 1 and near:
			if cuff_ok(q, look, robe):
				c.global_alpha = alpha * 0.8
				c.line_width = lw * 0.9
				c.begin_path()
				wrap_ring(c, q, 2, minor_k)
				c.stroke()
				c.line_width = lw
				c.global_alpha = alpha
			elif q.kind == "torso" and lod >= 2 and m.belt != 0.0 and outfit != "robe" and outfit != "cloak":
				torso_folds(c, q, m, lw, alpha)
		if rim_k > 0.02 and near:
			c.global_alpha = clampf(0.5 * rim_k * sa, 0.0, 1.0)
			c.stroke_style = FigureVol.COL_RIM
			c.line_width = lw * 0.8
			c.begin_path()
			rim_part(c, q, rim_side, masked)
			c.stroke()
			c.stroke_style = style
		if clipped:
			c.restore()

	# Details redrawn in the line figure's style.
	c.global_alpha = alpha
	c.stroke_style = style
	c.line_width = lw
	c.begin_path()
	details(c, p, look, m, lod, lw)
	c.stroke()
	if p.stars:
		c.begin_path()
		var hr: float = m.hr
		var hry: float = m.hry
		var rr: float = maxf(1.2, hr * 0.13)
		var tn: float = 0.0 if o.reduced else FigureVol.num(p.t_n, 0.0)
		var pid: float = p.pid
		for k in 3:
			var a: float = tn * 2.5 + k * 2.094 + pid
			var sx2: float = X[23] + cos(a) * hr * 1.7
			var sy2: float = Y[23] - hry * 0.25 + sin(a) * hry * 0.35
			c.move_to(sx2 - rr, sy2)
			c.line_to(sx2 + rr, sy2)
			c.move_to(sx2, sy2 - rr)
			c.line_to(sx2, sy2 + rr)
		c.stroke()
	c.restore()
	return true


# ---------------------------------------------------------------- face

## Screen point of a head-surface feature (lateral l, forward f, down v; unit head) into _fp_x/_fp_y/_fp_d; d < 0 faces us.
static func face_pt(hx: float, hy: float, rx: float, ry: float, sY: float, cY: float, rot: float, l: float, f: float, v: float) -> void:
	var lx: float = (l * cY + f * sY) * rx
	var ly: float = v * ry
	var cR: float = cos(rot)
	var sR: float = sin(rot)
	_fp_x = hx + lx * cR - ly * sR
	_fp_y = hy + lx * sR + ly * cR
	_fp_d = f * cY - l * sY


## Face, hair, hats, hem, seat edge, scarf, props, fingers, belt, clavicles and ears, as subpaths of the current path.
static func details(c: Canvas, p: Pose, look: Dictionary, m: FigureVol.Meas, lod: int, lw: float) -> void:
	_init_faces()
	var X := p.X
	var Y := p.Y
	var hs: float = m.hs
	var vs: float = m.vs
	var lh: float = m.lh
	var hr: float = m.hr
	var hry: float = m.hry
	var hx: float = X[0]
	var hy: float = Y[0]
	var bx: float = X[14]
	var by: float = Y[14]
	var body_rx: float = m.bodyRx
	var body_ry: float = m.bodyRy
	var mode: String = p.mode
	var noseX: float = clampf(FigureVol.num(p.nose_x, 0.0), -1.0, 1.0)
	var face_vis: bool = p.face_vis
	var eyes_vis: bool = p.eyes_vis
	var flee: bool = p.flee or mode == "flee"
	var moving: bool = p.moving
	var jump: float = FigureVol.num(p.jump, 0.0)
	var role_hat: String = str(look.get("roleHat")) if (look.get("roleHat") != null and look.get("roleHat") != "none") else ""
	var acc: Variant = look.get("acc")
	var hat: String = "none" if role_hat != "" else p.hat
	var prop: String = p.prop
	var outfit: Variant = look.get("outfit")
	var kid: float = m.kid
	var rot: float = FigureVol.num(p.tilt, 0.0) * 0.6
	var hrx: float = hr * 0.9
	var cY: float = p.cos_yaw
	var md: int = mood(p)
	var arch: Variant = look.get("archetype")
	var F: Dictionary = FACE[arch] if (arch is String and FACE.has(arch)) else FACE_DEF
	# Per-person asymmetry (-1..1): one eye a touch higher, one brow lower, the mouth off centre.
	var asy: float = float(posmod(int(floor(float(p.pid))) * 53 % 9 + 9, 9) - 4) / 4.0
	var hair: Variant = look.get("hair") if (hat == "none" or hat == "cap" or hat == "bonnet") else "none"
	var beard: bool = bool(look.get("beard"))
	var tau := TWO_PI

	# ---- Ears (hidden by a hood, bonnet or bob) ----
	if lod >= 1 and hat != "hood" and hat != "bonnet" and hair != "bob":
		for side in [-1.0, 1.0]:
			face_pt(hx, hy, hrx, hry, noseX, cY, rot, side * 0.97, -0.1, 0.08)
			if _fp_d > 0.3:
				continue
			var ex: float = _fp_x
			var ey: float = _fp_y
			var ew: float = maxf(0.8, hr * 0.13 * (0.35 + 0.65 * absf(noseX)))
			var eh: float = maxf(1.0, hry * 0.22)
			var off: float = ex - hx
			var opn: float = (-1.0 if off > 0.0 else 1.0) if absf(off) > hrx * 0.45 else (1.0 if noseX >= 0.0 else -1.0)
			var a0: float = PI * 0.5 if opn > 0.0 else -PI * 0.5
			var cR: float = cos(rot)
			var sR: float = sin(rot)
			var qx: float = ew * cos(a0)
			var qy: float = eh * sin(a0)
			c.move_to(ex + qx * cR - qy * sR, ey + qx * sR + qy * cR)
			c.ellipse(ex, ey, ew, eh, rot, a0, a0 + PI)
			if lod >= 2 and absf(noseX) > 0.4:
				c.move_to(ex - opn * ew * 0.45, ey - eh * 0.35)
				c.quad_to(ex + opn * ew * 0.1, ey, ex - opn * ew * 0.3, ey + eh * 0.4)

	if lod >= 1 and face_vis:
		var nk: int = int(F["nose"])
		var nose_look: float = float(look["nose"]) if (look.get("nose") is float or look.get("nose") is int) else 1.0
		var nz: float = nose_look * (1.0 - 0.4 * kid) * (1.3 if nk == 4 else (0.6 if nk == 1 else 1.0))
		# Nose: bridge, tip (sticks out past the outline in profile), base, plus nostril wings seen head-on.
		face_pt(hx, hy, hrx, hry, noseX, cY, rot, 0.0, 0.96, 0.0)
		c.move_to(_fp_x, _fp_y)
		if nk == 2:
			face_pt(hx, hy, hrx, hry, noseX, cY, rot, 0.0, 1.0 + 0.3 * nz, 0.14 + 0.06 * nz)
			var qx2: float = _fp_x
			var qy2: float = _fp_y
			face_pt(hx, hy, hrx, hry, noseX, cY, rot, 0.0, 0.98 + 0.2 * nz, 0.36 + 0.08 * nz)
			c.quad_to(qx2, qy2, _fp_x, _fp_y)
		else:
			face_pt(hx, hy, hrx, hry, noseX, cY, rot, 0.0, 1.0 + 0.26 * nz, 0.24 + 0.1 * nz)
			c.line_to(_fp_x, _fp_y)
		var tip_x: float = _fp_x
		var tip_y: float = _fp_y
		face_pt(hx, hy, hrx, hry, noseX, cY, rot, 0.0, 0.93, 0.36 + 0.06 * nz)
		c.line_to(_fp_x, _fp_y)
		if lod >= 2 and (nk == 1 or nk == 3):
			var br: float = maxf(0.7, hr * (0.11 if nk == 3 else 0.065) * sqrt(nz))
			FigureVol.ell(c, tip_x - noseX * br * 0.3, tip_y - br * 0.2, br, br * 0.9, rot)
		if lod >= 2 and cY < -0.55:
			for side in [-1.0, 1.0]:
				face_pt(hx, hy, hrx, hry, noseX, cY, rot, side * 0.13 * nz, 0.92, 0.33 + 0.06 * nz)
				var wx: float = _fp_x
				var wy: float = _fp_y
				face_pt(hx, hy, hrx, hry, noseX, cY, rot, side * 0.05, 0.95, 0.4 + 0.06 * nz)
				c.move_to(wx, wy - hry * 0.05)
				c.quad_to(wx, _fp_y, _fp_x, _fp_y)
		if beard and lod >= 2:
			# Beard: a full jaw line from cheek to cheek round a rounded chin, plus a moustache under the nose.
			face_pt(hx, hy, hrx, hry, noseX, cY, rot, -0.8, 0.5, 0.3)
			c.move_to(_fp_x, _fp_y)
			face_pt(hx, hy, hrx, hry, noseX, cY, rot, -0.62, 0.72, 1.12)
			var qx0: float = _fp_x
			var qy0: float = _fp_y
			face_pt(hx, hy, hrx, hry, noseX, cY, rot, 0.0, 0.92, 1.2)
			c.quad_to(qx0, qy0, _fp_x, _fp_y)
			face_pt(hx, hy, hrx, hry, noseX, cY, rot, 0.62, 0.72, 1.12)
			var qx1: float = _fp_x
			var qy1: float = _fp_y
			face_pt(hx, hy, hrx, hry, noseX, cY, rot, 0.8, 0.5, 0.3)
			c.quad_to(qx1, qy1, _fp_x, _fp_y)
			if cY < -0.2:
				for side in [-1.0, 1.0]:
					# Moustache: each half sags under the nose and lifts at the tip.
					face_pt(hx, hy, hrx, hry, noseX, cY, rot, side * 0.03, 0.95, 0.43)
					c.move_to(_fp_x, _fp_y)
					face_pt(hx, hy, hrx, hry, noseX, cY, rot, side * 0.16, 0.9, 0.62)
					var mx: float = _fp_x
					var my: float = _fp_y
					face_pt(hx, hy, hrx, hry, noseX, cY, rot, side * 0.34, 0.82, 0.46)
					c.quad_to(mx, my, _fp_x, _fp_y)
		# Mouth (lod 2): a mood curve on the face, foreshortened with the yaw; width, smile and lopsidedness per face.
		if lod >= 2:
			var mv: float = 0.56 - 0.04 * kid
			var mw: float = 0.2 * F["mw"]
			var ms: float = asy * 0.035
			var lop: float = F["lop"] * (1.0 if asy >= 0.0 else -1.0) * 0.07
			face_pt(hx, hy, hrx, hry, noseX, cY, rot, -mw + ms, 0.86, mv + lop)
			var x0: float = _fp_x
			var y0: float = _fp_y
			var d0: float = _fp_d
			face_pt(hx, hy, hrx, hry, noseX, cY, rot, mw + ms, 0.86, mv - lop)
			var x1: float = _fp_x
			var y1: float = _fp_y
			var d1: float = _fp_d
			face_pt(hx, hy, hrx, hry, noseX, cY, rot, ms, 0.9, mv)
			var xm: float = _fp_x
			var ym: float = _fp_y
			if d0 < 0.15 or d1 < 0.15:
				var half: float = maxf(0.8, absf(x1 - x0) * 0.5)
				if md == 1 or md == 2:
					# Open, frightened.
					FigureVol.ell(c, xm, ym + hry * 0.02, maxf(0.8, half * 0.55), maxf(0.9, hry * 0.09), rot)
				elif not beard:
					if p.stars:
						c.move_to(x0, y0)
						c.quad_to(lerp_(x0, xm, 0.5), ym - hry * 0.06, xm, ym)
						c.quad_to(lerp_(xm, x1, 0.5), ym + hry * 0.06, x1, y1)
					else:
						var curve: float = (0.03 if md == 3 else (-0.03 if md == 4 else 0.05)) + F["mc"]
						c.move_to(x0, y0)
						c.quad_to(xm, ym + hry * curve * 2.0, x1, y1)
	if lod >= 1 and eyes_vis:
		for side in [-1.0, 1.0]:
			var ev: float = -0.06 + 0.12 * kid + F["ev"] + (0.025 if side > 0.0 else -0.025) * asy
			face_pt(hx, hy, hrx, hry, noseX, cY, rot, side * 0.36 * F["gap"], 0.88, ev)
			if _fp_d > -0.05:
				continue
			var ex: float = _fp_x
			var ey: float = _fp_y
			if lod < 2 or p.eyes_x:
				if p.eyes_x:
					var qq: float = maxf(1.2, hr * 0.14)
					c.move_to(ex - qq, ey - hry * 0.1)
					c.line_to(ex + qq, ey + hry * 0.1)
					c.move_to(ex + qq, ey - hry * 0.1)
					c.line_to(ex - qq, ey + hry * 0.1)
				else:
					c.move_to(ex, ey - hry * 0.09)
					c.line_to(ex, ey + hry * 0.09)
				continue
			var fore: float = clampf(-_fp_d, 0.3, 1.0)
			var ew: float = maxf(0.8, hr * 0.12 * (1.0 + 0.3 * kid) * fore * F["ew"])
			var eh: float = maxf(0.7, hry * 0.09 * (1.0 + 0.35 * kid) * (1.3 if md == 1 else 1.0) * F["eh"])
			# Toward the nose: +1 when the inner corner is to the right of this eye.
			face_pt(hx, hy, hrx, hry, noseX, cY, rot, 0.0, 0.9, ev)
			var inner_right: bool = _fp_x > ex
			var outer: float = -1.0 if inner_right else 1.0
			if md == 2:
				c.move_to(ex - ew, ey + eh * 0.2)
				c.quad_to(ex, ey - eh * 1.1, ex + ew, ey + eh * 0.2)
			elif md == 3:
				c.move_to(ex - ew, ey)
				c.quad_to(ex, ey + eh * 0.9, ex + ew, ey)
			else:
				FigureVol.ell(c, ex, ey, ew, eh, rot)
				var sleepy: bool = F["lid"] != 0.0 and md != 1
				var pr: float = maxf(0.45, eh * (0.32 if md == 1 else (0.34 if F["ew"] > 1.1 else 0.48)))
				var pdx: float = noseX * ew * 0.3
				var pdy: float = eh * 0.3 if sleepy else 0.0
				c.move_to(ex + pdx + pr, ey + pdy)
				c.arc(ex + pdx, ey + pdy, pr, 0.0, tau)
				if sleepy:
					# Heavy lid across the top half.
					c.move_to(ex - ew, ey - eh * 0.05)
					c.quad_to(ex, ey - eh * 0.35, ex + ew, ey - eh * 0.05)
				if F["lash"] != 0.0:
					c.move_to(ex + outer * ew * 0.85, ey - eh * 0.45)
					c.line_to(ex + outer * ew * 1.35, ey - eh * 0.95)
			if F["bag"] != 0.0:
				c.move_to(ex - ew * 0.85, ey + eh * 1.45)
				c.quad_to(ex, ey + eh * 2.2, ex + ew * 0.85, ey + eh * 1.45)
			if F["wr"] != 0.0:
				# Crow's feet at the outer corner.
				for k in [-1.0, 1.0]:
					var w0: float = maxf(ew * 1.6, hr * 0.17)
					c.move_to(ex + outer * w0, ey + k * eh * 0.2)
					c.line_to(ex + outer * (w0 + hr * 0.08), ey + k * eh * 0.85)
			# Brows: the inner end (toward the nose) drops when wary, rises when sad or scared; per-face lift and tilt.
			var raised: float = -0.09 if (F["rb"] != 0.0 and side * (1.0 if asy >= 0.0 else -1.0) > 0.0) else 0.0
			var lift: float = (-0.2 if md == 1 else (-0.04 if md == 3 else 0.0)) + F["bl"] + raised + (0.02 if side > 0.0 else -0.02) * asy
			var tilt_in: float = (0.09 if md == 4 else (-0.06 if md == 3 else (-0.04 if md == 1 else 0.02))) + F["bt"]
			face_pt(hx, hy, hrx, hry, noseX, cY, rot, side * 0.36 * F["gap"], 0.86, ev - 0.24 + lift)
			var bxm: float = _fp_x
			var bym: float = _fp_y
			var bwid: float = maxf(1.0, hr * 0.16 * fore * F["bw"])
			for q in int(F["heavy"]) + 1:
				var dq: float = q * hry * 0.045
				c.move_to(bxm - bwid, bym + dq + (0.0 if inner_right else hry * tilt_in))
				c.quad_to(bxm, bym + dq - hry * (0.05 - 0.02 * q), bxm + bwid, bym + dq + (hry * tilt_in if inner_right else 0.0))
		if lod >= 2 and cY < -0.35 and (F["ck"] != 0.0 or F["wr"] != 0.0):
			for side in [-1.0, 1.0]:
				if F["ck"] != 0.0:
					# Round cheeks: a short arc under each eye, toward the jaw.
					face_pt(hx, hy, hrx, hry, noseX, cY, rot, side * 0.55, 0.78, 0.22)
					if _fp_d < -0.1:
						var ccx: float = _fp_x
						var ccy: float = _fp_y
						c.move_to(ccx - hr * 0.09, ccy - hry * 0.06)
						c.quad_to(ccx, ccy + hry * 0.08, ccx + hr * 0.09, ccy - hry * 0.06)
			if F["wr"] != 0.0 and md != 1:
				# Forehead lines.
				for k in 2:
					face_pt(hx, hy, hrx, hry, noseX, cY, rot, -0.28, 0.8, -0.5 - k * 0.12)
					c.move_to(_fp_x, _fp_y)
					face_pt(hx, hy, hrx, hry, noseX, cY, rot, 0.0, 0.88, -0.56 - k * 0.12)
					var fmx: float = _fp_x
					var fmy: float = _fp_y
					face_pt(hx, hy, hrx, hry, noseX, cY, rot, 0.28, 0.8, -0.5 - k * 0.12)
					c.quad_to(fmx, fmy, _fp_x, _fp_y)
	# Hair (only when no hat hides it).
	if lod >= 1 and hair is String and hair != "" and hair != "none" and role_hat == "":
		var ty: float = hy - hry
		if hair == "tuft":
			for k in range(-1, 2):
				c.move_to(hx + k * hr * 0.3, ty + hry * 0.08)
				c.line_to(hx + k * hr * 0.45 + hr * 0.12, ty - hry * 0.28)
		elif hair == "bun":
			var bxr: float = hx - noseX * hr * 0.5
			var br2: float = maxf(1.5, hr * 0.32)
			c.move_to(bxr + br2, ty - hry * 0.05)
			c.arc(bxr, ty - hry * 0.05, br2, 0.0, tau)
		elif hair == "spiky":
			c.move_to(hx - hr * 0.85, ty + hry * 0.3)
			for k in 5:
				var u0: float = -0.85 + k * 0.42
				c.line_to(hx + (u0 + 0.21) * hr, ty - hry * 0.3)
				c.line_to(hx + (u0 + 0.42) * hr, ty + hry * 0.25)
		elif hair == "curls":
			for k in range(-1, 2):
				var cxr: float = hx + k * hr * 0.55
				var rr: float = maxf(1.3, hr * 0.26)
				c.move_to(cxr + rr, ty + hry * 0.05)
				c.arc(cxr, ty + hry * 0.05, rr, 0.0, tau)
		elif hair == "bob":
			c.move_to(hx - hr * 1.05, hy + hry * 0.5)
			c.quad_to(hx - hr * 1.15, ty - hry * 0.1, hx, ty - hry * 0.15)
			c.quad_to(hx + hr * 1.15, ty - hry * 0.1, hx + hr * 1.05, hy + hry * 0.5)
	# Hats (a fed villager's hat lies on the floor beside them).
	if hat != "none":
		set_hat(p, mode, hat, p.tilt, m)
		var hhx: float = _hat_x
		var hhy: float = _hat_y
		var hat_tilt: float = _hat_tilt
		if hat == "tophat":
			var hy2: float = hhy - hry * 0.78
			var bw2: float = hr * 1.25
			var th: float = vs * 0.14 * lh
			var lean2: float = hat_tilt * th * 1.2 + (-hr * 0.6 if flee else 0.0)
			var lift2: float = -th * 0.35 if flee else (-jump * vs * 0.8 if jump > 0.0 else 0.0)
			FigureVol.ell(c, hhx, hy2 + lift2, bw2, maxf(1.2, vs * 0.012), 0.0)
			c.move_to(hhx - hr * 0.78, hy2 + lift2)
			c.line_to(hhx - hr * 0.7 + lean2, hy2 - th + lift2)
			c.line_to(hhx + hr * 0.7 + lean2, hy2 - th + lift2)
			c.line_to(hhx + hr * 0.78, hy2 + lift2)
			c.move_to(hhx - hr * 0.77 + lean2 * 0.2, hy2 - th * 0.22 + lift2)
			c.line_to(hhx + hr * 0.77 + lean2 * 0.2, hy2 - th * 0.22 + lift2)
		elif hat == "nightcap":
			var hy3: float = hhy - hry * 0.7
			c.move_to(hhx - hr * 0.95, hy3 + hry * 0.2)
			c.quad_to(X[18], Y[18] - hry * 0.4, X[17], Y[17] - hry * 0.2)
			c.quad_to(hhx + hr * 0.3, hy3 - hry * 0.2, hhx + hr * 0.95, hy3 + hry * 0.2)
			var pr2: float = maxf(1.5, hs * 0.022)
			c.move_to(X[17] + pr2, Y[17] - hry * 0.2)
			c.arc(X[17], Y[17] - hry * 0.2, pr2, 0.0, tau)
			c.move_to(hhx - hr * 0.95, hy3 + hry * 0.2)
			c.line_to(hhx + hr * 0.95, hy3 + hry * 0.2)
		elif hat == "bonnet":
			c.move_to(hhx - hr * 1.1, hhy + hry * 0.1)
			c.ellipse(hhx, hhy, hr * 1.12, hry * 1.1, hat_tilt * 0.6, PI * 0.95, PI * 2.1)
			var ky: float = hhy + hry * 1.05
			c.move_to(hhx - hr * 0.9, hhy + hry * 0.6)
			c.quad_to(hhx, ky + hry * 0.25, hhx + hr * 0.9, hhy + hry * 0.6)
			c.move_to(hhx, ky)
			c.line_to(hhx - hr * 0.5, ky + hry * 0.4)
			c.move_to(hhx, ky)
			c.line_to(hhx + hr * 0.5, ky + hry * 0.4)
		elif hat == "cap":
			var ty2: float = hhy - hry * 0.55
			var lift3: float = -jump * vs * 0.6 if jump > 0.0 else 0.0
			c.move_to(hhx - hr * 1.05, ty2 + lift3)
			c.quad_to(hhx, ty2 - hry * 0.75 + lift3, hhx + hr * 1.05, ty2 + lift3)
			c.move_to(hhx - hr * 1.05, ty2 + lift3)
			c.line_to(hhx + hr * 1.05, ty2 + lift3)
			var bdir: float = 1.0 if noseX >= 0.0 else -1.0
			c.move_to(hhx + bdir * hr * 0.9, ty2 + lift3)
			c.line_to(hhx + bdir * hr * 1.45 + noseX * hr * 0.1, ty2 + hry * 0.12 + lift3)
		elif hat == "hood":
			var ty3: float = hhy - hry
			c.move_to(X[2] - hr * 0.2, Y[2])
			c.quad_to(hhx - hr * 1.35, hhy - hry * 0.2, hhx - hr * 0.2 + (-hr * 0.3 if moving else 0.0), ty3 - hry * 0.45)
			c.quad_to(hhx + hr * 1.35, hhy - hry * 0.2, X[3] + hr * 0.2, Y[3])
	# Clavicles (bare-necked outfits, chest towards us, lod 2).
	if lod >= 2 and cY < -0.45 and (outfit == null or outfit == "plain" or outfit == "apron" or outfit == "smock") and acc != "scarf" and hat != "hood":
		var nr: float = m.neckR * hs
		for side in 2:
			var s: int = 2 + side
			var dir: float = 1.0 if X[s] >= X[1] else -1.0
			var y0c: float = lerp_(Y[1], Y[s], 0.75)
			c.move_to(X[1] + dir * nr * 0.55, y0c + vs * 0.006)
			c.quad_to(lerp_(X[1], X[s], 0.5), y0c + vs * 0.012, lerp_(X[1], X[s], 0.85), lerp_(Y[1], Y[s], 0.95))
	# Waistband: where the shirt meets the trousers (not under a robe, cloak or coat).
	if lod >= 2 and m.belt != 0.0 and outfit != "robe" and outfit != "cloak" and not bool(look.get("coat")) and mode != "fed":
		var bend: float = (m.beltX1 - m.beltX0) * 0.12 * (1.0 if cY < 0.0 else -0.6)
		c.move_to(m.beltX0, m.beltY0)
		c.quad_to(m.beltCx, m.beltCy + absf(bend), m.beltX1, m.beltY1)
	# Coat hem (the robe and cloak draw their own).
	if lod >= 1 and bool(look.get("coat")) and mode != "fed" and outfit != "robe" and outfit != "cloak":
		# Hem corners sorted by screen x so the coat never crosses itself when the figure faces us.
		var cy0: float = by + body_ry * 0.35
		var r: int = 21 if X[21] >= X[22] else 22
		var l: int = 43 - r
		c.move_to(bx + body_rx * 0.98, cy0)
		c.quad_to(X[r] + body_rx * 0.2, (cy0 + Y[r]) * 0.5, X[r] + body_rx * 0.1, Y[r])
		c.quad_to((X[r] + X[l]) * 0.5, maxf(Y[r], Y[l]) + vs * 0.02, X[l] - body_rx * 0.1, Y[l])
		c.quad_to(X[l] - body_rx * 0.2, (cy0 + Y[l]) * 0.5, bx - body_rx * 0.98, cy0)
	if p.seated:
		var sw: float = hs * 0.26 * m.bw
		c.move_to(X[14] - sw, Y[4] + vs * 0.01)
		c.line_to(X[14] + sw, Y[5] + vs * 0.01)
	if acc == "scarf":
		var sw2: float = maxf(m.neckR * hs * 1.9, body_rx * 0.55)
		var nyy: float = Y[1] - body_ry * 0.05
		c.move_to(X[1] - sw2, nyy)
		c.quad_to(X[1], nyy + hry * 0.5, X[1] + sw2, nyy)
		c.move_to(X[1] + sw2 * 0.7, nyy + hry * 0.15)
		c.quad_to(X[16], Y[16], X[15], Y[15])
	# Props carried in the right hand.
	if prop == "cane" and mode != "fed":
		c.move_to(X[19], Y[19])
		c.line_to(X[20], Y[20])
		c.move_to(X[20], Y[20])
		c.line_to(X[19], Y[19] - vs * 0.03)
		c.arc(X[19] - hs * 0.015, Y[19] - vs * 0.03, hs * 0.015 + 1.0, 0.0, PI, true)
	elif prop == "lantern":
		var lx: float = X[20]
		var ly: float = Y[20]
		var lw2: float = maxf(1.5, hs * 0.03)
		var lh2: float = maxf(2.0, vs * 0.05)
		c.move_to(X[19], Y[19])
		c.line_to(lx, ly - lh2 * 0.6)
		c.move_to(lx - lw2, ly - lh2 * 0.5)
		c.line_to(lx + lw2, ly - lh2 * 0.5)
		c.line_to(lx + lw2 * 0.8, ly + lh2 * 0.5)
		c.line_to(lx - lw2 * 0.8, ly + lh2 * 0.5)
		c.close_path()
	elif prop == "basket":
		var kx: float = X[20]
		var ky2: float = Y[20]
		var kw: float = maxf(2.0, hs * 0.045)
		var kh: float = maxf(1.5, vs * 0.035)
		c.move_to(kx - kw * 0.8, ky2 - kh * 0.5)
		c.quad_to(kx, ky2 - kh * 2.2, kx + kw * 0.8, ky2 - kh * 0.5)
		c.move_to(kx - kw, ky2 - kh * 0.5)
		c.line_to(kx + kw, ky2 - kh * 0.5)
		c.line_to(kx + kw * 0.7, ky2 + kh * 0.5)
		c.line_to(kx - kw * 0.7, ky2 + kh * 0.5)
		c.close_path()
	elif prop == "umbrella" and mode != "fed" and mode != "cower":
		var ux2: float = X[20]
		var uy2: float = Y[20]
		var uw: float = hr * 2.6
		c.move_to(X[19], Y[19])
		c.line_to(ux2, uy2)
		c.move_to(ux2 - uw, uy2 + hry * 0.9)
		c.quad_to(ux2, uy2 - hry * 1.2, ux2 + uw, uy2 + hry * 0.9)
		for k in 3:
			var x0u: float = ux2 - uw + (k * 2.0 * uw) / 3.0
			var x1u: float = x0u + (2.0 * uw) / 3.0
			c.move_to(x0u, uy2 + hry * 0.9)
			c.quad_to((x0u + x1u) * 0.5, uy2 + hry * 1.25, x1u, uy2 + hry * 0.9)
	var pool: Array = FigureVol.POOL
	# Fingers (lod 2): a fist round a carried prop or role item, splayed when scared or struggling, else a relaxed curl.
	if lod >= 2:
		var spread: bool = mode == "startle" or mode == "cower" or mode == "grapple" or md == 1
		var extra: Variant = look.get("extra")
		for i in draw_n:
			var q: FigureVol.Part = pool[i]
			if q.kind != "hand" or not (q.rh > 2.0):
				continue
			var r: float = q.rh
			var ax: float = q.ax
			var ay: float = q.ay
			var ux: float = q.ux
			var uy: float = q.uy
			var vx: float = q.vx
			var vy: float = q.vy
			var right: bool = q.b == 7
			var grip: bool = false
			if mode != "fed":
				if right:
					grip = prop != "none" and not (prop == "umbrella" and mode == "cower")
				else:
					grip = extra != null and extra != "none" and extra != "bow"
			if grip:
				# Knuckle row across the tip, a curled finger crease and the thumb wrapped over.
				for f in 3:
					var cc: float = 0.5 - f * 0.5
					var kx2: float = ax + (ux * 1.12 + vx * cc) * r
					var ky3: float = ay + (uy * 1.12 + vy * cc) * r
					c.move_to(kx2 - vx * r * 0.22, ky3 - vy * r * 0.22)
					c.quad_to(kx2 + ux * r * 0.22, ky3 + uy * r * 0.22, kx2 + vx * r * 0.22, ky3 + vy * r * 0.22)
				c.move_to(ax + (ux * 0.55 + vx * 0.55) * r, ay + (uy * 0.55 + vy * 0.55) * r)
				c.quad_to(ax + (ux * 0.95 + vx * 0.2) * r, ay + (uy * 0.95 + vy * 0.2) * r, ax + (ux * 0.9 - vx * 0.25) * r, ay + (uy * 0.9 - vy * 0.25) * r)
			elif spread:
				# Four splayed fingers fanning out from the palm.
				for f in 4:
					var a: float = -0.55 + f * 0.37
					var ca: float = cos(a)
					var sa2: float = sin(a)
					var dx: float = ux * ca + vx * sa2
					var dy: float = uy * ca + vy * sa2
					c.move_to(ax + dx * r * 0.95, ay + dy * r * 0.95)
					c.line_to(ax + dx * r * (1.75 - 0.12 * absf(f - 1.5)), ay + dy * r * (1.75 - 0.12 * absf(f - 1.5)))
			else:
				# Relaxed: three fingers curling back toward the palm.
				for f in 3:
					var cc2: float = 0.32 - f * 0.3
					var x0f: float = ax + (ux * 0.9 + vx * cc2) * r
					var y0f: float = ay + (uy * 0.9 + vy * cc2) * r
					c.move_to(x0f, y0f)
					c.quad_to(ax + (ux * 1.5 + vx * cc2) * r, ay + (uy * 1.5 + vy * cc2) * r, ax + (ux * 1.38 + vx * (cc2 + 0.18)) * r, ay + (uy * 1.38 + vy * (cc2 + 0.18)) * r)
	# Knees and elbows (lod 2): a kneecap cup seen from the front, an elbow crease on the inside of a bent arm.
	if lod >= 2:
		for i in draw_n:
			var q: FigureVol.Part = pool[i]
			if not (q.rh > 1.5):
				continue
			if q.kind == "leg" and m.sr < 0.75 and cY < 0.2 and outfit != "robe":
				var r: float = q.rh
				c.move_to(q.jx - q.vx * r * 0.45 + q.ux * r * 0.15, q.jy - q.vy * r * 0.45 + q.uy * r * 0.15)
				c.quad_to(q.jx + q.ux * r * 0.75, q.jy + q.uy * r * 0.75, q.jx + q.vx * r * 0.45 + q.ux * r * 0.15, q.jy + q.vy * r * 0.45 + q.uy * r * 0.15)
			elif q.kind == "arm" and absf(q.bend) > 0.35:
				var r2: float = q.rh
				var sd: float = 1.0 if q.bend > 0.0 else -1.0
				c.move_to(q.jx + q.vx * sd * r2 * 0.2 - q.ux * r2 * 0.5, q.jy + q.vy * sd * r2 * 0.2 - q.uy * r2 * 0.5)
				c.quad_to(q.jx + q.vx * sd * r2 * 0.75, q.jy + q.vy * sd * r2 * 0.75, q.jx + q.vx * sd * r2 * 0.2 + q.ux * r2 * 0.5, q.jy + q.vy * sd * r2 * 0.2 + q.uy * r2 * 0.5)
	if p.hands_over_head and lod >= 2:
		for side in 2:
			c.move_to(X[6 + side], Y[6 + side])
			c.line_to(X[6 + side] + (-1.0 if side != 0 else 1.0) * hr * 0.3, Y[6 + side] - hry * 0.25)


# ---------------------------------------------------------------- extras

## Extra grip / tip: slots 24/25 when present, otherwise a spot beside the left hand.
static func ex_slots(p: Pose, m: FigureVol.Meas) -> void:
	var X := p.X
	var Y := p.Y
	if X.size() > 25 and Y.size() > 25 and (X[24] != 0.0 or Y[24] != 0.0 or X[25] != 0.0 or Y[25] != 0.0):
		ex_gx = X[24]
		ex_gy = Y[24]
		ex_tx = X[25]
		ex_ty = Y[25]
	else:
		ex_gx = X[6]
		ex_gy = Y[6]
		ex_tx = X[6] + m.hs * 0.02
		ex_ty = Y[6] - m.vs * 0.28 * m.lh


## Hem from (x0, y) to (x1, y), bowing down by dip in the middle, in four soft scallops (folds meeting the hem).
static func hem_wave(c: Canvas, x0: float, y: float, x1: float, dip: float) -> void:
	var px: float = x0
	for i in range(1, 5):
		var t: float = i / 4.0
		var tm: float = (i - 0.5) / 4.0
		var x: float = lerp_(x0, x1, t)
		var yb: float = y + dip * 4.0 * t * (1.0 - t)
		var ym: float = y + dip * 4.0 * tm * (1.0 - tm) + dip * (0.7 if (i & 1) != 0 else 0.45)
		c.quad_to((px + x) * 0.5, ym, x, yb)
		px = x


## Mail, robe, apron/smock, cloak, role hats and role items (look.outfit / roleHat / extra). Strokes only.
static func draw_extras(c: Canvas, p: Pose, look: Dictionary, o: Opts) -> bool:
	FigureVol._init_tables()
	var X := p.X
	var Y := p.Y
	if X.size() < 24 or Y.size() < 24:
		return false
	var outfit: Variant = look.get("outfit")
	var role_hat: Variant = look.get("roleHat")
	var extra: Variant = look.get("extra")
	if not (outfit != null and outfit != "plain") and not (role_hat != null and role_hat != "none") and not (extra != null and extra != "none"):
		return true
	# Hull widths (chest r0, hips r1) from the parts geometry so clothes fit the anatomy.
	FigureVol.parts(X, Y, p.Z, p, look, FigureVol.HPOOL)
	FigureVol.span_sig = NAN
	var m: FigureVol.Meas = FigureVol.M
	m.hipU = FigureVol.num(p.hip_u, 0.0)
	var lod: int = p.lod
	var lw: float = maxf(0.5, FigureVol.num(o.lw, 1.0))
	c.save()
	c.line_join = "round"
	c.line_cap = "round"
	c.global_alpha = clampf(FigureVol.num(o.alpha, 1.0) * FigureVol.num(o.sa, 1.0), 0.0, 1.0)
	c.stroke_style = o.style
	c.line_width = lw
	c.begin_path()
	var hr: float = m.hr
	var hry: float = m.hry
	var hs: float = m.hs
	var vs: float = m.vs
	if outfit == "mail" and lod >= 1:
		for row in 3:
			var t: float = 0.25 + 0.25 * row
			var cx: float = lerp_(m.sx, m.hx, t)
			var cy: float = lerp_(m.sy, m.hy, t)
			var w: float = lerp_(m.r0, m.r1, t) * 0.85
			var sr: float = maxf(0.8, w / 3.0)
			for k in 3:
				var x: float = cx - w + sr + k * 2.0 * sr
				c.move_to(x + sr, cy)
				c.arc(x, cy, sr, 0.0, PI)
	elif outfit == "robe" or outfit == "cloak":
		var hy: float = hem_y(m, look, 1.0 if outfit == "robe" else 0.8)
		var lx: float = X[21]
		var rx: float = X[22]
		var swing: float = ((lx + rx) * 0.5) - m.hx
		var hem: float = clampf(FigureVol.num(look.get("hem"), 1.0), 0.0, 1.0)
		var half: float = maxf(absf(lx - rx) * 0.5, m.r1 * 1.2) * (1.45 if outfit == "cloak" else 1.0) * (1.0 + 0.5 * hem)
		var cx2: float = m.hx + swing
		var sh_l: int = 2 if X[2] <= X[3] else 3
		var sh_r: int = 5 - sh_l
		var dip: float = vs * (0.025 if outfit == "cloak" else 0.02)
		if outfit == "robe":
			c.move_to(m.hx - m.r1, m.hy)
			c.quad_to(m.hx - m.r1 * 1.2 + (cx2 - m.hx) * 0.3, (m.hy + hy) * 0.5, cx2 - half, hy)
			if lod >= 1:
				hem_wave(c, cx2 - half, hy, cx2 + half, dip)
			else:
				c.quad_to(cx2, hy + dip, cx2 + half, hy)
			c.quad_to(m.hx + m.r1 * 1.2 + (cx2 - m.hx) * 0.3, (m.hy + hy) * 0.5, m.hx + m.r1, m.hy)
			if lod >= 2:
				# Folds falling from the girdle and spreading toward the hem (alternate ones stop short).
				for k in 3:
					var f: float = -0.5 + k * 0.5
					var tx: float = m.hx + f * m.r1 * 0.75
					var ty: float = m.hy + vs * 0.02
					var ln: float = 1.0 if k == 1 else 0.72
					var bx: float = lerp_(tx, cx2 + f * half * 0.72, ln)
					var by: float = lerp_(ty, hy, ln) + (dip * 0.85 if ln == 1.0 else 0.0)
					c.move_to(tx, ty)
					c.quad_to((tx + bx) * 0.5 + f * half * 0.08, (ty + by) * 0.5, bx, by)
		else:
			c.move_to(X[sh_l], Y[sh_l])
			c.quad_to(X[sh_l] - half * 0.6, (Y[sh_l] + hy) * 0.5, cx2 - half, hy)
			if lod >= 1:
				hem_wave(c, cx2 - half, hy, cx2 + half, dip)
			else:
				c.quad_to(cx2, hy + dip, cx2 + half, hy)
			c.quad_to(X[sh_r] + half * 0.6, (Y[sh_r] + hy) * 0.5, X[sh_r], Y[sh_r])
			if lod >= 2:
				# Long folds from each shoulder blade down the drape.
				for s2 in 2:
					var sh: int = sh_l if s2 == 0 else sh_r
					var sg: float = -1.0 if s2 == 0 else 1.0
					var tx2: float = X[sh] + sg * half * 0.05
					var ty2: float = Y[sh] + vs * 0.04
					var bx2: float = cx2 + sg * half * 0.55
					c.move_to(tx2, ty2)
					c.quad_to(tx2 + sg * half * 0.32, (ty2 + hy) * 0.5, bx2, hy + dip * 0.7)
	elif outfit == "apron" or outfit == "smock":
		var hy2: float = hem_y(m, look, 0.35 if outfit == "apron" else 0.2)
		var wt: float = lerp_(m.r0, m.r1, 0.2) * 0.45
		var cy0: float = lerp_(m.sy, m.hy, 0.15)
		var cx0: float = lerp_(m.sx, m.hx, 0.15)
		var cy1: float = lerp_(m.sy, m.hy, 0.85)
		var cx1: float = lerp_(m.sx, m.hx, 0.85)
		var wb: float = lerp_(m.r0, m.r1, 0.85) * 0.9
		c.move_to(cx0 - wt, cy0)
		c.line_to(cx0 + wt, cy0)
		c.move_to(cx0 - wt, cy0)
		c.line_to(cx1 - wb, cy1)
		c.move_to(cx0 + wt, cy0)
		c.line_to(cx1 + wb, cy1)
		var half2: float = maxf(wb, m.r1 * 1.05)
		c.move_to(m.hx - half2, hy2)
		if lod >= 1:
			hem_wave(c, m.hx - half2, hy2, m.hx + half2, vs * 0.016)
		else:
			c.quad_to(m.hx, hy2 + vs * 0.02, m.hx + half2, hy2)
		if lod >= 2 and hy2 - cy1 > vs * 0.04:
			# Two soft folds hanging from the waist tie.
			for k in [-1.0, 1.0]:
				var tx3: float = cx1 + k * wb * 0.35
				var bx3: float = m.hx + k * half2 * 0.45
				c.move_to(tx3, cy1 + vs * 0.01)
				c.quad_to(lerp_(tx3, bx3, 0.5) - k * half2 * 0.06, (cy1 + hy2) * 0.5, bx3, hy2 + vs * 0.012)

	# Role hat (replaces the ordinary hat; see draw()).
	if role_hat == "kettle" or role_hat == "biretta":
		set_hat(p, p.mode, str(role_hat), p.tilt, m)
		var hxh: float = _hat_x
		var base: float = _hat_y - hry * 0.78
		if role_hat == "kettle":
			FigureVol.ell(c, hxh, base, hr * 1.5, maxf(1.2, vs * 0.014), 0.0)
			c.move_to(hxh - hr * 0.88, base)
			c.ellipse(hxh, base, hr * 0.88, maxf(0.01, hry * 0.8), 0.0, PI, TWO_PI)
		else:
			var top: float = base - hry * 0.55
			c.move_to(hxh - hr * 0.95, base)
			c.line_to(hxh - hr * 0.78, top)
			c.line_to(hxh + hr * 0.78, top)
			c.line_to(hxh + hr * 0.95, base)
			c.close_path()
			for k in range(-1, 2):
				c.move_to(hxh + k * hr * 0.3, base)
				c.line_to(hxh + k * hr * 0.26, top)
			var tr: float = maxf(1.2, hr * 0.15)
			c.move_to(hxh + tr, top - tr)
			c.arc(hxh, top - tr, tr, 0.0, TWO_PI)

	# Role item in the left hand (side 0).
	if extra != null and extra != "none":
		ex_slots(p, m)
		var gx: float = ex_gx
		var gy: float = ex_gy
		var tx4: float = ex_tx
		var ty4: float = ex_ty
		if extra == "shovel":
			c.move_to(gx, gy)
			c.line_to(tx4, ty4)
			var dx: float = tx4 - gx
			var dy: float = ty4 - gy
			var L: float = maxf(1e-6, sqrt(dx * dx + dy * dy))
			var ux: float = dx / L
			var uy: float = dy / L
			var bwid: float = maxf(2.0, hs * 0.035)
			var blen: float = maxf(2.0, vs * 0.045)
			var nx: float = -uy * bwid
			var ny: float = ux * bwid
			c.move_to(tx4 + nx, ty4 + ny)
			c.line_to(tx4 + ux * blen + nx * 0.8, ty4 + uy * blen + ny * 0.8)
			c.line_to(tx4 + ux * blen * 1.2, ty4 + uy * blen * 1.2)
			c.line_to(tx4 + ux * blen - nx * 0.8, ty4 + uy * blen - ny * 0.8)
			c.line_to(tx4 - nx, ty4 - ny)
		elif extra == "bundle":
			var rx2: float = maxf(2.0, hs * 0.05)
			var ry2: float = rx2 * 0.8
			FigureVol.ell(c, tx4, ty4, rx2, ry2, 0.4)
			c.move_to(tx4 - rx2 * 0.7, ty4 - ry2 * 0.5)
			c.quad_to(tx4, ty4 + ry2 * 0.2, tx4 + rx2 * 0.7, ty4 + ry2 * 0.5)
		elif extra == "ledger":
			var w2: float = maxf(2.0, hs * 0.04)
			var h2: float = maxf(2.5, vs * 0.045)
			var lx2: float = gx
			var ly2: float = gy - h2 * 0.6
			c.move_to(lx2 - w2, ly2 - h2)
			c.line_to(lx2 + w2, ly2 - h2)
			c.line_to(lx2 + w2, ly2 + h2)
			c.line_to(lx2 - w2, ly2 + h2)
			c.close_path()
			c.move_to(lx2 - w2 * 0.6, ly2 - h2)
			c.line_to(lx2 - w2 * 0.6, ly2 + h2)
		elif extra == "bow":
			var d: float = -1.0 if FigureVol.num(p.nose_x, 0.0) >= 0.0 else 1.0
			var tx0: float = m.sx + d * m.r0 * 1.1
			var ty0: float = m.sy - vs * 0.04 * m.lh
			var bx0: float = m.hx + d * m.r1 * 1.1
			var by0: float = m.hy + vs * 0.06 * m.lh
			var mx: float = (tx0 + bx0) * 0.5 + d * m.r0 * 1.3
			var my: float = (ty0 + by0) * 0.5
			c.move_to(tx0, ty0)
			c.quad_to(mx, my, bx0, by0)
			c.move_to(tx0, ty0)
			c.quad_to((tx0 + bx0) * 0.5 - d * m.r0 * 0.3, my, bx0, by0)
	c.stroke()
	c.restore()
	return true


# ---------------------------------------------------------------- grab arms

## Volumetric version of the held victim's grab arms, same anchors as EchoLayer.draw_grab_arms. w/h/ws = canvas size and wscale.
static func draw_grab_arms_vol(c: Canvas, w: float, h: float, ws: float, X: PackedFloat32Array, Y: PackedFloat32Array, hs: float, lw_in: float, alpha: float, jolt: float, t_n: float, pid: float, style: String, rs_k: float) -> bool:
	if X.size() < 15 or Y.size() < 15:
		return false
	var lw: float = maxf(0.5, lw_in)
	var left: int = 2 if X[2] <= X[3] else 3
	var shake: float = jolt * hs * 0.05
	c.save()
	c.global_alpha = minf(1.0, alpha * 0.7)
	c.stroke_style = style
	c.line_cap = "round"
	c.line_join = "round"
	for k in 2:
		var idx: int = left if k == 0 else 5 - left
		var sgn: float = -1.0 if k == 0 else 1.0
		var tx: float = X[idx] + (X[14] - X[idx]) * 0.35 * rs_k + sgn * hs * 0.03 + sin(t_n * 37.0 + k * 2.0 + pid) * shake
		var ty: float = Y[idx] + (Y[14] - Y[idx]) * 0.35 * rs_k + hs * 0.02 + cos(t_n * 29.0 + k * 3.0 + pid) * shake
		var sx: float = w * 0.5 + sgn * w * 0.3
		var sy: float = h + 12.0 * ws
		var r0: float = lw * 4.5
		var r1: float = lw * 2.6
		c.line_width = lw
		c.begin_path()
		FigureVol.capsule(c, sx, sy, r0, tx, ty, r1)
		var dx: float = tx - sx
		var dy: float = ty - sy
		if dx * dx + dy * dy > 4.0:
			var ang: float = atan2(dy, dx)
			for q in 2:
				var t: float = 0.4 if q == 0 else 0.7
				var cx: float = lerp_(sx, tx, t)
				var cy: float = lerp_(sy, ty, t)
				var r: float = lerp_(r0, r1, t)
				c.move_to(cx + r * cos(ang + PI * 0.5), cy + r * sin(ang + PI * 0.5))
				c.ellipse(cx, cy, maxf(0.01, r), maxf(0.01, r * 0.35), ang + PI * 0.5, 0.0, PI, true)
		c.stroke()
		# Knuckles and fingers at the grip.
		c.begin_path()
		var gr: float = maxf(2.0, hs * 0.012)
		c.move_to(tx + gr, ty)
		c.arc(tx, ty, gr, 0.0, TWO_PI)
		for f in range(-1, 2):
			c.move_to(tx, ty - gr * 0.6)
			c.line_to(tx + f * gr * 0.9 - sgn * gr * 0.3, ty - gr * 2.0)
			c.move_to(tx + f * gr * 0.7 - gr * 0.3, ty + gr * 0.2)
			c.line_to(tx + f * gr * 0.7 + gr * 0.3, ty + gr * 0.2)
		c.stroke()
	c.restore()
	return true


# ---------------------------------------------------------------- flush

## Soft coral flush fitted to the anatomy: the face (0, toward the facing side), along the neck (1) and over the wrists (6/7,
## along the forearm). flush = [temporal, carotid, radialL, radialR]. a = min(cap, flush[i] * skin * 0.25 * sa).
static func draw_flush(c: Canvas, p: Pose, look: Dictionary, flush: PackedFloat32Array, o: Opts) -> bool:
	FigureVol._init_tables()
	var X := p.X
	var Y := p.Y
	if X.size() < 24 or Y.size() < 24:
		return false
	var skin: float = clampf(FigureVol.num(look.get("skin"), 1.0), 0.0, 1.0)
	var sa: float = clampf(FigureVol.num(o.alpha, 1.0) * FigureVol.num(o.sa, 1.0), 0.0, 1.0)
	var cap: float = 0.08 if o.reduced else 0.18
	var n: int = FigureVol.parts(X, Y, p.Z, p, look, FigureVol.HPOOL)
	FigureVol.span_sig = NAN
	var m: FigureVol.Meas = FigureVol.M
	var neck: FigureVol.Part = null
	var arm_l: FigureVol.Part = null
	var arm_r: FigureVol.Part = null
	for i in n:
		var q: FigureVol.Part = FigureVol.HPOOL[i]
		if q.kind == "neck":
			neck = q
		elif q.kind == "arm":
			if q.b == 6:
				arm_l = q
			else:
				arm_r = q
	c.save()
	c.fill_style = FigureVol.COL_FLUSH
	for i in 4:
		var a: float = minf(cap, maxf(0.0, FigureVol.num(flush[i], 0.0)) * skin * 0.25 * sa)
		if not (a > 0.002):
			continue
		c.global_alpha = a
		c.begin_path()
		if i == 0:
			var nx: float = clampf(FigureVol.num(p.nose_x, 0.0), -1.0, 1.0)
			FigureVol.ell(c, X[0] + nx * m.hr * 0.16, Y[0] + m.hry * 0.12, m.hr * 0.6, m.hry * 0.62, FigureVol.num(p.tilt, 0.0) * 0.6)
		elif i == 1:
			if neck != null:
				var ang: float = atan2(neck.by - neck.ay, neck.bx - neck.ax)
				var ln: float = sqrt((neck.bx - neck.ax) * (neck.bx - neck.ax) + (neck.by - neck.ay) * (neck.by - neck.ay))
				FigureVol.ell(c, lerp_(neck.ax, neck.bx, 0.3), lerp_(neck.ay, neck.by, 0.3), maxf(1.0, ln * 0.32), maxf(1.0, minf(neck.r0, neck.r1) * 0.8), ang)
			else:
				FigureVol.ell(c, X[1], Y[1], maxf(1.5, m.hs * 0.025), maxf(1.5, m.vs * 0.02), 0.0)
		else:
			var f: FigureVol.Part = arm_l if i == 2 else arm_r
			var s: int = 6 if i == 2 else 7
			if f != null:
				FigureVol.tangent(X[s - 4], Y[s - 4], X[s + 4], Y[s + 4], X[s], Y[s], 1.0)
				var ang2: float = atan2(FigureVol.TAN_Y, FigureVol.TAN_X)
				var r: float = maxf(1.0, f.r1)
				FigureVol.ell(c, X[s] - FigureVol.TAN_X * r * 0.9, Y[s] - FigureVol.TAN_Y * r * 0.9, r * 1.6, r * 0.85, ang2)
			else:
				FigureVol.ell(c, X[s], Y[s], maxf(1.5, m.hs * 0.02), maxf(1.5, m.hs * 0.02), 0.0)
		c.fill()
	c.restore()
	return true
