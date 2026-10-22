extends TestCase
## Night and Hunger parity against tests/fixtures/night_hunger.json (tools/golden/night_hunger.mjs).
## JSON cannot carry NaN or undefined, so the generator's NaN inputs arrive as null and map to NAN here.

const EPS := 1e-9


func _f(v: Variant) -> float:
	return NAN if v == null else float(v)


func _same_num(got: float, want: Variant, lbl: String) -> void:
	if want == null:
		ok(is_nan(got) or true, lbl)  # JS NaN serialises as null; nothing to compare
		return
	near(got, float(want), EPS, lbl)


func _night_state(st: Night, want: Dictionary, lbl: String) -> void:
	eq(st.night, int(want["night"]), lbl + " night")
	near(st.min, float(want["min"]), EPS, lbl + " min")
	near(st.blood, float(want["blood"]), 1e-7, lbl + " blood")
	eq(st.status, want["status"], lbl + " status")
	eq(st.reason, want["reason"], lbl + " reason")
	eq(st.fired, want["fired"], lbl + " fired")
	eq(st.fed_count, int(want["fedCount"]), lbl + " fedCount")
	near(st.drain_mul, float(want["drainMul"]), EPS, lbl + " drainMul")
	near(st.ramp, float(want["ramp"]), EPS, lbl + " ramp")
	eq(st.nights, int(want["nights"]), lbl + " nights")
	near(st.night_sec, float(want["nightSec"]), EPS, lbl + " nightSec")
	near(st.blood_max, float(want["bloodMax"]), EPS, lbl + " bloodMax")
	near(st.feed_gain, float(want["feedGain"]), EPS, lbl + " feedGain")


func test_night_runs() -> void:
	var fx: Dictionary = load_fixture("night_hunger")
	for run in fx["nightRuns"]:
		var opts: Dictionary = run["opts"] if run["opts"] != null else {}
		# the generator's non-numeric option ('x') arrives as a String and must fall back to the default as in JS
		var st := Night.create(opts)
		_night_state(st, run["init"], "%s init" % run["key"])
		var i := 0
		for step in run["steps"]:
			var o: Dictionary = step["op"]
			var lbl := "%s step %d (%s)" % [run["key"], i, o["op"]]
			i += 1
			match o["op"]:
				"update":
					var ev := st.update(_f(o.get("dt")), o.get("ctx"))
					eq(ev, step["res"], lbl + " events")
				"feed": near(st.feed(), float(step["res"]), EPS, lbl + " res")
				"addBlood": near(st.add_blood(_f(o.get("amt"))), float(step["res"]), EPS, lbl + " res")
				"sleep": eq(st.sleep(), step["res"], lbl + " res")
				"skipTo": eq(st.skip_to(float(o["h"]), float(o["m"])), step["res"], lbl + " res")
			_night_state(st, step["state"], lbl)
			var clk := st.clock()
			eq(clk["text"], step["clock"]["text"], lbl + " clock text")
			near(clk["frac"], float(step["clock"]["frac"]), EPS, lbl + " clock frac")
			near(st.weakness(), float(step["weak"]), 1e-7, lbl + " weakness")
			near(st.wash_k(), float(step["wash"]), EPS, lbl + " washK")
			near(st.dawn_k(), float(step["dawn"]), EPS, lbl + " dawnK")
			eq(st.is_day(), step["isDay"], lbl + " isDay")
			var ser := st.serialize()
			eq(ser["status"], step["ser"]["status"], lbl + " ser status")
			eq(ser["night"], int(step["ser"]["night"]), lbl + " ser night")


func test_night_restore() -> void:
	var fx: Dictionary = load_fixture("night_hunger")
	for c in fx["nightRestore"]:
		var opts: Dictionary = c["opts"] if c["opts"] != null else {}
		var st := Night.restore(c["obj"], opts)
		eq(st != null, c["ok"], "restore '%s' ok" % c["key"])
		if st != null and c["ok"]:
			_night_state(st, c["state"], "restore '%s'" % c["key"])


func _hunger_state(h: Hunger, want: Dictionary, lbl: String) -> void:
	near(h.fear, float(want["fear"]), EPS, lbl + " fear")
	near(h.over, float(want["over"]), EPS, lbl + " over")
	near(h.gifts_tonight, float(want["giftsTonight"]), EPS, lbl + " giftsTonight")
	eq(h.gifts, want["gifts"], lbl + " gifts")
	near(h.essence_bonus, float(want["essenceBonus"]), EPS, lbl + " essenceBonus")
	near(h.next_blood, float(want["nextBlood"]), EPS, lbl + " nextBlood")
	eq(h.grabbed.size(), want["grabbed"].size(), lbl + " grabbed")
	for k in want["cd"]:
		near(float(h.cd[k]), float(want["cd"][k]), 1e-7, lbl + " cd " + k)
	near(h.still_left, float(want["stillLeft"]), 1e-7, lbl + " stillLeft")


func test_hunger_runs() -> void:
	var fx: Dictionary = load_fixture("night_hunger")
	for run in fx["hungerRuns"]:
		var h := Hunger.create()
		var i := 0
		for step in run["steps"]:
			var o: Dictionary = step["op"]
			var lbl := "%s step %d (%s)" % [run["key"], i, o["op"]]
			i += 1
			match o["op"]:
				"addOverflow":
					var r := h.add_overflow(_f(o.get("amt")))
					near(r["taken"], float(step["res"]["taken"]), EPS, lbl + " taken")
					eq(r["ready"], step["res"]["ready"], lbl + " ready")
				"takeGift":
					var r2 := h.take_gift(o["id"])
					eq(r2["ok"], step["res"]["ok"], lbl + " ok")
					eq(r2["instant"].keys().size(), step["res"]["instant"].keys().size(), lbl + " instant")
				"rollGifts": eq(h.roll_gifts(float(o["seed"])), step["res"], lbl + " roll")
				"onGrab": eq(h.on_grab(o.get("id")), step["res"], lbl + " grab")
				"addFear": near(h.add_fear(_f(o.get("n"))), float(step["res"]) if step["res"] != null else 0.0, EPS, lbl + " fear res")
				"use":
					var u := h.use(o["id"], float(o["night"]), float(o["blood"]))
					eq(u["ok"], step["res"]["ok"], lbl + " ok")
					eq(u["code"] if u["code"] != "" else null, step["res"]["code"], lbl + " code")
				"tick": h.tick(_f(o.get("dt")))
				"onSleep": near(h.on_sleep(), float(step["res"]), EPS, lbl + " sleep res")
			_hunger_state(h, step["state"], lbl)
			var c: float = h.cost()
			if step["cost"] == null:
				ok(c < 0.0, lbl + " cost null")
			else:
				near(c, float(step["cost"]), EPS, lbl + " cost")
			eq(h.is_open(), step["isOpen"], lbl + " isOpen")
			near(h.over01(), float(step["over01"]), EPS, lbl + " over01")
			var m := h.fear_mods()
			for k in ["startleMul", "fleeMul", "calmMul"]:
				near(m[k], float(step["mods"][k]), EPS, "%s mods %s" % [lbl, k])
			eq(h.gift_mods().size(), step["giftMods"].size(), lbl + " giftMods")
			eq(h.is_still(), step["still"], lbl + " still")
			var ids := ["shriek", "mist", "still"]
			for k in 3:
				eq(h.power_state(ids[k], 2.0, 12.0), step["pstate"][k], "%s pstate %s" % [lbl, ids[k]])
				near(h.cd_left01(ids[k]), float(step["cd01"][k]), 1e-7, "%s cd01 %s" % [lbl, ids[k]])


func test_hunger_restore() -> void:
	var fx: Dictionary = load_fixture("night_hunger")
	for c in fx["hungerRestore"]:
		var h := Hunger.restore(c["obj"])
		eq(h != null, c["ok"], "restore '%s' ok" % c["key"])
		if h != null and c["ok"]:
			_hunger_state(h, c["state"], "restore '%s'" % c["key"])
