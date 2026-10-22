extends SceneTree
## Headless micro-benchmark for sonar pulses, raycast and the pulse textures (town map).
## Usage: godot --headless --path project -s res://tests/tools/sonar_bench.gd
## Prints SONAR_BENCH {json} with microseconds per operation.


func _init() -> void:
	var def: Dictionary = GameData.map_def("town")
	var world := World.from_def(def)
	var px := 17.5
	var py := 12.5
	var res := {}

	# 50 pings with bounces (360 rays + children)
	var sonar := Sonar.create()
	var t0 := Time.get_ticks_usec()
	var pulses_made := 0
	for i in 50:
		sonar.pulses.clear()
		sonar.last_emit = -INF
		sonar.emit(world, px + float(i % 7) * 0.7, py + float(i % 5) * 0.3, 10.0 + i, {"facing": float(i) * 0.1, "z": 0.62})
		pulses_made += sonar.pulses.size()
	res["ping_us"] = float(Time.get_ticks_usec() - t0) / 50.0
	res["ping_pulses_avg"] = float(pulses_made) / 50.0

	# 500 footstep emits (180 rays, no bounces)
	var s2 := Sonar.create()
	t0 = Time.get_ticks_usec()
	for i in 500:
		s2.emit_sound(world, px + float(i % 11) * 0.5, py + float(i % 7) * 0.4, float(i), {"kind": "personStep", "range": 1.0, "strength": 0.3, "z": 0.0, "fade": 0.6, "visRays": 180})
		if s2.pulses.size() > 30:
			s2.pulses.clear()
	res["step_us"] = float(Time.get_ticks_usec() - t0) / 500.0

	# depth columns x 500
	var rs := RenderState.new()
	t0 = Time.get_ticks_usec()
	for i in 500:
		Raycast.depth_columns(world, px, py, float(i) * 0.05, rs.col_cos, rs.col_sin, 16.0, rs.zbuf)
	res["depth_columns_us"] = float(Time.get_ticks_usec() - t0) / 500.0

	# pulse texture sync with 22 pulses; rebuild every call (list changes)
	var s3 := Sonar.create()
	for i in 22:
		s3.emit_sound(world, px + float(i) * 0.3, py, 5.0, {"kind": "personStep", "range": 1.0, "strength": 0.3, "z": 0.0, "fade": 0.6, "visRays": 180})
	var tex := PulseTextures.new()
	t0 = Time.get_ticks_usec()
	for i in 200:
		# one pulse leaves, one arrives: the typical per-frame churn
		s3.pulses.remove_at(0)
		s3.emit_sound(world, px + float(i % 13) * 0.3, py, 5.0, {"kind": "personStep", "range": 1.0, "strength": 0.3, "z": 0.0, "fade": 0.6, "visRays": 180})
	res["emit_churn_us"] = float(Time.get_ticks_usec() - t0) / 200.0
	var churn := 0.0
	var big := Sonar.create()
	big.emit(world, px, py, 1.0, {"z": 0.62})
	for i in 200:
		s3.pulses.remove_at(0)
		s3.emit_sound(world, px + float(i % 13) * 0.3, py, 5.0, {"kind": "personStep", "range": 1.0, "strength": 0.3, "z": 0.0, "fade": 0.6, "visRays": 180})
		var a := Time.get_ticks_usec()
		tex.sync_from(s3, world)
		churn += float(Time.get_ticks_usec() - a)
	res["tex_sync_churn_us"] = churn / 200.0
	t0 = Time.get_ticks_usec()
	for i in 1000:
		tex.sync_from(s3, world)
	res["tex_sync_unchanged_us"] = float(Time.get_ticks_usec() - t0) / 1000.0

	# checksum of a ping's rays to compare before/after
	var s4 := Sonar.create()
	s4.emit(world, px, py, 1.0, {"facing": 0.3, "z": 0.62})
	var h := 0
	for p in s4.pulses:
		h = hash([h, p.vis, p.vmat, p.vnorm, p.vbeam])
	res["ray_hash"] = h
	t0 = Time.get_ticks_usec()
	var se := {}
	for i in 100:
		se = Sonar.strongest_echo(s4.pulses[0], 0.3)
	res["strongest_echo_us"] = float(Time.get_ticks_usec() - t0) / 100.0
	res["strongest_echo"] = [se.get("dist"), se.get("level"), se.get("mat")]
	# reference: the original per-ray hit_info / echo_level implementation
	var pu: Sonar.Pulse = s4.pulses[0]
	t0 = Time.get_ticks_usec()
	var best := {}
	for i in pu.vis.size():
		var d: float = pu.vis[i]
		if not (d > 0.0) or d >= pu.range - 1e-4:
			continue
		var angle: float = (float(i) / pu.vis.size()) * TAU
		var hi := Sonar.hit_info(pu, angle)
		if not hi["hit"]:
			continue
		var level: float = Acoustics.echo_level("wall", d, angle - 0.3, hi["mat"]) + 20.0 * log(maxf(hi["cosInc"], 0.25)) / log(10.0)
		if best.is_empty() or level > best["level"]:
			best = {"dist": d, "level": level, "mat": hi["mat"]}
	res["strongest_echo_ref_us"] = float(Time.get_ticks_usec() - t0)
	res["strongest_echo_same"] = best["level"] == se["level"] and best["dist"] == se["dist"]
	print("SONAR_BENCH " + JSON.stringify(res))
	quit(0)
