#!/usr/bin/env node
// Golden fixture: scripted people simulations from the real js/people.js (Forge and Schedule NOT loaded, which is the
// Phase 1 scope of core/people.gd). Each run steps the sonar clock, people.update and updateEchoes together and records
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
const JS = join(resolve(PORT, '..'), 'js');
const OUT = process.argv[2] ? resolve(process.argv[2]) : join(PORT, 'project', 'tests', 'fixtures', 'people.json');

for (const m of ['log', 'raycast', 'world', 'data/maps', 'data/sounds', 'sonar', 'people']) require(join(JS, m + '.js'));
const VCS = globalThis.VCS;
VCS.Log.setConsole(false);
if (VCS.Forge || VCS.Schedule) throw new Error('Forge/Schedule must not be loaded for this fixture');
const { World, MapData, Sonar, People } = VCS;

const DT = 0.05;

const personOut = (p) => [p.x, p.y, p.angle, p.idx, p.state, p.idleLeft, p.lookAngle, p.phase, p.steps, p.walked, p.mode,
  p.left, p.wary, p.calmLeft, p.modeLeft, p.fdir, p.blockCount, p.route ? p.route.length : -1, p.ret ? p.ret.length : -1, p.ri, p.ri2];
const echoOut = (e) => [e.personId, e.kind, e.x, e.y, e.angle, e.t, e.dist, e.strength, e.zMin, e.zMax, e.fade, e.mode, e.theta, e.lookAngle, e.phase];

function run(spec) {
  const def = MapData.maps[spec.map];
  const world = World.load(def, { requireStart: false });
  const state = People.create(world, def, { seed: spec.seed, shuffle: !!spec.shuffle });
  const sonar = Sonar.create({});
  const ops = spec.ops.slice().sort((a, b) => a.t - b.t);
  let oi = 0;
  let ctx = null;
  let t = 0;
  const snaps = [];
  const steps = Math.round(spec.seconds / DT);
  const looks = state.people.map((p) => p.look);
  let nextSnap = 1;
  for (let i = 0; i < steps; i++) {
    while (oi < ops.length && ops[oi].t <= t + 1e-9) {
      const o = ops[oi++];
      if (o.op === 'player') ctx = { player: { x: o.x, y: o.y }, playerLit: o.lit };
      else if (o.op === 'noplayer') ctx = null;
      else if (o.op === 'react') People.react(state, o.x, o.y, 'sound', ctx, o.dist);
      else if (o.op === 'ping') Sonar.emit(sonar, world, o.x, o.y, t, { facing: o.facing });
      else if (o.op === 'grab') o.res = People.grab(state, o.id);
      else if (o.op === 'release') o.res = People.release(state, o.id, o.x, o.y);
      else if (o.op === 'drink') o.res = People.drink(state, o.id, o.amount);
      else if (o.op === 'fed') o.res = People.markFed(state, o.id);
      else if (o.op === 'target') { const f = People.feedTarget(state, o.x, o.y, o.angle, o.reach, o.arc); o.res = f ? f.id : -1; }
    }
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
  return { spec: { map: spec.map, seed: spec.seed, shuffle: !!spec.shuffle, seconds: spec.seconds, ops }, looks, snaps };
}

const runs = [
  // A: three patrolling patrons, nobody around, ten minutes.
  { map: 'test', seed: 1, seconds: 600, ops: [] },
  { map: 'test', seed: 42, seconds: 120, shuffle: true, ops: [] },
  // B: pings and a lit player appearing near walkers, sounds that startle, then calm.
  {
    map: 'test', seed: 7, seconds: 150, ops: [
      { t: 5, op: 'ping', x: 12.5, y: 2.5, facing: 0.2 },
      { t: 12, op: 'ping', x: 14.5, y: 7.5, facing: 3.0 },
      { t: 20, op: 'player', x: 14.5, y: 2.5, lit: 0.6 },
      { t: 24, op: 'noplayer' },
      { t: 30, op: 'react', x: 17.0, y: 3.0 },
      { t: 31, op: 'ping', x: 17.5, y: 3.5, facing: 1.0 },
      { t: 45, op: 'player', x: 8.0, y: 7.5, lit: 0.1 },
      { t: 47, op: 'player', x: 8.0, y: 7.5, lit: 0.8 },
      { t: 60, op: 'noplayer' },
      { t: 90, op: 'react', x: 11.5, y: 2.5, dist: 5 },
      { t: 95, op: 'ping', x: 12.0, y: 3.0, facing: 5.0 }
    ]
  },
  // C: feeding hooks: target, grab, drink, release (dazed then quiet flee), second victim marked fed.
  {
    map: 'test', seed: 3, seconds: 90, ops: [
      { t: 4, op: 'target', x: 16.5, y: 1.5, angle: 0, reach: 2.5, arc: 1.2 },
      { t: 6, op: 'grab', id: 0 },
      { t: 7, op: 'drink', id: 0, amount: 4 },
      { t: 9, op: 'drink', id: 0, amount: 200 },
      { t: 10, op: 'release', id: 0, x: 15.0, y: 1.5 },
      { t: 20, op: 'fed', id: 1 },
      { t: 21, op: 'grab', id: 1 },
      { t: 25, op: 'release', id: 2, x: 0, y: 0 },
      { t: 40, op: 'player', x: 12.0, y: 2.5, lit: 0.9 },
      { t: 70, op: 'noplayer' }
    ]
  },
  // D: the town has lights and hide spots: flight prefers lit refuges.
  {
    map: 'town', seed: 5, seconds: 120, ops: [
      { t: 3, op: 'ping', x: 16.5, y: 10.5, facing: 0 },
      { t: 15, op: 'player', x: 16.5, y: 9.5, lit: 0.7 },
      { t: 30, op: 'noplayer' },
      { t: 45, op: 'react', x: 28.5, y: 4.5 },
      { t: 50, op: 'player', x: 24.5, y: 6.5, lit: 0.9 },
      { t: 70, op: 'noplayer' }
    ]
  }
];

const out = runs.map(run);
mkdirSync(dirname(OUT), { recursive: true });
writeFileSync(OUT, JSON.stringify({ dt: DT, runs: out }) + '\n');
console.log('wrote ' + OUT + ' (' + out.map((r) => r.spec.map + ' seed ' + r.spec.seed + ': ' + r.snaps.length + ' snaps, ' + r.looks.length + ' people').join('; ') + ')');
