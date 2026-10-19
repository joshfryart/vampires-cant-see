(function (root) {
  'use strict';
  const VCS = (root.VCS = root.VCS || {});

  const SCHEMA = 1;
  const MAX_GIFTS = 20;
  const MAX_GRABBED = 500;
  const MAX_NEXT_BLOOD = 1000;
  const MAX_ESSENCE_BONUS = 1000;
  const STILL_SECS = 5;
  const SAVE_KEYS = ['v', 'fear', 'over', 'giftsTonight', 'gifts', 'essenceBonus', 'nextBlood'];

  function getData() {
    let d = root.VCS && root.VCS.HungerData;
    if (!d && typeof require === 'function') {
      try { d = require('./data/hunger.js'); } catch (e) { d = null; }
    }
    return d;
  }
  function logger() {
    try { return root.VCS && root.VCS.Log ? root.VCS.Log.get('hunger') : null; } catch (e) { return null; }
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
  function clamp(x, lo, hi) { return x < lo ? lo : x > hi ? hi : x; }

  function mulberry32(a) {
    let s = a >>> 0;
    return function () {
      s = (s + 0x6D2B79F5) >>> 0;
      let t = s;
      t = Math.imul(t ^ (t >>> 15), t | 1);
      t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
      return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
  }

  function powerList() { const d = getData(); return d ? d.powers : []; }
  function giftList() { const d = getData(); return d ? d.gifts : []; }
  function powerById(id) {
    const l = powerList();
    for (let i = 0; i < l.length; i++) if (l[i].id === id) return l[i];
    return null;
  }
  function giftById(id) {
    const l = giftList();
    for (let i = 0; i < l.length; i++) if (l[i].id === id) return l[i];
    return null;
  }
  function fearMax() { const d = getData(); return d ? d.FEAR_MAX : 15; }

  function create() {
    return {
      v: SCHEMA, fear: 0, over: 0, giftsTonight: 0, gifts: [], essenceBonus: 0, nextBlood: 0,
      grabbed: [], cd: { shriek: 0, mist: 0, still: 0 }, stillLeft: 0
    };
  }

  function okState(st) { return !!st && typeof st === 'object' && Array.isArray(st.gifts); }

  // ---- overflow ----
  function cost(st) {
    try {
      const d = getData();
      if (!d || !okState(st)) return null;
      const n = Math.floor(st.giftsTonight);
      if (!isNum(n) || n < 0) return null;
      if (n >= d.GIFTS_PER_NIGHT || n >= d.GIFT_COSTS.length) return null;
      return d.GIFT_COSTS[n];
    } catch (e) { return null; }
  }
  function isOpen(st) { return cost(st) !== null; }
  function over01(st) {
    try {
      const c = cost(st);
      if (c === null || !isNum(st.over)) return 0;
      return clamp(st.over / c, 0, 1);
    } catch (e) { return 0; }
  }
  function addOverflow(st, amt) {
    try {
      const c = cost(st);
      if (c === null) return { taken: 0, ready: false };
      if (!isNum(st.over) || st.over < 0) st.over = 0;
      const room = Math.max(0, c - st.over);
      const taken = isNum(amt) && amt > 0 ? Math.min(amt, room) : 0;
      st.over = Math.min(c, st.over + taken);
      return { taken: taken, ready: st.over >= c };
    } catch (e) {
      warn('addOverflow failed', { err: String(e && e.message) });
      return { taken: 0, ready: false };
    }
  }

  // ---- gifts ----
  function rollGifts(st, seed) {
    try {
      const ids = giftList().map(function (g) { return g.id; });
      const n = okState(st) ? st.gifts.length : 0;
      const sd = isNum(seed) ? Math.floor(seed) : 0;
      const rnd = mulberry32((sd * 2654435761 + n * 40503 + 12345) >>> 0);
      const count = Math.min(3, ids.length);
      for (let i = 0; i < count; i++) {
        const j = i + Math.floor(rnd() * (ids.length - i));
        const t = ids[i]; ids[i] = ids[j]; ids[j] = t;
      }
      return ids.slice(0, count);
    } catch (e) { return []; }
  }
  function takeGift(st, id) {
    try {
      const d = getData();
      const g = typeof id === 'string' ? giftById(id) : null;
      if (!d || !g || !okState(st)) return { ok: false, instant: {} };
      if (st.gifts.length < MAX_GIFTS) st.gifts.push(g.id);
      st.giftsTonight = Math.max(0, Math.floor(isNum(st.giftsTonight) ? st.giftsTonight : 0)) + 1;
      st.over = 0;
      st.essenceBonus = Math.min(MAX_ESSENCE_BONUS, (isNum(st.essenceBonus) ? st.essenceBonus : 0) + d.GIFT_ESSENCE);
      const instant = {};
      if (g.kind === 'fear') {
        addFear(st, g.value);
        instant.fear = g.value;
      } else if (g.kind === 'nextBlood') {
        st.nextBlood = Math.min(MAX_NEXT_BLOOD, (isNum(st.nextBlood) ? st.nextBlood : 0) + g.value);
        instant.nextBlood = g.value;
      }
      return { ok: true, instant: instant };
    } catch (e) {
      warn('takeGift failed', { err: String(e && e.message) });
      return { ok: false, instant: {} };
    }
  }
  function giftMods(st) {
    try {
      if (!okState(st)) return [];
      const out = [];
      st.gifts.forEach(function (id) {
        const g = giftById(id);
        if (g && g.kind === 'effect') out.push({ effect: g.effect, op: g.op, value: g.value });
      });
      return out;
    } catch (e) { return []; }
  }

  // ---- fear ----
  function addFear(st, n) {
    try {
      if (!st || typeof st !== 'object' || !isNum(n)) return 0;
      const cur = isNum(st.fear) ? st.fear : 0;
      st.fear = clamp(Math.round(cur + n), 0, fearMax());
      return st.fear;
    } catch (e) { return 0; }
  }
  function onGrab(st, personId) {
    try {
      const d = getData();
      if (!d || !okState(st) || personId === undefined || personId === null) return false;
      if (!Array.isArray(st.grabbed)) st.grabbed = [];
      if (st.grabbed.indexOf(personId) >= 0) return false;
      if (st.grabbed.length < MAX_GRABBED) st.grabbed.push(personId);
      addFear(st, d.FEAR.grab);
      return true;
    } catch (e) { return false; }
  }
  function fearMods(st) {
    try {
      const d = getData();
      const f = st && isNum(st.fear) ? clamp(st.fear, 0, fearMax()) : 0;
      if (!d) return { startleMul: 1, fleeMul: 1, calmMul: 1 };
      return {
        startleMul: 1 + Math.min(d.FEAR_STARTLE[1], d.FEAR_STARTLE[0] * f),
        fleeMul: 1 + Math.min(d.FEAR_FLEE[1], d.FEAR_FLEE[0] * f),
        calmMul: 1 + Math.min(d.FEAR_CALM ? d.FEAR_CALM[1] : 0.6, (d.FEAR_CALM ? d.FEAR_CALM[0] : 0.04) * f)
      };
    } catch (e) { return { startleMul: 1, fleeMul: 1, calmMul: 1 }; }
  }

  // ---- powers ----
  function cdOf(st, id) {
    return st && st.cd && isNum(st.cd[id]) && st.cd[id] > 0 ? st.cd[id] : 0;
  }
  function powerState(st, id, night, blood) {
    try {
      const p = powerById(id);
      if (!p || !isNum(night) || night < p.unlock) return 'locked';
      if (cdOf(st, id) > 0) return 'cooldown';
      if (!isNum(blood) || blood < p.cost) return 'poor';
      return 'ready';
    } catch (e) { return 'locked'; }
  }
  function cdLeft01(st, id) {
    try {
      const p = powerById(id);
      if (!p) return 0;
      return clamp(cdOf(st, id) / p.cooldown, 0, 1);
    } catch (e) { return 0; }
  }
  function use(st, id, night, blood) {
    try {
      const p = powerById(id);
      if (!p || !okState(st)) return { ok: false, code: 'E_UNKNOWN', cost: null };
      const s = powerState(st, id, night, blood);
      if (s === 'locked') return { ok: false, code: 'E_LOCKED', cost: p.cost };
      if (s === 'cooldown') return { ok: false, code: 'E_COOLDOWN', cost: p.cost };
      if (s === 'poor') return { ok: false, code: 'E_POOR', cost: p.cost };
      if (!st.cd || typeof st.cd !== 'object') st.cd = { shriek: 0, mist: 0, still: 0 };
      st.cd[id] = p.cooldown;
      addFear(st, p.fear);
      if (id === 'still') st.stillLeft = STILL_SECS;
      return { ok: true, code: null, cost: p.cost };
    } catch (e) {
      warn('use failed', { err: String(e && e.message) });
      return { ok: false, code: 'E_UNKNOWN', cost: null };
    }
  }
  function tick(st, dt) {
    try {
      if (!st || typeof st !== 'object' || !isNum(dt)) return;
      const d = clamp(dt, 0, 0.1);
      if (st.cd && typeof st.cd === 'object') {
        Object.keys(st.cd).forEach(function (k) {
          st.cd[k] = isNum(st.cd[k]) ? Math.max(0, st.cd[k] - d) : 0;
        });
      }
      st.stillLeft = isNum(st.stillLeft) ? Math.max(0, st.stillLeft - d) : 0;
    } catch (e) { /* ignore */ }
  }
  function isStill(st) { return !!st && isNum(st.stillLeft) && st.stillLeft > 0; }

  // ---- sleep / persistence ----
  function onSleep(st) {
    try {
      if (!st || typeof st !== 'object') return 0;
      const d = getData();
      addFear(st, d ? d.FEAR.sleep : -3);
      st.over = 0;
      st.giftsTonight = 0;
      st.grabbed = [];
      const nb = isNum(st.nextBlood) && st.nextBlood > 0 ? st.nextBlood : 0;
      st.nextBlood = 0;
      return nb;
    } catch (e) { return 0; }
  }
  function serialize(st) {
    try {
      if (!okState(st)) return null;
      return {
        v: SCHEMA, fear: st.fear, over: st.over, giftsTonight: st.giftsTonight,
        gifts: st.gifts.slice(), essenceBonus: st.essenceBonus, nextBlood: st.nextBlood
      };
    } catch (e) { return null; }
  }
  function restore(obj) {
    try {
      if (!isPlain(obj)) return null;
      const keys = Object.keys(obj);
      if (keys.length !== SAVE_KEYS.length) return null;
      for (let i = 0; i < SAVE_KEYS.length; i++) if (!hasOwn(obj, SAVE_KEYS[i])) return null;
      if (obj.v !== SCHEMA) return null;
      const d = getData();
      if (!d) return null;
      const nums = ['fear', 'over', 'giftsTonight', 'essenceBonus', 'nextBlood'];
      for (let i = 0; i < nums.length; i++) {
        if (!isNum(obj[nums[i]]) || obj[nums[i]] < 0) return null;
      }
      if (obj.fear > d.FEAR_MAX || obj.fear !== Math.floor(obj.fear)) return null;
      if (obj.giftsTonight > d.GIFTS_PER_NIGHT || obj.giftsTonight !== Math.floor(obj.giftsTonight)) return null;
      if (obj.essenceBonus > MAX_ESSENCE_BONUS || obj.nextBlood > MAX_NEXT_BLOOD) return null;
      if (!Array.isArray(obj.gifts) || obj.gifts.length > MAX_GIFTS) return null;
      for (let i = 0; i < obj.gifts.length; i++) {
        if (typeof obj.gifts[i] !== 'string' || !giftById(obj.gifts[i])) return null;
      }
      const st = create();
      st.fear = obj.fear;
      st.giftsTonight = obj.giftsTonight;
      st.gifts = obj.gifts.slice();
      st.essenceBonus = obj.essenceBonus;
      st.nextBlood = obj.nextBlood;
      const c = cost(st);
      st.over = c === null ? 0 : Math.min(obj.over, c);
      return st;
    } catch (e) {
      warn('restore failed', { err: String(e && e.message) });
      return null;
    }
  }

  const Hunger = {
    SCHEMA: SCHEMA, STILL_SECS: STILL_SECS,
    create: create, addOverflow: addOverflow, isOpen: isOpen, cost: cost, over01: over01,
    rollGifts: rollGifts, takeGift: takeGift, giftMods: giftMods,
    onGrab: onGrab, addFear: addFear, fearMods: fearMods,
    powerState: powerState, cdLeft01: cdLeft01, use: use, tick: tick, isStill: isStill,
    onSleep: onSleep, serialize: serialize, restore: restore
  };
  VCS.Hunger = Hunger;
  if (typeof module !== 'undefined' && module.exports) module.exports = Hunger;
})(typeof window !== 'undefined' ? window : globalThis);
