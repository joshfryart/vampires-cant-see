class_name AudioDirector
extends Node
## Audio entry points the game calls (js VCS.Audio), played from baked samples (tools/bake-audio.mjs).
## Mixer: each voice slot Vn has its own bus (panner + low-pass) feeding a shared "World" bus (reverb) -> Master
## (compressor, as the JS master chain). Gains follow the JS "peak parameter" P: linear = P / (ref * scale) from the manifest.
## Delayed sounds (echoes) are queued and started on the first frame at or after their game-clock time (~16 ms quantised).
## `log` records every call (tests, scenarios); `muted` skips playback but keeps the log.

const VOICES := 24
const MAX_LOG := 512
const DEFAULT_VOLUME := 0.7
const MAX_ECHO_DELAY := 6.0
const ROOM_GAIN := {"indoor": 1.0, "outdoor": 0.7}

var log: Array = []
var muted: bool = false
var volume: float = DEFAULT_VOLUME
var room_kind: String = "indoor"
## The old cartoon bip ping (setting pingBip): no material voices, no floor, ceiling or prop echoes (js setPingStyle).
var ping_bip: bool = false
var t60: float = 1.0
var wet: float = 1.0

var _manifest: Dictionary = {}
var _streams: Dictionary = {}
var _pool: Array = []          # [{player, bus, pan_fx, lp_fx}]
var _next_slot: int = 0
var _pending: Array = []       # [{due, run: Callable}]
var _now: float = 0.0
var _reverb: AudioEffectReverb
var _rng := RandomNumberGenerator.new()
var _foot_toggle: bool = false

# ---- beds: ambience loops, fire noise, speech ----
const AMB_FADE := 1.5
const MAX_SPEAKERS := 4
var _amb: Dictionary = {}                 # kind -> {player, cur, tgt}
var _amb_kind: String = "none"
var _amb_level: float = 1.0
var _fire: Array = []                     # [{player, pan, cur, tgt, ref_scale}]
var _last_tick: float = 0.0
var _speakers: Array = []                 # [{player, handle, end}]
var _speech_cache: Dictionary = {}


func _ready() -> void:
	_rng.seed = 7
	_load_manifest()
	_build_buses()


func _load_manifest() -> void:
	var f := FileAccess.open("res://audio/manifest.json", FileAccess.READ)
	if f != null:
		_manifest = JSON.parse_string(f.get_as_text())


func _bus_index(bus_name: String) -> int:
	return AudioServer.get_bus_index(bus_name)


func _build_buses() -> void:
	if _bus_index("World") < 0:
		var m_idx := _bus_index("Master")
		var comp := AudioEffectCompressor.new()
		comp.threshold = -18.0
		comp.ratio = 4.0
		comp.attack_us = 3000.0
		comp.release_ms = 250.0
		AudioServer.add_bus_effect(m_idx, comp)
		AudioServer.add_bus()
		var w_idx := AudioServer.bus_count - 1
		AudioServer.set_bus_name(w_idx, "World")
		AudioServer.set_bus_send(w_idx, "Master")
		_reverb = AudioEffectReverb.new()
		_reverb.wet = 0.15
		_reverb.dry = 1.0
		_reverb.damping = 0.5
		_reverb.room_size = 0.5
		AudioServer.add_bus_effect(w_idx, _reverb)
		for i in VOICES:
			AudioServer.add_bus()
			var idx := AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, "V%d" % i)
			AudioServer.set_bus_send(idx, "World")
			AudioServer.add_bus_effect(idx, AudioEffectPanner.new())
			var lp := AudioEffectLowPassFilter.new()
			lp.cutoff_hz = 20500.0
			AudioServer.add_bus_effect(idx, lp)
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.bus_count - 1, "Beds")
		AudioServer.set_bus_send(AudioServer.bus_count - 1, "Master")
		for k in 2:
			AudioServer.add_bus()
			var fi := AudioServer.bus_count - 1
			AudioServer.set_bus_name(fi, "Fire%d" % k)
			AudioServer.set_bus_send(fi, "Master")
			AudioServer.add_bus_effect(fi, AudioEffectPanner.new())
	else:
		var wi := _bus_index("World")
		_reverb = AudioServer.get_bus_effect(wi, 0)
	_build_beds()
	for i in VOICES:
		var bidx := _bus_index("V%d" % i)
		var player := AudioStreamPlayer.new()
		player.bus = "V%d" % i
		add_child(player)
		_pool.append({"player": player, "pan": AudioServer.get_bus_effect(bidx, 0), "lp": AudioServer.get_bus_effect(bidx, 1)})


func _record(kind: String, opts: Dictionary) -> void:
	log.append({"kind": kind, "opts": opts})
	if log.size() > MAX_LOG:
		log.pop_front()


func _stream(file: String) -> AudioStream:
	if not _streams.has(file):
		_streams[file] = load("res://audio/wav/%s" % file)
	return _streams[file]


func _variants(key: String) -> Array:
	var e: Dictionary = _manifest.get("entries", {})
	return e[key] if e.has(key) else []


## Start a baked sample on the next voice slot with linear gain, pan -1..1 and low-pass (0 = none).
func _start(entry: Dictionary, linear: float, pan: float, lp_hz: float) -> void:
	if muted or _pool.is_empty() or linear <= 0.0:
		return
	var slot: Dictionary = _pool[_next_slot]
	for k in VOICES:
		var cand: Dictionary = _pool[(_next_slot + k) % VOICES]
		if not cand["player"].playing:
			slot = cand
			_next_slot = (_next_slot + k + 1) % VOICES
			break
	var player: AudioStreamPlayer = slot["player"]
	(slot["pan"] as AudioEffectPanner).pan = clampf(pan, -1.0, 1.0)
	(slot["lp"] as AudioEffectLowPassFilter).cutoff_hz = lp_hz if lp_hz > 0.0 else 20500.0
	player.stream = _stream(entry["file"])
	player.volume_db = linear_to_db(maxf(linear, 1e-6))
	player.play()


func _pick(variants: Array, material: Variant = null, foot: Variant = null) -> Dictionary:
	var pool: Array = []
	for v in variants:
		if material != null and v.get("material") != null and v["material"] != material:
			continue
		if foot != null and v.get("foot") != null and int(v["foot"]) != int(foot):
			continue
		pool.append(v)
	if pool.is_empty():
		pool = variants
	if pool.is_empty():
		return {}
	return pool[_rng.randi() % pool.size()]


func _schedule(delay: float, fn: Callable) -> void:
	if delay <= 0.0:
		fn.call()
	else:
		_pending.append({"due": _now + delay, "run": fn})


## Advance the audio clock (game clock seconds); starts queued sounds that are due and moves the bed levels.
func tick(now: float) -> void:
	var dt: float = clampf(now - _last_tick, 0.0, 0.25) if _last_tick > 0.0 else 0.0
	_last_tick = now
	_step_beds(dt)
	_now = now
	var keep: Array = []
	for p in _pending:
		if p["due"] <= now:
			p["run"].call()
		else:
			keep.append(p)
	_pending = keep


## Reverb send multiplier for the last ping (js setWet): 0..2.
func set_wet(w: float) -> void:
	wet = clampf(w, 0.0, 2.0) if is_finite(w) else 1.0
	if _reverb != null:
		_reverb.wet = clampf(0.15 * wet * 1.5, 0.0, 0.6)


## Room kind and Sabine T60 for the current zone (js setRoom).
func set_room(kind: String, t60_s: float) -> void:
	room_kind = kind
	t60 = t60_s
	wet = 1.0
	if _reverb != null:
		_reverb.room_size = clampf(t60_s / 2.5, 0.15, 0.95)
		_reverb.wet = 0.15 * 1.5


## js Audio.play(kind, opts). opts: gain, pan, delay, dist, occluded, occ {mat, diff}, behind, material, foot.
func play(kind: String, opts: Dictionary = {}) -> bool:
	_record(kind, opts)
	var lv_kind: String = "door" if kind == "doorOpen" or kind == "doorClose" else kind
	var lv := SoundData.level(lv_kind)
	var gain: float = float(opts["gain"]) if opts.get("gain") is float or opts.get("gain") is int else float(lv.get("gain", 0.1) if lv.get("gain") != null else 0.1)
	gain = clampf(gain, 0.0, 1.0)
	if gain <= 0.0:
		return false
	var delay: float = float(opts.get("delay", 0.0))
	if not (delay >= 0.0 and delay <= MAX_ECHO_DELAY):
		return false
	var lp_hz := 0.0
	if opts.get("dist") is float or opts.get("dist") is int:
		var dist := float(opts["dist"])
		if dist >= 0.0:
			if lv.get("hearDist") != null and dist > float(lv["hearDist"]):
				return false
			gain *= 1.0 / (1.0 + dist / 4.0)
	if opts.get("behind", false):
		gain *= 0.7
		lp_hz = 1200.0
	var occ: Variant = opts.get("occ")
	if occ is Dictionary and occ.get("mat") is String:
		var fx := Acoustics.occlusion(occ["mat"], float(occ["diff"]) if occ.get("diff") != null else NAN)
		gain *= float(fx["gain"])
		lp_hz = minf(lp_hz, float(fx["lpHz"])) if lp_hz > 0.0 else float(fx["lpHz"])
	elif opts.get("occluded", false):
		lp_hz = 600.0
	var mat: String = opts["material"] if opts.get("material") is String and ["grass", "wood", "stone"].has(opts["material"]) else "stone"
	var foot_v: Variant = opts.get("foot")
	var footed: bool = kind == "step" or kind == "personStep" or kind == "guardStep"
	var foot: int = (1 if foot_v else 0) if foot_v != null else (1 if _foot_toggle else 0)
	if footed:
		_foot_toggle = not _foot_toggle
	var entry := _pick(_variants("play:%s" % kind), mat if footed else null, foot if footed else null)
	if entry.is_empty():
		return false
	var linear: float = volume * gain / (float(entry["ref"]) * float(entry["scale"]))
	var pan: float = float(opts.get("pan", 0.0))
	_schedule(delay, func(): _start(entry, linear, pan, lp_hz))
	return true


## js Audio.ping: the 8 ms click (baked dry; the reverb bus supplies the room).
func click() -> void:
	var entry := _pick(_variants("ping:bip" if ping_bip else "ping:ping"))
	if entry.is_empty():
		return
	_start(entry, volume / float(entry["scale"]), 0.0, 0.0)


## js Audio.echo(delay, strength, pan, {voice, rough}).
func echo(delay: float, strength: float, pan: float, opts: Dictionary = {}) -> void:
	_record("echo", {"delay": delay, "amp": strength, "pan": pan, "voice": opts.get("voice", ""), "rough": opts.get("rough", 0.0)})
	if not (delay >= 0.0 and delay <= MAX_ECHO_DELAY) or not is_finite(strength):
		return
	var s: float = clampf(strength * float(ROOM_GAIN.get(room_kind, 1.0)), 0.0, 1.0)
	if s <= 0.0 or strength <= 0.0:
		return
	var voice: String = opts["voice"] if (opts.get("voice") is String and opts["voice"] != "" and not ping_bip) else "plain"
	var rough: float = float(opts.get("rough", 0.0))
	var variants := _variants("echo:%s" % voice)
	var want_room: String = "outdoor" if room_kind == "outdoor" else "indoor"
	var want_rough: float = 0.0 if rough <= 0.25 else (0.45 if rough <= 0.55 else 0.7)
	var entry: Dictionary = {}
	for v in variants:
		if v["room"] == want_room and absf(float(v["rough"]) - want_rough) < 0.01:
			entry = v
	if entry.is_empty():
		return
	var linear: float = volume * s / float(entry["scale"])
	_schedule(delay, func(): _start(entry, linear, pan, 0.0))


# ---------------------------------------------------------------- ping audio (js pulse() audio section)

func _clamp(v: float, lo: float, hi: float) -> float:
	return lo if v < lo else (hi if v > hi else v)


## The click ping and every echo it returns: wall, floor, ceiling, props, bounce children (js pulse()).
func ping(lp: Sonar.Pulse, player: Player, world: World, game: Node) -> void:
	_record("ping", {"gen": lp.gen if lp != null else 0})
	if lp == null:
		return
	var indoor: bool = world.kind_at(player.x, player.y) != "outdoor"
	_ping_enclosure(lp, indoor, player, world, game)
	click()
	_ping_echo(lp, player, game)
	_floor_bounce(player, world, game)
	_ceiling_bounce(indoor, game.room_zone)
	_prop_echoes(lp, player, world, game)
	_bounce_echoes(player, game)


func _echo_pan(lp: Sonar.Pulse, player: Player) -> float:
	var n: int = lp.vis.size()
	if n == 0:
		return 0.0
	var lim: float = PI / 3.0
	var ss := 0.0
	var sc := 0.0
	for i in n:
		var d: float = lp.vis[i]
		if not (d > 0.0) or is_inf(d):
			continue
		var a: float = (float(i) / n) * TAU - player.angle
		var rel: float = atan2(sin(a), cos(a))
		if absf(rel) > lim:
			continue
		var w: float = 1.0 / d
		ss += sin(rel) * w
		sc += cos(rel) * w
	if ss == 0.0 and sc == 0.0:
		return 0.0
	return clampf(sin(atan2(ss, sc)), -1.0, 1.0)


func _ping_enclosure(lp: Sonar.Pulse, indoor: bool, player: Player, world: World, game: Node) -> void:
	var e := Sonar.enclosure(lp)
	var n := 0
	var rng: float = lp.range if lp.range > 0.0 else 10.0
	for p in world.props:
		if not p["solid"]:
			continue
		var dx: float = p["x"] - player.x
		var dy: float = p["y"] - player.y
		if dx * dx + dy * dy <= rng * rng and game.first_solid(player.x, player.y, p["x"], p["y"]) == null:
			n += 1
	for pe in game.people.people:
		var dx2: float = pe.x - player.x
		var dy2: float = pe.y - player.y
		if sqrt(dx2 * dx2 + dy2 * dy2) <= rng and game.first_solid(player.x, player.y, pe.x, pe.y) == null:
			n += 1
	set_wet(Acoustics.wet_for(e["hitFrac"], e["meanAlpha"], n, indoor))


func _ping_echo(lp: Sonar.Pulse, player: Player, game: Node) -> void:
	var speed: float = game.sonar.speed
	var best := Sonar.strongest_echo(lp, player.angle)
	if not best.is_empty():
		var m := Acoustics.mat_of(best["mat"])
		var opts := {"voice": m["voice"], "rough": best["rough"]}
		echo(_clamp(Sonar.echo_delay(best["dist"], speed), 0.0, 6.0), Acoustics.game_amp(best["level"]), _echo_pan(lp, player), opts)
	else:
		var nearest: float = Sonar.nearest_dist(lp)
		var rng: float = lp.range if lp.range > 0.0 else 10.0
		echo(_clamp(Sonar.echo_delay(nearest, speed), 0.0, 6.0), _clamp(1.0 - nearest / rng, 0.15, 1.0), _echo_pan(lp, player), {"voice": "plain"})


func _floor_bounce(player: Player, world: World, game: Node) -> void:
	if ping_bip:
		return
	var m: String = game.step_material(player.x, player.y)
	var amp := Acoustics.floor_amp(m)
	if amp > 0.0:
		echo(float(Acoustics.a()["floor"]["delay"]), amp, 0.0, {"voice": Acoustics.mat_of(m)["voice"]})


func _ceiling_bounce(indoor: bool, zone: String) -> void:
	if not indoor or ping_bip:
		return
	var c := Acoustics.ceiling_for(zone)
	var amp := Acoustics.ceil_amp(float(c["h"]), c["mat"])
	if amp > 0.0:
		var m := Acoustics.mat_of(c["mat"])
		echo(Acoustics.ceil_delay(float(c["h"])), amp, 0.0, {"voice": m["voice"], "rough": m["rough"]})


func _prop_echoes(lp: Sonar.Pulse, player: Player, world: World, game: Node) -> void:
	if ping_bip:
		return
	var ac := Acoustics.a()
	var rng: float = lp.range if lp.range > 0.0 else 10.0
	var found: Array = []
	for pr in world.props:
		if not pr["solid"]:
			continue
		var dx: float = pr["x"] - player.x
		var dy: float = pr["y"] - player.y
		var d: float = sqrt(dx * dx + dy * dy)
		if d > rng or d < 0.3:
			continue
		var amp := Acoustics.prop_amp(d, atan2(dy, dx) - player.angle)
		if amp <= 0.0:
			continue
		var delay: float = Sonar.echo_delay(d, game.sonar.speed)
		if delay > 2.0 or game.first_solid(player.x, player.y, pr["x"], pr["y"]) != null:
			continue
		var mat: String = ac["propMat"].get(pr["type"], "wood")
		found.append({"amp": amp, "delay": delay, "x": pr["x"], "y": pr["y"], "mat": mat})
	found.sort_custom(func(a, b): return a["amp"] > b["amp"])
	var maxn: int = int(ac["propEcho"]["max"])
	for i in mini(found.size(), maxn):
		var f: Dictionary = found[i]
		var m := Acoustics.mat_of(f["mat"])
		echo(f["delay"], f["amp"], game.pan_to(f["x"], f["y"]), {"voice": m["voice"], "rough": m["rough"]})


func _bounce_echoes(player: Player, game: Node) -> void:
	var maxn: int = int(GameData.sounds()["maxBounceEchoes"])
	var picks: Array = []
	for c in game.sonar.pulses:
		if not (c.gen > 0) or not (c.t0 >= game.clock - 1e-6) or c.kind == "door" or c.kind == "interact":
			continue
		picks.append(c)
	picks.sort_custom(func(a, b): return a.t0 < b.t0)
	for i in mini(picks.size(), maxn):
		var c: Sonar.Pulse = picks[i]
		var dc: float = sqrt((c.x - player.x) * (c.x - player.x) + (c.y - player.y) * (c.y - player.y))
		var delay: float = c.t0 - game.clock + dc / (c.speed if c.speed > 0.0 else game.sonar.speed)
		if delay > 2.0:
			continue
		var voice: String = Acoustics.mat_of(c.mat if c.mat != "" else "stone")["voice"]
		echo(delay, _clamp(0.35 * (c.strength if c.strength > 0.0 else 0.4), 0.05, 0.3), game.pan_to(c.x, c.y), {"voice": voice})


## Audible echo of a person snapshot (js personEcho): only the player's own ping returns as an echo.
func person_echo(e: People.Echo, sonar: Sonar) -> void:
	if e.kind != "" and e.kind != "ping":
		return
	var amp: float = clampf(Acoustics.person_amp(e.dist, e.theta), 0.1, 0.7)
	echo(clampf(e.dist / sonar.speed, 0.0, 6.0), amp, e.pan, {"voice": "person"})


## js Audio.stopAll: silence every voice and drop queued echoes (the fade is not modelled: baked samples stop at once).
func stop_all(_fade: float = 0.0) -> void:
	_pending.clear()
	for slot in _pool:
		slot["player"].stop()


# ---------------------------------------------------------------- beds, fire, heartbeat, breath, far sounds

func _loop_stream(entry: Dictionary) -> AudioStream:
	var st: AudioStreamWAV = (_stream(entry["file"]) as AudioStreamWAV).duplicate()
	st.loop_mode = AudioStreamWAV.LOOP_FORWARD
	st.loop_begin = 0
	st.loop_end = st.data.size() / 2
	return st


func _build_beds() -> void:
	for kind in ["outdoor", "indoor"]:
		var vs := _variants("amb:%s" % kind)
		if vs.is_empty():
			continue
		var pl := AudioStreamPlayer.new()
		pl.bus = "Beds"
		pl.stream = _loop_stream(vs[0])
		pl.volume_db = -80.0
		add_child(pl)
		_amb[kind] = {"player": pl, "cur": 0.0, "tgt": 0.0, "entry": vs[0]}
	var fv := _variants("fire:bed")
	for k in 2:
		if fv.is_empty():
			break
		var pl2 := AudioStreamPlayer.new()
		pl2.bus = "Fire%d" % k
		pl2.stream = _loop_stream(fv[0])
		pl2.volume_db = -80.0
		add_child(pl2)
		_fire.append({"player": pl2, "pan": AudioServer.get_bus_effect(_bus_index("Fire%d" % k), 0), "cur": 0.0, "tgt": 0.0, "entry": fv[0], "started": false, "lv": 0.0})


func _apply_level(pl: AudioStreamPlayer, lin: float) -> void:
	if muted or lin <= 0.0005:
		if pl.playing:
			pl.stream_paused = true
		pl.volume_db = -80.0
		return
	pl.stream_paused = false
	if not pl.playing:
		pl.play()
	pl.volume_db = linear_to_db(lin)


func _step_beds(dt: float) -> void:
	if dt <= 0.0:
		return
	for kind in _amb:
		var b: Dictionary = _amb[kind]
		var tgt: float = b["tgt"]
		var cur: float = b["cur"]
		if tgt > 0.0:
			b["peak"] = tgt
		# linear ramp over AMB_FADE seconds from silence to the full level (and back)
		var step: float = float(b.get("peak", tgt)) / AMB_FADE * dt
		cur = move_toward(cur, tgt, step)
		b["cur"] = cur
		_apply_level(b["player"], cur)
	for f in _fire:
		var tgt2: float = f["tgt"]
		var cur2: float = f["cur"]
		# setTargetAtTime(tgt, now, 0.12): exponential approach
		cur2 += (tgt2 - cur2) * (1.0 - exp(-dt / 0.12))
		f["cur"] = cur2
		_apply_level(f["player"], cur2)


## js Audio.ambience: kind outdoor | indoor | none, level01 0..1; changing kind crossfades over 1.5 s. Returns true when a bed plays.
func ambience(kind: String, level01: float = 1.0) -> bool:
	_record("ambience", {"kind": kind, "level01": level01})
	var k := kind if kind == "outdoor" or kind == "indoor" else "none"
	var lvl: float = clampf(level01, 0.0, 1.0) if is_finite(level01) else 1.0
	_amb_kind = k
	_amb_level = lvl
	for name in _amb:
		var b: Dictionary = _amb[name]
		var e: Dictionary = b["entry"]
		var lin: float = volume * lvl / float(e["scale"]) if name == k else 0.0
		b["tgt"] = lin
	return k != "none" and _amb.has(k)


## js Audio.fireBed: quiet steady fire noise on one of two slots; level01 0..1 and pan -1..1.
func fire_bed(slot: int, level01: float, pan: float) -> bool:
	if slot < 0 or slot >= _fire.size():
		return false
	var lv: float = clampf(level01, 0.0, 1.0) if is_finite(level01) else 0.0
	var f: Dictionary = _fire[slot]
	f["lv"] = lv
	f["tgt"] = volume * lv / float(f["entry"]["scale"])
	(f["pan"] as AudioEffectPanner).pan = clampf(pan, -1.0, 1.0)
	return lv > 0.0


## js Audio.heartbeat (the felt lub-dub of a body): opts {pan, dist, behind, occluded, bpm}.
func heartbeat(o: Dictionary = {}) -> bool:
	_record("heartbeat", o)
	var lv := SoundData.level("vheart")
	var hear: float = float(lv["hearDist"]) if lv.get("hearDist") != null else 3.0
	var gain := 1.0
	if o.get("dist") is float or o.get("dist") is int:
		var dist := float(o["dist"])
		if dist >= 0.0:
			if dist >= hear:
				return false
			var near: float = hear * 0.4
			gain *= (0.1 + 1.05 * (1.0 - dist / near)) if dist < near else 0.1 * (1.0 - (dist - near) / (hear - near))
	if o.get("behind", false):
		gain *= 0.8
	if o.get("occluded", false):
		gain *= 0.6
	gain *= volume
	if not (gain > 0.0):
		return false
	var bpm: float = clampf(float(o.get("bpm", 70.0)), 30.0, 180.0)
	var best: Dictionary = {}
	for v in _variants("vheart:beat"):
		if best.is_empty() or absf(float(v["bpm"]) - bpm) < absf(float(best["bpm"]) - bpm):
			best = v
	if best.is_empty():
		return false
	var pan: float = clampf(float(o.get("pan", 0.0)), -1.0, 1.0) * 0.5
	_start(best, gain / float(best["scale"]), pan, 0.0)
	return true


## js Audio.breath: one soft breath swell. opts {pan, dist, behind, occluded, occ {mat, diff}}.
func breath(o: Dictionary = {}) -> bool:
	_record("breath", o)
	var lv := SoundData.level("breath")
	var hear: float = float(lv["hearDist"]) if lv.get("hearDist") != null else 6.0
	var gain := 1.0
	if o.get("dist") is float or o.get("dist") is int:
		var dist := float(o["dist"])
		if dist >= 0.0:
			if dist >= hear:
				return false
			gain *= 1.0 - dist / hear
	if o.get("behind", false):
		gain *= 0.7
	var occ: Variant = o.get("occ")
	if occ is Dictionary and occ.get("mat") is String:
		gain *= float(Acoustics.occlusion(occ["mat"], float(occ["diff"]) if occ.get("diff") != null else NAN)["gain"])
	elif o.get("occluded", false):
		gain *= 0.5
	var dull_it: bool = o.get("occluded", false) or o.get("behind", false) or (occ is Dictionary and occ.get("mat") is String)
	gain *= volume
	if not (gain > 0.0):
		return false
	var vs := _variants("breath:dull" if dull_it else "breath:soft")
	if vs.is_empty():
		return false
	_start(vs[0], gain / float(vs[0]["scale"]), clampf(float(o.get("pan", 0.0)), -1.0, 1.0), 0.0)
	return true


## js Audio.oneShotFar: a scheduled distant dog or church bell.
func one_shot_far(kind: String, o: Dictionary = {}) -> bool:
	if kind != "dog" and kind != "bell":
		return false
	return play(kind, {"pan": o.get("pan", 0.0), "dist": o.get("dist", -1.0)})


# ---------------------------------------------------------------- speech

## js Audio.speak: villager speech synthesised on a worker thread (SpeechSynth), then played on a voice slot with pan and low-pass.
## Returns {end: seconds the line lasts, stop: Callable}; at most MAX_SPEAKERS at once (the oldest is silenced).
func speak(o: Dictionary) -> Dictionary:
	_record("speak", o)
	var dd := VoiceData.d()
	var mood_name: Variant = o.get("mood")
	var mr: Dictionary = dd["MOODS"][mood_name] if mood_name is String and dd["MOODS"].has(mood_name) else dd["MOODS"]["calm"]
	var voice: Dictionary = VoiceData.resolve_voice(o.get("voice"))
	var og: float = clampf(float(o["gain"]), 0.0, 1.0) if o.get("gain") is float or o.get("gain") is int else 1.0
	var weak_in: Variant = o.get("weak")
	var weak: float = VoiceData.weak_of(weak_in)
	var lv := SoundData.level("voice")
	var peak: float = volume * float(lv.get("gain", 0.06)) * float(mr["gain"]) * og * (1.0 - 0.6 * weak)
	var length: float = VoiceData.speak_length(o.get("seed", 0), String(o.get("kind", "chat")), mood_name, voice, weak_in)
	var handle := {"dead": false, "player": null}
	var stop_fn := func() -> void:
		handle["dead"] = true
		var pl: Variant = handle["player"]
		if pl != null and is_instance_valid(pl):
			(pl as AudioStreamPlayer).stop()
	if muted or _pool.is_empty() or not (peak > 0.0):
		return {"end": length, "stop": stop_fn}
	var syls := VoiceData.line(o.get("seed", 0), String(o.get("kind", "chat")), mood_name, weak if weak_in != null else null)
	if syls.is_empty():
		return {"end": length, "stop": stop_fn}
	# concurrency cap: drop the oldest live speaker
	_speakers = _speakers.filter(func(s): return not s["handle"]["dead"] and s["end"] > _now)
	while _speakers.size() >= MAX_SPEAKERS:
		var old: Dictionary = _speakers.pop_front()
		(old["stop"] as Callable).call()
	_speakers.append({"handle": handle, "end": _now + length + 0.5, "stop": stop_fn})
	var params := {
		"syls": syls, "voice": voice, "mood": mr, "weak": weak, "vowels": dd["VOWELS"], "consonants": dd["CONSONANTS"],
		"seed": VoiceData.hash_seed(o.get("seed", 0)),
	}
	var pan: float = clampf(float(o.get("pan", 0.0)), -1.0, 1.0)
	var lp: float = float(o["lpHz"]) if o.get("lpHz") is float and float(o["lpHz"]) > 0.0 else 1800.0
	WorkerThreadPool.add_task(func() -> void:
		var r: Dictionary = SpeechSynth.render(params)
		var pcm: Dictionary = SpeechSynth.to_pcm16(r["pcm"])
		_speech_ready.call_deferred(handle, pcm["bytes"], pcm["scale"], peak, pan, lp))
	return {"end": length, "stop": stop_fn}


func _speech_ready(handle: Dictionary, bytes: PackedByteArray, scale: float, peak: float, pan: float, lp: float) -> void:
	if handle["dead"] or muted or _pool.is_empty():
		return
	var st := AudioStreamWAV.new()
	st.format = AudioStreamWAV.FORMAT_16_BITS
	st.mix_rate = SpeechSynth.RATE
	st.stereo = false
	st.data = bytes
	var slot: Dictionary = _pool[_next_slot]
	for k in VOICES:
		var cand: Dictionary = _pool[(_next_slot + k) % VOICES]
		if not cand["player"].playing:
			slot = cand
			_next_slot = (_next_slot + k + 1) % VOICES
			break
	var player: AudioStreamPlayer = slot["player"]
	(slot["pan"] as AudioEffectPanner).pan = pan
	(slot["lp"] as AudioEffectLowPassFilter).cutoff_hz = lp
	player.stream = st
	player.volume_db = linear_to_db(maxf(peak / scale, 1e-6))
	handle["player"] = player
	player.play()
