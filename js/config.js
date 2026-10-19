(function (root) {
  'use strict';
  const VCS = (root.VCS = root.VCS || {});

  const STORAGE_KEY = 'vcs.settings';
  const MAX_CHARS = 16 * 1024;
  const FORBIDDEN_KEYS = ['__proto__', 'constructor', 'prototype'];
  const NOOP_LOG = { debug() {}, info() {}, warn() {}, error() {} };

  const DEFAULTS = Object.freeze({
    mouseSensitivity: 0.0025,
    invertMouse: false,
    moveSpeed: 3.0,
    turnSpeedKeys: 2.4,
    renderScale: 1.0,
    volume: 0.7,
    nightLengthMin: 4,
    cfgV: 2,
    showFps: false,
    fovDeg: 66,
    sonarSpeed: 12,
    sonarRange: 10,
    sonarFade: 3,
    sonarCooldown: 0.8,
    headBob: true,
    lineBoil: true,
    transitionMs: 700,
    materialDetail: true,
    maxMapW: 64,
    maxMapH: 48,
    feedReach: 1.5,
    feedArcDeg: 60,
    poolMin: 18,
    poolMax: 32,
    dazedTime: 3,
    autosaveSec: 20,
    keyTurnSpeed: 3.2,
    dragLook: true,
    feedToggle: false,
    reduceMotion: false,
    largeText: false,
    ambienceGain: 0.6,
    devButton: true
  });

  const SCHEMA = Object.freeze({
    mouseSensitivity: Object.freeze({ type: 'number', min: 0.0005, max: 0.01 }),
    invertMouse: Object.freeze({ type: 'boolean' }),
    moveSpeed: Object.freeze({ type: 'number', min: 1, max: 6 }),
    turnSpeedKeys: Object.freeze({ type: 'number', min: 0.5, max: 5 }),
    renderScale: Object.freeze({ type: 'number', min: 0.25, max: 1 }),
    volume: Object.freeze({ type: 'number', min: 0, max: 1 }),
    nightLengthMin: Object.freeze({ type: 'number', min: 2, max: 30 }),
    cfgV: Object.freeze({ type: 'number', min: 0, max: 99 }),
    showFps: Object.freeze({ type: 'boolean' }),
    fovDeg: Object.freeze({ type: 'number', min: 50, max: 100 }),
    sonarSpeed: Object.freeze({ type: 'number', min: 4, max: 30 }),
    sonarRange: Object.freeze({ type: 'number', min: 4, max: 20 }),
    sonarFade: Object.freeze({ type: 'number', min: 1, max: 8 }),
    sonarCooldown: Object.freeze({ type: 'number', min: 0.2, max: 3 }),
    headBob: Object.freeze({ type: 'boolean' }),
    lineBoil: Object.freeze({ type: 'boolean' }),
    transitionMs: Object.freeze({ type: 'number', min: 200, max: 2000 }),
    materialDetail: Object.freeze({ type: 'boolean' }),
    maxMapW: Object.freeze({ type: 'number', min: 1, max: 64 }),
    maxMapH: Object.freeze({ type: 'number', min: 1, max: 48 }),
    feedReach: Object.freeze({ type: 'number', min: 1, max: 3 }),
    feedArcDeg: Object.freeze({ type: 'number', min: 20, max: 120 }),
    poolMin: Object.freeze({ type: 'number', min: 5, max: 100 }),
    poolMax: Object.freeze({ type: 'number', min: 5, max: 150 }),
    dazedTime: Object.freeze({ type: 'number', min: 0.5, max: 10 }),
    autosaveSec: Object.freeze({ type: 'number', min: 5, max: 300 }),
    keyTurnSpeed: Object.freeze({ type: 'number', min: 1, max: 6 }),
    dragLook: Object.freeze({ type: 'boolean' }),
    feedToggle: Object.freeze({ type: 'boolean' }),
    reduceMotion: Object.freeze({ type: 'boolean' }),
    largeText: Object.freeze({ type: 'boolean' }),
    ambienceGain: Object.freeze({ type: 'number', min: 0, max: 1 }),
    devButton: Object.freeze({ type: 'boolean' })
  });

  /** Returns the 'config' logger, or a no-op logger when VCS.Log is missing. @returns {object} */
  function log() {
    try {
      const L = root.VCS && root.VCS.Log;
      if (L && typeof L.get === 'function') return L.get('config');
    } catch (e) {
      // fall through to no-op
    }
    return NOOP_LOG;
  }

  /** Returns browser localStorage, or null when unavailable or blocked. @returns {Storage|null} */
  function getStorage() {
    try {
      return root.localStorage || null;
    } catch (e) {
      return null;
    }
  }

  /** Returns a fresh mutable copy of DEFAULTS. @returns {object} */
  function defaultsCopy() {
    return Object.assign({}, DEFAULTS);
  }

  /**
   * Validates an untrusted settings object. Never throws.
   * @param {*} obj Parsed settings (any type).
   * @returns {{config: object, warnings: string[]}} Clean config plus warnings.
   */
  function sanitize(obj) {
    const config = defaultsCopy();
    const warnings = [];
    if (obj === null || typeof obj !== 'object' || Array.isArray(obj)) {
      warnings.push('Settings are not an object; using defaults');
      return { config, warnings };
    }
    try {
      for (const key of Object.keys(obj)) {
        if (FORBIDDEN_KEYS.indexOf(key) !== -1) {
          warnings.push(`Setting "${key}" is not allowed; ignored`);
          continue;
        }
        if (!Object.prototype.hasOwnProperty.call(SCHEMA, key)) {
          warnings.push(`Unknown setting "${key}"; ignored`);
          continue;
        }
        const rule = SCHEMA[key];
        const value = obj[key];
        if (typeof value !== rule.type) {
          warnings.push(`Setting "${key}" should be ${rule.type}; using default`);
          continue;
        }
        if (rule.type === 'number' &&
            (!Number.isFinite(value) || value < rule.min || value > rule.max)) {
          warnings.push(`Setting "${key}" is outside ${rule.min} to ${rule.max}; using default`);
          continue;
        }
        config[key] = value;
      }
    } catch (e) {
      return { config: defaultsCopy(), warnings: ['Settings could not be read; using defaults'] };
    }
    return { config, warnings };
  }

  /**
   * Loads saved settings from localStorage. Never throws.
   * @param {{safeMode?: boolean}} [opts] safeMode ignores saved settings.
   * @returns {object} Sanitized config (defaults on any problem).
   */
  function load(opts) {
    const logger = log();
    if (opts && opts.safeMode) {
      logger.info('Safe mode: using default settings');
      return defaultsCopy();
    }
    let raw;
    try {
      const storage = getStorage();
      if (!storage) {
        logger.debug('Storage unavailable; using default settings');
        return defaultsCopy();
      }
      raw = storage.getItem(STORAGE_KEY);
    } catch (e) {
      logger.warn('Could not read saved settings; using defaults', e);
      return defaultsCopy();
    }
    if (raw === null || raw === undefined) return defaultsCopy();
    if (typeof raw !== 'string') {
      logger.warn('Saved settings are not text; using defaults');
      return defaultsCopy();
    }
    if (raw.length > MAX_CHARS) {
      logger.warn(`Saved settings too large (${raw.length} chars); using defaults`);
      return defaultsCopy();
    }
    let parsed;
    try {
      parsed = JSON.parse(raw);
    } catch (e) {
      logger.warn('Saved settings are corrupt; using defaults', e);
      return defaultsCopy();
    }
    const result = sanitize(parsed);
    for (const w of result.warnings) logger.warn(w);
    const cfg = result.config;
    const hadV = parsed && typeof parsed === 'object' && typeof parsed.cfgV === 'number' && parsed.cfgV >= DEFAULTS.cfgV;
    if (!hadV) {
      // v2 migration: the night-length default changed (no UI existed before, so any saved value is stale).
      cfg.nightLengthMin = DEFAULTS.nightLengthMin;
      cfg.cfgV = DEFAULTS.cfgV;
      logger.info('Settings migrated to v' + DEFAULTS.cfgV);
      save(cfg);
    }
    return cfg;
  }

  /**
   * Sanitizes and writes settings to localStorage.
   * @param {object} config Settings to store.
   * @returns {boolean} true when written, false otherwise.
   */
  function save(config) {
    const logger = log();
    try {
      const storage = getStorage();
      if (!storage) {
        logger.warn('Settings not saved: storage unavailable');
        return false;
      }
      const result = sanitize(config);
      for (const w of result.warnings) logger.warn(w);
      storage.setItem(STORAGE_KEY, JSON.stringify(result.config));
      return true;
    } catch (e) {
      logger.error('Could not save settings', e);
      return false;
    }
  }

  const Config = { DEFAULTS, SCHEMA, sanitize, load, save };

  VCS.Config = Config;
  if (typeof module !== 'undefined' && module.exports) module.exports = Config;
})(typeof window !== 'undefined' ? window : globalThis);
