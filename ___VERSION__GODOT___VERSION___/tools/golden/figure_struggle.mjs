#!/usr/bin/env node
// Golden fixture: draw-call logs of the line figure (effects 0) from the real js/render.js via Render.drawSolo.
// Each scene records the fake-canvas call log of one villager echo; the fixture stores the FNV-1a hash of the canonical
// log (args rounded to 1e-3, same canonical form as tools/figure-golden.mjs), the call count, and the full log for the
// first scenes so a mismatch can be debugged. Struggle (js/struggle.js) IS loaded here: grapple scenes use the struggle pose (fixture figure_struggle.json).
// Vessels and Figure (volumetric) are not loaded either (effects 0).
// Usage: node tools/golden/figure.mjs [outPath]   (default project/tests/fixtures/figure_struggle.json)
// Deterministic: no clock, no randomness.

import { createRequire } from 'node:module';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { mkdirSync, writeFileSync } from 'node:fs';

const require = createRequire(import.meta.url);
const HERE = dirname(fileURLToPath(import.meta.url));
const PORT = resolve(HERE, '..', '..');
const JS = join(resolve(PORT, '..'), 'js');
const OUT = process.argv[2] ? resolve(process.argv[2]) : join(PORT, 'project', 'tests', 'fixtures', 'figure_struggle.json');

for (const m of ['log', 'ripple', 'raycast', 'world', 'sonar', 'people', 'data/maps', 'data/sounds', 'struggle']) require(join(JS, m + '.js'));
const Render = require(join(JS, 'render.js'));
const VCS = globalThis.VCS;
VCS.Log.setConsole(false);
if (!VCS.Struggle || VCS.Figure || VCS.Flags) throw new Error('Struggle must be loaded and Figure/Flags not for this fixture');

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

// Held victims: struggle poses across blood left, time since the grab, struggle attempts, restraint, ids and reduced motion.
for (const pid of [0, 1, 2, 3, 6, 9]) {
  for (const k of [0, 0.15, 0.4, 0.7, 0.95, 1]) {
    for (const age of [0.1, 0.5, 2.0, 4.0, 8.0]) {
      for (const sp of [0.05, 0.3, 9]) {
        for (const reduced of [false, true]) {
          if (reduced && sp !== 9) continue;
          scene('G/p' + pid + '/k=' + k + '/age=' + age + '/sp=' + sp + '/red=' + reduced, { reduced, t: 20 + age, lock: { k, age, sp, rs: (pid + Math.round(k * 10)) % 3 === 0 ? 0.7 : 0 }, echo: { personId: pid, mode: 'grapple', x: 7.0 + pid * 0.2, look: VCS.People.makeLook(11, pid, pid % 7) } });
        }
      }
    }
  }
}
// Unlocked echoes still draw as before (a grapple echo with no lock state is a JS edge case that draws NaN poses: not ported).
for (const age of [0.2, 1.0]) for (const mode of ['path', 'flee']) scene('H/' + mode + '/age=' + age, { age, echo: { personId: 4, mode, look: VCS.People.makeLook(3, 4, 2) } });

const out = { fixture: 'figure-struggle-godot', v: 1, hash: 'fnv1a-32 over canonical call log (args rounded 1e-3), see tools/golden/figure.mjs', count: scenes.length, scenes };
mkdirSync(dirname(OUT), { recursive: true });
writeFileSync(OUT, JSON.stringify(out) + '\n');
const drawnN = scenes.filter((s) => s.drawn).length;
console.log('wrote ' + OUT + ' (' + scenes.length + ' scenes, ' + drawnN + ' drawn, ' + scenes.reduce((a, s) => a + s.calls, 0) + ' calls)');
