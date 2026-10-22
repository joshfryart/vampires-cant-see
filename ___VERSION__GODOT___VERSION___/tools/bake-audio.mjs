#!/usr/bin/env node
// Bakes the Web Audio recipes of js/audio.js into WAV files for the Godot port.
// Usage: node tools/bake-audio.mjs        (needs `npm install` in tools/ for node-web-audio-api)
// Output: project/audio/wav/*.wav (mono, 44.1 kHz, 16 bit) and project/audio/manifest.json.
//
// How: js/audio.js is loaded unchanged. Each variation runs the real Audio.play / Audio.echo / Audio.ping against an
// OfflineAudioContext with the master chain replaced by a dry pass-through (Godot supplies the compressor, reverb and
// panning), with Math.random and the pitch variation (a.rand) fixed so the files are deterministic.
// Manifest per entry: {file, kind, voice?, material?, foot?, pitch?, rough?, room?, ref, scale, ms}
//   ref   = the "peak" parameter the JS used for the render (volume x gain, or volume x 0.35 x strength for echoes)
//   scale = normalisation applied to the samples (peak 0.9)
//   In Godot: linear gain = P / (ref * scale), P = the JS peak parameter for the sound being played.

import { createRequire } from 'node:module';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { mkdirSync, writeFileSync, rmSync } from 'node:fs';
import { OfflineAudioContext } from 'node-web-audio-api';

const require = createRequire(import.meta.url);
const HERE = dirname(fileURLToPath(import.meta.url));
const PORT = resolve(HERE, '..');
const JS = join(resolve(PORT, '..'), 'js');
const OUT = join(PORT, 'project', 'audio');
const WAV = join(OUT, 'wav');

for (const m of ['log', 'data/sounds', 'data/voices', 'audio']) require(join(JS, m + '.js'));
const VCS = globalThis.VCS;
VCS.Log.setConsole(false);
const Audio = VCS.Audio;
const SD = VCS.SoundData;

const RATE = 44100;
const PLAY_GAIN = 0.3;      // gain handed to Audio.play when baking
const PEAK_TARGET = 0.9;

// ---- deterministic randomness ----
function mulberry(seed) {
  let a = seed >>> 0;
  return function () {
    a = (a + 0x6D2B79F5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

function wav16(samples, scale) {
  const n = samples.length;
  const buf = Buffer.alloc(44 + n * 2);
  buf.write('RIFF', 0); buf.writeUInt32LE(36 + n * 2, 4); buf.write('WAVE', 8); buf.write('fmt ', 12);
  buf.writeUInt32LE(16, 16); buf.writeUInt16LE(1, 20); buf.writeUInt16LE(1, 22); buf.writeUInt32LE(RATE, 24);
  buf.writeUInt32LE(RATE * 2, 28); buf.writeUInt16LE(2, 32); buf.writeUInt16LE(16, 34); buf.write('data', 36); buf.writeUInt32LE(n * 2, 40);
  for (let i = 0; i < n; i++) buf.writeInt16LE(Math.max(-32768, Math.min(32767, Math.round(samples[i] * scale * 32767))), 44 + i * 2);
  return buf;
}

const manifest = {};
let count = 0;
let bakeBip = false; // the old cartoon bip ping (setting pingBip)

async function bake(key, entry, seconds, fn) {
  const len = Math.ceil(seconds * RATE);
  const ctx = new OfflineAudioContext(1, len, RATE);
  ctx.__vcsMaster = { out: ctx.destination, send: null, delays: [], fbs: [], lp: null }; // dry
  const seq = entry._rand || [0.5, 0.5, 0.5, 0.5];
  let ri = 0;
  const a = { ok: true, ctx, volume: 1, warned: false, pingBip: bakeBip, room: 'indoor', rand: () => seq[ri++ % seq.length] };
  Math.random = mulberry(0xC0FFEE + count * 7919);
  const ok = fn(a);
  const rendered = await ctx.startRendering();
  const data = rendered.getChannelData(0);
  let peak = 0;
  let last = 0;
  for (let i = 0; i < data.length; i++) {
    const v = Math.abs(data[i]);
    if (v > peak) peak = v;
    if (v > 1e-4) last = i;
  }
  if (ok === false || peak < 1e-5) { console.warn('skip (silent):', key); return; }
  const end = Math.min(data.length, last + Math.ceil(0.02 * RATE));
  const slice = data.slice(0, end);
  const scale = PEAK_TARGET / peak;
  const file = key.replace(/[^A-Za-z0-9_.-]/g, '_') + '.wav';
  writeFileSync(join(WAV, file), wav16(slice, scale));
  delete entry._rand;
  (manifest[entry.kind + ':' + entry.name] = manifest[entry.kind + ':' + entry.name] || []).push(Object.assign({ file, scale, ms: Math.round((end / RATE) * 1000), peak }, entry));
  count++;
}

rmSync(WAV, { recursive: true, force: true });
mkdirSync(WAV, { recursive: true });

const PITCH = [['lo', 0.0, 0.92], ['mid', 0.5, 1.0], ['hi', 1.0, 1.08]];
const LONG = { bell: 7, chime: 2, still: 1.2, gift: 1.4, creak: 1.1, doorOpen: 0.9, yawn: 1.2, scream: 0.9, shriek: 0.7, gulp: 0.4, struggle: 0.5, doorClose: 0.4, heartbeat: 0.6, whimper: 0.6, dog: 1.0 };
const KINDS = ['step', 'personStep', 'guardStep', 'doorOpen', 'doorClose', 'creak', 'scream', 'startle', 'interact', 'chime', 'heartbeat', 'feed', 'gulp', 'struggle', 'clatter', 'scuffle', 'gasp', 'miss', 'yawn', 'shriek', 'mist', 'still', 'gift', 'overflow', 'whimper', 'dog', 'bell'];
const FOOTED = new Set(['step', 'personStep', 'guardStep']);
const PITCHED = new Set(['step', 'personStep', 'guardStep', 'doorOpen', 'creak', 'scream', 'startle', 'interact', 'gulp', 'struggle', 'clatter', 'scuffle', 'gasp', 'shriek', 'whimper', 'dog']);

for (const kind of KINDS) {
  const mats = FOOTED.has(kind) ? (kind === 'guardStep' ? ['stone', 'grass'] : ['stone', 'wood', 'grass']) : [null];
  const feet = FOOTED.has(kind) ? [0, 1] : [null];
  const pitches = PITCHED.has(kind) ? PITCH : [['mid', 0.5, 1.0]];
  for (const mat of mats) for (const foot of feet) for (const [pname, r, pitch] of pitches) {
    const key = ['play', kind, mat, foot === null ? null : 'f' + foot, pname].filter((x) => x !== null).join('_');
    const entry = { kind: 'play', name: kind, material: mat, foot, pitch, ref: PLAY_GAIN, _rand: kind === 'dog' ? [r, 0.0] : [r] };
    await bake(key, entry, LONG[kind] || 0.8, (a) => Audio.play(a, kind, { gain: PLAY_GAIN, material: mat || undefined, foot: foot === null ? undefined : foot }));
  }
}
// dog with three yips
await bake('play_dog_3yips', { kind: 'play', name: 'dog', pitch: 1, yips: 3, ref: PLAY_GAIN, _rand: [0.5, 0.99] }, 1.2, (a) => Audio.play(a, 'dog', { gain: PLAY_GAIN }));

// the click ping (3 wobble variants); peak parameter = volume x 0.35 x 1.5
for (const [pname, r] of [['lo', 0], ['mid', 0.5], ['hi', 1]]) {
  await bake('ping_' + pname, { kind: 'ping', name: 'ping', pitch: 1 + (r - 0.5) * 0.04, ref: 0.35 * 1.5, _rand: [r, 0.5] }, 0.1, (a) => Audio.ping(a));
}

// echo voices: crisp hollow tick ring soft person; plain, and rough grain variants; indoor / outdoor filter
const VOICES = ['crisp', 'hollow', 'tick', 'ring', 'soft', 'person'];
for (const voice of VOICES) {
  for (const room of ['indoor', 'outdoor']) {
    const lps = SD.acoustics ? null : null;
    for (const rough of [0, 0.45, 0.7]) {
      const key = ['echo', voice, room, rough ? 'r' + Math.round(rough * 100) : null].filter((x) => x !== null).join('_');
      const entry = { kind: 'echo', name: voice, voice, room, rough, ref: 0.35, _rand: [0.5, 0.25, 0.75, 0.4, 0.6, 0.1, 0.9] };
      await bake(key, entry, voice === 'ring' ? 0.7 : 0.3, (a) => { a.room = room; return Audio.echo(a, 0, 1, undefined, { voice, rough: rough || undefined }); });
    }
  }
}

// the plain chirp used when a ping finds no wall at all (echo without a voice)
for (const room of ['indoor', 'outdoor']) {
  await bake('echo_plain_' + room, { kind: 'echo', name: 'plain', voice: 'plain', room, rough: 0, ref: 0.35, _rand: [0.5] }, 0.3, (a) => { a.room = room; return Audio.echo(a, 0, 1, undefined, undefined); });
}

// ---- beds and body sounds (v2 bake): ambience loops, fire noise, the felt heartbeat and the breath swell ----
// A loop is rendered a second longer than needed and the tail is cross-faded onto the head so it repeats without a click.
async function bakeLoop(key, entry, seconds, fade, skip, fn) {
  const len = Math.ceil((seconds + fade + skip) * RATE);
  const ctx = new OfflineAudioContext(1, len, RATE);
  ctx.__vcsMaster = { out: ctx.destination, send: null, delays: [], fbs: [], lp: null };
  const a = { ok: true, ctx, volume: 1, warned: false, pingBip: false, room: 'indoor', rand: () => 0.5 };
  Math.random = mulberry(0xC0FFEE + count * 7919);
  fn(a);
  const rendered = await ctx.startRendering();
  const data = rendered.getChannelData(0);
  const n = Math.ceil(seconds * RATE);
  const f = Math.ceil(fade * RATE);
  const off = Math.ceil(skip * RATE);
  const out = new Float32Array(n);
  for (let i = 0; i < n; i++) out[i] = data[off + i];
  // cross-fade: out[i] (i < f) blends toward the audio that would have followed the end
  for (let i = 0; i < f; i++) {
    const k = i / f;
    out[i] = out[i] * k + data[off + n + i] * (1 - k);
  }
  let peak = 0;
  for (let i = 0; i < n; i++) peak = Math.max(peak, Math.abs(out[i]));
  const scale = PEAK_TARGET / peak;
  const file = key + '.wav';
  writeFileSync(join(WAV, file), wav16(out, scale));
  (manifest[entry.kind + ':' + entry.name] = manifest[entry.kind + ':' + entry.name] || []).push(Object.assign({ file, scale, ms: Math.round(seconds * 1000), peak, loop: true }, entry));
  count++;
}
const levelRow = (k) => (SD.levels && SD.levels[k] && SD.levels[k].gain) || 0;
const mixFor = (k) => (typeof SD.mixFor === 'function' ? SD.mixFor(k) : 1);
await bakeLoop('amb_outdoor', { kind: 'amb', name: 'outdoor', ref: levelRow('wind') * mixFor('wind') || 0.025 }, 30, 1.0, 0.5, (a) => Audio.ambience(a, { kind: 'outdoor', level01: 1 }));
await bakeLoop('amb_indoor', { kind: 'amb', name: 'indoor', ref: levelRow('room') * mixFor('room') || 0.02 }, 10, 0.0, 0.5, (a) => Audio.ambience(a, { kind: 'indoor', level01: 1 }));
await bakeLoop('fire_bed', { kind: 'fire', name: 'bed', ref: 0.035 * mixFor('fire') }, 3, 0.4, 1.5, (a) => Audio.fireBed(a, 0, 1, 0));
for (const bpm of [50, 80, 120]) {
  await bake('vheart_' + bpm, { kind: 'vheart', name: 'beat', bpm, ref: levelRow('vheart') * mixFor('vheart') || 0.06, _rand: [0.5] }, 0.7, (a) => Audio.heartbeat(a, { bpm }));
}
await bake('breath_soft', { kind: 'breath', name: 'soft', dull: false, ref: levelRow('breath') * mixFor('breath') || 0.05, _rand: [0.5] }, 1.8, (a) => Audio.breath(a, {}));
await bake('breath_dull', { kind: 'breath', name: 'dull', dull: true, ref: levelRow('breath') * mixFor('breath') || 0.05, _rand: [0.5] }, 1.8, (a) => Audio.breath(a, { occluded: true }));

// the old cartoon bip ping (pingBip setting); the echoes then use the plain chirp baked above
bakeBip = true;
for (const [pname, r] of [['lo', 0], ['mid', 0.5], ['hi', 1]]) {
  await bake('pingbip_' + pname, { kind: 'ping', name: 'bip', pitch: 1 + (r - 0.5) * 0.04, ref: 0.35, _rand: [r, 0.5] }, 0.3, (a) => Audio.ping(a));
}
bakeBip = false;

writeFileSync(join(OUT, 'manifest.json'), JSON.stringify({ rate: RATE, playGain: PLAY_GAIN, peakTarget: PEAK_TARGET, entries: manifest }, null, 1) + '\n');
console.log('baked ' + count + ' files into ' + WAV);
