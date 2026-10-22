extends TestCase

class FakePerson:
	var x: float = 0.0
	var y: float = 0.0
	var sched: Variant = null


func test_parse_sys() -> void:
	var m := Flags.parse_sys("vis.vessels:off, dev.showFps:on,bad,x:maybe,__proto__:on,a.b:1")
	eq(m.get("vis.vessels"), false, "off")
	eq(m.get("dev.showFps"), true, "on")
	eq(m.get("a.b"), true, "1")
	ok(not m.has("bad") and not m.has("x") and not m.has("__proto__"), "bad entries skipped")


func test_parse_tun_and_args() -> void:
	var t := Flags.parse_tun("vessels.alpha:0.5,nodot:3,figure.budgetMs:abc,figure.budgetMs:4")
	near(float(t["vessels.alpha"]), 0.5)
	near(float(t["figure.budgetMs"]), 4.0)
	ok(not t.has("nodot"), "needs a system.key path")
	var a := Flags.parse_args(PackedStringArray(["--filter=x", "--sys=a.b:on", "--tun=s.k:2", "--sys=c:off"]))
	eq(a["sys"], {"a.b": true, "c": false}, "sys merged")
	near(float(a["tun"]["s.k"]), 2.0)


func test_json_round_trip() -> void:
	var was := Flags.persist
	Flags.persist = false
	Flags.reset_all()
	eq(Flags.to_json(), {"flags": {}, "tun": {}}, "defaults serialise empty")
	var n := Flags.from_json('{"flags":{"vis.vessels":false,"nope":true},"tun":{"vessels":{"alpha":9,"size":1.5,"bogus":1}}}')
	eq(n, 3, "applied count")
	eq(Flags.get_flag("vis.vessels"), false, "flag applied")
	near(Flags.tun("vessels", "alpha"), 1.0, 1e-9, "clamped to max")
	var j := Flags.to_json()
	eq(j["flags"], {"vis.vessels": false}, "only non-defaults")
	near(float(j["tun"]["vessels"]["size"]), 1.5)
	eq(Flags.from_json("not json"), 0, "bad text")
	Flags.reset_all()
	Flags.persist = was


func test_sched_lines() -> void:
	var p := FakePerson.new()
	p.x = 3.0
	p.y = 4.0
	p.sched = {"role": "baker", "si": 0, "en": true, "homeEarly": true, "stops": [
		{"place": "shop", "act": "work", "until": 0.5}, {"place": "home", "act": "sleep", "until": 1.0}]}
	var q := FakePerson.new()
	var out := Hud.sched_lines([q, p], 0.0, 0.0, 0.25, 100.0)
	eq(out, "baker shop:work > next home eta 25s HOME d5\n", "format")
	p.sched["si"] = -1
	p.sched["en"] = false
	p.sched["homeEarly"] = false
	eq(Hud.sched_lines([p], 0.0, 0.0, 0.25, 100.0), "baker - @ next home eta 25s d5\n", "no current stop")
