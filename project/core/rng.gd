class_name Rng
extends RefCounted
## Ports mulberry32 from js/people.js (also meta.js, hunger.js, forge.js, game.js).
## All arithmetic is mod 2^32 on non-negative ints, matching JS `>>> 0` / Math.imul bit for bit.

var a: int = 0


## seed may be any JS number; it is reduced like `seed >>> 0`.
func _init(seed: float = 0.0) -> void:
	a = JsMath.u32(seed)


## Next float in [0, 1).
func next() -> float:
	a = (a + 0x6D2B79F5) & JsMath.M32
	var t: int = a
	t = JsMath.imul(t ^ (t >> 15), t | 1)
	t = (t ^ (t + JsMath.imul(t ^ (t >> 7), t | 61))) & JsMath.M32
	return float((t ^ (t >> 14)) & JsMath.M32) / 4294967296.0
