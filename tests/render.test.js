'use strict';
// Merged test file: each source file's tests live in their own describe().
const { describe } = require('node:test');

describe('render-feed.test.js', () => {

  const test = require('node:test');
  const assert = require('node:assert');

  const R = '../js/';
  for (const m of ['log', 'ripple', 'raycast', 'world', 'sonar', 'people', 'data/maps']) require(R + m + '.js');
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
    assert.ok(s.every((c) => c.alpha >= 0.9 - 1e-9), 'alpha >= 0.9');
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

  test('windows: lit panes glow without a ring (alpha <= 0.25), dark panes only glint on reveal; reduced motion is static', () => withPath2D(() => {
    const world = VCS.World.load(VCS.MapData.maps.town, { requireStart: false });
    function look(x, y, ang, t, reduced) {
      const r = Render.create(fakeCanvas(640, 360), {});
      r.reduced = reduced;
      r.quality = 3;
      const sonar = VCS.Sonar.create();
      r.octx.calls.length = 0;
      Render.drawFirstPerson(r, world, { x: x, y: y, angle: ang }, sonar, t, {});
      const glow = r.octx.calls.filter((c) => c.fn === 'fillRect' && c.alpha > 0.04);
      return { r: r, glow: glow };
    }
    const lit = look(32.5, 12.5, Math.PI / 2, 5, false);
    assert.ok(lit.glow.length > 4, 'lit window glows in the dark with no pulse');
    assert.ok(lit.glow.every((c) => c.alpha <= 0.25 + 1e-9), 'glow alpha <= 0.25');
    assert.ok(!lit.r.logged || Object.keys(lit.r.logged).length === 0);
    assert.strictEqual(look(22.5, 5, -Math.PI / 2, 5, false).glow.length, 0, 'unlit window shows no glow');
    const a = look(32.5, 12.5, Math.PI / 2, 5.0, true).glow.map((c) => c.alpha.toFixed(4)).join();
    const b = look(32.5, 12.5, Math.PI / 2, 5.6, true).glow.map((c) => c.alpha.toFixed(4)).join();
    assert.strictEqual(a, b, 'static under reduced motion');
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
    assert.ok(strokes(32.5, 12.5, Math.PI / 2, '#ffd596') > 0, 'lit window frame is candle gold');
    assert.ok(strokes(22.5, 5, -Math.PI / 2, '#c4e2ff') > 0, 'dark window frame is cold glass');
  }));

  test('props on the town map draw without a logged failure; flames show without any pulse', () => withPath2D(() => {
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
    assert.ok(flame.length >= 1, 'flame drawn in the dark');
    assert.ok(flame.every((c) => c.alpha <= 0.6), 'flame stays faint');
    VCS.Sonar.emit(sonar, world, pl.x, pl.y, 5, {});
    for (let t = 5.05; t < 6.5; t += 0.1) Render.drawFirstPerson(r, world, pl, sonar, t, {});
    assert.ok(!r.logged || !r.logged.props, 'props drew without failure');
    assert.ok(!r.logged || !r.logged.flames, 'flames drew without failure');
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

});

describe('render-warm.test.js', () => {

  const test = require('node:test');
  const assert = require('node:assert');

  const R = '../js/';
  for (const m of ['log', 'ripple', 'raycast', 'world', 'sonar', 'people', 'data/maps']) require(R + m + '.js');
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

