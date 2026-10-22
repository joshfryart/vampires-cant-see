extends RefCounted
## Scenario: a seeded bot plays the town windowed (random walking, pings, feeding, powers, rocks) so every drawing and audio path
## runs for real. Prints BOT_DONE with a few facts at the end; any SCRIPT ERROR in the output is a bug.
## Use: godot --path project --rendering-driver opengl3 --write-movie out/bot_play/f.png --fixed-fps 60 --quit-after 900 -- --scenario=bot_play

var rng := RandomNumberGenerator.new()
var inp := {}


func setup(g: Node) -> void:
	rng.seed = 77
	g.flow.seed_param = 21
	g.set_state("title")
	g.flow.begin_run()
	g.debug_map("town")
	g.night.night = 3
	g.night.blood = 70.0


func step(g: Node, _delta: float) -> Dictionary:
	if g.frame_no % 10 == 0:
		inp = {"forward": 1.0 if rng.randf() < 0.8 else 0.0, "strafe": 0.0, "turn": rng.randf_range(-1.0, 1.0) if rng.randf() < 0.3 else 0.0, "mouseDx": 0.0}
	var r := rng.randf()
	if r < 0.02:
		g.ping_clicks += 1
	elif r < 0.03:
		g.feed_press += 1
	elif r < 0.035:
		g.pressed[KEY_Q] = true
	elif r < 0.04:
		g.pressed[KEY_F] = true
	elif r < 0.045:
		g.pressed[KEY_G] = true
	elif r < 0.05:
		g.pressed[KEY_SHIFT] = true
	if g.state == "boon":
		g.pressed[KEY_1] = true
	elif g.state == "gift":
		g.pressed[KEY_2] = true
	if g.frame_no == 880:
		print("BOT_DONE state=%s night=%d blood=%.1f fed=%d pulses=%d echoes=%d people=%d" % [g.state, g.night.night if g.night != null else 0, g.blood, g.night.fed_count if g.night != null else 0, g.sonar.pulses.size(), g.people.echoes.size(), g.people.people.size()])
	return inp
