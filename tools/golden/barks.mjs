#!/usr/bin/env node
// Golden fixture (barks.json): js/data/voices.js (syllable lines, subtitles, per-person voices) and js/barks.js driven by
// a real people.js simulation of the town with scripted player, fear, startle and feeding events.
// Usage: node tools/golden/barks.mjs [outPath]   (default project/tests/fixtures/barks.json)

import { createRequire } from 'node:module';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { mkdirSync, writeFileSync } from 'node:fs';

const require = createRequire(import.meta.url);
const HERE = dirname(fileURLToPath(import.meta.url));
const PORT = resolve(HERE, '..', '..');
const JS = join(PORT, 'html-version', 'js');
const OUT = process.argv[2] ? resolve(process.argv[2]) : join(PORT, 'project', 'tests', 'fixtures', 'barks.json');

for (const m of ['log', 'raycast', 'world', 'data/maps', 'data/sounds', 'sonar', 'data/voices', 'data/archetypes', 'schedule', 'forge', 'people', 'barks']) require(join(JS, m + '.js'));
const VCS = globalThis.VCS;
VCS.Log.setConsole(false);
const { World, MapData, People, Barks, VoiceData: VD } = VCS;
const clean = (v) => (v === undefined ? null : JSON.parse(JSON.stringify(v)));

// ---------------- voice data ----------------
const kinds = VD.KINDS;
const moods = [undefined, 'calm', 'whisper', 'worried', 'argue', 'call'];
const lines = [];
const seeds = [0, 1, 2, 7, 99, 12345, 4294967295, 'abc', 'Hans', ''];
for (const seed of seeds) for (const kind of kinds.concat(['bogus'])) for (const mood of moods) {
  for (const weak of [undefined, 0, 0.35, 0.7, 0.95]) {
    if (weak !== undefined && kind !== 'struggle') continue;
    const l = VD.line(seed, kind, mood, weak);
    lines.push({ seed, kind, mood: mood === undefined ? null : mood, weak: weak === undefined ? null : weak, line: clean(l), len: VD.lineLength(l) });
  }
}
const subs = [];
for (const seed of seeds.concat([5, 6, 7, 8, 9, 10, 11, 13, 17, 23])) for (const kind of Object.keys(VD.SUBS).concat(['bogus'])) for (const mood of [undefined, 'calm', 'whisper', 'worried', 'argue']) {
  for (const role of [undefined, 'guard', 'farmer', 'priest', 'zzz', 'Mother', 'regular']) {
    if (role !== undefined && kind !== 'daytalk') continue;
    subs.push({ seed, kind, mood: mood === undefined ? null : mood, role: role === undefined ? null : role, sub: clean(VD.subtitle(seed, kind, mood, role)) });
  }
  if (kind === 'struggle') for (const weak of [0, 0.31, 0.61, 0.95]) subs.push({ seed, kind, mood: null, role: null, weak, sub: clean(VD.subtitle(seed, kind, mood, undefined, weak)) });
}
const voices = [];
for (const seed of seeds) for (const role of [undefined, 'man', 'woman', 'child', 'elder', 'priest', 'guard', 'mother', 'drunk', 'qq']) voices.push({ seed, role: role === undefined ? null : role, voice: clean(VD.forPerson(seed, role)), preset: VD.presetFor(role) });
const groups = ['', 'farmer', 'barkeep', 'Monk', 'drunkard', 'soldier', 'undertaker', 'grandma', 'wife', 'kid', 'miller', 'xx', 'guard', 'regular', 'gravedigger'].map((r) => ({ r, g: VD.groupOf(r) }));

// ---------------- barks over a people simulation ----------------
const DT = 0.05;
function run(spec) {
  const def = MapData.maps[spec.map];
  const world = World.load(def, { requireStart: false });
  const state = People.create(world, def, { seed: spec.seed, shuffle: false });
  const st = Barks.create(spec.barkSeed);
  const ops = spec.ops.slice().sort((a, b) => a.t - b.t);
  let oi = 0;
  let pl = { player: { x: spec.player[0], y: spec.player[1] }, playerLit: 0 };
  let fear = 0;
  let restrained;
  let enabled = true;
  let t = 0;
  const log = [];
  const steps = Math.round(spec.seconds / DT);
  for (let i = 0; i < steps; i++) {
    while (oi < ops.length && ops[oi].t <= t + 1e-9) {
      const o = ops[oi++];
      if (o.op === 'player') pl = { player: { x: o.x, y: o.y }, playerLit: o.lit || 0 };
      else if (o.op === 'fear') fear = o.v;
      else if (o.op === 'react') People.react(state, o.x, o.y, 'sound', pl, o.dist);
      else if (o.op === 'grab') People.grab(state, o.id);
      else if (o.op === 'drink') People.drink(state, o.id, o.amount);
      else if (o.op === 'fed') People.markFed(state, o.id);
      else if (o.op === 'release') People.release(state, o.id, o.x, o.y);
      else if (o.op === 'restrain') restrained = o.id;
      else if (o.op === 'unrestrain') restrained = undefined;
      else if (o.op === 'enable') enabled = o.v;
    }
    People.update(state, world, DT, Object.assign({}, pl, { nightFrac: Math.min(1, t / spec.seconds), nightSec: spec.seconds, fear }));
    t += DT;
    const res = Barks.step(st, { now: t, player: pl.player, people: state.people, fear, enabled, restrained, lengthFn: (seed, kind, mood, role, weak) => VD.lineLength(VD.line(seed, kind, mood, typeof weak === 'number' ? weak : undefined)) });
    if (res.barks.length || res.stop.length) log.push({ t, barks: clean(res.barks), stop: res.stop, sub: res.barks.map((b) => Barks.subtitleFor(b)) });
  }
  return { spec: { map: spec.map, seed: spec.seed, barkSeed: spec.barkSeed, seconds: spec.seconds, player: spec.player, ops }, log, total: st.total };
}

const runs = [
  { map: 'town', seed: 5, barkSeed: 7, seconds: 240, player: [16.5, 9.5], ops: [] },
  { map: 'town', seed: 9, barkSeed: 3, seconds: 240, player: [22.5, 6.5], ops: [
    { t: 40, op: 'react', x: 24.5, y: 6.5 }, { t: 60, op: 'fear', v: 3 }, { t: 70, op: 'fear', v: 6 }, { t: 100, op: 'fear', v: 9 }, { t: 150, op: 'fear', v: 0 }
  ] },
  { map: 'town', seed: 5, barkSeed: 7, seconds: 200, player: [16.5, 9.5], ops: [
    { t: 20, op: 'grab', id: 3 }, { t: 21, op: 'restrain', id: 3 }, { t: 25, op: 'drink', id: 3, amount: 10 }, { t: 40, op: 'drink', id: 3, amount: 12 },
    { t: 60, op: 'drink', id: 3, amount: 40 }, { t: 70, op: 'unrestrain', id: 3 }, { t: 71, op: 'release', id: 3, x: 16.0, y: 9.5 },
    { t: 90, op: 'fed', id: 5 }, { t: 100, op: 'player', x: 20.5, y: 5.5 }, { t: 120, op: 'enable', v: false }, { t: 130, op: 'enable', v: true }
  ] }
];
const out = runs.map(run);
mkdirSync(dirname(OUT), { recursive: true });
writeFileSync(OUT, JSON.stringify({ dt: DT, lines, subs, voices, groups, runs: out }) + '\n');
console.log('wrote ' + OUT + ' (' + lines.length + ' lines, ' + subs.length + ' subs, ' + voices.length + ' voices; barks per run: ' + out.map((r) => r.log.length + '/' + r.total).join(', ') + ')');
