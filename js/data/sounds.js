(function (root) {
  'use strict';
  const VCS = (root.VCS = root.VCS || {});

  // Sound levels in one place. range in cells, strength 0..1 (visual), z = source height (floor 0, ceiling 1, eye 0.5), fade = seconds, gain 0..1 (audio), hearDist = audible cells.
  /**
   * v0.11 echo acoustics (docs/SPEC-echoes.md). All dB are intensity dB; distances in metres = cells * cellM.
   * Physical numbers follow the spec; the game* / occ* / vis* fields are tuning knobs.
   */
  const A = {
    cellM: 1,
    c: 343,
    rMin: 0.5,
    airDbPerM: 0.0245, // 3.4 kHz, 10 C, 70 % RH
    spread: { wall: 20, object: 40 }, // wall = image source at 2r, object = sonar equation
    ts: { prop: -16.5, person: -15 },
    personGainDb: 12, // class calibration G for people (spec T21), so a person at 3 cells is still audible
    // Mouth beam B(theta), dB at 0/30/60/90/120/150/180 degrees (TODO v0.11; symmetric, linear between nodes).
    beamDb: [0, -1, -3, -8, -14, -18, -20],
    beamStepDeg: 30,
    visDb: 36, visMin: 0.15, // visual brightness v = clamp(1 + dB/visDb, visMin, 1)
    gameRefDb: -6, gameKappa: 0.7, gameMin: 0.05, // echo amplitude = 10^(kappa*(L-ref)/20), clamped
    // Per material: alpha (absorption), s (scatter), rough 0..1 (visual stipple + grain tail), tl500 (dB transmission loss at 500 Hz), echo voice.
    mat: {
      stone: { alpha: 0.03, s: 0.1, rough: 0.12, tl500: 60, voice: 'crisp' },
      brick: { alpha: 0.03, s: 0.15, rough: 0.2, tl500: 50, voice: 'crisp' },
      roughStone: { alpha: 0.04, s: 0.35, rough: 0.45, tl500: 60, voice: 'crisp' },
      cobble: { alpha: 0.05, s: 0.6, rough: 0.7, tl500: 60, voice: 'crisp' },
      wood: { alpha: 0.1, s: 0.3, rough: 0.3, tl500: 28, voice: 'hollow' },
      door: { alpha: 0.1, s: 0.3, rough: 0.3, tl500: 25.5, voice: 'hollow' }, // gap: 0.01 would model a 1 % gap under a closed door (leaks to ~2 kHz)
      glass: { alpha: 0.02, s: 0.05, rough: 0.05, tl500: 30, voice: 'tick', peakHz: 2000, peakDb: 6 },
      iron: { alpha: 0.02, s: 0.5, rough: 0.5, tl500: 3, voice: 'ring' },
      grass: { alpha: 0.6, s: 0.7, rough: 0.8, tl500: 6, voice: 'soft' }
    },
    // Occlusion (game): filter cutoff = 6000 * 10^(-loss/40) Hz; gain = 10^(-occK * loss / 20), floored at occMin.
    occCutoffHz: 6000, occK: 0.3, occMin: 0.04, maekawaCapDb: 24, maekawaHz: 500, doorwayReach: 14,
    // Reverb: T60 per zone from Sabine RT60 = 0.161 V / A (clamped), fb_i = 10^(-3 tau_i / T60).
    t60Min: 0.4, t60Max: 2.5,
    zone: {
      crypt: { w: 12, d: 7, h: 3, alpha: 0.04 }, mausoleum: { w: 6, d: 4, h: 3, alpha: 0.04 },
      tavern: { w: 18, d: 12, h: 3.5, alpha: 0.15 }, church: { w: 16, d: 14, h: 8, alpha: 0.06 },
      house1: { w: 10, d: 8, h: 2.7, alpha: 0.12 }, house2: { w: 9, d: 10, h: 2.7, alpha: 0.12 },
      cellar: { w: 4, d: 12, h: 2.5, alpha: 0.06 }, barn: { w: 8, d: 8, h: 4, alpha: 0.1 }, shed: { w: 4, d: 3, h: 2.4, alpha: 0.1 }
    },
    t60Indoor: 1.0, t60Outdoor: 0.4,
    // Repetition pitch: feed-forward comb at tau = 2r/c for r <= maxM.
    rp: { maxM: 2 },
    // Click ping: ~8 ms, 3.2 kHz (the old bip stays as the pingBip setting).
    ping: { clickMs: 8, clickHz: 3200 },
    // Floor bounce: every ping returns a short floor echo (eye height eyeM), shaped by the floor material; absDb = extra dB per unit alpha.
    floor: { eyeM: 1.6, delay: 0.035, db: -16, absDb: 20, minAmp: 0.06 },
    // Ceiling bounce (v0.11.9): indoors every ping also returns off the ceiling, delayed like the floor bounce scaled by the gap above the head.
    ceil: { minGap: 0.012, defaultH: 3, defaultMat: 'stone', db: -16, absDb: 20, minAmp: 0.06 },
    ceilMat: {
      crypt: 'stone', mausoleum: 'stone', cellar: 'stone', church: 'roughStone',
      tavern: 'wood', house1: 'wood', house2: 'wood', barn: 'wood', shed: 'wood'
    },
    // Solid props as reflectors (sonar equation, ts.prop): material per type, strongest few per ping.
    propMat: { barrel: 'wood', bench: 'wood', chair: 'wood', table: 'wood', gravestone: 'stone', brazier: 'iron', well: 'roughStone' },
    propEcho: { max: 3, minAmp: 0.06 },
    // Enclosure: per-ping reverb send multiplier (see A.wetFor).
    wet: { min: 0.1, max: 1.5, gain: 0.75, absorb: 0.8, scatter: 0.03, scatterMax: 8, base: 0 }
  };
  const EPS = 1e-9;
  function num(v, d) { return typeof v === 'number' && isFinite(v) ? v : d; }
  function log10(x) { return Math.log(x) / Math.LN10; }
  function clampN(v, lo, hi) { return v < lo ? lo : v > hi ? hi : v; }

  /** Mouth beam B(theta) in dB for an angle (radians) off the facing direction; symmetric, linear between nodes. */
  A.beam = function (theta) {
    let a = Math.abs(num(theta, 0)) % (Math.PI * 2);
    if (a > Math.PI) a = Math.PI * 2 - a;
    const k = ((a * 180) / Math.PI) / A.beamStepDeg;
    const t = A.beamDb;
    const i = Math.min(t.length - 2, Math.floor(k + EPS));
    return t[i] + (t[i + 1] - t[i]) * (k - i);
  };
  /** Visual brightness factor 0.15..1 for a level in dB (used by the sonar for the beam). */
  A.visFactor = function (db) { return clampN(1 + num(db, 0) / A.visDb, A.visMin, 1); };
  A.matOf = function (name) { return Object.prototype.hasOwnProperty.call(A.mat, name) ? A.mat[name] : A.mat.stone; };
  A.roughOf = function (name) { return A.matOf(name).rough; };
  /**
   * Echo level (dB re the on-axis click at 1 m). kind 'wall' (image source, 2r), 'prop' or 'person' (sonar equation + target strength).
   * rCells in cells, theta off the facing direction (radians), mat a material name (walls only).
   */
  A.echoLevel = function (kind, rCells, theta, mat) {
    const r = Math.max(num(rCells, 0) * A.cellM, A.rMin);
    const air = 2 * r * A.airDbPerM;
    let L = A.beam(theta);
    if (kind === 'wall') {
      const m = A.matOf(mat);
      L += -A.spread.wall * log10(2 * r) + 10 * log10((1 - m.alpha) * (1 - m.s)) - air;
    } else {
      L += -A.spread.object * log10(r) + (kind === 'person' ? A.ts.person : A.ts.prop) - air;
    }
    return L;
  };
  /** Game amplitude 0..1 for a level in dB (compressed by gameKappa, never below gameMin). */
  A.gameAmp = function (db) { return clampN(Math.pow(10, (A.gameKappa * (num(db, A.gameRefDb) - A.gameRefDb)) / 20), A.gameMin, 1); };
  /** Person echo amplitude 0..1 (object sonar equation -40 log r + TS + class gain, compressed like walls) at rCells, theta off the facing direction. */
  A.personAmp = function (rCells, theta) { return A.gameAmp(A.echoLevel('person', rCells, theta) + A.personGainDb); };
  /** Floor-bounce level (dB): image source at the eye height, floor material loss, softer by floor.db and floor.absDb x alpha (grass ~silent). */
  A.floorLevel = function (mat) {
    const f = A.floor;
    return A.echoLevel('wall', f.eyeM / A.cellM, 0, mat) + f.db - f.absDb * A.matOf(mat).alpha;
  };
  /** Floor-bounce amplitude 0..1 for a floor material; 0 when it is below floor.minAmp (nothing worth playing). */
  A.floorAmp = function (mat) { const a = A.gameAmp(A.floorLevel(mat)); return a < A.floor.minAmp ? 0 : a; };

  /** Ceiling of a zone/map name: {h metres above the floor, mat}. Unknown names get ceil.defaultH / defaultMat. */
  A.ceilingFor = function (name) {
    const has = typeof name === 'string' && Object.prototype.hasOwnProperty.call(A.zone, name);
    return {
      h: has ? A.zone[name].h : A.ceil.defaultH,
      mat: typeof name === 'string' && Object.prototype.hasOwnProperty.call(A.ceilMat, name) ? A.ceilMat[name] : A.ceil.defaultMat
    };
  };
  /** Ceiling-bounce level (dB): image source at the gap above the head, ceiling material loss, softer by ceil.db and ceil.absDb x alpha. */
  A.ceilLevel = function (h, mat) {
    const c = A.ceil;
    const gap = Math.max(num(h, c.defaultH) - A.floor.eyeM, 0.3);
    return A.echoLevel('wall', gap / A.cellM, 0, mat) + c.db - c.absDb * A.matOf(mat).alpha;
  };
  /** Ceiling-bounce amplitude 0..1; 0 when below ceil.minAmp. */
  A.ceilAmp = function (h, mat) { const a = A.gameAmp(A.ceilLevel(h, mat)); return a < A.ceil.minAmp ? 0 : a; };
  /** Ceiling-bounce delay (s): the floor bounce delay scaled by the gap above the head over the eye height (a tall church returns later). */
  A.ceilDelay = function (h) {
    const d = (A.floor.delay * Math.max(num(h, A.ceil.defaultH) - A.floor.eyeM, 0.3)) / A.floor.eyeM;
    // Keep it clear of the floor bounce so the two stay distinct reflections instead of fusing into one flammed click.
    return Math.abs(d - A.floor.delay) < A.ceil.minGap ? A.floor.delay + A.ceil.minGap : d;
  };
  /** Prop echo amplitude 0..1 for a prop type at rCells, theta off the facing direction; 0 when below propEcho.minAmp. */
  A.propAmp = function (rCells, theta) { const a = A.gameAmp(A.echoLevel('prop', rCells, theta)); return a < A.propEcho.minAmp ? 0 : a; };
  /**
   * Per-ping reverb send multiplier (1 = the room's static send) from how enclosed the ping is: hitFrac 0..1 of rays that met a surface in
   * range, meanAlpha mean absorption of those surfaces, scatterers solid props + people in range, indoor (a ceiling always closes the room).
   */
  A.wetFor = function (hitFrac, meanAlpha, scatterers, indoor) {
    const w = A.wet;
    const h = clampN(num(hitFrac, 0), 0, 1);
    const enc = indoor ? 0.5 + 0.5 * h : 0.9 * h;
    const v = w.gain * enc * (1 - w.absorb * clampN(num(meanAlpha, 0), 0, 1)) + w.scatter * Math.min(Math.max(num(scatterers, 0), 0), w.scatterMax) + w.base;
    return clampN(v, w.min, w.max);
  };

  /** Sabine RT60 = 0.161 V / A for a box w x d cells (cellM) of height h m and mean absorption alpha, clamped to t60Min..t60Max. */
  A.sabine = function (w, d, h, alpha) {
    const W = w * A.cellM;
    const D = d * A.cellM;
    const V = W * D * h;
    const S = 2 * (W * D + (W + D) * h);
    return clampN((0.161 * V) / (S * alpha), A.t60Min, A.t60Max);
  };
  /** Reverb T60 (s) for a zone/map name; unknown names use the kind default. */
  A.t60For = function (name, kind) {
    const z = typeof name === 'string' && Object.prototype.hasOwnProperty.call(A.zone, name) ? A.zone[name] : null;
    if (z) return A.sabine(z.w, z.d, z.h, z.alpha);
    return kind === 'outdoor' ? A.t60Outdoor : A.t60Indoor;
  };
  /** Comb feedback gain for delay tau (s) at reverb time t60 (s), t60 clamped to t60Min..t60Max. */
  A.combGain = function (tau, t60) { return Math.pow(10, (-3 * tau) / clampN(num(t60, 1), A.t60Min, A.t60Max)); };
  /** Maekawa diffraction loss (dB) for path difference delta (m) at hz: 10 log10(3 + 20 N), N = 2 delta / lambda, capped. */
  A.maekawa = function (delta, hz) {
    const lam = A.c / (hz || A.maekawaHz);
    const N = Math.max(0, (2 * num(delta, 0)) / lam);
    return Math.min(A.maekawaCapDb, 10 * log10(3 + 20 * N));
  };
  /** Transmission loss (dB at 500 Hz) of a material, composite with its gap fraction when it has one (closed door). */
  A.tlOf = function (name) {
    const m = A.matOf(name);
    if (!m.gap) return m.tl500;
    return -10 * log10((1 - m.gap) * Math.pow(10, -m.tl500 / 10) + m.gap);
  };
  /**
   * Occlusion effect of a blocking material, optionally with a doorway diffraction loss (dB, null when none).
   * loss = min(TL, Maekawa); returns {loss, gain, lpHz, peakHz, peakDb, diffracted}.
   */
  A.occlusion = function (name, diffDb) {
    const m = A.matOf(name);
    const tl = A.tlOf(name);
    const diff = typeof diffDb === 'number' && isFinite(diffDb) && diffDb < tl;
    const loss = diff ? diffDb : tl;
    return {
      loss: loss,
      gain: Math.max(A.occMin, Math.pow(10, (-A.occK * loss) / 20)),
      lpHz: A.occCutoffHz * Math.pow(10, -loss / 40),
      peakHz: diff ? 0 : m.peakHz || 0,
      peakDb: diff ? 0 : m.peakDb || 0,
      diffracted: diff
    };
  };
  /** Repetition-pitch comb for a reflector r cells away: {tau (s), gain} or null beyond rp.maxM. */
  A.repetition = function (rCells) {
    const r = num(rCells, Infinity) * A.cellM;
    if (!(r > 0) || r > A.rp.maxM) return null;
    return { tau: (2 * r) / A.c, gain: 0.5 };
  };

  const SoundData = {
    levels: {
      step: { range: 1.1, strength: 0.3, z: 0, fade: 0.8, bounces: 0, gain: 0.08, interval: 0.48, footOffset: 0.15, footSide: 0.12 },
      personStep: { range: 0.2, strength: 0.2, z: 0, fade: 0.6, bounces: 0, gain: 0.12, hearDist: 9 },
      door: { range: 5, strength: 0.5, z: 0.5, fade: 2.5, bounces: 1, gain: 0.25, hearDist: 18 },
      interact: { range: 3, strength: 0.35, z: 0.3, fade: 1.8, bounces: 1, gain: 0.15 },
      ping: { range: null, strength: 1, z: 0.62, fade: null, bounces: 2, gain: null },
      scream: { range: 7, strength: 0.6, z: 0.85, fade: 2.2, bounces: 1, gain: 0.3, hearDist: 25 },
      startle: { range: 1.5, strength: 0.3, z: 0.8, fade: 1.0, bounces: 0, gain: 0.1, hearDist: 12 },
      creak: { range: 3, strength: 0.4, z: 0.5, fade: 1.5, bounces: 0, gain: 0.2, hearDist: 12 },
      chime: { range: 0, strength: 0, z: 0.9, fade: 1, bounces: 0, gain: 0.22 },
      heartbeat: { range: 2.2, strength: 0.45, z: 0.6, fade: 1.2, bounces: 0, gain: 0.25 },
      feed: { range: 0, strength: 0, z: 0.5, fade: 1, bounces: 0, gain: 0.15 },
      gulp: { range: 0, strength: 0, z: 0.5, fade: 1, bounces: 0, gain: 0.2 },
      struggle: { range: 2.8, strength: 0.4, z: 0.5, fade: 1.0, bounces: 0, gain: 0.16, hearDist: 10 },
      clatter: { range: 7, strength: 0.55, z: 0.05, fade: 1.6, bounces: 1, gain: 0.26, hearDist: 22 },
      scuffle: { range: 1.4, strength: 0.28, z: 0.1, fade: 0.7, bounces: 0, gain: 0.1, hearDist: 8 },
      gasp: { range: 4, strength: 0.4, z: 0.8, fade: 1.2, bounces: 0, gain: 0.2, hearDist: 12 },
      miss: { range: 0, strength: 0, z: 0.5, fade: 0.5, bounces: 0, gain: 0.12 },
      yawn: { range: 0, strength: 0, z: 0.5, fade: 1, bounces: 0, gain: 0.15 },
      shriek: { range: null, strength: 1, z: 0.6, fade: null, bounces: 2, gain: 0.35 },
      mist: { range: 0.8, strength: 0.2, z: 0.3, fade: 0.5, bounces: 0, gain: 0.12 },
      still: { range: 0, strength: 0, z: 0.5, fade: 1, bounces: 0, gain: 0.12 },
      gift: { range: 0, strength: 0, z: 0.6, fade: 1, bounces: 0, gain: 0.18 },
      whimper: { range: 2, strength: 0.25, z: 0.6, fade: 1, bounces: 0, gain: 0.1, hearDist: 6 },
      overflow: { range: 0, strength: 0, z: 0.5, fade: 0.4, bounces: 0, gain: 0.06 },
      // ambience beds (gain = level at level01 1, volume 1; wind stays under -30 dBFS) and far/near atmosphere
      wind: { range: 0, strength: 0, z: 0.5, fade: 1, bounces: 0, gain: 0.025 },
      room: { range: 0, strength: 0, z: 0.5, fade: 1, bounces: 0, gain: 0.02 },
      dog: { range: 0, strength: 0, z: 0.5, fade: 1, bounces: 0, gain: 0.2, hearDist: 60 },
      bell: { range: 0, strength: 0, z: 0.9, fade: 1, bounces: 0, gain: 0.3, hearDist: 80 },
      breath: { range: 0, strength: 0, z: 0.7, fade: 1, bounces: 0, gain: 0.018, hearDist: 6 },
      // villager heartbeat: heard and shown (a small chest-high pulse per beat) out to 3 cells (+20% from 2.5), gain +15%
      vheart: { range: 0.5, strength: 1, z: 0.65, fade: 1.3, bounces: 0, gain: 0.069, hearDist: 3 }
    },
    // Villager step scaling (multipliers on the personStep row): gait x floor. Room (indoor/outdoor) scaling is applied on top by the game.
    stepScaleTable: {
      gait: {
        sneak: { range: 0.6, strength: 0.6, fade: 0.8, gain: 0.55 },
        walk: { range: 1, strength: 1, fade: 1, gain: 1 },
        run: { range: 1.8, strength: 1.6, fade: 1.2, gain: 1.8 }
      },
      floor: {
        grass: { range: 0.6, strength: 0.6, fade: 0.8, gain: 0.7 },
        wood: { range: 1, strength: 1, fade: 1, gain: 1 },
        stone: { range: 1.3, strength: 1.2, fade: 1.2, gain: 1.1 }
      }
    },
    rooms: {
      indoor: { rangeMul: 1, bounceCap: 2, fadeMul: 1 },
      outdoor: { rangeMul: 1.3, bounceCap: 1, fadeMul: 0.8 }
    },
    react: {
      startleDist: 3, seeDist: 8, seeCone: 2.0944, bumpDist: 1, fleeMul: 1.6, calmAfter: 10,
      screamGap: 2, startleTime: 1, arriveGrace: 1, lightSeen: 0.3, shriekMul: 2.5,
      bumpArc: 1.7453, bumpBackDist: 0.5, bumpFreeze: 0.4, waryTime: 20
    },
    reach: 1.3,
    reachArc: Math.PI / 3,
    maxBounceEchoes: 4,
    acoustics: A
  };

  /**
   * Multipliers {range, strength, fade, gain} for one villager step from gait (sneak|walk|run), floor (grass|wood|stone)
   * and pace (stride speed / default, clamped 0.8..1.25: slow elders are quieter, brisk walkers louder). Unknown names act as walk / stone.
   */
  SoundData.stepScale = function (gait, floor, pace) {
    const g = SoundData.stepScaleTable.gait[gait] || SoundData.stepScaleTable.gait.walk;
    const f = SoundData.stepScaleTable.floor[floor] || SoundData.stepScaleTable.floor.stone;
    let k = typeof pace === 'number' && isFinite(pace) ? pace : 1;
    k = k < 0.8 ? 0.8 : k > 1.25 ? 1.25 : k;
    return { range: g.range * f.range * k, strength: g.strength * f.strength * k, fade: g.fade * f.fade, gain: g.gain * f.gain * k };
  };

  VCS.SoundData = SoundData;
  if (typeof module !== 'undefined' && module.exports) module.exports = SoundData;
})(typeof window !== 'undefined' ? window : globalThis);
