'use strict';
const test = require('node:test');
const assert = require('node:assert');
const path = require('node:path');

const ROOT = path.join(__dirname, '..');
const VD = require(path.join(ROOT, 'js', 'data', 'voices.js'));
const Audio = require(path.join(ROOT, 'js', 'audio.js'));

class P { constructor(v) { this.value = v; } setValueAtTime() { return this; } linearRampToValueAtTime() { return this; } exponentialRampToValueAtTime() { return this; } }
class N { constructor() { this.outputs = []; } connect(d) { this.outputs.push(d); return d; } }
function fakeCtx() {
  const ctx = { currentTime: 1, state: 'running', destination: new N(), oscs: [] };
  ctx.createOscillator = () => { const n = new N(); n.frequency = new P(440); n.stops = []; n.start = () => {}; n.stop = (t) => n.stops.push(t); ctx.oscs.push(n); return n; };
  ctx.createGain = () => { const n = new N(); n.gain = new P(1); return n; };
  ctx.createBiquadFilter = () => { const n = new N(); n.frequency = new P(350); n.Q = new P(1); return n; };
  return ctx;
}
const audio = (ctx) => ({ ok: true, ctx, volume: 0.7, warned: false });

test('line is deterministic per seed and differs between seeds', () => {
  assert.deepStrictEqual(VD.line(42, 'chat', 'calm'), VD.line(42, 'chat', 'calm'));
  assert.notDeepStrictEqual(VD.line(42, 'chat'), VD.line(43, 'chat'));
  for (const k of VD.KINDS) assert.ok(VD.line('abc', k).length > 0, k);
});

test('forPerson is deterministic and presets differ', () => {
  assert.deepStrictEqual(VD.forPerson(7, 'child'), VD.forPerson(7, 'child'));
  assert.ok(VD.forPerson(7, 'child').pitch > VD.forPerson(7, 'man').pitch * 1.5);
  assert.ok(VD.forPerson(7, 'elder').speed < VD.forPerson(7, 'woman').speed);
  assert.notStrictEqual(VD.forPerson(1, 'man').pitch, VD.forPerson(2, 'man').pitch);
  assert.strictEqual(VD.forPerson(1, 'mother').name, 'woman');
  assert.notDeepStrictEqual(VD.PRESETS.man, VD.PRESETS.woman);
});

test('question ends with rising pitchMul', () => {
  for (let s = 0; s < 20; s++) {
    const l = VD.line(s, 'question');
    assert.ok(l[l.length - 1].pitchMul > l[Math.max(0, l.length - 4)].pitchMul || l.length < 2);
    assert.ok(l[l.length - 1].pitchMul < 1.6 && l[l.length - 1].pitchMul >= 1.15);
  }
});

test('argue is faster than chat on average', () => {
  let c = 0, ar = 0;
  for (let s = 0; s < 30; s++) {
    const a = VD.line(s, 'argue'), b = VD.line(s, 'chat');
    ar += VD.lineLength(a) / a.length;
    c += VD.lineLength(b) / b.length;
  }
  assert.ok(ar < c);
});

test('speakLength matches the line total', () => {
  assert.strictEqual(Audio.speakLength(5, 'chat', 'calm'), VD.lineLength(VD.line(5, 'chat', 'calm')));
  const v = VD.forPerson(5, 'elder');
  const len = Audio.speakLength(5, 'chat', 'calm', v);
  assert.ok(Math.abs(len - VD.lineLength(VD.line(5, 'chat', 'calm')) / v.speed) < 1e-9);
  assert.ok(Audio.speakLength(5, 'chat', 'argue') < Audio.speakLength(5, 'chat', 'calm'));
});

test('speak returns end equal to speakLength and builds formant filters', () => {
  const ctx = fakeCtx();
  const h = Audio.speak(audio(ctx), { seed: 9, kind: 'chat', voice: 'woman', mood: 'calm' });
  assert.ok(h);
  assert.ok(Math.abs(h.end - Audio.speakLength(9, 'chat', 'calm', 'woman')) < 1e-9);
  assert.strictEqual(ctx.oscs.length, 1);
  assert.doesNotThrow(() => h.stop());
});

test('at most 4 concurrent speakers: the oldest is dropped', () => {
  const ctx = fakeCtx();
  const a = audio(ctx);
  const hs = [];
  for (let i = 0; i < 6; i++) hs.push(Audio.speak(a, { seed: i, kind: 'chat' }));
  assert.ok(hs.every(Boolean));
  assert.strictEqual(ctx.__vcsSpeakers.length, 4);
  assert.ok(ctx.oscs[0].stops.length >= 2, 'oldest was stopped early');
  assert.ok(ctx.oscs[1].stops.length >= 2);
  assert.strictEqual(ctx.oscs[5].stops.length, 1);
});

test('speak never throws and returns null without a ctx or when muted', () => {
  assert.strictEqual(Audio.speak(null, {}), null);
  assert.strictEqual(Audio.speak({ ok: true, ctx: null, volume: 1 }), null);
  assert.strictEqual(Audio.speak(audio(fakeCtx()), { seed: 1, gain: 0 }), null);
  assert.strictEqual(Audio.speak({ ok: true, ctx: {}, volume: 1, warned: false }, { seed: 1 }), null);
  assert.strictEqual(Audio.speak(audio(fakeCtx()), { seed: 1, kind: 'bogus', mood: 'x', voice: 'nope' }) !== undefined, true);
});

test('V5 subtitle is deterministic, shaped {de,en} and covers every kind and mood', () => {
  for (const kind of VD.KINDS) {
    for (const mood of ['calm', 'worried', 'whisper', 'argue']) {
      for (let seed = 0; seed < 20; seed++) {
        const a = VD.subtitle(seed, kind, mood);
        const b = VD.subtitle(seed, kind, mood);
        assert.deepStrictEqual(a, b);
        assert.ok(typeof a.de === 'string' && a.de.length > 0, kind + '/' + mood);
        assert.ok(typeof a.en === 'string' && a.en.length > 0, kind + '/' + mood);
      }
    }
  }
  assert.deepStrictEqual(VD.subtitle('x', 'nonsense', 'calm'), VD.subtitle('x', 'chat', 'calm'));
});

test('V5 subtitles vary by seed, kind and mood; whisper and worried differ from calm', () => {
  const seen = new Set();
  for (let s = 0; s < 50; s++) seen.add(VD.subtitle(s, 'chat', 'calm').de);
  assert.ok(seen.size >= 3);
  const kinds = new Set(VD.KINDS.map((k) => VD.subtitle(1, k, 'calm').de));
  assert.equal(kinds.size, VD.KINDS.length);
  for (const kind of VD.KINDS) {
    const calm = new Set(VD.SUBS[kind].calm.map((e) => e.de));
    assert.ok(VD.SUBS[kind].whisper.every((e) => !calm.has(e.de)), kind);
    assert.ok(VD.SUBS[kind].worried.every((e) => !calm.has(e.de)), kind);
  }
});

test('bark kinds: every new kind has a line, subtitles in all tones, and distinct text from calm', () => {
  const barkKinds = ['notice', 'struggle', 'flee', 'cower', 'relief', 'alarm', 'daytalk', 'hum'];
  for (const k of barkKinds) {
    assert.ok(VD.KINDS.includes(k), k);
    for (let s = 0; s < 10; s++) assert.ok(VD.line(s, k, 'calm').length > 0, k);
    assert.deepStrictEqual(VD.line(3, k), VD.line(3, k));
    for (const tone of ['calm', 'worried', 'whisper']) assert.ok(VD.SUBS[k][tone].length >= 1, k + '/' + tone);
  }
  assert.ok(VD.line(1, 'notice').length >= 3);
  assert.ok(VD.lineLength(VD.line(1, 'alarm')) > 0.3);
  for (const k of VD.FEAR_KINDS) assert.ok(VD.KINDS.includes(k));
});

test('daytalk has 10+ distinct role-flavoured lines per group and groupOf maps roles', () => {
  for (const g of ['farmer', 'innkeeper', 'priest', 'drunk', 'guard', 'gravedigger', 'elder', 'mother', 'child']) {
    const list = VD.DAYTALK[g];
    assert.ok(list.length >= 10, g);
    assert.strictEqual(new Set(list.map((e) => e.de)).size, list.length, g);
    for (const e of list) assert.ok(e.de && e.en, g);
    const seen = new Set();
    for (let s = 0; s < 200; s++) seen.add(VD.subtitle(s, 'daytalk', 'calm', g).de);
    assert.ok(seen.size >= 10, g + ' variety ' + seen.size);
    assert.ok([...seen].every((d) => list.some((e) => e.de === d)), g);
  }
  assert.strictEqual(VD.groupOf('regular'), 'innkeeper');
  assert.strictEqual(VD.groupOf('insomniac'), 'villager');
  assert.strictEqual(VD.groupOf('guard'), 'guard');
  assert.notStrictEqual(VD.subtitle(1, 'daytalk', 'calm', 'child').de, VD.subtitle(1, 'daytalk', 'calm', 'priest').de);
});

// ---- v0.14: speech level and struggle weakness -------------------------------------------------------------------------------------
const SoundData = require(path.join(ROOT, 'js', 'data', 'sounds.js'));
globalThis.VCS = globalThis.VCS || {};
globalThis.VCS.SoundData = SoundData;

// A recording context: every gain ramp value, oscillator frequency set and filter frequency set is kept.
function recCtx() {
  const ctx = fakeCtx();
  const gains = [];
  const rec = (n, name) => {
    n[name].sets = [];
    n[name].ramps = [];
    n[name].setValueAtTime = function (v) { this.sets.push(v); return this; };
    n[name].linearRampToValueAtTime = function (v) { this.ramps.push(v); return this; };
  };
  const og = ctx.createGain;
  ctx.createGain = () => { const n = og(); rec(n, 'gain'); gains.push(n); return n; };
  const oo = ctx.createOscillator;
  ctx.createOscillator = () => { const n = oo(); rec(n, 'frequency'); return n; };
  ctx.filters = [];
  const of = ctx.createBiquadFilter;
  ctx.createBiquadFilter = () => { const n = of(); rec(n, 'frequency'); ctx.filters.push(n); return n; };
  ctx.gains = gains;
  return ctx;
}
function speakRec(opts) {
  const ctx = recCtx();
  const h = Audio.speak(audio(ctx), opts);
  const peak = Math.max.apply(null, ctx.gains.reduce((a, g) => a.concat(g.gain.ramps), [0]));
  return { h, ctx, peak, f0: ctx.oscs[0] && ctx.oscs[0].frequency.sets[0] };
}

test('v0.14 speech level: levels.voice is about +4 dB over the old 0.06 fallback and speech is louder than before', () => {
  const row = SoundData.levels.voice;
  assert.ok(row && row.gain > 0.06 * 1.4 && row.gain < 0.06 * 1.9, 'voice gain ' + (row && row.gain));
  assert.ok(row.hearDist >= 14);
  const o = { voice: 'man', seed: 3, kind: 'chat', mood: 'calm' };
  const after = speakRec(o).peak;
  const saved = SoundData.levels.voice;
  delete SoundData.levels.voice; // old behaviour: fallback 0.06
  const before = speakRec(o).peak;
  SoundData.levels.voice = saved;
  assert.ok(after > before * 1.4, 'after ' + after + ' before ' + before);
  // speech ignores mixOther
  const m = SoundData.mixOther;
  SoundData.mixOther = 0.2;
  const quietMix = speakRec(o).peak;
  SoundData.mixOther = m;
  assert.strictEqual(quietMix, after);
});

test('v0.14 weak: slower, lower, quieter and slurred, monotonic in weak', () => {
  const ws = [0, 0.25, 0.5, 0.75, 1];
  // chat lines do not depend on weak, so lengths isolate the speed effect
  const lens = ws.map((w) => Audio.speakLength(9, 'chat', 'calm', 'man', w));
  for (let i = 1; i < lens.length; i++) assert.ok(lens[i] > lens[i - 1], 'length grows ' + lens);
  assert.ok(Math.abs(lens[4] / lens[0] - 1 / 0.6) < 1e-6, 'down to 0.6x speed');
  assert.strictEqual(Audio.speakLength(9, 'chat', 'calm', 'man'), lens[0], 'weak absent = healthy');
  const run = ws.map((w) => speakRec({ voice: 'man', seed: 9, kind: 'chat', mood: 'calm', weak: w }));
  for (let i = 1; i < run.length; i++) {
    assert.ok(run[i].peak < run[i - 1].peak, 'quieter ' + run.map((r) => r.peak));
    assert.ok(run[i].f0 < run[i - 1].f0, 'lower ' + run.map((r) => r.f0));
    assert.ok(run[i].h.end > run[i - 1].h.end, 'longer');
  }
  // slur: formants move toward a neutral vowel (F1 500) between weak 0.5 (none) and 1
  const f1 = (w) => speakRec({ voice: 'man', seed: 9, kind: 'chat', mood: 'calm', weak: w }).ctx.filters[0].frequency.sets[0];
  assert.strictEqual(f1(0), f1(0.5), 'no slur above 60% blood');
  assert.ok(f1(1) !== f1(0) || f1(0) === 500, 'formants smear when slurred');
  assert.ok(Math.abs(f1(1) - 500) < Math.abs(f1(0) - 500) || f1(0) === 500, 'toward neutral');
  assert.ok(speakRec({ voice: 'man', seed: 9, kind: 'struggle', mood: 'worried', weak: 1 }).h, 'still speaks when nearly drained');
});

test('v0.14 struggle lines: shout / plea / slurred / groan tiers are distinct, deterministic and subtitled', () => {
  assert.strictEqual(VD.STRUGGLE_TIERS.length, 4);
  VD.STRUGGLE_TIERS.forEach((t) => assert.ok(t.length >= 6 && t.every((e) => e.de && e.en)));
  for (const [w, tier] of [[0, 0], [0.4, 1], [0.7, 2], [0.95, 3]]) {
    assert.strictEqual(VD.struggleTier(w), tier);
    const des = new Set();
    for (let s = 0; s < 60; s++) {
      const sub = VD.subtitle(s, 'struggle', 'worried', 'farmer', w);
      assert.ok(VD.STRUGGLE_TIERS[tier].some((e) => e.de === sub.de && e.en === sub.en));
      des.add(sub.de);
      assert.deepStrictEqual(VD.line(s, 'struggle', 'worried', w), VD.line(s, 'struggle', 'worried', w));
    }
    assert.ok(des.size >= Math.min(6, VD.STRUGGLE_TIERS[tier].length), 'variety in tier ' + tier);
  }
  // slurred lines are slower per syllable than shouts; groans are 1-2 syllables
  const avgDur = (w) => { let t = 0, n = 0; for (let s = 0; s < 40; s++) VD.line(s, 'struggle', 'worried', w).forEach((x) => { t += x.dur + x.gap; n++; }); return t / n; };
  assert.ok(avgDur(0.7) > avgDur(0) * 1.8);
  for (let s = 0; s < 40; s++) assert.ok(VD.line(s, 'struggle', 'worried', 0.95).length <= 2);
  assert.ok(/\.\.\./.test(VD.subtitle(1, 'struggle', 'worried', '', 0.7).de), 'slurred text trails off');
  // legacy call (no weak) keeps the old pool
  assert.ok(VD.subtitle(1, 'struggle', 'calm').de.length > 0);
});

test('v0.14 guard kinds: halt and guardcall have lines and subtitles in every tone', () => {
  for (const k of ['halt', 'guardcall']) {
    assert.ok(VD.KINDS.indexOf(k) >= 0);
    assert.ok(VD.line(4, k, 'call').length > 0);
    for (const m of ['calm', 'worried', 'whisper']) assert.ok(VD.SUBS[k][m].length >= 2, k + m);
  }
  assert.ok(VD.SUBS.halt.calm.some((e) => /Hoit/.test(e.de)));
  assert.ok(VD.SUBS.guardcall.calm.filter((e) => /ruhig/.test(e.de)).length >= 4);
  assert.ok(VD.MOODS.call && VD.MOODS.call.gain > 1);
});
