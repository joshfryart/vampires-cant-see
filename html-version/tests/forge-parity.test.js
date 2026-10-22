'use strict';
// v0.14 A3: the archetype refactor must not change a single villager. Compares rebuilt people against the
// v0.13.2 golden fixture (tools/forge-golden.mjs), plus the look-only rows and the role mappings.
const test = require('node:test');
const assert = require('node:assert');
const path = require('node:path');

const ROOT = path.join(__dirname, '..');
const Log = require(path.join(ROOT, 'js', 'log.js'));
const MapData = require(path.join(ROOT, 'js', 'data', 'maps.js'));
const VoiceData = require(path.join(ROOT, 'js', 'data', 'voices.js'));
require(path.join(ROOT, 'js', 'data', 'archetypes.js'));
const World = require(path.join(ROOT, 'js', 'world.js'));
require(path.join(ROOT, 'js', 'schedule.js'));
const Forge = require(path.join(ROOT, 'js', 'forge.js'));
const People = require(path.join(ROOT, 'js', 'people.js'));
const golden = require(path.join(ROOT, 'tests', 'fixtures', 'forge-golden.json'));

Log.setConsole(false);

const LEGACY_KEYS = ['height', 'build', 'stride', 'acc', 'body', 'head', 'hat', 'hair', 'beard', 'nose', 'coat', 'prop'];
const r9 = (x) => Math.round(x * 1e9) / 1e9;

function legacyOnly(look) {
  const o = {};
  LEGACY_KEYS.forEach((k) => { o[k] = look[k]; });
  return o;
}

const cache = {};
function built(map, seed) {
  const key = map + ':' + seed;
  if (!cache[key]) {
    const def = MapData.maps[map];
    const world = World.load(def, { requireStart: map === MapData.startMap || map === 'test' });
    cache[key] = People.create(world, def, { seed: seed });
  }
  return cache[key];
}

test('golden fixture is present and covers both maps and all seeds', () => {
  assert.strictEqual(golden.fixture, 'forge-golden');
  assert.ok(golden.people.length > 0);
  assert.deepStrictEqual(golden.maps, ['test', 'town']);
});

test('every rebuilt person matches the v0.13.2 golden row', () => {
  golden.people.forEach((row) => {
    const st = built(row.map, row.seed);
    const p = st.people[row.id];
    const tag = row.map + '/' + row.seed + '/' + row.id;
    assert.ok(p, tag + ' exists');
    assert.deepStrictEqual(legacyOnly(p.look), legacyOnly(row.look), tag + ' look');
    assert.strictEqual(p.role, row.role, tag + ' role');
    assert.deepStrictEqual(VoiceData.forPerson(p.id, p.role), row.voice, tag + ' voice');
    assert.strictEqual(VoiceData.groupOf(p.role), row.talk, tag + ' talk');
    const stops = p.sched && Array.isArray(p.sched.stops)
      ? p.sched.stops.map((s) => ({ place: s.place, act: s.act, until: r9(s.until) }))
      : null;
    assert.deepStrictEqual(stops, row.stops, tag + ' stops');
    assert.strictEqual(p.x, row.x, tag + ' x');
    assert.strictEqual(p.y, row.y, tag + ' y');
  });
});

test('person counts per map and seed match the fixture', () => {
  golden.maps.forEach((map) => {
    golden.seeds.forEach((seed) => {
      const n = golden.people.filter((r) => r.map === map && r.seed === seed).length;
      assert.strictEqual(built(map, seed).people.length, n, map + '/' + seed);
    });
  });
});

test('makeLook(11, id, 3) matches the golden look rows and Forge.legacyLook', () => {
  golden.looks.forEach((row) => {
    assert.deepStrictEqual(People.makeLook(11, row.id, 3), row.look, 'id ' + row.id);
    assert.deepStrictEqual(Forge.legacyLook(11, row.id, 3), row.look, 'legacyLook ' + row.id);
  });
});

test('presetFor and groupOf match the golden role table', () => {
  golden.roles.forEach((row) => {
    assert.strictEqual(VoiceData.presetFor(row.role), row.preset, 'preset ' + row.role);
    assert.strictEqual(VoiceData.groupOf(row.role), row.talk, 'talk ' + row.role);
  });
});

test('town people carry archetype, watch, feedable and gait from their archetype', () => {
  const st = built('town', 7);
  st.people.forEach((p) => {
    assert.strictEqual(typeof p.archetype, 'string');
    const a = Forge.archetype(p.archetype);
    assert.ok(a, p.archetype);
    assert.strictEqual(p.role, a.role);
    assert.strictEqual(p.watch, p.role === 'guard');
    assert.strictEqual(p.gait, p.role === 'guard' ? 'mail' : 'walk');
    assert.strictEqual(p.feedable, true);
  });
  assert.ok(st.places && st.mapDef && typeof st.accOffset === 'number');
});

test('old map data with role and no archetype still resolves', () => {
  const def = JSON.parse(JSON.stringify(MapData.maps.town));
  def.paths.forEach((d) => {
    if (d.archetype && d.archetype !== 'patron') d.role = d.archetype;
    delete d.archetype;
    delete d.seed;
  });
  const world = World.load(def, { requireStart: false });
  const a = People.create(world, def, { seed: 7 });
  const b = built('town', 7);
  assert.deepStrictEqual(a.people.map((p) => [p.role, p.archetype, legacyOnly(p.look)]), b.people.map((p) => [p.role, p.archetype, legacyOnly(p.look)]));
});
