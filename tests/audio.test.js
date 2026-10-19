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
    const a = Audio.create();
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
    const a = Audio.create();
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
    assert.deepStrictEqual(row('personStep', ['range', 'strength', 'z', 'fade', 'bounces', 'gain']), [0.7, 0.35, 0, 0.7, 0, 0.12]);
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

  test('quieter sounds are weaker than louder ones', () => {
    const l = SoundData.levels;
    assert.ok(l.step.strength <= l.personStep.strength);
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
