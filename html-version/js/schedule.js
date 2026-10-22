(function (root) {
  'use strict';
  const VCS = (root.VCS = root.VCS || {});

  // V1 night schedules. The night clock runs 20:00 (0) -> 06:00 (1); 01:00 is 0.5.
  // A role is a list of [places, until, act]: where to be until that fraction of the night, and what they do there.
  // Place tokens: a map place name ('well'), or '@kind' = the villager's own home place ('@bed' -> `${home}_bed`).
  // Rule of the village: everyone but the watch and the night owls is indoors by 01:00 and in bed well before dawn.
  // Pure data + math; people.js owns walking.

  const SEATED = { sleep: true, eat: true, sit: true, mend: true, spin: true, drink: true, pray: true, whittle: true };

  // Role templates come from the archetype data (js/data/archetypes.js): array schedules are used as-is, 'watch' maps to the post walker below.
  const ROLES = {};

  // The watch walks the posts all night, never going indoors. Slot picks the direction and starting post.
  const POSTS = ['square', 'street_w', 'well', 'street_mid', 'street_e', 'lane_s', 'road_s', 'street_far'];
  const WATCH_STOPS = 12;
  function watchRole(slot) {
    const n = POSTS.length;
    const out = [];
    for (let i = 0; i < WATCH_STOPS; i++) {
      const k = (((slot % 2 ? -i : i) + slot * 3) % n + n) % n;
      out.push([[POSTS[k]], (i + 1) / WATCH_STOPS, 'watch']);
    }
    return out;
  }

  (function loadRoles() {
    let AD = root.VCS && root.VCS.ArchetypeData ? root.VCS.ArchetypeData : null;
    try {
      if (!AD && typeof require === 'function' && typeof module !== 'undefined') AD = require('./data/archetypes.js');
    } catch (e) { /* ignore */ }
    const list = AD && Array.isArray(AD.list) ? AD.list : [];
    for (let i = 0; i < list.length; i++) {
      const a = list[i];
      if (!a || typeof a.role !== 'string' || a.role === '' || !a.schedule) continue;
      if (a.schedule === 'watch') ROLES[a.role] = watchRole;
      else if (Array.isArray(a.schedule)) ROLES[a.role] = a.schedule;
    }
  })();

  function isNum(x) { return typeof x === 'number' && isFinite(x); }
  function hasOwn(o, k) { return Object.prototype.hasOwnProperty.call(o, k); }
  function hasRole(role) { return typeof role === 'string' && hasOwn(ROLES, role); }
  function isSeated(act) { return hasOwn(SEATED, act); }

  /** Candidate place names for a token: 'well' -> ['well']; '@bed' + home 'h2' -> h2_bed, h2_bed2, h2_bed3 (those that exist). */
  function candidates(token, places, home) {
    const base = token.charAt(0) === '@' ? (home ? home + '_' + token.slice(1) : '') : token;
    if (!base) return [];
    return [base, base + '2', base + '3'].filter(function (n) { return hasOwn(places, n); });
  }

  /**
   * Build the stop list for a role. rng() in [0,1). `places` = { name: {x,y} } (cell centres), `spawn` = {x,y},
   * opts = { home, slot }. The first stop is the candidate nearest the spawn; later stops pick by slot so housemates
   * take different cells. Returns [{ place, x, y, at, until, act }] with at[0]=0, until[last]=1, or null.
   */
  function build(role, places, spawn, rng, opts) {
    if (!hasRole(role) || !places) return null;
    const o = opts || {};
    const slot = isNum(o.slot) ? Math.floor(o.slot) : 0;
    const tpl = typeof ROLES[role] === 'function' ? ROLES[role](slot) : ROLES[role];
    const stops = [];
    let prev = 0;
    for (let i = 0; i < tpl.length; i++) {
      const last = i === tpl.length - 1;
      let to = tpl[i][1];
      const jitter = (rng() - 0.5) * 0.03;
      if (!last) to = Math.min(0.98, Math.max(prev + 0.02, to + jitter)); else to = 1;
      let names = [];
      tpl[i][0].forEach(function (t) { names = names.concat(candidates(t, places, o.home)); });
      if (!names.length) continue;
      let name;
      if (!stops.length && spawn) {
        name = names.slice().sort(function (a, b) {
          return Math.hypot(places[a].x - spawn.x, places[a].y - spawn.y) - Math.hypot(places[b].x - spawn.x, places[b].y - spawn.y);
        })[0];
      } else {
        name = names[Math.abs(slot) % names.length];
      }
      stops.push({ place: name, x: places[name].x, y: places[name].y, at: stops.length ? prev : 0, until: to, act: tpl[i][2] || 'wait' });
      prev = to;
    }
    if (!stops.length) return null;
    stops[0].at = 0;
    stops[stops.length - 1].until = 1;
    return stops;
  }

  /** Index of the stop active at night fraction f (clamped to 0..1). */
  function stopAt(stops, f) {
    if (!stops || !stops.length) return -1;
    if (!isNum(f)) return 0;
    f = f < 0 ? 0 : f > 1 ? 1 : f;
    for (let i = 0; i < stops.length; i++) if (f < stops[i].until) return i;
    return stops.length - 1;
  }

  /** Per-person schedule state, or null when the role has no stops. */
  function make(role, places, spawn, rng, opts) {
    const stops = build(role, places, spawn, rng, opts);
    if (!stops) return null;
    return { role: role, home: opts && opts.home ? opts.home : null, stops: stops, si: -1, target: -1, en: false, retarget: false };
  }

  /** Drop interior waypoints that sit on a straight run (route cells -> fewer, longer legs). */
  function simplify(route) {
    if (!route || route.length < 3) return route || [];
    const out = [route[0]];
    for (let i = 1; i < route.length - 1; i++) {
      const a = out[out.length - 1];
      const b = route[i];
      const c = route[i + 1];
      if ((b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x) !== 0) out.push(b);
    }
    out.push(route[route.length - 1]);
    return out;
  }

  /** Seconds until the stop at index si ends, for the debug readout. */
  function eta(stops, si, f, nightSec) {
    if (!stops || si < 0 || !stops[si] || !isNum(f) || !isNum(nightSec)) return 0;
    return Math.max(0, (stops[si].until - f) * nightSec);
  }

  /** Night fraction of 01:00 (the village is indoors by then, apart from the watch and night owls). */
  const CURFEW = 0.5;

  // V2 meetings: weights [chat, hello, ignore] by role pair ('a|b', roles sorted); 'family' = housemates, 'default' otherwise.
  // chat = stop and talk 4-10 s, hello = a nod and a word (1.5-3 s), ignore = walk on. mood is a hint for the voices.
  const CHAT = {
    family: { w: [0.7, 0.25, 0.05], mood: 'warm' },
    'default': { w: [0.25, 0.4, 0.35], mood: 'neutral' },
    pairs: {
      'drunk|priest': { w: [0.15, 0.25, 0.6], mood: 'curt' },
      'drunk|guard': { w: [0.1, 0.3, 0.6], mood: 'curt' },
      'guard|guard': { w: [0.3, 0.5, 0.2], mood: 'neutral' },
      'elder|priest': { w: [0.6, 0.3, 0.1], mood: 'warm' },
      'innkeeper|regular': { w: [0.6, 0.3, 0.1], mood: 'warm' },
      'drunk|innkeeper': { w: [0.4, 0.3, 0.3], mood: 'neutral' },
      'insomniac|insomniac': { w: [0.4, 0.4, 0.2], mood: 'neutral' }
    },
    chatSec: [4, 10], helloSec: [1.5, 3]
  };
  const CHAT_KINDS = ['chat', 'hello', 'ignore'];

  /** Weights entry for a role pair. */
  function chatEntry(roleA, roleB, sameHome) {
    if (sameHome) return CHAT.family;
    const key = String(roleA) < String(roleB) ? roleA + '|' + roleB : roleB + '|' + roleA;
    return hasOwn(CHAT.pairs, key) ? CHAT.pairs[key] : CHAT['default'];
  }

  /** Pick 'chat' | 'hello' | 'ignore' with r1 in [0,1); duration via r2: {kind, mood, sec}. */
  function chatRoll(roleA, roleB, sameHome, r1, r2) {
    const e = chatEntry(roleA, roleB, sameHome);
    let acc = 0;
    let k = 2;
    for (let i = 0; i < 3; i++) { acc += e.w[i]; if (r1 < acc) { k = i; break; } }
    const kind = CHAT_KINDS[k];
    const rng = kind === 'chat' ? CHAT.chatSec : CHAT.helloSec;
    return { kind: kind, mood: e.mood, sec: kind === 'ignore' ? 0 : rng[0] + (rng[1] - rng[0]) * r2 };
  }

  const Schedule = { CHAT: CHAT, chatEntry: chatEntry, chatRoll: chatRoll, ROLES: ROLES, CURFEW: CURFEW, hasRole: hasRole, isSeated: isSeated, build: build, make: make, stopAt: stopAt, simplify: simplify, eta: eta };
  VCS.Schedule = Schedule;
  if (typeof module !== 'undefined' && module.exports) module.exports = Schedule;
})(typeof window !== 'undefined' ? window : globalThis);
