(function (root) {
  'use strict';
  const VCS = (root.VCS = root.VCS || {});

  // Procedural pose for a villager held by the vampire: panic flailing, then pushing away with straight arms, then going limp
  // as the blood drains. Pure maths: pose() fills `out` with body-frame offsets (f forward, s sideways, u height; the units
  // of render.js drawPerson). Moves are loosely based on human joint ranges (shoulder 0-180 deg, elbow 0-145, trunk twist ~40 deg,
  // neck roll ~45 deg) and the startle sequence (neck -> shoulders -> arms -> legs within ~200 ms).

  const TWO_PI = Math.PI * 2;
  const PANIC_END = 3.4;   // seconds after the grab when the flailing has burned out
  const PANIC_FADE = 1.2;
  const PUSH_SEG = 3.2;    // seconds per push-away variant
  const N_PUSH = 4;
  const SCALARS = ['lean', 'headF', 'headS', 'tilt', 'hipU', 'shU', 'headU', 'yawU', 'yawL', 'sway', 'sq', 'jolt'];
  const PAIRS = ['hf', 'hs', 'hu', 'hb', 'ff', 'fs', 'fu', 'kb'];

  function clamp(x, a, b) { return x < a ? a : x > b ? b : x; }
  function smooth(a, b, x) { const u = x <= a ? 0 : x >= b ? 1 : (x - a) / (b - a); return u * u * (3 - 2 * u); }
  function fract(x) { return x - Math.floor(x); }
  function hash(a, b) { return fract(Math.sin(a * 127.1 + b * 311.7) * 43758.5453); }
  function pos(x) { return x > 0 ? x : 0; }
  /** Fast attack, slow release bump peaking at x == tau with value 1. */
  function pk(x, tau) { return x > 0 ? (x / tau) * Math.exp(1 - x / tau) : 0; }

  function mkPose() {
    const p = {};
    for (let i = 0; i < SCALARS.length; i++) p[SCALARS[i]] = 0;
    for (let i = 0; i < PAIRS.length; i++) p[PAIRS[i]] = [0, 0];
    return p;
  }
  const PA = mkPose(); const PB = mkPose(); const UP = mkPose(); const LO = mkPose();
  const PIN = mkPose(); const PANIC = mkPose(); const PUSH = mkPose(); const PUSH2 = mkPose(); const LIMP = mkPose(); const TMP = mkPose();

  function copyPose(d, s) {
    for (let i = 0; i < SCALARS.length; i++) d[SCALARS[i]] = s[SCALARS[i]];
    for (let i = 0; i < PAIRS.length; i++) { const k = PAIRS[i]; d[k][0] = s[k][0]; d[k][1] = s[k][1]; }
  }
  function lerpPose(d, a, b, k) {
    for (let i = 0; i < SCALARS.length; i++) { const n = SCALARS[i]; d[n] = a[n] + (b[n] - a[n]) * k; }
    for (let i = 0; i < PAIRS.length; i++) {
      const n = PAIRS[i];
      d[n][0] = a[n][0] + (b[n][0] - a[n][0]) * k;
      d[n][1] = a[n][1] + (b[n][1] - a[n][1]) * k;
    }
  }
  /** Blend only the arm fields of d toward s by k. */
  function lerpArms(d, s, k) {
    const names = ['hf', 'hs', 'hu', 'hb'];
    for (let i = 0; i < names.length; i++) {
      const n = names[i];
      d[n][0] += (s[n][0] - d[n][0]) * k;
      d[n][1] += (s[n][1] - d[n][1]) * k;
    }
  }

  /** Rest pose of a held victim: hands up at the chest, feet planted a bit wide. */
  function base(P, c) {
    const L = c.L;
    P.lean = 0; P.headF = 0; P.headS = 0; P.tilt = 0.05; P.yawU = 0; P.yawL = 0; P.sway = 0; P.sq = 1; P.jolt = 0;
    P.hipU = 0.32 * L; P.shU = 0.53 * L; P.headU = 0.68 * L;
    for (let s = 0; s < 2; s++) {
      const sg = s === 0 ? 1 : -1;
      P.hf[s] = 0.08 * L; P.hs[s] = sg * c.shS * 1.3; P.hu[s] = P.shU - 0.06 * L; P.hb[s] = 0.8;
      P.ff[s] = 0; P.fs[s] = sg * c.hipS * 1.5; P.fu[s] = 0; P.kb[s] = 0.012 * L;
    }
  }

  // ---- Panic moves. Upper-body moves touch arms/head/trunk; lower-body moves touch legs, hips and sway. ----
  // m(P, t, a, spd, c, id): t absolute seconds, a amplitude 0..1, spd frequency scale.
  const UPPER = [
    // 0 wrist-pull breakaway: one arm at a time yanked down and back, trunk twisting with it
    function (P, t, a, spd, c) {
      for (let s = 0; s < 2; s++) {
        const sg = s ? -1 : 1; const L = c.L;
        const pull = Math.pow(pos(Math.sin(TWO_PI * 1.3 * spd * t + c.p + s * Math.PI)), 0.6) * a;
        P.hu[s] = P.shU - pull * (P.shU - P.hipU); P.hf[s] = (0.15 - 0.2 * pull) * L; P.hs[s] = sg * (c.shS + 0.06 * L);
        P.hb[s] = 0.8 - 0.5 * pull; P.yawU += sg * 0.35 * pull; P.headS += sg * 0.02 * pull;
      }
    },
    // 1 panic jabs: both hands punch at the camera
    function (P, t, a, spd, c) {
      for (let s = 0; s < 2; s++) {
        const pulse = Math.pow(pos(Math.sin(TWO_PI * 2.6 * spd * t + c.p + s * 0.7)), 3) * a;
        P.hf[s] = (0.06 + 0.16 * pulse) * c.L; P.hu[s] = P.shU + 0.01 * c.L; P.hb[s] = 1 - 0.9 * pulse;
      }
      P.jolt = Math.max(P.jolt, 0.7 * a);
    },
    // 2 windmill batting: arms sweep wide through abduction
    function (P, t, a, spd, c) {
      for (let s = 0; s < 2; s++) {
        const sg = s ? -1 : 1; const L = c.L;
        const th = 1.5 + (0.7 + 1.9 * (0.5 + 0.5 * Math.sin(TWO_PI * 1.7 * spd * t + c.p + s * Math.PI)) - 1.5) * a;
        P.hs[s] = sg * (c.shS + 0.22 * L * Math.sin(th)); P.hu[s] = P.shU - 0.22 * L * Math.cos(th); P.hf[s] = 0.05 * L; P.hb[s] = 0.3;
      }
      P.jolt = Math.max(P.jolt, 0.8 * a);
    },
    // 3 torso wrench: whole upper body twists left and right, head lagging
    function (P, t, a, spd, c) {
      const x = Math.sin(TWO_PI * 0.9 * spd * t + c.p);
      P.yawU += 0.5 * a * Math.sign(x) * Math.pow(Math.abs(x), 0.7);
      P.tilt += 0.25 * a * Math.sin(TWO_PI * 0.9 * spd * (t - 0.1) + c.p);
      for (let s = 0; s < 2; s++) { P.hu[s] = P.shU - 0.1 * c.L; P.hf[s] = 0.1 * c.L; }
      P.jolt = Math.max(P.jolt, 0.5 * a);
    },
    // 4 back arch: rear back with the arms flung wide (one-shot over the segment)
    function (P, t, a, spd, c) {
      const e = smooth(0, 0.15, c.seg) * (1 - smooth(0.35, 0.6, c.seg)) * a;
      P.lean -= 0.07 * c.L * e; P.headF -= 0.04 * c.L * e; P.headU += 0.025 * c.L * e; P.tilt -= 0.2 * e;
      for (let s = 0; s < 2; s++) {
        const sg = s ? -1 : 1;
        P.hs[s] += (sg * (c.shS + 0.12 * c.L) - P.hs[s]) * e; P.hu[s] += (P.headU - P.hu[s]) * e; P.hf[s] -= 0.04 * c.L * e;
      }
      P.sq += 0.05 * e; P.jolt = Math.max(P.jolt, 0.6 * e);
    },
    // 5 face claw: hands at its own face, alternate raking
    function (P, t, a, spd, c) {
      for (let s = 0; s < 2; s++) {
        const sg = s ? -1 : 1;
        P.hf[s] = 0.18 * c.L; P.hs[s] = sg * 0.05; P.hb[s] = 0.7;
        P.hu[s] = P.headU - 0.05 * c.L * pos(Math.sin(TWO_PI * 3 * spd * t + c.p + s * Math.PI)) * a;
      }
      P.tilt += 0.2 * a * Math.sin(TWO_PI * 1.4 * spd * t);
    },
    // 6 pry hands: hand over hand at the vampire's grip
    function (P, t, a, spd, c) {
      for (let s = 0; s < 2; s++) {
        const sg = s ? -1 : 1; const ph = Math.sin(TWO_PI * 2.4 * spd * t + s * Math.PI);
        P.hs[s] = sg * (0.02 + 0.03 * (ph > 0 ? 0.6 : 1)); P.hu[s] = P.shU - 0.08 * c.L + 0.04 * c.L * ph * a; P.hf[s] = 0.12 * c.L; P.hb[s] = 0.5;
      }
      P.jolt = Math.max(P.jolt, 0.4 * a);
    },
    // 7 slump: drop the weight and reach overhead to slip out of the grip
    function (P, t, a, spd, c) {
      const e = smooth(0, 0.2, c.seg) * (1 - smooth(0.4, 0.6, c.seg)) * a;
      P.shU -= 0.06 * c.L * e; P.headU -= 0.06 * c.L * e; P.sq -= 0.04 * e;
      for (let s = 0; s < 2; s++) { P.hu[s] += (P.headU + 0.08 * c.L - P.hu[s]) * e; P.hb[s] += (0.3 - P.hb[s]) * e; }
    }
  ];
  const LOWER = [
    // 0 knee / kick, legs alternating
    function (P, t, a, spd, c) {
      for (let s = 0; s < 2; s++) {
        const lift = Math.pow(pos(Math.sin(TWO_PI * 1.2 * spd * t + s * Math.PI + c.p)), 1.5) * a;
        P.fu[s] = 0.12 * c.L * lift; P.ff[s] = 0.1 * c.L * lift; P.kb[s] = (0.012 + 0.13 * lift) * c.L;
      }
    },
    // 1 stamp / heel dig
    function (P, t, a, spd, c) {
      for (let s = 0; s < 2; s++) {
        const x = Math.sin(TWO_PI * 2 * spd * t + s * Math.PI);
        P.fu[s] = 0.05 * c.L * pos(x) * a; P.fs[s] *= 1 + 0.2 * pos(-x);
      }
      P.sq -= 0.03 * a * pos(Math.sin(TWO_PI * 4 * spd * t));
    },
    // 2 side wrench: throw the whole body sideways
    function (P, t, a, spd, c) {
      const x = Math.sin(TWO_PI * 1.1 * spd * t + c.p);
      P.sway += 0.07 * a * x; P.headS -= 0.03 * a * x;
      const s = x > 0 ? 0 : 1; P.fs[s] += (s ? -1 : 1) * 0.03 * a * Math.abs(x);
    },
    // 3 squat: sink down and wide as dead weight
    function (P, t, a, spd, c) {
      const e = smooth(0, 0.2, c.seg) * (1 - smooth(0.4, 0.6, c.seg)) * a;
      P.hipU -= 0.07 * c.L * e;
      for (let s = 0; s < 2; s++) { const sg = s ? -1 : 1; P.kb[s] += 0.09 * c.L * e; P.fs[s] += sg * c.hipS * 0.7 * e; }
    }
  ];

  /** Schedule one region: pick a move from the villager's repertoire per segment and blend into the next. */
  function schedule(out, pool, t, a, spd, c, salt, dur0) {
    const dur = dur0 * (0.7 + 0.5 * hash(c.pid, salt)); // per-villager segment length
    const off = hash(c.pid, salt + 1) * dur;
    const n = Math.floor((t + off) / dur);
    const tSeg = (t + off) - n * dur;
    const pick = function (i) {
      const rep = [];
      for (let m = 0; m < pool.length; m++) if (hash(c.pid, salt * 7 + m) > 0.3) rep.push(m);
      if (rep.length < 2) { rep.length = 0; rep.push(0, 1); }
      let idx = rep[Math.floor(hash(c.pid + i * 0.37, salt + 5) * rep.length) % rep.length];
      const prev = rep[Math.floor(hash(c.pid + (i - 1) * 0.37, salt + 5) * rep.length) % rep.length];
      if (idx === prev) idx = rep[(rep.indexOf(idx) + 1) % rep.length];
      return idx;
    };
    const ma = pick(n);
    const mb = pick(n + 1);
    const k = smooth(dur - 0.18, dur, tSeg);
    c.seg = tSeg / dur;
    base(PA, c); pool[ma](PA, t, a, spd, c);
    if (k > 0) {
      c.seg = 0;
      base(PB, c); pool[mb](PB, t, a, spd, c);
      lerpPose(out, PA, PB, k);
    } else {
      copyPose(out, PA);
    }
  }

  // ---- Push-away variants ----
  function pushPose(P, v, t, a, spd, c, away) {
    const L = c.L;
    base(P, c);
    P.lean = -0.05 * L; P.headF = -0.035 * L; P.shU += 0.015 * L; P.headU -= 0.02 * L - 0.0; P.hipU -= 0.02 * L;
    P.headS = away * 0.04; P.tilt = away * 0.4; P.yawU = away * 0.2;
    // legs: one foot braced back, the other heel-digging forward, swapped every so often
    const swap = Math.floor(t / (0.45 + 0.25 * hash(c.pid, 33))) % 2 === 0 ? 0 : 1;
    P.ff[swap] = -0.09 * L; P.kb[swap] = 0.02 * L;
    P.ff[1 - swap] = 0.07 * L; P.kb[1 - swap] = 0.08 * L;
    P.fu[1 - swap] = 0.03 * L * pos(Math.sin(t * 9 * spd));
    const wr = TWO_PI * 1.3 * spd;
    if (v === 0) {
      // shove: straight arms thrust at the chest, elbows popping out as they unlock
      const e = Math.pow(pos(Math.sin(wr * t + c.p)), 0.5) * a;
      for (let s = 0; s < 2; s++) {
        const sg = s ? -1 : 1;
        P.hf[s] = (0.14 + 0.06 * e) * L; P.hs[s] = sg * c.shS * 0.9; P.hu[s] = P.shU + 0.01 * L; P.hb[s] = 0.6 * (1 - e);
      }
      P.lean -= 0.02 * L * e; P.hipU -= 0.01 * L * e; P.jolt = 0.6 * e;
    } else if (v === 1) {
      // face claw
      for (let s = 0; s < 2; s++) {
        const sg = s ? -1 : 1; const r = pos(Math.sin(TWO_PI * 2 * spd * t + s * Math.PI)) * a;
        P.hf[s] = 0.2 * L; P.hs[s] = sg * 0.05; P.hu[s] = P.headU + 0.01 * L - 0.06 * L * r; P.hb[s] = 0.5 + 0.3 * r;
      }
      P.tilt = away * 0.5; P.jolt = 0.5 * a;
    } else if (v === 2) {
      // grab the wrist and haul on it
      const yank = Math.pow(pos(Math.sin(TWO_PI * 0.9 * spd * t + c.p)), 3) * a;
      for (let s = 0; s < 2; s++) {
        const sg = s ? -1 : 1;
        P.hf[s] = (0.12 - 0.18 * yank) * L; P.hs[s] = sg * 0.02 - away * 0.03; P.hu[s] = P.shU - 0.05 * L; P.hb[s] = 0.5 + 0.3 * yank;
      }
      P.lean -= 0.08 * L * yank; P.hipU -= 0.03 * L * yank; P.sq -= 0.04 * yank; P.jolt = 0.7 * yank;
    } else {
      // one arm locked on the chest, the other batting at the head
      const lead = c.lead;
      for (let s = 0; s < 2; s++) {
        const sg = s ? -1 : 1;
        if (s === lead) {
          const e = 0.5 + 0.5 * Math.sin(wr * t + c.p);
          P.hf[s] = (0.2 + 0.015 * e) * L; P.hs[s] = sg * c.shS; P.hu[s] = P.shU; P.hb[s] = 0.05;
        } else {
          const th = 2.2 + 0.4 * Math.sin(TWO_PI * 1.7 * spd * t);
          const w = 0.4 + 0.6 * a;
          P.hs[s] = sg * (c.shS + 0.22 * L * Math.sin(th) * w); P.hu[s] = P.shU - 0.22 * L * Math.cos(th) * w; P.hf[s] = 0.08 * L; P.hb[s] = 0.3;
        }
      }
      P.jolt = 0.5 * a;
    }
  }

  /** Fully slack: the existing "grapple" pose (dangling arms, lolled head, buckled knees). */
  function limpPose(P, c) {
    const L = c.L;
    base(P, c);
    P.hipU = 0.3 * L; P.shU = 0.5 * L; P.headU = 0.6 * L;
    P.lean = 0.02 * L; P.headF = 0.03 * L; P.headS = 0.05 * c.bw; P.tilt = 0.55;
    P.ff[0] = 0; P.ff[1] = 0;
    P.kb[0] = 0.06 * L; P.kb[1] = 0.05 * L;
    P.fs[0] = c.hipS * 1.15; P.fs[1] = -c.hipS * 1.15;
    P.hf[0] = 0.01 * L; P.hf[1] = 0; P.hs[0] = c.shS * 1.1; P.hs[1] = -c.shS * 1.1;
    P.hu[0] = P.shU - 0.25 * L; P.hu[1] = P.shU - 0.26 * L; P.hb[0] = 0.2; P.hb[1] = 0.2;
  }

  /**
   * Fill `out` with the held victim's pose.
   * o: { t: clock seconds, g: seconds since the grab, bl: blood left 0..1, sp: seconds since the last struggle attempt,
   *      rs (restrain 0..1), pid, lh (height scale), bw (build), shS, hipS, anim (false = reduced motion: a still pose) }
   * out fields: lean headF headS tilt hipU shU headU yawU yawL sway sq jolt (scalars), and per-side hf hs hu hb (hand f/s/u + elbow bend 0..1),
   * ff fs fu (feet), kb (knee bend: extra forward offset of the knee).
   */
  function pose(out, o) {
    const pid = o.pid | 0;
    const anim = o.anim !== false;
    const c = { L: o.lh, bw: o.bw, shS: o.shS, hipS: o.hipS, pid: pid, p: pid * 1.7, seg: 0, lead: hash(pid, 93) < 0.5 ? 0 : 1 };
    const bl = clamp(o.bl, 0, 1);
    const E = Math.pow(smooth(0.05, 0.9, bl), 0.8);
    const amp = (0.8 + 0.4 * hash(pid, 92)) * Math.pow(E, 1.2);
    const spd = (0.85 + 0.35 * hash(pid, 91)) * (0.45 + 0.55 * E);
    const t = anim ? o.t : 0;
    const g = anim ? o.g : 99;
    const away = (pid & 2) ? 1 : -1;
    const a = clamp(amp, 0, 1);

    limpPose(LIMP, c);
    // Panic (first seconds) and a brief return of it on each struggle attempt while still strong
    const spike = anim ? pk(o.sp, 0.25) : 0;
    let wPanic = 1 - smooth(PANIC_END - PANIC_FADE, PANIC_END, g);
    if (bl > 0.6) wPanic = Math.max(wPanic, 0.6 * spike);
    const wPush = (1 - wPanic) * smooth(0.08, 0.3, bl);
    const wLimp = 1 - wPanic - wPush;

    if (wPanic > 0.001) {
      schedule(UP, UPPER, t, a, spd, c, 1, 0.75);
      schedule(LO, LOWER, t, a, spd, c, 2, 1.0);
      copyPose(PANIC, UP);
      for (let i = 0; i < PAIRS.length; i++) {
        const n = PAIRS[i];
        if (n === 'hf' || n === 'hs' || n === 'hu' || n === 'hb') continue;
        PANIC[n][0] = LO[n][0]; PANIC[n][1] = LO[n][1];
      }
      PANIC.hipU = LO.hipU; PANIC.yawL = LO.yawL; PANIC.sway = LO.sway; PANIC.sq = UP.sq * LO.sq;
      // head thrash overlay ("no no no") with a little high-frequency jitter
      PANIC.headS += 0.04 * a * Math.sin(TWO_PI * 1.4 * spd * t);
      PANIC.tilt += 0.5 * a * Math.sin(TWO_PI * 1.4 * spd * t - 0.4) + 0.06 * a * Math.sin(t * 25);
      if (g < 0.35) {
        // flinch: shoulders up, neck in, hands snapped to the face
        const x = g / 0.12; const e = x * Math.exp(1 - x) * (1 - smooth(0.2, 0.35, g));
        PANIC.shU += 0.03 * c.L * e; PANIC.headU -= 0.02 * c.L * e; PANIC.tilt += 0.15 * e;
        for (let s = 0; s < 2; s++) {
          const sg = s ? -1 : 1;
          PANIC.hu[s] += (PANIC.headU - 0.02 * c.L - PANIC.hu[s]) * e; PANIC.hs[s] += (sg * 0.04 - PANIC.hs[s]) * e;
          PANIC.hf[s] += (0.06 * c.L - PANIC.hf[s]) * e; PANIC.hb[s] += (1 - PANIC.hb[s]) * e;
        }
      }
    }
    if (wPush > 0.001 || wPanic <= 0.001) {
      const seg = Math.floor((anim ? g : 0) / PUSH_SEG);
      const kk = anim ? smooth(PUSH_SEG - 0.3, PUSH_SEG, g - seg * PUSH_SEG) : 0;
      const v0 = anim ? (pid + seg) % N_PUSH : 0;
      const v1 = anim ? (pid + seg + 1) % N_PUSH : 0;
      const tp = anim ? t : 0.2;
      const flip = hash(pid, Math.floor(g / 3) + 40) < 0.3 ? -1 : 1;
      pushPose(PUSH, v0, tp, a, spd, c, away * flip);
      if (kk > 0 && v0 !== v1) { pushPose(PUSH2, v1, tp, a, spd, c, away * flip); lerpPose(PUSH, PUSH, PUSH2, kk); }
      // Weakening: arms sag from the face to the chest to the waist, the head lolls first, knees buckle.
      const droop = 1 - smooth(0.15, 0.6, bl);
      lerpArms(PUSH, LIMP, droop);
      const loll = 1 - smooth(0.2, 0.55, bl);
      PUSH.tilt += (LIMP.tilt - PUSH.tilt) * loll; PUSH.headU += (LIMP.headU - PUSH.headU) * loll;
      const buckle = 1 - smooth(0.2, 0.35, bl);
      for (let s = 0; s < 2; s++) PUSH.kb[s] += (LIMP.kb[s] - PUSH.kb[s]) * buckle;
    }
    // Combine the three states.
    if (wLimp > 0.999) {
      copyPose(out, LIMP);
    } else if (wPanic > 0.999) {
      copyPose(out, PANIC);
    } else if (wPanic <= 0.001) {
      lerpPose(out, PUSH, LIMP, wLimp);
    } else {
      const d = wPanic + wPush > 0 ? wPanic / (wPanic + wPush) : 0;
      lerpPose(TMP, PUSH, PANIC, d);
      lerpPose(out, TMP, LIMP, wLimp);
    }
    // Restrained (vampire holding E): upper arms pinned to the body, thrashing damped to a squirm.
    const rs = clamp(o.rs || 0, 0, 1);
    if (rs > 0) {
      const L = c.L;
      for (let s = 0; s < 2; s++) {
        const sg = s ? -1 : 1;
        PIN.hf[s] = 0.03 * L; PIN.hs[s] = sg * c.shS * 1.15; PIN.hu[s] = out.hipU + 0.03 * L; PIN.hb[s] = 0.25;
      }
      lerpArms(out, PIN, 0.9 * rs * (1 - wLimp * 0.5));
      out.yawU *= 1 - 0.7 * rs; out.lean *= 1 - 0.5 * rs; out.sway *= 1 - 0.7 * rs;
      out.jolt *= 1 - 0.6 * rs;
    }
    // Tremor (shivering when drained) and the startle spike each time a break-free attempt fires.
    if (anim) {
      const L = c.L;
      const trem = 0.004 * L * (1 + 2 * (1 - E));
      const tf = 9 - 3 * (1 - E);
      out.shU += trem * Math.sin(t * tf * TWO_PI + pid);
      out.headU += trem * Math.sin(t * tf * TWO_PI + pid * 2);
      const sp = o.sp;
      const S = Math.sqrt(bl) * (1 - 0.7 * (1 - smooth(0.15, 0.6, bl)));
      if (S > 0 && sp >= 0 && sp < 0.7) {
        out.headU -= 0.02 * L * pk(sp, 0.07) * S;
        out.tilt += away * 0.15 * pk(sp, 0.07) * S;
        const sh = pk(sp - 0.03, 0.09) * S;
        out.shU += 0.02 * L * sh; out.yawU += away * 0.25 * sh;
        const ar = pk(sp - 0.08, 0.12) * S;
        for (let s = 0; s < 2; s++) { out.hf[s] += 0.05 * L * ar; out.hb[s] *= 1 - 0.8 * ar; out.hu[s] += 0.03 * L * ar; }
        const lg = pk(sp - 0.1, 0.15) * S;
        const kick = Math.floor(o.t * 3.1 + pid) % 2;
        out.fu[kick] += 0.08 * L * lg; out.ff[kick] += 0.06 * L * lg; out.kb[kick] += 0.08 * L * lg;
        out.jolt = Math.max(out.jolt, 1.0 * (ar > lg ? ar : lg));
        if (sp > 0.45) out.shU -= 0.01 * L * smooth(0.45, 0.55, sp) * (1 - smooth(0.6, 0.7, sp));
      }
    }
    out.jolt = clamp(out.jolt, 0, 1) * (anim ? 1 : 0);
    out.yawU = clamp(out.yawU, -0.55, 0.55);
    out.yawL = 0.4 * out.yawU;
    out.wl = wLimp;
    return out;
  }

  /** New pose container for pose(). */
  function create() { const p = mkPose(); p.wl = 0; return p; }

  const Struggle = { pose: pose, create: create, PANIC_END: PANIC_END, hash: hash };
  VCS.Struggle = Struggle;
  if (typeof module !== 'undefined' && module.exports) module.exports = Struggle;
})(typeof window !== 'undefined' ? window : globalThis);
