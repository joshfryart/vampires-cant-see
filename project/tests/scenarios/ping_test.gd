extends RefCounted
## Scenario: crypt-style first shot on the test map. Pings at t = 0 facing east and records for --quit-after frames.
## Use: godot --path project --rendering-driver opengl3 --write-movie out/ping_test/f.png --fixed-fps 60 --quit-after 200 -- --scenario=ping_test


func setup(g: Node) -> void:
	g.debug_map("test")
	g.player.place(g.world.start.x, g.world.start.y, 0.0)


func step(g: Node, _delta: float) -> Dictionary:
	if g.frame_no == 1:
		g.ping_clicks += 1
	return {}
