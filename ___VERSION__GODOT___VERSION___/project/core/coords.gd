class_name Coords
extends RefCounted
## JS world (x, y, z) -> Godot (x, z, y): 1 cell = 1 m, JS height z in [0, 1] becomes Godot y.
## Only for rendering; logic stays in JS (x, y) floats.


static func to_godot(x: float, y: float, z: float = 0.0) -> Vector3:
	return Vector3(x, z, y)


static func to_js_xy(p: Vector3) -> Vector2:
	return Vector2(p.x, p.z)


## Vertical scale so a wall of JS height 1 projects like js/render.js: the JS draws a wall at distance d
## oh/d pixels tall (oh = 360), while a 66 degree horizontal FOV at 640 px has focal length 320 / tan(33 deg).
const Z_SCALE: float = 360.0 * 0.6494075931975105 / 320.0


## Render-space position: like to_godot but with heights scaled by Z_SCALE (eye height 0.5 -> Z_SCALE / 2).
static func to_view(x: float, y: float, z: float = 0.0) -> Vector3:
	return Vector3(x, z * Z_SCALE, y)
