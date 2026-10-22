'use strict';
/**
 * Figure: volumetric villager drawing (v0.15, anatomy v0.17). Pure drawing on a 2D ctx from pose slots, no state of its own.
 *
 * v0.17 anatomy: every body part is a closed outline polygon (drawn as a smooth curve through its edge midpoints):
 * - torso: one hull from the neck base over the trapezius slope, shoulders, ribcage, waist and pelvis to the crotch,
 *   built from per-body cross sections (lateral half-width, depth, forward offset) seen at the figure's yaw;
 * - limbs: swept along the SAME quadratic curve the line figure and the vessel overlay use (root -> elbow/knee slot as
 *   control -> end), split at t = 0.5 (where the elbow/knee vessel node sits) with muscle profiles (deltoid, biceps,
 *   forearm, thigh, kneecap, calf, ankle), so arteries and veins run down the limb centrelines;
 * - hands: a palm with a thumb lobe and finger hints; shoes: heel, instep and a slightly upturned toe;
 * - head: cranium with jaw and chin (profile-aware), plus ears, brows, eyes, nose and a mood mouth in the details.
 * The line figure's details (hair, hats, scarf, hem, props, cower fingers, dazed stars) are redrawn on top.
 * No per-frame allocation: parts, polygons and scratch are preallocated at load. Public functions never throw.
 *
 * P is the pose slot set {X, Y, Z} (typed arrays, also accepted as {x, y, z}); slots 0..23 as in render.js, 24/25 are
 * the extra grip/tip when present (else a fallback near the hand is used). Z is optional (0 when absent), larger = farther.
 */
(function (root) {
  const VCS = root.VCS = root.VCS || {};
  const NOOP = { info() {}, warn() {}, error() {}, debug() {} };
  let logger = null;
  let logged = 0;
  function log() {
    if (logger) return logger;
    try { logger = VCS.Log && VCS.Log.get ? VCS.Log.get('figure') : NOOP; } catch (e) { logger = NOOP; }
    return logger || NOOP;
  }
  function fail(where, e) {
    if (logged++ < 3) { try { log().warn('Figure.' + where + ' failed: ' + (e && e.message)); } catch (e2) { /* ignore */ } }
  }

  const TWO_PI = Math.PI * 2;
  const MAXP = 16;
  /** Outline points per part (torso hull 22, limb segment <= 26, head 24, hand 14, shoe 12). */
  const MAXPTS = 40;
  const COL_RIM = '#ffcf8a';
  const COL_FLUSH = '#ff8a78';
  const BLACK = '#000000';

  function num(v, d) { return typeof v === 'number' && isFinite(v) ? v : d; }
  function clamp(v, a, b) { return v < a ? a : v > b ? b : v; }
  function hasCtx(c) { return !!c && typeof c.moveTo === 'function' && typeof c.stroke === 'function'; }
  function lerp(a, b, t) { return a + (b - a) * t; }
  /** Child factor 0..1 from look.height: 1 at 0.66 and below, 0 from 0.82 (same as render.js kidK). */
  function kidK(lh) { return clamp((0.82 - lh) / 0.16, 0, 1); }

  // ---------------------------------------------------------------- capsule

  /**
   * Add a tapered-capsule outline subpath (two tangent lines plus two arcs). A circle when the points coincide or one
   * circle contains the other. Returns true when something was added. (Grab arms; kept public.)
   */
  function capsule(c, x0, y0, r0, x1, y1, r1) {
    try {
      if (!hasCtx(c) || typeof c.arc !== 'function') return false;
      if (!(isFinite(x0) && isFinite(y0) && isFinite(x1) && isFinite(y1) && isFinite(r0) && isFinite(r1))) return false;
      r0 = Math.max(0, r0);
      r1 = Math.max(0, r1);
      const dx = x1 - x0;
      const dy = y1 - y0;
      const L = Math.sqrt(dx * dx + dy * dy);
      if (L < 1e-9 || Math.abs(r0 - r1) >= L) {
        const big = r1 > r0;
        const cx = big ? x1 : x0;
        const cy = big ? y1 : y0;
        const r = big ? r1 : r0;
        c.moveTo(cx + r, cy);
        c.arc(cx, cy, r, 0, TWO_PI);
        return true;
      }
      const a = Math.atan2(dy, dx);
      const beta = Math.acos(clamp((r0 - r1) / L, -1, 1));
      const aP = a + beta;
      const aM = a - beta;
      c.moveTo(x0 + r0 * Math.cos(aP), y0 + r0 * Math.sin(aP));
      c.arc(x1, y1, r1, aP, aM, true);
      c.lineTo(x0 + r0 * Math.cos(aM), y0 + r0 * Math.sin(aM));
      c.arc(x0, y0, r0, aM, aP, true);
      c.closePath();
      return true;
    } catch (e) { fail('capsule', e); return false; }
  }

  /** Ellipse subpath that always starts with a moveTo at angle 0 (so it never joins the previous subpath). */
  function ell(c, x, y, rx, ry, rot) {
    rx = Math.max(0.01, rx);
    ry = Math.max(0.01, ry);
    c.moveTo(x + rx * Math.cos(rot), y + rx * Math.sin(rot));
    c.ellipse(x, y, rx, ry, rot, 0, TWO_PI);
  }

  // ---------------------------------------------------------------- measurements

  function arrX(P) { return P && (P.X || P.x); }
  function arrY(P) { return P && (P.Y || P.y); }
  function arrZ(P) { return P && (P.Z || P.z); }

  /** Scratch measurements shared by parts / draw / extras. Filled by measure(); never allocated per call. */
  const M = {
    lh: 1, bw: 1, hs: 1, vs: 1, vsy: 1, sr: 0, cr: 1, shoulder: 1, kid: 0, fs: 1,
    sx: 0, sy: 0, hx: 0, hy: 0, r0: 1, r1: 1, shS: 0.062, hipS: 0.04,
    crU: 1, srU: 0, crL: 1, srL: 0, armK: 1, legK: 1, neckR: 1,
    hr: 1, hry: 1, bodyRx: 1, bodyRy: 1, hipU: 0, belt: 0, beltX0: 0, beltY0: 0, beltX1: 0, beltY1: 0, beltCx: 0, beltCy: 0
  };

  function bodyShS(look) {
    const b = look && look.body;
    return b === 'round' ? 0.075 : b === 'stick' ? 0.05 : b === 'pear' ? 0.05 : 0.062;
  }
  function bodyHipS(look) {
    const b = look && look.body;
    return b === 'pear' ? 0.055 : b === 'round' ? 0.06 : b === 'stick' ? 0.03 : 0.04;
  }

  /** Per body kind: [chest, waist, belly depth, hip width, seat, depth, arm thickness, leg thickness]. */
  const BODY = {
    bean: [1.0, 0.9, 1.12, 1.0, 1.0, 1.0, 1.0, 1.0],
    pear: [0.92, 1.0, 1.15, 1.18, 1.28, 1.0, 0.95, 1.12],
    stick: [0.9, 0.74, 1.45, 0.9, 0.8, 0.85, 0.8, 0.82],
    round: [1.08, 1.24, 1.6, 1.05, 1.1, 1.15, 1.18, 1.12],
    box: [1.08, 1.05, 1.0, 1.02, 1.0, 1.0, 1.08, 1.05]
  };
  function bodyRow(look) {
    const b = look && look.body;
    return b === 'pear' || b === 'stick' || b === 'round' || b === 'box' ? BODY[b] : BODY.bean;
  }

  function measure(P, pose, look) {
    const X = arrX(P);
    const Y = arrY(P);
    const lh = clamp(num(pose && pose.lh, num(look && look.height, 1)), 0.3, 2);
    const bw = clamp(num(look && look.build, 1), 0.4, 2);
    M.lh = lh;
    M.bw = bw;
    M.kid = kidK(lh);
    let hs = num(pose && pose.hs, 0);
    let vs = num(pose && pose.vs, 0);
    if (!(vs > 0)) {
      const fy = (Y[8] + Y[9]) * 0.5;
      vs = Math.max(1, Math.abs(fy - Y[0]) / (0.9 * lh));
    }
    if (!(hs > 0)) hs = vs;
    M.hs = hs;
    M.vs = vs;
    M.vsy = num(pose && pose.vsy, vs);
    M.shoulder = clamp(num(look && look.shoulder, 1), 0.8, 1.25);
    M.sx = (X[2] + X[3]) * 0.5;
    M.sy = (Y[2] + Y[3]) * 0.5;
    M.hx = (X[4] + X[5]) * 0.5;
    M.hy = (Y[4] + Y[5]) * 0.5;
    const swid = Math.sqrt((X[2] - X[3]) * (X[2] - X[3]) + 0.04 * (Y[2] - Y[3]) * (Y[2] - Y[3])) * 0.5;
    const hwid = Math.sqrt((X[4] - X[5]) * (X[4] - X[5]) + 0.04 * (Y[4] - Y[5]) * (Y[4] - Y[5])) * 0.5;
    const shS = Math.max(0.01, num(pose && pose.shS, bodyShS(look) * bw));
    const hipS = Math.max(0.01, num(pose && pose.hipS, bodyHipS(look) * bw));
    M.shS = shS;
    M.hipS = hipS;
    // Yaw of the trunk from the slot spreads (a held victim twists the shoulders more than the hips).
    M.crU = clamp(swid / (shS * hs + 1e-6), 0, 1);
    M.srU = Math.sqrt(1 - M.crU * M.crU);
    M.crL = clamp(hwid / (hipS * hs + 1e-6), 0, 1);
    M.srL = Math.sqrt(1 - M.crL * M.crL);
    let sr = num(pose && pose.sr, NaN);
    let cr = num(pose && pose.cr, NaN);
    if (!isFinite(sr) || !isFinite(cr)) { cr = M.crU; sr = M.srU; }
    M.sr = Math.abs(sr);
    M.cr = Math.abs(cr);
    M.fs = sr < 0 ? -1 : 1;
    const row = bodyRow(look);
    const kid = M.kid;
    M.armK = row[6] * (0.7 + 0.3 * bw) * (1 + 0.18 * kid);
    M.legK = row[7] * (0.6 + 0.4 * bw) * (1 + 0.15 * kid);
    M.neckR = (look && look.body === 'stick' ? 0.026 : look && look.body === 'round' ? 0.034 : 0.03) * lh * (1 + 0.1 * kid);
    const hk = 1 + 0.25 * kid;
    M.hr = Math.max(0.5, num(pose && pose.hr, 0.088 * lh * Math.sqrt(bw) * hs)) * hk;
    M.hry = Math.max(0.5, num(pose && pose.hry, 0.092 * lh * vs)) * hk;
    M.bodyRx = Math.max(1, num(pose && pose.bodyRx, swid));
    M.bodyRy = Math.max(1, Math.abs(M.hy - M.sy) * 0.5);
    M.r0 = Math.max(1, swid);
    M.r1 = Math.max(1, hwid);
    M.hipU = num(pose && pose.hipU, 0);
    M.belt = 0;
    return M;
  }

  // ---------------------------------------------------------------- parts

  function mkPart() {
    return {
      kind: '', a: 0, b: 0, r0: 0, r1: 0, z: 0, ax: 0, ay: 0, bx: 0, by: 0,
      n: 0, px: new Float64Array(MAXPTS), py: new Float64Array(MAXPTS), y0: 0, y1: 0,
      nw: 0, wx: new Float64Array(3), wy: new Float64Array(3), wr: new Float64Array(3), wa: new Float64Array(3),
      ux: 0, uy: 0, vx: 0, vy: 0, rh: 0, jx: 0, jy: 0, bend: 0, ns: 0
    };
  }
  /** Preallocated part pools: POOL for draw, HPOOL for hit / spanAt / flush (so a query never disturbs a draw). */
  const POOL = [];
  const HPOOL = [];
  for (let i = 0; i < MAXP; i++) { POOL.push(mkPart()); HPOOL.push(mkPart()); }

  function begin(out, i, kind, a, b, z) {
    let p = out[i];
    if (!p || !p.px || p.px.length < MAXPTS) p = out[i] = mkPart();
    p.kind = kind; p.a = a; p.b = b; p.z = z; p.n = 0; p.nw = 0; p.ns = 0;
    return p;
  }
  function pushPt(p, x, y) {
    if (p.n >= MAXPTS) return;
    p.px[p.n] = x; p.py[p.n] = y; p.n++;
  }
  function pushRing(p, x, y, r, a) {
    if (p.nw >= 3) return;
    p.wx[p.nw] = x; p.wy[p.nw] = y; p.wr[p.nw] = r; p.wa[p.nw] = a; p.nw++;
  }
  function finish(p) {
    let y0 = Infinity;
    let y1 = -Infinity;
    for (let i = 0; i < p.n; i++) { const y = p.py[i]; if (y < y0) y0 = y; if (y > y1) y1 = y; }
    p.y0 = y0; p.y1 = y1;
  }

  // Torso cross sections: u from the shoulder line (0) to the hip line (1), extrapolated above and below.
  const TU = [-0.3, -0.15, 0.0, 0.1, 0.28, 0.52, 0.76, 0.95, 1.1, 1.21];
  const NT = TU.length;
  const TW = new Float64Array(NT);
  const TD = new Float64Array(NT);
  const TF = new Float64Array(NT);
  const TLX = new Float64Array(NT); const TLY = new Float64Array(NT);
  const TRX = new Float64Array(NT); const TRY = new Float64Array(NT);

  /** Torso hull into part p. Writes M.r0 (chest), M.r1 (hips), M.bodyRx (waist) half-widths and the belt line. */
  function buildTorso(p, X, Y, look, pose, m) {
    const row = bodyRow(look);
    const kid = m.kid;
    const lh = m.lh;
    const chest = row[0] * (1 - 0.04 * kid);
    const waist = lerp(row[1], Math.max(row[1], 1.02), kid);
    const belly = row[2] * (1 + 0.25 * kid);
    const hipK = row[3];
    const seat = row[4];
    const dep = row[5];
    const sw = m.shS * m.shoulder;
    const hw = m.hipS;
    const dR = 0.024 * lh * m.armK;
    const tR = 0.042 * lh * m.legK;
    const nR = m.neckR;
    const stoop = clamp(num(look.stoop, 0), 0, 0.4);
    // Lopsided by person: one shoulder a touch broader (+-3.5%).
    const pid = num(pose.pid, 0);
    const wob = ((((pid * 37) % 7) + 7) % 7 - 3) / 3 * 0.035;
    TW[0] = nR * 1.08; TD[0] = nR * 1.05; TF[0] = -0.002;
    TW[1] = lerp(nR, sw + 0.5 * dR, 0.42); TD[1] = 0.046 + 0.025 * stoop; TF[1] = -0.006 - 0.05 * stoop;
    TW[2] = sw + 0.75 * dR; TD[2] = 0.056 + 0.03 * stoop; TF[2] = -0.004 - 0.06 * stoop;
    TW[3] = sw + 0.95 * dR; TD[3] = 0.064 + 0.02 * stoop; TF[3] = 0.002 - 0.035 * stoop;
    TW[4] = sw * chest + 0.5 * dR; TD[4] = 0.07 * dep; TF[4] = 0.01;
    TW[5] = lerp(sw, hw + tR * 0.6, 0.5) * waist; TD[5] = 0.06 * belly * dep; TF[5] = 0.008 * belly;
    TW[6] = (hw + tR * 0.75) * lerp(waist, hipK, 0.6); TD[6] = 0.064 * belly * dep; TF[6] = 0.012 * belly - 0.003;
    TW[7] = (hw + tR * 0.88) * hipK; TD[7] = 0.066 * dep * seat; TF[7] = -0.008 * seat;
    TW[8] = (hw + tR * 0.74) * hipK; TD[8] = 0.062 * seat; TF[8] = -0.014 * seat;
    TW[9] = hw * 0.55 + tR * 0.35; TD[9] = 0.04; TF[9] = -0.004;
    const sx = m.sx; const sy = m.sy; const hx = m.hx; const hy = m.hy;
    let ax = hx - sx;
    let ay = hy - sy;
    let L = Math.sqrt(ax * ax + ay * ay);
    if (L < 1e-6) { ax = 0; ay = 1; L = 1; } else { ax /= L; ay /= L; }
    // Normal pointing to screen +x (so forward offsets go along +sr).
    let nx = -ay;
    let ny = ax;
    if (nx < 0) { nx = -nx; ny = -ny; }
    const hs = m.hs;
    const fs = m.fs;
    const axAng = Math.atan2(ay, ax);
    for (let i = 0; i < NT; i++) {
      const u = TU[i];
      const k = clamp(u, 0, 1);
      const crI = lerp(m.crU, m.crL, k);
      const srI = lerp(m.srU, m.srL, k);
      const e = hs * Math.sqrt(TW[i] * crI * TW[i] * crI + TD[i] * srI * TD[i] * srI);
      const f = TF[i] * hs * srI * fs;
      const cx = sx + (hx - sx) * u + nx * f;
      const cy = sy + (hy - sy) * u + ny * f;
      const w = i >= 2 && i <= 4 ? wob : 0;
      TRX[i] = cx + nx * e * (1 - w); TRY[i] = cy + ny * e * (1 - w);
      TLX[i] = cx - nx * e * (1 + w); TLY[i] = cy - ny * e * (1 + w);
      if (i === 4) m.r0 = Math.max(1, e);
      if (i === 5) m.bodyRx = Math.max(1, e);
      if (i === 7) m.r1 = Math.max(1, e);
    }
    pushPt(p, (TLX[0] + TRX[0]) * 0.5 - ax * L * 0.03, (TLY[0] + TRY[0]) * 0.5 - ay * L * 0.03);
    for (let i = 0; i < NT; i++) pushPt(p, TRX[i], TRY[i]);
    const by = 1.27;
    pushPt(p, sx + (hx - sx) * by + nx * TF[9] * hs * m.srL * fs, sy + (hy - sy) * by + ny * TF[9] * hs * m.srL * fs);
    for (let i = NT - 1; i >= 0; i--) pushPt(p, TLX[i], TLY[i]);
    // One wrap ring between the ribcage and the waist.
    {
      const cx = (TLX[4] + TRX[4] + TLX[5] + TRX[5]) * 0.25;
      const cy = (TLY[4] + TRY[4] + TLY[5] + TRY[5]) * 0.25;
      pushRing(p, cx, cy, (Math.hypot(TRX[4] - TLX[4], TRY[4] - TLY[4]) + Math.hypot(TRX[5] - TLX[5], TRY[5] - TLY[5])) * 0.25, axAng);
    }
    // Waistband (trousers) between sections 6 and 7.
    m.belt = 1;
    m.beltX0 = lerp(TLX[6], TLX[7], 0.45); m.beltY0 = lerp(TLY[6], TLY[7], 0.45);
    m.beltX1 = lerp(TRX[6], TRX[7], 0.45); m.beltY1 = lerp(TRY[6], TRY[7], 0.45);
    m.beltCx = (m.beltX0 + m.beltX1) * 0.5; m.beltCy = (m.beltY0 + m.beltY1) * 0.5;
    p.ax = sx; p.ay = sy; p.bx = hx; p.by = hy; p.r0 = m.r0; p.r1 = m.r1;
    finish(p);
  }

  // Limb profiles over the whole root -> end curve (t 0..1): radius and forward bulge, in lh units (x hs on screen).
  const ARM_T = [0, 0.1, 0.24, 0.4, 0.5, 0.6, 0.72, 0.88, 1];
  const ARM_R = [0.024, 0.023, 0.021, 0.017, 0.0155, 0.0175, 0.017, 0.0135, 0.012];
  const ARM_A = [0, 0.002, 0.003, 0.0005, -0.002, 0.002, 0.001, 0, 0];
  const LEG_T = [0, 0.12, 0.28, 0.42, 0.5, 0.58, 0.68, 0.82, 0.93, 1];
  const LEG_R = [0.042, 0.04, 0.035, 0.029, 0.026, 0.028, 0.029, 0.022, 0.016, 0.016];
  const LEG_A = [0, 0.002, 0.002, 0.001, 0.003, -0.002, -0.006, -0.003, 0, 0];
  const NECK_T = [0, 1];
  const NECK_R = [1.12, 0.96];
  const NECK_A = [0, 0];
  const SHAFT_R = [1, 1];

  function prof(T, V, t) {
    if (t <= T[0]) return V[0];
    for (let i = 1; i < T.length; i++) {
      if (t <= T[i]) { const k = (t - T[i - 1]) / (T[i] - T[i - 1]); return V[i - 1] + (V[i] - V[i - 1]) * k; }
    }
    return V[V.length - 1];
  }

  const LX = new Float64Array(16); const LY = new Float64Array(16);
  const RX = new Float64Array(16); const RY = new Float64Array(16);
  const TAN = { x: 0, y: 1 };
  /** Unit tangent of the quadratic A -> C -> E at t into TAN (falls back to the chord, then straight down). */
  function tangent(Ax, Ay, Cx, Cy, Ex, Ey, t) {
    let dx = 2 * (1 - t) * (Cx - Ax) + 2 * t * (Ex - Cx);
    let dy = 2 * (1 - t) * (Cy - Ay) + 2 * t * (Ey - Cy);
    let L = Math.sqrt(dx * dx + dy * dy);
    if (L < 1e-6) { dx = Ex - Ax; dy = Ey - Ay; L = Math.sqrt(dx * dx + dy * dy); }
    if (L < 1e-6) { TAN.x = 0; TAN.y = 1; return; }
    TAN.x = dx / L; TAN.y = dy / L;
  }

  /**
   * Sweep a tapered outline along the quadratic A -> C -> E between t0 and t1 into part p. Radius = prof(T, R, t) x k
   * (+-) bulge prof(T, A, t) x k x the normal's screen-forward component (so calves and kneecaps show in profile).
   * Round caps at both ends. Rings at 35 %, 50 %, 70 % of the segment. K = samples per side - 1.
   */
  function sweep(p, Ax, Ay, Cx, Cy, Ex, Ey, t0, t1, T, R, A, k, fwd, K) {
    p.ns = K;
    let lastNx = 1;
    let lastNy = 0;
    for (let s = 0; s <= K; s++) {
      const t = t0 + (t1 - t0) * s / K;
      const u = 1 - t;
      const bx = u * u * Ax + 2 * u * t * Cx + t * t * Ex;
      const by = u * u * Ay + 2 * u * t * Cy + t * t * Ey;
      tangent(Ax, Ay, Cx, Cy, Ex, Ey, t);
      let nx = -TAN.y;
      let ny = TAN.x;
      if (!isFinite(nx) || !isFinite(ny)) { nx = lastNx; ny = lastNy; }
      lastNx = nx; lastNy = ny;
      const r = prof(T, R, t) * k;
      const a = prof(T, A, t) * k * nx * fwd;
      let rl = r + a;
      let rr = r - a;
      // On the inside of a bend keep the offset within the radius of curvature (no folded-over knees or elbows).
      {
        const dx = 2 * (1 - t) * (Cx - Ax) + 2 * t * (Ex - Cx);
        const dy = 2 * (1 - t) * (Cy - Ay) + 2 * t * (Ey - Cy);
        const cr = dx * 2 * (Ay - 2 * Cy + Ey) - dy * 2 * (Ax - 2 * Cx + Ex);
        const L2 = dx * dx + dy * dy;
        if (L2 > 1e-9 && Math.abs(cr) > 1e-12) {
          const rc = 0.85 * L2 * Math.sqrt(L2) / Math.abs(cr);
          if (cr > 0) { if (rl > rc) rl = rc; } else if (rr > rc) rr = rc;
        }
      }
      LX[s] = bx + nx * rl; LY[s] = by + ny * rl;
      RX[s] = bx - nx * rr; RY[s] = by - ny * rr;
      // Inside a tight bend an offset edge would run backwards and loop: hold it at the previous point instead.
      if (s > 0) {
        if ((LX[s] - LX[s - 1]) * TAN.x + (LY[s] - LY[s - 1]) * TAN.y < 0) { LX[s] = LX[s - 1]; LY[s] = LY[s - 1]; }
        if ((RX[s] - RX[s - 1]) * TAN.x + (RY[s] - RY[s - 1]) * TAN.y < 0) { RX[s] = RX[s - 1]; RY[s] = RY[s - 1]; }
      }
    }
    for (let s = 0; s <= K; s++) pushPt(p, LX[s], LY[s]);
    // End cap: from the left edge round the tip to the right edge.
    {
      const t = t1;
      const u = 1 - t;
      const bx = u * u * Ax + 2 * u * t * Cx + t * t * Ex;
      const by = u * u * Ay + 2 * u * t * Cy + t * t * Ey;
      tangent(Ax, Ay, Cx, Cy, Ex, Ey, t);
      const r = prof(T, R, t) * k;
      const nx = -TAN.y; const ny = TAN.x;
      pushPt(p, bx + (nx * 0.7 + TAN.x * 0.7) * r, by + (ny * 0.7 + TAN.y * 0.7) * r);
      pushPt(p, bx + TAN.x * r, by + TAN.y * r);
      pushPt(p, bx + (-nx * 0.7 + TAN.x * 0.7) * r, by + (-ny * 0.7 + TAN.y * 0.7) * r);
      p.bx = bx; p.by = by; p.r1 = r;
    }
    for (let s = K; s >= 0; s--) pushPt(p, RX[s], RY[s]);
    {
      const t = t0;
      const u = 1 - t;
      const bx = u * u * Ax + 2 * u * t * Cx + t * t * Ex;
      const by = u * u * Ay + 2 * u * t * Cy + t * t * Ey;
      tangent(Ax, Ay, Cx, Cy, Ex, Ey, t);
      const r = prof(T, R, t) * k;
      const nx = -TAN.y; const ny = TAN.x;
      pushPt(p, bx + (-nx * 0.7 - TAN.x * 0.7) * r, by + (-ny * 0.7 - TAN.y * 0.7) * r);
      pushPt(p, bx - TAN.x * r, by - TAN.y * r);
      pushPt(p, bx + (nx * 0.7 - TAN.x * 0.7) * r, by + (ny * 0.7 - TAN.y * 0.7) * r);
      p.ax = bx; p.ay = by; p.r0 = r;
    }
    // Wrap rings on the upper (t 0.25) and lower (t 0.75) halves; joint frame at t 0.5 (elbow / knee).
    for (let q = 0; q < 2; q++) {
      const t = t0 + (t1 - t0) * (q === 0 ? 0.25 : 0.75);
      const u = 1 - t;
      tangent(Ax, Ay, Cx, Cy, Ex, Ey, t);
      pushRing(p, u * u * Ax + 2 * u * t * Cx + t * t * Ex, u * u * Ay + 2 * u * t * Cy + t * t * Ey, prof(T, R, t) * k, Math.atan2(TAN.y, TAN.x));
    }
    {
      // Third ring: sleeve / trouser cuff near the wrist or ankle.
      const t = t0 + (t1 - t0) * 0.84;
      const u = 1 - t;
      tangent(Ax, Ay, Cx, Cy, Ex, Ey, t);
      pushRing(p, u * u * Ax + 2 * u * t * Cx + t * t * Ex, u * u * Ay + 2 * u * t * Cy + t * t * Ey, prof(T, R, t) * k * 1.04, Math.atan2(TAN.y, TAN.x));
    }
    {
      const t = (t0 + t1) * 0.5;
      const u = 1 - t;
      tangent(Ax, Ay, Cx, Cy, Ex, Ey, t);
      p.jx = u * u * Ax + 2 * u * t * Cx + t * t * Ex; p.jy = u * u * Ay + 2 * u * t * Cy + t * t * Ey;
      p.ux = TAN.x; p.uy = TAN.y; p.vx = -TAN.y; p.vy = TAN.x; p.rh = prof(T, R, t) * k;
      // Signed bend: cross of the chords root -> control and control -> end.
      const c1 = (Cx - Ax) * (Ey - Cy) - (Cy - Ay) * (Ex - Cx);
      const l1 = Math.hypot(Cx - Ax, Cy - Ay) * Math.hypot(Ex - Cx, Ey - Cy);
      p.bend = l1 > 1e-9 ? c1 / l1 : 0;
    }
    finish(p);
  }

  // Head outline samples.
  const NH = 24;
  const HCOS = new Float64Array(NH);
  const HSIN = new Float64Array(NH);
  for (let i = 0; i < NH; i++) { HCOS[i] = Math.cos(i / NH * TWO_PI); HSIN[i] = Math.sin(i / NH * TWO_PI); }

  /** Head: cranium with a jaw and chin that follow the face direction (sin yaw = pose.noseX). */
  function buildHead(p, hx, hy, hk, pose, m) {
    const sY = clamp(num(pose.noseX, 0), -1, 1);
    const aY = Math.abs(sY);
    const kid = m.kid;
    const rx = m.hr * (hk === 'square' ? 0.95 : 0.9);
    const ry = m.hry;
    const rot = num(pose.tilt, 0) * 0.6;
    const cR = Math.cos(rot);
    const sR = Math.sin(rot);
    const jaw = (hk === 'square' ? 0.08 : hk === 'long' ? 0.24 : hk === 'egg' ? 0.2 : 0.2) * (1 - 0.55 * kid);
    for (let i = 0; i < NH; i++) {
      const c = HCOS[i];
      const s = HSIN[i];
      let x = c;
      let y = s;
      if (hk === 'square') {
        x = (c < 0 ? -1 : 1) * Math.pow(Math.abs(c), 0.62);
        y = (s < 0 ? -1 : 1) * Math.pow(Math.abs(s), 0.62);
      }
      if (hk === 'egg') x *= s < 0 ? 1 + 0.08 * -s : 1 - 0.1 * s;
      const back = x * sY < 0;
      if (s > 0) {
        x *= 1 - jaw * s * s;
        x += sY * 0.16 * s * s * s * (1 - 0.5 * kid);
        if (back) x *= 1 - 0.22 * aY * s;
        y *= 1 + 0.1 * s * s * s * s * (1 - 0.6 * kid);
      } else if (back) {
        x *= 1 + 0.08 * aY;
      } else {
        // Brow ridge in profile.
        x += sY * 0.05 * Math.max(0, 1 - Math.abs(s + 0.3) * 4);
      }
      const lx = x * rx;
      const ly = y * ry;
      pushPt(p, hx + lx * cR - ly * sR, hy + lx * sR + ly * cR);
    }
    p.ax = hx; p.ay = hy; p.bx = hx; p.by = hy; p.r0 = rx; p.r1 = ry;
    finish(p);
  }

  // Hand (mitten) outline: (along the forearm, across toward the thumb), in hand radii.
  const HAND_A = [-0.5, -0.05, 0.35, 0.75, 0.82, 0.5, 0.95, 1.32, 1.46, 1.4, 1.15, 0.6, 0.0, -0.5];
  const HAND_C = [0.52, 0.75, 1.02, 1.0, 0.74, 0.55, 0.6, 0.46, 0.1, -0.3, -0.62, -0.72, -0.66, -0.52];

  function buildHand(p, X, Y, s, m, rh) {
    const A = 2 + s; const C = 10 + s; const E = 6 + s;
    tangent(X[A], Y[A], X[C], Y[C], X[E], Y[E], 1);
    const ux = TAN.x;
    const uy = TAN.y;
    let vx = -uy;
    let vy = ux;
    // Thumb toward the body's front in profile, toward the middle seen head-on.
    const medial = X[14] - X[E];
    const want = m.fs * m.sr * 1.5 + (medial < 0 ? -1 : 1) * (1 - m.sr);
    if (vx * want < 0) { vx = -vx; vy = -vy; }
    const hx = X[E];
    const hy = Y[E];
    for (let i = 0; i < HAND_A.length; i++) pushPt(p, hx + (ux * HAND_A[i] + vx * HAND_C[i]) * rh, hy + (uy * HAND_A[i] + vy * HAND_C[i]) * rh);
    p.ax = hx; p.ay = hy; p.bx = hx + ux * rh; p.by = hy + uy * rh; p.r0 = rh; p.r1 = rh;
    p.ux = ux; p.uy = uy; p.vx = vx; p.vy = vy; p.rh = rh;
    finish(p);
  }

  // Shoe outlines (toe along +a, sole at +v): profile and head-on, blended by |sin yaw|.
  const SHOE_PA = [-0.62, -0.9, -0.95, -0.72, -0.38, 0.0, 0.4, 0.78, 1.04, 1.0, 0.75, 0.1];
  const SHOE_PV = [0.95, 0.62, 0.05, -0.55, -0.95, -0.82, -0.52, -0.34, -0.06, 0.5, 0.95, 1.0];
  const SHOE_FA = [-0.86, -1.0, -0.98, -0.8, -0.42, 0.0, 0.42, 0.8, 0.98, 1.0, 0.86, 0.0];
  const SHOE_FV = [0.95, 0.55, 0.0, -0.45, -0.78, -0.86, -0.78, -0.45, 0.0, 0.55, 0.95, 1.0];

  function buildFoot(p, X, Y, s, m) {
    const F = 8 + s;
    const pw = clamp((m.sr - 0.1) / 0.6, 0, 1);
    const sl = Math.sqrt(m.lh);
    const Lp = m.hs * (0.064 * sl * Math.pow(m.legK, 0.3)) + 1;
    const Lf = m.hs * (0.033 * sl * Math.pow(m.legK, 0.5)) + 1;
    const L = lerp(Lf, Lp, pw);
    const H = Math.max(1.2, m.vs * 0.022 * sl);
    const td = m.fs;
    const cx = X[F] + m.sr * td * m.hs * 0.03;
    const cy = Y[F];
    for (let i = 0; i < SHOE_PA.length; i++) {
      const a = lerp(SHOE_FA[i], SHOE_PA[i], pw);
      const v = lerp(SHOE_FV[i], SHOE_PV[i], pw);
      pushPt(p, cx + td * a * L, cy + v * H);
    }
    p.ax = cx; p.ay = cy; p.bx = cx + td * L; p.by = cy; p.r0 = L; p.r1 = H;
    finish(p);
  }

  /**
   * Fill out[0..n) with up to 16 parts {kind, a, b, r0, r1, z, ax, ay, bx, by, n, px, py} (a/b are slot ids; the torso
   * uses 2 and 4). px/py hold the closed outline (n points) the part is drawn through. Kinds: torso, neck, per side
   * leg, foot, arm, hand, then head, then the shovel shaft ('extra'). Legs and arms are single outlines along their
   * whole curve (the knee / elbow is the curve midpoint, t 0.5); jx/jy, ux/uy, vx/vy, rh hold that joint's frame. Returns n.
   */
  function parts(P, pose, look, out) {
    try {
      const X = arrX(P);
      const Y = arrY(P);
      if (!X || !Y || X.length < 24 || Y.length < 24 || !Array.isArray(out)) return 0;
      look = look || {};
      pose = pose || {};
      const Z = arrZ(P);
      const m = measure(P, pose, look);
      const zf = function (k) { return Z ? num(Z[k], 0) : 0; };
      const lhs = m.lh * m.hs;
      const figPx = Math.abs(Y[8] - Y[0]) + Math.abs(Y[9] - Y[0]);
      const K = figPx > 160 ? 12 : figPx > 60 ? 8 : 5;
      const fwd = m.fs * m.sr;
      let n = 0;
      const tz = (zf(2) + zf(3) + zf(4) + zf(5)) * 0.25;
      buildTorso(begin(out, n++, 'torso', 2, 4, tz), X, Y, look, pose, m);
      {
        // Neck from slot 1 to just inside the jaw (the head outline covers its end), behind the torso and the head.
        const p = begin(out, n++, 'neck', 1, 0, (zf(1) + zf(0)) * 0.5 + 0.03);
        const dN = Math.hypot(X[0] - X[1], Y[0] - Y[1]);
        const kN = dN > 1e-6 ? clamp((dN - m.hry * 0.9 + m.neckR * m.hs * 0.5) / dN, 0.25, 0.8) : 0.5;
        const ex = X[1] + (X[0] - X[1]) * kN;
        const ey = Y[1] + (Y[0] - Y[1]) * kN;
        sweep(p, X[1], Y[1], (X[1] + ex) * 0.5, (Y[1] + ey) * 0.5, ex, ey, 0, 1, NECK_T, NECK_R, NECK_A, m.neckR * m.hs, 0, 2);
      }
      for (let s = 0; s < 2; s++) {
        const h = 4 + s; const kn = 12 + s; const f = 8 + s;
        const lk = lhs * m.legK;
        // One outline per leg along the hip -> knee -> foot curve, drawn over the pelvis (its root stroke is masked
        // inside the torso, so the thighs continue the hips instead of hanging below a pair of briefs).
        sweep(begin(out, n++, 'leg', h, f, 0.35 * zf(h) + 0.45 * zf(kn) + 0.2 * zf(f) - 0.02), X[h], Y[h], X[kn], Y[kn], X[f], Y[f], 0, 1, LEG_T, LEG_R, LEG_A, lk, fwd, K);
        buildFoot(begin(out, n++, 'foot', f, f, zf(f) - 0.01), X, Y, s, m);
        const sh = 2 + s; const el = 10 + s; const hd = 6 + s;
        const ak = lhs * m.armK;
        sweep(begin(out, n++, 'arm', sh, hd, (zf(sh) + zf(el) + zf(hd)) / 3), X[sh], Y[sh], X[el], Y[el], X[hd], Y[hd], 0, 1, ARM_T, ARM_R, ARM_A, ak, fwd, K);
        const rh = Math.max(1.2, m.hs * 0.021 * Math.sqrt(m.lh) * (1 + 0.15 * m.kid) * Math.sqrt(m.armK));
        buildHand(begin(out, n++, 'hand', hd, hd, zf(hd) - 0.01), X, Y, s, m, rh);
      }
      buildHead(begin(out, n++, 'head', 0, 0, zf(0) - 0.08), X[0], Y[0], pose.headKind || look.head || 'round', pose, m);
      // n is 11 here; the twelfth part is the shovel shaft.
      if (look.extra === 'shovel' && X.length > 25) {
        const p = begin(out, n++, 'extra', 24, 25, Z && Z.length > 25 ? (num(Z[24], 0) + num(Z[25], 0)) * 0.5 : 0);
        sweep(p, X[24], Y[24], (X[24] + X[25]) * 0.5, (Y[24] + Y[25]) * 0.5, X[25], Y[25], 0, 1, NECK_T, SHAFT_R, NECK_A, Math.max(1, m.hs * 0.008), 0, 1);
      }
      return n;
    } catch (e) { fail('parts', e); return 0; }
  }

  /** In-place stable insertion sort by z, descending (farthest first). Returns the same array. */
  function sortBackToFront(arr, n) {
    try {
      if (!arr || typeof arr.length !== 'number') return arr;
      const len = Math.min(arr.length, typeof n === 'number' && n >= 0 ? Math.floor(n) : arr.length);
      for (let i = 1; i < len; i++) {
        const item = arr[i];
        if (!item) continue;
        const z = num(item.z, 0);
        let j = i - 1;
        while (j >= 0 && arr[j] && num(arr[j].z, 0) < z) { arr[j + 1] = arr[j]; j--; }
        arr[j + 1] = item;
      }
      return arr;
    } catch (e) { fail('sort', e); return arr; }
  }

  // ---------------------------------------------------------------- geometry queries

  /**
   * True when (x, y) is inside part p's outline. Tested against the polygon through the outline's edge midpoints, which
   * the drawn curve always encloses for these (locally convex) shapes, so a hit is inside what is drawn.
   */
  function contains(p, x, y) {
    if (!p || !(p.n >= 3)) return false;
    // Nonzero winding (the rule the fill uses), so a limb that folds over itself still counts as inside.
    const n = p.n;
    let wn = 0;
    let jx = (p.px[n - 1] + p.px[0]) * 0.5;
    let jy = (p.py[n - 1] + p.py[0]) * 0.5;
    for (let i = 0; i < n; i++) {
      const k = i === n - 1 ? 0 : i + 1;
      const ix = (p.px[i] + p.px[k]) * 0.5;
      const iy = (p.py[i] + p.py[k]) * 0.5;
      const cr = (ix - jx) * (y - jy) - (x - jx) * (iy - jy);
      if (jy <= y) { if (iy > y && cr > 0) wn++; } else if (iy <= y && cr < 0) wn--;
      jx = ix; jy = iy;
    }
    return wn !== 0;
  }


  /**
   * Kind of the front-most body part whose outline contains screen point (x, y), or '' (also for bad input). Uses its
   * own part pool, so it never disturbs a draw in progress. For tests and tools (silhouette / vessel checks).
   */
  function hit(P, pose, look, x, y) {
    try {
      const n = parts(P, pose, look, HPOOL);
      spanSig = NaN;
      let best = '';
      let bz = Infinity;
      for (let i = 0; i < n; i++) {
        const p = HPOOL[i];
        if (num(p.z, 0) <= bz && contains(p, x, y)) { bz = num(p.z, 0); best = p.kind; }
      }
      return best;
    } catch (e) { fail('hit', e); return ''; }
  }

  /** All part kinds containing (x, y), comma separated in part order ('' when none). Test helper. */
  function hitAll(P, pose, look, x, y) {
    try {
      const n = parts(P, pose, look, HPOOL);
      spanSig = NaN;
      let s = '';
      for (let i = 0; i < n; i++) if (contains(HPOOL[i], x, y)) s += (s ? ',' : '') + HPOOL[i].kind;
      return s;
    } catch (e) { fail('hitAll', e); return ''; }
  }

  /**
   * Horizontal extent of the whole silhouette at screen row y into out {x0, x1}. False when no part crosses the row.
   * Recomputes the parts into its own pool only when the slots changed since the last call (the band-front rings ask
   * up to three rows of the same figure per frame).
   */
  let spanSig = NaN;
  let spanN = 0;
  function spanAt(P, pose, look, y, out) {
    try {
      const X = arrX(P);
      const Y = arrY(P);
      if (!X || !Y || !out || !isFinite(y)) return false;
      const sig = X[0] + Y[0] * 3.1 + X[6] * 1.7 + Y[7] * 2.3 + X[8] * 0.7 + Y[9] * 1.3 + X[2] * 0.9 + num(pose && pose.hr, 0);
      if (sig !== spanSig) { spanN = parts(P, pose, look, HPOOL); spanSig = sig; }
      let x0 = Infinity;
      let x1 = -Infinity;
      for (let i = 0; i < spanN; i++) {
        const p = HPOOL[i];
        if (!(p.y0 <= y && p.y1 >= y)) continue;
        const n = p.n;
        for (let j = 0; j < n; j++) {
          const k = j === n - 1 ? 0 : j + 1;
          const ya = p.py[j]; const yb = p.py[k];
          if ((ya <= y) === (yb <= y)) continue;
          const x = p.px[j] + (p.px[k] - p.px[j]) * (y - ya) / (yb - ya);
          if (x < x0) x0 = x;
          if (x > x1) x1 = x;
        }
      }
      if (!(x1 >= x0)) return false;
      out.x0 = x0; out.x1 = x1;
      return true;
    } catch (e) { fail('spanAt', e); return false; }
  }

  // ---------------------------------------------------------------- draw

  function setHat(P, mode, hat, tilt, m, out) {
    const X = arrX(P);
    const Y = arrY(P);
    const fed = mode === 'fed' && hat !== 'hood';
    if (fed) {
      out.x = X[9] + m.hr * 2.6;
      out.y = Math.max(Y[8], Y[9]) - m.hry * 0.35;
      out.tilt = 0.9;
    } else {
      out.x = X[0];
      out.y = Y[0];
      out.tilt = num(tilt, 0);
    }
    out.fed = fed;
  }
  const HAT = { x: 0, y: 0, tilt: 0, fed: false };
  /** Parts in POOL from the draw in progress (details read the hands). */
  let drawN = 0;

  /** Smooth closed outline of part p: quadratic segments through its points, joining edge midpoints. */
  function emitPoly(c, p) {
    const n = p.n;
    if (n < 3) return;
    const px = p.px;
    const py = p.py;
    c.moveTo((px[n - 1] + px[0]) * 0.5, (py[n - 1] + py[0]) * 0.5);
    for (let i = 0; i < n; i++) {
      const j = i === n - 1 ? 0 : i + 1;
      c.quadraticCurveTo(px[i], py[i], (px[i] + px[j]) * 0.5, (py[i] + py[j]) * 0.5);
    }
    c.closePath();
  }

  /**
   * Limb roots: mark (HID) the outline points of an arm or leg near its root (the start cap and the first 40 % of both
   * sides) that lie inside the torso hull, so the stroke leaves them out and the limb grows out of the body instead of
   * showing a doll-joint circle at the shoulder or hip. The fill still covers the whole outline. Returns the count.
   */
  const HID = new Uint8Array(MAXPTS);
  function maskRoot(p, torso) {
    const n = p.n;
    const K = p.ns;
    for (let i = 0; i < n; i++) HID[i] = 0;
    if (!torso || !(K > 1) || n !== 2 * K + 8) return 0;
    const rs = Math.ceil(K * 0.4);
    let hid = 0;
    for (let i = 0; i < n; i++) {
      const root = i <= rs || i >= 2 * K + 4 - rs;
      if (root && contains(torso, p.px[i], p.py[i])) { HID[i] = 1; hid++; }
    }
    return hid;
  }
  /**
   * Torso hull: mark (HID) its lower points (hips, seat and crotch, outline points 8..14) that lie inside a leg drawn
   * over it, so the pelvis does not show a ghost of briefs through the thighs. Returns the count.
   */
  function maskPelvis(p, l0, l1) {
    const n = p.n;
    for (let i = 0; i < n; i++) HID[i] = 0;
    if (n !== 2 * NT + 2 || (!l0 && !l1)) return 0;
    let hid = 0;
    for (let i = 8; i <= 14; i++) {
      const x = p.px[i]; const y = p.py[i];
      if ((l0 && contains(l0, x, y)) || (l1 && contains(l1, x, y))) { HID[i] = 1; hid++; }
    }
    return hid;
  }
  /** Open outline of p through the points not marked in HID (same curve as emitPoly). */
  function emitMasked(c, p) {
    const n = p.n;
    const px = p.px;
    const py = p.py;
    let pen = false;
    for (let i = 0; i < n; i++) {
      if (HID[i]) { pen = false; continue; }
      const a = i === 0 ? n - 1 : i - 1;
      const b = i === n - 1 ? 0 : i + 1;
      if (!pen) { c.moveTo((px[a] + px[i]) * 0.5, (py[a] + py[i]) * 0.5); pen = true; }
      c.quadraticCurveTo(px[i], py[i], (px[i] + px[b]) * 0.5, (py[i] + py[b]) * 0.5);
    }
  }

  /** Rim: the runs of the outline whose outward normal faces the light side (+1 = screen right), tops not bottoms. */
  function rimPart(c, p, side, masked) {
    const n = p.n;
    if (n < 3) return;
    const px = p.px;
    const py = p.py;
    let area = 0;
    for (let i = 0; i < n; i++) { const j = i === n - 1 ? 0 : i + 1; area += px[i] * py[j] - px[j] * py[i]; }
    const o = area > 0 ? 1 : -1;
    let pen = false;
    for (let i = 0; i < n; i++) {
      const a = i === 0 ? n - 1 : i - 1;
      const b = i === n - 1 ? 0 : i + 1;
      const tx = px[b] - px[a];
      const ty = py[b] - py[a];
      const L = Math.sqrt(tx * tx + ty * ty) + 1e-9;
      // Outward normal for orientation o (screen y down): (ty, -tx) * o.
      const nx = ty / L * o;
      const ny = -tx / L * o;
      const lit = nx * side > 0.3 && ny < 0.75 && !(masked && HID[i]);
      if (lit) {
        if (!pen) { c.moveTo((px[a] + px[i]) * 0.5, (py[a] + py[i]) * 0.5); pen = true; }
        c.quadraticCurveTo(px[i], py[i], (px[i] + px[b]) * 0.5, (py[i] + py[b]) * 0.5);
      } else {
        pen = false;
      }
    }
  }

  function wrapRing(c, p, q, minorK) {
    const r = p.wr[q];
    const ang = p.wa[q];
    const cx = p.wx[q];
    const cy = p.wy[q];
    c.moveTo(cx + r * Math.cos(ang + Math.PI * 0.5), cy + r * Math.sin(ang + Math.PI * 0.5));
    c.ellipse(cx, cy, Math.max(0.01, r), Math.max(0.01, r * minorK), ang + Math.PI * 0.5, 0, Math.PI, true);
  }

  /** Sleeve / trouser cuff ring on this limb (not under robes or cloaks, not on mail sleeves). */
  function cuffOk(p, look, robe) {
    const k = p.kind;
    return (k === 'leg' || k === 'arm') && p.nw > 2 && !robe && look.outfit !== 'cloak' && !(k === 'arm' && look.outfit === 'mail');
  }

  /** Cloth creases fanning up from the belt line. */
  function torsoFolds(c, p, m, lw, alpha) {
    const ax = p.bx - p.ax;
    const ay = p.by - p.ay;
    const L = Math.sqrt(ax * ax + ay * ay);
    if (L < 8) return;
    const ux = ax / L;
    const uy = ay / L;
    const dx = m.beltX1 - m.beltX0;
    const dy = m.beltY1 - m.beltY0;
    const bw = Math.sqrt(dx * dx + dy * dy);
    if (bw < 4) return;
    c.globalAlpha = alpha * 0.45;
    c.lineWidth = lw * 0.7;
    c.beginPath();
    for (let i = 0; i < 3; i++) {
      const f = 0.28 + i * 0.22;
      const sx = m.beltX0 + dx * f;
      const sy = m.beltY0 + dy * f;
      const sgn = i === 0 ? -1 : i === 2 ? 1 : 0;
      const len = L * (0.2 + 0.05 * (i % 2));
      const ex = sx - ux * len + dx * sgn * 0.08;
      const ey = sy - uy * len + dy * sgn * 0.08;
      const bow = bw * 0.06 * (i === 1 ? 1 : -sgn);
      c.moveTo(sx, sy);
      c.quadraticCurveTo((sx + ex) * 0.5 - uy * bow, (sy + ey) * 0.5 + ux * bow, ex, ey);
    }
    c.stroke();
    c.lineWidth = lw;
    c.globalAlpha = alpha;
  }

  /** Hem height on screen for the robe / apron / smock / cloak, from look.hem (0 waist .. 1 ankle). */
  function hemY(m, look, dflt) {
    const hem = clamp(num(look.hem, dflt), 0, 1);
    const hipU = num(m.hipU, 0);
    const u = lerp(hipU - 0.17 * m.lh, 0.04 * m.lh, hem);
    return m.hy + (hipU - u) * m.vsy;
  }

  /**
   * Draw one figure: contact shadow, sorted body parts (occlusion fill at fx 2, contour, wrap lines, rim), then the
   * line-figure details on top. o = {fx, lw, alpha, rim:{side,k}, depth, reduced, front}. `front` is accepted but unused.
   */
  function draw(c, sa, style, P, pose, look, o) {
    if (!hasCtx(c)) return false;
    let saved = false;
    try {
      const X = arrX(P);
      const Y = arrY(P);
      if (!X || !Y || X.length < 24 || Y.length < 24) return false;
      pose = pose || {};
      look = look || {};
      o = o || {};
      sa = num(sa, 1);
      const fx = o.fx >= 2 ? 2 : o.fx >= 1 ? 1 : 0;
      const lw = Math.max(0.5, num(o.lw, 1));
      const alpha = clamp(num(o.alpha, 1) * sa, 0, 1);
      const depth = num(o.depth, num(pose.depth, 0));
      const near = depth < 6;
      const rim = o.rim;
      const rimK = rim ? num(rim.k, 0) : 0;
      const rimSide = rim && rim.side < 0 ? -1 : 1;
      const lod = num(pose.lod, 0);
      const cut = num(pose.minX, -1e5);
      const cutW = num(pose.maxX, 1e5) - cut;

      const n = parts(P, pose, look, POOL);
      drawN = n;
      const m = M; // filled by parts() -> measure(); includes the hull widths.
      const robe = look.outfit === 'robe';
      const robeY = robe ? hemY(m, look, 1) : 0;

      c.save();
      saved = true;
      c.lineJoin = 'round';
      c.lineCap = 'round';
      c.strokeStyle = style;

      // Contact shadow.
      {
        const fxm = (X[8] + X[9]) * 0.5;
        const fym = Math.max(Y[8], Y[9]) + Math.max(0.5, m.vs * 0.004);
        const rx = Math.max(1, 0.12 * m.hs * m.bw);
        const ry = Math.max(0.4, rx * 0.18);
        if (fx >= 2 && near) {
          c.globalAlpha = 0.4 * sa;
          c.fillStyle = BLACK;
          c.beginPath();
          ell(c, fxm, fym, rx, ry, 0);
          c.fill();
        }
        c.globalAlpha = clamp(0.2 * sa, 0, 1);
        c.lineWidth = lw;
        c.beginPath();
        c.moveTo(fxm - rx, fym);
        c.ellipse(fxm, fym, rx, ry, 0, Math.PI, TWO_PI, true);
        c.stroke();
      }

      sortBackToFront(POOL, n);
      let torsoP = null;
      let legA = null;
      let legB = null;
      for (let i = 0; i < n; i++) {
        const p = POOL[i];
        if (p.kind === 'torso') torsoP = p;
        else if (p.kind === 'leg' && torsoP) { if (legA) legB = p; else legA = p; }
      }
      const sy =num(pose.sinYaw, num(pose.noseX, 0));
      const minorK = 0.15 + 0.35 * Math.min(1, Math.abs(sy));
      for (let i = 0; i < n; i++) {
        const p = POOL[i];
        const leg = p.kind === 'leg';
        let clipped = false;
        if (robe && leg) {
          // Legs show below the hem only.
          if (p.y1 <= robeY) continue;
          if (p.y0 < robeY) {
            c.save();
            c.beginPath();
            c.rect(cut, robeY, cutW, 1e5);
            c.clip();
            clipped = true;
          }
        }
        const masked = fx >= 1 && near && ((leg || p.kind === 'arm') ? maskRoot(p, torsoP) > 0 : p === torsoP && !robe && maskPelvis(p, legA, legB) > 0);
        c.beginPath();
        emitPoly(c, p);
        if (fx >= 2 && near && p.kind !== 'extra') {
          c.globalAlpha = Math.min(1, 0.55 * sa);
          c.fillStyle = BLACK;
          c.fill();
        }
        if (masked) {
          c.beginPath();
          emitMasked(c, p);
        }
        c.globalAlpha = alpha;
        c.strokeStyle = style;
        c.lineWidth = lw;
        if (fx >= 1 && near && p.nw > 0 && (p.kind === 'torso' || leg || p.kind === 'arm')) {
          // fx 1: one ring per torso, leg and arm (upper half); fx 2: also the lower half of each limb.
          const dx = p.bx - p.ax;
          const dy = p.by - p.ay;
          if (dx * dx + dy * dy > p.r0 * p.r0 * 2) {
            wrapRing(c, p, 0, minorK);
            // The lower ring sits right above the cuff; only draw it where no cuff follows (fewer stacked bands).
            if (fx >= 2 && p.nw > 1 && !(lod >= 1 && cuffOk(p, look, robe))) wrapRing(c, p, 1, minorK);
          }
        }
        c.stroke();
        if (fx >= 1 && near && p.kind !== 'extra' && p.kind !== 'head') {
          // Shade side: a heavier contour on the side away from the light gives the flat outline some roundness.
          c.globalAlpha = clamp(0.55 * alpha, 0, 1);
          c.lineWidth = lw * 1.9;
          c.beginPath();
          rimPart(c, p, -rimSide, masked);
          c.stroke();
          c.lineWidth = lw;
          c.globalAlpha = alpha;
        }
        if (lod >= 1 && fx >= 1 && near) {
          if (cuffOk(p, look, robe)) {
            c.globalAlpha = alpha * 0.8;
            c.lineWidth = lw * 0.9;
            c.beginPath();
            wrapRing(c, p, 2, minorK);
            c.stroke();
            c.lineWidth = lw;
            c.globalAlpha = alpha;
          } else if (p.kind === 'torso' && lod >= 2 && m.belt && look.outfit !== 'robe' && look.outfit !== 'cloak') {
            torsoFolds(c, p, m, lw, alpha);
          }
        }
        if (rimK > 0.02 && near) {
          c.globalAlpha = clamp(0.5 * rimK * sa, 0, 1);
          c.strokeStyle = COL_RIM;
          c.lineWidth = lw * 0.8;
          c.beginPath();
          rimPart(c, p, rimSide, masked);
          c.stroke();
          c.strokeStyle = style;
        }
        if (clipped) c.restore();
      }

      // Details redrawn in the line figure's style.
      c.globalAlpha = alpha;
      c.strokeStyle = style;
      c.lineWidth = lw;
      c.beginPath();
      details(c, P, pose, look, m, lod, lw);
      c.stroke();
      if (pose.stars) {
        c.beginPath();
        const hr = m.hr;
        const hry = m.hry;
        const rr = Math.max(1.2, hr * 0.13);
        const tN = o.reduced ? 0 : num(pose.t, 0);
        const pid = num(pose.pid, 0);
        for (let k = 0; k < 3; k++) {
          const a = tN * 2.5 + k * 2.094 + pid;
          const sx = X[23] + Math.cos(a) * hr * 1.7;
          const sy2 = Y[23] - hry * 0.25 + Math.sin(a) * hry * 0.35;
          c.moveTo(sx - rr, sy2); c.lineTo(sx + rr, sy2);
          c.moveTo(sx, sy2 - rr); c.lineTo(sx, sy2 + rr);
        }
        c.stroke();
      }
      c.restore();
      saved = false;
      return true;
    } catch (e) {
      fail('draw', e);
      if (saved) { try { c.restore(); } catch (e2) { /* ignore */ } }
      return false;
    }
  }

  // ---------------------------------------------------------------- face

  /** Screen point of a head-surface feature (lateral l, forward f, down v; unit head) into FP {x, y, d}; d < 0 faces us. */
  const FP = { x: 0, y: 0, d: 0 };
  function facePt(hx, hy, rx, ry, sY, cY, rot, l, f, v) {
    const lx = (l * cY + f * sY) * rx;
    const ly = v * ry;
    const cR = Math.cos(rot);
    const sR = Math.sin(rot);
    FP.x = hx + lx * cR - ly * sR;
    FP.y = hy + lx * sR + ly * cR;
    FP.d = f * cY - l * sY;
  }

  /**
   * Per-archetype face character (v0.19). ew/eh eye size, gap eye spacing, ev eye height, bl brow lift (negative is
   * higher), bt brow inner tilt, bw brow length, heavy double brow, nose 0 wedge / 1 button / 2 hook / 3 bulb / 4 long,
   * mw mouth width, mc mouth curve (+ smile), lop lopsided grin, lid sleepy lids, bag under-eye bags, wr wrinkles,
   * ck cheek lines, lash lashes, rb one raised brow.
   */
  function face(o) {
    const d = { ew: 1, eh: 1, gap: 1, ev: 0, bl: 0, bt: 0, bw: 1, heavy: 0, nose: 0, mw: 1, mc: 0, lop: 0, lid: 0, bag: 0, wr: 0, ck: 0, lash: 0, rb: 0 };
    for (const k in o) d[k] = o[k];
    return d;
  }
  const FACE_DEF = face({});
  const FACE = {
    patron: face({ mc: 0.01 }),
    innkeeper: face({ nose: 1, mw: 1.3, mc: 0.035, ck: 1, ew: 0.9 }),
    drunk: face({ lid: 1, nose: 3, lop: 1, mw: 1.15, mc: 0.02, ck: 1, bl: 0.03 }),
    regular: face({ nose: 4, mw: 0.9, ev: 0.02, bt: -0.02 }),
    priest: face({ bl: -0.05, bw: 1.15, nose: 4, mw: 0.7, mc: -0.04, ew: 0.9, eh: 0.85, bt: -0.04 }),
    elder: face({ ew: 0.78, eh: 0.8, bt: -0.06, nose: 2, mw: 0.85, mc: -0.065, wr: 1, bag: 1 }),
    farmer: face({ nose: 3, mw: 1.3, mc: 0.04, ck: 1, gap: 1.06, heavy: 1 }),
    mother: face({ lash: 1, bl: -0.04, mc: 0.03, bt: -0.03, nose: 1, gap: 0.96 }),
    insomniac: face({ ew: 1.18, eh: 1.25, bag: 1, bl: -0.05, mc: -0.06, mw: 0.8 }),
    gravedigger: face({ bag: 1, nose: 4, mc: -0.085, mw: 0.85, bl: 0.04, heavy: 1, eh: 0.85 }),
    guard: face({ heavy: 1, bl: 0.05, bt: 0.05, mc: -0.05, mw: 1.1, eh: 0.8, gap: 1.05 }),
    child: face({ nose: 1, ck: 1, mc: 0.03, ew: 1.05, eh: 1.1 }),
    merchant: face({ rb: 1, lop: 1, nose: 4, mw: 1.05, mc: 0.02, eh: 0.9 }),
    hunter: face({ eh: 0.68, heavy: 1, bt: 0.07, bl: 0.03, nose: 2, mc: -0.04, mw: 0.9 })
  };

  /** Mood from the pose: 0 calm, 1 wide-eyed (startle, flee, held), 2 squeezed (cower), 3 closed (fed), 4 wary. */
  function mood(pose) {
    const md = pose.mode;
    if (md === 'fed') return 3;
    if (md === 'cower') return 2;
    if (md === 'startle' || md === 'flee' || md === 'grapple' || pose.flee) return 1;
    if (md === 'wary' || pose.wary) return 4;
    return 0;
  }

  /** Face, hair, hats, hem, seat edge, scarf, props, fingers, belt, clavicles and ears, as subpaths of the current path. */
  function details(c, P, pose, look, m, lod, lw) {
    const X = arrX(P);
    const Y = arrY(P);
    const hs = m.hs;
    const vs = m.vs;
    const lh = m.lh;
    const hr = m.hr;
    const hry = m.hry;
    const hx = X[0];
    const hy = Y[0];
    const bx = X[14];
    const by = Y[14];
    const bodyRx = m.bodyRx;
    const bodyRy = m.bodyRy;
    const mode = pose.mode;
    const noseX = clamp(num(pose.noseX, 0), -1, 1);
    const faceVis = pose.faceVis !== undefined ? !!pose.faceVis : true;
    const eyesVis = pose.eyesVis !== undefined ? !!pose.eyesVis : false;
    const flee = !!pose.flee || mode === 'flee';
    const moving = !!pose.moving;
    const jump = num(pose.jump, 0);
    const roleHat = look.roleHat && look.roleHat !== 'none' ? look.roleHat : '';
    const acc = look.acc;
    const hat = roleHat ? 'none' : (pose.hat || look.hat || (acc === 'tophat' || acc === 'nightcap' || acc === 'bonnet' ? acc : 'none'));
    const prop = pose.prop || look.prop || 'none';
    const outfit = look.outfit;
    const kid = m.kid;
    const rot = num(pose.tilt, 0) * 0.6;
    const hrx = hr * 0.9;
    let cY = num(pose.cosYaw, NaN);
    if (!isFinite(cY)) cY = (faceVis ? -1 : 1) * Math.sqrt(Math.max(0, 1 - noseX * noseX));
    const md = mood(pose);
    const F = typeof look.archetype === 'string' && Object.prototype.hasOwnProperty.call(FACE, look.archetype) ? FACE[look.archetype] : FACE_DEF;
    // Per-person asymmetry (-1..1): one eye a touch higher, one brow lower, the mouth off centre.
    const pidF = num(pose.pid, 0);
    const asy = ((((Math.floor(pidF) * 53) % 9) + 9) % 9 - 4) / 4;
    const hair = hat === 'none' || hat === 'cap' || hat === 'bonnet' ? look.hair : 'none';

    // ---- Ears (hidden by a hood, bonnet or bob) ----
    if (lod >= 1 && hat !== 'hood' && hat !== 'bonnet' && hair !== 'bob') {
      for (let side = -1; side <= 1; side += 2) {
        facePt(hx, hy, hrx, hry, noseX, cY, rot, side * 0.97, -0.1, 0.08);
        if (FP.d > 0.3) continue;
        const ex = FP.x;
        const ey = FP.y;
        const ew = Math.max(0.8, hr * 0.13 * (0.35 + 0.65 * Math.abs(noseX)));
        const eh = Math.max(1, hry * 0.22);
        // Opening toward the face in profile, away from the head centre seen head-on.
        const off = ex - hx;
        const open = Math.abs(off) > hrx * 0.45 ? (off > 0 ? -1 : 1) : (noseX >= 0 ? 1 : -1);
        const a0 = open > 0 ? Math.PI * 0.5 : -Math.PI * 0.5;
        const cR = Math.cos(rot);
        const sR = Math.sin(rot);
        const qx = ew * Math.cos(a0);
        const qy = eh * Math.sin(a0);
        c.moveTo(ex + qx * cR - qy * sR, ey + qx * sR + qy * cR);
        c.ellipse(ex, ey, ew, eh, rot, a0, a0 + Math.PI);
        if (lod >= 2 && Math.abs(noseX) > 0.4) {
          c.moveTo(ex - open * ew * 0.45, ey - eh * 0.35);
          c.quadraticCurveTo(ex + open * ew * 0.1, ey, ex - open * ew * 0.3, ey + eh * 0.4);
        }
      }
    }

    if (lod >= 1 && faceVis) {
      const nk = F.nose;
      const nz = (typeof look.nose === 'number' ? look.nose : 1) * (1 - 0.4 * kid) * (nk === 4 ? 1.3 : nk === 1 ? 0.6 : 1);
      // Nose: bridge, tip (sticks out past the outline in profile), base, plus nostril wings seen head-on.
      facePt(hx, hy, hrx, hry, noseX, cY, rot, 0, 0.96, 0.0);
      c.moveTo(FP.x, FP.y);
      if (nk === 2) {
        // Hooked: the bridge bows out and the tip turns down.
        facePt(hx, hy, hrx, hry, noseX, cY, rot, 0, 1.0 + 0.3 * nz, 0.14 + 0.06 * nz);
        const qx = FP.x; const qy = FP.y;
        facePt(hx, hy, hrx, hry, noseX, cY, rot, 0, 0.98 + 0.2 * nz, 0.36 + 0.08 * nz);
        c.quadraticCurveTo(qx, qy, FP.x, FP.y);
      } else {
        facePt(hx, hy, hrx, hry, noseX, cY, rot, 0, 1.0 + 0.26 * nz, 0.24 + 0.1 * nz);
        c.lineTo(FP.x, FP.y);
      }
      const tipX = FP.x; const tipY = FP.y;
      facePt(hx, hy, hrx, hry, noseX, cY, rot, 0, 0.93, 0.36 + 0.06 * nz);
      c.lineTo(FP.x, FP.y);
      if (lod >= 2 && (nk === 1 || nk === 3)) {
        // Button / bulb tip.
        const br = Math.max(0.7, hr * (nk === 3 ? 0.11 : 0.065) * Math.sqrt(nz));
        ell(c, tipX - noseX * br * 0.3, tipY - br * 0.2, br, br * 0.9, rot);
      }
      if (lod >= 2 && cY < -0.55) {
        for (let side = -1; side <= 1; side += 2) {
          facePt(hx, hy, hrx, hry, noseX, cY, rot, side * 0.13 * nz, 0.92, 0.33 + 0.06 * nz);
          const wx = FP.x; const wy = FP.y;
          facePt(hx, hy, hrx, hry, noseX, cY, rot, side * 0.05, 0.95, 0.4 + 0.06 * nz);
          c.moveTo(wx, wy - hry * 0.05);
          c.quadraticCurveTo(wx, FP.y, FP.x, FP.y);
        }
      }
      if (look.beard && lod >= 2) {
        // Beard: a full jaw line from cheek to cheek round a rounded chin, plus a moustache under the nose.
        facePt(hx, hy, hrx, hry, noseX, cY, rot, -0.8, 0.5, 0.3);
        c.moveTo(FP.x, FP.y);
        facePt(hx, hy, hrx, hry, noseX, cY, rot, -0.62, 0.72, 1.12);
        const qx0 = FP.x; const qy0 = FP.y;
        facePt(hx, hy, hrx, hry, noseX, cY, rot, 0, 0.92, 1.2);
        c.quadraticCurveTo(qx0, qy0, FP.x, FP.y);
        facePt(hx, hy, hrx, hry, noseX, cY, rot, 0.62, 0.72, 1.12);
        const qx1 = FP.x; const qy1 = FP.y;
        facePt(hx, hy, hrx, hry, noseX, cY, rot, 0.8, 0.5, 0.3);
        c.quadraticCurveTo(qx1, qy1, FP.x, FP.y);
        if (cY < -0.2) {
          for (let side = -1; side <= 1; side += 2) {
            // Moustache: each half sags under the nose and lifts at the tip.
            facePt(hx, hy, hrx, hry, noseX, cY, rot, side * 0.03, 0.95, 0.43);
            c.moveTo(FP.x, FP.y);
            facePt(hx, hy, hrx, hry, noseX, cY, rot, side * 0.16, 0.9, 0.62);
            const mx = FP.x; const my = FP.y;
            facePt(hx, hy, hrx, hry, noseX, cY, rot, side * 0.34, 0.82, 0.46);
            c.quadraticCurveTo(mx, my, FP.x, FP.y);
          }
        }
      }
      // Mouth (lod 2): a mood curve on the face, foreshortened with the yaw; width, smile and lopsidedness per face.
      if (lod >= 2) {
        const mv = 0.56 - 0.04 * kid;
        const mw = 0.2 * F.mw;
        const ms = asy * 0.035;
        const lop = F.lop * (asy >= 0 ? 1 : -1) * 0.07;
        facePt(hx, hy, hrx, hry, noseX, cY, rot, -mw + ms, 0.86, mv + lop);
        const x0 = FP.x; const y0 = FP.y; const d0 = FP.d;
        facePt(hx, hy, hrx, hry, noseX, cY, rot, mw + ms, 0.86, mv - lop);
        const x1 = FP.x; const y1 = FP.y; const d1 = FP.d;
        facePt(hx, hy, hrx, hry, noseX, cY, rot, ms, 0.9, mv);
        const xm = FP.x; const ym = FP.y;
        if (d0 < 0.15 || d1 < 0.15) {
          const half = Math.max(0.8, Math.abs(x1 - x0) * 0.5);
          if (md === 1 || md === 2) {
            // Open, frightened.
            ell(c, xm, ym + hry * 0.02, Math.max(0.8, half * 0.55), Math.max(0.9, hry * 0.09), rot);
          } else if (!look.beard) {
            if (pose.stars) {
              c.moveTo(x0, y0);
              c.quadraticCurveTo(lerp(x0, xm, 0.5), ym - hry * 0.06, xm, ym);
              c.quadraticCurveTo(lerp(xm, x1, 0.5), ym + hry * 0.06, x1, y1);
            } else {
              const curve = (md === 3 ? 0.03 : md === 4 ? -0.03 : 0.05) + F.mc;
              c.moveTo(x0, y0);
              c.quadraticCurveTo(xm, ym + hry * curve * 2, x1, y1);
            }
          }
        }
      }
    }
    if (lod >= 1 && eyesVis) {
      for (let side = -1; side <= 1; side += 2) {
        const ev = -0.06 + 0.12 * kid + F.ev + (side > 0 ? 0.025 : -0.025) * asy;
        facePt(hx, hy, hrx, hry, noseX, cY, rot, side * 0.36 * F.gap, 0.88, ev);
        if (FP.d > -0.05) continue;
        const ex = FP.x;
        const ey = FP.y;
        if (lod < 2 || pose.eyesX) {
          if (pose.eyesX) {
            const q = Math.max(1.2, hr * 0.14);
            c.moveTo(ex - q, ey - hry * 0.1); c.lineTo(ex + q, ey + hry * 0.1);
            c.moveTo(ex + q, ey - hry * 0.1); c.lineTo(ex - q, ey + hry * 0.1);
          } else {
            c.moveTo(ex, ey - hry * 0.09);
            c.lineTo(ex, ey + hry * 0.09);
          }
          continue;
        }
        const fore = clamp(-FP.d, 0.3, 1);
        const ew = Math.max(0.8, hr * 0.12 * (1 + 0.3 * kid) * fore * F.ew);
        const eh = Math.max(0.7, hry * 0.09 * (1 + 0.35 * kid) * (md === 1 ? 1.3 : 1) * F.eh);
        // Toward the nose: +1 when the inner corner is to the right of this eye.
        facePt(hx, hy, hrx, hry, noseX, cY, rot, 0, 0.9, ev);
        const innerRight = FP.x > ex;
        const outer = innerRight ? -1 : 1;
        if (md === 2) {
          c.moveTo(ex - ew, ey + eh * 0.2);
          c.quadraticCurveTo(ex, ey - eh * 1.1, ex + ew, ey + eh * 0.2);
        } else if (md === 3) {
          c.moveTo(ex - ew, ey);
          c.quadraticCurveTo(ex, ey + eh * 0.9, ex + ew, ey);
        } else {
          ell(c, ex, ey, ew, eh, rot);
          const sleepy = F.lid && md !== 1;
          const pr = Math.max(0.45, eh * (md === 1 ? 0.32 : F.ew > 1.1 ? 0.34 : 0.48));
          const pdx = noseX * ew * 0.3;
          const pdy = sleepy ? eh * 0.3 : 0;
          c.moveTo(ex + pdx + pr, ey + pdy);
          c.arc(ex + pdx, ey + pdy, pr, 0, TWO_PI);
          if (sleepy) {
            // Heavy lid across the top half.
            c.moveTo(ex - ew, ey - eh * 0.05);
            c.quadraticCurveTo(ex, ey - eh * 0.35, ex + ew, ey - eh * 0.05);
          }
          if (F.lash) {
            c.moveTo(ex + outer * ew * 0.85, ey - eh * 0.45);
            c.lineTo(ex + outer * ew * 1.35, ey - eh * 0.95);
          }
        }
        if (F.bag) {
          c.moveTo(ex - ew * 0.85, ey + eh * 1.45);
          c.quadraticCurveTo(ex, ey + eh * 2.2, ex + ew * 0.85, ey + eh * 1.45);
        }
        if (F.wr) {
          // Crow's feet at the outer corner.
          for (let k = -1; k <= 1; k += 2) {
            const w0 = Math.max(ew * 1.6, hr * 0.17);
            c.moveTo(ex + outer * w0, ey + k * eh * 0.2);
            c.lineTo(ex + outer * (w0 + hr * 0.08), ey + k * eh * 0.85);
          }
        }
        // Brows: the inner end (toward the nose) drops when wary, rises when sad or scared; per-face lift and tilt.
        const raised = F.rb && side * (asy >= 0 ? 1 : -1) > 0 ? -0.09 : 0;
        const lift = (md === 1 ? -0.2 : md === 3 ? -0.04 : 0) + F.bl + raised + (side > 0 ? 0.02 : -0.02) * asy;
        const tiltIn = (md === 4 ? 0.09 : md === 3 ? -0.06 : md === 1 ? -0.04 : 0.02) + F.bt;
        facePt(hx, hy, hrx, hry, noseX, cY, rot, side * 0.36 * F.gap, 0.86, ev - 0.24 + lift);
        const bxm = FP.x; const bym = FP.y;
        const bwid = Math.max(1, hr * 0.16 * fore * F.bw);
        for (let q = 0; q <= F.heavy; q++) {
          const dq = q * hry * 0.045;
          c.moveTo(bxm - bwid, bym + dq + (innerRight ? 0 : hry * tiltIn));
          c.quadraticCurveTo(bxm, bym + dq - hry * (0.05 - 0.02 * q), bxm + bwid, bym + dq + (innerRight ? hry * tiltIn : 0));
        }
      }
      if (lod >= 2 && cY < -0.35 && (F.ck || F.wr)) {
        for (let side = -1; side <= 1; side += 2) {
          if (F.ck) {
            // Round cheeks: a short arc under each eye, toward the jaw.
            facePt(hx, hy, hrx, hry, noseX, cY, rot, side * 0.55, 0.78, 0.22);
            if (FP.d < -0.1) {
              const cx = FP.x; const cy = FP.y;
              c.moveTo(cx - hr * 0.09, cy - hry * 0.06);
              c.quadraticCurveTo(cx, cy + hry * 0.08, cx + hr * 0.09, cy - hry * 0.06);
            }
          }
        }
        if (F.wr && md !== 1) {
          // Forehead lines.
          for (let k = 0; k < 2; k++) {
            facePt(hx, hy, hrx, hry, noseX, cY, rot, -0.28, 0.8, -0.5 - k * 0.12);
            c.moveTo(FP.x, FP.y);
            facePt(hx, hy, hrx, hry, noseX, cY, rot, 0, 0.88, -0.56 - k * 0.12);
            const mx = FP.x; const my = FP.y;
            facePt(hx, hy, hrx, hry, noseX, cY, rot, 0.28, 0.8, -0.5 - k * 0.12);
            c.quadraticCurveTo(mx, my, FP.x, FP.y);
          }
        }
      }
    }
    // Hair (only when no hat hides it).
    if (lod >= 1 && hair && hair !== 'none' && !roleHat) {
      const ty = hy - hry;
      if (hair === 'tuft') {
        for (let k = -1; k <= 1; k++) {
          c.moveTo(hx + k * hr * 0.3, ty + hry * 0.08);
          c.lineTo(hx + k * hr * 0.45 + hr * 0.12, ty - hry * 0.28);
        }
      } else if (hair === 'bun') {
        const bxr = hx - noseX * hr * 0.5;
        const br2 = Math.max(1.5, hr * 0.32);
        c.moveTo(bxr + br2, ty - hry * 0.05);
        c.arc(bxr, ty - hry * 0.05, br2, 0, TWO_PI);
      } else if (hair === 'spiky') {
        c.moveTo(hx - hr * 0.85, ty + hry * 0.3);
        for (let k = 0; k < 5; k++) {
          const u0 = -0.85 + k * 0.42;
          c.lineTo(hx + (u0 + 0.21) * hr, ty - hry * 0.3);
          c.lineTo(hx + (u0 + 0.42) * hr, ty + hry * 0.25);
        }
      } else if (hair === 'curls') {
        for (let k = -1; k <= 1; k++) {
          const cxr = hx + k * hr * 0.55;
          const rr = Math.max(1.3, hr * 0.26);
          c.moveTo(cxr + rr, ty + hry * 0.05);
          c.arc(cxr, ty + hry * 0.05, rr, 0, TWO_PI);
        }
      } else if (hair === 'bob') {
        c.moveTo(hx - hr * 1.05, hy + hry * 0.5);
        c.quadraticCurveTo(hx - hr * 1.15, ty - hry * 0.1, hx, ty - hry * 0.15);
        c.quadraticCurveTo(hx + hr * 1.15, ty - hry * 0.1, hx + hr * 1.05, hy + hry * 0.5);
      }
    }
    // Hats (a fed villager's hat lies on the floor beside them).
    if (hat !== 'none') {
      setHat(P, mode, hat, pose.tilt, m, HAT);
      const hhx = HAT.x;
      const hhy = HAT.y;
      const hatTilt = HAT.tilt;
      if (hat === 'tophat') {
        const hy2 = hhy - hry * 0.78;
        const bw2 = hr * 1.25;
        const th = vs * 0.14 * lh;
        const lean2 = hatTilt * th * 1.2 + (flee ? -hr * 0.6 : 0);
        const lift = flee ? -th * 0.35 : jump > 0 ? -jump * vs * 0.8 : 0;
        ell(c, hhx, hy2 + lift, bw2, Math.max(1.2, vs * 0.012), 0);
        c.moveTo(hhx - hr * 0.78, hy2 + lift);
        c.lineTo(hhx - hr * 0.7 + lean2, hy2 - th + lift);
        c.lineTo(hhx + hr * 0.7 + lean2, hy2 - th + lift);
        c.lineTo(hhx + hr * 0.78, hy2 + lift);
        c.moveTo(hhx - hr * 0.77 + lean2 * 0.2, hy2 - th * 0.22 + lift);
        c.lineTo(hhx + hr * 0.77 + lean2 * 0.2, hy2 - th * 0.22 + lift);
      } else if (hat === 'nightcap') {
        const hy2 = hhy - hry * 0.7;
        c.moveTo(hhx - hr * 0.95, hy2 + hry * 0.2);
        c.quadraticCurveTo(X[18], Y[18] - hry * 0.4, X[17], Y[17] - hry * 0.2);
        c.quadraticCurveTo(hhx + hr * 0.3, hy2 - hry * 0.2, hhx + hr * 0.95, hy2 + hry * 0.2);
        const pr = Math.max(1.5, hs * 0.022);
        c.moveTo(X[17] + pr, Y[17] - hry * 0.2);
        c.arc(X[17], Y[17] - hry * 0.2, pr, 0, TWO_PI);
        c.moveTo(hhx - hr * 0.95, hy2 + hry * 0.2);
        c.lineTo(hhx + hr * 0.95, hy2 + hry * 0.2);
      } else if (hat === 'bonnet') {
        c.moveTo(hhx - hr * 1.1, hhy + hry * 0.1);
        c.ellipse(hhx, hhy, hr * 1.12, hry * 1.1, hatTilt * 0.6, Math.PI * 0.95, Math.PI * 2.1);
        const ky = hhy + hry * 1.05;
        c.moveTo(hhx - hr * 0.9, hhy + hry * 0.6);
        c.quadraticCurveTo(hhx, ky + hry * 0.25, hhx + hr * 0.9, hhy + hry * 0.6);
        c.moveTo(hhx, ky);
        c.lineTo(hhx - hr * 0.5, ky + hry * 0.4);
        c.moveTo(hhx, ky);
        c.lineTo(hhx + hr * 0.5, ky + hry * 0.4);
      } else if (hat === 'cap') {
        const ty = hhy - hry * 0.55;
        const lift = jump > 0 ? -jump * vs * 0.6 : 0;
        c.moveTo(hhx - hr * 1.05, ty + lift);
        c.quadraticCurveTo(hhx, ty - hry * 0.75 + lift, hhx + hr * 1.05, ty + lift);
        c.moveTo(hhx - hr * 1.05, ty + lift);
        c.lineTo(hhx + hr * 1.05, ty + lift);
        const bdir = noseX >= 0 ? 1 : -1;
        c.moveTo(hhx + bdir * hr * 0.9, ty + lift);
        c.lineTo(hhx + bdir * hr * 1.45 + noseX * hr * 0.1, ty + hry * 0.12 + lift);
      } else if (hat === 'hood') {
        const ty = hhy - hry;
        c.moveTo(X[2] - hr * 0.2, Y[2]);
        c.quadraticCurveTo(hhx - hr * 1.35, hhy - hry * 0.2, hhx - hr * 0.2 + (moving ? -hr * 0.3 : 0), ty - hry * 0.45);
        c.quadraticCurveTo(hhx + hr * 1.35, hhy - hry * 0.2, X[3] + hr * 0.2, Y[3]);
      }
    }
    // Clavicles (bare-necked outfits, chest towards us, lod 2).
    if (lod >= 2 && cY < -0.45 && (outfit === undefined || outfit === 'plain' || outfit === 'apron' || outfit === 'smock') && acc !== 'scarf' && hat !== 'hood') {
      const nr = m.neckR * hs;
      for (let side = 0; side < 2; side++) {
        const s = 2 + side;
        const dir = X[s] >= X[1] ? 1 : -1;
        const y0 = lerp(Y[1], Y[s], 0.75);
        c.moveTo(X[1] + dir * nr * 0.55, y0 + vs * 0.006);
        c.quadraticCurveTo(lerp(X[1], X[s], 0.5), y0 + vs * 0.012, lerp(X[1], X[s], 0.85), lerp(Y[1], Y[s], 0.95));
      }
    }
    // Waistband: where the shirt meets the trousers (not under a robe, cloak or coat).
    if (lod >= 2 && m.belt && outfit !== 'robe' && outfit !== 'cloak' && !look.coat && mode !== 'fed') {
      const bend = (m.beltX1 - m.beltX0) * 0.12 * (cY < 0 ? 1 : -0.6);
      c.moveTo(m.beltX0, m.beltY0);
      c.quadraticCurveTo(m.beltCx, m.beltCy + Math.abs(bend), m.beltX1, m.beltY1);
    }
    // Coat hem (the robe and cloak draw their own).
    if (lod >= 1 && look.coat && mode !== 'fed' && outfit !== 'robe' && outfit !== 'cloak') {
      // Hem corners sorted by screen x so the coat never crosses itself when the figure faces us.
      const cy0 = by + bodyRy * 0.35;
      const r = X[21] >= X[22] ? 21 : 22;
      const l = 43 - r;
      c.moveTo(bx + bodyRx * 0.98, cy0);
      c.quadraticCurveTo(X[r] + bodyRx * 0.2, (cy0 + Y[r]) * 0.5, X[r] + bodyRx * 0.1, Y[r]);
      c.quadraticCurveTo((X[r] + X[l]) * 0.5, Math.max(Y[r], Y[l]) + vs * 0.02, X[l] - bodyRx * 0.1, Y[l]);
      c.quadraticCurveTo(X[l] - bodyRx * 0.2, (cy0 + Y[l]) * 0.5, bx - bodyRx * 0.98, cy0);
    }
    if (pose.seated) {
      const sw = hs * 0.26 * m.bw;
      c.moveTo(X[14] - sw, Y[4] + vs * 0.01);
      c.lineTo(X[14] + sw, Y[5] + vs * 0.01);
    }
    if (acc === 'scarf') {
      const sw = Math.max(m.neckR * hs * 1.9, bodyRx * 0.55);
      const nyy = Y[1] - bodyRy * 0.05;
      c.moveTo(X[1] - sw, nyy);
      c.quadraticCurveTo(X[1], nyy + hry * 0.5, X[1] + sw, nyy);
      c.moveTo(X[1] + sw * 0.7, nyy + hry * 0.15);
      c.quadraticCurveTo(X[16], Y[16], X[15], Y[15]);
    }
    // Props carried in the right hand.
    if (prop === 'cane' && mode !== 'fed') {
      c.moveTo(X[19], Y[19]);
      c.lineTo(X[20], Y[20]);
      c.moveTo(X[20], Y[20]);
      c.lineTo(X[19], Y[19] - vs * 0.03);
      c.arc(X[19] - hs * 0.015, Y[19] - vs * 0.03, hs * 0.015 + 1, 0, Math.PI, true);
    } else if (prop === 'lantern') {
      const lx = X[20];
      const ly = Y[20];
      const lw2 = Math.max(1.5, hs * 0.03);
      const lh2 = Math.max(2, vs * 0.05);
      c.moveTo(X[19], Y[19]);
      c.lineTo(lx, ly - lh2 * 0.6);
      c.moveTo(lx - lw2, ly - lh2 * 0.5);
      c.lineTo(lx + lw2, ly - lh2 * 0.5);
      c.lineTo(lx + lw2 * 0.8, ly + lh2 * 0.5);
      c.lineTo(lx - lw2 * 0.8, ly + lh2 * 0.5);
      c.closePath();
    } else if (prop === 'basket') {
      const kx = X[20];
      const ky = Y[20];
      const kw = Math.max(2, hs * 0.045);
      const kh = Math.max(1.5, vs * 0.035);
      c.moveTo(kx - kw * 0.8, ky - kh * 0.5);
      c.quadraticCurveTo(kx, ky - kh * 2.2, kx + kw * 0.8, ky - kh * 0.5);
      c.moveTo(kx - kw, ky - kh * 0.5);
      c.lineTo(kx + kw, ky - kh * 0.5);
      c.lineTo(kx + kw * 0.7, ky + kh * 0.5);
      c.lineTo(kx - kw * 0.7, ky + kh * 0.5);
      c.closePath();
    } else if (prop === 'umbrella' && mode !== 'fed' && mode !== 'cower') {
      const ux = X[20];
      const uy = Y[20];
      const uw = hr * 2.6;
      c.moveTo(X[19], Y[19]);
      c.lineTo(ux, uy);
      c.moveTo(ux - uw, uy + hry * 0.9);
      c.quadraticCurveTo(ux, uy - hry * 1.2, ux + uw, uy + hry * 0.9);
      for (let k = 0; k < 3; k++) {
        const x0 = ux - uw + (k * 2 * uw) / 3;
        const x1 = x0 + (2 * uw) / 3;
        c.moveTo(x0, uy + hry * 0.9);
        c.quadraticCurveTo((x0 + x1) * 0.5, uy + hry * 1.25, x1, uy + hry * 0.9);
      }
    }
    // Fingers (lod 2): a fist round a carried prop or role item, splayed when scared or struggling, else a relaxed curl.
    if (lod >= 2) {
      const spread = mode === 'startle' || mode === 'cower' || mode === 'grapple' || md === 1;
      const extra = look.extra;
      for (let i = 0; i < drawN; i++) {
        const p = POOL[i];
        if (!p || p.kind !== 'hand' || !(p.rh > 2)) continue;
        const r = p.rh;
        const ax = p.ax; const ay = p.ay;
        const ux = p.ux; const uy = p.uy; const vx = p.vx; const vy = p.vy;
        const right = p.b === 7;
        const grip = mode !== 'fed' && (right ? prop !== 'none' && !(prop === 'umbrella' && mode === 'cower') : !!extra && extra !== 'none' && extra !== 'bow');
        if (grip) {
          // Knuckle row across the tip, a curled finger crease and the thumb wrapped over.
          for (let f = 0; f < 3; f++) {
            const cc = 0.5 - f * 0.5;
            const kx = ax + (ux * 1.12 + vx * cc) * r;
            const ky = ay + (uy * 1.12 + vy * cc) * r;
            c.moveTo(kx - vx * r * 0.22, ky - vy * r * 0.22);
            c.quadraticCurveTo(kx + ux * r * 0.22, ky + uy * r * 0.22, kx + vx * r * 0.22, ky + vy * r * 0.22);
          }
          c.moveTo(ax + (ux * 0.55 + vx * 0.55) * r, ay + (uy * 0.55 + vy * 0.55) * r);
          c.quadraticCurveTo(ax + (ux * 0.95 + vx * 0.2) * r, ay + (uy * 0.95 + vy * 0.2) * r, ax + (ux * 0.9 - vx * 0.25) * r, ay + (uy * 0.9 - vy * 0.25) * r);
        } else if (spread) {
          // Four splayed fingers fanning out from the palm.
          for (let f = 0; f < 4; f++) {
            const a = -0.55 + f * 0.37;
            const ca = Math.cos(a); const sa2 = Math.sin(a);
            const dx = ux * ca + vx * sa2;
            const dy = uy * ca + vy * sa2;
            c.moveTo(ax + dx * r * 0.95, ay + dy * r * 0.95);
            c.lineTo(ax + dx * r * (1.75 - 0.12 * Math.abs(f - 1.5)), ay + dy * r * (1.75 - 0.12 * Math.abs(f - 1.5)));
          }
        } else {
          // Relaxed: three fingers curling back toward the palm.
          for (let f = 0; f < 3; f++) {
            const cc = 0.32 - f * 0.3;
            const x0 = ax + (ux * 0.9 + vx * cc) * r;
            const y0 = ay + (uy * 0.9 + vy * cc) * r;
            c.moveTo(x0, y0);
            c.quadraticCurveTo(ax + (ux * 1.5 + vx * cc) * r, ay + (uy * 1.5 + vy * cc) * r, ax + (ux * 1.38 + vx * (cc + 0.18)) * r, ay + (uy * 1.38 + vy * (cc + 0.18)) * r);
          }
        }
      }
    }
    // Knees and elbows (lod 2): a kneecap cup seen from the front, an elbow crease on the inside of a bent arm.
    if (lod >= 2) {
      for (let i = 0; i < drawN; i++) {
        const p = POOL[i];
        if (!p || !(p.rh > 1.5)) continue;
        if (p.kind === 'leg' && m.sr < 0.75 && cY < 0.2 && outfit !== 'robe') {
          const r = p.rh;
          c.moveTo(p.jx - p.vx * r * 0.45 + p.ux * r * 0.15, p.jy - p.vy * r * 0.45 + p.uy * r * 0.15);
          c.quadraticCurveTo(p.jx + p.ux * r * 0.75, p.jy + p.uy * r * 0.75, p.jx + p.vx * r * 0.45 + p.ux * r * 0.15, p.jy + p.vy * r * 0.45 + p.uy * r * 0.15);
        } else if (p.kind === 'arm' && Math.abs(p.bend) > 0.35) {
          const r = p.rh;
          const side = p.bend > 0 ? 1 : -1;
          c.moveTo(p.jx + p.vx * side * r * 0.2 - p.ux * r * 0.5, p.jy + p.vy * side * r * 0.2 - p.uy * r * 0.5);
          c.quadraticCurveTo(p.jx + p.vx * side * r * 0.75, p.jy + p.vy * side * r * 0.75, p.jx + p.vx * side * r * 0.2 + p.ux * r * 0.5, p.jy + p.vy * side * r * 0.2 + p.uy * r * 0.5);
        }
      }
    }
    if (pose.handsOverHead && lod >= 2) {
      for (let side = 0; side < 2; side++) {
        c.moveTo(X[6 + side], Y[6 + side]);
        c.lineTo(X[6 + side] + (side ? -1 : 1) * hr * 0.3, Y[6 + side] - hry * 0.25);
      }
    }
  }

  // ---------------------------------------------------------------- extras

  /** Extra grip / tip: slots 24/25 when present, otherwise a spot beside the left hand. */
  const EX = { gx: 0, gy: 0, tx: 0, ty: 0 };
  function exSlots(P, m) {
    const X = arrX(P);
    const Y = arrY(P);
    if (X.length > 25 && Y.length > 25 && (X[24] !== 0 || Y[24] !== 0 || X[25] !== 0 || Y[25] !== 0)) {
      EX.gx = X[24]; EX.gy = Y[24]; EX.tx = X[25]; EX.ty = Y[25];
    } else {
      EX.gx = X[6]; EX.gy = Y[6];
      EX.tx = X[6] + m.hs * 0.02; EX.ty = Y[6] - m.vs * 0.28 * m.lh;
    }
  }

  /** Hem from (x0, y) to (x1, y), bowing down by dip in the middle, in four soft scallops (folds meeting the hem). */
  function hemWave(c, x0, y, x1, dip) {
    let px = x0;
    for (let i = 1; i <= 4; i++) {
      const t = i / 4;
      const tm = (i - 0.5) / 4;
      const x = lerp(x0, x1, t);
      const yb = y + dip * 4 * t * (1 - t);
      const ym = y + dip * 4 * tm * (1 - tm) + dip * (i & 1 ? 0.7 : 0.45);
      c.quadraticCurveTo((px + x) * 0.5, ym, x, yb);
      px = x;
    }
  }

  /** Mail, robe, apron/smock, cloak, role hats and role items (look.outfit / roleHat / extra). Strokes only. */
  function drawExtras(c, P, pose, look, o) {
    if (!hasCtx(c)) return false;
    let saved = false;
    try {
      const X = arrX(P);
      const Y = arrY(P);
      if (!X || !Y || X.length < 24 || Y.length < 24) return false;
      pose = pose || {};
      look = look || {};
      o = o || {};
      const outfit = look.outfit;
      const roleHat = look.roleHat;
      const extra = look.extra;
      if (!(outfit && outfit !== 'plain') && !(roleHat && roleHat !== 'none') && !(extra && extra !== 'none')) return true;
      // Hull widths (chest r0, hips r1) from the parts geometry so clothes fit the anatomy.
      parts(P, pose, look, HPOOL);
      spanSig = NaN;
      const m = M;
      m.hipU = num(pose.hipU, 0);
      const lod = num(pose.lod, 1);
      const lw = Math.max(0.5, num(o.lw, 1));
      c.save();
      saved = true;
      c.lineJoin = 'round';
      c.lineCap = 'round';
      c.globalAlpha = clamp(num(o.alpha, 1) * num(o.sa, 1), 0, 1);
      if (typeof o.style === 'string') c.strokeStyle = o.style;
      c.lineWidth = lw;
      c.beginPath();
      const hr = m.hr;
      const hry = m.hry;
      const hs = m.hs;
      const vs = m.vs;

      if (outfit === 'mail' && lod >= 1) {
        for (let row = 0; row < 3; row++) {
          const t = 0.25 + 0.25 * row;
          const cx = lerp(m.sx, m.hx, t);
          const cy = lerp(m.sy, m.hy, t);
          const w = lerp(m.r0, m.r1, t) * 0.85;
          const sr = Math.max(0.8, w / 3);
          for (let k = 0; k < 3; k++) {
            const x = cx - w + sr + k * 2 * sr;
            c.moveTo(x + sr, cy);
            c.arc(x, cy, sr, 0, Math.PI);
          }
        }
      } else if (outfit === 'robe' || outfit === 'cloak') {
        const hy = hemY(m, look, outfit === 'robe' ? 1 : 0.8);
        const lx = X[21];
        const rx = X[22];
        const swing = ((lx + rx) * 0.5) - m.hx;
        const hem = clamp(num(look.hem, 1), 0, 1);
        const half = Math.max(Math.abs(lx - rx) * 0.5, m.r1 * 1.2) * (outfit === 'cloak' ? 1.45 : 1) * (1 + 0.5 * hem);
        const cx = m.hx + swing;
        const shL = X[2] <= X[3] ? 2 : 3;
        const shR = 5 - shL;
        const dip = vs * (outfit === 'cloak' ? 0.025 : 0.02);
        if (outfit === 'robe') {
          c.moveTo(m.hx - m.r1, m.hy);
          c.quadraticCurveTo(m.hx - m.r1 * 1.2 + (cx - m.hx) * 0.3, (m.hy + hy) * 0.5, cx - half, hy);
          if (lod >= 1) hemWave(c, cx - half, hy, cx + half, dip);
          else c.quadraticCurveTo(cx, hy + dip, cx + half, hy);
          c.quadraticCurveTo(m.hx + m.r1 * 1.2 + (cx - m.hx) * 0.3, (m.hy + hy) * 0.5, m.hx + m.r1, m.hy);
          if (lod >= 2) {
            // Folds falling from the girdle and spreading toward the hem (alternate ones stop short).
            for (let k = 0; k < 3; k++) {
              const f = -0.5 + k * 0.5;
              const tx = m.hx + f * m.r1 * 0.75;
              const ty = m.hy + vs * 0.02;
              const len = k === 1 ? 1 : 0.72;
              const bx = lerp(tx, cx + f * half * 0.72, len);
              const by = lerp(ty, hy, len) + (len === 1 ? dip * 0.85 : 0);
              c.moveTo(tx, ty);
              c.quadraticCurveTo((tx + bx) * 0.5 + f * half * 0.08, (ty + by) * 0.5, bx, by);
            }
          }
        } else {
          c.moveTo(X[shL], Y[shL]);
          c.quadraticCurveTo(X[shL] - half * 0.6, (Y[shL] + hy) * 0.5, cx - half, hy);
          if (lod >= 1) hemWave(c, cx - half, hy, cx + half, dip);
          else c.quadraticCurveTo(cx, hy + dip, cx + half, hy);
          c.quadraticCurveTo(X[shR] + half * 0.6, (Y[shR] + hy) * 0.5, X[shR], Y[shR]);
          if (lod >= 2) {
            // Long folds from each shoulder blade down the drape.
            for (let s2 = 0; s2 < 2; s2++) {
              const sh = s2 === 0 ? shL : shR;
              const sg = s2 === 0 ? -1 : 1;
              const tx = X[sh] + sg * half * 0.05;
              const ty = Y[sh] + vs * 0.04;
              const bx = cx + sg * half * 0.55;
              c.moveTo(tx, ty);
              c.quadraticCurveTo(tx + sg * half * 0.32, (ty + hy) * 0.5, bx, hy + dip * 0.7);
            }
          }
        }
      } else if (outfit === 'apron' || outfit === 'smock') {
        const hy = hemY(m, look, outfit === 'apron' ? 0.35 : 0.2);
        const wt = lerp(m.r0, m.r1, 0.2) * 0.45;
        const cy0 = lerp(m.sy, m.hy, 0.15);
        const cx0 = lerp(m.sx, m.hx, 0.15);
        const cy1 = lerp(m.sy, m.hy, 0.85);
        const cx1 = lerp(m.sx, m.hx, 0.85);
        const wb = lerp(m.r0, m.r1, 0.85) * 0.9;
        c.moveTo(cx0 - wt, cy0);
        c.lineTo(cx0 + wt, cy0);
        c.moveTo(cx0 - wt, cy0);
        c.lineTo(cx1 - wb, cy1);
        c.moveTo(cx0 + wt, cy0);
        c.lineTo(cx1 + wb, cy1);
        const half = Math.max(wb, m.r1 * 1.05);
        c.moveTo(m.hx - half, hy);
        if (lod >= 1) hemWave(c, m.hx - half, hy, m.hx + half, vs * 0.016);
        else c.quadraticCurveTo(m.hx, hy + vs * 0.02, m.hx + half, hy);
        if (lod >= 2 && hy - cy1 > vs * 0.04) {
          // Two soft folds hanging from the waist tie.
          for (let k = -1; k <= 1; k += 2) {
            const tx = cx1 + k * wb * 0.35;
            const bx = m.hx + k * half * 0.45;
            c.moveTo(tx, cy1 + vs * 0.01);
            c.quadraticCurveTo(lerp(tx, bx, 0.5) - k * half * 0.06, (cy1 + hy) * 0.5, bx, hy + vs * 0.012);
          }
        }
      }

      // Role hat (replaces the ordinary hat; see draw()).
      if (roleHat === 'kettle' || roleHat === 'biretta') {
        setHat(P, pose.mode, roleHat, pose.tilt, m, HAT);
        const hx = HAT.x;
        const base = HAT.y - hry * 0.78;
        if (roleHat === 'kettle') {
          ell(c, hx, base, hr * 1.5, Math.max(1.2, vs * 0.014), 0);
          c.moveTo(hx - hr * 0.88, base);
          c.ellipse(hx, base, hr * 0.88, Math.max(0.01, hry * 0.8), 0, Math.PI, TWO_PI);
        } else {
          const top = base - hry * 0.55;
          c.moveTo(hx - hr * 0.95, base);
          c.lineTo(hx - hr * 0.78, top);
          c.lineTo(hx + hr * 0.78, top);
          c.lineTo(hx + hr * 0.95, base);
          c.closePath();
          for (let k = -1; k <= 1; k++) {
            c.moveTo(hx + k * hr * 0.3, base);
            c.lineTo(hx + k * hr * 0.26, top);
          }
          const tr = Math.max(1.2, hr * 0.15);
          c.moveTo(hx + tr, top - tr);
          c.arc(hx, top - tr, tr, 0, TWO_PI);
        }
      }

      // Role item in the left hand (side 0).
      if (extra && extra !== 'none') {
        exSlots(P, m);
        const gx = EX.gx;
        const gy = EX.gy;
        const tx = EX.tx;
        const ty = EX.ty;
        if (extra === 'shovel') {
          c.moveTo(gx, gy);
          c.lineTo(tx, ty);
          const dx = tx - gx;
          const dy = ty - gy;
          const L = Math.max(1e-6, Math.sqrt(dx * dx + dy * dy));
          const ux = dx / L;
          const uy = dy / L;
          const bwid = Math.max(2, hs * 0.035);
          const blen = Math.max(2, vs * 0.045);
          const nx = -uy * bwid;
          const ny = ux * bwid;
          c.moveTo(tx + nx, ty + ny);
          c.lineTo(tx + ux * blen + nx * 0.8, ty + uy * blen + ny * 0.8);
          c.lineTo(tx + ux * blen * 1.2, ty + uy * blen * 1.2);
          c.lineTo(tx + ux * blen - nx * 0.8, ty + uy * blen - ny * 0.8);
          c.lineTo(tx - nx, ty - ny);
        } else if (extra === 'bundle') {
          const rx = Math.max(2, hs * 0.05);
          const ry = rx * 0.8;
          ell(c, tx, ty, rx, ry, 0.4);
          c.moveTo(tx - rx * 0.7, ty - ry * 0.5);
          c.quadraticCurveTo(tx, ty + ry * 0.2, tx + rx * 0.7, ty + ry * 0.5);
        } else if (extra === 'ledger') {
          const w = Math.max(2, hs * 0.04);
          const h = Math.max(2.5, vs * 0.045);
          const lx = gx;
          const ly = gy - h * 0.6;
          c.moveTo(lx - w, ly - h);
          c.lineTo(lx + w, ly - h);
          c.lineTo(lx + w, ly + h);
          c.lineTo(lx - w, ly + h);
          c.closePath();
          c.moveTo(lx - w * 0.6, ly - h);
          c.lineTo(lx - w * 0.6, ly + h);
        } else if (extra === 'bow') {
          const d = num(pose.noseX, 0) >= 0 ? -1 : 1;
          const tx0 = m.sx + d * m.r0 * 1.1;
          const ty0 = m.sy - vs * 0.04 * m.lh;
          const bx0 = m.hx + d * m.r1 * 1.1;
          const by0 = m.hy + vs * 0.06 * m.lh;
          const mx = (tx0 + bx0) * 0.5 + d * m.r0 * 1.3;
          const my = (ty0 + by0) * 0.5;
          c.moveTo(tx0, ty0);
          c.quadraticCurveTo(mx, my, bx0, by0);
          c.moveTo(tx0, ty0);
          c.quadraticCurveTo((tx0 + bx0) * 0.5 - d * m.r0 * 0.3, my, bx0, by0);
        }
      }
      c.stroke();
      c.restore();
      saved = false;
      return true;
    } catch (e) {
      fail('drawExtras', e);
      if (saved) { try { c.restore(); } catch (e2) { /* ignore */ } }
      return false;
    }
  }

  // ---------------------------------------------------------------- flush

  /**
   * Soft coral flush fitted to the anatomy: the face (0, toward the facing side), along the neck (1) and over the wrists
   * (6/7, along the forearm). flush = [temporal, carotid, radialL, radialR].
   * a = min(0.18, flush[i] * skin * 0.25 * sa); static and <= 0.08 with reduced motion.
   */
  function drawFlush(c, P, pose, flush, o) {
    if (!hasCtx(c) || !flush || typeof c.fill !== 'function') return false;
    let saved = false;
    try {
      const X = arrX(P);
      const Y = arrY(P);
      if (!X || !Y || X.length < 24 || Y.length < 24) return false;
      pose = pose || {};
      o = o || {};
      const look = o.look || {};
      const skin = clamp(num(look.skin, num(o.skin, 1)), 0, 1);
      const sa = clamp(num(o.alpha, 1) * num(o.sa, 1), 0, 1);
      const cap = o.reduced ? 0.08 : 0.18;
      const n = parts(P, pose, look, HPOOL);
      spanSig = NaN;
      const m = M;
      let neck = null;
      let armL = null;
      let armR = null;
      for (let i = 0; i < n; i++) {
        const p = HPOOL[i];
        if (p.kind === 'neck') neck = p;
        else if (p.kind === 'arm') { if (p.b === 6) armL = p; else armR = p; }
      }
      c.save();
      saved = true;
      c.fillStyle = COL_FLUSH;
      for (let i = 0; i < 4; i++) {
        const a = Math.min(cap, Math.max(0, num(flush[i], 0)) * skin * 0.25 * sa);
        if (!(a > 0.002)) continue;
        c.globalAlpha = a;
        c.beginPath();
        if (i === 0) {
          const nx = clamp(num(pose.noseX, 0), -1, 1);
          ell(c, X[0] + nx * m.hr * 0.16, Y[0] + m.hry * 0.12, m.hr * 0.6, m.hry * 0.62, num(pose.tilt, 0) * 0.6);
        } else if (i === 1) {
          if (neck) {
            const ang = Math.atan2(neck.by - neck.ay, neck.bx - neck.ax);
            const len = Math.hypot(neck.bx - neck.ax, neck.by - neck.ay);
            ell(c, lerp(neck.ax, neck.bx, 0.3), lerp(neck.ay, neck.by, 0.3), Math.max(1, len * 0.32), Math.max(1, Math.min(neck.r0, neck.r1) * 0.8), ang);
          } else {
            ell(c, X[1], Y[1], Math.max(1.5, m.hs * 0.025), Math.max(1.5, m.vs * 0.02), 0);
          }
        } else {
          const f = i === 2 ? armL : armR;
          const s = i === 2 ? 6 : 7;
          if (f) {
            tangent(X[s - 4], Y[s - 4], X[s + 4], Y[s + 4], X[s], Y[s], 1);
            const ang = Math.atan2(TAN.y, TAN.x);
            const r = Math.max(1, f.r1);
            ell(c, X[s] - TAN.x * r * 0.9, Y[s] - TAN.y * r * 0.9, r * 1.6, r * 0.85, ang);
          } else {
            ell(c, X[s], Y[s], Math.max(1.5, m.hs * 0.02), Math.max(1.5, m.hs * 0.02), 0);
          }
        }
        c.fill();
      }
      c.restore();
      saved = false;
      return true;
    } catch (e) {
      fail('drawFlush', e);
      if (saved) { try { c.restore(); } catch (e2) { /* ignore */ } }
      return false;
    }
  }

  // ---------------------------------------------------------------- grab arms

  /**
   * Volumetric version of render.js drawGrabArms, same anchors: (r, X, Y, hs, lw, alpha, jolt, tN, pid, style, rs).
   * The first argument may be the renderer (uses r.octx, r.ow, r.oh, r.wscale) or a bare ctx.
   */
  function drawGrabArmsVol(rc, X, Y, hs, lw, alpha, jolt, tN, pid, style, rs) {
    let c = null;
    let saved = false;
    try {
      const isR = !!rc && !!rc.octx && typeof rc.octx.moveTo === 'function';
      c = isR ? rc.octx : rc;
      if (!hasCtx(c) || !X || !Y || X.length < 15 || Y.length < 15) return false;
      const W = isR ? num(rc.ow, 640) : num(c.canvas && c.canvas.width, 640);
      const H = isR ? num(rc.oh, 360) : num(c.canvas && c.canvas.height, 360);
      const ws = isR ? num(rc.wscale, 1) : 1;
      hs = num(hs, 100); lw = Math.max(0.5, num(lw, 1)); alpha = num(alpha, 1);
      jolt = num(jolt, 0); tN = num(tN, 0); pid = num(pid, 0); rs = num(rs, 0);
      const left = X[2] <= X[3] ? 2 : 3;
      const shake = jolt * hs * 0.05;
      c.save();
      saved = true;
      c.globalAlpha = Math.min(1, alpha * 0.7);
      c.strokeStyle = style;
      c.lineCap = 'round';
      c.lineJoin = 'round';
      for (let k = 0; k < 2; k++) {
        const idx = k === 0 ? left : 5 - left;
        const sgn = k === 0 ? -1 : 1;
        const tx = X[idx] + (X[14] - X[idx]) * 0.35 * rs + sgn * hs * 0.03 + Math.sin(tN * 37 + k * 2 + pid) * shake;
        const ty = Y[idx] + (Y[14] - Y[idx]) * 0.35 * rs + hs * 0.02 + Math.cos(tN * 29 + k * 3 + pid) * shake;
        const sx = W * 0.5 + sgn * W * 0.3;
        const sy = H + 12 * ws;
        const r0 = lw * 4.5;
        const r1 = lw * 2.6;
        c.lineWidth = lw;
        c.beginPath();
        capsule(c, sx, sy, r0, tx, ty, r1);
        const dx = tx - sx;
        const dy = ty - sy;
        if (dx * dx + dy * dy > 4) {
          const ang = Math.atan2(dy, dx);
          for (let q = 0; q < 2; q++) {
            const t = q === 0 ? 0.4 : 0.7;
            const cx = lerp(sx, tx, t);
            const cy = lerp(sy, ty, t);
            const r = lerp(r0, r1, t);
            c.moveTo(cx + r * Math.cos(ang + Math.PI * 0.5), cy + r * Math.sin(ang + Math.PI * 0.5));
            c.ellipse(cx, cy, Math.max(0.01, r), Math.max(0.01, r * 0.35), ang + Math.PI * 0.5, 0, Math.PI, true);
          }
        }
        c.stroke();
        // Knuckles and fingers at the grip.
        c.beginPath();
        const gr = Math.max(2, hs * 0.012);
        c.moveTo(tx + gr, ty);
        c.arc(tx, ty, gr, 0, TWO_PI);
        for (let f = -1; f <= 1; f++) {
          c.moveTo(tx, ty - gr * 0.6);
          c.lineTo(tx + f * gr * 0.9 - sgn * gr * 0.3, ty - gr * 2);
          c.moveTo(tx + f * gr * 0.7 - gr * 0.3, ty + gr * 0.2);
          c.lineTo(tx + f * gr * 0.7 + gr * 0.3, ty + gr * 0.2);
        }
        c.stroke();
      }
      c.restore();
      saved = false;
      return true;
    } catch (e) {
      fail('drawGrabArmsVol', e);
      if (saved) { try { c.restore(); } catch (e2) { /* ignore */ } }
      return false;
    }
  }

  const Figure = { capsule, parts, sortBackToFront, contains, hit, hitAll, spanAt, draw, drawExtras, drawFlush, drawGrabArmsVol, MAX_PARTS: MAXP, MAX_POINTS: MAXPTS };
  VCS.Figure = Figure;
  if (typeof module !== 'undefined' && module.exports) module.exports = Figure;
})(typeof window !== 'undefined' ? window : globalThis);
