extends TestCase
## Edge glow maths (render/edge_glow.gd, js edgeSides) and the transition wipe geometry (HudDraw.draw_wipe, js drawWipe).

const EdgeGlowC := preload("res://render/edge_glow.gd")


func test_alpha_curve() -> void:
	near(EdgeGlowC.alpha_for(1.0), 0.5, 1e-9, "full light is 0.5")
	near(EdgeGlowC.alpha_for(0.0), 0.0, 1e-9, "no light")
	near(EdgeGlowC.alpha_for(0.5), pow(0.5, 1.2) * 0.5, 1e-9, "power 1.2")
	near(EdgeGlowC.zone_alpha(0.0, 1.0), pow(0.35, 1.2) * 0.5, 1e-9, "outer zone reads 35%")


func _world_with_light(lx: float, ly: float) -> World:
	var w := World.new()
	w.width = 10
	w.height = 10
	w.light_grid.resize(100)
	w.outer_grid.resize(100)
	w.light_grid[5 * 10 + 4] = 1.0
	w.lights.append({"x": lx, "y": ly, "radius": 2.0, "type": "torch"})
	return w


func test_direction() -> void:
	var p := Player.new()
	var e := EdgeGlowC.new()
	p.place(4.5, 5.5, 0.0)
	e.compute(_world_with_light(6.0, 5.5), p, true)
	near(e.left, 0.5, 1e-6, "light ahead: left")
	near(e.right, 0.5, 1e-6, "light ahead: right")
	near(e.top, 0.5, 1e-6, "light ahead: top full")
	var e2 := EdgeGlowC.new()
	e2.compute(_world_with_light(4.5, 7.0), p, true)
	near(e2.right, 0.8, 1e-6, "light to +y of a player facing +x is on the right")
	near(e2.left, 0.2, 1e-6, "far side weak")
	near(e2.top, 0.25, 1e-6, "light abeam: top half")
	e2.compute(_world_with_light(40.0, 40.0), p, true)
	near(e2.right + e2.left + e2.top, 0.0, 1e-9, "no source in range gives zero")


func test_wipe_geometry() -> void:
	var c := DrawCanvas.new()
	HudDraw.draw_wipe(c, 0.0, 1.0, 640.0, 360.0)
	eq(c.ops.size(), 0, "k 0 draws nothing")
	HudDraw.draw_wipe(c, 1.0, 1.0, 640.0, 360.0)
	eq(c.ops.size(), 1, "k 1 is one black rect")
	c.reset()
	HudDraw.draw_wipe(c, 0.5, 1.0, 640.0, 360.0)
	var polys := 0
	var strokes := 0
	for op in c.ops:
		if op[0] == "p":
			polys += 1
		elif op[0] == "s":
			strokes += 1
	eq(polys, 64, "64 outside trapezoids")
	eq(strokes, 4, "four trailing rings")
