extends RefCounted
## Scenario: the top-down map (M) on the town street after a ping.
## Use: godot --path project --rendering-driver opengl3 --write-movie out/map_view/f.png --fixed-fps 60 --quit-after 60 -- --scenario=map_view


func setup(g: Node) -> void:
	g.debug_map("town")


func step(g: Node, _delta: float) -> Dictionary:
	if g.frame_no == 10:
		g.ping_clicks += 1
	if g.frame_no == 20:
		g.map_view.visible = true
		g.dev_panel.visible = true
	return {}
