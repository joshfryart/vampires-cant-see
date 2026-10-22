#!/usr/bin/env node
// Golden fixture: mulberry32 streams from the real js/people.js source.
// Usage: node tools/golden/rng.mjs [outPath]   (default project/tests/fixtures/rng.json)
// Outputs are stored as the integer numerator (draw * 2^32): Godot JSON parsing is not correctly rounded for doubles, integers are exact.
// mulberry32 is not exported, so the function text is cut out of js/people.js and evaluated.

import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';

const HERE = dirname(fileURLToPath(import.meta.url));
const PORT = resolve(HERE, '..', '..');
const REPO = resolve(PORT, '..');
const OUT = process.argv[2] ? resolve(process.argv[2]) : join(PORT, 'project', 'tests', 'fixtures', 'rng.json');

const src = readFileSync(join(REPO, 'js', 'people.js'), 'utf8');
const m = src.match(/function mulberry32\(seed\) \{[\s\S]*?\n  \}\n/);
if (!m) throw new Error('mulberry32 not found in js/people.js');
const mulberry32 = new Function(m[0] + '; return mulberry32;')();

// Seeds: edge values plus the per-villager mix used in people.js:79.
const seeds = [0, 1, 2, 42, 977, 12345, 65535, 2147483647, 2147483648, 3735928559, 4294967295];
const sd = 20260101, pid = 3;
seeds.push(((sd >>> 0) * 2654435761 + (pid + 1) * 40503 + 977) >>> 0);

const streams = seeds.map((seed) => {
  const r = mulberry32(seed);
  const out = [];
  for (let i = 0; i < 64; i++) out.push(r() * 4294967296);
  return { seed, out };
});

// Seeds that are not already uint32 reduce like `>>> 0` (negative, fractional, > 2^32).
const odd = [-1, 3.7, 4294967296 + 5, -4294967297].map((seed) => {
  const r = mulberry32(seed);
  const out = [];
  for (let i = 0; i < 8; i++) out.push(r() * 4294967296);
  return { seed, out };
});

mkdirSync(dirname(OUT), { recursive: true });
writeFileSync(OUT, JSON.stringify({ streams, odd }, null, 1) + '\n');
console.log('wrote ' + OUT + ' (' + streams.length + ' streams, ' + odd.length + ' odd seeds)');
