class_name Game
extends Node3D
## Integrator for the Phase 1 vertical slice. Builds the view (640x360 SubViewport scaled to the window), owns the
## logic objects and steps them in the JS order (js/game.js update -> simulateWorld -> stepDrink, then render):
##   clock += dt; player moves (drag speed while drinking); footsteps; door bump; lit value; feed grab / ping clicks;
##   sonar.prune; people.update; people events; villager steps; echo snapshots; stepDrink.
## Run a scripted shot with:  -- --scenario=NAME   (see tests/scenarios/). Order and what is stubbed: docs/PORT.md.
## Runs, nights, blood drain, boons, gifts, powers, sleep and saves live in RunFlow and Powers (run_flow.gd, powers.gd).
## Free play (scenarios, --map=) has no night: blood is a plain bar and nothing drains.

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
const CARD_LEN := 2.4
const SLEEP_STATES := ["playing", "transition", "feeding", "sleeping"]

## Tests give the Game an in-memory save store.
static var test_storage: Object = null
static var manual_boot: bool = false

var world: World
var player: Player
var sonar: Sonar
var people: People
var audio: AudioDirector
var clock: float = 0.0
var state: String = "playing"        # playing | feeding
var blood_free: float = BLOOD_START
var blood: float:
	get: return night.blood if night != null else blood_free
	set(v):
		if night != null:
			night.blood = v
		else:
			blood_free = v
var drink: Variant = null            # Dictionary while drinking
var player_lit: float = 0.0
var map_name: String = ""
var worlds: Dictionary = {}
var world_names: Array = []
var people_by_map: Dictionary = {}
var meshes: Dictionary = {}
var light_images: Dictionary = {}
var light_textures: Dictionary = {}
var transition: Variant = null   # {to_map, to_door, t, dur, swapped}
var wipe_k: float = 0.0
var cool: float = 0.0
var grace: float = 0.0
var just_arrived: Variant = null
var room_kind: String = "indoor"
var run_seed: int:
	get: return int(flow.run["seed"]) if flow != null and flow.run != null else 1
var night_no: int:
	get: return night.night if night != null else 1
var night: Night = null
var hunger: Hunger = null
var flow: RunFlow
var powers: Powers
var run_on: bool = false
var seed_base: int = 0
var card_text: String = ""
var card_sub: String = ""
var card_age: float = 0.0
var gift_flash: float = 0.0
var over_acc: float = 0.0
var pressed: Dictionary = {}
var last_input: Dictionary = {}
var fm: Dictionary = {"startleMul": 1.0, "fleeMul": 1.0, "calmMul": 1.0}
var react_key: float = -1.0
var react_dz: float = -1.0
var barks_st: Barks = null
var listen_st: Listen = null
var bark_sub: Variant = null       # {de, en, muffled, speaker, dist, start, end}
var lis_px: float = NAN
var lis_py: float = NAN
var lis_speed: float = 0.0
var last_victim: Variant = null
var reduced: bool = false           # reduced motion (config comes in Phase 8)
var ripple := RippleFx.Rings.new()   # secondary echo rings (js S.ripple)
const FIRE_NEAR := 1.5
const AMBIENCE_GAIN := 0.6
var far_rng: Rng = null
const GRAB_FOV := 54.0 / 66.0
var fov_k: float = 0.0
var vial_pulse: float = 0.0
var landings: Array = []
var veil_k: float = 0.0
var hud_a: float = 0.0
var hud_frac: float = 0.0
var hint_text: String = ""
var hint_age: float = 0.0
var hint_dur: float = 4.0
var hint_t: float = 0.0
var cfg: Dictionary = Config.defaults_copy()
var player_cfg: Dictionary = Player.DEFAULT_CFG.duplicate()
var base_range: float = BASE_RANGE
var base_fade: float = BASE_FADE
var feed_reach: float = FEED_REACH
var feed_arc: float = deg_to_rad(60.0)
var pool_min: float = 30.0
var pool_max: float = 50.0
var dazed_time: float = 3.0
var feed_toggle: bool = false
var show_subtitles: bool = true
var show_translation: bool = true
var villager_voices: bool = true
var large_text: bool = false
var fov_base_deg: float = FOV_DEG
var ambience_gain: float = AMBIENCE_GAIN
var tut: Tutorial
var hud_view: HudView
var fx_grade: ColorRect
var fx_grade_mat: ShaderMaterial
var fx_overlay: ColorRect
var fx_overlay_mat: ShaderMaterial
var dog_t: float = 25.0
var bell_t: float = 30.0
var amb_key: String = ""
var amb_lvl: float = -1.0
var menus: Control
var frame_no: int = 0
var mouse_dx: float = 0.0
var step_timer: float = 0.0
## Head bob (js updateBob): amplitude ramp, walk cycle phase and the resulting vertical offset in 640x360 pixels.
var bob_amp: float = 0.0
var walk_phase: float = 0.0
var bob: float = 0.0
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
var ceil_mat: ShaderMaterial
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
	if not manual_boot:
		boot()


## The body of _ready, callable by tests that build the Game outside the tree.
func boot() -> void:
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
	cfg = Config.load_file() if test_storage == null else Config.defaults_copy()
	flow = RunFlow.new(self, test_storage)
	tut = Tutorial.new(self, test_storage == null)
	powers = Powers.new(self)
	var start_name: String = want_map if want_map != "" else String(GameData.maps()["startMap"])
	var sp := start_place(worlds[start_name])
	player = Player.create(sp["x"], sp["y"], sp["angle"])
	sonar = Sonar.create()
	apply_config()
	enter_map(start_name, sp["x"], sp["y"], sp["angle"], "")
	if scenario_name != "":
		var script: GDScript = load("res://tests/scenarios/%s.gd" % scenario_name)
		scenario = script.new()
		scenario.setup(self)
	elif want_map != "":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		set_state("title")


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
	ceil_mat = ShaderMaterial.new()
	ceil_mat.shader = floor_mat.shader
	ceil_mat.set_shader_parameter("is_ceiling", true)
	fx_grade = ColorRect.new()
	fx_grade.set_anchors_preset(Control.PRESET_FULL_RECT)
	fx_grade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fx_grade_mat = ShaderMaterial.new()
	fx_grade_mat.shader = load("res://render/shaders/postfx_grade.gdshader")
	fx_grade.material = fx_grade_mat
	viewport.add_child(fx_grade)
	hud_view = HudView.new()
	viewport.add_child(hud_view)
	fx_overlay = ColorRect.new()
	fx_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	fx_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fx_overlay_mat = ShaderMaterial.new()
	fx_overlay_mat.shader = load("res://render/shaders/postfx_overlay.gdshader")
	fx_overlay.material = fx_overlay_mat
	viewport.add_child(fx_overlay)
	hud = Hud.new()
	add_child(hud)
	menus = Menus.new()
	add_child(menus)


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
func people_for(name: String, seed_override: Variant = null) -> People:
	if people_by_map.has(name) and (seed_override == null or people_by_map[name].seed_value == float(seed_override)):
		return people_by_map[name]
	var idx: int = maxi(0, world_names.find(name))
	var sd: float = float(seed_override) if seed_override != null else float(mix_seed(run_seed, idx, night_no))
	var st := People.create(worlds[name], GameData.map_def(name), {"seed": sd, "poolMin": pool_min, "poolMax": pool_max, "shuffle": true})
	people_by_map[name] = st
	return st


## js enterMap: switch to a map and place the player.
func enter_map(name: String, x: float, y: float, angle: float, door_id: String) -> void:
	end_drink("map")
	if people != null:
		people.clear_echoes()
	if sonar != null:
		sonar.reset()
	ripple.rings.clear()
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
			update_light_texture()
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
		var ce := MeshInstance3D.new()
		ce.mesh = WorldMeshBuilder.build_ceiling(worlds[name])
		ce.material_override = ceil_mat
		viewport.add_child(ce)
		meshes[name] = [walls, fl, ce]
	for n in meshes:
		for inst in meshes[n]:
			inst.visible = n == name
	walls_inst = meshes[name][0]
	floor_inst = meshes[name][1]
	update_light_texture()


## Upload the current map's light grid for the wall shader (windows glow when the room beyond is lit).
func update_light_texture() -> void:
	var w := world
	var img: Image = light_images.get(map_name)
	if img == null:
		img = Image.create(w.width, w.height, false, Image.FORMAT_RF)
		light_images[map_name] = img
	for y in w.height:
		for x in w.width:
			img.set_pixel(x, y, Color(w.light_grid[y * w.width + x], 0, 0, 1))
	var tex: ImageTexture = light_textures.get(map_name)
	if tex == null:
		tex = ImageTexture.create_from_image(img)
		light_textures[map_name] = tex
	else:
		tex.update(img)
	wall_mat.set_shader_parameter("light_tex", tex)
	wall_mat.set_shader_parameter("map_size", Vector2(w.width, w.height))


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
				if state == "playing" or state == "feeding":
					Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			else:
				ping_clicks += 1
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			feed_held_mouse = event.pressed
			if event.pressed:
				feed_press += 1
	elif event is InputEventKey and event.pressed and not event.echo:
		pressed[event.physical_keycode] = true
		match event.physical_keycode:
			KEY_SPACE: ping_clicks += 1
			KEY_R: feed_press += 1
			KEY_E: interact_press = true
			KEY_ESCAPE:
				if state == "playing" or state == "transition" or state == "feeding":
					pause()
				elif state == "paused":
					resume()
				else:
					Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


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
	last_input = inp
	var st0: String = state
	if st0 == "title" or st0 == "paused" or st0 == "runend" or st0 == "error":
		pressed.clear()
		hud.set_state(self)
		return
	if st0 == "boon" or st0 == "gift":
		for i in 3:
			if pressed.has(KEY_1 + i) or pressed.has(KEY_KP_1 + i):
				if st0 == "gift":
					flow.pick_gift(i)
				else:
					flow.pick_boon(i)
				break
		pressed.clear()
		hud.set_state(self)
		return
	if card_text != "":
		card_age += dt
		if card_age > CARD_LEN:
			card_text = ""
			card_sub = ""
	if st0 == "sleeping":
		clock += dt
		audio.tick(clock)
		flow.step_seq(dt)
		sonar.prune(clock)
		pressed.clear()
		hud.set_state(self)
		return
	clock += dt
	audio.tick(clock)
	if hunger != null:
		hunger.tick(dt)
	if gift_flash > 0.0:
		gift_flash = maxf(0.0, gift_flash - dt / 0.8)
	if state == "transition":
		step_transition(dt)
		sonar.prune(clock)
		pressed.clear()
		hud.set_state(self)
		return
	var was_drinking: bool = drink != null
	if not was_drinking and state == "playing":
		powers.power_keys()
	if powers.mist_vis > 0.0:
		powers.mist_vis = maxf(0.0, powers.mist_vis - dt / 0.45)
	if was_drinking:
		var dk: Dictionary = drink
		var di := inp.duplicate()
		di["mouseDx"] = float(inp.get("mouseDx", 0.0)) * 0.5
		var px: float = player.x
		var py: float = player.y
		var dcfg := player_cfg.duplicate()
		dcfg["moveSpeed"] = float(dcfg["moveSpeed"]) * drag_speed_k(dk)
		player.update(world, di, dt, dcfg)
		var moved: float = sqrt((player.x - px) * (player.x - px) + (player.y - py) * (player.y - py))
		step_victim_pull(dk, dt)
		player_steps(dt, moved)
	else:
		var px2: float = player.x
		var py2: float = player.y
		if powers.mist != null:
			var im := inp.duplicate()
			im["forward"] = 0.0
			im["strafe"] = 0.0
			player.update(world, im, dt)
			powers.step_mist(dt)
			step_timer = 0.0
		else:
			var cfg2 := player_cfg
			if listen_st != null and listen_st.active:
				cfg2 = player_cfg.duplicate()
				cfg2["moveSpeed"] = float(cfg2["moveSpeed"]) * Listen.MOVE_K
			player.update(world, inp, dt, cfg2)
			var moved2: float = sqrt((player.x - px2) * (player.x - px2) + (player.y - py2) * (player.y - py2))
			player_steps(dt, moved2)
			bump_doors(inp)
	if cool > 0.0:
		cool -= dt
	if powers.rock_cool > 0.0:
		powers.rock_cool -= dt
	powers.step_rocks()
	player_lit = world.light_at(player.x, player.y)
	veil_k += (clampf(player_lit, 0.0, 1.0) - veil_k) * (1.0 - exp(-dt / 0.3))
	if grace > 0.0:
		grace -= dt
	step_listen(dt)
	if not was_drinking:
		if check_link_door():
			feed_press = 0
			ping_clicks = 0
			interact_press = false
			pressed.clear()
			return
		follow_room()
		if interact_press:
			interact()
		if pressed.has(KEY_G):
			powers.throw_rock()
		if feed_press > 0 and state == "playing" and not start_drink(false):
			miss_feed()
	interact_press = false
	feed_press = 0
	if ping_clicks > 0:
		pulse()
	ping_clicks = 0
	sonar.prune(clock)
	simulate_world(dt)
	step_barks(dt)
	tut.step(dt)
	if run_on:
		step_ambient(dt)
		crackle_torches()
	update_ambience()
	if night != null and flow.step_night(dt):
		pressed.clear()
		hud.set_state(self)
		return
	if drink != null:
		step_drink(dt)
	step_feed_fx(dt)
	var cd: float = sonar.cooldown_left(clock)
	if cd > 0.0:
		hud_frac = minf(1.0, cd / (sonar.cooldown if sonar.cooldown > 0.0 else 0.8))
	hud_a = clampf(hud_a + (dt if cd > 0.0 else -dt) / 0.15, 0.0, 1.0)
	if flow != null:
		flow.tick_autosave(dt)
	pressed.clear()
	hud.set_state(self)


func pause() -> void:
	if drink != null:
		end_drink("pause")
	if state != "playing" and state != "transition":
		return
	set_state("paused")
	flow.save_run("pause")


func resume() -> void:
	if state == "paused":
		set_state("playing")


## js setState: switch state, end listening and barks, and put the mouse where the state wants it.
func set_state(next: String) -> void:
	if state == next:
		return
	state = next
	if next != "playing":
		end_listen()
		if next != "feeding":
			barks_reset()
	if scenario == null:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if (next == "playing" or next == "feeding" or next == "sleeping" or next == "transition") else Input.MOUSE_MODE_VISIBLE
	if menus != null:
		menus.sync(self)


func show_card(text: String, start_age: float = 0.0, sub: String = "") -> void:
	card_text = text
	card_sub = sub
	card_age = start_age


## Re-seed the far-sound timers for the current night (js initAmbient).
func init_ambient() -> void:
	far_rng = Rng.new(float(mix_seed(run_seed, 77, night_no)))
	dog_t = 20.0 + frng() * 20.0
	bell_t = 20.0 + frng() * 20.0


func frng() -> float:
	return far_rng.next() if far_rng != null else randf()


## The ambience bed follows the room kind; silent on the menus, pause and run end (js updateAmbience).
func update_ambience() -> void:
	var live: bool = run_on and (state == "playing" or state == "feeding" or state == "sleeping" or state == "transition")
	var kind: String = ("outdoor" if room_kind == "outdoor" else "indoor") if live else "none"
	if not live:
		audio.fire_bed(0, 0.0, 0.0)
		audio.fire_bed(1, 0.0, 0.0)
	if kind == amb_key and ambience_gain == amb_lvl:
		return
	var ok := audio.ambience(kind, ambience_gain)
	if ok or kind == "none":
		amb_key = kind
		amb_lvl = ambience_gain


## Steady fire noise: the 2 nearest torches within FIRE_NEAR cells, fading to 0 at that distance, panned to the torch.
func crackle_torches() -> void:
	var live: bool = world != null and not world.lights.is_empty() and run_on and (state == "playing" or state == "feeding")
	var idx := [-1, -1]
	var dist := [INF, INF]
	if live:
		for i in world.lights.size():
			var l: Dictionary = world.lights[i]
			var dx: float = l["x"] - player.x
			var dy: float = l["y"] - player.y
			if absf(dx) > FIRE_NEAR or absf(dy) > FIRE_NEAR:
				continue
			var d: float = sqrt(dx * dx + dy * dy)
			if d >= FIRE_NEAR:
				continue
			if d < dist[0]:
				dist[1] = dist[0]
				idx[1] = idx[0]
				dist[0] = d
				idx[0] = i
			elif d < dist[1]:
				dist[1] = d
				idx[1] = i
	for k in 2:
		if idx[k] < 0:
			audio.fire_bed(k, 0.0, 0.0)
			continue
		var l0: Dictionary = world.lights[idx[k]]
		audio.fire_bed(k, 1.0 - dist[k] / FIRE_NEAR, pan_to(l0["x"], l0["y"]))


## Position of the door that leads toward the crypt from the current map, or null (also null inside the crypt).
func crypt_door_pos() -> Variant:
	if world.doors_by_id.is_empty() or world.spots.get("crypt", []).size() > 0:
		return null
	for id in world.doors_by_id:
		var d: Dictionary = world.doors_by_id[id]
		var tw: World = worlds.get(d["toMap"])
		if tw != null and tw.spots.get("crypt", []).size() > 0:
			return {"x": d["col"] + 0.5, "y": d["row"] + 0.5}
	return null


## Far dogs and the church bell on their timers, and the breath of villagers within 6 cells (js stepAmbient).
func step_ambient(dt: float) -> void:
	dog_t -= dt
	bell_t -= dt
	if dog_t <= 0.0:
		dog_t = 20.0 + frng() * 20.0
		if room_kind == "outdoor":
			var pan := frng() * 2.0 - 1.0
			var dist := 6.0 + frng() * 6.0
			audio.one_shot_far("dog", {"pan": pan, "dist": dist})
	if bell_t <= 0.0:
		bell_t = 20.0 + frng() * 20.0
		var cd: Variant = crypt_door_pos()
		if cd != null:
			audio.play("bell", spatial(cd["x"], cd["y"], minf(1.0, float(SoundData.level("bell")["gain"]) * 2.0)))
	for q in people.people:
		if q.mode == "fed":
			continue
		var dx: float = q.x - player.x
		var dy: float = q.y - player.y
		if dx * dx + dy * dy >= 36.0:
			continue
		if is_nan(q.breath_t):
			q.breath_t = 0.3 + frng() * 2.0
		q.breath_t -= dt
		if q.breath_t > 0.0:
			continue
		q.breath_t = 2.0 + frng()
		audio.breath({"pan": pan_to(q.x, q.y), "dist": sqrt(dx * dx + dy * dy), "behind": cos(atan2(dy, dx) - player.angle) < 0.0, "occluded": first_solid(player.x, player.y, q.x, q.y) != null})


# ---------------------------------------------------------------- listening and barks

func end_listen() -> void:
	if listen_st != null:
		listen_st.stop_cur()
		listen_st.active = false
		listen_st.win = null
		listen_st.count = 0


func barks_reset() -> void:
	if barks_st != null:
		barks_st.reset()
	bark_sub = null


## js stepListen: hold E facing a window from outside to hear the room behind it.
func step_listen(dt: float) -> void:
	if state != "playing" or world == null:
		return
	if listen_st == null:
		listen_st = Listen.new()
	var px: float = player.x if is_nan(lis_px) else lis_px
	var py: float = player.y if is_nan(lis_py) else lis_py
	lis_px = player.x
	lis_py = player.y
	var inst: float = sqrt((player.x - px) * (player.x - px) + (player.y - py) * (player.y - py)) / dt if dt > 0.0 else 0.0
	lis_speed += (inst - lis_speed) * (1.0 - exp(-dt / 0.15))
	listen_st.step({
		"now": clock, "held": key_down(KEY_E), "holding": drink != null or powers.mist != null, "speed": lis_speed,
		"world": world, "player": {"x": player.x, "y": player.y, "angle": player.angle},
		"people": Barks.people_snapshot(people.people), "fear": hunger.fear if hunger != null else 0.0,
		"pan": pan_to, "speak": func(o): return audio.speak(o),
		"speak_length": func(sd, kind, mood_s, voice): return VoiceData.speak_length(sd, kind, mood_s, voice),
		"voice_for": func(who, sd): return VoiceData.for_person(who["id"] if who["id"] is int or who["id"] is float else sd, who["role"]),
		"conversation_for": func(id): return people.conversation_for(int(id))})


## js stepBarks: villager barks while playing or feeding (the grabbed victim's cries).
func step_barks(_dt: float) -> void:
	if (state != "playing" and state != "feeding") or world == null or people == null:
		return
	if barks_st == null:
		barks_st = Barks.new(map_name.length() * 131 + 7 if map_name != "" else 1)
	var on: bool = villager_voices and not (listen_st != null and listen_st.active) and powers.mist == null
	var res := barks_st.step({
		"now": clock, "player": {"x": player.x, "y": player.y}, "people": Barks.people_snapshot(people.people),
		"fear": hunger.fear if hunger != null else 0.0, "enabled": on,
		"restrained": int(drink["id"]) if drink != null and float(drink["rs"]) > 0.5 else null,
		"length_fn": func(sd, kind, mood_s, role, weak): return VoiceData.speak_length(sd, kind, mood_s, role, weak)})
	for b in res["barks"]:
		play_bark(b)


## Plays one bark: distance gain, pan, muffling, subtitle when close and in sight.
func play_bark(b: Dictionary) -> void:
	var occ: Variant = occlusion_to(b["x"], b["y"])
	var d: float = b["dist"]
	if d <= 5.0 and occ == null:
		var cur: Variant = bark_sub
		if cur == null or clock > float(cur["end"]) or d <= float(cur["dist"]):
			var t := Barks.subtitle_for(b)
			if t["de"] != "":
				bark_sub = {"de": t["de"], "en": t["en"], "muffled": false, "speaker": b["id"], "dist": d, "start": clock, "end": clock + maxf(0.5, float(b["len"]))}
	audio.speak({"kind": b["kind"], "seed": b["seed"], "mood": b["mood"], "gain": b["gain"], "pan": pan_to(b["x"], b["y"]), "voice": VoiceData.for_person(b["voiceSeed"], b["role"]), "weak": b["weak"] if b["kind"] == "struggle" else null})


# ---------------------------------------------------------------- sounds

static func num_or_1(v: Variant) -> float:
	return float(v) if (v is float or v is int) and is_finite(float(v)) and float(v) > 0.0 else 1.0


## js emitSound: emit a sound pulse at (x, y); over {range, z, bounces, rangeMul, strengthMul, fadeMul} overrides the level row.
func emit_sound(kind: String, x: float, y: float, over: Dictionary = {}) -> Sonar.Pulse:
	var lv := SoundData.level(kind)
	var room := SoundData.room_profile(world.kind_at(x, y))
	var weak: float = night.weakness() if night != null else 0.0
	var wash: float = night.wash_k() if night != null and world.kind_at(x, y) == "outdoor" else 0.0
	var wm: float = 1.0 - 0.4 * weak
	var base_range: float = float(over["range"]) if (over.get("range") is float or over.get("range") is int) else float(lv.get("range", 0.0) if lv.get("range") != null else 0.0) * wm
	var strength: float = (float(lv["strength"]) if lv.get("strength") != null else 0.0) * wm * num_or_1(over.get("strengthMul"))
	var bounces_v: int = int(over["bounces"]) if (over.get("bounces") is float or over.get("bounces") is int) else int(lv.get("bounces", 0))
	var opts := {
		"kind": kind,
		"range": base_range * float(room["rangeMul"]) * (1.0 - 0.5 * wash) * num_or_1(over.get("rangeMul")),
		"strength": strength,
		"bounces": mini(bounces_v, int(room["bounceCap"])),
		"visRays": 180,
	}
	if over.get("z") is float or over.get("z") is int:
		opts["z"] = over["z"]
	elif lv.get("z") is float or lv.get("z") is int:
		opts["z"] = lv["z"]
	if lv.get("fade") is float or lv.get("fade") is int:
		opts["fade"] = float(lv["fade"]) * float(room["fadeMul"]) * (1.0 - 0.3 * weak) * (1.0 - 0.6 * wash) * num_or_1(over.get("fadeMul"))
	var pu: Sonar.Pulse = sonar.emit_sound(world, x, y, clock, opts)
	if pu != null and weak > 0.0:
		tag_weak(pu, weak, 1.0)
	return pu


## Mark the primary pulse and every pulse pushed after it (its bounce children) as weak; scale their strength by s_mul.
func tag_weak(primary: Sonar.Pulse, weak: float, s_mul: float) -> void:
	var ps: Array = sonar.pulses
	var i: int = ps.find(primary)
	if i < 0:
		i = 0
	while i < ps.size():
		ps[i].weak = weak
		if s_mul != 1.0:
			ps[i].strength *= s_mul
		i += 1


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


## Fear-scaled react config; rebuilt only when dazedTime, fear, still or mist state changes (js reactCfgNow).
func react_cfg_now() -> Dictionary:
	var dz := dazed_time
	var calm: bool = hunger != null and (hunger.is_still() or powers.mist != null)
	var key: float = (hunger.fear if hunger != null else 0.0) * 2.0 + (1.0 if calm else 0.0)
	if react_dz != dz or react_key != key or react_cfg.is_empty():
		react_dz = dz
		react_key = key
		var base: Dictionary = GameData.sounds()["react"]
		fm = hunger.fear_mods() if hunger != null else {"startleMul": 1.0, "fleeMul": 1.0, "calmMul": 1.0}
		var cfg: Dictionary = base.duplicate()
		cfg["dazedTime"] = dz
		cfg["startleDist"] = float(base.get("startleDist", 3.0)) * float(fm["startleMul"])
		cfg["fleeMul"] = float(base.get("fleeMul", 1.6)) * float(fm["fleeMul"])
		cfg["calmAfter"] = float(base.get("calmAfter", 10.0)) * float(fm.get("calmMul", 1.0))
		if calm:
			cfg["bumpDist"] = 0.0
		react_cfg = cfg
	return react_cfg


func react_to(x: float, y: float, kind: String, dist: float = -1.0) -> void:
	if hunger != null and hunger.is_still() and (kind == "ping" or kind == "door"):
		return
	var d: float = dist
	if d < 0.0 and (kind == "ping" or kind == "door"):
		react_cfg_now()
		var base: float = float(GameData.sounds()["react"].get("startleDist", 4.0))
		d = base * flow.fxv("noise") * float(fm["startleMul"]) if flow != null else base
	people.react(x, y, kind, people_ctx(), d if d > 0.0 else 0.0)
	drain_people_events()


func people_ctx() -> Dictionary:
	return {
		"player": {"x": player.x, "y": player.y}, "playerLit": player_lit, "react": react_cfg_now(),
		"grace": grace, "nightFrac": float(night.clock()["frac"]) if night != null else 0.0,
		"nightSec": night.night_sec if night != null else 0.0, "fear": hunger.fear if hunger != null else 0.0,
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


func update_bob(dt: float, moved: float) -> void:
	var walking: bool = dt > 0.0 and moved / dt > 0.3
	bob_amp = clampf(bob_amp + (dt if walking else -dt) * 8.0, 0.0, 1.0)
	if walking:
		walk_phase += (moved / dt) * dt * 7.0
	bob = sin(walk_phase) * 2.5 * bob_amp if bool(cfg.get("headBob", true)) and not reduced else 0.0


func player_steps(dt: float, moved: float) -> void:
	update_bob(dt, moved)
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
	var pkind := player_kind()
	var room := SoundData.room_profile(pkind)
	var outdoor: bool = pkind == "outdoor"
	var keep := [sonar.range_, sonar.bounces, sonar.fade]
	var weak: float = night.weakness() if night != null else 0.0
	var wash: float = night.wash_k() if night != null and outdoor else 0.0
	var fr: float = flow.fxv("sonarRange") if flow != null else 1.0
	var ff: float = flow.fxv("sonarFade") if flow != null else 1.0
	sonar.range_ = base_range * float(room["rangeMul"]) * fr * (1.0 - 0.4 * weak) * (1.0 - 0.5 * wash)
	sonar.bounces = mini(BASE_BOUNCES, int(room["bounceCap"]))
	sonar.fade = base_fade * float(room["fadeMul"]) * ff * (1.0 - 0.3 * weak) * (1.0 - 0.6 * wash)
	var fired: bool = sonar.emit(world, player.x, player.y, clock, {"z": SoundData.level("ping")["z"], "facing": player.angle})
	sonar.range_ = keep[0]
	sonar.bounces = keep[1]
	sonar.fade = keep[2]
	if not fired:
		return false
	tut.pulsed()
	if weak > 0.0 and sonar.last_pulse != null:
		tag_weak(sonar.last_pulse, weak, 1.0 - 0.4 * weak)
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
	update_light_texture()
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
	if night != null:
		if flow.try_sleep():
			return "sleep"
		var sp_list: Array = world.spots.get("crypt", []) + world.spots.get("safe", []).filter(func(sp): return not flow.is_sealed(sp))
		for sp in sp_list:
			if sqrt((sp.x - player.x) * (sp.x - player.x) + (sp.y - player.y) * (sp.y - player.y)) <= reach:
				emit_sound("interact", sp.x, sp.y)
				audio.play("interact", spatial(sp.x, sp.y, float(SoundData.level("interact")["gain"])))
				return "interact"
	return "none"


# ---------------------------------------------------------------- world simulation

func simulate_world(dt: float) -> void:
	var t_prev: float = clock - dt
	people.update(world, dt, people_ctx())
	if flow != null:
		flow.step_forge(dt)
	drain_people_events()
	people_sounds(t_prev)
	var made := people.update_echoes(sonar, t_prev, clock)
	if not made.is_empty():
		tut.queue("person")
	for e in made:
		# floor rings under the person: a heartbeat is a small ring, a footstep a modest one, a ping the full size
		var small: float = 0.4 if e.kind == "vheart" else (0.45 if e.kind == "personStep" or e.kind == "step" else 1.0)
		ripple.spawn(e.x, e.y, clock, {"kind": "person", "maxR": 1.6 * small, "life": 0.9 * (0.7 if small < 1.0 else 1.0), "strength": e.strength})
		if small == 1.0:
			ripple.spawn(e.x, e.y, clock, {"kind": "person", "maxR": 1.2, "life": 0.8, "strength": e.strength * 0.6, "delay": 0.18})
		e.pan = clampf(sin(atan2(e.y - player.y, e.x - player.x) - player.angle), -1.0, 1.0)
		audio.person_echo(e, sonar)
	marker_ripples(t_prev, clock)
	ripple.prune(clock)


## Spawn one small ring on each crypt/safe/door spot a wavefront crossed this frame (js markerRipples).
func marker_ripples(t_prev: float, t: float) -> void:
	for pu in sonar.pulses:
		for kind in ["crypt", "safe", "doors"]:
			for sp in world.spots.get(kind, []):
				var la: float = Sonar.lit_at(pu, sp.x, sp.y)
				if not (la > t_prev and la <= t):
					continue
				if (la - pu.t0) * pu.speed > pu.range:
					continue
				if not Sonar.visible_from(pu, sp.x, sp.y):
					continue
				ripple.spawn(sp.x, sp.y, la, {"kind": "marker", "maxR": 0.8, "life": 0.6, "strength": 0.7})


func people_sounds(_t_prev: float) -> void:
	var lv := SoundData.level("personStep")
	for e in people.step_events():
		var mat := step_material(e["x"], e["y"])
		var sc := SoundData.step_scale(e["gait"], mat, e["pace"])
		var guard_step: bool = e["gait"] == "mail"
		var side: float = (1.0 if e["foot"] != 0 else -1.0) * 0.12
		var fx: float = e["x"] - sin(e["angle"]) * side
		var fy: float = e["y"] + cos(e["angle"]) * side
		var spu := emit_sound("personStep", fx, fy, {"rangeMul": sc["range"], "strengthMul": sc["strength"], "fadeMul": sc["fade"]})
		if spu != null:
			spu.hd = e["angle"]
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
	var target := people.feed_target(player.x, player.y, player.angle, feed_reach, feed_arc)
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
	last_victim = {"id": target.id, "people": people}
	if hunger != null:
		hunger.on_grab("%s:%d" % [map_name, target.id])
	over_acc = 0.0
	set_state("feeding")
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
	if not d["forced"] and float(d["t"]) > dt * 1.5 and not feed_held() and not feed_toggle:
		end_drink("released")
		return
	if sqrt((p.x - player.x) * (p.x - player.x) + (p.y - player.y) * (p.y - player.y)) > feed_reach + 0.3:
		end_drink("reach")
		return
	var want_rs: float = 1.0 if key_down(KEY_E) else 0.0
	d["rs"] = float(d["rs"]) + (want_rs - float(d["rs"])) * (1.0 - exp(-dt / 0.12))
	if float(d["t"]) >= float(d["struggleAt"]) and struggle(d):
		return
	var ov_open: bool = hunger != null and hunger.is_open()
	var blood_cap: float = night.blood_max if night != null else BLOOD_MAX
	if blood >= blood_cap and not ov_open:
		end_drink("cap")
		return
	var drink_fx: float = flow.fxv("drinkRate") if flow != null else 1.0
	var rate: float = (2.5 + 4.5 * clampf(float(d["left"]) / float(d["pool"]), 0.0, 1.0)) * drink_fx * DRINK_BOOST * (1.0 - (1.0 - RESTRAIN_DRINK) * float(d["rs"]))
	var gain := 0.0
	var over := 0.0
	var ready := false
	if night != null:
		gain = night.add_blood(rate * dt)
		if ov_open and night.blood >= night.blood_max and rate * dt - gain > 1e-9:
			var r: Dictionary = hunger.add_overflow(rate * dt - gain)
			over = float(r["taken"])
			ready = r["ready"]
	else:
		gain = minf(BLOOD_MAX, blood_free + rate * dt) - blood_free
		blood_free += gain
	if over > 0.0:
		over_acc += over
		while over_acc >= 10.0:
			over_acc -= 10.0
			audio.play("overflow", {"gain": SoundData.level("overflow")["gain"], "pan": 0.0})
	gain += over
	d["drunk"] = float(d["drunk"]) + gain
	var left: float = people.drink(int(d["id"]), gain)
	d["left"] = left if left >= 0.0 else 0.0
	if ready:
		end_drink("gift")
		flow.enter_gift()
		return
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
	if blood >= blood_cap and not (hunger != null and hunger.is_open()):
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
	ripple.spawn(v.x, v.y, clock, {"kind": "person", "maxR": 0.9 + 0.6 * k, "life": 0.45, "strength": 0.7})
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
	var weak: float = night.weakness() if night != null else 0.0
	var r: float = (1.5 + 2.5 * clampf(float(d["drunk"]) / float(d["pool"]), 0.0, 1.0)) * (1.0 - 0.4 * weak)
	emit_sound("heartbeat", v.x, v.y, {"range": r, "z": 0.55, "bounces": 0})
	react_to(v.x, v.y, "heartbeat", r)
	audio.play("heartbeat", spatial(v.x, v.y, float(SoundData.level("heartbeat")["gain"]) * (0.6 + 0.4 * clampf(float(d["left"]) / float(d["pool"]), 0.0, 1.0))))
	if landings.size() < 8:
		landings.append(clock + 0.4)
	ripple.spawn(v.x, v.y, clock, {"kind": "person", "maxR": 1.0, "life": 0.5, "strength": 0.9})
	if reduced:
		ripple.spawn(v.x, v.y, clock, {"kind": "person", "maxR": 0.8, "minR": 0.8, "inward": true, "life": 0.4, "strength": 0.6})
	else:
		ripple.spawn(player.x, player.y, clock, {"kind": "person", "maxR": 1.4, "minR": 0.15, "inward": true, "life": 0.4, "strength": 0.8})
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
		if night != null:
			night.fed_count += 1
	else:
		people.release(int(d["id"]), player.x, player.y)
	if state == "feeding":
		set_state("playing")


# ---------------------------------------------------------------- render

func lock_info() -> Dictionary:
	if drink == null:
		return {}
	var d: Dictionary = drink
	return {"id": d["id"], "k": 1.0 - clampf(float(d["left"]) / float(d["pool"]), 0.0, 1.0), "age": float(d["t"]), "sp": 9.0, "rs": float(d["rs"])}


func _render() -> void:
	last_render_clock = clock
	_sync_camera()
	textures.sync_from(sonar, world)
	textures.sync_rings(ripple.rings, clock)
	ceil_mat.set_shader_parameter("player_indoor", player_kind() != "outdoor")
	for m in [wall_mat, floor_mat, ceil_mat]:
		textures.apply_to(m)
		m.set_shader_parameter("game_time", clock)
	wall_mat.set_shader_parameter("boil_frame", int(floor(clock * 10.0)) % 4)
	echo_view.rs_fov = fov_now()
	echo_view.render_frame(world, player, people, sonar, clock, lock_info(), ripple.rings)
	hud_view.render_frame(self)
	_sync_postfx()
	wall_mat.set_shader_parameter("focal_px", 320.0 / tan(fov_now() / 2.0))


## Push the settings into the running game (js applyConfig): volume, sonar, feeding, motion, text and effects.
func apply_config() -> void:
	audio.volume = float(cfg["volume"])
	flow.night_length_min = float(cfg["nightLengthMin"])
	flow.autosave_sec = float(cfg["autosaveSec"])
	reduced = cfg["reduceMotion"] == true
	player_cfg = {"mouseSensitivity": cfg["mouseSensitivity"], "invertMouse": cfg["invertMouse"], "moveSpeed": cfg["moveSpeed"], "turnSpeedKeys": cfg["turnSpeedKeys"], "keyTurnSpeed": cfg["keyTurnSpeed"]}
	base_range = float(cfg["sonarRange"])
	base_fade = float(cfg["sonarFade"])
	sonar.speed = float(cfg["sonarSpeed"])
	sonar.cooldown = float(cfg["sonarCooldown"]) * (flow.fxv("sonarCooldown") if flow.run != null else 1.0)
	feed_reach = float(cfg["feedReach"])
	feed_arc = deg_to_rad(float(cfg["feedArcDeg"]))
	pool_min = float(cfg["poolMin"])
	pool_max = maxf(float(cfg["poolMax"]), pool_min)
	dazed_time = float(cfg["dazedTime"])
	feed_toggle = cfg["feedToggle"] == true
	show_subtitles = cfg["subtitles"] == true
	show_translation = cfg["translation"] == true
	villager_voices = cfg["villagerVoices"] == true
	large_text = cfg["largeText"] == true
	fov_base_deg = float(cfg["fovDeg"])
	ambience_gain = float(cfg["ambienceGain"])
	react_key = -1.0
	echo_view.apply_config(cfg, reduced)


## Change one setting, save the file and apply it.
func set_config(key: String, value: Variant) -> void:
	cfg[key] = value
	if test_storage == null:
		Config.save_file(cfg)
	apply_config()


## Per-frame feed effects: the FOV narrows while holding a victim, the vial pulses and gulps land (js stepFeedFx).
func step_feed_fx(dt: float) -> void:
	var up: float = 1.0 / 0.35 if drink != null else -1.0 / 0.4
	fov_k = clampf(fov_k + up * dt, 0.0, 1.0)
	if vial_pulse > 0.0:
		vial_pulse = maxf(0.0, vial_pulse - dt / 0.15)
	while landings.size() > 0 and landings[0] <= clock:
		landings.pop_front()
		vial_pulse = 1.0
		audio.play("gulp", {"gain": SoundData.level("gulp")["gain"], "pan": 0.0})


## Post effects from the effects level (js PostFx): bloom and the dusk/dawn grade at level >= 1, the grain and vignette levels.
func _sync_postfx() -> void:
	var fx: int = echo_view.rs.fx
	var menu: bool = state == "title" or state == "error"
	var bloom: float = 0.55 if fx >= 2 and not menu else 0.0
	var dusk := 0.0
	var dawn := 0.0
	if night != null and fx >= 1:
		dusk = 1.0 - night.min / 30.0 if night.min < 30.0 else 0.0
		dawn = night.dawn_k()
	fx_grade_mat.set_shader_parameter("bloom_alpha", bloom)
	fx_grade_mat.set_shader_parameter("dusk", dusk)
	fx_grade_mat.set_shader_parameter("dawn", dawn)
	var grain: float = [0.04, 0.035, 0.05][clampi(fx, 0, 2)]
	var vig: float = 1.0 if fx == 0 else (0.7 if fx == 1 else 1.0)
	var vignette_on: bool = cfg["edgeVignette"] == true and not menu
	fx_overlay_mat.set_shader_parameter("vig_opacity", vig if vignette_on else 0.0)
	fx_overlay_mat.set_shader_parameter("grain_opacity", 0.0 if menu else grain)
	fx_overlay_mat.set_shader_parameter("grain_time", clock)


func fov_ease() -> float:
	return fov_k * fov_k * (3.0 - 2.0 * fov_k)


## Current horizontal field of view in radians (the base 66 degrees, narrowed while feeding unless reduced motion).
func fov_now() -> float:
	var base: float = deg_to_rad(fov_base_deg)
	if reduced or fov_k <= 0.0:
		return base
	return base * (1.0 - (1.0 - GRAB_FOV) * fov_ease())


## Black overlay amount: the menus' dim and the sleep fade (js seqFade and the run end, boon and gift fades).
func fade_amount() -> float:
	match state:
		"runend": return 0.78
		"boon": return 0.97
		"gift": return 0.9
	var q: Variant = flow.seq if flow != null else null
	if q != null:
		var t: float = q["t"]
		return t / 0.8 if t < 0.8 else (1.0 if t < 1.4 else clampf(1.0 - (t - 1.4) / 0.8, 0.0, 1.0))
	return 0.0


func _sync_camera() -> void:
	cam.fov = rad_to_deg(fov_now())
	cam.position = Coords.to_view(player.x, player.y, 0.5)
	# A horizon shift of bob px (of 360) is a small pitch: positive bob moves the horizon down, i.e. looks up.
	var focal: float = 320.0 / tan(fov_now() * 0.5)
	cam.rotation = Vector3(atan(bob / focal), -player.angle - PI / 2.0, 0.0)
	echo_view.rs.horizon = echo_view.rs.oh / 2.0 + bob * (echo_view.rs.oh / 360.0)
