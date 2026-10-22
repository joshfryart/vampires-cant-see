extends RefCounted
## Scenario: a run with the Warm Sense effect forced on (radius 14): coral halos over nearby villagers, seen through walls.
## Use: godot --path project --rendering-driver opengl3 --write-movie out/warm_halo/f.png --fixed-fps 60 --quit-after 120 -- --scenario=warm_halo


func setup(g: Node) -> void:
	g.flow.seed_param = 42
	g.set_state("title")
	g.flow.begin_run()
	g.flow.fx["warmRadius"] = 14.0
	g.debug_map("town")


func step(g: Node, _delta: float) -> Dictionary:
	if g.frame_no == 5:
		g.flow.fx["warmRadius"] = 14.0
	return {}
