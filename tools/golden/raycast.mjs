#!/usr/bin/env node
// Golden fixture: ray-cast hits from the real js/raycast.js over real maps.
// Usage: node tools/golden/raycast.mjs [outPath]   (default project/tests/fixtures/raycast.json)
// Each map is flattened to a solid grid (World.isSolid at cell centres, doors closed) so the
// GDScript GridWorld needs no tile semantics. Deterministic: no clock, no randomness.

import { createRequire } from 'node:module';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { mkdirSync, writeFileSync } from 'node:fs';

const require = createRequire(import.meta.url);
const HERE = dirname(fileURLToPath(import.meta.url));
const PORT = resolve(HERE, '..', '..');
const JS = join(PORT, 'html-version', 'js');
const OUT = process.argv[2] ? resolve(process.argv[2]) : join(PORT, 'project', 'tests', 'fixtures', 'raycast.json');

for (const m of ['log', 'raycast', 'world', 'data/maps']) require(join(JS, m + '.js'));
const VCS = globalThis.VCS;
VCS.Log.setConsole(false);
const { Raycast, World, MapData } = VCS;

const FIELDS = ['hit', 'dist', 'rayDist', 'rayAngle', 'cellX', 'cellY', 'side', 'hitX', 'hitY', 'wallX', 'nx', 'ny'];
const pick = (h) => FIELDS.map((k) => (typeof h[k] === 'boolean' ? (h[k] ? 1 : 0) : h[k]));

const maps = [];
const names = ['test', 'crypt'].filter((n) => MapData.maps[n]);
for (const name of names) {
  const world = World.load(MapData.maps[name]);
  const w = world.width, h = world.height;
  let flags = '';
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) flags += world.isSolid(x + 0.5, y + 0.5) ? '1' : '0';

  const singles = [];
  for (let y = 0; y < h; y += 2) {
    for (let x = 0; x < w; x += 2) {
      if (world.isSolid(x + 0.5, y + 0.5)) continue;
      for (let a = 0; a < 16; a++) {
        const px = x + 0.5 + (a % 3) * 0.17, py = y + 0.5 + (a % 4) * 0.11;
        const ang = (a * Math.PI * 2) / 16 + 0.013 * a;
        const maxDist = a % 5 === 0 ? 3 : 24;
        singles.push({ x: px, y: py, ang, maxDist, h: pick(Raycast.castOne(world, px, py, ang, maxDist)) });
      }
    }
  }

  // Axis-aligned rays (dx or dy exactly 0 takes the Infinity branch) and a start inside a wall.
  const axis = [];
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
    if (world.isSolid(x + 0.5, y + 0.5)) { axis.push({ x: x + 0.5, y: y + 0.5, ang: 0.3, maxDist: 10, h: pick(Raycast.castOne(world, x + 0.5, y + 0.5, 0.3, 10)) }); y = h; break; }
  }
  const open = [];
  for (let y = 0; y < h && !open.length; y++) for (let x = 0; x < w; x++) if (!world.isSolid(x + 0.5, y + 0.5)) { open.push(x + 0.5, y + 0.5); break; }
  for (const ang of [Math.PI / 2, -Math.PI / 2, Math.PI]) {
    axis.push({ x: open[0], y: open[1], ang, maxDist: 30, h: pick(Raycast.castOne(world, open[0], open[1], ang, 30)) });
  }

  const fov = 66 * Math.PI / 180;
  const casts = [];
  for (let i = 0; i < 6; i++) {
    const px = open[0] + i * 0.31, py = open[1] + i * 0.07, ang = i * 1.1;
    const hits = Raycast.cast(world, px, py, ang, fov, 64, 24);
    casts.push({ x: px, y: py, angle: ang, fov, columns: 64, maxDist: 24, hits: hits.map(pick) });
  }
  maps.push({ name, w, h, flags, singles, axis, casts });
}

mkdirSync(dirname(OUT), { recursive: true });
writeFileSync(OUT, JSON.stringify({ fields: FIELDS, maps }) + '\n');
console.log('wrote ' + OUT + ' (' + maps.map((m) => m.name + ': ' + m.singles.length + ' rays').join(', ') + ')');
