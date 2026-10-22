class_name RecordingCanvas
extends Canvas
## Logs every call with the stroke style, alpha and line width in force, like the JS fake context in
## tools/figure-golden.mjs. canon_line / log_hash reproduce that tool's canonical text and FNV-1a hash.

## Each entry: {fn: String, args: Array, stroke: String, alpha: float, lw: float}
var calls: Array = []


func _log(fn: String, args: Array) -> void:
	calls.append({"fn": fn, "args": args, "stroke": stroke_style, "alpha": global_alpha, "lw": line_width})


func set_transform(a: float, b: float, c: float, d: float, e: float, f: float) -> void:
	_log("setTransform", [a, b, c, d, e, f])


func save() -> void:
	_log("save", [])


func restore() -> void:
	_log("restore", [])


func begin_path() -> void:
	_log("beginPath", [])


func close_path() -> void:
	_log("closePath", [])


func move_to(x: float, y: float) -> void:
	_log("moveTo", [x, y])


func line_to(x: float, y: float) -> void:
	_log("lineTo", [x, y])


func quad_to(cx: float, cy: float, x: float, y: float) -> void:
	_log("quadraticCurveTo", [cx, cy, x, y])


func rect(x: float, y: float, w: float, h: float) -> void:
	_log("rect", [x, y, w, h])


func clip() -> void:
	_log("clip", [])


func arc(x: float, y: float, r: float, a0: float, a1: float, ccw: Variant = null) -> void:
	# JS logs the anticlockwise argument only when it was passed (true or false)
	if ccw != null:
		_log("arc", [x, y, r, a0, a1, bool(ccw)])
	else:
		_log("arc", [x, y, r, a0, a1])


func ellipse(x: float, y: float, rx: float, ry: float, rot: float, a0: float, a1: float, ccw: Variant = null) -> void:
	if ccw != null:
		_log("ellipse", [x, y, rx, ry, rot, a0, a1, bool(ccw)])
	else:
		_log("ellipse", [x, y, rx, ry, rot, a0, a1])


func stroke() -> void:
	_log("stroke", [])


func fill() -> void:
	_log("fill", [])


func translate(x: float, y: float) -> void:
	_log("translate", [x, y])


func scale(x: float, y: float) -> void:
	_log("scale", [x, y])


func rotate(a: float) -> void:
	_log("rotate", [a])


func fill_rect(x: float, y: float, w: float, h: float) -> void:
	_log("fillRect", [x, y, w, h])


func fill_text(text: String, x: float, y: float, max_w: float = -1.0) -> void:
	if max_w >= 0.0:
		_log("fillText", [text, x, y, max_w])
	else:
		_log("fillText", [text, x, y])


func stroke_text(text: String, x: float, y: float) -> void:
	_log("strokeText", [text, x, y])


func measure_text(text: String) -> float:
	_log("measureText", [text])
	return -1.0


# ---- canonical text and hash (tools/golden/figure.mjs) ----

## JS String(Math.round(x * 1000) / 1000) for finite x: integer thousandths with trailing zeros trimmed.
static func canon_num(x: float) -> String:
	if is_nan(x):
		return "NaN"
	if is_inf(x):
		return "Infinity" if x > 0.0 else "-Infinity"
	var n: int = int(floor(x * 1000.0 + 0.5))
	if n == 0:
		return "0"
	var neg := n < 0
	var a: int = absi(n)
	var whole: int = a / 1000
	var frac: int = a % 1000
	var s := str(whole)
	if frac != 0:
		var f := "%03d" % frac
		while f.ends_with("0"):
			f = f.substr(0, f.length() - 1)
		s += "." + f
	return ("-" if neg else "") + s


static func canon_value(v: Variant) -> String:
	if v is bool:
		return "true" if v else "false"
	if v is float or v is int:
		return canon_num(float(v))
	if v is String:
		return JSON.stringify(v)
	return str(v)


static func canon_line(c: Dictionary) -> String:
	var parts: PackedStringArray = []
	for a in c["args"]:
		parts.append(canon_value(a))
	return "%s(%s) s=%s a=%s lw=%s" % [c["fn"], ",".join(parts), canon_value(c["stroke"]), canon_num(c["alpha"]), canon_num(c["lw"])]


static func fnv1a(text: String) -> String:
	var h: int = 0x811c9dc5
	for b in text.to_utf8_buffer():
		h ^= b
		h = (h * 0x01000193) & 0xFFFFFFFF
	return "%08x" % h


func lines() -> PackedStringArray:
	var out: PackedStringArray = []
	for c in calls:
		out.append(canon_line(c))
	return out


func log_hash() -> String:
	return fnv1a("\n".join(lines()))
