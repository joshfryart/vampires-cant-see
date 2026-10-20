'use strict';
const { describe } = require('node:test');

describe('struggle.test.js', () => {
  const test = require('node:test');
  const assert = require('node:assert');
  const Struggle = require('../js/struggle.js');

  const base = { pid: 5, lh: 1, bw: 1, shS: 0.062, hipS: 0.04, anim: true };
  function run(t, g, bl, sp) {
    const out = Struggle.create();
    Struggle.pose(out, Object.assign({}, base, { t: t, g: g, bl: bl, sp: sp }));
    return out;
  }
  function finite(p) {
    for (const k of Object.keys(p)) {
      const v = p[k];
      if (Array.isArray(v)) v.forEach(function (x) { assert.ok(Number.isFinite(x), k); });
      else assert.ok(Number.isFinite(v), k);
    }
  }

  test('every phase gives finite poses across ids, times and blood', () => {
    for (let pid = 0; pid < 12; pid++) {
      for (let g = 0; g < 12; g += 0.37) {
        for (const bl of [1, 0.7, 0.4, 0.2, 0.05, 0]) {
          const out = Struggle.create();
          Struggle.pose(out, Object.assign({}, base, { pid: pid, t: 100 + g, g: g, bl: bl, sp: g % 0.9 }));
          finite(out);
          assert.ok(Math.abs(out.yawU) <= 0.55 + 1e-9);
        }
      }
    }
  });

  test('panic moves the arms far more than a drained victim does', () => {
    function range(bl, g0) {
      let lo = Infinity; let hi = -Infinity;
      for (let t = 0; t < 3; t += 0.05) { const u = run(50 + t, g0 + t * 0.3, bl, 9).hu[0]; lo = Math.min(lo, u); hi = Math.max(hi, u); }
      return hi - lo;
    }
    assert.ok(range(1, 0.5) > 0.05);
    assert.ok(range(0.02, 8) < 0.02);
  });

  test('push phase leans back with arms out toward the viewer', () => {
    const o = run(10, 6, 0.8, 9);
    assert.ok(o.lean < 0, 'leans away');
    assert.ok(o.hf[0] > 0.08 || o.hf[1] > 0.08 || o.hu[0] > o.shU - 0.1, 'arms raised/out');
  });

  test('drained victim is the slack grapple pose', () => {
    const o = run(10, 9, 0.0, 9);
    assert.strictEqual(o.tilt, 0.55);
    assert.ok(o.hu[0] < o.shU - 0.2);
  });

  test('restraining pins the arms down and damps the thrashing', () => {
    const free = Struggle.create(); const held = Struggle.create();
    const o = Object.assign({}, base, { t: 50.3, g: 1.2, bl: 1, sp: 9 });
    Struggle.pose(free, o);
    Struggle.pose(held, Object.assign({}, o, { rs: 1 }));
    finite(held);
    assert.ok(held.hu[0] < free.hu[0] || held.hu[1] < free.hu[1] || free.hu[0] <= held.shU - 0.15, 'hands lower when pinned');
    assert.ok(held.jolt <= free.jolt + 1e-9);
    assert.ok(held.hu[0] < held.shU - 0.1 && held.hu[1] < held.shU - 0.1, 'both hands below the shoulders');
  });

  test('reduced motion is static', () => {
    const a = Struggle.create(); const b = Struggle.create();
    Struggle.pose(a, Object.assign({}, base, { anim: false, t: 1, g: 1, bl: 0.8, sp: 0.1 }));
    Struggle.pose(b, Object.assign({}, base, { anim: false, t: 9, g: 5, bl: 0.8, sp: 0.5 }));
    assert.deepStrictEqual(a, b);
  });
});
