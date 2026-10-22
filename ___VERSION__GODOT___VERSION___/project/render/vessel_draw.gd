class_name VesselDraw
extends RefCounted
## Ports the circulatory overlay of js/render.js (behind the vis.vessels flag): drawVessels (nodes, edges, the travelling lub-dub
## highlight), drawVesselsSeen (open columns at full strength, window columns muted), the skin flush and the helpers.
## Everything goes through the Canvas abstraction so the draw log can be hashed against the JS.

const TWO_PI := TAU
const LEVELS := 6
const REDUCED_CAP := 0.5
## Dot scale on volumetric bodies (artery radius x K, vein radius x VEIN instead of 1.6); see rad().
const VOL_K := 0.8
const VOL_VEIN := 1.35
const TILE_WINDOW := 119
const GLASS_REACH := 2.5
const TRAIL_ART := 0.35
const TRAIL_VEIN := 0.7
const TUN := {"alpha": 0.75, "size": 0.9, "hot": 1.0, "veins": 0.6, "minQuality": 1.0, "halo": 0.2, "pwvScale": 1.75, "edges": 0.45, "highlight": 1.0, "window": 0.35, "windowRange": 2.5, "lowGamma": 0.5}

## Flush strength per node (temporal, carotid, radialL, radialR), written by draw_vessels, read by paint_flush.
static var flush := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
static var _nx := PackedFloat32Array()
static var _ny := PackedFloat32Array()
static var _na := PackedFloat32Array()
static var _ne := PackedFloat32Array()
static var _fit := false
static var _flush_opts := FigureVolDraw.Opts.new()


static func _arrays() -> void:
	if _nx.size() == 32:
		return
	_nx.resize(32)
	_ny.resize(32)
	_na.resize(32)
	_ne.resize(32)


static func tun(key: String) -> float:
	return Flags.tun("vessels", key, TUN[key])


static func on() -> bool:
	return Flags.get_flag("vis.vessels")


## Seconds a vheart echo stays drawable for the vessel wave (last node's dub / venous swell decayed).
static func life(bpm: float, reduced: bool) -> float:
	return Vessels.timing(bpm, reduced, tun("pwvScale"))["life"]


## Static alpha (before the echo envelope) of one vessel node for a vheart echo e (stateK, periphK, headK).
## o: {base, hotK, veinK, reduced}.
static func vessel_alpha(n: Dictionary, e: Dictionary, o: Dictionary) -> float:
	var state_k: float = float(e["stateK"]) if (e.get("stateK") is float or e.get("stateK") is int) else 1.0
	if not (state_k > 0.0):
		return 0.0
	var periph_k: float = float(e["periphK"]) if (e.get("periphK") is float or e.get("periphK") is int) else 1.0
	var head_k: float = float(e["headK"]) if (e.get("headK") is float or e.get("headK") is int) else 1.0
	var base: float = float(o["base"]) if o.has("base") else TUN["alpha"]
	var p: float = float(n.get("periph", 0.0))
	var g: float = tun("lowGamma")
	var k: float = pow(state_k, g) if (state_k < 1.0 and g > 0.0 and g < 1.0) else state_k
	var a: float = base * float(n["w"]) * k * (1.0 - p + p * periph_k) * (head_k if n["head"] else 1.0)
	if n["vein"]:
		a *= float(o["veinK"]) if o.has("veinK") else TUN["veins"]
	elif not o.get("reduced", false):
		a *= 1.0 + float(n.get("hot", 0.0)) * (float(o["hotK"]) if o.has("hotK") else TUN["hot"])
	if o.get("reduced", false) and a > REDUCED_CAP:
		a = REDUCED_CAP
	return 1.0 if a > 1.0 else (0.0 if a < 0.0 else a)


## Mute (0..1) for vessels seen through a window: vessels.window x (1 - d / vessels.windowRange), 0 beyond the range or when a
## solid (non-glass) tile lies on the line.
static func window_mute(rs: RenderState, e: Dictionary, player: Dictionary) -> float:
	var k: float = tun("window")
	var rng: float = tun("windowRange")
	if not (k > 0.0) or not (rng > 0.0):
		return 0.0
	var d: float = sqrt((float(e["x"]) - player["x"]) * (float(e["x"]) - player["x"]) + (float(e["y"]) - player["y"]) * (float(e["y"]) - player["y"]))
	if not (d < rng):
		return 0.0
	if rs.world != null and rs.world.line_blocked(player["x"], player["y"], float(e["x"]), float(e["y"])):
		return 0.0
	return k * (1.0 - d / rng)


## Like clipped_draw, but only over window columns in front of the body (glass within GLASS_REACH of it).
static func window_draw(rs: RenderState, c: Canvas, x0: float, x1: float, depth: float, fn: Callable) -> void:
	var a: int = maxi(0, int(floor(x0 / rs.col_w)))
	var b: int = mini(rs.cols - 1, int(floor(x1 / rs.col_w)))
	var run_start := -1
	var col: int = a
	while col <= b + 1:
		var z: float = rs.zbuf[col] if col <= b else 0.0
		var vis: bool = col <= b and z <= depth and rs.tch[col] == TILE_WINDOW and depth - z <= GLASS_REACH
		if vis and run_start < 0:
			run_start = col
		if not vis and run_start >= 0:
			c.save()
			c.begin_path()
			c.rect(run_start * rs.col_w, 0, (col - run_start) * rs.col_w, rs.oh)
			c.clip()
			fn.call(c)
			c.restore()
			run_start = -1
		col += 1


## Vessels where the body is seen: open columns at full strength (walls hide them), window columns muted. Returns nodes drawn.
static func draw_seen(rs: RenderState, c: Canvas, p: Pose, e: Dictionary, age: float, x0: float, x1: float, depth: float, player: Dictionary) -> int:
	_fit = p.vol
	var n: Array = [0]  # lambdas capture by value: count through an array
	var open := func(cv: Canvas) -> void:
		var k := draw_vessels(rs, cv, p, e, age, -1.0)
		n[0] += k
		if k > 0:
			paint_flush(rs, cv, p, e, 1.0)
	EchoLayer.clipped_draw(rs, c, x0, x1, depth, open)
	var m: float = window_mute(rs, e, player)
	if m > 0.01:
		var glass := func(cv: Canvas) -> void:
			var k := draw_vessels(rs, cv, p, e, age, m)
			n[0] += k
			if k > 0:
				paint_flush(rs, cv, p, e, 1.0)
		window_draw(rs, c, x0, x1, depth, glass)
	_fit = false
	return n[0]


## Vessel dot radius (px) from the figure's on-screen height: figPx x 0.016 x vessels.size, scaled by wscale (0.6..1.5).
static func rad(rs: RenderState, Y: PackedFloat32Array, fit: bool) -> float:
	var fig_px: float = maxf(maxf(absf(Y[8] - Y[0]), absf(Y[9] - Y[0])), 1.0)
	var r: float = maxf(1.0, fig_px * 0.016 * tun("size")) * (minf(1.5, maxf(0.6, rs.wscale)) if rs.wscale > 0.0 else 1.0)
	return maxf(0.75, r * VOL_K) if fit else r


## Coral skin flush from the flush values of the draw_vessels call just made. Effects High only.
static func paint_flush(rs: RenderState, c: Canvas, p: Pose, e: Dictionary, sa: float) -> void:
	if rs.fx != 2:
		return
	if not (flush[0] > 0.0 or flush[1] > 0.0 or flush[2] > 0.0 or flush[3] > 0.0):
		return
	var lk: Dictionary = e["look"] if e.get("look") is Dictionary else p.look
	_flush_opts.alpha = 1.0
	_flush_opts.sa = sa
	_flush_opts.reduced = rs.reduced
	FigureVolDraw.draw_flush(c, p, lk, flush, _flush_opts)


static func level(a: float) -> int:
	return maxi(1, mini(LEVELS, int(floor(a * LEVELS + 0.5))))


## Path segment of edge (child i, parent p) from s0 to s1 (0..1) into c (along the limb curve when there is one).
static func segment(c: Canvas, nodes: Array, i: int, p: int, X: PackedFloat32Array, Y: PackedFloat32Array, s0: float, s1: float) -> void:
	var ax: float = _nx[p]
	var ay: float = _ny[p]
	var bx: float = _nx[i]
	var by: float = _ny[i]
	var cc := Vessels.edge_ctrl(nodes[p], nodes[i], X, Y)
	var curved: bool = cc[0]
	if s0 <= 0.0 and s1 >= 1.0:
		c.move_to(ax, ay)
		if curved:
			c.quad_to(cc[1], cc[2], bx, by)
		else:
			c.line_to(bx, by)
		return
	var steps: int = 4 if curved else 1
	for k in steps + 1:
		var pt := Vessels.edge_at([ax, ay], curved, [cc[1], cc[2]], [bx, by], s0 + (s1 - s0) * k / steps)
		if k == 0:
			c.move_to(pt[0], pt[1])
		else:
			c.line_to(pt[0], pt[1])


static func _queue_hl(hl: Array, i: int, p: int, s: float, trail: float, a: float) -> void:
	if not (s >= 0.0) or s > 1.0 + trail or a < 0.02:
		return
	var s0: float = maxf(0.0, s - trail)
	var s1: float = minf(1.0, s)
	if s1 - s0 < 0.01:
		return
	var lv := level(a)
	hl[lv].append(i)
	hl[lv].append(p)
	hl[lv].append(s0)
	hl[lv].append(s1)


## Vessel network for one vheart echo e at pose slots p.X / p.Y, age s since the beat reached them. mute < 0 = none.
## Returns the number of nodes drawn (0 when off).
static func draw_vessels(rs: RenderState, c: Canvas, p: Pose, e: Dictionary, age: float, mute: float) -> int:
	_arrays()
	Vessels.all()  # builds the node tables on first use
	var X := p.X
	var Y := p.Y
	flush[0] = 0.0
	flush[1] = 0.0
	flush[2] = 0.0
	flush[3] = 0.0
	if e.get("kind") != "vheart" or not on():
		return 0
	var q: int = rs.quality
	if q < 1 or float(q) < tun("minQuality"):
		return 0
	if e.get("vampire") != null or e.get("body") == "vampire" or e.get("bodyKind") == "vampire":
		return 0
	var mk: float = (1.0 if mute > 1.0 else mute) if mute >= 0.0 else 1.0
	var b: float = (minf(1.0, float(e["strength"])) if (e.get("strength") is float or e.get("strength") is int) else 1.0) * mk
	if not (b > 0.01) or not ((float(e["stateK"]) > 0.0) if (e.get("stateK") is float or e.get("stateK") is int) else true):
		return 0
	var reduced: bool = rs.reduced
	var pws: float = tun("pwvScale")
	var tm: Variant = Vessels.timing(float(e.get("bpm", 0.0)), reduced, pws) if age >= 0.0 else null
	if tm != null and age >= tm["life"]:
		return 0
	var opts := {"base": tun("alpha"), "hotK": tun("hot"), "veinK": tun("veins"), "reduced": reduced}
	var r: float = rad(rs, Y, _fit)
	var halo: float = tun("halo") if (not reduced and q >= 2) else 0.0
	var edge_k: float = tun("edges") if q >= 2 else 0.0
	var hl_k: float = tun("highlight") if (q >= 2 and not reduced and tm != null) else 0.0
	var cap: float = REDUCED_CAP if reduced else 1.0
	var tr: Variant = Vessels.travel(pws) if (tm != null and not reduced) else null
	var tail: float = (tm["life"] - age) / Vessels.TAIL if (tm != null and tm["life"] - age < Vessels.TAIL) else 1.0
	var list: Array = [Vessels.VEINS, Vessels.ARTERIES]
	var n := 0
	c.save()
	c.line_cap = "round"
	c.line_join = "round"
	for li in 2:
		var nodes: Array = list[li]
		var vein: bool = li == 0
		var rgb: Array = Vessels.VEIN_RGB if vein else Vessels.ARTERY_RGB
		var rr: float = r * (VOL_VEIN if _fit else 1.6) if vein else r
		var style := "rgb(%d,%d,%d)" % [rgb[0], rgb[1], rgb[2]]
		for i in nodes.size():
			var pt := Vessels.point(nodes[i], X, Y)
			_nx[i] = pt[0]
			_ny[i] = pt[1]
			_na[i] = vessel_alpha(nodes[i], e, opts) * b
			var env: float = Vessels.pulse(vein, i, age, tm, pws) if tm != null else 1.0
			_ne[i] = 1.0 if env > 1.0 else env
		if not vein:
			var ha: float = _na[0] * _ne[0]
			if ha > rs.vessel_heart:
				rs.vessel_heart = ha
			for i in nodes.size():
				var id: String = nodes[i]["id"]
				var fi: int = 0 if id == "temporal" else (1 if id == "carotid" else (2 if id == "radialL" else (3 if id == "radialR" else -1)))
				if fi >= 0:
					var fv: float = _na[i] * _ne[i]
					flush[fi] = cap if fv > cap else fv
			for i in range(nodes.size() - 2, nodes.size()):
				var fa: float = _na[i] * _ne[i]
				if fa > rs.vessel_feet:
					rs.vessel_feet = fa
		# ---- Edges (quality 2+): dim base line glowing with its end nodes, then the travelling highlight ----
		if edge_k > 0.0:
			var es: Array = Vessels.edges(vein)
			var lines: Array = []
			var hls: Array = []
			for k in LEVELS + 1:
				lines.append([])
				hls.append([])
			var dl: Variant = (tr["vein"] if vein else tr["art"]) if tr != null else null
			var trail: float = TRAIL_VEIN if vein else TRAIL_ART
			for k in es.size():
				var i: int = es[k]["i"]
				var pi: int = es[k]["p"]
				var env2: float = maxf(_ne[i], _ne[pi])
				var a: float = edge_k * _na[i] * env2
				if a > cap:
					a = cap
				if a >= 0.02:
					lines[level(a)].append(i)
					lines[level(a)].append(pi)
				if hl_k > 0.0 and dl != null:
					var ap: float = _na[pi]
					var ai: float = _na[i]
					var s: float = Vessels.edge_front(age, dl[pi], dl[i])
					var hv: float = 0.5 if vein else 1.0
					_queue_hl(hls, i, pi, s, trail, minf(1.0, hl_k * hv * tail * (ap + (ai - ap) * minf(1.0, maxf(0.0, s)))))
					if not vein and tm["dubK"] > 0.0:
						var s2: float = Vessels.edge_front(age - tm["dub"], dl[pi], dl[i])
						_queue_hl(hls, i, pi, s2, trail, minf(1.0, hl_k * tm["dubK"] * tail * (ap + (ai - ap) * minf(1.0, maxf(0.0, s2)))))
			c.stroke_style = style
			c.line_width = maxf(0.75, (0.9 if vein else 0.55) * r)
			for lv in range(1, LEVELS + 1):
				var bk: Array = lines[lv]
				if bk.is_empty():
					continue
				c.global_alpha = float(lv) / LEVELS
				c.begin_path()
				for k in range(0, bk.size(), 2):
					segment(c, nodes, bk[k], bk[k + 1], X, Y, 0.0, 1.0)
				c.stroke()
			c.line_width = maxf(1.0, (1.1 if vein else 0.85) * r)
			for lv in range(1, LEVELS + 1):
				var bk2: Array = hls[lv]
				if bk2.is_empty():
					continue
				c.global_alpha = float(lv) / LEVELS
				c.begin_path()
				for k in range(0, bk2.size(), 4):
					segment(c, nodes, bk2[k], bk2[k + 1], X, Y, bk2[k + 2], bk2[k + 3])
				c.stroke()
		# ---- Nodes ----
		var buckets: Array = []
		for k in LEVELS + 1:
			buckets.append(null)
		for i in nodes.size():
			var env3: float = _ne[i]
			if env3 <= 0.005:
				continue
			var a2: float = _na[i] * env3
			if a2 > cap:
				a2 = cap
			if a2 < 0.02:
				continue
			var lv2 := level(a2)
			if buckets[lv2] == null:
				buckets[lv2] = []
			buckets[lv2].append(i)
			n += 1
		c.fill_style = style
		for lv in range(1, LEVELS + 1):
			var bkn: Variant = buckets[lv]
			if bkn == null:
				continue
			var al: float = float(lv) / LEVELS
			for pass_i in range(0 if halo > 0.0 else 1, 2):
				var pr: float = rr * 2.4 if pass_i == 0 else rr
				c.global_alpha = al * halo if pass_i == 0 else al
				c.begin_path()
				for k in (bkn as Array).size():
					var x: float = _nx[bkn[k]]
					var y: float = _ny[bkn[k]]
					c.move_to(x + pr, y)
					c.arc(x, y, pr, 0.0, TWO_PI)
				c.fill()
	c.restore()
	c.global_alpha = 1.0
	rs.vessel_nodes += n
	return n
