class_name Coords
extends RefCounted
## JS world (x, y, z) -> Godot (x, z, y): 1 cell = 1 m, JS height z in [0, 1] becomes Godot y.
## Only for rendering; logic stays in JS (x, y) floats.


static func to_godot(x: float, y: float, z: float = 0.0) -> Vector3:
	return Vector3(x, z, y)


static func to_js_xy(p: Vector3) -> Vector2:
	return Vector2(p.x, p.z)
