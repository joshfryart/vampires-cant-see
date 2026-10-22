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

var _path: Array = []          # subpaths: Array of PackedVector2Array
var _cur: PackedVector2Array = PackedVector2Array()
var _path_rects: Array = []    # rect() calls since begin_path
var _clip: Rect2 = Rect2()
var _clip_on: bool = false
var _stack: Array = []


func reset() -> void:
	strokes.clear()
	_path.clear()
	_cur = PackedVector2Array()
	_path_rects.clear()
	_clip_on = false
	_stack.clear()
	global_alpha = 1.0
	stroke_style = "#000"
	line_width = 1.0


func save() -> void:
	_stack.append([_clip, _clip_on])


func restore() -> void:
	if _stack.is_empty():
		return
	var s: Array = _stack.pop_back()
	_clip = s[0]
	_clip_on = s[1]


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
	_cur.append(Vector2(x, y))


func line_to(x: float, y: float) -> void:
	if _cur.is_empty():
		_cur.append(Vector2(x, y))
	else:
		_cur.append(Vector2(x, y))


func quad_to(cx: float, cy: float, x: float, y: float) -> void:
	if _cur.is_empty():
		_cur.append(Vector2(cx, cy))
	var p0: Vector2 = _cur[_cur.size() - 1]
	var p1 := Vector2(cx, cy)
	var p2 := Vector2(x, y)
	for i in range(1, CURVE_STEPS + 1):
		var t: float = float(i) / CURVE_STEPS
		var mt: float = 1.0 - t
		_cur.append(p0 * (mt * mt) + p1 * (2.0 * mt * t) + p2 * (t * t))


func rect(x: float, y: float, w: float, h: float) -> void:
	_path_rects.append(Rect2(x, y, w, h))


func clip() -> void:
	for r in _path_rects:
		_clip = _clip.intersection(r) if _clip_on else r
		_clip_on = true


func ellipse(x: float, y: float, rx: float, ry: float, rot: float, a0: float, a1: float, ccw: bool = false) -> void:
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
		var pt := Vector2(x + px * cr - py * sr, y + px * sr + py * cr)
		if i == 0 and _cur.size() > 0 and pt.distance_to(_cur[_cur.size() - 1]) > 1e-6:
			_cur.append(pt)  # implicit line to the arc start, as the canvas does
		elif i == 0 and _cur.is_empty():
			_cur.append(pt)
		else:
			_cur.append(pt)


func arc(x: float, y: float, r: float, a0: float, a1: float, ccw: bool = false) -> void:
	ellipse(x, y, r, r, 0.0, a0, a1, ccw)


func _color() -> Color:
	var s := stroke_style
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


## Draw everything collected so far onto a CanvasItem (call from its _draw()).
func paint(item: CanvasItem) -> void:
	for s in strokes:
		item.draw_polyline(s.points, s.color, maxf(1.0, s.width), true)
