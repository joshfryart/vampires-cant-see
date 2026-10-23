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
	# The Long Night, cave (shown by RogueMode)
	"drip": "Something drips. Listen.",
	"squeeze": "Ping to steer in the squeeze.",
	"dead_end": "A dead end rings short and bright.",
	"prey": "Bats and rats are food. Hold R close to drink.",
	"sun": "Outside, the sun can find you.",
	"dawn": "Dawn: find cover, or wait it out.",
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
	if seen.get("ping") == true:
		return
	mark("ping")
	if cur != null and cur["id"] == "ping":
		cur = null
	q = q.filter(func(h): return h["id"] != "ping")


## Per frame: trigger conditions, then show one hint at a time when no card is up.
func step(dt: float) -> void:
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
