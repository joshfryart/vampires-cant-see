class_name Checks
extends RefCounted
## Ports the idea of js/checks.js: boot checks of what the game needs. Browser features do not apply, so these check the Godot
## equivalents: the data files, the baked audio manifest, a writable user folder and the shaders. Required failures stop the
## game on the error screen; optional ones become title notices. Every result is logged.

const REQUIRED_DATA := ["maps", "sounds", "upgrades", "hunger", "voices", "archetypes"]
const SHADERS := ["res://render/shaders/sonar_wall.gdshader", "res://render/shaders/sonar_floor.gdshader", "res://render/shaders/postfx_grade.gdshader", "res://render/shaders/postfx_overlay.gdshader"]


## Run all checks. Returns [{id, ok, required, message}].
static func run() -> Array:
	var out: Array = []
	for name in REQUIRED_DATA:
		var ok := true
		var d: Variant = GameData.get_json(name)
		if d == null or (d is Dictionary and (d as Dictionary).is_empty()):
			ok = false
		out.append({"id": "data." + name, "ok": ok, "required": true, "message": "data/%s.json loaded" % name if ok else "data/%s.json missing or empty" % name})
	var man := FileAccess.open("res://audio/manifest.json", FileAccess.READ)
	var man_ok := man != null and man.get_length() > 100
	out.append({"id": "audio.manifest", "ok": man_ok, "required": false, "message": "audio manifest present" if man_ok else "audio manifest missing: the game runs silent"})
	var probe := "user://.vcs_write_probe"
	var w := FileAccess.open(probe, FileAccess.WRITE)
	var wr_ok := w != null
	if w != null:
		w.store_string("ok")
		w.close()
		DirAccess.remove_absolute(ProjectSettings.globalize_path(probe))
	out.append({"id": "storage.user", "ok": wr_ok, "required": false, "message": "user folder writable" if wr_ok else "Progress cannot be saved: the user folder is not writable"})
	var sh_ok := true
	for s in SHADERS:
		if not ResourceLoader.exists(s):
			sh_ok = false
	out.append({"id": "render.shaders", "ok": sh_ok, "required": true, "message": "shaders present" if sh_ok else "a shader file is missing"})
	return out


## Log the results; returns {ok (all required passed), notices (messages of failed optional checks), failed (first required message)}.
static func report(results: Array) -> Dictionary:
	var ok := true
	var notices: Array = []
	var failed := ""
	for r in results:
		var text := "%s: %s" % [r["id"], r["message"]]
		if r["ok"]:
			Log.debug("checks", text)
		elif r["required"]:
			Log.error("checks", text)
			ok = false
			if failed == "":
				failed = r["message"]
		else:
			Log.warn("checks", text)
			notices.append(r["message"])
	return {"ok": ok, "notices": notices, "failed": failed}
