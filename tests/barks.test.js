'use strict';
const test = require('node:test');
const assert = require('node:assert');
const path = require('node:path');

const ROOT = path.join(__dirname, '..');
const VD = require(path.join(ROOT, 'js', 'data', 'voices.js'));
const Barks = require(path.join(ROOT, 'js', 'barks.js'));

function person(id, x, y, extra) {
  return Object.assign({ id: id, x: x, y: y, mode: 'path', wary: 0, chat: null, sched: { role: 'farmer' } }, extra || {});
}
// Runs the barks over `secs` seconds; mutate(t, people) may change people each tick. Returns all barks with their times.
function run(seed, people, secs, opts) {
  const o = opts || {};
  const st = Barks.create(seed);
  const out = [];
  const player = o.player || { x: 0, y: 0 };
  for (let t = 0; t <= secs; t += 0.1) {
    const now = Math.round(t * 10) / 10;
    if (o.mutate) o.mutate(now, people);
    const r = Barks.step(st, { now: now, player: player, people: people, fear: o.fear || 0, enabled: o.enabled, lengthFn: () => 1 });
    r.barks.forEach((b) => out.push(Object.assign({ t: now }, b)));
  }
  return { st: st, out: out };
}

test('deterministic from seed and sim time', () => {
  const mk = () => [person(1, 4, 0), person(2, 5, 0, { chat: { partner: 3 } }), person(3, 6, 0, { chat: { partner: 2 } })];
  mk()[1].chat.partner = 3;
  const link = () => { const p = mk(); p[1].chat = { partner: 3 }; p[2].chat = { partner: 2 }; return p; };
  const a = run(7, link(), 120).out;
  const b = run(7, link(), 120).out;
  assert.ok(a.length > 3);
  assert.deepStrictEqual(a, b);
  const c = run(8, link(), 120).out;
  assert.notDeepStrictEqual(a, c);
});

test('no Math.random or Date in the module', () => {
  const src = require('node:fs').readFileSync(path.join(ROOT, 'js', 'barks.js'), 'utf8');
  assert.ok(!/Math\.random|Date\.now|new Date/.test(src));
});

test('per-villager cooldown: consecutive barks are at least 4 s apart (calm ones 6 s+)', () => {
  const ppl = [person(1, 3, 0, { chat: null })];
  const { out } = run(3, ppl, 400);
  assert.ok(out.length >= 3, 'alone villager mumbles now and then: ' + out.length);
  for (let i = 1; i < out.length; i++) assert.ok(out[i].t - out[i - 1].t >= 6, 'gap ' + (out[i].t - out[i - 1].t));
});

test('no line twice in a row per villager', () => {
  const ppl = [person(1, 3, 0)];
  const { out } = run(5, ppl, 1500);
  assert.ok(out.length > 10);
  let last = '';
  for (const b of out) {
    const de = Barks.subtitleFor(b).de;
    assert.notStrictEqual(de, last);
    last = de;
  }
});

test('daytalk proximity gate: far villagers and the setting off stay silent', () => {
  const far = run(2, [person(1, 14, 0), person(2, 30, 0)], 300).out;
  assert.strictEqual(far.length, 0);
  const near = run(2, [person(1, 6, 0)], 300).out;
  assert.ok(near.length > 0);
  const off = run(2, [person(1, 6, 0)], 300, { enabled: false }).out;
  assert.strictEqual(off.length, 0);
});

test('chatting partners take turns', () => {
  const link = () => { const a = person(1, 4, 0, { chat: { partner: 2 } }); const b = person(2, 5, 0, { chat: { partner: 1 } }); return [a, b]; };
  const { out } = run(4, link(), 200);
  assert.ok(out.length >= 4);
  for (let i = 1; i < out.length; i++) assert.notStrictEqual(out[i].id, out[i - 1].id, 'speakers alternate');
  for (let i = 1; i < out.length; i++) assert.ok(out[i].t >= out[i - 1].t + 1 - 1e-9, 'no overlap');
  assert.ok(out.every((b) => b.kind === 'daytalk'));
});

test('events: startle, flee, cower, struggle then relief, wary notice', () => {
  const p = person(1, 5, 0);
  const seq = [[1, 'startle'], [10, 'flee'], [25, 'cower'], [40, 'grapple'], [60, 'path']];
  const { out } = run(9, [p], 70, { mutate: (t, ps) => { for (const s of seq) if (t >= s[0]) { ps[0].mode = s[1]; ps[0].bumping = s[1] === 'startle'; } } });
  const kinds = out.map((b) => b.kind);
  assert.strictEqual(kinds[0], 'startle');
  assert.ok(kinds.includes('flee'));
  assert.ok(kinds.includes('cower'));
  assert.ok(kinds.filter((k) => k === 'struggle').length >= 3, 'periodic struggle cries: ' + kinds.join(','));
  assert.ok(kinds.includes('relief'));
  assert.ok(out.filter((b) => b.kind === 'struggle').every((b) => b.loud));
  const q = person(1, 5, 0);
  const n = run(9, [q], 12, { mutate: (t, ps) => { if (t >= 3) ps[0].wary = 10; } }).out;
  assert.strictEqual(n[0].kind, 'notice');
  assert.ok(Math.abs(n[0].t - 3) < 0.2);
  // a noise startle (people.js startle without bumping) is the notice cry
  const ns = run(9, [person(1, 5, 0)], 6, { mutate: (t, ps) => { if (t >= 2) ps[0].mode = 'startle'; } }).out;
  assert.strictEqual(ns[0].kind, 'notice');
});

test('nothing at the first step (no burst on load) and drained or dazed villagers are silent', () => {
  const st = Barks.create(1);
  const r = Barks.step(st, { now: 0, player: { x: 0, y: 0 }, people: [person(1, 3, 0, { mode: 'flee' })], fear: 0 });
  assert.strictEqual(r.barks.length, 0);
  const out = run(1, [person(1, 3, 0)], 100, { mutate: (t, ps) => { if (t >= 1) ps[0].mode = 'fed'; } }).out;
  assert.strictEqual(out.length, 0);
  const dz = run(1, [person(1, 3, 0)], 100, { mutate: (t, ps) => { if (t >= 1) ps[0].mode = 'dazed'; } }).out;
  assert.strictEqual(dz.length, 0);
});

test('caps: at most 2 starts per second and 3 speakers at once; nearest and fear first', () => {
  const ppl = [];
  for (let i = 0; i < 8; i++) ppl.push(person(i + 1, 2 + i, 0));
  const { out } = run(6, ppl, 5, { mutate: (t, ps) => { if (t >= 1) for (const q of ps) q.mode = 'startle'; } });
  assert.ok(out.length >= 2);
  for (let i = 0; i < out.length; i++) {
    const inSec = out.filter((b) => b.t > out[i].t - 1 && b.t <= out[i].t).length;
    assert.ok(inSec <= 2, 'starts in 1 s: ' + inSec);
    const active = out.filter((b) => b.t <= out[i].t && b.t + b.len > out[i].t).length;
    assert.ok(active <= 3, 'active ' + active);
  }
  assert.deepStrictEqual(out.slice(0, 2).map((b) => b.id), [1, 2], 'nearest first');
  // fear beats daytalk for the free slot
  const st = Barks.create(1);
  const people = [person(1, 2, 0), person(2, 9, 0)];
  Barks.step(st, { now: 0, player: { x: 0, y: 0 }, people: people });
  st.active = [{ id: 98, end: 99 }, { id: 99, end: 99 }];
  people[1].mode = 'flee';
  const r = Barks.step(st, { now: 1, player: { x: 0, y: 0 }, people: people });
  assert.strictEqual(r.barks.length, 1);
  assert.strictEqual(r.barks[0].kind, 'flee');
});

test('high village fear: daytalk whispers, alarms are loud shouts', () => {
  const { out } = run(2, [person(1, 5, 0)], 300, { fear: 9 });
  assert.ok(out.length > 0);
  assert.ok(out.every((b) => b.mood === 'whisper' && !b.loud));
  const ppl = [person(1, 5, 0), person(2, 6, 0, { mode: 'path' })];
  const al = run(2, ppl, 20, { mutate: (t, ps) => { if (t >= 2) ps[1].mode = 'fed'; } }).out;
  const a = al.find((b) => b.kind === 'alarm');
  assert.ok(a && a.loud && a.mood === 'argue');
});

test('barks carry a subtitle that matches their kind and seed, and the role pool', () => {
  const { out } = run(2, [person(1, 5, 0, { sched: { role: 'child' } })], 300);
  const pool = VD.DAYTALK.child.map((e) => e.de).concat(VD.SUBS.hum.calm.map((e) => e.de));
  for (const b of out) assert.ok(pool.includes(Barks.subtitleFor(b).de), b.kind + ' ' + Barks.subtitleFor(b).de);
});

test('reset re-baselines without barking and step never throws on junk', () => {
  const st = Barks.create(1);
  assert.doesNotThrow(() => Barks.step(st, null));
  assert.doesNotThrow(() => Barks.step(st, { now: 'x', people: [null, {}, { id: 1 }] }));
  const ppl = [person(1, 3, 0)];
  Barks.step(st, { now: 0, player: { x: 0, y: 0 }, people: ppl });
  Barks.reset(st);
  ppl[0].mode = 'flee';
  assert.strictEqual(Barks.step(st, { now: 1, player: { x: 0, y: 0 }, people: ppl }).barks.length, 0);
});

// ---- v0.14: struggle voice by blood left, guards ---------------------------------------------------------------------------------
function victim(left, extra) { return person(1, 3, 0, Object.assign({ pool: 40, left: left }, extra || {})); }
// Calm for 2 s, then grabbed for `secs`; left may be a function of seconds since the grab. Returns barks with times.
function grab(left, secs, opts) {
  const o = opts || {};
  const p = victim(typeof left === 'function' ? left(0) : left, o.extra);
  const r = run(o.seed || 11, [p], secs + 2, {
    mutate: (t, ppl) => {
      if (t >= 2) { ppl[0].mode = 'grapple'; if (typeof left === 'function') ppl[0].left = left(t - 2); }
    }
  });
  return r.out;
}

test('struggle keeps barking for the whole grab (healthy: every ~1.5-3 s)', () => {
  const out = grab(40, 60);
  assert.ok(out.length >= 18, 'barks ' + out.length);
  assert.ok(out.every((b) => b.kind === 'struggle'));
  for (let i = 1; i < out.length; i++) {
    const gap = out[i].t - out[i - 1].t;
    assert.ok(gap >= 1.4 && gap <= 3.6, 'gap ' + gap);
  }
  assert.ok(out[out.length - 1].t > 55, 'still going at the end');
  assert.ok(out.every((b) => b.weak === 0 && b.mood === 'argue'));
});

test('cadence widens, gain and mood follow blood loss; weak rides on the bark', () => {
  const avgGap = (left) => { const o = grab(left, 120); assert.ok(o.length >= 5, 'barks at ' + left + ': ' + o.length); return (o[o.length - 1].t - o[0].t) / (o.length - 1); };
  const g100 = avgGap(40), g60 = avgGap(24), g30 = avgGap(12), g10 = avgGap(4);
  assert.ok(g100 < g60 && g60 < g30 && g30 < g10, [g100, g60, g30, g10].join(' < '));
  assert.ok(g100 < 3.4 && g10 > 5, 'ends of the range: ' + g100 + ' / ' + g10);
  const b = grab(12, 20)[0];
  assert.ok(Math.abs(b.weak - 0.7) < 1e-9);
  assert.strictEqual(b.mood, 'worried');
});

test('struggle goes silent at empty and once drained', () => {
  assert.strictEqual(grab(0, 30).length, 0, 'empty');
  assert.strictEqual(grab(0.5, 30).length, 0, 'under 2 % left');
  const out = grab((t) => Math.max(0, 40 - t * 2), 40);
  assert.ok(out.length >= 6);
  assert.ok(out[out.length - 1].t < 2 + 20 + 0.1, 'silent once drained, last at ' + out[out.length - 1].t);
});

test('struggle lines vary: never the same subtitle twice in a row, tiers follow weakness', () => {
  const out = grab((t) => Math.max(1, 40 - t * 0.6), 60, { seed: 5 });
  assert.ok(out.length >= 15);
  let last = '';
  for (const b of out) { const de = Barks.subtitleFor(b).de; assert.notStrictEqual(de, last); last = de; }
  const first = Barks.subtitleFor(out[0]).de, lastDe = Barks.subtitleFor(out[out.length - 1]).de;
  assert.ok(VD.STRUGGLE_TIERS[0].some((e) => e.de === first));
  assert.ok(VD.STRUGGLE_TIERS[2].concat(VD.STRUGGLE_TIERS[3]).some((e) => e.de === lastDe), lastDe);
  assert.ok(new Set(out.map((b) => Barks.subtitleFor(b).de)).size >= 8);
});

test('restrained victims are muffled and quieter', () => {
  const gainOf = (restrained) => {
    const st = Barks.create(3);
    const ppl = [person(1, 3, 0, { pool: 40, left: 30 })];
    let out = [];
    for (let t = 0; t <= 6; t += 0.1) {
      if (t >= 1) ppl[0].mode = 'grapple';
      const r = Barks.step(st, { now: Math.round(t * 10) / 10, player: { x: 0, y: 0 }, people: ppl, fear: 0, lengthFn: () => 1, restrained: restrained ? 1 : undefined });
      out = out.concat(r.barks);
    }
    return out[0];
  };
  const free = gainOf(false), held = gainOf(true);
  assert.strictEqual(free.restrained, false);
  assert.strictEqual(held.restrained, true);
  assert.ok(held.gain < free.gain * 0.7);
});

test('guards: call out ("Wer da? Alles ruhig", the hour) from farther away and shout HALT on noticing you', () => {
  const guard = (id, x, extra) => person(id, x, 0, Object.assign({ sched: { role: 'guard' } }, extra || {}));
  assert.ok(Barks.isGuard(guard(1, 3)));
  const out = run(6, [guard(1, 14)], 600).out; // 14 cells: past the villagers' 12 cell daytalk range
  assert.ok(out.length >= 5, 'guard calls from 14 cells: ' + out.length);
  assert.ok(out.some((b) => b.kind === 'guardcall'), 'guardcall kind');
  assert.ok(out.every((b) => b.role === 'guard'));
  const dess = new Set(out.filter((b) => b.kind === 'guardcall').map((b) => Barks.subtitleFor(b).de));
  assert.ok(dess.size >= 4);
  assert.ok(out.filter((b) => b.kind === 'guardcall').every((b) => b.mood === 'call'));
  const farmer = run(6, [person(1, 14, 0)], 600).out;
  assert.strictEqual(farmer.length, 0, 'villagers stay quiet at 14 cells');
  const notice = (p) => run(2, [p], 6, { mutate: (t, ppl) => { if (t >= 1) ppl[0].mode = 'startle'; } }).out;
  const g = notice(guard(1, 4)), f = notice(person(1, 4, 0));
  assert.strictEqual(g[0].kind, 'halt');
  assert.strictEqual(f[0].kind, 'notice');
  assert.ok(/Hoit|Alarm|Stehnbleibn|Wer da|Wachn/.test(Barks.subtitleFor(g[0]).de));
  assert.ok(g[0].loud);
});

test('people.stepEvents: guards walk with the heavy mail gait, runners still run', () => {
  const People = require(path.join(ROOT, 'js', 'people.js'));
  const mkp = (role, mode) => ({ id: 1, x: 1, y: 1, angle: 0, steps: 2, stepsReported: 0, mode: mode || 'path', wary: 0, speed: 1.3, role: role });
  const out = [];
  People.stepEvents({ people: [mkp('guard'), mkp('')] }, 0, 1, out);
  assert.deepStrictEqual(out.map((e) => e.gait), ['mail', 'mail', 'walk', 'walk']);
  People.stepEvents({ people: [Object.assign(mkp('guard'), { steps: 1 }), mkp('guard', 'flee')] }, 0, 1, out);
  assert.strictEqual(out[0].gait, 'mail');
  assert.strictEqual(out[1].gait, 'run');
});
