class_name Hud
extends Control
## Window-resolution overlay: subtitles (listening at windows and villager barks), the "not saved" dot and the F3 debug text.
## The line HUD (vial, dial, powers, cards, hints) is HudView inside the 640x360 viewport.

const POWER_KEYS := {"shriek": "Q", "mist": "Sh", "still": "F"}

var _debug: bool = false
var _text: String = ""
var _sub_de: String = ""
var _sub_en: String = ""
var _sub_muffled: bool = false
var _sub_a: float = 0.0
var _unsaved: bool = false


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_state(g: Node) -> void:
	_sub_a = 0.0
	var ls: Variant = g.listen_st.sub if g.listen_st != null else null
	if ls != null:
		_sub_de = ls["de"]
		_sub_en = ls["en"]
		_sub_muffled = ls["muffled"]
		_sub_a = Listen.sub_alpha(ls, g.clock)
	elif g.bark_sub != null:
		var bs: Dictionary = g.bark_sub
		_sub_de = bs["de"]
		_sub_en = bs["en"]
		_sub_muffled = false
		_sub_a = Listen.sub_alpha(bs, g.clock)
	_unsaved = g.flow != null and g.flow.save_failed
	if _debug:
		_text = "t %.2f  pos %.2f,%.2f  angle %.2f  pulses %d  people %d  echoes %d  light %.2f  state %s  canvas %d us" % [g.clock, g.player.x, g.player.y, g.player.angle, g.sonar.pulses.size(), g.people.people.size(), g.people.echoes.size(), g.player_lit, g.state, g.echo_view.last_us]
	queue_redraw()


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F3:
		_debug = not _debug


func _draw() -> void:
	var w: float = size.x
	var h: float = size.y
	var font := ThemeDB.fallback_font
	if _sub_a > 0.0 and _sub_de != "":
		var col2 := Color(0.56, 0.63, 0.72, _sub_a * 0.95) if _sub_muffled else Color(1.0, 0.96, 0.84, _sub_a * 0.95)
		draw_string(font, Vector2(0, h * 0.74), _sub_de, HORIZONTAL_ALIGNMENT_CENTER, w, 20, col2)
		if _sub_en != "":
			draw_string(font, Vector2(0, h * 0.74 + 22.0), _sub_en, HORIZONTAL_ALIGNMENT_CENTER, w, 15, Color(0.72, 0.78, 0.88, _sub_a * 0.9))
	if _unsaved:
		draw_circle(Vector2(w - 24.0, h - 20.0), 5.0, Color(1.0, 0.54, 0.47, 0.7))
		draw_string(font, Vector2(w - 120.0, h - 15.0), "not saved", HORIZONTAL_ALIGNMENT_RIGHT, 80.0, 12, Color(1.0, 0.54, 0.47, 0.7))
	if _debug:
		draw_string(font, Vector2(16, 24), _text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.8, 0.9, 1.0, 0.9))
