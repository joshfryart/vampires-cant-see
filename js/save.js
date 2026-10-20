(function (root) {
  'use strict';
  const VCS = (root.VCS = root.VCS || {});

  const KEYS = Object.freeze({ run: 'vcs.run', meta: 'vcs.meta' });
  const TAB_KEY = 'vcs.tab';
  const TAB_STALE_MS = 12000;
  const MAX_BYTES = 65536;
  const MAX_IMPORT = 131072;
  const RUN_SCHEMA = 4;
  const MAX_DEPTH = 12;
  const BAD_KEYS = ['__proto__', 'constructor', 'prototype'];
  const ENV_KEYS = ['app', 'kind', 'v', 'game', 'sum', 'data'];
  const IMPORT_KEYS = ['app', 'kind', 'v', 'game', 'meta', 'run'];
  const RUN_KEYS = ['v', 'map', 'player', 'doors', 'people', 'night', 'run', 'rocks'];
  const RUN_RUN_KEYS = ['seed', 'boons', 'closedSafe', 'pendingBoons'];

  function logger() {
    try {
      return root.VCS && root.VCS.Log ? root.VCS.Log.get('save') : null;
    } catch (e) {
      return null;
    }
  }
  function log(level, msg, data) {
    try {
      const l = logger();
      if (l && typeof l[level] === 'function') l[level](msg, data);
    } catch (e) { /* ignore */ }
  }
  function warn(msg, data) { log('warn', msg, data); }

  function hasOwn(o, k) { return Object.prototype.hasOwnProperty.call(o, k); }
  function isNum(x) { return typeof x === 'number' && isFinite(x); }
  function isInt(x) { return typeof x === 'number' && Number.isInteger(x); }
  function isPlain(o) {
    if (!o || typeof o !== 'object' || Array.isArray(o)) return false;
    const p = Object.getPrototypeOf(o);
    return p === Object.prototype || p === null;
  }
  function isBadKey(k) { return BAD_KEYS.indexOf(k) !== -1; }
  function exactKeys(o, keys) {
    const own = Object.keys(o);
    if (own.length !== keys.length) return false;
    for (let i = 0; i < keys.length; i++) if (!hasOwn(o, keys[i])) return false;
    return true;
  }
  function gameVersion() {
    try {
      return (root.VCS && root.VCS.Log && root.VCS.Log.VERSION) || '?';
    } catch (e) {
      return '?';
    }
  }

  /** FNV-1a 32-bit over UTF-16 code units, 8 lowercase hex chars. */
  function checksum(str) {
    const s = typeof str === 'string' ? str : String(str);
    let h = 0x811c9dc5;
    for (let i = 0; i < s.length; i++) {
      h ^= s.charCodeAt(i);
      h = Math.imul(h, 16777619) >>> 0;
    }
    return ('00000000' + (h >>> 0).toString(16)).slice(-8);
  }

  function depthOk(v) {
    const stack = [[v, 1]];
    let guard = 0;
    while (stack.length) {
      const it = stack.pop();
      const x = it[0];
      if (x && typeof x === 'object') {
        if (it[1] > MAX_DEPTH) return false;
        if (++guard > 200000) return false;
        const ks = Object.keys(x);
        for (let i = 0; i < ks.length; i++) stack.push([x[ks[i]], it[1] + 1]);
      }
    }
    return true;
  }

  /** Parse JSON text safely. */
  function safeParse(text) {
    try {
      if (typeof text !== 'string') return { ok: false, value: null, code: 'E_SAVE_PARSE' };
      let bad = false;
      let value;
      try {
        value = JSON.parse(text, function (k, v) {
          if (isBadKey(k)) bad = true;
          return v;
        });
      } catch (e) {
        return { ok: false, value: null, code: 'E_SAVE_PARSE' };
      }
      if (bad) return { ok: false, value: null, code: 'E_SAVE_BAD_KEY' };
      if (!depthOk(value)) return { ok: false, value: null, code: 'E_SAVE_SCHEMA' };
      return { ok: true, value: value, code: '' };
    } catch (e) {
      warn('safeParse failed', { message: String(e && e.message) });
      return { ok: false, value: null, code: 'E_SAVE_PARSE' };
    }
  }

  function wrap(kind, v, data) {
    return { app: 'vcs', kind: kind, v: v, game: gameVersion(), sum: checksum(JSON.stringify(data)), data: data };
  }

  function unwrap(env, kind) {
    try {
      if (!isPlain(env) || !exactKeys(env, ENV_KEYS)) return { ok: false, v: 0, data: null, code: 'E_SAVE_SCHEMA' };
      if (env.app !== 'vcs' || env.kind !== kind || !isInt(env.v) || env.v < 0 || typeof env.sum !== 'string') {
        return { ok: false, v: 0, data: null, code: 'E_SAVE_SCHEMA' };
      }
      if (checksum(JSON.stringify(env.data)) !== env.sum) return { ok: false, v: 0, data: null, code: 'E_SAVE_CHECKSUM' };
      return { ok: true, v: env.v, data: env.data, code: '' };
    } catch (e) {
      return { ok: false, v: 0, data: null, code: 'E_SAVE_SCHEMA' };
    }
  }

  function memoryStorage() {
    const m = new Map();
    return {
      getItem: function (k) { return m.has(k) ? m.get(k) : null; },
      setItem: function (k, v) { m.set(k, String(v)); },
      removeItem: function (k) { m.delete(k); }
    };
  }

  function probe(storage) {
    try {
      if (!storage || typeof storage.getItem !== 'function' || typeof storage.setItem !== 'function' || typeof storage.removeItem !== 'function') return false;
      const k = 'vcs.probe';
      storage.setItem(k, '1');
      const ok = storage.getItem(k) === '1';
      storage.removeItem(k);
      return ok;
    } catch (e) {
      return false;
    }
  }

  /** Create a store over a Storage-like object (or memory when unusable). */
  function create(storage, opts) {
    const o = opts && typeof opts === 'object' ? opts : {};
    const maxBytes = isNum(o.maxBytes) && o.maxBytes > 0 ? o.maxBytes : MAX_BYTES;
    let persistent = true;
    let st = storage;
    if (!probe(storage)) {
      warn('storage unavailable, using memory');
      st = memoryStorage();
      persistent = false;
    }

    function keyOf(kind) { return typeof kind === 'string' && hasOwn(KEYS, kind) ? KEYS[kind] : null; }
    function get(k) {
      try {
        const v = st.getItem(k);
        return typeof v === 'string' ? v : null;
      } catch (e) {
        return null;
      }
    }
    function tryRemove(k) {
      try { st.removeItem(k); } catch (e) { /* ignore */ }
    }

    // Returns {ok, env, v, data, code}; code E_SAVE_NONE when text is null.
    function check(text, kind) {
      if (text === null) return { ok: false, code: 'E_SAVE_NONE' };
      if (text.length > maxBytes) return { ok: false, code: 'E_SAVE_TOO_BIG' };
      const p = safeParse(text);
      if (!p.ok) return { ok: false, code: p.code };
      const u = unwrap(p.value, kind);
      if (!u.ok) return { ok: false, code: u.code };
      return { ok: true, env: p.value, v: u.v, data: u.data, code: '' };
    }

    function write(kind, v, data) {
      const key = keyOf(kind);
      if (!key) return { ok: false, code: 'E_SAVE_SCHEMA' };
      let tmpSet = false;
      try {
        let str;
        try {
          str = JSON.stringify(wrap(kind, v, data));
        } catch (e) {
          return { ok: false, code: 'E_SAVE_SCHEMA' };
        }
        if (typeof str !== 'string') return { ok: false, code: 'E_SAVE_SCHEMA' };
        if (str.length > maxBytes) {
          warn('save too big', { kind: kind, size: str.length });
          return { ok: false, code: 'E_SAVE_TOO_BIG' };
        }
        const tmp = key + '.tmp';
        st.setItem(tmp, str);
        tmpSet = true;
        if (st.getItem(tmp) !== str) {
          tryRemove(tmp);
          warn('save verify mismatch', { kind: kind });
          return { ok: false, code: 'E_SAVE_VERIFY' };
        }
        const cur = get(key);
        if (cur !== null && check(cur, kind).ok) st.setItem(key + '.bak', cur);
        st.setItem(key, str);
        st.removeItem(tmp);
        return { ok: true, code: '' };
      } catch (e) {
        if (tmpSet) tryRemove(key + '.tmp');
        else tryRemove(key + '.tmp');
        warn('save failed', { kind: kind, message: String(e && e.message) });
        return { ok: false, code: 'E_SAVE_QUOTA' };
      }
    }

    function readFull(kind) {
      const key = keyOf(kind);
      if (!key) return { ok: false, v: 0, data: null, env: null, source: 'none', code: 'E_SAVE_SCHEMA' };
      const mainText = get(key);
      const m = check(mainText, kind);
      if (m.ok) return { ok: true, v: m.v, data: m.data, env: m.env, source: 'main', code: '' };
      if (m.code !== 'E_SAVE_NONE') warn('main save bad, trying backup', { kind: kind, code: m.code });
      const bakText = get(key + '.bak');
      const b = check(bakText, kind);
      if (b.ok) {
        try { st.setItem(key, bakText); } catch (e) { warn('could not repair main from backup', { kind: kind }); }
        return { ok: true, v: b.v, data: b.data, env: b.env, source: 'bak', code: m.code };
      }
      if (bakText !== null) warn('backup save bad', { kind: kind, code: b.code });
      return { ok: false, v: 0, data: null, env: null, source: 'none', code: m.code };
    }

    function read(kind) {
      try {
        const r = readFull(kind);
        return { ok: r.ok, v: r.v, data: r.data, source: r.source, code: r.code };
      } catch (e) {
        return { ok: false, v: 0, data: null, source: 'none', code: 'E_SAVE_PARSE' };
      }
    }

    function readEnv(kind) {
      try {
        const r = readFull(kind);
        return r.ok ? r.env : null;
      } catch (e) {
        return null;
      }
    }

    function remove(kind, ropts) {
      const key = keyOf(kind);
      if (!key) return;
      tryRemove(key);
      if (!(ropts && ropts.keepBak === true)) tryRemove(key + '.bak');
      tryRemove(key + '.tmp');
    }

    /** Copy a valid .bak over main. Returns true when restored. */
    function restoreBak(kind) {
      try {
        const key = keyOf(kind);
        if (!key) return false;
        const bakText = get(key + '.bak');
        if (!check(bakText, kind).ok) return false;
        st.setItem(key, bakText);
        return true;
      } catch (e) {
        warn('restoreBak failed', { message: String(e && e.message) });
        return false;
      }
    }

    function has(kind) { return read(kind).ok; }

    return { persistent: persistent, write: write, read: read, readEnv: readEnv, remove: remove, restoreBak: restoreBak, has: has };
  }

  function exportText(store) {
    let meta = null;
    let run = null;
    try {
      if (store && typeof store.readEnv === 'function') {
        meta = store.readEnv('meta') || null;
        run = store.readEnv('run') || null;
      } else if (store && typeof store.read === 'function') {
        const m = store.read('meta');
        if (m && m.ok) meta = wrap('meta', m.v, m.data);
        const r = store.read('run');
        if (r && r.ok) run = wrap('run', r.v, r.data);
      }
      return JSON.stringify({ app: 'vcs', kind: 'export', v: 1, game: gameVersion(), meta: meta, run: run }, null, 2);
    } catch (e) {
      warn('exportText failed', { message: String(e && e.message) });
      return '';
    }
  }

  function parseImport(text) {
    const fail = function (code) { return { ok: false, meta: null, run: null, code: code }; };
    try {
      if (typeof text !== 'string' || text.length > MAX_IMPORT) return fail('E_SAVE_TOO_BIG');
      const p = safeParse(text);
      if (!p.ok) return fail(p.code);
      const top = p.value;
      if (!isPlain(top) || !exactKeys(top, IMPORT_KEYS)) return fail('E_SAVE_SCHEMA');
      if (top.app !== 'vcs' || top.kind !== 'export' || top.v !== 1) return fail('E_SAVE_SCHEMA');
      const m = unwrap(top.meta, 'meta');
      if (!m.ok) return fail(m.code);
      let run = null;
      if (top.run !== null) {
        const r = unwrap(top.run, 'run');
        if (!r.ok) return fail(r.code);
        run = { v: r.v, data: r.data };
      }
      return { ok: true, meta: { v: m.v, data: m.data }, run: run, code: '' };
    } catch (e) {
      warn('parseImport failed', { message: String(e && e.message) });
      return fail('E_SAVE_PARSE');
    }
  }

  function copyPlain(src) {
    const out = {};
    const ks = Object.keys(src);
    for (let i = 0; i < ks.length; i++) {
      if (isBadKey(ks[i])) continue;
      out[ks[i]] = src[ks[i]];
    }
    return out;
  }

  function migrateRun(v, data) {
    try {
      if (!isInt(v) || v < 1 || !isPlain(data)) return { ok: false, data: null, code: 'E_SAVE_SCHEMA' };
      if (v > RUN_SCHEMA) return { ok: false, data: null, code: 'E_SAVE_VERSION' };
      if (v === 4) return { ok: true, data: data, code: '' };
      const out = copyPlain(data);
      out.v = 4;
      if (v === 3) {
        if (!isPlain(data.run)) return { ok: false, data: null, code: 'E_SAVE_SCHEMA' };
        out.run = copyPlain(data.run);
        out.run.hunger = null;
        return { ok: true, data: out, code: '' };
      }
      out.run = { seed: 1, boons: [], closedSafe: {}, pendingBoons: null, hunger: null };
      if (v === 1) delete out.night;
      return { ok: true, data: out, code: '' };
    } catch (e) {
      return { ok: false, data: null, code: 'E_SAVE_SCHEMA' };
    }
  }

  // ---- sanitizeRun helpers (each returns undefined on failure) ----
  function cell(c) {
    if (!Array.isArray(c) || c.length !== 2 || !isInt(c[0]) || !isInt(c[1])) return undefined;
    return [c[0], c[1]];
  }
  function cells(arr, max) {
    if (!Array.isArray(arr) || arr.length > max) return undefined;
    const out = [];
    for (let i = 0; i < arr.length; i++) {
      const c = cell(arr[i]);
      if (!c) return undefined;
      out.push(c);
    }
    return out;
  }
  function cellMap(obj, max) {
    if (!isPlain(obj)) return undefined;
    const out = {};
    const ks = Object.keys(obj);
    for (let i = 0; i < ks.length; i++) {
      if (isBadKey(ks[i])) { warn('dropping bad key in run', { key: ks[i] }); continue; }
      const c = cells(obj[ks[i]], max);
      if (!c) return undefined;
      out[ks[i]] = c;
    }
    return out;
  }
  function strList(arr, maxLen, maxItem) {
    if (!Array.isArray(arr) || arr.length > maxLen) return undefined;
    const out = [];
    for (let i = 0; i < arr.length; i++) {
      if (typeof arr[i] !== 'string' || arr[i].length > maxItem) return undefined;
      out.push(arr[i]);
    }
    return out;
  }
  const HUNGER_KEYS = ['v', 'fear', 'over', 'giftsTonight', 'gifts', 'essenceBonus', 'nextBlood'];
  function cleanHunger(h) {
    if (!isPlain(h)) return undefined;
    const ks = Object.keys(h);
    if (ks.length !== HUNGER_KEYS.length) return undefined;
    for (let i = 0; i < HUNGER_KEYS.length; i++) if (!hasOwn(h, HUNGER_KEYS[i])) return undefined;
    const out = {};
    for (let i = 0; i < HUNGER_KEYS.length; i++) {
      const k = HUNGER_KEYS[i];
      if (k === 'gifts') {
        const g = strList(h.gifts, 20, 24);
        if (!g) return undefined;
        out.gifts = g;
      } else {
        if (!isNum(h[k]) || h[k] < 0) return undefined;
        out[k] = h[k];
      }
    }
    return out;
  }
  function cloneJson(v, depth) {
    if (depth > MAX_DEPTH) return undefined;
    if (v === null || typeof v === 'string' || typeof v === 'boolean') return v;
    if (typeof v === 'number') return isFinite(v) ? v : undefined;
    if (Array.isArray(v)) {
      const a = [];
      for (let i = 0; i < v.length; i++) {
        const c = cloneJson(v[i], depth + 1);
        if (c === undefined) return undefined;
        a.push(c);
      }
      return a;
    }
    if (isPlain(v)) {
      const out = {};
      const ks = Object.keys(v);
      for (let i = 0; i < ks.length; i++) {
        if (isBadKey(ks[i])) continue;
        const c = cloneJson(v[ks[i]], depth + 1);
        if (c === undefined) return undefined;
        out[ks[i]] = c;
      }
      return out;
    }
    return undefined;
  }

  function mod(name, file) {
    try {
      if (root.VCS && root.VCS[name]) return root.VCS[name];
      if (typeof require === 'function' && typeof module !== 'undefined') return require(file);
    } catch (e) { /* ignore */ }
    return null;
  }

  function sanitizeRun(data) {
    try {
      if (!isPlain(data)) return null;
      const keys = Object.keys(data);
      for (let i = 0; i < keys.length; i++) {
        if (RUN_KEYS.indexOf(keys[i]) === -1) warn('dropping unknown run key', { key: keys[i] });
      }
      const g = function (k) { return hasOwn(data, k) ? data[k] : undefined; };
      if (g('v') !== RUN_SCHEMA) return null;
      const map = g('map');
      if (typeof map !== 'string' || map.length < 1 || map.length > 32) return null;
      const pl = g('player');
      if (!isPlain(pl) || !hasOwn(pl, 'x') || !hasOwn(pl, 'y') || !hasOwn(pl, 'angle')) return null;
      if (!isNum(pl.x) || !isNum(pl.y) || !isNum(pl.angle)) return null;
      const doors = cellMap(g('doors'), 512);
      if (!doors) return null;
      const pe = g('people');
      if (!isPlain(pe)) return null;
      const people = {};
      const pk = Object.keys(pe);
      for (let i = 0; i < pk.length; i++) {
        if (isBadKey(pk[i])) { warn('dropping bad key in run', { key: pk[i] }); continue; }
        if (!isNum(pe[pk[i]])) return null;
        people[pk[i]] = pe[pk[i]];
      }
      const r = g('run');
      if (!isPlain(r)) return null;
      for (let i = 0; i < RUN_RUN_KEYS.length; i++) if (!hasOwn(r, RUN_RUN_KEYS[i])) return null;
      if (!isInt(r.seed) || r.seed < 0 || r.seed > 4294967295) return null;
      const boons = strList(r.boons, 20, 24);
      if (!boons) return null;
      const closedSafe = cellMap(r.closedSafe, 16);
      if (!closedSafe) return null;
      let hunger = null;
      if (hasOwn(r, 'hunger') && r.hunger !== null) {
        hunger = cleanHunger(r.hunger);
        if (!hunger) return null;
        const H = mod('Hunger', './hunger.js');
        if (H && typeof H.restore === 'function' && !H.restore(hunger)) {
          warn('hunger failed restore validation');
          return null;
        }
      }
      let pendingGifts = null;
      if (hasOwn(r, 'pendingGifts') && r.pendingGifts !== null) {
        pendingGifts = strList(r.pendingGifts, 3, 24);
        if (!pendingGifts) return null;
      }
      let pending = null;
      if (r.pendingBoons !== null) {
        pending = strList(r.pendingBoons, 3, 24);
        if (!pending) return null;
      }
      const out = {
        v: 4,
        map: map,
        player: { x: pl.x, y: pl.y, angle: pl.angle },
        doors: doors,
        people: people
      };
      if (isInt(data.rocks) && data.rocks >= 0 && data.rocks <= 99) out.rocks = data.rocks;
      if (hasOwn(data, 'night') && data.night !== undefined) {
        if (!isPlain(data.night)) { warn('night is not an object'); return null; }
        const n = cloneJson(data.night, 1);
        if (n === undefined) { warn('night is not clean JSON'); return null; }
        const N = mod('Night', './night.js');
        if (N && typeof N.restore === 'function' && !N.restore(cloneJson(n, 1))) {
          warn('night failed restore validation');
          return null;
        }
        out.night = n;
      }
      out.run = { seed: r.seed, boons: boons, closedSafe: closedSafe, pendingBoons: pending, hunger: hunger, pendingGifts: pendingGifts };
      return out;
    } catch (e) {
      warn('sanitizeRun failed', { message: String(e && e.message) });
      return null;
    }
  }

  /** Run migrate + sanitize on a run payload without writing. @returns {{ok:boolean, code:string}} */
  function validateRun(data, v) {
    try {
      const ver = isInt(v) ? v : (isPlain(data) && isInt(data.v) ? data.v : RUN_SCHEMA);
      const m = migrateRun(ver, data);
      if (!m.ok) return { ok: false, code: m.code };
      if (!sanitizeRun(m.data)) return { ok: false, code: 'E_SAVE_SCHEMA' };
      return { ok: true, code: '' };
    } catch (e) {
      return { ok: false, code: 'E_SAVE_SCHEMA' };
    }
  }

  /** Claim the two-tab lock (heartbeat). Pure over storage. @returns {boolean} written */
  function tabLock(storage, id, now) {
    try {
      if (!storage || typeof id !== 'string' || !id || !isNum(now)) return false;
      storage.setItem(TAB_KEY, JSON.stringify({ id: id, t: now }));
      return true;
    } catch (e) {
      return false;
    }
  }

  /** Is another tab alive? @returns {{other:boolean, id?:string}} */
  function tabCheck(storage, id, now) {
    try {
      if (!storage || !isNum(now)) return { other: false };
      const raw = storage.getItem(TAB_KEY);
      if (typeof raw !== 'string' || raw.length > 256) return { other: false };
      const p = JSON.parse(raw);
      if (!isPlain(p) || typeof p.id !== 'string' || !isNum(p.t)) return { other: false };
      if (p.id === id) return { other: false };
      const age = now - p.t;
      if (age < TAB_STALE_MS && age > -TAB_STALE_MS) return { other: true, id: p.id.slice(0, 40) };
      return { other: false };
    } catch (e) {
      return { other: false };
    }
  }

  const Save = {
    TAB_KEY: TAB_KEY,
    TAB_STALE_MS: TAB_STALE_MS,
    validateRun: validateRun,
    tabLock: tabLock,
    tabCheck: tabCheck,
    KEYS: KEYS,
    MAX_BYTES: MAX_BYTES,
    MAX_IMPORT: MAX_IMPORT,
    RUN_SCHEMA: RUN_SCHEMA,
    checksum: checksum,
    safeParse: safeParse,
    wrap: wrap,
    unwrap: unwrap,
    create: create,
    exportText: exportText,
    parseImport: parseImport,
    migrateRun: migrateRun,
    sanitizeRun: sanitizeRun
  };
  VCS.Save = Save;
  if (typeof module !== 'undefined' && module.exports) module.exports = Save;
})(typeof window !== 'undefined' ? window : globalThis);
