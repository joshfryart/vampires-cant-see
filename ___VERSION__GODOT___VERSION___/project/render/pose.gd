class_name Pose
extends RefCounted
## Ports posePerson / put / sweepWave from js/render.js (line figure only: no volumetric branch, and the held-victim
## struggle pose (js/struggle.js) is replaced by the plain grapple pose until struggle.gd lands in Phase 4).
## Body frame: f forward (the way the person faces), s to their left, u up (wall units, 0 = feet).
## Slots (screen px): 0 head, 1 neck, 2/3 shoulders, 4/5 hips, 6/7 hands, 8/9 feet, 10/11 elbows, 12/13 knees,
## 14 torso centre, 15 scarf tip, 16 scarf control, 17 hat tip, 18 hat control, 19 prop anchor, 20 prop tip,
## 21/22 coat hem, 23 head top. PX/PY are Float32 in JS, so they are PackedFloat32Array here.

const FIG_H := 0.78
const FIG_ZTOP := 1.7
const SWEEP := 0.22
const SWEEP_OVER := 1.3
const STRIP_Z := [0.0, 0.25, 0.45, 0.65, 0.85, 1.05, 1.7]
const FLASH_AGE := 0.12
const DEFAULT_LOOK := {"height": 1.0, "build": 1.0, "stride": 1.0, "acc": "scarf", "body": "bean", "head": "round", "hat": "none", "hair": "none", "beard": false, "nose": 1.0, "coat": false, "prop": "none"}

var X: PackedFloat32Array = PackedFloat32Array()
var Y: PackedFloat32Array = PackedFloat32Array()
var Z: PackedFloat32Array = PackedFloat32Array()

# fig scratch (js `fig`)
var f_cx: float = 0.0
var f_floor_y: float = 0.0
var f_hs: float = 0.0
var f_vs: float = 0.0
var f_sr: float = 0.0
var f_cr: float = 0.0
var f_sx: float = 1.0
var f_sy: float = 1.0
var f_age: float = -1.0
var f_h: float = 1.0
var f_fid: int = 0
var f_a: float = 0.0
var f_sway: float = 0.0
var f_persp: float = 0.0
var f_hz: float = 0.0

# pose scratch (js `pose`)
var hip_u: float = 0.0
var sh_u: float = 0.0
var head_u: float = 0.0
var hr: float = 0.0
var hry: float = 0.0
var body_rx: float = 0.0
var body_ry: float = 0.0
var tilt: float = 0.0
var lean: float = 0.0
var lod: int = 0
var depth: float = 0.0
var hs: float = 0.0
var vs: float = 0.0
var mode: String = "path"
var moving: bool = false
var seated: bool = false
var flee: bool = false
var prop: String = "none"
var hat: String = "none"
var head_kind: String = "round"
var body_kind: String = "bean"
var stars: bool = false
var eyes_x: bool = false
var hands_over_head: bool = false
var jump: float = 0.0
var nose_x: float = 0.0
var face_vis: bool = false
var eyes_vis: bool = false
var g_jolt: float = 0.0
var min_x: float = 0.0
var max_x: float = 0.0
var hip_s: float = 0.0
var lh: float = 1.0
var look: Dictionary = DEFAULT_LOOK
var acc: String = ""
var pid: int = 0
var t_n: float = 0.0
var anim: bool = true
var sweeping: bool = false
var dur: float = 0.0
var alpha: float = 1.0
var lw: float = 1.0
var sr: float = 0.0
var cr: float = 1.0

var _proj_fwd: float = 0.0
var _proj_sx: float = 0.0


func _init() -> void:
	X.resize(28)
	Y.resize(28)
	Z.resize(28)


static func smoothstep(a: float, b: float, x: float) -> float:
	var u: float = 0.0 if x <= a else (1.0 if x >= b else (x - a) / (b - a))
	return u * u * (3.0 - 2.0 * u)


## Ripple-only vision afterglow (render.js glowDur / glow / glowMul); AFTERGLOW_K 0.18, min 0.2, max 1.0.
static func glow_dur(fade: float) -> float:
	var f: float = fade if fade > 0.0 else 3.0
	return clampf(f * 0.18, 0.2, 1.0)


static func glow(age: float, dur_: float) -> float:
	if not (age >= 0.0) or age >= dur_:
		return 0.0
	var k: float = 1.0 - age / dur_
	return k * k * (3.0 - 2.0 * k)


## Lateral ripple -1..1 at normalised height zn while the band sweeps past (js sweepWave).
static func sweep_wave(zn: float, age: float) -> float:
	if not (age >= 0.0):
		return 0.0
	var f: float = (age / SWEEP) * SWEEP_OVER
	if zn > f:
		return 0.0
	var behind: float = f - zn
	var k: float = 1.0 - age / (SWEEP + 0.25)
	return 0.0 if k <= 0.0 else sin(behind * 22.0) * exp(-behind * 3.0) * k


## js project(): world point -> screen x and forward depth; false when behind the camera.
func project(player: Dictionary, x: float, y: float, half_w: float, tan_half: float) -> bool:
	var dx: float = x - player["x"]
	var dy: float = y - player["y"]
	var ca: float = cos(player["angle"])
	var sa: float = sin(player["angle"])
	var fwd: float = dx * ca + dy * sa
	var right: float = -dx * sa + dy * ca
	if fwd <= 0.1:
		return false
	_proj_fwd = fwd
	_proj_sx = half_w + (right / fwd) * (half_w / tan_half)
	return true


## js put(): project a body-frame point into slot k.
func put(rs: RenderState, k: int, f: float, s: float, u: float) -> void:
	var wv: float = sweep_wave(u / (f_h * 1.1), f_age) * 0.02 if f_age >= 0.0 else 0.0
	var ff: float = f * f_sx
	var ss: float = s * f_sx
	var px: float = (ff * f_sr + ss * f_cr + wv + f_sway * u) * f_hs
	var py: float = f_floor_y - u * f_sy * f_vs
	if f_persp > 0.0:
		var kp: float = f_persp / maxf(0.25, f_persp + f * f_cr)
		px *= kp
		py = f_hz + (py - f_hz) * kp
	X[k] = f_cx + px + rs.j(f_fid + k, 0) * f_a
	Y[k] = py + rs.j(f_fid + k, 1) * f_a
	Z[k] = ff * f_cr - ss * f_sr


## Ports posePerson (js/render.js:2318) for the line figure. e: {x, y, angle, lookAngle, phase, phaseRate, look, mode, sit,
## wary, modeAge, personId, fade}. Returns false when the figure is off screen. Fills X/Y/Z and the pose fields.
func pose_person(rs: RenderState, player: Dictionary, tan_half: float, e: Dictionary, age: float, locked: bool, now: float) -> bool:
	var half_w: float = rs.ow / 2.0
	if not project(player, e["x"], e["y"], half_w, tan_half):
		return false
	depth = _proj_fwd
	var vs_: float = rs.oh / depth
	var hs_: float = half_w / tan_half / depth
	var cx0: float = _proj_sx
	if cx0 < -hs_ * 0.5 - 20.0 or cx0 > rs.ow + hs_ * 0.5 + 20.0:
		return false
	var lk: Dictionary = e["look"] if e.get("look") is Dictionary else DEFAULT_LOOK
	var lh_: float = float(lk["height"]) if lk.get("height") is float or lk.get("height") is int else 1.0
	var bw: float = float(lk["build"]) if lk.get("build") is float or lk.get("build") is int else 1.0
	var anim_: bool = not rs.reduced
	var mode_: String = "grapple" if locked else (e["mode"] if e.get("mode") is String else "path")
	var pid_: int = int(e["personId"]) if e.get("personId") != null and float(e["personId"]) != 0.0 else 0
	var view_ang: float = atan2(e["y"] - player["y"], e["x"] - player["x"])
	var rel: float = e["angle"] - view_ang
	var ph: float = float(e["phase"]) if e.get("phase") != null else 0.0
	var phase_rate: float = float(e["phaseRate"]) if e.get("phaseRate") != null else 0.0
	if anim_ and phase_rate > 0.0 and age > 0.0 and (mode_ == "path" or mode_ == "flee"):
		ph += phase_rate * minf(age, 0.6)
	var can_move: bool = mode_ == "path" or mode_ == "flee"
	var moving_: bool = can_move and ph > 0.02
	var seated_: bool = bool(e.get("sit", false)) and not moving_ and (mode_ == "path" or mode_ == "startle")
	var sph: float = sin(ph)
	var cph: float = cos(ph)
	var amp: float = (float(lk["stride"]) if lk.get("stride") is float or lk.get("stride") is int else 1.0) * (1.35 if mode_ == "flee" else 1.0)
	var tn: float = now if anim_ else 0.0
	var fade: float = float(e["fade"]) if e.get("fade") != null and float(e["fade"]) > 0.0 else 3.0
	var dur_: float = glow_dur(fade)
	var sweeping_: bool = age >= 0.0 and age < SWEEP + dur_ and not locked
	var sq: float = 1.0 + 0.1 * cos(2.0 * ph) if moving_ else 1.0 + 0.02 * sin(tn * 3.1 + pid_ * 2.0)
	f_cx = cx0
	f_floor_y = rs.horizon + 0.5 * vs_
	f_hs = hs_
	f_vs = vs_
	f_sr = sin(rel)
	f_cr = cos(rel)
	f_age = age if sweeping_ and rs.quality >= 1 else -1.0
	f_h = FIG_H * lh_
	f_fid = (pid_ * 29 + 11) * 24
	f_a = 0.7 * rs.wscale
	f_sway = 0.0
	f_persp = depth if locked else 0.0
	f_hz = rs.horizon
	var yaw_u := 0.0
	var yaw_l := 0.0
	var g_jolt_ := 0.0
	if locked:
		var bm := 1.0
		if anim_:
			bm = 1.6 if rs.lock_age < 0.35 else 1.0 - smoothstep(0.2, 0.9, rs.lock_k)
		f_a *= bm
	var hip_u_: float = 0.33 * lh_
	var sh_u_: float = 0.53 * lh_
	var head_u_: float = 0.69 * lh_
	var lean_ := 0.0
	var head_f := 0.0
	var head_s := 0.0
	var tilt_ := 0.0
	var bob := 0.0
	var kid_w := 1.0
	var body: String = lk["body"] if lk.get("body") is String else ""
	var hip_s_: float = (0.055 if body == "pear" else (0.06 if body == "round" else (0.03 if body == "stick" else 0.04))) * bw * kid_w
	var sh_s: float = (0.075 if body == "round" else (0.05 if body == "stick" else (0.05 if body == "pear" else 0.062))) * bw * kid_w
	var foot_f := [0.0, 0.0]
	var foot_s := [hip_s_ * 1.15, -hip_s_ * 1.15]
	var foot_u := [0.0, 0.0]
	var knee_f := [0.012 * lh_, 0.012 * lh_]
	var knee_s := [hip_s_ * 1.25, -hip_s_ * 1.25]
	var knee_u := [0.0, 0.0]
	var hand_f := [0.0, 0.0]
	var hand_s := [0.0, 0.0]
	var hand_u := [0.0, 0.0]
	var elb_f := [0.0, 0.0]
	var elb_s := [0.0, 0.0]
	var elb_u := [0.0, 0.0]
	var lag_a: float = sin(ph - 1.3)
	var prop_: String = lk["prop"] if lk.get("prop") is String and lk["prop"] != "" else ("cane" if lk.get("acc") == "cane" else "none")
	var hold_r: bool = prop_ != "none"
	var jump_ := 0.0
	var stars_ := false
	var eyes_x_ := false
	var hands_over := false
	var mode_age: float = float(e["modeAge"]) if e.get("modeAge") is float or e.get("modeAge") is int else 9.0
	if mode_ == "grapple":
		hip_u_ = 0.3 * lh_
		sh_u_ = 0.5 * lh_
		head_u_ = 0.6 * lh_
		lean_ = 0.02 * lh_
		head_f = 0.03 * lh_
		head_s = 0.05 * bw
		tilt_ = 0.55 + 0.03 * sin(tn * 0.8 + pid_)
		knee_f = [0.06 * lh_, 0.05 * lh_]
		knee_u = [0.16 * lh_, 0.16 * lh_]
		hand_f = [0.01 * lh_, 0.0]
		hand_s = [sh_s * 1.1, -sh_s * 1.1]
		hand_u = [sh_u_ - 0.25 * lh_, sh_u_ - 0.26 * lh_]
		elb_f = [0.0, 0.0]
		elb_s = [sh_s * 1.4, -sh_s * 1.4]
		elb_u = [sh_u_ - 0.12 * lh_, sh_u_ - 0.12 * lh_]
	elif mode_ == "fed":
		hip_u_ = 0.07 * lh_
		sh_u_ = 0.3 * lh_
		head_u_ = 0.4 * lh_
		lean_ = -0.03 * lh_
		head_f = 0.05 * lh_
		head_s = -0.03 * bw
		tilt_ = -0.45
		foot_f = [0.22 * lh_, 0.19 * lh_]
		foot_u = [0.01 * lh_, 0.0]
		foot_s = [hip_s_ * 1.4, -hip_s_ * 1.1]
		knee_f = [0.1 * lh_, 0.09 * lh_]
		knee_u = [0.07 * lh_, 0.06 * lh_]
		knee_s = [hip_s_ * 1.3, -hip_s_ * 1.2]
		hand_f = [0.03 * lh_, 0.02 * lh_]
		hand_s = [sh_s * 2.2, -sh_s * 2.1]
		hand_u = [0.02 * lh_, 0.02 * lh_]
		elb_f = [0.0, 0.0]
		elb_s = [sh_s * 1.9, -sh_s * 1.8]
		elb_u = [0.14 * lh_, 0.14 * lh_]
	elif mode_ == "cower":
		var sh: float = sin(tn * 9.4 + pid_) * 0.006 * lh_ if anim_ else 0.0
		hip_u_ = 0.17 * lh_
		sh_u_ = 0.35 * lh_ + sh
		head_u_ = 0.45 * lh_ + sh
		lean_ = 0.05 * lh_
		head_f = 0.03 * lh_
		tilt_ = 0.12
		foot_s = [hip_s_ * 1.9, -hip_s_ * 1.9]
		knee_s = [hip_s_ * 2.3, -hip_s_ * 2.3]
		knee_f = [0.07 * lh_, 0.07 * lh_]
		knee_u = [0.1 * lh_, 0.1 * lh_]
		hand_f = [0.03 * lh_, 0.03 * lh_]
		hand_s = [0.03 * bw, -0.03 * bw]
		hand_u = [head_u_ + 0.08 * lh_, head_u_ + 0.07 * lh_]
		elb_f = [0.0, 0.0]
		elb_s = [sh_s * 1.9, -sh_s * 1.9]
		elb_u = [sh_u_ + 0.06 * lh_, sh_u_ + 0.06 * lh_]
		hands_over = true
	elif mode_ == "dazed":
		f_sway = sin(tn * 2.1 + pid_) * 0.05 if anim_ else 0.0
		tilt_ = sin(tn * 1.7 + pid_) * 0.3 if anim_ else 0.2
		hip_u_ = 0.3 * lh_
		sh_u_ = 0.5 * lh_
		head_u_ = 0.66 * lh_
		knee_s = [hip_s_ * 0.4, -hip_s_ * 0.4]
		knee_f = [0.03 * lh_, 0.03 * lh_]
		knee_u = [0.15 * lh_, 0.15 * lh_]
		hand_f = [0.0, 0.0]
		hand_s = [sh_s * 1.9, -sh_s * 1.9]
		hand_u = [sh_u_ - 0.22 * lh_, sh_u_ - 0.2 * lh_]
		elb_s = [sh_s * 1.6, -sh_s * 1.6]
		elb_u = [sh_u_ - 0.1 * lh_, sh_u_ - 0.1 * lh_]
		stars_ = true
		eyes_x_ = true
	elif mode_ == "startle":
		var hop_k: float = sin(PI * mode_age / 0.22) if anim_ and mode_age < 0.22 else 0.0
		jump_ = 0.09 * lh_ * hop_k
		sq = 1.0 + 0.12 * hop_k
		hip_u_ = 0.33 * lh_ + jump_
		sh_u_ = 0.54 * lh_ + jump_
		head_u_ = 0.71 * lh_ + jump_
		foot_u = [0.6 * jump_, 0.6 * jump_]
		knee_u = [0.0, 0.0]
		knee_f = [0.05 * lh_ * hop_k + 0.012 * lh_, 0.05 * lh_ * hop_k + 0.012 * lh_]
		hand_f = [0.02 * lh_, 0.02 * lh_]
		hand_s = [sh_s * 2.4, -sh_s * 2.4]
		hand_u = [sh_u_ + 0.12 * lh_, sh_u_ + 0.11 * lh_]
		elb_s = [sh_s * 2.0, -sh_s * 2.0]
		elb_u = [sh_u_ - 0.02 * lh_, sh_u_ - 0.02 * lh_]
		tilt_ = -0.08
	elif seated_:
		hip_u_ = 0.2 * lh_
		sh_u_ = 0.42 * lh_
		head_u_ = 0.58 * lh_
		lean_ = 0.01 * lh_
		knee_f = [0.13 * lh_, 0.13 * lh_]
		knee_u = [0.21 * lh_, 0.21 * lh_]
		knee_s = [hip_s_ * 2.4, -hip_s_ * 2.4]
		foot_f = [0.15 * lh_, 0.15 * lh_]
		foot_u = [0.0, 0.0]
		foot_s = [hip_s_ * 1.6, -hip_s_ * 1.6]
		hand_f = [0.12 * lh_, 0.12 * lh_]
		hand_s = [hip_s_ * 1.3, -hip_s_ * 1.3]
		hand_u = [0.22 * lh_, 0.22 * lh_]
		elb_f = [0.03 * lh_, 0.03 * lh_]
		elb_s = [sh_s * 1.5, -sh_s * 1.5]
		elb_u = [sh_u_ - 0.12 * lh_, sh_u_ - 0.12 * lh_]
		tilt_ = 0.05 * sin(tn * 1.1 + pid_)
		var nod: float = 0.004 * lh_ * sin(tn * 2.2 + pid_) if anim_ else 0.0
		head_u_ += nod
	elif moving_:
		var flee_ := mode_ == "flee"
		bob = 0.022 * lh_ * (1.0 - absf(sph)) * (1.4 if flee_ else 1.0)
		tilt_ = 0.5 * sph * 0.05
		hip_u_ = 0.33 * lh_ + bob
		sh_u_ = 0.53 * lh_ + bob
		head_u_ = 0.69 * lh_ + bob
		lean_ = 0.1 * lh_ if flee_ else 0.02 * lh_
		head_f = 0.07 * lh_ if flee_ else 0.01 * lh_
		for side in 2:
			var sg: float = 1.0 if side == 0 else -1.0
			var swing: float = sg * sph
			var lift: float = 0.075 * lh_ * maxf(0.0, sg * cph) * (1.3 if flee_ else 1.0)
			foot_f[side] = 0.17 * lh_ * amp * swing
			foot_u[side] = lift
			foot_s[side] = sg * hip_s_ * (1.15 + 2.2 * lift / lh_)
			knee_s[side] = sg * hip_s_ * (1.25 + 3.0 * lift / lh_)
			knee_f[side] = foot_f[side] * 0.5 + (0.07 * lh_ if lift > 0.0 else 0.012 * lh_)
			knee_u[side] = (hip_u_ + lift) * 0.5
			var aswing: float = -swing
			var carry: bool = side == 1 and hold_r
			if flee_:
				hand_f[side] = -0.02 * lh_ if carry else -0.1 * lh_ + 0.08 * lh_ * aswing
				hand_u[side] = sh_u_ - 0.17 * lh_ + 0.03 * lh_ * absf(aswing)
				hand_s[side] = sg * (sh_s + 0.06)
				elb_f[side] = hand_f[side] * 0.5 - 0.06 * lh_
				elb_s[side] = sg * (sh_s + 0.08)
				elb_u[side] = sh_u_ - 0.06 * lh_
			else:
				hand_f[side] = 0.1 * lh_ if carry else 0.15 * lh_ * amp * aswing
				hand_u[side] = sh_u_ - 0.2 * lh_ if carry else sh_u_ - 0.2 * lh_ + 0.015 * lh_ * absf(aswing)
				hand_s[side] = sg * (sh_s + 0.065 + (0.0 if carry else 0.03 * absf(aswing)))
				elb_f[side] = hand_f[side] * 0.4 - 0.01
				elb_s[side] = sg * (sh_s + 0.075 + 0.015 * absf(aswing))
				elb_u[side] = (sh_u_ + hand_u[side]) * 0.5 + 0.015
	else:
		var wary: bool = bool(e.get("wary", false))
		var shift: float = sin(tn * 0.9 + pid_ * 1.3) * 0.012 if anim_ else 0.0
		var breath: float = 0.004 * lh_ * sin(tn * 2.4 + pid_) if anim_ else 0.0
		f_sway = shift
		hip_u_ = 0.33 * lh_
		sh_u_ = 0.53 * lh_ + breath
		head_u_ = 0.69 * lh_ + breath
		tilt_ = 0.07 * sin(tn * 1.3 + pid_ * 1.7) if anim_ else 0.0
		lean_ = 0.03 * lh_ if wary else 0.0
		head_f = 0.03 * lh_ if wary else 0.0
		var scratch: bool = anim_ and not wary and (pid_ % 3 == 1) and sin(tn * 0.5 + pid_) > 0.55
		for side in 2:
			var sg: float = 1.0 if side == 0 else -1.0
			var carry: bool = side == 1 and hold_r
			if wary and not carry:
				hand_f[side] = 0.08 * lh_
				hand_s[side] = sg * 0.015 * bw
				hand_u[side] = sh_u_ - 0.16 * lh_
				elb_f[side] = 0.03 * lh_
				elb_s[side] = sg * (sh_s + 0.05)
				elb_u[side] = sh_u_ - 0.1 * lh_
			elif scratch and side == 0:
				hand_f[side] = 0.03 * lh_
				hand_s[side] = sg * 0.06 * bw
				hand_u[side] = head_u_ + 0.08 * lh_ + (0.01 * sin(tn * 6.0) if anim_ else 0.0)
				elb_f[side] = 0.02 * lh_
				elb_s[side] = sg * (sh_s + 0.12)
				elb_u[side] = sh_u_ + 0.02 * lh_
			else:
				hand_f[side] = 0.1 * lh_ if carry else 0.01 * sin(tn * 2.0 + side)
				hand_s[side] = sg * (sh_s + (0.075 if carry else 0.065))
				hand_u[side] = sh_u_ - 0.2 * lh_ if carry else sh_u_ - 0.2 * lh_ + 0.006 * sin(tn * 2.2 + side)
				elb_f[side] = hand_f[side] * 0.4 - 0.01
				elb_s[side] = sg * (sh_s + 0.075)
				elb_u[side] = (sh_u_ + hand_u[side]) * 0.5 + 0.015
	f_sy = sq
	f_sx = 1.0 / sq
	for side in 2:
		f_sr = sin(rel + yaw_l)
		f_cr = cos(rel + yaw_l)
		put(rs, 4 + side, 0.0, (1.0 if side == 0 else -1.0) * hip_s_, hip_u_)
		put(rs, 8 + side, foot_f[side], foot_s[side], foot_u[side])
		put(rs, 12 + side, knee_f[side], knee_s[side], knee_u[side] if knee_u[side] > 0.0 else (hip_u_ + foot_u[side]) * 0.5)
		f_sr = sin(rel + yaw_u)
		f_cr = cos(rel + yaw_u)
		put(rs, 2 + side, lean_, (1.0 if side == 0 else -1.0) * sh_s, sh_u_)
		put(rs, 6 + side, hand_f[side], hand_s[side], hand_u[side])
		put(rs, 10 + side, elb_f[side], elb_s[side], elb_u[side])
	put(rs, 14, lean_ * 0.5, 0.0, (sh_u_ + hip_u_) * 0.5)
	put(rs, 0, lean_ + head_f, head_s, head_u_)
	put(rs, 1, lean_, 0.0, sh_u_ + 0.02 * lh_)
	put(rs, 23, lean_ + head_f, head_s, head_u_ + 0.1 * lh_)
	var hr0: float = 0.088 * lh_ * sqrt(bw) * hs_
	var hry0: float = 0.092 * lh_ * vs_ * f_sy
	var head_kind_: String = lk["head"] if lk.get("head") is String and lk["head"] != "" else "round"
	var hr_: float = hr0 * 0.92 if head_kind_ == "egg" else (hr0 * 0.8 if head_kind_ == "long" else hr0)
	var hry_: float = hry0 * 1.15 if head_kind_ == "egg" else (hry0 * 1.3 if head_kind_ == "long" else (hry0 * 0.95 if head_kind_ == "square" else hry0))
	var body_kind_: String = lk["body"] if lk.get("body") is String and lk["body"] != "" else "bean"
	var body_rx_: float = ((0.095 if body_kind_ == "round" else (0.035 if body_kind_ == "stick" else (0.075 if body_kind_ == "box" else 0.07))) * bw * absf(f_cr) + 0.05 * absf(f_sr)) * hs_ * f_sx + 1.0
	var body_ry_: float = ((sh_u_ - hip_u_) * 0.5 + (0.06 if body_kind_ == "round" else 0.035) * lh_) * vs_ * f_sy
	var look_angle: float = float(e["lookAngle"]) if e.get("lookAngle") != null else 0.0
	var yaw: float = rel + look_angle
	var nose_x_: float = sin(yaw)
	var face_vis_: bool = cos(yaw) < 0.2
	var eyes_vis_: bool = cos(yaw) < -0.25
	var acc_: String = lk["acc"] if lk.get("acc") is String else ""
	var hat_: String = lk["hat"] if lk.get("hat") is String and lk["hat"] != "" else (acc_ if acc_ == "tophat" or acc_ == "nightcap" or acc_ == "bonnet" else "none")
	var flee2: bool = mode_ == "flee"
	var scarf_back: float = ((0.18 if flee2 else 0.1) + 0.03 * lag_a) if moving_ else 0.03
	put(rs, 15, -0.02 - scarf_back, 0.045 * bw, sh_u_ - (0.06 if flee2 else 0.16) * lh_ + (0.04 * lag_a if moving_ else 0.01 * sin(tn * 2.6)))
	put(rs, 16, -0.01 - scarf_back * 0.6, 0.04 * bw, sh_u_ - 0.05 * lh_)
	var hat_back: float = 0.12 if flee2 else ((0.1 + 0.04 * lag_a) if moving_ else 0.05)
	put(rs, 17, -hat_back, 0.1, head_u_ - 0.01 + (0.05 * lh_ if flee2 else 0.0))
	put(rs, 18, -0.02, 0.05, head_u_ + 0.15 * lh_)
	var coat_swing: float = 0.06 * lh_ * lag_a if moving_ else 0.0
	put(rs, 21, -0.03 * lh_ + coat_swing, hip_s_ * 1.6, hip_u_ - 0.17 * lh_)
	put(rs, 22, -0.03 * lh_ - coat_swing * 0.6, -hip_s_ * 1.6, hip_u_ - 0.17 * lh_)
	put(rs, 19, hand_f[1], hand_s[1], hand_u[1])
	if prop_ == "umbrella":
		put(rs, 20, hand_f[1] + 0.02 * lh_, hand_s[1] * 0.3, head_u_ + 0.26 * lh_)
	elif prop_ == "lantern":
		put(rs, 20, hand_f[1] + (0.04 * lag_a if moving_ else 0.01 * sin(tn * 1.9 + pid_)), hand_s[1] * 1.05, hand_u[1] - 0.09 * lh_)
	elif prop_ == "basket":
		put(rs, 20, hand_f[1], hand_s[1] * 1.1, hand_u[1] - 0.1 * lh_)
	else:
		put(rs, 20, hand_f[1] + 0.01 * lh_, hand_s[1] * 1.02, 0.0)
	var fig_px: float = 0.8 * lh_ * vs_
	var lod_: int = 0 if rs.quality < 1 else (2 if fig_px > 70.0 else (1 if fig_px > 34.0 else 0))
	var min_x_: float = X[0]
	var max_x_: float = X[0]
	for k in 24:
		if X[k] < min_x_:
			min_x_ = X[k]
		if X[k] > max_x_:
			max_x_ = X[k]
	min_x_ -= hr_ * 2.4 + 0.1 * hs_
	max_x_ += hr_ * 2.4 + 0.1 * hs_
	hip_u = hip_u_
	sh_u = sh_u_
	head_u = head_u_
	hr = hr_
	hry = hry_
	body_rx = body_rx_
	body_ry = body_ry_
	tilt = tilt_
	lean = lean_
	lod = lod_
	hs = hs_
	vs = vs_
	mode = mode_
	moving = moving_
	seated = seated_
	flee = flee2
	prop = prop_
	hat = hat_
	head_kind = head_kind_
	body_kind = body_kind_
	stars = stars_
	eyes_x = eyes_x_
	hands_over_head = hands_over
	jump = jump_
	nose_x = nose_x_
	face_vis = face_vis_
	eyes_vis = eyes_vis_
	g_jolt = g_jolt_
	min_x = min_x_
	max_x = max_x_
	hip_s = hip_s_
	lh = lh_
	look = lk
	acc = acc_
	pid = pid_
	t_n = tn
	anim = anim_
	sweeping = sweeping_
	dur = dur_
	sr = sin(rel)
	cr = cos(rel)
	return true
