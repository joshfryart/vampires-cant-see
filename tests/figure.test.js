'use strict';
const test = require('node:test');
const assert = require('node:assert');

require('../js/log.js');
const Figure = require('../js/figure.js');

function fakeCtx() {
  const calls = [];
  const state = { globalAlpha: 1, fillStyle: '#000', strokeStyle: '#000', lineWidth: 1 };
  return new Proxy({ calls, canvas: { width: 640, height: 360 } }, {
    get(t, p) {
      if (p in t) return t[p];
      if (p in state) return state[p];
      return function () {
        calls.push({ fn: String(p), args: Array.prototype.slice.call(arguments), alpha: state.globalAlpha, fill: state.fillStyle, stroke: state.strokeStyle, lw: state.lineWidth });
      };
    },
    set(t, p, v) { state[p] = v; return true; }
  });
}
const count = (c, fn) => c.calls.filter((k) => k.fn === fn).length;

function makeP() {
  const X = new Float32Array(28);
  const Y = new Float32Array(28);
  const Z = new Float32Array(28);
  const set = (k, x, y, z) => { X[k] = x; Y[k] = y; Z[k] = z || 0; };
  set(0, 300, 120, -0.2); set(1, 300, 140, 0); set(2, 280, 150, 0); set(3, 320, 150, 0);
  set(4, 290, 220, 0); set(5, 310, 220, 0); set(6, 270, 215, 0.1); set(7, 330, 215, -0.1);
  set(8, 285, 300, 0); set(9, 315, 300, 0.1); set(10, 272, 185, 0); set(11, 328, 185, 0);
  set(12, 288, 262, 0); set(13, 312, 262, 0); set(14, 300, 185, 0); set(15, 290, 150, 0); set(16, 292, 160, 0);
  set(17, 280, 100, 0); set(18, 300, 95, 0); set(19, 330, 215, 0); set(20, 335, 280, 0);
  set(21, 280, 235, 0); set(22, 320, 235, 0); set(23, 300, 100, 0); set(24, 270, 215, 0); set(25, 262, 150, 0);
  return { X, Y, Z };
}
const POSE = () => ({ hipU: 0.5, shU: 0.8, headU: 0.9, hs: 400, vs: 360, hr: 12, hry: 13, bodyRx: 20, bodyRy: 32, tilt: 0, lod: 2, noseX: 0.5, faceVis: true, eyesVis: true, mode: 'path', prop: 'none', hat: 'none', headKind: 'round', bodyKind: 'bean', depth: 2 });
const LOOK = () => ({ height: 1, build: 1, body: 'bean', head: 'round', hair: 'tuft', beard: true, nose: 1, coat: true, acc: 'none', hat: 'none', prop: 'none' });

test('capsule tangent points lie at the radii', () => {
  const c = fakeCtx();
  const [x0, y0, r0, x1, y1, r1] = [10, 20, 8, 70, 50, 3];
  assert.strictEqual(Figure.capsule(c, x0, y0, r0, x1, y1, r1), true);
  const mv = c.calls.find((k) => k.fn === 'moveTo').args;
  const ln = c.calls.find((k) => k.fn === 'lineTo').args;
  const arcs = c.calls.filter((k) => k.fn === 'arc');
  assert.strictEqual(arcs.length, 2);
  assert.ok(Math.abs(Math.hypot(mv[0] - x0, mv[1] - y0) - r0) < 1e-6);
  assert.ok(Math.abs(Math.hypot(ln[0] - x0, ln[1] - y0) - r0) < 1e-6);
  for (const a of arcs) {
    const [cx, cy, r, s, e] = a.args;
    const rr = cx === x1 ? r1 : r0;
    assert.ok(Math.abs(r - rr) < 1e-6);
    for (const ang of [s, e]) assert.ok(Math.abs(Math.hypot(cx + r * Math.cos(ang) - cx, cy + r * Math.sin(ang) - cy) - rr) < 1e-6);
  }
  // Both tangent points are perpendicular-consistent: the segment moveTo -> first arc start is tangent (normal . segment = 0).
  const a1 = arcs.find((k) => k.args[0] === x1).args;
  const px = x1 + a1[2] * Math.cos(a1[3]);
  const py = y1 + a1[2] * Math.sin(a1[3]);
  const nx = Math.cos(a1[3]);
  const ny = Math.sin(a1[3]);
  assert.ok(Math.abs((px - mv[0]) * nx + (py - mv[1]) * ny) < 1e-6);
});

test('capsule with coincident points is a circle', () => {
  const c = fakeCtx();
  assert.strictEqual(Figure.capsule(c, 5, 5, 4, 5, 5, 2), true);
  assert.strictEqual(count(c, 'arc'), 1);
  const a = c.calls.find((k) => k.fn === 'arc').args;
  assert.deepStrictEqual(a.slice(0, 3), [5, 5, 4]);
  assert.ok(Math.abs(a[4] - a[3] - Math.PI * 2) < 1e-9);
});

test('sortBackToFront is stable and descending in z', () => {
  const arr = [{ z: 1, id: 'a' }, { z: 3, id: 'b' }, { z: 1, id: 'c' }, { z: 3, id: 'd' }, { z: -2, id: 'e' }, { z: 2, id: 'f' }];
  Figure.sortBackToFront(arr, arr.length);
  assert.deepStrictEqual(arr.map((p) => p.id), ['b', 'd', 'f', 'a', 'c', 'e']);
  const part = [{ z: 1 }, { z: 5 }, { z: 9 }];
  Figure.sortBackToFront(part, 2);
  assert.deepStrictEqual(part.map((p) => p.z), [5, 1, 9]);
});

test('parts fills up to 16 sorted-ready parts with finite numbers', () => {
  const out = [];
  const n = Figure.parts(makeP(), POSE(), LOOK(), out);
  assert.ok(n >= 15 && n <= 16);
  for (let i = 0; i < n; i++) {
    const p = out[i];
    assert.ok(typeof p.kind === 'string' && p.kind);
    for (const k of ['r0', 'r1', 'z', 'ax', 'ay']) assert.ok(isFinite(p[k]), k);
  }
  assert.strictEqual(Figure.parts(makeP(), POSE(), Object.assign(LOOK(), { extra: 'shovel' }), []), 16);
});

test('draw: fx 2 fills black occluders, fx 1 does not, fx 0 still strokes', () => {
  for (const fx of [0, 1, 2]) {
    const c = fakeCtx();
    assert.strictEqual(Figure.draw(c, 1, '#ff8a78', makeP(), POSE(), LOOK(), { fx, lw: 1.5, alpha: 0.9, depth: 2 }), true);
    const blackFills = c.calls.filter((k) => k.fn === 'fill' && k.fill === '#000000').length;
    if (fx === 2) assert.ok(blackFills >= 10); else assert.strictEqual(blackFills, 0);
    assert.ok(count(c, 'stroke') > 10);
    assert.strictEqual(count(c, 'save'), count(c, 'restore'));
  }
});

test('draw: rim stroke only when rim.k > 0.02; far figures get contours only', () => {
  const rimmed = (rim, depth) => {
    const c = fakeCtx();
    Figure.draw(c, 1, '#fff', makeP(), POSE(), LOOK(), { fx: 2, lw: 1, alpha: 1, depth, rim });
    return c.calls.filter((k) => k.fn === 'stroke' && k.stroke === '#ffcf8a').length;
  };
  assert.ok(rimmed({ side: 1, k: 0.8 }, 2) > 5);
  assert.strictEqual(rimmed({ side: 1, k: 0.01 }, 2), 0);
  assert.strictEqual(rimmed({ side: -1, k: 0.8 }, 7), 0);
  const c = fakeCtx();
  Figure.draw(c, 1, '#fff', makeP(), POSE(), LOOK(), { fx: 2, lw: 1, alpha: 1, depth: 8 });
  assert.strictEqual(c.calls.filter((k) => k.fn === 'fill').length, 0);
});

test('draw covers every pose flag, hat, hair and prop', () => {
  for (const hat of ['none', 'tophat', 'nightcap', 'bonnet', 'cap', 'hood']) {
    for (const prop of ['none', 'cane', 'lantern', 'umbrella', 'basket']) {
      for (const hk of ['round', 'egg', 'square', 'long']) {
        const pose = Object.assign(POSE(), { hat, prop, headKind: hk, stars: true, handsOverHead: true, seated: true, mode: hat === 'cap' ? 'fed' : 'path', eyesX: true });
        const look = Object.assign(LOOK(), { hat, prop, acc: 'scarf', body: 'stick', hair: ['tuft', 'bun', 'spiky', 'curls', 'bob'][prop.length % 5] });
        const c = fakeCtx();
        assert.strictEqual(Figure.draw(c, 1, '#fff', makeP(), pose, look, { fx: 2, lw: 1, alpha: 1, depth: 1 }), true);
        assert.ok(count(c, 'stroke') > 0);
      }
    }
  }
});

test('draw: robe skips legs above the hem and clips the rest', () => {
  const c = fakeCtx();
  Figure.draw(c, 1, '#fff', makeP(), POSE(), Object.assign(LOOK(), { outfit: 'robe', hem: 0.5 }), { fx: 1, lw: 1, alpha: 1, depth: 2 });
  assert.ok(count(c, 'clip') >= 1 || count(c, 'stroke') > 0);
  assert.strictEqual(count(c, 'save'), count(c, 'restore'));
});

test('drawFlush alpha is capped at 0.18 and 0.08 when reduced', () => {
  const c = fakeCtx();
  assert.strictEqual(Figure.drawFlush(c, makeP(), POSE(), [5, 5, 5, 5], { alpha: 1, look: { skin: 1 } }), true);
  const fills = c.calls.filter((k) => k.fn === 'fill');
  assert.strictEqual(fills.length, 4);
  for (const f of fills) { assert.ok(f.alpha <= 0.18 + 1e-9); assert.strictEqual(f.fill, '#ff8a78'); }
  const r = fakeCtx();
  Figure.drawFlush(r, makeP(), POSE(), [5, 5, 5, 5], { alpha: 1, reduced: true });
  for (const f of r.calls.filter((k) => k.fn === 'fill')) assert.ok(f.alpha <= 0.08 + 1e-9);
  const small = fakeCtx();
  Figure.drawFlush(small, makeP(), POSE(), [0.2, 0, 0, 0], { alpha: 1, look: { skin: 0.5 } });
  assert.ok(Math.abs(small.calls.find((k) => k.fn === 'fill').alpha - 0.2 * 0.5 * 0.25) < 1e-9);
});

test('each extra kind emits strokes', () => {
  const kinds = [
    { outfit: 'mail' }, { outfit: 'robe', hem: 0.8 }, { outfit: 'apron' }, { outfit: 'smock' }, { outfit: 'cloak' },
    { roleHat: 'kettle' }, { roleHat: 'biretta' }, { extra: 'shovel' }, { extra: 'bundle' }, { extra: 'ledger' }, { extra: 'bow' }
  ];
  for (const k of kinds) {
    const c = fakeCtx();
    const look = Object.assign(LOOK(), k);
    assert.strictEqual(Figure.drawExtras(c, makeP(), POSE(), look, { fx: 2, lw: 1, alpha: 1 }), true, JSON.stringify(k));
    assert.ok(count(c, 'stroke') >= 1, JSON.stringify(k));
    assert.ok(c.calls.filter((x) => x.fn === 'moveTo' || x.fn === 'lineTo' || x.fn === 'arc' || x.fn === 'ellipse' || x.fn === 'quadraticCurveTo').length > 1, JSON.stringify(k));
  }
  // Plain / none draws nothing but succeeds.
  const c = fakeCtx();
  assert.strictEqual(Figure.drawExtras(c, makeP(), POSE(), LOOK(), {}), true);
  assert.strictEqual(count(c, 'stroke'), 0);
});

test('extras without slots 24/25 fall back near the hand', () => {
  const P = makeP();
  P.X = P.X.slice(0, 24); P.Y = P.Y.slice(0, 24); P.Z = P.Z.slice(0, 24);
  for (const extra of ['shovel', 'bundle', 'ledger']) {
    const c = fakeCtx();
    assert.strictEqual(Figure.drawExtras(c, P, POSE(), Object.assign(LOOK(), { extra }), {}), true);
    assert.ok(count(c, 'stroke') >= 1);
  }
});

test('drawGrabArmsVol strokes capsules and accepts a renderer or a ctx', () => {
  const P = makeP();
  const r = { octx: fakeCtx(), ow: 640, oh: 360, wscale: 1 };
  assert.strictEqual(Figure.drawGrabArmsVol(r, P.X, P.Y, 300, 1.5, 0.9, 0.5, 1.2, 3, '#fff', 1), true);
  assert.ok(count(r.octx, 'stroke') >= 4);
  assert.strictEqual(count(r.octx, 'arc') >= 4, true);
  assert.strictEqual(count(r.octx, 'save'), count(r.octx, 'restore'));
  const c = fakeCtx();
  assert.strictEqual(Figure.drawGrabArmsVol(c, P.X, P.Y, 300, 1.5, 0.9, 0, 0, 0, '#fff', 0), true);
});

test('garbage input never throws', () => {
  const junk = [undefined, null, 0, NaN, 'x', {}, [], () => 1, { X: [], Y: [] }, { X: [NaN], Y: [NaN] }, { moveTo() { throw new Error('boom'); } }];
  const P = makeP();
  for (const a of junk) {
    for (const b of junk) {
      assert.doesNotThrow(() => {
        Figure.capsule(a, 1, 2, 3, 4, 5, 6);
        Figure.capsule(fakeCtx(), a, b, a, b, a, b);
        Figure.parts(a, b, a, b);
        Figure.parts(P, a, b, []);
        Figure.sortBackToFront(a, b);
        Figure.draw(a, b, a, P, b, a, b);
        Figure.draw(fakeCtx(), 1, '#fff', a, b, a, b);
        Figure.draw(fakeCtx(), a, b, P, a, b, a);
        Figure.drawExtras(a, P, b, a, b);
        Figure.drawExtras(fakeCtx(), a, b, a, b);
        Figure.drawExtras(fakeCtx(), P, a, b, a);
        Figure.drawFlush(a, P, b, a, b);
        Figure.drawFlush(fakeCtx(), P, a, b, a);
        Figure.drawFlush(fakeCtx(), P, a, [a, b, a, b], b);
        Figure.drawGrabArmsVol(a, b, a, b, a, b, a, b, a, b, a);
        Figure.drawGrabArmsVol(fakeCtx(), P.X, P.Y, a, b, a, b, a, b, a, b, a);
      });
    }
  }
  // A throwing ctx leaves the call returning false rather than raising.
  const bad = { save() {}, restore() {}, beginPath() { throw new Error('x'); }, moveTo() {}, stroke() {} };
  assert.doesNotThrow(() => Figure.draw(bad, 1, '#fff', P, POSE(), LOOK(), { fx: 2 }));
  assert.strictEqual(Figure.draw(bad, 1, '#fff', P, POSE(), LOOK(), { fx: 2 }), false);
});

test('look keys may be absent or odd without throwing', () => {
  const c = fakeCtx();
  assert.strictEqual(Figure.draw(c, 1, '#fff', makeP(), {}, {}, { fx: 2 }), true);
  assert.strictEqual(Figure.draw(c, 1, '#fff', makeP(), POSE(), { outfit: '__proto__', roleHat: 7, extra: {}, shoulder: 'big', hem: NaN, skin: -3, stoop: 9 }, { fx: 2 }), true);
});

test('module attaches to VCS and index.html loads it before render.js', () => {
  assert.strictEqual(globalThis.VCS.Figure, Figure);
  const html = require('node:fs').readFileSync(require('node:path').join(__dirname, '..', 'index.html'), 'utf8');
  const a = html.indexOf('js/figure.js');
  const b = html.indexOf('js/render.js');
  assert.ok(a > 0 && b > a);
});
