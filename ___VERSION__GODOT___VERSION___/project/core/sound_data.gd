class_name SoundData
extends RefCounted
## Ports the non-acoustics parts of js/data/sounds.js: level rows, villager step scaling, room profiles, mix.

const FALLBACK_LEVEL := {"range": 3.0, "strength": 0.3, "bounces": 0, "gain": 0.1}


## Level row for a sound kind (js level() in game.js), with the same safe fallback.
static func level(kind: String) -> Dictionary:
	var lv: Dictionary = GameData.sounds()["levels"]
	return lv[kind] if lv.has(kind) else FALLBACK_LEVEL


## Multipliers {range, strength, fade, gain} for one villager step (js SoundData.stepScale).
static func step_scale(gait: String, floor_mat: String, pace: float) -> Dictionary:
	var t: Dictionary = GameData.sounds()["stepScaleTable"]
	var g: Dictionary = t["gait"][gait] if t["gait"].has(gait) else t["gait"]["walk"]
	var f: Dictionary = t["floor"][floor_mat] if t["floor"].has(floor_mat) else t["floor"]["stone"]
	var k: float = pace if is_finite(pace) else 1.0
	k = 0.8 if k < 0.8 else (1.25 if k > 1.25 else k)
	return {
		"range": float(g["range"]) * float(f["range"]) * k,
		"strength": float(g["strength"]) * float(f["strength"]) * k,
		"fade": float(g["fade"]) * float(f["fade"]),
		"gain": float(g["gain"]) * float(f["gain"]) * k,
	}


## Room profile {rangeMul, bounceCap, fadeMul} for a world kind (js roomProfile).
static func room_profile(kind: String) -> Dictionary:
	var rooms: Dictionary = GameData.sounds()["rooms"]
	var r: Dictionary = rooms[kind] if rooms.has(kind) else rooms["indoor"]
	return {"rangeMul": float(r["rangeMul"]), "bounceCap": int(r["bounceCap"]), "fadeMul": float(r["fadeMul"])}


## Mix multiplier for a sound kind: mixOther, or 1 for exempt kinds.
static func mix_for(kind: String) -> float:
	var sd := GameData.sounds()
	if sd["mixExempt"].has(kind) and sd["mixExempt"][kind] == true:
		return 1.0
	var k: Variant = sd["mixOther"]
	return float(k) if k is float or k is int else 1.0
