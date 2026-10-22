#!/usr/bin/env node
// Converts js/data/*.js to JSON in project/data (do not hand-edit the output).
// Usage: node tools/export-data.mjs
// Functions inside the data (acoustics.beam, visFactor, ...) are dropped and listed on stdout;
// they get ported into GDScript by hand. Date and non-finite values are reported, not guessed.

import { createRequire } from 'node:module';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { mkdirSync, writeFileSync } from 'node:fs';

const require = createRequire(import.meta.url);
const HERE = dirname(fileURLToPath(import.meta.url));
const PORT = resolve(HERE, '..');
const JS = join(resolve(PORT, '..'), 'js');
const OUT = join(PORT, 'project', 'data');

// [file, global name on VCS]
const SOURCES = [
  ['maps', 'MapData'], ['sounds', 'SoundData'], ['hunger', 'HungerData'], ['archetypes', 'Archetypes'],
  ['upgrades', 'Upgrades'], ['vessels', 'Vessels'], ['voices', 'Voices']
];

for (const m of ['log']) require(join(JS, m + '.js'));
globalThis.VCS.Log.setConsole(false);

const dropped = [];
function clean(v, path) {
  if (typeof v === 'function') { dropped.push(path); return undefined; }
  if (typeof v === 'number' && !Number.isFinite(v)) { dropped.push(path + ' (non-finite)'); return null; }
  if (Array.isArray(v)) return v.map((x, i) => clean(x, path + '[' + i + ']'));
  if (v && typeof v === 'object') {
    const o = {};
    for (const k of Object.keys(v)) { const c = clean(v[k], path + '.' + k); if (c !== undefined) o[k] = c; }
    return o;
  }
  return v;
}

mkdirSync(OUT, { recursive: true });
for (const [file, hint] of SOURCES) {
  const before = new Set(Object.keys(globalThis.VCS));
  try { require(join(JS, 'data', file + '.js')); } catch (e) { console.log('skip ' + file + ': ' + e.message); continue; }
  const added = Object.keys(globalThis.VCS).filter((k) => !before.has(k));
  const key = globalThis.VCS[hint] ? hint : added[0];
  if (!key) { console.log('skip ' + file + ': no VCS export found'); continue; }
  const data = clean(globalThis.VCS[key], key);
  writeFileSync(join(OUT, file + '.json'), JSON.stringify(data, null, 1) + '\n');
  console.log('wrote data/' + file + '.json from VCS.' + key);
}
if (dropped.length) console.log('not exported (port by hand):\n  ' + dropped.join('\n  '));
