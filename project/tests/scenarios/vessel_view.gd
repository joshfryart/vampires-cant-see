extends RefCounted
## Scenario: a run in the town with the player 1.6 cells from a villager: heartbeats light their chest and the vessel wave
## travels to the hands and feet. Use: ... --write-movie out/vessel_view/f.png --fixed-fps 60 --quit-after 240 -- --scenario=vessel_view

var _placed := false


func setup(g: Node) -> void:
	g.flow.seed_param = 42
	g.set_state("title")
	g.flow.begin_run()
	g.debug_map("town")


func step(g: Node, _delta: float) -> Dictionary:
	if g.frame_no == 5:
		for p in g.people.people:
			if p.mode == "path":
				var a: float = p.angle + PI
				g.player.place(p.x + cos(a) * 1.6, p.y + sin(a) * 1.6, atan2(p.y - (p.y + sin(a) * 1.6), p.x - (p.x + cos(a) * 1.6)))
				p.mode = "path"
				break
	return {}
