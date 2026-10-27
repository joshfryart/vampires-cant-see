class_name FigureLine
extends RefCounted
## Ports drawLineFigure and squareHead from js/render.js: the classic hand-drawn line figure (effects 0).
## Reads the pose written by Pose.pose_person (X/Y slots and the pose fields) and strokes it onto a Canvas.

const TWO_PI := JsMath.TWO_PI


static func square_head(c: Canvas, x: float, y: float, rx: float, ry: float, rot: float) -> void:
	var cr: float = cos(rot)
	var sr: float = sin(rot)
	var pt := func(px: float, py: float) -> Array: return [x + px * cr - py * sr, y + px * sr + py * cr]
	var k := 0.55
	var a: Array = pt.call(-rx * k, -ry)
	var b: Array = pt.call(rx * k, -ry)
	var c2: Array = pt.call(rx, -ry * k)
	var d: Array = pt.call(rx, ry * k)
	var e: Array = pt.call(rx * k, ry)
	var f: Array = pt.call(-rx * k, ry)
	var g: Array = pt.call(-rx, ry * k)
	var h: Array = pt.call(-rx, -ry * k)
	var tr: Array = pt.call(rx, -ry)
	var br: Array = pt.call(rx, ry)
	var bl: Array = pt.call(-rx, ry)
	var tl: Array = pt.call(-rx, -ry)
	c.move_to(a[0], a[1])
	c.line_to(b[0], b[1])
	c.quad_to(tr[0], tr[1], c2[0], c2[1])
	c.line_to(d[0], d[1])
	c.quad_to(br[0], br[1], e[0], e[1])
	c.line_to(f[0], f[1])
	c.quad_to(bl[0], bl[1], g[0], g[1])
	c.line_to(h[0], h[1])
	c.quad_to(tl[0], tl[1], a[0], a[1])


## Ports drawLineFigure (js/render.js:2653). sa = strip alpha, style = stroke colour.
static func draw(c: Canvas, p: Pose, sa: float, style: String, ink: bool = false) -> void:
	var X := p.X
	var Y := p.Y
	var hip_u: float = p.hip_u
	var sh_u: float = p.sh_u
	var head_u: float = p.head_u
	var hr: float = p.hr
	var hry: float = p.hry
	var body_rx: float = p.body_rx
	var body_ry: float = p.body_ry
	var tilt: float = p.tilt
	var lod: int = p.lod
	var hs: float = p.hs
	var vs: float = p.vs
	var mode: String = p.mode
	var seated: bool = p.seated
	var flee: bool = p.flee
	var prop: String = p.prop
	var hat: String = p.hat
	var head_kind: String = p.head_kind
	var body_kind: String = p.body_kind
	var stars: bool = p.stars
	var eyes_x: bool = p.eyes_x
	var hands_over_head: bool = p.hands_over_head
	var jump: float = p.jump
	var nose_x: float = p.nose_x
	var face_vis: bool = p.face_vis
	var eyes_vis: bool = p.eyes_vis
	var look: Dictionary = p.look
	var acc: String = p.acc
	var pid: int = p.pid
	var t_n: float = p.t_n
	var anim: bool = p.anim
	var alpha: float = p.alpha
	var lw: float = p.lw
	var lh: float = p.lh
	var bw: float = float(look["build"]) if look.get("build") is float or look.get("build") is int else 1.0
	var moving: bool = p.moving
	c.global_alpha = minf(1.0, alpha * sa)
	c.stroke_style = style
	if ink:
		# Ink: head and torso carry the near-black fill under the outline (the square head and box/pear torsos use their ellipse bounds).
		c.begin_path()
		c.ellipse(X[0], Y[0], hr, hry, tilt * 0.6, 0.0, TWO_PI)
		LineStyle.fill_silhouette(c, true)
		c.begin_path()
		c.ellipse(X[14], Y[14], body_rx, body_ry, -tilt * 0.4, 0.0, TWO_PI)
		LineStyle.fill_silhouette(c, true)
	# Limbs: single thicker hose lines with round caps (no hinges).
	c.line_width = lw * LineStyle.limb_mul(ink)
	c.begin_path()
	for side in 2:
		c.move_to(X[4 + side], Y[4 + side])
		c.quad_to(X[12 + side], Y[12 + side], X[8 + side], Y[8 + side])
		c.move_to(X[2 + side], Y[2 + side])
		c.quad_to(X[10 + side], Y[10 + side], X[6 + side], Y[6 + side])
	if prop == "cane" and mode != "fed":
		c.move_to(X[19], Y[19])
		c.line_to(X[20], Y[20])
	c.stroke()
	# Outlines: head, torso, shoes, gloves, face, hair, hat, coat, scarf, prop.
	c.line_width = lw
	c.begin_path()
	var hx: float = X[0]
	var hy: float = Y[0]
	if head_kind == "square":
		square_head(c, hx, hy, hr, hry, tilt * 0.6)
	else:
		c.move_to(hx + hr, hy)
		c.ellipse(hx, hy, hr, hry, tilt * 0.6, 0.0, TWO_PI)
	var bx: float = X[14]
	var by: float = Y[14]
	if body_kind == "box":
		c.move_to(bx - body_rx, by - body_ry)
		c.quad_to(bx, by - body_ry * 1.1, bx + body_rx, by - body_ry)
		c.quad_to(bx + body_rx * 1.2, by, bx + body_rx * 1.05, by + body_ry)
		c.quad_to(bx, by + body_ry * 1.1, bx - body_rx * 1.05, by + body_ry)
		c.quad_to(bx - body_rx * 1.2, by, bx - body_rx, by - body_ry)
	elif body_kind == "pear":
		c.move_to(bx - body_rx * 0.7, by - body_ry)
		c.quad_to(bx, by - body_ry * 1.15, bx + body_rx * 0.7, by - body_ry)
		c.quad_to(bx + body_rx * 1.4, by + body_ry * 0.3, bx + body_rx * 1.1, by + body_ry)
		c.quad_to(bx, by + body_ry * 1.25, bx - body_rx * 1.1, by + body_ry)
		c.quad_to(bx - body_rx * 1.4, by + body_ry * 0.3, bx - body_rx * 0.7, by - body_ry)
	else:
		c.move_to(bx + body_rx, by)
		c.ellipse(bx, by, body_rx, body_ry, -tilt * 0.4, 0.0, TWO_PI)
	if body_kind == "stick" and lod >= 1:
		c.move_to(bx - body_rx * 1.6, by + body_ry * 0.3)
		c.quad_to(bx, by + body_ry * 0.55, bx + body_rx * 1.6, by + body_ry * 0.3)
	for side in 2:
		var shoe_r: float = hs * (0.032 + 0.03 * absf(p.f_sr)) * p.f_sx + 1.0
		var shoe_y: float = maxf(1.2, vs * 0.02 * p.f_sy)
		c.move_to(X[8 + side] + shoe_r, Y[8 + side])
		c.ellipse(X[8 + side] + p.f_sr * hs * 0.03, Y[8 + side], shoe_r, shoe_y, 0.0, 0.0, TWO_PI)
		if lod >= 2:
			var hr2: float = maxf(1.3, hs * 0.02)
			c.move_to(X[6 + side] + hr2, Y[6 + side])
			c.arc(X[6 + side], Y[6 + side], hr2, 0.0, TWO_PI)
	if lod >= 1 and face_vis:
		var nz: float = float(look["nose"]) if look.get("nose") is float or look.get("nose") is int else 1.0
		c.move_to(hx + nose_x * hr * 0.55, hy + hry * 0.12)
		c.line_to(hx + nose_x * hr * (0.75 + 0.25 * nz), hy + hry * (0.2 + 0.14 * nz))
		if look.get("beard") == true and lod >= 2:
			c.move_to(hx - hr * 0.55, hy + hry * 0.55)
			c.line_to(hx - hr * 0.3, hy + hry * 1.1)
			c.line_to(hx, hy + hry * 0.8)
			c.line_to(hx + hr * 0.3, hy + hry * 1.1)
			c.line_to(hx + hr * 0.55, hy + hry * 0.55)
	if lod >= 1 and eyes_vis:
		for side in [-1, 1]:
			var ex: float = hx + side * hr * 0.4 + nose_x * hr * 0.2
			if eyes_x:
				var q: float = maxf(1.2, hr * 0.14)
				c.move_to(ex - q, hy - hry * 0.2)
				c.line_to(ex + q, hy)
				c.move_to(ex + q, hy - hry * 0.2)
				c.line_to(ex - q, hy)
			else:
				c.move_to(ex, hy - hry * 0.2)
				c.line_to(ex, hy - hry * 0.02)
	# Hair (only when no hat hides it).
	var hair: String = str(look.get("hair", "none")) if hat == "none" or hat == "cap" or hat == "bonnet" else "none"
	if lod >= 1 and hair != "" and hair != "none":
		var ty: float = hy - hry
		if hair == "tuft":
			for k in range(-1, 2):
				c.move_to(hx + k * hr * 0.3, ty + hry * 0.08)
				c.line_to(hx + k * hr * 0.45 + hr * 0.12, ty - hry * 0.28)
		elif hair == "bun":
			var bxr: float = hx - nose_x * hr * 0.5
			var br2: float = maxf(1.5, hr * 0.32)
			c.move_to(bxr + br2, ty - hry * 0.05)
			c.arc(bxr, ty - hry * 0.05, br2, 0.0, TWO_PI)
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
				c.arc(cxr, ty + hry * 0.05, rr, 0.0, TWO_PI)
		elif hair == "bob":
			c.move_to(hx - hr * 1.05, hy + hry * 0.5)
			c.quad_to(hx - hr * 1.15, ty - hry * 0.1, hx, ty - hry * 0.15)
			c.quad_to(hx + hr * 1.15, ty - hry * 0.1, hx + hr * 1.05, hy + hry * 0.5)
	# Hats (a fed villager's hat lies on the floor beside them).
	var fed_hat: bool = mode == "fed" and hat != "hood"
	var hhx: float = X[9] + hr * 2.6 if fed_hat else X[0]
	var hhy: float = p.f_floor_y - hry * 0.35 if fed_hat else Y[0]
	var hat_tilt: float = 0.9 if fed_hat else tilt
	if hat == "tophat":
		var hy2: float = hhy - hry * 0.78
		var bw2: float = hr * 1.25
		var th: float = vs * 0.14 * lh * p.f_sy
		var lean2: float = hat_tilt * th * 1.2 + (-hr * 0.6 if flee else 0.0)
		var lift: float = -th * 0.35 if flee else (-jump * vs * 0.8 if jump > 0.0 else 0.0)
		c.move_to(hhx + bw2, hy2 + lift)
		c.ellipse(hhx, hy2 + lift, bw2, maxf(1.2, vs * 0.012), 0.0, 0.0, TWO_PI)
		c.move_to(hhx - hr * 0.78, hy2 + lift)
		c.line_to(hhx - hr * 0.7 + lean2, hy2 - th + lift)
		c.line_to(hhx + hr * 0.7 + lean2, hy2 - th + lift)
		c.line_to(hhx + hr * 0.78, hy2 + lift)
		c.move_to(hhx - hr * 0.77 + lean2 * 0.2, hy2 - th * 0.22 + lift)
		c.line_to(hhx + hr * 0.77 + lean2 * 0.2, hy2 - th * 0.22 + lift)
	elif hat == "nightcap":
		var hy2n: float = hhy - hry * 0.7
		c.move_to(hhx - hr * 0.95, hy2n + hry * 0.2)
		c.quad_to(X[18], Y[18] - hry * 0.4, X[17], Y[17] - hry * 0.2)
		c.quad_to(hhx + hr * 0.3, hy2n - hry * 0.2, hhx + hr * 0.95, hy2n + hry * 0.2)
		var pr: float = maxf(1.5, hs * 0.022)
		c.move_to(X[17] + pr, Y[17] - hry * 0.2)
		c.arc(X[17], Y[17] - hry * 0.2, pr, 0.0, TWO_PI)
		c.move_to(hhx - hr * 0.95, hy2n + hry * 0.2)
		c.line_to(hhx + hr * 0.95, hy2n + hry * 0.2)
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
		var tyc: float = hhy - hry * 0.55
		var liftc: float = -jump * vs * 0.6 if jump > 0.0 else 0.0
		c.move_to(hhx - hr * 1.05, tyc + liftc)
		c.quad_to(hhx, tyc - hry * 0.75 + liftc, hhx + hr * 1.05, tyc + liftc)
		c.move_to(hhx - hr * 1.05, tyc + liftc)
		c.line_to(hhx + hr * 1.05, tyc + liftc)
		var bdir: float = 1.0 if nose_x >= 0.0 else -1.0
		c.move_to(hhx + bdir * hr * 0.9, tyc + liftc)
		c.line_to(hhx + bdir * hr * 1.45 + nose_x * hr * 0.1, tyc + hry * 0.12 + liftc)
	elif hat == "hood":
		var tyh: float = hhy - hry
		c.move_to(X[2] - hr * 0.2, Y[2])
		c.quad_to(hhx - hr * 1.35, hhy - hry * 0.2, hhx - hr * 0.2 + (-hr * 0.3 if moving else 0.0), tyh - hry * 0.45)
		c.quad_to(hhx + hr * 1.35, hhy - hry * 0.2, X[3] + hr * 0.2, Y[3])
	# Coat hem.
	if lod >= 1 and look.get("coat") == true and mode != "fed":
		var cy0: float = by + body_ry * 0.35
		c.move_to(bx + body_rx * 0.98, cy0)
		c.quad_to(X[21] + body_rx * 0.2, (cy0 + Y[21]) * 0.5, X[21] + body_rx * 0.1, Y[21])
		c.quad_to((X[21] + X[22]) * 0.5, Y[21] + vs * 0.02, X[22] - body_rx * 0.1, Y[22])
		c.quad_to(X[22] - body_rx * 0.2, (cy0 + Y[22]) * 0.5, bx - body_rx * 0.98, cy0)
	# Seated: the edge of the bench or stool under them.
	if seated:
		var sw: float = hs * 0.26 * bw
		c.move_to(X[14] - sw, Y[4] + vs * 0.01)
		c.line_to(X[14] + sw, Y[5] + vs * 0.01)
	# Scarf.
	if acc == "scarf":
		var nyy: float = Y[1] - body_ry * 0.1
		c.move_to(X[1] - body_rx * 0.8, nyy)
		c.quad_to(X[1], nyy + hry * 0.5, X[1] + body_rx * 0.8, nyy)
		c.move_to(X[1] + body_rx * 0.55, nyy + hry * 0.15)
		c.quad_to(X[16], Y[16], X[15], Y[15])
	# Props carried in the right hand.
	if prop == "cane" and mode != "fed":
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
		var ux: float = X[20]
		var uy: float = Y[20]
		var uw: float = hr * 2.6
		c.move_to(X[19], Y[19])
		c.line_to(ux, uy)
		c.move_to(ux - uw, uy + hry * 0.9)
		c.quad_to(ux, uy - hry * 1.2, ux + uw, uy + hry * 0.9)
		for k in 3:
			var x0: float = ux - uw + (k * 2.0 * uw) / 3.0
			var x1: float = x0 + (2.0 * uw) / 3.0
			c.move_to(x0, uy + hry * 0.9)
			c.quad_to((x0 + x1) * 0.5, uy + hry * 1.25, x1, uy + hry * 0.9)
	# Hands over the head (cower): small fingers.
	if hands_over_head and lod >= 2:
		for side in 2:
			c.move_to(X[6 + side], Y[6 + side])
			c.line_to(X[6 + side] + (-1.0 if side == 1 else 1.0) * hr * 0.3, Y[6 + side] - hry * 0.25)
	c.stroke()
	# Dazed: three little stars circling the head (0.4 Hz).
	if stars:
		c.begin_path()
		var rr2: float = maxf(1.2, hr * 0.13)
		for k in 3:
			var a: float = (t_n * 2.5 if anim else 0.0) + k * 2.094 + pid
			var sx: float = X[23] + cos(a) * hr * 1.7
			var sy: float = Y[23] - hry * 0.25 + sin(a) * hry * 0.35
			c.move_to(sx - rr2, sy)
			c.line_to(sx + rr2, sy)
			c.move_to(sx, sy - rr2)
			c.line_to(sx, sy + rr2)
		c.stroke()
