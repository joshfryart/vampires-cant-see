(function (root) {
  'use strict';
  const VCS = (root.VCS = root.VCS || {});

  // Pure acoustics maths for the echo model (docs/SPEC-echoes.md section 2). No DOM, no audio, never throws.
  // Levels are dB of intensity re the direct click at 1 m on axis. Distances in metres unless a name says cells.

  const C = 343;
  const R_MIN = 0.5;
  const BTX_NODES = [0, -1, -3, -5, -8, -13, -18]; // at 0,30,...,180 deg
  const R_REAR = -3;
  const LOG2NODES = [500, 1000, 2000, 3400, 4000, 8000];

  function logger() {
    try { return root.VCS && root.VCS.Log ? root.VCS.Log.get('acoustics') : null; } catch (e) { return null; }
  }
  function warn(msg, data) {
    try {
      const l = logger();
      if (l && typeof l.warn === 'function') l.warn(msg, data);
    } catch (e) { /* ignore */ }
  }
  function data() {
    try {
      if (root.VCS && root.VCS.SoundData && root.VCS.SoundData.acoustics) return root.VCS.SoundData.acoustics;
      if (typeof require === 'function') {
        const sd = require('./data/sounds.js');
        if (sd && sd.acoustics) return sd.acoustics;
      }
    } catch (e) { /* ignore */ }
    return null;
  }

  function isNum(x) { return typeof x === 'number' && isFinite(x); }
  function num(x, d) { return isNum(x) ? x : d; }
  function clamp(x, lo, hi) { return x < lo ? lo : x > hi ? hi : x; }
  function log10(x) { return Math.log(x) / Math.LN10; }
  function posNum(x, d) { return isNum(x) && x > 0 ? x : d; }

  function toMeters(cells, cellM) { return num(cells, 0) * posNum(cellM, 1); }

  /** Transmit beam, dB. Symmetric, linear between 30 deg nodes, non-increasing. */
  function bTx(thetaDeg) {
    let a = Math.abs(num(thetaDeg, 0)) % 360;
    if (a > 180) a = 360 - a;
    const i = Math.min(5, Math.floor(a / 30));
    const f = (a - i * 30) / 30;
    return BTX_NODES[i] + (BTX_NODES[i + 1] - BTX_NODES[i]) * f;
  }

  /** Receive beam: 0 unless rxRear, then -3 dB * (|theta|-90)/90 beyond 90 deg. */
  function bRx(thetaDeg, rxRear) {
    if (!rxRear) return 0;
    let a = Math.abs(num(thetaDeg, 0)) % 360;
    if (a > 180) a = 360 - a;
    return a <= 90 ? 0 : R_REAR * (a - 90) / 90;
  }

  function rEff(rM, rMin) { return Math.max(posNum(rMin, R_MIN), num(rM, 0) < 0 ? 0 : num(rM, 0)); }
  function airTerm(rM, airDbPerM) { return 2 * Math.max(0, num(rM, 0)) * Math.max(0, num(airDbPerM, 0)); }
  function tenLog(x) { return x > 0 ? 10 * log10(x) : -Infinity; }
  function finite(x) { return isNum(x) ? x : -200; }

  /** Eq. W, specular wall at the perpendicular foot (image source at 2r). */
  function levelWall(o) {
    o = o || {};
    const al = clamp(num(o.alpha, 0), 0, 1), s = clamp(num(o.s, 0), 0, 1);
    const r = rEff(o.rM, o.rMin);
    return finite(bTx(o.thetaDeg) + bRx(o.thetaDeg, o.rxRear) - 20 * log10(2 * r) +
      tenLog((1 - al) * (1 - s)) - airTerm(o.rM, o.airDbPerM));
  }

  /** Eq. O, compact object / person (sonar equation). */
  function levelObject(o) {
    o = o || {};
    const r = rEff(o.rM, o.rMin);
    return finite(bTx(o.thetaDeg) + bRx(o.thetaDeg, o.rxRear) - 40 * log10(r) +
      num(o.ts, 0) - airTerm(o.rM, o.airDbPerM));
  }

  /** Eq. D, diffuse Lambert patch of area A at incidence thetaI. */
  function levelDiffuse(o) {
    o = o || {};
    const al = clamp(num(o.alpha, 0), 0, 1), s = clamp(num(o.s, 0), 0, 1);
    const r = rEff(o.rM, o.rMin);
    const A = Math.max(0, num(o.area, 0));
    const ci = Math.cos(num(o.thetaIDeg, 0) * Math.PI / 180);
    return finite(bTx(o.thetaDeg) + bRx(o.thetaDeg, o.rxRear) +
      tenLog((1 - al) * s * A * ci * ci / Math.PI) - 40 * log10(r) - airTerm(o.rM, o.airDbPerM));
  }

  /** Game calibration: G_class + kappa * Lphys. cls in wall|prop|person; Gclass optional table or number. */
  function gameLevel(Lphys, cls, kappa, Gclass) {
    const d = data();
    const tbl = Gclass && typeof Gclass === 'object' ? Gclass : (d ? d.G : { wall: 0, prop: 6, person: 12 });
    let g = 0;
    if (isNum(Gclass)) g = Gclass;
    else if (tbl && isNum(tbl[cls])) g = tbl[cls];
    else warn('unknown class, G=0', { cls: cls });
    const k = clamp(num(kappa, d ? d.kappa : 1), 0, 1);
    return g + k * num(Lphys, 0);
  }

  function dbToAmp(db) { return Math.pow(10, num(db, 0) / 20); }

  /** Visual brightness 2.10: clamp(1 + L/Dvis, vmin, 1). */
  function visualBrightness(Lgame, Dvis, vmin) {
    const d = data();
    const D = posNum(Dvis, d ? d.Dvis : 36);
    const lo = clamp(num(vmin, d ? d.vmin : 0.15), 0, 1);
    return clamp(1 + num(Lgame, 0) / D, lo, 1);
  }

  /** Energy budget: abs + spec + diff = 1. */
  function energySplit(alpha, s) {
    const a = clamp(num(alpha, 0), 0, 1), sv = clamp(num(s, 0), 0, 1);
    const spec = (1 - a) * (1 - sv), diff = (1 - a) * sv;
    return { abs: a, spec: spec, diff: diff, specDb: tenLog(spec), diffDb: tenLog(diff), sum: a + spec + diff };
  }

  /** Kirchhoff roughness scattering fraction s(f, thetaI). */
  function kirchhoffS(sigma, fHz, thetaIDeg) {
    const k = 2 * Math.PI * Math.max(0, num(fHz, 0)) / C;
    const x = 2 * k * Math.max(0, num(sigma, 0)) * Math.cos(num(thetaIDeg, 0) * Math.PI / 180);
    return 1 - Math.exp(-x * x);
  }

  /** Fraunhofer smooth limit, metres: lambda / (32 cos thetaI). */
  function fraunhoferM(fHz, thetaIDeg) {
    const ci = Math.max(1e-6, Math.cos(num(thetaIDeg, 0) * Math.PI / 180));
    return (C / posNum(fHz, 3400)) / (32 * ci);
  }

  /** Air absorption, dB/m, ISO 9613-1 at 10 C, 70 % RH, 101.325 kPa. */
  function airDbPerM(fHz) {
    const f = Math.max(0, num(fHz, 0));
    const T = 283.15, T0 = 293.15, T01 = 273.16, hr = 70, pr = 1;
    const pa = 1; // pa/pr
    const C0 = -6.8346 * Math.pow(T01 / T, 1.261) + 4.6151;
    const h = hr * Math.pow(10, C0) * pr / pa;
    const frO = pa * (24 + 4.04e4 * h * (0.02 + h) / (0.391 + h));
    const frN = pa * Math.pow(T / T0, -0.5) * (9 + 280 * h * Math.exp(-4.170 * (Math.pow(T / T0, -1 / 3) - 1)));
    return 8.686 * f * f * (
      1.84e-11 * Math.pow(T / T0, 0.5) / pa +
      Math.pow(T / T0, -2.5) * (
        0.01275 * Math.exp(-2239.1 / T) / (frO + f * f / frO) +
        0.1068 * Math.exp(-3352 / T) / (frN + f * f / frN)));
  }

  /** Maekawa diffraction loss, dB. losClear -> 0; else min(cap, 10 log10(3 + 20 N)). */
  function maekawaDb(o) {
    o = o || {};
    if (o.losClear) return 0;
    const d = data();
    const cap = posNum(o.cap, d ? d.maekawaCap : 24);
    const N = Math.max(0, num(o.N, 0));
    return Math.min(cap, 10 * log10(3 + 20 * N));
  }

  function fresnelN(deltaM, fHz) {
    return 2 * Math.max(0, num(deltaM, 0)) * Math.max(0, num(fHz, 0)) / C;
  }

  /** Field-incidence mass law, dB: 20 log10(m f) - 47. */
  function massLawTL(m, f) {
    const p = posNum(m, 0) * posNum(f, 0);
    return p > 0 ? 20 * log10(p) - 47 : 0;
  }

  /**
   * Occlusion filter for a material key (or a material object).
   * mass materials -> {kind:'lowpass', f0, gain, peak?}; capped -> {kind:'flat', f0:0, gain}. Unknown -> {ok:false,code}.
   */
  function occlusionFilter(material) {
    const d = data();
    const m = typeof material === 'string' ? (d && d.mat ? d.mat[material] : null) : material;
    if (!m || typeof m !== 'object') return { ok: false, code: 'UNKNOWN_MATERIAL' };
    if (isNum(m.tlCap)) {
      return { ok: true, kind: 'flat', f0: 0, gain: Math.pow(10, -m.tlCap / 20) };
    }
    if (isNum(m.m) && m.m > 0) {
      const f0 = d && d.occlusion ? d.occlusion.f0 : 125;
      const out = { ok: true, kind: 'lowpass', f0: f0, gain: (500 / f0) * Math.pow(10, -massLawTL(m.m, 500) / 20) };
      if (m.peak) out.peak = { f: m.peak.f, gainDb: m.peak.gainDb, q: m.peak.q };
      return out;
    }
    return { ok: false, code: 'NO_TRANSMISSION_DATA' };
  }

  /** Magnitude response in dB of an occlusionFilter result at f (for tests / diagnostics). */
  function filterResponseDb(flt, f) {
    if (!flt || flt.ok === false) return 0;
    const g = 20 * log10(Math.max(1e-12, flt.gain));
    if (flt.kind === 'flat') return g;
    const r = num(f, 0) / flt.f0;
    return g - 10 * log10(1 + r * r);
  }

  /** Composite TL (dB) of a wall with a gap of fraction gapFrac (open path = 0 dB); tlDb may be a number (flat) or
   *  a mass-law m with f. Here tlDb is the panel TL at f. */
  function gapComposite(tlDb, gapFrac, f) {
    const g = clamp(num(gapFrac, 0), 0, 1);
    void f;
    const tau = (1 - g) * Math.pow(10, -num(tlDb, 0) / 10) + g;
    return -10 * log10(tau);
  }

  function roomT60(o, eyring) {
    o = o || {};
    const d = data();
    const cm = posNum(o.cellM, d ? d.cellM : 1);
    const L = posNum(o.Lc, 1) * cm, W = posNum(o.Wc, 1) * cm, H = posNum(o.H, 3);
    const V = L * W * H, S = 2 * (L * W + L * H + W * H);
    const a = clamp(num(o.alpha, 0.1), 1e-4, 0.999);
    const m = Math.max(0, num(o.airM, 0));
    const absorb = eyring ? -S * Math.log(1 - a) : S * a;
    return 0.161 * V / (absorb + 4 * m * V);
  }
  function sabineT60(o) { return roomT60(o, false); }
  function eyringT60(o) { return roomT60(o, true); }

  /** Comb feedback gain 10^(-3 tau / T60), T60 clamped 0.4..2.5 s. */
  function combGain(tauSec, t60) {
    const d = data();
    const cl = d && d.t60Clamp ? d.t60Clamp : { min: 0.4, max: 2.5 };
    const t = clamp(num(t60, 1), cl.min, cl.max);
    return Math.pow(10, -3 * Math.max(0, num(tauSec, 0)) / t);
  }
  /** T60 implied by a fixed feedback gain. */
  function impliedT60(tauSec, g) {
    const gg = clamp(num(g, 0.5), 1e-6, 0.999999);
    return -3 * Math.max(0, num(tauSec, 0)) / log10(gg);
  }

  function delayPhysical(rM) { return 2 * Math.max(0, num(rM, 0)) / C; }
  function repPitchHz(rM) { return C / (2 * Math.max(0.01, num(rM, 0.01))); }
  function repPitchActive(rM, maxM) {
    const d = data();
    return num(rM, Infinity) <= posNum(maxM, d ? d.rpMaxM : 2.0);
  }

  /** Feed-forward comb y[n] = x[n] + g x[n-D] (FIR, no feedback cycle). */
  function ffComb(x, g, delaySamples) {
    const src = Array.isArray(x) || ArrayBuffer.isView(x) ? x : [];
    const D = Math.max(0, Math.floor(num(delaySamples, 0)));
    const gg = num(g, 0);
    const y = new Array(src.length);
    for (let n = 0; n < src.length; n++) y[n] = src[n] + (n >= D ? gg * src[n - D] : 0);
    return y;
  }

  const Acoustics = {
    C: C, R_MIN: R_MIN,
    toMeters: toMeters, bTx: bTx, bRx: bRx,
    levelWall: levelWall, levelObject: levelObject, levelDiffuse: levelDiffuse,
    gameLevel: gameLevel, dbToAmp: dbToAmp, visualBrightness: visualBrightness,
    energySplit: energySplit, kirchhoffS: kirchhoffS, fraunhoferM: fraunhoferM, airDbPerM: airDbPerM,
    maekawaDb: maekawaDb, fresnelN: fresnelN,
    massLawTL: massLawTL, occlusionFilter: occlusionFilter, filterResponseDb: filterResponseDb, gapComposite: gapComposite,
    sabineT60: sabineT60, eyringT60: eyringT60, combGain: combGain, impliedT60: impliedT60,
    delayPhysical: delayPhysical, repPitchHz: repPitchHz, repPitchActive: repPitchActive, ffComb: ffComb
  };
  VCS.Acoustics = Acoustics;
  if (typeof module !== 'undefined' && module.exports) module.exports = Acoustics;
})(typeof window !== 'undefined' ? window : globalThis);
