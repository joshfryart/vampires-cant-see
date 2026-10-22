'use strict';
const test = require('node:test');
const assert = require('node:assert');
const Sys = require('../js/system.js');

test('register orders systems and runs lifecycle', () => {
  Sys._clear();
  const calls = [];
  Sys.register({ id: 'b', order: 20, init: () => calls.push('init b'), update: (dt) => calls.push('up b ' + dt), teardown: () => calls.push('td b') });
  Sys.register({ id: 'a', order: 10, init: () => calls.push('init a'), update: () => calls.push('up a') });
  assert.strictEqual(Sys.count(), 2);
  assert.strictEqual(Sys.register({ id: 'a' }), false);
  assert.strictEqual(Sys.register({}), false);
  assert.strictEqual(Sys.register({ id: 'constructor' }), false);
  Sys.initAll({});
  Sys.initAll({}); // idempotent
  Sys.update(0.5, {});
  Sys.teardownAll({});
  assert.deepStrictEqual(calls, ['init a', 'init b', 'up a', 'up b 0.5', 'td b']);
});

test('throwing system is isolated and auto-disabled', () => {
  Sys._clear();
  let good = 0, bad = 0;
  const tripped = [];
  Sys.on('sys:tripped', (p) => tripped.push(p.id));
  Sys.register({ id: 'bad', order: 1, update() { bad++; throw new Error('x'); } });
  Sys.register({ id: 'good', order: 2, update() { good++; } });
  Sys.update(1, {});
  Sys.update(1, {});
  assert.strictEqual(bad, 1);
  assert.strictEqual(good, 2);
  assert.strictEqual(Sys.isDisabled('bad'), true);
  assert.deepStrictEqual(tripped, ['bad']);
  Sys.enable('bad');
  assert.strictEqual(Sys.isDisabled('bad'), false);
});

test('event bus on/off/emit with error isolation', () => {
  Sys._clear();
  const got = [];
  const h = (p) => got.push(p);
  Sys.on('e', () => { throw new Error('h'); });
  Sys.on('e', h);
  assert.strictEqual(Sys.emit('e', 1), 1);
  Sys.off('e', h);
  Sys.emit('e', 2);
  assert.deepStrictEqual(got, [1]);
  assert.strictEqual(Sys.emit('none'), 0);
  assert.strictEqual(Sys.on('e', 'notfn'), false);
});
