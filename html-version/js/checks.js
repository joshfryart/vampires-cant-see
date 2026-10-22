(function (root) {
  'use strict';
  const VCS = (root.VCS = root.VCS || {});

  function logger() {
    try {
      return root.VCS && root.VCS.Log ? root.VCS.Log.get('checks') : null;
    } catch (e) {
      return null;
    }
  }

  function makeCanvas(env) {
    return env.document.createElement('canvas');
  }

  /** Run environment checks; never throws. Returns {ok, results}. */
  function run(env) {
    if (env === undefined) env = typeof window !== 'undefined' ? window : {};
    if (env === null || (typeof env !== 'object' && typeof env !== 'function')) env = {};
    const results = [];

    function add(id, required, fn, okMsg, failMsg, infoOnly) {
      let ok = false;
      try {
        ok = !!fn();
      } catch (e) {
        ok = false;
      }
      if (infoOnly) ok = true;
      results.push({ id: id, ok: ok, required: required, message: ok ? okMsg : failMsg });
    }

    add('canvas2d', true, function () {
      const c = makeCanvas(env);
      return c && typeof c.getContext === 'function' && c.getContext('2d');
    }, 'Canvas 2D available', 'Canvas 2D is not available; this browser cannot run the game');

    add('storage', false, function () {
      const ls = env.localStorage;
      const k = 'vcs.check';
      ls.setItem(k, 'ok');
      const same = ls.getItem(k) === 'ok';
      ls.removeItem(k);
      return same;
    }, 'Progress can be saved in this browser', 'This browser is blocking storage (private mode?), so your progress will not be saved between visits.');

    add('pointerLock', false, function () {
      try {
        const c = makeCanvas(env);
        if (c && 'requestPointerLock' in c) return true;
      } catch (e) {
        /* fall through */
      }
      return 'requestPointerLock' in env.Element.prototype;
    }, 'Pointer lock available', 'Mouse look unavailable; use arrow keys to turn');

    add('audio', false, function () {
      return env.AudioContext || env.webkitAudioContext;
    }, 'Web Audio available', 'Audio unavailable; the game will be silent');

    let isFile = false;
    try {
      isFile = env.location.protocol === 'file:';
    } catch (e) {
      isFile = false;
    }
    results.push({
      id: 'fileProtocol',
      ok: true,
      required: false,
      message: isFile ? 'Running from a local file (file://)' : 'Not running from a local file'
    });

    let ok = true;
    const log = logger();
    for (const r of results) {
      if (r.required && !r.ok) ok = false;
      if (log) {
        const text = r.id + ': ' + r.message;
        if (r.ok) log.info(text);
        else if (r.required) log.error(text);
        else log.warn(text);
      }
    }
    return { ok: ok, results: results };
  }

  const Checks = { run: run };
  VCS.Checks = Checks;
  if (typeof module !== 'undefined' && module.exports) module.exports = Checks;
})(typeof window !== 'undefined' ? window : globalThis);
