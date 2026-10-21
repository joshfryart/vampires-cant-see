'use strict';
const test = require('node:test');
const assert = require('node:assert');
const V = require('../js/data/vessels.js');
const D = V.data;

const near = (a, b, e) => assert.ok(Math.abs(a - b) < (e || 1e-9), a + ' vs ' + b);

test('data frozen, ~15 arteries, veins mirror', () => {
  assert.ok(Object.isFrozen(D) && Object.isFrozen(D.arteries[0]) && Object.isFrozen(D.modes.calm));
  assert.ok(D.arteries.length >= 13 && D.arteries.length <= 19);
  assert.strictEqual(D.veins.length, D.arteries.length);
  const ids = new Set(V.all().map((n) => n.id));
  assert.strictEqual(ids.size, V.all().length);
  D.veins.forEach((v, i) => {
    const a = D.arteries[i];
    assert.strictEqual(v.vein, true);
    assert.strictEqual(a.vein, false);
    assert.strictEqual(v.id, 'v_' + a.id);
    assert.strictEqual(v.slot, a.slot);
    assert.ok(v.w < a.w || a.w === 0);
    assert.strictEqual(v.hot, 0);
  });
  assert.strictEqual(D.PWV, 6);
  assert.ok(D.PWV_SCALE >= 1.5 && D.PWV_SCALE <= 2);
  assert.strictEqual(D.BPM_MAX, 175);
});

test('tree rooted at heart, slots valid', () => {
  [D.arteries, D.veins].forEach((set) => {
    const roots = set.filter((n) => n.parent === null);
    assert.strictEqual(roots.length, 1);
    const ids = new Set(set.map((n) => n.id));
    set.forEach((n) => {
      if (n.parent !== null) assert.ok(ids.has(n.parent), n.id + ' parent ' + n.parent);
      assert.ok(Number.isInteger(n.slot) && n.slot >= 0 && n.slot <= 14, n.id);
      assert.ok(Number.isInteger(n.to) && n.to >= 0 && n.to <= 14, n.id);
      // every node reaches the root (no cycles)
      let p = n;
      let hops = 0;
      while (p.parent !== null && hops < 50) { p = V.byId(p.parent); hops++; }
      assert.strictEqual(p, roots[0]);
    });
  });
  const h = V.byId('heart');
  assert.strictEqual(h.parent, null);
  assert.deepStrictEqual([h.slot, h.to, h.t], [D.HEART.slot, D.HEART.to, D.HEART.t]);
  assert.deepStrictEqual([h.slot, h.to, h.t], [14, 1, 0.45]);
  // all 15 pose slots used
  const used = new Set();
  D.arteries.forEach((n) => { used.add(n.slot); used.add(n.to); });
  for (let s = 0; s <= 14; s++) assert.ok(used.has(s), 'slot ' + s);
});

test('anchor follows pose slots', () => {
  const X = [];
  const Y = [];
  for (let i = 0; i < 15; i++) { X.push(i * 10); Y.push(-i * 2); }
  X[14] = 100; Y[14] = 50; X[1] = 100; Y[1] = 0;
  const p = V.anchor(V.byId('heart'), X, Y);
  near(p.x, 100);
  near(p.y, 50 - 50 * 0.45);
  const o = { x: 0, y: 0 };
  assert.strictEqual(V.anchor(V.byId('pedalL'), X, Y, o), o);
  assert.deepStrictEqual(o, { x: X[8], y: Y[8] });
});

test('pathLen, delay monotonic and w decreasing outward', () => {
  const del = V.delays(D.PWV, D.PWV_SCALE);
  const w = V.weights();
  D.arteries.forEach((n, i) => {
    if (n.parent === null) { assert.strictEqual(n.pathLen, 0); assert.strictEqual(del[i], 0); return; }
    const pi = D.arteries.findIndex((q) => q.id === n.parent);
    assert.ok(n.pathLen > D.arteries[pi].pathLen, n.id);
    assert.ok(del[i] > del[pi], n.id);
    assert.ok(w[i] < w[pi], n.id);
  });
  // research numbers
  near(V.byId('carotid').pathLen, 0.25);
  near(V.byId('temporal').pathLen, 0.4);
  near(V.byId('radialL').pathLen, 0.9);
  near(V.byId('femoralR').pathLen, 0.7);
  near(V.byId('poplitealL').pathLen, 0.95);
  near(V.byId('pedalR').pathLen, 1.35);
  // unscaled delays match the reference: head ~65 ms, wrist 150, groin ~115, ankle 225
  const raw = V.delays(6, 1);
  const at = (id) => raw[D.arteries.findIndex((n) => n.id === id)];
  near(at('temporal'), 0.0667, 0.002);
  near(at('radialL'), 0.15, 0.002);
  near(at('femoralL'), 0.1167, 0.002);
  near(at('pedalL'), 0.225, 0.002);
  // scale stretches proportionally; bad args fall back to defaults
  near(V.delays(6, 2)[16], 2 * raw[16]);
  assert.deepStrictEqual(V.delays(0, 0), V.delays(D.PWV, D.PWV_SCALE));
});

test('feet lag head, both sides symmetric', () => {
  [1, 1.5, 2].forEach((m) => {
    const del = V.delays(6, m);
    const at = (id) => del[D.arteries.findIndex((n) => n.id === id)];
    assert.ok(at('pedalL') > at('temporal'));
    assert.ok(at('pedalR') > at('radialR'));
    near(at('pedalL'), at('pedalR'));
    near(at('radialL'), at('radialR'));
  });
});

test('state modes', () => {
  const calm = V.state('villager', 'calm');
  assert.deepStrictEqual(calm, { pulse: true, bpm: 65, stateK: 1, periphK: 1, headK: 1 });
  assert.deepStrictEqual(V.state('villager', 'nonsense'), calm);
  const wary = V.state('villager', 'wary');
  assert.strictEqual(wary.bpm, 90);
  near(wary.stateK, 1.15);
  assert.ok(wary.headK > 1);
  const st = V.state('villager', 'startle');
  assert.strictEqual(st.bpm, 100);
  ['flee', 'cower'].forEach((m) => {
    const s = V.state('villager', m);
    assert.strictEqual(s.bpm, 130);
    assert.ok(s.stateK >= 1.4 && s.stateK <= 1.6);
    assert.ok(s.periphK < 1);
  });
  assert.ok(V.state('villager', 'sleep').bpm < 65);
  // drinking uses the drink formula 50 + 70 * blood
  near(V.state('villager', 'drinking', 1).bpm, 120);
  near(V.state('villager', 'drinking', 0.5).bpm, 85);
  // fed/drained and empty: no pulse
  ['fed', 'drained'].forEach((m) => assert.strictEqual(V.state('villager', m).pulse, false));
  assert.strictEqual(V.state('villager', 'calm', 0).pulse, false);
  assert.strictEqual(V.state('villager', 'calm', 0).bpm, 0);
});

test('strength: heart strongest, fear and blood loss dim extremities first', () => {
  const heart = V.byId('heart');
  const foot = V.byId('pedalL');
  const neck = V.byId('carotid');
  const calm = V.state('villager', 'calm');
  assert.ok(V.strength(heart, calm) > V.strength(foot, calm));
  near(V.strength(heart, calm), 1.5);
  const flee = V.state('villager', 'flee');
  assert.ok(V.strength(heart, flee) > V.strength(heart, calm));
  assert.ok(V.strength(foot, flee) / V.strength(heart, flee) < V.strength(foot, calm) / V.strength(heart, calm));
  const wary = V.state('villager', 'wary');
  assert.ok(V.strength(neck, wary) / V.strength(heart, wary) > V.strength(neck, calm) / V.strength(heart, calm));
  const low = V.state('villager', 'drinking', 0.3);
  const full = V.state('villager', 'drinking', 1);
  near(low.stateK, Math.pow(0.3, 1.5));
  assert.ok(V.strength(foot, low) / V.strength(heart, low) < V.strength(foot, full) / V.strength(heart, full));
  assert.ok(V.strength(heart, low) > 0);
  assert.strictEqual(V.strength(heart, V.state('villager', 'fed')), 0);
  assert.strictEqual(V.strength(heart, null), 0);
});

test('bpm cap 175', () => {
  assert.strictEqual(V.capBpm(300), 175);
  assert.strictEqual(V.capBpm(175), 175);
  assert.strictEqual(V.capBpm(90), 90);
  assert.strictEqual(V.capBpm(-5), 0);
  assert.strictEqual(V.capBpm(NaN), 0);
  Object.keys(D.modes).forEach((m) => {
    [1, 0.7, 0.4, 0.2, 0.05].forEach((f) => {
      const s = V.state('villager', m, f);
      assert.ok(s.bpm <= 175 && s.bpm < 180, m + ' ' + f);
    });
  });
});

test('vampire: anatomy only, no pulse, no blood', () => {
  const vb = V.forBody('vampire');
  assert.strictEqual(vb.kind, 'vampire');
  assert.strictEqual(vb.pulse, false);
  assert.strictEqual(vb.blood, false);
  assert.strictEqual(vb.nodes.length, D.arteries.length + D.veins.length);
  ['calm', 'flee', 'drinking'].forEach((m) => {
    const s = V.state('vampire', m, 1);
    assert.strictEqual(s.pulse, false);
    assert.strictEqual(s.bpm, 0);
    vb.nodes.forEach((n) => assert.strictEqual(V.strength(n, s), 0));
  });
  const pb = V.forBody('villager');
  assert.strictEqual(pb.pulse, true);
  assert.strictEqual(pb.blood, true);
});

// ---- P4: travelling pulse wave, lub-dub ----
const idx = (id) => D.arteries.findIndex((n) => n.id === id);
const firstLit = (vein, i, tm) => { for (let a = 0; a < 2; a += 0.001) if (V.pulse(vein, i, a, tm) > 0) return a; return Infinity; };

test('P4 delay ordering: foot after chest, hand after shoulder, head before feet', () => {
  const tm = V.timing(65);
  const tr = V.travel();
  near(tr.art[idx('pedalL')], 1.35 * D.PWV_SCALE / D.PWV);
  assert.ok(firstLit(false, idx('pedalL'), tm) > firstLit(false, idx('heart'), tm) + 0.3);
  assert.ok(firstLit(false, idx('radialL'), tm) > firstLit(false, idx('subclavL'), tm));
  assert.ok(firstLit(false, idx('temporal'), tm) < firstLit(false, idx('pedalR'), tm));
  assert.ok(firstLit(false, idx('femoralL'), tm) < firstLit(false, idx('pedalL'), tm));
});

test('P4 alpha 0 before a node\'s delay, peaks after attack, dimmer toward extremities', () => {
  const tm = V.timing(65);
  const tr = V.travel();
  D.arteries.forEach((n, i) => {
    if (tr.art[i] > 0) assert.strictEqual(V.pulse(false, i, tr.art[i] - 0.01, tm), 0, n.id);
    near(V.pulse(false, i, tr.art[i] + D.ATTACK, tm), 1, 1e-6);
  });
  assert.strictEqual(V.pulse(false, 0, -0.1, tm), 0);
  assert.strictEqual(V.pulse(false, 0, tm.life, tm), 0);
  assert.ok(V.weights()[idx('pedalL')] < V.weights()[idx('heart')]);
});

test('P4 dub ripple ~30% of the lub, ~0.3 s later at rest, sooner at high bpm', () => {
  const tm = V.timing(65);
  near(tm.dub, 0.3, 1e-9);
  near(tm.dubK, 0.3, 1e-9);
  const i = idx('carotid');
  const t = V.travel().art[i] + tm.dub + D.ATTACK;
  const lubOnly = V.envelope(t - V.travel().art[i], D.ATTACK, D.DECAY);
  near(V.pulse(false, i, t, tm) - lubOnly, 0.3, 1e-6);
  // A local bump: brighter at the dub peak than just before it.
  assert.ok(V.pulse(false, i, t, tm) > V.pulse(false, i, t - D.ATTACK, tm));
  const fast = V.timing(175);
  assert.ok(fast.dub < tm.dub && fast.dub <= 0.45 * 60 / 175 + 1e-12);
  assert.ok(fast.dubK <= 0.3 && fast.dubK >= 0.1);
  assert.strictEqual(V.timing(300).dub, fast.dub); // bpm cap 175 (< 3 Hz)
});

test('P4 veins lag their arteries, swell slower and never flash', () => {
  const tm = V.timing(65);
  D.veins.forEach((v, i) => {
    assert.ok(firstLit(true, i, tm) > firstLit(false, i, tm), v.id);
    assert.ok(V.travel().vein[i] >= V.travel().art[i] + D.VEIN_LAG - 1e-9);
  });
  assert.ok(D.VEIN_ATTACK > D.ATTACK && D.VEIN_DECAY > D.DECAY);
});

test('P4 reduced motion: zero delays, single soft pulse, no dub', () => {
  const tm = V.timing(130, true);
  assert.strictEqual(tm.dub, 0);
  assert.strictEqual(tm.dubK, 0);
  const all = D.arteries.map((n, i) => V.pulse(false, i, 0.15, tm)).concat(D.veins.map((n, i) => V.pulse(true, i, 0.15, tm)));
  all.forEach((p) => near(p, all[0]));
  assert.ok(all[0] > 0.5);
  // Monotonic after the peak: one pulse.
  let prev = Infinity;
  for (let a = D.SOFT_ATTACK; a < tm.life; a += 0.01) { const p = V.pulse(false, idx('pedalL'), a, tm); assert.ok(p <= prev + 1e-12); prev = p; }
});

test('P4 vessel life covers feet + dub + decay, ~1 s', () => {
  [52, 65, 90, 130, 175].forEach((b) => {
    const tm = V.timing(b);
    assert.ok(tm.life >= V.travel().artMax + tm.dub + D.DECAY, b);
    assert.ok(tm.life > 0.5 && tm.life < 1.3, b + ' ' + tm.life);
  });
  // Larger pwvScale = later feet.
  assert.ok(V.travel(2.5).art[idx('pedalL')] > V.travel().art[idx('pedalL')]);
});
