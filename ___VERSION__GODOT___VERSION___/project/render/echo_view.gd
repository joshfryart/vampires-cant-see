class_name EchoView
extends Control
## 2D overlay inside the 640x360 SubViewport: draws the villager echoes (line figures) over the 3D wall render.
## Each frame the game calls render_frame(); the polylines are painted from _draw().

var rs := RenderState.new()
var canvas := DrawCanvas.new()
var pose := Pose.new()
var drawn: int = 0
var debug_marks: bool = false
## The dotted pulse ring is drawn by the floor shader; set true to draw it on the canvas as well (parity-tested port).
var cpu_ripple: bool = false
## The ground effects (dotted ring, front arc, footstep rings, secondary rings) are drawn by sonar_floor.gdshader; set false to
## draw them on the canvas instead (the parity-tested port in floor_fx.gd).
var gpu_floor: bool = true
var tex_budget: int = FloorFx.TEX_MAX_CELLS
var last_us: int = 0


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Build this frame's strokes. echoes: Array of echo dictionaries (see echo_to_dict). lock_id < 0 = nobody held.
func render_frame(world: World, player: Player, people: People, sonar: Sonar, t: float, lock: Dictionary, rings: Array = []) -> void:
	var t0 := Time.get_ticks_usec()
	canvas.reset()
	Raycast.depth_columns(world, player.x, player.y, player.angle, rs.col_cos, rs.col_sin, 16.0, rs.zbuf)
	rs.update_boil(t)
	if lock.is_empty():
		rs.lock_id = -1
	else:
		rs.lock_id = int(lock["id"])
		rs.lock_k = float(lock.get("k", 0.0))
		rs.lock_age = float(lock.get("age", 1.0))
		rs.lock_sp = float(lock.get("sp", 9.0))
		rs.lock_rs = float(lock.get("rs", 0.0))
	var echoes: Array = []
	for e in people.echoes:
		echoes.append(echo_to_dict(e))
	var pl := {"x": player.x, "y": player.y, "angle": player.angle}
	var th: float = rs.tan_half()
	drawn = 0
	var any_pulse: bool = sonar.pulses.size() > 0 or people.echoes.size() > 0 or rings.size() > 0
	var tp := Time.get_ticks_usec()
	if sonar.pulses.size() > 0:
		if cpu_ripple or not gpu_floor:
			FloorFx.draw_ripple(rs, canvas, world, sonar, t, pl, th)
		tp = _lap("ripple", tp)
		FloorFx.draw_air_rings(rs, canvas, world, sonar, t, pl, th)
		tp = _lap("air", tp)
		FloorFx.draw_floor_texture(rs, canvas, world, sonar, t, pl, th, tex_budget)
		tp = _lap("texture", tp)
		if not gpu_floor:
			FloorFx.draw_floor_front(rs, canvas, world, sonar, t, pl, th)
			tp = _lap("front", tp)
			FloorFx.draw_foot_rings(rs, canvas, sonar, t, pl, th)
			tp = _lap("foot", tp)
	if not gpu_floor:
		FloorFx.draw_rings(rs, canvas, rings, t, pl, th)
		tp = _lap("rings", tp)
	if any_pulse:
		drawn += Sprites.draw_markers(rs, canvas, world, pl, sonar, t, th)
		drawn += Sprites.draw_props(rs, canvas, world, pl, sonar, t, th)
	tp = _lap("sprites", tp)
	drawn += EchoLayer.draw_echoes(rs, canvas, pose, echoes, sonar.fade, t, pl, th)
	_lap("echoes", tp)
	last_us = Time.get_ticks_usec() - t0
	queue_redraw()


## Per-section cost accounting (microseconds, summed): read by the perf scenario.
var prof: Dictionary = {}


func _lap(key: String, since: int) -> int:
	var now := Time.get_ticks_usec()
	prof[key] = int(prof.get(key, 0)) + (now - since)
	return now


static func echo_to_dict(e: People.Echo) -> Dictionary:
	return {
		"personId": e.person_id, "kind": e.kind, "x": e.x, "y": e.y, "angle": e.angle, "lookAngle": e.look_angle,
		"phase": e.phase, "phaseRate": e.phase_rate, "t": e.t, "strength": e.strength, "zMin": e.z_min, "zMax": e.z_max,
		"fade": e.fade, "look": e.look, "mode": e.mode, "sit": e.sit, "wary": e.wary, "modeAge": e.mode_age,
	}


func _draw() -> void:
	canvas.paint(self)
	if debug_marks:
		draw_line(Vector2(0, 180), Vector2(640, 180), Color(0, 1, 0, 0.8), 1.0)
		draw_line(Vector2(320, 0), Vector2(320, 360), Color(0, 1, 0, 0.8), 1.0)
		draw_rect(Rect2(0, 0, 20, 20), Color(1, 1, 0, 1))
