class_name Tutorial
extends RefCounted
## First-time hints (js game.js tutQueue / tutStart / stepTutorial): one hint at a time under the HUD, each shown once ever
## (the seen list persists in user://seen.json, as the JS keeps it in localStorage "vcs.seen").

const TEXT := {
	"ping": "Click or Space to listen",
	"person": "Echoes that move are people — hold right-click close to drink",
	"vial": "Vial = blood. Drink past full for gifts",
	"fear": "Eyes by the clock = fear",
	"sleep": "E at the crypt or a dark spot to sleep",
	"light": "Eye = light on you. Stay dark to stay unseen",
	"listen": "Hold E facing a lit window to listen",
}
const SEEN_PATH := "user://seen.json"

var g: Game
var seen: Dictionary = {}
var queued: Dictionary = {}
var q: Array = []
var cur: Variant = null
var age: float = 0.0
var persist: bool = true


func _init(game: Game, do_persist: bool = true) -> void:
	g = game
	persist = do_persist
	if persist:
		var f := FileAccess.open(SEEN_PATH, FileAccess.READ)
		if f != null:
			var v: Variant = JSON.parse_string(f.get_as_text())
			if v is Array:
				for i in mini(v.size(), 40):
					if v[i] is String and (v[i] as String).begins_with("tut:"):
						seen[(v[i] as String).substr(4)] = true


func _save() -> void:
	if not persist:
		return
	var list: Array = []
	for k in seen:
		list.append("tut:" + k)
	var f := FileAccess.open(SEEN_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(list))


## Queue a first-time hint (once ever, once per session).
func queue(id: String) -> void:
	if not g.run_on:
		return
	if seen.get(id) == true or queued.get(id) == true:
		return
	queued[id] = true
	q.append({"id": id, "text": TEXT[id], "dur": 60.0 if id == "ping" else 5.0})


func mark(id: String) -> void:
	seen[id] = true
	_save()


func clear() -> void:
	q.clear()
	cur = null
	age = 0.0


## New run or continued run: reset the session flags and queue the first hint.
func start() -> void:
	clear()
	queued = {}
	queue("ping")


## The first pulse retires the "Click or Space" hint for good.
func pulsed() -> void:
	ping_n += 1
	if seen.get("ping") == true:
		return
	mark("ping")
	if cur != null and cur["id"] == "ping":
		cur = null
	q = q.filter(func(h): return h["id"] != "ping")


## Per frame: trigger conditions, then show one hint at a time when no card is up.
func step(dt: float) -> void:
	if rogue_active:
		if g.rogue_on():
			_rogue_step(dt)
			return
		rogue_active = false   # the trek stopped (title, classic): the guided hints rest until the next start
	var n: Night = g.night
	if n != null:
		if n.blood < 50.0:
			queue("vial")
		if g.hunger != null and g.hunger.fear > 0.0:
			queue("fear")
		if g.veil_k > 0.5:
			queue("light")
		if g.world != null and Listen.near_lit_window(g.world, {"x": g.player.x, "y": g.player.y}, 2.5):
			queue("listen")
		if n.night == 1 and n.min >= 510.0 and not g.rogue_on():
			queue("sleep")
	if g.card_text != "" or g.unlock_hint_t > 0.0:
		g.hint_text = ""
		return
	if cur != null:
		age += dt
		if age > float(cur["dur"]):
			cur = null
	elif not q.is_empty() and g.state == "playing":
		cur = q.pop_front()
		age = 0.0
		if cur["id"] != "ping":
			mark(cur["id"])
	if cur != null:
		g.hint_text = cur["text"]
		g.hint_age = age
		g.hint_dur = float(cur["dur"])
	else:
		g.hint_text = ""


# ---------------------------------------------------------------- The Long Night: the guided first night (docs/ROGUELIKE.md "Tutorial")
## A sequence of short prompts under the HUD in the Hollow. Each step waits for the player to DO the thing (or reach the beat) and then
## the next one shows; nothing here ever blocks movement or touches the sim: it only reads RogueMode / TrekFlow state and writes
## hint_text. Runs on the first Long Night run only (rogue meta `tutorialDone` false); skippable with Tab; the Settings toggle turns it
## back on. It is a no-op outside a trek (classic Five Nights keeps the legacy hints above).

const SKIP_KEY := KEY_TAB
const SKIP_SUFFIX := "  [Tab: skip]"
## Beat ids in the order the generator lays them along the main path (rank = index). dead_end_spurs is off the path.
const BEAT_RANK := ["coffin_nook", "drip_gallery", "squeeze", "echo_hall", "still_pool", "rat_warren", "cave_mouth"]
const BEAT_NEAR := 4.5
const MAX_TEXT := 76
## id, text (at most MAX_TEXT characters: the HUD hint is one line of 90 with the skip suffix), `timed` = seconds shown (the whole step),
## `min` = least seconds before the gate may complete it. "interrupt" steps jump the queue when their moment comes.
const ROGUE_STEPS := [
	{"id": "wake", "text": "You rise. You cannot see. Listen.", "min": 2.5},
	{"id": "ping", "text": "Press Space to ping. Listen to what comes back.", "min": 0.0},
	{"id": "rings", "text": "Each ring is a wall. A long echo means a big room.", "timed": 5.5},
	{"id": "drips", "text": "Drips sing on their own, no ping needed. Follow them.", "min": 0.0},
	{"id": "squeeze", "text": "A squeeze. Ping to steer: short echoes mean close walls.", "min": 0.0},
	{"id": "hall", "text": "That huge echo is the hall. Bats roost here, and bats are food.", "timed": 5.5},
	{"id": "feed", "text": "Creep close, ping to freeze it, R to lunge and drink.", "min": 0.0},
	{"id": "vial", "text": "That is blood. The vial drains all night; empty, you wither.", "timed": 6.5},
	{"id": "pool", "text": "Pools ahead: water blocks your feet, not sound. Ping across.", "min": 0.0},
	{"id": "dead_end", "text": "A dead end rings short and bright. Some hide a place to rest.", "timed": 6.0},
	{"id": "mouth", "text": "Outside, the sun can find you. Roofs are safe; open sky is not.", "timed": 7.0},
	{"id": "powers", "text": "Q shrieks. Mist (Shift) and Still (F) wake at your first dusk.", "timed": 6.0},
	{"id": "dawn", "text": "Dawn nears. Any roof keeps the sun off. Rest spots hum: listen.", "interrupt": true, "min": 0.0},
	{"id": "choice", "text": "Sun is up. E at a rest spot sleeps; 1 waits here. Both add Heat.", "interrupt": true, "min": 9.0},
]

var rogue_active: bool = false
var rogue_done: Dictionary = {}     ## step id -> true
var rogue_cur: String = ""
var rogue_age: float = 0.0
var ping_n: int = 0                 ## player pings since boot (the gates compare against the count when a step began)
var _base: Dictionary = {}          ## step id -> {ping, drip} counters when the step began
var _fed0: int = 0                  ## RogueMode.stats critters_fed when the guided night began
var _rank: int = -1                 ## furthest main-path beat reached in the Hollow
var _field: PackedInt32Array = PackedInt32Array()
var _field_world: Variant = null
var _beat_cells: Dictionary = {}    ## beat id -> Vector2 (cell centre)
var _beat_depth: Dictionary = {}    ## beat id -> BFS depth from the start


## RogueMode._start: begin (or resume) the guided night when the rogue meta says the tutorial is still on. fresh = a new run;
## a continued one resumes by the beats it has already reached (steps behind the player are skipped).
func rogue_begin(fresh: bool) -> void:
	rogue_stop()
	if g.menus == null or not g.menus.tutorial_enabled() or not g.rogue_on():
		return
	rogue_active = true
	rogue_done = {}
	rogue_cur = ""
	rogue_age = 0.0
	_base = {}
	_rank = -1
	_field_world = null
	_fed0 = int(g.rogue.stats["critters_fed"])
	if not fresh:
		rogue_done["wake"] = true
		rogue_done["ping"] = true
		rogue_done["rings"] = true


## Stop showing the guided night without marking it done (the trek stopped; the Settings toggle was turned off).
func rogue_stop() -> void:
	if rogue_active and rogue_cur != "":
		g.hint_text = ""
	rogue_active = false
	rogue_cur = ""


## The tutorial is finished (all steps, Tab, or the run ended): stop and remember it in the rogue save.
func rogue_finish() -> void:
	rogue_stop()
	if g.menus != null:
		g.menus.set_tutorial_enabled(false)


func rogue_skip() -> void:
	rogue_finish()


func step_def(id: String) -> Dictionary:
	for s in ROGUE_STEPS:
		if s["id"] == id:
			return s
	return {}


func _drips() -> int:
	return int(g.rogue.stats["drips"])


func _fed_run() -> int:
	return int(g.rogue.stats["critters_fed"]) - _fed0


## Furthest main-path beat the player has reached (a cell within BEAT_NEAR of it, or farther along the BFS from the start).
func _update_rank(pp: Vector2) -> void:
	var tr: TrekFlow = g.rogue.trek
	if g.map_name != "hollow" or tr == null:
		_rank = BEAT_RANK.size()   # past the Hollow: every cave step is behind us
		return
	if _field_world != g.world:
		_field_world = g.world
		var sc: Array = tr.def["start"]["cell"]
		_field = RunFlow.bfs_cells(g.world, int(sc[0]), int(sc[1]))
		_beat_cells.clear()
		_beat_depth.clear()
		for b in tr.def.get("beats", []):
			_beat_cells[String(b["id"])] = Vector2(float(b["cell"][0]) + 0.5, float(b["cell"][1]) + 0.5)
			var i: int = int(b["cell"][1]) * g.world.width + int(b["cell"][0])
			_beat_depth[String(b["id"])] = int(_field[i]) if i >= 0 and i < _field.size() else 1000000
	var cx: int = floori(pp.x)
	var cy: int = floori(pp.y)
	var depth := -1
	if cx >= 0 and cy >= 0 and cx < g.world.width and cy < g.world.height:
		depth = int(_field[cy * g.world.width + cx])
	for r in BEAT_RANK.size():
		if r <= _rank or not _beat_cells.has(BEAT_RANK[r]):
			continue
		var id: String = BEAT_RANK[r]
		if (_beat_cells[id] as Vector2).distance_to(pp) <= BEAT_NEAR or (depth >= 0 and depth >= int(_beat_depth[id]) - 1):
			_rank = r


func _near_beat(id: String, pp: Vector2, radius: float) -> bool:
	return _beat_cells.has(id) and (_beat_cells[id] as Vector2).distance_to(pp) <= radius


## At a dead end: within reach of the spur beat or of a spur rest spot.
func _at_dead_end(pp: Vector2) -> bool:
	if _near_beat("dead_end_spurs", pp, BEAT_NEAR):
		return true
	for r in g.rogue.trek.def.get("rest", []):
		if String(r.get("kind", "")) == "spur" and Vector2(float(r["cell"][0]) + 0.5, float(r["cell"][1]) + 0.5).distance_to(pp) <= BEAT_NEAR:
			return true
	return false


## True when the step has been overtaken by where the player has got to (resuming a checkpoint, running ahead).
func _past(id: String) -> bool:
	match id:
		"drips": return _rank >= 1
		"squeeze": return _rank >= 3
		"hall": return _rank >= 4
		"feed": return _rank >= 4 or _fed_run() > 0
		"vial": return _fed_run() == 0
		"pool": return _rank >= 5
		"dead_end": return _rank >= 6
		"mouth", "powers": return _rank >= BEAT_RANK.size()
	return false


## Whether a pending step may show yet.
func _trigger(id: String, pp: Vector2) -> bool:
	match id:
		"hall": return _rank >= 3
		"dead_end": return _at_dead_end(pp)
		"mouth": return _rank >= 6
		"dawn": return g.rogue.trek.dawn_warning()
		"choice": return g.rogue.trek.needs_choice()
	return true


## Whether the shown step has been done (checked once its minimum on-screen time has passed).
func _gate(id: String, pp: Vector2) -> bool:
	var base: Dictionary = _base.get(id, {"ping": ping_n, "drip": _drips()})
	match id:
		"wake": return _drips() > int(base["drip"])
		"ping": return ping_n > int(base["ping"])
		"drips": return _rank >= 1
		"squeeze": return _rank >= 3 or (ping_n > int(base["ping"]) and _near_beat("squeeze", pp, 7.0))
		"feed": return _fed_run() > 0
		"pool": return _rank >= 5 or (ping_n > int(base["ping"]) and _near_beat("still_pool", pp, 8.0))
		"dawn": return g.rogue.trek.night.status != "night"
		"choice": return not g.rogue.trek.needs_choice() or not g.rogue.prompt_open
	return true   # timed steps: the time is the whole step


func _next_step(pp: Vector2) -> String:
	for s in ROGUE_STEPS:
		var id: String = s["id"]
		if bool(s.get("interrupt", false)) and not rogue_done.has(id) and _trigger(id, pp):
			return id
	for s in ROGUE_STEPS:
		var id: String = s["id"]
		if rogue_done.has(id) or bool(s.get("interrupt", false)):
			continue
		if _past(id):
			rogue_done[id] = true
			continue
		return id if _trigger(id, pp) else ""
	return ""


func _step_secs(def: Dictionary) -> float:
	return float(def.get("timed", def.get("min", 0.0)))


func _rogue_step(dt: float) -> void:
	if g.pressed.has(SKIP_KEY):
		rogue_skip()
		return
	var pp := Vector2(g.player.x, g.player.y)
	_update_rank(pp)
	if rogue_cur != "":
		var def := step_def(rogue_cur)
		rogue_age += dt
		if rogue_age >= _step_secs(def) and (_gate(rogue_cur, pp) or (_past(rogue_cur) and not bool(def.get("interrupt", false)))):
			rogue_done[rogue_cur] = true
			rogue_cur = ""
	var nxt := _next_step(pp)
	if nxt != "" and nxt != rogue_cur:
		var preempt: bool = rogue_cur != "" and bool(step_def(nxt).get("interrupt", false)) and not bool(step_def(rogue_cur).get("interrupt", false))
		if rogue_cur == "" or preempt:
			rogue_cur = nxt
			rogue_age = 0.0
			_base[nxt] = {"ping": ping_n, "drip": _drips()}
	if rogue_cur == "":
		var all_done := true
		for s in ROGUE_STEPS:
			if not rogue_done.has(s["id"]):
				all_done = false
				break
		if all_done:
			rogue_finish()
			return
	if g.card_text != "" or g.unlock_hint_t > 0.0 or rogue_cur == "":
		g.hint_text = ""
		return
	g.hint_text = String(step_def(rogue_cur)["text"]) + SKIP_SUFFIX
	g.hint_age = minf(rogue_age, 4.0)   # faded in and never fading out while the step stands
	g.hint_dur = 60.0
