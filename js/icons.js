(function (root) {
  'use strict';
  const VCS = (root.VCS = root.VCS || {});

  // Hand-drawn wobbly line doodles: icons, tombstone, crypt menu. Unit space is -1..1, scaled by size/2.
  const COL = '#cfe8ff';
  const TAU = Math.PI * 2;
  const NAMES = ['ear', 'hourglass', 'bat', 'vial', 'drop', 'fang', 'paw', 'moon', 'heart', 'shriek', 'mist', 'still', 'eye'];

  const logged = {};
  function logOnce(key, e) {
    try {
      if (logged[key]) return;
      logged[key] = true;
      const log = VCS.Log && VCS.Log.get ? VCS.Log.get('icons') : null;
      if (log && log.warn) log.warn('icons ' + key + ' failed: ' + (e && e.message ? e.message : String(e)));
    } catch (_) { /* never throw */ }
  }

  function hash(a, b) {
    const v = Math.sin(a * 12.9898 + b * 78.233) * 43758.5453;
    return v - Math.floor(v);
  }
  function seedOf(name) {
    let s = 7;
    for (let i = 0; i < name.length; i++) s = (s * 31 + name.charCodeAt(i)) % 9973;
    return s;
  }
  function fin(v, def) { return typeof v === 'number' && isFinite(v) ? v : def; }

  /** Arc points: centre, radius (rx, ry), angle range. */
  function arc(cx, cy, rx, ry, a0, a1, n) {
    const out = [];
    for (let i = 0; i <= n; i++) {
      const a = a0 + (a1 - a0) * i / n;
      out.push([cx + Math.cos(a) * rx, cy + Math.sin(a) * ry]);
    }
    return out;
  }

  // Each icon: list of strokes; stroke = array of [x,y] points (smoothed through midpoints).
  const SHAPES = {
    ear: [
      arc(0, -0.15, 0.6, 0.75, Math.PI * 0.85, Math.PI * 2.15, 10).concat([[0.5, 0.35], [0.35, 0.55], [0.15, 0.7], [-0.05, 0.9]]),
      [[-0.3, 0.2], [-0.25, -0.1], [-0.05, -0.3], [0.2, -0.2], [0.25, 0.05], [0.05, 0.25], [0.0, 0.5]],
      [[-0.1, -0.05], [0.05, -0.1]]
    ],
    hourglass: [
      [[-0.6, -0.85], [0.6, -0.85]], [[-0.6, 0.85], [0.6, 0.85]],
      [[-0.5, -0.85], [-0.45, -0.4], [-0.08, -0.04], [-0.45, 0.4], [-0.5, 0.85]],
      [[0.5, -0.85], [0.45, -0.4], [0.08, -0.04], [0.45, 0.4], [0.5, 0.85]],
      [[-0.3, 0.8], [-0.1, 0.55], [0.1, 0.55], [0.3, 0.8]],
      [[0, -0.2], [0, 0.4]]
    ],
    bat: [
      [[0, -0.35], [0.1, -0.5], [0.18, -0.3], [0.3, -0.35], [0.55, -0.6], [0.95, -0.45], [0.85, -0.1], [0.6, 0.0], [0.5, 0.35],
        [0.3, 0.12], [0.15, 0.2], [0.1, 0.45], [0, 0.55], [-0.1, 0.45], [-0.15, 0.2], [-0.3, 0.12], [-0.5, 0.35], [-0.6, 0.0],
        [-0.85, -0.1], [-0.95, -0.45], [-0.55, -0.6], [-0.3, -0.35], [-0.18, -0.3], [-0.1, -0.5], [0, -0.35]],
      [[-0.06, -0.2], [-0.04, -0.15]], [[0.06, -0.2], [0.04, -0.15]]
    ],
    vial: [
      [[-0.3, -0.85], [0.3, -0.85]],
      [[-0.2, -0.85], [-0.2, -0.55], [-0.4, -0.45], [-0.4, 0.55]].concat(arc(0, 0.55, 0.4, 0.35, Math.PI, 0, 6)),
      [[0.2, -0.85], [0.2, -0.55], [0.4, -0.45], [0.4, 0.55]],
      [[-0.4, 0.05], [-0.15, 0.0], [0.1, 0.08], [0.4, 0.02]],
      [[-0.2, 0.3], [-0.2, 0.5]]
    ],
    drop: [
      [[0, -0.9], [0.2, -0.5], [0.5, -0.1], [0.58, 0.25]].concat(arc(0, 0.28, 0.58, 0.6, 0, Math.PI, 8), [[-0.5, -0.1], [-0.2, -0.5], [0, -0.9]]),
      [[-0.25, 0.2], [-0.2, 0.45]]
    ],
    fang: [
      [[-0.6, -0.75], [0.6, -0.75]],
      [[-0.45, -0.75], [-0.4, -0.2], [-0.25, 0.4], [-0.12, 0.9], [0.02, 0.35], [0.1, -0.2], [0.12, -0.75]],
      [[0.2, -0.75], [0.35, -0.2], [0.5, 0.15], [0.55, -0.2], [0.55, -0.75]],
      [[-0.28, -0.35], [-0.22, 0.0]]
    ],
    paw: [
      [[0, 0.0], [0.25, 0.2], [0.4, 0.45], [0.2, 0.75], [0, 0.65], [-0.2, 0.75], [-0.4, 0.45], [-0.25, 0.2], [0, 0.0]],
      arc(-0.55, -0.15, 0.17, 0.22, 0, TAU, 8),
      arc(-0.22, -0.55, 0.17, 0.24, 0, TAU, 8),
      arc(0.22, -0.55, 0.17, 0.24, 0, TAU, 8),
      arc(0.55, -0.15, 0.17, 0.22, 0, TAU, 8)
    ],
    moon: [
      arc(0, 0, 0.8, 0.8, -Math.PI * 0.3, Math.PI * 1.3, 14).concat(arc(0.2, 0, 0.6, 0.68, Math.PI * 1.1, -Math.PI * 0.1, 10)),
      [[0.45, -0.7], [0.5, -0.55]], [[0.7, -0.5], [0.55, -0.5]]
    ],
    heart: [
      [[0, 0.8], [-0.4, 0.4], [-0.8, 0.0], [-0.85, -0.4], [-0.6, -0.65], [-0.3, -0.6], [0, -0.3],
        [0.3, -0.6], [0.6, -0.65], [0.85, -0.4], [0.8, 0.0], [0.4, 0.4], [0, 0.8]],
      [[-0.55, -0.3], [-0.4, -0.45]]
    ],
    shriek: [
      arc(-0.35, 0.05, 0.4, 0.55, 0, TAU, 10),
      [[-0.6, -0.3], [-0.45, -0.1], [-0.2, -0.3]],
      arc(0.05, 0, 0.35, 0.35, -Math.PI * 0.35, Math.PI * 0.35, 4),
      arc(0.05, 0, 0.62, 0.62, -Math.PI * 0.35, Math.PI * 0.35, 5),
      arc(0.05, 0, 0.9, 0.9, -Math.PI * 0.35, Math.PI * 0.35, 6)
    ],
    mist: [
      [[-0.85, -0.5], [-0.5, -0.65], [-0.15, -0.35], [0.2, -0.6], [0.55, -0.4], [0.85, -0.55]],
      [[-0.85, 0.0], [-0.5, -0.15], [-0.15, 0.15], [0.2, -0.1], [0.55, 0.1], [0.85, -0.05]],
      [[-0.85, 0.5], [-0.5, 0.35], [-0.15, 0.65], [0.2, 0.4], [0.55, 0.6], [0.85, 0.45]]
    ],
    still: [
      [[-0.85, 0.0], [-0.45, 0.35], [0, 0.45], [0.45, 0.35], [0.85, 0.0]],
      [[-0.65, 0.3], [-0.75, 0.6]], [[-0.3, 0.42], [-0.35, 0.78]], [[0.1, 0.46], [0.1, 0.82]],
      [[0.45, 0.36], [0.55, 0.7]], [[0.7, 0.2], [0.85, 0.45]]
    ],
    eye: [
      [[-0.9, 0.0], [-0.45, -0.4], [0, -0.5], [0.45, -0.4], [0.9, 0.0], [0.45, 0.4], [0, 0.5], [-0.45, 0.4], [-0.9, 0.0]],
      arc(0, 0, 0.3, 0.3, 0, TAU, 8),
      [[-0.02, 0.0], [0.02, 0.0]]
    ]
  };
  /** Stroke a smooth wobbly path through pts. j = jitter amplitude in unit space. */
  function strokePts(ctx, pts, s, ox, oy, seed, fr, j, si) {
    const n = pts.length;
    if (n < 2) return;
    const px = function (i) { return ox + (pts[i][0] + (hash(seed + si * 31 + i, fr) - 0.5) * j) * s; };
    const py = function (i) { return oy + (pts[i][1] + (hash(seed + si * 31 + i + 500, fr) - 0.5) * j) * s; };
    ctx.beginPath();
    ctx.moveTo(px(0), py(0));
    if (n === 2) ctx.lineTo(px(1), py(1));
    else {
      for (let i = 1; i < n - 1; i++) {
        ctx.quadraticCurveTo(px(i), py(i), (px(i) + px(i + 1)) / 2, (py(i) + py(i + 1)) / 2);
      }
      ctx.lineTo(px(n - 1), py(n - 1));
    }
    ctx.stroke();
  }

  function setLine(ctx, color, lw, alpha) {
    ctx.strokeStyle = color;
    ctx.lineWidth = lw;
    ctx.lineCap = 'round';
    ctx.lineJoin = 'round';
    ctx.globalAlpha = alpha;
  }

  /** Draw icon centred on the current origin, `size` px square. Returns true; unknown name draws "?" and returns false. */
  function draw(ctx, name, size, t, opts) {
    try {
      if (!ctx || typeof ctx.beginPath !== 'function') return false;
      opts = opts || {};
      const sz = fin(size, 48) > 0 ? fin(size, 48) : 48;
      const color = opts.color || COL;
      const fr = opts.still ? 0 : Math.floor(fin(t, 0) / 0.34);
      const known = Object.prototype.hasOwnProperty.call(SHAPES, name);
      const s = sz / 2 * 0.92;
      ctx.save();
      setLine(ctx, color, 1.5, fin(opts.alpha, 1));
      const jit = sz < 32 ? 0.05 : 0.07;
      if (!known) {
        const seed = seedOf(String(name));
        strokePts(ctx, arc(0, 0, 0.8, 0.8, 0, TAU, 12), s, 0, 0, seed, fr, jit, 0);
        strokePts(ctx, [[-0.25, -0.25], [-0.2, -0.5], [0, -0.55], [0.22, -0.45], [0.2, -0.2], [0, 0.0], [0, 0.2]], s, 0, 0, seed, fr, jit, 1);
        strokePts(ctx, [[0, 0.4], [0, 0.42]], s, 0, 0, seed, fr, jit, 2);
        ctx.restore();
        return false;
      }
      const seed = seedOf(name);
      const sh = SHAPES[name];
      for (let i = 0; i < sh.length; i++) strokePts(ctx, sh[i], s, 0, 0, seed, fr, jit, i);
      ctx.restore();
      return true;
    } catch (e) {
      logOnce('draw', e);
      return false;
    }
  }

  /** Wobbly line from a to b with a few segments. */
  function wline(ctx, x0, y0, x1, y1, seed, fr, amp) {
    const n = Math.max(2, Math.min(8, Math.ceil(Math.hypot(x1 - x0, y1 - y0) / 40)));
    ctx.beginPath();
    ctx.moveTo(x0, y0);
    for (let i = 1; i <= n; i++) {
      const k = i / n;
      const w = i === n ? 0 : (hash(seed + i, fr) - 0.5) * amp;
      ctx.lineTo(x0 + (x1 - x0) * k + w, y0 + (y1 - y0) * k + w * 0.7);
    }
    ctx.stroke();
  }

  /** Outline tombstone with rounded top, ground line and cracks, fitted in w x h from the origin. */
  function drawTombstone(ctx, w, h, t) {
    try {
      if (!ctx || typeof ctx.beginPath !== 'function') return false;
      w = fin(w, 200); h = fin(h, 260);
      const fr = Math.floor(fin(t, 0) / 0.34);
      ctx.save();
      setLine(ctx, COL, 1.5, 0.9);
      const gy = h * 0.9;
      const bw = w * 0.5;
      const cx = w / 2;
      const top = h * 0.12;
      const r = bw / 2;
      const pts = [[cx - bw / 2, gy], [cx - bw / 2, top + r]]
        .concat(arc(cx, top + r, r, r, Math.PI, TAU, 10))
        .concat([[cx + bw / 2, gy]]);
      strokePts(ctx, pts, 1, 0, 0, 3, fr, 3, 1);
      wline(ctx, w * 0.08, gy, w * 0.92, gy, 11, fr, 2.5);
      wline(ctx, w * 0.3, gy + 8, w * 0.5, gy + 8, 17, fr, 2);
      wline(ctx, w * 0.58, gy + 14, w * 0.78, gy + 14, 19, fr, 2);
      // cross
      wline(ctx, cx, top + r * 0.9, cx, top + r * 0.9 + h * 0.2, 23, fr, 1.5);
      wline(ctx, cx - w * 0.07, top + r * 0.9 + h * 0.06, cx + w * 0.07, top + r * 0.9 + h * 0.06, 29, fr, 1.5);
      // cracks
      strokePts(ctx, [[cx + bw * 0.2, gy - h * 0.35], [cx + bw * 0.12, gy - h * 0.28], [cx + bw * 0.22, gy - h * 0.2], [cx + bw * 0.1, gy - h * 0.1]], 1, 0, 0, 5, fr, 3, 2);
      strokePts(ctx, [[cx - bw * 0.35, gy - h * 0.12], [cx - bw * 0.25, gy - h * 0.06], [cx - bw * 0.3, gy]], 1, 0, 0, 6, fr, 3, 3);
      ctx.restore();
      return true;
    } catch (e) {
      logOnce('tombstone', e);
      return false;
    }
  }

  // Crypt layout in unit coords (x 0..1 of w, y 0..1 of h): [x0,y0,x1,y1] segments revealed by the sweep.
  const CRYPT = (function () {
    const L = [];
    // coffin (hexagonal lid outline), centre
    const c = [[0.42, 0.42], [0.46, 0.36], [0.54, 0.36], [0.58, 0.42], [0.55, 0.66], [0.45, 0.66], [0.42, 0.42]];
    for (let i = 0; i < c.length - 1; i++) L.push([c[i][0], c[i][1], c[i + 1][0], c[i + 1][1]]);
    L.push([0.5, 0.42, 0.5, 0.52], [0.47, 0.46, 0.53, 0.46]);
    // shelves both sides: 3 shelves each with a few posts
    for (let side = 0; side < 2; side++) {
      const x0 = side ? 0.74 : 0.06;
      const x1 = side ? 0.94 : 0.26;
      for (let k = 0; k < 4; k++) {
        const y = 0.24 + k * 0.17;
        L.push([x0, y, x1, y]);
        for (let p = 0; p < 4; p++) {
          const px = x0 + (x1 - x0) * (p + 0.5) / 4;
          L.push([px, y, px + 0.015, y - 0.07]);
        }
      }
      L.push([x0, 0.17, x0, 0.8], [x1, 0.17, x1, 0.8]);
    }
    // floor and ceiling lines, arch
    L.push([0.03, 0.82, 0.97, 0.82], [0.03, 0.14, 0.97, 0.14], [0.3, 0.82, 0.36, 0.7], [0.7, 0.82, 0.64, 0.7]);
    return L;
  })();
  const CANDLES = [[0.3, 0.5, 0], [0.7, 0.5, 1.3], [0.5, 0.26, 2.6]];
  const CRYPT_SEG = 12;

  /** Full-canvas black crypt: shapes revealed near a sweeping ring, candles as soft rings. */
  function drawCryptMenu(ctx, w, h, t) {
    try {
      if (!ctx || typeof ctx.beginPath !== 'function') return false;
      w = fin(w, 640); h = fin(h, 360); t = fin(t, 0);
      const fr = Math.floor(t / 0.34);
      ctx.save();
      ctx.globalAlpha = 1;
      ctx.fillStyle = '#000';
      ctx.fillRect(0, 0, w, h);
      ctx.lineCap = 'round';
      ctx.lineWidth = 1.5;
      ctx.strokeStyle = COL;
      const cx = w / 2;
      const cy = h * 0.55;
      const maxR = Math.hypot(w, h) * 0.55;
      const ph = (t % 4) / 4;
      const ringR = ph * maxR;
      const ringA = Math.sin(ph * Math.PI) * 0.35;
      const band = maxR * 0.14;
      // sweep ring
      if (ringA > 0.01) {
        ctx.globalAlpha = ringA;
        ctx.beginPath();
        ctx.ellipse(cx, cy, ringR, ringR * 0.8, 0, 0, TAU);
        ctx.stroke();
      }
      // shapes: alpha by ring proximity, bucketed to 5 levels so batches share a path
      const buckets = [[], [], [], [], []];
      for (let i = 0; i < CRYPT.length; i++) {
        const s = CRYPT[i];
        const mx = (s[0] + s[2]) / 2 * w;
        const my = (s[1] + s[3]) / 2 * h;
        const d = Math.hypot(mx - cx, (my - cy) / 0.8);
        const prox = 1 - Math.min(1, Math.abs(d - ringR) / band);
        const a = prox * prox * 0.9 + 0.025;
        const b = Math.min(4, Math.floor(a * 5));
        buckets[b].push(i);
      }
      for (let b = 0; b < 5; b++) {
        const list = buckets[b];
        if (!list.length) continue;
        ctx.globalAlpha = (b + 0.5) / 5 * 0.9;
        ctx.beginPath();
        for (let k = 0; k < list.length; k++) {
          const s = CRYPT[list[k]];
          const x0 = s[0] * w + (hash(list[k], fr) - 0.5) * 2;
          const y0 = s[1] * h + (hash(list[k] + 99, fr) - 0.5) * 2;
          ctx.moveTo(x0, y0);
          ctx.lineTo(s[2] * w + (hash(list[k] + 7, fr) - 0.5) * 2, s[3] * h + (hash(list[k] + 55, fr) - 0.5) * 2);
        }
        ctx.stroke();
      }
      // candles: slow soft expanding rings
      const baseR = Math.min(w, h) * 0.09;
      for (let i = 0; i < CANDLES.length; i++) {
        const c = CANDLES[i];
        const x = c[0] * w;
        const y = c[1] * h;
        for (let k = 0; k < 2; k++) {
          const p = (((t + c[2]) / 3.2 + k * 0.5) % 1);
          ctx.globalAlpha = (1 - p) * 0.28;
          ctx.beginPath();
          ctx.arc(x, y, 2 + p * baseR, 0, TAU);
          ctx.stroke();
        }
      }
      ctx.restore();
      return true;
    } catch (e) {
      logOnce('crypt', e);
      return false;
    }
  }

  const api = { NAMES: NAMES, draw: draw, drawTombstone: drawTombstone, drawCryptMenu: drawCryptMenu, COLOR: COL };
  VCS.Icons = api;
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
})(typeof window !== 'undefined' ? window : globalThis);
