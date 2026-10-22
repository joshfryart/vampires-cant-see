class_name Icons
extends RefCounted
## Ports js/icons.js: hand-drawn wobbly line doodles (power and boon icons, the tombstone and the crypt menu) onto a Canvas.
## Unit space is -1..1, scaled by size/2.

const COL := "#cfe8ff"
const TAU_ := TAU
const NAMES := ["ear", "hourglass", "bat", "vial", "drop", "fang", "paw", "moon", "heart", "shriek", "mist", "still", "eye"]
const CRYPT_SEG := 12
const CANDLES := [[0.3, 0.5, 0.0], [0.7, 0.5, 1.3], [0.5, 0.26, 2.6]]

static var _shapes: Dictionary = {}
static var _crypt: Array = []


static func hash2(a: float, b: float) -> float:
	var v: float = sin(a * 12.9898 + b * 78.233) * 43758.5453
	return v - floor(v)


static func seed_of(name: String) -> int:
	var s := 7
	for i in name.length():
		s = (s * 31 + name.unicode_at(i)) % 9973
	return s


## Arc points: centre, radius (rx, ry), angle range, n segments.
static func arc_pts(cx: float, cy: float, rx: float, ry: float, a0: float, a1: float, n: int) -> Array:
	var out: Array = []
	for i in n + 1:
		var a: float = a0 + (a1 - a0) * float(i) / n
		out.append([cx + cos(a) * rx, cy + sin(a) * ry])
	return out


static func shapes() -> Dictionary:
	if not _shapes.is_empty():
		return _shapes
	var PI_ := PI
	_shapes = {
		"ear": [
			arc_pts(0, -0.15, 0.6, 0.75, PI_ * 0.85, PI_ * 2.15, 10) + [[0.5, 0.35], [0.35, 0.55], [0.15, 0.7], [-0.05, 0.9]],
			[[-0.3, 0.2], [-0.25, -0.1], [-0.05, -0.3], [0.2, -0.2], [0.25, 0.05], [0.05, 0.25], [0.0, 0.5]],
			[[-0.1, -0.05], [0.05, -0.1]],
		],
		"hourglass": [
			[[-0.6, -0.85], [0.6, -0.85]], [[-0.6, 0.85], [0.6, 0.85]],
			[[-0.5, -0.85], [-0.45, -0.4], [-0.08, -0.04], [-0.45, 0.4], [-0.5, 0.85]],
			[[0.5, -0.85], [0.45, -0.4], [0.08, -0.04], [0.45, 0.4], [0.5, 0.85]],
			[[-0.3, 0.8], [-0.1, 0.55], [0.1, 0.55], [0.3, 0.8]],
			[[0, -0.2], [0, 0.4]],
		],
		"bat": [
			[[0, -0.35], [0.1, -0.5], [0.18, -0.3], [0.3, -0.35], [0.55, -0.6], [0.95, -0.45], [0.85, -0.1], [0.6, 0.0], [0.5, 0.35],
				[0.3, 0.12], [0.15, 0.2], [0.1, 0.45], [0, 0.55], [-0.1, 0.45], [-0.15, 0.2], [-0.3, 0.12], [-0.5, 0.35], [-0.6, 0.0],
				[-0.85, -0.1], [-0.95, -0.45], [-0.55, -0.6], [-0.3, -0.35], [-0.18, -0.3], [-0.1, -0.5], [0, -0.35]],
			[[-0.06, -0.2], [-0.04, -0.15]], [[0.06, -0.2], [0.04, -0.15]],
		],
		"vial": [
			[[-0.3, -0.85], [0.3, -0.85]],
			[[-0.2, -0.85], [-0.2, -0.55], [-0.4, -0.45], [-0.4, 0.55]] + arc_pts(0, 0.55, 0.4, 0.35, PI_, 0, 6),
			[[0.2, -0.85], [0.2, -0.55], [0.4, -0.45], [0.4, 0.55]],
			[[-0.4, 0.05], [-0.15, 0.0], [0.1, 0.08], [0.4, 0.02]],
			[[-0.2, 0.3], [-0.2, 0.5]],
		],
		"drop": [
			[[0, -0.9], [0.2, -0.5], [0.5, -0.1], [0.58, 0.25]] + arc_pts(0, 0.28, 0.58, 0.6, 0, PI_, 8) + [[-0.5, -0.1], [-0.2, -0.5], [0, -0.9]],
			[[-0.25, 0.2], [-0.2, 0.45]],
		],
		"fang": [
			[[-0.6, -0.75], [0.6, -0.75]],
			[[-0.45, -0.75], [-0.4, -0.2], [-0.25, 0.4], [-0.12, 0.9], [0.02, 0.35], [0.1, -0.2], [0.12, -0.75]],
			[[0.2, -0.75], [0.35, -0.2], [0.5, 0.15], [0.55, -0.2], [0.55, -0.75]],
			[[-0.28, -0.35], [-0.22, 0.0]],
		],
		"paw": [
			[[0, 0.0], [0.25, 0.2], [0.4, 0.45], [0.2, 0.75], [0, 0.65], [-0.2, 0.75], [-0.4, 0.45], [-0.25, 0.2], [0, 0.0]],
			arc_pts(-0.55, -0.15, 0.17, 0.22, 0, TAU_, 8),
			arc_pts(-0.22, -0.55, 0.17, 0.24, 0, TAU_, 8),
			arc_pts(0.22, -0.55, 0.17, 0.24, 0, TAU_, 8),
			arc_pts(0.55, -0.15, 0.17, 0.22, 0, TAU_, 8),
		],
		"moon": [
			arc_pts(0, 0, 0.8, 0.8, -PI_ * 0.3, PI_ * 1.3, 14) + arc_pts(0.2, 0, 0.6, 0.68, PI_ * 1.1, -PI_ * 0.1, 10),
			[[0.45, -0.7], [0.5, -0.55]], [[0.7, -0.5], [0.55, -0.5]],
		],
		"heart": [
			[[0, 0.8], [-0.4, 0.4], [-0.8, 0.0], [-0.85, -0.4], [-0.6, -0.65], [-0.3, -0.6], [0, -0.3],
				[0.3, -0.6], [0.6, -0.65], [0.85, -0.4], [0.8, 0.0], [0.4, 0.4], [0, 0.8]],
			[[-0.55, -0.3], [-0.4, -0.45]],
		],
		"shriek": [
			arc_pts(-0.35, 0.05, 0.4, 0.55, 0, TAU_, 10),
			[[-0.6, -0.3], [-0.45, -0.1], [-0.2, -0.3]],
			arc_pts(0.05, 0, 0.35, 0.35, -PI_ * 0.35, PI_ * 0.35, 4),
			arc_pts(0.05, 0, 0.62, 0.62, -PI_ * 0.35, PI_ * 0.35, 5),
			arc_pts(0.05, 0, 0.9, 0.9, -PI_ * 0.35, PI_ * 0.35, 6),
		],
		"mist": [
			[[-0.85, -0.5], [-0.5, -0.65], [-0.15, -0.35], [0.2, -0.6], [0.55, -0.4], [0.85, -0.55]],
			[[-0.85, 0.0], [-0.5, -0.15], [-0.15, 0.15], [0.2, -0.1], [0.55, 0.1], [0.85, -0.05]],
			[[-0.85, 0.5], [-0.5, 0.35], [-0.15, 0.65], [0.2, 0.4], [0.55, 0.6], [0.85, 0.45]],
		],
		"still": [
			[[-0.85, 0.0], [-0.45, 0.35], [0, 0.45], [0.45, 0.35], [0.85, 0.0]],
			[[-0.65, 0.3], [-0.75, 0.6]], [[-0.3, 0.42], [-0.35, 0.78]], [[0.1, 0.46], [0.1, 0.82]],
			[[0.45, 0.36], [0.55, 0.7]], [[0.7, 0.2], [0.85, 0.45]],
		],
		"eye": [
			[[-0.9, 0.0], [-0.45, -0.4], [0, -0.5], [0.45, -0.4], [0.9, 0.0], [0.45, 0.4], [0, 0.5], [-0.45, 0.4], [-0.9, 0.0]],
			arc_pts(0, 0, 0.3, 0.3, 0, TAU_, 8),
			[[-0.02, 0.0], [0.02, 0.0]],
		],
	}
	return _shapes


## Stroke a smooth wobbly path through pts. j = jitter amplitude in unit space. tp > 0 = tapered stroke at that full width.
static func stroke_pts(c: Canvas, pts: Array, s: float, ox: float, oy: float, seed_v: int, fr: int, j: float, si: int, tp: float = 0.0) -> void:
	var n: int = pts.size()
	if n < 2:
		return
	var P: Array = []
	for i in n:
		P.append([
			ox + (float(pts[i][0]) + (hash2(float(seed_v + si * 31 + i), float(fr)) - 0.5) * j) * s,
			oy + (float(pts[i][1]) + (hash2(float(seed_v + si * 31 + i + 500), float(fr)) - 0.5) * j) * s])
	if tp > 0.0:
		c.line_width = tp * 0.7
		_run(c, P)
		var Q: Array
		if n == 2:
			Q = [[P[0][0] + (P[1][0] - P[0][0]) * 0.15, P[0][1] + (P[1][1] - P[0][1]) * 0.15],
				[P[0][0] + (P[1][0] - P[0][0]) * 0.85, P[0][1] + (P[1][1] - P[0][1]) * 0.85]]
		else:
			var lo: int = int(floor((n - 1) * 0.15 + 0.5))
			var hi: int = maxi(lo + 1, int(ceil((n - 1) * 0.85 - 0.5)))
			Q = P.slice(lo, mini(n, hi + 1))
			if Q.size() < 2:
				Q = P
		c.line_width = tp
		_run(c, Q)
	else:
		_run(c, P)


static func _run(c: Canvas, Q: Array) -> void:
	var m: int = Q.size()
	c.begin_path()
	c.move_to(Q[0][0], Q[0][1])
	if m == 2:
		c.line_to(Q[1][0], Q[1][1])
	else:
		for i in range(1, m - 1):
			c.quad_to(Q[i][0], Q[i][1], (Q[i][0] + Q[i + 1][0]) / 2.0, (Q[i][1] + Q[i + 1][1]) / 2.0)
		c.line_to(Q[m - 1][0], Q[m - 1][1])
	c.stroke()


static func set_line(c: Canvas, color: String, lw: float, alpha: float) -> void:
	c.stroke_style = color
	c.line_width = lw
	c.global_alpha = alpha


## Draw an icon centred on the current origin, `size` px square. Returns true; an unknown name draws "?" and returns false.
## opts: {alpha, color, still, taper}.
static func draw(c: Canvas, name: String, size: float, t: float, opts: Dictionary = {}) -> bool:
	var sz: float = size if is_finite(size) and size > 0.0 else 48.0
	var color: String = opts["color"] if opts.get("color") is String and opts["color"] != "" else COL
	var fr: int = 0 if opts.get("still", false) else int(floor((t if is_finite(t) else 0.0) / 0.34))
	var sh: Dictionary = shapes()
	var known: bool = sh.has(name)
	var s: float = sz / 2.0 * 0.92
	c.save()
	set_line(c, color, 1.5, float(opts["alpha"]) if opts.get("alpha") is float or opts.get("alpha") is int else 1.0)
	var jit: float = 0.05 if sz < 32.0 else 0.07
	if not known:
		var sd := seed_of(name)
		stroke_pts(c, arc_pts(0, 0, 0.8, 0.8, 0, TAU_, 12), s, 0, 0, sd, fr, jit, 0)
		stroke_pts(c, [[-0.25, -0.25], [-0.2, -0.5], [0, -0.55], [0.22, -0.45], [0.2, -0.2], [0, 0.0], [0, 0.2]], s, 0, 0, sd, fr, jit, 1)
		stroke_pts(c, [[0, 0.4], [0, 0.42]], s, 0, 0, sd, fr, jit, 2)
		c.restore()
		return false
	var seed_v := seed_of(name)
	var strokes: Array = sh[name]
	var tp: float = 1.5 if opts.get("taper", false) == true else 0.0
	for i in strokes.size():
		stroke_pts(c, strokes[i], s, 0, 0, seed_v, fr, jit, i, tp)
	c.restore()
	return true


## Wobbly line from a to b with a few segments.
static func wline(c: Canvas, x0: float, y0: float, x1: float, y1: float, seed_v: int, fr: int, amp: float) -> void:
	var n: int = maxi(2, mini(8, int(ceil(sqrt((x1 - x0) * (x1 - x0) + (y1 - y0) * (y1 - y0)) / 40.0))))
	c.begin_path()
	c.move_to(x0, y0)
	for i in range(1, n + 1):
		var k: float = float(i) / n
		var w: float = 0.0 if i == n else (hash2(float(seed_v + i), float(fr)) - 0.5) * amp
		c.line_to(x0 + (x1 - x0) * k + w, y0 + (y1 - y0) * k + w * 0.7)
	c.stroke()


## Outline tombstone with rounded top, ground line and cracks, fitted in w x h from the origin.
static func draw_tombstone(c: Canvas, w: float, h: float, t: float) -> bool:
	var fr: int = int(floor((t if is_finite(t) else 0.0) / 0.34))
	c.save()
	set_line(c, COL, 1.5, 0.9)
	var gy: float = h * 0.9
	var bw: float = w * 0.5
	var cx: float = w / 2.0
	var top: float = h * 0.12
	var r: float = bw / 2.0
	var pts: Array = [[cx - bw / 2.0, gy], [cx - bw / 2.0, top + r]] + arc_pts(cx, top + r, r, r, PI, TAU_, 10) + [[cx + bw / 2.0, gy]]
	stroke_pts(c, pts, 1.0, 0, 0, 3, fr, 3.0, 1)
	wline(c, w * 0.08, gy, w * 0.92, gy, 11, fr, 2.5)
	wline(c, w * 0.3, gy + 8, w * 0.5, gy + 8, 17, fr, 2.0)
	wline(c, w * 0.58, gy + 14, w * 0.78, gy + 14, 19, fr, 2.0)
	wline(c, cx, top + r * 0.9, cx, top + r * 0.9 + h * 0.2, 23, fr, 1.5)
	wline(c, cx - w * 0.07, top + r * 0.9 + h * 0.06, cx + w * 0.07, top + r * 0.9 + h * 0.06, 29, fr, 1.5)
	stroke_pts(c, [[cx + bw * 0.2, gy - h * 0.35], [cx + bw * 0.12, gy - h * 0.28], [cx + bw * 0.22, gy - h * 0.2], [cx + bw * 0.1, gy - h * 0.1]], 1.0, 0, 0, 5, fr, 3.0, 2)
	stroke_pts(c, [[cx - bw * 0.35, gy - h * 0.12], [cx - bw * 0.25, gy - h * 0.06], [cx - bw * 0.3, gy]], 1.0, 0, 0, 6, fr, 3.0, 3)
	c.restore()
	return true


static func crypt_layout() -> Array:
	if not _crypt.is_empty():
		return _crypt
	var L: Array = []
	var cf := [[0.42, 0.42], [0.46, 0.36], [0.54, 0.36], [0.58, 0.42], [0.55, 0.66], [0.45, 0.66], [0.42, 0.42]]
	for i in cf.size() - 1:
		L.append([cf[i][0], cf[i][1], cf[i + 1][0], cf[i + 1][1]])
	L.append([0.5, 0.42, 0.5, 0.52])
	L.append([0.47, 0.46, 0.53, 0.46])
	for side in 2:
		var x0: float = 0.74 if side == 1 else 0.06
		var x1: float = 0.94 if side == 1 else 0.26
		for k in 4:
			var y: float = 0.24 + k * 0.17
			L.append([x0, y, x1, y])
			for p in 4:
				var px: float = x0 + (x1 - x0) * (p + 0.5) / 4.0
				L.append([px, y, px + 0.015, y - 0.07])
		L.append([x0, 0.17, x0, 0.8])
		L.append([x1, 0.17, x1, 0.8])
	L.append([0.03, 0.82, 0.97, 0.82])
	L.append([0.03, 0.14, 0.97, 0.14])
	L.append([0.3, 0.82, 0.36, 0.7])
	L.append([0.7, 0.82, 0.64, 0.7])
	_crypt = L
	return L


## Full-canvas black crypt: shapes revealed near a sweeping ring, candles as soft rings.
static func draw_crypt_menu(c: Canvas, w: float, h: float, t: float) -> bool:
	var fr: int = int(floor(t / 0.34))
	c.save()
	c.global_alpha = 1.0
	c.fill_style = "#000"
	c.fill_rect(0, 0, w, h)
	c.line_width = 1.5
	c.stroke_style = COL
	var cx: float = w / 2.0
	var cy: float = h * 0.55
	var max_r: float = sqrt(w * w + h * h) * 0.55
	var ph: float = fposmod(t, 4.0) / 4.0
	var ring_r: float = ph * max_r
	var ring_a: float = sin(ph * PI) * 0.35
	var band: float = max_r * 0.14
	if ring_a > 0.01:
		c.global_alpha = ring_a
		c.begin_path()
		c.ellipse(cx, cy, ring_r, ring_r * 0.8, 0.0, 0.0, TAU_)
		c.stroke()
	var layout := crypt_layout()
	var buckets: Array = [[], [], [], [], []]
	for i in layout.size():
		var sg: Array = layout[i]
		var mx: float = (sg[0] + sg[2]) / 2.0 * w
		var my: float = (sg[1] + sg[3]) / 2.0 * h
		var d: float = sqrt((mx - cx) * (mx - cx) + ((my - cy) / 0.8) * ((my - cy) / 0.8))
		var prox: float = 1.0 - minf(1.0, absf(d - ring_r) / band)
		var a: float = prox * prox * 0.9 + 0.025
		buckets[mini(4, int(floor(a * 5.0)))].append(i)
	for b in 5:
		var lst: Array = buckets[b]
		if lst.is_empty():
			continue
		c.global_alpha = (b + 0.5) / 5.0 * 0.9
		c.begin_path()
		for k in lst.size():
			var sg2: Array = layout[lst[k]]
			var x0: float = sg2[0] * w + (hash2(float(lst[k]), float(fr)) - 0.5) * 2.0
			var y0: float = sg2[1] * h + (hash2(float(lst[k] + 99), float(fr)) - 0.5) * 2.0
			c.move_to(x0, y0)
			c.line_to(sg2[2] * w + (hash2(float(lst[k] + 7), float(fr)) - 0.5) * 2.0, sg2[3] * h + (hash2(float(lst[k] + 55), float(fr)) - 0.5) * 2.0)
		c.stroke()
	var base_r: float = minf(w, h) * 0.09
	for i in CANDLES.size():
		var cd: Array = CANDLES[i]
		var x: float = cd[0] * w
		var y: float = cd[1] * h
		for k in 2:
			var p: float = fposmod((t + cd[2]) / 3.2 + k * 0.5, 1.0)
			c.global_alpha = (1.0 - p) * 0.28
			c.begin_path()
			c.arc(x, y, 2.0 + p * base_r, 0.0, TAU_)
			c.stroke()
	c.restore()
	return true
