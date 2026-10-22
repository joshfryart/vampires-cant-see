class_name Hud
extends Control
## Slice HUD (window resolution): blood bar with the gift overflow, clock and night, power icons with cooldowns, fear,
## title cards, subtitles and the F3 debug text. The polished HUD (js/hud.js, icons) is Phase 8.

const POWER_KEYS := {"shriek": "Q", "mist": "Sh", "still": "F"}

var _blood: float = 0.0
var _blood_max: float = Game.BLOOD_MAX
var _cool: float = 0.0
var _drinking: bool = false
var _debug: bool = false
var _text: String = ""
var _wipe: float = 0.0
var _clock_text: String = ""
var _night_no: int = 0
var _over: float = 0.0
var _fear: float = 0.0
var _powers: Array = []        # [{id, key, state, cd}]
var _card: String = ""
var _card_sub: String = ""
var _card_a: float = 0.0
var _sub_de: String = ""
var _sub_en: String = ""
var _sub_muffled: bool = false
var _sub_a: float = 0.0
var _weak: float = 0.0
var _day: float = 0.0
var _flash: float = 0.0
var _run_on: bool = false


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_state(g: Node) -> void:
	_blood = g.blood
	_blood_max = g.night.blood_max if g.night != null else Game.BLOOD_MAX
	_drinking = g.drink != null
	_wipe = g.wipe_k
	_run_on = g.run_on and g.night != null
	var cd: float = g.sonar.cooldown_left(g.clock)
	_cool = clampf(cd / g.sonar.cooldown, 0.0, 1.0) if cd > 0.0 else 0.0
	_flash = g.gift_flash
	_clock_text = ""
	_night_no = 0
	_over = 0.0
	_fear = 0.0
	_powers = []
	_weak = 0.0
	_day = 0.0
	if _run_on:
		_clock_text = g.night.clock()["text"]
		_night_no = g.night.night
		_weak = g.night.weakness()
		_day = g.night.dawn_k()
		if g.hunger != null:
			_over = g.hunger.over01() if g.hunger.is_open() else 0.0
			_fear = g.hunger.fear
			for pw in GameData.get_json("hunger")["powers"]:
				var id: String = pw["id"]
				_powers.append({"id": id, "key": POWER_KEYS.get(id, "?"), "state": g.hunger.power_state(id, float(g.night.night), g.night.blood), "cd": g.hunger.cd_left01(id)})
	_card = g.card_text
	_card_sub = g.card_sub
	_card_a = clampf(minf(g.card_age / 0.4, (Game.CARD_LEN - g.card_age) / 0.6 + 0.01), 0.0, 1.0) if _card != "" else 0.0
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
	if _debug:
		_text = "t %.2f  pos %.2f,%.2f  angle %.2f  pulses %d  people %d  echoes %d  light %.2f  state %s" % [g.clock, g.player.x, g.player.y, g.player.angle, g.sonar.pulses.size(), g.people.people.size(), g.people.echoes.size(), g.player_lit, g.state]
	queue_redraw()


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F3:
		_debug = not _debug


func _draw() -> void:
	var w: float = size.x
	var h: float = size.y
	var font := ThemeDB.fallback_font
	if _day > 0.0:
		draw_rect(Rect2(0, 0, w, h), Color(1.0, 0.85, 0.5, 0.18 * _day))
	if _flash > 0.0:
		draw_rect(Rect2(0, 0, w, h), Color(0.9, 0.3, 0.4, 0.2 * _flash))
	if _wipe > 0.0:
		draw_rect(Rect2(0, 0, w, h), Color(0, 0, 0, _wipe))
	var bw: float = minf(220.0, w * 0.25)
	var bx: float = 24.0
	var by: float = h - 36.0
	draw_rect(Rect2(bx, by, bw, 8.0), Color(0.15, 0.05, 0.05, 0.8))
	draw_rect(Rect2(bx, by, bw * clampf(_blood / _blood_max, 0.0, 1.0), 8.0), Color(0.8, 0.12, 0.12, 0.9) if not _drinking else Color(1.0, 0.35, 0.3, 1.0))
	if _blood < 25.0 and _run_on:
		draw_rect(Rect2(bx, by, bw * clampf(_blood / _blood_max, 0.0, 1.0), 8.0), Color(1, 1, 1, 0.25 * _weak))
	if _over > 0.0:
		draw_rect(Rect2(bx, by + 10.0, bw * _over, 3.0), Color(1.0, 0.5, 0.45, 0.9))
	if _cool > 0.0:
		draw_rect(Rect2(bx, by - 8.0, bw * _cool, 3.0), Color(0.55, 0.65, 0.95, 0.8))
	if _run_on:
		draw_string(font, Vector2(w - 190.0, 30.0), "Night %d   %s" % [_night_no, _clock_text], HORIZONTAL_ALIGNMENT_RIGHT, 170.0, 18, Color(0.85, 0.9, 1.0, 0.9))
		var fx: float = w - 190.0
		for i in int(round(_fear)):
			draw_circle(Vector2(fx + 4.0 + i * 9.0, 44.0), 3.0, Color(1.0, 0.6, 0.3, 0.8))
		var px: float = bx + bw + 24.0
		for pw in _powers:
			var st: String = pw["state"]
			if st == "locked":
				continue
			var col := Color(0.8, 0.85, 1.0, 0.9) if st == "ready" else Color(0.5, 0.5, 0.6, 0.7)
			draw_rect(Rect2(px, by - 6.0, 26.0, 22.0), Color(0.1, 0.1, 0.16, 0.8))
			draw_string(font, Vector2(px + 3.0, by + 10.0), pw["key"], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, col)
			if pw["cd"] > 0.0:
				draw_rect(Rect2(px, by + 16.0, 26.0 * pw["cd"], 2.0), Color(0.55, 0.65, 0.95, 0.9))
			px += 32.0
	if _card != "":
		draw_string(font, Vector2(0, h * 0.4), _card, HORIZONTAL_ALIGNMENT_CENTER, w, 40, Color(0.95, 0.9, 0.85, _card_a))
		if _card_sub != "":
			draw_string(font, Vector2(0, h * 0.4 + 30.0), _card_sub, HORIZONTAL_ALIGNMENT_CENTER, w, 16, Color(0.8, 0.85, 0.95, _card_a * 0.9))
	if _sub_a > 0.0 and _sub_de != "":
		var col2 := Color(0.56, 0.63, 0.72, _sub_a * 0.95) if _sub_muffled else Color(1.0, 0.96, 0.84, _sub_a * 0.95)
		draw_string(font, Vector2(0, h * 0.74), _sub_de, HORIZONTAL_ALIGNMENT_CENTER, w, 20, col2)
		if _sub_en != "":
			draw_string(font, Vector2(0, h * 0.74 + 22.0), _sub_en, HORIZONTAL_ALIGNMENT_CENTER, w, 15, Color(0.72, 0.78, 0.88, _sub_a * 0.9))
	if _debug:
		draw_string(font, Vector2(16, 24), _text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.8, 0.9, 1.0, 0.9))
