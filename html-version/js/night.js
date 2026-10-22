(function (root) {
  'use strict';
  const VCS = (root.VCS = root.VCS || {});

  const NIGHT_MIN = 600; // 20:00 -> 06:00
  const CHIME_MIN = 540;
  const WASH_MIN = 570;
  const WASH_SPAN = 30;
  const DAWN_SPAN = 60;
  const WEAK_BELOW = 25;
  const STATUSES = ['night', 'day', 'won', 'lost'];
  const ST_KEYS = ['v', 'night', 'min', 'blood', 'status', 'reason', 'fired', 'fedCount'];
  const FIRED_KEYS = ['chime', 'washout', 'dawn'];
  const MAX_FED = 1000000;
  const MAX_REASON = 32;

  const DEFAULTS = Object.freeze({ nightSec: 480, nights: 5, bloodMax: 100, bloodStart: 60, feedGain: 40 });

  function logger() {
    try {
      return root.VCS && root.VCS.Log ? root.VCS.Log.get('night') : null;
    } catch (e) {
      return null;
    }
  }
  function warn(msg, data) {
    try {
      const l = logger();
      if (l && typeof l.warn === 'function') l.warn(msg, data);
    } catch (e) { /* ignore */ }
  }

  function isNum(x) { return typeof x === 'number' && isFinite(x); }
  function clamp01(x) { return x < 0 ? 0 : x > 1 ? 1 : x; }
  function hasOwn(o, k) { return Object.prototype.hasOwnProperty.call(o, k); }
  function active(st) { return !!st && typeof st === 'object' && (st.status === 'night' || st.status === 'day'); }

  /** Create night state. Bad option values fall back to defaults (warn). */
  function create(opts) {
    const o = opts && typeof opts === 'object' ? opts : {};
    const out = {};
    for (const k in DEFAULTS) {
      let v = hasOwn(o, k) ? o[k] : undefined;
      if (v === undefined) { out[k] = DEFAULTS[k]; continue; }
      let ok = isNum(v) && v > 0;
      if (ok && k === 'nights') { ok = v === Math.floor(v) && v <= 1000; }
      if (ok && k === 'bloodStart') { ok = true; }
      if (ok && k === 'nightSec') { ok = v <= 86400; }
      if (!ok && k === 'bloodStart' && isNum(v) && v === 0) ok = true;
      if (!ok) { warn('bad option, using default', { key: k }); v = DEFAULTS[k]; }
      out[k] = v;
    }
    if (out.bloodStart > out.bloodMax) {
      warn('bloodStart above bloodMax, clamped', { bloodStart: out.bloodStart });
      out.bloodStart = out.bloodMax;
    }
    let drainMul = 1;
    if (hasOwn(o, 'drainMul') && o.drainMul !== undefined) {
      if (isNum(o.drainMul) && o.drainMul > 0) drainMul = o.drainMul;
      else warn('bad option, using default', { key: 'drainMul' });
    }
    let ramp = 0;
    if (hasOwn(o, 'ramp') && o.ramp !== undefined) {
      if (isNum(o.ramp) && o.ramp >= 0) ramp = o.ramp;
      else warn('bad option, using default', { key: 'ramp' });
    }
    return {
      drainMul: drainMul,
      ramp: ramp,
      night: 1,
      nights: out.nights,
      nightSec: out.nightSec,
      min: 0,
      blood: out.bloodStart,
      bloodMax: out.bloodMax,
      feedGain: out.feedGain,
      status: 'night',
      reason: '',
      fired: { chime: false, washout: false, dawn: false },
      fedCount: 0
    };
  }

  /** Advance the night. Returns events fired this call. */
  function update(st, dt, ctx) {
    const events = [];
    try {
      if (!active(st)) return events;
      let d = isNum(dt) ? dt : 0;
      d = d < 0 ? 0 : d > 0.1 ? 0.1 : d;
      const outdoor = !!(ctx && typeof ctx === 'object' && ctx.outdoor === true);
      st.min = Math.min(NIGHT_MIN, st.min + (d * NIGHT_MIN) / st.nightSec);
      st.blood = Math.max(0, st.blood - (d * st.bloodMax) / st.nightSec * (isNum(st.drainMul) ? st.drainMul : 1) * (1 + (isNum(st.ramp) ? st.ramp : 0) * ((isNum(st.night) ? st.night : 1) - 1)));
      if (st.min >= CHIME_MIN && !st.fired.chime) { st.fired.chime = true; events.push('chime'); }
      if (st.min >= WASH_MIN && !st.fired.washout) { st.fired.washout = true; events.push('washout'); }
      if (st.min >= NIGHT_MIN && !st.fired.dawn) {
        st.fired.dawn = true;
        st.status = 'day';
        events.push('dawn');
      }
      if (st.status === 'day' && outdoor) {
        st.status = 'lost';
        st.reason = 'sun';
        events.push('lost');
      }
    } catch (e) {
      warn('update failed', { err: String(e && e.message) });
    }
    return events;
  }

  /** Feed: returns blood gained (0 if state not active). */
  function feed(st) {
    try {
      if (!active(st)) return 0;
      const before = st.blood;
      st.blood = Math.min(st.bloodMax, st.blood + st.feedGain);
      st.fedCount++;
      return st.blood - before;
    } catch (e) {
      warn('feed failed', { err: String(e && e.message) });
      return 0;
    }
  }

  /** Add blood (drinking). Returns the actual gain, clamped to bloodMax; 0 when inactive or amt is bad. */
  function addBlood(st, amt) {
    try {
      if (!active(st) || !isNum(amt) || amt <= 0) return 0;
      const before = st.blood;
      st.blood = Math.min(st.bloodMax, st.blood + amt);
      return st.blood - before;
    } catch (e) {
      warn('addBlood failed', { err: String(e && e.message) });
      return 0;
    }
  }

  /** Sleep: 'next' | 'won' | 'none'. */
  function sleep(st) {
    try {
      if (!active(st)) return 'none';
      if (st.night < st.nights) {
        st.night++;
        st.min = 0;
        st.fired = { chime: false, washout: false, dawn: false };
        st.status = 'night';
        st.reason = '';
        return 'next';
      }
      st.status = 'won';
      return 'won';
    } catch (e) {
      warn('sleep failed', { err: String(e && e.message) });
      return 'none';
    }
  }

  function pad2(n) { return (n < 10 ? '0' : '') + n; }

  function clock(st) {
    let m = st && isNum(st.min) ? st.min : 0;
    m = m < 0 ? 0 : m > NIGHT_MIN ? NIGHT_MIN : m;
    const total = (1200 + Math.floor(m)) % 1440;
    const hour = Math.floor(total / 60);
    const minute = total % 60;
    return { hour: hour, minute: minute, text: pad2(hour) + ':' + pad2(minute), frac: m / NIGHT_MIN };
  }

  function weakness(st) {
    if (!st || !isNum(st.blood)) return 0;
    return st.blood < WEAK_BELOW ? clamp01(1 - st.blood / WEAK_BELOW) : 0;
  }
  function washK(st) {
    if (!st || !isNum(st.min)) return 0;
    return clamp01((st.min - WASH_MIN) / WASH_SPAN);
  }
  function dawnK(st) {
    if (!st || !isNum(st.min)) return 0;
    return clamp01((st.min - CHIME_MIN) / DAWN_SPAN);
  }
  function isDay(st) { return !!st && st.status === 'day'; }

  /** Debug: jump to a clock time within 20:00..06:00. */
  function skipTo(st, hour, minute) {
    try {
      if (!active(st)) return false;
      if (!isNum(hour) || !isNum(minute) || hour !== Math.floor(hour) || minute !== Math.floor(minute)) return false;
      if (minute < 0 || minute > 59 || hour < 0 || hour > 23) return false;
      let m;
      if (hour >= 20) m = (hour - 20) * 60 + minute;
      else if (hour < 6) m = (hour + 4) * 60 + minute;
      else if (hour === 6 && minute === 0) m = NIGHT_MIN;
      else return false;
      st.min = m;
      if (m < CHIME_MIN) st.fired.chime = false;
      if (m < WASH_MIN) st.fired.washout = false;
      if (m < NIGHT_MIN) {
        st.fired.dawn = false;
        if (st.status === 'day') { st.status = 'night'; st.reason = ''; }
      }
      return true;
    } catch (e) {
      warn('skipTo failed', { err: String(e && e.message) });
      return false;
    }
  }

  function serialize(st) {
    if (!st || typeof st !== 'object') return null;
    const f = st.fired || {};
    return {
      v: 1,
      night: st.night,
      min: st.min,
      blood: st.blood,
      status: st.status,
      reason: st.reason,
      fired: { chime: !!f.chime, washout: !!f.washout, dawn: !!f.dawn },
      fedCount: st.fedCount
    };
  }

  function plain(o) {
    if (!o || typeof o !== 'object' || Array.isArray(o)) return false;
    const p = Object.getPrototypeOf(o);
    return p === Object.prototype || p === null;
  }

  /** Validate a serialized object; returns fresh state or null. Never throws. */
  function restore(obj, opts) {
    try {
      if (!plain(obj)) { warn('restore: not an object'); return null; }
      const keys = Object.keys(obj);
      for (let i = 0; i < keys.length; i++) {
        if (ST_KEYS.indexOf(keys[i]) < 0) { warn('restore: unknown key', { key: String(keys[i]).slice(0, 24) }); return null; }
      }
      const st = create(opts);
      if (obj.v !== 1) { warn('restore: bad version'); return null; }
      const n = obj.night;
      if (!isNum(n) || n !== Math.floor(n) || n < 1 || n > st.nights) { warn('restore: bad night'); return null; }
      if (!isNum(obj.min) || obj.min < 0 || obj.min > NIGHT_MIN) { warn('restore: bad min'); return null; }
      if (!isNum(obj.blood) || obj.blood < 0 || obj.blood > st.bloodMax) { warn('restore: bad blood'); return null; }
      if (typeof obj.status !== 'string' || STATUSES.indexOf(obj.status) < 0) { warn('restore: bad status'); return null; }
      if (typeof obj.reason !== 'string' || obj.reason.length > MAX_REASON) { warn('restore: bad reason'); return null; }
      if (!isNum(obj.fedCount) || obj.fedCount !== Math.floor(obj.fedCount) || obj.fedCount < 0 || obj.fedCount > MAX_FED) {
        warn('restore: bad fedCount'); return null;
      }
      const f = obj.fired;
      if (!plain(f)) { warn('restore: bad fired'); return null; }
      const fk = Object.keys(f);
      for (let i = 0; i < fk.length; i++) {
        if (FIRED_KEYS.indexOf(fk[i]) < 0) { warn('restore: unknown fired key'); return null; }
      }
      for (let i = 0; i < FIRED_KEYS.length; i++) {
        if (typeof f[FIRED_KEYS[i]] !== 'boolean') { warn('restore: bad fired flag'); return null; }
      }
      if (obj.status === 'day' && obj.min < NIGHT_MIN) { warn('restore: day before dawn'); return null; }
      st.night = n;
      st.min = obj.min;
      st.blood = obj.blood;
      st.status = obj.status;
      st.reason = obj.reason;
      st.fired = { chime: f.chime, washout: f.washout, dawn: f.dawn };
      st.fedCount = obj.fedCount;
      return st;
    } catch (e) {
      warn('restore failed', { err: String(e && e.message) });
      return null;
    }
  }

  const Night = {
    DEFAULTS: DEFAULTS,
    create: create,
    update: update,
    feed: feed,
    addBlood: addBlood,
    sleep: sleep,
    clock: clock,
    weakness: weakness,
    washK: washK,
    dawnK: dawnK,
    isDay: isDay,
    skipTo: skipTo,
    serialize: serialize,
    restore: restore
  };
  VCS.Night = Night;
  if (typeof module !== 'undefined' && module.exports) module.exports = Night;
})(typeof window !== 'undefined' ? window : globalThis);
