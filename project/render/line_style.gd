class_name LineStyle
extends RefCounted
## One stroke family for the Ink-Etched style (docs/STYLE.md sections 1 and 4).
## `ink` is true only when the current world has a non-empty `wall_style` (see ink_for). Every classic branch returns the literal
## value the drawing code used before this class existed, so the parity hashes do not move.

const INK_FILL := Color8(4, 3, 6)
const BONE := [255, 252, 244]
const HALO := [255, 236, 210]
const TAPER_FRAC := 0.14
const TAPER_MUL := 0.6
const TAPER_MIN_LEN := 10.0


## Ink mode: the world carries a non-empty wall_style (S1 adds World.wall_style; until then this is always false).
static func world_ink(world: Variant) -> bool:
	if world == null or not (world is Object):
		return false
	if not ("wall_style" in world):
		return false
	var ws: Variant = world.get("wall_style")
	return (ws is Dictionary or ws is Array or ws is String) and not ws.is_empty()


static func ink_for(rs: RenderState) -> bool:
	return rs != null and world_ink(rs.world)


## Outline width at a distance. Classic 1.5 inside 1.5 cells else 1.0; ink is continuous, 1.75 up close to 1.25 from 2.5 cells out.
static func contour_width(depth: float, ink: bool, wscale: float = 1.0) -> float:
	if not ink:
		return (1.5 if depth < 1.5 else 1.0) * wscale
	return (1.25 + 0.5 * clampf((2.5 - depth) / 1.5, 0.0, 1.0)) * wscale


## Detail strokes (strata, cracks, grain, floor marks). `classic` is the width the call site used before (spec table: 0.7).
static func detail_width(ink: bool, wscale: float = 1.0, classic: float = 0.7) -> float:
	return (0.8 if ink else classic) * wscale


## Thin / taper floor: 0.7 classic, 0.35 x w in ink.
static func thin_width(w: float, ink: bool) -> float:
	return 0.35 * w if ink else 0.7


## Figure outline: the locked victim gets 1.6 (ink 2.0), everyone else the contour width.
static func figure_width(depth: float, locked: bool, ink: bool, wscale: float = 1.0) -> float:
	if locked:
		return (2.0 if ink else 1.6) * wscale
	return contour_width(depth, ink, wscale)


static func limb_mul(ink: bool) -> float:
	return 1.6 if ink else 1.7


## Flash widening: +0.5 f (x wscale) in both styles.
static func flash_width(w: float, f: float, wscale: float) -> float:
	return w + 0.5 * f * wscale


## Boil amplitude in px: 0.7 classic, 0.5 ink.
static func boil_amp(ink: bool, wscale: float = 1.0) -> float:
	return (0.5 if ink else 0.7) * wscale


## Alpha for a pulse of strength b at a distance. Classic is Sprites.line_alpha exactly. The flash term (+0.6 (1 - age / 0.12)) is added by the caller.
static func ping_lit(b: float, depth: float, ink: bool) -> float:
	if not ink:
		return Sprites.line_alpha(b, depth)
	return minf(1.0, maxf(1.15 * pow(b, 0.65), 0.2 + 0.6 * b)) / (1.0 + 0.10 * depth)


## Open strokes become three pieces: the first and last 14% of the arc length at 0.6 w, the middle at w. Closed strokes (first == last)
## and strokes shorter than 10 px are one stroke, as is everything in classic mode. Emits begin_path / move_to / line_to... / stroke per piece
## and leaves c.line_width at w.
static func taper(c: Canvas, pts: PackedVector2Array, w: float, ink: bool) -> void:
	if pts.size() < 2:
		return
	var total := 0.0
	for i in range(1, pts.size()):
		total += pts[i - 1].distance_to(pts[i])
	var closed: bool = pts.size() > 2 and pts[0].is_equal_approx(pts[pts.size() - 1])
	if not ink or closed or total < TAPER_MIN_LEN:
		c.line_width = w
		c.begin_path()
		c.move_to(pts[0].x, pts[0].y)
		for i in range(1, pts.size()):
			c.line_to(pts[i].x, pts[i].y)
		c.stroke()
		return
	var a: float = total * TAPER_FRAC
	var b: float = total * (1.0 - TAPER_FRAC)
	_piece(c, pts, 0.0, a, w * TAPER_MUL)
	_piece(c, pts, a, b, w)
	_piece(c, pts, b, total, w * TAPER_MUL)
	c.line_width = w


static func _piece(c: Canvas, pts: PackedVector2Array, s0: float, s1: float, w: float) -> void:
	c.line_width = w
	c.begin_path()
	var acc := 0.0
	var started := false
	for i in range(1, pts.size()):
		var p0: Vector2 = pts[i - 1]
		var p1: Vector2 = pts[i]
		var seg: float = p0.distance_to(p1)
		var e: float = acc + seg
		if e > s0 and acc < s1 and seg > 0.0:
			var u0: float = maxf(0.0, (s0 - acc) / seg)
			var u1: float = minf(1.0, (s1 - acc) / seg)
			var q0: Vector2 = p0.lerp(p1, u0)
			var q1: Vector2 = p0.lerp(p1, u1)
			if not started:
				c.move_to(q0.x, q0.y)
				started = true
			c.line_to(q1.x, q1.y)
		acc = e
	c.stroke()


## Ink: fill the current path with the near-black fill (wall faces, closed props, critter bodies, figure head and torso). Classic: nothing.
static func fill_silhouette(c: Canvas, ink: bool) -> void:
	if not ink:
		return
	var prev_a: float = c.global_alpha
	c.fill_style = "#040306"
	c.global_alpha = 1.0
	c.fill()
	c.global_alpha = prev_a


## Sample a quadratic Bezier into a polyline (n segments).
static func quad_points(x0: float, y0: float, cx: float, cy: float, x1: float, y1: float, n: int = 8) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in n + 1:
		var u: float = float(i) / n
		var v: float = 1.0 - u
		out.append(Vector2(v * v * x0 + 2.0 * v * u * cx + u * u * x1, v * v * y0 + 2.0 * v * u * cy + u * u * y1))
	return out


const HUD_INK := {"frame": 0.8, "primary": 1.25, "detail": 1.0, "emphasis": 2.0}


## HUD stroke widths by role. Classic returns `classic`, the literal the call site used (they differ: 0.75 to 2.4).
static func hud_width(role: String, ink: bool, classic: float = 1.0) -> float:
	if not ink:
		return classic
	return float(HUD_INK.get(role, classic))


## Wall feature switches per quality and the material-detail setting (mirrored by the shader consts STRATA_Q, HALO_Q, LIP_JAG_Q in S3).
static func wall_features(q: int, mat_detail: bool) -> Dictionary:
	q = clampi(q, 0, 3)
	return {
		"contour": true,
		"width": "continuous" if q >= 2 else (1.25 if q == 1 else 1.0),
		"lip_jag": q >= 2,
		"boil": q >= 2,
		"lit_body": q >= 2,
		"halo": "full" if q == 3 else ("flash" if q == 2 else "none"),
		"strata": q == 3 and mat_detail,
		"cracks": q == 3 and mat_detail,
		"material_ticks": q == 3 and mat_detail,
		"doors": true,
		"arcs": [0, 0, 2, 4][q],
		"vibration": q >= 2,
	}
