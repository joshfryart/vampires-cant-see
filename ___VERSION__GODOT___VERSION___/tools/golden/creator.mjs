#!/usr/bin/env node
// Golden fixture (creator.json): tools/character-creator-core.js on real archetypes, seeds, broken inputs and edits:
// sanitize, setField, the field table, presets through Forge, seeded randomize (wild and archetype, with locks), poseEcho
// for every pose, sanitizeView, export / import, and the list helpers. Deterministic (fixed `saved` timestamps, seeded rng).
// Usage: node tools/golden/creator.mjs [outPath]   (default project/tests/fixtures/creator.json)

import { createRequire } from 'node:module';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { mkdirSync, writeFileSync } from 'node:fs';

const require = createRequire(import.meta.url);
const HERE = dirname(fileURLToPath(import.meta.url));
const PORT = resolve(HERE, '..', '..');
const JS = join(resolve(PORT, '..'), 'js');
const OUT = process.argv[2] ? resolve(process.argv[2]) : join(PORT, 'project', 'tests', 'fixtures', 'creator.json');

for (const m of ['log', 'data/maps', 'data/voices', 'data/archetypes', 'schedule', 'forge']) require(join(JS, m + '.js'));
const Creator = require(join(PORT, '..', 'tools', 'character-creator-core.js'));
const VCS = globalThis.VCS;
VCS.Log.setConsole(false);
const clean = (v) => (v === undefined ? null : JSON.parse(JSON.stringify(v)));
const out = { fixture: 'creator-godot', v: 1 };

// field table
out.fields = clean(Creator.fields());
out.archetypes = clean(Creator.archetypes());

// sanitize: broken, partial and stringly inputs
const bad = [
  null, 5, 'x', [], {}, { height: 99, build: -3, stride: 'abc', nose: '1.25', stoop: 0.5, shoulder: 0.1, hem: 2, skin: '0.3' },
  { acc: 'tophat', body: 'cube', head: 'egg', hat: 'tophat', hair: 'bob', beard: 'yes', coat: true, prop: 'cane', outfit: 'robe', roleHat: 'kettle', extra: 'bow' },
  { archetype: 'Bad Id', height: 1.1 }, { archetype: 'priest', v: 7, junk: 1, __proto__: { x: 1 } }
];
out.sanitize = bad.map((i) => clean({ in: i, out: Creator.sanitize(i) }));
out.sanitizeBase = [clean({ in: { height: 'oops', body: 'nope' }, base: { height: 0.9, body: 'pear', archetype: 'elder' }, out: Creator.sanitize({ height: 'oops', body: 'nope' }, { height: 0.9, body: 'pear', archetype: 'elder' }) })];

// setField sequences
const edits = [
  ['hat', 'tophat'], ['prop', 'cane'], ['scarf', true], ['hat', 'hood'], ['scarf', false], ['height', '0.6'], ['height', 5], ['body', 'round'], ['beard', true],
  ['beard', 'false'], ['coat', 'true'], ['hem', 0.77], ['outfit', 'robe'], ['roleHat', 'biretta'], ['extra', 'shovel'], ['v', 9], ['nope', 1], ['skin', 'x'], ['archetype', 'guard']
];
let look = Creator.sanitize({}).look;
out.setField = edits.map(([k, v]) => { look = Creator.setField(look, k, v); return clean({ key: k, value: v, look }); });
out.getField = clean(['scarf', 'hat', 'height', 'zzz'].map((k) => [k, Creator.getField(look, k)]));
out.hairHidden = clean([{ hat: 'tophat', roleHat: 'none' }, { hat: 'tophat', roleHat: 'kettle' }, { hat: 'cap', roleHat: 'none' }, { hat: 'hood', roleHat: 'none' }].map((l) => [l, Creator.hairHidden(l)]));

// presets
out.presets = [];
for (const a of Creator.archetypes()) for (const s of [0, 1, 7, 99, 4242, 65535, -3, 70000.7]) out.presets.push(clean({ id: a.id, seed: s, look: Creator.preset(a.id, s) }));
out.presets.push(clean({ id: 'nobody', seed: 3, look: Creator.preset('nobody', 3) }));
out.presets.push(clean({ id: 5, seed: 'x', look: Creator.preset(5, 'x') }));

// randomize with seeded rngs
out.randomize = [];
const bases = [{}, { archetype: 'priest', hat: 'nightcap', prop: 'lantern', acc: 'scarf' }, { archetype: 'guard', outfit: 'mail', height: 0.6 }];
for (const [bi, b] of bases.entries()) {
  for (const mode of ['wild', 'archetype']) {
    for (const locks of [[], ['body', 'hat'], ['scarf', 'prop', 'height']]) {
      for (const sd of [1, 2, 3, 17]) {
        const r = Creator.randomize(b, { mode, locks, rng: Creator.mulberry32(sd * 1000 + bi) });
        out.randomize.push(clean({ base: b, mode, locks, seed: sd * 1000 + bi, out: r }));
      }
    }
  }
}

// pose echoes
out.poseEcho = [];
const lk = Creator.preset('innkeeper', 5);
for (const p of Creator.POSES) {
  for (const o of [{}, { t: 1.7, yaw: 0.5, dist: 3, lat: 0.4, personId: 9 }, { t: 2.3, reduced: true, struggle: 0.1, restrain: true }, { t: 9.1, struggle: 0.9 }]) {
    out.poseEcho.push(clean({ pose: p.id, opts: o, out: Creator.poseEcho(p.id, lk, o) }));
  }
}
out.poseEcho.push(clean({ pose: 'zzz', opts: {}, out: Creator.poseEcho('zzz', lk, {}) }));

// views
const views = [null, {}, { pose: 'held', fx: 5, quality: 0, zoom: 9, dist: 0.1, yaw: 9, speed: 7, struggle: 3, gameScale: 0, spin: 1, play: false, junk: 1 }, { yaw: -7, fx: 1.4, quality: 2.6, reduced: true }];
out.views = views.map((v) => clean({ in: v, out: Creator.sanitizeView(v) }));

// characters, json, list helpers (fixed timestamps)
const A = Creator.character('Alice  the <b>Baker</b>', Creator.preset('patron', 2), { archetype: 'patron', seed: 2, saved: 1000 });
const B = Creator.character('', { height: 0.7, body: 'pear' }, { saved: 2000 });
const C = Creator.character('x'.repeat(50), {}, { seed: 99999, saved: 3000, archetype: 'BAD' });
out.characters = clean([A, B, C]);
out.exportOne = Creator.exportJSON(A);
out.exportMany = Creator.exportJSON([A, B, C, 5, null]);
out.importCases = [out.exportOne, out.exportMany, JSON.stringify([A, { height: 1.2 }]), JSON.stringify({ height: 0.9, body: 'box' }), '{bad', '[]', '5', JSON.stringify({ list: [1, 2] }), JSON.stringify(Creator.preset('elder', 3))].map((t) => clean({ text: t, out: Creator.importJSON(t) }));
let list = [];
list = Creator.upsert(list, A); list = Creator.upsert(list, B); list = Creator.upsert(list, Object.assign({}, A, { name: 'alice  the baker', seed: 5 }));
out.upsert = clean(list);
out.remove = clean(Creator.remove(list, 'UNNAMED'));
out.find = clean([Creator.find(list, 'ALICE THE BAKER'), Creator.find(list, 'zz')]);
out.freeName = clean([Creator.freeName(list, 'Unnamed'), Creator.freeName(list, 'Fresh'), Creator.freeName(list, 'alice the baker')]);
out.toSpec = clean([A, B, C, null, { height: 1 }].map((c) => [c, Creator.toSpec(c)]));
out.cleanName = clean([['  a\u0001b  c ', Creator.cleanName('  a\u0001b  c ')], [5, Creator.cleanName(5)], ['<>', Creator.cleanName('<>')]]);

mkdirSync(dirname(OUT), { recursive: true });
writeFileSync(OUT, JSON.stringify(out) + '\n');
console.log('wrote ' + OUT + ' sanitize ' + out.sanitize.length + ' presets ' + out.presets.length + ' randomize ' + out.randomize.length + ' poses ' + out.poseEcho.length);
