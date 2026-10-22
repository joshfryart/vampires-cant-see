'use strict';
// v0.20 character creator (tools/character-creator-core.js): field table, clamping, presets, randomizing, pose echoes,
// view clamping, storage and JSON export / import. The last tests render creator looks through the real renderer
// (Render.drawSolo with a fake canvas) in every pose and Effects level to prove the figure code never throws on them.
const test = require('node:test');
const assert = require('node:assert');

require('../js/log.js');
for (const m of ['ripple', 'struggle', 'flags', 'data/vessels', 'data/archetypes', 'data/voices', 'forge', 'figure']) require('../js/' + m + '.js');
const Render = require('../js/render.js');
const C = require('../tools/character-creator-core.js');
const VCS = globalThis.VCS;
const Forge = VCS.Forge;
const AD = VCS.ArchetypeData;
VCS.Log.setConsole(false);
try { VCS.Flags.register('vis.vessels', false, 'Circulatory pulse on villagers'); } catch (e) { /* registered */ }

function memStore() {
  const m = new Map();
  return { getItem: (k) => (m.has(k) ? m.get(k) : null), setItem: (k, v) => { m.set(k, String(v)); }, removeItem: (k) => m.delete(k), _m: m };
}
function assertValidLook(l, tag) {
  assert.deepStrictEqual(Object.keys(l).sort(), C.LOOK_KEYS.slice().sort(), tag + ' keys');
  Object.keys(AD.LOOK_RANGES).forEach((k) => {
    assert.ok(typeof l[k] === 'number' && isFinite(l[k]), tag + ' ' + k + ' number');
    assert.ok(l[k] >= AD.LOOK_RANGES[k][0] && l[k] <= AD.LOOK_RANGES[k][1], tag + ' ' + k + ' in range: ' + l[k]);
  });
  Object.keys(AD.LOOK_ENUMS).forEach((k) => assert.ok(AD.LOOK_ENUMS[k].indexOf(l[k]) >= 0, tag + ' ' + k + ' enum: ' + l[k]));
  assert.strictEqual(typeof l.beard, 'boolean');
  assert.strictEqual(typeof l.coat, 'boolean');
  assert.strictEqual(l.v, 1);
  // The game's own validator accepts it unchanged (partial mode applies no derive rules).
  const r = Forge.validate('look', l, { partial: true });
  assert.ok(r.ok && r.errors.length === 0, tag + ' forge validate: ' + r.errors.join(','));
}

test('field table covers every Forge look field (acc is edited as hat, prop and the scarf toggle)', () => {
  const keys = C.fields().map((f) => f.key);
  Forge.LOOK_FIELDS.forEach((f) => { if (f.key !== 'acc') assert.ok(keys.indexOf(f.key) >= 0, f.key); });
  assert.ok(keys.indexOf('scarf') >= 0);
  C.fields().forEach((f) => {
    if (f.type === 'num') assert.deepStrictEqual([f.min, f.max], AD.LOOK_RANGES[f.key].slice(), f.key);
    if (f.type === 'enum') assert.deepStrictEqual(f.values, AD.LOOK_ENUMS[f.key].slice(), f.key);
    assert.ok(f.group && f.label, f.key);
  });
});

test('sanitize turns any input into a complete, in-range look', () => {
  const junk = [undefined, null, 5, 'x', [], [1, 2], {}, { height: NaN, build: Infinity, stride: -Infinity, nose: '1.3', stoop: '9', body: 'blob', head: 7, hat: null, beard: 'yes', coat: 1, hem: -4, skin: 99 },
    JSON.parse('{"__proto__": {"polluted": 1}, "constructor": 1, "height": 0.7, "outfit": "robe", "archetype": "Bad Id"}'), { look: {} }];
  junk.forEach((j, i) => assertValidLook(C.sanitize(j).look, 'junk ' + i));
  assert.strictEqual({}.polluted, undefined);
  const r = C.sanitize({ height: 9, nose: '1.3', body: 'blob', archetype: 'Bad Id', outfit: 'robe' });
  assert.strictEqual(r.look.height, 1.2);
  assert.strictEqual(r.look.nose, 1.3);
  assert.strictEqual(r.look.body, 'bean');
  assert.strictEqual(r.look.outfit, 'robe');
  assert.strictEqual(r.look.archetype, 'patron');
  assert.ok(['height', 'nose', 'body', 'archetype'].every((k) => r.fixed.indexOf(k) >= 0), r.fixed.join(','));
  // A bad field falls back to the base look, not the defaults.
  assert.strictEqual(C.sanitize({ body: 'blob' }, { body: 'pear' }).look.body, 'pear');
});

test('presets match the game Forge for every archetype and seed', () => {
  const ids = C.archetypes().map((a) => a.id);
  assert.deepStrictEqual(ids, Forge.list());
  ids.forEach((id) => [0, 1, 7, 65535].forEach((seed) => {
    const p = C.preset(id, seed);
    assertValidLook(p, id + '#' + seed);
    const g = Forge.generate({ archetype: id, seed: seed }, { stateSeed: 0, index: 0, accOffset: 0 }).person.look;
    Object.keys(g).forEach((k) => {
      if (typeof g[k] === 'number') assert.ok(Math.abs(g[k] - p[k]) < 0.001, id + ' ' + k);
      else assert.strictEqual(p[k], g[k], id + ' ' + k);
    });
  }));
  assert.strictEqual(C.preset('child', 3).archetype, 'child');
  assert.ok(C.preset('child', 3).height <= 0.66);
  assertValidLook(C.preset('nope', 1), 'unknown archetype');
  assertValidLook(C.preset(null, NaN), 'null');
  assert.strictEqual(C.cleanSeed(-5), 0);
  assert.strictEqual(C.cleanSeed(1e9), 65535);
  assert.strictEqual(C.cleanSeed('12.7'), 12);
});

test('setField edits one field, clamps it, and keeps hat, prop and scarf independent', () => {
  let l = C.preset('patron', 1);
  l = C.setField(l, 'height', 5);
  assert.strictEqual(l.height, 1.2);
  l = C.setField(l, 'hat', 'tophat');
  l = C.setField(l, 'prop', 'lantern');
  l = C.setField(l, 'scarf', true);
  assert.strictEqual(l.acc, 'scarf');
  assert.strictEqual(l.hat, 'tophat');
  assert.strictEqual(l.prop, 'lantern');
  assert.strictEqual(C.getField(l, 'scarf'), true);
  l = C.setField(l, 'hat', 'bonnet');
  assert.strictEqual(l.acc, 'scarf', 'scarf survives a hat change');
  l = C.setField(l, 'scarf', false);
  assert.strictEqual(l.acc, 'bonnet');
  const before = JSON.stringify(l);
  assert.strictEqual(JSON.stringify(C.setField(l, 'body', 'blob')), before, 'bad enum ignored');
  assert.strictEqual(JSON.stringify(C.setField(l, '__proto__', 1)), before);
  assert.strictEqual(JSON.stringify(C.setField(l, 'nonsense', 1)), before);
  assert.strictEqual(C.setField(l, 'beard', 'true').beard, true);
  assertValidLook(C.setField(null, 'stoop', 'x'), 'null look');
  assert.strictEqual(C.hairHidden({ hat: 'hood', roleHat: 'none' }), true);
  assert.strictEqual(C.hairHidden({ hat: 'cap', roleHat: 'none' }), false);
});

test('randomize is seedable, valid, and honours locks', () => {
  const base = C.preset('priest', 2);
  const a = C.randomize(base, { mode: 'wild', rng: C.mulberry32(42) });
  const b = C.randomize(base, { mode: 'wild', rng: C.mulberry32(42) });
  assert.deepStrictEqual(a, b);
  for (let i = 0; i < 300; i++) assertValidLook(C.randomize(base, { mode: 'wild', rng: C.mulberry32(i) }).look, 'wild ' + i);
  const locked = C.randomize(base, { mode: 'wild', rng: C.mulberry32(7), locks: { outfit: true, roleHat: true, height: true, scarf: true } });
  assert.strictEqual(locked.look.outfit, base.outfit);
  assert.strictEqual(locked.look.roleHat, base.roleHat);
  assert.strictEqual(locked.look.height, base.height);
  assert.strictEqual(locked.look.acc === 'scarf', base.acc === 'scarf');
  const arch = C.randomize(base, { mode: 'archetype', rng: C.mulberry32(3) });
  assert.deepStrictEqual(arch.look, C.preset('priest', arch.seed));
  assert.ok(arch.seed >= 0 && arch.seed <= 65535);
  assertValidLook(C.randomize('junk', { rng: 'nope' }).look, 'junk randomize');
});

test('poseEcho covers every pose with finite fields; held carries a lock; reduced motion freezes', () => {
  const look = C.preset('patron', 1);
  assert.deepStrictEqual(C.POSES.map((p) => p.id), ['idle', 'wary', 'chat', 'walk', 'flee', 'startle', 'cower', 'dazed', 'seated', 'fed', 'held']);
  C.POSES.forEach((p) => {
    const r = C.poseEcho(p.id, look, { t: 3.7, yaw: 0.5, dist: 2.2 });
    ['x', 'y', 'angle', 'phase', 'modeAge'].forEach((k) => assert.ok(isFinite(r.echo[k]), p.id + ' ' + k));
    assert.strictEqual(r.echo.look, look);
    assert.strictEqual(!!r.lock, p.id === 'held', p.id);
  });
  assert.strictEqual(C.poseEcho('seated', look, {}).echo.sit, true);
  assert.strictEqual(C.poseEcho('flee', look, {}).echo.mode, 'flee');
  assert.strictEqual(C.poseEcho('flee', look, {}).vmode, 'flee');
  assert.strictEqual(C.poseEcho('bogus', look, {}).echo.mode, 'path');
  assert.ok(Math.abs(C.poseEcho('idle', look, { yaw: 0 }).echo.angle - Math.PI) < 1e-9, 'yaw 0 faces the camera');
  const w1 = C.poseEcho('walk', look, { t: 1, reduced: true }).echo.phase;
  const w2 = C.poseEcho('walk', look, { t: 2, reduced: true }).echo.phase;
  assert.strictEqual(w1, w2);
  const h = C.poseEcho('held', look, { struggle: 7, restrain: true });
  assert.strictEqual(h.lock.k, 1);
  assert.strictEqual(h.lock.rs, 1);
});

test('sanitizeView clamps every view setting and wraps the turn', () => {
  const v = C.sanitizeView({ pose: 'nope', fx: 9, quality: -1, zoom: 2.6, dist: 99, yaw: Math.PI * 3, speed: 'x', rim: 'yes', vessels: true, gameScale: 0 });
  assert.strictEqual(v.pose, 'idle');
  assert.strictEqual(v.fx, 2);
  assert.strictEqual(v.quality, 1);
  assert.strictEqual(v.zoom, 3);
  assert.strictEqual(v.dist, 5);
  assert.ok(Math.abs(Math.abs(v.yaw) - Math.PI) < 1e-9);
  assert.strictEqual(v.speed, 1);
  assert.strictEqual(v.rim, true);
  assert.strictEqual(v.vessels, true);
  assert.strictEqual(v.gameScale, 1);
  assert.ok(Math.abs(C.sanitizeView({ yaw: -0.5 }).yaw + 0.5) < 1e-9);
  assert.deepStrictEqual(C.sanitizeView(null), C.sanitizeView({}));
});

test('export and import round-trip one character, a bundle, an array and a bare look', () => {
  const a = C.character('Old  Tom\u0007 <b>', C.preset('elder', 4), { archetype: 'elder', seed: 4, saved: 1700000000000 });
  assert.strictEqual(a.name, 'Old Tom b');
  const one = C.importJSON(C.exportJSON(a));
  assert.ok(one.ok);
  assert.deepStrictEqual(one.list[0], a);
  assert.strictEqual(JSON.parse(C.exportJSON(a)).format, 'vcs-character');
  const b = C.character('Kid', C.preset('child', 2), { archetype: 'child', seed: 2, saved: 5 });
  const many = C.importJSON(C.exportJSON([a, b]));
  assert.strictEqual(JSON.parse(C.exportJSON([a, b])).format, 'vcs-characters');
  assert.deepStrictEqual(many.list, [a, b]);
  assert.deepStrictEqual(C.importJSON(JSON.stringify([a, b])).list, [a, b]);
  const bare = C.importJSON(JSON.stringify(C.preset('guard', 1)));
  assert.ok(bare.ok);
  assert.strictEqual(bare.list[0].look.roleHat, 'kettle');
  const mixed = C.importJSON(JSON.stringify({ list: [a, 5, null, { foo: 1 }, { look: { height: 99 } }] }));
  assert.strictEqual(mixed.list.length, 2);
  assert.strictEqual(mixed.skipped, 3);
  assert.strictEqual(mixed.list[1].look.height, 1.2);
  assert.strictEqual(C.importJSON('{bad').code, 'E_CC_PARSE');
  assert.strictEqual(C.importJSON(42).code, 'E_CC_TYPE');
  assert.strictEqual(C.importJSON('7').code, 'E_CC_TYPE');
  assert.strictEqual(C.importJSON('{"foo":1}').code, 'E_CC_EMPTY');
  assert.strictEqual(C.importJSON('"' + 'x'.repeat(C.MAX_TEXT) + '"').code, 'E_CC_LIMIT');
  const polluted = C.importJSON('{"name":"P","look":{"__proto__":{"evil":1},"height":0.9}}');
  assert.ok(polluted.ok);
  assert.strictEqual({}.evil, undefined);
  assert.strictEqual(polluted.list[0].look.evil, undefined);
});

test('saved list: upsert by name, remove, find, free names, and the 64 cap', () => {
  let list = [];
  list = C.upsert(list, C.character('Ann', C.preset('mother', 1), {}));
  list = C.upsert(list, C.character('Bo', C.preset('farmer', 1), {}));
  list = C.upsert(list, C.character('ann', C.preset('child', 1), {}));
  assert.deepStrictEqual(list.map((c) => c.name), ['ann', 'Bo']);
  assert.strictEqual(C.find(list, 'ANN').look.archetype, 'child');
  assert.strictEqual(C.freeName(list, 'Bo'), 'Bo 2');
  assert.strictEqual(C.freeName(list, 'Cy'), 'Cy');
  list = C.remove(list, 'bo');
  assert.deepStrictEqual(list.map((c) => c.name), ['ann']);
  for (let i = 0; i < 80; i++) list = C.upsert(list, C.character('N' + i, C.DEFAULTS, {}));
  assert.strictEqual(list.length, C.MAX_SAVED);
  assert.strictEqual(list[0].name, 'N79');
  assert.deepStrictEqual(C.upsert(list, 'junk'), list);
});

test('storage: save, load, draft, and failing storage never throws', () => {
  const s = memStore();
  assert.deepStrictEqual(C.loadStore(s), { ok: true, code: 'OK', list: [] });
  const list = [C.character('Ann', C.preset('mother', 1), { archetype: 'mother', seed: 1, saved: 9 })];
  assert.ok(C.saveStore(s, list).ok);
  assert.deepStrictEqual(C.loadStore(s).list, list);
  s.setItem(C.STORE_KEY, '{garbage');
  const bad = C.loadStore(s);
  assert.strictEqual(bad.ok, false);
  assert.deepStrictEqual(bad.list, []);
  const boom = { getItem() { throw new Error('denied'); }, setItem() { throw new Error('quota'); } };
  assert.strictEqual(C.loadStore(boom).ok, false);
  assert.strictEqual(C.saveStore(boom, list).code, 'E_CC_STORAGE');
  assert.strictEqual(C.saveStore(null, list).code, 'E_CC_TYPE');
  assert.strictEqual(C.saveDraft(boom, { look: {} }), false);
  assert.strictEqual(C.loadDraft(boom), null);
  assert.ok(C.saveDraft(s, { look: C.preset('guard', 2), archetype: 'guard', seed: 2, name: 'G', view: { pose: 'flee', fx: 1, yaw: 1 } }));
  const d = C.loadDraft(s);
  assert.strictEqual(d.archetype, 'guard');
  assert.strictEqual(d.view.pose, 'flee');
  assert.strictEqual(d.view.fx, 1);
  assert.deepStrictEqual(d.look, C.preset('guard', 2));
  s.setItem(C.DRAFT_KEY, '{"v":2}');
  assert.strictEqual(C.loadDraft(s), null);
});

test('toSpec gives a Forge spawn spec the game accepts', () => {
  let l = C.setField(C.preset('merchant', 5), 'hat', 'cap');
  l = C.setField(l, 'scarf', true);
  const spec = C.toSpec(C.character('M', l, { archetype: 'merchant', seed: 5 }));
  const v = Forge.validate('spec', spec);
  assert.ok(v.ok, v.errors.join(','));
  const g = Forge.generate(spec, { stateSeed: 0, index: 0, accOffset: 0 }).person.look;
  ['hat', 'prop', 'acc', 'outfit', 'extra', 'body', 'head', 'height'].forEach((k) => assert.strictEqual(g[k], l[k], k));
  assert.strictEqual(C.toSpec(C.character('X', l, { archetype: 'gone_custom' })).archetype, 'patron');
  assert.strictEqual(C.toSpec(5), null);
});

// ---------------------------------------------------------------- real renderer: creator looks never break the figure
function fakeCtx(canvas) {
  const state = { globalAlpha: 1, fillStyle: '#000', strokeStyle: '#000', lineWidth: 1 };
  return new Proxy({ canvas }, {
    get(t, p) {
      if (p in t) return t[p];
      if (p in state) return state[p];
      return function () {
        if (p === 'createRadialGradient' || p === 'createLinearGradient') return { addColorStop() {} };
        if (p === 'createPattern') return {};
        if (p === 'createImageData') return { data: new Uint8ClampedArray(128 * 128 * 4) };
        return undefined;
      };
    },
    set(t, p, v) { state[p] = v; return true; }
  });
}
function fakeCanvas(w, h) {
  const c = { width: w, height: h };
  c.ownerDocument = { createElement() { return fakeCanvas(w, h); } };
  c.getContext = function () { return c._ctx || (c._ctx = fakeCtx(c)); };
  return c;
}

test('every pose x Effects level draws random creator looks through Render.drawSolo without errors', () => {
  const R = Render.create(fakeCanvas(640, 360), { effects: 2 });
  R.reduced = false;
  const errs = () => VCS.Log.entries().filter((e) => e && e.level === 'ERROR').length;
  const before = errs();
  const looks = [];
  for (let i = 0; i < 24; i++) looks.push(C.randomize(C.preset('patron', i), { mode: 'wild', rng: C.mulberry32(1000 + i) }).look);
  looks.push(C.sanitize({ height: 0.5, build: 1.4, outfit: 'robe', hem: 1, roleHat: 'biretta', extra: 'shovel', hat: 'hood', acc: 'scarf' }).look);
  looks.push(C.sanitize({ height: 1.2, build: 0.7, stoop: 0.4, shoulder: 0.8, outfit: 'mail', roleHat: 'kettle', extra: 'bow', prop: 'umbrella' }).look);
  let drawn = 0;
  looks.forEach((look, li) => {
    C.POSES.forEach((p) => {
      [0, 1, 2].forEach((fx) => {
        [0, -1.2, 2.6].forEach((yaw) => {
          const pe = C.poseEcho(p.id, look, { t: 1.7 + li, yaw: yaw, dist: 2.2, struggle: (li % 5) / 4 });
          const ok = Render.drawSolo(R, pe.echo, { fx: fx, quality: 3, t: 1.7 + li, age: -1, lights: [{ x: 1.8, y: -0.9, radius: 1.2 }], lock: pe.lock });
          assert.strictEqual(ok, true, p.id + ' fx' + fx + ' look ' + li);
          if (fx > 0) assert.strictEqual(R.figVol, 1, 'volumetric path at fx ' + fx);
          drawn++;
        });
      });
    });
  });
  assert.strictEqual(errs(), before, 'renderer logged errors');
  assert.strictEqual(drawn, looks.length * C.POSES.length * 9);
});
