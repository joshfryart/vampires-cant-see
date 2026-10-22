#!/usr/bin/env node
// Golden fixture (struggle.json): js/struggle.js pose() sampled over villager ids, blood left, time since the grab, time since a
// struggle attempt, restraint and reduced motion.
// Usage: node tools/golden/struggle.mjs [outPath]   (default project/tests/fixtures/struggle.json)

import { createRequire } from 'node:module';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { mkdirSync, writeFileSync } from 'node:fs';

const require = createRequire(import.meta.url);
const HERE = dirname(fileURLToPath(import.meta.url));
const PORT = resolve(HERE, '..', '..');
const JS = join(PORT, 'html-version', 'js');
const OUT = process.argv[2] ? resolve(process.argv[2]) : join(PORT, 'project', 'tests', 'fixtures', 'struggle.json');

require(join(JS, 'log.js'));
require(join(JS, 'struggle.js'));
const { Struggle } = globalThis.VCS;
const SC = ['lean', 'headF', 'headS', 'tilt', 'hipU', 'shU', 'headU', 'yawU', 'yawL', 'sway', 'sq', 'jolt', 'wl'];
const PR = ['hf', 'hs', 'hu', 'hb', 'ff', 'fs', 'fu', 'kb'];
const flat = (p) => SC.map((k) => p[k]).concat(PR.flatMap((k) => [p[k][0], p[k][1]]));

const out = Struggle.create();
const cases = [];
for (const pid of [0, 1, 2, 3, 5, 6, 11, 17, 100]) {
  for (const bl of [1, 0.85, 0.6, 0.4, 0.2, 0.05, 0]) {
    for (const g of [0.05, 0.3, 1.2, 3, 3.5, 6.5, 10, 25]) {
      for (const sp of [0, 0.1, 0.5, 9]) {
        for (const rs of [0, 0.8]) {
          const o = { t: g + 7.3, g, bl, sp, pid, lh: 1.05, bw: 1.1, shS: 0.17, hipS: 0.1, anim: true, rs };
          Struggle.pose(out, o);
          cases.push({ o, p: flat(out) });
        }
      }
    }
  }
  for (const bl of [1, 0.5]) {
    const o = { t: 3.3, g: 4, bl, sp: 0.2, pid, lh: 0.9, bw: 1, shS: 0.15, hipS: 0.09, anim: false, rs: 0 };
    Struggle.pose(out, o);
    cases.push({ o, p: flat(out) });
  }
}
mkdirSync(dirname(OUT), { recursive: true });
writeFileSync(OUT, JSON.stringify({ sc: SC, pr: PR, cases }) + '\n');
console.log('wrote ' + OUT + ' (' + cases.length + ' poses)');
