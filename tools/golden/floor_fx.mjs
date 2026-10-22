#!/usr/bin/env node
// Golden fixture (floor_fx.json): draw-call logs of drawRipple, drawAirRings, drawFloorTexture (floor and ceiling),
// drawFloorFront, drawFootRings and drawRings from the real js/render.js, on all maps with several player poses, pulses and
// times. One entry per (scene, function) so a mismatch names the function.
// Usage: node tools/golden/floor_fx.mjs [outPath]   (default project/tests/fixtures/floor_fx.json)

import { dirname, join, resolve } from 'node:path';
import { mkdirSync, writeFileSync } from 'node:fs';
import { PORT, loadRender, buildScene, callLine, fnv1a, TAN } from './lib/render_harness.mjs';

const OUT = process.argv[2] ? resolve(process.argv[2]) : join(PORT, 'project', 'tests', 'fixtures', 'floor_fx.json');
const H = loadRender(['drawRipple', 'drawAirRings', 'drawFloorTexture', 'drawFloorFront', 'drawFootRings', 'drawRings']);
const { VCS, X } = H;
const entries = [];

function run(key, spec, fnName, extra) {
  const { world, sonar, r } = buildScene(H, spec);
  const ctx = r.octx;
  ctx.calls.length = 0;
  const p = spec.player;
  if (fnName === 'drawRipple') X.drawRipple(r, world, sonar, spec.t, p, TAN);
  else if (fnName === 'drawAirRings') X.drawAirRings(r, world, sonar, spec.t, p, TAN);
  else if (fnName === 'drawFloorTexture') X.drawFloorTexture(r, world, sonar, spec.t, p, TAN);
  else if (fnName === 'drawFloorFront') X.drawFloorFront(r, world, sonar, spec.t, p, TAN);
  else if (fnName === 'drawFootRings') X.drawFootRings(r, sonar, spec.t, p, TAN);
  else if (fnName === 'drawRings') {
    const ring = VCS.Ripple.create({});
    for (const g of extra.rings) VCS.Ripple.spawn(ring, g.x, g.y, g.t0, g.opts);
    X.drawRings(r, ring, spec.t, p, TAN);
  }
  const lines = ctx.calls.map(callLine);
  const entry = { key: key + '/' + fnName, fn: fnName, spec, extra: extra || null, zbuf: Array.from(r.zbuf), hash: fnv1a(lines.join('\n')), calls: lines.length };
  if (entries.length < 3 && lines.length) entry.log = lines;
  entries.push(entry);
}

const poses = {
  test: [[3.5, 3.5, 0], [8.5, 4.5, 0.4], [12.5, 2.5, 3.14], [15.5, 7.5, -1.2]],
  crypt: null,
  town: [[16.5, 9.5, 0], [24.5, 6.5, 1.0], [30.5, 10.5, 3.0], [20.5, 14.5, 4.5]]
};
const FUNCS = ['drawRipple', 'drawAirRings', 'drawFloorTexture', 'drawFloorFront'];
for (const map of Object.keys(VCS.MapData.maps)) {
  const def = VCS.MapData.maps[map];
  const world = VCS.World.load(def, { requireStart: false });
  let list = poses[map];
  if (!list) {
    const s = world.start || { x: 3.5, y: 3.5 };
    list = [[s.x, s.y, 0], [s.x, s.y, 2.0]];
  }
  for (let pi = 0; pi < list.length; pi++) {
    const [x, y, a] = list[pi];
    if (world.isSolid(x, y)) continue;
    for (const dt of [0.05, 0.2, 0.4, 0.7, 1.1, 1.8]) {
      const spec = { map, player: { x, y, angle: a }, pulses: [{ k: 'ping', x, y, t0: 1, facing: a }], t: 1 + dt };
      for (const f of FUNCS) run('A/' + map + '/p' + pi + '/dt=' + dt, spec, f);
    }
    const src = (world.props && world.props[0]) || { x: x + 1, y };
    const two = { map, player: { x, y, angle: a }, pulses: [{ k: 'ping', x, y, t0: 1, facing: a }, { k: 'sound', x: src.x, y: src.y, t0: 1.1, opts: { kind: 'door', range: 7, strength: 0.7, bounces: 1, z: 0.4 } }], t: 1.5 };
    for (const f of FUNCS) run('B/' + map + '/p' + pi, two, f);
    for (const [tag, over] of [['q1', { quality: 1 }], ['q2', { quality: 2 }], ['red', { reduced: true }], ['fx1', { fx: 1 }], ['nomat', { matDetail: false }]]) {
      for (const f of FUNCS) run('C/' + map + '/p' + pi + '/' + tag, Object.assign({}, two, { t: 1.3 }, over), f);
    }
    // footsteps: own and others', then secondary rings
    const steps = { map, player: { x, y, angle: a }, pulses: [{ k: 'sound', x: x + 1.2 * Math.cos(a), y: y + 1.2 * Math.sin(a), t0: 1, opts: { kind: 'personStep', range: 3, strength: 0.4, bounces: 0 } }, { k: 'sound', x: x + 0.3, y: y, t0: 1.05, opts: { kind: 'step', range: 2, strength: 0.3, bounces: 0 } }], t: 1.7 };
    for (const dt of [0.3, 1.0, 2.0]) run('D/' + map + '/p' + pi + '/dt=' + dt, Object.assign({}, steps, { t: 1 + dt }), 'drawFootRings');
    const rings = [{ x: x + 2 * Math.cos(a), y: y + 2 * Math.sin(a), t0: 1, opts: { kind: 'person', maxR: 1.6, life: 0.9, strength: 0.8 } }, { x: x + 3 * Math.cos(a + 0.3), y: y + 3 * Math.sin(a + 0.3), t0: 1, opts: { kind: 'marker', maxR: 1.2, life: 0.8, strength: 0.6, delay: 0.18 } }, { x: x + 1.5 * Math.cos(a - 0.3), y: y + 1.5 * Math.sin(a - 0.3), t0: 1, opts: { kind: 'other', maxR: 1.4, minR: 0.3, life: 0.5, strength: 1, inward: true } }];
    for (const dt of [0.2, 0.5, 0.9]) run('E/' + map + '/p' + pi + '/dt=' + dt, { map, player: { x, y, angle: a }, pulses: [], t: 1 + dt }, 'drawRings', { rings });
  }
}
mkdirSync(dirname(OUT), { recursive: true });
writeFileSync(OUT, JSON.stringify({ fixture: 'floor-fx-godot', count: entries.length, entries }) + '\n');
const byFn = {};
for (const e of entries) { byFn[e.fn] = byFn[e.fn] || { n: 0, drawn: 0, calls: 0 }; byFn[e.fn].n++; if (e.calls) byFn[e.fn].drawn++; byFn[e.fn].calls += e.calls; }
console.log('wrote ' + OUT + ' ' + JSON.stringify(byFn));
