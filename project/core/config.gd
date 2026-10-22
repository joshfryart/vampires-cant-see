class_name Config
extends RefCounted
## Ports js/config.js: the settings schema, validation of untrusted settings and the settings file (user://settings.json).

const PATH := "user://settings.json"
const MAX_CHARS := 16 * 1024
const FORBIDDEN_KEYS := ["__proto__", "constructor", "prototype"]
const CFG_V := 2

const DEFAULTS := {
	"mouseSensitivity": 0.0025, "invertMouse": false, "moveSpeed": 3.0, "turnSpeedKeys": 2.4, "renderScale": 1.0, "volume": 0.7,
	"nightLengthMin": 4.0, "cfgV": 2.0, "showFps": false, "fovDeg": 66.0, "sonarSpeed": 12.0, "sonarRange": 10.0, "sonarFade": 3.0,
	"sonarCooldown": 0.8, "headBob": true, "lineBoil": true, "transitionMs": 700.0, "materialDetail": true, "maxMapW": 64.0,
	"maxMapH": 48.0, "feedReach": 1.5, "feedArcDeg": 60.0, "poolMin": 30.0, "poolMax": 50.0, "dazedTime": 3.0, "autosaveSec": 20.0,
	"keyTurnSpeed": 3.2, "dragLook": true, "feedToggle": false, "reduceMotion": false, "edgeVignette": true, "largeText": false,
	"ambienceGain": 0.6, "pingBip": false, "devButton": true, "subtitles": true, "translation": true, "villagerVoices": true, "effects": 2.0,
}

## key -> [type, min, max] (type "number" or "boolean"; min/max only for numbers).
const SCHEMA := {
	"mouseSensitivity": ["number", 0.0005, 0.01], "invertMouse": ["boolean"], "moveSpeed": ["number", 1.0, 6.0],
	"turnSpeedKeys": ["number", 0.5, 5.0], "renderScale": ["number", 0.25, 1.0], "volume": ["number", 0.0, 1.0],
	"nightLengthMin": ["number", 2.0, 30.0], "cfgV": ["number", 0.0, 99.0], "showFps": ["boolean"], "fovDeg": ["number", 50.0, 100.0],
	"sonarSpeed": ["number", 4.0, 30.0], "sonarRange": ["number", 4.0, 20.0], "sonarFade": ["number", 1.0, 8.0],
	"sonarCooldown": ["number", 0.2, 3.0], "headBob": ["boolean"], "lineBoil": ["boolean"], "transitionMs": ["number", 200.0, 2000.0],
	"materialDetail": ["boolean"], "maxMapW": ["number", 1.0, 64.0], "maxMapH": ["number", 1.0, 48.0], "feedReach": ["number", 1.0, 3.0],
	"feedArcDeg": ["number", 20.0, 120.0], "poolMin": ["number", 5.0, 100.0], "poolMax": ["number", 5.0, 150.0],
	"dazedTime": ["number", 0.5, 10.0], "autosaveSec": ["number", 5.0, 300.0], "keyTurnSpeed": ["number", 1.0, 6.0],
	"dragLook": ["boolean"], "feedToggle": ["boolean"], "reduceMotion": ["boolean"], "edgeVignette": ["boolean"], "largeText": ["boolean"],
	"ambienceGain": ["number", 0.0, 1.0], "pingBip": ["boolean"], "devButton": ["boolean"], "subtitles": ["boolean"],
	"translation": ["boolean"], "villagerVoices": ["boolean"], "effects": ["number", 0.0, 2.0],
}


static func defaults_copy() -> Dictionary:
	return DEFAULTS.duplicate()


## Validate an untrusted settings object: {config, warnings}. Never throws.
static func sanitize(obj: Variant) -> Dictionary:
	var config := defaults_copy()
	var warnings: Array = []
	if not (obj is Dictionary):
		warnings.append("Settings are not an object; using defaults")
		return {"config": config, "warnings": warnings}
	for key in obj:
		if FORBIDDEN_KEYS.has(str(key)):
			warnings.append("Setting \"%s\" is not allowed; ignored" % key)
			continue
		if not SCHEMA.has(key):
			warnings.append("Unknown setting \"%s\"; ignored" % key)
			continue
		var rule: Array = SCHEMA[key]
		var value: Variant = obj[key]
		if rule[0] == "number":
			if not (value is float or value is int) or not is_finite(float(value)):
				warnings.append("Setting \"%s\" should be number; using default" % key)
				continue
			var f := float(value)
			if f < float(rule[1]) or f > float(rule[2]):
				warnings.append("Setting \"%s\" is outside %s to %s; using default" % [key, str(rule[1]), str(rule[2])])
				continue
			config[key] = f
		else:
			if not (value is bool):
				warnings.append("Setting \"%s\" should be boolean; using default" % key)
				continue
			config[key] = value
	return {"config": config, "warnings": warnings}


## Load the saved settings (defaults on any problem). safe_mode ignores the file.
static func load_file(path: String = PATH, safe_mode: bool = false) -> Dictionary:
	if safe_mode:
		return defaults_copy()
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return defaults_copy()
	var raw := f.get_as_text()
	if raw.length() > MAX_CHARS:
		return defaults_copy()
	var parsed: Variant = JSON.parse_string(raw)
	var res := sanitize(parsed)
	var cfg: Dictionary = res["config"]
	var had_v: bool = parsed is Dictionary and (parsed.get("cfgV") is float or parsed.get("cfgV") is int) and float(parsed["cfgV"]) >= float(DEFAULTS["cfgV"])
	if not had_v:
		# v2 migration: the night-length default changed
		cfg["nightLengthMin"] = DEFAULTS["nightLengthMin"]
		cfg["cfgV"] = DEFAULTS["cfgV"]
		save_file(cfg, path)
	return cfg


static func save_file(config: Dictionary, path: String = PATH) -> bool:
	var res := sanitize(config)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JsJson.stringify(res["config"]))
	return true
