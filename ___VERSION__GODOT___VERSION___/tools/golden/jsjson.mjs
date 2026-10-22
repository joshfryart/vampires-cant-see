#!/usr/bin/env node
// Golden fixture: JS Number -> string and JSON.stringify results for the Godot JsJson port.
// Doubles are stored as 16-hex-digit IEEE bits (Godot's JSON parser is not correctly rounded for decimal text).
// Usage: node tools/golden/jsjson.mjs [outPath]   (default project/tests/fixtures/jsjson.json)

import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { mkdirSync, writeFileSync } from 'node:fs';

const HERE = dirname(fileURLToPath(import.meta.url));
const PORT = resolve(HERE, '..', '..');
const OUT = process.argv[2] ? resolve(process.argv[2]) : join(PORT, 'project', 'tests', 'fixtures', 'jsjson.json');

const buf = new DataView(new ArrayBuffer(8));
const hex = (v) => { buf.setFloat64(0, v); return buf.getBigUint64(0).toString(16).padStart(16, '0'); };
let s = 987654321;
const rnd = () => { s = (s * 1664525 + 1013904223) >>> 0; return s / 4294967296; };
const nums = [];
for (let i = 0; i < 6000; i++) {
  const k = i % 12;
  let v;
  if (k === 0) v = rnd();
  else if (k === 1) v = rnd() * 1000;
  else if (k === 2) v = (rnd() - 0.5) * 1e-5;
  else if (k === 3) v = rnd() * 1e15;
  else if (k === 4) v = Math.round(rnd() * 1e6) / 1000;
  else if (k === 5) v = Math.floor(rnd() * 1e9);
  else if (k === 6) v = (rnd() - 0.5) * 64;
  else if (k === 7) v = rnd() * Math.PI;
  else if (k === 8) v = Math.pow(10, Math.floor(rnd() * 60 - 30)) * (1 + Math.floor(rnd() * 9));
  else if (k === 9) v = rnd() * 1e22;
  else if (k === 10) v = Math.pow(2, Math.floor(rnd() * 200 - 100));
  else v = rnd() * 1e-300;
  nums.push([hex(v), String(v)]);
}
for (const v of [0.1 + 0.2, 1e21, 1e-7, 1e-6, 123456789012345680000, 5e-324, 1.7976931348623157e308, 0.000001, 1e300, 4.35, 0.1, 100, 1e20, 123456789.123456789, 2 ** 53, 2 ** 53 + 2, -1.5, -0.0001, 3.141592653589793, 2.2250738585072014e-308]) nums.push([hex(v), String(v)]);

const values = [
  { a: 1, b: [1, 2.5, 'x', null, true], c: { z: 1, y: 'é"\\\n\t', 10: 'ten', 2: 'two', k: [] } },
  [], {}, 'plain', 12, -0.5, null, true, { nested: { deep: [[1, [2, [3]]]], e: {} } },
  { text: 'tab\there \u0001 control \u001f   emoji 😀' },
  { n: 1e21, m: 1e-7, o: 0.1 + 0.2, p: 123456789012345680000, big: 2 ** 60 }
];
const json = values.map((v) => ({ value: v === undefined ? null : v, compact: JSON.stringify(v), pretty: JSON.stringify(v, null, 2) }));
// the lone surrogate and float cases cannot round-trip through a JSON fixture exactly: store them as escaped text
mkdirSync(dirname(OUT), { recursive: true });
writeFileSync(OUT, JSON.stringify({ nums, json }) + '\n');
console.log('wrote ' + OUT + ' (' + nums.length + ' numbers, ' + json.length + ' values)');
