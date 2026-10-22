extends RefCounted
## Scenario: facing a window wall in the town (open cell west of a 'w' tile), one ping at 0.5 s. (frame-golden 'window-wall')


func setup(g: Node) -> void:
	g.debug_map("town")
	var w: World = g.world
	for y in w.height:
		for x in w.width:
			if w.tile_at(x + 1.5, y + 0.5) == "w" and not w.is_solid(x + 0.5, y + 0.5):
				g.player.place(x + 0.5, y + 0.5, 0.0)
				return


func step(g: Node, _delta: float) -> Dictionary:
	if g.frame_no == 30:
		g.ping_clicks += 1
	return {}
