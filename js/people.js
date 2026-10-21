(function (root) {
  'use strict';
  const VCS = (root.VCS = root.VCS || {});

  // People walk fixed looping paths (from map data), pause at waypoints and
  // look around. They are never drawn live: a sonar wavefront that reaches a
  // person leaves an "echo" snapshot of their pose that the renderer fades.
  const TWO_PI = Math.PI * 2;
  const LOOK_MAX = 0.6;
  const DEFAULT_SPEED = 1.2;
  const DEFAULT_WAIT = 1.0;
  // Reaction parameters (contract section 2); ctx.react overrides field by field.
  const REACT_DEFAULTS = {
    startleDist: 3, seeDist: 8, seeCone: 2.0944, bumpDist: 1, fleeMul: 1.6,
    calmAfter: 10, screamGap: 2, startleTime: 1, arriveGrace: 1, lightSeen: 0.3, dazedTime: 3,
    bumpArc: 1.7453, bumpBackDist: 0.5, bumpFreeze: 0.4, waryTime: 20, fleeCap: 2.55, lightPref: 1
  };
  const HIDE_MAX_STEPS = 30;
  const LIT_MAX_STEPS = 15;
  const LIT_MIN = 0.3;
  const WARY_SEE_MUL = 0.5;
  const FEAR_SHIFT_PER = 0.015; // night fraction pulled forward per fear point (fear max 15)
  const FEAR_SHIFT_MAX = 0.2;
  const EXPOSE_FULL = 0.7; // light level at which a villager sees you from the full seeDist
  const EXPOSE_MIN_MUL = 0.6; // seeDist share at the lightSeen threshold
  const WHIMPER_GAP = 1.5;
  const MAX_EVENTS = 64;
  const NO_EVENTS = Object.freeze([]);

  function logger() {
    try {
      return root.VCS && root.VCS.Log ? root.VCS.Log.get('people') : null;
    } catch (e) {
      return null;
    }
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

  // Signature item per villager (one each, spread across ids). Hats sit on the head, 'cane' / 'lantern' /
  // 'umbrella' / 'basket' are carried, 'scarf' and 'hood' hang from the neck.
  const ACCESSORIES = ['tophat', 'nightcap', 'bonnet', 'cane', 'scarf', 'lantern', 'hood', 'umbrella', 'cap', 'basket'];
  const HATS = ['tophat', 'nightcap', 'bonnet', 'cap', 'hood'];
  const PROPS = ['cane', 'lantern', 'umbrella', 'basket'];
  const BODIES = ['bean', 'pear', 'stick', 'round', 'box'];
  const HEADS = ['round', 'egg', 'square', 'long'];
  const HAIRS = ['none', 'tuft', 'bun', 'spiky', 'curls', 'bob'];

  /**
   * Deterministic appearance for person id (seeded): height, build, stride, the signature accessory
   * (distinct across ids) plus body/head shapes, hair, beard, nose and a coat flag for the renderer.
   */
  function makeLook(seed, id, accOffset) {
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

  /** True when the radius box around (x,y) touches a wall. */
  function blocked(world, x, y, r) {
    if (typeof world.blocks === 'function') return world.blocks(x, y, r);
    return world.isSolid(x - r, y - r) || world.isSolid(x + r, y - r) ||
      world.isSolid(x - r, y + r) || world.isSolid(x + r, y + r);
  }

  /** True when the straight segment a->b never crosses a wall (sampled every 0.1 cell). */
  function segmentClear(world, ax, ay, bx, by) {
    const len = Math.hypot(bx - ax, by - ay);
    const n = Math.max(1, Math.ceil(len / 0.1));
    for (let i = 0; i <= n; i++) {
      const f = i / n;
      if (world.isSolid(ax + (bx - ax) * f, ay + (by - ay) * f)) return false;
    }
    return true;
  }

  /** Path legs may pass through local doors (people open them) but not walls or solid props. */
  function legClear(world, ax, ay, bx, by) {
    const len = Math.hypot(bx - ax, by - ay);
    const n = Math.max(1, Math.ceil(len / 0.1));
    const hasTile = typeof world.tileAt === 'function';
    const hasBlocks = typeof world.blocks === 'function' && Array.isArray(world.props) && world.props.length > 0;
    for (let i = 0; i <= n; i++) {
      const f = i / n;
      const x = ax + (bx - ax) * f;
      const y = ay + (by - ay) * f;
      if (world.isSolid(x, y)) {
        const t = hasTile ? world.tileAt(x, y) : '';
        if (t !== 'D' && t !== 'G') return false;
      } else if (hasBlocks && world.blocks(x, y, 0)) {
        return false;
      }
    }
    return true;
  }

  /** Build a validated path for a spawn; falls back to a one-point path. */
  function buildPath(world, spawn, def, id) {
    const log = logger();
    const pts = def && Array.isArray(def.points) ? def.points : null;
    const waits = def && Array.isArray(def.waits) ? def.waits : [];
    const one = [{ x: spawn.x, y: spawn.y, wait: DEFAULT_WAIT }];
    if (!pts || !pts.length) {
      if (log) log.warn('person ' + id + ' has no path; idling at spawn');
      return one;
    }
    const path = [];
    for (let i = 0; i < pts.length; i++) {
      const p = pts[i];
      if (!Array.isArray(p) || p.length < 2 || !isFinite(p[0]) || !isFinite(p[1])) {
        if (log) log.warn('person ' + id + ' path point ' + i + ' invalid; idling at spawn');
        return one;
      }
      const w = typeof waits[i] === 'number' && waits[i] >= 0 ? waits[i] : DEFAULT_WAIT;
      path.push({ x: p[0] + 0.5, y: p[1] + 0.5, wait: w });
    }
    if (Math.abs(path[0].x - spawn.x) > 1e-6 || Math.abs(path[0].y - spawn.y) > 1e-6) {
      if (log) log.warn('person ' + id + ' path does not start at its P tile; idling at spawn');
      return one;
    }
    for (let i = 0; i < path.length; i++) {
      const a = path[i];
      const b = path[(i + 1) % path.length];
      if (world.isSolid(a.x, a.y) || !legClear(world, a.x, a.y, b.x, b.y)) {
        if (log) log.warn('person ' + id + ' path segment ' + i + ' crosses a wall; idling at spawn');
        return one;
      }
    }
    return path;
  }

  /** Valid hide cells [[x,y]...] (in-bounds, not solid) from mapDef.hides; [] when absent. */
  function sanitizeHides(world, mapDef) {
    const out = [];
    const src = mapDef && Array.isArray(mapDef.hides) ? mapDef.hides : [];
    for (let i = 0; i < src.length && out.length < 256; i++) {
      const h = src[i];
      if (!Array.isArray(h) || h.length < 2 || !isFinite(h[0]) || !isFinite(h[1])) continue;
      const x = Math.floor(h[0]) + 0.5;
      const y = Math.floor(h[1]) + 0.5;
      if (!world || typeof world.isSolid !== 'function' || world.isSolid(x, y)) continue;
      out.push({ x: x, y: y });
    }
    return out;
  }

  function cellWalkable(world, cx, cy) {
    const x = cx + 0.5;
    const y = cy + 0.5;
    if (!world.isSolid(x, y)) return !(typeof world.blocks === 'function' && world.blocks(x, y, 0));
    const t = typeof world.tileAt === 'function' ? world.tileAt(x, y) : '';
    return t === 'D' || t === 'G';
  }

  function litAt(world, x, y) {
    if (!world || typeof world.lightAt !== 'function') return 0;
    const v = world.lightAt(x, y);
    return typeof v === 'number' && isFinite(v) ? v : 0;
  }

  /** True when the cell at (x,y) or a direct neighbour is lit (>= LIT_MIN). */
  function litAround(world, x, y) {
    return litAt(world, x, y) >= LIT_MIN || litAt(world, x + 1, y) >= LIT_MIN || litAt(world, x - 1, y) >= LIT_MIN ||
      litAt(world, x, y + 1) >= LIT_MIN || litAt(world, x, y - 1) >= LIT_MIN;
  }

  /** BFS over walkable cells from p; goal(cx,cy) picks the target. Returns the cell list (start excluded) or null. */
  function bfsRoute(world, p, goal, maxSteps) {
    const sx = Math.floor(p.x);
    const sy = Math.floor(p.y);
    const prev = new Map();
    const key = function (cx, cy) { return (cy + 1000) * 100000 + (cx + 1000); };
    let frontier = [[sx, sy]];
    prev.set(key(sx, sy), null);
    let found = null;
    for (let step = 0; step <= maxSteps && frontier.length && !found; step++) {
      const next = [];
      for (let i = 0; i < frontier.length; i++) {
        const c = frontier[i];
        if ((c[0] !== sx || c[1] !== sy) && goal(c[0], c[1])) { found = c; break; }
        const nb = [[c[0] + 1, c[1]], [c[0] - 1, c[1]], [c[0], c[1] + 1], [c[0], c[1] - 1]];
        for (let k = 0; k < 4; k++) {
          const kk = key(nb[k][0], nb[k][1]);
          if (prev.has(kk) || !cellWalkable(world, nb[k][0], nb[k][1])) continue;
          prev.set(kk, c);
          next.push(nb[k]);
        }
      }
      frontier = next;
    }
    if (!found) return null;
    const cells = [];
    for (let c = found; c; c = prev.get(key(c[0], c[1]))) cells.push(c);
    cells.reverse();
    cells.shift();
    const route = [];
    for (let i = 0; i < cells.length; i++) route.push({ x: cells[i][0] + 0.5, y: cells[i][1] + 0.5 });
    return route;
  }

  function sched() { return VCS.Schedule || null; }

  /** Lit-street cost: cells whose own light is >= LIT_MIN are cheap, dark cells cost more. Cached per state. */
  function stepCost(state, world, cx, cy, pref) {
    if (!(pref > 0) || typeof world.lightAt !== 'function') return 1;
    const k = cy * 100000 + cx;
    let c = state.litCache.get(k);
    if (c === undefined) { c = litAt(world, cx + 0.5, cy + 0.5) >= LIT_MIN ? 1 : 1 + pref; state.litCache.set(k, c); }
    return c;
  }

  /** Cheapest walkable route (4-connected, doors open) from p to cell (tx,ty), preferring lit cells. Cell centres, start excluded; null when unreachable. */
  function routeTo(state, world, p, tx, ty, pref) {
    const sx = Math.floor(p.x);
    const sy = Math.floor(p.y);
    if (sx === tx && sy === ty) return [];
    const key = function (cx, cy) { return cy * 100000 + cx; };
    const dist = new Map();
    const prev = new Map();
    const heap = [[0, sx, sy]];
    dist.set(key(sx, sy), 0);
    prev.set(key(sx, sy), null);
    const push = function (e) {
      heap.push(e);
      let i = heap.length - 1;
      while (i > 0) {
        const up = (i - 1) >> 1;
        if (heap[up][0] <= heap[i][0]) break;
        const t = heap[up]; heap[up] = heap[i]; heap[i] = t; i = up;
      }
    };
    const pop = function () {
      const top = heap[0];
      const last = heap.pop();
      if (heap.length) {
        heap[0] = last;
        let i = 0;
        for (;;) {
          const l = i * 2 + 1;
          const r = l + 1;
          let m = i;
          if (l < heap.length && heap[l][0] < heap[m][0]) m = l;
          if (r < heap.length && heap[r][0] < heap[m][0]) m = r;
          if (m === i) break;
          const t = heap[m]; heap[m] = heap[i]; heap[i] = t; i = m;
        }
      }
      return top;
    };
    let guard = 0;
    while (heap.length && guard++ < 20000) {
      const e = pop();
      const cx = e[1];
      const cy = e[2];
      if (e[0] > dist.get(key(cx, cy))) continue;
      if (cx === tx && cy === ty) break;
      const nb = [[cx + 1, cy], [cx - 1, cy], [cx, cy + 1], [cx, cy - 1]];
      for (let k = 0; k < 4; k++) {
        const nx = nb[k][0];
        const ny = nb[k][1];
        if (!cellWalkable(world, nx, ny)) continue;
        const nd = e[0] + stepCost(state, world, nx, ny, pref);
        const nk = key(nx, ny);
        if (dist.has(nk) && dist.get(nk) <= nd) continue;
        dist.set(nk, nd);
        prev.set(nk, [cx, cy]);
        push([nd, nx, ny]);
      }
    }
    if (!prev.has(key(tx, ty))) return null;
    const cells = [];
    for (let c = [tx, ty]; c; c = prev.get(key(c[0], c[1]))) cells.push(c);
    cells.reverse();
    cells.shift();
    return cells.map(function (c) { return { x: c[0] + 0.5, y: c[1] + 0.5 }; });
  }

  /**
   * Pick a refuge: the nearest LIT cell (<= LIT_MAX_STEPS) farther from the player than p is (rp.lightPref > 0),
   * else the nearest hide spot (<= HIDE_MAX_STEPS) farther from the player. Sets p.route (cell-centre waypoints)
   * and p.ret (the way back); returns false when there is none.
   */
  function pickHide(state, world, p, px, py, rp) {
    p.route = null;
    p.ri = 0;
    if (!world) return false;
    try {
      const dp = (p.x - px) * (p.x - px) + (p.y - py) * (p.y - py);
      const far = function (cx, cy) { return (cx + 0.5 - px) * (cx + 0.5 - px) + (cy + 0.5 - py) * (cy + 0.5 - py) > dp; };
      let route = null;
      if (rp && rp.lightPref > 0 && typeof world.lightAt === 'function') {
        route = bfsRoute(world, p, function (cx, cy) { return far(cx, cy) && litAt(world, cx + 0.5, cy + 0.5) >= LIT_MIN; }, LIT_MAX_STEPS);
      }
      const hides = state.hides;
      if (!route && hides && hides.length) {
        const want = new Map();
        for (let i = 0; i < hides.length; i++) {
          const cx = Math.floor(hides[i].x);
          const cy = Math.floor(hides[i].y);
          if (far(cx, cy)) want.set(cy * 100000 + cx, true);
        }
        if (want.size) route = bfsRoute(world, p, function (cx, cy) { return want.has(cy * 100000 + cx); }, HIDE_MAX_STEPS);
      }
      if (!route) return false;
      p.route = route;
      if (!route.length) return true;
      const back = [];
      for (let i = route.length - 2; i >= 0; i--) back.push(route[i]);
      back.push({ x: p.x, y: p.y });
      p.ret = back;
      p.ri2 = 0;
      return true;
    } catch (e) {
      const log = logger();
      if (log) log.warn('pickHide failed: ' + (e && e.message));
      p.route = null;
      return false;
    }
  }

  /** Create people state from world spawns and map path data. */
  function create(world, mapDef, opts) {
    const o = opts || {};
    const seed = typeof o.seed === 'number' && isFinite(o.seed) ? o.seed : 1;
    const state = {
      people: [], echoes: [], seed: seed, rng: mulberry32(seed),
      maxEchoes: typeof o.maxEchoes === 'number' && o.maxEchoes > 0 ? Math.floor(o.maxEchoes) : 24,
      radius: 0.2, hides: sanitizeHides(world, mapDef), time: 0, nightFrac: 0, nightSec: 0, litCache: new Map(), lastScream: -Infinity, events: [], world: world || null,
      rp: {
        startleDist: REACT_DEFAULTS.startleDist, seeDist: REACT_DEFAULTS.seeDist, seeCone: REACT_DEFAULTS.seeCone,
        bumpDist: REACT_DEFAULTS.bumpDist, fleeMul: REACT_DEFAULTS.fleeMul, calmAfter: REACT_DEFAULTS.calmAfter,
        screamGap: REACT_DEFAULTS.screamGap, startleTime: REACT_DEFAULTS.startleTime,
        arriveGrace: REACT_DEFAULTS.arriveGrace, lightSeen: REACT_DEFAULTS.lightSeen, dazedTime: REACT_DEFAULTS.dazedTime,
        bumpArc: REACT_DEFAULTS.bumpArc, bumpBackDist: REACT_DEFAULTS.bumpBackDist,
        bumpFreeze: REACT_DEFAULTS.bumpFreeze, waryTime: REACT_DEFAULTS.waryTime, fleeCap: REACT_DEFAULTS.fleeCap, lightPref: REACT_DEFAULTS.lightPref
      }
    };
    const poolMin = typeof o.poolMin === 'number' && isFinite(o.poolMin) && o.poolMin > 0 ? o.poolMin : 30;
    const poolMax = typeof o.poolMax === 'number' && isFinite(o.poolMax) && o.poolMax >= poolMin ? o.poolMax : Math.max(poolMin, 50);
    const accOffset = Math.floor(mulberry32((seed * 7919 + 13) >>> 0)() * ACCESSORIES.length);
    const spawns = (world && world.spots && world.spots.people) || [];
    const defs = mapDef && Array.isArray(mapDef.paths) ? mapDef.paths : [];
    const Sched = sched();
    const places = {};
    if (Sched && mapDef && mapDef.places && typeof mapDef.places === 'object') {
      Object.keys(mapDef.places).forEach(function (k) {
        const c = mapDef.places[k];
        if (Array.isArray(c) && isFinite(c[0]) && isFinite(c[1]) && world && !world.isSolid(c[0] + 0.5, c[1] + 0.5)) places[k] = { x: c[0] + 0.5, y: c[1] + 0.5 };
      });
    }
    for (let i = 0; i < spawns.length; i++) {
      const def = defs[i];
      const path = buildPath(world, spawns[i], def, i);
      const speed = def && typeof def.speed === 'number' && def.speed > 0 ? def.speed : DEFAULT_SPEED;
      let angle = 0;
      if (path.length > 1) angle = Math.atan2(path[1].y - path[0].y, path[1].x - path[0].x);
      const sit = !!(def && def.sit === true);
      const pool = poolMin + (poolMax - poolMin) * state.rng();
      state.people.push({
        pool: pool, left: pool, dazedLeft: 0,
        id: i, x: path[0].x, y: path[0].y, angle: angle, speed: speed, path: path,
        idx: path.length > 1 && !sit ? 1 : 0, state: 'idle', idleLeft: path[0].wait,
        lookAngle: 0, lookTarget: 0, lookIn: 0.5 + state.rng() * 0.6, phase: 0, walked: 0,
        look: makeLook(seed, i, accOffset), steps: 0, stepsReported: 0,
        mode: 'path', modeLeft: 0, fleeFrom: { x: 0, y: 0 }, calmLeft: 0, fdir: 1, blockCount: 0, preState: 'idle',
        sit: sit, route: null, ri: 0, ret: null, ri2: 0, bumping: false, wary: 0, whimperIn: WHIMPER_GAP
      });
      // V1: a role with a night schedule walks routed trips between named places instead of its hand-made loop.
      const person = state.people[state.people.length - 1];
      if (Sched && !sit && def && Sched.hasRole(def.role)) {
        person.sched = Sched.make(def.role, places, { x: path[0].x, y: path[0].y }, mulberry32((seed * 31 + i * 977 + 5) >>> 0), { home: def.home, slot: i });
        if (person.sched) person.idleLeft = 0;
      }
    }
    if (o.shuffle === true) {
      // v0.8: shuffle draws come after all per-person draws so unshuffled streams are unchanged.
      for (let i = 0; i < state.people.length; i++) {
        const p = state.people[i];
        const n = p.path.length;
        if (n <= 1 || p.sit || p.sched) continue;
        const k = Math.min(n - 1, Math.floor(state.rng() * n));
        if (state.rng() < 0.5) p.path = p.path.slice().reverse();
        p.x = p.path[k].x; p.y = p.path[k].y;
        p.idx = (k + 1) % n;
        p.idleLeft = p.path[k].wait;
        p.angle = Math.atan2(p.path[p.idx].y - p.y, p.path[p.idx].x - p.x);
      }
    }
    const log = logger();
    if (log) log.info('people: ' + state.people.length + ' walkers, seed ' + seed);
    return state;
  }

  function normDiff(a) {
    let d = a % TWO_PI;
    if (d > Math.PI) d -= TWO_PI;
    else if (d < -Math.PI) d += TWO_PI;
    return d;
  }

  /** Copy ctx.react (or defaults) into the state's scratch params; no allocation. */
  function fillReact(state, react) {
    const rp = state.rp;
    const src = react && typeof react === 'object' ? react : null;
    for (const k in REACT_DEFAULTS) {
      const v = src ? src[k] : undefined;
      rp[k] = typeof v === 'number' && isFinite(v) && v >= 0 ? v : REACT_DEFAULTS[k];
    }
    return rp;
  }

  /** True when person can see point (px,py): within seeDist, inside the view cone, no solid tile between. */
  function sees(person, world, px, py, rp) {
    const r = rp || REACT_DEFAULTS;
    if (!person || !world || !isFinite(px) || !isFinite(py)) return false;
    const dx = px - person.x;
    const dy = py - person.y;
    const d2 = dx * dx + dy * dy;
    const sd = typeof r.seeDist === 'number' ? r.seeDist : REACT_DEFAULTS.seeDist;
    if (d2 > sd * sd) return false;
    if (d2 > 1e-12) {
      const cone = typeof r.seeCone === 'number' ? r.seeCone : REACT_DEFAULTS.seeCone;
      const diff = normDiff(Math.atan2(dy, dx) - (person.angle + person.lookAngle));
      if (Math.abs(diff) > cone / 2) return false;
    }
    return segmentClear(world, person.x, person.y, px, py);
  }

  /** Share of seeDist a villager sees you from at light level lit: EXPOSE_MIN_MUL at the lightSeen threshold up to 1 at EXPOSE_FULL (the veil meter's value). */
  function exposureMul(lit, lightSeen) {
    if (!(lit > lightSeen)) return EXPOSE_MIN_MUL;
    if (lit >= EXPOSE_FULL || EXPOSE_FULL <= lightSeen) return 1;
    return EXPOSE_MIN_MUL + (1 - EXPOSE_MIN_MUL) * (lit - lightSeen) / (EXPOSE_FULL - lightSeen);
  }

  /**
   * 0 = not seen, 1 = seen (light + cone + line of sight), 2 = bump-noticed (touching).
   * Bump notice needs the person to face the player within bumpArc (half-angle, 100 deg), or the player to be lit;
   * from behind or the side only bumpBackDist counts. bumpDist 0 disables bump notice entirely.
   */
  function isSeen(p, world, px, py, lit, rp) {
    const dx = px - p.x;
    const dy = py - p.y;
    const d2 = dx * dx + dy * dy;
    const isLit = lit >= rp.lightSeen;
    if (isLit) {
      const full = typeof rp.seeDist === 'number' ? rp.seeDist : REACT_DEFAULTS.seeDist;
      const sd = full * exposureMul(lit, rp.lightSeen);
      rp.seeDist = sd;
      const hit = d2 <= sd * sd && sees(p, world, px, py, rp);
      rp.seeDist = full;
      if (hit) return 1;
    }
    if (rp.bumpDist > 0 && d2 <= rp.bumpDist * rp.bumpDist) {
      let near = isLit || d2 <= 1e-12;
      if (!near) near = Math.abs(normDiff(Math.atan2(dy, dx) - (p.angle + p.lookAngle))) <= rp.bumpArc;
      const back = Math.min(rp.bumpBackDist, rp.bumpDist);
      if (near || d2 <= back * back) return 2;
    }
    return 0;
  }

  /** isSeen with the wary person's halved sight (rp is shared scratch, restored after). */
  function isSeenBy(p, world, px, py, lit, rp) {
    if (!(p.wary > 0)) return isSeen(p, world, px, py, lit, rp);
    const sd = rp.seeDist;
    rp.seeDist = sd * WARY_SEE_MUL;
    const r = isSeen(p, world, px, py, lit, rp);
    rp.seeDist = sd;
    return r;
  }

  function pushEvent(state, type, p) {
    if (state.events.length >= MAX_EVENTS) state.events.shift();
    state.events.push({ type: type, id: p.id, x: p.x, y: p.y });
  }

  function farthestWaypoint(p, px, py) {
    const path = p.path;
    let best = -1;
    let bestD = (px - p.x) * (px - p.x) + (py - p.y) * (py - p.y) + 1e-6;
    for (let i = 0; i < path.length; i++) {
      const dx = path[i].x - px;
      const dy = path[i].y - py;
      const d = dx * dx + dy * dy;
      if (d > bestD) { bestD = d; best = i; }
    }
    return best;
  }

  /** Choose the loop direction toward waypoint g given the next waypoint each way; sets p.idx and p.fdir. */
  function route(p, g, nf, nb, px, py) {
    const n = p.path.length;
    if (p.sched && n > 1) {
      // A scheduled trip is an open polyline: never wrap from its last waypoint to its first (that segment runs through walls).
      const nfBad = nf === 0 && nb > nf;
      const nbBad = nb === n - 1 && nf < nb;
      const fwd = nfBad ? false : nbBad ? true : g >= nf;
      p.fdir = fwd ? 1 : -1;
      p.idx = fwd ? nf : nb;
      return;
    }
    const cf = (g - nf + n) % n;
    const cb = (nb - g + n) % n;
    let fwd = cf < cb;
    if (cf === cb) {
      const f = p.path[nf];
      const b = p.path[nb];
      fwd = (f.x - px) * (f.x - px) + (f.y - py) * (f.y - py) >= (b.x - px) * (b.x - px) + (b.y - py) * (b.y - py);
    }
    p.fdir = fwd ? 1 : -1;
    p.idx = fwd ? nf : nb;
  }

  function startCower(p, px, py) {
    p.route = null;
    p.mode = 'cower';
    p.state = 'idle';
    p.blockCount = 0;
    p.whimperIn = WHIMPER_GAP;
    p.angle = Math.atan2(p.y - py, p.x - px);
  }

  function enterFlee(state, p, px, py, rp, opts) {
    const n = p.path.length;
    const quiet = !!(opts && opts.quiet);
    if (p.mode === 'path' || p.mode === 'startle' || p.mode === 'dazed') {
      // Person sits on the loop segment prev -> idx.
      p.fleeFrom.x = px;
      p.fleeFrom.y = py;
      p.calmLeft = rp.calmAfter;
      p.blockCount = 0;
      p.modeLeft = 0;
      p.bumping = false;
      p.mode = 'flee';
      p.dazedLeft = 0;
      if (!quiet && state.time - state.lastScream >= rp.screamGap) {
        state.lastScream = state.time;
        pushEvent(state, 'scream', p);
      }
      pushEvent(state, 'flee', p);
      p.route = null;
      p.ret = null;
      if (pickHide(state, state.world, p, px, py, rp)) {
        if (!p.route.length) { startCower(p, px, py); return; }
        p.state = 'walk';
        p.lookTarget = 0;
        return;
      }
      const g = n > 1 ? farthestWaypoint(p, px, py) : -1;
      if (g < 0) { startCower(p, px, py); return; }
      route(p, g, p.idx, (p.idx - 1 + n) % n, px, py);
      p.state = 'walk';
      p.lookTarget = 0;
    }
  }

  /** Bump notice: freeze for rp.bumpFreeze (mode 'startle'), then flee. */
  function startBump(state, p, px, py, rp) {
    p.mode = 'startle';
    p.bumping = true;
    p.modeLeft = rp.bumpFreeze;
    p.preState = p.state;
    p.state = 'idle';
    p.angle = Math.atan2(py - p.y, px - p.x);
    pushEvent(state, 'startle', p);
  }

  /** Move p toward (tx,ty) by up to step; returns distance actually moved (v0.5 movement rules). */
  function moveToward(world, p, dx, dy, dist, step, r) {
    p.angle = Math.atan2(dy, dx);
    const mx = (dx / dist) * step;
    const my = (dy / dist) * step;
    const ox = p.x;
    const oy = p.y;
    if (!blocked(world, p.x + mx, p.y, r)) p.x += mx;
    if (!blocked(world, p.x, p.y + my, r)) p.y += my;
    const moved = Math.hypot(p.x - ox, p.y - oy);
    p.walked += moved;
    const phBefore = p.phase;
    p.phase += moved * 9;
    // A foot plants at the extremes of the leg swing: phase = PI/2 + k*PI (two per cycle).
    p.steps += Math.floor((p.phase - Math.PI / 2) / Math.PI) - Math.floor((phBefore - Math.PI / 2) / Math.PI);
    if (p.phase > TWO_PI * 1000) p.phase -= TWO_PI * 1000;
    return moved;
  }

  /** Waypoint reached on a scheduled trip: keep walking the route, or settle at the stop. */
  function schedArrive(p) {
    const s = p.sched;
    if (p.idx < p.path.length - 1) { p.idx++; return; }
    settle(p, s.target);
  }

  /** At the stop for good: idle there, seated when the act is a sitting one. */
  function settle(p, si) {
    const s = p.sched;
    s.en = false;
    s.si = si;
    s.retarget = false;
    p.state = 'idle';
    p.idleLeft = 0;
    p.seated = !!(s.stops[si] && sched().isSeated(s.stops[si].act));
  }

  /** Idle with a schedule: dwell until the night clock moves on (or a flight broke the trip), then route to the stop. */
  function schedIdle(state, world, p) {
    const Sched = sched();
    const s = p.sched;
    if (s.en) { p.state = 'walk'; return; }
    // Village fear pulls the night forward: the scared go home early (the watch never does).
    const shift = s.role === 'guard' ? 0 : (state.fearShift || 0);
    const want = Sched.stopAt(s.stops, Math.min(1, state.nightFrac + shift));
    if (want === s.si && !s.retarget) return;
    const stop = s.stops[want];
    s.target = want;
    s.retarget = false;
    let cells = null;
    try { cells = routeTo(state, world, p, Math.floor(stop.x), Math.floor(stop.y), state.rp.lightPref > 0 ? 0.6 : 0); } catch (e) { cells = null; }
    if (!cells || !cells.length) { settle(p, want); return; } // there already, or unreachable: stay for this stop
    const trip = [{ x: p.x, y: p.y, wait: 0 }];
    for (let i = 0; i < cells.length; i++) trip.push({ x: cells[i].x, y: cells[i].y, wait: 0 });
    p.path = Sched.simplify(trip);
    p.idx = 1;
    p.seated = false;
    s.en = true;
    p.state = 'walk';
    p.lookTarget = 0;
  }

  function stepPath(state, world, p, dt, r) {
    // Walking back from a hide spot: retrace the cells before rejoining the loop.
    if (p.ret) {
      if (p.ri2 >= p.ret.length) { p.ret = null; } else {
        const rt = p.ret[p.ri2];
        const rx = rt.x - p.x;
        const ry = rt.y - p.y;
        const rd = Math.sqrt(rx * rx + ry * ry);
        const rs = p.speed * dt;
        p.lookAngle += (0 - p.lookAngle) * Math.min(1, 4 * dt);
        if (rd <= rs || rd <= 0.02) { p.x = rt.x; p.y = rt.y; p.walked += rd; p.ri2++; p.blockCount = 0; return; }
        if (moveToward(world, p, rx, ry, rd, rs, r) < rs * 0.05) {
          p.blockCount++;
          if (p.blockCount >= 3) { p.ret = null; p.blockCount = 0; }
        } else p.blockCount = 0;
        return;
      }
    }
    if (p.state === 'idle') {
      p.idleLeft -= dt;
      p.lookIn -= dt;
      if (p.lookIn <= 0) {
        p.lookTarget = (state.rng() * 2 - 1) * LOOK_MAX;
        p.lookIn = 0.8 + state.rng() * 0.6;
      }
      p.lookAngle += (p.lookTarget - p.lookAngle) * Math.min(1, 3 * dt);
      p.phase *= Math.max(0, 1 - 8 * dt);
      if (p.phase < 0.01) p.phase = 0;
      if (p.sched) { schedIdle(state, world, p); return; }
      if (p.idleLeft <= 0 && p.path.length > 1 && (!p.sit || p.idx !== 0 || Math.hypot(p.path[0].x - p.x, p.path[0].y - p.y) > 0.05)) {
        p.state = 'walk';
        p.lookTarget = 0;
      }
      return;
    }
    // Walking toward path[idx].
    const tgt = p.path[p.idx];
    const dx = tgt.x - p.x;
    const dy = tgt.y - p.y;
    const dist = Math.sqrt(dx * dx + dy * dy);
    const step = p.speed * dt;
    p.lookAngle += (0 - p.lookAngle) * Math.min(1, 4 * dt);
    if (dist <= step || dist <= 0.02) {
      p.x = tgt.x;
      p.y = tgt.y;
      p.walked += dist;
      if (p.sched) { schedArrive(p); return; }
      p.state = 'idle';
      p.idleLeft = tgt.wait * (0.85 + 0.3 * state.rng());
      p.idx = p.sit ? 0 : (p.idx + 1) % p.path.length;
      return;
    }
    const moved = moveToward(world, p, dx, dy, dist, step, r);
    if (moved < step * 0.05) {
      // Stuck against a wall (bad path); give up on this leg.
      if (p.sched) { p.sched.en = false; p.sched.retarget = true; p.state = 'idle'; p.idleLeft = 1; return; }
      p.state = 'idle';
      p.idleLeft = tgt.wait;
      p.idx = p.sit ? 0 : (p.idx + 1) % p.path.length;
    }
  }

  function fleeStep(p, rp, dt) {
    return Math.min(p.speed * rp.fleeMul, rp.fleeCap) * dt;
  }

  /** Run along p.route to a hide spot, then cower there. */
  function stepHide(state, world, p, dt, r, rp) {
    const px = p.fleeFrom.x;
    const py = p.fleeFrom.y;
    p.lookAngle += (0 - p.lookAngle) * Math.min(1, 4 * dt);
    const rt = p.route;
    if (!rt || p.ri >= rt.length) { startCower(p, px, py); return; }
    const step = fleeStep(p, rp, dt);
    const tgt = rt[p.ri];
    const dx = tgt.x - p.x;
    const dy = tgt.y - p.y;
    const dist = Math.sqrt(dx * dx + dy * dy);
    if (dist <= step || dist <= 0.02) {
      p.x = tgt.x;
      p.y = tgt.y;
      p.walked += dist;
      p.blockCount = 0;
      p.ri++;
      if (p.ri >= rt.length) startCower(p, px, py);
      return;
    }
    const moved = moveToward(world, p, dx, dy, dist, step, r);
    if (moved < step * 0.05) {
      p.blockCount++;
      if (p.blockCount >= 3) startCower(p, px, py);
    } else {
      p.blockCount = 0;
    }
  }

  function stepFlee(state, world, p, dt, r, rp) {
    if (p.route) { stepHide(state, world, p, dt, r, rp); return; }
    const n = p.path.length;
    const px = p.fleeFrom.x;
    const py = p.fleeFrom.y;
    const tgt = p.path[p.idx];
    const dx = tgt.x - p.x;
    const dy = tgt.y - p.y;
    const dist = Math.sqrt(dx * dx + dy * dy);
    const step = fleeStep(p, rp, dt);
    p.lookAngle += (0 - p.lookAngle) * Math.min(1, 4 * dt);
    if (dist <= step || dist <= 0.02) {
      p.x = tgt.x;
      p.y = tgt.y;
      p.walked += dist;
      p.blockCount = 0;
      const g = farthestWaypoint(p, px, py);
      if (g < 0) { startCower(p, px, py); return; }
      route(p, g, (p.idx + 1) % n, (p.idx - 1 + n) % n, px, py);
      return;
    }
    const moved = moveToward(world, p, dx, dy, dist, step, r);
    if (moved < step * 0.05) {
      p.blockCount++;
      if (p.blockCount >= 2) { startCower(p, px, py); return; }
      // Blocked once: re-pick the goal from where we stand.
      const g = farthestWaypoint(p, px, py);
      if (g < 0) { startCower(p, px, py); return; }
      route(p, g, p.idx, (p.idx - p.fdir + n + n) % n, px, py);
    } else {
      p.blockCount = 0;
    }
  }

  /** Lit waypoint (surroundings lit), farthest from (px,py); -1 when none or lightPref is 0. */
  function litWaypoint(p, world, px, py, rp) {
    if (!rp || !(rp.lightPref > 0) || !world || typeof world.lightAt !== 'function') return -1;
    let best = -1;
    let bestD = -1;
    for (let i = 0; i < p.path.length; i++) {
      const w = p.path[i];
      if (!litAround(world, w.x, w.y)) continue;
      const d = (w.x - px) * (w.x - px) + (w.y - py) * (w.y - py);
      if (d > bestD) { bestD = d; best = i; }
    }
    return best;
  }

  function resumePath(p, rp, world) {
    const n = p.path.length;
    p.mode = 'path';
    p.route = null;
    p.calmLeft = 0;
    p.blockCount = 0;
    p.lookTarget = 0;
    p.wary = rp && rp.waryTime > 0 ? rp.waryTime : 0;
    if (p.sched) {
      // Scheduled people re-plan the trip to their current stop from wherever the flight left them.
      p.sched.en = false;
      p.sched.retarget = true;
      p.seated = false;
      p.state = 'idle';
      p.idleLeft = 0;
      return;
    }
    if (p.sit) {
      // Sitters walk back to their seat and stay.
      p.idx = 0;
      if (n > 1 && Math.hypot(p.path[0].x - p.x, p.path[0].y - p.y) > 0.05) { p.state = 'walk'; return; }
      p.state = 'idle';
      p.idleLeft = p.path[0].wait;
      return;
    }
    if (p.wary > 0 && n > 1) {
      // Wary: skip the waypoint nearest the player's last known spot; resume at the farthest one.
      let g = litWaypoint(p, world, p.fleeFrom.x, p.fleeFrom.y, rp);
      if (g < 0) g = farthestWaypoint(p, p.fleeFrom.x, p.fleeFrom.y);
      if (g >= 0) { p.idx = g; p.state = 'walk'; return; }
    }
    if (n > 1) {
      const a = p.path[p.idx];
      const b = p.path[(p.idx - p.fdir + n + n) % n];
      const da = (a.x - p.x) * (a.x - p.x) + (a.y - p.y) * (a.y - p.y);
      const db = (b.x - p.x) * (b.x - p.x) + (b.y - p.y) * (b.y - p.y);
      if (db < da) p.idx = (p.idx - p.fdir + n + n) % n;
      p.state = 'walk';
    } else {
      p.state = 'idle';
      p.idleLeft = p.path[0].wait;
    }
  }

  /**
   * Advance all people by dt seconds (clamped to 0.1). Optional ctx {player:{x,y}, playerLit, react, t, grace}
   * enables seeing/fleeing; without it people behave exactly as in v0.5.
   */
  function update(state, world, dt, ctx) {
    if (!(dt > 0)) return;
    if (dt > 0.1) dt = 0.1;
    const ps = state.people;
    const r = state.radius;
    state.time += dt;
    state.world = world;
    const rp = fillReact(state, ctx ? ctx.react : null);
    const pl = ctx && ctx.player;
    const hasPlayer = !!pl && isFinite(pl.x) && isFinite(pl.y) && !(ctx.grace > 0);
    const lit = ctx && typeof ctx.playerLit === 'number' ? ctx.playerLit : 0;
    if (ctx && typeof ctx.nightFrac === 'number' && isFinite(ctx.nightFrac)) state.nightFrac = ctx.nightFrac;
    if (ctx && typeof ctx.fear === 'number' && isFinite(ctx.fear)) state.fearShift = Math.min(FEAR_SHIFT_MAX, Math.max(0, ctx.fear) * FEAR_SHIFT_PER);
    if (ctx && typeof ctx.nightSec === 'number' && isFinite(ctx.nightSec)) state.nightSec = ctx.nightSec;
    // Pose bookkeeping for the renderer (no behaviour): seconds in the current mode, gait phase before this tick.
    for (let i = 0; i < ps.length; i++) {
      const p = ps[i];
      if (p.mode !== p.modePrev) { p.modePrev = p.mode; p.modeAge = 0; } else p.modeAge = (p.modeAge || 0) + dt;
      p.ph0 = p.phase;
    }
    for (let i = 0; i < ps.length; i++) {
      const p = ps[i];
      const mode = p.mode;
      if (mode === 'fed' || mode === 'grapple') continue; // v0.7: fed people are fully inert; grappled too
      if (mode === 'dazed') {
        p.lookAngle += (0 - p.lookAngle) * Math.min(1, 4 * dt);
        p.phase *= Math.max(0, 1 - 8 * dt);
        if (p.phase < 0.01) p.phase = 0;
        p.dazedLeft -= dt;
        p.whimperIn -= dt;
        if (p.whimperIn <= 0) { p.whimperIn += WHIMPER_GAP; pushEvent(state, 'whimper', p); }
        if (p.dazedLeft <= 0) enterFlee(state, p, p.fleeFrom.x, p.fleeFrom.y, rp, { quiet: true });
        continue;
      }
      if (p.wary > 0) p.wary = Math.max(0, p.wary - dt);
      if (mode === 'startle' && p.bumping) {
        // Bump freeze: a beat of surprise so a grab can land, then run.
        p.lookAngle += (0 - p.lookAngle) * Math.min(1, 4 * dt);
        p.phase *= Math.max(0, 1 - 8 * dt);
        if (p.phase < 0.01) p.phase = 0;
        p.modeLeft -= dt;
        if (p.modeLeft <= 0) {
          p.bumping = false;
          if (hasPlayer) enterFlee(state, p, pl.x, pl.y, rp);
          else { p.mode = 'path'; p.state = p.preState; }
        }
        continue;
      }
      const seen = hasPlayer ? isSeenBy(p, world, pl.x, pl.y, lit, rp) : 0;
      if (mode === 'path') {
        if (seen === 2 && rp.bumpFreeze > 0) { startBump(state, p, pl.x, pl.y, rp); continue; }
        if (seen) { enterFlee(state, p, pl.x, pl.y, rp); continue; }
        stepPath(state, world, p, dt, r);
      } else if (mode === 'startle') {
        if (seen) { enterFlee(state, p, pl.x, pl.y, rp); continue; }
        p.lookAngle += (0 - p.lookAngle) * Math.min(1, 4 * dt);
        p.phase *= Math.max(0, 1 - 8 * dt);
        if (p.phase < 0.01) p.phase = 0;
        p.modeLeft -= dt;
        if (p.modeLeft <= 0) {
          p.mode = 'path';
          p.state = p.preState;
        }
      } else {
        // flee or cower
        if (seen) {
          p.calmLeft = rp.calmAfter;
          p.fleeFrom.x = pl.x;
          p.fleeFrom.y = pl.y;
        } else {
          p.calmLeft -= dt;
          if (p.calmLeft <= 0) { resumePath(p, rp, world); continue; }
        }
        if (mode === 'flee') {
          stepFlee(state, world, p, dt, r, rp);
        } else {
          p.lookAngle += (0 - p.lookAngle) * Math.min(1, 4 * dt);
          p.phase *= Math.max(0, 1 - 8 * dt);
          if (p.phase < 0.01) p.phase = 0;
          p.angle = Math.atan2(p.y - p.fleeFrom.y, p.x - p.fleeFrom.x);
          p.whimperIn -= dt;
          if (p.whimperIn <= 0) { p.whimperIn += WHIMPER_GAP; pushEvent(state, 'whimper', p); }
        }
      }
    }
    // Gait phase rate (rad/s) over this tick: lets an echo keep walking while it glows.
    for (let i = 0; i < ps.length; i++) {
      const p = ps[i];
      const d = p.phase - p.ph0;
      p.phaseRate = d > 0 && d < 10 ? d / dt : 0;
    }
  }

  /**
   * A sound at (x,y): people in path mode within startleDist freeze and turn toward it (event 'startle');
   * if the player is lit and visible they flee instead. ctx optional {player, playerLit, react, grace}.
   */
  function react(state, x, y, kind, ctx, dist) {
    if (!state || !state.people || !isFinite(x) || !isFinite(y)) return;
    const rp = fillReact(state, ctx ? ctx.react : null);
    if (typeof dist === 'number' && isFinite(dist) && dist > 0) rp.startleDist = dist;
    const world = state.world;
    const pl = ctx && ctx.player;
    const hasPlayer = !!world && !!pl && isFinite(pl.x) && isFinite(pl.y) && !(ctx.grace > 0);
    const lit = ctx && typeof ctx.playerLit === 'number' ? ctx.playerLit : 0;
    const ps = state.people;
    const r2 = rp.startleDist * rp.startleDist;
    for (let i = 0; i < ps.length; i++) {
      const p = ps[i];
      if (p.mode !== 'path') continue;
      const dx = p.x - x;
      const dy = p.y - y;
      if (dx * dx + dy * dy > r2) continue;
      let seesYou = false;
      if (hasPlayer && lit >= rp.lightSeen) {
        const sd = rp.seeDist;
        rp.seeDist = sd * exposureMul(lit, rp.lightSeen) * (p.wary > 0 ? WARY_SEE_MUL : 1);
        seesYou = sees(p, world, pl.x, pl.y, rp);
        rp.seeDist = sd;
      }
      if (seesYou) {
        enterFlee(state, p, pl.x, pl.y, rp);
        continue;
      }
      p.mode = 'startle';
      p.modeLeft = rp.startleTime;
      p.preState = p.state;
      p.state = 'idle';
      p.angle = Math.atan2(y - p.y, x - p.x);
      pushEvent(state, 'startle', p);
    }
  }

  /** Events ({type:'scream'|'startle'|'flee'|'whimper', id, x, y}) since the last call; clears them. */
  function drainEvents(state) {
    if (!state || !state.events || state.events.length === 0) return NO_EVENTS;
    const out = state.events;
    state.events = [];
    return out;
  }

  /** Drop all echo snapshots (used on map change). */
  function clearEchoes(state) {
    if (state && state.echoes) state.echoes.length = 0;
  }

  /** True when a person can currently be fed on (v0.7). */
  function isFeedable(person) {
    return !!person && (person.mode === 'path' || person.mode === 'startle' || person.mode === 'flee' ||
      person.mode === 'cower' || person.mode === 'dazed');
  }

  function findPerson(state, id) {
    if (!state || !Array.isArray(state.people)) return null;
    for (let i = 0; i < state.people.length; i++) if (state.people[i].id === id) return state.people[i];
    return null;
  }

  /** Grab person id for drinking (v0.7.2): becomes inert 'grapple'. True when grabbed, false if missing or not feedable. */
  function grab(state, id) {
    try {
      const p = findPerson(state, id);
      if (!p || !isFeedable(p)) return false;
      p.mode = 'grapple';
      p.bumping = false;
      p.state = 'idle';
      p.phase = 0;
      p.modeLeft = 0;
      p.blockCount = 0;
      return true;
    } catch (e) {
      return false;
    }
  }

  /** Release a grappled person: 'dazed' (keeps left) for rp.dazedTime, then flees quietly from (fromX,fromY). */
  function release(state, id, fromX, fromY) {
    try {
      const p = findPerson(state, id);
      if (!p || p.mode !== 'grapple') return false;
      if (isFinite(fromX) && isFinite(fromY)) { p.fleeFrom.x = fromX; p.fleeFrom.y = fromY; }
      const dt = state.rp && typeof state.rp.dazedTime === 'number' && state.rp.dazedTime >= 0 ? state.rp.dazedTime : REACT_DEFAULTS.dazedTime;
      p.mode = 'dazed';
      p.state = 'idle';
      p.dazedLeft = dt;
      p.whimperIn = WHIMPER_GAP;
      p.phase = 0;
      return true;
    } catch (e) {
      return false;
    }
  }

  /** Drain amount from person id's blood pool. Returns the new left (>= 0), or -1 for an unknown person. */
  function drink(state, id, amount) {
    try {
      const p = findPerson(state, id);
      if (!p) return -1;
      if (typeof amount === 'number' && isFinite(amount) && amount > 0) p.left = Math.max(0, p.left - amount);
      return p.left;
    } catch (e) {
      return -1;
    }
  }

  /** Nearest feedable person within reach of (x,y) and within +-arc of angle, or null (v0.7). */
  function feedTarget(state, x, y, angle, reach, arc) {
    try {
      if (!state || !Array.isArray(state.people) || !isFinite(x) || !isFinite(y) || !isFinite(angle)) return null;
      const rch = typeof reach === 'number' && isFinite(reach) && reach > 0 ? reach : 1.5;
      const ar = typeof arc === 'number' && isFinite(arc) && arc > 0 ? arc : Math.PI / 3;
      let best = null;
      let bestD = Infinity;
      for (let i = 0; i < state.people.length; i++) {
        const p = state.people[i];
        if (!isFeedable(p) || !isFinite(p.x) || !isFinite(p.y)) continue;
        const dx = p.x - x;
        const dy = p.y - y;
        const d = Math.sqrt(dx * dx + dy * dy);
        if (d > rch) continue;
        if (d > 1e-6 && Math.abs(normDiff(Math.atan2(dy, dx) - angle)) > ar) continue;
        if (d < bestD) { bestD = d; best = p; }
      }
      return best;
    } catch (e) {
      return null;
    }
  }

  /** Mark person id as fed: inert for the rest of the night (v0.7). */
  function markFed(state, id) {
    try {
      if (!state || !Array.isArray(state.people)) return false;
      for (let i = 0; i < state.people.length; i++) {
        const p = state.people[i];
        if (p.id === id) {
          p.mode = 'fed';
          p.state = 'idle';
          p.phase = 0;
          p.modeLeft = 0;
          return true;
        }
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  const band = [0, 1.2];

  /** Lit height band [zMin, zMax] of a person at (x,y) once pulse pu has reached its full radius. */
  function heightBandOf(Sonar, pu, x, y, out) {
    out[0] = 0;
    out[1] = 1.2;
    if (typeof Sonar.heightBand !== 'function') return out;
    const z = typeof pu.z === 'number' ? pu.z : 0.5;
    const tFull = pu.t0 + pu.range / pu.speed;
    if (!Sonar.heightBand(pu, tFull, x, y, out)) {
      // Person sits at the very edge of the ring: only a thin slice at the source height.
      out[0] = Math.max(0, z - 0.15);
      out[1] = Math.min(1.2, z + 0.15);
    }
    // Footsteps ring the floor: they reveal feet and shins only.
    if ((pu.kind === 'step' || pu.kind === 'personStep') && out[1] > 0.5) out[1] = 0.5;
    return out;
  }

  /** Record echo snapshots for every person any sound wavefront crossed between tPrev and t. Returns the new echoes. */
  function updateEchoes(state, sonar, tPrev, t) {
    const made = [];
    const Sonar = root.VCS.Sonar;
    const pulses = sonar && sonar.pulses ? sonar.pulses : [];
    const ps = state.people;
    const es = state.echoes;
    for (let k = 0; k < pulses.length; k++) {
      const pu = pulses[k];
      const str = typeof pu.strength === 'number' ? pu.strength : 1;
      if (str <= 0.01) continue;
      for (let i = 0; i < ps.length; i++) {
        const p = ps[i];
        const ex = p.x - pu.x;
        const ey = p.y - pu.y;
        if (ex * ex + ey * ey > pu.range * pu.range) continue;
        const la = Sonar.litAt(pu, p.x, p.y);
        if (!(la > tPrev && la <= t)) continue;
        const dist = (la - pu.t0) * pu.speed;
        if (dist > pu.range) continue;
        if (str < 0.12 && dist > 6) continue;
        if (!Sonar.visibleFrom(pu, p.x, p.y)) continue;
        // Mouth beam (v0.11): pings are dimmer off the facing axis; other sounds have no beam (factor 1).
        const strength = Math.min(1, (1 - 0.5 * dist / pu.range) * str * Sonar.beamAt(pu, Math.atan2(ey, ex)));
        // Bounce children and overlapping sounds: keep only the stronger snapshot of the same moment.
        let dup = -1;
        for (let m = es.length - 1; m >= 0; m--) {
          if (es[m].personId === p.id && Math.abs(es[m].t - la) < 0.5) { dup = m; break; }
        }
        if (dup >= 0 && es[dup].strength >= strength) continue;
        heightBandOf(Sonar, pu, p.x, p.y, band);
        const efade = typeof pu.fade === 'number' && pu.fade > 0 ? pu.fade : (sonar && sonar.fade) || 3;
        if (dup >= 0) {
          // Same moment, two sounds: the snapshot shows the union of what both lit.
          const old = es[dup];
          band[0] = Math.min(band[0], old.zMin);
          band[1] = Math.max(band[1], old.zMax);
        }
        const echo = {
          personId: p.id, x: p.x, y: p.y, angle: p.angle, lookAngle: p.lookAngle, phase: p.phase,
          moving: p.state === 'walk', t: la, dist: dist, strength: strength, pan: 0, look: p.look,
          theta: typeof pu.facing === 'number' ? Math.atan2(ey, ex) - pu.facing : 0, // off the mouth axis, for the audio level
          zMin: band[0], zMax: band[1], fade: efade,
          // Pose state for the renderer (snapshot of the moment the wavefront passed).
          mode: p.mode, sit: !!(p.sit || p.seated), wary: p.wary > 0, modeAge: p.modeAge || 0, phaseRate: p.phaseRate || 0
        };
        if (dup >= 0) es.splice(dup, 1);
        es.push(echo);
        made.push(echo);
      }
    }
    const fade = sonar && typeof sonar.fade === 'number' ? sonar.fade : 3;
    let w = 0;
    for (let i = 0; i < es.length; i++) if (t - es[i].t < (es[i].fade || fade)) es[w++] = es[i];
    es.length = w;
    while (es.length > state.maxEchoes) es.shift();
    return made;
  }

  /**
   * Fill out with {x, y, id, gait: sneak|walk|run, pace} for each foot plant since the last call (two per walk cycle, none while idle).
   * Objects are reused between calls; out.length is set to the count, which is returned.
   */
  function stepEvents(people, tPrev, t, out) {
    const ps = people && people.people ? people.people : [];
    if (!out.pool) out.pool = [];
    const pool = out.pool;
    let n = 0;
    for (let i = 0; i < ps.length; i++) {
      const p = ps[i];
      const todo = Math.min(4, p.steps - p.stepsReported);
      p.stepsReported = p.steps;
      for (let k = 0; k < todo; k++) {
        let e = pool[n];
        if (!e) { e = { x: 0, y: 0, id: 0, gait: 'walk', pace: 1, angle: 0, side: 1 }; pool[n] = e; }
        e.x = p.x; e.y = p.y; e.id = p.id;
        e.angle = p.angle;
        e.side = ((p.steps - todo + k) & 1) ? 1 : -1; // feet alternate left/right
        e.gait = p.mode === 'flee' ? 'run' : p.wary > 0 ? 'sneak' : 'walk';
        e.pace = p.speed / DEFAULT_SPEED;
        out[n] = e;
        n++;
      }
    }
    out.length = n;
    return n;
  }

  /** Brightness 0..1 of an echo snapshot at time t. */
  function echoBrightness(echo, t, fade) {
    if (echo.fade > 0) fade = echo.fade;
    const age = t - echo.t;
    if (age < 0 || age >= fade) return 0;
    // Gentler than wall fade so a trail of snapshots stays readable.
    return Math.pow(1 - age / fade, 1.4) * echo.strength;
  }

  /** Seconds since the echo was taken. */
  function echoAge(echo, t) {
    return t - echo.t;
  }

  /** Compact state for debugState(). */
  function schedInfo(state, p) {
    const s = p.sched;
    if (!s) return null;
    const cur = s.stops[s.si];
    const nx = s.stops[Math.min(s.stops.length - 1, Math.max(0, s.si) + 1)];
    return { role: s.role, stop: cur ? cur.place : null, act: cur ? cur.act : null, next: nx ? nx.place : null, walking: !!s.en, eta: sched().eta(s.stops, Math.max(0, s.si), state.nightFrac, state.nightSec) };
  }

  function snapshot(state) {
    const out = [];
    const ps = state && state.people ? state.people : [];
    for (let i = 0; i < ps.length; i++) {
      const p = ps[i];
      out.push({ id: p.id, x: p.x, y: p.y, state: p.state, angle: p.angle, mode: p.mode, pool: p.pool, left: p.left, wary: p.wary > 0, waryLeft: p.wary > 0 ? p.wary : 0, sched: schedInfo(state, p) });
    }
    return out;
  }

  const People = {
    create: create, update: update, updateEchoes: updateEchoes, stepEvents: stepEvents, makeLook: makeLook,
    echoBrightness: echoBrightness, ACCESSORIES: ACCESSORIES, heightBandOf: heightBandOf, echoAge: echoAge, snapshot: snapshot,
    sees: sees, react: react, drainEvents: drainEvents, clearEchoes: clearEchoes, isFeedable: isFeedable,
    feedTarget: feedTarget, markFed: markFed, grab: grab, release: release, drink: drink
  };
  VCS.People = People;
  if (typeof module !== 'undefined' && module.exports) module.exports = People;
})(typeof window !== 'undefined' ? window : globalThis);
