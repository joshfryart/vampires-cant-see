extends TestCase
## Roguelike UI: title entries, The Coffin, Laid to Rest, stage card / dawn / wait overlays.


func _game() -> Game:
	Game.test_storage = SaveCodec.MemoryStorage.new()
	Game.manual_boot = true
	var g := Game.new()
	g.boot()
	return g


func _menus(g: Game) -> Menus:
	var m := Menus.new()
	m.trek_meta = TrekMeta.create()
	m.sync(g)
	return m


func _texts(root: Node) -> String:
	var out := ""
	for n in root.find_children("*", "Label", true, false):
		out += (n as Label).text + "\n"
	for n in root.find_children("*", "Button", true, false):
		out += "[" + (n as Button).text + "]\n"
	return out


func _result(cause: String) -> Dictionary:
	return {"cause": cause, "stageName": "The Old Road", "miles": 17.4, "humans": 3, "critters": 5, "unseen": 2, "newBest": true,
		"soil_breakdown": {"miles": 17, "humans": 6, "critters": 2, "unseen": 6, "newBest": 5}, "soilTotal": 36, "bestMiles": 17.4}


func test_title_hides_classic_by_default() -> void:
	var g := _game()
	g.state = "title"
	Menus.classic_override = -1
	var m := _menus(g)
	var t := _texts(m)
	ok(t.find("[The Long Night]") >= 0, "long night entry")
	ok(t.find("[The Coffin (Grave Soil 0)]") >= 0, "coffin entry")
	ok(t.find("[Stats]") >= 0, "stats entry")
	ok(t.find("Classic") < 0 and t.find("Shop (Essence") < 0, "classic hidden")
	Menus.classic_override = 1
	m.sync(g)
	ok(_texts(m).find("[Classic: New run]") >= 0 and _texts(m).find("Classic: Shop (Essence") >= 0, "classic shown with flag")
	Menus.classic_override = -1
	m.free()
	g.free()


func test_title_continue_when_checkpoint() -> void:
	var g := _game()
	g.state = "title"
	g.flow.store.write("trek", 1, {"v": 1})
	var m := _menus(g)
	ok(_texts(m).find("[Continue the Long Night]") >= 0, "continue shown")
	ok(_texts(m).find("[New Long Night]") >= 0, "new shown")
	m.free()
	g.free()


func test_every_panel_builds() -> void:
	var g := _game()
	g.state = "title"
	var m := _menus(g)
	for v in ["stats", "coffin", "settings", "guide", "shop", "cstats"]:
		m._view = v
		m.sync(g)
		ok(m._box.get_child_count() > 0, "view " + v)
	ok(_texts(m).find("Stats (classic)") >= 0, "last was classic stats")
	m._view = "coffin"
	m.sync(g)
	eq(m.find_children("buy_*", "Button", true, false).size(), 21, "21 unlock cards")
	m._view = "main"
	for c in ["sun", "withered", "staked", "holy", "victory"]:
		m.show_laid_to_rest(_result(c))
		ok(m._box.get_child_count() > 0, "rest " + c)
	m.free()
	g.free()


func test_buy_flow() -> void:
	var g := _game()
	g.state = "title"
	var m := _menus(g)
	m.trek_meta["soil"] = 30
	var r := m.coffin_buy("far_echo")
	ok(r["ok"], "bought")
	eq(int(m.trek_meta["soil"]), 22, "soil reduced by cost 8")
	eq(TrekMeta.tier_of(m.trek_meta, "far_echo"), 1, "tier up")
	ok(String(r["text"]).find("fresh soil") >= 0, "flavour line")
	eq(g.flow.store.read("rogue")["data"]["soil"], 22, "saved to the rogue slot")
	m._view = "coffin"
	m.sync(g)
	ok(_texts(m).find("Grave Soil: 22") >= 0, "balance shown")
	var b: Button = m.find_children("buy_far_echo", "Button", true, false)[0]
	eq(b.text, "Buy 20 Soil", "next tier cost")
	ok(not b.disabled, "affordable")
	m.free()
	g.free()


func test_locked_cannot_be_bought() -> void:
	var g := _game()
	g.state = "title"
	var m := _menus(g)
	m.trek_meta["soil"] = 500
	var r := m.coffin_buy("long_wither")
	ok(not r["ok"] and r["code"] == "E_META_LOCKED", "locked")
	eq(int(m.trek_meta["soil"]), 500, "soil untouched")
	eq(Menus.locked_reason(m.trek_meta, "long_wither"), "Needs Slow Thirst I", "reason text")
	m._view = "coffin"
	m.sync(g)
	var b: Button = m.find_children("buy_long_wither", "Button", true, false)[0]
	ok(b.disabled, "button disabled while locked")
	ok(_texts(m).find("Locked: Needs Slow Thirst I") >= 0, "reason shown")
	var poor := m.coffin_buy("far_echo")
	ok(poor["ok"], "rich enough")
	m.trek_meta["soil"] = 1
	ok(m.coffin_buy("far_echo")["code"] == "E_META_POOR", "poor")
	m.free()
	g.free()


func test_death_text_per_cause() -> void:
	var sun := TrekUi.rest_text(_result("sun"))
	eq(sun["cause"], "The sun found you at the Old Road, 17.4 miles from your coffin.", "sun")
	ok(TrekUi.rest_text(_result("withered"))["cause"].find("withered") >= 0, "withered")
	ok(TrekUi.rest_text(_result("staked"))["cause"].find("hunter") >= 0, "staked")
	ok(TrekUi.rest_text(_result("holy"))["cause"].find("Holy ground") >= 0, "holy")
	var v := TrekUi.rest_text(_result("victory"))
	ok(v["cause"].find("King") >= 0 and v["title"] == "The Long Night Ends", "victory")
	eq(sun["soil"], ["Miles walked: +17", "People fed: +6", "Critters fed: +2", "Stages cleared unseen: +6", "New best stage: +5"], "breakdown")
	eq(sun["total"], "Grave Soil gained: +36", "total")
	ok(sun["best"].begins_with("A new best"), "best marker")
	var r := _result("sun")
	r["newBest"] = false
	eq(TrekUi.rest_text(r)["best"], "Best: 17.4 miles.", "best line when not new")
	var g := _game()
	g.state = "title"
	var m := _menus(g)
	m.show_laid_to_rest(_result("sun"))
	var t := _texts(m)
	ok(t.find("The sun found you") >= 0 and t.find("[Rise Again]") >= 0 and t.find("[The Coffin]") >= 0 and t.find("[Title]") >= 0, "buttons and cause on screen")
	m.open_coffin(true)
	ok(_texts(m).find("Grave Soil:") >= 0, "coffin over rest")
	ok(m.consume_escape(), "esc leaves coffin")
	ok(_texts(m).find("[Rise Again]") >= 0, "back on rest")
	m.free()
	g.free()


func test_signals() -> void:
	var g := _game()
	g.state = "title"
	var m := _menus(g)
	var hits: Array = []
	m.rise_again_requested.connect(func(): hits.append("rise"))
	m.title_requested.connect(func(): hits.append("title"))
	m.trek_new_requested.connect(func(): hits.append("new"))
	m.show_laid_to_rest(_result("sun"))
	for b in m.find_children("*", "Button", true, false):
		if (b as Button).text == "Rise Again":
			(b as Button).pressed.emit()
	for b in m.find_children("*", "Button", true, false):
		if (b as Button).text == "Title":
			(b as Button).pressed.emit()
	eq(hits, ["rise", "title"], "rest buttons")
	for b in m.find_children("*", "Button", true, false):
		if (b as Button).text == "The Long Night":
			(b as Button).pressed.emit()
	eq(hits, ["rise", "title", "new"], "title entry")
	m.free()
	g.free()


func test_trek_overlays() -> void:
	var u := TrekUi.new()
	eq(TrekUi.stage_card_text(2, "Bramble Wood", 3.0, "dusk"), "Stage 2: Bramble Wood - 3.0 miles - dusk", "card text")
	u.show_stage_card(2, "Bramble Wood", 3.0)
	ok(u.stage_card_visible(), "card shown")
	u._process(5.0)
	ok(not u.stage_card_visible(), "card fades out")
	eq(u.dawn_state(), "hidden", "dawn hidden")
	u.set_dawn(300.0)
	eq(u.dawn_state(), "calm", "calm")
	eq(TrekUi.dawn_text(272.0), "Dawn in 4:32", "countdown")
	u.set_dawn(60.0)
	eq(u.dawn_state(), "warning", "warning")
	ok(TrekUi.dawn_text(60.0).begins_with("Dawn is coming"), "warning text")
	u.set_dawn(0.0)
	eq(u.dawn_state(), "sun", "sun")
	u.set_dawn(-1.0)
	eq(u.dawn_state(), "hidden", "hidden again")
	var hits: Array = []
	u.wait_chosen.connect(func(): hits.append("wait"))
	u.keep_looking_chosen.connect(func(): hits.append("keep"))
	u.show_wait_prompt({"on_keep": func(): hits.append("cb")})
	ok(u.wait_prompt_visible(), "prompt shown")
	var labels: Array = []
	for b in u.find_children("*", "Button", true, false):
		labels.append((b as Button).text)
	ok(labels.has("Wait out the day") and labels.has("Keep looking"), "prompt buttons")
	(u.find_children("keep", "Button", true, false)[0] as Button).pressed.emit()
	eq(hits, ["cb", "keep"], "keep looking")
	ok(not u.wait_prompt_visible(), "prompt closed")
	u.show_wait_prompt()
	(u.find_children("wait", "Button", true, false)[0] as Button).pressed.emit()
	eq(hits.back(), "wait", "wait chosen")
	u.show_waiting(42.4, ["A cough upstairs."])
	ok(u.waiting_visible() and u.waiting_text().find("Blood: 42") >= 0 and u.waiting_text().find("A cough upstairs.") >= 0, "waiting overlay")
	u.update_waiting(40.0, [])
	ok(u.waiting_text().find("Listening...") >= 0, "default listening line")
	u.hide_waiting()
	ok(not u.waiting_visible(), "hidden")
	u.free()
