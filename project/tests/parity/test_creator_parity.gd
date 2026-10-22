extends TestCase
## Character creator logic against tests/fixtures/creator.json (tools/golden/creator.mjs from tools/character-creator-core.js):
## sanitize, set_field, the field table, Forge presets, seeded randomize, pose echoes, views, export / import and list helpers.
## Compared deeply with key sets and a 1e-9 tolerance on numbers (key order is irrelevant).

const EPS := 1e-9


func _deep(got: Variant, want: Variant, lbl: String) -> void:
	checks += 1
	if want is Dictionary:
		if not (got is Dictionary):
			failures.append("%s: want dict, got %s" % [lbl, str(got).left(120)])
			return
		var wk: Array = want.keys()
		var gk: Array = got.keys()
		wk.sort()
		gk.sort()
		if wk != gk:
			failures.append("%s: keys got %s want %s" % [lbl, str(gk).left(200), str(wk).left(200)])
			return
		for k in want:
			_deep(got[k], want[k], lbl + "." + str(k))
	elif want is Array:
		if not (got is Array) or got.size() != want.size():
			failures.append("%s: array size got %s want %d" % [lbl, str(got).left(160) if got is Array else str(got), want.size()])
			return
		for i in want.size():
			_deep(got[i], want[i], "%s[%d]" % [lbl, i])
	elif (want is float or want is int) and (got is float or got is int):
		if absf(float(got) - float(want)) > EPS:
			failures.append("%s: got %s want %s" % [lbl, str(got), str(want)])
	elif want == null:
		if got != null:
			failures.append("%s: want null, got %s" % [lbl, str(got).left(120)])
	elif got != want:
		failures.append("%s: got %s want %s" % [lbl, str(got).left(120), str(want).left(120)])


## Clock-stamped "saved" values (Date.now when none was given) differ per run: zero those over 1e12 on both sides.
func _nostamp(v: Variant) -> Variant:
	if v is Dictionary:
		var d: Dictionary = (v as Dictionary).duplicate()
		for k in d:
			if k == "saved" and (d[k] is float or d[k] is int) and float(d[k]) > 1.0e12:
				d[k] = 0
			else:
				d[k] = _nostamp(d[k])
		return d
	if v is Array:
		var a: Array = []
		for x in v:
			a.append(_nostamp(x))
		return a
	return v


func test_fields_and_archetypes() -> void:
	var fx: Dictionary = load_fixture("creator")
	var f := Creator.fields()
	_deep(f, fx["fields"], "fields")
	_deep(Creator.archetypes(), fx["archetypes"], "archetypes")


func test_sanitize() -> void:
	var fx: Dictionary = load_fixture("creator")
	var i := 0
	for c in fx["sanitize"]:
		_deep(Creator.sanitize(c["in"]), c["out"], "sanitize[%d]" % i)
		i += 1
	for c in fx["sanitizeBase"]:
		_deep(Creator.sanitize(c["in"], c["base"]), c["out"], "sanitizeBase")


func test_set_field() -> void:
	var fx: Dictionary = load_fixture("creator")
	var look: Dictionary = Creator.sanitize({})["look"]
	for c in fx["setField"]:
		look = Creator.set_field(look, c["key"], c["value"])
		_deep(look, c["look"], "setField %s" % c["key"])
	for pair in fx["getField"]:
		_deep(Creator.get_field(look, pair[0]), pair[1], "getField " + pair[0])
	for pair in fx["hairHidden"]:
		eq(Creator.hair_hidden(pair[0]), pair[1], "hairHidden")


func test_presets() -> void:
	var fx: Dictionary = load_fixture("creator")
	for c in fx["presets"]:
		_deep(Creator.preset(c["id"], c["seed"]), c["look"], "preset %s/%s" % [str(c["id"]), str(c["seed"])])


func test_randomize() -> void:
	var fx: Dictionary = load_fixture("creator")
	var i := 0
	for c in fx["randomize"]:
		var r := Creator.randomize(c["base"], c["mode"], c["locks"], Rng.new(float(c["seed"])))
		_deep(r, c["out"], "randomize[%d] %s %s" % [i, c["mode"], str(c["locks"])])
		i += 1


func test_pose_echo_and_views() -> void:
	var fx: Dictionary = load_fixture("creator")
	var lk: Dictionary = Creator.preset("innkeeper", 5)
	for c in fx["poseEcho"]:
		_deep(Creator.pose_echo(c["pose"], lk, c["opts"]), c["out"], "poseEcho %s %s" % [c["pose"], str(c["opts"])])
	for c in fx["views"]:
		_deep(Creator.sanitize_view(c["in"]), c["out"], "view")


func test_characters_json_and_lists() -> void:
	var fx: Dictionary = load_fixture("creator")
	var a := Creator.character("Alice  the <b>Baker</b>", Creator.preset("patron", 2), {"archetype": "patron", "seed": 2, "saved": 1000})
	var b := Creator.character("", {"height": 0.7, "body": "pear"}, {"saved": 2000})
	var c := Creator.character("x".repeat(50), {}, {"seed": 99999, "saved": 3000, "archetype": "BAD"})
	_deep([a, b, c], fx["characters"], "characters")
	_deep(JSON.parse_string(Creator.export_json(a)), JSON.parse_string(fx["exportOne"]), "exportOne")
	_deep(JSON.parse_string(Creator.export_json([a, b, c, 5, null])), JSON.parse_string(fx["exportMany"]), "exportMany")
	for ic in fx["importCases"]:
		_deep(_nostamp(Creator.import_json(ic["text"])), _nostamp(ic["out"]), "import " + str(ic["text"]).left(30))
	var list: Array = []
	list = Creator.upsert(list, a)
	list = Creator.upsert(list, b)
	var a2 := a.duplicate()
	a2["name"] = "alice  the baker"
	a2["seed"] = 5
	list = Creator.upsert(list, a2)
	_deep(list, fx["upsert"], "upsert")
	_deep(Creator.remove(list, "UNNAMED"), fx["remove"], "remove")
	_deep([Creator.find(list, "ALICE THE BAKER"), Creator.find(list, "zz")], fx["find"], "find")
	_deep([Creator.free_name(list, "Unnamed"), Creator.free_name(list, "Fresh"), Creator.free_name(list, "alice the baker")], fx["freeName"], "freeName")
	var specs: Array = []
	for x in [a, b, c, null, {"height": 1}]:
		specs.append([x, Creator.to_spec(x)])
	_deep(specs, fx["toSpec"], "toSpec")
	_deep([["  a\u0001b  c ", Creator.clean_name("  a\u0001b  c ")], [5, Creator.clean_name(5)], ["<>", Creator.clean_name("<>")]], fx["cleanName"], "cleanName")
