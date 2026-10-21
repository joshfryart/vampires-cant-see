(function (root) {
  'use strict';
  const VCS = (root.VCS = root.VCS || {});

  // Whole-body circulatory pulse, phase 1: vessel graph data and pure helpers (no DOM, no game state).
  // Nothing in the game reads this yet; render/people wiring comes in later phases behind `vis.vessels`.
  //
  // Each node sits on a drawPerson pose slot (0 head, 1 neck, 2/3 shoulders, 4/5 hips, 6/7 hands, 8/9 feet,
  // 10/11 elbows, 12/13 knees, 14 torso), or between two slots: point = lerp(slot -> to, t). The heart is
  // lerp(14 -> 1, 0.45). pathLen is metres of artery from the heart (adult ~1.7 m), w the pulse strength as a
  // fraction of the heart, hot the hotspot bloom (+60% carotid = 0.6), periph 0..1 how much cold or fear
  // constriction dims it, head true where wary brightens it (neck, temple).

  function deepFreeze(o) {
    if (o && typeof o === 'object' && !Object.isFrozen(o)) {
      Object.freeze(o);
      Object.keys(o).forEach(function (k) { deepFreeze(o[k]); });
    }
    return o;
  }

  function node(id, parent, slot, to, t, pathLen, w, hot, periph, head) {
    return { id: id, parent: parent, slot: slot, to: to, t: t, pathLen: pathLen, w: w, hot: hot, periph: periph, head: !!head, vein: false };
  }

  // id, parent, slot, to, t, pathLen m, w, hot, periph, head
  const ARTERIES = [
    node('heart', null, 14, 1, 0.45, 0, 1, 0.5, 0),
    node('arch', 'heart', 14, 1, 0.75, 0.1, 0.9, 0, 0),
    node('carotid', 'arch', 1, 1, 0, 0.25, 0.75, 0.6, 0, true),
    node('temporal', 'carotid', 0, 0, 0, 0.4, 0.5, 0.25, 0.2, true),
    node('subclavL', 'arch', 2, 2, 0, 0.3, 0.6, 0, 0.1),
    node('subclavR', 'arch', 3, 3, 0, 0.3, 0.6, 0, 0.1),
    node('brachialL', 'subclavL', 10, 10, 0, 0.6, 0.45, 0.25, 0.4),
    node('brachialR', 'subclavR', 11, 11, 0, 0.6, 0.45, 0.25, 0.4),
    node('radialL', 'brachialL', 6, 6, 0, 0.9, 0.35, 0.35, 1),
    node('radialR', 'brachialR', 7, 7, 0, 0.9, 0.35, 0.35, 1),
    node('aorta', 'arch', 14, 14, 0, 0.45, 0.7, 0, 0),
    node('femoralL', 'aorta', 4, 4, 0, 0.7, 0.6, 0.4, 0),
    node('femoralR', 'aorta', 5, 5, 0, 0.7, 0.6, 0.4, 0),
    node('poplitealL', 'femoralL', 12, 12, 0, 0.95, 0.4, 0.15, 0.4),
    node('poplitealR', 'femoralR', 13, 13, 0, 0.95, 0.4, 0.15, 0.4),
    node('pedalL', 'poplitealL', 8, 8, 0, 1.35, 0.25, 0.2, 1),
    node('pedalR', 'poplitealR', 9, 9, 0, 1.35, 0.25, 0.2, 1)
  ];

  // Veins mirror the arteries (same anchors, own ids), drawn deeper red-blue with a slow drift, no sharp pulse.
  const VEINS = ARTERIES.map(function (a) {
    return {
      id: 'v_' + a.id, parent: a.parent ? 'v_' + a.parent : null, slot: a.slot, to: a.to, t: a.t,
      pathLen: a.pathLen, w: Math.round(a.w * 0.5 * 1000) / 1000, hot: 0, periph: a.periph, head: false, vein: true
    };
  });

  // Mode table (villager `mode` names). bpm before blood loss, stateK overall strength, periphK extra factor on
  // peripheral nodes (fear constricts hands/feet), headK on neck/temple (wary).
  const MODES = {
    calm: { bpm: 65, stateK: 1, periphK: 1, headK: 1 },
    wary: { bpm: 90, stateK: 1.15, periphK: 1, headK: 1.25 },
    startle: { bpm: 100, stateK: 1.3, periphK: 0.8, headK: 1.1 },
    flee: { bpm: 130, stateK: 1.5, periphK: 0.5, headK: 1 },
    cower: { bpm: 130, stateK: 1.5, periphK: 0.5, headK: 1 },
    sleep: { bpm: 52, stateK: 0.8, periphK: 1, headK: 1 },
    drinking: { bpm: 120, stateK: 1, periphK: 1, headK: 1 },
    fed: { bpm: 0, stateK: 0, periphK: 0, headK: 0 },
    drained: { bpm: 0, stateK: 0, periphK: 0, headK: 0 }
  };

  const VesselData = {
    PWV: 6,               // m/s pulse wave velocity, adult (child 5, old 8-9)
    PWV_SCALE: 1.75,      // slow the wave 1.5-2x so travel reads; feet still lag head
    BPM_MAX: 175,         // < 3 Hz flash cap
    DUB_DELAY: 0.3,       // s after lub
    DUB_K: 0.3,           // dub strength vs lub
    ATTACK: 0.06,         // s envelope rise
    DECAY: 0.25,          // s envelope tau
    VEIN_DRIFT: 0.2,      // m/s venous tint drift
    REST_BPM: 65,         // bpm the dub delay is quoted at
    DUB_K_FAST: 0.15,     // dub strength at the bpm cap (fades from DUB_K above DUB_FADE_BPM, keeps flashes soft)
    DUB_FADE_BPM: 120,
    VEIN_LAG: 0.08,       // s veins start after the arterial launch
    VEIN_SLOW: 1.25,       // venous swell travels this much slower than the arterial wave
    VEIN_ATTACK: 0.1,     // s venous swell rise
    VEIN_DECAY: 0.3,      // s venous swell tau
    SOFT_ATTACK: 0.1,     // reduced motion: one soft pulse, no travel
    SOFT_DECAY: 0.3,
    TAIL: 0.2,            // s smooth fade-out at the end of the vessel life
    LIFE_TAUS: 1.2,       // life ends this many decay taus after the last arrival (rest ~1 s)
    ARTERY_RGB: [200, 32, 36],
    VEIN_RGB: [104, 34, 92],
    HEART: { slot: 14, to: 1, t: 0.45 },
    arteries: ARTERIES,
    veins: VEINS,
    modes: MODES
  };

  deepFreeze(VesselData);

  function all() { return ARTERIES.concat(VEINS); }

  function byId(id) {
    for (let i = 0; i < ARTERIES.length; i++) if (ARTERIES[i].id === id) return ARTERIES[i];
    for (let i = 0; i < VEINS.length; i++) if (VEINS[i].id === id) return VEINS[i];
    return null;
  }

  /** Screen point of a node from pose slot arrays X, Y: lerp(slot -> to, t). Writes into out (or a new object). */
  function anchor(n, X, Y, out) {
    const o = out || { x: 0, y: 0 };
    const a = n.slot;
    const b = n.to === undefined ? a : n.to;
    const t = n.t || 0;
    o.x = X[a] + (X[b] - X[a]) * t;
    o.y = Y[a] + (Y[b] - Y[a]) * t;
    return o;
  }

  /** Arrival delay (s) per node: pathLen * pwvScale / pwv. */
  function delays(pwv, pwvScale, nodes) {
    const v = pwv > 0 ? pwv : VesselData.PWV;
    const m = pwvScale > 0 ? pwvScale : VesselData.PWV_SCALE;
    const list = nodes || ARTERIES;
    return list.map(function (n) { return n.pathLen * m / v; });
  }

  /** Base falloff weight per node (fraction of the heart, no hotspot). */
  function weights(nodes) {
    return (nodes || ARTERIES).map(function (n) { return n.w; });
  }

  function capBpm(bpm) {
    if (!(bpm > 0)) return 0;
    return Math.min(VesselData.BPM_MAX, bpm);
  }

  function clamp01(x) { return x < 0 ? 0 : x > 1 ? 1 : x; }

  /**
   * Pulse state for a body. kind 'vampire' never pulses (undead: anatomy only, no heartbeat, no blood).
   * mode is a villager mode name (unknown = calm); blood is left/pool 0..1 (default 1).
   * Blood loss: strength ~ blood^1.5, extremities dim first (periphK ~ blood, on top of stateK, so hands/feet ~ blood^2.5), bpm rises then collapses
   * below 40% blood, stops at empty. Drinking uses the drink formula 50 + 70 * blood.
   * Returns { pulse, bpm, stateK, periphK, headK }.
   */
  function state(kind, mode, blood) {
    if (kind === 'vampire') return { pulse: false, bpm: 0, stateK: 0, periphK: 0, headK: 0 };
    const m = MODES[mode] || MODES.calm;
    const f = blood === undefined ? 1 : clamp01(blood);
    if (m.bpm === 0 || f <= 0) return { pulse: false, bpm: 0, stateK: 0, periphK: 0, headK: 0 };
    let bpm;
    if (mode === 'drinking') bpm = 50 + 70 * f;
    else if (f >= 0.4) bpm = m.bpm * (1 + 0.3 * (1 - f) / 0.6);
    else bpm = m.bpm * 1.3 * (f / 0.4);
    return {
      pulse: true,
      bpm: capBpm(bpm),
      stateK: m.stateK * Math.pow(f, 1.5),
      periphK: m.periphK * f,
      headK: m.headK
    };
  }

  /** Peak strength of one node's lub: w * (1 + hot) * stateK * lerp(1, periphK, periph) * (head ? headK : 1). Veins skip hot. */
  function strength(n, st) {
    if (!st || !st.pulse) return 0;
    const p = n.periph || 0;
    const per = 1 - p + p * st.periphK;
    const k = n.vein ? n.w : n.w * (1 + n.hot);
    return k * st.stateK * per * (n.head ? st.headK : 1);
  }

  /** Vessel model per body kind. Vampire: same anatomy, pulse and blood false. */
  function forBody(kind) {
    const vamp = kind === 'vampire';
    return { kind: vamp ? 'vampire' : 'villager', nodes: all(), pulse: !vamp, blood: !vamp };
  }

  // ---- P4 travelling pulse: pure timing helpers ----
  const DELAY_CACHE = {};

  /** Arrival delays (s) for arteries and veins at pwvScale (cached). Veins: VEIN_LAG + arterial delay x VEIN_SLOW. */
  function travel(pwvScale) {
    const m = pwvScale > 0 ? pwvScale : VesselData.PWV_SCALE;
    const key = String(m);
    let c = DELAY_CACHE[key];
    if (c) return c;
    const art = delays(VesselData.PWV, m, ARTERIES);
    const vein = delays(VesselData.PWV, m, VEINS).map(function (d) { return VesselData.VEIN_LAG + d * VesselData.VEIN_SLOW; });
    c = { art: art, vein: vein, artMax: Math.max.apply(null, art), veinMax: Math.max.apply(null, vein) };
    DELAY_CACHE[key] = c;
    return c;
  }

  /** Envelope 0..1 at t s after arrival: smoothstep rise over attack, then exp decay with tau. 0 before arrival. */
  function envelope(t, attack, tau) {
    if (!(t >= 0)) return 0;
    if (t < attack) { const k = t / attack; return k * k * (3 - 2 * k); }
    return Math.exp(-(t - attack) / tau);
  }

  /**
   * Beat timing for a bpm (<= BPM_MAX). dub: delay of the dicrotic ripple after the lub (DUB_DELAY at REST_BPM, shrinks
   * ~1/sqrt(bpm), never past 45% of the beat period); dubK: its strength (DUB_K, fading to DUB_K_FAST at the cap so a fast
   * heart stays one strong flash per beat). life: seconds until the last node (dub at the feet, or the venous swell)
   * has decayed; reduced: no travel, one soft pulse.
   */
  function timing(bpm, reduced, pwvScale) {
    const D = VesselData;
    const b = bpm > 0 ? capBpm(bpm) : D.REST_BPM;
    if (reduced) return { dub: 0, dubK: 0, life: D.SOFT_ATTACK + 2 * D.SOFT_DECAY, reduced: true };
    let dub = D.DUB_DELAY * Math.min(1.1, Math.sqrt(D.REST_BPM / b));
    dub = Math.min(dub, 0.45 * 60 / b);
    const f = clamp01((b - D.DUB_FADE_BPM) / (D.BPM_MAX - D.DUB_FADE_BPM));
    const dubK = D.DUB_K + (D.DUB_K_FAST - D.DUB_K) * f;
    const tr = travel(pwvScale);
    const art = tr.artMax + dub + D.ATTACK + D.LIFE_TAUS * D.DECAY;
    const vein = tr.veinMax + D.VEIN_ATTACK + D.LIFE_TAUS * D.VEIN_DECAY;
    return { dub: dub, dubK: dubK, life: Math.max(art, vein), reduced: false };
  }

  /**
   * Pulse 0..~1 of node index i (in arteries or veins, by vein) at age s after the beat, for timing tm (from timing()).
   * Arteries: lub env(age - d) + dubK env(age - d - dub). Veins: one slower, later swell. Reduced: env(age), no delay.
   * Includes the smooth tail fade so nothing pops off at tm.life.
   */
  function pulse(vein, i, age, tm, pwvScale) {
    const D = VesselData;
    if (!(age >= 0) || !tm || age >= tm.life) return 0;
    const left = tm.life - age;
    const tail = left < D.TAIL ? (left / D.TAIL) * (left / D.TAIL) * (3 - 2 * left / D.TAIL) : 1;
    if (tm.reduced) return envelope(age, D.SOFT_ATTACK, D.SOFT_DECAY) * tail;
    const tr = travel(pwvScale);
    if (vein) return envelope(age - tr.vein[i], D.VEIN_ATTACK, D.VEIN_DECAY) * tail;
    const t = age - tr.art[i];
    return (envelope(t, D.ATTACK, D.DECAY) + tm.dubK * envelope(t - tm.dub, D.ATTACK, D.DECAY)) * tail;
  }

  // ---- P5 edges: geometry on drawPerson's limb curves, travelling highlight position ----
  // drawPerson draws each limb as one quadratic curve root -> (control = elbow/knee slot) -> end. A node on a control
  // slot (elbow 10/11, knee 12/13) is drawn at the curve midpoint so it sits on the limb; an edge between the limb
  // root and the joint, or the joint and the end, is the matching half of that curve (de Casteljau split at 0.5).
  const LIMB = { 10: [2, 6], 11: [3, 7], 12: [4, 8], 13: [5, 9] };

  function limbOf(n) {
    return n && (n.to === undefined || n.to === n.slot) && !n.t ? LIMB[n.slot] || null : null;
  }

  /** Screen point of a node: Vessels.anchor, except elbow/knee nodes sit on the limb curve midpoint. */
  function point(n, X, Y, out) {
    const L = limbOf(n);
    if (!L) return anchor(n, X, Y, out);
    const o = out || { x: 0, y: 0 };
    const c = n.slot;
    o.x = 0.25 * X[L[0]] + 0.5 * X[c] + 0.25 * X[L[1]];
    o.y = 0.25 * Y[L[0]] + 0.5 * Y[c] + 0.25 * Y[L[1]];
    return o;
  }

  /**
   * Control point of the edge parent -> child when it runs along a limb curve (writes out, returns true), else
   * false (straight segment). Root -> joint: (root + C) / 2; joint -> end: (C + end) / 2.
   */
  function edgeCtrl(parent, child, X, Y, out) {
    let L = limbOf(child);
    if (L && parent.slot === L[0] && !parent.t) {
      out.x = 0.5 * (X[L[0]] + X[child.slot]);
      out.y = 0.5 * (Y[L[0]] + Y[child.slot]);
      return true;
    }
    L = limbOf(parent);
    if (L && child.slot === L[1] && !child.t) {
      out.x = 0.5 * (X[parent.slot] + X[L[1]]);
      out.y = 0.5 * (Y[parent.slot] + Y[L[1]]);
      return true;
    }
    return false;
  }

  /** Point at s (0..1) on the edge a -> b (quadratic through ctrl when given, else straight). */
  function edgeAt(a, ctrl, b, s, out) {
    const o = out || { x: 0, y: 0 };
    if (ctrl) {
      const u = 1 - s;
      o.x = u * u * a.x + 2 * u * s * ctrl.x + s * s * b.x;
      o.y = u * u * a.y + 2 * u * s * ctrl.y + s * s * b.y;
    } else {
      o.x = a.x + (b.x - a.x) * s;
      o.y = a.y + (b.y - a.y) * s;
    }
    return o;
  }

  const EDGE_CACHE = {};
  /** Edges of the artery (vein false) or vein tree as [{ i: child index, p: parent index }] (cached, frozen). */
  function edges(vein) {
    const key = vein ? 'v' : 'a';
    if (EDGE_CACHE[key]) return EDGE_CACHE[key];
    const list = vein ? VEINS : ARTERIES;
    const out = [];
    for (let i = 0; i < list.length; i++) {
      if (!list[i].parent) continue;
      for (let j = 0; j < list.length; j++) if (list[j].id === list[i].parent) { out.push(Object.freeze({ i: i, p: j })); break; }
    }
    EDGE_CACHE[key] = Object.freeze(out);
    return EDGE_CACHE[key];
  }

  /**
   * Travelling highlight position on an edge: (age - dParent) / (dChild - dParent). < 0 not yet launched, > 1 passed.
   * A zero-length delay span (same arrival) is all-or-nothing.
   */
  function edgeFront(age, dParent, dChild) {
    const span = dChild - dParent;
    if (!(span > 1e-6)) return age >= dParent ? 1 : -1;
    return (age - dParent) / span;
  }

  const Vessels = {
    data: VesselData,
    point: point,
    edgeCtrl: edgeCtrl,
    edgeAt: edgeAt,
    edges: edges,
    edgeFront: edgeFront,
    travel: travel,
    envelope: envelope,
    timing: timing,
    pulse: pulse,
    all: all,
    byId: byId,
    anchor: anchor,
    delays: delays,
    weights: weights,
    capBpm: capBpm,
    state: state,
    strength: strength,
    forBody: forBody
  };

  VCS.VesselData = VesselData;
  VCS.Vessels = Vessels;
  if (typeof module !== 'undefined' && module.exports) module.exports = Vessels;
})(typeof window !== 'undefined' ? window : globalThis);
