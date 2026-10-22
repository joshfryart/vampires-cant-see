class_name PulseTextures
extends RefCounted
## Uploads Sonar pulses (and the secondary echo rings) to the textures read by the sonar shaders.
##   pulse_tex: MAX_PULSES x 5, RGBAF.  row 0 = (x, y, z, t0); row 1 = (range, speed, fade, strength);
##              row 2 = (ray count n, has beam 0/1, kind code, gen);
##              row 3 = (facing, weak, hd (1e9 when none), 0);
##              row 4 = (mean roughness, floor material code 0 other / 1 grass / 2 wood, 0, 0).
##   vis_tex:   MAX_RAYS x MAX_PULSES, RGF. per ray (vis distance, beam factor; 1 when the pulse has no beam).
##   ring_tex:  MAX_RINGS x 2, RGBAF. row 0 = (x, y, radius, alpha); row 1 = (kind code 0 person / 1 marker / 2 other, index, 0, 0).
## Pulse rows are rewritten only when the pulse list changes (a ping, bounce children, prune), never per frame.
## Kind codes: 0 ping or other sound, 1 step, 2 personStep, 3 vheart.

const MAX_PULSES := 64
const MAX_RAYS := 720
const MAX_RINGS := 16
const ROWS := 5

var pulse_tex: ImageTexture
var vis_tex: ImageTexture
var ring_tex: ImageTexture
var count: int = 0
var ring_count: int = 0

var _pulse_img: Image
var _vis_img: Image
var _ring_img: Image
var _uploaded: Array[Sonar.Pulse] = []


func _init() -> void:
	_pulse_img = Image.create(MAX_PULSES, ROWS, false, Image.FORMAT_RGBAF)
	_vis_img = Image.create(MAX_RAYS, MAX_PULSES, false, Image.FORMAT_RGF)
	_ring_img = Image.create(MAX_RINGS, 2, false, Image.FORMAT_RGBAF)
	pulse_tex = ImageTexture.create_from_image(_pulse_img)
	vis_tex = ImageTexture.create_from_image(_vis_img)
	ring_tex = ImageTexture.create_from_image(_ring_img)


func _same(pulses: Array[Sonar.Pulse]) -> bool:
	if pulses.size() != _uploaded.size():
		return false
	for i in pulses.size():
		if pulses[i] != _uploaded[i]:
			return false
	return true


static func kind_code(kind: String) -> int:
	match kind:
		"step": return 1
		"personStep": return 2
		"vheart": return 3
	return 0


## Call once per frame; cheap when the list is unchanged. world gives the floor under each pulse (roughness, grass/wood
## stipple). Returns the pulse count.
func sync_from(sonar: Sonar, world: World = null) -> int:
	var pulses: Array[Sonar.Pulse] = sonar.pulses
	if _same(pulses):
		return count
	_uploaded = pulses.duplicate()
	count = mini(pulses.size(), MAX_PULSES)
	_pulse_img.fill(Color(0, 0, 0, 0))
	_vis_img.fill(Color(0, 0, 0, 0))
	for i in count:
		var p: Sonar.Pulse = pulses[i]
		var n: int = mini(p.vis.size(), MAX_RAYS)
		var has_beam: bool = p.vbeam.size() > 0
		_pulse_img.set_pixel(i, 0, Color(p.x, p.y, p.z, p.t0))
		_pulse_img.set_pixel(i, 1, Color(p.range, p.speed, p.fade, p.strength))
		_pulse_img.set_pixel(i, 2, Color(n, 1.0 if has_beam else 0.0, kind_code(p.kind), p.gen))
		_pulse_img.set_pixel(i, 3, Color(p.facing if p.has_facing else 0.0, p.weak, 1e9 if is_nan(p.hd) else p.hd, 0.0))
		var rough: float = FloorFx.pulse_rough(world, p) if world != null else 0.2
		var fm := 0
		if world != null:
			var mat := world.material_at(p.x, p.y)
			fm = 1 if mat == "grass" else (2 if mat == "wood" else 0)
		_pulse_img.set_pixel(i, 4, Color(rough, fm, 0.0, 0.0))
		for j in n:
			_vis_img.set_pixel(j, i, Color(p.vis[j], p.vbeam[j] if has_beam else 1.0, 0.0, 0.0))
	pulse_tex.update(_pulse_img)
	vis_tex.update(_vis_img)
	return count


## Per-frame upload of the live secondary rings (radius and alpha at time t).
func sync_rings(rings: Array, t: float) -> int:
	_ring_img.fill(Color(0, 0, 0, 0))
	var n := 0
	for k in rings.size():
		if n >= MAX_RINGS:
			break
		var rg: Dictionary = rings[k]
		var a: float = RippleFx.Rings.alpha(rg, t)
		if a <= 0.01:
			continue
		var kc := 0 if rg["kind"] == "person" else (1 if rg["kind"] == "marker" else 2)
		_ring_img.set_pixel(n, 0, Color(rg["x"], rg["y"], RippleFx.Rings.radius(rg, t), a))
		_ring_img.set_pixel(n, 1, Color(kc, k, 0.0, 0.0))
		n += 1
	ring_count = n
	if n > 0 or _ring_dirty:
		ring_tex.update(_ring_img)
	_ring_dirty = n > 0
	return n


var _ring_dirty := false


func apply_to(mat: ShaderMaterial) -> void:
	mat.set_shader_parameter("pulse_tex", pulse_tex)
	mat.set_shader_parameter("vis_tex", vis_tex)
	mat.set_shader_parameter("pulse_count", count)
	mat.set_shader_parameter("ring_tex", ring_tex)
	mat.set_shader_parameter("ring_count", ring_count)
