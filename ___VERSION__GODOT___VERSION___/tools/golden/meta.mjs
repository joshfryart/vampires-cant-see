#!/usr/bin/env node
// Golden fixture: js/meta.js (sanitize, migrate, buy, run recording, effects, boon rolls) on real and corrupt inputs.
// Usage: node tools/golden/meta.mjs [outPath]   (default project/tests/fixtures/meta.json)

import { createRequire } from 'node:module';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { mkdirSync, writeFileSync } from 'node:fs';

const require = createRequire(import.meta.url);
const HERE = dirname(fileURLToPath(import.meta.url));
const PORT = resolve(HERE, '..', '..');
const JS = join(resolve(PORT, '..'), 'js');
const OUT = process.argv[2] ? resolve(process.argv[2]) : join(PORT, 'project', 'tests', 'fixtures', 'meta.json');

for (const m of ['log', 'data/upgrades', 'meta']) require(join(JS, m + '.js'));
const VCS = globalThis.VCS;
VCS.Log.setConsole(false);
const { Meta } = VCS;
const clean = (v) => (v === undefined ? null : JSON.parse(JSON.stringify(v)));

const ups = Object.keys(Meta.create().upgrades);
const sanitize = [];
const san = (key, obj) => sanitize.push({ key, obj: clean(obj), res: clean(Meta.sanitize(obj)) });
const base = Meta.create();
san('fresh', base);
san('with tiers', Object.assign(Meta.create(), { essence: 40, upgrades: Object.assign(Meta.create().upgrades, { far_echo: 3, soft_step: 1 }) }));
san('floats floor', { v: 1, essence: 12.9, upgrades: { far_echo: 1.7 }, stats: { runs: 3.5 } });
san('clamps', { v: 1, essence: 99999999, upgrades: { far_echo: 9 }, stats: { runs: 5e9 } });
san('unknown dropped', { v: 1, essence: 1, upgrades: { nope: 2, far_echo: 1 }, stats: { zed: 3, runs: 2 }, extra: 1 });
san('bad version', { v: 2, essence: 1 });
san('no version', { essence: 1 });
san('no essence', { v: 1 });
san('negative essence', { v: 1, essence: -1 });
san('bad upgrades', { v: 1, essence: 1, upgrades: [] });
san('bad tier', { v: 1, essence: 1, upgrades: { far_echo: -2 } });
san('bad stats', { v: 1, essence: 1, stats: 5 });
san('bad stat value', { v: 1, essence: 1, stats: { runs: 'x' } });
san('not object', 'x');
san('array', []);

const migrate = [];
const mig = (key, v, data) => migrate.push({ key, v, data: clean(data), res: clean(Meta.migrate(v, data)) });
mig('v1 passthrough', 1, base);
mig('v0 good', 0, { essence: 30, bought: ['far_echo', 'nope', 'soft_step', 5] });
mig('v0 bad', 0, { essence: 'x', bought: [] });
mig('v0 no bought', 0, { essence: 3 });
mig('future', 2, {});
mig('negative', -1, {});
mig('fraction', 0.5, {});
mig('string', '1', {});

const buy = [];
{
  const m = Meta.create(); m.essence = 100;
  const steps = [];
  for (const id of [ups[0], ups[0], ups[0], ups[0], ups[1], 'nope', ups[2], ups[3], ups[3], ups[3]]) {
    const r = Meta.buy(m, id);
    steps.push({ id, res: clean(r), essence: m.essence, tier: Meta.tierOf(m, id), cost: Meta.costOf(m, id), snapshot: clean(m.upgrades) });
  }
  const poor = Meta.create(); poor.essence = 4;
  buy.push({ key: 'rich', start: 100, steps });
  buy.push({ key: 'poor', steps: [{ id: ups[0], res: clean(Meta.buy(poor, ups[0])), essence: poor.essence }] });
}

const runs = [];
{
  const m = Meta.create();
  const seq = [{ nights: 3, fed: 4, won: false }, { nights: 5, fed: 9, won: true, bonus: 6 }, { nights: 1, fed: 0 }, { nights: -3, fed: 'x', won: 1, bonus: 99999 }, { nights: 2.7, fed: 1.2, bonus: 4.9 }, null, { nights: 5e9, fed: 5e9, won: true }];
  for (const r of seq) { const earned = Meta.recordRun(m, r); runs.push({ run: clean(r), earned, essenceFor: Meta.essenceFor(r), meta: clean(m) }); }
}

const effects = [];
{
  const m = Meta.create(); m.upgrades.far_echo = 3; m.upgrades.quick_call = 2; m.upgrades.full_veins = 1; m.upgrades.long_night = 3; m.upgrades.deep_draw = 3; m.upgrades.soft_step = 3;
  const combos = [
    { meta: Meta.create(), boons: [], extra: [] },
    { meta: m, boons: ['bats_ear', 'hush', 'moonlit', 'full_belly', 'nope', 5], extra: [{ effect: 'sonarRange', op: 'mul', value: 1.05 }, { effect: 'bloodNow', op: 'add', value: 10 }, { effect: 'drain', op: 'mul', value: 0.95 }, null, { effect: 'zzz', op: 'mul', value: 2 }] },
    { meta: m, boons: ['cold_blood', 'cold_blood', 'cold_blood', 'cold_blood', 'cold_blood', 'cold_blood', 'cold_blood', 'cold_blood', 'cold_blood'], extra: null },
    { meta: null, boons: null, extra: null },
    { meta: m, boons: Array(40).fill('bats_ear'), extra: [] }
  ];
  for (const c of combos) effects.push({ meta: clean(c.meta), boons: clean(c.boons), extra: clean(c.extra), fx: clean(Meta.effects(c.meta, c.boons, c.extra)) });
}

const rolls = [];
for (const seed of [0, 1, 42, 99999, 4294967295, -3, 1.5, 123456789]) for (const taken of [[], ['bats_ear', 'hush'], ['bats_ear', 'echo_memory', 'quick_ping', 'cold_blood', 'fast_fangs', 'hush', 'moonlit', 'warm_hint'], null]) rolls.push({ seed, taken, res: Meta.rollBoons(seed, taken) });

mkdirSync(dirname(OUT), { recursive: true });
writeFileSync(OUT, JSON.stringify({ sanitize, migrate, buy, runs, effects, rolls }) + '\n');
console.log('wrote ' + OUT);
