#!/usr/bin/env node
// Golden fixture (people_sched.json): people.js with Forge and Schedule loaded: archetype-generated villagers, night
// schedules, routed trips, conversations, spawn/despawn/alter. Each run steps the sonar clock, people.update and updateEchoes together and records
// a snapshot every second: per person state tuples, the echo list, and the drained events.
// Usage: node tools/golden/people.mjs [outPath]   (default project/tests/fixtures/people.json)
// Deterministic: no clock, no randomness beyond the seeded streams.

import { createRequire } from 'node:module';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { mkdirSync, writeFileSync } from 'node:fs';

const require = createRequire(import.meta.url);
const HERE = dirname(fileURLToPath(import.meta.url));
const PORT = resolve(HERE, '..', '..');
const JS = join(PORT, 'html-version', 'js');
const OUT = process.argv[2] ? resolve(process.argv[2]) : join(PORT, 'project', 'tests', 'fixtures', 'people_sched.json');

for (const m of ['log', 'raycast', 'world', 'data/maps', 'data/sounds', 'sonar', 'data/voices', 'data/archetypes', 'schedule', 'forge', 'people']) require(join(JS, m + '.js'));
const VCS = globalThis.VCS;
VCS.Log.setConsole(false);
const { World, MapData, Sonar, People } = VCS;
VCS.Forge.reset && VCS.Forge.reset();

const DT = 0.05;

const personOut = (p) => [p.x, p.y, p.angle, p.idx, p.state, p.idleLeft, p.lookAngle, p.phase, p.steps, p.walked, p.mode,
  p.left, p.wary, p.calmLeft, p.modeLeft, p.fdir, p.blockCount, p.route ? p.route.length : -1, p.ret ? p.ret.length : -1, p.ri, p.ri2, p.sched ? p.sched.si : -2, p.sched ? p.sched.target : -2, p.sched ? (p.sched.en ? 1 : 0) : -2, p.seated ? 1 : 0, p.chat ? p.chat.partner : -1, p.chat ? p.chat.kind : '', p.role, p.archetype];
const echoOut = (e) => [e.personId, e.kind, e.x, e.y, e.angle, e.t, e.dist, e.strength, e.zMin, e.zMax, e.fade, e.mode, e.theta, e.lookAngle, e.phase];

function run(spec) {
  const def = MapData.maps[spec.map];
  const world = World.load(def, { requireStart: false });
  const state = People.create(world, def, { seed: spec.seed, shuffle: !!spec.shuffle });
  const sonar = Sonar.create({});
  const ops = spec.ops.slice().sort((a, b) => a.t - b.t);
  let oi = 0;
  let ctx = null;
  let pl = null;
  let fear = 0;
  let t = 0;
  const snaps = [];
  const steps = Math.round(spec.seconds / DT);
  const looks = state.people.map((p) => p.look);
  let nextSnap = 1;
  for (let i = 0; i < steps; i++) {
    while (oi < ops.length && ops[oi].t <= t + 1e-9) {
      const o = ops[oi++];
      if (o.op === 'player') pl = { player: { x: o.x, y: o.y }, playerLit: o.lit };
      else if (o.op === 'noplayer') pl = null;
      else if (o.op === 'fear') fear = o.v;
      else if (o.op === 'spawn') o.res = People.spawn(state, world, o.spec, o.at);
      else if (o.op === 'despawn') o.res = People.despawn(state, o.id);
      else if (o.op === 'alter') o.res = People.alter(state, o.id, o.patch);
      else if (o.op === 'react') People.react(state, o.x, o.y, 'sound', ctx, o.dist);
      else if (o.op === 'ping') Sonar.emit(sonar, world, o.x, o.y, t, { facing: o.facing });
      else if (o.op === 'grab') o.res = People.grab(state, o.id);
      else if (o.op === 'release') o.res = People.release(state, o.id, o.x, o.y);
      else if (o.op === 'drink') o.res = People.drink(state, o.id, o.amount);
      else if (o.op === 'fed') o.res = People.markFed(state, o.id);
      else if (o.op === 'target') { const f = People.feedTarget(state, o.x, o.y, o.angle, o.reach, o.arc); o.res = f ? f.id : -1; }
    }
    ctx = Object.assign({}, pl || {}, { nightFrac: Math.min(1, t / spec.seconds), nightSec: spec.seconds, fear });
    People.update(state, world, DT, ctx);
    const tPrev = t;
    t += DT;
    People.updateEchoes(state, sonar, tPrev, t);
    Sonar.prune(sonar, t);
    if (t >= nextSnap - 1e-9) {
      nextSnap++;
      const ev = People.drainEvents(state);
      snaps.push({ t, people: state.people.map(personOut), echoes: state.echoes.map(echoOut), events: ev.map((e) => [e.type, e.id, e.x, e.y]), steps: People.stepEvents(state, tPrev, t, []) });
    }
  }
  return { forge: JSON.parse(JSON.stringify(People.forgeState(state))), spec: { map: spec.map, seed: spec.seed, shuffle: !!spec.shuffle, seconds: spec.seconds, ops }, looks, snaps };
}

const runs = [
  // A: the town, full night, nobody around: trips between places, conversations, seating.
  { map: 'town', seed: 5, seconds: 300, ops: [] },
  { map: 'town', seed: 11, seconds: 300, ops: [] },
  // B: the village gets afraid at 300 s (everyone but the watch heads home), a scream-worthy player shows up.
  { map: 'town', seed: 5, seconds: 320, ops: [
    { t: 100, op: 'player', x: 16.5, y: 9.5, lit: 0.7 }, { t: 110, op: 'noplayer' },
    { t: 150, op: 'react', x: 20.5, y: 5.5 }, { t: 200, op: 'fear', v: 2 }, { t: 250, op: 'fear', v: 9 }, { t: 300, op: 'fear', v: 0 }
  ] },
  // C: spawn, alter and despawn.
  { map: 'town', seed: 3, seconds: 200, ops: [
    { t: 10, op: 'spawn', spec: { archetype: 'guard', seed: 77 }, at: { x: 16.5, y: 10.5 } },
    { t: 20, op: 'spawn', spec: { archetype: 'drunk', seed: 5, home: 'house1' }, at: { x: 20.5, y: 5.5 } },
    { t: 30, op: 'spawn', spec: { archetype: 'nope' }, at: { x: 20.5, y: 5.5 } },
    { t: 40, op: 'spawn', spec: { archetype: 'patron' }, at: { x: 0.5, y: 0.5 } },
    { t: 50, op: 'alter', id: 1, patch: { acc: 'tophat', height: 1.2 } },
    { t: 60, op: 'alter', id: 1, patch: { evil: 1 } },
    { t: 70, op: 'despawn', id: 0 },
    { t: 80, op: 'despawn', id: 99 }
  ] }
];

const out = runs.map(run);
mkdirSync(dirname(OUT), { recursive: true });
writeFileSync(OUT, JSON.stringify({ dt: DT, runs: out }) + '\n');
console.log('wrote ' + OUT + ' (' + out.map((r) => r.spec.map + ' seed ' + r.spec.seed + ': ' + r.snaps.length + ' snaps, ' + r.looks.length + ' people').join('; ') + ')');
