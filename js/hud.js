(function (root) {
  'use strict';
  const VCS = (root.VCS = root.VCS || {});

  // Night HUD: blood vial, moon-to-sun dial, cooldown arc, dawn grain, title cards and fades.
  // Everything draws in 640x360 internal coordinates. Dim, hand-drawn, boiled thin lines; no fills
  // except the crosshair dot, the fade rect, the dawn vignette and the dawn grain.
  const W = 640;
  const H = 360;
  const TWO_PI = Math.PI * 2;
  const CARD_DUR = 2.4;
  const CARD_IN = 0.3;
  const CARD_OUT = 0.5;
  const COL_LINE = '#cfe3ff';
  const COL_BLOOD = '#d0505e';
  const COL_CORAL = '#ff8a78';
  const COL_BLUE = '#cfe8ff';
  const FONT_MONO = 'ui-monospace, Menlo, Consolas, monospace';
  const LARGE_K = 1.3;
  const HINT_FADE = 0.4;
  const HINT_DUR = 4;
  const GRAIN_W = 320;
  const GRAIN_H = 180;

  const logged = {};
  /** Log a HUD problem once per key; never throws. */
  function logOnce(key, e) {
    try {
      if (logged[key]) return;
      logged[key] = true;
      const log = VCS.Log && VCS.Log.get ? VCS.Log.get('hud') : null;
      if (log && log.warn) log.warn('hud ' + key + ' failed: ' + (e && e.message ? e.message : String(e)));
    } catch (_) { /* logging must never throw */ }
  }

  /** Finite number clamped to [lo, hi], else def. */
  function num(v, def, lo, hi) {
    if (typeof v !== 'number' || v !== v || v === Infinity || v === -Infinity) return def;
    return v < lo ? lo : v > hi ? hi : v;
  }

  /** Stable pseudo-random 0..1 from an integer pair (fallback when Ripple is absent). */
  function hash2(i, f) {
    const v = Math.sin(i * 12.9898 + f * 78.233) * 43758.5453;
    return v - Math.floor(v);
  }

  /** Create scratch state. Needs no DOM; the grain canvas is built lazily on first dawn draw. */
  function create() {
    return {
      fr: 0, boil: false,
      timeKey: -1, timeText: '20:00',
      grain: null, grainFor: null, grainTried: false,
      vig: null, vigFor: null, vigW: 0, vigH: 0
    };
  }
  let defaultHud = null;
  function hudOf(h) {
    if (h && typeof h === 'object') return h;
    return defaultHud || (defaultHud = create());
  }

  /** Boil jitter -1..1 for the current frame (0 when boil is off). */
  function J(h, id, axis) {
    if (!h.boil) return 0;
    const R = VCS.Ripple;
    if (R && R.jitter) return R.jitter(h.fr, id, axis);
    return (hash2(id * 2 + axis, h.fr) - 0.5) * 2;
  }

  function setFrame(h, t, boil) {
    h.boil = boil;
    if (!boil) { h.fr = 0; return; }
    const R = VCS.Ripple;
    h.fr = R && R.boilFrame ? R.boilFrame(t) : Math.floor(t * 10) & 3;
  }

  /** 'HH:MM' cached by minute so the per-frame draw allocates nothing. */
  function timeText(h, hour, minute) {
    const key = hour * 60 + minute;
    if (key !== h.timeKey) {
      h.timeKey = key;
      h.timeText = (hour < 10 ? '0' : '') + hour + ':' + (minute < 10 ? '0' : '') + minute;
    }
    return h.timeText;
  }

  // ---- blood vial ----
  const VX = 30;
  const V_RIM = 303;      // rim line y
  const V_IN_TOP = 305;   // inside top
  const V_IN_BOT = 333;   // inside bottom

  function drawVial(h, ctx, blood, weak, t, reduced, pulse) {
    const sc = 0.45;
    const scaled = pulse > 0 && !reduced && ctx.translate && ctx.scale;
    if (scaled) {
      const ps = 1 + 0.08 * pulse;
      ctx.save();
      ctx.translate(VX, (V_RIM - 5 + V_IN_BOT + 2) / 2);
      ctx.scale(ps, ps);
      ctx.translate(-VX, -(V_RIM - 5 + V_IN_BOT + 2) / 2);
    }
    try {
      drawVialBody(h, ctx, blood, weak, t, reduced, sc);
    } finally {
      if (scaled) ctx.restore();
    }
  }

  function drawVialBody(h, ctx, blood, weak, t, reduced, sc) {
    let fl = 1;
    if (weak > 0) fl = reduced ? 1 - 0.2 * weak : 1 - 0.25 * weak * (0.5 + 0.5 * Math.sin(t * 12.5)); // 2 Hz
    ctx.lineWidth = 1;
    ctx.strokeStyle = COL_LINE;
    ctx.globalAlpha = 0.5 * fl;
    ctx.beginPath();
    // glass: two sides, rounded bottom
    ctx.moveTo(23 + J(h, 1, 0) * sc, V_RIM + J(h, 1, 1) * sc);
    ctx.lineTo(23 + J(h, 2, 0) * sc, 328 + J(h, 2, 1) * sc);
    ctx.quadraticCurveTo(23 + J(h, 3, 0) * sc, 335, VX + J(h, 3, 1) * sc, 335 + J(h, 4, 1) * sc);
    ctx.quadraticCurveTo(37 + J(h, 5, 0) * sc, 335, 37 + J(h, 5, 1) * sc, 328 + J(h, 6, 1) * sc);
    ctx.lineTo(37 + J(h, 6, 0) * sc, V_RIM + J(h, 7, 1) * sc);
    // rim
    ctx.moveTo(21.5 + J(h, 8, 0) * sc, V_RIM + J(h, 8, 1) * sc);
    ctx.lineTo(38.5 + J(h, 9, 0) * sc, V_RIM + J(h, 9, 1) * sc);
    // cork
    ctx.moveTo(26 + J(h, 10, 0) * sc, V_RIM - 0.5);
    ctx.lineTo(26.5 + J(h, 11, 0) * sc, 298.5 + J(h, 11, 1) * sc);
    ctx.lineTo(33.5 + J(h, 12, 0) * sc, 298.5 + J(h, 12, 1) * sc);
    ctx.lineTo(34 + J(h, 13, 0) * sc, V_RIM - 0.5);
    ctx.stroke();

    if (blood <= 0.005) return;
    const level = V_IN_BOT - (V_IN_BOT - V_IN_TOP) * blood;
    const amp = reduced ? 0 : 1.5;
    ctx.strokeStyle = COL_BLOOD;
    ctx.lineWidth = 1.1;
    ctx.globalAlpha = 0.55;
    ctx.beginPath();
    // sloshing surface
    for (let i = 0; i < 6; i++) {
      const x = 24.5 + i * 2.2;
      let y = level + (amp ? Math.sin(t * 3.2 + i * 1.1) * amp : 0) + J(h, 20 + i, 1) * 0.35;
      if (y < V_IN_TOP) y = V_IN_TOP;
      else if (y > V_IN_BOT) y = V_IN_BOT;
      if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y);
    }
    // hatch lines under the surface
    const n = blood > 0.5 ? 3 : 2;
    for (let i = 1; i <= n; i++) {
      const y = level + i * 3.3;
      if (y > V_IN_BOT - 0.5) break;
      const inset = y > 328 ? (y - 328) * 0.9 : 0;
      const x0 = 24.6 + inset;
      const x1 = 35.4 - inset;
      const sl = amp ? Math.sin(t * 2.6 + i * 1.7) * 0.6 : 0;
      ctx.moveTo(x0, y + J(h, 30 + i, 1) * 0.4);
      ctx.lineTo((x0 + x1) / 2, y + sl + J(h, 34 + i, 1) * 0.5);
      ctx.lineTo(x1, y + J(h, 38 + i, 0) * 0.4);
    }
    ctx.stroke();
  }

  // ---- moon -> sun dial ----
  const DX = 606;
  const DY = 330;
  const DR = 16;

  let lg = 1;      // text/icon scale for this draw call (1 or LARGE_K)
  let feedDim = 1; // dial + clock alpha multiplier (0.5 while feeding)

  // ---- veil meter: how visible you are (eye icon + 5 ticks), cold blue-grey hidden -> candle gold exposed ----
  const VEIL_X = 56;
  const VEIL_MID = 319;

  /** Blend of hidden and exposed colours as 'rgb(r,g,b)' for k 0..1. */
  function veilColor(k) {
    const r = Math.round(143 + (255 - 143) * k);
    const g = Math.round(168 + (210 - 168) * k);
    const b = Math.round(200 + (122 - 200) * k);
    return 'rgb(' + r + ',' + g + ',' + b + ')';
  }

  function drawVeil(h, ctx, k, t, reduced) {
    const col = veilColor(k);
    const sc = 0.45;
    // gentle 0.5 Hz breathe at full exposure only
    const breathe = k > 0.95 && !reduced ? 0.85 + 0.15 * Math.sin(t * Math.PI) : 1;
    ctx.strokeStyle = col;
    ctx.lineWidth = 1;
    ctx.globalAlpha = 0.6 * breathe;
    // eye: lid opens from closed (flat line) to wide with exposure
    const open = k < 0.1 ? 0 : k < 0.5 ? 2.5 : 4.5;
    const ex = VEIL_X;
    const ey = VEIL_MID - 9;
    ctx.beginPath();
    ctx.moveTo(ex - 7 + J(h, 20, 0) * sc, ey + J(h, 20, 1) * sc);
    if (open === 0) {
      ctx.quadraticCurveTo(ex, ey + 2.5, ex + 7 + J(h, 21, 0) * sc, ey + J(h, 21, 1) * sc); // closed: drooping lid
    } else {
      ctx.quadraticCurveTo(ex, ey - open * 2, ex + 7 + J(h, 21, 0) * sc, ey + J(h, 21, 1) * sc);
      ctx.quadraticCurveTo(ex, ey + open * 2, ex - 7, ey);
    }
    ctx.stroke();
    if (open > 0) {
      ctx.beginPath();
      ctx.arc(ex, ey, open > 3 ? 1.8 : 1.2, 0, TWO_PI);
      ctx.stroke();
    }
    if (open > 3) {
      // lashes
      ctx.beginPath();
      for (let i = -1; i <= 1; i++) {
        ctx.moveTo(ex + i * 3.5, ey - open + 0.5);
        ctx.lineTo(ex + i * 4.5, ey - open - 2.5);
      }
      ctx.stroke();
    }
    // five ticks, lit left to right by exposure
    for (let i = 0; i < 5; i++) {
      const on = k * 5 - i;
      const fill = on >= 1 ? 1 : on > 0 ? on : 0;
      ctx.globalAlpha = (0.2 + 0.5 * fill) * breathe;
      ctx.beginPath();
      const x = ex - 8 + i * 4 + J(h, 30 + i, 0) * sc;
      ctx.moveTo(x, VEIL_MID + 5);
      ctx.lineTo(x, VEIL_MID + 5 - 3 - 3 * fill);
      ctx.stroke();
    }
  }

  function drawDial(h, ctx, frac, hour, minute, t) {
    const sunK = frac <= 0.9 ? 0 : frac >= 1 ? 1 : (frac - 0.9) / 0.1;
    ctx.lineCap = 'round';
    ctx.lineJoin = 'round';
    ctx.strokeStyle = COL_LINE;
    // dotted track: 9 dots on the upper semicircle
    ctx.lineWidth = 1.3;
    ctx.globalAlpha = feedDim * (0.3);
    ctx.beginPath();
    for (let i = 0; i < 9; i++) {
      const a = Math.PI + (i / 8) * Math.PI;
      const x = DX + Math.cos(a) * DR + J(h, 50 + i, 0) * 0.3;
      const y = DY + Math.sin(a) * DR + J(h, 50 + i, 1) * 0.3;
      ctx.moveTo(x, y);
      ctx.lineTo(x + 0.01, y);
    }
    ctx.stroke();
    ctx.lineWidth = 1;
    // moon crescent at the left end (fades as the night wears on)
    const mx = DX - DR - 6;
    ctx.globalAlpha = feedDim * (0.45 * (1 - 0.5 * frac));
    ctx.beginPath();
    ctx.moveTo(mx + 0.5 + J(h, 60, 0) * 0.3, DY + 3.5);
    ctx.arc(mx + J(h, 61, 0) * 0.3, DY + J(h, 61, 1) * 0.3, 3.5, Math.PI / 2, Math.PI * 1.5, false);
    ctx.quadraticCurveTo(mx - 1.8, DY, mx + 0.5, DY + 3.5);
    ctx.stroke();
    // rayed sun at the right end (brightens after 05:00)
    const sx = DX + DR + 6;
    ctx.globalAlpha = feedDim * (0.3 + 0.5 * sunK);
    ctx.beginPath();
    ctx.arc(sx + J(h, 62, 0) * 0.3, DY + J(h, 62, 1) * 0.3, 2.2, 0, TWO_PI);
    for (let i = 0; i < 8; i++) {
      const a = (i / 8) * TWO_PI + 0.2;
      const ca = Math.cos(a);
      const sa = Math.sin(a);
      const r1 = 3.6;
      const r2 = 5.2 + J(h, 63 + i, 0) * 0.5;
      ctx.moveTo(sx + ca * r1, DY + sa * r1);
      ctx.lineTo(sx + ca * r2, DY + sa * r2);
    }
    ctx.stroke();
    // marker
    const ma = Math.PI + frac * Math.PI;
    ctx.globalAlpha = feedDim * (0.6);
    ctx.lineWidth = 2.4;
    ctx.beginPath();
    const px = DX + Math.cos(ma) * DR + J(h, 80, 0) * 0.4;
    const py = DY + Math.sin(ma) * DR + J(h, 80, 1) * 0.4;
    ctx.moveTo(px, py);
    ctx.lineTo(px + 0.01, py);
    ctx.stroke();
    // tiny clock text
    ctx.globalAlpha = feedDim * (0.7);
    ctx.fillStyle = COL_LINE;
    ctx.font = (10 * lg) + 'px ' + FONT_MONO;
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.fillText(timeText(h, hour, minute), DX + J(h, 81, 0) * 0.4, DY + 13 + (lg - 1) * 4 + J(h, 81, 1) * 0.4);
  }

  // ---- hunger extras (v0.9): all optional, dim, drawn only when their field is present ----
  const PW_X0 = 84;
  const PW_X0_LG = 94;
  const PW_DX_LG = 30;   // powers row: right of the vial (x 21..38) and its gift ring (r 24), left of centre
  const PW_Y = 318;
  const PW_DX = 24;
  const POWER_MAX = 3;

  function drawOver(h, ctx, o, t, reduced) {
    const v = num(o.over01, 0, 0, 1);
    if (!(v > 0) && o.overOpen !== true) return;
    const pulse = v > 0.8 && !reduced ? 0.75 + 0.25 * Math.sin(t * 7) : 1;
    ctx.strokeStyle = COL_CORAL;
    ctx.lineWidth = 1.2;
    ctx.lineCap = 'round';
    ctx.globalAlpha = 0.55 * pulse;
    // faint track + fill, hugging the top of the vial
    ctx.beginPath();
    ctx.moveTo(21 + J(h, 90, 0) * 0.3, 293);
    ctx.lineTo(39, 293 + J(h, 91, 1) * 0.3);
    ctx.globalAlpha = 0.25;
    ctx.stroke();
    if (v > 0) {
      ctx.globalAlpha = 0.6 * pulse;
      ctx.beginPath();
      ctx.moveTo(21, 293);
      ctx.lineTo(21 + 18 * v, 293 + J(h, 92, 1) * 0.3);
      ctx.stroke();
    }
  }

  function drawPowers(h, ctx, list, t, reduced) {
    if (!Array.isArray(list)) return;
    let slot = 0;
    for (let i = 0; i < list.length && slot < POWER_MAX; i++) {
      const p = list[i];
      if (!p || typeof p !== 'object') continue;
      const st = p.state;
      if (st !== 'poor' && st !== 'cooldown' && st !== 'ready') continue; // locked / unknown: nothing
      const x = lg > 1 ? PW_X0_LG + slot * PW_DX_LG : PW_X0 + slot * PW_DX;
      slot++;
      const alpha = st === 'poor' ? 0.25 : st === 'cooldown' ? 0.4 : 0.8;
      const I = VCS.Icons;
      ctx.save();
      ctx.translate(x, PW_Y);
      let ok = false;
      if (I && I.draw && typeof p.id === 'string' && I.NAMES.indexOf(p.id) >= 0) {
        ok = I.draw(ctx, p.id, 18 * lg, t, { alpha: alpha, color: COL_BLUE, still: reduced });
      }
      ctx.restore();
      ctx.strokeStyle = COL_BLUE;
      ctx.lineWidth = 1;
      if (!ok) {
        ctx.globalAlpha = alpha;
        ctx.beginPath();
        ctx.arc(x, PW_Y, 7 * lg, 0, TWO_PI);
        ctx.stroke();
      }
      if (st === 'cooldown') {
        const k = num(p.cd01, 0, 0, 1);
        if (k > 0) {
          ctx.globalAlpha = 0.5;
          ctx.beginPath();
          ctx.arc(x, PW_Y, 11 * lg, -Math.PI / 2, -Math.PI / 2 + TWO_PI * k);
          ctx.stroke();
        }
      } else if (st === 'ready' && typeof p.key === 'string' && p.key) {
        ctx.globalAlpha = 0.7;
        ctx.fillStyle = COL_BLUE;
        ctx.font = (8 * lg) + 'px ' + FONT_MONO;
        ctx.textAlign = 'center';
        ctx.textBaseline = 'middle';
        ctx.fillText(p.key.slice(0, 2), x, PW_Y + 15 * lg);
      }
    }
  }

  /** Rocks left: three small pebbles just right of the powers row; spent ones are a faint dotted outline. */
  function drawRocks(h, ctx, n, max) {
    const x0 = (lg > 1 ? PW_X0_LG + POWER_MAX * PW_DX_LG : PW_X0 + POWER_MAX * PW_DX) + 4;
    ctx.strokeStyle = COL_LINE;
    ctx.lineWidth = 1;
    ctx.lineJoin = 'round';
    for (let i = 0; i < max; i++) {
      const x = x0 + i * 9 * lg;
      const y = PW_Y;
      const on = i < n;
      ctx.globalAlpha = on ? 0.6 : 0.18;
      ctx.beginPath();
      ctx.moveTo(x - 3 * lg + J(h, 60 + i, 0) * 0.3, y + 2 * lg);
      ctx.lineTo(x - 2 * lg, y - 2 * lg);
      ctx.lineTo(x + 1 * lg, y - 3 * lg + J(h, 60 + i, 1) * 0.3);
      ctx.lineTo(x + 3.5 * lg, y);
      ctx.lineTo(x + 2 * lg, y + 3 * lg);
      ctx.lineTo(x - 2 * lg, y + 3 * lg);
      ctx.closePath();
      ctx.stroke();
    }
  }

  function drawFear(h, ctx, fear) {
    const n = Math.ceil(fear / 3);
    ctx.strokeStyle = COL_BLUE;
    ctx.lineWidth = 0.9;
    ctx.lineCap = 'round';
    for (let i = 0; i < n && i < 5; i++) {
      const part = Math.min(3, fear - i * 3);
      ctx.globalAlpha = part >= 3 ? 0.55 : 0.3;
      const cx = (lg > 1 ? 570 : 582) + i * 12 * lg;
      const cy = 304;
      ctx.beginPath();
      ctx.moveTo(cx - 4 * lg, cy + J(h, 100 + i, 0) * 0.3);
      ctx.quadraticCurveTo(cx, cy - 4.5 * lg, cx + 4 * lg, cy + J(h, 110 + i, 1) * 0.3);
      ctx.quadraticCurveTo(cx, cy + 4.5 * lg, cx - 4 * lg, cy);
      ctx.moveTo(cx + 1.2 * lg, cy);
      ctx.arc(cx, cy, 1.2 * lg, 0, TWO_PI);
      ctx.stroke();
    }
  }

  function drawStill(h, ctx, k) {
    ctx.strokeStyle = COL_BLUE;
    ctx.lineWidth = 1.5;
    ctx.globalAlpha = 0.12 * k;
    const m = 4;
    ctx.beginPath();
    ctx.moveTo(m, m + J(h, 120, 1) * 0.5);
    ctx.lineTo(W - m, m + J(h, 121, 1) * 0.5);
    ctx.lineTo(W - m + J(h, 122, 0) * 0.5, H - m);
    ctx.lineTo(m, H - m + J(h, 123, 1) * 0.5);
    ctx.lineTo(m + J(h, 124, 0) * 0.5, m);
    ctx.stroke();
  }

  function drawMist(h, ctx, k, t, reduced) {
    ctx.strokeStyle = COL_BLUE;
    ctx.lineWidth = 1;
    ctx.lineCap = 'round';
    ctx.globalAlpha = 0.25 * k;
    ctx.beginPath();
    for (let i = 0; i < 4; i++) {
      const y = 140 + i * 26;
      const x0 = 70 + i * 17;
      const x1 = W - 70 - ((i * 29) % 40);
      const dr = reduced ? 0 : Math.sin(t * 0.6 + i * 1.9) * 6;
      ctx.moveTo(x0 + dr, y);
      ctx.quadraticCurveTo((x0 + x1) / 2, y - 3 + J(h, 130 + i, 1) * 0.6, x1 + dr, y + 1);
    }
    ctx.stroke();
  }

  function drawGift(h, ctx, k, t) {
    ctx.strokeStyle = COL_CORAL;
    ctx.lineWidth = 1.2;
    ctx.globalAlpha = 0.6 * k;
    ctx.beginPath();
    ctx.arc(VX + J(h, 140, 0) * 0.4, 317 + J(h, 140, 1) * 0.4, 22 + 3 * (1 - k), 0, TWO_PI);
    ctx.stroke();
  }

  function drawHunger(h, ctx, o, t, reduced) {
    if (o.over01 !== undefined || o.overOpen === true) drawOver(h, ctx, o, t, reduced);
    if (o.powers !== undefined) drawPowers(h, ctx, o.powers, t, reduced);
    if (typeof o.rocks === 'number') drawRocks(h, ctx, Math.max(0, Math.min(9, Math.floor(o.rocks))), 3);
    const fear = num(o.fear, 0, 0, 15);
    if (fear > 0) drawFear(h, ctx, fear);
    const still = num(o.still01, 0, 0, 1);
    if (still > 0) drawStill(h, ctx, still);
    const mist = num(o.mistK, 0, 0, 1);
    if (mist > 0) drawMist(h, ctx, mist, t, reduced);
    const gift = num(o.giftFlash, 0, 0, 1);
    if (gift > 0) drawGift(h, ctx, gift, t);
  }

  /**
   * Draw the whole HUD.
   * s: { largeText (bool, text/icons x1.3), blood01, weak, frac, hour, minute, t, boil, reduced, pulse01, vialPulse (0..1, vial scale 1+0.08*p, none when reduced), feeding (dial + clock alpha x0.5) }
   */
  function drawHud(h, ctx, s) {
    try {
      if (!ctx) return;
      h = hudOf(h);
      const o = s && typeof s === 'object' ? s : {};
      const t = num(o.t, 0, -1e9, 1e9);
      const reduced = o.reduced === true;
      lg = o.largeText === true ? LARGE_K : 1;
      const blood = num(o.blood01, 0, 0, 1);
      const weak = num(o.weak, 0, 0, 1);
      const frac = num(o.frac, 0, 0, 1);
      const pulse01 = num(o.pulse01, 0, 0, 1);
      let hour = num(o.hour, -1, 0, 23);
      let minute = num(o.minute, -1, 0, 59);
      if (hour < 0 || minute < 0) {
        const total = Math.round(frac * 600);
        hour = (20 + Math.floor(total / 60)) % 24;
        minute = total % 60;
      } else {
        hour = Math.floor(hour);
        minute = Math.floor(minute);
      }
      setFrame(h, t, o.boil === true && !reduced);
      if (ctx.save) ctx.save();
      ctx.globalCompositeOperation = 'source-over';
      // crosshair dot
      ctx.globalAlpha = 0.3;
      ctx.fillStyle = '#ffffff';
      ctx.fillRect(W / 2 - 1, H / 2 - 1, 2, 2);
      try {
        const fa = o.feeding === true;
        const vp = reduced ? 0 : num(o.vialPulse, 0, 0, 1);
        drawVial(h, ctx, blood, weak, t, reduced, vp);
        if (typeof o.veil === 'number') drawVeil(h, ctx, num(o.veil, 0, 0, 1), t, reduced);
        feedDim = fa ? 0.5 : 1;
        drawDial(h, ctx, frac, hour, minute, t);
        feedDim = 1;
      } catch (e) { logOnce('hud', e); }
      // cooldown arc
      if (pulse01 > 0) {
        ctx.globalAlpha = 0.5 * Math.min(1, pulse01 / 0.15);
        ctx.strokeStyle = COL_LINE;
        ctx.lineWidth = 0.75;
        ctx.beginPath();
        ctx.arc(W / 2, H - 18, 6, -Math.PI / 2, -Math.PI / 2 + TWO_PI * pulse01);
        ctx.stroke();
      }
      try { drawHunger(h, ctx, o, t, reduced); } catch (e) { logOnce('hunger', e); }
      lg = 1;
      ctx.globalAlpha = 1;
      if (ctx.restore) ctx.restore();
    } catch (e) {
      lg = 1;
      logOnce('drawHud', e);
      try { if (ctx && ctx.restore) ctx.restore(); } catch (_) { /* ignore */ }
    }
  }

  // ---- dawn ----
  /** Build two edge-weighted grey grain frames (low-res, scaled up when drawn). Null when no DOM. */
  function buildGrain(h, ctx) {
    h.grainTried = true;
    h.grainFor = ctx;
    h.grain = null;
    const cv = ctx.canvas;
    const doc = cv && cv.ownerDocument;
    if (!doc || !doc.createElement) return;
    const frames = [];
    for (let f = 0; f < 2; f++) {
      const c = doc.createElement('canvas');
      c.width = GRAIN_W;
      c.height = GRAIN_H;
      const g = c.getContext && c.getContext('2d');
      if (!g || !g.createImageData || !g.putImageData) return;
      const img = g.createImageData(GRAIN_W, GRAIN_H);
      const d = img.data;
      let seed = (0x9e3779b9 + f * 0x85ebca6b) >>> 0;
      for (let y = 0; y < GRAIN_H; y++) {
        const ny = (y / GRAIN_H) * 2 - 1;
        for (let x = 0; x < GRAIN_W; x++) {
          const nx = (x / GRAIN_W) * 2 - 1;
          const dist = Math.sqrt(nx * nx + ny * ny) / 1.25;
          let e = (dist - 0.4) / 0.6;
          e = e < 0 ? 0 : e > 1 ? 1 : e;
          seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0;
          const r = seed / 4294967296;
          const i = (y * GRAIN_W + x) * 4;
          const v = 120 + ((seed >>> 8) & 63);
          d[i] = v; d[i + 1] = v; d[i + 2] = v + 4;
          d[i + 3] = Math.min(255, Math.floor(357 * e * e * r * r));
        }
      }
      g.putImageData(img, 0, 0);
      frames.push(c);
    }
    h.grain = frames;
  }

  /**
   * Dawn: soft grey edge vignette and grey grain creeping in from the edges. k 0..1; k<=0 draws nothing.
   */
  function drawDawn(h, ctx, k, t, reduced) {
    try {
      if (!ctx) return;
      k = num(k, 0, 0, 1);
      if (!(k > 0)) return;
      h = hudOf(h);
      t = num(t, 0, -1e9, 1e9);
      if (ctx.save) ctx.save();
      ctx.globalCompositeOperation = 'source-over';
      // soft grey vignette
      if (ctx.createRadialGradient) {
        if (!h.vig || h.vigFor !== ctx || h.vigW !== W || h.vigH !== H) {
          const g = ctx.createRadialGradient(W / 2, H / 2, H * 0.3, W / 2, H / 2, W * 0.62);
          if (g && g.addColorStop) {
            g.addColorStop(0, 'rgba(150,150,158,0)');
            g.addColorStop(1, 'rgba(150,150,158,1)');
            h.vig = g; h.vigFor = ctx; h.vigW = W; h.vigH = H;
          }
        }
        if (h.vig) {
          ctx.globalAlpha = 0.22 * k;
          ctx.fillStyle = h.vig;
          ctx.fillRect(0, 0, W, H);
        }
      }
      // grain
      if (!h.grainTried || h.grainFor !== ctx) {
        try { buildGrain(h, ctx); } catch (e) { h.grain = null; logOnce('grain', e); }
      }
      if (h.grain && ctx.drawImage) {
        const f = reduced === true ? 0 : Math.floor(t * 2) & 1; // swap every 0.5 s (<= 2 changes/s)
        ctx.globalAlpha = 0.38 * k;
        ctx.imageSmoothingEnabled = false;
        ctx.drawImage(h.grain[f], 0, 0, W, H);
      }
      ctx.globalAlpha = 1;
      if (ctx.restore) ctx.restore();
    } catch (e) {
      logOnce('drawDawn', e);
      try { if (ctx && ctx.restore) ctx.restore(); } catch (_) { /* ignore */ }
    }
  }

  // ---- title card ----
  /** Small plain line(s) under the title card (word-wrapped, at most 2 lines). */
  function drawCardSub(ctx, sub, a, k) {
    const words = sub.slice(0, 160).split(' ');
    const lines = [];
    let cur = '';
    for (let i = 0; i < words.length; i++) {
      const nx = cur ? cur + ' ' + words[i] : words[i];
      if (nx.length > 72 && cur) { lines.push(cur); cur = words[i]; } else cur = nx;
    }
    if (cur) lines.push(cur);
    ctx.fillStyle = COL_LINE;
    ctx.globalAlpha = 0.7 * a;
    ctx.font = Math.round(11 * k) + 'px ' + FONT_MONO;
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    for (let i = 0; i < lines.length && i < 2; i++) ctx.fillText(lines[i], W / 2, H / 2 + 14 * k + i * 15 * k);
    ctx.globalAlpha = 1;
  }

  /** Boiled outline lettering, centred. age in seconds since the card began; no-op outside 0..CARD_DUR. */
  function drawCard(h, ctx, text, age, t, boil, sub, opts) {
    try {
      if (!ctx || typeof text !== 'string' || !text) return;
      age = num(age, -1, -1, 1e9);
      if (age < 0 || age > CARD_DUR) return;
      t = num(t, 0, -1e9, 1e9);
      let a = 1;
      if (age < CARD_IN) a = age / CARD_IN;
      else if (age > CARD_DUR - CARD_OUT) a = (CARD_DUR - age) / CARD_OUT;
      if (!(a > 0.01)) return;
      const on = boil === true;
      const frame = on ? Math.floor(t * 10) & 3 : 0;
      const str = text.length > 24 ? text.slice(0, 24) : text;
      const k = opts && opts.largeText === true ? LARGE_K : 1;
      const adv = Math.min(20 * k, 600 / Math.max(1, str.length - 1));
      const x0 = W / 2 - ((str.length - 1) * adv) / 2;
      if (ctx.save) ctx.save();
      ctx.globalCompositeOperation = 'source-over';
      ctx.strokeStyle = COL_LINE;
      ctx.lineJoin = 'round';
      ctx.lineCap = 'round';
      ctx.lineWidth = 1.3;
      ctx.globalAlpha = 0.85 * a;
      ctx.textBaseline = 'middle';
      ctx.textAlign = 'center';
      ctx.font = 'bold ' + Math.round(28 * k) + 'px ' + FONT_MONO;
      const j = on ? 1 : 0;
      for (let i = 0; i < str.length; i++) {
        const ch = str.charAt(i);
        if (ch === ' ') continue;
        const dx = (hash2(i, frame) - 0.5) * 2 * j;
        const dy = (hash2(i + 40, frame) - 0.5) * 2 * j;
        const rot = (hash2(i + 80, frame) - 0.5) * 0.1 * j;
        const base = Math.sin(i * 1.7) * 2.6 + (hash2(i, 9) - 0.5) * 2.4;
        ctx.save();
        ctx.translate(x0 + i * adv + dx, H / 2 - 20 + base + dy);
        ctx.rotate(rot + Math.sin(i * 2.3) * 0.04);
        ctx.strokeText(ch, 0, 0);
        ctx.restore();
      }
      ctx.globalAlpha = 1;
      if (typeof sub === 'string' && sub) drawCardSub(ctx, sub, a, k);
      if (ctx.restore) ctx.restore();
    } catch (e) {
      logOnce('drawCard', e);
      try { if (ctx && ctx.restore) ctx.restore(); } catch (_) { /* ignore */ }
    }
  }

  /**
   * One-line hint, bottom-centre above the vial row. age = seconds since shown; fades in/out over 0.4 s.
   * opts: { dur (default 4 s), largeText, reduced }. No-op outside 0..dur.
   */
  function drawHint(h, ctx, text, age, t, opts) {
    try {
      if (!ctx || typeof text !== 'string' || !text) return;
      const o = opts && typeof opts === 'object' ? opts : {};
      const dur = num(o.dur, HINT_DUR, 2 * HINT_FADE, 60);
      age = num(age, -1, -1, 1e9);
      if (age < 0 || age > dur) return;
      let a = 1;
      if (age < HINT_FADE) a = age / HINT_FADE;
      else if (age > dur - HINT_FADE) a = (dur - age) / HINT_FADE;
      if (!(a > 0.01)) return;
      const k = o.largeText === true ? LARGE_K : 1;
      const px = Math.round(10 * k);
      const str = text.length > 90 ? text.slice(0, 90) : text;
      if (ctx.save) ctx.save();
      ctx.globalCompositeOperation = 'source-over';
      ctx.font = px + 'px ' + FONT_MONO;
      ctx.textAlign = 'center';
      ctx.textBaseline = 'middle';
      let w = str.length * px * 0.6;
      if (ctx.measureText) {
        const m = ctx.measureText(str);
        if (m && typeof m.width === 'number' && m.width > 0) w = m.width;
      }
      w = Math.min(w, W - 40);
      const cy = 282 - (k - 1) * 10;
      const ph = px + 10;
      ctx.globalAlpha = 0.6 * a;
      ctx.fillStyle = '#04070e';
      ctx.fillRect(W / 2 - w / 2 - 8, cy - ph / 2, w + 16, ph);
      ctx.globalAlpha = 0.8 * a;
      ctx.fillStyle = COL_LINE;
      ctx.fillText(str, W / 2, cy, W - 40);
      ctx.globalAlpha = 1;
      if (ctx.restore) ctx.restore();
    } catch (e) {
      logOnce('drawHint', e);
      try { if (ctx && ctx.restore) ctx.restore(); } catch (_) { /* ignore */ }
    }
  }

  /** Black rect with alpha k (0..1). */
  function drawFade(ctx, k) {
    try {
      if (!ctx) return;
      k = num(k, 0, 0, 1);
      if (!(k > 0)) return;
      const cv = ctx.canvas;
      const w = cv && cv.width > 0 ? cv.width : W;
      const hh = cv && cv.height > 0 ? cv.height : H;
      ctx.globalCompositeOperation = 'source-over';
      ctx.globalAlpha = k;
      ctx.fillStyle = '#000';
      ctx.fillRect(0, 0, w, hh);
      ctx.globalAlpha = 1;
    } catch (e) {
      logOnce('drawFade', e);
    }
  }

  const Hud = {
    create: create,
    drawHud: drawHud,
    drawDawn: drawDawn,
    drawCard: drawCard,
    drawHint: drawHint,
    drawFade: drawFade,
    CARD_DUR: CARD_DUR
  };
  VCS.Hud = Hud;
  if (typeof module !== 'undefined' && module.exports) module.exports = Hud;
})(typeof window !== 'undefined' ? window : globalThis);
