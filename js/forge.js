(function (root) {
  'use strict';
  const VCS = (root.VCS = root.VCS || {});

  // NPC Forge: turns data archetypes plus a seed into a villager spec (look, voice, schedule role, flags).
  // Seed-deterministic, no DOM, public functions never throw. Legacy archetypes reproduce the v0.13 makeLook exactly.

  const LIBRARY_KEY = 'vcs.forge';
  const LIBRARY_MAX_BYTES = 16384;
  const MAX_CUSTOM = 16;
  const BAD_KEYS = ['__proto__', 'constructor', 'prototype'];
  const ID_RE = /^[a-z][a-z0-9_]{1,23}$/;

  function logger() {
    try {
      const l = root.VCS && root.VCS.Log ? root.VCS.Log.get('forge') : null;
      if (l) return l;
    } catch (e) { /* ignore */ }
    return { debug: function () {}, info: function () {}, warn: function () {}, error: function () {} };
  }
  function warn(msg) {
    try { const l = logger(); if (l && l.warn) l.warn(msg); } catch (e) { /* ignore */ }
  }

  function mod(name, file) {
    try {
      if (root.VCS && root.VCS[name]) return root.VCS[name];
      if (typeof require === 'function' && typeof module !== 'undefined') return require(file);
    } catch (e) { /* ignore */ }
    return null;
  }
  function AD() { return mod('ArchetypeData', './data/archetypes.js'); }
  function VD() { return mod('VoiceData', './data/voices.js'); }

  function deepFreeze(o) {
    if (o && typeof o === 'object' && !Object.isFrozen(o)) {
      Object.freeze(o);
      Object.keys(o).forEach(function (k) { deepFreeze(o[k]); });
    }
    return o;
  }

  /** Bit-identical copy of the people.js PRNG. */
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

  // Local copies of the legacy tables (the legacy look must not depend on data loading).
  const ACCESSORIES = ['tophat', 'nightcap', 'bonnet', 'cane', 'scarf', 'lantern', 'hood', 'umbrella', 'cap', 'basket'];
  const HATS = ['tophat', 'nightcap', 'bonnet', 'cap', 'hood'];
  const PROPS = ['cane', 'lantern', 'umbrella', 'basket'];
  const BODIES = ['bean', 'pear', 'stick', 'round', 'box'];
  const HEADS = ['round', 'egg', 'square', 'long'];
  const HAIRS = ['none', 'tuft', 'bun', 'spiky', 'curls', 'bob'];

  const FALLBACK_KEYS = ['height', 'build', 'stride', 'acc', 'body', 'head', 'hat', 'hair', 'beard', 'nose', 'coat', 'prop',
    'v', 'archetype', 'outfit', 'roleHat', 'extra', 'stoop', 'shoulder', 'hem', 'skin'];
  const FALLBACK_ENUMS = {
    acc: ['none'].concat(ACCESSORIES),
    body: BODIES,
    head: HEADS,
    hat: ['none'].concat(HATS),
    hair: HAIRS,
    prop: ['none'].concat(PROPS),
    outfit: ['plain', 'mail', 'robe', 'apron', 'smock', 'cloak'],
    roleHat: ['none', 'kettle', 'biretta'],
    extra: ['none', 'shovel', 'bundle', 'ledger', 'bow']
  };
  const FALLBACK_RANGES = {
    height: [0.5, 1.2], build: [0.7, 1.4], stride: [0.7, 1.4], nose: [0.5, 1.6],
    stoop: [0, 0.4], shoulder: [0.8, 1.25], hem: [0, 1], skin: [0, 1]
  };
  const FALLBACK_RECIPE = {
    height: [0.9, 0.15], build: [0.9, 0.25], stride: [0.9, 0.25], bodies: BODIES, heads: HEADS, hairs: HAIRS,
    beardP: 0.3, nose: [0.7, 0.7], coatP: 0.45, acc: 'cycle'
  };
  const DEFAULTS = {
    height: 1, build: 1, stride: 1, acc: 'none', body: 'bean', head: 'round', hat: 'none', hair: 'none', beard: false,
    nose: 1, coat: false, prop: 'none', v: 1, archetype: 'patron', outfit: 'plain', roleHat: 'none', extra: 'none',
    stoop: 0, shoulder: 1, hem: 0, skin: 0.5
  };
  const NUM_KEYS = ['height', 'build', 'stride', 'nose', 'stoop', 'shoulder', 'hem', 'skin'];
  const BOOL_KEYS = ['beard', 'coat'];
  const ENUM_KEYS = ['acc', 'body', 'head', 'hat', 'hair', 'prop', 'outfit', 'roleHat', 'extra'];

  function lookKeys() { const a = AD(); return a && a.LOOK_KEYS ? a.LOOK_KEYS : FALLBACK_KEYS; }
  function enums() { const a = AD(); return a && a.LOOK_ENUMS ? a.LOOK_ENUMS : FALLBACK_ENUMS; }
  function ranges() { const a = AD(); return a && a.LOOK_RANGES ? a.LOOK_RANGES : FALLBACK_RANGES; }
  function legacyRecipe() { const a = AD(); return a && a.LEGACY_RECIPE ? a.LEGACY_RECIPE : FALLBACK_RECIPE; }

  const hasOwn = Object.prototype.hasOwnProperty;
  function isPlain(o) { return !!o && typeof o === 'object' && !Array.isArray(o); }
  function isBadKey(k) { return BAD_KEYS.indexOf(k) >= 0; }
  function isNum(n) { return typeof n === 'number' && isFinite(n); }
  function clamp(n, lo, hi) { return n < lo ? lo : n > hi ? hi : n; }
  function inList(list, v) { return Array.isArray(list) && list.indexOf(v) >= 0; }
  function ownKeys(o) { try { return Object.keys(o); } catch (e) { return []; } }
  function safeRead(o, k) { try { return hasOwn.call(o, k) ? o[k] : undefined; } catch (e) { return undefined; } }

  function sanNum(n) { return isNum(n) ? n : 0; }

  /** Same seed derivation as the legacy makeLook, with pid := entrySeed. */
  function lookSeed(stateSeed, entrySeed) {
    try {
      const sd = isNum(stateSeed) ? stateSeed : 0;
      const pid = isNum(entrySeed) ? Math.floor(entrySeed) : 0;
      return ((sd >>> 0) * 2654435761 + (pid + 1) * 40503 + 977) >>> 0;
    } catch (e) {
      return 0;
    }
  }

  /** Verbatim body of the v0.13 People.makeLook. */
  function legacyLook(seed, id, accOffset) {
    const sd = typeof seed === 'number' && isFinite(seed) ? seed : 0;
    const pid = typeof id === 'number' && isFinite(id) ? Math.floor(id) : 0;
    const off = typeof accOffset === 'number' && isFinite(accOffset) ? Math.floor(accOffset) : 0;
    const rng = mulberry32(((sd >>> 0) * 2654435761 + (pid + 1) * 40503 + 977) >>> 0);
    const height = 0.9 + rng() * 0.15;
    const build = 0.9 + rng() * 0.25;
    const stride = 0.9 + rng() * 0.25;
    const n = ACCESSORIES.length;
    const acc = ACCESSORIES[(((off + 3 * pid) % n) + n) % n]; // 3 is coprime with the list length: all items cycle
    const body = BODIES[Math.floor(rng() * BODIES.length)];
    const head = HEADS[Math.floor(rng() * HEADS.length)];
    const hat = HATS.indexOf(acc) >= 0 ? acc : 'none';
    // Hair shows when there is no hat (a nightcap or hood hides it; a cap or bonnet lets a little out).
    let hair = HAIRS[Math.floor(rng() * HAIRS.length)];
    if (hat === 'nightcap' || hat === 'hood' || hat === 'tophat') hair = 'none';
    const beard = rng() < 0.3;
    const nose = 0.7 + rng() * 0.7;
    const coat = rng() < 0.45;
    const prop = PROPS.indexOf(acc) >= 0 ? acc : 'none';
    return { height: height, build: build, stride: stride, acc: acc, body: body, head: head, hat: hat, hair: hair, beard: beard, nose: nose, coat: coat, prop: prop };
  }

  // ---------------------------------------------------------------- validation

  function pick(list, r) { return list[Math.floor(r * list.length)]; }

  function validateLook(obj, partial) {
    const errors = [];
    if (!isPlain(obj)) return { ok: false, code: 'E_FORGE_TYPE', value: partial ? {} : Object.assign({}, DEFAULTS), errors: ['look must be an object'] };
    const E = enums();
    const R = ranges();
    const keys = lookKeys();
    const ks = ownKeys(obj);
    let bad = false;
    for (let i = 0; i < ks.length; i++) {
      if (isBadKey(ks[i]) || keys.indexOf(ks[i]) < 0) {
        bad = true;
        errors.push('bad key: ' + String(ks[i]).slice(0, 32));
      }
    }
    if (bad) return { ok: false, code: 'E_FORGE_BAD_KEY', value: partial ? {} : Object.assign({}, DEFAULTS), errors: errors };
    const out = {};
    for (let i = 0; i < keys.length; i++) {
      const k = keys[i];
      const has = ks.indexOf(k) >= 0;
      if (!has && partial) continue;
      const raw = has ? safeRead(obj, k) : undefined;
      const def = DEFAULTS[k];
      if (k === 'v') {
        out.v = 1;
      } else if (k === 'archetype') {
        if (typeof raw === 'string' && ID_RE.test(raw)) out[k] = raw;
        else { if (has) errors.push('archetype'); if (!partial) out[k] = def; }
      } else if (NUM_KEYS.indexOf(k) >= 0) {
        const r = R[k] || [0, 1];
        if (isNum(raw)) out[k] = clamp(raw, r[0], r[1]);
        else { if (has) errors.push(k); if (!partial) out[k] = def; }
      } else if (BOOL_KEYS.indexOf(k) >= 0) {
        if (typeof raw === 'boolean') out[k] = raw;
        else { if (has) errors.push(k); if (!partial) out[k] = def; }
      } else if (ENUM_KEYS.indexOf(k) >= 0) {
        if (typeof raw === 'string' && inList(E[k], raw)) out[k] = raw;
        else { if (has) errors.push(k); if (!partial) out[k] = def; }
      } else if (!partial) {
        out[k] = def;
      }
    }
    if (!partial) applyRules(out, null);
    return { ok: true, code: 'OK', value: out, errors: errors };
  }

  /** hat/prop follow acc; hair is hidden under tophat, nightcap and hood. patchKeys null = derive everything. */
  function applyRules(look, patch) {
    const has = function (k) { return patch === null || (hasOwn.call(patch, 'acc') && !hasOwn.call(patch, k)); };
    if (has('hat')) look.hat = HATS.indexOf(look.acc) >= 0 ? look.acc : 'none';
    if (has('prop')) look.prop = PROPS.indexOf(look.acc) >= 0 ? look.acc : 'none';
    if (look.hat === 'nightcap' || look.hat === 'hood' || look.hat === 'tophat') look.hair = 'none';
    return look;
  }

  function validateRecipe(r) {
    const base = legacyRecipe();
    if (!isPlain(r)) return null;
    const out = {};
    const pair = function (k, lo, hi, span) {
      const v = safeRead(r, k);
      if (v === undefined) { out[k] = base[k].slice(); return true; }
      if (!Array.isArray(v) || v.length !== 2 || !isNum(v[0]) || !isNum(v[1])) return false;
      out[k] = [clamp(v[0], lo, hi), clamp(v[1], 0, span)];
      return true;
    };
    if (!pair('height', 0.5, 1.2, 0.7) || !pair('build', 0.7, 1.4, 0.7) || !pair('stride', 0.7, 1.4, 0.7) || !pair('nose', 0.5, 1.6, 1.1)) return null;
    const E = enums();
    const lst = function (k, allowed) {
      const v = safeRead(r, k);
      if (v === undefined) { out[k] = base[k].slice(); return true; }
      if (!Array.isArray(v) || v.length < 1 || v.length > 16) return false;
      for (let i = 0; i < v.length; i++) if (!inList(allowed, v[i])) return false;
      out[k] = v.slice();
      return true;
    };
    if (!lst('bodies', E.body) || !lst('heads', E.head) || !lst('hairs', E.hair)) return null;
    const prob = function (k) {
      const v = safeRead(r, k);
      out[k] = isNum(v) ? clamp(v, 0, 1) : base[k];
    };
    prob('beardP');
    prob('coatP');
    const acc = safeRead(r, 'acc');
    if (acc === undefined || acc === 'cycle') out.acc = 'cycle';
    else if (typeof acc === 'string' && inList(E.acc, acc)) out.acc = acc;
    else return null;
    return out;
  }

  function validateExtras(x) {
    const E = enums();
    const R = ranges();
    const out = {};
    const src = isPlain(x) ? x : {};
    const enumKey = function (k) {
      const v = safeRead(src, k);
      out[k] = typeof v === 'string' && inList(E[k], v) ? v : DEFAULTS[k];
    };
    enumKey('outfit');
    enumKey('roleHat');
    enumKey('extra');
    const numKey = function (k) {
      const v = safeRead(src, k);
      const r = R[k] || [0, 1];
      if (isNum(v)) out[k] = clamp(v, r[0], r[1]);
      else if (Array.isArray(v) && v.length === 2 && isNum(v[0]) && isNum(v[1])) out[k] = [clamp(v[0], r[0], r[1]), clamp(v[1], 0, r[1] - r[0])];
      else out[k] = DEFAULTS[k];
    };
    numKey('stoop');
    numKey('shoulder');
    numKey('hem');
    numKey('skin');
    return out;
  }

  function validateSchedule(s) {
    if (s === null || s === undefined) return { ok: true, value: null };
    if (s === 'watch') return { ok: true, value: 'watch' };
    if (!Array.isArray(s) || s.length < 1 || s.length > 12) return { ok: false };
    const out = [];
    for (let i = 0; i < s.length; i++) {
      const t = s[i];
      if (!Array.isArray(t) || t.length !== 3 || !Array.isArray(t[0]) || t[0].length < 1 || t[0].length > 8) return { ok: false };
      if (!isNum(t[1]) || typeof t[2] !== 'string' || t[2].length > 16) return { ok: false };
      const places = [];
      for (let j = 0; j < t[0].length; j++) {
        if (typeof t[0][j] !== 'string' || t[0][j].length > 24) return { ok: false };
        places.push(t[0][j]);
      }
      out.push([places, clamp(t[1], 0, 1), t[2]]);
    }
    return { ok: true, value: out };
  }

  const ARCH_KEYS = ['id', 'role', 'label', 'legacy', 'voice', 'talk', 'schedule', 'watch', 'feedable', 'gait', 'speed', 'recipe', 'extras'];

  function validateArchetype(a) {
    const errors = [];
    if (!isPlain(a)) return { ok: false, code: 'E_FORGE_TYPE', value: null, errors: ['archetype must be an object'] };
    const ks = ownKeys(a);
    for (let i = 0; i < ks.length; i++) {
      if (isBadKey(ks[i]) || ARCH_KEYS.indexOf(ks[i]) < 0) errors.push('bad key: ' + String(ks[i]).slice(0, 32));
    }
    if (errors.length) return { ok: false, code: 'E_FORGE_BAD_KEY', value: null, errors: errors };
    const id = safeRead(a, 'id');
    if (typeof id !== 'string' || !ID_RE.test(id)) return { ok: false, code: 'E_FORGE_TYPE', value: null, errors: ['bad id'] };
    const role = safeRead(a, 'role');
    if (role !== undefined && (typeof role !== 'string' || role.length > 24)) return { ok: false, code: 'E_FORGE_TYPE', value: null, errors: ['bad role'] };
    const vd = VD();
    const voice = safeRead(a, 'voice');
    if (typeof voice !== 'string' || voice.length > 24 || (vd && vd.PRESETS && !hasOwn.call(vd.PRESETS, voice))) {
      return { ok: false, code: 'E_FORGE_TYPE', value: null, errors: ['bad voice'] };
    }
    const talk = safeRead(a, 'talk');
    if (typeof talk !== 'string' || talk.length > 24) return { ok: false, code: 'E_FORGE_TYPE', value: null, errors: ['bad talk'] };
    const sch = validateSchedule(safeRead(a, 'schedule'));
    if (!sch.ok) return { ok: false, code: 'E_FORGE_TYPE', value: null, errors: ['bad schedule'] };
    const gait = safeRead(a, 'gait');
    const recipeIn = safeRead(a, 'recipe');
    const recipe = recipeIn === undefined ? legacyRecipe() : validateRecipe(recipeIn);
    if (!recipe) return { ok: false, code: 'E_FORGE_TYPE', value: null, errors: ['bad recipe'] };
    const speed = safeRead(a, 'speed');
    const label = safeRead(a, 'label');
    const value = {
      id: id,
      role: role || '',
      label: typeof label === 'string' ? label.slice(0, 32) : id,
      legacy: false,
      voice: voice,
      talk: talk,
      schedule: sch.value,
      watch: safeRead(a, 'watch') === true,
      feedable: safeRead(a, 'feedable') !== false,
      gait: gait === 'mail' ? 'mail' : 'walk',
      speed: isNum(speed) ? clamp(speed, 0.5, 2) : 1,
      recipe: recipeIn === undefined ? JSON.parse(JSON.stringify(recipe)) : recipe,
      extras: validateExtras(safeRead(a, 'extras'))
    };
    return { ok: true, code: 'OK', value: value, errors: errors };
  }

  function validateSpec(s) {
    if (!isPlain(s)) return { ok: false, code: 'E_FORGE_TYPE', value: null, errors: ['spec must be an object'] };
    const ks = ownKeys(s);
    for (let i = 0; i < ks.length; i++) {
      if (isBadKey(ks[i]) || ['archetype', 'seed', 'home', 'overrides'].indexOf(ks[i]) < 0) {
        return { ok: false, code: 'E_FORGE_BAD_KEY', value: null, errors: ['bad key: ' + String(ks[i]).slice(0, 32)] };
      }
    }
    const arch = safeRead(s, 'archetype');
    if (typeof arch !== 'string' || !ID_RE.test(arch)) return { ok: false, code: 'E_FORGE_TYPE', value: null, errors: ['bad archetype'] };
    const value = { archetype: arch };
    const seed = safeRead(s, 'seed');
    if (isNum(seed)) value.seed = Math.floor(clamp(seed, 0, 4294967295));
    const home = safeRead(s, 'home');
    if (home !== undefined && home !== null) {
      if (typeof home !== 'string' && !isNum(home)) return { ok: false, code: 'E_FORGE_TYPE', value: null, errors: ['bad home'] };
      value.home = typeof home === 'string' ? home.slice(0, 24) : home;
    }
    const ov = safeRead(s, 'overrides');
    if (ov !== undefined) {
      const r = validateLook(ov, true);
      if (!r.ok) return { ok: false, code: r.code, value: null, errors: r.errors };
      value.overrides = r.value;
    }
    return { ok: true, code: 'OK', value: value, errors: [] };
  }

  function validateLibrary(lib) {
    if (!isPlain(lib)) return { ok: false, code: 'E_FORGE_TYPE', value: null, errors: ['library must be an object'] };
    const ks = ownKeys(lib);
    for (let i = 0; i < ks.length; i++) {
      if (isBadKey(ks[i]) || (ks[i] !== 'v' && ks[i] !== 'list')) return { ok: false, code: 'E_FORGE_BAD_KEY', value: null, errors: ['bad key: ' + String(ks[i]).slice(0, 32)] };
    }
    if (safeRead(lib, 'v') !== 1) return { ok: false, code: 'E_FORGE_TYPE', value: null, errors: ['bad version'] };
    const list = safeRead(lib, 'list');
    if (!Array.isArray(list)) return { ok: false, code: 'E_FORGE_TYPE', value: null, errors: ['list must be an array'] };
    if (list.length > MAX_CUSTOM) return { ok: false, code: 'E_FORGE_LIMIT', value: null, errors: ['too many archetypes'] };
    const out = [];
    for (let i = 0; i < list.length; i++) {
      const r = validateArchetype(list[i]);
      if (!r.ok) return { ok: false, code: r.code, value: null, errors: r.errors };
      out.push(r.value);
    }
    return { ok: true, code: 'OK', value: { v: 1, list: out }, errors: [] };
  }

  function validate(kind, obj, opts) {
    try {
      const partial = !!(opts && opts.partial === true);
      if (kind === 'look') return validateLook(obj, partial);
      if (kind === 'archetype') return validateArchetype(obj);
      if (kind === 'spec') return validateSpec(obj);
      if (kind === 'library') return validateLibrary(obj);
      return { ok: false, code: 'E_FORGE_UNKNOWN', value: null, errors: ['unknown kind'] };
    } catch (e) {
      warn('validate failed: ' + (e && e.message));
      return { ok: false, code: 'E_FORGE_TYPE', value: null, errors: ['exception'] };
    }
  }

  // ---------------------------------------------------------------- archetypes (built-in + custom overlay)

  const custom = Object.create(null);
  let customCount = 0;

  function archetype(id) {
    try {
      if (typeof id !== 'string' || isBadKey(id)) return null;
      const a = AD();
      const b = a && typeof a.byId === 'function' ? a.byId(id) : null;
      if (b) return b;
      return custom[id] || null;
    } catch (e) {
      return null;
    }
  }

  function list() {
    try {
      const a = AD();
      const out = [];
      if (a && Array.isArray(a.list)) a.list.forEach(function (x) { out.push(x.id); });
      Object.keys(custom).forEach(function (k) { out.push(k); });
      return out;
    } catch (e) {
      return [];
    }
  }

  function byRole(role) {
    try {
      if (typeof role !== 'string' || isBadKey(role)) return null;
      const a = AD();
      const b = a && typeof a.byRole === 'function' ? a.byRole(role) : null;
      if (b) return b;
      const ks = Object.keys(custom);
      for (let i = 0; i < ks.length; i++) if (custom[ks[i]].role === role && role !== '') return custom[ks[i]];
      return null;
    } catch (e) {
      return null;
    }
  }

  function isBuiltIn(id) {
    const a = AD();
    return !!(a && typeof a.byId === 'function' && a.byId(id));
  }

  function register(arch) {
    try {
      const r = validateArchetype(arch);
      if (!r.ok) return { ok: false, code: r.code };
      const id = r.value.id;
      if (isBuiltIn(id)) return { ok: false, code: 'E_FORGE_BAD_KEY' };
      if (!custom[id] && customCount >= MAX_CUSTOM) return { ok: false, code: 'E_FORGE_LIMIT' };
      if (!custom[id]) customCount++;
      custom[id] = deepFreeze(r.value);
      return { ok: true, code: 'OK' };
    } catch (e) {
      warn('register failed: ' + (e && e.message));
      return { ok: false, code: 'E_FORGE_TYPE' };
    }
  }

  // ---------------------------------------------------------------- generate / alter

  function generate(spec, ctx) {
    try {
      const sp = isPlain(spec) ? spec : {};
      const cx = isPlain(ctx) ? ctx : {};
      const id = typeof sp.archetype === 'string' ? sp.archetype : 'patron';
      let arch = archetype(id);
      let ok = true;
      let code = 'OK';
      if (!arch) {
        ok = false;
        code = 'E_FORGE_UNKNOWN';
        arch = archetype('patron');
      }
      if (!arch) return { ok: false, code: 'E_FORGE_UNKNOWN', person: null };
      const person = build(arch, sp, cx);
      return { ok: ok, code: code, person: person };
    } catch (e) {
      warn('generate failed: ' + (e && e.message));
      return { ok: false, code: 'E_FORGE_TYPE', person: null };
    }
  }

  function build(arch, sp, cx) {
    const rawSeed = safeRead(sp, 'seed');
    const index = isNum(safeRead(cx, 'index')) ? Math.floor(cx.index) : 0;
    const entrySeed = isNum(rawSeed) && Math.floor(rawSeed) === rawSeed && rawSeed >= 0 && rawSeed <= 65535 ? rawSeed : index;
    const stateSeed = sanNum(safeRead(cx, 'stateSeed'));
    const accOffset = isNum(safeRead(cx, 'accOffset')) ? Math.floor(cx.accOffset) : 0;
    const ls = lookSeed(stateSeed, entrySeed);
    const rng = mulberry32(ls);
    const rc = arch.recipe || legacyRecipe();
    const E = enums();
    const height = rc.height[0] + rng() * rc.height[1];
    const bld = rc.build[0] + rng() * rc.build[1];
    const stride = rc.stride[0] + rng() * rc.stride[1];
    let acc;
    if (rc.acc === 'cycle' || rc.acc === undefined) {
      const n = ACCESSORIES.length;
      acc = ACCESSORIES[((((accOffset + 3 * entrySeed) % n) + n) % n)];
    } else {
      acc = rc.acc;
    }
    const body = pick(rc.bodies, rng());
    const head = pick(rc.heads, rng());
    const hat = HATS.indexOf(acc) >= 0 ? acc : 'none';
    let hair = pick(rc.hairs, rng());
    if (hat === 'nightcap' || hat === 'hood' || hat === 'tophat') hair = 'none';
    const beard = rng() < rc.beardP;
    const nose = rc.nose[0] + rng() * rc.nose[1];
    const coat = rng() < rc.coatP;
    const prop = PROPS.indexOf(acc) >= 0 ? acc : 'none';
    const look = { height: height, build: bld, stride: stride, acc: acc, body: body, head: head, hat: hat, hair: hair, beard: beard, nose: nose, coat: coat, prop: prop };

    const ex = arch.extras || {};
    const er = mulberry32((ls ^ 0x9E3779B9) >>> 0);
    const drawn = function (k) {
      const v = ex[k];
      if (Array.isArray(v)) return v[0] + er() * v[1];
      return isNum(v) ? v : DEFAULTS[k];
    };
    const shoulder = drawn('shoulder');
    const skin = drawn('skin');
    const stoop = drawn('stoop');
    const hem = drawn('hem');
    look.v = 1;
    look.archetype = arch.id;
    look.outfit = inList(E.outfit, ex.outfit) ? ex.outfit : 'plain';
    look.roleHat = inList(E.roleHat, ex.roleHat) ? ex.roleHat : 'none';
    look.extra = inList(E.extra, ex.extra) ? ex.extra : 'none';
    look.stoop = clamp(stoop, 0, 0.4);
    look.shoulder = clamp(shoulder, 0.8, 1.25);
    look.hem = clamp(hem, 0, 1);
    look.skin = clamp(skin, 0, 1);

    const ov = safeRead(sp, 'overrides');
    if (isPlain(ov)) {
      const r = validateLook(ov, true);
      if (r.ok) {
        Object.assign(look, r.value);
        applyRules(look, r.value);
      }
    }
    look.archetype = arch.id;
    look.v = 1;
    const home = safeRead(sp, 'home');
    return {
      archetype: arch.id,
      role: arch.role || '',
      look: look,
      voice: arch.voice,
      talk: arch.talk,
      schedRole: arch.schedule && arch.role ? arch.role : null,
      home: home === undefined ? null : home,
      watch: !!arch.watch,
      feedable: arch.feedable !== false,
      gait: arch.gait || 'walk'
    };
  }

  function alter(look, patch) {
    try {
      const base = validateLook(look, false);
      if (!isPlain(look)) return { ok: false, code: 'E_FORGE_TYPE', look: base.value, changed: [] };
      // Start from the caller's look so unknown-but-valid state survives; invalid input falls back to clamped values.
      const src = {};
      const keys = lookKeys();
      for (let i = 0; i < keys.length; i++) {
        const v = safeRead(look, keys[i]);
        if (v !== undefined) src[keys[i]] = v;
      }
      const cur = validateLook(src, true).value;
      const start = Object.assign({}, base.value, cur);
      const p = validateLook(patch, true);
      if (!p.ok) return { ok: false, code: p.code, look: start, changed: [] };
      const next = Object.assign({}, start, p.value);
      applyRules(next, p.value);
      next.v = 1;
      const changed = [];
      const ks = Object.keys(next);
      for (let i = 0; i < ks.length; i++) if (next[ks[i]] !== start[ks[i]]) changed.push(ks[i]);
      return { ok: true, code: 'OK', look: next, changed: changed };
    } catch (e) {
      warn('alter failed: ' + (e && e.message));
      return { ok: false, code: 'E_FORGE_TYPE', look: Object.assign({}, DEFAULTS), changed: [] };
    }
  }

  // ---------------------------------------------------------------- library

  function snapshotLibrary() {
    const out = [];
    Object.keys(custom).forEach(function (k) { out.push(JSON.parse(JSON.stringify(custom[k]))); });
    return { v: 1, list: out };
  }

  function exportLibrary() {
    try {
      return JSON.stringify(snapshotLibrary());
    } catch (e) {
      return '{"v":1,"list":[]}';
    }
  }

  function importValidated(lib) {
    const r = validateLibrary(lib);
    if (!r.ok) return { ok: false, code: r.code, n: 0 };
    let fresh = 0;
    r.value.list.forEach(function (a) {
      if (!custom[a.id]) fresh++;
    });
    if (customCount + fresh > MAX_CUSTOM) return { ok: false, code: 'E_FORGE_LIMIT', n: 0 };
    let n = 0;
    for (let i = 0; i < r.value.list.length; i++) {
      const rr = register(r.value.list[i]);
      if (rr.ok) n++;
    }
    return { ok: true, code: 'OK', n: n };
  }

  function importLibrary(text) {
    try {
      if (typeof text !== 'string') return { ok: false, code: 'E_FORGE_TYPE', n: 0 };
      if (text.length > LIBRARY_MAX_BYTES) return { ok: false, code: 'E_FORGE_LIMIT', n: 0 };
      let parsed;
      try { parsed = JSON.parse(text); } catch (e) { return { ok: false, code: 'E_FORGE_PARSE', n: 0 }; }
      return importValidated(parsed);
    } catch (e) {
      warn('importLibrary failed: ' + (e && e.message));
      return { ok: false, code: 'E_FORGE_PARSE', n: 0 };
    }
  }

  function saveLibrary(storage) {
    try {
      if (!storage || typeof storage.setItem !== 'function') return { ok: false, code: 'E_FORGE_TYPE' };
      const text = exportLibrary();
      if (text.length > LIBRARY_MAX_BYTES) return { ok: false, code: 'E_FORGE_LIMIT' };
      storage.setItem(LIBRARY_KEY, text);
      return { ok: true, code: 'OK' };
    } catch (e) {
      warn('saveLibrary failed: ' + (e && e.message));
      return { ok: false, code: 'E_FORGE_TYPE' };
    }
  }

  function loadLibrary(storage) {
    try {
      if (!storage || typeof storage.getItem !== 'function') return { ok: false, code: 'E_FORGE_TYPE' };
      const text = storage.getItem(LIBRARY_KEY);
      if (text === null || text === undefined) return { ok: true, code: 'OK' };
      const r = importLibrary(text);
      return { ok: r.ok, code: r.code };
    } catch (e) {
      warn('loadLibrary failed: ' + (e && e.message));
      return { ok: false, code: 'E_FORGE_TYPE' };
    }
  }

  // ---------------------------------------------------------------- reinforcements

  function reinforcement(o) {
    try {
      if (!isPlain(o)) return null;
      const a = AD();
      const table = a && Array.isArray(a.REINFORCE) ? a.REINFORCE : [];
      const fear = sanNum(safeRead(o, 'fear'));
      const night = Math.floor(sanNum(safeRead(o, 'night')));
      const runSeed = Math.floor(sanNum(safeRead(o, 'runSeed')));
      const fired = Math.floor(sanNum(safeRead(o, 'fired')));
      if (fired < 0 || fired >= table.length) return null;
      const entry = table[fired];
      if (!(fear >= entry.fear)) return null;
      return { archetype: entry.archetype, seed: (runSeed * 31 + night * 977 + fired * 7919) >>> 0, card: entry.card };
    } catch (e) {
      return null;
    }
  }

  // ---------------------------------------------------------------- editor field table

  function buildFields() {
    const E = enums();
    const R = ranges();
    const steps = { height: 0.01, build: 0.01, stride: 0.01, nose: 0.01, stoop: 0.01, shoulder: 0.01, hem: 0.01, skin: 0.01 };
    const out = [];
    NUM_KEYS.forEach(function (k) { out.push({ key: k, type: 'num', min: R[k][0], max: R[k][1], step: steps[k] }); });
    ENUM_KEYS.forEach(function (k) { out.push({ key: k, type: 'enum', values: (E[k] || []).slice() }); });
    BOOL_KEYS.forEach(function (k) { out.push({ key: k, type: 'bool' }); });
    return deepFreeze(out);
  }
  let fields = null;

  const Forge = {
    lookSeed: lookSeed,
    legacyLook: legacyLook,
    generate: generate,
    alter: alter,
    validate: validate,
    archetype: archetype,
    list: list,
    byRole: byRole,
    register: register,
    loadLibrary: loadLibrary,
    saveLibrary: saveLibrary,
    exportLibrary: exportLibrary,
    importLibrary: importLibrary,
    reinforcement: reinforcement
  };
  Object.defineProperty(Forge, 'LOOK_FIELDS', {
    enumerable: true,
    get: function () {
      try {
        if (!fields) fields = buildFields();
        return fields;
      } catch (e) {
        return Object.freeze([]);
      }
    }
  });

  VCS.Forge = Forge;
  if (typeof module !== 'undefined' && module.exports) module.exports = Forge;
})(typeof window !== 'undefined' ? window : globalThis);
