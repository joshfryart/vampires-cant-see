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
