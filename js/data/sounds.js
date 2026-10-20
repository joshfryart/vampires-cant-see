(function (root) {
  'use strict';
  const VCS = (root.VCS = root.VCS || {});

  // Sound levels in one place. range in cells, strength 0..1 (visual), z = source height (floor 0, ceiling 1, eye 0.5), fade = seconds, gain 0..1 (audio), hearDist = audible cells.
  const SoundData = {
    levels: {
      step: { range: 1.1, strength: 0.3, z: 0, fade: 0.8, bounces: 0, gain: 0.08, interval: 0.48, footOffset: 0.15, footSide: 0.12 },
      personStep: { range: 0.7, strength: 0.35, z: 0, fade: 0.7, bounces: 0, gain: 0.12, hearDist: 9 },
      door: { range: 5, strength: 0.5, z: 0.5, fade: 2.5, bounces: 1, gain: 0.25, hearDist: 18 },
      interact: { range: 3, strength: 0.35, z: 0.3, fade: 1.8, bounces: 1, gain: 0.15 },
      ping: { range: null, strength: 1, z: 0.62, fade: null, bounces: 2, gain: null },
      scream: { range: 7, strength: 0.6, z: 0.85, fade: 2.2, bounces: 1, gain: 0.3, hearDist: 25 },
      startle: { range: 1.5, strength: 0.3, z: 0.8, fade: 1.0, bounces: 0, gain: 0.1, hearDist: 12 },
      creak: { range: 3, strength: 0.4, z: 0.5, fade: 1.5, bounces: 0, gain: 0.2, hearDist: 12 },
      chime: { range: 0, strength: 0, z: 0.9, fade: 1, bounces: 0, gain: 0.22 },
      heartbeat: { range: 2.2, strength: 0.45, z: 0.6, fade: 1.2, bounces: 0, gain: 0.25 },
      feed: { range: 0, strength: 0, z: 0.5, fade: 1, bounces: 0, gain: 0.15 },
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
      breath: { range: 0, strength: 0, z: 0.7, fade: 1, bounces: 0, gain: 0.05, hearDist: 6 }
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
    maxBounceEchoes: 4
  };

  // Echo acoustics constants (docs/SPEC-echoes.md section 3). Pure data, deep-frozen. Consumed by js/acoustics.js.
  // [estimate] tags: alpha for roughStone/cobble/iron/plaster, s for plaster, all sigmaH, plank/glass mass per area.
  SoundData.acoustics = (function deepFreeze(o) {
    Object.keys(o).forEach(function (k) { if (o[k] && typeof o[k] === 'object') deepFreeze(o[k]); });
    return Object.freeze(o);
  })({
    cellM: 1.0, c: 343, rMin: 0.5, rpMaxM: 2.0, kappa: 0.5,
    G: { wall: 0, prop: 6, person: 12 },
    TS: { person: -15, prop: -16.5 },
    maekawaCap: 24, Dvis: 36, vmin: 0.15,
    // alpha at 2 kHz, s (table model), sigmaH metres (kirchhoff model), m kg/m2 (mass law), tlCap dB (flat gain)
    mat: {
      stone: { alpha: 0.03, s: 0.1, sigmaH: 0.002, tlCap: 65 },
      brick: { alpha: 0.03, s: 0.15, sigmaH: 0.002, tlCap: 55 },
      plaster: { alpha: 0.04, s: 0.1, sigmaH: 0.002 },
      glass: { alpha: 0.02, s: 0.05, sigmaH: 0.002, m: 15, peak: { f: 2000, gainDb: 10, q: 1.4 } },
      wood: { alpha: 0.1, s: 0.3, sigmaH: 0.002 },
      roughStone: { alpha: 0.03, s: 0.35, sigmaH: 0.015, tlCap: 65 },
      cobble: { alpha: 0.05, s: 0.6, sigmaH: 0.025 },
      grass: { alpha: 0.6, s: 0.7, sigmaH: 0.04 },
      iron: { alpha: 0.02, s: 0.5, sigmaH: 0.002 },
      door: { alpha: 0.1, s: 0.3, sigmaH: 0.002, m: 24 },
      plank: { alpha: 0.1, s: 0.3, sigmaH: 0.002, m: 12 }
    },
    occlusion: { f0: 125 },
    // room T60 inputs: cells (Lc x Wc), height m, mean alpha
    zones: {
      crypt: { Lc: 12, Wc: 7, H: 3.0, alpha: 0.04 },
      tavern: { Lc: 18, Wc: 12, H: 3.5, alpha: 0.15 },
      church: { Lc: 16, Wc: 14, H: 8.0, alpha: 0.06 },
      house1: { Lc: 10, Wc: 8, H: 2.7, alpha: 0.12 }
    },
    t60Clamp: { min: 0.4, max: 2.5 },
    comb: { indoorMs: [37, 61, 97], outdoorMs: [19, 31, 47] }
  });

  VCS.SoundData = SoundData;
  if (typeof module !== 'undefined' && module.exports) module.exports = SoundData;
})(typeof window !== 'undefined' ? window : globalThis);
