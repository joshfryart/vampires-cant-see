'use strict';
const test = require('node:test');
const assert = require('node:assert');

globalThis.VCS = globalThis.VCS || {};
const SoundData = require('../js/data/sounds.js');
globalThis.VCS.SoundData = SoundData;
const Sonar = require('../js/sonar.js');
const A = SoundData.acoustics;

test('ceilingFor: known zones use their height and material, unknown the defaults', () => {
  assert.deepStrictEqual(A.ceilingFor('church'), { h: 8, mat: 'roughStone' });
  assert.deepStrictEqual(A.ceilingFor('tavern'), { h: 3.5, mat: 'wood' });
  assert.deepStrictEqual(A.ceilingFor('nowhere'), { h: A.ceil.defaultH, mat: A.ceil.defaultMat });
  assert.deepStrictEqual(A.ceilingFor(null), { h: A.ceil.defaultH, mat: A.ceil.defaultMat });
});

test('ceiling bounce: a tall church returns later and quieter than a low shed; wood is softer than stone', () => {
  assert.ok(A.ceilDelay(8) > A.ceilDelay(2.4));
  assert.ok(A.ceilLevel(8, 'stone') < A.ceilLevel(2.4, 'stone'));
  assert.ok(A.ceilLevel(3, 'wood') < A.ceilLevel(3, 'stone'));
  for (const h of [2.4, 2.5, 2.7, 3, 3.5, 4, 8]) assert.ok(Math.abs(A.ceilDelay(h) - A.floor.delay) >= A.ceil.minGap - 1e-9, 'ceiling clear of floor at h=' + h);
  assert.ok(A.ceilAmp(3, 'stone') > 0 && A.ceilAmp(3, 'stone') <= 1);
});

test('propAmp: nearer props are louder, far ones vanish', () => {
  assert.ok(A.propAmp(1.5, 0) > A.propAmp(3, 0));
  assert.strictEqual(A.propAmp(20, 0), 0);
});

test('wetFor: enclosed rooms send more reverb than open ground; absorbers and props shift it; always clamped', () => {
  const closed = A.wetFor(1, 0.03, 0, true);
  const open = A.wetFor(0, 0, 0, false);
  assert.ok(closed > 0.6 && closed < 1.2 && open < 0.3 && closed > open, 'a closed stone room is about the static send');
  assert.ok(A.wetFor(1, 0.6, 0, true) < closed, 'grass-like absorption lowers it');
  assert.ok(A.wetFor(0.5, 0.03, 6, true) > A.wetFor(0.5, 0.03, 0, true), 'props scatter more');
  assert.ok(A.wetFor(1, 0, 99, true) <= A.wet.max && A.wetFor(0, 1, 0, false) >= A.wet.min);
  assert.ok(A.wetFor(0.5, 0, 0, true) > A.wetFor(0.5, 0, 0, false), 'a ceiling closes the room');
});

test('Sonar.enclosure: counts rays that met a surface inside range and averages their absorption', () => {
  const n = 8;
  const pu = { range: 10, vis: new Float32Array([3, 3, 10, 10, 3, 3, 10, 10]), vnorm: new Uint8Array([0, 0, 255, 255, 0, 0, 255, 255]), vmat: new Uint8Array(n) };
  const e = Sonar.enclosure(pu);
  assert.strictEqual(e.hitFrac, 0.5);
  assert.strictEqual(e.meanAlpha, A.matOf(Sonar.MATS[0]).alpha);
  assert.deepStrictEqual(Sonar.enclosure(null), { hitFrac: 0, meanAlpha: 0 });
});
