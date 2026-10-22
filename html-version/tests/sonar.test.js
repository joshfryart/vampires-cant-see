'use strict';
// Merged test file: each source file's tests live in their own describe().
const { describe } = require('node:test');

describe('sonar.test.js', () => {

  const test = require('node:test');
  const assert = require('node:assert');
  const Log = require('../js/log.js');
  const World = require('../js/world.js');
  const Raycast = require('../js/raycast.js');
  const Sonar = require('../js/sonar.js');

  Log.setConsole(false);

  const room = World.load({
    name: 'room',
    rows: [
      '###############',
      '#@............#',
      '#.....#.......#',
      '#.....#.......#',
      '#.............#',
      '###############'
    ]
  });

  test('cooldown blocks second emit', () => {
    const s = Sonar.create({ cooldown: 0.8, bounces: 0 });
    assert.strictEqual(Sonar.emit(s, room, 2.5, 1.5, 10), true);
    assert.strictEqual(Sonar.emit(s, room, 2.5, 1.5, 10.5), false);
    assert.ok(Math.abs(Sonar.cooldownLeft(s, 10.5) - 0.3) < 1e-9);
    assert.strictEqual(Sonar.cooldownLeft(s, 12), 0);
    assert.strictEqual(Sonar.emit(s, room, 2.5, 1.5, 10.9), true);
    assert.strictEqual(s.lastPulse, s.pulses[1]);
  });

  test('brightness timeline: 0 before, max at arrival, 0 after fade', () => {
    const s = Sonar.create({ speed: 10, fade: 2, range: 10, bounces: 0 });
    Sonar.emit(s, room, 2.5, 1.5, 0);
    const px = 4.5, py = 1.5; // d = 2
    assert.strictEqual(Sonar.brightnessAt(s, px, py, 0.1), 0);
    const b0 = Sonar.brightnessAt(s, px, py, 0.2);
    assert.ok(Math.abs(b0 - 0.9) < 1e-6, 'b0 ' + b0); // 1 * (1 - 0.5*0.2)
    const mid = Sonar.brightnessAt(s, px, py, 1.2);
    assert.ok(mid > 0 && mid < b0);
    assert.strictEqual(Sonar.brightnessAt(s, px, py, 2.3), 0);
  });

  test('hidden point behind wall and beyond range are dark', () => {
    const s = Sonar.create({ speed: 10, fade: 5, range: 10 });
    Sonar.emit(s, room, 2.5, 1.5, 0);
    assert.ok(Sonar.brightnessAt(s, 6.0, 2.5, 1) > 0, 'wall face lit'); // wall at x=6
    assert.strictEqual(Sonar.brightnessAt(s, 8.5, 2.5, 1), 0);
    assert.strictEqual(Sonar.brightnessAt(s, 13.5, 1.5, 3), 0); // d=11 > range
  });

  test('nearestDist and ringRadius', () => {
    const s = Sonar.create({ speed: 12 });
    Sonar.emit(s, room, 2.5, 1.5, 5);
    const p = s.lastPulse;
    assert.ok(Math.abs(Sonar.nearestDist(p) - 0.5) < 1e-4);
    assert.ok(Math.abs(Sonar.ringRadius(p, 5.5) - 6) < 1e-9);
    assert.strictEqual(p.vis instanceof Float32Array, true);
    assert.strictEqual(p.vis.length, 720);
  });

  test('prune removes old pulses', () => {
    const s = Sonar.create({ speed: 10, range: 10, fade: 2, cooldown: 0.1, bounces: 0 });
    Sonar.emit(s, room, 2.5, 1.5, 0);
    Sonar.emit(s, room, 2.5, 1.5, 2);
    Sonar.prune(s, 2.9);
    assert.strictEqual(s.pulses.length, 2);
    Sonar.prune(s, 3.5);
    assert.strictEqual(s.pulses.length, 1);
    Sonar.prune(s, 100);
    assert.strictEqual(s.pulses.length, 0);
  });

  test('maxPulses cap drops oldest', () => {
    const s = Sonar.create({ maxPulses: 2, cooldown: 0.1, bounces: 0 });
    for (let i = 0; i < 5; i++) Sonar.emit(s, room, 2.5, 1.5, i);
    assert.strictEqual(s.pulses.length, 2);
    assert.strictEqual(s.pulses[0].t0, 3);
    assert.strictEqual(s.pulses[1].t0, 4);
  });

  test('defaults applied', () => {
    const s = Sonar.create();
    assert.strictEqual(s.speed, 12); assert.strictEqual(s.visRays, 720);
    assert.ok(Raycast);
  });

  test('ageAt: -1 before arrival, age after, -1 when hidden/out of range/faded', () => {
    const s = Sonar.create({ speed: 12, fade: 3, cooldown: 0.1 });
    Sonar.emit(s, room, 2.5, 1.5, 0);
    // wall face at x=6: d = 3.5 -> litAt = 3.5/12
    const litAt = 3.5 / 12;
    assert.strictEqual(Sonar.ageAt(s, 6.0, 1.5, litAt - 0.05), -1);
    const a = Sonar.ageAt(s, 6.0, 1.5, litAt + 0.1);
    assert.ok(Math.abs(a - 0.1) < 1e-9);
    assert.strictEqual(Sonar.ageAt(s, 6.0, 1.5, litAt + 3.5), -1);
    assert.strictEqual(Sonar.ageAt(s, 13.5, 1.5, 1), -1);
  });

  test('ageAt picks the strongest (youngest) pulse and agrees with brightnessAt', () => {
    const s = Sonar.create({ speed: 12, fade: 3, cooldown: 0.1 });
    Sonar.emit(s, room, 2.5, 1.5, 0);
    Sonar.emit(s, room, 2.5, 1.5, 1);
    const t = 1.5;
    const age = Sonar.ageAt(s, 6.0, 1.5, t);
    assert.ok(Sonar.brightnessAt(s, 6.0, 1.5, t) > 0);
    assert.ok(Math.abs(age - (t - 1 - 3.5 / 12)) < 1e-9);
    assert.strictEqual(Sonar.ageAt(Sonar.create(), 1, 1, 0), -1);
  });

  test('visibleFrom matches brightness visibility; litAt is distance over speed', () => {
    const s = Sonar.create({ speed: 10, range: 10, fade: 1 });
    Sonar.emit(s, room, 1.5, 1.5, 0);
    const p = s.lastPulse;
    assert.strictEqual(Sonar.visibleFrom(p, 4.5, 1.5), true);
    // Behind the pillar at column 6 rows 2-3 from (1.5,1.5): point (8.5, 3.2)
    // Pick a clearly hidden point: inside the pillar wall itself far side.
    assert.strictEqual(Sonar.visibleFrom(p, 6.9, 2.5), false);
    assert.ok(Math.abs(Sonar.litAt(p, 4.5, 1.5) - 0.3) < 1e-9);
    assert.strictEqual(Sonar.visibleFrom({ x: 0, y: 0 }, 3, 3), true);
  });

  test('strength scales brightness and ageAt still works', () => {
    const s = Sonar.create({ speed: 10, fade: 2, range: 10, bounces: 0 });
    Sonar.emitSound(s, room, 2.5, 1.5, 0, { strength: 0.5, visRays: 360 });
    const b = Sonar.brightnessAt(s, 4.5, 1.5, 0.2);
    assert.ok(Math.abs(b - 0.45) < 1e-6, 'b ' + b);
    assert.ok(Math.abs(Sonar.ageAt(s, 4.5, 1.5, 0.2) - 0) < 1e-9);
    assert.strictEqual(s.maxPulses, 64);
  });

  test('emitSound: no bounces by default, kind/gen/strength recorded', () => {
    const s = Sonar.create();
    const p = Sonar.emitSound(s, room, 2.5, 1.5, 3, { kind: 'step', range: 2.2, strength: 0.22 });
    assert.strictEqual(s.pulses.length, 1);
    assert.strictEqual(p.kind, 'step'); assert.strictEqual(p.gen, 0);
    assert.strictEqual(p.range, 2.2); assert.strictEqual(p.vis.length, 360);
    assert.strictEqual(s.lastEmit, -Infinity);
  });

  test('bounce children: t0, strength, gen, range, cap', () => {
    const s = Sonar.create({ speed: 10, range: 10 });
    const p = Sonar.emitSound(s, room, 2.5, 2.5, 1, { kind: 'ping', bounces: 1, visRays: 360 });
    const kids = s.pulses.filter((q) => q.gen === 1);
    assert.ok(kids.length > 0 && kids.length <= 6);
    for (const k of kids) {
      const dist = Math.hypot(k.x - p.x, k.y - p.y) + 0.08;
      assert.ok(Math.abs(k.t0 - (1 + dist / 10)) < 0.02, 't0');
      assert.ok(Math.abs(k.strength - 0.45) < 1e-9);
      assert.ok(Math.abs(k.range - (10 - dist)) < 0.02);
      assert.strictEqual(k.vis.length, 180);
    }
    const s2 = Sonar.create();
    Sonar.emitSound(s2, room, 2.5, 2.5, 0, { bounces: 2 });
    assert.ok(s2.pulses.length <= 12);
    assert.ok(s2.pulses.some((q) => q.gen === 2));
    const s3 = Sonar.create();
    Sonar.emitSound(s3, room, 2.5, 2.5, 0, { bounces: 0 });
    assert.strictEqual(s3.pulses.length, 1);
    const s4 = Sonar.create({ maxPulses: 3 });
    Sonar.emitSound(s4, room, 2.5, 2.5, 0, { bounces: 2 });
    assert.strictEqual(s4.pulses.length, 3);
  });

  test('emit (click) produces bounces by default', () => {
    const s = Sonar.create();
    assert.strictEqual(Sonar.emit(s, room, 2.5, 2.5, 0), true);
    assert.ok(s.pulses.length > 1);
    assert.strictEqual(s.lastPulse, s.pulses[0]);
  });

  test('point around a corner is lit by a bounce only', () => {
    const corner = World.load({ name: 'c', rows: [
      '##########',
      '#@.......#',
      '#.######.#',
      '#.#....#.#',
      '#.#....#.#',
      '#.######.#',
      '#........#',
      '##########' ] });
    // Point in hallway at (1.5,5.5) is hidden from (4.5,1.5) behind the block, bounce from the left wall sees it? use direct check of mechanism
    const s = Sonar.create({ speed: 10, range: 12, fade: 3 });
    const hidden = [1.5, 5.5];
    const p = Sonar.emitSound(s, corner, 1.5, 1.5, 0, { bounces: 0, visRays: 360 });
    // Direct line down column 1 is visible; choose hidden point instead: (4.5,6.5) behind block from (6.5,1.5)
    const s2 = Sonar.create({ speed: 10, range: 14, fade: 3 });
    const a = Sonar.emitSound(s2, corner, 8.5 - 0.0, 1.5, 0, { bounces: 0, visRays: 360 });
    assert.ok(a && p && hidden);
    const target = [5.5, 6.5];
    assert.ok(!Sonar.visibleFrom(a, target[0], target[1]), 'hidden from primary');
    assert.strictEqual(Sonar.brightnessAt(s2, target[0], target[1], 2), 0);
    const s3 = Sonar.create({ speed: 10, range: 14, fade: 3 });
    Sonar.emitSound(s3, corner, 8.5, 1.5, 0, { bounces: 2, visRays: 360 });
    let best = 0;
    for (let t = 0; t < 3; t += 0.05) best = Math.max(best, Sonar.brightnessAt(s3, target[0], target[1], t));
    assert.ok(best > 0, 'lit by bounce ' + best);
  });

  test('wallArc symmetric, NaN when R < dh, count', () => {
    const pulse = { x: 0, y: 0, t0: 0, speed: 10 };
    const out = new Float32Array(8);
    let n = Sonar.wallArc(pulse, 0.5, 3, 4, 4, out); // dh=5, ring=5
    assert.strictEqual(n, 0);
    for (let i = 0; i < 8; i++) assert.ok(Number.isNaN(out[i]));
    n = Sonar.wallArc(pulse, 0.6, 3, 4, 4, out); // ring 6, dh 5: dz = sqrt(11)
    assert.ok(n >= 1);
    n = Sonar.wallArc(pulse, 0.52, 3, 4, 2, out); // ring 5.2: dz=sqrt(5.2^2-25)=1.42 -> clipped
    assert.strictEqual(n, 1);
    assert.strictEqual(out[0], 0); assert.strictEqual(out[1], 1);
    const p2 = { x: 0, y: 0, t0: 0, speed: 1 };
    Sonar.wallArc(p2, 1.0, 0.95, 0, 2, out); // ring 1, dh .95 : dz=.312
    assert.ok(Math.abs((0.5 - out[0]) - (out[1] - 0.5)) < 1e-6);
    assert.ok(Number.isNaN(out[2]));
  });

  test('brightnessAt benchmark', () => {
    const s = Sonar.create({ maxPulses: 64 });
    for (let i = 0; i < 40; i++) s.pulses.push({ x: 2 + (i % 5), y: 1.5, t0: 0, range: 10, speed: 12, vis: new Float32Array(180).fill(8), strength: 0.5, kind: 'ping', gen: 1 });
    let sink = 0;
    for (let w = 0; w < 200; w++) sink += Sonar.brightnessAt(s, 5 + (w % 7), 3, 0.5);
    const t0 = process.hrtime.bigint();
    for (let i = 0; i < 1000; i++) sink += Sonar.brightnessAt(s, 3 + (i % 9), 2.5, 0.5);
    const ms = Number(process.hrtime.bigint() - t0) / 1e6;
    console.log('bench 1000x40 ms', ms.toFixed(2), sink > -1);
    assert.ok(ms < 20, 'ms ' + ms);
  });

  test('3D: floor source lights z=0 before z=1; step pulse never lights z=1 one cell away', () => {
    const s = Sonar.create({ speed: 10, fade: 3, range: 10, bounces: 0 });
    Sonar.emitSound(s, room, 2.5, 1.5, 0, { kind: 'ping', range: 6, strength: 1, z: 0 });
    // 3 cells away: z0 dist 3 -> t=0.3 ; z1 dist sqrt(10)=3.162 -> t=0.3162
    assert.ok(Sonar.brightnessAt3(s, 5.5, 1.5, 0, 0.305) > 0);
    assert.strictEqual(Sonar.brightnessAt3(s, 5.5, 1.5, 1, 0.305), 0);
    assert.ok(Sonar.brightnessAt3(s, 5.5, 1.5, 1, 0.33) > 0);
    const s2 = Sonar.create({ speed: 12, fade: 3, bounces: 0 });
    Sonar.emitSound(s2, room, 2.5, 1.5, 0, { kind: 'step', range: 0.7, strength: 0.3, z: 0, fade: 0.8 });
    assert.strictEqual(Sonar.brightnessAt3(s2, 3.5, 1.5, 1.0, 0.5), 0);
    assert.ok(Sonar.brightnessAt3(s2, 2.9, 1.5, 0, 0.5) > 0);
  });

  test('3D: heightBand values', () => {
    const p = { x: 0, y: 0, z: 0.5, t0: 0, speed: 10, range: 10 };
    const out = [0, 0];
    assert.strictEqual(Sonar.heightBand(p, 0.2, 3, 0, out), false); // R=2 < dh=3
    assert.strictEqual(Sonar.heightBand(p, 0.5, 3, 0, out), true); // R=5, dz=4
    assert.ok(Math.abs(out[0] - 0) < 1e-9 && Math.abs(out[1] - 1.2) < 1e-9);
    const q = { x: 0, y: 0, z: 0, t0: 0, speed: 10, range: 10 };
    assert.strictEqual(Sonar.heightBand(q, 0.31, 3, 0, out), true); // R=3.1, dz=sqrt(0.61)
    assert.ok(Math.abs(out[0]) < 1e-9 && Math.abs(out[1] - Math.sqrt(0.61)) < 1e-9);
    assert.strictEqual(Sonar.heightBand(q, 5, 11, 0, out), false); // R clamped to range 10 < 11
  });

  test('3D: old brightnessAt unchanged for z 0.5 sources; defaults and bounce inheritance', () => {
    const s = Sonar.create({ speed: 10, fade: 2, range: 10, bounces: 0 });
    Sonar.emit(s, room, 2.5, 1.5, 0);
    assert.strictEqual(s.lastPulse.z, 0.5);
    assert.strictEqual(s.lastPulse.fade, 2);
    assert.ok(Math.abs(Sonar.brightnessAt(s, 4.5, 1.5, 0.2) - 0.9) < 1e-6);
    assert.strictEqual(Sonar.brightnessAt(s, 4.5, 1.5, 0.2), Sonar.brightnessAt3(s, 4.5, 1.5, 0.5, 0.2));
    const b = Sonar.create({ speed: 12, fade: 3, range: 10, bounces: 2 });
    Sonar.emitSound(b, room, 2.5, 1.5, 0, { kind: 'door', range: 8, z: 0.3, fade: 2, bounces: 1 });
    assert.ok(b.pulses.length > 1);
    for (const p of b.pulses) assert.strictEqual(p.z, 0.3);
    assert.strictEqual(b.pulses[0].fade, 2);
    assert.ok(Math.abs(b.pulses[1].fade - 1.6) < 1e-9);
  });

  test('3D: per-pulse fade and wallArc centre', () => {
    const s = Sonar.create({ speed: 10, fade: 3, range: 10, bounces: 0 });
    Sonar.emitSound(s, room, 2.5, 1.5, 0, { range: 6, fade: 0.5, z: 0 });
    assert.ok(Sonar.brightnessAt3(s, 4.5, 1.5, 0, 0.4) > 0);
    assert.strictEqual(Sonar.brightnessAt3(s, 4.5, 1.5, 0, 0.8), 0); // arrival 0.2 + 0.5 < 0.8
    assert.ok(Sonar.ageAt3(s, 4.5, 1.5, 0, 0.4) > 0);
    assert.strictEqual(Sonar.ageAt3(s, 4.5, 1.5, 0, 0.8), -1);
    Sonar.prune(s, 1.5);
    assert.strictEqual(s.pulses.length, 0);
    const p = { x: 0, y: 0, z: 0, t0: 0, speed: 10 };
    const out = new Array(2);
    Sonar.wallArc(p, 0.5, 3, 0, 1, out);
    assert.ok(out[0] === 0 && Math.abs(out[1] - 4) < 1e-9 === false ? out[1] === 1 : true);
    assert.strictEqual(out[0], 0);
  });

  test('perf: brightnessAt 1000 calls x 40 pulses', () => {
    const s = Sonar.create({ speed: 12, fade: 3, range: 10, bounces: 0, maxPulses: 64 });
    for (let i = 0; i < 40; i++) Sonar.emitSound(s, room, 2.5 + (i % 5) * 0.5, 1.5 + (i % 3), 0, { range: 10, visRays: 360 });
    Sonar.brightnessAt(s, 5, 2, 0.5);
    const t0 = process.hrtime.bigint();
    let acc = 0;
    for (let i = 0; i < 1000; i++) acc += Sonar.brightnessAt3(s, 3 + (i % 7), 2, (i % 3) * 0.5, 0.4);
    const ms = Number(process.hrtime.bigint() - t0) / 1e6;
    console.log('bench ms', ms.toFixed(2), acc > 0);
    assert.ok(ms < 20, 'ms ' + ms);
  });

});

describe('sonar-reset.test.js', () => {

  const test = require('node:test');
  const assert = require('node:assert');
  const Log = require('../js/log.js');
  const World = require('../js/world.js');
  const Raycast = require('../js/raycast.js');
  const Sonar = require('../js/sonar.js');

  Log.setConsole(false);
  void Raycast;

  const room = World.load({
    name: 'room',
    rows: [
      '###############',
      '#@............#',
      '#.....#.......#',
      '#.....#.......#',
      '#.............#',
      '###############'
    ]
  });

  test('reset clears pulses and lastPulse, and keeps the config', () => {
    const s = Sonar.create({ cooldown: 0.8, bounces: 2, range: 9, fade: 2.5 });
    assert.strictEqual(Sonar.emit(s, room, 2.5, 1.5, 10), true);
    assert.ok(s.pulses.length > 0);
    assert.ok(s.lastPulse);
    assert.strictEqual(Sonar.reset(s), s);
    assert.strictEqual(s.pulses.length, 0);
    assert.strictEqual(s.lastPulse, null);
    assert.strictEqual(s.cooldown, 0.8);
    assert.strictEqual(s.bounces, 2);
    assert.strictEqual(s.range, 9);
    assert.strictEqual(s.fade, 2.5);
  });

  test('cooldown still applies after reset, and emitting works once it has passed', () => {
    const s = Sonar.create({ cooldown: 0.8, bounces: 0 });
    assert.strictEqual(Sonar.emit(s, room, 2.5, 1.5, 10), true);
    Sonar.reset(s);
    assert.strictEqual(Sonar.emit(s, room, 2.5, 1.5, 10.3), false);
    assert.ok(Math.abs(Sonar.cooldownLeft(s, 10.3) - 0.5) < 1e-9);
    assert.strictEqual(Sonar.emit(s, room, 2.5, 1.5, 10.9), true);
    assert.strictEqual(s.pulses.length, 1, 'only the new pulse after reset');
  });

  test('reset tolerates bad input', () => {
    assert.strictEqual(Sonar.reset(null), null);
  });

  test('sample2 matches brightnessAt3 / ageAt3 over a grid and several pulses', () => {
    const s = Sonar.create({ cooldown: 0, bounces: 1, range: 9, fade: 2 });
    Sonar.emit(s, room, 2.5, 1.5, 10);
    Sonar.emitSound(s, room, 3.5, 2.5, 10.2, { kind: 'step', range: 6, strength: 0.6, z: 0.1 });
    const out = new Float64Array(3);
    for (const t of [10.1, 10.5, 11, 11.8, 12.5]) {
      for (let x = 0.2; x < 6; x += 0.37) {
        for (let y = 0.2; y < 4; y += 0.41) {
          Sonar.sample2(s, x, y, t, out);
          const b0 = Sonar.brightnessAt3(s, x, y, 0, t);
          const b1 = Sonar.brightnessAt3(s, x, y, 1, t);
          assert.ok(Math.abs(out[0] - b0) < 1e-9 && Math.abs(out[1] - b1) < 1e-9, 'brightness ' + x + ',' + y);
          const b = Math.max(b0, b1);
          const age = b > 0 ? Sonar.ageAt3(s, x, y, b0 >= b1 ? 0 : 1, t) : -1;
          assert.ok(Math.abs(out[2] - age) < 1e-9, 'age ' + x + ',' + y);
        }
      }
    }
  });

  test('sample3 matches brightnessAt3 / ageAt3 and reports the pulse fade and index; sample2 writes fade in slot 3', () => {
    const s = Sonar.create({ cooldown: 0, bounces: 1, range: 9, fade: 2 });
    Sonar.emit(s, room, 2.5, 1.5, 10);
    Sonar.emitSound(s, room, 3.5, 2.5, 10.2, { kind: 'step', range: 6, strength: 0.6, z: 0.1, fade: 0.8 });
    const out = new Float64Array(4);
    const o2 = new Float64Array(4);
    let litSeen = 0;
    for (const t of [10.1, 10.5, 11, 11.8, 12.5]) {
      for (let x = 0.2; x < 6; x += 0.37) {
        for (let y = 0.2; y < 4; y += 0.41) {
          for (const z of [0, 0.5, 1]) {
            const b = Sonar.sample3(s, x, y, z, t, out);
            const bRef = Sonar.brightnessAt3(s, x, y, z, t);
            assert.ok(Math.abs(b - bRef) < 1e-9 && Math.abs(out[0] - bRef) < 1e-9, 'b ' + x + ',' + y + ',' + z);
            const age = bRef > 0 ? Sonar.ageAt3(s, x, y, z, t) : -1;
            assert.ok(Math.abs(out[1] - age) < 1e-9, 'age ' + x + ',' + y + ',' + z);
            if (bRef > 0) {
              litSeen++;
              const idx = out[3];
              assert.ok(idx >= 0 && idx < s.pulses.length, 'index in range');
              const p = s.pulses[idx];
              assert.strictEqual(out[2], p.fade === undefined ? s.fade : p.fade, 'fade of the strongest pulse');
              assert.ok(out[2] === 2 || out[2] === 0.8 || Math.abs(out[2] - 1.6) < 1e-9, 'fade value ' + out[2]);
            } else {
              assert.strictEqual(out[2], 0);
              assert.strictEqual(out[3], -1);
            }
          }
          Sonar.sample2(s, x, y, t, o2);
          if (o2[0] > 0 || o2[1] > 0) assert.ok(o2[3] > 0, 'sample2 fade slot');
          else assert.strictEqual(o2[3], 0);
        }
      }
    }
    assert.ok(litSeen > 50);
    // Bad input never throws and reads as unlit; a 3-slot array still works for sample2.
    assert.strictEqual(Sonar.sample3(null, 1, 1, 0.5, 10, out), 0);
    assert.strictEqual(out[1], -1);
    assert.doesNotThrow(() => Sonar.sample2(s, 1.5, 1.5, 10.3, new Float64Array(3)));
  });

});


describe('sonar-echo.test.js (v0.11 materials, beam, strongest echo)', () => {
  const test = require('node:test');
  const assert = require('node:assert');
  const World = require('../js/world.js');
  const Sonar = require('../js/sonar.js');
  const SoundData = require('../js/data/sounds.js');
  globalThis.VCS = globalThis.VCS || {};
  globalThis.VCS.SoundData = SoundData;
  const A = SoundData.acoustics;

  // Glass pane north, iron gate south, stone elsewhere.
  const mats = World.load({
    name: 'mats',
    rows: [
      '###########',
      '#####w#####',
      '#@........#',
      '#.........#',
      '#.........#',
      '#.........#',
      '#.........#',
      '####I######',
      '###########'
    ]
  });
  const hall = World.load({
    name: 'hall',
    rows: [
      '###########',
      '#.........#',
      '#.........#',
      '#....@....#',
      '#.........#',
      '#.........#',
      '###########'
    ]
  });
  const tube = World.load({ name: 'tube', rows: ['#########', '#.......#', '#...@...#', '#.......#', '#########'] });

  test('pulses expose per-ray material, normal code and roughness', () => {
    const s = Sonar.create({ bounces: 0, visRays: 360 });
    Sonar.emit(s, hall, 5.5, 3.5, 0, { facing: 0 });
    const p = s.lastPulse;
    assert.ok(p.vmat instanceof Uint8Array && p.vnorm instanceof Uint8Array && p.vmat.length === p.vis.length);
    const east = Sonar.hitInfo(p, 0);
    assert.strictEqual(east.hit, true);
    assert.strictEqual(east.mat, 'stone');
    assert.strictEqual(east.nx, -1);
    assert.ok(Math.abs(east.cosInc - 1) < 1e-9, 'head-on');
    assert.ok(Math.abs(east.rough - A.roughOf('stone')) < 1e-12);
    const out = {};
    Sonar.hitInfo(p, Math.PI / 2, out); // +y: bottom wall
    assert.strictEqual(out.ny, -1);
    Sonar.hitInfo(p, Math.PI / 4, out);
    assert.ok(out.cosInc > 0 && out.cosInc < 1, 'oblique hit has a partial incidence cosine');
  });

  test('every wall material is reported by name and has a roughness', () => {
    const s = Sonar.create({ bounces: 0, visRays: 720 });
    Sonar.emit(s, mats, 5.5, 4.5, 0);
    const seen = {};
    const p = s.lastPulse;
    for (let i = 0; i < p.vis.length; i++) {
      const h = Sonar.hitInfo(p, (i / p.vis.length) * Math.PI * 2);
      if (h.hit) seen[h.mat] = h.rough;
    }
    assert.ok('glass' in seen && 'iron' in seen && 'stone' in seen, Object.keys(seen).join());
    assert.ok(seen.glass < seen.stone && seen.iron > seen.stone);
    for (const m of Sonar.MATS) assert.ok(typeof A.matOf(m).rough === 'number', m);
  });

  test('mouth beam: pings facing +x are brighter ahead than behind; no facing means no beam', () => {
    const s = Sonar.create({ bounces: 0, visRays: 360, speed: 10, fade: 2, range: 10 });
    Sonar.emit(s, hall, 5.5, 3.5, 0, { facing: 0 });
    const p = s.lastPulse;
    assert.ok(p.vbeam && p.facing === 0);
    const ahead = Sonar.brightnessAt(s, 8.5, 3.5, 0.4);
    const behind = Sonar.brightnessAt(s, 2.5, 3.5, 0.4);
    assert.ok(ahead > 0 && behind > 0);
    assert.ok(Math.abs(behind / ahead - A.visFactor(-20)) < 0.05, 'rear is about the 180 degree value: ' + behind / ahead);
    assert.ok(Math.abs(Sonar.beamAt(p, 0) - 1) < 1e-9);
    assert.ok(Math.abs(Sonar.beamAt(p, Math.PI / 2) - A.visFactor(-8)) < 0.01);
    const s2 = Sonar.create({ bounces: 0, visRays: 360 });
    Sonar.emit(s2, hall, 5.5, 3.5, 0);
    assert.strictEqual(s2.lastPulse.vbeam, undefined);
    assert.strictEqual(Sonar.beamAt(s2.lastPulse, 1), 1);
  });

  test('beam is applied once: bounce children inherit it through their strength, not a second table', () => {
    const s = Sonar.create({ bounces: 1, visRays: 360 });
    Sonar.emit(s, hall, 5.5, 3.5, 0, { facing: 0 });
    const kids = s.pulses.filter((p) => p.gen === 1);
    assert.ok(kids.length > 0);
    for (const k of kids) {
      assert.strictEqual(k.vbeam, undefined, 'children have no beam of their own');
      assert.ok(k.mat && Sonar.MATS.indexOf(k.mat) >= 0);
      assert.ok(k.strength <= 0.45 + 1e-9);
    }
    const back = kids.filter((k) => k.x < 2.5).map((k) => k.strength);
    const front = kids.filter((k) => k.x > 8.5).map((k) => k.strength);
    if (back.length && front.length) assert.ok(Math.max.apply(null, back) < Math.max.apply(null, front), 'a wall behind the head re-radiates less');
  });

  test('strongestEcho: perpendicular near wall wins; level follows the formula; null without a pulse', () => {
    const s = Sonar.create({ bounces: 0, visRays: 720 });
    Sonar.emit(s, tube, 4.5, 2.5, 0, { facing: 0 });
    const e = Sonar.strongestEcho(s.lastPulse, 0);
    assert.ok(e && e.mat === 'stone');
    assert.ok(e.dist >= 1.5 && e.dist < 2, 'a near side wall, tilted toward the beam axis: ' + e.dist);
    assert.ok(Math.cos(e.theta) > 0,'the beam pulls the loudest return toward the facing side');
    const want = A.echoLevel('wall', e.dist, e.theta, 'stone') + 20 * Math.log10(Math.max(e.cosInc, 0.25));
    assert.ok(Math.abs(e.level - want) < 1e-9);
    const e2 = Sonar.strongestEcho(s.lastPulse, Math.PI);
    assert.ok(e2.dist >= 1.5 && e2.dist < 2);
    assert.ok(Math.cos(e2.angle - Math.PI) > 0, 'facing west favours the west half');
    assert.strictEqual(Sonar.strongestEcho(null), null);
  });

  test('echo timing stays 2d / v at the one sonar speed for the strongest echo', () => {
    const s = Sonar.create({ bounces: 0, visRays: 360 });
    Sonar.emit(s, tube, 4.5, 2.5, 0, { facing: 0 });
    const e = Sonar.strongestEcho(s.lastPulse, 0);
    assert.ok(Math.abs(Sonar.echoDelay(e.dist, s.speed) - (2 * e.dist) / Sonar.SONAR_SPEED) < 1e-12);
  });
});
