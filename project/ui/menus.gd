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
var _k: float = 1.0
var _version: Label
var _notice
const Notice = preload("res://ui/notice.gd")

## The Long Night UI API (WP9 wires these; full list in docs/ROGUELIKE.md "UI API").
signal trek_new_requested
signal trek_continue_requested
signal rise_again_requested
signal title_requested
## The live roguelike meta (TrekMeta dict). Integration may assign it; otherwise it is lazily read from the `rogue` save.
var trek_meta: Dictionary = {}
var trek_ui: TrekUi
var _trek_view: String = ""      # "" | "rest" (Laid to Rest) | "coffin" (the shop opened from the death screen)
var _coffin_back: String = "title"
var _coffin_msg: String = ""
var _rest_result: Dictionary = {}
## -1 follows the `--classic` command line flag; tests set 0 or 1.
static var classic_override: int = -1


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
	_version = Label.new()
	var ver := str(ProjectSettings.get_setting("application/config/version", ""))
	_version.text = "v" + ver if ver != "" else ""
	_version.add_theme_font_size_override("font_size", 11)
	_version.add_theme_color_override("font_color", Color(0.55, 0.6, 0.75, 0.7))
	_version.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_version.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_version.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_version.offset_right = -10.0
	_version.offset_bottom = -6.0
	_version.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_version.visible = false
	add_child(_version)
	_notice = Notice.new()
	add_child(_notice)
	trek_ui = TrekUi.new()
	add_child(trek_ui)


## Main title menu sits below the drawn title; every other panel is centred.
func _place(below_title: bool) -> void:
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	if below_title:
		_panel.anchor_left = 0.5
		_panel.anchor_right = 0.5
		_panel.anchor_top = 0.0
		_panel.anchor_bottom = 0.0
		_panel.grow_vertical = Control.GROW_DIRECTION_END
		_panel.offset_left = -210.0
		_panel.offset_right = 210.0
		_panel.offset_top = 215.0
		_panel.offset_bottom = 215.0
	else:
		_panel.anchor_left = 0.5
		_panel.anchor_right = 0.5
		_panel.anchor_top = 0.5
		_panel.anchor_bottom = 0.5
		_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
		_panel.offset_left = -210.0
		_panel.offset_right = 210.0
		_panel.offset_top = 0.0
		_panel.offset_bottom = 0.0
	_refit.call_deferred(below_title)


## Shrink the panel to its content and keep it centred (or hanging below the title) once the layout has settled.
func _refit(below_title: bool) -> void:
	if not _panel.is_inside_tree():
		return
	await _panel.get_tree().process_frame
	var ms: Vector2 = _panel.get_combined_minimum_size()
	if below_title:
		_panel.offset_top = 215.0
		_panel.offset_bottom = 215.0 + ms.y
	else:
		_panel.offset_top = -ms.y / 2.0
		_panel.offset_bottom = ms.y / 2.0
	_panel.offset_left = -maxf(210.0, ms.x / 2.0)
	_panel.offset_right = maxf(210.0, ms.x / 2.0)


func _clear() -> void:
	for c in _box.get_children():
		_box.remove_child(c)
		c.queue_free()


## Menu font size with the large-text factor (js adds a CSS class that enlarges every menu).
func _fs(size: int) -> int:
	return int(round(float(size) * _k))


func _label(text: String, size: int = 16, color: Color = Color(0.85, 0.9, 1.0), center: bool = true) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", _fs(size))
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
	_notice.attach(g)
	_k = 1.3 if g.cfg.get("largeText", false) == true else 1.0
	var th := Theme.new()
	th.default_font_size = _fs(16)
	_panel.theme = th
	_version.visible = g.state == "title" and _version.text != ""
	var st: String = g.state
	var key := "%s/%s" % [st, _view]
	if st != "title" and st != "paused":
		_view = "main"
		key = st
	if _trek_view != "" and st != "error":
		key = "trek/" + _trek_view
		_build_trek_overlay()
		if _panel.visible and key != _last_key:
			_focus_first.call_deferred()
		_last_key = key
		return
	match st:
		"title": _build_title()
		"paused": _build_pause()
		"boon": _build_choice("A gift of the night", g.flow.run["pendingBoons"], true)
		"gift": _build_choice("Blood gift", g.flow.run["pendingGifts"], false)
		"runend": _build_runend()
		"error": _build_error()
		_: _panel.visible = false
	if _panel.visible and key != _last_key:
		_focus_first.call_deferred()
	_last_key = key


## Esc inside a sub-view of the title or pause menu goes back to that menu's main view. Returns true when it did.
## game.gd calls this first in its Esc handler: `if menus != null and menus.consume_escape(): return`.
func consume_escape() -> bool:
	if _trek_view == "coffin" and _g != null:
		_coffin_close()
		return true
	if _g == null or _view == "main" or (_g.state != "title" and _g.state != "paused"):
		return false
	_view = "main"
	sync(_g)
	return true


## Keyboard focus on the first button of a freshly built panel (arrow keys and Enter then work).
func _focus_first() -> void:
	for c in _box.find_children("*", "Button", true, false):
		if c is Button and not c.disabled and c.is_inside_tree():
			(c as Button).grab_focus()
			return


func _build_title() -> void:
	_clear()
	_panel.visible = true
	_place(_view == "main")
	match _view:
		"settings":
			_build_settings()
			return
		"shop":
			_build_shop()
			return
		"stats":
			_build_trek_stats()
			return
		"cstats":
			_build_stats()
			return
		"coffin":
			_build_coffin()
			return
		"guide":
			_build_guide()
			return
	# Notices are shown by the Notice overlay (it drains g.flow.notices in any state).
	if has_trek_checkpoint():
		_button("Continue the Long Night", func(): trek_continue_requested.emit())
		var tb := _button("Abandon the trek? Click again" if _abandon_ask else "New Long Night", Callable())
		tb.pressed.connect(func():
			if not _abandon_ask:
				_abandon_ask = true
				tb.text = "Abandon the trek? Click again"
				_g.get_tree().create_timer(3.0).timeout.connect(func():
					_abandon_ask = false
					if is_instance_valid(tb):
						tb.text = "New Long Night")
				return
			_abandon_ask = false
			trek_new_requested.emit())
	else:
		_button("The Long Night", func(): trek_new_requested.emit())
	_button("The Coffin (Grave Soil %d)" % int(_tm()["soil"]), func():
		_coffin_back = "title"
		_view = "coffin"
		sync(_g))
	_button("Stats", func():
		_view = "stats"
		sync(_g))
	if classic_enabled():
		_build_classic_buttons()
	_button("How to play", func():
		_view = "guide"
		sync(_g))
	_button("Character creator", func(): _g.creator.open())
	_button("Export save", _export_save)
	_button("Import save", _import_save)
	_button("Settings", func():
		_view = "settings"
		sync(_g))
	_button("Quit", func(): _g.get_tree().quit())
	_label("WASD move · mouse look · click/Space ping · right-click/R drink · E door/sleep · Q shriek · Shift mist · F still · G rock · Esc pause", 11, Color(0.6, 0.65, 0.8))


## Classic Five Nights is hidden unless the dev flag `--classic` is on (Menus.classic_override forces it in tests).
static func classic_enabled() -> bool:
	if classic_override >= 0:
		return classic_override == 1
	return OS.get_cmdline_user_args().has("--classic") or OS.get_cmdline_args().has("--classic")


## Classic Five Nights entries: the original title code path, unchanged apart from the labels.
func _build_classic_buttons() -> void:
	if _g.flow.has_run:
		_button("Classic: Continue", func():
			if not _g.flow.continue_run():
				sync(_g))
		var nb := _button("Abandon run? Click again" if _abandon_ask else "Classic: New run", Callable())
		nb.pressed.connect(func():
			if not _abandon_ask:
				_abandon_ask = true
				nb.text = "Abandon run? Click again"
				_g.get_tree().create_timer(3.0).timeout.connect(func():
					_abandon_ask = false
					if is_instance_valid(nb):
						nb.text = "Classic: New run")
				return
			_abandon_ask = false
			_g.flow.abandon_stored()
			_g.flow.begin_run())
	else:
		_button("Classic: New run", func(): _g.flow.begin_run())
	_button("Classic: Shop (Essence %d)" % int(_g.flow.meta["essence"]), func():
		_view = "shop"
		sync(_g))
	_button("Classic: Stats", func():
		_view = "cstats"
		sync(_g))


func _build_shop() -> void:
	_label("Shop (classic)", 22, Color(0.9, 0.85, 0.5))
	_label("Essence: %d" % int(_g.flow.meta["essence"]), 15)
	var meta: Dictionary = _g.flow.meta
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(430, 340)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_box.add_child(scroll)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 6)
	list.custom_minimum_size = Vector2(410, 0)
	scroll.add_child(list)
	for u in GameData.get_json("upgrades")["upgrades"]:
		var t: int = Meta.tier_of(meta, u["id"])
		var cost: int = Meta.cost_of(meta, u["id"])
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		list.add_child(row)
		row.add_child(IconRect.new(str(u.get("icon", "bat")), 40.0))
		var info := Label.new()
		info.text = "%s  %s%s  %s" % [u["name"], "●".repeat(t), "○".repeat(Meta.MAX_TIER - t), u["desc"][mini(t, Meta.MAX_TIER) - (1 if t >= Meta.MAX_TIER else 0)]]
		info.custom_minimum_size = Vector2(260, 0)
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
	_label("Stats (classic)", 22, Color(0.9, 0.85, 0.5))
	var st: Dictionary = _g.flow.meta["stats"]
	for k in Meta.STAT_KEYS:
		_label("%s: %d" % [STAT_LABELS.get(k, k), int(st[k])], 14)
	_label("Essence now: %d" % int(_g.flow.meta["essence"]), 14)
	_button("Back", func():
		_view = "main"
		sync(_g))


func _build_pause() -> void:
	_clear()
	_panel.visible = true
	_place(false)
	if _view == "settings":
		_build_settings()
		return
	if _view == "guide":
		_build_guide()
		return
	_label("Paused", 24)
	_button("Resume", func(): _g.resume())
	_button("Abilities", func():
		_view = "guide"
		sync(_g))
	_button("Settings", func():
		_view = "settings"
		sync(_g))
	_button("Save and quit to menu", func():
		_g.flow.save_run("quit")
		_g.run_on = false
		_g.flow.has_run = _g.flow.store.has("run")
		_g.set_state("title"))
	_button("Copy report", func(): DisplayServer.clipboard_set(Log.report()))
	_button("Save log to file", func():
		var f := FileAccess.open("user://vcs-log.txt", FileAccess.WRITE)
		if f != null:
			f.store_string(Log.report())
			Log.info("menu", "log saved to " + ProjectSettings.globalize_path("user://vcs-log.txt")))
	_label("The run is saved when you pause.", 12, Color(0.6, 0.65, 0.8))


func _build_choice(title: String, ids: Variant, boon: bool) -> void:
	_clear()
	_panel.visible = true
	_place(false)
	_label(title, 22, Color(0.9, 0.85, 0.5))
	if ids == null:
		return
	var i := 0
	for id in ids:
		var info: Variant = Meta.boon_by_id(id) if boon else Hunger.gift_by_id(id)
		var card := VBoxContainer.new()
		card.add_theme_constant_override("separation", 2)
		_box.add_child(card)
		var ic := IconRect.new(str(info["icon"]) if info != null else "bat", 56.0)
		ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		card.add_child(ic)
		var name_l := Label.new()
		name_l.text = str(info["name"]) if info != null else str(id)
		name_l.add_theme_font_size_override("font_size", _fs(17))
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
	_place(false)
	var r: Dictionary = _g.flow.run_result
	var tomb := IconRect.new("tomb", 120.0)
	tomb.custom_minimum_size = Vector2(160, 120)
	tomb.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_box.add_child(tomb)
	_label(str(r.get("title", "Run over")), 24, Color(0.9, 0.3, 0.3) if r.get("kind") == "lost" else Color(0.5, 0.9, 0.6))
	_label(str(r.get("message", "")), 15)
	_label(str(r.get("essence", "")), 15, Color(0.9, 0.85, 0.5))
	_button("New run", func(): _g.flow.begin_run())
	_button("Crypt", func(): _g.set_state("title"))


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
	["Reduced motion", "reduceMotion"], ["Head bob", "headBob"], ["Old bip ping", "pingBip"], ["Edge vignette", "edgeVignette"], ["Key turn speed", "keyTurnSpeed", 1.0, 6.0, 0.1], ["Large text", "largeText"], ["Subtitles", "subtitles"], ["Translation", "translation"],
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
			cb.focus_mode = Control.FOCUS_ALL
			cb.toggled.connect(func(on): _g.set_config(key, on))
			hb.add_child(cb)
		else:
			var sl := HSlider.new()
			sl.min_value = row[2]
			sl.max_value = row[3]
			sl.step = row[4]
			sl.value = float(_g.cfg[key])
			sl.custom_minimum_size = Vector2(140, 0)
			sl.focus_mode = Control.FOCUS_ALL
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


# ---------------------------------------------------------------- guide

## The How to play / Abilities panel (js buildGuide): basics, goal, blood, power cards, gifts and fear from the data files.
func _build_guide() -> void:
	var hd: Dictionary = GameData.get_json("hunger")
	var nights: int = _g.night.nights if _g.night != null and _g.state == "paused" else 5
	_label("How to play", 22, Color(0.9, 0.85, 0.5))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(460, 380)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_box.add_child(scroll)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 6)
	list.custom_minimum_size = Vector2(440, 0)
	scroll.add_child(list)
	var sec := func(title: String, lines: Array) -> void:
		_guide_text(list, title, 16, Color(0.9, 0.85, 0.5))
		for ln in lines:
			_guide_text(list, ln, 13, Color(0.8, 0.85, 0.95))
	sec.call("Basics", [
		"Move with W A S D or the arrow keys (Left and Right arrows turn); look with the mouse.",
		"Ping: click or Space sends out a sonar pulse that draws walls and doors for a moment. It is loud, so people nearby may hear it.",
		"Echoes that move are people. Walk up close and hold right-click (or R) to drink. Drink in the dark; lit people see you.",
		"Sleep: press E at your crypt bed or a dark safe spot before 06:00. Powers: Q shriek, C or Shift mist, F still. Esc pauses.",
	])
	sec.call("Goal", [
		"Feed on the townsfolk, then get home or into a dark safe spot before 06:00. Survive %d nights." % nights,
		"The farthest open safe spot in town pays +5 Essence when you sleep there.",
	])
	sec.call("Blood", [
		"Your blood drains all night, and faster each night (+%d%% per night)." % int(round(float(hd["RAMP"]) * 100.0)),
		"Below 25 your pulses weaken. Hold right click near someone to drink.",
	])
	_guide_text(list, "Powers", 16, Color(0.9, 0.85, 0.5))
	var cur: int = _g.night.night if _g.state == "paused" and _g.night != null else 0
	for p in hd["powers"]:
		var locked: bool = cur > 0 and cur < int(p["unlock"])
		var key: String = "Shift or C" if str(p["key"][0]).begins_with("Shift") else str(p["key"][0]).trim_prefix("Key")
		var pic := IconRect.new(str(p["icon"]), 44.0)
		pic.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		list.add_child(pic)
		_guide_text(list, str(p["name"]), 15, Color(0.55, 0.6, 0.7) if locked else Color(1.0, 0.9, 0.7))
		if locked:
			_guide_text(list, "Unlocks night %d" % int(p["unlock"]), 12, Color(0.6, 0.65, 0.8))
		else:
			_guide_text(list, "Key %s · Night %d · Cost %d blood · Cooldown %s s · Fear +%d" % [key, int(p["unlock"]), int(p["cost"]), str(p["cooldown"]), int(p["fear"])], 12, Color(0.7, 0.75, 0.9))
		_guide_text(list, str(p.get("how", p.get("desc", ""))), 13, Color(0.8, 0.85, 0.95))
		_guide_text(list, str(p.get("tip", "")), 12, Color(0.6, 0.7, 0.6))
	var gc: Array = hd["GIFT_COSTS"]
	sec.call("Blood gifts", [
		"Keep drinking when your blood is full and the coral bar fills. At %d (then %d) you pick 1 of 3 gifts." % [int(gc[0]), int(gc[1])],
		"Up to %d per night. Each gift gives +%d Essence." % [int(hd["GIFTS_PER_NIGHT"]), int(hd["GIFT_ESSENCE"])],
	])
	sec.call("Fear", [
		"The eyes by the clock show how jumpy the town is.",
		"Feeding on someone new and using powers raise it; sleeping and the Calm Town gift lower it.",
		"Higher fear makes people startle from further away (up to +%d%%) and flee faster (up to +%d%%)." % [int(round(float(hd["FEAR_STARTLE"][1]) * 100.0)), int(round(float(hd["FEAR_FLEE"][1]) * 100.0))],
	])
	_button("Back", func():
		_view = "main"
		sync(_g))


func _guide_text(parent: Control, text: String, size: int, color: Color) -> void:
	if text == "":
		return
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", _fs(size))
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(430, 0)
	parent.add_child(l)


# ---------------------------------------------------------------- save export / import

func _export_save() -> void:
	var name := "vcs-save-%s.json" % Time.get_datetime_string_from_system().replace(":", "").replace("-", "").replace("T", "-")
	if DisplayServer.has_feature(DisplayServer.FEATURE_NATIVE_DIALOG_FILE):
		DisplayServer.file_dialog_show("Export save", OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS), name, false, DisplayServer.FILE_DIALOG_MODE_SAVE_FILE, ["*.json ; JSON"], func(ok: bool, paths: PackedStringArray, _f: int):
			if ok and paths.size() > 0:
				_g.flow.export_save_to(paths[0])
				sync(_g))
	else:
		_g.flow.export_save_to("user://" + name)
		sync(_g)


func _import_save() -> void:
	if not DisplayServer.has_feature(DisplayServer.FEATURE_NATIVE_DIALOG_FILE):
		_g.flow.notices.append("Import needs a file dialog; put the file at user://import.json and try again.")
		var f0 := FileAccess.open("user://import.json", FileAccess.READ)
		if f0 != null:
			_g.flow.import_text(f0.get_as_text())
		sync(_g)
		return
	DisplayServer.file_dialog_show("Import save", OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS), "", false, DisplayServer.FILE_DIALOG_MODE_OPEN_FILE, ["*.json ; JSON"], func(ok: bool, paths: PackedStringArray, _f: int):
		if ok and paths.size() > 0:
			var f := FileAccess.open(paths[0], FileAccess.READ)
			if f == null or f.get_length() > SaveCodec.MAX_IMPORT:
				_g.flow.notices.append("Import failed (%s)." % ("E_SAVE_TOO_BIG" if f != null else "E_SAVE_PARSE"))
			else:
				_g.flow.import_text(f.get_as_text())
			sync(_g))


# ---------------------------------------------------------------- error screen

func _build_error() -> void:
	_clear()
	_panel.visible = true
	_place(false)
	_label("Something went wrong", 22, Color(0.9, 0.3, 0.3))
	_label(str(_g.last_error.get("code", "E_UNKNOWN")), 14, Color(1.0, 0.8, 0.4))
	_label(str(_g.last_error.get("message", "")), 13)
	_label("If a run was in progress it was saved. Copy the report below into a bug report.", 12, Color(0.6, 0.65, 0.8))
	_button("Copy report", func(): DisplayServer.clipboard_set(Log.report("%s: %s" % [_g.last_error.get("code", ""), _g.last_error.get("message", "")])))
	_button("Save log to file", func():
		var f := FileAccess.open("user://vcs-log.txt", FileAccess.WRITE)
		if f != null:
			f.store_string(Log.report())
			_g.flow.notices.append("Log saved to " + ProjectSettings.globalize_path("user://vcs-log.txt")))
	_button("Quit", func(): _g.get_tree().quit())


# ---------------------------------------------------------------- The Long Night (roguelike)

func has_trek_checkpoint() -> bool:
	return _g != null and _g.flow != null and _g.flow.store != null and _g.flow.store.has("trek")


## The roguelike meta, read from the `rogue` save on first use (or a fresh one).
func _tm() -> Dictionary:
	if trek_meta.is_empty():
		trek_meta = TrekMeta.create()
		if _g != null and _g.flow != null and _g.flow.store != null:
			var r: Dictionary = _g.flow.store.read("rogue")
			if r["ok"]:
				var mg := TrekMeta.migrate(r["v"], r["data"])
				var san: Variant = TrekMeta.sanitize(mg["data"]) if mg["ok"] else null
				if san != null:
					trek_meta = san
	return trek_meta


func _save_trek_meta() -> void:
	if _g != null and _g.flow != null and _g.flow.store != null:
		_g.flow.store.write("rogue", TrekMeta.SCHEMA, _tm())


## Show the Laid to Rest screen for a finished trek (result dict: see docs/ROGUELIKE.md "UI API").
func show_laid_to_rest(result: Dictionary) -> void:
	_rest_result = result
	_trek_view = "rest"
	if _g != null:
		sync(_g)


func hide_laid_to_rest() -> void:
	_trek_view = ""
	_rest_result = {}
	if _g != null:
		sync(_g)


## Open The Coffin (title view, or over the death screen when from_rest); Back returns to where it was opened.
func open_coffin(from_rest: bool = false) -> void:
	_coffin_back = "rest" if from_rest else "title"
	if from_rest:
		_trek_view = "coffin"
	else:
		_view = "coffin"
	_coffin_msg = ""
	if _g != null:
		sync(_g)


func _coffin_close() -> void:
	_coffin_msg = ""
	if _coffin_back == "rest" and not _rest_result.is_empty():
		_trek_view = "rest"
	else:
		_trek_view = ""
		_view = "main"
	sync(_g)


func _build_trek_overlay() -> void:
	_clear()
	_panel.visible = true
	_place(false)
	if _trek_view == "coffin":
		_build_coffin()
	else:
		_build_rest()


static func _roman(n: int) -> String:
	return ["0", "I", "II", "III", "IV", "V"][clampi(n, 0, 5)]


## Why an unlock is locked ("Needs Far Echo II"), or "" when its prerequisites are met.
static func locked_reason(meta: Dictionary, id: String) -> String:
	var r: Variant = TrekMeta.missing_prereq(meta, id)
	if r == null:
		return ""
	var pu: Variant = TrekMeta.unlock_by_id(r["id"])
	return "Needs %s %s" % [str(pu["name"]) if pu != null else str(r["id"]), _roman(int(r["tier"]))]


## Buy through TrekMeta, save, and remember the line shown on the shop: {ok, code, text}.
func coffin_buy(id: String) -> Dictionary:
	var meta := _tm()
	var u: Variant = TrekMeta.unlock_by_id(id)
	var r := TrekMeta.buy(meta, id)
	var text := ""
	match r["code"]:
		"OK":
			text = "You pack fresh soil into the lining. %s deepens." % str(u["name"])
			_save_trek_meta()
		"E_META_POOR":
			text = "Not enough Grave Soil. The coffin stays hungry."
		"E_META_LOCKED":
			text = "The lid will not lift yet. %s." % locked_reason(meta, id)
		"E_META_MAX":
			text = "Nothing more to pack in there."
		_:
			text = "The coffin does not know that."
	_coffin_msg = text
	return {"ok": r["ok"], "code": r["code"], "text": text}


func _build_coffin() -> void:
	var meta := _tm()
	_label("The Coffin", 22, Color(0.9, 0.85, 0.5))
	_label("Grave Soil: %d" % int(meta["soil"]), 15, Color(0.75, 0.6, 0.4))
	if _coffin_msg != "":
		_label(_coffin_msg, 13, Color(0.6, 0.85, 0.6))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(700, 380)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_box.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	scroll.add_child(grid)
	for u in TrekMeta._d()["upgrades"]:
		var id: String = u["id"]
		var t := TrekMeta.tier_of(meta, id)
		var mx := TrekMeta.max_tier(id)
		var cost := TrekMeta.cost_of(meta, id)
		var why := locked_reason(meta, id)
		var card := PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.07, 0.07, 0.1, 0.9)
		sb.set_content_margin_all(8)
		sb.set_corner_radius_all(4)
		sb.border_color = Color(0.4, 0.35, 0.25, 0.6) if why == "" else Color(0.3, 0.3, 0.35, 0.5)
		sb.set_border_width_all(1)
		card.add_theme_stylebox_override("panel", sb)
		card.custom_minimum_size = Vector2(340, 0)
		grid.add_child(card)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 3)
		card.add_child(v)
		_card_text(v, "%s   %s%s" % [u["name"], "●".repeat(t), "○".repeat(mx - t)], 15, Color(0.55, 0.58, 0.68) if why != "" else Color(1.0, 0.9, 0.7))
		_card_text(v, str(u.get("flavour", "")), 12, Color(0.6, 0.7, 0.6))
		_card_text(v, str(u["desc"][t]) if t < mx else str(u["desc"][mx - 1]) + " (max)", 12, Color(0.8, 0.85, 0.95))
		if cost < 0:
			_card_text(v, "Fully packed.", 12, Color(0.6, 0.65, 0.8))
		elif why != "":
			_card_text(v, "Locked: " + why, 12, Color(0.85, 0.5, 0.4))
		var b := _button("Max" if cost < 0 else "Buy %d Soil" % cost, func():
			coffin_buy(id)
			sync(_g), v)
		b.disabled = cost < 0 or why != "" or float(meta["soil"]) < cost
		b.name = "buy_" + id
	_button("Back", func(): _coffin_close())


func _card_text(parent: Control, text: String, size: int, color: Color) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", _fs(size))
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(320, 0)
	parent.add_child(l)


func _build_trek_stats() -> void:
	var meta := _tm()
	var st: Dictionary = meta["stats"]
	_label("Stats", 22, Color(0.9, 0.85, 0.5))
	var lines := [
		"Treks: %d" % int(st["treks"]), "Furthest from the Coffin: %.1f miles" % float(st["bestMiles"]),
		"Best stage: %d" % int(st["bestStage"]), "Stages reached: %d" % (meta["reached"] as Array).size(),
		"People fed: %d" % int(st["fedHumans"]), "Critters fed: %d" % int(st["fedCritters"]),
		"Died to the sun: %d" % int(st["deaths"]["sun"]), "Withered: %d" % int(st["deaths"]["withered"]),
		"Staked: %d" % int(st["deaths"]["staked"]), "Holy ground: %d" % int(st["deaths"]["holy"]),
		"Grave Soil earned: %d" % int(st["soilEarned"]), "Grave Soil now: %d" % int(meta["soil"])]
	for ln in lines:
		_label(ln, 14)
	_button("Back", func():
		_view = "main"
		sync(_g))


func _build_rest() -> void:
	var r := _rest_result
	var tx := TrekUi.rest_text(r)
	var tomb := IconRect.new("tomb", 100.0)
	tomb.custom_minimum_size = Vector2(140, 100)
	tomb.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_box.add_child(tomb)
	_label(tx["title"], 24, Color(0.5, 0.9, 0.6) if r.get("cause") == "victory" or r.get("cause") == "frontier" else Color(0.9, 0.3, 0.3))
	_label(tx["cause"], 15)
	_label(tx["tally"], 13, Color(0.7, 0.75, 0.9))
	for ln in tx["soil"]:
		_label(ln, 13, Color(0.85, 0.8, 0.6))
	_label(tx["total"], 16, Color(0.9, 0.85, 0.5))
	if tx["best"] != "":
		_label(tx["best"], 14, Color(0.5, 0.9, 0.6) if r.get("newBest") == true else Color(0.6, 0.65, 0.8))
	_button("Rise Again", func(): rise_again_requested.emit())
	_button("The Coffin", func(): open_coffin(true))
	_button("Title", func():
		hide_laid_to_rest()
		title_requested.emit())
