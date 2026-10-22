class_name FigureVol
extends RefCounted
## Ports js/figure.js: the volumetric villager drawing (anatomy v0.17). Every body part is a closed outline polygon drawn as a
## smooth curve through its edge midpoints: torso hull, swept limbs (arm/leg along the same quadratic curve the line figure
## uses), hands, shoes and head; the line figure's details (hair, hats, scarf, hem, props...) are redrawn on top.
## Pure drawing on a Canvas from pose slots; no state of its own. P is the pose slot set (Pose: X, Y, Z PackedFloat32Array).
## This file holds the geometry (parts, queries); drawing is in figure_vol_draw.gd.

const TWO_PI := TAU
const MAXP := 16
const MAXPTS := 40
const NT := 10
const NH := 24
const COL_RIM := "#ffcf8a"
const COL_FLUSH := "#ff8a78"
const BLACK := "#000000"

const TU := [-0.3, -0.15, 0.0, 0.1, 0.28, 0.52, 0.76, 0.95, 1.1, 1.21]
const ARM_T := [0.0, 0.1, 0.24, 0.4, 0.5, 0.6, 0.72, 0.88, 1.0]
const ARM_R := [0.024, 0.023, 0.021, 0.017, 0.0155, 0.0175, 0.017, 0.0135, 0.012]
const ARM_A := [0.0, 0.002, 0.003, 0.0005, -0.002, 0.002, 0.001, 0.0, 0.0]
const LEG_T := [0.0, 0.12, 0.28, 0.42, 0.5, 0.58, 0.68, 0.82, 0.93, 1.0]
const LEG_R := [0.042, 0.04, 0.035, 0.029, 0.026, 0.028, 0.029, 0.022, 0.016, 0.016]
const LEG_A := [0.0, 0.002, 0.002, 0.001, 0.003, -0.002, -0.006, -0.003, 0.0, 0.0]
const NECK_T := [0.0, 1.0]
const NECK_R := [1.12, 0.96]
const NECK_A := [0.0, 0.0]
const SHAFT_R := [1.0, 1.0]
const HAND_A := [-0.5, -0.05, 0.35, 0.75, 0.82, 0.5, 0.95, 1.32, 1.46, 1.4, 1.15, 0.6, 0.0, -0.5]
const HAND_C := [0.52, 0.75, 1.02, 1.0, 0.74, 0.55, 0.6, 0.46, 0.1, -0.3, -0.62, -0.72, -0.66, -0.52]
const SHOE_PA := [-0.62, -0.9, -0.95, -0.72, -0.38, 0.0, 0.4, 0.78, 1.04, 1.0, 0.75, 0.1]
const SHOE_PV := [0.95, 0.62, 0.05, -0.55, -0.95, -0.82, -0.52, -0.34, -0.06, 0.5, 0.95, 1.0]
const SHOE_FA := [-0.86, -1.0, -0.98, -0.8, -0.42, 0.0, 0.42, 0.8, 0.98, 1.0, 0.86, 0.0]
const SHOE_FV := [0.95, 0.55, 0.0, -0.45, -0.78, -0.86, -0.78, -0.45, 0.0, 0.55, 0.95, 1.0]
## Per body kind: [chest, waist, belly depth, hip width, seat, depth, arm thickness, leg thickness].
const BODY := {
	"bean": [1.0, 0.9, 1.12, 1.0, 1.0, 1.0, 1.0, 1.0],
	"pear": [0.92, 1.0, 1.15, 1.18, 1.28, 1.0, 0.95, 1.12],
	"stick": [0.9, 0.74, 1.45, 0.9, 0.8, 0.85, 0.8, 0.82],
	"round": [1.08, 1.24, 1.6, 1.05, 1.1, 1.15, 1.18, 1.12],
	"box": [1.08, 1.05, 1.0, 1.02, 1.0, 1.0, 1.08, 1.05],
}


## A part: closed outline plus the frame data the draw code reads.
class Part:
	extends RefCounted
	var kind: String = ""
	var a: int = 0
	var b: int = 0
	var r0: float = 0.0
	var r1: float = 0.0
	var z: float = 0.0
	var ax: float = 0.0
	var ay: float = 0.0
	var bx: float = 0.0
	var by: float = 0.0
	var n: int = 0
	var px := PackedFloat64Array()
	var py := PackedFloat64Array()
	var y0: float = 0.0
	var y1: float = 0.0
	var nw: int = 0
	var wx := PackedFloat64Array()
	var wy := PackedFloat64Array()
	var wr := PackedFloat64Array()
	var wa := PackedFloat64Array()
	var ux: float = 0.0
	var uy: float = 0.0
	var vx: float = 0.0
	var vy: float = 0.0
	var rh: float = 0.0
	var jx: float = 0.0
	var jy: float = 0.0
	var bend: float = 0.0
	var ns: int = 0

	func _init() -> void:
		px.resize(MAXPTS)
		py.resize(MAXPTS)
		wx.resize(3)
		wy.resize(3)
		wr.resize(3)
		wa.resize(3)


## Scratch measurements shared by parts / draw / extras (filled by measure()).
class Meas:
	extends RefCounted
	var lh := 1.0
	var bw := 1.0
	var hs := 1.0
	var vs := 1.0
	var vsy := 1.0
	var sr := 0.0
	var cr := 1.0
	var shoulder := 1.0
	var kid := 0.0
	var fs := 1.0
	var sx := 0.0
	var sy := 0.0
	var hx := 0.0
	var hy := 0.0
	var r0 := 1.0
	var r1 := 1.0
	var shS := 0.062
	var hipS := 0.04
	var crU := 1.0
	var srU := 0.0
	var crL := 1.0
	var srL := 0.0
	var armK := 1.0
	var legK := 1.0
	var neckR := 1.0
	var hr := 1.0
	var hry := 1.0
	var bodyRx := 1.0
	var bodyRy := 1.0
	var hipU := 0.0
	var belt := 0.0
	var beltX0 := 0.0
	var beltY0 := 0.0
	var beltX1 := 0.0
	var beltY1 := 0.0
	var beltCx := 0.0
	var beltCy := 0.0


static var M := Meas.new()
static var POOL: Array = []
static var HPOOL: Array = []
static var TW := PackedFloat64Array()
static var TD := PackedFloat64Array()
static var TF := PackedFloat64Array()
static var TLX := PackedFloat64Array()
static var TLY := PackedFloat64Array()
static var TRX := PackedFloat64Array()
static var TRY := PackedFloat64Array()
static var LX := PackedFloat64Array()
static var LY := PackedFloat64Array()
static var RX := PackedFloat64Array()
static var RY := PackedFloat64Array()
static var HCOS := PackedFloat64Array()
static var HSIN := PackedFloat64Array()
static var TAN_X: float = 0.0
static var TAN_Y: float = 1.0
static var _inited := false


static func _init_tables() -> void:
	if _inited:
		return
	_inited = true
	for arr in [TW, TD, TF, TLX, TLY, TRX, TRY]:
		arr.resize(NT)
	for arr2 in [LX, LY, RX, RY]:
		arr2.resize(16)
	HCOS.resize(NH)
	HSIN.resize(NH)
	for i in NH:
		HCOS[i] = cos(float(i) / NH * TWO_PI)
		HSIN[i] = sin(float(i) / NH * TWO_PI)
	for i in MAXP:
		POOL.append(Part.new())
		HPOOL.append(Part.new())


static func num(v: Variant, d: float) -> float:
	return float(v) if (v is float or v is int) and is_finite(float(v)) else d


static func lerp_(a: float, b: float, t: float) -> float:
	return a + (b - a) * t


## Child factor 0..1 from look.height: 1 at 0.66 and below, 0 from 0.82.
static func kid_k(lh: float) -> float:
	return clampf((0.82 - lh) / 0.16, 0.0, 1.0)


# ---------------------------------------------------------------- capsule and ellipse helpers

## Tapered-capsule outline subpath (two tangent lines plus two arcs). Returns true when something was added.
static func capsule(c: Canvas, x0: float, y0: float, r0_in: float, x1: float, y1: float, r1_in: float) -> bool:
	if not (is_finite(x0) and is_finite(y0) and is_finite(x1) and is_finite(y1) and is_finite(r0_in) and is_finite(r1_in)):
		return false
	var r0v: float = maxf(0.0, r0_in)
	var r1v: float = maxf(0.0, r1_in)
	var dx: float = x1 - x0
	var dy: float = y1 - y0
	var L: float = sqrt(dx * dx + dy * dy)
	if L < 1e-9 or absf(r0v - r1v) >= L:
		var big: bool = r1v > r0v
		var cx: float = x1 if big else x0
		var cy: float = y1 if big else y0
		var r: float = r1v if big else r0v
		c.move_to(cx + r, cy)
		c.arc(cx, cy, r, 0.0, TWO_PI)
		return true
	var a: float = atan2(dy, dx)
	var beta: float = acos(clampf((r0v - r1v) / L, -1.0, 1.0))
	var aP: float = a + beta
	var aM: float = a - beta
	c.move_to(x0 + r0v * cos(aP), y0 + r0v * sin(aP))
	c.arc(x1, y1, r1v, aP, aM, true)
	c.line_to(x0 + r0v * cos(aM), y0 + r0v * sin(aM))
	c.arc(x0, y0, r0v, aM, aP, true)
	c.close_path()
	return true


## Ellipse subpath that always starts with a move_to at angle 0 (so it never joins the previous subpath).
static func ell(c: Canvas, x: float, y: float, rx_in: float, ry_in: float, rot: float) -> void:
	var rx: float = maxf(0.01, rx_in)
	var ry: float = maxf(0.01, ry_in)
	c.move_to(x + rx * cos(rot), y + rx * sin(rot))
	c.ellipse(x, y, rx, ry, rot, 0.0, TWO_PI)


# ---------------------------------------------------------------- measurements

static func body_sh_s(look: Dictionary) -> float:
	var b: Variant = look.get("body")
	return 0.075 if b == "round" else (0.05 if b == "stick" else (0.05 if b == "pear" else 0.062))


static func body_hip_s(look: Dictionary) -> float:
	var b: Variant = look.get("body")
	return 0.055 if b == "pear" else (0.06 if b == "round" else (0.03 if b == "stick" else 0.04))


static func body_row(look: Dictionary) -> Array:
	var b: Variant = look.get("body")
	return BODY[b] if (b == "pear" or b == "stick" or b == "round" or b == "box") else BODY["bean"]


## pose: Pose of the pose fields the JS reads (lh, hs, vs, vsy, shS, hipS, sr, cr, hr, hry, bodyRx, hipU, pid, noseX, tilt...).
static func measure(X: PackedFloat32Array, Y: PackedFloat32Array, pose: Pose, look: Dictionary) -> Meas:
	var m := M
	var lh: float = clampf(num(pose.lh, num(look.get("height"), 1.0)), 0.3, 2.0)
	var bw: float = clampf(num(look.get("build"), 1.0), 0.4, 2.0)
	m.lh = lh
	m.bw = bw
	m.kid = kid_k(lh)
	var hs: float = num(pose.hs, 0.0)
	var vs: float = num(pose.vs, 0.0)
	if not (vs > 0.0):
		var fy: float = (Y[8] + Y[9]) * 0.5
		vs = maxf(1.0, absf(fy - Y[0]) / (0.9 * lh))
	if not (hs > 0.0):
		hs = vs
	m.hs = hs
	m.vs = vs
	m.vsy = num(pose.vsy, vs)
	m.shoulder = clampf(num(look.get("shoulder"), 1.0), 0.8, 1.25)
	m.sx = (X[2] + X[3]) * 0.5
	m.sy = (Y[2] + Y[3]) * 0.5
	m.hx = (X[4] + X[5]) * 0.5
	m.hy = (Y[4] + Y[5]) * 0.5
	var swid: float = sqrt((X[2] - X[3]) * (X[2] - X[3]) + 0.04 * (Y[2] - Y[3]) * (Y[2] - Y[3])) * 0.5
	var hwid: float = sqrt((X[4] - X[5]) * (X[4] - X[5]) + 0.04 * (Y[4] - Y[5]) * (Y[4] - Y[5])) * 0.5
	var shS: float = maxf(0.01, num(pose.vol_sh_s, body_sh_s(look) * bw))
	var hipS: float = maxf(0.01, num(pose.hip_s, body_hip_s(look) * bw))
	m.shS = shS
	m.hipS = hipS
	m.crU = clampf(swid / (shS * hs + 1e-6), 0.0, 1.0)
	m.srU = sqrt(1.0 - m.crU * m.crU)
	m.crL = clampf(hwid / (hipS * hs + 1e-6), 0.0, 1.0)
	m.srL = sqrt(1.0 - m.crL * m.crL)
	var sr: float = num(pose.sr, NAN)
	var cr: float = num(pose.cr, NAN)
	if not is_finite(sr) or not is_finite(cr):
		cr = m.crU
		sr = m.srU
	m.sr = absf(sr)
	m.cr = absf(cr)
	m.fs = -1.0 if sr < 0.0 else 1.0
	var row := body_row(look)
	var kid: float = m.kid
	m.armK = row[6] * (0.7 + 0.3 * bw) * (1.0 + 0.18 * kid)
	m.legK = row[7] * (0.6 + 0.4 * bw) * (1.0 + 0.15 * kid)
	var bk: Variant = look.get("body")
	m.neckR = (0.026 if bk == "stick" else (0.034 if bk == "round" else 0.03)) * lh * (1.0 + 0.1 * kid)
	var hk: float = 1.0 + 0.25 * kid
	m.hr = maxf(0.5, num(pose.hr, 0.088 * lh * sqrt(bw) * hs)) * hk
	m.hry = maxf(0.5, num(pose.hry, 0.092 * lh * vs)) * hk
	m.bodyRx = maxf(1.0, num(pose.body_rx, swid))
	m.bodyRy = maxf(1.0, absf(m.hy - m.sy) * 0.5)
	m.r0 = maxf(1.0, swid)
	m.r1 = maxf(1.0, hwid)
	m.hipU = num(pose.hip_u, 0.0)
	m.belt = 0.0
	return m


# ---------------------------------------------------------------- parts

static func begin(out: Array, i: int, kind: String, a: int, b: int, z: float) -> Part:
	var p: Part
	if i < out.size() and out[i] is Part:
		p = out[i]
	else:
		p = Part.new()
		if i < out.size():
			out[i] = p
		else:
			out.append(p)
	p.kind = kind
	p.a = a
	p.b = b
	p.z = z
	p.n = 0
	p.nw = 0
	p.ns = 0
	return p


static func push_pt(p: Part, x: float, y: float) -> void:
	if p.n >= MAXPTS:
		return
	p.px[p.n] = x
	p.py[p.n] = y
	p.n += 1


static func push_ring(p: Part, x: float, y: float, r: float, a: float) -> void:
	if p.nw >= 3:
		return
	p.wx[p.nw] = x
	p.wy[p.nw] = y
	p.wr[p.nw] = r
	p.wa[p.nw] = a
	p.nw += 1


static func finish(p: Part) -> void:
	var y0 := INF
	var y1 := -INF
	for i in p.n:
		var y: float = p.py[i]
		if y < y0:
			y0 = y
		if y > y1:
			y1 = y
	p.y0 = y0
	p.y1 = y1


## Torso hull into part p. Writes m.r0 (chest), m.r1 (hips), m.bodyRx (waist) half-widths and the belt line.
static func build_torso(p: Part, look: Dictionary, pose: Pose, m: Meas) -> void:
	var row := body_row(look)
	var kid: float = m.kid
	var lh: float = m.lh
	var chest: float = row[0] * (1.0 - 0.04 * kid)
	var waist: float = lerp_(row[1], maxf(row[1], 1.02), kid)
	var belly: float = row[2] * (1.0 + 0.25 * kid)
	var hip_k: float = row[3]
	var seat: float = row[4]
	var dep: float = row[5]
	var sw: float = m.shS * m.shoulder
	var hw: float = m.hipS
	var dR: float = 0.024 * lh * m.armK
	var tR: float = 0.042 * lh * m.legK
	var nR: float = m.neckR
	var stoop: float = clampf(num(look.get("stoop"), 0.0), 0.0, 0.4)
	var pid: float = num(pose.pid, 0.0)
	var wob: float = (float(posmod(int(pid * 37.0) % 7 + 7, 7)) - 3.0) / 3.0 * 0.035
	TW[0] = nR * 1.08
	TD[0] = nR * 1.05
	TF[0] = -0.002
	TW[1] = lerp_(nR, sw + 0.5 * dR, 0.42)
	TD[1] = 0.046 + 0.025 * stoop
	TF[1] = -0.006 - 0.05 * stoop
	TW[2] = sw + 0.75 * dR
	TD[2] = 0.056 + 0.03 * stoop
	TF[2] = -0.004 - 0.06 * stoop
	TW[3] = sw + 0.95 * dR
	TD[3] = 0.064 + 0.02 * stoop
	TF[3] = 0.002 - 0.035 * stoop
	TW[4] = sw * chest + 0.5 * dR
	TD[4] = 0.07 * dep
	TF[4] = 0.01
	TW[5] = lerp_(sw, hw + tR * 0.6, 0.5) * waist
	TD[5] = 0.06 * belly * dep
	TF[5] = 0.008 * belly
	TW[6] = (hw + tR * 0.75) * lerp_(waist, hip_k, 0.6)
	TD[6] = 0.064 * belly * dep
	TF[6] = 0.012 * belly - 0.003
	TW[7] = (hw + tR * 0.88) * hip_k
	TD[7] = 0.066 * dep * seat
	TF[7] = -0.008 * seat
	TW[8] = (hw + tR * 0.74) * hip_k
	TD[8] = 0.062 * seat
	TF[8] = -0.014 * seat
	TW[9] = hw * 0.55 + tR * 0.35
	TD[9] = 0.04
	TF[9] = -0.004
	var sx: float = m.sx
	var sy: float = m.sy
	var hx: float = m.hx
	var hy: float = m.hy
	var ax: float = hx - sx
	var ay: float = hy - sy
	var L: float = sqrt(ax * ax + ay * ay)
	if L < 1e-6:
		ax = 0.0
		ay = 1.0
		L = 1.0
	else:
		ax /= L
		ay /= L
	var nx: float = -ay
	var ny: float = ax
	if nx < 0.0:
		nx = -nx
		ny = -ny
	var hs: float = m.hs
	var fs: float = m.fs
	var ax_ang: float = atan2(ay, ax)
	for i in NT:
		var u: float = TU[i]
		var k: float = clampf(u, 0.0, 1.0)
		var cr_i: float = lerp_(m.crU, m.crL, k)
		var sr_i: float = lerp_(m.srU, m.srL, k)
		var e: float = hs * sqrt(TW[i] * cr_i * TW[i] * cr_i + TD[i] * sr_i * TD[i] * sr_i)
		var f: float = TF[i] * hs * sr_i * fs
		var cx: float = sx + (hx - sx) * u + nx * f
		var cy: float = sy + (hy - sy) * u + ny * f
		var w: float = wob if i >= 2 and i <= 4 else 0.0
		TRX[i] = cx + nx * e * (1.0 - w)
		TRY[i] = cy + ny * e * (1.0 - w)
		TLX[i] = cx - nx * e * (1.0 + w)
		TLY[i] = cy - ny * e * (1.0 + w)
		if i == 4:
			m.r0 = maxf(1.0, e)
		if i == 5:
			m.bodyRx = maxf(1.0, e)
		if i == 7:
			m.r1 = maxf(1.0, e)
	push_pt(p, (TLX[0] + TRX[0]) * 0.5 - ax * L * 0.03, (TLY[0] + TRY[0]) * 0.5 - ay * L * 0.03)
	for i in NT:
		push_pt(p, TRX[i], TRY[i])
	var by_: float = 1.27
	push_pt(p, sx + (hx - sx) * by_ + nx * TF[9] * hs * m.srL * fs, sy + (hy - sy) * by_ + ny * TF[9] * hs * m.srL * fs)
	var i2: int = NT - 1
	while i2 >= 0:
		push_pt(p, TLX[i2], TLY[i2])
		i2 -= 1
	var cx2: float = (TLX[4] + TRX[4] + TLX[5] + TRX[5]) * 0.25
	var cy2: float = (TLY[4] + TRY[4] + TLY[5] + TRY[5]) * 0.25
	push_ring(p, cx2, cy2, (sqrt((TRX[4] - TLX[4]) * (TRX[4] - TLX[4]) + (TRY[4] - TLY[4]) * (TRY[4] - TLY[4])) + sqrt((TRX[5] - TLX[5]) * (TRX[5] - TLX[5]) + (TRY[5] - TLY[5]) * (TRY[5] - TLY[5]))) * 0.25, ax_ang)
	m.belt = 1.0
	m.beltX0 = lerp_(TLX[6], TLX[7], 0.45)
	m.beltY0 = lerp_(TLY[6], TLY[7], 0.45)
	m.beltX1 = lerp_(TRX[6], TRX[7], 0.45)
	m.beltY1 = lerp_(TRY[6], TRY[7], 0.45)
	m.beltCx = (m.beltX0 + m.beltX1) * 0.5
	m.beltCy = (m.beltY0 + m.beltY1) * 0.5
	p.ax = sx
	p.ay = sy
	p.bx = hx
	p.by = hy
	p.r0 = m.r0
	p.r1 = m.r1
	finish(p)


## Piecewise-linear profile lookup.
static func prof(T: Array, V: Array, t: float) -> float:
	if t <= T[0]:
		return V[0]
	for i in range(1, T.size()):
		if t <= T[i]:
			var k: float = (t - T[i - 1]) / (T[i] - T[i - 1])
			return V[i - 1] + (V[i] - V[i - 1]) * k
	return V[V.size() - 1]


## Unit tangent of the quadratic A -> C -> E at t into TAN_X/TAN_Y (falls back to the chord, then straight down).
static func tangent(Ax: float, Ay: float, Cx: float, Cy: float, Ex: float, Ey: float, t: float) -> void:
	var dx: float = 2.0 * (1.0 - t) * (Cx - Ax) + 2.0 * t * (Ex - Cx)
	var dy: float = 2.0 * (1.0 - t) * (Cy - Ay) + 2.0 * t * (Ey - Cy)
	var L: float = sqrt(dx * dx + dy * dy)
	if L < 1e-6:
		dx = Ex - Ax
		dy = Ey - Ay
		L = sqrt(dx * dx + dy * dy)
	if L < 1e-6:
		TAN_X = 0.0
		TAN_Y = 1.0
		return
	TAN_X = dx / L
	TAN_Y = dy / L


static func _quad(A: float, C: float, E: float, t: float) -> float:
	var u: float = 1.0 - t
	return u * u * A + 2.0 * u * t * C + t * t * E


## Sweep a tapered outline along the quadratic A -> C -> E between t0 and t1 into part p (see the JS for the profile rules).
static func sweep(p: Part, Ax: float, Ay: float, Cx: float, Cy: float, Ex: float, Ey: float, t0: float, t1: float, T: Array, R: Array, A: Array, k: float, fwd: float, K: int) -> void:
	p.ns = K
	var last_nx := 1.0
	var last_ny := 0.0
	for s in K + 1:
		var t: float = t0 + (t1 - t0) * s / K
		var bx: float = _quad(Ax, Cx, Ex, t)
		var by: float = _quad(Ay, Cy, Ey, t)
		tangent(Ax, Ay, Cx, Cy, Ex, Ey, t)
		var nx: float = -TAN_Y
		var ny: float = TAN_X
		if not is_finite(nx) or not is_finite(ny):
			nx = last_nx
			ny = last_ny
		last_nx = nx
		last_ny = ny
		var r: float = prof(T, R, t) * k
		var a: float = prof(T, A, t) * k * nx * fwd
		var rl: float = r + a
		var rr: float = r - a
		var dx: float = 2.0 * (1.0 - t) * (Cx - Ax) + 2.0 * t * (Ex - Cx)
		var dy: float = 2.0 * (1.0 - t) * (Cy - Ay) + 2.0 * t * (Ey - Cy)
		var cr: float = dx * 2.0 * (Ay - 2.0 * Cy + Ey) - dy * 2.0 * (Ax - 2.0 * Cx + Ex)
		var L2: float = dx * dx + dy * dy
		if L2 > 1e-9 and absf(cr) > 1e-12:
			var rc: float = 0.85 * L2 * sqrt(L2) / absf(cr)
			if cr > 0.0:
				if rl > rc:
					rl = rc
			elif rr > rc:
				rr = rc
		LX[s] = bx + nx * rl
		LY[s] = by + ny * rl
		RX[s] = bx - nx * rr
		RY[s] = by - ny * rr
		if s > 0:
			if (LX[s] - LX[s - 1]) * TAN_X + (LY[s] - LY[s - 1]) * TAN_Y < 0.0:
				LX[s] = LX[s - 1]
				LY[s] = LY[s - 1]
			if (RX[s] - RX[s - 1]) * TAN_X + (RY[s] - RY[s - 1]) * TAN_Y < 0.0:
				RX[s] = RX[s - 1]
				RY[s] = RY[s - 1]
	for s in K + 1:
		push_pt(p, LX[s], LY[s])
	var t_e: float = t1
	var bxe: float = _quad(Ax, Cx, Ex, t_e)
	var bye: float = _quad(Ay, Cy, Ey, t_e)
	tangent(Ax, Ay, Cx, Cy, Ex, Ey, t_e)
	var re: float = prof(T, R, t_e) * k
	var nxe: float = -TAN_Y
	var nye: float = TAN_X
	push_pt(p, bxe + (nxe * 0.7 + TAN_X * 0.7) * re, bye + (nye * 0.7 + TAN_Y * 0.7) * re)
	push_pt(p, bxe + TAN_X * re, bye + TAN_Y * re)
	push_pt(p, bxe + (-nxe * 0.7 + TAN_X * 0.7) * re, bye + (-nye * 0.7 + TAN_Y * 0.7) * re)
	p.bx = bxe
	p.by = bye
	p.r1 = re
	var s2: int = K
	while s2 >= 0:
		push_pt(p, RX[s2], RY[s2])
		s2 -= 1
	var t_s: float = t0
	var bxs: float = _quad(Ax, Cx, Ex, t_s)
	var bys: float = _quad(Ay, Cy, Ey, t_s)
	tangent(Ax, Ay, Cx, Cy, Ex, Ey, t_s)
	var rs_: float = prof(T, R, t_s) * k
	var nxs: float = -TAN_Y
	var nys: float = TAN_X
	push_pt(p, bxs + (-nxs * 0.7 - TAN_X * 0.7) * rs_, bys + (-nys * 0.7 - TAN_Y * 0.7) * rs_)
	push_pt(p, bxs - TAN_X * rs_, bys - TAN_Y * rs_)
	push_pt(p, bxs + (nxs * 0.7 - TAN_X * 0.7) * rs_, bys + (nys * 0.7 - TAN_Y * 0.7) * rs_)
	p.ax = bxs
	p.ay = bys
	p.r0 = rs_
	for q in 2:
		var tq: float = t0 + (t1 - t0) * (0.25 if q == 0 else 0.75)
		tangent(Ax, Ay, Cx, Cy, Ex, Ey, tq)
		push_ring(p, _quad(Ax, Cx, Ex, tq), _quad(Ay, Cy, Ey, tq), prof(T, R, tq) * k, atan2(TAN_Y, TAN_X))
	var t3: float = t0 + (t1 - t0) * 0.84
	tangent(Ax, Ay, Cx, Cy, Ex, Ey, t3)
	push_ring(p, _quad(Ax, Cx, Ex, t3), _quad(Ay, Cy, Ey, t3), prof(T, R, t3) * k * 1.04, atan2(TAN_Y, TAN_X))
	var tm: float = (t0 + t1) * 0.5
	tangent(Ax, Ay, Cx, Cy, Ex, Ey, tm)
	p.jx = _quad(Ax, Cx, Ex, tm)
	p.jy = _quad(Ay, Cy, Ey, tm)
	p.ux = TAN_X
	p.uy = TAN_Y
	p.vx = -TAN_Y
	p.vy = TAN_X
	p.rh = prof(T, R, tm) * k
	var c1: float = (Cx - Ax) * (Ey - Cy) - (Cy - Ay) * (Ex - Cx)
	var l1: float = sqrt((Cx - Ax) * (Cx - Ax) + (Cy - Ay) * (Cy - Ay)) * sqrt((Ex - Cx) * (Ex - Cx) + (Ey - Cy) * (Ey - Cy))
	p.bend = c1 / l1 if l1 > 1e-9 else 0.0
	finish(p)


## Head: cranium with a jaw and chin that follow the face direction (sin yaw = pose.noseX).
static func build_head(p: Part, hx: float, hy: float, hk: String, pose: Pose, m: Meas) -> void:
	var sY: float = clampf(num(pose.nose_x, 0.0), -1.0, 1.0)
	var aY: float = absf(sY)
	var kid: float = m.kid
	var rx: float = m.hr * (0.95 if hk == "square" else 0.9)
	var ry: float = m.hry
	var rot: float = num(pose.tilt, 0.0) * 0.6
	var cR: float = cos(rot)
	var sR: float = sin(rot)
	var jaw: float = (0.08 if hk == "square" else (0.24 if hk == "long" else (0.2 if hk == "egg" else 0.2))) * (1.0 - 0.55 * kid)
	for i in NH:
		var c: float = HCOS[i]
		var s: float = HSIN[i]
		var x: float = c
		var y: float = s
		if hk == "square":
			x = (-1.0 if c < 0.0 else 1.0) * pow(absf(c), 0.62)
			y = (-1.0 if s < 0.0 else 1.0) * pow(absf(s), 0.62)
		if hk == "egg":
			x *= 1.0 + 0.08 * -s if s < 0.0 else 1.0 - 0.1 * s
		var back: bool = x * sY < 0.0
		if s > 0.0:
			x *= 1.0 - jaw * s * s
			x += sY * 0.16 * s * s * s * (1.0 - 0.5 * kid)
			if back:
				x *= 1.0 - 0.22 * aY * s
			y *= 1.0 + 0.1 * s * s * s * s * (1.0 - 0.6 * kid)
		elif back:
			x *= 1.0 + 0.08 * aY
		else:
			x += sY * 0.05 * maxf(0.0, 1.0 - absf(s + 0.3) * 4.0)
		var lx: float = x * rx
		var ly: float = y * ry
		push_pt(p, hx + lx * cR - ly * sR, hy + lx * sR + ly * cR)
	p.ax = hx
	p.ay = hy
	p.bx = hx
	p.by = hy
	p.r0 = rx
	p.r1 = ry
	finish(p)


static func build_hand(p: Part, X: PackedFloat32Array, Y: PackedFloat32Array, s: int, m: Meas, rh: float) -> void:
	var A: int = 2 + s
	var C: int = 10 + s
	var E: int = 6 + s
	tangent(X[A], Y[A], X[C], Y[C], X[E], Y[E], 1.0)
	var ux: float = TAN_X
	var uy: float = TAN_Y
	var vx: float = -uy
	var vy: float = ux
	var medial: float = X[14] - X[E]
	var want: float = m.fs * m.sr * 1.5 + (-1.0 if medial < 0.0 else 1.0) * (1.0 - m.sr)
	if vx * want < 0.0:
		vx = -vx
		vy = -vy
	var hx: float = X[E]
	var hy: float = Y[E]
	for i in HAND_A.size():
		push_pt(p, hx + (ux * HAND_A[i] + vx * HAND_C[i]) * rh, hy + (uy * HAND_A[i] + vy * HAND_C[i]) * rh)
	p.ax = hx
	p.ay = hy
	p.bx = hx + ux * rh
	p.by = hy + uy * rh
	p.r0 = rh
	p.r1 = rh
	p.ux = ux
	p.uy = uy
	p.vx = vx
	p.vy = vy
	p.rh = rh
	finish(p)


static func build_foot(p: Part, X: PackedFloat32Array, Y: PackedFloat32Array, s: int, m: Meas) -> void:
	var F: int = 8 + s
	var pw: float = clampf((m.sr - 0.1) / 0.6, 0.0, 1.0)
	var sl: float = sqrt(m.lh)
	var Lp: float = m.hs * (0.064 * sl * pow(m.legK, 0.3)) + 1.0
	var Lf: float = m.hs * (0.033 * sl * pow(m.legK, 0.5)) + 1.0
	var L: float = lerp_(Lf, Lp, pw)
	var H: float = maxf(1.2, m.vs * 0.022 * sl)
	var td: float = m.fs
	var cx: float = X[F] + m.sr * td * m.hs * 0.03
	var cy: float = Y[F]
	for i in SHOE_PA.size():
		var a: float = lerp_(SHOE_FA[i], SHOE_PA[i], pw)
		var v: float = lerp_(SHOE_FV[i], SHOE_PV[i], pw)
		push_pt(p, cx + td * a * L, cy + v * H)
	p.ax = cx
	p.ay = cy
	p.bx = cx + td * L
	p.by = cy
	p.r0 = L
	p.r1 = H
	finish(p)


## Fill out with up to 16 parts (kind, a, b, r0, r1, z, ax, ay, bx, by, n, px, py ...). Returns the count. X/Y/Z are the slot arrays.
static func parts(X: PackedFloat32Array, Y: PackedFloat32Array, Z: PackedFloat32Array, pose: Pose, look: Dictionary, out: Array) -> int:
	_init_tables()
	if X.size() < 24 or Y.size() < 24:
		return 0
	var m := measure(X, Y, pose, look)
	var zf := func(k: int) -> float: return num(Z[k], 0.0) if k < Z.size() else 0.0
	var lhs: float = m.lh * m.hs
	var fig_px: float = absf(Y[8] - Y[0]) + absf(Y[9] - Y[0])
	var K: int = 12 if fig_px > 160.0 else (8 if fig_px > 60.0 else 5)
	var fwd: float = m.fs * m.sr
	var n := 0
	var tz: float = (zf.call(2) + zf.call(3) + zf.call(4) + zf.call(5)) * 0.25
	build_torso(begin(out, n, "torso", 2, 4, tz), look, pose, m)
	n += 1
	var pn := begin(out, n, "neck", 1, 0, (zf.call(1) + zf.call(0)) * 0.5 + 0.03)
	n += 1
	var dN: float = sqrt((X[0] - X[1]) * (X[0] - X[1]) + (Y[0] - Y[1]) * (Y[0] - Y[1]))
	var kN: float = clampf((dN - m.hry * 0.9 + m.neckR * m.hs * 0.5) / dN, 0.25, 0.8) if dN > 1e-6 else 0.5
	var ex: float = X[1] + (X[0] - X[1]) * kN
	var ey: float = Y[1] + (Y[0] - Y[1]) * kN
	sweep(pn, X[1], Y[1], (X[1] + ex) * 0.5, (Y[1] + ey) * 0.5, ex, ey, 0.0, 1.0, NECK_T, NECK_R, NECK_A, m.neckR * m.hs, 0.0, 2)
	for s in 2:
		var h: int = 4 + s
		var kn: int = 12 + s
		var f: int = 8 + s
		var lk: float = lhs * m.legK
		sweep(begin(out, n, "leg", h, f, 0.35 * zf.call(h) + 0.45 * zf.call(kn) + 0.2 * zf.call(f) - 0.02), X[h], Y[h], X[kn], Y[kn], X[f], Y[f], 0.0, 1.0, LEG_T, LEG_R, LEG_A, lk, fwd, K)
		n += 1
		build_foot(begin(out, n, "foot", f, f, zf.call(f) - 0.01), X, Y, s, m)
		n += 1
		var sh: int = 2 + s
		var el: int = 10 + s
		var hd: int = 6 + s
		var ak: float = lhs * m.armK
		sweep(begin(out, n, "arm", sh, hd, (zf.call(sh) + zf.call(el) + zf.call(hd)) / 3.0), X[sh], Y[sh], X[el], Y[el], X[hd], Y[hd], 0.0, 1.0, ARM_T, ARM_R, ARM_A, ak, fwd, K)
		n += 1
		var rh: float = maxf(1.2, m.hs * 0.021 * sqrt(m.lh) * (1.0 + 0.15 * m.kid) * sqrt(m.armK))
		build_hand(begin(out, n, "hand", hd, hd, zf.call(hd) - 0.01), X, Y, s, m, rh)
		n += 1
	var head_kind: String = pose.head_kind
	build_head(begin(out, n, "head", 0, 0, zf.call(0) - 0.08), X[0], Y[0], head_kind, pose, m)
	n += 1
	if look.get("extra") == "shovel" and X.size() > 25:
		var pe := begin(out, n, "extra", 24, 25, (num(Z[24], 0.0) + num(Z[25], 0.0)) * 0.5 if Z.size() > 25 else 0.0)
		n += 1
		sweep(pe, X[24], Y[24], (X[24] + X[25]) * 0.5, (Y[24] + Y[25]) * 0.5, X[25], Y[25], 0.0, 1.0, NECK_T, SHAFT_R, NECK_A, maxf(1.0, m.hs * 0.008), 0.0, 1)
	return n


## In-place stable insertion sort by z, descending (farthest first).
static func sort_back_to_front(arr: Array, n: int) -> Array:
	var length: int = mini(arr.size(), n if n >= 0 else arr.size())
	for i in range(1, length):
		var item: Part = arr[i]
		var z: float = item.z
		var j: int = i - 1
		while j >= 0 and (arr[j] as Part).z < z:
			arr[j + 1] = arr[j]
			j -= 1
		arr[j + 1] = item
	return arr


# ---------------------------------------------------------------- geometry queries

## True when (x, y) is inside part p's outline (nonzero winding through the edge-midpoint polygon, which the drawn curve encloses).
static func contains(p: Part, x: float, y: float) -> bool:
	if p == null or not (p.n >= 3):
		return false
	var n: int = p.n
	var wn := 0
	var jx: float = (p.px[n - 1] + p.px[0]) * 0.5
	var jy: float = (p.py[n - 1] + p.py[0]) * 0.5
	for i in n:
		var k: int = 0 if i == n - 1 else i + 1
		var ix: float = (p.px[i] + p.px[k]) * 0.5
		var iy: float = (p.py[i] + p.py[k]) * 0.5
		var cr: float = (ix - jx) * (y - jy) - (x - jx) * (iy - jy)
		if jy <= y:
			if iy > y and cr > 0.0:
				wn += 1
		elif iy <= y and cr < 0.0:
			wn -= 1
		jx = ix
		jy = iy
	return wn != 0


static var span_sig: float = NAN
static var span_n: int = 0


## Kind of the front-most body part whose outline contains screen point (x, y), or "". Own part pool (tests and tools).
static func hit(pose: Pose, look: Dictionary, x: float, y: float) -> String:
	var n := parts(pose.X, pose.Y, pose.Z, pose, look, HPOOL)
	span_sig = NAN
	var best := ""
	var bz := INF
	for i in n:
		var p: Part = HPOOL[i]
		if p.z <= bz and contains(p, x, y):
			bz = p.z
			best = p.kind
	return best


## All part kinds containing (x, y), comma separated in part order.
static func hit_all(pose: Pose, look: Dictionary, x: float, y: float) -> String:
	var n := parts(pose.X, pose.Y, pose.Z, pose, look, HPOOL)
	span_sig = NAN
	var s := ""
	for i in n:
		if contains(HPOOL[i], x, y):
			s += ("," if s != "" else "") + (HPOOL[i] as Part).kind
	return s


## Horizontal extent of the whole silhouette at screen row y into out [x0, x1]. False when no part crosses the row.
static func span_at(pose: Pose, look: Dictionary, y: float, out: PackedFloat64Array) -> bool:
	var X := pose.X
	var Y := pose.Y
	if not is_finite(y):
		return false
	var sig: float = X[0] + Y[0] * 3.1 + X[6] * 1.7 + Y[7] * 2.3 + X[8] * 0.7 + Y[9] * 1.3 + X[2] * 0.9 + pose.hr
	if sig != span_sig:
		span_n = parts(X, Y, pose.Z, pose, look, HPOOL)
		span_sig = sig
	var x0 := INF
	var x1 := -INF
	for i in span_n:
		var p: Part = HPOOL[i]
		if not (p.y0 <= y and p.y1 >= y):
			continue
		var n: int = p.n
		for j in n:
			var k: int = 0 if j == n - 1 else j + 1
			var ya: float = p.py[j]
			var yb: float = p.py[k]
			if (ya <= y) == (yb <= y):
				continue
			var x: float = p.px[j] + (p.px[k] - p.px[j]) * (y - ya) / (yb - ya)
			if x < x0:
				x0 = x
			if x > x1:
				x1 = x
	if not (x1 >= x0):
		return false
	out[0] = x0
	out[1] = x1
	return true
