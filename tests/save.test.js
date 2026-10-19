'use strict';
// Merged test file: each source file's tests live in their own describe().
const { describe } = require('node:test');

describe('save.test.js', () => {

  const test = require('node:test');
  const assert = require('node:assert');
  const Log = require('../js/log.js');
  if (Log && typeof Log.setConsole === 'function') Log.setConsole(false);
  require('../js/data/hunger.js');
  const Night = require('../js/night.js');
  const Save = require('../js/save.js');

  function fake(hooks) {
    const h = hooks || {};
    const m = new Map();
    return {
      m: m,
      getItem: function (k) {
        if (h.getItem) { const r = h.getItem(k, m); if (r !== undefined) return r; }
        return m.has(k) ? m.get(k) : null;
      },
      setItem: function (k, v) {
        if (h.setItem) h.setItem(k, v, m);
        m.set(k, String(v));
      },
      removeItem: function (k) { m.delete(k); }
    };
  }
  const META = { v: 1, essence: 3 };

  function validRun() {
    return {
      v: 4, map: 'town', player: { x: 1.5, y: 2.5, angle: 0.3 },
      doors: { town: [[1, 2], [3, 4]] }, people: { town: 12345 },
      night: Night.serialize(Night.create()),
      run: { seed: 99, boons: ['hush'], closedSafe: { town: [[5, 6]] }, pendingBoons: null, hunger: null, pendingGifts: null }
    };
  }

  test('checksum stable and 8 hex', () => {
    const a = Save.checksum('hello');
    assert.match(a, /^[0-9a-f]{8}$/);
    assert.strictEqual(a, Save.checksum('hello'));
    assert.notStrictEqual(a, Save.checksum('hellp'));
    assert.strictEqual(Save.checksum(''), '811c9dc5');
    assert.strictEqual(Save.checksum('a'), 'e40c292c');
    assert.match(Save.checksum('☃🦇'), /^[0-9a-f]{8}$/);
  });

  test('wrap/unwrap roundtrip', () => {
    const env = Save.wrap('meta', 1, { a: 1 });
    assert.strictEqual(env.app, 'vcs');
    assert.strictEqual(env.game, Log.VERSION);
    const u = Save.unwrap(JSON.parse(JSON.stringify(env)), 'meta');
    assert.deepStrictEqual([u.ok, u.v, u.data], [true, 1, { a: 1 }]);
  });

  test('unwrap rejects extra key, wrong kind, bad sum, junk', () => {
    const env = Save.wrap('meta', 1, { a: 1 });
    assert.strictEqual(Save.unwrap(Object.assign({ x: 1 }, env), 'meta').code, 'E_SAVE_SCHEMA');
    assert.strictEqual(Save.unwrap(env, 'run').code, 'E_SAVE_SCHEMA');
    assert.strictEqual(Save.unwrap(Object.assign({}, env, { sum: '00000000' }), 'meta').code, 'E_SAVE_CHECKSUM');
    assert.strictEqual(Save.unwrap(Object.assign({}, env, { app: 'x' }), 'meta').code, 'E_SAVE_SCHEMA');
    assert.strictEqual(Save.unwrap(Object.assign({}, env, { v: -1 }), 'meta').code, 'E_SAVE_SCHEMA');
    assert.strictEqual(Save.unwrap(Object.assign({}, env, { v: 1.5 }), 'meta').code, 'E_SAVE_SCHEMA');
    assert.strictEqual(Save.unwrap(null, 'meta').code, 'E_SAVE_SCHEMA');
    assert.strictEqual(Save.unwrap([], 'meta').code, 'E_SAVE_SCHEMA');
  });

  test('safeParse rejects dangerous keys, depth, bad json', () => {
    assert.strictEqual(Save.safeParse('{"__proto__":{"x":1}}').code, 'E_SAVE_BAD_KEY');
    assert.strictEqual(Save.safeParse('{"a":{"constructor":{"b":1}}}').code, 'E_SAVE_BAD_KEY');
    assert.strictEqual(Save.safeParse('{"a":[{"prototype":1}]}').code, 'E_SAVE_BAD_KEY');
    const deep = '['.repeat(20) + ']'.repeat(20);
    assert.strictEqual(Save.safeParse(deep).code, 'E_SAVE_SCHEMA');
    assert.strictEqual(Save.safeParse('{nope').code, 'E_SAVE_PARSE');
    assert.strictEqual(Save.safeParse(42).code, 'E_SAVE_PARSE');
    const okDeep = Save.safeParse('['.repeat(12) + ']'.repeat(12));
    assert.strictEqual(okDeep.ok, true);
    const good = Save.safeParse('{"a":[1,2,{"b":null}]}');
    assert.deepStrictEqual(good.value, { a: [1, 2, { b: null }] });
    assert.strictEqual({}.x, undefined);
  });

  test('write then read ok from main; second write makes bak', () => {
    const s = fake();
    const st = Save.create(s);
    assert.strictEqual(st.persistent, true);
    assert.deepStrictEqual(st.write('meta', 1, { n: 1 }), { ok: true, code: '' });
    const r = st.read('meta');
    assert.deepStrictEqual([r.ok, r.source, r.v, r.data], [true, 'main', 1, { n: 1 }]);
    assert.strictEqual(s.m.has('vcs.meta.bak'), false);
    assert.strictEqual(s.m.has('vcs.meta.tmp'), false);
    assert.strictEqual(st.write('meta', 1, { n: 2 }).ok, true);
    const bak = JSON.parse(s.m.get('vcs.meta.bak'));
    assert.deepStrictEqual(bak.data, { n: 1 });
    assert.strictEqual(st.has('meta'), true);
    assert.strictEqual(s.m.has('vcs.probe'), false);
  });

  test('read missing gives none', () => {
    const st = Save.create(fake());
    assert.deepStrictEqual(st.read('run'), { ok: false, v: 0, data: null, source: 'none', code: 'E_SAVE_NONE' });
    assert.strictEqual(st.has('run'), false);
  });

  test('corrupt main falls back to bak and repairs main', () => {
    const s = fake();
    const st = Save.create(s);
    st.write('run', 3, { n: 1 });
    st.write('run', 3, { n: 2 });
    const good = s.m.get('vcs.run');
    s.m.set('vcs.run', good.replace('"n":2', '"n":3'));
    const r = st.read('run');
    assert.strictEqual(r.ok, true);
    assert.strictEqual(r.source, 'bak');
    assert.strictEqual(r.code, 'E_SAVE_CHECKSUM');
    assert.deepStrictEqual(r.data, { n: 1 });
    assert.strictEqual(s.m.get('vcs.run'), s.m.get('vcs.run.bak'));
    const again = st.read('run');
    assert.strictEqual(again.source, 'main');
  });

  test('missing main with bak restores', () => {
    const s = fake();
    const st = Save.create(s);
    st.write('meta', 1, { n: 1 });
    st.write('meta', 1, { n: 2 });
    s.m.delete('vcs.meta');
    const r = st.read('meta');
    assert.deepStrictEqual([r.ok, r.source, r.code], [true, 'bak', 'E_SAVE_NONE']);
    assert.strictEqual(s.m.has('vcs.meta'), true);
  });

  test('both corrupt gives not ok', () => {
    const s = fake();
    const st = Save.create(s);
    st.write('meta', 1, { n: 1 });
    st.write('meta', 1, { n: 2 });
    s.m.set('vcs.meta', 'garbage{');
    s.m.set('vcs.meta.bak', s.m.get('vcs.meta.bak').replace('"n":1', '"n":9'));
    const r = st.read('meta');
    assert.deepStrictEqual([r.ok, r.source, r.code], [false, 'none', 'E_SAVE_PARSE']);
  });

  test('oversize write is rejected, oversize main read rejected', () => {
    const st = Save.create(fake(), { maxBytes: 100 });
    const r = st.write('meta', 1, { s: 'x'.repeat(500) });
    assert.deepStrictEqual(r, { ok: false, code: 'E_SAVE_TOO_BIG' });
    assert.strictEqual(st.has('meta'), false);
    const s = fake();
    Save.create(s).write('meta', 1, { s: 'x'.repeat(500) });
    const small = Save.create(s, { maxBytes: 100 });
    assert.strictEqual(small.read('meta').code, 'E_SAVE_TOO_BIG');
  });

  test('setItem throwing gives QUOTA and no tmp left', () => {
    let armed = false;
    const s = fake({ setItem: function (k) { if (armed && k === 'vcs.meta') throw new Error('quota'); } });
    const st = Save.create(s);
    armed = true;
    assert.deepStrictEqual(st.write('meta', 1, { a: 1 }), { ok: false, code: 'E_SAVE_QUOTA' });
    assert.strictEqual(s.m.has('vcs.meta.tmp'), false);
    assert.strictEqual(s.m.has('vcs.meta'), false);
    const s2 = fake({ setItem: function (k) { if (k.endsWith('.tmp')) throw new Error('quota'); } });
    const st2 = Save.create(s2);
    assert.strictEqual(st2.persistent, true);
    s2.m.clear();
    assert.strictEqual(st2.write('meta', 1, { a: 1 }).code, 'E_SAVE_QUOTA');
    assert.strictEqual(s2.m.has('vcs.meta.tmp'), false);
  });

  test('verify mismatch gives VERIFY and main unchanged', () => {
    let bad = false;
    const s = fake({ getItem: function (k, m) { if (bad && k === 'vcs.meta.tmp') return (m.get(k) || '') + ' '; return undefined; } });
    const st = Save.create(s);
    st.write('meta', 1, { n: 1 });
    const before = s.m.get('vcs.meta');
    bad = true;
    assert.deepStrictEqual(st.write('meta', 1, { n: 2 }), { ok: false, code: 'E_SAVE_VERIFY' });
    assert.strictEqual(s.m.get('vcs.meta'), before);
    assert.strictEqual(s.m.has('vcs.meta.tmp'), false);
  });

  test('null and throwing storage fall back to memory', () => {
    const st = Save.create(null);
    assert.strictEqual(st.persistent, false);
    assert.strictEqual(st.write('run', 3, { a: 1 }).ok, true);
    assert.deepStrictEqual(st.read('run').data, { a: 1 });
    const thrower = { getItem: function () { throw new Error('x'); }, setItem: function () { throw new Error('x'); }, removeItem: function () { throw new Error('x'); } };
    const st2 = Save.create(thrower);
    assert.strictEqual(st2.persistent, false);
    assert.strictEqual(st2.write('meta', 1, { a: 2 }).ok, true);
    assert.strictEqual(st2.has('meta'), true);
  });

  test('remove clears main, bak and tmp', () => {
    const s = fake();
    const st = Save.create(s);
    st.write('run', 3, { n: 1 });
    st.write('run', 3, { n: 2 });
    s.m.set('vcs.run.tmp', 'x');
    st.remove('run');
    assert.deepStrictEqual([...s.m.keys()], []);
    assert.strictEqual(st.has('run'), false);
  });

  test('exportText then parseImport roundtrip', () => {
    const st = Save.create(fake());
    st.write('meta', 1, { essence: 5 });
    st.write('run', 4, validRun());
    const text = Save.exportText(st);
    assert.ok(text.indexOf('\n  "app"') !== -1);
    const p = Save.parseImport(text);
    assert.strictEqual(p.ok, true);
    assert.deepStrictEqual(p.meta, { v: 1, data: { essence: 5 } });
    assert.deepStrictEqual(p.run, { v: 4, data: validRun() });
    const empty = Save.create(fake());
    const p2 = Save.parseImport(Save.exportText(empty));
    assert.strictEqual(p2.ok, false);
    empty.write('meta', 1, { essence: 1 });
    const p3 = Save.parseImport(Save.exportText(empty));
    assert.deepStrictEqual([p3.ok, p3.run], [true, null]);
  });

  test('parseImport rejections', () => {
    const st = Save.create(fake());
    st.write('meta', 1, { essence: 5 });
    st.write('run', 3, validRun());
    const obj = JSON.parse(Save.exportText(st));
    assert.strictEqual(Save.parseImport('x'.repeat(Save.MAX_IMPORT + 1)).code, 'E_SAVE_TOO_BIG');
    assert.strictEqual(Save.parseImport(5).code, 'E_SAVE_TOO_BIG');
    assert.strictEqual(Save.parseImport('{"__proto__":{"a":1}}').code, 'E_SAVE_BAD_KEY');
    assert.strictEqual(Save.parseImport('nope').code, 'E_SAVE_PARSE');
    assert.strictEqual(Save.parseImport(JSON.stringify(Object.assign({ extra: 1 }, obj))).code, 'E_SAVE_SCHEMA');
    assert.strictEqual(Save.parseImport(JSON.stringify(Object.assign({}, obj, { kind: 'nope' }))).code, 'E_SAVE_SCHEMA');
    assert.strictEqual(Save.parseImport(JSON.stringify(Object.assign({}, obj, { v: 2 }))).code, 'E_SAVE_SCHEMA');
    assert.strictEqual(Save.parseImport(JSON.stringify(Object.assign({}, obj, { meta: null }))).code, 'E_SAVE_SCHEMA');
    const badRun = JSON.parse(JSON.stringify(obj));
    badRun.run.sum = '00000000';
    assert.strictEqual(Save.parseImport(JSON.stringify(badRun)).code, 'E_SAVE_CHECKSUM');
  });

  test('migrateRun versions', () => {
    const v3 = validRun();
    assert.strictEqual(Save.migrateRun(4, v3).data, v3);
    const v2 = { v: 2, map: 'town', player: { x: 1, y: 1, angle: 0 }, doors: {}, people: {}, night: Night.serialize(Night.create()) };
    const m2 = Save.migrateRun(2, v2);
    assert.strictEqual(m2.ok, true);
    assert.strictEqual(m2.data.v, 4);
    assert.deepStrictEqual(m2.data.run, { seed: 1, boons: [], closedSafe: {}, pendingBoons: null, hunger: null });
    assert.deepStrictEqual(m2.data.night, v2.night);
    assert.strictEqual(v2.v, 2);
    const m1 = Save.migrateRun(1, Object.assign({}, v2, { v: 1 }));
    assert.strictEqual(m1.data.v, 4);
    assert.strictEqual('night' in m1.data, false);
    assert.deepStrictEqual(Save.migrateRun(99, v3), { ok: false, data: null, code: 'E_SAVE_VERSION' });
    assert.strictEqual(Save.migrateRun(0, v3).code, 'E_SAVE_SCHEMA');
    assert.strictEqual(Save.migrateRun(2, null).code, 'E_SAVE_SCHEMA');
    assert.strictEqual(Save.sanitizeRun(m2.data) !== null, true);
  });

  test('sanitizeRun keeps valid v3 exactly', () => {
    assert.deepStrictEqual(Save.sanitizeRun(validRun()), validRun());
    const noNight = validRun();
    delete noNight.night;
    assert.deepStrictEqual(Save.sanitizeRun(noNight), noNight);
    const pend = validRun();
    pend.run.pendingBoons = ['a', 'b', 'c'];
    assert.deepStrictEqual(Save.sanitizeRun(pend), pend);
    assert.notStrictEqual(Save.sanitizeRun(validRun()).player, validRun().player);
  });

  test('sanitizeRun drops unknown keys and rejects bad fields', () => {
    const d = validRun();
    d.evil = 1;
    assert.deepStrictEqual(Save.sanitizeRun(d), validRun());
    const bad = function (fn) { const x = validRun(); fn(x); assert.strictEqual(Save.sanitizeRun(x), null); };
    assert.strictEqual(Save.sanitizeRun(null), null);
    assert.strictEqual(Save.sanitizeRun([]), null);
    bad(function (x) { x.v = 3; });
    bad(function (x) { x.map = 5; });
    bad(function (x) { x.map = 'm'.repeat(33); });
    bad(function (x) { x.player = { x: NaN, y: 1, angle: 0 }; });
    bad(function (x) { x.player = { x: 1, y: 1 }; });
    bad(function (x) { x.player = 'p'; });
    bad(function (x) { x.doors = { town: [[1.5, 2]] }; });
    bad(function (x) { x.doors = { town: [[1, 2, 3]] }; });
    bad(function (x) { x.people = { town: 'a' }; });
    bad(function (x) { x.people = []; });
    bad(function (x) { x.run.seed = -1; });
    bad(function (x) { x.run.seed = 4294967296; });
    bad(function (x) { x.run.seed = 1.5; });
    bad(function (x) { delete x.run; });
    bad(function (x) { x.run.boons = [1]; });
    bad(function (x) { x.run.boons = ['x'.repeat(25)]; });
    bad(function (x) { x.run.pendingBoons = ['a', 'b', 'c', 'd']; });
    bad(function (x) { x.run.closedSafe = { town: [[1, 1]].concat(new Array(16).fill([2, 2])) }; });
  });

  test('sanitizeRun caps arrays', () => {
    const a = validRun();
    a.doors = { town: new Array(513).fill([1, 1]) };
    assert.strictEqual(Save.sanitizeRun(a), null);
    const b = validRun();
    b.doors = { town: new Array(512).fill([1, 1]) };
    assert.strictEqual(Save.sanitizeRun(b).doors.town.length, 512);
    const c = validRun();
    c.run.boons = new Array(21).fill('hush');
    assert.strictEqual(Save.sanitizeRun(c), null);
    const d = validRun();
    d.run.boons = new Array(20).fill('hush');
    assert.strictEqual(Save.sanitizeRun(d).run.boons.length, 20);
  });

  test('sanitizeRun strips proto-ish structure', () => {
    const x = validRun();
    const doors = JSON.parse('{"__proto__":[[1,1]],"town":[[1,2]]}');
    x.doors = doors;
    const people = JSON.parse('{"constructor":5,"town":7}');
    x.people = people;
    const out = Save.sanitizeRun(x);
    assert.ok(out);
    assert.deepStrictEqual(Object.keys(out.doors), ['town']);
    assert.deepStrictEqual(Object.keys(out.people), ['town']);
    assert.strictEqual(Object.getPrototypeOf(out.doors), Object.prototype);
    assert.strictEqual({}.p, undefined);
    const n = validRun();
    n.night = [1];
    assert.strictEqual(Save.sanitizeRun(n), null);
  });

  test('damaged night or hunger invalidates the whole run', () => {
    const a = validRun();
    a.night.blood = null;
    assert.strictEqual(Save.sanitizeRun(a), null);
    const b = validRun();
    b.night.night = 9999;
    assert.strictEqual(Save.sanitizeRun(b), null);
    const c = validRun();
    c.night = JSON.parse('{"v":1,"__proto__":{"p":1}}');
    assert.strictEqual(Save.sanitizeRun(c), null);
    const d = validRun();
    d.run.hunger = require('../js/hunger.js').serialize(require('../js/hunger.js').create());
    assert.ok(Save.sanitizeRun(d));
    d.run.hunger.fear = 9999;
    assert.strictEqual(Save.sanitizeRun(d), null);
  });

  test('validateRun reports without writing', () => {
    assert.deepStrictEqual(Save.validateRun(validRun()), { ok: true, code: '' });
    const a = validRun();
    a.night.blood = null;
    assert.strictEqual(Save.validateRun(a).ok, false);
    assert.strictEqual(Save.validateRun(null).ok, false);
    assert.strictEqual(Save.validateRun(Object.assign(validRun(), { v: 99 })).code, 'E_SAVE_VERSION');
    assert.deepStrictEqual(Save.validateRun({ v: 2, map: 'town', player: { x: 1, y: 1, angle: 0 }, doors: {}, people: {} }, 2), { ok: true, code: '' });
  });

  test('remove keepBak and restoreBak', () => {
    const mem = fake();
    const s = Save.create(mem);
    s.write('meta', 1, META);
    s.write('meta', 1, { v: 1, essence: 4 });
    s.remove('meta', { keepBak: true });
    assert.strictEqual(mem.getItem('vcs.meta'), null);
    assert.notStrictEqual(mem.getItem('vcs.meta.bak'), null);
    assert.strictEqual(s.restoreBak('meta'), true);
    assert.strictEqual(s.read('meta').data.essence, 3);
    s.remove('meta');
    assert.strictEqual(mem.getItem('vcs.meta.bak'), null);
    assert.strictEqual(s.restoreBak('meta'), false);
    assert.strictEqual(s.restoreBak('nope'), false);
  });

  test('tabLock / tabCheck two-tab guard', () => {
    const mem = fake();
    assert.deepStrictEqual(Save.tabCheck(mem, 'A', 1000), { other: false });
    assert.strictEqual(Save.tabLock(mem, 'A', 1000), true);
    assert.deepStrictEqual(Save.tabCheck(mem, 'A', 5000), { other: false });
    assert.strictEqual(Save.tabCheck(mem, 'B', 5000).other, true);
    assert.strictEqual(Save.tabCheck(mem, 'B', 12999).other, true);
    assert.strictEqual(Save.tabCheck(mem, 'B', 13000).other, false);
    mem.setItem('vcs.tab', '{bad');
    assert.strictEqual(Save.tabCheck(mem, 'B', 1).other, false);
    assert.strictEqual(Save.tabLock(null, 'A', 1), false);
    assert.strictEqual(Save.tabLock({ setItem() { throw new Error('x'); } }, 'A', 1), false);
    assert.strictEqual(Save.tabCheck({ getItem() { throw new Error('x'); } }, 'A', 1).other, false);
  });

});

describe('save-v4.test.js', () => {

  const test = require('node:test');
  const assert = require('node:assert');
  const Log = require('../js/log.js');
  if (Log && typeof Log.setConsole === 'function') Log.setConsole(false);
  const Save = require('../js/save.js');

  const H = () => ({ v: 1, fear: 3, over: 10, giftsTonight: 1, gifts: ['g_far'], essenceBonus: 2, nextBlood: 0 });
  function run() {
    return {
      v: 4, map: 'town', player: { x: 1, y: 2, angle: 0 }, doors: {}, people: {},
      run: { seed: 5, boons: [], closedSafe: {}, pendingBoons: null, hunger: H(), pendingGifts: ['g_far', 'g_fade', 'g_calm'] }
    };
  }
  function bad(fn) { const x = run(); fn(x); assert.strictEqual(Save.sanitizeRun(x), null); }

  test('RUN_SCHEMA is 4', () => assert.strictEqual(Save.RUN_SCHEMA, 4));

  test('v3 migrates to v4 with hunger null', () => {
    const v3 = { v: 3, map: 'town', player: { x: 1, y: 2, angle: 0 }, doors: {}, people: {},
      run: { seed: 5, boons: ['hush'], closedSafe: {}, pendingBoons: null } };
    const m = Save.migrateRun(3, v3);
    assert.strictEqual(m.ok, true);
    assert.strictEqual(m.data.v, 4);
    assert.strictEqual(m.data.run.hunger, null);
    assert.deepStrictEqual(m.data.run.boons, ['hush']);
    assert.strictEqual(v3.v, 3);
    assert.strictEqual('hunger' in v3.run, false);
    const s = Save.sanitizeRun(m.data);
    assert.ok(s);
    assert.strictEqual(s.run.pendingGifts, null);
    assert.strictEqual(Save.migrateRun(3, { v: 3 }).ok, false);
    assert.strictEqual(Save.migrateRun(5, run()).code, 'E_SAVE_VERSION');
    assert.strictEqual(Save.migrateRun(4, run()).ok, true);
  });

  test('v1/v2 chain to v4', () => {
    const v2 = { v: 2, map: 'town', player: { x: 1, y: 2, angle: 0 }, doors: {}, people: {} };
    const m = Save.migrateRun(2, v2);
    assert.strictEqual(m.data.v, 4);
    assert.strictEqual(m.data.run.hunger, null);
    assert.ok(Save.sanitizeRun(m.data));
    assert.strictEqual(Save.migrateRun(1, Object.assign({}, v2, { v: 1 })).data.v, 4);
  });

  test('sanitizeRun keeps hunger and pendingGifts, deep-cloned', () => {
    const s = Save.sanitizeRun(run());
    assert.deepStrictEqual(s, run());
    assert.notStrictEqual(s.run.hunger, run().hunger);
    const src = run();
    const c = Save.sanitizeRun(src);
    assert.notStrictEqual(c.run.hunger.gifts, src.run.hunger.gifts);
    const n = run(); n.run.hunger = null; n.run.pendingGifts = null;
    assert.deepStrictEqual(Save.sanitizeRun(n), n);
  });

  test('sanitizeRun rejects v3 and bad hunger', () => {
    bad(x => { x.v = 3; });
    bad(x => { x.run.hunger = 5; });
    bad(x => { x.run.hunger = []; });
    bad(x => { delete x.run.hunger.fear; });
    bad(x => { x.run.hunger.extra = 1; });
    bad(x => { x.run.hunger.fear = -1; });
    bad(x => { x.run.hunger.over = NaN; });
    bad(x => { x.run.hunger.nextBlood = '1'; });
    bad(x => { x.run.hunger.gifts = [1]; });
    bad(x => { x.run.hunger.gifts = new Array(21).fill('a'); });
    bad(x => { x.run.hunger.gifts = ['x'.repeat(25)]; });
  });

  test('sanitizeRun rejects bad pendingGifts', () => {
    bad(x => { x.run.pendingGifts = ['a', 'b', 'c', 'd']; });
    bad(x => { x.run.pendingGifts = [1]; });
    bad(x => { x.run.pendingGifts = 'a'; });
    bad(x => { x.run.pendingGifts = ['x'.repeat(25)]; });
  });

});

