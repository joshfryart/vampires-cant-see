'use strict';
// Merged test file: each source file's tests live in their own describe().
const { describe } = require('node:test');

describe('people.test.js', () => {

  const test = require('node:test');
  const assert = require('node:assert');
  const Log = require('../js/log.js');
  const MapData = require('../js/data/maps.js');
  const World = require('../js/world.js');
  const Raycast = require('../js/raycast.js');
  const Sonar = require('../js/sonar.js');
  const People = require('../js/people.js');

  Log.setConsole(false);
  void Raycast;

  const DT = 1 / 60;
  const def = MapData.maps.test;

  function sim(seed, seconds, fn) {
    const world = World.load(def);
    const st = People.create(world, def, { seed: seed });
    const n = Math.round(seconds / DT);
    for (let i = 0; i < n; i++) {
      People.update(st, world, DT);
      if (fn) fn(st, world, i * DT);
    }
    return st;
  }

  function inWall(world, p, r) {
    return world.isSolid(p.x - r, p.y - r) || world.isSolid(p.x + r, p.y - r) ||
      world.isSolid(p.x - r, p.y + r) || world.isSolid(p.x + r, p.y + r);
  }

  test('one person per P tile, starting at the spawn with its path', () => {
    const world = World.load(def);
    const st = People.create(world, def, { seed: 1 });
    assert.strictEqual(st.people.length, world.spots.people.length);
    assert.strictEqual(st.people.length, 3);
    st.people.forEach((p, i) => {
      assert.strictEqual(p.x, world.spots.people[i].x);
      assert.strictEqual(p.y, world.spots.people[i].y);
      assert.strictEqual(p.path.length, def.paths[i].points.length);
      assert.strictEqual(p.state, 'idle');
    });
  });

  test('every person moves and never enters a wall', () => {
    const start = sim(1, 0).people.map((p) => ({ x: p.x, y: p.y }));
    const st = sim(1, 10, (s, world) => {
      s.people.forEach((p) => assert.ok(!inWall(world, p, s.radius), 'person ' + p.id + ' in wall at ' + p.x + ',' + p.y));
    });
    st.people.forEach((p, i) => {
      assert.ok(Math.hypot(p.x - start[i].x, p.y - start[i].y) > 0.5 || p.walked > 2, 'person ' + i + ' moved');
    });
  });

  test('person 0 reaches its second waypoint and idles there', () => {
    let arrived = -1;
    let idleFor = 0;
    sim(1, 12, (s, world, t) => {
      const p = s.people[0];
      const at = Math.hypot(p.x - 21.5, p.y - 1.5) < 0.05;
      if (at && arrived < 0) arrived = t;
      if (at && p.state === 'idle') idleFor += DT;
    });
    assert.ok(arrived > 0, 'reached [21,1]');
    assert.ok(idleFor >= 0.8, 'idled at least 0.8 s, got ' + idleFor.toFixed(2));
  });

  test('deterministic for a seed; different seeds differ', () => {
    const a = sim(7, 20);
    const b = sim(7, 20);
    assert.deepStrictEqual(People.snapshot(a), People.snapshot(b));
    a.people.forEach((p, i) => assert.strictEqual(p.walked, b.people[i].walked));
    const c = sim(99, 20);
    const same = a.people.every((p, i) => p.walked === c.people[i].walked);
    assert.ok(!same, 'idle timing should differ with another seed');
  });

  test('looks around while idle', () => {
    let maxLook = 0;
    sim(1, 2, (s) => { maxLook = Math.max(maxLook, Math.abs(s.people[0].lookAngle)); });
    assert.ok(maxLook > 0.05, 'lookAngle moved: ' + maxLook);
  });

  test('invalid path (through a wall) falls back to idling in place without throwing', () => {
    const world = World.load(def);
    const bad = { paths: [{ points: [[16, 1], [16, 12]], waits: [1, 1] }] };
    const st = People.create(world, bad, { seed: 1 });
    assert.strictEqual(st.people[0].path.length, 1);
    for (let i = 0; i < 300; i++) People.update(st, world, DT);
    assert.strictEqual(st.people[0].x, world.spots.people[0].x);
    assert.strictEqual(st.people[2].path.length, 1, 'missing path entry -> one-point path');
  });

  test('echo snapshots are taken when the wavefront crosses a visible person', () => {
    const world = World.load(def);
    const st = People.create(world, def, { seed: 1 });
    const sonar = Sonar.create({ speed: 12, range: 10, fade: 3, cooldown: 0.1, bounces: 0 });
    // Pulse from the corridor in front of person 0 (16.5,1.5) and 1 (13.5,4.5).
    Sonar.emit(sonar, world, 14.5, 2.5, 0);
    let all = [];
    let tPrev = 0;
    for (let t = DT; t <= 1.5; t += DT) {
      all = all.concat(People.updateEchoes(st, sonar, tPrev, t));
      tPrev = t;
    }
    const ids = all.map((e) => e.personId).sort();
    assert.deepStrictEqual(ids, [0, 1], 'persons 0 and 1 echoed once each, person 2 is behind the wall');
    all.forEach((e) => {
      assert.ok(e.t > 0 && e.dist > 0 && e.strength > 0 && e.strength <= 1);
      assert.strictEqual(typeof e.phase, 'number');
    });
    assert.strictEqual(st.echoes.length, 2);
    assert.ok(People.echoBrightness(all[0], all[0].t, 3) > 0.5);
    assert.strictEqual(People.echoBrightness(all[0], all[0].t + 3, 3), 0);
    assert.strictEqual(People.echoBrightness(all[0], all[0].t - 0.1, 3), 0);
    assert.ok(Math.abs(People.echoAge(all[0], all[0].t + 1) - 1) < 1e-9);
    // Pruned after fade.
    People.updateEchoes(st, sonar, 5, 5.01);
    assert.strictEqual(st.echoes.length, 0);
  });

  test('echo cap holds', () => {
    const world = World.load(def);
    const st = People.create(world, def, { seed: 1, maxEchoes: 4 });
    const sonar = Sonar.create({ speed: 12, range: 10, fade: 30, cooldown: 0, bounces: 0 });
    for (let k = 0; k < 6; k++) {
      Sonar.emit(sonar, world, 14.5, 2.5, k * 0.7);
      const t0 = k * 0.7;
      let tPrev = t0;
      for (let t = t0 + 0.05; t <= t0 + 0.65; t += 0.05) { People.updateEchoes(st, sonar, tPrev, t); tPrev = t; }
    }
    assert.strictEqual(st.echoes.length, 4);
  });

  test('stepEvents: two foot plants per walk cycle, none while idle, objects reused', () => {
    const world = World.load(def);
    const st = People.create(world, def, { seed: 1 });
    const out = [];
    let total = 0;
    let idleSteps = 0;
    let first = null;
    for (let i = 0; i < 60 * 12; i++) {
      People.update(st, world, DT);
      const n = People.stepEvents(st, 0, 0, out);
      assert.strictEqual(out.length, n);
      if (n && !first) first = out[0];
      for (let k = 0; k < n; k++) {
        total++;
        const p = st.people[out[k].id];
        if (p.state === 'idle' && p.phase === 0) idleSteps++;
        assert.ok(Number.isFinite(out[k].x) && Number.isFinite(out[k].y));
        assert.ok(['sneak', 'walk', 'run'].includes(out[k].gait), 'gait ' + out[k].gait);
        assert.ok(out[k].pace > 0 && Number.isFinite(out[k].pace));
      }
    }
    assert.strictEqual(idleSteps, 0);
    // Each person's plants alternate left/right foot and carry the heading.
    const lastFoot = {};
    let alternated = 0;
    const st2 = People.create(world, def, { seed: 1 });
    for (let i = 0; i < 60 * 12; i++) {
      People.update(st2, world, DT);
      People.stepEvents(st2, 0, 0, out);
      for (let k = 0; k < out.length; k++) {
        const e = out[k];
        assert.ok(e.foot === 0 || e.foot === 1);
        assert.ok(Number.isFinite(e.angle));
        if (lastFoot[e.id] !== undefined && lastFoot[e.id] !== e.foot) alternated++;
        lastFoot[e.id] = e.foot;
      }
    }
    assert.ok(alternated > 5, 'feet alternate: ' + alternated);
    const walked = st.people.reduce((a, p) => a + p.walked, 0);
    // phase advances 9 rad per cell: two plants per 2*PI rad.
    const expected = walked * 9 / Math.PI;
    assert.ok(Math.abs(total - expected) <= 4, 'steps ' + total + ' vs ' + expected.toFixed(1));
    assert.ok(total > 10);
    const still = People.create(world, { paths: [] }, { seed: 1 });
    People.update(still, world, DT);
    assert.strictEqual(People.stepEvents(still, 0, 0, out), 0);
    assert.strictEqual(out.length, 0);
  });

  test('looks are deterministic per seed, in range, and distinct across people', () => {
    const world = World.load(def);
    const a = People.create(world, def, { seed: 5 }).people.map((p) => p.look);
    const b = People.create(world, def, { seed: 5 }).people.map((p) => p.look);
    assert.deepStrictEqual(a, b);
    a.forEach((l) => {
      assert.ok(l.height >= 0.9 && l.height <= 1.05 + 1e-9);
      assert.ok(l.build >= 0.9 && l.build <= 1.15 + 1e-9);
    });
    assert.strictEqual(new Set(a.map((l) => l.acc)).size, 3);
    const c = People.create(world, def, { seed: 6 }).people.map((p) => p.look);
    assert.notDeepStrictEqual(a, c);
  });

  test('looks carry body, head, hair, prop and coat fields; hats and props follow the accessory', () => {
    const bodies = ['bean', 'pear', 'stick', 'round', 'box'];
    const heads = ['round', 'egg', 'square', 'long'];
    const hairs = ['none', 'tuft', 'bun', 'spiky', 'curls', 'bob'];
    const seen = { body: new Set(), head: new Set(), hair: new Set(), prop: new Set(), hat: new Set() };
    for (let id = 0; id < 40; id++) {
      const l = People.makeLook(11, id, 3);
      assert.ok(bodies.includes(l.body) && heads.includes(l.head) && hairs.includes(l.hair), JSON.stringify(l));
      assert.ok(typeof l.beard === 'boolean' && typeof l.coat === 'boolean');
      assert.ok(l.nose >= 0.7 && l.nose <= 1.4 + 1e-9);
      assert.ok(People.ACCESSORIES.includes(l.acc));
      if (['tophat', 'nightcap', 'bonnet', 'cap', 'hood'].includes(l.acc)) assert.strictEqual(l.hat, l.acc);
      else assert.strictEqual(l.hat, 'none');
      if (['cane', 'lantern', 'umbrella', 'basket'].includes(l.acc)) assert.strictEqual(l.prop, l.acc);
      else assert.strictEqual(l.prop, 'none');
      if (l.hat === 'tophat' || l.hat === 'nightcap' || l.hat === 'hood') assert.strictEqual(l.hair, 'none');
      for (const k in seen) seen[k].add(l[k]);
    }
    assert.ok(seen.body.size >= 4 && seen.head.size >= 3 && seen.hair.size >= 4 && seen.prop.size >= 3 && seen.hat.size >= 4);
    // Bad input never throws.
    assert.doesNotThrow(() => People.makeLook(NaN, 'x', null));
    assert.ok(People.ACCESSORIES.includes(People.makeLook(undefined, -3, undefined).acc));
  });

  test('echoes carry pose state: mode, sit, wary, modeAge and phaseRate', () => {
    const world = World.load(def);
    const st = People.create(world, def, { seed: 1 });
    let walker = null;
    let ticks = 0;
    while (!walker && ticks < 1200) {
      People.update(st, world, DT, {});
      ticks++;
      if (ticks > 30) walker = st.people.find((p) => p.state === 'walk' && p.phaseRate > 0) || null;
    }
    assert.ok(walker, 'someone is walking');
    assert.ok(walker.phaseRate > 0 && walker.phaseRate < 40, 'phaseRate ' + walker.phaseRate);
    assert.ok(walker.modeAge >= 0.5, 'modeAge ' + walker.modeAge);
    const sonar = Sonar.create({ speed: 12, range: 10, fade: 3, cooldown: 0, bounces: 0 });
    Sonar.emitSound(sonar, world, walker.x + 0.3, walker.y, 1.5, { kind: 'ping', strength: 1, range: 10, bounces: 0, visRays: 180 });
    let all = [];
    let tPrev = 1.5;
    for (let t = 1.5 + DT; t <= 2.2; t += DT) { all = all.concat(People.updateEchoes(st, sonar, tPrev, t)); tPrev = t; }
    const e = all.find((x) => x.personId === walker.id);
    assert.ok(e, 'echo of the walker');
    assert.strictEqual(e.mode, 'path');
    assert.strictEqual(e.sit, false);
    assert.strictEqual(e.wary, false);
    assert.ok(e.phaseRate > 0 && e.modeAge >= 0.5);
    // A mode change resets modeAge on the next update.
    walker.mode = 'cower';
    People.update(st, world, DT, {});
    assert.ok(walker.modeAge < DT + 1e-9 && walker.modeAge >= 0);
    assert.strictEqual(walker.phaseRate, 0);
  });

  test('sound strength scales snapshots; weak far sounds are ignored; echoes carry the look', () => {
    const world = World.load(def);
    const st = People.create(world, def, { seed: 1 });
    const sonar = Sonar.create({ speed: 12, range: 10, fade: 3, cooldown: 0, bounces: 0 });
    Sonar.emitSound(sonar, world, 14.5, 2.5, 0, { kind: 'ping', strength: 0.4, range: 10, bounces: 0, visRays: 180 });
    let all = [];
    let tPrev = 0;
    for (let t = DT; t <= 1.2; t += DT) { all = all.concat(People.updateEchoes(st, sonar, tPrev, t)); tPrev = t; }
    assert.ok(all.length >= 1);
    all.forEach((e) => { assert.ok(e.strength <= 0.4 + 1e-9); assert.ok(e.look); });
    const st2 = People.create(world, def, { seed: 1 });
    const weak = Sonar.create({ speed: 12, range: 10, fade: 3, cooldown: 0, bounces: 0 });
    Sonar.emitSound(weak, world, 3.5, 7.5, 0, { kind: 'step', strength: 0.1, range: 10, bounces: 0, visRays: 180 });
    let far = [];
    tPrev = 0;
    for (let t = DT; t <= 1.2; t += DT) { far = far.concat(People.updateEchoes(st2, weak, tPrev, t)); tPrev = t; }
    far.forEach((e) => assert.ok(e.dist <= 6));
  });

  test('accessories come from the quirky set', () => {
    const world = World.load(def);
    const st = People.create(world, def, { seed: 3 });
    st.people.forEach((p) => assert.ok(People.ACCESSORIES.includes(p.look.acc), p.look.acc));
  });

  test('echoes store a lit height band and their own fade', () => {
    const world = World.load(def);
    const st = People.create(world, def, { seed: 1 });
    const sonar = Sonar.create({ speed: 12, range: 10, fade: 3, cooldown: 0, bounces: 0 });
    Sonar.emitSound(sonar, world, 14.5, 2.5, 0, { kind: 'ping', strength: 1, range: 10, bounces: 0, visRays: 180 });
    let all = [];
    let tPrev = 0;
    for (let t = DT; t <= 1.2; t += DT) { all = all.concat(People.updateEchoes(st, sonar, tPrev, t)); tPrev = t; }
    assert.ok(all.length >= 1);
    all.forEach((e) => {
      assert.ok(e.zMin >= 0 && e.zMax > e.zMin && e.zMax <= 1.2 + 1e-9, 'band ' + e.zMin + '..' + e.zMax);
      assert.ok(e.fade > 0);
    });
  });

  test('a person own foot-level step lights only low parts (needs Sonar.heightBand)', () => {
    if (typeof Sonar.heightBand !== 'function') return;
    const world = World.load(def);
    const st = People.create(world, def, { seed: 1 });
    const sonar = Sonar.create({ speed: 12, range: 10, fade: 3, cooldown: 0, bounces: 0 });
    const p = st.people[0];
    Sonar.emitSound(sonar, world, p.x, p.y, 0, { kind: 'personStep', strength: 0.35, range: 0.7, z: 0, fade: 0.7, bounces: 0, visRays: 90 });
    let all = [];
    let tPrev = -DT;
    for (let t = 0; t <= 0.5; t += DT) { all = all.concat(People.updateEchoes(st, sonar, tPrev, t)); tPrev = t; }
    const mine = all.filter((e) => e.personId === p.id);
    assert.ok(mine.length >= 1);
    assert.ok(mine[0].zMax < 0.8, 'zMax ' + mine[0].zMax);
    assert.ok(mine[0].zMin <= 0.01);
    assert.strictEqual(mine[0].fade, 0.7);
  });

  test('echoBrightness uses the echo own fade when present', () => {
    const e = { t: 0, strength: 1, fade: 0.5 };
    assert.ok(People.echoBrightness(e, 0.4, 3) > 0);
    assert.strictEqual(People.echoBrightness(e, 0.6, 3), 0);
  });

});

describe('people-react.test.js', () => {

  const test = require('node:test');
  const assert = require('node:assert');
  const Log = require('../js/log.js');
  const MapData = require('../js/data/maps.js');
  const SoundData = require('../js/data/sounds.js');
  const World = require('../js/world.js');
  const People = require('../js/people.js');

  Log.setConsole(false);

  const REACT = SoundData.react;
  const DT = 1 / 60;

  /** w x h room: walls on the border, floor inside. */
  function grid(w, h) {
    const rows = [];
    for (let r = 0; r < h; r++) {
      let s = '';
      for (let c = 0; c < w; c++) s += (r === 0 || r === h - 1 || c === 0 || c === w - 1) ? '#' : '.';
      rows.push(s);
    }
    return rows;
  }
  function setCh(rows, col, row, ch) {
    const out = rows.slice();
    out[row] = out[row].slice(0, col) + ch + out[row].slice(col + 1);
    return out;
  }
  /** Build a world and people state. One person per P tile, in row-major order, with paths[i]. */
  function scene(rows, paths, seed) {
    const def = { name: 'scene', rows: rows, paths: paths };
    const world = World.load(def, { requireStart: false });
    const st = People.create(world, def, { seed: seed || 7 });
    return { world: world, st: st };
  }

  // 21 x 9 hall with one person at (4,4) walking a loop east of the spawn, so it faces east (angle 0).
  const HALL = setCh(grid(21, 9), 4, 4, 'P');
  function hallPaths() {
    return [{ points: [[4, 4], [12, 4], [12, 6], [4, 6]], waits: [1, 1, 1, 1], speed: 1.2 }];
  }
  const PLAYER_E = { x: 7.5, y: 4.5 }; // 3 cells east of the person, on its facing line

  function ctx(player, lit, extra) {
    return Object.assign({ player: player, playerLit: lit, react: REACT, t: 0, grace: 0 }, extra || {});
  }

  // Determinism -----------------------------------------------------------------

  test('no ctx: the same seed gives identical positions', () => {
    const run = (seed) => {
      const def = MapData.maps.town;
      const w = World.load(def, { requireStart: false });
      const st = People.create(w, def, { seed: seed });
      for (let i = 0; i < 900; i++) People.update(st, w, DT);
      return st.people.map((p) => [p.x, p.y, p.angle, p.mode]);
    };
    assert.deepStrictEqual(run(5), run(5));
  });

  test('with ctx: the same inputs give identical results', () => {
    const run = () => {
      const { world, st } = scene(HALL, hallPaths());
      const c = ctx(PLAYER_E, 1);
      const trace = [];
      for (let i = 0; i < 120; i++) {
        People.update(st, world, DT, c);
        trace.push([st.people[0].x, st.people[0].y, st.people[0].mode]);
      }
      return { trace: trace, events: People.drainEvents(st).map((e) => e.type) };
    };
    assert.deepStrictEqual(run(), run());
  });

  // Seeing ----------------------------------------------------------------------

  test('seen when lit, in the cone, with line of sight: flees and screams', () => {
    const { world, st } = scene(HALL, hallPaths());
    People.update(st, world, DT, ctx(PLAYER_E, 1));
    const p = st.people[0];
    assert.strictEqual(p.mode, 'flee');
    // v0.7.2: entering flee also emits a 'flee' event alongside the scream.
    const ev = People.drainEvents(st).filter((e) => e.type === 'scream');
    assert.strictEqual(ev.length, 1);
    assert.strictEqual(ev[0].type, 'scream');
    assert.strictEqual(ev[0].id, 0);
    assert.strictEqual(ev[0].x, 4.5);
    assert.strictEqual(ev[0].y, 4.5);
    assert.strictEqual(People.drainEvents(st).length, 0, 'drainEvents clears');
  });

  test('lit below lightSeen is not enough; at lightSeen it is', () => {
    let s = scene(HALL, hallPaths());
    People.update(s.st, s.world, DT, ctx(PLAYER_E, REACT.lightSeen - 0.01));
    assert.strictEqual(s.st.people[0].mode, 'path');
    s = scene(HALL, hallPaths());
    People.update(s.st, s.world, DT, ctx(PLAYER_E, REACT.lightSeen));
    assert.strictEqual(s.st.people[0].mode, 'flee');
  });

  test('not seen in the dark beyond bumpDist', () => {
    const { world, st } = scene(HALL, hallPaths());
    People.update(st, world, DT, ctx(PLAYER_E, 0));
    assert.strictEqual(st.people[0].mode, 'path');
    assert.strictEqual(People.drainEvents(st).length, 0);
  });

  test('bump from behind only counts within bumpBackDist (was: any unlit touch within bumpDist)', () => {
    let s = scene(HALL, hallPaths());
    People.update(s.st, s.world, DT, ctx({ x: 3.8, y: 4.5 }, 0)); // 0.7 behind: not noticed
    assert.strictEqual(s.st.people[0].mode, 'path');
    s = scene(HALL, hallPaths());
    People.update(s.st, s.world, DT, ctx({ x: 4.2, y: 4.5 }, 0)); // 0.3 behind: bump freeze first
    assert.strictEqual(s.st.people[0].mode, 'startle');
    for (let i = 0; i < 30; i++) People.update(s.st, s.world, DT, ctx({ x: 4.2, y: 4.5 }, 0));
    assert.strictEqual(s.st.people[0].mode, 'flee');
  });

  test('a wall between them blocks sight (with an unwalled control)', () => {
    const stationary = [{ points: [[4, 4]] }];
    const walled = setCh(HALL, 6, 4, '#');
    let s = scene(walled, stationary);
    People.update(s.st, s.world, DT, ctx({ x: 8.5, y: 4.5 }, 1));
    assert.strictEqual(s.st.people[0].mode, 'path', 'wall blocks');

    s = scene(HALL, stationary);
    People.update(s.st, s.world, DT, ctx({ x: 8.5, y: 4.5 }, 1));
    assert.notStrictEqual(s.st.people[0].mode, 'path', 'control: unwalled point is seen');
  });

  test('outside the 120 degree cone is not seen', () => {
    const outside = [{ x: 1.5, y: 4.5 }, { x: 4.5, y: 1.5 }]; // directly behind and to the side
    outside.forEach((pl) => {
      const { world, st } = scene(HALL, hallPaths());
      People.update(st, world, DT, ctx(pl, 1));
      assert.strictEqual(st.people[0].mode, 'path', 'player at ' + pl.x + ',' + pl.y);
    });
  });

  test('grace > 0 means not seen even when lit and in view (grace 0 control)', () => {
    let s = scene(HALL, hallPaths());
    People.update(s.st, s.world, DT, ctx(PLAYER_E, 1, { grace: 0.5 }));
    assert.strictEqual(s.st.people[0].mode, 'path');
    s = scene(HALL, hallPaths());
    People.update(s.st, s.world, DT, ctx(PLAYER_E, 1, { grace: 0 }));
    assert.strictEqual(s.st.people[0].mode, 'flee');
  });

  // Sounds ----------------------------------------------------------------------

  test('react within startleDist startles; outside it does nothing', () => {
    let s = scene(HALL, hallPaths());
    People.react(s.st, 6.5, 4.5, 'step', { react: REACT }); // 2 cells from the person
    const p = s.st.people[0];
    assert.strictEqual(p.mode, 'startle');
    assert.strictEqual(p.modeLeft, REACT.startleTime);
    const ev = People.drainEvents(s.st);
    assert.strictEqual(ev.length, 1);
    assert.strictEqual(ev[0].type, 'startle');
    assert.strictEqual(ev[0].id, 0);

    s = scene(HALL, hallPaths());
    People.react(s.st, 15.5, 1.5, 'step', { react: REACT }); // about 11 cells away
    assert.strictEqual(s.st.people[0].mode, 'path');
    assert.strictEqual(People.drainEvents(s.st).length, 0);
  });

  test('startle lasts startleTime, then the person returns to path mode', () => {
    const { world, st } = scene(HALL, hallPaths());
    People.react(st, 6.5, 4.5, 'step', { react: REACT });
    for (let i = 0; i < 6; i++) People.update(st, world, 0.1);
    assert.strictEqual(st.people[0].mode, 'startle', 'still startled at 0.6 s');
    for (let i = 0; i < 6; i++) People.update(st, world, 0.1);
    assert.strictEqual(st.people[0].mode, 'path', 'back to path after 1.2 s');
  });

  test('a sound while the player is lit and visible makes the person flee, not startle', () => {
    const { world, st } = scene(HALL, hallPaths());
    People.react(st, 6.5, 4.5, 'ping', ctx(PLAYER_E, 1));
    assert.strictEqual(st.people[0].mode, 'flee');
    assert.deepStrictEqual(People.drainEvents(st).map((e) => e.type).filter((t) => t !== 'flee'), ['scream']);
  });

  test('two people seeing the player in the same moment give one scream', () => {
    const rows = setCh(setCh(grid(21, 9), 4, 3, 'P'), 4, 6, 'P');
    const paths = [{ points: [[4, 3], [12, 3]] }, { points: [[4, 6], [12, 6]] }];
    const { world, st } = scene(rows, paths);
    People.update(st, world, DT, ctx(PLAYER_E, 1));
    assert.deepStrictEqual(st.people.map((p) => p.mode), ['flee', 'flee']);
    const ev = People.drainEvents(st);
    assert.strictEqual(ev.filter((e) => e.type === 'scream').length, 1);
  });

  // Fleeing, cowering, calming -----------------------------------------------------

  test('cornered (no waypoint farther from the player) cowers, facing away', () => {
    const rows = setCh(grid(21, 9), 4, 4, 'P');
    const { world, st } = scene(rows, [{ points: [[4, 4]] }]);
    People.update(st, world, DT, ctx(PLAYER_E, 1));
    const p = st.people[0];
    assert.strictEqual(p.mode, 'cower');
    assert.ok(Math.abs(Math.abs(p.angle) - Math.PI) < 1e-9, 'faces away from the player');
    // v0.7.1: cornered prey can be fed on.
    assert.strictEqual(People.isFeedable(p), true);
  });

  test('cowering person returns to path after calmAfter seconds unseen', () => {
    const rows = setCh(grid(21, 9), 4, 4, 'P');
    const { world, st } = scene(rows, [{ points: [[4, 4]] }]);
    People.update(st, world, DT, ctx(PLAYER_E, 1));
    const away = ctx({ x: 1.5, y: 1.5 }, 0);
    for (let i = 0; i < 300; i++) People.update(st, world, DT, away); // 5 s
    assert.strictEqual(st.people[0].mode, 'cower', 'still cowering at 5 s');
    for (let i = 0; i < 360; i++) People.update(st, world, DT, away); // 11 s total
    assert.strictEqual(st.people[0].mode, 'path');
  });

  test('fleeing person calms after calmAfter seconds unseen and returns to path', () => {
    const { world, st } = scene(HALL, hallPaths());
    People.update(st, world, DT, ctx(PLAYER_E, 1));
    const p = st.people[0];
    assert.strictEqual(p.mode, 'flee');
    const away = ctx({ x: 1.5, y: 1.5 }, 0);
    for (let i = 0; i < 300; i++) People.update(st, world, DT, away); // 5 s
    assert.notStrictEqual(p.mode, 'path', 'still fleeing at 5 s');
    assert.strictEqual(People.isFeedable(p), true, 'v0.7.1: fleeing prey can be caught');
    for (let i = 0; i < 360; i++) People.update(st, world, DT, away); // 11 s total
    assert.strictEqual(p.mode, 'path');
    assert.strictEqual(People.isFeedable(p), true);
  });

  function hideScene(hides, paths, extra) {
    const def = { name: 'hide', rows: HALL, paths: paths || hallPaths(), hides: hides };
    if (extra) Object.assign(def, extra);
    const world = World.load(def, { requireStart: false });
    return { world: world, st: People.create(world, def, { seed: 7 }) };
  }

  test('flee speed is capped by fleeCap', () => {
    const { world, st } = scene(HALL, hallPaths());
    const c = ctx(PLAYER_E, 1, { react: Object.assign({}, REACT, { fleeMul: 5, fleeCap: 2.0 }) });
    People.update(st, world, DT, c);
    const p = st.people[0];
    assert.strictEqual(p.mode, 'flee');
    let max = 0;
    for (let i = 0; i < 120; i++) {
      const x = p.x, y = p.y;
      People.update(st, world, DT, c);
      max = Math.max(max, Math.hypot(p.x - x, p.y - y) / DT);
    }
    assert.ok(max <= 2.0 + 1e-6 && max > 1.5, 'max speed ' + max);
  });

  test('default fleeCap is 2.55', () => {
    const { world, st } = scene(HALL, [{ points: [[4, 4], [12, 4], [12, 6], [4, 6]], waits: [1, 1, 1, 1], speed: 3 }]);
    const c = ctx(PLAYER_E, 1, { react: Object.assign({}, REACT, { fleeMul: 4 }) });
    delete c.react.fleeCap;
    People.update(st, world, DT, c);
    const p = st.people[0];
    let max = 0;
    for (let i = 0; i < 90; i++) {
      const x = p.x, y = p.y;
      People.update(st, world, DT, c);
      max = Math.max(max, Math.hypot(p.x - x, p.y - y) / DT);
    }
    assert.ok(max <= 2.55 + 1e-6 && max > 2.0, 'max speed ' + max);
  });

  test('fleeing person runs to a hide spot farther from the player, cowers, then resumes', () => {
    const { world, st } = hideScene([[1, 1], [18, 7], [1, 7]]);
    const p = st.people[0];
    People.update(st, world, DT, ctx(PLAYER_E, 1));
    assert.strictEqual(p.mode, 'flee');
    assert.ok(p.route && p.route.length > 0);
    const last = p.route[p.route.length - 1];
    assert.ok(Math.hypot(last.x - PLAYER_E.x, last.y - PLAYER_E.y) > Math.hypot(4.5 - PLAYER_E.x, 4.5 - PLAYER_E.y));
    const seen = ctx(PLAYER_E, 1);
    for (let i = 0; i < 600 && p.mode === 'flee'; i++) {
      People.update(st, world, DT, seen);
      assert.ok(isFinite(p.x + p.y));
    }
    assert.strictEqual(p.mode, 'cower');
    assert.ok(Math.hypot(p.x - last.x, p.y - last.y) < 0.05, 'cowering at the hide spot');
    const away = ctx({ x: 19.5, y: 1.5 }, 0);
    for (let i = 0; i < 60 * 12; i++) People.update(st, world, DT, away);
    assert.strictEqual(p.mode, 'path');
    for (let i = 0; i < 60 * 30; i++) {
      People.update(st, world, DT, away);
      assert.ok(!world.isSolid(p.x, p.y) && isFinite(p.x + p.y));
    }
  });

  test('no hides, or none farther than the person: old farthest-waypoint flee', () => {
    const a = hideScene(undefined);
    People.update(a.st, a.world, DT, ctx(PLAYER_E, 1));
    assert.strictEqual(a.st.people[0].route, null);
    const b = hideScene([[10, 4]]); // closer to the player than the person
    People.update(b.st, b.world, DT, ctx(PLAYER_E, 1));
    assert.strictEqual(b.st.people[0].route, null);
    assert.strictEqual(b.st.people[0].mode, 'flee');
  });

  test('fleeing person prefers a lit refuge (torch) over a hide spot; lightPref 0 disables', () => {
    const torch = { props: [{ type: 'torch', col: 1, row: 4 }] };
    const a = hideScene([[18, 7]], null, torch);
    assert.ok(a.world.lightAt(1.5, 4.5) >= 0.3);
    People.update(a.st, a.world, DT, ctx(PLAYER_E, 1));
    const pa = a.st.people[0];
    const la = pa.route[pa.route.length - 1];
    assert.ok(a.world.lightAt(la.x, la.y) >= 0.3 && la.x < 4.5, 'lit refuge at ' + la.x + ',' + la.y);
    assert.ok(pa.route.length <= 15);
    const b = hideScene([[18, 7]], null, torch);
    People.update(b.st, b.world, DT, ctx(PLAYER_E, 1, { react: Object.assign({}, REACT, { lightPref: 0 }) }));
    const lb = b.st.people[0].route[b.st.people[0].route.length - 1];
    assert.ok(Math.abs(lb.x - 18.5) < 1e-6 && Math.abs(lb.y - 7.5) < 1e-6);
  });

  test('lit refuge is ignored when none is farther from the player (falls back, no throw)', () => {
    const s = hideScene(undefined, null, { props: [{ type: 'torch', col: 10, row: 4 }] });
    People.update(s.st, s.world, DT, ctx(PLAYER_E, 1));
    assert.strictEqual(s.st.people[0].mode, 'flee');
  });

  test('after calming, a wary person resumes at the waypoint with lit surroundings', () => {
    const s = hideScene(undefined, null, { props: [{ type: 'torch', col: 12, row: 6 }] });
    const p = s.st.people[0];
    People.update(s.st, s.world, DT, ctx(PLAYER_E, 1));
    const away = ctx({ x: 1.5, y: 1.5 }, 0);
    for (let i = 0; i < 60 * 12 && p.mode !== 'path'; i++) People.update(s.st, s.world, DT, away);
    assert.strictEqual(p.mode, 'path');
    assert.strictEqual(p.idx, 2);
  });

  test('isFeedable: path, startle, flee, cower, dazed yes; grapple, fed no', () => {
    for (const m of ['path', 'startle', 'flee', 'cower', 'dazed']) assert.strictEqual(People.isFeedable({ mode: m }), true, m);
    for (const m of ['grapple', 'fed']) assert.strictEqual(People.isFeedable({ mode: m }), false, m);
    assert.strictEqual(People.isFeedable(null), false);
  });

});

describe('people-feed.test.js', () => {

  const test = require('node:test');
  const assert = require('node:assert');
  const Log = require('../js/log.js');
  Log.setConsole(false);
  const MapData = require('../js/data/maps.js');
  const World = require('../js/world.js');
  require('../js/raycast.js');
  require('../js/sonar.js');
  const People = require('../js/people.js');

  function setup() {
    const def = MapData.maps.test;
    const world = World.load(def);
    const st = People.create(world, def, { seed: 3 });
    return { world: world, st: st };
  }

  test('feedTarget finds person in reach and arc', () => {
    const { st } = setup();
    const p = st.people[0];
    p.x = 5; p.y = 5;
    assert.strictEqual(People.feedTarget(st, 4.3, 5, 0), p);
    assert.strictEqual(People.feedTarget(st, 4.3, 5.2, 0.1), p);
  });

  test('feedTarget out of reach / behind / custom reach', () => {
    const { st } = setup();
    const p = st.people[0];
    p.x = 5; p.y = 5;
    assert.strictEqual(People.feedTarget(st, 3.4, 5, 0), null);
    assert.strictEqual(People.feedTarget(st, 3.6, 5, 0), p);
    assert.strictEqual(People.feedTarget(st, 3.4, 5, 0, 2), p);
    assert.strictEqual(People.feedTarget(st, 3.8, 5, 0, 1.0), null);
    assert.strictEqual(People.feedTarget(st, 4.3, 5, Math.PI), null);
    assert.strictEqual(People.feedTarget(st, 4.3, 5, Math.PI / 2 + 0.2 - Math.PI / 2 + Math.PI / 3 + 0.2), null);
    assert.strictEqual(People.feedTarget(st, 4.3, 5, 7 * Math.PI / 6 - 0.0), null);
  });

  test('feedTarget picks nearest and includes fleeing/cowering, skips fed', () => {
    const { st } = setup();
    const [a, b] = st.people;
    a.x = 5; a.y = 5; b.x = 5.5; b.y = 5;
    assert.strictEqual(People.feedTarget(st, 4.6, 5, 0), a);
    b.x = 4.9;
    assert.strictEqual(People.feedTarget(st, 4.6, 5, 0), b);
    b.mode = 'flee';
    assert.strictEqual(People.feedTarget(st, 4.6, 5, 0), b);
    b.mode = 'fed';
    assert.strictEqual(People.feedTarget(st, 4.6, 5, 0), a);
    a.mode = 'cower';
    assert.strictEqual(People.feedTarget(st, 4.6, 5, 0), a);
    a.mode = 'fed';
    assert.strictEqual(People.feedTarget(st, 4.6, 5, 0), null);
    a.mode = 'bogus';
    assert.strictEqual(People.feedTarget(st, 4.6, 5, 0), null);
  });

  test('isFeedable modes', () => {
    for (const m of ['path', 'startle', 'flee', 'cower']) assert.strictEqual(People.isFeedable({ mode: m }), true);
    for (const m of ['fed', 'idle', undefined]) assert.strictEqual(People.isFeedable({ mode: m }), false);
  });

  test('markFed sets mode and isFeedable false', () => {
    const { st } = setup();
    const p = st.people[1];
    p.state = 'walk'; p.phase = 0.7;
    assert.strictEqual(People.isFeedable(p), true);
    assert.strictEqual(People.markFed(st, p.id), true);
    assert.strictEqual(p.mode, 'fed');
    assert.strictEqual(p.state, 'idle');
    assert.strictEqual(p.phase, 0);
    assert.strictEqual(People.isFeedable(p), false);
    assert.strictEqual(People.snapshot(st)[1].mode, 'fed');
    assert.strictEqual(People.markFed(st, 999), false);
  });

  test('fed person stays fixed for 30 s even when player lit and adjacent', () => {
    const { world, st } = setup();
    const p = st.people[0];
    People.markFed(st, p.id);
    const x = p.x, y = p.y, ang = p.angle;
    const ctx = { player: { x: x - 0.5, y: y }, playerLit: 1, t: 0 };
    for (let i = 0; i < 300; i++) People.update(st, world, 0.1, ctx);
    assert.strictEqual(p.x, x);
    assert.strictEqual(p.y, y);
    assert.strictEqual(p.angle, ang);
    assert.strictEqual(p.mode, 'fed');
    assert.strictEqual(People.drainEvents(st).filter((e) => e.id === p.id).length, 0);
    // others still move
    const q = st.people[1];
    assert.notStrictEqual(q.mode, 'fed');
  });

  test('fed person also inert without ctx', () => {
    const { world, st } = setup();
    const p = st.people[2];
    People.markFed(st, p.id);
    const x = p.x, y = p.y;
    for (let i = 0; i < 300; i++) People.update(st, world, 0.1);
    assert.strictEqual(p.x, x);
    assert.strictEqual(p.y, y);
    assert.strictEqual(p.mode, 'fed');
  });

  test('react ignores fed', () => {
    const { world, st } = setup();
    const p = st.people[0];
    People.markFed(st, p.id);
    People.react(st, p.x + 0.5, p.y, 'door', { player: { x: p.x - 0.5, y: p.y }, playerLit: 1 });
    assert.strictEqual(p.mode, 'fed');
    assert.strictEqual(People.drainEvents(st).length, 0);
  });

  test('bad args never throw', () => {
    const { st } = setup();
    for (const bad of [null, undefined, {}, { people: null }, 5, 'x']) {
      assert.strictEqual(People.feedTarget(bad, 1, 1, 0), null);
      assert.strictEqual(People.markFed(bad, 0), false);
    }
    assert.strictEqual(People.feedTarget(st, NaN, 1, 0), null);
    assert.strictEqual(People.feedTarget(st, 1, undefined, 0), null);
    assert.strictEqual(People.feedTarget(st, 1, 1, NaN), null);
    st.people[0].x = 1.2; st.people[0].y = 1;
    assert.strictEqual(People.feedTarget(st, 1, 1, 0, NaN, -1), st.people[0]);
    assert.strictEqual(People.markFed(st, undefined), false);
    assert.strictEqual(People.isFeedable(null), false);
  });

});

describe('people-drink.test.js', () => {

  const test = require('node:test');
  const assert = require('node:assert');
  const Log = require('../js/log.js');
  Log.setConsole(false);
  const MapData = require('../js/data/maps.js');
  const World = require('../js/world.js');
  require('../js/raycast.js');
  require('../js/sonar.js');
  const People = require('../js/people.js');

  function setup(seed) {
    const def = MapData.maps.test;
    const world = World.load(def);
    const st = People.create(world, def, { seed: seed === undefined ? 3 : seed });
    return { world: world, st: st, p: st.people[0] };
  }
  const FAR = { player: { x: 1000, y: 1000 }, playerLit: 0 };

  test('pool is seeded 30-50, left = pool, deterministic per seed', () => {
    const a = setup(5).st;
    const b = setup(5).st;
    const c = setup(6).st;
    assert.ok(a.people.length > 0);
    for (let i = 0; i < a.people.length; i++) {
      const p = a.people[i];
      assert.ok(p.pool >= 30 && p.pool <= 50);
      assert.strictEqual(p.left, p.pool);
      assert.strictEqual(p.dazedLeft, 0);
      assert.strictEqual(p.pool, b.people[i].pool);
    }
    assert.ok(a.people.some((p, i) => p.pool !== c.people[i].pool));
    const snap = People.snapshot(a)[0];
    assert.strictEqual(snap.pool, a.people[0].pool);
    assert.strictEqual(snap.left, a.people[0].left);
  });

  test('grab sets grapple; not feedable; false when not feedable', () => {
    const { st, p } = setup();
    p.phase = 2;
    assert.strictEqual(People.grab(st, p.id), true);
    assert.strictEqual(p.mode, 'grapple');
    assert.strictEqual(p.phase, 0);
    assert.strictEqual(People.isFeedable(p), false);
    assert.strictEqual(People.grab(st, p.id), false);
    assert.strictEqual(People.grab(st, 999), false);
    People.markFed(st, p.id);
    assert.strictEqual(People.isFeedable(p), false);
  });

  test('isFeedable modes', () => {
    for (const m of ['path', 'startle', 'flee', 'cower', 'dazed']) assert.strictEqual(People.isFeedable({ mode: m }), true, m);
    for (const m of ['grapple', 'fed']) assert.strictEqual(People.isFeedable({ mode: m }), false, m);
  });

  test('grapple is skipped by update and react', () => {
    const { world, st, p } = setup();
    People.grab(st, p.id);
    const x = p.x, y = p.y;
    People.update(st, world, 0.1, { player: { x: p.x + 0.5, y: p.y }, playerLit: 1 });
    for (let i = 0; i < 20; i++) People.update(st, world, 0.1, FAR);
    People.react(st, p.x, p.y, 'clap', FAR);
    assert.strictEqual(p.mode, 'grapple');
    assert.strictEqual(p.x, x);
    assert.strictEqual(p.y, y);
    assert.strictEqual(People.drainEvents(st).length, 0);
  });

  test('release gives dazed keeping left; dazed stands still and ignores react', () => {
    const { world, st, p } = setup();
    People.drink(st, p.id, 10);
    const left = p.left;
    People.grab(st, p.id);
    assert.strictEqual(People.release(st, p.id, 1, 2), true);
    assert.strictEqual(p.mode, 'dazed');
    assert.strictEqual(p.left, left);
    assert.strictEqual(p.dazedLeft, 3);
    assert.deepStrictEqual({ x: p.fleeFrom.x, y: p.fleeFrom.y }, { x: 1, y: 2 });
    assert.strictEqual(People.isFeedable(p), true);
    assert.strictEqual(People.release(st, p.id, 1, 2), false);
    const x = p.x, y = p.y;
    People.react(st, p.x, p.y, 'clap', FAR);
    People.update(st, world, 0.1, FAR);
    assert.strictEqual(p.mode, 'dazed');
    assert.strictEqual(p.x, x);
    assert.strictEqual(p.y, y);
  });

  test('dazed can be grabbed again and keeps left', () => {
    const { st, p } = setup();
    People.grab(st, p.id);
    People.release(st, p.id, 0, 0);
    assert.strictEqual(People.grab(st, p.id), true);
    assert.strictEqual(p.mode, 'grapple');
  });

  test('dazed flees quietly after dazedTime (no scream, one flee event)', () => {
    const { world, st, p } = setup();
    People.grab(st, p.id);
    People.release(st, p.id, p.x - 2, p.y);
    People.drainEvents(st);
    let t = 0;
    while (p.mode === 'dazed' && t < 10) { People.update(st, world, 0.1, FAR); t += 0.1; }
    assert.ok(t >= 2.9 && t <= 3.3, 'dazed lasted ' + t);
    assert.ok(p.mode === 'flee' || p.mode === 'cower');
    const ev = People.drainEvents(st);
    assert.strictEqual(ev.filter((e) => e.type === 'scream').length, 0);
    const fl = ev.filter((e) => e.type === 'flee');
    assert.strictEqual(fl.length, 1);
    assert.strictEqual(fl[0].id, p.id);
  });

  test('dazedTime override via ctx.react', () => {
    const { world, st, p } = setup();
    const ctx = { player: { x: 1000, y: 1000 }, playerLit: 0, react: { dazedTime: 1 } };
    People.update(st, world, 0.05, ctx);
    People.grab(st, p.id);
    People.release(st, p.id, 0, 0);
    assert.strictEqual(p.dazedLeft, 1);
  });

  test('loud flee emits scream and flee events', () => {
    const { world, st, p } = setup();
    People.drainEvents(st);
    People.update(st, world, 0.1, { player: { x: p.x + 0.5, y: p.y }, playerLit: 1 });
    const types = People.drainEvents(st).map((e) => e.type);
    assert.ok(types.includes('scream'));
    assert.ok(types.includes('flee'));
    assert.strictEqual(p.mode === 'flee' || p.mode === 'cower', true);
  });

  test('react honours the dist argument', () => {
    const { st, p } = setup();
    const q = st.people[1];
    const x0 = p.x + 5, y0 = p.y;
    q.x = 900; q.y = 900;
    People.react(st, x0, y0, 'heartbeat', FAR);
    assert.strictEqual(p.mode, 'path');
    People.react(st, x0, y0, 'heartbeat', FAR, 4.9);
    assert.strictEqual(p.mode, 'path');
    People.react(st, x0, y0, 'heartbeat', FAR, 5.1);
    assert.strictEqual(p.mode, 'startle');
    const p2 = setup().p;
    const s2 = setup().st;
    s2.people[0].x = 5; s2.people[0].y = 5;
    People.react(s2, 5.5, 5, 'x', FAR, 0.2);
    assert.strictEqual(s2.people[0].mode, 'path');
    People.react(s2, 5.5, 5, 'x', FAR);
    assert.strictEqual(s2.people[0].mode, 'startle');
    assert.ok(p2);
  });

  test('drink reduces left, floors at 0, returns new left', () => {
    const { st, p } = setup();
    const pool = p.pool;
    assert.strictEqual(People.drink(st, p.id, 5), pool - 5);
    assert.strictEqual(p.left, pool - 5);
    assert.strictEqual(People.drink(st, p.id, NaN), pool - 5);
    assert.strictEqual(People.drink(st, p.id, -3), pool - 5);
    assert.strictEqual(People.drink(st, p.id, 1e6), 0);
    assert.strictEqual(People.drink(st, 999, 1), -1);
    assert.strictEqual(People.drink(null, 0, 1), -1);
  });

  test('bad inputs never throw', () => {
    assert.strictEqual(People.grab(null, 0), false);
    assert.strictEqual(People.release(undefined, 0, 0, 0), false);
  });

});

describe('people-shuffle.test.js', () => {

  const test = require('node:test');
  const assert = require('node:assert');
  const Log = require('../js/log.js');
  const MapData = require('../js/data/maps.js');
  const World = require('../js/world.js');
  const People = require('../js/people.js');

  Log.setConsole(false);
  const all = World.loadAll(MapData);
  const world = all.worlds.town;
  const def = MapData.maps.town;

  function starts(st) { return st.people.map(p => [p.x, p.y, p.idx].join(',')).join('|'); }

  test('deterministic per seed', () => {
    const a = People.create(world, def, { seed: 7, shuffle: true });
    const b = People.create(world, def, { seed: 7, shuffle: true });
    assert.strictEqual(starts(a), starts(b));
  });

  test('different seeds give different start positions', () => {
    const seen = new Set();
    for (let s = 1; s <= 8; s++) seen.add(starts(People.create(world, def, { seed: s, shuffle: true })));
    assert.ok(seen.size > 1);
  });

  test('starts are on path points and not blocked', () => {
    for (let s = 1; s <= 10; s++) {
      const st = People.create(world, def, { seed: s, shuffle: true });
      for (const p of st.people) {
        assert.ok(p.path.some(q => q.x === p.x && q.y === p.y));
        assert.strictEqual(world.blocks(p.x, p.y, 0.2), false);
        assert.ok(p.idx >= 0 && p.idx < p.path.length);
      }
    }
  });

  test('simulation 20s: no NaN, not blocked, keeps moving', () => {
    for (let s = 1; s <= 4; s++) {
      const st = People.create(world, def, { seed: s, shuffle: true });
      const first = starts(st);
      for (let i = 0; i < 20 * 60; i++) People.update(st, world, 1 / 60);
      for (const p of st.people) {
        assert.ok(isFinite(p.x) && isFinite(p.y) && isFinite(p.angle));
        assert.strictEqual(world.blocks(p.x, p.y, 0.2), false);
      }
      assert.notStrictEqual(starts(st), first);
    }
  });

  test('shuffle false is identical to no opts', () => {
    const a = People.create(world, def, { seed: 3 });
    const b = People.create(world, def, { seed: 3, shuffle: false });
    const strip = st => JSON.stringify(st.people);
    assert.strictEqual(strip(a), strip(b));
    assert.strictEqual(a.rng(), b.rng());
  });

});

describe('people-a3.test.js', () => {

  const test = require('node:test');
  const assert = require('node:assert');
  const Log = require('../js/log.js');
  const World = require('../js/world.js');
  const People = require('../js/people.js');

  Log.setConsole(false);
  const DT = 1 / 60;

  function grid(w, h) {
    const rows = [];
    for (let r = 0; r < h; r++) {
      let s = '';
      for (let c = 0; c < w; c++) s += (r === 0 || r === h - 1 || c === 0 || c === w - 1) ? '#' : '.';
      rows.push(s);
    }
    return rows;
  }
  function setCh(rows, col, row, ch) {
    const out = rows.slice();
    out[row] = out[row].slice(0, col) + ch + out[row].slice(col + 1);
    return out;
  }
  function scene(paths) {
    const def = { name: 'a3', rows: setCh(grid(21, 9), 4, 4, 'P'), paths: paths };
    const world = World.load(def, { requireStart: false });
    return { world: world, st: People.create(world, def, { seed: 7 }) };
  }
  const LOOP = [{ points: [[4, 4], [12, 4], [12, 6], [4, 6]], waits: [1, 1, 1, 1], speed: 1.2 }];
  function run(s, sec, c) {
    for (let i = 0; i < Math.round(sec / DT); i++) People.update(s.st, s.world, DT, c);
  }

  test('front bump freezes 0.4 s (grabbable) then flees', () => {
    const s = scene(LOOP);
    const c = { player: { x: 4.5 + 0.8, y: 4.5 }, playerLit: 0 };
    People.update(s.st, s.world, DT, c);
    const p = s.st.people[0];
    assert.strictEqual(p.mode, 'startle');
    assert.strictEqual(People.isFeedable(p), true);
    run(s, 0.3, c);
    assert.strictEqual(p.mode, 'startle');
    run(s, 0.2, c);
    assert.strictEqual(p.mode, 'flee');
  });

  test('lit from behind within bumpDist is noticed; bumpDist 0 disables; react overrides', () => {
    let s = scene(LOOP);
    People.update(s.st, s.world, DT, { player: { x: 3.8, y: 4.5 }, playerLit: 1 });
    assert.strictEqual(s.st.people[0].mode, 'startle');
    s = scene(LOOP);
    People.update(s.st, s.world, DT, { player: { x: 4.2, y: 4.5 }, playerLit: 0, react: { bumpDist: 0 } });
    assert.strictEqual(s.st.people[0].mode, 'path');
    s = scene(LOOP);
    People.update(s.st, s.world, DT, { player: { x: 3.8, y: 4.5 }, playerLit: 0, react: { bumpBackDist: 1 } });
    assert.strictEqual(s.st.people[0].mode, 'startle');
    s = scene(LOOP);
    People.update(s.st, s.world, DT, { player: { x: 5.3, y: 4.5 }, playerLit: 0, react: { bumpFreeze: 0 } });
    assert.strictEqual(s.st.people[0].mode, 'flee');
  });

  test('bump at the side (90 deg) is inside bumpArc 100 deg', () => {
    const s = scene(LOOP);
    People.update(s.st, s.world, DT, { player: { x: 4.5, y: 5.3 }, playerLit: 0 });
    assert.strictEqual(s.st.people[0].mode, 'startle');
  });

  test('wary after flee: 20 s, resumes at the farthest waypoint, halved sight', () => {
    const s = scene(LOOP);
    const p = s.st.people[0];
    People.update(s.st, s.world, DT, { player: { x: 7.5, y: 4.5 }, playerLit: 1 });
    assert.strictEqual(p.mode, 'flee');
    const away = { player: { x: 1.5, y: 1.5 }, playerLit: 0 };
    run(s, 11, away);
    assert.strictEqual(p.mode, 'path');
    assert.ok(p.wary > 0 && p.wary <= 20);
    const snap = People.snapshot(s.st)[0];
    assert.strictEqual(snap.wary, true);
    assert.ok(snap.waryLeft > 0);
    // Halved sight: 5 cells lit in the cone is beyond 8/2 = 4.
    p.x = 4.5; p.y = 4.5; p.angle = 0; p.lookAngle = 0;
    People.update(s.st, s.world, DT, { player: { x: 9.5, y: 4.5 }, playerLit: 1 });
    assert.strictEqual(p.mode, 'path');
    p.wary = 0;
    People.update(s.st, s.world, DT, { player: { x: 9.5, y: 4.5 }, playerLit: 1 });
    assert.strictEqual(p.mode, 'flee');
  });

  test('wary expires after waryTime; waryTime 0 never sets it', () => {
    let s = scene(LOOP);
    let p = s.st.people[0];
    People.update(s.st, s.world, DT, { player: { x: 7.5, y: 4.5 }, playerLit: 1 });
    run(s, 11, { player: { x: 1.5, y: 1.5 }, playerLit: 0 });
    run(s, 21, { player: { x: 1.5, y: 1.5 }, playerLit: 0 });
    assert.strictEqual(p.wary, 0);
    s = scene(LOOP);
    p = s.st.people[0];
    const c = { player: { x: 7.5, y: 4.5 }, playerLit: 1, react: { waryTime: 0 } };
    People.update(s.st, s.world, DT, c);
    run(s, 11, { player: { x: 1.5, y: 1.5 }, playerLit: 0, react: { waryTime: 0 } });
    assert.strictEqual(p.mode, 'path');
    assert.strictEqual(p.wary, 0);
  });

  test('whimper events every 1.5 s while cowering and while dazed', () => {
    const s = scene([{ points: [[4, 4]] }]);
    People.update(s.st, s.world, DT, { player: { x: 7.5, y: 4.5 }, playerLit: 1 });
    assert.strictEqual(s.st.people[0].mode, 'cower');
    People.drainEvents(s.st);
    run(s, 4.6, { player: { x: 7.5, y: 4.5 }, playerLit: 1 });
    const w = People.drainEvents(s.st).filter((e) => e.type === 'whimper');
    assert.strictEqual(w.length, 3);
    assert.strictEqual(w[0].id, 0);
    // dazed
    const d = scene(LOOP);
    const p = d.st.people[0];
    assert.ok(People.grab(d.st, 0));
    People.drainEvents(d.st);
    People.release(d.st, 0, 0, 0);
    for (let i = 0; i < Math.round(3.2 / DT) && p.mode === 'dazed'; i++) People.update(d.st, d.world, DT);
    const dw = People.drainEvents(d.st).filter((e) => e.type === 'whimper');
    assert.strictEqual(dw.length, 2); // at 1.5 s and 3.0 s of the 3 s daze
  });

  test('def.sit: stays put idle and looks around; startled cowering returns to seat', () => {
    const s = scene([{ sit: true, points: [[4, 4], [12, 4]] }]);
    const p = s.st.people[0];
    run(s, 15, null);
    assert.ok(Math.abs(p.x - 4.5) < 1e-9 && Math.abs(p.y - 4.5) < 1e-9);
    assert.strictEqual(p.state, 'idle');
    assert.notStrictEqual(p.lookAngle, 0);
    People.update(s.st, s.world, DT, { player: { x: 7.5, y: 4.5 }, playerLit: 1 });
    assert.strictEqual(p.mode, 'flee');
    run(s, 40, { player: { x: 1.5, y: 1.5 }, playerLit: 0 });
    assert.strictEqual(p.mode, 'path');
    assert.ok(Math.hypot(p.x - 4.5, p.y - 4.5) < 0.1);
    assert.strictEqual(p.state, 'idle');
  });

  test('def.sit with no points and shuffle: still stationary', () => {
    const def = { name: 'a3', rows: setCh(grid(21, 9), 4, 4, 'P'), paths: [{ sit: true }] };
    const world = World.load(def, { requireStart: false });
    const st = People.create(world, def, { seed: 3, shuffle: true });
    for (let i = 0; i < 600; i++) People.update(st, world, DT);
    assert.strictEqual(st.people[0].x, 4.5);
  });

  test('def.loop: true loops through all points repeatedly', () => {
    const s = scene([{ loop: true, points: [[4, 4], [8, 4], [8, 6], [4, 6]], waits: [0.2, 0.2, 0.2, 0.2] }]);
    const seen = new Set();
    for (let i = 0; i < 60 * 40; i++) {
      People.update(s.st, s.world, DT);
      const p = s.st.people[0];
      for (let k = 0; k < 4; k++) if (p.state === 'idle' && Math.hypot(p.x - [4.5, 8.5, 8.5, 4.5][k], p.y - [4.5, 4.5, 6.5, 6.5][k]) < 0.05) seen.add(k);
    }
    assert.strictEqual(seen.size, 4);
  });
});
