class_name Ripple
extends RefCounted
## Ports the parts of js/ripple.js the renderer needs: the line-boil jitter table and the height mask.
## BOIL_TAB is a Float32Array in JS, so it is a PackedFloat32Array here (same quantisation).

const BOIL_FRAMES := 4
const BOIL_N := 256
const BOIL_FPS := 10.0

static var _tab: PackedFloat32Array = PackedFloat32Array()


static func _boil_tab() -> PackedFloat32Array:
	if _tab.is_empty():
		_tab.resize(BOIL_FRAMES * 2 * BOIL_N)
		var a: int = 0x9e3779b9
		for i in _tab.size():
			a = (a + 0x6D2B79F5) & JsMath.M32
			var t: int = a
			t = JsMath.imul(t ^ (t >> 15), t | 1)
			t = (t ^ (t + JsMath.imul(t ^ (t >> 7), t | 61))) & JsMath.M32
			_tab[i] = (float((t ^ (t >> 14)) & JsMath.M32) / 4294967296.0) * 2.0 - 1.0
	return _tab


## Boil frame 0..3 at time t (10 fps, 4 cycling seeds).
static func boil_frame(t: float) -> int:
	var f: int = int(floor(t * BOIL_FPS))
	return ((f % BOIL_FRAMES) + BOIL_FRAMES) % BOIL_FRAMES


## Stable jitter -1..1 for (frame, id, axis 0|1).
static func jitter(frame: int, id: int, axis: int) -> float:
	var tab := _boil_tab()
	return tab[(((frame & 3) * 2 + (1 if axis != 0 else 0)) * BOIL_N) + (id & (BOIL_N - 1))]


## Visibility 0..1 of a body part at height z for a lit band [z_min, z_max] with soft edges (js maskAlpha).
static func mask_alpha(z: float, z_min: float, z_max: float, soft: float) -> float:
	var s: float = soft if soft > 0.0 else 0.12
	if z >= z_min and z <= z_max:
		return 1.0
	var d: float = z_min - z if z < z_min else z - z_max
	return 0.0 if d >= s else 1.0 - d / s
