extends RefCounted
## Scenario: facing a window wall in the town with a chosen render quality / reduced motion / effects level, to compare the shaders.
## Extra user args: --qmode=high|low|q2|q0|reduced (default high), --qfx=0|1|2 (default 2), --qwindow (face a window wall instead of the street)
## Use: godot --path project --rendering-driver opengl3 --write-movie <abs dir>\f.png --fixed-fps 60 --quit-after 120 -- --scenario=quality_modes --qmode=low


func setup(g: Node) -> void:
	var mode := "high"
	var fxl := 2
	var window := false
	for a in OS.get_cmdline_user_args():
		if a == "--qwindow":
			window = true
		if a.begins_with("--qmode="):
			mode = a.substr(8)
		elif a.begins_with("--qfx="):
			fxl = int(a.substr(6))
	g.cfg["effects"] = fxl
	match mode:
		"low":
			g.echo_view.gov.enabled = false
			g.echo_view.gov.quality = 1
			g.echo_view.gov.mat_detail = false
		"q2":
			g.echo_view.gov.enabled = false
			g.echo_view.gov.quality = 2
		"q0":
			g.echo_view.gov.enabled = false
			g.echo_view.gov.quality = 0
		"reduced":
			g.cfg["reduceMotion"] = true
	g.apply_config()
	g.debug_map("town")
	var w: World = g.world
	if not window:
		for y in w.height:
			for x in w.width:
				if w.tile_at(x + 0.5, y + 0.5) == "g" and w.tile_at(x + 1.5, y + 0.5) == "g" and w.kind_at(x + 0.5, y + 0.5) == "outdoor":
					g.player.place(x + 0.5, y + 0.5, 0.0)
					return
	for y in w.height:
		for x in w.width:
			if w.tile_at(x + 1.5, y + 0.5) == "w" and not w.is_solid(x + 0.5, y + 0.5):
				g.player.place(x + 0.5, y + 0.5, 0.0)
				return


func step(g: Node, _delta: float) -> Dictionary:
	if g.frame_no == 20 or g.frame_no == 70:
		g.ping_clicks += 1
	return {}
