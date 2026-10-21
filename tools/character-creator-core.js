(function (root) {
  'use strict';
  const VCS = (root.VCS = root.VCS || {});

  // Character creator data layer (tools/character-creator.html). Pure logic, no DOM: the look field table, validation
  // and clamping (so Figure / Render never see a bad look), archetype presets through the real Forge, randomizing,
  // pose-to-echo set-up, view-state clamping, named-character storage and JSON export / import. Public functions never
  // throw. Loaded by the creator page after js/data/archetypes.js and js/forge.js; Node tests require it directly.

  const STORE_KEY = 'vcs.creator';
  const DRAFT_KEY = 'vcs.creator.draft';
  const FORMAT_ONE = 'vcs-character';
  const FORMAT_MANY = 'vcs-characters';
  const MAX_SAVED = 64;
  const MAX_TEXT = 262144;
  const MAX_NAME = 32;
  const BAD_KEYS = ['__proto__', 'constructor', 'prototype'];
  const TAU = Math.PI * 2;

  function mod(name, file) {
    try {
      if (root.VCS && root.VCS[name]) return root.VCS[name];
      if (typeof require === 'function' && typeof module !== 'undefined') return require(file);
    } catch (e) { /* ignore */ }
    return null;
  }
  function AD() { return mod('ArchetypeData', '../js/data/archetypes.js'); }
  function Forge() { return mod('Forge', '../js/forge.js'); }

  const hasOwn = Object.prototype.hasOwnProperty;
  function isPlain(o) { return !!o && typeof o === 'object' && !Array.isArray(o); }
  function isNum(n) { return typeof n === 'number' && isFinite(n); }
  function clamp(n, lo, hi) { return n < lo ? lo : n > hi ? hi : n; }
  function own(o, k) { try { return isPlain(o) && hasOwn.call(o, k) && BAD_KEYS.indexOf(k) < 0 ? o[k] : undefined; } catch (e) { return undefined; } }
  function round3(n) { return Math.round(n * 1000) / 1000; }

  // ---------------------------------------------------------------- field table

  const FALLBACK_ENUMS = {
    acc: ['tophat', 'nightcap', 'bonnet', 'cane', 'scarf', 'lantern', 'hood', 'umbrella', 'cap', 'basket', 'none'],
    body: ['bean', 'pear', 'stick', 'round', 'box'],
    head: ['round', 'egg', 'square', 'long'],
    hat: ['none', 'tophat', 'nightcap', 'bonnet', 'cap', 'hood'],
    hair: ['none', 'tuft', 'bun', 'spiky', 'curls', 'bob'],
    prop: ['none', 'cane', 'lantern', 'umbrella', 'basket'],
    outfit: ['plain', 'mail', 'robe', 'apron', 'smock', 'cloak'],
    roleHat: ['none', 'kettle', 'biretta'],
    extra: ['none', 'shovel', 'bundle', 'ledger', 'bow']
  };
  const FALLBACK_RANGES = {
    height: [0.5, 1.2], build: [0.7, 1.4], stride: [0.7, 1.4], nose: [0.5, 1.6],
    stoop: [0, 0.4], shoulder: [0.8, 1.25], hem: [0, 1], skin: [0, 1]
  };
  function enums() { const a = AD(); return a && a.LOOK_ENUMS ? a.LOOK_ENUMS : FALLBACK_ENUMS; }
  function ranges() { const a = AD(); return a && a.LOOK_RANGES ? a.LOOK_RANGES : FALLBACK_RANGES; }

  const DEFAULTS = {
    height: 1, build: 1, stride: 1, acc: 'none', body: 'bean', head: 'round', hat: 'none', hair: 'none', beard: false,
    nose: 1, coat: false, prop: 'none', v: 1, archetype: 'patron', outfit: 'plain', roleHat: 'none', extra: 'none',
    stoop: 0, shoulder: 1, hem: 0, skin: 0.5
  };
  const NUM_KEYS = ['height', 'build', 'stride', 'nose', 'stoop', 'shoulder', 'hem', 'skin'];
  const BOOL_KEYS = ['beard', 'coat'];
  const ENUM_KEYS = ['acc', 'body', 'head', 'hat', 'hair', 'prop', 'outfit', 'roleHat', 'extra'];
  const LOOK_KEYS = Object.keys(DEFAULTS);
  const ID_RE = /^[a-z][a-z0-9_]{1,23}$/;

  // UI groups. 'scarf' is a creator-only toggle: the look stores it as acc 'scarf' (see deriveAcc).
  const GROUPS = [
    ['Body', ['body', 'height', 'build', 'shoulder', 'stoop', 'stride']],
    ['Head and face', ['head', 'nose', 'hair', 'beard', 'skin']],
    ['Clothes', ['outfit', 'hem', 'coat', 'scarf']],
    ['Headwear', ['hat', 'roleHat']],
    ['Carried', ['prop', 'extra']]
  ];
  const LABELS = {
    body: 'Body', height: 'Height', build: 'Build', shoulder: 'Shoulders', stoop: 'Stoop', stride: 'Stride',
    head: 'Head', nose: 'Nose', hair: 'Hair', beard: 'Beard', skin: 'Flush (skin)', outfit: 'Outfit', hem: 'Hem length',
    coat: 'Coat', scarf: 'Scarf', hat: 'Hat', roleHat: 'Role hat', prop: 'Prop', extra: 'Role item'
  };
  const HINTS = {
    height: 'At or below 0.66 reads as a child', stoop: 'Shows at Effects 1 and 2', skin: 'How strongly the pulse flushes the skin (Effects 2, circulation on)',
    hem: '0 waist .. 1 ankle (robe, apron, smock, cloak)', stride: 'Walk and flee step size', roleHat: 'Replaces the hat', extra: 'Volumetric figures only (Effects 1 and 2)'
  };

  function fields() {
    const E = enums();
    const R = ranges();
    const out = [];
    GROUPS.forEach(function (g) {
      g[1].forEach(function (k) {
        const f = { key: k, label: LABELS[k] || k, group: g[0], hint: HINTS[k] || '' };
        if (NUM_KEYS.indexOf(k) >= 0) { f.type = 'num'; f.min = R[k][0]; f.max = R[k][1]; f.step = 0.01; }
        else if (BOOL_KEYS.indexOf(k) >= 0 || k === 'scarf') f.type = 'bool';
        else { f.type = 'enum'; f.values = (E[k] || []).slice(); }
        out.push(f);
      });
    });
    return out;
  }

  // ---------------------------------------------------------------- validation

  /** acc is the legacy single accessory; the renderer draws look.hat and look.prop directly and a scarf from acc. */
  function deriveAcc(look, scarf) {
    if (scarf) return 'scarf';
    if (look.hat && look.hat !== 'none') return look.hat;
    if (look.prop && look.prop !== 'none') return look.prop;
    return 'none';
  }

  /**
   * Clamp any input into a complete, render-safe look. Unknown keys are dropped, numbers are clamped to LOOK_RANGES,
   * enums and booleans that are wrong fall back to `base` (or the defaults). Returns {look, fixed: [keys changed]}.
   */
  function sanitize(input, base) {
    try {
      const E = enums();
      const R = ranges();
      const b = isPlain(base) ? base : DEFAULTS;
      const src = isPlain(input) ? input : {};
      const out = {};
      const fixed = [];
      LOOK_KEYS.forEach(function (k) {
        const raw = own(src, k);
        const fb = own(b, k) !== undefined ? own(b, k) : DEFAULTS[k];
        let v;
        if (k === 'v') v = 1;
        else if (k === 'archetype') v = typeof raw === 'string' && ID_RE.test(raw) ? raw : (typeof fb === 'string' && ID_RE.test(fb) ? fb : 'patron');
        else if (NUM_KEYS.indexOf(k) >= 0) {
          const r = R[k] || [0, 1];
          if (isNum(raw)) v = round3(clamp(raw, r[0], r[1]));
          else if (typeof raw === 'string' && raw.trim() !== '' && isFinite(Number(raw))) v = round3(clamp(Number(raw), r[0], r[1]));
          else v = isNum(fb) ? round3(clamp(fb, r[0], r[1])) : DEFAULTS[k];
        } else if (BOOL_KEYS.indexOf(k) >= 0) v = typeof raw === 'boolean' ? raw : !!fb;
        else if (ENUM_KEYS.indexOf(k) >= 0) v = typeof raw === 'string' && (E[k] || []).indexOf(raw) >= 0 ? raw : ((E[k] || []).indexOf(fb) >= 0 ? fb : DEFAULTS[k]);
        else v = DEFAULTS[k];
        if (raw !== undefined && raw !== v && k !== 'v') fixed.push(k);
        out[k] = v;
      });
      return { look: out, fixed: fixed };
    } catch (e) {
      return { look: Object.assign({}, DEFAULTS), fixed: ['*'] };
    }
  }

  /** Apply one field edit (including the 'scarf' toggle) to a look; returns a new sanitized look. */
  function setField(look, key, value) {
    try {
      const cur = sanitize(look).look;
      if (key === 'scarf') { cur.acc = deriveAcc(cur, value === true || value === 'true'); return cur; }
      if (LOOK_KEYS.indexOf(key) < 0 || key === 'v') return cur;
      const patch = {};
      if (NUM_KEYS.indexOf(key) >= 0) patch[key] = Number(value);
      else if (BOOL_KEYS.indexOf(key) >= 0) patch[key] = value === true || value === 'true';
      else patch[key] = String(value);
      const next = sanitize(Object.assign({}, cur, patch), cur).look;
      if (key === 'hat' || key === 'prop') next.acc = deriveAcc(next, cur.acc === 'scarf');
      return next;
    } catch (e) {
      return sanitize(look).look;
    }
  }

  /** Value of a field for the UI (the 'scarf' toggle reads acc). */
  function getField(look, key) {
    if (key === 'scarf') return !!look && look.acc === 'scarf';
    return look ? look[key] : undefined;
  }

  /** True when the game's Forge would hide this hair under the hat (tophat, nightcap, hood). */
  function hairHidden(look) {
    return !!look && (look.hat === 'nightcap' || look.hat === 'hood' || look.hat === 'tophat') && look.roleHat === 'none';
  }

  // ---------------------------------------------------------------- presets and randomizing

  function mulberry32(seed) {
    let a = seed >>> 0;
    return function () {
      a = (a + 0x6D2B79F5) >>> 0;
      let t = a;
      t = Math.imul(t ^ (t >>> 15), t | 1);
      t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
      return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
  }

  function archetypes() {
    try {
      const F = Forge();
      const ids = F ? F.list() : [];
      return ids.map(function (id) {
        const a = F.archetype(id);
        return { id: id, label: a && a.label ? String(a.label) : id };
      });
    } catch (e) {
      return [{ id: 'patron', label: 'Patron' }];
    }
  }

  function cleanSeed(seed) {
    const n = Math.floor(Number(seed));
    return isFinite(n) ? clamp(n, 0, 65535) : 0;
  }

  /** The look the game's Forge gives archetype `id` at `seed` (same context as the dev panel's Forge editor). */
  function preset(id, seed) {
    try {
      const F = Forge();
      const s = cleanSeed(seed);
      if (!F) return sanitize({ archetype: id }).look;
      const r = F.generate({ archetype: typeof id === 'string' ? id : 'patron', seed: s }, { stateSeed: 0, index: 0, accOffset: 0 });
      return sanitize(r && r.person ? r.person.look : {}).look;
    } catch (e) {
      return Object.assign({}, DEFAULTS);
    }
  }

  /**
   * Randomize a look. mode 'wild': every unlocked field uniform over its full range or list. mode 'archetype': a fresh
   * Forge preset of look.archetype at a random seed. `locks` (array or object of keys) keeps those fields from `base`.
   * Returns {look, seed}.
   */
  function randomize(base, opts) {
    try {
      const o = isPlain(opts) ? opts : {};
      const rnd = typeof o.rng === 'function' ? o.rng : Math.random;
      const b = sanitize(base).look;
      const locked = Array.isArray(o.locks) ? o.locks : (isPlain(o.locks) ? Object.keys(o.locks).filter(function (k) { return o.locks[k]; }) : []);
      const seed = Math.floor(rnd() * 65536) % 65536;
      let next;
      if (o.mode === 'archetype') {
        next = preset(b.archetype, seed);
      } else {
        next = Object.assign({}, b);
        const E = enums();
        const R = ranges();
        NUM_KEYS.forEach(function (k) { next[k] = R[k][0] + rnd() * (R[k][1] - R[k][0]); });
        ['body', 'head', 'hat', 'hair', 'prop', 'outfit', 'extra'].forEach(function (k) { const l = E[k] || []; next[k] = l[Math.floor(rnd() * l.length)] || DEFAULTS[k]; });
        // Role hats and children are rarer, so a wild roll still looks like a villager most of the time.
        next.roleHat = rnd() < 0.2 ? (E.roleHat || ['none'])[1 + Math.floor(rnd() * ((E.roleHat || []).length - 1))] || 'none' : 'none';
        if (rnd() < 0.8) next.height = 0.82 + rnd() * 0.38;
        next.hem = next.outfit === 'robe' ? 0.85 + rnd() * 0.15 : next.hem;
        next.beard = rnd() < 0.3;
        next.coat = rnd() < 0.4;
        next.acc = deriveAcc(next, rnd() < 0.2);
      }
      locked.forEach(function (k) {
        if (k === 'scarf') next.acc = deriveAcc(next, b.acc === 'scarf');
        else if (LOOK_KEYS.indexOf(k) >= 0) next[k] = b[k];
      });
      if (locked.indexOf('hat') >= 0 || locked.indexOf('prop') >= 0) next.acc = deriveAcc(next, next.acc === 'scarf');
      return { look: sanitize(next).look, seed: seed };
    } catch (e) {
      return { look: sanitize(base).look, seed: 0 };
    }
  }

  // ---------------------------------------------------------------- poses and view

  const POSES = [
    { id: 'idle', label: 'Idle' }, { id: 'wary', label: 'Wary' }, { id: 'chat', label: 'Chat' }, { id: 'walk', label: 'Walk' },
    { id: 'flee', label: 'Flee' }, { id: 'startle', label: 'Startle' }, { id: 'cower', label: 'Cower' }, { id: 'dazed', label: 'Dazed' },
    { id: 'seated', label: 'Seated' }, { id: 'fed', label: 'Fed (slumped)' }, { id: 'held', label: 'Held (struggle)' }
  ];
  const POSE_IDS = POSES.map(function (p) { return p.id; });
  const VMODE = { flee: 'flee', cower: 'cower', fed: 'fed', startle: 'startle' };

  /**
   * Echo for Render.drawSolo: one villager at depth dist, lateral lat, facing yaw (0 = facing the camera), in pose id,
   * at clock t (s). Returns {echo, lock, vmode}; lock is null except for 'held'.
   */
  function poseEcho(id, look, o) {
    const c = isPlain(o) ? o : {};
    const pid = POSE_IDS.indexOf(id) >= 0 ? id : 'idle';
    const t = isNum(c.t) ? c.t : 0;
    const anim = !c.reduced;
    const yaw = isNum(c.yaw) ? c.yaw : 0;
    const e = {
      x: isNum(c.dist) ? c.dist : 2.2, y: isNum(c.lat) ? c.lat : 0, angle: Math.PI + yaw, lookAngle: 0,
      phase: 0, phaseRate: 0, personId: isNum(c.personId) ? c.personId : 4, t: 0, strength: 1, zMin: 0, zMax: 2,
      look: look, fade: 3, mode: 'path', sit: false, wary: false, chat: false, modeAge: 9
    };
    let lock = null;
    if (pid === 'wary') e.wary = true;
    else if (pid === 'chat') e.chat = true;
    else if (pid === 'walk') e.phase = 0.3 + (anim ? t * 6 : 0);
    else if (pid === 'flee') { e.mode = 'flee'; e.phase = 0.3 + (anim ? t * 8 : 0); }
    else if (pid === 'startle') { e.mode = 'startle'; e.modeAge = anim ? (t * 0.6) % 1.2 : 2; }
    else if (pid === 'cower') e.mode = 'cower';
    else if (pid === 'dazed') e.mode = 'dazed';
    else if (pid === 'seated') e.sit = true;
    else if (pid === 'fed') e.mode = 'fed';
    else if (pid === 'held') {
      const k = isNum(c.struggle) ? clamp(c.struggle, 0, 1) : 0.4;
      const span = k < 0.2 ? 3 : 6;
      lock = { k: k, age: (k < 0.2 ? 0.3 : 5) + (anim ? t % span : 0), rs: c.restrain ? 1 : 0, sp: 9 };
      e.x = 1.25;
    }
    return { echo: e, lock: lock, vmode: VMODE[pid] || 'calm' };
  }

  const VIEW_DEFAULTS = {
    pose: 'idle', fx: 2, quality: 3, zoom: 3, dist: 2.2, yaw: 0, spin: false, play: true, speed: 1, rim: true,
    vessels: false, skel: false, graph: false, parts: false, reduced: false, struggle: 0.4, restrain: false, gameScale: 2
  };
  /** Clamp a view state (pose, Effects, quality, zoom, distance, yaw in -pi..pi, speed, toggles). */
  function sanitizeView(v) {
    const s = isPlain(v) ? v : {};
    const out = {};
    const num = function (k, lo, hi, int) {
      let n = Number(own(s, k));
      if (!isFinite(n)) n = VIEW_DEFAULTS[k];
      n = clamp(n, lo, hi);
      out[k] = int ? Math.round(n) : n;
    };
    out.pose = POSE_IDS.indexOf(own(s, 'pose')) >= 0 ? own(s, 'pose') : 'idle';
    num('fx', 0, 2, true); num('quality', 1, 3, true); num('zoom', 1, 4, true); num('dist', 1.2, 5, false);
    num('speed', 0, 2, false); num('struggle', 0, 1, false); num('gameScale', 1, 4, true);
    let yaw = Number(own(s, 'yaw'));
    if (!isFinite(yaw)) yaw = 0;
    yaw = ((yaw + Math.PI) % TAU + TAU) % TAU - Math.PI;
    out.yaw = yaw;
    ['spin', 'play', 'rim', 'vessels', 'skel', 'graph', 'parts', 'reduced', 'restrain'].forEach(function (k) {
      const r = own(s, k);
      out[k] = typeof r === 'boolean' ? r : VIEW_DEFAULTS[k];
    });
    return out;
  }

  // ---------------------------------------------------------------- characters, storage, JSON

  function cleanName(name) {
    // eslint-disable-next-line no-control-regex
    const s = typeof name === 'string' ? name.replace(/[\u0000-\u001f\u007f<>]/g, '').replace(/\s+/g, ' ').trim().slice(0, MAX_NAME) : '';
    return s || 'Unnamed';
  }

  /** A saved character: {name, archetype, seed, look, saved (ms)}. */
  function character(name, look, meta) {
    const m = isPlain(meta) ? meta : {};
    const l = sanitize(look).look;
    const arch = typeof m.archetype === 'string' && ID_RE.test(m.archetype) ? m.archetype : l.archetype;
    const saved = isNum(m.saved) && m.saved > 0 ? Math.floor(m.saved) : Date.now();
    return { name: cleanName(name), archetype: arch, seed: cleanSeed(m.seed), look: l, saved: saved };
  }

  /** Accepts a saved-character object, or a bare look; returns a sanitized character or null. */
  function fromAny(o, i) {
    if (!isPlain(o)) return null;
    if (isPlain(own(o, 'look'))) return character(own(o, 'name'), own(o, 'look'), { archetype: own(o, 'archetype'), seed: own(o, 'seed'), saved: own(o, 'saved') });
    // A bare look (from the dev panel preview or Forge) needs at least one look key.
    const ks = Object.keys(o);
    for (let j = 0; j < ks.length; j++) {
      if (LOOK_KEYS.indexOf(ks[j]) >= 0 && ks[j] !== 'v') return character('Imported ' + ((i || 0) + 1), o, {});
    }
    return null;
  }

  function exportJSON(chars) {
    try {
      const list = Array.isArray(chars) ? chars : [chars];
      const clean = list.map(function (c, i) { return fromAny(c, i); }).filter(Boolean);
      if (!Array.isArray(chars) && clean.length === 1) return JSON.stringify(Object.assign({ format: FORMAT_ONE, v: 1 }, clean[0]), null, 2);
      return JSON.stringify({ format: FORMAT_MANY, v: 1, list: clean.slice(0, MAX_SAVED) }, null, 2);
    } catch (e) {
      return JSON.stringify({ format: FORMAT_MANY, v: 1, list: [] });
    }
  }

  /**
   * Parse exported JSON: one character, a {format: 'vcs-characters', list} bundle, a plain array, or a bare look.
   * Returns {ok, code, list, skipped}. Codes: OK, E_CC_TYPE, E_CC_PARSE, E_CC_LIMIT, E_CC_EMPTY.
   */
  function importJSON(text) {
    try {
      if (typeof text !== 'string') return { ok: false, code: 'E_CC_TYPE', list: [], skipped: 0 };
      if (text.length > MAX_TEXT) return { ok: false, code: 'E_CC_LIMIT', list: [], skipped: 0 };
      let data;
      try { data = JSON.parse(text); } catch (e) { return { ok: false, code: 'E_CC_PARSE', list: [], skipped: 0 }; }
      let items;
      if (Array.isArray(data)) items = data;
      else if (isPlain(data) && Array.isArray(own(data, 'list'))) items = own(data, 'list');
      else if (isPlain(data)) items = [data];
      else return { ok: false, code: 'E_CC_TYPE', list: [], skipped: 0 };
      if (items.length > MAX_SAVED * 4) return { ok: false, code: 'E_CC_LIMIT', list: [], skipped: 0 };
      const out = [];
      let skipped = 0;
      items.forEach(function (it, i) {
        const c = fromAny(it, i);
        if (c && out.length < MAX_SAVED) out.push(c); else skipped++;
      });
      if (!out.length) return { ok: false, code: 'E_CC_EMPTY', list: [], skipped: skipped };
      return { ok: true, code: 'OK', list: out, skipped: skipped };
    } catch (e) {
      return { ok: false, code: 'E_CC_PARSE', list: [], skipped: 0 };
    }
  }

  /** Insert or replace (same name, case-insensitive) into a list; newest first, at most MAX_SAVED. Returns a new list. */
  function upsert(list, c) {
    const src = Array.isArray(list) ? list : [];
    const ch = fromAny(c, 0);
    if (!ch) return src.slice();
    const key = ch.name.toLowerCase();
    const out = [ch].concat(src.filter(function (x) { return !(x && typeof x.name === 'string' && x.name.toLowerCase() === key); }));
    return out.slice(0, MAX_SAVED);
  }
  function remove(list, name) {
    const key = typeof name === 'string' ? name.toLowerCase() : '';
    return (Array.isArray(list) ? list : []).filter(function (x) { return !(x && typeof x.name === 'string' && x.name.toLowerCase() === key); });
  }
  function find(list, name) {
    const key = typeof name === 'string' ? name.toLowerCase() : '';
    const arr = Array.isArray(list) ? list : [];
    for (let i = 0; i < arr.length; i++) if (arr[i] && typeof arr[i].name === 'string' && arr[i].name.toLowerCase() === key) return arr[i];
    return null;
  }
  /** A name not yet in the list: base, base 2, base 3, ... */
  function freeName(list, base) {
    const b = cleanName(base);
    if (!find(list, b)) return b;
    for (let i = 2; i < 1000; i++) { const n = cleanName(b.slice(0, MAX_NAME - 5) + ' ' + i); if (!find(list, n)) return n; }
    return b;
  }

  function loadStore(storage) {
    try {
      if (!storage || typeof storage.getItem !== 'function') return { ok: false, code: 'E_CC_TYPE', list: [] };
      const text = storage.getItem(STORE_KEY);
      if (text === null || text === undefined) return { ok: true, code: 'OK', list: [] };
      const r = importJSON(String(text));
      return r.ok ? { ok: true, code: 'OK', list: r.list } : { ok: r.code === 'E_CC_EMPTY', code: r.code, list: [] };
    } catch (e) {
      return { ok: false, code: 'E_CC_TYPE', list: [] };
    }
  }
  function saveStore(storage, list) {
    try {
      if (!storage || typeof storage.setItem !== 'function') return { ok: false, code: 'E_CC_TYPE' };
      const text = JSON.stringify({ format: FORMAT_MANY, v: 1, list: (Array.isArray(list) ? list : []).map(function (c, i) { return fromAny(c, i); }).filter(Boolean).slice(0, MAX_SAVED) });
      if (text.length > MAX_TEXT) return { ok: false, code: 'E_CC_LIMIT' };
      storage.setItem(STORE_KEY, text);
      return { ok: true, code: 'OK' };
    } catch (e) {
      return { ok: false, code: 'E_CC_STORAGE' };
    }
  }

  /** Draft = the work in progress (look, archetype, seed, view), restored when the page reopens. */
  function saveDraft(storage, d) {
    try {
      if (!storage || typeof storage.setItem !== 'function' || !isPlain(d)) return false;
      storage.setItem(DRAFT_KEY, JSON.stringify({ v: 1, look: sanitize(d.look).look, archetype: sanitize({ archetype: d.archetype }).look.archetype, seed: cleanSeed(d.seed), name: cleanName(d.name), view: sanitizeView(d.view) }));
      return true;
    } catch (e) {
      return false;
    }
  }
  function loadDraft(storage) {
    try {
      if (!storage || typeof storage.getItem !== 'function') return null;
      const text = storage.getItem(DRAFT_KEY);
      if (typeof text !== 'string' || text.length > MAX_TEXT) return null;
      const d = JSON.parse(text);
      if (!isPlain(d) || d.v !== 1) return null;
      return { look: sanitize(own(d, 'look')).look, archetype: sanitize({ archetype: own(d, 'archetype') }).look.archetype, seed: cleanSeed(own(d, 'seed')), name: cleanName(own(d, 'name')), view: sanitizeView(own(d, 'view')) };
    } catch (e) {
      return null;
    }
  }

  /**
   * Forge spawn spec for this character ({archetype, seed, overrides}) that the dev panel's host.spawnAhead accepts.
   * Note the game re-applies its Forge rules on spawn (hair hidden under a tophat, nightcap or hood).
   */
  function toSpec(c) {
    try {
      const ch = fromAny(c, 0);
      if (!ch) return null;
      const ov = {};
      LOOK_KEYS.forEach(function (k) { if (k !== 'v' && k !== 'archetype') ov[k] = ch.look[k]; });
      const F = Forge();
      const known = F && F.archetype(ch.archetype) ? ch.archetype : 'patron';
      return { archetype: known, seed: ch.seed, overrides: ov };
    } catch (e) {
      return null;
    }
  }

  const Creator = {
    STORE_KEY: STORE_KEY, DRAFT_KEY: DRAFT_KEY, MAX_SAVED: MAX_SAVED, MAX_TEXT: MAX_TEXT, MAX_NAME: MAX_NAME,
    DEFAULTS: Object.freeze(Object.assign({}, DEFAULTS)), LOOK_KEYS: Object.freeze(LOOK_KEYS.slice()),
    POSES: Object.freeze(POSES.map(function (p) { return Object.freeze(p); })), VIEW_DEFAULTS: Object.freeze(Object.assign({}, VIEW_DEFAULTS)),
    fields: fields, sanitize: sanitize, setField: setField, getField: getField, deriveAcc: deriveAcc, hairHidden: hairHidden,
    archetypes: archetypes, preset: preset, randomize: randomize, mulberry32: mulberry32, cleanSeed: cleanSeed,
    poseEcho: poseEcho, sanitizeView: sanitizeView,
    cleanName: cleanName, character: character, fromAny: fromAny, exportJSON: exportJSON, importJSON: importJSON,
    upsert: upsert, remove: remove, find: find, freeName: freeName,
    loadStore: loadStore, saveStore: saveStore, saveDraft: saveDraft, loadDraft: loadDraft, toSpec: toSpec
  };
  VCS.Creator = Creator;
  if (typeof module !== 'undefined' && module.exports) module.exports = Creator;
})(typeof window !== 'undefined' ? window : globalThis);
