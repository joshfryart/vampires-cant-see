(function (root) {
  'use strict';
  const VCS = (root.VCS = root.VCS || {});

  // W2 listening at windows: pure logic (no DOM, no audio context). game.js feeds it the world, player and people.
  const REACH = 1.2; // cells from the window centre
  const FACE = 0.9; // max angle off the window (rad)
  const START_SPEED = 1.0; // cells/s to begin listening
  const STOP_SPEED = 1.8; // cells/s to break it off
  const MOVE_K = 0.5; // walking speed multiplier while listening
  const MAX_SPEAKERS = 2;
  const LP_GLASS = 1200;
  const LP_DARK = 600;
  const SUB_DIST = 1.2; // cells: words are readable only this close to the window...
  const SUB_LIT = 0.15; // ...and when the window is lit (open glass, not dark and muffled)
  const SUB_FADE = 0.6; // seconds a subtitle takes to fade after its line ends
  const MUFFLED = '(muffled talking)';

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

  /**
   * The window the player could listen at: {cx, cy, x, y, dist, zone, lit} or null.
   * Needs the player outdoors, within reach of a 'w' tile, facing it, with an indoor cell behind it.
   */
  function findWindow(world, p, reach) {
    try {
      if (!world || !p || typeof world.tileAt !== 'function' || typeof world.kindAt !== 'function') return null;
      if (world.kindAt(p.x, p.y) !== 'outdoor') return null;
      reach = num(reach, REACH);
      const px = Math.floor(p.x);
      const py = Math.floor(p.y);
      const r = Math.ceil(reach);
      let best = null;
      for (let cy = py - r; cy <= py + r; cy++) {
        for (let cx = px - r; cx <= px + r; cx++) {
          if (world.tileAt(cx, cy) !== 'w') continue;
          const wx = cx + 0.5;
          const wy = cy + 0.5;
          const dx = wx - p.x;
          const dy = wy - p.y;
          const d = Math.hypot(dx, dy);
          if (d > reach || (best && d >= best.dist)) continue;
          let da = Math.atan2(dy, dx) - num(p.angle, 0);
          da = Math.atan2(Math.sin(da), Math.cos(da));
          if (Math.abs(da) > FACE && d > 0.6) continue;
          // The inside is the side opposite the player along the dominant axis.
          const sx = Math.abs(dx) >= Math.abs(dy) ? (dx >= 0 ? 1 : -1) : 0;
          const sy = sx === 0 ? (dy >= 0 ? 1 : -1) : 0;
          const ix = wx + sx;
          const iy = wy + sy;
          if (world.kindAt(ix, iy) !== 'indoor') continue;
          const zone = typeof world.zoneAt === 'function' ? world.zoneAt(ix, iy) : null;
          const lit = typeof world.lightAt === 'function' ? Math.max(world.lightAt(wx, wy), world.lightAt(ix, iy)) : 0;
          best = { cx: cx, cy: cy, x: wx, y: wy, ix: ix, iy: iy, dist: d, zone: zone, lit: lit };
        }
      }
      return best;
    } catch (e) { return null; }
  }

  /** Is there a lit window within `reach` (no facing needed)? Used for the first-time hint. */
  function nearLitWindow(world, p, reach) {
    try {
      if (!world || !p || world.kindAt(p.x, p.y) !== 'outdoor') return false;
      reach = num(reach, 2.5);
      const r = Math.ceil(reach);
      for (let cy = Math.floor(p.y) - r; cy <= Math.floor(p.y) + r; cy++) {
        for (let cx = Math.floor(p.x) - r; cx <= Math.floor(p.x) + r; cx++) {
          if (world.tileAt(cx, cy) !== 'w') continue;
          if (Math.hypot(cx + 0.5 - p.x, cy + 0.5 - p.y) > reach) continue;
          if (world.lightAt(cx + 0.5, cy + 0.5) > 0.15) return true;
        }
      }
    } catch (e) { /* ignore */ }
    return false;
  }

  /** People inside the zone behind the window and not busy fleeing: [{id, x, y, noticed}]. */
  function insiders(world, people, win) {
    const out = [];
    try {
      if (!win || !people) return out;
      for (let i = 0; i < people.length; i++) {
        const q = people[i];
        if (!q || q.mode === 'fed' || q.mode === 'grapple') continue;
        if (world.kindAt(q.x, q.y) !== 'indoor') continue;
        if (win.zone && world.zoneAt(q.x, q.y) !== win.zone) continue;
        const noticed = q.mode === 'startle' || q.mode === 'flee' || q.mode === 'cower' || q.mode === 'dazed' || num(q.wary, 0) > 0 || q.wary === true;
        out.push({ id: q.id, x: q.x, y: q.y, noticed: noticed, role: q.role || (q.sched && q.sched.role) });
      }
    } catch (e) { /* ignore */ }
    return out;
  }

  /** Can the words be made out? Pure: distance to the window (cells) and its light level. */
  function subtitleClear(dist, lit) {
    return num(dist, Infinity) <= SUB_DIST && num(lit, 0) > SUB_LIT;
  }

  /** The subtitle for a line (same seed/kind/mood as the speech): {de, en} or the muffled marker with empty en. */
  function subtitleFor(seed, kind, mood, dist, lit) {
    const VD = root.VCS && root.VCS.VoiceData;
    if (!subtitleClear(dist, lit) || !VD || typeof VD.subtitle !== 'function') return { de: MUFFLED, en: '', muffled: true };
    const t = VD.subtitle(seed, kind, mood);
    return { de: t.de, en: t.en, muffled: false };
  }

  /** Opacity 0..1 of a subtitle at time `now`: full while the line runs, then a short fade. */
  function subAlpha(sub, now) {
    if (!sub) return 0;
    const over = num(now, 0) - num(sub.end, 0);
    if (over <= 0) return 1;
    return Math.max(0, 1 - over / SUB_FADE);
  }

  function moodFor(fear) {
    fear = num(fear, 0);
    return fear >= 8 ? 'whisper' : fear >= 4 ? 'worried' : 'calm';
  }

  const KINDS_CALM = ['chat', 'chat', 'question', 'laugh', 'greet'];
  const KINDS_WORRIED = ['murmur', 'question', 'chat'];
  const KINDS_WHISPER = ['murmur', 'murmur', 'chat'];
  const KINDS_WARM = ['chat', 'laugh', 'question', 'chat'];
  const KINDS_NEUTRAL = ['chat', 'question', 'chat'];
  const KINDS_CURT = ['argue', 'chat', 'argue'];
  const KINDS_HUSHED = ['murmur', 'chat', 'question'];

  /** Speech kinds for a line: from the real conversation (People.conversationFor) while calm, else by the fear mood. */
  function conversationKinds(conv, mood) {
    if (mood === 'worried') return KINDS_WORRIED;
    if (mood === 'whisper') return KINDS_WHISPER;
    if (!conv) return KINDS_CALM;
    return conv.mood === 'warm' ? KINDS_WARM : conv.mood === 'curt' ? KINDS_CURT : conv.mood === 'hushed' ? KINDS_HUSHED : KINDS_NEUTRAL;
  }

  function create() {
    return { active: false, win: null, count: 0, silent: false, mood: 'calm', turn: 0, nextAt: 0, speaker: -1, cur: null, sub: null, lpHz: LP_GLASS };
  }

  function stopCur(st) {
    try { if (st.cur && typeof st.cur.stop === 'function') st.cur.stop(); } catch (e) { /* ignore */ }
    st.cur = null;
    st.sub = null;
  }

  /**
   * One tick. ctx: {now, held (E down), holding (victim), speed, world, player, people, fear,
   * speak(opts)->handle|null, speakLength(seed,kind,mood)->s, voiceFor(person,seed), pan(x,y), onChange(active, info)}.
   * Returns st (read st.active, st.count, st.silent, st.lpHz).
   */
  function step(st, ctx) {
    try {
      const wasActive = st.active;
      const speed = num(ctx.speed, 0);
      let win = null;
      if (ctx.held && !ctx.holding) {
        win = findWindow(ctx.world, ctx.player, REACH);
        if (win && !wasActive && speed > START_SPEED) win = null;
        if (win && wasActive && speed > STOP_SPEED) win = null;
      }
      if (!win) {
        if (wasActive) {
          stopCur(st);
          st.active = false;
          st.win = null;
          st.count = 0;
          if (ctx.onChange) ctx.onChange(false, null);
        }
        return st;
      }
      const same = !!st.win && st.win.cx === win.cx && st.win.cy === win.cy;
      st.win = win;
      st.active = true;
      const ins = insiders(ctx.world, ctx.people, win);
      st.count = ins.length;
      st.silent = ins.some(function (q) { return q.noticed; });
      st.mood = moodFor(ctx.fear);
      st.lpHz = win.lit > 0.15 ? LP_GLASS : LP_DARK;
      const now = num(ctx.now, 0);
      if (!wasActive || !same) {
        st.nextAt = now + 0.6;
        st.turn = 0;
        st.speaker = -1;
        if (ctx.onChange) ctx.onChange(true, { count: ins.length, zone: win.zone, lit: win.lit });
      }
      if (st.sub && now > st.sub.end + SUB_FADE) st.sub = null;
      if (st.silent || !ins.length) { stopCur(st); return st; }
      if (now < st.nextAt || typeof ctx.speak !== 'function') return st;
      ins.sort(function (a, b) { return Math.hypot(a.x - win.x, a.y - win.y) - Math.hypot(b.x - win.x, b.y - win.y); });
      // V2: when the nearest villager is in a conversation, the overheard pair is them and their partner.
      const convOf = typeof ctx.conversationFor === 'function' ? ctx.conversationFor : null;
      let conv = convOf ? convOf(ins[0].id) : null;
      let pool = ins.slice(0, MAX_SPEAKERS);
      if (conv) {
        let mate = null;
        for (let i = 1; i < ins.length; i++) if (ins[i].id === conv.partner) { mate = ins[i]; break; }
        if (mate) pool = [ins[0], mate];
        else conv = null;
      }
      st.speaker = pool.length > 1 ? (st.speaker + 1) % pool.length : 0;
      const who = pool[st.speaker];
      const seed = hash(idNum(who.id), st.turn);
      const kinds = conversationKinds(conv, st.mood);
      const kind = conv && conv.kind === 'hello' ? 'greet' : st.turn === 0 && pool.length > 1 && !conv ? 'greet' : kinds[seed % kinds.length];
      const d = Math.hypot(who.x - win.x, who.y - win.y) + win.dist;
      const gain = Math.max(0.15, Math.min(1, 1 / (1 + d * 0.18)));
      const mood = st.mood;
      stopCur(st);
      const voice = ctx.voiceFor ? ctx.voiceFor(who, seed) : undefined;
      st.cur = ctx.speak({ voice: voice, seed: seed, kind: kind, mood: mood, pan: ctx.pan ? ctx.pan(win.x, win.y) : 0, lpHz: st.lpHz, gain: gain }) || null;
      let len = 1.2;
      if (st.cur && num(st.cur.end, 0) > 0) len = st.cur.end;
      else if (typeof ctx.speakLength === 'function') len = num(ctx.speakLength(seed, kind, mood, voice), 1.2);
      const two = pool.length > 1;
      const pause = (two ? 0.35 : 1.6) + ((hash(seed, 99) % 100) / 100) * (two ? 0.9 : 2.4);
      const sub = subtitleFor(seed, kind, mood, win.dist, win.lit);
      sub.speaker = who.id;
      sub.kind = kind;
      sub.mood = mood;
      sub.start = now;
      sub.end = now + Math.max(0.3, len);
      st.sub = sub;
      st.subId = (st.subId || 0) + 1;
      if (typeof ctx.onSubtitle === 'function') ctx.onSubtitle(sub, who);
      st.nextAt = now + Math.max(0.3, len) + pause;
      st.turn++;
    } catch (e) { /* never throw */ }
    return st;
  }

  const Listen = { REACH: REACH, MOVE_K: MOVE_K, MAX_SPEAKERS: MAX_SPEAKERS, SUB_DIST: SUB_DIST, SUB_FADE: SUB_FADE, MUFFLED: MUFFLED, subtitleClear: subtitleClear, subtitleFor: subtitleFor, subAlpha: subAlpha, conversationKinds: conversationKinds, findWindow: findWindow, nearLitWindow: nearLitWindow, insiders: insiders, moodFor: moodFor, create: create, step: step, stop: stopCur };
  VCS.Listen = Listen;
  if (typeof module !== 'undefined' && module.exports) module.exports = Listen;
})(typeof window !== 'undefined' ? window : globalThis);
