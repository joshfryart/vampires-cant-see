extends SceneTree
## Headless probe for the outdoor stages (WP13a): generation time, attempts, open fraction, pockets, rest distance and the open-air maximum.
## Usage: godot --headless --path project -s res://tests/tools/wild_probe.gd -- --stage=wood --seeds=20 [--dump=3]
## Prints one line per seed and WILD_PROBE {json}.


func _init() -> void:
	var stage := "wood"
	var seeds_n := 20
	var dump := -1
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--stage="):
			stage = a.substr(8)
		elif a.begins_with("--seeds="):
			seeds_n = maxi(1, int(a.substr(8)))
		elif a.begins_with("--dump="):
			dump = int(a.substr(7))
	var row := StageGen.stage_row(stage)
	var worst_ms := 0.0
	var tot_ms := 0.0
	var worst_rest := 0
	var worst_open := 0.0
	var lo_f := 1.0
	var hi_f := 0.0
	var failed := 0
	for s in range(1, seeds_n + 1):
		GenWild.fails = {}
		var t0 := Time.get_ticks_usec()
		var d := StageGen.generate(stage, s)
		var ms := float(Time.get_ticks_usec() - t0) / 1000.0
		if d.is_empty():
			failed += 1
			print("seed %d FAILED %s" % [s, str(GenWild.fails)])
			continue
		var rep := StageGen.analyze(d, row)
		var oa := GenWild.open_air_max(d)
		worst_ms = maxf(worst_ms, ms)
		tot_ms += ms
		worst_rest = maxi(worst_rest, int(rep["max_rest_dist"]))
		worst_open = maxf(worst_open, oa)
		lo_f = minf(lo_f, float(rep["open_fraction"]))
		hi_f = maxf(hi_f, float(rep["open_fraction"]))
		print("seed %d ms %.0f attempts %d open %.3f rest %d pockets %d openair %.2f crit %d props %d amb %d lights %d fails %s" % [s, ms, GenWild.last_attempts, rep["open_fraction"], rep["max_rest_dist"], d["pockets"].size(), oa, d["critters"].size(), d["props"].size(), d["ambient"].size(), d["lights"].size(), str(GenWild.fails)])
		if s == dump:
			for r in d["rows"]:
				print(r)
	print("WILD_PROBE " + JSON.stringify({"stage": stage, "seeds": seeds_n, "failed": failed, "avg_ms": tot_ms / float(seeds_n), "worst_ms": worst_ms, "worst_rest": worst_rest, "worst_open_air": worst_open, "open_lo": lo_f, "open_hi": hi_f}))
	quit(0)
