#!/usr/bin/env node
// Golden fixture: the acoustics and sound-data functions of js/data/sounds.js evaluated over input grids.
// Usage: node tools/golden/acoustics.mjs [outPath]   (default project/tests/fixtures/acoustics.json)
// Deterministic: no clock, no randomness.

import { createRequire } from 'node:module';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { mkdirSync, writeFileSync } from 'node:fs';

const require = createRequire(import.meta.url);
const HERE = dirname(fileURLToPath(import.meta.url));
const PORT = resolve(HERE, '..', '..');
const JS = join(resolve(PORT, '..'), 'js');
const OUT = process.argv[2] ? resolve(process.argv[2]) : join(PORT, 'project', 'tests', 'fixtures', 'acoustics.json');

require(join(JS, 'data', 'sounds.js'));
const SD = globalThis.VCS.SoundData;
const A = SD.acoustics;

const mats = Object.keys(A.mat);
const dists = [0, 0.2, 0.5, 1, 2.5, 4, 7.5, 10, 16];
const thetas = [-3.2, -1.5, -0.4, 0, 0.3, 1.1, 2.4, 3.14159, 5.0];
const out = { mats, dists, thetas, beam: [], visFactor: [], echoLevel: [], gameAmp: [], personAmp: [], propAmp: [], floor: [], ceil: [], wet: [], sabine: [], t60: [], comb: [], maekawa: [], occlusion: [], repetition: [], stepScale: [] };

for (const t of thetas) { out.beam.push(A.beam(t)); out.visFactor.push(A.visFactor(A.beam(t))); }
for (const kind of ['wall', 'prop', 'person']) {
  for (const m of kind === 'wall' ? mats : ['stone']) {
    for (const d of dists) for (const t of thetas) out.echoLevel.push({ kind, m, d, t, v: A.echoLevel(kind, d, t, m) });
  }
}
for (const db of [-60, -30, -12, -6, 0, 3, 10]) out.gameAmp.push([db, A.gameAmp(db)]);
for (const d of dists) for (const t of thetas) { out.personAmp.push([d, t, A.personAmp(d, t)]); out.propAmp.push([d, t, A.propAmp(d, t)]); }
for (const m of mats) out.floor.push({ m, level: A.floorLevel(m), amp: A.floorAmp(m) });
for (const z of [undefined, 'crypt', 'church', 'tavern', 'shed', 'nowhere', 'house1']) {
  const c = A.ceilingFor(z);
  out.ceil.push({ z: z || '', h: c.h, mat: c.mat, level: A.ceilLevel(c.h, c.mat), amp: A.ceilAmp(c.h, c.mat), delay: A.ceilDelay(c.h) });
}
for (const hf of [0, 0.3, 0.8, 1]) for (const ma of [0, 0.05, 0.4]) for (const n of [0, 3, 20]) for (const indoor of [true, false]) out.wet.push({ hf, ma, n, indoor, v: A.wetFor(hf, ma, n, indoor) });
for (const z of Object.keys(A.zone)) { const q = A.zone[z]; out.sabine.push({ z, v: A.sabine(q.w, q.d, q.h, q.alpha) }); }
for (const z of [...Object.keys(A.zone), 'nowhere']) for (const kind of ['indoor', 'outdoor']) out.t60.push({ z, kind, v: A.t60For(z, kind) });
for (const tau of [0.001, 0.01, 0.05]) for (const t60 of [0.1, 0.4, 1, 2.5, 9]) out.comb.push([tau, t60, A.combGain(tau, t60)]);
for (const d of [0, 0.5, 2, 9, 40]) for (const hz of [250, 500, 2000]) out.maekawa.push([d, hz, A.maekawa(d, hz)]);
for (const m of [...mats, 'door']) for (const diff of [null, 2, 8, 40]) {
  const o = A.occlusion(m, diff === null ? undefined : diff);
  out.occlusion.push({ m, diff, loss: o.loss, gain: o.gain, lpHz: o.lpHz, peakHz: o.peakHz, peakDb: o.peakDb, diffracted: o.diffracted });
}
for (const r of [0, 0.3, 1.2, 2, 2.1, 5]) out.repetition.push([r, A.repetition(r)]);
for (const g of ['sneak', 'walk', 'mail', 'run', 'bogus']) for (const f of ['grass', 'wood', 'stone', 'bogus']) for (const pace of [0.5, 1, 1.4]) out.stepScale.push({ g, f, pace, v: SD.stepScale(g, f, pace) });

mkdirSync(dirname(OUT), { recursive: true });
writeFileSync(OUT, JSON.stringify(out) + '\n');
console.log('wrote ' + OUT);
