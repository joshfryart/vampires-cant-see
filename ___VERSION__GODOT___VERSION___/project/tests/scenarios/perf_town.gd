extends RefCounted
## Scenario: the town street with several pings; prints the average and worst canvas-draw cost per frame (EchoView.render_frame).
## Use: godot --path project --rendering-driver opengl3 --write-movie out/perf_town/f.png --fixed-fps 60 --quit-after 400 -- --scenario=perf_town

var samples: Array = []


func setup(g: Node) -> void:
	g.debug_map("town")
	var w: World = g.world
	for y in w.height:
		for x in w.width:
			if w.tile_at(x + 0.5, y + 0.5) == "g" and w.tile_at(x + 1.5, y + 0.5) == "g" and w.kind_at(x + 0.5, y + 0.5) == "outdoor":
				g.player.place(x + 0.5, y + 0.5, 0.0)
				return


func step(g: Node, _delta: float) -> Dictionary:
	if g.frame_no in [30, 150, 270]:
		g.ping_clicks += 1
	if g.frame_no > 20:
		samples.append(g.echo_view.last_us)
	if g.frame_no == 380:
		samples.sort()
		var sum := 0
		for s in samples:
			sum += s
		print("PERF_TOWN avg_us=%d p95_us=%d max_us=%d n=%d" % [sum / samples.size(), samples[int(samples.size() * 0.95)], samples[samples.size() - 1], samples.size()])
		var parts := []
		for k in g.echo_view.prof:
			parts.append("%s=%d" % [k, int(g.echo_view.prof[k]) / maxi(1, g.frame_no)])
		print("PERF_TOWN per-frame us: ", ", ".join(parts))
	return {}
