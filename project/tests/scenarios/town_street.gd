extends RefCounted
## Scenario: the town street (first grass cell with grass to its east, outdoors), one ping at 0.5 s. (frame-golden 'town-street')


func setup(g: Node) -> void:
	g.debug_map("town")
	var w: World = g.world
	for y in w.height:
		for x in w.width:
			if w.tile_at(x + 0.5, y + 0.5) == "g" and w.tile_at(x + 1.5, y + 0.5) == "g" and w.kind_at(x + 0.5, y + 0.5) == "outdoor":
				g.player.place(x + 0.5, y + 0.5, 0.0)
				return


func step(g: Node, _delta: float) -> Dictionary:
	if g.frame_no == 30:
		g.ping_clicks += 1
	return {}
