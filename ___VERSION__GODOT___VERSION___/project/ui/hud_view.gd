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
func render_frame(g: Game) -> void:
	canvas.reset()
	var n: Night = g.night
	_vignette = g.fov_ease() if g.drink != null or g.fov_k > 0.0 else 0.0
	if g.reduced:
		_vignette = 0.3 if g.drink != null else 0.0
	_dawn = n.dawn_k() if n != null else 0.0
	_fade = g.fade_amount()
	if g.state == "title" or g.state == "runend" or g.state == "boon" or g.state == "gift":
		queue_redraw()
		return
	var wiping: bool = g.transition != null and g.wipe_k > 0.0
	if wiping or n == null:
		if not wiping:
			_plain_hud(g)
		queue_redraw()
		return
	var boil: bool = not g.reduced and g.cfg["lineBoil"] == true
	var s := {
		"blood01": n.blood / n.blood_max if n.blood_max > 0.0 else 0.0, "weak": n.weakness(), "frac": n.min / 600.0,
		"hour": n.clock()["hour"], "minute": n.clock()["minute"], "t": g.clock, "boil": boil, "reduced": g.reduced,
		"largeText": g.large_text, "fx": g.echo_view.rs.fx, "pulse01": g.hud_a * g.hud_frac if g.hud_a > 0.01 else 0.0,
		"vialPulse": g.vial_pulse, "feeding": g.drink != null, "veil": g.veil_k, "rocks": g.powers.rocks_left,
	}
	var h: Hunger = g.hunger
	if h != null:
		s["overOpen"] = h.is_open() and n.blood >= n.blood_max
		s["over01"] = h.over01()
		s["fear"] = h.fear
		s["still01"] = minf(1.0, h.still_left / Hunger.STILL_SECS) if h.still_left > 0.0 else 0.0
		s["mistK"] = g.powers.mist_vis
		s["giftFlash"] = g.gift_flash
		var rows: Array = []
		for pw in GameData.get_json("hunger")["powers"]:
			var id: String = pw["id"]
			rows.append({"id": id, "state": h.power_state(id, float(n.night), n.blood), "cd01": h.cd_left01(id), "key": Hud.POWER_KEYS.get(id, "")})
		s["powers"] = rows
	hud.draw_hud(canvas, s)
	if g.card_text != "":
		HudDraw.draw_card(canvas, g.card_text, g.card_age, g.clock, boil, g.card_sub, g.large_text)
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
