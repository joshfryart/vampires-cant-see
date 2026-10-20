'use strict';
const { describe } = require('node:test');

describe('schedule.test.js', () => {
  const test = require('node:test');
  const assert = require('node:assert');
  const Log = require('../js/log.js');
  const MapData = require('../js/data/maps.js');
  const World = require('../js/world.js');
  const Schedule = require('../js/schedule.js');
  const People = require('../js/people.js');

  Log.setConsole(false);

  const town = MapData.maps.town;
  const DT = 1 / 30;
  const worlds = World.loadAll(MapData).worlds;

  function rngOf(seed) {
    let a = seed >>> 0;
    return function () {
      a = (a + 0x6D2B79F5) >>> 0;
      let t = a;
      t = Math.imul(t ^ (t >>> 15), t | 1);
      t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
      return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
  }
  // Mirrors game.js: a door opens when a person is within one cell.
  function openDoorsNear(world, st) {
    const doors = world.spots.doors;
    for (const p of st.people) {
      for (const d of doors) {
        if (Math.hypot(p.x - d.x, p.y - d.y) < 1.0 && !world.isDoorOpen(Math.floor(d.x), Math.floor(d.y))) world.setDoor(Math.floor(d.x), Math.floor(d.y), true);
      }
    }
  }
  function placeCells() {
    const out = {};
    Object.keys(town.places).forEach((k) => { out[k] = { x: town.places[k][0] + 0.5, y: town.places[k][1] + 0.5 }; });
    return out;
  }

  test('build: stops tile the night 0..1 in order, deterministic per seed', () => {
    const pl = placeCells();
    Object.keys(Schedule.ROLES).forEach((role) => {
      const o = { home: 'house2', slot: 4 };
      const a = Schedule.build(role, pl, { x: 28.5, y: 16.5 }, rngOf(7), o);
      const b = Schedule.build(role, pl, { x: 28.5, y: 16.5 }, rngOf(7), o);
      assert.deepStrictEqual(a, b, role);
      assert.ok(a && a.length >= 3, role + ' has stops');
      assert.strictEqual(a[0].at, 0);
      assert.strictEqual(a[a.length - 1].until, 1);
      for (let i = 1; i < a.length; i++) {
        assert.ok(Math.abs(a[i].at - a[i - 1].until) < 1e-9);
        assert.ok(a[i].until - a[i].at >= 0.015, role + ' stop ' + i + ' is not a blink');
      }
    });
  });

  test('build: unknown role or no places gives null; stopAt clamps', () => {
    assert.strictEqual(Schedule.build('nobody', placeCells(), null, rngOf(1)), null);
    assert.strictEqual(Schedule.make('mother', {}, null, rngOf(1), { home: 'house2' }), null);
    const s = Schedule.build('priest', placeCells(), null, rngOf(2), { home: 'church' });
    assert.strictEqual(Schedule.stopAt(s, -3), 0);
    assert.strictEqual(Schedule.stopAt(s, 9), s.length - 1);
  });

  test('housemates take different cells; guards walk opposite ways', () => {
    const pl = placeCells();
    const bed = (slot) => Schedule.build('mother', pl, null, rngOf(1), { home: 'house2', slot: slot }).slice(-1)[0].place;
    assert.strictEqual(new Set([bed(12), bed(4), bed(5)]).size, 3);
    const g0 = Schedule.build('guard', pl, null, rngOf(1), { slot: 0 }).map((x) => x.place);
    const g1 = Schedule.build('guard', pl, null, rngOf(1), { slot: 1 }).map((x) => x.place);
    assert.notDeepStrictEqual(g0, g1);
    assert.ok(g0.every((p) => !/_bed|_hearth|tavern|church|house|barn_|shed/.test(p)), 'the watch stays outdoors');
  });

  test('simplify drops collinear waypoints', () => {
    const r = Schedule.simplify([{ x: 0, y: 0 }, { x: 1, y: 0 }, { x: 2, y: 0 }, { x: 2, y: 1 }, { x: 2, y: 2 }]);
    assert.deepStrictEqual(r, [{ x: 0, y: 0 }, { x: 2, y: 0 }, { x: 2, y: 2 }]);
  });

  test('town: every named place is open floor and every role is known', () => {
    const world = worlds.town;
    Object.keys(town.places).forEach((k) => {
      const x = town.places[k][0] + 0.5;
      const y = town.places[k][1] + 0.5;
      assert.ok(!world.isSolid(x, y) && !world.blocks(x, y, 0), k);
    });
    town.paths.forEach((p, i) => {
      if (!p.role) return;
      assert.ok(Schedule.hasRole(p.role), 'path ' + i + ' role ' + p.role);
      if (p.home) assert.ok(town.zones.some((z) => z.name === p.home), 'path ' + i + ' home zone ' + p.home);
    });
  });

  test('town: the village is home by 01:00, the watch and night owls stay out, everyone but the watch sleeps indoors', () => {
    const world = worlds.town;
    const st = People.create(world, town, { seed: 11, shuffle: true });
    const walkers = st.people.filter((p) => p.sched);
    assert.ok(walkers.length >= 11, 'the town is scheduled');
    const nightSec = 240;
    const owls = ['insomniac', 'gravedigger'];
    const indoors = (p) => !!p.sched.home && world.zoneAt(p.x, p.y) === p.sched.home;
    const outAfterCurfew = new Set();
    for (let t = 0; t < nightSec; t += DT) {
      openDoorsNear(world, st);
      const f = t / nightSec;
      People.update(st, world, DT, { nightFrac: f, nightSec: nightSec });
      for (const p of walkers) {
        assert.ok(!world.isSolid(p.x, p.y) || ['D', 'G'].includes(world.tileAt(p.x, p.y)), 'person ' + p.id + ' in a wall at t=' + t.toFixed(0));
        const r = p.sched.role;
        if (r === 'guard') assert.ok(!world.zoneAt(p.x, p.y), 'guard ' + p.id + ' went indoors');
        if (f > 0.53 && r !== 'guard' && !owls.includes(r)) assert.ok(indoors(p), r + ' ' + p.id + ' still out at frac ' + f.toFixed(2) + ' in ' + world.zoneAt(p.x, p.y));
        if (f > 0.53 && (r === 'guard' || owls.includes(r)) && !world.zoneAt(p.x, p.y)) outAfterCurfew.add(r);
      }
    }
    assert.ok(outAfterCurfew.has('guard'), 'guards patrol after 01:00');
    assert.ok(outAfterCurfew.has('insomniac') || outAfterCurfew.has('gravedigger'), 'some stay out after 01:00');
    for (const p of walkers) {
      if (p.sched.role === 'guard') continue;
      assert.ok(indoors(p), p.sched.role + ' ' + p.id + ' ends the night at home');
      assert.ok(p.seated, p.sched.role + ' ' + p.id + ' is abed');
    }
  });

  test('home life: evening acts happen indoors at the home cells', () => {
    const world = worlds.town;
    const st = People.create(world, town, { seed: 4, shuffle: true });
    const mother = st.people.find((p) => p.sched && p.sched.role === 'mother');
    const acts = new Set();
    for (let t = 0; t < 240; t += DT) {
      openDoorsNear(world, st);
      People.update(st, world, DT, { nightFrac: t / 240, nightSec: 240 });
      const cur = mother.sched.stops[mother.sched.si];
      if (cur && !mother.sched.en && world.zoneAt(mother.x, mother.y) === 'house2') acts.add(cur.act);
    }
    ['cook', 'eat', 'spin', 'sleep'].forEach((a) => assert.ok(acts.has(a), 'mother does ' + a + ' at home: ' + [...acts]));
  });

  test('flight breaks a trip and the walker re-plans to the same stop', () => {
    const world = worlds.town;
    const st = People.create(world, town, { seed: 5, shuffle: true });
    const p = st.people.find((q) => q.sched);
    for (let t = 0; t < 150; t += DT) { openDoorsNear(world, st); People.update(st, world, DT, { nightFrac: 0.5, nightSec: 240 }); }
    const target = p.sched.si;
    assert.ok(target >= 0);
    p.mode = 'cower';
    p.fleeFrom = { x: p.x + 1, y: p.y };
    p.calmLeft = 0.1;
    for (let t = 0; t < 120; t += DT) { openDoorsNear(world, st); People.update(st, world, DT, { nightFrac: 0.5, nightSec: 240 }); }
    assert.strictEqual(p.mode, 'path');
    assert.strictEqual(p.sched.si, target);
    const stop = p.sched.stops[target];
    assert.ok(Math.hypot(p.x - stop.x, p.y - stop.y) < 1.5);
  });

  test('snapshot exposes schedule info for the debug readout', () => {
    const world = worlds.town;
    const st = People.create(world, town, { seed: 3 });
    People.update(st, world, DT, { nightFrac: 0.1, nightSec: 240 });
    const snap = People.snapshot(st);
    const withSched = snap.filter((s) => s.sched);
    assert.ok(withSched.length >= 9);
    assert.ok(typeof withSched[0].sched.role === 'string');
    assert.strictEqual(snap.filter((s) => !s.sched).length, st.people.length - withSched.length);
  });

  test('maps without roles behave as before (test map has no schedules)', () => {
    const def = MapData.maps.test;
    const st = People.create(World.load(def), def, { seed: 1 });
    assert.ok(st.people.every((p) => !p.sched));
  });
});
