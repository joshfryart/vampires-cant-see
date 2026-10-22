extends TestCase


func test_round_js_halves_go_up() -> void:
	eq(JsMath.round_js(0.5), 1.0, "0.5")
	eq(JsMath.round_js(-0.5), 0.0, "-0.5 (JS gives -0, equal to 0)")
	eq(JsMath.round_js(-1.5), -1.0, "-1.5")
	eq(JsMath.round_js(2.4), 2.0, "2.4")


func test_u32() -> void:
	eq(JsMath.u32(-1.0), 4294967295, "-1")
	eq(JsMath.u32(4294967296.0 + 5.0), 5, "2^32+5")
	eq(JsMath.u32(3.7), 3, "3.7")
	eq(JsMath.u32(-4294967297.0), 4294967295, "-2^32-1")


func test_imul_matches_js() -> void:
	# Math.imul(0xFFFFFFFF, 0xFFFFFFFF) = 1; Math.imul(0x6D2B79F5, 0x6D2B79F5) low 32 bits.
	eq(JsMath.imul(0xFFFFFFFF, 0xFFFFFFFF), 1, "max*max")
	eq(JsMath.imul(0x10000, 0x10000), 0, "overflow to zero")
	eq(JsMath.imul(3, 5), 15, "small")


func test_mod_js_keeps_dividend_sign() -> void:
	eq(JsMath.mod_js(-7.0, 3.0), -1.0, "-7 % 3")
	eq(JsMath.mod_js(7.0, -3.0), 1.0, "7 % -3")


func test_coords_swap_y_and_z() -> void:
	var p := Coords.to_godot(1.0, 2.0, 0.5)
	eq(p, Vector3(1.0, 0.5, 2.0), "to_godot")
	eq(Coords.to_js_xy(p), Vector2(1.0, 2.0), "to_js_xy")
