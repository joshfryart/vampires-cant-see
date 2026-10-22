class_name Player
extends RefCounted
## Ports js/player.js. Plain floats; input is a Dictionary {forward, strafe, turn, mouseDx}.

const DEFAULT_CFG := {"mouseSensitivity": 0.0025, "invertMouse": false, "moveSpeed": 3.0, "turnSpeedKeys": 2.4, "keyTurnSpeed": 3.2}

var x: float = 0.0
var y: float = 0.0
var angle: float = 0.0
var radius: float = 0.2


static func norm_angle(a: float) -> float:
	var r: float = fmod(a, JsMath.TWO_PI)
	if r < 0.0:
		r += JsMath.TWO_PI
	if r >= JsMath.TWO_PI or is_nan(r) or is_inf(r):
		r = 0.0
	return r


static func create(sx: float, sy: float, ang: float = 0.0) -> Player:
	var p := Player.new()
	p.x = sx
	p.y = sy
	p.angle = norm_angle(ang)
	return p


static func _num(v: Variant, d: float) -> float:
	return float(v) if (v is float or v is int) and is_finite(float(v)) else d


## Advance by dt seconds (js/player.js update). cfg keys missing fall back to DEFAULT_CFG.
func update(world: World, input: Dictionary, dt: float, cfg: Dictionary = DEFAULT_CFG) -> void:
	var d: float = clampf(_num(dt, 0.0), 0.0, 0.1)
	var sens: float = _num(cfg.get("mouseSensitivity"), DEFAULT_CFG["mouseSensitivity"])
	var speed: float = _num(cfg.get("moveSpeed"), DEFAULT_CFG["moveSpeed"])
	var turn_speed: float = _num(cfg.get("keyTurnSpeed"), _num(cfg.get("turnSpeedKeys"), DEFAULT_CFG["keyTurnSpeed"]))
	var inv: float = -1.0 if cfg.get("invertMouse", false) else 1.0
	angle = norm_angle(angle + _num(input.get("mouseDx"), 0.0) * sens * inv + _num(input.get("turn"), 0.0) * turn_speed * d)
	var f: float = _num(input.get("forward"), 0.0)
	var s: float = _num(input.get("strafe"), 0.0)
	var mx: float = f * cos(angle) + s * cos(angle + PI / 2.0)
	var my: float = f * sin(angle) + s * sin(angle + PI / 2.0)
	var length: float = sqrt(mx * mx + my * my)
	if length > 0.0 and d > 0.0:
		mx = (mx / length) * speed * d
		my = (my / length) * speed * d
		var nx: float = x + mx
		if not world.blocks(nx, y, radius):
			x = nx
		var ny: float = y + my
		if not world.blocks(x, ny, radius):
			y = ny


func place(px: float, py: float, ang: float) -> void:
	x = px
	y = py
	angle = norm_angle(ang)
