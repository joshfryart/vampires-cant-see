(function (root) {
  'use strict';
  const VCS = (root.VCS = root.VCS || {});

  const TWO_PI = Math.PI * 2;
  const TOL = 0.35;
  const DEFAULTS = { speed: 12, range: 10, fade: 3.0, cooldown: 0.8, maxPulses: 64, visRays: 720, reflectors: 6, bounces: 2 };
  const MAX_PER_SOUND = 12;

  function logger() {
    try {
      return root.VCS && root.VCS.Log ? root.VCS.Log.get('sonar') : null;
    } catch (e) {
      return null;
    }
  }

  /** Create sonar state; missing or invalid opts fall back to defaults. */
  function create(opts) {
    const s = { pulses: [], lastEmit: -Infinity, lastPulse: null };
    const o = opts || {};
    for (const k in DEFAULTS) {
      s[k] = typeof o[k] === 'number' && isFinite(o[k]) && o[k] > 0 ? o[k] : DEFAULTS[k];
    }
    s.maxPulses = Math.floor(s.maxPulses);
    s.visRays = Math.max(8, Math.floor(s.visRays));
    s.reflectors = Math.floor(s.reflectors);
    s.bounces = typeof o.bounces === 'number' && isFinite(o.bounces) && o.bounces >= 0 ? Math.min(2, Math.floor(o.bounces)) : DEFAULTS.bounces;
    return s;
  }

  /** Clear all pulses and the last pulse; keeps config and cooldown (lastEmit). */
  function reset(state) {
    if (!state || !Array.isArray(state.pulses)) return state;
    state.pulses.length = 0;
    state.lastPulse = null;
    return state;
  }

  /** Seconds of cooldown remaining at time t (>= 0). */
  function cooldownLeft(state, t) {
    return Math.max(0, state.cooldown - (t - state.lastEmit));
  }

  function makeVis(world, x, y, range, n) {
    const R = root.VCS.Raycast;
    const vis = new Float32Array(n);
    for (let i = 0; i < n; i++) vis[i] = R.distOne(world, x, y, (i / n) * TWO_PI, range);
    return vis;
  }

  function makePulse(world, x, y, t0, range, speed, strength, kind, gen, n, z, fade) {
    return { x: x, y: y, z: z, fade: fade, t0: t0, range: range, speed: speed, vis: makeVis(world, x, y, range, n), strength: strength, kind: kind, gen: gen };
  }

  /** Reflection points (nearest wall points, local minima of vis, >= 20 deg apart). Returns [{a, d}] nearest first. */
  function pickReflectors(pulse, maxN) {
    const v = pulse.vis;
    const n = v.length;
    const cand = [];
    for (let i = 0; i < n; i++) {
      const d = v[i];
      if (d >= pulse.range - 1e-4) continue;
      const prev = v[(i + n - 1) % n];
      const next = v[(i + 1) % n];
      if (d <= prev && d < next) cand.push({ a: (i / n) * TWO_PI, d: d });
    }
    cand.sort(function (p, q) { return p.d - q.d; });
    const minSep = (20 * Math.PI) / 180;
    const out = [];
    for (let i = 0; i < cand.length && out.length < maxN; i++) {
      let ok = true;
      for (let j = 0; j < out.length; j++) {
        let da = Math.abs(cand[i].a - out[j].a);
        if (da > Math.PI) da = TWO_PI - da;
        if (da < minSep) { ok = false; break; }
      }
      if (ok) out.push(cand[i]);
    }
    return out;
  }

  /**
   * Emit a sound of any kind. Returns the primary pulse (or null). No cooldown here.
   * opts {kind, range, strength, bounces 0..2, visRays, z (default 0.5), fade (default state.fade)}. Bounce children are pushed after the primary.
   */
  function emitSound(state, world, x, y, t, opts) {
    const o = opts || {};
    if (!state || !world || typeof x !== 'number' || typeof y !== 'number' || !isFinite(x) || !isFinite(y)) return null;
    const range = typeof o.range === 'number' && o.range > 0 ? o.range : state.range;
    let strength = typeof o.strength === 'number' && isFinite(o.strength) ? o.strength : 1;
    strength = Math.max(0, Math.min(1, strength));
    const bounces = typeof o.bounces === 'number' && o.bounces > 0 ? Math.min(2, Math.floor(o.bounces)) : 0;
    const rays = typeof o.visRays === 'number' && o.visRays >= 8 ? Math.floor(o.visRays) : 360;
    const kind = typeof o.kind === 'string' ? o.kind : 'ping';
    const z = typeof o.z === 'number' && isFinite(o.z) ? Math.max(0, Math.min(1.2, o.z)) : 0.5;
    const fade = typeof o.fade === 'number' && isFinite(o.fade) && o.fade > 0 ? o.fade : state.fade;
    const primary = makePulse(world, x, y, t, range, state.speed, strength, kind, 0, rays, z, fade);
    const made = [primary];
    if (bounces > 0) {
      const maxRefl = state.reflectors || 6;
      let layer = [primary];
      for (let gen = 1; gen <= bounces && made.length < MAX_PER_SOUND; gen++) {
        const next = [];
        for (let li = 0; li < layer.length && made.length < MAX_PER_SOUND; li++) {
          const par = layer[li];
          const refl = pickReflectors(par, maxRefl);
          for (let r = 0; r < refl.length && made.length < MAX_PER_SOUND; r++) {
            const cr = par.range - refl[r].d;
            if (cr < 1.5) continue;
            const ca = refl[r].a;
            const hx = par.x + Math.cos(ca) * refl[r].d;
            const hy = par.y + Math.sin(ca) * refl[r].d;
            const ox = hx - Math.cos(ca) * 0.08;
            const oy = hy - Math.sin(ca) * 0.08;
            const child = makePulse(world, ox, oy, par.t0 + refl[r].d / par.speed, cr, par.speed, par.strength * 0.45, kind, gen, 180, par.z, par.fade * 0.8);
            made.push(child);
            next.push(child);
          }
        }
        layer = next;
      }
    }
    const ps = state.pulses;
    for (let i = 0; i < made.length; i++) ps.push(made[i]);
    if (ps.length > state.maxPulses) ps.splice(0, ps.length - state.maxPulses);
    return primary;
  }

  /** Start a pulse at (x,y) at time t (the click ping); false if still cooling down. */
  function emit(state, world, x, y, t, opts) {
    if (t - state.lastEmit < state.cooldown) return false;
    const o = { kind: 'ping', range: state.range, strength: 1, bounces: state.bounces, visRays: state.visRays };
    if (opts && typeof opts.z === 'number') o.z = opts.z;
    if (opts && typeof opts.fade === 'number') o.fade = opts.fade;
    const pulse = emitSound(state, world, x, y, t, o);
    if (!pulse) return false;
    state.lastEmit = t;
    state.lastPulse = pulse;
    const log = logger();
    if (log) log.debug('pulse at ' + x.toFixed(2) + ',' + y.toFixed(2) + ' nearest ' + nearestDist(pulse).toFixed(2));
    return true;
  }

  /** Minimum visible distance of a pulse (for echo timing). */
  function nearestDist(pulse) {
    const v = pulse.vis;
    let m = Infinity;
    for (let i = 0; i < v.length; i++) if (v[i] < m) m = v[i];
    return m;
  }

  let scanAge = -1; // age of the strongest pulse found by the last scan (no allocation)
  let scanFade = 0; // fade (s) of that pulse
  let scanIdx = -1; // index of that pulse in state.pulses

  /** Shared hot loop: returns best brightness, leaves its age in scanAge (fade in scanFade, index in scanIdx). */
  function scan(state, px, py, pz, t) {
    const ps = state.pulses;
    const sfade = state.fade;
    let best = 0;
    scanAge = -1;
    scanFade = 0;
    scanIdx = -1;
    for (let i = 0; i < ps.length; i++) {
      const p = ps[i];
      const dx = px - p.x;
      const dy = py - p.y;
      const dh2 = dx * dx + dy * dy;
      const dz = pz - (p.z === undefined ? 0.5 : p.z);
      const d2 = dh2 + dz * dz;
      if (d2 > p.range * p.range) continue;
      const rr = (t - p.t0) * p.speed;
      if (rr < 0 || d2 > rr * rr) continue;
      const d = Math.sqrt(d2);
      const fade = p.fade === undefined ? sfade : p.fade;
      const age = t - (p.t0 + d / p.speed);
      if (age >= fade) continue;
      const vis = p.vis;
      const n = vis.length;
      let a = Math.atan2(dy, dx);
      if (a < 0) a += TWO_PI;
      let idx = Math.round(a / TWO_PI * n);
      if (idx >= n) idx -= n;
      if (Math.sqrt(dh2) > vis[idx] + TOL) continue;
      let b = 1 - age / fade;
      b = b * b * (1 - 0.5 * d / p.range);
      if (p.strength !== undefined) b *= p.strength;
      if (b > best) { best = b; scanAge = age; scanFade = fade; scanIdx = i; }
    }
    return best;
  }

  /**
   * One pass at (px,py,pz): writes out[0]=brightness, out[1]=age since the wavefront arrived (-1 if unlit),
   * out[2]=fade (s) of the strongest pulse there (0 if unlit), out[3]=its index in state.pulses (-1 if unlit).
   * Same maths as brightnessAt3 + ageAt3 in a single scan. Never throws; bad input writes "unlit".
   */
  function sample3(state, px, py, pz, t, out) {
    let b = 0;
    try {
      if (state && Array.isArray(state.pulses) && state.pulses.length) b = scan(state, px, py, pz, t);
    } catch (e) {
      b = 0;
    }
    if (b > 0) { out[0] = b; out[1] = scanAge; out[2] = scanFade; out[3] = scanIdx; }
    else { out[0] = 0; out[1] = -1; out[2] = 0; out[3] = -1; }
    return b;
  }

  /**
   * One pass over the pulses for a wall point: writes out[0]=brightness at z=0, out[1]=brightness at z=1,
   * out[2]=age of the strongest of the two (-1 if unlit), and, when out has a 4th slot, out[3]=fade (s) of
   * that pulse (0 if unlit). Same maths as brightnessAt3/ageAt3, a third of the work.
   */
  function sample2(state, px, py, t, out) {
    const ps = state.pulses;
    const sfade = state.fade;
    let b0 = 0;
    let b1 = 0;
    let a0 = -1;
    let a1 = -1;
    let f0 = 0;
    let f1 = 0;
    for (let i = 0; i < ps.length; i++) {
      const p = ps[i];
      const rr = (t - p.t0) * p.speed;
      if (rr < 0) continue;
      const dx = px - p.x;
      const dy = py - p.y;
      const dh2 = dx * dx + dy * dy;
      const range = p.range;
      if (dh2 > range * range || dh2 > rr * rr + 1.5) continue; // |dz| < 1.22 for any z in 0..1.2
      const pz = p.z === undefined ? 0.5 : p.z;
      const fade = p.fade === undefined ? sfade : p.fade;
      const vis = p.vis;
      const n = vis.length;
      let a = Math.atan2(dy, dx);
      if (a < 0) a += TWO_PI;
      let idx = Math.round(a / TWO_PI * n);
      if (idx >= n) idx -= n;
      if (Math.sqrt(dh2) > vis[idx] + TOL) continue;
      const mul = p.strength === undefined ? 1 : p.strength;
      for (let e = 0; e < 2; e++) {
        const dz = e - pz;
        const d2 = dh2 + dz * dz;
        if (d2 > range * range || d2 > rr * rr) continue;
        const d = Math.sqrt(d2);
        const age = t - (p.t0 + d / p.speed);
        if (age >= fade) continue;
        let b = 1 - age / fade;
        b = b * b * (1 - 0.5 * d / range) * mul;
        if (e === 0) { if (b > b0) { b0 = b; a0 = age; f0 = fade; } } else if (b > b1) { b1 = b; a1 = age; f1 = fade; }
      }
    }
    out[0] = b0;
    out[1] = b1;
    const lit = b0 > 0 || b1 > 0;
    const useLo = b0 >= b1;
    out[2] = lit ? (useLo ? a0 : a1) : -1;
    if (out.length > 3) out[3] = lit ? (useLo ? f0 : f1) : 0;
  }

  /** Brightness 0..1 of world point (px,py) at height pz (0 floor .. 1 ceiling) at time t. */
  function brightnessAt3(state, px, py, pz, t) {
    return scan(state, px, py, pz, t);
  }

  /** Age in seconds of the strongest pulse at (px,py,pz), or -1 if unlit. */
  function ageAt3(state, px, py, pz, t) {
    return scan(state, px, py, pz, t) > 0 ? scanAge : -1;
  }

  /** Brightness 0..1 of world point (px,py) at time t (eye height 0.5). */
  function brightnessAt(state, px, py, t) {
    return scan(state, px, py, 0.5, t);
  }

  /** Age in seconds (since the wavefront arrived) of the strongest pulse at P, or -1 if unlit. */
  function ageAt(state, px, py, t) {
    return ageAt3(state, px, py, 0.5, t);
  }

  /**
   * Height band lit on the vertical line at (px,py): sphere of radius R = min(ring, range) around the source.
   * Writes out[0]=zLow, out[1]=zHigh (clamped 0..1.2) and returns true, else false.
   */
  function heightBand(pulse, t, px, py, out) {
    const dx = px - pulse.x;
    const dy = py - pulse.y;
    const dh2 = dx * dx + dy * dy;
    let R = (t - pulse.t0) * pulse.speed;
    if (R > pulse.range) R = pulse.range;
    if (R > 0 && R * R > dh2) {
      const dz = Math.sqrt(R * R - dh2);
      const z = pulse.z === undefined ? 0.5 : pulse.z;
      const lo = z - dz;
      const hi = z + dz;
      out[0] = lo < 0 ? 0 : lo;
      out[1] = hi > 1.2 ? 1.2 : hi;
      return true;
    }
    return false;
  }

  /** True when world point (x,y) is visible from the pulse origin (same test as brightnessAt). */
  function visibleFrom(pulse, x, y) {
    const vis = pulse.vis;
    if (!vis || !vis.length) return true;
    const dx = x - pulse.x;
    const dy = y - pulse.y;
    const d = Math.sqrt(dx * dx + dy * dy);
    let a = Math.atan2(dy, dx);
    if (a < 0) a += TWO_PI;
    const n = vis.length;
    let idx = Math.round(a / TWO_PI * n);
    if (idx >= n) idx -= n;
    return d <= vis[idx] + TOL;
  }

  /** Time at which the wavefront of a pulse reaches world point (x,y) (no visibility check). */
  function litAt(pulse, x, y) {
    const dx = x - pulse.x;
    const dy = y - pulse.y;
    return pulse.t0 + Math.sqrt(dx * dx + dy * dy) / pulse.speed;
  }

  /** Current ring radius of a pulse at time t. */
  function ringRadius(pulse, t) {
    return (t - pulse.t0) * pulse.speed;
  }

  /**
   * Water-ripple arcs on a wall point: for k in 0..trail-1, ring radius R = ringRadius - k*0.35;
   * if R > dh writes [zLow, zHigh] (wall spans 0..1, centred on pulse.z) at out[2k], out[2k+1], else NaN.
   * Returns the count of arcs written. Fade factor per k is (1 - k/trail).
   */
  function wallArc(pulse, t, hitX, hitY, trail, out) {
    const dx = hitX - pulse.x;
    const dy = hitY - pulse.y;
    const dh2 = dx * dx + dy * dy;
    const ring = (t - pulse.t0) * pulse.speed;
    const zc = pulse.z === undefined ? 0.5 : pulse.z;
    let count = 0;
    for (let k = 0; k < trail; k++) {
      const R = ring - k * 0.35;
      if (R * R > dh2 && R > 0) {
        const dz = Math.sqrt(R * R - dh2);
        const lo = zc - dz;
        const hi = zc + dz;
        out[2 * k] = lo < 0 ? 0 : lo;
        out[2 * k + 1] = hi > 1 ? 1 : hi;
        count++;
      } else {
        out[2 * k] = NaN;
        out[2 * k + 1] = NaN;
      }
    }
    return count;
  }

  /** Remove pulses that have fully faded. */
  function prune(state, t) {
    const ps = state.pulses;
    let w = 0;
    for (let i = 0; i < ps.length; i++) if (t - ps[i].t0 <= ps[i].range / ps[i].speed + (ps[i].fade === undefined ? state.fade : ps[i].fade)) ps[w++] = ps[i];
    ps.length = w;
  }

  const Sonar = {
    DEFAULTS: DEFAULTS, create: create, emit: emit, emitSound: emitSound, wallArc: wallArc, nearestDist: nearestDist,
    brightnessAt: brightnessAt, ageAt: ageAt, brightnessAt3: brightnessAt3, sample2: sample2, sample3: sample3, ageAt3: ageAt3, heightBand: heightBand, visibleFrom: visibleFrom, litAt: litAt, ringRadius: ringRadius, prune: prune, reset: reset, cooldownLeft: cooldownLeft
  };
  VCS.Sonar = Sonar;
  if (typeof module !== 'undefined' && module.exports) module.exports = Sonar;
})(typeof window !== 'undefined' ? window : globalThis);
