(function (root) {
  'use strict';
  const VCS = (root.VCS = root.VCS || {});

  const SCHEMA = 1;
  const MAX_ESSENCE = 1000000;
  const MAX_STAT = 1000000000;
  const MAX_TIER = 3;
  const STAT_KEYS = ['runs', 'wins', 'nightsSurvived', 'peopleFed', 'bestNights', 'essenceEarned'];
  const TOP_KEYS = ['v', 'essence', 'upgrades', 'stats'];

  function getData() {
    let d = root.VCS && root.VCS.UpgradeData;
    if (!d && typeof require === 'function') {
      try { d = require('./data/upgrades.js'); } catch (e) { d = null; }
    }
    return d;
  }
  function logger() {
    try { return root.VCS && root.VCS.Log ? root.VCS.Log.get('meta') : null; } catch (e) { return null; }
  }
  function warn(msg, data) {
    try { const l = logger(); if (l && typeof l.warn === 'function') l.warn(msg, data); } catch (e) { /* ignore */ }
  }

  function hasOwn(o, k) { return Object.prototype.hasOwnProperty.call(o, k); }
  function isNum(x) { return typeof x === 'number' && isFinite(x); }
  function isPlain(o) {
    if (!o || typeof o !== 'object' || Array.isArray(o)) return false;
    const p = Object.getPrototypeOf(o);
    return p === Object.prototype || p === null;
  }
  function upgradeList() { const d = getData(); return d ? d.upgrades : []; }
  function boonList() { const d = getData(); return d ? d.boons : []; }
  function upgradeById(id) {
    const l = upgradeList();
    for (let i = 0; i < l.length; i++) if (l[i].id === id) return l[i];
    return null;
  }
  function boonById(id) {
    const l = boonList();
    for (let i = 0; i < l.length; i++) if (l[i].id === id) return l[i];
    return null;
  }

  function create() {
    const upgrades = {};
    upgradeList().forEach(function (u) { upgrades[u.id] = 0; });
    return {
      v: SCHEMA, essence: 0, upgrades: upgrades,
      stats: { runs: 0, wins: 0, nightsSurvived: 0, peopleFed: 0, bestNights: 0, essenceEarned: 0 }
    };
  }

  /** Non-negative number -> floored int clamped to max; else null. */
  function toInt(x, max) {
    if (!isNum(x) || x < 0) return null;
    const f = Math.floor(x);
    return f > max ? max : f;
  }

  function sanitize(obj) {
    try {
      if (!isPlain(obj)) return null;
      Object.keys(obj).forEach(function (k) {
        if (TOP_KEYS.indexOf(k) < 0) warn('unknown meta key dropped', { key: String(k).slice(0, 32) });
      });
      if (!hasOwn(obj, 'v') || obj.v !== SCHEMA) return null;
      const essence = hasOwn(obj, 'essence') ? toInt(obj.essence, MAX_ESSENCE) : null;
      if (essence === null) return null;
      const out = create();
      out.essence = essence;
      if (hasOwn(obj, 'upgrades')) {
        const up = obj.upgrades;
        if (!isPlain(up)) return null;
        const keys = Object.keys(up);
        for (let i = 0; i < keys.length; i++) {
          const k = keys[i];
          if (!upgradeById(k)) { warn('unknown upgrade dropped', { id: String(k).slice(0, 32) }); continue; }
          const t = toInt(up[k], MAX_TIER);
          if (t === null) return null;
          out.upgrades[k] = t;
        }
      }
      if (hasOwn(obj, 'stats')) {
        const st = obj.stats;
        if (!isPlain(st)) return null;
        const keys = Object.keys(st);
        for (let i = 0; i < keys.length; i++) {
          const k = keys[i];
          if (STAT_KEYS.indexOf(k) < 0) { warn('unknown stat dropped', { key: String(k).slice(0, 32) }); continue; }
          const n = toInt(st[k], MAX_STAT);
          if (n === null) return null;
          out.stats[k] = n;
        }
      }
      return out;
    } catch (e) {
      warn('sanitize failed', { err: String(e && e.message) });
      return null;
    }
  }

  function migrate(v, data) {
    try {
      if (!isNum(v) || v < 0 || v !== Math.floor(v)) return { ok: false, data: null, code: 'E_SAVE_SCHEMA' };
      if (v > SCHEMA) return { ok: false, data: null, code: 'E_SAVE_VERSION' };
      if (v === 1) return { ok: true, data: data, code: null };
      if (v === 0) {
        if (!isPlain(data) || !hasOwn(data, 'essence') || !isNum(data.essence) || !hasOwn(data, 'bought') || !Array.isArray(data.bought)) {
          return { ok: false, data: null, code: 'E_SAVE_SCHEMA' };
        }
        const m = create();
        m.essence = data.essence;
        data.bought.forEach(function (id) {
          if (typeof id === 'string' && upgradeById(id)) m.upgrades[id] = 1;
        });
        return { ok: true, data: m, code: null };
      }
      return { ok: false, data: null, code: 'E_SAVE_SCHEMA' };
    } catch (e) {
      return { ok: false, data: null, code: 'E_SAVE_SCHEMA' };
    }
  }

  function tierOf(meta, id) {
    try {
      if (!meta || !isPlain(meta.upgrades) || !hasOwn(meta.upgrades, id) || !upgradeById(id)) return 0;
      const t = meta.upgrades[id];
      return isNum(t) ? Math.max(0, Math.min(MAX_TIER, Math.floor(t))) : 0;
    } catch (e) { return 0; }
  }

  function costOf(meta, id) {
    const u = upgradeById(id);
    if (!u) return null;
    const t = tierOf(meta, id);
    return t >= MAX_TIER ? null : u.costs[t];
  }

  function buy(meta, id) {
    try {
      const u = upgradeById(id);
      if (!u) return { ok: false, code: 'E_META_UNKNOWN', cost: null };
      if (!meta || typeof meta !== 'object' || !isPlain(meta.upgrades)) return { ok: false, code: 'E_META_UNKNOWN', cost: null };
      const cost = costOf(meta, id);
      if (cost === null) return { ok: false, code: 'E_META_MAX', cost: null };
      if (!isNum(meta.essence) || meta.essence < cost) return { ok: false, code: 'E_META_POOR', cost: cost };
      meta.essence -= cost;
      meta.upgrades[id] = tierOf(meta, id) + 1;
      return { ok: true, code: 'OK', cost: cost };
    } catch (e) {
      return { ok: false, code: 'E_META_UNKNOWN', cost: null };
    }
  }

  function cleanInt(x) { return isNum(x) && x > 0 ? Math.min(Math.floor(x), MAX_STAT) : 0; }

  function essenceFor(run) {
    try {
      if (!run || typeof run !== 'object') return 0;
      return cleanInt(run.nights) * 4 + cleanInt(run.fed) + (run.won ? 15 : 0);
    } catch (e) { return 0; }
  }

  function recordRun(meta, run) {
    try {
      if (!meta || typeof meta !== 'object' || !isPlain(meta.stats)) return 0;
      const nights = cleanInt(run && run.nights);
      const fed = cleanInt(run && run.fed);
      const won = !!(run && run.won);
      const bonus = Math.min(1000, cleanInt(run && run.bonus));
      const earned = essenceFor({ nights: nights, fed: fed, won: won }) + bonus;
      const cap = function (n) { return Math.min(MAX_STAT, n); };
      const s = meta.stats;
      meta.essence = Math.min(MAX_ESSENCE, cleanInt(meta.essence) + earned);
      s.runs = cap(cleanInt(s.runs) + 1);
      s.wins = cap(cleanInt(s.wins) + (won ? 1 : 0));
      s.nightsSurvived = cap(cleanInt(s.nightsSurvived) + nights);
      s.peopleFed = cap(cleanInt(s.peopleFed) + fed);
      s.bestNights = Math.max(cleanInt(s.bestNights), nights);
      s.essenceEarned = cap(cleanInt(s.essenceEarned) + earned);
      return earned;
    } catch (e) { return 0; }
  }

  function apply(fx, effect, op, val) {
    if (!hasOwn(fx, effect) || !isNum(val)) return;
    if (op === 'mul') fx[effect] *= val;
    else if (op === 'add') fx[effect] += val;
  }

  function effects(meta, boons, extra) {
    const d = getData();
    const fx = {};
    if (!d) return fx;
    Object.keys(d.EFFECT_DEFAULTS).forEach(function (k) { fx[k] = d.EFFECT_DEFAULTS[k]; });
    try {
      d.upgrades.forEach(function (u) {
        const t = tierOf(meta, u.id);
        if (t > 0) apply(fx, u.effect, u.op, u.tiers[t - 1]);
      });
      if (Array.isArray(boons)) {
        boons.forEach(function (id) {
          const b = typeof id === 'string' ? boonById(id) : null;
          if (b) apply(fx, b.effect, b.op, b.value);
        });
      }
      if (Array.isArray(extra)) {
        extra.forEach(function (e) {
          if (e && typeof e === 'object' && typeof e.effect === 'string' && e.effect !== 'bloodNow') apply(fx, e.effect, e.op, e.value);
        });
      }
      Object.keys(d.EFFECT_LIMITS).forEach(function (k) {
        const lim = d.EFFECT_LIMITS[k];
        fx[k] = Math.max(lim[0], Math.min(lim[1], fx[k]));
      });
    } catch (e) { warn('effects failed', { err: String(e && e.message) }); }
    return fx;
  }

  /** Small deterministic PRNG (mulberry32). */
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

  function rollBoons(seed, taken) {
    try {
      const tk = Array.isArray(taken) ? taken : [];
      const pool = boonList().filter(function (b) { return b.repeat || tk.indexOf(b.id) < 0; }).map(function (b) { return b.id; });
      const rng = mulberry32(isNum(seed) ? seed : 0);
      const n = Math.min(3, pool.length);
      for (let i = 0; i < n; i++) {
        const j = i + Math.floor(rng() * (pool.length - i));
        const tmp = pool[i]; pool[i] = pool[j]; pool[j] = tmp;
      }
      return pool.slice(0, n);
    } catch (e) { return []; }
  }

  const Meta = {
    SCHEMA: SCHEMA, create: create, sanitize: sanitize, migrate: migrate, tierOf: tierOf, costOf: costOf,
    buy: buy, essenceFor: essenceFor, recordRun: recordRun, effects: effects, rollBoons: rollBoons,
    boonById: boonById, upgradeById: upgradeById
  };
  VCS.Meta = Meta;
  if (typeof module !== 'undefined' && module.exports) module.exports = Meta;
})(typeof window !== 'undefined' ? window : globalThis);
