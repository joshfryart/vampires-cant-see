'use strict';
// Merged test file: each source file's tests live in their own describe().
const { describe } = require('node:test');

describe('meta.test.js', () => {

  const test = require('node:test');
  const assert = require('node:assert');
  const Log = require('../js/log.js');
  if (Log && typeof Log.setConsole === 'function') Log.setConsole(false);
  const Meta = require('../js/meta.js');
  const D = require('../js/data/upgrades.js');

  const near = (a, b) => assert.ok(Math.abs(a - b) < 1e-9, a + ' vs ' + b);

  test('create', () => {
    const m = Meta.create();
    assert.strictEqual(Meta.SCHEMA, 1);
    assert.strictEqual(m.v, 1);
    assert.strictEqual(m.essence, 0);
    assert.strictEqual(Object.keys(m.upgrades).length, 9);
    D.upgrades.forEach((u) => assert.strictEqual(m.upgrades[u.id], 0));
    assert.deepStrictEqual(m.stats, { runs: 0, wins: 0, nightsSurvived: 0, peopleFed: 0, bestNights: 0, essenceEarned: 0 });
  });

  test('sanitize accepts, floors and clamps', () => {
    const s = Meta.sanitize({ v: 1, essence: 7.9, upgrades: { far_echo: 2.7, soft_step: 9 }, stats: { runs: 3.2 } });
    assert.strictEqual(s.essence, 7);
    assert.strictEqual(s.upgrades.far_echo, 2);
    assert.strictEqual(s.upgrades.soft_step, 3);
    assert.strictEqual(s.upgrades.long_night, 0);
    assert.strictEqual(s.stats.runs, 3);
    assert.strictEqual(Meta.sanitize({ v: 1, essence: 5e9 }).essence, 1e6);
    assert.strictEqual(Meta.sanitize({ v: 1, essence: 0, stats: { runs: 5e12 } }).stats.runs, 1e9);
  });

  test('sanitize drops unknown keys and ids', () => {
    const src = { v: 1, essence: 3, extra: 1, upgrades: { nope: 3, far_echo: 1 }, stats: { runs: 1, junk: 5 } };
    const s = Meta.sanitize(src);
    assert.notStrictEqual(s, src);
    assert.deepStrictEqual(Object.keys(s).sort(), ['essence', 'stats', 'upgrades', 'v']);
    assert.ok(!('nope' in s.upgrades));
    assert.ok(!('junk' in s.stats));
    assert.strictEqual(s.upgrades.far_echo, 1);
  });

  test('sanitize rejects bad input', () => {
    [null, undefined, 5, 'x', [], [1], new Date(), new Map(), () => 1].forEach((x) => assert.strictEqual(Meta.sanitize(x), null));
    assert.strictEqual(Meta.sanitize({ v: 2, essence: 1 }), null);
    assert.strictEqual(Meta.sanitize({ essence: 1 }), null);
    assert.strictEqual(Meta.sanitize({ v: 1 }), null);
    assert.strictEqual(Meta.sanitize({ v: 1, essence: NaN }), null);
    assert.strictEqual(Meta.sanitize({ v: 1, essence: Infinity }), null);
    assert.strictEqual(Meta.sanitize({ v: 1, essence: -1 }), null);
    assert.strictEqual(Meta.sanitize({ v: 1, essence: '5' }), null);
    assert.strictEqual(Meta.sanitize({ v: 1, essence: 1, upgrades: [] }), null);
    assert.strictEqual(Meta.sanitize({ v: 1, essence: 1, upgrades: { far_echo: -1 } }), null);
    assert.strictEqual(Meta.sanitize({ v: 1, essence: 1, upgrades: { far_echo: NaN } }), null);
    assert.strictEqual(Meta.sanitize({ v: 1, essence: 1, stats: { runs: -2 } }), null);
    assert.strictEqual(Meta.sanitize({ v: 1, essence: 1, stats: 'x' }), null);
  });

  test('sanitize ignores inherited props', () => {
    const o = Object.create({ v: 1, essence: 5 });
    assert.strictEqual(Meta.sanitize(o), null);
  });

  test('sanitize is safe against __proto__ payloads', () => {
    const a = JSON.parse('{"__proto__":{"essence":5}}');
    assert.strictEqual(Meta.sanitize(a), null);
    const b = JSON.parse('{"v":1,"essence":2,"__proto__":{"essence":99,"polluted":true},"upgrades":{"__proto__":{"far_echo":3}},"stats":{"__proto__":{"runs":9}}}');
    const s = Meta.sanitize(b);
    assert.ok(s);
    assert.strictEqual(s.essence, 2);
    assert.strictEqual(s.polluted, undefined);
    assert.strictEqual(Object.getPrototypeOf(s), Object.prototype);
    assert.strictEqual(s.upgrades.far_echo, 0);
    assert.strictEqual(s.stats.runs, 0);
    assert.strictEqual(({}).polluted, undefined);
    assert.strictEqual(({}).essence, undefined);
    assert.strictEqual(Object.prototype.hasOwnProperty.call(Object.prototype, 'polluted'), false);
  });

  test('migrate', () => {
    const d1 = { v: 1, essence: 1 };
    assert.deepStrictEqual(Meta.migrate(1, d1), { ok: true, data: d1, code: null });
    const r0 = Meta.migrate(0, { essence: 12, bought: ['far_echo', 'bogus', 'long_night', 5] });
    assert.ok(r0.ok);
    assert.strictEqual(r0.data.v, 1);
    assert.strictEqual(r0.data.essence, 12);
    assert.strictEqual(r0.data.upgrades.far_echo, 1);
    assert.strictEqual(r0.data.upgrades.long_night, 1);
    assert.strictEqual(r0.data.upgrades.hush, undefined);
    assert.strictEqual(r0.data.stats.runs, 0);
    assert.ok(Meta.sanitize(r0.data));
    const r2 = Meta.migrate(2, {});
    assert.strictEqual(r2.ok, false);
    assert.strictEqual(r2.code, 'E_SAVE_VERSION');
    assert.strictEqual(Meta.migrate(99, {}).code, 'E_SAVE_VERSION');
    ['x', null, undefined, -1, 0.5, NaN, {}].forEach((v) => {
      const r = Meta.migrate(v, {});
      assert.strictEqual(r.ok, false);
      assert.strictEqual(r.code, 'E_SAVE_SCHEMA');
    });
    assert.strictEqual(Meta.migrate(0, null).code, 'E_SAVE_SCHEMA');
    assert.strictEqual(Meta.migrate(0, { essence: 'a', bought: [] }).code, 'E_SAVE_SCHEMA');
    assert.strictEqual(Meta.migrate(0, { essence: 1, bought: 'x' }).code, 'E_SAVE_SCHEMA');
  });

  test('tierOf and costOf', () => {
    const m = Meta.create();
    assert.strictEqual(Meta.tierOf(m, 'far_echo'), 0);
    assert.strictEqual(Meta.tierOf(m, 'nope'), 0);
    assert.strictEqual(Meta.tierOf(null, 'far_echo'), 0);
    assert.strictEqual(Meta.costOf(m, 'far_echo'), 5);
    m.upgrades.far_echo = 1;
    assert.strictEqual(Meta.costOf(m, 'far_echo'), 12);
    m.upgrades.far_echo = 2;
    assert.strictEqual(Meta.costOf(m, 'far_echo'), 25);
    m.upgrades.far_echo = 3;
    assert.strictEqual(Meta.costOf(m, 'far_echo'), null);
    assert.strictEqual(Meta.costOf(m, 'nope'), null);
  });

  test('buy', () => {
    const m = Meta.create();
    m.essence = 100;
    let r = Meta.buy(m, 'far_echo');
    assert.deepStrictEqual([r.ok, r.cost], [true, 5]);
    assert.strictEqual(m.essence, 95);
    assert.strictEqual(m.upgrades.far_echo, 1);
    assert.strictEqual(Meta.buy(m, 'far_echo').cost, 12);
    assert.strictEqual(Meta.buy(m, 'far_echo').cost, 25);
    assert.strictEqual(m.essence, 100 - 42);
    r = Meta.buy(m, 'far_echo');
    assert.deepStrictEqual([r.ok, r.code], [false, 'E_META_MAX']);
    assert.strictEqual(m.upgrades.far_echo, 3);
    assert.strictEqual(m.essence, 58);
    r = Meta.buy(m, 'nope');
    assert.deepStrictEqual([r.ok, r.code], [false, 'E_META_UNKNOWN']);
    const p = Meta.create();
    p.essence = 4;
    r = Meta.buy(p, 'soft_step');
    assert.deepStrictEqual([r.ok, r.code], [false, 'E_META_POOR']);
    assert.strictEqual(p.essence, 4);
    assert.strictEqual(p.upgrades.soft_step, 0);
    assert.strictEqual(Meta.buy(null, 'soft_step').ok, false);
  });

  test('essenceFor', () => {
    assert.strictEqual(Meta.essenceFor({ nights: 2, fed: 3, won: false }), 11);
    assert.strictEqual(Meta.essenceFor({ nights: 5, fed: 10, won: true }), 45);
    assert.strictEqual(Meta.essenceFor(null), 0);
    assert.strictEqual(Meta.essenceFor({ nights: NaN, fed: -3, won: false }), 0);
    assert.strictEqual(Meta.essenceFor({ nights: 'a', fed: 2.9 }), 2);
  });

  test('recordRun', () => {
    const m = Meta.create();
    assert.strictEqual(Meta.recordRun(m, { nights: 2, fed: 3, won: false }), 11);
    assert.strictEqual(Meta.recordRun(m, { nights: 5, fed: 10, won: true }), 45);
    assert.strictEqual(Meta.recordRun(m, { nights: 1, fed: 0, won: false }), 4);
    assert.strictEqual(m.essence, 60);
    assert.deepStrictEqual(m.stats, { runs: 3, wins: 1, nightsSurvived: 8, peopleFed: 13, bestNights: 5, essenceEarned: 60 });
    m.essence = 999999;
    Meta.recordRun(m, { nights: 5, fed: 10, won: true });
    assert.strictEqual(m.essence, 1e6);
    assert.strictEqual(Meta.recordRun(null, {}), 0);
    assert.ok(Meta.sanitize(m));
  });

  test('effects', () => {
    const m = Meta.create();
    assert.deepStrictEqual(Meta.effects(m, []), D.EFFECT_DEFAULTS);
    assert.deepStrictEqual(Meta.effects(null), D.EFFECT_DEFAULTS);
    m.upgrades.far_echo = 2;
    assert.strictEqual(Meta.effects(m, []).sonarRange, 1.3);
    m.upgrades.far_echo = 3;
    near(Meta.effects(m, ['bats_ear']).sonarRange, 1.45 * 1.1);
    m.upgrades.full_veins = 2;
    m.upgrades.warm_sense = 3;
    const fx = Meta.effects(m, ['warm_hint']);
    assert.strictEqual(fx.startBlood, 20);
    assert.strictEqual(fx.warmRadius, 9);
  });

  test('effects clamps, ignores bloodNow and unknown', () => {
    const m = Meta.create();
    m.upgrades.quick_call = 3;
    const many = ['quick_ping', 'quick_ping', 'quick_ping', 'quick_ping', 'quick_ping', 'quick_ping'];
    assert.strictEqual(Meta.effects(m, many).sonarCooldown, 0.5);
    m.upgrades.warm_sense = 3;
    assert.strictEqual(Meta.effects(m, ['warm_hint', 'warm_hint', 'warm_hint', 'warm_hint']).warmRadius, 10);
    const base = Meta.effects(Meta.create(), []);
    const fx = Meta.effects(Meta.create(), ['full_belly', 'full_belly', 'nope', 42, null, '__proto__']);
    assert.deepStrictEqual(fx, base);
    assert.ok(!('bloodNow' in fx));
    assert.deepStrictEqual(Meta.effects(Meta.create(), 'bats_ear'), base);
  });

  test('rollBoons', () => {
    const ids = D.boons.map((b) => b.id);
    const a = Meta.rollBoons(123, []);
    assert.deepStrictEqual(a, Meta.rollBoons(123, []));
    assert.strictEqual(a.length, 3);
    assert.strictEqual(new Set(a).size, 3);
    a.forEach((id) => assert.ok(ids.includes(id)));
    let differs = false;
    for (let s = 1; s < 20; s++) if (Meta.rollBoons(s, []).join() !== a.join()) differs = true;
    assert.ok(differs);
    const taken = ['bats_ear', 'hush', 'moonlit'];
    for (let s = 0; s < 50; s++) {
      Meta.rollBoons(s, taken).forEach((id) => assert.ok(!taken.includes(id)));
    }
    let sawBelly = false;
    for (let s = 0; s < 100; s++) if (Meta.rollBoons(s, ['full_belly', 'full_belly']).includes('full_belly')) sawBelly = true;
    assert.ok(sawBelly);
    const nonRepeat = D.boons.filter((b) => !b.repeat).map((b) => b.id);
    assert.strictEqual(nonRepeat.length, 8);
    assert.deepStrictEqual(Meta.rollBoons(5, nonRepeat), ['full_belly']);
    const seven = nonRepeat.slice(0, 7);
    const r = Meta.rollBoons(5, seven);
    assert.strictEqual(r.length, 2);
    assert.deepStrictEqual(Meta.rollBoons(1, 'junk').length, 3);
  });

  test('lookups', () => {
    assert.strictEqual(Meta.boonById('hush').name, 'Hush');
    assert.strictEqual(Meta.boonById('x'), null);
    assert.strictEqual(Meta.upgradeById('far_echo').name, 'Far Echo');
    assert.strictEqual(Meta.upgradeById('hush'), null);
  });

});

describe('meta-extra.test.js', () => {

  const test = require('node:test');
  const assert = require('node:assert');
  const Log = require('../js/log.js');
  if (Log && typeof Log.setConsole === 'function') Log.setConsole(false);
  require('../js/data/upgrades.js');
  const Meta = require('../js/meta.js');

  test('effects extra applies after boons and clamps', () => {
    const m = Meta.create();
    const fx = Meta.effects(m, ['bats_ear'], [{ effect: 'sonarRange', op: 'mul', value: 1.05 }]);
    assert.ok(Math.abs(fx.sonarRange - 1.1 * 1.05) < 1e-9);
    const big = Meta.effects(m, [], [{ effect: 'sonarRange', op: 'mul', value: 100 }]);
    assert.strictEqual(big.sonarRange, 2.5);
    const add = Meta.effects(m, [], [{ effect: 'warmRadius', op: 'add', value: 3 }]);
    assert.strictEqual(add.warmRadius, 3);
  });

  test('effects extra ignores bad entries', () => {
    const m = Meta.create();
    const base = Meta.effects(m, []);
    const bad = [null, 5, 'x', {}, { effect: 'nope', op: 'mul', value: 2 }, { effect: 'drain', op: 'mul', value: NaN },
      { effect: 'drain', op: 'pow', value: 2 }, { effect: 'bloodNow', op: 'add', value: 9 }];
    assert.deepStrictEqual(Meta.effects(m, [], bad), base);
    assert.deepStrictEqual(Meta.effects(m, [], 'junk'), base);
    assert.deepStrictEqual(Meta.effects(m, [], undefined), base);
    assert.strictEqual('bloodNow' in Meta.effects(m, [], bad), false);
  });

  test('recordRun bonus', () => {
    const m = Meta.create();
    const e = Meta.recordRun(m, { nights: 2, fed: 3, won: false, bonus: 4 });
    assert.strictEqual(e, 15);
    assert.strictEqual(m.essence, 15);
    assert.strictEqual(m.stats.essenceEarned, 15);
  });

  test('recordRun bonus capped and sanitised', () => {
    const m = Meta.create();
    assert.strictEqual(Meta.recordRun(m, { nights: 0, fed: 0, bonus: 99999 }), 1000);
    assert.strictEqual(Meta.recordRun(m, { nights: 0, fed: 0, bonus: -5 }), 0);
    assert.strictEqual(Meta.recordRun(m, { nights: 0, fed: 0, bonus: NaN }), 0);
    assert.strictEqual(Meta.recordRun(m, { nights: 1, fed: 0, bonus: 2.9 }), 6);
    assert.strictEqual(Meta.recordRun(m, { nights: 1, fed: 0 }), 4);
  });

});

describe('upgrades.test.js', () => {

  const test = require('node:test');
  const assert = require('node:assert');
  const D = require('../js/data/upgrades.js');

  const ICONS = ['ear', 'hourglass', 'bat', 'vial', 'drop', 'fang', 'paw', 'moon', 'heart'];

  test('counts and unique ids', () => {
    assert.strictEqual(D.upgrades.length, 9);
    assert.strictEqual(D.boons.length, 9);
    assert.strictEqual(new Set(D.upgrades.map((u) => u.id)).size, 9);
    assert.strictEqual(new Set(D.boons.map((b) => b.id)).size, 9);
  });

  test('icons, effects, limits', () => {
    const keys = Object.keys(D.EFFECT_DEFAULTS);
    assert.strictEqual(keys.length, 9);
    keys.forEach((k) => {
      assert.ok(Array.isArray(D.EFFECT_LIMITS[k]) && D.EFFECT_LIMITS[k].length === 2, k);
      assert.ok(D.EFFECT_LIMITS[k][0] <= D.EFFECT_LIMITS[k][1]);
    });
    D.upgrades.forEach((u) => {
      assert.ok(ICONS.includes(u.icon));
      assert.ok(keys.includes(u.effect));
      assert.ok(u.op === 'mul' || u.op === 'add');
      assert.deepStrictEqual(u.costs, [5, 12, 25]);
      assert.strictEqual(u.tiers.length, 3);
      assert.strictEqual(u.desc.length, 3);
    });
    D.boons.forEach((b) => {
      assert.ok(ICONS.includes(b.icon));
      assert.ok(keys.includes(b.effect) || b.effect === 'bloodNow');
      assert.strictEqual(typeof b.value, 'number');
      assert.strictEqual(typeof b.repeat, 'boolean');
      assert.ok(b.desc.length > 0);
    });
  });

  test('exact table values', () => {
    const far = D.upgrades.find((u) => u.id === 'far_echo');
    assert.deepStrictEqual(far.tiers, [1.15, 1.3, 1.45]);
    assert.strictEqual(far.name, 'Far Echo');
    const warm = D.upgrades.find((u) => u.id === 'warm_sense');
    assert.deepStrictEqual([warm.effect, warm.op, warm.tiers], ['warmRadius', 'add', [3, 5, 7]]);
    const belly = D.boons.find((b) => b.id === 'full_belly');
    assert.deepStrictEqual([belly.effect, belly.value, belly.repeat], ['bloodNow', 25, true]);
    assert.strictEqual(D.boons.filter((b) => b.repeat).length, 1);
    assert.strictEqual(D.boons.find((b) => b.id === 'bats_ear').name, "Bat's Ear");
  });

  test('deep frozen', () => {
    assert.ok(Object.isFrozen(D));
    assert.ok(Object.isFrozen(D.upgrades));
    assert.ok(Object.isFrozen(D.upgrades[0]));
    assert.ok(Object.isFrozen(D.upgrades[0].tiers));
    assert.ok(Object.isFrozen(D.boons[0]));
    assert.ok(Object.isFrozen(D.EFFECT_LIMITS.drain));
  });

});

