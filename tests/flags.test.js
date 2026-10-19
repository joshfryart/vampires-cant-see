'use strict';
const test = require('node:test');
const assert = require('node:assert');
const Flags = require('../js/flags.js');

function fakeStore(init) {
  const m = Object.assign({}, init || {});
  global.localStorage = { getItem: (k) => (k in m ? m[k] : null), setItem: (k, v) => { m[k] = String(v); }, _m: m };
  return m;
}
function fresh() { Flags._clear(); delete global.localStorage; }

test('parseSys / parseTun', () => {
  const s = Flags.parseSys('a.b:on,c.d:off,bad,x:maybe,__proto__:on,e:1');
  assert.deepStrictEqual(Object.assign({}, s), { 'a.b': true, 'c.d': false, e: true });
  const t = Flags.parseTun('s.k:0.5,s.j:abc,nodot:3,__proto__.x:1');
  assert.deepStrictEqual(Object.assign({}, t), { 's.k': 0.5 });
  assert.deepStrictEqual(Object.assign({}, Flags.parseSys(null)), {});
});

test('default, then storage, then URL precedence', () => {
  fresh();
  const m = fakeStore({ 'vcs.dev.flags': JSON.stringify({ a: true, b: true }) });
  Flags.register('a', false, 'A');
  Flags.register('b', false);
  Flags.register('c', true);
  Flags.load('?sys=b:off');
  assert.strictEqual(Flags.get('a'), true); // storage
  assert.strictEqual(Flags.get('b'), false); // URL beats storage
  assert.strictEqual(Flags.get('c'), true); // default
  assert.strictEqual(Flags.get('nope'), false);
  Flags.load('?sys=b:off', false); // storage ignored
  assert.strictEqual(Flags.get('a'), false);
  assert.ok(m);
});

test('register after load still honours URL', () => {
  fresh();
  Flags.load('?sys=late:on&tun=s.k:2');
  Flags.register('late', false);
  Flags.registerTun('s', 'k', { value: 1, min: 0, max: 5, step: 1 });
  assert.strictEqual(Flags.get('late'), true);
  assert.strictEqual(Flags.tun('s', 'k'), 2);
});

test('tunables clamp and validate', () => {
  fresh();
  Flags.registerTun('s', 'k', { value: 1, min: 0, max: 2, step: 0.1 });
  Flags.load('?tun=s.k:99');
  assert.strictEqual(Flags.tun('s', 'k'), 2);
  assert.strictEqual(Flags.setTun('s', 'k', -5), true);
  assert.strictEqual(Flags.tun('s', 'k'), 0);
  assert.strictEqual(Flags.setTun('s', 'k', 'x'), false);
  assert.strictEqual(Flags.setTun('s', 'k', null), false);
  assert.strictEqual(Flags.setTun('s', 'zz', 1), false);
  assert.strictEqual(Flags.registerTun('s', 'bad', { value: 1, min: 3, max: 2 }), false);
  assert.strictEqual(Flags.registerTun('__proto__', 'x', { value: 1, min: 0, max: 2 }), false);
  assert.strictEqual(Flags.register('__proto__', true), false);
});

test('toJSON / fromJSON round trip, proto rejection', () => {
  fresh();
  fakeStore();
  Flags.register('x.y', false);
  Flags.registerTun('x', 'k', { value: 1, min: 0, max: 10, step: 1 });
  Flags.set('x.y', true);
  Flags.setTun('x', 'k', 7);
  const j = JSON.parse(JSON.stringify(Flags.toJSON()));
  assert.deepStrictEqual(j, { flags: { 'x.y': true }, tun: { x: { k: 7 } } });
  Flags.resetAll();
  assert.strictEqual(Flags.get('x.y'), false);
  assert.strictEqual(Flags.fromJSON(j), 2);
  assert.strictEqual(Flags.tun('x', 'k'), 7);
  Flags.resetAll();
  const evil = '{"flags":{"__proto__":true,"x.y":"yes"},"tun":{"__proto__":{"k":1},"x":{"k":99,"constructor":1}}}';
  assert.strictEqual(Flags.fromJSON(evil), 1); // only x.k clamped to 10
  assert.strictEqual(Flags.tun('x', 'k'), 10);
  assert.strictEqual(({}).k, undefined);
  assert.strictEqual(Flags.fromJSON('not json'), 0);
  assert.strictEqual(Flags.fromJSON(null), 0);
});

test('change listeners fire, throwing listener isolated, unsubscribe', () => {
  fresh();
  Flags.register('f', false);
  const seen = [];
  Flags.onChange(() => { throw new Error('boom'); });
  const off = Flags.onChange((e) => seen.push(e));
  Flags.set('f', true);
  Flags.set('f', true); // no change
  assert.strictEqual(seen.length, 1);
  assert.deepStrictEqual(seen[0], { kind: 'flag', id: 'f', value: true });
  off();
  Flags.set('f', false);
  assert.strictEqual(seen.length, 1);
});

test('persists to storage and survives throwing storage', () => {
  fresh();
  const m = fakeStore();
  Flags.register('p', false);
  Flags.set('p', true);
  assert.deepStrictEqual(JSON.parse(m['vcs.dev.flags']), { p: true });
  global.localStorage = { getItem() { throw new Error('denied'); }, setItem() { throw new Error('denied'); } };
  Flags.load('');
  assert.strictEqual(Flags.get('p'), false);
  assert.doesNotThrow(() => Flags.set('p', true));
  assert.strictEqual(Flags.get('p'), true);
  delete global.localStorage;
});
