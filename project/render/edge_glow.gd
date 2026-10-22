extends RefCounted
## Warm directional screen-edge glow when the player stands in torchlight (js render.js edgeSides / drawAtmosphere).
## Pure computation with a low-pass bearing state; the HUD view draws it with shaders/edge_glow.gdshader (additive).

const EDGE_GLOW_MAX := 1.0

var cos_state: float = 0.0
var side_state: float = 0.0
var init: bool = false
var left: float = 0.0
var right: float = 0.0
var top: float = 0.0


static func alpha_for(lit: float) -> float:
	var k: float = clampf(lit, 0.0, 1.0) if is_finite(lit) else 0.0
	return pow(k, 1.2) * 0.5 * EDGE_GLOW_MAX


static func zone_alpha(core: float, outer: float) -> float:
	return alpha_for(maxf(core, 0.35 * outer))


## Updates left/right/top (0..1) for the player standing in world.
func compute(world: World, player: Player, reduced: bool) -> void:
	left = 0.0
	right = 0.0
	top = 0.0
	if world == null or player == null:
		return
	var px: float = player.x
	var py: float = player.y
	var ea: float = zone_alpha(world.light_at(px, py), world.outer_at(px, py))
	if not (ea > 0.0):
		init = false
		return
	var sx: float = 0.0
	var sy: float = 0.0
	var sw: float = 0.0
	for l in world.lights:
		var dx: float = l["x"] - px
		var dy: float = l["y"] - py
		var d: float = sqrt(dx * dx + dy * dy)
		var rad: float = l["radius"]
		if d > 3.0 * rad:
			continue
		var ro: float = rad * 1.8
		if d >= ro:
			continue
		var w: float = 1.0 if d <= 0.5 * ro else 2.0 - 2.0 * d / ro
		if not (w > 0.0):
			continue
		var ang: float = atan2(dy, dx) - player.angle
		var rel: float = atan2(sin(ang), cos(ang))
		if d > 0.05:
			sx += w * cos(rel)
			sy += w * sin(rel)
		sw += w
	if not (sw > 0.0):
		init = false
		return
	var cos_rel: float = sx / sw
	var side: float = clampf(sy / sw, -1.0, 1.0)
	if not init or reduced:
		cos_state = cos_rel
		side_state = side
		init = true
	else:
		cos_state += (cos_rel - cos_state) * 0.15
		side_state += (side - side_state) * 0.15
	cos_rel = cos_state
	side = side_state
	var a: float = absf(side)
	var near: float = 1.0 + 0.6 * a
	var far: float = 1.0 - 0.6 * a
	right = minf(1.0, ea * (near if side >= 0.0 else far))
	left = minf(1.0, ea * (far if side >= 0.0 else near))
	top = minf(1.0, ea * (0.5 + 0.5 * maxf(0.0, cos_rel)))
