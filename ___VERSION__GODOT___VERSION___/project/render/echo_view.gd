class_name EchoView
extends Control
## 2D overlay inside the 640x360 SubViewport: draws the villager echoes (line figures) over the 3D wall render.
## Each frame the game calls render_frame(); the polylines are painted from _draw().

var rs := RenderState.new()
var canvas := DrawCanvas.new()
var pose := Pose.new()
var drawn: int = 0
var debug_marks: bool = false


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Build this frame's strokes. echoes: Array of echo dictionaries (see echo_to_dict). lock_id < 0 = nobody held.
func render_frame(world: World, player: Player, people: People, sonar: Sonar, t: float, lock: Dictionary) -> void:
	canvas.reset()
	var fov: float = RenderState.FOV_DEG * PI / 180.0
	var hits := Raycast.cast(world, player.x, player.y, player.angle, fov, rs.cols, 16.0)
	for i in rs.cols:
		rs.zbuf[i] = hits[i].dist
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
	drawn = EchoLayer.draw_echoes(rs, canvas, pose, echoes, sonar.fade, t, pl, rs.tan_half())
	queue_redraw()


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
