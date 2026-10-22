extends RefCounted
## Adaptive render quality and the figure-budget effects cap, ported from js/render.js (adapt, figureFrameEnd and the per-frame
## fx block of render()). Plain state machine: no nodes, no clocks of its own; callers pass the time in.
##
## Godot adaptation: the JS thresholds are about the browser frame rate. Here the caller (EchoView.render_frame) passes the REAL
## wall-clock time in ms (Time.get_ticks_usec) between calls, so the fps estimate is the real presented frame rate. The JS
## constants are kept unchanged: fps EMA < 45 for 2 s steps down, > 58 for 5 s steps up, gaps over 250 ms (hitches, pause, menus)
## and frames with nothing lit reset the timers.
##
## Order of degradation (as JS): material detail first (quality >= 2), then quality 3 -> 2 -> 1 -> 0. Recovery is the reverse.

const MAX_QUALITY := 3
const FPS_LOW := 45.0
const FPS_HIGH := 58.0
const LOW_MS := 2000.0
const HIGH_MS := 5000.0
const HITCH_MS := 250.0
const EMA_K := 0.08
const FIG_HIST := 30
const FIG_HIST_OVER := 20
const FIG_CAP_SECONDS := 10.0

## False pins the quality (tests, benches): adapt() does nothing, the fx cap still works.
var enabled: bool = true
var quality: int = MAX_QUALITY
## Automatic material-detail switch (JS r.matDetail); the user's materialDetail setting is ANDed on top by the caller.
var mat_detail: bool = true
var fps_ema: float = 60.0
var low_t: float = 0.0
var high_t: float = 0.0
var last_ms: float = -1.0

## Effects: the configured level, the cap (0 none, 1 = held at Low), when it lifts (game clock s), the effective level, taper flag.
var fx_cfg: int = 0
var fx_cap: int = 0
var fx_cap_until: float = 0.0
var fx: int = 0
var fx_taper: bool = false
var _hist: PackedByteArray = PackedByteArray()
var _hi: int = 0
var _over: int = 0
## Set when quality, mat_detail or fx_cap last changed (callers push shader uniforms only then if they like).
var changed: bool = false


func _init() -> void:
	_hist.resize(FIG_HIST)


## JS adapt(r, active). now_ms = wall clock in ms; active = something lit this frame. Returns true when quality or mat_detail changed.
func adapt(now_ms: float, active: bool) -> bool:
	var dt: float = now_ms - last_ms if last_ms >= 0.0 else INF
	last_ms = now_ms
	if not enabled:
		return false
	if not active or dt <= 0.0 or dt > HITCH_MS:
		low_t = 0.0
		high_t = 0.0
		return false
	fps_ema += (1000.0 / dt - fps_ema) * EMA_K
	if fps_ema < FPS_LOW:
		low_t += dt
		high_t = 0.0
	elif fps_ema > FPS_HIGH:
		high_t += dt
		low_t = 0.0
	else:
		low_t = 0.0
		high_t = 0.0
	var q: int = quality
	var did := false
	if low_t > LOW_MS and mat_detail and quality >= 2:
		mat_detail = false
		low_t = 0.0
		did = true
		Log.info("render", "material detail off (fps ~%d)" % int(round(fps_ema)))
	elif low_t > LOW_MS and q > 0:
		q -= 1
	elif high_t > HIGH_MS and q < MAX_QUALITY:
		q += 1
	elif high_t > HIGH_MS and not mat_detail:
		mat_detail = true
		high_t = 0.0
		did = true
	if q != quality:
		quality = q
		low_t = 0.0
		high_t = 0.0
		did = true
		Log.info("render", "render quality %d (fps ~%d)" % [q, int(round(fps_ema))])
	if did:
		changed = true
	return did


## Per-frame fx block of JS render(): lifts an expired cap, then derives the effective level and the taper flag.
## cfg_effects = the Effects setting (0 Off, 1 Low, 2 High), t = game clock in seconds.
func begin_frame(t: float, cfg_effects: int) -> void:
	fx_cfg = clampi(cfg_effects, 0, 2)
	if fx_cap != 0 and not (t < fx_cap_until and fx_cap_until - t <= FIG_CAP_SECONDS):
		fx_cap = 0
		changed = true
		Log.info("render", "effects cap lifted, retrying High")
	fx = fx_cap if (fx_cap != 0 and fx_cfg > fx_cap) else fx_cfg
	fx_taper = fx == 2 and quality >= 3


## JS figureFrameEnd(r, t): end of the echo pass. Call only when a pulse is alive. 20 over-budget frames of the last 30 drop
## High to Low for 10 s. fig_ms/fig_budget are the volumetric figure time spent and the cut-off of that frame.
func figure_frame_end(t: float, fig_vol: int, fig_line: int, fig_ms: float, fig_budget: float) -> void:
	if not (fig_vol + fig_line > 0):
		return
	var over: int = 1 if (fig_vol > 0 and fig_ms > fig_budget) else 0
	_over += over - _hist[_hi]
	_hist[_hi] = over
	_hi = (_hi + 1) % FIG_HIST
	if _over >= FIG_HIST_OVER and fx_cap == 0 and fx_cfg >= 2:
		fx_cap = 1
		fx_cap_until = t + FIG_CAP_SECONDS
		_hist.fill(0)
		_over = 0
		changed = true
		Log.info("render", "effects capped to Low for %d s (figures over budget)" % int(FIG_CAP_SECONDS))


## Forget a cap (the Effects setting was changed on purpose).
func clear_cap() -> void:
	fx_cap = 0
	_hist.fill(0)
	_over = 0
	_hi = 0


## Snapshot for the F3 overlay.
func state() -> Dictionary:
	return {"quality": quality, "mat_detail": mat_detail, "fx_cap": fx_cap, "fps_ema": fps_ema, "fx": fx, "fx_taper": fx_taper}
