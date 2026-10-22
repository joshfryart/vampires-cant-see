extends RefCounted
## Scenario: the character creator with a robed, bearded villager. Use: ... --write-movie out/creator_view/f.png --fixed-fps 60 --quit-after 60 -- --scenario=creator_view


func setup(g: Node) -> void:
	g.set_state("title")


func step(g: Node, _delta: float) -> Dictionary:
	if g.frame_no == 5:
		g.creator.open()
		g.creator._look = Creator.preset("priest", 3)
		g.creator._view["pose"] = "walk"
		g.creator._sync_fields()
	return {}
