'use strict';
// Spec docs/SPEC-echoes.md section 6, tests T1-T21 (T22 timing and T23 golden are not covered here).
const { describe } = require('node:test');

describe('acoustics.test.js', () => {
  const test = require('node:test');
  const assert = require('node:assert');
  const Log = require('../js/log.js');
  if (Log && typeof Log.setConsole === 'function') Log.setConsole(false);
  const SD = require('../js/data/sounds.js');
  const A = require('../js/acoustics.js');

  function near(a, b, tol, msg) {
    assert.ok(Math.abs(a - b) <= tol, (msg || '') + ' got ' + a + ' want ' + b + ' +-' + tol);
  }
  const DB = 0.05;
  const W = function (r, extra) { return A.levelWall(Object.assign({ thetaDeg: 0, rM: r, alpha: 0, s: 0, airDbPerM: 0 }, extra || {})); };
  const O = function (r, ts, extra) { return A.levelObject(Object.assign({ thetaDeg: 0, rM: r, ts: ts, airDbPerM: 0 }, extra || {})); };

  test('T1 toMeters', () => {
    near(A.toMeters(3, 1.0), 3.0, 0.001);
    near(A.toMeters(3, 1.5), 4.5, 0.001);
  });

  test('T2 wall Eq. W and T2b regression', () => {
    near(W(1), -6.021, DB); near(W(3), -15.563, DB); near(W(10), -26.021, DB);
    // formula without the factor 2 must not match
    const wrong = [1, 3, 10].map((r) => -20 * Math.log10(r));
    near(wrong[0], 0, 0.001); near(wrong[1], -9.542, 0.001); near(wrong[2], -20, 0.001);
    [1, 3, 10].forEach((r, i) => assert.ok(Math.abs(W(r) - wrong[i]) > 5));
  });

  test('T3 object Eq. O, person, prop', () => {
    near(O(1, 0), 0, DB); near(O(3, 0), -19.085, DB); near(O(10, 0), -40, DB);
    near(O(1, -15), -15, DB); near(O(3, -15), -34.085, DB); near(O(10, -15), -55, DB);
    near(10 * Math.log10(0.3 * 0.3 / 4), -16.478, 0.001);
    near(SD.acoustics.TS.prop, -16.5, 0.05);
    near(SD.acoustics.TS.person, -15, 0.001);
  });

  test('T4 wall with absorption and scattering', () => {
    near(W(3, { alpha: 0.03, s: 0.1 }), -16.153, DB);
  });

  test('T5 B_tx symmetry, monotonic, nodes', () => {
    let prev = Infinity;
    for (let t = 0; t <= 180; t += 5) {
      assert.strictEqual(A.bTx(t), A.bTx(-t));
      assert.ok(A.bTx(t) <= prev + 1e-12, 'non-increasing at ' + t);
      prev = A.bTx(t);
    }
    assert.strictEqual(A.bTx(0), 0);
    assert.strictEqual(A.bTx(180), -18);
    near(A.bTx(45), -2.0, 1e-9); near(A.bTx(75), -4.0, 1e-9);
    near(A.bTx(135), -10.5, 1e-9); near(A.bTx(165), -15.5, 1e-9);
    [[0, 0], [30, -1], [60, -3], [90, -5], [120, -8], [150, -13], [180, -18]].forEach((p) => near(A.bTx(p[0]), p[1], 1e-9));
  });

  test('T6 no double beam', () => {
    const L0 = W(3);
    near(W(3, { thetaDeg: 90 }) - L0, -5, 1e-9);
    near(W(3, { thetaDeg: 180 }) - L0, -18, 1e-9);
    near(W(3, { thetaDeg: -90 }) - L0, -5, 1e-9);
  });

  test('T7 rxRear', () => {
    const L0 = W(3, { rxRear: true });
    near(W(3, { thetaDeg: 90, rxRear: true }) - L0, -5, 1e-9);
    near(W(3, { thetaDeg: 135, rxRear: true }) - L0, -12, 1e-9);
    near(W(3, { thetaDeg: 180, rxRear: true }) - L0, -21, 1e-9);
    assert.strictEqual(A.bRx(180, false), 0);
  });

  test('T8 energy budget', () => {
    [[0.03, 0.1], [0.05, 0.6], [0.6, 0.7], [0.02, 0.05]].forEach((p) => {
      const e = A.energySplit(p[0], p[1]);
      near(e.abs + e.spec + e.diff, 1, 1e-9);
    });
    const c = A.energySplit(0.05, 0.6);
    near(c.spec, 0.380, 0.001); near(c.specDb, -4.202, 0.001);
    near(c.diff, 0.570, 0.001); near(c.diffDb, -2.441, 0.001);
    near(A.energySplit(0.03, 0.1).diffDb, -10.132, 0.001);
  });

  test('T9 Lambert Eq. D', () => {
    const D = (al, s, r, ti) => A.levelDiffuse({ thetaDeg: 0, rM: r, alpha: al, s: s, area: 1, thetaIDeg: ti, airDbPerM: 0 });
    near(D(0.05, 0.6, 2, 0), -19.454, DB);
    near(D(0.05, 0.6, 2, 60), -25.475, DB);
    near(D(0.03, 0.1, 1, 0), -15.104, DB);
  });

  test('T10 Maekawa', () => {
    const cap = SD.acoustics.maekawaCap;
    near(A.maekawaDb({ losClear: true, N: 5, cap: cap }), 0, 0.01);
    near(A.maekawaDb({ losClear: false, N: 0, cap: cap }), 4.771, 0.01);
    near(A.maekawaDb({ losClear: false, N: 1, cap: cap }), 13.617, 0.01);
    near(A.fresnelN(0.5, 3400), 9.913, 0.001);
    near(A.maekawaDb({ losClear: false, N: A.fresnelN(0.5, 3400), cap: cap }), 23.037, 0.01);
    near(A.fresnelN(1.0, 3400), 19.825, 0.001);
    near(A.maekawaDb({ losClear: false, N: A.fresnelN(1.0, 3400), cap: cap }), 24.0, 0.01);
    near(10 * Math.log10(3 + 20 * A.fresnelN(1.0, 3400)), 26.015, 0.01);
    near(A.maekawaDb({ losClear: false, N: 100, cap: cap }), 24.0, 0.01);
  });

  test('T11 door occlusion filter vs mass law', () => {
    const f = A.occlusionFilter('door');
    assert.strictEqual(f.kind, 'lowpass');
    assert.strictEqual(f.f0, 125);
    near(f.gain, 0.0746, 0.0002);
    near(A.filterResponseDb(f, 500), -34.847, DB);
    near(A.filterResponseDb(f, 2000), -46.642, DB);
    near(-A.massLawTL(24, 500), -34.584, 0.001);
    near(-A.massLawTL(24, 2000), -46.625, 0.001);
    near(A.filterResponseDb(f, 500) - -A.massLawTL(24, 500), 0, 0.3);
    near(A.filterResponseDb(f, 2000) - -A.massLawTL(24, 2000), 0, 0.3);
    near(A.occlusionFilter('plank').gain, 0.1492, 0.0003);
    const g = A.occlusionFilter('glass');
    near(g.gain, 0.1194, 0.0003);
    assert.ok(g.peak && g.peak.f === 2000 && g.peak.gainDb === 10 && g.peak.q === 1.4);
  });

  test('T12 brick flat gain, not the filter', () => {
    const f = A.occlusionFilter('brick');
    assert.strictEqual(f.kind, 'flat');
    near(f.gain, 1.778e-3, 1e-5);
    near(A.filterResponseDb(f, 2000), -55.0, 0.001);
    near(A.filterResponseDb(f, 100), -55.0, 0.001);
    near(A.occlusionFilter('stone').gain, 5.62e-4, 1e-6);
    // the lowpass would have given -67.058 at 2 kHz
    const lp = 20 * Math.log10(4 * Math.pow(10, -55 / 20)) - 10 * Math.log10(1 + 256);
    near(lp, -67.058, 0.01);
    assert.ok(Math.abs(A.filterResponseDb(f, 2000) - lp) > 10);
  });

  test('T13 door 1 percent gap', () => {
    const exp = { 125: 18.093, 250: 19.439, 500: 19.853, 2000: 19.991 };
    Object.keys(exp).forEach((fk) => {
      const tl = A.massLawTL(24, Number(fk));
      near(A.gapComposite(tl, 0.01, Number(fk)), exp[fk], 0.01, fk);
    });
  });

  test('T14 Sabine cellM 1.0', () => {
    const z = SD.acoustics.zones;
    const T = (k) => A.sabineT60(Object.assign({ cellM: 1.0, airM: 0 }, z[k]));
    near(T('crypt'), 3.60, 0.01); near(T('tavern'), 1.26, 0.01);
    near(T('church'), 5.18, 0.01); near(T('house1'), 1.13, 0.01);
    near(A.eyringT60(Object.assign({ cellM: 1.0 }, z.crypt)), 3.52, 0.01);
  });

  test('T15 Sabine cellM 1.5 and air', () => {
    const z = SD.acoustics.zones;
    const T = (k, cm, m) => A.sabineT60(Object.assign({ cellM: cm, airM: m || 0 }, z[k]));
    near(T('crypt', 1.5), 4.16, 0.01); near(T('tavern', 1.5), 1.42, 0.01);
    near(T('church', 1.5), 6.26, 0.01); near(T('house1', 1.5), 1.29, 0.01);
    near(T('crypt', 1.0, 0.005641), 2.39, 0.01);
    near(T('crypt', 1.5, 0.005641), 2.63, 0.01);
  });

  test('T16 comb gain', () => {
    const taus = [0.037, 0.061, 0.097];
    [0.774, 0.656, 0.512].forEach((g, i) => near(A.combGain(taus[i], 1.0), g, 0.001));
    [0.903, 0.845, 0.765].forEach((g, i) => near(A.combGain(taus[i], 2.5), g, 0.001));
    [0.469, 0.774, 1.230].forEach((t, i) => near(A.impliedT60(taus[i], 0.58), t, 0.001));
    // clamp 0.4 .. 2.5
    near(A.combGain(0.037, 10), A.combGain(0.037, 2.5), 1e-12);
    near(A.combGain(0.037, 0.01), A.combGain(0.037, 0.4), 1e-12);
  });

  test('T17 air loss over 20 m', () => {
    const exp = { 500: 0.038, 1000: 0.074, 2000: 0.194, 3400: 0.490, 4000: 0.662, 8000: 2.368 };
    Object.keys(exp).forEach((f) => near(20 * A.airDbPerM(Number(f)), exp[f], 0.005, f));
  });

  test('T18 Kirchhoff s and Fraunhofer', () => {
    near(A.kirchhoffS(0.002, 3400, 0), 0.060, 0.001);
    near(A.kirchhoffS(0.015, 3400, 0), 0.970, 0.001);
    near(A.kirchhoffS(0.025, 3400, 80), 0.254, 0.001);
    near(A.fraunhoferM(3400, 0) * 100, 0.315, 0.001);
  });

  test('T19 physical delay and repetition pitch', () => {
    near(A.delayPhysical(A.toMeters(1, 1)) * 1000, 5.831, 0.001);
    near(A.delayPhysical(A.toMeters(1.3, 1)) * 1000, 7.580, 0.001);
    near(A.delayPhysical(A.toMeters(2, 1)) * 1000, 11.662, 0.001);
    near(A.repPitchHz(1), 171.5, 0.05); near(A.repPitchHz(1.3), 131.9, 0.05); near(A.repPitchHz(2), 85.75, 0.05);
  });

  test('T20 comb gating and feed-forward', () => {
    const max = SD.acoustics.rpMaxM;
    assert.strictEqual(A.repPitchActive(2.0, max), true);
    assert.strictEqual(A.repPitchActive(2.01, max), false);
    // feed-forward: impulse response is finite with exactly two taps (no feedback cycle)
    const x = new Array(200).fill(0); x[0] = 1;
    const y = A.ffComb(x, 0.5, 40);
    assert.deepStrictEqual(y.map((v, i) => (v ? i : -1)).filter((i) => i >= 0), [0, 40]);
    near(y[40], 0.5, 1e-12);
  });

  test('T21 visual brightness', () => {
    const d = SD.acoustics;
    near(A.visualBrightness(0, d.Dvis, d.vmin), 1.0, 0.001);
    near(A.visualBrightness(-18, d.Dvis, d.vmin), 0.5, 0.001);
    near(A.visualBrightness(-36, d.Dvis, d.vmin), 0.15, 0.001);
    near(A.visualBrightness(-100, d.Dvis, d.vmin), 0.15, 0.001);
    const Lp = O(10, d.TS.person);
    const Lg = A.gameLevel(Lp, 'person', 0.5, d.G);
    near(Lg, -15.5, DB);
    near(A.visualBrightness(Lg), 0.569, 0.001);
  });

  test('never throws on junk', () => {
    const junk = [undefined, null, NaN, Infinity, 'x', {}, []];
    junk.forEach((j) => {
      assert.doesNotThrow(() => {
        A.toMeters(j, j); A.bTx(j); A.bRx(j, j); A.levelWall(j); A.levelObject(j); A.levelDiffuse(j);
        A.gameLevel(j, j, j, j); A.dbToAmp(j); A.visualBrightness(j, j, j); A.energySplit(j, j);
        A.kirchhoffS(j, j, j); A.airDbPerM(j); A.maekawaDb(j); A.fresnelN(j, j); A.massLawTL(j, j);
        A.occlusionFilter(j); A.gapComposite(j, j, j); A.sabineT60(j); A.eyringT60(j); A.combGain(j, j);
        A.delayPhysical(j); A.repPitchHz(j); A.ffComb(j, j, j);
      });
    });
    assert.strictEqual(A.occlusionFilter('nope').ok, false);
    assert.strictEqual(A.occlusionFilter('nope').code, 'UNKNOWN_MATERIAL');
    assert.ok(isFinite(A.levelWall({ rM: 0 })));
    near(A.levelWall({ rM: 0, thetaDeg: 0 }), W(0.5), 1e-9);
  });

  test('acoustics data block is deep-frozen', () => {
    assert.ok(Object.isFrozen(SD.acoustics));
    assert.ok(Object.isFrozen(SD.acoustics.mat.door));
    assert.ok(Object.isFrozen(SD.acoustics.zones.crypt));
  });
});
