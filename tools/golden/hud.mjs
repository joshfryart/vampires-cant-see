#!/usr/bin/env node
// Golden fixture (hud.json): draw-call logs of js/hud.js (drawHud, drawCard, drawHint) and js/icons.js (draw, tombstone, crypt menu)
// over many states, with the same fake canvas context and canonical hash as the other render fixtures.
// Usage: node tools/golden/hud.mjs [outPath]   (default project/tests/fixtures/hud.json)

import { createRequire } from 'node:module';
import { dirname, join, resolve } from 'node:path';
import { mkdirSync, writeFileSync } from 'node:fs';
import { PORT, JS, fakeCtx, fakeCanvas, callLine, fnv1a } from './lib/render_harness.mjs';

const require = createRequire(import.meta.url);
const OUT = process.argv[2] ? resolve(process.argv[2]) : join(PORT, 'project', 'tests', 'fixtures', 'hud.json');
for (const m of ['log', 'ripple', 'icons', 'hud']) require(join(JS, m + '.js'));
const VCS = globalThis.VCS;
VCS.Log.setConsole(false);
const { Hud, Icons } = VCS;
const entries = [];

function run(key, spec, fn) {
  const ctx = fakeCanvas(640, 360).getContext('2d');
  const h = Hud.create();
  const ret = fn(ctx, h);
  const lines = ctx.calls.map(callLine);
  const e = { key, spec, ret: ret === undefined ? null : ret, hash: fnv1a(lines.join('\n')), calls: lines.length };
  if (entries.length < 2) e.log = lines;
  entries.push(e);
}

const POWERS = [
  { id: 'shriek', state: 'ready', key: 'Q' },
  { id: 'mist', state: 'cooldown', cd01: 0.4, key: 'Sh' },
  { id: 'still', state: 'poor', key: 'F' },
  { id: 'locked', state: 'locked' }
];
let n = 0;
for (const boil of [false, true]) for (const reduced of [false, true]) for (const large of [false, true]) for (const fx of [0, 1, 2]) {
  for (const [blood, weak] of [[1, 0], [0.62, 0], [0.2, 0.2], [0.04, 0.8], [0.0, 1]]) {
    const frac = [0.02, 0.35, 0.8, 0.95, 1][n % 5];
    const s = { t: 12.34 + n * 0.37, boil, reduced, largeText: large, fx, blood01: blood, weak, frac, pulse01: n % 3 === 0 ? 0 : 0.4, vialPulse: n % 2 ? 0.6 : 0, feeding: n % 4 === 0, veil: n % 3 === 1 ? n / 70 % 1 : undefined };
    if (n % 2 === 0) Object.assign(s, { hour: (20 + Math.floor(frac * 10)) % 24, minute: (n * 7) % 60 });
    if (n % 3 !== 2) Object.assign(s, { over01: [0, 0.3, 0.9][n % 3], overOpen: n % 3 === 0, powers: POWERS, rocks: n % 4, fear: [0, 1.5, 4, 9, 15][n % 5], still01: n % 4 === 1 ? 0.8 : 0, mistK: n % 5 === 2 ? 0.7 : 0, giftFlash: n % 6 === 3 ? 0.5 : 0 });
    run('hud/' + n, s, (ctx, h) => Hud.drawHud(h, ctx, s));
    n++;
  }
}
for (const age of [-1, 0, 0.1, 0.3, 1.2, 1.95, 2.2, 2.4, 2.5]) for (const boil of [false, true]) for (const [text, sub] of [['Night 1', null], ['Dawn', null], ['Night 4 — Shriek (Q)', 'Press Q to scream: people nearby will hear it and run away from the noise.'], ['A', 'short'], ['', 'x'], ['Sealed', 'Wait until the night is nearly spent, or sleep in the crypt.']]) for (const large of [false, true]) {
  const spec = { text, age, t: 5.5 + age, boil, sub, large };
  run('card/' + text + '/' + age + '/' + boil + '/' + large, spec, (ctx, h) => Hud.drawCard(h, ctx, text, age, spec.t, boil, sub === null ? undefined : sub, { largeText: large }));
}
for (const age of [-1, 0, 0.2, 2, 3.7, 3.9, 4.2]) for (const large of [false, true]) for (const text of ['Esc → Abilities for details', 'Hold E at a lit window to listen', 'x'.repeat(120)]) {
  const spec = { text, age, large };
  run('hint/' + text.length + '/' + age + '/' + large, spec, (ctx, h) => Hud.drawHint(h, ctx, text, age, 0, { largeText: large }));
}
for (const name of Icons.NAMES.concat(['nope'])) for (const size of [18, 24, 56]) for (const [t, o] of [[1.2, {}], [3.7, { alpha: 0.4, color: '#ff8a78' }], [2, { still: true, taper: true }]]) {
  const spec = { name, size, t, o };
  run('icon/' + name + '/' + size + '/' + t, spec, (ctx) => Icons.draw(ctx, name, size, t, o));
}
for (const [w, h2, t] of [[200, 260, 0], [300, 400, 1.7], [120, 140, 5]]) run('tomb/' + w + '/' + t, { w, h: h2, t }, (ctx) => Icons.drawTombstone(ctx, w, h2, t));
for (const t of [0, 0.7, 1.3, 2, 3.1, 3.9, 5.5, 9.2]) run('crypt/' + t, { t }, (ctx) => Icons.drawCryptMenu(ctx, 640, 360, t));
mkdirSync(dirname(OUT), { recursive: true });
writeFileSync(OUT, JSON.stringify({ fixture: 'hud-godot', count: entries.length, entries }) + '\n');
console.log('wrote ' + OUT + ' (' + entries.length + ' entries, ' + entries.reduce((a, e) => a + e.calls, 0) + ' calls)');
