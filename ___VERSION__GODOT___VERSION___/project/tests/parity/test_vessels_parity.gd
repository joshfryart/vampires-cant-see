extends TestCase
## Vessels against tests/fixtures/vessels.json (tools/golden/vessels.mjs from js/data/vessels.js).


func test_vessels() -> void:
	var fx: Dictionary = load_fixture("vessels")
	deep(Vessels.all(), fx["nodes"], "nodes")
	deep(Vessels.edges(false), fx["edgesA"], "edgesA")
	deep(Vessels.edges(true), fx["edgesV"], "edgesV")
	for c in fx["travel"]:
		deep(Vessels.travel(c["s"]), c["out"], "travel %s" % str(c["s"]))
	for c in fx["state"]:
		var got: Dictionary = Vessels.state(c.get("kind", "villager"), c["mode"], c["blood"])
		deep(got, c["out"], "state %s/%s" % [c["mode"], str(c["blood"])])
	var i := 0
	var states := [Vessels.state("villager", "calm", 1.0), Vessels.state("villager", "flee", 0.5), Vessels.state("villager", "wary", 0.9), Vessels.state("villager", "drinking", 0.3), Vessels.state("villager", "fed", 1.0), null]
	for c in fx["strength"]:
		var got: Array = []
		for n in Vessels.all():
			got.append(Vessels.strength(n, states[i]))
		deep(got, c["list"], "strength[%d]" % i)
		i += 1
	for c in fx["timing"]:
		deep(Vessels.timing(c["bpm"], c["red"], c["sc"]), c["out"], "timing %s/%s/%s" % [str(c["bpm"]), str(c["red"]), str(c["sc"])])
	for c in fx["pulse"]:
		var tm: Dictionary = Vessels.timing(c["bpm"], c["red"], 1.75)
		deep(tm, c["tm"], "pulse tm")
		for row in c["rows"]:
			var art: Array = []
			var vein: Array = []
			for k in Vessels.ARTERIES.size():
				art.append(Vessels.pulse(false, k, row["age"], tm, 1.75))
				vein.append(Vessels.pulse(true, k, row["age"], tm, 1.75))
			deep(art, row["art"], "pulse art %s" % str(row["age"]))
			deep(vein, row["vein"], "pulse vein %s" % str(row["age"]))
	var X := PackedFloat32Array(fx["pose"]["X"])
	var Y := PackedFloat32Array(fx["pose"]["Y"])
	var nodes: Array = Vessels.all()
	for k in nodes.size():
		var a := Vessels.anchor(nodes[k], X, Y)
		var p := Vessels.point(nodes[k], X, Y)
		var want: Dictionary = fx["points"][k]
		deep(a, [want["anchor"]["x"], want["anchor"]["y"]], "anchor " + want["id"])
		deep(p, [want["point"]["x"], want["point"]["y"]], "point " + want["id"])
	for c in fx["edgeCtrls"]:
		var list: Array = Vessels.VEINS if c["vein"] else Vessels.ARTERIES
		var r := Vessels.edge_ctrl(list[int(c["p"])], list[int(c["i"])], X, Y)
		eq(r[0], c["has"], "edgeCtrl has")
		if c["has"]:
			deep([r[1], r[2]], [c["c"]["x"], c["c"]["y"]], "edgeCtrl c")
	for c in fx["edgeAt"]:
		var s := Vessels.edge_at([1.0, 2.0], false, [0.0, 0.0], [9.0, 6.0], c["s"])
		deep(s, [c["straight"]["x"], c["straight"]["y"]], "edgeAt straight")
		var q := Vessels.edge_at([1.0, 2.0], true, [5.0, 9.0], [9.0, 6.0], c["s"])
		deep(q, [c["curved"]["x"], c["curved"]["y"]], "edgeAt curved")
	for c in fx["edgeFront"]:
		deep(Vessels.edge_front(c["a"][0], c["a"][1], c["a"][2]), c["out"], "edgeFront")
	for c in fx["envelope"]:
		deep(Vessels.envelope(c["a"][0], c["a"][1], c["a"][2]), c["out"], "envelope")
	var vb := Vessels.for_body("villager")
	var vm := Vessels.for_body("vampire")
	eq(vb["nodes"].size(), fx["forBody"][0]["n"], "forBody nodes")
	eq(vm["pulse"], false, "vampire never pulses")
