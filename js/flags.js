(function (root) {
  'use strict';
  const VCS = (root.VCS = root.VCS || {});

  const FLAGS_KEY = 'vcs.dev.flags';
  const TUN_KEY = 'vcs.dev.tun';
  const BAD = Object.create(null);
  ['__proto__', 'constructor', 'prototype'].forEach(function (k) { BAD[k] = 1; });

  let flags = Object.create(null); // id -> {def, desc, urlSet, value}
  let tuns = Object.create(null); // sys -> key -> {def,min,max,step,desc,value}
  let listeners = [];
  let saved = { flags: null, tun: null };
  let urlFlags = Object.create(null);
  let urlTun = Object.create(null);

  function log() {
    return VCS.Log && VCS.Log.get ? VCS.Log.get('flags') : { warn() {}, error() {}, debug() {}, info() {} };
  }
  function safeName(s) {
    return typeof s === 'string' && s.length > 0 && s.length < 80 && /^[A-Za-z0-9_.\-]+$/.test(s) && !BAD[s] && s.split('.').every(function (p) { return !BAD[p]; });
  }
  function storage() {
    try { return typeof localStorage !== 'undefined' ? localStorage : null; } catch (e) { return null; }
  }
  function readStore(key) {
    try {
      const ls = storage();
      if (!ls) return null;
      const raw = ls.getItem(key);
      if (!raw) return null;
      const o = JSON.parse(raw);
      return o && typeof o === 'object' && !Array.isArray(o) ? o : null;
    } catch (e) { return null; }
  }
  function writeStore(key, obj) {
    try {
      const ls = storage();
      if (ls) ls.setItem(key, JSON.stringify(obj));
    } catch (e) { /* ignore */ }
  }
  function clamp(t, v) {
    let n = Number(v);
    if (typeof v === 'boolean' || v === null || v === '' || !isFinite(n)) return null;
    if (n < t.min) n = t.min;
    if (n > t.max) n = t.max;
    return n;
  }
  function fire(kind, id, value) {
    listeners.slice().forEach(function (fn) {
      try { fn({ kind: kind, id: id, value: value }); } catch (e) { log().error('flags listener', e); }
    });
  }
  function parseBool(s) {
    s = String(s).toLowerCase();
    if (s === 'on' || s === '1' || s === 'true') return true;
    if (s === 'off' || s === '0' || s === 'false') return false;
    return null;
  }

  /** Parse "a.b:on,c.d:off" into a null-prototype map. Bad entries are skipped. */
  function parseSys(str) {
    const out = Object.create(null);
    if (typeof str !== 'string') return out;
    str.split(',').forEach(function (part) {
      const i = part.lastIndexOf(':');
      if (i < 1) return;
      const id = part.slice(0, i).trim();
      const b = parseBool(part.slice(i + 1).trim());
      if (safeName(id) && b !== null) out[id] = b;
    });
    return out;
  }
  /** Parse "sys.key:0.5,..." (last dot splits system from key). Values stay raw numbers. */
  function parseTun(str) {
    const out = Object.create(null);
    if (typeof str !== 'string') return out;
    str.split(',').forEach(function (part) {
      const i = part.lastIndexOf(':');
      if (i < 1) return;
      const path = part.slice(0, i).trim();
      const raw = part.slice(i + 1).trim();
      const d = path.lastIndexOf('.');
      if (d < 1 || !safeName(path) || raw === '') return;
      const n = Number(raw);
      if (!isFinite(n)) return;
      out[path] = n;
    });
    return out;
  }

  function resolveFlag(id, f) {
    if (id in urlFlags) return urlFlags[id];
    if (saved.flags && Object.prototype.hasOwnProperty.call(saved.flags, id) && typeof saved.flags[id] === 'boolean') return saved.flags[id];
    return f.def;
  }
  function resolveTun(sys, key, t) {
    const p = sys + '.' + key;
    if (p in urlTun) { const c = clamp(t, urlTun[p]); if (c !== null) return c; }
    if (saved.tun && saved.tun[sys] && Object.prototype.hasOwnProperty.call(saved.tun[sys], key)) {
      const c = clamp(t, saved.tun[sys][key]);
      if (c !== null) return c;
    }
    return t.def;
  }

  function persist() {
    const fo = {};
    Object.keys(flags).forEach(function (id) { if (flags[id].value !== flags[id].def) fo[id] = flags[id].value; });
    const to = {};
    Object.keys(tuns).forEach(function (s) {
      Object.keys(tuns[s]).forEach(function (k) {
        if (tuns[s][k].value !== tuns[s][k].def) { to[s] = to[s] || {}; to[s][k] = tuns[s][k].value; }
      });
    });
    saved = { flags: fo, tun: to };
    writeStore(FLAGS_KEY, fo);
    writeStore(TUN_KEY, to);
  }

  const Flags = {
    FLAGS_KEY: FLAGS_KEY,
    TUN_KEY: TUN_KEY,
    parseSys: parseSys,
    parseTun: parseTun,

    /** Read URL (search string) and storage. Call at boot (and in tests). */
    load: function (search, useStore) {
      let p = null;
      try { p = new root.URLSearchParams(search || ''); } catch (e) { p = null; }
      urlFlags = parseSys(p && p.get('sys'));
      urlTun = parseTun(p && p.get('tun'));
      saved = useStore === false ? { flags: null, tun: null } : { flags: readStore(FLAGS_KEY), tun: readStore(TUN_KEY) };
      Object.keys(flags).forEach(function (id) { flags[id].value = resolveFlag(id, flags[id]); });
      Object.keys(tuns).forEach(function (s) {
        Object.keys(tuns[s]).forEach(function (k) { tuns[s][k].value = resolveTun(s, k, tuns[s][k]); });
      });
    },

    register: function (id, def, desc) {
      if (!safeName(id)) { log().warn('flag id rejected: ' + String(id)); return false; }
      const d = !!def;
      const f = { def: d, desc: String(desc || ''), value: d };
      flags[id] = f;
      f.value = resolveFlag(id, f);
      return true;
    },
    get: function (id) {
      const f = Object.prototype.hasOwnProperty.call(flags, id) ? flags[id] : null;
      return f ? f.value : false;
    },
    set: function (id, v) {
      const f = Object.prototype.hasOwnProperty.call(flags, id) ? flags[id] : null;
      if (!f) return false;
      const b = !!v;
      if (f.value === b) return true;
      f.value = b;
      persist();
      fire('flag', id, b);
      return true;
    },
    list: function () {
      return Object.keys(flags).sort().map(function (id) { return { id: id, value: flags[id].value, def: flags[id].def, desc: flags[id].desc }; });
    },

    registerTun: function (sys, key, o) {
      if (!safeName(sys) || !safeName(key) || key.indexOf('.') >= 0 || !o || typeof o !== 'object') { log().warn('tunable rejected: ' + sys + '.' + key); return false; }
      const min = Number(o.min), max = Number(o.max), def = Number(o.value);
      if (!isFinite(min) || !isFinite(max) || !isFinite(def) || min > max) { log().warn('tunable bad range: ' + sys + '.' + key); return false; }
      const t = { min: min, max: max, step: Number(o.step) > 0 ? Number(o.step) : (max - min) / 100 || 1, desc: String(o.desc || ''), def: Math.min(max, Math.max(min, def)), value: 0 };
      tuns[sys] = tuns[sys] || Object.create(null);
      tuns[sys][key] = t;
      t.value = resolveTun(sys, key, t);
      return true;
    },
    tun: function (sys, key) {
      return tuns[sys] && tuns[sys][key] ? tuns[sys][key].value : undefined;
    },
    setTun: function (sys, key, v) {
      const t = tuns[sys] && tuns[sys][key];
      if (!t) return false;
      const c = clamp(t, v);
      if (c === null) return false;
      if (c === t.value) return true;
      t.value = c;
      persist();
      fire('tun', sys + '.' + key, c);
      return true;
    },
    listTun: function () {
      const out = [];
      Object.keys(tuns).sort().forEach(function (s) {
        Object.keys(tuns[s]).forEach(function (k) {
          const t = tuns[s][k];
          out.push({ sys: s, key: k, value: t.value, def: t.def, min: t.min, max: t.max, step: t.step, desc: t.desc });
        });
      });
      return out;
    },

    onChange: function (fn) {
      if (typeof fn === 'function') listeners.push(fn);
      return function () { listeners = listeners.filter(function (f) { return f !== fn; }); };
    },

    /** Values that differ from defaults, for copy/paste. */
    toJSON: function () {
      const o = { flags: {}, tun: {} };
      Object.keys(flags).forEach(function (id) { if (flags[id].value !== flags[id].def) o.flags[id] = flags[id].value; });
      Object.keys(tuns).forEach(function (s) {
        Object.keys(tuns[s]).forEach(function (k) {
          if (tuns[s][k].value !== tuns[s][k].def) { o.tun[s] = o.tun[s] || {}; o.tun[s][k] = tuns[s][k].value; }
        });
      });
      return o;
    },
    /** Apply {flags:{id:bool}, tun:{sys:{key:n}}}. Unknown / unsafe entries are ignored. Returns count applied. */
    fromJSON: function (input) {
      let o = input;
      if (typeof o === 'string') { try { o = JSON.parse(o); } catch (e) { return 0; } }
      if (!o || typeof o !== 'object') return 0;
      let n = 0;
      const fo = o.flags && typeof o.flags === 'object' ? o.flags : {};
      Object.keys(fo).forEach(function (id) {
        if (!safeName(id) || typeof fo[id] !== 'boolean') return;
        if (Flags.set(id, fo[id])) n++;
      });
      const to = o.tun && typeof o.tun === 'object' ? o.tun : {};
      Object.keys(to).forEach(function (s) {
        if (!safeName(s) || !to[s] || typeof to[s] !== 'object') return;
        Object.keys(to[s]).forEach(function (k) {
          if (!safeName(k)) return;
          if (Flags.setTun(s, k, to[s][k])) n++;
        });
      });
      return n;
    },
    resetAll: function () {
      Object.keys(flags).forEach(function (id) { Flags.set(id, flags[id].def); });
      Object.keys(tuns).forEach(function (s) {
        Object.keys(tuns[s]).forEach(function (k) { Flags.setTun(s, k, tuns[s][k].def); });
      });
    },
    /** Test helper: forget everything. */
    _clear: function () { flags = Object.create(null); tuns = Object.create(null); listeners = []; saved = { flags: null, tun: null }; urlFlags = Object.create(null); urlTun = Object.create(null); }
  };

  VCS.Flags = Flags;
  if (typeof module !== 'undefined' && module.exports) module.exports = Flags;
})(typeof window !== 'undefined' ? window : globalThis);
