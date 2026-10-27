#!/usr/bin/env node
// Bakes the procedural sounds of the roguelike mode ("rg_*") with node-web-audio-api. Deterministic (seeded noise).
// Usage: node tools/bake-rogue-audio.mjs        (needs `npm install` in tools/)
// Output: project/audio/rogue/*.wav (mono, 44.1 kHz, 16 bit, peak-normalised to 0.9; the four ambience beds to 0.35) and project/data/rogue/sounds_rogue.json.
// Kept apart from project/audio/wav/ on purpose: tools/bake-audio.mjs wipes that folder when it runs.
// Manifest entry: {id, file, loop, ms, gain, bus, use}. `gain` = suggested linear play gain (samples are normalised to 0.9).
// Loops are cross-faded head/tail like bake-audio.mjs, so set AudioStreamWAV.loop_mode = LOOP_FORWARD (loop_end = bytes / 2) in code.
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { mkdirSync, writeFileSync, rmSync, readdirSync } from 'node:fs';
import { OfflineAudioContext } from 'node-web-audio-api';

const PORT = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const OUT = join(PORT, 'project', 'audio', 'rogue');
const MANIFEST = join(PORT, 'project', 'data', 'rogue', 'sounds_rogue.json');
const RATE = 44100;
const PEAK = 0.9;
const LOOP_PEAK = 0.35; // ambience beds (wind/creek/fountain/cricket) sit quietly under the one-shots
const WIND_PEAK = 0.28; // cave-mouth wind bed: quieter than the other beds (user playtest)

function mulberry(seed) {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6D2B79F5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

function wav16(samples) {
  const n = samples.length;
  const buf = Buffer.alloc(44 + n * 2);
  buf.write('RIFF', 0); buf.writeUInt32LE(36 + n * 2, 4); buf.write('WAVE', 8); buf.write('fmt ', 12);
  buf.writeUInt32LE(16, 16); buf.writeUInt16LE(1, 20); buf.writeUInt16LE(1, 22); buf.writeUInt32LE(RATE, 24);
  buf.writeUInt32LE(RATE * 2, 28); buf.writeUInt16LE(2, 32); buf.writeUInt16LE(16, 34); buf.write('data', 36); buf.writeUInt32LE(n * 2, 40);
  for (let i = 0; i < n; i++) buf.writeInt16LE(Math.max(-32768, Math.min(32767, Math.round(samples[i] * 32767))), 44 + i * 2);
  return buf;
}

// ---- synth toolkit (all take a ctx `c` and a seeded rng `r`) ----
const noiseBuf = (c, r, secs) => {
  const b = c.createBuffer(1, Math.ceil(secs * RATE), RATE);
  const d = b.getChannelData(0);
  for (let i = 0; i < d.length; i++) d[i] = r() * 2 - 1;
  return b;
};
function env(param, t, a, peak, dur) {
  param.setValueAtTime(0.0001, t);
  param.linearRampToValueAtTime(peak, t + Math.max(a, 0.001));
  param.exponentialRampToValueAtTime(0.0001, t + dur);
}
// oscillator with pitch glide f0 -> f1 and a percussive envelope; optional filter {type,f,q}; optional AM {hz,depth}; vib {hz,cents}
function tone(c, o) {
  const { t = 0, dur = 0.2, f0 = 440, f1 = f0, type = 'sine', gain = 0.5, a = 0.005, filt, am, vib, glideEnd } = o;
  const osc = c.createOscillator(); osc.type = type;
  osc.frequency.setValueAtTime(f0, t);
  if (f1 !== f0) osc.frequency.exponentialRampToValueAtTime(f1, t + (glideEnd ?? dur));
  const g = c.createGain(); env(g.gain, t, a, gain, dur);
  let node = osc;
  if (filt) { const f = c.createBiquadFilter(); f.type = filt.type; f.frequency.value = filt.f; f.Q.value = filt.q ?? 1; node.connect(f); node = f; }
  node.connect(g);
  if (am) { const l = c.createOscillator(); l.frequency.value = am.hz; const lg = c.createGain(); lg.gain.value = am.depth * gain; l.connect(lg); lg.connect(g.gain); l.start(t); l.stop(t + dur + 0.05); }
  if (vib) { const l = c.createOscillator(); l.frequency.value = vib.hz; const lg = c.createGain(); lg.gain.value = vib.cents; l.connect(lg); lg.connect(osc.detune); l.start(t); l.stop(t + dur + 0.05); }
  g.connect(c.destination);
  osc.start(t); osc.stop(t + dur + 0.05);
}
// filtered noise burst; filter freq glides f0 -> f1
function noise(c, r, o) {
  const { t = 0, dur = 0.1, gain = 0.5, a = 0.002, type = 'bandpass', f0 = 1000, f1 = f0, q = 1, hold = false } = o;
  const s = c.createBufferSource(); s.buffer = noiseBuf(c, r, dur + 0.05);
  const f = c.createBiquadFilter(); f.type = type; f.Q.value = q;
  f.frequency.setValueAtTime(f0, t);
  if (f1 !== f0) f.frequency.exponentialRampToValueAtTime(f1, t + dur);
  const g = c.createGain();
  if (hold) { g.gain.setValueAtTime(0.0001, t); g.gain.linearRampToValueAtTime(gain, t + a); g.gain.setValueAtTime(gain, t + dur - a); g.gain.linearRampToValueAtTime(0.0001, t + dur); }
  else env(g.gain, t, a, gain, dur);
  s.connect(f); f.connect(g); g.connect(c.destination);
  s.start(t); s.stop(t + dur + 0.05);
}
// steady noise bed whose filter and level are modulated by slow LFOs (wind, creek, fountain)
function bed(c, r, o) {
  const { secs, type = 'bandpass', f = 600, q = 0.7, gain = 0.3, lfoHz = 0.3, fDepth = 250, gDepth = 0.5 } = o;
  const s = c.createBufferSource(); s.buffer = noiseBuf(c, r, secs); s.loop = true;
  const fl = c.createBiquadFilter(); fl.type = type; fl.frequency.value = f; fl.Q.value = q;
  const g = c.createGain(); g.gain.value = gain;
  const l1 = c.createOscillator(); l1.frequency.value = lfoHz; const d1 = c.createGain(); d1.gain.value = fDepth; l1.connect(d1); d1.connect(fl.frequency);
  const l2 = c.createOscillator(); l2.frequency.value = lfoHz * 0.63; const d2 = c.createGain(); d2.gain.value = gain * gDepth; l2.connect(d2); d2.connect(g.gain);
  s.connect(fl); fl.connect(g); g.connect(c.destination);
  s.start(0); l1.start(0); l2.start(0);
}
const bellPartials = [[1, 1, 1], [2.0, 0.6, 0.7], [2.76, 0.5, 0.55], [5.4, 0.3, 0.35], [8.93, 0.15, 0.2]];
function bell(c, o) { // inharmonic partial bell: [ratio, amp, decayScale]
  const { t = 0, f = 220, dur = 3, gain = 0.4 } = o;
  for (const [ra, am, ds] of bellPartials) tone(c, { t, f0: f * ra, dur: dur * ds, gain: gain * am, a: 0.003 });
  noise(c, mulberry(7), { t, dur: 0.04, gain: gain * 0.5, type: 'highpass', f0: 2500 });
}

// ---- the sound table: id -> {secs, loop?, gain, use, build(c, r)} ----
const S = [];
const def = (id, secs, gain, use, build, loop = null) => S.push({ id, secs, gain, use, build, loop });

// water
def('rg_drip_cave', 0.9, 0.5, 'drip anchor in caves / large chambers (sparse, resonant)', (c, r) => {
  tone(c, { f0: 2100, f1: 1100, dur: 0.07, gain: 0.5, a: 0.001 });
  tone(c, { t: 0.0, f0: 1400, f1: 1000, dur: 0.45, gain: 0.12, a: 0.004 });
  tone(c, { t: 0.21, f0: 2000, f1: 1050, dur: 0.07, gain: 0.16, a: 0.001 });
  tone(c, { t: 0.43, f0: 1900, f1: 1000, dur: 0.07, gain: 0.07, a: 0.001 });
});
def('rg_drip_pool', 0.5, 0.5, 'drip falling into a pool / still water tile (bubbly plop)', (c, r) => {
  tone(c, { f0: 380, f1: 900, dur: 0.12, glideEnd: 0.09, gain: 0.6, a: 0.002 });
  tone(c, { t: 0.0, f0: 190, f1: 420, dur: 0.14, gain: 0.25, a: 0.002 });
  noise(c, r, { dur: 0.03, gain: 0.15, type: 'bandpass', f0: 3000, q: 1.5 });
});
def('rg_drip_gutter', 0.4, 0.45, 'drip on stone / roof gutter in towns and ruins (bright tick)', (c, r) => {
  noise(c, r, { dur: 0.012, gain: 0.5, type: 'highpass', f0: 3500 });
  tone(c, { f0: 3000, f1: 2300, dur: 0.05, gain: 0.35, a: 0.001 });
  tone(c, { t: 0.14, f0: 2900, f1: 2200, dur: 0.04, gain: 0.12, a: 0.001 });
});
def('rg_splash_step_a', 0.55, 0.5, 'footstep through shallow water (alternate with _b by foot)', (c, r) => {
  noise(c, r, { dur: 0.3, gain: 0.5, a: 0.02, f0: 700, f1: 2400, q: 0.9 });
  tone(c, { t: 0.05, f0: 300, f1: 800, dur: 0.1, gain: 0.25, a: 0.002 });
  tone(c, { t: 0.2, f0: 450, f1: 1100, dur: 0.07, gain: 0.12, a: 0.002 });
});
def('rg_splash_step_b', 0.55, 0.5, 'footstep through shallow water (second foot, deeper ripple)', (c, r) => {
  noise(c, r, { dur: 0.35, gain: 0.5, a: 0.025, f0: 500, f1: 1800, q: 0.8 });
  tone(c, { t: 0.04, f0: 240, f1: 650, dur: 0.12, gain: 0.3, a: 0.002 });
  tone(c, { t: 0.25, f0: 520, f1: 1300, dur: 0.06, gain: 0.1, a: 0.002 });
});
// critters
def('rg_bat_squeak', 0.3, 0.4, 'bat critter squeak (high, short; use with a short-range emit)', (c, r) => {
  tone(c, { f0: 5200, f1: 9000, dur: 0.07, gain: 0.5, a: 0.003 });
  tone(c, { t: 0.1, f0: 8200, f1: 5600, dur: 0.08, gain: 0.35, a: 0.003 });
});
def('rg_bat_flutter', 0.6, 0.45, 'bat wings: fly-by / flush from roost', (c, r) => {
  noise(c, r, { dur: 0.55, gain: 0.3, a: 0.05, f0: 700, f1: 500, q: 0.8 });
  for (let i = 0; i < 9; i++) noise(c, r, { t: 0.03 + i * 0.058, dur: 0.045, gain: 0.55 * (1 - i * 0.07), a: 0.006, f0: 900 - i * 30, q: 1.2 });
});
def('rg_rat_skitter', 0.7, 0.4, 'rat critter moving (claw ticks); one-shot per scurry', (c, r) => {
  for (let i = 0; i < 14; i++) noise(c, r, { t: i * 0.045 + r() * 0.01, dur: 0.012, gain: 0.35 + r() * 0.3, type: 'highpass', f0: 2500 + r() * 2000, q: 1 });
});
def('rg_rat_squeak', 0.3, 0.4, 'rat critter squeak when startled / fed on', (c, r) => {
  tone(c, { f0: 2600, f1: 3500, dur: 0.1, gain: 0.45, a: 0.004, type: 'sawtooth', filt: { type: 'bandpass', f: 3000, q: 2 }, vib: { hz: 40, cents: 60 } });
  tone(c, { t: 0.12, f0: 3300, f1: 2400, dur: 0.09, gain: 0.35, a: 0.004, type: 'sawtooth', filt: { type: 'bandpass', f: 3000, q: 2 } });
});
def('rg_hare_thump', 0.35, 0.6, 'hare/rabbit alarm foot-thump (low; carries through ground, good for sonar)', (c, r) => {
  tone(c, { f0: 110, f1: 48, dur: 0.18, gain: 0.8, a: 0.002 });
  noise(c, r, { dur: 0.05, gain: 0.3, type: 'lowpass', f0: 400 });
  tone(c, { t: 0.14, f0: 100, f1: 46, dur: 0.15, gain: 0.5, a: 0.002 });
});
def('rg_owl_hoot', 1.4, 0.5, 'owl at night in woods / ruins (hoo, hoo-hooo)', (c, r) => {
  const hoot = (t, f, dur, g) => {
    tone(c, { t, f0: f * 1.06, f1: f, dur, glideEnd: 0.06, gain: g, a: 0.05 });
    tone(c, { t, f0: f * 2.1, f1: f * 2, dur: dur * 0.7, gain: g * 0.18, a: 0.05 });
  };
  hoot(0.0, 400, 0.3, 0.5); hoot(0.5, 390, 0.25, 0.4); hoot(0.8, 370, 0.5, 0.55);
});
def('rg_wolf_howl', 3.2, 0.5, 'wolf howl (distant; plains/forest at night, heat/danger cue)', (c, r) => {
  const dur = 3.0;
  const osc = c.createOscillator(); osc.type = 'sawtooth';
  osc.frequency.setValueAtTime(260, 0.1);
  osc.frequency.linearRampToValueAtTime(520, 1.0); osc.frequency.linearRampToValueAtTime(540, 1.7); osc.frequency.linearRampToValueAtTime(330, 3.0);
  const lf = c.createBiquadFilter(); lf.type = 'lowpass'; lf.frequency.value = 1400; lf.Q.value = 2;
  const g = c.createGain(); env(g.gain, 0.1, 0.5, 0.45, dur);
  const vib = c.createOscillator(); vib.frequency.value = 5.2; const vg = c.createGain(); vg.gain.value = 18; vib.connect(vg); vg.connect(osc.detune);
  osc.connect(lf); lf.connect(g); g.connect(c.destination);
  osc.start(0.1); osc.stop(dur + 0.2); vib.start(0); vib.stop(dur + 0.2);
  noise(c, r, { t: 0.2, dur: 2.6, gain: 0.05, a: 0.5, f0: 1200, q: 3 });
});
def('rg_crow_caw', 0.7, 0.5, 'crow caw (daytime/dawn outdoors; startled flee)', (c, r) => {
  for (const t of [0.0, 0.3]) {
    tone(c, { t, f0: 780, f1: 520, dur: 0.22, gain: 0.5, a: 0.01, type: 'sawtooth', filt: { type: 'bandpass', f: 1100, q: 1.5 }, am: { hz: 85, depth: 0.5 } });
    noise(c, r, { t, dur: 0.2, gain: 0.12, f0: 1500, q: 1 });
  }
});
def('rg_sheep_bleat', 1.0, 0.5, 'sheep bleat (pasture/farm)', (c, r) => {
  tone(c, { f0: 340, f1: 300, dur: 0.8, glideEnd: 0.8, gain: 0.5, a: 0.06, type: 'sawtooth', filt: { type: 'bandpass', f: 900, q: 2.5 }, am: { hz: 26, depth: 0.55 }, vib: { hz: 7, cents: 80 } });
});
def('rg_hen_cluck', 0.6, 0.45, 'hen cluck (farm yard)', (c, r) => {
  for (const [t, f] of [[0.0, 520], [0.14, 480], [0.31, 540]]) tone(c, { t, f0: f, f1: f * 0.7, dur: 0.08, gain: 0.5, a: 0.004, type: 'square', filt: { type: 'bandpass', f: 1000, q: 3 } });
});
// ambience loops
def('rg_cricket_loop', 2.1, 0.5, 'night insect bed, meadows/roads/farm (loop)', (c, r) => {
  for (let t = 0.05; t < 3.2; t += 0.7) for (let k = 0; k < 3; k++) tone(c, { t: t + k * 0.075, f0: 4500, f1: 4500, dur: 0.05, gain: 0.35, a: 0.01, am: { hz: 180, depth: 0.5 } });
  for (let t = 0.4; t < 3.2; t += 1.05) for (let k = 0; k < 2; k++) tone(c, { t: t + k * 0.08, f0: 5100, f1: 5100, dur: 0.045, gain: 0.18, a: 0.01 });
}, { fade: 0.5, skip: 0.2, peak: LOOP_PEAK });
def('rg_wind_loop', 5, 0.5, 'wind gust / draft bed (loop); scale gain with openness or draft strength', (c, r) => {
  bed(c, r, { secs: 7, f: 550, q: 0.8, gain: 0.5, lfoHz: 0.23, fDepth: 300, gDepth: 0.7 });
  bed(c, r, { secs: 7, f: 1500, q: 1.5, gain: 0.12, lfoHz: 0.37, fDepth: 500, gDepth: 0.8 });
}, { fade: 1.0, skip: 0.5, peak: WIND_PEAK });
def('rg_creek_loop', 3, 0.5, 'creek / stream bed (loop); positional on stream tiles', (c, r) => {
  bed(c, r, { secs: 5, f: 1400, q: 0.5, gain: 0.35, lfoHz: 0.9, fDepth: 500, gDepth: 0.3 });
  for (let i = 0; i < 70; i++) { const f = 500 + r() * 1500; tone(c, { t: 0.3 + r() * 3.6, f0: f, f1: f * 1.8, dur: 0.05 + r() * 0.05, gain: 0.05 + r() * 0.07, a: 0.003 }); }
}, { fade: 0.6, skip: 0.3, peak: LOOP_PEAK });
def('rg_fountain_loop', 3, 0.5, 'town fountain bed (loop); brighter and steadier than the creek', (c, r) => {
  bed(c, r, { secs: 5, type: 'highpass', f: 2200, q: 0.4, gain: 0.22, lfoHz: 1.3, fDepth: 300, gDepth: 0.2 });
  bed(c, r, { secs: 5, f: 900, q: 0.7, gain: 0.18, lfoHz: 0.5, fDepth: 200, gDepth: 0.3 });
  for (let i = 0; i < 90; i++) { const f = 900 + r() * 1800; tone(c, { t: 0.3 + r() * 3.6, f0: f, f1: f * 1.6, dur: 0.04 + r() * 0.04, gain: 0.04 + r() * 0.06, a: 0.002 }); }
}, { fade: 0.6, skip: 0.3, peak: LOOP_PEAK });
def('rg_hearth_crackle', 2.5, 0.4, 'hearth/campfire pops (loop) layered over the existing fire_bed', (c, r) => {
  noise(c, r, { dur: 3.6, gain: 0.05, hold: true, type: 'lowpass', f0: 900, q: 0.5 });
  for (let i = 0; i < 26; i++) noise(c, r, { t: 0.2 + r() * 3.2, dur: 0.008 + r() * 0.02, gain: 0.25 + r() * 0.6, type: 'bandpass', f0: 1500 + r() * 4000, q: 1.2 });
  for (let i = 0; i < 4; i++) noise(c, r, { t: 0.4 + r() * 3, dur: 0.05, gain: 0.4, type: 'lowpass', f0: 600 });
}, { fade: 0.5, skip: 0.2 });
// UI / meta
def('rg_coffin_creak', 1.6, 0.5, 'The Coffin: lid opens (title / hub), then thunk', (c, r) => {
  tone(c, { f0: 70, f1: 150, dur: 1.2, gain: 0.5, a: 0.15, type: 'sawtooth', filt: { type: 'lowpass', f: 500, q: 4 }, am: { hz: 17, depth: 0.7 }, vib: { hz: 6, cents: 120 } });
  tone(c, { t: 0.1, f0: 520, f1: 780, dur: 0.9, gain: 0.08, a: 0.1, type: 'sawtooth', filt: { type: 'bandpass', f: 900, q: 6 }, am: { hz: 23, depth: 0.8 } });
  for (let i = 0; i < 10; i++) noise(c, r, { t: 0.05 + r() * 1.1, dur: 0.01, gain: 0.25, type: 'bandpass', f0: 1200 + r() * 1500, q: 2 });
  tone(c, { t: 1.25, f0: 90, f1: 45, dur: 0.3, gain: 0.7, a: 0.003 });
  noise(c, r, { t: 1.25, dur: 0.06, gain: 0.3, type: 'lowpass', f0: 500 });
});
def('rg_soil_chime', 0.9, 0.45, 'Grave Soil gained / spent (earthy marimba-like, soft)', (c, r) => {
  tone(c, { f0: 196, f1: 190, dur: 0.5, gain: 0.5, a: 0.004 });
  tone(c, { f0: 588, f1: 585, dur: 0.18, gain: 0.25, a: 0.002 });
  tone(c, { t: 0.09, f0: 294, f1: 290, dur: 0.6, gain: 0.35, a: 0.004, type: 'triangle' });
  noise(c, r, { dur: 0.04, gain: 0.3, type: 'lowpass', f0: 350 });
});
def('rg_upgrade_sting', 1.6, 0.5, 'upgrade purchased (rising minor arpeggio over a low swell)', (c, r) => {
  [146.8, 174.6, 220, 293.7].forEach((f, i) => { tone(c, { t: i * 0.11, f0: f, dur: 0.9, gain: 0.35, a: 0.01, type: 'triangle' }); tone(c, { t: i * 0.11, f0: f * 2, dur: 0.5, gain: 0.1, a: 0.01 }); });
  tone(c, { t: 0.0, f0: 73.4, dur: 1.5, gain: 0.3, a: 0.2 });
});
def('rg_stage_arrival', 2.5, 0.5, 'stage arrival stinger (stage card): low swell and a far bell', (c, r) => {
  tone(c, { f0: 55, dur: 2.4, gain: 0.45, a: 0.6 });
  tone(c, { f0: 82.4, dur: 2.2, gain: 0.3, a: 0.7, type: 'triangle' });
  bell(c, { t: 0.6, f: 196, dur: 1.8, gain: 0.18 });
  noise(c, r, { dur: 1.2, gain: 0.08, a: 0.5, f0: 300, f1: 900, q: 0.7 });
});
def('rg_dawn_bell', 3.6, 0.5, 'dawn warning: bell tolls (play when the sky first lightens; repeat as time runs out)', (c, r) => {
  bell(c, { t: 0, f: 330, dur: 3.2, gain: 0.35 });
  bell(c, { t: 1.4, f: 330, dur: 2.0, gain: 0.25 });
});
def('rg_dawn_birds', 2.6, 0.35, 'dawn warning: birdsong layered with the bell, or alone as the last-chance cue', (c, r) => {
  for (let i = 0; i < 16; i++) { const t = r() * 2.2, f = 2800 + r() * 2200; tone(c, { t, f0: f, f1: f * (0.7 + r() * 0.8), dur: 0.05 + r() * 0.06, gain: 0.2 + r() * 0.3, a: 0.004, vib: { hz: 30, cents: 100 } }); }
});
def('rg_laid_to_rest', 4.5, 0.55, 'Laid to Rest (death) toll: two slow low bells, then silence', (c, r) => {
  bell(c, { t: 0.0, f: 110, dur: 3.6, gain: 0.5 });
  bell(c, { t: 2.1, f: 98, dur: 2.3, gain: 0.4 });
  tone(c, { t: 0, f0: 41, dur: 4.2, gain: 0.25, a: 0.3 });
});

// ---- render ----
mkdirSync(OUT, { recursive: true });
for (const f of readdirSync(OUT)) if (/^rg_.*\.wav$/.test(f)) rmSync(join(OUT, f), { force: true }); // not the whole folder: Godot keeps .import files here
const sounds = [];
let seedN = 0;
for (const s of S) {
  const fade = s.loop ? s.loop.fade : 0, skip = s.loop ? s.loop.skip : 0;
  const len = Math.ceil((s.secs + fade + skip + 0.1) * RATE);
  const c = new OfflineAudioContext(1, len, RATE);
  s.build(c, mulberry(0xB10C + 977 * ++seedN));
  const data = (await c.startRendering()).getChannelData(0);
  let out, ms;
  if (s.loop) {
    const n = Math.ceil(s.secs * RATE), f = Math.ceil(fade * RATE), off = Math.ceil(skip * RATE);
    out = new Float32Array(n);
    for (let i = 0; i < n; i++) out[i] = data[off + i];
    for (let i = 0; i < f; i++) { const k = i / f; out[i] = out[i] * k + data[off + n + i] * (1 - k); }
    ms = Math.round(s.secs * 1000);
  } else {
    let last = 0;
    for (let i = 0; i < data.length; i++) if (Math.abs(data[i]) > 1e-3) last = i;
    const end = Math.min(data.length, last + Math.ceil(0.03 * RATE));
    out = data.slice(0, end);
    const fo = Math.min(out.length, Math.ceil(0.02 * RATE)); // short fade-out so nothing ends on a click
    for (let i = 0; i < fo; i++) out[out.length - 1 - i] *= i / fo;
    ms = Math.round((end / RATE) * 1000);
  }
  let peak = 0;
  for (let i = 0; i < out.length; i++) peak = Math.max(peak, Math.abs(out[i]));
  if (peak < 1e-4) throw new Error('silent: ' + s.id);
  const k = (s.loop && s.loop.peak ? s.loop.peak : PEAK) / peak;
  for (let i = 0; i < out.length; i++) out[i] *= k;
  const file = s.id + '.wav';
  writeFileSync(join(OUT, file), wav16(out));
  sounds.push({ id: s.id, file, loop: !!s.loop, ms, gain: s.gain, bus: 'World', use: s.use });
}
writeFileSync(MANIFEST, JSON.stringify({ v: 1, rate: RATE, peakTarget: PEAK, dir: 'res://audio/rogue/', sounds }, null, 1) + '\n');
console.log('baked ' + sounds.length + ' rogue sounds into ' + OUT);
