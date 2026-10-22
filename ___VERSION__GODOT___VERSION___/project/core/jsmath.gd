class_name JsMath
extends RefCounted
## JS-faithful number helpers. Logic code uses plain float (64-bit) and int, never Vector2/3.

const M32: int = 0xFFFFFFFF
const TWO_PI: float = PI * 2.0


## JS Math.round: halves round toward +Infinity.
static func round_js(x: float) -> float:
	return floor(x + 0.5)


## JS `x >>> 0` for a number: truncate, wrap into [0, 2^32).
static func u32(x: float) -> int:
	var t: float = floor(x) if x >= 0.0 else ceil(x)
	return int(fposmod(t, 4294967296.0))


## JS Math.imul as an unsigned 32-bit result (same low bits as the signed JS value).
## Inputs must be in [0, 2^32). The int64 product wraps mod 2^64, so the low 32 bits stay exact.
static func imul(a: int, b: int) -> int:
	return (a * b) & M32


## JS `%` (sign follows the dividend), same as fmod.
static func mod_js(a: float, b: float) -> float:
	return fmod(a, b)
