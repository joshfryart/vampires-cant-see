extends RefCounted
## Scenario: the ink-etched wall style tour (docs/STYLE.md S3). Free play on generated stage maps (seed 7), one ping per view with the front
## mid-flight, at render quality 3 then 0: cave passage, echo hall, squeeze, pool, wood, moor, road, inn.
## It writes frames with Movie Maker; shots.txt in the movie directory maps frame numbers to view names (the first listed frame of each view
## is 12 frames after the ping, the second 24). Pick the files out and delete the rest.
## Use: godot --path project --rendering-driver opengl3 --write-movie <ABSOLUTE dir>\f.png --fixed-fps 60 --quit-after 1170 -- --scenario=style_tour
## Extra user args: --tour-dir=<absolute dir for shots.txt> (scripts cannot see the movie path, so pass it), --only=cave_passage,moor (subset of views),
## --novib (no struck-wall vibration lines), --dist=5 (the free ray length to face), --qs=3,0 (qualities to tour, default both; the recorded length is views x qualities x 72 frames + 10)

const BLOCK := 72
const PING_AT := 22
const SHOT_A := 34
const SHOT_B := 46
const SEED := 7
## name, stage id, target (a beat id prefix for the cave, else a tile char to face)
const VIEWS := [
	["cave_passage", "hollow", "beat:drip"],
	["echo_hall", "hollow", "beat:echo"],
	["squeeze", "hollow", "beat:squeeze"],
	["pool", "hollow", "beat:pool"],
	["wood", "wood", "tile:W"],
	["moor", "moor", "tile:B"],
	["road", "road", "tile:B"],
	["inn", "inn", "tile:W"],
]

var _defs: Dictionary = {}
var _views: Array = VIEWS.duplicate()
var _qs: Array = [3, 0]
var _novib := false
var _dist := 5.0
var _log: Array = []
var _dir := ""


func setup(g: Node) -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--tour-dir="):
			_dir = a.substr(11)
		elif a.begins_with("--only="):
			var want: PackedStringArray = a.substr(7).split(",")
			_views = VIEWS.filter(func(v): return want.has(v[0]))
		elif a == "--novib":
			_novib = true
		elif a.begins_with("--dist="):
			_dist = float(a.substr(7))
		elif a.begins_with("--qs="):
			_qs = []
			for t in a.substr(5).split(","):
				_qs.append(int(t))
	g.echo_view.gov.enabled = false
	for v in _views:
		var id: String = v[1]
		if not _defs.has(id):
			_defs[id] = StageGen.generate(id, SEED)
			g.add_world(id, _defs[id])
	g.debug_map(String(_views[0][1]))


func _set_quality(g: Node, q: int) -> void:
	g.echo_view.gov.quality = q
	g.echo_view.gov.mat_detail = q >= 2
	g.apply_config()


func _free_ray(w: World, x: float, y: float, ang: float) -> float:
	var d := 0.0
	while d < 12.0:
		if w.is_solid(x + cos(ang) * d, y + sin(ang) * d):
			break
		d += 0.1
	return d


func _best_angle(w: World, x: float, y: float) -> float:
	var best := 0.0
	var bd := -1.0
	for k in 32:
		var a := TAU * float(k) / 32.0
		var d := _free_ray(w, x, y, a)
		var sc := absf(minf(d, 12.0) - _dist) + (100.0 if d < 3.0 else 0.0)
		if bd < 0.0 or sc < bd:
			bd = sc
			best = a
	return best


## Stand 3 to 4 cells from the nearest cell of `ch` with a clear line to it, facing it.
func _face_tile(w: World, ch: String, from: Vector2) -> Array:
	var tgt := Vector2.ZERO
	var best := 1e9
	for y in w.height:
		for x in w.width:
			if w.tile_at(x + 0.5, y + 0.5) == ch:
				var dd := Vector2(x + 0.5, y + 0.5).distance_to(from)
				if dd < best:
					best = dd
					tgt = Vector2(x + 0.5, y + 0.5)
	if best > 1e8:
		return [from.x, from.y, _best_angle(w, from.x, from.y)]
	var pick := from
	var pd := 1e9
	for dy in range(-6, 7):
		for dx in range(-6, 7):
			var c := tgt + Vector2(dx, dy)
			if w.blocks(c.x, c.y, 0.25):
				continue
			var d := c.distance_to(tgt)
			if d < 2.6 or d > 4.2:
				continue
			var ang := atan2(tgt.y - c.y, tgt.x - c.x)
			if _free_ray(w, c.x, c.y, ang) < d - 0.6:
				continue
			var score := absf(d - 3.2) + c.distance_to(from) * 0.01
			if score < pd:
				pd = score
				pick = c
	return [pick.x, pick.y, atan2(tgt.y - pick.y, tgt.x - pick.x)]


func _place(g: Node, v: Array) -> void:
	var id: String = v[1]
	if g.map_name != id:
		g.debug_map(id)
	var w: World = g.world
	var def: Dictionary = _defs[id]
	var start: Vector2 = Vector2(float(def["start"]["cell"][0]) + 0.5, float(def["start"]["cell"][1]) + 0.5)
	var spec: String = v[2]
	var at: Array
	if spec.begins_with("beat:"):
		var pre := spec.substr(5)
		var c := start
		for b in def["beats"]:
			if String(b["id"]).contains(pre):
				c = Vector2(float(b["cell"][0]) + 0.5, float(b["cell"][1]) + 0.5)
				break
		at = [c.x, c.y, _best_angle(w, c.x, c.y)]
	else:
		at = _face_tile(w, spec.substr(5), start)
	g.player.place(at[0], at[1], at[2])


func step(g: Node, _delta: float) -> Dictionary:
	var f: int = g.frame_no
	var n := _views.size()
	var k: int = (f - 10) / BLOCK
	var at: int = (f - 10) % BLOCK
	if f >= 10 and k < _qs.size() * n:
		var v: Array = _views[k % n]
		var q: int = _qs[k / n]
		if at == 0:
			if k % n == 0:
				_set_quality(g, q)
			_place(g, v)
		if at == 2 and _novib:
			g.wall_mat.set_shader_parameter("vib_on", 0.0) # the struck-wall shiver lines look like strata for a moment: judge the strata without them
		if at == PING_AT:
			g.ping_clicks += 1
		if at == SHOT_A:
			print("STYLETOUR %s q%d pos %.2f,%.2f ang %.2f solid=%s pulses=%d" % [v[0], q, g.player.x, g.player.y, g.player.angle, str(g.world.is_solid(g.player.x, g.player.y)), g.sonar.pulses.size()])
		if at == SHOT_A or at == SHOT_B:
			_log.append("%d %s_q%d_%s" % [f, v[0], q, "a" if at == SHOT_A else "b"])
	if f == 10 + _qs.size() * n * BLOCK - 1 and _dir != "":
		var fa := FileAccess.open(_dir.path_join("shots.txt"), FileAccess.WRITE)
		if fa != null:
			fa.store_string("\n".join(_log))
	return {}
