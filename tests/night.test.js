'use strict';
// Merged test file: each source file's tests live in their own describe().
const { describe } = require('node:test');

describe('night.test.js', () => {

  const test = require('node:test');
  const assert = require('node:assert');
  const Log = require('../js/log.js');
  if (Log && typeof Log.setConsole === 'function') Log.setConsole(false);
  const Night = require('../js/night.js');

  const IN = { outdoor: false };
  const OUT = { outdoor: true };

  function run(st, seconds, ctx) {
    const ev = [];
    const steps = Math.round(seconds / 0.05);
    for (let i = 0; i < steps; i++) ev.push.apply(ev, Night.update(st, 0.05, ctx || IN));
    return ev;
  }

  test('create defaults and bad options', () => {
    const st = Night.create();
    assert.strictEqual(st.night, 1);
    assert.strictEqual(st.nights, 5);
    assert.strictEqual(st.nightSec, 480);
    assert.strictEqual(st.blood, 60);
    assert.strictEqual(st.bloodMax, 100);
    assert.strictEqual(st.feedGain, 40);
    assert.strictEqual(st.status, 'night');
    assert.deepStrictEqual(st.fired, { chime: false, washout: false, dawn: false });
    const bad = Night.create({ nightSec: -1, nights: 2.5, bloodMax: NaN, bloodStart: 'x', feedGain: Infinity });
    assert.strictEqual(bad.nightSec, 480);
    assert.strictEqual(bad.nights, 5);
    assert.strictEqual(bad.bloodMax, 100);
    assert.strictEqual(bad.blood, 60);
    assert.strictEqual(bad.feedGain, 40);
    assert.strictEqual(Night.create(null).nights, 5);
    assert.strictEqual(Night.create({ bloodStart: 500 }).blood, 100);
    assert.strictEqual(Night.create({ nights: 3 }).nights, 3);
    assert.ok(Object.isFrozen(Night.DEFAULTS));
  });

  test('clock text at 0, 1, 540, 600', () => {
    const st = Night.create();
    assert.strictEqual(Night.clock(st).text, '20:00');
    st.min = 1;
    assert.strictEqual(Night.clock(st).text, '20:01');
    st.min = 540;
    const c = Night.clock(st);
    assert.strictEqual(c.text, '05:00');
    assert.strictEqual(c.hour, 5);
    assert.strictEqual(c.minute, 0);
    st.min = 600;
    assert.strictEqual(Night.clock(st).text, '06:00');
    assert.strictEqual(Night.clock(st).frac, 1);
    st.min = 240;
    assert.strictEqual(Night.clock(st).text, '00:00');
    assert.strictEqual(Night.clock(st).frac, 0.4);
    assert.strictEqual(Night.clock(null).text, '20:00');
  });

  test('update advances time and drains blood', () => {
    const st = Night.create({ nightSec: 100, bloodStart: 100 });
    run(st, 50);
    assert.ok(Math.abs(st.min - 300) < 1e-6);
    assert.ok(Math.abs(st.blood - 50) < 1e-6);
  });

  test('full night drains bloodMax and floors at 0', () => {
    const st = Night.create({ nightSec: 10, bloodStart: 100 });
    run(st, 5);
    assert.ok(Math.abs(st.blood - 50) < 1e-6);
    run(st, 10);
    assert.strictEqual(st.blood, 0);
    assert.ok(st.blood >= 0);
    const s2 = Night.create({ nightSec: 10, bloodStart: 60 });
    run(s2, 20);
    assert.strictEqual(s2.blood, 0);
  });

  test('dt clamps to 0..0.1 and bad dt is ignored', () => {
    const st = Night.create({ nightSec: 60 });
    Night.update(st, 5, IN);
    assert.ok(Math.abs(st.min - 0.1 * 10) < 1e-9);
    const m = st.min;
    Night.update(st, -1, IN);
    Night.update(st, NaN, IN);
    Night.update(st, 'a', IN);
    Night.update(st, undefined, undefined);
    assert.strictEqual(st.min, m);
  });

  test('events fire once, in order; dawn sets day', () => {
    const st = Night.create({ nightSec: 60 });
    const ev = run(st, 70);
    assert.deepStrictEqual(ev, ['chime', 'washout', 'dawn']);
    assert.strictEqual(st.status, 'day');
    assert.strictEqual(st.min, 600);
    assert.strictEqual(Night.isDay(st), true);
    assert.deepStrictEqual(run(st, 5), []);
    assert.strictEqual(Night.clock(st).text, '06:00');
  });

  test('events can fire together in one call when skipping', () => {
    const st = Night.create();
    st.min = 599.99;
    const ev = Night.update(st, 0.1, IN);
    assert.deepStrictEqual(ev, ['chime', 'washout', 'dawn']);
  });

  test('dawn while outdoor: dawn then lost (sun)', () => {
    const st = Night.create({ nightSec: 60 });
    st.min = 599.99;
    const ev = Night.update(st, 0.1, OUT);
    assert.deepStrictEqual(ev, ['chime', 'washout', 'dawn', 'lost']);
    assert.strictEqual(st.status, 'lost');
    assert.strictEqual(st.reason, 'sun');
    assert.deepStrictEqual(Night.update(st, 0.1, OUT), []);
  });

  test('indoor day then stepping outdoors is lost', () => {
    const st = Night.create({ nightSec: 60 });
    run(st, 70, IN);
    assert.strictEqual(st.status, 'day');
    assert.deepStrictEqual(Night.update(st, 0.05, IN), []);
    assert.strictEqual(st.status, 'day');
    const ev = Night.update(st, 0.05, OUT);
    assert.deepStrictEqual(ev, ['lost']);
    assert.strictEqual(st.status, 'lost');
    assert.strictEqual(st.reason, 'sun');
  });

  test('outdoor before dawn is fine; outdoor must be exactly true', () => {
    const st = Night.create({ nightSec: 60 });
    run(st, 30, OUT);
    assert.strictEqual(st.status, 'night');
    st.min = 600;
    st.status = 'day';
    Night.update(st, 0.05, { outdoor: 'yes' });
    assert.strictEqual(st.status, 'day');
  });

  test('update ignored when won or lost, and for bad state', () => {
    const st = Night.create();
    st.status = 'won';
    const m = st.min;
    assert.deepStrictEqual(Night.update(st, 0.1, IN), []);
    assert.strictEqual(st.min, m);
    assert.deepStrictEqual(Night.update(null, 0.1, IN), []);
    assert.deepStrictEqual(Night.update(undefined), []);
    assert.deepStrictEqual(Night.update(42, 1, IN), []);
  });

  test('feed adds, clamps, counts', () => {
    const st = Night.create();
    assert.strictEqual(Night.feed(st), 40);
    assert.strictEqual(st.blood, 100);
    assert.strictEqual(st.fedCount, 1);
    assert.strictEqual(Night.feed(st), 0);
    assert.strictEqual(st.blood, 100);
    assert.strictEqual(st.fedCount, 2);
    st.blood = 80;
    assert.strictEqual(Night.feed(st), 20);
    st.status = 'lost';
    assert.strictEqual(Night.feed(st), 0);
    assert.strictEqual(st.fedCount, 3);
    assert.strictEqual(Night.feed(null), 0);
  });

  test('feed works while day', () => {
    const st = Night.create();
    st.status = 'day';
    st.min = 600;
    assert.strictEqual(Night.feed(st), 40);
  });

  test('sleep next x4 then won', () => {
    const st = Night.create();
    st.blood = 33;
    for (let n = 2; n <= 5; n++) {
      st.min = 400;
      st.fired = { chime: true, washout: true, dawn: true };
      assert.strictEqual(Night.sleep(st), 'next');
      assert.strictEqual(st.night, n);
      assert.strictEqual(st.min, 0);
      assert.strictEqual(st.status, 'night');
      assert.deepStrictEqual(st.fired, { chime: false, washout: false, dawn: false });
      assert.strictEqual(st.blood, 33);
    }
    assert.strictEqual(Night.sleep(st), 'won');
    assert.strictEqual(st.status, 'won');
    assert.strictEqual(st.night, 5);
    assert.strictEqual(Night.sleep(st), 'none');
  });

  test('sleep from day state moves to next night', () => {
    const st = Night.create({ nightSec: 60 });
    run(st, 70);
    assert.strictEqual(Night.sleep(st), 'next');
    assert.strictEqual(st.status, 'night');
    assert.strictEqual(st.night, 2);
  });

  test('sleep invalid cases', () => {
    const st = Night.create();
    st.status = 'lost';
    assert.strictEqual(Night.sleep(st), 'none');
    assert.strictEqual(Night.sleep(null), 'none');
    assert.strictEqual(Night.sleep({}), 'none');
  });

  test('weakness values', () => {
    const st = Night.create();
    st.blood = 100;
    assert.strictEqual(Night.weakness(st), 0);
    st.blood = 25;
    assert.strictEqual(Night.weakness(st), 0);
    st.blood = 12.5;
    assert.ok(Math.abs(Night.weakness(st) - 0.5) < 1e-9);
    st.blood = 0;
    assert.strictEqual(Night.weakness(st), 1);
    assert.strictEqual(Night.weakness(null), 0);
  });

  test('washK and dawnK values', () => {
    const st = Night.create();
    st.min = 569;
    assert.strictEqual(Night.washK(st), 0);
    st.min = 570;
    assert.strictEqual(Night.washK(st), 0);
    st.min = 585;
    assert.ok(Math.abs(Night.washK(st) - 0.5) < 1e-9);
    st.min = 600;
    assert.strictEqual(Night.washK(st), 1);
    st.min = 540;
    assert.strictEqual(Night.dawnK(st), 0);
    st.min = 570;
    assert.ok(Math.abs(Night.dawnK(st) - 0.5) < 1e-9);
    st.min = 600;
    assert.strictEqual(Night.dawnK(st), 1);
    st.min = 0;
    assert.strictEqual(Night.dawnK(st), 0);
    assert.strictEqual(Night.washK(null), 0);
    assert.strictEqual(Night.dawnK(undefined), 0);
  });

  test('skipTo sets time and resets flags above it', () => {
    const st = Night.create();
    assert.strictEqual(Night.skipTo(st, 20, 0), true);
    assert.strictEqual(st.min, 0);
    assert.strictEqual(Night.skipTo(st, 23, 30), true);
    assert.strictEqual(st.min, 210);
    assert.strictEqual(Night.skipTo(st, 0, 0), true);
    assert.strictEqual(st.min, 240);
    assert.strictEqual(Night.skipTo(st, 4, 59), true);
    assert.strictEqual(st.min, 539);
    assert.strictEqual(Night.skipTo(st, 5, 59), true);
    assert.strictEqual(st.min, 599);
    assert.strictEqual(Night.skipTo(st, 6, 0), true);
    assert.strictEqual(st.min, 600);
    assert.strictEqual(Night.clock(st).text, '06:00');
  });

  test('skipTo rejects times outside the night', () => {
    const st = Night.create();
    st.min = 100;
    for (const [h, m] of [[6, 1], [12, 0], [19, 59], [24, 0], [-1, 0], [5, 60], [5, -1], [5.5, 0], [NaN, 0], ['5', '0'], [undefined, undefined]]) {
      assert.strictEqual(Night.skipTo(st, h, m), false, h + ':' + m);
    }
    assert.strictEqual(st.min, 100);
    assert.strictEqual(Night.skipTo(null, 5, 0), false);
    st.status = 'won';
    assert.strictEqual(Night.skipTo(st, 5, 0), false);
  });

  test('skipTo resets fired flags and drives events afterwards', () => {
    const st = Night.create({ nightSec: 60 });
    run(st, 70);
    assert.strictEqual(st.status, 'day');
    assert.strictEqual(Night.skipTo(st, 4, 59), true);
    assert.strictEqual(st.status, 'night');
    assert.deepStrictEqual(st.fired, { chime: false, washout: false, dawn: false });
    const ev = run(st, 3);
    assert.deepStrictEqual(ev.slice(0, 1), ['chime']);
    const st2 = Night.create();
    Night.skipTo(st2, 5, 59);
    assert.deepStrictEqual(Night.update(st2, 0.1, IN), ['chime', 'washout']);
  });

  test('serialize -> restore round trip', () => {
    const st = Night.create();
    st.night = 3;
    st.min = 321.5;
    st.blood = 42.25;
    st.fedCount = 7;
    st.fired.chime = true;
    const o = Night.serialize(st);
    assert.strictEqual(o.v, 1);
    assert.deepStrictEqual(Object.keys(o).sort(), ['blood', 'fedCount', 'fired', 'min', 'night', 'reason', 'status', 'v']);
    const json = JSON.parse(JSON.stringify(o));
    const r = Night.restore(json);
    assert.ok(r);
    assert.deepStrictEqual(Night.serialize(r), o);
    assert.strictEqual(r.nights, 5);
    assert.strictEqual(r.nightSec, 480);
    // serialize returns a copy
    o.fired.chime = false;
    assert.strictEqual(st.fired.chime, true);
    assert.strictEqual(Night.serialize(null), null);
  });

  test('round trip for lost/won/day statuses and opts', () => {
    for (const status of ['night', 'day', 'won', 'lost']) {
      const st = Night.create({ nightSec: 120, nights: 3 });
      st.status = status;
      st.min = status === 'day' ? 600 : 100;
      st.reason = status === 'lost' ? 'sun' : '';
      const r = Night.restore(Night.serialize(st), { nightSec: 120, nights: 3 });
      assert.ok(r, status);
      assert.strictEqual(r.status, status);
      assert.strictEqual(r.nightSec, 120);
      assert.strictEqual(r.nights, 3);
    }
  });

  function good() {
    return { v: 1, night: 2, min: 100, blood: 50, status: 'night', reason: '', fired: { chime: false, washout: false, dawn: false }, fedCount: 1 };
  }

  test('restore accepts a good object', () => {
    assert.ok(Night.restore(good()));
  });

  test('restore rejects non-objects', () => {
    for (const x of [null, undefined, 0, 1, 'str', true, [], [1], () => 1, NaN]) {
      assert.strictEqual(Night.restore(x), null);
    }
  });

  test('restore rejects wrong types, ranges, NaN, oversize', () => {
    const cases = [
      ['v', 2], ['v', '1'], ['v', undefined],
      ['night', 0], ['night', 6], ['night', 1.5], ['night', '2'], ['night', NaN], ['night', Infinity], ['night', 1e12],
      ['min', -1], ['min', 600.1], ['min', NaN], ['min', '5'], ['min', Infinity], ['min', 1e300],
      ['blood', -0.1], ['blood', 100.1], ['blood', NaN], ['blood', '50'], ['blood', 1e9], ['blood', -Infinity],
      ['status', 'sleeping'], ['status', ''], ['status', 5], ['status', 'NIGHT'], ['status', null], ['status', 'constructor'],
      ['reason', 5], ['reason', 'x'.repeat(500)], ['reason', null],
      ['fedCount', -1], ['fedCount', 1.2], ['fedCount', NaN], ['fedCount', 1e12], ['fedCount', '3'],
      ['fired', null], ['fired', []], ['fired', 'x'], ['fired', 5]
    ];
    for (const [k, v] of cases) {
      const o = good();
      o[k] = v;
      assert.strictEqual(Night.restore(o), null, k + '=' + String(v).slice(0, 10));
    }
  });

  test('restore rejects missing keys', () => {
    for (const k of ['v', 'night', 'min', 'blood', 'status', 'reason', 'fired', 'fedCount']) {
      const o = good();
      delete o[k];
      assert.strictEqual(Night.restore(o), null, k);
    }
  });

  test('restore rejects bad fired flags and extra fired keys', () => {
    let o = good();
    o.fired.chime = 1;
    assert.strictEqual(Night.restore(o), null);
    o = good();
    delete o.fired.dawn;
    assert.strictEqual(Night.restore(o), null);
    o = good();
    o.fired.extra = true;
    assert.strictEqual(Night.restore(o), null);
    o = good();
    o.fired = JSON.parse('{"chime":false,"washout":false,"dawn":false,"__proto__":{"x":1}}');
    assert.strictEqual(Night.restore(o), null);
  });

  test('restore rejects unknown keys and hostile keys', () => {
    let o = good();
    o.extra = 1;
    assert.strictEqual(Night.restore(o), null);
    for (const bad of ['{"__proto__":{"status":"won"}}', '{"constructor":{"prototype":{"x":1}}}', '{"prototype":1}']) {
      assert.strictEqual(Night.restore(JSON.parse(bad)), null, bad);
    }
    const hostile = JSON.parse('{"v":1,"night":1,"min":0,"blood":10,"status":"night","reason":"","fedCount":0,' +
      '"fired":{"chime":false,"washout":false,"dawn":false},"__proto__":{"polluted":true}}');
    assert.strictEqual(Night.restore(hostile), null);
    assert.strictEqual(({}).polluted, undefined);
    o = good();
    o.constructor = 'x';
    assert.strictEqual(Night.restore(o), null);
  });

  test('restore rejects class instances / odd prototypes', () => {
    class Foo { constructor() { Object.assign(this, good()); } }
    assert.strictEqual(Night.restore(new Foo()), null);
    const withProto = Object.create({ inherited: 1 });
    Object.assign(withProto, good());
    assert.strictEqual(Night.restore(withProto), null);
  });

  test('restore rejects day status before dawn', () => {
    const o = good();
    o.status = 'day';
    o.min = 100;
    assert.strictEqual(Night.restore(o), null);
  });

  test('restore respects opts for night/blood limits', () => {
    const o = good();
    o.night = 4;
    assert.strictEqual(Night.restore(o, { nights: 3 }), null);
    assert.ok(Night.restore(o, { nights: 5 }));
    o.blood = 90;
    assert.strictEqual(Night.restore(o, { bloodMax: 80 }), null);
  });

  test('restore result is independent and safe to use', () => {
    const o = good();
    const r = Night.restore(o);
    r.fired.chime = true;
    assert.strictEqual(o.fired.chime, false);
    assert.strictEqual(Night.feed(r), 40);
    assert.deepStrictEqual(Night.update(r, 0.1, IN), []);
  });

  test('nothing throws on garbage input', () => {
    const garbage = [null, undefined, 0, NaN, 'x', {}, [], () => 1, Symbol('s')];
    for (const g of garbage) {
      assert.doesNotThrow(() => {
        Night.update(g, g, g);
        Night.feed(g);
        Night.sleep(g);
        Night.clock(g);
        Night.weakness(g);
        Night.washK(g);
        Night.dawnK(g);
        Night.isDay(g);
        Night.skipTo(g, g, g);
        Night.serialize(g);
        Night.restore(g, g);
        Night.create(g);
      });
    }
    const trap = {};
    Object.defineProperty(trap, 'status', { get() { throw new Error('boom'); } });
    assert.doesNotThrow(() => { Night.update(trap, 0.1, IN); Night.feed(trap); Night.sleep(trap); Night.restore(trap); });
  });

  test('deterministic', () => {
    const a = Night.create({ nightSec: 90 });
    const b = Night.create({ nightSec: 90 });
    const ea = run(a, 100);
    const eb = run(b, 100);
    assert.deepStrictEqual(ea, eb);
    assert.deepStrictEqual(Night.serialize(a), Night.serialize(b));
  });

  test('addBlood returns actual gain and clamps at bloodMax', () => {
    const st = Night.create({ bloodStart: 90 });
    assert.strictEqual(Night.addBlood(st, 4), 4);
    assert.strictEqual(st.blood, 94);
    assert.strictEqual(Night.addBlood(st, 20), 6);
    assert.strictEqual(st.blood, 100);
    assert.strictEqual(Night.addBlood(st, 5), 0);
    assert.strictEqual(st.fedCount, 0);
  });

  test('addBlood is 0 for bad amounts or inactive state', () => {
    const st = Night.create({ bloodStart: 50 });
    for (const bad of [0, -3, NaN, Infinity, '5', null, undefined]) assert.strictEqual(Night.addBlood(st, bad), 0);
    assert.strictEqual(st.blood, 50);
    assert.strictEqual(Night.addBlood(null, 5), 0);
    assert.strictEqual(Night.addBlood({}, 5), 0);
    st.status = 'lost';
    assert.strictEqual(Night.addBlood(st, 5), 0);
    st.status = 'day';
    assert.strictEqual(Night.addBlood(st, 5), 5);
  });

});

describe('night-drain.test.js', () => {

  const test = require('node:test');
  const assert = require('node:assert');
  const Log = require('../js/log.js');
  if (Log && typeof Log.setConsole === 'function') Log.setConsole(false);
  const Night = require('../js/night.js');

  function run(st, sec) { for (let i = 0; i < Math.round(sec / 0.05); i++) Night.update(st, 0.05, { outdoor: false }); }

  test('drainMul 0.5 drains half', () => {
    const a = Night.create(); const b = Night.create({ drainMul: 0.5 });
    run(a, 20); run(b, 20);
    assert.ok(Math.abs((60 - b.blood) * 2 - (60 - a.blood)) < 1e-6);
    assert.ok(a.blood < 60);
  });

  test('bad drainMul falls back to 1', () => {
    for (const v of [0, -1, NaN, 'x', Infinity]) assert.strictEqual(Night.create({ drainMul: v }).drainMul, 1);
    assert.strictEqual(Night.create().drainMul, 1);
  });

  test('not serialized; restore honours opts', () => {
    const st = Night.create({ drainMul: 0.7 });
    const s = Night.serialize(st);
    assert.ok(!('drainMul' in s));
    assert.strictEqual(Night.restore(s, { drainMul: 0.7 }).drainMul, 0.7);
    assert.strictEqual(Night.restore(s).drainMul, 1);
  });

});

describe('night-ramp.test.js', () => {

  const test = require('node:test');
  const assert = require('node:assert');
  const Log = require('../js/log.js');
  if (Log && typeof Log.setConsole === 'function') Log.setConsole(false);
  const Night = require('../js/night.js');

  function drainOf(st) { const b = st.blood; Night.update(st, 0.1); return b - st.blood; }

  test('ramp defaults to 0: no change per night', () => {
    const a = Night.create({ nightSec: 100 });
    const base = drainOf(a);
    a.night = 4;
    assert.ok(Math.abs(drainOf(a) - base) < 1e-9);
  });

  test('ramp scales drain by night', () => {
    const s = Night.create({ nightSec: 100, ramp: 0.1 });
    const d1 = drainOf(s);
    s.night = 5; s.blood = 60;
    const d5 = drainOf(s);
    assert.ok(Math.abs(d5 / d1 - 1.4) < 1e-9);
  });

  test('ramp combines with drainMul', () => {
    const s = Night.create({ nightSec: 100, ramp: 0.1, drainMul: 0.5 });
    s.night = 3;
    assert.ok(Math.abs(drainOf(s) - (0.1 * 100 / 100) * 0.5 * 1.2) < 1e-9);
  });

  test('bad ramp falls back to 0', () => {
    [-1, NaN, 'x', Infinity].forEach(function (r) {
      const s = Night.create({ ramp: r });
      assert.strictEqual(s.ramp, 0);
    });
  });

  test('ramp not serialized; restore takes it from opts', () => {
    const s = Night.create({ ramp: 0.1 });
    assert.strictEqual('ramp' in Night.serialize(s), false);
    const r = Night.restore(Night.serialize(s), { ramp: 0.2 });
    assert.strictEqual(r.ramp, 0.2);
    assert.strictEqual(Night.restore(Night.serialize(s)).ramp, 0);
  });

});

