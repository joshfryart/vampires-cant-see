#!/usr/bin/env node
// Economic agent sim for "Vampires Can't See". No map, no deps.
// Usage: node tools/sim.mjs [--runs N] [--seed N] [--json]
//          [--poolMin N] [--poolMax N] [--fearSleep N] [--drainRamp X] [--giftCosts a,b]
// The last five override the loaded game values for this simulation only.
//
// Rules and numbers come from the real modules (js/night.js, js/hunger.js,
// js/data/hunger.js, js/meta.js, js/data/upgrades.js, js/config.js). Only the
// items listed under SIM ASSUMPTIONS below are not in the game code.

import { createRequire } from 'node:module';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const require = createRequire(import.meta.url);
const JS = resolve(dirname(fileURLToPath(import.meta.url)), '..', 'js');

// Load the data modules first so the logic modules resolve them via VCS.
const HungerData = require(join(JS, 'data', 'hunger.js'));
const UpgradeData = require(join(JS, 'data', 'upgrades.js'));
const Config = require(join(JS, 'config.js'));
const Night = require(join(JS, 'night.js'));
const Hunger = require(join(JS, 'hunger.js'));
const Meta = require(join(JS, 'meta.js'));

const DEFAULTS = Config.DEFAULTS;

// ---- clock helpers (minutes since 20:00, same scale as Night.clock) ----
function minOf(h, m) { return h >= 20 ? (h - 20) * 60 + m : (h + 4) * 60 + m; }
const T_0200 = minOf(2, 0);   // 360
const T_0300 = minOf(3, 0);   // 420
const T_0430 = minOf(4, 30);  // 510

// ---- SIM ASSUMPTIONS (not in the game code) ----
const DT = 0.1;                    // seconds per tick; equals Night.update's dt clamp
const SIM_MAX_TICKS = 200000;      // guard against a stuck run
const SEARCH_S = [25, 60];         // victim search time, seconds (spec)
const TRAVEL_S = [20, 60];         // travel home, seconds (spec)
const WEAK_SEARCH_MUL = 1.5;       // spec: weak -> search x1.5
const SEARCH_FEAR_PER_FEAR = HungerData.FEAR_FLEE[0]; // spec's 0.03 per fear point (same value, reused)
const DRINK_BASE = 6;              // drink rate 6 + 14 x left/pool (game.js:525, not exported)
const DRINK_SLOPE = 14;
const SLEEP_BLOOD = 80;            // sleep early once blood >= this after 03:00
const SHRIEK_AFTER = 40;           // greedy shrieks when searching longer than this
const BALANCED_MIST_P = 0.15;      // balanced: chance to mist at each search start
const BALANCED_STILL_P = 0.1;      // balanced: chance to still at each drink start
const BALANCED_OVERFLOW_UNTIL = T_0300;

const POLICIES = {
  cautious: { overflow: () => false, shriekAfter: null, mistP: 0, stillP: 0 },
  greedy: { overflow: () => true, shriekAfter: SHRIEK_AFTER, mistP: 0, stillP: 0 },
  balanced: { overflow: (min) => min < BALANCED_OVERFLOW_UNTIL, shriekAfter: null, mistP: BALANCED_MIST_P, stillP: BALANCED_STILL_P }
};
const META_TIERS = { none: 0, mid: 1, max: 3 };

// ---- CLI overrides (simulation only; game files are never changed) ----
// null means "use the game value". Set from argv in parseArgs.
const OV = {
  poolMin: DEFAULTS.poolMin,
  poolMax: DEFAULTS.poolMax,
  fearSleep: null,        // fear change on sleep; game: HungerData.FEAR.sleep
  ramp: HungerData.RAMP,  // drain ramp per night; game: HungerData.RAMP
  giftCosts: null         // overflow cost per gift; game: HungerData.GIFT_COSTS
};
const GIFTS_PER_NIGHT = HungerData.GIFTS_PER_NIGHT;

function costOverride(st) {
  const n = Math.floor(st.giftsTonight);
  if (!(n >= 0) || n >= GIFTS_PER_NIGHT || n >= OV.giftCosts.length) return null;
  return OV.giftCosts[n];
}

// Same contract as Hunger.isOpen / Hunger.addOverflow, with the cost swapped
// when --giftCosts is given. Without it, these are the game functions.
const Gifts = {
  isOpen(st) {
    return OV.giftCosts === null ? Hunger.isOpen(st) : costOverride(st) !== null;
  },
  addOverflow(st, amt) {
    if (OV.giftCosts === null) return Hunger.addOverflow(st, amt);
    const c = costOverride(st);
    if (c === null) return { taken: 0, ready: false };
    if (!(st.over >= 0)) st.over = 0;
    const room = Math.max(0, c - st.over);
    const taken = amt > 0 ? Math.min(amt, room) : 0;
    st.over = Math.min(c, st.over + taken);
    return { taken, ready: st.over >= c };
  }
};

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

function makeMeta(tier) {
  const m = Meta.create();
  if (tier > 0) UpgradeData.upgrades.forEach((u) => { m.upgrades[u.id] = tier; });
  return m;
}

function nightSecFor(fx) {
  return DEFAULTS.nightLengthMin * 60 * fx.nightLen;
}

function runOne(polName, metaName, runSeed) {
  const pol = POLICIES[polName];
  const rng = mulberry32(runSeed);
  const meta = makeMeta(META_TIERS[metaName]);
  const boons = [];
  const taken = [];
  let fx = Meta.effects(meta, boons, []);

  const st = Night.create({
    nightSec: nightSecFor(fx),
    bloodStart: Math.min(Night.DEFAULTS.bloodMax, Night.DEFAULTS.bloodStart + fx.startBlood),
    ramp: OV.ramp,
    drainMul: fx.drain
  });
  const hst = Hunger.create();

  const out = {
    nightsSurvived: 0, won: false, fed: 0, gifts: 0, fearSleep: [], bloodSleep: [],
    nightsPlayed: 0, bored: 0, lossCause: null, essence: 0
  };

  let phase = 'search';
  let elapsed = 0;
  let timer = 0;
  let shrieked = false;
  let victims = 0;
  let pool = 1;
  let left = 0;
  let hitMax = null;   // clock minute when blood first reached max this night
  let ended = false;

  function usePower(id) {
    const u = Hunger.use(hst, id, st.night, st.blood);
    if (u.ok) st.blood = Math.max(0, st.blood - u.cost);
    return u.ok;
  }

  function searchTime() {
    const base = SEARCH_S[0] + rng() * (SEARCH_S[1] - SEARCH_S[0]);
    const fear = 1 + hst.fear * SEARCH_FEAR_PER_FEAR;
    const weak = Night.weakness(st) > 0 ? WEAK_SEARCH_MUL : 1;
    return base * fear * weak;
  }

  function searchStart() {
    phase = 'search';
    elapsed = 0;
    shrieked = false;
    timer = searchTime();
    if (pol.mistP > 0 && rng() < pol.mistP) usePower('mist');
  }

  function startDrink() {
    victims++;
    Hunger.onGrab(hst, st.night * 100000 + victims);
    pool = OV.poolMin + rng() * (OV.poolMax - OV.poolMin);
    left = pool;
    phase = 'drink';
    if (pol.stillP > 0 && rng() < pol.stillP) usePower('still');
  }

  function sleepDue() {
    return st.min >= T_0430 || (st.min >= T_0300 && st.blood >= SLEEP_BLOOD);
  }

  function decide() {
    if (sleepDue()) {
      phase = 'travel';
      timer = TRAVEL_S[0] + rng() * (TRAVEL_S[1] - TRAVEL_S[0]);
    } else {
      searchStart();
    }
  }

  function claimGift() {
    const ids = Hunger.rollGifts(hst, runSeed + st.night * 131);
    if (!ids.length) return;
    const pick = ids[Math.floor(rng() * ids.length)];
    if (Hunger.takeGift(hst, pick).ok) out.gifts++;
  }

  function closeNight() {
    if (hitMax !== null && hitMax < T_0200) out.bored++;
  }

  function sleepNow() {
    closeNight();
    out.fearSleep.push(hst.fear);
    out.bloodSleep.push(st.blood);
    const fearBefore = hst.fear;
    const nb = Hunger.onSleep(hst);
    if (OV.fearSleep !== null) {
      hst.fear = Math.min(HungerData.FEAR_MAX, Math.max(0, fearBefore + OV.fearSleep));
    }
    const res = Night.sleep(st);
    if (res === 'none') {
      out.lossCause = 'error';
      ended = true;
      return;
    }
    out.nightsSurvived++;
    if (res === 'won') {
      out.won = true;
      ended = true;
      return;
    }
    const offered = Meta.rollBoons(runSeed + st.night * 7919, taken);
    if (offered.length) {
      const id = offered[Math.floor(rng() * offered.length)];
      taken.push(id);
      const b = Meta.boonById(id);
      if (b && b.effect === 'bloodNow') Night.addBlood(st, b.value);
      else boons.push(id);
      fx = Meta.effects(meta, boons, Hunger.giftMods(hst));
    }
    if (nb > 0) Night.addBlood(st, nb);
    st.nightSec = nightSecFor(fx);
    st.drainMul = fx.drain;
    hitMax = null;
    out.nightsPlayed++;
    searchStart();
  }

  out.nightsPlayed = 1;
  searchStart();

  let lost = null;
  for (let tick = 0; tick < SIM_MAX_TICKS && !ended; tick++) {
    const ev = Night.update(st, DT, { outdoor: true });
    Hunger.tick(hst, DT);
    if (ev.indexOf('lost') >= 0) {
      lost = phase === 'travel' ? 'sun:travel' : 'sun:hunt';
      break;
    }

    if (phase === 'search') {
      elapsed += DT;
      timer -= DT;
      if (pol.shriekAfter !== null && !shrieked && elapsed > pol.shriekAfter && usePower('shriek')) {
        shrieked = true;
        timer *= 0.5; // assumption: a shriek halves the remaining search
      }
      if (timer <= 0) startDrink();
    } else if (phase === 'drink') {
      const rate = (DRINK_BASE + DRINK_SLOPE * Math.min(1, Math.max(0, left / pool))) * fx.drinkRate;
      const gain = rate * DT;
      left = Math.max(0, left - gain);
      const got = Night.addBlood(st, gain);
      const rest = gain - got;
      const overflowOn = pol.overflow(st.min) && Gifts.isOpen(hst);
      let done = false;
      if (rest > 0 && overflowOn && Gifts.addOverflow(hst, rest).ready) {
        claimGift();
        done = true;
      } else if (left <= 0.5) {
        out.fed++;
        done = true;
      } else if (st.blood >= st.bloodMax && !overflowOn) {
        done = true;
      }
      if (done) decide();
    } else if (phase === 'travel') {
      timer -= DT;
      if (timer <= 0) sleepNow();
    }

    if (hitMax === null && st.blood >= st.bloodMax) hitMax = st.min;
  }

  if (lost !== null) {
    closeNight();
    out.lossCause = lost;
  } else if (!out.won && out.lossCause === null) {
    out.lossCause = 'guard';
  }
  out.essence = Meta.essenceFor({ nights: out.nightsSurvived, fed: out.fed, won: out.won }) + hst.essenceBonus;
  return out;
}

function seedFor(base, i) {
  return (Math.imul(base >>> 0, 0x9E3779B1) + Math.imul(i + 1, 0x85EBCA77)) >>> 0;
}

function mean(xs) { return xs.length ? xs.reduce((a, b) => a + b, 0) / xs.length : 0; }

function aggregate(results) {
  const n = results.length;
  const wins = results.filter((r) => r.won).length;
  const fearAll = results.flatMap((r) => r.fearSleep);
  const bloodAll = results.flatMap((r) => r.bloodSleep);
  const played = results.reduce((a, r) => a + r.nightsPlayed, 0);
  const bored = results.reduce((a, r) => a + r.bored, 0);
  const causes = {};
  for (const r of results) if (r.lossCause) causes[r.lossCause] = (causes[r.lossCause] || 0) + 1;
  const losses = {};
  for (const k of Object.keys(causes)) losses[k] = (causes[k] / n) * 100;
  return {
    win: (wins / n) * 100,
    nights: mean(results.map((r) => r.nightsSurvived)),
    essence: mean(results.map((r) => r.essence)),
    gifts: mean(results.map((r) => r.gifts)),
    fearSleep: mean(fearAll),
    bloodSleep: mean(bloodAll),
    boredPct: played ? (bored / played) * 100 : 0,
    losses
  };
}

function parseArgs(argv) {
  const o = { runs: 200, seed: 1, json: false };
  const num = (a, v, min, max, int) => {
    if (!Number.isFinite(v) || v < min || v > max || (int && !Number.isInteger(v))) {
      throw new Error(`bad value for ${a}: ${v}`);
    }
    return v;
  };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--json') { o.json = true; continue; }
    if (a === '--runs' || a === '--seed') {
      const v = Number(argv[++i]);
      const max = a === '--runs' ? 1000000 : 4294967295;
      const min = a === '--runs' ? 1 : 0;
      if (!Number.isInteger(v) || v < min || v > max) throw new Error(`bad value for ${a}`);
      o[a.slice(2)] = v;
      continue;
    }
    // Overrides: simulation only.
    if (a === '--poolMin') { OV.poolMin = num(a, Number(argv[++i]), 1, 500, false); continue; }
    if (a === '--poolMax') { OV.poolMax = num(a, Number(argv[++i]), 1, 500, false); continue; }
    if (a === '--fearSleep') { OV.fearSleep = num(a, Number(argv[++i]), -15, 15, true); continue; }
    if (a === '--drainRamp') { OV.ramp = num(a, Number(argv[++i]), 0, 2, false); continue; }
    if (a === '--giftCosts') {
      const parts = String(argv[++i] || '').split(',').map((s) => Number(s.trim()));
      if (parts.length < 1 || parts.length > GIFTS_PER_NIGHT) throw new Error(`--giftCosts takes 1..${GIFTS_PER_NIGHT} values`);
      OV.giftCosts = parts.map((v) => num(a, v, 1, 1000, true));
      continue;
    }
    throw new Error(`unknown argument: ${a}`);
  }
  if (OV.poolMin > OV.poolMax) throw new Error(`--poolMin (${OV.poolMin}) must be <= --poolMax (${OV.poolMax})`);
  return o;
}

function overridesText() {
  const parts = [];
  if (OV.poolMin !== DEFAULTS.poolMin || OV.poolMax !== DEFAULTS.poolMax) parts.push(`pool=${OV.poolMin}-${OV.poolMax}`);
  if (OV.fearSleep !== null) parts.push(`fearSleep=${OV.fearSleep}`);
  if (OV.ramp !== HungerData.RAMP) parts.push(`ramp=${OV.ramp}`);
  if (OV.giftCosts !== null) parts.push(`giftCosts=${OV.giftCosts.join(',')}`);
  return parts.length ? parts.join(' ') : 'game defaults';
}

function fmtLosses(losses) {
  const keys = Object.keys(losses);
  if (!keys.length) return '-';
  return keys.map((k) => `${k} ${losses[k].toFixed(1)}%`).join(', ');
}

function main() {
  const opts = parseArgs(process.argv.slice(2));
  const rows = [];
  for (const polName of Object.keys(POLICIES)) {
    for (const metaName of Object.keys(META_TIERS)) {
      const results = [];
      for (let i = 0; i < opts.runs; i++) results.push(runOne(polName, metaName, seedFor(opts.seed, i)));
      rows.push({ policy: polName, meta: metaName, ...aggregate(results) });
    }
  }

  if (opts.json) {
    console.log(JSON.stringify({ runs: opts.runs, seed: opts.seed, nights: Night.DEFAULTS.nights, overrides: overridesText(), results: rows }, null, 2));
    return;
  }

  const head = ['Policy', 'Meta', 'Win%', 'Nights', 'Essence', 'Gifts', 'Fear@sleep', 'Blood@sleep', 'Bored%', 'Losses'];
  const lines = rows.map((r) => [
    r.policy, r.meta, r.win.toFixed(1), r.nights.toFixed(2), r.essence.toFixed(1), r.gifts.toFixed(2),
    r.fearSleep.toFixed(2), r.bloodSleep.toFixed(1), r.boredPct.toFixed(1), fmtLosses(r.losses)
  ]);
  const widths = head.map((h, c) => Math.max(h.length, ...lines.map((l) => l[c].length)));
  const row = (cells) => cells.map((c, i) => c.padEnd(widths[i])).join('  ');
  console.log(`runs=${opts.runs} seed=${opts.seed} nights=${Night.DEFAULTS.nights} nightSec(base)=${nightSecFor({ nightLen: 1 })} overrides: ${overridesText()}`);
  console.log(row(head));
  console.log(row(widths.map((w) => '-'.repeat(w))));
  for (const l of lines) console.log(row(l));
}

try {
  main();
} catch (err) {
  console.error(`sim failed: ${err && err.message}`);
  process.exitCode = 1;
}
