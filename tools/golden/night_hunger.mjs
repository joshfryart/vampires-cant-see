#!/usr/bin/env node
// Golden fixture: js/night.js and js/hunger.js operation sequences. Each run records the operations and, after every
// operation, the return value and the serialised/visible state. Restore cases cover good and corrupt inputs.
// Usage: node tools/golden/night_hunger.mjs [outPath]   (default project/tests/fixtures/night_hunger.json)

import { createRequire } from 'node:module';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { mkdirSync, writeFileSync } from 'node:fs';

const require = createRequire(import.meta.url);
const HERE = dirname(fileURLToPath(import.meta.url));
const PORT = resolve(HERE, '..', '..');
const JS = join(PORT, 'html-version', 'js');
const OUT = process.argv[2] ? resolve(process.argv[2]) : join(PORT, 'project', 'tests', 'fixtures', 'night_hunger.json');

for (const m of ['log', 'data/hunger', 'night', 'hunger']) require(join(JS, m + '.js'));
const VCS = globalThis.VCS;
VCS.Log.setConsole(false);
const { Night, Hunger } = VCS;

// ---------------- Night ----------------
function nightState(st) {
  return { night: st.night, min: st.min, blood: st.blood, status: st.status, reason: st.reason, fired: Object.assign({}, st.fired), fedCount: st.fedCount, drainMul: st.drainMul, ramp: st.ramp, nights: st.nights, nightSec: st.nightSec, bloodMax: st.bloodMax, feedGain: st.feedGain };
}
function nightRun(key, opts, ops) {
  const st = Night.create(opts);
  const steps = [];
  for (const o of ops) {
    let res;
    if (o.op === 'update') res = Night.update(st, o.dt, o.ctx);
    else if (o.op === 'feed') res = Night.feed(st);
    else if (o.op === 'addBlood') res = Night.addBlood(st, o.amt);
    else if (o.op === 'sleep') res = Night.sleep(st);
    else if (o.op === 'skipTo') res = Night.skipTo(st, o.h, o.m);
    steps.push({ op: o, res, state: nightState(st), clock: Night.clock(st), weak: Night.weakness(st), wash: Night.washK(st), dawn: Night.dawnK(st), isDay: Night.isDay(st), ser: Night.serialize(st) });
  }
  return { key, opts: opts || null, ops, steps, init: nightState(Night.create(opts)) };
}
const nightRuns = [];
const ticks = (n, dt, ctx) => Array.from({ length: n }, () => ({ op: 'update', dt, ctx }));
nightRuns.push(nightRun('full night', {}, [...ticks(4800, 0.1, {}), { op: 'sleep' }, ...ticks(10, 0.05, {})]));
nightRuns.push(nightRun('sun kills', { nightSec: 60 }, [...ticks(620, 0.1, { outdoor: false }), ...ticks(5, 0.1, { outdoor: true }), { op: 'sleep' }]));
nightRuns.push(nightRun('feeding', { bloodStart: 10, feedGain: 30 }, [{ op: 'feed' }, { op: 'feed' }, { op: 'feed' }, { op: 'feed' }, { op: 'addBlood', amt: 12.5 }, { op: 'addBlood', amt: -3 }, { op: 'addBlood', amt: NaN }, ...ticks(200, 0.1, {})]));
nightRuns.push(nightRun('five nights', { nights: 3, nightSec: 30, drainMul: 0.5, ramp: 0.2 }, [
  ...ticks(320, 0.1, {}), { op: 'sleep' }, ...ticks(320, 0.1, {}), { op: 'sleep' }, ...ticks(320, 0.1, {}), { op: 'sleep' }, { op: 'sleep' }, { op: 'update', dt: 0.1 }]));
nightRuns.push(nightRun('skipTo', { nightSec: 100 }, [{ op: 'skipTo', h: 5, m: 59 }, ...ticks(10, 0.1, {}), { op: 'skipTo', h: 20, m: 0 }, { op: 'skipTo', h: 6, m: 0 }, { op: 'skipTo', h: 7, m: 0 }, { op: 'skipTo', h: 1.5, m: 0 }, { op: 'skipTo', h: 3, m: 60 }, { op: 'skipTo', h: 23, m: 59 }, { op: 'skipTo', h: 0, m: 0 }, { op: 'update', dt: 5 }, { op: 'update', dt: -1 }, { op: 'update', dt: NaN }]));
nightRuns.push(nightRun('bad options', { nightSec: -5, nights: 2.5, bloodMax: 0, bloodStart: 1000, feedGain: 'x', drainMul: -1, ramp: -2 }, ticks(20, 0.1, {})));
nightRuns.push(nightRun('bloodStart 0', { bloodStart: 0, bloodMax: 50 }, ticks(20, 0.1, {})));

const goodNight = Night.serialize((() => { const s = Night.create({}); Night.update(s, 0.1); return s; })());
const nightRestore = [];
function nr(key, obj, opts) { const st = Night.restore(obj, opts); nightRestore.push({ key, obj, opts: opts || null, ok: !!st, state: st ? nightState(st) : null }); }
nr('good', goodNight);
nr('extra key', Object.assign({}, goodNight, { x: 1 }));
nr('bad version', Object.assign({}, goodNight, { v: 2 }));
nr('night 0', Object.assign({}, goodNight, { night: 0 }));
nr('night 9', Object.assign({}, goodNight, { night: 9 }));
nr('min high', Object.assign({}, goodNight, { min: 601 }));
nr('blood high', Object.assign({}, goodNight, { blood: 101 }));
nr('bad status', Object.assign({}, goodNight, { status: 'zzz' }));
nr('long reason', Object.assign({}, goodNight, { reason: 'x'.repeat(40) }));
nr('bad fed', Object.assign({}, goodNight, { fedCount: -1 }));
nr('bad fired', Object.assign({}, goodNight, { fired: { chime: 1, washout: false, dawn: false } }));
nr('fired extra', Object.assign({}, goodNight, { fired: { chime: true, washout: false, dawn: false, q: true } }));
nr('day before dawn', Object.assign({}, goodNight, { status: 'day', min: 10 }));
nr('day after dawn', Object.assign({}, goodNight, { status: 'day', min: 600, fired: { chime: true, washout: true, dawn: true } }));
nr('not object', 5);
nr('null', null);

// ---------------- Hunger ----------------
function hungerState(h) {
  return { fear: h.fear, over: h.over, giftsTonight: h.giftsTonight, gifts: h.gifts.slice(), essenceBonus: h.essenceBonus, nextBlood: h.nextBlood, grabbed: h.grabbed.slice(), cd: Object.assign({}, h.cd), stillLeft: h.stillLeft };
}
function hungerRun(key, ops) {
  const h = Hunger.create();
  const steps = [];
  for (const o of ops) {
    let res;
    if (o.op === 'addOverflow') res = Hunger.addOverflow(h, o.amt);
    else if (o.op === 'takeGift') res = Hunger.takeGift(h, o.id);
    else if (o.op === 'rollGifts') res = Hunger.rollGifts(h, o.seed);
    else if (o.op === 'onGrab') res = Hunger.onGrab(h, o.id);
    else if (o.op === 'addFear') res = Hunger.addFear(h, o.n);
    else if (o.op === 'use') res = Hunger.use(h, o.id, o.night, o.blood);
    else if (o.op === 'tick') { Hunger.tick(h, o.dt); res = null; }
    else if (o.op === 'onSleep') res = Hunger.onSleep(h);
    steps.push({ op: o, res: res === undefined ? null : res, state: hungerState(h), cost: Hunger.cost(h), isOpen: Hunger.isOpen(h), over01: Hunger.over01(h), mods: Hunger.fearMods(h), giftMods: Hunger.giftMods(h), still: Hunger.isStill(h), pstate: ['shriek', 'mist', 'still'].map((id) => Hunger.powerState(h, id, 2, 12)), cd01: ['shriek', 'mist', 'still'].map((id) => Hunger.cdLeft01(h, id)), ser: Hunger.serialize(h) });
  }
  return { key, ops, steps };
}
const hungerRuns = [];
hungerRuns.push(hungerRun('overflow and gifts', [
  { op: 'addOverflow', amt: 15 }, { op: 'addOverflow', amt: 30 }, { op: 'addOverflow', amt: 100 }, { op: 'rollGifts', seed: 7 }, { op: 'takeGift', id: 'g_calm' },
  { op: 'addOverflow', amt: 50 }, { op: 'addOverflow', amt: 50 }, { op: 'takeGift', id: 'g_reserve' }, { op: 'addOverflow', amt: 10 }, { op: 'takeGift', id: 'nope' }, { op: 'takeGift', id: 'g_far' },
  { op: 'rollGifts', seed: 123456789 }, { op: 'rollGifts', seed: -5 }, { op: 'rollGifts', seed: 4294967295 }, { op: 'onSleep' }, { op: 'addOverflow', amt: NaN }, { op: 'addOverflow', amt: -4 }]));
hungerRuns.push(hungerRun('fear', [
  { op: 'addFear', n: 3 }, { op: 'addFear', n: 2.5 }, { op: 'addFear', n: 2.4 }, { op: 'addFear', n: 100 }, { op: 'addFear', n: -200 }, { op: 'addFear', n: NaN }, { op: 'addFear', n: -0.5 }, { op: 'addFear', n: 0.5 },
  { op: 'onGrab', id: 'crypt:1' }, { op: 'onGrab', id: 'crypt:1' }, { op: 'onGrab', id: 'town:2' }, { op: 'onGrab', id: null }, { op: 'onGrab', id: 7 }, { op: 'onSleep' }, { op: 'onSleep' }]));
hungerRuns.push(hungerRun('powers', [
  { op: 'use', id: 'shriek', night: 1, blood: 50 }, { op: 'use', id: 'shriek', night: 1, blood: 50 }, { op: 'tick', dt: 0.1 }, { op: 'use', id: 'mist', night: 1, blood: 50 }, { op: 'use', id: 'mist', night: 2, blood: 5 },
  { op: 'use', id: 'mist', night: 2, blood: 50 }, { op: 'use', id: 'still', night: 3, blood: 50 }, ...Array.from({ length: 60 }, () => ({ op: 'tick', dt: 0.1 })), { op: 'use', id: 'bogus', night: 3, blood: 50 },
  ...Array.from({ length: 100 }, () => ({ op: 'tick', dt: 0.1 })), { op: 'use', id: 'shriek', night: 5, blood: 15 }, { op: 'tick', dt: NaN }, { op: 'tick', dt: -1 }, { op: 'tick', dt: 5 }]));

const hungerRestore = [];
const goodH = (() => { const h = Hunger.create(); Hunger.addFear(h, 4); Hunger.addOverflow(h, 20); Hunger.takeGift(h, 'g_far'); return Hunger.serialize(h); })();
function hr(key, obj) { const st = Hunger.restore(obj); hungerRestore.push({ key, obj, ok: !!st, state: st ? hungerState(st) : null }); }
hr('good', goodH);
hr('missing key', (() => { const o = Object.assign({}, goodH); delete o.fear; return o; })());
hr('extra key', Object.assign({}, goodH, { zed: 1 }));
hr('bad version', Object.assign({}, goodH, { v: 9 }));
hr('fear float', Object.assign({}, goodH, { fear: 2.5 }));
hr('fear high', Object.assign({}, goodH, { fear: 16 }));
hr('negative over', Object.assign({}, goodH, { over: -1 }));
hr('gifts too many', Object.assign({}, goodH, { giftsTonight: 3 }));
hr('bad gift id', Object.assign({}, goodH, { gifts: ['nope'] }));
hr('gift not string', Object.assign({}, goodH, { gifts: [3] }));
hr('over beyond cost', Object.assign({}, goodH, { over: 1000 }));
hr('not object', 'x');

mkdirSync(dirname(OUT), { recursive: true });
writeFileSync(OUT, JSON.stringify({ nightRuns, nightRestore, hungerRuns, hungerRestore, hungerData: VCS.HungerData }) + '\n');
console.log('wrote ' + OUT + ' (' + nightRuns.length + ' night runs, ' + hungerRuns.length + ' hunger runs)');
