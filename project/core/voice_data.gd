class_name VoiceData
extends RefCounted
## Ports js/data/voices.js logic: deterministic syllable lines, subtitles and per-villager voices. The tables (vowels,
## presets, moods, subtitles, daytalk) come from data/voices.json (tools/export-data.mjs).

const FNV_BASIS := 2166136261
const FNV_PRIME := 16777619


static func d() -> Dictionary:
	return GameData.get_json("voices")


## Hashes a number or string into a 32-bit unsigned seed. Variant: int/float/String, anything else is 0.
static func hash_seed(seed: Variant) -> int:
	if seed is String:
		var s: int = FNV_BASIS
		var u := (seed as String).to_utf16_buffer()
		for i in range(0, u.size(), 2):
			var unit: int = u[i] | (u[i + 1] << 8)
			s = JsMath.imul((s ^ unit) & JsMath.M32, FNV_PRIME)
		return s
	if (seed is float or seed is int) and is_finite(float(seed)):
		return JsMath.u32(floor(float(seed)))
	return 0


## The JS prng(seed): mulberry32 over hash_seed(seed).
static func prng(seed: Variant) -> Rng:
	return Rng.new(float(hash_seed(seed)))


static func pick(rng: Rng, arr: Array) -> Variant:
	return arr[int(floor(rng.next() * arr.size())) % arr.size()]


## Round to 3 decimals so sums are stable.
static func r3(v: float) -> float:
	return JsMath.round_js(v * 1000.0) / 1000.0


static func syl(key: String, dur: float, pitch_mul: float, gap: float) -> Dictionary:
	var s: Dictionary = d()["SYLLABLES"][key]
	return {"vowel": s["vowel"], "consonant": s["consonant"], "dur": dur, "pitchMul": pitch_mul, "gap": gap}


static func struggle_tier(weak: Variant) -> int:
	var w: float = float(weak) if (weak is float or weak is int) and is_finite(float(weak)) else 0.0
	return 0 if w < 0.3 else (1 if w < 0.6 else (2 if w < 0.9 else 3))


## Archetype for a role string, or null.
static func arch_by_role(r: String) -> Variant:
	return Forge.by_role(r)


## Daytalk group for a role: farmer|innkeeper|priest|drunk|guard|gravedigger|elder|mother|child, else 'villager'.
static func group_of(role: Variant) -> String:
	var r: String = str(role if role != null else "").to_lower()
	var arch: Variant = arch_by_role(r)
	if arch != null and arch.get("talk") is String:
		return arch["talk"]
	if d()["DAYTALK"].has(r):
		return r
	var tests := [
		["inn|regular|barkeep|tavern|baker", "innkeeper"], ["priest|monk|nun|sexton", "priest"], ["drunk", "drunk"],
		["guard|watch|soldier", "guard"], ["grave|undertaker", "gravedigger"], ["elder|old|grand", "elder"],
		["mother|wife|woman|maid", "mother"], ["child|kid|boy|girl", "child"], ["farm|herd|shepherd|miller", "farmer"]]
	for t in tests:
		var re := RegEx.new()
		re.compile(t[0])
		if re.search(r) != null:
			return t[1]
	return "villager"


## Subtitle for a spoken line: {de, en}. weak (struggle only) picks the weakness tier pool.
static func subtitle(seed: Variant, kind: String, mood: Variant = null, role: Variant = null, weak: Variant = null) -> Dictionary:
	var dd := d()
	if kind == "struggle" and (weak is float or weak is int) and is_finite(float(weak)):
		var pool: Array = dd["STRUGGLE_TIERS"][struggle_tier(weak)]
		var e0: Dictionary = pool[hash_seed(seed) % pool.size()]
		return {"de": e0["de"], "en": e0["en"]}
	var k: String = kind if dd["SUBS"].has(kind) else "chat"
	var tone: String = "whisper" if mood == "whisper" else ("worried" if mood == "worried" else "calm")
	var lst: Array = dd["SUBS"][k][tone]
	if k == "daytalk" and role != null and tone == "calm":
		lst = dd["DAYTALK"][group_of(role)]
	var e: Dictionary = lst[hash_seed(seed) % lst.size()]
	return {"de": e["de"], "en": e["en"]}


## Deterministic syllable line for a seed. mood nudges the pitch range only; weak (struggle) picks the tier.
static func line(seed: Variant, kind: String, mood: Variant = null, weak: Variant = null) -> Array:
	var dd := d()
	var kinds: Array = dd["KINDS"]
	var k: String = kind if kinds.has(kind) else "chat"
	var rng := Rng.new(float((hash_seed(seed) ^ ((kinds.find(k) + 1) * 7919)) & JsMath.M32))
	var rng_range := 0.12
	if mood == "whisper":
		rng_range = 0.05
	elif mood == "argue":
		rng_range = 0.2
	elif mood == "worried":
		rng_range = 0.16
	var out: Array = []
	# wander() = r3(1 + (rng() - 0.5) * 2 * range)
	if k == "greet":
		out.append(syl("ser", r3(0.13 + rng.next() * 0.03), r3(1.0 + (rng.next() - 0.5) * 2.0 * rng_range), r3(0.01)))
		var vdur := r3(0.2 + rng.next() * 0.08)
		var w2 := r3(1.0 + (rng.next() - 0.5) * 2.0 * rng_range)
		out.append(syl("vus", vdur, r3(w2 * 0.95), r3(0.12 + rng.next() * 0.1)))
		if rng.next() < 0.6:
			var key: String = "na" if rng.next() < 0.5 else "ja"
			out.append(syl(key, r3(0.13 + rng.next() * 0.04), r3(1.0 + (rng.next() - 0.5) * 2.0 * rng_range), r3(0.06)))
		return out
	if k == "laugh":
		var n: int = 3 + int(floor(rng.next() * 4.0))
		for i in n:
			var dur := r3(0.09 + rng.next() * 0.03)
			var wv := r3(1.0 + (rng.next() - 0.5) * 2.0 * rng_range)
			out.append(syl("ha", dur, r3((1.15 - i * 0.04) * wv), r3(0.07 + rng.next() * 0.03)))
		return out
	if k == "startle":
		var oa: String = "oa" if rng.next() < 0.5 else "oe"
		out.append(syl(oa, r3(0.14 + rng.next() * 0.06), r3(1.35 + rng.next() * 0.2), r3(0.05)))
		if rng.next() < 0.6:
			out.append(syl("sch", r3(0.1 + rng.next() * 0.05), r3(1.2 + rng.next() * 0.1), r3(0.03)))
		return out
	if k == "notice":
		var oa2: String = "oa" if rng.next() < 0.5 else "oe"
		out.append(syl(oa2, r3(0.1 + rng.next() * 0.05), r3(1.3 + rng.next() * 0.15), r3(0.06)))
		out.append(syl("wo", r3(0.12 + rng.next() * 0.04), r3(1.0 + (rng.next() - 0.5) * 2.0 * rng_range), r3(0.02)))
		out.append(syl("da", r3(0.14 + rng.next() * 0.05), r3(1.2 + rng.next() * 0.25), r3(0.04)))
		if rng.next() < 0.5:
			out.append(syl("ja", r3(0.12), r3(1.1 + rng.next() * 0.2), r3(0.04)))
		return out
	if k == "halt":
		out.append(syl("ha", r3(0.16 + rng.next() * 0.04), r3(1.2 + rng.next() * 0.1), r3(0.05)))
		out.append(syl("oa", r3(0.26 + rng.next() * 0.06), r3(1.05 + rng.next() * 0.08), r3(0.12 + rng.next() * 0.05)))
		out.append(syl("wo", r3(0.14), r3(1.1), r3(0.02)))
		out.append(syl("da", r3(0.2 + rng.next() * 0.05), r3(1.25 + rng.next() * 0.1), r3(0.04)))
		return out
	if k == "guardcall":
		var n2: int = 4 + int(floor(rng.next() * 4.0))
		for i in n2:
			var key2: String = pick(rng, ["wo", "da", "oa", "ha", "mo"])
			var last: bool = i == n2 - 1
			out.append(syl(key2, r3(0.17 + rng.next() * 0.08 + (0.15 if last else 0.0)), r3(1.05 + (rng.next() - 0.5) * 0.14 - (0.12 if last else 0.0)), r3(0.05 + rng.next() * 0.08)))
		return out
	if k == "struggle" and (weak is float or weak is int) and is_finite(float(weak)):
		var w: float = clampf(float(weak), 0.0, 1.0)
		var tier := struggle_tier(w)
		if tier == 0:
			var n3: int = 3 + int(floor(rng.next() * 3.0))
			for i in n3:
				var key3: String = pick(rng, ["oa", "ha", "wo", "oe", "da", "ja"])
				out.append(syl(key3, r3(0.09 + rng.next() * 0.06), r3(1.3 + rng.next() * 0.25), r3(0.02 + rng.next() * 0.03)))
		elif tier == 1:
			var n4: int = 3 + int(floor(rng.next() * 3.0))
			for i in n4:
				var key4: String = pick(rng, ["ue", "oe", "bi", "mo", "oa"])
				out.append(syl(key4, r3(0.14 + rng.next() * 0.08), r3(1.2 - i * 0.05 + (rng.next() - 0.5) * 0.06), r3(0.06 + rng.next() * 0.1)))
		elif tier == 2:
			var n5: int = 2 + int(floor(rng.next() * 3.0))
			for i in n5:
				var key5: String = pick(rng, ["mo", "gu", "ue", "rr"])
				out.append(syl(key5, r3(0.2 + rng.next() * 0.12), r3(1.0 - i * 0.05 + (rng.next() - 0.5) * 0.04), r3(0.12 + rng.next() * 0.16)))
		else:
			var n6: int = 1 + int(floor(rng.next() * 2.0))
			for i in n6:
				var key6: String = pick(rng, ["mo", "ha", "oe", "ue"])
				out.append(syl(key6, r3(0.3 + rng.next() * 0.2), r3(0.88 - i * 0.06 + (rng.next() - 0.5) * 0.03), r3(0.25 + rng.next() * 0.2)))
		return out
	if k == "struggle":
		var n7: int = 3 + int(floor(rng.next() * 4.0))
		for i in n7:
			var key7: String = pick(rng, ["mo", "gu", "rr", "mo"])
			out.append(syl(key7, r3(0.1 + rng.next() * 0.1), r3(1.15 + rng.next() * 0.3), r3(0.03 + rng.next() * 0.07)))
		return out
	if k == "flee":
		var n8: int = 3 + int(floor(rng.next() * 3.0))
		for i in n8:
			var key8: String = pick(rng, ["oa", "ha", "wo", "oe", "da"])
			out.append(syl(key8, r3(0.13 + rng.next() * 0.07), r3(1.3 + rng.next() * 0.25), r3(0.03 + rng.next() * 0.04)))
		return out
	if k == "cower":
		var n9: int = 3 + int(floor(rng.next() * 3.0))
		for i in n9:
			var key9: String = pick(rng, ["ue", "oe", "mo", "bi"])
			out.append(syl(key9, r3(0.16 + rng.next() * 0.1), r3(1.25 - i * 0.07 + (rng.next() - 0.5) * 0.06), r3(0.12 + rng.next() * 0.16)))
		return out
	if k == "relief":
		out.append(syl("ha", r3(0.32 + rng.next() * 0.12), r3(1.1), r3(0.12)))
		var key10: String = "oa" if rng.next() < 0.5 else "ue"
		out.append(syl(key10, r3(0.24 + rng.next() * 0.1), r3(0.92 + rng.next() * 0.05), r3(0.1)))
		if rng.next() < 0.5:
			out.append(syl("mo", r3(0.18), r3(0.88), r3(0.05)))
		return out
	if k == "alarm":
		out.append(syl("oa", r3(0.26 + rng.next() * 0.1), r3(1.5 + rng.next() * 0.15), r3(0.08)))
		var n11: int = 2 + int(floor(rng.next() * 3.0))
		for i in n11:
			var key11: String = pick(rng, ["sch", "ha", "oe", "wo"])
			out.append(syl(key11, r3(0.12 + rng.next() * 0.05), r3(1.3 + rng.next() * 0.2), r3(0.04)))
		return out
	if k == "hum":
		var n12: int = 4 + int(floor(rng.next() * 4.0))
		var p := 1.0
		for i in n12:
			p = maxf(0.8, minf(1.25, p + (rng.next() - 0.5) * 0.22))
			var key12: String = "mo" if rng.next() < 0.7 else "na"
			out.append(syl(key12, r3(0.26 + rng.next() * 0.14), r3(p), r3(0.03 + rng.next() * 0.05)))
		return out
	if k == "murmur":
		var n13: int = 3 + int(floor(rng.next() * 4.0))
		for i in n13:
			var key13: String = pick(rng, ["mo", "rr", "gu", "oa", "na", "ue"])
			out.append(syl(key13, r3(0.18 + rng.next() * 0.12), r3(0.9 + rng.next() * 0.08), r3(0.1 + rng.next() * 0.15)))
		return out
	var argue: bool = k == "argue"
	var n14: int = (5 if argue else 4) + int(floor(rng.next() * float(5 if argue else 4)))
	var dur_mul: float = 0.68 if argue else 1.0
	var gap_mul: float = 0.4 if argue else 1.0
	var syl_keys: Array = dd["SYLLABLES"].keys()
	for i in n14:
		var key14: String = pick(rng, syl_keys)
		if i > 0 and rng.next() < 0.18:
			key14 = "ja" if rng.next() < 0.5 else "na"
		var s: Dictionary = dd["SYLLABLES"][key14]
		var dur := r3(float(s["dur"]) * dur_mul * (0.85 + rng.next() * 0.3))
		var contour: float = 1.05 if argue else 1.04 - (0.1 * i) / n14
		var gap := r3((0.04 + rng.next() * 0.05) * gap_mul)
		if not argue and i < n14 - 1 and rng.next() < 0.15:
			gap = r3(gap + 0.12 + rng.next() * 0.1)
		var wv2 := r3(1.0 + (rng.next() - 0.5) * 2.0 * rng_range)
		out.append({"vowel": s["vowel"], "consonant": s["consonant"], "dur": dur, "pitchMul": r3(contour * wv2), "gap": gap})
	if rng.next() < (0.5 if argue else 0.3):
		var wa := r3(1.0 + (rng.next() - 0.5) * 2.0 * rng_range)
		out.append(syl("ja", r3(0.14 * dur_mul), r3(1.02 * wa), r3(0.05 * gap_mul)))
		var wb := r3(1.0 + (rng.next() - 0.5) * 2.0 * rng_range)
		out.append(syl("ja", r3(0.16 * dur_mul), r3(0.95 * wb), r3(0.05 * gap_mul)))
	if k == "question":
		var m: int = out.size()
		for i in mini(3, m):
			out[m - 1 - i]["pitchMul"] = r3(1.55 - 0.2 * i)
	return out


## Line total = sum(dur + gap) minus the trailing gap, seconds.
static func line_length(syllables: Array) -> float:
	var t := 0.0
	for i in syllables.size():
		t += float(syllables[i]["dur"])
		if i < syllables.size() - 1:
			t += float(syllables[i]["gap"])
	return r3(t)


## Preset name for a role or age group.
static func preset_for(role: Variant) -> String:
	var presets: Dictionary = d()["PRESETS"]
	var r: String = str(role if role != null else "").to_lower()
	var arch: Variant = arch_by_role(r)
	if arch != null and arch.get("voice") is String and presets.has(arch["voice"]):
		return arch["voice"]
	if presets.has(r):
		return r
	var tests := [["child|kid|boy|girl", "child"], ["elder|old|priest|grand", "elder"], ["woman|mother|maid|wife|baker|innkeeper|female", "woman"]]
	for t in tests:
		var re := RegEx.new()
		re.compile(t[0])
		if re.search(r) != null:
			return t[1]
	return "man"


## Per-villager voice: a preset with seeded jitter on pitch, speed, wobble and breath.
static func for_person(seed: Variant, role: Variant = null) -> Dictionary:
	var base: Dictionary = d()["PRESETS"][preset_for(role)]
	var rng := Rng.new(float((hash_seed(seed) ^ 0x51ed270b) & JsMath.M32))
	return {
		"name": base["name"],
		"pitch": r3(float(base["pitch"]) * (0.88 + rng.next() * 0.24)),
		"speed": r3(float(base["speed"]) * (0.9 + rng.next() * 0.2)),
		"wobble": r3(minf(1.0, float(base["wobble"]) * (0.7 + rng.next() * 0.6))),
		"breath": r3(minf(1.0, float(base["breath"]) * (0.7 + rng.next() * 0.6))),
		"formantMul": r3(float(base["formantMul"]) * (0.97 + rng.next() * 0.06)),
	}


static func weak_of(w: Variant) -> float:
	return clampf(float(w), 0.0, 1.0) if (w is float or w is int) and is_finite(float(w)) else 0.0


## A voice dictionary (forPerson result) is used as is; a preset name or anything else resolves to a preset row (man default).
static func resolve_voice(voice: Variant) -> Dictionary:
	if voice is Dictionary and (voice.get("pitch") is float or voice.get("pitch") is int):
		return voice
	var presets: Dictionary = d()["PRESETS"]
	return presets[voice] if voice is String and presets.has(voice) else presets["man"]


## Duration in seconds speak() takes for a line, without playing (js Audio.speakLength). voice null = speed 1.
static func speak_length(seed: Variant, kind: String, mood: Variant = null, voice: Variant = null, weak: Variant = null) -> float:
	var mr: Dictionary = d()["MOODS"][mood] if mood is String and d()["MOODS"].has(mood) else d()["MOODS"]["calm"]
	var v: Dictionary = {"speed": 1.0} if voice == null else resolve_voice(voice)
	var wk: Variant = weak_of(weak) if (weak is float or weak is int) else null
	var syls := line(seed, kind, mood, wk)
	var sp: float = maxf(0.3, float(mr["speed"]) * (float(v["speed"]) if float(v.get("speed", 0.0)) > 0.0 else 1.0) * (1.0 - 0.4 * weak_of(weak)))
	return line_length(syls) / sp
