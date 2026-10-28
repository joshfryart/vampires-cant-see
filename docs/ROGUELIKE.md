# The Long Night: roguelike run mode (design, 0.21.x)

Godot-only. No JS parity. New modules live in sibling files; the classic `Meta`, run schema 4 and `people.gd` parity code are NOT changed. Classic "Five Nights" stays in the code and tests, hidden from the title (dev flag `--classic` brings it back).

Decisions (user, 2026-10-22): currency **Grave Soil** (existing Essence imports 1:1 once); checkpoint-only saves (stage entry and sleep); new baked sounds allowed via `node-web-audio-api` (`tools/bake-rogue-audio.mjs`); new data lives in `project/data/rogue/*.json` (never hand-edit generated `data/*.json`).

## Core rules
- Sun kills only on an outdoor cell in daylight (`night.gd`). Any roofed cell is sun-safe.
- Every stage starts at dusk (fog crossing between stages). Leaving early gives a fresh night.
- Pass the day by (a) **sleeping** at a rest spot (`S`/`C`: coffin, crypt, burrow, barrow, mausoleum): skip to dusk, drain x0.15, small discovery roll by rest-spot safety; or (b) **waiting out the day** in any roofed cell: interruptible fast-forward, drain x0.4, occupants live their schedules, you hear them as faint pulses, discovery means you deal with it (slip away, hide, Mist, feed at risk). Both add +1 **Heat**. Heat 2 spawns a hunter, Heat 3 two. Prey never respawns.
- Dawn warning ~90 s ahead (birds, bell, cold glow); rest spots hum a faint pulse.
- Cover guarantee: from any walkable cell a roofed cell is reachable within ~40% of the night's walk time; at least 3 covered pockets per stage, at least 2 true rest spots; rest spots hidden until within ~3 cells or heard.
- Deaths: sun; withered (blood 0 for 25 s); staked (hunter within 1.2 cells, unmisted, -45 blood); holy ground (-8 blood/s).
- Metric: **Miles from the Coffin** = cleared-stage miles + stage miles x best progress (BFS distance field from exit via `RunFlow.bfs_cells`). Full route 60 miles.

## Stages
| # | Stage | Maps | Walls / floor | Ambient | Fauna / people | Mi |
|---|---|---|---|---|---|---|
| 1 | The Hollow (cave) | 1 | roughStone, pools `~` | drips, ripples, mouth draft | bats, rats | 3 |
| 2 | Bramble Wood | 1 | `#` grass thicket, `W` trunks | wind, owl, creek | rabbits, deer | 3 |
| 3 | Gallows Moor | 1 | grass, `B` cairns, `I` gibbet | wind, crickets, howls | hares, wolves | 3 |
| 4 | The Old Road | 1 | `I` fences, `B` milestones | carts, shrine bell | travellers, first hunter | 4 |
| 5 | Crossroads Inn | 1 | timber | hearth, singing | patrons, horse | 3 |
| 6 | Hamlet and Farms | 1 | barns, fences | sheep, hens, dogs | farmers, dogs | 4 |
| 7 | Village | `town` | as today | dog, bell | villagers, guards | 5 |
| 8 | Lychgate Cemetery | 1 | stone, graves | crows, spade | mourners, sexton | 3 |
| 9 | Market Town | 1 | brick, cobble | fountain, watch | watch, priest | 5 |
| 10 | Warrens (poor) | 1 | cobble | gutter drips | beggars | 5 |
| 11 | Guild Row (commerce) | 1 | shopfronts | signs, coins | merchants, guards | 6 |
| 12 | Silk Ward (nobility) | 1 | railings | fountains, quartet | nobles (+50% feed) | 6 |
| 13 | The Keep (royalty) | 1-2 | stone, portcullis | throne echo T60 2.5 | royal guard, King | 10 |

Per-stage row in `data/rogue/stages.json`: `drainMul` (0.8 cave to 1.6 keep), `preyCount`, `watchers`, `lights`, `hunterBase`, `bloodGain`, shelter counts and kinds. Drinking from the King wins (+25 Soil).

## The Hollow (cave)
Seeded procedural from authored beat chunks (`data/rogue/chunks.json`), mulberry32 (`core/rng.gd`): Poisson-disc 8-9 chambers in 62x46, MST + 1 loop, order by tree depth, beat chunks along the main path, cellular-automaton filler chambers, biased drunk-walk tunnels (width 1-2), 2-3 blind spurs, 30-38% floor. Beats in order: Coffin Nook (upright coffin, drip 2 cells ahead after 1.5 s, "Something drips. Listen."), Drip Gallery, The Squeeze, Echo Hall (T60 ~2.2, pillars, bats), Still Pool (`~`), dead-end spurs, Rat Warren, Cave Mouth (wind draft, glow-worm light).
Echo geometry: big stalagmites = `#` pillar cells; small = solid prop `stalagmite`; `stalactite` non-solid ceiling prop and drip anchor; pools `~` (rays pass, movement blocked); zones per chamber for T60 (`data/rogue/acoustics_extra.json`, merged for missing keys only). Drip: `emit_sound(kind="drip", range 2.5, strength 0.35, fade 1.2, visRays 180, bounces 0)`, only within 12 cells of the player.

## Meta (The Coffin)
Soil = floor(miles) + 2 x humans fed + floor(critters/2) + 3 x stages cleared unseen + 5 new best stage; Soil Pouch multiplies. Upgrades: far_echo, lingering_echo, quick_call, slow_thirst, deep_draw, soft_step, warm_sense (existing effects), full_veins, drip_ear, thick_blood, long_wither, ratspeak, focused_cry, mist_born, stake_callus, silent_fang, bat_form, thrall, second_coffin, soil_pouch, waystones. Saves: `vcs.rogue` (soil, unlocks, stats, reached) and `vcs.trek` (seed, stage, leg, miles, progress, heat, night, hunger); `core/trek_meta.gd` with sanitize/migrate; `Store.key_of` gets the two kinds.

## Echo validation per environment
Open air (every walkable cell needs a solid cell within R: wild 6, road 5, city 4), ambient budget (4 live, 180 rays, within 12 cells, player ping protected), fast ray path bit-for-bit vs generic, water tile, no-light caves (glow-worms), caps per map (people 10-12, critters 12, props 60, lights 16, emitters 24), map size <= 64x48, determinism (stage = pure function of seed, id). Tests in `tests/unit/test_echo_env.gd`.

## Wild stages: Bramble Wood and Gallows Moor (WP13a, 0.21.1)
`core/gen/gen_wild.gd` (`GenWild.generate(row, seed, style)`, style = the row's `generator`: `wood` | `moor`). Both are `kind: outdoor` 64x48 maps (sun kills), start at dusk on the arrival cell of the west entry door, exit door on the east edge. Door names follow the neighbour's `toDoor`: hollow `mouth` -> wood `cave`; wood `moor` -> moor `wood`; moor `road` -> `stage:road`. The row's `entry {doorId, toMap, toDoor}` / `exit` give both; the def carries `entry {door, cell, arrival, toMap}` as well as `exit`.
- Row keys beyond the cave's: `terrain` (`wood`: `fill [lo, hi]`, `passes`, `fords`; `moor`: `pools [min, max]`, `blobs [min, max]`), `shelter.kinds` (pocket kinds: `hollow_tree` and `burrow` | `barrow` and `peat_cut`), `shelter.maxPockets`, `shelter.restTarget` (wood 30, moor 36), `fauna {small, big, bigCount, stumps, boulders}`, `ambient {wind, owls, creekEvery, creekMax, crickets, lightRadius}`.
- Wood: grass thicket `#` (CA), trunks `W`, a 2-wide creek `~` over the full height with 2 fords (2-row gaps with protected banks, `places.ford_N` = [x, y]) and trails to them, rabbits and deer, owl / creek / wind anchors, fireflies (`glowworm` props, light 2.0). Moor: open grass, gorse blobs `#`, cairns `B` (material roughStone), gibbets `I`, 2-3 bog pools `~` (ripple anchors), hares and wolves (wolves >= 18 cells from the start), wind and cricket anchors (cricket `quiet` 3.0: silent within 3 cells of the player), wisps (`glowworm`, light 3.0). The first wind anchor is 6-10 cells from the entry.
- Pockets are indoor zones (`pocket_<kind>_<n>`) stamped where they cannot cut a path (the open cells of their surrounding ring form one arc); each has an `S` rest spot (`rest[]` kind = pocket kind, safety by kind +-0.05). Added at the farthest walkable cell from the rest spots until it is within `restTarget` BFS cells (rule limit still 576), at least 3 (`shelter.pockets.min`), at most `maxPockets`.
- Open-air rule R = 6: obstacles drop on the walkable cell farthest from any wall (local distance-transform updates, threshold 5.5) and always have 8 floor neighbours; `GenWild.open_air_max(def)` is the exact check. Props are decoration (stump / boulder, solid) and `glowworm` lights; the rule is guaranteed by wall tiles alone.
- Tests: `tests/unit/test_gen_wild.gd`, `test_echo_env.gd` (`GENERATORS`), `tests/flow/test_trek_stages.gd`. Tool: `tests/tools/wild_probe.gd`.

## Road stages: The Old Road and Crossroads Inn (WP13b, 0.21.2)
`core/gen/gen_road.gd` (`GenRoad.generate(row, seed, style)`, style = `road` | `inn`; `StageGen.generate` dispatches both). Both are `kind: outdoor` 64x48, enter on the west edge, leave on the east edge, drainMul 1.1, and keep the open-air rule R = 5 (`GenRoad.open_air_max(def)`, walkable = `.,gSP@C`). Doors: moor `road` -> road `moor`; road `inn` -> inn `road`; inn `hamlet` -> `stage:hamlet` (no generator: TrekFlow ends `frontier`). Hunters are not spawned by the generators (TrekFlow `hunters_wanted` / RogueMode); the road has 2 `guard` (watch) walkers and `watchers: 2` in its row.
- Road (4 miles): floor cobble, a 3-wide winding cobbled band (`.`, double sine, slope <= 1 per column) with grass verges `g` (3-4 each side), 3-5 ragged field edges, `I` fence posts and `B` milestones beside the verge, ditches `~` along the outer verge (kept only when nothing is cut off), `shrine` prop (light 2.0) in a 5x5 alcove next to the road with a 3x3 zone `shrine_holy` of kind `holy` (nine floor cells, the centre is the solid shrine; TrekFlow drains `HOLY_DPS` = 8/s there and dies by `holy`; `WorldValidate` accepts the zone kind `holy`, the sun does not apply there), shrine `bell` anchor on the alcove ring. Pockets (indoor zones, every one a rest spot, safety lower than the wild stages): `wayside_crypt` (stone `B` ring, cobbled), `culvert` (earth bank), `bramble_hollow` (trunks), 3-12 of them, restTarget 28. People on `P` cells in row-major order, one path def each: a pilgrim pair (`patron`, ping-pong along the centreline), a carter (`merchant`), two `guard` walkers on 3-cell posts. Crows and 1-2 hares; ambient `cart` x2, `bell`, wind, crickets, ripples on ditch water; new kinds `cart`, `bell`, `singing` in `data/rogue/ambient.json`.
- Inn (3 miles): a yard (cobble, strip along the south) with the timber inn (`W`, wood floor `,`, windows `w`): common room (`tavern`, bar counter, 5 tables, torches, brazier hearth), kitchen (beds, brazier), cellar (barrels, rest spot `cellar`, safety 0.4: hostile owner), a stable (`stable` rest spot, hay) and a woodshed (`woodshed`) built into the south hedge, a well and a pond `~`. The front doorway and the room gaps are open wood floor (no `D`), so occupants see you: waiting out the day in the common room is a gamble. 8 people (cap): innkeeper, drunk, 2 regulars and a merchant live `tavern_*` / `square` schedules (`home: tavern`), 3 patrons sit at tables; rats only (stable has no horse prop yet). Ambient hearth x2, `singing`, wind, crickets.
- Both: `StageGen.SOLID_PROPS` now lists every solid prop type (shrine, haybale, scarecrow, table, chair, bench, barrel, well, brazier, gravestone) so BFS matches `World`. Tests: `tests/unit/test_gen_road.gd`, `test_echo_env.gd` (`GENERATORS`), `tests/flow/test_trek_stages.gd`. Tool: `tests/tools/road_probe.gd`.

## Work packages
WP0 resolve perf round 2; 1 this doc; 2 map registry + hooks; 3 water tile, props, covered pockets; 4 critters; 5 ambient emitters; 6 trek meta + saves; 7 cave generator; 8 trek flow; 8b wait-out-the-day; 9 integration (0.21.0); 10 UI; 11 Opus review; 12 echo suite; 13a-d wilderness/road/settlements/city; 14 hazards + powers; 15 docs; 16 final review. Cut-line, lowest priority first: thrall/bat form/second coffin, keep+nobility mechanics, cricket/howl reveals, holy ground, waystones, cemetery+inn, city districts beyond one, procedural variation outside the cave. Never cut: WP0, 2-10, 12.

## UI API (WP10)
`ui/menus.gd` (`Menus`, the `menus` node on Game) and `ui/trek_ui.gd` (`TrekUi`, `menus.trek_ui`). Classic Five Nights entries show only with `--classic` (`Menus.classic_override` forces it in tests).

Menus:
- signals `trek_new_requested`, `trek_continue_requested` (title buttons; continue shows when the store has a `trek` slot), `rise_again_requested`, `title_requested`
- `var trek_meta: Dictionary` (TrekMeta state; lazily read from the `rogue` slot if empty; buys write it back)
- `show_laid_to_rest(result: Dictionary)` / `hide_laid_to_rest()`; result `{cause: sun|withered|staked|holy|victory, stageName, miles, humans, critters, unseen, newBest, soil_breakdown{miles,humans,critters,unseen,newBest,pouch,...}, soilTotal, bestMiles}`
- `open_coffin(from_rest := false)`, `coffin_buy(id) -> {ok, code, text}`, `has_trek_checkpoint()`, static `locked_reason(meta, id)`

TrekUi:
- `show_stage_card(index, stage_name, miles, time_of_day := "dusk", seconds := 4.0)`
- `set_dawn(seconds_left)` (< 0 hides, <= 90 warning, <= 0 "The sun is up"), `dawn_state()`
- `show_wait_prompt(options := {title, body, wait_label, keep_label, on_wait, on_keep})`, `hide_wait_prompt()`; signals `wait_chosen`, `keep_looking_chosen`
- `show_waiting(blood, lines)`, `update_waiting(blood, lines)`, `hide_waiting()`; signal `wait_interrupted` (Stir button)
- static `stage_card_text`, `dawn_text`, `rest_text(result)`

## Audio (baked rogue sounds)
Baker: `node tools/bake-rogue-audio.mjs` (node-web-audio-api, seeded, deterministic; re-running gives identical files). Output: `project/audio/rogue/rg_*.wav` (mono 44.1 kHz 16 bit, peak 0.9, 27 files, about 3.4 MB) plus the manifest `project/data/rogue/sounds_rogue.json` (`{v, rate, peakTarget, dir, sounds:[{id, file, loop, ms, gain, bus, use}]}`; `gain` = suggested linear play gain). They live in `audio/rogue/`, not `audio/wav/`, because `tools/bake-audio.mjs` wipes `audio/wav/`. `AudioDirector` is unchanged and does not load these yet: WP9 reads the manifest and loads `dir + file` (`ResourceLoader.load_threaded_request` like `preload_streams`, or plain `load`), plays on a World-bus voice with `gain x scale`, and for `loop: true` builds the stream like `_loop_stream` (LOOP_FORWARD, loop_end = bytes / 2; head and tail are already cross-faded). Test: `tests/unit/test_rogue_audio.gd`. Existing sounds are reused where they exist: dog = `play:dog`, fire bed = `fire:bed`, wind = `amb:outdoor`, bell = `play:bell`.

| id | what | who plays it |
|---|---|---|
| `rg_drip_cave` | resonant drip | `stalactite` drip anchor in cave chambers (pair with the `drip` sonar emit) |
| `rg_drip_pool` | bubbly plop | drip anchor over a `~` pool, Still Pool beat |
| `rg_drip_gutter` | bright tick | drip anchor in town / ruin / road stages (eaves, gutters) |
| `rg_splash_step_a`, `_b` | wading footstep (foot 0 / 1) | player or critter step onto a `~` water tile, instead of the material step |
| `rg_bat_squeak` | high squeak | bat critter squeak (Critters `squeak` event, species bat) |
| `rg_bat_flutter` | wing beats | bat flushed from roost / fly-by, Echo Hall |
| `rg_rat_skitter` | claw ticks | rat critter scurry (on flee start, or every few cells of movement) |
| `rg_rat_squeak` | squeak | rat critter squeak / being fed on, Rat Warren |
| `rg_hare_thump` | low thump | hare/rabbit alarm when it flees; carry far (sonar emit, range 3-4) |
| `rg_owl_hoot` | hoo, hoo-hooo | night ambient emitter in woods / ruins / cemetery |
| `rg_wolf_howl` | long howl | distant howl in wild / road stages at night; heat or hunter-alert cue |
| `rg_cricket_loop` | insect bed (loop) | night ambience for meadow, road, farm stages (outdoor bed layer) |
| `rg_wind_loop` | wind gust (loop) | Cave Mouth draft emitter, any open-air bed; scale gain by draft strength |
| `rg_creek_loop` | stream (loop) | positional emitter on creek tiles |
| `rg_fountain_loop` | fountain (loop) | positional emitter at town fountains |
| `rg_hearth_crackle` | fire pops (loop) | inn / farmhouse hearth, layered over `fire_bed` |
| `rg_crow_caw` | caw x2 | crow critter / dawn ambience outdoors, startled flee |
| `rg_sheep_bleat` | bleat | sheep critter in pasture / farm |
| `rg_hen_cluck` | cluck x3 | hen critter in farm yard |
| `rg_coffin_creak` | lid opens + thunk | `Menus.open_coffin` and the title screen "Rise" |
| `rg_soil_chime` | earthy chime | `coffin_buy` success; Grave Soil tally lines on Laid to Rest |
| `rg_upgrade_sting` | rising arpeggio | upgrade tier bought (after the chime, or instead of it) |
| `rg_stage_arrival` | swell + far bell | `TrekUi.show_stage_card` |
| `rg_dawn_bell` | bell tolls | `TrekUi.set_dawn` entering the warning (<= 90 s), repeat at 30 s |
| `rg_dawn_birds` | birdsong | dawn warning layer / "The sun is up" |
| `rg_laid_to_rest` | two low tolls | `Menus.show_laid_to_rest` |

No dog bark was baked (the classic `dog` sound exists).

## stages.json schema (`project/data/rogue/stages.json`)
`{"stages": [row, ...]}`. A row is plain data read by `StageGen.stage_row(id)`; `StageGen.generate(id, seed)` dispatches on `generator` (only `cave` exists).

| Key | Meaning (Hollow value) |
|---|---|
| `id`, `name`, `index`, `generator` | `hollow`, "The Hollow", 1, `cave` |
| `miles` | stage length for the Miles metric (3) |
| `drainMul`, `bloodGain`, `hunterBase`, `watchers` | run tuning read by the trek flow (0.8, 1.0, 0, 0) |
| `preyCount {min,max}` | critters spawned (8-11, never above `caps.critters`) |
| `lights {min,max}` | glow-worm lights (3-12: 4-6 authored or scattered, plus 6 breadcrumbs) |
| `size {w,h}`, `kind`, `floor`, `materials` | map size (<= 64x48), `indoor`, `stone`, `{"#": "roughStone"}` |
| `openFraction {min,max}` | share of non-wall cells (floor, markers, water) in the 62x46 interior (0.30-0.38) |
| `nodes {min,max}`, `spurs {min,max}` | chambers (8-9, 7 of them beat chunks) and blind spurs (2-3) |
| `shelter.pockets.min`, `shelter.restSpots.min` | covered pockets (3) and non-coffin rest spots (2) |
| `shelter.coverFrac`, `shelter.restTarget`, `shelter.maxExtraCrevices` | rule fraction (0.4), design target in cells (30), crevice budget (8) |
| `shelter.safety {kind: 0..1}` | rest-spot safety by kind: coffin 0.9, roost 0.55, crevice 0.7, spur 0.8 (non-coffin kinds get +-0.05 per rest spot from the rng) |
| `caps` | people 0, critters 12, props 60, lights 16, ambient 24 |
| `exit {doorId, toMap, toDoor}` | `mouth` -> `stage:wood` (placeholder until WP8 resolves it) / `cave` |
| `ambient` | `fillerDripsPerRoom [1,2]`, `extraGlowworms [0,2]` |

Cover rule constants: walk speed `Player.DEFAULT_CFG.moveSpeed` = 3.0 cells/s, night length `Night.DEFAULTS.nightSec` = 480 s, so a night's walk is 1440 cells and 0.4 of it (`StageGen.cover_limit`) is 576 BFS cells from any walkable cell to the nearest rest spot (`rest[]`). That is the hard rule `StageGen.analyze` and the tests enforce. The generator also aims at the much tighter `restTarget` (30 cells) by carving crevice alcoves; seeds 1-50 end at <= 38.

### Generated map def (`StageGen.generate`)
A `data/maps.json` map entry (`name` = stage id, `kind`, `floor`, `materials`, `rows`, `doors`, `props`, `zones`, `paths` [], `hides` [], `places`) plus keys `World.from_def` ignores:
- `stage`, `seed`; `start {cell [x,y], angle}` (the `@` cell, facing south); `exit {door, cell, arrival [x,y], toMap}`.
- `beats [{id, cell}]` in order: `coffin_nook, drip_gallery, squeeze, echo_hall, still_pool, dead_end_spurs, rat_warren, cave_mouth`. BFS depth from the start strictly increases along them (spurs excluded).
- `rest [{cell, kind: coffin|roost|crevice|spur, marker: C|S, safety}]`; `pockets [{zone, kind, rest, cell}]` (each zone is an indoor rect in `zones`).
- `ambient [{cell, kind}]` anchors for `core/ambient.gd`; `critters [{species, cell}]`; `lights [{cell, radius, kind}]` (one per glow-worm prop).
- `zones` carry the T60 rooms (`echo_hall` ~2.2 s, `coffin_nook`, `drip_gallery`, `squeeze`, `still_pool`, `rat_warren`, `cave_mouth`; their Sabine inputs are in `data/rogue/acoustics_extra.json`, merged for missing keys only) and the `pocket_*` rects.
- `gen {attempt, loops, spurs, nodes, openFraction, maxRestDist}`.

### Chunks (`project/data/rogue/chunks.json`)
`legend` maps a template char to `{tile, marker?, prop?, anchor?, spawn?, rest?, safety?, door?}`; `order` is the beat order; each chunk has `rows` (strings), `w`, `h`, `ports [[x,y,dir]]` (edge floor cells tunnels attach to), `beat_at`, optional `zones [{name, rect:[x0,y0,x1,y1]}]`, `pockets [{zone, kind, cell_char}]`, `flip` (mirror allowed), `transpose` (squeeze only), `door {id, facing}`, `radius`. Chars: `#` wall, `.` floor, `~` water, `@` start, `C` coffin rest, `R` roost rest (stalactite), `k` coffin prop, `m` stalagmite, `t` stalactite, `d` stalactite + drip anchor, `e` drip anchor, `o` ripple anchor on water, `r` rat, `b` bat, `B` bat under a stalactite, `g` glow-worm, `v` draft anchor, `D` exit door, `?` untouched. A stamped rect is protected from later carving.

**Repeat runs and variants (0.21.8, 0.22.0).** `StageGen.generate(id, seed, brief = false, variants = true)`. `brief` (the trek began with `tutorialDone`, `TrekFlow.brief`, saved as `night.trek.brief`) gives the Hollow without filler chambers, beats within 18 cells. On a brief cave each beat listed in chunks.json `variants` (coffin_nook, drip_gallery, echo_hall, still_pool) uses its authored chunk or its `_b` alternative, 50/50 per beat, picked by `GenCave.variant_pick(stage id, seed, brief)` on its own rng stream; the attempt must also lay a clean breadcrumb trail (`_crumbs_clean`). The first-run cave (brief = false) never varies: the guided night teaches in the authored cave, byte-identical to 0.21.7. A variant keeps its beat id, zone names, pockets and the beat features the tests check. `variants = false` is the 0.21.8-0.21.9 brief cave, used to continue a repeat-run checkpoint saved before 0.22.0 (no `night.trek.variants` key). `def.gen.variants` records the pick (brief caves only).

### Generator pipeline (`core/gen/stage_gen.gd`, `core/gen/gen_cave.gd`)
`StageGen.generate(stage_id, seed) -> Dictionary` is a pure function of its arguments (mulberry32, `StageGen.seed_for(seed, attempt)`); an attempt that breaks a constraint is discarded and attempt+1 runs (typically 2-3 attempts, <= 300 ms, avg ~100 ms for the Hollow). Utilities: `bfs(plan, sources)`, `distance_transform(plan)`, `mst(pts, forced)`, `carve*`, `carve_tunnel`, `carve_ca_blob`, `stamp(plan, chunk, legend, ox, oy, transpose, flip)`, `rows_of(plan)`, `plan_from_def(def)`, `analyze(def, row)`, `validate(def)` (WorldValidate). Hollow: the 7 chunk rects are walked out in beat order (each within 24 cells of the previous, 2-cell gap), 1-2 CA filler chambers, MST of the centres with the chain edges forced, one loop through a filler, tunnels of width 1-2 between chunk ports, 2-3 spurs (a spur end is a hidden `S` rest spot), growth to a 0.32-0.36 target, crevice alcoves until the rest-distance target holds.

## Trek wiring notes (WP13b)
- **Catching:** `RogueMode` feeds `Critters.step(..., sneak)` with sneak = smoothed player speed below `Critters.SNEAK_SPEED`. The player's own ping calls `critters.on_ping` (startle-freeze) instead of `hear()`; shriek, scream, struggle and door noises still call `hear()`. R, right-click and E call `critters.lunge(player_pos)` first, then fall back to `nearest_feedable()`. Tutorial hint: "Creep up, ping to freeze it, R to lunge and drink."
- **Rest spots:** non-coffin rest spots are unknown until the player is within 3 cells (`RogueMode.rest_is_known`, `known_rests`; discovery plays a soft chime and notes the spot for `TrekFlow.note_rest`). While `dawn_warning()` is on, each non-coffin rest spot emits a faint `rest_hum` pulse (range 5, strength 0.18, every ~3 s, at most one live, skipped when the ambient budget is full), so hearing is not discovering.
- **Powers on a trek:** `Game.power_night()` replaces the classic night counter in `Powers.use_power` and the HUD. Classic is unchanged. On a trek Shriek (unlock 1) works from the start; Mist and Still unlock at the first dusk (night 2, any Heat, or a cleared stage) or from stage 1 with the Mist-born effect (`mistBorn`). Hint: "Q shriek, Shift mist, F still. 1/2 answer the day prompt."

## Wayfinding (0.21.6)
Lost for 25 s (50 s second level; x1.5 tutorial off, x2 far_echo, x2 after the Hollow) the cave helps: the cave-mouth draft is panned toward the way out and gets a quiet floor, and "breath" beads ring a few steps ahead along the way out. **V** (Sense, 8 s cooldown) shows an arc toward the way out for 2 s and swells the draft: free in the Hollow, `ceil(4 x drainMul)` blood after it (needs blood >= cost + 5). Details and constants: `AI_HANDOFF.md`, "Changes in 0.21.6".

## Tutorial (guided first night)
`game/tutorial.gd` (`Tutorial.rogue_*`, driven from `Tutorial.step` while `Game.rogue_on()`). It replaces the old passive hint lines (drip, squeeze, dead end, prey, powers, sun, dawn) with a gated sequence of one-line prompts under the HUD. It reads RogueMode / TrekFlow state and writes only `hint_text`: never blocks input, never moves or spawns anything (test: identical sim with it on and off). It does nothing in classic mode.
- **Runs** on the first Long Night run only: the rogue save's `tutorialDone` is false. It ends (and writes `tutorialDone: true`) when every step is done, on **Tab** (every line ends `[Tab: skip]`), or when the run ends. **Settings > Long Night tutorial: On/Off** (`Menus.tutorial_enabled()` / `set_tutorial_enabled(on)`; the check box is named `TutorialToggle`): On clears the flag so the next new run replays it; Off sets it and stops a live one.
- **Steps** (`Tutorial.ROGUE_STEPS`, in order; each waits for the player to do the thing, then the next shows; a step the player has already run past is skipped): `wake` ("The lid creaks. So do your knees. You cannot see. Listen.", done by the first drip), `ping` (Click or Space; done by a ping, including one made during `wake`), `rings` (what rings and echoes mean, timed), `sense_intro` (V: sense the way, timed, once; skipped when past the gallery or already sensed), `drips` (done on reaching the drip gallery), `squeeze` (ping to steer: ping within 7 cells of the squeeze), `hall` (big echo, bats are food, timed), `feed` (creep, ping to freeze, R to lunge and drink: done by feeding), `vial` (blood meter, only after a feed), `pool` (water blocks you, not sound: ping near the pool), `dead_end` (shown at a spur or spur rest spot), `mouth` (arrival at the cave mouth, "Outside, the sun can find you"), `powers` (Q / Shift / F). Two interrupt steps jump the queue: `dawn` (dawn warning: any roof is safe, rest spots hum) and `choice` (day prompt: E sleeps at a rest spot, 1 waits it out, both add Heat; shown over the frozen prompt). Beats reached come from the player's cell (within 4.5 cells of a beat, or at least as deep as it by BFS from the start); leaving the Hollow marks all cave steps past.
- **Resume**: `continue_trek` begins with `fresh = false`: `wake`, `ping`, `rings` are done and the rest follows from the position (a checkpoint in the nook starts at `drips`). Starting a new run while the flag is false replays from step 1.
- **Opening** (0.21.9): for the first `Tutorial.OPEN_HOLD` (3.2 s) after the guided night begins no line shows and the step clock stands still, so the stage card has the screen to itself.
- **Free revive** (0.21.9): while the guided night is live, the first **withering** death in the Hollow takes the second-coffin path for free (`TrekFlow.guided` / `guided_revived`, card "Back in the box"); a bought Second Coffin and `deaths_avoided` are untouched, nothing is paid or counted. Sun, stakes and holy ground keep their rules. Saved as `night.trek.guidedRevive` once spent; Tab ends the offer with the tutorial.
- **Death screen**: when the run ends with the tutorial still live (not skipped) the result carries `tutorial: true` and Laid to Rest adds two lines (`TrekUi.tutorial_rest_lines()`) explaining Grave Soil and The Coffin; the run end then marks the tutorial done, so they show once.
- **Save**: `tutorialDone` is an additive, optional key (`SaveCodec.ROGUE_OPTIONAL_KEYS`; `ROGUE_KEYS` and `ROGUE_STAT_KEYS` are unchanged, a present value must be a bool). `TrekMeta.create()` writes `false`; `TrekMeta.sanitize` of an older save lacking it gives `true` when `stats.treks > 0` (a veteran) and `false` otherwise, and repairs a non-bool. Tests: `tests/flow/test_rogue_tutorial.gd`.

