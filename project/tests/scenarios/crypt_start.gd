extends RefCounted
## Scenario: the crypt start, one ping at 0.5 s. (js frame-golden scene 'crypt-start')


func setup(g: Node) -> void:
	g.debug_map("crypt")
	g.player.place(g.world.start.x, g.world.start.y, 0.0)


func step(g: Node, _delta: float) -> Dictionary:
	if g.frame_no == 30:
		g.ping_clicks += 1
	return {}
