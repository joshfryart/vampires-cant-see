class_name CritterDraw
extends RefCounted
## Line glyphs for critters (bat, rat, hare, hen, sheep, deer, wolf, crow ...), lit only by the sonar echoes of core/critters.gd
## (Critters.echoes: a snapshot where a wavefront crossed the critter). Same look as sprites.gd props: thin lines tinted by brightness
## (EchoLayer.sprite_style), depth cue (Sprites.line_alpha), hidden behind closer walls by the per-column depth buffer (clipped_draw).
## Much cheaper than a People figure: one small path per echo, no pose or strips. Pure drawing: it never changes game state.

const TWO_PI := JsMath.TWO_PI
## Seconds a glyph glows after the wavefront passes (a short afterglow, like a prop).
const GLOW := 0.7
const FLASH_AGE := 0.12
const MAX_DIST := 14.0
const DEFAULT_COL := [255, 196, 140]
const COLORS := {
	"bat": [190, 160, 255], "rat": [255, 170, 120], "rabbit": [255, 210, 160], "hare": [255, 210, 160], "deer": [255, 200, 120],
	"wolf": [255, 150, 130], "hen": [255, 220, 150], "sheep": [235, 230, 215], "crow": [170, 150, 255],
}
## Glyph family and relative size per species.
const KIND := {"bat": "wing", "crow": "wing", "rat": "rat", "rabbit": "hare", "hare": "hare", "hen": "bird", "sheep": "quad", "deer": "quad", "wolf": "quad"}
const SIZE := {"bat": 1.0, "crow": 1.3, "rat": 1.0, "rabbit": 0.8, "hare": 1.0, "hen": 0.9, "sheep": 1.1, "deer": 1.5, "wolf": 1.25}
## Height of the glyph centre above the floor (cells; 1.0 = the wall height).
const LIFT := {"bat": 0.62, "crow": 0.5}


static func colour_of(species: String) -> Array:
	return COLORS.get(species, DEFAULT_COL)


static func kind_of(species: String) -> String:
	return String(KIND.get(species, "quad"))


## Brightness 0..1 of an echo this far into its glow: pulse strength with the smooth glow curve.
static func brightness(strength: float, age: float) -> float:
	return clampf(strength * 1.6, 0.0, 1.0) * Pose.glow(age, GLOW)


## Draw every live echo of `crit` (Critters). `player` is {x, y, angle}. Returns the glyph count.
static func draw_all(rs: RenderState, c: Canvas, player: Dictionary, crit: Critters, t: float, tan_half: float) -> int:
	if crit == null or crit.echoes.is_empty():
		return 0
	var by_id := {}
	for cr in crit.critters:
		by_id[cr.id] = cr
	var half_w: float = rs.ow / 2.0
	var focal: float = half_w / tan_half
	var drawn := 0
	for e in crit.echoes:
		var age: float = t - e.t
		if age < 0.0 or age >= GLOW:
			continue
		var b := brightness(e.strength, age)
		if b <= 0.01:
			continue
		var pj := Sprites.project(player, e.x, e.y, half_w, tan_half)
		if pj.is_empty() or pj[0] > MAX_DIST:
			continue
		var depth: float = pj[0]
		var cx: float = pj[1]
		var hs: float = focal / depth
		if cx < -hs - 40.0 or cx > rs.ow + hs + 40.0:
			continue
		var live: Variant = by_id.get(e.critter_id)
		var heading: float = live.heading if live != null else 0.0
		var resting: bool = live != null and (live.state == "roost" or live.state == "sleep")
		var moving: bool = live != null and live.moving and not resting
		var face: float = 1.0 if sin(heading - player["angle"]) >= 0.0 else -1.0
		var vs: float = rs.oh / depth
		var fy: float = rs.horizon + 0.5 * vs
		var flash: bool = age < FLASH_AGE
		var alpha: float = minf(1.0, Sprites.line_alpha(b, depth) * 1.2 + (0.4 * (1.0 - age / FLASH_AGE) if flash else 0.0))
		var lw: float = (1.5 if depth < 1.5 else 1.0) * rs.wscale
		var style: String = "#ffffff" if flash else EchoLayer.sprite_style(colour_of(e.species), b)
		var sz: float = float(SIZE.get(e.species, 1.0))
		var phase: float = float(e.critter_id) * 1.7
		var kind := kind_of(e.species)
		var species: String = e.species
		var hw: float = hs * 0.5 * sz + 6.0
		c.line_width = lw
		var fn := func(cv: Canvas) -> void:
			cv.global_alpha = alpha
			CritterDraw.glyph(cv, kind, species, cx, fy, hs, vs, sz, face, t, phase, resting, moving, style)
		EchoLayer.clipped_draw(rs, c, cx - hw, cx + hw, depth, fn)
		drawn += 1
	c.global_alpha = 1.0
	return drawn


## One glyph. (cx, fy) = the critter's floor point on screen, hs / vs = pixels per cell sideways / per unit of height.
static func glyph(c: Canvas, kind: String, species: String, cx: float, fy: float, hs: float, vs: float, sz: float, face: float, t: float, phase: float, resting: bool, moving: bool, style: String) -> void:
	c.stroke_style = style
	c.begin_path()
	match kind:
		"wing":
			var cy: float = fy - float(LIFT.get(species, 0.55)) * vs
			if resting:
				_hanging(c, cx, cy - 0.25 * vs, hs * sz, vs * sz)
			else:
				_wings(c, cx, cy, hs * sz, face, t, phase, moving)
		"rat":
			_rat(c, cx, fy - 0.06 * vs, fy, hs * sz, vs * sz, face, t, phase, moving)
		"hare":
			_hare(c, cx, fy - 0.11 * vs * sz, fy, hs * sz, vs * sz, face, t, phase, moving, resting)
		"bird":
			_hen(c, cx, fy - 0.12 * vs * sz, fy, hs * sz, vs * sz, face, t, phase, moving)
		_:
			_quad(c, cx, fy - 0.2 * vs * sz, fy, hs * sz, vs * sz, face, t, phase, moving, resting)
	c.stroke()


## A flying bat seen from the front: scalloped wings that flap, a small body, two ears.
static func _wings(c: Canvas, cx: float, cy: float, hs: float, face: float, t: float, phase: float, moving: bool) -> void:
	var w: float = 0.3 * hs
	var flap: float = sin(t * 15.0 + phase) * 0.12 * hs if moving else sin(t * 6.0 + phase) * 0.05 * hs
	for side in [-1.0, 1.0]:
		var tipx: float = cx + side * w
		var tipy: float = cy - flap - 0.04 * hs
		c.move_to(cx + side * 0.03 * hs, cy - 0.02 * hs)
		c.quad_to(cx + side * w * 0.5, cy - 0.15 * hs - flap, tipx, tipy)
		c.quad_to(cx + side * w * 0.75, cy + 0.03 * hs - flap * 0.3, cx + side * w * 0.5, cy + 0.05 * hs)
		c.quad_to(cx + side * w * 0.38, cy + 0.0, cx + side * w * 0.2, cy + 0.08 * hs)
		c.quad_to(cx + side * w * 0.1, cy + 0.04 * hs, cx + side * 0.02 * hs, cy + 0.1 * hs)
	c.move_to(cx + 0.045 * hs, cy + 0.02 * hs)
	c.ellipse(cx, cy + 0.02 * hs, 0.045 * hs, 0.075 * hs, 0.0, 0.0, TWO_PI)
	c.move_to(cx - 0.035 * hs, cy - 0.04 * hs)
	c.line_to(cx - 0.05 * hs, cy - 0.11 * hs)
	c.move_to(cx + 0.035 * hs, cy - 0.04 * hs)
	c.line_to(cx + 0.05 * hs, cy - 0.11 * hs)


## A roosting bat: wings folded round the body, hanging from the ceiling by a short line.
static func _hanging(c: Canvas, cx: float, top: float, hs: float, vs: float) -> void:
	c.move_to(cx, top - 0.06 * vs)
	c.line_to(cx, top)
	c.move_to(cx, top)
	c.quad_to(cx - 0.09 * hs, top + 0.07 * vs, cx - 0.05 * hs, top + 0.16 * vs)
	c.quad_to(cx, top + 0.2 * vs, cx + 0.05 * hs, top + 0.16 * vs)
	c.quad_to(cx + 0.09 * hs, top + 0.07 * vs, cx, top)
	c.move_to(cx - 0.02 * hs, top + 0.1 * vs)
	c.line_to(cx - 0.02 * hs, top + 0.16 * vs)
	c.move_to(cx + 0.02 * hs, top + 0.1 * vs)
	c.line_to(cx + 0.02 * hs, top + 0.16 * vs)


## A rat in profile: long low body, pointed head on the facing side, round ear, curved tail, scurrying legs.
static func _rat(c: Canvas, cx: float, cy: float, fy: float, hs: float, vs: float, face: float, t: float, phase: float, moving: bool) -> void:
	var f: float = face
	c.move_to(cx + 0.12 * hs, cy)
	c.ellipse(cx, cy, 0.12 * hs, 0.06 * vs, 0.0, 0.0, TWO_PI)
	c.move_to(cx + f * 0.12 * hs, cy - 0.02 * vs)
	c.line_to(cx + f * 0.24 * hs, cy + 0.005 * vs)
	c.line_to(cx + f * 0.12 * hs, cy + 0.04 * vs)
	c.move_to(cx + f * 0.14 * hs + 0.025 * hs, cy - 0.045 * vs)
	c.ellipse(cx + f * 0.14 * hs, cy - 0.045 * vs, 0.025 * hs, 0.03 * vs, 0.0, 0.0, TWO_PI)
	c.move_to(cx - f * 0.12 * hs, cy + 0.01 * vs)
	c.quad_to(cx - f * 0.22 * hs, cy + 0.07 * vs, cx - f * 0.3 * hs, cy - 0.01 * vs)
	var s: float = sin(t * 22.0 + phase) * 0.03 * hs if moving else 0.0
	c.move_to(cx - 0.05 * hs, cy + 0.05 * vs)
	c.line_to(cx - 0.05 * hs + s, fy)
	c.move_to(cx + 0.06 * hs, cy + 0.05 * vs)
	c.line_to(cx + 0.06 * hs - s, fy)


## A hare / rabbit: round haunch, small head with two tall ears, short tail.
static func _hare(c: Canvas, cx: float, cy: float, fy: float, hs: float, vs: float, face: float, t: float, phase: float, moving: bool, resting: bool) -> void:
	var f: float = face
	var hop: float = absf(sin(t * 9.0 + phase)) * 0.06 * vs if moving else 0.0
	cy -= hop
	c.move_to(cx + 0.15 * hs, cy)
	c.ellipse(cx, cy, 0.15 * hs, 0.1 * vs, 0.0, 0.0, TWO_PI)
	var hx: float = cx + f * 0.16 * hs
	var hy: float = cy - 0.07 * vs
	c.move_to(hx + 0.07 * hs, hy)
	c.ellipse(hx, hy, 0.07 * hs, 0.055 * vs, 0.0, 0.0, TWO_PI)
	var ear_h: float = 0.1 if resting else 0.2
	c.move_to(hx - f * 0.01 * hs, hy - 0.05 * vs)
	c.quad_to(hx - f * 0.05 * hs, hy - (0.05 + ear_h) * vs, hx - f * 0.01 * hs, hy - (0.05 + ear_h * 1.1) * vs)
	c.move_to(hx + f * 0.03 * hs, hy - 0.05 * vs)
	c.quad_to(hx + f * 0.0, hy - (0.05 + ear_h * 0.9) * vs, hx + f * 0.045 * hs, hy - (0.05 + ear_h) * vs)
	c.move_to(cx - f * 0.15 * hs, cy)
	c.line_to(cx - f * 0.2 * hs, cy - 0.02 * vs)
	c.move_to(cx - f * 0.07 * hs, cy + 0.08 * vs)
	c.line_to(cx - f * 0.07 * hs, fy)
	c.line_to(cx - f * 0.02 * hs, fy)
	c.move_to(cx + f * 0.09 * hs, cy + 0.08 * vs)
	c.line_to(cx + f * 0.09 * hs, fy)


## A hen: plump body, small head with a beak on the facing side, tail fan, two legs.
static func _hen(c: Canvas, cx: float, cy: float, fy: float, hs: float, vs: float, face: float, t: float, phase: float, moving: bool) -> void:
	var f: float = face
	var bob: float = sin(t * 8.0 + phase) * 0.02 * vs if moving else 0.0
	c.move_to(cx + 0.13 * hs, cy)
	c.ellipse(cx, cy, 0.13 * hs, 0.1 * vs, 0.0, 0.0, TWO_PI)
	var hx: float = cx + f * 0.12 * hs
	var hy: float = cy - 0.12 * vs + bob
	c.move_to(hx + 0.045 * hs, hy)
	c.ellipse(hx, hy, 0.045 * hs, 0.04 * vs, 0.0, 0.0, TWO_PI)
	c.move_to(hx + f * 0.04 * hs, hy)
	c.line_to(hx + f * 0.08 * hs, hy + 0.012 * vs)
	c.line_to(hx + f * 0.04 * hs, hy + 0.02 * vs)
	c.move_to(cx - f * 0.12 * hs, cy - 0.03 * vs)
	c.line_to(cx - f * 0.2 * hs, cy - 0.1 * vs)
	c.move_to(cx - f * 0.12 * hs, cy)
	c.line_to(cx - f * 0.21 * hs, cy - 0.03 * vs)
	c.move_to(cx - 0.03 * hs, cy + 0.09 * vs)
	c.line_to(cx - 0.03 * hs, fy)
	c.move_to(cx + 0.04 * hs, cy + 0.09 * vs)
	c.line_to(cx + 0.04 * hs, fy)


## Sheep, deer, wolf: oval body on four legs, a head on a short neck, species ears. Lying down when resting.
static func _quad(c: Canvas, cx: float, cy: float, fy: float, hs: float, vs: float, face: float, t: float, phase: float, moving: bool, resting: bool) -> void:
	var f: float = face
	if resting:
		cy = fy - 0.1 * vs
	c.move_to(cx + 0.22 * hs, cy)
	c.ellipse(cx, cy, 0.22 * hs, 0.11 * vs, 0.0, 0.0, TWO_PI)
	var hx: float = cx + f * 0.27 * hs
	var hy: float = cy - 0.08 * vs
	c.move_to(cx + f * 0.18 * hs, cy - 0.06 * vs)
	c.line_to(hx, hy)
	c.move_to(hx + 0.06 * hs, hy)
	c.ellipse(hx, hy, 0.06 * hs, 0.045 * vs, 0.0, 0.0, TWO_PI)
	c.move_to(hx - f * 0.02 * hs, hy - 0.04 * vs)
	c.line_to(hx - f * 0.04 * hs, hy - 0.1 * vs)
	c.move_to(hx + f * 0.025 * hs, hy - 0.04 * vs)
	c.line_to(hx + f * 0.03 * hs, hy - 0.1 * vs)
	if resting:
		c.move_to(cx - 0.2 * hs, fy)
		c.line_to(cx + 0.2 * hs, fy)
		return
	var s: float = sin(t * 10.0 + phase) * 0.04 * hs if moving else 0.0
	c.move_to(cx - 0.16 * hs, cy + 0.1 * vs)
	c.line_to(cx - 0.16 * hs + s, fy)
	c.move_to(cx - 0.07 * hs, cy + 0.1 * vs)
	c.line_to(cx - 0.07 * hs - s, fy)
	c.move_to(cx + 0.09 * hs, cy + 0.1 * vs)
	c.line_to(cx + 0.09 * hs + s, fy)
	c.move_to(cx + 0.17 * hs, cy + 0.1 * vs)
	c.line_to(cx + 0.17 * hs - s, fy)
	c.move_to(cx - f * 0.22 * hs, cy - 0.04 * vs)
	c.line_to(cx - f * 0.3 * hs, cy + 0.0)
