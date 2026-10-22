extends TestCase
## Ripple helper parity against tests/fixtures/ripple.json (tools/golden/ripple.mjs).

const EPS := 1e-12


func test_functions() -> void:
	var fx: Dictionary = load_fixture("ripple")
	var rows: Dictionary = fx["rows"]
	for e in rows["wobble"]:
		near(RippleFx.wobble(float(e["a"]), float(e["p"])), float(e["v"]), EPS, "wobble %s" % str(e["a"]))
	for e in rows["band"]:
		if e.has("f"):
			near(RippleFx.band_front(float(e["a"])), float(e["f"]), EPS, "bandFront %s" % str(e["a"]))
		else:
			near(RippleFx.band_gain(float(e["u"]), float(e["a"])), float(e["g"]), EPS, "bandGain %s/%s" % [str(e["u"]), str(e["a"])])
	for e in rows["wave"]:
		near(RippleFx.wave(float(e["u"]), float(e["a"])), float(e["w"]), EPS, "wave %s/%s" % [str(e["u"]), str(e["a"])])
	for e in rows["wavy"]:
		var amp: float = 0.04 if e["amp"] == null else float(e["amp"])
		near(RippleFx.wavy_radius(float(e["R"]), float(e["th"]), float(e["t"]), float(e["k"]), amp), float(e["v"]), EPS, "wavy")
	for e in rows["strips"]:
		var got: Array = RippleFx.mask_strips(float(e["zmin"]), float(e["zmax"]), float(e["ztop"]), float(e["soft"]))
		eq(got.size(), int(e["n"]), "strip count %s" % str([e["zmin"], e["zmax"], e["ztop"], e["soft"]]))
		for i in mini(got.size(), int(e["n"])):
			for j in 3:
				near(got[i][j], float(e["out"][i * 3 + j]), 1e-6, "strip value")
	for e in rows["foot"]:
		near(RippleFx.foot_ring(float(e["age"]), 3.0, 7.0, int(e["k"])), float(e["ring"]), EPS, "footRing")
		near(RippleFx.foot_ring_alpha(float(e["age"]), 3.0, int(e["k"])), float(e["alpha"]), EPS, "footRingAlpha")
	for e in rows["amp"]:
		near(RippleFx.jitter_amp(float(e["l"])), float(e["v"]), EPS, "jitterAmp")


func test_ring_state() -> void:
	var fx: Dictionary = load_fixture("ripple")
	var st := RippleFx.Rings.new()
	st.max_rings = 3
	for i in 5:
		var r := st.spawn(float(i), float(i * 2), i * 0.3, {"kind": "person" if i % 2 == 1 else "marker", "maxR": 1.0 + i * 0.2, "life": 0.5, "strength": 0.8, "delay": 0.2 if i == 2 else 0.0, "inward": i == 3, "minR": 0.3})
		eq(st.rings.size(), int(fx["ops"][i]["n"]), "ring count %d" % i)
		near(r["x"], float(fx["ops"][i]["x"]), EPS, "ring x")
	var n := 0
	for ring in st.rings:
		for t in [0.0, 0.5, 0.8, 1.2, 2.0]:
			var want: Dictionary = fx["samples"][n]
			n += 1
			near(RippleFx.Rings.radius(ring, t), float(want["r"]), EPS, "ring radius")
			near(RippleFx.Rings.alpha(ring, t), float(want["a"]), EPS, "ring alpha")
	st.prune(1.0)
	var xs: Array = []
	for r in st.rings:
		xs.append(int(r["x"]))
	var want_xs: Array = []
	for x in fx["afterPrune"]:
		want_xs.append(int(x))
	eq(xs, want_xs, "after prune")
