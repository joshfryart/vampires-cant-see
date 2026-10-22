class_name Powers
extends RefCounted
## Blood powers (shriek, mist, still) and thrown rocks, ported from the js/game.js power and rock code.

const MIST_DIST := 2.0
const MIST_DUR := 0.18
const ROCKS_PER_RUN := 3
const ROCK_RANGE := 10.0
const ROCK_SPEED := 14.0
const ROCK_COOL := 1.0

var g: Game
var mist: Variant = null          # {t, dx, dy, left} while dashing
var mist_vis: float = 0.0
var rocks: Array = []             # [{x, y, at}]
var rocks_left: int = ROCKS_PER_RUN
var rock_cool: float = 0.0
var miss_at: float = -99.0
var msg_at: float = -99.0


func _init(game: Game) -> void:
	g = game


func reset_run() -> void:
	mist = null
	mist_vis = 0.0
	rocks.clear()
	rocks_left = ROCKS_PER_RUN
	rock_cool = 0.0


## Q shriek, Shift or C mist, F still (js powerKeys).
func power_keys() -> void:
	if g.hunger == null or g.night == null:
		return
	if g.pressed.has(KEY_Q):
		use_power("shriek")
	if g.pressed.has(KEY_SHIFT) or g.pressed.has(KEY_C):
		use_power("mist")
	if g.pressed.has(KEY_F):
		use_power("still")


## Spend blood on a power and run its effect. Returns Hunger's result {ok, code, cost}.
func use_power(id: String) -> Dictionary:
	var bad := {"ok": false, "code": "E_UNKNOWN", "cost": null}
	if g.hunger == null or g.night == null or g.state != "playing" or g.drink != null:
		return bad
	var r: Dictionary = g.hunger.use(id, float(g.night.night), g.night.blood)
	if not r["ok"]:
		if g.clock - miss_at > 0.35 or miss_at > g.clock:
			miss_at = g.clock
			g.audio.play("miss", {"gain": SoundData.level("miss")["gain"], "pan": 0.0})
		if r["code"] == "E_POOR" and (g.clock - msg_at > 3.0 or msg_at > g.clock):
			msg_at = g.clock
			g.show_card("Not enough blood", Game.CARD_LEN - 1.0)
		return r
	g.night.blood = maxf(0.0, g.night.blood - float(r["cost"]))
	match id:
		"shriek": do_shriek()
		"mist": start_mist()
		"still": do_still()
	return r


## Shriek: a loud pulse at double range; people react far away.
func do_shriek() -> void:
	var weak: float = g.night.weakness() if g.night != null else 0.0
	var rng_: float = Game.BASE_RANGE * g.fxv("sonarRange") * 2.0 * (1.0 - 0.4 * weak)
	g.emit_sound("shriek", g.player.x, g.player.y, {"range": rng_})
	g.audio.play("shriek", {"gain": SoundData.level("shriek")["gain"], "pan": 0.0})
	var react: Dictionary = GameData.sounds()["react"]
	var base: float = float(react.get("startleDist", 3.0))
	var mul: float = float(react.get("shriekMul", 2.5))
	g.react_cfg_now()
	g.react_to(g.player.x, g.player.y, "shriek", base * mul * g.fxv("noise") * float(g.fm["startleMul"]))


## Mist: a quiet two-cell dash along the move direction (or facing).
func start_mist() -> void:
	var p: Player = g.player
	var f: float = float(g.last_input.get("forward", 0.0))
	var s: float = float(g.last_input.get("strafe", 0.0))
	var dx: float = f * cos(p.angle) + s * cos(p.angle + PI / 2.0)
	var dy: float = f * sin(p.angle) + s * sin(p.angle + PI / 2.0)
	var length: float = sqrt(dx * dx + dy * dy)
	if not (length > 0.0):
		dx = cos(p.angle)
		dy = sin(p.angle)
		length = 1.0
	mist = {"t": 0.0, "dx": dx / length, "dy": dy / length, "left": MIST_DIST}
	mist_vis = 1.0
	g.step_timer = 0.0
	g.react_cfg_now()
	g.emit_sound("mist", p.x, p.y)
	g.audio.play("mist", {"gain": SoundData.level("mist")["gain"], "pan": 0.0})


## Advance the mist dash by dt using small collision substeps.
func step_mist(dt: float) -> void:
	if mist == null:
		return
	var m: Dictionary = mist
	var p: Player = g.player
	var r: float = p.radius
	var want: float = minf(float(m["left"]), MIST_DIST * minf(dt, MIST_DUR) / MIST_DUR)
	var blocked := false
	while want > 1e-6 and not blocked:
		var d: float = minf(0.1, want)
		want -= d
		var moved := false
		var nx: float = p.x + float(m["dx"]) * d
		if not g.world.blocks(nx, p.y, r):
			p.x = nx
			moved = true
		var ny: float = p.y + float(m["dy"]) * d
		if not g.world.blocks(p.x, ny, r):
			p.y = ny
			moved = true
		if moved:
			m["left"] = float(m["left"]) - d
		else:
			blocked = true
	m["t"] = float(m["t"]) + dt
	if blocked or float(m["left"]) <= 1e-6 or float(m["t"]) >= MIST_DUR + 0.05:
		mist = null


## Still: five quiet seconds.
func do_still() -> void:
	g.react_cfg_now()
	g.audio.play("still", {"gain": SoundData.level("still")["gain"], "pan": 0.0})
	g.emit_sound("still", g.player.x, g.player.y)


## G: throw a rock along the facing; it flies until a wall or person and clatters down after its flight time.
func throw_rock() -> bool:
	if g.state != "playing" or g.drink != null or rock_cool > 0.0:
		return false
	if rocks_left <= 0:
		rock_cool = ROCK_COOL
		g.show_card("No rocks left", 0.0)
		g.audio.play("miss", {"gain": 0.06, "pan": 0.0})
		return false
	rocks_left -= 1
	var p: Player = g.player
	var dx: float = cos(p.angle)
	var dy: float = sin(p.angle)
	var d := 0.0
	while d < ROCK_RANGE:
		var nx: float = p.x + dx * (d + 0.1)
		var ny: float = p.y + dy * (d + 0.1)
		if g.world.blocks(nx, ny, 0.05):
			break
		d += 0.1
		var hit := false
		for q in g.people.people:
			if sqrt((q.x - nx) * (q.x - nx) + (q.y - ny) * (q.y - ny)) < 0.3:
				hit = true
		if hit:
			break
	d = maxf(0.4, d)
	rocks.append({"x": p.x + dx * d, "y": p.y + dy * d, "at": g.clock + d / ROCK_SPEED})
	rock_cool = ROCK_COOL
	g.audio.play("miss", {"gain": 0.1, "pan": 0.0})
	return true


## Land any rocks whose flight is over: a loud clatter, sound waves, nearby villagers startle.
func step_rocks() -> void:
	var i: int = rocks.size() - 1
	while i >= 0:
		var r: Dictionary = rocks[i]
		i -= 1
		if float(r["at"]) > g.clock:
			continue
		rocks.erase(r)
		g.emit_sound("clatter", r["x"], r["y"])
		var lv := SoundData.level("clatter")
		g.react_to(r["x"], r["y"], "clatter", float(lv["range"]) * 0.7)
		g.audio.play("clatter", g.spatial(r["x"], r["y"], float(lv["gain"]), {"material": g.step_material(r["x"], r["y"])}))
