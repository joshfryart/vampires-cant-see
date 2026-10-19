'use strict';
const test = require('node:test');
const assert = require('node:assert');
const Dev = require('../js/devpanel.js');
const Flags = require('../js/flags.js');

test('exports the public API', () => {
  ['init', 'isOpen', 'open', 'close', 'toggle'].forEach((k) => assert.strictEqual(typeof Dev[k], 'function', k));
});

test('without a DOM, init declines and nothing throws', () => {
  assert.strictEqual(Dev.init({ f9: true }), false);
  assert.strictEqual(Dev.isOpen(), false);
  assert.strictEqual(Dev.open(), false);
  assert.strictEqual(Dev.close(), false);
  assert.strictEqual(Dev.toggle(), false);
  assert.strictEqual(Dev.isOpen(), false);
});

test('the panel data source (Flags) lists what the panel renders', () => {
  Flags._clear();
  Flags.register('demo.thing', false, 'A demo switch');
  Flags.registerTun('demo', 'amount', { min: 0, max: 10, step: 1, value: 5, desc: 'A demo slider' });
  assert.strictEqual(Flags.list().length, 1);
  assert.strictEqual(Flags.listTun()[0].def, 5);
  Flags.setTun('demo', 'amount', 8);
  assert.strictEqual(Flags.tun('demo', 'amount'), 8);
  Flags.resetAll();
  assert.strictEqual(Flags.tun('demo', 'amount'), 5);
  Flags._clear();
});
