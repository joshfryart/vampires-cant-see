#!/usr/bin/env node
// Golden fixture (vessels.json): js/data/vessels.js. Node tables, pulse state per mode and blood, strengths, beat timing, the
// travelling pulse (arteries, veins, reduced motion) on an age grid, travel delays, edges, limb geometry on a pose, edge fronts.
// Usage: node tools/golden/vessels.mjs [outPath]   (default project/tests/fixtures/vessels.json)

import { createRequire } from 'node:module';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { mkdirSync, writeFileSync } from 'node:fs';

const require = createRequire(import.meta.url);
const HERE = dirname(fileURLToPath(import.meta.url));
const PORT = resolve(HERE, '..', '..');
const JS = join(resolve(PORT, '..'), 'js');
const OUT = process.argv[2] ? resolve(process.argv[2]) : join(PORT, 'project', 'tests', 'fixtures', 'vessels.json');
const V = require(join(JS, 'data', 'vessels.js'));
const clean = (v) => (v === undefined ? null : JSON.parse(JSON.stringify(v)));
const out = { fixture: 'vessels-godot', v: 1 };

out.nodes = clean(V.all());
out.edgesA = clean(V.edges(false));
out.edgesV = clean(V.edges(true));
out.travel = [0, 1, 1.75, 2.5, -1].map((s) => clean({ s, out: V.travel(s) }));

const modes = ['calm', 'wary', 'startle', 'flee', 'cower', 'sleep', 'drinking', 'fed', 'drained', 'zzz'];
const bloods = [undefined, 1, 0.8, 0.6, 0.4, 0.39, 0.2, 0.05, 0, -1, 2];
out.state = [];
for (const m of modes) for (const b of bloods) out.state.push(clean({ mode: m, blood: b === undefined ? null : b, out: V.state('villager', m, b) }));
out.state.push(clean({ mode: 'calm', blood: 1, kind: 'vampire', out: V.state('vampire', 'calm', 1) }));

out.strength = [];
for (const st of [V.state('villager', 'calm', 1), V.state('villager', 'flee', 0.5), V.state('villager', 'wary', 0.9), V.state('villager', 'drinking', 0.3), V.state('villager', 'fed', 1), null]) {
  out.strength.push(clean({ st, list: V.all().map((n) => V.strength(n, st)) }));
}

out.timing = [];
for (const bpm of [0, 40, 65, 90, 120, 150, 175, 300, -5]) for (const red of [false, true]) for (const sc of [0, 1.75, 2.5]) out.timing.push(clean({ bpm, red, sc, out: V.timing(bpm, red, sc) }));

out.pulse = [];
for (const bpm of [65, 130]) for (const red of [false, true]) {
  const tm = V.timing(bpm, red, 1.75);
  const rows = [];
  for (let a = -0.1; a <= tm.life + 0.3; a += 0.07) {
    rows.push({ age: Math.round(a * 1000) / 1000, art: V.data.arteries.map((_, i) => V.pulse(false, i, a, tm, 1.75)), vein: V.data.veins.map((_, i) => V.pulse(true, i, a, tm, 1.75)) });
  }
  out.pulse.push(clean({ bpm, red, tm, rows }));
}

// geometry on a pose: slots 0..23
const X = new Float32Array(28);
const Y = new Float32Array(28);
for (let k = 0; k < 28; k++) { X[k] = 300 + Math.sin(k * 1.7) * 60 + k * 3; Y[k] = 120 + Math.cos(k * 2.3) * 70 + k * 5; }
out.pose = { X: Array.from(X), Y: Array.from(Y) };
const nodes = V.all();
out.points = clean(nodes.map((n) => ({ id: n.id, anchor: V.anchor(n, X, Y), point: V.point(n, X, Y) })));
out.edgeCtrls = [];
for (const vein of [false, true]) {
  const list = vein ? V.data.veins : V.data.arteries;
  for (const e of V.edges(vein)) {
    const c = { x: 0, y: 0 };
    const has = V.edgeCtrl(list[e.p], list[e.i], X, Y, c);
    out.edgeCtrls.push(clean({ vein, i: e.i, p: e.p, has, c: has ? c : null }));
  }
}
out.edgeAt = [];
for (const s of [0, 0.25, 0.5, 1]) {
  out.edgeAt.push(clean({ s, straight: V.edgeAt({ x: 1, y: 2 }, null, { x: 9, y: 6 }, s), curved: V.edgeAt({ x: 1, y: 2 }, { x: 5, y: 9 }, { x: 9, y: 6 }, s) }));
}
out.edgeFront = [[0.5, 0.1, 0.4], [0.05, 0.1, 0.4], [1, 0.1, 0.4], [0.2, 0.3, 0.3], [0.4, 0.3, 0.3], [0.3, 0.3, 0.3]].map((a) => clean({ a, out: V.edgeFront(a[0], a[1], a[2]) }));
out.envelope = [[-1, 0.06, 0.25], [0, 0.06, 0.25], [0.03, 0.06, 0.25], [0.06, 0.06, 0.25], [0.5, 0.06, 0.25]].map((a) => clean({ a, out: V.envelope(a[0], a[1], a[2]) }));
out.forBody = clean([V.forBody('villager'), V.forBody('vampire')].map((b) => ({ kind: b.kind, n: b.nodes.length, pulse: b.pulse, blood: b.blood, state: b.state })));

mkdirSync(dirname(OUT), { recursive: true });
writeFileSync(OUT, JSON.stringify(out) + '\n');
console.log('wrote ' + OUT);
