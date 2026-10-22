#!/usr/bin/env node
// Golden fixture: World.validate / validateAll / reachable from the real js/world.js on the real maps and on
// deliberately broken variants of them. The fixture stores each input definition and the JS result (error codes with
// map, row/col/door/path/segment/hide fields), so the GDScript port is run on identical input.
// Usage: node tools/golden/world_validate.mjs [outPath]   (default project/tests/fixtures/world_validate.json)

import { createRequire } from 'node:module';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { mkdirSync, writeFileSync } from 'node:fs';

const require = createRequire(import.meta.url);
const HERE = dirname(fileURLToPath(import.meta.url));
const PORT = resolve(HERE, '..', '..');
const JS = join(PORT, 'html-version', 'js');
const OUT = process.argv[2] ? resolve(process.argv[2]) : join(PORT, 'project', 'tests', 'fixtures', 'world_validate.json');

for (const m of ['log', 'world', 'data/maps']) require(join(JS, m + '.js'));
const VCS = globalThis.VCS;
VCS.Log.setConsole(false);
const { World, MapData } = VCS;

const clone = (o) => JSON.parse(JSON.stringify(o));
const slim = (res) => ({ ok: res.ok, errors: res.errors.map((e) => ({ code: e.code, map: e.map, row: e.row, col: e.col, door: e.door, path: e.path, segment: e.segment, hide: e.hide, char: e.char })) });
const setCh = (def, c, r, ch) => { const row = def.rows[r]; def.rows[r] = row.slice(0, c) + ch + row.slice(c + 1); };

const cases = [];
function single(key, def, opts, names, links) {
  cases.push({ key, def, opts: opts || null, names: names || null, links: links || null, res: slim(World.validate(def, names, links, opts)) });
}

const maps = MapData.maps;
for (const n of Object.keys(maps)) single('real/' + n, clone(maps[n]), { requireStart: n === MapData.startMap || n === 'test' });

const base = () => clone(maps.test);
let d;
single('empty rows', { name: 'e', rows: [] });
single('not rect', Object.assign(base(), { rows: base().rows.map((r, i) => (i === 3 ? r + '#' : r)) }));
d = base(); d.rows = d.rows.map(() => ''); single('empty strings', d);
d = base(); setCh(d, 4, 4, 'X'); single('bad tile', d);
d = base(); setCh(d, 0, 3, '.'); single('open edge', d);
d = base(); setCh(d, 2, 1, '.'); single('no start', d, { requireStart: true });
d = base(); setCh(d, 3, 1, '@'); single('two starts', d);
d = base(); setCh(d, 2, 1, '.'); single('no start optional', d, { requireStart: false });
d = base(); d.zones = [{ name: 'a', kind: 'indoor', x0: 0, y0: 0, x1: 5, y1: 5 }, { name: 'a', kind: 'cave', x0: 0, y0: 0, x1: 99, y1: 5 }, { name: 'b', kind: 'indoor', x0: 5, y0: 5, x1: 1, y1: 1 }, { kind: 'indoor' }, 7]; single('bad zones', d);
d = base(); d.zones = 'nope'; single('zones not array', d);
d = base(); d.props = [{ type: 'barrel', col: 3, row: 3 }, { type: 'barrel', col: 3, row: 3 }, { type: 'spaceship', col: 1, row: 1 }, { type: 'table', col: 0, row: 0 }, { type: 'torch', col: 99, row: 1 }, { type: 'torch', col: 2, row: 2, light: -3 }, null]; single('bad props', d);
d = base(); d.props = 4; single('props not array', d);
d = clone(maps.crypt); d.doors = [{ id: 'x', col: 1, row: 1, facing: 'n' }, { id: 'x', col: 2, row: 2, facing: 'q' }, { col: 3, row: 3 }, { id: 'z', col: 99, row: 1, facing: 'n' }, 5]; single('bad doors', d, { requireStart: true });
d = clone(maps.town); if (d.doors && d.doors.length) { d.doors[0].facing = 'zz'; } single('door bad facing', d, { requireStart: false });
d = clone(maps.town); if (d.doors && d.doors.length > 1) { d.doors[1].col = d.doors[0].col; d.doors[1].row = d.doors[0].row; } single('door shares cell', d, { requireStart: false });
d = base(); d.hides = [[1, 1], [0, 0], 'x', [99, 1], [2.5, 1]]; single('bad hides', d);
d = base(); d.hides = 'x'; single('hides not array', d);
d = base(); d.paths = [{ points: [[1, 1], [20, 1]] }, { points: [[1, 1], 'x'] }, { points: [] }, { points: [[16, 1], [16, 12]] }]; single('bad paths', d);
d = base(); d.paths = [{ points: [[2, 3], [3, 3]] }]; d.props = [{ type: 'barrel', col: 2, row: 3 }]; single('path through prop', d);
single('link missing map', base(), null, ['test'], [{ from: 'test', to: 'nowhere' }, { from: 'test', to: 'test' }]);

// validateAll on the real data and on broken link graphs.
const all = [];
function whole(key, data) { all.push({ key, data, res: slim(World.validateAll(data)), reach: data.startMap && data.maps[data.startMap] ? World.reachable(data, data.startMap) : [] }); }
whole('real', clone(MapData));
let md = clone(MapData); md.startMap = 'nope'; whole('bad startMap', md);
md = clone(MapData); const dn = Object.keys(md.maps).find((n) => (md.maps[n].doors || []).length && md.maps[n].doors.some((x) => x.toMap)); if (dn) { const dd = md.maps[dn].doors.find((x) => x.toMap); dd.toDoor = 'ghost'; } whole('door to ghost', md);
md = clone(MapData); const dn2 = Object.keys(md.maps).find((n) => (md.maps[n].doors || []).some((x) => x.toMap)); if (dn2) { md.maps[dn2].doors.find((x) => x.toMap).toMap = dn2; } whole('self link', md);
md = clone(MapData); const dn3 = Object.keys(md.maps).find((n) => (md.maps[n].doors || []).some((x) => x.toMap)); if (dn3) { const x = md.maps[dn3].doors.find((q) => q.toMap); const tgt = md.maps[x.toMap].doors.find((q) => q.id === x.toDoor); if (tgt) tgt.toDoor = 'other'; } whole('one way', md);
md = clone(MapData); md.maps.island = clone(maps.test); md.maps.island.name = 'island'; whole('unreachable', md);
md = clone(MapData); md.maps = {}; whole('no maps', md);

mkdirSync(dirname(OUT), { recursive: true });
writeFileSync(OUT, JSON.stringify({ cases, all }) + '\n');
console.log('wrote ' + OUT + ' (' + cases.length + ' map cases, ' + all.length + ' graph cases)');
