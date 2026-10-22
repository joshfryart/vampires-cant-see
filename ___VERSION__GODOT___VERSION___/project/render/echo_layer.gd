class_name EchoLayer
extends RefCounted
## Ports drawPerson, drawEchoes, clippedDraw, drawGrabArms and drawSolo from js/render.js (line figures, effects 0).
## Draws onto a Canvas: the villager echoes are lit strip by strip as the sweep band passes, fade on their own
## afterglow, and are hidden behind walls by the per-column depth buffer rs.zbuf (as in JS clippedDraw).

const TWO_PI := JsMath.TWO_PI
const FLASH_AGE := 0.12
const COL_PERSON := [255, 107, 91]
const C_LOW := [91, 127, 214]
const C_HI := [242, 248, 255]
const COL_LOCK := "#ff8a78"


static func _round_js(x: float) -> int:
	return int(floor(x + 0.5))


## Sprite colour: base tinted pale at high brightness, cool blue at low (js spriteStyle).
static func sprite_style(base: Array, b: float) -> String:
	var k := 0.0
	var target: Array = C_HI
	if b > 0.5:
		k = 0.5 * minf(1.0, (b - 0.5) / 0.5)
		target = [255, 255, 255]
	else:
		k = 0.45 * (1.0 - b / 0.5)
		target = C_LOW
	return "rgb(%d,%d,%d)" % [_round_js(lerpf(base[0], target[0], k)), _round_js(lerpf(base[1], target[1], k)), _round_js(lerpf(base[2], target[2], k))]


## Run fn(canvas) once per run of columns spanning px x0..x1 not occluded by closer walls (js clippedDraw).
static func clipped_draw(rs: RenderState, c: Canvas, x0: float, x1: float, depth: float, fn: Callable) -> void:
	var a: int = maxi(0, int(floor(x0 / rs.col_w)))
	var b: int = mini(rs.cols - 1, int(floor(x1 / rs.col_w)))
	var run_start := -1
	var col: int = a
	while col <= b + 1:
		var vis: bool = col <= b and rs.zbuf[col] > depth
		if vis and run_start < 0:
			run_start = col
		if not vis and run_start >= 0:
			if run_start == a and col - 1 == b:
				fn.call(c)
			else:
				c.save()
				c.begin_path()
				c.rect(run_start * rs.col_w, 0, (col - run_start) * rs.col_w, rs.oh)
				c.clip()
				fn.call(c)
				c.restore()
			run_start = -1
		col += 1


## The vampire's own arms clamping the held victim's shoulders (js drawGrabArms).
static func draw_grab_arms(rs: RenderState, c: Canvas, p: Pose, hs: float, lw: float, alpha: float, jolt: float, t_n: float, pid: int, style: String, rs_k: float) -> void:
	var X := p.X
	var Y := p.Y
	var w: float = rs.ow
	var h: float = rs.oh
	var left: int = 2 if X[2] <= X[3] else 3
	var shake: float = jolt * hs * 0.05
	c.save()
	c.global_alpha = minf(1.0, alpha * 0.7)
	c.stroke_style = style
	for k in 2:
		var idx: int = left if k == 0 else 5 - left
		var sgn: float = -1.0 if k == 0 else 1.0
		var tx: float = X[idx] + (X[14] - X[idx]) * 0.35 * rs_k + sgn * hs * 0.03 + sin(t_n * 37.0 + k * 2.0 + pid) * shake
		var ty: float = Y[idx] + (Y[14] - Y[idx]) * 0.35 * rs_k + hs * 0.02 + cos(t_n * 29.0 + k * 3.0 + pid) * shake
		var sx: float = w * 0.5 + sgn * w * 0.3
		var sy: float = h + 12.0 * rs.wscale
		var cx: float = (sx + tx) * 0.5 + sgn * w * 0.1
		var cy: float = (sy + ty) * 0.5 + (sy - ty) * 0.05
		c.line_width = lw * (3.2 + 1.4 * rs_k)
		c.begin_path()
		c.move_to(sx, sy)
		c.quad_to(cx, cy, tx, ty)
		c.stroke()
		c.line_width = lw
		c.begin_path()
		var gr: float = maxf(2.0, hs * 0.012)
		c.arc(tx, ty, gr, 0.0, TWO_PI)
		for f in range(-1, 2):
			c.move_to(tx, ty - gr * 0.6)
			c.line_to(tx + f * gr * 0.9 - sgn * gr * 0.3, ty - gr * 2.0)
		c.stroke()
	c.restore()


## Ports drawPerson (js/render.js:2933) for the line figure. e: echo dictionary (see Pose.pose_person) with zMin, zMax.
## b = strength 0..1, age = seconds since the wavefront reached them (-1 = already lit). True when drawn.
static func draw_person(rs: RenderState, c: Canvas, p: Pose, player: Dictionary, tan_half: float, e: Dictionary, b: float, age: float, flash_white: bool, now: float, locked: bool) -> bool:
	if not p.pose_person(rs, player, tan_half, e, age, locked, now):
		return false
	var depth: float = p.depth
	var sweeping: bool = p.sweeping
	var dur: float = p.dur
	var alpha: float = minf(1.0, 1.15 * pow(b, 0.65)) / (1.0 + 0.07 * depth) * 1.25
	var lw: float = (1.5 if depth < 1.5 else 1.0) * rs.wscale
	var base_style: String
	if locked:
		if alpha < 0.9:
			alpha = 0.9
		lw = 1.6 * rs.wscale
		base_style = COL_LOCK
	elif flash_white and not (sweeping and rs.quality >= 1):
		var f: float = 1.0 - age / FLASH_AGE
		alpha = minf(1.0, alpha + 0.5 * f)
		lw += 0.5 * f * rs.wscale
		base_style = "#ffffff"
	else:
		base_style = sprite_style(COL_PERSON, b)
	c.stroke_style = base_style
	p.alpha = alpha
	p.lw = lw
	if p.max_x < -lw or p.min_x > rs.ow + lw:
		return false
	# Lit height band [zMin, zMax] from the pulse, and the sweeping band front.
	var z_min: float = float(e["zMin"]) if e.get("zMin") is float or e.get("zMin") is int else 0.0
	var z_max: float = float(e["zMax"]) if e.get("zMax") is float or e.get("zMax") is int else 2.0
	if z_max >= 1.15:
		z_max = 2.0
	var n_strips: int = Pose.STRIP_Z.size() - 1
	var strips: bool = sweeping and rs.quality >= 1
	var strip_a := PackedFloat32Array()
	strip_a.resize(n_strips)
	var lo := 1.0
	var hi := 0.0
	var front_strip := -1
	for s in n_strips:
		var zm: float = (Pose.STRIP_Z[s] + Pose.STRIP_Z[s + 1]) * 0.5
		var a: float = Ripple.mask_alpha(minf(zm, 1.1), z_min, z_max, 0.12)
		if strips:
			var local: float = age - (minf(zm, 1.25) / Pose.SWEEP_OVER) * Pose.SWEEP
			var g: float = 0.0 if local < 0.0 else Pose.glow(local, dur)
			a *= g
			if g > 0.0 and local < FLASH_AGE and front_strip < 0:
				front_strip = s
		elif age >= 0.0 and not locked:
			a *= Pose.glow(age, dur)
		strip_a[s] = a
		if strip_a[s] < lo:
			lo = strip_a[s]
		if strip_a[s] > hi:
			hi = strip_a[s]
	if hi < 0.02:
		return false
	var uniform: bool = hi - lo < 0.03 and front_strip < 0
	var lh: float = p.lh
	var to_y := func(z: float) -> float: return p.f_floor_y - z * Pose.FIG_H * lh * p.f_sy * p.vs
	var wrapped := func(cv: Canvas) -> void:
		if uniform:
			FigureLine.draw(cv, p, hi, base_style)
			return
		for s in n_strips:
			var sa: float = strip_a[s]
			if sa < 0.02:
				continue
			var za: float = Pose.STRIP_Z[s]
			var zb: float = Pose.STRIP_Z[s + 1]
			cv.save()
			cv.begin_path()
			var y_top: float = -50.0 if zb >= Pose.FIG_ZTOP - 1e-3 else to_y.call(zb)
			var y_bot: float = p.f_floor_y + 30.0 * rs.wscale if za <= 1e-3 else to_y.call(za)
			cv.rect(p.min_x, y_top, p.max_x - p.min_x, y_bot - y_top)
			cv.clip()
			FigureLine.draw(cv, p, sa, "#ffffff" if s == front_strip and not locked else base_style)
			cv.restore()
		# The band front: thin rings wrapping the body where the wave is right now.
		if strips and rs.quality >= 2 and age < Pose.SWEEP:
			var f2: float = (age / Pose.SWEEP) * Pose.SWEEP_OVER
			cv.stroke_style = "#ffffff"
			cv.line_width = maxf(1.0, lw * 0.9)
			for m in 3:
				var zn: float = f2 - m * 0.15
				if zn < 0.0 or zn > 1.05:
					continue
				var u: float = zn * p.f_h
				var rcx: float = p.f_cx + p.f_sway * u * p.hs + Pose.sweep_wave(zn, age) * 0.02 * p.hs
				var rad: float
				if u < p.hip_u:
					rad = p.hip_s * 1.3
				elif u < p.sh_u:
					rad = p.body_rx / p.hs / p.f_sx
				elif u < p.head_u - 0.06 * lh:
					rad = 0.04
				else:
					rad = p.hr / p.hs * 0.9
				var rx: float = rad * p.hs * 1.15
				var g2: float = (1.0 - age / Pose.SWEEP) * (1.0 - m * 0.3)
				cv.global_alpha = minf(1.0, alpha * g2 * 1.4)
				cv.begin_path()
				cv.ellipse(rcx, p.f_floor_y - u * p.f_sy * p.vs, rx, maxf(1.0, rx * 0.22), 0.0, 0.0, TWO_PI)
				cv.stroke()
	clipped_draw(rs, c, p.min_x - lw, p.max_x + lw, depth, wrapped)
	if locked:
		draw_grab_arms(rs, c, p, p.hs, lw, alpha, p.g_jolt, p.t_n, p.pid, base_style, rs.lock_rs)
	c.global_alpha = 1.0
	return true


## Ports drawEchoes (js/render.js:3816). echoes: Array of echo dictionaries; returns the number drawn.
static func draw_echoes(rs: RenderState, c: Canvas, p: Pose, echoes: Array, sonar_fade: float, t: float, player: Dictionary, tan_half: float) -> int:
	if echoes.is_empty():
		return 0
	var fade: float = sonar_fade if sonar_fade > 0.0 else 3.0
	var lock_id: int = rs.lock_id
	var newest := -1
	if lock_id >= 0:
		var bt := -INF
		for i in echoes.size():
			if int(echoes[i]["personId"]) == lock_id and float(echoes[i]["t"]) >= bt:
				bt = echoes[i]["t"]
				newest = i
	var n := 0
	for i in echoes.size():
		var e: Dictionary = echoes[i]
		var lk: bool = lock_id >= 0 and int(e["personId"]) == lock_id
		var age: float = t - float(e["t"])
		if lk:
			if i != newest:
				continue
			if draw_person(rs, c, p, player, tan_half, e, 0.9, -1.0, false, t, true):
				n += 1
			continue
		if not (age >= 0.0):
			continue
		var ef: float = float(e["fade"]) if e.get("fade") != null and float(e["fade"]) > 0.0 else fade
		var life: float = Pose.SWEEP + Pose.glow_dur(ef)
		if age >= life:
			continue
		var b: float = float(e["strength"]) if e.get("strength") != null else 1.0
		if b <= 0.01:
			continue
		if b > 1.0:
			b = 1.0
		if draw_person(rs, c, p, player, tan_half, e, b, age, age < FLASH_AGE, t, false):
			n += 1
	return n


## Tool/test hook (js drawSolo, effects 0): draw one echo with no world, nothing occludes it.
## o: {quality, t, age, b, player, lock {k, age, sp, rs}}.
static func draw_solo(rs: RenderState, c: Canvas, e: Dictionary, o: Dictionary) -> bool:
	var p := Pose.new()
	var tan_half: float = rs.tan_half()
	var player: Dictionary = o["player"] if o.has("player") else {"x": 0.0, "y": 0.0, "angle": 0.0}
	rs.horizon = rs.oh / 2.0
	rs.zbuf.fill(1e9)
	if o.has("quality"):
		rs.quality = int(o["quality"])
	var t: float = float(o["t"]) if o.has("t") else 0.0
	rs.update_boil(t)
	c.set_transform(1, 0, 0, 1, 0, 0)
	var lk: Variant = o.get("lock")
	if lk is Dictionary:
		rs.lock_id = int(e.get("personId", 0))
		rs.lock_k = float(lk["k"]) if lk.has("k") else 0.5
		rs.lock_age = float(lk["age"]) if lk.has("age") else 1.0
		rs.lock_sp = float(lk["sp"]) if lk.has("sp") else 9.0
		rs.lock_rs = float(lk["rs"]) if lk.has("rs") else 0.0
		return draw_person(rs, c, p, player, tan_half, e, 0.9, -1.0, false, t, true)
	rs.lock_id = -1
	var age: float = float(o["age"]) if o.has("age") else -1.0
	var b: float = float(o["b"]) if o.has("b") else 1.0
	return draw_person(rs, c, p, player, tan_half, e, b, age, age >= 0.0 and age < FLASH_AGE, t, false)
