(function (root) {
  'use strict';
  const VCS = (root.VCS = root.VCS || {});

  const TWO_PI = Math.PI * 2;
  const CELL = 16;
  const COL_PERSON = [255, 107, 91];
  const COL_CRYPT = [178, 140, 255];
  const COL_SAFE = [140, 122, 217];
  const COL_DOOR = [232, 242, 255];
  const COL_DOOR_OPEN = [255, 226, 196];
  /** Door line tints: wooden doors read warmer than the cool wall lines, iron gates a touch brighter. */
  const COL_WOOD_DOOR = '#ffe2c4';
  const COL_GATE = '#f4f8ff';
  const COL_WIN_GLOW = '#ffcf8a';
  /** Window line tints: candle gold when light spills through from the far side, cold glass otherwise. */
  const COL_WIN_LIT = '#ffd596';
  const COL_WIN_DARK = '#c4e2ff';
  /** Candle glow in lit window panes: max alpha (steady, no flicker). */
  const WIN_GLOW_MAX = 0.25;
  /** Warm screen-edge glow: alpha at full light (lightAt = 1). */
  const EDGE_GLOW_MAX = 1;
  /** Door lines are drawn this much brighter than wall lines (alpha multiplier, clamped to 1). */
  const DOOR_GAIN = 1.35;
  const C_LOW = [91, 127, 214];
  const C_MID = [207, 227, 255];
  const C_HI = [242, 248, 255];
  const MAX_DIST = 16;
  const VIS_TOL = 0.35;
  const FLASH_AGE = 0.12;
  const RING_SAMPLES = 270;
  const BASE_W = 640;
  const BASE_H = 360;
  const SEC_SAMPLES = 90;
  const COL_LOCK = '#ff8a78';
  const COL_RING_PERSON = '#ffb3a6';
  const COL_RING_MARKER = '#dcd0ff';
  const COL_RING_OTHER = '#e8f2ff';
  const COL_BOUNCE = '#7fa6ff';
  const COL_ARC = '#cfe3ff';
  const RIPPLE_V = 4.0;       // speed (cells/s) of water ripples spreading over a wall face
  const MAX_TRAIL = 4;
  /** Overlay opacity at grain level 1 (matches the old canvas grain's 4% alpha). */
  const GRAIN_BASE = 0.04;

  /** Log a render problem once per key (never throws). */
  function logOnce(r, key, e) {
    try {
      if (!r.logged) r.logged = {};
      if (r.logged[key]) return;
      r.logged[key] = true;
      const log = VCS.Log && VCS.Log.get('render');
      if (log) log.warn('render ' + key + ' failed', e);
    } catch (e2) {
      // logging must never throw
    }
  }

  /** Smoothstep 0..1 between edges a and b. */
  function smoothstep(a, b, x) {
    const u = x <= a ? 0 : x >= b ? 1 : (x - a) / (b - a);
    return u * u * (3 - 2 * u);
  }

  /** Linear interpolation. */
  function lerp(a, b, t) { return a + (b - a) * t; }

  // ---- Ripple-only vision: a surface is lit only while the wavefront passes, then a short afterglow ----
  /** Afterglow seconds per second of pulse fade (default fade 3 s -> 0.45 s; Lingering Echo scales it). */
  const AFTERGLOW_K = 0.18;
  const AFTERGLOW_MIN = 0.2;
  const AFTERGLOW_MAX = 1.0;

  /** Afterglow duration (s) for a pulse with the given fade. */
  function glowDur(fade) {
    const f = typeof fade === 'number' && fade > 0 ? fade : 3;
    const d = f * AFTERGLOW_K;
    return d < AFTERGLOW_MIN ? AFTERGLOW_MIN : d > AFTERGLOW_MAX ? AFTERGLOW_MAX : d;
  }

  /** Brightness multiplier 0..1 for a surface struck age seconds ago (1 at the front, 0 after dur). */
  function glow(age, dur) {
    if (!(age >= 0) || age >= dur) return 0;
    const k = 1 - age / dur;
    return k * k * (3 - 2 * k);
  }

  /**
   * Replace the sonar's long fade with the short afterglow: multiplier applied to a sonar brightness
   * sampled `age` seconds after the front of a pulse with the given fade.
   */
  function glowMul(age, fade) {
    const g = glow(age, glowDur(fade));
    if (g <= 0) return 0;
    const f = typeof fade === 'number' && fade > 0 ? fade : 3;
    const kf = 1 - age / f;
    return kf > 0.05 ? g / (kf * kf) : g;
  }

  /** CSS colour string for brightness b (cool blue tail to pale white). */
  function fadeStyle(b) {
    let c0;
    let c1;
    let t;
    if (b < 0.12) { c0 = C_LOW; c1 = C_LOW; t = 0; }
    else if (b < 0.45) { c0 = C_LOW; c1 = C_MID; t = (b - 0.12) / 0.33; }
    else if (b < 0.8) { c0 = C_MID; c1 = C_HI; t = (b - 0.45) / 0.35; }
    else { c0 = C_HI; c1 = C_HI; t = 0; }
    return 'rgb(' + Math.round(lerp(c0[0], c1[0], t)) + ',' + Math.round(lerp(c0[1], c1[1], t)) +
      ',' + Math.round(lerp(c0[2], c1[2], t)) + ')';
  }

  const STYLE_N = 32;
  const STYLES = [];
  for (let i = 0; i <= STYLE_N; i++) STYLES.push(fadeStyle(i / STYLE_N));

  /** Pre-built colour string for brightness b in 0..1. */
  function styleFor(b) { return STYLES[Math.max(0, Math.min(STYLE_N, Math.round(b * STYLE_N)))]; }

  /** Prefers-reduced-motion flag (false outside browsers). */
  function reducedMotion() {
    try {
      return !!(root.matchMedia && root.matchMedia('(prefers-reduced-motion: reduce)').matches);
    } catch (e) {
      return false;
    }
  }

  /** (Re)build offscreen buffers and atmosphere canvases for the renderer. */
  function build(r, cfg) {
    const scale = typeof cfg.renderScale === 'number' && cfg.renderScale > 0 ? cfg.renderScale : 1;
    const ow = Math.max(160, Math.round(BASE_W * scale));
    const oh = Math.max(90, Math.round(BASE_H * scale));
    const doc = r.canvas.ownerDocument || root.document;
    if (!r.off) r.off = doc.createElement('canvas');
    r.off.width = ow;
    r.off.height = oh;
    r.octx = r.off.getContext('2d');
    if (!r.octx) throw new Error('Renderer could not get a 2D context');
    r.config = cfg;
    r.ow = ow;
    r.oh = oh;
    r.cols = Math.max(80, ow >> 1);
    r.colW = ow / r.cols;
    r.wscale = ow / BASE_W;
    const n = r.cols;
    r.zbuf = new Float32Array(n);
    r.bcol = new Float32Array(n);
    r.acol = new Float32Array(n);
    r.bbot = new Float32Array(n);
    r.btop = new Float32Array(n);
    r.bf = 0;
    r.boilOn = false;
    r.dcol = new Uint8Array(n);
    r.wlit = new Float32Array(n);
    r.wcolU = new Float32Array(n);
    r.tch = new Uint8Array(n);
    if (typeof r.matDetail !== 'boolean') r.matDetail = true;
    r.arcLo = new Float32Array(MAX_TRAIL);
    r.arcHi = new Float32Array(MAX_TRAIL);
    r.arcP = new Int16Array(MAX_TRAIL);
    r.ytop = new Float32Array(n);
    r.ybot = new Float32Array(n);
    r.ytopD = new Float32Array(n);
    r.ybotD = new Float32Array(n);
    r.horizon = oh / 2;
    if (!r.glow) r.glow = doc.createElement('canvas');
    r.glow.width = Math.max(1, ow >> 1);
    r.glow.height = Math.max(1, oh >> 1);
    r.gctx = r.glow.getContext('2d');
    // Vignette: transparent centre, dark edges (made once).
    const W = r.canvas.width;
    const H = r.canvas.height;
    const vig = doc.createElement('canvas');
    vig.width = W;
    vig.height = H;
    const vctx = vig.getContext('2d');
    if (vctx) {
      const g = vctx.createRadialGradient(W / 2, H / 2, H * 0.28, W / 2, H / 2, Math.hypot(W, H) * 0.52);
      g.addColorStop(0, 'rgba(0,0,0,0)');
      g.addColorStop(1, 'rgba(0,0,0,0.75)');
      vctx.fillStyle = g;
      vctx.fillRect(0, 0, W, H);
    }
    r.vignette = vctx ? vig : null;
    // Warm edge vignette (shown when the player stands in light).
    const wv = doc.createElement('canvas');
    wv.width = W;
    wv.height = H;
    const wctx = wv.getContext('2d');
    if (wctx) {
      const g2 = wctx.createRadialGradient(W / 2, H / 2, H * 0.3, W / 2, H / 2, Math.hypot(W, H) * 0.5);
      g2.addColorStop(0, 'rgba(255,150,50,0)');
      g2.addColorStop(1, 'rgba(255,150,50,0.55)');
      wctx.fillStyle = g2;
      wctx.fillRect(0, 0, W, H);
    }
    r.warmVig = wctx ? wv : null;
    // Directional edge glows: one linear gradient per screen side (left, right, top).
    r.warmSide = null;
    try {
      const mk = function (x0, y0, x1, y1) {
        const c = doc.createElement('canvas');
        c.width = W;
        c.height = H;
        const cx = c.getContext('2d');
        if (!cx) return null;
        const g = cx.createLinearGradient(x0, y0, x1, y1);
        // Smoothstep fade over 8 stops: no visible band edge as the glow scales in and out.
        for (let i = 0; i <= 7; i++) {
          const u = i / 7;
          const k = 1 - u * u * (3 - 2 * u);
          g.addColorStop(u, 'rgba(255,150,50,' + (0.55 * k).toFixed(4) + ')');
        }
        cx.fillStyle = g;
        cx.fillRect(0, 0, W, H);
        return c;
      };
      const sl = mk(0, 0, W * 0.45, 0);
      const sr = mk(W, 0, W * 0.55, 0);
      const st = mk(0, 0, 0, H * 0.5);
      if (sl && sr && st) r.warmSide = { left: sl, right: sr, top: st };
    } catch (e) {
      r.warmSide = null;
    }
    if (!r.grain) {
      const gc = doc.createElement('canvas');
      gc.width = 128;
      gc.height = 128;
      const gctx = gc.getContext('2d');
      if (gctx) {
        const id = gctx.createImageData(128, 128);
        for (let i = 0; i < id.data.length; i += 4) {
          const v = 120 + Math.floor(Math.random() * 136);
          id.data[i] = v * 0.8;
          id.data[i + 1] = v * 0.9;
          id.data[i + 2] = v;
          id.data[i + 3] = 255;
        }
        gctx.putImageData(id, 0, 0);
        r.grain = gc;
        applyGrainImage(r, gc, doc);
      }
    }
  }

  /** Hand the grain tile to the CSS overlay (#grain) as a tiled data-URL background; never throws. */
  function applyGrainImage(r, gc, doc) {
    try {
      const el = doc && typeof doc.getElementById === 'function' ? doc.getElementById('grain') : null;
      if (!el || !el.style || typeof gc.toDataURL !== 'function') return;
      const url = gc.toDataURL('image/png');
      if (typeof url !== 'string' || url.indexOf('data:') !== 0) return;
      el.style.backgroundImage = 'url(' + url + ')';
      r.grainEl = el;
      r.grainApplied = -1;
      setGrain(r, typeof r.grainLevel === 'number' ? r.grainLevel : 1);
    } catch (e) {
      logOnce(r, 'grainOverlay', e);
    }
  }

  /** Film grain strength 0..1 (1 = the classic look, 4% opacity). Drives the #grain overlay's opacity. */
  function setGrain(r, level) {
    try {
      let l = Number(level);
      if (!isFinite(l)) l = 1;
      l = Math.max(0, Math.min(1, l));
      r.grainLevel = l;
      const el = r.grainEl;
      if (!el || !el.style) return;
      const o = r.quality >= 1 ? GRAIN_BASE * l : 0;
      if (o === r.grainApplied) return;
      r.grainApplied = o;
      el.style.opacity = String(o);
    } catch (e) {
      logOnce(r, 'setGrain', e);
    }
  }

  /** Create a renderer drawing to the given main canvas. */
  function create(canvas, config) {
    const ctx = canvas.getContext('2d');
    if (!ctx) throw new Error('Renderer could not get a 2D context');
    const r = {
      canvas: canvas,
      ctx: ctx,
      off: null,
      grain: null,
      hasFilter: 'filter' in ctx,
      reduced: reducedMotion(),
      litColumns: 0,
      sprites: 0,
      echoesDrawn: 0,
      ringsDrawn: 0,
      quality: 3,
      maxQuality: config && config.glowBlur ? 4 : 3,
      fpsEma: 60,
      lastFrame: 0,
      lowT: 0,
      highT: 0
    };
    build(r, config || {});
    return r;
  }

  /** Apply renderScale / fovDeg changes live (rebuilds buffers). */
  function setConfig(r, config) {
    try {
      build(r, config || {});
    } catch (e) {
      const log = VCS.Log && VCS.Log.get('render');
      if (log) log.error('setConfig failed', e);
    }
  }

  /** True when world point (x,y) is visible from the pulse origin. */
  function visibleFrom(pulse, x, y) {
    const vis = pulse.vis;
    if (!vis || !vis.length) return true;
    const dx = x - pulse.x;
    const dy = y - pulse.y;
    const d = Math.sqrt(dx * dx + dy * dy);
    let ang = Math.atan2(dy, dx);
    if (ang < 0) ang += TWO_PI;
    const n = vis.length;
    const idx = Math.round(ang / TWO_PI * n) % n;
    return d <= vis[idx] + VIS_TOL;
  }

  /** Line alpha from brightness and distance (depth cue). */
  function lineAlpha(b, dist) {
    return Math.min(1, 1.15 * Math.pow(b, 0.65)) / (1 + 0.12 * dist);
  }

  /** True when columns i-1 and i lie on the same continuous flush wall face. */
  function connected(hits, i) {
    const h = hits[i];
    const p = hits[i - 1];
    if (!h.hit || !p.hit || h.side !== p.side) return false;
    if (h.side === 0) return Math.abs(h.hitX - p.hitX) < 0.02 && Math.abs(h.hitY - p.hitY) < 1.5;
    return Math.abs(h.hitY - p.hitY) < 0.02 && Math.abs(h.hitX - p.hitX) < 1.5;
  }

  // Batched stroking: segments are grouped into (colour, alpha, width) buckets,
  // one Path2D per bucket, each stroked once per frame.
  // Colours: 0-3 brightness fade, 4 flash white, 5 door, 6 ripple arc, 7 bounce ripple arc.
  // Width classes: 0 normal, 1 thick, 2 thin.
  const NCOL = 12;
  const NALPHA = 8;
  const NKEY = NCOL * NALPHA * 3;
  /** Glow pass skips buckets with alpha index below this (only the bright wavefront glows). */
  const GLOW_MIN_AI = 4;
  const BUCKET_COLS = [];
  for (let k = 0; k < 4; k++) BUCKET_COLS.push(fadeStyle((k + 0.5) / 4));
  BUCKET_COLS.push('#ffffff', '#e8f2ff', COL_ARC, COL_BOUNCE, COL_WOOD_DOOR, COL_GATE, COL_WIN_LIT, COL_WIN_DARK);
  const WCLASS = [1.0, 1.5, 0.7];
  const bpaths = new Array(NKEY).fill(null);
  const bused = new Uint8Array(NKEY);
  const bkeys = [];
  let doorMode = 0; // 0 wall, 1 wooden door, 2 iron gate

  /** Path2D for colour index ci, alpha a and width class wc. */
  function pathForC(ci, a, wc) {
    let ai = Math.ceil(a * NALPHA) - 1;
    if (ai < 0) ai = 0; else if (ai >= NALPHA) ai = NALPHA - 1;
    const key = (ci * NALPHA + ai) * 3 + wc;
    if (!bused[key]) {
      bused[key] = 1;
      bpaths[key] = new Path2D();
      bkeys.push(key);
    }
    return bpaths[key];
  }

  /** Path2D for the bucket matching brightness, alpha, flash and width class. */
  function pathFor(b, a, flash, thick) {
    const ci = flash ? 4 : doorMode ? 7 + doorMode : Math.min(3, Math.floor(b * 4));
    if (doorMode && !flash) a = Math.min(1, a * DOOR_GAIN);
    return pathForC(ci, a, thick || flash ? 1 : 0);
  }

  /** Stroke all buckets (optional wide glow pass first) and reset them. */
  function flushBuckets(r, ctx, glow) {
    const n = bkeys.length;
    ctx.lineJoin = 'round';
    ctx.lineCap = 'round';
    for (let pass = glow ? 0 : 1; pass < 2; pass++) {
      ctx.globalCompositeOperation = pass === 0 ? 'lighter' : 'source-over';
      for (let k = 0; k < n; k++) {
        const key = bkeys[k];
        const wc = key % 3;
        const q = (key - wc) / 3;
        const ai = q % NALPHA;
        const ci = (q - ai) / NALPHA;
        const alpha = (ai + 1) / NALPHA;
        const w = WCLASS[wc] * r.wscale;
        if (pass === 0 && ai < GLOW_MIN_AI) continue;
        ctx.strokeStyle = BUCKET_COLS[ci];
        ctx.lineWidth = pass === 0 ? w * 3.4 : w;
        ctx.globalAlpha = pass === 0 ? alpha * 0.2 : alpha;
        ctx.stroke(bpaths[key]);
      }
    }
    for (let k = 0; k < n; k++) { bused[bkeys[k]] = 0; bpaths[bkeys[k]] = null; }
    bkeys.length = 0;
    ctx.globalCompositeOperation = 'source-over';
    ctx.globalAlpha = 1;
  }

  // ---- Line boil helpers (10 fps, 4 cycling seeds; offsets come from a precomputed table) ----
  /** Table jitter -1..1 for the current boil frame (0 when boil is off). */
  function J(r, id, axis) {
    return r.boilOn ? VCS.Ripple.jitter(r.bf, id, axis) : 0;
  }

  /** Smooth jitter along a column index: values at every 4th column are blended. */
  function wallJit(r, i, axis, salt) {
    const k = i >> 2;
    const f = (i & 3) * 0.25;
    const a = VCS.Ripple.jitter(r.bf, k * 2 + axis + salt, axis);
    const b = VCS.Ripple.jitter(r.bf, (k + 1) * 2 + axis + salt, axis);
    return a + (b - a) * f;
  }

  const samp = new Float64Array(4);
  const samp3 = new Float64Array(4);
  const has3 = function (name) { return typeof VCS.Sonar[name] === 'function'; };

  /**
   * Brightness / age / fade of the strongest pulse at (x,y,z) with the afterglow applied; writes samp3
   * [b, age, fade, idx] and returns b (0 when dark). Uses Sonar.sample3 when present (one scan).
   */
  function litAt3(sonar, x, y, z, t) {
    const Sonar = VCS.Sonar;
    let b = 0;
    if (has3('sample3')) {
      b = Sonar.sample3(sonar, x, y, z, t, samp3);
    } else {
      b = has3('brightnessAt3') ? Sonar.brightnessAt3(sonar, x, y, z, t) : Sonar.brightnessAt(sonar, x, y, t);
      samp3[0] = b;
      samp3[1] = b > 0 ? (has3('ageAt3') ? Sonar.ageAt3(sonar, x, y, z, t) : Sonar.ageAt(sonar, x, y, t)) : -1;
      samp3[2] = sonar.fade;
      samp3[3] = -1;
    }
    if (b > 0) {
      b *= glowMul(samp3[1], samp3[2]);
      samp3[0] = b;
      if (b <= 0) samp3[1] = -1;
    }
    return b;
  }

  /** Add one wall segment (top edge lit by bTop, bottom edge lit by bBot) between x0..x1 to its buckets. */
  function wallSeg(r, x0, x1, i0, i1, bTop, bBot, age, dist) {
    const flash = age >= 0 && age < FLASH_AGE;
    for (let e = 0; e < 2; e++) {
      const b = e === 0 ? bTop : bBot;
      if (b <= 0.01) continue;
      let a = lineAlpha(b, dist);
      if (flash) a = Math.min(1, a + 0.6 * (1 - age / FLASH_AGE));
      const path = pathFor(b, a, flash, dist < 1.5);
      if (e === 0) {
        path.moveTo(x0, r.ytopD[i0]);
        path.lineTo(x1, r.ytopD[i1]);
      } else {
        path.moveTo(x0, r.ybotD[i0]);
        path.lineTo(x1, r.ybotD[i1]);
      }
    }
  }

  /** Add a vertical line at x between yt..yb (leaning by lean px at the top), lit by two halves. */
  function vert(r, x, yt, yb, bTop, bBot, age, dist, mul, lean) {
    const flash = age >= 0 && age < FLASH_AGE;
    const ym = (yt + yb) / 2;
    const xm = x + lean / 2;
    for (let h = 0; h < 2; h++) {
      const b = h === 0 ? bBot + (bTop - bBot) * 0.75 : bBot + (bTop - bBot) * 0.25;
      if (b <= 0.01) continue;
      let a = lineAlpha(b, dist) * mul;
      if (flash) a = Math.min(1, a + 0.5 * (1 - age / FLASH_AGE) * mul);
      const path = pathFor(b, a, flash && mul >= 1, mul >= 1 && dist < 1.5);
      if (h === 0) { path.moveTo(x + lean, yt); path.lineTo(xm, ym); }
      else { path.moveTo(xm, ym); path.lineTo(x, yb); }
    }
  }

  // ---- Material detail on lit wall faces (batched into the same stroke buckets) ----
  const MAT_B = 0.35;

  /** Stable hash 0..1 from a cell and a salt. */
  function cellHash(cx, cy, k) {
    let x = Math.imul(cx + 7, 374761393) + Math.imul(cy + 13, 668265263) + Math.imul(k + 1, 1274126177);
    x = Math.imul(x ^ (x >>> 13), 1103515245);
    return ((x ^ (x >>> 16)) >>> 0) / 4294967296;
  }

  /** Horizontal detail line from column j (height fraction va) to column i (vb); fractions run top 0 .. bottom 1. */
  function matH(r, i, va, vb, bt, bb, dist, wc, j) {
    const vm = (va + vb) * 0.5;
    const b = bt + (bb - bt) * vm;
    if (b < 0.1) return;
    const a = lineAlpha(b, dist) * 0.6;
    if (a < 0.04) return;
    const t0 = r.ytopD[j];
    const t1 = r.ytopD[i];
    const pth = pathForC(Math.min(3, Math.floor(b * 4)), a, wc);
    pth.moveTo((j + 0.5) * r.colW, t0 + (r.ybotD[j] - t0) * va);
    pth.lineTo((i + 0.5) * r.colW, t1 + (r.ybotD[i] - t1) * vb);
  }

  /** Vertical detail line on the boundary between columns i-1 and i, from height fraction v0 to v1. */
  function matV(r, i, v0, v1, bt, bb, dist, wc) {
    const vm = (v0 + v1) * 0.5;
    const b = bt + (bb - bt) * vm;
    if (b < 0.1) return;
    const a = lineAlpha(b, dist) * 0.6;
    if (a < 0.04) return;
    const yt = (r.ytopD[i - 1] + r.ytopD[i]) * 0.5;
    const yh = (r.ybotD[i - 1] + r.ybotD[i]) * 0.5 - yt;
    const x = i * r.colW + (r.boilOn ? J(r, i * 5 + ((v0 * 7) | 0), 0) * 0.4 * r.wscale : 0);
    const pth = pathForC(Math.min(3, Math.floor(b * 4)), a, wc);
    pth.moveTo(x, yt + yh * v0);
    pth.lineTo(x, yt + yh * v1);
  }

  /** True when u moved across threshold th between two adjacent columns. */
  function crossU(u0, u1, th) {
    return (u0 - th) * (u1 - th) <= 0 && u0 !== u1 && Math.abs(u0 - u1) < 0.5;
  }

  /** Material lines for column i (continuous with column i-1, same tile char). */
  function drawMat(r, hits, i, bt, bb) {
    const h = hits[i];
    const p = hits[i - 1];
    const dist = h.dist;
    const sameCell = h.cellX === p.cellX && h.cellY === p.cellY;
    const u0 = p.wallX;
    const u1 = h.wallX;
    const along = h.side === 0 ? h.hitY : h.hitX;
    const alongP = h.side === 0 ? p.hitY : p.hitX;
    const ch = r.tch[i];
    const cx = h.cellX;
    const cy = h.cellY;
    // Horizontal lines are drawn every second column (span of 2) to halve the path work.
    const hz = (i & 1) === 0 && i >= 2;
    const j = hz ? i - 2 : i - 1;
    const hOk = hz && hits[i - 2].cellX === cx && hits[i - 2].cellY === cy && hits[i - 2].side === h.side && r.tch[i - 2] === ch;
    switch (ch) {
      case 35: { // '#' stone: irregular blocks
        if (!sameCell) return;
        const v1 = 0.3 + 0.14 * (cellHash(cx, cy, 1) - 0.5);
        const v2 = 0.66 + 0.14 * (cellHash(cx, cy, 2) - 0.5);
        const w1 = (r.boilOn ? J(r, i, 1) : 0) * 0.006;
        if (hOk) {
          matH(r, i, v1 + w1, v1 + 0.015 * (cellHash(cx, cy, 5) - 0.5) - w1, bt, bb, dist, 2, j);
          matH(r, i, v2, v2 + 0.02 * (cellHash(cx, cy, 6) - 0.5) + w1, bt, bb, dist, 2, j);
        }
        const j0 = 0.2 + 0.6 * cellHash(cx, cy, 3);
        const j1 = 0.2 + 0.6 * cellHash(cx, cy, 4);
        const j2 = 0.2 + 0.6 * cellHash(cx, cy, 7);
        if (crossU(u0, u1, j0)) matV(r, i, 0.02, v1, bt, bb, dist, 2);
        if (crossU(u0, u1, j1)) matV(r, i, v1, v2, bt, bb, dist, 2);
        if (crossU(u0, u1, j2)) matV(r, i, v2, 0.98, bt, bb, dist, 2);
        break;
      }
      case 66: { // 'B' brick: coursing + staggered joints
        if (hz && hits[i - 2].side === h.side && r.tch[i - 2] === ch) for (let k = 1; k < 4; k++) matH(r, i, k * 0.25, k * 0.25, bt, bb, dist, 2, j);
        if (!sameCell) return;
        for (let row = 0; row < 4; row++) {
          const v0 = row * 0.25 + 0.01;
          const v1 = row * 0.25 + 0.24;
          if (row & 1) {
            if (crossU(u0, u1, 0.5)) matV(r, i, v0, v1, bt, bb, dist, 2);
          } else {
            if (crossU(u0, u1, 0.25)) matV(r, i, v0, v1, bt, bb, dist, 2);
            if (crossU(u0, u1, 0.75)) matV(r, i, v0, v1, bt, bb, dist, 2);
          }
        }
        break;
      }
      case 87: { // 'W' wood: grain squiggles
        const ph = cellHash(cx, cy, 8) * 6;
        if (!(hz && hits[i - 2].side === h.side && r.tch[i - 2] === ch)) break;
        const alongJ = h.side === 0 ? hits[j].hitY : hits[j].hitX;
        for (let k = 0; k < 3; k++) {
          const v = 0.2 + k * 0.3;
          matH(r, i, v + 0.03 * Math.sin(alongJ * 11 + ph + k * 2.1), v + 0.03 * Math.sin(along * 11 + ph + k * 2.1), bt, bb, dist, 2, j);
        }
        break;
      }
      case 73: { // 'I' iron fence: rails + bars with dark gaps
        if (hz && hits[i - 2].side === h.side && r.tch[i - 2] === ch) {
          matH(r, i, 0.14, 0.14, bt, bb, dist, 0, j);
          matH(r, i, 0.86, 0.86, bt, bb, dist, 0, j);
        }
        if (!sameCell) return;
        for (let k = 0; k < 5; k++) if (crossU(u0, u1, 0.1 + k * 0.2)) matV(r, i, 0.14, 0.86, bt, bb, dist, 0);
        break;
      }
      default: break;
    }
  }

  // ---- Door language: frame inset from the wall face, planks/hinges/handle (wood) or spear bars (gate) ----
  let dlCx = -1;
  let dlCy = -1;
  let dlLink = false;

  /** Door horizontal line at height fraction v from column i-1 to i (colour ci, width class wc, alpha mul). */
  function dH(r, i, v, bt, bb, dist, ci, wc, mul) {
    const b = bt + (bb - bt) * v;
    if (b < 0.08) return;
    const a = Math.min(1, lineAlpha(b, dist) * mul);
    if (a < 0.04) return;
    const j = i - 1;
    const t0 = r.ytopD[j];
    const t1 = r.ytopD[i];
    const pth = pathForC(ci, a, wc);
    pth.moveTo((j + 0.5) * r.colW, t0 + (r.ybotD[j] - t0) * v);
    pth.lineTo((i + 0.5) * r.colW, t1 + (r.ybotD[i] - t1) * v);
  }

  /** Door vertical line on the boundary of columns i-1 and i from height fraction v0 to v1. */
  function dV(r, i, v0, v1, bt, bb, dist, ci, wc, mul) {
    const b = bt + (bb - bt) * (v0 + v1) * 0.5;
    if (b < 0.08) return;
    const a = Math.min(1, lineAlpha(b, dist) * mul);
    if (a < 0.04) return;
    const yt = (r.ytopD[i - 1] + r.ytopD[i]) * 0.5;
    const yh = (r.ybotD[i - 1] + r.ybotD[i]) * 0.5 - yt;
    const pth = pathForC(ci, a, wc);
    const x = i * r.colW;
    pth.moveTo(x, yt + yh * v0);
    pth.lineTo(x, yt + yh * v1);
  }

  /** Details of a closed wooden door ('D') or iron gate ('G') for column i (continuous with i-1). */
  function drawDoor(r, world, hits, i, bt, bb, age) {
    const h = hits[i];
    const p = hits[i - 1];
    if (h.cellX !== p.cellX || h.cellY !== p.cellY) return;
    const u0 = p.wallX;
    const u1 = h.wallX;
    const dist = h.dist;
    const gate = r.tch[i] === 71;
    const ci = gate ? 9 : 8;
    // One-shot outline pulse while the afterglow lasts (a single ~1.2 Hz hump; none under reduced motion).
    let pm = 1;
    if (!r.reduced && age >= 0 && age < 0.4) pm += 0.5 * Math.sin(Math.PI * age / 0.4);
    const G = DOOR_GAIN;
    const f = pm * G; // frame
    const d = G;     // detail
    const inO = u0 >= 0.1 && u0 <= 0.9 && u1 >= 0.1 && u1 <= 0.9;
    const inI = u0 >= 0.17 && u0 <= 0.83 && u1 >= 0.17 && u1 <= 0.83;
    // Outer frame: lintel + jambs (brightest, thick) and an inset inner frame.
    if (inO) dH(r, i, 0.07, bt, bb, dist, ci, 1, f);
    if (crossU(u0, u1, 0.1) || crossU(u0, u1, 0.9)) dV(r, i, 0.07, 1, bt, bb, dist, ci, 1, f);
    if (inI) dH(r, i, 0.16, bt, bb, dist, ci, 2, d * 0.8);
    if (crossU(u0, u1, 0.17) || crossU(u0, u1, 0.83)) dV(r, i, 0.16, 1, bt, bb, dist, ci, 2, d * 0.8);
    if (gate) {
      // Spear-tipped bars with visible gaps, three crossbars.
      if (inI) { dH(r, i, 0.22, bt, bb, dist, ci, 0, d); dH(r, i, 0.55, bt, bb, dist, ci, 0, d); dH(r, i, 0.9, bt, bb, dist, ci, 2, d * 0.8); }
      for (let k = 0; k < 7; k++) {
        const ub = 0.23 + k * 0.09;
        if (crossU(u0, u1, ub)) {
          dV(r, i, 0.22, 1, bt, bb, dist, ci, 2, d);
          dV(r, i, 0.08, 0.22, bt, bb, dist, ci, 0, d * pm); // spear tip
        }
      }
    } else {
      // Vertical planks, hinge straps (left), ring handle (right).
      if (crossU(u0, u1, 0.33) || crossU(u0, u1, 0.5) || crossU(u0, u1, 0.67)) dV(r, i, 0.16, 1, bt, bb, dist, ci, 2, d * 0.7);
      if (u0 >= 0.17 && u0 <= 0.42 && u1 >= 0.17 && u1 <= 0.42) { dH(r, i, 0.3, bt, bb, dist, ci, 1, d); dH(r, i, 0.78, bt, bb, dist, ci, 1, d); }
      if (crossU(u0, u1, 0.6) || crossU(u0, u1, 0.7)) dV(r, i, 0.5, 0.62, bt, bb, dist, ci, 1, d);
      if (u0 >= 0.6 && u0 <= 0.7 && u1 >= 0.6 && u1 <= 0.7) { dH(r, i, 0.5, bt, bb, dist, ci, 1, d); dH(r, i, 0.62, bt, bb, dist, ci, 1, d); }
    }
    // Link doors (lead to another map): keystone on the lintel and two stud ticks.
    const cx = h.cellX;
    const cy = h.cellY;
    if (cx !== dlCx || cy !== dlCy) {
      dlCx = cx;
      dlCy = cy;
      dlLink = typeof world.isLinkDoor === 'function' && !!world.isLinkDoor(cx, cy);
    }
    if (dlLink) {
      if (crossU(u0, u1, 0.44) || crossU(u0, u1, 0.56)) dV(r, i, 0, 0.07, bt, bb, dist, ci, 1, f);
      if (u0 >= 0.44 && u0 <= 0.56 && u1 >= 0.44 && u1 <= 0.56) dH(r, i, 0, bt, bb, dist, ci, 1, f);
      if (crossU(u0, u1, 0.3) || crossU(u0, u1, 0.7)) dV(r, i, 0, 0.05, bt, bb, dist, ci, 0, f);
    }
  }

  // ---- Windows ('w' glass): crooked cross-framed panes, candle glow when the far side is lit ----
  let wlCx = -1;
  let wlCy = -1;
  let wlV = 0;

  /** Light (0..1) in the cell just beyond the window face struck by hit h (away from the viewer); cached per cell. */
  function windowLight(world, h) {
    const cx = h.cellX;
    const cy = h.cellY;
    if (cx === wlCx && cy === wlCy) return wlV;
    wlCx = cx;
    wlCy = cy;
    wlV = 0;
    if (typeof world.lightAt !== 'function') return 0;
    let bx;
    let by;
    if (h.side === 0) { bx = h.hitX - cx < 0.5 ? cx + 1.5 : cx - 0.5; by = cy + 0.5; }
    else { bx = cx + 0.5; by = h.hitY - cy < 0.5 ? cy + 1.5 : cy - 0.5; }
    const v = world.lightAt(bx, by);
    wlV = v > 0.05 ? (v > 1 ? 1 : v) : 0;
    return wlV;
  }

  /** Diagonal detail from column i-1 (height fraction va) to column i (vb). */
  function dD(r, i, va, vb, bt, bb, dist, ci, wc, mul) {
    const b = bt + (bb - bt) * (va + vb) * 0.5;
    if (b < 0.08) return;
    const a = Math.min(1, lineAlpha(b, dist) * mul);
    if (a < 0.04) return;
    const j = i - 1;
    const t0 = r.ytopD[j];
    const t1 = r.ytopD[i];
    const pth = pathForC(ci, a, wc);
    pth.moveTo((j + 0.5) * r.colW, t0 + (r.ybotD[j] - t0) * va);
    pth.lineTo((i + 0.5) * r.colW, t1 + (r.ybotD[i] - t1) * vb);
  }

  /** Window lines for column i on reveal: bowed frame, cross mullions, sill, and glints on dark glass. */
  function drawWindow(r, hits, i, bt, bb, age) {
    const h = hits[i];
    const p = hits[i - 1];
    if (h.cellX !== p.cellX || h.cellY !== p.cellY) return;
    const u0 = p.wallX;
    const u1 = h.wallX;
    const dist = h.dist;
    const lit = r.wlit[i] > 0;
    const ci = lit ? 10 : 11;
    let pm = 1;
    if (!r.reduced && age >= 0 && age < 0.4) pm += 0.4 * Math.sin(Math.PI * age / 0.4);
    const G = 1.25 * pm;
    const bow = (u1 - 0.5) * 0.05; // crooked: the frame leans a little to one side
    const inF = u0 >= 0.16 && u0 <= 0.84 && u1 >= 0.16 && u1 <= 0.84;
    if (inF) {
      dH(r, i, 0.16 + bow, bt, bb, dist, ci, 1, G);
      dH(r, i, 0.8 + bow * 0.6, bt, bb, dist, ci, 1, G);
      dH(r, i, 0.48 + bow * 0.8, bt, bb, dist, ci, 2, G * 0.8);
    }
    if (crossU(u0, u1, 0.16) || crossU(u0, u1, 0.84)) dV(r, i, 0.16, 0.8, bt, bb, dist, ci, 1, G);
    if (crossU(u0, u1, 0.5)) dV(r, i, 0.16, 0.8, bt, bb, dist, ci, 2, G * 0.8);
    // Sill: a thick ledge under the frame, wider than it.
    if (u0 >= 0.08 && u0 <= 0.92 && u1 >= 0.08 && u1 <= 0.92) dH(r, i, 0.87 + bow * 0.5, bt, bb, dist, ci, 1, G);
    if (crossU(u0, u1, 0.08) || crossU(u0, u1, 0.92)) dV(r, i, 0.85, 0.9, bt, bb, dist, ci, 0, G);
    if (!lit) {
      // Two diagonal glints in the top-left pane.
      if (u0 >= 0.22 && u0 <= 0.4 && u1 >= 0.22 && u1 <= 0.4) dD(r, i, 0.22 + (u0 - 0.22) * 1.3, 0.22 + (u1 - 0.22) * 1.3, bt, bb, dist, ci, 0, G);
      if (u0 >= 0.22 && u0 <= 0.32 && u1 >= 0.22 && u1 <= 0.32) dD(r, i, 0.32 + (u0 - 0.22) * 1.3, 0.32 + (u1 - 0.22) * 1.3, bt, bb, dist, ci, 2, G);
    }
  }

  /** Candle glow in the panes of a lit window column (visible without a ring) plus a faint floor spill. */
  function drawWindowGlow(r, i, v, dist, t, hx) {
    const ctx = r.octx;
    const hp = r.ybot[i] - r.ytop[i];
    if (hp < 6) return;
    let a = (0.06 + 0.19 * v) / (1 + 0.05 * dist);
    if (a > WIN_GLOW_MAX) a = WIN_GLOW_MAX;
    const u = r.wcolU[i];
    if (u > 0.47 && u < 0.53) return; // the vertical mullion stays dark
    if (u < 0.17 || u > 0.83) return;
    const x = i * r.colW;
    const w = r.colW + 0.6;
    const sk = (u - 0.5) * 0.05 * hp; // panes bow with the frame
    const y0 = r.ytop[i] + hp * 0.17 + sk;
    ctx.fillStyle = COL_WIN_GLOW;
    ctx.globalAlpha = a;
    ctx.fillRect(x, y0, w, hp * 0.3);
    ctx.fillRect(x, y0 + hp * 0.34, w, hp * 0.28);
    ctx.globalAlpha = a * 0.3; // spill on the floor below the sill
    ctx.fillRect(x, r.ybot[i], w, Math.min(hp * 0.14, 40));
    ctx.globalAlpha = 1;
  }

  /** Draw wall outlines, corner verticals and seams into the offscreen canvas. */
  function drawWalls(r, world, hits, sonar, t) {
    const n = r.cols;
    const oh = r.oh;
    const horizon = r.horizon;
    const Sonar = VCS.Sonar;
    const Ripple = VCS.Ripple;
    const WOBBLE_DUR = Ripple ? Ripple.WOBBLE_DUR : 0;
    const wob = !!Ripple && r.quality >= 1;
    const cw = r.colW;
    const b3 = has3('brightnessAt3');
    const a3 = has3('ageAt3');
    const s2 = has3('sample2');
    const A = 0.8 * r.wscale;
    const boil = r.boilOn;
    let lit = 0;
    for (let i = 0; i < n; i++) {
      const h = hits[i];
      const d = Math.max(0.05, h.dist);
      r.zbuf[i] = h.dist;
      let b = 0;
      let b0 = 0;
      let b1 = 0;
      let age = -1;
      if (h.hit) {
        let pf = sonar.fade;
        if (s2) {
          samp[3] = 0;
          Sonar.sample2(sonar, h.hitX, h.hitY, t, samp);
          b0 = samp[0];
          b1 = samp[1];
          b = b0 > b1 ? b0 : b1;
          if (b > 0.01) { age = samp[2]; if (samp[3] > 0) pf = samp[3]; }
        } else {
          if (b3) {
            b0 = Sonar.brightnessAt3(sonar, h.hitX, h.hitY, 0, t);
            b1 = Sonar.brightnessAt3(sonar, h.hitX, h.hitY, 1, t);
          } else {
            b0 = b1 = Sonar.brightnessAt(sonar, h.hitX, h.hitY, t);
          }
          b = b0 > b1 ? b0 : b1;
          if (b > 0.01) age = a3 ? Sonar.ageAt3(sonar, h.hitX, h.hitY, b0 >= b1 ? 0 : 1, t) : Sonar.ageAt(sonar, h.hitX, h.hitY, t);
        }
        // Ripple-only vision: keep the brightness only for a short afterglow behind the front.
        if (b > 0.01) {
          const g = glowMul(age, pf);
          b0 *= g;
          b1 *= g;
          b *= g;
          if (b <= 0.01) { b = b0 = b1 = 0; age = -1; }
        }
      }
      r.bcol[i] = b;
      r.bbot[i] = b0;
      r.btop[i] = b1;
      r.acol[i] = age;
      const tcode = h.hit && world.tileAt ? world.tileAt(h.cellX, h.cellY).charCodeAt(0) : 0;
      const isDoor = tcode === 68 || tcode === 71;
      r.tch[i] = tcode;
      r.dcol[i] = isDoor ? (tcode === 71 ? 2 : 1) : 0;
      r.wlit[i] = tcode === 119 ? windowLight(world, h) : 0;
      if (b > 0.01) lit++;
      const hp = oh / d;
      r.ytop[i] = horizon - hp / 2;
      r.ybot[i] = horizon + hp / 2;
      // Ripple: the struck surface quivers for a moment after the wavefront passes.
      let dy = 0;
      if (wob && age >= 0 && age < WOBBLE_DUR) {
        let amp = hp * 0.02;
        if (amp < 0.8) amp = 0.8; else if (amp > 3.5) amp = 3.5;
        dy = Ripple.wobble(age, (h.hitX + h.hitY) * 5.0) * amp * r.wscale;
      }
      // Crooked doors: the frame leans a few percent across its width.
      const tilt = isDoor ? hp * 0.05 * (h.wallX * (1 - h.wallX) * 4) * (0.4 + 0.6 * h.wallX) : 0;
      r.ytopD[i] = r.ytop[i] - dy + tilt + (boil && b > 0.01 ? wallJit(r, i, 0, 0) * A : 0);
      r.ybotD[i] = r.ybot[i] + dy + (boil && b > 0.01 ? wallJit(r, i, 1, 64) * A : 0);
      if (r.wlit[i] > 0) { r.wcolU[i] = h.wallX; drawWindowGlow(r, i, r.wlit[i], d, t, h.hitX + h.hitY); }
    }
    r.litColumns = lit;
    if (!lit) return;
    const ctx = r.octx;
    const matOn = r.matDetail && r.quality >= 2 && !(r.config && r.config.materialDetail === false);
    for (let i = 0; i < n; i++) {
      const h = hits[i];
      const b = r.bcol[i];
      const xc = (i + 0.5) * cw;
      const conn = i > 0 && connected(hits, i);
      doorMode = r.dcol[i];
      if (b > 0.01) {
        const age = r.acol[i];
        const endRun = i === n - 1 || !connected(hits, i + 1);
        if (conn) {
          let bt = r.btop[i];
          let bb = r.bbot[i];
          if (r.bcol[i - 1] > 0.01) { bt = (bt + r.btop[i - 1]) / 2; bb = (bb + r.bbot[i - 1]) / 2; }
          wallSeg(r, xc - cw, xc, i - 1, i, bt, bb, age, h.dist);
          const p = hits[i - 1];
          const along = h.side === 0 ? h.hitY : h.hitX;
          const alongP = h.side === 0 ? p.hitY : p.hitX;
          if (doorMode) {
            if (b > 0.12) drawDoor(r, world, hits, i, bt, bb, age);
          } else if (Math.floor(along) !== Math.floor(alongP)) {
            const yt = (r.ytopD[i - 1] + r.ytopD[i]) / 2;
            const yb = (r.ybotD[i - 1] + r.ybotD[i]) / 2;
            vert(r, xc - cw / 2 + J(r, i, 0) * A * 0.5, yt, yb, bt, bb, age, h.dist, 0.35, 0);
          }
          if (r.tch[i] === 119 && b > 0.12 && r.tch[i - 1] === 119) drawWindow(r, hits, i, bt, bb, age);
          if (matOn && b > MAT_B && r.tch[i] === r.tch[i - 1]) drawMat(r, hits, i, bt, bb);
        } else {
          wallSeg(r, xc - cw / 2, xc, i, i, r.btop[i], r.bbot[i], age, h.dist);
        }
        if (endRun) wallSeg(r, xc, xc + cw / 2, i, i, r.btop[i], r.bbot[i], age, h.dist);
      }
      if (i === 0 || conn) continue;
      const p = hits[i - 1];
      if (!h.hit && !p.hit) continue;
      let col = i;
      if (!h.hit || (p.hit && p.dist < h.dist)) col = i - 1;
      const bc = r.bcol[col];
      if (bc <= 0.01) continue;
      vert(r, i * cw + J(r, i, 1) * A * 0.6, r.ytopD[col], r.ybotD[col], r.btop[col], r.bbot[col], r.acol[col], hits[col].dist, 1, 0);
    }
    doorMode = 0;
    const trail = r.quality >= 3 ? MAX_TRAIL : r.quality === 2 ? 2 : 0;
    if (trail > 0) drawWallArcs(r, hits, sonar, t, trail);
    flushBuckets(r, ctx, r.quality >= 3);
  }

  const pick = { idx: -1, b: 0 };
  /** Find the pulse lighting (px,py) most strongly; sets pick.idx / pick.b. */
  function pickPulse(sonar, px, py, t) {
    const ps = sonar.pulses;
    const fade = sonar.fade;
    const Sonar = VCS.Sonar;
    let best = 0;
    let bi = -1;
    for (let k = 0; k < ps.length; k++) {
      const p = ps[k];
      const dx = px - p.x;
      const dy = py - p.y;
      const d = Math.sqrt(dx * dx + dy * dy);
      if (d > p.range) continue;
      const age = t - (p.t0 + d / p.speed);
      const pf = typeof p.fade === 'number' && p.fade > 0 ? p.fade : fade;
      if (age < 0 || age >= pf) continue;
      let b = 1 - age / pf;
      b = b * b * (1 - 0.5 * d / p.range) * (typeof p.strength === 'number' ? p.strength : 1);
      if (b <= best) continue;
      if (!Sonar.visibleFrom(p, px, py)) continue;
      best = b;
      bi = k;
    }
    pick.idx = bi;
    pick.b = best;
  }

  const proxy = { x: 0, y: 0, z: 0.5, t0: 0, speed: RIPPLE_V, vis: null };
  const arcOut = new Float32Array(2 * MAX_TRAIL);

  /** Local fallback with the same maths as Sonar.wallArc. */
  function localWallArc(pulse, t, hitX, hitY, trail, out) {
    const dx = hitX - pulse.x;
    const dy = hitY - pulse.y;
    const dh2 = dx * dx + dy * dy;
    const ring = (t - pulse.t0) * pulse.speed;
    let count = 0;
    for (let k = 0; k < trail; k++) {
      const R = ring - k * 0.35;
      if (R > 0 && R * R > dh2) {
        const dz = Math.sqrt(R * R - dh2);
        const zc = typeof pulse.z === 'number' ? pulse.z : 0.5;
        out[2 * k] = Math.max(0, zc - dz);
        out[2 * k + 1] = Math.min(1, zc + dz);
        count++;
      } else { out[2 * k] = NaN; out[2 * k + 1] = NaN; }
    }
    return count;
  }

  /**
   * Water ripples on wall faces: concentric rings spreading over the face from the point nearest the
   * sound, drawn as contour lines (Sonar.wallArc on a proxy pulse sitting on the wall).
   */
  function drawWallArcs(r, hits, sonar, t, trail) {
    const Sonar = VCS.Sonar;
    const arcFn = typeof Sonar.wallArc === 'function' ? Sonar.wallArc : localWallArc;
    const pulses = sonar.pulses;
    if (!pulses || !pulses.length) return;
    const n = r.cols;
    const cw = r.colW;
    const lo = r.arcLo;
    const hi = r.arcHi;
    const lp = r.arcP;
    for (let k = 0; k < MAX_TRAIL; k++) { lo[k] = NaN; hi[k] = NaN; lp[k] = -1; }
    for (let i = 0; i < n; i++) {
      const h = hits[i];
      const bb = r.bcol[i];
      const conn = i > 0 && connected(hits, i);
      if (!conn) for (let k = 0; k < MAX_TRAIL; k++) { lo[k] = NaN; hi[k] = NaN; }
      if (!h.hit || bb < 0.04 || r.dcol[i]) { for (let k = 0; k < MAX_TRAIL; k++) { lo[k] = NaN; hi[k] = NaN; } continue; }
      pickPulse(sonar, h.hitX, h.hitY, t);
      if (pick.idx < 0) { for (let k = 0; k < MAX_TRAIL; k++) { lo[k] = NaN; hi[k] = NaN; } continue; }
      const pu = pulses[pick.idx];
      let D;
      if (h.side === 0) { proxy.x = h.hitX; proxy.y = pu.y; D = Math.abs(h.hitX - pu.x); }
      else { proxy.x = pu.x; proxy.y = h.hitY; D = Math.abs(h.hitY - pu.y); }
      proxy.t0 = pu.t0 + D / pu.speed;
      proxy.z = typeof pu.z === 'number' ? pu.z : 0.5;
      if (t <= proxy.t0) { for (let k = 0; k < MAX_TRAIL; k++) { lo[k] = NaN; hi[k] = NaN; } continue; }
      // Fewer rings on near walls; head-on walls get fainter arcs than grazing ones.
      const tk = h.dist < 3 && trail > 2 ? 2 : trail;
      for (let k = tk; k < trail; k++) { lo[k] = NaN; hi[k] = NaN; lp[k] = -1; }
      const cinc = Math.abs(h.side === 0 ? Math.cos(h.rayAngle) : Math.sin(h.rayAngle));
      const incK = Math.max(0.25, 1 - (cinc === cinc ? cinc : 0));
      arcFn(proxy, t, h.hitX, h.hitY, tk, arcOut);
      const xc = (i + 0.5) * cw;
      const yt = r.ytopD[i];
      const yh = r.ybotD[i] - yt;
      const bounce = pu.gen > 0;
      for (let k = 0; k < tk; k++) {
        let zl = arcOut[2 * k];
        let zh = arcOut[2 * k + 1];
        if (!(zl > 0.002 && zl < 0.998)) zl = NaN;
        if (!(zh > 0.002 && zh < 0.998)) zh = NaN;
        const yl = zl === zl ? yt + (1 - zl) * yh : NaN;
        const yhi = zh === zh ? yt + (1 - zh) * yh : NaN;
        if (conn && lp[k] === pick.idx) {
          const a = Math.min(1, lineAlpha(bb, h.dist) * 0.9 * incK * (1 - k / tk) * (bounce ? 0.8 : 1));
          if (a > 0.03) {
            if (yl === yl && lo[k] === lo[k]) {
              const pth = pathForC(bounce ? 7 : 6, a, bounce ? 2 : (h.dist < 1.5 ? 1 : 0));
              pth.moveTo(xc - cw, lo[k]);
              pth.lineTo(xc, yl);
            }
            if (yhi === yhi && hi[k] === hi[k] && zh !== zl) {
              const pth = pathForC(bounce ? 7 : 6, a, bounce ? 2 : (h.dist < 1.5 ? 1 : 0));
              pth.moveTo(xc - cw, hi[k]);
              pth.lineTo(xc, yhi);
            }
          }
        }
        lo[k] = yl;
        hi[k] = yhi;
        lp[k] = pick.idx;
      }
    }
  }

  /** Draw each pulse ring as a wavy dotted arc on the floor and a fainter one on the ceiling. */
  function drawRipple(r, sonar, t, player, tanHalf) {
    const pulses = sonar.pulses;
    if (!pulses || !pulses.length) return;
    const Sonar = VCS.Sonar;
    const Ripple = VCS.Ripple;
    const ctx = r.octx;
    const halfW = r.ow / 2;
    const focal = halfW / tanHalf;
    const ca = Math.cos(player.angle);
    const sa = Math.sin(player.angle);
    const horizon = r.horizon;
    const half = r.oh / 2;
    const dot = 2.2 * r.wscale;
    const hd = dot / 2;
    const boil = r.boilOn;
    for (let k = 0; k < pulses.length; k++) {
      const pu = pulses[k];
      // Footsteps are drawn as floor ripples (drawFootRings), never as a body-high ring.
      if (pu.kind === 'step' || pu.kind === 'personStep') continue;
      const R = Sonar.ringRadius(pu, t);
      if (R < 0.2 || R > pu.range) continue;
      const str = typeof pu.strength === 'number' ? pu.strength : 1;
      const bounce = pu.gen > 0;
      if (pu.gen > 1 && r.quality < 3) continue;
      let alpha = 0.85 * (1 - R / pu.range) * Math.min(1, str * 1.3);
      let dotk = bounce ? 0.7 : 1;
      if (pu.weak > 0) {
        // Weak (low blood): the ring flickers and its dots shrink.
        const wk0 = pu.weak > 1 ? 1 : pu.weak;
        // Slow (<= 2.5 Hz), shallow wobble; reduced motion gets a static dim instead.
        alpha *= r.reduced ? 0.7 : 1 - 0.3 * wk0 * (0.5 + 0.5 * Math.sin(t * 15 + k));
        dotk *= 1 - 0.35 * wk0;
      }
      if (alpha <= 0.04) continue;
      const samples = bounce ? RING_SAMPLES >> 1 : RING_SAMPLES;
      const wk = 5 + (k % 3);
      const wphase = t * 1.4 + k;
      const ceilOk = !(typeof pu.z === 'number' && pu.z < 0.3);
      ctx.fillStyle = bounce ? COL_BOUNCE : '#e8f2ff';
      for (let pass = 0; pass < (r.quality >= 2 && !bounce && ceilOk ? 2 : 1); pass++) {
        ctx.globalAlpha = pass === 0 ? alpha : alpha * 0.4;
        ctx.beginPath();
        let any = false;
        for (let s = 0; s < samples; s++) {
          const th = (s / samples) * TWO_PI;
          const Rw = Ripple.wavyRadius(R, th, wphase, wk, 0.04);
          const wx = pu.x + Math.cos(th) * Rw;
          const wy = pu.y + Math.sin(th) * Rw;
          const dx = wx - player.x;
          const dy = wy - player.y;
          const fwd = dx * ca + dy * sa;
          if (fwd <= 0.15) continue;
          const right = -dx * sa + dy * ca;
          const sx = halfW + (right / fwd) * focal;
          if (sx < 0 || sx >= r.ow) continue;
          const col = Math.min(r.cols - 1, Math.floor(sx / r.colW));
          if (fwd > r.zbuf[col] + 0.05) continue;
          if (!visibleFrom(pu, wx, wy)) continue;
          const off = half / fwd;
          const y = (pass === 0 ? horizon + off : horizon - off) + (boil ? J(r, s + k * 17, 1) * 0.5 * r.wscale : 0);
          if (y < 0 || y >= r.oh) continue;
          const xj = boil ? J(r, s + k * 17, 0) * 0.5 * r.wscale : 0;
          ctx.rect(sx + xj - hd * dotk, y - hd * dotk, dot * dotk, dot * dotk);
          any = true;
        }
        if (any) ctx.fill();
      }
    }
    ctx.globalAlpha = 1;
  }

  const FRONT_SEG = 40;
  const FRONT_DOTS = 40;
  /** Seeded 0..1 value from two integers (deterministic stipple, no allocation). */
  function hash01(a, b) {
    let h = (Math.imul(a | 0, 374761393) + Math.imul(b | 0, 668265263)) | 0;
    h = Math.imul(h ^ (h >>> 13), 1274126177);
    return ((h ^ (h >>> 16)) >>> 0) / 4294967296;
  }

  /**
   * Floor depth cue: each primary pulse's wavefront over open floor as a thin perspective-projected ellipse
   * arc, with a few seeded stipple dots trailing behind it. Cheap (one stroke + one fill per pulse).
   */
  function drawFloorFront(r, sonar, t, player, tanHalf) {
    const pulses = sonar.pulses;
    if (!pulses || !pulses.length || r.quality < 2) return;
    const Sonar = VCS.Sonar;
    const ctx = r.octx;
    const halfW = r.ow / 2;
    const focal = halfW / tanHalf;
    const ca = Math.cos(player.angle);
    const sa = Math.sin(player.angle);
    const horizon = r.horizon;
    const half = r.oh / 2;
    ctx.lineJoin = 'round';
    ctx.lineCap = 'round';
    ctx.strokeStyle = '#e8f2ff';
    ctx.fillStyle = '#e8f2ff';
    ctx.lineWidth = 1.5;
    for (let k = 0; k < pulses.length; k++) {
      const pu = pulses[k];
      if (pu.gen > 0 || pu.kind === 'step' || pu.kind === 'personStep') continue;
      if (typeof pu.z === 'number' && pu.z > 0.7) continue;
      const R = Sonar.ringRadius(pu, t);
      if (R < 0.3 || R > pu.range) continue;
      const fade = typeof pu.fade === 'number' && pu.fade > 0 ? pu.fade : sonar.fade;
      const age = t - pu.t0;
      const str = typeof pu.strength === 'number' ? pu.strength : 1;
      let a = 0.5 * (1 - R / pu.range) * Math.min(1, str * 1.3) * (fade > 0 ? Math.max(0, 1 - age / (fade * 2)) : 1);
      if (pu.weak > 0) a *= r.reduced ? 0.7 : 1 - 0.3 * Math.min(1, pu.weak) * (0.5 + 0.5 * Math.sin(t * 15 + k));
      if (a < 0.04) continue;
      ctx.globalAlpha = a;
      ctx.beginPath();
      let pen = false;
      for (let s = 0; s <= FRONT_SEG; s++) {
        const th = (s / FRONT_SEG) * TWO_PI;
        const wx = pu.x + Math.cos(th) * R;
        const wy = pu.y + Math.sin(th) * R;
        const dx = wx - player.x;
        const dy = wy - player.y;
        const fwd = dx * ca + dy * sa;
        let ok = fwd > 0.2;
        let sx = 0;
        let y = 0;
        if (ok) {
          sx = halfW + ((-dx * sa + dy * ca) / fwd) * focal;
          y = horizon + half / fwd;
          if (sx < -20 || sx > r.ow + 20 || y > r.oh * 4) ok = false;
          else {
            const col = Math.max(0, Math.min(r.cols - 1, Math.floor(sx / r.colW)));
            if (fwd > r.zbuf[col] + 0.05 || !visibleFrom(pu, wx, wy)) ok = false;
          }
        }
        if (!ok) { pen = false; continue; }
        if (!pen) { ctx.moveTo(sx, y); pen = true; } else ctx.lineTo(sx, y);
      }
      ctx.stroke();
      // Stipple behind the front: seeded per pulse so the dots hold still as the ring expands.
      const seed = Math.round(pu.t0 * 1000) + k * 7919;
      const nd = r.quality >= 3 ? FRONT_DOTS : FRONT_DOTS >> 1;
      ctx.globalAlpha = a * 0.7;
      ctx.beginPath();
      let any = false;
      for (let d = 0; d < nd; d++) {
        const th = hash01(seed, d * 2) * TWO_PI;
        const back = 0.06 + 0.5 * hash01(seed, d * 2 + 1);
        const Rd = R * (1 - back);
        const wx = pu.x + Math.cos(th) * Rd;
        const wy = pu.y + Math.sin(th) * Rd;
        const dx = wx - player.x;
        const dy = wy - player.y;
        const fwd = dx * ca + dy * sa;
        if (fwd <= 0.25) continue;
        const sx = halfW + ((-dx * sa + dy * ca) / fwd) * focal;
        const y = horizon + half / fwd;
        if (sx < 0 || sx >= r.ow || y >= r.oh) continue;
        const col = Math.min(r.cols - 1, Math.floor(sx / r.colW));
        if (fwd > r.zbuf[col] + 0.05 || !visibleFrom(pu, wx, wy)) continue;
        ctx.rect(sx - 0.5, y - 0.5, 1, 1);
        any = true;
      }
      if (any) ctx.fill();
    }
    ctx.globalAlpha = 1;
  }

  const FOOT_SEG = 44;
  /**
   * Footstep ripples on the floor: 2-3 wobbly concentric rings around each step's origin, drawn with true
   * perspective projection so they read as ellipses. The player's own steps sit at the bottom of the view.
   */
  function drawFootRings(r, sonar, t, player, tanHalf) {
    const pulses = sonar.pulses;
    if (!pulses || !pulses.length || r.quality < 1) return;
    const Ripple = VCS.Ripple;
    const ctx = r.octx;
    const halfW = r.ow / 2;
    const focal = halfW / tanHalf;
    const ca = Math.cos(player.angle);
    const sa = Math.sin(player.angle);
    const horizon = r.horizon;
    const half = r.oh / 2;
    const boil = r.boilOn;
    const nr = r.quality >= 2 ? 3 : 2;
    ctx.lineJoin = 'round';
    ctx.lineCap = 'round';
    for (let k = 0; k < pulses.length; k++) {
      const pu = pulses[k];
      if (pu.kind !== 'step' && pu.kind !== 'personStep') continue;
      const age = t - pu.t0;
      const fade = typeof pu.fade === 'number' && pu.fade > 0 ? pu.fade : sonar.fade;
      if (age < 0 || age >= fade) continue;
      const str = typeof pu.strength === 'number' ? pu.strength : 0.3;
      const own = pu.kind === 'personStep';
      const nrk = own ? Math.min(nr, 2) : nr;
      ctx.strokeStyle = own ? COL_RING_PERSON : '#e8f2ff';
      for (let m = 0; m < nrk; m++) {
        const R = Ripple.footRing(age, fade, pu.range * (1.8), m);
        if (R < 0) continue;
        const a = Math.min(1, Ripple.footRingAlpha(age, fade, m) * Math.min(1, str * 4) * (own ? 0.7 : 1.2));
        if (a < 0.03) continue;
        ctx.globalAlpha = a;
        ctx.lineWidth = (m === 0 ? 1.7 : 1.3) * r.wscale;
        ctx.beginPath();
        let pen = false;
        const ph = k * 1.7 + m * 2.1;
        for (let s = 0; s <= FOOT_SEG; s++) {
          const th = (s / FOOT_SEG) * TWO_PI;
          const Rw = Ripple.wavyRadius(R, th, t * 3 + ph, 5, 0.06);
          const wx = pu.x + Math.cos(th) * Rw;
          const wy = pu.y + Math.sin(th) * Rw;
          const dx = wx - player.x;
          const dy = wy - player.y;
          const fwd = dx * ca + dy * sa;
          let ok = fwd > 0.2;
          let sx = 0;
          let y = 0;
          if (ok) {
            const right = -dx * sa + dy * ca;
            sx = halfW + (right / fwd) * focal;
            y = horizon + half / fwd;
            if (sx < -20 || sx > r.ow + 20 || y > r.oh * 4) ok = false;
            else {
              const col = Math.max(0, Math.min(r.cols - 1, Math.floor(sx / r.colW)));
              if (fwd > r.zbuf[col] + 0.05) ok = false;
            }
          }
          if (!ok) { pen = false; continue; }
          if (boil) {
            sx += J(r, s + m * 32 + k * 5, 0) * 0.35 * r.wscale;
            y += J(r, s + m * 32 + k * 5, 1) * 0.35 * r.wscale;
          }
          if (!pen) { ctx.moveTo(sx, y); pen = true; } else ctx.lineTo(sx, y);
        }
        ctx.stroke();
      }
    }
    ctx.globalAlpha = 1;
  }

  /** Draw secondary echo rings (from struck people and markers) as wavy dotted floor circles. */
  function drawRings(r, ripple, t, player, tanHalf) {
    const rings = ripple && ripple.rings;
    if (!rings || !rings.length || r.quality < 2) { r.ringsDrawn = 0; return; }
    const Ripple = VCS.Ripple;
    const ctx = r.octx;
    const halfW = r.ow / 2;
    const focal = halfW / tanHalf;
    const ca = Math.cos(player.angle);
    const sa = Math.sin(player.angle);
    const horizon = r.horizon;
    const half = r.oh / 2;
    const dot = 2.0 * r.wscale;
    const hd = dot / 2;
    const boil = r.boilOn;
    let drawn = 0;
    for (let k = 0; k < rings.length; k++) {
      const rg = rings[k];
      const a = Ripple.alpha(rg, t);
      if (a <= 0.01) continue;
      const R = Ripple.radius(rg, t);
      ctx.fillStyle = rg.kind === 'person' ? COL_RING_PERSON : rg.kind === 'marker' ? COL_RING_MARKER : COL_RING_OTHER;
      ctx.globalAlpha = rg.kind === 'person' ? a * 0.8 : a;
      ctx.beginPath();
      let any = false;
      for (let s = 0; s < SEC_SAMPLES; s++) {
        const th = (s / SEC_SAMPLES) * TWO_PI;
        const Rw = Ripple.wavyRadius(R, th, t * 1.6 + k, 6, 0.05);
        const wx = rg.x + Math.cos(th) * Rw;
        const wy = rg.y + Math.sin(th) * Rw;
        const dx = wx - player.x;
        const dy = wy - player.y;
        const fwd = dx * ca + dy * sa;
        if (fwd <= 0.15) continue;
        const right = -dx * sa + dy * ca;
        const sx = halfW + (right / fwd) * focal;
        if (sx < 0 || sx >= r.ow) continue;
        const col = Math.min(r.cols - 1, Math.floor(sx / r.colW));
        if (fwd > r.zbuf[col] + 0.05) continue;
        const y = horizon + half / fwd + (boil ? J(r, s + k * 11, 1) * 0.5 * r.wscale : 0);
        if (y < 0 || y >= r.oh) continue;
        ctx.rect(sx + (boil ? J(r, s + k * 11, 0) * 0.5 * r.wscale : 0) - hd, y - hd, dot, dot);
        any = true;
      }
      if (any) { ctx.fill(); drawn++; }
    }
    ctx.globalAlpha = 1;
    r.ringsDrawn = drawn;
  }

  /** Project a world point to camera space; returns false when behind. */
  const proj = { fwd: 0, sx: 0 };
  function project(player, x, y, halfW, tanHalf) {
    const dx = x - player.x;
    const dy = y - player.y;
    const ca = Math.cos(player.angle);
    const sa = Math.sin(player.angle);
    const fwd = dx * ca + dy * sa;
    const right = -dx * sa + dy * ca;
    if (fwd <= 0.1) return false;
    proj.fwd = fwd;
    proj.sx = halfW + (right / fwd) * (halfW / tanHalf);
    return true;
  }

  /** Run fn once per run of columns spanning px x0..x1 not occluded by closer walls. */
  function clippedDraw(r, x0, x1, depth, fn) {
    const a = Math.max(0, Math.floor(x0 / r.colW));
    const b = Math.min(r.cols - 1, Math.floor(x1 / r.colW));
    const ctx = r.octx;
    let runStart = -1;
    for (let c = a; c <= b + 1; c++) {
      const vis = c <= b && r.zbuf[c] > depth;
      if (vis && runStart < 0) runStart = c;
      if (!vis && runStart >= 0) {
        if (runStart === a && c - 1 === b) {
          fn(ctx);
        } else {
          ctx.save();
          ctx.beginPath();
          ctx.rect(runStart * r.colW, 0, (c - runStart) * r.colW, r.oh);
          ctx.clip();
          fn(ctx);
          ctx.restore();
        }
        runStart = -1;
      }
    }
  }

  /** Sprite colour: base tinted pale at high brightness, cool blue at low. */
  function spriteStyle(base, b) {
    let c = base;
    let k = 0;
    let target = C_HI;
    if (b > 0.5) { k = 0.5 * Math.min(1, (b - 0.5) / 0.5); target = [255, 255, 255]; }
    else { k = 0.45 * (1 - b / 0.5); target = C_LOW; }
    return 'rgb(' + Math.round(lerp(c[0], target[0], k)) + ',' + Math.round(lerp(c[1], target[1], k)) +
      ',' + Math.round(lerp(c[2], target[2], k)) + ')';
  }

  /** Draw horizontal ripple band lines (white) between xl..xr at normalised heights for a marker. */
  function bandLines(ctx, xl, xr, floorY, hpx, age, alpha) {
    const Ripple = VCS.Ripple;
    const f = Ripple.bandFront(age);
    if (f < 0) return;
    ctx.strokeStyle = '#ffffff';
    ctx.lineWidth = 1;
    for (let m = 0; m < 3; m++) {
      const u = f - m * 0.16;
      if (u < 0 || u > 1) continue;
      ctx.globalAlpha = Math.min(1, alpha * (1 - age / Ripple.BAND_DUR) * (1 - m * 0.3) * 1.4);
      const y = floorY - u * hpx;
      ctx.beginPath();
      ctx.moveTo(xl, y);
      ctx.quadraticCurveTo((xl + xr) / 2, y + hpx * 0.04, xr, y);
      ctx.stroke();
    }
  }

  /** Draw one outlined marker sprite (wobbly coffin, bouncy diamond, crooked doorway); true when drawn. */
  function drawSprite(r, world, player, sonar, t, kind, spot, tanHalf) {
    const halfW = r.ow / 2;
    const Ripple = VCS.Ripple;
    let open = null;
    if (kind === 'doors' && typeof world.isDoorOpen === 'function') {
      open = world.isDoorOpen(spot.x, spot.y);
      if (!open) return false; // closed doors are solid and drawn as walls
    }
    if (!project(player, spot.x, spot.y, halfW, tanHalf)) return false;
    const depth = proj.fwd;
    const cx = proj.sx;
    const zc = kind === 'safe' ? 0.3 : kind === 'doors' ? 0.45 : 0.18;
    const b = litAt3(sonar, spot.x, spot.y, zc, t);
    if (b <= 0.01) return false;
    const age = samp3[1];
    const horizon = r.horizon;
    const vs = r.oh / depth;
    const hs = halfW / tanHalf / depth;
    const floorY = horizon + 0.5 * vs;
    const flash = age >= 0 && age < FLASH_AGE;
    const rip = age >= 0 && age < Ripple.BAND_DUR && r.quality >= 1;
    let alpha = lineAlpha(b, depth) * 1.2;
    let lw = (depth < 1.5 ? 1.5 : 1) * r.wscale;
    const idb = ((spot.x * 7 + spot.y * 13) | 0) * 24;
    const A = 0.7 * r.wscale;
    const jx = function (k) { return J(r, idb + k, 0) * A; };
    const jy = function (k) { return J(r, idb + k, 1) * A; };
    let base;
    let c0;
    let c1;
    let shape;
    if (kind === 'safe') {
      // Bouncy diamond: hops with squash on landing, stretch at the top; shadow on the floor.
      base = COL_SAFE;
      const hop = Math.abs(Math.sin(t * 3.2 + spot.x));
      const land = (1 - hop) * (1 - hop) * (1 - hop);
      const sy = 1.08 - 0.3 * land;
      const sx = 1 / sy;
      const hov = 0.2 + 0.12 * hop;
      const dh = 0.17 * vs * sy;
      const dw = 0.12 * hs * sx;
      const my = floorY - hov * vs;
      const grow = rip ? 1 + 0.9 * (age / Ripple.BAND_DUR) : 1;
      c0 = cx - dw * 2 - 10;
      c1 = cx + dw * 2 + 10;
      shape = function (ctx) {
        ctx.beginPath();
        ctx.moveTo(cx + jx(0), my - dh + jy(0));
        ctx.lineTo(cx + dw + jx(1), my + jy(1));
        ctx.lineTo(cx + jx(2), my + dh + jy(2));
        ctx.lineTo(cx - dw + jx(3), my + jy(3));
        ctx.closePath();
        // facet tick
        ctx.moveTo(cx - dw * 0.35, my - dh * 0.25);
        ctx.lineTo(cx - dw * 0.1, my - dh * 0.55);
        ctx.stroke();
        // shadow ellipse on the floor shrinks as it hops up
        ctx.globalAlpha = Math.min(1, alpha * 0.6);
        ctx.beginPath();
        const sw = dw * (1.1 - 0.4 * hop);
        ctx.ellipse(cx, floorY, sw, Math.max(1, sw * 0.22), 0, 0, TWO_PI);
        ctx.stroke();
        ctx.globalAlpha = Math.min(1, alpha);
        if (rip && grow > 1.02) {
          ctx.globalAlpha = Math.min(1, alpha * (1 - age / Ripple.BAND_DUR));
          ctx.beginPath();
          ctx.moveTo(cx, my - dh * grow);
          ctx.lineTo(cx + dw * grow, my);
          ctx.lineTo(cx, my + dh * grow);
          ctx.lineTo(cx - dw * grow, my);
          ctx.closePath();
          ctx.stroke();
        }
      };
    } else {
      const isDoor = kind === 'doors';
      base = isDoor ? COL_DOOR_OPEN : COL_CRYPT;
      const hN = isDoor ? 0.92 : 0.38;
      const hpx = hN * vs;
      let xl;
      let xr;
      if (isDoor) {
        // Open doorway: jambs sit on the cell edges across the wall line.
        const cxi = Math.floor(spot.x);
        const cyi = Math.floor(spot.y);
        const solid = function (x, y) { return world.isSolid(x, y); };
        let ax;
        let ay;
        let bx;
        let by;
        if (solid(cxi - 0.5, cyi + 0.5) && solid(cxi + 1.5, cyi + 0.5)) {
          ax = cxi; ay = cyi + 0.5; bx = cxi + 1; by = cyi + 0.5;
        } else {
          ax = cxi + 0.5; ay = cyi; bx = cxi + 0.5; by = cyi + 1;
        }
        if (!project(player, ax, ay, halfW, tanHalf)) return false;
        xl = proj.sx;
        if (!project(player, bx, by, halfW, tanHalf)) return false;
        xr = proj.sx;
        if (xl > xr) { const tmp = xl; xl = xr; xr = tmp; }
      } else {
        const w = 0.85 * hs;
        xl = cx - w / 2;
        xr = cx + w / 2;
      }
      c0 = xl - 10;
      c1 = xr + 10;
      const amp = rip ? 0.02 * hs : 0;
      const wid = xr - xl;
      shape = function (ctx) {
        ctx.beginPath();
        if (isDoor) {
          // Crooked frame: jambs lean the same way, lintel sags in the middle.
          const lean = wid * 0.07;
          const sag = hpx * 0.035;
          for (let side = 0; side < 2; side++) {
            const x = side === 0 ? xl : xr;
            const lx = side === 0 ? lean : lean * 0.6;
            for (let k = 0; k <= 6; k++) {
              const u = k / 6;
              const px = x + lx * u + (rip ? Ripple.wave(u, age) * amp * (side ? -1 : 1) : 0) + jx(k + side * 8);
              const py = floorY - u * hpx + jy(k + side * 8);
              if (k === 0) ctx.moveTo(px, py); else ctx.lineTo(px, py);
            }
            if (side === 0) ctx.quadraticCurveTo((xl + xr) / 2 + lean * 0.8, floorY - hpx + sag, xr + lean * 0.6, floorY - hpx);
          }
          ctx.stroke();
          // Inset inner jambs (the doorway reads as a gap framed twice) and the door leaf swung open.
          ctx.beginPath();
          const ins = wid * 0.09;
          ctx.moveTo(xl + ins + lean * 0.1, floorY);
          ctx.lineTo(xl + ins + lean * 0.9, floorY - hpx * 0.9);
          ctx.moveTo(xr - ins + lean * 0.05, floorY);
          ctx.lineTo(xr - ins + lean * 0.55, floorY - hpx * 0.9);
          ctx.stroke();
          ctx.beginPath();
          const lw2 = wid * 0.2;
          ctx.moveTo(xl + ins, floorY);
          ctx.lineTo(xl + ins + lw2, floorY - hpx * 0.04);
          ctx.lineTo(xl + ins + lw2, floorY - hpx * 0.82);
          ctx.lineTo(xl + ins + lean * 0.9, floorY - hpx * 0.9);
          ctx.moveTo(xl + ins + lw2 * 0.5, floorY - hpx * 0.02);
          ctx.lineTo(xl + ins + lw2 * 0.5, floorY - hpx * 0.86);
          if (typeof world.isLinkDoor === 'function' && world.isLinkDoor(spot.x, spot.y)) {
            const kx = (xl + xr) / 2 + lean * 0.8;
            const ky = floorY - hpx + sag;
            ctx.moveTo(kx - wid * 0.06, ky);
            ctx.lineTo(kx - wid * 0.06, ky - hpx * 0.07);
            ctx.lineTo(kx + wid * 0.06, ky - hpx * 0.07);
            ctx.lineTo(kx + wid * 0.06, ky);
          }
          ctx.stroke();
        } else {
          // Wobbly coffin: six-sided lid shape, wavering outline, cross on the lid.
          const wob = function (k) { return Math.sin(t * 2.2 + k * 1.3 + spot.x) * 0.012 * hs; };
          const px = [0.2, 0.8, 1, 0.8, 0.2, 0];
          const py = [0, 0, 0.55, 1, 1, 0.55];
          for (let k = 0; k < 6; k++) {
            const x = xl + px[k] * wid + wob(k) + jx(k);
            const y = floorY - py[k] * hpx + Math.cos(t * 2.6 + k) * hpx * 0.012 + jy(k);
            if (k === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y);
          }
          ctx.closePath();
          const mx = (xl + xr) / 2;
          const my2 = floorY - hpx * 0.55;
          ctx.moveTo(mx, my2 + hpx * 0.22);
          ctx.lineTo(mx, my2 - hpx * 0.22);
          ctx.moveTo(mx - wid * 0.1, my2 + hpx * 0.1);
          ctx.lineTo(mx + wid * 0.1, my2 + hpx * 0.1);
          ctx.stroke();
        }
        if (rip && r.quality >= 2) bandLines(ctx, xl, xr, floorY, hpx, age, alpha);
      };
    }
    const ctx = r.octx;
    if (flash) {
      const f = 1 - age / FLASH_AGE;
      alpha = Math.min(1, alpha + 0.5 * f);
      lw += 0.5 * f * r.wscale;
      ctx.strokeStyle = '#ffffff';
    } else {
      ctx.strokeStyle = spriteStyle(base, b);
    }
    ctx.lineWidth = lw;
    ctx.lineJoin = 'round';
    ctx.lineCap = 'round';
    ctx.globalAlpha = Math.min(1, alpha);
    clippedDraw(r, c0 - lw, c1 + lw, depth, function (c) {
      shape(c);
      c.globalAlpha = Math.min(1, alpha);
    });
    ctx.globalAlpha = 1;
    return true;
  }

  // ---- Villagers: quirky hand-drawn figures lit only by the passing wavefront ----
  // Body frame: f forward (the way the person faces), s to their left, u up (wall units, 0 = feet).
  // Pose slots (screen px after projection): 0 head, 1 neck, 2/3 shoulders, 4/5 hips, 6/7 hands, 8/9 feet,
  // 10/11 elbows, 12/13 knees, 14 torso centre, 15 scarf tip, 16 scarf control, 17 hat tip, 18 hat control,
  // 19 prop anchor, 20 prop tip, 21/22 coat hem, 23 head top.
  const FIG_H = 0.78;
  const FIG_ZTOP = 1.7;
  const DEFAULT_LOOK = { height: 1, build: 1, stride: 1, acc: 'scarf', body: 'bean', head: 'round', hat: 'none', hair: 'none', beard: false, nose: 1, coat: false, prop: 'none' };
  /** Seconds for the revealing band to sweep a figure from feet to hat. */
  const SWEEP = 0.22;
  /** Band over-run so the hat is reached before the sweep ends. */
  const SWEEP_OVER = 1.3;
  /** Strip edges (z units, 0 feet .. 1 head top .. FIG_ZTOP hat) used to light a figure piecewise. */
  const STRIP_Z = [0, 0.25, 0.45, 0.65, 0.85, 1.05, FIG_ZTOP];
  const STRIP_A = new Float32Array(STRIP_Z.length - 1);
  const PX = new Float32Array(24);
  const PY = new Float32Array(24);
  const fig = { cx: 0, floorY: 0, hs: 0, vs: 0, sr: 0, cr: 0, sx: 1, sy: 1, age: -1, H: 1, fid: 0, A: 0, sway: 0 };

  /** Lateral ripple -1..1 at normalised height zn (0 feet .. 1 head) while the band sweeps past; 0 elsewhere. */
  function sweepWave(zn, age) {
    if (!(age >= 0)) return 0;
    const f = (age / SWEEP) * SWEEP_OVER;
    if (zn > f) return 0;
    const behind = f - zn;
    const k = 1 - age / (SWEEP + 0.25);
    return k <= 0 ? 0 : Math.sin(behind * 22) * Math.exp(-behind * 3) * k;
  }

  /** Project a body-frame point into pose slot k (applies squash/stretch, sway, ripple wave and line boil). */
  function put(r, k, f, s, u) {
    const wv = fig.age >= 0 ? sweepWave(u / (fig.H * 1.1), fig.age) * 0.02 : 0;
    const ff = f * fig.sx;
    const ss = s * fig.sx;
    PX[k] = fig.cx + (ff * fig.sr + ss * fig.cr + wv + fig.sway * u) * fig.hs + J(r, fig.fid + k, 0) * fig.A;
    PY[k] = fig.floorY - u * fig.sy * fig.vs + J(r, fig.fid + k, 1) * fig.A;
  }

  /** Rounded-square head outline (used for the 'square' head). */
  function squareHead(c, x, y, rx, ry, rot) {
    const cr = Math.cos(rot);
    const sr = Math.sin(rot);
    const P = function (px, py) { return [x + px * cr - py * sr, y + px * sr + py * cr]; };
    const k = 0.55;
    const a = P(-rx * k, -ry); const b = P(rx * k, -ry); const c2 = P(rx, -ry * k); const d = P(rx, ry * k);
    const e = P(rx * k, ry); const f = P(-rx * k, ry); const g = P(-rx, ry * k); const h = P(-rx, -ry * k);
    const tr = P(rx, -ry); const br = P(rx, ry); const bl = P(-rx, ry); const tl = P(-rx, -ry);
    c.moveTo(a[0], a[1]);
    c.lineTo(b[0], b[1]);
    c.quadraticCurveTo(tr[0], tr[1], c2[0], c2[1]);
    c.lineTo(d[0], d[1]);
    c.quadraticCurveTo(br[0], br[1], e[0], e[1]);
    c.lineTo(f[0], f[1]);
    c.quadraticCurveTo(bl[0], bl[1], g[0], g[1]);
    c.lineTo(h[0], h[1]);
    c.quadraticCurveTo(tl[0], tl[1], a[0], a[1]);
  }

  /**
   * Draw one villager echo e {x,y,angle,lookAngle,phase,phaseRate,look,mode,sit,wary,modeAge,zMin,zMax,personId}.
   * b = strength 0..1, age = seconds since the wavefront reached them (-1 = already lit, e.g. the feed lock).
   * Only the strips the band has swept over are drawn; each fades on its own afterglow. True when drawn.
   */
  function drawPerson(r, player, tanHalf, e, b, age, flashWhite, now, locked) {
    const halfW = r.ow / 2;
    if (!project(player, e.x, e.y, halfW, tanHalf)) return false;
    const depth = proj.fwd;
    const vs = r.oh / depth;
    const hs = halfW / tanHalf / depth;
    const cx0 = proj.sx;
    if (cx0 < -hs * 0.5 - 20 || cx0 > r.ow + hs * 0.5 + 20) return false;
    const Ripple = VCS.Ripple;
    const look = e.look || DEFAULT_LOOK;
    const lh = typeof look.height === 'number' ? look.height : 1;
    const bw = typeof look.build === 'number' ? look.build : 1;
    const anim = !r.reduced;
    const mode = locked ? 'grapple' : (typeof e.mode === 'string' ? e.mode : 'path');
    const pid = e.personId || 0;
    const viewAng = Math.atan2(e.y - player.y, e.x - player.x);
    const rel = e.angle - viewAng;
    // Gait phase keeps advancing while the echo glows, so a walker keeps walking as it fades.
    let ph = e.phase || 0;
    if (anim && e.phaseRate > 0 && age > 0 && (mode === 'path' || mode === 'flee')) ph += e.phaseRate * Math.min(age, 0.6);
    const canMove = mode === 'path' || mode === 'flee';
    const moving = canMove && ph > 0.02;
    const seated = !!e.sit && !moving && (mode === 'path' || mode === 'startle');
    const sph = Math.sin(ph);
    const cph = Math.cos(ph);
    const amp = (typeof look.stride === 'number' ? look.stride : 1) * (mode === 'flee' ? 1.35 : 1);
    const tN = anim ? now : 0;
    const fade = typeof e.fade === 'number' && e.fade > 0 ? e.fade : 3;
    const dur = glowDur(fade);
    const sweeping = age >= 0 && age < SWEEP + dur && !locked;
    // Squash and stretch: squashed when a foot plants (phase PI/2 + k PI), stretched mid-stride.
    let sq = moving ? 1 + 0.1 * Math.cos(2 * ph) : 1 + 0.02 * Math.sin(tN * 3.1 + pid * 2);
    fig.cx = cx0;
    fig.floorY = r.horizon + 0.5 * vs;
    fig.hs = hs;
    fig.vs = vs;
    fig.sr = Math.sin(rel);
    fig.cr = Math.cos(rel);
    fig.age = sweeping && r.quality >= 1 ? age : -1;
    fig.H = FIG_H * lh;
    fig.fid = (pid * 29 + 11) * 24;
    fig.A = 0.7 * r.wscale;
    fig.sway = 0;
    if (locked) {
      // Feeding lock: tension boil for the first 0.35 s, then the victim goes still as k rises.
      let bm = 1;
      if (anim) bm = r.lockAge < 0.35 ? 1.6 : 1 - smoothstep(0.2, 0.9, r.lockK);
      fig.A *= bm;
    }
    // ---- Pose by mode (body-frame numbers; u in wall units) ----
    let hipU = 0.33 * lh;
    let shU = 0.53 * lh;
    let headU = 0.69 * lh;
    let lean = 0;           // forward offset of the shoulders (f)
    let headF = 0;          // forward offset of the head (f)
    let headS = 0;          // sideways offset of the head (s), e.g. a lolling head
    let tilt = 0;           // head roll (screen radians)
    let bob = 0;
    const hipS = (look.body === 'pear' ? 0.055 : look.body === 'round' ? 0.06 : look.body === 'stick' ? 0.03 : 0.04) * bw;
    const shS = (look.body === 'round' ? 0.075 : look.body === 'stick' ? 0.05 : look.body === 'pear' ? 0.05 : 0.062) * bw;
    let footF = [0, 0]; let footS = [hipS * 1.15, -hipS * 1.15]; let footU = [0, 0];
    let kneeF = [0.012 * lh, 0.012 * lh]; let kneeS = [hipS * 1.25, -hipS * 1.25]; let kneeU = [0, 0];
    let handF = [0, 0]; let handS = [0, 0]; let handU = [0, 0];
    let elbF = [0, 0]; let elbS = [0, 0]; let elbU = [0, 0];
    const lagA = Math.sin(ph - 1.3);
    const prop = look.prop || (look.acc === 'cane' ? 'cane' : 'none');
    const holdR = prop !== 'none'; // the right hand (side 1) carries the prop
    let jump = 0;
    let stars = false;
    let eyesX = false;
    let handsOverHead = false;
    const modeAge = typeof e.modeAge === 'number' ? e.modeAge : 9;
    if (mode === 'grapple') {
      hipU = 0.3 * lh; shU = 0.5 * lh; headU = 0.6 * lh;
      lean = 0.02 * lh; headF = 0.03 * lh; headS = 0.05 * bw;
      tilt = 0.55 + 0.03 * Math.sin(tN * 0.8 + pid);
      kneeF = [0.06 * lh, 0.05 * lh]; kneeU = [0.16 * lh, 0.16 * lh];
      handF = [0.01 * lh, 0.0]; handS = [shS * 1.1, -shS * 1.1]; handU = [shU - 0.25 * lh, shU - 0.26 * lh];
      elbF = [0.0, 0.0]; elbS = [shS * 1.4, -shS * 1.4]; elbU = [shU - 0.12 * lh, shU - 0.12 * lh];
    } else if (mode === 'fed') {
      // Slumped on the floor, legs out, head hung.
      hipU = 0.07 * lh; shU = 0.3 * lh; headU = 0.4 * lh;
      lean = -0.03 * lh; headF = 0.05 * lh; headS = -0.03 * bw; tilt = -0.45;
      footF = [0.22 * lh, 0.19 * lh]; footU = [0.01 * lh, 0.0]; footS = [hipS * 1.4, -hipS * 1.1];
      kneeF = [0.1 * lh, 0.09 * lh]; kneeU = [0.07 * lh, 0.06 * lh]; kneeS = [hipS * 1.3, -hipS * 1.2];
      handF = [0.03 * lh, 0.02 * lh]; handS = [shS * 2.2, -shS * 2.1]; handU = [0.02 * lh, 0.02 * lh];
      elbF = [0.0, 0.0]; elbS = [shS * 1.9, -shS * 1.8]; elbU = [0.14 * lh, 0.14 * lh];
    } else if (mode === 'cower') {
      // Crouched, knees out, hands over the head; a slow 1.5 Hz tremble.
      const sh = anim ? Math.sin(tN * 9.4 + pid) * 0.006 * lh : 0;
      hipU = 0.17 * lh; shU = 0.35 * lh + sh; headU = 0.45 * lh + sh;
      lean = 0.05 * lh; headF = 0.03 * lh; tilt = 0.12;
      footS = [hipS * 1.9, -hipS * 1.9]; kneeS = [hipS * 2.3, -hipS * 2.3]; kneeF = [0.07 * lh, 0.07 * lh]; kneeU = [0.1 * lh, 0.1 * lh];
      handF = [0.03 * lh, 0.03 * lh]; handS = [0.03 * bw, -0.03 * bw]; handU = [headU + 0.08 * lh, headU + 0.07 * lh];
      elbF = [0.0, 0.0]; elbS = [shS * 1.9, -shS * 1.9]; elbU = [shU + 0.06 * lh, shU + 0.06 * lh];
      handsOverHead = true;
    } else if (mode === 'dazed') {
      // Wobbling on knocked knees, eyes crossed, little stars orbiting the head.
      fig.sway = anim ? Math.sin(tN * 2.1 + pid) * 0.05 : 0;
      tilt = anim ? Math.sin(tN * 1.7 + pid) * 0.3 : 0.2;
      hipU = 0.3 * lh; shU = 0.5 * lh; headU = 0.66 * lh;
      kneeS = [hipS * 0.4, -hipS * 0.4]; kneeF = [0.03 * lh, 0.03 * lh]; kneeU = [0.15 * lh, 0.15 * lh];
      handF = [0.0, 0.0]; handS = [shS * 1.9, -shS * 1.9]; handU = [shU - 0.22 * lh, shU - 0.2 * lh];
      elbS = [shS * 1.6, -shS * 1.6]; elbU = [shU - 0.1 * lh, shU - 0.1 * lh];
      stars = true; eyesX = true;
    } else if (mode === 'startle') {
      // A hop of surprise (first 0.22 s), then frozen with the arms up.
      const hopK = anim && modeAge < 0.22 ? Math.sin(Math.PI * modeAge / 0.22) : 0;
      jump = 0.09 * lh * hopK;
      sq = 1 + 0.12 * hopK;
      hipU = 0.33 * lh + jump; shU = 0.54 * lh + jump; headU = 0.71 * lh + jump;
      footU = [0.6 * jump, 0.6 * jump]; kneeU = [0, 0]; kneeF = [0.05 * lh * hopK + 0.012 * lh, 0.05 * lh * hopK + 0.012 * lh];
      handF = [0.02 * lh, 0.02 * lh]; handS = [shS * 2.4, -shS * 2.4]; handU = [shU + 0.12 * lh, shU + 0.11 * lh];
      elbS = [shS * 2.0, -shS * 2.0]; elbU = [shU - 0.02 * lh, shU - 0.02 * lh];
      tilt = -0.08;
    } else if (seated) {
      // On a bench: thighs forward, shins down, hands on the knees.
      hipU = 0.2 * lh; shU = 0.42 * lh; headU = 0.58 * lh;
      lean = 0.01 * lh;
      kneeF = [0.13 * lh, 0.13 * lh]; kneeU = [0.21 * lh, 0.21 * lh]; kneeS = [hipS * 2.4, -hipS * 2.4];
      footF = [0.15 * lh, 0.15 * lh]; footU = [0, 0]; footS = [hipS * 1.6, -hipS * 1.6];
      handF = [0.12 * lh, 0.12 * lh]; handS = [hipS * 1.3, -hipS * 1.3]; handU = [0.22 * lh, 0.22 * lh];
      elbF = [0.03 * lh, 0.03 * lh]; elbS = [shS * 1.5, -shS * 1.5]; elbU = [shU - 0.12 * lh, shU - 0.12 * lh];
      tilt = 0.05 * Math.sin(tN * 1.1 + pid);
      const nod = anim ? 0.004 * lh * Math.sin(tN * 2.2 + pid) : 0;
      headU += nod;
    } else if (moving) {
      const flee = mode === 'flee';
      bob = 0.022 * lh * (1 - Math.abs(sph)) * (flee ? 1.4 : 1);
      tilt = 0.5 * sph * 0.05;
      hipU = 0.33 * lh + bob; shU = 0.53 * lh + bob; headU = 0.69 * lh + bob;
      lean = flee ? 0.1 * lh : 0.02 * lh;
      headF = flee ? 0.07 * lh : 0.01 * lh;
      for (let side = 0; side < 2; side++) {
        const sg = side === 0 ? 1 : -1;
        const swing = sg * sph;
        const lift = 0.075 * lh * Math.max(0, sg * cph) * (flee ? 1.3 : 1);
        footF[side] = 0.17 * lh * amp * swing;
        footU[side] = lift;
        // A touch of sideways motion so the gait still reads head-on.
        footS[side] = sg * hipS * (1.15 + 2.2 * lift / lh);
        kneeS[side] = sg * hipS * (1.25 + 3 * lift / lh);
        kneeF[side] = footF[side] * 0.5 + (lift > 0 ? 0.07 * lh : 0.012 * lh);
        kneeU[side] = (hipU + lift) * 0.5;
        const aswing = -swing;
        const carry = side === 1 && holdR;
        if (flee) {
          // Arms pump low and behind.
          handF[side] = carry ? -0.02 * lh : -0.1 * lh + 0.08 * lh * aswing;
          handU[side] = shU - 0.17 * lh + 0.03 * lh * Math.abs(aswing);
          handS[side] = sg * (shS + 0.06);
          elbF[side] = handF[side] * 0.5 - 0.06 * lh;
          elbS[side] = sg * (shS + 0.08);
          elbU[side] = shU - 0.06 * lh;
        } else {
          handF[side] = carry ? 0.1 * lh : 0.15 * lh * amp * aswing;
          handU[side] = carry ? shU - 0.2 * lh : shU - 0.2 * lh + 0.015 * lh * Math.abs(aswing);
          handS[side] = sg * (shS + 0.065 + (carry ? 0 : 0.03 * Math.abs(aswing)));
          elbF[side] = handF[side] * 0.4 - 0.01;
          elbS[side] = sg * (shS + 0.075 + 0.015 * Math.abs(aswing));
          elbU[side] = (shU + handU[side]) * 0.5 + 0.015;
        }
      }
    } else {
      // Idle fidgets: weight shift, breathing, the odd head scratch; wary villagers clasp their hands.
      const wary = !!e.wary;
      const shift = anim ? Math.sin(tN * 0.9 + pid * 1.3) * 0.012 : 0;
      const breath = anim ? 0.004 * lh * Math.sin(tN * 2.4 + pid) : 0;
      fig.sway = shift;
      hipU = 0.33 * lh; shU = 0.53 * lh + breath; headU = 0.69 * lh + breath;
      tilt = anim ? 0.07 * Math.sin(tN * 1.3 + pid * 1.7) : 0;
      lean = wary ? 0.03 * lh : 0.0;
      headF = wary ? 0.03 * lh : 0;
      const scratch = anim && !wary && (pid % 3 === 1) && Math.sin(tN * 0.5 + pid) > 0.55;
      for (let side = 0; side < 2; side++) {
        const sg = side === 0 ? 1 : -1;
        const carry = side === 1 && holdR;
        if (wary && !carry) {
          handF[side] = 0.08 * lh; handS[side] = sg * 0.015 * bw; handU[side] = shU - 0.16 * lh;
          elbF[side] = 0.03 * lh; elbS[side] = sg * (shS + 0.05); elbU[side] = shU - 0.1 * lh;
        } else if (scratch && side === 0) {
          handF[side] = 0.03 * lh; handS[side] = sg * 0.06 * bw; handU[side] = headU + 0.08 * lh + (anim ? 0.01 * Math.sin(tN * 6) : 0);
          elbF[side] = 0.02 * lh; elbS[side] = sg * (shS + 0.12); elbU[side] = shU + 0.02 * lh;
        } else {
          handF[side] = carry ? 0.1 * lh : 0.01 * Math.sin(tN * 2 + side);
          handS[side] = sg * (shS + (carry ? 0.075 : 0.065));
          handU[side] = carry ? shU - 0.2 * lh : shU - 0.2 * lh + 0.006 * Math.sin(tN * 2.2 + side);
          elbF[side] = handF[side] * 0.4 - 0.01;
          elbS[side] = sg * (shS + 0.075);
          elbU[side] = (shU + handU[side]) * 0.5 + 0.015;
        }
      }
    }
    fig.sy = sq;
    fig.sx = 1 / sq;
    for (let side = 0; side < 2; side++) {
      put(r, 4 + side, 0, (side === 0 ? 1 : -1) * hipS, hipU);
      put(r, 8 + side, footF[side], footS[side], footU[side]);
      put(r, 12 + side, kneeF[side], kneeS[side], kneeU[side] > 0 ? kneeU[side] : (hipU + footU[side]) * 0.5);
      put(r, 2 + side, lean, (side === 0 ? 1 : -1) * shS, shU);
      put(r, 6 + side, handF[side], handS[side], handU[side]);
      put(r, 10 + side, elbF[side], elbS[side], elbU[side]);
    }
    put(r, 14, lean * 0.5, 0, (shU + hipU) * 0.5);
    put(r, 0, lean + headF, headS, headU);
    put(r, 1, lean, 0, shU + 0.02 * lh);
    put(r, 23, lean + headF, headS, headU + 0.1 * lh);
    const X = PX;
    const Y = PY;
    const hr0 = 0.088 * lh * Math.sqrt(bw) * hs;
    const hry0 = 0.092 * lh * vs * fig.sy;
    const headKind = look.head || 'round';
    const hr = headKind === 'egg' ? hr0 * 0.92 : headKind === 'long' ? hr0 * 0.8 : hr0;
    const hry = headKind === 'egg' ? hry0 * 1.15 : headKind === 'long' ? hry0 * 1.3 : headKind === 'square' ? hry0 * 0.95 : hry0;
    const bodyKind = look.body || 'bean';
    const bodyRx = ((bodyKind === 'round' ? 0.095 : bodyKind === 'stick' ? 0.035 : bodyKind === 'box' ? 0.075 : 0.07) * bw * Math.abs(fig.cr) + 0.05 * Math.abs(fig.sr)) * hs * fig.sx + 1;
    const bodyRy = ((shU - hipU) * 0.5 + (bodyKind === 'round' ? 0.06 : 0.035) * lh) * vs * fig.sy;
    const yaw = rel + (e.lookAngle || 0);
    const noseX = Math.sin(yaw);
    const faceVis = Math.cos(yaw) < 0.2;
    const eyesVis = Math.cos(yaw) < -0.25;
    const acc = look.acc;
    const hat = look.hat || (acc === 'tophat' || acc === 'nightcap' || acc === 'bonnet' ? acc : 'none');
    const flee = mode === 'flee';
    // Accessory anchors.
    const scarfBack = moving ? (flee ? 0.18 : 0.1) + 0.03 * lagA : 0.03;
    put(r, 15, -0.02 - scarfBack, 0.045 * bw, shU - (flee ? 0.06 : 0.16) * lh + (moving ? 0.04 * lagA : 0.01 * Math.sin(tN * 2.6)));
    put(r, 16, -0.01 - scarfBack * 0.6, 0.04 * bw, shU - 0.05 * lh);
    const hatBack = flee ? 0.12 : moving ? 0.1 + 0.04 * lagA : 0.05;
    put(r, 17, -hatBack, 0.1, headU - 0.01 + (flee ? 0.05 * lh : 0));
    put(r, 18, -0.02, 0.05, headU + 0.15 * lh);
    const coatSwing = moving ? 0.06 * lh * lagA : 0;
    put(r, 21, -0.03 * lh + coatSwing, hipS * 1.6, hipU - 0.17 * lh);
    put(r, 22, -0.03 * lh - coatSwing * 0.6, -hipS * 1.6, hipU - 0.17 * lh);
    put(r, 19, handF[1], handS[1], handU[1]);
    if (prop === 'umbrella') put(r, 20, handF[1] + 0.02 * lh, handS[1] * 0.3, headU + 0.26 * lh);
    else if (prop === 'lantern') put(r, 20, handF[1] + (moving ? 0.04 * lagA : 0.01 * Math.sin(tN * 1.9 + pid)), handS[1] * 1.05, handU[1] - 0.09 * lh);
    else if (prop === 'basket') put(r, 20, handF[1], handS[1] * 1.1, handU[1] - 0.1 * lh);
    else put(r, 20, handF[1] + 0.01 * lh, handS[1] * 1.02, 0);
    // Gentler depth cue than walls so a far villager still reads.
    let alpha = Math.min(1, 1.15 * Math.pow(b, 0.65)) / (1 + 0.07 * depth) * 1.25;
    let lw = (depth < 1.5 ? 1.5 : 1) * r.wscale;
    const ctx = r.octx;
    let baseStyle;
    if (locked) {
      if (alpha < 0.9) alpha = 0.9;
      lw = 1.6 * r.wscale;
      baseStyle = COL_LOCK;
    } else if (flashWhite && !(sweeping && r.quality >= 1)) {
      const f = 1 - age / FLASH_AGE;
      alpha = Math.min(1, alpha + 0.5 * f);
      lw += 0.5 * f * r.wscale;
      baseStyle = '#ffffff';
    } else {
      baseStyle = spriteStyle(COL_PERSON, b);
    }
    ctx.strokeStyle = baseStyle;
    ctx.lineJoin = 'round';
    ctx.lineCap = 'round';
    let minX = X[0];
    let maxX = X[0];
    for (let k = 0; k < 24; k++) { if (X[k] < minX) minX = X[k]; if (X[k] > maxX) maxX = X[k]; }
    minX -= hr * 2.4 + 0.1 * hs;
    maxX += hr * 2.4 + 0.1 * hs;
    if (maxX < -lw || minX > r.ow + lw) return false;
    // Level of detail by on-screen size (figure px height ~ 0.8 * lh * vs).
    const figPx = 0.8 * lh * vs;
    const lod = r.quality < 1 ? 0 : figPx > 70 ? 2 : figPx > 34 ? 1 : 0;

    const drawAll = function (c, sa, style) {
      c.globalAlpha = Math.min(1, alpha * sa);
      c.strokeStyle = style;
      // Limbs: single thicker hose lines with round caps (no hinges).
      c.lineWidth = lw * 1.7;
      c.beginPath();
      for (let side = 0; side < 2; side++) {
        c.moveTo(X[4 + side], Y[4 + side]);
        c.quadraticCurveTo(X[12 + side], Y[12 + side], X[8 + side], Y[8 + side]);
        c.moveTo(X[2 + side], Y[2 + side]);
        c.quadraticCurveTo(X[10 + side], Y[10 + side], X[6 + side], Y[6 + side]);
      }
      if (prop === 'cane' && mode !== 'fed') {
        c.moveTo(X[19], Y[19]);
        c.lineTo(X[20], Y[20]);
      }
      c.stroke();
      // Outlines: head, torso, shoes, gloves, face, hair, hat, coat, scarf, prop.
      c.lineWidth = lw;
      c.beginPath();
      const hx = X[0];
      const hy = Y[0];
      if (headKind === 'square') squareHead(c, hx, hy, hr, hry, tilt * 0.6);
      else { c.moveTo(hx + hr, hy); c.ellipse(hx, hy, hr, hry, tilt * 0.6, 0, TWO_PI); }
      const bx = X[14];
      const by = Y[14];
      if (bodyKind === 'box') {
        // Boxy coat: a slightly bulging quad.
        c.moveTo(bx - bodyRx, by - bodyRy);
        c.quadraticCurveTo(bx, by - bodyRy * 1.1, bx + bodyRx, by - bodyRy);
        c.quadraticCurveTo(bx + bodyRx * 1.2, by, bx + bodyRx * 1.05, by + bodyRy);
        c.quadraticCurveTo(bx, by + bodyRy * 1.1, bx - bodyRx * 1.05, by + bodyRy);
        c.quadraticCurveTo(bx - bodyRx * 1.2, by, bx - bodyRx, by - bodyRy);
      } else if (bodyKind === 'pear') {
        c.moveTo(bx - bodyRx * 0.7, by - bodyRy);
        c.quadraticCurveTo(bx, by - bodyRy * 1.15, bx + bodyRx * 0.7, by - bodyRy);
        c.quadraticCurveTo(bx + bodyRx * 1.4, by + bodyRy * 0.3, bx + bodyRx * 1.1, by + bodyRy);
        c.quadraticCurveTo(bx, by + bodyRy * 1.25, bx - bodyRx * 1.1, by + bodyRy);
        c.quadraticCurveTo(bx - bodyRx * 1.4, by + bodyRy * 0.3, bx - bodyRx * 0.7, by - bodyRy);
      } else {
        c.moveTo(bx + bodyRx, by);
        c.ellipse(bx, by, bodyRx, bodyRy, -tilt * 0.4, 0, TWO_PI);
      }
      if (bodyKind === 'stick' && lod >= 1) {
        // A little paunch bump and a belt line.
        c.moveTo(bx - bodyRx * 1.6, by + bodyRy * 0.3);
        c.quadraticCurveTo(bx, by + bodyRy * 0.55, bx + bodyRx * 1.6, by + bodyRy * 0.3);
      }
      for (let side = 0; side < 2; side++) {
        const shoeR = hs * (0.032 + 0.03 * Math.abs(fig.sr)) * fig.sx + 1;
        const shoeY = Math.max(1.2, vs * 0.02 * fig.sy);
        c.moveTo(X[8 + side] + shoeR, Y[8 + side]);
        c.ellipse(X[8 + side] + fig.sr * hs * 0.03, Y[8 + side], shoeR, shoeY, 0, 0, TWO_PI);
        if (lod >= 2) {
          const hr2 = Math.max(1.3, hs * 0.02);
          c.moveTo(X[6 + side] + hr2, Y[6 + side]);
          c.arc(X[6 + side], Y[6 + side], hr2, 0, TWO_PI);
        }
      }
      if (lod >= 1 && faceVis) {
        const nz = (typeof look.nose === 'number' ? look.nose : 1);
        c.moveTo(hx + noseX * hr * 0.55, hy + hry * 0.12);
        c.lineTo(hx + noseX * hr * (0.75 + 0.25 * nz), hy + hry * (0.2 + 0.14 * nz));
        if (look.beard && lod >= 2) {
          c.moveTo(hx - hr * 0.55, hy + hry * 0.55);
          c.lineTo(hx - hr * 0.3, hy + hry * 1.1);
          c.lineTo(hx, hy + hry * 0.8);
          c.lineTo(hx + hr * 0.3, hy + hry * 1.1);
          c.lineTo(hx + hr * 0.55, hy + hry * 0.55);
        }
      }
      if (lod >= 1 && eyesVis) {
        for (let side = -1; side <= 1; side += 2) {
          const ex = hx + side * hr * 0.4 + noseX * hr * 0.2;
          if (eyesX) {
            const q = Math.max(1.2, hr * 0.14);
            c.moveTo(ex - q, hy - hry * 0.2); c.lineTo(ex + q, hy);
            c.moveTo(ex + q, hy - hry * 0.2); c.lineTo(ex - q, hy);
          } else {
            c.moveTo(ex, hy - hry * 0.2);
            c.lineTo(ex, hy - hry * 0.02);
          }
        }
      }
      // Hair (only when no hat hides it).
      const hair = hat === 'none' || hat === 'cap' || hat === 'bonnet' ? look.hair : 'none';
      if (lod >= 1 && hair && hair !== 'none') {
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
      const fedHat = mode === 'fed' && hat !== 'hood';
      const hhx = fedHat ? X[9] + hr * 2.6 : X[0];
      const hhy = fedHat ? fig.floorY - hry * 0.35 : Y[0];
      const hatTilt = fedHat ? 0.9 : tilt;
      if (hat === 'tophat') {
        const hy2 = hhy - hry * 0.78;
        const bw2 = hr * 1.25;
        const th = vs * 0.14 * lh * fig.sy;
        const lean2 = hatTilt * th * 1.2 + (flee ? -hr * 0.6 : 0);
        const lift = flee ? -th * 0.35 : jump > 0 ? -jump * vs * 0.8 : 0;
        c.moveTo(hhx + bw2, hy2 + lift);
        c.ellipse(hhx, hy2 + lift, bw2, Math.max(1.2, vs * 0.012), 0, 0, TWO_PI);
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
        // Flat cap: a low dome with a brim poking out the front.
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
        // Pointed hood running into the shoulders.
        const ty = hhy - hry;
        c.moveTo(X[2] - hr * 0.2, Y[2]);
        c.quadraticCurveTo(hhx - hr * 1.35, hhy - hry * 0.2, hhx - hr * 0.2 + (moving ? -hr * 0.3 : 0), ty - hry * 0.45);
        c.quadraticCurveTo(hhx + hr * 1.35, hhy - hry * 0.2, X[3] + hr * 0.2, Y[3]);
      }
      // Coat hem.
      if (lod >= 1 && look.coat && mode !== 'fed') {
        const cy0 = by + bodyRy * 0.35;
        c.moveTo(bx + bodyRx * 0.98, cy0);
        c.quadraticCurveTo(X[21] + bodyRx * 0.2, (cy0 + Y[21]) * 0.5, X[21] + bodyRx * 0.1, Y[21]);
        c.quadraticCurveTo((X[21] + X[22]) * 0.5, Y[21] + vs * 0.02, X[22] - bodyRx * 0.1, Y[22]);
        c.quadraticCurveTo(X[22] - bodyRx * 0.2, (cy0 + Y[22]) * 0.5, bx - bodyRx * 0.98, cy0);
      }
      // Seated: the edge of the bench or stool under them.
      if (seated) {
        const sw = hs * 0.26 * bw;
        c.moveTo(X[14] - sw, Y[4] + vs * 0.01);
        c.lineTo(X[14] + sw, Y[5] + vs * 0.01);
      }
      // Scarf.
      if (acc === 'scarf') {
        const nyy = Y[1] - bodyRy * 0.1;
        c.moveTo(X[1] - bodyRx * 0.8, nyy);
        c.quadraticCurveTo(X[1], nyy + hry * 0.5, X[1] + bodyRx * 0.8, nyy);
        c.moveTo(X[1] + bodyRx * 0.55, nyy + hry * 0.15);
        c.quadraticCurveTo(X[16], Y[16], X[15], Y[15]);
      }
      // Props carried in the right hand.
      if (prop === 'cane' && mode !== 'fed') {
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
      // Hands over the head (cower): small fingers.
      if (handsOverHead && lod >= 2) {
        for (let side = 0; side < 2; side++) {
          c.moveTo(X[6 + side], Y[6 + side]);
          c.lineTo(X[6 + side] + (side ? -1 : 1) * hr * 0.3, Y[6 + side] - hry * 0.25);
        }
      }
      c.stroke();
      // Dazed: three little stars circling the head (0.4 Hz).
      if (stars) {
        c.beginPath();
        const rr = Math.max(1.2, hr * 0.13);
        for (let k = 0; k < 3; k++) {
          const a = (anim ? tN * 2.5 : 0) + k * 2.094 + pid;
          const sx = X[23] + Math.cos(a) * hr * 1.7;
          const sy = Y[23] - hry * 0.25 + Math.sin(a) * hry * 0.35;
          c.moveTo(sx - rr, sy); c.lineTo(sx + rr, sy);
          c.moveTo(sx, sy - rr); c.lineTo(sx, sy + rr);
        }
        c.stroke();
      }
    };

    // Lit height band [zMin, zMax] from the pulse, and the sweeping band front.
    let zMin = typeof e.zMin === 'number' ? e.zMin : 0;
    let zMax = typeof e.zMax === 'number' ? e.zMax : 2;
    if (zMax >= 1.15) zMax = 2;
    const nStrips = STRIP_Z.length - 1;
    const strips = sweeping && r.quality >= 1;
    let lo = 1;
    let hi = 0;
    let frontStrip = -1;
    for (let s = 0; s < nStrips; s++) {
      const zm = (STRIP_Z[s] + STRIP_Z[s + 1]) * 0.5;
      let a = Ripple.maskAlpha(Math.min(zm, 1.1), zMin, zMax, 0.12);
      if (strips) {
        const local = age - (Math.min(zm, 1.25) / SWEEP_OVER) * SWEEP;
        const g = local < 0 ? 0 : glow(local, dur);
        a *= g;
        if (g > 0 && local < FLASH_AGE && frontStrip < 0) frontStrip = s;
      } else if (age >= 0 && !locked) {
        a *= glow(age, dur);
      }
      STRIP_A[s] = a;
      if (a < lo) lo = a;
      if (a > hi) hi = a;
    }
    if (hi < 0.02) return false;
    const uniform = hi - lo < 0.03 && frontStrip < 0;
    const uToY = function (z) { return fig.floorY - z * FIG_H * lh * fig.sy * vs; };
    const wrapped = function (c) {
      if (uniform) { drawAll(c, hi, baseStyle); return; }
      for (let s = 0; s < nStrips; s++) {
        const sa = STRIP_A[s];
        if (sa < 0.02) continue;
        const za = STRIP_Z[s];
        const zb = STRIP_Z[s + 1];
        c.save();
        c.beginPath();
        const yTop = zb >= FIG_ZTOP - 1e-3 ? -50 : uToY(zb);
        const yBot = za <= 1e-3 ? fig.floorY + 30 * r.wscale : uToY(za);
        c.rect(minX, yTop, maxX - minX, yBot - yTop);
        c.clip();
        drawAll(c, sa, s === frontStrip && !locked ? '#ffffff' : baseStyle);
        c.restore();
      }
      // The band front: thin rings wrapping the body where the wave is right now.
      if (strips && r.quality >= 2 && age < SWEEP) {
        const f = (age / SWEEP) * SWEEP_OVER;
        c.strokeStyle = '#ffffff';
        c.lineWidth = Math.max(1, lw * 0.9);
        for (let m = 0; m < 3; m++) {
          const zn = f - m * 0.15;
          if (zn < 0 || zn > 1.05) continue;
          const u = zn * fig.H;
          const rad = u < hipU ? hipS * 1.3 : u < shU ? bodyRx / hs / fig.sx : u < headU - 0.06 * lh ? 0.04 : hr / hs * 0.9;
          const rx = rad * hs * 1.15;
          const g = (1 - age / SWEEP) * (1 - m * 0.3);
          c.globalAlpha = Math.min(1, alpha * g * 1.4);
          c.beginPath();
          c.ellipse(fig.cx + fig.sway * u * hs + sweepWave(zn, age) * 0.02 * hs, fig.floorY - u * fig.sy * vs, rx, Math.max(1, rx * 0.22), 0, 0, TWO_PI);
          c.stroke();
        }
      }
    };
    clippedDraw(r, minX - lw, maxX + lw, depth, wrapped);
    ctx.globalAlpha = 1;
    return true;
  }

  // ---- Props: outline doodles drawn through the sprite path (lit only by pulses, height-masked) ----
  const PROP_MAX_DIST = 12;
  const COL_PROP = [200, 214, 236];
  const COL_FLAME = 'rgb(255,176,64)';
  const COL_FLAME_IN = 'rgb(255,226,140)';
  const COL_LIGHT = 'rgb(255,170,70)';
  const PROP_DEF = {
    gravestone: { zc: 0.2, top: 0.4 },
    cross: { zc: 0.3, top: 0.64 },
    barrel: { zc: 0.22, top: 0.46 },
    table: { zc: 0.2, top: 0.4 },
    chair: { zc: 0.22, top: 0.52 },
    bench: { zc: 0.2, top: 0.4 },
    well: { zc: 0.3, top: 0.86 },
    torch: { zc: 0.72, top: 0.85, fire: true, light: 3 },
    brazier: { zc: 0.45, top: 0.78, fire: true, light: 3.5 }
  };
  /** Extra heights sampled when a fire prop is not lit at its centre height. */
  const FIRE_Z = [0.3, 0.95, 0.5];
  const propOff = typeof WeakMap === 'function' ? new WeakMap() : null;
  const STRIPS = new Float32Array(9);
  const bandOut = new Float32Array(2);
  const pband = { lo: 0, hi: 0 };
  /** Holder side for the torch being drawn (see torchHolder); set per prop in drawProps. */
  let holdLat = 2;

  /** Union of lit heights at (x,y) over all pulses that currently reach it; false when none. */
  function propBand(sonar, t, x, y) {
    const Sonar = VCS.Sonar;
    const ps = sonar.pulses;
    let lo = 9;
    let hi = -9;
    const hasBand = typeof Sonar.heightBand === 'function';
    for (let k = 0; k < ps.length; k++) {
      const pu = ps[k];
      const dx = x - pu.x;
      const dy = y - pu.y;
      const d = Math.sqrt(dx * dx + dy * dy);
      if (d > pu.range) continue;
      const age = t - (pu.t0 + d / pu.speed);
      const pf = typeof pu.fade === 'number' && pu.fade > 0 ? pu.fade : sonar.fade;
      if (age < 0 || age >= glowDur(pf)) continue;
      if (!Sonar.visibleFrom(pu, x, y)) continue;
      if (hasBand) {
        if (!Sonar.heightBand(pu, t, x, y, bandOut)) continue;
        if (bandOut[0] < lo) lo = bandOut[0];
        if (bandOut[1] > hi) hi = bandOut[1];
      } else { lo = 0; hi = 1.2; }
    }
    if (hi < lo) return false;
    pband.lo = lo;
    pband.hi = hi;
    return true;
  }

  /** Steady teardrop flame (outer + inner); only the tip sways, slower than 1 Hz, and the size never changes. */
  function flamePath(c, x, y0, w, h, t, ph) {
    const sw = Math.sin(t * TWO_PI * 0.6 + ph) * w * 0.25;
    const hh = h;
    c.moveTo(x, y0);
    c.quadraticCurveTo(x - w, y0 - hh * 0.45, x + sw, y0 - hh);
    c.quadraticCurveTo(x + w, y0 - hh * 0.45, x, y0);
    c.moveTo(x, y0);
    c.quadraticCurveTo(x - w * 0.45, y0 - hh * 0.3, x + sw * 0.6, y0 - hh * 0.6);
    c.quadraticCurveTo(x + w * 0.45, y0 - hh * 0.3, x, y0);
  }

  /**
   * Torch holder path (no stroke): lat in -1..1 is the wall's side on screen (wall sconce: iron bracket and
   * plate on that wall face, wooden shaft in a cup); lat > 1.5 means no wall, a free-standing iron post.
   */
  function torchHolder(c, cx, Y, hs, lat) {
    const w = 0.07 * hs;
    // Wooden shaft and the cup it sits in (flame starts at Y(0.62)).
    c.moveTo(cx, Y(0.42));
    c.lineTo(cx, Y(0.6));
    c.moveTo(cx - w * 1.3, Y(0.62));
    c.lineTo(cx - w, Y(0.54));
    c.lineTo(cx + w, Y(0.54));
    c.lineTo(cx + w * 1.3, Y(0.62));
    if (lat > 1.5) {
      // Free-standing: post with a ring holder under the cup and a splayed foot.
      c.moveTo(cx, Y(0.54));
      c.lineTo(cx, Y(0.04));
      c.moveTo(cx - w * 1.1, Y(0.44));
      c.lineTo(cx + w * 1.1, Y(0.44));
      c.moveTo(cx - w * 2.2, Y(0));
      c.lineTo(cx, Y(0.1));
      c.lineTo(cx + w * 2.2, Y(0));
      return;
    }
    // Wall sconce: plate bar on the wall face, scrolled arm curling up to the cup.
    const dir = lat < 0 ? -1 : 1;
    const len = (0.12 + 0.2 * Math.abs(lat)) * hs + w * 1.5;
    const wx = cx + dir * len;
    c.moveTo(wx, Y(0.28));
    c.lineTo(wx, Y(0.5));
    c.moveTo(wx, Y(0.34));
    c.quadraticCurveTo(cx + dir * len * 0.4, Y(0.34), cx, Y(0.44));
    c.moveTo(cx + dir * w * 1.2, Y(0.4));
    c.arc(cx + dir * w * 0.8, Y(0.37), w * 0.5, 0, TWO_PI);
    c.moveTo(cx - w * 0.9, Y(0.44));
    c.lineTo(cx + w * 0.9, Y(0.44));
  }

  /** Stroke the body path of a prop (hs = px per cell, vs = px per wall height, fy = floor y at centre). */
  function propBody(c, type, cx, fy, hs, vs, t, ph, body, alpha, lat) {
    const Y = function (z) { return fy - z * vs; };
    c.strokeStyle = body;
    c.beginPath();
    switch (type) {
      case 'gravestone': {
        const w = 0.2 * hs;
        c.moveTo(cx - w, fy);
        c.lineTo(cx - w, Y(0.26));
        c.quadraticCurveTo(cx - w, Y(0.4), cx, Y(0.4));
        c.quadraticCurveTo(cx + w, Y(0.4), cx + w, Y(0.26));
        c.lineTo(cx + w, fy);
        c.moveTo(cx - w * 1.5, fy);
        c.lineTo(cx + w * 1.5, fy);
        c.moveTo(cx, Y(0.3));
        c.lineTo(cx, Y(0.2));
        c.moveTo(cx - w * 0.4, Y(0.26));
        c.lineTo(cx + w * 0.4, Y(0.26));
        break;
      }
      case 'cross': {
        const w = 0.1 * hs;
        c.moveTo(cx - w * 0.3, fy);
        c.lineTo(cx - w * 0.3, Y(0.42));
        c.lineTo(cx - w * 1.6, Y(0.42));
        c.lineTo(cx - w * 1.6, Y(0.5));
        c.lineTo(cx - w * 0.3, Y(0.5));
        c.lineTo(cx - w * 0.3, Y(0.64));
        c.lineTo(cx + w * 0.3, Y(0.64));
        c.lineTo(cx + w * 0.3, Y(0.5));
        c.lineTo(cx + w * 1.6, Y(0.5));
        c.lineTo(cx + w * 1.6, Y(0.42));
        c.lineTo(cx + w * 0.3, Y(0.42));
        c.lineTo(cx + w * 0.3, fy);
        c.moveTo(cx - w, fy);
        c.lineTo(cx + w, fy);
        break;
      }
      case 'barrel': {
        const w = 0.2 * hs;
        const e = Math.max(1.2, vs * 0.025);
        c.moveTo(cx - w, Y(0.44));
        c.quadraticCurveTo(cx - w * 1.25, Y(0.22), cx - w, fy);
        c.quadraticCurveTo(cx, fy + e * 1.6, cx + w, fy);
        c.quadraticCurveTo(cx + w * 1.25, Y(0.22), cx + w, Y(0.44));
        c.moveTo(cx + w, Y(0.44));
        c.ellipse(cx, Y(0.44), w, e, 0, 0, TWO_PI);
        c.moveTo(cx - w * 1.1, Y(0.15));
        c.quadraticCurveTo(cx, Y(0.15) + e * 1.5, cx + w * 1.1, Y(0.15));
        c.moveTo(cx - w * 1.1, Y(0.31));
        c.quadraticCurveTo(cx, Y(0.31) + e * 1.5, cx + w * 1.1, Y(0.31));
        break;
      }
      case 'table': {
        const w = 0.36 * hs;
        c.moveTo(cx - w, Y(0.38));
        c.lineTo(cx + w, Y(0.38));
        c.lineTo(cx + w, Y(0.34));
        c.lineTo(cx - w, Y(0.34));
        c.closePath();
        c.moveTo(cx - w * 0.85, Y(0.34));
        c.lineTo(cx - w * 0.85, fy);
        c.moveTo(cx + w * 0.85, Y(0.34));
        c.lineTo(cx + w * 0.85, fy);
        c.moveTo(cx - w * 0.5, Y(0.34));
        c.lineTo(cx - w * 0.5, Y(0.05));
        c.moveTo(cx + w * 0.5, Y(0.34));
        c.lineTo(cx + w * 0.5, Y(0.05));
        break;
      }
      case 'chair': {
        const w = 0.15 * hs;
        c.moveTo(cx - w, Y(0.5));
        c.lineTo(cx - w, Y(0.22));
        c.lineTo(cx + w, Y(0.22));
        c.lineTo(cx + w, Y(0.5));
        c.moveTo(cx - w, Y(0.42));
        c.lineTo(cx + w, Y(0.42));
        c.moveTo(cx - w, Y(0.22));
        c.lineTo(cx - w, fy);
        c.moveTo(cx + w, Y(0.22));
        c.lineTo(cx + w, fy);
        c.moveTo(cx - w * 0.9, Y(0.19));
        c.lineTo(cx + w * 0.9, Y(0.19));
        break;
      }
      case 'bench': {
        const w = 0.42 * hs;
        c.moveTo(cx - w, Y(0.2));
        c.lineTo(cx + w, Y(0.2));
        c.moveTo(cx - w, Y(0.17));
        c.lineTo(cx + w, Y(0.17));
        c.moveTo(cx - w * 0.9, Y(0.17));
        c.lineTo(cx - w * 0.9, fy);
        c.moveTo(cx + w * 0.9, Y(0.17));
        c.lineTo(cx + w * 0.9, fy);
        c.moveTo(cx - w, Y(0.4));
        c.lineTo(cx + w, Y(0.4));
        c.moveTo(cx - w * 0.9, Y(0.2));
        c.lineTo(cx - w * 0.9, Y(0.4));
        c.moveTo(cx + w * 0.9, Y(0.2));
        c.lineTo(cx + w * 0.9, Y(0.4));
        break;
      }
      case 'well': {
        const w = 0.38 * hs;
        const e = Math.max(1.5, vs * 0.05);
        c.moveTo(cx - w, Y(0.3));
        c.lineTo(cx - w, fy);
        c.quadraticCurveTo(cx, fy + e * 1.6, cx + w, fy);
        c.lineTo(cx + w, Y(0.3));
        c.moveTo(cx + w, Y(0.3));
        c.ellipse(cx, Y(0.3), w, e, 0, 0, TWO_PI);
        c.moveTo(cx - w * 0.85, Y(0.3));
        c.lineTo(cx - w * 0.85, Y(0.8));
        c.moveTo(cx + w * 0.85, Y(0.3));
        c.lineTo(cx + w * 0.85, Y(0.8));
        c.moveTo(cx - w * 1.05, Y(0.76));
        c.lineTo(cx, Y(0.88));
        c.lineTo(cx + w * 1.05, Y(0.76));
        c.moveTo(cx, Y(0.78));
        c.lineTo(cx, Y(0.5));
        c.moveTo(cx + w * 0.18, Y(0.5));
        c.arc(cx, Y(0.5), w * 0.18, 0, TWO_PI);
        break;
      }
      case 'torch': {
        torchHolder(c, cx, Y, hs, lat);
        break;
      }
      case 'brazier': {
        const w = 0.2 * hs;
        const e = Math.max(1.3, vs * 0.03);
        c.moveTo(cx - w, Y(0.4));
        c.quadraticCurveTo(cx - w * 0.9, Y(0.27), cx, Y(0.24));
        c.quadraticCurveTo(cx + w * 0.9, Y(0.27), cx + w, Y(0.4));
        c.moveTo(cx + w, Y(0.4));
        c.ellipse(cx, Y(0.4), w, e, 0, 0, TWO_PI);
        c.moveTo(cx - w * 0.3, Y(0.24));
        c.lineTo(cx - w * 0.8, fy);
        c.moveTo(cx + w * 0.3, Y(0.24));
        c.lineTo(cx + w * 0.8, fy);
        c.moveTo(cx, Y(0.24));
        c.lineTo(cx, fy);
        c.moveTo(cx - w * 0.9, fy);
        c.lineTo(cx + w * 0.9, fy);
        break;
      }
      default: break;
    }
    c.stroke();
    if (type === 'torch' || type === 'brazier') {
      const fw = (type === 'torch' ? 0.07 : 0.13) * hs;
      const fy0 = type === 'torch' ? Y(0.62) : Y(0.4);
      const fh = (type === 'torch' ? 0.2 : 0.34) * vs;
      c.strokeStyle = COL_FLAME;
      c.beginPath();
      flamePath(c, cx, fy0, fw, fh, t, ph);
      c.stroke();
    }
  }

  /** Draw all props lit by the current pulses; returns the count drawn. */
  function drawProps(r, world, player, sonar, t, tanHalf) {
    const props = world.props;
    if (!props || !props.length || !sonar.pulses.length) return 0;
    const Ripple = VCS.Ripple;
    const halfW = r.ow / 2;
    const focal = halfW / tanHalf;
    const ca = Math.cos(player.angle);
    const sa = Math.sin(player.angle);
    const ctx = r.octx;
    let drawn = 0;
    for (let k = 0; k < props.length; k++) {
      const pr = props[k];
      const def = pr && PROP_DEF[pr.type];
      if (!def) continue;
      const dx = pr.x - player.x;
      const dy = pr.y - player.y;
      if (dx * dx + dy * dy > PROP_MAX_DIST * PROP_MAX_DIST) continue;
      const fwd0 = dx * ca + dy * sa;
      if (fwd0 <= 0.1) continue;
      const right0 = -dx * sa + dy * ca;
      if (Math.abs(right0) > fwd0 * tanHalf * 1.2 + 1) continue;
      let b = litAt3(sonar, pr.x, pr.y, def.zc, t);
      if (def.fire && b <= 0.01) {
        // Fires: any wavefront that reached the torch (at any height) draws flame and holder for the afterglow.
        for (let q = 0; q < FIRE_Z.length && b <= 0.01; q++) b = litAt3(sonar, pr.x, pr.y, FIRE_Z[q], t);
      }
      if (b <= 0.01) continue;
      const age = samp3[1];
      // Sconces hug the nearest wall.
      let px = pr.x;
      let py = pr.y;
      if (pr.type === 'torch') {
        let off = propOff ? propOff.get(pr) : null;
        if (!off) {
          off = { x: 0, y: 0 };
          const cx = Math.floor(pr.x);
          const cy = Math.floor(pr.y);
          if (world.isSolid(cx + 1, cy)) off.x = 0.42;
          else if (world.isSolid(cx - 1, cy)) off.x = -0.42;
          else if (world.isSolid(cx, cy + 1)) off.y = 0.42;
          else if (world.isSolid(cx, cy - 1)) off.y = -0.42;
          if (propOff) propOff.set(pr, off);
        }
        px += off.x;
        py += off.y;
        holdLat = off.x === 0 && off.y === 0 ? 2 : (off.x > 0 ? 1 : off.x < 0 ? -1 : 0) * -sa + (off.y > 0 ? 1 : off.y < 0 ? -1 : 0) * ca;
      }
      if (!project(player, px, py, halfW, tanHalf)) continue;
      const depth = proj.fwd;
      const cx = proj.sx;
      const hs = focal / depth;
      if (cx < -hs - 40 || cx > r.ow + hs + 40) continue;
      const vs = r.oh / depth;
      const fy = r.horizon + 0.5 * vs;
      const flash = age >= 0 && age < FLASH_AGE;
      let alpha = lineAlpha(b, depth) * 1.2;
      let lw = (depth < 1.5 ? 1.5 : 1) * r.wscale;
      if (flash) { alpha = Math.min(1, alpha + 0.5 * (1 - age / FLASH_AGE)); lw += 0.4 * r.wscale; }
      const idb = ((pr.x * 7 + pr.y * 13) | 0) * 8;
      const jx = r.boilOn ? J(r, idb, 0) * 0.7 * r.wscale : 0;
      const jy = r.boilOn ? J(r, idb, 1) * 0.7 * r.wscale : 0;
      const body = flash ? '#ffffff' : spriteStyle(COL_PROP, b);
      const phase = (pr.x * 3.1 + pr.y * 1.7);
      let full = true;
      let zMin = 0;
      let zMax = 1.2;
      if (!def.fire && propBand(sonar, t, pr.x, pr.y)) {
        zMin = pband.lo;
        zMax = pband.hi;
        full = zMin <= 0.02 && zMax >= def.top + 0.05;
      }
      const hw = hs * 0.5 + 6;
      ctx.lineWidth = lw;
      ctx.lineJoin = 'round';
      ctx.lineCap = 'round';
      const cxj = cx + jx;
      const fyj = fy + jy;
      const fn = function (c) {
        if (full || !Ripple) {
          c.globalAlpha = Math.min(1, alpha);
          propBody(c, pr.type, cxj, fyj, hs, vs, t, phase, body, alpha, holdLat);
          return;
        }
        const ns = Ripple.maskStrips(zMin, zMax, 1.0, 0.12, STRIPS);
        for (let s2 = 0; s2 < ns; s2++) {
          const za = STRIPS[s2 * 3];
          const zb = STRIPS[s2 * 3 + 1];
          const sal = STRIPS[s2 * 3 + 2];
          c.save();
          c.beginPath();
          const yTop = zb >= 1.0 - 1e-3 ? -50 : fyj - zb * vs;
          const yBot = za <= 1e-3 ? fyj + 30 * r.wscale : fyj - za * vs;
          c.rect(cxj - hw - hs * 0.4, yTop, hw * 2 + hs * 0.8, yBot - yTop);
          c.clip();
          c.globalAlpha = Math.min(1, alpha * sal);
          propBody(c, pr.type, cxj, fyj, hs, vs, t, phase, body, alpha, holdLat);
          c.restore();
        }
      };
      clippedDraw(r, cx - hw - lw - hs * 0.4, cx + hw + lw + hs * 0.4, depth, fn);
      drawn++;
    }
    ctx.globalAlpha = 1;
    return drawn;
  }

  /** Draw fading echo snapshots of people (oldest first so newest is on top). */
  function drawEchoes(r, people, sonar, t, player, tanHalf) {
    const es = people && people.echoes;
    if (!es || !es.length) return 0;
    const People = VCS.People;
    const fade = sonar.fade || 3;
    const lockId = r.lockId;
    // Newest echo of the locked victim is kept visible at full brightness.
    let newest = -1;
    if (lockId >= 0) {
      let bt = -Infinity;
      for (let i = 0; i < es.length; i++) {
        if (es[i].personId === lockId && es[i].t >= bt) { bt = es[i].t; newest = i; }
      }
    }
    let n = 0;
    for (let i = 0; i < es.length; i++) {
      const e = es[i];
      const lk = lockId >= 0 && e.personId === lockId;
      const age = People.echoAge(e, t);
      if (lk) {
        // The victim stays lit while drinking (newest snapshot only).
        if (i !== newest) continue;
        if (drawPerson(r, player, tanHalf, e, 0.9, -1, false, t, true)) n++;
        continue;
      }
      // Ripple-only: the snapshot shows while the band sweeps it and for one afterglow after.
      if (!(age >= 0)) continue;
      const ef = typeof e.fade === 'number' && e.fade > 0 ? e.fade : fade;
      if (age >= SWEEP + glowDur(ef)) continue;
      let b = typeof e.strength === 'number' ? e.strength : 1;
      if (b <= 0.01) continue;
      if (b > 1) b = 1;
      if (drawPerson(r, player, tanHalf, e, b, age, age < FLASH_AGE, t, false)) n++;
    }
    return n;
  }

  /** Cached radial vignette canvas (transparent centre, black edge); rebuilt only when the size changes. */
  function drawFeedVignette(r, v) {
    try {
      const ctx = r.ctx;
      const W = r.canvas.width;
      const H = r.canvas.height;
      if (!r.feedVig || r.feedVigW !== W || r.feedVigH !== H) {
        const doc = r.canvas.ownerDocument || root.document;
        const c = r.feedVig || doc.createElement('canvas');
        c.width = W;
        c.height = H;
        const g2 = c.getContext('2d');
        const hd = Math.sqrt(W * W + H * H) / 2;
        const gr = g2.createRadialGradient(W / 2, H / 2, 0, W / 2, H / 2, hd);
        gr.addColorStop(0, 'rgba(0,0,0,0)');
        gr.addColorStop(0.45, 'rgba(0,0,0,0)');
        gr.addColorStop(1, 'rgba(0,0,0,0.85)');
        g2.clearRect(0, 0, W, H);
        g2.fillStyle = gr;
        g2.fillRect(0, 0, W, H);
        r.feedVig = c;
        r.feedVigW = W;
        r.feedVigH = H;
      }
      ctx.globalCompositeOperation = 'source-over';
      ctx.globalAlpha = 0.5 * v;
      ctx.drawImage(r.feedVig, 0, 0);
      ctx.globalAlpha = 1;
    } catch (e) {
      logOnce(r, 'feedVignette', e);
    }
  }

  /** Warm screen-edge glow alpha for raw light level lit (0..1): continuous, no time term. */
  function edgeGlowAlpha(lit) {
    const k = typeof lit === 'number' && isFinite(lit) ? (lit < 0 ? 0 : lit > 1 ? 1 : lit) : 0;
    return Math.pow(k, 1.2) * 0.5 * EDGE_GLOW_MAX;
  }

  /** Edge glow alpha from the core and outer light values: the outer zone reads faint (<= 35%). */
  function edgeZoneAlpha(core, outer) {
    const c = typeof core === 'number' && isFinite(core) ? core : 0;
    const o = typeof outer === 'number' && isFinite(outer) ? outer : 0;
    return edgeGlowAlpha(Math.max(c, 0.35 * o));
  }

  /**
   * Directional edge glow for the player: { left, right, top } alphas (0..1).
   * Stronger on the side facing nearby lights, weak on the far side. All zero with no light nearby.
   * Optional state ({ out, cos, side, init }) low-passes the bearing (0.15 per frame) so turning
   * does not snap; with reduced true the target is used directly. Without state the call is pure.
   */
  function edgeSides(world, player, state, reduced) {
    const out = state && state.out ? state.out : { left: 0, right: 0, top: 0 };
    out.left = 0;
    out.right = 0;
    out.top = 0;
    if (!world || !player || typeof world.outerAt !== 'function' || typeof world.lightSources !== 'function') return out;
    const px = player.x;
    const py = player.y;
    const core = world.lightAt(px, py);
    const outer = world.outerAt(px, py);
    const ea = edgeZoneAlpha(core, outer);
    if (!(ea > 0)) { if (state) state.init = false; return out; }
    const srcs = world.lightSources();
    let sx = 0;
    let sy = 0;
    let sw = 0;
    for (let i = 0; i < srcs.length; i++) {
      const L = srcs[i];
      const dx = L.x - px;
      const dy = L.y - py;
      const d = Math.sqrt(dx * dx + dy * dy);
      if (d > 3 * L.radius) continue;
      const RO = L.radius * 1.8;
      if (d >= RO) continue;
      const w = d <= 0.5 * RO ? 1 : 2 - 2 * d / RO;
      if (!(w > 0)) continue;
      const rel = Math.atan2(Math.sin(Math.atan2(dy, dx) - player.angle), Math.cos(Math.atan2(dy, dx) - player.angle));
      // A light on the player's own spot has no bearing: it adds weight but no direction.
      if (d > 0.05) { sx += w * Math.cos(rel); sy += w * Math.sin(rel); }
      sw += w;
    }
    if (!(sw > 0)) { if (state) state.init = false; return out; }
    let cosRel = sx / sw;
    let side = Math.max(-1, Math.min(1, sy / sw));
    if (state) {
      if (!state.init || reduced) { state.cos = cosRel; state.side = side; state.init = true; }
      else {
        state.cos += (cosRel - state.cos) * 0.15;
        state.side += (side - state.side) * 0.15;
      }
      cosRel = state.cos;
      side = state.side;
    }
    const a = Math.abs(side);
    const near = 1 + 0.6 * a;
    const far = 1 - 0.6 * a;
    out.right = Math.min(1, ea * (side >= 0 ? near : far));
    out.left = Math.min(1, ea * (side >= 0 ? far : near));
    out.top = Math.min(1, ea * (0.5 + 0.5 * Math.max(0, cosRel)));
    return out;
  }

  /** Draw vignette and faint animated film grain over the frame. */
  function drawAtmosphere(r, lit, t, world, player) {
    const ctx = r.ctx;
    ctx.globalCompositeOperation = 'source-over';
    ctx.globalAlpha = 1;
    if (r.vignette) ctx.drawImage(r.vignette, 0, 0);
    if (world && player && r.warmSide) {
      // Zoned, directional edge glow (core + faint outer halo), steady.
      if (!r.edgeState) r.edgeState = { out: { left: 0, right: 0, top: 0 }, cos: 0, side: 0, init: false };
      const e = edgeSides(world, player, r.edgeState, r.reduced);
      ctx.globalCompositeOperation = 'lighter';
      if (e.left > 0.002) { ctx.globalAlpha = e.left; ctx.drawImage(r.warmSide.left, 0, 0); }
      if (e.right > 0.002) { ctx.globalAlpha = e.right; ctx.drawImage(r.warmSide.right, 0, 0); }
      if (e.top > 0.002) { ctx.globalAlpha = e.top; ctx.drawImage(r.warmSide.top, 0, 0); }
      ctx.globalCompositeOperation = 'source-over';
      ctx.globalAlpha = 1;
    } else if (edgeGlowAlpha(lit) > 0.002 && r.warmVig) {
      const ea = edgeGlowAlpha(lit);
      // Warm glow at the screen edges, steady, stronger the closer the player is to the light.
      ctx.globalCompositeOperation = 'lighter';
      ctx.globalAlpha = ea;
      ctx.drawImage(r.warmVig, 0, 0);
      ctx.globalCompositeOperation = 'source-over';
      ctx.globalAlpha = 1;
    }
    // Film grain is a CSS overlay (#grain); keep its opacity in step with quality (cheap no-op when unchanged).
    if (r.grainEl) setGrain(r, r.grainLevel);
    ctx.globalCompositeOperation = 'source-over';
    ctx.globalAlpha = 1;
  }

  /** Adaptive quality: step down when slow for 2 s while lit, up when fast for 5 s. */
  function adapt(r, active) {
    const now = typeof performance !== 'undefined' ? performance.now() : Date.now();
    const dt = now - r.lastFrame;
    r.lastFrame = now;
    if (!active || dt <= 0 || dt > 250) { r.lowT = 0; r.highT = 0; return; }
    r.fpsEma += (1000 / dt - r.fpsEma) * 0.08;
    if (r.fpsEma < 45) { r.lowT += dt; r.highT = 0; }
    else if (r.fpsEma > 58) { r.highT += dt; r.lowT = 0; }
    else { r.lowT = 0; r.highT = 0; }
    let q = r.quality;
    if (r.lowT > 2000 && r.matDetail && r.quality >= 2) {
      // Material detail is the first thing to go.
      r.matDetail = false;
      r.lowT = 0;
      const log0 = VCS.Log && VCS.Log.get('render');
      if (log0) log0.info('material detail off (fps ~' + Math.round(r.fpsEma) + ')');
    } else if (r.lowT > 2000 && q > 0) q--;
    else if (r.highT > 5000 && q < r.maxQuality) q++;
    else if (r.highT > 5000 && !r.matDetail) { r.matDetail = true; r.highT = 0; }
    if (q !== r.quality) {
      r.quality = q;
      r.lowT = 0;
      r.highT = 0;
      const log = VCS.Log && VCS.Log.get('render');
      if (log) log.info('render quality ' + q + ' (fps ~' + Math.round(r.fpsEma) + ')');
    }
  }

  /** Warm sense: soft coral halos on nearby people, drawn over walls (seen through them). */
  function drawWarm(r, player, tanHalf, warm) {
    const rad = warm && typeof warm.radius === 'number' && isFinite(warm.radius) ? warm.radius : 0;
    const list = warm && warm.people;
    if (rad <= 0 || !list || !list.length) return 0;
    const ctx = r.ctx;
    const W = r.canvas.width;
    const H = r.canvas.height;
    const halfW = W / 2;
    const hy = r.horizon * (H / r.oh);
    const ca = Math.cos(player.angle);
    const sa = Math.sin(player.angle);
    let n = 0;
    ctx.globalCompositeOperation = 'source-over';
    for (let i = 0; i < list.length; i++) {
      const p = list[i];
      if (!p || typeof p.x !== 'number' || typeof p.y !== 'number') continue;
      const dx = p.x - player.x;
      const dy = p.y - player.y;
      const d = Math.sqrt(dx * dx + dy * dy);
      if (d > rad) continue;
      const fwd = dx * ca + dy * sa;
      if (fwd <= 0.3) continue;
      const right = -dx * sa + dy * ca;
      if (Math.abs(right / fwd) > tanHalf * 1.15) continue;
      const sx = halfW + (right / fwd) * (halfW / tanHalf);
      const a = 0.10 * (1 - d / rad);
      if (a <= 0.002) continue;
      const pr = Math.min(H * 0.6, (H * 0.55) / Math.max(0.6, fwd));
      const sy = hy;
      let drew = false;
      if (typeof ctx.createRadialGradient === 'function') {
        const g = ctx.createRadialGradient(sx, sy, 0, sx, sy, pr);
        if (g && typeof g.addColorStop === 'function') {
          g.addColorStop(0, 'rgba(255,138,120,' + (a * 2.2).toFixed(3) + ')');
          g.addColorStop(1, 'rgba(255,138,120,0)');
          ctx.globalAlpha = 1;
          ctx.fillStyle = g;
          ctx.fillRect(sx - pr, sy - pr, pr * 2, pr * 2);
          drew = true;
        }
      }
      if (!drew) {
        ctx.globalAlpha = a * 1.5;
        ctx.fillStyle = '#ff8a78';
        ctx.beginPath();
        ctx.arc(sx, sy, pr * 0.6, 0, Math.PI * 2);
        ctx.fill();
      }
      n++;
    }
    ctx.globalAlpha = 1;
    return n;
  }

  /** Draw the first-person sonar view onto the main canvas. */
  const DBG_INK = '#cfe3ff';
  const DBG_SOLID = [];
  const DBG_DOT = [3, 4];
  const DBG_SEG = 48;

  function dbgRing(r, player, cx, cy, rad, halfW, tanHalf) {
    const ctx = r.octx;
    let pen = false;
    ctx.beginPath();
    for (let i = 0; i <= DBG_SEG; i++) {
      const a = (i / DBG_SEG) * TWO_PI;
      if (project(player, cx + Math.cos(a) * rad, cy + Math.sin(a) * rad, halfW, tanHalf)) {
        const y = r.horizon + 0.5 * (r.oh / proj.fwd);
        if (pen) ctx.lineTo(proj.sx, y); else ctx.moveTo(proj.sx, y);
        pen = true;
      } else {
        pen = false;
      }
    }
    ctx.stroke();
  }

  /**
   * Devtool (?debug=1 only): while a pulse has reached a light, draw its core radius (solid) and outer halo
   * (dotted, 1.8 x core) as thin dim ellipses on the first-person floor plane. Does nothing when debug is off.
   */
  function drawLightRadiiDebug(r, world, sonar, t, player, tanHalf, debug) {
    if (!debug || !world || !sonar || !player || typeof world.lightSources !== 'function') return;
    if (!(sonar.pulses && sonar.pulses.length)) return;
    const src = world.lightSources();
    const ctx = r.octx;
    const halfW = r.ow / 2;
    ctx.save();
    ctx.globalAlpha = 0.35;
    ctx.strokeStyle = DBG_INK;
    ctx.lineWidth = 1;
    for (let i = 0; i < src.length; i++) {
      const L = src[i];
      if (litAt3(sonar, L.x, L.y, 0.3, t) <= 0.01) continue;
      ctx.setLineDash(DBG_SOLID);
      dbgRing(r, player, L.x, L.y, L.radius, halfW, tanHalf);
      ctx.setLineDash(DBG_DOT);
      dbgRing(r, player, L.x, L.y, L.radius * 1.8, halfW, tanHalf);
    }
    ctx.restore();
  }

  function drawFirstPerson(r, world, player, sonar, t, opts) {
    const ctx = r.ctx;
    ctx.globalCompositeOperation = 'source-over';
    ctx.globalAlpha = 1;
    ctx.fillStyle = '#000';
    ctx.fillRect(0, 0, r.canvas.width, r.canvas.height);
    const cfg = r.config || {};
    const fovDeg = typeof cfg.fovDeg === 'number' ? cfg.fovDeg : 66;
    const fov = (opts && opts.fov) || fovDeg * Math.PI / 180;
    const tanHalf = Math.tan(fov / 2);
    const bob = opts && typeof opts.bob === 'number' && isFinite(opts.bob) ? opts.bob : 0;
    r.horizon = r.oh / 2 + bob * (r.oh / BASE_H);
    const hits = VCS.Raycast.cast(world, player.x, player.y, player.angle, fov, r.cols, MAX_DIST);

    const octx = r.octx;
    octx.setTransform(1, 0, 0, 1, 0, 0);
    octx.globalAlpha = 1;
    octx.clearRect(0, 0, r.ow, r.oh);
    r.boilOn = cfg.lineBoil !== false && !r.reduced && r.quality >= 2 && !!VCS.Ripple;
    r.bf = r.boilOn ? VCS.Ripple.boilFrame(t) : 0;
    r.frameNo = (r.frameNo | 0) + 1;
    drawWalls(r, world, hits, sonar, t);
    drawRipple(r, sonar, t, player, tanHalf);
    drawFloorFront(r, sonar, t, player, tanHalf);
    drawFootRings(r, sonar, t, player, tanHalf);
    const ripple = opts && opts.ripple;
    const people = opts && opts.people;
    const fl = opts && opts.feedLock;
    if (fl && typeof fl.id === 'number' && fl.id >= 0) {
      r.lockId = fl.id;
      r.lockK = typeof fl.k === 'number' && isFinite(fl.k) ? fl.k : 0;
      const la = typeof fl.age === 'number' ? fl.age : fl.t0age;
      r.lockAge = typeof la === 'number' && isFinite(la) ? la : 1;
    } else {
      r.lockId = -1;
    }
    drawRings(r, ripple, t, player, tanHalf);

    let drawn = 0;
    let echoes = 0;
    const anyPulse = (sonar.pulses && sonar.pulses.length) || (people && people.echoes && people.echoes.length) ||
      (ripple && ripple.rings && ripple.rings.length);
    if (anyPulse) {
      const spots = world.spots || {};
      const kinds = ['crypt', 'safe', 'doors'];
      for (let k = 0; k < kinds.length; k++) {
        const list = spots[kinds[k]] || [];
        for (let j = 0; j < list.length; j++) {
          if (drawSprite(r, world, player, sonar, t, kinds[k], list[j], tanHalf)) drawn++;
        }
      }
    }
    if (anyPulse) { try { drawn += drawProps(r, world, player, sonar, t, tanHalf); } catch (e) { logOnce(r, 'props', e); } }
    if (anyPulse) echoes = drawEchoes(r, people, sonar, t, player, tanHalf);
    if (opts && opts.debug) { try { drawLightRadiiDebug(r, world, sonar, t, player, tanHalf, true); } catch (e) { logOnce(r, 'lightdbg', e); } }
    r.echoesDrawn = echoes;
    r.sprites = drawn + echoes;
    // v0.10.5: torch and brazier flames/holders are drawn only by drawProps (ripple + afterglow).
    if (anyPulse) {
      const smooth = r.ow !== r.canvas.width;
      ctx.globalCompositeOperation = 'lighter';
      if (r.quality >= 4 && r.glow && (r.litColumns > 0 || drawn > 0 || echoes > 0)) {
        // Glow: half-res copy softened with a small blur (4x cheaper than blurring full-res).
        const gctx = r.gctx;
        gctx.globalCompositeOperation = 'copy';
        gctx.imageSmoothingEnabled = true;
        if (r.hasFilter) gctx.filter = 'blur(1.6px)';
        gctx.drawImage(r.off, 0, 0, r.glow.width, r.glow.height);
        if (r.hasFilter) gctx.filter = 'none';
        ctx.globalAlpha = 0.85;
        ctx.imageSmoothingEnabled = true;
        ctx.drawImage(r.glow, 0, 0, r.canvas.width, r.canvas.height);
      }
      ctx.imageSmoothingEnabled = smooth;
      ctx.globalAlpha = 1;
      // Main canvas is black under the offscreen layer: source-over equals additive here and is cheaper to raster.
      ctx.globalCompositeOperation = 'source-over';
      ctx.drawImage(r.off, 0, 0, r.canvas.width, r.canvas.height);
      ctx.globalCompositeOperation = 'source-over';
    }
    if (opts && opts.warm) { try { drawWarm(r, player, tanHalf, opts.warm); } catch (e) { logOnce(r, 'warm', e); } }
    drawAtmosphere(r, opts && typeof opts.lit === 'number' ? opts.lit : 0, t, world, player);
    if (opts && typeof opts.vignette === 'number' && opts.vignette > 0.001) drawFeedVignette(r, Math.min(1, opts.vignette));
    adapt(r, !!anyPulse && r.litColumns > 0);
  }

  /** Draw the top-down debug view (phase 1 look) plus pulse rings. */
  function drawTopDown(r, world, p, sonar, t, opts) {
    const ctx = r.ctx;
    const W = r.canvas.width;
    const H = r.canvas.height;
    ctx.globalCompositeOperation = 'source-over';
    ctx.globalAlpha = 1;
    ctx.fillStyle = '#000';
    ctx.fillRect(0, 0, W, H);
    const ox = W / 2 - p.x * CELL;
    const oy = H / 2 - p.y * CELL;
    const x0 = Math.max(0, Math.floor(-ox / CELL));
    const x1 = Math.min(world.width - 1, Math.floor((W - ox) / CELL));
    const y0 = Math.max(0, Math.floor(-oy / CELL));
    const y1 = Math.min(world.height - 1, Math.floor((H - oy) / CELL));

    ctx.lineWidth = 1;
    const WALLS = '#BWIw';
    const wallStyle = { '#': 'rgba(207,227,255,0.6)', B: 'rgba(230,150,125,0.8)', W: 'rgba(214,180,110,0.8)', I: 'rgba(150,175,205,0.8)', w: 'rgba(110,210,255,0.9)' };
    const wallPath = {};
    for (let cy = y0; cy <= y1; cy++) {
      for (let cx = x0; cx <= x1; cx++) {
        const ch = world.tileAt(cx, cy);
        if (WALLS.indexOf(ch) < 0) continue;
        const pth = wallPath[ch] || (wallPath[ch] = new Path2D());
        const gx = Math.round(ox + cx * CELL) + 0.5;
        const gy = Math.round(oy + cy * CELL) + 0.5;
        if (WALLS.indexOf(world.tileAt(cx, cy - 1)) < 0) { pth.moveTo(gx, gy); pth.lineTo(gx + CELL, gy); }
        if (WALLS.indexOf(world.tileAt(cx, cy + 1)) < 0) { pth.moveTo(gx, gy + CELL); pth.lineTo(gx + CELL, gy + CELL); }
        if (WALLS.indexOf(world.tileAt(cx - 1, cy)) < 0) { pth.moveTo(gx, gy); pth.lineTo(gx, gy + CELL); }
        if (WALLS.indexOf(world.tileAt(cx + 1, cy)) < 0) { pth.moveTo(gx + CELL, gy); pth.lineTo(gx + CELL, gy + CELL); }
        if (ch === 'w') { pth.moveTo(gx + 4, gy + 4); pth.lineTo(gx + CELL - 4, gy + CELL - 4); pth.moveTo(gx + CELL - 4, gy + 4); pth.lineTo(gx + 4, gy + CELL - 4); }
        else if (ch === 'I') { for (let q = 4; q < CELL; q += 4) { pth.moveTo(gx + q, gy + 2); pth.lineTo(gx + q, gy + CELL - 2); } }
      }
    }
    for (const ch in wallPath) { ctx.strokeStyle = wallStyle[ch]; ctx.stroke(wallPath[ch]); }

    // Door cells (D wood / G gate); link doors get a letter.
    ctx.font = '10px monospace';
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    for (let cy = y0; cy <= y1; cy++) {
      for (let cx = x0; cx <= x1; cx++) {
        const ch = world.tileAt(cx, cy);
        if (ch !== 'D' && ch !== 'G') continue;
        const gx = Math.round(ox + cx * CELL);
        const gy = Math.round(oy + cy * CELL);
        const link = typeof world.isLinkDoor === 'function' && world.isLinkDoor(cx, cy);
        ctx.strokeStyle = ch === 'G' ? '#9fb4cc' : '#e8f2ff';
        ctx.strokeRect(gx + 3.5, gy + 3.5, CELL - 7, CELL - 7);
        if (link) {
          ctx.fillStyle = '#7fffa0';
          ctx.fillText('L', gx + CELL / 2, gy + CELL / 2 + 1);
        }
      }
    }

    // Props (dots).
    const wprops = world.props;
    if (wprops && wprops.length) {
      for (let i = 0; i < wprops.length; i++) {
        const q = wprops[i];
        const qx = ox + q.x * CELL;
        const qy = oy + q.y * CELL;
        if (qx < -10 || qy < -10 || qx > W + 10 || qy > H + 10) continue;
        ctx.fillStyle = q.type === 'torch' || q.type === 'brazier' ? '#ffaa46' : '#b8c8e0';
        ctx.beginPath();
        ctx.arc(qx, qy, q.solid === false ? 2 : 3, 0, TWO_PI);
        ctx.fill();
      }
    }

    const marks = [
      [world.spots.crypt, COL_CRYPT],
      [world.spots.safe, COL_SAFE],
      [world.spots.people, COL_PERSON],
      [world.spots.doors, COL_DOOR]
    ];
    for (let i = 0; i < marks.length; i++) {
      ctx.fillStyle = marks[i][1];
      const list = marks[i][0] || [];
      for (let j = 0; j < list.length; j++) {
        ctx.fillRect(Math.round(ox + list[j].x * CELL) - 3, Math.round(oy + list[j].y * CELL) - 3, 6, 6);
      }
    }

    const people = opts && opts.people && opts.people.people ? opts.people.people : [];
    ctx.strokeStyle = '#ff6b5b';
    ctx.fillStyle = '#ff6b5b';
    for (let i = 0; i < people.length; i++) {
      const q = people[i];
      const qx = ox + q.x * CELL;
      const qy = oy + q.y * CELL;
      ctx.beginPath();
      ctx.arc(qx, qy, 3, 0, TWO_PI);
      ctx.fill();
      ctx.beginPath();
      ctx.moveTo(qx, qy);
      ctx.lineTo(qx + Math.cos(q.angle) * 8, qy + Math.sin(q.angle) * 8);
      ctx.stroke();
    }

    const pulses = sonar && sonar.pulses ? sonar.pulses : [];
    for (let k = 0; k < pulses.length; k++) {
      const pu = pulses[k];
      const rad = VCS.Sonar.ringRadius(pu, t);
      if (rad < 0 || rad > pu.range) continue;
      ctx.globalAlpha = Math.max(0, 0.6 * (1 - rad / pu.range));
      ctx.strokeStyle = '#cfe3ff';
      ctx.beginPath();
      ctx.arc(ox + pu.x * CELL, oy + pu.y * CELL, rad * CELL, 0, TWO_PI);
      ctx.stroke();
    }
    ctx.globalAlpha = 1;

    ctx.strokeStyle = '#ffffff';
    ctx.fillStyle = '#ffffff';
    ctx.beginPath();
    ctx.arc(W / 2, H / 2, 4, 0, TWO_PI);
    ctx.fill();
    ctx.beginPath();
    ctx.moveTo(W / 2, H / 2);
    ctx.lineTo(W / 2 + Math.cos(p.angle) * 12, H / 2 + Math.sin(p.angle) * 12);
    ctx.stroke();
    r.litColumns = 0;
    r.sprites = 0;
  }

  /**
   * Transition wipe: hand-drawn ripple rings close in from the screen edge to a black centre.
   * k 0 = nothing, k 1 = fully black. Call after drawFirstPerson.
   */
  function drawWipe(r, k) {
    try {
      if (!r || !r.ctx || typeof k !== 'number' || !isFinite(k) || k <= 0) return;
      const ctx = r.ctx;
      const W = r.canvas.width;
      const H = r.canvas.height;
      ctx.globalCompositeOperation = 'source-over';
      ctx.globalAlpha = 1;
      if (k >= 1) { ctx.fillStyle = '#000'; ctx.fillRect(0, 0, W, H); return; }
      const cx = W / 2;
      const cy = H / 2;
      const maxR = Math.hypot(W, H) / 2 * 1.05;
      const base = maxR * Math.pow(1 - k, 1.25);
      const Ripple = VCS.Ripple;
      const fr = Ripple ? Ripple.boilFrame(Date.now() / 1000) : 0;
      const N = 64;
      const sc = Math.max(1, H / 360);
      // Black outside the closing ring (even-odd hole).
      ctx.fillStyle = '#000';
      ctx.beginPath();
      ctx.rect(-2, -2, W + 4, H + 4);
      for (let s = 0; s <= N; s++) {
        const th = (s / N) * TWO_PI;
        const wob = 1 + 0.035 * Math.sin(th * 6 + k * 9) + (Ripple ? Ripple.jitter(fr, s, 0) * 0.008 : 0);
        const x = cx + Math.cos(th) * base * wob;
        const y = cy + Math.sin(th) * base * wob;
        if (s === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y);
      }
      ctx.closePath();
      ctx.fill('evenodd');
      // Trailing pale rings inside the closing edge.
      ctx.lineJoin = 'round';
      ctx.lineCap = 'round';
      ctx.strokeStyle = '#cfe3ff';
      for (let ring = 0; ring < 4; ring++) {
        const R = base * (1 - 0.13 * ring) - ring * 2 * sc;
        if (R < 2) continue;
        ctx.globalAlpha = Math.min(1, (0.9 - ring * 0.2) * Math.min(1, (1 - k) * 4 + 0.25));
        ctx.lineWidth = (2.2 - ring * 0.4) * sc;
        ctx.beginPath();
        for (let s = 0; s <= N; s++) {
          const th = (s / N) * TWO_PI;
          const wob = 1 + 0.035 * Math.sin(th * (6 + ring) + k * 9 + ring) + (Ripple ? Ripple.jitter(fr, s + ring * 64, 1) * 0.008 : 0);
          const x = cx + Math.cos(th) * R * wob;
          const y = cy + Math.sin(th) * R * wob;
          if (s === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y);
        }
        ctx.stroke();
      }
      ctx.globalAlpha = 1;
    } catch (e) {
      logOnce(r, 'wipe', e);
    }
  }

  /** Draw crosshair dot and thin cooldown arc on top of the view. */
  function drawHud(r, sonar, t) {
    const ctx = r.ctx;
    const W = r.canvas.width;
    const H = r.canvas.height;
    ctx.globalCompositeOperation = 'source-over';
    ctx.fillStyle = '#ffffff';
    ctx.globalAlpha = 0.3;
    ctx.fillRect(W / 2 - 1, H / 2 - 1, 2, 2);
    const left = VCS.Sonar.cooldownLeft(sonar, t);
    if (left > 0) {
      const total = sonar.cooldown || 0.8;
      const frac = Math.min(1, left / total);
      const fade = Math.min(1, left / 0.15, (total - left) / 0.15 + 0.001);
      ctx.globalAlpha = 0.5 * Math.max(0, fade);
      ctx.strokeStyle = '#cfe3ff';
      ctx.lineWidth = 0.75;
      ctx.beginPath();
      ctx.arc(W / 2, H - 18, 6, -Math.PI / 2, -Math.PI / 2 + TWO_PI * frac);
      ctx.stroke();
    }
    ctx.globalAlpha = 1;
  }

  /** Stats from the last first-person frame. */
  function stats(r) {
    return { litColumns: r.litColumns, sprites: r.sprites, quality: r.quality, echoes: r.echoesDrawn || 0, rings: r.ringsDrawn || 0 };
  }

  const Render = {
    create: create,
    setConfig: setConfig,
    drawFirstPerson: drawFirstPerson,
    drawLightRadiiDebug: drawLightRadiiDebug,
    drawTopDown: drawTopDown,
    drawHud: drawHud,
    drawWipe: drawWipe,
    setGrain: setGrain,
    stats: stats,
    AFTERGLOW_K: AFTERGLOW_K,
    SWEEP: SWEEP,
    glowDur: glowDur,
    glow: glow,
    edgeGlowAlpha: edgeGlowAlpha,
    edgeZoneAlpha: edgeZoneAlpha
  };
  VCS.Render = Render;
  if (typeof module !== 'undefined' && module.exports) module.exports = Render;
})(typeof window !== 'undefined' ? window : globalThis);
