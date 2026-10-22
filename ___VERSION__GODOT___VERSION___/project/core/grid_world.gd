class_name GridWorld
extends RefCounted
## Minimal solid-grid world for ray casting. Phase 0 stand-in for core/world.gd.
## Out-of-bounds cells are solid, as in js/world.js tileAt.

var width: int = 0
var height: int = 0
var solid: PackedByteArray = PackedByteArray()


## flags is w*h characters, row-major, "1" = solid.
static func from_flags(w: int, h: int, flags: String) -> GridWorld:
	var g := GridWorld.new()
	g.width = w
	g.height = h
	g.solid.resize(w * h)
	for i in w * h:
		g.solid[i] = 1 if flags[i] == "1" else 0
	return g


## Ports js/world.js isSolid for the closed-door state (cell of floor(x), floor(y)).
func is_solid(x: float, y: float) -> bool:
	var cx: int = int(floor(x))
	var cy: int = int(floor(y))
	if cx < 0 or cy < 0 or cx >= width or cy >= height:
		return true
	return solid[cy * width + cx] == 1
