class_name World
extends RefCounted
## Ports js/world.js `load` (Phase 1 subset: walls, floors, doors, props, materials, spots, start).
## Not yet ported: validate/validateAll (Phase 2), zones, light grid, lineBlocked.
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
var doors_by_id: Dictionary = {}
var door_grid: Dictionary = {}
var props: Array[Dictionary] = []
var prop_cells: Dictionary = {}
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
	for r in w.height:
		var row: String = w.rows[r]
		for c in w.width:
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
	for d in def.get("props", []):
		var solid := not NON_SOLID.has(d["type"])
		var p := {"type": d["type"], "x": int(d["col"]) + 0.5, "y": int(d["row"]) + 0.5, "solid": solid, "r": PROP_R}
		w.props.append(p)
		if solid:
			var k := w._key(int(d["col"]), int(d["row"]))
			if not w.prop_cells.has(k):
				w.prop_cells[k] = []
			w.prop_cells[k].append(p)
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


func is_solid(x: float, y: float) -> bool:
	var t := tile_at(x, y)
	if WALLS.contains(t):
		return true
	return DOORS.contains(t) and not open_doors.has(_key(int(floor(x)), int(floor(y))))


func material_at(x: float, y: float) -> String:
	var m: Variant = mat_table.get(tile_at(x, y))
	return m if m != null else floor_mat


func is_door_open(cx: float, cy: float) -> bool:
	return open_doors.has(_key(int(floor(cx)), int(floor(cy))))


## Open or close the door in cell (cx, cy); false if that cell is not a door (no light grid yet).
func set_door(cx: float, cy: float, is_open: bool) -> bool:
	var ix: int = int(floor(cx))
	var iy: int = int(floor(cy))
	if not DOORS.contains(tile_at(ix, iy)):
		return false
	if is_open:
		open_doors[_key(ix, iy)] = true
	else:
		open_doors.erase(_key(ix, iy))
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
