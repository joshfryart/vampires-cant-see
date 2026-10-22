// Shared harness for the render golden fixtures: a recording fake 2D context (same canonical log as figure.mjs), an
// in-memory copy of js/render.js with chosen private functions exported (the JS file on disk is never touched), and the
// scene runner that fills the per-column depth buffer from a ray cast like drawWalls does.

import { createRequire } from 'node:module';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

const require = createRequire(import.meta.url);
const HERE = dirname(fileURLToPath(import.meta.url));
export const PORT = resolve(HERE, '..', '..', '..');
export const JS = join(resolve(PORT, '..'), 'js');

export function fakeCtx(canvas) {
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

export function fakeCanvas(w, h) {
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
export const callLine = (c) => c.fn + '(' + c.args.map(canon).join(',') + ') s=' + canon(c.stroke) + ' a=' + canon(c.alpha) + ' lw=' + canon(c.lw);
export function fnv1a(str) {
  const bytes = Buffer.from(str, 'utf8');
  let h = 0x811c9dc5;
  for (let i = 0; i < bytes.length; i++) { h ^= bytes[i]; h = Math.imul(h, 0x01000193) >>> 0; }
  return h.toString(16).padStart(8, '0');
}

/** Load the JS modules a render scene needs, then render.js with `names` exported as Render.__x. */
export function loadRender(names, extraModules = []) {
  for (const m of ['log', 'ripple', 'raycast', 'world', 'sonar', 'data/maps', 'data/sounds'].concat(extraModules)) require(join(JS, m + '.js'));
  const VCS = globalThis.VCS;
  VCS.Log.setConsole(false);
  let src = readFileSync(join(JS, 'render.js'), 'utf8');
  if (!src.includes('VCS.Render = Render;')) throw new Error('render.js layout changed');
  src = src.replace('VCS.Render = Render;', 'Render.__x = { ' + names.join(', ') + ' };\n  VCS.Render = Render;');
  vm.runInThisContext(src, { filename: 'render.js' });
  return { VCS, Render: VCS.Render, X: VCS.Render.__x };
}

export const FOV = 66 * Math.PI / 180;
export const TAN = Math.tan(FOV / 2);

/**
 * Build one scene: world, sonar with pulses, renderer with the depth buffer from a ray cast. Returns {world, sonar, r, hits}.
 * spec: {map, player, doors, pulses [{k:'ping'|'sound', x, y, t0, facing, opts}], t, quality, reduced, fx, matDetail}
 */
export function buildScene(H, spec) {
  const { VCS, Render } = H;
  const def = VCS.MapData.maps[spec.map];
  const world = VCS.World.load(def, { requireStart: false });
  for (const d of spec.doors || []) world.setDoor(d[0], d[1], true);
  const sonar = VCS.Sonar.create({});
  for (const p of spec.pulses) {
    if (p.k === 'ping') VCS.Sonar.emit(sonar, world, p.x, p.y, p.t0, { facing: p.facing });
    else VCS.Sonar.emitSound(sonar, world, p.x, p.y, p.t0, p.opts);
  }
  const r = Render.create(fakeCanvas(640, 360), {});
  r.reduced = !!spec.reduced;
  r.quality = spec.quality === undefined ? 3 : spec.quality;
  r.fx = spec.fx === undefined ? 0 : spec.fx;
  if (spec.matDetail === false) r.matDetail = false;
  r.horizon = r.oh / 2;
  r.boilOn = !r.reduced && r.quality >= 2;
  r.bf = r.boilOn ? VCS.Ripple.boilFrame(spec.t) : 0;
  const hits = VCS.Raycast.cast(world, spec.player.x, spec.player.y, spec.player.angle, FOV, r.cols, 16);
  for (let i = 0; i < r.cols; i++) r.zbuf[i] = hits[i].dist;
  return { world, sonar, r, hits };
}
