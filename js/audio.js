(function (root) {
  'use strict';
  const VCS = (root.VCS = root.VCS || {});

  const NOOP_LOG = { debug() {}, info() {}, warn() {}, error() {} };
  const DEFAULT_VOLUME = 0.7;
  const BASE_PEAK = 0.35;
  const PING_START_HZ = 1800;
  const PING_END_HZ = 1100;
  const PING_SEC = 0.07;
  const ATTACK_SEC = 0.005;
  const TAIL_SEC = 0.12;
  const FLOOR_GAIN = 0.0001;
  const ECHO_FILTER_HZ = 2200;
  const MAX_ECHO_DELAY = 6;
  const STEP_HZ = 120;
  const STEP_SEC = 0.04;
  const STEP_GAIN = 0.08;

  /** Returns the 'audio' logger, or a no-op logger when VCS.Log is missing. @returns {object} */
  function log() {
    try {
      const L = root.VCS && root.VCS.Log;
      if (L && typeof L.get === 'function') return L.get('audio');
    } catch (e) {
      // fall through to no-op
    }
    return NOOP_LOG;
  }

  /** Clamps a number to 0..1. @returns {number} */
  function clamp01(v) {
    return v < 0 ? 0 : v > 1 ? 1 : v;
  }

  /** Logs a sound failure as WARN once per audio state, then stays quiet. */
  function reportFailure(a, msg, err) {
    try {
      if (a && a.warned) return;
      if (a) a.warned = true;
      log().warn(msg, err);
    } catch (e) {
      // logging must never throw
    }
  }

  /** True when the audio state has a usable context. @returns {boolean} */
  function ready(a) {
    return !!(a && a.ok && a.ctx);
  }

  /** Resumes a suspended context if the browser allows it. */
  function resumeCtx(a) {
    try {
      const ctx = a.ctx;
      if (ctx.state === 'suspended' && typeof ctx.resume === 'function') {
        const p = ctx.resume();
        if (p && typeof p.catch === 'function') {
          p.catch((e) => reportFailure(a, 'Sound could not resume', e));
        }
      }
    } catch (e) {
      reportFailure(a, 'Sound could not resume', e);
    }
  }

  const ROOMS = { indoor: { gainMul: 1, cutoff: 2200 }, outdoor: { gainMul: 0.7, cutoff: 1400 } };

  /** Acoustics data block (SoundData.acoustics) or null. */
  function acoustics() {
    const sd = root.VCS && root.VCS.SoundData;
    return sd && sd.acoustics ? sd.acoustics : null;
  }

  // Per-material echo voices (v0.11). f0->f1 sweep over sec, tail = full decay, lp = lowpass Hz, gain = level scale, type = oscillator, partials = extra ring partials.
  // stone/brick crisp, wood hollow, glass tick, iron ring, grass nearly silent, people dull. 'legacy' is the old chirp (pingBip setting).
  const ECHO_VOICES = {
    legacy: { f0: PING_START_HZ, f1: PING_END_HZ, sec: PING_SEC, tail: TAIL_SEC, lp: ECHO_FILTER_HZ, gain: 1, type: 'sine' },
    crisp: { f0: 3200, f1: 2700, sec: 0.012, tail: 0.05, lp: 6500, gain: 1, type: 'sine' },
    hollow: { f0: 720, f1: 480, sec: 0.05, tail: 0.15, lp: 1500, gain: 0.95, type: 'triangle' },
    tick: { f0: 5200, f1: 4800, sec: 0.004, tail: 0.02, lp: 9000, gain: 0.8, type: 'sine' },
    ring: { f0: 2400, f1: 2400, sec: 0.02, tail: 0.45, lp: 5500, gain: 0.8, type: 'sine', partials: [2.76] },
    soft: { f0: 900, f1: 600, sec: 0.04, tail: 0.09, lp: 700, gain: 0.12, type: 'sine' },
    // dull body thud (a chirp here read as a cartoon "bew" on every villager echo)
    person: { f0: 170, f1: 120, sec: 0.03, tail: 0.09, lp: 380, gain: 1, type: 'sine' }
  };
  const MAX_VOICES = 96;

  /** Remember a voice (osc + its gain) so stopAll can fade it. Never throws. */
  function track(ctx, osc, g, endAt) {
    try {
      const list = ctx.__vcsVoices || (ctx.__vcsVoices = []);
      if (list.length >= MAX_VOICES) {
        const now = ctx.currentTime || 0;
        let w = 0;
        for (let i = 0; i < list.length; i++) if (list[i].end > now) list[w++] = list[i];
        list.length = w;
        if (list.length >= MAX_VOICES) {
          // Real cap: silence and stop the oldest voice instead of only forgetting it.
          const old = list.shift();
          try {
            old.g.gain.cancelScheduledValues(now);
            old.g.gain.setValueAtTime(0, now);
            old.osc.stop(now + 0.01);
          } catch (e) {
            // already ended
          }
        }
      }
      list.push({ osc: osc, g: g, end: endAt });
    } catch (e) {
      // tracking is best effort
    }
  }

  const REVERB = {
    indoor: { times: [0.037, 0.061, 0.097], fb: 0.58, cutoff: 1500, send: 0.15 },
    outdoor: { times: [0.019, 0.031, 0.047], fb: 0.25, cutoff: 2600, send: 0.15 }
  };

  /** Lazily builds the shared master chain (compressor, reverb send). Falls back to ctx.destination. @returns {{out: object, send: object|null, delays: object[], fbs: object[], lp: object|null}} */
  function master(ctx) {
    if (ctx.__vcsMaster) return ctx.__vcsMaster;
    const m = { out: ctx.destination, send: null, delays: [], fbs: [], lp: null };
    try {
      if (typeof ctx.createDynamicsCompressor === 'function') {
        const c = ctx.createDynamicsCompressor();
        if (c) {
          try {
            c.threshold.value = -18;
            c.ratio.value = 4;
            c.knee.value = 12;
            c.attack.value = 0.003;
            c.release.value = 0.25;
          } catch (e) {
            // params are best effort
          }
          c.connect(ctx.destination);
          m.out = c;
        }
      }
    } catch (e) {
      m.out = ctx.destination;
    }
    try {
      if (typeof ctx.createDelay === 'function') {
        const send = ctx.createGain();
        const lp = ctx.createBiquadFilter();
        lp.type = 'lowpass';
        lp.frequency.value = REVERB.indoor.cutoff;
        lp.connect(m.out);
        for (let i = 0; i < REVERB.indoor.times.length; i++) {
          const d = ctx.createDelay(1);
          d.delayTime.value = REVERB.indoor.times[i];
          const fb = ctx.createGain();
          fb.gain.value = REVERB.indoor.fb;
          send.connect(d);
          d.connect(fb);
          fb.connect(d);
          d.connect(lp);
          m.delays.push(d);
          m.fbs.push(fb);
        }
        m.send = send;
        m.lp = lp;
        send.gain.value = REVERB.indoor.send;
      }
    } catch (e) {
      m.send = null;
    }
    ctx.__vcsMaster = m;
    if (ctx.__vcsRoom) tuneReverb({ ctx: ctx }, ctx.__vcsRoom.kind, ctx.__vcsRoom.t60);
    return m;
  }

  /** Retunes the reverb for a room kind. Never throws. */
  function tuneReverb(a, kind, t60) {
    try {
      if (!a || !a.ctx) return;
      a.ctx.__vcsRoom = { kind: kind, t60: t60 }; // remembered so a master chain built later starts tuned
      if (!a.ctx.__vcsMaster) return;
      const m = a.ctx.__vcsMaster;
      const r = REVERB[kind] || REVERB.indoor;
      const A = acoustics();
      // Per-zone T60 (Sabine, clamped 0.4-2.5 s): each comb feeds back 10^(-3 tau / T60). Without data/T60 the old fixed gain is kept.
      const useT60 = A && typeof t60 === 'number' && isFinite(t60);
      for (let i = 0; i < m.delays.length; i++) {
        const tau = r.times[i % r.times.length];
        m.delays[i].delayTime.value = tau;
        if (m.fbs[i]) m.fbs[i].gain.value = useT60 ? A.combGain(tau, t60) : r.fb;
      }
      if (m.lp) m.lp.frequency.value = r.cutoff;
      if (m.send) m.send.gain.value = r.send;
    } catch (e) {
      // best effort
    }
  }

  /** Short filtered white-noise burst into target. Returns false when the context cannot make buffers. */
  function noise(ctx, target, t, dur, peak, ftype, freq, attack) {
    if (typeof ctx.createBuffer !== 'function' || typeof ctx.createBufferSource !== 'function') return false;
    const rate = ctx.sampleRate || 44100;
    const n = Math.max(1, Math.floor(rate * dur));
    const buf = ctx.createBuffer(1, n, rate);
    const d = buf.getChannelData(0);
    for (let i = 0; i < n; i++) d[i] = Math.random() * 2 - 1;
    const src = ctx.createBufferSource();
    src.buffer = buf;
    const f = ctx.createBiquadFilter();
    f.type = ftype;
    f.frequency.value = freq;
    const g = ctx.createGain();
    g.gain.setValueAtTime(0, t);
    g.gain.linearRampToValueAtTime(peak, t + (attack || 0.005));
    g.gain.exponentialRampToValueAtTime(FLOOR_GAIN, t + dur);
    src.connect(f);
    f.connect(g);
    g.connect(target);
    src.start(t);
    src.stop(t + dur);
    src.onended = function () {
      try {
        src.disconnect();
        f.disconnect();
        g.disconnect();
      } catch (e) {
        // best effort
      }
    };
    return true;
  }

  /** Builds one sonar chirp (oscillator through a gain envelope) into the target node. */
  function chirp(ctx, startAt, peak, target) {
    const osc = ctx.createOscillator();
    const gain = ctx.createGain();
    osc.type = 'sine';
    osc.frequency.setValueAtTime(PING_START_HZ, startAt);
    osc.frequency.exponentialRampToValueAtTime(PING_END_HZ, startAt + PING_SEC);
    gain.gain.setValueAtTime(0, startAt);
    gain.gain.linearRampToValueAtTime(peak, startAt + ATTACK_SEC);
    gain.gain.exponentialRampToValueAtTime(FLOOR_GAIN, startAt + TAIL_SEC);
    osc.connect(gain);
    gain.connect(target);
    osc.start(startAt);
    osc.stop(startAt + TAIL_SEC);
    track(ctx, osc, gain, startAt + TAIL_SEC);
  }

  /** One echo voice partial (oscillator sweep f0->f1 through a short enveloped gain) at frequency ratio k. */
  function voiceChirp(ctx, startAt, peak, target, v, k) {
    const osc = ctx.createOscillator();
    const gain = ctx.createGain();
    osc.type = v.type;
    osc.frequency.setValueAtTime(v.f0 * k, startAt);
    if (v.f1 !== v.f0) osc.frequency.exponentialRampToValueAtTime(v.f1 * k, startAt + v.sec);
    gain.gain.setValueAtTime(0, startAt);
    gain.gain.linearRampToValueAtTime(peak, startAt + Math.min(ATTACK_SEC, v.sec * 0.3));
    gain.gain.exponentialRampToValueAtTime(FLOOR_GAIN, startAt + v.tail);
    osc.connect(gain);
    gain.connect(target);
    osc.start(startAt);
    osc.stop(startAt + v.tail);
    track(ctx, osc, gain, startAt + v.tail);
  }

  /** Peak gain for a chirp at the given strength (0..1) and the current volume. @returns {number} */
  function peakFor(a, strength) {
    return a.volume * BASE_PEAK * strength;
  }

  /**
   * Creates audio state. Creates no AudioContext until unlock().
   * @param {object} [config] Settings; uses config.volume (0..1).
   * @returns {{ok: boolean, ctx: object|null, volume: number, warned: boolean}} Audio state.
   */
  function create(config) {
    try {
      let volume = DEFAULT_VOLUME;
      if (config && typeof config.volume === 'number' && Number.isFinite(config.volume)) {
        volume = clamp01(config.volume);
      }
      return { ok: true, ctx: null, volume, warned: false, pingBip: !!(config && config.pingBip === true) };
    } catch (e) {
      return { ok: true, ctx: null, volume: DEFAULT_VOLUME, warned: false, pingBip: false };
    }
  }

  /**
   * Creates or resumes the AudioContext. Call inside a user gesture. Safe to repeat.
   * @param {object} a Audio state from create().
   */
  function unlock(a) {
    try {
      if (!a) return;
      if (a.ctx) {
        a.ok = true;
        resumeCtx(a);
        return;
      }
      const Ctor = root.AudioContext || root.webkitAudioContext;
      if (typeof Ctor !== 'function') throw new Error('Web Audio is not available');
      a.ctx = new Ctor();
      a.ok = true;
      if (a.room) a.ctx.__vcsRoom = { kind: a.room, t60: a.t60 };
      log().info('Audio unlocked');
      resumeCtx(a);
    } catch (e) {
      a.ok = false;
      a.ctx = null;
      reportFailure(a, 'Sound is off: audio could not start', e);
    }
  }

  /** Random 0..1 (Math.random; overridable on the audio state for tests). @returns {number} */
  function rnd(a) {
    try {
      if (a && typeof a.rand === 'function') return a.rand();
    } catch (e) {
      // fall through
    }
    return Math.random();
  }

  /** The v0.11 ping: a short (~8 ms) 3.2 kHz click with a touch of high noise, into the master and the reverb send. */
  function clickPing(a, ctx, t) {
    const A = acoustics();
    const dur = A.ping.clickMs / 1000;
    const wob = 1 + (rnd(a) - 0.5) * 0.04;
    const osc = ctx.createOscillator();
    const gain = ctx.createGain();
    osc.type = 'sine';
    osc.frequency.setValueAtTime(A.ping.clickHz * wob, t);
    gain.gain.setValueAtTime(0, t);
    gain.gain.linearRampToValueAtTime(peakFor(a, 1) * 1.5, t + 0.001);
    gain.gain.exponentialRampToValueAtTime(FLOOR_GAIN, t + dur);
    osc.connect(gain);
    const m = master(ctx);
    gain.connect(m.out);
    if (m.send) gain.connect(m.send);
    osc.start(t);
    osc.stop(t + dur);
    track(ctx, osc, gain, t + dur);
    noise(ctx, m.out, t, 0.004, peakFor(a, 1) * 0.5, 'highpass', 2500, 0.001);
    log().debug('ping click');
  }

  /**
   * Plays the ping now: the short ~8 ms click by default, or the old cartoon "bip" (rises, then drops, tiny pitch wobble)
   * when the pingBip setting is on (create(config.pingBip) / setPingStyle). No-op when audio is not ready.
   * @param {object} a Audio state.
   */
  function ping(a) {
    try {
      if (!ready(a)) return;
      const ctx = a.ctx;
      const t = ctx.currentTime;
      if (a.pingBip !== true && acoustics()) {
        clickPing(a, ctx, t);
        return;
      }
      const wob = 1 + (rnd(a) - 0.5) * 0.04;
      const osc = ctx.createOscillator();
      const gain = ctx.createGain();
      osc.type = 'sine';
      osc.frequency.setValueAtTime(PING_START_HZ * wob, t);
      osc.frequency.exponentialRampToValueAtTime(PING_END_HZ * wob, t + PING_SEC);
      gain.gain.setValueAtTime(0, t);
      gain.gain.linearRampToValueAtTime(peakFor(a, 1), t + ATTACK_SEC);
      gain.gain.exponentialRampToValueAtTime(FLOOR_GAIN, t + TAIL_SEC);
      osc.connect(gain);
      gain.connect(master(ctx).out);
      osc.start(t);
      osc.stop(t + TAIL_SEC);
      track(ctx, osc, gain, t + TAIL_SEC);
      log().debug('ping');
    } catch (e) {
      reportFailure(a, 'Sound failed to play a ping', e);
    }
  }

  /**
   * Plays a delayed, softer, low-passed chirp for an echo. No-op when not ready,
   * when delaySec is outside 0..2, or when strength is not above 0.
   * @param {object} a Audio state.
   * @param {number} delaySec Seconds after now (0..2).
   * @param {number} strength Echo loudness, 0..1.
   * @param {number} [pan] Stereo position -1 (left) .. 1 (right); skipped if unsupported.
   * @param {{voice?: string, rp?: {tau: number, gain: number}, rough?: number}} [opts] voice crisp|hollow|tick|ring|soft|person (v0.11 material voice; ignored with pingBip),
   *   rp repetition-pitch comb (tau seconds), rough 0..1 adds a diffuse grain tail above 0.25.
   */
  function echo(a, delaySec, strength, pan, opts) {
    try {
      if (!ready(a)) return;
      if (!(delaySec >= 0 && delaySec <= MAX_ECHO_DELAY)) return;
      if (typeof strength !== 'number' || !Number.isFinite(strength)) return;
      const s = clamp01(strength * (ROOMS[a.room] || ROOMS.indoor).gainMul);
      if (s <= 0 || strength <= 0) return;
      const ctx = a.ctx;
      const o = opts || {};
      // v0.11 per-material voice (the old chirp is kept when no material is given or the pingBip setting is on).
      const voice = a.pingBip !== true && typeof o.voice === 'string' && ECHO_VOICES[o.voice] ? ECHO_VOICES[o.voice] : null;
      const filter = ctx.createBiquadFilter();
      filter.type = 'lowpass';
      const room = ROOMS[a.room] || ROOMS.indoor;
      filter.frequency.value = voice ? (a.room === 'outdoor' ? Math.min(voice.lp, 2.4 * room.cutoff) : voice.lp) : a.room === 'outdoor' ? room.cutoff : ECHO_FILTER_HZ;
      const m = master(ctx);
      const dest = m.out;
      let out = dest;
      if (typeof pan === 'number' && Number.isFinite(pan) && typeof ctx.createStereoPanner === 'function') {
        const panner = ctx.createStereoPanner();
        if (panner && panner.pan) {
          panner.pan.value = pan < -1 ? -1 : pan > 1 ? 1 : pan;
          panner.connect(dest);
          out = panner;
        }
      }
      filter.connect(out);
      if (m.send && voice) filter.connect(m.send);
      const t0 = ctx.currentTime + delaySec;
      if (!voice) {
        chirp(ctx, t0, peakFor(a, s), filter);
        return;
      }
      const peak = peakFor(a, s) * voice.gain;
      voiceChirp(ctx, t0, peak, filter, voice, 1);
      if (voice.partials) for (let i = 0; i < voice.partials.length; i++) voiceChirp(ctx, t0, peak * 0.4, filter, voice, voice.partials[i]);
      // Repetition pitch: a feed-forward comb (direct + the same click delayed 2r/c) for reflectors closer than rp.maxM.
      if (o.rp && o.rp.tau > 0 && o.rp.tau < 0.05 && typeof ctx.createDelay === 'function') {
        const d = ctx.createDelay(0.05);
        d.delayTime.value = o.rp.tau;
        const g = ctx.createGain();
        g.gain.value = clamp01(o.rp.gain);
        filter.connect(d);
        d.connect(g);
        g.connect(out);
      }
      // Diffuse grain tail on rough hits: a few short noise grains smeared over a physical-scale window.
      const rough = typeof o.rough === 'number' && o.rough > 0.25 ? Math.min(1, o.rough) : 0;
      if (rough) {
        const n = rough > 0.55 ? 4 : 2;
        for (let i = 0; i < n; i++) {
          const at = t0 + 0.004 + rnd(a) * 0.03 * rough + i * 0.006;
          noise(ctx, out, at, 0.012, peak * 0.4 * (1 - i / (n + 1)) * rough, 'bandpass', Math.min(voice.lp, 3000), 0.002);
        }
      }
    } catch (e) {
      reportFailure(a, 'Sound failed to play an echo', e);
    }
  }

  /**
   * Plays a very soft low footstep tick (40 ms, 120 Hz sine). No-op when not ready.
   * @param {object} a Audio state.
   */
  function step(a) {
    try {
      if (!ready(a)) return;
      const ctx = a.ctx;
      const t = ctx.currentTime;
      const osc = ctx.createOscillator();
      const gain = ctx.createGain();
      osc.type = 'sine';
      osc.frequency.setValueAtTime(STEP_HZ, t);
      gain.gain.setValueAtTime(0, t);
      gain.gain.linearRampToValueAtTime(a.volume * STEP_GAIN, t + 0.008);
      gain.gain.exponentialRampToValueAtTime(FLOOR_GAIN, t + STEP_SEC);
      osc.connect(gain);
      gain.connect(master(ctx).out);
      osc.start(t);
      osc.stop(t + STEP_SEC);
    } catch (e) {
      reportFailure(a, 'Sound failed to play a footstep', e);
    }
  }


  /** Connects a node to the master chain, through optional lowpass and StereoPanner, plus the reverb send. */
  function routeOut(ctx, node, pan, lpHz) {
    const m = master(ctx);
    let dest = m.out;
    if (typeof pan === 'number' && Number.isFinite(pan) && typeof ctx.createStereoPanner === 'function') {
      const panner = ctx.createStereoPanner();
      if (panner && panner.pan) {
        panner.pan.value = pan < -1 ? -1 : pan > 1 ? 1 : pan;
        panner.connect(dest);
        dest = panner;
      }
    }
    let head = dest;
    if (typeof lpHz === 'number' && lpHz > 0) {
      const lp = ctx.createBiquadFilter();
      lp.type = 'lowpass';
      lp.frequency.value = lpHz;
      lp.connect(dest);
      head = lp;
    }
    node.connect(head);
    if (m.send) node.connect(m.send);
    return node;
  }

  /** One enveloped oscillator into target. */
  function tone(ctx, target, type, f0, f1, t, attack, dur, peak) {
    const osc = ctx.createOscillator();
    const g = ctx.createGain();
    osc.type = type;
    osc.frequency.setValueAtTime(f0, t);
    if (f1 !== f0) osc.frequency.exponentialRampToValueAtTime(f1, t + dur);
    g.gain.setValueAtTime(0, t);
    g.gain.linearRampToValueAtTime(peak, t + attack);
    g.gain.exponentialRampToValueAtTime(FLOOR_GAIN, t + dur);
    osc.connect(g);
    g.connect(target);
    osc.start(t);
    osc.stop(t + dur);
    track(ctx, osc, g, t + dur);
  }

  /** One oscillator whose pitch glides through several (freq, time) points. */
  function bend(ctx, target, type, points, t, attack, dur, peak) {
    const osc = ctx.createOscillator();
    const g = ctx.createGain();
    osc.type = type;
    osc.frequency.setValueAtTime(points[0], t);
    for (let i = 1; i < points.length; i++) {
      osc.frequency.exponentialRampToValueAtTime(points[i], t + (dur * i) / (points.length - 1));
    }
    g.gain.setValueAtTime(0, t);
    g.gain.linearRampToValueAtTime(peak, t + attack);
    g.gain.exponentialRampToValueAtTime(FLOOR_GAIN, t + dur);
    osc.connect(g);
    g.connect(target);
    osc.start(t);
    osc.stop(t + dur);
    track(ctx, osc, g, t + dur);
  }

  // v = per-play variation: pitch (1 +- 0.08) and foot (0 left, 1 right).
  const KINDS = {
    // soft low thump; left and right feet have slightly different tones
    step: function (ctx, out, t, peak, v) {
      const m = v.material;
      if (m === 'grass') {
        // soft low-passed noise brush
        if (noise(ctx, out, t, 0.12, peak * 1.6, 'lowpass', 900 * v.pitch, 0.03)) {
          noise(ctx, out, t, 0.08, peak * 0.8, 'bandpass', 1800, 0.02);
          return;
        }
        tone(ctx, out, 'triangle', 300 * v.pitch, 180 * v.pitch, t, 0.03, 0.1, peak * 0.6);
        return;
      }
      if (m === 'wood') {
        // duller hollow thud
        const f = 150 * v.pitch * (v.foot ? 1.1 : 1);
        tone(ctx, out, 'triangle', f, f * 0.5, t, 0.005, 0.1, peak);
        tone(ctx, out, 'sine', f * 2.1, f * 1.2, t, 0.004, 0.06, peak * 0.5);
        tone(ctx, out, 'triangle', f * 3.2, f * 2, t, 0.004, 0.03, peak * 0.2);
        return;
      }
      const f = 110 * v.pitch * (v.foot ? 1.14 : 1);
      tone(ctx, out, v.foot ? 'triangle' : 'sine', f, f * 0.64, t, 0.008, 0.07, peak);
      tone(ctx, out, 'triangle', f * 2, f * 1.3, t, 0.005, 0.05, peak * 0.6);
      tone(ctx, out, 'triangle', f * 3, f * 2, t, 0.004, 0.035, peak * 0.4);
      noise(ctx, out, t, 0.03, peak * 0.5, 'bandpass', 700, 0.003);
    },
    // villager footstep: shoe heel thump + scuff noise by floor; feet alternate in tone
    personStep: function (ctx, out, t, peak, v) {
      const k = v.pitch * (v.foot ? 1.08 : 1);
      const m = v.material;
      if (m === 'grass') {
        if (noise(ctx, out, t, 0.11, peak * 1.3, 'lowpass', 800 * k, 0.02)) {
          noise(ctx, out, t + 0.01, 0.07, peak * 0.5, 'bandpass', 2200, 0.015);
          return;
        }
      } else if (m === 'wood') {
        tone(ctx, out, 'triangle', 140 * k, 70 * k, t, 0.004, 0.09, peak * 1.1);
        noise(ctx, out, t, 0.04, peak * 0.5, 'bandpass', 900 * k, 0.003);
        return;
      } else if (noise(ctx, out, t, 0.035, peak * 1.2, 'bandpass', 1500 * k, 0.002)) {
        // stone: crisp heel click, then a short scuff
        tone(ctx, out, 'sine', 95 * k, 55 * k, t, 0.004, 0.06, peak * 0.8);
        noise(ctx, out, t + 0.03, 0.06, peak * 0.35, 'highpass', 3000, 0.01);
        return;
      }
      tone(ctx, out, 'sine', 110 * k, 60 * k, t, 0.004, 0.07, peak);
    },
    // cartoon creak: pitch bends up and wobbles back down through a band-pass
    doorOpen: function (ctx, out, t, peak, v) {
      const f = ctx.createBiquadFilter();
      f.type = 'bandpass';
      f.frequency.setValueAtTime(260, t);
      f.frequency.exponentialRampToValueAtTime(900, t + 0.5);
      f.connect(out);
      const k = v.pitch;
      bend(ctx, f, 'sawtooth', [70 * k, 150 * k, 88 * k, 130 * k], t, 0.06, 0.55, peak);
      bend(ctx, f, 'sawtooth', [73 * k, 158 * k, 92 * k, 136 * k], t, 0.06, 0.55, peak * 0.6);
    },
    // short heavy thud
    doorClose: function (ctx, out, t, peak) {
      tone(ctx, out, 'sine', 90, 45, t, 0.006, 0.16, peak);
      tone(ctx, out, 'triangle', 180, 90, t, 0.004, 0.06, peak * 0.4);
    },
    // long wooden creak, slower and lower than a door
    creak: function (ctx, out, t, peak, v) {
      const f = ctx.createBiquadFilter();
      f.type = 'bandpass';
      f.frequency.setValueAtTime(180, t);
      f.frequency.exponentialRampToValueAtTime(620, t + 0.7);
      f.connect(out);
      const k = v.pitch;
      bend(ctx, f, 'sawtooth', [55 * k, 120 * k, 70 * k, 140 * k, 80 * k], t, 0.08, 0.75, peak);
    },
    // cartoon scream: wobbly high slide with a detuned partner
    scream: function (ctx, out, t, peak, v) {
      const k = v.pitch;
      bend(ctx, out, 'sawtooth', [500 * k, 1250 * k, 900 * k, 1500 * k, 700 * k], t, 0.03, 0.7, peak * 0.6);
      bend(ctx, out, 'square', [510 * k, 1290 * k, 930 * k, 1560 * k, 720 * k], t, 0.03, 0.7, peak * 0.3);
    },
    // short surprised "eep"
    startle: function (ctx, out, t, peak, v) {
      const k = v.pitch;
      bend(ctx, out, 'triangle', [600 * k, 1400 * k, 1000 * k], t, 0.01, 0.16, peak);
    },
    // hollow "tok": quick downward sine plus a quiet overtone
    interact: function (ctx, out, t, peak, v) {
      tone(ctx, out, 'sine', 420 * v.pitch, 170 * v.pitch, t, 0.003, 0.09, peak);
      tone(ctx, out, 'triangle', 840 * v.pitch, 340 * v.pitch, t, 0.003, 0.04, peak * 0.3);
    },
    // soft bell: 660 Hz then 990 Hz sine, both decaying over about 1.2 s
    chime: function (ctx, out, t, peak) {
      tone(ctx, out, 'sine', 660, 660, t, 0.01, 1.2, peak);
      tone(ctx, out, 'sine', 990, 990, t + 0.35, 0.01, 1.2, peak * 0.6);
    },
    // two low thumps, 55 Hz sliding to 40 Hz, 0.22 s apart
    heartbeat: function (ctx, out, t, peak) {
      tone(ctx, out, 'sine', 55, 40, t, 0.01, 0.12, peak);
      tone(ctx, out, 'triangle', 110, 80, t, 0.008, 0.08, peak * 0.5);
      tone(ctx, out, 'triangle', 165, 120, t, 0.006, 0.05, peak * 0.3);
      tone(ctx, out, 'sine', 55, 40, t + 0.22, 0.01, 0.12, peak * 0.8);
      tone(ctx, out, 'triangle', 110, 80, t + 0.22, 0.008, 0.08, peak * 0.4);
      tone(ctx, out, 'triangle', 165, 120, t + 0.22, 0.006, 0.05, peak * 0.25);
    },
    // soft low gulp: sine sliding 180 Hz down to 90 Hz
    feed: function (ctx, out, t, peak) {
      tone(ctx, out, 'sine', 180, 90, t, 0.02, 0.25, peak);
    },
    // wet gulp: low throat thump, a swallowed noise burst, then a smaller second "glk"
    gulp: function (ctx, out, t, peak, v) {
      const k = v.pitch;
      tone(ctx, out, 'sine', 150 * k, 70 * k, t, 0.01, 0.13, peak);
      noise(ctx, out, t + 0.01, 0.1, peak * 0.7, 'lowpass', 520 * k, 0.02);
      tone(ctx, out, 'sine', 230 * k, 120 * k, t + 0.14, 0.008, 0.08, peak * 0.6);
      noise(ctx, out, t + 0.14, 0.05, peak * 0.3, 'bandpass', 900 * k, 0.01);
    },
    // victim thrashing in your grip: muffled "mmph" with a cloth-rustle burst
    struggle: function (ctx, out, t, peak, v) {
      const k = v.pitch;
      bend(ctx, out, 'triangle', [240 * k, 330 * k, 200 * k], t, 0.03, 0.3, peak * 0.7);
      noise(ctx, out, t, 0.28, peak * 0.8, 'bandpass', 1100 * k, 0.03);
      noise(ctx, out, t + 0.12, 0.14, peak * 0.5, 'highpass', 2500, 0.02);
    },
    // a thrown rock hitting stone: sharp crack, then two skittering clicks that die away
    clatter: function (ctx, out, t, peak, v) {
      const k = v.pitch;
      noise(ctx, out, t, 0.05, peak, 'bandpass', 2400 * k, 0.005);
      tone(ctx, out, 'triangle', 900 * k, 380 * k, t, 0.002, 0.07, peak * 0.6);
      noise(ctx, out, t + 0.09, 0.04, peak * 0.55, 'bandpass', 3000 * k, 0.004);
      tone(ctx, out, 'triangle', 700 * k, 340 * k, t + 0.09, 0.002, 0.05, peak * 0.35);
      noise(ctx, out, t + 0.17, 0.03, peak * 0.3, 'bandpass', 3400 * k, 0.003);
    },
    // boots and cloth scraping while a victim is hauled along
    scuffle: function (ctx, out, t, peak, v) {
      noise(ctx, out, t, 0.11, peak, 'bandpass', 1300 * v.pitch, 0.01);
      tone(ctx, out, 'triangle', 120 * v.pitch, 70 * v.pitch, t, 0.005, 0.06, peak * 0.5);
    },
    // breathy gasp: short rising bend 400 -> 900 Hz with a detuned partner for a noisy edge
    gasp: function (ctx, out, t, peak, v) {
      const k = v.pitch;
      bend(ctx, out, 'triangle', [400 * k, 900 * k], t, 0.04, 0.25, peak);
      bend(ctx, out, 'sine', [430 * k, 960 * k], t, 0.04, 0.25, peak * 0.5);
    },
    // soft whoosh for a grab that finds nothing: triangle sliding 600 -> 200 Hz
    miss: function (ctx, out, t, peak) {
      tone(ctx, out, 'triangle', 600, 200, t, 0.03, 0.18, peak);
    },
    // slow yawn: triangle gliding 300 -> 180 -> 220 Hz over 0.9 s
    yawn: function (ctx, out, t, peak) {
      bend(ctx, out, 'triangle', [300, 180, 220], t, 0.15, 0.9, peak);
    },
    // loudest: sharp bat-like descending screech (summed partial peaks <= 1.0 x gain, so no clipping)
    shriek: function (ctx, out, t, peak, v) {
      const k = v.pitch;
      bend(ctx, out, 'sawtooth', [3200 * k, 2200 * k, 1100 * k], t, 0.01, 0.5, peak * 0.55);
      bend(ctx, out, 'square', [3350 * k, 2300 * k, 1150 * k], t, 0.01, 0.5, peak * 0.25);
      bend(ctx, out, 'sine', [1600 * k, 1100 * k, 550 * k], t, 0.01, 0.5, peak * 0.2);
    },
    // soft airy whoosh
    mist: function (ctx, out, t, peak) {
      tone(ctx, out, 'triangle', 900, 300, t, 0.08, 0.25, peak);
    },
    // low soft hum swell
    still: function (ctx, out, t, peak) {
      tone(ctx, out, 'sine', 90, 90, t, 0.3, 0.6, peak);
      tone(ctx, out, 'sine', 135, 135, t, 0.3, 0.6, peak * 0.4);
      tone(ctx, out, 'triangle', 180, 180, t, 0.3, 0.6, peak * 0.3);
      tone(ctx, out, 'triangle', 270, 270, t, 0.3, 0.6, peak * 0.15);
    },
    // two soft rising bell tones
    gift: function (ctx, out, t, peak) {
      tone(ctx, out, 'sine', 523, 523, t, 0.01, 0.8, peak);
      tone(ctx, out, 'sine', 784, 784, t + 0.25, 0.01, 0.8, peak * 0.8);
    },
    // very soft single low tick
    overflow: function (ctx, out, t, peak) {
      tone(ctx, out, 'sine', 70, 50, t, 0.004, 0.05, peak);
      tone(ctx, out, 'triangle', 140, 100, t, 0.003, 0.04, peak * 0.6);
      tone(ctx, out, 'triangle', 210, 150, t, 0.003, 0.03, peak * 0.4);
      noise(ctx, out, t, 0.025, peak * 0.4, 'bandpass', 600, 0.002);
    },
    // soft, short, breathy falling tone for cowering people
    whimper: function (ctx, out, t, peak, v) {
      const k = v.pitch;
      bend(ctx, out, 'sine', [520 * k, 430 * k, 330 * k], t, 0.06, 0.4, peak);
      bend(ctx, out, 'triangle', [1040 * k, 860 * k, 660 * k], t, 0.06, 0.4, peak * 0.25);
      noise(ctx, out, t, 0.35, peak * 0.3, 'bandpass', 1800, 0.08);
    },
    // distant dog: 2-3 low-passed yips
    dog: function (ctx, out, t, peak, v) {
      const f = ctx.createBiquadFilter();
      f.type = 'lowpass';
      f.frequency.value = 900;
      f.connect(out);
      const n = v.yips || 2;
      for (let i = 0; i < n; i++) {
        const k = v.pitch * (1 - i * 0.04);
        bend(ctx, f, 'sawtooth', [420 * k, 680 * k, 360 * k], t + i * 0.24, 0.015, 0.16, peak * (1 - i * 0.12));
      }
    },
    // deep church bell: inharmonic sine partials, long decay (also the crypt homing bell)
    bell: function (ctx, out, t, peak) {
      const parts = [[98, 1, 6], [196, 0.55, 4.5], [235, 0.3, 3.2], [294, 0.22, 2.4], [402, 0.1, 1.6]];
      for (let i = 0; i < parts.length; i++) tone(ctx, out, 'sine', parts[i][0], parts[i][0], t, 0.006, parts[i][2], peak * 0.5 * parts[i][1]);
    }
  };

  /**
   * Plays a movement/interaction sound. Kinds: step, personStep, doorOpen, doorClose, interact, creak, scream, startle,
   * chime, heartbeat, feed, gulp, struggle, scuffle, clatter, yawn, gasp, miss, shriek, mist, still, gift, overflow, whimper, dog, bell.
   * No-op when not ready or the kind is unknown.
   * @param {object} a Audio state.
   * @param {string} kind Sound kind.
   * @param {{gain?: number, pan?: number, delay?: number, dist?: number, occluded?: boolean, behind?: boolean, material?: string}} [opts] gain 0..1, pan -1..1, delay s (0..2), dist cells (attenuates; beyond hearDist drops and returns false), occluded (lowpass 600), occ {mat, diff} (v0.11 transmission-loss filter + gain by blocking material, diff = doorway Maekawa dB), behind (lowpass 1200, x0.7; the listener's rear shadow for world sounds), material stone|grass|wood.
   * @returns {boolean} true when played.
   */
  function play(a, kind, opts) {
    try {
      if (!ready(a)) return false;
      const fn = Object.prototype.hasOwnProperty.call(KINDS, kind) ? KINDS[kind] : null;
      if (!fn) {
        if (a && !a.warnedKinds) a.warnedKinds = {};
        if (a && a.warnedKinds && !a.warnedKinds[kind]) {
          a.warnedKinds[kind] = true;
          log().warn('Unknown sound kind: ' + String(kind));
        }
        return false;
      }
      const o = opts || {};
      const sd = root.VCS && root.VCS.SoundData && root.VCS.SoundData.levels;
      const lv = sd && sd[kind === 'doorOpen' || kind === 'doorClose' ? 'door' : kind];
      let gain = typeof o.gain === 'number' && Number.isFinite(o.gain) ? o.gain : (lv && lv.gain) || 0.1;
      gain = clamp01(gain);
      if (gain <= 0) return false;
      const delay = typeof o.delay === 'number' && Number.isFinite(o.delay) ? o.delay : 0;
      if (!(delay >= 0 && delay <= MAX_ECHO_DELAY)) return false;
      let lpHz = 0;
      if (typeof o.dist === 'number' && Number.isFinite(o.dist) && o.dist >= 0) {
        if (lv && typeof lv.hearDist === 'number' && o.dist > lv.hearDist) return false;
        gain *= 1 / (1 + o.dist / 4);
      }
      if (o.behind) {
        gain *= 0.7;
        lpHz = 1200;
      }
      // Occlusion (v0.11): o.occ = {mat, diff} -> transmission-loss filter by material (or a doorway's Maekawa loss when smaller).
      // A bare o.occluded keeps the old fixed 600 Hz lowpass.
      let fx = null;
      const A = acoustics();
      if (o.occ && typeof o.occ.mat === 'string' && A) {
        fx = A.occlusion(o.occ.mat, o.occ.diff);
        gain *= fx.gain;
        lpHz = lpHz ? Math.min(lpHz, fx.lpHz) : fx.lpHz;
      } else if (o.occluded) lpHz = 600;
      const ctx = a.ctx;
      const bus = ctx.createGain();
      bus.gain.value = 1;
      if (fx && fx.peakHz > 0) {
        const pk = ctx.createBiquadFilter();
        pk.type = 'peaking';
        pk.frequency.value = fx.peakHz;
        if (pk.Q) pk.Q.value = 1.4;
        if (pk.gain) pk.gain.value = fx.peakDb;
        bus.connect(pk);
        routeOut(ctx, pk, o.pan, lpHz);
      } else routeOut(ctx, bus, o.pan, lpHz);
      const foot = a.foot ? 1 : 0;
      if (kind === 'step' || kind === 'personStep') a.foot = !a.foot;
      const mat = o.material === 'grass' || o.material === 'wood' || o.material === 'stone' ? o.material : 'stone';
      const v = { pitch: 1 + (rnd(a) - 0.5) * 0.16, foot: typeof o.foot === 'number' ? (o.foot ? 1 : 0) : foot, material: mat };
      if (kind === 'dog') v.yips = 2 + Math.floor(rnd(a) * 2);
      fn(ctx, bus, ctx.currentTime + delay, a.volume * gain, v);
      return true;
    } catch (e) {
      reportFailure(a, 'Sound failed to play ' + kind, e);
      return false;
    }
  }

  const AMB_FADE = 1.5;
  const NOISE_SEC = 3;

  /** Shared looping white-noise buffer (one per context), or null when buffers are unsupported. @returns {object|null} */
  function noiseBuffer(ctx) {
    if (ctx.__vcsNoise) return ctx.__vcsNoise;
    if (typeof ctx.createBuffer !== 'function') return null;
    const rate = ctx.sampleRate || 44100;
    const n = Math.max(1, Math.floor(rate * NOISE_SEC));
    const buf = ctx.createBuffer(1, n, rate);
    const d = buf.getChannelData(0);
    for (let i = 0; i < n; i++) d[i] = Math.random() * 2 - 1;
    ctx.__vcsNoise = buf;
    return buf;
  }

  /** Shared breath buffers (soft and dull), the noise buffer smoothed by a one-pole low-pass. @returns {{soft: object, dull: object}|null} */
  function breathBuffers(ctx) {
    if (ctx.__vcsBreath) return ctx.__vcsBreath;
    const src = noiseBuffer(ctx);
    if (!src || typeof ctx.createBuffer !== 'function') return null;
    const rate = ctx.sampleRate || 44100;
    const white = src.getChannelData(0);
    const n = white.length;
    const make = (hz) => {
      const buf = ctx.createBuffer(1, n, rate);
      const d = buf.getChannelData(0);
      const k = 1 - Math.exp((-2 * Math.PI * hz) / rate);
      let y = 0;
      for (let i = 0; i < n; i++) {
        y += k * (white[i] - y);
        d[i] = y * 2.2;
      }
      return buf;
    };
    ctx.__vcsBreath = { soft: make(1800), dull: make(500) };
    return ctx.__vcsBreath;
  }

  /** Level row from SoundData (or a fallback). @returns {{gain: number, hearDist?: number}} */
  function levelOf(kind, fallbackGain) {
    const sd = root.VCS && root.VCS.SoundData && root.VCS.SoundData.levels;
    const lv = sd && sd[kind];
    return { gain: lv && typeof lv.gain === 'number' ? lv.gain : fallbackGain, hearDist: lv && lv.hearDist };
  }

  /** Ramps an AudioParam from its current value to v over sec seconds. Best effort. */
  function rampTo(p, v, now, sec) {
    if (typeof p.cancelScheduledValues === 'function') p.cancelScheduledValues(now);
    if (typeof p.setValueAtTime === 'function') p.setValueAtTime(typeof p.value === 'number' ? p.value : 0, now);
    if (typeof p.linearRampToValueAtTime === 'function') p.linearRampToValueAtTime(v, now + sec);
    else p.value = v;
  }

  /** Builds one ambience bed (all nodes start silent at gain 0). Returns {g, srcs, target} or null. */
  function buildBed(ctx, kind, target) {
    const out = master(ctx).out;
    const now = ctx.currentTime || 0;
    const g = ctx.createGain();
    g.gain.value = 0;
    g.connect(out);
    const srcs = [];
    if (kind === 'outdoor') {
      const buf = noiseBuffer(ctx);
      if (!buf) return null;
      const src = ctx.createBufferSource();
      src.buffer = buf;
      src.loop = true;
      const f = ctx.createBiquadFilter();
      f.type = 'lowpass';
      f.frequency.value = 420;
      src.connect(f);
      f.connect(g);
      // slow gusts: LFO on cutoff and on gain
      const l1 = ctx.createOscillator();
      const l1g = ctx.createGain();
      l1.frequency.value = 0.11;
      l1g.gain.value = 220;
      l1.connect(l1g);
      l1g.connect(f.frequency);
      const l2 = ctx.createOscillator();
      const l2g = ctx.createGain();
      l2.frequency.value = 0.07;
      l2g.gain.value = target * 0.35;
      l2.connect(l2g);
      l2g.connect(g.gain);
      src.start(now);
      l1.start(now);
      l2.start(now);
      srcs.push(src, l1, l2);
    } else {
      // low room tone: two soft sines a fifth apart, one very slowly beating
      const freqs = [55, 82.7, 55.4];
      const mix = [1, 0.5, 0.7];
      for (let i = 0; i < freqs.length; i++) {
        const o = ctx.createOscillator();
        o.type = 'sine';
        o.frequency.value = freqs[i];
        const og = ctx.createGain();
        og.gain.value = mix[i] / 2.2;
        o.connect(og);
        og.connect(g);
        o.start(now);
        srcs.push(o);
      }
    }
    return { g: g, srcs: srcs, kind: kind };
  }

  /** Stops a bed after fading it out. */
  function retireBed(bed, now, sec) {
    try {
      rampTo(bed.g.gain, 0, now, sec);
      for (let i = 0; i < bed.srcs.length; i++) {
        try {
          bed.srcs[i].stop(now + sec + 0.05);
        } catch (e) {
          // already stopped
        }
      }
      const s0 = bed.srcs[0];
      if (s0) {
        s0.onended = function () {
          try {
            bed.g.disconnect();
          } catch (e) {
            // best effort
          }
        };
      }
    } catch (e) {
      // best effort
    }
  }

  /**
   * Sets the ambience bed. outdoor = very quiet wind, indoor = very quiet low room tone, none = silence.
   * Changing kind crossfades over 1.5 s; the same kind only retunes the level. No-op without a context.
   * @param {object} a Audio state.
   * @param {{kind?: string, level01?: number}} [opts] kind outdoor|indoor|none (default none), level01 0..1 (default 1).
   * @returns {boolean} true when a bed is (or stays) playing.
   */
  function ambience(a, opts) {
    try {
      if (!ready(a)) return false;
      const o = opts || {};
      const kind = o.kind === 'outdoor' || o.kind === 'indoor' ? o.kind : 'none';
      const lvl = typeof o.level01 === 'number' && Number.isFinite(o.level01) ? clamp01(o.level01) : 1;
      const ctx = a.ctx;
      const now = ctx.currentTime || 0;
      const cur = a.amb || null;
      const target = a.volume * levelOf(kind === 'outdoor' ? 'wind' : 'room', kind === 'outdoor' ? 0.025 : 0.02).gain * lvl;
      if (cur && cur.kind === kind) {
        cur.level = lvl;
        if (kind !== 'none') rampTo(cur.bed.g.gain, target, now, 0.3);
        return kind !== 'none';
      }
      if (cur && cur.bed) retireBed(cur.bed, now, AMB_FADE);
      a.amb = null;
      if (kind === 'none') return false;
      const bed = buildBed(ctx, kind, target);
      if (!bed) return false;
      rampTo(bed.g.gain, target, now, AMB_FADE);
      a.amb = { kind: kind, bed: bed, level: lvl };
      return true;
    } catch (e) {
      reportFailure(a, 'Sound failed to set the ambience', e);
      return false;
    }
  }

  /**
   * Plays a scheduled distant event: 'dog' (2-3 low-passed yips) or 'bell' (deep church bell).
   * @param {object} a Audio state.
   * @param {string} kind dog | bell.
   * @param {{pan?: number, dist?: number}} [opts] pan -1..1, dist cells (attenuates; beyond hearDist drops).
   * @returns {boolean} true when played.
   */
  function oneShotFar(a, kind, opts) {
    try {
      if (kind !== 'dog' && kind !== 'bell') return false;
      const o = opts || {};
      return play(a, kind, { pan: o.pan, dist: o.dist });
    } catch (e) {
      reportFailure(a, 'Sound failed to play a far sound', e);
      return false;
    }
  }

  /**
   * One heartbeat "lub-dub" felt through the body: 60 Hz and 80 Hz sine thumps with a short 120 Hz click, low-passed near 200 Hz.
   * Quiet and mono-ish. opts {pan, dist, behind, occluded, bpm}: gain falls to 0 at hearDist (2 cells), bpm sets the lub-dub gap.
   * @returns {boolean} true when played.
   */
  function heartbeat(a, opts) {
    try {
      if (!ready(a)) return false;
      const o = opts || {};
      const lv = levelOf('vheart', 0.06);
      const hear = typeof lv.hearDist === 'number' ? lv.hearDist : 2;
      let gain = lv.gain;
      if (typeof o.dist === 'number' && Number.isFinite(o.dist) && o.dist >= 0) {
        if (o.dist >= hear) return false;
        gain *= 1 - o.dist / hear;
      }
      if (o.behind) gain *= 0.8;
      if (o.occluded) gain *= 0.6;
      gain *= a.volume;
      if (!(gain > 0)) return false;
      const ctx = a.ctx;
      if (typeof ctx.createOscillator !== 'function') return false;
      const bpm = typeof o.bpm === 'number' && Number.isFinite(o.bpm) ? Math.min(180, Math.max(30, o.bpm)) : 70;
      const gap = Math.min(0.35, 60 / bpm * 0.32);
      const t = ctx.currentTime || 0;
      const lp = ctx.createBiquadFilter();
      lp.type = 'lowpass';
      lp.frequency.value = 200;
      let node = null;
      if (typeof o.pan === 'number' && Number.isFinite(o.pan) && typeof ctx.createStereoPanner === 'function') {
        const pn = ctx.createStereoPanner();
        if (pn && pn.pan) {
          pn.pan.value = (o.pan < -1 ? -1 : o.pan > 1 ? 1 : o.pan) * 0.5;
          pn.connect(master(ctx).out);
          lp.connect(pn);
          node = pn;
        }
      }
      if (!node) lp.connect(master(ctx).out);
      const thump = (at, freq, amp) => {
        const osc = ctx.createOscillator();
        const g = ctx.createGain();
        osc.type = 'sine';
        osc.frequency.setValueAtTime(freq * 1.6, at);
        osc.frequency.exponentialRampToValueAtTime(freq, at + 0.05);
        g.gain.setValueAtTime(0, at);
        g.gain.linearRampToValueAtTime(gain * amp, at + 0.012);
        g.gain.exponentialRampToValueAtTime(0.0001, at + 0.14);
        osc.connect(g);
        g.connect(lp);
        osc.onended = function () {
          try { g.disconnect(); } catch (e) { /* best effort */ }
        };
        osc.start(at);
        osc.stop(at + 0.16);
        return osc;
      };
      thump(t, 60, 1);
      const last = thump(t + gap, 80, 0.7);
      const clk = ctx.createOscillator();
      const cg = ctx.createGain();
      clk.type = 'sine';
      clk.frequency.value = 120;
      cg.gain.setValueAtTime(gain * 0.35, t);
      cg.gain.exponentialRampToValueAtTime(0.0001, t + 0.03);
      clk.connect(cg);
      cg.connect(lp);
      clk.start(t);
      clk.stop(t + 0.04);
      last.addEventListener && last.addEventListener('ended', function () {
        try { lp.disconnect(); if (node) node.disconnect(); } catch (e) { /* best effort */ }
      });
      return true;
    } catch (e) {
      reportFailure(a, 'Sound failed to play a heartbeat', e);
      return false;
    }
  }

  /**
   * Plays one soft breath swell (about 0.8 s in, 0.8 s out). Cheap: reuses a cached buffer; a gain node and a
   * source per call (plus a panner only when pan is given); cleans itself up when it ends.
   * @param {object} a Audio state.
   * @param {{pan?: number, dist?: number, behind?: boolean, occluded?: boolean, rate?: number}} [opts] dist cells (hearDist 6, beyond drops), rate 0.5..2 speeds the swell.
   * @returns {boolean} true when played.
   */
  function breath(a, opts) {
    try {
      if (!ready(a)) return false;
      const o = opts || {};
      const lv = levelOf('breath', 0.05);
      const hear = typeof lv.hearDist === 'number' ? lv.hearDist : 6;
      let gain = lv.gain;
      if (typeof o.dist === 'number' && Number.isFinite(o.dist) && o.dist >= 0) {
        if (o.dist >= hear) return false;
        gain *= 1 - o.dist / hear;
      }
      if (o.behind) gain *= 0.7;
      const A = acoustics();
      if (o.occ && typeof o.occ.mat === 'string' && A) gain *= A.occlusion(o.occ.mat, o.occ.diff).gain;
      else if (o.occluded) gain *= 0.5;
      const dullIt = !!(o.occluded || o.behind || (o.occ && typeof o.occ.mat === 'string' && A));
      gain *= a.volume;
      if (!(gain > 0)) return false;
      const ctx = a.ctx;
      if (typeof ctx.createBufferSource !== 'function') return false;
      const bufs = breathBuffers(ctx);
      if (!bufs) return false;
      const rate = typeof o.rate === 'number' && Number.isFinite(o.rate) ? Math.min(2, Math.max(0.5, o.rate)) : 1;
      const half = 0.8 / rate;
      const t = ctx.currentTime || 0;
      const src = ctx.createBufferSource();
      src.buffer = dullIt ? bufs.dull : bufs.soft;
      src.loop = true;
      const g = ctx.createGain();
      g.gain.setValueAtTime(0, t);
      g.gain.linearRampToValueAtTime(gain, t + half);
      g.gain.linearRampToValueAtTime(0, t + half * 2);
      src.connect(g);
      let node = null;
      if (typeof o.pan === 'number' && Number.isFinite(o.pan) && typeof ctx.createStereoPanner === 'function') {
        const p = ctx.createStereoPanner();
        if (p && p.pan) {
          p.pan.value = o.pan < -1 ? -1 : o.pan > 1 ? 1 : o.pan;
          p.connect(master(ctx).out);
          g.connect(p);
          node = p;
        }
      }
      if (!node) g.connect(master(ctx).out);
      src.onended = function () {
        try {
          g.disconnect();
          if (node) node.disconnect();
        } catch (e) {
          // best effort
        }
      };
      src.start(t, rnd(a) * 1.2);
      src.stop(t + half * 2 + 0.02);
      return true;
    } catch (e) {
      reportFailure(a, 'Sound failed to play a breath', e);
      return false;
    }
  }

  /**
   * Sets the volume, clamped to 0..1. Ignores non-numbers.
   * @param {object} a Audio state.
   * @param {number} v Volume.
   */
  function setVolume(a, v) {
    try {
      if (!a || typeof v !== 'number' || Number.isNaN(v)) return;
      a.volume = clamp01(v);
      if (a.amb && a.amb.kind !== 'none') ambience(a, { kind: a.amb.kind, level01: a.amb.level });
    } catch (e) {
      // never throws
    }
  }

  /**
   * Sets the room acoustics: 'indoor' (short bright echo) or 'outdoor' (longer, softer). Unknown kinds are ignored.
   * @param {object} a Audio state.
   * @param {string} kind Room kind.
   */
  function setRoom(a, kind, t60) {
    try {
      if (!a || !Object.prototype.hasOwnProperty.call(ROOMS, kind)) return;
      a.room = kind;
      a.t60 = typeof t60 === 'number' && isFinite(t60) ? t60 : undefined;
      tuneReverb(a, kind, a.t60);
    } catch (e) {
      // never throws
    }
  }

  /**
   * Fades out every active voice and cancels voices scheduled for later (echoes). Safe when locked/unavailable.
   * @param {object} a Audio state.
   * @param {number} [fadeSec] Fade length in seconds (default 0.15).
   */
  function stopAll(a, fadeSec) {
    try {
      if (!a || !a.ctx) return;
      const ctx = a.ctx;
      const list = ctx.__vcsVoices;
      if (!list || !list.length) return;
      const fade = typeof fadeSec === 'number' && Number.isFinite(fadeSec) && fadeSec >= 0 ? Math.min(fadeSec, 2) : 0.15;
      const now = ctx.currentTime || 0;
      for (let i = 0; i < list.length; i++) {
        const v = list[i];
        try {
          if (v.end <= now) continue;
          const p = v.g.gain;
          if (typeof p.cancelScheduledValues === 'function') p.cancelScheduledValues(now);
          if (typeof p.setValueAtTime === 'function') p.setValueAtTime(typeof p.value === 'number' && p.value > 0 ? p.value : FLOOR_GAIN, now);
          if (typeof p.linearRampToValueAtTime === 'function') p.linearRampToValueAtTime(0, now + fade);
          v.osc.stop(now + fade + 0.02);
        } catch (e) {
          // voice already ended
        }
      }
      list.length = 0;
    } catch (e) {
      reportFailure(a, 'Sound failed to stop', e);
    }
  }

  const FIRE_MAX = 0.035;
  const FIRE_SLOTS = 2;

  /**
   * Steady quiet fire noise bed for one of 2 slots (shared noise buffer, lowpass 2.5 kHz, panned).
   * level01 0..1 scales the gain (0 = silent); the voice is built on first use and only retargeted after.
   * @param {object} a Audio state.
   * @param {number} slot 0 or 1.
   * @param {number} level01 0..1.
   * @param {number} pan -1..1.
   * @returns {boolean} true when audible.
   */
  function fireBed(a, slot, level01, pan) {
    try {
      if (!ready(a) || !(slot >= 0 && slot < FIRE_SLOTS)) return false;
      const lv = typeof level01 === 'number' && Number.isFinite(level01) ? clamp01(level01) : 0;
      if (!a.fire) a.fire = [null, null];
      let v = a.fire[slot];
      if (!v) {
        if (lv <= 0.001) return false;
        const ctx = a.ctx;
        const buf = noiseBuffer(ctx);
        if (!buf) return false;
        const src = ctx.createBufferSource();
        src.buffer = buf;
        src.loop = true;
        const f = ctx.createBiquadFilter();
        f.type = 'lowpass';
        f.frequency.value = 2500;
        const g = ctx.createGain();
        g.gain.value = 0;
        src.connect(f);
        f.connect(g);
        let pn = null;
        if (typeof ctx.createStereoPanner === 'function') {
          pn = ctx.createStereoPanner();
          if (pn && pn.pan) { pn.connect(master(ctx).out); g.connect(pn); } else pn = null;
        }
        if (!pn) g.connect(master(ctx).out);
        src.start(ctx.currentTime || 0, slot * 1.3);
        v = a.fire[slot] = { g: g, pn: pn, lv: 0, tgt: 0, pan: 0 };
      }
      const ctx2 = a.ctx;
      const now = ctx2.currentTime || 0;
      const tgt = lv * a.volume * FIRE_MAX;
      if (Math.abs(tgt - v.tgt) > FIRE_MAX * 0.01 || (tgt === 0 && v.tgt !== 0)) {
        v.lv = lv;
        v.tgt = tgt;
        if (typeof v.g.gain.setTargetAtTime === 'function') v.g.gain.setTargetAtTime(tgt, now, 0.12);
        else v.g.gain.value = tgt;
      }
      if (v.pn && typeof pan === 'number' && Number.isFinite(pan) && Math.abs(pan - v.pan) > 0.02) {
        v.pan = pan < -1 ? -1 : pan > 1 ? 1 : pan;
        v.pn.pan.value = v.pan;
      }
      return v.lv > 0;
    } catch (e) {
      reportFailure(a, 'Sound failed to update the fire bed', e);
      return false;
    }
  }

  /** Chooses the ping: true = the old cartoon bip (and the old echo chirp), false = the ~8 ms click with material echo voices. */
  function setPingStyle(a, bip) {
    if (a) a.pingBip = bip === true;
  }

  const Audio = { create, unlock, ping, echo, step, play, setVolume, setRoom, setPingStyle, ECHO_VOICES, stopAll, ambience, oneShotFar, breath, heartbeat, fireBed };

  VCS.Audio = Audio;
  if (typeof module !== 'undefined' && module.exports) module.exports = Audio;
})(typeof window !== 'undefined' ? window : globalThis);
