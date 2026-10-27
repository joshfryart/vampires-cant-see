extends SceneTree
## ms per call of Raycast.depth_columns vs depth_columns_contour (160 columns) on seeds 1..N of each ink stage, from random walkable cells and angles.
## Usage: godot --headless --path project -s res://tests/tools/depth_bench.gd -- --seeds=5. Prints DEPTH_BENCH lines.

const COLUMNS := 160
const CALLS := 400


func _init() -> void:
	var seeds_n := 5
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seeds="):
			seeds_n = maxi(1, int(a.substr(8)))
	var offs: Array = Raycast.column_offsets(1.2, COLUMNS)
	var out := PackedFloat32Array()
	out.resize(COLUMNS)
	for stage in ["hollow", "wood", "moor", "road", "inn"]:
		var tg := 0.0
		var tc := 0.0
		var tb := 0.0
		var cmax := 0.0
		for sd in range(1, seeds_n + 1):
			var def: Dictionary = StageGen.generate(stage, sd)
			def["wallStyle"] = StageGen.stage_row(stage)["wallStyle"]
			var world := World.from_def(def)
			var t0 := Time.get_ticks_usec()
			var f := ContourField.for_world(world)
			tb += float(Time.get_ticks_usec() - t0) / 1000.0
			var cells: Array = []
			for y in world.height:
				for x in world.width:
					if world.solid_grid[y * world.width + x] == 0 and ".@CS".find(String(world.rows[y])[x]) >= 0:
						cells.append(Vector2i(x, y))
			var rng := Rng.new(sd)
			var poses: Array = []
			for i in CALLS:
				var c: Vector2i = cells[int(floor(rng.next() * cells.size()))]
				poses.append([c.x + rng.next(), c.y + rng.next(), rng.next() * TAU])
			t0 = Time.get_ticks_usec()
			for p in poses:
				Raycast.depth_columns(world, p[0], p[1], p[2], offs[0], offs[1], 16.0, out)
			tg += float(Time.get_ticks_usec() - t0) / 1000.0 / CALLS
			t0 = Time.get_ticks_usec()
			for p in poses:
				var t1 := Time.get_ticks_usec()
				Raycast.depth_columns_contour(world, f, p[0], p[1], p[2], offs[0], offs[1], 16.0, out)
				cmax = maxf(cmax, float(Time.get_ticks_usec() - t1) / 1000.0)
			tc += float(Time.get_ticks_usec() - t0) / 1000.0 / CALLS
		print("DEPTH_BENCH %s grid_ms=%.3f contour_ms=%.3f delta_ms=%.3f contour_max_ms=%.3f build_ms=%.1f" % [stage, tg / seeds_n, tc / seeds_n, (tc - tg) / seeds_n, cmax, tb / seeds_n])
	quit(0)
