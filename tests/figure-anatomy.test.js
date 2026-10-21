'use strict';
// v0.17 anatomy: the circulatory overlay must sit inside the volumetric body. For every archetype, several seeds, yaws,
// depths and every pose mode (incl. the held victim through its struggle), each vessel node must lie inside the body
// part that owns it, every vessel edge (sampled along the limb curves exactly as drawVessels draws them) must stay inside
// the silhouette, the dots must fit the wrists and ankles, and the skin flush must sit on the skin.
const test = require('node:test');
const assert = require('node:assert');

require('../js/log.js');
for (const m of ['ripple', 'raycast', 'world', 'sonar', 'people', 'struggle', 'data/maps', 'data/sounds', 'flags', 'data/vessels', 'data/archetypes', 'data/voices', 'forge', 'figure']) require('../js/' + m + '.js');
const Render = require('../js/render.js');
const VCS = globalThis.VCS;
const Figure = VCS.Figure;
const V = VCS.Vessels;
const D = VCS.VesselData;
VCS.Flags.register('vis.vessels', false, 'Circulatory pulse on villagers');
VCS.Log.setConsole(false);

function fakeCtx(canvas) {
  const calls = [];
  const state = { globalAlpha: 1, fillStyle: '#000', strokeStyle: '#000', lineWidth: 1 };
  return new Proxy({ calls, canvas }, {
    get(t, p) {
      if (p in t) return t[p];
      if (p in state) return state[p];
      return function () {
        calls.push({ fn: String(p), args: Array.prototype.slice.call(arguments), fill: state.fillStyle, alpha: state.globalAlpha });
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
  const c = { width: w, height: h };
  c.ownerDocument = { createElement() { return fakeCanvas(w, h); } };
  c._ctx = null;
  c.getContext = function () { return c._ctx || (c._ctx = fakeCtx(c)); };
  return c;
}
const R = Render.create(fakeCanvas(640, 360), { effects: 2 });
R.reduced = false;

function lookOf(arch, seed) {
  return VCS.Forge.generate({ archetype: arch, seed: seed }, { stateSeed: 99, index: seed, accOffset: 3 }).person.look;
}

// Pose one echo through the real renderer (vol path) and snapshot slots + pose.
function posed(look, o, lock) {
  const e = Object.assign({ x: 2.2, y: 0, angle: Math.PI, lookAngle: 0, phase: 0, phaseRate: 0, personId: 5, t: 0, strength: 1, zMin: 0, zMax: 2, look: look, fade: 3 }, o);
  R.octx.calls.length = 0;
  Render.drawSolo(R, e, { fx: 2, quality: 3, t: 3.3, age: -1, lock: lock || null });
  const d = Render.poseDebug();
  return { P: { X: Float32Array.from(d.X), Y: Float32Array.from(d.Y), Z: Float32Array.from(d.Z) }, pose: Object.assign({}, d.pose), look: look };
}

// Owning parts per artery id (veins share the anchors).
const OWN = {
  heart: ['torso'], arch: ['torso'], aorta: ['torso'], carotid: ['neck', 'torso'], temporal: ['head'],
  subclavL: ['torso', 'arm'], subclavR: ['torso', 'arm'], brachialL: ['arm'], brachialR: ['arm'],
  radialL: ['hand', 'arm'], radialR: ['hand', 'arm'], femoralL: ['torso', 'leg'], femoralR: ['torso', 'leg'],
  poplitealL: ['leg'], poplitealR: ['leg'], pedalL: ['foot', 'leg'], pedalR: ['foot', 'leg']
};

const MODES = [
  ['idle', {}], ['wary', { wary: true }], ['chat', { chat: true }], ['walk', { phase: 0.4 }], ['walk2', { phase: 2.0 }], ['walk3', { phase: 3.7 }],
  ['flee', { mode: 'flee', phase: 0.9 }], ['flee2', { mode: 'flee', phase: 4.4 }], ['startle', { mode: 'startle', modeAge: 0.1 }],
  ['startle2', { mode: 'startle', modeAge: 2 }], ['cower', { mode: 'cower' }], ['dazed', { mode: 'dazed' }], ['seated', { sit: true }], ['fed', { mode: 'fed' }]
];
const LOCKS = [{ k: 0.1, age: 0.4 }, { k: 0.1, age: 1.6 }, { k: 0.4, age: 5 }, { k: 0.5, age: 7, rs: 1 }, { k: 0.95, age: 12 }];
const YAWS = [Math.PI, Math.PI * 0.75, Math.PI * 0.5, Math.PI * 0.25, 0.02, -Math.PI * 0.6];

/** ANAT_DUMP=<file> appends every failure (debugging aid). */
function dump(fails) {
  if (process.env.ANAT_DUMP && fails.length) require('node:fs').appendFileSync(process.env.ANAT_DUMP, fails.join('\n') + '\n');
}

const PT = { x: 0, y: 0 };
const A = { x: 0, y: 0 };
const B = { x: 0, y: 0 };
const C = { x: 0, y: 0 };

function checkFigure(f, tag, fails) {
  const nodes = D.arteries;
  for (const n of nodes) {
    V.point(n, f.P.X, f.P.Y, PT);
    const kinds = Figure.hitAll(f.P, f.pose, f.look, PT.x, PT.y).split(',');
    if (!OWN[n.id].some((k) => kinds.indexOf(k) >= 0)) fails.push(tag + ' node ' + n.id + ' in [' + kinds.join(',') + ']');
  }
  for (const ed of V.edges(false)) {
    V.point(nodes[ed.p], f.P.X, f.P.Y, A);
    V.point(nodes[ed.i], f.P.X, f.P.Y, B);
    const curved = V.edgeCtrl(nodes[ed.p], nodes[ed.i], f.P.X, f.P.Y, C);
    for (let s = 0.1; s < 0.95; s += 0.2) {
      V.edgeAt(A, curved ? C : null, B, s, PT);
      if (!Figure.hit(f.P, f.pose, f.look, PT.x, PT.y)) fails.push(tag + ' edge ' + nodes[ed.p].id + '->' + nodes[ed.i].id + ' s=' + s.toFixed(1) + ' outside');
    }
  }
}

test('Figure.parts gives closed outlines and contains/hit agree with them', () => {
  const f = posed(lookOf('patron', 1), {});
  const out = [];
  const n = Figure.parts(f.P, f.pose, f.look, out);
  assert.strictEqual(n, 11);
  for (let i = 0; i < n; i++) {
    assert.ok(out[i].n >= 12 && out[i].n <= Figure.MAX_POINTS, out[i].kind + ' points ' + out[i].n);
    let cx = 0; let cy = 0;
    for (let j = 0; j < out[i].n; j++) { cx += out[i].px[j]; cy += out[i].py[j]; }
    assert.ok(isFinite(cx) && isFinite(cy));
  }
  // Head centre is in the head, a point far away is in nothing.
  assert.strictEqual(Figure.hit(f.P, f.pose, f.look, f.P.X[0], f.P.Y[0]), 'head');
  assert.strictEqual(Figure.hit(f.P, f.pose, f.look, -1e4, -1e4), '');
  assert.strictEqual(Figure.hit(null, null, null, 1, 1), '');
  const sp = { x0: 0, x1: 0 };
  assert.ok(Figure.spanAt(f.P, f.pose, f.look, f.P.Y[14], sp) && sp.x1 > sp.x0);
  assert.strictEqual(Figure.spanAt(f.P, f.pose, f.look, -1e4, sp), false);
});

test('vessel nodes sit in their body parts and edges stay inside the body: every archetype, yaw and pose mode', () => {
  const fails = [];
  let figs = 0;
  for (const arch of VCS.Forge.list()) {
    for (const seed of [1, 2, 3]) {
      const look = lookOf(arch, seed);
      for (const yaw of YAWS) {
        for (const m of MODES) {
          const f = posed(look, Object.assign({ angle: yaw }, m[1]));
          assert.ok(f.pose.vol, 'vol figure ' + arch);
          checkFigure(f, arch + '/' + seed + '/' + yaw.toFixed(2) + '/' + m[0], fails);
          figs++;
        }
      }
      for (const lk of LOCKS) {
        const f = posed(look, { x: 1.25, angle: Math.PI }, lk);
        checkFigure(f, arch + '/' + seed + '/held k' + lk.k + ' g' + lk.age, fails);
        figs++;
      }
    }
  }
  assert.ok(figs > 3000, 'figures ' + figs);
  dump(fails);
  assert.deepStrictEqual(fails.slice(0, 25), [], fails.length + ' failures');
});

test('every body type, head, outfit, stoop, shoulder, build and height keeps the vessels inside', () => {
  const fails = [];
  const E = VCS.ArchetypeData.LOOK_ENUMS;
  const base = Object.assign({}, lookOf('patron', 1), { outfit: 'plain', extra: 'none', roleHat: 'none' });
  const variants = [];
  for (const body of E.body) for (const head of E.head) variants.push({ body, head });
  for (const outfit of E.outfit) variants.push({ outfit, hem: 1 });
  for (const extra of E.extra) variants.push({ extra });
  for (const height of [0.5, 0.58, 0.66, 0.8, 1, 1.2]) for (const build of [0.7, 1, 1.4]) variants.push({ height, build });
  for (const stoop of [0, 0.2, 0.4]) for (const shoulder of [0.8, 1.25]) variants.push({ stoop, shoulder });
  for (const v of variants) {
    const look = Object.assign({}, base, v);
    for (const yaw of [Math.PI, Math.PI * 0.6, 0.3]) {
      for (const m of [MODES[0], MODES[4], MODES[10], MODES[12], MODES[13]]) {
        checkFigure(posed(look, Object.assign({ angle: yaw }, m[1])), JSON.stringify(v) + '/' + yaw.toFixed(2) + '/' + m[0], fails);
      }
    }
  }
  dump(fails);
  assert.deepStrictEqual(fails.slice(0, 25), [], fails.length + ' failures');
});

test('vessel dots fit inside the wrists and ankles on volumetric bodies; line figures keep the v0.16 size', () => {
  const fails = [];
  for (const arch of VCS.Forge.list()) {
    const f = posed(lookOf(arch, 2), { angle: Math.PI * 0.8 });
    const rad = Render.vesselRad(R, f.P.Y, true);
    assert.ok(rad < Render.vesselRad(R, f.P.Y, false), 'vol dots are smaller');
    for (const id of ['radialL', 'radialR', 'pedalL', 'pedalR', 'brachialL', 'poplitealR', 'carotid']) {
      V.point(V.byId(id), f.P.X, f.P.Y, PT);
      for (let k = 0; k < 8; k++) {
        const a = k * Math.PI / 4;
        if (!Figure.hit(f.P, f.pose, f.look, PT.x + Math.cos(a) * rad, PT.y + Math.sin(a) * rad)) { fails.push(arch + ' ' + id + ' dot edge ' + k); break; }
      }
    }
  }
  assert.deepStrictEqual(fails, []);
  const Y = new Float32Array(24); Y[0] = 20; Y[8] = 220; Y[9] = 220;
  assert.strictEqual(Render.vesselRad({ wscale: 1 }, Y, false), 200 * 0.016 * 0.9);
});

test('skin flush ellipses sit on the face, neck and wrists', () => {
  const fails = [];
  for (const arch of VCS.Forge.list()) {
    for (const yaw of [Math.PI, Math.PI * 0.6]) {
      const f = posed(lookOf(arch, 3), { angle: yaw });
      const c = fakeCtx({});
      assert.strictEqual(Figure.drawFlush(c, f.P, f.pose, [1, 1, 1, 1], { look: { skin: 1 }, alpha: 1 }), true);
      const els = c.calls.filter((k) => k.fn === 'ellipse');
      assert.strictEqual(els.length, 4);
      els.forEach((e, i) => {
        const [x, y, rx, ry, rot] = e.args;
        for (let k = 0; k < 8; k++) {
          const a = k * Math.PI / 4;
          const px = x + Math.cos(a) * rx * 0.85 * Math.cos(rot) - Math.sin(a) * ry * 0.85 * Math.sin(rot);
          const py = y + Math.cos(a) * rx * 0.85 * Math.sin(rot) + Math.sin(a) * ry * 0.85 * Math.cos(rot);
          if (!Figure.hit(f.P, f.pose, f.look, px, py)) { fails.push(arch + ' flush ' + i + ' yaw ' + yaw.toFixed(2)); break; }
        }
      });
    }
  }
  assert.deepStrictEqual(fails, []);
});

test('a child reads as a child: narrower shoulders and a bigger head for its height', () => {
  const adult = posed(Object.assign({}, lookOf('patron', 1), { height: 1 }), {});
  const kid = posed(lookOf('child', 1), {});
  const ratio = (f) => {
    const out = [];
    const n = Figure.parts(f.P, f.pose, f.look, out);
    let head = null; let torso = null;
    for (let i = 0; i < n; i++) { if (out[i].kind === 'head') head = out[i]; if (out[i].kind === 'torso') torso = out[i]; }
    const h = Math.abs(f.P.Y[8] - f.P.Y[0]);
    return { head: (head.y1 - head.y0) / h, sh: Math.abs(f.P.X[2] - f.P.X[3]) / h };
  };
  const a = ratio(adult);
  const k = ratio(kid);
  assert.ok(k.head > a.head * 1.12, 'head ' + k.head + ' vs ' + a.head);
  assert.ok(k.sh / k.head < a.sh / a.head * 0.85, 'shoulders vs head ' + JSON.stringify({ k, a }));
});
