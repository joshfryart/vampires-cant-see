#!/usr/bin/env node
// Golden fixture (vessels_draw.json): draw-call logs of js/render.js drawPerson with the circulatory overlay on (VCS.Flags stub:
// vis.vessels true, default tunables), js/data/vessels.js and js/figure.js loaded. Real world, ray-cast depth buffer and tile
// codes, so walls hide the overlay and window columns show it muted. Scenes: vheart echoes on every body type across ages,
// effects and quality levels, reduced motion, the held victim's pulse, bodies behind glass.
// Usage: node tools/golden/vessels_draw.mjs [outPath]   (default project/tests/fixtures/vessels_draw.json)

import { join, resolve, dirname } from 'node:path';
import { mkdirSync, writeFileSync } from 'node:fs';
import { PORT, loadRender, buildScene, callLine, fnv1a, TAN } from './lib/render_harness.mjs';

const OUT = process.argv[2] ? resolve(process.argv[2]) : join(PORT, 'project', 'tests', 'fixtures', 'vessels_draw.json');
const H = loadRender(['drawPerson'], ['data/vessels', 'figure', 'people']);
const { VCS, X } = H;
VCS.Flags = { get: (id) => id === 'vis.vessels', tun: () => undefined };
const V = VCS.Vessels;
const scenes = [];

function look(i) { return VCS.People.makeLook(1234, i, i % 10); }

function scene(key, spec) {
  const sc = buildScene(H, Object.assign({ t: 12.34, quality: 3, fx: 2 }, spec.scene));
  const { world, r, hits } = sc;
  r.visWorld = world;
  for (let i = 0; i < r.cols; i++) r.tch[i] = hits[i].hit ? world.tileAt(hits[i].cellX, hits[i].cellY).charCodeAt(0) : 0;
  r.figMs = 0; r.figBudget = 1e9; r.figVol = 0; r.figLine = 0; r.fxCfg = r.fx; r.fxCap = 0; r.lockId = -1;
  r.vesselNodes = 0; r.vesselHeart = 0; r.vesselFeet = 0;
  const e = spec.echo;
  let locked = false;
  if (spec.lock) {
    locked = true;
    r.lockId = e.personId || 0; r.lockK = spec.lock.k; r.lockAge = spec.lock.age; r.lockSp = 9; r.lockRs = spec.lock.rs || 0;
  }
  const ctx = r.octx;
  ctx.calls.length = 0;
  const drawn = X.drawPerson(r, spec.scene.player, TAN, e, spec.b === undefined ? 0.9 : spec.b, spec.age, false, spec.now === undefined ? 12.34 : spec.now, locked);
  const lines = ctx.calls.map(callLine);
  const entry = { key, hash: fnv1a(lines.join('\n')), calls: lines.length, drawn: !!drawn, nodes: r.vesselNodes, heart: r.vesselHeart, feet: r.vesselFeet, in: JSON.parse(JSON.stringify({ scene: spec.scene, echo: e, age: spec.age, b: spec.b === undefined ? 0.9 : spec.b, now: spec.now === undefined ? 12.34 : spec.now, lock: spec.lock || null })) };
  if (scenes.length < 4) entry.log = lines;
  scenes.push(entry);
}

const PL = { x: 5.5, y: 5.5, angle: 0 };
function echo(i, over) {
  const st = V.state('villager', 'calm', 1);
  return Object.assign({
    personId: 3 + i, kind: 'vheart', x: 7.5, y: 5.5, angle: Math.PI, lookAngle: 0, phase: 0, phaseRate: 0, t: 12, strength: 0.9, zMin: 0.45, zMax: 0.85,
    mode: 'path', sit: false, wary: false, modeAge: 9, fade: 1.3, look: look(i), bpm: st.bpm, stateK: st.stateK, periphK: st.periphK, headK: st.headK
  }, over || {});
}
const test = (extra) => Object.assign({ map: 'test', player: PL, pulses: [], t: 12.34 }, extra || {});

// A: states x ages x fx x quality
const states = [['calm', 1], ['flee', 0.5], ['wary', 0.9], ['drinking', 0.3], ['calm', 0.08]];
for (const [mode, blood] of states) {
  const st = V.state('villager', mode, blood);
  for (const age of [-1, 0, 0.05, 0.2, 0.45, 0.8, 1.3, 2.2]) {
    for (const [fx, quality] of [[2, 3], [1, 2], [2, 1], [0, 0], [2, 2]]) {
      scene('A/' + mode + blood + '/age=' + age + '/fx' + fx + 'q' + quality, { scene: test({ fx, quality }), age, echo: echo(2, { bpm: st.bpm, stateK: st.stateK, periphK: st.periphK, headK: st.headK }) });
    }
  }
}
// B: bodies and facings, reduced motion
for (let i = 0; i < 24; i++) {
  scene('B/look' + i + '/walk', { scene: test(), age: 0.3, echo: echo(i, { phase: 1.7 + i, phaseRate: 6, x: 6.6 + (i % 4) * 0.6, angle: i * 0.7 }) });
  scene('B/look' + i + '/reduced', { scene: Object.assign(test(), { reduced: true }), age: 0.2, echo: echo(i, { x: 6.8 + (i % 3) * 0.5, angle: i * 0.5, mode: i % 2 ? 'flee' : 'path' }) });
}
// C: held victim (pulse snapshot on the locked figure)
for (const k of [0, 0.5, 1]) {
  for (const now of [12.34, 12.6, 13.2]) {
    const st = V.state('villager', 'drinking', 1 - k * 0.8);
    scene('C/lock/k=' + k + '/now=' + now, { scene: test(), age: -1, now, lock: { k, age: 2.5, rs: k > 0.5 ? 0.6 : 0 }, echo: { personId: 7, kind: 'ping', x: 6.4, y: 5.5, angle: Math.PI, lookAngle: 0.1, phase: 0, t: 12.2, strength: 0.9, zMin: 0, zMax: 1.2, fade: 2.2, look: look(7), vessel: { bpm: st.bpm, stateK: st.stateK, periphK: st.periphK, headK: st.headK } } });
  }
}
// D: behind glass in the town: a body inside, the player outside, facing a window
{
  const def = VCS.MapData.maps.town;
  const world = VCS.World.load(def, { requireStart: false });
  let n = 0;
  for (let y = 1; y < world.height - 1 && n < 10; y++) {
    for (let x = 1; x < world.width - 1 && n < 10; x++) {
      if (world.tileAt(x, y) !== 'w') continue;
      for (const d of [[0, 1], [0, -1], [1, 0], [-1, 0]]) {
        const ox = x + 0.5 + d[0] * 0.8; const oy = y + 0.5 + d[1] * 0.8; // player side
        const ix = x + 0.5 - d[0] * 1.2; const iy = y + 0.5 - d[1] * 1.2; // inside
        if (world.isSolid(ox, oy) || world.isSolid(ix, iy)) continue;
        const ang = Math.atan2(-d[1], -d[0]);
        for (const age of [0.1, 0.5]) {
          scene('D/window' + x + ',' + y + '/' + d + '/age=' + age, { scene: { map: 'town', player: { x: ox, y: oy, angle: ang }, pulses: [], t: 12.34 }, age, b: 0.9, echo: echo(n, { x: ix, y: iy, angle: ang + Math.PI * 0.8 }) });
        }
        n++;
        break;
      }
    }
  }
}
// E: behind a wall, off screen, too old
scene('E/behind-wall', { scene: { map: 'town', player: { x: 16.5, y: 9.5, angle: 0 }, pulses: [], t: 12.34 }, age: 0.2, echo: echo(1, { x: 20.5, y: 9.5 }) });
scene('E/old', { scene: test(), age: 3.0, echo: echo(1) });
scene('E/offscreen', { scene: test(), age: 0.2, echo: echo(1, { x: 5.5, y: 40 }) });
scene('E/novheart', { scene: test(), age: 0.2, echo: echo(1, { kind: 'ping' }) });

mkdirSync(dirname(OUT), { recursive: true });
writeFileSync(OUT, JSON.stringify({ fixture: 'vessels-draw-godot', v: 1, count: scenes.length, scenes }) + '\n');
console.log('wrote ' + OUT + ' ' + scenes.length + ' scenes, ' + scenes.filter((s) => s.drawn).length + ' drawn, ' + scenes.filter((s) => s.nodes > 0).length + ' with vessel nodes, ' + scenes.reduce((a, s) => a + s.calls, 0) + ' calls');
