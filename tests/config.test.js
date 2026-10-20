'use strict';

const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');

const ROOT = path.join(__dirname, '..');
const logPath = path.join(ROOT, 'js', 'log.js');
if (fs.existsSync(logPath)) require(logPath);
const Config = require(path.join(ROOT, 'js', 'config.js'));
const { DEFAULTS, sanitize, load, save } = Config;

/** Installs an in-memory localStorage stand-in on globalThis. @returns {object} */
function fakeStorage(initial) {
  const store = new Map(Object.entries(initial || {}));
  return {
    _store: store,
    getItem(k) { return store.has(k) ? store.get(k) : null; },
    setItem(k, v) { store.set(k, String(v)); },
    removeItem(k) { store.delete(k); }
  };
}

function setStorage(value) {
  Object.defineProperty(globalThis, 'localStorage', { value, configurable: true, writable: true });
}

function clearStorage() {
  delete globalThis.localStorage;
}

/** Replaces VCS.Log with a capturing fake; returns the captured calls and a restore fn. */
function captureLog() {
  const calls = [];
  const logger = {};
  for (const level of ['debug', 'info', 'warn', 'error']) {
    logger[level] = (msg) => calls.push({ level, msg: String(msg) });
  }
  const VCS = globalThis.VCS;
  const prev = VCS.Log;
  VCS.Log = { get: () => logger };
  return {
    calls,
    warnings: () => calls.filter((c) => c.level === 'warn').map((c) => c.msg),
    restore() {
      if (prev === undefined) delete VCS.Log;
      else VCS.Log = prev;
    }
  };
}

test('DEFAULTS is frozen and has the contract values', () => {
  assert.ok(Object.isFrozen(DEFAULTS));
  assert.deepStrictEqual(Object.assign({}, DEFAULTS), {
    mouseSensitivity: 0.0025,
    invertMouse: false,
    moveSpeed: 3.0,
    turnSpeedKeys: 2.4,
    renderScale: 1.0,
    volume: 0.7,
    nightLengthMin: 4,
    cfgV: 2,
    showFps: false,
    fovDeg: 66,
    sonarSpeed: 12,
    sonarRange: 10,
    sonarFade: 3,
    sonarCooldown: 0.8,
    headBob: true,
    lineBoil: true,
    transitionMs: 700,
    materialDetail: true,
    maxMapW: 64,
    maxMapH: 48,
    feedReach: 1.5,
    feedArcDeg: 60,
    poolMin: 30,
    poolMax: 50,
    dazedTime: 3,
    autosaveSec: 20,
    keyTurnSpeed: 3.2,
    dragLook: true,
    feedToggle: false,
    reduceMotion: false,
    largeText: false,
    ambienceGain: 0.6,
    devButton: true
  });
});

test('sanitize range-checks fovDeg (50 to 100 degrees)', () => {
  assert.deepStrictEqual(sanitize({ fovDeg: 50 }).config.fovDeg, 50);
  const high = sanitize({ fovDeg: 101 });
  assert.strictEqual(high.config.fovDeg, DEFAULTS.fovDeg);
  assert.strictEqual(high.warnings.length, 1);
  assert.match(high.warnings[0], /fovDeg/);
  assert.strictEqual(sanitize({ fovDeg: '66' }).config.fovDeg, DEFAULTS.fovDeg);
});

test('sanitize returns defaults with one warning for non-object input', () => {
  for (const input of [null, undefined, 5, 'text', true, [1, 2]]) {
    const r = sanitize(input);
    assert.deepStrictEqual(r.config, Object.assign({}, DEFAULTS));
    assert.strictEqual(r.warnings.length, 1);
  }
});

test('sanitize warns on unknown keys and ignores them', () => {
  const r = sanitize({ foo: 1, moveSpeed: 4 });
  assert.strictEqual(r.warnings.length, 1);
  assert.match(r.warnings[0], /foo/);
  assert.strictEqual(r.config.moveSpeed, 4);
  assert.strictEqual(r.config.foo, undefined);
});

test('sanitize warns on wrong types and keeps defaults', () => {
  const r = sanitize({ invertMouse: 'yes', moveSpeed: '3' });
  assert.strictEqual(r.warnings.length, 2);
  assert.strictEqual(r.config.invertMouse, false);
  assert.strictEqual(r.config.moveSpeed, 3.0);
});

test('sanitize warns on out-of-range numbers and keeps defaults', () => {
  const r = sanitize({ moveSpeed: 9, volume: -0.1, renderScale: 0.1, nightLengthMin: 1 });
  assert.strictEqual(r.warnings.length, 4);
  assert.strictEqual(r.config.moveSpeed, DEFAULTS.moveSpeed);
  assert.strictEqual(r.config.volume, DEFAULTS.volume);
  assert.strictEqual(r.config.renderScale, DEFAULTS.renderScale);
  assert.strictEqual(r.config.nightLengthMin, DEFAULTS.nightLengthMin);
});

test('sanitize rejects NaN and Infinity for numbers', () => {
  const r = sanitize({ moveSpeed: NaN, volume: Infinity });
  assert.strictEqual(r.warnings.length, 2);
  assert.strictEqual(r.config.moveSpeed, DEFAULTS.moveSpeed);
  assert.strictEqual(r.config.volume, DEFAULTS.volume);
});

test('sanitize rejects __proto__ key without polluting Object.prototype', () => {
  const r = sanitize(JSON.parse('{"__proto__":{"x":1}}'));
  assert.ok(r.warnings.length >= 1);
  assert.strictEqual(({}).x, undefined);
  assert.strictEqual(Object.prototype.x, undefined);
  assert.strictEqual(Object.getPrototypeOf(r.config), Object.prototype);
  assert.strictEqual(Object.prototype.hasOwnProperty.call(r.config, '__proto__'), false);
});

test('sanitize rejects constructor and prototype keys', () => {
  const r = sanitize(JSON.parse('{"constructor":{"prototype":{"polluted":true}},"prototype":{"y":2}}'));
  assert.strictEqual(r.warnings.length, 2);
  assert.strictEqual(Object.prototype.hasOwnProperty.call(r.config, 'constructor'), false);
  assert.strictEqual(Object.prototype.hasOwnProperty.call(r.config, 'prototype'), false);
  assert.strictEqual(({}).polluted, undefined);
  assert.strictEqual(Object.prototype.polluted, undefined);
});

test('sanitize keeps valid values, including range bounds', () => {
  const input = {
    mouseSensitivity: 0.004,
    invertMouse: true,
    moveSpeed: 4,
    turnSpeedKeys: 0.5,
    renderScale: 0.25,
    volume: 0,
    nightLengthMin: 30,
    cfgV: 2,
    showFps: true,
    fovDeg: 50,
    sonarSpeed: 30,
    sonarRange: 4,
    sonarFade: 8,
    sonarCooldown: 0.2,
    headBob: false,
    lineBoil: false,
    transitionMs: 2000,
    materialDetail: false,
    maxMapW: 64,
    maxMapH: 48,
    feedReach: 3,
    feedArcDeg: 20,
    poolMin: 5,
    poolMax: 150,
    dazedTime: 0.5,
    autosaveSec: 300,
    keyTurnSpeed: 6,
    dragLook: false,
    feedToggle: true,
    reduceMotion: true,
    largeText: true,
    ambienceGain: 1,
    devButton: false
  };
  const r = sanitize(input);
  assert.deepStrictEqual(r.warnings, []);
  assert.deepStrictEqual(r.config, input);
  const max = sanitize({ mouseSensitivity: 0.01, moveSpeed: 6, turnSpeedKeys: 5, renderScale: 1, volume: 1, nightLengthMin: 2 });
  assert.deepStrictEqual(max.warnings, []);
});

test('sanitize never throws on hostile getters', () => {
  const evil = {};
  Object.defineProperty(evil, 'moveSpeed', { enumerable: true, get() { throw new Error('boom'); } });
  const r = sanitize(evil);
  assert.deepStrictEqual(r.config, Object.assign({}, DEFAULTS));
  assert.ok(r.warnings.length >= 1);
});

test('sanitize works with no VCS.Log present', () => {
  const VCS = globalThis.VCS;
  const prev = VCS.Log;
  delete VCS.Log;
  try {
    assert.doesNotThrow(() => sanitize({ foo: 1 }));
    assert.doesNotThrow(() => load());
  } finally {
    if (prev !== undefined) VCS.Log = prev;
  }
});

test('load returns defaults when nothing is saved', () => {
  const cap = captureLog();
  setStorage(fakeStorage());
  try {
    assert.deepStrictEqual(load(), Object.assign({}, DEFAULTS));
    assert.deepStrictEqual(cap.warnings(), []);
  } finally {
    cap.restore();
    clearStorage();
  }
});

test('load applies valid saved settings', () => {
  const cap = captureLog();
  setStorage(fakeStorage({ 'vcs.settings': JSON.stringify({ moveSpeed: 5, invertMouse: true }) }));
  try {
    const c = load();
    assert.strictEqual(c.moveSpeed, 5);
    assert.strictEqual(c.invertMouse, true);
    assert.strictEqual(c.volume, DEFAULTS.volume);
    assert.deepStrictEqual(cap.warnings(), []);
  } finally {
    cap.restore();
    clearStorage();
  }
});

test('load falls back to defaults and warns on corrupt JSON', () => {
  const cap = captureLog();
  setStorage(fakeStorage({ 'vcs.settings': '{nope' }));
  try {
    assert.deepStrictEqual(load(), Object.assign({}, DEFAULTS));
    assert.strictEqual(cap.warnings().length, 1);
  } finally {
    cap.restore();
    clearStorage();
  }
});

test('load rejects oversize saved string and warns', () => {
  const cap = captureLog();
  const big = JSON.stringify({ moveSpeed: 4, pad: 'x'.repeat(16 * 1024) });
  assert.ok(big.length > 16 * 1024);
  setStorage(fakeStorage({ 'vcs.settings': big }));
  try {
    assert.deepStrictEqual(load(), Object.assign({}, DEFAULTS));
    assert.strictEqual(cap.warnings().length, 1);
    assert.match(cap.warnings()[0], /too large/);
  } finally {
    cap.restore();
    clearStorage();
  }
});

test('load returns defaults when getItem throws', () => {
  const cap = captureLog();
  setStorage({ getItem() { throw new Error('blocked'); }, setItem() { throw new Error('blocked'); } });
  try {
    assert.deepStrictEqual(load(), Object.assign({}, DEFAULTS));
    assert.strictEqual(cap.warnings().length, 1);
  } finally {
    cap.restore();
    clearStorage();
  }
});

test('load returns defaults when localStorage is missing', () => {
  clearStorage();
  assert.deepStrictEqual(load(), Object.assign({}, DEFAULTS));
});

test('load in safeMode returns defaults even when settings are saved', () => {
  const cap = captureLog();
  const storage = fakeStorage({ 'vcs.settings': JSON.stringify({ moveSpeed: 5 }) });
  setStorage(storage);
  try {
    assert.deepStrictEqual(load({ safeMode: true }), Object.assign({}, DEFAULTS));
    assert.ok(cap.calls.some((c) => c.level === 'info'));
  } finally {
    cap.restore();
    clearStorage();
  }
});

test('save then load round-trips the settings', () => {
  const storage = fakeStorage();
  setStorage(storage);
  try {
    const cfg = Object.assign({}, DEFAULTS, { moveSpeed: 4.5, invertMouse: true, showFps: true });
    assert.strictEqual(save(cfg), true);
    assert.ok(storage._store.has('vcs.settings'));
    assert.deepStrictEqual(load(), cfg);
  } finally {
    clearStorage();
  }
});

test('save sanitizes what it writes', () => {
  const cap = captureLog();
  const storage = fakeStorage();
  setStorage(storage);
  try {
    assert.strictEqual(save({ moveSpeed: 99, junk: true }), true);
    const stored = JSON.parse(storage._store.get('vcs.settings'));
    assert.strictEqual(stored.moveSpeed, DEFAULTS.moveSpeed);
    assert.strictEqual(stored.junk, undefined);
    assert.ok(cap.warnings().length >= 2);
  } finally {
    cap.restore();
    clearStorage();
  }
});

test('save returns false when setItem throws', () => {
  const cap = captureLog();
  setStorage({ getItem() { return null; }, setItem() { throw new Error('full'); } });
  try {
    assert.strictEqual(save(Object.assign({}, DEFAULTS)), false);
    assert.ok(cap.calls.some((c) => c.level === 'error'));
  } finally {
    cap.restore();
    clearStorage();
  }
});

test('save returns false when storage is missing', () => {
  const cap = captureLog();
  clearStorage();
  try {
    assert.strictEqual(save(Object.assign({}, DEFAULTS)), false);
  } finally {
    cap.restore();
  }
});

test('headBob defaults to true and must be boolean', () => {
  assert.strictEqual(DEFAULTS.headBob, true);
  assert.strictEqual(sanitize({ headBob: false }).config.headBob, false);
  const bad = sanitize({ headBob: 'yes' });
  assert.strictEqual(bad.config.headBob, true);
  assert.match(bad.warnings[0], /headBob/);
});

test('lineBoil defaults to true and must be boolean', () => {
  assert.strictEqual(DEFAULTS.lineBoil, true);
  assert.strictEqual(sanitize({ lineBoil: false }).config.lineBoil, false);
  const bad = sanitize({ lineBoil: 'yes' });
  assert.strictEqual(bad.config.lineBoil, true);
  assert.match(bad.warnings[0], /lineBoil/);
});

test('feeding settings are range-checked', () => {
  assert.strictEqual(DEFAULTS.feedReach, 1.5);
  assert.strictEqual(sanitize({ feedReach: 3 }).warnings.length, 0);
  const bad = sanitize({ feedReach: 0.5, feedArcDeg: 121, poolMin: 4, poolMax: 151, dazedTime: 0.1 });
  assert.strictEqual(bad.warnings.length, 5);
  assert.strictEqual(bad.config.feedArcDeg, 60);
  assert.strictEqual(bad.config.poolMax, 50);
  assert.strictEqual(sanitize({ dazedTime: '3' }).config.dazedTime, 3);
});

test('autosaveSec is range-checked (5..300)', () => {
  assert.strictEqual(DEFAULTS.autosaveSec, 20);
  assert.strictEqual(sanitize({ autosaveSec: 5 }).warnings.length, 0);
  assert.strictEqual(sanitize({ autosaveSec: 300 }).warnings.length, 0);
  const bad = sanitize({ autosaveSec: 4 });
  assert.strictEqual(bad.warnings.length, 1);
  assert.strictEqual(bad.config.autosaveSec, 20);
  assert.strictEqual(sanitize({ autosaveSec: 301 }).config.autosaveSec, 20);
});

test('load migrates old settings without cfgV: night length reset to 4, saved with cfgV 2', () => {
  const storage = fakeStorage();
  setStorage(storage);
  try {
    storage.setItem('vcs.settings', JSON.stringify({ nightLengthMin: 8, volume: 0.3 }));
    const c = load();
    assert.strictEqual(DEFAULTS.nightLengthMin, 4);
    assert.strictEqual(c.nightLengthMin, 4);
    assert.strictEqual(c.volume, 0.3);
    assert.strictEqual(c.cfgV, 2);
    assert.strictEqual(JSON.parse(storage._store.get('vcs.settings')).cfgV, 2);
    assert.strictEqual(JSON.parse(storage._store.get('vcs.settings')).nightLengthMin, 4);
  } finally {
    clearStorage();
  }
});

test('load keeps a chosen night length once cfgV is 2', () => {
  const storage = fakeStorage();
  setStorage(storage);
  try {
    storage.setItem('vcs.settings', JSON.stringify({ nightLengthMin: 10, cfgV: 2 }));
    assert.strictEqual(load().nightLengthMin, 10);
  } finally {
    clearStorage();
  }
});

test('keyTurnSpeed, dragLook, feedToggle defaults and ranges', () => {
  assert.strictEqual(DEFAULTS.keyTurnSpeed, 3.2);
  assert.strictEqual(DEFAULTS.dragLook, true);
  assert.strictEqual(DEFAULTS.feedToggle, false);
  assert.strictEqual(sanitize({ keyTurnSpeed: 1 }).config.keyTurnSpeed, 1);
  assert.strictEqual(sanitize({ keyTurnSpeed: 6 }).config.keyTurnSpeed, 6);
  const bad = sanitize({ keyTurnSpeed: 7, dragLook: 'yes', feedToggle: 1 });
  assert.strictEqual(bad.config.keyTurnSpeed, 3.2);
  assert.strictEqual(bad.config.dragLook, true);
  assert.strictEqual(bad.config.feedToggle, false);
  assert.strictEqual(bad.warnings.length, 3);
  assert.strictEqual(sanitize({ feedToggle: true }).config.feedToggle, true);
});

test('ambienceGain defaults to 0.6 and is range checked 0..1', () => {
  assert.strictEqual(Config.DEFAULTS.ambienceGain, 0.6);
  assert.deepStrictEqual(sanitize({ ambienceGain: 0 }).warnings, []);
  assert.strictEqual(sanitize({ ambienceGain: 0 }).config.ambienceGain, 0);
  const hi = sanitize({ ambienceGain: 1.5 });
  assert.strictEqual(hi.config.ambienceGain, 0.6);
  assert.strictEqual(hi.warnings.length, 1);
  assert.strictEqual(sanitize({ ambienceGain: 'loud' }).config.ambienceGain, 0.6);
});
