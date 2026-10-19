'use strict';
const test = require('node:test');
const assert = require('node:assert');
const Log = require('../js/log.js');
const World = require('../js/world.js');
const Raycast = require('../js/raycast.js');

Log.setConsole(false);

const box = World.load({ name: 'box', rows: ['#######', '#@....#', '#.....#', '#.....#', '#######'] });
const near = (a, b, e) => assert.ok(Math.abs(a - b) < (e || 1e-6), a + ' vs ' + b);

test('straight ray hits known wall distance', () => {
  const h = Raycast.castOne(box, 2.5, 2.5, 0, 20);
  assert.strictEqual(h.hit, true);
  near(h.dist, 3.5); near(h.rayDist, 3.5);
  assert.strictEqual(h.cellX, 6); assert.strictEqual(h.cellY, 2);
  near(h.hitX, 6); near(h.hitY, 2.5);
  near(Raycast.castOne(box, 2.5, 2.5, Math.PI, 20).dist, 1.5);
  near(Raycast.castOne(box, 2.5, 2.5, Math.PI / 2, 20).dist, 1.5);
  near(Raycast.castOne(box, 2.5, 2.5, -Math.PI / 2, 20).dist, 1.5);
});

test('side: 0 for x faces, 1 for y faces', () => {
  assert.strictEqual(Raycast.castOne(box, 2.5, 2.5, 0, 20).side, 0);
  assert.strictEqual(Raycast.castOne(box, 2.5, 2.5, Math.PI / 2, 20).side, 1);
});

test('wallX within [0,1]', () => {
  for (let a = 0; a < 6.28; a += 0.1) {
    const h = Raycast.castOne(box, 2.5, 2.5, a, 20);
    assert.ok(h.wallX >= 0 && h.wallX <= 1, 'wallX ' + h.wallX);
  }
  near(Raycast.castOne(box, 2.25, 2.5, Math.PI / 2, 20).wallX, 0.25);
});

test('cast: perpendicular dist = rayDist*cos(offset)', () => {
  const fov = 66 * Math.PI / 180;
  const hits = Raycast.cast(box, 2.5, 2.5, 0, fov, 33, 20);
  assert.strictEqual(hits.length, 33);
  hits.forEach((h) => {
    near(h.dist, h.rayDist * Math.cos(h.rayAngle - 0), 1e-9);
    // facing +x at x wall: perpendicular distance is 3.5 for x-face hits
    if (h.side === 0) near(h.dist, 3.5);
  });
  near(hits[16].rayAngle, Math.atan(0) , 0.05);
});

test('no hit returns maxDist', () => {
  const h = Raycast.castOne(box, 2.5, 2.5, 0, 2);
  assert.strictEqual(h.hit, false);
  near(h.dist, 2); near(h.rayDist, 2);
  near(h.hitX, 4.5); near(h.hitY, 2.5);
  const c = Raycast.cast(box, 2.5, 2.5, 0, 1, 5, 2);
  c.forEach((x) => { assert.strictEqual(x.hit, false); assert.strictEqual(x.dist, 2); });
});

test('open-ended world does not hang', () => {
  const open = { width: 4, height: 4, isSolid: () => false };
  const h = Raycast.castOne(open, 1.5, 1.5, 0.3, 1e9);
  assert.strictEqual(h.hit, false);
  const axis = Raycast.castOne(open, 1.5, 1.5, 0, 1e9);
  assert.strictEqual(axis.hit, false);
});
