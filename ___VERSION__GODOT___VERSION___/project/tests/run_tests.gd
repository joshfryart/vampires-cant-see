extends SceneTree
## Headless test runner. Usage:
##   godot --headless --path project -s res://tests/run_tests.gd -- --filter=rng
## Finds tests/**/test_*.gd (extends TestCase), runs test_* methods, prints one JSON summary line,
## exits 1 on any failure.


func _init() -> void:
	var filter := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--filter="):
			filter = a.substr(9)
	var files: Array[String] = []
	_collect("res://tests", files)
	files.sort()
	var ran := 0
	var checks := 0
	var failed: Array[String] = []
	for path in files:
		if filter != "" and path.find(filter) < 0:
			continue
		var script: GDScript = load(path)
		if script == null:
			failed.append("%s: failed to load" % path)
			continue
		for m in script.get_script_method_list():
			var mname: String = m["name"]
			if not mname.begins_with("test_"):
				continue
			var t: TestCase = script.new()
			t.call(mname)
			ran += 1
			checks += t.checks
			for f in t.failures:
				failed.append("%s::%s %s" % [path.get_file(), mname, f])
	print(JSON.stringify({"tests": ran, "checks": checks, "failed": failed.size(), "failures": failed}))
	quit(1 if failed.size() > 0 else 0)


func _collect(dir: String, out: Array[String]) -> void:
	for d in DirAccess.get_directories_at(dir):
		_collect(dir + "/" + d, out)
	for f in DirAccess.get_files_at(dir):
		if f.begins_with("test_") and f.ends_with(".gd"):
			out.append(dir + "/" + f)
