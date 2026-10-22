class_name WorldValidate
extends RefCounted
## Ports js/world.js validate / reachable / validateAll. Never throws; returns {ok, errors} where each error is
## {code, message, map, ...extra} with the same codes as the JS (E_MAP_EMPTY, E_MAP_NOT_RECT, E_MAP_TOO_BIG, ...).

const WALLS := "#BWIw"
const FLOORS := ".,g"
const MARKERS := "@CSP"
const VALID := "#BWIw.,gDG@CSP"
const MAX_W := 64
const MAX_H := 48
const PROP_TYPES := ["gravestone", "cross", "barrel", "table", "chair", "bench", "well", "torch", "brazier"]
const NON_SOLID := ["cross", "torch"]
const PROP_R := 0.3


static func _is_int(v: Variant) -> bool:
	return (v is int) or (v is float and is_finite(v) and floor(v) == v)


static func _is_wall(ch: String) -> bool:
	return WALLS.contains(ch)


static func _is_floor(ch: String) -> bool:
	return FLOORS.contains(ch) or MARKERS.contains(ch)


static func _ch_at(rows: Array, c: int, r: int) -> String:
	if r >= 0 and r < rows.size() and c >= 0 and c < String(rows[r]).length():
		return String(rows[r])[c]
	return "#"


static func _add(errors: Array, code: String, message: String, map_name: String, extra: Dictionary = {}) -> void:
	var e := {"code": code, "message": message, "map": map_name}
	e.merge(extra, true)
	errors.append(e)


## Ports validate (js/world.js:50). all_names / links may be null. opts.requireStart defaults to true.
static func validate(map_def: Variant, all_names: Variant = null, links: Variant = null, opts: Variant = null) -> Dictionary:
	var errors: Array = []
	var map_name := "unknown"
	if map_def is Dictionary and map_def.has("name"):
		map_name = str(map_def["name"])
	var names: Array = all_names if all_names is Array else [map_name]
	var lks: Array = links if links is Array else []
	var require_start: bool = not (opts is Dictionary and opts.get("requireStart") == false)
	var rows: Array = map_def["rows"] if map_def is Dictionary and map_def.get("rows") is Array else []
	var rect := false
	if rows.is_empty():
		_add(errors, "E_MAP_EMPTY", "map %s has no rows" % map_name, map_name)
	else:
		var w: int = String(rows[0]).length() if rows[0] is String else -1
		rect = true
		for r in rows.size():
			if not (rows[r] is String) or String(rows[r]).length() != w or w == 0:
				rect = false
				_add(errors, "E_MAP_NOT_RECT", "map %s row %d has wrong width" % [map_name, r], map_name, {"row": r})
		if w == 0 and rect:
			rect = false
			_add(errors, "E_MAP_EMPTY", "map %s has empty rows" % map_name, map_name)
		if rect and (w > MAX_W or rows.size() > MAX_H):
			_add(errors, "E_MAP_TOO_BIG", "map %s is %dx%d (max %dx%d)" % [map_name, w, rows.size(), MAX_W, MAX_H], map_name)
		var starts := 0
		for r in rows.size():
			var row: Variant = rows[r]
			if not (row is String):
				continue
			for c in String(row).length():
				var ch: String = String(row)[c]
				if not VALID.contains(ch):
					_add(errors, "E_MAP_BAD_TILE", "map %s row %d col %d has invalid tile %s" % [map_name, r, c, JSON.stringify(ch)], map_name, {"row": r, "col": c, "char": ch})
					continue
				if ch == "@":
					starts += 1
				var edge: bool = r == 0 or r == rows.size() - 1 or c == 0 or c == String(row).length() - 1
				if edge and not _is_wall(ch):
					_add(errors, "E_MAP_OPEN_EDGE", "map %s row %d col %d is a non-wall on the border" % [map_name, r, c], map_name, {"row": r, "col": c})
		if require_start:
			if starts == 0:
				_add(errors, "E_MAP_NO_START", "map %s has no start tile @" % map_name, map_name)
			elif starts > 1:
				_add(errors, "E_MAP_MULTI_START", "map %s has %d start tiles @" % [map_name, starts], map_name)
		elif starts > 1:
			_add(errors, "E_MAP_MULTI_START", "map %s has %d start tiles @" % [map_name, starts], map_name)
	if rect and map_def.has("zones"):
		_validate_zones(map_def["zones"], rows, map_name, errors)
	if rect:
		_validate_contents(map_def, rows, map_name, errors)
	for l in lks:
		if l is Dictionary and not names.has(l.get("to")):
			_add(errors, "E_MAP_BAD_LINK", "map %s link from %s targets missing map %s" % [map_name, str(l.get("from")), str(l.get("to"))], map_name)
	return {"ok": errors.is_empty(), "errors": errors}


static func _validate_zones(zs: Variant, rows: Array, map_name: String, errors: Array) -> void:
	var zw: int = String(rows[0]).length()
	var zh: int = rows.size()
	if not (zs is Array):
		_add(errors, "E_MAP_BAD_ZONE", "map %s zones must be an array" % map_name, map_name)
		return
	var seen := {}
	for i in zs.size():
		var z: Variant = zs[i]
		var tag := "map %s zone %d" % [map_name, i]
		if not (z is Dictionary):
			_add(errors, "E_MAP_BAD_ZONE", tag + " is not an object", map_name)
			continue
		if not (z.get("name") is String) or z["name"] == "":
			_add(errors, "E_MAP_BAD_ZONE", tag + " has no name", map_name)
			continue
		if seen.has(z["name"]):
			_add(errors, "E_MAP_BAD_ZONE", "%s duplicates name %s" % [tag, z["name"]], map_name)
		seen[z["name"]] = true
		if z.get("kind") != "indoor" and z.get("kind") != "outdoor":
			_add(errors, "E_MAP_BAD_ZONE", "%s (%s) has bad kind %s" % [tag, z["name"], JSON.stringify(z.get("kind"))], map_name)
			continue
		if not (_is_int(z.get("x0")) and _is_int(z.get("y0")) and _is_int(z.get("x1")) and _is_int(z.get("y1"))) \
				or z["x0"] < 0 or z["y0"] < 0 or z["x1"] >= zw or z["y1"] >= zh or z["x0"] > z["x1"] or z["y0"] > z["y1"]:
			_add(errors, "E_MAP_BAD_ZONE", "%s (%s) rect is out of bounds or inverted" % [tag, z["name"]], map_name)


static func _validate_contents(map_def: Dictionary, rows: Array, map_name: String, errors: Array) -> void:
	var w: int = String(rows[0]).length()
	var h: int = rows.size()
	# Props first (doors and paths consult the solid ones).
	var solid_cells := {}
	var props: Variant = map_def.get("props")
	if props != null and not (props is Array):
		_add(errors, "E_MAP_BAD_PROP", "map %s props must be an array" % map_name, map_name)
	elif props is Array:
		for i in props.size():
			var p: Variant = props[i]
			var tag := "map %s prop %d" % [map_name, i]
			if not (p is Dictionary):
				_add(errors, "E_MAP_BAD_PROP", tag + " is not an object", map_name)
				continue
			if not PROP_TYPES.has(p.get("type")):
				_add(errors, "E_MAP_BAD_PROP", "%s has unknown type %s" % [tag, JSON.stringify(p.get("type"))], map_name)
				continue
			if not (_is_int(p.get("col")) and _is_int(p.get("row"))) or p["col"] < 0 or p["row"] < 0 or p["col"] >= w or p["row"] >= h:
				_add(errors, "E_MAP_BAD_PROP", "%s (%s) is out of bounds" % [tag, p["type"]], map_name)
				continue
			if not _is_floor(_ch_at(rows, int(p["col"]), int(p["row"]))):
				_add(errors, "E_MAP_BAD_PROP", "%s (%s) at %d,%d is not on a floor cell" % [tag, p["type"], int(p["col"]), int(p["row"])], map_name)
				continue
			if p.has("light") and not ((p["light"] is float or p["light"] is int) and is_finite(float(p["light"])) and float(p["light"]) >= 0.0):
				_add(errors, "E_MAP_BAD_PROP", "%s (%s) has bad light radius" % [tag, p["type"]], map_name)
				continue
			var key: int = int(p["row"]) * 4096 + int(p["col"])
			if not NON_SOLID.has(p["type"]):
				if solid_cells.has(key):
					_add(errors, "E_MAP_BAD_PROP", "%s (%s) shares cell %d,%d with another solid prop" % [tag, p["type"], int(p["col"]), int(p["row"])], map_name)
				solid_cells[key] = true
	# Doors.
	var doors: Variant = map_def.get("doors")
	if doors != null and not (doors is Array):
		_add(errors, "E_MAP_BAD_DOOR", "map %s doors must be an array" % map_name, map_name)
	elif doors is Array:
		var ids := {}
		var cells := {}
		for i in doors.size():
			var d: Variant = doors[i]
			var did_str: String = str(d["id"]) if d is Dictionary and d.has("id") else "#%d" % i
			var tag := "map %s door %s" % [map_name, did_str]
			if not (d is Dictionary):
				_add(errors, "E_MAP_BAD_DOOR", tag + " is not an object", map_name)
				continue
			var did: Variant = d["id"] if d.get("id") is String and d["id"] != "" else null
			if did == null:
				_add(errors, "E_MAP_BAD_DOOR", tag + " has no string id", map_name, {"door": d.get("id")})
				continue
			if ids.has(did):
				_add(errors, "E_MAP_BAD_DOOR", tag + " has a duplicate id", map_name, {"door": did})
			ids[did] = true
			if not (_is_int(d.get("col")) and _is_int(d.get("row"))) or d["col"] < 0 or d["row"] < 0 or d["col"] >= w or d["row"] >= h:
				_add(errors, "E_MAP_BAD_DOOR", tag + " is out of bounds", map_name, {"door": did})
				continue
			var dch := _ch_at(rows, int(d["col"]), int(d["row"]))
			if dch != "D" and dch != "G":
				_add(errors, "E_MAP_BAD_DOOR", "%s at %d,%d is not on a D or G cell" % [tag, int(d["col"]), int(d["row"])], map_name, {"door": did})
				continue
			var ck: int = int(d["row"]) * 4096 + int(d["col"])
			if cells.has(ck):
				_add(errors, "E_MAP_BAD_DOOR", "%s shares its cell with door %s" % [tag, cells[ck]], map_name, {"door": did})
			cells[ck] = did
			if not World.FACING.has(d.get("facing")):
				_add(errors, "E_MAP_BAD_DOOR", "%s has bad facing %s" % [tag, JSON.stringify(d.get("facing"))], map_name, {"door": did})
				continue
			var f: Array = World.FACING[d["facing"]]
			var ac: int = int(d["col"]) + int(f[0])
			var ar: int = int(d["row"]) + int(f[1])
			if not _is_floor(_ch_at(rows, ac, ar)):
				_add(errors, "E_MAP_BAD_DOOR", "%s arrival cell %d,%d is not walkable floor" % [tag, ac, ar], map_name, {"door": did})
			elif solid_cells.has(ar * 4096 + ac):
				_add(errors, "E_MAP_BAD_DOOR", "%s arrival cell %d,%d holds a solid prop" % [tag, ac, ar], map_name, {"door": did})
	# Hides.
	if map_def.has("hides"):
		var hides: Variant = map_def["hides"]
		if not (hides is Array):
			_add(errors, "E_MAP_BAD_HIDE", "map %s hides must be an array" % map_name, map_name)
		else:
			for i in hides.size():
				var hd: Variant = hides[i]
				var ok: bool = hd is Array and hd.size() >= 2 and _is_int(hd[0]) and _is_int(hd[1]) and hd[0] >= 0 and hd[1] >= 0 and hd[0] < w and hd[1] < h and _is_floor(_ch_at(rows, int(hd[0]), int(hd[1])))
				if not ok:
					_add(errors, "E_MAP_BAD_HIDE", "map %s hide %d is not an in-bounds floor cell" % [map_name, i], map_name, {"hide": i})
	# Paths: every segment clear of walls and solid props.
	var paths: Variant = map_def.get("paths")
	if paths is Array:
		var solid_list: Array = []
		if map_def.get("props") is Array:
			for p in map_def["props"]:
				if p is Dictionary and PROP_TYPES.has(p.get("type")) and not NON_SOLID.has(p["type"]) and _is_int(p.get("col")) and _is_int(p.get("row")):
					solid_list.append(p)
		for i in paths.size():
			var pts: Variant = paths[i].get("points") if paths[i] is Dictionary and paths[i].get("points") is Array else null
			if pts == null or pts.is_empty():
				continue
			var ok_pts := true
			for k in pts.size():
				var q: Variant = pts[k]
				if not (q is Array) or q.size() < 2 or not (q[0] is float or q[0] is int) or not (q[1] is float or q[1] is int):
					_add(errors, "E_MAP_BAD_PATH", "map %s path %d point %d is invalid" % [map_name, i, k], map_name, {"path": i})
					ok_pts = false
					break
			if not ok_pts:
				continue
			for k in pts.size():
				var a: Array = pts[k]
				var b: Array = pts[(k + 1) % pts.size()]
				var ax: float = float(a[0]) + 0.5
				var ay: float = float(a[1]) + 0.5
				var bx: float = float(b[0]) + 0.5
				var by: float = float(b[1]) + 0.5
				var length: float = sqrt((bx - ax) * (bx - ax) + (by - ay) * (by - ay))
				var n: int = maxi(1, int(ceil(length / 0.1)))
				var bad := false
				var s := 0
				while s <= n and not bad:
					var fr: float = float(s) / n
					if _blocked_at(rows, solid_list, ax + (bx - ax) * fr, ay + (by - ay) * fr):
						bad = true
					s += 1
				if bad:
					_add(errors, "E_MAP_BAD_PATH", "map %s path %d segment %d crosses a wall or solid prop" % [map_name, i, k], map_name, {"path": i, "segment": k})
					break


static func _blocked_at(rows: Array, solid_list: Array, x: float, y: float) -> bool:
	var ch := _ch_at(rows, int(floor(x)), int(floor(y)))
	if _is_wall(ch):
		return true
	for p in solid_list:
		var dx: float = x - (float(p["col"]) + 0.5)
		var dy: float = y - (float(p["row"]) + 0.5)
		if dx * dx + dy * dy < PROP_R * PROP_R:
			return true
	return false


static func _maps_of(map_data: Variant) -> Dictionary:
	if map_data is Dictionary and map_data.get("maps") is Dictionary:
		return map_data["maps"]
	return {}


## Names of maps reachable from start_name through link doors (start first).
static func reachable(map_data: Variant, start_name: String) -> Array:
	var maps := _maps_of(map_data)
	var out: Array = []
	if not maps.has(start_name):
		return out
	var seen := {start_name: true}
	var queue: Array = [start_name]
	while not queue.is_empty():
		var n: String = queue.pop_front()
		out.append(n)
		var ds: Array = maps[n].get("doors", []) if maps[n] is Dictionary and maps[n].get("doors") is Array else []
		for d in ds:
			var t: Variant = d.get("toMap") if d is Dictionary else null
			if t is String and not seen.has(t) and maps.has(t):
				seen[t] = true
				queue.append(t)
	return out


## Validate every map plus the link graph (js validateAll). Errors carry {code, message, map, door?}.
static func validate_all(map_data: Variant) -> Dictionary:
	var errors: Array = []
	var maps := _maps_of(map_data)
	var names: Array = maps.keys()
	var start_map: Variant = map_data.get("startMap") if map_data is Dictionary else null
	if not (start_map is String) or not maps.has(start_map):
		_add(errors, "E_MAP_NO_STARTMAP", "startMap %s is not a defined map" % JSON.stringify(start_map), start_map if start_map is String else "unknown")
	for n in names:
		var def: Variant = maps[n]
		var res := validate(def, names, null, {"requireStart": n == start_map or n == "test"})
		for e in res["errors"]:
			if not e.get("map") or e["map"] == "unknown":
				e["map"] = n
			errors.append(e)
		var ds: Array = def.get("doors", []) if def is Dictionary and def.get("doors") is Array else []
		for d in ds:
			if not (d is Dictionary) or not (d.get("id") is String):
				continue
			var tag := "map %s door %s" % [n, d["id"]]
			if not (d.get("toMap") is String) or not (d.get("toDoor") is String):
				_add(errors, "E_MAP_BAD_LINK", tag + " has no toMap/toDoor", n, {"door": d["id"]})
				continue
			if d["toMap"] == n:
				_add(errors, "E_MAP_SELF_LINK", tag + " links to its own map", n, {"door": d["id"]})
				continue
			if not maps.has(d["toMap"]):
				_add(errors, "E_MAP_BAD_LINK", "%s targets missing map %s" % [tag, d["toMap"]], n, {"door": d["id"]})
				continue
			var tds: Array = maps[d["toMap"]].get("doors", []) if maps[d["toMap"]].get("doors") is Array else []
			var target: Variant = null
			for td in tds:
				if td is Dictionary and td.get("id") == d["toDoor"]:
					target = td
					break
			if target == null:
				_add(errors, "E_MAP_BAD_LINK", "%s targets missing door %s.%s" % [tag, d["toMap"], d["toDoor"]], n, {"door": d["id"]})
				continue
			if target.get("toMap") != n or target.get("toDoor") != d["id"]:
				_add(errors, "E_MAP_ONEWAY", "%s -> %s.%s does not link back" % [tag, d["toMap"], d["toDoor"]], n, {"door": d["id"]})
	if start_map is String and maps.has(start_map):
		var reach := reachable(map_data, start_map)
		for n in names:
			if n != "test" and not reach.has(n):
				_add(errors, "E_MAP_UNREACHABLE", "map %s is not reachable from %s" % [n, start_map], n)
	return {"ok": errors.is_empty(), "errors": errors}
