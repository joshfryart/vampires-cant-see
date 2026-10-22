extends Node3D
## Integrator for the Phase 1 vertical slice. Builds the view (640x360 SubViewport scaled to the window),
## owns the logic objects (World, Player, Sonar) and advances them in the JS order: input -> player -> sonar -> render.
## Run a scripted shot with:  -- --scenario=NAME   (see tests/scenarios/)

const VIEW_W := 640
const VIEW_H := 360
const FOV_DEG := 66.0
const MAX_DIST := 16.0
const PING_FACING_Z := 0.5

var world: World
var player: Player
var sonar: Sonar
var clock: float = 0.0
var textures: PulseTextures
var wall_mat: ShaderMaterial
var floor_mat: ShaderMaterial
var cam: Camera3D
var viewport: SubViewport
var scenario: Object = null
var mouse_dx: float = 0.0
var frame_no: int = 0
var map_name: String = "test"


func _ready() -> void:
	var scenario_name := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--scenario="):
			scenario_name = a.substr(11)
		elif a.begins_with("--map="):
			map_name = a.substr(6)
	_build_view()
	load_map(map_name)
	if scenario_name != "":
		var script: GDScript = load("res://tests/scenarios/%s.gd" % scenario_name)
		scenario = script.new()
		scenario.setup(self)
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _build_view() -> void:
	var container := SubViewportContainer.new()
	container.stretch = true
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
	textures = PulseTextures.new()
	wall_mat = ShaderMaterial.new()
	wall_mat.shader = load("res://render/shaders/sonar_wall.gdshader")
	floor_mat = ShaderMaterial.new()
	floor_mat.shader = load("res://render/shaders/sonar_floor.gdshader")


func load_map(name: String) -> void:
	map_name = name
	world = World.from_def(GameData.map_def(name))
	player = Player.create(world.start.x, world.start.y, 0.0)
	sonar = Sonar.create()
	clock = 0.0
	for child in viewport.get_children():
		if child.has_meta("map_mesh"):
			child.queue_free()
	var walls := MeshInstance3D.new()
	walls.mesh = WorldMeshBuilder.build(world)
	walls.material_override = wall_mat
	walls.set_meta("map_mesh", true)
	viewport.add_child(walls)
	var floor_inst := MeshInstance3D.new()
	floor_inst.mesh = WorldMeshBuilder.build_floor(world)
	floor_inst.material_override = floor_mat
	floor_inst.set_meta("map_mesh", true)
	viewport.add_child(floor_inst)
	_sync_camera()


func ping() -> bool:
	return sonar.emit(world, player.x, player.y, clock, {"facing": player.angle, "z": PING_FACING_Z})


func _unhandled_input(event: InputEvent) -> void:
	if scenario != null:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		mouse_dx += event.relative.x
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		else:
			ping()
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_SPACE:
			ping()
		elif event.physical_keycode == KEY_ESCAPE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


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


func _process(delta: float) -> void:
	frame_no += 1
	var inp := {}
	if scenario != null:
		scenario.step(self, delta)
	else:
		inp = _read_input()
	clock += delta
	player.update(world, inp, delta)
	sonar.prune(clock)
	_sync_camera()
	textures.sync_from(sonar)
	for m in [wall_mat, floor_mat]:
		textures.apply_to(m)
		m.set_shader_parameter("game_time", clock)
	wall_mat.set_shader_parameter("boil_frame", int(floor(clock * 10.0)) % 4)


func _sync_camera() -> void:
	cam.position = Coords.to_view(player.x, player.y, 0.5)
	cam.rotation = Vector3(0.0, -player.angle - PI / 2.0, 0.0)
