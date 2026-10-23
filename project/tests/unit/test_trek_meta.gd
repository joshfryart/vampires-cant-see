extends TestCase
## TrekMeta (roguelike meta) and the vcs.rogue / vcs.trek save kinds.


func _store() -> SaveCodec.Store:
	return SaveCodec.create(SaveCodec.MemoryStorage.new())


func _trek() -> Dictionary:
	return {"v": 1, "seed": 12345, "stage": "cave", "leg": 2, "miles": 3.5, "progress": 0.25, "heat": 1.0, "night": null, "hunger": null, "unlocksUsed": ["second_coffin"], "deathsAvoided": 1}


func test_data_shape() -> void:
	var n := 0
	for u in TrekMeta._d()["upgrades"]:
		n += 1
		eq((u["tiers"] as Array).size(), (u["costs"] as Array).size(), "tiers/costs %s" % u["id"])
		ok(TrekMeta._d()["EFFECT_DEFAULTS"].has(u["effect"]), "default for %s" % u["effect"])
		ok(TrekMeta._d()["EFFECT_LIMITS"].has(u["effect"]), "limits for %s" % u["effect"])
		for r in u["requires"]:
			ok(TrekMeta.unlock_by_id(r["id"]) != null and int(r["tier"]) <= TrekMeta.max_tier(r["id"]), "prereq of %s" % u["id"])
	eq(n, 21, "21 unlocks")
	for k in Meta._d()["EFFECT_DEFAULTS"]:
		ok(TrekMeta.effects(TrekMeta.create()).has(k), "classic fx key %s" % k)


func test_rogue_round_trip() -> void:
	var m := TrekMeta.create()
	m["soil"] = 77
	m["unlocks"]["far_echo"] = 2
	m["reached"] = ["cave", "road"]
	m["stats"]["bestMiles"] = 12.5
	var s := _store()
	ok(s.write("rogue", 1, m)["ok"], "write")
	eq(s.has("rogue"), true, "has")
	var r := s.read("rogue")
	ok(r["ok"], "read")
	var mg := TrekMeta.migrate(r["v"], r["data"])
	ok(mg["ok"], "migrate")
	deep(TrekMeta.sanitize(mg["data"]), m, "meta round trip")
	ok(SaveCodec.validate_rogue(r["data"], r["v"])["ok"], "codec validates")
	eq(SaveCodec.Store.key_of("rogue"), "vcs.rogue", "rogue key")
	eq(SaveCodec.Store.key_of("trek"), "vcs.trek", "trek key")
	eq(SaveCodec.Store.key_of("run"), "vcs.run", "run key")
	eq(SaveCodec.Store.key_of("meta"), "vcs.meta", "meta key")
	eq(SaveCodec.Store.key_of("nope"), "", "unknown key")


func test_trek_round_trip() -> void:
	var t := _trek()
	var s := _store()
	ok(s.write("trek", 1, t)["ok"], "write")
	var r := s.read("trek")
	ok(r["ok"], "read")
	var v := SaveCodec.validate_trek(r["data"], r["v"])
	ok(v["ok"], "validates")
	deep(SaveCodec.sanitize_trek(r["data"]), t, "trek round trip")
	ok(not SaveCodec.check(s.read_text("trek"), "rogue")["ok"], "kind mismatch rejected")


func test_tamper_and_checksum() -> void:
	var m := TrekMeta.create()
	var text := SaveCodec.wrap_text("rogue", 1, m)
	ok(SaveCodec.check(text, "rogue")["ok"], "clean text ok")
	var bad := text.replace("\"soil\":0", "\"soil\":999")
	eq(SaveCodec.check(bad, "rogue")["code"], "E_SAVE_CHECKSUM", "tampered soil rejected")
	var ttext := SaveCodec.wrap_text("trek", 1, _trek())
	eq(SaveCodec.check(ttext.replace("\"leg\":2", "\"leg\":9"), "trek")["code"], "E_SAVE_CHECKSUM", "tampered trek rejected")
	eq(SaveCodec.check("{not json", "trek")["code"], "E_SAVE_PARSE", "garbage rejected")


func test_size_cap() -> void:
	var t := _trek()
	t["night"] = {"pad": "x".repeat(70000)}
	var s := _store()
	eq(s.write("trek", 1, t)["code"], "E_SAVE_TOO_BIG", "write over 64 KB refused")
	eq(SaveCodec.check("x".repeat(65537), "rogue")["code"], "E_SAVE_TOO_BIG", "read over 64 KB refused")


func test_codec_exact_keys() -> void:
	var m := TrekMeta.create()
	ok(SaveCodec.sanitize_rogue(m) != null, "valid rogue")
	var extra := m.duplicate(true)
	extra["bonus"] = 1
	eq(SaveCodec.sanitize_rogue(extra), null, "extra rogue key")
	var missing := m.duplicate(true)
	missing.erase("reached")
	eq(SaveCodec.sanitize_rogue(missing), null, "missing rogue key")
	var bad_stat := m.duplicate(true)
	bad_stat["stats"]["deaths"]["sun"] = -1
	eq(SaveCodec.sanitize_rogue(bad_stat), null, "negative death count")
	var bad_stat2 := m.duplicate(true)
	bad_stat2["stats"]["extra"] = 1
	eq(SaveCodec.sanitize_rogue(bad_stat2), null, "extra stat key")
	var t := _trek()
	t["extra"] = 1
	eq(SaveCodec.sanitize_trek(t), null, "extra trek key")
	t = _trek()
	t["seed"] = -1
	eq(SaveCodec.sanitize_trek(t), null, "negative seed")
	t = _trek()
	t["stage"] = ""
	eq(SaveCodec.sanitize_trek(t), null, "empty stage")
	t = _trek()
	t["progress"] = "a"
	eq(SaveCodec.sanitize_trek(t), null, "non numeric progress")
	eq(SaveCodec.migrate_rogue(2, m)["code"], "E_SAVE_VERSION", "future rogue version")
	eq(SaveCodec.migrate_trek(2, _trek())["code"], "E_SAVE_VERSION", "future trek version")
	eq(SaveCodec.migrate_rogue(0, m)["code"], "E_SAVE_SCHEMA", "v0 rogue")


func test_sanitize_repairs() -> void:
	eq(TrekMeta.sanitize(null), null, "null")
	eq(TrekMeta.sanitize({"v": 2}), null, "wrong version")
	var bad := {"v": 1, "soil": -5, "unlocks": {"far_echo": 99, "bogus": 3, "soft_step": -2, "deep_draw": "x"}, "stats": {"treks": "a", "bestMiles": -1, "deaths": {"sun": 2.7, "holy": -1, "evil": 5}}, "reached": ["a", "a", 7, ""], "legacyImported": "yes"}
	var s: Dictionary = TrekMeta.sanitize(bad)
	eq(s["soil"], 0, "soil floor")
	eq(s["unlocks"]["far_echo"], 3, "tier clamped to max")
	ok(not s["unlocks"].has("bogus"), "unknown dropped")
	eq(s["unlocks"]["soft_step"], 0, "negative tier")
	eq(s["unlocks"]["deep_draw"], 0, "bad tier")
	eq(s["stats"]["treks"], 0, "bad stat")
	eq(s["stats"]["bestMiles"], 0.0, "bad miles")
	eq(s["stats"]["deaths"]["sun"], 2, "death floored")
	eq(s["stats"]["deaths"]["holy"], 0, "death negative")
	eq(s["reached"], ["a"], "reached cleaned")
	eq(s["legacyImported"], false, "flag must be true bool")
	ok(SaveCodec.sanitize_rogue(s) != null, "repaired data passes codec")
	var big: Dictionary = TrekMeta.sanitize({"v": 1, "soil": 1e15})
	eq(big["soil"], TrekMeta.MAX_SOIL, "soil capped")


func test_migrate() -> void:
	var m := TrekMeta.create()
	deep(TrekMeta.migrate(1, m)["data"], m, "v1 identity")
	eq(TrekMeta.migrate(2, m)["code"], "E_SAVE_VERSION", "future")
	eq(TrekMeta.migrate("x", m)["code"], "E_SAVE_SCHEMA", "bad v")
	eq(TrekMeta.migrate(1, 5)["code"], "E_SAVE_SCHEMA", "bad data")


func test_buy_rules() -> void:
	var m := TrekMeta.create()
	eq(TrekMeta.buy(m, "nope")["code"], "E_META_UNKNOWN", "unknown")
	eq(TrekMeta.buy(m, "far_echo")["code"], "E_META_POOR", "poor")
	eq(m["soil"], 0, "poor leaves soil")
	m["soil"] = 1000
	var r := TrekMeta.buy(m, "far_echo")
	ok(r["ok"], "buy t1")
	eq(r["cost"], 8, "t1 cost")
	eq(m["soil"], 992, "soil spent")
	eq(TrekMeta.tier_of(m, "far_echo"), 1, "tier 1")
	eq(TrekMeta.buy(m, "far_echo")["cost"], 20, "t2 cost")
	TrekMeta.buy(m, "far_echo")
	TrekMeta.buy(m, "far_echo")
	eq(TrekMeta.tier_of(m, "far_echo"), 3, "tier 3")
	eq(TrekMeta.buy(m, "far_echo")["code"], "E_META_MAX", "max tier")
	eq(TrekMeta.buy(m, "thrall")["code"], "E_META_LOCKED", "thrall locked")
	eq(TrekMeta.buy(m, "bat_form")["code"], "E_META_LOCKED", "bat form needs quick call 2")
	TrekMeta.buy(m, "quick_call")
	eq(TrekMeta.buy(m, "bat_form")["code"], "E_META_LOCKED", "tier 1 not enough")
	TrekMeta.buy(m, "quick_call")
	ok(TrekMeta.buy(m, "bat_form")["ok"], "bat form unlocked")
	eq(TrekMeta.max_tier("bat_form"), 1, "single tier")
	eq(TrekMeta.buy(m, "bat_form")["code"], "E_META_MAX", "single tier max")
	var poor := TrekMeta.create()
	eq(TrekMeta.buy(poor, "thrall")["code"], "E_META_LOCKED", "locked reported first")


func test_soil_formula() -> void:
	eq(TrekMeta.soil_for_run({"miles": 10.9, "humans": 0, "critters": 0, "unseen": 0, "newBest": false}), 10, "miles floor")
	eq(TrekMeta.soil_for_run({"miles": 4.2, "humans": 3, "critters": 5, "unseen": 2, "newBest": true}), 4 + 6 + 2 + 6 + 5, "all terms")
	eq(TrekMeta.soil_for_run({}), 0, "empty")
	eq(TrekMeta.soil_for_run(null), 0, "null")
	var m := TrekMeta.create()
	var st := {"miles": 100, "humans": 0, "critters": 0, "unseen": 0, "newBest": false}
	eq(TrekMeta.soil_for_run(st, m), 100, "no pouch")
	m["unlocks"]["soil_pouch"] = 1
	eq(TrekMeta.soil_for_run(st, m), 110, "+10%")
	m["unlocks"]["soil_pouch"] = 2
	eq(TrekMeta.soil_for_run(st, m), 120, "+20%")
	eq(TrekMeta.soil_for_run({"miles": 7}, m), 8, "floor after multiplier")


func test_record_run() -> void:
	var m := TrekMeta.create()
	var e := TrekMeta.record_run(m, {"miles": 3.7, "humans": 2, "critters": 3, "unseen": 1, "stageIndex": 2, "reached": ["cave", "wild"], "death": "sun"})
	eq(e, 3 + 4 + 1 + 3 + 5, "earned with new best")
	eq(m["soil"], e, "soil added")
	eq(m["stats"]["treks"], 1, "treks")
	eq(m["stats"]["bestStage"], 2, "best stage")
	near(m["stats"]["bestMiles"], 3.7, 1e-9, "best miles")
	eq(m["stats"]["deaths"]["sun"], 1, "death recorded")
	eq(m["stats"]["fedHumans"], 2, "humans")
	eq(m["stats"]["fedCritters"], 3, "critters")
	eq(m["stats"]["soilEarned"], e, "earned total")
	eq(m["reached"], ["cave", "wild"], "reached")
	var e2 := TrekMeta.record_run(m, {"miles": 1, "stageIndex": 2, "reached": ["wild", "road"], "death": "staked"})
	eq(e2, 1, "no new best bonus")
	eq(m["reached"], ["cave", "wild", "road"], "reached merged")
	near(m["stats"]["bestMiles"], 3.7, 1e-9, "best miles kept")
	eq(m["stats"]["deaths"]["staked"], 1, "staked")
	eq(TrekMeta.record_run(m, {"miles": 2, "stageIndex": 1}), 2, "survived run, no death")
	ok(SaveCodec.sanitize_rogue(m) != null, "recorded meta is codec valid")
	eq(TrekMeta.record_run(null, {}), 0, "null meta")


func test_legacy_import_once() -> void:
	var m := TrekMeta.create()
	var classic := Meta.create()
	classic["essence"] = 42
	eq(TrekMeta.import_legacy_essence(m, classic), 42, "imported 1:1")
	eq(m["soil"], 42, "soil")
	ok(m["legacyImported"], "flag set")
	eq(TrekMeta.import_legacy_essence(m, classic), 0, "second import is a no-op")
	eq(m["soil"], 42, "soil unchanged")
	eq(classic["essence"], 42, "classic untouched")
	var m2 := TrekMeta.create()
	eq(TrekMeta.import_legacy_essence(m2, null), 0, "no classic meta")
	ok(not m2["legacyImported"], "flag not set without classic meta")
	eq(TrekMeta.import_legacy_essence(m2, {"essence": "x"}), 0, "junk essence")
	var m3 := TrekMeta.create()
	eq(TrekMeta.import_legacy_essence(m3, Meta.create()), 0, "zero essence adds nothing")
	ok(m3["legacyImported"], "flag set even for zero essence")


func test_effects_mapping() -> void:
	var m := TrekMeta.create()
	var base := TrekMeta.effects(m)
	var classic_base := Meta.effects(Meta.create(), [], [])
	for k in classic_base:
		near(base[k], classic_base[k], 1e-9, "default %s matches classic" % k)
	m["unlocks"]["far_echo"] = 2
	m["unlocks"]["full_veins"] = 3
	m["unlocks"]["soft_step"] = 1
	m["unlocks"]["thick_blood"] = 3
	m["unlocks"]["second_coffin"] = 1
	m["unlocks"]["soil_pouch"] = 2
	var fx := TrekMeta.effects(m)
	near(fx["sonarRange"], 1.3, 1e-9, "far_echo t2")
	near(fx["startBlood"], 30.0, 1e-9, "full_veins t3")
	near(fx["noise"], 0.85, 1e-9, "soft_step t1")
	near(fx["bloodMax"], 30.0, 1e-9, "thick_blood")
	near(fx["secondCoffin"], 1.0, 1e-9, "second coffin")
	near(fx["soilMul"], 0.2, 1e-9, "soil pouch")
	var capped := TrekMeta.effects(m, [{"effect": "sonarRange", "op": "mul", "value": 10}, {"effect": "bloodNow", "op": "add", "value": 5}])
	near(capped["sonarRange"], 2.5, 1e-9, "limit applied")
	ok(not capped.has("bloodNow"), "bloodNow ignored")
	var all := TrekMeta.create()
	for id in all["unlocks"]:
		all["unlocks"][id] = TrekMeta.max_tier(id)
	var af := TrekMeta.effects(all)
	for k in af:
		var lim: Array = TrekMeta._d()["EFFECT_LIMITS"][k]
		ok(af[k] >= lim[0] and af[k] <= lim[1], "max tier %s within limits" % k)
