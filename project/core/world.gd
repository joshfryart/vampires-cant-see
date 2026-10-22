class_name World
extends RefCounted
## Ports js/world.js `load` (Phase 1 subset: walls, floors, doors, props, materials, spots, start).
## Validation lives in world_validate.gd. Zones (kind_at / zone_at) are here.
## Logic uses plain floats; cells are (col, row), a point (x, y) is in cell (floor(x), floor(y)).

const WALLS := "#BWIw"
const DOORS := "DG"
const MATERIAL := {
	"#": "stone", "B": "brick", "W": "wood", "I": "iron", "w": "glass",
	".": "stone", ",": "wood", "g": "grass", "D": "wood", "G": "iron",
}
const FLOOR_MATS := ["stone", "wood", "grass", "cobble", "roughStone"]
const MATERIALS := ["stone", "brick", "roughStone", "cobble", "wood", "glass", "iron", "grass"]
const NON_SOLID := ["cross", "torch"]
const PROP_R := 0.3
const DEFAULT_LIGHT := {"torch": 3.0, "brazier": 3.5}
const LIGHT_SCALE := 0.39
## Outer halo reaches this many times the core radius (js/world.js OUTER_K).
const OUTER_K := 1.8
## Door facing -> [dx, dy, angle].
const FACING := {"n": [0, -1, -PI / 2], "s": [0, 1, PI / 2], "e": [1, 0, 0.0], "w": [-1, 0, PI]}

var name: String = ""
var kind: String = "indoor"
var floor_mat: String = "stone"
var width: int = 0
var height: int = 0
var rows: Array = []
var mat_table: Dictionary = {}
var open_doors: Dictionary = {}
## Per-cell flags for fast queries: 0 floor, 1 wall, 2 door. A door is solid until its cell is in open_doors.
var cell_kind: PackedByteArray = PackedByteArray()
var cell_open: PackedByteArray = PackedByteArray()
## Ray-cast caches: solid_grid = cell_solid() as 0/1 (follows door state); mat_grid = hit material index into Sonar.MATS (same order as RAY_MATS).
var solid_grid: PackedByteArray = PackedByteArray()
var mat_grid: PackedByteArray = PackedByteArray()
var tile_grid: PackedInt32Array = PackedInt32Array()
const RAY_MATS := ["stone", "brick", "wood", "iron", "glass", "cobble", "roughStone", "grass"]
var doors_by_id: Dictionary = {}
var door_grid: Dictionary = {}
var props: Array[Dictionary] = []
var prop_cells: Dictionary = {}
var lights: Array[Dictionary] = []
var light_grid: PackedFloat32Array = PackedFloat32Array()
var outer_grid: PackedFloat32Array = PackedFloat32Array()
var zones: Array = []
var kind_grid: PackedStringArray = PackedStringArray()
var zone_grid: PackedStringArray = PackedStringArray()
var start: Variant = null
var spots: Dictionary = {"crypt": [], "safe": [], "people": [], "doors": []}


## Ports load (js/world.js:389) without validation.
static func from_def(def: Dictionary) -> World:
	var w := World.new()
	w.name = str(def["name"])
	w.kind = "outdoor" if def.get("kind", "") == "outdoor" else "indoor"
	w.rows = def["rows"]
	w.height = w.rows.size()
	w.width = String(w.rows[0]).length()
	w.floor_mat = def["floor"] if FLOOR_MATS.has(def.get("floor", "")) else "stone"
	w.kind_grid.resize(w.width * w.height)
	w.zone_grid.resize(w.width * w.height)
	for i in w.kind_grid.size():
		w.kind_grid[i] = w.kind
	w.zones = def.get("zones", []) if def.get("zones") is Array else []
	for z in w.zones:
		for zy in range(int(z["y0"]), int(z["y1"]) + 1):
			for zx in range(int(z["x0"]), int(z["x1"]) + 1):
				w.kind_grid[zy * w.width + zx] = z["kind"]
				w.zone_grid[zy * w.width + zx] = z["name"]
	w.cell_kind.resize(w.width * w.height)
	w.cell_open.resize(w.width * w.height)
	for r in w.height:
		var row: String = w.rows[r]
		for c in w.width:
			var ch: String = row[c]
			w.cell_kind[r * w.width + c] = 1 if WALLS.contains(ch) else (2 if DOORS.contains(ch) else 0)
			var p := Vector2(c + 0.5, r + 0.5)
			match row[c]:
				"@": w.start = p
				"C": w.spots["crypt"].append(p)
				"S": w.spots["safe"].append(p)
				"P": w.spots["people"].append(p)
				"D": w.spots["doors"].append(p)
	for d in def.get("doors", []):
		var entry := {"id": d["id"], "col": int(d["col"]), "row": int(d["row"]), "toMap": d.get("toMap"), "toDoor": d.get("toDoor"), "facing": d["facing"]}
		w.doors_by_id[d["id"]] = entry
		w.door_grid[w._key(entry["col"], entry["row"])] = entry
	w.mat_table = MATERIAL.duplicate()
	var over: Dictionary = def.get("materials", {})
	for ch in over:
		if MATERIAL.has(ch) and MATERIALS.has(over[ch]):
			w.mat_table[ch] = over[ch]
	w.solid_grid.resize(w.width * w.height)
	w.mat_grid.resize(w.width * w.height)
	w.tile_grid.resize(w.width * w.height)
	for r in w.height:
		var row2: String = w.rows[r]
		for c in w.width:
			var k2: int = r * w.width + c
			w.solid_grid[k2] = 1 if w.cell_kind[k2] != 0 else 0
			var mname: String = w.mat_table.get(row2[c], w.floor_mat)
			var mi: int = RAY_MATS.find(mname)
			w.mat_grid[k2] = 0 if mi < 0 else mi
			w.tile_grid[k2] = row2.unicode_at(c)
	for d in def.get("props", []):
		var solid := not NON_SOLID.has(d["type"])
		var light: float = float(d["light"]) if d.get("light") is float or d.get("light") is int else float(DEFAULT_LIGHT.get(d["type"], 0.0))
		if not (light > 0.0):
			light = 0.0
		var p := {"type": d["type"], "x": int(d["col"]) + 0.5, "y": int(d["row"]) + 0.5, "solid": solid, "r": PROP_R, "light": light}
		w.props.append(p)
		if light > 0.0:
			w.lights.append({"x": p["x"], "y": p["y"], "radius": light * LIGHT_SCALE, "type": p["type"]})
		if solid:
			var k := w._key(int(d["col"]), int(d["row"]))
			if not w.prop_cells.has(k):
				w.prop_cells[k] = []
			w.prop_cells[k].append(p)
	w.light_grid.resize(w.width * w.height)
	w.outer_grid.resize(w.width * w.height)
	w.recompute_lights()
	return w


func _key(cx: int, cy: int) -> int:
	return cy * width + cx


## Ports tileAt (out of bounds is wall).
func tile_at(x: float, y: float) -> String:
	var cx: int = int(floor(x))
	var cy: int = int(floor(y))
	if not (cx >= 0 and cy >= 0 and cx < width and cy < height):
		return "#"
	return String(rows[cy])[cx]


## Solid test on integer cell coordinates (out of bounds is solid): the hot path of the ray cast.
func cell_solid(cx: int, cy: int) -> bool:
	if cx < 0 or cy < 0 or cx >= width or cy >= height:
		return true
	var k: int = cy * width + cx
	var kind: int = cell_kind[k]
	return kind == 1 or (kind == 2 and cell_open[k] == 0)


func is_solid(x: float, y: float) -> bool:
	return cell_solid(int(floor(x)), int(floor(y)))


func material_at(x: float, y: float) -> String:
	var m: Variant = mat_table.get(tile_at(x, y))
	return m if m != null else floor_mat


func is_door_open(cx: float, cy: float) -> bool:
	return open_doors.has(_key(int(floor(cx)), int(floor(cy))))


## Open or close the door in cell (cx, cy); false if that cell is not a door. Relights when the state changes.
func set_door(cx: float, cy: float, is_open: bool) -> bool:
	var ix: int = int(floor(cx))
	var iy: int = int(floor(cy))
	if not DOORS.contains(tile_at(ix, iy)):
		return false
	var was: bool = open_doors.has(_key(ix, iy))
	if is_open:
		open_doors[_key(ix, iy)] = true
		cell_open[_key(ix, iy)] = 1
		solid_grid[_key(ix, iy)] = 0
	else:
		open_doors.erase(_key(ix, iy))
		cell_open[_key(ix, iy)] = 0
		solid_grid[_key(ix, iy)] = 1
	if was != is_open and lights.size() > 0:
		recompute_lights()
	return true


func door_at(cx: float, cy: float) -> Variant:
	var ix: int = int(floor(cx))
	var iy: int = int(floor(cy))
	if not (ix >= 0 and iy >= 0 and ix < width and iy < height):
		return null
	return door_grid.get(_key(ix, iy))


## Arrival pose {x, y, angle} for a door id, or null.
func arrival(door_id: String) -> Variant:
	if not doors_by_id.has(door_id):
		return null
	var d: Dictionary = doors_by_id[door_id]
	var f: Array = FACING[d["facing"]]
	return {"x": d["col"] + 0.5 + f[0], "y": d["row"] + 0.5 + f[1], "angle": float(f[2])}


## Ports blocks (js/world.js:523): circle of radius r against walls and solid props.
func blocks(x: float, y: float, r: float) -> bool:
	if is_nan(x) or is_nan(y) or is_inf(x) or is_inf(y):
		return true
	if not (r > 0.0):
		r = 0.0
	if is_solid(x - r, y - r) or is_solid(x + r, y - r) or is_solid(x - r, y + r) or is_solid(x + r, y + r):
		return true
	var reach: float = r + PROP_R
	var c0: int = maxi(0, int(floor(x - reach)))
	var c1: int = mini(width - 1, int(floor(x + reach)))
	var r0: int = maxi(0, int(floor(y - reach)))
	var r1: int = mini(height - 1, int(floor(y + reach)))
	for cy in range(r0, r1 + 1):
		for cx in range(c0, c1 + 1):
			var list: Variant = prop_cells.get(_key(cx, cy))
			if list == null:
				continue
			for p in list:
				var dx: float = x - p["x"]
				var dy: float = y - p["y"]
				var rr: float = r + p["r"]
				if dx * dx + dy * dy < rr * rr:
					return true
	return false


## True when a solid tile lies strictly between the cell of (x0, y0) and the cell of (x1, y1) (DDA); glass lets light through.
## Ports lineBlocked (js/world.js:553).
func line_blocked(x0: float, y0: float, x1: float, y1: float) -> bool:
	var cx: int = int(floor(x0))
	var cy: int = int(floor(y0))
	var ex: int = int(floor(x1))
	var ey: int = int(floor(y1))
	if cx == ex and cy == ey:
		return false
	var dx: float = x1 - x0
	var dy: float = y1 - y0
	var step_x: int = -1 if dx < 0.0 else 1
	var step_y: int = -1 if dy < 0.0 else 1
	var tdx: float = INF if dx == 0.0 else absf(1.0 / dx)
	var tdy: float = INF if dy == 0.0 else absf(1.0 / dy)
	var tx: float = INF if dx == 0.0 else ((x0 - cx) if dx < 0.0 else (cx + 1 - x0)) * tdx
	var ty: float = INF if dy == 0.0 else ((y0 - cy) if dy < 0.0 else (cy + 1 - y0)) * tdy
	for i in 256:
		if tx < ty:
			tx += tdx
			cx += step_x
		else:
			ty += tdy
			cy += step_y
		if cx == ex and cy == ey:
			return false
		if cx < 0 or cy < 0 or cx >= width or cy >= height:
			return true
		var k: int = cy * width + cx
		if solid_grid[k] == 1 and tile_grid[k] != 119:
			return true
	return true


## Ports recomputeLights (js/world.js:575): per-cell max falloff for the core radius and the outer halo.
func recompute_lights() -> void:
	light_grid.fill(0.0)
	outer_grid.fill(0.0)
	for l in lights:
		var rad: float = l["radius"]
		var ro: float = rad * OUTER_K
		var c0: int = maxi(0, int(floor(l["x"] - ro)))
		var c1: int = mini(width - 1, int(floor(l["x"] + ro)))
		var r0: int = maxi(0, int(floor(l["y"] - ro)))
		var r1: int = mini(height - 1, int(floor(l["y"] + ro)))
		for cy in range(r0, r1 + 1):
			for cx in range(c0, c1 + 1):
				if is_solid(cx + 0.5, cy + 0.5):
					continue
				var px: float = cx + 0.5
				var py: float = cy + 0.5
				var d: float = sqrt((px - l["x"]) * (px - l["x"]) + (py - l["y"]) * (py - l["y"]))
				if d >= ro:
					continue
				var k: int = cy * width + cx
				var vo: float = 1.0 if d <= 0.5 * ro else 2.0 - 2.0 * d / ro
				var need_o: bool = vo > outer_grid[k]
				var v: float = 0.0 if d >= rad else (1.0 if d <= 0.5 * rad else 2.0 - 2.0 * d / rad)
				var need_c: bool = v > light_grid[k]
				if not need_o and not need_c:
					continue
				if line_blocked(l["x"], l["y"], px, py):
					continue
				if need_o:
					outer_grid[k] = vo
				if need_c:
					light_grid[k] = v


## Light 0..1 at (x, y) (js lightAt).
func light_at(x: float, y: float) -> float:
	var cx: int = int(floor(x))
	var cy: int = int(floor(y))
	if not (cx >= 0 and cy >= 0 and cx < width and cy < height):
		return 0.0
	return light_grid[cy * width + cx]


func outer_at(x: float, y: float) -> float:
	var cx: int = int(floor(x))
	var cy: int = int(floor(y))
	if not (cx >= 0 and cy >= 0 and cx < width and cy < height):
		return 0.0
	return outer_grid[cy * width + cx]


## Read-only copy of the light sources {x, y, radius} (js lightSources).
func light_sources() -> Array:
	var out: Array = []
	for l in lights:
		out.append({"x": l["x"], "y": l["y"], "radius": l["radius"]})
	return out


## Indoor/outdoor kind at (x, y); outside the map it is the map kind (js kindAt).
func kind_at(x: float, y: float) -> String:
	var cx: int = int(floor(x))
	var cy: int = int(floor(y))
	if not (cx >= 0 and cy >= 0 and cx < width and cy < height):
		return kind
	return kind_grid[cy * width + cx]


## Name of the zone at (x, y), or "" (js zoneAt returns null).
func zone_at(x: float, y: float) -> String:
	var cx: int = int(floor(x))
	var cy: int = int(floor(y))
	if not (cx >= 0 and cy >= 0 and cx < width and cy < height):
		return ""
	return zone_grid[cy * width + cx]


## True when the door in cell (cx, cy) leads to another map (js isLinkDoor).
func is_link_door(cx: float, cy: float) -> bool:
	return door_at(cx, cy) != null
