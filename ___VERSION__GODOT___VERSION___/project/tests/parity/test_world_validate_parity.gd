extends TestCase
## World validation parity against tests/fixtures/world_validate.json (tools/golden/world_validate.mjs): the same
## error codes, maps and location fields as js/world.js validate / validateAll, in the same order.


func _norm(v: Variant) -> Variant:
	if v is float and floor(v) == v:
		return int(v)
	return v


func _check(got: Dictionary, want: Dictionary, lbl: String) -> void:
	eq(got["ok"], want["ok"], lbl + " ok")
	var ge: Array = got["errors"]
	var we: Array = want["errors"]
	eq(ge.size(), we.size(), lbl + " error count (got %s)" % str(ge.map(func(e): return e["code"])))
	for i in mini(ge.size(), we.size()):
		var g: Dictionary = ge[i]
		var w: Dictionary = we[i]
		eq(g["code"], w["code"], "%s error %d code" % [lbl, i])
		eq(g["map"], w["map"], "%s error %d map" % [lbl, i])
		for k in ["row", "col", "door", "path", "segment", "hide", "char"]:
			eq(_norm(g.get(k)), _norm(w.get(k)), "%s error %d %s" % [lbl, i, k])


func test_single_maps() -> void:
	var fx: Dictionary = load_fixture("world_validate")
	for c in fx["cases"]:
		var got := WorldValidate.validate(c["def"], c["names"], c["links"], c["opts"])
		_check(got, c["res"], "case '%s'" % c["key"])


func test_whole_graphs() -> void:
	var fx: Dictionary = load_fixture("world_validate")
	for c in fx["all"]:
		var got := WorldValidate.validate_all(c["data"])
		_check(got, c["res"], "graph '%s'" % c["key"])
		if c["data"].get("startMap") is String and c["data"]["maps"].has(c["data"]["startMap"]):
			eq(WorldValidate.reachable(c["data"], c["data"]["startMap"]), c["reach"], "graph '%s' reachable" % c["key"])
