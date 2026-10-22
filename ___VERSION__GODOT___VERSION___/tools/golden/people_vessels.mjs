#!/usr/bin/env node
// Golden fixture (people_vessels.json): js/people.js with the whole-body pulse flag ON (VCS.Flags stub returns true for
// vis.vessels, js/data/vessels.js loaded): heartbeat echoes carry the circulatory snapshot (bpm, stateK, periphK, headK), the
// beat that lands exactly on the next tPrev is counted, and a heartbeat echo lives until its vessel wave has faded.
// Each run records the echo list (with the snapshot fields) every 0.25 s.
// Usage: node tools/golden/people_vessels.mjs [outPath]   (default project/tests/fixtures/people_vessels.json)

import { createRequire } from 'node:module';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { mkdirSync, writeFileSync } from 'node:fs';

const require = createRequire(import.meta.url);
const HERE = dirname(fileURLToPath(import.meta.url));
const PORT = resolve(HERE, '..', '..');
const JS = join(resolve(PORT, '..'), 'js');
const OUT = process.argv[2] ? resolve(process.argv[2]) : join(PORT, 'project', 'tests', 'fixtures', 'people_vessels.json');

for (const m of ['log', 'raycast', 'world', 'data/maps', 'data/sounds', 'sonar', 'data/vessels', 'people']) require(join(JS, m + '.js'));
const VCS = globalThis.VCS;
VCS.Log.setConsole(false);
VCS.Flags = { get: (id) => id === 'vis.vessels' };
const { World, MapData, Sonar, People } = VCS;
const DT = 0.05;

const echoOut = (e) => [e.personId, e.kind, e.x, e.y, e.t, e.dist, e.strength, e.zMin, e.zMax, e.fade, e.bpm === undefined ? null : e.bpm, e.stateK === undefined ? null : e.stateK, e.periphK === undefined ? null : e.periphK, e.headK === undefined ? null : e.headK];

function run(spec) {
  const def = MapData.maps[spec.map];
  const world = World.load(def, { requireStart: false });
  const state = People.create(world, def, { seed: spec.seed });
  const sonar = Sonar.create({});
  const snaps = [];
  let t = 0;
  const steps = Math.round(spec.seconds / DT);
  const beats = spec.beats.slice();
  let next = 0.25;
  for (let i = 0; i < steps; i++) {
    // heartbeats are emitted after the people pass of the previous frame, like game.js stepHeartbeats
    for (const b of beats.filter((x) => x.t <= t + 1e-9 && !x.done)) {
      b.done = true;
      const p = state.people[b.id];
      p.heartBpm = b.bpm; p.heartStateK = b.stateK; p.heartPeriphK = b.periphK; p.heartHeadK = b.headK;
      Sonar.emitSound(sonar, world, p.x, p.y, t, { kind: 'vheart', z: 0.65, range: b.range, strength: b.strength, bounces: 0 });
    }
    People.update(state, world, DT, null);
    const tPrev = t;
    t += DT;
    People.updateEchoes(state, sonar, tPrev, t);
    Sonar.prune(sonar, t);
    if (t >= next - 1e-9) {
      next += 0.25;
      snaps.push({ t, echoes: state.echoes.map(echoOut) });
    }
  }
  return { spec: { map: spec.map, seed: spec.seed, seconds: spec.seconds, beats: spec.beats.map((b) => ({ t: b.t, id: b.id, bpm: b.bpm, stateK: b.stateK, periphK: b.periphK, headK: b.headK, range: b.range, strength: b.strength })) }, snaps };
}

const mk = (t, id, bpm, k, range = 6, strength = 0.8) => ({ t, id, bpm, stateK: k, periphK: k * 0.8, headK: 1.1, range, strength });
const runs = [
  { map: 'test', seed: 1, seconds: 14, beats: [mk(1, 0, 65, 1), mk(2, 0, 65, 1), mk(3, 1, 130, 1.5), mk(3.46, 1, 130, 1.5), mk(4, 2, 90, 1.15), mk(6, 0, 170, 0.6), mk(8, 1, 52, 0.8), mk(8.5, 1, 52, 0.8)] },
  { map: 'test', seed: 42, seconds: 12, beats: [0, 1, 2].flatMap((id) => [1, 2, 3, 4].map((k) => mk(k + id * 0.13, id, 65 + id * 30, 1, 20, 1))) },
  { map: 'town', seed: 5, seconds: 10, beats: [0, 1, 2, 3, 4].flatMap((id) => [0.5, 1.5, 2.5].map((k) => mk(k + id * 0.07, id, 80 + id * 10, 0.9, 20, 1))) }
];
const out = runs.map(run);
mkdirSync(dirname(OUT), { recursive: true });
writeFileSync(OUT, JSON.stringify({ dt: DT, runs: out }) + '\n');
console.log('wrote ' + OUT + ' ' + out.map((r) => r.snaps.reduce((a, s) => a + s.echoes.filter((e) => e[1] === 'vheart').length, 0) + ' vheart samples').join(', '));
