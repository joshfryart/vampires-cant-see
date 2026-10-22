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
var _show_sub: bool = true
var _show_en: bool = true
## Warm sense halos (js drawWarm): [x fraction of width, y fraction of height, radius fraction of height, alpha].
var _warm: Array = []
var _warm_tex: GradientTexture2D


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.54, 0.47, 1.0))
	grad.set_color(1, Color(1.0, 0.54, 0.47, 0.0))
	_warm_tex = GradientTexture2D.new()
	_warm_tex.gradient = grad
	_warm_tex.fill = GradientTexture2D.FILL_RADIAL
	_warm_tex.fill_from = Vector2(0.5, 0.5)
	_warm_tex.fill_to = Vector2(1.0, 0.5)
	_warm_tex.width = 128
	_warm_tex.height = 128


func set_state(g: Node) -> void:
	_sub_a = 0.0
	_show_sub = g.show_subtitles
	_show_en = g.show_translation
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
	_warm = _warm_halos(g)
	if _debug:
		_text = "t %.2f  pos %.2f,%.2f  angle %.2f  pulses %d  people %d  echoes %d  light %.2f  state %s  canvas %d us" % [g.clock, g.player.x, g.player.y, g.player.angle, g.sonar.pulses.size(), g.people.people.size(), g.people.echoes.size(), g.player_lit, g.state, g.echo_view.last_us]
	queue_redraw()


## Warm sense: soft coral halos on nearby people, drawn over walls (seen through them). Returns the halos to draw.
static func _warm_halos(g: Node) -> Array:
	var out: Array = []
	if g.state != "playing" and g.state != "feeding":
		return out
	if g.flow == null or g.flow.run == null or g.people == null:
		return out
	var rad: float = g.flow.fxv("warmRadius")
	if rad <= 0.0:
		return out
	var tan_half: float = tan(g.fov_now() / 2.0)
	var ca: float = cos(g.player.angle)
	var sa: float = sin(g.player.angle)
	var hy_frac: float = g.echo_view.rs.horizon / float(g.echo_view.rs.oh)
	for p in g.people.people:
		var dx: float = p.x - g.player.x
		var dy: float = p.y - g.player.y
		var d: float = sqrt(dx * dx + dy * dy)
		if d > rad:
			continue
		var fwd: float = dx * ca + dy * sa
		if fwd <= 0.3:
			continue
		var right: float = -dx * sa + dy * ca
		if absf(right / fwd) > tan_half * 1.15:
			continue
		var a: float = 0.10 * (1.0 - d / rad)
		if a <= 0.002:
			continue
		var sx: float = 0.5 + 0.5 * (right / fwd) / tan_half
		var pr: float = minf(0.6, 0.55 / maxf(0.6, fwd))
		out.append([sx, hy_frac, pr, a])
	return out


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F3:
		_debug = not _debug


func _draw() -> void:
	var w: float = size.x
	var h: float = size.y
	var font := ThemeDB.fallback_font
	for hlo in _warm:
		var pr: float = hlo[2] * h
		var cx: float = hlo[0] * w
		var cy: float = hlo[1] * h
		draw_texture_rect(_warm_tex, Rect2(cx - pr, cy - pr, pr * 2.0, pr * 2.0), false, Color(1, 1, 1, minf(1.0, hlo[3] * 2.2)))
	if _sub_a > 0.0 and _sub_de != "" and _show_sub:
		var col2 := Color(0.56, 0.63, 0.72, _sub_a * 0.95) if _sub_muffled else Color(1.0, 0.96, 0.84, _sub_a * 0.95)
		draw_string(font, Vector2(0, h * 0.74), _sub_de, HORIZONTAL_ALIGNMENT_CENTER, w, 20, col2)
		if _sub_en != "" and _show_en:
			draw_string(font, Vector2(0, h * 0.74 + 22.0), _sub_en, HORIZONTAL_ALIGNMENT_CENTER, w, 15, Color(0.72, 0.78, 0.88, _sub_a * 0.9))
	if _unsaved:
		draw_circle(Vector2(w - 24.0, h - 20.0), 5.0, Color(1.0, 0.54, 0.47, 0.7))
		draw_string(font, Vector2(w - 120.0, h - 15.0), "not saved", HORIZONTAL_ALIGNMENT_RIGHT, 80.0, 12, Color(1.0, 0.54, 0.47, 0.7))
	if _debug:
		draw_string(font, Vector2(16, 24), _text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.8, 0.9, 1.0, 0.9))
