#!/usr/bin/env node
// Golden fixture: draw-call logs of the line figure (effects 0) from the real js/render.js via Render.drawSolo.
// Each scene records the fake-canvas call log of one villager echo; the fixture stores the FNV-1a hash of the canonical
// log (args rounded to 1e-3, same canonical form as tools/figure-golden.mjs), the call count, and the full log for the
// first scenes so a mismatch can be debugged. Struggle (js/struggle.js) is NOT loaded: grapple uses the plain pose,
// which is what core/struggle.gd replaces in Phase 4. Vessels and Figure (volumetric) are not loaded either (effects 0).
// Usage: node tools/golden/figure.mjs [outPath]   (default project/tests/fixtures/figure.json)
// Deterministic: no clock, no randomness.

import { createRequire } from 'node:module';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { mkdirSync, writeFileSync } from 'node:fs';

const require = createRequire(import.meta.url);
const HERE = dirname(fileURLToPath(import.meta.url));
const PORT = resolve(HERE, '..', '..');
const JS = join(resolve(PORT, '..'), 'js');
const OUT = process.argv[2] ? resolve(process.argv[2]) : join(PORT, 'project', 'tests', 'fixtures', 'figure.json');

for (const m of ['log', 'ripple', 'raycast', 'world', 'sonar', 'people', 'data/maps', 'data/sounds']) require(join(JS, m + '.js'));
const Render = require(join(JS, 'render.js'));
const VCS = globalThis.VCS;
VCS.Log.setConsole(false);
if (VCS.Struggle || VCS.Figure || VCS.Flags) throw new Error('Struggle/Figure/Flags must not be loaded for this fixture');

function fakeCtx(canvas) {
  const calls = [];
  const state = { globalAlpha: 1, fillStyle: '#000', strokeStyle: '#000', lineWidth: 1 };
  return new Proxy({ calls, canvas }, {
    get(t, p) {
      if (p in t) return t[p];
      if (p in state) return state[p];
      return function () {
        calls.push({ fn: String(p), args: Array.prototype.slice.call(arguments), stroke: state.strokeStyle, alpha: state.globalAlpha, lw: state.lineWidth });
        if (p === 'createRadialGradient' || p === 'createLinearGradient') return { addColorStop() {} };
        if (p === 'createPattern') return {};
        if (p === 'createImageData') return { data: new Uint8ClampedArray(128 * 128 * 4) };
        return undefined;
      };
    },
    set(t, p, v) { state[p] = v; return true; }
  });
}
function fakeCanvas(w, h) {
  const c = { width: w, height: h, ownerDocument: null };
  c.ownerDocument = { createElement() { return fakeCanvas(w, h); } };
  c._ctx = null;
  c.getContext = function () { return c._ctx || (c._ctx = fakeCtx(c)); };
  return c;
}

function r3(x) { return Object.is(x, -0) ? 0 : Math.round(x * 1000) / 1000; }
function canon(v) {
  if (typeof v === 'number') return Number.isFinite(v) ? String(r3(v)) : String(v);
  if (typeof v === 'string') return JSON.stringify(v);
  if (typeof v === 'boolean' || v === null || v === undefined) return String(v);
  return '<obj>';
}
function callLine(c) {
  return c.fn + '(' + c.args.map(canon).join(',') + ') s=' + canon(c.stroke) + ' a=' + canon(c.alpha) + ' lw=' + canon(c.lw);
}
function fnv1a(str) {
  const bytes = Buffer.from(str, 'utf8');
  let h = 0x811c9dc5;
  for (let i = 0; i < bytes.length; i++) { h ^= bytes[i]; h = Math.imul(h, 0x01000193) >>> 0; }
  return h.toString(16).padStart(8, '0');
}

const modes = ['path', 'startle', 'flee', 'cower', 'dazed', 'grapple', 'fed'];
const accs = VCS.People.ACCESSORIES;
const PLAYER = { x: 5.5, y: 5.5, angle: 0 };
const scenes = [];

function scene(key, o) {
  // o: {quality, reduced, t, age, b, echo, lock, player}
  const canvas = fakeCanvas(640, 360);
  const r = Render.create(canvas, {});
  r.reduced = !!o.reduced;
  const e = Object.assign({
    x: 7.5, y: 5.5, angle: Math.PI, lookAngle: 0, phase: 0, phaseRate: 0, personId: 3, t: 0, strength: 1, zMin: 0, zMax: 2,
    mode: 'path', sit: false, wary: false, modeAge: 0.1, fade: 3, look: VCS.People.makeLook(9, 3, 0)
  }, o.echo || {});
  const ctx = r.octx;
  ctx.calls.length = 0;
  const drawn = Render.drawSolo(r, e, { fx: 0, quality: o.quality === undefined ? 3 : o.quality, t: o.t === undefined ? 12.34 : o.t, age: o.age === undefined ? 0.1 : o.age, b: o.b === undefined ? 0.8 : o.b, player: o.player || PLAYER, lock: o.lock });
  const lines = ctx.calls.map(callLine);
  const entry = { key, hash: fnv1a(lines.join('\n')), calls: lines.length, drawn: !!drawn, in: { quality: o.quality === undefined ? 3 : o.quality, reduced: !!o.reduced, t: o.t === undefined ? 12.34 : o.t, age: o.age === undefined ? 0.1 : o.age, b: o.b === undefined ? 0.8 : o.b, player: o.player || PLAYER, lock: o.lock || null, echo: Object.assign({}, e, { look: e.look }) } };
  if (scenes.length < 6) entry.log = lines;
  scenes.push(entry);
}

// A: every mode x every accessory while the band sweeps (age 0.1), default quality.
for (const mode of modes) {
  for (let a = 0; a < accs.length; a++) {
    const look = VCS.People.makeLook(9, a * 7 + modes.indexOf(mode), a);
    look.acc = accs[a];
    scene('A/' + mode + '/' + accs[a], { echo: { mode, look, sit: modes.indexOf(mode) % 2 === 0, wary: modes.indexOf(mode) % 3 === 0 } });
  }
}
// B: every mode across ages (before, front, glow, late) x quality x reduced.
for (const mode of modes) {
  for (const age of [-1, 0.03, 0.15, 0.3, 0.6, 1.2]) {
    for (const quality of [0, 1, 3]) {
      for (const reduced of [false, true]) {
        scene('B/' + mode + '/age=' + age + '/q=' + quality + '/red=' + reduced, { quality, reduced, age, echo: { mode, look: VCS.People.makeLook(4, 2, 5) } });
      }
    }
  }
}
// C: walking and fleeing gait phases, near and far, various facings and lookAngles.
for (const mode of ['path', 'flee']) {
  for (const phase of [0.5, 1.7, 3.0, 4.4, 6.0]) {
    for (const [x, y, ang] of [[6.7, 5.5, Math.PI], [7.5, 6.2, Math.PI * 0.75], [9.5, 4.8, 0.4], [12.5, 5.5, -Math.PI / 2], [7.0, 5.0, Math.PI / 2]]) {
      scene('C/' + mode + '/ph=' + phase + '/at=' + x + ',' + y, { age: 0.4, echo: { mode, phase, phaseRate: 7, x, y, angle: ang, lookAngle: 0.3, look: VCS.People.makeLook(2, 1, 3) } });
    }
  }
}
// D: many looks (bodies, heads, hairs, hats, coats, beards) idle and moving.
for (let id = 0; id < 40; id++) {
  const look = VCS.People.makeLook(1234, id, id % 10);
  scene('D/look' + id + '/idle', { age: 0.5, echo: { look, personId: id } });
  scene('D/look' + id + '/walk', { age: 0.5, echo: { look, personId: id, phase: 2.1 + id * 0.3, phaseRate: 6, x: 6.5 + (id % 5), y: 5.5 + (id % 3 - 1) * 0.6, angle: id * 0.8 } });
}
// E: the held victim (feeding lock): pose, red outline and grab arms.
for (const k of [0, 0.3, 0.7, 1]) {
  for (const age of [0.2, 1.0, 3.0]) {
    for (const reduced of [false, true]) {
      scene('E/lock/k=' + k + '/age=' + age + '/red=' + reduced, { reduced, lock: { k, age, sp: 9, rs: k > 0.5 ? 0.6 : 0 }, echo: { personId: 7, mode: 'grapple', look: VCS.People.makeLook(11, 7, 1) } });
    }
  }
}
// F: off screen, behind the camera, and the camera inside a figure.
for (const [x, y] of [[5.5, 5.5], [5.6, 5.5], [-2.0, 5.5], [7.5, 40.0], [7.5, -30.0], [5.55, 5.5]]) {
  scene('F/edge/' + x + ',' + y, { age: 0.2, echo: { x, y } });
}

const out = { fixture: 'figure-line-godot', v: 1, hash: 'fnv1a-32 over canonical call log (args rounded 1e-3), see tools/golden/figure.mjs', count: scenes.length, scenes };
mkdirSync(dirname(OUT), { recursive: true });
writeFileSync(OUT, JSON.stringify(out) + '\n');
const drawnN = scenes.filter((s) => s.drawn).length;
console.log('wrote ' + OUT + ' (' + scenes.length + ' scenes, ' + drawnN + ' drawn, ' + scenes.reduce((a, s) => a + s.calls, 0) + ' calls)');
