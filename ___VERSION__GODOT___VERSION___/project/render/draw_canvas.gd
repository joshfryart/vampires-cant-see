class_name DrawCanvas
extends Canvas
## Canvas implementation that tessellates strokes into polylines (clipped to the active clip rect) so a CanvasItem
## can draw them with draw_polyline. Collect during a frame, then call paint(item) from the item's _draw().
## Only strokes exist in the line-figure drawing, so clipping polylines to a rectangle is exact.

const CURVE_STEPS := 10

class Stroke:
	extends RefCounted
	var points: PackedVector2Array
	var color: Color
	var width: float

var strokes: Array[Stroke] = []
var fills: Array = []          # [Rect2, Color] filled dots

var _path: Array = []          # subpaths: Array of PackedVector2Array
var _cur: PackedVector2Array = PackedVector2Array()
var _path_rects: Array = []    # rect() calls since begin_path
var _clip: Rect2 = Rect2()
var _clip_on: bool = false
var _stack: Array = []
var _xf: Transform2D = Transform2D.IDENTITY
var texts: Array = []          # text items: {text, xf, color, size, bold, align, outline, max_w}
var text_baseline_middle: bool = true


func reset() -> void:
	strokes.clear()
	fills.clear()
	_path.clear()
	_cur = PackedVector2Array()
	_path_rects.clear()
	_clip_on = false
	_stack.clear()
	_xf = Transform2D.IDENTITY
	texts.clear()
	global_alpha = 1.0
	stroke_style = "#000"
	fill_style = "#000"
	line_width = 1.0
	font_px = 10.0
	font_bold = false
	text_align = "left"


## save/restore unwind the clip, the transform and the drawing state, like a real canvas.
func save() -> void:
	_stack.append([_clip, _clip_on, _xf, global_alpha, stroke_style, fill_style, line_width, font_px, font_bold, text_align])


func restore() -> void:
	if _stack.is_empty():
		return
	var s: Array = _stack.pop_back()
	_clip = s[0]
	_clip_on = s[1]
	_xf = s[2]
	global_alpha = s[3]
	stroke_style = s[4]
	fill_style = s[5]
	line_width = s[6]
	font_px = s[7]
	font_bold = s[8]
	text_align = s[9]


func set_transform(a: float, b: float, c: float, d: float, e: float, f: float) -> void:
	_xf = Transform2D(Vector2(a, b), Vector2(c, d), Vector2(e, f))


func translate(x: float, y: float) -> void:
	_xf = _xf * Transform2D(0.0, Vector2(x, y))


func scale(x: float, y: float) -> void:
	_xf = _xf * Transform2D(Vector2(x, 0.0), Vector2(0.0, y), Vector2.ZERO)


func rotate(a: float) -> void:
	_xf = _xf * Transform2D(a, Vector2.ZERO)


func fill_rect(x: float, y: float, w: float, h: float) -> void:
	var col := _fill_color()
	if col.a <= 0.0:
		return
	var r := _xf * Rect2(x, y, w, h)
	if _clip_on:
		r = r.intersection(_clip)
		if r.size.x <= 0.0 or r.size.y <= 0.0:
			return
	fills.append([r, col])


func _text_item(text: String, x: float, y: float, outline: bool, max_w: float) -> void:
	texts.append({"text": text, "xf": _xf * Transform2D(0.0, Vector2(x, y)), "color": _fill_color() if not outline else _color(), "size": font_px, "bold": font_bold, "align": text_align, "outline": outline, "max_w": max_w, "width": line_width})


func fill_text(text: String, x: float, y: float, max_w: float = -1.0) -> void:
	_text_item(text, x, y, false, max_w)


func stroke_text(text: String, x: float, y: float) -> void:
	_text_item(text, x, y, true, -1.0)


func measure_text(_text: String) -> float:
	return -1.0


func begin_path() -> void:
	_path.clear()
	_cur = PackedVector2Array()
	_path_rects.clear()


func _flush_cur() -> void:
	if _cur.size() > 0:
		_path.append(_cur)
	_cur = PackedVector2Array()


func close_path() -> void:
	if _cur.size() > 1:
		_cur.append(_cur[0])
	_flush_cur()


func move_to(x: float, y: float) -> void:
	_flush_cur()
	_cur.append(_xf * Vector2(x, y))


func line_to(x: float, y: float) -> void:
	_cur.append(_xf * Vector2(x, y))


func quad_to(cx: float, cy: float, x: float, y: float) -> void:
	if _cur.is_empty():
		_cur.append(_xf * Vector2(cx, cy))
	var p0: Vector2 = _cur[_cur.size() - 1]
	var p1: Vector2 = _xf * Vector2(cx, cy)
	var p2: Vector2 = _xf * Vector2(x, y)
	for i in range(1, CURVE_STEPS + 1):
		var t: float = float(i) / CURVE_STEPS
		var mt: float = 1.0 - t
		_cur.append(p0 * (mt * mt) + p1 * (2.0 * mt * t) + p2 * (t * t))


func rect(x: float, y: float, w: float, h: float) -> void:
	_path_rects.append(_xf * Rect2(x, y, w, h))


func clip() -> void:
	for r in _path_rects:
		_clip = _clip.intersection(r) if _clip_on else r
		_clip_on = true


func ellipse(x: float, y: float, rx: float, ry: float, rot: float, a0: float, a1: float, ccw_v: Variant = null) -> void:
	var ccw: bool = ccw_v == true
	var sweep: float = a1 - a0
	if not ccw:
		if sweep >= TAU:
			sweep = TAU
		elif sweep < 0.0:
			sweep = fposmod(sweep, TAU)
	else:
		if sweep <= -TAU:
			sweep = -TAU
		elif sweep > 0.0:
			sweep = -fposmod(-sweep, TAU)
	var n: int = maxi(8, int(ceil(absf(sweep) / TAU * clampf((rx + ry) * 0.9, 12.0, 48.0))))
	var cr: float = cos(rot)
	var sr: float = sin(rot)
	for i in n + 1:
		var a: float = a0 + sweep * float(i) / n
		var px: float = cos(a) * rx
		var py: float = sin(a) * ry
		var pt: Vector2 = _xf * Vector2(x + px * cr - py * sr, y + px * sr + py * cr)
		if i == 0 and _cur.size() > 0 and pt.distance_to(_cur[_cur.size() - 1]) > 1e-6:
			_cur.append(pt)  # implicit line to the arc start, as the canvas does
		elif i == 0 and _cur.is_empty():
			_cur.append(pt)
		else:
			_cur.append(pt)


func arc(x: float, y: float, r: float, a0: float, a1: float, ccw: Variant = null) -> void:
	ellipse(x, y, r, r, 0.0, a0, a1, ccw)


func _color() -> Color:
	return _parse_color(stroke_style)


func _fill_color() -> Color:
	return _parse_color(fill_style)


func _parse_color(s: String) -> Color:
	var c := Color.BLACK
	if s.begins_with("#"):
		c = Color.html(s)
	elif s.begins_with("rgb("):
		var parts := s.substr(4, s.length() - 5).split(",")
		if parts.size() >= 3:
			c = Color(float(parts[0]) / 255.0, float(parts[1]) / 255.0, float(parts[2]) / 255.0)
	c.a = clampf(global_alpha, 0.0, 1.0)
	return c


## Liang-Barsky: clip segment a-b to r; returns [] when fully outside, else [a', b'].
static func _clip_segment(a: Vector2, b: Vector2, r: Rect2) -> Array:
	var t0 := 0.0
	var t1 := 1.0
	var dx: float = b.x - a.x
	var dy: float = b.y - a.y
	var p := [-dx, dx, -dy, dy]
	var q := [a.x - r.position.x, r.position.x + r.size.x - a.x, a.y - r.position.y, r.position.y + r.size.y - a.y]
	for i in 4:
		if p[i] == 0.0:
			if q[i] < 0.0:
				return []
		else:
			var t: float = q[i] / p[i]
			if p[i] < 0.0:
				if t > t1:
					return []
				t0 = maxf(t0, t)
			else:
				if t < t0:
					return []
				t1 = minf(t1, t)
	return [a + Vector2(dx, dy) * t0, a + Vector2(dx, dy) * t1]


func stroke() -> void:
	_flush_cur()
	var col := _color()
	if col.a <= 0.0:
		return
	for sub in _path:
		if sub.size() < 2:
			continue
		if not _clip_on:
			_emit(sub, col)
			continue
		var run := PackedVector2Array()
		for i in range(sub.size() - 1):
			var seg := _clip_segment(sub[i], sub[i + 1], _clip)
			if seg.is_empty():
				if run.size() > 1:
					_emit(run, col)
				run = PackedVector2Array()
				continue
			if run.is_empty():
				run.append(seg[0])
			elif run[run.size() - 1].distance_to(seg[0]) > 1e-4:
				_emit(run, col)
				run = PackedVector2Array([seg[0]])
			run.append(seg[1])
		if run.size() > 1:
			_emit(run, col)
	# the canvas keeps the path after stroke(); callers always begin_path() again


func _emit(points: PackedVector2Array, col: Color) -> void:
	var s := Stroke.new()
	s.points = points
	s.color = col
	s.width = line_width
	strokes.append(s)


## Fill the rect() subpaths (dots), clipped to the active clip rect.
func fill() -> void:
	var col := _fill_color()
	if col.a <= 0.0:
		return
	for r in _path_rects:
		var rr: Rect2 = r
		if _clip_on:
			rr = rr.intersection(_clip)
			if rr.size.x <= 0.0 or rr.size.y <= 0.0:
				continue
		fills.append([rr, col])


## Draw everything collected so far onto a CanvasItem (call from its _draw()).
func paint(item: CanvasItem) -> void:
	for f in fills:
		item.draw_rect(f[0], f[1], true)
	for s in strokes:
		item.draw_polyline(s.points, s.color, maxf(1.0, s.width), true)
	if not texts.is_empty():
		var font: Font = _font()
		for t in texts:
			var xf: Transform2D = t["xf"]
			item.draw_set_transform_matrix(xf)
			var size: int = maxi(1, int(round(t["size"])))
			var dy: float = (font.get_ascent(size) - font.get_descent(size)) * 0.5
			var al := HORIZONTAL_ALIGNMENT_LEFT
			var w := -1.0
			if t["align"] == "center":
				al = HORIZONTAL_ALIGNMENT_CENTER
				w = 600.0
			elif t["align"] == "right":
				al = HORIZONTAL_ALIGNMENT_RIGHT
				w = 600.0
			var ox: float = -w * 0.5 if t["align"] == "center" else (-w if t["align"] == "right" else 0.0)
			if t["outline"]:
				item.draw_string_outline(font, Vector2(ox, dy), t["text"], al, w, size, maxi(1, int(round(t["width"]))), t["color"])
			else:
				item.draw_string(font, Vector2(ox, dy), t["text"], al, w if t["max_w"] < 0.0 else t["max_w"], size, t["color"])
		item.draw_set_transform_matrix(Transform2D.IDENTITY)


static var _mono: Font = null


static func _font() -> Font:
	if _mono == null:
		var f := SystemFont.new()
		f.font_names = PackedStringArray(["ui-monospace", "Menlo", "Consolas", "Courier New", "monospace"])
		_mono = f
	return _mono
