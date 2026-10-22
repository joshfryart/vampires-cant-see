#!/usr/bin/env node
// Line-figure golden fixture generator for the v0.14 figure split (job B0).
// Captures today's Render.drawFirstPerson call log for the matrix of the existing
// test 'every mode and look draws' (render.test.js:231), plus the locked victim
// (feedLock), so the render.js split (B1) can be checked for parity.
// Usage: node tools/figure-golden.mjs [outPath]
//   default outPath: tests/fixtures/figure-line-v0140.json
// Deterministic: same code in, byte-identical JSON out. No randomness, no clock.

import { createRequire } from 'node:module';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { mkdirSync, writeFileSync } from 'node:fs';

const require = createRequire(import.meta.url);
const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const JS = join(ROOT, 'js');

// Load order mirrors render.test.js (render-feed describe), plus the flags and vessels
// modules that the same merged test file registers before the tests run.
const LOAD = ['log', 'ripple', 'raycast', 'world', 'sonar', 'people', 'struggle', 'data/maps', 'data/sounds'];
for (const m of LOAD) require(join(JS, m + '.js'));
require(join(JS, 'flags.js'));
require(join(JS, 'data', 'vessels.js'));
const Render = require(join(JS, 'render.js'));
const VCS = globalThis.VCS;
VCS.Flags.register('vis.vessels', false, 'Circulatory pulse on villagers');
VCS.Log.setConsole(false);

const OUT = process.argv[2] ? resolve(process.argv[2]) : join(ROOT, 'tests', 'fixtures', 'figure-line-v0140.json');

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

// Same setup as render.test.js setup(), but one fresh renderer per entry so that
// each hash depends only on its own input (no state carried between entries).
function setup() {
  const canvas = fakeCanvas(640, 360);
  const r = Render.create(canvas, {});
  r.reduced = false;
  const map = VCS.MapData.maps[VCS.MapData.startMap];
  const world = VCS.World.load(map);
  const sonar = VCS.Sonar.create();
  return { r, canvas, world, sonar };
}
const player = { x: 5.5, y: 5.5, angle: 0 };
function echo(id, t) {
  return { x: 7.5, y: 5.5, angle: Math.PI, lookAngle: 0, phase: 0, personId: id, t: t, strength: 1, zMin: 0, zMax: 2, look: VCS.People.makeLook ? VCS.People.makeLook(id) : undefined, fade: 3 };
}

// ---- canonical serialisation of one call ----
function r3(x) {
  if (Object.is(x, -0)) return 0;
  return Math.round(x * 1000) / 1000;
}
function canon(v) {
  if (typeof v === 'number') return Number.isFinite(v) ? String(r3(v)) : String(v);
  if (typeof v === 'string') return JSON.stringify(v);
  if (typeof v === 'boolean' || v === null || v === undefined) return String(v);
  return '<obj>'; // gradients, Path2D stubs, canvases: identity is not part of the contract
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

function hashDraw(f, people, opts) {
  const { r, world, sonar } = f;
  r.octx.calls.length = 0;
  let threw = null;
  try {
    Render.drawFirstPerson(r, world, player, sonar, 60.15, Object.assign({ people: people }, opts || {}));
  } catch (e) {
    threw = String(e && e.message ? e.message : e);
  }
  const calls = r.octx.calls;
  const log = calls.map(callLine).join('\n');
  return { hash: fnv1a(log), calls: calls.length, threw: threw };
}

const modes = ['path', 'startle', 'flee', 'cower', 'dazed', 'grapple', 'fed', 'bogus', undefined];
const accs = VCS.People.ACCESSORIES;
const entries = [];

// 1. Matrix: reduced x quality x mode x accessory, as render.test.js:231 enumerates.
for (const reduced of [false, true]) {
  for (const q of [0, 1, 3]) {
    for (let i = 0; i < modes.length; i++) {
      for (let a = 0; a < accs.length; a++) {
        const f = setup();
        f.r.reduced = reduced;
        f.r.quality = q;
        const look = VCS.People.makeLook(9, a * 7 + i, a);
        look.acc = accs[a];
        const e = Object.assign(echo(i, 60), { mode: modes[i], sit: i % 2 === 0, wary: i % 3 === 0, modeAge: 0.1, look: look });
        const res = hashDraw(f, { echoes: [e] });
        entries.push({
          key: 'matrix/reduced=' + reduced + '/q=' + q + '/mode=' + (modes[i] === undefined ? 'undefined' : modes[i]) + '/acc=' + accs[a],
          hash: res.hash,
          calls: res.calls,
          threw: res.threw
        });
      }
    }
  }
}

// 2. Locked victim (feedLock), as render.test.js:75-97: victim id 7 among a bystander id 8.
for (const reduced of [false, true]) {
  for (const q of [0, 1, 3]) {
    const f = setup();
    f.r.reduced = reduced;
    f.r.quality = q;
    const res = hashDraw(f, { echoes: [echo(7, 100), echo(8, 100)] }, { feedLock: { id: 7, k: 0.5, age: 1 } });
    entries.push({ key: 'feedLock/reduced=' + reduced + '/q=' + q, hash: res.hash, calls: res.calls, threw: res.threw });
  }
}

const out = {
  fixture: 'figure-line',
  v: 1,
  baseline: 'v0.14.0-pre',
  hash: 'fnv1a-32 over the fake-ctx call log, one line per call: fn(args rounded to 1e-3) s=stroke a=alpha lw=lineWidth, joined by \\n',
  source: 'render.test.js:231 matrix (reduced x quality x mode x accessory) plus feedLock victim',
  count: entries.length,
  entries: entries
};

mkdirSync(dirname(OUT), { recursive: true });
writeFileSync(OUT, JSON.stringify(out, null, 2) + '\n', 'utf8');
process.stdout.write('wrote ' + entries.length + ' entries to ' + OUT + '\n');
