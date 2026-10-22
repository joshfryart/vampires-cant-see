'use strict';
/**
 * PostFx (v0.16): bloom and colour grade drawn over the first-person frame, plus the grain and vignette levels.
 * Everything is gated on the effects level `fx` (0 = exactly the v0.15 output). Static: nothing here pulses or flashes,
 * so reduced motion needs no special case. Composite operations are guarded: set, read back, and skip the pass when the
 * canvas did not take the value. Public functions never throw.
 */
(function (root) {
  const VCS = root.VCS = root.VCS || {};
  const NOOP = { info() {}, warn() {}, error() {}, debug() {} };
  let logger = null;
  let logged = 0;
  function log() {
    if (logger) return logger;
    try { logger = VCS.Log && VCS.Log.get ? VCS.Log.get('postfx') : NOOP; } catch (e) { logger = NOOP; }
    return logger || NOOP;
  }
  function fail(where, e) {
    if (logged++ < 3) { try { log().warn('PostFx.' + where + ' failed: ' + (e && e.message)); } catch (e2) { /* ignore */ } }
  }

  const GRAIN_BASE = 0.04; // same value as render.js
  const GRAIN = [GRAIN_BASE, 0.035, 0.05];
  const VIGNETTE = [null, 0.7, 1];
  const BLOOM_ALPHA_Q4 = 0.85;
  const BLOOM_ALPHA_FX2 = 0.55;
  const DUSK_A = 0.10;
  const DAWN_A = 0.12;
  const DAWN_SAT_A = 0.25;
  const DUSK_RGB = 'rgb(150,140,200)';
  const DAWN_RGB = 'rgb(255,205,185)';
  const GREY_RGB = 'rgb(128,128,128)';

  function num(v, d) { return typeof v === 'number' && isFinite(v) ? v : d; }
  function clamp(v, a, b) { return v < a ? a : v > b ? b : v; }
  function fxLevel(fx) { return clamp(Math.floor(num(fx, 0)), 0, 2); }
  function hasDraw(c) { return !!c && typeof c.drawImage === 'function'; }

  // Set a composite operation and confirm the canvas took it. Reading is not a ctx call.
  function setOp(ctx, op) {
    try {
      if (ctx.globalCompositeOperation !== op) ctx.globalCompositeOperation = op;
      return ctx.globalCompositeOperation === op;
    } catch (e) { return false; }
  }

  /**
   * Bloom: soft additive copy of the offscreen frame. Returns true when drawn.
   * fx 2 and quality >= 3: half-res blurred copy at alpha 0.55 (needs r.hasFilter). Quality 4: alpha 0.85, as before v0.16
   * (so fx 0 and 1 keep today's behaviour). The caller decides whether anything is lit; r.glow/r.gctx are the half-res buffers.
   */
  function bloom(r, ctx, fx) {
    try {
      if (!r || !hasDraw(ctx) || !r.glow || !r.gctx || !r.off) return false;
      const f = fxLevel(fx);
      const q = num(r.quality, 0);
      let alpha;
      if (q >= 4) alpha = BLOOM_ALPHA_Q4;
      else if (f >= 2 && q >= 3 && r.hasFilter) alpha = BLOOM_ALPHA_FX2;
      else return false;
      if (!setOp(ctx, 'lighter')) return false;
      const gctx = r.gctx;
      gctx.globalCompositeOperation = 'copy';
      gctx.imageSmoothingEnabled = true;
      if (r.hasFilter) gctx.filter = 'blur(1.6px)';
      gctx.drawImage(r.off, 0, 0, r.glow.width, r.glow.height);
      if (r.hasFilter) gctx.filter = 'none';
      ctx.globalAlpha = alpha;
      ctx.imageSmoothingEnabled = true;
      ctx.drawImage(r.glow, 0, 0, r.canvas.width, r.canvas.height);
      return true;
    } catch (e) { fail('bloom', e); return false; }
  }

  /**
   * Colour grade over the finished frame. g = {dusk: 0..1, dawn: 0..1}. fx 0: no-op (zero ctx calls).
   * Dusk: multiply rgb(150,140,200) at 0.10*dusk. Dawn: multiply rgb(255,205,185) at 0.12*dawn, then saturation grey at
   * 0.25*dawn. Restores source-over and alpha 1. Returns true when anything was drawn.
   */
  function grade(r, ctx, g, fx) {
    try {
      if (fxLevel(fx) < 1) return false;
      if (!r || !r.canvas || !ctx || typeof ctx.fillRect !== 'function') return false;
      const w = num(r.canvas.width, 0);
      const h = num(r.canvas.height, 0);
      if (w <= 0 || h <= 0) return false;
      const dusk = clamp(num(g && g.dusk, 0), 0, 1);
      const dawn = clamp(num(g && g.dawn, 0), 0, 1);
      if (dusk <= 0 && dawn <= 0) return false;
      let drew = false;
      if (dusk > 0 && setOp(ctx, 'multiply')) {
        ctx.globalAlpha = DUSK_A * dusk;
        ctx.fillStyle = DUSK_RGB;
        ctx.fillRect(0, 0, w, h);
        drew = true;
      }
      if (dawn > 0 && setOp(ctx, 'multiply')) {
        ctx.globalAlpha = DAWN_A * dawn;
        ctx.fillStyle = DAWN_RGB;
        ctx.fillRect(0, 0, w, h);
        drew = true;
        if (setOp(ctx, 'saturation')) {
          ctx.globalAlpha = DAWN_SAT_A * dawn;
          ctx.fillStyle = GREY_RGB;
          ctx.fillRect(0, 0, w, h);
        }
      }
      if (drew) {
        setOp(ctx, 'source-over');
        ctx.globalAlpha = 1;
      }
      return drew;
    } catch (e) {
      fail('grade', e);
      try { ctx.globalCompositeOperation = 'source-over'; ctx.globalAlpha = 1; } catch (e2) { /* ignore */ }
      return false;
    }
  }

  /** Grain opacity base for the effects level: 0 gives GRAIN_BASE, 1 gives 0.035, 2 gives 0.05. */
  function grainLevel(fx) { return GRAIN[fxLevel(fx)]; }

  /** Vignette opacity for the effects level: 0 gives null (unchanged), 1 gives 0.7, 2 gives 1. */
  function vignetteOpacity(fx) { return VIGNETTE[fxLevel(fx)]; }

  const PostFx = { bloom, grade, grainLevel, vignetteOpacity, GRAIN_BASE };
  VCS.PostFx = PostFx;
  if (typeof module !== 'undefined' && module.exports) module.exports = PostFx;
})(typeof window !== 'undefined' ? window : globalThis);
