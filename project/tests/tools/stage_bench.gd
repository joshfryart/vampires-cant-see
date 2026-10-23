extends SceneTree
## Headless per-stage bench for generated stages (WP12). For seeds 1..N of one stage id it prints generation, ping,
## strongest_echo and depth-column timings, plus a 60 s Ambient soak with the stage's own anchors.
## frame_est_ms = depth_columns (one call per frame) + strongest_echo (one call per frame) + mean Ambient step per 60 Hz frame.
## Usage: godot --headless --path project -s res://tests/tools/stage_bench.gd -- --stage=hollow --seeds=5
## Prints STAGE_BENCH {json}.

const PING_REPEATS := 20
const ECHO_SAMPLES := 50
const COLUMN_CALLS := 200
const SOAK_FRAMES := 3600
const FOV := 1.2
const COLUMNS := 160


func _init() -> void:
	var stage := "hollow"
	var seeds_n := 5
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--stage="):
			stage = a.substr(8)
		elif a.begins_with("--seeds="):
			seeds_n = maxi(1, int(a.substr(8)))
	var gen_ms: Array = []
	var ping_ms: Array = []
	var echo_ms: Array = []
	var depth_ms: Array = []
	var amb_frame_ms: Array = []
	var pulses_avg: Array = []
	var peak_pulses: Array = []
	var built := 0
	var offs: Array = Raycast.column_offsets(FOV, COLUMNS)
	var cs: PackedFloat64Array = offs[0]
	var sn: PackedFloat64Array = offs[1]
	var zbuf := PackedFloat32Array()
	zbuf.resize(COLUMNS)
	for seed_v in range(1, seeds_n + 1):
		var t0 := Time.get_ticks_usec()
		var def: Dictionary = StageGen.generate(stage, seed_v)
		gen_ms.append(float(Time.get_ticks_usec() - t0) / 1000.0)
		if def.is_empty():
			push_error("stage_bench: no def for %s seed %d" % [stage, seed_v])
			continue
		built += 1
		var world := World.from_def(def)
		var st: Dictionary = def["start"]
		var sx: float = float(st["cell"][0]) + 0.5
		var sy: float = float(st["cell"][1]) + 0.5
		var ang: float = float(st["angle"])

		# ping from the start cell
		var n_pulses := 0
		t0 = Time.get_ticks_usec()
		for i in PING_REPEATS:
			var s := Sonar.create()
			s.emit(world, sx, sy, 0.0, {"facing": ang})
			n_pulses = s.pulses.size()
		ping_ms.append(float(Time.get_ticks_usec() - t0) / 1000.0 / PING_REPEATS)
		pulses_avg.append(float(n_pulses))

		# strongest_echo over pulses from walkable cells (range 13)
		var rows: Array = def["rows"]
		var cells: Array = []
		for y in world.height:
			for x in world.width:
				if ".@CS".find(String(rows[y])[x]) >= 0 and world.solid_grid[y * world.width + x] == 0:
					cells.append(Vector2i(x, y))
		var pulses: Array = []
		for i in ECHO_SAMPLES:
			var c: Vector2i = cells[(i * 7919) % cells.size()]
			pulses.append(Sonar.make_pulse(world, c.x + 0.5, c.y + 0.5, 0.0, 13.0, Sonar.SONAR_SPEED, 1.0, "ping", 0, 720, 0.5, 3.0))
		t0 = Time.get_ticks_usec()
		for p in pulses:
			Sonar.strongest_echo(p)
		echo_ms.append(float(Time.get_ticks_usec() - t0) / 1000.0 / ECHO_SAMPLES)

		# depth columns from the start cell
		t0 = Time.get_ticks_usec()
		for i in COLUMN_CALLS:
			Raycast.depth_columns(world, sx, sy, float(i) * 0.05, cs, sn, 16.0, zbuf)
		depth_ms.append(float(Time.get_ticks_usec() - t0) / 1000.0 / COLUMN_CALLS)

		# 60 s soak at 60 Hz with the stage's own ambient anchors, player at the start
		var amb := Ambient.new([], {})
		for an in def["ambient"]:
			amb.add(an)
		var son := Sonar.create()
		var pos := Vector2(sx, sy)
		var rng := Rng.new(7)
		var clock := 0.0
		var peak := 0
		var step_us := 0
		for f in SOAK_FRAMES:
			clock += 1.0 / 60.0
			var t1 := Time.get_ticks_usec()
			amb.step(world, son, pos, 1.0 / 60.0, rng, clock)
			step_us += Time.get_ticks_usec() - t1
			peak = maxi(peak, son.pulses.size())
		amb_frame_ms.append(float(step_us) / 1000.0 / SOAK_FRAMES)
		peak_pulses.append(float(peak))

	var res := {
		"stage": stage,
		"seeds": seeds_n,
		"built": built,
		"gen_ms": _stat(gen_ms),
		"ping_ms": _stat(ping_ms),
		"ping_pulses": _stat(pulses_avg),
		"strongest_echo_ms": _stat(echo_ms),
		"depth_columns_ms": _stat(depth_ms),
		"ambient_frame_ms": _stat(amb_frame_ms),
		"ambient_peak_pulses": _stat(peak_pulses),
	}
	var frame_mean: float = res["depth_columns_ms"]["mean"] + res["strongest_echo_ms"]["mean"] + res["ambient_frame_ms"]["mean"]
	var frame_max: float = res["depth_columns_ms"]["max"] + res["strongest_echo_ms"]["max"] + res["ambient_frame_ms"]["max"]
	res["frame_est_ms"] = {"mean": frame_mean, "max": frame_max, "budget_60hz": 16.7}
	print("STAGE_BENCH " + JSON.stringify(res))
	quit(0)


static func _stat(a: Array) -> Dictionary:
	if a.is_empty():
		return {"mean": 0.0, "max": 0.0}
	var s := 0.0
	var m := -INF
	for v in a:
		s += float(v)
		m = maxf(m, float(v))
	return {"mean": snappedf(s / a.size(), 0.0001), "max": snappedf(m, 0.0001)}
