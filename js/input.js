(function (root) {
  'use strict';
  const VCS = (root.VCS = root.VCS || {});

  const PREVENT = new Set(['KeyW', 'KeyA', 'KeyS', 'KeyD', 'ArrowUp', 'ArrowDown',
    'ArrowLeft', 'ArrowRight', 'Space', 'F3', 'KeyM', 'KeyF', 'KeyE', 'KeyR']);

  // A single mouse delta larger than SPIKE_PX is clamped; larger than BOGUS_PX is dropped as a glitch.
  const SPIKE_PX = 300;
  const BOGUS_PX = 1000;
  // Drag shorter than this (px) still counts as a click.
  const DRAG_PX = 4;

  function log() {
    return VCS.Log ? VCS.Log.get('input') : { debug() {}, info() {}, warn() {}, error() {} };
  }

  /** Create an input handler bound to a canvas. */
  function create(canvas, config) {
    const keys = new Set();
    let pressed = new Set();
    let dx = 0;
    let dy = 0;
    let warned = false;
    let clicks = 0;
    let feeds = 0;
    let feedHeld = false;
    let spikes = 0;
    let toggles = 0;
    let dragging = false;
    let dragMoved = 0;
    let suppressLock = false;
    const cfgOn = function (k, d) {
      const v = config && config[k];
      return typeof v === 'boolean' ? v : d;
    };
    let lockUnavailable = typeof canvas.requestPointerLock !== 'function';
    const doc = canvas.ownerDocument || root.document;

    function locked() {
      return !!doc && doc.pointerLockElement === canvas;
    }
    function onKeyDown(e) {
      if (PREVENT.has(e.code)) e.preventDefault();
      if (!e.repeat) {
        pressed.add(e.code);
        if (e.code === 'Space') clicks++;
        if (e.code === 'KeyR') {
          if (cfgOn('feedToggle', false)) toggles++;
          else { feeds++; feedHeld = true; }
        }
      }
      keys.add(e.code);
    }
    function onKeyUp(e) {
      if (PREVENT.has(e.code)) e.preventDefault();
      keys.delete(e.code);
      if (e.code === 'KeyR' && !cfgOn('feedToggle', false)) feedHeld = false;
    }
    function clearKeys() {
      keys.clear();
    }
    function onMouseMove(e) {
      const isLocked = locked();
      if (!isLocked && !dragging) return;
      let mx = Number(e.movementX) || 0;
      let my = Number(e.movementY) || 0;
      if (Math.abs(mx) > BOGUS_PX || Math.abs(my) > BOGUS_PX) {
        spikes++;
        if (spikes === 1 || spikes % 120 === 0) log().debug('Ignored mouse spike ' + mx + ',' + my + ' (x' + spikes + ')');
        return;
      }
      if (Math.abs(mx) > SPIKE_PX || Math.abs(my) > SPIKE_PX) {
        spikes++;
        if (spikes === 1 || spikes % 120 === 0) log().debug('Clamped mouse spike ' + mx + ',' + my + ' (x' + spikes + ')');
        mx = Math.max(-SPIKE_PX, Math.min(SPIKE_PX, mx));
        my = Math.max(-SPIKE_PX, Math.min(SPIKE_PX, my));
      }
      if (!isLocked) dragMoved += Math.abs(mx) + Math.abs(my);
      dx += mx;
      dy += my;
    }
    function onLockChange() {
      if (locked()) {
        if (typeof canvas.requestPointerLock === 'function') lockUnavailable = false;
        dragging = false;
      } else { clearKeys(); feedHeld = false; dragging = false; }
    }
    function onBlur() {
      clearKeys();
      feedHeld = false;
      dragging = false;
    }
    function onMouseUp(e) {
      if (e && e.button === 2) feedHeld = false;
      if (e && e.button === 0 && dragging) {
        dragging = false;
        if (dragMoved > DRAG_PX) suppressLock = true;
        else if (lockUnavailable) clicks++;
      }
    }
    function onLockError() {
      lockUnavailable = true;
      log().warn('Pointer lock refused; canvas clicks will pulse');
    }
    function onMouseDown(e) {
      if (e.button === 2) {
        if (locked() || lockUnavailable) {
          if (cfgOn('feedToggle', false)) toggles++;
          else { feeds++; feedHeld = true; }
        }
        return;
      }
      if (e.button !== 0) return;
      if (locked()) { clicks++; return; }
      if (cfgOn('dragLook', true)) {
        dragging = true;
        dragMoved = 0;
        suppressLock = false;
        return; // pulse (if lock is unavailable) is decided on mouseup
      }
      if (lockUnavailable) clicks++;
    }
    function onContextMenu(e) {
      try { e.preventDefault(); } catch (err) { /* ignore */ }
    }
    function onDocContextMenu(e) {
      if (locked()) onContextMenu(e);
    }
    /**
     * Ask for pointer lock (raw/unadjusted movement first, plain request as fallback).
     * Returns a Promise resolving true when the request was accepted/issued, false on failure.
     * An optional callback(ok) is also invoked. Never throws.
     */
    function requestLock(cb) {
      let done = false;
      let resolveFn = null;
      const finish = function (ok) {
        if (done) return;
        done = true;
        if (!ok) lockUnavailable = true;
        try { if (typeof cb === 'function') cb(ok); } catch (err) { /* ignore */ }
        if (resolveFn) resolveFn(ok);
      };
      const result = typeof Promise === 'function'
        ? new Promise(function (res) { resolveFn = res; })
        : { then() {}, catch() {} };
      if (typeof canvas.requestPointerLock !== 'function') {
        lockUnavailable = true;
        if (!warned) {
          warned = true;
          log().warn('Pointer lock unsupported; use arrow keys to turn');
        }
        finish(false);
        return result;
      }
      const plain = function () {
        try {
          const r2 = canvas.requestPointerLock();
          if (r2 && typeof r2.then === 'function') {
            r2.then(function () { finish(true); }, function (err) {
              log().warn('Pointer lock refused', String(err));
              finish(false);
            });
          } else finish(true);
        } catch (err) {
          log().warn('Pointer lock failed', String(err));
          finish(false);
        }
      };
      try {
        const r = canvas.requestPointerLock({ unadjustedMovement: true });
        if (r && typeof r.then === 'function') {
          r.then(function () { finish(true); }, function (err) {
            log().debug('Unadjusted pointer lock rejected; retrying plain', String(err));
            plain();
          });
        } else finish(true);
      } catch (err) {
        log().debug('Unadjusted pointer lock threw; retrying plain', String(err));
        plain();
      }
      return result;
    }
    function onCanvasClick() {
      if (suppressLock) { suppressLock = false; return; }
      if (!locked()) requestLock();
    }

    root.addEventListener('keydown', onKeyDown);
    root.addEventListener('keyup', onKeyUp);
    root.addEventListener('blur', onBlur);
    if (doc) {
      doc.addEventListener('mousemove', onMouseMove);
      doc.addEventListener('pointerlockchange', onLockChange);
      doc.addEventListener('pointerlockerror', onLockError);
      doc.addEventListener('contextmenu', onDocContextMenu);
    }
    canvas.addEventListener('click', onCanvasClick);
    canvas.addEventListener('mousedown', onMouseDown);
    root.addEventListener('mouseup', onMouseUp);
    canvas.addEventListener('mouseup', onMouseUp);
    canvas.addEventListener('contextmenu', onContextMenu);

    return {
      keys: keys,
      config: config,
      /** Mouse movement since last call. */
      consumeMouseDelta: function () {
        const r = { dx: dx, dy: dy };
        dx = 0;
        dy = 0;
        return r;
      },
      /** Key codes pressed since last call. */
      consumePressed: function () {
        const r = pressed;
        pressed = new Set();
        return r;
      },
      /** Left-button clicks (and Space presses) since last call. */
      consumeClicks: function () {
        const n = clicks;
        clicks = 0;
        return n;
      },
      /** Right-button presses (feed) since last call. */
      consumeFeeds: function () {
        const n = feeds;
        feeds = 0;
        return n;
      },
      /** Feed toggle events (right-click or R press) since last call; only counted when config.feedToggle is true. */
      consumeFeedToggle: function () {
        const n = toggles;
        toggles = 0;
        return n;
      },
      /** True while the right button is held (cleared on mouseup(2), pointer unlock, blur). */
      feedHeld: function () { return feedHeld; },
      /** True when pointer lock is missing or was refused. */
      get lockUnavailable() { return lockUnavailable; },
      /** True when pointer is locked to the canvas. */
      isLocked: locked,
      /** Ask the browser for pointer lock. */
      requestLock: requestLock,
      /** Remove all listeners. */
      destroy: function () {
        root.removeEventListener('keydown', onKeyDown);
        root.removeEventListener('keyup', onKeyUp);
        root.removeEventListener('blur', onBlur);
        if (doc) {
          doc.removeEventListener('mousemove', onMouseMove);
          doc.removeEventListener('pointerlockchange', onLockChange);
          doc.removeEventListener('pointerlockerror', onLockError);
          doc.removeEventListener('contextmenu', onDocContextMenu);
        }
        canvas.removeEventListener('click', onCanvasClick);
        canvas.removeEventListener('mousedown', onMouseDown);
        root.removeEventListener('mouseup', onMouseUp);
        canvas.removeEventListener('mouseup', onMouseUp);
        canvas.removeEventListener('contextmenu', onContextMenu);
      }
    };
  }

  const Input = { create: create };
  VCS.Input = Input;
  if (typeof module !== 'undefined' && module.exports) module.exports = Input;
})(typeof window !== 'undefined' ? window : globalThis);
