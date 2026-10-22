extends TestCase
## Save codec parity against tests/fixtures/save.json (tools/golden/save.mjs): checksums, stored texts written by the JS
## store, byte-exact envelope text, tampering, import, run migrate/sanitize, tab lock, and the file store round trip.


func test_checksums() -> void:
	var fx: Dictionary = load_fixture("save")
	for c in fx["sums"]:
		eq(SaveCodec.checksum(c["s"]), c["sum"], "checksum of %s" % JsJson.stringify(c["s"]).left(30))


func test_check_stored_texts() -> void:
	var fx: Dictionary = load_fixture("save")
	for c in fx["texts"]:
		var r := SaveCodec.check(c["text"], c["kind"])
		eq(r["ok"], c["ok"], "text '%s' ok (code %s)" % [c["key"], str(r.get("code"))])
		if not c["ok"]:
			eq(r["code"], c["code"], "text '%s' code" % c["key"])


func test_wrap_text_is_byte_exact() -> void:
	var fx: Dictionary = load_fixture("save")
	var old := SaveCodec.game_version
	SaveCodec.game_version = fx["game"]
	for w in fx["wraps"]:
		eq(SaveCodec.wrap_text(w["kind"], int(w["v"]), w["data"]), w["text"], "wrap %s" % w["kind"])
	SaveCodec.game_version = old


func test_import() -> void:
	var fx: Dictionary = load_fixture("save")
	for c in fx["impCases"]:
		var r := SaveCodec.parse_import(c["text"])
		eq(r["ok"], c["ok"], "import '%s' ok (code %s)" % [c["key"], str(r.get("code"))])
		if not c["ok"]:
			eq(r["code"], c["code"], "import '%s' code" % c["key"])
		else:
			eq(int(r["meta"]["v"]), int(c["metaV"]), "import '%s' meta v" % c["key"])
			eq(JsJson.stringify(r["meta"]["data"]), JsJson.stringify(c["metaData"]), "import '%s' meta data" % c["key"])
			eq(r["run"] != null, c["runV"] != null, "import '%s' has run" % c["key"])


func test_run_migrate_and_sanitize() -> void:
	var fx: Dictionary = load_fixture("save")
	for c in fx["runCases"]:
		if c.get("needsForge", false) and not FileAccess.file_exists("res://core/forge.gd"):
			continue
		var m := SaveCodec.migrate_run(c["v"], c["data"])
		eq(m["ok"], c["migOk"], "run '%s' migrate ok" % c["key"])
		if not c["migOk"]:
			eq(m["code"], c["migCode"], "run '%s' migrate code" % c["key"])
		else:
			var s: Variant = SaveCodec.sanitize_run(m["data"])
			eq(s == null, c["san"] == null, "run '%s' sanitize result" % c["key"])
			if s != null and c["san"] != null:
				eq(JsJson.stringify(s), JsJson.stringify(c["san"]), "run '%s' sanitized text" % c["key"])
		var v := SaveCodec.validate_run(c["data"], c["v"])
		eq(v["ok"], c["valOk"], "run '%s' validate ok" % c["key"])
		if not c["valOk"]:
			eq(v["code"], c["valCode"], "run '%s' validate code" % c["key"])


func test_tab_lock() -> void:
	var fx: Dictionary = load_fixture("save")
	var mem := SaveCodec.MemoryStorage.new()
	var i := 0
	for step in fx["tab"]:
		var lbl: String = step["op"]
		if i == 1:
			SaveCodec.tab_lock(mem, "b", 1000.0)
		match i:
			0: eq(SaveCodec.tab_check(mem, "a", 1000.0), step["res"], lbl)
			1: eq(SaveCodec.tab_check(mem, "a", 5000.0), step["res"], lbl)
			2: eq(SaveCodec.tab_check(mem, "b", 5000.0), step["res"], lbl)
			3: eq(SaveCodec.tab_check(mem, "a", 20000.0), step["res"], lbl)
			4: eq(SaveCodec.tab_check(mem, "a", -20000.0), step["res"], lbl)
		i += 1


func test_store_round_trip_and_backup() -> void:
	var fx: Dictionary = load_fixture("save")
	var mem := SaveCodec.MemoryStorage.new()
	var store := SaveCodec.create(mem)
	ok(store.persistent, "memory storage probes as usable")
	var w := store.write("meta", 1, fx["metaData"])
	ok(w["ok"], "write meta")
	var r := store.read("meta")
	ok(r["ok"], "read meta back")
	eq(r["source"], "main", "read from main")
	eq(JsJson.stringify(r["data"]), JsJson.stringify(fx["metaData"]), "data survives a round trip")
	# second write rotates the first to .bak; corrupting main then reads the backup and repairs main
	var data2: Dictionary = (fx["metaData"] as Dictionary).duplicate(true)
	data2["essence"] = 99
	ok(store.write("meta", 1, data2)["ok"], "second write")
	mem.set_item("vcs.meta", "garbage")
	var rb := store.read("meta")
	ok(rb["ok"], "falls back to the backup")
	eq(rb["source"], "bak", "source is bak")
	eq(int(rb["data"]["essence"]), 37, "backup holds the previous save")
	eq(store.read("meta")["source"], "main", "main repaired from the backup")
	# JS-written texts load unchanged, and export -> import is lossless
	mem.set_item("vcs.run", fx["texts"][1]["text"])
	var rr := store.read("run")
	ok(rr["ok"], "JS run text loads")
	var exp := SaveCodec.export_text(store)
	var imp := SaveCodec.parse_import(exp)
	ok(imp["ok"], "export text imports (%s)" % str(imp.get("code")))
	ok(imp["run"] != null, "export carries the run")
	store.remove("meta")
	ok(not store.has("meta"), "removed")
