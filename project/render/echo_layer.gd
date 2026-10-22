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
## Per-frame time allowed for volumetric figures (ms); past it the rest of the frame's villagers are line figures.
const FIG_BUDGET_MS := 2.5


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


## Nearest world light within 3 radii of the echo into o.rim_k / o.rim_side (k 0 = none). Steady, never flickers (js rimLight).
static func rim_light(rs: RenderState, e: Dictionary, player: Dictionary, o: FigureVolDraw.Opts) -> void:
	o.rim_k = 0.0
	o.rim_side = 1.0
	if rs.lights.is_empty():
		return
	var bd := INF
	var bl: Variant = null
	for l in rs.lights:
		var rad: float = float(l["radius"])
		if not (rad > 0.0):
			continue
		var d: float = sqrt((float(l["x"]) - e["x"]) * (float(l["x"]) - e["x"]) + (float(l["y"]) - e["y"]) * (float(l["y"]) - e["y"]))
		if d < 3.0 * rad and d < bd:
			bd = d
			bl = l
	if bl == null:
		return
	o.rim_k = maxf(0.0, minf(1.0, 1.0 - bd / (3.0 * float(bl["radius"]))))
	var s: float = (float(bl["x"]) - e["x"]) * -sin(player["angle"]) + (float(bl["y"]) - e["y"]) * cos(player["angle"])
	o.rim_side = -1.0 if s < 0.0 else 1.0


## Capsule radius (px) of the figure at height u, for the band-front rings when no silhouette row is found.
static func vol_ring_rx(p: Pose, u: float) -> float:
	var lk: Dictionary = p.look
	var sho: float = clampf(float(lk["shoulder"]), 0.8, 1.25) if (lk.get("shoulder") is float or lk.get("shoulder") is int) else 1.0
	var bwv: float = float(lk["build"]) if (lk.get("build") is float or lk.get("build") is int) else 1.0
	var asr: float = absf(p.sr)
	var X := p.X
	var hw: float = absf(X[4] - X[5]) * 0.5
	if u < p.hip_u:
		return (hw + 0.045 * bwv * p.lh * p.hs) * 1.05
	if u < p.sh_u:
		var sw: float = absf(X[2] - X[3]) * 0.5 * sho + 0.05 * p.hs * asr
		var hw2: float = hw * 1.1 + 0.035 * p.hs * asr
		return (hw2 + (sw - hw2) * ((u - p.hip_u) / maxf(1e-6, p.sh_u - p.hip_u))) * 1.05
	if u < p.head_u - 0.06 * p.lh:
		return 0.022 * p.lh * p.hs * 1.3
	return p.hr * 0.95


## Ports drawPerson (js/render.js:2933). e: echo dictionary (see Pose.pose_person) with zMin, zMax.
## b = strength 0..1, age = seconds since the wavefront reached them (-1 = already lit). True when drawn.
static func draw_person(rs: RenderState, c: Canvas, p: Pose, player: Dictionary, tan_half: float, e: Dictionary, b: float, age: float, flash_white: bool, now: float, locked: bool) -> bool:
	# Volumetric figure: effects >= 1, quality >= 1, nearer than FIG_VOL_DEPTH (checked in pose_person), within the frame
	# budget. The held victim is exempt from the budget cut.
	var vol_want: bool = rs.fx >= 1 and rs.quality >= 1 and (locked or not (rs.fig_ms > rs.fig_budget))
	if not p.pose_person(rs, player, tan_half, e, age, locked, now, vol_want):
		return false
	var vol: bool = p.vol
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
		# Outline gone, but the circulatory wave may still be travelling to the hands and feet (vessels on only).
		if e.get("kind") == "vheart" and not locked and VesselDraw.on() and age >= 0.0 and age < VesselDraw.life(float(e.get("bpm", 0.0)), rs.reduced):
			var nv: int = VesselDraw.draw_seen(rs, c, p, e, age, p.min_x - lw, p.max_x + lw, depth, player)
			c.global_alpha = 1.0
			return nv > 0
		return false
	var uniform: bool = hi - lo < 0.03 and front_strip < 0
	var lh: float = p.lh
	var fo := FigureVolDraw.Opts.new()
	var eo := FigureVolDraw.Opts.new()
	var vol_t0 := 0
	var look: Dictionary = p.look
	if vol:
		fo.fx = rs.fx
		fo.lw = lw
		fo.alpha = alpha
		fo.depth = depth
		fo.reduced = rs.reduced
		rim_light(rs, e, player, fo)
		eo.lw = lw
		eo.alpha = alpha
		vol_t0 = Time.get_ticks_usec()
		rs.fig_vol += 1
	else:
		rs.fig_line += 1
	var draw_fig := func(cv: Canvas, sa: float, style: String) -> void:
		if vol:
			FigureVolDraw.draw(cv, sa, style, p, look, fo)
			eo.sa = sa
			eo.style = style
			FigureVolDraw.draw_extras(cv, p, look, eo)
		else:
			FigureLine.draw(cv, p, sa, style)
	var span := PackedFloat64Array([0.0, 0.0])
	var to_y := func(z: float) -> float: return p.f_floor_y - z * Pose.FIG_H * lh * p.f_sy * p.vs
	var wrapped := func(cv: Canvas) -> void:
		if uniform:
			draw_fig.call(cv, hi, base_style)
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
			draw_fig.call(cv, sa, "#ffffff" if s == front_strip and not locked else base_style)
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
				var rx: float
				if vol:
					# The ring hugs the volumetric silhouette at this height, else a radius estimate.
					var ry: float = p.f_floor_y - u * p.f_sy * p.vs
					if FigureVol.span_at(p, look, ry, span):
						rx = (span[1] - span[0]) * 0.5 * 1.08 + lw
						rcx = (span[0] + span[1]) * 0.5
					else:
						rx = vol_ring_rx(p, u)
				else:
					var rad: float
					if u < p.hip_u:
						rad = p.hip_s * 1.3
					elif u < p.sh_u:
						rad = p.body_rx / p.hs / p.f_sx
					elif u < p.head_u - 0.06 * lh:
						rad = 0.04
					else:
						rad = p.hr / p.hs * 0.9
					rx = rad * p.hs * 1.15
				var g2: float = (1.0 - age / Pose.SWEEP) * (1.0 - m * 0.3)
				cv.global_alpha = minf(1.0, alpha * g2 * 1.4)
				cv.begin_path()
				cv.ellipse(rcx, p.f_floor_y - u * p.f_sy * p.vs, rx, maxf(1.0, rx * 0.22), 0.0, 0.0, TWO_PI)
				cv.stroke()
	clipped_draw(rs, c, p.min_x - lw, p.max_x + lw, depth, wrapped)
	if vol:
		rs.fig_ms += (Time.get_ticks_usec() - vol_t0) / 1000.0
	# Circulatory overlay: after the outline, not limited to the chest strip (the outline stays chest-only).
	if e.get("kind") == "vheart" and not locked and VesselDraw.on():
		VesselDraw.draw_seen(rs, c, p, e, age, p.min_x - lw, p.max_x + lw, depth, player)
	# Held victim: the vessels beat with the drink pulse (the echo is rebuilt each beat, so its age is the beat age).
	if locked and e.get("vessel") is Dictionary and VesselDraw.on():
		var ve: Dictionary = (e["vessel"] as Dictionary).duplicate()
		ve["kind"] = "vheart"
		ve["x"] = e["x"]
		ve["y"] = e["y"]
		ve["strength"] = 1.0
		VesselDraw.draw_seen(rs, c, p, ve, maxf(0.0, now - float(e["t"])), p.min_x - lw, p.max_x + lw, depth, player)
	if locked:
		if rs.fx >= 1:
			FigureVolDraw.draw_grab_arms_vol(c, rs.ow, rs.oh, rs.wscale, p.X, p.Y, p.hs, lw, alpha, p.g_jolt, p.t_n, p.pid, base_style, rs.lock_rs)
		else:
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
	rs.lights = o.get("lights", [])
	rs.tch.fill(0)
	rs.vessel_nodes = 0
	rs.vessel_heart = 0.0
	rs.vessel_feet = 0.0
	rs.fx = int(clampi(int(round(float(o["fx"]))), 0, 2)) if o.has("fx") else rs.fx
	rs.fig_ms = 0.0
	rs.fig_vol = 0
	rs.fig_line = 0
	rs.fig_budget = 1e9
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
