extends TestCase
## JsJson parity against tests/fixtures/jsjson.json (tools/golden/jsjson.mjs): JS Number->string for 6000 doubles
## (shortest round-trip digits) and JSON.stringify of nested values, compact and indented.


func _bits_to_double(hex: String) -> float:
	var b := PackedByteArray()
	b.resize(8)
	var hi: int = ("0x" + hex.substr(0, 8)).hex_to_int()
	var lo: int = ("0x" + hex.substr(8, 8)).hex_to_int()
	b.encode_s64(0, (hi << 32) | lo)
	return b.decode_double(0)


func test_number_strings() -> void:
	var fx: Dictionary = load_fixture("jsjson")
	var bad := 0
	for p in fx["nums"]:
		var v := _bits_to_double(p[0])
		var got := JsJson.num_to_string(v)
		if got != p[1]:
			bad += 1
			if bad <= 8:
				failures.append("number %s: got %s want %s" % [p[0], got, p[1]])
		checks += 1
	if bad > 8:
		failures.append("... %d numbers mismatched in total" % bad)


func test_stringify_values() -> void:
	var fx: Dictionary = load_fixture("jsjson")
	var i := 0
	for c in fx["json"]:
		i += 1
		# Dictionaries parsed by Godot keep file order; the generator wrote JS key order, so a re-stringify must agree.
		eq(JsJson.stringify(c["value"]), c["compact"], "value %d compact" % i)
		eq(JsJson.stringify(c["value"], 2), c["pretty"], "value %d pretty" % i)
