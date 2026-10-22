class_name Game
extends Node3D
## Integrator for the Phase 1 vertical slice. Builds the view (640x360 SubViewport scaled to the window), owns the
## logic objects and steps them in the JS order (js/game.js update -> simulateWorld -> stepDrink, then render):
##   clock += dt; player moves (drag speed while drinking); footsteps; door bump; lit value; feed grab / ping clicks;
##   sonar.prune; people.update; people events; villager steps; echo snapshots; stepDrink.
## Run a scripted shot with:  -- --scenario=NAME   (see tests/scenarios/). Order and what is stubbed: docs/PORT.md.
## Stubs until their phases: Night/Hunger (blood is a plain bar without drain), Barks/Listen, powers, save, audio samples.

const VIEW_W := 640
const VIEW_H := 360
const FOV_DEG := 66.0
const MAX_DIST := 16.0
# js/game.js constants
const FEED_REACH := 1.5
const DRAG_FULL := 0.25
const DRAG_EMPTY := 0.55
const DRAG_HOLD := 0.6
const DRAG_PULL := 2.4
const STRUGGLE_GAP := 0.9
const STRUGGLE_START := 0.7
const STRUGGLE_WEAK := 0.45
const STRUGGLE_FREE := 0.4
const DRINK_BOOST := 1.25
const RESTRAIN_DRINK := 0.5
const RESTRAIN_NOISE := 0.35
const SCUFFLE_GAP := 0.38
const BLOOD_MAX := 100.0
const BLOOD_START := 60.0
## Base sonar before room multipliers (js baseSonar from Sonar.DEFAULTS).
const BASE_RANGE := 10.0
const BASE_FADE := 3.0
const BASE_BOUNCES := 2

var world: World
var player: Player
var sonar: Sonar
var people: People
var audio: AudioDirector
var clock: float = 0.0
var state: String = "playing"        # playing | feeding
var blood: float = BLOOD_START
var drink: Variant = null            # Dictionary while drinking
var player_lit: float = 0.0
var map_name: String = ""
var worlds: Dictionary = {}
var world_names: Array = []
var people_by_map: Dictionary = {}
var meshes: Dictionary = {}
var transition: Variant = null   # {to_map, to_door, t, dur, swapped}
var wipe_k: float = 0.0
var cool: float = 0.0
var grace: float = 0.0
var just_arrived: Variant = null
var room_kind: String = "indoor"
var run_seed: int = 1
var night_no: int = 1
var frame_no: int = 0
var mouse_dx: float = 0.0
var step_timer: float = 0.0
var foot_right: bool = false
var feed_press: int = 0
var ping_clicks: int = 0
var interact_press: bool = false
var feed_held_mouse: bool = false
var rng := RandomNumberGenerator.new()
var react_cfg: Dictionary = {}
var room_zone: String = ""

var textures: PulseTextures
var wall_mat: ShaderMaterial
var floor_mat: ShaderMaterial
var cam: Camera3D
var viewport: SubViewport
var echo_view: EchoView
var walls_inst: MeshInstance3D
var floor_inst: MeshInstance3D
var hud: Hud
var scenario: Object = null
## Game clock used for the frame most recently handed to the renderer (read-back tests compare against it).
var last_render_clock: float = 0.0


func _ready() -> void:
	rng.seed = 1
	var scenario_name := ""
	var want_map := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--scenario="):
			scenario_name = a.substr(11)
		elif a.begins_with("--map="):
			want_map = a.substr(6)
	audio = AudioDirector.new()
	add_child(audio)
	_build_view()
	_load_worlds()
	var start_name: String = want_map if want_map != "" else String(GameData.maps()["startMap"])
	var sp := start_place(worlds[start_name])
	player = Player.create(sp["x"], sp["y"], sp["angle"])
	sonar = Sonar.create()
	enter_map(start_name, sp["x"], sp["y"], sp["angle"], "")
	if scenario_name != "":
		var script: GDScript = load("res://tests/scenarios/%s.gd" % scenario_name)
		scenario = script.new()
		scenario.setup(self)
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _build_view() -> void:
	var container := SubViewportContainer.new()
	container.stretch = true
	container.stretch_shrink = 2  # 1280x720 design size -> exactly 640x360 internal frame
	container.set_anchors_preset(Control.PRESET_FULL_RECT)
	container.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	add_child(container)
	viewport = SubViewport.new()
	viewport.size = Vector2i(VIEW_W, VIEW_H)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.msaa_3d = Viewport.MSAA_DISABLED
	container.add_child(viewport)
	cam = Camera3D.new()
	cam.keep_aspect = Camera3D.KEEP_WIDTH
	cam.fov = FOV_DEG
	cam.near = 0.02
	cam.far = MAX_DIST + 2.0
	viewport.add_child(cam)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color.BLACK
	var we := WorldEnvironment.new()
	we.environment = env
	viewport.add_child(we)
	echo_view = EchoView.new()
	viewport.add_child(echo_view)
	textures = PulseTextures.new()
	wall_mat = ShaderMaterial.new()
	wall_mat.shader = load("res://render/shaders/sonar_wall.gdshader")
	floor_mat = ShaderMaterial.new()
	floor_mat.shader = load("res://render/shaders/sonar_floor.gdshader")
	floor_mat.render_priority = -1
	hud = Hud.new()
	add_child(hud)


func _load_worlds() -> void:
	var md: Dictionary = GameData.maps()
	var res := WorldValidate.validate_all(md)
	if not res["ok"]:
		for e in res["errors"]:
			push_warning("map data: %s (%s)" % [e["message"], e["code"]])
	world_names = md["maps"].keys()
	for n in world_names:
		worlds[n] = World.from_def(md["maps"][n])


## js startPlace: the start tile, else the first door's arrival, else the first free cell.
func start_place(w: World) -> Dictionary:
	if w.start != null:
		return {"x": w.start.x, "y": w.start.y, "angle": 0.0}
	for id in w.doors_by_id:
		var a: Variant = w.arrival(id)
		if a != null:
			return a
	for y in w.height:
		for x in w.width:
			if not w.blocks(x + 0.5, y + 0.5, 0.2):
				return {"x": x + 0.5, "y": y + 0.5, "angle": 0.0}
	return {"x": 1.5, "y": 1.5, "angle": 0.0}


static func mix_seed(seed_v: int, map_index: int, night: int) -> int:
	return (seed_v ^ JsMath.u32(float(map_index) * 2654435761.0) ^ JsMath.u32(float(night) * 40503.0)) & JsMath.M32


## js peopleFor: the (cached) people state of a map.
func people_for(name: String) -> People:
	if people_by_map.has(name):
		return people_by_map[name]
	var idx: int = maxi(0, world_names.find(name))
	var sd: float = float(mix_seed(run_seed, idx, night_no))
	var st := People.create(worlds[name], GameData.map_def(name), {"seed": sd, "poolMin": 30.0, "poolMax": 50.0, "shuffle": true})
	people_by_map[name] = st
	return st


## js enterMap: switch to a map and place the player.
func enter_map(name: String, x: float, y: float, angle: float, door_id: String) -> void:
	end_drink("map")
	if people != null:
		people.clear_echoes()
	if sonar != null:
		sonar.reset()
	map_name = name
	world = worlds[name]
	people = people_for(name)
	player.place(x, y, angle)
	_show_map_mesh(name)
	apply_room()
	just_arrived = null
	if door_id != "":
		var d: Variant = world.doors_by_id.get(door_id)
		if d != null:
			world.set_door(d["col"], d["row"], true)
			just_arrived = {"map": name, "cx": d["col"], "cy": d["row"]}
		push_off_people()
	grace = float(GameData.sounds()["react"]["arriveGrace"])
	player_lit = world.light_at(player.x, player.y)
	step_timer = 0.0
	cool = 0.3
	react_cfg = GameData.sounds()["react"].duplicate()
	react_cfg["dazedTime"] = 3.0
	_sync_camera()


func _show_map_mesh(name: String) -> void:
	if not meshes.has(name):
		var walls := MeshInstance3D.new()
		walls.mesh = WorldMeshBuilder.build(worlds[name])
		walls.material_override = wall_mat
		viewport.add_child(walls)
		var fl := MeshInstance3D.new()
		fl.mesh = WorldMeshBuilder.build_floor(worlds[name])
		fl.material_override = floor_mat
		viewport.add_child(fl)
		meshes[name] = [walls, fl]
	for n in meshes:
		for inst in meshes[n]:
			inst.visible = n == name
	walls_inst = meshes[name][0]
	floor_inst = meshes[name][1]


## Nudge the player forward when the arrival point overlaps a villager (js pushOffPeople).
func push_off_people() -> void:
	var hit := false
	for p in people.people:
		if sqrt((p.x - player.x) * (p.x - player.x) + (p.y - player.y) * (p.y - player.y)) < 0.5:
			hit = true
	if not hit:
		return
	var d := 0.6
	while d >= 0.1:
		var nx: float = player.x + cos(player.angle) * d
		var ny: float = player.y + sin(player.angle) * d
		if not world.blocks(nx, ny, player.radius):
			player.x = nx
			player.y = ny
			return
		d -= 0.1


func player_kind() -> String:
	return world.kind_at(player.x, player.y)


## js applyRoom / applyReverb / followRoom: the room kind and zone at the player set the reverb.
func apply_room() -> void:
	room_kind = player_kind()
	apply_reverb(room_kind)


func apply_reverb(kind: String) -> void:
	var zone := world.zone_at(player.x, player.y)
	room_zone = zone if zone != "" else world.name
	audio.set_room(kind, Acoustics.t60_for(room_zone, kind))


func follow_room() -> void:
	var k := player_kind()
	if k != room_kind:
		apply_room()
	else:
		var z := world.zone_at(player.x, player.y)
		if (z if z != "" else world.name) != room_zone:
			apply_reverb(k)


## js changeMap: begin the wipe through a link door.
func change_map(to_map: String, to_door: String) -> bool:
	if transition != null or state != "playing":
		return false
	if not worlds.has(to_map) or worlds[to_map].arrival(to_door) == null:
		push_warning("E_MAP_LINK: no such map/door %s/%s" % [to_map, to_door])
		return false
	transition = {"to_map": to_map, "to_door": to_door, "t": 0.0, "dur": 0.7, "swapped": false}
	wipe_k = 0.0
	state = "transition"
	audio.play("creak", {"gain": SoundData.level("creak")["gain"], "pan": 0.0})
	return true


func step_transition(dt: float) -> void:
	var tr: Variant = transition
	if tr == null:
		state = "playing"
		return
	tr["t"] = float(tr["t"]) + dt
	var half: float = float(tr["dur"]) / 2.0
	if not tr["swapped"]:
		wipe_k = minf(1.0, float(tr["t"]) / half)
		if float(tr["t"]) >= half:
			wipe_k = 1.0
			tr["swapped"] = true
			var a: Dictionary = worlds[tr["to_map"]].arrival(tr["to_door"])
			enter_map(tr["to_map"], a["x"], a["y"], a["angle"], tr["to_door"])
	else:
		wipe_k = maxf(0.0, 1.0 - (float(tr["t"]) - half) / half)
		if float(tr["t"]) >= float(tr["dur"]):
			wipe_k = 0.0
			transition = null
			state = "playing"
			cool = 0.3


## js checkLinkDoor: standing in an open link door starts the transition.
func check_link_door() -> bool:
	var cx: int = int(floor(player.x))
	var cy: int = int(floor(player.y))
	var ja: Variant = just_arrived
	if ja != null and (ja["map"] != map_name or ja["cx"] != cx or ja["cy"] != cy):
		just_arrived = null
	if cool > 0.0 or just_arrived != null:
		return false
	var d: Variant = world.door_at(cx, cy)
	if d == null or not world.is_door_open(cx, cy):
		return false
	return change_map(str(d["toMap"]), str(d["toDoor"]))


## Test hook: jump to a map instantly (js debugMap).
func debug_map(name: String, door_id: String = "") -> bool:
	if not worlds.has(name):
		return false
	var a: Variant = start_place(worlds[name]) if door_id == "" else worlds[name].arrival(door_id)
	if a == null:
		return false
	transition = null
	wipe_k = 0.0
	if state == "transition":
		state = "playing"
	enter_map(name, a["x"], a["y"], a["angle"], door_id)
	return true


# ---------------------------------------------------------------- input

func _unhandled_input(event: InputEvent) -> void:
	if scenario != null:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		mouse_dx += event.relative.x
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			else:
				ping_clicks += 1
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			feed_held_mouse = event.pressed
			if event.pressed:
				feed_press += 1
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_SPACE: ping_clicks += 1
			KEY_R: feed_press += 1
			KEY_E: interact_press = true
			KEY_ESCAPE: Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func feed_held() -> bool:
	return feed_held_mouse or Input.is_physical_key_pressed(KEY_R)


func key_down(code: Key) -> bool:
	return Input.is_physical_key_pressed(code)


func _read_input() -> Dictionary:
	var k := func(code: Key) -> float: return 1.0 if Input.is_physical_key_pressed(code) else 0.0
	var inp := {
		"forward": maxf(k.call(KEY_W), k.call(KEY_UP)) - maxf(k.call(KEY_S), k.call(KEY_DOWN)),
		"strafe": k.call(KEY_D) - k.call(KEY_A),
		"turn": k.call(KEY_RIGHT) - k.call(KEY_LEFT),
		"mouseDx": mouse_dx,
	}
	mouse_dx = 0.0
	return inp


# ---------------------------------------------------------------- frame

func _process(delta: float) -> void:
	frame_no += 1
	var inp := {}
	if scenario != null:
		inp = scenario.step(self, delta)
		if inp == null:
			inp = {}
	else:
		inp = _read_input()
	step(delta, inp)
	_render()


## One logic step (js update): input -> world -> drinking. Also called directly by scripted tests.
func step(dt: float, inp: Dictionary) -> void:
	clock += dt
	audio.tick(clock)
	if state == "transition":
		step_transition(dt)
		sonar.prune(clock)
		hud.set_state(self)
		return
	var was_drinking: bool = drink != null
	if was_drinking:
		var dk: Dictionary = drink
		var di := inp.duplicate()
		di["mouseDx"] = float(inp.get("mouseDx", 0.0)) * 0.5
		var px: float = player.x
		var py: float = player.y
		var cfg := Player.DEFAULT_CFG.duplicate()
		cfg["moveSpeed"] = float(cfg["moveSpeed"]) * drag_speed_k(dk)
		player.update(world, di, dt, cfg)
		var moved: float = sqrt((player.x - px) * (player.x - px) + (player.y - py) * (player.y - py))
		step_victim_pull(dk, dt)
		player_steps(dt, moved)
	else:
		var px2: float = player.x
		var py2: float = player.y
		player.update(world, inp, dt)
		var moved2: float = sqrt((player.x - px2) * (player.x - px2) + (player.y - py2) * (player.y - py2))
		player_steps(dt, moved2)
		bump_doors(inp)
	if cool > 0.0:
		cool -= dt
	player_lit = world.light_at(player.x, player.y)
	if grace > 0.0:
		grace -= dt
	if not was_drinking:
		if check_link_door():
			feed_press = 0
			ping_clicks = 0
			interact_press = false
			return
		follow_room()
		if interact_press:
			interact()
		if feed_press > 0 and state == "playing" and not start_drink(false):
			miss_feed()
	interact_press = false
	feed_press = 0
	if ping_clicks > 0:
		pulse()
	ping_clicks = 0
	sonar.prune(clock)
	simulate_world(dt)
	if drink != null:
		step_drink(dt)
	hud.set_state(self)


# ---------------------------------------------------------------- sounds

static func num_or_1(v: Variant) -> float:
	return float(v) if (v is float or v is int) and is_finite(float(v)) and float(v) > 0.0 else 1.0


## js emitSound: emit a sound pulse at (x, y); over {range, z, bounces, rangeMul, strengthMul, fadeMul} overrides the level row.
func emit_sound(kind: String, x: float, y: float, over: Dictionary = {}) -> Sonar.Pulse:
	var lv := SoundData.level(kind)
	var room := SoundData.room_profile(world.kind_at(x, y))
	var base_range: float = float(over["range"]) if (over.get("range") is float or over.get("range") is int) else float(lv.get("range", 0.0) if lv.get("range") != null else 0.0)
	var strength: float = (float(lv["strength"]) if lv.get("strength") != null else 0.0) * num_or_1(over.get("strengthMul"))
	var bounces_v: int = int(over["bounces"]) if (over.get("bounces") is float or over.get("bounces") is int) else int(lv.get("bounces", 0))
	var opts := {
		"kind": kind,
		"range": base_range * float(room["rangeMul"]) * num_or_1(over.get("rangeMul")),
		"strength": strength,
		"bounces": mini(bounces_v, int(room["bounceCap"])),
		"visRays": 180,
	}
	if over.get("z") is float or over.get("z") is int:
		opts["z"] = over["z"]
	elif lv.get("z") is float or lv.get("z") is int:
		opts["z"] = lv["z"]
	if lv.get("fade") is float or lv.get("fade") is int:
		opts["fade"] = float(lv["fade"]) * float(room["fadeMul"]) * num_or_1(over.get("fadeMul"))
	return sonar.emit_sound(world, x, y, clock, opts)


func pan_to(x: float, y: float) -> float:
	return clampf(sin(atan2(y - player.y, x - player.x) - player.angle), -1.0, 1.0)


## First solid point on the segment (sampled every 0.25 cell, up to 25 cells) or null (js firstSolid).
func first_solid(x0: float, y0: float, x1: float, y1: float) -> Variant:
	var dx: float = x1 - x0
	var dy: float = y1 - y0
	var d: float = sqrt(dx * dx + dy * dy)
	if not (d > 0.5):
		return null
	var n: float = minf(d, 25.0) / 0.25
	var i := 1
	while i < n:
		var k: float = (i * 0.25) / d
		if world.is_solid(x0 + dx * k, y0 + dy * k):
			return Vector2(x0 + dx * k, y0 + dy * k)
		i += 1
	return null


func step_material(x: float, y: float) -> String:
	var m := world.material_at(x, y)
	return m if m == "grass" or m == "wood" else "stone"


## Audio.play options for a world sound at (x, y) (js spatial()).
func spatial(x: float, y: float, gain: float, extra: Dictionary = {}) -> Dictionary:
	var dx: float = x - player.x
	var dy: float = y - player.y
	var o := {"gain": gain, "pan": pan_to(x, y), "dist": sqrt(dx * dx + dy * dy), "behind": cos(atan2(dy, dx) - player.angle) < 0.0}
	var occ: Variant = occlusion_to(x, y)
	o["occluded"] = occ != null
	if occ != null:
		o["occ"] = occ
	o.merge(extra, true)
	return o


## Acoustic material of the solid cell at (x, y): "door" for a closed D, else the world material (js blockMaterial).
func block_material(x: float, y: float) -> String:
	if world.tile_at(x, y) == "D":
		return "door"
	var m := world.material_at(x, y)
	return m if m != "" else "stone"


## Occlusion detail for a world sound at (x, y): null when the line is clear, else {mat, diff} where diff is the least
## Maekawa loss (dB) over open doorways both the player and the sound can see (NAN when none) (js occlusionTo).
func occlusion_to(x: float, y: float) -> Variant:
	var hit: Variant = first_solid(player.x, player.y, x, y)
	if hit == null:
		return null
	var out := {"mat": block_material(hit.x, hit.y), "diff": null}
	var ac := Acoustics.a()
	var direct: float = sqrt((x - player.x) * (x - player.x) + (y - player.y) * (y - player.y))
	for dr in world.spots["doors"]:
		if not world.is_door_open(floor(dr.x), floor(dr.y)):
			continue
		var d1: float = sqrt((dr.x - player.x) * (dr.x - player.x) + (dr.y - player.y) * (dr.y - player.y))
		var d2: float = sqrt((x - dr.x) * (x - dr.x) + (y - dr.y) * (y - dr.y))
		if d1 > float(ac["doorwayReach"]) or d1 + d2 > direct + 12.0:
			continue
		if first_solid(player.x, player.y, dr.x, dr.y) != null or first_solid(dr.x, dr.y, x, y) != null:
			continue
		var loss: float = Acoustics.maekawa((d1 + d2 - direct) * float(ac["cellM"]), float(ac["maekawaHz"]))
		if out["diff"] == null or loss < float(out["diff"]):
			out["diff"] = loss
	return out


func react_to(x: float, y: float, kind: String, dist: float = -1.0) -> void:
	var d: float = dist
	if d < 0.0 and (kind == "ping" or kind == "door"):
		d = float(react_cfg["startleDist"])
	people.react(x, y, kind, people_ctx(), d if d > 0.0 else 0.0)
	drain_people_events()


func people_ctx() -> Dictionary:
	return {
		"player": {"x": player.x, "y": player.y}, "playerLit": player_lit, "react": react_cfg,
		"grace": grace, "nightFrac": 0.0, "nightSec": 0.0, "fear": 0.0,
	}


func drain_people_events() -> void:
	for e in people.drain_events():
		if e["type"] == "flee" and drink != null and int(e["id"]) != int(drink["id"]):
			drink["interrupt"] = true
		var kind: String = ""
		match e["type"]:
			"scream": kind = "scream"
			"startle": kind = "startle"
			"whimper": kind = "whimper"
		if kind == "":
			continue
		emit_sound(kind, e["x"], e["y"])
		audio.play(kind, spatial(e["x"], e["y"], float(SoundData.level(kind)["gain"])))


func player_steps(dt: float, moved: float) -> void:
	var moving: bool = dt > 0.0 and moved / dt > 0.3
	if not moving:
		step_timer = 0.0
		return
	step_timer += dt
	var lv := SoundData.level("step")
	var iv: float = float(lv.get("interval", 0.48))
	if step_timer < iv:
		return
	step_timer -= iv
	var ahead: float = float(lv.get("footOffset", 0.15))
	var side: float = float(lv.get("footSide", 0.12)) * (1.0 if foot_right else -1.0)
	var fx: float = player.x + cos(player.angle) * ahead + cos(player.angle + PI / 2.0) * side
	var fy: float = player.y + sin(player.angle) * ahead + sin(player.angle + PI / 2.0) * side
	var foot := Vector2(player.x, player.y) if world.is_solid(fx, fy) else Vector2(fx, fy)
	emit_sound("step", foot.x, foot.y)
	audio.play("step", {"gain": lv["gain"], "foot": 1 if foot_right else 0, "pan": 0.25 if foot_right else -0.25, "material": step_material(player.x, player.y)})
	foot_right = not foot_right


## js pulse(): the click ping with room-scaled range, fade and bounces, then startle reactions and audio.
func pulse() -> bool:
	var room := SoundData.room_profile(player_kind())
	var keep := [sonar.range_, sonar.bounces, sonar.fade]
	sonar.range_ = BASE_RANGE * float(room["rangeMul"])
	sonar.bounces = mini(BASE_BOUNCES, int(room["bounceCap"]))
	sonar.fade = BASE_FADE * float(room["fadeMul"])
	var fired: bool = sonar.emit(world, player.x, player.y, clock, {"z": SoundData.level("ping")["z"], "facing": player.angle})
	sonar.range_ = keep[0]
	sonar.bounces = keep[1]
	sonar.fade = keep[2]
	if not fired:
		return false
	react_to(player.x, player.y, "ping")
	audio.ping(sonar.last_pulse, player, world, self)
	return true


func miss_feed() -> void:
	audio.play("miss", {"gain": SoundData.level("miss")["gain"], "pan": 0.0})


func toggle_door(cx: int, cy: int, want_open: bool) -> bool:
	if world.is_door_open(cx, cy) == want_open:
		return false
	if not want_open:
		if _overlaps_cell(player.x, player.y, player.radius, cx, cy):
			return false
		for p in people.people:
			if _overlaps_cell(p.x, p.y, 0.25, cx, cy):
				return false
	world.set_door(cx, cy, want_open)
	var x: float = cx + 0.5
	var y: float = cy + 0.5
	emit_sound("door", x, y)
	react_to(x, y, "door")
	audio.play("doorOpen" if want_open else "doorClose", spatial(x, y, float(SoundData.level("door")["gain"])))
	return true


static func _overlaps_cell(x: float, y: float, r: float, cx: int, cy: int) -> bool:
	return x > cx - r and x < cx + 1 + r and y > cy - r and y < cy + 1 + r


func bump_doors(inp: Dictionary) -> void:
	var f: float = float(inp.get("forward", 0.0))
	var s: float = float(inp.get("strafe", 0.0))
	if f == 0.0 and s == 0.0:
		return
	var dirx: float = f * cos(player.angle) + s * cos(player.angle + PI / 2.0)
	var diry: float = f * sin(player.angle) + s * sin(player.angle + PI / 2.0)
	var length: float = sqrt(dirx * dirx + diry * diry)
	if not (length > 0.0):
		return
	var reach: float = player.radius + 0.12
	var cx: int = int(floor(player.x + (dirx / length) * reach))
	var cy: int = int(floor(player.y + (diry / length) * reach))
	var ch := world.tile_at(cx + 0.5, cy + 0.5)
	if (ch == "D" or ch == "G") and not world.is_door_open(cx, cy):
		toggle_door(cx, cy, true)


## E: toggle the nearest door in reach and in front (js interact, doors only for the slice).
func interact() -> String:
	var reach: float = float(GameData.sounds()["reach"])
	var arc: float = float(GameData.sounds()["reachArc"])
	var best: Variant = null
	var best_d := INF
	var doors: Array = world.spots["doors"]
	for i in doors.size():
		var dx: float = doors[i].x - player.x
		var dy: float = doors[i].y - player.y
		var d: float = sqrt(dx * dx + dy * dy)
		if d > reach or d >= best_d:
			continue
		var da: float = atan2(dy, dx) - player.angle
		da = atan2(sin(da), cos(da))
		if absf(da) > arc and d > 0.7:
			continue
		best = doors[i]
		best_d = d
	if best != null:
		var cx: int = int(floor(best.x))
		var cy: int = int(floor(best.y))
		return "door" if toggle_door(cx, cy, not world.is_door_open(cx, cy)) else "blocked"
	return "none"


# ---------------------------------------------------------------- world simulation

func simulate_world(dt: float) -> void:
	var t_prev: float = clock - dt
	people.update(world, dt, people_ctx())
	drain_people_events()
	people_sounds(t_prev)
	var made := people.update_echoes(sonar, t_prev, clock)
	for e in made:
		e.pan = clampf(sin(atan2(e.y - player.y, e.x - player.x) - player.angle), -1.0, 1.0)
		audio.person_echo(e, sonar)


func people_sounds(_t_prev: float) -> void:
	var lv := SoundData.level("personStep")
	for e in people.step_events():
		var mat := step_material(e["x"], e["y"])
		var sc := SoundData.step_scale(e["gait"], mat, e["pace"])
		var guard_step: bool = e["gait"] == "mail"
		var side: float = (1.0 if e["foot"] != 0 else -1.0) * 0.12
		var fx: float = e["x"] - sin(e["angle"]) * side
		var fy: float = e["y"] + cos(e["angle"]) * side
		emit_sound("personStep", fx, fy, {"rangeMul": sc["range"], "strengthMul": sc["strength"], "fadeMul": sc["fade"]})
		var g: float = float(SoundData.level("guardStep")["gain"]) if guard_step else float(lv["gain"])
		audio.play("guardStep" if guard_step else "personStep", spatial(e["x"], e["y"], minf(1.0, g * sc["gain"]), {"material": mat}))
	# Choice: people open any closed door they come within 1 cell of; it stays open.
	for p in people.people:
		for d in world.spots["doors"]:
			var cx: int = int(floor(d.x))
			var cy: int = int(floor(d.y))
			if not world.is_door_open(cx, cy) and sqrt((p.x - d.x) * (p.x - d.x) + (p.y - d.y) * (p.y - d.y)) < 1.0:
				toggle_door(cx, cy, true)


# ---------------------------------------------------------------- feeding

func drag_speed_k(d: Dictionary) -> float:
	var f: float = clampf(float(d["left"]) / float(d["pool"]), 0.0, 1.0) if float(d["pool"]) > 0.0 else 0.0
	return DRAG_EMPTY + (DRAG_FULL - DRAG_EMPTY) * f


## Push (or refresh) a snapshot echo of a person so the feed lock has a figure to draw (js pushVictimEcho).
func push_victim_echo(p: People.Person) -> void:
	var i: int = people.echoes.size() - 1
	while i >= 0:
		if people.echoes[i].person_id == p.id:
			people.echoes.remove_at(i)
		i -= 1
	var e := People.Echo.new()
	e.person_id = p.id
	e.x = p.x
	e.y = p.y
	e.angle = p.angle
	e.look_angle = p.look_angle
	e.phase = p.phase
	e.t = clock
	e.dist = sqrt((p.x - player.x) * (p.x - player.x) + (p.y - player.y) * (p.y - player.y))
	e.strength = 0.9
	e.pan = pan_to(p.x, p.y)
	e.look = p.look
	e.z_min = 0.0
	e.z_max = 1.2
	e.fade = 2.2
	people.echoes.append(e)
	while people.echoes.size() > people.max_echoes:
		people.echoes.pop_front()


func start_drink(forced: bool) -> bool:
	if state != "playing" or drink != null:
		return false
	var target := people.feed_target(player.x, player.y, player.angle, FEED_REACH, deg_to_rad(60.0))
	if target == null:
		return false
	var front: bool = People.sees(target, world, player.x, player.y, People.REACT_DEFAULTS)
	if not people.grab(target.id):
		return false
	drink = {
		"id": target.id, "person": target, "pool": target.pool if target.pool > 0.0 else 40.0, "left": target.left, "drunk": 0.0,
		"beatAt": 0.1, "t": 0.0, "forced": forced, "interrupt": false, "struggleAt": STRUGGLE_START, "lastStruggle": -99.0,
		"rs": 0.0, "scuffAcc": 0.0, "pullEcho": 0.0,
	}
	state = "feeding"
	push_victim_echo(target)
	if front:
		emit_sound("gasp", target.x, target.y)
		audio.play("gasp", spatial(target.x, target.y, float(SoundData.level("gasp")["gain"])))
		react_to(target.x, target.y, "gasp")
	return true


## Ease the victim to DRAG_HOLD cells in front of the player, without walking through walls (js stepVictimPull).
func step_victim_pull(d: Dictionary, dt: float) -> void:
	var v: People.Person = d["person"]
	var tx: float = player.x + cos(player.angle) * DRAG_HOLD
	var ty: float = player.y + sin(player.angle) * DRAG_HOLD
	var dx: float = tx - v.x
	var dy: float = ty - v.y
	var dist: float = sqrt(dx * dx + dy * dy)
	if dist < 0.02:
		return
	var step: float = minf(dist, DRAG_PULL * dt)
	var mx: float = dx / dist * step
	var my: float = dy / dist * step
	var moved := false
	if not world.blocks(v.x + mx, v.y, 0.2):
		v.x += mx
		moved = true
	if not world.blocks(v.x, v.y + my, 0.2):
		v.y += my
		moved = true
	if moved:
		v.angle = atan2(player.y - v.y, player.x - v.x)
		d["pullEcho"] = float(d["pullEcho"]) + dt
		if float(d["pullEcho"]) >= 0.1:
			d["pullEcho"] = 0.0
			push_victim_echo(v)
		d["scuffAcc"] = float(d["scuffAcc"]) + dt
		if float(d["scuffAcc"]) >= SCUFFLE_GAP:
			d["scuffAcc"] = 0.0
			emit_sound("scuffle", v.x, v.y)
			react_to(v.x, v.y, "scuffle", float(SoundData.level("scuffle")["range"]))
			audio.play("scuffle", spatial(v.x, v.y, float(SoundData.level("scuffle")["gain"]), {"material": step_material(v.x, v.y)}))


## One drinking tick: blood flows, beats fire, stop rules run (js stepDrink).
func step_drink(dt: float) -> void:
	var d: Dictionary = drink
	var p: People.Person = d["person"]
	d["t"] = float(d["t"]) + dt
	if d["interrupt"]:
		end_drink("witness")
		return
	if not d["forced"] and float(d["t"]) > dt * 1.5 and not feed_held():
		end_drink("released")
		return
	if sqrt((p.x - player.x) * (p.x - player.x) + (p.y - player.y) * (p.y - player.y)) > FEED_REACH + 0.3:
		end_drink("reach")
		return
	var want_rs: float = 1.0 if key_down(KEY_E) else 0.0
	d["rs"] = float(d["rs"]) + (want_rs - float(d["rs"])) * (1.0 - exp(-dt / 0.12))
	if float(d["t"]) >= float(d["struggleAt"]) and struggle(d):
		return
	if blood >= BLOOD_MAX:
		end_drink("cap")
		return
	var rate: float = (2.5 + 4.5 * clampf(float(d["left"]) / float(d["pool"]), 0.0, 1.0)) * DRINK_BOOST * (1.0 - (1.0 - RESTRAIN_DRINK) * float(d["rs"]))
	var gain: float = minf(BLOOD_MAX, blood + rate * dt) - blood
	blood += gain
	d["drunk"] = float(d["drunk"]) + gain
	var left: float = people.drink(int(d["id"]), gain)
	d["left"] = left if left >= 0.0 else 0.0
	if float(d["left"]) <= 0.5:
		end_drink("empty")
		return
	if float(d["t"]) >= float(d["beatAt"]):
		drink_beat(d)
		if d["interrupt"]:
			end_drink("witness")
			return
		var bpm: float = 50.0 + 70.0 * clampf(float(d["left"]) / float(d["pool"]), 0.0, 1.0)
		d["beatAt"] = float(d["beatAt"]) + 60.0 / bpm
	if blood >= BLOOD_MAX:
		end_drink("cap")


## One struggle attempt (js struggle()): returns true if the victim broke free.
func struggle(d: Dictionary) -> bool:
	var v: People.Person = d["person"]
	var frac: float = clampf(float(d["left"]) / float(d["pool"]), 0.0, 1.0)
	d["struggleAt"] = float(d["struggleAt"]) + STRUGGLE_GAP * (0.8 + 0.4 * rng.randf())
	d["lastStruggle"] = d["t"]
	var strong: float = clampf((frac - STRUGGLE_WEAK) / (1.0 - STRUGGLE_WEAK), 0.0, 1.0)
	var rs: float = 1.0 if float(d["rs"]) > 0.5 else 0.0
	var k: float = (0.35 + 0.65 * maxf(strong, 0.3)) * (1.0 - (1.0 - RESTRAIN_NOISE) * rs)
	emit_sound("struggle", v.x, v.y, {"rangeMul": k, "strengthMul": k})
	react_to(v.x, v.y, "struggle", float(SoundData.level("struggle")["range"]) * k + 0.5)
	audio.play("struggle", spatial(v.x, v.y, float(SoundData.level("struggle")["gain"]) * k))
	push_victim_echo(v)
	if rs > 0.0 or strong <= 0.0 or rng.randf() >= STRUGGLE_FREE * strong:
		return false
	end_drink("broke")
	if v.mode == "dazed":
		v.dazed_left = minf(v.dazed_left, 0.15)
	emit_sound("scream", v.x, v.y)
	audio.play("scream", spatial(v.x, v.y, float(SoundData.level("scream")["gain"])))
	react_to(v.x, v.y, "scream", 5.0)
	return true


## One heartbeat: sonar pulse from the victim, startle radius, audio, echo refresh.
func drink_beat(d: Dictionary) -> void:
	var v: People.Person = d["person"]
	var r: float = 1.5 + 2.5 * clampf(float(d["drunk"]) / float(d["pool"]), 0.0, 1.0)
	emit_sound("heartbeat", v.x, v.y, {"range": r, "z": 0.55, "bounces": 0})
	react_to(v.x, v.y, "heartbeat", r)
	audio.play("heartbeat", spatial(v.x, v.y, float(SoundData.level("heartbeat")["gain"]) * (0.6 + 0.4 * clampf(float(d["left"]) / float(d["pool"]), 0.0, 1.0))))
	push_victim_echo(v)


## Stop drinking. Fully drained: fed. Otherwise the victim is released dazed.
func end_drink(_reason: String) -> void:
	var d: Variant = drink
	if d == null:
		return
	drink = null
	var p: People.Person = d["person"]
	if p.left <= 0.5:
		people.mark_fed(int(d["id"]))
	else:
		people.release(int(d["id"]), player.x, player.y)
	if state == "feeding":
		state = "playing"


# ---------------------------------------------------------------- render

func lock_info() -> Dictionary:
	if drink == null:
		return {}
	var d: Dictionary = drink
	return {"id": d["id"], "k": 1.0 - clampf(float(d["left"]) / float(d["pool"]), 0.0, 1.0), "age": float(d["t"]), "sp": 9.0, "rs": float(d["rs"])}


func _render() -> void:
	last_render_clock = clock
	_sync_camera()
	textures.sync_from(sonar)
	for m in [wall_mat, floor_mat]:
		textures.apply_to(m)
		m.set_shader_parameter("game_time", clock)
	wall_mat.set_shader_parameter("boil_frame", int(floor(clock * 10.0)) % 4)
	echo_view.render_frame(world, player, people, sonar, clock, lock_info())


func _sync_camera() -> void:
	cam.position = Coords.to_view(player.x, player.y, 0.5)
	cam.rotation = Vector3(0.0, -player.angle - PI / 2.0, 0.0)
