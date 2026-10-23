class_name TrekUi
extends Control
## The Long Night in-trek overlays (child of Menus as `menus.trek_ui`): stage card, dawn countdown / warning, the "Wait out
## the day" prompt and the waiting overlay. Text builders are static so they can be tested without a scene.
##
## API (see docs/ROGUELIKE.md "UI API"):
##   show_stage_card(index:int, stage_name:String, miles:float, time_of_day:="dusk", seconds:=4.0)
##   set_dawn(seconds_left:float)            # < 0 hides; <= WARN_SECONDS warns; <= 0 "The sun is up"
##   dawn_state() -> "hidden"|"calm"|"warning"|"sun"
##   show_wait_prompt(options:={}) / hide_wait_prompt()   # keys: title, body, wait_label, keep_label, on_wait, on_keep
##   show_waiting(blood:float, lines:Array) / update_waiting(blood, lines) / hide_waiting()
##   signals: wait_chosen, keep_looking_chosen, wait_interrupted
##   static: stage_card_text, dawn_text, rest_text

signal wait_chosen
signal keep_looking_chosen
signal wait_interrupted

const WARN_SECONDS := 90.0

var _card: Label
var _card_age: float = -1.0
var _card_len: float = 4.0
var _dawn: Label
var _dawn_left: float = -1.0
var _prompt: PanelContainer
var _prompt_box: VBoxContainer
var _waiting: PanelContainer
var _wait_blood: Label
var _wait_lines: Label
var _stir: Button
var _t: float = 0.0


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card = Label.new()
	_card.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_card.offset_top = 70.0
	_card.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_card.add_theme_font_size_override("font_size", 24)
	_card.add_theme_color_override("font_color", Color(0.92, 0.88, 0.7))
	_card.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.visible = false
	add_child(_card)
	_dawn = Label.new()
	_dawn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_dawn.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_dawn.offset_right = -14.0
	_dawn.offset_top = 10.0
	_dawn.add_theme_font_size_override("font_size", 16)
	_dawn.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_dawn.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dawn.visible = false
	add_child(_dawn)
	_prompt = _make_panel()
	_prompt_box = VBoxContainer.new()
	_prompt_box.add_theme_constant_override("separation", 10)
	_prompt.add_child(_prompt_box)
	_waiting = _make_panel()
	_waiting.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var wb := VBoxContainer.new()
	wb.add_theme_constant_override("separation", 8)
	_waiting.add_child(wb)
	var wt := Label.new()
	wt.text = "Waiting out the day"
	wt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wt.add_theme_font_size_override("font_size", 20)
	wb.add_child(wt)
	_wait_blood = Label.new()
	_wait_blood.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wb.add_child(_wait_blood)
	_wait_lines = Label.new()
	_wait_lines.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_wait_lines.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_wait_lines.custom_minimum_size = Vector2(360, 0)
	_wait_lines.add_theme_color_override("font_color", Color(0.6, 0.7, 0.85))
	wb.add_child(_wait_lines)
	var stir := Button.new()
	stir.text = "Stir"
	stir.name = "stir"
	_stir = stir
	stir.pressed.connect(func(): wait_interrupted.emit())
	wb.add_child(stir)


func _make_panel() -> PanelContainer:
	var p := PanelContainer.new()
	p.set_anchors_preset(Control.PRESET_CENTER)
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	p.grow_vertical = Control.GROW_DIRECTION_BOTH
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.03, 0.06, 0.92)
	sb.set_content_margin_all(22)
	sb.set_corner_radius_all(6)
	sb.border_color = Color(0.5, 0.55, 0.75, 0.5)
	sb.set_border_width_all(1)
	p.add_theme_stylebox_override("panel", sb)
	p.custom_minimum_size = Vector2(400, 0)
	p.visible = false
	add_child(p)
	return p


# ---------------------------------------------------------------- text builders

static func stage_card_text(index: int, stage_name: String, miles: float, time_of_day: String = "dusk") -> String:
	return "Stage %d: %s - %.1f miles - %s" % [index, stage_name, miles, time_of_day]


## "Dawn in 4:32", the warning form, or "The sun is up".
static func dawn_text(seconds_left: float) -> String:
	if seconds_left <= 0.0:
		return "The sun is up"
	var s := int(ceil(seconds_left))
	var t := "%d:%02d" % [s / 60, s % 60]
	return "Dawn is coming: %s" % t if seconds_left <= WARN_SECONDS else "Dawn in %s" % t


static func _place_phrase(stage_name: String) -> String:
	if stage_name == "":
		return "the road"
	return "the " + stage_name.substr(4) if stage_name.begins_with("The ") else stage_name


const SOIL_LABELS := {"miles": "Miles walked", "humans": "People fed", "critters": "Critters fed", "unseen": "Stages cleared unseen",
	"newBest": "New best stage", "pouch": "Soil Pouch", "victory": "The King's blood"}
const SOIL_ORDER := ["miles", "humans", "critters", "unseen", "newBest", "pouch", "victory"]


## Laid to Rest text for a result dict {cause, stageName, miles, humans, critters, unseen, newBest, soil_breakdown, soilTotal,
## bestMiles}: {title, cause, tally, soil: Array[String], total, best}.
static func rest_text(r: Dictionary) -> Dictionary:
	var cause := str(r.get("cause", ""))
	var where := _place_phrase(str(r.get("stageName", "")))
	var miles := "%.1f" % float(r.get("miles", 0.0))
	var line := ""
	var title := "Laid to Rest"
	match cause:
		"sun":
			line = "The sun found you at %s, %s miles from your coffin." % [where, miles]
		"withered":
			line = "You withered away at %s, %s miles from your coffin. Nobody noticed." % [where, miles]
		"staked":
			line = "A hunter found your heart at %s, %s miles from your coffin." % [where, miles]
		"holy":
			line = "Holy ground does not forgive. It took you at %s, %s miles from your coffin." % [where, miles]
		"frontier":
			title = "To be continued..."
			line = "The road goes on past %s, %s miles from your coffin, but the way is not yet laid. To be continued..." % [where, miles]
		"victory":
			title = "The Long Night Ends"
			line = "The King's blood is yours. You came %s miles from your coffin, and nothing is left to fear but morning." % miles
		_:
			line = "You fell at %s, %s miles from your coffin." % [where, miles]
	var tally := "Fed %d people and %d critters. %d stages cleared unseen." % [int(r.get("humans", 0)), int(r.get("critters", 0)), int(r.get("unseen", 0))]
	var soil: Array = []
	var bd: Variant = r.get("soil_breakdown")
	if bd is Dictionary:
		var keys: Array = []
		for k in SOIL_ORDER:
			if bd.has(k):
				keys.append(k)
		for k in bd.keys():
			if not keys.has(k):
				keys.append(k)
		for k in keys:
			var v: Variant = bd[k]
			if (v is float or v is int) and float(v) != 0.0:
				soil.append("%s: +%d" % [SOIL_LABELS.get(k, str(k)), int(v)])
			elif v is bool and v:
				soil.append(str(SOIL_LABELS.get(k, str(k))))
	var best := ""
	if r.get("newBest") == true:
		best = "A new best! Furthest yet: %.1f miles." % float(r.get("miles", 0.0))
	elif r.has("bestMiles"):
		best = "Best: %.1f miles." % float(r["bestMiles"])
	return {"title": title, "cause": line, "tally": tally, "soil": soil, "total": "Grave Soil gained: +%d" % int(r.get("soilTotal", 0)), "best": best}


# ---------------------------------------------------------------- widgets

func show_stage_card(index: int, stage_name: String, miles: float, time_of_day: String = "dusk", seconds: float = 4.0) -> void:
	_card.text = stage_card_text(index, stage_name, miles, time_of_day)
	_card_len = maxf(0.1, seconds)
	_card_age = 0.0
	_card.modulate.a = 1.0
	_card.visible = true


func stage_card_visible() -> bool:
	return _card.visible


func set_dawn(seconds_left: float) -> void:
	_dawn_left = seconds_left
	_dawn.visible = seconds_left >= 0.0
	if not _dawn.visible:
		return
	_dawn.text = dawn_text(seconds_left)
	_dawn.add_theme_color_override("font_color", Color(1.0, 0.45, 0.3) if seconds_left <= WARN_SECONDS else Color(0.8, 0.85, 0.95))


func dawn_state() -> String:
	if _dawn_left < 0.0:
		return "hidden"
	if _dawn_left <= 0.0:
		return "sun"
	return "warning" if _dawn_left <= WARN_SECONDS else "calm"


func show_wait_prompt(options: Dictionary = {}) -> void:
	for c in _prompt_box.get_children():
		_prompt_box.remove_child(c)
		c.queue_free()
	var t := Label.new()
	t.text = str(options.get("title", "The day is long"))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", 20)
	_prompt_box.add_child(t)
	var body := str(options.get("body", "Under a roof you could wait out the day. Prey may stir. Heat will rise."))
	if body != "":
		var bl := Label.new()
		bl.text = body
		bl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		bl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		bl.custom_minimum_size = Vector2(360, 0)
		_prompt_box.add_child(bl)
	var wait := Button.new()
	wait.text = str(options.get("wait_label", "Wait out the day"))
	wait.name = "wait"
	wait.pressed.connect(func():
		var cb: Variant = options.get("on_wait")
		hide_wait_prompt()
		if cb is Callable and cb.is_valid():
			cb.call()
		wait_chosen.emit())
	_prompt_box.add_child(wait)
	var keep := Button.new()
	keep.text = str(options.get("keep_label", "Keep looking"))
	keep.name = "keep"
	keep.pressed.connect(func():
		var cb: Variant = options.get("on_keep")
		hide_wait_prompt()
		if cb is Callable and cb.is_valid():
			cb.call()
		keep_looking_chosen.emit())
	_prompt_box.add_child(keep)
	# no keyboard focus on the prompt: Space (the ping) or Enter must never pick "Wait out the day" by accident
	wait.focus_mode = Control.FOCUS_CLICK
	keep.focus_mode = Control.FOCUS_CLICK
	_prompt.visible = true
	if is_inside_tree():
		var vp := get_viewport()
		if vp != null:
			vp.gui_release_focus()


func hide_wait_prompt() -> void:
	_prompt.visible = false


func wait_prompt_visible() -> bool:
	return _prompt.visible


func show_waiting(blood: float, lines: Array) -> void:
	update_waiting(blood, lines)
	_waiting.visible = true
	if is_inside_tree():
		_stir.grab_focus.call_deferred()   # Space / Enter on the focused button stirs; the mouse is kept visible by RogueMode


func update_waiting(blood: float, lines: Array) -> void:
	_wait_blood.text = "Blood: %d" % int(round(blood))
	var out: Array = lines.duplicate()
	if out.is_empty():
		out.append("Listening...")
	_wait_lines.text = "\n".join(PackedStringArray(out.map(func(x): return str(x))))


func hide_waiting() -> void:
	_waiting.visible = false


func waiting_visible() -> bool:
	return _waiting.visible


func waiting_text() -> String:
	return _wait_blood.text + "\n" + _wait_lines.text


func _process(dt: float) -> void:
	_t += dt
	if _card_age >= 0.0:
		_card_age += dt
		var left := _card_len - _card_age
		_card.modulate.a = clampf(left / 0.8, 0.0, 1.0)
		if left <= 0.0:
			_card_age = -1.0
			_card.visible = false
	if _dawn.visible and _dawn_left <= WARN_SECONDS:
		_dawn.modulate.a = 0.65 + 0.35 * sin(_t * 5.0)
	else:
		_dawn.modulate.a = 1.0
