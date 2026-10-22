class_name MapView
extends Control
## The M top-down map (js Render.drawTopDown), a debug-build tool: walls, doors, props, spots, people and the pulse rings
## around the player, at window resolution. Not part of normal play (only in debug builds, like `?debug=1` in the JS).

const CELL := 16.0
const WALLS := "#BWIw"
const WALL_COL := {"#": Color(0.81, 0.89, 1.0, 0.6), "B": Color(0.9, 0.59, 0.49, 0.8), "W": Color(0.84, 0.71, 0.43, 0.8), "I": Color(0.59, 0.69, 0.8, 0.8), "w": Color(0.43, 0.82, 1.0, 0.9)}
const COL_PERSON := Color(1.0, 0.42, 0.36)
const COL_CRYPT := Color(0.7, 0.55, 1.0)
const COL_SAFE := Color(0.55, 0.48, 0.85)
const COL_DOOR := Color(0.91, 0.95, 1.0)

var _g: Game


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


func attach(g: Game) -> void:
	_g = g


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_M and OS.is_debug_build() and _g != null and (_g.state == "playing" or _g.state == "paused" or _g.state == "feeding"):
		visible = not visible


func _process(_d: float) -> void:
	if visible:
		queue_redraw()


func _draw() -> void:
	if _g == null or _g.world == null:
		return
	var w: World = _g.world
	var k: float = size.x / 640.0
	var cell: float = CELL * k
	draw_rect(Rect2(Vector2.ZERO, size), Color.BLACK)
	var ox: float = size.x / 2.0 - _g.player.x * cell
	var oy: float = size.y / 2.0 - _g.player.y * cell
	var x0: int = maxi(0, int(floor(-ox / cell)))
	var x1: int = mini(w.width - 1, int(floor((size.x - ox) / cell)))
	var y0: int = maxi(0, int(floor(-oy / cell)))
	var y1: int = mini(w.height - 1, int(floor((size.y - oy) / cell)))
	for cy in range(y0, y1 + 1):
		for cx in range(x0, x1 + 1):
			var ch: String = w.tile_at(cx, cy)
			var gx: float = ox + cx * cell
			var gy: float = oy + cy * cell
			if WALLS.contains(ch) and ch != "":
				var col: Color = WALL_COL[ch]
				if not WALLS.contains(w.tile_at(cx, cy - 1)) or w.tile_at(cx, cy - 1) == "":
					draw_line(Vector2(gx, gy), Vector2(gx + cell, gy), col)
				if not WALLS.contains(w.tile_at(cx, cy + 1)) or w.tile_at(cx, cy + 1) == "":
					draw_line(Vector2(gx, gy + cell), Vector2(gx + cell, gy + cell), col)
				if not WALLS.contains(w.tile_at(cx - 1, cy)) or w.tile_at(cx - 1, cy) == "":
					draw_line(Vector2(gx, gy), Vector2(gx, gy + cell), col)
				if not WALLS.contains(w.tile_at(cx + 1, cy)) or w.tile_at(cx + 1, cy) == "":
					draw_line(Vector2(gx + cell, gy), Vector2(gx + cell, gy + cell), col)
				if ch == "w":
					draw_line(Vector2(gx + 4, gy + 4), Vector2(gx + cell - 4, gy + cell - 4), col)
					draw_line(Vector2(gx + cell - 4, gy + 4), Vector2(gx + 4, gy + cell - 4), col)
			elif ch == "D" or ch == "G":
				draw_rect(Rect2(gx + 3.5, gy + 3.5, cell - 7.0, cell - 7.0), Color(0.62, 0.71, 0.8) if ch == "G" else COL_DOOR, false)
				if w.is_link_door(cx, cy):
					draw_string(ThemeDB.fallback_font, Vector2(gx + cell / 2.0 - 4.0, gy + cell / 2.0 + 5.0), "L", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.5, 1.0, 0.63))
	for q in w.props:
		var qp := Vector2(ox + float(q["x"]) * cell, oy + float(q["y"]) * cell)
		var warm: bool = q.get("type") == "torch" or q.get("type") == "brazier"
		draw_circle(qp, 2.0 if q.get("solid") == false else 3.0, Color(1.0, 0.67, 0.27) if warm else Color(0.72, 0.78, 0.88))
	for pair in [[w.spots["crypt"], COL_CRYPT], [w.spots["safe"], COL_SAFE], [w.spots["people"], COL_PERSON], [w.spots["doors"], COL_DOOR]]:
		for s in pair[0]:
			draw_rect(Rect2(ox + float(s["x"]) * cell - 3.0, oy + float(s["y"]) * cell - 3.0, 6.0, 6.0), pair[1])
	if _g.people != null:
		for p in _g.people.people:
			var pp := Vector2(ox + p.x * cell, oy + p.y * cell)
			draw_circle(pp, 3.0, COL_PERSON)
			draw_line(pp, pp + Vector2(cos(p.angle), sin(p.angle)) * 8.0, COL_PERSON)
	for pu in _g.sonar.pulses:
		var rad: float = Sonar.ring_radius(pu, _g.clock)
		if rad < 0.0 or rad > pu.range:
			continue
		draw_arc(Vector2(ox + pu.x * cell, oy + pu.y * cell), rad * cell, 0.0, TAU, 64, Color(0.81, 0.89, 1.0, maxf(0.0, 0.6 * (1.0 - rad / pu.range))))
	var c: Vector2 = size / 2.0
	draw_circle(c, 4.0, Color.WHITE)
	draw_line(c, c + Vector2(cos(_g.player.angle), sin(_g.player.angle)) * 12.0, Color.WHITE)
