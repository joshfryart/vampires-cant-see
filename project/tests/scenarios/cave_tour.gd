extends RefCounted
## Scenario: The Long Night, a tour of the Hollow (seed 7): the start in the Coffin Nook, then one ping at each of the first beats
## (drip gallery, squeeze, echo hall with bats, still pool, ...), and the dawn warning at the end. Critter glyphs, drips and the stage
## card are what to look at.
## Use: godot --path project --rendering-driver opengl3 --write-movie <ABSOLUTE dir>\f.png --fixed-fps 60 --quit-after 420 -- --scenario=cave_tour
## Saves are in memory (Game.boot, 0.22.0): the user:// checkpoint is untouched, and the tour is always a fresh install's first Long Night
## (the guided night on the first-run Hollow layout, whatever tutorialDone says in the real rogue save).

const BEAT_FRAMES := 60
var _cells: Array = []


func setup(g: Node) -> void:
	g.flow.seed_param = 7
	g.set_state("title")
	g.rogue.new_trek(7)
	for b in g.rogue.trek.def["beats"]:
		_cells.append(Vector2(float(b["cell"][0]) + 0.5, float(b["cell"][1]) + 0.5))


func step(g: Node, _delta: float) -> Dictionary:
	var f: int = g.frame_no
	var k: int = (f - 20) / BEAT_FRAMES
	var at: int = (f - 20) % BEAT_FRAMES
	if f >= 20 and k < _cells.size() and k < 6:
		if at == 0 and k > 0:
			var c: Vector2 = _cells[k]
			var nxt: Vector2 = _cells[k + 1] if k + 1 < _cells.size() else c + Vector2(1, 0)
			g.player.place(c.x, c.y, atan2(nxt.y - c.y, nxt.x - c.x))
		if at == 15:
			g.ping_clicks += 1
	if f == 330:
		g.night.skip_to(5, 30)
	return {}
