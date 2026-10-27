class_name Sprites
extends RefCounted
## Ports drawSprite (crypt coffin, safe diamond, open doorway) and drawProps (gravestone, cross, barrel, table, chair, bench,
## well, torch, brazier, plus the roguelike stalagmite, stalactite, coffin, glowworm, stump, boulder, haybale, scarecrow, shrine) from js/render.js onto a Canvas. Lit only while a wavefront passes, with the height band mask on props.

const TWO_PI := JsMath.TWO_PI
const FLASH_AGE := 0.12
const COL_CRYPT := [178, 140, 255]
const COL_SAFE := [140, 122, 217]
const COL_DOOR_OPEN := [255, 226, 196]
const COL_PROP := [200, 214, 236]
const COL_FLAME := "rgb(255,176,64)"
const PROP_MAX_DIST := 12.0
static var _pc_world: int = 0
static var _pc_n: int = -1
static var _pc_xy: PackedFloat64Array = PackedFloat64Array()
const FIRE_Z := [0.3, 0.95, 0.5]
const PROP_DEF := {
	"gravestone": {"zc": 0.2, "top": 0.4, "fire": false},
	"cross": {"zc": 0.3, "top": 0.64, "fire": false},
	"barrel": {"zc": 0.22, "top": 0.46, "fire": false},
	"table": {"zc": 0.2, "top": 0.4, "fire": false},
	"chair": {"zc": 0.22, "top": 0.52, "fire": false},
	"bench": {"zc": 0.2, "top": 0.4, "fire": false},
	"well": {"zc": 0.3, "top": 0.86, "fire": false},
	"torch": {"zc": 0.72, "top": 0.85, "fire": true},
	"brazier": {"zc": 0.45, "top": 0.78, "fire": true},
	"stalagmite": {"zc": 0.3, "top": 0.7, "fire": false},
	"stalactite": {"zc": 0.85, "top": 1.0, "fire": false},
	"coffin": {"zc": 0.4, "top": 0.88, "fire": false},
	"glowworm": {"zc": 0.9, "top": 1.0, "fire": false},
	"stump": {"zc": 0.14, "top": 0.28, "fire": false},
	"boulder": {"zc": 0.2, "top": 0.4, "fire": false},
	"haybale": {"zc": 0.15, "top": 0.3, "fire": false},
	"scarecrow": {"zc": 0.45, "top": 0.9, "fire": false},
	"shrine": {"zc": 0.3, "top": 0.62, "fire": false},
}


## Line alpha from brightness and distance (depth cue; js lineAlpha).
static func line_alpha(b: float, dist: float) -> float:
	return minf(1.0, 1.15 * pow(b, 0.65)) / (1.0 + 0.12 * dist)


## Brightness multiplier for a surface struck age seconds ago, replacing the sonar's long fade (js glowMul).
static func glow_mul(age: float, fade: float) -> float:
	var g: float = Pose.glow(age, Pose.glow_dur(fade))
	if g <= 0.0:
		return 0.0
	var f: float = fade if fade > 0.0 else 3.0
	var kf: float = 1.0 - age / f
	return g / (kf * kf) if kf > 0.05 else g


## js litAt3: brightness/age/fade/index of the strongest pulse at (x, y, z) with the afterglow applied: [b, age, fade, idx].
static func lit_at3(sonar: Sonar, x: float, y: float, z: float, t: float) -> Array:
	var b := 0.0
	if sonar.pulses.size() > 0:
		b = sonar.scan(x, y, z, t)
	var out: Array = [0.0, -1.0, 0.0, -1.0]
	if b > 0.0:
		out = [b, sonar.scan_age, sonar.scan_fade, float(sonar.scan_idx)]
		b *= glow_mul(out[1], out[2])
		out[0] = b
		if b <= 0.0:
			out[1] = -1.0
	return out


## js project(): [fwd, sx] or an empty array when behind the camera.
static func project(player: Dictionary, x: float, y: float, half_w: float, tan_half: float) -> Array:
	var dx: float = x - player["x"]
	var dy: float = y - player["y"]
	var ca: float = cos(player["angle"])
	var sa: float = sin(player["angle"])
	var fwd: float = dx * ca + dy * sa
	var right: float = -dx * sa + dy * ca
	if fwd <= 0.1:
		return []
	return [fwd, half_w + (right / fwd) * (half_w / tan_half)]


## Horizontal ripple band lines (white) between xl..xr at normalised heights for a marker (js bandLines).
static func band_lines(c: Canvas, xl: float, xr: float, floor_y: float, hpx: float, age: float, alpha: float) -> void:
	var f := RippleFx.band_front(age)
	if f < 0.0:
		return
	c.stroke_style = "#ffffff"
	c.line_width = 1.0
	for m in 3:
		var u: float = f - m * 0.16
		if u < 0.0 or u > 1.0:
			continue
		c.global_alpha = minf(1.0, alpha * (1.0 - age / RippleFx.BAND_DUR) * (1.0 - m * 0.3) * 1.4)
		var y: float = floor_y - u * hpx
		c.begin_path()
		c.move_to(xl, y)
		c.quad_to((xl + xr) / 2.0, y + hpx * 0.04, xr, y)
		c.stroke()


## Draw one outlined marker sprite (wobbly coffin, bouncy diamond, crooked doorway); true when drawn.
static func draw_sprite(rs: RenderState, c: Canvas, world: World, player: Dictionary, sonar: Sonar, t: float, kind: String, spot: Dictionary, tan_half: float) -> bool:
	var half_w: float = rs.ow / 2.0
	var sx_: float = spot["x"]
	var sy_: float = spot["y"]
	if kind == "doors":
		if not world.is_door_open(sx_, sy_):
			return false
	var pj := project(player, sx_, sy_, half_w, tan_half)
	if pj.is_empty():
		return false
	var depth: float = pj[0]
	var cx: float = pj[1]
	var zc: float = 0.3 if kind == "safe" else (0.45 if kind == "doors" else 0.18)
	var lit := lit_at3(sonar, sx_, sy_, zc, t)
	var b: float = lit[0]
	if b <= 0.01:
		return false
	var age: float = lit[1]
	var horizon: float = rs.horizon
	var vs: float = rs.oh / depth
	var hs: float = half_w / tan_half / depth
	var floor_y: float = horizon + 0.5 * vs
	var flash: bool = age >= 0.0 and age < FLASH_AGE
	var rip: bool = age >= 0.0 and age < RippleFx.BAND_DUR and rs.quality >= 1
	var ink: bool = LineStyle.ink_for(rs)
	var alpha: float = LineStyle.ping_lit(b, depth, ink) * 1.2
	var lw: float = LineStyle.contour_width(depth, ink, rs.wscale)
	var idb: int = int(sx_ * 7.0 + sy_ * 13.0) * 24
	var a_j: float = LineStyle.boil_amp(ink, rs.wscale)
	var base: Array
	var c0: float
	var c1: float
	var shape: Callable
	# the flash tints and thickens before the shape runs (js closes over alpha/lw, which the flash edits afterwards)
	var flash_alpha: float = alpha
	var flash_lw: float = lw
	if flash:
		var f: float = 1.0 - age / FLASH_AGE
		flash_alpha = minf(1.0, alpha + 0.5 * f)
		flash_lw = LineStyle.flash_width(lw, f, rs.wscale)
	alpha = flash_alpha
	lw = flash_lw
	if kind == "safe":
		base = COL_SAFE
		var hop: float = absf(sin(t * 3.2 + sx_))
		var land: float = (1.0 - hop) * (1.0 - hop) * (1.0 - hop)
		var sy: float = 1.08 - 0.3 * land
		var sx: float = 1.0 / sy
		var hov: float = 0.2 + 0.12 * hop
		var dh: float = 0.17 * vs * sy
		var dw: float = 0.12 * hs * sx
		var my: float = floor_y - hov * vs
		var grow: float = 1.0 + 0.9 * (age / RippleFx.BAND_DUR) if rip else 1.0
		c0 = cx - dw * 2.0 - 10.0
		c1 = cx + dw * 2.0 + 10.0
		shape = func(cv: Canvas) -> void:
			cv.begin_path()
			cv.move_to(cx + rs.j(idb + 0, 0) * a_j, my - dh + rs.j(idb + 0, 1) * a_j)
			cv.line_to(cx + dw + rs.j(idb + 1, 0) * a_j, my + rs.j(idb + 1, 1) * a_j)
			cv.line_to(cx + rs.j(idb + 2, 0) * a_j, my + dh + rs.j(idb + 2, 1) * a_j)
			cv.line_to(cx - dw + rs.j(idb + 3, 0) * a_j, my + rs.j(idb + 3, 1) * a_j)
			cv.close_path()
			LineStyle.fill_silhouette(cv, ink)
			cv.move_to(cx - dw * 0.35, my - dh * 0.25)
			cv.line_to(cx - dw * 0.1, my - dh * 0.55)
			cv.stroke()
			cv.global_alpha = minf(1.0, alpha * 0.6)
			cv.begin_path()
			var sw: float = dw * (1.1 - 0.4 * hop)
			cv.ellipse(cx, floor_y, sw, maxf(1.0, sw * 0.22), 0.0, 0.0, TWO_PI)
			cv.stroke()
			cv.global_alpha = minf(1.0, alpha)
			if rip and grow > 1.02:
				cv.global_alpha = minf(1.0, alpha * (1.0 - age / RippleFx.BAND_DUR))
				cv.begin_path()
				cv.move_to(cx, my - dh * grow)
				cv.line_to(cx + dw * grow, my)
				cv.line_to(cx, my + dh * grow)
				cv.line_to(cx - dw * grow, my)
				cv.close_path()
				cv.stroke()
	else:
		var is_door: bool = kind == "doors"
		base = COL_DOOR_OPEN if is_door else COL_CRYPT
		var h_n: float = 0.92 if is_door else 0.38
		var hpx: float = h_n * vs
		var xl: float
		var xr: float
		if is_door:
			var cxi: int = int(floor(sx_))
			var cyi: int = int(floor(sy_))
			var ax: float
			var ay: float
			var bx: float
			var by: float
			if world.is_solid(cxi - 0.5, cyi + 0.5) and world.is_solid(cxi + 1.5, cyi + 0.5):
				ax = cxi
				ay = cyi + 0.5
				bx = cxi + 1
				by = cyi + 0.5
			else:
				ax = cxi + 0.5
				ay = cyi
				bx = cxi + 0.5
				by = cyi + 1
			var pa := project(player, ax, ay, half_w, tan_half)
			if pa.is_empty():
				return false
			xl = pa[1]
			var pb := project(player, bx, by, half_w, tan_half)
			if pb.is_empty():
				return false
			xr = pb[1]
			if xl > xr:
				var tmp: float = xl
				xl = xr
				xr = tmp
		else:
			var w: float = 0.85 * hs
			xl = cx - w / 2.0
			xr = cx + w / 2.0
		c0 = xl - 10.0
		c1 = xr + 10.0
		var amp: float = 0.02 * hs if rip else 0.0
		var wid: float = xr - xl
		var link: bool = is_door and world.is_link_door(sx_, sy_)
		shape = func(cv: Canvas) -> void:
			cv.begin_path()
			if is_door:
				var lean: float = wid * 0.07
				var sag: float = hpx * 0.035
				for side in 2:
					var x: float = xl if side == 0 else xr
					var lx: float = lean if side == 0 else lean * 0.6
					for k in 7:
						var u: float = k / 6.0
						var wv: float = RippleFx.wave(u, age) * amp * (-1.0 if side != 0 else 1.0) if rip else 0.0
						var px: float = x + lx * u + wv + rs.j(idb + k + side * 8, 0) * a_j
						var py: float = floor_y - u * hpx + rs.j(idb + k + side * 8, 1) * a_j
						if k == 0:
							cv.move_to(px, py)
						else:
							cv.line_to(px, py)
					if side == 0:
						cv.quad_to((xl + xr) / 2.0 + lean * 0.8, floor_y - hpx + sag, xr + lean * 0.6, floor_y - hpx)
				cv.stroke()
				cv.begin_path()
				var ins: float = wid * 0.09
				cv.move_to(xl + ins + lean * 0.1, floor_y)
				cv.line_to(xl + ins + lean * 0.9, floor_y - hpx * 0.9)
				cv.move_to(xr - ins + lean * 0.05, floor_y)
				cv.line_to(xr - ins + lean * 0.55, floor_y - hpx * 0.9)
				cv.stroke()
				cv.begin_path()
				var lw2: float = wid * 0.2
				cv.move_to(xl + ins, floor_y)
				cv.line_to(xl + ins + lw2, floor_y - hpx * 0.04)
				cv.line_to(xl + ins + lw2, floor_y - hpx * 0.82)
				cv.line_to(xl + ins + lean * 0.9, floor_y - hpx * 0.9)
				cv.move_to(xl + ins + lw2 * 0.5, floor_y - hpx * 0.02)
				cv.line_to(xl + ins + lw2 * 0.5, floor_y - hpx * 0.86)
				if link:
					var kx: float = (xl + xr) / 2.0 + lean * 0.8
					var ky: float = floor_y - hpx + sag
					cv.move_to(kx - wid * 0.06, ky)
					cv.line_to(kx - wid * 0.06, ky - hpx * 0.07)
					cv.line_to(kx + wid * 0.06, ky - hpx * 0.07)
					cv.line_to(kx + wid * 0.06, ky)
				cv.stroke()
			else:
				var pxs := [0.2, 0.8, 1.0, 0.8, 0.2, 0.0]
				var pys := [0.0, 0.0, 0.55, 1.0, 1.0, 0.55]
				for k in 6:
					var x2: float = xl + pxs[k] * wid + sin(t * 2.2 + k * 1.3 + sx_) * 0.012 * hs + rs.j(idb + k, 0) * a_j
					var y2: float = floor_y - pys[k] * hpx + cos(t * 2.6 + k) * hpx * 0.012 + rs.j(idb + k, 1) * a_j
					if k == 0:
						cv.move_to(x2, y2)
					else:
						cv.line_to(x2, y2)
				cv.close_path()
				LineStyle.fill_silhouette(cv, ink)
				var mx: float = (xl + xr) / 2.0
				var my2: float = floor_y - hpx * 0.55
				cv.move_to(mx, my2 + hpx * 0.22)
				cv.line_to(mx, my2 - hpx * 0.22)
				cv.move_to(mx - wid * 0.1, my2 + hpx * 0.1)
				cv.line_to(mx + wid * 0.1, my2 + hpx * 0.1)
				cv.stroke()
			if rip and rs.quality >= 2:
				band_lines(cv, xl, xr, floor_y, hpx, age, alpha)
	if flash:
		c.stroke_style = "#ffffff"
	else:
		c.stroke_style = EchoLayer.sprite_style(base, b)
	c.line_width = lw
	c.global_alpha = minf(1.0, alpha)
	EchoLayer.clipped_draw(rs, c, c0 - lw, c1 + lw, depth, func(cv: Canvas) -> void:
		shape.call(cv)
		cv.global_alpha = minf(1.0, alpha))
	c.global_alpha = 1.0
	return true


## Steady teardrop flame (outer + inner); only the tip sways, slower than 1 Hz.
static func flame_path(c: Canvas, x: float, y0: float, w: float, h: float, t: float, ph: float) -> void:
	var sw: float = sin(t * TWO_PI * 0.6 + ph) * w * 0.25
	c.move_to(x, y0)
	c.quad_to(x - w, y0 - h * 0.45, x + sw, y0 - h)
	c.quad_to(x + w, y0 - h * 0.45, x, y0)
	c.move_to(x, y0)
	c.quad_to(x - w * 0.45, y0 - h * 0.3, x + sw * 0.6, y0 - h * 0.6)
	c.quad_to(x + w * 0.45, y0 - h * 0.3, x, y0)


## Torch holder path (no stroke): lat in -1..1 is the wall's side on screen; lat > 1.5 means a free-standing iron post.
static func torch_holder(c: Canvas, cx: float, fy: float, vs: float, hs: float, lat: float) -> void:
	var w: float = 0.07 * hs
	c.move_to(cx, fy - 0.42 * vs)
	c.line_to(cx, fy - 0.6 * vs)
	c.move_to(cx - w * 1.3, fy - 0.62 * vs)
	c.line_to(cx - w, fy - 0.54 * vs)
	c.line_to(cx + w, fy - 0.54 * vs)
	c.line_to(cx + w * 1.3, fy - 0.62 * vs)
	if lat > 1.5:
		c.move_to(cx, fy - 0.54 * vs)
		c.line_to(cx, fy - 0.04 * vs)
		c.move_to(cx - w * 1.1, fy - 0.44 * vs)
		c.line_to(cx + w * 1.1, fy - 0.44 * vs)
		c.move_to(cx - w * 2.2, fy)
		c.line_to(cx, fy - 0.1 * vs)
		c.line_to(cx + w * 2.2, fy)
		return
	var dir: float = -1.0 if lat < 0.0 else 1.0
	var ln: float = (0.12 + 0.2 * absf(lat)) * hs + w * 1.5
	var wx: float = cx + dir * ln
	c.move_to(wx, fy - 0.28 * vs)
	c.line_to(wx, fy - 0.5 * vs)
	c.move_to(wx, fy - 0.34 * vs)
	c.quad_to(cx + dir * ln * 0.4, fy - 0.34 * vs, cx, fy - 0.44 * vs)
	c.move_to(cx + dir * w * 1.2, fy - 0.4 * vs)
	c.arc(cx + dir * w * 0.8, fy - 0.37 * vs, w * 0.5, 0.0, TWO_PI)
	c.move_to(cx - w * 0.9, fy - 0.44 * vs)
	c.line_to(cx + w * 0.9, fy - 0.44 * vs)


## Stroke the body path of a prop (hs = px per cell, vs = px per wall height, fy = floor y at centre).
static func prop_body(c: Canvas, type: String, cx: float, fy: float, hs: float, vs: float, t: float, ph: float, body: String, lat: float) -> void:
	c.stroke_style = body
	c.begin_path()
	match type:
		"gravestone":
			var w: float = 0.2 * hs
			c.move_to(cx - w, fy)
			c.line_to(cx - w, fy - 0.26 * vs)
			c.quad_to(cx - w, fy - 0.4 * vs, cx, fy - 0.4 * vs)
			c.quad_to(cx + w, fy - 0.4 * vs, cx + w, fy - 0.26 * vs)
			c.line_to(cx + w, fy)
			c.move_to(cx - w * 1.5, fy)
			c.line_to(cx + w * 1.5, fy)
			c.move_to(cx, fy - 0.3 * vs)
			c.line_to(cx, fy - 0.2 * vs)
			c.move_to(cx - w * 0.4, fy - 0.26 * vs)
			c.line_to(cx + w * 0.4, fy - 0.26 * vs)
		"cross":
			var w2: float = 0.1 * hs
			c.move_to(cx - w2 * 0.3, fy)
			c.line_to(cx - w2 * 0.3, fy - 0.42 * vs)
			c.line_to(cx - w2 * 1.6, fy - 0.42 * vs)
			c.line_to(cx - w2 * 1.6, fy - 0.5 * vs)
			c.line_to(cx - w2 * 0.3, fy - 0.5 * vs)
			c.line_to(cx - w2 * 0.3, fy - 0.64 * vs)
			c.line_to(cx + w2 * 0.3, fy - 0.64 * vs)
			c.line_to(cx + w2 * 0.3, fy - 0.5 * vs)
			c.line_to(cx + w2 * 1.6, fy - 0.5 * vs)
			c.line_to(cx + w2 * 1.6, fy - 0.42 * vs)
			c.line_to(cx + w2 * 0.3, fy - 0.42 * vs)
			c.line_to(cx + w2 * 0.3, fy)
			c.move_to(cx - w2, fy)
			c.line_to(cx + w2, fy)
		"barrel":
			var w3: float = 0.2 * hs
			var e: float = maxf(1.2, vs * 0.025)
			c.move_to(cx - w3, fy - 0.44 * vs)
			c.quad_to(cx - w3 * 1.25, fy - 0.22 * vs, cx - w3, fy)
			c.quad_to(cx, fy + e * 1.6, cx + w3, fy)
			c.quad_to(cx + w3 * 1.25, fy - 0.22 * vs, cx + w3, fy - 0.44 * vs)
			c.move_to(cx + w3, fy - 0.44 * vs)
			c.ellipse(cx, fy - 0.44 * vs, w3, e, 0.0, 0.0, TWO_PI)
			c.move_to(cx - w3 * 1.1, fy - 0.15 * vs)
			c.quad_to(cx, fy - 0.15 * vs + e * 1.5, cx + w3 * 1.1, fy - 0.15 * vs)
			c.move_to(cx - w3 * 1.1, fy - 0.31 * vs)
			c.quad_to(cx, fy - 0.31 * vs + e * 1.5, cx + w3 * 1.1, fy - 0.31 * vs)
		"table":
			var w4: float = 0.36 * hs
			c.move_to(cx - w4, fy - 0.38 * vs)
			c.line_to(cx + w4, fy - 0.38 * vs)
			c.line_to(cx + w4, fy - 0.34 * vs)
			c.line_to(cx - w4, fy - 0.34 * vs)
			c.close_path()
			c.move_to(cx - w4 * 0.85, fy - 0.34 * vs)
			c.line_to(cx - w4 * 0.85, fy)
			c.move_to(cx + w4 * 0.85, fy - 0.34 * vs)
			c.line_to(cx + w4 * 0.85, fy)
			c.move_to(cx - w4 * 0.5, fy - 0.34 * vs)
			c.line_to(cx - w4 * 0.5, fy - 0.05 * vs)
			c.move_to(cx + w4 * 0.5, fy - 0.34 * vs)
			c.line_to(cx + w4 * 0.5, fy - 0.05 * vs)
		"chair":
			var w5: float = 0.15 * hs
			c.move_to(cx - w5, fy - 0.5 * vs)
			c.line_to(cx - w5, fy - 0.22 * vs)
			c.line_to(cx + w5, fy - 0.22 * vs)
			c.line_to(cx + w5, fy - 0.5 * vs)
			c.move_to(cx - w5, fy - 0.42 * vs)
			c.line_to(cx + w5, fy - 0.42 * vs)
			c.move_to(cx - w5, fy - 0.22 * vs)
			c.line_to(cx - w5, fy)
			c.move_to(cx + w5, fy - 0.22 * vs)
			c.line_to(cx + w5, fy)
			c.move_to(cx - w5 * 0.9, fy - 0.19 * vs)
			c.line_to(cx + w5 * 0.9, fy - 0.19 * vs)
		"bench":
			var w6: float = 0.42 * hs
			c.move_to(cx - w6, fy - 0.2 * vs)
			c.line_to(cx + w6, fy - 0.2 * vs)
			c.move_to(cx - w6, fy - 0.17 * vs)
			c.line_to(cx + w6, fy - 0.17 * vs)
			c.move_to(cx - w6 * 0.9, fy - 0.17 * vs)
			c.line_to(cx - w6 * 0.9, fy)
			c.move_to(cx + w6 * 0.9, fy - 0.17 * vs)
			c.line_to(cx + w6 * 0.9, fy)
			c.move_to(cx - w6, fy - 0.4 * vs)
			c.line_to(cx + w6, fy - 0.4 * vs)
			c.move_to(cx - w6 * 0.9, fy - 0.2 * vs)
			c.line_to(cx - w6 * 0.9, fy - 0.4 * vs)
			c.move_to(cx + w6 * 0.9, fy - 0.2 * vs)
			c.line_to(cx + w6 * 0.9, fy - 0.4 * vs)
		"well":
			var w7: float = 0.38 * hs
			var e2: float = maxf(1.5, vs * 0.05)
			c.move_to(cx - w7, fy - 0.3 * vs)
			c.line_to(cx - w7, fy)
			c.quad_to(cx, fy + e2 * 1.6, cx + w7, fy)
			c.line_to(cx + w7, fy - 0.3 * vs)
			c.move_to(cx + w7, fy - 0.3 * vs)
			c.ellipse(cx, fy - 0.3 * vs, w7, e2, 0.0, 0.0, TWO_PI)
			c.move_to(cx - w7 * 0.85, fy - 0.3 * vs)
			c.line_to(cx - w7 * 0.85, fy - 0.8 * vs)
			c.move_to(cx + w7 * 0.85, fy - 0.3 * vs)
			c.line_to(cx + w7 * 0.85, fy - 0.8 * vs)
			c.move_to(cx - w7 * 1.05, fy - 0.76 * vs)
			c.line_to(cx, fy - 0.88 * vs)
			c.line_to(cx + w7 * 1.05, fy - 0.76 * vs)
			c.move_to(cx, fy - 0.78 * vs)
			c.line_to(cx, fy - 0.5 * vs)
			c.move_to(cx + w7 * 0.18, fy - 0.5 * vs)
			c.arc(cx, fy - 0.5 * vs, w7 * 0.18, 0.0, TWO_PI)
		"stalagmite":
			var w9: float = 0.2 * hs
			c.move_to(cx - w9, fy)
			c.line_to(cx - w9 * 0.45, fy - 0.3 * vs)
			c.line_to(cx - w9 * 0.2, fy - 0.24 * vs)
			c.line_to(cx, fy - 0.7 * vs)
			c.line_to(cx + w9 * 0.3, fy - 0.28 * vs)
			c.line_to(cx + w9 * 0.55, fy - 0.36 * vs)
			c.line_to(cx + w9, fy)
			c.close_path()
		"stalactite":
			var w10: float = 0.16 * hs
			var top_y: float = fy - 1.0 * vs
			c.move_to(cx - w10, top_y)
			c.line_to(cx - w10 * 0.3, top_y + 0.22 * vs)
			c.line_to(cx - w10 * 0.15, top_y + 0.18 * vs)
			c.line_to(cx, top_y + 0.42 * vs)
			c.line_to(cx + w10 * 0.2, top_y + 0.2 * vs)
			c.line_to(cx + w10 * 0.4, top_y + 0.24 * vs)
			c.line_to(cx + w10, top_y)
			c.move_to(cx - w10 * 1.3, top_y)
			c.line_to(cx + w10 * 1.3, top_y)
		"coffin":
			var w11: float = 0.2 * hs
			c.move_to(cx - w11 * 0.6, fy - 0.88 * vs)
			c.line_to(cx + w11 * 0.6, fy - 0.88 * vs)
			c.line_to(cx + w11, fy - 0.62 * vs)
			c.line_to(cx + w11 * 0.7, fy)
			c.line_to(cx - w11 * 0.7, fy)
			c.line_to(cx - w11, fy - 0.62 * vs)
			c.close_path()
			c.move_to(cx - w11 * 0.5, fy - 0.8 * vs)
			c.line_to(cx + w11 * 0.5, fy - 0.8 * vs)
			c.move_to(cx, fy - 0.78 * vs)
			c.line_to(cx, fy - 0.5 * vs)
			c.move_to(cx - w11 * 0.4, fy - 0.68 * vs)
			c.line_to(cx + w11 * 0.4, fy - 0.68 * vs)
		"glowworm":
			var top_g: float = fy - 1.0 * vs
			for gi in 7:
				var gx: float = cx + sin(ph + gi * 2.1) * 0.22 * hs
				var gy: float = top_g + (0.06 + 0.05 * float(gi % 4)) * vs + sin(t * 1.3 + ph + gi) * 0.012 * vs
				var gr: float = maxf(1.0, 0.018 * hs)
				c.move_to(gx + gr, gy)
				c.arc(gx, gy, gr, 0.0, TWO_PI)
				if gi % 2 == 0:
					c.move_to(gx, gy - gr)
					c.line_to(gx, top_g)
		"stump":
			var w12: float = 0.2 * hs
			var e4: float = maxf(1.2, vs * 0.025)
			c.move_to(cx - w12, fy - 0.26 * vs)
			c.line_to(cx - w12 * 1.25, fy)
			c.line_to(cx + w12 * 1.25, fy)
			c.line_to(cx + w12, fy - 0.26 * vs)
			c.move_to(cx + w12, fy - 0.26 * vs)
			c.ellipse(cx, fy - 0.26 * vs, w12, e4, 0.0, 0.0, TWO_PI)
			c.move_to(cx + w12 * 0.45, fy - 0.26 * vs)
			c.ellipse(cx, fy - 0.26 * vs, w12 * 0.45, e4 * 0.45, 0.0, 0.0, TWO_PI)
		"boulder":
			var w13: float = 0.28 * hs
			c.move_to(cx - w13, fy)
			c.quad_to(cx - w13 * 1.1, fy - 0.34 * vs, cx - w13 * 0.2, fy - 0.4 * vs)
			c.quad_to(cx + w13 * 1.0, fy - 0.42 * vs, cx + w13, fy)
			c.line_to(cx - w13, fy)
			c.move_to(cx - w13 * 0.4, fy - 0.3 * vs)
			c.line_to(cx - w13 * 0.1, fy - 0.18 * vs)
			c.line_to(cx + w13 * 0.3, fy - 0.2 * vs)
		"haybale":
			var w14: float = 0.34 * hs
			c.move_to(cx - w14, fy)
			c.line_to(cx - w14, fy - 0.3 * vs)
			c.line_to(cx + w14, fy - 0.3 * vs)
			c.line_to(cx + w14, fy)
			c.close_path()
			c.move_to(cx - w14 * 0.35, fy - 0.3 * vs)
			c.line_to(cx - w14 * 0.35, fy)
			c.move_to(cx + w14 * 0.35, fy - 0.3 * vs)
			c.line_to(cx + w14 * 0.35, fy)
			c.move_to(cx - w14, fy - 0.3 * vs)
			c.line_to(cx - w14 * 1.15, fy - 0.36 * vs)
			c.move_to(cx + w14, fy - 0.3 * vs)
			c.line_to(cx + w14 * 1.15, fy - 0.36 * vs)
		"scarecrow":
			var w15: float = 0.3 * hs
			c.move_to(cx, fy)
			c.line_to(cx, fy - 0.72 * vs)
			c.move_to(cx - w15, fy - 0.58 * vs)
			c.line_to(cx + w15, fy - 0.58 * vs)
			c.move_to(cx - w15, fy - 0.58 * vs)
			c.line_to(cx - w15 * 1.1, fy - 0.4 * vs)
			c.move_to(cx + w15, fy - 0.58 * vs)
			c.line_to(cx + w15 * 1.1, fy - 0.4 * vs)
			c.move_to(cx + w15 * 0.28, fy - 0.8 * vs)
			c.arc(cx, fy - 0.8 * vs, w15 * 0.28, 0.0, TWO_PI)
			c.move_to(cx - w15 * 0.5, fy - 0.86 * vs)
			c.line_to(cx + w15 * 0.5, fy - 0.86 * vs)
			c.move_to(cx - w15 * 0.25, fy - 0.86 * vs)
			c.line_to(cx, fy - 0.92 * vs)
			c.line_to(cx + w15 * 0.25, fy - 0.86 * vs)
		"shrine":
			var w16: float = 0.26 * hs
			c.move_to(cx - w16, fy)
			c.line_to(cx - w16, fy - 0.2 * vs)
			c.line_to(cx + w16, fy - 0.2 * vs)
			c.line_to(cx + w16, fy)
			c.move_to(cx - w16 * 0.6, fy - 0.2 * vs)
			c.line_to(cx - w16 * 0.6, fy - 0.46 * vs)
			c.line_to(cx, fy - 0.62 * vs)
			c.line_to(cx + w16 * 0.6, fy - 0.46 * vs)
			c.line_to(cx + w16 * 0.6, fy - 0.2 * vs)
			c.move_to(cx, fy - 0.32 * vs)
			c.line_to(cx, fy - 0.46 * vs)
			c.move_to(cx - w16 * 0.2, fy - 0.4 * vs)
			c.line_to(cx + w16 * 0.2, fy - 0.4 * vs)
		"torch":
			torch_holder(c, cx, fy, vs, hs, lat)
		"brazier":
			var w8: float = 0.2 * hs
			var e3: float = maxf(1.3, vs * 0.03)
			c.move_to(cx - w8, fy - 0.4 * vs)
			c.quad_to(cx - w8 * 0.9, fy - 0.27 * vs, cx, fy - 0.24 * vs)
			c.quad_to(cx + w8 * 0.9, fy - 0.27 * vs, cx + w8, fy - 0.4 * vs)
			c.move_to(cx + w8, fy - 0.4 * vs)
			c.ellipse(cx, fy - 0.4 * vs, w8, e3, 0.0, 0.0, TWO_PI)
			c.move_to(cx - w8 * 0.3, fy - 0.24 * vs)
			c.line_to(cx - w8 * 0.8, fy)
			c.move_to(cx + w8 * 0.3, fy - 0.24 * vs)
			c.line_to(cx + w8 * 0.8, fy)
			c.move_to(cx, fy - 0.24 * vs)
			c.line_to(cx, fy)
			c.move_to(cx - w8 * 0.9, fy)
			c.line_to(cx + w8 * 0.9, fy)
	c.stroke()
	if type == "torch" or type == "brazier":
		var fw: float = (0.07 if type == "torch" else 0.13) * hs
		var fy0: float = fy - 0.62 * vs if type == "torch" else fy - 0.4 * vs
		var fh: float = (0.2 if type == "torch" else 0.34) * vs
		c.stroke_style = COL_FLAME
		c.begin_path()
		flame_path(c, cx, fy0, fw, fh, t, ph)
		c.stroke()


## Union of lit heights at (x, y) over all pulses that currently reach it: [lo, hi] or an empty array.
static func prop_band(sonar: Sonar, t: float, x: float, y: float) -> Array:
	var lo := 9.0
	var hi := -9.0
	for pu in sonar.pulses:
		var dx: float = x - pu.x
		var dy: float = y - pu.y
		var d: float = sqrt(dx * dx + dy * dy)
		if d > pu.range:
			continue
		var age: float = t - (pu.t0 + d / pu.speed)
		var pf: float = pu.fade if pu.fade > 0.0 else sonar.fade
		if age < 0.0 or age >= Pose.glow_dur(pf):
			continue
		if not Sonar.visible_from(pu, x, y):
			continue
		var bd := Sonar.height_band(pu, t, x, y)
		if bd.is_empty():
			continue
		if bd[0] < lo:
			lo = bd[0]
		if bd[1] > hi:
			hi = bd[1]
	if hi < lo:
		return []
	return [lo, hi]


## Per pulse, the annulus (squared horizontal radii) where a point can be lit right now: scan() only lights a point whose
## wavefront passed it less than glow_dur ago (glow_mul is 0 after that), within range; |dz| <= 1.5 widens the inner edge.
## Flat [x, y, lo2, hi2, ...]. A point outside every annulus has lit_at3 brightness 0, so it can be skipped before the scan.
static func lit_bands(sonar: Sonar, t: float) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	for p in sonar.pulses:
		var rr: float = (t - p.t0) * p.speed
		if rr < 0.0:
			continue
		var hi: float = minf(rr, p.range) + 1e-6
		var lo: float = rr - Pose.glow_dur(p.fade) * p.speed - 1.5
		out.append(p.x)
		out.append(p.y)
		out.append(lo * lo if lo > 0.0 else 0.0)
		out.append(hi * hi)
	return out


static func in_lit_band(bands: PackedFloat64Array, x: float, y: float) -> bool:
	var i := 0
	var n: int = bands.size()
	while i < n:
		var dx: float = x - bands[i]
		var dy: float = y - bands[i + 1]
		var d2: float = dx * dx + dy * dy
		if d2 >= bands[i + 2] and d2 <= bands[i + 3]:
			return true
		i += 4
	return false


## Draw all props lit by the current pulses; returns the count drawn.
static func draw_props(rs: RenderState, c: Canvas, world: World, player: Dictionary, sonar: Sonar, t: float, tan_half: float) -> int:
	var props: Array = world.props
	if props.is_empty() or sonar.pulses.is_empty():
		return 0
	var half_w: float = rs.ow / 2.0
	var focal: float = half_w / tan_half
	var ca: float = cos(player["angle"])
	var sa: float = sin(player["angle"])
	var drawn := 0
	var bands := lit_bands(sonar, t)
	if bands.is_empty():
		c.global_alpha = 1.0
		return 0
	# prop positions are static: scan them from a packed array and only touch the dictionaries of the few that pass the culls
	var np: int = props.size()
	var wid: int = world.get_instance_id()
	if wid != _pc_world or np != _pc_n:
		_pc_world = wid
		_pc_n = np
		_pc_xy.resize(np * 2)
		for k in np:
			_pc_xy[k * 2] = float(props[k]["x"])
			_pc_xy[k * 2 + 1] = float(props[k]["y"])
	var ppx: float = player["x"]
	var ppy: float = player["y"]
	var max2: float = PROP_MAX_DIST * PROP_MAX_DIST
	for pi in np:
		var qx: float = _pc_xy[pi * 2]
		var qy: float = _pc_xy[pi * 2 + 1]
		var dx: float = qx - ppx
		var dy: float = qy - ppy
		if dx * dx + dy * dy > max2:
			continue
		var fwd0: float = dx * ca + dy * sa
		if fwd0 <= 0.1:
			continue
		var right0: float = -dx * sa + dy * ca
		if absf(right0) > fwd0 * tan_half * 1.2 + 1.0:
			continue
		if not in_lit_band(bands, qx, qy):
			continue
		var pr: Dictionary = props[pi]
		var type: String = pr["type"]
		if not PROP_DEF.has(type):
			continue
		var def: Dictionary = PROP_DEF[type]
		var lit := lit_at3(sonar, pr["x"], pr["y"], def["zc"], t)
		var b: float = lit[0]
		if def["fire"] and b <= 0.01:
			var q := 0
			while q < FIRE_Z.size() and b <= 0.01:
				lit = lit_at3(sonar, pr["x"], pr["y"], FIRE_Z[q], t)
				b = lit[0]
				q += 1
		if b <= 0.01:
			continue
		var age: float = lit[1]
		var px: float = pr["x"]
		var py: float = pr["y"]
		var hold_lat := 2.0
		if type == "torch":
			var off_x := 0.0
			var off_y := 0.0
			var cxi: int = int(floor(pr["x"]))
			var cyi: int = int(floor(pr["y"]))
			if world.is_solid(cxi + 1, cyi):
				off_x = 0.42
			elif world.is_solid(cxi - 1, cyi):
				off_x = -0.42
			elif world.is_solid(cxi, cyi + 1):
				off_y = 0.42
			elif world.is_solid(cxi, cyi - 1):
				off_y = -0.42
			px += off_x
			py += off_y
			hold_lat = 2.0 if off_x == 0.0 and off_y == 0.0 else (1.0 if off_x > 0.0 else (-1.0 if off_x < 0.0 else 0.0)) * -sa + (1.0 if off_y > 0.0 else (-1.0 if off_y < 0.0 else 0.0)) * ca
		var pj := project(player, px, py, half_w, tan_half)
		if pj.is_empty():
			continue
		var depth: float = pj[0]
		var cx: float = pj[1]
		var hs: float = focal / depth
		if cx < -hs - 40.0 or cx > rs.ow + hs + 40.0:
			continue
		var vs: float = rs.oh / depth
		var fy: float = rs.horizon + 0.5 * vs
		var flash: bool = age >= 0.0 and age < FLASH_AGE
		var ink: bool = LineStyle.ink_for(rs)
		var alpha: float = LineStyle.ping_lit(b, depth, ink) * 1.2
		var lw: float = LineStyle.contour_width(depth, ink, rs.wscale)
		if flash:
			alpha = minf(1.0, alpha + 0.5 * (1.0 - age / FLASH_AGE))
			if ink:
				lw = LineStyle.flash_width(lw, 1.0 - age / FLASH_AGE, rs.wscale)
			else:
				lw += 0.4 * rs.wscale
		var idb: int = int(pr["x"] * 7.0 + pr["y"] * 13.0) * 8
		var boil_px: float = LineStyle.boil_amp(ink, rs.wscale)
		var jx: float = rs.j(idb, 0) * boil_px if rs.boil_on else 0.0
		var jy: float = rs.j(idb, 1) * boil_px if rs.boil_on else 0.0
		var body: String = "#ffffff" if flash else EchoLayer.sprite_style(COL_PROP, b)
		var phase: float = pr["x"] * 3.1 + pr["y"] * 1.7
		var full := true
		var z_min := 0.0
		var z_max := 1.2
		if not def["fire"]:
			var pbd := prop_band(sonar, t, pr["x"], pr["y"])
			if not pbd.is_empty():
				z_min = pbd[0]
				z_max = pbd[1]
				full = z_min <= 0.02 and z_max >= def["top"] + 0.05
		var hw: float = hs * 0.5 + 6.0
		c.line_width = lw
		var cxj: float = cx + jx
		var fyj: float = fy + jy
		var fn := func(cv: Canvas) -> void:
			if full:
				cv.global_alpha = minf(1.0, alpha)
				prop_body(cv, type, cxj, fyj, hs, vs, t, phase, body, hold_lat)
				return
			for s in RippleFx.mask_strips(z_min, z_max, 1.0, 0.12):
				var za: float = s[0]
				var zb: float = s[1]
				var sal: float = s[2]
				cv.save()
				cv.begin_path()
				var y_top: float = -50.0 if zb >= 1.0 - 1e-3 else fyj - zb * vs
				var y_bot: float = fyj + 30.0 * rs.wscale if za <= 1e-3 else fyj - za * vs
				cv.rect(cxj - hw - hs * 0.4, y_top, hw * 2.0 + hs * 0.8, y_bot - y_top)
				cv.clip()
				cv.global_alpha = minf(1.0, alpha * sal)
				prop_body(cv, type, cxj, fyj, hs, vs, t, phase, body, hold_lat)
				cv.restore()
		EchoLayer.clipped_draw(rs, c, cx - hw - lw - hs * 0.4, cx + hw + lw + hs * 0.4, depth, fn)
		drawn += 1
	c.global_alpha = 1.0
	return drawn


## All three marker kinds (crypt, safe, open doors) lit this frame; returns the count drawn.
static func draw_markers(rs: RenderState, c: Canvas, world: World, player: Dictionary, sonar: Sonar, t: float, tan_half: float) -> int:
	var n := 0
	# draw_sprite returns false for anything behind the camera (project() fwd <= 0.1): skip those before the dictionary and lights.
	var ca: float = cos(player["angle"])
	var sa: float = sin(player["angle"])
	var px: float = player["x"]
	var py: float = player["y"]
	var bands := lit_bands(sonar, t)
	for kind in ["crypt", "safe", "doors"]:
		for spot in world.spots.get(kind, []):
			if (spot.x - px) * ca + (spot.y - py) * sa <= 0.1:
				continue
			if not in_lit_band(bands, spot.x, spot.y):
				continue
			if draw_sprite(rs, c, world, player, sonar, t, kind, {"x": spot.x, "y": spot.y}, tan_half):
				n += 1
	return n
