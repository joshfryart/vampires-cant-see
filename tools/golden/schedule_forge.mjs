#!/usr/bin/env node
// Golden fixture: js/schedule.js and js/forge.js (+ archetype data) on real archetypes, seeds and broken inputs.
// Usage: node tools/golden/schedule_forge.mjs [outPath]   (default project/tests/fixtures/schedule_forge.json)
// VoiceData is loaded so validateArchetype can check voice presets. Deterministic.

import { createRequire } from 'node:module';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { mkdirSync, writeFileSync } from 'node:fs';

const require = createRequire(import.meta.url);
const HERE = dirname(fileURLToPath(import.meta.url));
const PORT = resolve(HERE, '..', '..');
const JS = join(PORT, 'html-version', 'js');
const OUT = process.argv[2] ? resolve(process.argv[2]) : join(PORT, 'project', 'tests', 'fixtures', 'schedule_forge.json');

for (const m of ['log', 'data/maps', 'data/voices', 'data/archetypes', 'schedule', 'forge']) require(join(JS, m + '.js'));
const VCS = globalThis.VCS;
VCS.Log.setConsole(false);
const { Schedule, Forge, MapData } = VCS;
const clean = (v) => (v === undefined ? null : JSON.parse(JSON.stringify(v)));

function mulberry32(seed) {
  let a = seed >>> 0;
  return function () {
    a = (a + 0x6D2B79F5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

// ---------------- schedule ----------------
const town = MapData.maps.town;
const places = {};
Object.keys(town.places || {}).forEach((k) => { const c = town.places[k]; places[k] = { x: c[0] + 0.5, y: c[1] + 0.5 }; });
const roles = Object.keys(Schedule.ROLES);
const builds = [];
for (const role of roles) {
  for (const home of [null, 'house1', 'house2', 'tavern', 'barn', 'church', 'nowhere']) {
    for (const slot of [0, 1, 2, 3, 7, -1]) {
      for (const seed of [1, 99]) {
        const spawn = { x: 16.5, y: 3.5 };
        const stops = Schedule.build(role, places, spawn, mulberry32(seed), { home, slot });
        builds.push({ role, home, slot, seed, spawn, stops: clean(stops) });
      }
    }
  }
}
const make = [];
for (const role of roles.slice(0, 4)) { const m = Schedule.make(role, places, null, mulberry32(5), { home: 'house1', slot: 2 }); make.push({ role, res: clean(m) }); }
make.push({ role: 'bogus', res: clean(Schedule.make('bogus', places, null, mulberry32(5), {})) });
const stopAt = [];
{
  const stops = Schedule.build(roles[0], places, { x: 16.5, y: 3.5 }, mulberry32(3), { home: 'house1', slot: 0 });
  for (const f of [-1, 0, 0.1, 0.25, 0.5, 0.75, 0.99, 1, 1.5, NaN]) stopAt.push({ f: Number.isNaN(f) ? null : f, res: Schedule.stopAt(stops, f), eta: Schedule.eta(stops, Math.max(0, Schedule.stopAt(stops, Number.isNaN(f) ? 0 : f)), Number.isNaN(f) ? 0 : f, 480) });
  stopAt.push({ stops: clean(stops) });
}
const simplify = [
  { route: [{ x: 0, y: 0 }, { x: 1, y: 0 }, { x: 2, y: 0 }, { x: 2, y: 1 }, { x: 2, y: 2 }, { x: 3, y: 2 }], res: Schedule.simplify([{ x: 0, y: 0 }, { x: 1, y: 0 }, { x: 2, y: 0 }, { x: 2, y: 1 }, { x: 2, y: 2 }, { x: 3, y: 2 }]) },
  { route: [{ x: 0, y: 0 }], res: Schedule.simplify([{ x: 0, y: 0 }]) },
  { route: [{ x: 0, y: 0 }, { x: 1, y: 1 }], res: Schedule.simplify([{ x: 0, y: 0 }, { x: 1, y: 1 }]) }
];
const seated = ['sleep', 'eat', 'watch', 'wait', 'pray', 'bogus'].map((a) => ({ a, res: Schedule.isSeated(a) }));
const chats = [];
const rolePairs = [['drunk', 'priest'], ['priest', 'drunk'], ['guard', 'guard'], ['elder', 'priest'], ['regular', 'innkeeper'], ['x', 'y'], ['insomniac', 'insomniac']];
for (const [a, b] of rolePairs) for (const same of [false, true]) for (const r1 of [0, 0.1, 0.3, 0.6, 0.9, 0.999]) chats.push({ a, b, same, r1, r2: 0.5, res: Schedule.chatRoll(a, b, same, r1, 0.5) });

// ---------------- forge ----------------
const archIds = Forge.list();
const generates = [];
for (const id of archIds.concat(['bogus'])) {
  for (const stateSeed of [0, 1, 7, 123456, 4294967295]) {
    for (const index of [0, 1, 5]) {
      for (const seed of [undefined, 3, 65535, 70000]) {
        const r = Forge.generate({ archetype: id, seed, home: index === 1 ? 'h2' : undefined }, { stateSeed, index, accOffset: index + 2 });
        generates.push({ id, stateSeed, index, seed: seed === undefined ? null : seed, res: clean(r) });
      }
    }
  }
}
const legacy = [];
for (const seed of [0, 1, 9, 12345, 4294967295]) for (const id of [0, 1, 2, 7, 25]) for (const off of [0, 3]) legacy.push({ seed, id, off, look: clean(Forge.legacyLook(seed, id, off)) });
const overrides = [
  { archetype: 'patron', seed: 4, overrides: { acc: 'tophat', hair: 'bun', height: 5, beard: true } },
  { archetype: 'guard', overrides: { acc: 'lantern', outfit: 'robe', coat: 'x' } },
  { archetype: 'guard', overrides: { zzz: 1 } },
  { archetype: 'elder', overrides: { acc: 'cane', stoop: 0.3 } }
].map((spec) => ({ spec, res: clean(Forge.generate(spec, { stateSeed: 5, index: 2, accOffset: 1 })) }));

const looks = Forge.generate({ archetype: 'patron' }, { stateSeed: 1, index: 0, accOffset: 0 }).person.look;
const validateLook = [];
const vl = (key, obj, partial) => validateLook.push({ key, obj: clean(obj), partial: !!partial, res: clean(Forge.validate('look', obj, { partial: !!partial })) });
vl('good', looks);
vl('good partial', { acc: 'cane', height: 0.8 }, true);
vl('clamped', Object.assign({}, looks, { height: 99, build: -3 }));
vl('bad enum', Object.assign({}, looks, { acc: 'zzz', body: 5 }));
vl('bad key', Object.assign({}, looks, { evil: 1 }));
vl('proto key', JSON.parse('{"__proto__": 1}'));
vl('not object', 5);
vl('partial bad', { height: 'x', acc: 'tophat' }, true);
vl('empty', {});
vl('hat rules', { acc: 'hood' }, false);
const validateOther = [];
const vo = (kind, obj) => validateOther.push({ kind, obj: clean(obj), res: clean(Forge.validate(kind, obj)) });
const archGood = { id: 'ratcatcher', role: 'ratcatcher', label: 'Rat Catcher', voice: 'man', talk: 'villager', schedule: [[['well'], 0.5, 'wait'], [['@bed'], 1, 'sleep']], watch: false, feedable: true, gait: 'walk', speed: 1.1, recipe: { height: [0.9, 0.1], acc: 'cane', bodies: ['bean'] }, extras: { outfit: 'apron', stoop: [0.1, 0.1] } };
vo('archetype', archGood);
vo('archetype', Object.assign({}, archGood, { id: 'Bad Id' }));
vo('archetype', Object.assign({}, archGood, { voice: 'no_such_voice' }));
vo('archetype', Object.assign({}, archGood, { schedule: 'later' }));
vo('archetype', Object.assign({}, archGood, { schedule: 'watch' }));
vo('archetype', Object.assign({}, archGood, { recipe: { height: [1] } }));
vo('archetype', Object.assign({}, archGood, { evil: 1 }));
vo('archetype', Object.assign({}, archGood, { gait: 'mail', speed: 9 }));
vo('archetype', 'x');
vo('spec', { archetype: 'guard', seed: 5.5, home: 'h1', overrides: { acc: 'cane' } });
vo('spec', { archetype: 'guard', seed: -5, home: 12 });
vo('spec', { archetype: 'guard', extra: 1 });
vo('spec', { archetype: 'Bad' });
vo('spec', { archetype: 'guard', home: {} });
vo('library', { v: 1, list: [archGood] });
vo('library', { v: 2, list: [] });
vo('library', { v: 1, list: new Array(17).fill(archGood) });
vo('library', { v: 1, list: [archGood], zed: 1 });
vo('bogus', {});

const alters = [];
const al = (key, look, patch) => alters.push({ key, look: clean(look), patch: clean(patch), res: clean(Forge.alter(look, patch)) });
al('hat follows acc', looks, { acc: 'hood' });
al('explicit hat', looks, { acc: 'cane', hat: 'cap' });
al('hair hidden', looks, { acc: 'tophat' });
al('clamp', looks, { height: 9 });
al('bad patch key', looks, { evil: 1 });
al('bad look', 5, { height: 1 });
al('partial look', { height: 0.7, acc: 'bonnet' }, { beard: true });
al('no change', looks, { height: looks.height });

const reinf = [];
for (const fear of [0, 5, 6, 9, 10, 15]) for (const fired of [0, 1, 2, -1]) for (const [night, runSeed] of [[1, 1], [3, 99999], [5, 4294967295]]) reinf.push({ fear, fired, night, runSeed, res: clean(Forge.reinforcement({ fear, fired, night, runSeed })) });
reinf.push({ bad: true, res: clean(Forge.reinforcement(null)) });

// custom library
const reg = [];
reg.push({ key: 'register good', res: clean(Forge.register(archGood)) });
reg.push({ key: 'register builtin', res: clean(Forge.register(Object.assign({}, archGood, { id: 'guard' }))) });
reg.push({ key: 'list after', res: Forge.list() });
reg.push({ key: 'byRole', res: clean(Forge.byRole('ratcatcher')) });
reg.push({ key: 'generate custom', res: clean(Forge.generate({ archetype: 'ratcatcher', seed: 9 }, { stateSeed: 3, index: 1, accOffset: 0 })) });
reg.push({ key: 'export', res: Forge.exportLibrary() });
reg.push({ key: 'import again', res: clean(Forge.importLibrary(Forge.exportLibrary())) });
reg.push({ key: 'import bad json', res: clean(Forge.importLibrary('{nope')) });
reg.push({ key: 'import too big', res: clean(Forge.importLibrary(' '.repeat(20000))) });

mkdirSync(dirname(OUT), { recursive: true });
writeFileSync(OUT, JSON.stringify({ places, roles, builds, make, stopAt, simplify, seated, chats, archIds, generates, legacy, overrides, validateLook, validateOther, alters, reinf, reg, archGood }) + '\n');
console.log('wrote ' + OUT + ' (' + builds.length + ' schedule builds, ' + generates.length + ' generated people)');
