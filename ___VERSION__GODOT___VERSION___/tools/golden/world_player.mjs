#!/usr/bin/env node
// Golden fixture: World.load queries and Player.update from the real js/world.js and js/player.js.
// Usage: node tools/golden/world_player.mjs [outPath]   (default project/tests/fixtures/world_player.json)
// Deterministic: no clock, no randomness.

import { createRequire } from 'node:module';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { mkdirSync, writeFileSync } from 'node:fs';

const require = createRequire(import.meta.url);
const HERE = dirname(fileURLToPath(import.meta.url));
const PORT = resolve(HERE, '..', '..');
const JS = join(resolve(PORT, '..'), 'js');
const OUT = process.argv[2] ? resolve(process.argv[2]) : join(PORT, 'project', 'tests', 'fixtures', 'world_player.json');

for (const m of ['log', 'raycast', 'world', 'data/maps', 'data/sounds', 'player']) require(join(JS, m + '.js'));
const VCS = globalThis.VCS;
VCS.Log.setConsole(false);
const { World, MapData, Player } = VCS;

const worlds = [];
for (const name of Object.keys(MapData.maps)) {
  const def = MapData.maps[name];
  const w = World.load(def, { requireStart: name === MapData.startMap || name === 'test' });
  const pts = [];
  const step = w.width * w.height > 1000 ? 1.7 : 0.53; // thin the big town map
  for (let y = -0.6; y < w.height + 0.6; y += step) {
    for (let x = -0.6; x < w.width + 0.6; x += step) {
      pts.push([x, y, w.tileAt(x, y), w.isSolid(x, y) ? 1 : 0, w.materialAt(x, y), w.blocks(x, y, 0.2) ? 1 : 0, w.blocks(x, y, 0.45) ? 1 : 0, w.lightAt(x, y), w.outerAt(x, y), w.kindAt(x, y), w.zoneAt(x, y) || '', w.isLinkDoor(x, y) ? 1 : 0]);
    }
  }
  // Open every door, then re-query the door cells' neighbourhood.
  const doorCells = [];
  for (let r = 0; r < w.height; r++) for (let c = 0; c < w.width; c++) if (w.doorAt(c, r) || 'DG'.includes(w.tileAt(c + 0.5, r + 0.5))) doorCells.push([c, r]);
  const lightsBefore = w.lightSources().length;
  const doorsClosed = doorCells.map(([c, r]) => [c, r, w.isSolid(c + 0.5, r + 0.5) ? 1 : 0, w.setDoor(c, r, true) ? 1 : 0, w.isSolid(c + 0.5, r + 0.5) ? 1 : 0, w.isDoorOpen(c, r) ? 1 : 0]);
  const arrivals = Object.keys(w.doorsById).map((id) => ({ id, a: w.arrival(id) }));
  worlds.push({
    name, width: w.width, height: w.height, kind: w.kind, floor: w.floor, start: w.start, spots: w.spots,
    propCount: w.props.length, props: w.props.map((p) => [p.type, p.x, p.y, p.solid ? 1 : 0]),
    lightCount: lightsBefore, pts, doorsClosed, arrivals,
    lightAfter: (function () { const out = []; for (let y = 0; y < w.height; y += 2) for (let x = 0; x < w.width; x += 2) out.push(w.lightAt(x + 0.5, y + 0.5)); return out; })()
  });
}

// Player: scripted input sequences on the test map and the crypt.
const players = [];
const patterns = [
  { forward: 1, strafe: 0, turn: 0, mouseDx: 0 }, { forward: 1, strafe: 1, turn: 0, mouseDx: 12 },
  { forward: 0, strafe: -1, turn: 1, mouseDx: -5 }, { forward: -1, strafe: 0, turn: -1, mouseDx: 0 },
  { forward: 1, strafe: 0, turn: 1, mouseDx: 30 }, { forward: 1, strafe: 1, turn: 0, mouseDx: 0 }
];
for (const map of ['test', 'crypt']) {
  const w = World.load(MapData.maps[map], { requireStart: true });
  const p = Player.create(w.start, 0.3);
  const trace = [];
  let k = 0;
  for (let i = 0; i < 600; i++) {
    const inp = patterns[Math.floor(i / 25) % patterns.length];
    const dt = i % 37 === 0 ? 0.5 : (i % 5 === 0 ? 0.033 : 0.016); // includes the 0.1 clamp
    Player.update(p, w, inp, dt, undefined);
    if (i % 10 === 9) trace.push([p.x, p.y, p.angle]);
    k++;
  }
  players.push({ map, start: [w.start.x, w.start.y], angle0: 0.3, patterns, trace });
}
const angles = [-7, -0.1, 0, 3.2, 6.283185307179586, 100, 1e6].map((a) => [a, Player.create({ x: 1, y: 1 }, a).angle]);

mkdirSync(dirname(OUT), { recursive: true });
writeFileSync(OUT, JSON.stringify({ worlds, players, angles }) + '\n');
console.log('wrote ' + OUT + ' (' + worlds.map((w) => w.name + ': ' + w.pts.length + ' pts').join(', ') + ')');
