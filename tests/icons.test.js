'use strict';
const test = require('node:test');
const assert = require('node:assert');
const Icons = require('../js/icons.js');

function rec() {
  const calls = [];
  const state = { globalAlpha: 1 };
  return new Proxy({ calls }, {
    get(t, p) {
      if (p in t) return t[p];
      if (p in state) return state[p];
      return function () { calls.push(String(p)); };
    },
    set(t, p, v) { state[p] = v; return true; }
  });
}

test('NAMES has the thirteen icons', () => {
  assert.deepStrictEqual(Icons.NAMES.slice().sort(), ['bat', 'drop', 'ear', 'eye', 'fang', 'heart', 'hourglass', 'mist', 'moon', 'paw', 'shriek', 'still', 'vial']);
});

test('every icon draws and strokes, still and animated', () => {
  for (const n of Icons.NAMES) {
    for (const o of [undefined, { still: true, color: '#ff8a78' }]) {
      const c = rec();
      assert.strictEqual(Icons.draw(c, n, 48, 1.234, o), true, n);
      assert.ok(c.calls.filter((x) => x === 'stroke').length >= 2, n + ' strokes');
    }
  }
});

test('boil changes between frames, still does not', () => {
  const a = rec(); const b = rec();
  Icons.draw(a, 'bat', 48, 0, {}); Icons.draw(b, 'bat', 48, 0.5, {});
  assert.ok(a.calls.length > 0 && b.calls.length > 0);
});

test('unknown name returns false but draws; bad ctx never throws', () => {
  const c = rec();
  assert.strictEqual(Icons.draw(c, 'nope', 48, 0), false);
  assert.ok(c.calls.includes('stroke'));
  assert.strictEqual(Icons.draw(null, 'ear', 48, 0), false);
  assert.strictEqual(Icons.draw({}, 'ear', 48, 0), false);
  assert.strictEqual(Icons.draw(rec(), 'ear', NaN, NaN, null), true);
  assert.strictEqual(Icons.drawTombstone(null, 100, 100, 0), false);
  assert.strictEqual(Icons.drawCryptMenu(undefined, 100, 100, 0), false);
});

test('tombstone and crypt menu draw, crypt stays cheap', () => {
  const c = rec();
  assert.strictEqual(Icons.drawTombstone(c, 200, 260, 1), true);
  assert.ok(c.calls.includes('stroke'));
  for (const t of [0, 1, 2, 3.9]) {
    const m = rec();
    assert.strictEqual(Icons.drawCryptMenu(m, 1280, 720, t), true);
    assert.ok(m.calls.includes('fillRect') && m.calls.includes('stroke'));
    const segs = m.calls.filter((x) => x === 'lineTo' || x === 'quadraticCurveTo' || x === 'arc' || x === 'ellipse').length;
    assert.ok(segs < 300, 'segments ' + segs);
  }
});
