(function (root) {
  'use strict';
  const VCS = (root.VCS = root.VCS || {});

  // Secondary echo rings (spawned where a wavefront strikes a person or marker)
  // and the "line quivers as the wavefront passes" helper used by the renderer.
  const WOBBLE_DUR = 0.45;
  const WOBBLE_FREQ = 34;

  /** Vibration -1..1 for a surface struck age seconds ago; 0 outside [0, WOBBLE_DUR). */
  function wobble(age, phase) {
    if (!(age >= 0) || age >= WOBBLE_DUR) return 0;
    const k = 1 - age / WOBBLE_DUR;
    return Math.sin(age * WOBBLE_FREQ + (phase || 0)) * k * k;
  }

  // Bands and a travelling displacement that flow over a figure/marker from feet to head.
  const BAND_DUR = 0.6;
  const BAND_OVER = 1.25;

  /** Normalised height (0..BAND_OVER) of the band front age seconds after a hit; -1 outside the window. */
  function bandFront(age) {
    if (!(age >= 0) || age >= BAND_DUR) return -1;
    return (age / BAND_DUR) * BAND_OVER;
  }

  /** Brightness gain 0..1 of the band at normalised height u (0 feet .. 1 head). */
  function bandGain(u, age) {
    const f = bandFront(age);
    if (f < 0) return 0;
    const d = (u - f) / 0.14;
    return Math.exp(-d * d) * (1 - age / BAND_DUR);
  }

  /** Lateral wave -1..1 at normalised height u: zero above the front, decaying behind it. */
  function wave(u, age) {
    const f = bandFront(age);
    if (f < 0 || u > f) return 0;
    const behind = f - u;
    return Math.sin(behind * 24) * Math.exp(-behind * 3.2) * (1 - age / BAND_DUR);
  }


  // ---- P5-QUIRK helpers: height mask, line boil, wavy rings, floor footstep rings ----
  const BOIL_FRAMES = 4;
  const BOIL_N = 256;
  const BOIL_FPS = 10;
  // Deterministic jitter table: BOIL_FRAMES x 2 axes x BOIL_N values in [-1, 1].
  const BOIL_TAB = new Float32Array(BOIL_FRAMES * 2 * BOIL_N);
  (function fillBoil() {
    let a = 0x9e3779b9;
    for (let i = 0; i < BOIL_TAB.length; i++) {
      a = (a + 0x6D2B79F5) >>> 0;
      let t = a;
      t = Math.imul(t ^ (t >>> 15), t | 1);
      t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
      BOIL_TAB[i] = (((t ^ (t >>> 14)) >>> 0) / 4294967296) * 2 - 1;
    }
  })();

  /** Boil frame 0..3 at time t (10 fps, 4 cycling seeds). */
  function boilFrame(t) {
    const f = Math.floor((t || 0) * BOIL_FPS);
    return ((f % BOIL_FRAMES) + BOIL_FRAMES) % BOIL_FRAMES;
  }

  /** Stable jitter -1..1 for (frame, id, axis 0|1). Same inputs always give the same value. */
  function jitter(frame, id, axis) {
    return BOIL_TAB[(((frame & 3) * 2 + (axis ? 1 : 0)) * BOIL_N) + (id & (BOIL_N - 1))];
  }

  /** Jitter that is exactly 0 when boil is disabled. */
  function boil(enabled, t, id, axis) {
    return enabled ? jitter(boilFrame(t), id, axis) : 0;
  }

  /** Jitter amplitude in internal px for a segment of the given length (0.4 base + ~1%, cap 1.5). */
  function jitterAmp(len) {
    const a = 0.4 + 0.01 * (len > 0 ? len : 0);
    return a > 1.5 ? 1.5 : a;
  }

  /** Ring radius with a slight wave: R * (1 + amp * sin(k * theta + t)). */
  function wavyRadius(R, theta, t, k, amp) {
    return R * (1 + (typeof amp === 'number' ? amp : 0.04) * Math.sin((k || 6) * theta + t));
  }

  /** Visibility 0..1 of a body part at height z for a lit band [zMin, zMax] with soft edges. */
  function maskAlpha(z, zMin, zMax, soft) {
    const s = soft > 0 ? soft : 0.12;
    if (z >= zMin && z <= zMax) return 1;
    const d = z < zMin ? zMin - z : z - zMax;
    return d >= s ? 0 : 1 - d / s;
  }

  /**
   * Split a figure (height 0..zTop) into horizontal strips by lit band. Fills out with
   * [zLow, zHigh, alpha] triples; returns the strip count (0..3). Edge strips use the soft alpha.
   */
  function maskStrips(zMin, zMax, zTop, soft, out) {
    const s = soft > 0 ? soft : 0.12;
    const lo = Math.max(0, Math.min(zMin, zMax));
    const hi = Math.min(zTop, Math.max(zMin, zMax));
    let n = 0;
    function add(a, b, al) {
      const za = Math.max(0, a);
      const zb = Math.min(zTop, b);
      if (zb - za < 1e-4 || al < 0.02) return;
      out[n * 3] = za; out[n * 3 + 1] = zb; out[n * 3 + 2] = al; n++;
    }
    add(lo - s, lo, maskAlpha(lo - s / 2, zMin, zMax, s));
    add(lo, hi, 1);
    add(hi, hi + s, maskAlpha(hi + s / 2, zMin, zMax, s));
    return n;
  }

  /** Floor footstep ring k (0..2): radius in cells at pulse age, or -1 when not visible. */
  function footRing(age, fade, range, k) {
    const u = age / fade - k * 0.2;
    if (!(u > 0) || u >= 1) return -1;
    return range * (0.3 + 0.7 * Math.sqrt(u));
  }

  /** Alpha 0..1 of floor footstep ring k at pulse age. */
  function footRingAlpha(age, fade, k) {
    const u = age / fade - k * 0.2;
    if (!(u > 0) || u >= 1) return 0;
    return Math.pow(1 - u, 1.5) * (1 - k * 0.22);
  }

  /** Create ring state. */
  function create(opts) {
    const o = opts || {};
    return { rings: [], maxRings: typeof o.maxRings === 'number' && o.maxRings > 0 ? Math.floor(o.maxRings) : 16 };
  }

  /** Spawn a ring at (x,y) at time t; returns the ring. */
  function spawn(state, x, y, t, opts) {
    const o = opts || {};
    const ring = {
      x: x, y: y, t0: t,
      kind: o.kind || 'marker',
      maxR: typeof o.maxR === 'number' ? o.maxR : 1.0,
      life: typeof o.life === 'number' && o.life > 0 ? o.life : 0.7,
      strength: typeof o.strength === 'number' ? o.strength : 1,
      delay: typeof o.delay === 'number' ? o.delay : 0,
      inward: o.inward === true,
      minR: typeof o.minR === 'number' && o.minR >= 0 ? o.minR : 0.15
    };
    state.rings.push(ring);
    while (state.rings.length > state.maxRings) state.rings.shift();
    return ring;
  }

  /** Ring radius in cells at time t (0 before it starts, maxR at end of life; inward rings shrink maxR to minR). */
  function radius(ring, t) {
    const f = (t - ring.t0 - ring.delay) / ring.life;
    if (ring.inward) {
      const c = f < 0 ? 0 : f > 1 ? 1 : f;
      const mn = typeof ring.minR === 'number' ? ring.minR : 0.15;
      return mn + (ring.maxR - mn) * (1 - c);
    }
    return Math.max(0, f) * ring.maxR;
  }

  /** Ring alpha 0..strength at time t. */
  function alpha(ring, t) {
    const f = (t - ring.t0 - ring.delay) / ring.life;
    if (f < 0 || f >= 1) return 0;
    return ring.strength * Math.pow(1 - f, 1.5);
  }

  /** Remove rings that have finished. */
  function prune(state, t) {
    const rs = state.rings;
    let w = 0;
    for (let i = 0; i < rs.length; i++) {
      const r = rs[i];
      if (t <= r.t0 + r.delay + r.life) rs[w++] = r;
    }
    rs.length = w;
  }

  const Ripple = {
    WOBBLE_DUR: WOBBLE_DUR, BAND_DUR: BAND_DUR, bandFront: bandFront, bandGain: bandGain, wave: wave, wobble: wobble, create: create, spawn: spawn,
    radius: radius, alpha: alpha, prune: prune,
    BOIL_TAB: BOIL_TAB, BOIL_N: BOIL_N, boilFrame: boilFrame, jitter: jitter, boil: boil, jitterAmp: jitterAmp,
    wavyRadius: wavyRadius, maskAlpha: maskAlpha, maskStrips: maskStrips, footRing: footRing, footRingAlpha: footRingAlpha
  };
  VCS.Ripple = Ripple;
  if (typeof module !== 'undefined' && module.exports) module.exports = Ripple;
})(typeof window !== 'undefined' ? window : globalThis);
