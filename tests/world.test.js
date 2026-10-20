'use strict';
// Merged test file: each source file's tests live in their own describe().
const { describe } = require('node:test');

describe('world.test.js', () => {

  const test = require('node:test');
  const assert = require('node:assert');
  const Log = require('../js/log.js');
  const World = require('../js/world.js');

  Log.setConsole(false);

  const GOOD = {
    name: 'test',
    rows: [
      '#######',
      '#@..C.#',
      '#.D.S.#',
      '#P.S.P#',
      '#######'
    ]
  };
  const codes = (m, names, links) => World.validate(m, names, links).errors.map((e) => e.code);
  const withRows = (rows) => ({ name: 'test', rows });

  test('TILES', () => {
    assert.deepStrictEqual(World.TILES, { WALL: '#', FLOOR: '.', START: '@', DOOR: 'D', CRYPT: 'C', SAFE: 'S', PERSON: 'P' });
  });

  test('valid map (with doors) is ok', () => {
    const r = World.validate(GOOD);
    assert.deepStrictEqual(r, { ok: true, errors: [] });
  });

  test('E_MAP_EMPTY', () => {
    assert.deepStrictEqual(codes(withRows([])), ['E_MAP_EMPTY']);
    assert.deepStrictEqual(codes(null), ['E_MAP_EMPTY']);
    assert.deepStrictEqual(codes({}), ['E_MAP_EMPTY']);
  });

  test('E_MAP_NOT_RECT with row', () => {
    const m = withRows(['#####', '#@..#', '#...', '#####']);
    const e = World.validate(m).errors.find((x) => x.code === 'E_MAP_NOT_RECT');
    assert.ok(e);
    assert.strictEqual(e.row, 2);
    assert.ok(e.message.includes('map test row 2'));
  });

  test('E_MAP_BAD_TILE with row/col', () => {
    const m = withRows(['#####', '#@x.#', '#####']);
    const e = World.validate(m).errors.find((x) => x.code === 'E_MAP_BAD_TILE');
    assert.strictEqual(e.row, 1);
    assert.strictEqual(e.col, 2);
    assert.strictEqual(e.char, 'x');
    assert.ok(e.message.includes('map test row 1 col 2'));
    assert.ok(codes(withRows(['#####', '#@ .#', '#####'])).includes('E_MAP_BAD_TILE'));
  });

  test('E_MAP_NO_START and E_MAP_MULTI_START', () => {
    assert.deepStrictEqual(codes(withRows(['####', '#..#', '####'])), ['E_MAP_NO_START']);
    assert.deepStrictEqual(codes(withRows(['#####', '#@.@#', '#####'])), ['E_MAP_MULTI_START']);
  });

  test('E_MAP_OPEN_EDGE with row/col', () => {
    const m = withRows(['#####', '#@..#', '#...#', '##.##']);
    const e = World.validate(m).errors.find((x) => x.code === 'E_MAP_OPEN_EDGE');
    assert.strictEqual(e.row, 3);
    assert.strictEqual(e.col, 2);
    assert.ok(codes(withRows(['#####', '.@..#', '#####'])).includes('E_MAP_OPEN_EDGE'));
  });

  test('E_MAP_BAD_LINK only for missing target', () => {
    const links = [{ from: 'test', to: 'nowhere', x: 2, y: 2 }];
    assert.deepStrictEqual(codes(GOOD, ['test'], links), ['E_MAP_BAD_LINK']);
    assert.deepStrictEqual(codes(GOOD, ['test', 'nowhere'], links), []);
    assert.deepStrictEqual(codes(GOOD, ['test'], []), []);
  });

  test('validate never throws on garbage', () => {
    assert.doesNotThrow(() => World.validate(undefined));
    assert.doesNotThrow(() => World.validate({ rows: [1, null] }));
    assert.strictEqual(World.validate({ name: 'x', rows: [1, null] }).ok, false);
  });

  test('load throws E_MAP_INVALID with details', () => {
    Log.clear();
    try {
      World.load(withRows(['####', '#..#', '####']));
      assert.fail('should throw');
    } catch (e) {
      assert.strictEqual(e.code, 'E_MAP_INVALID');
      assert.strictEqual(e.details[0].code, 'E_MAP_NO_START');
    }
    assert.ok(Log.entries().some((x) => x.level === 'ERROR'));
  });

  test('load returns world; dimensions, start, spots', () => {
    const w = World.load(GOOD);
    assert.strictEqual(w.name, 'test');
    assert.strictEqual(w.width, 7);
    assert.strictEqual(w.height, 5);
    assert.deepStrictEqual(w.start, { x: 1.5, y: 1.5 });
    assert.strictEqual(w.spots.crypt.length, 1);
    assert.strictEqual(w.spots.safe.length, 2);
    assert.strictEqual(w.spots.people.length, 2);
    assert.strictEqual(w.spots.doors.length, 1);
    assert.deepStrictEqual(w.spots.crypt[0], { x: 4.5, y: 1.5 });
    assert.deepStrictEqual(w.spots.doors[0], { x: 2.5, y: 2.5 });
    assert.deepStrictEqual(w.spots.people[0], { x: 1.5, y: 3.5 });
  });

  test('tileAt and out of bounds', () => {
    const w = World.load(GOOD);
    assert.strictEqual(w.tileAt(1, 1), '@');
    assert.strictEqual(w.tileAt(4, 1), 'C');
    assert.strictEqual(w.tileAt(2, 2), 'D');
    assert.strictEqual(w.tileAt(-1, 0), '#');
    assert.strictEqual(w.tileAt(0, -5), '#');
    assert.strictEqual(w.tileAt(7, 1), '#');
    assert.strictEqual(w.tileAt(1, 5), '#');
    assert.strictEqual(w.tileAt(100, 100), '#');
  });

  test('isSolid floors floats', () => {
    const w = World.load(GOOD);
    assert.strictEqual(w.isSolid(0.99, 0.5), true);
    assert.strictEqual(w.isSolid(1.0, 1.0), false);
    assert.strictEqual(w.isSolid(1.99, 1.99), false);
    assert.strictEqual(w.isSolid(2.5, 2.5), true, 'closed door is solid');
    assert.strictEqual(w.isSolid(6.5, 1.5), true);
    assert.strictEqual(w.isSolid(-0.1, 1.5), true);
  });

  test('doors start closed; setDoor opens and closes', () => {
    const w = World.load(GOOD);
    assert.strictEqual(w.isDoorOpen(2, 2), false);
    assert.strictEqual(w.setDoor(2, 2, true), true);
    assert.strictEqual(w.isDoorOpen(2, 2), true);
    assert.strictEqual(w.isSolid(2.5, 2.5), false);
    assert.strictEqual(w.setDoor(2, 2, false), true);
    assert.strictEqual(w.isSolid(2.5, 2.5), true);
  });

  test('setDoor refuses non-door cells and ignores bad input', () => {
    const w = World.load(GOOD);
    assert.strictEqual(w.setDoor(1, 1, true), false);
    assert.strictEqual(w.setDoor(-3, 99, true), false);
    assert.strictEqual(w.isDoorOpen(1, 1), false);
    assert.strictEqual(w.isDoorOpen(-3, 99), false);
  });

  test('door state is per world', () => {
    const a = World.load(GOOD);
    const b = World.load(GOOD);
    a.setDoor(2, 2, true);
    assert.strictEqual(b.isDoorOpen(2, 2), false);
  });

});

describe('world-v06.test.js', () => {

  const test = require('node:test');
  const assert = require('node:assert');
  const Log = require('../js/log.js');
  const World = require('../js/world.js');

  Log.setConsole(false);

  // Helpers -------------------------------------------------------------------

  /** w x h rectangle of walls with floor inside and a start tile at (1,1). */
  function box(w, h) {
    const rows = [];
    for (let r = 0; r < h; r++) {
      rows.push(r === 0 || r === h - 1 ? '#'.repeat(w) : '#' + '.'.repeat(w - 2) + '#');
    }
    rows[1] = '#@' + '.'.repeat(w - 3) + '#';
    return rows;
  }
  /** Copy of rows with one cell replaced. */
  function put(rows, col, row, ch) {
    const out = rows.slice();
    out[row] = out[row].slice(0, col) + ch + out[row].slice(col + 1);
    return out;
  }
  function def(rows, extra) {
    return Object.assign({ name: 't', rows: rows }, extra || {});
  }
  function codes(d, opts) {
    return World.validate(d, undefined, undefined, opts).errors.map((e) => e.code);
  }
  function messages(d, code, opts) {
    return World.validate(d, undefined, undefined, opts).errors.filter((e) => e.code === code).map((e) => e.message);
  }

  const BASE = [
    '#######',
    '#@....#',
    '#.....#',
    '###D###',
    '#######'
  ];
  const DOOR_N = [{ id: 'd', col: 3, row: 3, facing: 'n' }];

  // Validation: size ------------------------------------------------------------

  test('base map with a valid door is clean', () => {
    assert.deepStrictEqual(codes(def(BASE, { doors: DOOR_N })), []);
  });

  test('E_MAP_TOO_BIG above 64 wide or 48 tall, not at the limit', () => {
    assert.ok(codes(def(box(65, 10))).includes('E_MAP_TOO_BIG'));
    assert.ok(codes(def(box(20, 49))).includes('E_MAP_TOO_BIG'));
    assert.ok(!codes(def(box(64, 48))).includes('E_MAP_TOO_BIG'));
  });

  // Validation: doors -----------------------------------------------------------

  test('E_MAP_BAD_DOOR: door cell is not a D or G tile', () => {
    const d = def(BASE, { doors: [{ id: 'd', col: 2, row: 2, facing: 'n' }] });
    assert.ok(codes(d).includes('E_MAP_BAD_DOOR'));
    assert.ok(messages(d, 'E_MAP_BAD_DOOR')[0].includes('not on a D or G cell'));
  });

  test('E_MAP_BAD_DOOR: bad facing', () => {
    const d = def(BASE, { doors: [{ id: 'd', col: 3, row: 3, facing: 'x' }] });
    assert.ok(codes(d).includes('E_MAP_BAD_DOOR'));
    assert.ok(messages(d, 'E_MAP_BAD_DOOR')[0].includes('bad facing'));
  });

  test('E_MAP_BAD_DOOR: arrival cell is a wall (blocked arrival)', () => {
    // Facing south points into the wall row below the door.
    const d = def(BASE, { doors: [{ id: 'd', col: 3, row: 3, facing: 's' }] });
    assert.ok(codes(d).includes('E_MAP_BAD_DOOR'));
    assert.ok(messages(d, 'E_MAP_BAD_DOOR')[0].includes('not walkable floor'));
  });

  test('E_MAP_BAD_DOOR: arrival cell holds a solid prop', () => {
    const d = def(BASE, { doors: DOOR_N, props: [{ type: 'table', col: 3, row: 2 }] });
    assert.ok(codes(d).includes('E_MAP_BAD_DOOR'));
    assert.ok(messages(d, 'E_MAP_BAD_DOOR')[0].includes('solid prop'));
  });

  test('E_MAP_BAD_DOOR: duplicate id', () => {
    const d = def(BASE, { doors: [{ id: 'd', col: 3, row: 3, facing: 'n' }, { id: 'd', col: 3, row: 3, facing: 'n' }] });
    assert.ok(messages(d, 'E_MAP_BAD_DOOR').some((m) => m.includes('duplicate id')));
  });

  test('E_MAP_BAD_DOOR: door out of bounds', () => {
    const d = def(BASE, { doors: [{ id: 'd', col: 40, row: 3, facing: 'n' }] });
    assert.ok(messages(d, 'E_MAP_BAD_DOOR').some((m) => m.includes('out of bounds')));
  });

  // Validation: props -----------------------------------------------------------

  test('E_MAP_BAD_PROP: unknown type', () => {
    const d = def(BASE, { props: [{ type: 'sofa', col: 2, row: 2 }] });
    assert.ok(messages(d, 'E_MAP_BAD_PROP').some((m) => m.includes('unknown type')));
  });

  test('E_MAP_BAD_PROP: prop on a wall', () => {
    const d = def(BASE, { props: [{ type: 'table', col: 0, row: 0 }] });
    assert.ok(messages(d, 'E_MAP_BAD_PROP').some((m) => m.includes('not on a floor cell')));
  });

  test('E_MAP_BAD_PROP: two solid props on one cell', () => {
    const d = def(BASE, { props: [{ type: 'table', col: 2, row: 2 }, { type: 'barrel', col: 2, row: 2 }] });
    assert.ok(messages(d, 'E_MAP_BAD_PROP').some((m) => m.includes('shares cell')));
  });

  test('a cross may share a cell with a solid prop', () => {
    const d = def(BASE, { props: [{ type: 'table', col: 2, row: 2 }, { type: 'cross', col: 2, row: 2 }] });
    assert.ok(!codes(d).includes('E_MAP_BAD_PROP'));
  });

  // Validation: paths -----------------------------------------------------------

  test('E_MAP_BAD_PATH: a segment passes through a wall', () => {
    const d = def(BASE, { paths: [{ points: [[1, 1], [1, 4]] }] });
    assert.ok(codes(d).includes('E_MAP_BAD_PATH'));
  });

  test('E_MAP_BAD_PATH: a segment passes through a solid prop', () => {
    const d = def(BASE, {
      props: [{ type: 'table', col: 2, row: 1 }],
      paths: [{ points: [[1, 1], [4, 1], [4, 2], [1, 2]] }]
    });
    assert.ok(codes(d).includes('E_MAP_BAD_PATH'));
  });

  test('a path may cross a cross or a torch', () => {
    const d = def(BASE, {
      props: [{ type: 'cross', col: 2, row: 1 }, { type: 'torch', col: 3, row: 2 }],
      paths: [{ points: [[1, 1], [4, 1], [4, 2], [1, 2]] }]
    });
    assert.ok(!codes(d).includes('E_MAP_BAD_PATH'));
  });

  // Validation: start tile ------------------------------------------------------

  test('requireStart:false allows a map with no @; the default still requires one', () => {
    const rows = ['#####', '#...#', '#####'];
    assert.ok(codes(def(rows)).includes('E_MAP_NO_START'));
    assert.deepStrictEqual(codes(def(rows), { requireStart: false }), []);
    assert.doesNotThrow(() => World.load(def(rows), { requireStart: false }));
    assert.throws(() => World.load(def(rows)), (e) => e.code === 'E_MAP_INVALID');
  });

  test('load throws E_MAP_INVALID with details', () => {
    assert.throws(() => World.load(def(['#####'])), (e) => e.code === 'E_MAP_INVALID' && Array.isArray(e.details) && e.details.length > 0);
  });

  // Validation: link graph (validateAll / loadAll) -------------------------------

  const D = (id, toMap, toDoor) => ({ id: id, col: 3, row: 3, toMap: toMap, toDoor: toDoor, facing: 'n' });
  function room(name, doors) { return { name: name, rows: BASE, doors: doors || [] }; }
  function data(maps, startMap) {
    const o = {};
    maps.forEach((m) => { o[m.name] = m; });
    return { startMap: startMap || 'a', maps: o, links: [] };
  }
  function linkCodes(d) {
    return World.validateAll(d).errors.map((e) => e.code);
  }

  test('validateAll: a matched pair of links is clean', () => {
    const res = World.validateAll(data([room('a', [D('d1', 'b', 'd1')]), room('b', [D('d1', 'a', 'd1')])]));
    assert.deepStrictEqual(res.errors, []);
    assert.strictEqual(res.ok, true);
  });

  test('E_MAP_BAD_LINK: target map missing', () => {
    const d = data([room('a', [D('d1', 'zz', 'd1')]), room('b', [D('d1', 'a', 'd1')])]);
    assert.ok(linkCodes(d).includes('E_MAP_BAD_LINK'));
  });

  test('E_MAP_BAD_LINK: target door missing', () => {
    const d = data([room('a', [D('d1', 'b', 'nope')]), room('b', [D('d1', 'a', 'd1')])]);
    assert.ok(linkCodes(d).includes('E_MAP_BAD_LINK'));
  });

  test('E_MAP_ONEWAY: target door does not link back', () => {
    const d = data([
      room('a', [D('d1', 'b', 'd1')]),
      room('b', [D('d1', 'c', 'd1')]),
      room('c', [D('d1', 'b', 'd1')])
    ]);
    const errs = World.validateAll(d).errors.filter((e) => e.code === 'E_MAP_ONEWAY');
    assert.strictEqual(errs.length, 1);
    assert.strictEqual(errs[0].map, 'a');
    assert.strictEqual(errs[0].door, 'd1');
  });

  test('E_MAP_SELF_LINK: door links to its own map', () => {
    const d = data([room('a', [D('d1', 'a', 'd1')])]);
    assert.ok(linkCodes(d).includes('E_MAP_SELF_LINK'));
  });

  test('E_MAP_UNREACHABLE: maps not reachable from the start map', () => {
    const d = data([
      room('a'),
      room('b', [D('d1', 'c', 'd1')]),
      room('c', [D('d1', 'b', 'd1')])
    ]);
    const errs = World.validateAll(d).errors.filter((e) => e.code === 'E_MAP_UNREACHABLE');
    assert.deepStrictEqual(errs.map((e) => e.map).sort(), ['b', 'c']);
  });

  test('test map is exempt from the reachability rule', () => {
    const d = data([room('a'), room('test')]);
    assert.deepStrictEqual(World.validateAll(d).errors, []);
  });

  test('E_MAP_NO_STARTMAP when startMap is not a defined map', () => {
    assert.ok(linkCodes(data([room('a')], 'nope')).includes('E_MAP_NO_STARTMAP'));
  });

  test('loadAll throws E_MAP_INVALID with details for a one-way link', () => {
    const bad = data([
      room('a', [D('d1', 'b', 'd1')]),
      room('b', [D('d1', 'c', 'd1')]),
      room('c', [D('d1', 'b', 'd1')])
    ]);
    assert.throws(() => World.loadAll(bad), (e) => e.code === 'E_MAP_INVALID' && Array.isArray(e.details) && e.details.length >= 1);
  });

  // World: materials ------------------------------------------------------------

  const MAT = [
    '###########',
    '#@.,g.BWIw#',
    '###########'
  ];

  test('materialAt: each wall char maps to its material', () => {
    const w = World.load(def(MAT));
    assert.strictEqual(w.materialAt(0.5, 1.5), 'stone');  // #
    assert.strictEqual(w.materialAt(6.5, 1.5), 'brick');  // B
    assert.strictEqual(w.materialAt(7.5, 1.5), 'wood');   // W
    assert.strictEqual(w.materialAt(8.5, 1.5), 'iron');   // I
    assert.strictEqual(w.materialAt(9.5, 1.5), 'glass');  // w
  });

  test('materialAt: floor chars and markers', () => {
    const w = World.load(def(MAT));
    assert.strictEqual(w.materialAt(2.5, 1.5), 'stone');  // .
    assert.strictEqual(w.materialAt(3.5, 1.5), 'wood');   // ,
    assert.strictEqual(w.materialAt(4.5, 1.5), 'grass');  // g
    assert.strictEqual(w.materialAt(1.5, 1.5), 'stone');  // @ with default floor
    assert.strictEqual(World.load(def(MAT, { floor: 'grass' })).materialAt(1.5, 1.5), 'grass');
  });

  test('materialAt: door cells are wood (D) or iron (G)', () => {
    assert.strictEqual(World.load(def(BASE)).materialAt(3.5, 3.5), 'wood');
    assert.strictEqual(World.load(def(put(BASE, 3, 3, 'G'))).materialAt(3.5, 3.5), 'iron');
  });

  // World: blocks ---------------------------------------------------------------

  const PROP_PLACES = [
    { type: 'table', col: 4, row: 2 },
    { type: 'cross', col: 6, row: 2 },
    { type: 'torch', col: 2, row: 4 }
  ];

  test('blocks: solid prop blocks; cross and torch do not', () => {
    const w = World.load(def(box(10, 6), { props: PROP_PLACES }));
    assert.strictEqual(w.blocks(4.5, 2.5, 0.2), true);
    assert.strictEqual(w.blocks(6.5, 2.5, 0.2), false);
    assert.strictEqual(w.blocks(2.5, 4.5, 0.2), false);
  });

  test('blocks: radius counts (prop 0.3 plus body radius)', () => {
    const w = World.load(def(box(10, 6), { props: PROP_PLACES }));
    assert.strictEqual(w.blocks(4.95, 2.5, 0.2), true);
    assert.strictEqual(w.blocks(5.05, 2.5, 0.2), false);
  });

  test('blocks: walls block', () => {
    const w = World.load(def(box(10, 6), { props: PROP_PLACES }));
    assert.strictEqual(w.blocks(0.7, 2.5, 0.2), true);
    assert.strictEqual(w.blocks(1.5, 2.5, 0.2), false);
  });

  // World: lights ---------------------------------------------------------------

  test('lightAt: full inside half the radius, linear falloff, zero at the radius', () => {
    // torch light 20 -> core radius 20 * LIGHT_SCALE 0.39 = 7.8; light at cell (3,3), centre (3.5,3.5)
    const w = World.load(def(box(40, 9), { props: [{ type: 'torch', col: 3, row: 3, light: 20 }] }));
    const R = 7.8;
    assert.strictEqual(w.lights.length, 1);
    assert.strictEqual(w.lightAt(3.5, 3.5), 1);
    assert.strictEqual(w.lightAt(6.5, 3.5), 1);                       // 3 cells <= half radius 3.9
    assert.ok(Math.abs(w.lightAt(8.5, 3.5) - (2 - 2 * 5 / R)) < 1e-6); // 5 cells
    assert.ok(Math.abs(w.lightAt(10.5, 3.5) - (2 - 2 * 7 / R)) < 1e-6); // 7 cells: just inside the radius
    assert.strictEqual(w.lightAt(11.5, 3.5), 0);                      // 8 cells > radius 7.8
    assert.strictEqual(w.lightAt(12.5, 3.5), 0);
    assert.strictEqual(w.lightAt(30.5, 3.5), 0);
  });

  test('outerAt is faint-positive just outside the core radius', () => {
    const w = World.load(def(box(40, 9), { props: [{ type: 'torch', col: 3, row: 3, light: 20 }] })); // core 7.8, outer 14.04
    assert.strictEqual(w.lightAt(12.5, 3.5), 0);                      // 9 cells: outside core
    assert.ok(w.outerAt(12.5, 3.5) > 0 && w.outerAt(12.5, 3.5) < 1);  // inside outer 14.04
    assert.strictEqual(w.lightSources().length, 1);
  });

  test('outerAt is 0 beyond 1.8x the core radius', () => {
    const w = World.load(def(box(40, 9), { props: [{ type: 'torch', col: 3, row: 3, light: 20 }] })); // outer 7.8 * 1.8 = 14.04
    assert.strictEqual(w.outerAt(18.5, 3.5), 0);                      // 15 cells > 14.04
    assert.strictEqual(w.outerAt(-1, -1), 0);
  });

  test('lightAt is 0 out of bounds', () => {
    const w = World.load(def(box(15, 7), { props: [{ type: 'torch', col: 3, row: 3 }] }));
    assert.strictEqual(w.lightAt(-1, -1), 0);
    assert.strictEqual(w.lightAt(-0.5, 3.5), 0);
    assert.strictEqual(w.lightAt(99, 3.5), 0);
    assert.strictEqual(w.lightAt(3.5, 99), 0);
  });

  /** 15x7 room split by a wall column at col 6, optionally with a closed door at (6,3). */
  function splitRows(withDoor) {
    let rows = box(15, 7);
    for (let r = 1; r <= 5; r++) rows = put(rows, 6, r, '#');
    if (withDoor) rows = put(rows, 6, 3, 'D');
    return rows;
  }
  const TORCH6 = [{ type: 'torch', col: 3, row: 3, light: 40 }];

  test('lightAt is 0 behind a wall, and lit on the same side (control)', () => {
    const open = World.load(def(box(15, 7), { props: TORCH6 }));
    assert.ok(open.lightAt(7.5, 3.5) > 0, 'control: the unwalled point is lit');
    const walled = World.load(def(splitRows(false), { props: TORCH6 }));
    assert.strictEqual(walled.lightAt(7.5, 3.5), 0);
    assert.ok(walled.lightAt(5.5, 3.5) > 0);
  });

  test('lightAt recomputes when a door between light and point opens and closes', () => {
    const w = World.load(def(splitRows(true), { props: TORCH6 }));
    assert.strictEqual(w.lightAt(7.5, 3.5), 0);
    assert.strictEqual(w.setDoor(6, 3, true), true);
    assert.ok(w.lightAt(7.5, 3.5) > 0, 'open door lets light through');
    assert.strictEqual(w.setDoor(6, 3, false), true);
    assert.strictEqual(w.lightAt(7.5, 3.5), 0, 'closed again');
    assert.strictEqual(w.setDoor(3, 3, true), false, 'not a door cell');
  });

  // World: arrival --------------------------------------------------------------

  test('arrival returns the cell in front of the door with the facing angle', () => {
    let rows = box(11, 9);
    rows = put(rows, 2, 2, 'D');
    rows = put(rows, 5, 2, 'D');
    rows = put(rows, 8, 5, 'D');
    rows = put(rows, 3, 6, 'D');
    const doors = [
      { id: 'n1', col: 2, row: 2, facing: 'n', toMap: 'x', toDoor: 'y' },
      { id: 's1', col: 5, row: 2, facing: 's', toMap: 'x', toDoor: 'y' },
      { id: 'e1', col: 8, row: 5, facing: 'e', toMap: 'x', toDoor: 'y' },
      { id: 'w1', col: 3, row: 6, facing: 'w', toMap: 'x', toDoor: 'y' }
    ];
    const w = World.load(def(rows, { doors: doors }));
    assert.deepStrictEqual(w.arrival('n1'), { x: 2.5, y: 1.5, angle: -Math.PI / 2 });
    assert.deepStrictEqual(w.arrival('s1'), { x: 5.5, y: 3.5, angle: Math.PI / 2 });
    assert.deepStrictEqual(w.arrival('e1'), { x: 9.5, y: 5.5, angle: 0 });
    assert.deepStrictEqual(w.arrival('w1'), { x: 2.5, y: 6.5, angle: Math.PI });
    assert.strictEqual(w.arrival('nope'), null);
    assert.strictEqual(w.doorAt(2.5, 2.5).id, 'n1');
    assert.strictEqual(w.isLinkDoor(2.5, 2.5), true);
    assert.strictEqual(w.isLinkDoor(0.5, 0.5), false);
  });

  // Zones (v0.6.1) ------------------------------------------------------------

  const ZONE_HUT = [{ name: 'hut', kind: 'indoor', x0: 2, y0: 2, x1: 4, y1: 4 }];

  test('kindAt: a zone cell takes the zone kind, other cells take the map kind', () => {
    const w = World.load(def(box(12, 8), { kind: 'outdoor', zones: ZONE_HUT }));
    assert.strictEqual(w.kindAt(3.5, 3.5), 'indoor', 'inside the zone');
    assert.strictEqual(w.kindAt(2.5, 2.5), 'indoor', 'zone corner');
    assert.strictEqual(w.kindAt(4.9, 4.9), 'indoor', 'zone far corner');
    assert.strictEqual(w.kindAt(8.5, 6.5), 'outdoor', 'outside the zone');
    assert.strictEqual(w.kindAt(5.5, 3.5), 'outdoor', 'just past the zone edge');
  });

  test('kindAt: a zone can be outdoor inside an indoor map', () => {
    const w = World.load(def(box(12, 8), { kind: 'indoor', zones: [{ name: 'yard', kind: 'outdoor', x0: 2, y0: 2, x1: 4, y1: 4 }] }));
    assert.strictEqual(w.kindAt(3.5, 3.5), 'outdoor');
    assert.strictEqual(w.kindAt(8.5, 6.5), 'indoor');
  });

  test('kindAt: out of bounds returns the map kind', () => {
    const out = World.load(def(box(12, 8), { kind: 'outdoor', zones: ZONE_HUT }));
    assert.strictEqual(out.kindAt(-1, -1), 'outdoor');
    assert.strictEqual(out.kindAt(-0.5, 3.5), 'outdoor');
    assert.strictEqual(out.kindAt(99, 3.5), 'outdoor');
    assert.strictEqual(out.kindAt(3.5, 99), 'outdoor');
    const ind = World.load(def(box(12, 8), { zones: ZONE_HUT }));
    assert.strictEqual(ind.kindAt(-1, -1), 'indoor', 'no kind field defaults to indoor');
  });

  test('zoneAt: returns the zone name inside, null outside and out of bounds', () => {
    const w = World.load(def(box(12, 8), { kind: 'outdoor', zones: ZONE_HUT }));
    assert.strictEqual(w.zoneAt(3.5, 3.5), 'hut');
    assert.strictEqual(w.zoneAt(2.5, 2.5), 'hut');
    assert.strictEqual(w.zoneAt(8.5, 6.5), null);
    assert.strictEqual(w.zoneAt(5.5, 3.5), null);
    assert.strictEqual(w.zoneAt(-1, -1), null);
    assert.strictEqual(w.zoneAt(99, 3.5), null);
  });

  test('zoneAt: adjacent zones keep their own names', () => {
    const zones = [
      { name: 'left', kind: 'indoor', x0: 1, y0: 1, x1: 4, y1: 3 },
      { name: 'right', kind: 'indoor', x0: 5, y0: 1, x1: 8, y1: 3 }
    ];
    const w = World.load(def(box(12, 6), { zones: zones }));
    assert.strictEqual(w.zoneAt(4.5, 2.5), 'left');
    assert.strictEqual(w.zoneAt(5.5, 2.5), 'right');
  });

  test('E_MAP_BAD_ZONE: a zone rect outside the map bounds', () => {
    const d = def(BASE, { doors: DOOR_N, zones: [{ name: 'z', kind: 'indoor', x0: 1, y0: 1, x1: 9, y1: 2 }] });
    assert.ok(codes(d).includes('E_MAP_BAD_ZONE'));
    assert.ok(messages(d, 'E_MAP_BAD_ZONE')[0].includes('out of bounds'));
  });

  test('E_MAP_BAD_ZONE: a zone with x0 > x1 or y0 > y1', () => {
    const inverted = def(BASE, { doors: DOOR_N, zones: [{ name: 'z', kind: 'indoor', x0: 3, y0: 1, x1: 1, y1: 2 }] });
    assert.ok(codes(inverted).includes('E_MAP_BAD_ZONE'));
    const flipped = def(BASE, { doors: DOOR_N, zones: [{ name: 'z', kind: 'indoor', x0: 1, y0: 2, x1: 3, y1: 1 }] });
    assert.ok(codes(flipped).includes('E_MAP_BAD_ZONE'));
  });

  test('E_MAP_BAD_ZONE: a bad kind', () => {
    const d = def(BASE, { doors: DOOR_N, zones: [{ name: 'z', kind: 'cave', x0: 1, y0: 1, x1: 2, y1: 2 }] });
    assert.ok(codes(d).includes('E_MAP_BAD_ZONE'));
    assert.ok(messages(d, 'E_MAP_BAD_ZONE')[0].includes('bad kind'));
  });

  test('E_MAP_BAD_ZONE: a duplicate zone name', () => {
    const d = def(BASE, {
      doors: DOOR_N,
      zones: [
        { name: 'z', kind: 'indoor', x0: 1, y0: 1, x1: 2, y1: 2 },
        { name: 'z', kind: 'indoor', x0: 4, y0: 1, x1: 5, y1: 2 }
      ]
    });
    assert.ok(codes(d).includes('E_MAP_BAD_ZONE'));
    assert.ok(messages(d, 'E_MAP_BAD_ZONE').some((m) => m.includes('duplicates')));
  });

  test('a valid zone list is clean', () => {
    const d = def(BASE, {
      doors: DOOR_N,
      zones: [
        { name: 'a', kind: 'indoor', x0: 1, y0: 1, x1: 2, y1: 2 },
        { name: 'b', kind: 'outdoor', x0: 4, y0: 1, x1: 5, y1: 2 }
      ]
    });
    assert.deepStrictEqual(codes(d), []);
  });

  test('E_MAP_BAD_HIDE: hides must be floor cells in bounds', () => {
    assert.deepStrictEqual(codes(def(BASE, { hides: [[1, 1], [2, 2]] })), []);
    assert.deepStrictEqual(codes(def(BASE, { hides: [[0, 0]] })), ['E_MAP_BAD_HIDE']);
    assert.deepStrictEqual(codes(def(BASE, { hides: [[99, 1]] })), ['E_MAP_BAD_HIDE']);
    assert.deepStrictEqual(codes(def(BASE, { hides: [[1.5, 1]] })), ['E_MAP_BAD_HIDE']);
    assert.deepStrictEqual(codes(def(BASE, { hides: 'x' })), ['E_MAP_BAD_HIDE']);
  });

  test('glass (w) lets light through; a stone wall does not', () => {
    const mk = (ch) => World.load(def(put(splitRows(false), 6, 3, ch), { props: TORCH6 }));
    const glass = mk('w');
    assert.ok(glass.lightAt(7.5, 3.5) > 0, 'lit outside the window');
    assert.ok(glass.isSolid(6.5, 3.5), 'window still blocks movement');
    assert.strictEqual(mk('#').lightAt(7.5, 3.5), 0);
  });

});

