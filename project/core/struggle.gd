class_name Struggle
extends RefCounted
## Ports js/struggle.js: procedural pose of a villager held by the vampire (panic flailing, then pushing away, then limp as
## the blood drains). Pure maths: pose() fills a pose Dictionary with body-frame offsets (f forward, s sideways, u height).
## A pose is {lean, headF, headS, tilt, hipU, shU, headU, yawU, yawL, sway, sq, jolt, wl} plus per-side [left, right] arrays
## hf hs hu hb (hand f/s/u and elbow bend 0..1), ff fs fu (feet), kb (knee bend).

const TWO_PI := PI * 2.0
const PANIC_END := 3.4
const PANIC_FADE := 1.2
const PUSH_SEG := 3.2
const N_PUSH := 4
const SCALARS := ["lean", "headF", "headS", "tilt", "hipU", "shU", "headU", "yawU", "yawL", "sway", "sq", "jolt"]
const PAIRS := ["hf", "hs", "hu", "hb", "ff", "fs", "fu", "kb"]
const ARMS := ["hf", "hs", "hu", "hb"]

static var PA := mk_pose()
static var PB := mk_pose()
static var UP := mk_pose()
static var LO := mk_pose()
static var PIN := mk_pose()
static var PANIC := mk_pose()
static var PUSH := mk_pose()
static var PUSH2 := mk_pose()
static var LIMP := mk_pose()
static var TMP := mk_pose()


static func smooth(a: float, b: float, x: float) -> float:
	var u: float = 0.0 if x <= a else (1.0 if x >= b else (x - a) / (b - a))
	return u * u * (3.0 - 2.0 * u)


static func fract(x: float) -> float:
	return x - floor(x)


static func hash2(a: float, b: float) -> float:
	return fract(sin(a * 127.1 + b * 311.7) * 43758.5453)


static func pos(x: float) -> float:
	return x if x > 0.0 else 0.0


## Fast attack, slow release bump peaking at x == tau with value 1.
static func pk(x: float, tau: float) -> float:
	return (x / tau) * exp(1.0 - x / tau) if x > 0.0 else 0.0


## JS Math.sign.
static func sgn(x: float) -> float:
	return 1.0 if x > 0.0 else (-1.0 if x < 0.0 else x)


static func mk_pose() -> Dictionary:
	var p := {}
	for k in SCALARS:
		p[k] = 0.0
	for k in PAIRS:
		p[k] = [0.0, 0.0]
	p["wl"] = 0.0
	return p


static func create() -> Dictionary:
	return mk_pose()


static func copy_pose(d: Dictionary, s: Dictionary) -> void:
	for k in SCALARS:
		d[k] = s[k]
	for k in PAIRS:
		d[k][0] = s[k][0]
		d[k][1] = s[k][1]


static func lerp_pose(d: Dictionary, a: Dictionary, b: Dictionary, k: float) -> void:
	for n in SCALARS:
		d[n] = a[n] + (b[n] - a[n]) * k
	for n in PAIRS:
		d[n][0] = a[n][0] + (b[n][0] - a[n][0]) * k
		d[n][1] = a[n][1] + (b[n][1] - a[n][1]) * k


## Blend only the arm fields of d toward s by k.
static func lerp_arms(d: Dictionary, s: Dictionary, k: float) -> void:
	for n in ARMS:
		d[n][0] += (s[n][0] - d[n][0]) * k
		d[n][1] += (s[n][1] - d[n][1]) * k


## Rest pose of a held victim: hands up at the chest, feet planted a bit wide.
static func base(P: Dictionary, c: Dictionary) -> void:
	var L: float = c["L"]
	P["lean"] = 0.0
	P["headF"] = 0.0
	P["headS"] = 0.0
	P["tilt"] = 0.05
	P["yawU"] = 0.0
	P["yawL"] = 0.0
	P["sway"] = 0.0
	P["sq"] = 1.0
	P["jolt"] = 0.0
	P["hipU"] = 0.32 * L
	P["shU"] = 0.53 * L
	P["headU"] = 0.68 * L
	for s in 2:
		var sg: float = 1.0 if s == 0 else -1.0
		P["hf"][s] = 0.08 * L
		P["hs"][s] = sg * c["shS"] * 1.3
		P["hu"][s] = P["shU"] - 0.06 * L
		P["hb"][s] = 0.8
		P["ff"][s] = 0.0
		P["fs"][s] = sg * c["hipS"] * 1.5
		P["fu"][s] = 0.0
		P["kb"][s] = 0.012 * L


# ---- Panic moves. Upper-body moves touch arms/head/trunk; lower-body moves touch legs, hips and sway. ----
# t absolute seconds, a amplitude 0..1, spd frequency scale.
static func upper(i: int, P: Dictionary, t: float, a: float, spd: float, c: Dictionary) -> void:
	var L: float = c["L"]
	match i:
		0:  # wrist-pull breakaway
			for s in 2:
				var sg: float = -1.0 if s != 0 else 1.0
				var pull: float = pow(pos(sin(TWO_PI * 1.3 * spd * t + c["p"] + s * PI)), 0.6) * a
				P["hu"][s] = P["shU"] - pull * (P["shU"] - P["hipU"])
				P["hf"][s] = (0.15 - 0.2 * pull) * L
				P["hs"][s] = sg * (c["shS"] + 0.06 * L)
				P["hb"][s] = 0.8 - 0.5 * pull
				P["yawU"] += sg * 0.35 * pull
				P["headS"] += sg * 0.02 * pull
		1:  # panic jabs
			for s in 2:
				var pulse: float = pow(pos(sin(TWO_PI * 2.6 * spd * t + c["p"] + s * 0.7)), 3.0) * a
				P["hf"][s] = (0.06 + 0.16 * pulse) * L
				P["hu"][s] = P["shU"] + 0.01 * L
				P["hb"][s] = 1.0 - 0.9 * pulse
			P["jolt"] = maxf(P["jolt"], 0.7 * a)
		2:  # windmill batting
			for s in 2:
				var sg2: float = -1.0 if s != 0 else 1.0
				var th: float = 1.5 + (0.7 + 1.9 * (0.5 + 0.5 * sin(TWO_PI * 1.7 * spd * t + c["p"] + s * PI)) - 1.5) * a
				P["hs"][s] = sg2 * (c["shS"] + 0.22 * L * sin(th))
				P["hu"][s] = P["shU"] - 0.22 * L * cos(th)
				P["hf"][s] = 0.05 * L
				P["hb"][s] = 0.3
			P["jolt"] = maxf(P["jolt"], 0.8 * a)
		3:  # torso wrench
			var x: float = sin(TWO_PI * 0.9 * spd * t + c["p"])
			P["yawU"] += 0.5 * a * sgn(x) * pow(absf(x), 0.7)
			P["tilt"] += 0.25 * a * sin(TWO_PI * 0.9 * spd * (t - 0.1) + c["p"])
			for s in 2:
				P["hu"][s] = P["shU"] - 0.1 * L
				P["hf"][s] = 0.1 * L
			P["jolt"] = maxf(P["jolt"], 0.5 * a)
		4:  # back arch (one-shot over the segment)
			var e: float = smooth(0.0, 0.15, c["seg"]) * (1.0 - smooth(0.35, 0.6, c["seg"])) * a
			P["lean"] -= 0.07 * L * e
			P["headF"] -= 0.04 * L * e
			P["headU"] += 0.025 * L * e
			P["tilt"] -= 0.2 * e
			for s in 2:
				var sg3: float = -1.0 if s != 0 else 1.0
				P["hs"][s] += (sg3 * (c["shS"] + 0.12 * L) - P["hs"][s]) * e
				P["hu"][s] += (P["headU"] - P["hu"][s]) * e
				P["hf"][s] -= 0.04 * L * e
			P["sq"] += 0.05 * e
			P["jolt"] = maxf(P["jolt"], 0.6 * e)
		5:  # face claw
			for s in 2:
				var sg4: float = -1.0 if s != 0 else 1.0
				P["hf"][s] = 0.18 * L
				P["hs"][s] = sg4 * 0.05
				P["hb"][s] = 0.7
				P["hu"][s] = P["headU"] - 0.05 * L * pos(sin(TWO_PI * 3.0 * spd * t + c["p"] + s * PI)) * a
			P["tilt"] += 0.2 * a * sin(TWO_PI * 1.4 * spd * t)
		6:  # pry hands
			for s in 2:
				var sg5: float = -1.0 if s != 0 else 1.0
				var ph: float = sin(TWO_PI * 2.4 * spd * t + s * PI)
				P["hs"][s] = sg5 * (0.02 + 0.03 * (0.6 if ph > 0.0 else 1.0))
				P["hu"][s] = P["shU"] - 0.08 * L + 0.04 * L * ph * a
				P["hf"][s] = 0.12 * L
				P["hb"][s] = 0.5
			P["jolt"] = maxf(P["jolt"], 0.4 * a)
		7:  # slump
			var e2: float = smooth(0.0, 0.2, c["seg"]) * (1.0 - smooth(0.4, 0.6, c["seg"])) * a
			P["shU"] -= 0.06 * L * e2
			P["headU"] -= 0.06 * L * e2
			P["sq"] -= 0.04 * e2
			for s in 2:
				P["hu"][s] += (P["headU"] + 0.08 * L - P["hu"][s]) * e2
				P["hb"][s] += (0.3 - P["hb"][s]) * e2


static func lower(i: int, P: Dictionary, t: float, a: float, spd: float, c: Dictionary) -> void:
	var L: float = c["L"]
	match i:
		0:  # knee / kick
			for s in 2:
				var lift: float = pow(pos(sin(TWO_PI * 1.2 * spd * t + s * PI + c["p"])), 1.5) * a
				P["fu"][s] = 0.12 * L * lift
				P["ff"][s] = 0.1 * L * lift
				P["kb"][s] = (0.012 + 0.13 * lift) * L
		1:  # stamp / heel dig
			for s in 2:
				var x: float = sin(TWO_PI * 2.0 * spd * t + s * PI)
				P["fu"][s] = 0.05 * L * pos(x) * a
				P["fs"][s] *= 1.0 + 0.2 * pos(-x)
			P["sq"] -= 0.03 * a * pos(sin(TWO_PI * 4.0 * spd * t))
		2:  # side wrench
			var x2: float = sin(TWO_PI * 1.1 * spd * t + c["p"])
			P["sway"] += 0.07 * a * x2
			P["headS"] -= 0.03 * a * x2
			var s2: int = 0 if x2 > 0.0 else 1
			P["fs"][s2] += (-1.0 if s2 != 0 else 1.0) * 0.03 * a * absf(x2)
		3:  # squat
			var e: float = smooth(0.0, 0.2, c["seg"]) * (1.0 - smooth(0.4, 0.6, c["seg"])) * a
			P["hipU"] -= 0.07 * L * e
			for s in 2:
				var sg: float = -1.0 if s != 0 else 1.0
				P["kb"][s] += 0.09 * L * e
				P["fs"][s] += sg * c["hipS"] * 0.7 * e


static func _pick(pid: float, salt: int, n_pool: int, i: float) -> int:
	var rep: Array = []
	for m in n_pool:
		if hash2(pid, float(salt * 7 + m)) > 0.3:
			rep.append(m)
	if rep.size() < 2:
		rep = [0, 1]
	var idx: int = rep[int(floor(hash2(pid + i * 0.37, float(salt + 5)) * rep.size())) % rep.size()]
	var prev: int = rep[int(floor(hash2(pid + (i - 1.0) * 0.37, float(salt + 5)) * rep.size())) % rep.size()]
	if idx == prev:
		idx = rep[(rep.find(idx) + 1) % rep.size()]
	return idx


## Schedule one region: pick a move from the villager's repertoire per segment and blend into the next.
static func schedule(out: Dictionary, upper_pool: bool, n_pool: int, t: float, a: float, spd: float, c: Dictionary, salt: int, dur0: float) -> void:
	var dur: float = dur0 * (0.7 + 0.5 * hash2(c["pid"], float(salt)))
	var off: float = hash2(c["pid"], float(salt + 1)) * dur
	var n: float = floor((t + off) / dur)
	var t_seg: float = (t + off) - n * dur
	var ma := _pick(c["pid"], salt, n_pool, n)
	var mb := _pick(c["pid"], salt, n_pool, n + 1.0)
	var k: float = smooth(dur - 0.18, dur, t_seg)
	c["seg"] = t_seg / dur
	base(PA, c)
	if upper_pool:
		upper(ma, PA, t, a, spd, c)
	else:
		lower(ma, PA, t, a, spd, c)
	if k > 0.0:
		c["seg"] = 0.0
		base(PB, c)
		if upper_pool:
			upper(mb, PB, t, a, spd, c)
		else:
			lower(mb, PB, t, a, spd, c)
		lerp_pose(out, PA, PB, k)
	else:
		copy_pose(out, PA)


# ---- Push-away variants ----
static func push_pose(P: Dictionary, v: int, t: float, a: float, spd: float, c: Dictionary, away: float) -> void:
	var L: float = c["L"]
	base(P, c)
	P["lean"] = -0.05 * L
	P["headF"] = -0.035 * L
	P["shU"] += 0.015 * L
	P["headU"] -= 0.02 * L - 0.0
	P["hipU"] -= 0.02 * L
	P["headS"] = away * 0.04
	P["tilt"] = away * 0.4
	P["yawU"] = away * 0.2
	var swap: int = 0 if int(floor(t / (0.45 + 0.25 * hash2(c["pid"], 33.0)))) % 2 == 0 else 1
	P["ff"][swap] = -0.09 * L
	P["kb"][swap] = 0.02 * L
	P["ff"][1 - swap] = 0.07 * L
	P["kb"][1 - swap] = 0.08 * L
	P["fu"][1 - swap] = 0.03 * L * pos(sin(t * 9.0 * spd))
	var wr: float = TWO_PI * 1.3 * spd
	if v == 0:
		var e: float = pow(pos(sin(wr * t + c["p"])), 0.5) * a
		for s in 2:
			var sg: float = -1.0 if s != 0 else 1.0
			P["hf"][s] = (0.14 + 0.06 * e) * L
			P["hs"][s] = sg * c["shS"] * 0.9
			P["hu"][s] = P["shU"] + 0.01 * L
			P["hb"][s] = 0.6 * (1.0 - e)
		P["lean"] -= 0.02 * L * e
		P["hipU"] -= 0.01 * L * e
		P["jolt"] = 0.6 * e
	elif v == 1:
		for s in 2:
			var sg2: float = -1.0 if s != 0 else 1.0
			var r: float = pos(sin(TWO_PI * 2.0 * spd * t + s * PI)) * a
			P["hf"][s] = 0.2 * L
			P["hs"][s] = sg2 * 0.05
			P["hu"][s] = P["headU"] + 0.01 * L - 0.06 * L * r
			P["hb"][s] = 0.5 + 0.3 * r
		P["tilt"] = away * 0.5
		P["jolt"] = 0.5 * a
	elif v == 2:
		var yank: float = pow(pos(sin(TWO_PI * 0.9 * spd * t + c["p"])), 3.0) * a
		for s in 2:
			var sg3: float = -1.0 if s != 0 else 1.0
			P["hf"][s] = (0.12 - 0.18 * yank) * L
			P["hs"][s] = sg3 * 0.02 - away * 0.03
			P["hu"][s] = P["shU"] - 0.05 * L
			P["hb"][s] = 0.5 + 0.3 * yank
		P["lean"] -= 0.08 * L * yank
		P["hipU"] -= 0.03 * L * yank
		P["sq"] -= 0.04 * yank
		P["jolt"] = 0.7 * yank
	else:
		var lead: int = c["lead"]
		for s in 2:
			var sg4: float = -1.0 if s != 0 else 1.0
			if s == lead:
				var e2: float = 0.5 + 0.5 * sin(wr * t + c["p"])
				P["hf"][s] = (0.2 + 0.015 * e2) * L
				P["hs"][s] = sg4 * c["shS"]
				P["hu"][s] = P["shU"]
				P["hb"][s] = 0.05
			else:
				var th: float = 2.2 + 0.4 * sin(TWO_PI * 1.7 * spd * t)
				var w: float = 0.4 + 0.6 * a
				P["hs"][s] = sg4 * (c["shS"] + 0.22 * L * sin(th) * w)
				P["hu"][s] = P["shU"] - 0.22 * L * cos(th) * w
				P["hf"][s] = 0.08 * L
				P["hb"][s] = 0.3
		P["jolt"] = 0.5 * a


## Fully slack: dangling arms, lolled head, buckled knees.
static func limp_pose(P: Dictionary, c: Dictionary) -> void:
	var L: float = c["L"]
	base(P, c)
	P["hipU"] = 0.3 * L
	P["shU"] = 0.5 * L
	P["headU"] = 0.6 * L
	P["lean"] = 0.02 * L
	P["headF"] = 0.03 * L
	P["headS"] = 0.05 * c["bw"]
	P["tilt"] = 0.55
	P["ff"][0] = 0.0
	P["ff"][1] = 0.0
	P["kb"][0] = 0.06 * L
	P["kb"][1] = 0.05 * L
	P["fs"][0] = c["hipS"] * 1.15
	P["fs"][1] = -c["hipS"] * 1.15
	P["hf"][0] = 0.01 * L
	P["hf"][1] = 0.0
	P["hs"][0] = c["shS"] * 1.1
	P["hs"][1] = -c["shS"] * 1.1
	P["hu"][0] = P["shU"] - 0.25 * L
	P["hu"][1] = P["shU"] - 0.26 * L
	P["hb"][0] = 0.2
	P["hb"][1] = 0.2


## Fill `out` with the held victim's pose. o: {t, g (s since the grab), bl (blood left 0..1), sp (s since the last struggle
## attempt), rs (restrain 0..1), pid, lh (height scale), bw (build), shS, hipS, anim (false = reduced motion: a still pose)}.
static func pose(out: Dictionary, o: Dictionary) -> Dictionary:
	var pid: float = float(Barks.to_i32(int(o["pid"])))
	var anim: bool = o.get("anim", true) != false
	var c := {"L": o["lh"], "bw": o["bw"], "shS": o["shS"], "hipS": o["hipS"], "pid": pid, "p": pid * 1.7, "seg": 0.0, "lead": 0 if hash2(pid, 93.0) < 0.5 else 1}
	var bl: float = clampf(float(o["bl"]), 0.0, 1.0)
	var E: float = pow(smooth(0.05, 0.9, bl), 0.8)
	var amp: float = (0.8 + 0.4 * hash2(pid, 92.0)) * pow(E, 1.2)
	var spd: float = (0.85 + 0.35 * hash2(pid, 91.0)) * (0.45 + 0.55 * E)
	var t: float = float(o["t"]) if anim else 0.0
	var g: float = float(o["g"]) if anim else 99.0
	var away: float = 1.0 if (int(pid) & 2) != 0 else -1.0
	var a: float = clampf(amp, 0.0, 1.0)
	limp_pose(LIMP, c)
	var spike: float = pk(float(o["sp"]), 0.25) if anim else 0.0
	var w_panic: float = 1.0 - smooth(PANIC_END - PANIC_FADE, PANIC_END, g)
	if bl > 0.6:
		w_panic = maxf(w_panic, 0.6 * spike)
	var w_push: float = (1.0 - w_panic) * smooth(0.08, 0.3, bl)
	var w_limp: float = 1.0 - w_panic - w_push
	if w_panic > 0.001:
		schedule(UP, true, 8, t, a, spd, c, 1, 0.75)
		schedule(LO, false, 4, t, a, spd, c, 2, 1.0)
		copy_pose(PANIC, UP)
		for n in PAIRS:
			if n == "hf" or n == "hs" or n == "hu" or n == "hb":
				continue
			PANIC[n][0] = LO[n][0]
			PANIC[n][1] = LO[n][1]
		PANIC["hipU"] = LO["hipU"]
		PANIC["yawL"] = LO["yawL"]
		PANIC["sway"] = LO["sway"]
		PANIC["sq"] = UP["sq"] * LO["sq"]
		PANIC["headS"] += 0.04 * a * sin(TWO_PI * 1.4 * spd * t)
		PANIC["tilt"] += 0.5 * a * sin(TWO_PI * 1.4 * spd * t - 0.4) + 0.06 * a * sin(t * 25.0)
		if g < 0.35:
			var x: float = g / 0.12
			var e: float = x * exp(1.0 - x) * (1.0 - smooth(0.2, 0.35, g))
			PANIC["shU"] += 0.03 * c["L"] * e
			PANIC["headU"] -= 0.02 * c["L"] * e
			PANIC["tilt"] += 0.15 * e
			for s in 2:
				var sg: float = -1.0 if s != 0 else 1.0
				PANIC["hu"][s] += (PANIC["headU"] - 0.02 * c["L"] - PANIC["hu"][s]) * e
				PANIC["hs"][s] += (sg * 0.04 - PANIC["hs"][s]) * e
				PANIC["hf"][s] += (0.06 * c["L"] - PANIC["hf"][s]) * e
				PANIC["hb"][s] += (1.0 - PANIC["hb"][s]) * e
	if w_push > 0.001 or w_panic <= 0.001:
		var seg: int = int(floor((g if anim else 0.0) / PUSH_SEG))
		var kk: float = smooth(PUSH_SEG - 0.3, PUSH_SEG, g - seg * PUSH_SEG) if anim else 0.0
		var ipid: int = int(pid)
		var v0: int = (ipid + seg) % N_PUSH if anim else 0
		var v1: int = (ipid + seg + 1) % N_PUSH if anim else 0
		var tp: float = t if anim else 0.2
		var flip: float = -1.0 if hash2(pid, floor(g / 3.0) + 40.0) < 0.3 else 1.0
		push_pose(PUSH, v0, tp, a, spd, c, away * flip)
		if kk > 0.0 and v0 != v1:
			push_pose(PUSH2, v1, tp, a, spd, c, away * flip)
			lerp_pose(PUSH, PUSH, PUSH2, kk)
		var droop: float = 1.0 - smooth(0.15, 0.6, bl)
		lerp_arms(PUSH, LIMP, droop)
		var loll: float = 1.0 - smooth(0.2, 0.55, bl)
		PUSH["tilt"] += (LIMP["tilt"] - PUSH["tilt"]) * loll
		PUSH["headU"] += (LIMP["headU"] - PUSH["headU"]) * loll
		var buckle: float = 1.0 - smooth(0.2, 0.35, bl)
		for s in 2:
			PUSH["kb"][s] += (LIMP["kb"][s] - PUSH["kb"][s]) * buckle
	if w_limp > 0.999:
		copy_pose(out, LIMP)
	elif w_panic > 0.999:
		copy_pose(out, PANIC)
	elif w_panic <= 0.001:
		lerp_pose(out, PUSH, LIMP, w_limp)
	else:
		var d: float = w_panic / (w_panic + w_push) if w_panic + w_push > 0.0 else 0.0
		lerp_pose(TMP, PUSH, PANIC, d)
		lerp_pose(out, TMP, LIMP, w_limp)
	var rs: float = clampf(float(o.get("rs", 0.0)), 0.0, 1.0)
	if rs > 0.0:
		var L: float = c["L"]
		for s in 2:
			var sg2: float = -1.0 if s != 0 else 1.0
			PIN["hf"][s] = 0.03 * L
			PIN["hs"][s] = sg2 * c["shS"] * 1.15
			PIN["hu"][s] = out["hipU"] + 0.03 * L
			PIN["hb"][s] = 0.25
		lerp_arms(out, PIN, 0.9 * rs * (1.0 - w_limp * 0.5))
		out["yawU"] *= 1.0 - 0.7 * rs
		out["lean"] *= 1.0 - 0.5 * rs
		out["sway"] *= 1.0 - 0.7 * rs
		out["jolt"] *= 1.0 - 0.6 * rs
	if anim:
		var L2: float = c["L"]
		var trem: float = 0.004 * L2 * (1.0 + 2.0 * (1.0 - E))
		var tf: float = 9.0 - 3.0 * (1.0 - E)
		out["shU"] += trem * sin(t * tf * TWO_PI + pid)
		out["headU"] += trem * sin(t * tf * TWO_PI + pid * 2.0)
		var sp: float = float(o["sp"])
		var S: float = sqrt(bl) * (1.0 - 0.7 * (1.0 - smooth(0.15, 0.6, bl)))
		if S > 0.0 and sp >= 0.0 and sp < 0.7:
			out["headU"] -= 0.02 * L2 * pk(sp, 0.07) * S
			out["tilt"] += away * 0.15 * pk(sp, 0.07) * S
			var sh: float = pk(sp - 0.03, 0.09) * S
			out["shU"] += 0.02 * L2 * sh
			out["yawU"] += away * 0.25 * sh
			var ar: float = pk(sp - 0.08, 0.12) * S
			for s in 2:
				out["hf"][s] += 0.05 * L2 * ar
				out["hb"][s] *= 1.0 - 0.8 * ar
				out["hu"][s] += 0.03 * L2 * ar
			var lg: float = pk(sp - 0.1, 0.15) * S
			var kick: int = posmod(int(floor(float(o["t"]) * 3.1 + pid)), 2)
			out["fu"][kick] += 0.08 * L2 * lg
			out["ff"][kick] += 0.06 * L2 * lg
			out["kb"][kick] += 0.08 * L2 * lg
			out["jolt"] = maxf(out["jolt"], 1.0 * (ar if ar > lg else lg))
			if sp > 0.45:
				out["shU"] -= 0.01 * L2 * smooth(0.45, 0.55, sp) * (1.0 - smooth(0.6, 0.7, sp))
	out["jolt"] = clampf(out["jolt"], 0.0, 1.0) * (1.0 if anim else 0.0)
	out["yawU"] = clampf(out["yawU"], -0.55, 0.55)
	out["yawL"] = 0.4 * out["yawU"]
	out["wl"] = w_limp
	return out
