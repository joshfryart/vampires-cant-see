extends TestCase
## Meta parity against tests/fixtures/meta.json (tools/golden/meta.mjs). Compared as JS-style JSON text so ints and floats
## that print the same count as equal.

const EPS := 1e-9


func _t(v: Variant) -> String:
	return JsJson.stringify(v)


func test_sanitize() -> void:
	var fx: Dictionary = load_fixture("meta")
	for c in fx["sanitize"]:
		var got: Variant = Meta.sanitize(c["obj"])
		eq(got == null, c["res"] == null, "sanitize '%s' null-ness" % c["key"])
		if got != null and c["res"] != null:
			eq(_t(got), _t(c["res"]), "sanitize '%s'" % c["key"])


func test_migrate() -> void:
	var fx: Dictionary = load_fixture("meta")
	for c in fx["migrate"]:
		var got := Meta.migrate(c["v"], c["data"])
		eq(got["ok"], c["res"]["ok"], "migrate '%s' ok" % c["key"])
		eq(got["code"] if got["code"] != "" else null, c["res"]["code"], "migrate '%s' code" % c["key"])
		if got["ok"]:
			eq(_t(got["data"]), _t(c["res"]["data"]), "migrate '%s' data" % c["key"])


func test_buy() -> void:
	var fx: Dictionary = load_fixture("meta")
	for run in fx["buy"]:
		var m := Meta.create()
		m["essence"] = float(run.get("start", 4))
		for step in run["steps"]:
			var r := Meta.buy(m, step["id"])
			eq(r["ok"], step["res"]["ok"], "buy %s ok" % step["id"])
			eq(r["code"], step["res"]["code"], "buy %s code" % step["id"])
			if step.has("cost"):
				var c := Meta.cost_of(m, step["id"])
				eq(c if c >= 0 else null, step["cost"], "cost after %s" % step["id"])
				eq(Meta.tier_of(m, step["id"]), int(step["tier"]), "tier after %s" % step["id"])
			near(float(m["essence"]), float(step["essence"]), EPS, "essence after %s" % step["id"])


func test_record_run() -> void:
	var fx: Dictionary = load_fixture("meta")
	var m := Meta.create()
	var i := 0
	for step in fx["runs"]:
		var earned := Meta.record_run(m, step["run"])
		eq(earned, int(step["earned"]), "run %d earned" % i)
		eq(Meta.essence_for(step["run"]), int(step["essenceFor"]), "run %d essenceFor" % i)
		eq(_t(m["stats"]), _t(step["meta"]["stats"]), "run %d stats" % i)
		near(float(m["essence"]), float(step["meta"]["essence"]), EPS, "run %d essence" % i)
		i += 1


func test_effects() -> void:
	var fx: Dictionary = load_fixture("meta")
	var i := 0
	for c in fx["effects"]:
		var got := Meta.effects(c["meta"], c["boons"], c["extra"])
		eq(got.size(), c["fx"].size(), "effects %d size" % i)
		for k in c["fx"]:
			near(float(got[k]), float(c["fx"][k]), 1e-12, "effects %d %s" % [i, k])
		i += 1


func test_roll_boons() -> void:
	var fx: Dictionary = load_fixture("meta")
	for c in fx["rolls"]:
		eq(Meta.roll_boons(float(c["seed"]), c["taken"]), c["res"], "roll seed %s" % str(c["seed"]))
