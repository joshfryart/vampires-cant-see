'use strict';
const test = require('node:test');
const assert = require('node:assert');
const A = require('../js/data/archetypes.js');
const VoiceData = require('../js/data/voices.js');
const Sched = require('../js/schedule.js');

const ID_RE = /^[a-z][a-z0-9_]{1,23}$/;

function isDeepFrozen(o) {
  if (!o || typeof o !== 'object') return true;
  return Object.isFrozen(o) && Object.keys(o).every(function (k) { return isDeepFrozen(o[k]); });
}

test('archetype ids match the regex and are unique', () => {
  const seen = new Set();
  A.list.forEach((a) => {
    assert.match(a.id, ID_RE);
    assert.ok(!seen.has(a.id), 'dup ' + a.id);
    seen.add(a.id);
  });
  assert.strictEqual(A.list.length, 14);
});

test('legacy rows reproduce presetFor and groupOf', () => {
  const legacy = A.list.filter((a) => a.legacy);
  assert.strictEqual(legacy.length, 11);
  legacy.forEach((a) => {
    assert.strictEqual(a.voice, VoiceData.presetFor(a.role), a.id + ' voice');
    assert.strictEqual(a.talk, VoiceData.groupOf(a.role), a.id + ' talk');
    assert.ok(Object.prototype.hasOwnProperty.call(VoiceData.PRESETS, a.voice));
  });
});

test('legacy schedules equal schedule.js ROLES', () => {
  A.list.filter((a) => a.legacy && Array.isArray(a.schedule)).forEach((a) => {
    assert.deepStrictEqual(JSON.parse(JSON.stringify(a.schedule)), JSON.parse(JSON.stringify(Sched.ROLES[a.role])), a.id);
  });
  assert.strictEqual(A.byId('guard').schedule, 'watch');
});

test('byId and byRole use own props only', () => {
  assert.strictEqual(A.byId('guard').role, 'guard');
  assert.strictEqual(A.byRole('').id, 'patron');
  assert.strictEqual(A.byRole('priest').id, 'priest');
  ['__proto__', 'constructor', 'prototype', 'toString', 'hasOwnProperty', 'nope', null, 5, {}].forEach((k) => {
    assert.strictEqual(A.byId(k), null, String(k));
    assert.strictEqual(A.byRole(k), null, String(k));
  });
});

test('data is deep-frozen', () => {
  assert.ok(isDeepFrozen(A));
  assert.ok(Object.isFrozen(A.list[0].extras) && Object.isFrozen(A.LEGACY_RECIPE.bodies));
  assert.throws(() => { A.list.push({}); }, TypeError);
});

test('children are not feedable; guard and hunter keep watch', () => {
  assert.strictEqual(A.byId('child').feedable, false);
  assert.strictEqual(A.byId('guard').watch, true);
  assert.strictEqual(A.byId('hunter').speed, 1.3);
});
