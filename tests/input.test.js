'use strict';
// Merged test file: each source file's tests live in their own describe().
const { describe } = require('node:test');

describe('input-feed.test.js', () => {

  const test = require('node:test');
  const assert = require('node:assert');
  require('../js/log.js').setConsole(false);
  const Input = require('../js/input.js');

  function fakeCanvas() {
    const ls = {};
    const doc = { pointerLockElement: null, addEventListener() {}, removeEventListener() {} };
    return {
      ls, ownerDocument: doc,
      addEventListener(t, f) { (ls[t] = ls[t] || []).push(f); },
      removeEventListener(t, f) { ls[t] = (ls[t] || []).filter((x) => x !== f); },
      fire(t, e) { (ls[t] || []).slice().forEach((f) => f(e)); }
    };
  }

  test('right mousedown counts a feed when lock unavailable', () => {
    const g = globalThis;
    g.addEventListener = g.addEventListener || (() => {});
    g.removeEventListener = g.removeEventListener || (() => {});
    const c = fakeCanvas();
    const inp = Input.create(c, {});
    c.fire('mousedown', { button: 2 });
    assert.strictEqual(inp.consumeFeeds(), 1);
    assert.strictEqual(inp.consumeFeeds(), 0);
    assert.strictEqual(inp.consumeClicks(), 0);
    c.fire('mousedown', { button: 0 });
    c.fire('mouseup', { button: 0 });
    assert.strictEqual(inp.consumeClicks(), 1);
    assert.strictEqual(inp.consumeFeeds(), 0);
    let prevented = 0;
    c.fire('contextmenu', { preventDefault() { prevented++; } });
    assert.strictEqual(prevented, 1);
    inp.destroy();
    assert.strictEqual((c.ls.mousedown || []).length, 0);
    assert.strictEqual((c.ls.contextmenu || []).length, 0);
  });

  test('feedHeld tracks right button, cleared by mouseup, unlock and blur', () => {
    const g = globalThis;
    const wl = {};
    g.addEventListener = (t, f) => { (wl[t] = wl[t] || []).push(f); };
    g.removeEventListener = (t, f) => { wl[t] = (wl[t] || []).filter((x) => x !== f); };
    const dls = {};
    const c = fakeCanvas();
    c.ownerDocument.addEventListener = (t, f) => { (dls[t] = dls[t] || []).push(f); };
    const inp = Input.create(c, {});
    assert.strictEqual(inp.feedHeld(), false);
    c.fire('mousedown', { button: 2 });
    assert.strictEqual(inp.feedHeld(), true);
    c.fire('mouseup', { button: 0 });
    assert.strictEqual(inp.feedHeld(), true);
    c.fire('mouseup', { button: 2 });
    assert.strictEqual(inp.feedHeld(), false);
    assert.strictEqual(inp.consumeFeeds(), 1);
    // left button never sets it
    c.fire('mousedown', { button: 0 });
    assert.strictEqual(inp.feedHeld(), false);
    // pointer unlock
    c.fire('mousedown', { button: 2 });
    assert.strictEqual(inp.feedHeld(), true);
    (dls.pointerlockchange || []).forEach((f) => f());
    assert.strictEqual(inp.feedHeld(), false);
    // blur
    c.fire('mousedown', { button: 2 });
    assert.strictEqual(inp.feedHeld(), true);
    (wl.blur || []).forEach((f) => f());
    assert.strictEqual(inp.feedHeld(), false);
    // window-level mouseup (released outside canvas)
    c.fire('mousedown', { button: 2 });
    (wl.mouseup || []).forEach((f) => f({ button: 2 }));
    assert.strictEqual(inp.feedHeld(), false);
    inp.destroy();
  });

  function setup(cfg, extra) {
    const g = globalThis;
    const wl = {};
    g.addEventListener = (t, f) => { (wl[t] = wl[t] || []).push(f); };
    g.removeEventListener = (t, f) => { wl[t] = (wl[t] || []).filter((x) => x !== f); };
    const dls = {};
    const c = fakeCanvas();
    c.ownerDocument.addEventListener = (t, f) => { (dls[t] = dls[t] || []).push(f); };
    Object.assign(c, extra || {});
    const inp = Input.create(c, cfg || {});
    return { c, inp, wl, dls, key: (t, code, rep) => (wl[t] || []).forEach((f) => f({ code, repeat: !!rep, preventDefault() {} })),
      move: (mx, my) => (dls.mousemove || []).forEach((f) => f({ movementX: mx, movementY: my || 0 })) };
  }

  test('arrow keys, KeyC and KeyR are tracked', () => {
    const t = setup({});
    t.key('keydown', 'ArrowUp'); t.key('keydown', 'KeyC');
    assert.ok(t.inp.keys.has('ArrowUp') && t.inp.keys.has('KeyC'));
    assert.ok(t.inp.consumePressed().has('KeyC'));
    t.inp.destroy();
  });

  test('mouse spikes clamp to 300, bogus > 1000 dropped', () => {
    const t = setup({});
    t.c.ownerDocument.pointerLockElement = t.c;
    t.move(500, -400);
    assert.deepStrictEqual(t.inp.consumeMouseDelta(), { dx: 300, dy: -300 });
    t.move(1500, 5);
    assert.deepStrictEqual(t.inp.consumeMouseDelta(), { dx: 0, dy: 0 });
    t.move(40, 2);
    assert.deepStrictEqual(t.inp.consumeMouseDelta(), { dx: 40, dy: 2 });
    t.inp.destroy();
  });

  test('drag-look turns when unlocked; click without drag pulses (lock unavailable)', () => {
    const t = setup({ dragLook: true });
    assert.strictEqual(t.inp.lockUnavailable, true);
    t.move(50);
    assert.strictEqual(t.inp.consumeMouseDelta().dx, 0);
    t.c.fire('mousedown', { button: 0 });
    t.move(50);
    assert.strictEqual(t.inp.consumeMouseDelta().dx, 50);
    t.c.fire('mouseup', { button: 0 });
    assert.strictEqual(t.inp.consumeClicks(), 0);
    t.move(50);
    assert.strictEqual(t.inp.consumeMouseDelta().dx, 0);
    t.c.fire('mousedown', { button: 0 });
    t.c.fire('mouseup', { button: 0 });
    assert.strictEqual(t.inp.consumeClicks(), 1);
    t.inp.destroy();
  });

  test('dragLook false keeps immediate pulse and no drag turning', () => {
    const t = setup({ dragLook: false });
    t.c.fire('mousedown', { button: 0 });
    assert.strictEqual(t.inp.consumeClicks(), 1);
    t.move(30);
    assert.strictEqual(t.inp.consumeMouseDelta().dx, 0);
    t.inp.destroy();
  });

  test('feedToggle: right-click and R report toggles, not holds', () => {
    const t = setup({ feedToggle: true });
    t.c.fire('mousedown', { button: 2 });
    t.key('keydown', 'KeyR');
    assert.strictEqual(t.inp.feedHeld(), false);
    assert.strictEqual(t.inp.consumeFeedToggle(), 2);
    assert.strictEqual(t.inp.consumeFeedToggle(), 0);
    assert.strictEqual(t.inp.consumeFeeds(), 0);
    t.inp.destroy();
  });

  test('hold mode: R held feeds, released clears; no toggles', () => {
    const t = setup({ feedToggle: false });
    t.key('keydown', 'KeyR');
    assert.strictEqual(t.inp.feedHeld(), true);
    t.key('keyup', 'KeyR');
    assert.strictEqual(t.inp.feedHeld(), false);
    assert.strictEqual(t.inp.consumeFeeds(), 1);
    assert.strictEqual(t.inp.consumeFeedToggle(), 0);
    t.inp.destroy();
  });

  test('requestLock tries unadjusted, falls back to plain; failure flags lockUnavailable', async () => {
    const calls = [];
    const t = setup({}, { requestPointerLock(o) { calls.push(o); if (o) return Promise.reject(new Error('NotSupported')); return undefined; } });
    assert.strictEqual(t.inp.lockUnavailable, false);
    assert.strictEqual(await t.inp.requestLock(), true);
    assert.deepStrictEqual(calls, [{ unadjustedMovement: true }, undefined]);
    t.inp.destroy();
    const t2 = setup({}, { requestPointerLock() { throw new TypeError('x'); } });
    let cbv = null;
    assert.strictEqual(await t2.inp.requestLock((ok) => { cbv = ok; }), false);
    assert.strictEqual(cbv, false);
    assert.strictEqual(t2.inp.lockUnavailable, true);
    t2.inp.destroy();
  });

  test('successful pointerlockchange clears lockUnavailable; isLocked reflects state', () => {
    const t = setup({}, { requestPointerLock() {} });
    (t.dls.pointerlockerror || []).forEach((f) => f());
    assert.strictEqual(t.inp.lockUnavailable, true);
    assert.strictEqual(t.inp.isLocked(), false);
    t.c.ownerDocument.pointerLockElement = t.c;
    (t.dls.pointerlockchange || []).forEach((f) => f());
    assert.strictEqual(t.inp.lockUnavailable, false);
    assert.strictEqual(t.inp.isLocked(), true);
    t.inp.destroy();
  });

});

