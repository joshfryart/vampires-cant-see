extends RefCounted
## Scenario: REAL-TIME play profile. Run windowed WITHOUT --write-movie/--fixed-fps so frame times are wall-clock:
##   godot --path project --rendering-driver opengl3 -- --scenario=perf_play [--fx=0|1|2] [--vessels=0|1] [--vsync=0|1] [--secs=20] [--title]
## Starts a run in the town, drops the player in the street with the most villagers nearby, then walks, turns and pings like a player
## for --secs real seconds (after a 3 s warm-up) and prints PERFPLAY lines (frame ms percentiles, per-section costs, canvas op counts).
## Per-section costs come from tests/tools/pf.gd (PF.add / PF.cnt); they are zero unless temporary PF instrumentation is present in the
## game code (see the PF calls in git history of the profiling session); the frame/GPU/process numbers always work.
## --title profiles the idle title screen instead. The run uses an in-memory save store: the real save files are never touched.

const PF = preload("res://tests/tools/pf.gd")
const WARM := 3.0

var secs := 20.0
var title := false
var fx := 2
var vessels := true
var vsync := true
var no_move := false
var crowd := 0
var next_crowd := 0.0
var ping_gap := 0.7

var rng := RandomNumberGenerator.new()
var t_wall := 0.0
var last_us := 0
var frame_ms: Array = []
var work_ms: Array = []       # CPU time of this frame's script work (scenario + step + _render + canvas paint)
var proc_ms: Array = []       # Performance.TIME_PROCESS
var draw_calls: Array = []
var gpu_ms: Array = []
var pre_post_ms: Array = []   # RenderingServer.frame_pre_draw -> frame_post_draw
var step_start_us := 0
var pre_us := 0
var pings := 0
var next_ping := 1.0
var inp := {"forward": 0.0, "strafe": 0.0, "turn": 0.0, "mouseDx": 0.0}
var seg_end := 0.0
var started := false
var counted := 0
var saved_probe := false
var snap: Dictionary = {}
var hitches: Array = []
var last_pp := 0.0
var pf_base_us: Dictionary = {}
var pf_base_n: Dictionary = {}
var prev_work_total := 0
var placed := false
var fig_vol_sum := 0
var fig_line_sum := 0
var vessel_nodes_sum := 0
var people_n := 0
var echoes_sum := 0
var pulses_sum := 0
var rings_sum := 0


func setup(g: Node) -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--fx="):
			fx = int(a.substr(5))
		elif a.begins_with("--vessels="):
			vessels = a.substr(10) != "0"
		elif a.begins_with("--vsync="):
			vsync = a.substr(8) != "0"
		elif a.begins_with("--secs="):
			secs = float(a.substr(7))
		elif a == "--title":
			title = true
		elif a.begins_with("--crowd="):
			crowd = int(a.substr(8))
		elif a == "--nomove":
			no_move = true
	rng.seed = 4242
	print("PERFPLAY hw: adapter=%s | vendor=%s | driver_info=%s | rendering_driver=%s | refresh=%.1f Hz | window=%s | os=%s" % [
		RenderingServer.get_video_adapter_name(), RenderingServer.get_video_adapter_vendor(), str(OS.get_video_adapter_driver_info()),
		RenderingServer.get_current_rendering_driver_name(), DisplayServer.screen_get_refresh_rate(), str(DisplayServer.window_get_size()), OS.get_name() + " " + OS.get_version()])
	print("PERFPLAY settings: vsync_default=%s max_fps=%d" % [str(DisplayServer.window_get_vsync_mode()), Engine.max_fps])
	Flags.persist = false
	Flags.set_flag("vis.vessels", vessels)
	People.vessels_on = vessels
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
	g.cfg["effects"] = float(fx)
	g.apply_config()
	g.flow.store = SaveCodec.create(SaveCodec.MemoryStorage.new())
	if title:
		g.set_state("title")
	else:
		g.set_state("title")
		g.flow.begin_run()
		g.debug_map("town")
		g.night.night = 2
		g.night.blood = 80.0
	RenderingServer.viewport_set_measure_render_time(g.get_tree().root.get_viewport_rid(), true)
	RenderingServer.viewport_set_measure_render_time(g.viewport.get_viewport_rid(), true)
	RenderingServer.frame_pre_draw.connect(func() -> void: pre_us = Time.get_ticks_usec())
	RenderingServer.frame_post_draw.connect(func() -> void:
		if started:
			pre_post_ms.append((Time.get_ticks_usec() - pre_us) / 1000.0)
			work_ms.append((pre_us - step_start_us) / 1000.0))


func _busy_spot(g: Node) -> void:
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
	people_n = best
	print("PERFPLAY placed at %.1f,%.1f with %d people within 10 cells (total %d)" % [bx, by, best, g.people.people.size()])


## --crowd=N: every 2.5 s move N villagers to open ground 2-7 cells in front of the player (worst case: figures everywhere).
func _gather(g: Node) -> void:
	var w: World = g.world
	var moved := 0
	for p in g.people.people:
		if moved >= crowd:
			break
		for tries in 20:
			var a: float = g.player.angle + rng.randf_range(-0.45, 0.45)
			var d := rng.randf_range(1.5, 6.0)
			var x: float = g.player.x + cos(a) * d
			var y: float = g.player.y + sin(a) * d
			if not w.blocks(x, y, 0.3):
				p.x = x
				p.y = y
				moved += 1
				break


func step(g: Node, delta: float) -> Dictionary:
	var now := Time.get_ticks_usec()
	step_start_us = now
	if g.frame_no == 2 and not title and not placed:
		_busy_spot(g)
		placed = true
	if last_us != 0:
		t_wall += float(now - last_us) / 1e6
	var dt_ms := float(now - last_us) / 1000.0
	last_us = now
	if not started and t_wall >= WARM:
		started = true
		t_wall = 0.0
		PF.reset()
		counted = 0
		frame_ms.clear()
		work_ms.clear()
		pre_post_ms.clear()
		pf_base_us = g.echo_view.prof.duplicate()
		next_ping = 0.5
		return inp
	if started:
		counted += 1
		frame_ms.append(dt_ms)
		if dt_ms > 40.0:
			var top := []
			for k in PF.us:
				var d: int = int(PF.us[k]) - int(snap.get(k, 0))
				if d > 3000:
					top.append("%s=%.1f" % [k, d / 1000.0])
			hitches.append("PERFPLAY HITCH t=%.2f frame=%d dt=%.1fms prev-frame sections>3ms: %s | pulses=%d echoes=%d state=%s" % [t_wall, g.frame_no, dt_ms, " ".join(top), g.sonar.pulses.size(), g.people.echoes.size(), g.state] + " rs_draw_prev=%.1f" % (pre_post_ms[pre_post_ms.size() - 1] if not pre_post_ms.is_empty() else 0.0))
		snap = PF.us.duplicate()
		proc_ms.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
		draw_calls.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		var gm: float = RenderingServer.viewport_get_measured_render_time_gpu(g.get_tree().root.get_viewport_rid())
		gpu_ms.append(gm)
		fig_vol_sum += g.echo_view.rs.fig_vol
		fig_line_sum += g.echo_view.rs.fig_line
		vessel_nodes_sum += g.echo_view.rs.vessel_nodes
		echoes_sum += g.people.echoes.size()
		pulses_sum += g.sonar.pulses.size()
		rings_sum += g.ripple.rings.size()
	if crowd > 0 and started and t_wall >= next_crowd:
		next_crowd = t_wall + 1.0
		_gather(g)
	if not title and started:
		# player-like input: walk in 1-3 s legs with turns, ping every ~0.5-1.0 s
		if t_wall >= seg_end:
			seg_end = t_wall + rng.randf_range(1.0, 3.0)
			inp = {"forward": 1.0 if (rng.randf() < 0.75 and not no_move) else 0.0, "strafe": 0.0,
				"turn": rng.randf_range(-1.0, 1.0) if rng.randf() < 0.6 else 0.0, "mouseDx": 0.0}
		if t_wall >= next_ping:
			g.ping_clicks += 1
			pings += 1
			next_ping = t_wall + rng.randf_range(0.5, 1.0)
	if started and t_wall >= 5.0 and not saved_probe:
		saved_probe = true
		var ts := Time.get_ticks_usec()
		var sres: bool = g.flow.save_run("perf")
		print("PERFPLAY save_run (memory store, encode+checksum) = %.2f ms ok=%s | Log.lines=%d" % [(Time.get_ticks_usec() - ts) / 1000.0, str(sres), Log.lines.size()])
	if started and t_wall >= secs:
		_report(g)
		g.get_tree().quit()
	return inp


static func _pct(a: Array, q: float) -> float:
	if a.is_empty():
		return 0.0
	var s := a.duplicate()
	s.sort()
	return float(s[mini(s.size() - 1, int(s.size() * q))])


static func _avg(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var s := 0.0
	for v in a:
		s += float(v)
	return s / a.size()


func _report(g: Node) -> void:
	var n := maxi(1, counted)
	var avg := _avg(frame_ms)
	print("PERFPLAY ===== cfg: fx=%d vessels=%s vsync=%s title=%s secs=%.1f frames=%d pings=%d =====" % [fx, str(vessels), str(vsync), str(title), t_wall, counted, pings])
	print("PERFPLAY frame_ms avg=%.2f p50=%.2f p95=%.2f p99=%.2f max=%.2f | fps(avg)=%.1f fps(engine)=%d | >20ms=%d >33ms=%d >50ms=%d" % [
		avg, _pct(frame_ms, 0.5), _pct(frame_ms, 0.95), _pct(frame_ms, 0.99), _pct(frame_ms, 1.0), 1000.0 / maxf(avg, 0.001), Engine.get_frames_per_second(),
		frame_ms.filter(func(v): return v > 20.0).size(), frame_ms.filter(func(v): return v > 33.4).size(), frame_ms.filter(func(v): return v > 50.0).size()])
	print("PERFPLAY script_work_ms(avg/p95/max; frame start -> pre_draw)=%.2f/%.2f/%.2f  rs_draw_ms(pre->post draw, incl. vsync/swap)=%.2f/%.2f/%.2f  TIME_PROCESS_ms=%.2f  gpu_ms(root vp)=%.2f  draw_calls=%.0f" % [
		_avg(work_ms), _pct(work_ms, 0.95), _pct(work_ms, 1.0), _avg(pre_post_ms), _pct(pre_post_ms, 0.95), _pct(pre_post_ms, 1.0), _avg(proc_ms), _avg(gpu_ms), _avg(draw_calls)])
	print("PERFPLAY per-frame: fig_vol=%.2f fig_line=%.2f vessel_nodes=%.1f people_near=%d echoes=%.1f pulses=%.2f rings=%.1f" % [
		float(fig_vol_sum) / n, float(fig_line_sum) / n, float(vessel_nodes_sum) / n, people_n, float(echoes_sum) / n, float(pulses_sum) / n, float(rings_sum) / n])
	for h in hitches.slice(0, 25):
		print(h)
	var eparts := []
	for k in g.echo_view.prof:
		eparts.append("%s=%.3f" % [k, float(int(g.echo_view.prof[k]) - int(pf_base_us.get(k, 0))) / 1000.0 / n])
	print("PERFPLAY echo_view.render_frame laps (ms/frame): ", "  ".join(eparts), " | last_us=", g.echo_view.last_us)
	var keys := PF.us.keys()
	keys.sort()
	var parts := []
	for k in keys:
		parts.append("%s=%.3fms(x%.1f)" % [k, float(PF.us[k]) / 1000.0 / n, float(PF.n.get(k, 0)) / n])
	print("PERFPLAY sections (ms per frame, calls per frame): ", "  ".join(parts))
	var cks := PF.n.keys()
	cks.sort()
	var cparts := []
	for k in cks:
		if not PF.us.has(k):
			cparts.append("%s=%.1f" % [k, float(PF.n[k]) / n])
	print("PERFPLAY counters per frame: ", "  ".join(cparts))
	print("PERFPLAY nodes=%d objects=%d mem_static_MB=%.0f" % [Performance.get_monitor(Performance.OBJECT_NODE_COUNT), Performance.get_monitor(Performance.OBJECT_COUNT), Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0])
