extends SceneTree
## Per-figure CPU cost of EchoLayer.draw_person (op building into DrawCanvas, no painting) for one villager, by effects level,
## wave age (-1 = fully lit, uniform; 0.1/0.3 = the sweeping band that redraws the figure per height strip) and distance.
## Usage: godot --headless --path project -s res://tests/tools/fig_bench.gd
## Prints FIGBENCH lines: fx, age, dist -> avg ms, ops, stroke points, polygons.

const PF = preload("res://tests/tools/pf.gd")


func _init() -> void:
	Pose.use_struggle = false
	var fx: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/figure_vol.json"))
	var base: Dictionary = {}
	for sc in fx["scenes"]:
		if sc["in"]["echo"].get("mode") == "path" and not sc["in"]["echo"]["look"].get("coat", false):
			base = (sc["in"]["echo"] as Dictionary).duplicate()
			break
	var lights := [{"x": 6.3, "y": 4, "radius": 3}]
	for fxl in [0, 1, 2]:
		for age in [-1.0, 0.1, 0.3]:
			for dist in [1.5, 3.0, 6.0]:
				var rs := RenderState.new()
				var cv := DrawCanvas.new()
				var e := base.duplicate()
				e["x"] = 5.5 + dist
				e["y"] = 5.5
				var o := {"quality": 3, "t": 12.34, "age": age, "b": 0.9, "fx": fxl, "lights": lights, "player": {"x": 5.5, "y": 5.5, "angle": 0.0}}
				var times: Array = []
				PF.reset()
				var ops := 0
				var pts := 0
				var polys := 0
				for it in 40:
					cv.reset()
					var t0 := Time.get_ticks_usec()
					EchoLayer.draw_solo(rs, cv, e, o)
					var dt := Time.get_ticks_usec() - t0
					if it >= 5:
						times.append(dt)
					ops = cv.ops.size()
					pts = 0
					polys = 0
					for op in cv.ops:
						if op[0] == "s":
							pts += op[1].points.size()
						elif op[0] == "p":
							polys += 1
				var s := 0.0
				for v in times:
					s += v
				var top := []
				var ks := PF.us.keys()
				ks.sort_custom(func(a, b): return PF.us[a] > PF.us[b])
				for k in ks.slice(0, 7):
					top.append("%s=%.2f" % [k, float(PF.us[k]) / 1000.0 / 40.0])
				print("FIGBENCH fx=%d age=%.1f dist=%.1f avg_ms=%.2f ops=%d stroke_pts=%d polys=%d | per-call ms: %s" % [fxl, age, dist, s / times.size() / 1000.0, ops, pts, polys, " ".join(top)])
	quit(0)
