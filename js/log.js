(function (root) {
  'use strict';
  const VCS = (root.VCS = root.VCS || {});

  const LEVELS = { DEBUG: 10, INFO: 20, WARN: 30, ERROR: 40 };
  const RING_MAX = 500;
  const PERSIST_MAX = 200;
  const MSG_MAX = 500;
  const THROTTLE_MS = 2000;
  const KEY = 'vcs.log';

  let minLevel = LEVELS.INFO;
  let ring = [];
  const subscribers = [];
  let lastPersist = 0;
  let pendingTimer = null;
  let consoleOn = true;

  function getStorage() {
    try {
      return typeof localStorage !== 'undefined' ? localStorage : null;
    } catch (e) {
      return null;
    }
  }

  /** Write the last 200 entries to localStorage; never throws. */
  function flush() {
    pendingTimer = null;
    lastPersist = Date.now();
    try {
      const ls = getStorage();
      if (!ls) return false;
      ls.setItem(KEY, JSON.stringify(ring.slice(-PERSIST_MAX)));
      return true;
    } catch (e) {
      return false;
    }
  }

  function schedulePersist(isError) {
    try {
      const now = Date.now();
      if (isError || now - lastPersist >= THROTTLE_MS) {
        flush();
      } else if (!pendingTimer && typeof setTimeout === 'function') {
        pendingTimer = setTimeout(flush, THROTTLE_MS - (now - lastPersist));
        if (pendingTimer && typeof pendingTimer.unref === 'function') pendingTimer.unref();
      }
    } catch (e) {
      /* ignore */
    }
  }

  function mirror(entry) {
    if (!consoleOn || typeof console === 'undefined') return;
    try {
      const fn = { DEBUG: 'debug', INFO: 'info', WARN: 'warn', ERROR: 'error' }[entry.level];
      const f = console[fn] || console.log;
      f.call(console, '[VCS ' + entry.module + '] ' + entry.msg);
    } catch (e) {
      /* ignore */
    }
  }

  function write(levelName, module, msg, extra) {
    try {
      if (LEVELS[levelName] < minLevel) return null;
      let text;
      try {
        text = String(msg);
      } catch (e) {
        text = '[unprintable]';
      }
      if (text.length > MSG_MAX) text = text.slice(0, MSG_MAX);
      const entry = { t: new Date().toISOString(), level: levelName, module: String(module), msg: text };
      if (extra !== undefined && extra !== null) {
        if (extra instanceof Error || (typeof extra === 'object' && typeof extra.stack === 'string')) {
          entry.stack = String(extra.stack || extra.message || extra);
        } else {
          try {
            entry.data = JSON.parse(JSON.stringify(extra));
          } catch (e) {
            entry.data = String(extra);
          }
        }
      }
      ring.push(entry);
      if (ring.length > RING_MAX) ring.splice(0, ring.length - RING_MAX);
      mirror(entry);
      schedulePersist(levelName === 'ERROR');
      for (const fn of subscribers.slice()) {
        try {
          fn(entry);
        } catch (e) {
          /* ignore */
        }
      }
      return entry;
    } catch (e) {
      return null;
    }
  }

  const Log = {
    VERSION: '0.10.19',
    LEVELS: LEVELS,

    /** Set the minimum level by name (DEBUG/INFO/WARN/ERROR). */
    setLevel: function (name) {
      const v = LEVELS[String(name).toUpperCase()];
      if (v !== undefined) minLevel = v;
    },

    /** Enable or disable the console mirror. */
    setConsole: function (on) {
      consoleOn = !!on;
    },

    /** Get a logger bound to a module name. */
    get: function (module) {
      return {
        debug: function (msg, data) { return write('DEBUG', module, msg, data); },
        info: function (msg, data) { return write('INFO', module, msg, data); },
        warn: function (msg, data) { return write('WARN', module, msg, data); },
        error: function (msg, errOrData) { return write('ERROR', module, msg, errOrData); }
      };
    },

    /** Copy of the in-memory ring buffer. */
    entries: function () {
      return ring.slice();
    },

    /** Force-write the persisted log now. */
    flush: flush,

    /** Clear memory buffer (testing aid). */
    clear: function () {
      ring = [];
      lastPersist = 0;
    },

    /** Read persisted entries from localStorage; [] on any failure. */
    loadPersisted: function () {
      try {
        const ls = getStorage();
        if (!ls) return [];
        const raw = ls.getItem(KEY);
        if (!raw) return [];
        const arr = JSON.parse(raw);
        return Array.isArray(arr) ? arr : [];
      } catch (e) {
        return [];
      }
    },

    /** Format one entry as a text line (plus indented stack lines). */
    format: function (entry) {
      let line = entry.t + ' ' + String(entry.level).padEnd(5) + ' ' + String(entry.module).padEnd(5) + ' ' + entry.msg;
      if (entry.stack) {
        line += '\n' + String(entry.stack).split('\n').map(function (l) { return '    ' + l; }).join('\n');
      }
      return line;
    },

    /** Last n entries as text lines joined by newline. */
    asText: function (n) {
      const count = n === undefined ? 500 : n;
      return ring.slice(-count).map(Log.format).join('\n');
    },

    /** Install window.onerror and unhandledrejection handlers (browser only). */
    installGlobalHandlers: function (onFatal) {
      if (typeof window === 'undefined') return;
      const log = Log.get('global');
      function fatal(code, message, stack) {
        if (typeof onFatal === 'function') {
          try {
            onFatal({ code: code, message: message, stack: stack });
          } catch (e) {
            /* ignore */
          }
        }
      }
      window.onerror = function (message, src, line, col, err) {
        const stack = err && err.stack ? String(err.stack) : String(src) + ':' + line + ':' + col;
        log.error(String(message), { stack: stack });
        fatal('E_UNCAUGHT', String(message), stack);
        return false;
      };
      window.addEventListener('unhandledrejection', function (ev) {
        const r = ev && ev.reason;
        const message = r && r.message ? String(r.message) : String(r);
        const stack = r && r.stack ? String(r.stack) : '';
        log.error(message, { stack: stack });
        fatal('E_REJECTION', message, stack);
      });
    },

    /** Build a plain-text error report (version, UA, time, extra, last 50 lines). */
    report: function (extra) {
      const lines = ['Vampires Can\'t See error report', 'Version: ' + Log.VERSION];
      try {
        if (typeof navigator !== 'undefined' && navigator && navigator.userAgent) {
          lines.push('UserAgent: ' + navigator.userAgent);
        }
      } catch (e) {
        /* ignore */
      }
      lines.push('Time: ' + new Date().toISOString());
      if (extra !== undefined && extra !== null) {
        if (typeof extra === 'object') {
          if (extra.code) lines.push('Code: ' + extra.code);
          if (extra.message) lines.push('Message: ' + extra.message);
        } else {
          lines.push('Info: ' + String(extra));
        }
      }
      lines.push('--- last 50 log lines ---');
      lines.push(Log.asText(50));
      return lines.join('\n');
    },

    /** Subscribe to new entries; returns an unsubscribe function. */
    subscribe: function (fn) {
      subscribers.push(fn);
      return function () {
        const i = subscribers.indexOf(fn);
        if (i >= 0) subscribers.splice(i, 1);
      };
    }
  };

  VCS.Log = Log;
  if (typeof module !== 'undefined' && module.exports) module.exports = Log;
})(typeof window !== 'undefined' ? window : globalThis);
