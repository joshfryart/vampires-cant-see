class_name Menus
extends Control
## Menu panels over the game (js index.html overlays): title menu with shop and stats, pause, boon and gift choices, run end,
## and the notice list. Built in code; sync(g) shows the panel for the game's state. Phase 8 restyles these.

var _g: Game
var _view: String = "main"
var _panel: PanelContainer
var _box: VBoxContainer
var _last_key: String = ""
var _abandon_ask: bool = false


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.03, 0.06, 0.92)
	sb.set_content_margin_all(22)
	sb.set_corner_radius_all(6)
	sb.border_color = Color(0.5, 0.55, 0.75, 0.5)
	sb.set_border_width_all(1)
	_panel.add_theme_stylebox_override("panel", sb)
	_panel.custom_minimum_size = Vector2(420, 0)
	add_child(_panel)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 10)
	_panel.add_child(_box)
	_panel.visible = false


func _clear() -> void:
	for c in _box.get_children():
		_box.remove_child(c)
		c.queue_free()


func _label(text: String, size: int = 16, color: Color = Color(0.85, 0.9, 1.0), center: bool = true) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(380, 0)
	if center:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_box.add_child(l)
	return l


func _button(text: String, cb: Callable, parent: Control = null) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_ALL
	if cb.is_valid():
		b.pressed.connect(cb)
	(parent if parent != null else _box).add_child(b)
	return b


## Show the panel that belongs to the game's current state.
func sync(g: Game) -> void:
	_g = g
	var st: String = g.state
	var key := "%s/%s" % [st, _view]
	if st != "title" and st != "paused":
		_view = "main"
		key = st
	match st:
		"title": _build_title()
		"paused": _build_pause()
		"boon": _build_choice("A gift of the night", g.flow.run["pendingBoons"], true)
		"gift": _build_choice("Blood gift", g.flow.run["pendingGifts"], false)
		"runend": _build_runend()
		_: _panel.visible = false
	if _panel.visible and key != _last_key:
		_focus_first.call_deferred()
	_last_key = key


## Keyboard focus on the first button of a freshly built panel (arrow keys and Enter then work).
func _focus_first() -> void:
	for c in _box.find_children("*", "Button", true, false):
		if c is Button and not c.disabled and c.is_inside_tree():
			(c as Button).grab_focus()
			return


func _build_title() -> void:
	_clear()
	_panel.visible = true
	match _view:
		"settings":
			_build_settings()
			return
		"shop":
			_build_shop()
			return
		"stats":
			_build_stats()
			return
	_label("VAMPIRES CAN'T SEE", 26, Color(0.9, 0.2, 0.2))
	_label("You are a vampire and you are blind. Ping the dark, drink the town, sleep before dawn.", 13, Color(0.7, 0.75, 0.9))
	for n in _g.flow.notices:
		_label(n, 12, Color(1.0, 0.8, 0.4))
	_g.flow.notices.clear()
	if _g.flow.has_run:
		_button("Continue", func(): _g.flow.continue_run())
		var nb := _button("Abandon run? Click again" if _abandon_ask else "New run", Callable())
		nb.pressed.connect(func():
			if not _abandon_ask:
				_abandon_ask = true
				nb.text = "Abandon run? Click again"
				_g.get_tree().create_timer(3.0).timeout.connect(func():
					_abandon_ask = false
					if is_instance_valid(nb):
						nb.text = "New run")
				return
			_abandon_ask = false
			_g.flow.abandon_stored()
			_g.flow.begin_run())
	else:
		_button("New run", func(): _g.flow.begin_run())
	_button("Shop (Essence %d)" % int(_g.flow.meta["essence"]), func():
		_view = "shop"
		sync(_g))
	_button("Stats", func():
		_view = "stats"
		sync(_g))
	_button("Settings", func():
		_view = "settings"
		sync(_g))
	_button("Quit", func(): _g.get_tree().quit())
	_label("WASD move · mouse look · click/Space ping · right-click/R drink · E door/sleep · Q shriek · Shift mist · F still · G rock · Esc pause", 11, Color(0.6, 0.65, 0.8))


func _build_shop() -> void:
	_label("Shop", 22, Color(0.9, 0.85, 0.5))
	_label("Essence: %d" % int(_g.flow.meta["essence"]), 15)
	var meta: Dictionary = _g.flow.meta
	for u in GameData.get_json("upgrades")["upgrades"]:
		var t: int = Meta.tier_of(meta, u["id"])
		var cost: int = Meta.cost_of(meta, u["id"])
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		_box.add_child(row)
		var info := Label.new()
		info.text = "%s  [%d/%d]  %s" % [u["name"], t, Meta.MAX_TIER, u["desc"][mini(t, Meta.MAX_TIER) - (1 if t >= Meta.MAX_TIER else 0)]]
		info.custom_minimum_size = Vector2(300, 0)
		info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(info)
		var id: String = u["id"]
		var b := _button("Max" if cost < 0 else "Buy %d" % cost, func():
			var r := Meta.buy(_g.flow.meta, id)
			if r["ok"]:
				_g.flow.save_meta()
			sync(_g), row)
		b.disabled = cost < 0 or float(meta["essence"]) < cost
	_button("Back", func():
		_view = "main"
		sync(_g))


func _build_stats() -> void:
	_label("Stats", 22, Color(0.9, 0.85, 0.5))
	var st: Dictionary = _g.flow.meta["stats"]
	for k in Meta.STAT_KEYS:
		_label("%s: %d" % [STAT_LABELS.get(k, k), int(st[k])], 14)
	_button("Back", func():
		_view = "main"
		sync(_g))


func _build_pause() -> void:
	_clear()
	_panel.visible = true
	if _view == "settings":
		_build_settings()
		return
	_label("Paused", 24)
	_button("Resume", func(): _g.resume())
	_button("Settings", func():
		_view = "settings"
		sync(_g))
	_button("Save and quit to menu", func():
		_g.flow.save_run("quit")
		_g.run_on = false
		_g.flow.has_run = _g.flow.store.has("run")
		_g.set_state("title"))
	_label("The run is saved when you pause.", 12, Color(0.6, 0.65, 0.8))


func _build_choice(title: String, ids: Variant, boon: bool) -> void:
	_clear()
	_panel.visible = true
	_label(title, 22, Color(0.9, 0.85, 0.5))
	if ids == null:
		return
	var i := 0
	for id in ids:
		var info: Variant = Meta.boon_by_id(id) if boon else Hunger.gift_by_id(id)
		var card := VBoxContainer.new()
		card.add_theme_constant_override("separation", 2)
		_box.add_child(card)
		var name_l := Label.new()
		name_l.text = str(info["name"]) if info != null else str(id)
		name_l.add_theme_font_size_override("font_size", 17)
		name_l.add_theme_color_override("font_color", Color(1.0, 0.9, 0.7))
		card.add_child(name_l)
		var d := Label.new()
		d.text = str(info["desc"]) if info != null else ""
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.custom_minimum_size = Vector2(380, 0)
		card.add_child(d)
		var idx := i
		_button("Take (%d)" % (i + 1), func():
			if boon:
				_g.flow.pick_boon(idx)
			else:
				_g.flow.pick_gift(idx), card)
		i += 1


func _build_runend() -> void:
	_clear()
	_panel.visible = true
	var r: Dictionary = _g.flow.run_result
	_label(str(r.get("title", "Run over")), 24, Color(0.9, 0.3, 0.3) if r.get("kind") == "lost" else Color(0.5, 0.9, 0.6))
	_label(str(r.get("message", "")), 15)
	_label(str(r.get("essence", "")), 15, Color(0.9, 0.85, 0.5))
	_button("New run", func(): _g.flow.begin_run())
	_button("Menu", func(): _g.set_state("title"))


# ---------------------------------------------------------------- settings

const STAT_LABELS := {"runs": "Runs", "wins": "Wins", "nightsSurvived": "Nights survived", "peopleFed": "People fed", "bestNights": "Best nights in a run", "essenceEarned": "Essence earned"}
const SETTINGS_ROWS := [
	["Volume", "volume", 0.0, 1.0, 0.05], ["Ambience", "ambienceGain", 0.0, 1.0, 0.05],
	["Mouse sensitivity", "mouseSensitivity", 0.0005, 0.01, 0.0005], ["Invert mouse", "invertMouse"],
	["Move speed", "moveSpeed", 1.0, 6.0, 0.25], ["Field of view", "fovDeg", 50.0, 100.0, 1.0],
	["Night length (minutes)", "nightLengthMin", 2.0, 30.0, 1.0], ["Ping range", "sonarRange", 4.0, 20.0, 0.5],
	["Ping fade (s)", "sonarFade", 1.0, 8.0, 0.25], ["Ping cooldown (s)", "sonarCooldown", 0.2, 3.0, 0.05],
	["Feeding reach", "feedReach", 1.0, 3.0, 0.1], ["Hold to drink / toggle", "feedToggle"],
	["Effects (0 off, 1 low, 2 high)", "effects", 0.0, 2.0, 1.0], ["Wobbly lines", "lineBoil"], ["Material detail", "materialDetail"],
	["Reduced motion", "reduceMotion"], ["Head bob", "headBob"], ["Edge vignette", "edgeVignette"], ["Key turn speed", "keyTurnSpeed", 1.0, 6.0, 0.1], ["Large text", "largeText"], ["Subtitles", "subtitles"], ["Translation", "translation"],
	["Villager voices", "villagerVoices"], ["Autosave every (s)", "autosaveSec", 5.0, 300.0, 5.0],
]


func _build_settings() -> void:
	_label("Settings", 22, Color(0.9, 0.85, 0.5))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(430, 360)
	_box.add_child(scroll)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 6)
	list.custom_minimum_size = Vector2(410, 0)
	scroll.add_child(list)
	for row in SETTINGS_ROWS:
		var key: String = row[1]
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 8)
		list.add_child(hb)
		var l := Label.new()
		l.text = row[0]
		l.custom_minimum_size = Vector2(190, 0)
		hb.add_child(l)
		if row.size() == 2:
			var cb := CheckBox.new()
			cb.button_pressed = _g.cfg[key] == true
			cb.focus_mode = Control.FOCUS_NONE
			cb.toggled.connect(func(on): _g.set_config(key, on))
			hb.add_child(cb)
		else:
			var sl := HSlider.new()
			sl.min_value = row[2]
			sl.max_value = row[3]
			sl.step = row[4]
			sl.value = float(_g.cfg[key])
			sl.custom_minimum_size = Vector2(140, 0)
			sl.focus_mode = Control.FOCUS_NONE
			hb.add_child(sl)
			var val := Label.new()
			val.text = _fmt(float(_g.cfg[key]))
			val.custom_minimum_size = Vector2(50, 0)
			hb.add_child(val)
			sl.value_changed.connect(func(v):
				val.text = _fmt(v)
				_g.set_config(key, v))
	_button("Reset to defaults", func():
		for k in Config.DEFAULTS:
			_g.cfg[k] = Config.DEFAULTS[k]
		_g.set_config("cfgV", Config.DEFAULTS["cfgV"])
		sync(_g))
	_button("Back", func():
		_view = "main"
		sync(_g))


static func _fmt(v: float) -> String:
	return str(snappedf(v, 0.0001))
