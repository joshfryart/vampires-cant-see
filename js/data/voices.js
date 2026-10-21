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


  // V5 subtitles: quasi-Bavarian lines with English translations. Per kind, per tone (calm | worried | whisper).
  const SUBS = {
    chat: {
      calm: [
        { de: 'Heid is a guada Obend, gell?', en: 'Good evening tonight, isn\'t it?' },
        { de: 'Da Brunna host scho gseng? Staubi is er.', en: 'Have you seen the well? Dusty, it is.' },
        { de: 'Mei Oide sagt, s Brot werd teia.', en: 'My wife says bread is getting dear.' },
        { de: 'Morgn miass ma fria auf, Hans.', en: 'Tomorrow we must rise early, Hans.' },
        { de: 'Nix is los, nur da Wind.', en: 'Nothing\'s going on, only the wind.' }
      ],
      worried: [
        { de: 'Host des ghert? Draußn hod si wos grührt.', en: 'Did you hear that? Something stirred outside.' },
        { de: 'I mog net, dass d Kerzn so flackert.', en: 'I don\'t like how the candle flickers.' },
        { de: 'Schliaß d Fensta liaba zua.', en: 'Better shut the windows.' },
        { de: 'Seit gestern is mir net wohl.', en: 'I\'ve felt uneasy since yesterday.' }
      ],
      whisper: [
        { de: 'Pst. Is wer do?', en: 'Shh. Is someone there?' },
        { de: 'Roar di net, bleib staad.', en: 'Don\'t stir, keep quiet.' },
        { de: 'Des san d Bluadsauger, i sag da s.', en: 'It\'s the bloodsuckers, I tell you.' }
      ]
    },
    question: {
      calm: [
        { de: 'Hast a Schmoiz fürs Brot?', en: 'Have you any lard for the bread?' },
        { de: 'Wo is denn da Pfarrer heid?', en: 'Where is the priest tonight?' },
        { de: 'Kimmst no auf a Bier eina?', en: 'Coming in for one more beer?' },
        { de: 'Wia spaad is denn scho?', en: 'How late is it already?' }
      ],
      worried: [
        { de: 'Wos woar des fia a Gschrei?', en: 'What kind of scream was that?' },
        { de: 'Host d Tür aa guad versperrt?', en: 'Did you lock the door properly?' },
        { de: 'Wo is da Bua hikemma?', en: 'Where did the boy go?' }
      ],
      whisper: [
        { de: 'Siagst du des aa?', en: 'Do you see that too?' },
        { de: 'Wer schleicht do ume?', en: 'Who is sneaking about?' }
      ]
    },
    argue: {
      calm: [
        { de: 'Du Depp, des is mei Platz!', en: 'You fool, that is my seat!' },
        { de: 'Gschwoabl, hoit dei Goschn!', en: 'Blabber, hold your tongue!' },
        { de: 'Zoin soist, du Gizkragn!', en: 'You will pay, you skinflint!' }
      ],
      worried: [
        { de: 'Des is alles dei Schuid!', en: 'This is all your fault!' },
        { de: 'Hätt i auf mei Muatta ghört!', en: 'I should have listened to my mother!' }
      ],
      whisper: [
        { de: 'Sei staad, sunst hert ma uns!', en: 'Be quiet, or they\'ll hear us!' }
      ]
    },
    laugh: {
      calm: [
        { de: 'Hahaha, des is guad!', en: 'Hahaha, that\'s good!' },
        { de: 'Ha ha, du Hamml!', en: 'Ha ha, you rascal!' },
        { de: 'Hihi, na wirkli?', en: 'Hehe, no, really?' }
      ],
      worried: [
        { de: 'Ha... ja, ja, freili.', en: 'Ha... yes, yes, of course.' },
        { de: 'Hehe, sei froh, dass nix passiert is.', en: 'Hehe, be glad nothing happened.' }
      ],
      whisper: [
        { de: 'Hihi... pst.', en: 'Hehe... shh.' }
      ]
    },
    murmur: {
      calm: [
        { de: 'Mhm... jo, jo, mei...', en: 'Mhm... yes, yes, well...' },
        { de: 'Oiso, oiso, wia ma s nimmt...', en: 'Well, well, as one takes it...' }
      ],
      worried: [
        { de: 'Heiliger Gott, bewahr uns...', en: 'Holy God, protect us...' },
        { de: 'Es wird scho wieda, es wird scho...', en: 'It will be all right, it will...' },
        { de: 'Wenn s nur da Morgn war...', en: 'If only it were morning...' }
      ],
      whisper: [
        { de: 'Gott schütz uns, Gott schütz uns...', en: 'God shield us, God shield us...' },
        { de: 'Ned umschaun... ned umschaun...', en: 'Don\'t look round... don\'t look round...' },
        { de: 'Es is do... i spier s...', en: 'It is here... I feel it...' }
      ]
    },
    greet: {
      calm: [
        { de: 'Servus, wia geht s da?', en: 'Hello, how are you?' },
        { de: 'Griaß di, Nachbar!', en: 'Greetings, neighbour!' },
        { de: 'Servus, na, ja, du aa do?', en: 'Hello, well, you here too?' }
      ],
      worried: [
        { de: 'Servus... host wos gseng?', en: 'Hello... have you seen anything?' },
        { de: 'Griaß di, bleib liaba herinnen.', en: 'Greetings, better stay inside.' }
      ],
      whisper: [
        { de: 'Servus, pst, leise.', en: 'Hello, shh, quietly.' }
      ]
    },
    startle: {
      calm: [
        { de: 'Jessas! Hob i mi derschrock!', en: 'Jesus! You gave me a fright!' },
        { de: 'Oha! Wos woar des?', en: 'Whoa! What was that?' }
      ],
      worried: [
        { de: 'Jessas Maria, da is wer!', en: 'Jesus Mary, someone\'s there!' },
        { de: 'Oa! Schaug do hi!', en: 'Oh! Look over there!' }
      ],
      whisper: [
        { de: 'Oh... nur ned schrein.', en: 'Oh... just don\'t scream.' }
      ]
    }
  };

  /**
   * V5 subtitle for a spoken line: {de, en}, pure and deterministic. Uses the same seed/kind/mood as line() / the played speech.
   * mood whisper -> whisper table, worried -> worried table, anything else (calm, argue) -> calm table.
   * @param {number|string} seed
   * @param {string} kind chat|question|argue|laugh|murmur|greet|startle
   * @param {string} [mood] calm|whisper|worried|argue
   * @returns {{de: string, en: string}}
   */
  function subtitle(seed, kind, mood) {
    const k = SUBS[kind] ? kind : 'chat';
    const tone = mood === 'whisper' ? 'whisper' : mood === 'worried' ? 'worried' : 'calm';
    const list = SUBS[k][tone];
    const e = list[hashSeed(seed) % list.length];
    return { de: e.de, en: e.en };
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

  const VoiceData = { VOWELS, CONSONANTS, PRESETS, MOODS, SYLLABLES, KINDS, hashSeed, prng, line, lineLength, forPerson, presetFor, subtitle, SUBS };

  VCS.VoiceData = VoiceData;
  if (typeof module !== 'undefined' && module.exports) module.exports = VoiceData;
})(typeof window !== 'undefined' ? window : globalThis);
