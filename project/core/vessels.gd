class_name Vessels
extends RefCounted
## Ports js/data/vessels.js: the whole-body circulatory pulse. Vessel graph data (arteries and mirrored veins on the pose slots),
## pulse state per mode and blood level, beat timing, the travelling pulse envelope and the limb-curve edge geometry.
## Pure functions, no game state. A node is a Dictionary {id, parent, slot, to, t, pathLen, w, hot, periph, head, vein}.

const PWV := 6.0
const PWV_SCALE := 1.75
const BPM_MAX := 175.0
const DUB_DELAY := 0.3
const DUB_K := 0.3
const ATTACK := 0.06
const DECAY := 0.25
const VEIN_DRIFT := 0.2
const REST_BPM := 65.0
const DUB_K_FAST := 0.15
const DUB_FADE_BPM := 120.0
const VEIN_LAG := 0.08
const VEIN_SLOW := 1.25
const VEIN_ATTACK := 0.1
const VEIN_DECAY := 0.3
const SOFT_ATTACK := 0.1
const SOFT_DECAY := 0.3
const TAIL := 0.2
const LIFE_TAUS := 1.2
const ARTERY_RGB := [200, 32, 36]
const VEIN_RGB := [104, 34, 92]
const HEART := {"slot": 14, "to": 1, "t": 0.45}

## Mode table (villager mode names): bpm before blood loss, stateK overall strength, periphK on peripheral nodes, headK on neck/temple.
const MODES := {
	"calm": {"bpm": 65.0, "stateK": 1.0, "periphK": 1.0, "headK": 1.0},
	"wary": {"bpm": 90.0, "stateK": 1.15, "periphK": 1.0, "headK": 1.25},
	"startle": {"bpm": 100.0, "stateK": 1.3, "periphK": 0.8, "headK": 1.1},
	"flee": {"bpm": 130.0, "stateK": 1.5, "periphK": 0.5, "headK": 1.0},
	"cower": {"bpm": 130.0, "stateK": 1.5, "periphK": 0.5, "headK": 1.0},
	"sleep": {"bpm": 52.0, "stateK": 0.8, "periphK": 1.0, "headK": 1.0},
	"drinking": {"bpm": 120.0, "stateK": 1.0, "periphK": 1.0, "headK": 1.0},
	"fed": {"bpm": 0.0, "stateK": 0.0, "periphK": 0.0, "headK": 0.0},
	"drained": {"bpm": 0.0, "stateK": 0.0, "periphK": 0.0, "headK": 0.0},
}

## limb curve ends per elbow/knee slot
const LIMB := {10: [2, 6], 11: [3, 7], 12: [4, 8], 13: [5, 9]}

static var ARTERIES: Array = []
static var VEINS: Array = []
static var _delay_cache := {}
static var _edge_cache := {}


static func _node(id: String, parent: Variant, slot: int, to: int, t: float, path_len: float, w: float, hot: float, periph: float, head: bool = false) -> Dictionary:
	return {"id": id, "parent": parent, "slot": slot, "to": to, "t": t, "pathLen": path_len, "w": w, "hot": hot, "periph": periph, "head": head, "vein": false}


static func _init_nodes() -> void:
	if not ARTERIES.is_empty():
		return
	ARTERIES = [
		_node("heart", null, 14, 1, 0.45, 0.0, 1.0, 0.5, 0.0),
		_node("arch", "heart", 14, 1, 0.75, 0.1, 0.9, 0.0, 0.0),
		_node("carotid", "arch", 1, 1, 0.0, 0.25, 0.75, 0.6, 0.0, true),
		_node("temporal", "carotid", 0, 0, 0.0, 0.4, 0.5, 0.25, 0.2, true),
		_node("subclavL", "arch", 2, 2, 0.0, 0.3, 0.6, 0.0, 0.1),
		_node("subclavR", "arch", 3, 3, 0.0, 0.3, 0.6, 0.0, 0.1),
		_node("brachialL", "subclavL", 10, 10, 0.0, 0.6, 0.45, 0.25, 0.4),
		_node("brachialR", "subclavR", 11, 11, 0.0, 0.6, 0.45, 0.25, 0.4),
		_node("radialL", "brachialL", 6, 6, 0.0, 0.9, 0.35, 0.35, 1.0),
		_node("radialR", "brachialR", 7, 7, 0.0, 0.9, 0.35, 0.35, 1.0),
		_node("aorta", "arch", 14, 14, 0.0, 0.45, 0.7, 0.0, 0.0),
		_node("femoralL", "aorta", 4, 4, 0.0, 0.7, 0.6, 0.4, 0.0),
		_node("femoralR", "aorta", 5, 5, 0.0, 0.7, 0.6, 0.4, 0.0),
		_node("poplitealL", "femoralL", 12, 12, 0.0, 0.95, 0.4, 0.15, 0.4),
		_node("poplitealR", "femoralR", 13, 13, 0.0, 0.95, 0.4, 0.15, 0.4),
		_node("pedalL", "poplitealL", 8, 8, 0.0, 1.35, 0.25, 0.2, 1.0),
		_node("pedalR", "poplitealR", 9, 9, 0.0, 1.35, 0.25, 0.2, 1.0),
	]
	VEINS = []
	for a in ARTERIES:
		VEINS.append({
			"id": "v_" + a["id"], "parent": ("v_" + a["parent"]) if a["parent"] != null else null, "slot": a["slot"], "to": a["to"], "t": a["t"],
			"pathLen": a["pathLen"], "w": floorf(a["w"] * 0.5 * 1000.0 + 0.5) / 1000.0, "hot": 0.0, "periph": a["periph"], "head": false, "vein": true,
		})


static func all() -> Array:
	_init_nodes()
	return ARTERIES + VEINS


static func by_id(id: String) -> Variant:
	_init_nodes()
	for n in ARTERIES:
		if n["id"] == id:
			return n
	for n in VEINS:
		if n["id"] == id:
			return n
	return null


## Screen point [x, y] of a node from pose slot arrays X, Y: lerp(slot -> to, t). (Arrays, not Vector2: doubles keep draw logs exact.)
static func anchor(n: Dictionary, X: PackedFloat32Array, Y: PackedFloat32Array) -> Array:
	var a: int = n["slot"]
	var b: int = n["to"] if n.get("to") != null else a
	var t: float = float(n.get("t", 0.0))
	return [X[a] + (X[b] - X[a]) * t, Y[a] + (Y[b] - Y[a]) * t]


## Arrival delay (s) per node: pathLen * pwvScale / pwv.
static func delays(pwv: float, pwv_scale: float, nodes: Array = []) -> PackedFloat64Array:
	_init_nodes()
	var v: float = pwv if pwv > 0.0 else PWV
	var m: float = pwv_scale if pwv_scale > 0.0 else PWV_SCALE
	var list: Array = nodes if not nodes.is_empty() else ARTERIES
	var out := PackedFloat64Array()
	for n in list:
		out.append(float(n["pathLen"]) * m / v)
	return out


static func cap_bpm(bpm: float) -> float:
	if not (bpm > 0.0):
		return 0.0
	return minf(BPM_MAX, bpm)


static func clamp01(x: float) -> float:
	return 0.0 if x < 0.0 else (1.0 if x > 1.0 else x)


const STILL := {"pulse": false, "bpm": 0.0, "stateK": 0.0, "periphK": 0.0, "headK": 0.0}


## Pulse state for a body. kind "vampire" never pulses. mode is a villager mode name (unknown = calm); blood = left/pool 0..1
## (default 1). Returns {pulse, bpm, stateK, periphK, headK}.
static func state(kind: String, mode: String, blood: Variant = null) -> Dictionary:
	if kind == "vampire":
		return STILL.duplicate()
	var m: Dictionary = MODES.get(mode, MODES["calm"])
	var f: float = 1.0 if blood == null else clamp01(float(blood))
	if m["bpm"] == 0.0 or f <= 0.0:
		return STILL.duplicate()
	var bpm: float
	if mode == "drinking":
		bpm = 50.0 + 70.0 * f
	elif f >= 0.4:
		bpm = m["bpm"] * (1.0 + 0.3 * (1.0 - f) / 0.6)
	else:
		bpm = m["bpm"] * 1.3 * (f / 0.4)
	return {"pulse": true, "bpm": cap_bpm(bpm), "stateK": m["stateK"] * pow(f, 1.5), "periphK": m["periphK"] * f, "headK": m["headK"]}


## Peak strength of one node's lub: w * (1 + hot) * stateK * lerp(1, periphK, periph) * (head ? headK : 1). Veins skip hot.
static func strength(n: Dictionary, st: Variant) -> float:
	if not (st is Dictionary) or not st.get("pulse", false):
		return 0.0
	var p: float = float(n.get("periph", 0.0))
	var per: float = 1.0 - p + p * float(st["periphK"])
	var k: float = float(n["w"]) if n["vein"] else float(n["w"]) * (1.0 + float(n["hot"]))
	return k * float(st["stateK"]) * per * (float(st["headK"]) if n["head"] else 1.0)


## Vessel model per body kind (vampire: anatomy only, never pulses).
static func for_body(kind: String) -> Dictionary:
	var vamp: bool = kind == "vampire"
	return {"kind": "vampire" if vamp else "villager", "nodes": all(), "pulse": not vamp, "blood": not vamp, "state": STILL.duplicate() if vamp else null}


## Arrival delays (s) for arteries and veins at pwvScale (cached): {art, vein, artMax, veinMax}.
static func travel(pwv_scale: float) -> Dictionary:
	_init_nodes()
	var m: float = pwv_scale if pwv_scale > 0.0 else PWV_SCALE
	var key := str(m)
	if _delay_cache.has(key):
		return _delay_cache[key]
	var art := delays(PWV, m, ARTERIES)
	var vein := delays(PWV, m, VEINS)
	var art_max := 0.0
	var vein_max := 0.0
	for i in vein.size():
		vein[i] = VEIN_LAG + vein[i] * VEIN_SLOW
	for d in art:
		art_max = maxf(art_max, d)
	for d in vein:
		vein_max = maxf(vein_max, d)
	var c := {"art": art, "vein": vein, "artMax": art_max, "veinMax": vein_max}
	_delay_cache[key] = c
	return c


## Envelope 0..1 at t s after arrival: smoothstep rise over attack, then exp decay with tau. 0 before arrival.
static func envelope(t: float, attack: float, tau: float) -> float:
	if not (t >= 0.0):
		return 0.0
	if t < attack:
		var k: float = t / attack
		return k * k * (3.0 - 2.0 * k)
	return exp(-(t - attack) / tau)


## Beat timing for a bpm: {dub, dubK, life, reduced}.
static func timing(bpm: float, reduced: bool = false, pwv_scale: float = 0.0) -> Dictionary:
	var b: float = cap_bpm(bpm) if bpm > 0.0 else REST_BPM
	if reduced:
		return {"dub": 0.0, "dubK": 0.0, "life": SOFT_ATTACK + 2.0 * SOFT_DECAY, "reduced": true}
	var dub: float = DUB_DELAY * minf(1.1, sqrt(REST_BPM / b))
	dub = minf(dub, 0.45 * 60.0 / b)
	var f: float = clamp01((b - DUB_FADE_BPM) / (BPM_MAX - DUB_FADE_BPM))
	var dub_k: float = DUB_K + (DUB_K_FAST - DUB_K) * f
	var tr := travel(pwv_scale)
	var art: float = tr["artMax"] + dub + ATTACK + LIFE_TAUS * DECAY
	var vein: float = tr["veinMax"] + VEIN_ATTACK + LIFE_TAUS * VEIN_DECAY
	return {"dub": dub, "dubK": dub_k, "life": maxf(art, vein), "reduced": false}


## Pulse 0..~1 of node index i (arteries or veins) at age s after the beat, for timing tm.
static func pulse(vein: bool, i: int, age: float, tm: Variant, pwv_scale: float = 0.0) -> float:
	if not (age >= 0.0) or not (tm is Dictionary) or age >= tm["life"]:
		return 0.0
	var left: float = tm["life"] - age
	var tail: float = (left / TAIL) * (left / TAIL) * (3.0 - 2.0 * left / TAIL) if left < TAIL else 1.0
	if tm["reduced"]:
		return envelope(age, SOFT_ATTACK, SOFT_DECAY) * tail
	var tr := travel(pwv_scale)
	if vein:
		return envelope(age - tr["vein"][i], VEIN_ATTACK, VEIN_DECAY) * tail
	var t: float = age - tr["art"][i]
	return (envelope(t, ATTACK, DECAY) + tm["dubK"] * envelope(t - tm["dub"], ATTACK, DECAY)) * tail


## The limb [root, end] slots when the node sits on an elbow/knee control slot, else [].
static func limb_of(n: Dictionary) -> Array:
	var to: Variant = n.get("to")
	if (to == null or to == n["slot"]) and float(n.get("t", 0.0)) == 0.0 and LIMB.has(n["slot"]):
		return LIMB[n["slot"]]
	return []


## Screen point of a node: anchor, except elbow/knee nodes sit on the limb curve midpoint.
static func point(n: Dictionary, X: PackedFloat32Array, Y: PackedFloat32Array) -> Array:
	var L := limb_of(n)
	if L.is_empty():
		return anchor(n, X, Y)
	var c: int = n["slot"]
	return [0.25 * X[L[0]] + 0.5 * X[c] + 0.25 * X[L[1]], 0.25 * Y[L[0]] + 0.5 * Y[c] + 0.25 * Y[L[1]]]


## Control point of the edge parent -> child when it runs along a limb curve: [true, x, y] else [false, 0, 0].
static func edge_ctrl(parent: Dictionary, child: Dictionary, X: PackedFloat32Array, Y: PackedFloat32Array) -> Array:
	var L := limb_of(child)
	if not L.is_empty() and parent["slot"] == L[0] and float(parent.get("t", 0.0)) == 0.0:
		return [true, 0.5 * (X[L[0]] + X[child["slot"]]), 0.5 * (Y[L[0]] + Y[child["slot"]])]
	L = limb_of(parent)
	if not L.is_empty() and child["slot"] == L[1] and float(child.get("t", 0.0)) == 0.0:
		return [true, 0.5 * (X[parent["slot"]] + X[L[1]]), 0.5 * (Y[parent["slot"]] + Y[L[1]])]
	return [false, 0.0, 0.0]


## Point [x, y] at s (0..1) on the edge a -> b (a, b: [x, y]; quadratic through ctrl [x, y] when has_ctrl, else straight).
static func edge_at(a: Array, has_ctrl: bool, ctrl: Array, b: Array, s: float) -> Array:
	if has_ctrl:
		var u: float = 1.0 - s
		return [u * u * a[0] + 2.0 * u * s * ctrl[0] + s * s * b[0], u * u * a[1] + 2.0 * u * s * ctrl[1] + s * s * b[1]]
	return [a[0] + (b[0] - a[0]) * s, a[1] + (b[1] - a[1]) * s]


## Edges of the artery (vein false) or vein tree as [{i: child index, p: parent index}] (cached).
static func edges(vein: bool) -> Array:
	_init_nodes()
	var key := "v" if vein else "a"
	if _edge_cache.has(key):
		return _edge_cache[key]
	var list: Array = VEINS if vein else ARTERIES
	var out: Array = []
	for i in list.size():
		if list[i]["parent"] == null:
			continue
		for j in list.size():
			if list[j]["id"] == list[i]["parent"]:
				out.append({"i": i, "p": j})
				break
	_edge_cache[key] = out
	return out


## Travelling highlight position on an edge: (age - dParent) / (dChild - dParent). < 0 not yet launched, > 1 passed.
static func edge_front(age: float, d_parent: float, d_child: float) -> float:
	var span: float = d_child - d_parent
	if not (span > 1e-6):
		return 1.0 if age >= d_parent else -1.0
	return (age - d_parent) / span
