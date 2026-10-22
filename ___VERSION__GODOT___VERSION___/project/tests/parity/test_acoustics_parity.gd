extends TestCase
## Acoustics and SoundData parity against tests/fixtures/acoustics.json (tools/golden/acoustics.mjs).

const EPS := 1e-9


func test_beam_and_levels() -> void:
	var fx: Dictionary = load_fixture("acoustics")
	for i in fx["thetas"].size():
		var t := float(fx["thetas"][i])
		near(Acoustics.beam(t), float(fx["beam"][i]), EPS, "beam %s" % str(t))
		near(Acoustics.vis_factor(Acoustics.beam(t)), float(fx["visFactor"][i]), EPS, "visFactor %s" % str(t))
	for e in fx["echoLevel"]:
		near(Acoustics.echo_level(e["kind"], float(e["d"]), float(e["t"]), e["m"]), float(e["v"]), EPS, "echoLevel %s %s d=%s t=%s" % [e["kind"], e["m"], str(e["d"]), str(e["t"])])
	for g in fx["gameAmp"]:
		near(Acoustics.game_amp(float(g[0])), float(g[1]), EPS, "gameAmp %s" % str(g[0]))
	for p in fx["personAmp"]:
		near(Acoustics.person_amp(float(p[0]), float(p[1])), float(p[2]), EPS, "personAmp")
	for p in fx["propAmp"]:
		near(Acoustics.prop_amp(float(p[0]), float(p[1])), float(p[2]), EPS, "propAmp")


func test_bounces_and_reverb() -> void:
	var fx: Dictionary = load_fixture("acoustics")
	for f in fx["floor"]:
		near(Acoustics.floor_level(f["m"]), float(f["level"]), EPS, "floor level %s" % f["m"])
		near(Acoustics.floor_amp(f["m"]), float(f["amp"]), EPS, "floor amp %s" % f["m"])
	for c in fx["ceil"]:
		var cf := Acoustics.ceiling_for(c["z"])
		near(float(cf["h"]), float(c["h"]), EPS, "ceil h %s" % c["z"])
		eq(cf["mat"], c["mat"], "ceil mat %s" % c["z"])
		near(Acoustics.ceil_level(float(c["h"]), c["mat"]), float(c["level"]), EPS, "ceil level")
		near(Acoustics.ceil_amp(float(c["h"]), c["mat"]), float(c["amp"]), EPS, "ceil amp")
		near(Acoustics.ceil_delay(float(c["h"])), float(c["delay"]), EPS, "ceil delay")
	for w in fx["wet"]:
		near(Acoustics.wet_for(float(w["hf"]), float(w["ma"]), float(w["n"]), w["indoor"]), float(w["v"]), EPS, "wet")
	for s in fx["sabine"]:
		var z: Dictionary = Acoustics.a()["zone"][s["z"]]
		near(Acoustics.sabine(float(z["w"]), float(z["d"]), float(z["h"]), float(z["alpha"])), float(s["v"]), EPS, "sabine %s" % s["z"])
	for t in fx["t60"]:
		near(Acoustics.t60_for(t["z"], t["kind"]), float(t["v"]), EPS, "t60 %s" % t["z"])
	for c in fx["comb"]:
		near(Acoustics.comb_gain(float(c[0]), float(c[1])), float(c[2]), EPS, "comb")


func test_occlusion_and_steps() -> void:
	var fx: Dictionary = load_fixture("acoustics")
	for m in fx["maekawa"]:
		near(Acoustics.maekawa(float(m[0]), float(m[1])), float(m[2]), EPS, "maekawa")
	for o in fx["occlusion"]:
		var got := Acoustics.occlusion(o["m"], NAN if o["diff"] == null else float(o["diff"]))
		var lbl := "occlusion %s diff=%s" % [o["m"], str(o["diff"])]
		near(got["loss"], float(o["loss"]), EPS, lbl + " loss")
		near(got["gain"], float(o["gain"]), EPS, lbl + " gain")
		near(got["lpHz"], float(o["lpHz"]), 1e-6, lbl + " lpHz")
		near(got["peakHz"], float(o["peakHz"]), EPS, lbl + " peakHz")
		near(got["peakDb"], float(o["peakDb"]), EPS, lbl + " peakDb")
		eq(got["diffracted"], o["diffracted"], lbl + " diffracted")
	for r in fx["repetition"]:
		var got := Acoustics.repetition(float(r[0]))
		if r[1] == null:
			ok(got.is_empty(), "repetition %s should be empty" % str(r[0]))
		else:
			near(got["tau"], float(r[1]["tau"]), EPS, "repetition tau")
			near(got["gain"], float(r[1]["gain"]), EPS, "repetition gain")
	for s in fx["stepScale"]:
		var got := SoundData.step_scale(s["g"], s["f"], float(s["pace"]))
		for k in ["range", "strength", "fade", "gain"]:
			near(got[k], float(s["v"][k]), EPS, "stepScale %s %s %s" % [s["g"], s["f"], k])
