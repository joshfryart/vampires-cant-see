#!/usr/bin/env node
// Golden fixture (listen.json): js/listen.js on the town map: findWindow over a grid of player poses, subtitles, and a
// scripted listening session over a real people.js simulation.
// Usage: node tools/golden/listen.mjs [outPath]   (default project/tests/fixtures/listen.json)

import { createRequire } from 'node:module';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { mkdirSync, writeFileSync } from 'node:fs';

const require = createRequire(import.meta.url);
const HERE = dirname(fileURLToPath(import.meta.url));
const PORT = resolve(HERE, '..', '..');
const JS = join(resolve(PORT, '..'), 'js');
const OUT = process.argv[2] ? resolve(process.argv[2]) : join(PORT, 'project', 'tests', 'fixtures', 'listen.json');

for (const m of ['log', 'raycast', 'world', 'data/maps', 'data/sounds', 'sonar', 'data/voices', 'data/archetypes', 'schedule', 'forge', 'people', 'listen']) require(join(JS, m + '.js'));
const VCS = globalThis.VCS;
VCS.Log.setConsole(false);
const { World, MapData, People, Listen: L, VoiceData: VD } = VCS;
const clean = (v) => (v === undefined ? null : JSON.parse(JSON.stringify(v)));

const def = MapData.maps.town;
const world = World.load(def, { requireStart: false });

const finds = [];
const wins = [];
for (let cy = 0; cy < world.height; cy++) for (let cx = 0; cx < world.width; cx++) if (world.tileAt(cx, cy) === 'w') wins.push([cx, cy]);
const seen = new Set();
for (const [wx, wy] of wins) for (let dy = -2; dy <= 2; dy++) for (let dx = -2; dx <= 2; dx++) {
  const k = (wx + dx) + ',' + (wy + dy);
  if (seen.has(k)) continue;
  seen.add(k);
  for (const a of [0, 1.5708, 3.14159, -1.5708, 0.7]) {
    const p = { x: wx + dx + 0.5, y: wy + dy + 0.5, angle: a };
    if (world.isSolid(p.x, p.y)) continue;
    finds.push({ p, win: clean(L.findWindow(world, p, 1.2)), near: L.nearLitWindow(world, p, 2.5) });
  }
}
const subs = [];
for (const dist of [0, 0.5, 1.2, 1.3, 5]) for (const lit of [0, 0.15, 0.2, 0.9]) for (const kind of ['chat', 'greet', 'question', 'murmur']) for (const seed of [1, 2, 3]) subs.push({ dist, lit, kind, seed, mood: 'calm', sub: clean(L.subtitleFor(seed, kind, 'calm', dist, lit)) });
const alpha = [{ end: 5 }, { end: 5.3 }].flatMap((s) => [4, 5, 5.3, 5.5, 6, 7].map((now) => ({ s, now, a: L.subAlpha(s, now) })));
alpha.push({ s: null, now: 3, a: L.subAlpha(null, 3) });
const kinds = [];
for (const conv of [null, { mood: 'warm' }, { mood: 'curt' }, { mood: 'hushed' }, { mood: 'neutral' }]) for (const mood of ['calm', 'worried', 'whisper']) kinds.push({ conv, mood, res: L.conversationKinds(conv, mood) });
const moods = [0, 3.9, 4, 7.9, 8, 20].map((f) => ({ f, m: L.moodFor(f) }));

const DT = 0.1;
function session(spec) {
  const state = People.create(world, def, { seed: spec.seed, shuffle: false });
  const st = L.create();
  const log = [];
  const calls = [];
  let t = 0;
  const ops = spec.ops;
  let oi = 0;
  let held = false, holding = false, speed = 0, fear = 0;
  let player = { x: spec.player[0], y: spec.player[1], angle: spec.player[2] };
  const steps = Math.round(spec.seconds / DT);
  for (let i = 0; i < steps; i++) {
    while (oi < ops.length && ops[oi].t <= t + 1e-9) {
      const o = ops[oi++];
      if (o.op === 'held') held = o.v; else if (o.op === 'holding') holding = o.v; else if (o.op === 'speed') speed = o.v; else if (o.op === 'fear') fear = o.v;
      else if (o.op === 'player') player = { x: o.x, y: o.y, angle: o.a };
    }
    People.update(state, world, DT, { nightFrac: Math.min(1, t / spec.seconds), nightSec: spec.seconds, fear });
    t += DT;
    const changes = [];
    L.step(st, {
      now: t, held, holding, speed, world, player, people: state.people, fear,
      speak: (o) => { calls.push({ t, seed: o.seed, kind: o.kind, mood: o.mood, pan: o.pan, lpHz: o.lpHz, gain: o.gain, voice: o.voice === undefined ? null : o.voice }); return { stop() {}, end: 0 }; },
      speakLength: (seed, kind, mood) => VD.lineLength(VD.line(seed, kind, mood)),
      voiceFor: (p, seed) => p.role || 'man',
      pan: (x, y) => (x - player.x) * 0.1,
      onChange: (a, info) => changes.push([a, info ? info.count : -1]),
      conversationFor: (id) => People.conversationFor(state, id),
      onSubtitle: (sub, who) => changes.push(['sub', sub.de, sub.en, who.id])
    });
    log.push({ t, active: st.active, count: st.count, silent: st.silent, mood: st.mood, lpHz: st.lpHz, turn: st.turn, nextAt: st.nextAt, speaker: st.speaker, win: st.win ? [st.win.cx, st.win.cy] : null, sub: st.sub ? [st.sub.de, st.sub.end] : null, changes });
  }
  return { spec, log, calls };
}
// Pick a window with a populated room: scan a sim for the first window with an insider.
let pick = null;
{
  const state = People.create(world, def, { seed: 5, shuffle: false });
  for (let i = 0; i < 1200 && !pick; i++) {
    People.update(state, world, 0.1, { nightFrac: i / 1200, nightSec: 120, fear: 0 });
    for (const [wx, wy] of wins) {
      for (const [dx, dy, a] of [[0, 1, -1.5708], [0, -1, 1.5708], [1, 0, 3.14159], [-1, 0, 0]]) {
        const p = { x: wx + 0.5 + dx * 0.6, y: wy + 0.5 + dy * 0.6, angle: a };
        if (world.isSolid(p.x, p.y)) continue;
        const w = L.findWindow(world, p, 1.2);
        if (w && L.insiders(world, state.people, w).length >= 1) { pick = { p, t: i * 0.1 }; break; }
      }
      if (pick) break;
    }
  }
}
console.log('pick', JSON.stringify(pick));
const p0 = pick ? pick.p : { x: 10.5, y: 10.5, angle: 0 };
const sessions = [
  { seed: 5, seconds: 120, player: [p0.x, p0.y, p0.angle], ops: [{ t: 0, op: 'held', v: true }, { t: 40, op: 'fear', v: 5 }, { t: 60, op: 'speed', v: 1.5 }, { t: 61, op: 'speed', v: 0 }, { t: 80, op: 'fear', v: 9 }, { t: 100, op: 'held', v: false }, { t: 105, op: 'held', v: true }, { t: 110, op: 'holding', v: true }] }
];
const out = sessions.map(session);
mkdirSync(dirname(OUT), { recursive: true });
writeFileSync(OUT, JSON.stringify({ dt: DT, finds, subs, alpha, kinds, moods, sessions: out }) + '\n');
console.log('wrote ' + OUT + ' (' + finds.length + ' finds, ' + out.map((s) => s.calls.length + ' speaks').join(', ') + ')');
