class_name Ambient
extends RefCounted
## Ambient sound emitters (drips, ripples, draft, wind, crickets, owl, creek, fountain, hearth) as ordinary Sonar.emit_sound calls.
## Emitters are placed anchors {cell: [x, y], kind}. Each has its own period; it only fires while the player is within the kind's
## "within" cells (default 12). Budget: at most MAX_LIVE live ambient pulses, and at most MAX_RAYS rays cast per step
## (one 180-ray drip fits, so at most one drip per step). Deterministic: all randomness comes from the Rng passed to step().
## Opts for Ambient.new: {"kinds": Dictionary (default data/rogue/ambient.json), "drip_ear": range multiplier for drip and ripple (default 1.0)}.

const MAX_LIVE := 4
const MAX_RAYS := 180
const DEFAULT_WITHIN := 12.0
const DATA_PATH := "res://data/rogue/ambient.json"

static var _kinds_cache: Dictionary = {}

var emitters: Array = []  # {cx, cy, kind, next (NAN = unscheduled)}
var kinds: Dictionary = {}
var drip_ear: float = 1.0
var clock: float = 0.0
var live: Array[Sonar.Pulse] = []
## Counters for tests and diagnostics.
var emitted: int = 0
var skipped_budget: int = 0


static func load_kinds() -> Dictionary:
	if _kinds_cache.is_empty():
		var f := FileAccess.open(DATA_PATH, FileAccess.READ)
		if f != null:
			var d: Variant = JSON.parse_string(f.get_as_text())
			if d is Dictionary and d.get("kinds") is Dictionary:
				_kinds_cache = d["kinds"]
	return _kinds_cache


func _init(anchors: Array = [], opts: Dictionary = {}) -> void:
	kinds = opts["kinds"] if opts.get("kinds") is Dictionary else load_kinds()
	drip_ear = maxf(0.1, float(opts.get("drip_ear", 1.0)))
	for a in anchors:
		add(a)


## anchor: {cell: [x, y] (or cx, cy), kind}. Unknown kinds are ignored. Returns whether it was added.
func add(anchor: Dictionary) -> bool:
	var kind: String = str(anchor.get("kind", ""))
	if not kinds.has(kind):
		return false
	var c: Variant = anchor.get("cell")
	var cx: int = int(c[0]) if c is Array and c.size() >= 2 else int(anchor.get("cx", 0))
	var cy: int = int(c[1]) if c is Array and c.size() >= 2 else int(anchor.get("cy", 0))
	emitters.append({"cx": cx, "cy": cy, "kind": kind, "next": NAN})
	return true


func set_drip_ear(mul: float) -> void:
	drip_ear = maxf(0.1, mul)


func live_count(sonar: Sonar) -> int:
	_prune_live(sonar)
	return live.size()


func _prune_live(sonar: Sonar) -> void:
	var keep: Array[Sonar.Pulse] = []
	for p in live:
		if clock - p.t0 <= p.range / p.speed + p.fade and sonar.pulses.has(p):
			keep.append(p)
	live = keep


func _period(k: Dictionary, rng: Rng) -> float:
	var per: Array = k.get("period", [4.0, 8.0])
	var lo: float = maxf(0.05, float(per[0]))
	var hi: float = maxf(lo, float(per[1]))
	var r1: float = rng.next()
	var r2: float = rng.next()
	return maxf(0.05, (lo + (hi - lo) * r1) * (1.0 + float(k.get("jitter", 0.0)) * (r2 * 2.0 - 1.0)))


## Advance dt seconds. player_pos is in cells. t < 0 uses the internal clock (sum of dt), else t is the sonar time to stamp pulses with.
## Returns the number of pulses emitted this step.
func step(world, sonar: Sonar, player_pos: Vector2, dt: float, rng: Rng, t: float = -1.0) -> int:
	clock = clock + dt if t < 0.0 else t
	sonar.protect_last = true
	_prune_live(sonar)
	var rays_used := 0
	var made := 0
	for e in emitters:
		var k: Dictionary = kinds[e["kind"]]
		if is_nan(e["next"]):
			# Random phase so emitters placed together do not fire in unison.
			e["next"] = clock + _period(k, rng) * rng.next()
			continue
		if clock < e["next"]:
			continue
		var x: float = e["cx"] + 0.5
		var y: float = e["cy"] + 0.5
		var within: float = float(k.get("within", DEFAULT_WITHIN))
		var rays: int = int(k.get("visRays", 90))
		if Vector2(x, y).distance_to(player_pos) > within:
			# Out of earshot: skip this beat (no catch-up burst) and reschedule.
			e["next"] = clock + _period(k, rng)
			continue
		if live.size() >= MAX_LIVE or rays_used + rays > MAX_RAYS:
			# Over budget: stays due and retries next step.
			skipped_budget += 1
			continue
		var mul: float = drip_ear if (e["kind"] == "drip" or e["kind"] == "ripple") else 1.0
		var p := sonar.emit_sound(world, x, y, clock, {
			"kind": e["kind"], "range": float(k.get("range", 3.0)) * mul, "strength": float(k.get("strength", 0.3)),
			"z": float(k.get("z", 0.0)), "fade": float(k.get("fade", 1.2)), "visRays": rays, "bounces": int(k.get("bounces", 0)),
		})
		e["next"] = clock + _period(k, rng)
		if p != null:
			live.append(p)
			rays_used += rays
			made += 1
			emitted += 1
	return made
