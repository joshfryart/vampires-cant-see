'use strict';
const test = require('node:test');
const assert = require('node:assert');
const Log = require('../js/log.js');
const Checks = require('../js/checks.js');

Log.setConsole(false);

function fullEnv() {
  const store = new Map();
  return {
    document: {
      createElement: () => ({ getContext: () => ({}), requestPointerLock() {} })
    },
    localStorage: {
      setItem: (k, v) => store.set(k, v),
      getItem: (k) => (store.has(k) ? store.get(k) : null),
      removeItem: (k) => store.delete(k)
    },
    Element: { prototype: { requestPointerLock() {} } },
    AudioContext: function () {},
    location: { protocol: 'file:' }
  };
}
const byId = (res, id) => res.results.find((r) => r.id === id);

test('full fake env passes everything', () => {
  const res = Checks.run(fullEnv());
  assert.strictEqual(res.ok, true);
  assert.strictEqual(res.results.length, 5);
  assert.ok(res.results.every((r) => r.ok));
  assert.strictEqual(byId(res, 'canvas2d').required, true);
  assert.match(byId(res, 'fileProtocol').message, /file/i);
});

test('empty object env does not throw; required fails', () => {
  const res = Checks.run({});
  assert.strictEqual(res.ok, false);
  assert.strictEqual(byId(res, 'canvas2d').ok, false);
  assert.strictEqual(byId(res, 'storage').ok, false);
  assert.match(byId(res, 'storage').message, /not be saved/);
  assert.strictEqual(byId(res, 'pointerLock').message, 'Mouse look unavailable; use arrow keys to turn');
  assert.strictEqual(byId(res, 'audio').ok, false);
  assert.strictEqual(byId(res, 'fileProtocol').ok, true);
});

test('non-object env does not throw', () => {
  assert.doesNotThrow(() => Checks.run(null));
  assert.doesNotThrow(() => Checks.run(42));
});

test('getContext throwing fails canvas2d only', () => {
  const env = fullEnv();
  env.document.createElement = () => ({ getContext() { throw new Error('no'); } });
  const res = Checks.run(env);
  assert.strictEqual(res.ok, false);
  assert.strictEqual(byId(res, 'canvas2d').ok, false);
  assert.strictEqual(byId(res, 'storage').ok, true);
  assert.strictEqual(byId(res, 'pointerLock').ok, true, 'falls back to Element.prototype');
});

test('storage that does not read back is an optional failure', () => {
  const env = fullEnv();
  env.localStorage.getItem = () => null;
  const res = Checks.run(env);
  assert.strictEqual(byId(res, 'storage').ok, false);
  assert.strictEqual(byId(res, 'storage').required, false);
  assert.strictEqual(res.ok, true);
});

test('storage throwing is optional failure', () => {
  const env = fullEnv();
  env.localStorage.setItem = () => { throw new Error('denied'); };
  const res = Checks.run(env);
  assert.strictEqual(res.ok, true);
  assert.strictEqual(byId(res, 'storage').ok, false);
  assert.strictEqual(byId(res, 'storage').required, false);
});

test('webkitAudioContext and http protocol', () => {
  const env = fullEnv();
  delete env.AudioContext;
  env.webkitAudioContext = function () {};
  env.location.protocol = 'https:';
  const res = Checks.run(env);
  assert.strictEqual(byId(res, 'audio').ok, true);
  assert.strictEqual(byId(res, 'fileProtocol').ok, true);
});

test('logs results', () => {
  Log.clear();
  Checks.run({});
  const e = Log.entries();
  assert.ok(e.some((x) => x.level === 'ERROR'));
  assert.ok(e.some((x) => x.level === 'WARN'));
  assert.ok(e.some((x) => x.level === 'INFO'));
});
