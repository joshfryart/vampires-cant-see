extends RefCounted
## Scenario: stand 1.2 cells from the brightest town light, looking 70 degrees off it, so the warm edge glow is strongest on one side.


func setup(g: Node) -> void:
	g.debug_map("town")
	var w: World = g.world
	var best: Dictionary = {}
	for l in w.lights:
		if best.is_empty() or l["radius"] > best["radius"]:
			best = l
	var px: float = best["x"] - 1.2
	var py: float = best["y"]
	g.player.place(px, py, deg_to_rad(-70.0))
	print("EDGE_GLOW light=", best, " player=", [px, py], " lit=", w.light_at(px, py), " outer=", w.outer_at(px, py))


func step(g: Node, _delta: float) -> Dictionary:
	if g.frame_no == 40:
		var e = g.hud_view.edge
		print("EDGE_GLOW_REPORT ", [e.left, e.right, e.top])
	return {}
