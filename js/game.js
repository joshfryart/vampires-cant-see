(function (root) {
  'use strict';
  const VCS = (root.VCS = root.VCS || {});

  const W = 640;
  const H = 360;
  const NOOP_LOG = { debug() {}, info() {}, warn() {}, error() {} };

  const S = {
    state: 'boot',
    config: null,
    world: null,
    player: null,
    input: null,
    canvas: null,
    ctx: null,
    els: {},
    debugOn: false,
    debugEnabled: false,
    running: false,
    rafId: 0,
    lastT: 0,
    frames: 0,
    fpsAcc: 0,
    fps: 0,
    debugAcc: 0,
    lastErr: null,
    wasLocked: false,
    clock: 0,
    view: 'fp',
    sonar: null,
    audio: null,
    renderer: null,
    reduced: false,
    titleT: 0,
    walkPhase: 0,
    bobAmp: 0,
    bob: 0,
    stepCount: 0,
    hudA: 0,
    hudFrac: 0,
    mapWarned: false,
    settingsBound: false,
    people: null,
    ripple: null,
    stepTimer: 0,
    stepOut: [],
    footRight: false,
    worlds: null,
    worldNames: [],
    peopleByMap: {},
    mapName: '',
    baseSonar: null,
    roomKind: null,
    roomZone: null,
    transition: null,
    pausedFrom: '',
    pendingPause: false,
    justArrived: null,
    cool: 0,
    grace: 0,
    playerLit: 0,
    wipeK: 0,
    pctx: { player: null, playerLit: 0, react: null, t: 0, grace: 0 },
    nearIdx: [-1, -1, -1, -1],
    nearD: [0, 0, 0, 0],
    night: null,
    hud: null,
    hudBad: false,
    hs: { blood01: 0, weak: 0, frac: 0, hour: 20, minute: 0, t: 0, boil: true, reduced: false, pulse01: 0 },
    clkMin: -1,
    clkHour: 20,
    clkMinute: 0,
    cardText: null,
    cardSub: null,
    hintPending: false,
    hintT: 0,
    guideOpen: false,
    guideFrom: 'menu',
    cardAge: 0,
    seq: null,
    drink: null,
    lastVictim: null,
    landings: [],
    rocks: [],
    rockCool: 0,
    rocksLeft: 3, // = ROCKS_PER_RUN (reset on new run)
    vialPulse: 0,
    veilK: 0,
    fovK: 0,
    reactCfg: null,
    reactDazed: -1,
    seedBase: 0,
    runKind: '',
    meta: null,
    store: null,
    run: { seed: 1, boons: [], closedSafe: {}, pendingBoons: null, pendingGifts: null },
    fx: null,
    runOn: false,
    menuView: 'main',
    uiT: 0,
    iconCvs: [],
    autoAcc: 0,
    storeWarned: false,
    seedParam: null,
    forceMap: '',
    abandonTimer: 0,
    cardLen: 2.4,
    cryptBad: false,
    uiBad: false,
    hasRun: false,
    hunger: null,
    fm: { startleMul: 1, fleeMul: 1, calmMul: 1 },
    reactKey: -1,
    mist: null,
    mistVis: 0,
    giftFlash: 0,
    overAcc: 0,
    msgAt: -99,
    missAt: -99,
    powerArr: [],
    powerRows: null,
    osReduced: false,
    frameErrs: 0,
    tabId: '',
    otherTab: false,
    tabTimer: 0,
    saveFailed: false,
    ambKey: '',
    ambLvl: -1,
    tutQd: null,
    dogT: 25,
    bellT: 30,
    farRng: null,
    farSpot: null,
    sleepDenied: false,
    cryptWarnUntil: 0,
    tutQ: [],
    tutCur: null,
    tutAge: 0,
    tutSeen: null,
    tutPing: false
  };

  const DEFAULT_FX = { sonarRange: 1, sonarFade: 1, sonarCooldown: 1, startBlood: 0, drain: 1, drinkRate: 1, noise: 1, nightLen: 1, warmRadius: 0 };
  const ACTIVE_STATES = ['playing', 'paused', 'transition', 'feeding', 'sleeping', 'boon', 'gift'];
  const MIST_DIST = 2.0;
  const MIST_DUR = 0.18;
  const POWER_KEYS = { shriek: 'Q', mist: '\u21e7', still: 'F' };

  const HOPTS = { largeText: false, reduced: false, dur: 4 };
  const FEED_REACH = 1.5;
  const DRAG_FULL = 0.25; // v0.10.14: move speed fraction while dragging a full victim
  const DRAG_EMPTY = 0.55; // ... and a nearly drained one
  const DRAG_HOLD = 0.6; // victim is held this far in front of you
  const DRAG_PULL = 2.4; // cells/s the victim is pulled toward the hold point
  const SLEEP_MIN = 510; // night minute (04:30) from which sleeping is allowed
  const STRUGGLE_GAP =0.9; // seconds between struggle attempts
  const STRUGGLE_START = 0.7; // grace after the grab before the first attempt
  const STRUGGLE_WEAK = 0.45; // below this share of blood left the victim is too weak to break free
  const DRINK_BOOST = 1.25; // v0.10.18: drinking ~20% quicker (~7 s per villager)
  const DRAIN_BASE = 1.3; // v0.10.20: blood drains 30% faster before upgrades and boons
  const RESTRAIN_DRINK = 0.5; // drink rate while you hold E to restrain (your hands are busy)
  const RESTRAIN_NOISE = 0.35; // struggle noise left while restrained
  const ROCKS_PER_RUN = 3; // rocks you can throw in one run
  const ROCK_RANGE = 10; // cells a thrown rock can fly
  const ROCK_SPEED = 14; // cells per second
  const ROCK_COOL = 1.0; // seconds between throws
  const STRUGGLE_FREE = 0.4; // chance an attempt breaks free at a full victim (scales to 0 at STRUGGLE_WEAK)
  const SCUFFLE_GAP = 0.38; // seconds of being dragged between scuff sounds
  const FEED_ARC = Math.PI / 3;
  const GRAB_FOV = 54 / 66;
  const SLEEP_DUR = 2.2;
  const CARD_LEN = 2.4;

  /** Module logger (safe if log.js failed to load). */
  function L() {
    return VCS.Log ? VCS.Log.get('game') : NOOP_LOG;
  }

  /** Query an element by id. */
  function $(id) {
    return root.document.getElementById(id);
  }

  /** Show or hide an overlay element. */
  function show(el, on) {
    if (el) el.hidden = !on;
  }

  /** Change game state and toggle overlays. */
  function setState(next) {
    if (S.state === next) return;
    L().info('State ' + S.state + ' -> ' + next);
    S.state = next;
    if (next !== 'paused') S.guideOpen = false;
    show(S.els.pause, next === 'paused' && !S.guideOpen);
    if (next === 'paused') showSettings(false);
    show(S.els.error, next === 'error');
    if (S.renderer && VCS.Render && typeof VCS.Render.setGrain === 'function') VCS.Render.setGrain(S.renderer, next === 'title' || next === 'error' ? 0 : 1);
    if (S.renderer && VCS.Render && typeof VCS.Render.setVignette === 'function' && (next === 'title' || next === 'error')) VCS.Render.setVignette(S.renderer, false);
    syncPanels();
    if (next !== 'error' && next !== 'paused') hideReportBox();
  }

  /** Hide the manual-copy report box. */
  function hideReportBox() {
    if (S.els.reportBox) S.els.reportBox.hidden = true;
  }

  /** Build the timestamp part of the log filename. */
  function stamp() {
    const d = new Date();
    const p = function (n) { return String(n).padStart(2, '0'); };
    return d.getFullYear() + p(d.getMonth() + 1) + p(d.getDate()) + '-' + p(d.getHours()) + p(d.getMinutes());
  }

  /** Download the log as a text file via a temporary link. */
  function downloadLog() {
    try {
      const text = VCS.Log ? VCS.Log.asText() : 'Log unavailable';
      const url = root.URL.createObjectURL(new root.Blob([text], { type: 'text/plain' }));
      const a = root.document.createElement('a');
      a.href = url;
      a.download = 'vcs-log-' + stamp() + '.txt';
      root.document.body.appendChild(a);
      a.click();
      root.document.body.removeChild(a);
      root.setTimeout(function () { root.URL.revokeObjectURL(url); }, 1000);
      L().info('Log downloaded');
    } catch (err) {
      L().error('Download log failed', err);
    }
  }

  /** Copy an error report to the clipboard, or show it for manual copy. */
  function copyReport() {
    let text = '';
    try {
      text = VCS.Log ? VCS.Log.report(S.lastErr || undefined) : 'Log unavailable';
    } catch (err) {
      text = 'Report failed: ' + String(err);
    }
    const fallback = function () {
      const box = S.els.reportBox;
      if (!box) return;
      box.value = text;
      box.hidden = false;
      try { box.focus(); box.select(); } catch (e) { /* ignore */ }
    };
    try {
      const nav = root.navigator;
      if (nav && nav.clipboard && typeof nav.clipboard.writeText === 'function') {
        nav.clipboard.writeText(text).then(function () {
          L().info('Report copied');
        }, fallback);
      } else {
        fallback();
      }
    } catch (err) {
      fallback();
    }
  }

  /** Show the fatal error screen and stop the loop. */
  function fatal(code, message, err) {
    if (S.state === 'error') return;
    S.running = false;
    if (S.rafId && root.cancelAnimationFrame) root.cancelAnimationFrame(S.rafId);
    try {
      L().error('FATAL ' + code + ': ' + message, err);
    } catch (e) { /* ignore */ }
    try {
      if (S.store && S.runOn && !S.drink) saveRun('fatal');
    } catch (e) { /* ignore */ }
    S.lastErr = { code: code, message: message };
    try {
      if (root.document.exitPointerLock) root.document.exitPointerLock();
    } catch (e) { /* ignore */ }
    const els = S.els;
    if (els.errorCode) els.errorCode.textContent = String(code);
    if (els.errorMsg) els.errorMsg.textContent = String(message);
    S.state = 'error';
    try { syncPanels(); } catch (e) { /* ignore */ }
    show(els.pause, false);
    show(els.notice, false);
    show(els.error, true);
  }

  /** A fresh Night state sized from config.nightLengthMin and the run's effects (null if Night fails). */
  function newNightState() {
    try {
      const m = S.config && typeof S.config.nightLengthMin === 'number' ? S.config.nightLengthMin : 4;
      return VCS.Night.create({ nightSec: m * 60 * fxv('nightLen'), bloodStart: Math.min(100, 10 + fxv('startBlood')), drainMul: fxv('drain') * DRAIN_BASE, ramp: VCS.HungerData ? VCS.HungerData.RAMP : 0 });
    } catch (err) {
      L().error('Night.create failed', err);
      return null;
    }
  }

  /** Show a title card (restarts its timer). */
  function showCard(text, startAge, sub) {
    S.cardText = text;
    S.cardSub = typeof sub === 'string' && sub ? sub : null;
    S.cardAge = typeof startAge === 'number' ? startAge : 0;
  }

  /** Ask for pointer lock; if refused show "Click to look" (a canvas click retries via Input). Never throws. */
  function grabLock() {
    const inp = S.input;
    if (!inp) return;
    try {
      const r = inp.requestLock();
      if (r && typeof r.then === 'function') {
        r.then(function (ok) {
          if (ok === false && !inp.isLocked() && (S.state === 'playing' || S.state === 'paused')) {
            if (S.state === 'playing') showCard('Click to look', 0);
            L().info('Pointer lock not granted; waiting for a canvas click');
          }
        }, function () { /* ignore */ });
      }
    } catch (err) {
      L().warn('requestLock failed', err);
    }
  }

  /** Resume from pause. */
  function resume() {
    if (S.state !== 'paused') return;
    grabLock();
    if (S.audio) VCS.Audio.unlock(S.audio);
    setState(S.transition && S.pausedFrom === 'transition' ? 'transition' : 'playing');
    S.pausedFrom = '';
    S.wasLocked = false;
  }

  /** Pause the game. */
  function pause() {
    if (S.drink) endDrink('pause');
    if (S.state !== 'playing' && S.state !== 'transition') return;
    S.pausedFrom = S.state;
    if (S.input) S.input.keys.clear();
    try {
      if (root.document.pointerLockElement && root.document.exitPointerLock) root.document.exitPointerLock();
    } catch (e) { /* ignore */ }
    setState('paused');
    saveRun('pause');
  }

  /** Advance simulation by dt seconds. */
  function update(dt) {
    const input = S.input;
    const pressed = input.consumePressed();
    const mouse = input.consumeMouseDelta();
    const clicks = input.consumeClicks();
    const feeds = typeof input.consumeFeeds === 'function' ? input.consumeFeeds() : 0;
    const feedTog = typeof input.consumeFeedToggle === 'function' ? input.consumeFeedToggle() : 0;
    if (pressed.has('F3')) {
      S.debugOn = !S.debugOn;
      show(S.els.debug, S.debugOn);
    }
    const st0 = S.state;
    if (st0 === 'paused' && S.guideOpen && pressed.has('Escape')) closeGuide();
    if (st0 === 'title' && pressed.has('Escape') && S.menuView !== 'main') showMenuView('main');
    if (st0 === 'boon' || st0 === 'gift') {
      for (let i = 0; i < 3; i++) {
        if (pressed.has('Digit' + (i + 1)) || pressed.has('Numpad' + (i + 1))) {
          if (st0 === 'gift') pickGift(i);
          else pickBoon(i);
          break;
        }
      }
      return;
    }
    if (st0 !== 'playing' && st0 !== 'transition' && st0 !== 'feeding' && st0 !== 'sleeping') return;
    if (S.cardText !== null) {
      S.cardAge += dt;
      if (S.cardAge > S.cardLen) {
        S.cardText = null;
        S.cardSub = null;
        if (S.hintPending) {
          S.hintPending = false;
          S.hintT = 3;
        }
      }
    } else if (S.hintT > 0) {
      S.hintT = Math.max(0, S.hintT - dt);
    }
    if (st0 === 'sleeping') {
      // The sleep sequence ignores Escape, lost pointer lock and clicks; only the sequence timer advances.
      S.wasLocked = false;
      S.clock += dt;
      stepSeq(dt);
      VCS.Sonar.prune(S.sonar, S.clock);
      return;
    }
    const locked = input.isLocked();
    if (S.wasLocked && !locked) {
      // Lost pointer lock: pause now, or right after a running transition finishes.
      if (S.state === 'transition') S.pendingPause = true;
      else {
        pause();
        return;
      }
    }
    S.wasLocked = locked;
    if (pressed.has('Escape')) {
      pause();
      return;
    }
    S.clock += dt;
    if (S.hunger) VCS.Hunger.tick(S.hunger, dt);
    if (S.state === 'transition') {
      stepTransition(dt);
      VCS.Sonar.prune(S.sonar, S.clock);
      return;
    }
    if (pressed.has('KeyM')) {
      if (S.debugEnabled) {
        S.view = S.view === 'fp' ? 'top' : 'fp';
      } else if (!S.mapWarned) {
        S.mapWarned = true;
        L().debug('Map view ignored (only available with ?debug=1)');
      }
    }
    const wasDrinking = !!S.drink;
    if (!wasDrinking && S.state === 'playing') powerKeys(pressed);
    if (S.mistVis > 0) S.mistVis = Math.max(0, S.mistVis - dt / 0.45);
    if (wasDrinking) {
      // Drinking: you drag the victim slowly (the fuller they are, the harder they resist); look is halved.
      const dk = S.drink;
      const inp = VCS.Player.inputFromKeys(input.keys, mouse.dx * 0.5);
      const px = S.player.x;
      const py = S.player.y;
      const k = dragSpeedK(dk);
      const cfg = Object.assign({}, S.config, { moveSpeed: cfgNum('moveSpeed', 3) * k });
      VCS.Player.update(S.player, S.world, inp, dt, cfg);
      const moved = Math.hypot(S.player.x - px, S.player.y - py);
      stepVictimPull(dk, dt);
      updateBob(dt, moved);
      playerSteps(dt, moved);
    } else {
      const inp = VCS.Player.inputFromKeys(input.keys, mouse.dx);
      const px = S.player.x;
      const py = S.player.y;
      if (S.mist) {
        // Mist dash: look still works, walking input is replaced by the dash; no footsteps, no door bumps.
        inp.forward = 0;
        inp.strafe = 0;
        VCS.Player.update(S.player, S.world, inp, dt, S.config);
        stepMist(dt);
        updateBob(dt, 0);
        S.stepTimer = 0;
      } else {
        VCS.Player.update(S.player, S.world, inp, dt, S.config);
        const moved = Math.hypot(S.player.x - px, S.player.y - py);
        updateBob(dt, moved);
        playerSteps(dt, moved);
        bumpDoors(inp);
      }
    }
    if (S.cool > 0) S.cool -= dt;
    if (S.rockCool > 0) S.rockCool -= dt;
    stepRocks();
    S.playerLit = safeLight(S.world, S.player.x, S.player.y);
    S.veilK += (clamp(S.playerLit, 0, 1) - S.veilK) * (1 - Math.exp(-dt / 0.3)); // veil meter: same light value villagers spot with
    if (S.grace > 0) S.grace -= dt;
    if (!wasDrinking) {
      if (checkLinkDoor()) return;
      followRoom();
      if (pressed.has('KeyE')) interact();
      if (pressed.has('KeyG')) throwRock();
      if (feeds > 0 && S.state === 'playing' && !startDrink(false)) missFeed();
      if (feedTog > 0 && S.state === 'playing' && cfgOn('feedToggle') && !S.drink && !startDrink(false)) missFeed();
    } else if (feedTog > 0 && S.drink && cfgOn('feedToggle') && !S.drink.forced) {
      endDrink('release');
    }
    if (clicks > 0) pulse(); // v0.10.17: echolocate while holding a victim (click no longer lets go)
    VCS.Sonar.prune(S.sonar, S.clock);
    simulateWorld(dt);
    stepAmbient(dt);
    crackleTorches();
    if (stepNight(dt)) return;
    stepTutorial(dt);
    if (S.drink) stepDrink(dt);
    stepFeedFx(dt);
    if (S.state === 'playing' && S.runOn) {
      S.autoAcc += dt;
      if (S.autoAcc >= cfgNum('autosaveSec', 20)) {
        S.autoAcc = 0;
        saveRun('autosave');
      }
    }
    const cd = VCS.Sonar.cooldownLeft(S.sonar, S.clock);
    if (cd > 0) S.hudFrac = Math.min(1, cd / (S.sonar.cooldown || 0.8));
    S.hudA = clamp(S.hudA + (cd > 0 ? dt : -dt) / 0.15, 0, 1);
  }

  /** Advance the night clock; handles its events. True if the run ended or a fatal error occurred. */
  function stepNight(dt) {
    const n = S.night;
    if (!n) return false;
    let ev;
    try {
      ev = VCS.Night.update(n, dt, { outdoor: S.world.kindAt(S.player.x, S.player.y) === 'outdoor' });
    } catch (err) {
      fatal('E_NIGHT', 'Night clock failed: ' + ((err && err.message) || String(err)), err);
      return true;
    }
    if (!ev || !ev.length) return false;
    let lost = false;
    for (let i = 0; i < ev.length; i++) {
      if (ev[i] === 'chime') {
        if (S.audio) VCS.Audio.play(S.audio, 'chime', { gain: level('chime').gain, pan: 0 });
        showCard('Dawn');
        L().info('Night chime');
      } else if (ev[i] === 'dawn') {
        L().info('Dawn: the sun is up');
      } else if (ev[i] === 'lost') {
        lost = true;
      }
    }
    if (lost) {
      endRun('lost');
      return true;
    }
    return false;
  }

  /** Begin the sleep sequence. */
  function startSeq(type, dur) {
    S.seq = { type: type, t: 0, dur: dur, did: false, did2: false, person: null, people: null };
    setState('sleeping');
    return S.seq;
  }

  /** Config number with a fallback. */
  function cfgNum(key, d) {
    const v = S.config ? S.config[key] : undefined;
    return typeof v === 'number' && isFinite(v) ? v : d;
  }

  /** Boolean config flag (false when unset). */
  function cfgOn(key) {
    return !!(S.config && S.config[key] === true);
  }

  /** Right click with nothing to grab: soft miss sound, no pulse. */
  function missFeed() {
    L().debug('feed: no target');
    if (S.audio) VCS.Audio.play(S.audio, 'miss', { gain: level('miss').gain, pan: 0 });
  }

  /** Push (or refresh) a snapshot echo of a person so the feed lock has a figure to draw. */
  function pushVictimEcho(p) {
    const st = S.people;
    if (!st || !p) return;
    const es = st.echoes;
    for (let i = es.length - 1; i >= 0; i--) if (es[i].personId === p.id) es.splice(i, 1);
    es.push({
      personId: p.id, x: p.x, y: p.y, angle: p.angle, lookAngle: p.lookAngle, phase: p.phase, moving: false,
      t: S.clock, dist: Math.hypot(p.x - S.player.x, p.y - S.player.y), strength: 0.9, pan: panTo(p.x, p.y), look: p.look,
      zMin: 0, zMax: 1.2, fade: 2.2
    });
    while (es.length > st.maxEchoes) es.shift();
  }

  /** Grab the person in front and start drinking. forced = debug hold (ignores the mouse button). True if started. */
  function startDrink(forced) {
    if (S.state !== 'playing' || !S.night || !S.people || !S.player || S.drink) return false;
    const p = S.player;
    let target = null;
    try {
      target = VCS.People.feedTarget(S.people, p.x, p.y, p.angle, cfgNum('feedReach', FEED_REACH), cfgNum('feedArcDeg', 60) * Math.PI / 180);
    } catch (err) {
      L().warn('feedTarget failed', err);
    }
    if (!target) return false;
    let front = false;
    try {
      front = VCS.People.sees(target, S.world, p.x, p.y);
    } catch (err) {
      L().warn('People.sees failed', err);
    }
    if (!VCS.People.grab(S.people, target.id)) return false;
    S.drink = { id: target.id, person: target, people: S.people, pool: target.pool > 0 ? target.pool : 40, left: target.left, drunk: 0, beatAt: 0.1, t: 0, forced: !!forced, interrupt: false, struggleAt: STRUGGLE_START, lastStruggle: -99, rs: 0, scuffAcc: 0 };
    S.lastVictim = { id: target.id, people: S.people };
    if (S.hunger) VCS.Hunger.onGrab(S.hunger, S.mapName + ':' + target.id);
    S.overAcc = 0;
    setState('feeding');
    pushVictimEcho(target);
    if (front) {
      emitSound('gasp', target.x, target.y);
      if (S.audio) VCS.Audio.play(S.audio, 'gasp', spatial(target.x, target.y, level('gasp').gain));
      reactTo(target.x, target.y, 'gasp');
    }
    L().info('Drinking person ' + target.id + ' pool ' + S.drink.pool.toFixed(1) + (front ? ' (front grab)' : ''));
    return true;
  }

  /** Player speed fraction while dragging: DRAG_FULL with a full victim, DRAG_EMPTY as they run dry (resistance falls with blood). */
  function dragSpeedK(d) {
    const f = d && d.pool > 0 ? clamp(d.left / d.pool, 0, 1) : 0;
    return DRAG_EMPTY + (DRAG_FULL - DRAG_EMPTY) * f;
  }

  /** Ease the victim to DRAG_HOLD cells in front of the player, without walking through walls. */
  function stepVictimPull(d, dt) {
    const v = d.person;
    const p = S.player;
    const tx = p.x + Math.cos(p.angle) * DRAG_HOLD;
    const ty = p.y + Math.sin(p.angle) * DRAG_HOLD;
    const dx = tx - v.x;
    const dy = ty - v.y;
    const dist = Math.hypot(dx, dy);
    if (dist < 0.02) return;
    const step = Math.min(dist, DRAG_PULL * dt);
    const mx = dx / dist * step;
    const my = dy / dist * step;
    const w = S.world;
    const r = 0.2;
    const free = function (x, y) { return typeof w.blocks === 'function' ? !w.blocks(x, y, r) : !w.isSolid(x, y); };
    let moved = false;
    if (free(v.x + mx, v.y)) { v.x += mx; moved = true; }
    if (free(v.x, v.y + my)) { v.y += my; moved = true; }
    if (moved) {
      v.angle = Math.atan2(p.y - v.y, p.x - v.x);
      d.pullEcho = (d.pullEcho || 0) + dt;
      if (d.pullEcho >= 0.1) { d.pullEcho = 0; pushVictimEcho(v); }
      d.scuffAcc += dt;
      if (d.scuffAcc >= SCUFFLE_GAP) {
        d.scuffAcc = 0;
        emitSound('scuffle', v.x, v.y);
        reactTo(v.x, v.y, 'scuffle', level('scuffle').range);
        if (S.audio) VCS.Audio.play(S.audio, 'scuffle', spatial(v.x, v.y, level('scuffle').gain, { material: stepMaterial(v.x, v.y) }));
      }
    }
  }

  /** One drinking tick: blood flows, beats fire, stop rules run. */
  function stepDrink(dt) {
    const d = S.drink;
    if (!d) return;
    const p = d.person;
    const n = S.night;
    d.t += dt;
    if (d.interrupt) return endDrink('witness');
    if (!d.forced && d.t > dt * 1.5 && S.input && typeof S.input.feedHeld === 'function' && !S.input.feedHeld() && !cfgOn('feedToggle')) return endDrink('released');
    if (Math.hypot(p.x - S.player.x, p.y - S.player.y) > cfgNum('feedReach', FEED_REACH) + 0.3) return endDrink('reach');
    const wantRs = S.input && S.input.keys && S.input.keys.has('KeyE') ? 1 : 0;
    d.rs += (wantRs - d.rs) * (1 - Math.exp(-dt / 0.12));
    if (d.t >= d.struggleAt && struggle(d)) return;
    const ovOpen = !!S.hunger && VCS.Hunger.isOpen(S.hunger);
    if (n.blood >= n.bloodMax && !ovOpen) return endDrink('cap');
    const rate = (2.5 + 4.5 * clamp(d.left / d.pool, 0, 1)) * fxv('drinkRate') * DRINK_BOOST * (1 - (1 - RESTRAIN_DRINK) * d.rs); // v0.10.15: ~8 s per villager (was 6..20/s, ~2.5 s)
    let gain = 0;
    let over = 0;
    let ready = false;
    try {
      gain = VCS.Night.addBlood(n, rate * dt) || 0;
      if (ovOpen && n.blood >= n.bloodMax && rate * dt - gain > 1e-9) {
        const r = VCS.Hunger.addOverflow(S.hunger, rate * dt - gain);
        over = r.taken;
        ready = r.ready;
      }
    } catch (err) {
      L().warn('Night.addBlood failed', err);
    }
    if (over > 0) {
      S.overAcc += over;
      while (S.overAcc >= 10) {
        S.overAcc -= 10;
        if (S.audio) VCS.Audio.play(S.audio, 'overflow', { gain: level('overflow').gain, pan: 0 });
      }
    }
    gain += over;
    d.drunk += gain;
    const left = VCS.People.drink(d.people, d.id, gain);
    d.left = left >= 0 ? left : 0;
    if (ready) {
      endDrink('gift');
      enterGift();
      return;
    }
    if (d.left <= 0.5) return endDrink('empty');
    if (d.t >= d.beatAt) {
      drinkBeat(d);
      if (d.interrupt) return endDrink('witness');
      const bpm = 50 + 70 * clamp(d.left / d.pool, 0, 1);
      d.beatAt += 60 / bpm;
    }
    if (n.blood >= n.bloodMax && !(S.hunger && VCS.Hunger.isOpen(S.hunger))) endDrink('cap');
  }

  /**
   * One struggle attempt: the victim thrashes (noise, ripple, startles neighbours). While they still hold enough blood
   * there is a chance they tear free, scream and run; below STRUGGLE_WEAK they are too weak and only twitch. True if they broke free.
   */
  function struggle(d) {
    const v = d.person;
    const frac = clamp(d.left / d.pool, 0, 1);
    d.struggleAt += STRUGGLE_GAP * (0.8 + 0.4 * Math.random());
    d.lastStruggle = d.t;
    const strong = clamp((frac - STRUGGLE_WEAK) / (1 - STRUGGLE_WEAK), 0, 1);
    const rs = d.rs > 0.5 ? 1 : 0; // restrained (holding E): pinned down, muffled, cannot tear free
    const k = (0.35 + 0.65 * Math.max(strong, 0.3)) * (1 - (1 - RESTRAIN_NOISE) * rs); // weak victims thrash quieter
    emitSound('struggle', v.x, v.y, { rangeMul: k, strengthMul: k });
    reactTo(v.x, v.y, 'struggle', level('struggle').range * k + 0.5);
    if (S.audio) VCS.Audio.play(S.audio, 'struggle', spatial(v.x, v.y, level('struggle').gain * k));
    if (S.ripple) VCS.Ripple.spawn(S.ripple, v.x, v.y, S.clock, { kind: 'person', maxR: 0.9 + 0.6 * k, life: 0.45, strength: 0.7 });
    pushVictimEcho(v);
    if (rs || strong <= 0 || Math.random() >= STRUGGLE_FREE * strong) return false;
    L().info('Person ' + d.id + ' broke free (left ' + d.left.toFixed(1) + ')');
    endDrink('broke');
    if (v.mode === 'dazed') v.dazedLeft = Math.min(v.dazedLeft, 0.15); // bolts at once instead of standing dazed
    emitSound('scream', v.x, v.y);
    if (S.audio) VCS.Audio.play(S.audio, 'scream', spatial(v.x, v.y, level('scream').gain));
    reactTo(v.x, v.y, 'scream', 5);
    return true;
  }

  /** Throw a rock along your facing: it flies until a wall or person and clatters down there after its flight time. */
  function throwRock() {
    if (S.state !== 'playing' || S.drink || !S.world || !S.player || S.rockCool > 0) return false;
    if (S.rocksLeft <= 0) {
      S.rockCool = ROCK_COOL;
      showCard('No rocks left', 0);
      if (S.audio) VCS.Audio.play(S.audio, 'miss', { gain: 0.06, pan: 0 });
      return false;
    }
    S.rocksLeft--;
    const p = S.player;
    const w = S.world;
    const dx = Math.cos(p.angle);
    const dy = Math.sin(p.angle);
    const ppl = S.people ? S.people.people : [];
    let d = 0;
    while (d < ROCK_RANGE) {
      const nx = p.x + dx * (d + 0.1);
      const ny = p.y + dy * (d + 0.1);
      if (typeof w.blocks === 'function' ? w.blocks(nx, ny, 0.05) : w.isSolid(nx, ny)) break;
      d += 0.1;
      let hit = false;
      for (let i = 0; i < ppl.length; i++) if (Math.hypot(ppl[i].x - nx, ppl[i].y - ny) < 0.3) hit = true;
      if (hit) break;
    }
    d = Math.max(0.4, d);
    S.rocks.push({ x: p.x + dx * d, y: p.y + dy * d, at: S.clock + d / ROCK_SPEED });
    S.rockCool = ROCK_COOL;
    if (S.audio) VCS.Audio.play(S.audio, 'miss', { gain: 0.1, pan: 0 });
    L().debug('Rock thrown (' + S.rocksLeft + ' left), lands in ' + (d / ROCK_SPEED).toFixed(2) + ' s');
    return true;
  }

  /** Land any rocks whose flight is over: a loud clatter, sound waves, ripple ring, nearby villagers startle. */
  function stepRocks() {
    const rs = S.rocks;
    for (let i = rs.length - 1; i >= 0; i--) {
      const r = rs[i];
      if (r.at > S.clock) continue;
      rs.splice(i, 1);
      emitSound('clatter', r.x, r.y);
      reactTo(r.x, r.y, 'clatter', level('clatter').range * 0.7);
      if (S.audio) VCS.Audio.play(S.audio, 'clatter', spatial(r.x, r.y, level('clatter').gain, { material: stepMaterial(r.x, r.y) }));
      if (S.ripple) VCS.Ripple.spawn(S.ripple, r.x, r.y, S.clock, { kind: 'person', maxR: 1.1, life: 0.5, strength: 0.7 });
    }
  }

  /** One heartbeat: sonar pulse from the victim, startle radius, audio, rings, echo refresh, gulp landing. */
  function drinkBeat(d) {
    const v = d.person;
    const weak = S.night ? VCS.Night.weakness(S.night) : 0;
    const R = (1.5 + 2.5 * clamp(d.drunk / d.pool, 0, 1)) * (1 - 0.4 * weak);
    emitSound('heartbeat', v.x, v.y, { range: R, z: 0.55, bounces: 0 });
    reactTo(v.x, v.y, 'heartbeat', R);
    if (S.audio) VCS.Audio.play(S.audio, 'heartbeat', spatial(v.x, v.y, level('heartbeat').gain * (0.6 + 0.4 * clamp(d.left / d.pool, 0, 1))));
    if (S.ripple) {
      VCS.Ripple.spawn(S.ripple, v.x, v.y, S.clock, { kind: 'person', maxR: 1.0, life: 0.5, strength: 0.9 });
      if (S.reduced) VCS.Ripple.spawn(S.ripple, v.x, v.y, S.clock, { kind: 'person', maxR: 0.8, minR: 0.8, inward: true, life: 0.4, strength: 0.6 });
      else VCS.Ripple.spawn(S.ripple, S.player.x, S.player.y, S.clock, { kind: 'person', maxR: 1.4, minR: 0.15, inward: true, life: 0.4, strength: 0.8 });
    }
    pushVictimEcho(v);
    if (S.landings.length < 8) S.landings.push(S.clock + 0.4);
  }

  /** Stop drinking. Fully drained: fed. Otherwise the victim is released dazed. */
  function endDrink(reason) {
    const d = S.drink;
    if (!d) return;
    S.drink = null;
    try {
      const p = d.person;
      if (p.left <= 0.5) {
        VCS.People.markFed(d.people, d.id);
        if (S.night) S.night.fedCount = (S.night.fedCount || 0) + 1;
        L().info('Drained person ' + d.id + ' (' + reason + '), drunk ' + d.drunk.toFixed(1));
      } else {
        VCS.People.release(d.people, d.id, S.player ? S.player.x : p.x, S.player ? S.player.y : p.y);
        L().info('Released person ' + d.id + ' (' + reason + '), drunk ' + d.drunk.toFixed(1) + ' left ' + p.left.toFixed(1));
      }
    } catch (err) {
      L().warn('endDrink failed', err);
    }
    if (S.state === 'feeding') setState('playing');
  }

  /** Per-frame feed effects: FOV ease, vial pulse decay, gulp landings. */
  function stepFeedFx(dt) {
    const up = S.drink ? 1 / 0.35 : -1 / 0.4;
    S.fovK = clamp(S.fovK + up * dt, 0, 1);
    if (S.vialPulse > 0) S.vialPulse = Math.max(0, S.vialPulse - dt / 0.15);
    const ls = S.landings;
    while (ls.length && ls[0] <= S.clock) {
      ls.shift();
      S.vialPulse = 1;
      if (S.audio) VCS.Audio.play(S.audio, 'gulp', { gain: level('gulp').gain, pan: 0 });
    }
  }

  /** Try to go to sleep at a crypt or safe spot in reach. True if the sequence started. */
  function trySleep(force) {
    if (S.state !== 'playing' || !S.night || !S.world || !S.player) return false;
    const p = S.player;
    S.sleepDenied = false;
    // Safe spots open at SLEEP_MIN (04:30, as the tutorial hint says). The crypt bed works any time, but the first early
    // press only warns (nights get harder); a second press within 4 s sleeps. Debug sleep ignores all of this.
    if (force !== true && S.night.min < SLEEP_MIN) {
      const reach0 = (VCS.SoundData && VCS.SoundData.reach) || 1.3;
      const near = function (sp) { return Math.hypot(sp.x - p.x, sp.y - p.y) <= reach0; };
      const nearCrypt = (S.world.spots.crypt || []).some(near);
      const nearSafe = (S.world.spots.safe || []).some(near);
      if (nearCrypt && S.clock < S.cryptWarnUntil) {
        S.cryptWarnUntil = 0; // confirmed: fall through to sleep
      } else if (nearCrypt || nearSafe) {
        S.sleepDenied = true;
        if (nearCrypt) {
          S.cryptWarnUntil = S.clock + 4;
          showCard('Sleep early?', CARD_LEN - 1, 'Each night grows harder. Press E again to sleep.');
        } else {
          showCard('Not tired yet', CARD_LEN - 1, 'Wait until the night is nearly spent, or sleep in the crypt.');
        }
        if (S.audio) VCS.Audio.play(S.audio, 'miss', { gain: level('miss').gain, pan: 0 });
        L().info('Sleep too early (min ' + Math.floor(S.night.min) + ')');
        return false;
      } else {
        return false;
      }
    }
    const reach = (VCS.SoundData && VCS.SoundData.reach) || 1.3;
    const w = S.world;
    const lists = [w.spots.crypt || [], w.spots.safe || []];
    let sealed = false;
    S.sleepDenied = false;
    for (let a = 0; a < 2; a++) {
      for (let i = 0; i < lists[a].length; i++) {
        if (Math.hypot(lists[a][i].x - p.x, lists[a][i].y - p.y) <= reach) {
          if (a === 1 && isSealed(lists[a][i])) {
            sealed = true;
            continue;
          }
          if (a === 1 && isFarSpot(lists[a][i])) awardFarSpot();
          startSeq('sleep', SLEEP_DUR);
          if (S.audio) VCS.Audio.play(S.audio, 'yawn', { gain: level('yawn').gain, pan: 0 });
          L().info('Sleeping');
          return true;
        }
      }
    }
    if (sealed) {
      S.sleepDenied = true;
      showCard('Sealed', CARD_LEN - 1);
      if (S.audio) VCS.Audio.play(S.audio, 'miss', { gain: level('miss').gain, pan: 0 });
      L().info('Safe spot is sealed');
    }
    return false;
  }

  /** Advance the active feed/sleep sequence. */
  function stepSeq(dt) {
    const q = S.seq;
    if (!q) {
      setState('playing');
      return;
    }
    q.t += dt;
    if (!q.did && q.t >= 0.8) {
      q.did = true;
      let r = 'none';
      try {
        r = VCS.Night.sleep(S.night);
      } catch (err) {
        L().warn('sleep failed', err);
      }
      if (r === 'won') {
        S.seq = null;
        endRun('won');
        return;
      }
      if (r === 'next') {
        S.seq = null;
        enterBoon();
        return;
      }
    }
    if (q.t >= q.dur) {
      S.seq = null;
      setState('playing');
    }
  }

  /** Reset the world for a new night after sleeping. */
  function nextNight() {
    const n = S.night.night;
    if (S.hunger) {
      const nb = VCS.Hunger.onSleep(S.hunger);
      S.hunger.stillLeft = 0;
      S.mist = null;
      if (nb > 0) {
        try {
          VCS.Night.addBlood(S.night, nb);
        } catch (err) {
          L().warn('addBlood (reserve) failed', err);
        }
      }
    }
    S.seedBase = n * 100;
    S.peopleByMap = {};
    S.people = peopleFor(S.mapName);
    VCS.Sonar.reset(S.sonar);
    if (S.ripple) S.ripple.rings.length = 0;
    if (S.audio) VCS.Audio.stopAll(S.audio, 0.15);
    const up = unlockedPower(n);
    const sub = up ? up.how : '';
    showCard('Night ' + n + unlockText(n), 0, sub.trim() || null);
    initAmbient();
    tutClear();
    S.hintPending = false;
    S.hintT = 0;
    if (up && markSeen(up.id)) S.hintPending = true;
    L().info('Night ' + n + ' begins');
  }

  /** End the run: kind 'lost' (sun) or 'won' (all nights survived). Records meta stats, clears the saved run. */
  function endRun(kind) {
    if (S.state === 'runend') return;
    endDrink('run');
    S.runKind = kind;
    S.seq = null;
    S.landings.length = 0;
    if (S.input) S.input.keys.clear();
    try {
      if (root.document.pointerLockElement && root.document.exitPointerLock) root.document.exitPointerLock();
    } catch (e) { /* ignore */ }
    const n = S.night;
    const survived = n ? (kind === 'won' ? n.nights : Math.max(0, n.night - 1)) : 0;
    const fed = n ? n.fedCount : 0;
    let earned = 0;
    const bonus = S.hunger && Number.isFinite(S.hunger.essenceBonus) ? Math.max(0, Math.floor(S.hunger.essenceBonus)) : 0;
    try {
      earned = VCS.Meta.recordRun(S.meta, { nights: survived, fed: fed, won: kind === 'won', bonus: bonus }) || 0;
      saveMeta();
    } catch (err) {
      L().error('recordRun failed', err);
    }
    try {
      if (S.store && !S.otherTab) S.store.remove('run');
    } catch (err) {
      L().warn('Could not clear the saved run', err);
    }
    S.hasRun = false;
    S.runOn = false;
    if (S.run) {
      S.run.pendingBoons = null;
      S.run.pendingGifts = null;
    }
    if (S.els.runendTitle) S.els.runendTitle.textContent = kind === 'won' ? 'Five nights survived' : 'The sun found you';
    if (S.els.runendMsg) S.els.runendMsg.textContent = 'Nights survived: ' + survived + ' · People fed: ' + fed;
    if (S.els.runendEssence) S.els.runendEssence.textContent = 'Essence +' + earned + (bonus > 0 ? ' (bonus +' + bonus + ')' : '');
    setState('runend');
    L().info('Run ended: ' + kind + ' nights=' + survived + ' fed=' + fed + ' essence=+' + earned);
  }

  /** Reset per-run world state (doors, people, sequences) and put the player at the start of `mapName`. */
  function resetWorldForRun() {
    resetWorldDoors();
    S.seedBase = 0;
    S.peopleByMap = {};
    S.seq = null;
    S.drink = null;
    S.landings.length = 0;
    S.transition = null;
    S.wipeK = 0;
    S.pendingPause = false;
    S.cardText = null;
    S.clkMin = -1;
    S.mist = null;
    S.mistVis = 0;
    S.overAcc = 0;
  }

  /** Begin a brand new run (from the menu or the run-end panel). True if it started. */
  function beginRun() {
    if (S.state !== 'title' && S.state !== 'runend') return false;
    if (!S.worlds || !S.player) return false;
    const seed = S.seedParam !== null ? S.seedParam : (Math.random() * 4294967296) >>> 0;
    S.run = { seed: seed, boons: [], closedSafe: {}, pendingBoons: null, pendingGifts: null };
    S.hunger = VCS.Hunger.create();
    S.fx = computeFx();
    resetWorldForRun();
    S.run.closedSafe = closeSafeSpots(seed);
    computeFarSpot();
    S.night = newNightState();
    const w = S.forceMap && S.worlds[S.forceMap] ? S.forceMap : S.worlds[VCS.MapData.startMap] ? VCS.MapData.startMap : S.worldNames[0];
    const a = startPlace(S.worlds[w]);
    enterMap(w, a.x, a.y, a.angle, null);
    applyFx();
    S.runOn = true;
    S.autoAcc = 0;
    S.rocksLeft = ROCKS_PER_RUN;
    S.rocks.length = 0;
    L().info('New run seed ' + seed);
    initAmbient();
    tutStart();
    setState('playing');
    S.wasLocked = false;
    grabLock();
    if (S.audio) VCS.Audio.unlock(S.audio);
    showCard('Night 1');
    saveRun('new run');
    return true;
  }

  /** Levels for a sound kind from SoundData (with safe fallbacks). */
  function level(kind) {
    const lv = VCS.SoundData && VCS.SoundData.levels && VCS.SoundData.levels[kind];
    return lv || { range: 3, strength: 0.3, bounces: 0, gain: 0.1 };
  }

  /** Emit a sound pulse; over {range,z,bounces} overrides (rangeMul/strengthMul/fadeMul scale it) the level table (guarded: Sonar.emitSound may not exist yet). Passes the source height z and fade. Returns the pulse or null. */
  /** Multiplier from an optional override: finite positive number, else 1. */
  function num(v) { return typeof v === 'number' && isFinite(v) && v > 0 ? v : 1; }

  function emitSound(kind, x, y, over) {
    try {
      if (!S.sonar || typeof VCS.Sonar.emitSound !== 'function') return null;
      const lv = level(kind);
      const room = roomProfile(S.world, S.world.kindAt(x, y));
      const weak = S.night ? VCS.Night.weakness(S.night) : 0;
      const wash = S.night && S.world.kindAt(x, y) === 'outdoor' ? VCS.Night.washK(S.night) : 0;
      const wm = 1 - 0.4 * weak;
      const ov = over || {};
      const baseRange = typeof ov.range === 'number' && isFinite(ov.range) ? ov.range : lv.range * wm;
      const opts = {
        kind: kind,
        range: baseRange * room.rangeMul * (1 - 0.5 * wash) * num(ov.rangeMul),
        strength: lv.strength * wm * num(ov.strengthMul),
        bounces: Math.min(typeof ov.bounces === 'number' ? ov.bounces : lv.bounces || 0, room.bounceCap),
        visRays: 180
      };
      if (typeof ov.z === 'number') opts.z = ov.z;
      else if (typeof lv.z === 'number') opts.z = lv.z;
      if (typeof lv.fade === 'number') opts.fade = lv.fade * room.fadeMul * (1 - 0.3 * weak) * (1 - 0.6 * wash) * num(ov.fadeMul);
      const pu = VCS.Sonar.emitSound(S.sonar, S.world, x, y, S.clock, opts);
      if (pu && weak > 0) tagWeak(pu, weak, 1);
      return pu;
    } catch (err) {
      L().warn('emitSound failed', err);
      return null;
    }
  }

  /** Mark the primary pulse and every pulse pushed after it (its bounce children) as weak; scale their strength by sMul. */
  function tagWeak(primary, weak, sMul) {
    const ps = S.sonar.pulses;
    let i = ps.indexOf(primary);
    if (i < 0) i = 0;
    for (; i < ps.length; i++) {
      ps[i].weak = weak;
      if (sMul !== 1) ps[i].strength *= sMul;
    }
  }

  /** Stereo pan (-1..1) of a world point relative to where the player faces. */
  function panTo(x, y) {
    const p = S.player;
    return clamp(Math.sin(Math.atan2(y - p.y, x - p.x) - p.angle), -1, 1);
  }

  /** First solid point on the segment (x0,y0)-(x1,y1) (sampled every 0.25 cell, up to 25 cells): {x, y} or null when the line is clear. */
  function firstSolid(x0, y0, x1, y1) {
    const w = S.world;
    if (!w || typeof w.isSolid !== 'function') return null;
    const dx = x1 - x0;
    const dy = y1 - y0;
    const d = Math.hypot(dx, dy);
    if (!(d > 0.5)) return null;
    const n = Math.min(d, 25) / 0.25;
    for (let i = 1; i < n; i++) {
      const k = (i * 0.25) / d;
      if (w.isSolid(x0 + dx * k, y0 + dy * k)) return { x: x0 + dx * k, y: y0 + dy * k };
    }
    return null;
  }

  /** Acoustic material of the solid cell at (x,y): door (closed D), or the world material (stone, brick, wood, iron, glass). */
  function blockMaterial(x, y) {
    const w = S.world;
    try {
      if (typeof w.tileAt === 'function' && w.tileAt(x, y) === 'D') return 'door';
      if (typeof w.materialAt === 'function') return w.materialAt(x, y) || 'stone';
    } catch (err) { /* stone */ }
    return 'stone';
  }

  /** True when a solid cell lies on the line from the player to (x,y). */
  function occludedTo(x, y) {
    const p = S.player;
    return !!(p && firstSolid(p.x, p.y, x, y));
  }

  /**
   * Occlusion detail for a world sound at (x,y): null when the line is clear, else {mat, diff}. mat is the first blocking material;
   * diff is the least Maekawa loss (dB) over open doorways that both the player and the sound can see (null when none).
   */
  function occlusionTo(x, y) {
    const w = S.world;
    const p = S.player;
    if (!w || !p) return null;
    const hit = firstSolid(p.x, p.y, x, y);
    if (!hit) return null;
    const out = { mat: blockMaterial(hit.x, hit.y), diff: null };
    const A = VCS.SoundData && VCS.SoundData.acoustics;
    const doors = w.spots && w.spots.doors;
    if (!A || !doors || typeof w.isDoorOpen !== 'function') return out;
    const direct = Math.hypot(x - p.x, y - p.y);
    for (let i = 0; i < doors.length; i++) {
      const dr = doors[i];
      if (!w.isDoorOpen(Math.floor(dr.x), Math.floor(dr.y))) continue;
      const d1 = Math.hypot(dr.x - p.x, dr.y - p.y);
      const d2 = Math.hypot(x - dr.x, y - dr.y);
      if (d1 > A.doorwayReach || d1 + d2 > direct + 12) continue;
      if (firstSolid(p.x, p.y, dr.x, dr.y) || firstSolid(dr.x, dr.y, x, y)) continue;
      const loss = A.maekawa((d1 + d2 - direct) * A.cellM, A.maekawaHz);
      if (out.diff === null || loss < out.diff) out.diff = loss;
    }
    return out;
  }

  /** Audio.play options for a world sound at (x,y): gain, pan, dist, behind, occluded (+ extra fields). */
  function spatial(x, y, gain, extra) {
    const p = S.player;
    const o = { gain: gain, pan: panTo(x, y) };
    if (p) {
      const dx = x - p.x;
      const dy = y - p.y;
      o.dist = Math.hypot(dx, dy);
      o.behind = Math.cos(Math.atan2(dy, dx) - p.angle) < 0;
      const occ = occlusionTo(x, y);
      o.occluded = !!occ;
      if (occ) o.occ = occ;
    }
    if (extra) Object.assign(o, extra);
    return o;
  }

  /** v0.11 floor bounce: each ping also returns a short echo off the floor underfoot, voiced by the floor material (grass ~silent, stone crisp, wood hollow). */
  function floorBounce() {
    const A = VCS.SoundData && VCS.SoundData.acoustics;
    const p = S.player;
    if (!A || !A.floor || !S.audio || S.audio.pingBip === true || !p) return;
    const m = stepMaterial(p.x, p.y);
    const amp = A.floorAmp(m);
    if (amp > 0) VCS.Audio.echo(S.audio, A.floor.delay, amp, 0, { voice: A.matOf(m).voice });
  }

  /** Floor material under (x,y) for footsteps: grass, stone or wood (anything else is stone). */
  function stepMaterial(x, y) {
    let m = 'stone';
    try {
      if (S.world && typeof S.world.materialAt === 'function') m = S.world.materialAt(x, y);
    } catch (err) { /* stone */ }
    return m === 'grass' || m === 'wood' ? m : 'stone';
  }

  /** Footstep sound every step interval while moving. */
  function playerSteps(dt, moved) {
    const moving = dt > 0 && moved / dt > 0.3;
    if (!moving) {
      S.stepTimer = 0;
      return;
    }
    S.stepTimer += dt;
    const iv = level('step').interval || 0.48;
    if (S.stepTimer < iv) return;
    S.stepTimer -= iv;
    // The sound comes from the foot that lands: slightly ahead, alternating left and right.
    const lv = level('step');
    const p = S.player;
    const ahead = typeof lv.footOffset === 'number' ? lv.footOffset : 0.15;
    const side = (typeof lv.footSide === 'number' ? lv.footSide : 0.12) * (S.footRight ? 1 : -1);
    const fx = p.x + Math.cos(p.angle) * ahead + Math.cos(p.angle + Math.PI / 2) * side;
    const fy = p.y + Math.sin(p.angle) * ahead + Math.sin(p.angle + Math.PI / 2) * side;
    const foot = typeof S.world.isSolid === 'function' && S.world.isSolid(fx, fy) ? { x: p.x, y: p.y } : { x: fx, y: fy };
    emitSound('step', foot.x, foot.y);
    if (S.audio) VCS.Audio.play(S.audio, 'step', { gain: lv.gain, foot: S.footRight ? 1 : 0, pan: S.footRight ? 0.25 : -0.25, material: stepMaterial(p.x, p.y) });
    S.footRight = !S.footRight;
  }

  /** True when the circle (x,y,r) overlaps door cell (cx,cy). */
  function overlapsCell(x, y, r, cx, cy) {
    return x > cx - r && x < cx + 1 + r && y > cy - r && y < cy + 1 + r;
  }

  /** Open or close a door cell with its sound. Returns true if it changed. */
  function toggleDoor(cx, cy, wantOpen) {
    const w = S.world;
    if (typeof w.setDoor !== 'function') return false;
    if (w.isDoorOpen(cx, cy) === wantOpen) return false;
    if (!wantOpen) {
      if (overlapsCell(S.player.x, S.player.y, S.player.radius || 0.2, cx, cy)) return false;
      const ps = S.people ? S.people.people : [];
      for (let i = 0; i < ps.length; i++) if (overlapsCell(ps[i].x, ps[i].y, 0.25, cx, cy)) return false;
    }
    w.setDoor(cx, cy, wantOpen);
    const x = cx + 0.5;
    const y = cy + 0.5;
    emitSound('door', x, y);
    reactTo(x, y, 'door');
    if (S.audio) {
      VCS.Audio.play(S.audio, wantOpen ? 'doorOpen' : 'doorClose', spatial(x, y, level('door').gain));
    }
    L().debug('door ' + cx + ',' + cy + (wantOpen ? ' opened' : ' closed'));
    return true;
  }

  /** Walking into a closed door opens it. */
  function bumpDoors(inp) {
    const w = S.world;
    if (typeof w.isDoorOpen !== 'function') return;
    const p = S.player;
    const f = inp.forward;
    const s = inp.strafe;
    if (!f && !s) return;
    const dirx = f * Math.cos(p.angle) + s * Math.cos(p.angle + Math.PI / 2);
    const diry = f * Math.sin(p.angle) + s * Math.sin(p.angle + Math.PI / 2);
    const len = Math.hypot(dirx, diry);
    if (!(len > 0)) return;
    const reach = (p.radius || 0.2) + 0.12;
    const cx = Math.floor(p.x + (dirx / len) * reach);
    const cy = Math.floor(p.y + (diry / len) * reach);
    const ch = w.tileAt(cx + 0.5, cy + 0.5);
    if ((ch === 'D' || ch === 'G') && !w.isDoorOpen(cx, cy)) toggleDoor(cx, cy, true);
  }

  /** E key (doors, crypt, sleep): toggle the nearest door in front, else interact with a crypt or safe spot. Returns what happened. */
  function interact() {
    const w = S.world;
    const p = S.player;
    if (!w || !p || S.state !== 'playing') return 'none';
    const reach = (VCS.SoundData && VCS.SoundData.reach) || 1.3;
    const arc = (VCS.SoundData && VCS.SoundData.reachArc) || Math.PI / 3;
    let best = null;
    let bestD = Infinity;
    const doors = interactDoors(w);
    for (let i = 0; i < doors.length; i++) {
      const d = Math.hypot(doors[i].x - p.x, doors[i].y - p.y);
      if (d > reach || d >= bestD) continue;
      let da = Math.atan2(doors[i].y - p.y, doors[i].x - p.x) - p.angle;
      da = Math.atan2(Math.sin(da), Math.cos(da));
      if (Math.abs(da) > arc && d > 0.7) continue;
      best = doors[i];
      bestD = d;
    }
    if (best && typeof w.isDoorOpen === 'function') {
      const cx = Math.floor(best.x);
      const cy = Math.floor(best.y);
      return toggleDoor(cx, cy, !w.isDoorOpen(cx, cy)) ? 'door' : 'blocked';
    }
    if (trySleep()) return 'sleep';
    if (S.sleepDenied) return 'blocked';
    const spots = (w.spots.crypt || []).concat((w.spots.safe || []).filter(function (sp) { return !isSealed(sp); }));
    for (let i = 0; i < spots.length; i++) {
      if (Math.hypot(spots[i].x - p.x, spots[i].y - p.y) <= reach) {
        emitSound('interact', spots[i].x, spots[i].y);
        if (S.audio) VCS.Audio.play(S.audio, 'interact', spatial(spots[i].x, spots[i].y, level('interact').gain));
        return 'interact';
      }
    }
    return 'none';
  }

  /** People step pulses with attenuated, panned audio; people open closed doors they walk up to. */
  function peopleSounds(tPrev) {
    if (typeof VCS.People.stepEvents === 'function') {
      const out = S.stepOut;
      out.length = 0;
      try {
        VCS.People.stepEvents(S.people, tPrev, S.clock, out);
      } catch (err) {
        L().warn('People.stepEvents failed', err);
        out.length = 0;
      }
      const lv = level('personStep');
      for (let i = 0; i < out.length; i++) {
        const e = out[i];
        const mat = stepMaterial(e.x, e.y);
        const sc = VCS.SoundData.stepScale(e.gait, mat, e.pace);
        // The foot lands a little to the left or right of the body; the ring is a flat scuff stretched along the heading.
        const side = (e.foot ? 1 : -1) * 0.12;
        const fx = e.x - Math.sin(e.angle) * side;
        const fy = e.y + Math.cos(e.angle) * side;
        const spu = emitSound('personStep', fx, fy, { rangeMul: sc.range, strengthMul: sc.strength, fadeMul: sc.fade });
        if (spu) spu.hd = e.angle;
        if (S.audio) VCS.Audio.play(S.audio, 'personStep', spatial(e.x, e.y, Math.min(1, lv.gain * sc.gain), { material: mat }));
      }
    }
    // Choice: people open any closed door they come within 1 cell of; it stays open.
    const w = S.world;
    if (typeof w.isDoorOpen === 'function') {
      const doors = w.spots.doors;
      const ps = S.people.people;
      for (let i = 0; i < ps.length; i++) {
        for (let k = 0; k < doors.length; k++) {
          const cx = Math.floor(doors[k].x);
          const cy = Math.floor(doors[k].y);
          if (!w.isDoorOpen(cx, cy) && Math.hypot(ps[i].x - doors[k].x, ps[i].y - doors[k].y) < 1.0) toggleDoor(cx, cy, true);
        }
      }
    }
  }

  /** Move people, take echo snapshots where wavefronts cross them, spawn ripples. */
  function simulateWorld(dt) {
    if (!S.people || !S.ripple) return;
    const tPrev = S.clock - dt;
    const pc = peopleCtx();
    VCS.People.update(S.people, S.world, dt, pc);
    drainPeopleEvents();
    peopleSounds(tPrev);
    const made = VCS.People.updateEchoes(S.people, S.sonar, tPrev, S.clock);
    const p = S.player;
    if (made.length) tutQueue('person');
    for (let i = 0; i < made.length; i++) {
      const e = made[i];
      // Floor rings under the person: a heartbeat is a small ring at the chest's foot, a footstep a modest one, a ping the full size.
      const small = e.kind === 'vheart' ? 0.4 : e.kind === 'personStep' || e.kind === 'step' ? 0.45 : 1;
      VCS.Ripple.spawn(S.ripple, e.x, e.y, S.clock, { kind: 'person', maxR: 1.6 * small, life: 0.9 * (small < 1 ? 0.7 : 1), strength: e.strength });
      if (small === 1) VCS.Ripple.spawn(S.ripple, e.x, e.y, S.clock, { kind: 'person', maxR: 1.2, life: 0.8, strength: e.strength * 0.6, delay: 0.18 });
      e.pan = clamp(Math.sin(Math.atan2(e.y - p.y, e.x - p.x) - p.angle), -1, 1);
      if (S.audio) personEcho(e);
    }
    markerRipples(tPrev, S.clock);
    VCS.Ripple.prune(S.ripple, S.clock);
  }

  const PERSON_ECHO_GAIN = 1; // level of a villager's ping echo (was turned down to 0.5/0.08/0.03 while chasing the footstep bug)

  /** Audible echo of a person snapshot: object sonar equation (-40 log r + TS + class gain), not the old 0.7 * strength. */
  function personEcho(e) {
    // Only the player's own ping comes back to the player as an echo. World sounds (villager footsteps, doors) light the
    // person visually but are not echoes you hear; playing them made every step of every villager thump in the ear.
    if (e.kind && e.kind !== 'ping') return;
    const A = VCS.SoundData && VCS.SoundData.acoustics;
    const amp = (A ? clamp(A.personAmp(e.dist, e.theta), 0.1, 0.7) : clamp(0.7 * e.strength, 0.1, 0.7)) * PERSON_ECHO_GAIN;
    VCS.Audio.echo(S.audio, clamp(e.dist / S.sonar.speed, 0, 6), amp, e.pan, { voice: 'person' });
  }

  /** Spawn one small ring on each crypt/safe/door spot a wavefront crossed this frame. */
  function markerRipples(tPrev, t) {
    const spots = S.world.spots;
    const pulses = S.sonar.pulses;
    const Sonar = VCS.Sonar;
    const kinds = ['crypt', 'safe', 'doors'];
    for (let k = 0; k < pulses.length; k++) {
      const pu = pulses[k];
      for (let a = 0; a < kinds.length; a++) {
        const list = spots[kinds[a]] || [];
        for (let i = 0; i < list.length; i++) {
          const sp = list[i];
          const la = Sonar.litAt(pu, sp.x, sp.y);
          if (!(la > tPrev && la <= t)) continue;
          if ((la - pu.t0) * pu.speed > pu.range) continue;
          if (!Sonar.visibleFrom(pu, sp.x, sp.y)) continue;
          VCS.Ripple.spawn(S.ripple, sp.x, sp.y, la, { kind: 'marker', maxR: 0.8, life: 0.6, strength: 0.7 });
        }
      }
    }
  }

  /** Advance the walk cycle; moved is distance travelled this frame. */
  function updateBob(dt, moved) {
    const moving = dt > 0 && moved / dt > 0.3;
    const speed = moving ? moved / dt : 0;
    S.bobAmp = clamp(S.bobAmp + (moving ? dt : -dt) * 8, 0, 1);
    if (moving) {
      S.walkPhase += speed * dt * 7;
      S.stepCount = Math.floor(S.walkPhase / Math.PI);
    }
    const on = S.config.headBob !== false && !S.reduced;
    S.bob = on ? Math.sin(S.walkPhase) * 2.5 * S.bobAmp : 0;
  }

  /** Emit a sonar pulse from the player with audio ping and echo; true if emitted. */
  function pulse() {
    const p = S.player;
    const pkind = S.world.kindAt(p.x, p.y);
    const room = roomProfile(S.world, pkind);
    room.outdoor = pkind === 'outdoor';
    const b = S.baseSonar;
    const sn = S.sonar;
    const keep = { range: sn.range, bounces: sn.bounces, fade: sn.fade };
    const weak = S.night ? VCS.Night.weakness(S.night) : 0;
    const wash = S.night && room.outdoor ? VCS.Night.washK(S.night) : 0;
    if (b) {
      sn.range = b.range * room.rangeMul * fxv('sonarRange') * (1 - 0.4 * weak) * (1 - 0.5 * wash);
      sn.bounces = Math.min(b.bounces, room.bounceCap);
      sn.fade = b.fade * room.fadeMul * fxv('sonarFade') * (1 - 0.3 * weak) * (1 - 0.6 * wash);
    }
    const fired = VCS.Sonar.emit(sn, S.world, p.x, p.y, S.clock, { z: level('ping').z, facing: p.angle });
    sn.range = keep.range;
    sn.bounces = keep.bounces;
    sn.fade = keep.fade;
    if (!fired) return false;
    tutPulsed();
    if (weak > 0 && S.sonar.lastPulse) tagWeak(S.sonar.lastPulse, weak, 1 - 0.4 * weak);
    tagPingHeight();
    reactTo(p.x, p.y, 'ping');
    const a = S.audio;
    VCS.Audio.ping(a);
    pingEcho(S.sonar.lastPulse);
    floorBounce();
    bounceEchoes();
    return true;
  }

  /** The audible wall echo of a ping pulse lp. */
  function pingEcho(lp) {
    const a = S.audio;
    const p = S.player;
    if (!lp) return;
    const A = VCS.SoundData && VCS.SoundData.acoustics;
    // v0.11: the loudest wall return (beam B(theta) once, spread, material, air) with its material voice, grain tail and near-wall comb.
    const best = A ? VCS.Sonar.strongestEcho(lp, p.angle) : null;
    if (best) {
      const opts = { voice: A.matOf(best.mat).voice, rough: best.rough, rp: A.repetition(best.dist) };
      VCS.Audio.echo(a, clamp(VCS.Sonar.echoDelay(best.dist, S.sonar.speed), 0, 6), A.gameAmp(best.level), echoPan(lp), opts);
    } else {
      const nearest = VCS.Sonar.nearestDist(lp);
      const range = lp.range || 10;
      VCS.Audio.echo(a, clamp(VCS.Sonar.echoDelay(nearest, S.sonar.speed), 0, 6), clamp(1 - nearest / range, 0.15, 1), echoPan(lp));
    }
  }

  /** Sonar.emit may not set a source height; give the new ping and its bounces the ping height (head, 0.62) and fade. */
  function tagPingHeight() {
    try {
      const z = level('ping').z;
      if (typeof z !== 'number') return;
      const ps = S.sonar.pulses;
      for (let i = 0; i < ps.length; i++) {
        const c = ps[i];
        if (c.kind === 'ping' && c.t0 >= S.clock - 1e-6 && c.z === 0.5) c.z = z;
      }
      if (S.sonar.lastPulse && S.sonar.lastPulse.z === 0.5) S.sonar.lastPulse.z = z;
    } catch (err) {
      L().warn('tagPingHeight failed', err);
    }
  }

  /** Quiet panned echoes for the first few bounce children of the ping just emitted. */
  function bounceEchoes() {
    if (!S.audio) return;
    const ps = S.sonar.pulses;
    const max = (VCS.SoundData && VCS.SoundData.maxBounceEchoes) || 4;
    const picks = [];
    for (let i = 0; i < ps.length; i++) {
      const c = ps[i];
      if (!(c.gen > 0) || !(c.t0 >= S.clock - 1e-6) || c.kind === 'door' || c.kind === 'interact') continue;
      picks.push(c);
    }
    picks.sort(function (a, b) { return a.t0 - b.t0; });
    for (let i = 0; i < picks.length && i < max; i++) {
      const c = picks[i];
      const dc = Math.sqrt((c.x - S.player.x) * (c.x - S.player.x) + (c.y - S.player.y) * (c.y - S.player.y));
      const delay = c.t0 - S.clock + dc / (c.speed || S.sonar.speed);
      if (delay > 2) continue;
      const A = VCS.SoundData && VCS.SoundData.acoustics;
      VCS.Audio.echo(S.audio, delay, clamp(0.35 * (c.strength || 0.4), 0.05, 0.3), panTo(c.x, c.y), A ? { voice: A.matOf(c.mat).voice } : undefined);
    }
  }

  /** Stereo pan (-1..1): 1/dist-weighted circular mean of visible walls within 60 deg of facing (0 if none). */
  function echoPan(lp) {
    try {
      const v = lp && lp.vis;
      if (!v || !v.length || !S.player) return 0;
      const n = v.length;
      const lim = Math.PI / 3;
      let ss = 0;
      let sc = 0;
      for (let i = 0; i < n; i++) {
        const d = v[i];
        if (!(d > 0) || !isFinite(d)) continue;
        const rel = Math.atan2(Math.sin((i / n) * Math.PI * 2 - S.player.angle), Math.cos((i / n) * Math.PI * 2 - S.player.angle));
        if (Math.abs(rel) > lim) continue;
        const w = 1 / d;
        ss += Math.sin(rel) * w;
        sc += Math.cos(rel) * w;
      }
      if (ss === 0 && sc === 0) return 0;
      return clamp(Math.sin(Math.atan2(ss, sc)), -1, 1);
    } catch (err) {
      return 0;
    }
  }

  /** Clamp v into [lo, hi]. */
  function clamp(v, lo, hi) {
    return v < lo ? lo : v > hi ? hi : v;
  }

  /** Draw the title backdrop: slow concentric rings from the centre. */
  function drawTitle() {
    const c = S.ctx;
    c.globalCompositeOperation = 'source-over';
    c.globalAlpha = 1;
    if (!S.cryptBad && VCS.Icons && typeof VCS.Icons.drawCryptMenu === 'function') {
      let ok = false;
      try {
        ok = VCS.Icons.drawCryptMenu(c, W, H, S.reduced ? 3.3 : S.titleT) !== false;
      } catch (err) {
        L().warn('drawCryptMenu failed', err);
      }
      if (ok) {
        c.globalAlpha = 1;
        drawTitleText(c, S.reduced ? 0 : S.titleT, -92);
        return;
      }
      S.cryptBad = true;
      L().warn('Crypt menu backdrop unavailable, using rings');
    }
    c.fillStyle = '#000';
    c.fillRect(0, 0, W, H);
    c.strokeStyle = '#cfe3ff';
    c.lineWidth = 1;
    const life = 6.6;
    const gap = 2.2;
    const speed = 52;
    const t = S.reduced ? 3.3 : S.titleT;
    const first = Math.floor((t - life) / gap) + 1;
    for (let k = first; k * gap <= t; k++) {
      const age = t - k * gap;
      if (age < 0 || age > life) continue;
      const f = age / life;
      c.globalAlpha = 0.45 * (1 - f) * (1 - f) * Math.min(1, age / 0.4);
      c.beginPath();
      c.arc(W / 2, H / 2, 8 + age * speed, 0, Math.PI * 2);
      c.stroke();
    }
    c.globalAlpha = 1;
    drawTitleText(c, S.reduced ? 0 : S.titleT, 0);
  }

  /** Stable pseudo-random 0..1 from an integer pair (for line boil). */
  function hash2(i, f) {
    const v = Math.sin(i * 12.9898 + f * 78.233) * 43758.5453;
    return v - Math.floor(v);
  }

  /** Draw the quirky title: outline letters that boil at 10 fps on an uneven baseline, a flapping bat squiggle, and the subtitle. */
  function drawTitleText(c, t, yOff) {
    const boil = !S.reduced && (!S.config || S.config.lineBoil !== false);
    const frame = boil ? Math.floor(t * 10) % 4 : 0;
    const text = "VAMPIRES CAN'T SEE";
    c.save();
    c.globalCompositeOperation = 'source-over';
    c.strokeStyle = '#cfe3ff';
    c.fillStyle = 'rgba(207, 227, 255, 0.12)';
    c.lineJoin = 'round';
    c.lineCap = 'round';
    c.lineWidth = 1.4;
    c.textBaseline = 'middle';
    c.textAlign = 'center';
    c.font = 'bold 30px ui-monospace, Menlo, Consolas, monospace';
    const adv = 27;
    const x0 = W / 2 - ((text.length - 1) * adv) / 2;
    for (let i = 0; i < text.length; i++) {
      const ch = text.charAt(i);
      if (ch === ' ') continue;
      const j = boil ? 1.1 : 0;
      const dx = (hash2(i, frame) - 0.5) * 2 * j;
      const dy = (hash2(i + 40, frame) - 0.5) * 2 * j;
      const rot = (hash2(i + 80, frame) - 0.5) * 0.1 * (boil ? 1 : 0);
      const base = Math.sin(i * 1.7) * 3.2 + (hash2(i, 9) - 0.5) * 3;
      c.save();
      c.translate(x0 + i * adv + dx, H / 2 + yOff + base + dy);
      c.rotate(rot + Math.sin(i * 2.3) * 0.05);
      c.fillText(ch, 0, 0);
      c.strokeText(ch, 0, 0);
      c.restore();
    }
    // bat squiggle: two scalloped wings and a tiny body
    const flap = boil || !S.reduced ? Math.sin(t * 4) * 5 : 0;
    const bx = W / 2;
    const by = H / 2 + yOff - 48;
    const jit = function (k) { return boil ? (hash2(k, frame + 17) - 0.5) * 1.6 : 0; };
    c.lineWidth = 1.2;
    c.globalAlpha = 0.9;
    c.beginPath();
    for (let side = -1; side <= 1; side += 2) {
      c.moveTo(bx + side * 3, by);
      c.quadraticCurveTo(bx + side * 12, by - 12 - flap + jit(1), bx + side * 26 + jit(2), by - 6 - flap * 1.4);
      c.quadraticCurveTo(bx + side * 22, by + 1 + jit(3), bx + side * 19, by + 3 - flap * 0.4);
      c.quadraticCurveTo(bx + side * 14, by - 1 + jit(4), bx + side * 10, by + 4);
      c.quadraticCurveTo(bx + side * 6, by + 1, bx + side * 3, by + 6);
    }
    c.stroke();
    c.beginPath();
    c.ellipse(bx, by + 1 + jit(5), 3, 5, 0, 0, Math.PI * 2);
    c.moveTo(bx - 2.5, by - 4);
    c.lineTo(bx - 3.5, by - 8);
    c.moveTo(bx + 2.5, by - 4);
    c.lineTo(bx + 3.5, by - 8);
    c.stroke();
    // subtitle (only on the plain title; the menu has its own buttons)
    if (!yOff) {
      c.globalAlpha = 0.6 + (S.reduced ? 0 : 0.2 * Math.sin(t * 2.2));
      c.fillStyle = '#cfe3ff';
      c.font = '13px ui-monospace, Menlo, Consolas, monospace';
      c.fillText('c l i c k   t o   l i s t e n', W / 2 + (boil ? (hash2(3, frame) - 0.5) * 0.8 : 0), H / 2 + 46);
    }
    c.restore();
    c.globalAlpha = 1;
  }

  /** Plain crosshair dot and the cooldown arc (fades in and out over 0.15 s); fallback when Hud fails. */
  function drawPlainHud() {
    const c = S.ctx;
    c.globalCompositeOperation = 'source-over';
    c.fillStyle = '#ffffff';
    c.globalAlpha = 0.3;
    c.fillRect(W / 2 - 1, H / 2 - 1, 2, 2);
    if (S.hudA > 0.01) {
      c.globalAlpha = 0.5 * S.hudA;
      c.strokeStyle = '#cfe3ff';
      c.lineWidth = 0.75;
      c.beginPath();
      c.arc(W / 2, H - 18, 6, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * S.hudFrac);
      c.stroke();
    }
    c.globalAlpha = 1;
  }

  /** Draw one frame. */
  function render() {
    const r = S.renderer;
    if (S.state === 'title' || !S.world || !S.player) {
      drawTitle();
      return;
    }
    if (S.view === 'top') {
      VCS.Render.drawTopDown(r, S.world, S.player, S.sonar, S.clock, { people: S.people });
    } else {
      const ro = { bob: S.bob, people: S.people, ripple: S.ripple, lit: S.playerLit, debug: S.debugEnabled };
      const wr = fxv('warmRadius');
      if (wr > 0 && S.people) ro.warm = { radius: wr, people: S.people.people.map(function (p) { return { x: p.x, y: p.y }; }) };
      const dk = S.drink;
      if (dk) ro.feedLock = { id: dk.id, k: clamp(dk.drunk / dk.pool, 0, 1), age: dk.t, sp: dk.t - dk.lastStruggle, rs: dk.rs };
      if (S.reduced) {
        if (dk) ro.vignette = 0.3;
      } else if (S.fovK > 0) {
        const e = S.fovK * S.fovK * (3 - 2 * S.fovK);
        ro.vignette = e;
        const base = cfgNum('fovDeg', 66) * Math.PI / 180;
        ro.fov = base * (1 - (1 - GRAB_FOV) * e);
      }
      VCS.Render.drawFirstPerson(r, S.world, S.player, S.sonar, S.clock, ro);
    }
    if (S.state === 'runend') {
      drawFade(0.78);
      return;
    }
    if (S.state === 'boon') {
      drawFade(0.97);
      return;
    }
    if (S.state === 'gift') {
      drawFade(0.9);
      return;
    }
    const wiping = !!(S.transition && S.wipeK > 0);
    if (wiping) VCS.Render.drawWipe(r, S.wipeK);
    const n = S.night;
    if (!n) {
      if (!wiping) drawPlainHud();
      return;
    }
    if (!S.hudBad) {
      try {
        drawNightHud(n, wiping);
      } catch (err) {
        S.hudBad = true;
        L().error('Hud failed, falling back to plain crosshair', err);
      }
    }
    if (S.hudBad && !wiping) drawPlainHud();
    if (S.seq) drawFade(seqFade(S.seq));
  }

  /** Fade-to-black amount (0..1) of the sleep sequence. */
  function seqFade(q) {
    const t = q.t;
    return t < 0.8 ? t / 0.8 : t < 1.4 ? 1 : clamp(1 - (t - 1.4) / 0.8, 0, 1);
  }

  /** Black overlay with alpha k. */
  function drawFade(k) {
    if (!(k > 0)) return;
    try {
      if (!S.hudBad && VCS.Hud) VCS.Hud.drawFade(S.ctx, k);
      else {
        S.ctx.globalAlpha = k;
        S.ctx.fillStyle = '#000';
        S.ctx.fillRect(0, 0, W, H);
        S.ctx.globalAlpha = 1;
      }
    } catch (err) {
      S.hudBad = true;
      L().error('Hud.drawFade failed', err);
    }
  }

  /** Draw dawn grain, the HUD and the active card. */
  function drawNightHud(n, wiping) {
    const Hud = VCS.Hud;
    const c = S.ctx;
    const boil = !S.reduced && (!S.config || S.config.lineBoil !== false);
    const dk = VCS.Night.dawnK(n);
    if (dk > 0) Hud.drawDawn(S.hud, c, dk, S.clock, S.reduced);
    if (wiping) return;
    const m = Math.floor(n.min);
    if (m !== S.clkMin) {
      const ck = VCS.Night.clock(n);
      S.clkMin = m;
      S.clkHour = ck.hour;
      S.clkMinute = ck.minute;
    }
    const hs = S.hs;
    hs.blood01 = n.bloodMax > 0 ? n.blood / n.bloodMax : 0;
    hs.weak = VCS.Night.weakness(n);
    hs.frac = n.min / 600;
    hs.hour = S.clkHour;
    hs.minute = S.clkMinute;
    hs.t = S.clock;
    hs.boil = boil;
    hs.reduced = S.reduced;
    hs.largeText = cfgOn('largeText');
    HOPTS.largeText = hs.largeText;
    HOPTS.reduced = S.reduced;
    hs.pulse01 = S.hudA > 0.01 ? S.hudA * S.hudFrac : 0;
    hs.vialPulse = S.vialPulse;
    hs.feeding = !!S.drink;
    hs.veil = S.veilK;
    hs.rocks = S.rocksLeft;
    feedHunger(hs, n);
    Hud.drawHud(S.hud, c, hs);
    if (S.cardText !== null) Hud.drawCard(S.hud, c, S.cardText, S.cardAge, S.clock, boil, S.cardSub || undefined, HOPTS);
    else if (S.hintT > 0) drawHint(c);
    else if (S.tutCur) {
      HOPTS.dur = S.tutCur.dur;
      Hud.drawHint(S.hud, c, S.tutCur.text, S.tutAge, S.clock, HOPTS);
    }
    drawSaveDot(c);
  }

  /** Tiny "not saved" dot while the last write failed or saving is paused by another tab. */
  function drawSaveDot(c) {
    if (!S.saveFailed && !S.otherTab) return;
    try {
      c.save();
      c.globalAlpha = 0.7;
      c.fillStyle = '#ff8a78';
      c.beginPath();
      c.arc(628, 351, 2.5, 0, Math.PI * 2);
      c.fill();
      c.font = '9px ui-monospace, Menlo, Consolas, monospace';
      c.textAlign = 'right';
      c.textBaseline = 'middle';
      c.fillText('not saved', 622, 351);
      c.restore();
    } catch (e) { /* ignore */ }
  }

  /** Fill the v0.9 HUD fields (overflow, powers, fear, still, mist, gift flash). Reuses its arrays. */
  function feedHunger(hs, n) {
    const h = S.hunger;
    if (!h) return;
    const Hg = VCS.Hunger;
    hs.overOpen = Hg.isOpen(h) && n.blood >= n.bloodMax;
    hs.over01 = Hg.over01(h);
    hs.fear = h.fear;
    hs.still01 = h.stillLeft > 0 ? Math.min(1, h.stillLeft / Hg.STILL_SECS) : 0;
    hs.mistK = S.mistVis;
    if (S.giftFlash > 0) S.giftFlash = Math.max(0, S.giftFlash - 1 / 90);
    hs.giftFlash = S.giftFlash;
    const ps = VCS.HungerData.powers;
    if (!S.powerRows) {
      S.powerRows = [];
      for (let i = 0; i < ps.length; i++) S.powerRows.push({ id: ps[i].id, state: 'locked', cd01: 0, key: POWER_KEYS[ps[i].id] || '' });
    }
    const arr = S.powerArr;
    arr.length = 0;
    for (let i = 0; i < ps.length; i++) {
      const row = S.powerRows[i];
      row.state = Hg.powerState(h, ps[i].id, n.night, n.blood);
      row.cd01 = Hg.cdLeft01(h, ps[i].id);
      if (row.state !== 'locked') arr.push(row);
    }
    hs.powers = arr;
  }

  /** Count ERROR entries in the log buffer. */
  function errorCount() {
    try {
      return VCS.Log.entries().filter(function (e) { return e.level === 'ERROR'; }).length;
    } catch (e) {
      return 0;
    }
  }

  /** Update the F3 overlay text. */
  function updateDebug() {
    if (!S.debugOn || !S.els.debug || !S.player) return;
    const p = S.player;
    let last = '';
    try {
      const es = VCS.Log.entries();
      if (es.length) last = VCS.Log.format(es[es.length - 1]);
    } catch (e) { /* ignore */ }
    S.els.debug.textContent = 'FPS ' + S.fps + '\n' +
      'x ' + p.x.toFixed(2) + ' y ' + p.y.toFixed(2) + ' a ' + p.angle.toFixed(2) + '\n' +
      'state ' + S.state + ' view ' + S.view + '\n' +
      'pulses ' + (S.sonar ? S.sonar.pulses.length : 0) +
      ' cd ' + (S.sonar ? VCS.Sonar.cooldownLeft(S.sonar, S.clock).toFixed(2) : '0') +
      ' lit ' + (S.renderer ? VCS.Render.stats(S.renderer).litColumns : 0) + '\n' +
      'people ' + (S.people ? S.people.people.length : 0) +
      ' echoes ' + (S.people ? S.people.echoes.length : 0) +
      ' rings ' + (S.ripple ? S.ripple.rings.length : 0) + '\n' + schedLines() + last;
  }

  /** V1 debug readout (?debug=1): role, now, next stop and ETA for the 6 nearest scheduled villagers. */
  function schedLines() {
    if (!S.debugEnabled || !S.people || !S.player) return '';
    const near = [];
    const list = S.people.people;
    for (let i = 0; i < list.length; i++) {
      const q = list[i];
      if (!q.sched) continue;
      near.push({ q: q, d: Math.hypot(q.x - S.player.x, q.y - S.player.y) });
    }
    near.sort(function (a, b) { return a.d - b.d; });
    let out = '';
    for (let i = 0; i < near.length && i < 6; i++) {
      const q = near[i].q;
      const s = q.sched;
      const cur = s.stops[s.si];
      const nx = s.stops[Math.min(s.stops.length - 1, Math.max(0, s.si) + 1)];
      const eta = VCS.Schedule.eta(s.stops, Math.max(0, s.si), S.pctx.nightFrac, S.pctx.nightSec);
      out += s.role + ' ' + (cur ? cur.place + ':' + cur.act : '-') + (s.en ? ' >' : ' @') + ' next ' + (nx ? nx.place : '-') +
        ' eta ' + (typeof eta === 'number' && isFinite(eta) ? Math.round(eta) + 's' : '-') + (s.homeEarly ? ' HOME' : '') + ' d' + near[i].d.toFixed(0) + '\n';
    }
    return out;
  }

  /** One animation frame. */
  function frame(t) {
    if (!S.running) return;
    try {
      const dt = Math.min(0.1, Math.max(0, (t - S.lastT) / 1000));
      S.lastT = t;
      S.uiT += dt;
      if (S.state === 'title') S.titleT += dt;
      update(dt);
      if (VCS.Sys && VCS.Sys.count() > 0) VCS.Sys.update(dt, S);
      updateAmbience();
      render();
      drawUiCanvases();
      S.frameErrs = 0;
      S.frames++;
      S.fpsAcc += dt;
      S.debugAcc += dt;
      if (S.fpsAcc >= 1) {
        S.fps = Math.round(S.frames / S.fpsAcc);
        L().debug('fps ' + S.fps);
        S.frames = 0;
        S.fpsAcc = 0;
      }
      if (S.debugAcc >= 0.25) {
        S.debugAcc = 0;
        updateDebug();
      }
    } catch (err) {
      const em = (err && err.message) || String(err);
      S.frameErrs++;
      L().error('Frame error ' + S.frameErrs + '/3: ' + em, err);
      if (S.frameErrs >= 3) {
        fatal('E_LOOP', S.transition ? 'Map transition failed: ' + em : em, err);
        return;
      }
    }
    S.rafId = root.requestAnimationFrame(frame);
  }

  /** Show the settings panel (true) or the main pause buttons (false). */
  function showSettings(on) {
    show($('settings'), on);
    show($('pause-main'), !on);
    if (on) {
      syncControls();
      const first = $('set-sens');
      if (first && first.focus) first.focus();
    } else {
      const b = $(S.state === 'paused' ? 'btn-resume' : 'btn-settings');
      if (b && b.focus) b.focus();
    }
  }

  /** Set a range/checkbox/select control and its read-out from the config. */
  function syncControls() {
    const c = S.config;
    if (!c) return;
    const set = function (id, prop, val) {
      const el = $(id);
      if (el) el[prop] = val;
    };
    set('set-sens', 'value', String(c.mouseSensitivity));
    set('set-invert', 'checked', !!c.invertMouse);
    set('set-volume', 'value', String(c.volume));
    set('set-scale', 'value', String(c.renderScale));
    set('set-fov', 'value', String(c.fovDeg));
    set('set-night', 'value', String(c.nightLengthMin));
    set('set-bob', 'checked', c.headBob !== false);
    set('set-boil', 'checked', c.lineBoil !== false);
    set('set-keyturn', 'value', String(c.keyTurnSpeed));
    set('set-draglook', 'checked', c.dragLook !== false);
    set('set-feedtoggle', 'checked', c.feedToggle === true);
    set('set-reduce', 'checked', c.reduceMotion === true);
    set('set-vignette', 'checked', c.edgeVignette !== false);
    set('set-bip', 'checked', c.pingBip === true);
    set('set-large', 'checked', c.largeText === true);
    set('set-ambience', 'value', String(typeof c.ambienceGain === 'number' ? c.ambienceGain : 0.6));
    const out = function (id, text) {
      const el = $(id);
      if (el) el.textContent = text;
    };
    out('out-sens', (c.mouseSensitivity * 1000).toFixed(1));
    out('out-volume', Math.round(c.volume * 100) + '%');
    out('out-ambience', Math.round((typeof c.ambienceGain === 'number' ? c.ambienceGain : 0.6) * 100) + '%');
    out('out-fov', Math.round(c.fovDeg) + '°');
    out('out-night', Math.round(c.nightLengthMin) + ' min');
    out('out-keyturn', Number(c.keyTurnSpeed).toFixed(1));
  }

  /** Push current config into live systems (audio volume, renderer). */
  function applyConfig() {
    if (S.audio) VCS.Audio.setVolume(S.audio, S.config.volume);
    applyMotion();
    updateAmbience();
    if (S.renderer && typeof VCS.Render.setConfig === 'function') {
      try {
        VCS.Render.setConfig(S.renderer, S.config);
      } catch (err) {
        L().error('Render.setConfig failed', err);
      }
    }
    syncControls();
  }

  /** Combine the OS reduced-motion preference with the setting; push it to the renderer; toggle large text. */
  function applyMotion() {
    S.reduced = S.osReduced || cfgOn('reduceMotion');
    if (S.audio && typeof VCS.Audio.setPingStyle === 'function') VCS.Audio.setPingStyle(S.audio, cfgOn('pingBip'));
    if (S.renderer) S.renderer.reduced = S.reduced;
    try {
      const b = root.document && root.document.body;
      if (b && b.classList) b.classList.toggle('large-text', cfgOn('largeText'));
      if (b && b.classList) b.classList.toggle('no-vignette', S.config && S.config.edgeVignette === false);
    } catch (e) { /* ignore */ }
  }

  /** Persist the config. */
  function saveConfig() {
    if (!VCS.Config.save(S.config)) L().warn('Settings could not be saved');
  }

  /** Wire the settings controls. */
  function wireSettings() {
    if (S.settingsBound) return;
    S.settingsBound = true;
    const bind = function (id, evt, fn) {
      const el = $(id);
      if (el) el.addEventListener(evt, fn);
    };
    const num = function (id, key) {
      const read = function () {
        const v = parseFloat($(id).value);
        if (isFinite(v)) S.config[key] = v;
        applyConfig();
      };
      bind(id, 'input', read);
      bind(id, 'change', function () { read(); saveConfig(); });
    };
    num('set-sens', 'mouseSensitivity');
    num('set-volume', 'volume');
    num('set-ambience', 'ambienceGain');
    num('set-fov', 'fovDeg');
    num('set-night', 'nightLengthMin');
    num('set-scale', 'renderScale');
    num('set-keyturn', 'keyTurnSpeed');
    const flag = function (id, key) {
      bind(id, 'change', function () {
        S.config[key] = !!$(id).checked;
        applyConfig();
        saveConfig();
      });
    };
    flag('set-invert', 'invertMouse');
    flag('set-bob', 'headBob');
    flag('set-boil', 'lineBoil');
    flag('set-draglook', 'dragLook');
    flag('set-feedtoggle', 'feedToggle');
    flag('set-reduce', 'reduceMotion');
    flag('set-vignette', 'edgeVignette');
    flag('set-bip', 'pingBip');
    flag('set-large', 'largeText');
    bind('btn-reset', 'click', function () {
      Object.assign(S.config, VCS.Config.DEFAULTS);
      applyConfig();
      saveConfig();
      L().info('Settings reset to defaults');
    });
    bind('btn-settings', 'click', function () { showSettings(true); });
    bind('btn-abilities', 'click', function () { openGuide('pause'); });
    bind('btn-settings-back', 'click', function () { showSettings(false); });
  }

  /** Fit the canvas to the window keeping 16:9. */
  function fitCanvas() {
    const k = Math.min(root.innerWidth / W, root.innerHeight / H);
    if (!(k > 0)) return;
    S.canvas.style.width = Math.floor(W * k) + 'px';
    S.canvas.style.height = Math.floor(H * k) + 'px';
  }

  /** Wire overlay buttons. */
  function wire() {
    const on = function (id, fn) {
      const el = $(id);
      if (el) el.addEventListener('click', fn);
    };
    on('btn-resume', resume);
    on('btn-pause-log', downloadLog);
    on('btn-pause-report', copyReport);
    on('btn-err-report', copyReport);
    on('btn-err-log', downloadLog);
    on('btn-err-reload', function () { root.location.reload(); });
    const g = function (name, fn) {
      return function () {
        try {
          fn();
        } catch (err) {
          L().error(name + ' failed', err);
        }
      };
    };
    on('btn-newrun', g('New run', beginRun));
    on('btn-crypt', g('Crypt', toCrypt));
    on('btn-notice-ok', function () {
      show(S.els.notice, false);
      const list = S.els.noticeList;
      while (list && list.firstChild) list.removeChild(list.firstChild);
    });
    on('btn-continue', g('Continue', continueRun));
    on('btn-menu-new', g('Menu new run', function () { menuNewRun(false); }));
    on('btn-shop', g('Shop', function () { showMenuView('shop'); }));
    on('btn-stats', g('Stats', function () { showMenuView('stats'); }));
    on('btn-guide', g('Guide', function () { openGuide('menu'); }));
    on('btn-guide-back', g('Guide back', closeGuide));
    on('btn-shop-back', function () { showMenuView('main'); });
    on('btn-stats-back', function () { showMenuView('main'); });
    on('btn-export', g('Export', exportSave));
    on('btn-import', g('Import', function () {
      if (S.els.fileImport) S.els.fileImport.click();
    }));
    if (S.els.fileImport) S.els.fileImport.addEventListener('change', g('Import file', onImportFile));
    root.addEventListener('resize', fitCanvas);
    root.document.addEventListener('visibilitychange', function () {
      if (root.document.hidden) saveRun('hidden');
    });
    root.addEventListener('pagehide', function () {
      saveRun('pagehide');
      releaseTab();
    });
    root.document.addEventListener('keydown', menuArrows);
  }

  /** Arrow keys move focus between the buttons of the menu grid (2 columns) and the pause list. */
  function menuArrows(e) {
    try {
      const k = e && e.key;
      if (k !== 'ArrowUp' && k !== 'ArrowDown' && k !== 'ArrowLeft' && k !== 'ArrowRight') return;
      let cont = null;
      let cols = 1;
      if (S.state === 'title' && S.menuView === 'main') {
        cont = S.els.menu;
        cols = 2;
      } else if (S.state === 'paused' && !S.guideOpen) {
        const pm = $('pause-main');
        if (pm && !pm.hidden) cont = pm;
      }
      if (!cont || cont.hidden) return;
      const all = Array.prototype.slice.call(cont.querySelectorAll('button'));
      if (!all.length) return;
      e.preventDefault();
      const cur = all.indexOf(root.document.activeElement);
      const dir = k === 'ArrowUp' || k === 'ArrowLeft' ? -1 : 1;
      const step = cols === 2 && (k === 'ArrowUp' || k === 'ArrowDown') ? 2 : 1;
      let ni;
      if (cur < 0) ni = dir > 0 ? 0 : all.length - 1;
      else {
        ni = cur + dir * step;
        if (ni < 0 || ni >= all.length) ni = dir > 0 ? all.length - 1 : 0;
      }
      while (ni >= 0 && ni < all.length && all[ni].disabled) ni += dir;
      if (ni >= 0 && ni < all.length && ni !== cur) all[ni].focus();
    } catch (err) {
      L().warn('menuArrows failed', err);
    }
  }

  /** Show optional check failures once. */
  function showNotices(res) {
    const list = S.els.noticeList;
    if (!list) return;
    let n = 0;
    for (let i = 0; i < res.results.length; i++) {
      const r = res.results[i];
      if (r.ok || r.required) continue;
      const li = root.document.createElement('li');
      li.textContent = r.message;
      list.appendChild(li);
      n++;
    }
    if (n) show(S.els.notice, true);
  }

  // ---------------------------------------------------------------- v0.8: runs, saves, menu ----------------------------------------------------------------

  /** Effect value (falls back to the default when effects are missing or bad). */
  function fxv(k) {
    const f = S.fx;
    const v = f ? f[k] : undefined;
    return typeof v === 'number' && isFinite(v) ? v : DEFAULT_FX[k];
  }

  /** Effects of the current meta + run boons (defaults if Meta fails). */
  function computeFx() {
    try {
      const f = VCS.Meta.effects(S.meta, S.run ? S.run.boons : [], S.hunger && VCS.Hunger ? VCS.Hunger.giftMods(S.hunger) : []);
      if (f && typeof f === 'object') return f;
    } catch (err) {
      L().warn('Meta.effects failed', err);
    }
    return Object.assign({}, DEFAULT_FX);
  }

  /** Recompute effects and push them into the sonar. */
  function applyFx() {
    S.fx = computeFx();
    if (S.sonar && S.baseSonar && typeof S.baseSonar.cooldown === 'number') S.sonar.cooldown = S.baseSonar.cooldown * fxv('sonarCooldown');
    if (S.world) applyRoom(S.world);
  }

  /** Small seeded generator (mulberry32). */
  function mulberry32(a) {
    let s = a >>> 0;
    return function () {
      s = (s + 0x6D2B79F5) | 0;
      let t = Math.imul(s ^ (s >>> 15), 1 | s);
      t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
      return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
  }

  /** People seed for (run seed, map index, night). */
  function mixSeed(seed, mapIndex, night) {
    return (seed ^ (mapIndex * 2654435761) ^ (night * 40503)) >>> 0;
  }

  /** Deep copy of a run object. */
  function cloneRun(r) {
    const cs = {};
    if (r && r.closedSafe && typeof r.closedSafe === 'object') {
      for (const k in r.closedSafe) {
        if (Object.prototype.hasOwnProperty.call(r.closedSafe, k) && Array.isArray(r.closedSafe[k])) cs[k] = r.closedSafe[k].map(function (c) { return [c[0], c[1]]; });
      }
    }
    return {
      seed: r && typeof r.seed === 'number' ? r.seed : 1,
      boons: r && Array.isArray(r.boons) ? r.boons.slice() : [],
      closedSafe: cs,
      pendingBoons: r && Array.isArray(r.pendingBoons) ? r.pendingBoons.slice() : null,
      pendingGifts: r && Array.isArray(r.pendingGifts) ? r.pendingGifts.slice() : null
    };
  }

  /** Check a (sanitized) run object against the loaded maps and boon data. Returns a clean copy or null. */
  function validateRun(run) {
    try {
      if (!run || typeof run !== 'object') return null;
      if (!Number.isInteger(run.seed) || run.seed < 0 || run.seed > 4294967295) return null;
      if (!Array.isArray(run.boons)) return null;
      for (let i = 0; i < run.boons.length; i++) if (typeof run.boons[i] !== 'string' || !VCS.Meta.boonById(run.boons[i])) return null;
      let pending = null;
      if (run.pendingBoons !== null && run.pendingBoons !== undefined) {
        if (!Array.isArray(run.pendingBoons)) return null;
        for (let i = 0; i < run.pendingBoons.length; i++) if (typeof run.pendingBoons[i] !== 'string' || !VCS.Meta.boonById(run.pendingBoons[i])) return null;
        pending = run.pendingBoons.length ? run.pendingBoons.slice() : null;
      }
      let gifts = null;
      if (run.pendingGifts !== null && run.pendingGifts !== undefined) {
        if (!Array.isArray(run.pendingGifts)) return null;
        for (let i = 0; i < run.pendingGifts.length; i++) if (typeof run.pendingGifts[i] !== 'string' || !giftKnown(run.pendingGifts[i])) return null;
        gifts = run.pendingGifts.length ? run.pendingGifts.slice() : null;
      }
      const cs = {};
      const src = run.closedSafe && typeof run.closedSafe === 'object' ? run.closedSafe : {};
      for (const k in src) {
        if (!Object.prototype.hasOwnProperty.call(src, k)) continue;
        if (!S.worlds || !Object.prototype.hasOwnProperty.call(S.worlds, k) || !Array.isArray(src[k])) continue;
        cs[k] = src[k].filter(function (c) { return Array.isArray(c) && Number.isInteger(c[0]) && Number.isInteger(c[1]); }).map(function (c) { return [c[0], c[1]]; });
      }
      return { seed: run.seed, boons: run.boons.slice(), closedSafe: cs, pendingBoons: pending, pendingGifts: gifts, hunger: run.hunger && typeof run.hunger === 'object' ? run.hunger : null };
    } catch (err) {
      L().warn('validateRun failed', err);
      return null;
    }
  }

  /** True if id is a known gift id. */
  function giftKnown(id) {
    const gs = VCS.HungerData ? VCS.HungerData.gifts : [];
    for (let i = 0; i < gs.length; i++) if (gs[i].id === id) return true;
    return false;
  }

  /** Pick floor(n/3) safe spots per map (n >= 2) to seal for this run. Crypt beds never close. */
  function closeSafeSpots(seed) {
    const out = {};
    try {
      for (let idx = 0; idx < S.worldNames.length; idx++) {
        const name = S.worldNames[idx];
        const spots = (S.worlds[name].spots && S.worlds[name].spots.safe) || [];
        if (spots.length < 2) continue;
        const k = Math.min(16, Math.floor(spots.length / 3));
        if (k < 1) continue;
        const rng = mulberry32(mixSeed(seed, idx, 7));
        const order = spots.map(function (sp, i) { return i; });
        for (let i = 0; i < k; i++) {
          const j = i + Math.floor(rng() * (order.length - i));
          const t = order[i];
          order[i] = order[j];
          order[j] = t;
        }
        out[name] = order.slice(0, k).map(function (i) { return [Math.floor(spots[i].x), Math.floor(spots[i].y)]; });
      }
    } catch (err) {
      L().warn('closeSafeSpots failed', err);
    }
    return out;
  }

  /** True if this safe spot is sealed on the current map. */
  function isSealed(sp) {
    return isSealedIn(S.mapName, sp);
  }

  /** True if this safe spot is sealed on the named map. */
  function isSealedIn(name, sp) {
    const cs = S.run && S.run.closedSafe;
    if (!cs || !Object.prototype.hasOwnProperty.call(cs, name)) return false;
    const list = cs[name];
    const cx = Math.floor(sp.x);
    const cy = Math.floor(sp.y);
    for (let i = 0; i < list.length; i++) if (list[i][0] === cx && list[i][1] === cy) return true;
    return false;
  }

  /** Close every door and gate in every map (used when a run starts or loads). */
  function resetWorldDoors() {
    if (!S.worlds) return;
    for (let n = 0; n < S.worldNames.length; n++) {
      const w = S.worlds[S.worldNames[n]];
      if (typeof w.setDoor !== 'function') continue;
      for (let y = 0; y < w.height; y++) {
        for (let x = 0; x < w.width; x++) {
          const ch = w.tileAt(x + 0.5, y + 0.5);
          if ((ch === 'D' || ch === 'G') && w.isDoorOpen(x, y)) w.setDoor(x, y, false);
        }
      }
    }
  }

  /** Add a line to the notice panel and show it. */
  function addNotice(text) {
    const list = S.els.noticeList;
    if (!list) return;
    const li = root.document.createElement('li');
    li.textContent = text;
    list.appendChild(li);
    show(S.els.notice, true);
  }

  /** One storage-failure notice per session. */
  function storageFail(code) {
    S.saveFailed = true;
    if (S.storeWarned) return;
    S.storeWarned = true;
    addNotice('Could not save (' + code + '). Progress may be lost.');
  }

  /** A write succeeded: clear the "not saved" dot and re-arm the one-time failure notice. */
  function storageOk() {
    if (!S.saveFailed) return;
    S.saveFailed = false;
    if (S.store && S.store.persistent) S.storeWarned = false;
  }

  /** Per-tab id (random, not secret). */
  function makeTabId() {
    try {
      const old = root.sessionStorage.getItem('vcs.tabid');
      if (typeof old === 'string' && /^t[0-9a-z]{1,30}$/.test(old)) return old;
    } catch (e) { /* ignore */ }
    const id = newTabId();
    try { root.sessionStorage.setItem('vcs.tabid', id); } catch (e) { /* ignore */ }
    return id;
  }

  /** A fresh random tab id. */
  function newTabId() {
    let r = '';
    try {
      const a = new Uint32Array(2);
      root.crypto.getRandomValues(a);
      r = a[0].toString(36) + a[1].toString(36);
    } catch (e) { /* ignore */ }
    if (!r) {
      try {
        r = Math.random().toString(36).slice(2, 10);
      } catch (e) { /* ignore */ }
    }
    return 't' + (r || '0') + Math.floor(root.performance && root.performance.now ? root.performance.now() : 0).toString(36);
  }

  /** Raw localStorage for the tab lock (null when blocked). */
  function lockStorage() {
    try {
      return root.localStorage || null;
    } catch (e) {
      return null;
    }
  }

  /** Drop our own tab lock (page is going away) so a reload is not mistaken for a second tab. */
  function releaseTab() {
    try {
      const ls = lockStorage();
      if (!ls || !VCS.Save || !S.tabId) return;
      const raw = ls.getItem(VCS.Save.TAB_KEY);
      if (typeof raw === 'string' && raw.indexOf('"' + S.tabId + '"') >= 0) ls.removeItem(VCS.Save.TAB_KEY);
    } catch (e) { /* ignore */ }
  }

  /** Check for another live tab, then claim the lock if there is none. Runs at boot and every 5 s. Never throws. */
  function tabBeat() {
    try {
      const ls = lockStorage();
      if (!ls || !VCS.Save || typeof VCS.Save.tabCheck !== 'function') return;
      const now = Date.now();
      const r = VCS.Save.tabCheck(ls, S.tabId, now);
      if (r.other) {
        if (!S.otherTab) {
          S.otherTab = true;
          addNotice('Game is open in another tab \u2014 saving is paused here.');
          L().warn('Another tab is open; saving paused');
        }
        return;
      }
      if (S.otherTab) {
        S.otherTab = false;
        L().info('Other tab gone; saving resumed');
      }
      VCS.Save.tabLock(ls, S.tabId, now);
    } catch (err) {
      L().warn('tabBeat failed', err);
    }
  }

  /** Open the save store and load the meta save (fresh on any problem). */
  function initStorage() {
    let ls = null;
    try {
      ls = root.localStorage || null;
    } catch (e) {
      ls = null;
    }
    S.store = VCS.Save.create(ls);
    S.meta = VCS.Meta.create();
    if (!S.store.persistent) {
      S.storeWarned = true;
      addNotice('Saving is unavailable in this browser. Progress will not be kept.');
    }
    const r = S.store.read('meta');
    if (r.ok) {
      const m = VCS.Meta.migrate(r.v, r.data);
      const san = m.ok ? VCS.Meta.sanitize(m.data) : null;
      if (san) {
        S.meta = san;
        if (r.source === 'bak' && r.code && r.code !== 'E_SAVE_NONE') addNotice('Meta save was damaged, restored backup.');
      } else {
        addNotice('Meta save was damaged (' + (m.ok ? 'E_SAVE_SCHEMA' : m.code) + '). Started fresh.');
      }
    } else if (r.code !== 'E_SAVE_NONE') {
      addNotice('Meta save was damaged (' + r.code + '). Started fresh.');
    }
    S.fx = computeFx();
  }

  /** Write the meta save. True on success. */
  function saveMeta() {
    if (!S.store || !S.meta) return false;
    if (S.otherTab) return false;
    const r = S.store.write('meta', VCS.Meta.SCHEMA, S.meta);
    if (!r.ok) {
      L().warn('Meta save failed (' + r.code + ')');
      storageFail(r.code);
      return false;
    }
    storageOk();
    return true;
  }

  /** True while a run is in progress and may be saved. */
  function runIsActive() {
    return S.runOn && !!S.night && !!S.world && ACTIVE_STATES.indexOf(S.state) >= 0;
  }

  /** Write the run save (autosave, pause, hidden, boon). Never throws. */
  function saveRun(why) {
    if (!S.store || !runIsActive() || S.otherTab) return false;
    try {
      const snap = getSnapshot();
      const v = VCS.Save.validateRun(snap);
      if (!v.ok) {
        L().warn('Run snapshot invalid (' + v.code + '); autosave skipped on ' + why);
        return false;
      }
      const r = S.store.write('run', VCS.Save.RUN_SCHEMA, snap);
      if (!r.ok) {
        L().warn('Run save failed (' + r.code + ') on ' + why);
        storageFail(r.code);
        return false;
      }
      S.hasRun = true;
      storageOk();
      L().info('Run saved (' + why + ')');
      return true;
    } catch (err) {
      L().warn('Run save threw on ' + why, err);
      return false;
    }
  }

  /** Show the right overlay panels for the current state and menu view. */
  function syncPanels() {
    const st = S.state;
    const t = st === 'title';
    show(S.els.menu, t && S.menuView === 'main');
    show(S.els.shop, t && S.menuView === 'shop');
    show(S.els.stats, t && S.menuView === 'stats');
    show($('guide'), (t && S.menuView === 'guide') || (st === 'paused' && S.guideOpen));
    show(S.els.boons, st === 'boon' || st === 'gift');
    show(S.els.runend, st === 'runend');
    show(S.els.error, st === 'error');
  }

  /** Switch the menu between main / shop / stats. */
  function showMenuView(v) {
    S.menuView = v;
    if (v === 'shop') buildShop();
    else if (v === 'stats') buildStats();
    else if (v === 'guide') buildGuide();
    else refreshMenu();
    syncPanels();
    if (v === 'shop') openScrollPanel('shop', 'btn-shop-back');
    else if (v === 'guide') openScrollPanel('guide', 'btn-guide-back');
  }

  /** Scroll a freshly opened panel to the top and focus its Back button without scrolling. */
  function openScrollPanel(panelId, backId) {
    try {
      const pn = $(panelId);
      if (pn) pn.scrollTop = 0;
      const body = $(panelId + '-body') || $(panelId + '-list');
      if (body) body.scrollTop = 0;
      const b = $(backId);
      if (b && b.focus) b.focus({ preventScroll: true });
      if (pn) pn.scrollTop = 0;
    } catch (e) { /* ignore */ }
  }

  /** Cancel the "abandon run?" confirmation. */
  function resetAbandon() {
    if (S.abandonTimer) {
      root.clearTimeout(S.abandonTimer);
      S.abandonTimer = 0;
    }
    if (S.els.btnMenuNew) S.els.btnMenuNew.textContent = 'New run';
  }

  /** Refresh the main menu: essence, Continue availability. */
  function refreshMenu() {
    if (S.els.menuEssence) S.els.menuEssence.textContent = 'Essence ' + (S.meta ? S.meta.essence : 0);
    try {
      S.hasRun = !!(S.store && S.store.has('run'));
    } catch (err) {
      S.hasRun = false;
    }
    if (S.els.btnContinue) S.els.btnContinue.disabled = !S.hasRun;
    resetAbandon();
  }

  /** Remove all children of an element. */
  function clearEl(el) {
    while (el && el.firstChild) el.removeChild(el.firstChild);
  }

  /** Create an element with a class and optional text. */
  function mk(tag, cls, text) {
    const el = root.document.createElement(tag);
    if (cls) el.className = cls;
    if (text !== undefined) el.textContent = text;
    return el;
  }

  /** An icon canvas; registers it for the per-frame redraw. */
  function iconCanvas(name, size) {
    const c = root.document.createElement('canvas');
    c.width = size;
    c.height = size;
    c.className = 'icon';
    S.iconCvs.push({ c: c, name: name });
    return c;
  }

  /** Build the shop cards from the upgrade data and the current meta. */
  function buildShop() {
    const list = S.els.shopList;
    if (!list) return;
    clearEl(list);
    S.iconCvs = [];
    if (S.els.shopEssence) S.els.shopEssence.textContent = 'Essence ' + S.meta.essence;
    const ups = VCS.UpgradeData.upgrades;
    for (let i = 0; i < ups.length; i++) {
      const u = ups[i];
      const tier = VCS.Meta.tierOf(S.meta, u.id);
      const cost = VCS.Meta.costOf(S.meta, u.id);
      const card = mk('div', 'card');
      card.appendChild(iconCanvas(u.icon, 44));
      const info = mk('div', 'info');
      info.appendChild(mk('div', 'name', u.name));
      info.appendChild(mk('div', 'pips', '●'.repeat(tier) + '○'.repeat(Math.max(0, 3 - tier))));
      info.appendChild(mk('div', 'desc', u.desc[Math.min(tier, u.desc.length - 1)]));
      card.appendChild(info);
      const btn = mk('button', '', cost === null ? 'Max' : 'Buy (' + cost + ')');
      btn.type = 'button';
      btn.id = 'buy-' + u.id;
      btn.disabled = cost === null || S.meta.essence < cost;
      btn.addEventListener('click', buyHandler(u.id));
      card.appendChild(btn);
      list.appendChild(card);
    }
  }

  /** Click handler for a shop button. */
  function buyHandler(id) {
    return function () {
      try {
        buyUpgrade(id);
      } catch (err) {
        L().error('Buy failed', err);
      }
    };
  }

  /** Buy the next tier of an upgrade and save. */
  function buyUpgrade(id) {
    const r = VCS.Meta.buy(S.meta, id);
    if (!r.ok) {
      L().warn('Buy refused: ' + r.code);
      buildShop();
      return false;
    }
    L().info('Bought ' + id + ' for ' + r.cost);
    saveMeta();
    S.fx = computeFx();
    buildShop();
    return true;
  }

  /** Fill the stats panel. */
  function buildStats() {
    const list = S.els.statsList;
    if (!list) return;
    clearEl(list);
    const st = S.meta.stats;
    const rows = [['Runs', st.runs], ['Wins', st.wins], ['Nights survived', st.nightsSurvived], ['People fed', st.peopleFed], ['Best nights', st.bestNights], ['Essence earned', st.essenceEarned], ['Essence now', S.meta.essence]];
    for (let i = 0; i < rows.length; i++) {
      list.appendChild(mk('dt', '', rows[i][0]));
      list.appendChild(mk('dd', '', String(rows[i][1])));
    }
  }

  /** Redraw the icon canvases while a panel that shows them is open, and the tombstone on the run-end panel. */
  function drawUiCanvases() {
    if (S.uiBad) return;
    try {
      const st = S.state;
      if ((st === 'title' && (S.menuView === 'shop' || S.menuView === 'guide')) || (st === 'paused' && S.guideOpen) || st === 'boon' || st === 'gift') {
        const list = S.iconCvs;
        for (let i = 0; i < list.length; i++) {
          const c = list[i].c;
          const ctx = c.getContext('2d');
          if (!ctx) continue;
          ctx.clearRect(0, 0, c.width, c.height);
          ctx.save();
          ctx.translate(c.width / 2, c.height / 2);
          VCS.Icons.draw(ctx, list[i].name, Math.min(c.width, c.height) - 4, S.uiT, { still: S.reduced });
          ctx.restore();
        }
      } else if (st === 'runend' && S.els.tomb) {
        const c = S.els.tomb;
        const ctx = c.getContext('2d');
        if (ctx) {
          ctx.clearRect(0, 0, c.width, c.height);
          VCS.Icons.drawTombstone(ctx, c.width, c.height, S.uiT);
        }
      }
    } catch (err) {
      S.uiBad = true;
      L().error('UI canvas draw failed', err);
    }
  }

  /** Leave the run-end panel for the crypt menu. */
  function toCrypt() {
    if (S.state !== 'runend') return;
    S.menuView = 'main';
    setState('title');
    refreshMenu();
  }

  /** Abandon the stored run: record it as a loss with the nights survived so far, then remove it. */
  function abandonStored() {
    try {
      const r = S.store.read('run');
      if (r.ok) {
        const mg = VCS.Save.migrateRun(r.v, r.data);
        const san = mg.ok ? VCS.Save.sanitizeRun(mg.data) : null;
        const nt = san && san.night && typeof san.night === 'object' ? san.night : null;
        const nights = nt && Number.isInteger(nt.night) ? Math.max(0, nt.night - 1) : 0;
        const fed = nt && Number.isInteger(nt.fedCount) ? Math.max(0, nt.fedCount) : 0;
        const hb = san && san.run && san.run.hunger && Number.isFinite(san.run.hunger.essenceBonus) ? Math.max(0, Math.floor(san.run.hunger.essenceBonus)) : 0;
        VCS.Meta.recordRun(S.meta, { nights: nights, fed: fed, won: false, bonus: hb });
        saveMeta();
        L().info('Abandoned run: nights=' + nights + ' fed=' + fed);
      }
    } catch (err) {
      L().warn('abandonStored failed', err);
    }
    try {
      S.store.remove('run');
    } catch (err) {
      L().warn('Could not remove the run', err);
    }
    S.hasRun = false;
  }

  /** New run from the menu. With a stored run the first click asks to confirm (3 s); force skips the ask. */
  function menuNewRun(force) {
    if (S.state !== 'title') return false;
    if (S.hasRun && !force && !S.abandonTimer) {
      if (S.els.btnMenuNew) S.els.btnMenuNew.textContent = 'Abandon run? Click again';
      S.abandonTimer = root.setTimeout(function () {
        S.abandonTimer = 0;
        if (S.els.btnMenuNew) S.els.btnMenuNew.textContent = 'New run';
      }, 3000);
      return true;
    }
    resetAbandon();
    if (S.hasRun) abandonStored();
    return beginRun();
  }

  /** Load the stored run and resume it. False (with a notice) if it cannot be loaded. */
  function continueRun() {
    if (S.state !== 'title') return false;
    let src = 'main';
    const fail = function (code) {
      L().warn('Continue failed: ' + code + ' (from ' + src + ')');
      addNotice('Run save could not be loaded (' + code + ').');
      try {
        // Keep the backup for a retry only when the main copy failed; a bad backup is dropped too.
        if (src === 'bak') S.store.remove('run');
        else S.store.remove('run', { keepBak: true });
      } catch (e) { /* ignore */ }
      refreshMenu();
      return false;
    };
    const r = S.store.read('run');
    if (r.source === 'bak') src = 'bak';
    if (!r.ok) return fail(r.code || 'E_SAVE_NONE');
    if (r.source === 'bak' && r.code && r.code !== 'E_SAVE_NONE') addNotice('Run save was damaged, restored backup.');
    const mg = VCS.Save.migrateRun(r.v, r.data);
    if (!mg.ok) return fail(mg.code);
    const san = VCS.Save.sanitizeRun(mg.data);
    if (!san) return fail('E_SAVE_SCHEMA');
    const run = validateRun(san.run);
    if (!run || !Object.prototype.hasOwnProperty.call(S.worlds, san.map)) return fail('E_SAVE_SCHEMA');
    S.run = run;
    S.hunger = VCS.Hunger.create();
    S.fx = computeFx();
    resetWorldForRun();
    S.night = newNightState();
    if (!applySnapshot(san)) return fail('E_SAVE_SCHEMA');
    computeFarSpot();
    S.runOn = true;
    initAmbient();
    tutStart();
    S.autoAcc = 0;
    S.wasLocked = false;
    L().info('Run continued: seed ' + run.seed + ' night ' + (S.night ? S.night.night : '?'));
    if (S.run.pendingGifts && S.run.pendingGifts.length) {
      setState('gift');
      buildGifts();
    } else if (S.run.pendingBoons && S.run.pendingBoons.length) {
      setState('boon');
      buildBoons();
    } else {
      setState('playing');
      grabLock();
      if (S.audio) VCS.Audio.unlock(S.audio);
      showCard('Night ' + (S.night ? S.night.night : 1));
    }
    return true;
  }

  /** After sleeping: roll three boons and show the choice panel. */
  function enterBoon() {
    let ids = [];
    try {
      ids = VCS.Meta.rollBoons(S.run.seed + S.night.night * 7919, S.run.boons) || [];
    } catch (err) {
      L().warn('rollBoons failed', err);
    }
    if (!ids.length) {
      nextNight();
      setState('playing');
      return;
    }
    S.run.pendingBoons = ids;
    if (S.input) S.input.keys.clear();
    try {
      if (root.document.pointerLockElement && root.document.exitPointerLock) root.document.exitPointerLock();
    } catch (e) { /* ignore */ }
    setState('boon');
    buildBoons();
    saveRun('boon offered');
  }

  /** Build the three boon cards. */
  function buildBoons() {
    const list = S.els.boonList;
    if (S.els.boonsTitle) S.els.boonsTitle.textContent = 'A gift of the night';
    if (!list) return;
    clearEl(list);
    S.iconCvs = [];
    const ids = S.run.pendingBoons || [];
    for (let i = 0; i < ids.length; i++) {
      const b = VCS.Meta.boonById(ids[i]);
      const card = mk('div', 'card boon');
      card.appendChild(iconCanvas(b ? b.icon : 'bat', 56));
      card.appendChild(mk('div', 'name', b ? b.name : ids[i]));
      card.appendChild(mk('div', 'desc', b ? b.desc : ''));
      const btn = mk('button', '', 'Take (' + (i + 1) + ')');
      btn.type = 'button';
      btn.id = 'boon-' + i;
      btn.addEventListener('click', pickHandler(i));
      card.appendChild(btn);
      list.appendChild(card);
    }
  }

  /** Overflow is full: roll three small gifts and show the choice panel. */
  function enterGift() {
    if (!S.hunger || !S.run || !S.night) return;
    let ids = [];
    try {
      ids = VCS.Hunger.rollGifts(S.hunger, S.run.seed + S.night.night * 131 + S.hunger.gifts.length) || [];
    } catch (err) {
      L().warn('rollGifts failed', err);
    }
    if (!ids.length) {
      S.hunger.over = 0;
      return;
    }
    S.run.pendingGifts = ids;
    if (S.input) S.input.keys.clear();
    try {
      if (root.document.pointerLockElement && root.document.exitPointerLock) root.document.exitPointerLock();
    } catch (e) { /* ignore */ }
    setState('gift');
    buildGifts();
    L().info('Gift offered: ' + ids.join(','));
    saveRun('gift offered');
  }

  /** Build the three gift cards (reuses the boon panel). */
  function buildGifts() {
    const list = S.els.boonList;
    if (S.els.boonsTitle) S.els.boonsTitle.textContent = 'Blood gift';
    if (!list) return;
    clearEl(list);
    S.iconCvs = [];
    const ids = S.run.pendingGifts || [];
    const gs = VCS.HungerData.gifts;
    for (let i = 0; i < ids.length; i++) {
      let g = null;
      for (let k = 0; k < gs.length; k++) if (gs[k].id === ids[i]) g = gs[k];
      const card = mk('div', 'card boon');
      card.appendChild(iconCanvas(g ? g.icon : 'bat', 56));
      card.appendChild(mk('div', 'name', g ? g.name : ids[i]));
      card.appendChild(mk('div', 'desc', g ? g.desc : ''));
      const btn = mk('button', '', 'Take (' + (i + 1) + ')');
      btn.type = 'button';
      btn.id = 'boon-' + i;
      btn.addEventListener('click', function () {
        try {
          pickGift(i);
        } catch (err) {
          L().error('Pick gift failed', err);
        }
      });
      card.appendChild(btn);
      list.appendChild(card);
    }
  }

  /** Take gift number i (0..2) and go back to the night. */
  function pickGift(i) {
    if (S.state !== 'gift' || !S.run || !S.run.pendingGifts || !S.hunger) return false;
    const id = S.run.pendingGifts[i];
    if (typeof id !== 'string') return false;
    const r = VCS.Hunger.takeGift(S.hunger, id);
    if (!r.ok) {
      L().warn('takeGift refused ' + id);
      return false;
    }
    S.run.pendingGifts = null;
    S.overAcc = 0;
    applyFx();
    S.giftFlash = 1;
    L().info('Gift taken: ' + id);
    if (S.audio) VCS.Audio.play(S.audio, 'gift', { gain: level('gift').gain, pan: 0 });
    setState('playing');
    S.wasLocked = false;
    grabLock();
    if (S.audio) VCS.Audio.unlock(S.audio);
    saveRun('gift taken');
    return true;
  }

  /** The power that unlocks on night n (n > 1), or null. */
  function unlockedPower(n) {
    const ps = VCS.HungerData ? VCS.HungerData.powers : [];
    for (let i = 0; i < ps.length; i++) if (ps[i].unlock === n && n > 1) return ps[i];
    return null;
  }

  /** Record a power id as seen in this browser (localStorage "vcs.seen"). True when it was new. */
  function markSeen(id) {
    try {
      const ls = root.localStorage;
      let list = [];
      try {
        const v = JSON.parse(ls.getItem('vcs.seen') || '[]');
        if (Array.isArray(v)) list = v.filter(function (x) { return typeof x === 'string'; }).slice(0, 20);
      } catch (e) { list = []; }
      if (list.indexOf(id) !== -1) return false;
      list.push(id);
      ls.setItem('vcs.seen', JSON.stringify(list));
      return true;
    } catch (e) {
      return false;
    }
  }

  /** Subtle one-line hint under the crosshair after an unlock card. */
  function drawHint(c) {
    try {
      const a = Math.min(1, S.hintT / 0.6, (3 - S.hintT) / 0.4 + 0.01);
      c.save();
      c.globalAlpha = 0.45 * Math.max(0, a);
      c.fillStyle = '#cfe3ff';
      c.font = '10px ui-monospace, Menlo, Consolas, monospace';
      c.textAlign = 'center';
      c.textBaseline = 'middle';
      c.fillText('Esc → Abilities for details', 320, 336);
      c.restore();
    } catch (e) { /* ignore */ }
  }

  /** Open the How to play panel from the menu or the pause panel. */
  function openGuide(from) {
    S.guideFrom = from === 'pause' ? 'pause' : 'menu';
    if (S.guideFrom === 'pause') {
      if (S.state !== 'paused') return;
      S.guideOpen = true;
      buildGuide();
      show(S.els.pause, false);
      syncPanels();
    } else {
      showMenuView('guide');
    }
    openScrollPanel('guide', 'btn-guide-back');
  }

  /** Close the guide and return to where it was opened from. */
  function closeGuide() {
    if (S.guideFrom === 'pause' && S.state === 'paused') {
      S.guideOpen = false;
      show(S.els.pause, true);
      syncPanels();
      const b = $('btn-abilities');
      if (b && b.focus) b.focus();
    } else if (S.state === 'title') {
      showMenuView('main');
    }
  }

  /** Key label for a power. */
  function keyLabel(p) {
    const k = p.key && p.key[0] ? String(p.key[0]) : '';
    if (k.indexOf('Shift') === 0) return 'Shift or C';
    return k.replace(/^Key/, '');
  }

  /** Build the How to play panel from the data modules (createElement/textContent only). */
  function buildGuide() {
    const body = $('guide-body');
    if (!body) return;
    clearEl(body);
    S.iconCvs = [];
    const HD = VCS.HungerData;
    const nights = S.night && S.night.nights ? S.night.nights : 5;
    const sec = function (title, lines) {
      body.appendChild(mk('h3', '', title));
      for (let i = 0; i < lines.length; i++) body.appendChild(mk('p', '', lines[i]));
    };
    sec('Basics', [
      'Move with W A S D or the arrow keys (Left and Right arrows turn); look with the mouse.',
      'Ping: click or Space sends out a sonar pulse that draws walls and doors for a moment. It is loud, so people nearby may hear it.',
      'Echoes that move are people. Walk up close and hold right-click (or R) to drink. Drink in the dark; lit people see you.',
      'Sleep: press E at your crypt bed or a dark safe spot before 06:00. Powers: Q shriek, C or Shift mist, F still. Esc pauses.'
    ]);
    sec('Goal', [
      'Feed on the townsfolk, then get home or into a dark safe spot before 06:00. Survive ' + nights + ' nights.',
      'The farthest open safe spot in town pays +5 Essence when you sleep there.'
    ]);
    sec('Blood', [
      'Your blood drains all night, and faster each night (+' + Math.round((HD ? HD.RAMP : 0.1) * 100) + '% per night).',
      'Below 25 your pulses weaken. Hold right click near someone to drink.'
    ]);
    body.appendChild(mk('h3', '', 'Powers'));
    const ps = HD ? HD.powers : [];
    const cur = S.state === 'paused' && S.night ? S.night.night : 0;
    for (let i = 0; i < ps.length; i++) {
      const p = ps[i];
      const locked = cur > 0 && cur < p.unlock;
      const card = mk('div', 'gcard' + (locked ? ' locked' : ''));
      card.appendChild(iconCanvas(p.icon, 44));
      const col = mk('div', '');
      col.appendChild(mk('div', 'name', p.name));
      if (locked) {
        col.appendChild(mk('div', 'facts', 'Unlocks night ' + p.unlock));
      } else {
        col.appendChild(mk('div', 'facts', 'Key ' + keyLabel(p) + ' · Night ' + p.unlock + ' · Cost ' + p.cost + ' blood · Cooldown ' + p.cooldown + ' s · Fear +' + p.fear));
      }
      col.appendChild(mk('p', 'how', p.how || p.desc || ''));
      col.appendChild(mk('p', 'tip', p.tip || ''));
      card.appendChild(col);
      body.appendChild(card);
    }
    const gc = HD ? HD.GIFT_COSTS : [40, 60];
    sec('Blood gifts', [
      'Keep drinking when your blood is full and the coral bar fills. At ' + gc[0] + ' (then ' + gc[1] + ') you pick 1 of 3 gifts.',
      'Up to ' + (HD ? HD.GIFTS_PER_NIGHT : 2) + ' per night. Each gift gives +' + (HD ? HD.GIFT_ESSENCE : 2) + ' Essence.'
    ]);
    sec('Fear', [
      'The eyes by the clock show how jumpy the town is.',
      'Feeding on someone new and using powers raise it; sleeping and the Calm Town gift lower it.',
      'Higher fear makes people startle from further away (up to +' + Math.round((HD ? HD.FEAR_STARTLE[1] : 0.6) * 100) + '%) and flee faster (up to +' + Math.round((HD ? HD.FEAR_FLEE[1] : 0.45) * 100) + '%).'
    ]);
  }

  /** Title-card suffix for a power that unlocks on night n (n > 1). */
  function unlockText(n) {
    const ps = VCS.HungerData ? VCS.HungerData.powers : [];
    for (let i = 0; i < ps.length; i++) {
      if (ps[i].unlock === n && n > 1) return ' \u2014 ' + ps[i].name + ' (' + (ps[i].id === 'mist' ? 'Shift' : POWER_KEYS[ps[i].id]) + ')';
    }
    return '';
  }

  /** Power keys pressed this frame (Q shriek, Shift mist, F still). */
  function powerKeys(pressed) {
    if (!S.hunger || !S.night) return;
    if (pressed.has('KeyQ')) usePower('shriek');
    if (pressed.has('ShiftLeft') || pressed.has('ShiftRight') || pressed.has('KeyC')) usePower('mist');
    if (pressed.has('KeyF')) usePower('still');
  }

  /** Spend blood on a power and run its effect. Returns Hunger's result ({ok, code, cost}). */
  function usePower(id) {
    const bad = { ok: false, code: 'E_UNKNOWN', cost: null };
    if (!S.hunger || !S.night || S.state !== 'playing' || S.drink || !S.player) return bad;
    let r = bad;
    try {
      r = VCS.Hunger.use(S.hunger, id, S.night.night, S.night.blood);
    } catch (err) {
      L().warn('Hunger.use failed', err);
      return bad;
    }
    if (!r.ok) {
      if (S.clock - S.missAt > 0.35 || S.missAt > S.clock) {
        S.missAt = S.clock;
        if (S.audio) VCS.Audio.play(S.audio, 'miss', { gain: level('miss').gain, pan: 0 });
      }
      if (r.code === 'E_POOR' && (S.clock - S.msgAt > 3 || S.msgAt > S.clock)) {
        S.msgAt = S.clock;
        showCard('Not enough blood', S.cardLen - 1);
      }
      L().debug('power ' + id + ' refused: ' + r.code);
      return r;
    }
    S.night.blood = Math.max(0, S.night.blood - r.cost);
    L().info('Power ' + id + ' used (fear ' + S.hunger.fear + ')');
    try {
      if (id === 'shriek') doShriek();
      else if (id === 'mist') startMist();
      else if (id === 'still') doStill();
    } catch (err) {
      L().error('Power ' + id + ' failed', err);
    }
    return r;
  }

  /** Shriek: a loud pulse at double range; people react far away. */
  function doShriek() {
    const p = S.player;
    const b = S.baseSonar;
    const weak = S.night ? VCS.Night.weakness(S.night) : 0;
    const range = (b ? b.range : 10) * fxv('sonarRange') * 2 * (1 - 0.4 * weak);
    emitSound('shriek', p.x, p.y, { range: range });
    if (S.audio) VCS.Audio.play(S.audio, 'shriek', { gain: level('shriek').gain, pan: 0 });
    const base = VCS.SoundData && VCS.SoundData.react && typeof VCS.SoundData.react.startleDist === 'number' ? VCS.SoundData.react.startleDist : 3;
    const mul = VCS.SoundData && VCS.SoundData.react && typeof VCS.SoundData.react.shriekMul === 'number' ? VCS.SoundData.react.shriekMul : 2.5;
    reactCfgNow();
    reactTo(p.x, p.y, 'shriek', base * mul * fxv('noise') * S.fm.startleMul);
  }

  /** Mist: a quiet two-cell dash along the move direction (or facing). */
  function startMist() {
    const p = S.player;
    const keys = S.input ? S.input.keys : null;
    const inp = VCS.Player.inputFromKeys(keys, 0);
    let dx = inp.forward * Math.cos(p.angle) + inp.strafe * Math.cos(p.angle + Math.PI / 2);
    let dy = inp.forward * Math.sin(p.angle) + inp.strafe * Math.sin(p.angle + Math.PI / 2);
    let len = Math.hypot(dx, dy);
    if (!(len > 0)) {
      dx = Math.cos(p.angle);
      dy = Math.sin(p.angle);
      len = 1;
    }
    S.mist = { t: 0, dx: dx / len, dy: dy / len, left: MIST_DIST };
    S.mistVis = 1;
    S.stepTimer = 0;
    reactCfgNow();
    emitSound('mist', p.x, p.y);
    if (S.audio) VCS.Audio.play(S.audio, 'mist', { gain: level('mist').gain, pan: 0 });
  }

  /** Advance the mist dash by dt using small collision substeps. */
  function stepMist(dt) {
    const m = S.mist;
    if (!m) return;
    const p = S.player;
    const w = S.world;
    const r = p.radius || 0.2;
    let want = Math.min(m.left, MIST_DIST * Math.min(dt, MIST_DUR) / MIST_DUR);
    let blocked = false;
    while (want > 1e-6 && !blocked) {
      const d = Math.min(0.1, want);
      want -= d;
      let moved = false;
      const nx = p.x + m.dx * d;
      if (!w.blocks(nx, p.y, r)) {
        p.x = nx;
        moved = true;
      }
      const ny = p.y + m.dy * d;
      if (!w.blocks(p.x, ny, r)) {
        p.y = ny;
        moved = true;
      }
      if (moved) m.left -= d;
      else blocked = true;
    }
    m.t += dt;
    if (blocked || m.left <= 1e-6 || m.t >= MIST_DUR + 0.05) S.mist = null;
  }

  /** Still: five quiet seconds. */
  function doStill() {
    reactCfgNow();
    if (S.audio) VCS.Audio.play(S.audio, 'still', { gain: level('still').gain, pan: 0 });
    emitSound('still', S.player.x, S.player.y);
  }

  /** Click handler for a boon button. */
  function pickHandler(i) {
    return function () {
      try {
        pickBoon(i);
      } catch (err) {
        L().error('Pick boon failed', err);
      }
    };
  }

  /** Take boon number i (0..2): apply it and start the next night. */
  function pickBoon(i) {
    if (S.state !== 'boon' || !S.run || !S.run.pendingBoons) return false;
    const id = S.run.pendingBoons[i];
    if (typeof id !== 'string') return false;
    const b = VCS.Meta.boonById(id);
    S.run.boons.push(id);
    S.run.pendingBoons = null;
    if (b && b.effect === 'bloodNow' && S.night) {
      try {
        VCS.Night.addBlood(S.night, b.value);
      } catch (err) {
        L().warn('addBlood failed', err);
      }
    }
    applyFx();
    if (S.night) {
      const m = S.config && typeof S.config.nightLengthMin === 'number' ? S.config.nightLengthMin : 4;
      S.night.nightSec = m * 60 * fxv('nightLen');
      S.night.drainMul = fxv('drain') * DRAIN_BASE;
    }
    L().info('Boon taken: ' + id);
    nextNight();
    setState('playing');
    S.wasLocked = false;
    grabLock();
    if (S.audio) VCS.Audio.unlock(S.audio);
    saveRun('boon taken');
    return true;
  }

  /** Download text as a file via a temporary link. */
  function downloadText(name, text, type) {
    const url = root.URL.createObjectURL(new root.Blob([text], { type: type }));
    const a = root.document.createElement('a');
    a.href = url;
    a.download = name;
    root.document.body.appendChild(a);
    a.click();
    root.document.body.removeChild(a);
    root.setTimeout(function () { root.URL.revokeObjectURL(url); }, 1000);
  }

  /** Export meta + run as a JSON file. */
  function exportSave() {
    if (!S.store.has('meta')) saveMeta();
    const text = VCS.Save.exportText(S.store);
    if (!text) {
      addNotice('Export failed (E_SAVE_EXPORT).');
      return false;
    }
    downloadText('vcs-save-' + stamp() + '.json', text, 'application/json');
    L().info('Save exported');
    return true;
  }

  /** A file was chosen for import. */
  function onImportFile() {
    const inp = S.els.fileImport;
    const f = inp && inp.files && inp.files[0];
    if (!f) return;
    if (f.size > VCS.Save.MAX_IMPORT) {
      inp.value = '';
      addNotice('Import failed (E_SAVE_TOO_BIG).');
      return;
    }
    const fr = new root.FileReader();
    fr.onload = function () {
      try {
        importText(String(fr.result));
      } catch (err) {
        L().error('Import failed', err);
        addNotice('Import failed (E_SAVE_PARSE).');
      }
    };
    fr.onerror = function () { addNotice('Import failed (E_SAVE_PARSE).'); };
    fr.readAsText(f);
    inp.value = '';
  }

  /** Import exported save text: meta replaces meta, a good run replaces the run (a bad run is dropped). */
  function importText(text) {
    const bad = function (code) {
      L().warn('Import failed: ' + code);
      addNotice('Import failed (' + code + ').');
      return { ok: false, code: code };
    };
    const pi = VCS.Save.parseImport(text);
    if (!pi.ok) return bad(pi.code);
    const mm = VCS.Meta.migrate(pi.meta.v, pi.meta.data);
    const msan = mm.ok ? VCS.Meta.sanitize(mm.data) : null;
    if (!msan) return bad(mm.ok ? 'E_SAVE_SCHEMA' : mm.code);
    let runSan = null;
    if (pi.run) {
      const rm = VCS.Save.migrateRun(pi.run.v, pi.run.data);
      const rs = rm.ok ? VCS.Save.sanitizeRun(rm.data) : null;
      if (rs && Object.prototype.hasOwnProperty.call(S.worlds, rs.map) && validateRun(rs.run)) runSan = rs;
      else L().warn('Import: run section dropped');
    }
    S.meta = msan;
    S.fx = computeFx();
    saveMeta();
    try {
      if (runSan) {
        const w = S.store.write('run', VCS.Save.RUN_SCHEMA, runSan);
        if (!w.ok) storageFail(w.code);
      } else {
        S.store.remove('run');
      }
    } catch (err) {
      L().warn('Import: run write failed', err);
    }
    if (S.state === 'title') {
      if (S.menuView === 'shop') buildShop();
      else if (S.menuView === 'stats') buildStats();
      else refreshMenu();
    }
    addNotice('Save imported.');
    L().info('Save imported' + (runSan ? ' with run' : ''));
    return { ok: true, code: '' };
  }

  /** ?debug=1 hooks for runs and saves. */
  function installDebugHooks() {
    const G = Game;
    G.debugSave = function () {
      const m = S.store.write('meta', VCS.Meta.SCHEMA, S.meta);
      const r = runIsActive() ? S.store.write('run', VCS.Save.RUN_SCHEMA, getSnapshot()) : null;
      return { meta: m, run: r };
    };
    G.debugMeta = function () { return JSON.parse(JSON.stringify(S.meta)); };
    G.debugEssence = function (n) {
      if (typeof n !== 'number' || !isFinite(n)) return false;
      S.meta.essence = Math.max(0, Math.min(1000000, Math.floor(n)));
      saveMeta();
      if (S.state === 'title') showMenuView(S.menuView);
      return true;
    };
    G.debugEndRun = function (kind) {
      if (!S.night) return false;
      endRun(kind === 'won' ? 'won' : 'lost');
      return true;
    };
    G.debugPickBoon = pickBoon;
    G.debugPickGift = pickGift;
    G.debugHunger = function () { return S.hunger ? Object.assign(JSON.parse(JSON.stringify(VCS.Hunger.serialize(S.hunger))), { stillLeft: S.hunger.stillLeft, cd: Object.assign({}, S.hunger.cd), mist: !!S.mist }) : null; };
    G.debugFear = function (n) {
      if (!S.hunger || typeof n !== 'number' || !isFinite(n)) return false;
      S.hunger.fear = 0;
      VCS.Hunger.addFear(S.hunger, n);
      return true;
    };
    G.debugOverflow = function (n) {
      if (!S.hunger || typeof n !== 'number' || !isFinite(n)) return false;
      const r = VCS.Hunger.addOverflow(S.hunger, n);
      if (r.ready && S.state === 'playing') enterGift();
      return r.taken;
    };
    G.debugPower = function (id) { return usePower(id); };
    G.debugHungerSet = function (patch) {
      if (!S.hunger || !patch || typeof patch !== 'object') return false;
      ['fear', 'over', 'giftsTonight', 'essenceBonus', 'nextBlood'].forEach(function (k) {
        if (typeof patch[k] === 'number' && isFinite(patch[k]) && patch[k] >= 0) S.hunger[k] = Math.floor(patch[k]);
      });
      return true;
    };
    G.debugPending = function () { return S.run && S.run.pendingGifts ? S.run.pendingGifts.slice() : null; };
    G.debugRun = function () { return cloneRun(S.run); };
    G.debugFx = function () { return Object.assign({}, S.fx); };
    G.debugExport = function () { return VCS.Save.exportText(S.store); };
    G.debugImport = importText;
    G.debugMenu = function (action) {
      switch (action) {
        case 'continue': return continueRun();
        case 'newrun': return menuNewRun(true);
        case 'shop': showMenuView('shop'); return true;
        case 'stats': showMenuView('stats'); return true;
        case 'guide': openGuide('menu'); return true;
        case 'abilities': openGuide('pause'); return true;
        case 'menu':
          if (S.state === 'runend') toCrypt();
          else showMenuView('main');
          return true;
        default: return false;
      }
    };
  }

  /** Boot the game. */
  function boot() {
    const doc = root.document;
    S.els = {
      menu: $('menu'), shop: $('shop'), stats: $('stats'), boons: $('boons'), boonsTitle: $('boons-title'), fileImport: $('file-import'),
      menuEssence: $('menu-essence'), btnContinue: $('btn-continue'), btnMenuNew: $('btn-menu-new'),
      shopEssence: $('shop-essence'), shopList: $('shop-list'), statsList: $('stats-list'), boonList: $('boon-list'),
      tomb: $('tomb'), runendEssence: $('runend-essence'), pause: $('pause'), error: $('error'), notice: $('notice'),
      noticeList: $('notice-list'), debug: $('debug'), reportBox: $('report-box'),
      errorCode: $('error-code'), errorMsg: $('error-msg'),
      runend: $('runend'), runendTitle: $('runend-title'), runendMsg: $('runend-msg')
    };
    S.canvas = $('view');
    wire();
    wireSettings();
    try {
      const missing = ['Log', 'Config', 'Checks', 'MapData', 'SoundData', 'World', 'Raycast', 'Sonar', 'Audio', 'Input', 'Player', 'Ripple', 'People', 'Render', 'Night', 'Hud', 'UpgradeData', 'HungerData', 'Meta', 'Hunger', 'Save', 'Icons'].filter(function (m) {
        return !VCS[m];
      });
      if (missing.length) {
        fatal('E_MODULES', 'Missing game files: ' + missing.join(', '), null);
        return;
      }
      const params = new root.URLSearchParams(root.location.search);
      const debug = params.get('debug') === '1';
      const safe = params.get('safe') === '1';
      if (debug) VCS.Log.setLevel('DEBUG');
      S.debugOn = debug;
      S.debugEnabled = debug;
      try {
        if (VCS.Flags) {
          VCS.Flags.register('dev.showFps', false, 'Show the FPS/debug overlay');
          VCS.Flags.register('vis.vessels', false, 'Circulatory pulse on villagers');
          VCS.Flags.registerTun('vessels', 'alpha', { value: 0.75, min: 0, max: 1, step: 0.05, desc: 'Vessel node base alpha' });
          VCS.Flags.registerTun('vessels', 'size', { value: 1, min: 0.3, max: 3, step: 0.1, desc: 'Vessel dot size' });
          VCS.Flags.registerTun('vessels', 'hot', { value: 1, min: 0, max: 2, step: 0.1, desc: 'Hotspot bloom scale (carotid, femoral, radial)' });
          VCS.Flags.registerTun('vessels', 'veins', { value: 0.6, min: 0, max: 1, step: 0.05, desc: 'Vein alpha vs arteries' });
          VCS.Flags.registerTun('vessels', 'halo', { value: 0.3, min: 0, max: 1, step: 0.05, desc: 'Soft halo alpha at quality 2+' });
          VCS.Flags.registerTun('vessels', 'pwvScale', { value: 1.75, min: 1, max: 3, step: 0.05, desc: 'Pulse wave slow-down (travel delay x this)' });
          VCS.Flags.registerTun('vessels', 'minQuality', { value: 1, min: 1, max: 3, step: 1, desc: 'Lowest render quality that draws vessels' });
          VCS.Flags.registerTun('vessels', 'edges', { value: 0.45, min: 0, max: 1, step: 0.05, desc: 'Vessel edge line alpha (quality 2+)' });
          VCS.Flags.registerTun('vessels', 'highlight', { value: 1, min: 0, max: 2, step: 0.1, desc: 'Travelling highlight alpha along the edges' });
          VCS.Flags.load(root.location.search, debug);
          if (VCS.Flags.get('dev.showFps')) S.debugOn = true;
          VCS.Flags.onChange(function (ev) {
            if (ev.id === 'dev.showFps') { S.debugOn = !!ev.value; show(S.els.debug, S.debugOn); }
          });
        }
        if (VCS.DevPanel) VCS.DevPanel.init({ f9: debug });
      } catch (err) { L().warn('dev flags init failed', err); }
      try {
        S.osReduced = !!(root.matchMedia && root.matchMedia('(prefers-reduced-motion: reduce)').matches);
      } catch (e) { S.osReduced = false; }
      S.reduced = S.osReduced;
      VCS.Log.installGlobalHandlers(function (info) {
        fatal(info.code, info.message, info);
      });
      L().info('Boot v' + VCS.Log.VERSION + ' debug=' + debug + ' safe=' + safe);

      const res = VCS.Checks.run(root);
      if (!res.ok) {
        const bad = res.results.filter(function (r) { return !r.ok && r.required; })
          .map(function (r) { return r.message; }).join('; ');
        fatal('E_CHECKS', bad || 'A required browser feature is missing', null);
        return;
      }
      S.config = VCS.Config.load({ safeMode: safe });
      try {
        const dvb = $('btn-devtool');
        if (dvb && S.config.devButton === false) dvb.hidden = true;
      } catch (err) { /* ignore */ }
      applyMotion();
      initStorage();
      S.tabId = makeTabId();
      tabBeat();
      S.tabTimer = root.setInterval(tabBeat, 5000);

      let loaded;
      try {
        loaded = VCS.World.loadAll(VCS.MapData);
      } catch (err) {
        const det = err && Array.isArray(err.details) ? err.details : [];
        const lines = det.slice(0, 5).map(function (e) {
          return '- ' + (e.map ? e.map + ': ' : '') + (e.code ? e.code + ' ' : '') + (e.message || '');
        });
        const more = det.length > 5 ? '\n(+' + (det.length - 5) + ' more)' : '';
        fatal('E_MAP_INVALID', 'Map data is invalid:\n' + (lines.length ? lines.join('\n') : (err && err.message) || 'unknown') + more, err);
        return;
      }
      S.worlds = loaded.worlds;
      S.worldNames = Object.keys(loaded.worlds);
      let startName = loaded.startMap;
      const wantMap = params.get('map');
      if (debug && wantMap) {
        if (S.worlds[wantMap]) startName = wantMap;
        else L().warn('Unknown ?map=' + wantMap + ', using ' + startName);
      }
      S.mapName = startName;
      if (debug && wantMap && S.worlds[wantMap]) S.forceMap = wantMap;
      const seedQ = params.get('seed');
      if (debug && seedQ && /^[0-9]{1,10}$/.test(seedQ)) S.seedParam = Number(seedQ) >>> 0;
      S.world = S.worlds[startName];
      L().info('Map loaded: ' + S.world.name + ' ' + S.world.width + 'x' + S.world.height + ' (' + S.worldNames.length + ' maps)');
      const st = startPlace(S.world);
      S.player = VCS.Player.create({ x: st.x, y: st.y }, st.angle);

      S.canvas.width = W;
      S.canvas.height = H;
      S.ctx = S.canvas.getContext('2d');
      if (!S.ctx) {
        fatal('E_CANVAS', 'Could not get a 2D drawing context', null);
        return;
      }
      S.ctx.imageSmoothingEnabled = false;
      fitCanvas();
      S.input = VCS.Input.create(S.canvas, S.config);
      if (S.input && typeof S.input.setLockGate === 'function') {
        S.input.setLockGate(function () { return S.state === 'playing' || S.state === 'feeding' || S.state === 'sleeping'; });
      }
      const c = S.config;
      const num = function (v, d) { return typeof v === 'number' ? v : d; };
      S.sonar = VCS.Sonar.create({
        speed: num(c.sonarSpeed, 12), range: num(c.sonarRange, 10),
        fade: num(c.sonarFade, 3), cooldown: num(c.sonarCooldown, 0.8)
      });
      S.audio = VCS.Audio.create(c);
      S.baseSonar = { range: S.sonar.range, bounces: S.sonar.bounces, fade: S.sonar.fade, cooldown: S.sonar.cooldown };
      applyRoom(S.world);
      S.people = peopleFor(startName);
      S.ripple = VCS.Ripple.create();
      S.renderer = VCS.Render.create(S.canvas, c);
      applyMotion();
      if (S.state === 'title' && typeof VCS.Render.setGrain === 'function') { VCS.Render.setGrain(S.renderer, 0); VCS.Render.setVignette(S.renderer, false); }
      try {
        S.hud = VCS.Hud.create();
      } catch (err) {
        S.hudBad = true;
        L().error('Hud.create failed', err);
      }
      syncControls();
      S.clock = 0;
      S.view = 'fp';
      if (debug) {
        Game.debugPulse = debugPulse;
        Game.debugTeleport = debugTeleport;
        Game.debugAdvance = debugAdvance;
        Game.debugInteract = interact;
        Game.debugEchoes = function () { return S.people ? S.people.echoes.slice() : []; };
        Game.debugMap = debugMap;
        Game.debugZone = debugZone;
        Game.debugTime = function (h, m) { return !!S.night && VCS.Night.skipTo(S.night, h, m); };
        Game.debugBlood = function (v) {
          if (!S.night || typeof v !== 'number' || !isFinite(v)) return false;
          S.night.blood = clamp(v, 0, S.night.bloodMax);
          return true;
        };
        Game.debugFeed = function () { return startDrink(true); };
        Game.debugPlay = function (kind, cells) {
          if (!S.audio || !S.player) return false;
          const d = typeof cells === 'number' ? cells : 0;
          return VCS.Audio.play(S.audio, kind, spatial(S.player.x + Math.cos(S.player.angle) * d, S.player.y + Math.sin(S.player.angle) * d, level(kind).gain));
        };
        Game.debugFeedHold = debugFeedHold;
        Game.debugPeopleState = function () { return S.people; };
        Game.debugSleep = function () { return trySleep(true); };
        Game.debugNight = function () { return S.night ? VCS.Night.serialize(S.night) : null; };
      }

      if (debug) installDebugHooks();
      showNotices(res);
      show(S.els.debug, S.debugOn);
      S.state = 'title';
      S.menuView = 'main';
      refreshMenu();
      syncPanels();
      S.running = true;
      S.lastT = root.performance.now();
      S.rafId = root.requestAnimationFrame(frame);
    } catch (err) {
      fatal((err && err.code) || 'E_BOOT', (err && err.message) || String(err), err);
    }
    void doc;
  }

  /** Light level 0..1 at a point; 0 when the world has no lights or the call fails. */
  function safeLight(w, x, y) {
    try {
      const v = w && typeof w.lightAt === 'function' ? w.lightAt(x, y) : 0;
      return typeof v === 'number' && isFinite(v) ? v : 0;
    } catch (err) {
      return 0;
    }
  }

  /** Sound room profile (rangeMul, bounceCap, fadeMul) for a world. */
  function roomProfile(w, kind) {
    const rooms = VCS.SoundData && VCS.SoundData.rooms;
    const r = rooms && w ? rooms[kind || w.kind] : null;
    return {
      rangeMul: r && typeof r.rangeMul === 'number' ? r.rangeMul : 1,
      bounceCap: r && typeof r.bounceCap === 'number' ? r.bounceCap : 2,
      fadeMul: r && typeof r.fadeMul === 'number' ? r.fadeMul : 1,
      outdoor: false
    };
  }

  /** Apply the room profile to the sonar and audio (base values come from config at boot). */
  function applyRoom(w) {
    const k = playerKind(w);
    const room = roomProfile(w, k);
    const b = S.baseSonar;
    if (S.sonar && b) {
      S.sonar.range = b.range * room.rangeMul * fxv('sonarRange');
      S.sonar.bounces = Math.min(b.bounces, room.bounceCap);
      S.sonar.fade = b.fade * room.fadeMul * fxv('sonarFade');
      if (typeof b.cooldown === 'number') S.sonar.cooldown = b.cooldown * fxv('sonarCooldown');
    }
    S.roomKind = k;
    applyReverb(w, k);
  }

  /** Reverb for the player's zone: T60 from Sabine per zone name (map name when the zone is unnamed), clamped 0.4-2.5 s. */
  function applyReverb(w, k) {
    const p = S.player;
    const zone = p && w && typeof w.zoneAt === 'function' ? w.zoneAt(p.x, p.y) : null;
    S.roomZone = zone || (w && w.name) || null;
    const A = VCS.SoundData && VCS.SoundData.acoustics;
    if (S.audio && typeof VCS.Audio.setRoom === 'function') VCS.Audio.setRoom(S.audio, k, A ? A.t60For(S.roomZone, k) : undefined);
  }

  /** Sound kind at the player (zone kind, else map kind). */
  function playerKind(w) {
    const p = S.player;
    return p && w && typeof w.kindAt === 'function' ? w.kindAt(p.x, p.y) : w.kind;
  }

  /** Follow the player's zone kind; only touches Audio/sonar when it changes. */
  function followRoom() {
    if (!S.world) return;
    const k = playerKind(S.world);
    if (k !== S.roomKind) applyRoom(S.world);
    else {
      const p = S.player;
      const z = p && typeof S.world.zoneAt === 'function' ? S.world.zoneAt(p.x, p.y) : null;
      if ((z || S.world.name || null) !== S.roomZone) applyReverb(S.world, k);
    }
  }

  /** Test hook: name of the zone at the player, or null. */
  function debugZone() {
    const p = S.player;
    return S.world && p && typeof S.world.zoneAt === 'function' ? S.world.zoneAt(p.x, p.y) : null;
  }

  /** Start position for a world: its @ marker, else its first door's arrival, else the first walkable cell. */
  function startPlace(w) {
    if (w.start && isFinite(w.start.x)) return { x: w.start.x, y: w.start.y, angle: 0 };
    const ids = Object.keys(w.doorsById || {});
    for (let i = 0; i < ids.length; i++) {
      const a = w.arrival(ids[i]);
      if (a) return a;
    }
    for (let y = 0; y < w.height; y++) {
      for (let x = 0; x < w.width; x++) if (!w.blocks(x + 0.5, y + 0.5, 0.2)) return { x: x + 0.5, y: y + 0.5, angle: 0 };
    }
    return { x: 1.5, y: 1.5, angle: 0 };
  }

  /** The People state of a map, created lazily (seed = 1 + map index). */
  function peopleFor(name, seed) {
    const have = S.peopleByMap[name];
    if (have && (seed === undefined || have.seed === seed)) return have;
    const idx = Math.max(0, S.worldNames.indexOf(name));
    const sd = typeof seed === 'number' ? seed : mixSeed(S.run ? S.run.seed : 1, idx, S.night ? S.night.night : 1);
    const st = VCS.People.create(S.worlds[name], VCS.MapData.maps[name], { seed: sd, poolMin: cfgNum('poolMin', 30), poolMax: cfgNum('poolMax', 50), shuffle: true });
    S.peopleByMap[name] = st;
    return st;
  }

  // ---------------------------------------------------------------- far spot, ambience, breathing, tutorial

  /** Breadth-first walking distances (cells) from the cell (sx,sy); Int16Array, -1 where unreachable. Doors count as open. */
  function bfsCells(w, sx, sy) {
    const W2 = w.width;
    const H2 = w.height;
    const dist = new Int16Array(W2 * H2).fill(-1);
    const q = new Int32Array(W2 * H2);
    if (!(sx >= 0 && sy >= 0 && sx < W2 && sy < H2)) return dist;
    let head = 0;
    let tail = 0;
    dist[sy * W2 + sx] = 0;
    q[tail++] = sy * W2 + sx;
    const dx = [1, -1, 0, 0];
    const dy = [0, 0, 1, -1];
    while (head < tail) {
      const cur = q[head++];
      const cx = cur % W2;
      const cy = (cur - cx) / W2;
      for (let k = 0; k < 4; k++) {
        const nx = cx + dx[k];
        const ny = cy + dy[k];
        if (nx < 0 || ny < 0 || nx >= W2 || ny >= H2) continue;
        const ni = ny * W2 + nx;
        if (dist[ni] >= 0) continue;
        const ch = w.tileAt(nx + 0.5, ny + 0.5);
        if (w.isSolid(nx + 0.5, ny + 0.5) && ch !== 'D' && ch !== 'G') continue;
        dist[ni] = dist[cur] + 1;
        q[tail++] = ni;
      }
    }
    return dist;
  }

  /** Find the farthest open safe spot (by walking distance from the crypt door) in the map that links to the crypt. Sets S.farSpot or null. */
  function computeFarSpot() {
    S.farSpot = null;
    try {
      for (let n = 0; n < S.worldNames.length && !S.farSpot; n++) {
        const name = S.worldNames[n];
        const w = S.worlds[name];
        if (!w || !w.doorsById || (w.spots.crypt && w.spots.crypt.length)) continue;
        let door = null;
        const ids = Object.keys(w.doorsById);
        for (let i = 0; i < ids.length && !door; i++) {
          const d = w.doorsById[ids[i]];
          const tw = d ? S.worlds[d.toMap] : null;
          if (tw && tw.spots.crypt && tw.spots.crypt.length) door = d;
        }
        const safe = w.spots.safe || [];
        if (!door || !safe.length) continue;
        const a = w.arrival(door.id);
        if (!a) continue;
        const dist = bfsCells(w, Math.floor(a.x), Math.floor(a.y));
        let best = null;
        for (let i = 0; i < safe.length; i++) {
          if (isSealedIn(name, safe[i])) continue;
          const cx = Math.floor(safe[i].x);
          const cy = Math.floor(safe[i].y);
          const d = dist[cy * w.width + cx];
          if (d >= 0 && (!best || d > best.d)) best = { map: name, cx: cx, cy: cy, d: d };
        }
        S.farSpot = best;
      }
      if (S.farSpot) L().info('Far spot ' + S.farSpot.map + ' ' + S.farSpot.cx + ',' + S.farSpot.cy + ' dist ' + S.farSpot.d);
    } catch (err) {
      S.farSpot = null;
      L().warn('computeFarSpot failed', err);
    }
  }

  /** True if sp is the far safe spot of the current map. */
  function isFarSpot(sp) {
    const f = S.farSpot;
    return !!f && f.map === S.mapName && Math.floor(sp.x) === f.cx && Math.floor(sp.y) === f.cy;
  }

  /** Sleeping at the far spot: +5 Essence (stored in hunger.essenceBonus, so saves stay valid). */
  function awardFarSpot() {
    if (!S.hunger) return;
    S.hunger.essenceBonus = Math.min(1000, (Number.isFinite(S.hunger.essenceBonus) ? S.hunger.essenceBonus : 0) + 5);
    showCard('+5 Essence', 0.2, 'A far, dark corner of town.');
    L().info('Far spot bonus +5 Essence');
  }

  /** Random in 0..1 from the seeded ambience rng (Math.random if not set up). */
  function frng() {
    return S.farRng ? S.farRng() : Math.random();
  }

  /** Re-seed the far-sound timers for the current night. */
  function initAmbient() {
    const seed = S.run && Number.isFinite(S.run.seed) ? S.run.seed : 1;
    S.farRng = mulberry32(mixSeed(seed, 77, S.night ? S.night.night : 1));
    S.dogT = 20 + frng() * 20;
    S.bellT = 20 + frng() * 20;
  }

  /** Ambience bed follows the player's room kind; silent on menu, pause and run end. Only calls Audio on change. */
  function updateAmbience() {
    const a = S.audio;
    if (!a) return;
    const live = S.runOn && (S.state === 'playing' || S.state === 'feeding' || S.state === 'sleeping' || S.state === 'transition');
    const kind = live ? (S.roomKind === 'outdoor' ? 'outdoor' : 'indoor') : 'none';
    if (!live) { VCS.Audio.fireBed(a, 0, 0, 0); VCS.Audio.fireBed(a, 1, 0, 0); }
    const lvl = cfgNum('ambienceGain', 0.6);
    if (kind === S.ambKey && lvl === S.ambLvl) return;
    const ok = VCS.Audio.ambience(a, { kind: kind, level01: lvl });
    if (ok || kind === 'none') {
      S.ambKey = kind;
      S.ambLvl = lvl;
    }
  }

  /** Position of the door that leads toward the crypt from the current map, or null (also null inside the crypt). */
  function cryptDoorPos() {
    const w = S.world;
    if (!w || !w.doorsById || (w.spots.crypt && w.spots.crypt.length)) return null;
    const ids = Object.keys(w.doorsById);
    for (let i = 0; i < ids.length; i++) {
      const d = w.doorsById[ids[i]];
      const tw = d ? S.worlds[d.toMap] : null;
      if (tw && tw.spots.crypt && tw.spots.crypt.length) return { x: d.col + 0.5, y: d.row + 0.5 };
    }
    return null;
  }

  const FAR_OPTS = { pan: 0, dist: 8 };
  const BREATH_OPTS = { pan: 0, dist: 3, behind: false, occluded: false };

  /** Scheduled dog (outdoors) and church bell (from the crypt door's direction), plus per-person breathing. */
  function stepAmbient(dt) {
    const a = S.audio;
    const p = S.player;
    if (!a || !p) return;
    S.dogT -= dt;
    S.bellT -= dt;
    if (S.dogT <= 0) {
      S.dogT = 20 + frng() * 20;
      if (S.roomKind === 'outdoor') {
        FAR_OPTS.pan = frng() * 2 - 1;
        FAR_OPTS.dist = 6 + frng() * 6;
        VCS.Audio.oneShotFar(a, 'dog', FAR_OPTS);
      }
    }
    if (S.bellT <= 0) {
      S.bellT = 20 + frng() * 20;
      const cd = cryptDoorPos();
      if (cd) VCS.Audio.play(a, 'bell', spatial(cd.x, cd.y, Math.min(1, level('bell').gain * 2)));
    }
    const st = S.people;
    if (!st) return;
    const list = st.people;
    for (let i = 0; i < list.length; i++) {
      const q = list[i];
      if (q.mode === 'fed') continue;
      const dx = q.x - p.x;
      const dy = q.y - p.y;
      if (dx * dx + dy * dy >= 36) continue;
      if (q.breathT === undefined) q.breathT = 0.3 + frng() * 2;
      q.breathT -= dt;
      if (q.breathT > 0) continue;
      q.breathT = 2 + frng();
      BREATH_OPTS.dist = Math.sqrt(dx * dx + dy * dy);
      BREATH_OPTS.pan = panTo(q.x, q.y);
      BREATH_OPTS.behind = Math.cos(Math.atan2(dy, dx) - p.angle) < 0;
      BREATH_OPTS.occluded = occludedTo(q.x, q.y);
      VCS.Audio.breath(a, BREATH_OPTS);
    }
    stepHeartbeats(dt, list);
  }

  const HEART_OPTS = { pan: 0, dist: 1, behind: false, occluded: false, bpm: 70 };

  // Neutral pulse state when the vessel helpers are not loaded (bpm 65, no blood scaling).
  const HEART_FALLBACK = { pulse: true, bpm: 65, stateK: 1, periphK: 1, headK: 1 };

  /** Vessel mode name for a villager: flee/cower 130, startle (or bumping) 100, wary 90, otherwise calm 65. */
  function heartMode(q) {
    if (q.mode === 'flee' || q.mode === 'cower') return q.mode;
    if (q.mode === 'startle' || q.bumping) return 'startle';
    if (q.wary > 0) return 'wary';
    return 'calm';
  }

  /**
   * Villager pulse state (single source of truth for the audio heartbeat and the vheart echo): VCS.Vessels.state
   * with blood = left/pool, so bpm follows the research curve (rises to ~1.3x at 40% blood, then falls to 0 at
   * empty), capped at 175 bpm. Returns { pulse, bpm, stateK, periphK, headK }.
   */
  function heartState(q) {
    const V = VCS.Vessels;
    if (!V || typeof V.state !== 'function') return HEART_FALLBACK;
    const blood = q.pool > 0 ? clamp(q.left / q.pool, 0, 1) : 1;
    return V.state('villager', heartMode(q), blood);
  }

  /** Villager bpm (0 = no pulse). */
  function heartBpm(q) {
    return heartState(q).bpm;
  }

  /**
   * Heartbeat of the nearest two villagers within hearDist (2.5 cells; also through a wall: the occlusion filter dulls it): sound plus a chest pulse.
   * The drink victim is skipped: drinkBeat owns its beat while the player drinks.
   */
  function stepHeartbeats(dt, list) {
    const a = S.audio;
    const p = S.player;
    const hear = level('vheart').hearDist || 2.5;
    const victim = S.drink ? S.drink.person : null;
    let n1 = null;
    let d1 = hear * hear;
    let n2 = null;
    let d2 = hear * hear;
    for (let i = 0; i < list.length; i++) {
      const q = list[i];
      if (q.mode === 'fed' || q === victim) continue;
      const dx = q.x - p.x;
      const dy = q.y - p.y;
      const d = dx * dx + dy * dy;
      if (d >= d2) continue;
      if (d < d1) { n2 = n1; d2 = d1; n1 = q; d1 = d; } else { n2 = q; d2 = d; }
    }
    for (let k = 0; k < 2; k++) {
      const q = k === 0 ? n1 : n2;
      if (!q) continue;
      if (q.heartT === undefined) q.heartT = 0.2 + frng() * 0.6;
      q.heartT -= dt;
      if (q.heartT > 0) continue;
      const hs = heartState(q);
      if (!hs.pulse || !(hs.bpm > 0)) { q.heartT = 0.5; continue; }
      const bpm = hs.bpm;
      q.heartT = 60 / bpm;
      // Snapshot fields for the vheart echo (People.updateEchoes copies them onto the echo).
      q.heartBpm = bpm;
      q.heartStateK = hs.stateK;
      q.heartPeriphK = hs.periphK;
      q.heartHeadK = hs.headK;
      HEART_OPTS.dist = Math.sqrt(k === 0 ? d1 : d2);
      HEART_OPTS.pan = panTo(q.x, q.y);
      HEART_OPTS.behind = Math.cos(Math.atan2(q.y - p.y, q.x - p.x) - p.angle) < 0;
      HEART_OPTS.occluded = occludedTo(q.x, q.y);
      HEART_OPTS.bpm = bpm;
      // Each beat also sends a small chest-high pulse (like a footstep does for the feet) that shows the chest.
      emitSound('vheart', q.x, q.y, { z: 0.65 });
      if (a) VCS.Audio.heartbeat(a, HEART_OPTS);
    }
  }

  const TUT_TEXT = {
    ping: 'Click or Space to listen',
    person: 'Echoes that move are people — hold right-click close to drink',
    vial: 'Vial = blood. Drink past full for gifts',
    fear: 'Eyes by the clock = fear',
    sleep: 'E at the crypt or a dark spot to sleep',
    light: 'Eye = light on you. Stay dark to stay unseen'
  };

  /** Which tutorial hints were already seen in this browser (vcs.seen entries "tut:<id>"). */
  function tutSeenMap() {
    if (S.tutSeen) return S.tutSeen;
    const m = Object.create(null);
    try {
      const v = JSON.parse(root.localStorage.getItem('vcs.seen') || '[]');
      if (Array.isArray(v)) {
        for (let i = 0; i < v.length && i < 40; i++) {
          if (typeof v[i] === 'string' && v[i].indexOf('tut:') === 0) m[v[i].slice(4)] = true;
        }
      }
    } catch (e) { /* ignore */ }
    S.tutSeen = m;
    return m;
  }

  /** Queue a first-time hint (once per browser, once per session). */
  function tutQueue(id) {
    if (!S.runOn) return;
    const seen = tutSeenMap();
    if (!S.tutQd) S.tutQd = Object.create(null);
    if (seen[id] === true || S.tutQd[id] === true) return;
    S.tutQd[id] = true;
    S.tutQ.push({ id: id, text: TUT_TEXT[id], dur: id === 'ping' ? 60 : 5 });
  }

  /** Mark a hint seen for good. */
  function tutMark(id) {
    tutSeenMap()[id] = true;
    markSeen('tut:' + id);
  }

  /** Drop the queue and the visible hint (new night, new run). */
  function tutClear() {
    S.tutQ.length = 0;
    S.tutCur = null;
    S.tutAge = 0;
  }

  /** New run or continued run: reset the session flags and queue the first hint. */
  function tutStart() {
    tutClear();
    S.tutQd = Object.create(null);
    tutQueue('ping');
  }

  /** The first pulse retires the "Click or Space" hint for good. */
  function tutPulsed() {
    const seen = tutSeenMap();
    if (seen.ping === true) return;
    tutMark('ping');
    if (S.tutCur && S.tutCur.id === 'ping') S.tutCur = null;
    for (let i = S.tutQ.length - 1; i >= 0; i--) if (S.tutQ[i].id === 'ping') S.tutQ.splice(i, 1);
  }

  /** Per-frame: trigger conditions, then show one hint at a time when no card is up. */
  function stepTutorial(dt) {
    const n = S.night;
    if (n) {
      if (n.blood < 50) tutQueue('vial');
      if (S.hunger && S.hunger.fear > 0) tutQueue('fear');
      if (S.veilK > 0.5) tutQueue('light');
      if (n.night === 1 && n.min >= 510) tutQueue('sleep');
    }
    if (S.cardText !== null || S.hintT > 0) return;
    if (S.tutCur) {
      S.tutAge += dt;
      if (S.tutAge > S.tutCur.dur) S.tutCur = null;
    } else if (S.tutQ.length && S.state === 'playing') {
      S.tutCur = S.tutQ.shift();
      S.tutAge = 0;
      if (S.tutCur.id !== 'ping') tutMark(S.tutCur.id);
    }
  }

  /** Fear-scaled react config; rebuilt only when dazedTime, fear, still or mist state changes (no per-frame allocation). */
  function reactCfgNow() {
    const dz = cfgNum('dazedTime', 3);
    const h = S.hunger;
    const calm = !!h && (VCS.Hunger.isStill(h) || !!S.mist);
    const key = (h ? h.fear : 0) * 2 + (calm ? 1 : 0);
    if (S.reactDazed !== dz || !S.reactCfg || S.reactKey !== key) {
      S.reactDazed = dz;
      S.reactKey = key;
      const base = VCS.SoundData ? VCS.SoundData.react : null;
      const fm = h ? VCS.Hunger.fearMods(h) : { startleMul: 1, fleeMul: 1, calmMul: 1 };
      S.fm = fm;
      const cfg = Object.assign({}, base, { dazedTime: dz });
      cfg.startleDist = (base && typeof base.startleDist === 'number' ? base.startleDist : 3) * fm.startleMul;
      cfg.fleeMul = (base && typeof base.fleeMul === 'number' ? base.fleeMul : 1.6) * fm.fleeMul;
      cfg.calmAfter = (base && typeof base.calmAfter === 'number' ? base.calmAfter : 10) * (typeof fm.calmMul === 'number' ? fm.calmMul : 1);
      if (calm) cfg.bumpDist = 0;
      S.reactCfg = cfg;
    }
    return S.reactCfg;
  }

  /** Shared People ctx object (reused each frame). */
  function peopleCtx() {
    const c = S.pctx;
    c.player = S.player;
    c.playerLit = S.playerLit;
    c.react = reactCfgNow();
    c.t = S.clock;
    c.grace = S.grace;
    c.nightFrac = S.night ? VCS.Night.clock(S.night).frac : 0;
    c.nightSec = S.night ? S.night.nightSec : 0;
    c.fear = S.hunger ? S.hunger.fear : 0;
    return c;
  }

  /** Tell the current map's people that a sound happened at (x,y). */
  function reactTo(x, y, kind, dist) {
    if (!S.people || !S.player) return;
    if ((kind === 'ping' || kind === 'door') && S.hunger && VCS.Hunger.isStill(S.hunger)) return;
    if (dist === undefined && (kind === 'ping' || kind === 'door')) {
      const base = VCS.SoundData && VCS.SoundData.react && typeof VCS.SoundData.react.startleDist === 'number' ? VCS.SoundData.react.startleDist : 4;
      reactCfgNow();
      dist = base * fxv('noise') * S.fm.startleMul;
    }
    try {
      VCS.People.react(S.people, x, y, kind, peopleCtx(), dist);
      drainPeopleEvents();
    } catch (err) {
      L().warn('People.react failed', err);
    }
  }

  /** Turn scream/startle events into sound pulses and audio. */
  function drainPeopleEvents() {
    const evs = VCS.People.drainEvents(S.people);
    for (let i = 0; i < evs.length; i++) {
      const e = evs[i];
      if (e.type === 'flee' && S.drink && e.id !== S.drink.id) S.drink.interrupt = true;
      const kind = e.type === 'scream' ? 'scream' : e.type === 'startle' ? 'startle' : e.type === 'whimper' ? 'whimper' : '';
      if (!kind) continue;
      emitSound(kind, e.x, e.y);
      if (S.audio) VCS.Audio.play(S.audio, kind, spatial(e.x, e.y, level(kind).gain));
    }
  }

  /** Door cells the player may interact with: spots.doors plus G gates. */
  function interactDoors(w) {
    if (!w._gates) {
      const g = [];
      for (let y = 0; y < w.height; y++) {
        for (let x = 0; x < w.width; x++) if (w.tileAt(x + 0.5, y + 0.5) === 'G') g.push({ x: x + 0.5, y: y + 0.5 });
      }
      w._gates = g;
    }
    const base = (w.spots && w.spots.doors) || [];
    return w._gates.length ? base.concat(w._gates) : base;
  }

  const FIRE_NEAR = 1.5;
  const fireLvl = [0, 0];
  const fireIdx = [-1, -1];
  const fireD = [Infinity, Infinity];

  /** Steady fire noise bed: the 2 nearest torches within FIRE_NEAR cells, level fading to 0 at that distance, panned to the torch. */
  function crackleTorches() {
    const a = S.audio;
    if (!a) return;
    const lights = S.world && S.world.lights;
    const p = S.player;
    const live = !!(lights && lights.length && p && S.runOn && (S.state === 'playing' || S.state === 'feeding'));
    fireIdx[0] = fireIdx[1] = -1;
    fireD[0] = fireD[1] = Infinity;
    if (live) {
      for (let i = 0; i < lights.length; i++) {
        const dx = lights[i].x - p.x;
        const dy = lights[i].y - p.y;
        if (dx > FIRE_NEAR || dx < -FIRE_NEAR || dy > FIRE_NEAR || dy < -FIRE_NEAR) continue;
        const d = Math.sqrt(dx * dx + dy * dy);
        if (d >= FIRE_NEAR) continue;
        if (d < fireD[0]) { fireD[1] = fireD[0]; fireIdx[1] = fireIdx[0]; fireD[0] = d; fireIdx[0] = i; }
        else if (d < fireD[1]) { fireD[1] = d; fireIdx[1] = i; }
      }
    }
    for (let k = 0; k < 2; k++) {
      const i = fireIdx[k];
      if (i < 0) { fireLvl[k] = 0; VCS.Audio.fireBed(a, k, 0, 0); continue; }
      const L0 = lights[i];
      const lv = 1 - fireD[k] / FIRE_NEAR;
      fireLvl[k] = lv;
      VCS.Audio.fireBed(a, k, lv, panTo(L0.x, L0.y));
    }
  }

  /** If the player stands in an open link door (not the one just arrived by), start a transition. True if it did. */
  function checkLinkDoor() {
    const w = S.world;
    const p = S.player;
    const cx = Math.floor(p.x);
    const cy = Math.floor(p.y);
    const ja = S.justArrived;
    if (ja && (ja.map !== S.mapName || ja.cx !== cx || ja.cy !== cy)) S.justArrived = null;
    if (S.cool > 0 || S.justArrived || typeof w.doorAt !== 'function') return false;
    const d = w.doorAt(cx, cy);
    if (!d || !w.isDoorOpen(cx, cy)) return false;
    return changeMap(d.toMap, d.toDoor);
  }

  /** Begin a wipe transition through a link door. Returns true if started. */
  function changeMap(toMap, toDoor) {
    if (S.transition || S.state !== 'playing') {
      L().warn('changeMap ignored: already transitioning or not playing (' + toMap + ')');
      return false;
    }
    const tw = S.worlds && typeof toMap === 'string' ? S.worlds[toMap] : null;
    if (!tw || !tw.arrival(toDoor)) {
      L().warn('E_MAP_LINK: no such map/door ' + toMap + '/' + toDoor);
      return false;
    }
    const ms = S.config && typeof S.config.transitionMs === 'number' ? S.config.transitionMs : 700;
    S.transition = { toMap: toMap, toDoor: toDoor, t: 0, dur: Math.max(100, ms) / 1000, swapped: false };
    S.wipeK = 0;
    S.pendingPause = false;
    if (S.input) S.input.keys.clear();
    setState('transition');
    S.wasLocked = S.input ? S.input.isLocked() : false;
    L().info('Transition ' + S.mapName + ' -> ' + toMap + '/' + toDoor);
    if (S.audio) VCS.Audio.play(S.audio, 'creak', { gain: level('creak').gain, pan: 0 });
    return true;
  }

  /** Advance the active transition by dt; swaps maps at the midpoint, finishes at the end. */
  function stepTransition(dt) {
    const tr = S.transition;
    if (!tr) {
      setState('playing');
      return;
    }
    tr.t += dt;
    const half = tr.dur / 2;
    if (!tr.swapped) {
      S.wipeK = Math.min(1, tr.t / half);
      if (tr.t >= half) {
        S.wipeK = 1;
        tr.swapped = true;
        const a = S.worlds[tr.toMap].arrival(tr.toDoor);
        enterMap(tr.toMap, a.x, a.y, a.angle, tr.toDoor);
      }
    } else {
      S.wipeK = Math.max(0, 1 - (tr.t - half) / half);
      if (tr.t >= tr.dur) {
        S.wipeK = 0;
        S.transition = null;
        setState('playing');
        S.cool = 0.3;
        if (S.pendingPause) {
          S.pendingPause = false;
          pause();
        }
      }
    }
  }

  /** Swap to map `name` placing the player at (x,y,angle); resets sonar, echoes, rings, audio. doorId opens the arrival door. */
  function enterMap(name, x, y, angle, doorId) {
    endDrink('map');
    S.landings.length = 0;
    const old = S.people;
    if (old) VCS.People.clearEchoes(old);
    S.rocks.length = 0;
    VCS.Sonar.reset(S.sonar);
    if (S.ripple) S.ripple.rings.length = 0;
    if (S.audio) VCS.Audio.stopAll(S.audio, 0.15);
    S.mapName = name;
    S.world = S.worlds[name];
    S.people = peopleFor(name);
    VCS.Player.place(S.player, x, y, angle);
    applyRoom(S.world);
    S.justArrived = null;
    if (doorId) {
      const d = S.world.doorsById[doorId];
      if (d) {
        S.world.setDoor(d.col, d.row, true);
        S.justArrived = { map: name, cx: d.col, cy: d.row };
      }
      pushOffPeople();
    }
    S.grace = (VCS.SoundData && VCS.SoundData.react && VCS.SoundData.react.arriveGrace) || 1;
    S.playerLit = safeLight(S.world, S.player.x, S.player.y);
    S.stepTimer = 0;
    S.hudA = 0;
    S.bobAmp = 0;
    S.cool = 0.3;
    L().info('Entered map ' + name);
  }

  /** If the arrival point overlaps a person, nudge the player forward along its facing (up to 0.6) when free. */
  function pushOffPeople() {
    const ps = S.people ? S.people.people : [];
    const p = S.player;
    let hit = false;
    for (let i = 0; i < ps.length; i++) if (Math.hypot(ps[i].x - p.x, ps[i].y - p.y) < 0.5) hit = true;
    if (!hit) return;
    for (let d = 0.6; d >= 0.1; d -= 0.1) {
      const nx = p.x + Math.cos(p.angle) * d;
      const ny = p.y + Math.sin(p.angle) * d;
      if (!S.world.blocks(nx, ny, p.radius || 0.2)) {
        p.x = nx;
        p.y = ny;
        return;
      }
    }
  }

  /** Test hook (only with ?debug=1): jump to a map instantly (no wipe). */
  function debugMap(name, doorId) {
    if (!S.worlds || !S.worlds[name]) {
      L().warn('debugMap: unknown map ' + name);
      return false;
    }
    const w = S.worlds[name];
    const a = doorId ? w.arrival(doorId) : startPlace(w);
    if (!a) {
      L().warn('debugMap: unknown door ' + doorId);
      return false;
    }
    S.transition = null;
    S.wipeK = 0;
    S.pendingPause = false;
    if (S.state === 'transition') setState('playing');
    enterMap(name, a.x, a.y, a.angle, doorId || null);
    return true;
  }

  /** Serializable game state (v3: v2 plus the run: seed, boons, sealed safe spots, pending boon choice). */
  function getSnapshot() {
    const doors = {};
    const people = {};
    for (let n = 0; n < S.worldNames.length; n++) {
      const name = S.worldNames[n];
      const w = S.worlds[name];
      const open = [];
      for (let y = 0; y < w.height; y++) {
        for (let x = 0; x < w.width; x++) {
          const ch = w.tileAt(x + 0.5, y + 0.5);
          if ((ch === 'D' || ch === 'G') && w.isDoorOpen(x, y)) open.push([x, y]);
        }
      }
      if (open.length) doors[name] = open;
      if (S.peopleByMap[name]) people[name] = S.peopleByMap[name].seed;
    }
    const p = S.player || { x: 0, y: 0, angle: 0 };
    const snap = { v: 4, map: S.mapName, player: { x: p.x, y: p.y, angle: p.angle }, doors: doors, people: people };
    if (S.night) snap.night = VCS.Night.serialize(S.night);
    snap.rocks = S.rocksLeft;
    snap.run = cloneRun(S.run);
    snap.run.hunger = S.hunger ? VCS.Hunger.serialize(S.hunger) : null;
    return snap;
  }

  /** Restore a snapshot; validates everything, ignores bad fields, never throws. Returns true if the map was applied. */
  function applySnapshot(snap) {
    try {
      if (!snap || typeof snap !== 'object' || (snap.v !== 1 && snap.v !== 2 && snap.v !== 3 && snap.v !== 4) || !S.worlds || !S.player) {
        L().warn('applySnapshot: invalid snapshot');
        return false;
      }
      const fin = function (v) { return typeof v === 'number' && isFinite(v); };
      const has = function (o, k) { return Object.prototype.hasOwnProperty.call(o, k); };
      S.rocksLeft = fin(snap.rocks) ? clamp(Math.round(snap.rocks), 0, ROCKS_PER_RUN) : ROCKS_PER_RUN;
      if (typeof snap.map !== 'string' || !has(S.worlds, snap.map)) {
        L().warn('applySnapshot: unknown map ' + String(snap.map));
        return false;
      }
      if (snap.v >= 3) {
        const rs = validateRun(snap.run);
        if (!rs) {
          L().warn('applySnapshot: invalid run section');
          return false;
        }
        const raw = rs.hunger;
        delete rs.hunger;
        S.run = rs;
        let hs = null;
        if (snap.v >= 4 && raw) {
          hs = VCS.Hunger.restore(raw);
          if (!hs) L().warn('applySnapshot: bad hunger state, starting fresh');
        }
        S.hunger = hs || VCS.Hunger.create();
        S.reactKey = -1;
        S.fx = computeFx();
      }
      if (snap.people && typeof snap.people === 'object') {
        for (const name in snap.people) {
          if (!has(snap.people, name)) continue;
          if (!has(S.worlds, name) || !fin(snap.people[name])) {
            L().warn('applySnapshot: ignoring people for ' + name);
            continue;
          }
          peopleFor(name, snap.people[name]);
        }
      }
      if (snap.doors && typeof snap.doors === 'object') {
        for (const name in snap.doors) {
          if (!has(snap.doors, name)) continue;
          const w = has(S.worlds, name) ? S.worlds[name] : null;
          if (!w || !Array.isArray(snap.doors[name])) {
            L().warn('applySnapshot: ignoring doors for ' + name);
            continue;
          }
          for (const c of snap.doors[name]) {
            if (!Array.isArray(c) || !Number.isInteger(c[0]) || !Number.isInteger(c[1])) continue;
            const ch = w.tileAt(c[0] + 0.5, c[1] + 0.5);
            if (ch === 'D' || ch === 'G') w.setDoor(c[0], c[1], true);
          }
        }
      }
      const w = S.worlds[snap.map];
      const pl = snap.player;
      let pos = startPlace(w);
      if (pl && typeof pl === 'object' && fin(pl.x) && fin(pl.y) && pl.x > 0 && pl.y > 0 && pl.x < w.width && pl.y < w.height && !w.blocks(pl.x, pl.y, 0.2)) {
        pos = { x: pl.x, y: pl.y, angle: fin(pl.angle) ? pl.angle : 0 };
      } else {
        L().warn('applySnapshot: bad player position, using start');
      }
      if (snap.v >= 2 && snap.night !== undefined && snap.night !== null) {
        const cur = S.night;
        const rn = VCS.Night.restore(snap.night, {
          nightSec: (S.config && typeof S.config.nightLengthMin === 'number' ? S.config.nightLengthMin : 4) * 60 * fxv('nightLen'),
          drainMul: fxv('drain') * DRAIN_BASE,
          ramp: VCS.HungerData ? VCS.HungerData.RAMP : 0,
          nights: cur ? cur.nights : undefined,
          bloodMax: cur ? cur.bloodMax : undefined
        });
        if (rn) {
          S.night = rn;
          S.seedBase = rn.night > 1 ? rn.night * 100 : 0;
          S.clkMin = -1;
        } else {
          L().warn('applySnapshot: invalid night, keeping current');
        }
      }
      endDrink('snapshot');
      S.transition = null;
      S.wipeK = 0;
      S.seq = null;
      if (S.state === 'transition' || S.state === 'feeding' || S.state === 'sleeping') setState('playing');
      enterMap(snap.map, pos.x, pos.y, pos.angle, null);
      applyFx();
      return true;
    } catch (err) {
      L().error('applySnapshot failed', err);
      return false;
    }
  }

  /** State snapshot for tests and debugging. */
  /** Distinct wall materials the last ping's rays hit (names), for smoke checks of the per-hit material data. */
  function pingMaterials() {
    const lp = S.sonar && S.sonar.lastPulse;
    if (!lp || !lp.vmat || !VCS.Sonar.hitInfo) return [];
    const seen = {};
    const h = {};
    for (let i = 0; i < lp.vis.length; i++) {
      VCS.Sonar.hitInfo(lp, (i / lp.vis.length) * Math.PI * 2, h);
      if (h.hit) seen[h.mat] = true;
    }
    return Object.keys(seen);
  }

  function debugState() {
    const p = S.player || { x: 0, y: 0, angle: 0 };
    return {
      state: S.state,
      player: { x: p.x, y: p.y, angle: p.angle },
      fps: S.fps,
      errors: errorCount(),
      view: S.view,
      pulses: S.sonar ? S.sonar.pulses.length : 0,
      voices: S.audio && S.audio.ctx && S.audio.ctx.__vcsVoices ? S.audio.ctx.__vcsVoices.length : 0,
      pingMats: pingMaterials(),
      litColumns: S.renderer ? VCS.Render.stats(S.renderer).litColumns : 0,
      people: S.people ? VCS.People.snapshot(S.people) : [],
      echoes: S.people ? S.people.echoes.length : 0,
      rings: S.ripple ? S.ripple.rings.length : 0,
      doorsOpen: countOpenDoors(),
      sounds: soundCounts(),
      soundZ: soundHeights(),
      lineBoil: S.config ? S.config.lineBoil !== false : true,
      map: S.mapName,
      transition: S.transition ? { to: S.transition.toMap, k: S.wipeK, swapped: S.transition.swapped } : null,
      playerLit: S.playerLit,
      peopleModes: S.people ? S.people.people.map(function (p) { return p.mode; }) : [],
      card: S.cardText,
      cardSub: S.cardSub,
      tutHint: S.tutCur ? S.tutCur.text : null,
      farSpot: S.farSpot ? { map: S.farSpot.map, cx: S.farSpot.cx, cy: S.farSpot.cy, d: S.farSpot.d } : null,
      saving: { failed: S.saveFailed, otherTab: S.otherTab },
      ambience: S.ambKey,
      reduced: S.reduced,
      hint: S.hintT > 0,
      night: nightInfo(),
      fed: S.night ? S.night.fedCount : 0,
      drink: S.drink ? { id: S.drink.id, left: S.drink.left, pool: S.drink.pool, drunk: S.drink.drunk, mode: S.drink.person.mode } : null,
      victim: victimInfo()
    };
  }

  /** Last victim's id, mode and remaining blood (null if none yet). */
  function victimInfo() {
    const v = S.lastVictim;
    if (!v || !v.people) return null;
    const ps = v.people.people;
    for (let i = 0; i < ps.length; i++) {
      if (ps[i].id === v.id) return { id: v.id, mode: ps[i].mode, left: ps[i].left, pool: ps[i].pool };
    }
    return null;
  }

  /** Test hook (only with ?debug=1): grab the person in front, hold the drink for up to `seconds` simulated seconds (stops early if the drink ends), then let go. True if it started. */
  function debugFeedHold(seconds) {
    if (!startDrink(true)) return false;
    const n = Math.max(1, Math.round((seconds || 0) * 60));
    for (let i = 0; i < n && S.drink; i++) debugAdvance(1 / 60);
    if (S.drink) endDrink('released');
    return true;
  }

  /** Night summary for debugState (null before the first start). */
  function nightInfo() {
    const n = S.night;
    if (!n) return null;
    return { n: n.night, clock: VCS.Night.clock(n).text, blood: n.blood, status: n.status, weak: VCS.Night.weakness(n), nightSec: n.nightSec };
  }

  /** Number of open doors. */
  function countOpenDoors() {
    const w = S.world;
    if (!w || typeof w.isDoorOpen !== 'function') return 0;
    let n = 0;
    for (let i = 0; i < w.spots.doors.length; i++) {
      if (w.isDoorOpen(Math.floor(w.spots.doors[i].x), Math.floor(w.spots.doors[i].y))) n++;
    }
    return n;
  }

  /** Active pulse count by kind (also 'bounce' for gen > 0). */
  function soundCounts() {
    const out = {};
    const ps = S.sonar ? S.sonar.pulses : [];
    for (let i = 0; i < ps.length; i++) {
      const k = ps[i].kind || 'ping';
      out[k] = (out[k] || 0) + 1;
      if (ps[i].gen > 0) out.bounce = (out.bounce || 0) + 1;
    }
    return out;
  }

  /** Max source height z of active pulses per kind (for tests). */
  function soundHeights() {
    const out = {};
    const ps = S.sonar ? S.sonar.pulses : [];
    for (let i = 0; i < ps.length; i++) {
      const k = ps[i].kind || 'ping';
      const z = typeof ps[i].z === 'number' ? ps[i].z : 0.5;
      if (!(k in out) || z > out[k]) out[k] = z;
    }
    return out;
  }

  /** Test hook (only with ?debug=1): emit a pulse at the player as if clicked. */
  function debugPulse() {
    if (!S.sonar || !S.player) return false;
    L().debug('debugPulse');
    return pulse();
  }

  /** Test hook (only with ?debug=1): move the player without collision checks. */
  function debugTeleport(x, y, angle) {
    if (!S.player) return false;
    S.player.x = x;
    S.player.y = y;
    if (typeof angle === 'number') S.player.angle = angle;
    L().debug('debugTeleport ' + x + ',' + y);
    return true;
  }

  /** Test hook (only with ?debug=1): run the simulation forward in 1/60 s steps without rendering. */
  function debugAdvance(seconds) {
    if (S.state !== 'playing' && S.state !== 'transition' && S.state !== 'feeding' && S.state !== 'sleeping') return false;
    const n = Math.max(1, Math.round((seconds || 0) * 60));
    for (let i = 0; i < n; i++) {
      S.wasLocked = false;
      update(1 / 60);
    }
    return true;
  }

  const Game = { boot: boot, debugState: debugState, fatal: fatal, getSnapshot: getSnapshot, applySnapshot: applySnapshot };
  // Test hook: binds just enough state to exercise the audio helpers without booting.
  Game.__test = {
    bind: function (o) { Object.assign(S, o); },
    firstSolid: firstSolid, blockMaterial: blockMaterial, occlusionTo: occlusionTo,
    pingEcho: pingEcho, floorBounce: floorBounce, personEcho: personEcho,
    heartState: heartState, heartBpm: heartBpm, stepHeartbeats: stepHeartbeats
  };
  VCS.Game = Game;
  if (typeof module !== 'undefined' && module.exports) module.exports = Game;

  if (typeof window !== 'undefined' && root.document) {
    if (root.document.readyState === 'loading') {
      root.document.addEventListener('DOMContentLoaded', boot);
    } else {
      boot();
    }
  }
})(typeof window !== 'undefined' ? window : globalThis);
