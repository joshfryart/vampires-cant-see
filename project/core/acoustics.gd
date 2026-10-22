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


## Floor-bounce level (dB): image source at the eye height, floor material loss, softer by floor.db and floor.absDb x alpha.
static func floor_level(mat: String) -> float:
	var f: Dictionary = a()["floor"]
	return echo_level("wall", float(f["eyeM"]) / float(a()["cellM"]), 0.0, mat) + float(f["db"]) - float(f["absDb"]) * float(mat_of(mat)["alpha"])


## Floor-bounce amplitude 0..1; 0 below floor.minAmp.
static func floor_amp(mat: String) -> float:
	var amp: float = game_amp(floor_level(mat))
	return 0.0 if amp < float(a()["floor"]["minAmp"]) else amp


## Ceiling of a zone/map name: {h metres above the floor, mat}.
static func ceiling_for(zone_name: String) -> Dictionary:
	var ac := a()
	var zones: Dictionary = ac["zone"]
	var has: bool = zone_name != "" and zones.has(zone_name)
	var mats: Dictionary = ac["ceilMat"]
	return {
		"h": float(zones[zone_name]["h"]) if has else float(ac["ceil"]["defaultH"]),
		"mat": mats[zone_name] if zone_name != "" and mats.has(zone_name) else ac["ceil"]["defaultMat"],
	}


static func ceil_level(h: float, mat: String) -> float:
	var ac := a()
	var c: Dictionary = ac["ceil"]
	var gap: float = maxf(h - float(ac["floor"]["eyeM"]), 0.3)
	return echo_level("wall", gap / float(ac["cellM"]), 0.0, mat) + float(c["db"]) - float(c["absDb"]) * float(mat_of(mat)["alpha"])


static func ceil_amp(h: float, mat: String) -> float:
	var amp: float = game_amp(ceil_level(h, mat))
	return 0.0 if amp < float(a()["ceil"]["minAmp"]) else amp


## Ceiling-bounce delay (s), kept clear of the floor bounce.
static func ceil_delay(h: float) -> float:
	var ac := a()
	var fl: Dictionary = ac["floor"]
	var d: float = (float(fl["delay"]) * maxf(h - float(fl["eyeM"]), 0.3)) / float(fl["eyeM"])
	if absf(d - float(fl["delay"])) < float(ac["ceil"]["minGap"]):
		return float(fl["delay"]) + float(ac["ceil"]["minGap"])
	return d


static func prop_amp(r_cells: float, theta: float) -> float:
	var amp: float = game_amp(echo_level("prop", r_cells, theta))
	return 0.0 if amp < float(a()["propEcho"]["minAmp"]) else amp


## Per-ping reverb send multiplier from enclosure (js A.wetFor).
static func wet_for(hit_frac: float, mean_alpha: float, scatterers: float, indoor: bool) -> float:
	var w: Dictionary = a()["wet"]
	var h: float = clampf(hit_frac, 0.0, 1.0)
	var enc: float = 0.5 + 0.5 * h if indoor else 0.9 * h
	var v: float = float(w["gain"]) * enc * (1.0 - float(w["absorb"]) * clampf(mean_alpha, 0.0, 1.0)) + float(w["scatter"]) * minf(maxf(scatterers, 0.0), float(w["scatterMax"])) + float(w["base"])
	return clampf(v, float(w["min"]), float(w["max"]))


## Sabine RT60 = 0.161 V / A for a box w x d cells of height h metres and mean absorption alpha, clamped (js A.sabine).
static func sabine(w: float, d: float, h: float, alpha: float) -> float:
	var ac := a()
	var ww: float = w * float(ac["cellM"])
	var dd: float = d * float(ac["cellM"])
	var v: float = ww * dd * h
	var s: float = 2.0 * (ww * dd + (ww + dd) * h)
	return clampf((0.161 * v) / (s * alpha), float(ac["t60Min"]), float(ac["t60Max"]))


## Reverb T60 (s) for a zone/map name; unknown names use the kind default.
static func t60_for(zone_name: String, kind: String) -> float:
	var ac := a()
	var zones: Dictionary = ac["zone"]
	if zone_name != "" and zones.has(zone_name):
		var z: Dictionary = zones[zone_name]
		return sabine(float(z["w"]), float(z["d"]), float(z["h"]), float(z["alpha"]))
	return float(ac["t60Outdoor"]) if kind == "outdoor" else float(ac["t60Indoor"])


static func comb_gain(tau: float, t60: float) -> float:
	var ac := a()
	return pow(10.0, (-3.0 * tau) / clampf(t60, float(ac["t60Min"]), float(ac["t60Max"])))


## Maekawa diffraction loss (dB) for path difference delta (m) at hz (js A.maekawa).
static func maekawa(delta: float, hz: float) -> float:
	var ac := a()
	var lam: float = float(ac["c"]) / (hz if hz != 0.0 else float(ac["maekawaHz"]))
	var n: float = maxf(0.0, (2.0 * delta) / lam)
	return minf(float(ac["maekawaCapDb"]), 10.0 * _log10(3.0 + 20.0 * n))


## Transmission loss (dB at 500 Hz) of a material, composite with its gap fraction when it has one.
static func tl_of(mat_name: String) -> float:
	var m := mat_of(mat_name)
	if not m.has("gap") or float(m["gap"]) == 0.0:
		return float(m["tl500"])
	var gap: float = m["gap"]
	return -10.0 * _log10((1.0 - gap) * pow(10.0, -float(m["tl500"]) / 10.0) + gap)


## Occlusion of a blocking material, optionally with a doorway diffraction loss (dB, NAN when none).
## Returns {loss, gain, lpHz, peakHz, peakDb, diffracted}.
static func occlusion(mat_name: String, diff_db: float = NAN) -> Dictionary:
	var ac := a()
	var m := mat_of(mat_name)
	var tl: float = tl_of(mat_name)
	var diff: bool = not is_nan(diff_db) and is_finite(diff_db) and diff_db < tl
	var loss: float = diff_db if diff else tl
	return {
		"loss": loss,
		"gain": maxf(float(ac["occMin"]), pow(10.0, (-float(ac["occK"]) * loss) / 20.0)),
		"lpHz": float(ac["occCutoffHz"]) * pow(10.0, -loss / 40.0),
		"peakHz": 0.0 if diff else float(m.get("peakHz", 0.0)),
		"peakDb": 0.0 if diff else float(m.get("peakDb", 0.0)),
		"diffracted": diff,
	}


## Repetition-pitch comb for a reflector r cells away: {tau, gain} or empty beyond rp.maxM.
static func repetition(r_cells: float) -> Dictionary:
	var ac := a()
	var r: float = r_cells * float(ac["cellM"])
	if not (r > 0.0) or r > float(ac["rp"]["maxM"]):
		return {}
	return {"tau": (2.0 * r) / float(ac["c"]), "gain": 0.5}
