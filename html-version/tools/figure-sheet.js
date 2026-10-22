// Villager figure contact sheet (tools/figure-sheet.html). Draws the REAL game figures through Render.drawSolo (the
// drawPerson path: posePerson, pulse-strip masking, rim light, volumetric Figure or line figure, vessels, flush, grab
// arms) into the renderer's offscreen canvas, then copies a crop around the figure into each cell. No drawing logic is
// copied here: only echo set-up, layout and debug overlays (slots, vessel graph, part outlines).
(function () {
  'use strict';
  const VCS = window.VCS;
  const main = document.getElementById('main');

  function fatal(msg) {
    const p = document.createElement('p');
    p.className = 'err';
    p.textContent = msg;
    main.appendChild(p);
  }
  if (!VCS || !VCS.Render || !VCS.Figure || !VCS.Forge) { fatal('Game modules failed to load.'); return; }
  const R = VCS.Render;
  const NEW = VCS.Figure;
  const OLD = VCS.FigureV016 || null;
  const Flags = VCS.Flags;
  const Vs = VCS.Vessels;
  try { if (VCS.Log && VCS.Log.setConsole) VCS.Log.setConsole(true); } catch (e) { /* ignore */ }
  try { Flags.register('vis.vessels', false, 'Circulatory pulse on villagers'); } catch (e) { /* already registered */ }
  document.getElementById('ver').textContent = 'v' + (VCS.Log && VCS.Log.VERSION ? VCS.Log.VERSION : '?') + ' figures' + (OLD ? ' (v0.16.0 copy loaded for before/after)' : '');

  const $ = (id) => document.getElementById(id);
  const S = { fx: 2, q: 3, zoom: 3, play: true, t: 0, speed: 1, seed: 1, parch: 'patron', sweep: false, rim: true, reduced: false, skel: false, graph: false, parts: false, vall: false };
  const ARCH = VCS.Forge.list();
  const VIEWS = [['front', Math.PI], ['3/4', Math.PI * 0.72], ['side', Math.PI * 0.5], ['back', 0.02]];
  const DIST = 2.2;
  // URL options (all optional): ?only=1,2 sections, &zoom=3, &cell=440, &fx=2, &t=1.5 (paused at t), &arch=child.
  const Q = {};
  try { new URLSearchParams(location.search).forEach((v, k) => { Q[k] = v; }); } catch (e) { /* sandboxed or no URL */ }
  const ONLY = Q.only ? Q.only.split(',').map(Number) : null;
  const want = (k) => !ONLY || ONLY.indexOf(k) >= 0;
  if (Q.zoom) S.zoom = Math.max(1, Math.min(4, Number(Q.zoom) || 3));
  if (Q.fx) S.fx = Math.max(0, Math.min(2, Number(Q.fx) || 0));
  if (Q.t) { S.t = Number(Q.t) || 0; S.play = false; }
  if (Q.arch) S.parch = Q.arch;
  for (const k of ['skel', 'graph', 'parts', 'vall', 'sweep', 'reduced']) if (Q[k]) S[k] = Q[k] === '1';
  if (Q.cell) document.documentElement.style.setProperty('--cell', Number(Q.cell) + 'px');

  // ---------------------------------------------------------------- renderer per zoom
  const RENDS = {};
  function rend() {
    let r = RENDS[S.zoom];
    if (!r) {
      const cv = document.createElement('canvas');
      cv.width = 640 * S.zoom; cv.height = 360 * S.zoom;
      r = R.create(cv, { renderScale: S.zoom, effects: 2, lineBoil: true });
      RENDS[S.zoom] = r;
    }
    r.reduced = S.reduced;
    return r;
  }

  function lookOf(arch, seed) {
    try {
      const g = VCS.Forge.generate({ archetype: arch, seed: seed }, { stateSeed: 99, index: seed, accOffset: 3 });
      return g && g.person && g.person.look ? g.person.look : null;
    } catch (e) { return null; }
  }
  function withLook(base, over) { return Object.assign({}, base, over); }

  // ---------------------------------------------------------------- echoes
  function echoOf(c, t) {
    const anim = !S.reduced && !c.still;
    const e = {
      x: c.dist || DIST, y: c.lat || 0, angle: c.angle === undefined ? Math.PI : c.angle, lookAngle: c.lookAngle || 0,
      phase: 0, phaseRate: 0, personId: c.pid || 3, t: 0, strength: 1, zMin: 0, zMax: 2, look: c.look, fade: 3,
      mode: c.mode || 'path', sit: !!c.sit, wary: !!c.wary, chat: !!c.chat, modeAge: c.modeAge === undefined ? 9 : c.modeAge
    };
    if (c.walk) e.phase = c.phase0 + (anim && !c.frame ? t * c.walk : 0);
    if (e.mode === 'startle' && c.hop && anim) e.modeAge = (t * 0.6) % 1.2;
    return e;
  }
  function beatOf(c, t) {
    const st = Vs.state('villager', c.vmode || 'calm', c.blood === undefined ? 1 : c.blood);
    const per = st.bpm > 0 ? 60 / st.bpm : 1;
    const age = c.beatAge !== undefined ? c.beatAge : (S.reduced ? 0.15 : t % per);
    return { st: st, age: age };
  }

  // ---------------------------------------------------------------- cell drawing
  function crop(r, c) {
    const d = c.dist || DIST;
    const vs = r.oh / d;
    const floorY = r.oh / 2 + 0.5 * vs;
    const half = (c.halfW || 0.58) * vs;
    const top = floorY - (c.topK || 1.12) * vs;
    const bot = floorY + (c.botK || 0.1) * vs;
    const cx = r.ow / 2 + (c.cropDx || 0) * vs;
    return { x: Math.round(cx - half), y: Math.round(top), w: Math.round(half * 2), h: Math.round(bot - top) };
  }

  function drawOne(r, c, t, fig) {
    const lights = S.rim ? [{ x: (c.dist || DIST) - 0.4, y: (c.lat || 0) - 0.9, radius: 1.2 }] : null;
    const vessels = !!(c.vessels || S.vall);
    try { Flags.set('vis.vessels', vessels); } catch (e) { /* ignore */ }
    VCS.Figure = fig;
    try {
      const e = echoOf(c, t);
      const sweepAge = S.sweep && !c.lock ? (t % 2.6) - 0.05 : -1;
      if (c.lock) {
        const lockAge = c.lock.age + (S.reduced || c.still ? 0 : (t % (c.lock.span || 3)));
        if (vessels) {
          const st = Vs.state('villager', 'drinking', 1 - c.lock.k);
          const per = st.bpm > 0 ? 60 / st.bpm : 1;
          e.vessel = st.pulse ? { bpm: st.bpm, stateK: st.stateK, periphK: st.periphK, headK: st.headK } : null;
          e.t = t - (S.reduced ? 0.15 : t % per);
        }
        R.drawSolo(r, e, { fx: S.fx, quality: S.q, t: t, lights: lights, lock: { k: c.lock.k, age: lockAge, rs: c.lock.rs || 0, sp: 9 } });
        return;
      }
      if (!c.beatOnly) R.drawSolo(r, e, { fx: S.fx, quality: S.q, t: t, age: sweepAge, lights: lights });
      if (vessels) {
        const b = beatOf(c, t);
        if (b.st.pulse) {
          const v = echoOf(c, t);
          v.kind = 'vheart'; v.zMin = 0.45; v.zMax = 0.85; v.bpm = b.st.bpm; v.stateK = b.st.stateK; v.periphK = b.st.periphK; v.headK = b.st.headK;
          R.drawSolo(r, v, { fx: S.fx, quality: S.q, t: t, age: b.age, lights: lights });
        }
      }
    } finally {
      VCS.Figure = NEW;
    }
  }

  function overlay(g, r, c, k, ox, oy) {
    const d = R.poseDebug();
    if (!d) return;
    const X = d.X; const Y = d.Y;
    const px = (i) => (X[i] - ox) * k;
    const py = (i) => (Y[i] - oy) * k;
    g.save();
    g.lineWidth = 1;
    if (S.parts && d.pose && d.pose.vol && NEW.parts) {
      const out = [];
      const n = NEW.parts({ X: d.X, Y: d.Y, Z: d.Z }, d.pose, d.pose.look, out);
      g.strokeStyle = 'rgba(120,255,160,0.85)';
      for (let i = 0; i < n; i++) {
        const p = out[i];
        if (!p.n) continue;
        g.beginPath();
        for (let j = 0; j < p.n; j++) { const x = (p.px[j] - ox) * k; const y = (p.py[j] - oy) * k; if (j) g.lineTo(x, y); else g.moveTo(x, y); }
        g.closePath();
        g.stroke();
      }
    }
    if (S.skel) {
      g.strokeStyle = 'rgba(120,200,255,0.8)';
      g.beginPath();
      const seg = (a, b) => { g.moveTo(px(a), py(a)); g.lineTo(px(b), py(b)); };
      seg(0, 1); seg(1, 2); seg(1, 3); seg(2, 4); seg(3, 5); seg(4, 5); seg(2, 3);
      for (const L of [[2, 10, 6], [3, 11, 7], [4, 12, 8], [5, 13, 9]]) { g.moveTo(px(L[0]), py(L[0])); g.quadraticCurveTo(px(L[1]), py(L[1]), px(L[2]), py(L[2])); }
      g.stroke();
      g.fillStyle = 'rgba(120,200,255,0.95)';
      g.font = Math.max(9, 10 * Math.min(1.4, k * S.zoom / 2)) + 'px ui-monospace, monospace';
      for (let i = 0; i <= 14; i++) { g.fillRect(px(i) - 2, py(i) - 2, 4, 4); if (S.zoom >= 2) g.fillText(String(i), px(i) + 3, py(i) - 3); }
    }
    if (S.graph && Vs) {
      const D = VCS.VesselData;
      const pt = { x: 0, y: 0 };
      const ctl = { x: 0, y: 0 };
      const nodes = D.arteries;
      g.strokeStyle = 'rgba(255,230,90,0.9)';
      g.beginPath();
      for (const ed of Vs.edges(false)) {
        const a = Vs.point(nodes[ed.p], X, Y, { x: 0, y: 0 });
        const b = Vs.point(nodes[ed.i], X, Y, { x: 0, y: 0 });
        g.moveTo((a.x - ox) * k, (a.y - oy) * k);
        if (Vs.edgeCtrl(nodes[ed.p], nodes[ed.i], X, Y, ctl)) g.quadraticCurveTo((ctl.x - ox) * k, (ctl.y - oy) * k, (b.x - ox) * k, (b.y - oy) * k);
        else g.lineTo((b.x - ox) * k, (b.y - oy) * k);
      }
      g.stroke();
      g.fillStyle = 'rgba(255,230,90,1)';
      for (const n of nodes) { Vs.point(n, X, Y, pt); g.beginPath(); g.arc((pt.x - ox) * k, (pt.y - oy) * k, 2.2, 0, Math.PI * 2); g.fill(); }
    }
    g.restore();
  }

  function paintCell(cell, t) {
    const r = rend();
    const o = r.octx;
    const specs = cell.lineup || [cell.spec];
    const c0 = specs[0];
    const box = crop(r, cell.box || c0);
    o.setTransform(1, 0, 0, 1, 0, 0);
    o.globalAlpha = 1;
    o.clearRect(box.x, box.y, box.w, box.h);
    for (const c of specs) drawOne(r, c, t, c.legacy && OLD ? OLD : NEW);
    const cv = cell.canvas;
    if (cv.width !== box.w || cv.height !== box.h) { cv.width = box.w; cv.height = box.h; }
    const g = cv.getContext('2d');
    g.setTransform(1, 0, 0, 1, 0, 0);
    g.globalAlpha = 1;
    g.fillStyle = '#000';
    g.fillRect(0, 0, box.w, box.h);
    g.drawImage(r.off, box.x, box.y, box.w, box.h, 0, 0, box.w, box.h);
    if (!cell.lineup && (S.skel || S.graph || S.parts)) overlay(g, r, c0, 1, box.x, box.y);
  }

  // ---------------------------------------------------------------- layout
  const CELLS = [];
  let observer = null;
  function addSection(title, note, cls) {
    const s = document.createElement('section');
    const h = document.createElement('h2');
    h.textContent = title;
    s.appendChild(h);
    if (note) { const p = document.createElement('p'); p.className = 'note'; p.textContent = note; s.appendChild(p); }
    const grid = document.createElement('div');
    grid.className = 'grid' + (cls ? ' ' + cls : '');
    s.appendChild(grid);
    main.appendChild(s);
    return grid;
  }
  function addCell(parent, caption, spec, extra) {
    const fig = document.createElement('figure');
    fig.className = 'cell';
    const cv = document.createElement('canvas');
    cv.width = 10; cv.height = 10;
    cv.setAttribute('role', 'img');
    cv.setAttribute('aria-label', caption);
    fig.appendChild(cv);
    const cap = document.createElement('figcaption');
    const parts = String(caption).split('|');
    const b = document.createElement('b');
    b.textContent = parts[0];
    cap.appendChild(b);
    if (parts[1]) cap.appendChild(document.createTextNode(' ' + parts[1]));
    fig.appendChild(cap);
    parent.appendChild(fig);
    const cell = Object.assign({ canvas: cv, spec: spec, visible: false, dirty: true }, extra || {});
    CELLS.push(cell);
    if (observer) observer.observe(fig); else cell.visible = true;
    fig._cell = cell;
    return cell;
  }

  function build() {
    CELLS.length = 0;
    while (main.firstChild) main.removeChild(main.firstChild);
    const seed = S.seed;
    const looks = {};
    ARCH.forEach((a, i) => { looks[a] = lookOf(a, (seed - 1) * ARCH.length + i + 1); });
    const base = looks[S.parch] || looks.patron;

    // 0. Game scale lineups (exact in-game size at Zoom 1x).
    if (want(0)) {
    const g0 = addSection('Game-scale lineup', 'All archetypes side by side at 2.5 and 1.5 cells, as the smoke lineup sees them. Pick Zoom 1x for true in-game pixel size.', 'wide');
    for (const d of [2.5, 1.5]) {
      for (let h = 0; h < 2; h++) {
        const ids = ARCH.slice(h * 7, h * 7 + 7);
        const step = d > 2 ? 0.36 : 0.24;
        const specs = ids.map((a, i) => ({ look: looks[a], dist: d, lat: (i - (ids.length - 1) / 2) * step, angle: Math.PI * (i % 2 ? 0.85 : 1), pid: h * 7 + i + 1 }));
        addCell(g0, 'Lineup|depth ' + d + ': ' + ids.join(', '), specs[0], { lineup: specs, box: { dist: d, halfW: (3.6 * step * 493 / d + 30) / (360 / d), topK: 1.1, botK: 0.1 } });
      }
    }

    }
    // 1. Archetypes x views.
    if (want(1)) {
    const g1 = addSection('1. Archetypes', 'Every archetype (seed ' + seed + ') front, three-quarter, side and back. Idle fidgets run with time.');
    for (const a of ARCH) for (const v of VIEWS) addCell(g1, a + '|' + v[0], { look: looks[a], angle: v[1], pid: ARCH.indexOf(a) + 1 });

    }
    // 2. Pose modes.
    if (want(2)) {
    const g2 = addSection('2. Pose modes', 'Look: ' + S.parch + '. Walk and flee show 8 fixed phases (3/4 view); the held victim runs the struggle timeline with the vampire grab arms.');
    const P = (cap, o) => addCell(g2, cap, Object.assign({ look: base, angle: Math.PI * 0.8, pid: 4 }, o));
    P('idle|front', { angle: Math.PI });
    P('idle|3/4', {});
    P('wary|clasped hands', { wary: true });
    P('chat|gesture', { chat: true });
    P('walk|animated', { walk: 6, phase0: 0.3 });
    for (let k = 0; k < 8; k++) P('walk|phase ' + k + '/8', { walk: 6, phase0: 0.05 + k * Math.PI / 4, frame: true });
    P('flee|animated', { mode: 'flee', walk: 8, phase0: 0.3, angle: Math.PI * 0.6 });
    for (let k = 0; k < 8; k++) P('flee|phase ' + k + '/8', { mode: 'flee', walk: 8, phase0: 0.05 + k * Math.PI / 4, frame: true, angle: Math.PI * 0.6 });
    P('startle|hop loop', { mode: 'startle', hop: true });
    P('startle|frozen', { mode: 'startle', modeAge: 2 });
    P('cower|', { mode: 'cower', angle: Math.PI });
    P('dazed|', { mode: 'dazed', angle: Math.PI });
    P('seated|front', { sit: true, angle: Math.PI });
    P('seated|side', { sit: true, angle: Math.PI * 0.5 });
    P('fed|slumped', { mode: 'fed', angle: Math.PI * 0.85 });
    P('held|panic', { lock: { k: 0.1, age: 0.3, span: 3 }, angle: Math.PI, dist: 1.25, halfW: 0.75, topK: 1.05, botK: 0.55 });
    P('held|push away', { lock: { k: 0.4, age: 5, span: 6 }, angle: Math.PI, dist: 1.25, halfW: 0.75, topK: 1.05, botK: 0.55 });
    P('held|restrained', { lock: { k: 0.5, age: 5, span: 6, rs: 1 }, angle: Math.PI, dist: 1.25, halfW: 0.75, topK: 1.05, botK: 0.55 });
    P('held|limp', { lock: { k: 0.95, age: 12, span: 4 }, angle: Math.PI, dist: 1.25, halfW: 0.75, topK: 1.05, botK: 0.55 });

    }
    // 3. Body x head x hair x hat.
    if (want(3)) {
    const g3 = addSection('3. Body x head matrix', 'Rows are body types (bean, pear, stick, round, box), columns head types; hair and hat cycle along the grid. Then each hat, hair, outfit and role item on a bean.');
    const AD = VCS.ArchetypeData;
    const BOD = AD.LOOK_ENUMS.body; const HEADS = AD.LOOK_ENUMS.head; const HAIR = AD.LOOK_ENUMS.hair; const HATS = AD.LOOK_ENUMS.hat;
    const plain = withLook(looks.patron, { outfit: 'plain', roleHat: 'none', extra: 'none', coat: false, prop: 'none', acc: 'none', beard: false, stoop: 0, shoulder: 1, height: 1, build: 1 });
    BOD.forEach((b, i) => HEADS.forEach((h, j) => {
      const hair = HAIR[(i + j * 2) % HAIR.length];
      const hat = HATS[(i * 2 + j) % HATS.length];
      addCell(g3, b + ' / ' + h + '|' + hair + ', ' + hat, { look: withLook(plain, { body: b, head: h, hair: hair, hat: hat, beard: (i + j) % 3 === 0 }), angle: Math.PI * (j % 2 ? 0.75 : 1), pid: i * 4 + j + 1 });
    }));
    HATS.forEach((h, i) => addCell(g3, 'hat|' + h, { look: withLook(plain, { hat: h, hair: 'none' }), angle: Math.PI * 0.85, pid: 30 + i }));
    HAIR.forEach((h, i) => addCell(g3, 'hair|' + h, { look: withLook(plain, { hair: h }), angle: Math.PI * 0.85, pid: 40 + i }));
    AD.LOOK_ENUMS.outfit.forEach((o, i) => addCell(g3, 'outfit|' + o, { look: withLook(plain, { outfit: o, hem: o === 'robe' ? 1 : 0.5 }), angle: Math.PI * 0.85, pid: 50 + i }));
    [['kettle', {}], ['biretta', {}]].forEach((rh, i) => addCell(g3, 'role hat|' + rh[0], { look: withLook(plain, { roleHat: rh[0] }), angle: Math.PI * 0.85, pid: 60 + i }));
    AD.LOOK_ENUMS.extra.slice(1).forEach((x, i) => addCell(g3, 'item|' + x, { look: withLook(plain, { extra: x }), angle: Math.PI * 0.85, pid: 70 + i }));
    AD.LOOK_ENUMS.prop.slice(1).forEach((x, i) => addCell(g3, 'prop|' + x, { look: withLook(plain, { prop: x }), angle: Math.PI * 0.85, pid: 80 + i }));
    [['shoulder 0.8', { shoulder: 0.8 }], ['shoulder 1.25', { shoulder: 1.25 }], ['build 0.7', { build: 0.7 }], ['build 1.4', { build: 1.4 }], ['stoop 0.4', { stoop: 0.4 }], ['height 0.58 (child)', { height: 0.58 }], ['height 1.2', { height: 1.2 }], ['coat + scarf', { coat: true, acc: 'scarf' }]]
      .forEach((x, i) => addCell(g3, 'look|' + x[0], { look: withLook(plain, x[1]), angle: Math.PI * 0.8, pid: 90 + i }));

    }
    // 4. Circulation.
    if (want(4)) {
    const g4 = addSection('4. Circulation', 'Vessel overlay with the travelling lub-dub pulse on the new bodies (vis.vessels on for this panel). Flush shows at Effects 2. Fixed beat ages, then blood 1 / 0.5 / 0.15, then fear modes. Toggle "vessel graph" and "skeleton slots" to see the anatomy.');
    const C = (cap, o) => addCell(g4, cap, Object.assign({ look: base, angle: Math.PI, pid: 5, vessels: true }, o));
    C('beat|live', {});
    C('beat|side live', { angle: Math.PI * 0.5 });
    C('beat|back live', { angle: 0.02 });
    for (const a of [0.03, 0.1, 0.2, 0.35, 0.55]) C('beat age|' + a + ' s', { beatAge: a });
    for (const bl of [1, 0.5, 0.15]) C('blood|' + bl, { blood: bl });
    C('flee|130 bpm', { mode: 'flee', vmode: 'flee', walk: 8, phase0: 0.3, angle: Math.PI * 0.7 });
    C('cower|', { mode: 'cower', vmode: 'cower' });
    C('seated|', { sit: true, angle: Math.PI * 0.6 });
    C('fed|(no pulse)', { mode: 'fed', vmode: 'fed' });
    C('held|drinking beat', { lock: { k: 0.5, age: 5, span: 6 }, dist: 1.25, halfW: 0.75, topK: 1.05, botK: 0.55 });
    C('child|', { look: looks.child, angle: Math.PI * 0.8 });
    C('priest robe|', { look: looks.priest, angle: Math.PI * 0.8 });
    C('guard mail|', { look: looks.guard, angle: Math.PI * 0.8 });
    C('heartbeat only|outline is the chest strip', { beatOnly: true });

    }
    // 5. Before / after.
    if (want(5)) {
    const g5 = addSection('5. Before / after', OLD ? 'Left: the v0.16.0 figure (tools/figure-v016.js, a copy of git 9460bc0:js/figure.js). Right: this build. Same pose slots (the v0.17 child-width tweak applies to both).' : 'v0.16 copy not loaded.', 'pairs');
    for (const a of ARCH) {
      for (const v of [VIEWS[0], VIEWS[1]]) {
        const pair = document.createElement('div');
        pair.className = 'pair';
        g5.appendChild(pair);
        const spec = { look: looks[a], angle: v[1], pid: ARCH.indexOf(a) + 1 };
        if (OLD) addCell(pair, 'v0.16|' + a + ' ' + v[0], Object.assign({ legacy: true }, spec));
        addCell(pair, 'v0.17|' + a + ' ' + v[0], spec);
      }
    }
    }
  }

  // ---------------------------------------------------------------- loop
  let last = 0;
  let frames = 0;
  window.__sheet = {
    frames: () => frames, cells: () => CELLS.length, errors: [],
    /** Paint every cell now (also the off-screen ones), at time t when given. For screenshots. */
    paintAll: (t) => { if (typeof t === 'number') S.t = t; for (const c of CELLS) paintCell(c, S.t); return CELLS.length; }
  };
  function tick(now) {
    const dt = last ? Math.min(0.1, (now - last) / 1000) : 0;
    last = now;
    if (S.play) {
      S.t = (S.t + dt * S.speed) % 20;
      $('time').value = S.t.toFixed(2);
    }
    $('tval').textContent = S.t.toFixed(2) + ' s';
    for (const c of CELLS) {
      if (!c.visible) continue;
      if (!S.play && !c.dirty) continue;
      try { paintCell(c, S.t); } catch (e) { if (window.__sheet.errors.length < 5) { window.__sheet.errors.push(String(e && e.stack || e)); console.error(e); } }
      c.dirty = false;
    }
    frames++;
    requestAnimationFrame(tick);
  }
  function dirtyAll() { for (const c of CELLS) c.dirty = true; }

  function bind() {
    const sel = $('parch');
    for (const a of ARCH) { const o = document.createElement('option'); o.value = a; o.textContent = a; sel.appendChild(o); }
    sel.value = S.parch;
    $('fx').value = String(S.fx); $('zoom').value = String(S.zoom);
    for (const k of ['skel', 'graph', 'parts', 'vall', 'sweep', 'reduced']) $(k).checked = !!S[k];
    $('play').textContent = S.play ? 'Pause' : 'Play';
    const num = (id, key, rebuild) => $(id).addEventListener('change', (ev) => { S[key] = Number(ev.target.value); if (rebuild) build(); dirtyAll(); });
    num('fx', 'fx'); num('q', 'q'); num('zoom', 'zoom'); num('speed', 'speed'); num('seed', 'seed', true);
    sel.addEventListener('change', (ev) => { S.parch = ev.target.value; build(); dirtyAll(); });
    $('cellsz').addEventListener('change', (ev) => document.documentElement.style.setProperty('--cell', ev.target.value + 'px'));
    for (const k of ['sweep', 'rim', 'reduced', 'skel', 'graph', 'parts', 'vall']) $(k).addEventListener('change', (ev) => { S[k] = !!ev.target.checked; dirtyAll(); });
    $('play').addEventListener('click', () => { S.play = !S.play; $('play').textContent = S.play ? 'Pause' : 'Play'; dirtyAll(); });
    $('time').addEventListener('input', (ev) => { S.t = Number(ev.target.value); S.play = false; $('play').textContent = 'Play'; dirtyAll(); });
  }

  if (typeof IntersectionObserver === 'function') {
    observer = new IntersectionObserver((ents) => {
      for (const en of ents) { const c = en.target._cell; if (c) { c.visible = en.isIntersecting; c.dirty = true; } }
    }, { rootMargin: '200px' });
  }
  bind();
  build();
  requestAnimationFrame(tick);
})();
