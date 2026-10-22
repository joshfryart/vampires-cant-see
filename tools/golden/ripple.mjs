#!/usr/bin/env node
// Golden fixture (ripple.json): js/ripple.js beyond the boil table: wobble, bands, wave, wavy rings, mask strips,
// footstep rings and the secondary ring state.
// Usage: node tools/golden/ripple.mjs [outPath]   (default project/tests/fixtures/ripple.json)

import { createRequire } from 'node:module';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { mkdirSync, writeFileSync } from 'node:fs';

const require = createRequire(import.meta.url);
const HERE = dirname(fileURLToPath(import.meta.url));
const PORT = resolve(HERE, '..', '..');
const JS = join(PORT, 'html-version', 'js');
const OUT = process.argv[2] ? resolve(process.argv[2]) : join(PORT, 'project', 'tests', 'fixtures', 'ripple.json');
require(join(JS, 'log.js'));
require(join(JS, 'ripple.js'));
const R = globalThis.VCS.Ripple;
const ages = [-1, 0, 0.01, 0.1, 0.2, 0.3, 0.45, 0.59, 0.6, 1];
const us = [0, 0.1, 0.3, 0.5, 0.8, 1, 1.2];
const rows = { wobble: [], band: [], wave: [], wavy: [], strips: [], foot: [], amp: [] };
for (const a of ages) for (const p of [0, 1.7]) rows.wobble.push({ a, p, v: R.wobble(a, p) });
for (const a of ages) {
  rows.band.push({ a, f: R.bandFront(a) });
  for (const u of us) { rows.band.push({ a, u, g: R.bandGain(u, a) }); rows.wave.push({ a, u, w: R.wave(u, a) }); }
}
for (const R0 of [0.5, 3, 9]) for (const th of [0, 1, 3.3, 6]) for (const [t, k, amp] of [[0, 6, 0.04], [2.5, 5, 0.04], [1, 7, undefined], [1, 0, 0.1]]) rows.wavy.push({ R: R0, th, t, k, amp: amp === undefined ? null : amp, v: R.wavyRadius(R0, th, t, k, amp) });
for (const [zmin, zmax] of [[0, 1.2], [0.2, 0.6], [0.7, 0.75], [0.5, 0.2], [-0.2, 0.05], [1, 1.2], [0.3, 0.3]]) {
  for (const ztop of [1, 1.7]) for (const soft of [0.12, 0.3, 0]) {
    const out = new Float32Array(9);
    const n = R.maskStrips(zmin, zmax, ztop, soft, out);
    rows.strips.push({ zmin, zmax, ztop, soft, n, out: Array.from(out.slice(0, n * 3)) });
  }
}
for (const age of [-0.2, 0, 0.3, 1.2, 2.9, 3.5]) for (const k of [0, 1, 2]) rows.foot.push({ age, k, ring: R.footRing(age, 3, 7, k), alpha: R.footRingAlpha(age, 3, k) });
for (const l of [-1, 0, 10, 100, 1000]) rows.amp.push({ l, v: R.jitterAmp(l) });
const st = R.create({ maxRings: 3 });
const ops = [];
for (let i = 0; i < 5; i++) {
  const r = R.spawn(st, i, i * 2, i * 0.3, { kind: i % 2 ? 'person' : 'marker', maxR: 1 + i * 0.2, life: 0.5, strength: 0.8, delay: i === 2 ? 0.2 : 0, inward: i === 3, minR: 0.3 });
  ops.push({ n: st.rings.length, x: r.x });
}
const samples = [];
for (const ring of st.rings) for (const t of [0, 0.5, 0.8, 1.2, 2]) samples.push({ x: ring.x, t, r: R.radius(ring, t), a: R.alpha(ring, t) });
R.prune(st, 1.0);
mkdirSync(dirname(OUT), { recursive: true });
writeFileSync(OUT, JSON.stringify({ rows, ops, samples, afterPrune: st.rings.map((r) => r.x) }) + '\n');
console.log('wrote ' + OUT);
