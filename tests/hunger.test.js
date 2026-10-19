'use strict';
const test = require('node:test');
const assert = require('node:assert');
const Log = require('../js/log.js');
if (Log && typeof Log.setConsole === 'function') Log.setConsole(false);
const H = require('../js/hunger.js');
const D = require('../js/data/hunger.js');

const near = (a, b) => assert.ok(Math.abs(a - b) < 1e-9, a + ' vs ' + b);

test('data tables and freeze', () => {
  assert.strictEqual(D.RAMP, 0.12);
  assert.deepStrictEqual(D.GIFT_COSTS, [40, 60]);
  assert.strictEqual(D.GIFTS_PER_NIGHT, 2);
  assert.strictEqual(D.GIFT_ESSENCE, 2);
  assert.strictEqual(D.FEAR_MAX, 15);
  assert.deepStrictEqual(D.FEAR, { grab: 1, sleep: -5 });
  assert.deepStrictEqual(D.FEAR_STARTLE, [0.04, 0.6]);
  assert.deepStrictEqual(D.FEAR_FLEE, [0.015, 0.2]);
  assert.deepStrictEqual(D.powers.map((p) => [p.id, p.unlock, p.cost, p.cooldown, p.fear, p.icon]),
    [['shriek', 1, 15, 6, 2, 'shriek'], ['mist', 2, 10, 3, 1, 'mist'], ['still', 3, 10, 12, 1, 'still']]);
  assert.deepStrictEqual(D.powers.map((p) => p.key), [['KeyQ'], ['ShiftLeft', 'ShiftRight'], ['KeyF']]);
  assert.strictEqual(D.gifts.length, 8);
  assert.deepStrictEqual(D.gifts.map((g) => g.id),
    ['g_far', 'g_fade', 'g_quick', 'g_thirst', 'g_draw', 'g_quiet', 'g_calm', 'g_reserve']);
  assert.deepStrictEqual(D.gifts.map((g) => g.icon), ['ear', 'hourglass', 'bat', 'drop', 'fang', 'paw', 'eye', 'vial']);
  assert.deepStrictEqual(D.gifts.map((g) => g.value), [1.05, 1.05, 0.95, 0.95, 1.08, 0.95, -2, 10]);
  assert.ok(Object.isFrozen(D) && Object.isFrozen(D.powers[0].key) && Object.isFrozen(D.gifts[0]));
  assert.strictEqual(H.create().v, 1);
});

test('overflow open/cost/addOverflow', () => {
  const s = H.create();
  assert.strictEqual(H.cost(s), 40);
  assert.ok(H.isOpen(s));
  let r = H.addOverflow(s, 30);
  assert.deepStrictEqual(r, { taken: 30, ready: false });
  near(H.over01(s), 0.75);
  r = H.addOverflow(s, 30);
  assert.deepStrictEqual(r, { taken: 10, ready: true });
  assert.strictEqual(H.over01(s), 1);
  assert.deepStrictEqual(H.addOverflow(s, 5), { taken: 0, ready: true });
  assert.deepStrictEqual(H.addOverflow(s, -5), { taken: 0, ready: true });
  assert.deepStrictEqual(H.addOverflow(s, NaN), { taken: 0, ready: true });
  H.takeGift(s, 'g_far');
  assert.strictEqual(s.over, 0);
  assert.strictEqual(H.cost(s), 60);
  assert.deepStrictEqual(H.addOverflow(s, 100), { taken: 60, ready: true });
  H.takeGift(s, 'g_far');
  assert.strictEqual(H.cost(s), null);
  assert.strictEqual(H.isOpen(s), false);
  assert.strictEqual(H.over01(s), 0);
  assert.deepStrictEqual(H.addOverflow(s, 10), { taken: 0, ready: false });
});

test('rollGifts distinct, deterministic, varied', () => {
  const s = H.create();
  const ids = D.gifts.map((g) => g.id);
  const seen = new Set();
  for (let seed = 0; seed < 50; seed++) {
    const a = H.rollGifts(s, seed);
    assert.strictEqual(a.length, 3);
    assert.strictEqual(new Set(a).size, 3);
    a.forEach((x) => { assert.ok(ids.includes(x)); seen.add(x); });
    assert.deepStrictEqual(a, H.rollGifts(s, seed));
  }
  assert.ok(seen.size >= 6);
  const before = H.rollGifts(s, 7);
  s.gifts.push('g_far');
  assert.strictEqual(H.rollGifts(s, 7).length, 3);
  assert.ok(before.length === 3);
  assert.strictEqual(H.rollGifts(null, 'x').length, 3);
});

test('takeGift effects, instants, unknown', () => {
  const s = H.create();
  s.fear = 5; s.over = 40;
  let r = H.takeGift(s, 'g_calm');
  assert.deepStrictEqual(r, { ok: true, instant: { fear: -2 } });
  assert.strictEqual(s.fear, 3);
  assert.strictEqual(s.over, 0);
  assert.strictEqual(s.giftsTonight, 1);
  assert.strictEqual(s.essenceBonus, 2);
  r = H.takeGift(s, 'g_reserve');
  assert.deepStrictEqual(r, { ok: true, instant: { nextBlood: 10 } });
  assert.strictEqual(s.nextBlood, 10);
  assert.strictEqual(s.essenceBonus, 4);
  r = H.takeGift(s, 'g_draw');
  assert.deepStrictEqual(r, { ok: true, instant: {} });
  assert.deepStrictEqual(s.gifts, ['g_calm', 'g_reserve', 'g_draw']);
  const snap = JSON.stringify(s);
  assert.strictEqual(H.takeGift(s, 'nope').ok, false);
  assert.strictEqual(H.takeGift(s, 5).ok, false);
  assert.strictEqual(H.takeGift(null, 'g_far').ok, false);
  assert.strictEqual(JSON.stringify(s), snap);
  s.fear = 1;
  H.takeGift(s, 'g_calm');
  assert.strictEqual(s.fear, 0);
});

test('giftMods only effect gifts', () => {
  const s = H.create();
  ['g_far', 'g_calm', 'g_draw', 'g_reserve', 'g_far'].forEach((g) => H.takeGift(s, g));
  assert.deepStrictEqual(H.giftMods(s), [
    { effect: 'sonarRange', op: 'mul', value: 1.05 },
    { effect: 'drinkRate', op: 'mul', value: 1.08 },
    { effect: 'sonarRange', op: 'mul', value: 1.05 }
  ]);
  assert.deepStrictEqual(H.giftMods(null), []);
});

test('fear: onGrab once per person, bounds, mods', () => {
  const s = H.create();
  assert.strictEqual(H.onGrab(s, 'p1'), true);
  assert.strictEqual(H.onGrab(s, 'p1'), false);
  assert.strictEqual(H.onGrab(s, 3), true);
  assert.strictEqual(s.fear, 2);
  assert.strictEqual(H.onGrab(s, null), false);
  assert.strictEqual(H.addFear(s, 100), 15);
  assert.strictEqual(H.addFear(s, -100), 0);
  assert.strictEqual(H.addFear(s, NaN), 0);
  let m = H.fearMods(H.create());
  assert.deepStrictEqual(m, { startleMul: 1, fleeMul: 1, calmMul: 1 });
  s.fear = 5;
  m = H.fearMods(s);
  near(m.startleMul, 1.2); near(m.fleeMul, 1.075); near(m.calmMul, 1.2);
  s.fear = 15;
  m = H.fearMods(s);
  near(m.startleMul, 1.6); near(m.fleeMul, 1.2); near(m.calmMul, 1.6);
  assert.deepStrictEqual(H.fearMods(null), { startleMul: 1, fleeMul: 1, calmMul: 1 });
});

test('powerState / cdLeft01 / use', () => {
  const s = H.create();
  assert.strictEqual(H.powerState(s, 'shriek', 1, 100), 'ready');
  assert.strictEqual(H.powerState(s, 'shriek', 1, 14), 'poor');
  assert.strictEqual(H.powerState(s, 'mist', 1, 100), 'locked');
  assert.strictEqual(H.powerState(s, 'still', 2, 100), 'locked');
  assert.strictEqual(H.powerState(s, 'still', 3, 100), 'ready');
  assert.strictEqual(H.powerState(s, 'zzz', 3, 100), 'locked');
  assert.deepStrictEqual(H.use(s, 'mist', 1, 100), { ok: false, code: 'E_LOCKED', cost: 10 });
  assert.deepStrictEqual(H.use(s, 'nope', 1, 100), { ok: false, code: 'E_UNKNOWN', cost: null });
  assert.deepStrictEqual(H.use(s, 'shriek', 1, 10), { ok: false, code: 'E_POOR', cost: 15 });
  assert.strictEqual(s.fear, 0);
  assert.deepStrictEqual(H.use(s, 'shriek', 1, 50), { ok: true, code: null, cost: 15 });
  assert.strictEqual(s.fear, 2);
  assert.strictEqual(s.cd.shriek, 6);
  assert.strictEqual(H.cdLeft01(s, 'shriek'), 1);
  assert.strictEqual(H.powerState(s, 'shriek', 1, 50), 'cooldown');
  assert.strictEqual(H.use(s, 'shriek', 1, 50).code, 'E_COOLDOWN');
  assert.strictEqual(s.fear, 2);
  assert.strictEqual(H.cdLeft01(s, 'nope'), 0);
  assert.strictEqual(H.use(s, 'still', 3, 20).ok, true);
  assert.strictEqual(s.stillLeft, 5);
  assert.strictEqual(H.isStill(s), true);
  assert.strictEqual(s.cd.still, 12);
  assert.strictEqual(H.use(s, 'mist', 2, 10).ok, true);
  assert.strictEqual(s.fear, 4);
  assert.strictEqual(H.use(null, 'mist', 2, 10).ok, false);
});

test('tick clamps dt and expires still', () => {
  const s = H.create();
  H.use(s, 'shriek', 1, 50);
  H.use(s, 'still', 3, 50);
  H.tick(s, 5);
  near(s.cd.shriek, 5.9); near(s.stillLeft, 4.9);
  H.tick(s, -1);
  near(s.cd.shriek, 5.9);
  H.tick(s, NaN);
  near(s.cd.shriek, 5.9);
  for (let i = 0; i < 100; i++) H.tick(s, 0.1);
  assert.strictEqual(s.cd.shriek, 0);
  assert.strictEqual(s.stillLeft, 0);
  assert.strictEqual(H.isStill(s), false);
  assert.strictEqual(H.powerState(s, 'shriek', 1, 50), 'ready');
  H.tick(null, 0.1);
});

test('onSleep', () => {
  const s = H.create();
  s.fear = 7; s.over = 30; s.giftsTonight = 1; s.nextBlood = 10; s.grabbed = ['a'];
  assert.strictEqual(H.onSleep(s), 10);
  assert.strictEqual(s.fear, 2);
  assert.strictEqual(s.over, 0);
  assert.strictEqual(s.giftsTonight, 0);
  assert.deepStrictEqual(s.grabbed, []);
  assert.strictEqual(s.nextBlood, 0);
  assert.strictEqual(H.onSleep(s), 0);
  assert.strictEqual(s.fear, 0);
  assert.strictEqual(H.onSleep(null), 0);
  H.onGrab(s, 'a');
  assert.strictEqual(s.fear, 1);
});

test('serialize/restore roundtrip', () => {
  const s = H.create();
  H.takeGift(s, 'g_far'); H.takeGift(s, 'g_reserve');
  s.fear = 7;
  H.use(s, 'shriek', 1, 50);
  const o = H.serialize(s);
  assert.deepStrictEqual(Object.keys(o).sort(), ['essenceBonus', 'fear', 'gifts', 'giftsTonight', 'nextBlood', 'over', 'v']);
  assert.notStrictEqual(o.gifts, s.gifts);
  const r = H.restore(JSON.parse(JSON.stringify(o)));
  assert.strictEqual(r.fear, 9);
  assert.deepStrictEqual(r.gifts, ['g_far', 'g_reserve']);
  assert.strictEqual(r.essenceBonus, 4);
  assert.strictEqual(r.nextBlood, 10);
  assert.deepStrictEqual(r.cd, { shriek: 0, mist: 0, still: 0 });
  assert.strictEqual(r.stillLeft, 0);
  assert.deepStrictEqual(r.grabbed, []);
  assert.deepStrictEqual(H.serialize(r), o);
  assert.strictEqual(H.serialize(null), null);
});

test('restore rejects bad input', () => {
  const good = H.serialize(H.create());
  assert.ok(H.restore(good));
  const bad = [
    null, 5, 'x', [], undefined,
    Object.assign({}, good, { v: 2 }),
    Object.assign({}, good, { extra: 1 }),
    Object.assign({}, good, { fear: 16 }),
    Object.assign({}, good, { fear: -1 }),
    Object.assign({}, good, { fear: 1.5 }),
    Object.assign({}, good, { over: NaN }),
    Object.assign({}, good, { giftsTonight: 3 }),
    Object.assign({}, good, { essenceBonus: 'a' }),
    Object.assign({}, good, { nextBlood: Infinity }),
    Object.assign({}, good, { gifts: ['nope'] }),
    Object.assign({}, good, { gifts: [1] }),
    Object.assign({}, good, { gifts: 'g_far' }),
    Object.assign({}, good, { gifts: new Array(21).fill('g_far') })
  ];
  bad.forEach((b) => assert.strictEqual(H.restore(b), null, JSON.stringify(b)));
  const missing = Object.assign({}, good); delete missing.over;
  assert.strictEqual(H.restore(missing), null);
  const ok20 = H.restore(Object.assign({}, good, { gifts: new Array(20).fill('g_far') }));
  assert.strictEqual(ok20.gifts.length, 20);
  const capped = H.restore(Object.assign({}, good, { over: 999 }));
  assert.strictEqual(capped.over, 40);
  const closed = H.restore(Object.assign({}, good, { over: 30, giftsTonight: 2 }));
  assert.strictEqual(closed.over, 0);
});

test('never throws on garbage', () => {
  const junk = [null, undefined, 0, 'x', {}, [], NaN, { gifts: 5 }];
  junk.forEach((j) => {
    assert.doesNotThrow(() => {
      H.addOverflow(j, 5); H.isOpen(j); H.cost(j); H.over01(j); H.rollGifts(j, 1); H.takeGift(j, 'g_far');
      H.giftMods(j); H.onGrab(j, 1); H.addFear(j, 1); H.fearMods(j); H.powerState(j, 'shriek', 1, 1);
      H.cdLeft01(j, 'shriek'); H.use(j, 'shriek', 1, 1); H.tick(j, 0.1); H.isStill(j); H.onSleep(j);
      H.serialize(j); H.restore(j);
    });
  });
});
