class_name HudView
extends Control
## The night HUD, drawn inside the 640x360 SubViewport with the ported js/hud.js (render/hud_draw.gd): vial, veil, dial, powers,
## fear, title card and hints as dim hand-drawn lines. Dawn tint, feed vignette and fades are plain overlays here.

var canvas := DrawCanvas.new()
var hud := HudDraw.new()
var _vig: GradientTexture2D
var _vignette: float = 0.0
var _dawn: float = 0.0
var _fade: float = 0.0
var _plain: bool = false


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vig = GradientTexture2D.new()
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, 0))
	g.set_color(1, Color(0, 0, 0, 1))
	_vig.gradient = g
	_vig.fill = GradientTexture2D.FILL_RADIAL
	_vig.fill_from = Vector2(0.5, 0.5)
	_vig.fill_to = Vector2(1.0, 0.5)
	_vig.width = 128
	_vig.height = 128


## Build this frame's HUD strokes from the game state.
## The HUD is mostly static, so the op list is rebuilt only when its (quantised) inputs change: strokes and fills are kept by the
## CanvasItem between redraws, so an unchanged HUD costs neither the build nor a repaint. Quantum: time 1/12 s (the boil is 10 fps,
## the slow wobbles are under 4 Hz), meters about a tenth of a pixel. Title card, hints and the title screen animate and are
## rebuilt at the time quantum.
const T_Q := 12.0
const TITLE_Q := 30.0
var _sig: int = 0
var _sig_valid: bool = false
var _ov_sig: int = 0
var _power_ids: Array = []
## Counters for the benches: how many frames rebuilt the ops.
var stat_built: int = 0
var stat_cached: int = 0
## The inputs of the last night HUD build (diagnostics).
var last_s: Dictionary = {}


static func _q(v: float, steps: float) -> float:
	return roundf(v * steps) / steps


func render_frame(g: Game) -> void:
	var n: Night = g.night
	var vignette: float = g.fov_ease() if g.drink != null or g.fov_k > 0.0 else 0.0
	if g.reduced:
		vignette = 0.3 if g.drink != null else 0.0
	var dawn: float = n.dawn_k() if n != null else 0.0
	var fade: float = g.fade_amount()
	var ov: int = [vignette, dawn, fade].hash()
	var redraw: bool = ov != _ov_sig
	_ov_sig = ov
	_vignette = vignette
	_dawn = dawn
	_fade = fade
	var tq: float = floorf(g.clock * T_Q) / T_Q
	if g.state == "title":
		var ttq: float = floorf(g.title_t * TITLE_Q) / TITLE_Q
		var sig: int = ["title", ttq, g.reduced, g.cfg["lineBoil"] == true].hash()
		if not _sig_valid or sig != _sig:
			_sig = sig
			_sig_valid = true
			canvas.reset()
			TitleDraw.draw(canvas, 640.0, 360.0, ttq, g.reduced, g.cfg["lineBoil"] == true, true)
			redraw = true
			stat_built += 1
		else:
			stat_cached += 1
		if redraw:
			queue_redraw()
		return
	if g.state == "runend" or g.state == "boon" or g.state == "gift":
		if not _sig_valid or _sig != 1:
			_sig = 1
			_sig_valid = true
			canvas.reset()
			redraw = true
		if redraw:
			queue_redraw()
		return
	var wiping: bool = g.transition != null and g.wipe_k > 0.0
	if wiping or n == null:
		var sig2: int = ["plain", wiping, _q(g.hud_a, 24.0), _q(g.hud_frac, 24.0)].hash()
		if not _sig_valid or sig2 != _sig:
			_sig = sig2
			_sig_valid = true
			canvas.reset()
			if not wiping:
				_plain_hud(g)
			redraw = true
			stat_built += 1
		else:
			stat_cached += 1
		if redraw:
			queue_redraw()
		return
	var boil: bool = not g.reduced and g.cfg["lineBoil"] == true
	var clk: Dictionary = n.clock()
	var s := {
		"blood01": _q(n.blood / n.blood_max, 150.0) if n.blood_max > 0.0 else 0.0, "weak": _q(n.weakness(), 50.0), "frac": _q(n.min / 600.0, 500.0),
		"hour": clk["hour"], "minute": clk["minute"], "t": 0.0 if g.reduced else tq, "boil": boil, "reduced": g.reduced,
		"largeText": g.large_text, "fx": g.echo_view.rs.fx_cfg, "pulse01": _q(g.hud_a * g.hud_frac, 24.0) if g.hud_a > 0.01 else 0.0,
		"vialPulse": _q(g.vial_pulse, 50.0), "feeding": g.drink != null, "veil": _q(g.veil_k, 100.0), "rocks": g.powers.rocks_left,
	}
	var h: Hunger = g.hunger
	if h != null:
		s["overOpen"] = h.is_open() and n.blood >= n.blood_max
		s["over01"] = _q(h.over01(), 100.0)
		s["fear"] = _q(h.fear, 100.0)
		s["still01"] = _q(minf(1.0, h.still_left / Hunger.STILL_SECS), 100.0) if h.still_left > 0.0 else 0.0
		s["mistK"] = _q(g.powers.mist_vis, 100.0)
		s["giftFlash"] = _q(g.gift_flash, 100.0)
		if _power_ids.is_empty():
			for pw in GameData.get_json("hunger")["powers"]:
				_power_ids.append(pw["id"])
		var rows: Array = []
		for id in _power_ids:
			rows.append({"id": id, "state": h.power_state(id, float(n.night), n.blood), "cd01": _q(h.cd_left01(id), 100.0), "key": Hud.POWER_KEYS.get(id, "")})
		s["powers"] = rows
	last_s = s
	var animated: bool = g.card_text != "" or g.hint_text != "" or g.unlock_hint_t > 0.0
	var sig3: int = s.hash()
	if animated:
		sig3 = [sig3, tq, g.card_age, g.hint_age].hash()
	if _sig_valid and sig3 == _sig:
		stat_cached += 1
		if redraw:
			queue_redraw()
		return
	_sig = sig3
	_sig_valid = true
	stat_built += 1
	canvas.reset()
	hud.draw_hud(canvas, s)
	if g.card_text != "":
		HudDraw.draw_card(canvas, g.card_text, g.card_age, tq, boil, g.card_sub, g.large_text)
	elif g.hint_text != "":
		HudDraw.draw_hint(canvas, g.hint_text, g.hint_age, g.hint_dur, g.large_text)
	elif g.unlock_hint_t > 0.0:
		HudDraw.draw_hint(canvas, "Esc → Abilities for details", 3.0 - g.unlock_hint_t, 3.0, g.large_text)
	queue_redraw()


func _plain_hud(g: Game) -> void:
	canvas.global_alpha = 0.3
	canvas.fill_style = "#ffffff"
	canvas.fill_rect(319.0, 179.0, 2.0, 2.0)
	if g.hud_a > 0.01:
		canvas.global_alpha = 0.5 * g.hud_a
		canvas.stroke_style = "#cfe3ff"
		canvas.line_width = 0.75
		canvas.begin_path()
		canvas.arc(320.0, 342.0, 6.0, -PI / 2.0, -PI / 2.0 + TAU * g.hud_frac)
		canvas.stroke()
	canvas.global_alpha = 1.0


func _draw() -> void:
	var w: float = size.x
	var h: float = size.y
	if _dawn > 0.0:
		draw_texture_rect(_vig, Rect2(Vector2.ZERO, size), false, Color(0.59, 0.59, 0.62, 0.22 * _dawn))
		draw_rect(Rect2(0, 0, w, h), Color(1.0, 0.85, 0.5, 0.06 * _dawn))
	if _vignette > 0.0:
		draw_texture_rect(_vig, Rect2(Vector2.ZERO, size), false, Color(1, 1, 1, 0.55 * _vignette))
	canvas.paint(self)
	if _fade > 0.0:
		draw_rect(Rect2(0, 0, w, h), Color(0, 0, 0, _fade))
