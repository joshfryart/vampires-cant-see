class_name HudDraw
extends RefCounted
## Ports js/hud.js: the night HUD drawn as dim, hand-drawn, boiled thin lines in 640x360 internal coordinates: blood vial,
## veil meter, moon-to-sun dial, cooldown arc, powers, rocks, fear eyes, overflow track, still/mist/gift effects, title cards
## and hints. (The dawn vignette/grain and the fade are plain screen effects done by the HUD node.)

const W := 640.0
const H := 360.0
const TWO_PI := TAU
const CARD_DUR := 2.4
const CARD_IN := 0.3
const CARD_OUT := 0.5
const COL_LINE := "#cfe3ff"
const COL_BLOOD := "#d0505e"
const COL_CORAL := "#ff8a78"
const COL_BLUE := "#cfe8ff"
const LARGE_K := 1.3
const HINT_FADE := 0.4
const HINT_DUR := 4.0
const VX := 30.0
const V_RIM := 303.0
const V_IN_TOP := 305.0
const V_IN_BOT := 333.0
const DX := 606.0
const DY := 330.0
const DR := 16.0
const VEIL_X := 56.0
const VEIL_MID := 319.0
const PW_X0 := 84.0
const PW_X0_LG := 94.0
const PW_DX_LG := 30.0
const PW_Y := 318.0
const PW_DX := 24.0
const POWER_MAX := 3

## Scratch state (js create()): boil frame and the cached clock text.
var fr: int = 0
var boil: bool = false
var time_key: int = -1
var time_text: String = "20:00"

# per-draw-call module state in the JS (lg, fx, feedDim)
var lg: float = 1.0
var fx: int = 0
var feed_dim: float = 1.0


static func num(v: Variant, def: float, lo: float, hi: float) -> float:
	if not (v is float or v is int) or is_nan(float(v)) or is_inf(float(v)):
		return def
	var f := float(v)
	return lo if f < lo else (hi if f > hi else f)


static func hash2(i: float, f: float) -> float:
	var v: float = sin(i * 12.9898 + f * 78.233) * 43758.5453
	return v - floor(v)


func j(id: int, axis: int) -> float:
	if not boil:
		return 0.0
	return Ripple.jitter(fr, id, axis)


func set_frame(t: float, boil_on: bool) -> void:
	boil = boil_on
	if not boil_on:
		fr = 0
		return
	fr = Ripple.boil_frame(t)


func time_text_for(hour: int, minute: int) -> String:
	var key: int = hour * 60 + minute
	if key != time_key:
		time_key = key
		time_text = ("0" if hour < 10 else "") + str(hour) + ":" + ("0" if minute < 10 else "") + str(minute)
	return time_text


# ---------------------------------------------------------------- blood vial

func draw_vial(c: Canvas, blood: float, weak: float, t: float, reduced: bool, pulse: float) -> void:
	var sc := 0.45
	var scaled: bool = pulse > 0.0 and not reduced
	if scaled:
		var ps: float = 1.0 + 0.08 * pulse
		c.save()
		c.translate(VX, (V_RIM - 5.0 + V_IN_BOT + 2.0) / 2.0)
		c.scale(ps, ps)
		c.translate(-VX, -(V_RIM - 5.0 + V_IN_BOT + 2.0) / 2.0)
	_draw_vial_body(c, blood, weak, t, reduced, sc)
	if scaled:
		c.restore()


func _draw_vial_body(c: Canvas, blood: float, weak: float, t: float, reduced: bool, sc: float) -> void:
	var fl := 1.0
	if weak > 0.0:
		fl = 1.0 - 0.2 * weak if reduced else 1.0 - 0.25 * weak * (0.5 + 0.5 * sin(t * 12.5))
	c.line_width = 1.0
	c.stroke_style = COL_LINE
	c.global_alpha = 0.5 * fl
	c.begin_path()
	c.move_to(23.0 + j(1, 0) * sc, V_RIM + j(1, 1) * sc)
	c.line_to(23.0 + j(2, 0) * sc, 328.0 + j(2, 1) * sc)
	c.quad_to(23.0 + j(3, 0) * sc, 335.0, VX + j(3, 1) * sc, 335.0 + j(4, 1) * sc)
	c.quad_to(37.0 + j(5, 0) * sc, 335.0, 37.0 + j(5, 1) * sc, 328.0 + j(6, 1) * sc)
	c.line_to(37.0 + j(6, 0) * sc, V_RIM + j(7, 1) * sc)
	c.move_to(21.5 + j(8, 0) * sc, V_RIM + j(8, 1) * sc)
	c.line_to(38.5 + j(9, 0) * sc, V_RIM + j(9, 1) * sc)
	c.move_to(26.0 + j(10, 0) * sc, V_RIM - 0.5)
	c.line_to(26.5 + j(11, 0) * sc, 298.5 + j(11, 1) * sc)
	c.line_to(33.5 + j(12, 0) * sc, 298.5 + j(12, 1) * sc)
	c.line_to(34.0 + j(13, 0) * sc, V_RIM - 0.5)
	c.stroke()
	if fx >= 1:
		c.global_alpha = 0.25 * fl
		c.line_width = 1.0
		c.begin_path()
		c.move_to(25.0 + j(14, 0) * sc, V_RIM + 5.0)
		c.line_to(24.8 + j(15, 0) * sc, 325.0)
		c.stroke()
	if blood <= 0.005:
		return
	var level: float = V_IN_BOT - (V_IN_BOT - V_IN_TOP) * blood
	var amp: float = 0.0 if reduced else 1.5
	c.stroke_style = COL_BLOOD
	c.line_width = 1.1
	c.global_alpha = 0.55
	c.begin_path()
	for i in 6:
		var x: float = 24.5 + i * 2.2
		var y: float = level + (sin(t * 3.2 + i * 1.1) * amp if amp != 0.0 else 0.0) + j(20 + i, 1) * 0.35
		if y < V_IN_TOP:
			y = V_IN_TOP
		elif y > V_IN_BOT:
			y = V_IN_BOT
		if i == 0:
			c.move_to(x, y)
		else:
			c.line_to(x, y)
	var n: int = 3 if blood > 0.5 else 2
	for i in range(1, n + 1):
		var y2: float = level + i * 3.3
		if y2 > V_IN_BOT - 0.5:
			break
		var inset: float = (y2 - 328.0) * 0.9 if y2 > 328.0 else 0.0
		var x0: float = 24.6 + inset
		var x1: float = 35.4 - inset
		var sl: float = sin(t * 2.6 + i * 1.7) * 0.6 if amp != 0.0 else 0.0
		c.move_to(x0, y2 + j(30 + i, 1) * 0.4)
		c.line_to((x0 + x1) / 2.0, y2 + sl + j(34 + i, 1) * 0.5)
		c.line_to(x1, y2 + j(38 + i, 0) * 0.4)
	c.stroke()
	if fx >= 1 and level > V_IN_TOP + 1.0 and level < V_IN_BOT - 1.0:
		c.global_alpha = 0.4
		c.line_width = 0.9
		c.begin_path()
		c.move_to(24.2, level - 1.2)
		c.quad_to(25.8, level + 0.4, 28.0, level + 0.4)
		c.move_to(35.8, level - 1.2)
		c.quad_to(34.2, level + 0.4, 32.0, level + 0.4)
		c.stroke()


# ---------------------------------------------------------------- veil meter

static func veil_color(k: float) -> String:
	var r: int = int(JsMath.round_js(143.0 + (255.0 - 143.0) * k))
	var g: int = int(JsMath.round_js(168.0 + (210.0 - 168.0) * k))
	var b: int = int(JsMath.round_js(200.0 + (122.0 - 200.0) * k))
	return "rgb(%d,%d,%d)" % [r, g, b]


func draw_veil(c: Canvas, k: float, t: float, reduced: bool) -> void:
	var col := veil_color(k)
	var sc := 0.45
	var breathe: float = 0.85 + 0.15 * sin(t * PI) if k > 0.95 and not reduced else 1.0
	c.stroke_style = col
	c.line_width = 1.0
	c.global_alpha = 0.6 * breathe
	var open_: float = 0.0 if k < 0.1 else (2.5 if k < 0.5 else 4.5)
	var ex: float = VEIL_X
	var ey: float = VEIL_MID - 9.0
	c.begin_path()
	c.move_to(ex - 7.0 + j(20, 0) * sc, ey + j(20, 1) * sc)
	if open_ == 0.0:
		c.quad_to(ex, ey + 2.5, ex + 7.0 + j(21, 0) * sc, ey + j(21, 1) * sc)
	else:
		c.quad_to(ex, ey - open_ * 2.0, ex + 7.0 + j(21, 0) * sc, ey + j(21, 1) * sc)
		c.quad_to(ex, ey + open_ * 2.0, ex - 7.0, ey)
	c.stroke()
	if open_ > 0.0:
		c.begin_path()
		c.arc(ex, ey, 1.8 if open_ > 3.0 else 1.2, 0.0, TWO_PI)
		c.stroke()
	if open_ > 3.0:
		c.begin_path()
		for i in range(-1, 2):
			c.move_to(ex + i * 3.5, ey - open_ + 0.5)
			c.line_to(ex + i * 4.5, ey - open_ - 2.5)
		c.stroke()
	for i in 5:
		var on: float = k * 5.0 - i
		var fill: float = 1.0 if on >= 1.0 else (on if on > 0.0 else 0.0)
		c.global_alpha = (0.2 + 0.5 * fill) * breathe
		c.begin_path()
		var x: float = ex - 8.0 + i * 4.0 + j(30 + i, 0) * sc
		c.move_to(x, VEIL_MID + 5.0)
		c.line_to(x, VEIL_MID + 5.0 - 3.0 - 3.0 * fill)
		c.stroke()


# ---------------------------------------------------------------- moon -> sun dial

func draw_dial(c: Canvas, frac: float, hour: int, minute: int, _t: float) -> void:
	var sun_k: float = 0.0 if frac <= 0.9 else (1.0 if frac >= 1.0 else (frac - 0.9) / 0.1)
	c.stroke_style = COL_LINE
	c.line_width = 1.3
	c.global_alpha = feed_dim * 0.3
	c.begin_path()
	for i in 9:
		var a: float = PI + (i / 8.0) * PI
		var x: float = DX + cos(a) * DR + j(50 + i, 0) * 0.3
		var y: float = DY + sin(a) * DR + j(50 + i, 1) * 0.3
		c.move_to(x, y)
		c.line_to(x + 0.01, y)
	c.stroke()
	c.line_width = 1.0
	if fx >= 1:
		c.global_alpha = feed_dim * 0.2
		c.line_width = 0.8
		c.begin_path()
		c.arc(DX + j(82, 0) * 0.3, DY + j(82, 1) * 0.3, DR - 4.0, PI, TWO_PI, false)
		c.stroke()
		c.line_width = 1.0
	var mx: float = DX - DR - 6.0
	c.global_alpha = feed_dim * (0.45 * (1.0 - 0.5 * frac))
	c.begin_path()
	c.move_to(mx + 0.5 + j(60, 0) * 0.3, DY + 3.5)
	c.arc(mx + j(61, 0) * 0.3, DY + j(61, 1) * 0.3, 3.5, PI / 2.0, PI * 1.5, false)
	c.quad_to(mx - 1.8, DY, mx + 0.5, DY + 3.5)
	c.stroke()
	var sx: float = DX + DR + 6.0
	c.global_alpha = feed_dim * (0.3 + 0.5 * sun_k)
	c.begin_path()
	c.arc(sx + j(62, 0) * 0.3, DY + j(62, 1) * 0.3, 2.2, 0.0, TWO_PI)
	for i in 8:
		var a2: float = (i / 8.0) * TWO_PI + 0.2
		var ca: float = cos(a2)
		var sa: float = sin(a2)
		var r1 := 3.6
		var r2: float = 5.2 + j(63 + i, 0) * 0.5
		c.move_to(sx + ca * r1, DY + sa * r1)
		c.line_to(sx + ca * r2, DY + sa * r2)
	c.stroke()
	var ma: float = PI + frac * PI
	c.global_alpha = feed_dim * 0.6
	c.line_width = 2.4
	c.begin_path()
	var px: float = DX + cos(ma) * DR + j(80, 0) * 0.4
	var py: float = DY + sin(ma) * DR + j(80, 1) * 0.4
	c.move_to(px, py)
	c.line_to(px + 0.01, py)
	c.stroke()
	c.global_alpha = feed_dim * 0.7
	c.fill_style = COL_LINE
	c.font_px = 10.0 * lg
	c.text_align = "center"
	c.fill_text(time_text_for(hour, minute), DX + j(81, 0) * 0.4, DY + 13.0 + (lg - 1.0) * 4.0 + j(81, 1) * 0.4)


# ---------------------------------------------------------------- hunger extras

func draw_over(c: Canvas, o: Dictionary, t: float, reduced: bool) -> void:
	var v: float = num(o.get("over01"), 0.0, 0.0, 1.0)
	if not (v > 0.0) and o.get("overOpen") != true:
		return
	var pulse: float = 0.75 + 0.25 * sin(t * 7.0) if v > 0.8 and not reduced else 1.0
	c.stroke_style = COL_CORAL
	c.line_width = 1.2
	c.global_alpha = 0.55 * pulse
	c.begin_path()
	c.move_to(21.0 + j(90, 0) * 0.3, 293.0)
	c.line_to(39.0, 293.0 + j(91, 1) * 0.3)
	c.global_alpha = 0.25
	c.stroke()
	if v > 0.0:
		c.global_alpha = 0.6 * pulse
		c.begin_path()
		c.move_to(21.0, 293.0)
		c.line_to(21.0 + 18.0 * v, 293.0 + j(92, 1) * 0.3)
		c.stroke()


func draw_powers(c: Canvas, list: Variant, t: float, reduced: bool) -> void:
	if not (list is Array):
		return
	var slot := 0
	var i := 0
	while i < list.size() and slot < POWER_MAX:
		var p: Variant = list[i]
		i += 1
		if not (p is Dictionary):
			continue
		var st: Variant = p.get("state")
		if st != "poor" and st != "cooldown" and st != "ready":
			continue
		var x: float = PW_X0_LG + slot * PW_DX_LG if lg > 1.0 else PW_X0 + slot * PW_DX
		slot += 1
		var alpha: float = 0.25 if st == "poor" else (0.4 if st == "cooldown" else 0.8)
		c.save()
		c.translate(x, PW_Y)
		var ok := false
		if p.get("id") is String and Icons.NAMES.has(p["id"]):
			ok = Icons.draw(c, p["id"], 18.0 * lg, t, {"alpha": alpha, "color": COL_BLUE, "still": reduced, "taper": fx == 2})
		c.restore()
		c.stroke_style = COL_BLUE
		c.line_width = 1.0
		if not ok:
			c.global_alpha = alpha
			c.begin_path()
			c.arc(x, PW_Y, 7.0 * lg, 0.0, TWO_PI)
			c.stroke()
		if st == "cooldown":
			var k: float = num(p.get("cd01"), 0.0, 0.0, 1.0)
			if k > 0.0:
				c.global_alpha = 0.5
				c.begin_path()
				c.arc(x, PW_Y, 11.0 * lg, -PI / 2.0, -PI / 2.0 + TWO_PI * k)
				c.stroke()
		elif st == "ready" and fx >= 1:
			c.global_alpha = 0.2
			c.begin_path()
			c.arc(x, PW_Y, 11.0 * lg, 0.0, TWO_PI)
			c.stroke()
		if st == "ready" and p.get("key") is String and p["key"] != "":
			c.global_alpha = 0.7
			c.fill_style = COL_BLUE
			c.font_px = 8.0 * lg
			c.text_align = "center"
			c.fill_text((p["key"] as String).substr(0, 2), x, PW_Y + 15.0 * lg)


## Rocks left: three small pebbles just right of the powers row; spent ones are a faint dotted outline.
func draw_rocks(c: Canvas, n: int, max_n: int) -> void:
	var x0: float = (PW_X0_LG + POWER_MAX * PW_DX_LG if lg > 1.0 else PW_X0 + POWER_MAX * PW_DX) + 4.0
	c.stroke_style = COL_LINE
	c.line_width = 1.0
	for i in max_n:
		var x: float = x0 + i * 9.0 * lg
		var y: float = PW_Y
		c.global_alpha = 0.6 if i < n else 0.18
		c.begin_path()
		c.move_to(x - 3.0 * lg + j(60 + i, 0) * 0.3, y + 2.0 * lg)
		c.line_to(x - 2.0 * lg, y - 2.0 * lg)
		c.line_to(x + 1.0 * lg, y - 3.0 * lg + j(60 + i, 1) * 0.3)
		c.line_to(x + 3.5 * lg, y)
		c.line_to(x + 2.0 * lg, y + 3.0 * lg)
		c.line_to(x - 2.0 * lg, y + 3.0 * lg)
		c.close_path()
		c.stroke()


func draw_fear(c: Canvas, fear: float) -> void:
	var n: int = int(ceil(fear / 3.0))
	c.stroke_style = COL_BLUE
	c.line_width = 0.9
	var i := 0
	while i < n and i < 5:
		var part: float = minf(3.0, fear - i * 3.0)
		c.global_alpha = 0.55 if part >= 3.0 else 0.3
		var cx: float = (570.0 if lg > 1.0 else 582.0) + i * 12.0 * lg
		var cy := 304.0
		c.begin_path()
		c.move_to(cx - 4.0 * lg, cy + j(100 + i, 0) * 0.3)
		c.quad_to(cx, cy - 4.5 * lg, cx + 4.0 * lg, cy + j(110 + i, 1) * 0.3)
		c.quad_to(cx, cy + 4.5 * lg, cx - 4.0 * lg, cy)
		c.move_to(cx + 1.2 * lg, cy)
		c.arc(cx, cy, 1.2 * lg, 0.0, TWO_PI)
		c.stroke()
		i += 1


func draw_still(c: Canvas, k: float) -> void:
	c.stroke_style = COL_BLUE
	c.line_width = 1.5
	c.global_alpha = 0.12 * k
	var m := 4.0
	c.begin_path()
	c.move_to(m, m + j(120, 1) * 0.5)
	c.line_to(W - m, m + j(121, 1) * 0.5)
	c.line_to(W - m + j(122, 0) * 0.5, H - m)
	c.line_to(m, H - m + j(123, 1) * 0.5)
	c.line_to(m + j(124, 0) * 0.5, m)
	c.stroke()


func draw_mist(c: Canvas, k: float, t: float, reduced: bool) -> void:
	c.stroke_style = COL_BLUE
	c.line_width = 1.0
	c.global_alpha = 0.25 * k
	c.begin_path()
	for i in 4:
		var y: float = 140.0 + i * 26.0
		var x0: float = 70.0 + i * 17.0
		var x1: float = W - 70.0 - float((i * 29) % 40)
		var dr: float = 0.0 if reduced else sin(t * 0.6 + i * 1.9) * 6.0
		c.move_to(x0 + dr, y)
		c.quad_to((x0 + x1) / 2.0, y - 3.0 + j(130 + i, 1) * 0.6, x1 + dr, y + 1.0)
	c.stroke()


func draw_gift(c: Canvas, k: float, _t: float) -> void:
	c.stroke_style = COL_CORAL
	c.line_width = 1.2
	c.global_alpha = 0.6 * k
	c.begin_path()
	c.arc(VX + j(140, 0) * 0.4, 317.0 + j(140, 1) * 0.4, 22.0 + 3.0 * (1.0 - k), 0.0, TWO_PI)
	c.stroke()


func draw_hunger(c: Canvas, o: Dictionary, t: float, reduced: bool) -> void:
	if o.get("over01") != null or o.get("overOpen") == true:
		draw_over(c, o, t, reduced)
	if o.get("powers") != null:
		draw_powers(c, o["powers"], t, reduced)
	if o.get("rocks") is float or o.get("rocks") is int:
		draw_rocks(c, maxi(0, mini(9, int(floor(float(o["rocks"]))))), 3)
	var fear: float = num(o.get("fear"), 0.0, 0.0, 15.0)
	if fear > 0.0:
		draw_fear(c, fear)
	var still: float = num(o.get("still01"), 0.0, 0.0, 1.0)
	if still > 0.0:
		draw_still(c, still)
	var mist: float = num(o.get("mistK"), 0.0, 0.0, 1.0)
	if mist > 0.0:
		draw_mist(c, mist, t, reduced)
	var gift: float = num(o.get("giftFlash"), 0.0, 0.0, 1.0)
	if gift > 0.0:
		draw_gift(c, gift, t)


## Draw the whole HUD. s: {largeText, blood01, weak, frac, hour, minute, t, boil, reduced, pulse01, vialPulse, feeding, veil, fx,
## over01, overOpen, powers [{id, state, key, cd01}], rocks, fear, still01, mistK, giftFlash}.
func draw_hud(c: Canvas, s: Dictionary) -> void:
	var t: float = num(s.get("t"), 0.0, -1e9, 1e9)
	var reduced: bool = s.get("reduced") == true
	lg = LARGE_K if s.get("largeText") == true else 1.0
	var fxn: float = num(s.get("fx"), 0.0, 0.0, 2.0)
	fx = 2 if fxn >= 2.0 else (1 if fxn >= 1.0 else 0)
	var blood: float = num(s.get("blood01"), 0.0, 0.0, 1.0)
	var weak: float = num(s.get("weak"), 0.0, 0.0, 1.0)
	var frac: float = num(s.get("frac"), 0.0, 0.0, 1.0)
	var pulse01: float = num(s.get("pulse01"), 0.0, 0.0, 1.0)
	var hour: float = num(s.get("hour"), -1.0, 0.0, 23.0)
	var minute: float = num(s.get("minute"), -1.0, 0.0, 59.0)
	var hh: int
	var mm: int
	if hour < 0.0 or minute < 0.0:
		var total: int = int(JsMath.round_js(frac * 600.0))
		hh = (20 + int(floor(total / 60.0))) % 24
		mm = total % 60
	else:
		hh = int(floor(hour))
		mm = int(floor(minute))
	set_frame(t, s.get("boil") == true and not reduced)
	c.save()
	c.global_alpha = 0.3
	c.fill_style = "#ffffff"
	c.fill_rect(W / 2.0 - 1.0, H / 2.0 - 1.0, 2.0, 2.0)
	var fa: bool = s.get("feeding") == true
	var vp: float = 0.0 if reduced else num(s.get("vialPulse"), 0.0, 0.0, 1.0)
	draw_vial(c, blood, weak, t, reduced, vp)
	if s.get("veil") is float or s.get("veil") is int:
		draw_veil(c, num(s.get("veil"), 0.0, 0.0, 1.0), t, reduced)
	feed_dim = 0.5 if fa else 1.0
	draw_dial(c, frac, hh, mm, t)
	feed_dim = 1.0
	if pulse01 > 0.0:
		c.global_alpha = 0.5 * minf(1.0, pulse01 / 0.15)
		c.stroke_style = COL_LINE
		c.line_width = 0.75
		c.begin_path()
		c.arc(W / 2.0, H - 18.0, 6.0, -PI / 2.0, -PI / 2.0 + TWO_PI * pulse01)
		c.stroke()
	draw_hunger(c, s, t, reduced)
	lg = 1.0
	fx = 0
	c.global_alpha = 1.0
	c.restore()


# ---------------------------------------------------------------- title card and hint

static func draw_card_sub(c: Canvas, sub: String, a: float, k: float) -> void:
	var words: PackedStringArray = sub.substr(0, 160).split(" ")
	var lines: Array = []
	var cur := ""
	for w in words:
		var nx: String = (cur + " " + w) if cur != "" else w
		if nx.length() > 72 and cur != "":
			lines.append(cur)
			cur = w
		else:
			cur = nx
	if cur != "":
		lines.append(cur)
	c.fill_style = COL_LINE
	c.global_alpha = 0.7 * a
	c.font_px = JsMath.round_js(11.0 * k)
	c.text_align = "center"
	for i in mini(lines.size(), 2):
		c.fill_text(lines[i], W / 2.0, H / 2.0 + 14.0 * k + i * 15.0 * k)
	c.global_alpha = 1.0


## Boiled outline lettering, centred. age = seconds since the card began; nothing outside 0..CARD_DUR.
static func draw_card(c: Canvas, text: String, age_in: float, t_in: float, boil_on: bool, sub: String = "", large: bool = false) -> void:
	if text == "":
		return
	var age: float = num(age_in, -1.0, -1.0, 1e9)
	if age < 0.0 or age > CARD_DUR:
		return
	var t: float = num(t_in, 0.0, -1e9, 1e9)
	var a := 1.0
	if age < CARD_IN:
		a = age / CARD_IN
	elif age > CARD_DUR - CARD_OUT:
		a = (CARD_DUR - age) / CARD_OUT
	if not (a > 0.01):
		return
	var frame: int = int(floor(t * 10.0)) & 3 if boil_on else 0
	var str_: String = text.substr(0, 24) if text.length() > 24 else text
	var k: float = LARGE_K if large else 1.0
	var adv: float = minf(20.0 * k, 600.0 / maxf(1.0, str_.length() - 1.0))
	var x0: float = W / 2.0 - ((str_.length() - 1) * adv) / 2.0
	c.save()
	c.stroke_style = COL_LINE
	c.line_width = 1.3
	c.global_alpha = 0.85 * a
	c.text_align = "center"
	c.font_px = JsMath.round_js(28.0 * k)
	c.font_bold = true
	var jj: float = 1.0 if boil_on else 0.0
	for i in str_.length():
		var ch: String = str_[i]
		if ch == " ":
			continue
		var dx: float = (hash2(i, frame) - 0.5) * 2.0 * jj
		var dy: float = (hash2(i + 40, frame) - 0.5) * 2.0 * jj
		var rot: float = (hash2(i + 80, frame) - 0.5) * 0.1 * jj
		var base: float = sin(i * 1.7) * 2.6 + (hash2(i, 9) - 0.5) * 2.4
		c.save()
		c.translate(x0 + i * adv + dx, H / 2.0 - 20.0 + base + dy)
		c.rotate(rot + sin(i * 2.3) * 0.04)
		c.stroke_text(ch, 0.0, 0.0)
		c.restore()
	c.global_alpha = 1.0
	if sub != "":
		draw_card_sub(c, sub, a, k)
	c.restore()


## One-line hint, bottom-centre above the vial row. age = seconds since shown; fades in/out over 0.4 s. dur default 4 s.
static func draw_hint(c: Canvas, text: String, age_in: float, dur_in: float = HINT_DUR, large: bool = false) -> void:
	if text == "":
		return
	var dur: float = num(dur_in, HINT_DUR, 2.0 * HINT_FADE, 60.0)
	var age: float = num(age_in, -1.0, -1.0, 1e9)
	if age < 0.0 or age > dur:
		return
	var a := 1.0
	if age < HINT_FADE:
		a = age / HINT_FADE
	elif age > dur - HINT_FADE:
		a = (dur - age) / HINT_FADE
	if not (a > 0.01):
		return
	var k: float = LARGE_K if large else 1.0
	var px: float = JsMath.round_js(10.0 * k)
	var str_: String = text.substr(0, 90) if text.length() > 90 else text
	c.save()
	c.font_px = px
	c.text_align = "center"
	var w: float = str_.length() * px * 0.6
	var m: float = c.measure_text(str_)
	if m > 0.0:
		w = m
	w = minf(w, W - 40.0)
	var cy: float = 282.0 - (k - 1.0) * 10.0
	var ph: float = px + 10.0
	c.global_alpha = 0.6 * a
	c.fill_style = "#04070e"
	c.fill_rect(W / 2.0 - w / 2.0 - 8.0, cy - ph / 2.0, w + 16.0, ph)
	c.global_alpha = 0.8 * a
	c.fill_style = COL_LINE
	c.fill_text(str_, W / 2.0, cy, W - 40.0)
	c.global_alpha = 1.0
	c.restore()
