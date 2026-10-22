#!/usr/bin/env node
// Golden fixture: js/save.js. Real stored texts (written by the JS store), export text, tampered variants, checksums,
// run migrate/sanitize cases and tab-lock checks. js/save.js requires js/forge.js itself, so forge `altered` looks are validated; the one case that needs it is
// marked needsForge and skipped by the Godot test until core/forge.gd exists.
// Usage: node tools/golden/save.mjs [outPath]   (default project/tests/fixtures/save.json)

import { createRequire } from 'node:module';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { mkdirSync, writeFileSync } from 'node:fs';

const require = createRequire(import.meta.url);
const HERE = dirname(fileURLToPath(import.meta.url));
const PORT = resolve(HERE, '..', '..');
const JS = join(resolve(PORT, '..'), 'js');
const OUT = process.argv[2] ? resolve(process.argv[2]) : join(PORT, 'project', 'tests', 'fixtures', 'save.json');

for (const m of ['log', 'data/hunger', 'data/upgrades', 'night', 'hunger', 'meta', 'save']) require(join(JS, m + '.js'));
const VCS = globalThis.VCS;
VCS.Log.setConsole(false);
const { Save, Night, Hunger, Meta } = VCS;

class Mem { constructor() { this.m = new Map(); } getItem(k) { return this.m.has(k) ? this.m.get(k) : null; } setItem(k, v) { this.m.set(k, String(v)); } removeItem(k) { this.m.delete(k); } }

const clean = (v) => (v === undefined ? null : JSON.parse(JSON.stringify(v)));
const game = (VCS.Log && VCS.Log.VERSION) || '?';

// ---- data ----
const meta = Meta.create(); meta.essence = 37; meta.upgrades.far_echo = 2; meta.upgrades.soft_step = 1; meta.stats.runs = 4; meta.stats.bestNights = 3;
const night = Night.create({}); Night.update(night, 0.1); Night.feed(night);
const hunger = Hunger.create(); Hunger.addFear(hunger, 3); Hunger.addOverflow(hunger, 20); Hunger.takeGift(hunger, 'g_far');
const run = {
  v: 4, map: 'town', player: { x: 12.5, y: 7.25, angle: 1.5 }, doors: { town: [[3, 4], [10, 2]], crypt: [] }, people: { town: 12345, crypt: 77 },
  night: Night.serialize(night), rocks: 3,
  run: { seed: 99, boons: ['bats_ear', 'hush'], closedSafe: { town: [[5, 5]] }, pendingBoons: null, hunger: Hunger.serialize(hunger), pendingGifts: null }
};

// ---- stored texts via the real store ----
const mem = new Mem();
const store = Save.create(mem);
store.write('meta', 1, meta);
store.write('run', 4, run);
const metaText = mem.getItem('vcs.meta');
const runText = mem.getItem('vcs.run');
const pretty = Save.exportText(store);

const flip = (t) => t.replace('"essence":37', '"essence":38');
const texts = [
  { key: 'meta good', kind: 'meta', text: metaText },
  { key: 'run good', kind: 'run', text: runText },
  { key: 'meta tampered', kind: 'meta', text: flip(metaText) },
  { key: 'wrong kind', kind: 'run', text: metaText },
  { key: 'not json', kind: 'meta', text: '{nope' },
  { key: 'bad key', kind: 'meta', text: metaText.replace('"upgrades"', '"__proto__"') },
  { key: 'extra key', kind: 'meta', text: metaText.replace('{"app"', '{"zed":1,"app"') },
  { key: 'huge', kind: 'meta', text: ' '.repeat(70000) + metaText },
  { key: 'whitespace ok', kind: 'meta', text: JSON.stringify(JSON.parse(metaText), null, 2) }
].map((c) => { const p = Save.safeParse(c.text); const u = p.ok ? Save.unwrap(p.value, c.kind) : { ok: false, code: p.code }; const big = c.text.length > Save.MAX_BYTES; return Object.assign({}, c, { ok: !big && p.ok && u.ok, code: big ? 'E_SAVE_TOO_BIG' : (p.ok ? u.code : p.code) }); });

// ---- wrap text equality: our writer must produce the JS text byte for byte ----
const wraps = [
  { kind: 'meta', v: 1, data: meta, text: JSON.stringify(Save.wrap('meta', 1, meta)) },
  { kind: 'run', v: 4, data: run, text: JSON.stringify(Save.wrap('run', 4, run)) },
  { kind: 'meta', v: 1, data: { s: 'é"\\\n\t  emoji 😀', n: [0.1, 1e21, 1e-7, 123456789.5, -0.25, 5], o: { 3: 'a', 1: 'b', z: null } }, text: JSON.stringify(Save.wrap('meta', 1, { s: 'é"\\\n\t  emoji 😀', n: [0.1, 1e21, 1e-7, 123456789.5, -0.25, 5], o: { 3: 'a', 1: 'b', z: null } })) }
];

// ---- checksums ----
const sums = ['', 'a', 'hello world', '{"a":1}', 'é', '日本語', '😀', 'tab\there', metaText, runText].map((s) => ({ s, sum: Save.checksum(s) }));

// ---- import ----
const impCases = [
  { key: 'good export', text: pretty },
  { key: 'tampered meta', text: pretty.replace('"essence": 37', '"essence": 38') },
  { key: 'export without run', text: (() => { const m2 = new Mem(); const s2 = Save.create(m2); s2.write('meta', 1, meta); return Save.exportText(s2); })() },
  { key: 'bad top key', text: pretty.replace('"kind": "export"', '"kind": "exp"') },
  { key: 'not json', text: 'zzz' },
  { key: 'missing meta', text: JSON.stringify({ app: 'vcs', kind: 'export', v: 1, game, meta: null, run: null }) }
].map((c) => { const r = Save.parseImport(c.text); return Object.assign({}, c, { ok: r.ok, code: r.code, metaV: r.meta ? r.meta.v : null, runV: r.run ? r.run.v : null, metaData: r.meta ? clean(r.meta.data) : null, runData: r.run ? clean(r.run.data) : null }); });

// ---- run migrate / sanitize ----
const v3 = JSON.parse(JSON.stringify(run)); v3.v = 3; delete v3.run.hunger; delete v3.run.pendingGifts;
const v2 = { v: 2, map: 'crypt', player: { x: 1.5, y: 2.5, angle: 0 }, doors: {}, people: {}, night: Night.serialize(Night.create({})) };
const v1 = { v: 1, map: 'crypt', player: { x: 1.5, y: 2.5, angle: 0 }, doors: {}, people: {}, night: { junk: 1 } };
const mut = (f) => { const r = JSON.parse(JSON.stringify(run)); f(r); return r; };
const runCases = [
  { key: 'good v4', v: 4, data: run },
  { key: 'v3', v: 3, data: v3 },
  { key: 'v2', v: 2, data: v2 },
  { key: 'v1', v: 1, data: v1 },
  { key: 'future', v: 5, data: run },
  { key: 'v0', v: 0, data: run },
  { key: 'not object', v: 4, data: 'x' },
  { key: 'map not string', v: 4, data: mut((r) => { r.map = 5; }) },
  { key: 'player nan', v: 4, data: mut((r) => { r.player.x = 'a'; }) },
  { key: 'doors bad cell', v: 4, data: mut((r) => { r.doors.town = [[1.5, 2]]; }) },
  { key: 'people bad', v: 4, data: mut((r) => { r.people.town = 'x'; }) },
  { key: 'seed negative', v: 4, data: mut((r) => { r.run.seed = -1; }) },
  { key: 'boons too many', v: 4, data: mut((r) => { r.run.boons = new Array(21).fill('a'); }) },
  { key: 'hunger bad', v: 4, data: mut((r) => { r.run.hunger.fear = 99; }) },
  { key: 'hunger extra', v: 4, data: mut((r) => { r.run.hunger.extra = 1; }) },
  { key: 'night bad', v: 4, data: mut((r) => { r.night.status = 'zz'; }) },
  { key: 'night not object', v: 4, data: mut((r) => { r.night = 4; }) },
  { key: 'rocks out of range', v: 4, data: mut((r) => { r.rocks = 500; }) },
  { key: 'no rocks', v: 4, data: mut((r) => { delete r.rocks; }) },
  { key: 'pending boons', v: 4, data: mut((r) => { r.run.pendingBoons = ['bats_ear', 'hush', 'moonlit']; }) },
  { key: 'pending too long', v: 4, data: mut((r) => { r.run.pendingBoons = ['a', 'b', 'c', 'd']; }) },
  { key: 'forge spawned only', v: 4, data: mut((r) => { r.forge = { v: 1, maps: { town: { spawned: [{ a: 'guard_x', s: 42, x: 3.5, y: 4.5, ang: 1 }], altered: [] } } }; }) },
  { key: 'forge altered (needs forge.gd)', needsForge: true, v: 4, data: mut((r) => { r.forge = { v: 1, maps: { town: { spawned: [], altered: [{ id: 2, look: { acc: 'lantern' } }] } } }; }) },
  { key: 'forge bad', v: 4, data: mut((r) => { r.forge = { v: 2, maps: {} }; }) },
  { key: 'unknown key dropped', v: 4, data: mut((r) => { r.zed = 1; }) }
].map((c) => { const m = Save.migrateRun(c.v, c.data); const s = m.ok ? Save.sanitizeRun(m.data) : null; const val = Save.validateRun(c.data, c.v); return Object.assign({}, c, { migOk: m.ok, migCode: m.code, san: clean(s), valOk: val.ok, valCode: val.code }); });

// ---- tab lock ----
const tabMem = new Mem();
const tab = [];
tab.push({ op: 'check empty', res: Save.tabCheck(tabMem, 'a', 1000) });
Save.tabLock(tabMem, 'b', 1000);
tab.push({ op: 'check other fresh', res: Save.tabCheck(tabMem, 'a', 5000) });
tab.push({ op: 'check self', res: Save.tabCheck(tabMem, 'b', 5000) });
tab.push({ op: 'check stale', res: Save.tabCheck(tabMem, 'a', 20000) });
tab.push({ op: 'check future skew', res: Save.tabCheck(tabMem, 'a', -20000) });

mkdirSync(dirname(OUT), { recursive: true });
writeFileSync(OUT, JSON.stringify({ game, texts, wraps, sums, impCases, runCases, tab, metaData: meta, runData: run }) + '\n');
console.log('wrote ' + OUT);
