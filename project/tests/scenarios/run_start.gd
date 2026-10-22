extends RefCounted
## Scenario: a new run (seed 42) from the title: the "Night 1" card, HUD, a ping at 1.0 s.
## Use: godot --path project --rendering-driver opengl3 --write-movie out/run_start/f.png --fixed-fps 60 --quit-after 150 -- --scenario=run_start


func setup(g: Node) -> void:
	g.flow.seed_param = 42
	g.set_state("title")
	g.flow.begin_run()


func step(g: Node, _delta: float) -> Dictionary:
	if g.frame_no == 60:
		g.ping_clicks += 1
	return {}
