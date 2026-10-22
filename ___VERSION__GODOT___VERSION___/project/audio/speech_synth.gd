class_name SpeechSynth
extends RefCounted
## Villager speech (js/audio.js speak): a sawtooth source through three formant band-pass filters (a muffled horn), noise for the
## consonants and for whispers, with the per-syllable pitch, envelope and (for weak victims) slur of the JS recipe. Pure maths over
## plain data so it can run on a worker thread: render() returns unit-peak PCM at RATE; the caller applies the level.

const RATE := 22050
const FLOOR_GAIN := 0.0001
const NEUTRAL_FORMANT := [500.0, 1500.0, 2500.0]
const FGAIN := [1.0, 0.6, 0.3]
const FQ := [5.0, 8.0, 8.0]


## One band-pass biquad (RBJ, constant 0 dB peak gain, like WebAudio's bandpass).
class Band:
	extends RefCounted
	var b0: float = 0.0
	var b2: float = 0.0
	var a1: float = 0.0
	var a2: float = 0.0
	var z1: float = 0.0
	var z2: float = 0.0

	func set_freq(hz: float, q: float, rate: float) -> void:
		var w0: float = TAU * clampf(hz, 20.0, rate * 0.45) / rate
		var alpha: float = sin(w0) / (2.0 * q)
		var a0: float = 1.0 + alpha
		b0 = alpha / a0
		b2 = -alpha / a0
		a1 = -2.0 * cos(w0) / a0
		a2 = (1.0 - alpha) / a0

	func process(x: float) -> float:
		var y: float = b0 * x + z1
		z1 = -a1 * y + z2
		z2 = b2 * x - a2 * y
		return y


static func _weak_speed(w: float) -> float:
	return 1.0 - 0.4 * w


## Slur amount 0..1: starts at weak 0.6 (below ~40% blood), full at 1.
static func slur_of(w: float) -> float:
	var x: float = (w - 0.6) / 0.4
	return 0.0 if x <= 0.0 else (1.0 if x >= 1.0 else x * x * (3.0 - 2.0 * x))


## Render the line. p: {syls, voice, mood (row), weak, vowels, consonants, seed}. Returns {pcm: PackedFloat32Array (unit peak),
## total: seconds the line lasts}.
static func render(p: Dictionary) -> Dictionary:
	var syls: Array = p["syls"]
	var voice: Dictionary = p["voice"]
	var mr: Dictionary = p["mood"]
	var weak: float = p["weak"]
	var vowels: Dictionary = p["vowels"]
	var consonants: Dictionary = p["consonants"]
	var slur := slur_of(weak)
	var sp: float = maxf(0.3, float(mr["speed"]) * (float(voice["speed"]) if float(voice["speed"]) > 0.0 else 1.0) * _weak_speed(weak))
	var total := 0.0
	for i in syls.size():
		total += float(syls[i]["dur"])
		if i < syls.size() - 1:
			total += float(syls[i]["gap"])
	total = JsMath.round_js(total * 1000.0) / 1000.0 / sp
	var breath: float = minf(1.0, float(voice["breath"]) + float(mr["breath"]) + 0.45 * weak)
	var base: float = float(voice["pitch"]) * float(mr["pitch"]) * (1.0 - 0.2 * weak)
	var voiced: float = float(mr["voiced"])
	var fmul: float = float(voice.get("formantMul", 1.0)) if float(voice.get("formantMul", 1.0)) != 0.0 else 1.0
	var n_total: int = int(ceil((total + 0.15) * RATE))
	var out := PackedFloat32Array()
	out.resize(n_total)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(p.get("seed", 1)) & 0xFFFFFFFF
	var bands: Array = [Band.new(), Band.new(), Band.new()]
	var nbp := Band.new()
	var phase := 0.0
	var freq_hold := base
	var t := 0.02
	for i in syls.size():
		var s: Dictionary = syls[i]
		var d: float = float(s["dur"]) / sp
		var gap: float = float(s["gap"]) / sp
		var fm: Array = vowels.get(s["vowel"], vowels["a"])
		var nxt_s: Dictionary = syls[i + 1] if i + 1 < syls.size() else s
		var nxt: Array = vowels.get(nxt_s["vowel"], fm)
		var pm: float = float(s["pitchMul"])
		var f0: float = maxf(40.0, base * pm * (1.0 + (1.0 if i % 2 == 1 else -1.0) * float(voice["wobble"]) * 0.04))
		var f1: float = f0 * (1.0 + float(voice["wobble"]) * 0.03) * (1.0 - 0.12 * slur)
		var c0: Dictionary = consonants.get(s["consonant"], consonants[""])
		var c: Dictionary = consonants[""] if slur > 0.5 and (slur > 0.9 or i % 2 == 0) else c0
		var trail: float = 1.0 - 0.65 * slur * (float(i) / float(syls.size() - 1) if syls.size() > 1 else 1.0)
		var pk: float = (0.7 + 0.3 * minf(1.5, pm)) * voiced * trail
		var att: float = minf(0.03, d * 0.25)
		# envelope as linear segments: (time offset, value)
		var env: Array = [[0.0, FLOOR_GAIN], [att, maxf(pk, FLOOR_GAIN)]]
		if c["rolled"]:
			var step: float = maxf(0.02, d / 5.0)
			for k in range(1, 5):
				env.append([k * step, maxf(pk * (0.3 if k % 2 == 1 else 1.0), FLOOR_GAIN)])
		env.append([d, FLOOR_GAIN])
		env.sort_custom(func(a, b): return a[0] < b[0])
		var i0: int = int(floor(t * RATE))
		var n: int = maxi(1, int(floor(d * RATE)))
		var hz0: Array = []
		var hz1: Array = []
		for j in 3:
			var neutral: float = NEUTRAL_FORMANT[j]
			var h0: float = (float(fm[j]) + (neutral - float(fm[j])) * 0.65 * slur) * fmul
			hz0.append(h0)
			hz1.append(h0 + (float(nxt[j]) * fmul - h0) * 0.5 * slur if slur > 0.0 else h0)
			(bands[j] as Band).set_freq(h0, FQ[j], RATE)
		var ei := 0
		for k in n:
			var idx: int = i0 + k
			if idx >= n_total:
				break
			var u: float = float(k) / float(n)
			var tt: float = u * d
			var freq: float = f0 + (f1 - f0) * u
			if slur > 0.0 and k % 16 == 0:
				for j in 3:
					(bands[j] as Band).set_freq(float(hz0[j]) + (float(hz1[j]) - float(hz0[j])) * u, FQ[j], RATE)
			var dp: float = freq / RATE
			phase += dp
			phase -= floor(phase)
			# naive saw with a polyBLEP correction at the wrap
			var saw: float = 2.0 * phase - 1.0
			if phase < dp:
				var x: float = phase / dp
				saw -= x + x - x * x - 1.0
			elif phase > 1.0 - dp:
				var x2: float = (phase - 1.0) / dp
				saw -= x2 * x2 + x2 + x2 + 1.0
			var y: float = 0.0
			for j in 3:
				y += (bands[j] as Band).process(saw) * FGAIN[j]
			while ei < env.size() - 2 and tt >= float(env[ei + 1][0]):
				ei += 1
			var e0: Array = env[ei]
			var e1: Array = env[ei + 1]
			var span: float = float(e1[0]) - float(e0[0])
			var ev: float = float(e0[1]) + (float(e1[1]) - float(e0[1])) * (clampf((tt - float(e0[0])) / span, 0.0, 1.0) if span > 1e-9 else 1.0)
			out[idx] += y * ev
		freq_hold = f1
		phase += freq_hold * gap
		phase -= floor(phase)
		# consonant / breath noise
		var nz: float = maxf(float(c["noise"]), breath * 0.5)
		if nz > 0.02:
			var n_hz: float = float(c["hz"]) if float(c["hz"]) > 0.0 else float(fm[1]) * fmul
			var n_dur: float = maxf(0.03, d * (0.45 if float(c["noise"]) > 0.2 else 1.0))
			var n_peak: float = nz * (1.6 if voiced < 0.5 else 0.8)
			var nn: int = maxi(1, int(floor(n_dur * RATE)))
			nbp.z1 = 0.0
			nbp.z2 = 0.0
			nbp.set_freq(n_hz, 1.0, RATE)
			var na: float = 0.01
			for k in nn:
				var idx2: int = i0 + k
				if idx2 >= n_total:
					break
				var tn: float = float(k) / RATE
				var g: float
				if tn < na:
					g = n_peak * tn / na
				else:
					g = n_peak * pow(FLOOR_GAIN / n_peak, (tn - na) / maxf(n_dur - na, 1e-4))
				out[idx2] += nbp.process(rng.randf() * 2.0 - 1.0) * g
		t += d + gap
	return {"pcm": out, "total": total}


## Unit-peak float PCM -> 16-bit little-endian bytes (scaled so the peak is 0.9). Returns {bytes, scale}: scale is the factor
## the stored samples were multiplied by, so a level L plays at L / scale.
static func to_pcm16(pcm: PackedFloat32Array) -> Dictionary:
	var peak := 1e-9
	for v in pcm:
		peak = maxf(peak, absf(v))
	var scale: float = 0.9 / peak
	var bytes := PackedByteArray()
	bytes.resize(pcm.size() * 2)
	for i in pcm.size():
		var q: int = clampi(int(round(pcm[i] * scale * 32767.0)), -32768, 32767)
		bytes[i * 2] = q & 0xFF
		bytes[i * 2 + 1] = (q >> 8) & 0xFF
	return {"bytes": bytes, "scale": scale}
