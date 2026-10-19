# VCS modular plan (v0.10.x baseline: 504 unit tests green, game.js 4026 lines)

Goal: work on ONE system at a time, tune it live in the browser, send values back, commit. No build step, no libs, IIFE + `window.VCS`, CSP `script-src 'self'`, DOM APIs only.

Key finding: the leaf modules are already decent (world/sonar/ripple/night/hunger/meta/save are pure-ish). The problem is two monoliths: `game.js` (4026, integrator + ~15 embedded systems) and `render.js` (3182, 8 drawing systems). Modularising = peeling those two apart, NOT rewriting the leaves.

## 1. System map

Lines = current file size. "game.js owns" = clusters still inside game.js (approx line ranges, from `function` map).

| System | Files (lines) | game.js calls / owns | Shared state |
|---|---|---|---|
| Core/log/config/checks | log 237, config 226, checks 92 | `VCS.Log` x12, `Config` x3; game.js 154-330 (state, fatal, report box) | `Config` settings, `S.state` |
| World/doors/light/glass | world 652, raycast 78, data/maps 294 | `World` 1 call but `S.world` passed everywhere; door logic game.js 977-1060, 3579-3730 (interact, crackle, link, changeMap) | `S.world`, door open flags |
| Player/input | player 84, input 270 | `Player` x6, `Input` x1; walk/bob/footsteps game.js 953-1020, 1139 | `S.player` |
| **Sonar/echoes/ripples** | sonar 376, ripple 192; render pulse/ring/arc fns (render.js 889-1300, 2673) | `Sonar` x13, `Ripple` x8; game.js `pulse` 1152-1235, `bounceEchoes`, `markerRipples`, `simulateWorld` 1093-1139 | `S.sonar`, `S.ripple`, `S.clock` |
| **Acoustics (sound->world)** | audio 967, data/sounds 52; game.js `emitSound/panTo/occludedTo/spatial/stepMaterial` 859-953, `peopleSounds` 1060 | `Audio` x40, `SoundData` x30 (the most-coupled pair) | `S.world`, listener pose |
| People/AI/reactions | people 1060; render `drawPerson` 1628-2229 (600 lines!); game.js 3516-3580 (`reactCfgNow/peopleCtx/reactTo/drainPeopleEvents`), 3239-3266 (`peopleFor`) | `People` x15 | `S.people`, pools, refuges |
| Feeding | game.js 515-670 (`startDrink/stepDrink/endDrink/feedFx`), 1510 | uses People grab/drink | `S.feed`, blood |
| Night/clock/sleep | night 291 (pure); game.js 466-500, 671-830 | `Night` x21 | `S.night` |
| Hunger/powers | hunger 307, data/hunger 58; powers game.js 2572-2830 (`usePower/doShriek/startMist/doStill`) | `Hunger` x23 | `S.hunger` |
| Meta/upgrades/boons | meta 255, data/upgrades 66; shop/boon UI game.js 2245-2300, 2447-2570 | `Meta` x18 | `S.meta`, essence |
| Save/storage | save 589; game.js 2009-2163 (tab lock, saveRun/Meta), 3769-3890 (snapshot) | `Save` x22 | storage keys `vcs.*` |
| Render: walls/doors/windows | render 760-890, 612-760, 1008-1300 | `Render` x13 | `S.render`, config |
| Render: people/props/flames | render 1628-2229, 2229-2673 | via `Render.drawFirstPerson` | cam, people |
| Render: atmosphere/HUD overlays | render 2711-2850, 3082-3182; hud 675, icons 328 | `Hud` x4, `Icons` x5 | S.* read-only |
| Ambience/tutorial/far-spot | game.js 3263-3516 | n/a | `S.amb`, tut flags |
| Menus/settings/overlays | game.js 1605-1840, 2163-2447, 2871-2962 | DOM | `Config` |
| Debug hooks | game.js 2962-3028, 3749-4016; DESIGN §12 | `?debug=1` | all |

Planned (TODO.md): acoustics/echoes (v0.11), hidden meter, villager schedules (V1), voices/subtitles (W3,V5), items/lights (V6), animals (V8), watch (V9), bigger map (V7). Each gets its own module from day one (section 2).

## 2. Module contract

One system = `js/<sys>.js` (+ optional `js/data/<sys>.js`) + `tests/<sys>.test.js`. Registered on a tiny bus; game.js only calls `VCS.Sys.update(dt, S)` in a fixed order.

```js
// js/system.js  (new, ~120 lines, loaded right after config.js)
(function (root) {
  'use strict';
  const VCS = (root.VCS = root.VCS || {});
  const list = [];            // ordered
  const subs = Object.create(null);
  const Sys = {
    /** def = { id, order, tunables:{key:{v,min,max,step,doc}}, init(ctx), update(dt,ctx), teardown(ctx) } */
    register(def) { list.push(def); list.sort((a, b) => a.order - b.order); VCS.Flags.declare(def); },
    initAll(ctx)   { each('init', ctx); },
    update(dt, ctx){ for (const d of list) if (VCS.Flags.on(d.id)) guard(d, 'update', dt, ctx); },
    teardownAll(ctx){ each('teardown', ctx); },
    on(ev, fn)  { (subs[ev] = subs[ev] || []).push(fn); },
    emit(ev, p) { for (const fn of subs[ev] || []) try { fn(p); } catch (e) { VCS.Log.get('bus').error(ev, e); } },
    t(id, key)  { return VCS.Flags.tun(id, key); },   // live tunable read, falls back to def default
  };
  function guard(d, fn, a, b) { try { d[fn] && d[fn](a, b); } catch (e) { VCS.Log.get(d.id).error(fn, e); VCS.Flags.trip(d.id); } }
  VCS.Sys = Sys;
})(typeof window !== 'undefined' ? window : globalThis);

// js/acoustics.js
VCS.Sys.register({
  id: 'acoustics', order: 30,
  tunables: { glassLoss: { v: 0.4, min: 0, max: 1, step: 0.01 }, echoDecay: { v: 1.2, min: 0.2, max: 4, step: 0.05 } },
  init(ctx) {}, update(dt, ctx) {}, teardown(ctx) {},
});
```
Rules:
- Reads only `ctx` (= `S`) + its own tunables; never another system's internals. Cross-system talk = events: `sound` {x,y,kind,level}, `pulse`, `door`, `feed:start`, `person:react`, `night:dawn`, `map:enter`. Existing direct calls (e.g. `Audio` from `emitSound`) stay until that system is migrated; then game.js subscribes instead.
- A failing `update` is caught, logged, and the system is auto-disabled (`Flags.trip`) so the game keeps running (matches "error checking and logging" rule).
- Pure logic stays Node-testable (the `getData()` require-fallback pattern in hunger.js is the template). Tunables live in the module, not scattered constants (e.g. render.js `WIN_GLOW_MAX`, `DOOR_GAIN`, `MAX_DIST` become tunables of their system).
- Save: a module with persistent state exposes `serialize()/restore(o)`; `Save` validates under its key (existing SAVE_KEYS pattern).

## 3. Flags + live tuning (the "work live, go back and forth" core)

New `js/flags.js` (~150 lines) = `VCS.Flags`: `declare(def)`, `on(id)`, `set(id,bool)`, `tun(id,key)`, `setTun(id,key,v)`, `dump()`, `trip(id)`.
- Ids are `system` or `system.feature` (`acoustics`, `acoustics.beam`, `people.schedule`). Default = current behaviour: every new mechanic is declared `{default:false}` until the user approves it, or `true` if it reproduces old behaviour exactly. Old code paths stay as the else-branch until the flag is retired (delete the flag + old branch in a later cleanup commit).
- Precedence: URL > localStorage > default. URL: `?sys=acoustics.beam:on,people.schedule:off` (parse with `URLSearchParams`, ignore unknown ids with a log warn). `?tun=acoustics.glassLoss:0.6` likewise.
- Persistence: `localStorage` keys `vcs.dev.flags`, `vcs.dev.tun`, all in try/catch (Save's safe-storage helper already exists; reuse it). Production (`debug` off) ignores `vcs.dev.*` unless `?sys=` is given, so players never see experiments.
- Dev panel: `js/devpanel.js` (~250 lines, loaded only if `?debug=1`; F9 toggles, `hidden` attribute; CSS in `css/dev.css`, `style-src 'self'` OK). Built with `createElement/textContent` only:
  - one row per system: checkbox (on/off), status dot (red if tripped), per-feature checkboxes;
  - per-tunable `<input type=range min max step>` + number box, "reset" per row, live apply on `input` event (no reload);
  - buttons: "Copy tunables JSON" (`navigator.clipboard.writeText(JSON.stringify(Flags.dump(),null,1))`, fallback to a `<textarea>` select), "Paste JSON" (apply), "Reset all", "Reload with flags" (builds the `?sys=` URL);
  - small perf readout per system (ms/frame via `performance.now()` around `guard`), which also gives the TODO "Perf gate".
- The JSON the user sends back looks like `{"flags":{"acoustics.beam":true},"tun":{"acoustics":{"glassLoss":0.55}}}`; the agent pastes the numbers into the module's `tunables` defaults + flips `default`, commit. Include `VERSION` in dump so stale pastes are detectable.
- Existing debug hooks (`debugTime`, `debugTeleport`, ...) stay; panel adds "teleport to scene spot", "set time", "give blood" buttons that call them.

## 4. Isolation testing

1. Unit: one `tests/<sys>.test.js` per module, `node --test`. Rule: any new module must add >=1 test file; baseline 504 must stay green. Event-bus + Flags get their own tests (precedence, URL parse, try/catch storage, tripped system skipped).
2. Sandbox scenes: `?scene=NAME` (debug only, like `?map=`). Add `data/scenes.js` registering extra maps in `MapData`: 
   - `acoustics-lab`: ~24x16 grid, a strip of every material (stone, wood, glass, plaster, metal per `materialAt`), one wood door (closed) + one open doorway, a glass window wall, a 12-tile corridor with a dead end, a big hall, one stationary person at each of 3 distances, no night clock/hunger (`Night` frozen via `ctx.lab=true`).
   - `people-lab` (walkers + paths, schedule fast-forward), `render-lab` (all props, windows lit/dark), `feed-lab`.
   - Each scene sets start pose/time/seed so screenshots are reproducible (`?seed=7`).
3. Smoke subset: `node tests/smoke.mjs --only acoustics` (add `ONLY` filter: each check group tagged by system; untagged = core, always run). `--list` prints groups. Screenshots to `tests/out/<sys>-*.png` for diffing by eye.
4. Per-flag matrix test: for each declared flag, unit test asserts `default` state reproduces the current output (golden values captured before the change) = guarantee "no behaviour change until flipped".
5. Gate before commit: `node --test tests/*.test.js && node tests/smoke.mjs --only <sys>`; full smoke only at release.

## 5. Workflow loop + ownership

Loop (per system): 1 pick system from TODO -> 2 agent reads its read set only -> 3 adds code behind `sys.feature` flag (default off) + tunables + unit tests -> 4 user opens `?debug=1&scene=<sys>-lab&sys=<sys>.<feature>:on`, flips and slides live -> 5 user pastes "Copy tunables JSON" -> 6 agent bakes defaults, flips flag default if approved, bumps version, commit -> 7 unit + `--only` smoke -> 8 repeat; full smoke + sim at release.

Ownership (parallel agents never touch the same file):

| Owner | Writes | Never touches |
|---|---|---|
| acoustics | acoustics.js, data/sounds.js, audio.js, tests/acoustics+audio | people.js, render.js |
| sonar-visual | sonar.js, ripple.js, render/ sonar layer, tests/sonar+ripple+render(sonar) | audio.js |
| people | people.js, data/people.js (new), schedules, tests/people | render people |
| people-render | render/people.js (after split) | people.js logic |
| world/map | world.js, data/maps.js, scenes.js | game.js |
| economy | night/hunger/meta + data, tools/sim.mjs | render |
| ui | hud, icons, menus (split from game.js), css | systems |
| integrator (Opus lead only) | game.js, flags.js, system.js, index.html script order, DESIGN.md | |

Shared-file rule: `game.js`, `index.html`, `DESIGN.md` are edited ONLY by the lead, in small registration diffs (one `<script>` line + one `Sys.register`). Systems add a section to their own doc header rather than DESIGN.md until release.

## 6. Migration from the monolith (small, safe steps)

Each step: pure move + thin delegate; run `node --test tests/*.test.js` (504) and `node tests/smoke.mjs` after; commit alone so any step is revertible. game.js size is the estimate after the step.

| # | Step | Risk | game.js after |
|---|---|---|---|
| 0 | Add `system.js` + `flags.js` + tests; no callers (load order after config.js; add to index.html). | Very low | 4026 |
| 1 | `devpanel.js` + `css/dev.css` behind `?debug=1`; panel shows empty registry. Smoke asserts panel hidden w/o debug. | Low | 4030 |
| 2 | Extract **debug hooks** (2962-3028, 3749-4016, `getSnapshot/applySnapshot`) to `js/debug.js`; game.js passes `S` + accessors. First: zero gameplay risk, biggest cut. | Low | ~3550 |
| 3 | Extract **menus/shop/stats/settings/import-export UI** (1605-1840, 2163-2447, 2871-2962) to `js/menu.js` (DOM only). | Low-med (DOM ids; smoke covers) | ~2850 |
| 4 | Extract **ambience/tutorial/far-spot** (3263-3516) to `js/ambience.js`, `js/tutorial.js`. | Low | ~2600 |
| 5 | **Acoustics**: move `emitSound/panTo/occludedTo/spatial/stepMaterial/playerSteps/peopleSounds` (859-1093) into `js/acoustics.js` as `Sys` module; game.js emits `sound` events. Identical math, flag `acoustics.legacy` default on. This is the first real system and the one next in TODO (v0.11 Echoes); do it right before building echoes. | Med (most coupled: Audio x40, SoundData x30; audio.test + smoke audio) | ~2350 |
| 6 | Extract **feeding** (515-670) + **powers** (2572-2830) to `feeding.js`, `powers.js`. | Med (state machine `feeding`) | ~1850 |
| 7 | Extract **doors/map transitions** (977-1060, 3579-3730) to `doors.js`. | Med (link doors, snapshot) | ~1500 |
| 8 | Extract **people reactions** glue (3516-3580, 3239-3266) into `people.js`/`reactions.js`. | Med | ~1400 |
| 9 | Split **render.js** into `render/` files via `VCS.Render.parts`: `walls.js` (760-1300), `people.js` (1628-2229), `props.js` (2229-2673), `overlay.js` (2711-3182). Keep `Render` facade API (render.test unchanged). | Med-high (shared closures/consts like CELL, STYLES; do one part per commit) | 1400 |
| 10 | Run loop becomes `Sys.update()` list; game.js = state machine + boot + loop (~1000). | Med | ~1000 |

Order of new work: step 0-1 first (user gets the panel immediately), then 5 (acoustics) in parallel with 2-4 (different files). Do not start 9 until a render feature needs it; do only the part being worked on.
Invariants every step: script order in index.html respected (data before modules, game.js last); no `innerHTML/eval`; `Log` errors on every catch; save format unchanged (`Save` tests); `?seed=7` smoke screenshots visually identical.

## 7. Token/cost: read sets per system

Never read game.js whole. Use `grep -n "function \|VCS\.<Sys>"` and read the listed ranges only. Approx. line counts to read:

| Working on | Read set | ~lines |
|---|---|---|
| Acoustics/echoes | DESIGN §6; data/sounds.js 52; audio.js (grep `play`, `spatial` areas ~300); game.js 859-1235; sonar.js 376; tests/audio+sonar | ~1100 |
| Sonar/ripple visuals | sonar 376, ripple 192, render 889-1300 + 2673-2711; game.js `pulse` 1152-1235 | ~1000 |
| People/schedules | DESIGN §5; people.js (1060, grep sections); data/maps.js people paths; game.js 3239-3266, 3516-3580 | ~1500 |
| Villager look/models | render 1570-2229; DESIGN §5 | ~700 |
| Windows/lights/items | render 612-760, 2229-2673; world.js light/glass fns; DESIGN §6.1 | ~900 |
| Hidden meter / HUD | hud.js 675; game.js 1451-1510; night.js 291 | ~1000 |
| Economy (night/hunger/meta) | those 3 + data files + tools/sim.mjs; DESIGN §3,8,9 | ~900 |
| Save/schema | save.js 589; game.js 2009-2163, 3769-3890; DESIGN §7 | ~900 |
| Map/world | world.js 652, data/maps.js 294, DESIGN §10 | ~950 |
| UI/menus | game.js 1605-1840 / 2163-2447 (until step 3 done, then menu.js); index.html; css | ~700 |
| Flags/panel | system.js, flags.js, devpanel.js (all new, ~520) | ~520 |

Savings tactics: (1) agents get this file's section 1 + their read set in the prompt, nothing else; (2) after steps 2-9 the read sets shrink 30-50% since each system is one file; (3) cheap models (Haiku/Sonnet) do mechanical moves (steps 2-4, 6-8) with the 504-test gate as the safety net, Opus only for the contract, acoustics, and render split; (4) user tuning is done by sliders + pasted JSON, so a "tweak a number" round trip costs ~0 agent tokens until the commit; (5) keep per-module header comment (purpose, tunables, events in/out, 10 lines) so an agent never needs DESIGN.md for a single-system task.
