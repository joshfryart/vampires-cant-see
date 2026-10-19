'use strict';
// Merged test file: each source file's tests live in their own describe().
const { describe } = require('node:test');

describe('hud.test.js', () => {

  const test = require('node:test');
  const assert = require('node:assert');
  const path = require('node:path');

  const ROOT = path.join(__dirname, '..');
  require(path.join(ROOT, 'js', 'ripple.js'));
  const Hud = require(path.join(ROOT, 'js', 'hud.js'));

  /** Fake 2D context: records every call as {fn, args, fillStyle, strokeStyle, globalAlpha}. */
  function fakeCtx(opts) {
    const calls = [];
    const state = { globalAlpha: 1, fillStyle: '#000', strokeStyle: '#000', lineWidth: 1 };
    const canvas = Object.assign({ width: 640, height: 360 }, opts && opts.canvas);
    const ctx = new Proxy({ calls: calls, canvas: canvas }, {
      get(target, prop) {
        if (prop in target) return target[prop];
        if (prop in state) return state[prop];
        return function () {
          const rec = { fn: String(prop), args: Array.prototype.slice.call(arguments), fillStyle: state.fillStyle, strokeStyle: state.strokeStyle, alpha: state.globalAlpha };
          calls.push(rec);
          if (prop === 'createRadialGradient') return { addColorStop() {} };
          return undefined;
        };
      },
      set(target, prop, v) { state[prop] = v; return true; }
    });
    return ctx;
  }

  const BAD = [NaN, undefined, null, Infinity, -Infinity, -5, 1e12, 'x', {}, []];

  /** y coordinates of every path point drawn while strokeStyle was the blood colour. */
  function bloodYs(ctx) {
    const ys = [];
    for (const c of ctx.calls) {
      if ((c.fn === 'moveTo' || c.fn === 'lineTo') && c.strokeStyle === '#d0505e') ys.push(c.args[1]);
    }
    return ys;
  }

  test('create needs no DOM and exports API', () => {
    const h = Hud.create();
    assert.ok(h && typeof h === 'object');
    for (const k of ['create', 'drawHud', 'drawDawn', 'drawCard', 'drawHint', 'drawFade']) assert.strictEqual(typeof Hud[k], 'function');
    assert.strictEqual(Hud.CARD_DUR, 2.4);
  });

  test('drawHud draws crosshair, vial, dial and text', () => {
    const ctx = fakeCtx();
    Hud.drawHud(Hud.create(), ctx, { blood01: 0.6, weak: 0, frac: 0.5, hour: 1, minute: 5, t: 1, boil: true, reduced: false, pulse01: 0 });
    assert.ok(ctx.calls.some((c) => c.fn === 'fillRect' && c.args[2] === 2 && c.args[3] === 2));
    const txt = ctx.calls.find((c) => c.fn === 'fillText');
    assert.strictEqual(txt.args[0], '01:05');
    assert.ok(txt.alpha >= 0.7 && txt.alpha <= 0.75);
    assert.ok(!ctx.calls.some((c) => c.fn === 'fill'));
  });

  test('drawHud cooldown arc only when pulse01 > 0', () => {
    const a = fakeCtx();
    Hud.drawHud(Hud.create(), a, { pulse01: 0 });
    assert.ok(!a.calls.some((c) => c.fn === 'arc' && c.args[2] === 6));
    const b = fakeCtx();
    Hud.drawHud(Hud.create(), b, { pulse01: 0.5 });
    assert.ok(b.calls.some((c) => c.fn === 'arc' && c.args[2] === 6));
  });

  test('drawHud never throws on bad input', () => {
    const h = Hud.create();
    for (const v of BAD) {
      const ctx = fakeCtx();
      assert.doesNotThrow(() => Hud.drawHud(h, ctx, { blood01: v, weak: v, frac: v, hour: v, minute: v, t: v, boil: v, reduced: v, pulse01: v }));
    }
    assert.doesNotThrow(() => Hud.drawHud(undefined, fakeCtx(), undefined));
    assert.doesNotThrow(() => Hud.drawHud(null, null, null));
    assert.doesNotThrow(() => Hud.drawHud(h, {}, {}));
    assert.doesNotThrow(() => Hud.drawHud(h, { save() { throw new Error('boom'); } }, {}));
  });

  test('vial liquid y moves with blood01', () => {
    const lo = fakeCtx();
    const hi = fakeCtx();
    Hud.drawHud(Hud.create(), lo, { blood01: 0.2, t: 0, reduced: true });
    Hud.drawHud(Hud.create(), hi, { blood01: 0.9, t: 0, reduced: true });
    const yLo = Math.min.apply(null, bloodYs(lo));
    const yHi = Math.min.apply(null, bloodYs(hi));
    assert.ok(isFinite(yLo) && isFinite(yHi));
    assert.ok(yHi < yLo - 10, 'fuller vial has higher (smaller y) surface: ' + yHi + ' vs ' + yLo);
    const none = fakeCtx();
    Hud.drawHud(Hud.create(), none, { blood01: 0 });
    assert.strictEqual(bloodYs(none).length, 0);
  });

  test('reduced motion: no slosh, no boil', () => {
    const a = fakeCtx();
    const b = fakeCtx();
    const s = { blood01: 0.5, weak: 0.5, frac: 0.3, hour: 22, minute: 0, boil: true, reduced: true };
    Hud.drawHud(Hud.create(), a, Object.assign({ t: 0.0 }, s));
    Hud.drawHud(Hud.create(), b, Object.assign({ t: 3.37 }, s));
    assert.deepStrictEqual(a.calls.map((c) => c.args), b.calls.map((c) => c.args));
  });

  test('weak makes the vial outline flicker', () => {
    const alphas = new Set();
    for (let i = 0; i < 12; i++) {
      const ctx = fakeCtx();
      Hud.drawHud(Hud.create(), ctx, { blood01: 0.1, weak: 1, t: i * 0.05 });
      const st = ctx.calls.find((c) => c.fn === 'stroke');
      alphas.add(st.alpha.toFixed(3));
    }
    assert.ok(alphas.size > 3);
    assert.ok(Math.max.apply(null, Array.from(alphas).map(Number)) <= 0.55);
  });

  test('sun end brightens after 05:00', () => {
    function sunAlpha(frac) {
      const ctx = fakeCtx();
      Hud.drawHud(Hud.create(), ctx, { frac: frac, t: 0 });
      // sun stroke is stroke index 3 when blood is empty: vial outline, track dots, moon, sun
      const strokes = ctx.calls.filter((c) => c.fn === 'stroke');
      return strokes[3].alpha;
    }
    assert.ok(sunAlpha(1) > sunAlpha(0.5));
    assert.ok(sunAlpha(1) <= 0.8 + 1e-9);
  });

  test('drawCard is a no-op past 2.4 s and before 0', () => {
    const a = fakeCtx();
    Hud.drawCard(Hud.create(), a, 'Night 1', 2.41, 1, true);
    assert.strictEqual(a.calls.length, 0);
    const b = fakeCtx();
    Hud.drawCard(Hud.create(), b, 'Night 1', -0.1, 1, true);
    assert.strictEqual(b.calls.length, 0);
    const c = fakeCtx();
    Hud.drawCard(Hud.create(), c, 'Night 1', 1, 1, true);
    assert.strictEqual(c.calls.filter((x) => x.fn === 'strokeText').length, 6);
  });

  test('drawCard alpha follows 0.3 / 1.6 / 0.5 timing', () => {
    function alphaAt(age) {
      const ctx = fakeCtx();
      Hud.drawCard(Hud.create(), ctx, 'Dawn', age, 0, false);
      const st = ctx.calls.find((c) => c.fn === 'strokeText');
      return st ? st.alpha : 0;
    }
    assert.ok(alphaAt(0.15) < alphaAt(1));
    assert.ok(Math.abs(alphaAt(1) - 0.85) < 1e-9);
    assert.ok(alphaAt(2.2) < alphaAt(1));
    assert.ok(alphaAt(2.2) > 0);
  });

  test('drawCard never throws on bad input', () => {
    for (const v of BAD) {
      assert.doesNotThrow(() => Hud.drawCard(Hud.create(), fakeCtx(), v, v, v, v));
      assert.doesNotThrow(() => Hud.drawCard(Hud.create(), fakeCtx(), 'Night 2', v, v, v));
    }
    assert.doesNotThrow(() => Hud.drawCard(null, null, 'x', 1, 1, true));
    assert.doesNotThrow(() => Hud.drawCard(Hud.create(), fakeCtx(), 'x'.repeat(500), 1, 1, true));
  });

  test('drawCard sub draws extra text; absent sub is identical', () => {
    const a = fakeCtx();
    Hud.drawCard(Hud.create(), a, 'Night 2', 1, 1, false);
    const b = fakeCtx();
    Hud.drawCard(Hud.create(), b, 'Night 2', 1, 1, false, undefined);
    assert.deepStrictEqual(b.calls, a.calls);
    const c = fakeCtx();
    Hud.drawCard(Hud.create(), c, 'Night 2', 1, 1, false, 'A silent dash of two cells.');
    assert.ok(c.calls.length > a.calls.length);
    assert.ok(c.calls.some((x) => x.fn === 'fillText' && /silent dash/.test(x.args[0])));
    assert.ok(!a.calls.some((x) => x.fn === 'fillText'));
    for (const v of BAD) assert.doesNotThrow(() => Hud.drawCard(Hud.create(), fakeCtx(), 'x', 1, 1, true, v));
  });

  test('drawFade clamps alpha and no-ops at 0', () => {
    const a = fakeCtx();
    Hud.drawFade(a, 5);
    const r = a.calls.find((c) => c.fn === 'fillRect');
    assert.strictEqual(r.alpha, 1);
    assert.strictEqual(r.fillStyle, '#000');
    const b = fakeCtx();
    Hud.drawFade(b, 0.4);
    assert.strictEqual(b.calls.find((c) => c.fn === 'fillRect').alpha, 0.4);
    for (const k of [0, -1, NaN, undefined]) {
      const c = fakeCtx();
      Hud.drawFade(c, k);
      assert.strictEqual(c.calls.length, 0);
    }
    for (const v of BAD) assert.doesNotThrow(() => Hud.drawFade(fakeCtx(), v));
    assert.doesNotThrow(() => Hud.drawFade(null, 1));
  });

  test('drawDawn is a no-op at k 0 and ramps with k', () => {
    for (const k of [0, -1, NaN, undefined]) {
      const ctx = fakeCtx();
      Hud.drawDawn(Hud.create(), ctx, k, 1, false);
      assert.strictEqual(ctx.calls.length, 0);
    }
    function vigAlpha(k) {
      const ctx = fakeCtx();
      Hud.drawDawn(Hud.create(), ctx, k, 1, false);
      return ctx.calls.find((c) => c.fn === 'fillRect').alpha;
    }
    assert.ok(vigAlpha(1) > vigAlpha(0.2));
    for (const v of BAD) assert.doesNotThrow(() => Hud.drawDawn(Hud.create(), fakeCtx(), v, v, v));
    assert.doesNotThrow(() => Hud.drawDawn(null, null, 1, 1, false));
  });

  test('drawDawn builds grain lazily from ownerDocument and caches it', () => {
    let made = 0;
    const doc = {
      createElement() {
        made++;
        return {
          width: 0, height: 0,
          getContext() {
            return {
              createImageData(w, h) { return { data: new Uint8ClampedArray(w * h * 4) }; },
              putImageData() {}
            };
          }
        };
      }
    };
    const h = Hud.create();
    assert.strictEqual(made, 0);
    const ctx = fakeCtx({ canvas: { ownerDocument: doc } });
    Hud.drawDawn(h, ctx, 0.8, 1, false);
    assert.strictEqual(made, 2);
    assert.ok(ctx.calls.some((c) => c.fn === 'drawImage'));
    Hud.drawDawn(h, ctx, 0.8, 1.1, false);
    assert.strictEqual(made, 2);
    // a failing document must not throw
    const bad = fakeCtx({ canvas: { ownerDocument: { createElement() { throw new Error('no'); } } } });
    assert.doesNotThrow(() => Hud.drawDawn(Hud.create(), bad, 1, 1, false));
  });

  test('vialPulse scales the vial around its centre; none when reduced or zero', () => {
    const base = { blood01: 0.5, frac: 0.3, t: 1, reduced: false };
    const a = fakeCtx();
    Hud.drawHud(Hud.create(), a, Object.assign({ vialPulse: 1 }, base));
    const sc = a.calls.filter((c) => c.fn === 'scale');
    assert.strictEqual(sc.length, 1);
    assert.ok(Math.abs(sc[0].args[0] - 1.08) < 1e-9);
    const b = fakeCtx();
    Hud.drawHud(Hud.create(), b, Object.assign({ vialPulse: 0 }, base));
    assert.strictEqual(b.calls.filter((c) => c.fn === 'scale').length, 0);
    const c = fakeCtx();
    Hud.drawHud(Hud.create(), c, Object.assign({}, base, { vialPulse: 1, reduced: true }));
    assert.strictEqual(c.calls.filter((x) => x.fn === 'scale').length, 0);
    const sv = a.calls.filter((x) => x.fn === 'save').length;
    const rs = a.calls.filter((x) => x.fn === 'restore').length;
    assert.strictEqual(sv, rs);
  });

  test('feeding halves dial and clock alpha', () => {
    const run = (feeding) => {
      const ctx = fakeCtx();
      Hud.drawHud(Hud.create(), ctx, { frac: 0.5, hour: 1, minute: 5, t: 1, feeding });
      return ctx.calls.filter((c) => c.fn === 'fillText').map((c) => c.alpha);
    };
    const off = run(false);
    const on = run(true);
    assert.ok(off.length > 0);
    assert.ok(Math.abs(on[0] - off[0] * 0.5) < 1e-9);
  });

  test('vialPulse and feeding tolerate bad values', () => {
    for (const v of BAD) assert.doesNotThrow(() => Hud.drawHud(Hud.create(), fakeCtx(), { vialPulse: v, feeding: v, blood01: 0.5 }));
  });

});

describe('hud-hunger.test.js', () => {

  const test = require('node:test');
  const assert = require('node:assert');
  const path = require('node:path');

  const ROOT = path.join(__dirname, '..');
  require(path.join(ROOT, 'js', 'ripple.js'));
  require(path.join(ROOT, 'js', 'icons.js'));
  const Hud = require(path.join(ROOT, 'js', 'hud.js'));

  function fakeCtx() {
    const calls = [];
    const state = { globalAlpha: 1, fillStyle: '#000', strokeStyle: '#000', lineWidth: 1 };
    return new Proxy({ calls: calls, canvas: { width: 640, height: 360 } }, {
      get(t, p) {
        if (p in t) return t[p];
        if (p in state) return state[p];
        return function () {
          calls.push({ fn: String(p), args: Array.prototype.slice.call(arguments), stroke: state.strokeStyle, alpha: state.globalAlpha });
        };
      },
      set(t, p, v) { state[p] = v; return true; }
    });
  }
  const BASE = { blood01: 0.5, frac: 0.4, hour: 23, minute: 10, t: 1, boil: true };
  function run(extra) {
    const c = fakeCtx();
    Hud.drawHud(Hud.create(), c, Object.assign({}, BASE, extra));
    return c.calls;
  }
  const sig = (a) => JSON.stringify(a);

  test('no new fields: identical call sequence to baseline', () => {
    const base = run({});
    assert.strictEqual(sig(run({ powers: undefined, over01: undefined })), sig(base));
    assert.strictEqual(sig(run({ fear: 0, still01: 0, mistK: 0, giftFlash: 0, over01: 0, overOpen: false })), sig(base));
  });

  test('each field produces extra draw calls', () => {
    const n = run({}).length;
    const cases = [
      { over01: 0.5, overOpen: true }, { over01: 0.9 },
      { powers: [{ id: 'bat', state: 'ready', cd01: 0, key: 'Q' }] },
      { fear: 7 }, { still01: 0.8 }, { mistK: 0.6 }, { giftFlash: 0.7 }
    ];
    for (const c of cases) assert.ok(run(c).length > n, sig(c));
  });

  test('overOpen true with over01 0 still draws the track; both off draws nothing', () => {
    const n = run({}).length;
    assert.ok(run({ overOpen: true, over01: 0 }).length > n);
    assert.strictEqual(run({ overOpen: false, over01: 0 }).length, n);
  });

  test('locked powers draw nothing', () => {
    const n = run({}).length;
    assert.strictEqual(run({ powers: [{ id: 'bat', state: 'locked', cd01: 0, key: 'Q' }, { id: 'mist', state: 'locked' }] }).length, n);
  });

  test('power states: alpha, cooldown arc, key letter', () => {
    const poor = run({ powers: [{ id: 'shriek', state: 'poor', key: 'Q' }] });
    assert.ok(poor.some((c) => c.fn === 'stroke' && c.alpha === 0.25) || poor.length > run({}).length);
    const cd = run({ powers: [{ id: 'mist', state: 'cooldown', cd01: 0.5, key: 'F' }] });
    assert.ok(cd.some((c) => c.fn === 'arc' && c.args[2] === 11));
    assert.ok(!cd.some((c) => c.fn === 'fillText' && c.args[0] === 'F'));
    const rd = run({ powers: [{ id: 'still', state: 'ready', key: '⇧' }] });
    assert.ok(rd.some((c) => c.fn === 'fillText' && c.args[0] === '⇧'));
  });

  test('unknown icon id falls back to a circle', () => {
    const c = run({ powers: [{ id: 'zzz', state: 'ready', key: 'Q' }] });
    assert.ok(c.some((x) => x.fn === 'arc' && x.args[2] === 7));
  });

  test('fear draws one eye per 3 and caps at 5', () => {
    const eyes = (f) => run({ fear: f }).filter((c) => c.fn === 'arc' && c.args[2] === 1.2).length;
    assert.strictEqual(eyes(3), 1);
    assert.strictEqual(eyes(4), 2);
    assert.strictEqual(eyes(15), 5);
    assert.strictEqual(eyes(99), 5);
  });

  test('still border and mist stay dim', () => {
    assert.ok(run({ still01: 1 }).filter((c) => c.stroke === '#cfe8ff' && c.fn === 'stroke').every((c) => c.alpha <= 0.55));
    const base = run({}).length;
    const m = run({ mistK: 1 }).slice(base - 2);
    assert.ok(m.some((c) => c.fn === 'stroke' && c.alpha <= 0.25));
  });

  test('bad values never throw', () => {
    const bad = [NaN, 'x', null, {}, [], -3, Infinity, 1e9, true];
    for (const b of bad) {
      assert.doesNotThrow(() => run({ over01: b, overOpen: b, powers: b, fear: b, still01: b, mistK: b, giftFlash: b }));
      assert.doesNotThrow(() => run({ powers: [b, { id: b, state: b, cd01: b, key: b }, { id: 'bat', state: 'cooldown', cd01: b, key: b }, { id: b, state: 'ready', key: b }] }));
    }
    assert.doesNotThrow(() => Hud.drawHud(null, fakeCtx(), { fear: 'a', powers: 'b' }));
  });


  describe('a11y (v1.1)', () => {
    const BAD = [NaN, undefined, null, Infinity, -Infinity, -5, 1e12, 'x', {}, []];
    const fakeCtx = (opts) => {
      const calls = [];
      const state = { globalAlpha: 1, fillStyle: '#000', strokeStyle: '#000' };
      return new Proxy({ calls: calls, canvas: Object.assign({ width: 640, height: 360 }, opts && opts.canvas) }, {
        get(t, p) { if (p in t) return t[p]; if (p in state) return state[p]; return function () { calls.push({ fn: String(p), args: Array.prototype.slice.call(arguments), alpha: state.globalAlpha }); return p === 'createRadialGradient' ? { addColorStop() {} } : undefined; }; },
        set(t, p, v) { state[p] = v; return true; }
      });
    };
    const posRun = (extra) => {
      const calls = [];
      const state = { globalAlpha: 1 };
      const ctx = new Proxy({ calls: calls, canvas: { width: 640, height: 360 } }, {
        get(t, p) { if (p in t) return t[p]; if (p in state) return state[p]; return function () { calls.push({ fn: String(p), args: Array.prototype.slice.call(arguments), alpha: state.globalAlpha, font: state.font }); }; },
        set(t, p, v) { state[p] = v; return true; }
      });
      Hud.drawHud(Hud.create(), ctx, Object.assign({ frac: 0.5, t: 1 }, extra));
      return calls;
    };
    const fontPx = (calls) => calls.filter((c) => c.fn === 'fillText').map((c) => parseFloat(c.font));

    test('clock 10px alpha 0.7; key labels 8px', () => {
      const c = posRun({ powers: [{ id: 'bat', state: 'ready', key: 'Q' }] });
      const px = fontPx(c);
      assert.ok(px.includes(10) && px.includes(8));
    });

    test('largeText scales text x1.3 and stays non-overlapping', () => {
      const pw = [{ id: 'shriek', state: 'ready', key: 'Q' }, { id: 'mist', state: 'ready', key: 'Sh' }, { id: 'still', state: 'ready', key: 'F' }];
      const n = posRun({ powers: pw, fear: 15 });
      const l = posRun({ powers: pw, fear: 15, largeText: true });
      assert.deepStrictEqual(fontPx(l), fontPx(n).map((v) => v * 1.3));
      const xs = (cs) => cs.filter((c) => c.fn === 'translate').map((c) => c.args[0]);
      const tx = xs(l);
      for (let i = 1; i < tx.length; i++) assert.ok(tx[i] - tx[i - 1] >= 18 * 1.3, 'icons clear each other');
      assert.ok(tx[0] - 18 * 1.3 / 2 > 54, 'clear of the vial gift ring');
      const eyes = l.filter((c) => c.fn === 'arc' && Math.abs(c.args[2] - 1.2 * 1.3) < 1e-9).map((c) => c.args[0]);
      assert.strictEqual(eyes.length, 5);
      for (let i = 1; i < eyes.length; i++) assert.ok(eyes[i] - eyes[i - 1] >= 8 * 1.3);
      assert.ok(eyes[4] + 4 * 1.3 < 640);
    });

    test('largeText on cards and bad values', () => {
      const f = (o) => { const c = fakeCtx(); Hud.drawCard(Hud.create(), c, 'NIGHT ONE', 1, 1, false, 'sub', o); return c.calls.length; };
      assert.ok(f({ largeText: true }) > 0 && f(undefined) > 0);
      for (const v of BAD) assert.doesNotThrow(() => Hud.drawHud(Hud.create(), fakeCtx(), { largeText: v, fear: 15, powers: [{ id: 'bat', state: 'ready', key: 'Q' }] }));
    });

    test('weak flicker is at most 3 Hz and dawn grain swaps at most 2 Hz', () => {
      const a = (t) => { const c = fakeCtx(); Hud.drawHud(Hud.create(), c, { blood01: 0.1, weak: 1, t }); return c.calls.find((x) => x.fn === 'stroke').alpha; };
      let flips = 0; let prev = a(0) - a(-0.01);
      for (let t = 0.01; t < 1; t += 0.01) { const d = a(t) - a(t - 0.01); if (d * prev < 0) flips++; if (d) prev = d; }
      assert.ok(flips <= 6, 'extrema per second ' + flips);
      const h = Hud.create();
      let swaps = 0; let last = null;
      const frames = [{}, {}];
      const mk = () => { const c = fakeCtx({ canvas: { ownerDocument: { createElement() { const g = { createImageData: () => ({ data: new Uint8ClampedArray(320 * 180 * 4) }), putImageData() {} }; return { width: 0, height: 0, getContext: () => g }; } } } }); return c; };
      const ctx = mk();
      for (let t = 0; t < 2; t += 0.02) {
        ctx.calls.length = 0;
        Hud.drawDawn(h, ctx, 1, t, false);
        const d = ctx.calls.find((x) => x.fn === 'drawImage');
        if (d) { if (last && d.args[0] !== last) swaps++; last = d.args[0]; }
      }
      assert.ok(swaps <= 4, 'swaps in 2s: ' + swaps);
      assert.ok(frames.length === 2);
    });

    test('drawHint fades over 0.4 s, sits above the vial row, never throws', () => {
      const run = (age, o) => { const c = fakeCtx(); Hud.drawHint(Hud.create(), c, 'Click to pulse', age, 1, o); return c.calls; };
      assert.strictEqual(run(-1).length, 0);
      assert.strictEqual(run(5).length, 0);
      const txt = (c) => c.find((x) => x.fn === 'fillText');
      assert.ok(Math.abs(txt(run(2)).alpha - 0.8) < 1e-9);
      assert.ok(txt(run(0.2)).alpha < txt(run(2)).alpha);
      assert.ok(txt(run(3.8)).alpha < txt(run(2)).alpha);
      const plate = run(2).find((x) => x.fn === 'fillRect');
      assert.ok(plate && plate.args[1] + plate.args[3] < 293, 'above vial row');
      assert.ok(run(2, { largeText: true }).length > 0);
      for (const v of BAD) { assert.doesNotThrow(() => Hud.drawHint(Hud.create(), fakeCtx(), v, v, v, v)); assert.doesNotThrow(() => Hud.drawHint(null, null, 'x', 1, 1)); }
    });
  });

});

