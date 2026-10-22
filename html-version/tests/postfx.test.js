'use strict';
const test = require('node:test');
const assert = require('node:assert');

require('../js/log.js');
const PostFx = require('../js/postfx.js');

// ctx that logs every method call and every property write; `refuse` lists composite ops it will not accept.
function mk(refuse) {
  const log = [];
  const state = { globalAlpha: 1, fillStyle: '#000', globalCompositeOperation: 'source-over', filter: 'none', imageSmoothingEnabled: false };
  const ctx = new Proxy({}, {
    get(t, p) {
      if (p in state) return state[p];
      return function () { log.push({ fn: String(p), args: Array.prototype.slice.call(arguments), alpha: state.globalAlpha, op: state.globalCompositeOperation, fill: state.fillStyle }); };
    },
    set(t, p, v) {
      log.push({ set: String(p), v });
      if (p === 'globalCompositeOperation' && refuse && refuse.indexOf(v) >= 0) return true;
      state[p] = v;
      return true;
    }
  });
  return { ctx, log, state };
}
function rig(over) {
  const g = mk();
  const r = Object.assign({ canvas: { width: 640, height: 360 }, off: {}, glow: { width: 320, height: 180 }, gctx: g.ctx, quality: 4, hasFilter: true }, over || {});
  return { r, g };
}

test('fx 0: grade and levels make zero ctx calls or writes', () => {
  const { r } = rig();
  const m = mk();
  assert.strictEqual(PostFx.grade(r, m.ctx, { dusk: 1, dawn: 1 }, 0), false);
  assert.strictEqual(m.log.length, 0);
  assert.strictEqual(PostFx.grainLevel(0), 0.04);
  assert.strictEqual(PostFx.vignetteOpacity(0), null);
});

test('fx 0/1 below quality 4: bloom is a no-op with zero ctx calls', () => {
  for (const fx of [0, 1]) {
    const { r, g } = rig({ quality: 3 });
    const m = mk();
    assert.strictEqual(PostFx.bloom(r, m.ctx, fx), false);
    assert.strictEqual(m.log.length, 0);
    assert.strictEqual(g.log.length, 0);
  }
  const { r, g } = rig({ quality: 2 });
  const m = mk();
  assert.strictEqual(PostFx.bloom(r, m.ctx, 2), false);
  assert.strictEqual(m.log.length + g.log.length, 0);
});

test('quality 4 bloom keeps today: alpha 0.85, lighter, at fx 0 too', () => {
  for (const fx of [0, 1, 2]) {
    const { r, g } = rig({ quality: 4 });
    const m = mk();
    assert.strictEqual(PostFx.bloom(r, m.ctx, fx), true);
    assert.strictEqual(m.state.globalAlpha, 0.85);
    const d = m.log.find((e) => e.fn === 'drawImage');
    assert.strictEqual(d.op, 'lighter');
    assert.ok(g.log.some((e) => e.set === 'filter' && e.v === 'blur(1.6px)'));
  }
});

test('fx 2 quality 3 bloom: alpha 0.55 with filter, skipped without', () => {
  const { r } = rig({ quality: 3 });
  const m = mk();
  assert.strictEqual(PostFx.bloom(r, m.ctx, 2), true);
  assert.strictEqual(m.state.globalAlpha, 0.55);
  const rig2 = rig({ quality: 3, hasFilter: false });
  const m2 = mk();
  assert.doesNotThrow(() => PostFx.bloom(rig2.r, m2.ctx, 2));
  assert.strictEqual(PostFx.bloom(rig2.r, m2.ctx, 2), false);
  assert.strictEqual(m2.log.length, 0);
});

test('bloom skips when lighter is not supported', () => {
  const { r } = rig({ quality: 4 });
  const m = mk(['lighter']);
  assert.strictEqual(PostFx.bloom(r, m.ctx, 2), false);
  assert.ok(!m.log.some((e) => e.fn === 'drawImage'));
});

test('grade: dusk and dawn alpha caps hold, state restored', () => {
  for (const fx of [1, 2]) {
    const m = mk();
    const r = { canvas: { width: 640, height: 360 } };
    assert.strictEqual(PostFx.grade(r, m.ctx, { dusk: 5, dawn: 0 }, fx), true);
    const f = m.log.filter((e) => e.fn === 'fillRect');
    assert.strictEqual(f.length, 1);
    assert.ok(f[0].alpha <= 0.10 + 1e-9);
    assert.strictEqual(f[0].op, 'multiply');
    assert.strictEqual(m.state.globalCompositeOperation, 'source-over');
    assert.strictEqual(m.state.globalAlpha, 1);

    const m2 = mk();
    PostFx.grade(r, m2.ctx, { dusk: 0, dawn: 9 }, fx);
    const f2 = m2.log.filter((e) => e.fn === 'fillRect');
    assert.strictEqual(f2.length, 2);
    assert.strictEqual(f2[0].op, 'multiply');
    assert.ok(f2[0].alpha <= 0.12 + 1e-9);
    assert.strictEqual(f2[1].op, 'saturation');
    assert.ok(f2[1].alpha <= 0.25 + 1e-9);
    assert.strictEqual(m2.state.globalCompositeOperation, 'source-over');
    assert.strictEqual(m2.state.globalAlpha, 1);
  }
});

test('grade: no grade amounts or unsupported ops draw nothing / skip passes', () => {
  const r = { canvas: { width: 640, height: 360 } };
  const m = mk();
  assert.strictEqual(PostFx.grade(r, m.ctx, { dusk: 0, dawn: 0 }, 2), false);
  assert.strictEqual(m.log.length, 0);
  const m2 = mk(['multiply', 'saturation']);
  assert.strictEqual(PostFx.grade(r, m2.ctx, { dusk: 1, dawn: 1 }, 2), false);
  assert.ok(!m2.log.some((e) => e.fn === 'fillRect'));
  const m3 = mk(['saturation']);
  PostFx.grade(r, m3.ctx, { dusk: 0, dawn: 1 }, 2);
  assert.strictEqual(m3.log.filter((e) => e.fn === 'fillRect').length, 1);
  assert.strictEqual(m3.state.globalCompositeOperation, 'source-over');
});

test('grainLevel and vignetteOpacity tables', () => {
  assert.strictEqual(PostFx.grainLevel(1), 0.035);
  assert.strictEqual(PostFx.grainLevel(2), 0.05);
  assert.strictEqual(PostFx.vignetteOpacity(1), 0.7);
  assert.strictEqual(PostFx.vignetteOpacity(2), 1);
  assert.strictEqual(PostFx.grainLevel(9), 0.05);
  assert.strictEqual(PostFx.grainLevel(-3), 0.04);
  assert.strictEqual(PostFx.grainLevel(NaN), 0.04);
});

test('garbage args never throw', () => {
  const junk = [undefined, null, 0, 'x', NaN, {}, [], () => 1, { canvas: null }, { get canvas() { throw new Error('x'); } }];
  const throwing = new Proxy({}, { get() { throw new Error('boom'); }, set() { throw new Error('boom'); } });
  for (const a of junk.concat([throwing])) {
    for (const b of junk.concat([throwing])) {
      assert.doesNotThrow(() => { PostFx.bloom(a, b, 2); PostFx.bloom(a, b); });
      assert.doesNotThrow(() => { PostFx.grade(a, b, a, 2); PostFx.grade(a, b, b, NaN); });
    }
    assert.doesNotThrow(() => { PostFx.grainLevel(a); PostFx.vignetteOpacity(a); });
  }
});
