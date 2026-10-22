#!/usr/bin/env node
// Golden fixture (figure_vol.json): draw-call logs of the volumetric figure (js/figure.js, effects 1 and 2) from the real
// js/render.js via Render.drawSolo with VCS.Figure loaded: parts, occlusion fill, wrap lines, shade and rim, details (face,
// hair, hats, props, fingers), outfits, role hats and items, the band-front rings on the silhouette and the held victim's
// vol grab arms. One entry per scene (FNV-1a over the canonical call log, same form as figure.json).
// Usage: node tools/golden/figure_vol.mjs [outPath]   (default project/tests/fixtures/figure_vol.json)

import { createRequire } from 'node:module';
import { dirname, join, resolve } from 'node:path';
import { mkdirSync, writeFileSync } from 'node:fs';
import { PORT, JS, fakeCanvas, callLine, fnv1a } from './lib/render_harness.mjs';

const require = createRequire(import.meta.url);
const OUT = process.argv[2] ? resolve(process.argv[2]) : join(PORT, 'project', 'tests', 'fixtures', 'figure_vol.json');
for (const m of ['log', 'ripple', 'raycast', 'world', 'sonar', 'people', 'figure', 'data/maps', 'data/sounds']) require(join(JS, m + '.js'));
const Render = require(join(JS, 'render.js'));
const VCS = globalThis.VCS;
VCS.Log.setConsole(false);
if (VCS.Struggle || VCS.Flags) throw new Error('Struggle/Flags must not be loaded for this fixture');
if (!VCS.Figure) throw new Error('Figure must be loaded');

const modes = ['path', 'startle', 'flee', 'cower', 'dazed', 'grapple', 'fed'];
const PLAYER = { x: 5.5, y: 5.5, angle: 0 };
const scenes = [];

function scene(key, o) {
  const canvas = fakeCanvas(640, 360);
  const r = Render.create(canvas, {});
  r.reduced = !!o.reduced;
  const e = Object.assign({
    x: 7.5, y: 5.5, angle: Math.PI, lookAngle: 0, phase: 0, phaseRate: 0, personId: 3, t: 0, strength: 1, zMin: 0, zMax: 2,
    mode: 'path', sit: false, wary: false, modeAge: 0.1, fade: 3, look: VCS.People.makeLook(9, 3, 0)
  }, o.echo || {});
  const ctx = r.octx;
  ctx.calls.length = 0;
  const inp = { fx: o.fx === undefined ? 2 : o.fx, quality: o.quality === undefined ? 3 : o.quality, t: o.t === undefined ? 12.34 : o.t, age: o.age === undefined ? 0.1 : o.age, b: o.b === undefined ? 0.8 : o.b, player: o.player || PLAYER, lock: o.lock, lights: o.lights };
  const drawn = Render.drawSolo(r, e, inp);
  const lines = ctx.calls.map(callLine);
  const entry = { key, hash: fnv1a(lines.join('\n')), calls: lines.length, drawn: !!drawn, in: Object.assign({ reduced: !!o.reduced }, JSON.parse(JSON.stringify(inp)), { echo: e }) };
  if (scenes.length < 6) entry.log = lines;
  scenes.push(entry);
}

const LIGHTS = [{ x: 6.3, y: 4.0, radius: 3 }, { x: 9, y: 9, radius: 2 }];
const OUTFITS = ['plain', 'mail', 'robe', 'cloak', 'apron', 'smock'];
const ROLEHATS = ['none', 'kettle', 'biretta'];
const EXTRAS = ['none', 'shovel', 'bundle', 'ledger', 'bow'];
const ARCH = ['patron', 'innkeeper', 'drunk', 'regular', 'priest', 'elder', 'farmer', 'mother', 'insomniac', 'gravedigger', 'guard', 'child', 'merchant', 'hunter'];

// A: every mode x every fx x quality while the band sweeps, with a rim light.
for (const mode of modes) {
  for (const fx of [1, 2]) {
    for (const quality of [1, 2, 3]) {
      scene('A/' + mode + '/fx=' + fx + '/q=' + quality, { fx, quality, lights: LIGHTS, echo: { mode, look: VCS.People.makeLook(9, modes.indexOf(mode), 2), sit: modes.indexOf(mode) % 2 === 0, wary: modes.indexOf(mode) % 3 === 0 } });
    }
  }
}
// B: ages across the band (before, front, glow, late), fx 2, quality 3, reduced and not.
for (const mode of ['path', 'startle', 'cower']) {
  for (const age of [-1, 0.03, 0.08, 0.15, 0.3, 0.6, 1.2]) {
    for (const reduced of [false, true]) scene('B/' + mode + '/age=' + age + '/red=' + reduced, { reduced, age, lights: LIGHTS, echo: { mode, look: VCS.People.makeLook(4, 2, 5) } });
  }
}
// C: gait phases, facings, distances.
for (const mode of ['path', 'flee']) {
  for (const phase of [0.5, 1.7, 3.0, 4.4, 6.0]) {
    for (const [x, y, ang] of [[6.7, 5.5, Math.PI], [7.5, 6.2, Math.PI * 0.75], [9.5, 4.8, 0.4], [12.5, 5.5, -Math.PI / 2], [7.0, 5.0, Math.PI / 2], [14.0, 5.5, 3]]) {
      scene('C/' + mode + '/ph=' + phase + '/at=' + x + ',' + y, { age: 0.4, lights: LIGHTS, echo: { mode, phase, phaseRate: 7, x, y, angle: ang, lookAngle: 0.3, look: VCS.People.makeLook(2, 1, 3) } });
    }
  }
}
// D: many looks, idle and walking (bodies, heads, hairs, hats, coats, beards), one with a head scratch (pid % 3 == 1).
for (let id = 0; id < 40; id++) {
  const look = VCS.People.makeLook(1234, id, id % 10);
  scene('D/look' + id + '/idle', { age: 0.5, lights: LIGHTS, echo: { look, personId: id, lookAngle: (id % 5) * 0.5 - 1 } });
  scene('D/look' + id + '/walk', { age: 0.5, echo: { look, personId: id, phase: 2.1 + id * 0.3, phaseRate: 6, x: 6.5 + (id % 5), y: 5.5 + (id % 3 - 1) * 0.6, angle: id * 0.8 } });
  scene('D/look' + id + '/turn', { age: 0.5, echo: { look, personId: id, x: 6.2 + (id % 4) * 0.3, y: 5.9, angle: id * 0.37, lookAngle: id * 0.2 } });
}
// E: outfits x role hats x extras x archetypes on a few builds, idle, walking and fleeing.
let n = 0;
for (const outfit of OUTFITS) {
  for (const roleHat of ROLEHATS) {
    for (const extra of EXTRAS) {
      const look = Object.assign({}, VCS.People.makeLook(77, n, n % 10), { outfit, roleHat, extra, hem: [0.2, 0.7, 1][n % 3], shoulder: 0.9 + (n % 4) * 0.1, stoop: (n % 3) * 0.15, archetype: ARCH[n % ARCH.length], skin: 0.5 });
      const moving = n % 2 === 0;
      scene('E/' + outfit + '/' + roleHat + '/' + extra, { age: 0.5, lights: LIGHTS, echo: { look, personId: n, mode: n % 5 === 0 ? 'flee' : 'path', phase: moving ? 1.3 + n * 0.2 : 0, phaseRate: moving ? 6 : 0, x: 6.5 + (n % 4), angle: n * 0.9, chat: n % 3 === 0 } });
      n++;
    }
  }
}
// F: every archetype face at several yaws, moods via modes.
for (const a of ARCH) {
  for (const lookAngle of [0, 0.6, -0.6, 1.4]) {
    for (const mode of ['path', 'startle', 'fed']) {
      const look = Object.assign({}, VCS.People.makeLook(5, ARCH.indexOf(a), 1), { archetype: a, beard: ARCH.indexOf(a) % 3 === 0 });
      scene('F/' + a + '/yaw=' + lookAngle + '/' + mode, { age: 0.5, echo: { look, personId: ARCH.indexOf(a), mode, x: 6.6, angle: Math.PI + lookAngle * 0.3, lookAngle } });
    }
  }
}
// G: the held victim (vol grab arms).
for (const k of [0, 0.3, 0.7, 1]) {
  for (const age of [0.2, 1.0, 3.0]) {
    for (const reduced of [false, true]) {
      scene('G/lock/k=' + k + '/age=' + age + '/red=' + reduced, { reduced, lock: { k, age, sp: 9, rs: k > 0.5 ? 0.6 : 0 }, echo: { personId: 7, mode: 'grapple', look: VCS.People.makeLook(11, 7, 1) } });
    }
  }
}
// H: edges: off screen, behind, too far for vol, inside the figure.
for (const [x, y] of [[5.5, 5.5], [5.6, 5.5], [-2.0, 5.5], [7.5, 40.0], [7.5, -30.0], [5.55, 5.5], [15.4, 5.5], [15.6, 5.5], [16.5, 5.5]]) {
  scene('H/edge/' + x + ',' + y, { age: 0.2, echo: { x, y } });
}

const out = { fixture: 'figure-vol-godot', v: 1, hash: 'fnv1a-32 over canonical call log (args rounded 1e-3), see tools/golden/figure_vol.mjs', count: scenes.length, scenes };
mkdirSync(dirname(OUT), { recursive: true });
writeFileSync(OUT, JSON.stringify(out) + '\n');
console.log('wrote ' + OUT + ' ' + scenes.length + ' scenes, ' + scenes.filter((s) => s.drawn).length + ' drawn, ' + scenes.reduce((a, s) => a + s.calls, 0) + ' calls');
