(function (root) {
  'use strict';
  const VCS = (root.VCS = root.VCS || {});

  let panel = null, body = null, pasteBox = null, status = null, search = null, errBox = null, fpsEl = null;
  let rendering = false, confirming = false, fpsTimer = null, f9 = false;

  function el(tag, cls, text) {
    const e = root.document.createElement(tag);
    if (cls) e.className = cls;
    if (text !== undefined) e.textContent = text;
    return e;
  }
  function say(msg) { if (status) status.textContent = msg; }
  function log() { return VCS.Log && VCS.Log.get ? VCS.Log.get('devpanel') : { warn() {}, error() {} }; }
  function nice(s) {
    s = String(s).replace(/([a-z])([A-Z])/g, '$1 $2').replace(/[_\-]+/g, ' ');
    return s.charAt(0).toUpperCase() + s.slice(1);
  }
  function button(label, fn, cls) {
    const b = el('button', cls || null, label);
    b.type = 'button';
    b.addEventListener('click', fn);
    return b;
  }
  function pressGame(id, what) {
    const b = root.document.getElementById(id);
    if (!b) { say(what + ' unavailable'); return; }
    try { b.click(); say(what + ' done'); } catch (e) { say(what + ' failed'); log().error('devpanel ' + what, e); }
  }

  function addFlag(sec, f) {
    const F = VCS.Flags;
    const row = el('label', 'dp-row dp-flag');
    row.dataset.q = (f.id + ' ' + f.desc).toLowerCase();
    const txt = el('span', 'dp-text');
    txt.appendChild(el('span', 'dp-name', nice(f.id.indexOf('.') > 0 ? f.id.slice(f.id.indexOf('.') + 1) : f.id)));
    if (f.desc) txt.appendChild(el('span', 'dp-hint', f.desc));
    const cb = el('input', 'dp-switch');
    cb.type = 'checkbox';
    cb.checked = !!f.value;
    cb.setAttribute('role', 'switch');
    cb.addEventListener('change', function () { F.set(f.id, cb.checked); });
    row.appendChild(txt);
    row.appendChild(cb);
    sec.appendChild(row);
  }
  function addTun(sec, t) {
    const F = VCS.Flags;
    const row = el('div', 'dp-row dp-tun');
    row.dataset.q = (t.sys + ' ' + t.key + ' ' + t.desc).toLowerCase();
    const txt = el('div', 'dp-text');
    txt.appendChild(el('span', 'dp-name', nice(t.key)));
    if (t.desc) txt.appendChild(el('span', 'dp-hint', t.desc));
    const ctl = el('div', 'dp-ctl');
    const rng = el('input');
    rng.type = 'range';
    rng.min = String(t.min); rng.max = String(t.max); rng.step = String(t.step); rng.value = String(t.value);
    const out = el('output', 'dp-val', String(t.value));
    const rst = button('reset', function () {
      F.setTun(t.sys, t.key, t.def);
      rng.value = String(t.def); out.textContent = String(t.def);
    }, 'dp-small');
    rng.addEventListener('input', function () { out.textContent = rng.value; F.setTun(t.sys, t.key, rng.value); });
    ctl.appendChild(rng); ctl.appendChild(out); ctl.appendChild(rst);
    row.appendChild(txt); row.appendChild(ctl);
    sec.appendChild(row);
  }

  function applyFilter() {
    const q = search ? search.value.trim().toLowerCase() : '';
    Array.prototype.forEach.call(body.querySelectorAll('.dp-group'), function (g) {
      let any = false;
      Array.prototype.forEach.call(g.querySelectorAll('.dp-row'), function (r) {
        const ok = !q || (r.dataset.q || '').indexOf(q) >= 0;
        r.hidden = !ok;
        if (ok) any = true;
      });
      g.hidden = !any;
    });
  }

  function build() {
    const F = VCS.Flags;
    rendering = true;
    body.textContent = '';
    const groups = Object.create(null);
    F.list().forEach(function (f) {
      const g = f.id.indexOf('.') > 0 ? f.id.slice(0, f.id.indexOf('.')) : f.id;
      (groups[g] = groups[g] || { flags: [], tuns: [] }).flags.push(f);
    });
    F.listTun().forEach(function (t) { (groups[t.sys] = groups[t.sys] || { flags: [], tuns: [] }).tuns.push(t); });
    const names = Object.keys(groups).sort();
    if (!names.length) body.appendChild(el('p', 'dp-hint', 'Nothing to tweak yet. Switches and sliders appear here as game systems are added.'));
    names.forEach(function (name) {
      const sec = el('section', 'dp-group');
      sec.appendChild(el('h3', null, nice(name)));
      groups[name].flags.forEach(function (f) { addFlag(sec, f); });
      groups[name].tuns.forEach(function (t) { addTun(sec, t); });
      body.appendChild(sec);
    });
    rendering = false;
    applyFilter();
    refreshErrors();
  }

  function refreshErrors() {
    if (!errBox) return;
    errBox.textContent = '';
    let list = [];
    try { list = VCS.Log && VCS.Log.entries ? VCS.Log.entries().filter(function (e) { return e && (e.level === 'ERROR' || e.level === 'WARN'); }).slice(-10).reverse() : []; } catch (e) { list = []; }
    if (!list.length) { errBox.appendChild(el('li', 'dp-hint', 'No recent warnings or errors.')); return; }
    list.forEach(function (e) {
      errBox.appendChild(el('li', e.level === 'ERROR' ? 'dp-err' : 'dp-warn', e.level + ' [' + e.module + '] ' + e.msg));
    });
  }

  function copyJson() {
    const text = JSON.stringify(VCS.Flags.toJSON(), null, 1);
    const fallback = function () {
      const box = root.document.getElementById('report-box');
      if (!box) { say('Copy unavailable'); return; }
      box.value = text; box.hidden = false;
      try { box.focus(); box.select(); } catch (e) { /* ignore */ }
      say('Selected in the box below; press Ctrl+C');
    };
    try {
      const nav = root.navigator;
      if (nav && nav.clipboard && typeof nav.clipboard.writeText === 'function') {
        nav.clipboard.writeText(text).then(function () { say('Copied settings'); }, fallback);
      } else fallback();
    } catch (e) { fallback(); }
  }

  function tickFps() {
    if (!fpsEl || !panel || panel.hidden) return;
    let fps = '?';
    try { fps = VCS.Game && VCS.Game.debugState ? VCS.Game.debugState().fps : '?'; } catch (e) { /* ignore */ }
    fpsEl.textContent = 'FPS ' + (fps === undefined ? '?' : fps);
    refreshErrors();
  }

  function resetFlow(bar) {
    const ask = button('Reset all', function () {
      if (confirming) return;
      confirming = true;
      ask.hidden = true;
      const yes = button('Really reset everything?', function () { VCS.Flags.resetAll(); done(); build(); say('Everything reset'); }, 'dp-danger');
      const no = button('Cancel', function () { done(); });
      function done() { confirming = false; ask.hidden = false; yes.remove(); no.remove(); }
      bar.appendChild(yes); bar.appendChild(no);
    });
    bar.appendChild(ask);
  }

  // ---- NPC Forge editor (v0.14). Host is set by game.js: {spawnAhead(spec), alterNearest(patch), despawnNearest(), people()} or null.
  let forgeHost = null;
  // v0.20: the standalone character creator (tools/character-creator.html) draws the same figures with every look field.
  const CREATOR_URL = 'tools/character-creator.html';
  const forgeUi = { sel: null, seed: null, pre: null, ctl: Object.create(null), hostBtns: [], hint: null, edits: Object.create(null), look: null, lib: null };

  function forgeApi() { return VCS.Forge && typeof VCS.Forge.generate === 'function' ? VCS.Forge : null; }
  function storageRef() { try { return root.localStorage || null; } catch (e) { return null; } }
  function forgeSeedValue() {
    const n = Math.floor(Number(forgeUi.seed && forgeUi.seed.value));
    return isFinite(n) ? Math.max(0, Math.min(4294967295, n)) : 0;
  }
  function forgeSpec() {
    const spec = { archetype: forgeUi.sel ? forgeUi.sel.value : 'patron', seed: forgeSeedValue() };
    if (Object.keys(forgeUi.edits).length) spec.overrides = Object.assign({}, forgeUi.edits);
    return spec;
  }
  function forgeRefresh(fromControls) {
    const F = forgeApi();
    if (!F || !forgeUi.pre) return;
    let look = null;
    try {
      const r = F.generate(forgeSpec(), { stateSeed: 0, index: 0, accOffset: 0 });
      look = r && r.person ? r.person.look : null;
    } catch (e) { look = null; }
    forgeUi.look = look;
    forgeUi.pre.textContent = look ? JSON.stringify(look, null, 1) : '(no look)';
    if (fromControls || !look) return;
    Object.keys(forgeUi.ctl).forEach(function (k) {
      const c = forgeUi.ctl[k];
      const v = look[k];
      if (c.kind === 'num') { c.input.value = String(v); c.out.textContent = String(v); }
      else if (c.kind === 'bool') c.input.checked = !!v;
      else c.input.value = String(v);
    });
  }
  function forgeFillSelect(keep) {
    const F = forgeApi();
    if (!F || !forgeUi.sel) return;
    forgeUi.sel.textContent = '';
    let ids = [];
    try { ids = F.list(); } catch (e) { ids = []; }
    ids.forEach(function (id) {
      const o = el('option', null, id);
      o.value = id;
      forgeUi.sel.appendChild(o);
    });
    if (keep && ids.indexOf(keep) >= 0) forgeUi.sel.value = keep;
  }
  function forgeSetHostState() {
    forgeUi.hostBtns.forEach(function (b) { b.disabled = !forgeHost; });
    if (forgeUi.hint) forgeUi.hint.textContent = forgeHost ? '' : 'Start a run to use these';
  }
  function forgeCall(name, arg, what) {
    if (!forgeHost || typeof forgeHost[name] !== 'function') { say('Start a run to use these'); return; }
    try {
      const r = forgeHost[name](arg);
      say(what + (r && r.code ? ': ' + r.code : ' done'));
    } catch (e) { say(what + ' failed'); log().error('devpanel forge ' + what, e); }
  }
  function forgeCopyLibrary() {
    const F = forgeApi();
    if (!F) { say('Forge unavailable'); return; }
    const text = F.exportLibrary();
    const fallback = function () {
      const box = root.document.getElementById('report-box');
      if (!box) { say('Copy unavailable'); return; }
      box.value = text; box.hidden = false;
      try { box.focus(); box.select(); } catch (e) { /* ignore */ }
      say('Selected in the box below; press Ctrl+C');
    };
    try {
      const nav = root.navigator;
      if (nav && nav.clipboard && typeof nav.clipboard.writeText === 'function') {
        nav.clipboard.writeText(text).then(function () { say('Copied library'); }, fallback);
      } else fallback();
    } catch (e) { fallback(); }
  }
  function forgeSaveCustom() {
    const F = forgeApi();
    if (!F) { say('Forge unavailable'); return; }
    const base = F.archetype(forgeUi.sel.value);
    const look = forgeUi.look;
    if (!base || !look) { say('Nothing to save'); return; }
    let id = '';
    for (let i = 1; i < 100 && !id; i++) if (!F.archetype('custom_' + i)) id = 'custom_' + i;
    if (!id) { say('Save archetype: E_FORGE_LIMIT'); return; }
    const arch = {
      id: id, role: '', label: id, voice: base.voice, talk: base.talk, schedule: null, watch: false, feedable: base.feedable,
      gait: base.gait, speed: base.speed,
      recipe: {
        height: [look.height, 0], build: [look.build, 0], stride: [look.stride, 0], nose: [look.nose, 0],
        bodies: [look.body], heads: [look.head], hairs: [look.hair], beardP: look.beard ? 1 : 0, coatP: look.coat ? 1 : 0, acc: look.acc
      },
      extras: { outfit: look.outfit, roleHat: look.roleHat, extra: look.extra, stoop: look.stoop, shoulder: look.shoulder, hem: look.hem, skin: look.skin }
    };
    const r = F.register(arch);
    let code = r.code;
    if (r.ok) {
      const st = storageRef();
      const sv = st ? F.saveLibrary(st) : { ok: false, code: 'E_FORGE_TYPE' };
      code = sv.ok ? 'OK' : 'registered, not stored (' + sv.code + ')';
      forgeFillSelect(id);
      forgeUi.edits = Object.create(null);
      forgeRefresh(false);
    }
    say('Save archetype ' + id + ': ' + code);
  }
  function forgeAddField(sec, f) {
    const row = el('div', 'dp-row dp-forge-row');
    row.appendChild(el('span', 'dp-name', nice(f.key)));
    const ctl = el('div', 'dp-ctl');
    const note = function (v) { forgeUi.edits[f.key] = v; forgeRefresh(true); };
    if (f.type === 'num') {
      const rng = el('input');
      rng.type = 'range';
      rng.min = String(f.min); rng.max = String(f.max); rng.step = String(f.step);
      const out = el('output', 'dp-val', '');
      rng.addEventListener('input', function () { out.textContent = rng.value; note(Number(rng.value)); });
      ctl.appendChild(rng); ctl.appendChild(out);
      forgeUi.ctl[f.key] = { kind: 'num', input: rng, out: out };
    } else if (f.type === 'enum') {
      const sel = el('select');
      (f.values || []).forEach(function (v) {
        const o = el('option', null, v);
        o.value = v;
        sel.appendChild(o);
      });
      sel.addEventListener('change', function () { note(sel.value); });
      ctl.appendChild(sel);
      forgeUi.ctl[f.key] = { kind: 'enum', input: sel };
    } else {
      const cb = el('input', 'dp-switch');
      cb.type = 'checkbox';
      cb.addEventListener('change', function () { note(cb.checked); });
      ctl.appendChild(cb);
      forgeUi.ctl[f.key] = { kind: 'bool', input: cb };
    }
    row.appendChild(ctl);
    sec.appendChild(row);
  }
  function buildForge(parent) {
    const F = forgeApi();
    const sec = el('section', 'dp-group dp-forge');
    sec.appendChild(el('h3', null, 'NPC Forge'));
    if (!F) {
      sec.appendChild(el('p', 'dp-hint', 'Forge is not loaded.'));
      parent.appendChild(sec);
      return;
    }
    const top = el('div', 'dp-bar dp-forge-top');
    forgeUi.sel = el('select', 'dp-forge-select');
    forgeUi.sel.setAttribute('aria-label', 'Archetype');
    forgeFillSelect();
    forgeUi.sel.addEventListener('change', function () { forgeUi.edits = Object.create(null); forgeRefresh(false); });
    forgeUi.seed = el('input', 'dp-forge-seed');
    forgeUi.seed.type = 'number';
    forgeUi.seed.min = '0'; forgeUi.seed.max = '4294967295'; forgeUi.seed.step = '1'; forgeUi.seed.value = '1';
    forgeUi.seed.setAttribute('aria-label', 'Seed');
    forgeUi.seed.addEventListener('change', function () { forgeUi.edits = Object.create(null); forgeRefresh(false); });
    top.appendChild(forgeUi.sel);
    top.appendChild(forgeUi.seed);
    top.appendChild(button('Random seed', function () {
      forgeUi.seed.value = String(Math.floor(Math.random() * 4294967296));
      forgeUi.edits = Object.create(null);
      forgeRefresh(false);
    }, 'dp-small'));
    sec.appendChild(top);
    let fields = [];
    try { fields = F.LOOK_FIELDS || []; } catch (e) { fields = []; }
    fields.forEach(function (f) { forgeAddField(sec, f); });
    forgeUi.pre = el('pre', 'dp-forge-preview');
    sec.appendChild(forgeUi.pre);
    const hb = el('div', 'dp-bar');
    forgeUi.hostBtns = [
      button('Spawn in front', function () { forgeCall('spawnAhead', forgeSpec(), 'Spawn'); }),
      button('Alter nearest', function () {
        forgeCall('alterNearest', Object.keys(forgeUi.edits).length ? Object.assign({}, forgeUi.edits) : Object.assign({}, forgeUi.look || {}), 'Alter');
      }),
      button('Despawn nearest', function () { forgeCall('despawnNearest', undefined, 'Despawn'); })
    ];
    forgeUi.hostBtns.forEach(function (b) { hb.appendChild(b); });
    sec.appendChild(hb);
    forgeUi.hint = el('div', 'dp-hint dp-forge-hint');
    sec.appendChild(forgeUi.hint);
    const lb = el('div', 'dp-bar');
    lb.appendChild(button('Save as custom archetype', forgeSaveCustom));
    lb.appendChild(button('Copy library JSON', forgeCopyLibrary));
    lb.appendChild(button('Open character creator', function () {
      try { root.open(CREATOR_URL, '_blank', 'noopener'); say('Character creator opened in a new tab'); } catch (e) { say('Open ' + CREATOR_URL + ' from the game folder'); }
    }));
    sec.appendChild(lb);
    forgeUi.lib = el('textarea', 'dp-paste dp-forge-lib');
    forgeUi.lib.rows = 3;
    forgeUi.lib.spellcheck = false;
    forgeUi.lib.setAttribute('aria-label', 'Library JSON to import');
    forgeUi.lib.placeholder = 'Paste library JSON here, then press Import';
    sec.appendChild(forgeUi.lib);
    const ib = el('div', 'dp-bar');
    ib.appendChild(button('Import library JSON', function () {
      const r = F.importLibrary(forgeUi.lib.value);
      forgeFillSelect(forgeUi.sel.value);
      forgeRefresh(false);
      say('Import library: ' + r.code + (r.ok ? ' (' + r.n + ')' : ''));
    }));
    sec.appendChild(ib);
    parent.appendChild(sec);
    forgeSetHostState();
    forgeRefresh(false);
  }

  function init(opts) {
    if (panel || !root.document || !VCS.Flags) return false;
    f9 = !!(opts && opts.f9);
    try {
      const doc = root.document;
      panel = el('div');
      panel.id = 'devpanel';
      panel.hidden = true;
      panel.setAttribute('role', 'dialog');
      panel.setAttribute('aria-label', 'Developer tools');
      const head = el('div', 'dp-head');
      head.appendChild(el('strong', null, 'Developer tools'));
      fpsEl = el('span', 'dp-fps', 'FPS ?');
      head.appendChild(fpsEl);
      head.appendChild(button('Close (Esc)', function () { Dev.close(); }));
      panel.appendChild(head);
      panel.appendChild(el('p', 'dp-hint', 'Tweak the game while it runs. Changes save in this browser. Nothing here is needed to play.'));
      search = el('input', 'dp-search');
      search.type = 'search';
      search.placeholder = 'Search settings...';
      search.setAttribute('aria-label', 'Search settings');
      search.addEventListener('input', applyFilter);
      panel.appendChild(search);
      body = el('div', 'dp-body');
      panel.appendChild(body);

      const tools = el('section', 'dp-group');
      tools.appendChild(el('h3', null, 'Help and reports'));
      const tbar = el('div', 'dp-bar');
      tbar.appendChild(button('Copy error report', function () { pressGame('btn-pause-report', 'Copy report'); }));
      tbar.appendChild(button('Download log', function () { pressGame('btn-pause-log', 'Download log'); }));
      tools.appendChild(tbar);
      tools.appendChild(el('div', 'dp-hint', 'Recent warnings and errors'));
      errBox = el('ul', 'dp-errs');
      tools.appendChild(errBox);
      panel.appendChild(tools);

      buildForge(panel);

      const io = el('section', 'dp-group');
      io.appendChild(el('h3', null, 'Share settings'));
      pasteBox = el('textarea', 'dp-paste');
      pasteBox.rows = 3;
      pasteBox.spellcheck = false;
      pasteBox.setAttribute('aria-label', 'Paste settings JSON');
      pasteBox.placeholder = 'Paste settings JSON here, then press Apply';
      io.appendChild(pasteBox);
      const bar = el('div', 'dp-bar');
      bar.appendChild(button('Copy tunables JSON', copyJson));
      bar.appendChild(button('Apply pasted JSON', function () {
        const n = VCS.Flags.fromJSON(pasteBox.value);
        build(); say(n ? 'Applied ' + n + ' setting(s)' : 'Nothing applied (is the JSON valid?)');
      }));
      resetFlow(bar);
      io.appendChild(bar);
      panel.appendChild(io);
      status = el('div', 'dp-status');
      status.setAttribute('role', 'status');
      panel.appendChild(status);

      ['keydown', 'keyup', 'keypress'].forEach(function (t) {
        panel.addEventListener(t, function (e) {
          e.stopPropagation(); // F9 and Esc are handled by the window capture listener below
        });
      });
      doc.body.appendChild(panel);
      // Capture phase so Esc closes the panel before the game sees it.
      root.addEventListener('keydown', function (e) {
        if (Dev.isOpen() && (e.key === 'Escape' || e.code === 'Escape')) {
          e.preventDefault(); e.stopImmediatePropagation(); Dev.close();
        } else if (f9 && (e.key === 'F9' || e.code === 'F9')) { e.preventDefault(); Dev.toggle(); }
      }, true);
      VCS.Flags.onChange(function () { if (!rendering && !panel.hidden && !panel.contains(doc.activeElement)) build(); });
      const btn = doc.getElementById('btn-devtool');
      if (btn) btn.addEventListener('click', function () { Dev.open(); });
      return true;
    } catch (e) {
      log().error('devpanel init failed', e);
      return false;
    }
  }

  const Dev = {
    init: init,
    isOpen: function () { return !!panel && !panel.hidden; },
    open: function () {
      if (!panel) return false;
      panel.hidden = false;
      build();
      try { if (root.document.pointerLockElement && root.document.exitPointerLock) root.document.exitPointerLock(); } catch (e) { /* ignore */ }
      if (!fpsTimer) fpsTimer = root.setInterval(tickFps, 500);
      tickFps();
      try { search.focus(); } catch (e) { /* ignore */ }
      return true;
    },
    close: function () {
      if (!panel) return false;
      panel.hidden = true;
      if (fpsTimer) { root.clearInterval(fpsTimer); fpsTimer = null; }
      const b = root.document.getElementById('btn-devtool');
      try { if (b && b.offsetParent !== null) b.focus(); } catch (e) { /* ignore */ }
      return false;
    },
    toggle: function () { return this.isOpen() ? this.close() : this.open(); },
    setForgeHost: function (h) {
      forgeHost = h && typeof h === 'object' ? h : null;
      try { forgeSetHostState(); } catch (e) { log().error('setForgeHost', e); }
      return !!forgeHost;
    }
  };
  VCS.DevPanel = Dev;
  if (typeof module !== 'undefined' && module.exports) module.exports = Dev;
})(typeof window !== 'undefined' ? window : globalThis);
