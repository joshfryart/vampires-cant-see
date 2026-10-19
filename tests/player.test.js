'use strict';
const test = require('node:test');
const assert = require('node:assert');
const Log = require('../js/log.js');
const World = require('../js/world.js');
const Player = require('../js/player.js');

Log.setConsole(false);

const CFG = { mouseSensitivity: 0.0025, invertMouse: false, moveSpeed: 3.0, turnSpeedKeys: 2.4 };
const NONE = { forward: 0, strafe: 0, turn: 0, mouseDx: 0 };
const world = World.load({
  name: 'p',
  rows: [
    '###########',
    '#.........#',
    '#....@....#',
    '#.........#',
    '###########'
  ]
});
const mk = (angle) => Player.create({ x: 5.5, y: 2.5 }, angle);
const inp = (o) => Object.assign({}, NONE, o);

test('create', () => {
  const p = Player.create({ x: 1.5, y: 2.5 });
  assert.deepStrictEqual(p, { x: 1.5, y: 2.5, angle: 0, radius: 0.2 });
});

test('forward moves along angle', () => {
  const p = mk(0);
  Player.update(p, world, inp({ forward: 1 }), 0.1, CFG);
  assert.ok(Math.abs(p.x - 5.8) < 1e-9);
  assert.ok(Math.abs(p.y - 2.5) < 1e-9);
  const q = mk(Math.PI / 2); // +y (down)
  Player.update(q, world, inp({ forward: 1 }), 0.1, CFG);
  assert.ok(Math.abs(q.y - 2.8) < 1e-9);
  assert.ok(Math.abs(q.x - 5.5) < 1e-9);
});

test('backward and strafe directions', () => {
  const p = mk(0);
  Player.update(p, world, inp({ forward: -1 }), 0.1, CFG);
  assert.ok(p.x < 5.5);
  const q = mk(0);
  Player.update(q, world, inp({ strafe: 1 }), 0.1, CFG);
  assert.ok(q.y > 2.5, 'strafe right at angle 0 is +y');
  assert.ok(Math.abs(q.x - 5.5) < 1e-9);
});

test('diagonal is not faster than straight', () => {
  const a = mk(0);
  const b = mk(0);
  Player.update(a, world, inp({ forward: 1 }), 0.1, CFG);
  Player.update(b, world, inp({ forward: 1, strafe: 1 }), 0.1, CFG);
  const da = Math.hypot(a.x - 5.5, a.y - 2.5);
  const db = Math.hypot(b.x - 5.5, b.y - 2.5);
  assert.ok(Math.abs(da - db) < 1e-9);
});

test('running into a wall for 2 s stays inside floor', () => {
  const p = mk(0);
  for (let i = 0; i < 120; i++) Player.update(p, world, inp({ forward: 1 }), 1 / 60, CFG);
  assert.ok(p.x <= 10 - p.radius + 1e-9, 'x=' + p.x);
  assert.ok(p.x > 9, 'reached the wall');
  assert.ok(!world.isSolid(p.x + p.radius, p.y));
  const q = mk(Math.PI * 0.25);
  for (let i = 0; i < 300; i++) Player.update(q, world, inp({ forward: 1, strafe: 1 }), 1 / 60, CFG);
  for (const [dx, dy] of [[-1, -1], [1, -1], [-1, 1], [1, 1]]) {
    assert.ok(!world.isSolid(q.x + dx * q.radius, q.y + dy * q.radius));
  }
});

test('slides along wall (axis-separated)', () => {
  const p = Player.create({ x: 9.7, y: 2.0 }, Math.PI / 4);
  const y0 = p.y;
  Player.update(p, world, inp({ forward: 1 }), 0.1, CFG);
  assert.ok(p.y > y0, 'still slides in y');
});

test('dt clamped to 0.1', () => {
  const a = mk(0);
  const b = mk(0);
  Player.update(a, world, inp({ forward: 1 }), 5, CFG);
  Player.update(b, world, inp({ forward: 1 }), 0.1, CFG);
  assert.ok(Math.abs(a.x - b.x) < 1e-12);
});

test('angle wraps into [0, 2pi)', () => {
  const p = mk(0);
  Player.update(p, world, inp({ mouseDx: -100 }), 0.016, CFG);
  assert.ok(p.angle >= 0 && p.angle < Math.PI * 2);
  assert.ok(Math.abs(p.angle - (Math.PI * 2 - 0.25)) < 1e-9);
  const q = mk(Math.PI * 2 - 0.1);
  Player.update(q, world, inp({ mouseDx: 100 }), 0.016, CFG);
  assert.ok(Math.abs(q.angle - 0.15) < 1e-9);
  for (let i = 0; i < 1000; i++) Player.update(q, world, inp({ turn: 1 }), 0.1, CFG);
  assert.ok(q.angle >= 0 && q.angle < Math.PI * 2);
});

test('mouse sensitivity and invert', () => {
  const a = mk(1);
  Player.update(a, world, inp({ mouseDx: 40 }), 0.016, CFG);
  assert.ok(Math.abs(a.angle - 1.1) < 1e-9);
  const b = mk(1);
  Player.update(b, world, inp({ mouseDx: 40 }), 0.016, Object.assign({}, CFG, { invertMouse: true }));
  assert.ok(Math.abs(b.angle - 0.9) < 1e-9);
});

test('key turning scales with dt', () => {
  const p = mk(1);
  Player.update(p, world, inp({ turn: 1 }), 0.1, CFG);
  assert.ok(Math.abs(p.angle - (1 + 0.24)) < 1e-9);
});

test('inputFromKeys mapping', () => {
  assert.deepStrictEqual(Player.inputFromKeys(new Set(), 0), { forward: 0, strafe: 0, turn: 0, mouseDx: 0 });
  assert.deepStrictEqual(Player.inputFromKeys(new Set(['KeyW', 'KeyD', 'ArrowLeft']), 7),
    { forward: 1, strafe: 1, turn: -1, mouseDx: 7 });
  assert.deepStrictEqual(Player.inputFromKeys(new Set(['KeyS', 'KeyA', 'ArrowRight']), -2),
    { forward: -1, strafe: -1, turn: 1, mouseDx: -2 });
  assert.deepStrictEqual(Player.inputFromKeys(new Set(['KeyW', 'KeyS', 'KeyA', 'KeyD']), 0),
    { forward: 0, strafe: 0, turn: 0, mouseDx: 0 });
});

test('arrow up/down move forward/back; keyTurnSpeed overrides turnSpeedKeys', () => {
  assert.strictEqual(Player.inputFromKeys(new Set(['ArrowUp']), 0).forward, 1);
  assert.strictEqual(Player.inputFromKeys(new Set(['ArrowDown']), 0).forward, -1);
  assert.strictEqual(Player.inputFromKeys(new Set(['ArrowUp', 'KeyS']), 0).forward, 0);
  const p = mk(1);
  Player.update(p, world, inp({ turn: 1 }), 0.1, Object.assign({}, CFG, { keyTurnSpeed: 3.2 }));
  assert.ok(Math.abs(p.angle - (1 + 0.32)) < 1e-9);
  const q = mk(1);
  Player.update(q, world, inp({ turn: 1 }), 0.1, {});
  assert.ok(Math.abs(q.angle - (1 + 0.32)) < 1e-9);
});
