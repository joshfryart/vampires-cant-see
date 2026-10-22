class_name RunFlow
extends RefCounted
## Runs, nights, boons, gifts, sleep, saves: the flow code of js/game.js (beginRun, endRun, enterBoon, pickBoon, enterGift,
## pickGift, nextNight, trySleep, stepSeq, stepNight, getSnapshot, applySnapshot, saveRun, continueRun).
## The Game node owns the live state (night, hunger, run); this object owns the meta save, the store and the flow.

const DEFAULT_FX := {"sonarRange": 1.0, "sonarFade": 1.0, "sonarCooldown": 1.0, "startBlood": 0.0, "drain": 1.0, "drinkRate": 1.0, "noise": 1.0, "nightLen": 1.0, "warmRadius": 0.0}
const DRAIN_BASE := 1.3
const SLEEP_DUR := 2.2
const SLEEP_MIN := 510.0
const NIGHT_LENGTH_MIN := 4.0
const AUTOSAVE_SEC := 20.0

var g: Game
var store: SaveCodec.Store
var meta: Dictionary = {}
var run: Variant = null            # {seed, boons, closedSafe, pendingBoons, pendingGifts}
var fx: Dictionary = DEFAULT_FX.duplicate()
var seq: Variant = null            # sleep sequence {type, t, dur, did}
var far_spot: Variant = null       # {map, cx, cy, d}
var run_kind: String = ""
var run_result: Dictionary = {}    # last end_run summary for the run-end panel
var notices: Array = []
var crypt_warn_until: float = 0.0
var auto_acc: float = 0.0
var seed_param: Variant = null     # fixed run seed (tests, --seed=)
var save_failed: bool = false
var has_run: bool = false
var night_length_min: float = NIGHT_LENGTH_MIN
var autosave_sec: float = AUTOSAVE_SEC


func _init(game: Game, storage: Object = null) -> void:
	g = game
	store = SaveCodec.create(storage if storage != null else SaveCodec.FileStorage.new("user://"))
	meta = Meta.create()
	if not store.persistent:
		notices.append("Saving is unavailable. Progress will not be kept.")
	var r := store.read("meta")
	if r["ok"]:
		var m := Meta.migrate(r["v"], r["data"])
		var san: Variant = Meta.sanitize(m["data"]) if m["ok"] else null
		if san != null:
			meta = san
			if r["source"] == "bak" and r["code"] != "" and r["code"] != "E_SAVE_NONE":
				notices.append("Meta save was damaged, restored backup.")
		else:
			notices.append("Meta save was damaged (%s). Started fresh." % ("E_SAVE_SCHEMA" if m["ok"] else m["code"]))
	elif r["code"] != "E_SAVE_NONE":
		notices.append("Meta save was damaged (%s). Started fresh." % r["code"])
	has_run = store.has("run")
	fx = compute_fx()


# ---------------------------------------------------------------- effects

func fxv(k: String) -> float:
	var v: Variant = fx.get(k)
	return float(v) if (v is float or v is int) and is_finite(float(v)) else float(DEFAULT_FX[k])


func compute_fx() -> Dictionary:
	var boons: Array = run["boons"] if run != null else []
	var extra: Array = g.hunger.gift_mods() if g.hunger != null else []
	var f: Dictionary = Meta.effects(meta, boons, extra)
	return f if not f.is_empty() else DEFAULT_FX.duplicate()


## Recompute effects and push them into the sonar.
func apply_fx() -> void:
	fx = compute_fx()
	g.apply_room()


func new_night_state() -> Night:
	var m: float = night_length_min
	return Night.create({"nightSec": m * 60.0 * fxv("nightLen"), "bloodStart": minf(100.0, 10.0 + fxv("startBlood")), "drainMul": fxv("drain") * DRAIN_BASE, "ramp": hunger_ramp()})


# ---------------------------------------------------------------- safe spots

static func hunger_ramp() -> float:
	return float(GameData.get_json("hunger").get("RAMP", 0.0))


static func _mulberry(seed_v: int) -> Rng:
	return Rng.new(float(seed_v & JsMath.M32))


## Pick floor(n/3) safe spots per map to seal for this run. Crypt beds never close.
func close_safe_spots(seed_v: int) -> Dictionary:
	var out := {}
	for idx in g.world_names.size():
		var name: String = g.world_names[idx]
		var spots: Array = g.worlds[name].spots.get("safe", [])
		if spots.size() < 2:
			continue
		var k: int = mini(16, spots.size() / 3)
		if k < 1:
			continue
		var rng := _mulberry(Game.mix_seed(seed_v, idx, 7))
		var order: Array = []
		for i in spots.size():
			order.append(i)
		for i in k:
			var j: int = i + int(floor(rng.next() * float(order.size() - i)))
			var t: int = order[i]
			order[i] = order[j]
			order[j] = t
		var cells: Array = []
		for i in k:
			cells.append([int(floor(spots[order[i]].x)), int(floor(spots[order[i]].y))])
		out[name] = cells
	return out


func is_sealed_in(name: String, sp: Variant) -> bool:
	if run == null:
		return false
	var cs: Dictionary = run["closedSafe"]
	if not cs.has(name):
		return false
	var cx: int = int(floor(sp.x))
	var cy: int = int(floor(sp.y))
	for c in cs[name]:
		if int(c[0]) == cx and int(c[1]) == cy:
			return true
	return false


func is_sealed(sp: Variant) -> bool:
	return is_sealed_in(g.map_name, sp)


## Breadth-first walking distances (cells) from (sx, sy); -1 where unreachable. Doors count as open.
static func bfs_cells(w: World, sx: int, sy: int) -> PackedInt32Array:
	var n: int = w.width * w.height
	var dist := PackedInt32Array()
	dist.resize(n)
	dist.fill(-1)
	if not (sx >= 0 and sy >= 0 and sx < w.width and sy < w.height):
		return dist
	var q := PackedInt32Array()
	q.resize(n)
	var head := 0
	var tail := 0
	dist[sy * w.width + sx] = 0
	q[tail] = sy * w.width + sx
	tail += 1
	var dxs := [1, -1, 0, 0]
	var dys := [0, 0, 1, -1]
	while head < tail:
		var cur: int = q[head]
		head += 1
		var cx: int = cur % w.width
		var cy: int = cur / w.width
		for k in 4:
			var nx: int = cx + dxs[k]
			var ny: int = cy + dys[k]
			if nx < 0 or ny < 0 or nx >= w.width or ny >= w.height:
				continue
			var ni: int = ny * w.width + nx
			if dist[ni] >= 0:
				continue
			var ch := w.tile_at(nx + 0.5, ny + 0.5)
			if w.is_solid(nx + 0.5, ny + 0.5) and ch != "D" and ch != "G":
				continue
			dist[ni] = dist[cur] + 1
			q[tail] = ni
			tail += 1
	return dist


## Farthest open safe spot (walking distance from the crypt door) in the map that links to the crypt.
func compute_far_spot() -> void:
	far_spot = null
	for n in g.world_names.size():
		if far_spot != null:
			break
		var name: String = g.world_names[n]
		var w: World = g.worlds[name]
		if w.doors_by_id.is_empty() or w.spots.get("crypt", []).size() > 0:
			continue
		var door: Variant = null
		for id in w.doors_by_id:
			var d: Dictionary = w.doors_by_id[id]
			var tw: World = g.worlds.get(d["toMap"])
			if door == null and tw != null and tw.spots.get("crypt", []).size() > 0:
				door = d
		var safe: Array = w.spots.get("safe", [])
		if door == null or safe.is_empty():
			continue
		var a: Variant = w.arrival(door["id"])
		if a == null:
			continue
		var dist := bfs_cells(w, int(floor(a["x"])), int(floor(a["y"])))
		var best: Variant = null
		for sp in safe:
			if is_sealed_in(name, sp):
				continue
			var cx: int = int(floor(sp.x))
			var cy: int = int(floor(sp.y))
			var d2: int = dist[cy * w.width + cx]
			if d2 >= 0 and (best == null or d2 > best["d"]):
				best = {"map": name, "cx": cx, "cy": cy, "d": d2}
		far_spot = best


func is_far_spot(sp: Variant) -> bool:
	return far_spot != null and far_spot["map"] == g.map_name and int(floor(sp.x)) == far_spot["cx"] and int(floor(sp.y)) == far_spot["cy"]


func award_far_spot() -> void:
	if g.hunger == null:
		return
	g.hunger.essence_bonus = minf(1000.0, g.hunger.essence_bonus + 5.0)
	g.show_card("+5 Essence", 0.2, "A far, dark corner of town.")


# ---------------------------------------------------------------- runs

func reset_world_doors() -> void:
	for name in g.world_names:
		var w: World = g.worlds[name]
		for y in w.height:
			for x in w.width:
				var ch := w.tile_at(x + 0.5, y + 0.5)
				if (ch == "D" or ch == "G") and w.is_door_open(x, y):
					w.set_door(x, y, false)


func reset_world_for_run() -> void:
	reset_world_doors()
	g.seed_base = 0
	g.people_by_map.clear()
	seq = null
	g.drink = null
	g.transition = null
	g.wipe_k = 0.0
	g.card_text = ""
	g.powers.reset_run()
	g.over_acc = 0.0
	g.end_listen()
	g.barks_reset()


## Begin a brand new run (from the menu or the run-end panel). True if it started.
func begin_run() -> bool:
	if g.state != "title" and g.state != "runend" and g.state != "free":
		return false
	var seed_v: int = int(seed_param) if seed_param != null else (randi() & JsMath.M32)
	run = {"seed": seed_v, "boons": [], "closedSafe": {}, "pendingBoons": null, "pendingGifts": null}
	g.hunger = Hunger.create()
	fx = compute_fx()
	reset_world_for_run()
	run["closedSafe"] = close_safe_spots(seed_v)
	compute_far_spot()
	g.night = new_night_state()
	var w: String = String(GameData.maps()["startMap"]) if g.worlds.has(String(GameData.maps()["startMap"])) else String(g.world_names[0])
	var a := g.start_place(g.worlds[w])
	g.enter_map(w, a["x"], a["y"], a["angle"], "")
	apply_fx()
	g.run_on = true
	auto_acc = 0.0
	g.init_ambient()
	g.tut.start()
	g.set_state("playing")
	g.show_card("Night 1")
	save_run("new run")
	return true


## End the run: "lost" (sun) or "won" (all nights survived). Records meta stats and clears the saved run.
func end_run(kind: String) -> void:
	if g.state == "runend":
		return
	g.end_drink("run")
	run_kind = kind
	seq = null
	var n: Night = g.night
	var survived: int = (n.nights if kind == "won" else maxi(0, n.night - 1)) if n != null else 0
	var fed: int = n.fed_count if n != null else 0
	var bonus: int = maxi(0, int(floor(g.hunger.essence_bonus))) if g.hunger != null and is_finite(g.hunger.essence_bonus) else 0
	var earned: int = Meta.record_run(meta, {"nights": survived, "fed": fed, "won": kind == "won", "bonus": bonus})
	save_meta()
	store.remove("run")
	has_run = false
	g.run_on = false
	if run != null:
		run["pendingBoons"] = null
		run["pendingGifts"] = null
	run_result = {
		"kind": kind, "survived": survived, "fed": fed, "earned": earned, "bonus": bonus,
		"title": "Five nights survived" if kind == "won" else "The sun found you",
		"message": "Nights survived: %d · People fed: %d" % [survived, fed],
		"essence": "Essence +%d%s" % [earned, " (bonus +%d)" % bonus if bonus > 0 else ""],
	}
	g.set_state("runend")


func new_run_from_runend() -> bool:
	return begin_run()


# ---------------------------------------------------------------- night clock

## Advance the night clock; handles its events. True if the run ended.
func step_night(dt: float) -> bool:
	var n: Night = g.night
	if n == null:
		return false
	var ev: Array = n.update(dt, {"outdoor": g.world.kind_at(g.player.x, g.player.y) == "outdoor"})
	if ev.is_empty():
		return false
	var lost := false
	for e in ev:
		if e == "chime":
			g.audio.play("chime", {"gain": SoundData.level("chime")["gain"], "pan": 0.0})
			g.show_card("Dawn")
		elif e == "washout":
			forge_washout()
		elif e == "lost":
			lost = true
	if lost:
		end_run("lost")
		return true
	return false


## Fear walks in reinforcements; at fear 8 the watch lifts lanterns (look only, no light).
func step_forge(dt: float) -> void:
	var st: People = g.people
	if st == null or g.night == null or g.hunger == null or (g.state != "playing" and g.state != "feeding"):
		return
	var md: Dictionary = GameData.map_def(g.map_name)
	var rf: Variant = md.get("reinforce")
	if not (rf is Dictionary) or not (rf.get("at") is Array):
		return
	st.forge_in -= dt
	if st.forge_in > 0.0:
		return
	st.forge_in = 1.0
	var fear: float = g.hunger.fear
	var hit: Variant = Forge.reinforcement({"fear": fear, "night": g.night.night, "runSeed": run["seed"] if run != null else 1, "fired": st.forge_fired})
	if hit != null:
		var x: float = float(rf["at"][0]) + 0.5
		var y: float = float(rf["at"][1]) + 0.5
		var p: Player = g.player
		var far: bool = sqrt((p.x - x) * (p.x - x) + (p.y - y) * (p.y - y)) >= 10.0 or g.world.line_blocked(p.x, p.y, x, y)
		if far:
			var r: Dictionary = st.spawn(g.world, {"archetype": hit["archetype"], "seed": hit["seed"]}, {"x": x, "y": y})
			st.forge_fired += 1
			if r["ok"]:
				st.forge_reinf.append(r["id"])
				g.show_card(hit["card"])
				g.emit_sound("bell", x, y)
	if fear >= 8.0 and not st.forge_lantern:
		st.forge_lantern = true
		for q in st.people:
			if q.watch:
				st.alter(q.id, {"acc": "lantern"})


## At washout, reinforcements that are out of sight (walled off or over 10 cells away) and not busy leave.
func forge_washout() -> void:
	var st: People = g.people
	if st == null:
		return
	var keep: Array = []
	for id in st.forge_reinf:
		var q := st.find_person(int(id))
		if q == null:
			continue
		var gone: bool = g.world.line_blocked(g.player.x, g.player.y, q.x, q.y) or sqrt((g.player.x - q.x) * (g.player.x - q.x) + (g.player.y - q.y) * (g.player.y - q.y)) > 10.0
		if not gone or not st.despawn(int(id))["ok"]:
			keep.append(id)
	st.forge_reinf = keep


# ---------------------------------------------------------------- sleep

## Try to sleep at a crypt or safe spot in reach. True if the sequence started.
func try_sleep(force: bool = false) -> bool:
	if g.state != "playing" or g.night == null or g.world == null:
		return false
	var p: Player = g.player
	var reach: float = float(GameData.sounds()["reach"])
	var w: World = g.world
	if not force and g.night.min < SLEEP_MIN:
		var near := func(sp: Variant) -> bool: return sqrt((sp.x - p.x) * (sp.x - p.x) + (sp.y - p.y) * (sp.y - p.y)) <= reach
		var near_crypt := false
		for sp in w.spots.get("crypt", []):
			if near.call(sp):
				near_crypt = true
		var near_safe := false
		for sp in w.spots.get("safe", []):
			if near.call(sp):
				near_safe = true
		if near_crypt and g.clock < crypt_warn_until:
			crypt_warn_until = 0.0
		elif near_crypt or near_safe:
			if near_crypt:
				crypt_warn_until = g.clock + 4.0
				g.show_card("Sleep early?", Game.CARD_LEN - 1.0, "Each night grows harder. Press E again to sleep.")
			else:
				g.show_card("Not tired yet", Game.CARD_LEN - 1.0, "Wait until the night is nearly spent, or sleep in the crypt.")
			g.audio.play("miss", {"gain": SoundData.level("miss")["gain"], "pan": 0.0})
			return false
		else:
			return false
	var lists := [w.spots.get("crypt", []), w.spots.get("safe", [])]
	var sealed := false
	for a in 2:
		for sp in lists[a]:
			if sqrt((sp.x - p.x) * (sp.x - p.x) + (sp.y - p.y) * (sp.y - p.y)) <= reach:
				if a == 1 and is_sealed(sp):
					sealed = true
					continue
				if a == 1 and is_far_spot(sp):
					award_far_spot()
				start_seq("sleep", SLEEP_DUR)
				g.audio.play("yawn", {"gain": SoundData.level("yawn")["gain"], "pan": 0.0})
				return true
	if sealed:
		g.show_card("Sealed", Game.CARD_LEN - 1.0)
		g.audio.play("miss", {"gain": SoundData.level("miss")["gain"], "pan": 0.0})
	return false


func start_seq(type: String, dur: float) -> void:
	seq = {"type": type, "t": 0.0, "dur": dur, "did": false}
	g.set_state("sleeping")


## Advance the sleep sequence.
func step_seq(dt: float) -> void:
	if seq == null:
		g.set_state("playing")
		return
	var q: Dictionary = seq
	q["t"] = float(q["t"]) + dt
	if not q["did"] and float(q["t"]) >= 0.8:
		q["did"] = true
		var r: String = g.night.sleep()
		if r == "won":
			seq = null
			end_run("won")
			return
		if r == "next":
			seq = null
			enter_boon()
			return
	if float(q["t"]) >= float(q["dur"]):
		seq = null
		g.set_state("playing")


## Reset the world for a new night after sleeping.
func next_night() -> void:
	var n: int = g.night.night
	if g.hunger != null:
		var nb: float = g.hunger.on_sleep()
		g.hunger.still_left = 0.0
		g.powers.mist = null
		if nb > 0.0:
			g.night.add_blood(nb)
	g.seed_base = n * 100
	g.people_by_map.clear()
	g.people = g.people_for(g.map_name)
	g.sonar.reset()
	g.audio.stop_all(0.15)
	var up: Variant = unlocked_power(n)
	g.show_card("Night %d%s" % [n, unlock_text(n)], 0.0, str(up["how"]).strip_edges() if up != null and str(up["how"]).strip_edges() != "" else "")
	g.init_ambient()
	g.tut.clear()


## The power that unlocks on night n (n > 1), or null.
static func unlocked_power(n: int) -> Variant:
	for p in GameData.get_json("hunger")["powers"]:
		if int(p["unlock"]) == n and n > 1:
			return p
	return null


static func unlock_text(n: int) -> String:
	var keys := {"shriek": "Q", "still": "F"}
	for p in GameData.get_json("hunger")["powers"]:
		if int(p["unlock"]) == n and n > 1:
			return " — %s (%s)" % [p["name"], "Shift" if p["id"] == "mist" else keys.get(p["id"], "")]
	return ""


# ---------------------------------------------------------------- boons and gifts

## After sleeping: roll three boons and show the choice panel.
func enter_boon() -> void:
	var ids: Array = Meta.roll_boons(float(run["seed"] + g.night.night * 7919), run["boons"])
	if ids.is_empty():
		next_night()
		g.set_state("playing")
		return
	run["pendingBoons"] = ids
	g.set_state("boon")
	save_run("boon offered")


## Take boon number i (0..2): apply it and start the next night.
func pick_boon(i: int) -> bool:
	if g.state != "boon" or run == null or run["pendingBoons"] == null:
		return false
	var ids: Array = run["pendingBoons"]
	if i < 0 or i >= ids.size():
		return false
	var id: String = ids[i]
	var b: Variant = Meta.boon_by_id(id)
	run["boons"].append(id)
	run["pendingBoons"] = null
	if b != null and b.get("effect") == "bloodNow" and g.night != null:
		g.night.add_blood(float(b["value"]))
	apply_fx()
	if g.night != null:
		g.night.night_sec = night_length_min * 60.0 * fxv("nightLen")
		g.night.drain_mul = fxv("drain") * DRAIN_BASE
	next_night()
	g.set_state("playing")
	save_run("boon taken")
	return true


## Overflow is full: roll three small gifts and show the choice panel.
func enter_gift() -> void:
	if g.hunger == null or run == null or g.night == null:
		return
	var ids: Array = g.hunger.roll_gifts(float(run["seed"] + g.night.night * 131 + g.hunger.gifts.size()))
	if ids.is_empty():
		g.hunger.over = 0.0
		return
	run["pendingGifts"] = ids
	g.set_state("gift")
	save_run("gift offered")


## Take gift number i (0..2) and go back to the night.
func pick_gift(i: int) -> bool:
	if g.state != "gift" or run == null or run["pendingGifts"] == null or g.hunger == null:
		return false
	var ids: Array = run["pendingGifts"]
	if i < 0 or i >= ids.size():
		return false
	var id: String = ids[i]
	var r: Dictionary = g.hunger.take_gift(id)
	if not r["ok"]:
		return false
	run["pendingGifts"] = null
	g.over_acc = 0.0
	apply_fx()
	g.gift_flash = 1.0
	g.audio.play("gift", {"gain": SoundData.level("gift")["gain"], "pan": 0.0})
	g.set_state("playing")
	save_run("gift taken")
	return true


# ---------------------------------------------------------------- saves

func save_meta() -> bool:
	var r := store.write("meta", Meta.SCHEMA, meta)
	if not r["ok"]:
		save_failed = true
		return false
	return true


func run_is_active() -> bool:
	return g.run_on and g.night != null and g.world != null and ["playing", "paused", "transition", "feeding", "sleeping", "boon", "gift"].has(g.state)


## Serializable game state (v4).
func get_snapshot() -> Dictionary:
	var doors := {}
	var people := {}
	var forge := {}
	for name in g.world_names:
		var w: World = g.worlds[name]
		var open: Array = []
		for y in w.height:
			for x in w.width:
				var ch := w.tile_at(x + 0.5, y + 0.5)
				if (ch == "D" or ch == "G") and w.is_door_open(x, y):
					open.append([x, y])
		if not open.is_empty():
			doors[name] = open
		if g.people_by_map.has(name):
			var st: People = g.people_by_map[name]
			people[name] = st.seed_value
			var fs: Dictionary = st.forge_state()
			if fs["spawned"].size() > 0 or fs["altered"].size() > 0:
				forge[name] = fs
	var p: Player = g.player
	var snap := {"v": 4, "map": g.map_name, "player": {"x": p.x, "y": p.y, "angle": p.angle}, "doors": doors, "people": people}
	if g.night != null:
		snap["night"] = g.night.serialize()
	snap["rocks"] = g.powers.rocks_left
	var r := {"seed": run["seed"], "boons": run["boons"].duplicate(), "closedSafe": run["closedSafe"].duplicate(true), "pendingBoons": run["pendingBoons"].duplicate() if run["pendingBoons"] != null else null}
	r["hunger"] = g.hunger.serialize() if g.hunger != null else null
	snap["run"] = r
	if not forge.is_empty():
		snap["forge"] = {"v": 1, "maps": forge}
	return snap


## Write the run save (autosave, pause, boon). False when not saved.
func save_run(_why: String) -> bool:
	if not run_is_active():
		return false
	var snap := get_snapshot()
	var v := SaveCodec.validate_run(snap, SaveCodec.RUN_SCHEMA)
	if not v["ok"]:
		push_warning("run snapshot invalid (%s)" % v["code"])
		return false
	var r := store.write("run", SaveCodec.RUN_SCHEMA, snap)
	if not r["ok"]:
		save_failed = true
		return false
	has_run = true
	return true


## Replay saved mid-night spawns, then alters, onto a freshly built people state.
func replay_forge(st: People, name: String, forge: Variant) -> void:
	if not (forge is Dictionary) or forge.get("v") != 1 or not (forge.get("maps") is Dictionary) or not forge["maps"].has(name):
		return
	if st.forge_log["spawned"].size() > 0 or st.forge_log["altered"].size() > 0:
		return
	var f: Variant = forge["maps"][name]
	var reinf: Array = []
	for e in GameData.get_json("archetypes").get("REINFORCE", []):
		reinf.append(e["archetype"])
	if not (f is Dictionary) or not (f.get("spawned") is Array):
		return
	for e in f["spawned"]:
		if not (e is Dictionary) or not (e.get("a") is String) or Forge.archetype(e["a"]) == null:
			continue
		var r: Dictionary = st.spawn(g.worlds[name], {"archetype": e["a"], "seed": e["s"], "ang": e["ang"]}, {"x": e["x"], "y": e["y"]})
		if not r["ok"]:
			continue
		if reinf.has(e["a"]):
			st.forge_fired += 1
			st.forge_reinf.append(r["id"])
	for al in f.get("altered", []):
		if al is Dictionary and al.get("id") is float and al.get("look") is Dictionary:
			st.alter(int(al["id"]), al["look"])


## Restore a snapshot; validates everything, never throws. True if the map was applied.
func apply_snapshot(snap: Dictionary) -> bool:
	if snap.get("v") == null or int(snap["v"]) < 1 or int(snap["v"]) > 4:
		return false
	var map_name: String = str(snap.get("map", ""))
	if not g.worlds.has(map_name):
		return false
	g.powers.rocks_left = clampi(int(round(float(snap.get("rocks", Powers.ROCKS_PER_RUN)))), 0, Powers.ROCKS_PER_RUN)
	if int(snap["v"]) >= 3:
		var rs: Variant = snap.get("run")
		if not (rs is Dictionary):
			return false
		var raw: Variant = rs.get("hunger")
		run = {"seed": int(rs["seed"]), "boons": (rs["boons"] as Array).duplicate(), "closedSafe": (rs["closedSafe"] as Dictionary).duplicate(true), "pendingBoons": rs.get("pendingBoons"), "pendingGifts": null}
		var hs: Variant = Hunger.restore(raw) if int(snap["v"]) >= 4 and raw != null else null
		g.hunger = hs if hs != null else Hunger.create()
		fx = compute_fx()
	if snap.get("people") is Dictionary:
		for name in snap["people"]:
			if not g.worlds.has(name):
				continue
			var pst: People = g.people_for(name, float(snap["people"][name]))
			replay_forge(pst, name, snap.get("forge"))
	if snap.get("doors") is Dictionary:
		for name in snap["doors"]:
			if not g.worlds.has(name):
				continue
			var w: World = g.worlds[name]
			for c in snap["doors"][name]:
				var ch := w.tile_at(float(c[0]) + 0.5, float(c[1]) + 0.5)
				if ch == "D" or ch == "G":
					w.set_door(int(c[0]), int(c[1]), true)
	var w2: World = g.worlds[map_name]
	var pl: Variant = snap.get("player")
	var pos := g.start_place(w2)
	if pl is Dictionary and float(pl["x"]) > 0.0 and float(pl["y"]) > 0.0 and float(pl["x"]) < w2.width and float(pl["y"]) < w2.height and not w2.blocks(float(pl["x"]), float(pl["y"]), 0.2):
		pos = {"x": float(pl["x"]), "y": float(pl["y"]), "angle": float(pl["angle"])}
	if int(snap["v"]) >= 2 and snap.get("night") != null:
		var cur: Night = g.night
		var rn: Variant = Night.restore(snap["night"], {"nightSec": night_length_min * 60.0 * fxv("nightLen"), "drainMul": fxv("drain") * DRAIN_BASE, "ramp": hunger_ramp(), "nights": cur.nights if cur != null else null, "bloodMax": cur.blood_max if cur != null else null})
		if rn != null:
			g.night = rn
			g.seed_base = rn.night * 100 if rn.night > 1 else 0
	g.end_drink("snapshot")
	g.transition = null
	g.wipe_k = 0.0
	seq = null
	if ["transition", "feeding", "sleeping"].has(g.state):
		g.set_state("playing")
	g.enter_map(map_name, pos["x"], pos["y"], pos["angle"], "")
	apply_fx()
	return true


## Load the stored run and resume it. False (with a notice) if it cannot be loaded.
func continue_run() -> bool:
	if g.state != "title":
		return false
	var fail := func(code: String) -> bool:
		notices.append("Run save could not be loaded (%s)." % code)
		store.remove("run")
		has_run = false
		return false
	var r := store.read("run")
	if not r["ok"]:
		return fail.call(r["code"] if r["code"] != "" else "E_SAVE_NONE")
	var mg := SaveCodec.migrate_run(r["v"], r["data"])
	if not mg["ok"]:
		return fail.call(mg["code"])
	var san: Variant = SaveCodec.sanitize_run(mg["data"])
	if san == null or not g.worlds.has(san["map"]):
		return fail.call("E_SAVE_SCHEMA")
	run = {"seed": int(san["run"]["seed"]), "boons": (san["run"]["boons"] as Array).duplicate(), "closedSafe": (san["run"]["closedSafe"] as Dictionary).duplicate(true), "pendingBoons": san["run"].get("pendingBoons"), "pendingGifts": null}
	g.hunger = Hunger.create()
	fx = compute_fx()
	reset_world_for_run()
	g.night = new_night_state()
	if not apply_snapshot(san):
		return fail.call("E_SAVE_SCHEMA")
	compute_far_spot()
	g.run_on = true
	g.init_ambient()
	g.tut.start()
	auto_acc = 0.0
	if run["pendingBoons"] != null and (run["pendingBoons"] as Array).size() > 0:
		g.set_state("boon")
	else:
		g.set_state("playing")
		g.show_card("Night %d" % g.night.night)
	return true


## Autosave tick (js update: every autosaveSec while playing).
func tick_autosave(dt: float) -> void:
	if g.state == "playing" and g.run_on:
		auto_acc += dt
		if auto_acc >= autosave_sec:
			auto_acc = 0.0
			save_run("autosave")
