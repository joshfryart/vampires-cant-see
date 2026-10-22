class_name Menus
extends Control
## Menu panels over the game (js index.html overlays): title menu with shop and stats, pause, boon and gift choices, run end,
## and the notice list. Built in code; sync(g) shows the panel for the game's state. Phase 8 restyles these.

var _g: Game
var _view: String = "main"
var _panel: PanelContainer
var _box: VBoxContainer
var _last_key: String = ""


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
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	(parent if parent != null else _box).add_child(b)
	return b


## Show the panel that belongs to the game's current state.
func sync(g: Game) -> void:
	_g = g
	var st: String = g.state
	var key := "%s/%s" % [st, _view]
	if st != "title":
		_view = "main"
		key = st
	match st:
		"title": _build_title()
		"paused": _build_pause()
		"boon": _build_choice("A gift of the night", g.flow.run["pendingBoons"], true)
		"gift": _build_choice("Blood gift", g.flow.run["pendingGifts"], false)
		"runend": _build_runend()
		_: _panel.visible = false
	_last_key = key


func _build_title() -> void:
	_clear()
	_panel.visible = true
	match _view:
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
		_button("New run (abandons the saved run)", func():
			_g.flow.store.remove("run")
			_g.flow.has_run = false
			_g.flow.begin_run())
	else:
		_button("New run", func(): _g.flow.begin_run())
	_button("Shop (Essence %d)" % int(_g.flow.meta["essence"]), func():
		_view = "shop"
		sync(_g))
	_button("Stats", func():
		_view = "stats"
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
		_label("%s: %d" % [k, int(st[k])], 14)
	_button("Back", func():
		_view = "main"
		sync(_g))


func _build_pause() -> void:
	_clear()
	_panel.visible = true
	_label("Paused", 24)
	_button("Resume", func(): _g.resume())
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
