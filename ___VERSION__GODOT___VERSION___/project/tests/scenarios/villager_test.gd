extends RefCounted
## Scenario: villagers on the test map. The player stands in the east room facing the patrol loop, pings at 0.5 s and
## again at 3.0 s; the echoes of the walkers appear as fading line figures and have moved between the two pings.
## Use: godot --path project --rendering-driver opengl3 --write-movie out/villager_test/f.png --fixed-fps 60 --quit-after 300 -- --scenario=villager_test


func setup(g: Node) -> void:
	g.debug_map("test")
	g.player.place(11.5, 4.5, 0.0)


func step(g: Node, _delta: float) -> Dictionary:
	if g.frame_no == 30 or g.frame_no == 180:
		g.ping_clicks += 1
	return {}
