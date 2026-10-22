extends SceneTree
## F3 CPU budget benchmark (headless): per-frame cost of the logic and the 2D echo layer on the town map with 14 villagers
## and live pulses. Prints one line  F3_BENCH {json}  with average and 95th percentile milliseconds per component.
## Usage: godot --headless --path project -s res://tests/tools/bench.gd


func _init() -> void:
	var def: Dictionary = GameData.map_def("town")
	var world := World.from_def(def)
	var player := Player.create(17.5, 12.5, 0.0)
	var sonar := Sonar.create()
	var people := People.create(world, def, {"seed": 5, "noForge": true})
	var view := EchoView.new()
	var rs := RenderState.new()
	var canvas := DrawCanvas.new()
	var pose := Pose.new()
	var dt := 1.0 / 60.0
	var t := 0.0
	var cast_ms: Array = []
	var people_ms: Array = []
	var echo_ms: Array = []
	var draw_ms: Array = []
	var tex_ms: Array = []
	var total_ms: Array = []
	var textures := PulseTextures.new()
	var ctx := {"player": {"x": player.x, "y": player.y}, "playerLit": 0.0, "react": GameData.sounds()["react"], "grace": 0.0}
	var tan_half := rs.tan_half()
	for frame in 900:
		t += dt
		if frame % 48 == 5:
			sonar.emit(world, player.x, player.y, t, {"facing": player.angle, "z": 0.62})
		if frame % 90 == 40:
			sonar.emit_sound(world, player.x + 2.0, player.y, t, {"kind": "personStep", "range": 1.0, "strength": 0.3, "z": 0.0, "fade": 0.6, "visRays": 180})
		player.angle = fmod(player.angle + 0.01, TAU)
		sonar.prune(t)
		var t0 := Time.get_ticks_usec()
		people.update(world, dt, ctx)
		var made := people.update_echoes(sonar, t - dt, t)
		var t1 := Time.get_ticks_usec()
		Raycast.depth_columns(world, player.x, player.y, player.angle, rs.col_cos, rs.col_sin, 16.0, rs.zbuf)
		var t2 := Time.get_ticks_usec()
		textures.sync_from(sonar)
		var t3 := Time.get_ticks_usec()
		canvas.reset()
		var echoes: Array = []
		for e in people.echoes:
			echoes.append(EchoView.echo_to_dict(e))
		rs.update_boil(t)
		EchoLayer.draw_echoes(rs, canvas, pose, echoes, sonar.fade, t, {"x": player.x, "y": player.y, "angle": player.angle}, tan_half)
		var t4 := Time.get_ticks_usec()
		if frame >= 60:
			people_ms.append((t1 - t0) / 1000.0)
			cast_ms.append((t2 - t1) / 1000.0)
			tex_ms.append((t3 - t2) / 1000.0)
			echo_ms.append((t4 - t3) / 1000.0)
			total_ms.append((t4 - t0) / 1000.0)
		draw_ms.append(float(made.size()))
	var res := {}
	for pair in [["people_update_and_echoes", people_ms], ["raycast_320_cols", cast_ms], ["pulse_texture_sync", tex_ms], ["echo_layer_draw", echo_ms], ["total", total_ms]]:
		var a: Array = pair[1].duplicate()
		a.sort()
		var sum := 0.0
		for v in a:
			sum += v
		res[pair[0]] = {"avg_ms": snappedf(sum / a.size(), 0.001), "p95_ms": snappedf(a[int(a.size() * 0.95)], 0.001), "max_ms": snappedf(a[a.size() - 1], 0.001)}
	res["people"] = people.people.size()
	res["pulses_last"] = sonar.pulses.size()
	print("F3_BENCH " + JSON.stringify(res))
	quit(0)
