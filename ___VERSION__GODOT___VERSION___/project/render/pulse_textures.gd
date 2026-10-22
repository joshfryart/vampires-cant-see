class_name PulseTextures
extends RefCounted
## Uploads Sonar pulses to the textures read by the sonar shaders.
##   pulse_tex: MAX_PULSES x 3, RGBAF.  row 0 = (x, y, z, t0); row 1 = (range, speed, fade, strength);
##              row 2 = (ray count n, has beam 0/1, 0, 0).
##   vis_tex:   MAX_RAYS x MAX_PULSES, RGF. per ray (vis distance, beam factor; 1 when the pulse has no beam).
## Rows are rewritten only when the pulse list changes (a ping, bounce children, prune), never per frame.

const MAX_PULSES := 64
const MAX_RAYS := 720

var pulse_tex: ImageTexture
var vis_tex: ImageTexture
var count: int = 0

var _pulse_img: Image
var _vis_img: Image
var _uploaded: Array[Sonar.Pulse] = []


func _init() -> void:
	_pulse_img = Image.create(MAX_PULSES, 3, false, Image.FORMAT_RGBAF)
	_vis_img = Image.create(MAX_RAYS, MAX_PULSES, false, Image.FORMAT_RGF)
	pulse_tex = ImageTexture.create_from_image(_pulse_img)
	vis_tex = ImageTexture.create_from_image(_vis_img)


func _same(pulses: Array[Sonar.Pulse]) -> bool:
	if pulses.size() != _uploaded.size():
		return false
	for i in pulses.size():
		if pulses[i] != _uploaded[i]:
			return false
	return true


## Call once per frame; cheap when the list is unchanged. Returns the pulse count.
func sync_from(sonar: Sonar) -> int:
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
		_pulse_img.set_pixel(i, 2, Color(n, 1.0 if has_beam else 0.0, 0.0, 0.0))
		for j in n:
			_vis_img.set_pixel(j, i, Color(p.vis[j], p.vbeam[j] if has_beam else 1.0, 0.0, 0.0))
	pulse_tex.update(_pulse_img)
	vis_tex.update(_vis_img)
	return count


func apply_to(mat: ShaderMaterial) -> void:
	mat.set_shader_parameter("pulse_tex", pulse_tex)
	mat.set_shader_parameter("vis_tex", vis_tex)
	mat.set_shader_parameter("pulse_count", count)
