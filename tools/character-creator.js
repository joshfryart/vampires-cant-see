// Character creator page (tools/character-creator.html). Draws the REAL game figure through Render.drawSolo (the same
// drawPerson path the game and the figure sheet use), so art changes in js/figure.js and js/render.js show up here
// with no copy of drawing code. Data, validation and storage live in tools/character-creator-core.js (VCS.Creator).
(function () {
  'use strict';
  const VCS = window.VCS || {};
  const C = VCS.Creator;
  const R = VCS.Render;
  const Flags = VCS.Flags;
  const Vs = VCS.Vessels;
  const $ = (id) => document.getElementById(id);
  const statusEl = $('status');

  function say(msg, bad) {
    statusEl.textContent = msg;
    statusEl.className = 'cc-status' + (bad ? ' cc-err' : '');
  }
  if (!C || !R || !VCS.Figure || !VCS.Forge) { say('Game modules failed to load. Open this page from the repo (tools/ next to js/).', true); return; }
  try { Flags.register('vis.vessels', false, 'Circulatory pulse on villagers'); } catch (e) { /* already registered */ }
  $('ver').textContent = 'v' + (VCS.Log && VCS.Log.VERSION ? VCS.Log.VERSION : '?');

  function storage() { try { return window.localStorage || null; } catch (e) { return null; } }

  // ---------------------------------------------------------------- state
  const ARCH = C.archetypes();
  const S = {
    arch: 'patron', seed: 1, name: 'Villager', look: null, view: C.sanitizeView({}), locks: Object.create(null),
    saved: [], t: 0, errors: [], frames: 0
  };
  const draft = C.loadDraft(storage());
  if (draft) {
    S.arch = draft.archetype; S.seed = draft.seed; S.name = draft.name; S.look = draft.look; S.view = draft.view;
  }
  if (!S.look) S.look = C.preset(S.arch, S.seed);
  if (!ARCH.some((a) => a.id === S.arch)) S.arch = 'patron';
  const st = C.loadStore(storage());
  S.saved = st.list;
  if (!st.ok) say('Saved characters could not be read (' + st.code + ').', true);

  let draftTimer = 0;
  function touch() {
    if (draftTimer) clearTimeout(draftTimer);
    draftTimer = setTimeout(() => { draftTimer = 0; C.saveDraft(storage(), { look: S.look, archetype: S.arch, seed: S.seed, name: S.name, view: S.view }); }, 300);
  }

  // ---------------------------------------------------------------- renderers
  const RENDS = {};
  function rend(scale) {
    let r = RENDS[scale];
    if (!r) {
      const cv = document.createElement('canvas');
      cv.width = 640 * scale; cv.height = 360 * scale;
      r = R.create(cv, { renderScale: scale, effects: 2, lineBoil: true });
      RENDS[scale] = r;
    }
    r.reduced = S.view.reduced;
    return r;
  }

  /** Draw one figure (body, then the heart echo when circulation is on) into r.octx. */
  function drawFig(r, look, pose, o) {
    const v = S.view;
    const t = S.t;
    const pe = C.poseEcho(pose, look, { t: t, yaw: o.yaw, dist: o.dist, lat: o.lat || 0, personId: o.pid || 4, reduced: v.reduced, struggle: v.struggle, restrain: v.restrain });
    const e = pe.echo;
    const lights = v.rim ? [{ x: e.x - 0.4, y: e.y - 0.9, radius: 1.2 }] : null;
    const vessels = !!(v.vessels && o.vessels !== false);
    try { Flags.set('vis.vessels', vessels); } catch (err) { /* ignore */ }
    const base = { fx: v.fx, quality: v.quality, t: t, lights: lights };
    if (pe.lock) {
      if (vessels && Vs) {
        const sv = Vs.state('villager', 'drinking', 1 - pe.lock.k);
        const per = sv.bpm > 0 ? 60 / sv.bpm : 1;
        e.vessel = sv.pulse ? { bpm: sv.bpm, stateK: sv.stateK, periphK: sv.periphK, headK: sv.headK } : null;
        e.t = t - (v.reduced ? 0.15 : t % per);
      }
      R.drawSolo(r, e, Object.assign(base, { lock: pe.lock }));
      return e;
    }
    R.drawSolo(r, e, Object.assign({ age: -1 }, base));
    if (vessels && Vs) {
      const sv = Vs.state('villager', pe.vmode, 1);
      if (sv.pulse) {
        const per = sv.bpm > 0 ? 60 / sv.bpm : 1;
        const h = C.poseEcho(pose, look, { t: t, yaw: o.yaw, dist: o.dist, lat: o.lat || 0, personId: o.pid || 4, reduced: v.reduced }).echo;
        h.kind = 'vheart'; h.zMin = 0.45; h.zMax = 0.85; h.bpm = sv.bpm; h.stateK = sv.stateK; h.periphK = sv.periphK; h.headK = sv.headK;
        R.drawSolo(r, h, Object.assign({}, base, { age: v.reduced ? 0.15 : t % per }));
      }
    }
    return e;
  }

  function cropBox(r, dist, halfW, topK, botK, dx) {
    const vs = r.oh / dist;
    const floorY = r.oh / 2 + 0.5 * vs;
    const half = halfW * vs;
    const cx = r.ow / 2 + (dx || 0) * vs;
    const x = Math.max(0, Math.round(cx - half));
    const y = Math.max(0, Math.round(floorY - topK * vs));
    const w = Math.min(r.ow - x, Math.round(half * 2));
    const h = Math.min(r.oh - y, Math.round((topK + botK) * vs));
    return { x: x, y: y, w: Math.max(1, w), h: Math.max(1, h) };
  }

  function blit(cv, r, box) {
    if (cv.width !== box.w || cv.height !== box.h) { cv.width = box.w; cv.height = box.h; }
    const g = cv.getContext('2d');
    g.setTransform(1, 0, 0, 1, 0, 0);
    g.globalAlpha = 1;
    g.fillStyle = '#000';
    g.fillRect(0, 0, box.w, box.h);
    g.drawImage(r.off, box.x, box.y, box.w, box.h, 0, 0, box.w, box.h);
    return g;
  }
  function clearBox(r, box) {
    const o = r.octx;
    o.setTransform(1, 0, 0, 1, 0, 0);
    o.globalAlpha = 1;
    o.clearRect(box.x, box.y, box.w, box.h);
  }

  function overlay(g, ox, oy) {
    const v = S.view;
    if (!v.skel && !v.graph && !v.parts) return;
    const d = R.poseDebug();
    if (!d) return;
    const X = d.X; const Y = d.Y;
    const px = (i) => X[i] - ox;
    const py = (i) => Y[i] - oy;
    g.save();
    g.lineWidth = 1;
    if (v.parts && d.pose && d.pose.vol && VCS.Figure.parts) {
      const out = [];
      const n = VCS.Figure.parts({ X: d.X, Y: d.Y, Z: d.Z }, d.pose, d.pose.look, out);
      g.strokeStyle = 'rgba(120,255,160,0.85)';
      for (let i = 0; i < n; i++) {
        const p = out[i];
        if (!p || !p.n) continue;
        g.beginPath();
        for (let j = 0; j < p.n; j++) { const x = p.px[j] - ox; const y = p.py[j] - oy; if (j) g.lineTo(x, y); else g.moveTo(x, y); }
        g.closePath();
        g.stroke();
      }
    }
    if (v.skel) {
      g.strokeStyle = 'rgba(120,200,255,0.8)';
      g.beginPath();
      const seg = (a, b) => { g.moveTo(px(a), py(a)); g.lineTo(px(b), py(b)); };
      seg(0, 1); seg(1, 2); seg(1, 3); seg(2, 4); seg(3, 5); seg(4, 5); seg(2, 3);
      for (const L of [[2, 10, 6], [3, 11, 7], [4, 12, 8], [5, 13, 9]]) { g.moveTo(px(L[0]), py(L[0])); g.quadraticCurveTo(px(L[1]), py(L[1]), px(L[2]), py(L[2])); }
      g.stroke();
      g.fillStyle = 'rgba(120,200,255,0.95)';
      g.font = (8 + 2 * v.zoom) + 'px ui-monospace, monospace';
      for (let i = 0; i <= 14; i++) { g.fillRect(px(i) - 2, py(i) - 2, 4, 4); if (v.zoom >= 2) g.fillText(String(i), px(i) + 3, py(i) - 3); }
    }
    if (v.graph && Vs && VCS.VesselData) {
      const nodes = VCS.VesselData.arteries;
      const a = { x: 0, y: 0 }; const b = { x: 0, y: 0 }; const ctl = { x: 0, y: 0 };
      g.strokeStyle = 'rgba(255,230,90,0.9)';
      g.beginPath();
      for (const ed of Vs.edges(false)) {
        Vs.point(nodes[ed.p], X, Y, a);
        Vs.point(nodes[ed.i], X, Y, b);
        g.moveTo(a.x - ox, a.y - oy);
        if (Vs.edgeCtrl(nodes[ed.p], nodes[ed.i], X, Y, ctl)) g.quadraticCurveTo(ctl.x - ox, ctl.y - oy, b.x - ox, b.y - oy);
        else g.lineTo(b.x - ox, b.y - oy);
      }
      g.stroke();
      g.fillStyle = 'rgba(255,230,90,1)';
      for (const n of nodes) { Vs.point(n, X, Y, a); g.beginPath(); g.arc(a.x - ox, a.y - oy, 2.2, 0, Math.PI * 2); g.fill(); }
    }
    g.restore();
  }

  // ---------------------------------------------------------------- painting
  const NEIGHBOURS = ['patron', 'guard', null, 'child', 'priest'];
  const neighbourLooks = NEIGHBOURS.map((a, i) => (a ? C.preset(a, i + 3) : null));
  const VIEWS = [['Front', 0], ['3/4', -0.28 * Math.PI], ['Side', -0.5 * Math.PI], ['Back', Math.PI * 0.98]];
  const viewCells = [];

  function paintPreview() {
    const v = S.view;
    const r = rend(v.zoom);
    const held = v.pose === 'held';
    const box = held ? cropBox(r, 1.25, 0.8, 1.08, 0.55) : cropBox(r, v.dist, 0.72, 1.36, 0.14);
    clearBox(r, box);
    drawFig(r, S.look, v.pose, { yaw: v.yaw, dist: v.dist, pid: 4 });
    const g = blit($('preview'), r, box);
    overlay(g, box.x, box.y);
  }

  function paintViews() {
    const r = rend(2);
    const pose = S.view.pose === 'held' ? 'idle' : S.view.pose;
    const box = cropBox(r, 2.2, 0.62, 1.3, 0.12);
    for (let i = 0; i < VIEWS.length; i++) {
      clearBox(r, box);
      drawFig(r, S.look, pose, { yaw: VIEWS[i][1], dist: 2.2, pid: 4 });
      blit(viewCells[i], r, box);
    }
  }

  function paintGame() {
    const r = rend(1);
    const gs = S.view.gameScale;
    const pose = S.view.pose === 'held' ? 'idle' : S.view.pose;
    // Lineup: five villagers 0.36 cells apart at depth 2.5, you in the middle.
    const d = 2.5; const step = 0.36;
    const box = cropBox(r, d, 1.369 * step * 2 + 0.62, 1.3, 0.12);
    clearBox(r, box);
    NEIGHBOURS.forEach((a, i) => {
      const lat = (i - 2) * step;
      if (a) drawFig(r, neighbourLooks[i], 'idle', { yaw: i % 2 ? -0.5 : 0.4, dist: d, lat: lat, pid: 10 + i, vessels: false });
      else drawFig(r, S.look, pose, { yaw: S.view.yaw, dist: d, lat: lat, pid: 4 });
    });
    const lc = $('lineup');
    blit(lc, r, box);
    lc.style.width = (box.w * gs) + 'px';
    lc.style.height = (box.h * gs) + 'px';
    // Full frame: you at four depths, far to near, like the game draws its echoes.
    const full = { x: 0, y: 0, w: r.ow, h: r.oh };
    clearBox(r, full);
    [[7, -0.6], [4, 2.0], [2.6, -1.2], [1.6, 0.35]].forEach((p, i) => drawFig(r, S.look, pose, { yaw: S.view.yaw + i * 0.6, dist: p[0], lat: p[1], pid: 20 + i }));
    const fc = $('frame');
    blit(fc, r, full);
    fc.style.width = (full.w * gs) + 'px';
    fc.style.height = (full.h * gs) + 'px';
  }

  let last = 0;
  function tick(now) {
    const dt = last ? Math.min(0.1, (now - last) / 1000) : 0;
    last = now;
    const v = S.view;
    if (v.play) S.t = (S.t + dt * v.speed) % 600;
    if (v.spin && !dragging) { v.yaw = wrapYaw(v.yaw + dt * 0.6 * (v.speed || 1)); syncYaw(); }
    try {
      paintPreview();
      if ((S.frames & 1) === 0) paintViews();
      if ((S.frames & 1) === 1) paintGame();
    } catch (e) {
      if (S.errors.length < 5) { S.errors.push(String(e && e.stack || e)); console.error(e); }
    }
    S.frames++;
    requestAnimationFrame(tick);
  }

  // ---------------------------------------------------------------- controls
  function el(tag, cls, text) {
    const e = document.createElement(tag);
    if (cls) e.className = cls;
    if (text !== undefined) e.textContent = text;
    return e;
  }
  function button(label, fn, cls) {
    const b = el('button', cls, label);
    b.type = 'button';
    b.addEventListener('click', fn);
    return b;
  }
  function wrapYaw(y) { return C.sanitizeView({ yaw: y }).yaw; }

  const CTL = Object.create(null);
  function buildFields() {
    const host = $('fields');
    host.textContent = '';
    let group = null;
    let sec = null;
    C.fields().forEach((f) => {
      if (f.group !== group) {
        group = f.group;
        sec = el('div', 'cc-group');
        sec.appendChild(el('h2', null, group));
        host.appendChild(sec);
      }
      const row = el('div', 'cc-row');
      const id = 'f-' + f.key;
      const lab = el('label', null, f.label);
      lab.htmlFor = id;
      row.appendChild(lab);
      const ctl = el('span', 'cc-ctl');
      let input; let out = null;
      if (f.type === 'num') {
        input = el('input');
        input.type = 'range';
        input.min = String(f.min); input.max = String(f.max); input.step = String(f.step);
        out = el('output', 'cc-val');
        input.addEventListener('input', () => edit(f.key, Number(input.value)));
        ctl.appendChild(input); ctl.appendChild(out);
      } else if (f.type === 'enum') {
        input = el('select');
        f.values.forEach((v) => { const o = el('option', null, v); o.value = v; input.appendChild(o); });
        input.addEventListener('change', () => edit(f.key, input.value));
        ctl.appendChild(input);
      } else {
        input = el('input');
        input.type = 'checkbox';
        input.addEventListener('change', () => edit(f.key, input.checked));
        ctl.appendChild(input);
      }
      input.id = id;
      row.appendChild(ctl);
      const lock = el('label', 'cc-lock');
      lock.title = 'Keep this field when randomizing';
      const lk = el('input');
      lk.type = 'checkbox';
      lk.setAttribute('aria-label', 'Lock ' + f.label);
      lk.checked = !!S.locks[f.key];
      lk.addEventListener('change', () => { S.locks[f.key] = lk.checked; });
      lock.appendChild(lk);
      lock.appendChild(document.createTextNode('lock'));
      row.appendChild(lock);
      const hint = el('div', 'cc-hint', f.hint);
      if (!f.hint) hint.hidden = true;
      row.appendChild(hint);
      sec.appendChild(row);
      CTL[f.key] = { f: f, input: input, out: out, row: row, hint: hint };
    });
  }

  function syncFields() {
    Object.keys(CTL).forEach((k) => {
      const c = CTL[k];
      const v = C.getField(S.look, k);
      if (c.f.type === 'num') { c.input.value = String(v); c.out.textContent = Number(v).toFixed(2); }
      else if (c.f.type === 'bool') c.input.checked = !!v;
      else c.input.value = String(v);
    });
    const hair = CTL.hair;
    if (hair) {
      const hid = C.hairHidden(S.look);
      hair.row.classList.toggle('cc-off', hid);
      hair.hint.hidden = !hid;
      hair.hint.textContent = hid ? 'In game the Forge hides hair under a ' + S.look.hat + '.' : '';
    }
    const hat = CTL.hat;
    if (hat) hat.row.classList.toggle('cc-off', S.look.roleHat !== 'none');
    $('c-arch').value = S.arch;
    $('c-seed').value = String(S.seed);
    if (document.activeElement !== $('c-name')) $('c-name').value = S.name;
  }

  function edit(key, value) {
    S.look = C.setField(S.look, key, value);
    syncFields();
    touch();
  }

  function applyPreset(msg) {
    S.look = C.preset(S.arch, S.seed);
    syncFields();
    touch();
    say(msg || 'Preset ' + S.arch + ' seed ' + S.seed + '.');
  }

  function syncView() {
    const v = S.view;
    $('v-pose').value = v.pose;
    $('v-play').textContent = v.play ? 'Pause' : 'Play';
    $('v-speed').value = String(v.speed);
    $('v-fx').value = String(v.fx);
    $('v-quality').value = String(v.quality);
    $('v-zoom').value = String(v.zoom);
    $('v-dist').value = String(v.dist);
    $('o-dist').textContent = v.dist.toFixed(2);
    $('v-struggle').value = String(v.struggle);
    $('v-gscale').value = String(v.gameScale);
    for (const k of ['spin', 'rim', 'vessels', 'skel', 'graph', 'parts', 'reduced', 'restrain']) $('v-' + k).checked = !!v[k];
    for (const n of document.querySelectorAll('.cc-held')) n.hidden = v.pose !== 'held';
    $('v-dist').disabled = v.pose === 'held';
    syncYaw();
  }
  function syncYaw() {
    const deg = Math.round(S.view.yaw * 180 / Math.PI);
    $('v-yaw').value = String(deg);
    $('o-yaw').textContent = deg + '°';
  }
  function setView(patch) {
    S.view = C.sanitizeView(Object.assign({}, S.view, patch));
    syncView();
    touch();
  }

  function renderSaved() {
    const ul = $('saved');
    ul.textContent = '';
    if (!S.saved.length) { ul.appendChild(el('li', 'cc-empty', 'Nothing saved yet.')); return; }
    S.saved.forEach((c) => {
      const li = el('li');
      li.appendChild(el('span', 'cc-name', c.name));
      li.appendChild(el('span', 'cc-meta', c.archetype + ' #' + c.seed));
      li.appendChild(button('Load', () => {
        S.look = C.sanitize(c.look).look; S.arch = ARCH.some((a) => a.id === c.archetype) ? c.archetype : 'patron'; S.seed = c.seed; S.name = c.name;
        $('c-name').value = S.name;
        syncFields(); touch(); say('Loaded ' + c.name + '.');
      }, 'cc-small'));
      const del = button('Delete', () => {
        if (del.dataset.armed !== '1') { del.dataset.armed = '1'; del.textContent = 'Sure?'; setTimeout(() => { del.dataset.armed = ''; del.textContent = 'Delete'; }, 2500); return; }
        S.saved = C.remove(S.saved, c.name);
        persist('Deleted ' + c.name + '.');
      }, 'cc-small cc-danger');
      li.appendChild(del);
      ul.appendChild(li);
    });
  }
  function persist(msg) {
    const r = C.saveStore(storage(), S.saved);
    renderSaved();
    say(r.ok ? msg : msg + ' (not stored in this browser: ' + r.code + ')', !r.ok);
  }

  function current() { return C.character(S.name, S.look, { archetype: S.arch, seed: S.seed }); }
  function slug(s) { return String(s).toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '') || 'character'; }
  function download(name, blob) {
    try {
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url; a.download = name;
      document.body.appendChild(a);
      a.click();
      a.remove();
      setTimeout(() => URL.revokeObjectURL(url), 2000);
      return true;
    } catch (e) {
      return false;
    }
  }
  function exportText(text, file) {
    $('c-json').value = text;
    const ok = download(file, new Blob([text], { type: 'application/json' }));
    say(ok ? 'Exported ' + file + ' (also shown in the JSON box).' : 'Download blocked; copy the JSON from the box.');
  }
  function importText(text, from) {
    const r = C.importJSON(text);
    if (!r.ok) { say('Import from ' + from + ' failed: ' + r.code + '.', true); return; }
    r.list.slice().reverse().forEach((c) => { S.saved = C.upsert(S.saved, c); });
    const first = r.list[0];
    S.look = first.look; S.arch = ARCH.some((a) => a.id === first.archetype) ? first.archetype : 'patron'; S.seed = first.seed; S.name = first.name;
    $('c-name').value = S.name;
    syncFields(); touch();
    persist('Imported ' + r.list.length + ' character(s)' + (r.skipped ? ', skipped ' + r.skipped : '') + '; loaded ' + first.name + '.');
  }

  let dragging = false;
  function bind() {
    const ps = $('v-pose');
    C.POSES.forEach((p) => { const o = el('option', null, p.label); o.value = p.id; ps.appendChild(o); });
    ps.addEventListener('change', () => setView({ pose: ps.value }));
    $('v-play').addEventListener('click', () => setView({ play: !S.view.play }));
    $('v-speed').addEventListener('change', (e) => setView({ speed: Number(e.target.value) }));
    $('v-struggle').addEventListener('input', (e) => setView({ struggle: Number(e.target.value) }));
    $('v-yaw').addEventListener('input', (e) => setView({ yaw: Number(e.target.value) * Math.PI / 180, spin: false }));
    for (const b of document.querySelectorAll('[data-yaw]')) b.addEventListener('click', () => setView({ yaw: Number(b.dataset.yaw) * Math.PI / 180, spin: false }));
    $('v-fx').addEventListener('change', (e) => setView({ fx: Number(e.target.value) }));
    $('v-quality').addEventListener('change', (e) => setView({ quality: Number(e.target.value) }));
    $('v-zoom').addEventListener('change', (e) => setView({ zoom: Number(e.target.value) }));
    $('v-dist').addEventListener('input', (e) => setView({ dist: Number(e.target.value) }));
    $('v-gscale').addEventListener('change', (e) => setView({ gameScale: Number(e.target.value) }));
    for (const k of ['spin', 'rim', 'vessels', 'skel', 'graph', 'parts', 'reduced', 'restrain']) {
      $('v-' + k).addEventListener('change', (e) => { const p = {}; p[k] = !!e.target.checked; setView(p); });
    }
    $('v-png').addEventListener('click', () => {
      const cv = $('preview');
      if (!cv.toBlob) { say('PNG export is not supported here.', true); return; }
      cv.toBlob((b) => { if (b && download(slug(S.name) + '.png', b)) say('Saved ' + slug(S.name) + '.png.'); else say('PNG export failed.', true); }, 'image/png');
    });

    // Drag to turn.
    const stage = $('stage');
    let lastX = 0;
    stage.addEventListener('pointerdown', (e) => { dragging = true; lastX = e.clientX; stage.classList.add('dragging'); try { stage.setPointerCapture(e.pointerId); } catch (err) { /* ignore */ } });
    stage.addEventListener('pointermove', (e) => {
      if (!dragging) return;
      const dx = e.clientX - lastX;
      lastX = e.clientX;
      S.view.yaw = wrapYaw(S.view.yaw + dx * 0.012);
      syncYaw();
    });
    const end = () => { if (dragging) { dragging = false; stage.classList.remove('dragging'); touch(); } };
    stage.addEventListener('pointerup', end);
    stage.addEventListener('pointercancel', end);

    // Start from.
    const as = $('c-arch');
    ARCH.forEach((a) => { const o = el('option', null, a.label + (a.label.toLowerCase() === a.id ? '' : ' (' + a.id + ')')); o.value = a.id; as.appendChild(o); });
    as.addEventListener('change', () => { S.arch = as.value; applyPreset(); });
    $('c-seed').addEventListener('change', (e) => { S.seed = C.cleanSeed(e.target.value); applyPreset(); });
    $('c-seed-rand').addEventListener('click', () => { S.seed = Math.floor(Math.random() * 65536); applyPreset(); });
    $('c-preset').addEventListener('click', () => applyPreset());
    $('c-rand-arch').addEventListener('click', () => {
      const r = C.randomize(Object.assign({}, S.look, { archetype: S.arch }), { mode: 'archetype', locks: S.locks });
      S.look = r.look; S.seed = r.seed;
      syncFields(); touch(); say('Random ' + S.arch + ' (seed ' + S.seed + ').');
    });
    $('c-rand-wild').addEventListener('click', () => {
      S.look = C.randomize(S.look, { mode: 'wild', locks: S.locks }).look;
      syncFields(); touch(); say('Wild random look.');
    });

    // Saving and JSON.
    const nameIn = $('c-name');
    nameIn.addEventListener('input', () => { S.name = C.cleanName(nameIn.value); touch(); });
    nameIn.addEventListener('keydown', (e) => { if (e.key === 'Enter') $('c-save').click(); });
    $('c-save').addEventListener('click', () => {
      S.name = C.cleanName(nameIn.value);
      nameIn.value = S.name;
      const existed = !!C.find(S.saved, S.name);
      S.saved = C.upsert(S.saved, current());
      persist((existed ? 'Updated ' : 'Saved ') + S.name + '.');
    });
    $('c-export').addEventListener('click', () => exportText(C.exportJSON(current()), slug(S.name) + '.vcs-character.json'));
    $('c-export-all').addEventListener('click', () => {
      if (!S.saved.length) { say('Nothing saved to export.'); return; }
      exportText(C.exportJSON(S.saved), 'vcs-characters.json');
    });
    $('c-import').addEventListener('click', () => importText($('c-json').value, 'the box'));
    $('c-import-file').addEventListener('click', () => $('c-file').click());
    $('c-file').addEventListener('change', (e) => {
      const f = e.target.files && e.target.files[0];
      e.target.value = '';
      if (!f) return;
      if (f.size > C.MAX_TEXT) { say('That file is too large.', true); return; }
      const rd = new FileReader();
      rd.onload = () => importText(String(rd.result), f.name);
      rd.onerror = () => say('Could not read ' + f.name + '.', true);
      rd.readAsText(f);
    });
    $('c-show').addEventListener('click', () => { $('c-json').value = C.exportJSON(current()); say('Current character shown as JSON.'); });
    $('c-spec').addEventListener('click', () => {
      $('c-json').value = JSON.stringify(C.toSpec(current()), null, 2);
      say('Forge spawn spec ({archetype, seed, overrides}) shown in the box.');
    });

    // Four views.
    const vh = $('views');
    VIEWS.forEach((v) => {
      const fig = el('figure');
      const cv = el('canvas');
      cv.width = 10; cv.height = 10;
      cv.setAttribute('role', 'img');
      cv.setAttribute('aria-label', v[0] + ' view');
      fig.appendChild(cv);
      fig.appendChild(el('figcaption', null, v[0]));
      vh.appendChild(fig);
      viewCells.push(cv);
    });
  }

  // Test and screenshot hook.
  window.__creator = {
    state: () => ({ arch: S.arch, seed: S.seed, name: S.name, look: Object.assign({}, S.look), view: Object.assign({}, S.view), saved: S.saved.length }),
    frames: () => S.frames,
    errors: S.errors,
    edit: edit,
    setView: setView,
    setTime: (t) => { S.t = Number(t) || 0; }
  };

  bind();
  buildFields();
  syncFields();
  syncView();
  renderSaved();
  if (!statusEl.textContent) say(draft ? 'Restored your last session.' : 'Pick an archetype, then change anything.');
  requestAnimationFrame(tick);
})();
