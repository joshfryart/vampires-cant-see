#!/usr/bin/env node
// Golden fixture: sonar emit / scan / sample2 / pickReflectors from the real js/sonar.js on the `test` and `crypt` maps.
// Usage: node tools/golden/sonar.mjs [outPath]   (default project/tests/fixtures/sonar.json)
// Large arrays are thinned: vis is stored every 5th ray plus its sum; vmat/vnorm as digit strings.
// Deterministic: no clock, no randomness.

import { createRequire } from 'node:module';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { mkdirSync, writeFileSync } from 'node:fs';

const require = createRequire(import.meta.url);
const HERE = dirname(fileURLToPath(import.meta.url));
const PORT = resolve(HERE, '..', '..');
const JS = join(resolve(PORT, '..'), 'js');
const OUT = process.argv[2] ? resolve(process.argv[2]) : join(PORT, 'project', 'tests', 'fixtures', 'sonar.json');

for (const m of ['log', 'raycast', 'world', 'data/maps', 'data/sounds', 'sonar']) require(join(JS, m + '.js'));
const VCS = globalThis.VCS;
VCS.Log.setConsole(false);
const { Sonar, World, MapData } = VCS;

const pulseOut = (p) => {
  const thin = [];
  let sum = 0;
  for (let i = 0; i < p.vis.length; i++) { sum += p.vis[i]; if (i % 5 === 0) thin.push(p.vis[i]); }
  return {
    x: p.x, y: p.y, z: p.z, t0: p.t0, range: p.range, fade: p.fade, speed: p.speed, strength: p.strength,
    gen: p.gen, kind: p.kind, mat: p.mat || '', facing: typeof p.facing === 'number' ? p.facing : null,
    n: p.vis.length, visThin: thin, visSum: sum,
    vmat: Array.from(p.vmat).join(''), vnorm: Array.from(p.vnorm).map((v) => (v === 255 ? 'x' : String(v))).join(''),
    vbeamSum: p.vbeam ? Array.from(p.vbeam).reduce((a, b) => a + b, 0) : null,
    vbeamThin: p.vbeam ? Array.from(p.vbeam).filter((_, i) => i % 5 === 0) : null
  };
};

const scenes = [];
const SCENES = [
  { map: 'test', x: 2.5, y: 3.5, facing: 0.4, opts: {} },
  { map: 'test', x: 15.2, y: 8.6, facing: 3.0, opts: { bounces: 1 } },
  { map: 'crypt', x: null, y: null, facing: 1.9, opts: {} }
];
const TIMES = [0, 0.1, 0.3, 0.6, 1.0, 1.5, 2.5, 4.0];

for (const sc of SCENES) {
  const world = World.load(MapData.maps[sc.map]);
  const x = sc.x === null ? world.start.x : sc.x;
  const y = sc.y === null ? world.start.y : sc.y;
  const s = Sonar.create({});
  const t0 = 1.25;
  const ok = Sonar.emit(s, world, x, y, t0, Object.assign({ facing: sc.facing }, sc.opts));
  const again = Sonar.emit(s, world, x, y, t0 + 0.5, { facing: sc.facing }); // cooling down: false
  const cd = Sonar.cooldownLeft(s, t0 + 0.3);
  const primary = s.lastPulse;

  const pts = [];
  for (let py = 0.37; py < world.height; py += 1.0) {
    for (let px = 0.37; px < world.width; px += 1.0) {
      const row = { x: px, y: py, t: [] };
      for (const dt of TIMES) {
        const t = t0 + dt;
        const out = [0, 0, 0, 0];
        Sonar.sample2(s, px, py, t, out);
        const b = Sonar.brightnessAt(s, px, py, t);
        const age = Sonar.ageAt(s, px, py, t);
        row.t.push([out[0], out[1], out[2], out[3], b, age]);
      }
      pts.push(row);
    }
  }
  const bands = [];
  for (const dt of [0.2, 0.5, 1.0]) {
    const o = [0, 0];
    const hit = Sonar.heightBand(primary, t0 + dt, x + 1.1, y + 0.4, o);
    bands.push({ dt, hit, o: hit ? [o[0], o[1]] : null });
  }
  // pickReflectors is not exported; the bounce children made by emit (gen 1/2) exercise it.
  const extra = (function () {
    const A = [];
    for (let i = 0; i < 24; i++) {
      const ang = (i / 24) * Math.PI * 2 + 0.07;
      const o = {};
      Sonar.hitInfo(primary, ang, o);
      A.push({ ang, hit: o.hit, dist: o.dist, mat: o.mat, rough: o.rough, nx: o.nx, ny: o.ny, cosInc: o.cosInc, beam: o.beam });
    }
    const se = (f) => { const e = Sonar.strongestEcho(primary, f); return e ? { dist: e.dist, angle: e.angle, theta: e.theta, mat: e.mat, rough: e.rough, level: e.level, cosInc: e.cosInc } : null; };
    const arcs = [];
    for (const dt of [0.3, 0.7, 1.4]) for (const [qx, qy] of [[x + 2, y], [x, y + 3], [x - 1.5, y - 1.5]]) {
      const out = new Float32Array(8);
      const n = Sonar.wallArc(primary, t0 + dt, qx, qy, 4, out);
      arcs.push({ dt, qx, qy, n, out: Array.from(out).map((v) => (Number.isNaN(v) ? null : v)) });
    }
    return { hitInfo: A, strongest: se(undefined), strongestFacing: se(1.0), enclosure: Sonar.enclosure(primary), arcs };
  })();
  scenes.push({
    extra,
    map: sc.map, x, y, facing: sc.facing, opts: sc.opts, t0, emitOk: ok, emitAgain: again, cooldownLeft: cd,
    nearest: Sonar.nearestDist(primary), pulseCount: s.pulses.length,
    pulses: s.pulses.map(pulseOut),
    visibleFrom: [[x + 2, y], [x, y + 3], [x - 1.5, y - 1.5]].map(([qx, qy]) => ({ x: qx, y: qy, v: Sonar.visibleFrom(primary, qx, qy), lit: Sonar.litAt(primary, qx, qy) })),
    ring: [0.1, 0.7].map((dt) => Sonar.ringRadius(primary, t0 + dt)),
    bands, points: pts, times: TIMES,
    echoDelay: [0.5, 3, 9.9].map((d) => Sonar.echoDelay(d)),
    pruneAfter: (function () { Sonar.prune(s, t0 + 20); return s.pulses.length; })()
  });
}

mkdirSync(dirname(OUT), { recursive: true });
writeFileSync(OUT, JSON.stringify({ scenes }) + '\n');
console.log('wrote ' + OUT + ' (' + scenes.map((s) => s.map + ': ' + s.pulseCount + ' pulses, ' + s.points.length + ' pts').join(', ') + ')');
