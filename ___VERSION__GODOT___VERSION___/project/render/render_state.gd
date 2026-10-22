class_name RenderState
extends RefCounted
## The slice of js/render.js renderer state (`r`) that the line figures read. One instance per frame buffer.
## Internal frame is 640x360 (BASE_W x BASE_H); `quality` 0..3 and `reduced` (reduced motion) as in the JS.

const BASE_W := 640
const BASE_H := 360
const FOV_DEG := 66.0

var ow: int = BASE_W
var oh: int = BASE_H
var cols: int = 320
var col_w: float = 2.0
var wscale: float = 1.0
var quality: int = 3
var reduced: bool = false
## Effects level 0..2 (js r.fx) and the material-detail switch (r.matDetail).
var fx: int = 0
## Horizontal field of view in radians (js fov); set_fov rebuilds the per-column ray offsets when it changes.
var fov: float = FOV_DEG * PI / 180.0
var mat_detail: bool = true
var boil_cfg: bool = true
var horizon: float = 180.0
## Per-column wall distance (js r.zbuf), larger than any figure depth when no wall.
var zbuf: PackedFloat32Array = PackedFloat32Array()
var boil_on: bool = false
var bf: int = 0
var lock_id: int = -1
var lock_k: float = 0.0
var lock_age: float = 1.0
var lock_sp: float = 9.0
var lock_rs: float = 0.0
## cos/sin of each column's view-angle offset (fixed fov), for Raycast.depth_columns.
var col_cos: PackedFloat64Array = PackedFloat64Array()
var col_sin: PackedFloat64Array = PackedFloat64Array()


func _init(width: int = BASE_W, height: int = BASE_H) -> void:
	ow = width
	oh = height
	cols = maxi(80, ow >> 1)
	col_w = float(ow) / cols
	wscale = float(ow) / BASE_W
	horizon = oh / 2.0
	zbuf.resize(cols)
	zbuf.fill(1e9)
	var offs := Raycast.column_offsets(FOV_DEG * PI / 180.0, cols)
	col_cos = offs[0]
	col_sin = offs[1]


func tan_half() -> float:
	return tan(fov / 2.0)


func set_fov(f: float) -> void:
	if absf(f - fov) < 1e-9:
		return
	fov = f
	var offs := Raycast.column_offsets(fov, cols)
	col_cos = offs[0]
	col_sin = offs[1]


## Line boil is on at quality >= 2 unless reduced motion (js drawFirstPerson / drawSolo).
func update_boil(t: float) -> void:
	boil_on = boil_cfg and not reduced and quality >= 2
	bf = Ripple.boil_frame(t) if boil_on else 0


## js J(r, id, axis).
func j(id: int, axis: int) -> float:
	return Ripple.jitter(bf, id, axis) if boil_on else 0.0
