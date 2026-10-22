extends RefCounted
## Scenario: walk through every link door chain: the player is put in an open link door cell of the start map and the
## transition must carry them to the linked map and door. Prints TRANSITION_REPORT and quits.
## Use: godot --path project --rendering-driver opengl3 --fixed-fps 60 --quit-after 600 -- --scenario=transition_test

var from_map := ""
var door: Dictionary = {}
var frame := 0


func setup(g: Node) -> void:
	g.debug_map("crypt")
	from_map = "crypt"
	for id in g.world.doors_by_id:
		var d: Dictionary = g.world.doors_by_id[id]
		if d["toMap"] != null:
			door = d
			break
	g.world.set_door(door["col"], door["row"], true)
	g.player.place(door["col"] + 0.5, door["row"] + 0.5, 0.0)
	g.cool = 0.0
	g.just_arrived = null


func step(g: Node, _delta: float) -> Dictionary:
	frame += 1
	if frame >= 120:
		var a: Dictionary = g.worlds[door["toMap"]].arrival(door["toDoor"])
		print("TRANSITION_REPORT " + JSON.stringify({
			"from": from_map, "door": door["id"], "expect_map": door["toMap"], "map": g.map_name, "state": g.state,
			"at": [snappedf(g.player.x, 0.01), snappedf(g.player.y, 0.01)], "arrival": [snappedf(a["x"], 0.01), snappedf(a["y"], 0.01)],
			"wipe": g.wipe_k, "people": g.people.people.size()}))
		g.get_tree().quit()
	return {}
