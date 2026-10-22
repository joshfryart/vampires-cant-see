extends TestCase
## The adaptive render quality governor and the figure-budget effects cap (render/governor.gd, ported from js/render.js adapt and
## figureFrameEnd) fed with synthetic frame-time sequences.

const Governor = preload("res://render/governor.gd")


## Feed n frames of dt ms each starting at now; returns the new time.
func _feed(g, now: float, dt: float, n: int, active: bool = true) -> float:
	for i in n:
		now += dt
		g.adapt(now, active)
	return now


func test_steady_60fps_stays_put() -> void:
	var g := Governor.new()
	var now := _feed(g, 1000.0, 16.667, 600)
	eq(g.quality, 3, "quality unchanged at 60 fps")
	ok(g.mat_detail, "material detail stays on")
	near(g.fps_ema, 60.0, 0.5, "ema tracks 60")
	_feed(g, now, 16.667, 600)
	eq(g.quality, 3, "still 3 after 20 s")


func test_step_down_order_and_timing() -> void:
	var g := Governor.new()
	var now := 1000.0
	# 30 fps: the ema (0.08 per frame) drops under 45 within a few frames, then lowT must exceed 2000 ms
	now = _feed(g, now, 33.333, 30)
	eq(g.quality, 3, "not yet after 1 s")
	ok(g.mat_detail, "material detail still on after 1 s")
	now = _feed(g, now, 33.333, 60)
	ok(not g.mat_detail, "material detail goes first (about 2 s of low fps)")
	eq(g.quality, 3, "quality untouched by the material-detail step")
	# the next 2 s of low fps steps the quality down one level
	now = _feed(g, now, 33.333, 72)
	eq(g.quality, 2, "quality 3 -> 2 after another 2 s")
	now = _feed(g, now, 33.333, 72)
	eq(g.quality, 1, "2 -> 1")
	now = _feed(g, now, 33.333, 72)
	eq(g.quality, 0, "1 -> 0")
	now = _feed(g, now, 33.333, 300)
	eq(g.quality, 0, "never below 0")


func test_step_up_needs_5_seconds_and_restores_mat_detail_last() -> void:
	var g := Governor.new()
	g.quality = 0
	g.mat_detail = false
	g.fps_ema = 60.0
	var now := 1000.0
	now = _feed(g, now, 16.667, 270)
	eq(g.quality, 0, "not before 5 s of high fps")
	now = _feed(g, now, 16.667, 60)
	eq(g.quality, 1, "0 -> 1 after 5 s")
	now = _feed(g, now, 16.667, 320)
	eq(g.quality, 2, "1 -> 2")
	now = _feed(g, now, 16.667, 320)
	eq(g.quality, 3, "2 -> 3")
	ok(not g.mat_detail, "material detail still off at max quality")
	now = _feed(g, now, 16.667, 320)
	ok(g.mat_detail, "then material detail comes back")
	eq(g.quality, 3, "quality stays at the maximum")


func test_resets_on_hitch_inactive_and_middle_band() -> void:
	var g := Governor.new()
	var now := 1000.0
	now = _feed(g, now, 33.333, 50)
	ok(g.low_t > 1000.0, "low timer running")
	# a gap over 250 ms (pause, loading) resets both timers
	now += 400.0
	g.adapt(now, true)
	near(g.low_t, 0.0, 1e-9, "hitch resets the low timer")
	# nothing lit: timers reset, no counting
	now = _feed(g, now, 33.333, 10)
	ok(g.low_t > 0.0, "counting again")
	now = _feed(g, now, 33.333, 1, false)
	near(g.low_t, 0.0, 1e-9, "inactive frame resets")
	# the ema between 45 and 58 neither steps up nor down
	var h := Governor.new()
	h.fps_ema = 50.0
	var t2 := _feed(h, 1000.0, 20.0, 400)
	near(h.low_t, 0.0, 1e-9, "50 fps: no low time")
	near(h.high_t, 0.0, 1e-9, "50 fps: no high time")
	eq(h.quality, 3, "50 fps changes nothing")
	ok(t2 > 0.0)


func test_disabled_governor_pins_quality() -> void:
	var g := Governor.new()
	g.enabled = false
	_feed(g, 1000.0, 50.0, 400)
	eq(g.quality, 3, "pinned")
	ok(g.mat_detail, "pinned")


func test_fx_cap_trigger_and_lift() -> void:
	var g := Governor.new()
	g.begin_frame(0.0, 2)
	eq(g.fx, 2, "effects High")
	ok(g.fx_taper, "taper at fx 2 and quality 3")
	# 19 over-budget frames among under-budget ones: no cap
	for i in 19:
		g.figure_frame_end(1.0, 3, 2, 5.0, 2.5)
	for i in 10:
		g.figure_frame_end(1.0, 3, 2, 1.0, 2.5)
	eq(g.fx_cap, 0, "19 of 29 frames over budget does not cap")
	# frames without figures do not count
	g.figure_frame_end(1.0, 0, 0, 9.0, 2.5)
	eq(g.fx_cap, 0, "no figures, not counted")
	# a frame with only line figures is counted as under budget
	g.figure_frame_end(1.0, 0, 4, 9.0, 2.5)
	# keep going over budget: 20 of the last 30 frames cap High to Low
	var capped_at := -1
	for i in 40:
		g.figure_frame_end(2.0, 3, 2, 5.0, 2.5)
		if g.fx_cap == 1 and capped_at < 0:
			capped_at = i
	ok(capped_at >= 0, "capped after sustained over-budget frames")
	eq(g.fx_cap, 1, "cap is Low")
	near(g.fx_cap_until, 12.0, 1e-9, "cap lasts 10 s from the clock")
	g.begin_frame(5.0, 2)
	eq(g.fx, 1, "effective effects capped to Low")
	ok(not g.fx_taper, "no taper while capped")
	eq(g.fx_cfg, 2, "configured level untouched")
	g.begin_frame(11.9, 2)
	eq(g.fx, 1, "still capped just before the end")
	g.begin_frame(12.0, 2)
	eq(g.fx_cap, 0, "cap lifted at 10 s")
	eq(g.fx, 2, "High again")
	# configured Low or Off is never capped further or capped at all
	var lo := Governor.new()
	lo.begin_frame(0.0, 1)
	for i in 40:
		lo.figure_frame_end(1.0, 3, 2, 5.0, 2.5)
	eq(lo.fx_cap, 0, "no cap when effects are not High")
	eq(lo.fx, 1)


func test_fx_cap_history_cleared_after_trigger() -> void:
	var g := Governor.new()
	g.begin_frame(0.0, 2)
	for i in 20:
		g.figure_frame_end(0.0, 2, 1, 4.0, 2.5)
	eq(g.fx_cap, 1, "capped after 20 over-budget frames")
	g.begin_frame(10.5, 2)
	eq(g.fx_cap, 0, "lifted")
	# the history was cleared: 19 further over-budget frames do not re-trigger
	for i in 19:
		g.figure_frame_end(10.5, 2, 1, 4.0, 2.5)
	eq(g.fx_cap, 0, "needs 20 fresh frames")
	g.figure_frame_end(10.5, 2, 1, 4.0, 2.5)
	eq(g.fx_cap, 1, "20th fresh frame caps again")


func test_taper_needs_quality_3() -> void:
	var g := Governor.new()
	g.quality = 2
	g.begin_frame(0.0, 2)
	ok(not g.fx_taper, "no taper below quality 3")
	g.quality = 3
	g.begin_frame(0.0, 2)
	ok(g.fx_taper, "taper at quality 3, effects High")
	g.begin_frame(0.0, 1)
	ok(not g.fx_taper, "no taper at effects Low")
