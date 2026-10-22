class_name DevPanel
extends Control
## The F9 developer panel (js devpanel.js, trimmed to what the port has): feature flags and tunables, a villager spawner,
## night clock and blood shortcuts, map jumps and the log tail. Debug builds only.

var _g: Game
var _panel: PanelContainer
var _log: Label
var _arch: OptionButton
var _map: OptionButton
var _t_log: float = 0.0
var _fps: Label
var _status: Label
var _search: LineEdit
var _json: TextEdit
var _patch: LineEdit
## [{q: lowercase search text, nodes: [Control]}] for the search filter.
var _rows: Array = []
## id -> control, so Reset and Apply can move them.
var _sliders: Dictionary = {}
var _checks: Dictionary = {}


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


func attach(g: Game) -> void:
	_g = g
	_panel = PanelContainer.new()
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.anchor_top = 0.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = -330.0
	_panel.offset_right = -8.0
	_panel.offset_top = 8.0
	_panel.offset_bottom = -8.0
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.04, 0.08, 0.93)
	sb.set_content_margin_all(10)
	sb.border_color = Color(0.4, 0.6, 0.9, 0.5)
	sb.set_border_width_all(1)
	_panel.add_theme_stylebox_override("panel", sb)
	add_child(_panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel.add_child(scroll)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(300, 0)
	box.add_theme_constant_override("separation", 5)
	scroll.add_child(box)
	_head(box, "Developer panel (F9)")
	_fps = Label.new()
	box.add_child(_fps)
	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 11)
	box.add_child(_status)
	_search = LineEdit.new()
	_search.placeholder_text = "Search flags and tunables"
	_search.clear_button_enabled = true
	_search.text_changed.connect(func(_t): _apply_filter())
	box.add_child(_search)
	_head(box, "Flags")
	Flags.get_flag("dev.showFps")
	for id in Flags.flag_info:
		var cb := CheckBox.new()
		cb.text = "%s: %s" % [id, Flags.flag_info[id]["desc"]]
		cb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		cb.focus_mode = Control.FOCUS_NONE
		cb.button_pressed = Flags.get_flag(id)
		var fid: String = id
		cb.toggled.connect(func(on): Flags.set_flag(fid, on))
		box.add_child(cb)
		_checks[id] = cb
		_rows.append({"q": ("%s %s" % [id, Flags.flag_info[id]["desc"]]).to_lower(), "nodes": [cb]})
	_head(box, "Tunables")
	for id in Flags.tun_info:
		var info: Dictionary = Flags.tun_info[id]
		var l := Label.new()
		l.text = "%s: %s" % [id, info["desc"]]
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(l)
		var row := HBoxContainer.new()
		box.add_child(row)
		var sl := HSlider.new()
		sl.min_value = info["min"]
		sl.max_value = info["max"]
		sl.step = info["step"]
		sl.value = Flags.tuns[id]
		sl.custom_minimum_size = Vector2(150, 0)
		sl.focus_mode = Control.FOCUS_NONE
		row.add_child(sl)
		var val := Label.new()
		val.text = str(sl.value)
		row.add_child(val)
		var tid: String = id
		sl.value_changed.connect(func(v):
			val.text = str(snappedf(v, 0.001))
			Flags.set_tun(tid, v))
		var rb := Button.new()
		rb.text = "reset"
		rb.focus_mode = Control.FOCUS_NONE
		rb.pressed.connect(func():
			Flags.reset_tun(tid)
			sl.value = Flags.tuns[tid])
		row.add_child(rb)
		_sliders[id] = sl
		_rows.append({"q": ("%s %s" % [id, info["desc"]]).to_lower(), "nodes": [l, row]})
	_btn(box, "Reset all flags and tunables", func():
		Flags.reset_all()
		_refresh_controls()
		_say("Everything reset"))
	_head(box, "Settings JSON")
	_json = TextEdit.new()
	_json.custom_minimum_size = Vector2(290, 70)
	_json.placeholder_text = "Paste settings JSON here, then Apply"
	box.add_child(_json)
	_btn(box, "Copy settings", func():
		var txt := JSON.stringify(Flags.to_json(), " ")
		_json.text = txt
		DisplayServer.clipboard_set(txt)
		_say("Copied settings"))
	_btn(box, "Apply settings", func():
		var n := Flags.from_json(_json.text)
		_refresh_controls()
		_say("Applied %d setting(s)" % n))
	_head(box, "Villagers")
	_arch = OptionButton.new()
	for id in Forge.list_ids():
		_arch.add_item(str(id))
	box.add_child(_arch)
	_btn(box, "Spawn ahead", _spawn)
	_btn(box, "Despawn nearest", _despawn)
	_patch = LineEdit.new()
	_patch.placeholder_text = "Look patch JSON, e.g. {\"hat\":\"tall\"}"
	box.add_child(_patch)
	_btn(box, "Alter nearest", _alter)
	_head(box, "Night")
	for hm in [[20, 0], [23, 0], [2, 0], [4, 30], [5, 30]]:
		var h: int = hm[0]
		var m: int = hm[1]
		_btn(box, "Clock %02d:%02d" % [h, m], func():
			if _g.night != null:
				_g.night.skip_to(h, m))
	_btn(box, "Blood full", func():
		if _g.night != null:
			_g.night.blood = _g.night.blood_max)
	_btn(box, "Blood 20", func():
		if _g.night != null:
			_g.night.blood = 20.0)
	_btn(box, "+50 Essence", func():
		_g.flow.meta["essence"] = int(_g.flow.meta["essence"]) + 50
		_g.flow.save_meta())
	_head(box, "Maps")
	_map = OptionButton.new()
	for n in _g.world_names:
		_map.add_item(str(n))
	box.add_child(_map)
	_btn(box, "Go to map", func(): _g.debug_map(_map.get_item_text(_map.selected)))
	_head(box, "Log")
	_log = Label.new()
	_log.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	_log.add_theme_font_size_override("font_size", 10)
	box.add_child(_log)
	_btn(box, "Copy error report", func():
		DisplayServer.clipboard_set(Log.report())
		_say("Report copied"))


func _say(t: String) -> void:
	if _status != null:
		_status.text = t


func _apply_filter() -> void:
	var q := _search.text.strip_edges().to_lower()
	for r in _rows:
		var show: bool = q == "" or str(r["q"]).contains(q)
		for n in r["nodes"]:
			(n as Control).visible = show


## Move every control to the current Flags values (after Reset all or Apply).
func _refresh_controls() -> void:
	for id in _checks:
		(_checks[id] as CheckBox).set_pressed_no_signal(Flags.get_flag(id))
	for id in _sliders:
		(_sliders[id] as HSlider).value = Flags.tuns[id]


## Patch the nearest villager's look (Forge.alter via People.alter) from the JSON in the patch box.
func _alter() -> void:
	if _g.people == null or _g.player == null:
		return
	var j := JSON.new()
	if j.parse(_patch.text) != OK or not (j.data is Dictionary):
		_say("Alter: patch must be a JSON object")
		return
	var best: Variant = null
	var bd := INF
	for q in _g.people.people:
		var d: float = Vector2(q.x - _g.player.x, q.y - _g.player.y).length()
		if d < bd:
			bd = d
			best = q
	if best == null:
		_say("Alter: nobody nearby")
		return
	var r: Dictionary = _g.people.alter(best.id, j.data)
	_say("Alter %s: %s" % [str(best.id), str(r.get("code"))])


func _head(box: VBoxContainer, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", Color(0.9, 0.85, 0.5))
	box.add_child(l)


func _btn(box: VBoxContainer, text: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	box.add_child(b)


func _spawn() -> void:
	if _g.people == null or _arch.item_count == 0:
		return
	var p := _g.player
	var at := {"x": p.x + cos(p.angle) * 1.5, "y": p.y + sin(p.angle) * 1.5}
	var r: Dictionary = _g.people.spawn(_g.world, {"archetype": _arch.get_item_text(_arch.selected), "seed": randi()}, at)
	Log.info("dev", "spawn %s -> %s" % [_arch.get_item_text(_arch.selected), str(r.get("code", "ok"))])


func _despawn() -> void:
	if _g.people == null:
		return
	var best: Variant = null
	var bd := INF
	for q in _g.people.people:
		var d: float = Vector2(q.x - _g.player.x, q.y - _g.player.y).length()
		if d < bd:
			bd = d
			best = q
	if best != null:
		_g.people.despawn(best.id)


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F9 and OS.is_debug_build() and _g != null:
		visible = not visible
		if visible:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		elif _g.state == "playing" or _g.state == "feeding":
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _process(delta: float) -> void:
	if not visible or _log == null:
		return
	_fps.text = "FPS %d" % Engine.get_frames_per_second()
	_t_log += delta
	if _t_log < 0.5:
		return
	_t_log = 0.0
	var out := PackedStringArray()
	for l in Log.lines.slice(-14):
		out.append("%.1f %s %s: %s" % [l["t"], l["level"], l["tag"], l["msg"]])
	_log.text = "\n".join(out)
