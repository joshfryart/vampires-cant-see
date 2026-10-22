class_name Hud
extends Control
## Window-resolution overlay: subtitles (listening at windows and villager barks), the "not saved" dot and the F3 debug text.
## The line HUD (vial, dial, powers, cards, hints) is HudView inside the 640x360 viewport.

const POWER_KEYS := {"shriek": "Q", "mist": "Sh", "still": "F"}

var _debug: bool = false
var _debug_key: bool = false
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
var _large: bool = false
var _listening: bool = false
var _voices: String = ""
var _dbg_ms: int = 0


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
	elif g.bark_sub != null and not (g.listen_st != null and g.listen_st.active):
		var bs: Dictionary = g.bark_sub
		_sub_de = bs["de"]
		_sub_en = bs["en"]
		_sub_muffled = false
		_sub_a = Listen.sub_alpha(bs, g.clock)
	_unsaved = g.flow != null and g.flow.save_failed
	_large = g.large_text
	_listening = g.listen_st != null and g.listen_st.active
	_voices = ""
	if _listening:
		_voices = "Voices inside: %d%s" % [g.listen_st.count, " (hushed)" if g.listen_st.silent and g.listen_st.count > 0 else ""]
	_debug = _debug_key or Flags.get_flag("dev.showFps") or g.cfg.get("showFps", false) == true
	_warm = _warm_halos(g)
	if _debug:
		var now := Time.get_ticks_msec()
		if now - _dbg_ms >= 250 or _text == "":
			_dbg_ms = now
			_text = _debug_text(g)
	queue_redraw()


## The F3 text (refreshed every 0.25 s, like js updateDebug): js lines plus the port's counters, schedule lines and governor state.
func _debug_text(g: Node) -> String:
	var last := ""
	if not Log.lines.is_empty():
		var l: Dictionary = Log.lines[Log.lines.size() - 1]
		last = "
%s %s: %s" % [l["level"], l["tag"], str(l["msg"]).left(80)]
	var view := "top" if g.map_view != null and g.map_view.visible else "fp"
	var t := "FPS %d  canvas %d us  figures %d vol / %d line  vessels %d
x %.2f y %.2f a %.2f
state %s view %s  t %.2f
pulses %d cd %.2f  people %d echoes %d rings %d  light %.2f" % [Engine.get_frames_per_second(), g.echo_view.last_us, g.echo_view.rs.fig_vol, g.echo_view.rs.fig_line, g.echo_view.rs.vessel_nodes, g.player.x, g.player.y, g.player.angle, g.state, view, g.clock, g.sonar.pulses.size(), g.sonar.cooldown_left(g.clock), g.people.people.size(), g.people.echoes.size(), g.ripple.rings.size(), g.player_lit]
	if g.echo_view.has_method("governor_state"):
		var gs: Variant = g.echo_view.governor_state()
		if gs is Dictionary:
			t += "
gov quality %s mat %s fx %s cap %s fps~%.0f" % [str(gs.get("quality")), str(gs.get("mat_detail")), str(gs.get("fx")), str(gs.get("fx_cap")), float(gs.get("fps_ema", 0.0))]
	if OS.is_debug_build() and g.people != null and g.player != null:
		t += "
" + sched_lines(g.people.people, g.player.x, g.player.y, g.people.night_frac, g.people.night_sec)
	return t + last


## js schedLines: role, current stop, next stop, eta, for the 6 nearest scheduled villagers (one per line, newline terminated).
static func sched_lines(list: Array, px: float, py: float, night_frac: float, night_sec: float) -> String:
	var near: Array = []
	for q in list:
		if q.sched == null:
			continue
		near.append({"q": q, "d": sqrt((q.x - px) * (q.x - px) + (q.y - py) * (q.y - py))})
	near.sort_custom(func(a, b): return a["d"] < b["d"])
	var out := ""
	for i in mini(near.size(), 6):
		var q: Variant = near[i]["q"]
		var s: Dictionary = q.sched
		var stops: Array = s["stops"]
		var si: int = int(s["si"])
		var cur: Variant = stops[si] if si >= 0 and si < stops.size() else null
		var nxi: int = mini(stops.size() - 1, maxi(0, si) + 1)
		var nx: Variant = stops[nxi] if nxi >= 0 and nxi < stops.size() else null
		var eta: float = Schedule.eta(stops, maxi(0, si), night_frac, night_sec)
		out += "%s %s%s next %s eta %s%s d%d
" % [str(s["role"]), (str(cur["place"]) + ":" + str(cur["act"])) if cur != null else "-", " >" if s["en"] else " @", str(nx["place"]) if nx != null else "-", (str(int(floorf(eta + 0.5))) + "s") if is_finite(eta) else "-", " HOME" if s.get("homeEarly", false) else "", int(floorf(near[i]["d"] + 0.5))]
	return out


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
		_debug_key = not _debug_key
		_debug = _debug_key or Flags.get_flag("dev.showFps")


func _draw() -> void:
	var w: float = size.x
	var h: float = size.y
	var font := ThemeDB.fallback_font
	for hlo in _warm:
		var pr: float = hlo[2] * h
		var cx: float = hlo[0] * w
		var cy: float = hlo[1] * h
		draw_texture_rect(_warm_tex, Rect2(cx - pr, cy - pr, pr * 2.0, pr * 2.0), false, Color(1, 1, 1, minf(1.0, hlo[3] * 2.2)))
	var sc: float = h / 360.0
	var k: float = 1.3 if _large else 1.0
	var cx2: float = w / 2.0
	if _voices != "":
		var fs: int = int(round(11.0 * k * sc))
		draw_string(font, Vector2(0, (262.0 - (k - 1.0) * 20.0) * sc + fs * 0.35), _voices, HORIZONTAL_ALIGNMENT_CENTER, w, fs, Color(0.81, 0.89, 1.0, 0.85))
	if _sub_a > 0.0 and _sub_de != "" and _show_sub:
		var show_en: bool = _sub_en != "" and _show_en
		var fs_de: int = int(round(13.0 * k * sc))
		var y0: float = (262.0 - (k - 1.0) * 20.0 - round(24.0 * k) - (round(16.0 * k) if show_en else 0.0)) * sc
		var col2 := Color(0.56, 0.63, 0.72, _sub_a * 0.95) if _sub_muffled else Color(1.0, 0.96, 0.84, _sub_a * 0.95)
		draw_string(font, Vector2(0, y0 + fs_de * 0.35), _sub_de, HORIZONTAL_ALIGNMENT_CENTER, w, fs_de, col2)
		if show_en:
			var fs_en: int = int(round(11.0 * k * sc))
			draw_string(font, Vector2(0, y0 + round(16.0 * k) * sc + fs_en * 0.35), _sub_en, HORIZONTAL_ALIGNMENT_CENTER, w, fs_en, Color(0.72, 0.78, 0.88, _sub_a * 0.95))
	if _unsaved:
		draw_circle(Vector2(w - 24.0, h - 20.0), 5.0, Color(1.0, 0.54, 0.47, 0.7))
		draw_string(font, Vector2(w - 120.0, h - 15.0), "not saved", HORIZONTAL_ALIGNMENT_RIGHT, 80.0, 12, Color(1.0, 0.54, 0.47, 0.7))
	if _debug:
		draw_multiline_string(font, Vector2(16, 24), _text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, -1, Color(0.8, 0.9, 1.0, 0.9))
