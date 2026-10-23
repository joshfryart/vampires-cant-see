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
