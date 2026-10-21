#!/usr/bin/env node
// Golden fixture generator for the v0.14 NPC Forge refactor (job A0).
// Captures today's villager output so the refactor can be checked for parity.
// Usage: node tools/forge-golden.mjs [outPath]
//   default outPath: tests/fixtures/forge-golden.json
// Deterministic: same code in, byte-identical JSON out. No randomness, no clock.

import { createRequire } from 'node:module';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { mkdirSync, writeFileSync } from 'node:fs';

const require = createRequire(import.meta.url);
const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const JS = join(ROOT, 'js');

// Load order: logging, data, then logic modules (each attaches to VCS).
const Log = require(join(JS, 'log.js'));
const MapData = require(join(JS, 'data', 'maps.js'));
const VoiceData = require(join(JS, 'data', 'voices.js'));
const World = require(join(JS, 'world.js'));
const Schedule = require(join(JS, 'schedule.js'));
const People = require(join(JS, 'people.js'));
void Schedule;

Log.setConsole(false);

const MAPS = ['test', 'town'];
const SEEDS = [1, 7, 123456];
const LOOK_SEED = 11;
const LOOK_ACC_OFFSET = 3;
const LOOK_IDS = 40;

function r9(x) {
  return Math.round(x * 1e9) / 1e9;
}

// 1. Every person on both maps for each seed.
const people = [];
for (const name of MAPS) {
  const def = MapData.maps[name];
  for (const seed of SEEDS) {
    // Same options as World.loadAll: the start map and the test map need a start tile.
    const world = World.load(def, { requireStart: name === MapData.startMap || name === 'test' });
    const st = People.create(world, def, { seed: seed });
    for (const p of st.people) {
      const stops = p.sched && Array.isArray(p.sched.stops)
        ? p.sched.stops.map(function (s) {
          return { place: s.place, act: s.act, until: r9(s.until) };
        })
        : null;
      people.push({
        map: name,
        seed: seed,
        id: p.id,
        role: p.role,
        look: p.look,
        voice: VoiceData.forPerson(p.id, p.role),
        talk: VoiceData.groupOf(p.role),
        stops: stops,
        x: p.x,
        y: p.y
      });
    }
  }
}

// 2. Look-only rows: makeLook(11, id, 3) for id 0..39.
const looks = [];
for (let id = 0; id < LOOK_IDS; id++) {
  looks.push({ id: id, look: People.makeLook(LOOK_SEED, id, LOOK_ACC_OFFSET) });
}

// 3. Role mapping for every role string in the town map, plus ''.
const roleSet = [''];
for (const def of MapData.maps.town.paths) {
  const r = def && typeof def.role === 'string' ? def.role : '';
  if (roleSet.indexOf(r) < 0) roleSet.push(r);
}
const roles = roleSet.map(function (role) {
  return { role: role, preset: VoiceData.presetFor(role), talk: VoiceData.groupOf(role) };
});

const out = {
  fixture: 'forge-golden',
  v: 1,
  baseline: 'v0.13.2',
  maps: MAPS,
  seeds: SEEDS,
  people: people,
  looks: looks,
  roles: roles
};

const outPath = process.argv[2] ? resolve(process.argv[2]) : join(ROOT, 'tests', 'fixtures', 'forge-golden.json');
mkdirSync(dirname(outPath), { recursive: true });
writeFileSync(outPath, JSON.stringify(out, null, 1) + '\n', 'utf8');

process.stdout.write(
  'forge-golden: wrote ' + outPath + '\n' +
  'rows: people=' + people.length + ' looks=' + looks.length + ' roles=' + roles.length + '\n'
);
