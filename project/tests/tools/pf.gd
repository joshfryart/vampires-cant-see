extends RefCounted
## Tiny static accumulator used by the profiling scenario (perf_play) and temporary instrumentation: PF.add(key, usec), PF.cnt(key, n).
## Reference from game code with: const PF = preload("res://tests/tools/pf.gd")

static var us: Dictionary = {}
static var n: Dictionary = {}


static func add(key: String, usec: int) -> void:
	us[key] = int(us.get(key, 0)) + usec
	n[key] = int(n.get(key, 0)) + 1


static func cnt(key: String, k: int = 1) -> void:
	n[key] = int(n.get(key, 0)) + k


static func reset() -> void:
	us.clear()
	n.clear()
