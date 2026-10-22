extends SceneTree
## Headless per-frame cost of EchoView.render_frame and HudView.render_frame (op building, no painting) in the town with pings,
## per render quality level. Usage:
##   godot --headless --path project -s res://tests/tools/view_bench.gd [-- --frames=400 --scene=town|title|idle]
## Prints VIEWBENCH lines: ms/frame for echo_view, hud_view, op counts, and the echo_view.prof laps.

const WARM := 60


func _init() -> void:
	var frames := 400
	var scene := "town"
	var crowd := 0
	var only_q := -1
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--frames="):
			frames = int(a.substr(9))
		elif a.begins_with("--q="):
			only_q = int(a.substr(4))
		elif a.begins_with("--crowd="):
			crowd = int(a.substr(8))
		elif a.begins_with("--scene="):
			scene = a.substr(8)
	Game.manual_boot = true
	Game.test_storage = SaveCodec.MemoryStorage.new()
	Flags.persist = false
	var g := Game.new()
	g.boot()
	if scene == "title":
		g.set_state("title")
	else:
		g.flow.seed_param = 5
		g.flow.begin_run()
		g.debug_map("town")
		if scene == "town":
			_place(g)
		g.night.night = 2
	var ev: EchoView = g.echo_view
	for q in ([3, 2, 1, 0] if only_q < 0 else [only_q]):
		ev.gov.enabled = false
		ev.gov.quality = q
		ev.rs.quality = q
		ev.prof.clear()
		var t_echo := 0
		var t_hud := 0
		var le: Array = []
		var lh: Array = []
		var n := 0
		var ops_e := 0
		var ops_h := 0
		var inp := {"forward": 0.0, "strafe": 0.0, "turn": 0.4, "mouseDx": 0.0}
		for f in frames + WARM:
			if scene == "town" and f % 45 == 5:
				g.ping_clicks += 1
			if crowd > 0 and f % 90 == 0:
				_gather(g, crowd)
			if scene == "title":
				g.title_t += 1.0 / 60.0
			else:
				g.step(1.0 / 60.0, inp)
			g.card_text = ""
			g.hint_text = ""
			g.unlock_hint_t = 0.0
			ev.rs_fov = g.fov_now()
			var t0 := Time.get_ticks_usec()
			ev.render_frame(g.world, g.player, g.people, g.sonar, g.clock, g.lock_info(), g.ripple.rings)
			var t1 := Time.get_ticks_usec()
			g.hud_view.render_frame(g)
			var t2 := Time.get_ticks_usec()
			if f >= WARM:
				t_echo += t1 - t0
				t_hud += t2 - t1
				le.append(t1 - t0)
				lh.append(t2 - t1)
				n += 1
				ops_e += ev.canvas.ops.size()
				ops_h += g.hud_view.canvas.ops.size()
			if f == WARM - 1:
				ev.prof.clear()
		le.sort()
		lh.sort()
		var parts := []
		for k in ev.prof:
			parts.append("%s=%.3f" % [k, float(ev.prof[k]) / 1000.0 / n])
		print("VIEWBENCH scene=%s q=%d echo_ms=%.3f(p50 %.3f p95 %.3f) hud_ms=%.3f(p50 %.3f) echo_ops=%.0f hud_ops=%.0f hud_built=%d hud_cached=%d echo_skipped=%d depth=%d/%d | laps: %s" % [scene, q, t_echo / 1000.0 / n, le[n / 2] / 1000.0, le[int(n * 0.95)] / 1000.0, t_hud / 1000.0 / n, lh[n / 2] / 1000.0, float(ops_e) / n, float(ops_h) / n, g.hud_view.stat_built, g.hud_view.stat_cached, ev.stat_skipped, ev.stat_depth, ev.stat_depth_reused, " ".join(parts)])
	# sprite micro-benchmark with the current state: markers and props alone
	var pl := {"x": g.player.x, "y": g.player.y, "angle": g.player.angle}
	var th: float = ev.rs.tan_half()
	var cv := DrawCanvas.new()
	for pass_i in 2:
		var tm := Time.get_ticks_usec()
		for i in 1000:
			cv.reset()
			Sprites.draw_markers(ev.rs, cv, g.world, pl, g.sonar, g.clock, th)
		var tp := Time.get_ticks_usec()
		for i in 1000:
			cv.reset()
			Sprites.draw_props(ev.rs, cv, g.world, pl, g.sonar, g.clock, th)
		var te := Time.get_ticks_usec()
		print("VIEWBENCH sprites markers=%.1f us props=%.1f us (props in map %d, pulses %d)" % [(tp - tm) / 1000.0, (te - tp) / 1000.0, g.world.props.size(), g.sonar.pulses.size()])
	g.free()
	quit(0)


func _place(g: Game) -> void:
	var w: World = g.world
	var best := -1
	var bx := 0.0
	var by := 0.0
	for y in w.height:
		for x in w.width:
			if w.tile_at(x + 0.5, y + 0.5) != "g" or w.kind_at(x + 0.5, y + 0.5) != "outdoor":
				continue
			var n := 0
			for p in g.people.people:
				var d: float = sqrt((p.x - x - 0.5) * (p.x - x - 0.5) + (p.y - y - 0.5) * (p.y - y - 0.5))
				if d < 10.0:
					n += 1
			if n > best:
				best = n
				bx = x + 0.5
				by = y + 0.5
	g.player.place(bx, by, 0.0)


## Move N villagers to open ground 1.5-6 cells in front of the player (worst case: figures everywhere).
func _gather(g: Game, crowd: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var moved := 0
	for p in g.people.people:
		if moved >= crowd:
			break
		for tries in 20:
			var a: float = g.player.angle + rng.randf_range(-0.45, 0.45)
			var d := rng.randf_range(1.5, 6.0)
			var x: float = g.player.x + cos(a) * d
			var y: float = g.player.y + sin(a) * d
			if not g.world.blocks(x, y, 0.3):
				p.x = x
				p.y = y
				moved += 1
				break
