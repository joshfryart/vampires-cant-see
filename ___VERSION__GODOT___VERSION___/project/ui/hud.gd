class_name Hud
extends Control
## Slice HUD (window resolution): blood bar, ping cooldown, and the F3-style debug text. Proper HUD (js/hud.js) is Phase 8.

var _blood: float = 0.0
var _blood_max: float = Game.BLOOD_MAX
var _cool: float = 0.0
var _drinking: bool = false
var _debug: bool = false
var _text: String = ""


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_state(g: Node) -> void:
	_blood = g.blood
	_drinking = g.drink != null
	var cd: float = g.sonar.cooldown_left(g.clock)
	_cool = clampf(cd / g.sonar.cooldown, 0.0, 1.0) if cd > 0.0 else 0.0
	if _debug:
		_text = "t %.2f  pos %.2f,%.2f  angle %.2f  pulses %d  people %d  echoes %d  light %.2f" % [g.clock, g.player.x, g.player.y, g.player.angle, g.sonar.pulses.size(), g.people.people.size(), g.people.echoes.size(), g.player_lit]
	queue_redraw()


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F3:
		_debug = not _debug


func _draw() -> void:
	var w: float = size.x
	var h: float = size.y
	var bw: float = minf(220.0, w * 0.25)
	var bx: float = 24.0
	var by: float = h - 36.0
	draw_rect(Rect2(bx, by, bw, 8.0), Color(0.15, 0.05, 0.05, 0.8))
	draw_rect(Rect2(bx, by, bw * clampf(_blood / _blood_max, 0.0, 1.0), 8.0), Color(0.8, 0.12, 0.12, 0.9) if not _drinking else Color(1.0, 0.35, 0.3, 1.0))
	if _cool > 0.0:
		draw_rect(Rect2(bx, by - 8.0, bw * _cool, 3.0), Color(0.55, 0.65, 0.95, 0.8))
	if _debug:
		draw_string(ThemeDB.fallback_font, Vector2(16, 24), _text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.8, 0.9, 1.0, 0.9))
