'use strict';
const { describe } = require('node:test');

describe('listen.test.js', () => {
  const test = require('node:test');
  const assert = require('node:assert');
  const Listen = require('../js/listen.js');

  // 5x3 map: row 0 outdoor, row 1 wall with window at x=2, row 2 indoor.
  function world(lit) {
    const rows = ['.....', '##w##', '.....'];
    return {
      tileAt: (x, y) => (rows[y] && rows[y][x]) || '#',
      kindAt: (x, y) => (Math.floor(y) >= 2 ? 'indoor' : Math.floor(y) === 1 ? 'indoor' : 'outdoor'),
      zoneAt: (x, y) => (Math.floor(y) >= 1 ? 'house' : null),
      lightAt: () => lit
    };
  }
  const player = { x: 2.5, y: 0.5, angle: Math.PI / 2 };
  const people = [
    { id: 1, x: 1.5, y: 2.5, mode: 'path', wary: 0 },
    { id: 2, x: 3.5, y: 2.5, mode: 'path', wary: 0 },
    { id: 3, x: 4.5, y: 2.5, mode: 'path', wary: 0 }
  ];

  test('findWindow needs outdoor, reach and facing', () => {
    const w = world(0.5);
    assert.ok(Listen.findWindow(w, player));
    assert.equal(Listen.findWindow(w, { x: 2.5, y: 0.5, angle: -Math.PI / 2 }), null);
    assert.equal(Listen.findWindow(w, { x: 0.5, y: 0.2, angle: 0 }), null);
    assert.equal(Listen.findWindow(w, { x: 2.5, y: 2.5, angle: -Math.PI / 2 }), null); // indoors
  });

  test('step enters, speaks turn by turn with up to 2 speakers, exits', () => {
    const w = world(0.5);
    const st = Listen.create();
    const calls = [];
    let stops = 0;
    const base = () => ({ held: true, holding: false, speed: 0, world: w, player, people, fear: 0, speakLength: () => 1,
      speak: (o) => { calls.push(o); return { stop() { stops++; } }; } });
    for (let t = 0; t < 10; t += 0.1) Listen.step(st, Object.assign(base(), { now: t }));
    assert.equal(st.active, true);
    assert.equal(st.count, 3);
    assert.ok(calls.length >= 3);
    assert.equal(calls[0].lpHz, 1200);
    const seeds = new Set(calls.map((c) => c.seed));
    assert.ok(seeds.size > 1);
    Listen.step(st, Object.assign(base(), { now: 11, held: false }));
    assert.equal(st.active, false);
    assert.ok(stops >= 1);
  });

  test('dark window is more muffled, noticed room is silent, moving fast exits, victim blocks', () => {
    const st = Listen.create();
    let n = 0;
    const ctx = (o) => Object.assign({ now: 0, held: true, holding: false, speed: 0, world: world(0), player, people, fear: 9, speak: () => { n++; return null; } }, o);
    let lp = 0;
    for (let t = 0; t < 5; t += 0.1) Listen.step(st, ctx({ now: t, speak: (o) => { lp = o.lpHz; n++; return null; } }));
    assert.equal(lp, 600);
    assert.equal(st.mood, 'whisper');
    const noisy = [{ id: 1, x: 1.5, y: 2.5, mode: 'startle' }];
    n = 0;
    const st2 = Listen.create();
    for (let t = 0; t < 5; t += 0.1) Listen.step(st2, ctx({ now: t, people: noisy }));
    assert.equal(n, 0);
    assert.equal(st2.silent, true);
    Listen.step(st, ctx({ now: 6, speed: 3 }));
    assert.equal(st.active, false);
    const st3 = Listen.create();
    Listen.step(st3, ctx({ holding: true }));
    assert.equal(st3.active, false);
  });

  test('never throws on garbage', () => {
    const st = Listen.create();
    assert.doesNotThrow(() => Listen.step(st, {}));
    assert.doesNotThrow(() => Listen.step(st, { held: true, world: {}, player: {} }));
    assert.equal(Listen.nearLitWindow(null, null), false);
  });
});
