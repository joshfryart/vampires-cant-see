extends RefCounted
## Scenario: does the Sense key (V) really work in a real window? Starts a New Long Night in the Hollow (seed 7), waits 3 s, injects a V
## key press through Input.parse_input_event (InputEventKey, physical_keycode KEY_V, pressed then released) so it takes the same
## Game._unhandled_input path as a human press, then saves a frame every 0.25 s for 2.5 s and logs rogue.sense_t, the cooldown and
## trek.senses before and after. Game._unhandled_input ignores input while a scenario runs (the scenarios drive the sim themselves), so the
## scenario lifts that guard for the one dispatch only.
## Use: godot --path project --rendering-driver opengl3 --quit-after 600 -- --scenario=sense_check [--out=<absolute dir>]
## It needs a real window (it reads the window texture). Since 0.22.0 every --scenario run uses in-memory saves (Game.boot), so the
## new trek it starts no longer touches the user:// trek checkpoint or rogue meta.

const OUT_DEFAULT := "C:/Users/hello/AppData/Local/Temp/claude/C--Users-hello-OneDrive-Desktop-claude-Vampires-Cant-See/4095c3ef-caf6-4fb9-a1b1-a8cf76b650c8/scratchpad/sense_check"
const PRESS_AT := 3.0
const SHOT_EVERY := 0.25
const SHOT_SPAN := 2.5

var _t := 0.0
var _out := OUT_DEFAULT
var _pressed := false
var _next_shot := 0.0
var _n := 0


func setup(g: Node) -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
	DirAccess.make_dir_recursive_absolute(_out)
	g.flow.seed_param = 7
	g.set_state("title")
	g.rogue.new_trek(7)
	print("[sense_check] state=%s map=%s rogue_on=%s hint='%s' out=%s" % [g.state, g.map_name, g.rogue_on(), g.rogue.sense_hint(), _out])


func _key(code: Key, down: bool) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.pressed = down
	return e


func _report(g: Node, tag: String) -> void:
	var r = g.rogue
	print("[sense_check] %s t=%.2f sense_t=%.2f cooldown=%.2f senses=%d stat=%d state=%s hint_text='%s'" % [tag, _t, r.sense_t, r._sense_cd, r.trek.senses, int(r.stats.get("senses", 0)), g.state, g.hint_text])


func step(g: Node, delta: float) -> Dictionary:
	_t += delta
	if not _pressed and _t >= PRESS_AT:
		_pressed = true
		_next_shot = _t
		_report(g, "BEFORE")
		var scen = g.scenario
		g.scenario = null   # lift the scenario guard in Game._unhandled_input for the dispatch only
		Input.parse_input_event(_key(KEY_V, true))
		Input.parse_input_event(_key(KEY_V, false))
		print("[sense_check] injected V; pressed dict has V right after parse_input_event: %s (false = the event is delivered later)" % str(g.pressed.has(KEY_V)))
		# parse_input_event delivers at the next input flush, so the guard stays lifted for a few frames (the game reads the keyboard itself meanwhile)
		var left := [4]
		var cb := Callable()
		cb = func():
			left[0] -= 1
			if left[0] <= 0:
				g.scenario = scen
				g.get_tree().process_frame.disconnect(cb)
		g.get_tree().process_frame.connect(cb)
	if _pressed and _t >= _next_shot and _t <= PRESS_AT + SHOT_SPAN + 0.01:
		_report(g, "frame%02d" % _n)
		var img: Image = g.get_viewport().get_texture().get_image()
		if img != null:
			img.save_png("%s/f%02d.png" % [_out, _n])
		_n += 1
		_next_shot += SHOT_EVERY
	if _pressed and _t > PRESS_AT + SHOT_SPAN + 0.3:
		_report(g, "AFTER")
		g.get_tree().quit()
	return {}
