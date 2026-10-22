extends RefCounted
## Scenario F1 (go/no-go): does the wall shader reproduce sonar.js sample2 on screen?
## One ping at t = 0 from a fixed pose; every frame, for a set of screen columns, the wall point under the column is
## taken from the ray cast, the expected edge-line intensity is computed on the CPU (sample2 + afterglow + lineAlpha)
## and the brightest pixel near the top and bottom edge lines is read back from the SubViewport texture.
## At the end it prints one line  F1_REPORT {json}  with onset offsets (frames) and fade-curve error per sample.
## Use: godot --path project --rendering-driver opengl3 --write-movie out/F1/f.png --fixed-fps 60 --quit-after 200 -- --scenario=f1_readback

const COLUMNS := [24, 88, 152, 216, 280, 344, 408, 472, 536, 600]
const FRAMES := 190
const HORIZON := 180.0

var samples: Array = []   # per column: {dist, wx, wy, rows: [{t, exp_b0, exp_b1, exp_i0, exp_i1, obs0, obs1}]}
var pose := {"x": 5.5, "y": 3.5, "angle": 0.35}
var frame := 0


func setup(g: Node) -> void:
	g.floor_inst.visible = false  # the floor wavefront ring is a separate effect; measure the wall alone
	g.player.place(pose["x"], pose["y"], pose["angle"])
	var hits := Raycast.cast(g.world, g.player.x, g.player.y, g.player.angle, RenderState.FOV_DEG * PI / 180.0, 320, 16.0)
	for c in COLUMNS:
		var h: Raycast.Hit = hits[c / 2]
		samples.append({"col": c, "dist": h.dist, "hit": h.hit, "wx": h.hit_x, "wy": h.hit_y, "rows": []})


func step(g: Node, _delta: float) -> Dictionary:
	frame += 1
	if frame == 3:
		g.ping_clicks += 1
	if frame > 4:
		_read(g)
	if frame >= FRAMES:
		_report(g)
		g.get_tree().quit()
	return {}


# Expected line intensity as the shader computes it: fade_color(b) * line_alpha(b, depth), luma-ish max channel.
static func _intensity(b: float, depth: float, age: float) -> float:
	if b <= 0.01:
		return 0.0
	var a: float = minf(1.0, 1.15 * pow(b, 0.65)) / (1.0 + 0.12 * depth)
	if age >= 0.0 and age < 0.12:
		# arrival flash: brighter and white for the first 0.12 s
		a = minf(1.0, a + 0.6 * (1.0 - age / 0.12))
		return a
	var c: float
	if b < 0.12:
		c = 0.84
	elif b < 0.45:
		c = lerpf(214.0, 255.0, (b - 0.12) / 0.33) / 255.0
	elif b < 0.8:
		c = lerpf(255.0, 255.0, (b - 0.45) / 0.35) / 255.0
	else:
		c = 1.0
	return a * c


func _expected(g: Node, s: Dictionary, t: float) -> Array:
	var r: PackedFloat64Array = g.sonar.sample2(s["wx"], s["wy"], t)
	var b0: float = r[0]
	var b1: float = r[1]
	var age: float = r[2]
	var fade: float = r[3]
	var b: float = maxf(b0, b1)
	if b <= 0.01:
		return [0.0, 0.0]
	var gm: float = Pose.glow(age, Pose.glow_dur(fade))
	var mul: float = gm
	if gm > 0.0:
		var kf: float = 1.0 - age / fade
		mul = gm / (kf * kf) if kf > 0.05 else gm
	else:
		mul = 0.0
	b0 *= mul
	b1 *= mul
	if maxf(b0, b1) <= 0.01:
		return [0.0, 0.0]
	return [_intensity(b0, s["dist"], age), _intensity(b1, s["dist"], age)]


## Line energy: sum over the vertical window of the brightest channel in column x. A 1 px anti-aliased line spreads its
## intensity over two rows when it sits between pixel centres, so the sum (not the per-pixel peak) tracks line intensity.
func _peak(img: Image, x: int, y0: int, y1: int) -> float:
	var total := 0.0
	for yy in range(maxi(0, y0), mini(img.get_height() - 1, y1) + 1):
		var c := img.get_pixel(x, yy)
		total += maxf(c.r, maxf(c.g, c.b))
	return total


func _read(g: Node) -> void:
	var img: Image = g.viewport.get_texture().get_image()
	if img == null or img.get_width() < 640:
		return
	var t: float = g.last_render_clock
	for s in samples:
		if not s["hit"]:
			continue
		var d: float = maxf(0.05, s["dist"])
		var y_bot: float = HORIZON + 0.5 * 360.0 / d
		var y_top: float = HORIZON - 0.5 * 360.0 / d
		var exp: Array = _expected(g, s, t)
		var obs_top := _peak(img, s["col"], int(y_top) - 3, int(y_top) + 5)
		var obs_bot := _peak(img, s["col"], int(y_bot) - 5, int(y_bot) + 3)
		s["rows"].append({"t": t, "e0": exp[0], "e1": exp[1], "o0": obs_bot, "o1": obs_top})


func _report(g: Node) -> void:
	var out: Array = []
	for s in samples:
		if not s["hit"] or s["rows"].is_empty():
			continue
		var rows: Array = s["rows"]
		var res := {"col": s["col"], "dist": s["dist"]}
		for edge in ["0", "1"]:
			var ek: String = "e" + edge
			var ok: String = "o" + edge
			var on_e := -1
			var on_o := -1
			var peak_e := 0.0
			var err_sum := 0.0
			var err_n := 0
			for i in rows.size():
				peak_e = maxf(peak_e, rows[i][ek])
				if on_e < 0 and rows[i][ek] > 0.04:
					on_e = i
				if on_o < 0 and rows[i][ok] > 0.04:
					on_o = i
			# fade curve: where the expected intensity is meaningful, compare to what was seen (relative to the expected peak)
			for i in rows.size():
				if rows[i][ek] > 0.1 * peak_e and peak_e > 0.05:
					err_sum += absf(rows[i][ok] - rows[i][ek]) / peak_e
					err_n += 1
			res["onset_e" + edge] = on_e
			res["onset_o" + edge] = on_o
			res["peak_e" + edge] = peak_e
			res["fade_err" + edge] = err_sum / err_n if err_n > 0 else 0.0
		out.append(res)
	print("F1_REPORT " + JSON.stringify(out))
	for s in samples:
		if not s["hit"]:
			continue
		var flat: Array = []
		for r in s["rows"]:
			flat.append([snappedf(r["t"], 0.001), snappedf(r["e0"], 0.001), snappedf(r["e1"], 0.001), snappedf(r["o0"], 0.001), snappedf(r["o1"], 0.001)])
		print("F1_ROWS %d %s" % [s["col"], JSON.stringify(flat)])
