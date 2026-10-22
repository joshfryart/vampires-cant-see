#!/usr/bin/env node
// Golden fixture (sprites.json): draw-call logs of drawSprite (crypt, safe, open doors) and drawProps from the real
// js/render.js, on all maps, for several player poses, pulses and times. render.js is evaluated from an in-memory copy with
// its private draw functions exported; the JS file on disk is never touched.
// Usage: node tools/golden/sprites.mjs [outPath]   (default project/tests/fixtures/sprites.json)

import { createRequire } from 'node:module';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { mkdirSync, writeFileSync, readFileSync } from 'node:fs';
import vm from 'node:vm';

const require = createRequire(import.meta.url);
const HERE = dirname(fileURLToPath(import.meta.url));
const PORT = resolve(HERE, '..', '..');
const JS = join(resolve(PORT, '..'), 'js');
const OUT = process.argv[2] ? resolve(process.argv[2]) : join(PORT, 'project', 'tests', 'fixtures', 'sprites.json');

for (const m of ['log', 'ripple', 'raycast', 'world', 'sonar', 'data/maps', 'data/sounds']) require(join(JS, m + '.js'));
const VCS = globalThis.VCS;
VCS.Log.setConsole(false);
let src = readFileSync(join(JS, 'render.js'), 'utf8');
if (!src.includes('VCS.Render = Render;')) throw new Error('render.js layout changed');
src = src.replace('VCS.Render = Render;', 'Render.__x = { drawSprite, drawProps, drawWalls };\n  VCS.Render = Render;');
vm.runInThisContext(src, { filename: 'render.js' });
const Render = VCS.Render;
const X = Render.__x;
const { World, MapData, Sonar, Raycast } = VCS;

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
const callLine = (c) => c.fn + '(' + c.args.map(canon).join(',') + ') s=' + canon(c.stroke) + ' a=' + canon(c.alpha) + ' lw=' + canon(c.lw);
function fnv1a(str) {
  const bytes = Buffer.from(str, 'utf8');
  let h = 0x811c9dc5;
  for (let i = 0; i < bytes.length; i++) { h ^= bytes[i]; h = Math.imul(h, 0x01000193) >>> 0; }
  return h.toString(16).padStart(8, '0');
}

const FOV = 66 * Math.PI / 180;
const TAN = Math.tan(FOV / 2);
const scenes = [];

function scene(key, spec) {
  // spec: {map, player {x,y,angle}, pulses: [{k:'ping'|'sound', x,y,t0,opts}], t, quality, reduced}
  const def = MapData.maps[spec.map];
  const world = World.load(def, { requireStart: false });
  for (const d of spec.doors || []) world.setDoor(d[0], d[1], true);
  const sonar = Sonar.create({});
  for (const p of spec.pulses) {
    if (p.k === 'ping') Sonar.emit(sonar, world, p.x, p.y, p.t0, { facing: p.facing });
    else Sonar.emitSound(sonar, world, p.x, p.y, p.t0, p.opts);
  }
  const canvas = fakeCanvas(640, 360);
  const r = Render.create(canvas, {});
  r.reduced = !!spec.reduced;
  r.quality = spec.quality === undefined ? 3 : spec.quality;
  r.horizon = r.oh / 2;
  r.boilOn = !r.reduced && r.quality >= 2;
  r.bf = r.boilOn ? VCS.Ripple.boilFrame(spec.t) : 0;
  const hits = Raycast.cast(world, spec.player.x, spec.player.y, spec.player.angle, FOV, r.cols, 16);
  for (let i = 0; i < r.cols; i++) r.zbuf[i] = hits[i].dist;
  const ctx = r.octx;
  ctx.calls.length = 0;
  let drawn = 0;
  for (const kind of ['crypt', 'safe', 'doors']) for (const spot of (world.spots[kind] || [])) if (X.drawSprite(r, world, spec.player, sonar, spec.t, kind, spot, TAN)) drawn++;
  const nSprite = ctx.calls.length;
  drawn += X.drawProps(r, world, spec.player, sonar, spec.t, TAN);
  const lines = ctx.calls.map(callLine);
  const entry = { key, spec, zbuf: Array.from(r.zbuf), hash: fnv1a(lines.join('\n')), calls: lines.length, spriteCalls: nSprite, drawn };
  if (scenes.length < 4) entry.log = lines;
  scenes.push(entry);
}

const poses = {
  test: [[3.5, 3.5, 0], [8.5, 4.5, 0.4], [12.5, 2.5, 3.14], [15.5, 7.5, -1.2], [5.5, 6.5, 1.9]],
  crypt: null,
  town: [[16.5, 9.5, 0], [24.5, 6.5, 1.0], [30.5, 10.5, 3.0], [12.5, 8.5, -0.5], [20.5, 14.5, 4.5], [17.5, 3.5, 2.2]]
};
for (const map of Object.keys(MapData.maps)) {
  const def = MapData.maps[map];
  const world = World.load(def, { requireStart: false });
  let list = poses[map];
  if (!list) {
    const s = world.start || { x: 3.5, y: 3.5 };
    list = [[s.x, s.y, 0], [s.x, s.y, 1.5708], [s.x, s.y, 3.14159], [s.x, s.y, 4.7]];
  }
  const doorOpen = (world.spots.doors || []).slice(0, 3).map((d) => [Math.floor(d.x), Math.floor(d.y)]);
  for (let pi = 0; pi < list.length; pi++) {
    const [x, y, a] = list[pi];
    if (world.isSolid(x, y)) continue;
    for (const dt of [0.03, 0.1, 0.2, 0.35, 0.6, 1.0, 1.7, 2.6]) {
      const t0 = 1;
      scene('A/' + map + '/p' + pi + '/dt=' + dt, { map, player: { x, y, angle: a }, doors: doorOpen, pulses: [{ k: 'ping', x, y, t0, facing: a }], t: t0 + dt });
    }
    // second source: a sound from a prop or spot, plus reduced / quality variants
    const src2 = (world.props && world.props[0]) || { x: x + 1, y };
    scene('B/' + map + '/p' + pi, { map, player: { x, y, angle: a }, doors: doorOpen, pulses: [{ k: 'ping', x, y, t0: 1, facing: a }, { k: 'sound', x: src2.x, y: src2.y, t0: 1.1, opts: { kind: 'door', range: 7, strength: 0.7, bounces: 1, z: 0.4 } }], t: 1.4 });
    scene('C/' + map + '/p' + pi + '/q1', { map, player: { x, y, angle: a }, doors: doorOpen, pulses: [{ k: 'ping', x, y, t0: 1, facing: a }], t: 1.25, quality: 1 });
    scene('C/' + map + '/p' + pi + '/red', { map, player: { x, y, angle: a }, doors: doorOpen, pulses: [{ k: 'ping', x, y, t0: 1, facing: a }], t: 1.25, reduced: true });
  }
}
mkdirSync(dirname(OUT), { recursive: true });
writeFileSync(OUT, JSON.stringify({ fixture: 'sprites-godot', count: scenes.length, scenes }) + '\n');
console.log('wrote ' + OUT + ' (' + scenes.length + ' scenes, ' + scenes.filter((s) => s.drawn).length + ' drawn, ' + scenes.reduce((a, s) => a + s.calls, 0) + ' calls)');
