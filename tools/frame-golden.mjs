#!/usr/bin/env node
// Full-frame golden fixture generator for the v0.15 frame split (job C0).
// Captures today's Render.drawFirstPerson call log at effects 0 for 4 fixed scenes
// (crypt start, town street, window wall, dawn), so the C2 render.js changes can be
// checked for parity with effects off. Same fake context and FNV-1a hash as figure-golden.mjs.
// Usage: node tools/frame-golden.mjs [outPath]
//   default outPath: tests/fixtures/frame-v0150.json
// Deterministic: same code in, byte-identical JSON out. No randomness, no clock.

import { createRequire } from 'node:module';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { mkdirSync, writeFileSync } from 'node:fs';

const require = createRequire(import.meta.url);
const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const JS = join(ROOT, 'js');

const LOAD = ['log', 'ripple', 'raycast', 'world', 'sonar', 'people', 'struggle', 'data/maps', 'data/sounds'];
for (const m of LOAD) require(join(JS, m + '.js'));
require(join(JS, 'flags.js'));
require(join(JS, 'data', 'vessels.js'));
const Render = require(join(JS, 'render.js'));
const VCS = globalThis.VCS;
VCS.Flags.register('vis.vessels', false, 'Circulatory pulse on villagers');
VCS.Log.setConsole(false);

// Wall segments are batched into Path2D objects, which Node lacks: same counting stub as render.test.js:174.
if (typeof globalThis.Path2D === 'undefined') {
  globalThis.Path2D = class { constructor() { this.n = 0; } moveTo() { this.n++; } lineTo() { this.n++; } };
}

const OUT = process.argv[2] ? resolve(process.argv[2]) : join(ROOT, 'tests', 'fixtures', 'frame-v0150.json');

// ---- fake canvas / context: same shape as render.test.js:15 ----
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
  const doc = { createElement() { return fakeCanvas(w, h); } };
  c.ownerDocument = doc;
  c._ctx = null;
  c.getContext = function () { return c._ctx || (c._ctx = fakeCtx(c)); };
  return c;
}

function setup(map, effects) {
  const canvas = fakeCanvas(640, 360);
  const r = Render.create(canvas, { effects: effects });
  r.reduced = false;
  // Only the crypt carries a start tile; town loads without one, as in render.test.js.
  const world = VCS.World.load(VCS.MapData.maps[map], { requireStart: map === VCS.MapData.startMap });
  const sonar = VCS.Sonar.create();
  return { r, canvas, world, sonar };
}

// ---- scene placement: first match in row-major scan, so the choice is deterministic ----
function openCell(world, x, y) {
  return !world.isSolid(x + 0.5, y + 0.5);
}
function findCell(world, pred) {
  for (let y = 0; y < world.height; y++) {
    for (let x = 0; x < world.width; x++) {
      if (pred(x, y)) return { x: x, y: y };
    }
  }
  throw new Error('no matching cell');
}
function streetCell(world) {
  // An outdoor grass cell with grass to its east: the player looks down a street (angle 0 is +x).
  return findCell(world, (x, y) => world.tileAt(x, y) === 'g' && world.tileAt(x + 1, y) === 'g' && world.kindAt(x + 0.5, y + 0.5) === 'outdoor');
}
function windowCell(world) {
  // An open cell directly west of a window tile, so the player faces the window (angle 0 looks east).
  return findCell(world, (x, y) => world.tileAt(x + 1, y) === 'w' && openCell(world, x, y));
}

// ---- canonical serialisation of one call (identical rules to figure-golden.mjs) ----
function r3(x) {
  if (Object.is(x, -0)) return 0;
  return Math.round(x * 1000) / 1000;
}
function canon(v) {
  if (typeof v === 'number') return Number.isFinite(v) ? String(r3(v)) : String(v);
  if (typeof v === 'string') return JSON.stringify(v);
  if (typeof v === 'boolean' || v === null || v === undefined) return String(v);
  return '<obj>';
}
function callLine(c) {
  return c.fn + '(' + c.args.map(canon).join(',') + ')'
    + ' s=' + canon(c.stroke) + ' a=' + canon(c.alpha) + ' lw=' + canon(c.lw);
}

// ---- FNV-1a 32-bit over UTF-8 bytes ----
function fnv1a(str) {
  const bytes = Buffer.from(str, 'utf8');
  let h = 0x811c9dc5;
  for (let i = 0; i < bytes.length; i++) {
    h ^= bytes[i];
    h = Math.imul(h, 0x01000193) >>> 0;
  }
  return h.toString(16).padStart(8, '0');
}

// The frame draws to the main context (r.ctx); r.octx is the offscreen buffer for figures and
// glow. Both logs are hashed, the main one first, so a change in either shows up.
function hashFrame(f, pl, t, opts) {
  const { r, world, sonar } = f;
  r.ctx.calls.length = 0;
  r.octx.calls.length = 0;
  let threw = null;
  try {
    Render.drawFirstPerson(r, world, pl, sonar, t, opts || {});
  } catch (e) {
    threw = String(e && e.message ? e.message : e);
  }
  const main = r.ctx.calls;
  const off = r.octx.calls;
  const log = main.map(callLine).join('\n') + '\n--offscreen--\n' + off.map(callLine).join('\n');
  return { hash: fnv1a(log), calls: main.length + off.length, threw: threw };
}

// ---- the four scenes. Each gets a fresh renderer so entries do not depend on each other. ----
const entries = [];
function scene(key, map, placeFn, t, opts) {
  const f = setup(map, 0);
  const c = placeFn(f.world);
  const pl = { x: c.x + 0.5, y: c.y + 0.5, angle: 0 };
  // Walls and floor are drawn only while a sonar pulse is live, so emit one at the player's cell
  // 0.15 s before the frame (fixed offset, so the pulse age is part of the fixture).
  VCS.Sonar.emit(f.sonar, f.world, pl.x, pl.y, t - 0.15);
  const res = hashFrame(f, pl, t, opts);
  entries.push({ key: key, map: map, x: pl.x, y: pl.y, t: t, hash: res.hash, calls: res.calls, threw: res.threw });
}

const startCell = (world) => ({ x: Math.floor(world.start.x), y: Math.floor(world.start.y) });

scene('crypt-start', 'crypt', startCell, 60.15, {});
scene('town-street', 'town', streetCell, 60.15, {});
scene('window-wall', 'town', windowCell, 60.15, {});
scene('dawn', 'town', streetCell, 340.2, { lit: 0.5 });

const out = {
  fixture: 'frame',
  v: 1,
  baseline: 'v0.15.0-pre',
  effects: 0,
  hash: 'fnv1a-32 over the fake-ctx call log, one line per call: fn(args rounded to 1e-3) s=stroke a=alpha lw=lineWidth, joined by \\n',
  source: 'drawFirstPerson at effects 0, scenes: crypt start, town street, window wall (open cell west of a w tile), dawn (town street, t and lit set for dawn)',
  count: entries.length,
  entries: entries
};

mkdirSync(dirname(OUT), { recursive: true });
writeFileSync(OUT, JSON.stringify(out, null, 2) + '\n', 'utf8');
process.stdout.write('wrote ' + entries.length + ' entries to ' + OUT + '\n');
