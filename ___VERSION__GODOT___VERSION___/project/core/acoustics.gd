class_name Acoustics
extends RefCounted
## Ports the functions of SoundData.acoustics in js/data/sounds.js (the numbers come from data/sounds.json).
## Phase 1 subset: beam, vis_factor, mat_of, rough_of, echo_level, game_amp, person_amp.

const EPS := 1e-9

static var _a: Dictionary = {}


static func a() -> Dictionary:
	if _a.is_empty():
		_a = GameData.sounds()["acoustics"]
	return _a


static func _log10(x: float) -> float:
	return log(x) / log(10.0)


## Mouth beam B(theta) in dB, symmetric, linear between nodes (sounds.js A.beam).
static func beam(theta: float) -> float:
	var ac := a()
	var ang: float = fmod(absf(theta), JsMath.TWO_PI)
	if ang > PI:
		ang = JsMath.TWO_PI - ang
	var step: float = ac["beamStepDeg"]
	var k: float = ((ang * 180.0) / PI) / step
	var t: Array = ac["beamDb"]
	var i: int = mini(t.size() - 2, int(floor(k + EPS)))
	return float(t[i]) + (float(t[i + 1]) - float(t[i])) * (k - i)


## Visual brightness factor 0.15..1 for a level in dB (sounds.js A.visFactor).
static func vis_factor(db: float) -> float:
	var ac := a()
	return clampf(1.0 + db / float(ac["visDb"]), float(ac["visMin"]), 1.0)


static func mat_of(name: String) -> Dictionary:
	var m: Dictionary = a()["mat"]
	return m[name] if m.has(name) else m["stone"]


static func rough_of(name: String) -> float:
	return float(mat_of(name)["rough"])


## Echo level in dB for kind "wall" / "prop" / "person" (sounds.js A.echoLevel).
static func echo_level(kind: String, r_cells: float, theta: float, mat: String = "") -> float:
	var ac := a()
	var r: float = maxf(r_cells * float(ac["cellM"]), float(ac["rMin"]))
	var air: float = 2.0 * r * float(ac["airDbPerM"])
	var l: float = beam(theta)
	if kind == "wall":
		var m := mat_of(mat)
		l += -float(ac["spread"]["wall"]) * _log10(2.0 * r) + 10.0 * _log10((1.0 - float(m["alpha"])) * (1.0 - float(m["s"]))) - air
	else:
		var ts: float = float(ac["ts"]["person"]) if kind == "person" else float(ac["ts"]["prop"])
		l += -float(ac["spread"]["object"]) * _log10(r) + ts - air
	return l


## Game amplitude 0..1 for a level in dB (sounds.js A.gameAmp).
static func game_amp(db: float) -> float:
	var ac := a()
	var ref: float = ac["gameRefDb"]
	return clampf(pow(10.0, (float(ac["gameKappa"]) * (db - ref)) / 20.0), float(ac["gameMin"]), 1.0)


static func person_amp(r_cells: float, theta: float) -> float:
	return game_amp(echo_level("person", r_cells, theta) + float(a()["personGainDb"]))
