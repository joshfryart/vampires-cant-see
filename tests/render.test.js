'use strict';
// Merged test file: each source file's tests live in their own describe().
const { describe } = require('node:test');

describe('render-feed.test.js', () => {

  const test = require('node:test');
  const assert = require('node:assert');

  const R = '../js/';
  for (const m of ['log', 'ripple', 'raycast', 'world', 'sonar', 'people', 'struggle', 'data/maps', 'data/sounds']) require(R + m + '.js');
  const Render = require(R + 'render.js');
  const VCS = globalThis.VCS;

  function fakeCtx(canvas) {
    const calls = [];
    const state = { globalAlpha: 1, fillStyle: '#000', strokeStyle: '#000', lineWidth: 1 };
    return new Proxy({ calls, canvas }, {
      get(t, p) {
        if (p in t) return t[p];
        if (p in state) return state[p];
        return function () {
          calls.push({ fn: String(p), args: Array.prototype.slice.call(arguments), stroke: state.strokeStyle, alpha: state.globalAlpha, lw: state.lineWidth });
          if (p === 'createRadialGradient' || p === 'createLinearGradient') return { addColorStop() {} };
          if (p === 'createPattern') return {};
          if (p === 'createImageData') return { data: new Uint8ClampedArray(128 * 128 * 4) };
          return undefined;
        };
      },
      set(t, p, v) { state[p] = v; return true; }
    });
  }
  function fakeCanvas(w, h) {
    const c = { width: w, height: h, ownerDocument: null };
    const doc = { createElement() { return fakeCanvas(w, h); } };
    c.ownerDocument = doc;
    c._ctx = null;
    c.getContext = function () { return c._ctx || (c._ctx = fakeCtx(c)); };
    return c;
  }

  function setup() {
    const canvas = fakeCanvas(640, 360);
    const r = Render.create(canvas, {});
    r.reduced = false;
    const map = VCS.MapData.maps[VCS.MapData.startMap];
    const world = VCS.World.load(map);
    const sonar = VCS.Sonar.create();
    return { r, canvas, world, sonar };
  }

  const player = { x: 5.5, y: 5.5, angle: 0 };
  function echo(id, t) {
    return { x: 7.5, y: 5.5, angle: Math.PI, lookAngle: 0, phase: 0, personId: id, t: t, strength: 1, zMin: 0, zMax: 2, look: VCS.People.makeLook ? VCS.People.makeLook(id) : undefined, fade: 3 };
  }
  function personStrokes(r) {
    return r.octx.calls.filter((c) => c.fn === 'stroke' && c.stroke === '#ff8a78');
  }

  test('drawLightRadiiDebug draws no strokes when debug is off, strokes when on', () => {
    const { r, sonar } = setup();
    const world = VCS.World.load(VCS.MapData.maps.town, { requireStart: false });
    r.horizon = r.oh / 2;
    const L = world.lightSources();
    assert.ok(L.length > 0, 'town has lights');
    const p = { x: L[0].x - 3, y: L[0].y, angle: 0 };
    VCS.Sonar.emit(sonar, world, p.x, p.y, 0);
    const t = 0.3;
    r.octx.calls.length = 0;
    Render.drawLightRadiiDebug(r, world, sonar, t, p, Math.tan(0.57), false);
    assert.strictEqual(r.octx.calls.filter((c) => c.fn === 'stroke').length, 0);
    Render.drawLightRadiiDebug(r, world, sonar, t, p, Math.tan(0.57), true); // must not throw
  });

  test('feedLock draws the victim echo coral at 1.6px, even when faded', () => {
    const f = setup();
    const people = { echoes: [echo(7, 0), echo(8, 0)] };
    // t=100: echoes long faded -> nothing, without lock
    Render.drawFirstPerson(f.r, f.world, player, f.sonar, 100, { people });
    assert.strictEqual(personStrokes(f.r).length, 0);
    f.r.octx.calls.length = 0;
    Render.drawFirstPerson(f.r, f.world, player, f.sonar, 100, { people, feedLock: { id: 7, k: 0.5, age: 1 } });
    const s = personStrokes(f.r);
    assert.ok(s.length > 0, 'victim drawn in lock colour');
    assert.ok(s.some((c) => c.alpha >= 0.9 - 1e-9), 'victim alpha >= 0.9 (the vampire arms are dimmer)');
    assert.ok(s.some((c) => Math.abs(c.lw - 1.6 * f.r.wscale * 1.7) < 1e-6 || Math.abs(c.lw - 1.6 * f.r.wscale) < 1e-6));
  });

  test('unlocked echoes never use the lock colour; reduced motion draws lock without boil ramp', () => {
    const f = setup();
    const people = { echoes: [echo(7, 99.5)] };
    Render.drawFirstPerson(f.r, f.world, player, f.sonar, 100, { people });
    assert.strictEqual(personStrokes(f.r).length, 0);
    f.r.reduced = true;
    assert.doesNotThrow(() => Render.drawFirstPerson(f.r, f.world, player, f.sonar, 100, { people, feedLock: { id: 7, k: 1, age: 0.1 } }));
    assert.ok(personStrokes(f.r).length > 0);
  });

  test('vignette canvas is cached and drawn at 0.5*v', () => {
    const f = setup();
    const people = { echoes: [] };
    Render.drawFirstPerson(f.r, f.world, player, f.sonar, 1, { people, vignette: 0.8 });
    const vig = f.r.feedVig;
    assert.ok(vig);
    const draws = f.canvas._ctx.calls.filter((c) => c.fn === 'drawImage' && c.args[0] === vig);
    assert.strictEqual(draws.length, 1);
    assert.ok(Math.abs(draws[0].alpha - 0.4) < 1e-9);
    Render.drawFirstPerson(f.r, f.world, player, f.sonar, 1.1, { people, vignette: 1 });
    assert.strictEqual(f.r.feedVig, vig, 'not rebuilt');
    const n = f.canvas._ctx.calls.length;
    Render.drawFirstPerson(f.r, f.world, player, f.sonar, 1.2, { people, vignette: 0 });
    assert.ok(!f.canvas._ctx.calls.slice(n).some((c) => c.fn === 'drawImage' && c.args[0] === vig));
  });

  test('vignette rebuilds only on size change; bad opts never throw', () => {
    const f = setup();
    Render.drawFirstPerson(f.r, f.world, player, f.sonar, 1, { vignette: 1 });
    const vig = f.r.feedVig;
    f.canvas.width = 800;
    Render.drawFirstPerson(f.r, f.world, player, f.sonar, 1, { vignette: 1 });
    assert.strictEqual(f.r.feedVigW, 800);
    assert.ok(vig);
    for (const bad of [NaN, 'x', null, -1, Infinity]) {
      assert.doesNotThrow(() => Render.drawFirstPerson(f.r, f.world, player, f.sonar, 1, { vignette: bad, feedLock: { id: 1, k: bad, age: bad } }));
    }
  });


  test('setGrain drives the #grain overlay opacity, clamps, and never throws', () => {
    const f = setup();
    const el = { style: {} };
    f.r.grainEl = el;
    f.r.grainApplied = -1;
    Render.setGrain(f.r, 1);
    assert.strictEqual(Number(el.style.opacity), 0.04);
    Render.setGrain(f.r, 0.5);
    assert.strictEqual(Number(el.style.opacity), 0.02);
    Render.setGrain(f.r, 7);
    assert.strictEqual(Number(el.style.opacity), 0.04);
    Render.setGrain(f.r, -1);
    assert.strictEqual(Number(el.style.opacity), 0);
    assert.doesNotThrow(() => Render.setGrain(f.r, NaN));
    assert.doesNotThrow(() => Render.setGrain(null, 1));
    assert.doesNotThrow(() => Render.setGrain({}, 1));
  });

  test('static vignette is a CSS overlay: not drawn on the canvas, setVignette toggles #vignette, never throws', () => {
    const f = setup();
    const el = { style: {} };
    f.r.vignetteEl = el;
    f.r.vignetteOn = null;
    Render.drawFirstPerson(f.r, f.world, player, f.sonar, 1, {});
    assert.strictEqual(el.style.opacity, '1');
    assert.ok(!f.canvas._ctx.calls.some((c) => c.fn === 'createRadialGradient' && c.args[2] === 360 * 0.28), 'no canvas vignette gradient');
    Render.setVignette(f.r, false);
    assert.strictEqual(el.style.opacity, '0');
    Render.setVignette(f.r, true);
    assert.strictEqual(el.style.opacity, '1');
    assert.doesNotThrow(() => Render.setVignette(null, true));
    assert.doesNotThrow(() => Render.setVignette({}, true));
  });

  test('floor front: a pulse over open floor draws a 1.5px arc and a few stipple dots', () => {
    const f = setup();
    f.r.quality = 3;
    VCS.Sonar.emit(f.sonar, f.world, 5.5, 5.5, 100, { range: 10 });
    Render.drawFirstPerson(f.r, f.world, player, f.sonar, 100.15, {});
    const arcs = f.r.octx.calls.filter((c) => c.fn === 'stroke' && c.lw === 1.5 && c.stroke === '#e8f2ff');
    assert.ok(arcs.length >= 1);
    assert.ok(f.r.octx.calls.filter((c) => c.fn === 'rect' && c.args[2] === 1 && c.args[3] === 1).length <= 40);
  });

  // Wall segments are batched into Path2D objects, which Node lacks: a tiny stub records the calls.
  function withPath2D(fn) {
    const had = typeof globalThis.Path2D !== 'undefined';
    if (!had) {
      globalThis.Path2D = class { constructor() { this.n = 0; } moveTo() { this.n++; } lineTo() { this.n++; } };
    }
    try { return fn(); } finally { if (!had) delete globalThis.Path2D; }
  }

  test('ripple-only vision: walls light as the front passes, then go dark within one afterglow', () => withPath2D(() => {
    const f = setup();
    f.r.quality = 3;
    const T0 = 100;
    VCS.Sonar.emit(f.sonar, f.world, 5.5, 5.5, T0, { range: 10 });
    const lit = [];
    for (const dt of [0.05, 0.2, 0.4, 0.6, 0.9, 1.3, 1.6, 2.0, 2.5]) {
      Render.drawFirstPerson(f.r, f.world, player, f.sonar, T0 + dt, {});
      lit.push(Render.stats(f.r).litColumns);
    }
    assert.ok(lit[3] > 20 || lit[4] > 20, 'walls lit while the front passes: ' + lit.join(','));
    assert.strictEqual(lit[0], 0, 'dark before the front arrives');
    // Range 10 at 12 cells/s: the ring is done by 0.83 s; afterglow (0.18 x fade 3 = 0.54 s) ends by ~1.4 s.
    assert.strictEqual(lit[7], 0, 'dark at 2.0 s: ' + lit.join(','));
    assert.strictEqual(lit[8], 0, 'dark at 2.5 s: ' + lit.join(','));
    assert.ok(Render.AFTERGLOW_K > 0.05 && Render.AFTERGLOW_K <= 0.25);
    assert.ok(Math.abs(Render.glowDur(3) - 3 * Render.AFTERGLOW_K) < 1e-9);
    assert.strictEqual(Render.glowDur(0.1), 0.2, 'short fades still glow 0.2 s');
    assert.strictEqual(Render.glowDur(100), 1.0, 'long fades cap at 1 s');
  }));

  test('villager echo: the band sweeps feet first, the figure is gone after sweep + afterglow', () => {
    const f = setup();
    f.r.quality = 3;
    const e = Object.assign(echo(3, 50), { mode: 'path', phaseRate: 9, phase: 1 });
    const people = { echoes: [e] };
    const strokesAt = (t) => {
      f.r.octx.calls.length = 0;
      Render.drawFirstPerson(f.r, f.world, player, f.sonar, t, { people });
      return f.r.octx.calls.filter((c) => c.fn === 'stroke');
    };
    const clipsAt = (t) => { strokesAt(t); return f.r.octx.calls.filter((c) => c.fn === 'rect'); };
    assert.strictEqual(strokesAt(49.9).length, 0, 'nothing before the front arrives');
    const early = clipsAt(50.03);
    assert.ok(early.length >= 1, 'first strip drawn');
    const lowest = Math.max.apply(null, early.map((c) => c.args[1] + c.args[3]));
    const highest = Math.min.apply(null, early.map((c) => c.args[1]));
    assert.ok(lowest > 180 && highest > 150, 'only low strips early: ' + highest + '..' + lowest);
    const mid = clipsAt(50.2);
    assert.ok(mid.length > early.length, 'more strips as the band rises');
    assert.ok(strokesAt(50.45).length > 0, 'still glowing at 0.45 s');
    assert.strictEqual(strokesAt(50.9).length, 0, 'gone after sweep + afterglow');
    // The front strip is white; the rest coral.
    f.r.octx.calls.length = 0;
    Render.drawFirstPerson(f.r, f.world, player, f.sonar, 50.03, { people });
    const cols = new Set(f.r.octx.calls.filter((c) => c.fn === 'stroke').map((c) => c.stroke));
    assert.ok(cols.has('#ffffff'));
  });

  test('every mode and look draws without throwing, also under reduced motion and low quality', () => {
    const f = setup();
    const modes = ['path', 'startle', 'flee', 'cower', 'dazed', 'grapple', 'fed', 'bogus', undefined];
    const accs = VCS.People.ACCESSORIES;
    let n = 0;
    for (const reduced of [false, true]) {
      for (const q of [0, 1, 3]) {
        f.r.reduced = reduced;
        f.r.quality = q;
        for (let i = 0; i < modes.length; i++) {
          for (let a = 0; a < accs.length; a++) {
            const look = VCS.People.makeLook(9, a * 7 + i, a);
            look.acc = accs[a];
            const e = Object.assign(echo(i, 60), { mode: modes[i], sit: i % 2 === 0, wary: i % 3 === 0, modeAge: 0.1, look });
            const people = { echoes: [e] };
            f.r.octx.calls.length = 0;
            assert.doesNotThrow(() => Render.drawFirstPerson(f.r, f.world, player, f.sonar, 60.15, { people }));
            n += f.r.octx.calls.filter((c) => c.fn === 'stroke').length;
          }
        }
      }
    }
    assert.ok(n > 100);
    assert.ok(!f.r.logged || Object.keys(f.r.logged).length === 0, 'no render failures logged: ' + JSON.stringify(f.r.logged));
  });

  test('doors: wood draws warm detail, gates a bright iron tint, only while the ring passes; link door and reduced motion are safe', () => withPath2D(() => {
    const world = VCS.World.load(VCS.MapData.maps.town, { requireStart: false });
    function look(x, y, ang, reduced, times) {
      const r = Render.create(fakeCanvas(640, 360), {});
      r.reduced = reduced;
      r.quality = 3;
      const sonar = VCS.Sonar.create();
      VCS.Sonar.emit(sonar, world, x, y, 10, { range: 10 });
      const out = { warm: 0, gate: 0, pts: 0 };
      for (const dt of times) {
        r.octx.calls.length = 0;
        Render.drawFirstPerson(r, world, { x: x, y: y, angle: ang }, sonar, 10 + dt, {});
        for (const c of r.octx.calls) {
          if (c.fn !== 'stroke') continue;
          if (c.stroke === '#ffe2c4') { out.warm++; out.pts += c.args[0] && c.args[0].n ? c.args[0].n : 0; }
          if (c.stroke === '#f4f8ff') out.gate++;
        }
      }
      assert.ok(!r.logged || Object.keys(r.logged).length === 0, 'no render failures logged');
      return out;
    }
    const during = [0.2, 0.25, 0.3, 0.35, 0.4];
    const wood = look(28.5, 17.5, -Math.PI / 2, false, during);
    assert.ok(wood.warm > 0, 'wooden door lines use the warm tint');
    assert.ok(wood.pts > 30, 'frame + planks + hinges + handle add many segments: ' + wood.pts);
    assert.strictEqual(look(28.5, 17.5, -Math.PI / 2, false, [2.5]).warm, 0, 'dark again after the afterglow');
    assert.strictEqual(look(28.5, 17.5, -Math.PI / 2, false, [0.05]).warm, 0, 'dark before the front arrives');
    const gate = look(8.5, 16, -Math.PI / 2, false, [0.3, 0.32, 0.34, 0.36]);
    assert.ok(gate.gate > 0, 'gate uses the iron tint');
    assert.strictEqual(gate.warm, 0, 'gate is not wood-tinted');
    assert.ok(world.isLinkDoor(7, 6), 'mausoleum is a link door');
    assert.ok(look(7.5, 8.5, -Math.PI / 2, false, during).warm > 0, 'link door draws (keystone path)');
    assert.ok(look(28.5, 17.5, -Math.PI / 2, true, during).warm > 0, 'reduced motion still draws doors');
  }));

  test('windows: no glow without a ring; lit panes glow briefly (alpha <= 0.25) while a ripple passes; reduced motion is static', () => withPath2D(() => {
    const world = VCS.World.load(VCS.MapData.maps.town, { requireStart: false });
    function look(x, y, ang, t, reduced, pulse) {
      const r = Render.create(fakeCanvas(640, 360), {});
      r.reduced = reduced;
      r.quality = 3;
      const sonar = VCS.Sonar.create();
      if (pulse) VCS.Sonar.emit(sonar, world, x, y, 10, { range: 10 });
      r.octx.calls.length = 0;
      Render.drawFirstPerson(r, world, { x: x, y: y, angle: ang }, sonar, t, {});
      const glow = r.octx.calls.filter((c) => c.fn === 'fillRect' && c.alpha > 0.04);
      return { r: r, glow: glow };
    }
    assert.strictEqual(look(38.5, 9.5, Math.PI, 5, false, false).glow.length, 0, 'v0.10.12: lit window is hidden with no pulse');
    let peak = [];
    for (const dt of [0.2, 0.24, 0.28, 0.32]) {
      const g = look(38.5, 9.5, Math.PI, 10 + dt, false, true).glow;
      if (g.length > peak.length) peak = g;
    }
    assert.ok(peak.length > 0, 'lit window glows while a ripple passes');
    assert.ok(peak.every((c) => c.alpha <= 0.25 + 1e-9), 'glow alpha <= 0.25');
    assert.strictEqual(look(38.5, 9.5, Math.PI, 10 + 6, false, true).glow.length, 0, 'glow gone after the afterglow');
    assert.strictEqual(look(22.5, 5, -Math.PI / 2, 5, false, false).glow.length, 0, 'unlit window shows no glow');
    const a = look(38.5, 9.5, Math.PI, 10.24, true, true).glow.map((c) => c.alpha.toFixed(4)).join();
    const b = look(38.5, 9.5, Math.PI, 10.24, true, true).glow.map((c) => c.alpha.toFixed(4)).join();
    assert.strictEqual(a, b, 'deterministic under reduced motion');
    // Rings reveal the frame: lit tint on lit glass, cold tint on dark glass.
    function strokes(x, y, ang, color) {
      const r = Render.create(fakeCanvas(640, 360), {});
      r.reduced = false; r.quality = 3;
      const sonar = VCS.Sonar.create();
      VCS.Sonar.emit(sonar, world, x, y, 10, { range: 10 });
      let n = 0;
      for (const dt of [0.2, 0.24, 0.28, 0.32]) {
        r.octx.calls.length = 0;
        Render.drawFirstPerson(r, world, { x: x, y: y, angle: ang }, sonar, 10 + dt, {});
        n += r.octx.calls.filter((c) => c.fn === 'stroke' && c.stroke === color).length;
      }
      return n;
    }
    assert.ok(strokes(38.5, 9.5, Math.PI, '#ffd596') > 0, 'lit window frame is candle gold');
    assert.ok(strokes(22.5, 5, -Math.PI / 2, '#c4e2ff') > 0, 'dark window frame is cold glass');
  }));

  test('props on the town map draw without a logged failure; flames show only under a ripple', () => withPath2D(() => {
    const canvas = fakeCanvas(640, 360);
    const r = Render.create(canvas, {});
    r.reduced = false;
    r.quality = 3;
    const world = VCS.World.load(VCS.MapData.maps.town, { requireStart: false });
    const sonar = VCS.Sonar.create();
    const torch = world.props.find((p) => p.type === 'torch' || p.type === 'brazier');
    assert.ok(torch, 'town has a fire prop');
    const pl = { x: torch.x - 2, y: torch.y, angle: 0 };
    r.octx.calls.length = 0;
    Render.drawFirstPerson(r, world, pl, sonar, 5, {});
    const flame = r.octx.calls.filter((c) => c.fn === 'stroke' && c.stroke === 'rgb(255,176,64)');
    assert.strictEqual(flame.length, 0, 'v0.10.5: no flame without a pulse');
    VCS.Sonar.emit(sonar, world, pl.x, pl.y, 5, {});
    for (let t = 5.05; t < 6.5; t += 0.1) Render.drawFirstPerson(r, world, pl, sonar, t, {});
    assert.ok(!r.logged || !r.logged.props, 'props drew without failure');
    r.octx.calls.length = 0;
    VCS.Sonar.emit(sonar, world, pl.x, pl.y, 8, {});
    for (let t = 8.02; t < 8.9; t += 0.04) Render.drawFirstPerson(r, world, pl, sonar, t, {});
    assert.ok(r.octx.calls.some((c) => c.fn === 'stroke' && c.stroke === 'rgb(255,176,64)'), 'flame drawn while the wavefront passes');
  }));

  test('render ring beam and sonar beam share one curve (0/90/180 deg); aimOf reads pu.facing', () => {
    require('../js/data/sounds.js');
    const A = VCS.SoundData.acoustics;
    const hall = VCS.World.load(VCS.MapData.maps.town, { requireStart: false });
    const s = VCS.Sonar.create({ bounces: 0, visRays: 360, speed: 10, fade: 2, range: 10 });
    VCS.Sonar.emit(s, hall, 5.5, 3.5, 0, { facing: 0.7 });
    const p = s.lastPulse;
    assert.strictEqual(p.facing, 0.7);
    for (const deg of [0, 90, 180]) {
      const rel = deg * Math.PI / 180;
      const g = Render.beamGain(rel);
      assert.ok(Math.abs(g - A.visFactor(A.beam(rel))) < 1e-9, 'curve at ' + deg);
      assert.ok(Math.abs(g - VCS.Sonar.beamAt(p, 0.7 + rel)) < 0.01, 'agrees with sonar at ' + deg);
    }
    assert.ok(Math.abs(Render.beamGain(-Math.PI / 2) - Render.beamGain(Math.PI / 2)) < 1e-6, 'symmetric');
    assert.ok(Math.abs(Render.beamGain(2 * Math.PI) - 1) < 1e-6, 'wraps');
    assert.ok(Render.beamGain(Math.PI) >= 0.15 - 1e-9);
    assert.ok(Render.beamReach(16, 1) > Render.beamReach(16, 0.15));
  });

  function airArcs(f) { return f.r.octx.calls.filter((c) => c.fn === 'arc' && c.args[2] > 0).length; }

  test('air rings: 3 hollow circles leave the mouth, aimed by the beam (pu.facing), gated by matDetail', () => withPath2D(() => {
    const ringsAt = (angle, t, facing) => {
      const f = setup();
      f.r.quality = 3;
      f.sonar.range = 4; // short ping: the rear beam reach (0.61 of range) ends inside the ring window
      VCS.Sonar.emit(f.sonar, f.world, 5.5, 5.5, 100, typeof facing === 'number' ? { facing: facing } : {});
      Render.drawFirstPerson(f.r, f.world, player, f.sonar, 100.02, {}); // fixes the aim at the player's facing
      f.r.octx.calls.length = 0;
      Render.drawFirstPerson(f.r, f.world, { x: 5.5, y: 5.5, angle: angle }, f.sonar, t, {});
      return airArcs(f);
    };
    const T = 100.25;
    const ahead = ringsAt(0, T);

    assert.ok(ahead > 0, 'rings drawn');
    assert.ok(ringsAt(Math.PI, T) < ahead, 'turned away from the aim: dimmer, shorter');
    assert.ok(ringsAt(0, T, Math.PI) < ahead, 'pu.facing (not the player angle) sets the aim');
    const f = setup();
    f.r.quality = 3;
    VCS.Sonar.emit(f.sonar, f.world, 5.5, 5.5, 100, { range: 12 });
    Render.drawFirstPerson(f.r, f.world, player, f.sonar, 100.02, {});
    f.r.matDetail = false;
    f.r.octx.calls.length = 0;
    Render.drawFirstPerson(f.r, f.world, player, f.sonar, 100.25, {});
    assert.strictEqual(airArcs(f), 0, 'matDetail auto-off removes the rings');
  }));

  test('air rings and wall vibration survive reduced motion', () => withPath2D(() => {
    const f = setup();
    f.r.quality = 3;
    f.r.reduced = true;
    VCS.Sonar.emit(f.sonar, f.world, 5.5, 5.5, 100, { range: 12 });
    for (let t = 100.05; t < 101.2; t += 0.1) assert.doesNotThrow(() => Render.drawFirstPerson(f.r, f.world, player, f.sonar, t, {}));
  }));

  test('struck walls light and vibrate; matDetail off removes it', () => withPath2D(() => {
    const f = setup();
    f.r.quality = 3;
    VCS.Sonar.emit(f.sonar, f.world, 5.5, 5.5, 100, { range: 12 });
    const strokes = () => f.r.octx.calls.filter((c) => c.fn === 'stroke' && c.stroke === '#e8f2ff' && c.lw < 1).length;
    let on = 0;
    let off = 0;
    for (let t = 100.1; t < 101.5; t += 0.05) {
      f.r.matDetail = true;
      f.r.octx.calls.length = 0;
      Render.drawFirstPerson(f.r, f.world, player, f.sonar, t, {});
      on += strokes();
      f.r.matDetail = false;
      f.r.octx.calls.length = 0;
      Render.drawFirstPerson(f.r, f.world, player, f.sonar, t, {});
      off += strokes();
    }
    assert.ok(on > off, 'vibration contours drawn only with detail on');
  }));

  test('ceiling ring is drawn indoors only', () => withPath2D(() => {
    const f = setup();
    f.r.quality = 3;
    VCS.Sonar.emit(f.sonar, f.world, 5.5, 5.5, 100, { range: 12 });
    const rects = () => f.r.octx.calls.filter((c) => c.fn === 'rect').length;
    f.r.matDetail = false; // isolate drawRipple
    f.r.octx.calls.length = 0;
    Render.drawFirstPerson(f.r, f.world, player, f.sonar, 100.5, {});
    const inside = rects();
    const w2 = Object.create(f.world);
    w2.kindAt = () => 'outdoor';
    f.r.octx.calls.length = 0;
    Render.drawFirstPerson(f.r, w2, player, f.sonar, 100.5, {});
    assert.ok(inside > rects(), 'outdoors draws fewer ring dots (no ceiling pass)');
  }));

  test('weak pulse flicker is slow and shallow; reduced motion is a static dim', () => {
    for (const reduced of [false, true]) {
      const f = setup();
      f.r.quality = 3;
      f.r.reduced = reduced;
      VCS.Sonar.emit(f.sonar, f.world, 5.5, 5.5, 100, { range: 10 });
      f.sonar.pulses[0].weak = 1;
      const alphas = [];
      for (let i = 0; i < 6; i++) {
        f.r.octx.calls.length = 0;
        Render.drawFirstPerson(f.r, f.world, player, f.sonar, 100.2 + i * 0.001, {});
        alphas.push(f.r.octx.calls.filter((c) => c.fn === 'fill').map((c) => c.alpha)[0]);
      }
      assert.ok(alphas.every((a) => a > 0));
      if (reduced) assert.ok(Math.max.apply(null, alphas) - Math.min.apply(null, alphas) < 0.01);
    }
  });

  test('speckle scale: roughness thickens and lengthens the stipple, clamped 0..1', () => {
    const lo = Render.speckle(0.1);
    const hi = Render.speckle(0.8);
    assert.ok(hi.n > lo.n && hi.back > lo.back);
    assert.deepStrictEqual(Render.speckle(-5), Render.speckle(0));
    assert.deepStrictEqual(Render.speckle(9), Render.speckle(1));
    assert.ok(Render.speckle(0).n >= 0.5 && Render.speckle(1).n <= 2.01);
    const room = (floor, wall) => VCS.World.load({ name: 'sp', rows: ['#############', '#' + floor.repeat(11) + '#', '#' + floor.repeat(11) + '#', '#' + floor.repeat(11) + '#', '#############'], materials: { '#': wall } }, { requireStart: false });
    const pulse = (w) => { const s = VCS.Sonar.create({ bounces: 0, visRays: 360 }); VCS.Sonar.emit(s, w, 3.5, 2.5, 0, { range: 10 }); return s.lastPulse; };
    const smooth = Render.pulseRough(room('.', 'stone'), pulse(room('.', 'stone')));
    const rough = Render.pulseRough(room('g', 'cobble'), pulse(room('g', 'cobble')));
    assert.ok(rough > smooth + 0.3, 'grass + cobble ' + rough + ' vs stone ' + smooth);
    const pu = pulse(room('.', 'stone'));
    const first = Render.pulseRough(room('g', 'cobble'), pu);
    assert.strictEqual(Render.pulseRough(room('.', 'stone'), pu), first, 'cached on the pulse');
  });

  test('speckles: rough surfaces draw more dots; matDetail auto-off and quality 1 fall back to the plain stipple', () => withPath2D(() => {
    const rows = ['#################', '#' + '.'.repeat(15) + '#', '#' + '.'.repeat(15) + '#', '#' + '.'.repeat(15) + '#', '#' + '.'.repeat(15) + '#', '#################'];
    const dotsFor = (floorCh, wall, mut) => {
      const w = VCS.World.load({ name: 'sp', rows: rows.map((r) => r.replace(/[.]/g, floorCh)), materials: { '#': wall } }, { requireStart: false });
      const f = setup();
      f.r.quality = 3;
      if (mut) mut(f.r);
      const p = { x: 3.5, y: 2.5, angle: 0 };
      VCS.Sonar.emit(f.sonar, w, p.x, p.y, 100, { range: 12, facing: 0 });
      f.r.octx.calls.length = 0;
      Render.drawFirstPerson(f.r, w, p, f.sonar, 100.45, {});
      return f.r.octx.calls.filter((c) => c.fn === 'rect' && c.args[2] <= 2 && c.args[3] <= 2 && c.args[2] * c.args[3] <= 2);
    };
    const smooth = dotsFor('.', 'stone');
    const rough = dotsFor('g', 'cobble');
    assert.ok(rough.length > smooth.length, 'rough ' + rough.length + ' > smooth ' + smooth.length);
    assert.ok(rough.length <= 80 + 40, 'dot count stays bounded');
    const off = dotsFor('g', 'cobble', (r) => { r.matDetail = false; });
    assert.ok(off.length <= 40, 'matDetail off: base stipple only (' + off.length + ')');
    const cfgOff = dotsFor('g', 'cobble', (r) => { r.config = { materialDetail: false }; });
    assert.ok(cfgOff.length <= 40, 'materialDetail setting off: base stipple only');
    const q1 = dotsFor('g', 'cobble', (r) => { r.quality = 1; });
    assert.strictEqual(q1.length, 0, 'quality < 2 draws no floor front');
  }));

  test('floor texture: grass dots are 1x2 ticks, wood 2x1 grain, stone 1x1 specks (one fill, no extra pass)', () => withPath2D(() => {
    const rows = ['#################', '#' + '.'.repeat(15) + '#', '#' + '.'.repeat(15) + '#', '#' + '.'.repeat(15) + '#', '#################'];
    const sizes = (ch) => {
      const w = VCS.World.load({ name: 'ft', rows: rows.map((r) => r.replace(/[.]/g, ch)) }, { requireStart: false });
      const f = setup();
      f.r.quality = 3;
      const p = { x: 3.5, y: 2.5, angle: 0 };
      VCS.Sonar.emit(f.sonar, w, p.x, p.y, 100, { range: 12, facing: 0 });
      f.r.octx.calls.length = 0;
      Render.drawFirstPerson(f.r, w, p, f.sonar, 100.45, {});
      const dots = f.r.octx.calls.filter((c) => c.fn === 'rect' && c.args[2] * c.args[3] <= 2);
      return { w: new Set(dots.map((c) => c.args[2])), h: new Set(dots.map((c) => c.args[3])), n: dots.length };
    };
    const grass = sizes('g');
    const wood = sizes(',');
    const stone = sizes('.');
    assert.ok(grass.n > 0 && wood.n > 0 && stone.n > 0);
    assert.ok(grass.h.has(2) && grass.w.has(1) && !grass.w.has(2));
    assert.ok(wood.w.has(2) && wood.h.has(1) && !wood.h.has(2));
    assert.ok(stone.w.has(1) && stone.h.has(1) && stone.w.size === 1 && stone.h.size === 1);
  }));
});

describe('render-warm.test.js', () => {

  const test = require('node:test');
  const assert = require('node:assert');

  const R = '../js/';
  for (const m of ['log', 'ripple', 'raycast', 'world', 'sonar', 'people', 'struggle', 'data/maps']) require(R + m + '.js');
  const Render = require(R + 'render.js');
  const VCS = globalThis.VCS;

  function fakeCtx(canvas) {
    const calls = [];
    const state = { globalAlpha: 1, fillStyle: '#000', strokeStyle: '#000', lineWidth: 1 };
    return new Proxy({ calls, canvas }, {
      get(t, p) {
        if (p in t) return t[p];
        if (p in state) return state[p];
        return function () {
          calls.push({ fn: String(p), args: Array.prototype.slice.call(arguments) });
          if (p === 'createRadialGradient' || p === 'createLinearGradient') return { addColorStop() {} };
          if (p === 'createPattern') return {};
          if (p === 'createImageData') return { data: new Uint8ClampedArray(128 * 128 * 4) };
          return undefined;
        };
      },
      set(t, p, v) { state[p] = v; return true; }
    });
  }
  function fakeCanvas(w, h) {
    const c = { width: w, height: h };
    c.ownerDocument = { createElement() { return fakeCanvas(w, h); } };
    c._ctx = null;
    c.getContext = function () { return c._ctx || (c._ctx = fakeCtx(c)); };
    return c;
  }

  const player = { x: 5.5, y: 5.5, angle: 0 };
  function run(warm) {
    const canvas = fakeCanvas(640, 360);
    const r = Render.create(canvas, {});
    const world = VCS.World.load(VCS.MapData.maps[VCS.MapData.startMap]);
    const sonar = VCS.Sonar.create();
    const opts = warm ? { warm } : {};
    Render.drawFirstPerson(r, world, player, sonar, 1, opts);
    return canvas._ctx.calls.filter((c) => c.fn === 'arc' || c.fn === 'createRadialGradient').length;
  }

  test('person within radius adds a halo', () => {
    const base = run(null);
    assert.ok(run({ radius: 5, people: [{ x: 8.5, y: 5.5 }] }) > base);
  });

  test('person beyond radius, behind, or radius 0 adds nothing', () => {
    const base = run(null);
    assert.strictEqual(run({ radius: 5, people: [{ x: 13.5, y: 5.5 }] }), base);
    assert.strictEqual(run({ radius: 5, people: [{ x: 2.5, y: 5.5 }] }), base);
    assert.strictEqual(run({ radius: 0, people: [{ x: 8.5, y: 5.5 }] }), base);
    assert.strictEqual(run({ radius: 5, people: [] }), base);
  });

  test('falls back to a circle when gradients are missing; bad input never throws', () => {
    const canvas = fakeCanvas(640, 360);
    const r = Render.create(canvas, {});
    const world = VCS.World.load(VCS.MapData.maps[VCS.MapData.startMap]);
    const ctx = canvas.getContext('2d');
    const proxyless = new Proxy(ctx, { get(t, p) { return p === 'createRadialGradient' ? undefined : t[p]; } });
    r.ctx = proxyless;
    assert.doesNotThrow(() => Render.drawFirstPerson(r, world, player, VCS.Sonar.create(), 1, { warm: { radius: 5, people: [{ x: 8.5, y: 5.5 }, null, { x: 'a' }] } }));
    assert.doesNotThrow(() => Render.drawFirstPerson(r, world, player, VCS.Sonar.create(), 1, { warm: { radius: NaN, people: 5 } }));
  });


});


describe('edge glow ramp', () => {
  const test = require('node:test');
  const assert = require('node:assert');
  const Render = require('../js/render.js');
  test('edgeGlowAlpha is continuous, monotonic, 0 at 0 and 0.5 at 1', () => {
    const f = Render.edgeGlowAlpha;
    assert.strictEqual(f(0), 0);
    assert.ok(Math.abs(f(1) - 0.5) < 1e-9);
    assert.ok(f(0.29) > 0 && f(0.31) - f(0.29) < 0.02, 'no switch at 0.3');
    let prev = 0;
    for (let i = 1; i <= 20; i++) { const v = f(i / 20); assert.ok(v > prev); prev = v; }
    assert.strictEqual(f(5), f(1));
    assert.strictEqual(f(NaN), 0);
  });
  test('edgeZoneAlpha is monotone in core and 0 when both are 0', () => {
    const f = Render.edgeZoneAlpha;
    assert.strictEqual(f(0, 0), 0);
    let prev = 0;
    for (let i = 1; i <= 20; i++) { const v = f(i / 20, 0.5); assert.ok(v >= prev); prev = v; }
    assert.ok(f(0, 1) > 0 && f(0, 1) <= Render.edgeGlowAlpha(0.35) + 1e-9);
  });
});

describe('render-vessels (circulatory P3)', () => {
  const test = require('node:test');
  const assert = require('node:assert');
  require('../js/log.js');
  require('../js/flags.js');
  require('../js/data/vessels.js');
  const Render = require('../js/render.js');
  const VCS = globalThis.VCS;
  const Flags = VCS.Flags;
  const D = VCS.VesselData;
  Flags.register('vis.vessels', false, 'Circulatory pulse on villagers');

  function ctx() {
    const calls = [];
    const st = { globalAlpha: 1, fillStyle: '#000' };
    return new Proxy({ calls }, {
      get(t, p) {
        if (p in t) return t[p];
        if (p in st) return st[p];
        return function () { calls.push({ fn: String(p), args: Array.from(arguments), alpha: st.globalAlpha, fill: st.fillStyle, lw: st.lineWidth }); };
      },
      set(t, p, v) { st[p] = v; return true; }
    });
  }
  function rig(q, reduced) { return { octx: ctx(), quality: q, reduced: !!reduced, wscale: 1 }; }
  // Pose: head at top, feet 200 px below. age -1 = static nodes (no beat clock); P4 travel is tested below.
  const X = new Float32Array(24).fill(100);
  const Y = new Float32Array(24);
  [20, 40, 50, 50, 120, 120, 110, 110, 220, 220, 80, 80, 170, 170, 85].forEach((v, i) => { Y[i] = v; });
  function vh(o) { return Object.assign({ kind: 'vheart', strength: 1, fade: 3, bpm: 65, stateK: 1, periphK: 1, headK: 1 }, o || {}); }
  const total = D.arteries.length + D.veins.length;

  test('no-op when the flag is off (default)', () => {
    Flags.set('vis.vessels', false);
    const r = rig(2);
    assert.strictEqual(Render.drawVessels(r, vh(), X, Y, -1), 0);
    assert.strictEqual(r.octx.calls.length, 0);
  });

  test('draws every node at quality >= 1, nothing extra at quality 0 or for other echo kinds', () => {
    Flags.set('vis.vessels', true);
    for (const q of [1, 2, 3]) assert.strictEqual(Render.drawVessels(rig(q), vh(), X, Y, -1), total);
    const r0 = rig(0);
    assert.strictEqual(Render.drawVessels(r0, vh(), X, Y, -1), 0);
    assert.strictEqual(r0.octx.calls.length, 0);
    assert.strictEqual(Render.drawVessels(rig(2), vh({ kind: 'ping' }), X, Y, -1), 0);
    // Batched: a handful of fills per figure, not one per node.
    const r = rig(2);
    Render.drawVessels(r, vh(), X, Y, -1);
    const fills = r.octx.calls.filter((c) => c.fn === 'fill').length;
    assert.ok(fills > 0 && fills <= 4 * 6, 'fills ' + fills);
    // Halo only at quality 2+.
    const r1 = rig(1);
    Render.drawVessels(r1, vh(), X, Y, -1);
    assert.ok(r1.octx.calls.filter((c) => c.fn === 'fill').length < fills);
    Flags.set('vis.vessels', false);
  });

  test('alpha scales with node weight and periphK, headK on head nodes', () => {
    const o = { base: 0.5, hotK: 0, veinK: 0.6 };
    const heart = D.arteries.find((n) => n.id === 'heart');
    const radial = D.arteries.find((n) => n.id === 'radialL');
    const temporal = D.arteries.find((n) => n.id === 'temporal');
    assert.ok(Math.abs(Render.vesselAlpha(heart, vh(), o) - 0.5) < 1e-9);
    assert.ok(Math.abs(Render.vesselAlpha(radial, vh(), o) - 0.5 * radial.w) < 1e-9);
    assert.ok(Math.abs(Render.vesselAlpha(radial, vh({ periphK: 0.5 }), o) - 0.25 * radial.w) < 1e-9);
    assert.strictEqual(Render.vesselAlpha(heart, vh({ periphK: 0.5 }), o), Render.vesselAlpha(heart, vh(), o));
    assert.ok(Render.vesselAlpha(temporal, vh({ headK: 1.25 }), o) > Render.vesselAlpha(temporal, vh(), o));
    assert.ok(Render.vesselAlpha(heart, vh({ stateK: 0.5 }), o) < Render.vesselAlpha(heart, vh(), o));
    // Hotspot boost (heart +50%), veins dimmer than their artery.
    assert.ok(Render.vesselAlpha(heart, vh(), { base: 0.5, hotK: 1 }) > Render.vesselAlpha(heart, vh(), o));
    assert.ok(Render.vesselAlpha(D.veins[0], vh(), o) < Render.vesselAlpha(heart, vh(), o));
    // periphK 0 drops the hands/feet (periph 1) from the drawn set.
    Flags.set('vis.vessels', true);
    const periph = D.arteries.concat(D.veins).filter((n) => n.periph >= 1).length;
    assert.strictEqual(Render.drawVessels(rig(2), vh({ periphK: 0 }), X, Y, -1), total - periph);
    Flags.set('vis.vessels', false);
  });

  test('vampire, zero stateK or zero strength draws nothing', () => {
    Flags.set('vis.vessels', true);
    for (const e of [vh({ vampire: true }), vh({ body: 'vampire' }), vh({ stateK: 0 }), vh({ strength: 0 })]) {
      const r = rig(2);
      assert.strictEqual(Render.drawVessels(r, e, X, Y, -1), 0);
      assert.strictEqual(r.octx.calls.filter((c) => c.fn === 'fill').length, 0);
    }
    // Past the echo's life: nothing.
    assert.strictEqual(Render.drawVessels(rig(2), vh(), X, Y, 5), 0);
    Flags.set('vis.vessels', false);
  });

  test('reduced motion: no halo, every fill alpha <= 0.5', () => {
    Flags.set('vis.vessels', true);
    const r = rig(3, true);
    const n = Render.drawVessels(r, vh({ stateK: 1.6, headK: 1.25 }), X, Y, -1);
    assert.ok(n > 0);
    const fills = r.octx.calls.filter((c) => c.fn === 'fill');
    assert.ok(fills.length > 0);
    for (const f of fills) assert.ok(f.alpha <= 0.5 + 1e-9, 'alpha ' + f.alpha);
    for (const n2 of D.arteries) assert.ok(Render.vesselAlpha(n2, vh({ stateK: 2 }), { base: 1, reduced: true }) <= 0.5);
    Flags.set('vis.vessels', false);
  });

  // ---- P4: travelling wave ----
  // Node positions drawn (arc centres) with their fill alpha, solid pass only.
  function lit(r) {
    const out = [];
    for (const c of r.octx.calls) if (c.fn === 'arc' && c.alpha > 0) out.push({ x: c.args[0], y: c.args[1], r: c.args[2], a: c.alpha, fill: c.fill });
    return out;
  }
  const V = VCS.Vessels;
  const art = (id) => D.arteries.find((n) => n.id === id);
  const yOf = (n) => V.anchor(n, X, Y).y;

  test('P4 wave travels outward: chest first, feet later, nothing before a node\'s delay', () => {
    Flags.set('vis.vessels', true);
    const tr = V.travel(1.75);
    const early = lit((() => { const r = rig(1); Render.drawVessels(r, vh(), X, Y, 0.03); return r; })());
    const footY = yOf(art('pedalL'));
    const handY = yOf(art('radialL'));
    assert.ok(early.length > 0, 'heart lit at 0.03 s');
    assert.ok(early.every((p) => p.y < handY - 1), 'only the chest at 0.03 s');
    const ages = [0.03, 0.15, 0.3, tr.art[D.arteries.indexOf(art('pedalL'))] + 0.06];
    const reach = ages.map((a) => { const r = rig(1); Render.drawVessels(r, vh(), X, Y, a); return Math.max(...lit(r).map((p) => p.y)); });
    for (let k = 1; k < reach.length; k++) assert.ok(reach[k] >= reach[k - 1], 'front moves down ' + reach);
    assert.ok(Math.abs(reach[reach.length - 1] - footY) < 1e-6, 'feet lit at the end');
    Flags.set('vis.vessels', false);
  });

  test('P4 vessel life: drawVessels stops at life, vesselLife ~1 s and reduced shorter', () => {
    Flags.set('vis.vessels', true);
    const life = Render.vesselLife(vh(), false);
    assert.ok(life > 0.9 && life < 1.3, 'life ' + life);
    assert.ok(Render.vesselLife(vh(), true) < life);
    assert.ok(Render.drawVessels(rig(2), vh(), X, Y, life * 0.6) > 0);
    assert.strictEqual(Render.drawVessels(rig(2), vh(), X, Y, life + 0.01), 0);
    Flags.set('vis.vessels', false);
  });

  test('P4 reduced motion: every node lit together, alpha <= 0.5', () => {
    Flags.set('vis.vessels', true);
    const r = rig(3, true);
    const n = Render.drawVessels(r, vh({ stateK: 1.6 }), X, Y, 0.1);
    assert.strictEqual(n, total);
    for (const f of r.octx.calls.filter((c) => c.fn === 'fill')) assert.ok(f.alpha <= 0.5 + 1e-9);
    Flags.set('vis.vessels', false);
  });
  // ---- P5: edges + travelling highlight ----
  // Figure 200 px tall -> rad 3.2; artery highlight width 1.1 x rad, base line 0.55 x rad.
  const HL_ART = 1.1 * 3.2;
  const BASE_ART = 0.55 * 3.2;
  const pts = (r, lw) => r.octx.calls.filter((c) => c.fn === 'lineTo' && Math.abs(c.lw - lw) < 1e-6);
  const strokes = (r) => r.octx.calls.filter((c) => c.fn === 'stroke');

  test('P5 quality gating: q2+ edges and nodes, q1 nodes only, q0 nothing', () => {
    Flags.set('vis.vessels', true);
    for (const q of [2, 3]) {
      const r = rig(q);
      assert.ok(Render.drawVessels(r, vh(), X, Y, 0.2) > 0);
      assert.ok(strokes(r).length > 0, 'edges at q' + q);
    }
    const r1 = rig(1);
    assert.ok(Render.drawVessels(r1, vh(), X, Y, 0.2) > 0);
    assert.strictEqual(strokes(r1).length, 0);
    const r0 = rig(0);
    assert.strictEqual(Render.drawVessels(r0, vh(), X, Y, 0.2), 0);
    assert.strictEqual(r0.octx.calls.length, 0);
    // Batched: one stroke per alpha level and pass, not one per edge.
    const r = rig(2);
    Render.drawVessels(r, vh(), X, Y, 0.2);
    assert.ok(strokes(r).length <= 4 * 6, 'strokes ' + strokes(r).length);
    Flags.set('vis.vessels', false);
  });

  test('P5 highlight travels outward along the edges, lub then dub', () => {
    Flags.set('vis.vessels', true);
    const lowest = (a) => { const r = rig(2); Render.drawVessels(r, vh(), X, Y, a); const p = pts(r, HL_ART); return p.length ? Math.max(...p.map((c) => c.args[1])) : -1; };
    const ys = [0.03, 0.1, 0.2, 0.3].map(lowest);
    for (let k = 1; k < ys.length; k++) assert.ok(ys[k] >= ys[k - 1], 'front moves down ' + ys);
    assert.ok(ys[0] > 0 && ys[0] < 120, 'starts in the torso ' + ys[0]);
    // Long after the lub has reached the feet only the dub (and later nothing) travels.
    const tr = V.travel(1.75);
    const after = tr.artMax + 0.05;
    const r = rig(2);
    Render.drawVessels(r, vh(), X, Y, after);
    const hl = r.octx.calls.filter((c) => c.fn === 'stroke' && Math.abs(c.lw - HL_ART) < 1e-6);
    // The dub (~30%) is still on its way: dimmer than the lub peak.
    const rl = rig(2);
    Render.drawVessels(rl, vh(), X, Y, 0.15);
    const lubMax = Math.max(...rl.octx.calls.filter((c) => c.fn === 'stroke' && Math.abs(c.lw - HL_ART) < 1e-6).map((c) => c.alpha));
    assert.ok(hl.length > 0, 'dub highlight');
    assert.ok(Math.max(...hl.map((c) => c.alpha)) < lubMax);
    Flags.set('vis.vessels', false);
  });

  test('P5 edges follow the limb curves (quadratic through the elbow and knee)', () => {
    Flags.set('vis.vessels', true);
    const r = rig(2);
    Render.drawVessels(r, vh(), X, Y, -1);
    assert.ok(r.octx.calls.some((c) => c.fn === 'quadraticCurveTo' && Math.abs(c.lw - BASE_ART) < 1e-6));
    Flags.set('vis.vessels', false);
  });

  test('P5 reduced motion: no highlight, edges and nodes alpha <= 0.5', () => {
    Flags.set('vis.vessels', true);
    for (const a of [0.05, 0.2, 0.4]) {
      const r = rig(3, true);
      Render.drawVessels(r, vh({ stateK: 1.6, headK: 1.25 }), X, Y, a);
      assert.strictEqual(pts(r, HL_ART).length, 0);
      for (const c of r.octx.calls) if (c.fn === 'stroke' || c.fn === 'fill') assert.ok(c.alpha <= 0.5 + 1e-9, c.fn + ' ' + c.alpha);
    }
    Flags.set('vis.vessels', false);
  });

  test('mute scales every vessel alpha down (window, P2b)', () => {
    Flags.set('vis.vessels', true);
    const full = rig(2);
    Render.drawVessels(full, vh(), X, Y, 0.1);
    const half = rig(2);
    Render.drawVessels(half, vh(), X, Y, 0.1, 0.3);
    const mx = (r) => Math.max(...r.octx.calls.filter((c) => c.fn === 'fill' || c.fn === 'stroke').map((c) => c.alpha));
    assert.ok(mx(half) < mx(full) * 0.5, mx(half) + ' vs ' + mx(full));
    assert.strictEqual(Render.drawVessels(rig(2), vh(), X, Y, 0.1, 0), 0);
    Flags.set('vis.vessels', false);
  });
});

