# Vampires Can't See - Design (v0.19.0)

Single source of truth for rules and numbers. Code wins if this drifts; data lives in `js/data/*.js` and `js/config.js`.

## 1. Rules and coding standards

| Rule | Detail |
|---|---|
| Module shape | Classic script IIFE `(function (root) { ... })(typeof window !== 'undefined' ? window : globalThis)`; attach to `root.VCS`; also `module.exports` for Node |
| Dependencies | No libraries, no build, no network. Double-click `index.html` to run |
| Forbidden | `innerHTML`, `outerHTML`, `insertAdjacentHTML`, `document.write`, `eval`, `new Function`, `confirm()`, `alert()` |
| DOM | Only `createElement` + `textContent` |
| Errors | Public functions never throw: guard, return result objects `{ok, code}`, log via `VCS.Log.get('<module>')` (may be missing: use a no-op logger) |
| Frame errors | Each frame error is logged `Frame error n/3`. A good frame resets the count. Three in a row show the error screen (`E_LOOP`) |
| Storage keys | Start with `vcs.` (`vcs.settings`, `vcs.run`, `vcs.meta`, `vcs.tab`, `vcs.seen`). Session key `vcs.tabid` |
| Untrusted input | Reject keys `__proto__`, `constructor`, `prototype`; read own props only; clamp numbers |
| Data modules | Deep-frozen |
| CSP | No inline script, no external loads |
| Tests | `node:test` in `tests/`; full suite must stay green |
| Version | `VCS.Log.VERSION` in `js/log.js` (`'0.19.0'`) |
| Style | Dim, hand-drawn, boiled thin lines; no blood or gore drawn; every cue has an audio and a visual twin; nothing flashes above 3 Hz |

## 2. Module map

Script order in `index.html`: log, config, checks, data (maps, sounds, upgrades, hunger), then modules; `game.js` last.

| File | Global | Purpose |
|---|---|---|
| `js/log.js` | `VCS.Log` | Logging, error reports, `VERSION` |
| `js/config.js` | `VCS.Config` | Validated settings (`vcs.settings`), `DEFAULTS`, `SCHEMA` |
| `js/checks.js` | `VCS.Checks` | Browser feature checks at boot |
| `js/data/maps.js` | `VCS.MapData` | Maps `test`, `crypt`, `town`: grids, doors, props, zones, people paths, hides |
| `js/data/sounds.js` | `VCS.SoundData` | Sound levels, room kinds, `react` constants |
| `js/data/upgrades.js` | `VCS.UpgradeData` | Effect defaults/limits, 9 upgrades, 9 boons |
| `js/data/hunger.js` | `VCS.HungerData` | Powers, gifts, fear, drain ramp |
| `js/data/vessels.js` | `VCS.VesselData`, `VCS.Vessels` | Arterial/venous node graph on pose slots, PWV delays, pulse state per mode (drawn by `render.js` `drawVessels` behind `vis.vessels`) |
| `js/data/archetypes.js` | `VCS.ArchetypeData` | NPC archetypes (14 rows), look schema ranges and enums, legacy recipe, REINFORCE table (Section 5.5) |
| `js/raycast.js` | `VCS.Raycast` | DDA grid raycasting |
| `js/world.js` | `VCS.World` | Tile grid, doors, torches, light, glass, `kindAt`, `materialAt` |
| `js/player.js` | `VCS.Player` | Movement, turning, collision |
| `js/input.js` | `VCS.Input` | Keyboard, mouse, drag-to-look, pointer lock, `feedHeld()` |
| `js/sonar.js` | `VCS.Sonar` | Pulse emission, range/fade/cooldown, echoes |
| `js/ripple.js` | `VCS.Ripple` | Secondary rings, line wobble, `inward` rings, jitter |
| `js/forge.js` | `VCS.Forge` | NPC Forge: seeded look generation from archetypes, look validation and alter, custom library (`vcs.forge`), reinforcement rule (Section 5.5) |
| `js/people.js` | `VCS.People` | Walkers, reactions, lit and hide refuges, grab/drink/release, pools, mid-night spawn/despawn/alter |
| `js/night.js` | `VCS.Night` | Clock, blood, weakness, dawn, sleep (pure state) |
| `js/meta.js` | `VCS.Meta` | Essence, upgrades, stats, boons, effects |
| `js/hunger.js` | `VCS.Hunger` | Overflow gifts, powers, fear (pure state) |
| `js/save.js` | `VCS.Save` | Safe storage, envelope, checksum, run validation, tab lock, import/export |
| `js/audio.js` | `VCS.Audio` | WebAudio synthesized kinds, distance/occlusion/behind filtering, ambience beds |
| `js/render.js` | `VCS.Render` | First-person view, outlines, people echoes, warm halo, feed vignette |
| `js/hud.js` | `VCS.Hud` | Vial, dial, powers, fear, cards, fades, dawn grain |
| `js/icons.js` | `VCS.Icons` | 13 doodle icons, tombstone, crypt menu |
| `js/game.js` | `VCS.Game` | Loop, states, menus, overlays, tutorial hints, ambience, debug hooks |
| `tools/sim.mjs` | none | Economy simulation (Section 13) |

Game states: `title`, `playing`, `paused`, `transition`, `feeding`, `sleeping`, `boon`, `gift`, `runend`, `error`.

## 3. Night and blood

Source: `js/night.js`, `js/config.js`, `js/game.js`, `js/data/hunger.js`.

| Item | Value |
|---|---|
| Clock | 20:00 to 06:00 = 600 game minutes. Minute 540 = 05:00, 570 = 05:30 |
| Night length | `config.nightLengthMin` (default 4, schema 2..30) x 60 x `fx.nightLen` real seconds. The settings slider offers 4..12 |
| Nights per run | 5 (win after sleeping through night 5) |
| Blood max / start | 100 / `min(100, 10 + fx.startBlood)` |
| Base drain | `bloodMax / nightSec` per real second x `fx.drain` x ramp |
| Drain ramp | `RAMP` 0.12: x `(1 + 0.12 x (night - 1))`. N1 1.00, N2 1.12, N3 1.24, N4 1.36, N5 1.48. Set per run in `Night.create` (`ramp`, not serialized) |
| Weak | blood < 25: `weak = 1 - blood/25`. Pulse range and strength x `(1 - 0.4 weak)`, fade x `(1 - 0.3 weak)`; outline flickers, pulse gets `weak` |
| Chime | 05:00 (minute 540), once per night; card "Dawn" |
| Wash-out | from 05:30: `washK = (min - 570)/30`; outdoor pulses range x `(1 - 0.5 washK)`, fade x `(1 - 0.6 washK)` |
| Dawn | 06:00: clock stops, status `day`. Outdoors then = run lost (reason `sun`); indoors you survive but stepping outside while day = lost. You must still sleep |
| Sleep spots | Crypt bed `C` (one, in the crypt) and safe spots `S` (town has three: barn, cellar, shed). Must be within reach (`SoundData.reach` 1.3 cells) |
| Closed safe spots | Per run, each map with >= 2 `S` spots closes `min(16, floor(n/3))` of them (seeded by run seed). Town: 1 of 3 closed. Crypt never closes. Sealed spot: card "Sealed" + `miss` sound |
| Far safe spot | Per run, the open safe spot with the greatest walking distance from the crypt door (BFS, doors open). Sleeping there: +5 Essence each time (card "+5 Essence", stored in `hunger.essenceBonus`) |
| Sleep | `Night.sleep` -> `next` (night++, clock reset, people rebuilt) or `won`. Blood carries over |
| Sleep sequence | 2.2 s: fade out 0.8, `Night.sleep` at 0.8, hold 0.6, fade in 0.8. Ignores Esc, clicks and lost pointer lock |
| Interact order (E) | door in front, then sleep spot, then old `interact` sound |
| Night events | `chime`, `washout`, `dawn`, `lost` (each once per night) |

Night state: `{night, nights, nightSec, min, blood, bloodMax, feedGain, status: night|day|won|lost, reason, fired, fedCount}`. `update(st, dt, {outdoor})` clamps dt to 0..0.1. API: `create, update, feed, addBlood, sleep, clock, weakness, washK, dawnK, isDay, skipTo, serialize (v1), restore`. `Night.DEFAULTS`: nightSec 480, nights 5, bloodMax 100, bloodStart 60, feedGain 40 (feedGain unused by hold-to-drink; `addBlood` is used).

## 4. Feeding (hold to drink)

Right mouse button held, or R held (`debugFeed` for tests). Source: `game.js` startDrink/stepDrink/endDrink, `people.js`, `config.js`.

| Item | Value |
|---|---|
| Reach / arc | `feedReach` 1.5 cells, `feedArcDeg` 60 (config; range 1..3 and 20..120) |
| Toggle mode | `feedToggle` (Settings: "Click to start/stop drinking"): right click or R toggles instead of holding |
| Feedable | Nearest person in reach and arc whose mode is not `grapple` or `fed`; `dazed` is feedable |
| Pool | `poolMin + (poolMax - poolMin) x rng` blood per person; config `poolMin` 18, `poolMax` 32 (ranges 5..100 and 5..150). Seeded per map and night |
| Drink rate | `(6 + 14 x left/pool) x fx.drinkRate` blood/s; real per tick via `Night.addBlood` (returns actual gain, clamps at max) |
| Empty | `left <= 0.5` -> person `fed` (inert), `fedCount++` |
| While drinking | Drag: move at 25% (full victim) to 55% (drained) speed, look halved; victim held 0.6 cells ahead; clock and world keep running |
| Heartbeat | bpm `50 + 70 x left/pool`. Each beat: `heartbeat` pulse at the victim, range `(1.5 + 2.5 x drunk/pool) x (1 - 0.4 weak)`, z 0.55, strength 0.45; also the `react` radius. Outward chest ring + inward ring (R 1.4 -> 0.15 over 0.4 s) whose landing plays `feed` gulp. Reduced motion: fixed static ring R 0.8 |
| Villager heartbeat | Nearest 2 villagers within `hearDist` 2.5 cells (not `fed`, not the drink victim: Heartbeat above owns its beat). bpm from `Vessels.state` (single source for audio and the `vheart` chest pulse): calm 65, wary 90, startle/bumping 100, flee/cower 130; blood f = left/pool: f >= 0.4 bpm x (1 + 0.3 x (1 - f)/0.6) (~1.3x at 40%), below 0.4 falls linearly to 0 at empty; capped 175 (< 3 Hz). Each beat copies `bpm`, `stateK` (mode k x f^1.5), `periphK` (mode k x f), `headK` onto the villager, and the `vheart` echo snapshot carries them for the vessel overlay. Each beat emits a small `vheart` pulse (z 0.65) that shows the chest outline (band 0.45-0.85); with `vis.vessels` on the whole-body vessel overlay below rides on it |
| Vessel states (P6) | From `Vessels.state` via the echo fields (stateK, periphK, headK; hands/feet periph 1, elbows/knees 0.4): calm 1/1/1; wary 1.15/1/1.25 (neck and temple brighter); startle 1.3/0.8/1.1; flee/cower 1.5/0.5/1 (core brighter, hands and feet x 0.75 net: constricted); sleep 0.8. Blood f: stateK = f^1.5, eased in the renderer by `vessels.lowGamma` 0.5 (stateK^0.5 below 1, so 15% blood still shows a faint core: 0.24 not 0.06), extremities x periphK = f on top (dim first); f = 0, `fed` or `drained`: no pulse, nothing drawn. Tunables (dev panel, `vessels` group, `?tun=vessels.key:v`): alpha 0.75, size 0.9, lowGamma 0.5, hot 1, veins 0.6, halo 0.2, pwvScale 1.75, minQuality 1, edges 0.45, highlight 1, window 0.35, windowRange 2.5. `Render.stats().vessels` {nodes, heart, feet} per frame (`Game.debugVessels` with ?debug=1). Smoke: `?sys=vis.vessels:on`, calm villager pinned 1.3 cells away for 3 s from its first beat: >= 2 beats drawn, the brightest foot comes 0.15-0.9 s after each lub (~0.4 s measured), fps >= 10 headless, no page errors |
| Vessel overlay | Flag `vis.vessels` (default on since P7; `?sys=vis.vessels:off` or dev panel to turn it off). `drawVessels` in `render.js` on `vheart` echoes only, after the chest-only outline and not strip-masked. Nodes: one dot per `Vessels` node at its pose anchor (veins 1.6x larger behind, `VEIN_RGB`; arteries `ARTERY_RGB`), alpha `vessels.alpha` (0.75) x w x stateK' (stateK^`vessels.lowGamma` below 1) x lerp(1, periphK, periph) x (head ? headK : 1) x (1 + hot x `vessels.hot`), veins x `vessels.veins` (0.6), times echo strength and the P4 travelling pulse `Vessels.pulse`: the lub launches at the heart and reaches each node after `pathLen x vessels.pwvScale (1.75) / 6 m/s` (feet ~0.39 s, head ~0.12 s), envelope smoothstep attack 0.06 s then exp decay tau 0.25 s; dub ripple 30% (15% at 175 bpm) `DUB_DELAY` 0.3 s x sqrt(65/bpm) later (<= 45% of the beat); veins one later, slower, dimmer swell (lag 0.08 s + 1.25x delay, attack 0.1 s, tau 0.3 s), no dub; 0.2 s tail fade. With the flag on a vheart echo lives `Vessels.timing(bpm).life` (~1.0-1.05 s) in drawEchoes and People.updateEchoes (outline still ends at its afterglow); flag off unchanged. Bucketed into 6 alpha levels (few fills per figure). Elbow/knee nodes sit on the midpoint of drawPerson's limb curve (`Vessels.point`). Edges (P5, quality >= 2 only): one per parent -> child vessel, along the limb curve half (`Vessels.edgeCtrl`, quadratic through the elbow/knee) or straight in the torso; a dim base line `vessels.edges` (0.45) x child alpha x max(parent, child pulse), plus a travelling highlight (width 0.85x dot radius, veins 1.1x) at s = (age - d_parent)/(d_child - d_parent) (`Vessels.edgeFront`), trail 0.35 of the edge (veins 0.7, half alpha), alpha `vessels.highlight` (1) x lerp(parent, child alpha, s); the dub sends a second highlight at dubK. Strokes batched per alpha level (lines, highlights). Halo (2.4x radius, `vessels.halo` 0.2) at quality >= 2; quality 1 nodes only; quality 0 or below `vessels.minQuality` draws none. Vampire / stateK 0 / zero strength: none. Reduced motion: no travel, dub or highlight, one soft pulse over the whole network (nodes and dim edges at quality 2+; attack 0.1 s, tau 0.3 s, life 0.7 s), no halo or bloom, alpha <= 0.5 |
| Vessel echo timing | A heartbeat is emitted in stepAmbient after simulateWorld's echo pass, so for a villager that has not moved its own beat lands exactly on the next pass's tPrev; the strict `la > tPrev` edge then drops it (a standing villager's chest pulse is often missing). With `vis.vessels` on, `vheart` uses `la >= tPrev` (dedupe keeps one snapshot); flag off keeps the strict edge |
| Vessel visibility (P2b) | The overlay rides only on `vheart` echoes, which exist only where the beat's own pulse passed `Sonar.visibleFrom` (the same rule as the chest pulse). Open columns: clipped by the wall z-buffer like the outline, so never through a solid wall or closed door. Window columns (ray tile `w`, glass at most 2.5 cells in front of the body): drawn again at mute `vessels.window` (0.35) x (1 - d / `vessels.windowRange` (2.5 cells)), d = player -> body, and only when `world.lineBlocked` (glass-transparent line of sight) is clear; the chest outline itself stays hidden behind glass |
| Vampire body (P2c) | `Vessels.forBody('vampire')`: the same anatomy (nodes, anchors, edges) with `pulse` and `blood` false and a frozen still state (`Vessels.state('vampire', ...)` always bpm 0). The player body is only drawn as the first-person grab arms, so the model is anatomy data only; no heartbeat, no blood, no vheart pulse is ever emitted for the player, and `drawVessels` refuses any echo marked `vampire` / `body: 'vampire'` |
| Gasp | If the victim `sees()` the player at grab: `gasp` (range 4, z 0.8, strength 0.4, fade 1.2, gain 0.2). Grab from behind = silent |
| No target | `miss` sound only |
| Visual | Victim drawn `#ff8a78` (1.6 px, alpha 0.9) with `feedLock`; FOV 66 -> 54 over 0.35 s, back over 0.4 s; cached radial vignette alpha 0.5; dial dims to 0.5; vial scale 1.08 per beat. Reduced motion: no FOV/yaw change, fixed vignette 0.3, no vial pulse |
| Stop (first true) | Button or key released (toggle: second press), blood at max (with overflow closed), victim empty, victim out of reach (> reach + 0.3), a non-victim person sees you or enters `flee`, Escape / lock loss / blur, run end, map change, overflow gift ready |
| On release (not empty) | Victim -> `dazed` for `dazedTime` 3 s (config 0.5..10), keeps `left`, then flees silently (`quiet`) |
| Witnesses | Dark neighbours only startle (freeze, turn); lit (>= 0.3) neighbours in view see you and flee: that ends the drink. Rule: drink in the dark |
| Saves | Never written while `feeding` |

## 5. People

Source: `SoundData.react`, `people.js`, `game.js` (`reactCfgNow`).

### 5.1 Reaction constants

| Constant | Value | Meaning |
|---|---|---|
| startleDist | 3 | Sound reach at which a walker startles (x `fx.noise` x fear `startleMul`; ping and door use it, `heartbeat` passes its own radius) |
| seeDist / seeCone | 8 cells / 2.0944 rad (120 deg) | Vision: cone + line of sight; needs light |
| lightSeen | 0.3 | Torch light needed for a person to "see" you |
| bumpDist | 1 | Touching distance. Noticed when they face you within `bumpArc` 1.7453 rad (100 deg), or you are lit; from behind or the side only `bumpBackDist` 0.5 counts. 0 while Still or Mist |
| bumpFreeze | 0.4 s | Freeze after a bump, then flee |
| fleeMul | 1.6 | Flee speed multiplier (x fear `fleeMul`) |
| fleeCap | 2.55 cells/s | Flee speed cap: `min(speed x fleeMul, 2.55)` |
| calmAfter | 10 s | Flee time before returning to path (x fear `calmMul`) |
| waryTime | 20 s | After a flee, the person is wary: sight halved (x0.5) and resumes at a lit waypoint |
| lightPref | 1 | Refuge preference: lit cells first (1), hide spots only (0) |
| screamGap | 2 s | Min gap between scream events |
| startleTime | 1 s | Freeze duration for a sound startle |
| shriekMul | 2.5 | Shriek reach = startleDist x 2.5 x `fx.noise` |

### 5.2 Modes

| Mode | Behaviour |
|---|---|
| `path` | Walks looped path, pauses at waypoints, looks around |
| `startle` | Freezes, turns toward the sound (or the bump) |
| `flee` | Runs to a refuge (below), screams when first seen (scream sound range 7) |
| `cower` | At the refuge (or stuck): stays put, whimpers every ~1.5 s |
| `grapple` | Being drunk: inert, not feedable |
| `dazed` | Still, no sound reaction, feedable; then quiet flee |
| `fed` | Inert for the rest of the night |

### 5.3 Fleeing and refuges

- A fleeing person first looks for the nearest lit cell (light >= 0.3 at the cell or a neighbour) that is farther from the player than they are, within 15 steps. Torchlit paths are where they run.
- If there is none, they go to the nearest hide spot (`hides`, dark doorway or alcove cells) farther from the player, within 30 steps.
- If neither exists, they run along their loop away from the player.
- After a flee, they resume at the lit waypoint farthest from the player's last known spot (or the farthest waypoint if none is lit).

### 5.4 Walkers and echoes

`People.create(world, mapDef, {seed, poolMin, poolMax, shuffle})`. With `shuffle`, each walker starts at a random path index and 50% travel in reverse (seeded). Paths must not cross walls (legs may pass through doors). People are never drawn live: a passing wavefront reveals each figure strip by strip (feet→hat over SWEEP 0.22 s); everything (people, walls, props) uses a short afterglow AFTERGLOW_K 0.18 × pulse fade (≈0.54 s, clamped 0.2–1.0 s), so the screen is black once rings stop. Exceptions: feed lock, Warm Sense, people's own sound rings. Torch/brazier flames and their holders (wall sconce or free-standing post) follow the same ripple + afterglow rule; the warm screen-border vignette (lit >= 0.3) is the always-on light cue. Looks: 10 accessories × body/head/hair/beard/nose/coat; poses per mode (walk, idle, wary, sit, startle hop, flee lean, cower, dazed stars, grapple limp, fed slump). Seed per map: `(seed ^ (mapIndex x 2654435761) ^ (night x 40503)) >>> 0`. Events kept: `scream`, `startle`, `flee`, `whimper` (max 64).

### 5.5 Archetypes and Forge

Source: `js/data/archetypes.js`, `js/forge.js`, `js/schedule.js` (`loadRoles`), `people.js` (`create`, `spawn`, `despawn`, `alter`, `forgeState`), `game.js` (`stepForge`, `forgeWashout`, `replayForge`), `save.js` (`sanitizeForge`).

- **Look.** A look is a plain object. The 12 legacy keys (`height, build, stride, acc, body, head, hat, hair, beard, nose, coat, prop`) are the v0.13 shape. v0.14 adds `v, archetype, outfit, roleHat, extra, stoop, shoulder, hem, skin`. The renderer reads the v0.14 keys from v0.15 on (`outfit`, `roleHat`, `extra` in `figure.js`; `stoop`, `hem`, `shoulder`, `skin` in `render.js`).
- **Ranges and enums** (`ArchetypeData.LOOK_RANGES` / `LOOK_ENUMS`): height 0.5..1.2, build and stride 0.7..1.4, nose 0.5..1.6, stoop 0..0.4, shoulder 0.8..1.25, hem 0..1, skin 0..1. `validate` clamps numbers, falls back to defaults on bad enums and non-boolean values, and rejects unknown or `__proto__`/`constructor`/`prototype` keys.
- **Derived rules.** `hat` and `prop` follow `acc` (hat-type and prop-type accessories). `hair` is `none` under tophat, nightcap or hood.
- **Generation.** `Forge.generate(spec, ctx)` with `spec = {archetype, seed?, home?, overrides?}` and `ctx = {stateSeed, index, accOffset}`. The entry seed is `spec.seed` when it is an integer 0..65535, otherwise `index`. The look seed is the v0.13 `makeLook` formula with the entry seed in place of the person id. Shipped walkers use `seed = index`, so their looks match v0.13.2. `acc` is `ACCESSORIES[(accOffset + 3 * entrySeed) mod 10]` for recipes marked `cycle`. The extras (shoulder, skin, stoop, hem) come from a second stream seeded by `lookSeed ^ 0x9E3779B9`. `overrides` are validated as a partial look and applied last. An unknown archetype returns `E_FORGE_UNKNOWN` with a patron person.
- **Alter.** `Forge.alter(look, patch)` returns a new look object and the list of changed keys. It never mutates the old one, so echoes keep their snapshot.

**Archetype rows** (`ArchetypeData.list`, 14 rows; the first 11 are the shipped roles):

| id | role | voice | talk | schedule | watch | feedable | gait | speed | outfit / roleHat / extra / stoop / hem |
|---|---|---|---|---|---|---|---|---|---|
| patron | '' | man | villager | none | no | yes | walk | 1.0 | plain / none / none / 0 / 0 |
| innkeeper | innkeeper | woman | innkeeper | 5 stops | no | yes | walk | 1.0 | apron / none / none / 0 / 0.6 |
| drunk | drunk | man | drunk | 3 stops | no | yes | walk | 1.0 | plain / none / none / 0 / 0 |
| regular | regular | man | innkeeper | 4 stops | no | yes | walk | 1.0 | plain / none / none / 0 / 0 |
| priest | priest | elder | priest | 4 stops | no | yes | walk | 1.0 | robe / biretta / none / 0 / 1 |
| elder | elder | elder | elder | 4 stops | no | yes | walk | 1.0 | plain / none / none / 0.25 / 0.5 |
| farmer | farmer | man | farmer | 7 stops | no | yes | walk | 1.0 | smock / none / none / 0 / 0.3 |
| mother | mother | woman | mother | 5 stops | no | yes | walk | 1.0 | apron / none / bundle / 0 / 0.8 |
| insomniac | insomniac | man | villager | 5 stops | no | yes | walk | 1.0 | plain / none / none / 0 / 0 |
| gravedigger | gravedigger | man | gravedigger | 5 stops | no | yes | walk | 1.0 | smock / none / shovel / 0.05 / 0.2 |
| guard | guard | man | guard | watch | yes | yes | mail | 1.3 | mail / kettle / none / 0 / 0.3 |
| child | child | child | child | 3 stops | no | **no** | walk | 1.0 | plain / none / none / 0 / 0 (height 0.58+0.08r, build 0.85+0.15r, no beard) |
| merchant | merchant | man | villager | 3 stops | no | yes | walk | 1.0 | cloak / none / ledger / 0 / 0.7 |
| hunter | hunter | man | guard | watch | yes | yes | walk | 1.3 | cloak / none / bow / 0 / 0.4 |

- Every row has skin `[0.35, 0.3]`. Shoulder is `[0.95, 0.1]`, except priest and guard at `[1.05, 0.1]`.
- `schedule` tuples are the same format as before (`[[places], until, act]`). `schedule.js` builds its `ROLES` table from this data at load: `'watch'` becomes the watch-post walk, and an array becomes a routine. Child, merchant and hunter have routines too, but no shipped map spawns the child or merchant.
- Children are not feedable and are not reinforcements. Children are not placed on any shipped map.
- `legacy` marks the 11 shipped roles. It is data only.

**Walkers.** `People.create` picks each walker's archetype from `def.archetype`, else `Forge.byRole(def.role)` for old map data, else `patron`. `maps.js` gives all 17 walkers an `archetype` and a `seed` (the entry index). `person.watch` replaces the old `role === 'guard'` checks, and `person.gait === 'mail'` replaces the old guard gait check. `isFeedable` returns false when `person.feedable === false`.

**Mid-night spawn, despawn, alter** (`People.spawn/despawn/alter`, used by the reinforcement rule and the dev panel):

- `spawn(state, world, spec, at)`: `spec.seed` is a uint32 saved for replay. The look seed is `((s >>> 16) ^ s) & 0xFFFF`. The pool and schedule draw from `mulberry32(s)`, never from `state.rng`. Refused codes: `E_PEOPLE_SOLID` (solid cell), `E_FORGE_LIMIT` (24 walkers at most), `E_PEOPLE_ARGS`, `E_FORGE_UNKNOWN`.
- `despawn(state, id)`: refused with `E_FORGE_BUSY` while the person is grappled, dazed or fed. Echoes stay.
- `alter(state, id, patch)`: replaces `person.look` with `Forge.alter` output.
- Each spawn and alter is logged in `state.forgeLog` (`spawned` and `altered`, at most 16 altered). `forgeState` returns the compact record for the run snapshot, with altered ids renumbered to the ids a replay assigns.

**Reinforcements** (`ArchetypeData.REINFORCE`, `Forge.reinforcement`):

| Fear | Archetype | Card |
|---|---|---|
| 6 | guard | The watch is doubled |
| 10 | hunter | A hunter walks the lanes |

- `stepForge` runs at most once per second. It runs only while `playing` or `feeding`, and only on maps with `reinforce` (the town, at the `[2, 19]` cell).
- Each entry fires once per run, in order (`st.forgeFired`), when fear reaches its threshold and the player is at least 10 cells away or out of line of sight. The seed is `(runSeed * 31 + night * 977 + fired * 7919) >>> 0`. A success shows the card and plays the bell at the entry cell. A refused spawn still counts as fired.
- At fear 8, once per run, every watch person gets `acc: 'lantern'` (look only).
- `forgeWashout` (on washout) despawns reinforcements that are out of sight (line blocked, or over 10 cells away) and not busy. The rest stay.

**Custom archetypes and the library.** `Forge.register` adds a custom archetype (id matches `^[a-z][a-z0-9_]{1,23}$`; built-in ids are refused; at most 16 custom). The library is stored under `vcs.forge` as `{v:1, list}` (at most 16384 bytes). It loads at boot. The dev panel's "Save as custom archetype" button is the only writer. `Forge.importLibrary` and `exportLibrary` back the dev panel's import and copy buttons.

**Dev panel.** F9 opens the NPC Forge editor: pick an archetype and seed, edit look fields (`Forge.LOOK_FIELDS`), then spawn in front, alter the nearest person or despawn the nearest person. The buttons need a running run.

### 5.6 Figures

Source: `js/figure.js` (`VCS.Figure`, a script before `render.js`), `js/render.js` (`posePerson`, `drawPerson`, `drawLineFigure`, `rimLight`, `paintFlush`, `figureFrameEnd`), `js/config.js` (`effects`), `js/game.js` (`figure.budgetMs` tunable).

- **Slots.** `PX`, `PY`, `PZ` are `Float32Array(28)`. 0 head, 1 neck, 2/3 shoulders, 4/5 hips, 6/7 hands, 8/9 feet, 10/11 elbows, 12/13 knees, 14 torso centre, 15/16 scarf tip and control, 17/18 hat tip and control, 19/20 prop anchor and tip, 21/22 coat hem, 23 head top. 24 extra grip (the side-0 hand) and 25 extra tip are written only in vol mode. 26 and 27 are unused. `PZ[k] = ff*cr - ss*sr`: positive is away from the camera. Parts sort by the mean PZ of their ends.
- **Effects** (`config.effects`, integer 0..2, default 2, menu label "Effects": Off (classic lines), Low, High). `drawFirstPerson` sets `r.fx = round(clamp(effects))`, lowered to 1 while the budget cap is on.

  | fx | Figure | Black occlusion fill (near) | Wrap lines | Contact shadow | Flush | Grab arms |
  |---|---|---|---|---|---|---|
  | 0 | line figure only (`drawLineFigure`) | no | no | stroke | no | line |
  | 1 | volumetric | no | 1 per torso, leg and arm (upper half) | stroke | no | volumetric |
  | 2 | volumetric | yes, 0.55 x sa per part | torso 1, legs and arms 2 (t 0.25, 0.75) | filled 0.4 x sa + stroke | yes | volumetric |

- **Volumetric gate.** `volWant = fx >= 1 && quality >= 1 && (locked || figMs <= figBudget)`. `vol = volWant && depth < 10`. The held victim skips the budget cut. Quality 0 and fx 0 never take this path.
- **Near and far.** "Near" is depth < 6. Fills, wrap lines and the rim apply only when near. Depth 6..10 draws contours only.
- **Vol-only pose tweaks** (in `posePerson` behind `if (vol)`, never at fx 0):
  - Elder stoop from `look.stoop` (0..0.4): lean +0.1, head forward +0.06, shoulder -0.04, head -0.05, all times lh. Not in grapple, fed or cower.
  - Chat gesture when `e.chat && !moving`: side-0 hand lifts `0.06*lh*(0.5+0.5 sin(2 pi 0.6 t + pid))` and goes forward +0.05*lh. Reduced motion holds a static 0.03*lh.
  - Head scratch (idle, `pid % 3 == 1`, v0.19): the side-0 hand rests on the side of the head, just outside the head (or hood) outline, with the elbow out at shoulder height + 0.08*lh, instead of the line pose's hand on the crown that pushed the solid forearm through the head.
  - Shovel (`extra`): over the shoulder while moving, planted beside foot 8 when idle. Bundle (`extra`) clutched at the chest while fleeing.
- **Parts** (`Figure.parts`, v0.17 anatomy, 11 plus the shovel shaft): torso, neck, per side leg, foot, arm and hand, then the head. Every part is a closed outline (`px`/`py`, at most `MAX_POINTS` 40) drawn as a smooth curve through its edge midpoints.
  - Torso: one hull from the neck base over the trapezius slope, shoulders (deltoid), ribcage, waist and pelvis to the crotch. Ten cross sections (lateral half-width W, depth D, forward offset F per body kind: bean, pear, stick, round, box; `look.shoulder`, `stoop` hunch, child belly) seen at the trunk yaw from the slot spreads: half extent `hs sqrt((W cr)^2 + (D sr)^2)`. One shoulder is up to 3.5% broader per person (wonk).
  - Legs and arms: one outline each, swept along the SAME quadratic the line figure and the vessels use (root, elbow/knee slot as control, end). Radius and front/back bulge profiles over t (deltoid, biceps, elbow, forearm, wrist; thigh, kneecap, calf, ankle), scaled by body kind, build and child factor. The knee/elbow is the curve midpoint (t 0.5, where the vessel node sits). The inside of a bend is clamped to 0.85 x the curvature radius so nothing folds.
  - Hands: a mitten palm with a thumb lobe (toward the front in profile, the middle head-on) and finger hints. Shoes: heel, instep and a slightly upturned toe, blended from a head-on dome by |sin yaw|. Head: cranium with jaw taper, chin and brow that follow the face direction, square/egg/long variants.
  - Child (`look.height` <= 0.66, fading out by 0.82): head x1.25, chubbier limbs, rounder face, lower and bigger eyes; in vol mode `posePerson` also narrows shoulder and hip spreads by up to 32% (`kidW`, exactly 1 for line figures).
  - Sorting z: legs -0.02 (over the pelvis, v0.19; the far leg in profile still sorts behind), neck +0.03, head -0.08.
  - Queries: `Figure.contains(part, x, y)` (nonzero winding), `Figure.hit` / `hitAll` (parts at a point, own pool), `Figure.spanAt` (silhouette span at a row; the band-front rings use it).
- **Draw order.** Contact shadow, then parts sorted back to front (stable insertion sort, descending z). Per part: occlusion fill (fx 2, near, not the shovel shaft), contour stroke at `lw` (fx >= 1, near: an arm or leg leaves out the root outline points that lie inside the torso, and the torso leaves out its hip, seat and crotch points that lie inside a leg drawn over it, so limbs grow out of the body without doll-joint circles or a ghost of briefs; the fill still covers the whole outline), wrap arcs (fx >= 1, near, limbs and torso; the lower limb ring is dropped where a cuff ring follows), rim stroke (near, k > 0.02). A robe clips legs to below the hem. Then `drawExtras` (mail, robe, cloak, apron, smock; at lod >= 1 their hems are four soft scallops, and at lod 2 robes get three folds from the girdle, cloaks two long folds from the shoulders, aprons and smocks two folds from the waist tie; role hats kettle and biretta, role items shovel, bundle, ledger, bow). Then the line-style details and the dazed stars. Face: ears (not under a hood, bonnet or bob), nose with nostrils head-on, and at lod 2 eyes with pupils and brows, and a mouth, all placed on the head as 3D points at the face yaw (`pose.cosYaw`, `noseX`). Per-archetype face character (`FACE` table, v0.19): eye size and spacing, brow lift, tilt, length and a heavy double brow, nose kind (wedge, button, hook, bulb, long), mouth width, smile and a lopsided grin, sleepy lids, under-eye bags, crow's feet and forehead lines, cheek lines, lashes, one raised brow; plus a per-person asymmetry from `pid` (one eye and brow higher, the mouth off centre). Beards draw a jaw line round the chin and a moustache. Mood from the mode: wide eyes and an open mouth (startle, flee, held), squeezed eyes (cower), closed (fed), knitted brows (wary), X eyes and a wavy mouth (dazed). Also beard, hair, hats, clavicles (bare neck, chest toward us), waistband, coat hem (corners sorted by x), seat edge, scarf, props, fingers at lod 2 (a fist with knuckles and a wrapped thumb on the hand that carries a prop or role item, four splayed fingers in startle, cower, held and flee, else three relaxed curled fingers), kneecaps and elbow creases (lod 2), hands over head. Extras run only in vol mode and read slots 24/25 when set, else a point beside hand 6.
- **Rim light.** `rimLight` picks the nearest `r.visWorld.lights` entry within 3 x radius of the echo. `k = 1 - d/(3 radius)`. Side is the sign of the light's offset along the camera right vector. Steady (lights do not flicker). Stroke `#ffcf8a` at `0.5 k sa`, width `0.8 lw`, on the lit side.
- **Vessel flush** (fx 2 only). `drawVessels` writes `FLUSH[0..3]` (temporal, carotid, radial L, radial R) from the node pulse times stateK and periphK. `paintFlush` draws `#ff8a78` fitted to the anatomy: the face (toward the facing side), along the neck part and over each wrist along the forearm. `a = min(cap, flush x skin x 0.25 x sa)`, skipped below 0.002. Cap 0.18, or 0.08 with reduced motion. It runs only from the two `drawVesselsSeen` call sites: `vheart` echoes with vessels on, and the held victim. The pulse follows the heart bpm, capped at 175 (`VESSELS.BPM_MAX`, 2.92 Hz).
- **Circulation fit.** Vessel nodes and edges run inside the body for every archetype, body type, height, outfit, stoop, yaw and pose mode, including the held victim (`tests/figure-anatomy.test.js` checks each node against its owning part and samples every edge). On volumetric bodies `vesselRad` scales the dots by 0.8 (veins 1.35x instead of 1.6x) so they fit the wrists and ankles; line figures keep the v0.16 sizes.
- **Figure sheet.** `tools/figure-sheet.html` draws the real figures through `Render.drawSolo` (archetypes x views, pose modes, body x head matrix, circulation, v0.16 before/after from `tools/figure-v016.js`). `node tools/build-figure-sheet.mjs [out]` regenerates that legacy copy from git and inlines everything into one offline HTML file.
- **Budget guard.** `r.figMs`, `r.figVol` and `r.figLine` reset each frame in `drawFirstPerson`. Each vol `drawPerson` adds its `nowMs()` time to `figMs`. Once `figMs > figBudget` (default 2.5 ms, `figure.budgetMs` tunable 0.5..8 step 0.25), later non-held figures draw as lines that frame. `figureFrameEnd` runs after the echo pass: a frame is over when it had a vol figure and `figMs > figBudget`. 20 of the last 30 over frames at fxCfg 2 sets `r.fxCap = 1` for 10 s (High draws as Low), clears the history and logs once. The cap is lifted when the time runs out. `Render.stats().figure` is `{vol, line, ms, cap}`.
- **3 Hz list.** Brightness: only the flush varies, and at most 2.92 Hz (bpm cap 175). Motion (position, not brightness):
  - chat hand 0.6 Hz (vol only; static when reduced)
  - dazed stars orbit 0.40 Hz (zero when reduced)
  - body shake `sin(9.4 t)` 1.5 Hz, 0.006 lh (one mode)
  - every other sway in `posePerson` is at or below 1.5 Hz
  - grab-arm jitter `sin(37 t)` and `cos(29 t)` at 5.9 Hz and 4.6 Hz, amplitude `jolt x hs x 0.05` px, zero at rest. This is shake, not light, and it exists in the line grab arms too.

## 6. Light, sound and hearing

Source: `js/data/sounds.js`, `js/audio.js`, `js/game.js` (`spatial`, `occludedTo`, `stepAmbient`, `updateAmbience`), `js/world.js`.

### 6.1 Light

- Torches are light sources (`light` radius on some torches in `maps.js`). Light is shown as `lightAt(x,y)` (0..1).
- About 48% of the town is torch-lit.
- Glass windows (`w`) let light through; they still block movement and sonar.
- No drawn light circles or rings. Light shows only as: the warm screen-edge glow (alpha = `lightAt(player)^1.2 * 0.5`, steady, `Render.edgeGlowAlpha`); torch/brazier flame and holder under a sonar wavefront (any height reached, fades with the afterglow); floor/wall spill only where the ripple has passed.
- Two zones per light: the core (`lightAt`, the torch radius) and a faint outer halo (`outerAt`, radius = 1.8 x core, same falloff shape and occlusion). Edge glow level = `max(core, 0.35 * outer)` through `Render.edgeZoneAlpha` (outer never above 35%).
- Edge glow is directional (`edgeSides` in `js/render.js`; bearing low-passed 0.15 per frame, direct under reduced motion; 8-stop smoothstep gradients): lights within 3 x radius are weighted by their outer value at the player and averaged as bearing relative to facing. The side facing the light gets x(1 + 0.6|side|), the far side x(1 - 0.6|side|) (0.4 at full side); the top edge gets x(0.5 + 0.5 max(0, cos)). No light nearby: no glow. No flicker, no drawn circle.
- Nothing about light flickers: flames keep a fixed size (tip sways < 1 Hz, brightness constant); window candle glow is steady.
- Fire sound: no pulse or interval. Within 1.5 cells of a torch, `Audio.fireBed` plays a quiet lowpass (2.5 kHz) noise bed (max 0.035 x volume), panned to the torch, fading to 0 at 1.5 cells; 2 nearest torches; only while playing or feeding.

### 6.2 Sound levels

Each level: `range` (cells), `strength` (visual), `z` (source height), `fade` (s), `bounces`, `gain` (0..1), `hearDist` (audible cells). Main kinds:

| Kind | range | fade | gain | hearDist |
|---|---|---|---|---|
| step | 1.1 | 0.8 | 0.08 | - (interval 0.48 s) |
| personStep | 0.7 | 0.7 | 0.12 | 9 |
| door | 5 | 2.5 | 0.25 | 18 |
| scream | 7 | 2.2 | 0.3 | 25 |
| startle | 1.5 | 1.0 | 0.1 | 12 |
| wind / room | - | 1 | 0.025 / 0.02 | ambience beds (6.4) |

Echo timing: one speed, SONAR_SPEED 12 cells/s; echo delay = round trip at that speed.

Rooms (`SoundData.rooms`): indoor range x1, 2 bounces, fade x1; outdoor range x1.3, 1 bounce, fade x0.8.

### 6.3 Spatial rules (`Audio.play` options)

| Option | Effect |
|---|---|
| `pan` | Stereo position `sin(angle to source - facing)`, -1..1 |
| `dist` | Gain x `1 / (1 + dist/4)`; beyond `hearDist` the sound is dropped (returns false) |
| `occluded` | Lowpass 600 Hz. Set when a solid cell lies on the line to the source (sampled up to 25 cells) |
| `behind` | Source is behind you (cos of relative angle < 0): gain x0.7, lowpass 1200 Hz |
| `material` | `stone`, `grass` or `wood`; picks the footstep timbre |
| `foot` | Left/right alternation. Step kinds flip `a.foot` each play |

Breathing: `Audio.breath` gain x `(1 - dist/6)`; behind x0.7; occluded x0.5 and a dull buffer.

Footsteps by floor: `stepMaterial(x,y)` reads `world.materialAt` (`grass`, `wood` for wood floor, else `stone`). Player steps are `step`, people's are `personStep`.

### 6.4 Ambience

| Item | Rule |
|---|---|
| Bed | Outdoors: wind. Indoors: room tone. Level `ambienceGain` x `volume` (fade 1.5 s). Silent on menu, pause and run end |
| Dog | Outdoors only, every 20-40 s, at pan -1..1 and 6-12 cells away; 2-3 yips |
| Crypt bell | Every 20-40 s, from the direction of the crypt door, on maps linked to the crypt (not inside the crypt). Played at the bell level x2 (gain 0.6) with spatial rules |
| Breathing | Each person within 6 cells breathes every 2-3 s (first breath 0.3-2.3 s in). Fed people are silent |
| Timers | Seeded per night from run seed and night (`initAmbient`) |

### 6.5 Post-FX and grade

Source: `js/postfx.js` (`VCS.PostFx`), `js/render.js` (`drawFirstPerson`, grain and vignette, taper, glint, stone and wood texture), `js/game.js` (render opts `ro.grade`).

Everything is gated on the effects level `fx` (0 Off, 1 Low, 2 High; `r.fx` is capped by the adaptive quality step). At fx 0 the output is the v0.15 frame.

| fx | Bloom | Grade | Grain base | Vignette |
|---|---|---|---|---|
| 0 | off, except quality 4 at alpha 0.85 (unchanged) | none | 0.04 (`GRAIN_BASE`) | unchanged (1) |
| 1 | quality 4 only (0.85) | dusk and dawn | 0.035 | 0.7 |
| 2 | quality >= 3 with `filter` support: half-res blur(1.6px) copy, `lighter`, alpha 0.55 (quality 4 keeps 0.85) | dusk and dawn | 0.05 | 1 |

Caps and inputs:
- Bloom alpha is at most 0.85 (quality 4) and 0.55 at fx 2. Without `filter` the fx 2 bloom is skipped, not faked.
- Grade `g = {dusk, dawn}` in 0..1. `ro.grade.dusk = 1 - night.min / 30` while `night.min < 30` (else 0). `ro.grade.dawn = Night.dawnK(night)`.
  - Dusk: `multiply` `rgb(150,140,200)` at alpha <= 0.10.
  - Dawn: `multiply` `rgb(255,205,185)` at alpha <= 0.12, then `saturation` grey `rgb(128,128,128)` at alpha <= 0.25 (skipped if the canvas does not take the mode).
  - Each composite mode is set and read back; a mode the canvas refuses skips its pass. The pass restores `source-over` and alpha 1.
- Grain scale is `min(1.25, level / 0.04)` applied to the existing grain. The vignette opacity is the value in the table; at fx 2 it is 1, the same as before.
- Grade is drawn inside the render canvas after atmosphere, before the HUD canvas pass, so it never darkens the HUD. Public functions never throw; errors are logged once.

Other fx >= 1 and fx 2 details (render.js):
- Taper (fx 2, quality >= 3): each vertical segment is split at 30% from its outer end. The outer part goes to the thin bucket (`pathForC(ci, a, 2)`), the inner part keeps its class. No extra `stroke()` calls.
- Floor front (fx >= 1): two trailing arcs at `R-0.06` and `R-0.12` cells, alpha x0.45 and x0.2.
- Stone `#` (fx >= 1, material detail on, quality >= 2): two short slanted hatch strokes per block, in the lower third. Wood `W`: grain dashes only on every other block.
- Window glint (fx 2, quality >= 2): one seeded pair of crossed strokes per pane, alpha <= 0.3 x glow. It fades once over the ripple afterglow (0.2 to 1.0 s, `glowDur`). It does not twinkle.

Rate and motion notes:
- Post-FX adds no periodic term. Bloom, grade, grain and vignette are static per frame apart from the existing grain.
- The only new time-varying element is the window glint: one fade per ripple, lasting 0.2 to 1.0 s. A single pulse cannot make it blink or repeat inside its own fade. Its repeat rate follows the player's pulse rate; there is no timer that retriggers it.
- Reduced motion does not change bloom or grade (both static). The glint is not gated on reduced motion; it is one fade, not a pulse. The v0.16 HUD marks (section 11) are static.

## 7. Saves

Source: `js/save.js`, `js/game.js`.

| Item | Value |
|---|---|
| Keys | `vcs.settings` (config), `vcs.run`, `vcs.meta`; each also `.bak` and `.tmp`. `vcs.tab` (two-tab lock), `vcs.seen` (hints seen). `vcs.forge` (custom archetype library, raw `{v:1, list}` JSON, not in the envelope, <= 16384 bytes; Section 5.5) |
| Limits | `MAX_BYTES` 65536 per save, `MAX_IMPORT` 131072, nesting depth <= 12 |
| Schemas | `RUN_SCHEMA = 4`, `Meta.SCHEMA = 1`, `Hunger.SCHEMA = 1`, night serialize `v:1`, export `v:1` |
| Envelope | Exactly keys `app:'vcs', kind, v, game, sum, data`. `sum` = FNV-1a 32 (8 hex chars) of `JSON.stringify(data)` |
| Safe write | stringify -> too big? `E_SAVE_TOO_BIG` -> write `.tmp` -> read back must equal (`E_SAVE_VERIFY`) -> if current main valid copy to `.bak` -> write main -> remove `.tmp`. setItem throws -> `E_SAVE_QUOTA` |
| Safe read | Main bad (size, parse, bad key, schema, checksum): try `.bak`; if ok copy into main, `source:'bak'`, `code` = main's error. Both bad: `source:'none'` |
| Run validation | `validateRun` (save.js) runs on each autosave snapshot: failure logs `Run snapshot invalid (code)` and skips that autosave |
| Run snapshot | `{v:4, map, player:{x,y,angle}, doors, people, night, run, hunger?, forge?}`; `run = {seed, boons[], closedSafe{}, pendingBoons, pendingGifts}`; `run.hunger` null or Hunger.serialize |
| Forge block | Optional top-level `forge`, written only when a map has mid-night spawns or alters: `{v:1, maps:{<mapName>: {spawned:[{a, s, x, y, ang}], altered:[{id, look}]}}}`. Schema stays 4. Replayed after the map's people are built (`replayForge`): unknown archetypes are dropped with a warning |
| sanitizeRun | Allowed top keys `v, map, player, doors, people, night, run, rocks, forge`; `v===4`; map string <= 32; doors <= 512 cells per map; boons <= 20 strings <= 24; pendingBoons/pendingGifts null or <= 3 strings; hunger exact keys `v,fear,over,giftsTonight,gifts,essenceBonus,nextBlood`, gifts <= 20. `forge` (`sanitizeForge`): exactly keys `v, maps`, `v===1`, <= 4 maps, each map has only `spawned` (<= 4, `a` matches the archetype id pattern, `s` uint32, x/y clamped 0..64, ang clamped -7..7) and `altered` (<= 16, `id` 0..255, look validated as a partial look). A bad forge block is dropped, the rest of the run is kept |
| Migration | v1/v2 -> v3 (adds `run:{seed:1, boons:[], closedSafe:{}, pendingBoons:null}`) -> v4 (adds `run.hunger = null`); newer than 4 -> `E_SAVE_VERSION`. Meta v0 `{essence, bought[]}` -> v1 with tier 1 each |
| Autosave | Every `autosaveSec` (20; range 5..300) of play clock in `playing`; also after map change, on pause, `visibilitychange` hidden, `pagehide` (any active run state) |
| Two-tab guard | `tabLock` writes a heartbeat `{id, t}` to `vcs.tab`; `tabCheck` treats another tab as alive if its heartbeat is < 12 s old. Checked at boot and every 5 s. While another tab is alive: saving is paused here and the notice "Game is open in another tab — saving is paused here." appears once. Resumes when the other tab is gone |
| "Not saved" dot | Small coral dot with the text "not saved" at the bottom right of the play screen while the last write failed (`saveFailed`) or saving is paused by another tab |
| Continue | read -> migrate -> sanitize -> validate map and boon ids -> apply. Fail: notice "Run save could not be loaded (code).", remove run, disable Continue. Main copy bad: remove run and keep `.bak` (`keepBak`). Bad backup: remove both. Resumes in `boon`/`gift` state if a pick was pending |
| Boot meta | `E_SAVE_NONE` silent fresh; other failure: fresh + notice "Meta save was damaged (code). Started fresh."; `source:'bak'`: notice "restored backup" |
| Export | `exportText` -> pretty JSON `{app, kind:'export', v:1, game, meta, run}`; downloaded as `vcs-save-YYYYMMDD-HHMM.json` |
| Import | File input `.json`; size checked before read; `parseImport` (keys exactly app,kind,v,game,meta,run; meta required; bad run envelope fails the whole import); then migrate + sanitize; bad run dropped in game, meta kept |
| Codes | `E_SAVE_NONE`, `E_SAVE_PARSE`, `E_SAVE_BAD_KEY`, `E_SAVE_SCHEMA`, `E_SAVE_CHECKSUM`, `E_SAVE_VERSION`, `E_SAVE_TOO_BIG`, `E_SAVE_VERIFY`, `E_SAVE_QUOTA`; meta `E_META_UNKNOWN`, `E_META_MAX`, `E_META_POOR` (ok = `OK`) |
| Abandon run | Menu "New run" with a run present asks "Abandon run? Click again" (3 s), then records a loss |
| Run end | `recordRun`, write meta, remove run; tombstone shows nights, people fed, Essence (+ gifts and far-spot bonus) |

## 8. Meta (Essence, upgrades, boons)

Meta state: `{v:1, essence, upgrades:{id:0..3}, stats:{runs, wins, nightsSurvived, peopleFed, bestNights, essenceEarned}}`. Ints >= 0; essence <= 1e6; stats <= 1e9.

Essence per run: `nights x 4 + fed + (won ? 15 : 0) + bonus`. Bonus = 2 per gift taken plus the far-spot +5 per sleep, kept in `hunger.essenceBonus` (int 0..1000).

Effect keys (combine upgrades, then boons, then gifts; then clamp):

| key | op | default | min | max |
|---|---|---|---|---|
| sonarRange | mul | 1 | 0.5 | 2.5 |
| sonarFade | mul | 1 | 0.5 | 2.5 |
| sonarCooldown | mul | 1 | 0.5 | 1.5 |
| startBlood | add | 0 | 0 | 40 |
| drain | mul | 1 | 0.4 | 1.5 |
| drinkRate | mul | 1 | 0.5 | 2.5 |
| noise | mul | 1 | 0.3 | 1.5 |
| nightLen | mul | 1 | 0.5 | 2 |
| warmRadius | add | 0 | 0 | 10 |

Upgrades (permanent, 3 tiers, cost 5 / 12 / 25 Essence each):

| id | Name | Icon | Effect | Op | Tiers |
|---|---|---|---|---|---|
| far_echo | Far Echo | ear | sonarRange | mul | 1.15, 1.3, 1.45 |
| lingering_echo | Lingering Echo | hourglass | sonarFade | mul | 1.2, 1.4, 1.6 |
| quick_call | Quick Call | bat | sonarCooldown | mul | 0.9, 0.8, 0.7 |
| full_veins | Full Veins | vial | startBlood | add | 10, 20, 30 |
| slow_thirst | Slow Thirst | drop | drain | mul | 0.9, 0.8, 0.7 |
| deep_draw | Deep Draw | fang | drinkRate | mul | 1.15, 1.3, 1.45 |
| soft_step | Soft Step | paw | noise | mul | 0.85, 0.7, 0.55 |
| long_night | Long Night | moon | nightLen | mul | 1.1, 1.2, 1.3 |
| warm_sense | Warm Sense | heart | warmRadius | add | 3, 5, 7 |

Boons (one pick of 3 after each sleep, this run only; `rollBoons(seed + night x 7919, taken)`, deterministic, excludes taken unless `repeat`):

| id | Name | Icon | Effect | Op | Value | Repeat |
|---|---|---|---|---|---|---|
| bats_ear | Bat's Ear | ear | sonarRange | mul | 1.1 | no |
| echo_memory | Echo Memory | hourglass | sonarFade | mul | 1.15 | no |
| quick_ping | Quick Ping | bat | sonarCooldown | mul | 0.9 | no |
| cold_blood | Cold Blood | drop | drain | mul | 0.85 | no |
| fast_fangs | Fast Fangs | fang | drinkRate | mul | 1.2 | no |
| hush | Hush | paw | noise | mul | 0.8 | no |
| moonlit | Moonlit | moon | nightLen | mul | 1.1 | no |
| warm_hint | Warm Hint | heart | warmRadius | add | 2 | no |
| full_belly | Full Belly | vial | bloodNow (instant, not an effect) | add | 25 | yes |

Meta API: `create, sanitize, migrate, tierOf, costOf, buy, essenceFor, recordRun, effects(meta, boons, extra), rollBoons, boonById, upgradeById`. Warm sense draws a soft halo `rgba(255,138,120, 0.10 x (1 - d/radius))` for people within `warmRadius`, seen through walls.

Menu: Continue, New run, Shop (9 cards, tier pips, Buy/Max), Stats, Export save, Import save; Esc in a sub-panel returns to the main menu.

## 9. Hunger (gifts, powers, fear)

Source: `js/data/hunger.js`, `js/hunger.js`.

Overflow gifts:

| Item | Value |
|---|---|
| Overflow | Drinking at full blood routes gain into `over` (victim pool still drains) |
| Gift costs | By gifts taken tonight: 40, then 60. Max 2 per night; once 2 taken overflow is closed and the drink ends at the cap |
| Ready | `over >= cost`: drink ends (victim released dazed), state `gift`, 3 distinct gifts via `rollGifts(seed + night x 131 + gifts.length)`, keys 1/2/3 |
| Bonus | +2 Essence per gift, added at run end |
| Reset | `over` and `giftsTonight` -> 0 at sleep |
| Sound | `overflow` tick every 10 taken, `gift` on pick |

Gifts (repeatable, separate pool):

| id | Name | Icon | Kind | Value |
|---|---|---|---|---|
| g_far | Keener Ear | ear | sonarRange mul | 1.05 |
| g_fade | Longer Echo | hourglass | sonarFade mul | 1.05 |
| g_quick | Quicker Call | bat | sonarCooldown mul | 0.95 |
| g_thirst | Slower Thirst | drop | drain mul | 0.95 |
| g_draw | Deeper Draw | fang | drinkRate mul | 1.08 |
| g_quiet | Quieter | paw | noise mul | 0.95 |
| g_calm | Calm Town | eye | instant fear | -2 |
| g_reserve | Reserve | vial | instant nextBlood | +10 (applied once at start of next night) |

Powers (costs and cooldowns are fixed; cannot spend below cost, blood may drop under 25):

| id | Key | Unlock night | Cost | Cooldown s | Fear | Effect |
|---|---|---|---|---|---|---|
| shriek | Q | 1 | 15 | 6 | +2 | Pulse with range x2 (normal bounces); people react kind `shriek` at `startleDist x 2.5 x fx.noise`; not suppressed by Still |
| mist | Shift or C | 2 | 10 | 3 | +1 | Dash 2.0 cells over 0.18 s along move dir (or facing), stops at blocks (radius 0.2); no footsteps, `bumpDist` 0 during |
| still | F | 3 | 10 | 12 | +1 | 5 s: ping/door/step sounds do not make people react; `bumpDist` 0 |

`use` result codes: `E_LOCKED`, `E_COOLDOWN`, `E_POOR`, `E_UNKNOWN` (checked in that order). Failure plays `miss`; "Not enough blood" card at most once per 3 s. Unlock title card at night start: "Night 2 - Mist (Shift)".

Fear (int 0..15, shown as up to 5 eyes, 3 fear per eye):

| Event | Change |
|---|---|
| Person first grabbed (once per person per night) | +1 |
| Shriek / Mist / Still | +2 / +1 / +1 |
| Sleep | -5 (floor 0) |
| Gift Calm Town | -2 |

| Modifier | Formula | Cap |
|---|---|---|
| startleMul | `1 + min(0.6, 0.04 x fear)` (x `startleDist`) | +60% at fear 15 |
| fleeMul | `1 + min(0.2, 0.015 x fear)` (x flee speed 1.6) | +20% at fear 14 and up |
| calmMul | `1 + min(0.6, 0.04 x fear)` (x `calmAfter`) | +60% at fear 15 |

Separately, while Still or Mist is active the reaction config sets `bumpDist` to 0 (nobody notices a bump).

Hunger state: `{v:1, fear, over, giftsTonight, gifts[], essenceBonus, nextBlood, grabbed[], cd{}, stillLeft}`; serialize keeps only `v,fear,over,giftsTonight,gifts,essenceBonus,nextBlood`. `restore` is strict (fear int 0..15, giftsTonight <= 2, gifts <= 20 known ids) and returns null on bad input. API: `create, addOverflow, isOpen, cost, over01, rollGifts, takeGift, giftMods, onGrab, addFear, fearMods, powerState, cdLeft01, use, tick (dt clamp 0..0.1), isStill, onSleep, serialize, restore`.


## 10. Maps and town

Source: `js/data/maps.js`, `js/game.js`, `js/world.js`.

| Map | Kind | Notes |
|---|---|---|
| `crypt` | indoor, stone | One crypt bed `C`, no safe spots. One door to town (mausoleum) |
| `town` | outdoor, grass | 64 x 48. Zones: mausoleum, tavern, church, house1, house2, cellar, barn, shed. Three safe spots: barn (44,26), cellar (31,33), shed (45,39). Eight hide cells. About 48% lit by torches. 14 walkers on loop paths |
| `test` | outdoor | Debug and tests only (`?map=test`) |

Walkers: each has a looped path from map data with per-waypoint waits, speed, and optional `sit: true` (sitters walk back to their seat and stay). Paths must start on their `P` tile and not cross walls.

Tutorial hints (`game.js`, one per browser, shown under the crosshair, one at a time, never during cards):

| Id | Trigger | Text |
|---|---|---|
| ping | Queued at the start of a run until the first pulse retires it | "Click or Space to listen" |
| person | Queued when a person's echo first appears | "Echoes that move are people - hold right-click close to drink" |
| vial | Blood < 50 | "Vial = blood. Drink past full for gifts" |
| fear | Fear > 0 | "Eyes by the clock = fear" |
| sleep | Night 1 at 04:30 or later | "E at the crypt or a dark spot to sleep" |

The far safe spot pays +5 Essence.

Light rule: every door, gate and safe spot in the town must be reachable from the crypt door along cells with `lightAt` < 0.6, and every door and the gate along cells < 0.3 (checked in `tests/maps.test.js`); torches go on wall faces or verges, not the road centre.

## 11. HUD and controls (640 x 360 internal canvas)

Dim (alpha <= 0.55), boiled lines (10 fps), readable at 640x360. Every optional field absent = unchanged output.

| Element | Placement / look |
|---|---|
| Crosshair | 2x2 white dot, alpha 0.3, centre |
| Blood vial | Centre (30, 318), 14 x 34, cork on top; level = `blood01` as 2-3 hatch lines with surface slosh (amp 1.5 px, none when reduced); liquid `#d0505e`, outline `#cfe3ff`, flickers when weak |
| Dial | Centre (606, 330), r 16, dotted upper semicircle (9 dots), crescent left, sun right, marker by `frac`; sun brightens after 05:00; tiny `HH:MM` under (9 px, alpha 0.4) |
| Cooldown arc | Bottom centre, r 6, while `pulse01 > 0` |
| Overflow bar | `#ff8a78` thin bar x 21-39, y 293, fills with `over01`, pulses > 0.8, hidden when closed and empty |
| Powers row | Icons ~18 px at x 62 / 86 / 110, y 318; locked hidden, poor alpha 0.25, cooldown alpha 0.4 + sweeping arc, ready alpha 0.8 + key letter (Q, shift, F) |
| Fear eyes | Up to 5 tiny eyes, x 582-630, y 304; each eye = 3 fear; partial = half alpha |
| Still border | Inner border inset 4 px, `#cfe8ff`, alpha <= 0.12, fades with `still01` |
| Mist streaks | Soft horizontal lines y 140-218, alpha <= 0.25 x `mistK` |
| Not-saved dot | Coral dot at (628, 351), "not saved" text (see Section 7) |
| Dawn | `drawDawn(k)`: grey grain + edge vignette, no-op at k <= 0 |
| Card | 28 px bold monospace boiled outline lettering, `CARD_DUR` 2.4 s |
| Controls line | "WASD move - Arrows move/turn - Mouse look - Left click / Space pulse - Right click / R drink - E doors / sleep - Esc pause - Q shriek - Shift / C mist - F still" |

v0.16 polish (all new marks are fx-gated, alpha <= 0.55, and static):

| Element | fx | Look |
|---|---|---|
| Vial glass highlight | >= 1 | 1 px line down the left side, alpha 0.25 x flicker |
| Vial meniscus | >= 1 | curled edge where the level meets the glass, alpha 0.4 |
| Dial inner arc | >= 1 | thin second arc under the dotted track, alpha `feedDim` x 0.2 |
| Ready power ring | >= 1 | static ring at r 11 on ready powers, alpha 0.2, no pulse |
| Power and glyph taper | 2 | `icons.draw` `taper`: full length at 0.7 x width plus the middle 70% at full width |

Menu buttons (`css/style.css`): ink underline on `:hover` and `:focus-visible`, 2 px `--ink` focus outline with a faint background tint, transitions 120 ms. Transitions are `none` under `prefers-reduced-motion: reduce` and `body.reduce-motion`.

### 11.1 Input

Source: `js/input.js`, `js/player.js`, `js/game.js`.

| Input | Action |
|---|---|
| W / S, ArrowUp / ArrowDown | Forward / back |
| A / D | Strafe left / right |
| ArrowLeft / ArrowRight | Turn; speed `keyTurnSpeed` (default 3.2 rad/s, range 1..6) |
| Mouse (pointer locked) | Turn; `mouseSensitivity` 0.0025, `invertMouse` |
| Left button drag (not locked) | Look, when `dragLook` is on (default). Dragging more than a few pixels turns the view and does not pulse or lock |
| Left click / Space | Pulse. Space also counts as a click |
| Right button held / R held | Drink (or toggle with `feedToggle`) |
| E | Doors; sleep at crypt or safe spot |
| Q / Shift or C / F | Shriek / Mist / Still |
| Esc | Pause. Lock loss and window blur clear held keys |
| M, F3 | Map view and overlay (debug builds only) |

Pointer lock requests `unadjustedMovement: true` first, falling back to a plain request. Mouse movement spikes > 300 px are clamped, > 1000 px dropped. If lock is refused, clicks pulse.

### 11.2 Settings

Source: `js/config.js` (DEFAULTS, SCHEMA), `index.html`, `game.js` (`syncControls`).

| Key | Default | Range | Label |
|---|---|---|---|
| mouseSensitivity | 0.0025 | 0.0005..0.01 | Mouse sensitivity |
| invertMouse | false | bool | Invert mouse |
| volume | 0.7 | 0..1 | Volume |
| ambienceGain | 0.6 | 0..1 | Ambience |
| renderScale | 1.0 | 0.25..1 | Render scale |
| fovDeg | 66 | 50..100 | Field of view |
| headBob | true | bool | Head bob |
| lineBoil | true | bool | Wobbly lines |
| keyTurnSpeed | 3.2 | 1..6 | Key turn speed |
| dragLook | true | bool | Drag to look |
| feedToggle | false | bool | Click to start/stop drinking |
| reduceMotion | false | bool | Reduce motion (also follows the OS setting) |
| largeText | false | bool | Large text |
| nightLengthMin | 4 | 2..30 (slider 4..12) | Night length |
| poolMin / poolMax | 18 / 32 | 5..100 / 5..150 | Walker blood pool |
| feedReach / feedArcDeg | 1.5 / 60 | 1..3 / 20..120 | Drink reach and arc |
| dazedTime | 3 | 0.5..10 | Released victim dazed time |
| effects | 2 | 0..2 (menu: Off, Low, High) | Effects (figure detail, section 5.6) |

Other keys (sonar, render, `autosaveSec` 20 in 5..300, `moveSpeed`, `showFps`) are in `config.js` and not in the menu. Invalid values fall back to defaults with a warning; unknown keys are ignored.

## 12. Debug hooks

Only with `?debug=1` on `VCS.Game`. URL params: `?debug=1` (verbose log, F3 overlay, M top-down map), `?map=NAME` (debug only; `test`, `crypt`, `town`), `?seed=N` (fixed run seed), `?safe=1` (ignore saved settings).

| Group | Hooks |
|---|---|
| State / world | `debugState`, `debugAcc`, `debugAdvance(s)`, `debugTeleport(x,y,angle)`, `debugMap(name, doorId)`, `debugZone`, `debugPeopleState`, `debugEchoes`, `debugPulse`, `debugInteract` |
| Night | `debugTime(h,m)`, `debugBlood(v)`, `debugNight`, `debugSleep` |
| Feeding | `debugFeed`, `debugFeedHold(seconds)` |
| Meta / saves | `debugSave`, `debugMeta`, `debugEssence(n)`, `debugEndRun(kind)`, `debugPickBoon(i)`, `debugRun`, `debugFx`, `debugMenu(action: continue, newrun, shop, stats, menu)`, `debugExport`, `debugImport`, `debugPending` |
| Hunger | `debugHunger`, `debugHungerSet`, `debugFear(n)`, `debugOverflow(n)`, `debugPower(id)`, `debugPickGift(i)` |
| Forge | `debugForgeSpawn(archetype, x, y, angle)` (random seed), `debugForgeAlter(id, patch)` |

## 13. Testing and simulation

| Command | What |
|---|---|
| `node --test tests/*.test.js` | Unit suite (node:test, Node 22): one file per module plus feature files (feed, drink, ramp, hunger, save-v4, meta-extra, ...) |
| `node tests/smoke.mjs` | Chromium via Playwright; drives the real page with `?seed=7&debug=1` (some runs add `&map=test` or `&safe=1`); writes screenshots to `tests/out/` |
| `node tools/sim.mjs [--runs N] [--seed N] [--json]` | Economy simulation with no browser. Runs the real `night.js`, `hunger.js`, `meta.js`, `upgrades.js` and `config.js` rules over simulated players. Default 200 runs, seed 1 |
| `node tools/sim.mjs ... [--poolMin N] [--poolMax N] [--fearSleep N] [--drainRamp X] [--giftCosts a,b]` | Same, with the listed values overridden for this run only. Game files are never changed |

The sim's assumptions are listed at the top of `tools/sim.mjs`.

Gates before release: full unit suite and smoke green; security grep (forbidden APIs) clean; CSP unchanged; no page or console errors; forced crash shows the error screen; FPS >= 35 hard, >= 50 target; screenshots reviewed.
