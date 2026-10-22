class_name DrawCanvas
extends Canvas
## Canvas implementation that tessellates strokes into polylines (clipped to the active clip rect) so a CanvasItem
## can draw them with draw_polyline. Collect during a frame, then call paint(item) from the item's _draw().
## Only strokes exist in the line-figure drawing, so clipping polylines to a rectangle is exact.

const CURVE_STEPS := 10
const CURVE_TOL := 0.15   # max deviation (px) of the flattened quadratic from the true curve

class Stroke:
	extends RefCounted
	var points: PackedVector2Array
	var color: Color
	var width: float
	var bb: Rect2 = Rect2()   # bounds, only filled for recorded strokes (rec_mode)

## Everything drawn this frame in call order, so later fills hide earlier lines the way a canvas does:
## ["s", Stroke] | ["r", Rect2, Color] | ["p", PackedVector2Array, Color] | ["t", text item].
var ops: Array = []

var _path: Array = []          # subpaths: Array of PackedVector2Array
var _cur: PackedVector2Array = PackedVector2Array()
var _path_rects: Array = []    # rect() calls since begin_path
var _clip: Rect2 = Rect2()
var _clip_on: bool = false
var _stack: Array = []
var _xf: Transform2D = Transform2D.IDENTITY
var text_baseline_middle: bool = true
## Recording mode (EchoLayer swept figures): ops keep an alpha marker (>= 2.0 means "linear in the strip alpha") and bounds, so
## replay_rec can redraw the same figure per height strip without rebuilding its geometry.
var rec_mode: bool = false
var _box: PackedVector2Array = PackedVector2Array()
var _q0: Vector2 = Vector2.ZERO
var _q1: Vector2 = Vector2.ZERO


func reset() -> void:
	ops.clear()
	_path.clear()
	_cur = PackedVector2Array()
	_path_rects.clear()
	_clip_on = false
	_stack.clear()
	_xf = Transform2D.IDENTITY
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
	ops.append(["r", r, col])


func _text_item(text: String, x: float, y: float, outline: bool, max_w: float) -> void:
	ops.append(["t", {"text": text, "xf": _xf * Transform2D(0.0, Vector2(x, y)), "color": _fill_color() if not outline else _color(), "size": font_px, "bold": font_bold, "align": text_align, "outline": outline, "max_w": max_w, "width": line_width}])


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
	# Adaptive flattening: the deviation of N chords from the curve is |p0 - 2 p1 + p2| / 4 / N^2, kept under CURVE_TOL px.
	var dev: float = (p0 - p1 * 2.0 + p2).length() * 0.25
	var steps: int = clampi(int(ceil(sqrt(dev / CURVE_TOL))), 2, CURVE_STEPS)
	var base: int = _cur.size()
	_cur.resize(base + steps)
	var inv: float = 1.0 / steps
	for i in range(1, steps + 1):
		var t: float = i * inv
		var mt: float = 1.0 - t
		_cur[base + i - 1] = p0 * (mt * mt) + p1 * (2.0 * mt * t) + p2 * (t * t)


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


func style_color(s: String) -> Color:
	return _parse_color(s)


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
	if rec_mode and global_alpha >= 2.0:
		c.a = global_alpha
	else:
		c.a = clampf(global_alpha, 0.0, 1.0)
	return c


## Liang-Barsky: clip segment a-b to the rect x0..x1, y0..y1; false when fully outside, else the ends are in _q0/_q1.
func _lb(a: Vector2, b: Vector2, x0: float, y0: float, x1: float, y1: float) -> bool:
	var t0 := 0.0
	var t1 := 1.0
	var dx: float = b.x - a.x
	var dy: float = b.y - a.y
	if dx == 0.0:
		if a.x < x0 or x1 < a.x:
			return false
	else:
		var tl: float = (x0 - a.x) / dx
		var tr: float = (x1 - a.x) / dx
		if dx > 0.0:
			t0 = maxf(t0, tl)
			t1 = minf(t1, tr)
		else:
			t0 = maxf(t0, tr)
			t1 = minf(t1, tl)
		if t0 > t1:
			return false
	if dy == 0.0:
		if a.y < y0 or y1 < a.y:
			return false
	else:
		var tt: float = (y0 - a.y) / dy
		var tb: float = (y1 - a.y) / dy
		if dy > 0.0:
			t0 = maxf(t0, tt)
			t1 = minf(t1, tb)
		else:
			t0 = maxf(t0, tb)
			t1 = minf(t1, tt)
		if t0 > t1:
			return false
	_q0 = a + Vector2(dx, dy) * t0
	_q1 = a + Vector2(dx, dy) * t1
	return true


## Emit the parts of polyline pts inside rect r as strokes (runs of connected clipped segments).
func _clip_stroke(pts: PackedVector2Array, col: Color, width: float, r: Rect2) -> void:
	var x0: float = r.position.x
	var y0: float = r.position.y
	var x1: float = r.end.x
	var y1: float = r.end.y
	var run := PackedVector2Array()
	var last := Vector2.ZERO
	var a: Vector2 = pts[0]
	var ina: bool = a.x >= x0 and a.x <= x1 and a.y >= y0 and a.y <= y1
	for i in range(1, pts.size()):
		var b: Vector2 = pts[i]
		var p0: Vector2 = a
		var p1: Vector2 = b
		var inb: bool = b.x >= x0 and b.x <= x1 and b.y >= y0 and b.y <= y1
		var ok := true
		if not (ina and inb):
			if (a.x < x0 and b.x < x0) or (a.x > x1 and b.x > x1) or (a.y < y0 and b.y < y0) or (a.y > y1 and b.y > y1):
				ok = false
			else:
				ok = _lb(a, b, x0, y0, x1, y1)
				p0 = _q0
				p1 = _q1
		a = b
		ina = inb
		if not ok:
			if not run.is_empty():
				if run.size() > 1:
					_emit_w(run, col, width)
				run = PackedVector2Array()
			continue
		if run.is_empty():
			run.append(p0)
		elif last.distance_to(p0) > 1e-4:
			if run.size() > 1:
				_emit_w(run, col, width)
			run = PackedVector2Array([p0])
		run.append(p1)
		last = p1
	if run.size() > 1:
		_emit_w(run, col, width)


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
		else:
			_clip_stroke(sub, col, line_width, _clip)
	# the canvas keeps the path after stroke(); callers always begin_path() again


func _emit(points: PackedVector2Array, col: Color) -> void:
	_emit_w(points, col, line_width)


func _emit_w(points: PackedVector2Array, col: Color, width: float) -> void:
	var s := Stroke.new()
	s.points = points
	s.color = col
	s.width = width
	if rec_mode:
		s.bb = _bounds(points)
	ops.append(["s", s])


static func _bounds(pts: PackedVector2Array) -> Rect2:
	var x0: float = pts[0].x
	var y0: float = pts[0].y
	var x1 := x0
	var y1 := y0
	for i in range(1, pts.size()):
		var p: Vector2 = pts[i]
		if p.x < x0:
			x0 = p.x
		elif p.x > x1:
			x1 = p.x
		if p.y < y0:
			y0 = p.y
		elif p.y > y1:
			y1 = p.y
	return Rect2(x0, y0, x1 - x0, y1 - y0)


## Fill the current path: rect() subpaths (dots) and every moveTo/lineTo/arc subpath as a closed polygon (nonzero winding is
## approximated by merging self-overlaps), clipped to the active clip rect.
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
		ops.append(["r", rr, col])
	_flush_cur()
	for sub in _path:
		var pts: PackedVector2Array = sub
		if pts.size() > 1 and pts[0].distance_to(pts[pts.size() - 1]) < 1e-6:
			pts = pts.slice(0, pts.size() - 1)
		if pts.size() < 3:
			continue
		var polys: Array = [pts]
		if _clip_on:
			var bb: Rect2 = _bounds(pts)
			if bb.end.x < _clip.position.x or bb.position.x > _clip.end.x or bb.end.y < _clip.position.y or bb.position.y > _clip.end.y:
				continue
			if not (bb.position.x >= _clip.position.x and bb.end.x <= _clip.end.x and bb.position.y >= _clip.position.y and bb.end.y <= _clip.end.y):
				var box := PackedVector2Array([_clip.position, Vector2(_clip.end.x, _clip.position.y), _clip.end, Vector2(_clip.position.x, _clip.end.y)])
				polys = Geometry2D.intersect_polygons(pts, box)
		for pl in polys:
			_add_poly(pl, col)


func _add_poly(pts: PackedVector2Array, col: Color) -> void:
	if pts.size() < 3:
		return
	var idx: PackedInt32Array = Geometry2D.triangulate_polygon(pts)
	if not idx.is_empty():
		_push_poly(pts, col, idx)
		return
	# self-overlapping outline: merge it with nothing to get simple pieces
	for q in Geometry2D.merge_polygons(pts, PackedVector2Array()):
		if not Geometry2D.is_polygon_clockwise(q):
			var qi: PackedInt32Array = Geometry2D.triangulate_polygon(q)
			if qi.size() > 0:
				_push_poly(q, col, qi)


## A fill op: ["p", points, colour, triangle indices (triangulated once, here) {, bounds when recording}].
func _push_poly(pts: PackedVector2Array, col: Color, idx: PackedInt32Array) -> void:
	if rec_mode:
		ops.append(["p", pts, col, idx, _bounds(pts)])
	else:
		ops.append(["p", pts, col, idx])


static func _scale_a(a: float, k: float) -> float:
	if a >= 2.0:
		return (a - 2.0) * k
	return minf(a, a * k)


## Replay a recorded figure (rec.ops, built with rec_mode at strip alpha sa_ref, stroke colour sentinel) clipped to rect clip_r, at
## strip alpha sa and stroke colour style (the strokes drawn in the sentinel colour). Every alpha is min(cap, k * sa) (marker ops
## are purely linear), so scaling by sa / sa_ref reproduces a fresh draw at sa.
func replay_rec(rec: DrawCanvas, clip_r: Rect2, sa: float, sa_ref: float, sentinel: Color, style: Color) -> void:
	var k: float = sa / sa_ref
	var cx0: float = clip_r.position.x
	var cy0: float = clip_r.position.y
	var cx1: float = clip_r.end.x
	var cy1: float = clip_r.end.y
	for op in rec.ops:
		match op[0]:
			"s":
				var st: Stroke = op[1]
				var bb: Rect2 = st.bb
				if bb.end.x < cx0 or bb.position.x > cx1 or bb.end.y < cy0 or bb.position.y > cy1:
					continue
				var col: Color = st.color
				var a: float = _scale_a(col.a, k)
				if a <= 0.0:
					continue
				if absf(col.r - sentinel.r) < 0.002 and absf(col.g - sentinel.g) < 0.002 and absf(col.b - sentinel.b) < 0.002:
					col = style
				col.a = a
				if bb.position.x >= cx0 and bb.end.x <= cx1 and bb.position.y >= cy0 and bb.end.y <= cy1:
					var s2 := Stroke.new()
					s2.points = st.points
					s2.color = col
					s2.width = st.width
					ops.append(["s", s2])
				else:
					if _box.size() == 0:
						_box.resize(4)
					_box[0] = clip_r.position
					_box[1] = Vector2(cx1, cy0)
					_box[2] = clip_r.end
					_box[3] = Vector2(cx0, cy1)
					for piece in Geometry2D.intersect_polyline_with_polygon(st.points, _box):
						if piece.size() > 1:
							_emit_w(piece, col, st.width)
			"r":
				var col2: Color = op[2]
				col2.a = _scale_a(col2.a, k)
				var rr: Rect2 = (op[1] as Rect2).intersection(clip_r)
				if col2.a <= 0.0 or rr.size.x <= 0.0 or rr.size.y <= 0.0:
					continue
				ops.append(["r", rr, col2])
			"p":
				var bp: Rect2 = op[4]
				if bp.end.x < cx0 or bp.position.x > cx1 or bp.end.y < cy0 or bp.position.y > cy1:
					continue
				var col3: Color = op[2]
				col3.a = _scale_a(col3.a, k)
				if col3.a <= 0.0:
					continue
				if bp.position.x >= cx0 and bp.end.x <= cx1 and bp.position.y >= cy0 and bp.end.y <= cy1:
					ops.append(["p", op[1], col3, op[3]])
				else:
					var box := PackedVector2Array([clip_r.position, Vector2(cx1, cy0), clip_r.end, Vector2(cx0, cy1)])
					for pl in Geometry2D.intersect_polygons(op[1], box):
						_add_poly(pl, col3)


## Draw everything collected so far onto a CanvasItem (call from its _draw()).
func paint(item: CanvasItem) -> void:
	for op in ops:
		match op[0]:
			"r":
				item.draw_rect(op[1], op[2], true)
			"p":
				item.draw_colored_polygon(op[1], op[2])
			"s":
				var st: Stroke = op[1]
				item.draw_polyline(st.points, st.color, maxf(1.0, st.width), true)
			"t":
				_paint_text(item, op[1])


func _paint_text(item: CanvasItem, t: Dictionary) -> void:
	var font: Font = _font()
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
