(function (root) {
  'use strict';
  const VCS = (root.VCS = root.VCS || {});

  // Villager speech data (synth gibberish with a quasi old-Bavarian flavour). Pure and deterministic: never Math.random.

  // Formants (F1, F2, F3 Hz) for an adult male voice; scaled by a preset's formantMul.
  const VOWELS = {
    a: [700, 1200, 2500],
    e: [450, 1900, 2600],
    i: [300, 2200, 3000],
    o: [450, 800, 2500],
    u: [320, 700, 2400],
    oa: [550, 950, 2500], // Bavarian "oa" (a diphthong, held as one broad vowel)
    ue: [300, 1700, 2300], // ue / u-umlaut
    oe: [430, 1450, 2400] // oe / o-umlaut
  };

  // Consonant colours: noise centre Hz (0 = none), noise share of the syllable, rolled = amplitude flutter (r).
  const CONSONANTS = {
    '': { hz: 0, noise: 0, rolled: false },
    sch: { hz: 3200, noise: 0.55, rolled: false },
    s: { hz: 5500, noise: 0.45, rolled: false },
    r: { hz: 600, noise: 0.15, rolled: true },
    j: { hz: 2200, noise: 0.1, rolled: false },
    n: { hz: 400, noise: 0.05, rolled: false },
    m: { hz: 300, noise: 0.05, rolled: false },
    h: { hz: 1800, noise: 0.5, rolled: false },
    g: { hz: 1500, noise: 0.2, rolled: false },
    b: { hz: 800, noise: 0.15, rolled: false },
    d: { hz: 2000, noise: 0.2, rolled: false },
    k: { hz: 2600, noise: 0.35, rolled: false },
    w: { hz: 700, noise: 0.05, rolled: false }
  };

  // Voice presets: base pitch Hz, speed (1 = normal), wobble (vibrato depth 0..1), breath (noise share 0..1), formantMul (vocal tract size).
  const PRESETS = {
    man: { name: 'man', pitch: 105, speed: 1, wobble: 0.1, breath: 0.1, formantMul: 1 },
    woman: { name: 'woman', pitch: 205, speed: 1.05, wobble: 0.12, breath: 0.14, formantMul: 1.17 },
    elder: { name: 'elder', pitch: 118, speed: 0.78, wobble: 0.3, breath: 0.28, formantMul: 0.97 },
    child: { name: 'child', pitch: 290, speed: 1.2, wobble: 0.14, breath: 0.1, formantMul: 1.35 }
  };

  // Mood: speed and loudness multipliers, extra breathiness, voiced = 0 means a pure whisper.
  const MOODS = {
    calm: { speed: 1, gain: 1, breath: 0, pitch: 1, voiced: 1 },
    whisper: { speed: 0.9, gain: 0.45, breath: 0.6, pitch: 1, voiced: 0.12 },
    worried: { speed: 1.1, gain: 0.8, breath: 0.15, pitch: 1.08, voiced: 1 },
    argue: { speed: 1.25, gain: 1.35, breath: 0.05, pitch: 1.05, voiced: 1 }
  };

  // Named syllables (flavour). Each is a vowel + consonant seed used when composing lines.
  const SYLLABLES = {
    oa: { vowel: 'oa', consonant: '', dur: 0.2 },
    ue: { vowel: 'ue', consonant: '', dur: 0.17 },
    oe: { vowel: 'oe', consonant: '', dur: 0.17 },
    sch: { vowel: 'u', consonant: 'sch', dur: 0.16 },
    rr: { vowel: 'o', consonant: 'r', dur: 0.2 },
    ja: { vowel: 'a', consonant: 'j', dur: 0.15 },
    na: { vowel: 'a', consonant: 'n', dur: 0.14 },
    ser: { vowel: 'e', consonant: 's', dur: 0.14 },
    vus: { vowel: 'u', consonant: 's', dur: 0.2 },
    ha: { vowel: 'a', consonant: 'h', dur: 0.13 },
    mo: { vowel: 'o', consonant: 'm', dur: 0.16 },
    gu: { vowel: 'u', consonant: 'g', dur: 0.15 },
    bi: { vowel: 'i', consonant: 'b', dur: 0.12 },
    da: { vowel: 'a', consonant: 'd', dur: 0.13 },
    wo: { vowel: 'o', consonant: 'w', dur: 0.15 },
    ke: { vowel: 'e', consonant: 'k', dur: 0.12 }
  };
  const SYL_KEYS = Object.keys(SYLLABLES);
  const KINDS = ['chat', 'question', 'argue', 'laugh', 'murmur', 'greet', 'startle'];

  /** Hashes a number or string into a 32-bit unsigned seed. @returns {number} */
  function hashSeed(seed) {
    let s = typeof seed === 'number' && isFinite(seed) ? Math.floor(seed) : 0;
    if (typeof seed === 'string') {
      s = 2166136261;
      for (let i = 0; i < seed.length; i++) s = Math.imul(s ^ seed.charCodeAt(i), 16777619);
    }
    return s >>> 0;
  }

  /** Small seeded PRNG (mulberry32). @returns {function(): number} 0..1 generator */
  function prng(seed) {
    let t = hashSeed(seed) >>> 0;
    return function () {
      t = (t + 0x6d2b79f5) >>> 0;
      let r = Math.imul(t ^ (t >>> 15), 1 | t);
      r = (r + Math.imul(r ^ (r >>> 7), 61 | r)) ^ r;
      return (((r ^ (r >>> 14)) >>> 0) / 4294967296);
    };
  }

  /** Picks an item from an array with a generator. */
  function pick(rng, arr) {
    return arr[Math.floor(rng() * arr.length) % arr.length];
  }

  /** Builds one syllable object from a named template. */
  function syl(key, dur, pitchMul, gap) {
    const s = SYLLABLES[key];
    return { vowel: s.vowel, consonant: s.consonant, dur: dur, pitchMul: pitchMul, gap: gap };
  }

  /** Round to 3 decimals so sums are stable. */
  function r3(v) {
    return Math.round(v * 1000) / 1000;
  }

  /**
   * Deterministic syllable line for a seed.
   * @param {number|string} seed
   * @param {string} kind chat|question|argue|laugh|murmur|greet|startle
   * @param {string} [mood] calm|whisper|worried|argue (nudges the pitch range only)
   * @returns {{vowel: string, consonant: string, dur: number, pitchMul: number, gap: number}[]}
   */
  function line(seed, kind, mood) {
    const k = KINDS.indexOf(kind) >= 0 ? kind : 'chat';
    const rng = prng(hashSeed(seed) ^ (KINDS.indexOf(k) + 1) * 7919);
    const range = mood === 'whisper' ? 0.05 : mood === 'argue' ? 0.2 : mood === 'worried' ? 0.16 : 0.12;
    const out = [];
    const wander = () => r3(1 + (rng() - 0.5) * 2 * range);
    if (k === 'greet') {
      // "Servus" (+ optional "na" / "ja")
      out.push(syl('ser', r3(0.13 + rng() * 0.03), wander(), r3(0.01)));
      out.push(syl('vus', r3(0.2 + rng() * 0.08), r3(wander() * 0.95), r3(0.12 + rng() * 0.1)));
      if (rng() < 0.6) out.push(syl(rng() < 0.5 ? 'na' : 'ja', r3(0.13 + rng() * 0.04), wander(), r3(0.06)));
      return out;
    }
    if (k === 'laugh') {
      const n = 3 + Math.floor(rng() * 4);
      for (let i = 0; i < n; i++) {
        out.push(syl('ha', r3(0.09 + rng() * 0.03), r3((1.15 - i * 0.04) * wander()), r3(0.07 + rng() * 0.03)));
      }
      return out;
    }
    if (k === 'startle') {
      out.push(syl(rng() < 0.5 ? 'oa' : 'oe', r3(0.14 + rng() * 0.06), r3(1.35 + rng() * 0.2), r3(0.05)));
      if (rng() < 0.6) out.push(syl('sch', r3(0.1 + rng() * 0.05), r3(1.2 + rng() * 0.1), r3(0.03)));
      return out;
    }
    if (k === 'murmur') {
      const n = 3 + Math.floor(rng() * 4);
      for (let i = 0; i < n; i++) {
        const key = pick(rng, ['mo', 'rr', 'gu', 'oa', 'na', 'ue']);
        out.push(syl(key, r3(0.18 + rng() * 0.12), r3(0.9 + rng() * 0.08), r3(0.1 + rng() * 0.15)));
      }
      return out;
    }
    const argue = k === 'argue';
    const n = (argue ? 5 : 4) + Math.floor(rng() * (argue ? 5 : 4));
    const durMul = argue ? 0.68 : 1;
    const gapMul = argue ? 0.4 : 1;
    for (let i = 0; i < n; i++) {
      let key = pick(rng, SYL_KEYS);
      if (i > 0 && rng() < 0.18) key = rng() < 0.5 ? 'ja' : 'na';
      const s = SYLLABLES[key];
      const dur = r3(s.dur * durMul * (0.85 + rng() * 0.3));
      // phrase contour: gentle fall; argument stays pressed high
      const contour = argue ? 1.05 : 1.04 - (0.1 * i) / n;
      let gap = r3((0.04 + rng() * 0.05) * gapMul);
      if (!argue && i < n - 1 && rng() < 0.15) gap = r3(gap + 0.12 + rng() * 0.1); // phrase pause
      out.push({ vowel: s.vowel, consonant: s.consonant, dur: dur, pitchMul: r3(contour * wander()), gap: gap });
    }
    if (rng() < (argue ? 0.5 : 0.3)) {
      // doubled "ja-ja"
      out.push(syl('ja', r3(0.14 * durMul), r3(1.02 * wander()), r3(0.05 * gapMul)));
      out.push(syl('ja', r3(0.16 * durMul), r3(0.95 * wander()), r3(0.05 * gapMul)));
    }
    if (k === 'question') {
      // rising end: last three syllables climb
      const m = out.length;
      for (let i = 0; i < Math.min(3, m); i++) {
        out[m - 1 - i].pitchMul = r3(1.55 - 0.2 * i);
      }
    }
    return out;
  }

  /** The final gap of a line is trailing silence; line total = sum(dur + gap) minus that gap. @returns {number} seconds */
  function lineLength(syllables) {
    let t = 0;
    for (let i = 0; i < syllables.length; i++) {
      t += syllables[i].dur;
      if (i < syllables.length - 1) t += syllables[i].gap;
    }
    return r3(t);
  }

  /** Resolves a role or age group into a preset name. @returns {string} */
  function presetFor(role) {
    const r = String(role || '').toLowerCase();
    if (PRESETS[r]) return r;
    if (/child|kid|boy|girl/.test(r)) return 'child';
    if (/elder|old|priest|grand/.test(r)) return 'elder';
    if (/woman|mother|maid|wife|baker|innkeeper|female/.test(r)) return 'woman';
    return 'man';
  }

  /**
   * Per-villager voice: a preset with seeded jitter on pitch (+-12 %), speed (+-10 %), wobble and breath.
   * @param {number|string} seed
   * @param {string} [role] preset name or a role/age group (child, elder, mother, ...)
   * @returns {{name: string, pitch: number, speed: number, wobble: number, breath: number, formantMul: number}}
   */
  function forPerson(seed, role) {
    const base = PRESETS[presetFor(role)];
    const rng = prng(hashSeed(seed) ^ 0x51ed270b);
    return {
      name: base.name,
      pitch: r3(base.pitch * (0.88 + rng() * 0.24)),
      speed: r3(base.speed * (0.9 + rng() * 0.2)),
      wobble: r3(Math.min(1, base.wobble * (0.7 + rng() * 0.6))),
      breath: r3(Math.min(1, base.breath * (0.7 + rng() * 0.6))),
      formantMul: r3(base.formantMul * (0.97 + rng() * 0.06))
    };
  }

  const VoiceData = { VOWELS, CONSONANTS, PRESETS, MOODS, SYLLABLES, KINDS, hashSeed, prng, line, lineLength, forPerson, presetFor };

  VCS.VoiceData = VoiceData;
  if (typeof module !== 'undefined' && module.exports) module.exports = VoiceData;
})(typeof window !== 'undefined' ? window : globalThis);
