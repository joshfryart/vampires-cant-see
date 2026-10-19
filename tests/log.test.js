'use strict';
const test = require('node:test');
const assert = require('node:assert');
const Log = require('../js/log.js');

function fakeStorage(throwOnSet) {
  const m = new Map();
  return {
    m,
    getItem: (k) => (m.has(k) ? m.get(k) : null),
    setItem: (k, v) => { if (throwOnSet) throw new Error('quota'); m.set(k, String(v)); },
    removeItem: (k) => m.delete(k)
  };
}

test.beforeEach(() => {
  Log.setConsole(false);
  Log.setLevel('INFO');
  Log.clear();
  delete globalThis.localStorage;
});

test('version', () => assert.strictEqual(Log.VERSION, '0.10.4'));

test('ring buffer caps at 500 and keeps newest', () => {
  const l = Log.get('t');
  for (let i = 0; i < 650; i++) l.info('m' + i);
  const e = Log.entries();
  assert.strictEqual(e.length, 500);
  assert.strictEqual(e[499].msg, 'm649');
  assert.strictEqual(e[0].msg, 'm150');
  e.pop();
  assert.strictEqual(Log.entries().length, 500, 'entries() returns a copy');
});

test('message coerced and truncated to 500 chars', () => {
  const l = Log.get('t');
  l.info('x'.repeat(900));
  l.info(12345);
  const e = Log.entries();
  assert.strictEqual(e[0].msg.length, 500);
  assert.strictEqual(e[1].msg, '12345');
});

test('level filtering', () => {
  const l = Log.get('t');
  l.debug('d');
  l.info('i');
  assert.strictEqual(Log.entries().length, 1);
  Log.setLevel('DEBUG');
  l.debug('d2');
  assert.strictEqual(Log.entries().length, 2);
  Log.setLevel('ERROR');
  l.warn('w');
  l.error('e');
  assert.strictEqual(Log.entries().length, 3);
  assert.strictEqual(Log.entries()[2].level, 'ERROR');
});

test('format string shape', () => {
  const line = Log.format({ t: '2026-10-17T12:00:00.000Z', level: 'INFO', module: 'game', msg: 'message' });
  assert.strictEqual(line, '2026-10-17T12:00:00.000Z INFO  game  message');
  const err = Log.format({ t: 'T', level: 'ERROR', module: 'a', msg: 'boom', stack: 'Error: x\n at y' });
  const lines = err.split('\n');
  assert.strictEqual(lines.length, 3);
  assert.ok(lines[1].startsWith('    '));
});

test('entry shape and error stack', () => {
  Log.get('mod').error('bad', new Error('oops'));
  const e = Log.entries()[0];
  assert.match(e.t, /^\d{4}-\d\d-\d\dT/);
  assert.strictEqual(e.level, 'ERROR');
  assert.strictEqual(e.module, 'mod');
  assert.ok(e.stack.includes('oops'));
});

test('asText returns last n lines', () => {
  const l = Log.get('t');
  for (let i = 0; i < 10; i++) l.info('line' + i);
  const t = Log.asText(3).split('\n');
  assert.strictEqual(t.length, 3);
  assert.ok(t[2].endsWith('line9'));
});

test('report contains version and last lines', () => {
  const l = Log.get('t');
  for (let i = 0; i < 60; i++) l.info('row' + i);
  const r = Log.report({ code: 'E_TEST', message: 'hello' });
  assert.ok(r.includes('0.10.4'));
  assert.ok(r.includes('E_TEST'));
  assert.ok(r.includes('hello'));
  assert.ok(r.includes('row59'));
  assert.ok(r.includes('row10'));
  assert.ok(!r.includes('row9\n') && !/row9$/m.test(r), 'only last 50 lines');
});

test('persists to localStorage, throttled, immediate on ERROR', () => {
  const ls = fakeStorage();
  globalThis.localStorage = ls;
  const l = Log.get('t');
  l.info('a'); // first write persists
  l.info('b'); // throttled
  let saved = JSON.parse(ls.m.get('vcs.log'));
  assert.strictEqual(saved.length, 1);
  l.error('c'); // immediate
  saved = JSON.parse(ls.m.get('vcs.log'));
  assert.deepStrictEqual(saved.map((e) => e.msg), ['a', 'b', 'c']);
  assert.deepStrictEqual(Log.loadPersisted().map((e) => e.msg), ['a', 'b', 'c']);
});

test('persists only last 200', () => {
  const ls = fakeStorage();
  globalThis.localStorage = ls;
  const l = Log.get('t');
  for (let i = 0; i < 300; i++) l.info('m' + i);
  l.error('end');
  const saved = JSON.parse(ls.m.get('vcs.log'));
  assert.strictEqual(saved.length, 200);
  assert.strictEqual(saved[199].msg, 'end');
});

test('survives localStorage.setItem throwing', () => {
  globalThis.localStorage = fakeStorage(true);
  const l = Log.get('t');
  assert.doesNotThrow(() => { l.info('x'); l.error('y'); });
  assert.strictEqual(Log.entries().length, 2);
  assert.deepStrictEqual(Log.loadPersisted(), []);
});

test('works with no localStorage and bad persisted JSON', () => {
  assert.deepStrictEqual(Log.loadPersisted(), []);
  const ls = fakeStorage();
  ls.m.set('vcs.log', '{not json');
  globalThis.localStorage = ls;
  assert.deepStrictEqual(Log.loadPersisted(), []);
});

test('subscribe and unsubscribe', () => {
  const got = [];
  const un = Log.subscribe((e) => got.push(e.msg));
  Log.get('t').info('one');
  un();
  Log.get('t').info('two');
  assert.deepStrictEqual(got, ['one']);
});

test('installGlobalHandlers is a no-op in Node', () => {
  assert.doesNotThrow(() => Log.installGlobalHandlers(() => {}));
});
