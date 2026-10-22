'use strict';
const { describe } = require('node:test');

describe('tables.test.js (V4 dinner tables, V2 conversations)', () => {
  const test = require('node:test');
  const assert = require('node:assert');
  const fs = require('node:fs');
  const path = require('node:path');
  const Log = require('../js/log.js');
  const MapData = require('../js/data/maps.js');
  const World = require('../js/world.js');
  const Schedule = require('../js/schedule.js');
  require('../js/data/archetypes.js');
  require('../js/forge.js');
  const People = require('../js/people.js');

  Log.setConsole(false);
  const town = MapData.maps.town;
  const DT = 1 / 30;
  const worlds = World.loadAll(MapData).worlds;

  function openDoorsNear(world, st) {
    for (const p of st.people) {
      for (const d of world.spots.doors) {
        if (Math.hypot(p.x - d.x, p.y - d.y) < 1.0 && !world.isDoorOpen(Math.floor(d.x), Math.floor(d.y))) world.setDoor(Math.floor(d.x), Math.floor(d.y), true);
      }
    }
  }
  function run(st, world, secs, ctx) {
    for (let t = 0; t < secs; t += DT) {
      openDoorsNear(world, st);
      People.update(st, world, DT, Object.assign({ nightFrac: 0.3, nightSec: 240 }, ctx || {}));
    }
  }
  // Put two scheduled walkers next to each other on open ground, calm and idle.
  function pair(st, world, roleA, roleB) {
    const a = st.people.find((p) => p.sched && p.sched.role === roleA);
    const b = st.people.find((p) => p.sched && p.sched.role === roleB && p !== a);
    a.x = 28.5; a.y = 17.5; b.x = 29.3; b.y = 17.5;
    [a, b].forEach((p) => { p.state = 'idle'; p.idleLeft = 99; p.sched.en = false; p.sched.si = p.sched.target = Schedule.stopAt(p.sched.stops, 0.3); p.seated = false; p.chatCool = 0; });
    return [a, b];
  }

  test('tables sit on floor cells beside a window and their seats are open cells next to them', () => {
    const world = worlds.town;
    const tables = town.props.filter((p) => p.type === 'table');
    const byWindow = tables.filter((t) => {
      for (let dy = -4; dy <= 4; dy++) for (let dx = -4; dx <= 4; dx++) if (world.tileAt(t.col + dx + 0.5, t.row + dy + 0.5) === 'w') return true;
      return false;
    });
    assert.ok(byWindow.length >= 4, 'tables by windows: ' + byWindow.length);
    assert.ok(town.props.length < 200, 'prop count stays reasonable: ' + town.props.length);
    ['house1', 'house2', 'tavern'].forEach((zone) => {
      const seats = Object.keys(town.places).filter((k) => /_table\d?$|^tavern_t\d?$/.test(k) && world.zoneAt(town.places[k][0] + 0.5, town.places[k][1] + 0.5) === zone);
      assert.ok(seats.length >= 2, zone + ' has seats');
      seats.forEach((k) => {
        const [c, r] = town.places[k];
        assert.ok(!world.isSolid(c + 0.5, r + 0.5), k + ' is open floor');
        assert.ok(tables.some((t) => Math.abs(t.col - c) + Math.abs(t.row - r) <= 2), k + ' is beside a table');
      });
    });
  });

  test('solid tables never touch a door cell or the cells in front of it', () => {
    const world = worlds.town;
    for (const d of world.spots.doors) {
      for (const t of town.props.filter((p) => p.type === 'table')) {
        assert.ok(Math.hypot(t.col + 0.5 - d.x, t.row + 0.5 - d.y) > 1.5, 'table ' + t.col + ',' + t.row + ' near a door');
      }
    }
  });

  test('evening: family sits and eats at their table facing it; tablemates chat continuously', () => {
    const world = worlds.town;
    const st = People.create(world, town, { seed: 4, shuffle: true });
    const mother = st.people.find((p) => p.sched && p.sched.role === 'mother');
    let ate = false;
    let tableChat = false;
    for (let t = 0; t < 140; t += DT) {
      openDoorsNear(world, st);
      People.update(st, world, DT, { nightFrac: t / 240, nightSec: 240 });
      const cur = mother.sched.stops[mother.sched.si];
      if (cur && cur.act === 'eat' && !mother.sched.en && mother.seated) {
        ate = true;
        assert.ok(typeof cur.face === 'number', 'eat stop faces a table');
        if (mother.chat && mother.chat.table) tableChat = true;
      }
    }
    assert.ok(ate, 'mother sat to eat in the first half of the night');
    assert.ok(tableChat, 'mother chatted with a tablemate');
  });

  test('walkers meet: stop, face, chat for 4-10 s, then part', () => {
    const world = worlds.town;
    let seen = false;
    for (let seed = 1; seed <= 40 && !seen; seed++) {
      const st = People.create(world, town, { seed: seed });
      const [a, b] = pair(st, world, 'guard', 'guard');
      st.fear = 0;
      for (let t = 0; t < 4 && !a.chat; t += DT) { a.chatCool = 0; b.chatCool = 0; run(st, world, DT, { nightFrac: 0.3 }); a.x = 28.5; a.y = 17.5; b.x = 29.3; b.y = 17.5; }
      if (!a.chat || a.chat.kind !== 'chat') continue;
      seen = true;
      assert.strictEqual(a.chat.partner, b.id);
      assert.strictEqual(b.chat.partner, a.id);
      const start = st.time;
      const dur = a.chat.until - start;
      assert.ok(dur >= 3.5 && dur <= 10.5, 'chat length ' + dur);
      const x0 = a.x;
      run(st, world, 1, { nightFrac: 0.3 });
      assert.ok(Math.abs(a.x - x0) < 0.05, 'chatter stands still');
      assert.ok(Math.abs(Math.cos(a.angle) - 1) < 0.01, 'a faces b');
      const c = People.conversationFor(st, a.id);
      assert.strictEqual(c.partner, b.id);
      assert.strictEqual(c.kind, 'chat');
      assert.ok(People.snapshot(st)[a.id].chat);
      run(st, world, 11, { nightFrac: 0.3 });
      assert.strictEqual(a.chat, null);
      assert.strictEqual(b.chat, null);
      assert.strictEqual(People.conversationFor(st, a.id), null);
    }
    assert.ok(seen, 'some seed produced a chat');
  });

  test('any alarm ends a chat at once: flee, startle, fear, and a nearby sound', () => {
    const world = worlds.town;
    const mk = () => {
      for (let seed = 1; seed <= 60; seed++) {
        const st = People.create(world, town, { seed: seed });
        const [a, b] = pair(st, world, 'guard', 'guard');
        a.chat = { partner: b.id, kind: 'chat', until: 1e6, table: false, mood: 'neutral' };
        b.chat = { partner: a.id, kind: 'chat', until: 1e6, table: false, mood: 'neutral' };
        return { st, a, b };
      }
    };
    let k = mk();
    People.react(k.st, k.a.x, k.a.y, 'noise', { player: { x: 5, y: 5 }, playerLit: 0 }, 3);
    assert.strictEqual(k.a.chat, null);
    assert.strictEqual(k.b.chat, null);
    k = mk();
    k.b.mode = 'flee';
    run(k.st, world, DT);
    assert.strictEqual(k.a.chat, null, 'partner fleeing ends it');
    k = mk();
    run(k.st, world, DT, { fear: 6 });
    assert.strictEqual(k.a.chat, null, 'village fear ends it');
    k = mk();
    k.a.wary = 5;
    run(k.st, world, DT);
    assert.strictEqual(k.b.chat, null, 'wary ends it');
    // a drinking victim (grappled) is never held in a chat
    k = mk();
    k.a.mode = 'grapple';
    run(k.st, world, DT);
    assert.strictEqual(k.b.chat, null);
  });

  test('no chats start while the village is afraid', () => {
    const world = worlds.town;
    const st = People.create(world, town, { seed: 2 });
    const [a, b] = pair(st, world, 'guard', 'guard');
    for (let t = 0; t < 6; t += DT) { a.x = 28.5; b.x = 29.3; run(st, world, DT, { fear: 4 }); }
    assert.ok(!a.chat && !b.chat);
  });

  test('deterministic: same seed, same chat timeline', () => {
    const world = worlds.town;
    const trace = () => {
      const st = People.create(world, town, { seed: 9, shuffle: true });
      const out = [];
      for (let t = 0; t < 120; t += DT) {
        openDoorsNear(world, st);
        People.update(st, world, DT, { nightFrac: t / 240, nightSec: 240 });
        if (Math.round(t / DT) % 15 === 0) out.push(st.people.map((p) => (p.chat ? p.chat.partner + p.chat.kind : '-') + p.x.toFixed(2)).join(','));
      }
      return out;
    };
    assert.deepStrictEqual(trace(), trace());
  });

  test('chatRoll: seeded weights, family chats most, ignore gives no time', () => {
    let fam = 0;
    for (let i = 0; i < 100; i++) if (Schedule.chatRoll('mother', 'elder', true, i / 100, 0.5).kind === 'chat') fam++;
    assert.ok(fam >= 60);
    const ig = Schedule.chatRoll('drunk', 'priest', false, 0.95, 0.5);
    assert.strictEqual(ig.kind, 'ignore');
    assert.strictEqual(ig.sec, 0);
    const c = Schedule.chatRoll('mother', 'elder', true, 0.1, 1);
    assert.ok(c.sec >= 4 && c.sec <= 10);
    assert.deepStrictEqual(Schedule.chatRoll('a', 'b', false, 0.3, 0.3), Schedule.chatRoll('b', 'a', false, 0.3, 0.3));
  });

  test('chat code uses no wall clock and no unseeded randomness', () => {
    ['people.js', 'schedule.js'].forEach((f) => {
      const src = fs.readFileSync(path.join(__dirname, '..', 'js', f), 'utf8');
      assert.ok(!/Date\.now|performance\.now|Math\.random/.test(src), f);
    });
  });
});
