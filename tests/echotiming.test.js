'use strict';
const { test } = require('node:test');
const assert = require('node:assert');
const Sonar = require('../js/sonar.js');

test('one sonar speed: wall echo delay is the round trip at SONAR_SPEED', () => {
  assert.strictEqual(Sonar.SONAR_SPEED, 12);
  assert.strictEqual(Sonar.DEFAULTS.speed, Sonar.SONAR_SPEED);
  const want = { 1: 0.1666667, 5: 0.8333333, 10: 1.6666667 };
  for (const d of [1, 5, 10]) {
    const delay = Sonar.echoDelay(d);
    assert.ok(Math.abs(delay - want[d]) < 1e-6, 'd=' + d);
    // The wavefront reaches the wall at d/v and returns at 2d/v: ring radius at that time is 2d.
    const pulse = { x: 0, y: 0, t0: 0, speed: Sonar.SONAR_SPEED };
    assert.ok(Math.abs(Sonar.litAt(pulse, d, 0) * 2 - delay) < 1e-9);
    assert.ok(Math.abs(Sonar.ringRadius(pulse, delay) - 2 * d) < 1e-9);
  }
});
