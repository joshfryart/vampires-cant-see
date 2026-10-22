extends TestCase
## Schedule and Forge parity against tests/fixtures/schedule_forge.json (tools/golden/schedule_forge.mjs).
## Values are compared as JS-style JSON text (JsJson.stringify) so int/float spelling differences do not matter; looks
## are compared key by key with a 1e-12 tolerance where they hold doubles.

const EPS := 1e-12


func _t(v: Variant) -> String:
	return JsJson.stringify(v)


func _same(got: Variant, want: Variant, lbl: String) -> void:
	checks += 1
	if _t(got) != _t(want):
		failures.append("%s:\n   got  %s\n   want %s" % [lbl, _t(got).left(400), _t(want).left(400)])


func _near_deep(got: Variant, want: Variant, lbl: String) -> void:
	if want is Dictionary and got is Dictionary:
		eq(got.size(), want.size(), lbl + " size")
		for k in want:
			if not got.has(k):
				checks += 1
				failures.append("%s: missing key %s" % [lbl, k])
				continue
			_near_deep(got[k], want[k], lbl + "." + str(k))
	elif want is Array and got is Array:
		eq(got.size(), want.size(), lbl + " len")
		for i in mini(got.size(), want.size()):
			_near_deep(got[i], want[i], "%s[%d]" % [lbl, i])
	elif (want is float or want is int) and (got is float or got is int):
		near(float(got), float(want), EPS, lbl)
	else:
		eq(got, want, lbl)


func test_schedule_builds() -> void:
	var fx: Dictionary = load_fixture("schedule_forge")
	eq(Schedule.roles().keys().size(), fx["roles"].size(), "role count")
	var places: Dictionary = fx["places"]
	for b in fx["builds"]:
		var got: Variant = Schedule.build(b["role"], places, b["spawn"], Rng.new(float(b["seed"])), {"home": b["home"], "slot": b["slot"]})
		var lbl := "build %s home=%s slot=%s seed=%s" % [b["role"], str(b["home"]), str(b["slot"]), str(b["seed"])]
		eq(got == null, b["stops"] == null, lbl + " null-ness")
		if got != null and b["stops"] != null:
			_near_deep(got, b["stops"], lbl)


func test_schedule_helpers() -> void:
	var fx: Dictionary = load_fixture("schedule_forge")
	for m in fx["make"]:
		var got: Variant = Schedule.make(m["role"], fx["places"], null, Rng.new(5.0), {"home": "house1", "slot": 2})
		eq(got == null, m["res"] == null, "make %s null-ness" % m["role"])
		if got != null and m["res"] != null:
			_near_deep(got, m["res"], "make %s" % m["role"])
	var stops: Array = fx["stopAt"][fx["stopAt"].size() - 1]["stops"]
	for s in fx["stopAt"]:
		if s.has("stops"):
			continue
		var f: float = NAN if s["f"] == null else float(s["f"])
		eq(Schedule.stop_at(stops, f), int(s["res"]), "stopAt %s" % str(s["f"]))
		var idx: int = maxi(0, Schedule.stop_at(stops, f if is_finite(f) else 0.0))
		near(Schedule.eta(stops, idx, f if is_finite(f) else 0.0, 480.0), float(s["eta"]), 1e-9, "eta %s" % str(s["f"]))
	for s in fx["simplify"]:
		_same(Schedule.simplify(s["route"]), s["res"], "simplify")
	for s in fx["seated"]:
		eq(Schedule.is_seated(s["a"]), s["res"], "isSeated %s" % s["a"])
	for c in fx["chats"]:
		var got := Schedule.chat_roll(c["a"], c["b"], c["same"], float(c["r1"]), float(c["r2"]))
		eq(got["kind"], c["res"]["kind"], "chat %s %s same=%s r1=%s kind" % [c["a"], c["b"], str(c["same"]), str(c["r1"])])
		eq(got["mood"], c["res"]["mood"], "chat mood")
		near(float(got["sec"]), float(c["res"]["sec"]), 1e-12, "chat sec")


func test_forge_generate() -> void:
	var fx: Dictionary = load_fixture("schedule_forge")
	eq(Forge.list_ids(), fx["archIds"], "archetype ids")
	for g in fx["generates"]:
		var spec := {"archetype": g["id"]}
		if g["seed"] != null:
			spec["seed"] = g["seed"]
		if g["index"] == 1:
			spec["home"] = "h2"
		var got := Forge.generate(spec, {"stateSeed": float(g["stateSeed"]), "index": float(g["index"]), "accOffset": float(g["index"] + 2)})
		var lbl := "generate %s ss=%s i=%s seed=%s" % [g["id"], str(g["stateSeed"]), str(g["index"]), str(g["seed"])]
		eq(got["ok"], g["res"]["ok"], lbl + " ok")
		eq(got["code"], g["res"]["code"], lbl + " code")
		_near_deep(got["person"], g["res"]["person"], lbl)


func test_forge_legacy_and_overrides() -> void:
	var fx: Dictionary = load_fixture("schedule_forge")
	for l in fx["legacy"]:
		_near_deep(Forge.legacy_look(float(l["seed"]), float(l["id"]), float(l["off"])), l["look"], "legacy %s/%s/%s" % [str(l["seed"]), str(l["id"]), str(l["off"])])
	for o in fx["overrides"]:
		var got := Forge.generate(o["spec"], {"stateSeed": 5.0, "index": 2.0, "accOffset": 1.0})
		_near_deep(got["person"], o["res"]["person"], "overrides %s" % _t(o["spec"]).left(60))


func test_forge_validate() -> void:
	var fx: Dictionary = load_fixture("schedule_forge")
	for c in fx["validateLook"]:
		var got := Forge.validate("look", c["obj"], c["partial"])
		eq(got["ok"], c["res"]["ok"], "validate look '%s' ok" % c["key"])
		eq(got["code"], c["res"]["code"], "validate look '%s' code" % c["key"])
		_near_deep(got["value"], c["res"]["value"], "validate look '%s' value" % c["key"])
		eq(got["errors"], c["res"]["errors"], "validate look '%s' errors" % c["key"])
	for c in fx["validateOther"]:
		var got := Forge.validate(c["kind"], c["obj"])
		var lbl := "validate %s %s" % [c["kind"], _t(c["obj"]).left(50)]
		eq(got["ok"], c["res"]["ok"], lbl + " ok")
		eq(got["code"], c["res"]["code"], lbl + " code")
		if got["ok"] and c["res"]["ok"]:
			_near_deep(got["value"], c["res"]["value"], lbl + " value")


func test_forge_alter_and_reinforce() -> void:
	var fx: Dictionary = load_fixture("schedule_forge")
	for c in fx["alters"]:
		var got := Forge.alter(c["look"], c["patch"])
		eq(got["ok"], c["res"]["ok"], "alter '%s' ok" % c["key"])
		eq(got["code"], c["res"]["code"], "alter '%s' code" % c["key"])
		_near_deep(got["look"], c["res"]["look"], "alter '%s' look" % c["key"])
		eq(got["changed"], c["res"]["changed"], "alter '%s' changed" % c["key"])
	for c in fx["reinf"]:
		if c.has("bad"):
			ok(Forge.reinforcement(null) == null, "reinforcement null")
			continue
		var got: Variant = Forge.reinforcement({"fear": c["fear"], "fired": c["fired"], "night": c["night"], "runSeed": c["runSeed"]})
		eq(got == null, c["res"] == null, "reinforcement %s/%s null-ness" % [str(c["fear"]), str(c["fired"])])
		if got != null and c["res"] != null:
			eq(got["archetype"], c["res"]["archetype"], "reinforcement archetype")
			eq(int(got["seed"]), int(c["res"]["seed"]), "reinforcement seed")
			eq(got["card"], c["res"]["card"], "reinforcement card")


func test_forge_library() -> void:
	var fx: Dictionary = load_fixture("schedule_forge")
	Forge.reset_custom()
	var r: Array = fx["reg"]
	eq(Forge.register(fx["archGood"])["ok"], r[0]["res"]["ok"], "register good")
	eq(Forge.register(fx["archGood"].duplicate(true).merged({"id": "guard"}, true))["ok"], r[1]["res"]["ok"], "register builtin id")
	eq(Forge.list_ids(), r[2]["res"], "list after register")
	_near_deep(Forge.by_role("ratcatcher"), r[3]["res"], "byRole custom")
	var g := Forge.generate({"archetype": "ratcatcher", "seed": 9}, {"stateSeed": 3.0, "index": 1.0, "accOffset": 0.0})
	_near_deep(g["person"], r[4]["res"]["person"], "generate custom")
	eq(Forge.export_library().length() > 0, true, "export non-empty")
	eq(Forge.import_library(Forge.export_library())["ok"], r[6]["res"]["ok"], "import own export")
	eq(Forge.import_library("{nope")["code"], r[7]["res"]["code"], "import bad json")
	eq(Forge.import_library(" ".repeat(20000))["code"], r[8]["res"]["code"], "import too big")
	Forge.reset_custom()
