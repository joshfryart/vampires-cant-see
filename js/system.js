(function (root) {
  'use strict';
  const VCS = (root.VCS = root.VCS || {});

  let list = [];
  let subs = Object.create(null);

  function log(id) {
    return VCS.Log && VCS.Log.get ? VCS.Log.get(id || 'sys') : { warn() {}, error() {}, debug() {}, info() {} };
  }
  function fail(d, phase, e) {
    d.disabled = true;
    d.error = String(e && e.message ? e.message : e);
    log(d.id).error(phase + ' failed; system disabled: ' + d.error, e);
    emit('sys:tripped', { id: d.id, phase: phase });
  }
  function enabled(d) {
    if (d.disabled) return false;
    return true;
  }
  function call(d, phase, a, b) {
    if (typeof d[phase] !== 'function') return;
    try { d[phase](a, b); } catch (e) { fail(d, phase, e); }
  }
  function emit(ev, payload) {
    const arr = subs[ev];
    if (!arr) return 0;
    let n = 0;
    arr.slice().forEach(function (fn) {
      try { fn(payload); n++; } catch (e) { log('bus').error('handler for "' + ev + '" threw', e); }
    });
    return n;
  }

  const Sys = {
    /** def = { id, order?, init(ctx), update(dt,ctx), teardown(ctx) } */
    register: function (def) {
      if (!def || typeof def.id !== 'string' || !def.id || Object.prototype.hasOwnProperty.call(Object.prototype, def.id)) { log().warn('system rejected'); return false; }
      if (list.some(function (d) { return d.id === def.id; })) { log().warn('duplicate system ' + def.id); return false; }
      const d = Object.assign({ order: 100 }, def, { disabled: false, error: null, inited: false });
      list.push(d);
      list.sort(function (a, b) { return a.order - b.order; });
      return true;
    },
    count: function () { return list.length; },
    list: function () { return list.map(function (d) { return { id: d.id, order: d.order, disabled: d.disabled, error: d.error }; }); },
    isDisabled: function (id) { const d = list.find(function (x) { return x.id === id; }); return d ? d.disabled : false; },
    enable: function (id) { const d = list.find(function (x) { return x.id === id; }); if (d) { d.disabled = false; d.error = null; } },
    initAll: function (ctx) {
      list.forEach(function (d) { if (!d.inited && enabled(d)) { d.inited = true; call(d, 'init', ctx); } });
    },
    update: function (dt, ctx) {
      for (let i = 0; i < list.length; i++) if (enabled(list[i])) call(list[i], 'update', dt, ctx);
    },
    teardownAll: function (ctx) {
      list.slice().reverse().forEach(function (d) { if (d.inited) { d.inited = false; call(d, 'teardown', ctx); } });
    },
    on: function (ev, fn) {
      if (typeof ev !== 'string' || typeof fn !== 'function') return false;
      (subs[ev] = subs[ev] || []).push(fn);
      return true;
    },
    off: function (ev, fn) {
      if (!subs[ev]) return;
      subs[ev] = subs[ev].filter(function (f) { return f !== fn; });
    },
    emit: emit,
    _clear: function () { list = []; subs = Object.create(null); }
  };

  VCS.Sys = Sys;
  if (typeof module !== 'undefined' && module.exports) module.exports = Sys;
})(typeof window !== 'undefined' ? window : globalThis);
