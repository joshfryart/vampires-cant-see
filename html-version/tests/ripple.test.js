'use strict';
// Merged test file: each source file's tests live in their own describe().
const { describe } = require('node:test');

describe('ripple.test.js', () => {

  const test = require('node:test');
  const assert = require('node:assert');
  const Ripple = require('../js/ripple.js');

  test('wobble is zero outside its window and bounded inside', () => {
    assert.strictEqual(Ripple.wobble(-0.1, 0), 0);
    assert.strictEqual(Ripple.wobble(Ripple.WOBBLE_DUR, 0), 0);
    assert.strictEqual(Ripple.wobble(NaN, 0), 0);
    let max = 0;
    for (let a = 0; a < Ripple.WOBBLE_DUR; a += 0.005) max = Math.max(max, Math.abs(Ripple.wobble(a, 1.3)));
    assert.ok(max <= 1 && max > 0.5);
    assert.ok(Math.abs(Ripple.wobble(Ripple.WOBBLE_DUR - 0.001, 0)) < 0.01, 'decays to ~0 at end');
  });

  test('spawn, cap, radius, alpha, delay, prune', () => {
    const st = Ripple.create({ maxRings: 3 });
    for (let i = 0; i < 5; i++) Ripple.spawn(st, i, 0, 0, { life: 1, maxR: 2 });
    assert.strictEqual(st.rings.length, 3);
    assert.strictEqual(st.rings[0].x, 2);
    const r = st.rings[0];
    assert.strictEqual(Ripple.radius(r, 0), 0);
    assert.ok(Math.abs(Ripple.radius(r, 0.5) - 1) < 1e-9);
    assert.ok(Math.abs(Ripple.radius(r, 1) - 2) < 1e-9);
    assert.strictEqual(Ripple.alpha(r, 0), 1);
    assert.ok(Ripple.alpha(r, 0.5) > 0 && Ripple.alpha(r, 0.5) < 1);
    assert.strictEqual(Ripple.alpha(r, 1), 0);
    const d = Ripple.spawn(st, 0, 0, 0, { delay: 0.5, life: 1, strength: 0.5 });
    assert.strictEqual(Ripple.alpha(d, 0.2), 0);
    assert.strictEqual(Ripple.radius(d, 0.2), 0);
    assert.ok(Math.abs(Ripple.alpha(d, 0.5) - 0.5) < 1e-9);
    Ripple.prune(st, 1.2);
    assert.strictEqual(st.rings.length, 1);
    assert.strictEqual(st.rings[0], d);
    Ripple.prune(st, 2);
    assert.strictEqual(st.rings.length, 0);
  });

  test('band front rises with age and is only active inside the window', () => {
    assert.strictEqual(Ripple.bandFront(-0.1), -1);
    assert.strictEqual(Ripple.bandFront(Ripple.BAND_DUR), -1);
    assert.ok(Ripple.bandFront(0.1) < Ripple.bandFront(0.3));
    assert.strictEqual(Ripple.bandGain(0.5, -1), 0);
    assert.strictEqual(Ripple.bandGain(0.5, 0.9), 0);
    const age = 0.2;
    const f = Ripple.bandFront(age);
    assert.ok(Ripple.bandGain(f, age) > Ripple.bandGain(f + 0.5, age));
    assert.ok(Ripple.bandGain(f, age) <= 1);
  });

  test('wave is zero above the front and bounded behind it', () => {
    const age = 0.15;
    const f = Ripple.bandFront(age);
    assert.strictEqual(Ripple.wave(f + 0.1, age), 0);
    let max = 0;
    for (let u = 0; u < f; u += 0.01) max = Math.max(max, Math.abs(Ripple.wave(u, age)));
    assert.ok(max > 0.05 && max <= 1);
    assert.strictEqual(Ripple.wave(0.1, 5), 0);
  });

  test('boil jitter is deterministic per (frame, id), bounded, and zero when disabled', () => {
    for (let f = 0; f < 4; f++) {
      for (let id = 0; id < 300; id += 7) {
        for (let ax = 0; ax < 2; ax++) {
          const v = Ripple.jitter(f, id, ax);
          assert.strictEqual(v, Ripple.jitter(f, id, ax));
          assert.ok(v >= -1 && v <= 1);
        }
      }
    }
    assert.notStrictEqual(Ripple.jitter(0, 5, 0), Ripple.jitter(1, 5, 0));
    assert.strictEqual(Ripple.boil(false, 1.234, 9, 0), 0);
    assert.strictEqual(Ripple.boil(true, 0.35, 9, 1), Ripple.jitter(Ripple.boilFrame(0.35), 9, 1));
  });

  test('boil frame runs at 10 fps over 4 cycling seeds', () => {
    assert.strictEqual(Ripple.boilFrame(0), 0);
    assert.strictEqual(Ripple.boilFrame(0.099), 0);
    assert.strictEqual(Ripple.boilFrame(0.1), 1);
    assert.strictEqual(Ripple.boilFrame(0.45), 0);
    assert.strictEqual(Ripple.boilFrame(0.35), 3);
    assert.ok(Ripple.jitterAmp(0) >= 0.4 && Ripple.jitterAmp(1000) <= 1.5);
  });

  test('maskAlpha: full inside the band, soft edge, zero beyond', () => {
    assert.strictEqual(Ripple.maskAlpha(0.2, 0, 0.5, 0.12), 1);
    assert.ok(Math.abs(Ripple.maskAlpha(0.56, 0, 0.5, 0.12) - 0.5) < 1e-9);
    assert.strictEqual(Ripple.maskAlpha(0.7, 0, 0.5, 0.12), 0);
    assert.strictEqual(Ripple.maskAlpha(0.1, 0.3, 0.9, 0.12), 0);
  });

  test('maskStrips: foot band gives core + soft edge, full band gives one strip', () => {
    const out = new Float32Array(9);
    let n = Ripple.maskStrips(0, 0.3, 1.4, 0.12, out);
    assert.strictEqual(n, 2);
    assert.strictEqual(out[2], 1);
    assert.ok(out[5] > 0 && out[5] < 1);
    assert.ok(out[4] > 0.3 && out[4] < 0.5);
    n = Ripple.maskStrips(0, 1.4, 1.4, 0.12, out);
    assert.strictEqual(n, 1);
    assert.strictEqual(out[0], 0);
    assert.ok(Math.abs(out[1] - 1.4) < 1e-5);
    n = Ripple.maskStrips(0.5, 0.8, 1.4, 0.12, out);
    assert.strictEqual(n, 3);
  });

  test('floor footstep rings expand, fade and stagger', () => {
    assert.strictEqual(Ripple.footRing(-0.1, 0.8, 1, 0), -1);
    assert.strictEqual(Ripple.footRing(0.8, 0.8, 1, 0), -1);
    assert.ok(Ripple.footRing(0.2, 0.8, 1, 0) < Ripple.footRing(0.6, 0.8, 1, 0));
    assert.strictEqual(Ripple.footRing(0.1, 0.8, 1, 2), -1);
    assert.ok(Ripple.footRingAlpha(0.1, 0.8, 0) > Ripple.footRingAlpha(0.6, 0.8, 0));
    assert.ok(Math.abs(Ripple.wavyRadius(2, 0, 0, 6, 0.04) - 2) < 1e-9);
    assert.ok(Math.abs(Ripple.wavyRadius(2, 1, 0.5, 6) - 2) <= 2 * 0.04 + 1e-9);
  });

});

describe('ripple-inward.test.js', () => {

  const test = require('node:test');
  const assert = require('node:assert');
  const Ripple = require('../js/ripple.js');

  test('inward ring shrinks from maxR to minR over its life', () => {
    const st = Ripple.create();
    const rg = Ripple.spawn(st, 0, 0, 10, { kind: 'person', maxR: 1.4, life: 0.4, inward: true });
    assert.strictEqual(rg.inward, true);
    assert.ok(Math.abs(Ripple.radius(rg, 10) - 1.4) < 1e-9);
    assert.ok(Math.abs(Ripple.radius(rg, 10.2) - (0.15 + 1.25 * 0.5)) < 1e-9);
    assert.ok(Math.abs(Ripple.radius(rg, 10.4) - 0.15) < 1e-9);
    assert.ok(Math.abs(Ripple.radius(rg, 99) - 0.15) < 1e-9);
    let prev = Infinity;
    for (let t = 10; t <= 10.4; t += 0.02) {
      const r = Ripple.radius(rg, t);
      assert.ok(r <= prev + 1e-9 && r >= 0.15 - 1e-9);
      prev = r;
    }
  });

  test('inward ring honours delay and custom minR; alpha unchanged', () => {
    const st = Ripple.create();
    const a = Ripple.spawn(st, 0, 0, 0, { maxR: 1, life: 1, delay: 0.5, inward: true, minR: 0.3, strength: 0.8 });
    const b = Ripple.spawn(st, 0, 0, 0, { maxR: 1, life: 1, delay: 0.5, strength: 0.8 });
    assert.strictEqual(Ripple.radius(a, 0.2), 1);
    assert.ok(Math.abs(Ripple.radius(a, 1.5) - 0.3) < 1e-9);
    for (const t of [0, 0.6, 1.0, 1.4, 1.6]) assert.strictEqual(Ripple.alpha(a, t), Ripple.alpha(b, t));
  });

  test('non-inward rings behave as before', () => {
    const st = Ripple.create();
    const rg = Ripple.spawn(st, 0, 0, 0, { maxR: 2, life: 1 });
    assert.strictEqual(rg.inward, false);
    assert.strictEqual(Ripple.radius(rg, -1), 0);
    assert.strictEqual(Ripple.radius(rg, 0.5), 1);
    assert.strictEqual(Ripple.radius(rg, 1), 2);
  });

});

