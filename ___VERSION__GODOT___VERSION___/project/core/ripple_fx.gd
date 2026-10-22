class_name RippleFx
extends RefCounted
## The rest of js/ripple.js beyond the boil table (core/ripple.gd): wobble, bands, wavy rings, mask strips, footstep rings and
## the secondary ring state (spawned where a wavefront strikes a person or marker).

const WOBBLE_DUR := 0.45
const WOBBLE_FREQ := 34.0
const BAND_DUR := 0.6
const BAND_OVER := 1.25


## Vibration -1..1 for a surface struck age seconds ago; 0 outside [0, WOBBLE_DUR).
static func wobble(age: float, phase: float = 0.0) -> float:
	if not (age >= 0.0) or age >= WOBBLE_DUR:
		return 0.0
	var k: float = 1.0 - age / WOBBLE_DUR
	return sin(age * WOBBLE_FREQ + phase) * k * k


## Normalised height (0..BAND_OVER) of the band front age seconds after a hit; -1 outside the window.
static func band_front(age: float) -> float:
	if not (age >= 0.0) or age >= BAND_DUR:
		return -1.0
	return (age / BAND_DUR) * BAND_OVER


## Brightness gain 0..1 of the band at normalised height u (0 feet .. 1 head).
static func band_gain(u: float, age: float) -> float:
	var f := band_front(age)
	if f < 0.0:
		return 0.0
	var d: float = (u - f) / 0.14
	return exp(-d * d) * (1.0 - age / BAND_DUR)


## Lateral wave -1..1 at normalised height u: zero above the front, decaying behind it.
static func wave(u: float, age: float) -> float:
	var f := band_front(age)
	if f < 0.0 or u > f:
		return 0.0
	var behind: float = f - u
	return sin(behind * 24.0) * exp(-behind * 3.2) * (1.0 - age / BAND_DUR)


## Jitter amplitude in internal px for a segment of the given length (0.4 base + ~1%, cap 1.5).
static func jitter_amp(length: float) -> float:
	var a: float = 0.4 + 0.01 * (length if length > 0.0 else 0.0)
	return 1.5 if a > 1.5 else a


## Ring radius with a slight wave: R * (1 + amp * sin(k * theta + t)).
static func wavy_radius(r: float, theta: float, t: float, k: float = 6.0, amp: float = 0.04) -> float:
	return r * (1.0 + amp * sin((k if k != 0.0 else 6.0) * theta + t))


## Split a figure (height 0..z_top) into horizontal strips by lit band: Array of [zLow, zHigh, alpha] (0..3 entries).
static func mask_strips(z_min: float, z_max: float, z_top: float, soft: float) -> Array:
	var s: float = soft if soft > 0.0 else 0.12
	var lo: float = maxf(0.0, minf(z_min, z_max))
	var hi: float = minf(z_top, maxf(z_min, z_max))
	var out: Array = []
	var add := func(a: float, b: float, al: float) -> void:
		var za: float = maxf(0.0, a)
		var zb: float = minf(z_top, b)
		if zb - za < 1e-4 or al < 0.02:
			return
		out.append([za, zb, al])
	add.call(lo - s, lo, Ripple.mask_alpha(lo - s / 2.0, z_min, z_max, s))
	add.call(lo, hi, 1.0)
	add.call(hi, hi + s, Ripple.mask_alpha(hi + s / 2.0, z_min, z_max, s))
	return out


## Floor footstep ring k (0..2): radius in cells at pulse age, or -1 when not visible.
static func foot_ring(age: float, fade: float, rng_: float, k: int) -> float:
	var u: float = age / fade - k * 0.2
	if not (u > 0.0) or u >= 1.0:
		return -1.0
	return rng_ * (0.3 + 0.7 * sqrt(u))


## Alpha 0..1 of floor footstep ring k at pulse age.
static func foot_ring_alpha(age: float, fade: float, k: int) -> float:
	var u: float = age / fade - k * 0.2
	if not (u > 0.0) or u >= 1.0:
		return 0.0
	return pow(1.0 - u, 1.5) * (1.0 - k * 0.22)


## Secondary ring state: Array of Dictionary {x, y, t0, kind, maxR, life, strength, delay, inward, minR}.
class Rings:
	extends RefCounted
	var rings: Array = []
	var max_rings: int = 16

	func spawn(x: float, y: float, t: float, o: Dictionary = {}) -> Dictionary:
		var ring := {
			"x": x, "y": y, "t0": t, "kind": o.get("kind", "marker"), "maxR": float(o.get("maxR", 1.0)),
			"life": float(o["life"]) if o.get("life") != null and float(o["life"]) > 0.0 else 0.7,
			"strength": float(o.get("strength", 1.0)), "delay": float(o.get("delay", 0.0)), "inward": o.get("inward", false) == true,
			"minR": float(o["minR"]) if o.get("minR") != null and float(o["minR"]) >= 0.0 else 0.15,
		}
		rings.append(ring)
		while rings.size() > max_rings:
			rings.pop_front()
		return ring

	## Ring radius in cells at time t (0 before it starts, maxR at the end; inward rings shrink maxR to minR).
	static func radius(ring: Dictionary, t: float) -> float:
		var f: float = (t - float(ring["t0"]) - float(ring["delay"])) / float(ring["life"])
		if ring["inward"]:
			var c: float = clampf(f, 0.0, 1.0)
			var mn: float = float(ring["minR"])
			return mn + (float(ring["maxR"]) - mn) * (1.0 - c)
		return maxf(0.0, f) * float(ring["maxR"])

	## Ring alpha 0..strength at time t.
	static func alpha(ring: Dictionary, t: float) -> float:
		var f: float = (t - float(ring["t0"]) - float(ring["delay"])) / float(ring["life"])
		if f < 0.0 or f >= 1.0:
			return 0.0
		return float(ring["strength"]) * pow(1.0 - f, 1.5)

	func prune(t: float) -> void:
		rings = rings.filter(func(r): return t <= float(r["t0"]) + float(r["delay"]) + float(r["life"]))
