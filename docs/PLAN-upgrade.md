# Upgrade plan: v0.14.0 NPC Forge, v0.15.0 volumetric characters, v0.16.0 FX and UI

Base: v0.13.2 (`VCS.Log.VERSION` in `js/log.js`). Workers follow every job in order. A job may start only when the jobs it depends on are merged. Jobs marked **||** run in parallel with each other, because their file sets never overlap. Model tags: **[haiku]** for mechanical, test, data and doc chores; **[sonnet]** for implementation.

## 0. Rules for every job (from docs/DESIGN.md section 1, not negotiable)

- IIFE `(function (root) { ... })(typeof window !== 'undefined' ? window : globalThis)`, attach to `root.VCS`, also `module.exports`.
- Never use `innerHTML`, `outerHTML`, `insertAdjacentHTML`, `document.write`, `eval`, `new Function`, `alert`, `confirm`. Build DOM with `createElement` + `textContent` only.
- Public functions never throw. They return `{ok, code, ...}`. Log through `VCS.Log.get('<module>')` and fall back to a no-op logger.
- Data modules are deep-frozen. Copy the `deepFreeze` helper from `js/data/vessels.js:14`.
- Untrusted input: reject the keys `__proto__`, `constructor` and `prototype`, read own properties only, clamp numbers.
- Storage keys start with `vcs.`. No libraries, no network, CSP stays unchanged. Every new file gets a `<script src defer>` tag in `index.html`, in the order given below.
- Style: dim, hand-drawn, thin lines. No blood or gore. Nothing flashes above 3 Hz. Reduced motion (`r.reduced` / `S.reduced`) is respected. Every cue has an audio twin and a visual twin.
- Release gates (DESIGN section 13):
  - `node --test tests/*.test.js` is green (706 tests today).
  - `node tests/smoke.mjs` is green.
  - The security grep is clean: `grep -nE "innerHTML|outerHTML|insertAdjacentHTML|document\.write|eval\(|new Function" js/` returns nothing.
  - FPS is >= 35 hard and >= 50 target.
  - Baseline screenshots are captured with `node tests/smoke.mjs --shots` (writes `tests/shots/base-*.png` and prints `BASELINE {fps, shots}`) and reviewed.
- Version bump (last job of each release): update `js/log.js` `VERSION`, the README line `Current build (vX.Y.Z)` (checked by `tests/log.test.js`), and the DESIGN.md title and section 1 version cell. Add the new DESIGN sections listed in each release.

---

# v0.14.0 NPC Forge

Goal: villagers come from data archetypes plus a seed. The 10 shipped roles, the sitters and the test map look, sound and walk exactly as they do in v0.13.2. New: 3 archetypes, mid-night spawn/despawn/alter, save integration and a dev panel editor. **There is no visual change in v0.14.** The renderer ignores the new look fields until v0.15.

## 14.1 What exists today (read before coding)

- `js/people.js:68` `makeLook(seed, id, accOffset)`:
  - RNG: `mulberry32(((sd>>>0) * 2654435761 + (pid+1) * 40503 + 977) >>> 0)`. Note this is a float multiply, not `Math.imul`.
  - Draw order: height `0.9+0.15r`, build `0.9+0.25r`, stride `0.9+0.25r`, then `acc = ACCESSORIES[(off+3*pid) mod 10]` (no draw), body (BODIES), head (HEADS), hair (HAIRS, forced `none` under nightcap, hood or tophat), beard `r<0.3`, nose `0.7+0.7r`, coat `r<0.45`. `hat` and `prop` are derived from `acc`.
  - Returns 12 keys.
- `People.create` (`people.js:381`):
  - `accOffset = floor(mulberry32((seed*7919+13)>>>0)() * 10)`.
  - Walker i pairs with the i-th `P` tile and with `mapDef.paths[i]`.
  - `role = def.role || ''`.
  - A schedule is made when `Sched.hasRole(def.role)` and the walker does not sit. Schedule RNG is `mulberry32((seed*31 + i*977 + 5)>>>0)` with `{home, slot: i}`.
  - Role checks: `people.js:664` (`s.role !== 'guard'`, go home at FEAR_HOME 8) and `people.js:1338` (gait `mail` for guard).
- `js/schedule.js`:
  - `ROLES` is a template table for innkeeper, drunk, regular, priest, elder, farmer, mother, insomniac and gravedigger.
  - `ROLES.guard` is a function of slot that walks the `POSTS` watch.
  - Exports `ROLES, hasRole, build, make, ...`.
- `js/data/voices.js:806`:
  - `presetFor(role)`: child → `child`; elder, old, priest, grand → `elder`; woman, mother, maid, wife, baker, innkeeper → `woman`; anything else → `man`.
  - `groupOf(role)` at `:590` is the daytalk group.
  - `forPerson(seed, role)` is called from `game.js:528` and `game.js:616` as `forPerson(who.id, who.role)`.
- `js/data/maps.js`:
  - `maps.town.paths` holds 14 entries (`{points, waits, speed, role?, home?, sit?}`). 3 are sitters with no role.
  - `maps.test.paths` holds 3 entries with no role. The key name `paths` stays, because tests read it.
- Saves:
  - The run snapshot `people` is `{mapName: seed}` (`game.js:4563`). It is applied by `peopleFor(name, seed)` (`game.js:3943`).
  - `save.js:15` `RUN_KEYS`, `save.js:447` `sanitizeRun`, `save.js:439` `mod(name, file)` (lazy module lookup).
- Dev panel: `js/devpanel.js` builds static sections in `init` (tools at `:182`, io at `:192`). `build()` rebuilds only the flag/tunable groups.

## 14.2 The shared `look` schema (single source; v0.15 and v0.16 read only this)

```
look = {
  // legacy keys (v0.13; read by today's drawPerson; exact values must not change for legacy archetypes)
  height: 0.5..1.2, build: 0.7..1.4, stride: 0.7..1.4,
  acc:  ACCESSORIES | 'none',      // tophat nightcap bonnet cane scarf lantern hood umbrella cap basket
  body: 'bean'|'pear'|'stick'|'round'|'box',
  head: 'round'|'egg'|'square'|'long',
  hat:  'none'|'tophat'|'nightcap'|'bonnet'|'cap'|'hood',
  hair: 'none'|'tuft'|'bun'|'spiky'|'curls'|'bob',
  beard: bool, nose: 0.5..1.6, coat: bool,
  prop: 'none'|'cane'|'lantern'|'umbrella'|'basket',   // right hand (side 1)
  // v0.14 keys (ignored until v0.15)
  v: 1,
  archetype: id string,
  outfit:  'plain'|'mail'|'robe'|'apron'|'smock'|'cloak',
  roleHat: 'none'|'kettle'|'biretta',   // volumetric mode draws this instead of `hat` when not 'none'
  extra:   'none'|'shovel'|'bundle'|'ledger'|'bow',     // left hand (side 0)
  stoop: 0..0.4, shoulder: 0.8..1.25, hem: 0..1 (0 waist .. 1 ankle), skin: 0..1 (flush gain)
}
```

Rules:
- `hat` follows `acc` (hat-type accessories). `prop` follows `acc` (prop-type accessories).
- `hair` is `none` under tophat, nightcap or hood.
- Looks returned to callers are plain objects. Do not freeze them, because `tests/render.test.js:243` mutates `look.acc`.
- An alter never mutates in place. It builds a new object, so old echoes keep their snapshot.

## 14.3 Data shape: `js/data/archetypes.js` → `VCS.ArchetypeData` (deep-frozen)

```
ArchetypeData = {
  LOOK_KEYS, LOOK_ENUMS: {acc, body, head, hat, hair, prop, outfit, roleHat, extra},
  LOOK_RANGES: {height:[0.5,1.2], build:[0.7,1.4], stride:[0.7,1.4], nose:[0.5,1.6], stoop:[0,0.4], shoulder:[0.8,1.25], hem:[0,1], skin:[0,1]},
  LEGACY_RECIPE: { height:[0.9,0.15], build:[0.9,0.25], stride:[0.9,0.25], bodies:BODIES, heads:HEADS, hairs:HAIRS,
                   beardP:0.3, nose:[0.7,0.7], coatP:0.45, acc:'cycle' },     // [min, span]
  REINFORCE: [ {fear:6, archetype:'guard', card:'The watch is doubled'}, {fear:10, archetype:'hunter', card:'A hunter walks the lanes'} ],
  list: [ archetype, ... ],
  byId(id) -> archetype|null, byRole(role) -> archetype|null   // own-prop lookups; role '' -> patron
}
archetype = { id, role, label, legacy, voice, talk, schedule, watch, feedable, gait, speed, recipe, extras }
  id: /^[a-z][a-z0-9_]{1,23}$/; role: string ('' allowed); voice: VoiceData.PRESETS key; talk: daytalk group
  schedule: null | 'watch' | [[[placeToken...], until, act], ...]   // same tuple format as schedule.js ROLES
  recipe: LEGACY_RECIPE (all legacy archetypes) or own recipe with the same keys
  extras: {outfit, roleHat, extra, stoop, shoulder, hem, skin}  // number = fixed, [min, span] = drawn
```

Archetype table. Legacy rows must reproduce today's `presetFor` and `groupOf` results. Schedules are moved verbatim from `schedule.js` ROLES.

| id | role | legacy | voice | talk | schedule | watch | feedable | gait | extras (outfit / roleHat / extra / stoop / hem) |
|---|---|---|---|---|---|---|---|---|---|
| patron | '' | yes | man | villager | null | no | yes | walk | plain / none / none / 0 / 0 |
| innkeeper | innkeeper | yes | woman | innkeeper | ROLES.innkeeper | no | yes | walk | apron / none / none / 0 / 0.6 |
| drunk | drunk | yes | man | drunk | ROLES.drunk | no | yes | walk | plain / none / none / 0 / 0 |
| regular | regular | yes | man | innkeeper | ROLES.regular | no | yes | walk | plain |
| priest | priest | yes | elder | priest | ROLES.priest | no | yes | walk | robe / biretta / none / 0 / 1 |
| elder | elder | yes | elder | elder | ROLES.elder | no | yes | walk | plain / none / none / 0.25 / 0.5 |
| farmer | farmer | yes | man | farmer | ROLES.farmer | no | yes | walk | smock / none / none / 0 / 0.3 |
| mother | mother | yes | woman | mother | ROLES.mother | no | yes | walk | apron / none / bundle / 0 / 0.8 |
| insomniac | insomniac | yes | man | villager | ROLES.insomniac | no | yes | walk | plain |
| gravedigger | gravedigger | yes | man | gravedigger | ROLES.gravedigger | no | yes | walk | smock / none / shovel / 0.05 / 0.2 |
| guard | guard | yes | man | guard | 'watch' | yes | yes | mail | mail / kettle / none / 0 / 0.3 |
| child | child | no | child | child | [[['@table'],0.06,'eat'],[['@hearth'],0.14,'play'],[['@bed'],1,'sleep']] | no | **no** | walk | plain; recipe height [0.58,0.08], build [0.85,0.15], beardP 0 |
| merchant | merchant | no | man | villager | [[['square'],0.18,'sell'],[['tavern_t'],0.34,'drink'],[['@bed'],1,'sleep']] | no | yes | walk | cloak / none / ledger / 0 / 0.7; coatP 0.9 |
| hunter | hunter | no | man | guard | 'watch' | yes | yes | walk | cloak / none / bow / 0 / 0.4 |

- In every row, `shoulder` is `[0.95, 0.1]` and `skin` is `[0.35, 0.3]`. Mail, robe and kettle rows use `shoulder [1.05, 0.1]`.
- `speed` is 1.0, except guard and hunter at 1.3. It is only used when a spec has no path speed.
- Children are never feedable (`isFeedable` false) and are never reinforcements. They do not appear in town in v0.14. They exist for the dev panel only. **Product decision to confirm before v0.15 ships them anywhere.**

## 14.4 API: `js/forge.js` → `VCS.Forge` (seed-deterministic, never throws)

```
Forge.lookSeed(stateSeed, entrySeed) -> uint32         // EXACT legacy formula with pid := entrySeed
Forge.legacyLook(seed, id, accOffset) -> 12-key look   // body of today's makeLook, moved verbatim
Forge.generate(spec, ctx) -> {ok, code, person}
  spec = {archetype, seed?, home?, overrides?}; ctx = {stateSeed, index, accOffset}
  entrySeed = int 0..65535 ? spec.seed : ctx.index
  person = {archetype, role, look, voice: preset name, talk, schedRole: role|null, home, watch, feedable, gait}
  look = recipe draws in the 14.1 order from mulberry32(lookSeed), acc = 'cycle' ? ACCESSORIES[(accOffset+3*entrySeed) mod 10] : fixed
         then extras: arrays drawn from mulberry32((lookSeed ^ 0x9E3779B9)>>>0) in key order shoulder, skin, stoop, hem
         then overrides via validate('look', ..., {partial:true}); archetype/v set last
  unknown archetype -> {ok:false, code:'E_FORGE_UNKNOWN', person: generate(patron)}
Forge.alter(look, patch) -> {ok, code, look (new object), changed: [keys]}     // re-derives hat/prop/hair rules
Forge.validate(kind, obj, opts) -> {ok, code, value, errors: [string]}           // kind: look|archetype|spec|library
  clamps to LOOK_RANGES; bad enum -> default; non-boolean -> default; bad keys rejected
  codes: OK, E_FORGE_TYPE, E_FORGE_BAD_KEY, E_FORGE_UNKNOWN, E_FORGE_LIMIT, E_FORGE_PARSE
Forge.archetype(id), Forge.list() -> ids (built-ins then custom), Forge.byRole(role)
Forge.register(arch) -> {ok, code}            // custom overlay map (Object.create(null)); built-in ids refused; <= 16
Forge.loadLibrary(storage), Forge.saveLibrary(storage) -> {ok, code}   // key 'vcs.forge', {v:1, list:[...]}, <= 16384 bytes
Forge.exportLibrary() -> string, Forge.importLibrary(text) -> {ok, code, n}
Forge.reinforcement({fear, night, runSeed, fired}) -> null | {archetype, seed, card}
  next REINFORCE entry with fear >= entry.fear and index === fired; seed = (runSeed*31 + night*977 + fired*7919) >>> 0
Forge.LOOK_FIELDS  // frozen [{key, type:'num'|'enum'|'bool', min, max, step | values}] for the editor
```

Parity holds because `People.makeLook(seed, id, off) === Forge.legacyLook(seed, id, off)`, and every legacy entry gets `seed = index`.

## 14.5 Jobs

**A0 [haiku] Golden fixtures (before any refactor)**
- Add `tools/forge-golden.mjs`. It loads log, data/maps, data/voices, world, schedule and people via `require` and writes `tests/fixtures/forge-golden.json`. Contents:
  - For maps `test` and `town`, seeds `[1, 7, 123456]`, every person: `{id, role, look, voice: VoiceData.forPerson(id, role), talk: groupOf(role), stops: sched ? stops.map({place, act, until rounded 1e-9}) : null, x, y}`.
  - `People.makeLook(11, id, 3)` for id 0..39.
  - `presetFor` and `groupOf` for every role string in the town map plus `''`.
- Run it on the v0.13.2 tree and commit the fixture.
- Acceptance: the file exists and the script is deterministic (run twice, identical output).

**A1 [sonnet] `js/data/archetypes.js` || A2**
- Build exactly per 14.3.
- Schedule tuples are copied from `schedule.js` ROLES. Delete nothing in schedule.js yet.
- Deep-freeze the module.
- Script tag goes after `js/data/vessels.js`.

**A2 [sonnet] `js/forge.js` || A1**
- Build per 14.4. Use a `mod('ArchetypeData', './data/archetypes.js')` lookup (save.js pattern).
- Use a private mulberry32 copy that is bit-identical to people.js.
- Script tag goes after `js/schedule.js` and before `js/people.js`.
- Add `tests/forge.test.js`:
  - Determinism: same spec and ctx give deep-equal output. Different seeds give different looks.
  - Every built-in archetype validates OK and generates OK for 20 seeds, with all values inside LOOK_RANGES and enums.
  - The hat, prop and hair rules hold.
  - `validate` rejects `{"__proto__":...}`, `constructor` and `prototype` (parse with `JSON.parse` so the key is own). It clamps `height: 99` to 1.2. Non-objects give `E_FORGE_TYPE`.
  - `register` refuses built-in ids and a 17th custom.
  - Library round trip through a fake storage. An oversize library gives `E_FORGE_LIMIT`. Garbage text gives `E_FORGE_PARSE`.
  - `reinforcement` fires at fear 6 and 10 in order, is null below, and is deterministic.
  - No call throws on `undefined`, `NaN`, strings or cyclic objects.

**A3 [sonnet] Refactor readers onto archetypes (after A0-A2)**
- `js/data/maps.js`:
  - Replace each `role: 'x'` with `archetype: 'x', seed: <i>`, where i is the entry index in its `paths` array.
  - Sitters and test-map entries get `archetype: 'patron', seed: <i>`.
  - Keep `points/waits/speed/home/sit`.
- `js/people.js` `create`:
  - Resolve each entry: `def.archetype`, else `Forge.byRole(def.role)` (back-compat for old map data), else patron.
  - `person = Forge.generate({archetype, seed: def.seed, home: def.home}, {stateSeed: seed, index: i, accOffset})`.
  - Set `p.look`, `p.role = person.role`, `p.archetype`, `p.watch`, `p.feedable`, `p.gait`.
  - Schedule only when `person.schedRole && Sched.hasRole(person.schedRole)`, with an unchanged RNG and options.
  - Store `state.places`, `state.mapDef` and `state.accOffset` for A4.
  - Replace `s.role !== 'guard'` (`:664`) with `!p.watch`. Thread `p` (already in scope).
  - Replace the gait test at `:1338` with `p.gait === 'mail'`.
  - `isFeedable` returns false when `p.feedable === false`.
  - `makeLook` becomes `return Forge.legacyLook(seed, id, accOffset)`, with the people.js copy as a fallback when Forge is missing.
- `js/schedule.js`:
  - `ROLES` is built at load from `ArchetypeData.list`. Array schedules are used as-is. `'watch'` maps to the existing slot function (keep `POSTS`, `WATCH_STOPS`). The key is `arch.role`, skipping `''`.
  - Keep the export names. Remove the inline table.
- `js/data/voices.js`: `presetFor(role)` and `groupOf(role)` first check `root.VCS.ArchetypeData && byRole(role)` at call time. They return `.voice` / `.talk` when found, else they fall through to the current regexes, which stay for unknown strings.
- Tests to update:
  - `tests/schedule.test.js:92` reads `Forge.archetype(p.archetype).role` instead of `p.role`.
  - The test files that require schedule/people must also `require('../js/data/archetypes.js')` and `forge.js` first.
- Add `tests/forge-parity.test.js`: for every fixture row, rebuilt people deep-equal the A0 golden data (look's 12 legacy keys, role, voice, talk, stops, x, y), and `makeLook(11, id, 3)` matches.
- Acceptance: the full suite is green, and `--shots` images are pixel-identical to v0.13.2 (`street`, `tavern`, `feeding`).

**A4 [sonnet] Mid-night hooks + game wiring (after A3; || A5 || A6)**
- New exports in `js/people.js`:
  - `spawn(state, world, spec, at)` → `{ok, code, id}`:
    - id = `state.nextId++` (init to `people.length` in create).
    - One-point path at `at`. Pool from the existing pool range, drawn from `mulberry32(spec.seed)`, not from `state.rng`, so other streams stay unchanged.
    - Schedule via `Sched.make(schedRole, state.places, at, rng, {home, slot: id})` plus `faceTables`.
    - Refuse when more than 24 people (`E_FORGE_LIMIT`) or `at` is solid.
  - `despawn(state, id)` → `{ok, code}`. Refused for modes grapple, dazed or fed (`E_FORGE_BUSY`). Splices the person out. Echoes stay.
  - `alter(state, id, patch)` → `{ok, code}` via `Forge.alter`.
  - `forgeState(state)` → `{spawned:[{a, s, x, y, ang}], altered:[{id, look: patch}]}`. Maintained by the three calls above.
- `js/data/maps.js` town: add `reinforce: { at: [2, 19] }` (the `street_far` cell).
- `js/game.js`:
  - New `stepForge(dt)` called from `simulateWorld` (`:1590`), at most once per 1 s, only while `playing` or `feeding` on a map with `reinforce`.
  - `Forge.reinforcement({fear: S.hunger.fear, night, runSeed: S.run.seed, fired})`. On a hit, spawn at `reinforce.at`, but only when the player is >= 10 cells away or `world.lineBlocked` from the player to that point.
  - Cue twin on spawn: `showCard(card)` plus `emitSound('bell', x, y)` (the existing `bell` kind in `data/sounds.js:233`).
  - At fear >= 8, once per night, alter every `watch` person to `{acc:'lantern'}`. This is visual only: it adds no light and leaves `world.lights` untouched.
  - At washout (night event `washout`), despawn reinforcements that are out of sight (`lineBlocked` or dist > 10) and not busy.
  - Debug hooks (`?debug=1`, near `:3836`): `debugForgeSpawn(archetype, x, y, angle)` and `debugForgeAlter(id, patch)`.
  - At boot: `Forge.loadLibrary(localStorage)` in try/catch.
  - Call `VCS.DevPanel.setForgeHost({spawnAhead(spec), alterNearest(patch), despawnNearest(), people()})` when DevPanel exists.
  - Snapshot (`:4563`): add `snap.forge = {v:1, maps:{name: People.forgeState(st)}}` for maps whose state has spawns or alters.
  - `applySnapshot` (`:4603`): after `peopleFor(name, seed)`, replay spawns then alters. Unknown archetypes are dropped with a warning.
- Tests: `tests/people.test.js` gets spawn, despawn and alter.
  - Ids are unique.
  - Despawn of a grappled person is refused.
  - Alter gives a new look object, and the old echo keeps the old look.
  - A spawned guard has `watch` and does not go home at fear 8.
  - The `state.rng` sequence is unchanged by a spawn.

**A5 [sonnet] `js/save.js` forge key (|| A4, || A6)**
- Add `'forge'` to `RUN_KEYS`.
- New `sanitizeForge(f)`:
  - Exact keys `v, maps`, with `v === 1`.
  - At most 4 map names (string <= 32 chars, bad keys rejected).
  - Per map, `spawned` <= 4 with `a` matching the id regex, `s` int 0..4294967295, `x/y` clamped 0..64, `ang` clamped -7..7.
  - `altered` <= 16 with `id` int 0..255 and `look` passed through `Forge.validate('look', .., {partial:true})` via `mod('Forge','./forge.js')`.
- In `sanitizeRun`, a bad `forge` value drops only `forge` (warn). The run still loads. Out gets `forge` only when valid.
- No `RUN_SCHEMA` bump. Old saves have no `forge` and load unchanged.
- Tests in `tests/save.test.js`:
  - A v4 run without `forge` gives deep-equal sanitized output before and after the change. Use a literal v0.13.2-shaped snapshot.
  - Garbage forge (`__proto__`, NaN, 1e9 coordinates, 50 spawns) gives a run that is ok with forge dropped or clamped.
  - A valid forge round-trips through `Save.create(memoryStorage).write/read`.

**A6 [sonnet] Dev panel editor (after A2; || A4 || A5)**
- In `js/devpanel.js`, add a static section `NPC Forge` (h3), built in `init` after the tools section.
- Controls, all via `el()`:
  - A `select` of `Forge.list()` (create `option` elements with `textContent`).
  - A seed `input[type=number]` (0..4294967295) and a `Random seed` button.
  - One row per `Forge.LOOK_FIELDS` entry: a range plus output for num, a select for enum, a checkbox for bool.
  - A `pre.dp-forge-preview` whose `textContent` is the JSON of the current look.
- Buttons:
  - `Spawn in front`, `Alter nearest`, `Despawn nearest`: these call the host and are disabled with the hint "Start a run to use these" when no host is set.
  - `Save as custom archetype`: `Forge.register` plus `saveLibrary`.
  - `Copy library JSON`: clipboard with the existing fallback pattern from `copyJson`.
  - `Import library JSON`: textarea plus `Forge.importLibrary`, then rebuild the select. The status line reports the result code.
- Add `Dev.setForgeHost(h)`.
- Add CSS for `.dp-forge-*` in `css/style.css`, reusing the dp- styles.
- Tests in `tests/devpanel.test.js`:
  - `setForgeHost` exists and accepts null.
  - Without a DOM, nothing throws.
  - A source grep test: devpanel.js contains no forbidden API names.

**A7 [haiku] Docs + release (after A3-A6)**
- DESIGN.md:
  - Add new section 5.5 "Archetypes and Forge": the 14.2 schema, the 14.3 table, REINFORCE, `vcs.forge`, and the run `forge` key.
  - Add rows to the section 2 module map.
  - Update section 7 Saves (keys, sanitize).
  - Add section 12 hooks.
- Bump to 0.14.0.
- Acceptance:
  - Suite and smoke are green.
  - `--shots` shows no visual diff versus v0.13.2.
  - Manual: in town with `?debug=1`, `debugFear(6)` gives the card and the bell, and a guard appears on the west road. A save and reload keeps it.

**v0.14 risks:**
- The float-multiply seed formula must be copied byte-for-byte. The golden fixture is the guard.
- `accOffset` uses `index`, not `entrySeed`. The parity rule requires `entrySeed === index` for shipped data.
- `game.js` and barks read `p.role`. It must stay populated (patron gives `''`).
- Splicing on despawn is safe, because every lookup is by `p.id` (`findPerson`, `barks.js:142`). Never despawn the feed victim.
- Changes to the schedule RNG stream break `tests/tables.test.js`. Do not draw from it in spawn.

---

# v0.15.0 Volumetric characters

Goal: `drawPerson` (`js/render.js:2164`) draws volumetric figures driven by `look`, behind the new setting `effects` (0 Off, 1 Low, 2 High). **Effects 0 is byte-identical to v0.14** (the old line figure).

## 15.1 What exists today

- Pose slots (PX/PY, `render.js:2064`), filled by `put(r, k, f, s, u)` (`:2080`):

  | Slot | Meaning |
  |---|---|
  | 0 | head |
  | 1 | neck |
  | 2, 3 | shoulders |
  | 4, 5 | hips |
  | 6, 7 | hands |
  | 8, 9 | feet |
  | 10, 11 | elbows |
  | 12, 13 | knees |
  | 14 | torso centre |
  | 15, 16 | scarf |
  | 17, 18 | hat tips |
  | 19 | prop grip |
  | 20 | prop tip |
  | 21, 22 | coat hem |
  | 23 | above head |

- Side 0 is left/+s and side 1 is right/prop.
- Pose by mode at `:2218-2377`: grapple via `VCS.Struggle.pose` / `STRUGGLE_POSE`, fed, cower, dazed, startle, seated, moving (walk/flee), and idle (wary, scratch).
- `drawAll` (`:2457`) is the line figure. The strip reveal is `wrapped` (`:2756`) with `STRIP_Z`, `SWEEP`, the front strip in white, and band-front rings.
- Vessels: `drawVesselsSeen` (`:2903`) and `drawVessels(r, e, X, Y, age, mute)` (`:2971`). Nodes `carotid` (slot 1), `temporal` (0), `radialL` (6) and `radialR` (7) come from `js/data/vessels.js`. `V.pulse(vein, i, age, tm, pws)` and `V.timing(bpm, reduced, pws)` exist. The bpm cap of 175 is below 3 Hz.
- Grab arms are `drawGrabArms` (`:2120`). Lights are `world.lights` `[{x, y, radius, type}]`, and `r.visWorld = world` is set in `drawFirstPerson`. LOD is computed at `:2455`, and `r.quality` runs 0..4.
- There is no chat pose yet (`e.chat` is snapshotted in `people.js` but unused by render). Role extras do not exist yet.

## 15.2 Design

- **Setting**:
  - `config.js`: `DEFAULTS.effects = 2` and `SCHEMA.effects = {type:'number', min:0, max:2}`.
  - `index.html`: `select#set-effects` with options 0 "Off (classic lines)", 1 "Low", 2 "High" and the label "Effects", next to `set-scale`.
  - `game.js` syncControls: `set('set-effects','value',...)` near `:2251` and `num('set-effects','effects')` near `:2333`.
  - Render reads `fx = Math.round(clamp(r.config.effects, 0, 2))` once per frame in `drawFirstPerson`, giving `r.fx`.
- **Split** `drawPerson` into:
  - `posePerson(r, player, tanHalf, e, age, locked, now, vol)`: today's `:2165-2426`. It fills PX/PY and the new PZ and writes a module-level `pose` scratch object `{hipU, shU, headU, hr, hry, bodyRx, bodyRy, tilt, lean, lod, depth, hs, vs, mode, moving, seated, flee, prop, hat, headKind, bodyKind, stars, eyesX, handsOverHead, jump, noseX, faceVis, eyesVis, gJolt, minX, maxX}`.
  - `drawLineFigure(c, sa, style)`: today's `drawAll`, unchanged, reading `pose`.
  - Dispatch inside `wrapped`: `vol ? Figure.draw(c, sa, style, P, pose, look, opts) : drawLineFigure(c, sa, style)`.
  - `vol = r.fx >= 1 && r.quality >= 1 && depth < 10 && !budgetOut`.
  - `vol`-only pose tweaks happen inside `posePerson` behind `if (vol)`, so effects 0 is untouched:
    - Elder stoop: `lean += stoop*0.1*lh; headF += stoop*0.06*lh; shU -= stoop*0.04*lh; headU -= stoop*0.05*lh`. Not applied in grapple, fed or cower.
    - Chat gesture: when `e.chat && !moving`, side 0 `handU += 0.06*lh*(0.5+0.5*sin(tN*2π*0.6+pid))` and `handF += 0.05*lh`. Reduced motion uses a static +0.03. Frequency is 0.6 Hz.
    - Extra slots 24 (extra grip, the side-0 hand) and 25 (extra tip): shovel over the shoulder while moving, planted by foot 8 while idle; bundle at the hand, clutched at `(1+14)/2` when fleeing.
- **Depth**: `PZ[k] = ff*fig.cr - ss*fig.sr`. Positive means away from the camera (consistent with the `persp` term at `:2088`).
  - Grow PX/PY/PZ to 28. Keep `fig.fid` and the `for k<24` bounds loop for the line figure (jitter ids 0..23 are unchanged). Vol mode loops 28.
- **`js/figure.js` → `VCS.Figure`** (new; script tag before `render.js`). It is pure drawing on a ctx, with no per-frame allocation (preallocated part arrays). Functions:
  - `capsule(c, x0, y0, r0, x1, y1, r1)`: adds a tapered-capsule outline subpath (two tangents plus two arcs; degenerates to a circle when the points coincide).
  - `parts(P, pose, look, out)`: up to 16 parts, each `{kind, a, b, r0, r1, z}`:
    - neck 1→0
    - torso: shoulders → hips, width `shS*|cr|*look.shoulder + depth*|sr|` (yaw narrowing)
    - upper arms 2/3→10/11, r `0.032→0.026*lh*hs`
    - forearms 10/11→6/7, `0.026→0.02`
    - thighs 4/5→12/13, `0.045*bw→0.034`
    - shins 12/13→8/9, `0.034→0.024`
    - hands, feet, head ellipse
    - extras
    - `z` = mean PZ of the endpoints
  - `sortBackToFront(parts, n)`: insertion sort by z, descending.
  - `draw(c, sa, style, P, pose, look, o)`, where `o = {fx, lw, alpha, rim:{side, k}, depth, reduced, front}`:
    - Per part, far to near: at fx 2 and depth < 6, fill `rgba(0,0,0,0.55*sa)` (occludes far lines). Then stroke the contour (`lw`).
    - Wrap contours: fx 2 → 2 per part at t 0.35/0.7, fx 1 → 1 at depth < 6. Each wrap is an elliptic arc across the axis with minor radius `r*(0.15+0.35*|sin yaw|)`.
    - Rim: a second stroke on the light side of each part, `#ffcf8a`, alpha `0.5*rim.k*sa`, `lw*0.8`. Only when rim.k > 0.02.
    - Contact shadow: a black ellipse under the feet (`rx 0.12*hs*bw`, `ry rx*0.18`) plus one arc stroke at alpha `0.2*sa`.
    - Distance falloff: depth >= 6 gives contours only. The caller passes line mode at >= 10.
    - Line-figure details are redrawn on top in the same path style: face (nose, eyes), hair, hats (or `roleHat`), scarf, coat hem, props, cower fingers and dazed stars. Copy the shapes from `drawAll` so poses read the same.
  - `drawExtras(c, P, pose, look, o)`:
    - mail: 3 rows of small scallop arcs across the torso, lod >= 1
    - robe: silhouette from the hips widening to the hem at `u = lerp(hipU-0.17*lh, 0.04*lh, hem)`; legs drawn below the hem only
    - apron and smock: a bib line plus a hem line
    - cloak: a back drape from the shoulders to the hem
    - kettle: a wide brim ellipse plus a dome
    - biretta: a square cap with 3 ridges and a tuft
    - shovel: a shaft plus a blade
    - bundle: an oval with a fold line
    - ledger: a small rectangle
    - bow: an arc plus a string, carried unstrung on the back
  - `drawFlush(c, P, pose, flush, o)`: soft coral fills `rgba(255,138,120,a)` at the face (0), neck (1) and wrists (6/7). `a = min(0.18, flush[i]*look.skin*0.25*sa)`. With reduced motion, a static `a <= 0.08`.
  - `drawGrabArmsVol(c, ...)`: the same signature and anchors as `drawGrabArms`. Tapered capsule forearms (`r0 = lw*4.5` at the screen bottom, `r1 = lw*2.6` at the grip), 2 wrap arcs and knuckle lines. Used when `r.fx >= 1`.
- **Rim light** (render.js, per figure): pick the nearest `r.visWorld.lights` within `3*radius` of the person.
  - `k = clamp(1 - d/(3*radius), 0, 1)`.
  - Screen side = sign of `(lx-ex)*(-sinθ) + (ly-ey)*cosθ`, with θ = player angle (the camera right vector).
  - Steady (lights never flicker, DESIGN 6.1).
- **Vessel flush**: `drawVessels` additionally writes `FLUSH[0..3]` (temporal, carotid, radialL, radialR). Each is the node pulse times the same stateK/periph factors it already computes. `drawVesselsSeen` calls `Figure.drawFlush` after the nodes when `r.fx === 2`.
  - Only on `vheart` echoes and the locked victim, the same gating as the overlay. Never for the vampire.
  - With `vis.vessels` off: no flush.
- **Progressive reveal**: keep `wrapped` strip clipping for both modes. In vol mode the band-front rings (`:2773`) use the capsule radius at that height instead of `hipS`/`bodyRx`.
- **Budget guard**:
  - `r.figMs` and `r.figVol`/`r.figLine` reset in `drawFirstPerson`.
  - Each vol `drawPerson` is timed with `performance.now()` (guarded). Once `r.figMs > budget` (Flags tunable `figure.budgetMs`, default 2.5, range 0.5..8, registered in `game.js` beside the `vessels` tunables at `:3701`), the remaining figures in that frame draw as lines.
  - If 20 of the last 30 frames went over, set `r.fxCap = 1` for 10 s (High becomes Low), then retry. Log once per change.
  - `Render.stats()` adds `figure: {vol, line, ms, cap}`.

## 15.3 Jobs

**B0 [haiku] Line-figure fixture (before B1)**
- Add `tests/fixtures/figure-line-v0140.json`: an FNV-1a hash of the fake-ctx call log (fn plus args rounded to 1e-3, stroke, alpha, lw).
- Inputs: `Render.drawFirstPerson` on the matrix of the existing test `every mode and look draws` (`render.test.js:231`), plus the locked victim (`feedLock`).
- Generator: `tools/figure-golden.mjs`. Same fakeCtx as `render.test.js:15`.

**B1 [sonnet] render.js split (after B0)**
- `posePerson` / `drawLineFigure` / `pose` / PZ / 28 slots, as specified in 15.2. Pure refactor: `vol` is always false in this job.
- Acceptance: the B0 hash matches and the suite is green.

**B2 [sonnet] `js/figure.js` (|| B1, || B3)**
- Implement against the 15.2 interface.
- Add `tests/figure.test.js`:
  - The capsule tangent points lie at the radii (±1e-6).
  - The coincident-points capsule is a circle.
  - `sortBackToFront` gives a stable descending order.
  - The `drawFlush` alpha cap holds at <= 0.18 (<= 0.08 reduced).
  - Every function with garbage input does not throw.
  - Each extra kind emits strokes.

**B3 [sonnet] Setting (|| B1, || B2)**
- Covers `config.js`, `index.html` and game.js syncControls (15.2 Setting).
- `tests/config.test.js`:
  - The effects default is 2.
  - 3 is rejected and gives 2.
  - `'2'` (a string) is rejected.

**B4 [sonnet] Integration (after B1-B3)**
- render.js:
  - The `vol` dispatch.
  - The vol pose tweaks.
  - Rim.
  - FLUSH in `drawVessels`.
  - `drawGrabArmsVol` selection.
  - Band-front radii.
  - Budget guard and stats.
  - `r.fx`.
- `js/people.js`: none.
- `js/game.js`: register `figure.budgetMs`.
- Tests in `tests/render.test.js`:
  1. Effects 0 still matches the B0 hash.
  2. For every `Forge.list()` archetype × 3 seeds × modes `['path' moving (phase 0.5, phaseRate 6), 'path' idle, sit, chat, 'startle', 'flee', 'cower', 'dazed', 'grapple', 'fed']` × fx {0,1,2} × quality {0,1,3} × reduced {false,true}, plus locked victim and grab arms: no throw, strokes > 0, `r.logged` empty.
  3. Fx 1 emits no black occlusion fills. Extend fakeCtx to record `fillStyle`.
  4. Budget: stub `performance.now` to step +5 ms per call. With 3 echoes, `stats().figure.line >= 2`. After 20 over-frames, cap is 1.
  5. PZ sign: an echo facing the camera (`angle = viewAng + π`) has PZ[0] (head forward f > 0 via `headF`) < PZ[14] in flee mode.
  6. Flush is drawn only for `vheart` with `vis.vessels` on, and never with `e.vampire`.
  7. Periodic terms: the chat gesture is 0.6 Hz, and the flush follows the bpm, capped at 175 (< 3 Hz).
- Shots (`tests/smoke.mjs --shots`, B5 adds the code): with `?map=test`, `debugForgeSpawn` places every archetype in a row 1.6 cells apart, 2.5 cells ahead. Set the modes via `debugPeopleState().people[i].mode` (path, sit, chat, flee, cower, dazed, grapple, fed). Pulse, advance 0.4.
  - Capture `base-lineup-fx0.png`, `base-lineup-fx1.png` and `base-lineup-fx2.png`.
  - Capture `base-feeding.png` and `base-street.png` at fx 2.
  - Set fx with `localStorage['vcs.settings']` before load, or with the settings select.

**B5 [haiku] Shots, docs, release (after B4)**
- Add the shots code above.
- Smoke main run asserts `debugState().fps >= 35` in the town street at fx 2, with 3 pulses.
- DESIGN.md new section 5.6 "Figures":
  - slots 0-27 and PZ
  - effects levels
  - parts and extras
  - rim, flush and budget rules
  - the 3 Hz list
- Add settings table row `effects`.
- Bump to 0.15.0.
- Review the screenshots for all 14 archetypes:
  - mail visible
  - priest hem and biretta
  - mother bundle
  - gravedigger shovel
  - elder stoop
  - child height

**v0.15 risks:**
- Fill cost at quality 3 with many echoes. The budget guard and depth LOD mitigate this. Verify `BASELINE` fps.
- Black occlusion fills hide floor and wall lines behind the echo of a person who has since moved. This is acceptable: it reads as "they were here". Keep the alpha at 0.55 and Low has no fills.
- Do not leak `vol` tweaks into fx 0. The B0 hash catches it.
- `drawVessels` is already heavy. FLUSH must reuse its computed alphas, not recompute the pulses.
- Child archetype visibility needs the product decision from v0.14.

---

# v0.16.0 FX and UI

Goal: post-FX, material texture, colour grade and HUD/menu/icon polish. All of it sits behind `effects` (0 = exactly v0.15 output). Constraints: dim thin-line style, no gore, no flashes above 3 Hz, reduced motion respected, and no new cue without an audio and a visual twin. Everything here refines existing cues; no new cue is added.

## 16.1 What exists today

- Glow: the half-res blur path in `drawFirstPerson` (`render.js` ~3860) runs only at `r.quality >= 4`, which needs `config.glowBlur`. The buffers are `r.glow` / `r.gctx` (built in `build()`).
- CSS overlays: `#vignette` (`setVignette`, `:305`) and `#grain` (`setGrain`, `:287`, `GRAIN_BASE 0.04`).
- The wavefront: `drawFloorFront` (`:1555`, a 1.5 px arc in `#e8f2ff`).
- Walls: `vert()` (`:511`) and buckets `pathFor` / `pathForC(ci, a, wc)` with `WCLASS [1.0, 1.5, 0.7]` (`:394-421`).
- Materials: `drawMat` (`:571`, stone `#`, brick `B`, wood `W`, iron `I`) through `matH(r,i,va,vb,..)` (slanted when va≠vb) and `matV`. Windows: `drawWindow` (`:769`, tile `w`).
- Atmosphere: `drawAtmosphere(r, lit, t, world, player)` (`:3628`). Dawn: `Night.dawnK`, `Hud.drawDawn` (`game.js:2048`). Body classes are toggled at `game.js:2301`.
- HUD: `hud.js` `drawVialBody` (`:111`), `drawDial` (`:233`), `drawPowers` (`:324`) and `drawCard` (`:636`). Icons: `icons.js` `strokePts` (`:118`) and `draw(ctx, name, size, t, opts)` (`:144`).

## 16.2 Jobs

**C0 [haiku] Frame fixture (before C2/C4)**
- Add `tests/fixtures/frame-v0150.json`: hashes of full `drawFirstPerson` call logs at effects 0 for 4 scenes:
  - crypt start
  - town street
  - window wall
  - dawn
- Generator: `tools/frame-golden.mjs`, with the same fakeCtx and fixed `t`/seeds.

**C1 [sonnet] `js/postfx.js` → `VCS.PostFx` (|| C2 || C3)**
- Script tag before `render.js`. API:
  - `bloom(r, ctx, fx)` → bool:
    - fx 2 and quality >= 3: the half-res copy of `r.off` with `blur(1.6px)` (only when `r.hasFilter`), drawn `lighter` at alpha 0.55.
    - quality 4: keeps today's alpha 0.85.
    - fx < 2: no-op, except quality 4 keeps today's behaviour exactly.
    - Reduced motion has no effect on bloom (it is static), but bloom never pulses.
  - `grade(r, ctx, g, fx)` with `g = {dusk:0..1, dawn:0..1}`:
    - fx 0: no-op.
    - Dusk: `multiply` fillRect `rgb(150,140,200)` alpha `0.10*dusk`.
    - Dawn: `multiply` `rgb(255,205,185)` alpha `0.12*dawn`, then `saturation` with grey alpha `0.25*dawn`.
    - Restore `source-over`/alpha 1.
  - `grainLevel(fx)`: 0 gives `GRAIN_BASE`, 1 gives 0.035, 2 gives 0.05.
  - `vignetteOpacity(fx)`: 0 gives unchanged, 1 gives 0.7, 2 gives 1.
- Add `tests/postfx.test.js`:
  - fx 0 makes zero ctx calls.
  - The grade alpha caps hold.
  - Without `filter`, bloom is skipped without throwing.
  - Garbage args do not throw.

**C2 [sonnet] render.js line and material texture (after C0; || C1 || C3)**
- `r.fxTaper = r.fx === 2 && r.quality >= 3`.
- `vert()`: when `fxTaper`, split each half at 30% from its outer end. Put the outer part in the thin bucket (`pathForC(ci, a, 2)`) and the inner part in the normal class. Two bucket paths, no extra flush.
- `drawFloorFront`: at fx >= 1, add 2 trailing arcs at `R-0.06` and `R-0.12` cells with alpha 0.45 and 0.2 (a soft gradient front). Reduced motion keeps the same static offsets.
- `drawMat` (fx >= 1, existing `quality >= 2` gate):
  - Stone `#`: per block, 2 short slanted hatch strokes with `matH(r, i, v, v+0.05, ...)` at `cellHash(cx,cy,9..10)` positions inside the lower third.
  - Wood `W`: draw the grain squiggles only when `((i>>1)&1)===0` (dashes).
- `drawWindow` (fx 2, `quality >= 2`): one seeded glint per pane at `(cellHash(cx,cy,11), cellHash(cx,cy,12))`.
  - Two crossed lines of `1.5*r.wscale`, alpha `0.3 * glow(age, dur)`.
  - Only while the ripple afterglow lasts. It fades once and never twinkles.
- Integration in `drawFirstPerson`. Code against the C1 API, guarded by `VCS.PostFx &&`. When PostFx is absent, keep today's glow block, so C2 works before C1 merges.
  - Replace the glow block with `PostFx.bloom`.
  - After `drawAtmosphere`, call `PostFx.grade(r, ctx, opts.grade, r.fx)`.
  - `setGrain(r, PostFx.grainLevel(r.fx) / GRAIN_BASE * l)` (scale the existing level).
  - `setVignette` opacity via `PostFx.vignetteOpacity`.
- `game.js` render opts (`:1974` `ro`):
  - `ro.grade = {dusk: S.night.min < 30 ? 1 - S.night.min/30 : 0, dawn: VCS.Night.dawnK(S.night)}`
  - `body.classList.toggle('reduce-motion', S.reduced)` at `:2301`
- Tests in `tests/render.test.js`:
  - Effects 0 matches the C0 hashes.
  - fx 2 window glint only while the ripple passes, alpha <= 0.3.
  - Stone hatch adds calls only at fx >= 1.
  - Taper adds no `stroke()` calls beyond the bucket count.
  - Grade is zero at minute 300.

**C3 [sonnet] HUD, menu and icon polish (|| C1 || C2; files hud.js, icons.js, css/style.css)**
- `hud.js`:
  - `drawVialBody`: a 1 px glass highlight on the left side (alpha 0.25) plus a meniscus curve on the level.
  - `drawDial`: a second thin inner arc on the crescent (alpha 0.2).
  - `drawPowers`: ready icons get a static soft ring (alpha 0.2, no pulse).
  - All of this applies only when the HUD state field `s.fx >= 1`. `game.js` fills `hs.fx` in the HUD-field fill (`:2106`), which is a one-line change owned by C3.
  - DESIGN 11: alpha stays <= 0.55.
- `icons.js`: `strokePts` takes an optional taper. When `opts.taper`, draw the polyline at `lw*0.7` full length plus the middle 70% at `lw`. `draw()` passes it through, and the HUD passes `taper: s.fx === 2`.
- `css/style.css`:
  - Menu buttons get `:hover` / `:focus-visible` ink underline and a 2 px `var(--ink)` outline on `:focus-visible`.
  - Transitions <= 150 ms, set to `none` under `@media (prefers-reduced-motion: reduce)` and under `body.reduce-motion`.
  - Panel border wobble uses the existing `--wonk-a` / `--wonk-b`.
- Tests:
  - `tests/hud.test.js`: `drawHud` with `fx` 0/1/2 does not throw, and fx 0 makes the same calls as before (count).
  - `tests/icons.test.js`: every icon draws with and without `taper`.

**C4 [haiku] Shots, docs, release (after C1-C3)**
- `--shots`: capture `base-street`, `base-tavern`, `base-church`, `base-dawn` and `base-hud-weak` at fx 0 and at fx 2, plus a new `base-dusk` (`debugTime(20,5)`).
- Smoke asserts no page errors and fps >= 35 at fx 2 in the street.
- DESIGN.md new section 6.5 "Post-FX and grade" (levels table, caps, the 3 Hz and reduced-motion notes).
- Update section 11 HUD.
- Bump to 0.16.0.

**v0.16 risks:**
- `filter: blur` is slow on some GPUs. Bloom is only on at fx 2 and quality >= 3, so adaptive quality (`adapt`, `:3659`) steps it off.
- The `multiply` and `saturation` composite ops are unsupported in old browsers. Guard them (check `ctx.globalCompositeOperation` after setting it, and skip if it did not take).
- Taper doubles the vertical segments. Measure with `BASELINE` and drop the taper first if fps falls by more than 10%.
- Grade must never darken the HUD. Draw it before the HUD canvas pass, inside render only.
- Glass glints must not read as a flash. A single fade with the afterglow (>= 0.2 s) stays below 3 Hz by construction.

## Parallelism summary

| Release | Serial spine | Parallel groups (file-disjoint) |
|---|---|---|
| 0.14 | A0 → {A1 ‖ A2} → A3 → {A4 ‖ A5 ‖ A6} → A7 | A1 `data/archetypes.js` ‖ A2 `forge.js` + `tests/forge.test.js`. A4 `people.js`, `game.js`, `maps.js`, `people.test.js` ‖ A5 `save.js`, `save.test.js` ‖ A6 `devpanel.js`, `style.css`, `devpanel.test.js`. `index.html` tags: A1 and A2 each add one line in different spots; merge by hand |
| 0.15 | B0 → {B1 ‖ B2 ‖ B3} → B4 → B5 | B1 `render.js` ‖ B2 `figure.js`, `figure.test.js`, `index.html` tag ‖ B3 `config.js`, `index.html` settings row, `game.js` syncControls, `config.test.js` (B2 and B3 both touch `index.html`: different lines) |
| 0.16 | C0 → {C1 ‖ C2 ‖ C3} → C4 | C1 `postfx.js`, `postfx.test.js` ‖ C2 `render.js`, `game.js:1974`/`:2301`, `render.test.js` ‖ C3 `hud.js`, `icons.js`, `style.css`, `game.js:2106`, `hud.test.js`, `icons.test.js` (C2 and C3 both touch `game.js`: different functions) |
