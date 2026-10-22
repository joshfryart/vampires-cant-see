extends RefCounted
## Scenario: same as villager_test with registration marks (green horizon and centre lines, yellow corner square).


func setup(g: Node) -> void:
	g.player.place(11.5, 4.5, 0.0)
	g.echo_view.debug_marks = true


func step(g: Node, _delta: float) -> Dictionary:
	if g.frame_no == 30:
		g.ping_clicks += 1
	return {}
