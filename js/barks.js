(function (root) {
  'use strict';
  const VCS = (root.VCS = root.VCS || {});

  // Villager barks: pure decision logic (no DOM, no audio, no wall-clock or unseeded randomness). Given the people, the player and sim time it says
  // who speaks what. game.js plays it (distance gain, pan, occlusion, subtitles). Deterministic from the seed and sim time.
  const RANGE = 16; // cells: nobody farther than this barks at all
  const DAY_RANGE = 12; // cells: calm daytalk / humming only this close to the player
  const MAX_STARTS = 2; // barks starting per second
  const MAX_ACTIVE = 3; // speakers heard at once
  const PENDING_TTL = 2; // seconds an event bark waits for a free slot before it is dropped
  const RELIEF_TTL = 8; // a sigh of relief may wait longer for the cooldown
  const WHISPER_FEAR = 8;
  const WORRIED_FEAR = 4;
  const ALARM_JUMP = 2; // village-fear rise within ALARM_WINDOW that makes a nearby villager cry out
  const ALARM_WINDOW = 4;
  const BODY_SEEN = 5; // cells: a calm villager this close to a drained body raises the alarm
  // Per-villager cooldown (s) after a bark of that kind: [min, max]; struggle cries come a little faster while grabbed.
  const COOLDOWNS = {
    notice: [8, 12], startle: [6, 9], flee: [6, 10], cower: [8, 12], struggle: [4, 6], relief: [10, 15],
    alarm: [8, 12], daytalk: [9, 15], chat: [6, 10], hum: [12, 15]
  };
  const PRIO = { alarm: 100, startle: 98, flee: 96, struggle: 94, notice: 92, cower: 90, relief: 60, daytalk: 20, hum: 10 };
  const FEAR_KIND = { alarm: 1, startle: 1, flee: 1, struggle: 1, notice: 1, cower: 1 };
  const GAIN = { alarm: 1, startle: 0.95, flee: 1, struggle: 0.7, notice: 0.9, cower: 0.6, relief: 0.6, daytalk: 0.65, hum: 0.4 };
  const EST_LEN = 1.5; // seconds assumed for a line when no length function is supplied

  function num(v, d) { return typeof v === 'number' && isFinite(v) ? v : d; }
  function hash(a, b) {
    let h = (Math.imul(a | 0, 374761393) + Math.imul(b | 0, 668265263)) | 0;
    h = Math.imul(h ^ (h >>> 13), 1274126177);
    return (h ^ (h >>> 16)) >>> 0;
  }
  function idNum(id) {
    if (typeof id === 'number' && isFinite(id)) return id | 0;
    const s = String(id);
    let h = 7;
    for (let i = 0; i < s.length; i++) h = (Math.imul(h, 31) + s.charCodeAt(i)) | 0;
    return h;
  }
  /** Seeded unit float from three integers. */
  function unit(a, b, c) { return hash(hash(a, b), c) / 4294967296; }
  function VD() { return root.VCS && root.VCS.VoiceData; }

  /** A villager's role (raw person or snapshot). */
  function roleOf(p) { return (p && (p.role || (p.sched && p.sched.role))) || ''; }

  function create(seed) {
    return { seed: idNum(seed === undefined ? 1 : seed), v: Object.create(null), active: [], starts: [], pair: Object.create(null), lastFear: 0, fearAt: 0, init: false, bodies: Object.create(null), total: 0, recent: 0 };
  }

  /** Forget everything (map change, state change, setting toggled): next step re-baselines without barking. */
  function reset(st) {
    st.v = Object.create(null);
    st.active = [];
    st.starts = [];
    st.pair = Object.create(null);
    st.bodies = Object.create(null);
    st.init = false;
    st.lastFear = 0;
    st.fearAt = 0;
    return st;
  }

  function isWary(p) { return p.wary === true || num(p.wary, 0) > 0; }
  function silent(p) { return p.mode === 'fed' || p.mode === 'dazed' || p.dead === true || p.drained === true; }
  function calm(p) { return p.mode === 'path' && !isWary(p) && !p.bumping; }
  function toneFor(kind, fear) {
    if (FEAR_KIND[kind]) return kind === 'cower' && fear >= WHISPER_FEAR ? 'whisper' : fear >= WORRIED_FEAR ? 'worried' : 'calm';
    return fear >= WHISPER_FEAR ? 'whisper' : fear >= WORRIED_FEAR ? 'worried' : 'calm';
  }
  /** Audio mood (VoiceData.MOODS key) for a kind and tone: shouts are loud, whispers hushed. */
  function moodFor(kind, tone) {
    if (tone === 'whisper') return 'whisper';
    if (kind === 'alarm' || kind === 'flee' || kind === 'startle' || kind === 'notice') return 'argue';
    if (kind === 'struggle' || kind === 'cower') return 'worried';
    return tone === 'worried' ? 'worried' : 'calm';
  }

  function cooldown(st, v, kind, n) {
    const r = COOLDOWNS[kind] || COOLDOWNS.daytalk;
    return r[0] + (r[1] - r[0]) * unit(st.seed, v.key, n * 7 + 3);
  }

  /** Subtitle {de, en} for a bark (same seed / kind / tone / role as the speech). */
  function subtitleFor(b) {
    const d = VD();
    if (!b || !d || typeof d.subtitle !== 'function') return { de: '', en: '' };
    return d.subtitle(b.seed, b.kind, b.tone, b.role);
  }

  /**
   * One tick. ctx: {now (sim s), player {x,y}, people [raw or snapshot], fear (village fear), enabled (default true),
   * lengthFn(seed, kind, mood, role)->s (optional)}.
   * Returns {barks: [{id, x, y, dist, kind, seed, tone, mood, gain, loud, role, voiceSeed}], stop: [ids that fell silent]}.
   * Never throws.
   */
  function step(st, ctx) {
    const res = { barks: [], stop: [] };
    try {
      const now = num(ctx.now, 0);
      const people = Array.isArray(ctx.people) ? ctx.people : [];
      const pl = ctx.player || { x: 0, y: 0 };
      const fear = num(ctx.fear, 0);
      const enabled = ctx.enabled !== false;
      const first = !st.init;
      st.init = true;
      // prune finished speakers and old start stamps
      st.active = st.active.filter(function (a) { return a.end > now; });
      st.starts = st.starts.filter(function (t) { return t > now - 1; });
      if (now < st.lastNow) { st.active = []; st.starts = []; }
      st.lastNow = now;

      // fear spike
      let spike = false;
      if (fear - st.lastFear >= ALARM_JUMP && now - st.fearAt > ALARM_WINDOW) { spike = true; st.fearAt = now; }
      st.lastFear = fear;

      const byId = Object.create(null);
      for (let i = 0; i < people.length; i++) if (people[i] && people[i].id !== undefined) byId[people[i].id] = people[i];
      const seen = Object.create(null);
      const cands = [];

      for (let i = 0; i < people.length; i++) {
        const p = people[i];
        if (!p || p.id === undefined) continue;
        seen[p.id] = true;
        let v = st.v[p.id];
        const fresh = !v;
        if (fresh) {
          v = st.v[p.id] = { key: idNum(p.id), mode: p.mode, wary: isWary(p), nextAt: 0, lastKind: '', lastDe: '', n: 0, pend: null, pendUntil: 0, aloneAt: now + 4 + 20 * unit(st.seed, idNum(p.id), 1) };
        }
        const prevMode = v.mode;
        const prevWary = v.wary;
        v.mode = p.mode;
        v.wary = isWary(p);
        if (silent(p)) {
          v.pend = null;
          if (st.active.some(function (a) { return a.id === p.id; })) {
            res.stop.push(p.id);
            st.active = st.active.filter(function (a) { return a.id !== p.id; });
          }
          continue;
        }
        if (first || fresh || !enabled) { v.pend = null; continue; }
        const dist = Math.hypot(num(p.x, 0) - num(pl.x, 0), num(p.y, 0) - num(pl.y, 0));
        // --- event triggers (state transitions)
        let ev = null;
        // people.js: a bump freeze is 'startle' with bumping (touched: gasp); a plain 'startle' is a heard noise ("Wer da?").
        // wary only rises together with flee -> path (relief), so the noise startle is the real notice moment.
        if (p.mode === 'startle' && prevMode !== 'startle') ev = p.bumping ? 'startle' : 'notice';
        else if (p.mode === 'flee' && prevMode !== 'flee') ev = 'flee';
        else if (p.mode === 'cower' && prevMode !== 'cower') ev = 'cower';
        else if (p.mode === 'grapple' && prevMode !== 'grapple') ev = 'struggle';
        else if (p.mode === 'path' && (prevMode === 'flee' || prevMode === 'cower' || prevMode === 'startle' || prevMode === 'grapple')) ev = 'relief';
        else if (p.mode === 'path' && v.wary && !prevWary && prevMode === 'path') ev = 'notice';
        if (ev) { v.pend = ev; v.pendUntil = now + (ev === 'relief' ? RELIEF_TTL : PENDING_TTL); }
        // fear spike or a drained body in sight of a calm villager
        if (!v.pend && calm(p) && dist <= RANGE) {
          if (spike && dist <= DAY_RANGE) { v.pend = 'alarm'; v.pendUntil = now + PENDING_TTL; }
          else {
            for (let j = 0; j < people.length; j++) {
              const q = people[j];
              if (!q || q.mode !== 'fed') continue;
              const k = p.id + ':' + q.id;
              if (st.bodies[k]) continue;
              if (Math.hypot(num(q.x, 0) - num(p.x, 0), num(q.y, 0) - num(p.y, 0)) <= BODY_SEEN) {
                st.bodies[k] = true;
                v.pend = 'alarm';
                v.pendUntil = now + PENDING_TTL;
                break;
              }
            }
          }
        }
        // periodic cries while the mode lasts
        if (!v.pend && now >= v.nextAt && dist <= RANGE) {
          if (p.mode === 'grapple') v.pend = 'struggle';
          else if (p.mode === 'flee' && unit(st.seed, v.key, v.n + 11) < 0.7) v.pend = 'flee';
          else if (p.mode === 'cower') v.pend = 'cower';
          if (v.pend) v.pendUntil = now + PENDING_TTL;
        }
        if (v.pend && now > v.pendUntil) v.pend = null;
        if (v.pend && dist <= RANGE) {
          const lastCalm = v.lastKind === 'daytalk' || v.lastKind === 'hum' || v.lastKind === '';
          if (now >= v.nextAt || (FEAR_KIND[v.pend] && lastCalm)) {
            cands.push({ p: p, v: v, kind: v.pend, dist: dist, prio: PRIO[v.pend] - dist * 0.5, chatKind: null });
          }
          continue;
        }
        // --- calm daytalk / mumbling near the player
        if (!calm(p) || dist > DAY_RANGE || now < v.nextAt) continue;
        const partner = p.chat && p.chat.partner !== undefined ? byId[p.chat.partner] : null;
        if (partner && !silent(partner) && partner.chat && partner.chat.partner === p.id) {
          // turn-taking: the partner must have spoken last (or nobody yet and I have the lower id), and not be speaking now
          const pk = p.id < partner.id ? p.id + '|' + partner.id : partner.id + '|' + p.id;
          const pr = st.pair[pk];
          const mine = pr ? pr.last !== p.id && now >= pr.end + 0.4 : idNum(p.id) <= idNum(partner.id);
          if (mine && !st.active.some(function (a) { return a.id === partner.id; })) {
            cands.push({ p: p, v: v, kind: 'daytalk', dist: dist, prio: PRIO.daytalk - dist * 0.5, chatKind: pk });
          }
        } else if (!p.chat && now >= v.aloneAt) {
          const roll = unit(st.seed, v.key, v.n * 13 + 5);
          cands.push({ p: p, v: v, kind: roll < 0.4 ? 'hum' : 'daytalk', dist: dist, prio: PRIO.daytalk - dist * 0.5 - 5, chatKind: null, alone: true });
        }
      }

      // drop state of people who left
      for (const k in st.v) if (!seen[k]) delete st.v[k];

      // --- pick: fear first, nearest first; caps
      cands.sort(function (a, b) { return b.prio - a.prio || idNum(a.p.id) - idNum(b.p.id); });
      for (let i = 0; i < cands.length; i++) {
        if (st.starts.length >= MAX_STARTS || st.active.length >= MAX_ACTIVE) break;
        const c = cands[i];
        if (st.active.some(function (a) { return a.id === c.p.id; })) continue;
        const v = c.v;
        const role = roleOf(c.p);
        const tone0 = toneFor(c.kind, fear);
        // choose a line that is not the one this villager said last (try seeds; stay quiet if none differs)
        let seed = 0;
        const tone = tone0;
        let sub = null;
        const d = VD();
        for (let t = 0; t < 12 && d; t++) {
          seed = hash(v.key ^ st.seed, v.n * 16 + t + 1);
          const s = d.subtitle(seed, c.kind, tone, role);
          if (s.de !== v.lastDe) { sub = s; break; }
        }
        if (d && !sub) { // cannot vary: stay quiet this time
          v.pend = null;
          v.n++;
          v.nextAt = now + 2;
          continue;
        }
        const mood = moodFor(c.kind, tone);
        const len = typeof ctx.lengthFn === 'function' ? num(ctx.lengthFn(seed, c.kind, mood, role), EST_LEN) : EST_LEN;
        const cdKind = c.kind === 'daytalk' && c.chatKind ? 'chat' : c.kind;
        v.n++;
        v.lastKind = c.kind;
        v.lastDe = sub ? sub.de : '';
        v.pend = null;
        v.nextAt = now + Math.max(0.3, len) + cooldown(st, v, cdKind, v.n);
        if (c.alone) v.aloneAt = now + 20 + 25 * unit(st.seed, v.key, v.n * 3 + 9);
        if (c.chatKind) st.pair[c.chatKind] = { last: c.p.id, end: now + Math.max(0.3, len) };
        st.starts.push(now);
        st.active.push({ id: c.p.id, end: now + Math.max(0.3, len) });
        st.total++;
        st.recent++;
        res.barks.push({
          id: c.p.id, x: num(c.p.x, 0), y: num(c.p.y, 0), dist: c.dist, kind: c.kind, seed: seed, tone: tone, mood: mood,
          gain: GAIN[c.kind] || 0.6, loud: !!FEAR_KIND[c.kind], role: role, voiceSeed: v.key, len: len
        });
      }
    } catch (e) { /* never throw */ }
    return res;
  }

  const Barks = {
    RANGE: RANGE, DAY_RANGE: DAY_RANGE, MAX_STARTS: MAX_STARTS, MAX_ACTIVE: MAX_ACTIVE, COOLDOWNS: COOLDOWNS, PRIO: PRIO,
    create: create, reset: reset, step: step, subtitleFor: subtitleFor, roleOf: roleOf, toneFor: toneFor, moodFor: moodFor
  };
  VCS.Barks = Barks;
  if (typeof module !== 'undefined' && module.exports) module.exports = Barks;
})(typeof window !== 'undefined' ? window : globalThis);
