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
var rs_fov: float = RenderState.FOV_DEG * PI / 180.0
const Governor = preload("res://render/governor.gd")
## Adaptive quality and the effects cap. render_frame runs it every frame (real wall-clock frame times); shader_state() reads it back.
var gov := Governor.new()
var _painted_ops: int = 0
# depth-buffer cache: the zbuf only depends on the pose, the fov, the doors and the column count
var _d_valid: bool = false
var _d_x: float = 0.0
var _d_y: float = 0.0
var _d_a: float = 0.0
var _d_fov: float = 0.0
var _d_doors: int = 0
var _d_half: bool = false
var _d_world: int = 0
var _zh: PackedFloat32Array = PackedFloat32Array()
var _th: PackedByteArray = PackedByteArray()
## Whole-frame cache key: when nothing the frame depends on changed (paused, menus) the previous strokes are kept as they are.
var _frame_key: Array = []
## Profiling counters (read by tools): frames skipped by the frame cache, depth buffers computed / reused / not needed.
var stat_skipped: int = 0
var stat_depth: int = 0
var stat_depth_reused: int = 0


## Settings that change how the canvas draws: effects level, material detail, line boil, reduced motion.
func apply_config(cfg: Dictionary, reduced: bool) -> void:
	var fxc: int = clampi(int(round(float(cfg["effects"]))), 0, 2)
	if fxc != gov.fx_cfg:
		gov.clear_cap()
	gov.fx_cfg = fxc
	rs.fx_cfg = fxc
	rs.fx = fxc
	rs.mat_cfg = cfg["materialDetail"] == true
	rs.mat_detail = rs.mat_cfg and gov.mat_detail
	rs.boil_cfg = cfg["lineBoil"] == true
	rs.reduced = reduced
	_frame_key = []


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## What the game pushes to the wall and floor shaders each frame (call after render_frame). Quality mapping as the JS:
## halo at quality 3, arc_trail 4/2/0 for quality 3/2/<2, vib_on and mat_detail need quality >= 2 and material detail on,
## boil_on = line boil (quality >= 2, not reduced). fx is the CAPPED effects level, fx_cfg the configured one.
func shader_state() -> Dictionary:
	var q: int = rs.quality
	var air: bool = q >= 2 and rs.mat_detail
	return {
		"quality": q, "mat_detail": air, "vib_on": air, "boil_on": rs.boil_on, "halo": q >= 3,
		"arc_trail": 4 if q >= 3 else (2 if q == 2 else 0), "fx": rs.fx, "fx_cfg": rs.fx_cfg, "fx_taper": rs.fx_taper,
		"fx_cap": gov.fx_cap, "fps_ema": gov.fps_ema, "auto_mat_detail": gov.mat_detail,
	}


## Fill rs.zbuf / rs.tch for this view. Cached while the pose, fov and doors are unchanged; quality <= 1 casts half the columns.
func _update_depth(world: World, player: Player) -> void:
	var half: bool = rs.quality <= 1
	var doors: int = world.open_doors.hash()
	var wid: int = world.get_instance_id()
	if _d_valid and player.x == _d_x and player.y == _d_y and player.angle == _d_a and rs_fov == _d_fov and doors == _d_doors and half == _d_half and wid == _d_world:
		stat_depth_reused += 1
		return
	stat_depth += 1
	_d_valid = true
	_d_x = player.x
	_d_y = player.y
	_d_a = player.angle
	_d_fov = rs_fov
	_d_doors = doors
	_d_half = half
	_d_world = wid
	if not half:
		Raycast.depth_columns(world, player.x, player.y, player.angle, rs.col_cos, rs.col_sin, 16.0, rs.zbuf, rs.tch)
		return
	var n: int = rs.col_cos_h.size()
	if _zh.size() != n:
		_zh.resize(n)
		_th.resize(n)
	Raycast.depth_columns(world, player.x, player.y, player.angle, rs.col_cos_h, rs.col_sin_h, 16.0, _zh, _th)
	var last: int = rs.cols - 1
	for i in n:
		var z: float = _zh[i]
		var tc: int = _th[i]
		var c0: int = mini(last, i * 2)
		rs.zbuf[c0] = z
		rs.tch[c0] = tc
		var c1: int = mini(last, i * 2 + 1)
		rs.zbuf[c1] = z
		rs.tch[c1] = tc
	for c in range(n * 2, rs.cols):
		rs.zbuf[c] = _zh[n - 1]
		rs.tch[c] = _th[n - 1]


## Build this frame's strokes. echoes: Array of echo dictionaries (see echo_to_dict). lock_id < 0 = nobody held.
func render_frame(world: World, player: Player, people: People, sonar: Sonar, t: float, lock: Dictionary, rings: Array = []) -> void:
	var t0 := Time.get_ticks_usec()
	var any_pulse: bool = sonar.pulses.size() > 0 or people.echoes.size() > 0 or rings.size() > 0
	# governor: real frame time -> quality / material detail; effects cap and taper from the configured level
	gov.adapt(float(t0) / 1000.0, any_pulse)
	gov.begin_frame(t, gov.fx_cfg)
	rs.quality = gov.quality
	rs.mat_detail = rs.mat_cfg and gov.mat_detail
	rs.fx = gov.fx
	rs.fx_taper = gov.fx_taper
	var key := [t, player.x, player.y, player.angle, rs_fov, sonar.pulses.size(), people.echoes.size(), rings.size(), rs.quality, rs.fx,
		rs.mat_detail, rs.reduced, rs.boil_cfg, rs.horizon, lock.is_empty(), world.get_instance_id(), world.open_doors.hash(), tex_budget, gpu_floor]
	if key == _frame_key and lock.is_empty():
		stat_skipped += 1
		last_us = Time.get_ticks_usec() - t0
		return
	_frame_key = key
	rs.set_fov(rs_fov)
	canvas.reset()
	# the depth buffer is read by the floor effects, sprites and echoes only: nothing alive means nothing to occlude
	if any_pulse:
		_update_depth(world, player)
	rs.world = world
	rs.update_boil(t)
	rs.fig_ms = 0.0
	rs.vessel_nodes = 0
	rs.vessel_heart = 0.0
	rs.vessel_feet = 0.0
	rs.fig_vol = 0
	rs.fig_line = 0
	rs.fig_budget = Flags.tun("figure", "budgetMs", EchoLayer.FIG_BUDGET_MS)
	rs.lights = world.lights
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
	if sonar.pulses.size() > 0:
		gov.figure_frame_end(t, rs.fig_vol, rs.fig_line, rs.fig_ms, rs.fig_budget)
	last_us = Time.get_ticks_usec() - t0
	# an empty overlay that stays empty needs no repaint
	var nops: int = canvas.ops.size()
	if nops > 0 or _painted_ops > 0:
		queue_redraw()
	_painted_ops = nops


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
		"fade": e.fade, "look": e.look, "mode": e.mode, "sit": e.sit, "wary": e.wary, "chat": e.chat, "modeAge": e.mode_age,
		"bpm": e.bpm, "stateK": e.state_k, "periphK": e.periph_k, "headK": e.head_k, "vessel": e.vessel,
	}


func _draw() -> void:
	canvas.paint(self)
	if debug_marks:
		draw_line(Vector2(0, 180), Vector2(640, 180), Color(0, 1, 0, 0.8), 1.0)
		draw_line(Vector2(320, 0), Vector2(320, 360), Color(0, 1, 0, 0.8), 1.0)
		draw_rect(Rect2(0, 0, 20, 20), Color(1, 1, 0, 1))
