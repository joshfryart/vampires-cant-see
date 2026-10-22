class_name CreatorScreen
extends Control
## The character creator (js tools/character-creator.html): edit a villager's look field by field, apply an archetype preset or
## randomize, preview it in any pose with the real figure renderer, and keep a named list as JSON in user://creator.json.
## Logic lives in core/creator.gd (parity tested); this is the UI around it.

var _g: Game
var _look: Dictionary = Creator.sanitize({})["look"]
var _view: Dictionary = Creator.sanitize_view({})
var _seed: int = 0
var _name: String = "Unnamed"
var _saved: Array = []
var _t: float = 0.0
var _yaw_spin: float = 0.0

var _preview: Control
var _rs := RenderState.new()
var _canvas := DrawCanvas.new()
var _controls: Dictionary = {}
var _arch: OptionButton
var _seed_box: SpinBox
var _name_edit: LineEdit
var _saved_pick: OptionButton
var _status: Label
var _locks: Dictionary = {}


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false


func attach(g: Game) -> void:
	_g = g
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.02, 0.04, 1.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var root := HBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 10.0
	root.offset_top = 10.0
	root.offset_right = -10.0
	root.offset_bottom = -10.0
	root.add_theme_constant_override("separation", 12)
	add_child(root)
	var left := ScrollContainer.new()
	left.custom_minimum_size = Vector2(330, 0)
	left.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(left)
	var lbox := VBoxContainer.new()
	lbox.custom_minimum_size = Vector2(310, 0)
	lbox.add_theme_constant_override("separation", 4)
	left.add_child(lbox)
	_build_fields(lbox)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 6)
	root.add_child(right)
	var clip := Control.new()
	clip.custom_minimum_size = Vector2(960, 540)
	clip.clip_contents = true
	right.add_child(clip)
	_preview = Control.new()
	_preview.custom_minimum_size = Vector2(640, 360)
	_preview.size = Vector2(640, 360)
	_preview.scale = Vector2(1.5, 1.5)
	_preview.draw.connect(_draw_preview)
	clip.add_child(_preview)
	_build_toolbar(right)
	_saved = Creator.load_store()
	_refresh_saved()
	_sync_fields()


func open() -> void:
	visible = true
	_g.menus.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_sync_fields()


func close() -> void:
	visible = false
	_g.menus.visible = true
	_g.menus.sync(_g)


func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()


# ---------------------------------------------------------------- building

func _head(box: Container, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 15)
	l.add_theme_color_override("font_color", Color(0.9, 0.85, 0.5))
	box.add_child(l)


func _btn(box: Container, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	box.add_child(b)
	return b


func _build_fields(box: VBoxContainer) -> void:
	_head(box, "Character creator")
	_btn(box, "Back (Esc)", close)
	var group := ""
	for f in Creator.fields():
		if f["group"] != group:
			group = f["group"]
			_head(box, group)
		var key: String = f["key"]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		box.add_child(row)
		var lock := CheckBox.new()
		lock.tooltip_text = "Lock this field when randomizing"
		lock.focus_mode = Control.FOCUS_NONE
		lock.toggled.connect(func(on): _locks[key] = on)
		row.add_child(lock)
		var l := Label.new()
		l.text = f["label"]
		l.tooltip_text = f["hint"]
		l.custom_minimum_size = Vector2(90, 0)
		row.add_child(l)
		match f["type"]:
			"num":
				var sl := HSlider.new()
				sl.min_value = f["min"]
				sl.max_value = f["max"]
				sl.step = f["step"]
				sl.custom_minimum_size = Vector2(110, 0)
				sl.focus_mode = Control.FOCUS_NONE
				row.add_child(sl)
				var val := Label.new()
				val.custom_minimum_size = Vector2(40, 0)
				row.add_child(val)
				sl.value_changed.connect(func(v):
					val.text = "%.2f" % v
					_edit(key, v))
				_controls[key] = {"w": sl, "val": val}
			"bool":
				var cb := CheckBox.new()
				cb.focus_mode = Control.FOCUS_NONE
				cb.toggled.connect(func(on): _edit(key, on))
				row.add_child(cb)
				_controls[key] = {"w": cb}
			_:
				var ob := OptionButton.new()
				for v in f["values"]:
					ob.add_item(str(v))
				ob.focus_mode = Control.FOCUS_NONE
				ob.item_selected.connect(func(i): _edit(key, ob.get_item_text(i)))
				row.add_child(ob)
				_controls[key] = {"w": ob}


func _build_toolbar(box: VBoxContainer) -> void:
	var r1 := HBoxContainer.new()
	r1.add_theme_constant_override("separation", 6)
	box.add_child(r1)
	_arch = OptionButton.new()
	for a in Creator.archetypes():
		_arch.add_item(str(a["label"]))
		_arch.set_item_metadata(_arch.item_count - 1, a["id"])
	_arch.focus_mode = Control.FOCUS_NONE
	r1.add_child(_arch)
	_seed_box = SpinBox.new()
	_seed_box.min_value = 0
	_seed_box.max_value = 65535
	_seed_box.value_changed.connect(func(v): _seed = int(v))
	r1.add_child(_seed_box)
	_btn(r1, "Preset", func():
		_look = Creator.preset(_arch.get_item_metadata(_arch.selected), _seed)
		_sync_fields())
	_btn(r1, "Randomize", func(): _randomize("wild"))
	_btn(r1, "Random archetype", func(): _randomize("archetype"))
	var r2 := HBoxContainer.new()
	r2.add_theme_constant_override("separation", 6)
	box.add_child(r2)
	var pose := OptionButton.new()
	for p in Creator.POSES:
		pose.add_item(p[1])
	pose.focus_mode = Control.FOCUS_NONE
	pose.item_selected.connect(func(i): _view["pose"] = Creator.POSES[i][0])
	r2.add_child(pose)
	var fx := OptionButton.new()
	for t in ["Effects 0", "Effects 1", "Effects 2"]:
		fx.add_item(t)
	fx.select(2)
	fx.focus_mode = Control.FOCUS_NONE
	fx.item_selected.connect(func(i): _view["fx"] = i)
	r2.add_child(fx)
	for spec in [["Spin", "spin"], ["Play", "play"], ["Rim light", "rim"], ["Reduced", "reduced"], ["Restrain", "restrain"]]:
		var cb := CheckBox.new()
		cb.text = spec[0]
		cb.button_pressed = _view[spec[1]]
		cb.focus_mode = Control.FOCUS_NONE
		var k: String = spec[1]
		cb.toggled.connect(func(on): _view[k] = on)
		r2.add_child(cb)
	var r3 := HBoxContainer.new()
	r3.add_theme_constant_override("separation", 6)
	box.add_child(r3)
	for spec in [["Yaw", "yaw", -PI, PI, 0.05], ["Distance", "dist", 1.2, 5.0, 0.05], ["Struggle", "struggle", 0.0, 1.0, 0.05]]:
		var l := Label.new()
		l.text = spec[0]
		r3.add_child(l)
		var sl := HSlider.new()
		sl.min_value = spec[2]
		sl.max_value = spec[3]
		sl.step = spec[4]
		sl.value = _view[spec[1]]
		sl.custom_minimum_size = Vector2(120, 0)
		sl.focus_mode = Control.FOCUS_NONE
		var k: String = spec[1]
		sl.value_changed.connect(func(v): _view[k] = v)
		r3.add_child(sl)
	var r4 := HBoxContainer.new()
	r4.add_theme_constant_override("separation", 6)
	box.add_child(r4)
	_name_edit = LineEdit.new()
	_name_edit.text = _name
	_name_edit.custom_minimum_size = Vector2(180, 0)
	_name_edit.text_changed.connect(func(t): _name = t)
	r4.add_child(_name_edit)
	_btn(r4, "Save", _save)
	_saved_pick = OptionButton.new()
	_saved_pick.focus_mode = Control.FOCUS_NONE
	r4.add_child(_saved_pick)
	_btn(r4, "Load", _load_selected)
	_btn(r4, "Delete", _delete_selected)
	_btn(r4, "Export", _export)
	_btn(r4, "Import", _import)
	_btn(r4, "Copy spec", func():
		DisplayServer.clipboard_set(JSON.stringify(Creator.to_spec(Creator.character(_name, _look, {"archetype": _look["archetype"], "seed": _seed})))))
	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 12)
	box.add_child(_status)


# ---------------------------------------------------------------- state

func _edit(key: String, value: Variant) -> void:
	_look = Creator.set_field(_look, key, value)
	_sync_fields(key)


## Push the look into every control without firing their signals; skip the control being dragged.
func _sync_fields(skip: String = "") -> void:
	for key in _controls:
		if key == skip:
			continue
		var w: Control = _controls[key]["w"]
		var v: Variant = Creator.get_field(_look, key)
		if w is HSlider:
			(w as HSlider).set_value_no_signal(float(v))
			(_controls[key]["val"] as Label).text = "%.2f" % float(v)
		elif w is CheckBox:
			(w as CheckBox).set_pressed_no_signal(v == true)
		elif w is OptionButton:
			var ob := w as OptionButton
			for i in ob.item_count:
				if ob.get_item_text(i) == str(v):
					ob.select(i)
	if _arch != null:
		for i in _arch.item_count:
			if _arch.get_item_metadata(i) == _look["archetype"]:
				_arch.select(i)
	if _seed_box != null:
		_seed_box.set_value_no_signal(_seed)


func _randomize(mode: String) -> void:
	var locks: Array = []
	for k in _locks:
		if _locks[k]:
			locks.append(k)
	if mode == "archetype":
		_look["archetype"] = _arch.get_item_metadata(_arch.selected)
	var r := Creator.randomize(_look, mode, locks)
	_look = r["look"]
	_seed = int(r["seed"])
	_sync_fields()


func _say(text: String) -> void:
	_status.text = text


func _refresh_saved() -> void:
	_saved_pick.clear()
	for c in _saved:
		_saved_pick.add_item(str(c["name"]))


func _save() -> void:
	var c := Creator.character(_name, _look, {"archetype": _look["archetype"], "seed": _seed})
	_saved = Creator.upsert(_saved, c)
	_name = c["name"]
	_name_edit.text = _name
	_say("Saved %s (%s)." % [_name, "ok" if Creator.save_store(_saved) else "could not write the file"])
	_refresh_saved()


func _load_selected() -> void:
	if _saved_pick.item_count == 0:
		return
	var c: Dictionary = _saved[_saved_pick.selected]
	_look = c["look"].duplicate()
	_seed = int(c["seed"])
	_name = c["name"]
	_name_edit.text = _name
	_sync_fields()
	_say("Loaded " + _name)


func _delete_selected() -> void:
	if _saved_pick.item_count == 0:
		return
	var n: String = _saved[_saved_pick.selected]["name"]
	_saved = Creator.remove(_saved, n)
	Creator.save_store(_saved)
	_refresh_saved()
	_say("Deleted " + n)


func _export() -> void:
	var text := Creator.export_json(_saved if not _saved.is_empty() else [Creator.character(_name, _look, {"seed": _seed})])
	var fname := "vcs-characters.json"
	if DisplayServer.has_feature(DisplayServer.FEATURE_NATIVE_DIALOG_FILE):
		DisplayServer.file_dialog_show("Export characters", OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS), fname, false, DisplayServer.FILE_DIALOG_MODE_SAVE_FILE, ["*.json ; JSON"], func(ok: bool, paths: PackedStringArray, _f: int):
			if ok and paths.size() > 0:
				var f := FileAccess.open(paths[0], FileAccess.WRITE)
				if f != null:
					f.store_string(text)
					_say("Exported to " + paths[0].get_file()))
	else:
		var f := FileAccess.open("user://" + fname, FileAccess.WRITE)
		if f != null:
			f.store_string(text)
			_say("Exported to user://" + fname)


func _import() -> void:
	var take := func(text: String) -> void:
		var r := Creator.import_json(text)
		if not r["ok"]:
			_say("Import failed (%s)." % r["code"])
			return
		for c in r["list"]:
			_saved = Creator.upsert(_saved, c)
		Creator.save_store(_saved)
		_refresh_saved()
		_say("Imported %d character(s), skipped %d." % [(r["list"] as Array).size(), int(r["skipped"])])
	if DisplayServer.has_feature(DisplayServer.FEATURE_NATIVE_DIALOG_FILE):
		DisplayServer.file_dialog_show("Import characters", OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS), "", false, DisplayServer.FILE_DIALOG_MODE_OPEN_FILE, ["*.json ; JSON"], func(ok: bool, paths: PackedStringArray, _f: int):
			if ok and paths.size() > 0:
				var f := FileAccess.open(paths[0], FileAccess.READ)
				if f != null:
					take.call(f.get_as_text()))
	else:
		var f2 := FileAccess.open("user://import-characters.json", FileAccess.READ)
		if f2 != null:
			take.call(f2.get_as_text())
		else:
			_say("Put the file at user://import-characters.json")


# ---------------------------------------------------------------- preview

func _process(delta: float) -> void:
	if not visible:
		return
	if _view["play"]:
		_t += delta * float(_view["speed"])
	if _view["spin"]:
		_view["yaw"] = fposmod(float(_view["yaw"]) + delta * 0.8 + PI, TAU) - PI
	_preview.queue_redraw()


func _draw_preview() -> void:
	var v: Dictionary = _view
	_rs.reduced = v["reduced"]
	_rs.fx = int(v["fx"])
	var pe := Creator.pose_echo(v["pose"], _look, {"t": _t, "reduced": v["reduced"], "yaw": v["yaw"], "dist": v["dist"], "struggle": v["struggle"], "restrain": v["restrain"]})
	var o := {"quality": int(v["quality"]), "t": _t, "age": -1.0, "b": 1.0, "fx": int(v["fx"]), "player": {"x": 0.0, "y": 0.0, "angle": 0.0}}
	if v["rim"]:
		o["lights"] = [{"x": float(pe["echo"]["x"]) - 1.0, "y": 1.6, "radius": 3.0}]
	if pe["lock"] != null:
		o["lock"] = pe["lock"]
	_canvas.reset()
	_canvas.fill_style = "#05060a"
	_canvas.fill_rect(0, 0, 640, 360)
	EchoLayer.draw_solo(_rs, _canvas, pe["echo"], o)
	_canvas.paint(_preview)
