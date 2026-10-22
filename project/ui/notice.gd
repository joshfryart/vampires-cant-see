extends Control
## The "Heads up" notice overlay (js index.html #notice): a bullet list in a panel at the top centre, non-pausing, over any screen
## including play. It drains g.flow.notices every frame, so messages stack until OK is pressed.
## While the mouse is captured (playing) the OK button cannot be clicked, so the panel dismisses itself after AUTO_HIDE seconds;
## with a visible mouse (menus, pause, F9 panel) it stays until OK. Tab/Enter also work: the button is focusable.

const AUTO_HIDE := 10.0

var _g: Node
var _items: Array = []
var _panel: PanelContainer
var _list: VBoxContainer
var _title: Label
var _ok: Button
var _age: float = 0.0
var _large: bool = false


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel = PanelContainer.new()
	_panel.anchor_left = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_top = 0.0
	_panel.anchor_bottom = 0.0
	_panel.grow_vertical = Control.GROW_DIRECTION_END
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.04, 0.08, 0.95)
	sb.set_content_margin_all(12)
	sb.set_corner_radius_all(6)
	sb.border_color = Color(1.0, 0.8, 0.4, 0.7)
	sb.set_border_width_all(1)
	_panel.add_theme_stylebox_override("panel", sb)
	add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_panel.add_child(box)
	_title = Label.new()
	_title.text = "Heads up"
	_title.add_theme_color_override("font_color", Color(1.0, 0.8, 0.4))
	box.add_child(_title)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 3)
	box.add_child(_list)
	_ok = Button.new()
	_ok.text = "OK"
	_ok.focus_mode = Control.FOCUS_ALL
	_ok.size_flags_horizontal = Control.SIZE_SHRINK_END
	_ok.pressed.connect(dismiss)
	box.add_child(_ok)
	_panel.visible = false
	_layout()


func attach(g: Node) -> void:
	_g = g


## Add messages directly (also used by tests).
func push(msgs: Array) -> void:
	for m in msgs:
		_items.append(str(m))
	_rebuild()


func dismiss() -> void:
	_items.clear()
	_rebuild()


func is_showing() -> bool:
	return _panel.visible


func items() -> Array:
	return _items


func _layout() -> void:
	var w: float = minf(maxf(size.x, 640.0) - 32.0, 520.0)
	if is_inside_tree() and size.x > 0.0:
		w = minf(size.x - 32.0, 520.0)
	_panel.offset_left = -w / 2.0
	_panel.offset_right = w / 2.0
	_panel.offset_top = 12.0
	_panel.offset_bottom = 12.0


func _rebuild() -> void:
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	var fs := int(round(11.0 * (1.3 if _large else 1.0)))
	for m in _items:
		var l := Label.new()
		l.text = "- " + str(m)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(maxf(100.0, _panel.offset_right - _panel.offset_left - 24.0), 0)
		l.add_theme_font_size_override("font_size", fs)
		l.add_theme_color_override("font_color", Color(0.9, 0.93, 1.0))
		_list.add_child(l)
	_title.add_theme_font_size_override("font_size", fs + 2)
	_ok.add_theme_font_size_override("font_size", fs)
	_panel.visible = not _items.is_empty()
	_panel.reset_size()
	_age = 0.0


func _process(delta: float) -> void:
	if _g == null:
		return
	var flow: Variant = _g.get("flow")
	var large: bool = _g.get("large_text") == true
	var changed := large != _large
	_large = large
	if flow != null and not (flow.notices as Array).is_empty():
		for m in flow.notices:
			_items.append(str(m))
		(flow.notices as Array).clear()
		changed = true
	_layout()
	if changed:
		_rebuild()
	if _panel.visible and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_age += delta
		if _age >= AUTO_HIDE:
			dismiss()
