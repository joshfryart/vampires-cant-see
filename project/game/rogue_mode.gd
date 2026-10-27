class_name RogueMode
extends RefCounted
## "The Long Night" (docs/ROGUELIKE.md) wired into the Game: it owns the TrekFlow, the Critters, the Ambient emitters, the day choice
## (sleep / wait out the day with WaitDay), the hunters, the cave audio and the Laid to Rest hand-off. It registers itself as a Game
## `systems` hook (step / on_pulse / draw) while a trek is on, and game.gd calls the few hooks below (interact, feed, exit door, ...).
## Classic Five Nights code is untouched: while `active` the classic night clock, saves and sleep are bypassed in game.gd / run_flow.gd.
##
## Entry points: new_trek(seed), continue_trek(), connect_ui() (Menus signals). Everything else is called by Game each frame.

const SOUNDS_PATH := "res://data/rogue/sounds_rogue.json"
const SLEEP_REACH := 1.5
const REST_NOTE := 3.0
## A hidden rest spot (not the coffin nook) becomes known when the player is this close (cells).
const REST_DISCOVER := 3.0
## Dawn hum: during the dawn warning every non-coffin rest spot emits a faint `rest_hum` pulse (short range, low strength).
const REST_HUM_RANGE := 5.0
const REST_HUM_STRENGTH := 0.18
const REST_HUM_PERIOD := 3.0
const REST_HUM_RAYS := 90
const REST_HUM_WITHIN := 12.0
## Powers on a trek: the classic night counter would lock Mist (night 2) and Still (night 3) on the first dusk, so a trek uses this level.
const POWER_LEVEL_ALL := 3
const FEED_REACH := 1.2
const HUNTER_SPEED := 2.4
const HUNTER_FIELD_SEC := 0.4
const HUNTER_MIN_BFS := 16
const HUNTER_MAX_BFS := 38
const HEAT_CARD_SEC := 3.0
## An interrupted wait ends by itself after this many seconds (the Stir button / E / Enter / Space end it sooner).
const INTERRUPT_TIMEOUT := 8.0
## Hunter modes People drives itself (shrieked / grappled / frightened): the hunter walk and the stake leave them alone.
const HUNTER_BUSY := ["fed", "grapple", "dazed", "flee"]
const INTERRUPT_TEXT := {
	"occupant_in_room": "Someone is in the room with you.",
	"occupant_near": "Someone is very close.",
	"guard_near": "A guard walks nearby.",
}
## How loud a sonar kind is to the critters (Critters.hear loudness); anything else does not frighten them.
const NOISE_LOUD := {"shriek": 1.5, "scream": 1.0, "struggle": 0.5, "door": 0.5}
## Beat id -> tutorial hint id (shown once when the player comes within 4 cells of the beat).
const BEAT_HINTS := {"squeeze": "squeeze", "dead_end_spurs": "dead_end", "cave_mouth": "sun"}

var g: Game
var trek: TrekFlow = null
var active: bool = false
var critters: Critters = null
var ambient: Ambient = null
var amb_rng: Rng = null
var waiting: bool = false
var wait_day: WaitDay = null
var wait_last: Dictionary = {}
var prompt_open: bool = false
var hunter_ids: Array = []
var last_result: Dictionary = {}
## Counters for tests and diagnostics.
var stats: Dictionary = {"critters_fed": 0, "stages": 0, "squeaks": 0, "drips": 0}
var _hfield: PackedInt32Array = PackedInt32Array()
var _hfield_t: float = 99.0
var _flee_state: Dictionary = {}
var _flee_snd: Dictionary = {}
var _bell30: bool = false
var _sounds: Dictionary = {}
var _audio_ready: bool = false
var _wind: AudioStreamPlayer = null
var _shop_sig: String = ""
var _t: float = 0.0
var _spawn_idx: Dictionary = {}   ## critter id -> index in the descriptor's critters list (for the eaten save)
var _interrupt_t: float = 0.0
var _classic: Dictionary = {}     ## classic flow state to restore when the trek stops
var _rng_h: Rng = null
var rest_known: Dictionary = {}   ## "x,y" of a discovered rest spot -> true (the coffin nook is always known); reset per stage
var _hum_next: Dictionary = {}    ## "x,y" -> sonar time of the next hum
var _hum_live: Sonar.Pulse = null
var _last_pp: Vector2 = Vector2(NAN, NAN)
var _speed: float = 0.0           ## smoothed player speed (cells/s), for the critters' sneak test
var hum_count: int = 0


func _init(game: Game) -> void:
	g = game


# ---------------------------------------------------------------- menu wiring

## Connect the Menus signals (title buttons, Laid to Rest buttons, the Stir button). Safe to call once at boot.
func connect_ui() -> void:
	var m: Variant = g.menus
	if m == null:
		return
	m.trek_new_requested.connect(func(): new_trek())
	m.trek_continue_requested.connect(func(): continue_trek())
	m.rise_again_requested.connect(func():
		m.hide_laid_to_rest()
		new_trek())
	m.title_requested.connect(func():
		m.hide_laid_to_rest()
		g.set_state("title"))
	m.trek_ui.wait_interrupted.connect(func(): stir())
	# the classic Essence turns into Grave Soil 1:1, once, as soon as the game knows there is some
	if g.flow != null and int(g.flow.meta.get("essence", 0)) > 0:
		var tm: Dictionary = _meta()
		if TrekMeta.import_legacy_essence(tm, g.flow.meta) > 0 and g.flow.store != null:
			g.flow.store.write("rogue", TrekMeta.SCHEMA, tm)


func _meta() -> Dictionary:
	return g.menus._tm()


func _ui() -> TrekUi:
	return g.menus.trek_ui


# ---------------------------------------------------------------- starting and stopping

## A brand new trek (title button, Rise Again). The old checkpoint is abandoned. seed_v < 0 picks one (flow.seed_param wins).
func new_trek(seed_v: int = -1) -> bool:
	_deactivate(false)
	var s: int = seed_v
	if s < 0:
		s = int(g.flow.seed_param) if g.flow.seed_param != null else (randi() & JsMath.M32)
	if g.flow.store != null:
		g.flow.store.remove("trek")
	var t := TrekFlow.begin(_meta(), s, g.flow.store)
	if t == null:
		push_warning("RogueMode: the first stage could not be generated (seed %d)" % s)
		return false
	_start(t, true)
	return true


## Continue from the checkpoint (title button). False when there is none or it no longer loads.
func continue_trek() -> bool:
	_deactivate(false)
	if g.flow.store == null:
		return false
	var r: Dictionary = g.flow.store.read("trek")
	if not r["ok"]:
		return false
	var t := TrekFlow.continue_from(r["data"], _meta(), g.flow.store)
	if t == null:
		return false
	_start(t, false)
	return true


func _start(t: TrekFlow, fresh: bool) -> void:
	trek = t
	if _classic.is_empty():
		_classic = {"has_run": g.flow.has_run, "fx": g.flow.fx.duplicate(true)}
	active = true
	last_result = {}
	g.end_drink("run")
	g.hunger = trek.hunger
	g.night = trek.night
	g.flow.run = {"seed": trek.seed, "boons": [], "closedSafe": {}, "pendingBoons": null, "pendingGifts": null}
	g.flow.fx = trek.fx
	g.flow.seq = null
	g.flow.has_run = false
	g.powers.reset_run()
	g.transition = null
	g.wipe_k = 0.0
	g.card_text = ""
	g.over_acc = 0.0
	g.end_listen()
	g.barks_reset()
	g.sonar.protect_last = true
	trek.emitter = func(w, x, y, _t0, opts): g.sonar.emit_sound(w, x, y, g.clock, opts)
	_init_audio()
	_enter_descriptor(trek.descriptor)
	g.run_on = true
	g.init_ambient()
	g.tut.clear()
	g.tut.queued = {}
	g.tut.queue("drip")
	g.tut.queue("ping")
	g.tut.queue("powers")
	if not g.systems.has(self):
		g.systems.append(self)
	g.set_state("playing")
	if fresh:
		sfx("rg_coffin_creak")
	if trek.needs_choice():
		_open_choice()
	_recapture()


## Show a stage: build its world, put the player on the start cell, spawn its critters and ambient emitters, the stage card.
func _enter_descriptor(d: Dictionary) -> void:
	var name: String = d["map_name"]
	var prev: String = g.map_name
	if g.map_name == name:
		g.map_name = ""   # a stale copy of the same stage (an earlier trek): let add_world evict it
	g.add_world(name, d["def"])
	var st: Vector2i = d["start"]
	g.enter_map(name, st.x + 0.5, st.y + 0.5, float(d["angle"]), "")
	trek.world = g.worlds[name]
	if prev != "" and prev != name:
		g.drop_world(prev)
	var is_day: bool = trek.night.status != "night"
	critters = Critters.new(g.world, float(int(d["seed"]) ^ 0x2545F491) + 1.0)
	_spawn_idx.clear()
	var list: Array = d["critters"]
	for i in list.size():
		if trek.eaten.has(i):
			continue   # drunk dry before the save: prey never respawns
		var cs: Dictionary = list[i]
		var c := critters.spawn(String(cs["species"]), Vector2i(int(cs["cell"][0]), int(cs["cell"][1])), is_day)
		if c != null:
			_spawn_idx[c.id] = i
	trek.critter_sys = critters
	trek.people = g.people
	ambient = Ambient.new(d["ambient"], {"drip_ear": 1.0 + float(trek.fx.get("dripEar", 0.0)) / 2.5})
	amb_rng = Rng.new(float(int(d["seed"]) ^ 0x1B873593) + 1.0)
	_rng_h = Rng.new(float(int(d["seed"]) ^ 0x68E31DA4) + 1.0)
	_flee_state.clear()
	_flee_snd.clear()
	rest_known.clear()
	_hum_next.clear()
	_hum_live = null
	_last_pp = Vector2(NAN, NAN)
	_speed = 0.0
	_bell30 = false
	hunter_ids.clear()
	_hfield = PackedInt32Array()
	_hfield_t = 99.0
	_spawn_hunters()
	var c: Dictionary = trek.stage_card()
	_ui().show_stage_card(int(c["index"]), String(c["stage_name"]), float(c["miles"]), String(c["time_of_day"]), float(c["seconds"]))
	sfx("rg_stage_arrival")
	stats["stages"] = int(stats["stages"]) + 1


func _deactivate(keep_state: bool) -> void:
	if not active and not waiting and not prompt_open:
		return
	active = false
	waiting = false
	prompt_open = false
	g.systems.erase(self)
	g.run_on = false
	g.sonar.protect_last = false
	if not _classic.is_empty():
		g.flow.has_run = bool(_classic["has_run"])
		g.flow.fx = _classic["fx"]
		_classic = {}
	if g.menus != null and g.menus.trek_ui != null:
		var ui := _ui()
		ui.hide_wait_prompt()
		ui.hide_waiting()
		ui.set_dawn(-1.0)
	if _wind != null:
		_wind.stream_paused = true
	if not keep_state:
		g.audio.stop_all(0.1)


## Game.set_state("title") (also the pause menu's "Save and quit"): checkpoint the trek and stop driving it.
func on_title() -> void:
	if active and trek != null and trek.alive():
		_checkpoint_now()
	_deactivate(true)


## The window is closing: checkpoint (js pagehide).
func on_close() -> void:
	if active and trek != null and trek.alive():
		_checkpoint_now()


## Quit / close: only a checkpoint-safe state is saved (the checkpoint position; blood, eaten prey and the wither timer as they are,
## a live wait's blood and day clock folded in), so quitting and continuing cannot be used to respawn prey or reset the wither timer.
func _checkpoint_now() -> void:
	trek.update_position(Vector2i(floori(g.player.x), floori(g.player.y)), Vector2(g.player.x, g.player.y))
	trek.quit_checkpoint(wait_day if waiting else null)


## Title / pause / run-end frames: only watches the Coffin shop for a purchase (chime).
func idle_step(_dt: float) -> void:
	var m: Dictionary = g.menus.trek_meta
	if m.is_empty():
		return
	var sig := JSON.stringify(m.get("unlocks", {}))
	if _shop_sig != "" and sig != _shop_sig:
		sfx("rg_soil_chime")
		sfx("rg_upgrade_sting")
	_shop_sig = sig


# ---------------------------------------------------------------- per frame (Game systems hook)

func step(_gm: Variant, dt: float) -> void:
	if not active or trek == null:
		return
	if g.state != "playing" and g.state != "feeding":
		return
	_t += dt
	g.flow.fx = trek.fx
	var pp := Vector2(g.player.x, g.player.y)
	var cell := Vector2i(floori(pp.x), floori(pp.y))
	var outdoor: bool = g.world.kind_at(pp.x, pp.y) == "outdoor"
	var frozen: bool = prompt_open or waiting
	var ctx := {"player_pos": pp, "mist": g.powers.mist != null, "hunters": _hunter_list(), "frozen": frozen}
	_handle(trek.step(dt, cell, outdoor, ctx))
	if not active:
		return
	_prompt_keys()
	if not frozen:
		_note_rest(pp)
		_step_hunters(dt)
	_step_critters(dt, pp)
	_step_ambient(dt, pp)
	step_rest_hum(pp)
	_step_wind()
	_step_hints(pp)
	var ui := _ui()
	ui.set_dawn(trek.dawn_in() if trek.night.status == "night" else 0.0)
	if trek.night.status == "night" and not _bell30 and trek.dawn_in() <= 30.0 and trek.dawn_warning():
		_bell30 = true
		sfx("rg_dawn_bell")
	if prompt_open and g.scenario == null and Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## Frames while waiting out the day (game.step branches here instead of simulating the world).
func step_waiting(dt: float) -> void:
	if not waiting or wait_day == null:
		return
	var o := wait_day.step(dt)
	wait_last = o
	# a captured mouse (resume from pause, a click outside the overlay) must never leave the Stir button unclickable
	if g.scenario == null and Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_ui().update_waiting(float(o["blood_after"]), _wait_lines(o))
	if g.interact_press or g.pressed.has(KEY_ENTER) or g.pressed.has(KEY_KP_ENTER) or g.pressed.has(KEY_SPACE):
		g.interact_press = false
		stir()
		return
	if String(o["result"]) == "interrupted":
		_interrupt_t += dt
		if _interrupt_t >= INTERRUPT_TIMEOUT:
			stir()
			return
	else:
		_interrupt_t = 0.0
	match String(o["result"]):
		"noticed", "withered", "dusk":
			_finish_wait(o)


## Day prompt keys: 1 waits out the day, 2 keeps looking (a click or E also choose; Space and Enter never do).
func _prompt_keys() -> void:
	if not prompt_open:
		return
	if g.pressed.has(KEY_1) or g.pressed.has(KEY_KP_1):
		_ui().hide_wait_prompt()
		_begin_wait()
	elif g.pressed.has(KEY_2) or g.pressed.has(KEY_KP_2):
		_ui().hide_wait_prompt()
		prompt_open = false
		_recapture()


func input_locked() -> bool:
	return active and (prompt_open or waiting)


## Sonar pulse hook: loud sounds flush the critters; the player's ping only freezes the ones close by (Critters.on_ping).
func on_pulse(_gm: Variant, pulse: Variant) -> void:
	if not active or critters == null or pulse == null:
		return
	if String(pulse.kind) == "ping":
		critters.on_ping(Vector2(pulse.x, pulse.y))   # the player's own ping startle-freezes nearby prey instead of flushing it
		return
	var loud: float = float(NOISE_LOUD.get(pulse.kind, 0.0))
	if loud <= 0.0:
		return
	var before := _states()
	critters.hear(pulse.x, pulse.y, loud)
	_flee_sounds(before)


## Game systems "draw" hook: the critter glyphs, lit by their echoes.
func draw(_gm: Variant, canvas: Variant) -> void:
	if not active or critters == null or g.state == "title":
		return
	var rs := g.echo_view.rs
	CritterDraw.draw_all(rs, canvas, {"x": g.player.x, "y": g.player.y, "angle": g.player.angle}, critters, g.clock, rs.tan_half())


# ---------------------------------------------------------------- events

func _handle(ev: Array) -> void:
	for e in ev:
		match String(e["type"]):
			"chime":
				g.audio.play("chime", {"gain": SoundData.level("chime")["gain"], "pan": 0.0})
			"dawn_warning":
				sfx("rg_dawn_bell")
				sfx("rg_dawn_birds", NAN, NAN, 0.6)
				g.tut.queue("dawn")
			"dawn":
				sfx("rg_dawn_birds")
				g.show_card("The sun is up", 0.0, "Find cover.")
			"needs_choice":
				_open_choice()
			"dusk":
				_on_dusk(e)
			"withering":
				g.show_card("You are withering", 0.0, "Drink, or you will fall.")
			"stake_hit":
				g.show_card("Staked", 0.0, "A hunter found your heart.")
				g.audio.play("scream", {"gain": float(SoundData.level("scream")["gain"]), "pan": 0.0})
			"stake_ignored":
				g.show_card("The stake glances off", 0.0, "Callused skin.")
			"noticed":
				g.show_card("Something saw you", 0.0, "Heat %d" % trek.heat)
			"revived":
				var c: Vector2i = e["cell"]
				g.player.place(c.x + 0.5, c.y + 0.5, g.player.angle)
				g.show_card("The second coffin", 0.0, "You wake where you last rested.")
			"death":
				_on_end()
				return


## A new night of the same stage (Heat +1): reset the sights and sounds, wake the world, new hunters.
func _on_dusk(e: Dictionary) -> void:
	prompt_open = false
	_ui().hide_wait_prompt()
	if g.hunger != null:
		var nb: float = g.hunger.on_sleep()
		g.hunger.still_left = 0.0
		if nb > 0.0:
			g.night.add_blood(nb)
	g.powers.mist = null
	g.sonar.reset()
	g.audio.stop_all(0.15)
	_bell30 = false
	_spawn_hunters()
	g.show_card("Dusk", 0.0, "Heat %d%s" % [int(e.get("heat", trek.heat)), (" - %d hunting" % int(e.get("hunters", 0))) if int(e.get("hunters", 0)) > 0 else ""])
	_recapture()


## The trek is over (death, or the end of the built stages): pay the Soil and show Laid to Rest.
func _on_end(result_in: Dictionary = {}) -> void:
	var r: Dictionary = result_in if not result_in.is_empty() else trek.end_run()
	last_result = r
	g.end_drink("run")
	g.audio.stop_all(0.1)
	_deactivate(true)
	g.menus.show_laid_to_rest(r)
	g.set_state("runend")
	sfx("rg_laid_to_rest")


# ---------------------------------------------------------------- the day: sleep or wait

func _rest_near(pos: Vector2, reach: float) -> Variant:
	var best: Variant = null
	var bd := reach
	for r in trek.def.get("rest", []):
		var d: float = Vector2(float(r["cell"][0]) + 0.5, float(r["cell"][1]) + 0.5).distance_to(pos)
		if d <= bd:
			bd = d
			best = r
	return best


func _open_choice() -> void:
	if prompt_open or waiting or not active:
		return
	prompt_open = true
	var near: Variant = _rest_near(Vector2(g.player.x, g.player.y), SLEEP_REACH)
	var body := "Under a roof you can wait out the day. Prey may stir, and Heat will rise."
	body += "\nYou are at a resting place: press E to sleep instead." if near != null else "\nAt a coffin or a resting place you can sleep (E)."
	body += "\n1: wait out the day   2: keep looking" + ("" if near != null else "   E: wait")
	_ui().show_wait_prompt({
		"title": "The sun is up", "body": body, "wait_label": "Wait out the day", "keep_label": "Keep looking",
		"on_wait": func(): _begin_wait(), "on_keep": func():
			prompt_open = false
			_recapture(),
	})
	if g.scenario == null:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _begin_wait() -> void:
	prompt_open = false
	wait_day = trek.begin_wait({})
	if wait_day == null:
		_recapture()
		return
	waiting = true
	wait_last = {}
	_interrupt_t = 0.0
	g.end_drink("wait")
	_ui().show_waiting(trek.blood(), [])
	g.interact_press = false
	g.pressed.erase(KEY_ENTER)
	g.pressed.erase(KEY_SPACE)
	if g.scenario == null:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _wait_lines(o: Dictionary) -> Array:
	var lines: Array = []
	if wait_day != null:
		var listens := 0
		for ev in wait_day.events:
			if ev["type"] == "listen":
				listens += 1
		if listens > 0:
			lines.append("Footsteps, somewhere near (%d heard)." % listens)
	if String(o.get("result", "")) == "interrupted":
		lines.append(String(INTERRUPT_TEXT.get(String(o.get("reason", "")), "Something stirs.")))
		lines.append("Stir to deal with it.")
	else:
		lines.append("%d seconds of sunlight left." % int(ceil(float(o.get("day_left", 0.0)))))
	return lines


## The Stir button (or the end of a wait): stop waiting, keep the blood and the day clock where they got to.
func stir() -> void:
	if not waiting:
		return
	_finish_wait(wait_last if not wait_last.is_empty() else {"result": "running", "blood_after": trek.blood()})


func _finish_wait(o: Dictionary) -> void:
	waiting = false
	_ui().hide_waiting()
	var r := trek.apply_wait(o)
	wait_day = null
	_handle(r["events"])
	if not active:
		return
	if String(r["result"]) == "noticed":
		_open_choice()
	_recapture()


## Sleep at the rest spot `rest` (a descriptor["rest"] entry). Returns "sleep" or "blocked".
func _sleep(rest: Dictionary) -> String:
	var cell := Vector2i(int(rest["cell"][0]), int(rest["cell"][1]))
	var r := trek.sleep_at_rest(cell)
	if not r.get("ok", false):
		return "blocked"
	prompt_open = false
	_ui().hide_wait_prompt()
	g.player.place(cell.x + 0.5, cell.y + 0.5, g.player.angle)
	g.audio.play("yawn", {"gain": SoundData.level("yawn")["gain"], "pan": 0.0})
	_handle(r["events"])
	if not active:
		return "sleep"
	if String(r["result"]) == "noticed":
		g.show_card("Something found you asleep", 0.0, "Heat %d" % trek.heat)
	g.flow.seq = {"type": "sleep", "t": 0.0, "dur": RunFlow.SLEEP_DUR, "did": true}
	g.set_state("sleeping")
	return "sleep"


## E (Game.interact, after doors): sleep at a rest spot by day, reopen the day prompt, or drink a critter in reach.
func interact() -> String:
	if not active or trek == null:
		return "none"
	var pp := Vector2(g.player.x, g.player.y)
	if trek.needs_choice():
		var near: Variant = _rest_near(pp, SLEEP_REACH)
		if near != null:
			return _sleep(near)
	if try_feed_critter():
		return "feed"
	if trek.needs_choice() and not prompt_open:
		_open_choice()
		return "choice"
	if trek.needs_choice() and prompt_open:
		_ui().hide_wait_prompt()   # E on the open prompt waits out the day
		_begin_wait()
		return "wait"
	return "none"


# ---------------------------------------------------------------- feeding

## Drink the nearest critter within reach (R or E). Returns true when one was fed on. Noise follows the classic rules in miniature:
## a struggle-sized sound at the critter, scaled by the Drinking Noise effect; Ratspeak (critterTalk) lets you drink without a sound
## and the second tier adds a quarter more blood.
func try_feed_critter() -> bool:
	if not active or critters == null or g.state != "playing" or g.drink != null:
		return false
	var c: Critters.Critter = critters.lunge(Vector2(g.player.x, g.player.y))
	if c == null:
		c = critters.nearest_feedable(g.player.x, g.player.y, FEED_REACH)
	if c == null:
		return false
	var sp: Dictionary = Critters.spec(c.species)
	var talk: float = float(trek.fx.get("critterTalk", 0.0))
	var base: float = float(sp.get("blood", 6)) * (1.25 if talk >= 2.0 else 1.0)
	var x := c.x
	var y := c.y
	var species := c.species
	if _spawn_idx.has(c.id):
		trek.mark_eaten(int(_spawn_idx[c.id]))
	critters.feed(c)
	var gain := trek.on_feed_critter(species, base)
	stats["critters_fed"] = int(stats["critters_fed"]) + 1
	for k in 3:
		g.landings.append(g.clock + 0.2 + 0.3 * k)
	g.ripple.spawn(x, y, g.clock, {"kind": "person", "maxR": 0.9, "life": 0.45, "strength": 0.7})
	if talk < 1.0:
		var nm: float = float(trek.fx.get("drinkNoise", 1.0)) * 0.5
		g.emit_sound("struggle", x, y, {"rangeMul": nm, "strengthMul": nm})
		sfx("rg_rat_squeak" if species == "rat" else "rg_bat_squeak", x, y)
	g.show_card("+%d blood" % int(round(gain)), 0.0, species.capitalize())
	return true


## A villager was drained to the end (Game.end_drink): count it for the Soil. The blood itself came through the classic drink.
func on_human_fed(person_id: int) -> void:
	if not active or trek == null or hunter_ids.has(person_id):
		return
	trek.on_feed_human(0.0)


func on_notice(by: int = -1) -> void:
	if active and trek != null:
		trek.on_notice(by)


# ---------------------------------------------------------------- the exit

## Game.check_link_door: the player stands in an open door. True when the trek took it (next stage or the end).
func on_exit_door() -> bool:
	if not active or trek == null or not trek.alive():
		return false
	var cell := Vector2i(floori(g.player.x), floori(g.player.y))
	if not trek.at_exit(cell):
		return false
	trek.update_position(cell, Vector2(g.player.x, g.player.y))
	var r := trek.reach_exit()
	if not r.get("ok", false):
		return false
	if r["ended"]:
		_on_end(r["result"])
		return true
	prompt_open = false
	_ui().hide_wait_prompt()
	_enter_descriptor(r["descriptor"])
	g.drop_inputs()
	_recapture()
	return true


# ---------------------------------------------------------------- critters, ambient, hunters, sounds

func _states() -> Dictionary:
	var out := {}
	for c in critters.critters:
		out[c.id] = c.state
	return out


## Play the flush sounds (bat wings, rat scurry) for critters that just started fleeing.
func _flee_sounds(before: Dictionary) -> void:
	for c in critters.critters:
		if c.state == "flee" and before.get(c.id, "") != "flee" and g.clock - float(_flee_snd.get(c.id, -9.0)) > 1.5:
			_flee_snd[c.id] = g.clock
			if c.species == "bat":
				sfx("rg_bat_flutter", c.x, c.y)
			elif c.species == "rat":
				sfx("rg_rat_skitter", c.x, c.y)
			elif c.species == "hare" or c.species == "rabbit":
				sfx("rg_hare_thump", c.x, c.y)
				g.emit_sound("struggle", c.x, c.y, {"rangeMul": 0.6, "strengthMul": 0.5})
			elif c.species == "crow":
				sfx("rg_crow_caw", c.x, c.y)


func _step_critters(dt: float, pp: Vector2) -> void:
	var is_day: bool = trek.night.status != "night"
	var before := _states()
	var sneak: bool = _track_speed(pp, dt) < Critters.SNEAK_SPEED
	critters.step(pp, dt, is_day, {}, sneak)
	_flee_sounds(before)
	var t_prev: float = g.clock - dt
	for pu in g.sonar.pulses:
		critters.echo_snapshot_visible(pu, t_prev, g.clock)
	critters.prune_echoes(g.clock, 1.2)
	if critters.echoes.size() > 48:
		critters.echoes = critters.echoes.slice(critters.echoes.size() - 48)
	var sq := {}
	for c in critters.critters:
		sq[c.id] = c.squeak_t
	if critters.squeak(g.sonar, g.clock) > 0:
		for c in critters.critters:
			if sq.has(c.id) and c.squeak_t > float(sq[c.id]) + 0.5:
				stats["squeaks"] = int(stats["squeaks"]) + 1
				match c.species:
					"bat": sfx("rg_bat_squeak", c.x, c.y)
					"rat": sfx("rg_rat_squeak", c.x, c.y)
					"sheep": sfx("rg_sheep_bleat", c.x, c.y)
					"hen": sfx("rg_hen_cluck", c.x, c.y)
					"crow": sfx("rg_crow_caw", c.x, c.y)
					"wolf": sfx("rg_wolf_howl", c.x, c.y)


## Smoothed player speed in cells/s (a teleport, e.g. a revive, does not count as running).
func _track_speed(pp: Vector2, dt: float) -> float:
	if dt > 0.0 and not is_nan(_last_pp.x):
		var inst: float = pp.distance_to(_last_pp) / dt
		if inst > 12.0:
			inst = 0.0
		_speed += (inst - _speed) * (1.0 - exp(-dt / 0.15))
	_last_pp = pp
	return _speed


func _step_ambient(dt: float, pp: Vector2) -> void:
	var before: Array = ambient.live.duplicate()
	ambient.step(g.world, g.sonar, pp, dt, amb_rng, g.clock)
	for p in ambient.live:
		if before.has(p):
			continue
		match String(p.kind):
			"drip":
				stats["drips"] = int(stats["drips"]) + 1
				var pool := g.world.tile_at(p.x, p.y) == "~"
				sfx("rg_drip_pool" if pool else "rg_drip_cave", p.x, p.y)
			"ripple":
				sfx("rg_drip_pool", p.x, p.y)
			"owl":
				sfx("rg_owl_hoot", p.x, p.y)


## The draft at the cave mouth: a looping wind bed whose level follows the distance to the exit.
func _step_wind() -> void:
	if g.audio == null or not g.audio.is_inside_tree() or not _sounds.has("rg_wind_loop") or AudioServer.get_bus_index("Beds") < 0:
		return
	if _wind == null:
		var st: Variant = g.audio._streams.get(_sounds["rg_wind_loop"]["file"])
		if not (st is AudioStreamWAV):
			return
		var ls: AudioStreamWAV = (st as AudioStreamWAV).duplicate()
		ls.loop_mode = AudioStreamWAV.LOOP_FORWARD
		ls.loop_begin = 0
		ls.loop_end = ls.data.size() / 2
		_wind = AudioStreamPlayer.new()
		_wind.bus = "Beds"
		_wind.stream = ls
		_wind.volume_db = -80.0
		g.audio.add_child(_wind)
	var ex: Vector2i = trek.exit_cell
	var d: float = Vector2(ex.x + 0.5, ex.y + 0.5).distance_to(Vector2(g.player.x, g.player.y))
	var lin: float = clampf(1.0 - d / 16.0, 0.0, 1.0) * float(_sounds["rg_wind_loop"]["gain"]) * g.audio.volume * g.ambience_gain
	if lin <= 0.002:
		_wind.stream_paused = true
		return
	_wind.stream_paused = false
	if not _wind.playing:
		_wind.play()
	_wind.volume_db = linear_to_db(lin)


static func _rkey(cell: Variant) -> String:
	return "%d,%d" % [int(cell[0]), int(cell[1])]


## A rest spot is known when it is the coffin nook or the player has been within REST_DISCOVER cells of it.
func rest_is_known(r: Dictionary) -> bool:
	return String(r.get("kind", "")) == "coffin" or rest_known.has(_rkey(r["cell"]))


## Rest spots the player knows about (what TrekUi / the flow may list or show). Unknown ones stay hidden until found.
func known_rests() -> Array:
	var out: Array = []
	if trek == null:
		return out
	for r in trek.def.get("rest", []):
		if rest_is_known(r):
			out.append(r)
	return out


func _note_rest(pp: Vector2) -> void:
	for r in trek.def.get("rest", []):
		if rest_is_known(r):
			continue
		if Vector2(float(r["cell"][0]) + 0.5, float(r["cell"][1]) + 0.5).distance_to(pp) <= REST_DISCOVER:
			rest_known[_rkey(r["cell"])] = true
			g.audio.play("chime", {"gain": float(SoundData.level("chime")["gain"]) * 0.4, "pan": 0.0})
	var near: Variant = _rest_near(pp, REST_NOTE)
	if near != null:
		trek.note_rest(Vector2i(int(near["cell"][0]), int(near["cell"][1])))


## Dawn hum: while the dawn warning is on, each non-coffin rest spot (known or not) breathes a faint, short `rest_hum` pulse about every
## 3 s, so a listening player can find cover by ear. Shares the ambient budget: at most one hum live, none when ambient is full.
## Returns the number of pulses emitted.
func step_rest_hum(pp: Vector2) -> int:
	if trek == null or not trek.dawn_warning():
		_hum_next.clear()
		return 0
	if _hum_live != null and (g.clock - _hum_live.t0 > _hum_live.range / _hum_live.speed + _hum_live.fade or not g.sonar.pulses.has(_hum_live)):
		_hum_live = null
	if _hum_live != null or (ambient != null and ambient.live_count(g.sonar) >= Ambient.MAX_LIVE):
		return 0
	for r in trek.def.get("rest", []):
		if String(r.get("kind", "")) == "coffin":
			continue
		var k := _rkey(r["cell"])
		var x: float = float(r["cell"][0]) + 0.5
		var y: float = float(r["cell"][1]) + 0.5
		if not _hum_next.has(k):
			_hum_next[k] = g.clock   # the first hum is immediate, the others follow in turn
		if g.clock < float(_hum_next[k]):
			continue
		_hum_next[k] = g.clock + REST_HUM_PERIOD
		if Vector2(x, y).distance_to(pp) > REST_HUM_WITHIN:
			continue
		var p: Sonar.Pulse = g.sonar.emit_sound(g.world, x, y, g.clock, {
			"kind": "rest_hum", "range": REST_HUM_RANGE, "strength": REST_HUM_STRENGTH, "z": 0.0, "fade": 1.6,
			"visRays": REST_HUM_RAYS, "bounces": 0})
		if p != null:
			_hum_live = p
			hum_count += 1
			return 1
	return 0


## The level Hunger compares each power's unlock to. Classic: the night counter. Trek: everything is usable from the first dusk on
## (night 2+, any Heat, or a cleared stage), and Mist-born (TrekMeta effect mistBorn) unlocks Mist and Still from stage 1.
## Shriek (unlock 1) is always available.
func power_level() -> float:
	if trek == null:
		return float(g.night.night) if g.night != null else 1.0
	if float(trek.fx.get("mistBorn", 0.0)) >= 1.0 or trek.night.night >= 2 or trek.heat >= 1 or not trek.cleared.is_empty():
		return float(POWER_LEVEL_ALL)
	return float(trek.night.night)


func _step_hints(pp: Vector2) -> void:
	for b in trek.def.get("beats", []):
		var id: String = String(b["id"])
		if BEAT_HINTS.has(id) and Vector2(float(b["cell"][0]) + 0.5, float(b["cell"][1]) + 0.5).distance_to(pp) < 4.0:
			g.tut.queue(String(BEAT_HINTS[id]))
	if critters != null and critters.nearest_feedable(pp.x, pp.y, 5.0) != null:
		g.tut.queue("prey")


# hunters ---------------------------------------------------------------

func _clear_hunters() -> void:
	for id in hunter_ids:
		g.people.despawn(int(id))
	hunter_ids.clear()


## One "hunter" villager per Heat-driven hunter wanted, far from the player along the walkable graph.
func _spawn_hunters() -> void:
	_clear_hunters()
	var n: int = trek.hunters_wanted()
	if n <= 0:
		return
	var field := RunFlow.bfs_cells(g.world, floori(g.player.x), floori(g.player.y))
	var pool: Array = []
	var far_i := -1
	var far_d := -1
	for i in field.size():
		var d: int = field[i]
		if d < 0:
			continue
		if d >= HUNTER_MIN_BFS and d <= HUNTER_MAX_BFS:
			pool.append(i)
		if d > far_d:
			far_d = d
			far_i = i
	for k in n:
		var idx: int = int(pool[int(_rng_h.next() * pool.size())]) if not pool.is_empty() else far_i
		if idx < 0:
			break
		var cx: int = idx % g.world.width
		var cy: int = idx / g.world.width
		var r: Dictionary = g.people.spawn(g.world, {"archetype": "hunter", "seed": float(trek.seed + trek.heat * 31 + k * 977 + 5)}, {"x": cx + 0.5, "y": cy + 0.5})
		if r.get("ok", false):
			var p := g.people.find_person(int(r["id"]))
			p.sched = null
			p.feedable = false
			p.speed = HUNTER_SPEED
			hunter_ids.append(int(r["id"]))


func _hunter_list() -> Array:
	var out: Array = []
	for id in hunter_ids:
		var p := g.people.find_person(int(id))
		if p != null and p.mode != "fed":
			out.append({"x": p.x, "y": p.y, "noticing": not HUNTER_BUSY.has(p.mode)})
	return out


## Hunters walk the shortest way to the player (a distance field refreshed 2.5 times a second) at HUNTER_SPEED.
func _step_hunters(dt: float) -> void:
	if hunter_ids.is_empty():
		return
	_hfield_t += dt
	var pcx: int = floori(g.player.x)
	var pcy: int = floori(g.player.y)
	if _hfield_t >= HUNTER_FIELD_SEC or _hfield.is_empty():
		_hfield_t = 0.0
		_hfield = RunFlow.bfs_cells(g.world, pcx, pcy)
	var w: int = g.world.width
	for id in hunter_ids:
		var p := g.people.find_person(int(id))
		if p == null or HUNTER_BUSY.has(p.mode):
			continue   # dazed / fleeing / shrieked hunters keep the mode People gave them
		if p.mode != "path":   # a startle or cower at the sight of the player does not stop the hunt
			p.mode = "path"
			p.mode_left = 0.0
			p.wary = 0.0
			p.bumping = false
		var cx: int = clampi(floori(p.x), 0, w - 1)
		var cy: int = clampi(floori(p.y), 0, g.world.height - 1)
		var here: int = _hfield[cy * w + cx]
		var tx: float = g.player.x
		var ty: float = g.player.y
		if here > 1:
			var best: int = here
			for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx: int = cx + o.x
				var ny: int = cy + o.y
				if nx < 0 or ny < 0 or nx >= w or ny >= g.world.height:
					continue
				var dn: int = _hfield[ny * w + nx]
				if dn >= 0 and dn < best:
					best = dn
					tx = nx + 0.5
					ty = ny + 0.5
		var dx: float = tx - p.x
		var dy: float = ty - p.y
		var dist: float = sqrt(dx * dx + dy * dy)
		if dist > 0.05:
			g.people.walk_toward(p, dx, dy, dist, minf(dist, HUNTER_SPEED * dt), 0.2)
		p.state = "walk"
		p.path = [{"x": p.x, "y": p.y, "wait": 0.0}]
		p.idx = 0
		p.idle_left = 0.0


# ---------------------------------------------------------------- audio

## Register the baked rogue sounds with the AudioDirector (its manifest and stream cache) so g.audio.play("rg_...") works with pan,
## distance and occlusion. Loops are built by the caller like AudioDirector._loop_stream.
func _init_audio() -> void:
	if _audio_ready:
		return
	_audio_ready = true
	var f := FileAccess.open(SOUNDS_PATH, FileAccess.READ)
	if f == null:
		return
	var m: Variant = JSON.parse_string(f.get_as_text())
	if not (m is Dictionary):
		return
	var dir := String(m.get("dir", "res://audio/rogue/"))
	var man: Dictionary = g.audio._manifest
	if not man.has("entries"):
		man["entries"] = {}
	for s in m.get("sounds", []):
		var path: String = dir + String(s["file"])
		if not ResourceLoader.exists(path):
			continue
		var st: Resource = load(path)
		if st == null:
			continue
		g.audio._streams[String(s["file"])] = st
		man["entries"]["play:" + String(s["id"])] = [{"file": String(s["file"]), "ref": 1.0, "scale": 1.0}]
		_sounds[String(s["id"])] = s


## Play a baked rogue sound at a world position (NAN = flat), with the manifest's suggested gain times `mul`.
func sfx(id: String, x: float = NAN, y: float = NAN, mul: float = 1.0) -> bool:
	_init_audio()
	var s: Variant = _sounds.get(id)
	if s == null:
		return false
	var gain: float = float(s["gain"]) * mul
	var opts: Dictionary = {"gain": gain, "pan": 0.0} if is_nan(x) else g.spatial(x, y, gain)
	return g.audio.play(id, opts)


func _recapture() -> void:
	if g.scenario == null and g.state == "playing" and not prompt_open and not waiting:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
