extends TestCase
## mulberry32 parity against tests/fixtures/rng.json (tools/golden/rng.mjs).


func test_streams_match_js_exactly() -> void:
	var fx: Dictionary = load_fixture("rng")
	for s in fx["streams"]:
		var r := Rng.new(float(s["seed"]))
		var out: Array = s["out"]
		for i in out.size():
			eq(int(r.next() * 4294967296.0), int(out[i]), "seed %s draw %d" % [str(s["seed"]), i])


func test_non_uint32_seeds_reduce_like_js() -> void:
	var fx: Dictionary = load_fixture("rng")
	for s in fx["odd"]:
		var r := Rng.new(float(s["seed"]))
		var out: Array = s["out"]
		for i in out.size():
			eq(int(r.next() * 4294967296.0), int(out[i]), "odd seed %s draw %d" % [str(s["seed"]), i])
