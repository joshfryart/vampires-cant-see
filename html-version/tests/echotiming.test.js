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

test('v0.11: wall echo level is B(theta) once + spread + material; delay stays 2d/v', () => {
  const SoundData = require('../js/data/sounds.js');
  const A = SoundData.acoustics;
  const near = (a, b) => assert.ok(Math.abs(a - b) < 1e-9, a + ' vs ' + b);
  // Image-source wall: doubling the distance costs 20 log10(2) plus the extra air path.
  near(A.echoLevel('wall', 2, 0, 'stone') - A.echoLevel('wall', 4, 0, 'stone'), 20 * Math.log10(2) + 4 * A.airDbPerM);
  // Beam adds exactly B(theta) on top (no second cut).
  for (const deg of [0, 30, 60, 90, 120, 150, 180]) {
    const th = (deg * Math.PI) / 180;
    near(A.echoLevel('wall', 3, th, 'brick') - A.echoLevel('wall', 3, 0, 'brick'), A.beam(th));
  }
  // The delay does not depend on level, material or beam: round trip at the one sonar speed.
  for (const d of [1, 5, 10]) near(Sonar.echoDelay(d), (2 * d) / Sonar.SONAR_SPEED);
  for (const d of [0.5, 3, 10]) {
    const g = A.gameAmp(A.echoLevel('wall', d, 0, 'stone'));
    assert.ok(g >= A.gameMin && g <= 1);
  }
  assert.ok(A.gameAmp(A.echoLevel('wall', 2, 0, 'stone')) > A.gameAmp(A.echoLevel('wall', 2, Math.PI, 'stone')), 'behind is quieter');
  assert.ok(A.gameAmp(A.echoLevel('wall', 2, 0, 'stone')) > A.gameAmp(A.echoLevel('wall', 2, 0, 'grass')), 'grass is quieter than stone');
});
