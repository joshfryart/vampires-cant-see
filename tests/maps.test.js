'use strict';
const test = require('node:test');
const assert = require('node:assert');
const Log = require('../js/log.js');
const MapData = require('../js/data/maps.js');
const World = require('../js/world.js');
const People = require('../js/people.js');

Log.setConsole(false);

const NAMES = Object.keys(MapData.maps).sort();
const START = MapData.startMap;
const NON_TEST = NAMES.filter((n) => n !== 'test');
const FLOOR_CHARS = World.FLOORS + '@CSP';
// Cells a villager may stand on, or that may sit just inside a door: floor and markers, never P.
const CLEAR_CHARS = World.FLOORS + '@S';
const BUILDINGS = ['tavern', 'church', 'house1', 'house2', 'cellar', 'barn', 'shed'];
const DIRS = [[0, -1], [0, 1], [1, 0], [-1, 0]];

let loaded = null;
function all() {
  if (!loaded) loaded = World.loadAll(MapData);
  return loaded;
}
function countP(rows) {
  let n = 0;
  rows.forEach((row) => { for (const ch of row) if (ch === 'P') n++; });
  return n;
}
function linkDoors(name) {
  return MapData.maps[name].doors || [];
}
function zoneRect(name) {
  const z = (MapData.maps.town.zones || []).find((x) => x.name === name);
  assert.ok(z, 'no zone named ' + name);
  return z;
}
/** Local doors: D tiles that have no doors[] entry (building entrances). */
function localDoors(def) {
  const linked = new Set(linkDoors(def.name || '').map((d) => d.col + ',' + d.row));
  const out = [];
  def.rows.forEach((row, r) => {
    for (let c = 0; c < row.length; c++) {
      if (row[c] === 'D' && !linked.has(c + ',' + r)) out.push({ col: c, row: r });
    }
  });
  return out;
}
/** Every cell a path touches, including segments and the closing loop back to the first point. */
function pathCells(def) {
  const set = new Set();
  (def.paths || []).forEach((p) => {
    const pts = p.points;
    for (let i = 0; i < pts.length; i++) {
      const a = pts[i];
      const b = pts[(i + 1) % pts.length];
      const steps = Math.max(Math.abs(b[0] - a[0]), Math.abs(b[1] - a[1]), 1) * 10;
      for (let s = 0; s <= steps; s++) {
        const x = a[0] + ((b[0] - a[0]) * s) / steps;
        const y = a[1] + ((b[1] - a[1]) * s) / steps;
        set.add(Math.floor(x) + ',' + Math.floor(y));
      }
    }
  });
  return set;
}
function zoneNameAt(w, c, r) {
  return w.zoneAt(c + 0.5, r + 0.5);
}

test('start map is crypt and the expected maps exist', () => {
  assert.strictEqual(START, 'crypt');
  assert.deepStrictEqual(NAMES, ['crypt', 'test', 'town']);
  assert.deepStrictEqual(MapData.links, []);
});

test('every map validates on its own', () => {
  NAMES.forEach((name) => {
    const res = World.validate(MapData.maps[name], NAMES, [], { requireStart: name === START || name === 'test' });
    assert.deepStrictEqual(res.errors.map((e) => e.message), [], 'map ' + name);
    assert.strictEqual(res.ok, true, 'map ' + name);
  });
});

test('validateAll passes for the shipped data', () => {
  const res = World.validateAll(MapData);
  assert.deepStrictEqual(res.errors, []);
  assert.strictEqual(res.ok, true);
});

test('loadAll builds one world per map, starting at crypt', () => {
  const res = all();
  assert.strictEqual(res.startMap, START);
  assert.deepStrictEqual(Object.keys(res.worlds).sort(), NAMES);
  NAMES.forEach((n) => assert.strictEqual(res.worlds[n].name, n));
});

test('every non-test map is reachable from crypt', () => {
  const reach = World.reachable(MapData, START);
  assert.strictEqual(reach[0], START);
  assert.deepStrictEqual(reach.slice().sort(), NON_TEST);
});

test('the only link is crypt <-> town, and it is symmetric', () => {
  assert.strictEqual(linkDoors('crypt').length, 1);
  assert.strictEqual(linkDoors('crypt')[0].toMap, 'town');
  assert.strictEqual(linkDoors('town').length, 1);
  assert.strictEqual(linkDoors('town')[0].toMap, 'crypt');
  assert.strictEqual(linkDoors('test').length, 0);
  NAMES.forEach((name) => {
    linkDoors(name).forEach((d) => {
      const tag = name + '.' + d.id;
      assert.ok(MapData.maps[d.toMap], tag + ' targets a missing map');
      const back = linkDoors(d.toMap).find((x) => x.id === d.toDoor);
      assert.ok(back, tag + ' targets a missing door');
      assert.strictEqual(back.toMap, name, tag + ' is one-way');
      assert.strictEqual(back.toDoor, d.id, tag + ' is one-way');
    });
  });
});

test('every link door sits on a D or G cell', () => {
  NAMES.forEach((name) => {
    const rows = MapData.maps[name].rows;
    linkDoors(name).forEach((d) => {
      assert.ok('DG'.includes(rows[d.row][d.col]), name + '.' + d.id + ' is not a door tile');
    });
  });
});

test('arrival cells are walkable floor with no solid prop', () => {
  const worlds = all().worlds;
  NAMES.forEach((name) => {
    const w = worlds[name];
    linkDoors(name).forEach((d) => {
      const tag = name + '.' + d.id;
      const a = w.arrival(d.id);
      assert.ok(a, tag + ' has no arrival');
      assert.ok(FLOOR_CHARS.includes(w.tileAt(a.x, a.y)), tag + ' arrival is not floor');
      assert.ok(!w.blocks(a.x, a.y, 0.2), tag + ' arrival is blocked');
    });
  });
});

test('town has at least 8 lights; crypt has none', () => {
  const worlds = all().worlds;
  assert.ok(worlds.town.lights.length >= 8, 'town lights: ' + worlds.town.lights.length);
  assert.strictEqual(worlds.crypt.lights.length, 0);
});

test('crypt is dark and empty: no lights, no people', () => {
  const worlds = all().worlds;
  assert.strictEqual(worlds.crypt.lights.length, 0);
  assert.strictEqual(countP(MapData.maps.crypt.rows), 0);
  assert.strictEqual(worlds.crypt.spots.people.length, 0);
  assert.strictEqual(People.create(worlds.crypt, MapData.maps.crypt, { seed: 1 }).people.length, 0);
});

test('one person per P tile, one path per P, and every path is accepted', () => {
  const worlds = all().worlds;
  NAMES.forEach((name) => {
    const def = MapData.maps[name];
    const st = People.create(worlds[name], def, { seed: 1 });
    const p = countP(def.rows);
    assert.strictEqual(st.people.length, p, name + ' people');
    assert.strictEqual((def.paths || []).length, p, name + ' paths');
    st.people.forEach((person) => {
      assert.ok(person.path.length > 1, name + ' person ' + person.id + ' fell back to idle at its spawn');
    });
  });
});

test('town has 14 people in total, and the other maps have none', () => {
  const worlds = all().worlds;
  assert.strictEqual(countP(MapData.maps.town.rows), 14);
  assert.strictEqual(People.create(worlds.town, MapData.maps.town, { seed: 1 }).people.length, 14);
  assert.strictEqual(countP(MapData.maps.crypt.rows), 0);
});

test('kind and floor match the contract', () => {
  const want = {
    crypt: ['indoor', 'stone'],
    town: ['outdoor', 'grass']
  };
  const worlds = all().worlds;
  Object.keys(want).forEach((name) => {
    assert.deepStrictEqual([worlds[name].kind, worlds[name].floor], want[name], name);
  });
});

test('map sizes match the contract and fit the caps', () => {
  const want = { crypt: [14, 10], town: [64, 48] };
  Object.keys(want).forEach((name) => {
    const rows = MapData.maps[name].rows;
    assert.deepStrictEqual([rows[0].length, rows.length], want[name], name);
  });
  NAMES.forEach((name) => {
    const rows = MapData.maps[name].rows;
    assert.ok(rows[0].length <= 64 && rows.length <= 48, name + ' exceeds the cap');
    rows.forEach((r) => assert.strictEqual(r.length, rows[0].length, name + ' is not rectangular'));
  });
});

test('town zones are valid and named exactly as the contract lists', () => {
  const res = World.validate(MapData.maps.town, NAMES, [], { requireStart: false });
  assert.deepStrictEqual(res.errors.filter((e) => e.code === 'E_MAP_BAD_ZONE').map((e) => e.message), []);
  const names = (MapData.maps.town.zones || []).map((z) => z.name).sort();
  assert.deepStrictEqual(names, ['barn', 'cellar', 'church', 'house1', 'house2', 'mausoleum', 'shed', 'tavern']);
  (MapData.maps.town.zones || []).forEach((z) => {
    assert.ok(z.kind === 'indoor' || z.kind === 'outdoor', z.name + ' kind');
  });
});

test('each building door has at least 2 clear floor cells inside, with no person or path cell', () => {
  const def = MapData.maps.town;
  const w = all().worlds.town;
  const paths = pathCells(def);
  const doors = localDoors(def);
  assert.strictEqual(doors.length, 7, 'local building doors: ' + doors.length);
  const reached = new Set();
  doors.forEach((d) => {
    const tag = 'town door (' + d.col + ',' + d.row + ')';
    const inside = DIRS.filter(([dx, dy]) => {
      const z1 = zoneNameAt(w, d.col + dx, d.row + dy);
      const z2 = zoneNameAt(w, d.col + 2 * dx, d.row + 2 * dy);
      const back = zoneNameAt(w, d.col - dx, d.row - dy);
      return z1 && z1 === z2 && z1 !== back;
    });
    assert.ok(inside.length >= 1, tag + ' has no zone on either side');
    inside.forEach(([dx, dy]) => {
      const zone = zoneNameAt(w, d.col + dx, d.row + dy);
      reached.add(zone);
      for (let k = 1; k <= 2; k++) {
        const c = d.col + k * dx;
        const r = d.row + k * dy;
        const cell = tag + ' inside cell ' + k + ' (' + c + ',' + r + ') in ' + zone;
        assert.ok(CLEAR_CHARS.includes(def.rows[r][c]), cell + ' is not clear floor');
        assert.notStrictEqual(def.rows[r][c], 'P', cell + ' holds a person');
        assert.ok(!w.blocks(c + 0.5, r + 0.5, 0.2), cell + ' is blocked');
        assert.ok(!paths.has(c + ',' + r), cell + ' is on a path');
      }
    });
  });
  BUILDINGS.forEach((name) => assert.ok(reached.has(name), 'no local door leads into ' + name));
});

test('cellar, barn and mausoleum are dark: lightAt is 0 at every floor cell', () => {
  const w = all().worlds.town;
  const rows = MapData.maps.town.rows;
  ['cellar', 'barn', 'mausoleum'].forEach((name) => {
    const z = zoneRect(name);
    for (let r = z.y0; r <= z.y1; r++) {
      for (let c = z.x0; c <= z.x1; c++) {
        if (!FLOOR_CHARS.includes(rows[r][c])) continue;
        assert.strictEqual(w.lightAt(c + 0.5, r + 0.5), 0, name + ' cell (' + c + ',' + r + ') is lit');
      }
    }
  });
});

test('tavern zone is indoor and a street cell is outdoor', () => {
  const w = all().worlds.town;
  const z = zoneRect('tavern');
  for (let r = z.y0; r <= z.y1; r++) {
    for (let c = z.x0; c <= z.x1; c++) {
      assert.strictEqual(w.kindAt(c + 0.5, r + 0.5), 'indoor', 'tavern cell (' + c + ',' + r + ')');
    }
  }
  assert.strictEqual(w.kindAt(1.5, 1.5), 'outdoor');
  assert.strictEqual(w.zoneAt(1.5, 1.5), null);
});

test('town: crypt has one C and no S; town has 3 safe spots, all dark with dark neighbours', () => {
  const worlds = all().worlds;
  assert.strictEqual(worlds.crypt.spots.safe.length, 0);
  assert.strictEqual(worlds.crypt.spots.crypt.length, 1);
  const w = worlds.town;
  assert.strictEqual(w.spots.safe.length, 3);
  w.spots.safe.forEach((s) => {
    for (let dy = -1; dy <= 1; dy++) for (let dx = -1; dx <= 1; dx++) {
      assert.strictEqual(w.lightAt(s.x + dx, s.y + dy), 0, 'lit near safe spot ' + s.x + ',' + s.y);
    }
  });
});

test('town: every door, gate and safe spot has a dark route (lightAt < 0.6) from the crypt door', () => {
  const def = MapData.maps.town;
  const w = all().worlds.town;
  const rows = def.rows;
  const start = def.doors.find((d) => d.id === 'mausoleum');
  const free = (c, r) => r >= 0 && r < rows.length && c >= 0 && c < rows[r].length &&
    !World.WALLS.includes(rows[r][c]) && w.lightAt(c + 0.5, r + 0.5) < 0.6;
  const seen = new Set([start.col + ',' + start.row]);
  const queue = [[start.col, start.row]];
  while (queue.length) {
    const [c, r] = queue.shift();
    DIRS.forEach(([dx, dy]) => {
      const k = (c + dx) + ',' + (r + dy);
      if (!seen.has(k) && free(c + dx, r + dy)) { seen.add(k); queue.push([c + dx, r + dy]); }
    });
  }
  let targets = 0;
  rows.forEach((row, r) => {
    for (let c = 0; c < row.length; c++) {
      if (!'DGS'.includes(row[c])) continue;
      targets++;
      assert.ok(seen.has(c + ',' + r), 'no dark route to ' + row[c] + ' at ' + c + ',' + r);
    }
  });
  assert.ok(targets >= 11, 'targets ' + targets);
});

test('town hides: 6-10 dark floor cells', () => {
  const def = MapData.maps.town;
  const w = all().worlds.town;
  assert.ok(def.hides.length >= 6 && def.hides.length <= 10);
  def.hides.forEach(([c, r]) => {
    assert.ok(FLOOR_CHARS.includes(def.rows[r][c]), 'hide ' + c + ',' + r);
    assert.strictEqual(w.lightAt(c + 0.5, r + 0.5), 0, 'hide ' + c + ',' + r + ' is lit');
  });
});

test('some patrol length is torchlit (v0.10.5 radius x0.15: small share), and window light spills outside', () => {
  const def = MapData.maps.town;
  const w = all().worlds.town;
  let tot = 0, lit = 0;
  def.paths.forEach((p) => {
    for (let k = 0; k < p.points.length; k++) {
      const a = p.points[k], b = p.points[(k + 1) % p.points.length];
      const len = Math.hypot(b[0] - a[0], b[1] - a[1]);
      const n = Math.max(1, Math.ceil(len * 4));
      for (let i = 0; i < n; i++) {
        const f = (i + 0.5) / n;
        tot += len / n;
        if (w.lightAt(a[0] + 0.5 + (b[0] - a[0]) * f, a[1] + 0.5 + (b[1] - a[1]) * f) > 0) lit += len / n;
      }
    }
  });
  assert.ok(lit / tot >= 0.03, 'lit share ' + (lit / tot).toFixed(2));
  assert.strictEqual(def.rows[8][18], 'w');
  assert.ok(w.lightAt(36.5, 9.5) > 0);
  assert.ok(def.paths.filter((p) => p.sit).length >= 2);
});

test('test map is unchanged: 24 x 16 with one start tile', () => {
  const t = MapData.maps.test;
  assert.strictEqual(t.rows.length, 16);
  t.rows.forEach((r) => assert.strictEqual(r.length, 24));
  assert.strictEqual(t.rows.join('').split('@').length - 1, 1);
});
