extends RefCounted
## Scenario: the title menu, then the settings panel. Use: ... --write-movie out/menu_shots/f.png --fixed-fps 60 --quit-after 40 -- --scenario=menu_shots


func setup(g: Node) -> void:
	g.set_state("title")


func step(g: Node, _delta: float) -> Dictionary:
	if g.frame_no == 25:
		g.menus._view = "main"
		g.menus.sync(g)
	return {}
