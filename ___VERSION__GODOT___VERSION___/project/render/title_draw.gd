class_name TitleDraw
extends RefCounted
## Ports drawTitle / drawTitleText from js/game.js: the crypt backdrop (render/icons.gd) with the quirky title on an uneven
## baseline, boiling at 10 fps, and the flapping bat squiggle.


## Stable pseudo-random 0..1 from an integer pair (for line boil).
static func hash2(i: float, f: float) -> float:
	var v: float = sin(i * 12.9898 + f * 78.233) * 43758.5453
	return v - floorf(v)


## Title backdrop and text. t = title time (0 with reduced motion), menu_up = the menu panel is showing (title lifts).
static func draw(c: Canvas, w: float, h: float, t: float, reduced: bool, line_boil: bool, menu_up: bool) -> void:
	c.global_alpha = 1.0
	var tt: float = 3.3 if reduced else t
	if Icons.draw_crypt_menu(c, w, h, tt):
		c.global_alpha = 1.0
		draw_text(c, w, h, 0.0 if reduced else t, -92.0 if menu_up else -92.0, reduced, line_boil)
		return
	c.fill_style = "#000"
	c.fill_rect(0, 0, w, h)
	draw_text(c, w, h, 0.0 if reduced else t, 0.0, reduced, line_boil)


static func draw_text(c: Canvas, w: float, h: float, t: float, y_off: float, reduced: bool, line_boil: bool) -> void:
	var boil: bool = not reduced and line_boil
	var frame: int = (int(floor(t * 10.0)) % 4) if boil else 0
	var text := "VAMPIRES CAN'T SEE"
	c.save()
	c.stroke_style = "#cfe3ff"
	c.fill_style = "rgba(207, 227, 255, 0.12)"
	c.line_width = 1.4
	c.font_px = 30.0
	c.font_bold = true
	c.text_align = "center"
	var adv := 27.0
	var x0: float = w / 2.0 - ((text.length() - 1) * adv) / 2.0
	for i in text.length():
		var ch: String = text[i]
		if ch == " ":
			continue
		var j: float = 1.1 if boil else 0.0
		var dx: float = (hash2(i, frame) - 0.5) * 2.0 * j
		var dy: float = (hash2(i + 40, frame) - 0.5) * 2.0 * j
		var rot: float = (hash2(i + 80, frame) - 0.5) * 0.1 * (1.0 if boil else 0.0)
		var base: float = sin(i * 1.7) * 3.2 + (hash2(i, 9) - 0.5) * 3.0
		c.save()
		c.translate(x0 + i * adv + dx, h / 2.0 + y_off + base + dy)
		c.rotate(rot + sin(i * 2.3) * 0.05)
		c.fill_text(ch, 0, 0)
		c.stroke_text(ch, 0, 0)
		c.restore()
	# bat squiggle: two scalloped wings and a tiny body
	var flap: float = sin(t * 4.0) * 5.0 if (boil or not reduced) else 0.0
	var bx: float = w / 2.0
	var by: float = h / 2.0 + y_off - 48.0
	var jit := func(k: float) -> float: return (hash2(k, frame + 17) - 0.5) * 1.6 if boil else 0.0
	c.line_width = 1.2
	c.global_alpha = 0.9
	c.begin_path()
	for side in [-1.0, 1.0]:
		c.move_to(bx + side * 3.0, by)
		c.quad_to(bx + side * 12.0, by - 12.0 - flap + jit.call(1.0), bx + side * 26.0 + jit.call(2.0), by - 6.0 - flap * 1.4)
		c.quad_to(bx + side * 22.0, by + 1.0 + jit.call(3.0), bx + side * 19.0, by + 3.0 - flap * 0.4)
		c.quad_to(bx + side * 14.0, by - 1.0 + jit.call(4.0), bx + side * 10.0, by + 4.0)
		c.quad_to(bx + side * 6.0, by + 1.0, bx + side * 3.0, by + 6.0)
	c.stroke()
	c.begin_path()
	c.ellipse(bx, by + 1.0 + jit.call(5.0), 3.0, 5.0, 0.0, 0.0, TAU)
	c.move_to(bx - 2.5, by - 4.0)
	c.line_to(bx - 3.5, by - 8.0)
	c.move_to(bx + 2.5, by - 4.0)
	c.line_to(bx + 3.5, by - 8.0)
	c.stroke()
	c.restore()
	c.global_alpha = 1.0
