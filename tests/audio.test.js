'use strict';
// Merged test file: each source file's tests live in their own describe().
const { describe } = require('node:test');

describe('audio.test.js', () => {

  const test = require('node:test');
  const assert = require('node:assert');
  const fs = require('node:fs');
  const path = require('node:path');
  const { afterEach, beforeEach } = require('node:test');

  const ROOT = path.join(__dirname, '..');
  const logPath = path.join(ROOT, 'js', 'log.js');
  if (fs.existsSync(logPath)) require(logPath);
  const Audio = require(path.join(ROOT, 'js', 'audio.js'));

  // ---- fake Web Audio ---------------------------------------------------------

  class FakeParam {
    constructor(value) {
      this.value = value;
      this.events = [];
    }
    setValueAtTime(v, t) { this.events.push({ type: 'set', v, t }); return this; }
    linearRampToValueAtTime(v, t) { this.events.push({ type: 'linear', v, t }); return this; }
    exponentialRampToValueAtTime(v, t) { this.events.push({ type: 'exp', v, t }); return this; }
  }

  class FakeNode {
    constructor(kind) {
      this.kind = kind;
      this.outputs = [];
    }
    connect(dest) { this.outputs.push(dest); return dest; }
  }

  class FakeOscillator extends FakeNode {
    constructor() {
      super('oscillator');
      this.type = 'sine';
      this.frequency = new FakeParam(440);
      this.started = [];
      this.stopped = [];
    }
    start(t) { this.started.push(t); }
    stop(t) { this.stopped.push(t); }
  }

  class FakeGain extends FakeNode {
    constructor() {
      super('gain');
      this.gain = new FakeParam(1);
    }
  }

  class FakeFilter extends FakeNode {
    constructor() {
      super('biquadFilter');
      this.type = 'allpass';
      this.frequency = new FakeParam(350);
    }
  }

  /** Builds a fake AudioContext class that records every node it creates. */
  function makeFakeContext(opts) {
    const options = opts || {};
    const instances = [];
    class FakeAudioContext {
      constructor() {
        this.currentTime = 1.5;
        this.state = 'suspended';
        this.destination = new FakeNode('destination');
        this.oscillators = [];
        this.gains = [];
        this.filters = [];
        this.resumeCalls = 0;
        instances.push(this);
      }
      resume() {
        this.resumeCalls += 1;
        this.state = 'running';
        return Promise.resolve();
      }
      createOscillator() {
        if (options.throwOnOscillator) throw new Error('oscillator refused');
        const node = new FakeOscillator();
        this.oscillators.push(node);
        return node;
      }
      createGain() {
        const node = new FakeGain();
        this.gains.push(node);
        return node;
      }
      createStereoPanner() {
        if (options.noPanner) return undefined;
        const node = new FakeNode('stereoPanner');
        node.pan = new FakeParam(0);
        this.panners = this.panners || [];
        this.panners.push(node);
        return node;
      }
      createBiquadFilter() {
        const node = new FakeFilter();
        this.filters.push(node);
        return node;
      }
    }
    return { FakeAudioContext, instances };
  }

  /** Returns the peak gain (value of the linear attack ramp) recorded on a fake gain node. */
  function peakOf(gainNode) {
    const ramp = gainNode.gain.events.find((e) => e.type === 'linear');
    return ramp ? ramp.v : undefined;
  }

  // ---- global isolation -------------------------------------------------------

  const GLOBAL_NAMES = ['AudioContext', 'webkitAudioContext'];
  const savedGlobals = {};
  for (const name of GLOBAL_NAMES) {
    savedGlobals[name] = Object.getOwnPropertyDescriptor(globalThis, name);
  }

  function setGlobal(name, value) {
    Object.defineProperty(globalThis, name, { value, configurable: true, writable: true });
  }

  beforeEach(() => {
    for (const name of GLOBAL_NAMES) delete globalThis[name];
  });

  afterEach(() => {
    for (const name of GLOBAL_NAMES) {
      delete globalThis[name];
      if (savedGlobals[name]) Object.defineProperty(globalThis, name, savedGlobals[name]);
    }
  });

  // ---- tests ------------------------------------------------------------------

  test('create() makes no AudioContext and ping before unlock does nothing', () => {
    const { FakeAudioContext, instances } = makeFakeContext();
    setGlobal('AudioContext', FakeAudioContext);
    const a = Audio.create({ volume: 0.7 });
    assert.strictEqual(a.ok, true);
    assert.strictEqual(a.ctx, null);
    assert.strictEqual(instances.length, 0);
    assert.doesNotThrow(() => Audio.ping(a));
    assert.strictEqual(instances.length, 0);
  });

  test('unlock() creates one AudioContext and is safe to call again', () => {
    const { FakeAudioContext, instances } = makeFakeContext();
    setGlobal('AudioContext', FakeAudioContext);
    const a = Audio.create();
    Audio.unlock(a);
    assert.ok(a.ctx instanceof FakeAudioContext);
    assert.strictEqual(instances.length, 1);
    assert.strictEqual(a.ctx.resumeCalls, 1);
    assert.strictEqual(a.ctx.state, 'running');
    Audio.unlock(a);
    Audio.unlock(a);
    assert.strictEqual(instances.length, 1);
  });

  test('unlock() falls back to webkitAudioContext', () => {
    const { FakeAudioContext, instances } = makeFakeContext();
    setGlobal('webkitAudioContext', FakeAudioContext);
    const a = Audio.create();
    Audio.unlock(a);
    assert.strictEqual(instances.length, 1);
    assert.strictEqual(a.ok, true);
  });

  test('ping creates an oscillator and a gain wired to the destination', () => {
    const { FakeAudioContext } = makeFakeContext();
    setGlobal('AudioContext', FakeAudioContext);
    const a = Audio.create({ pingBip: true }); // the old bip is the pingBip setting
    Audio.unlock(a);
    Audio.ping(a);
    const ctx = a.ctx;
    assert.strictEqual(ctx.oscillators.length, 1);
    assert.strictEqual(ctx.gains.length, 1);
    const osc = ctx.oscillators[0];
    const gain = ctx.gains[0];
    assert.deepStrictEqual(osc.outputs, [gain]);
    assert.deepStrictEqual(gain.outputs, [ctx.destination]);
    assert.strictEqual(osc.started.length, 1);
    assert.strictEqual(osc.started[0], ctx.currentTime);
    assert.ok(Math.abs(osc.frequency.events[0].v / 1800 - 1) <= 0.021, 'tiny pitch wobble');
    assert.ok(Math.abs(osc.frequency.events[1].v / 1100 - 1) <= 0.021);
    assert.ok(osc.stopped[0] - ctx.currentTime <= 0.15, 'short bip');
    assert.ok(Math.abs(peakOf(gain) - 0.7 * 0.35) < 1e-9);
  });

  test('echo with delay above 6 seconds does nothing', () => {
    const { FakeAudioContext } = makeFakeContext();
    setGlobal('AudioContext', FakeAudioContext);
    const a = Audio.create();
    Audio.unlock(a);
    Audio.echo(a, 6.5, 1);
    Audio.echo(a, Infinity, 1);
    Audio.echo(a, -0.1, 1);
    Audio.echo(a, NaN, 1);
    assert.strictEqual(a.ctx.oscillators.length, 0);
    assert.strictEqual(a.ctx.gains.length, 0);
    assert.strictEqual(a.ctx.filters.length, 0);
  });

  test('echo creates a lowpass filter and an oscillator delayed by delaySec', () => {
    const { FakeAudioContext } = makeFakeContext();
    setGlobal('AudioContext', FakeAudioContext);
    const a = Audio.create();
    Audio.unlock(a);
    Audio.echo(a, 0.5, 0.5);
    const ctx = a.ctx;
    assert.strictEqual(ctx.filters.length, 1);
    const filter = ctx.filters[0];
    assert.strictEqual(filter.type, 'lowpass');
    assert.strictEqual(filter.frequency.value, 2200);
    assert.deepStrictEqual(filter.outputs, [ctx.destination]);
    assert.strictEqual(ctx.oscillators.length, 1);
    assert.strictEqual(ctx.oscillators[0].started[0], ctx.currentTime + 0.5);
    assert.deepStrictEqual(ctx.gains[0].outputs, [filter]);
    assert.ok(Math.abs(peakOf(ctx.gains[0]) - 0.7 * 0.35 * 0.5) < 1e-9);
  });

  test('every public method is a no-op without AudioContext', () => {
    const a = Audio.create();
    assert.doesNotThrow(() => Audio.unlock(a));
    assert.strictEqual(a.ok, false);
    assert.strictEqual(a.ctx, null);
    assert.doesNotThrow(() => Audio.ping(a));
    assert.doesNotThrow(() => Audio.echo(a, 0.5, 1));
    assert.doesNotThrow(() => Audio.setVolume(a, 0.3));
    assert.strictEqual(a.ctx, null);
    assert.strictEqual(a.volume, 0.3);
  });

  test('no method throws on null or missing state', () => {
    assert.doesNotThrow(() => Audio.unlock(null));
    assert.doesNotThrow(() => Audio.ping(null));
    assert.doesNotThrow(() => Audio.ping(undefined));
    assert.doesNotThrow(() => Audio.echo(null, 0.1, 1));
    assert.doesNotThrow(() => Audio.setVolume(null, 0.5));
  });

  test('ping does not throw when createOscillator throws', () => {
    const { FakeAudioContext } = makeFakeContext({ throwOnOscillator: true });
    setGlobal('AudioContext', FakeAudioContext);
    const a = Audio.create();
    Audio.unlock(a);
    assert.strictEqual(a.ok, true);
    assert.doesNotThrow(() => Audio.ping(a));
    assert.doesNotThrow(() => Audio.echo(a, 0.2, 1));
    assert.doesNotThrow(() => Audio.ping(a));
  });

  test('unlock does not throw when the AudioContext constructor throws', () => {
    class BrokenAudioContext {
      constructor() { throw new Error('blocked by policy'); }
    }
    setGlobal('AudioContext', BrokenAudioContext);
    const a = Audio.create();
    assert.doesNotThrow(() => Audio.unlock(a));
    assert.strictEqual(a.ok, false);
    assert.strictEqual(a.ctx, null);
  });

  test('setVolume clamps to 0..1 and scales the next ping', () => {
    const { FakeAudioContext } = makeFakeContext();
    setGlobal('AudioContext', FakeAudioContext);
    const a = Audio.create({ pingBip: true });
    Audio.unlock(a);

    Audio.setVolume(a, 2);
    assert.strictEqual(a.volume, 1);
    Audio.ping(a);
    assert.ok(Math.abs(peakOf(a.ctx.gains[0]) - 0.35) < 1e-9);

    Audio.setVolume(a, -3);
    assert.strictEqual(a.volume, 0);
    Audio.ping(a);
    assert.strictEqual(peakOf(a.ctx.gains[1]), 0);

    Audio.setVolume(a, NaN);
    assert.strictEqual(a.volume, 0);
  });

  test('create() reads and clamps config.volume', () => {
    assert.strictEqual(Audio.create({ volume: 0.4 }).volume, 0.4);
    assert.strictEqual(Audio.create({ volume: 9 }).volume, 1);
    assert.strictEqual(Audio.create({ volume: 'loud' }).volume, 0.7);
    assert.strictEqual(Audio.create().volume, 0.7);
  });

  test('echo with pan routes the filter through a clamped StereoPanner', () => {
    const { FakeAudioContext } = makeFakeContext();
    setGlobal('AudioContext', FakeAudioContext);
    const a = Audio.create();
    Audio.unlock(a);
    Audio.echo(a, 0.2, 0.5, -0.6);
    Audio.echo(a, 0.2, 0.5, 5);
    const ctx = a.ctx;
    assert.strictEqual(ctx.panners.length, 2);
    assert.strictEqual(ctx.panners[0].pan.value, -0.6);
    assert.strictEqual(ctx.panners[1].pan.value, 1);
    assert.deepStrictEqual(ctx.filters[0].outputs, [ctx.panners[0]]);
    assert.deepStrictEqual(ctx.panners[0].outputs, [ctx.destination]);
  });

  test('echo without pan or without StereoPanner support still plays', () => {
    const { FakeAudioContext } = makeFakeContext();
    setGlobal('AudioContext', FakeAudioContext);
    const a = Audio.create();
    Audio.unlock(a);
    Audio.echo(a, 0.2, 0.5);
    assert.strictEqual(a.ctx.panners, undefined);
    assert.deepStrictEqual(a.ctx.filters[0].outputs, [a.ctx.destination]);

    const none = makeFakeContext({ noPanner: true });
    setGlobal('AudioContext', none.FakeAudioContext);
    const b = Audio.create();
    Audio.unlock(b);
    assert.doesNotThrow(() => Audio.echo(b, 0.2, 0.5, 0.7));
    assert.deepStrictEqual(b.ctx.filters[0].outputs, [b.ctx.destination]);
    assert.strictEqual(b.ctx.oscillators.length, 1);
  });

  test('echo works when the context lacks createStereoPanner entirely', () => {
    const { FakeAudioContext } = makeFakeContext();
    FakeAudioContext.prototype.createStereoPanner = undefined;
    setGlobal('AudioContext', FakeAudioContext);
    const a = Audio.create();
    Audio.unlock(a);
    assert.doesNotThrow(() => Audio.echo(a, 0.2, 0.5, 0.7));
    assert.strictEqual(a.ctx.oscillators.length, 1);
  });

  test('step plays a very quiet short low tick', () => {
    const { FakeAudioContext } = makeFakeContext();
    setGlobal('AudioContext', FakeAudioContext);
    const a = Audio.create();
    Audio.unlock(a);
    Audio.step(a);
    const ctx = a.ctx;
    assert.strictEqual(ctx.oscillators.length, 1);
    assert.strictEqual(ctx.oscillators[0].frequency.events[0].v, 120);
    assert.ok(Math.abs(peakOf(ctx.gains[0]) - 0.7 * 0.08) < 1e-9);
    assert.ok(ctx.oscillators[0].stopped[0] - ctx.currentTime <= 0.05);
    assert.deepStrictEqual(ctx.gains[0].outputs, [ctx.destination]);
  });

  test('step is a no-op before unlock, without audio, or when nodes throw', () => {
    assert.doesNotThrow(() => Audio.step(null));
    const a = Audio.create();
    assert.doesNotThrow(() => Audio.step(a));
    const { FakeAudioContext } = makeFakeContext({ throwOnOscillator: true });
    setGlobal('AudioContext', FakeAudioContext);
    const b = Audio.create();
    Audio.unlock(b);
    assert.doesNotThrow(() => Audio.step(b));
  });

  test('play() makes distinct sounds per kind and ignores unknown kinds', () => {
    const { FakeAudioContext } = makeFakeContext();
    setGlobal('AudioContext', FakeAudioContext);
    const counts = {};
    for (const kind of ['step', 'personStep', 'doorOpen', 'doorClose', 'interact']) {
      const a = Audio.create();
      Audio.unlock(a);
      Audio.play(a, kind, { gain: 0.1 });
      counts[kind] = a.ctx.oscillators.length;
      assert.ok(a.ctx.oscillators.length >= 1, kind + ' creates an oscillator');
      assert.ok(a.ctx.oscillators.every((o) => o.started.length === 1 && o.stopped.length === 1));
    }
    assert.strictEqual(counts.interact, 2);
    assert.strictEqual(counts.doorOpen, 2);
    const a = Audio.create();
    Audio.unlock(a);
    Audio.play(a, 'bogus');
    Audio.play(a, '__proto__');
    assert.strictEqual(a.ctx.oscillators.length, 0);
  });

  test('play() applies gain, pan and delay; doorOpen uses a band-pass sweep', () => {
    const { FakeAudioContext } = makeFakeContext();
    setGlobal('AudioContext', FakeAudioContext);
    const a = Audio.create();
    Audio.unlock(a);
    Audio.play(a, 'step', { gain: 0.1, pan: 5, delay: 0.5 });
    const ctx = a.ctx;
    assert.strictEqual(ctx.panners[0].pan.value, 1);
    assert.ok(Math.abs(ctx.oscillators[0].started[0] - (ctx.currentTime + 0.5)) < 1e-9);
    assert.ok(Math.abs(peakOf(ctx.gains[1]) - 0.07) < 1e-9);
    Audio.play(a, 'doorOpen');
    assert.strictEqual(ctx.filters[0].type, 'bandpass');
    const before = ctx.oscillators.length;
    Audio.play(a, 'step', { delay: 7 });
    Audio.play(a, 'step', { gain: 0 });
    assert.strictEqual(ctx.oscillators.length, before);
  });

  test('play() is safe with no audio, null state, or throwing nodes', () => {
    assert.doesNotThrow(() => Audio.play(null, 'step'));
    assert.doesNotThrow(() => Audio.play(Audio.create(), 'step'));
    const { FakeAudioContext } = makeFakeContext({ throwOnOscillator: true });
    setGlobal('AudioContext', FakeAudioContext);
    const b = Audio.create();
    Audio.unlock(b);
    for (const k of ['step', 'personStep', 'doorOpen', 'doorClose', 'interact']) {
      assert.doesNotThrow(() => Audio.play(b, k));
    }
  });

  test('step pitch varies within +-8% and feet alternate left/right', () => {
    const { FakeAudioContext } = makeFakeContext();
    setGlobal('AudioContext', FakeAudioContext);
    const a = Audio.create();
    Audio.unlock(a);
    const seq = [0, 1, 0.5, 0.25];
    let i = 0;
    a.rand = () => seq[i++ % seq.length];
    for (let n = 0; n < 4; n++) Audio.play(a, 'step', { gain: 0.1 });
    const osc = a.ctx.oscillators.filter((o, k) => k % 3 === 0); // fundamental of each step; 2x/3x partials follow
    assert.strictEqual(a.ctx.oscillators.length, 12);
    const f = osc.map((o) => o.frequency.events[0].v);
    for (const v of f) assert.ok(v >= 110 * 0.92 - 1e-9 && v <= 110 * 1.14 * 1.08 + 1e-9, 'freq ' + v);
    assert.strictEqual(osc[0].type, 'sine');
    assert.strictEqual(osc[1].type, 'triangle');
    assert.strictEqual(osc[2].type, 'sine');
    assert.strictEqual(osc[3].type, 'triangle');
    assert.notStrictEqual(f[0], f[2]);
  });

  test('door creak bends pitch up and back; interact is a short hollow tok', () => {
    const { FakeAudioContext } = makeFakeContext();
    setGlobal('AudioContext', FakeAudioContext);
    const a = Audio.create();
    Audio.unlock(a);
    Audio.play(a, 'doorOpen');
    const ev = a.ctx.oscillators[0].frequency.events;
    assert.ok(ev.length >= 4);
    assert.ok(ev[1].v > ev[0].v && ev[2].v < ev[1].v, 'up then down');
    const b = Audio.create();
    Audio.unlock(b);
    Audio.play(b, 'interact');
    assert.ok(b.ctx.oscillators.every((o) => o.stopped[0] - b.ctx.currentTime <= 0.1));
    assert.ok(b.ctx.oscillators[0].frequency.events[1].v < b.ctx.oscillators[0].frequency.events[0].v);
  });

});

describe('audio-kinds.test.js', () => {

  const test = require('node:test');
  const assert = require('node:assert');

  // Fake Web Audio: records how many oscillators were created so tests can see scheduling.
  const made = { osc: 0 };

  function param(value) {
    return {
      value: value === undefined ? 0 : value,
      setValueAtTime() {},
      linearRampToValueAtTime() {},
      exponentialRampToValueAtTime() {},
      cancelScheduledValues() {}
    };
  }

  function node(extra) {
    return Object.assign({ connect() {}, disconnect() {} }, extra || {});
  }

  class FakeAudioContext {
    constructor() {
      this.currentTime = 0;
      this.state = 'running';
      this.destination = node();
    }
    createOscillator() {
      made.osc++;
      return node({ type: 'sine', frequency: param(0), start() {}, stop() {} });
    }
    createGain() {
      return node({ gain: param(1) });
    }
    createBiquadFilter() {
      return node({ type: 'lowpass', frequency: param(0) });
    }
    createStereoPanner() {
      return node({ pan: param(0) });
    }
  }

  require('node:test').before(() => { globalThis.AudioContext = FakeAudioContext; });
  require('node:test').after(() => { delete globalThis.AudioContext; });

  const Audio = require('../js/audio.js');

  function freshState() {
    return Audio.create({ volume: 0.7 });
  }

  test('play before unlock does nothing and never throws', () => {
    const a = freshState();
    made.osc = 0;
    for (const kind of ['chime', 'heartbeat', 'feed', 'yawn']) {
      assert.doesNotThrow(() => Audio.play(a, kind));
    }
    assert.strictEqual(made.osc, 0);
    assert.strictEqual(a.ctx, null);
  });

  test('play with a missing state never throws', () => {
    assert.doesNotThrow(() => Audio.play(null, 'chime'));
    assert.doesNotThrow(() => Audio.play(undefined, 'feed'));
  });

  test('each new kind schedules oscillators after unlock', () => {
    const a = freshState();
    Audio.unlock(a);
    assert.ok(a.ctx, 'context created');
    for (const kind of ['chime', 'heartbeat', 'feed', 'yawn']) {
      made.osc = 0;
      assert.doesNotThrow(() => Audio.play(a, kind));
      assert.ok(made.osc > 0, kind + ' should create at least one oscillator');
    }
  });

  test('chime and heartbeat schedule two tones each', () => {
    const a = freshState();
    Audio.unlock(a);
    made.osc = 0;
    Audio.play(a, 'chime');
    assert.strictEqual(made.osc, 2);
    made.osc = 0;
    Audio.play(a, 'heartbeat');
    assert.strictEqual(made.osc, 6); // two beats x (fundamental + 2x + 3x)
  });

  test('feed and yawn schedule one oscillator each', () => {
    const a = freshState();
    Audio.unlock(a);
    made.osc = 0;
    Audio.play(a, 'feed');
    assert.strictEqual(made.osc, 1);
    made.osc = 0;
    Audio.play(a, 'yawn');
    assert.strictEqual(made.osc, 1);
  });

  test('new kinds never throw with a bad gain or delay option', () => {
    const a = freshState();
    Audio.unlock(a);
    for (const kind of ['chime', 'heartbeat', 'feed', 'yawn']) {
      assert.doesNotThrow(() => Audio.play(a, kind, { gain: NaN, delay: 99 }));
      assert.doesNotThrow(() => Audio.play(a, kind, { gain: 0 }));
    }
  });

  test('gasp and miss schedule oscillators and exist in the levels table', () => {
    const SoundData = require('../js/data/sounds.js');
    const a = freshState();
    Audio.unlock(a);
    for (const kind of ['gasp', 'miss']) {
      assert.ok(SoundData.levels[kind], kind + ' level');
      made.osc = 0;
      assert.doesNotThrow(() => Audio.play(a, kind));
      assert.ok(made.osc > 0, kind + ' creates oscillators');
      assert.doesNotThrow(() => Audio.play(a, kind, { gain: NaN, delay: 99 }));
      assert.doesNotThrow(() => Audio.play(a, kind, { gain: 0 }));
    }
    made.osc = 0;
    Audio.play(a, 'miss');
    assert.strictEqual(made.osc, 1);
  });

});

describe('audio-hunger.test.js', () => {

  const test = require('node:test');
  const assert = require('node:assert');

  const made = { osc: 0, peaks: [] };
  function param() {
    return {
      value: 0,
      setValueAtTime() {},
      linearRampToValueAtTime(v) { made.peaks.push(v); },
      exponentialRampToValueAtTime() {},
      cancelScheduledValues() {}
    };
  }
  function node(extra) {
    return Object.assign({ connect() {}, disconnect() {} }, extra || {});
  }
  class FakeAudioContext {
    constructor() { this.currentTime = 0; this.state = 'running'; this.destination = node(); }
    createOscillator() { made.osc++; return node({ type: 'sine', frequency: param(), start() {}, stop() {} }); }
    createGain() { return node({ gain: param() }); }
    createBiquadFilter() { return node({ type: 'lowpass', frequency: param() }); }
    createStereoPanner() { return node({ pan: param() }); }
  }
  require('node:test').before(() => { globalThis.AudioContext = FakeAudioContext; });
  require('node:test').after(() => { delete globalThis.AudioContext; });

  const Audio = require('../js/audio.js');
  const SoundData = require('../js/data/sounds.js');
  globalThis.VCS.SoundData = SoundData;
  const KINDS = ['shriek', 'mist', 'still', 'gift', 'overflow'];

  test('hunger kinds schedule oscillators and never throw on bad options', () => {
    const a = Audio.create({ volume: 0.7 });
    Audio.unlock(a);
    for (const k of KINDS) {
      made.osc = 0;
      assert.doesNotThrow(() => Audio.play(a, k));
      assert.ok(made.osc > 0, k);
      assert.doesNotThrow(() => Audio.play(a, k, { gain: NaN, delay: 99 }));
      assert.doesNotThrow(() => Audio.play(a, k, { gain: 0 }));
    }
  });

  test('hunger kinds are silent before unlock', () => {
    const a = Audio.create({ volume: 0.7 });
    made.osc = 0;
    for (const k of KINDS) Audio.play(a, k);
    assert.strictEqual(made.osc, 0);
  });

  test('levels and react.shriekMul match the contract', () => {
    const l = SoundData.levels;
    assert.deepStrictEqual(l.shriek, { range: null, strength: 1, z: 0.6, fade: null, bounces: 2, gain: 0.35 });
    assert.strictEqual(l.mist.gain, 0.12);
    assert.strictEqual(l.still.gain, 0.12);
    assert.strictEqual(l.gift.gain, 0.18);
    assert.strictEqual(l.overflow.gain, 0.06);
    assert.strictEqual(SoundData.react.shriekMul, 2.5);
  });

  test('shriek is the loudest and its summed peaks stay below 1', () => {
    const a = Audio.create({ volume: 1 });
    Audio.unlock(a);
    const sum = (k) => { made.peaks = []; Audio.play(a, k); return made.peaks.reduce((x, y) => x + y, 0); };
    const s = sum('shriek');
    assert.ok(s < 1, 'shriek sum ' + s);
    for (const k of KINDS.slice(1)) assert.ok(sum(k) < s, k + ' quieter than shriek');
  });

});

describe('sounds.test.js', () => {

  const test = require('node:test');
  const assert = require('node:assert');
  const SoundData = require('../js/data/sounds.js');

  test('levels table has every kind with sane numbers', () => {
    for (const k of ['step', 'personStep', 'door', 'interact', 'ping']) {
      const lv = SoundData.levels[k];
      assert.ok(lv, k);
      assert.ok(lv.strength > 0 && lv.strength <= 1, k + ' strength');
      assert.ok(Number.isInteger(lv.bounces) && lv.bounces >= 0 && lv.bounces <= 2, k + ' bounces');
    }
  });

  test('contract values', () => {
    const l = SoundData.levels;
    const row = (k, keys) => keys.map((x) => l[k][x]);
    assert.deepStrictEqual(row('step', ['range', 'strength', 'z', 'fade', 'bounces', 'gain']), [1.1, 0.3, 0, 0.8, 0, 0.08]);
    assert.deepStrictEqual(row('personStep', ['range', 'strength', 'z', 'fade', 'bounces', 'gain']), [0.2, 0.2, 0, 0.6, 0, 0.12]);
    assert.deepStrictEqual(row('door', ['range', 'strength', 'z', 'fade', 'bounces', 'gain']), [5, 0.5, 0.5, 2.5, 1, 0.25]);
    assert.deepStrictEqual(row('interact', ['range', 'strength', 'z', 'fade', 'bounces', 'gain']), [3, 0.35, 0.3, 1.8, 1, 0.15]);
    assert.strictEqual(l.ping.bounces, 2);
    assert.strictEqual(l.ping.z, 0.62);
    assert.strictEqual(l.personStep.hearDist, 9);
    assert.strictEqual(l.step.interval, 0.48);
  });

  test('v0.7 night sound levels exist with contract values', () => {
    const l = SoundData.levels;
    const row = (k) => ['range', 'strength', 'z', 'fade', 'bounces', 'gain'].map((x) => l[k][x]);
    assert.deepStrictEqual(row('chime'), [0, 0, 0.9, 1, 0, 0.22]);
    assert.deepStrictEqual(row('heartbeat'), [2.2, 0.45, 0.6, 1.2, 0, 0.25]);
    assert.deepStrictEqual(row('feed'), [0, 0, 0.5, 1, 0, 0.15]);
    assert.deepStrictEqual(row('yawn'), [0, 0, 0.5, 1, 0, 0.15]);
  });

  test('footsteps come from the floor and are short-lived', () => {
    const l = SoundData.levels;
    assert.strictEqual(l.step.z, 0);
    assert.strictEqual(l.personStep.z, 0);
    for (const k of ['step', 'personStep']) {
      assert.ok(l[k].range < 1.5, k + ' range stays small');
      assert.ok(l[k].fade <= 0.9, k + ' fade is short');
    }
    for (const k of ['step', 'personStep', 'door', 'interact', 'ping']) {
      assert.ok(l[k].z >= 0 && l[k].z <= 1, k + ' z within wall height');
    }
  });

  test('stepScale: sneak < walk < run, grass < wood < stone, pace clamps, unknown names act as walk/stone', () => {
    const sc = SoundData.stepScale;
    for (const key of ['range', 'strength', 'fade', 'gain']) {
      assert.ok(sc('sneak', 'wood', 1)[key] < sc('walk', 'wood', 1)[key], key + ' sneak < walk');
      assert.ok(sc('walk', 'wood', 1)[key] < sc('run', 'wood', 1)[key], key + ' walk < run');
      assert.ok(sc('walk', 'grass', 1)[key] < sc('walk', 'wood', 1)[key], key + ' grass < wood');
      assert.ok(sc('walk', 'wood', 1)[key] < sc('walk', 'stone', 1)[key], key + ' wood < stone');
    }
    assert.deepStrictEqual(sc('walk', 'wood', 1), { range: 1, strength: 1, fade: 1, gain: 1 });
    assert.deepStrictEqual(sc('nope', 'nope', NaN), sc('walk', 'stone', 1));
    assert.strictEqual(sc('walk', 'wood', 9).range, 1.25);
    assert.strictEqual(sc('walk', 'wood', 0.1).range, 0.8);
    const worst = sc('run', 'stone', 9).range * SoundData.levels.personStep.range;
    assert.ok(worst < 1.5, 'loudest villager step ring still small: ' + worst);
  });

  test('quieter sounds are weaker than louder ones', () => {
    const l = SoundData.levels;
    assert.ok(l.personStep.strength <= l.step.strength);
    assert.ok(l.personStep.strength <= l.interact.strength);
    assert.ok(l.interact.strength < l.door.strength);
    assert.ok(l.door.strength < l.ping.strength);
  });

  test('gasp and miss levels', () => {
    const l = SoundData.levels;
    const row = (k) => ['range', 'strength', 'z', 'fade', 'bounces', 'gain'].map((x) => l[k][x]);
    assert.deepStrictEqual(row('gasp'), [4, 0.4, 0.8, 1.2, 0, 0.2]);
    assert.deepStrictEqual(row('miss'), [0, 0, 0.5, 0.5, 0, 0.12]);
  });

});


describe('audio-a2.test.js', () => {

  const test = require('node:test');
  const assert = require('node:assert');
  const Audio = require('../js/audio.js');
  const SoundData = require('../js/data/sounds.js');
  globalThis.VCS = globalThis.VCS || {};
  globalThis.VCS.SoundData = SoundData;

  const param = (v) => ({ value: v, setValueAtTime() {}, linearRampToValueAtTime() {}, exponentialRampToValueAtTime() {}, cancelScheduledValues() {} });
  const node = (kind) => ({ kind, outputs: [], connect(d) { this.outputs.push(d); return d; } });

  function fullCtx() {
    const c = {
      currentTime: 1, state: 'running', sampleRate: 8000, destination: node('dest'), made: [],
      createOscillator() { const n = node('osc'); n.type = 'sine'; n.frequency = param(1); n.start = () => {}; n.stop = () => {}; return n; },
      createGain() { const n = node('gain'); n.gain = param(1); return n; },
      createBiquadFilter() { const n = node('filter'); n.frequency = param(1); c.made.push(n); return n; },
      createStereoPanner() { const n = node('pan'); n.pan = param(0); return n; },
      createDynamicsCompressor() { const n = node('comp'); n.threshold = param(0); n.ratio = param(0); n.knee = param(0); n.attack = param(0); n.release = param(0); return n; },
      createDelay() { const n = node('delay'); n.delayTime = param(0); return n; },
      createBuffer(ch, n) { return { getChannelData: () => new Float32Array(n) }; },
      createBufferSource() { const n = node('src'); n.start = () => {}; n.stop = () => {}; return n; }
    };
    return c;
  }
  const mk = () => { const a = Audio.create({ volume: 1 }); a.ctx = fullCtx(); a.ok = true; a.rand = () => 0.5; return a; };
  const count = (a, kind) => a.ctx.createGain && a.ctx.destination && a.ctx.__vcsVoices ? a.ctx.__vcsVoices.length : 0;

  test('master compressor feeds destination, threshold -18 ratio 4', () => {
    const a = mk();
    assert.strictEqual(Audio.play(a, 'step'), true);
    const m = a.ctx.__vcsMaster;
    assert.strictEqual(m.out.kind, 'comp');
    assert.strictEqual(m.out.threshold.value, -18);
    assert.strictEqual(m.out.ratio.value, 4);
    assert.deepStrictEqual(m.out.outputs, [a.ctx.destination]);
    assert.ok(m.send && m.delays.length >= 2, 'reverb send built');
  });

  test('dist attenuates and hearDist drops', () => {
    const a = mk();
    assert.strictEqual(Audio.play(a, 'scream', { dist: 26 }), false);
    assert.strictEqual(Audio.play(a, 'whimper', { dist: 7 }), false);
    assert.strictEqual(Audio.play(a, 'whimper', { dist: 4 }), true);
    assert.strictEqual(Audio.play(a, 'scream'), true);
    assert.strictEqual(Audio.play(a, 'scream', { dist: 20 }), true);
  });

  test('behind + occ takes the lower cutoff; breath honors occ like play', () => {
    const a = mk();
    Audio.play(a, 'doorClose');
    const n0 = a.ctx.made.length;
    Audio.play(a, 'doorClose', { behind: true, occ: { mat: 'brick' } });
    const lp = a.ctx.made.slice(n0).map((f) => f.frequency.value);
    assert.ok(Math.abs(lp[0] - Math.min(1200, A.occlusion('brick').lpHz)) < 1e-6, 'min cutoff');
    const b = mk();
    assert.strictEqual(Audio.breath(b, { occ: { mat: 'brick' } }), true);
    assert.strictEqual(Audio.breath(b, { occ: { mat: 'brick' } }), true);
  });

  test('voice cap is real: the oldest tracked voice is stopped past 96', () => {
    const a = mk();
    let first = null;
    for (let i = 0; i < 130; i++) {
      Audio.play(a, 'doorClose', { delay: 5 });
      if (i === 0) first = a.ctx.__vcsVoices[0];
    }
    assert.ok(a.ctx.__vcsVoices.length <= 96);
    assert.ok(!a.ctx.__vcsVoices.includes(first));
  });

  test('occluded and behind add lowpass; absent adds none', () => {
    const a = mk();
    Audio.play(a, 'doorClose');
    const before = a.ctx.made.length;
    Audio.play(a, 'doorClose', { occluded: true });
    const lp = a.ctx.made[a.ctx.made.length - 1];
    assert.strictEqual(lp.frequency.value, 600);
    Audio.play(a, 'doorClose', { behind: true });
    assert.strictEqual(a.ctx.made[a.ctx.made.length - 1].frequency.value, 1200);
    assert.strictEqual(a.ctx.made.length, before + 2);
  });

  test('step materials all play; unknown falls back to stone', () => {
    for (const m of ['stone', 'grass', 'wood', 'bogus']) {
      const a = mk();
      assert.strictEqual(Audio.play(a, 'step', { material: m }), true, m);
      assert.strictEqual(Audio.play(a, 'personStep', { material: m }), true, m);
    }
  });

  test('step is audible: more than one partial', () => {
    const a = mk();
    let oscs = 0;
    const orig = a.ctx.createOscillator;
    a.ctx.createOscillator = () => { oscs++; return orig(); };
    Audio.play(a, 'step');
    assert.ok(oscs >= 3, 'fundamental plus 2x and 3x');
  });

  // ---- v0.11 echo acoustics ---------------------------------------------------
  const A = SoundData.acoustics;
  /** Context whose oscillators/gains/delays record what was set on them. */
  function recCtx() {
    const a = mk();
    const c = a.ctx;
    c.oscs = [];
    c.delays = [];
    c.srcCount = 0;
    c.createOscillator = () => {
      const n = node('osc');
      n.type = 'sine';
      n.freqs = [];
      n.frequency = { value: 1, setValueAtTime(v) { n.freqs.push(v); }, exponentialRampToValueAtTime(v) { n.freqs.push(v); } };
      n.start = (t) => { n.t = t; };
      n.stop = () => {};
      c.oscs.push(n);
      return n;
    };
    c.createGain = () => {
      const n = node('gain');
      n.peak = 0;
      n.gain = { value: 1, setValueAtTime() {}, exponentialRampToValueAtTime() {}, linearRampToValueAtTime(v) { n.peak = v; } };
      return n;
    };
    const cd = c.createDelay;
    c.createDelay = () => { const n = cd(); c.delays.push(n); return n; };
    const cb = c.createBufferSource;
    c.createBufferSource = () => { c.srcCount++; return cb(); };
    c.createBiquadFilter = () => { const n = node('filter'); n.frequency = param(1); n.gain = param(0); n.type = ''; c.made.push(n); return n; };
    return a;
  }

  test('acoustics: beam table 0/-1/-3/-8/-14/-18/-20, symmetric, interpolated, non-increasing', () => {
    const want = [0, -1, -3, -8, -14, -18, -20];
    for (let i = 0; i < want.length; i++) {
      const th = (i * 30 * Math.PI) / 180;
      assert.ok(Math.abs(A.beam(th) - want[i]) < 1e-9, 'node ' + i * 30);
      assert.ok(Math.abs(A.beam(-th) - want[i]) < 1e-9, 'symmetric ' + i * 30);
    }
    assert.ok(Math.abs(A.beam((45 * Math.PI) / 180) + 2) < 1e-9, 'linear between nodes');
    let prev = 1;
    for (let d = 0; d <= 180; d += 5) {
      const b = A.beam((d * Math.PI) / 180);
      assert.ok(b <= prev + 1e-9, 'non-increasing at ' + d);
      prev = b;
    }
    assert.ok(Math.abs(A.beam(Math.PI * 2) - 0) < 1e-9, 'wraps');
  });

  test('acoustics: echo level formula (wall 2r image source, object sonar equation, beam once)', () => {
    const air = (r) => 2 * r * A.airDbPerM;
    const wall = (r) => -20 * Math.log10(2 * r) + 10 * Math.log10((1 - 0.03) * (1 - 0.1)) - air(r);
    assert.ok(Math.abs(A.echoLevel('wall', 3, 0, 'stone') - wall(3)) < 1e-9);
    assert.ok(Math.abs(A.echoLevel('wall', 10, 0, 'stone') - wall(10)) < 1e-9);
    assert.ok(Math.abs(A.echoLevel('wall', 3, Math.PI / 2, 'stone') - A.echoLevel('wall', 3, 0, 'stone') + 8) < 1e-9, 'beam applied once');
    const obj = (r, ts) => -40 * Math.log10(r) + ts - air(r);
    assert.ok(Math.abs(A.echoLevel('person', 3, 0) - obj(3, A.ts.person)) < 1e-9);
    assert.ok(Math.abs(A.echoLevel('prop', 3, 0) - obj(3, A.ts.prop)) < 1e-9);
    assert.ok(A.echoLevel('wall', 1, 0, 'grass') < A.echoLevel('wall', 1, 0, 'stone') - 3, 'grass absorbs');
    assert.ok(A.gameAmp(A.echoLevel('wall', 1, 0, 'stone')) > A.gameAmp(A.echoLevel('wall', 9, 0, 'stone')));
    assert.ok(A.gameAmp(-200) >= A.gameMin && A.gameAmp(50) <= 1);
  });

  test('acoustics: Sabine T60 per zone is clamped 0.4-2.5 s; comb gain 10^(-3 tau / T60)', () => {
    assert.ok(Math.abs(A.sabine(18, 12, 3.5, 0.15) - 1.26) < 0.01, 'tavern');
    assert.ok(Math.abs(A.sabine(10, 8, 2.7, 0.12) - 1.13) < 0.01, 'house1');
    assert.strictEqual(A.t60For('church', 'indoor'), 2.5, 'church capped');
    assert.strictEqual(A.t60For('crypt', 'indoor'), 2.5, 'crypt capped');
    assert.strictEqual(A.t60For('nowhere', 'indoor'), A.t60Indoor);
    assert.strictEqual(A.t60For(null, 'outdoor'), A.t60Outdoor);
    assert.strictEqual(A.sabine(2, 2, 2, 0.9), 0.4, 'floor clamp');
    assert.ok(Math.abs(A.combGain(0.037, 1) - 0.774) < 0.001);
    assert.ok(Math.abs(A.combGain(0.097, 2.5) - 0.765) < 0.001);
    assert.strictEqual(A.combGain(0.037, 99), A.combGain(0.037, 2.5), 'T60 clamped');
  });

  test('acoustics: transmission loss, Maekawa and occlusion', () => {
    assert.ok(Math.abs(A.maekawa(0) - 4.771) < 0.001, 'grazing N=0');
    assert.strictEqual(A.maekawa(100), A.maekawaCapDb);
    assert.ok(A.maekawa(0.4) > A.maekawa(0.1));
    const cut = (m) => A.occlusion(m).lpHz;
    assert.ok(cut('iron') > 4000, 'iron gate nearly open');
    assert.ok(cut('glass') < cut('door') + 600 && cut('door') > 1000 && cut('door') < 2000, 'door ~1.4 kHz');
    assert.ok(cut('brick') > 300 && cut('brick') < 380, 'brick ~340 Hz');
    assert.ok(A.occlusion('brick').gain < A.occlusion('door').gain && A.occlusion('door').gain < A.occlusion('iron').gain);
    A.mat.__gap = { alpha: 0, s: 0, rough: 0, tl500: 25, voice: 'hollow', gap: 0.01 };
    assert.ok(A.tlOf('__gap') < 20 && A.tlOf('__gap') > 17, 'a 1 % gap caps TL near 19 dB');
    delete A.mat.__gap;
    const d = A.occlusion('brick', 6);
    assert.strictEqual(d.diffracted, true, 'a doorway beats brick');
    assert.ok(d.gain > A.occlusion('brick').gain && d.lpHz > cut('brick'));
    assert.strictEqual(A.occlusion('iron', 40).diffracted, false, 'diffraction worse than TL is ignored');
    assert.ok(A.occlusion('glass').peakHz === 2000 && A.occlusion('brick').peakHz === 0);
  });

  test('acoustics: repetition pitch only inside rp.maxM, tau = 2r/c', () => {
    assert.strictEqual(A.repetition(2.01), null);
    assert.strictEqual(A.repetition(0), null);
    const r = A.repetition(1.3);
    assert.ok(Math.abs(r.tau - (2 * 1.3) / 343) < 1e-12);
    assert.ok(Math.abs(A.repetition(1).tau * 1000 - 5.831) < 0.001);
  });

  test('ping is a short ~8 ms 3.2 kHz click; pingBip / setPingStyle restore the old bip', () => {
    const a = recCtx();
    Audio.ping(a);
    assert.ok(a.ctx.oscs[0].freqs[0] > 3000 && a.ctx.oscs[0].freqs[0] < 3400, 'click near 3.2 kHz');
    assert.strictEqual(a.ctx.oscs[0].freqs.length, 1, 'no sweep');
    const b = recCtx();
    Audio.setPingStyle(b, true);
    Audio.ping(b);
    assert.ok(b.ctx.oscs[0].freqs[0] < 2000, 'bip');
    assert.strictEqual(Audio.create({ pingBip: true }).pingBip, true);
    assert.strictEqual(Audio.create({}).pingBip, false);
  });

  test('echo voices differ by material; grass is nearly silent; pingBip keeps the old chirp', () => {
    const peakOf2 = (voice) => {
      const a = recCtx();
      let pk = 0;
      const cg = a.ctx.createGain;
      a.ctx.createGain = () => { const n = cg(); const o = n.gain.linearRampToValueAtTime; n.gain.linearRampToValueAtTime = (v) => { pk = Math.max(pk, v); o(v); }; return n; };
      Audio.echo(a, 0.2, 0.8, 0, { voice });
      return { pk, f: a.ctx.oscs.map((o) => o.freqs[0]), types: a.ctx.oscs.map((o) => o.type) };
    };
    const crisp = peakOf2('crisp');
    const hollow = peakOf2('hollow');
    const ring = peakOf2('ring');
    const soft = peakOf2('soft');
    assert.ok(crisp.f[0] > 3000 && hollow.f[0] < 1000, 'stone crisp high, wood hollow low');
    assert.strictEqual(ring.f.length, 2, 'iron rings with an extra partial');
    assert.ok(soft.pk < crisp.pk * 0.25, 'grass nearly silent');
    assert.ok(peakOf2('tick').f[0] > 4500, 'glass tick');
    const a = recCtx();
    Audio.setPingStyle(a, true);
    Audio.echo(a, 0.2, 0.8, 0, { voice: 'crisp' });
    assert.strictEqual(a.ctx.oscs[0].freqs[0], 1800, 'old chirp when pingBip');
    const l = recCtx();
    Audio.echo(l, 0.2, 0.8, 0);
    assert.strictEqual(l.ctx.oscs[0].freqs[0], 1800, 'no voice, legacy');
  });

  test('echo: repetition-pitch comb is feed-forward at tau; rough hits add a grain tail', () => {
    const a = recCtx();
    Audio.echo(a, 0.2, 0.8, 0, { voice: 'crisp', rp: { tau: 0.0058, gain: 0.5 } });
    const rpDelays = a.ctx.delays.filter((d) => d.delayTime.value === 0.0058);
    assert.strictEqual(rpDelays.length, 1);
    const d = rpDelays[0];
    assert.ok(!d.outputs.includes(d), 'no self loop');
    const g = d.outputs[0];
    assert.ok(!g.outputs.some((x) => x === d), 'no feedback to the delay');
    const smooth = recCtx();
    Audio.echo(smooth, 0.2, 0.8, 0, { voice: 'crisp', rough: 0.1 });
    const rough = recCtx();
    Audio.echo(rough, 0.2, 0.8, 0, { voice: 'crisp', rough: 0.7 });
    assert.strictEqual(smooth.ctx.srcCount, 0);
    assert.strictEqual(rough.ctx.srcCount, 4, 'four grains');
    const mid = recCtx();
    Audio.echo(mid, 0.2, 0.8, 0, { voice: 'crisp', rough: 0.4 });
    assert.strictEqual(mid.ctx.srcCount, 2);
  });

  test('echo and ping feed the reverb send (so zone reverb colours them)', () => {
    const a = recCtx();
    Audio.play(a, 'step'); // builds the master chain
    const send = a.ctx.__vcsMaster.send;
    assert.ok(send);
    const before = a.ctx.gains ? 0 : 0;
    Audio.echo(a, 0.2, 0.8, 0, { voice: 'crisp' });
    const filt = a.ctx.made[a.ctx.made.length - 1];
    assert.ok(filt.outputs.includes(send), 'echo send');
    assert.strictEqual(before, 0);
  });

  test('setRoom with a T60 sets comb feedback 10^(-3 tau / T60), clamped; later-built master starts tuned', () => {
    const a = mk();
    Audio.play(a, 'step');
    Audio.setRoom(a, 'indoor', 1.0);
    const m = a.ctx.__vcsMaster;
    for (let i = 0; i < m.delays.length; i++) {
      assert.ok(Math.abs(m.fbs[i].gain.value - Math.pow(10, (-3 * m.delays[i].delayTime.value) / 1.0)) < 1e-9);
    }
    Audio.setRoom(a, 'indoor', 99);
    assert.ok(Math.abs(m.fbs[0].gain.value - Math.pow(10, (-3 * m.delays[0].delayTime.value) / 2.5)) < 1e-9, 'clamped to 2.5 s');
    Audio.setRoom(a, 'outdoor');
    assert.strictEqual(m.fbs[0].gain.value, 0.25, 'no T60: old fixed outdoor gain');
    const b = mk(); // room set before any sound: the chain built later starts tuned
    Audio.setRoom(b, 'indoor', 0.8);
    Audio.play(b, 'step');
    const mb = b.ctx.__vcsMaster;
    assert.ok(Math.abs(mb.fbs[1].gain.value - Math.pow(10, (-3 * mb.delays[1].delayTime.value) / 0.8)) < 1e-9);
  });

  test('play with occ: lowpass cutoff and gain follow the blocking material; no double cut with occluded', () => {
    const cut = (opts) => {
      const a = mk();
      Audio.play(a, 'doorClose');
      const n0 = a.ctx.made.length;
      Audio.play(a, 'doorClose', opts);
      return { lp: a.ctx.made.slice(n0).map((f) => f.frequency.value), n: a.ctx.made.length - n0 };
    };
    const brick = cut({ occluded: true, occ: { mat: 'brick' } });
    assert.strictEqual(brick.n, 1, 'one filter, not two');
    assert.ok(Math.abs(brick.lp[0] - A.occlusion('brick').lpHz) < 1e-6);
    const door = cut({ occluded: true, occ: { mat: 'door' } });
    assert.ok(door.lp[0] > brick.lp[0] * 3, 'door passes more than brick');
    const dif = cut({ occluded: true, occ: { mat: 'brick', diff: 5 } });
    assert.ok(dif.lp[0] > brick.lp[0] * 3, 'open doorway diffraction beats brick');
    assert.strictEqual(cut({ occluded: true }).lp[0], 600, 'bare occluded keeps the old lowpass');
    const glass = cut({ occluded: true, occ: { mat: 'glass' } });
    assert.strictEqual(glass.n, 2, 'glass adds its peak filter');
  });

  test('setRoom retunes the shared reverb', () => {
    const a = mk();
    Audio.play(a, 'step');
    const m = a.ctx.__vcsMaster;
    Audio.setRoom(a, 'outdoor');
    const out = m.delays[0].delayTime.value;
    Audio.setRoom(a, 'indoor');
    assert.ok(m.delays[0].delayTime.value > out);
  });

  test('whimper level and sound', () => {
    const l = SoundData.levels.whimper;
    assert.deepStrictEqual([l.range, l.strength, l.z, l.fade, l.bounces, l.gain, l.hearDist], [2, 0.25, 0.6, 1, 0, 0.1, 6]);
    assert.strictEqual(SoundData.levels.scream.hearDist, 25);
    assert.strictEqual(SoundData.levels.door.hearDist, 18);
    assert.strictEqual(SoundData.levels.personStep.gain, 0.12);
    assert.strictEqual(Audio.play(mk(), 'whimper'), true);
  });

  test('no AudioContext: everything no-ops', () => {
    const a = Audio.create({});
    assert.strictEqual(Audio.play(a, 'whimper', { dist: 1, material: 'grass' }), false);
    assert.doesNotThrow(() => Audio.setRoom(a, 'outdoor'));
  });
});

describe('audio-atmosphere (B4)', () => {

  const test = require('node:test');
  const assert = require('node:assert');
  const Audio = require('../js/audio.js');
  const SoundData = require('../js/data/sounds.js');
  globalThis.VCS = globalThis.VCS || {};
  globalThis.VCS.SoundData = SoundData;

  const param = (v) => ({ value: v, ev: [], setValueAtTime(x, t) { this.ev.push(['set', x, t]); }, linearRampToValueAtTime(x, t) { this.ev.push(['lin', x, t]); }, exponentialRampToValueAtTime() {}, cancelScheduledValues() {} });
  function ctxStub() {
    const c = {
      currentTime: 2, state: 'running', sampleRate: 1000, destination: null, count: { buf: 0, src: 0, gain: 0, osc: 0, pan: 0 }, srcs: [], oscs: [],
      createOscillator() { c.count.osc++; const n = nd(); n.type = 'sine'; n.frequency = param(1); n.start = () => { n.started = true; }; n.stop = (t) => { n.stoppedAt = t; }; c.oscs.push(n); return n; },
      createGain() { c.count.gain++; const n = nd(); n.gain = param(1); return n; },
      createBiquadFilter() { const n = nd(); n.frequency = param(1); return n; },
      createStereoPanner() { c.count.pan++; const n = nd(); n.pan = param(0); return n; },
      createBuffer(ch, n) { c.count.buf++; const d = new Float32Array(n); return { getChannelData: () => d }; },
      createBufferSource() { c.count.src++; const n = nd(); n.start = (t, off) => { n.started = [t, off]; }; n.stop = (t) => { n.stoppedAt = t; }; c.srcs.push(n); return n; }
    };
    function nd() { return { outputs: [], connect(d) { this.outputs.push(d); return d; }, disconnect() { this.disconnected = true; } }; }
    c.destination = nd();
    return c;
  }
  const mk = () => { const a = Audio.create({ volume: 1 }); a.ctx = ctxStub(); a.ok = true; a.rand = () => 0.5; return a; };

  test('levels exist with required hearDist and a wind gain under -30 dBFS', () => {
    const l = SoundData.levels;
    for (const k of ['wind', 'room', 'dog', 'bell', 'breath']) {
      assert.ok(l[k], k);
      assert.strictEqual(l[k].range, 0, k + ' has no visual pulse');
      assert.ok(l[k].gain > 0 && l[k].gain <= 0.3, k + ' gain small');
    }
    assert.strictEqual(l.breath.hearDist, 6);
    assert.strictEqual(l.dog.hearDist, 60);
    assert.strictEqual(l.bell.hearDist, 80);
    assert.ok(l.wind.gain < 0.0316 && l.room.gain < 0.0316);
  });

  test('everything no-ops without a context or state', () => {
    const a = Audio.create({});
    assert.strictEqual(Audio.ambience(a, { kind: 'outdoor' }), false);
    assert.strictEqual(Audio.oneShotFar(a, 'dog'), false);
    assert.strictEqual(Audio.breath(a, {}), false);
    assert.strictEqual(a.ctx, null);
    for (const x of [null, undefined]) {
      assert.doesNotThrow(() => Audio.ambience(x));
      assert.doesNotThrow(() => Audio.oneShotFar(x, 'bell'));
      assert.doesNotThrow(() => Audio.breath(x));
    }
  });

  test('ambience outdoor builds a quiet wind bed with one shared noise buffer', () => {
    const a = mk();
    assert.strictEqual(Audio.ambience(a, { kind: 'outdoor', level01: 1 }), true);
    assert.strictEqual(a.ctx.count.buf, 1);
    assert.strictEqual(a.ctx.count.src, 1);
    assert.strictEqual(a.ctx.count.osc, 2, 'two slow LFOs');
    assert.ok(a.ctx.oscs.every((o) => o.frequency.value < 0.2));
    const g = a.amb.bed.g.gain;
    const ramp = g.ev.find((e) => e[0] === 'lin');
    assert.ok(ramp[1] < 0.0316, 'under -30 dBFS: ' + ramp[1]);
    assert.ok(Math.abs(ramp[2] - (a.ctx.currentTime + 1.5)) < 1e-9, '1.5 s fade in');
    // same kind only retunes: no new nodes
    const srcs = a.ctx.count.src;
    Audio.ambience(a, { kind: 'outdoor', level01: 0.5 });
    assert.strictEqual(a.ctx.count.src, srcs);
  });

  test('ambience crossfades on change, retires the old bed, reuses the noise buffer', () => {
    const a = mk();
    Audio.ambience(a, { kind: 'outdoor' });
    const old = a.amb.bed;
    assert.strictEqual(Audio.ambience(a, { kind: 'indoor' }), true);
    assert.notStrictEqual(a.amb.bed, old);
    assert.ok(old.g.gain.ev.some((e) => e[0] === 'lin' && e[1] === 0 && Math.abs(e[2] - (a.ctx.currentTime + 1.5)) < 1e-9), 'old fades out over 1.5 s');
    assert.ok(old.srcs.every((s) => s.stoppedAt > a.ctx.currentTime + 1.5), 'old nodes stop after the fade');
    assert.doesNotThrow(() => old.srcs[0].onended());
    assert.strictEqual(old.g.disconnected, true);
    Audio.ambience(a, { kind: 'outdoor' });
    assert.strictEqual(a.ctx.count.buf, 1, 'one noise buffer for the whole context');
    assert.strictEqual(Audio.ambience(a, { kind: 'none' }), false);
    assert.strictEqual(a.amb, null);
  });

  test('setVolume retunes a running bed', () => {
    const a = mk();
    Audio.ambience(a, { kind: 'indoor' });
    const g = a.amb.bed.g.gain;
    Audio.setVolume(a, 0.5);
    const last = g.ev.filter((e) => e[0] === 'lin').pop();
    assert.ok(Math.abs(last[1] - 0.5 * SoundData.levels.room.gain) < 1e-9);
  });

  test('oneShotFar: dog makes 2-3 yips, bell is long, unknown and too far drop', () => {
    const a = mk();
    assert.strictEqual(Audio.oneShotFar(a, 'dog', { pan: -0.5, dist: 30 }), true);
    assert.ok([2, 3].includes(a.ctx.count.osc), 'yips ' + a.ctx.count.osc);
    assert.strictEqual(a.ctx.count.pan, 1);
    const b = mk();
    assert.strictEqual(Audio.oneShotFar(b, 'bell', { dist: 50 }), true);
    assert.ok(Math.max(...b.ctx.oscs.map((o) => o.stoppedAt)) - b.ctx.currentTime >= 5, 'long decay');
    assert.strictEqual(Audio.oneShotFar(b, 'dog', { dist: 61 }), false);
    assert.strictEqual(Audio.oneShotFar(b, 'bell', { dist: 81 }), false);
    assert.strictEqual(Audio.oneShotFar(b, 'step'), false);
    assert.strictEqual(Audio.oneShotFar(b, '__proto__'), false);
  });

  test('bell works as a homing sound through play() with pan, behind and occluded', () => {
    const a = mk();
    assert.strictEqual(Audio.play(a, 'bell', { pan: 0.8, dist: 20, behind: true }), true);
    assert.strictEqual(Audio.play(a, 'bell', { dist: 20, occluded: true }), true);
    assert.strictEqual(Audio.play(a, 'bell', { dist: 90 }), false);
  });

  test('breath: at most 2 core nodes (+ panner), cached buffers, cleans up', () => {
    const a = mk();
    assert.strictEqual(Audio.breath(a, { dist: 2 }), true);
    const c = a.ctx;
    assert.strictEqual(c.count.src, 1);
    assert.strictEqual(c.count.gain, 1);
    assert.strictEqual(c.count.osc, 0);
    const bufs = c.count.buf;
    Audio.breath(a, { dist: 2, pan: 0.4 });
    Audio.breath(a, { dist: 2, occluded: true });
    assert.strictEqual(c.count.buf, bufs, 'buffers are cached (noise, soft, dull)');
    Audio.breath(a, { dist: 2, occluded: true });
    assert.strictEqual(c.count.buf, bufs);
    assert.strictEqual(c.count.pan, 1);
    const s = c.srcs[0];
    assert.ok(s.stoppedAt - c.currentTime <= 1.7, 'about 1.6 s');
    assert.doesNotThrow(() => s.onended());
  });

  test('villager heartbeat: plays within 1 cell, silent beyond 2.5, no-ops without a context', () => {
    const a = mk();
    assert.strictEqual(Audio.heartbeat(a, { dist: 1, bpm: 65 }), true);
    assert.strictEqual(Audio.heartbeat(a, { dist: 2.2 }), true, 'faint tail out to 2.5 cells');
    assert.strictEqual(Audio.heartbeat(a, { dist: 2.5 }), false);
    assert.strictEqual(Audio.heartbeat(a, { dist: 5 }), false);
    assert.strictEqual(Audio.heartbeat(a, { dist: 1, pan: 0.6, occluded: true, behind: true, bpm: 130 }), true);
    assert.strictEqual(Audio.heartbeat(Audio.create({}), { dist: 1 }), false);
    assert.doesNotThrow(() => Audio.heartbeat(null));
    assert.ok(a.ctx.count.osc >= 3, 'lub, dub and click oscillators');
  });

  test('breath swell is 0.8 s in/out, scales with distance and rate; beyond 6 cells drops', () => {
    const a = mk();
    const peakAt = (o) => {
      const before = a.ctx.srcs.length;
      Audio.breath(a, o);
      return before;
    };
    assert.strictEqual(Audio.breath(a, { dist: 6 }), false);
    assert.strictEqual(Audio.breath(a, { dist: 9 }), false);
    const gainsOf = (n) => n.outputs; // src -> gain
    peakAt({ dist: 0 });
    const g0 = gainsOf(a.ctx.srcs[0])[0].gain.ev.filter((e) => e[0] === 'lin');
    assert.ok(Math.abs(g0[0][2] - (a.ctx.currentTime + 0.8)) < 1e-9);
    assert.ok(Math.abs(g0[1][2] - (a.ctx.currentTime + 1.6)) < 1e-9);
    peakAt({ dist: 3 });
    const g3 = gainsOf(a.ctx.srcs[1])[0].gain.ev.filter((e) => e[0] === 'lin');
    assert.ok(Math.abs(g3[0][1] - g0[0][1] / 2) < 1e-9, 'half gain at half hearDist');
    peakAt({ dist: 0, rate: 2 });
    const gr = gainsOf(a.ctx.srcs[2])[0].gain.ev.filter((e) => e[0] === 'lin');
    assert.ok(Math.abs(gr[1][2] - (a.ctx.currentTime + 0.8)) < 1e-9, 'rate 2 halves the swell');
  });

  test('new calls never throw on bad options or throwing nodes', () => {
    const a = mk();
    for (const o of [null, {}, { kind: 5, level01: NaN }, { dist: NaN, pan: 'x', rate: -1 }]) {
      assert.doesNotThrow(() => Audio.ambience(a, o));
      assert.doesNotThrow(() => Audio.breath(a, o));
      assert.doesNotThrow(() => Audio.oneShotFar(a, 'dog', o));
    }
    const b = mk();
    b.ctx.createBufferSource = () => { throw new Error('nope'); };
    b.ctx.createOscillator = () => { throw new Error('nope'); };
    assert.doesNotThrow(() => Audio.ambience(b, { kind: 'outdoor' }));
    assert.doesNotThrow(() => Audio.ambience(b, { kind: 'indoor' }));
    assert.doesNotThrow(() => Audio.breath(b, {}));
    assert.doesNotThrow(() => Audio.oneShotFar(b, 'bell'));
  });
});

describe('game-echo helpers (v0.11.2)', () => {

  const test = require('node:test');
  const assert = require('node:assert');
  const SoundData = require('../js/data/sounds.js');
  globalThis.VCS = globalThis.VCS || {};
  globalThis.VCS.SoundData = SoundData;
  for (const m of ['log', 'raycast', 'world', 'sonar', 'ripple', 'people', 'struggle']) require('../js/' + m + '.js');
  const Audio = require('../js/audio.js');
  require('../js/game.js');
  const VCS = globalThis.VCS;
  const G = VCS.Game.__test;
  const A = SoundData.acoustics;

  // Wall column at x=6 (brick; glass w at row 2, door D at row 3); floor stone/wood/grass by argument.
  const rows = ['###########', '#.....#...#', '#.....w...#', '#.....D...#', '#.....#...#', '###########'];
  const FLOOR_CH = { stone: '.', wood: ',', grass: 'g' };
  const mkWorld = (floor) => VCS.World.load({ name: 'occ', rows: rows.map((r) => r.replace(/[.]/g, FLOOR_CH[floor])), materials: { '#': 'brick' } }, { requireStart: false });
  const near = (a, b, eps) => assert.ok(Math.abs(a - b) < (eps || 1e-9), a + ' vs ' + b);

  // Records Audio.echo calls instead of making sound.
  function spyEcho(fn) {
    const calls = [];
    const real = VCS.Audio.echo;
    VCS.Audio.echo = (a, delay, strength, pan, opts) => { calls.push({ delay, strength, pan, opts }); };
    try { fn(); } finally { VCS.Audio.echo = real; }
    return calls;
  }

  test('firstSolid: clear line is null, blocked line returns the first solid point; short lines are ignored', () => {
    G.bind({ world: mkWorld('stone') });
    assert.strictEqual(G.firstSolid(1.5, 1.5, 4.5, 1.5), null);
    const hit = G.firstSolid(1.5, 1.5, 7.5, 1.5);
    assert.ok(hit && hit.x >= 6 && hit.x < 6.3 && hit.y === 1.5, 'stops at the wall column');
    assert.strictEqual(G.firstSolid(5.9, 1.5, 6.1, 1.5), null, 'under 0.5 cells is never occluded');
    G.bind({ world: null });
    assert.strictEqual(G.firstSolid(0, 0, 5, 5), null, 'no world, no hit');
  });

  test('blockMaterial: closed door is door, walls give the world material, glass is glass', () => {
    G.bind({ world: mkWorld('stone') });
    assert.strictEqual(G.blockMaterial(6.5, 3.5), 'door');
    assert.strictEqual(G.blockMaterial(6.5, 1.5), 'brick');
    assert.strictEqual(G.blockMaterial(6.5, 2.5), 'glass');
    G.bind({ world: {} });
    assert.strictEqual(G.blockMaterial(1, 1), 'stone', 'no material API falls back to stone');
  });

  test('occlusionTo: null when clear, else the first blocking material', () => {
    G.bind({ world: mkWorld('stone'), player: { x: 4.5, y: 1.5, angle: 0 } });
    assert.strictEqual(G.occlusionTo(5.5, 2.5), null);
    const brick = G.occlusionTo(7.5, 1.5);
    assert.strictEqual(brick.mat, 'brick');
    assert.strictEqual(brick.diff, null, 'no open doorway: no diffraction path');
    G.bind({ player: { x: 4.5, y: 3.5, angle: 0 } });
    assert.strictEqual(G.occlusionTo(7.5, 3.5).mat, 'door', 'closed door blocks');
    G.bind({ player: { x: 4.5, y: 2.5, angle: 0 } });
    assert.strictEqual(G.occlusionTo(7.5, 2.5).mat, 'glass');
  });

  test('occlusionTo: an open door lets sound through; a sound round the corner gets a doorway diff loss', () => {
    const w = mkWorld('stone');
    assert.ok(w.setDoor(6, 3, true));
    G.bind({ world: w, player: { x: 4.5, y: 3.5, angle: 0 } });
    assert.strictEqual(G.occlusionTo(7.5, 3.5), null, 'straight through the open door');
    G.bind({ player: { x: 4.5, y: 1.5, angle: 0 } });
    const o = G.occlusionTo(8.5, 1.5);
    assert.ok(o && o.mat === 'brick');
    assert.ok(typeof o.diff === 'number' && o.diff > 0, 'visible via the doorway: Maekawa loss ' + o.diff);
    const direct = Math.hypot(8.5 - 4.5, 0);
    const via = Math.hypot(6.5 - 4.5, 3.5 - 1.5) + Math.hypot(8.5 - 6.5, 1.5 - 3.5);
    near(o.diff, A.maekawa((via - direct) * A.cellM, A.maekawaHz), 0.5);
  });

  test('strongestEcho -> gameAmp end to end: the game plays the echo at gameAmp(level) with the material voice and 2d/v delay', () => {
    const w = mkWorld('stone');
    const player = { x: 3.5, y: 2.5, angle: 0 };
    const sonar = VCS.Sonar.create({ bounces: 0, visRays: 720 });
    VCS.Sonar.emit(sonar, w, player.x, player.y, 0, { facing: 0 });
    const lp = sonar.lastPulse;
    G.bind({ world: w, player: player, sonar: sonar, audio: { room: 'indoor' } });
    const best = VCS.Sonar.strongestEcho(lp, player.angle);
    const calls = spyEcho(() => G.pingEcho(lp));
    assert.strictEqual(calls.length, 1);
    near(calls[0].strength, A.gameAmp(best.level));
    near(calls[0].delay, Math.min(6, (2 * best.dist) / VCS.Sonar.SONAR_SPEED));
    assert.strictEqual(calls[0].opts.voice, A.matOf(best.mat).voice);
    assert.ok(calls[0].strength >= A.gameMin && calls[0].strength <= 1);
    // Standing closer to a wall is louder (same path, different player).
    const close = { x: 5.2, y: 2.5, angle: 0 };
    G.bind({ player: close });
    const s2 = VCS.Sonar.create({ bounces: 0, visRays: 720 });
    VCS.Sonar.emit(s2, w, close.x, close.y, 0, { facing: 0 });
    const nearCall = spyEcho(() => G.pingEcho(s2.lastPulse))[0];
    assert.ok(nearCall.strength > calls[0].strength, 'a nearer wall echoes louder');
  });

  test('floor bounce: one echo per ping voiced by the floor; grass silent, stone louder and crisp, wood hollow', () => {
    const run = (floor) => {
      G.bind({ world: mkWorld(floor), player: { x: 3.5, y: 2.5, angle: 0 }, audio: { room: 'indoor' } });
      return spyEcho(() => G.floorBounce());
    };
    assert.strictEqual(run('grass').length, 0, 'grass is ~silent: nothing played');
    const stone = run('stone');
    const wood = run('wood');
    assert.strictEqual(stone.length, 1);
    assert.strictEqual(wood.length, 1);
    assert.strictEqual(stone[0].opts.voice, 'crisp');
    assert.strictEqual(wood[0].opts.voice, 'hollow');
    assert.ok(stone[0].strength > wood[0].strength);
    near(stone[0].strength, A.floorAmp('stone'));
    near(stone[0].delay, A.floor.delay);
    assert.ok(A.floorAmp('grass') === 0 && A.floorLevel('grass') < A.floorLevel('wood') && A.floorLevel('wood') < A.floorLevel('stone'));
    // The old bip setting keeps its single chirp.
    G.bind({ world: mkWorld('stone'), audio: { room: 'indoor', pingBip: true } });
    assert.strictEqual(spyEcho(() => G.floorBounce()).length, 0);
  });

  test('person echo level follows the object sonar equation: -40 log d, beam off axis, old clamp kept', () => {
    G.bind({ audio: { room: 'indoor' }, sonar: { speed: VCS.Sonar.SONAR_SPEED } });
    const at = (dist, theta) => spyEcho(() => G.personEcho({ dist: dist, theta: theta || 0, strength: 1, pan: 0.2 }))[0];
    const a2 = at(2);
    const a4 = at(4);
    assert.strictEqual(a2.opts.voice, 'person');
    near(a2.strength, Math.min(0.7, Math.max(0.1, A.personAmp(2, 0))));
    assert.ok(a2.strength > a4.strength, 'doubling distance costs level');
    near(A.echoLevel('person', 2, 0) - A.echoLevel('person', 4, 0), 40 * Math.log10(2) + 2 * 2 * A.airDbPerM);
    assert.ok(at(3, Math.PI).strength < at(3, 0).strength, 'behind the mouth is quieter');
    near(a2.delay, 2 / VCS.Sonar.SONAR_SPEED);
    assert.ok(at(30).strength >= 0.1 - 1e-9, 'never below the old floor');
    assert.ok(at(0.2).strength <= 0.7 + 1e-9, 'never above the old ceiling');
  });

  test('person echoes of world sounds (villager steps) are silent; only the player ping is heard', () => {
    G.bind({ audio: { room: 'indoor' }, sonar: { speed: VCS.Sonar.SONAR_SPEED } });
    const go = (kind) => spyEcho(() => G.personEcho({ dist: 0.1, theta: 0, strength: 1, pan: 0, kind: kind }));
    assert.strictEqual(go('personStep').length, 0);
    assert.strictEqual(go('step').length, 0);
    assert.strictEqual(go('door').length, 0);
    assert.strictEqual(go('ping').length, 1);
  });

  test('person echo record carries theta (off the mouth axis) from the ping facing', () => {
    const w = mkWorld('stone');
    const sonar = VCS.Sonar.create({ bounces: 0, visRays: 360 });
    VCS.Sonar.emit(sonar, w, 1.5, 2.5, 0, { facing: 0, range: 8 });
    const p = { id: 1, x: 4.5, y: 1.5, angle: 0, state: 'idle', look: null, lookAngle: 0, phase: 0 };
    const made = VCS.People.updateEchoes({ people: [p], echoes: [] }, sonar, 0, 1);
    assert.strictEqual(made.length, 1, 'the wavefront crossed the person');
    near(made[0].theta, Math.atan2(1.5 - 2.5, 4.5 - 1.5), 0.02);
  });

  test('breath(): occlusion changes the actual output (quieter peak gain, duller buffer), not just the return value', () => {
    const param = (v) => ({ value: v, ev: [], setValueAtTime(x, t) { this.ev.push(['set', x, t]); }, linearRampToValueAtTime(x, t) { this.ev.push(['lin', x, t]); }, exponentialRampToValueAtTime() {}, cancelScheduledValues() {} });
    const nd = () => ({ outputs: [], connect(d) { this.outputs.push(d); return d; }, disconnect() {} });
    const mkCtx = () => {
      const c = {
        currentTime: 2, state: 'running', sampleRate: 1000, srcs: [], destination: nd(),
        createGain() { const n = nd(); n.gain = param(1); return n; },
        createBiquadFilter() { const n = nd(); n.frequency = param(1); return n; },
        createStereoPanner() { const n = nd(); n.pan = param(0); return n; },
        createBuffer(ch, n) { const d = new Float32Array(n); return { getChannelData: () => d }; },
        createBufferSource() { const n = nd(); n.start = () => {}; n.stop = () => {}; c.srcs.push(n); return n; }
      };
      return c;
    };
    const play = (o) => {
      const a = Audio.create({ volume: 1 });
      a.ctx = mkCtx();
      a.ok = true;
      a.rand = () => 0.5;
      assert.strictEqual(Audio.breath(a, o), true);
      const src = a.ctx.srcs[0];
      const peak = src.outputs[0].gain.ev.find((e) => e[0] === 'lin')[1];
      return { peak, buf: src.buffer, bufs: a.ctx.__vcsBreath };
    };
    const open = play({ dist: 1 });
    const brick = play({ dist: 1, occ: { mat: 'brick' } });
    const iron = play({ dist: 1, occ: { mat: 'iron' } });
    const bare = play({ dist: 1, occluded: true });
    assert.strictEqual(open.buf, open.bufs.soft);
    assert.strictEqual(brick.buf, brick.bufs.dull, 'occluded breath uses the dull buffer');
    assert.ok(brick.peak < open.peak, 'brick lowers the level');
    near(brick.peak, open.peak * A.occlusion('brick').gain);
    assert.ok(brick.peak < iron.peak, 'brick blocks more than iron bars');
    near(bare.peak, open.peak * 0.5);
  });
});

describe('villager heartbeat bpm and drink-victim suppression (circulatory P2)', () => {

  const test = require('node:test');
  const assert = require('node:assert');
  const SoundData = require('../js/data/sounds.js');
  globalThis.VCS = globalThis.VCS || {};
  globalThis.VCS.SoundData = SoundData;
  require('../js/data/vessels.js');
  for (const m of ['log', 'raycast', 'world', 'sonar', 'ripple', 'people', 'struggle']) require('../js/' + m + '.js');
  require('../js/audio.js');
  require('../js/game.js');
  const VCS = globalThis.VCS;
  const G = VCS.Game.__test;
  const near = (a, b, eps) => assert.ok(Math.abs(a - b) < (eps || 1e-9), a + ' vs ' + b);
  const v = (o) => Object.assign({ mode: 'path', wary: 0, pool: 40, left: 40, x: 2.5, y: 2.5 }, o);
  const mkWorld = () => VCS.World.load({ name: 'hb', rows: ['#######', '#.....#', '#.....#', '#.....#', '#######'] }, { requireStart: false });

  test('bpm per mode at full blood: calm 65, wary 90, startle/bumping 100, flee/cower 130', () => {
    assert.strictEqual(G.heartBpm(v({})), 65);
    assert.strictEqual(G.heartBpm(v({ mode: 'dazed' })), 65);
    assert.strictEqual(G.heartBpm(v({ wary: 2 })), 90);
    assert.strictEqual(G.heartBpm(v({ mode: 'startle' })), 100);
    assert.strictEqual(G.heartBpm(v({ bumping: true })), 100);
    assert.strictEqual(G.heartBpm(v({ mode: 'flee' })), 130);
    assert.strictEqual(G.heartBpm(v({ mode: 'cower' })), 130);
    assert.strictEqual(G.heartBpm(v({ mode: 'flee', wary: 3 })), 130, 'flight beats wariness');
  });

  test('blood curve follows the research: rises to ~1.3x at 40% blood, then falls to 0 at empty', () => {
    const at = (f, o) => G.heartBpm(v(Object.assign({ left: 40 * f }, o)));
    near(at(0.4), 65 * 1.3, 1e-6);
    assert.ok(at(0.7) > at(1) && at(0.4) > at(0.7), 'rises as blood is lost down to 40%');
    assert.ok(at(0.2) < at(0.4) && at(0.05) < at(0.2), 'collapses below 40%');
    near(at(0.2), 65 * 1.3 * 0.5, 1e-6);
    assert.strictEqual(at(0), 0, 'no pulse at empty');
    assert.strictEqual(G.heartState(v({ left: 0 })).pulse, false);
    assert.strictEqual(G.heartBpm(v({ pool: 0, left: 0 })), 65, 'unknown pool counts as full');
    // Strength and peripheral dimming come along with the bpm (single source of truth).
    const half = G.heartState(v({ left: 20 }));
    near(half.stateK, Math.pow(0.5, 1.5), 1e-9);
    near(half.periphK, 0.5, 1e-9);
  });

  test('bpm is capped at 175 (< 3 Hz)', () => {
    // Flight at 40% blood would be 130 * 1.3 = 169; the cap is the guard for anything above.
    near(G.heartBpm(v({ mode: 'flee', left: 16 })), 169, 1e-6);
    for (let f = 0; f <= 1.0001; f += 0.05) {
      for (const mode of ['path', 'startle', 'flee', 'cower']) assert.ok(G.heartBpm(v({ mode, wary: 1, left: 40 * f })) <= 175);
    }
    assert.strictEqual(VCS.Vessels.capBpm(400), 175);
  });

  function stepWith(list, drink) {
    const beats = [];
    const real = VCS.Audio.heartbeat;
    VCS.Audio.heartbeat = (a, o) => { beats.push(Object.assign({}, o)); return true; };
    const sonar = VCS.Sonar.create({ speed: 12, range: 10, fade: 3, cooldown: 0, bounces: 0 });
    G.bind({ world: mkWorld(), player: { x: 2, y: 2.5, angle: 0 }, sonar: sonar, audio: {}, clock: 0, night: null, drink: drink || null });
    try { G.stepHeartbeats(0.016, list); } finally { VCS.Audio.heartbeat = real; G.bind({ drink: null, sonar: null, audio: null }); }
    return { beats, pulses: sonar.pulses.filter((p) => p.kind === 'vheart') };
  }

  test('a beat sets the snapshot fields on the villager and plays at the same bpm', () => {
    const q = v({ mode: 'flee', left: 28, heartT: 0 });
    const r = stepWith([q]);
    assert.strictEqual(r.beats.length, 1);
    assert.strictEqual(r.pulses.length, 1);
    const hs = G.heartState(q);
    assert.strictEqual(q.heartBpm, hs.bpm);
    assert.strictEqual(r.beats[0].bpm, hs.bpm, 'audio and pulse share the bpm');
    assert.strictEqual(q.heartStateK, hs.stateK);
    assert.strictEqual(q.heartPeriphK, hs.periphK);
    assert.strictEqual(q.heartHeadK, hs.headK);
    near(q.heartT, 60 / hs.bpm, 1e-9);
  });

  test('the drink victim gets no villager vheart (audio or pulse); others still beat', () => {
    const victim = v({ heartT: 0 });
    const other = v({ x: 3, heartT: 0 });
    const r = stepWith([victim, other], { person: victim });
    assert.strictEqual(r.beats.length, 1, 'only the bystander is heard');
    assert.strictEqual(r.pulses.length, 1);
    assert.strictEqual(victim.heartBpm, undefined);
    assert.strictEqual(other.heartBpm, 65);
    const alone = stepWith([v({ heartT: 0 })].map((q) => q), null);
    assert.strictEqual(alone.beats.length, 1, 'without a drink the same villager beats');
    const solo = v({ heartT: 0 });
    assert.strictEqual(stepWith([solo], { person: solo }).beats.length, 0);
  });
});
