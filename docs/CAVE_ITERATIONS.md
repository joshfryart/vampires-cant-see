# The Hollow: three-pass improvement log

The Hollow is the first stage of The Long Night and its tutorial: the first playthrough has to teach (echolocation, drips, the squeeze,
feeding, the sun), and every later run has to get out of the way. Three sequential passes improve it, each one handing off to the next:

| Version | What contributed | Commit |
|---------|------------------|--------|
| 0.21.8 (pass 1) | Sense hint held until the tutorial's V line; a ping during the waking line counts for the ping step ("Click or Space"); dry waking line, echo-hall word and complaining-rat cards; brief repeat-run Hollow (no filler chambers, beats within 18 cells) | c70008b |
| 0.21.9 (pass 2) | Stage card alone for 3.2 s before the first guided line; one free revive from withering on the guided night; stalactites get an opaque occluding body; far rock strata and vault bedding thin with distance; calmer ink wall shiver | b27352f |
| 0.22.0 (pass 3) | Second chunk for coffin_nook, drip_gallery, echo_hall and still_pool on repeat runs (per seed, 50/50 per beat), strict breadcrumb acceptance on those caves, old repeat-run checkpoints keep their cave; scenarios run on in-memory saves; final review and docs | the `0.22.0:` commit (`git log --grep "^0.22.0"`) |
| 0.22.1 (polish) | Second chunk for the squeeze, rat warren and cave mouth too (variant level 2; 0.22.0 checkpoints stay at level 1) | |

Rules all passes keep: classic / parity code paths and tests stay untouched; the first-run Hollow layout stays a pure function of
(stage id, seed) and only changes on purpose; tutorial lines fit `Tutorial.MAX_TEXT` (76); every pass ends on a green full suite.

## 0.21.8 (pass 1)

### Changes

1. **Calmer opening.** At t = 0 the stage card, the coffin creak, the waking line and the pulsing Sense HUD hint all used to start
   together. The Sense hint is now held on the guided night: rested (no pulse, not bright) with its clock (`RogueMode.hint_t`) stopped
   until the tutorial actually shows its V line (`sense_intro`, or the lost-player `sense` reminder). `RogueMode.sense_hint_held()`.
   Repeat runs, a Tab-skipped tutorial and continued runs behave as in 0.21.7 (hint up from the first frame).
2. **Ping step bug.** The `ping` gate only counted pings made after the step began, so a player who pinged while "wake" was showing was
   asked to ping again. `Tutorial._past("ping")` is now "any ping since `rogue_begin`" (`_ping0`), so the step is marked done and the
   rings line follows. Text: "Click or Space to ping. Listen to what comes back." (left click pings as well as Space).
3. **Quirky moments, cards and hint text only (no new systems):**
   - The coffin creak gets a dry waking line: "The lid creaks. So do your knees. You cannot see. Listen." (the guided night's step 1, so
     no extra element joins the busy opening).
   - The echo hall returns a word: the first ping within 7 cells of the `echo_hall` beat on the guided night shows the card
     "...hello ...ello ...llo" / "You only clicked. The hall is being polite." It starts part-way into `Game.CARD_LEN` (about 1.8 s on
     screen), never replaces another card, and fires once a trek. Repeat runs stay quiet.
   - The first rat drunk each trek complains: the +blood card's subtitle reads "Rat. It wishes to complain." instead of "Rat" (the card
     is shown anyway, so it costs repeat runs nothing).
4. **Brief Hollow on repeat runs.** `StageGen.generate(stage_id, seed, brief := false)`. With brief = true the cave generator places the
   7 beat chunks only (no filler chambers, so no filler loop, filler drips or filler rats: a pure beat chain) and keeps each beat within
   `BRIEF_REACH` = 18 cells of the previous one instead of `CHAIN_REACH` = 24. Fillers alone barely shortened the walk (they hang off the
   main path and the growth step refills the open fraction), so the tighter reach is what makes it shorter: mean coffin-to-exit walk
   151 vs 179 cells over 40 seeds (149 vs 176 over the 25 test seeds), and generation is faster (64 vs 96 ms). Reach 16 fails every seed.
   - brief = false is byte-identical to 0.21.7 (the rng draws happen in the same order; JSON hashes of seeds 1..60 compared before and
     after). Only a brief def carries `gen.brief` / `gen.fillers`.
   - The flag is an explicit argument. `TrekFlow.begin` sets `TrekFlow.brief` from the meta's `tutorialDone`; it is saved as the optional
     `night.trek.brief` (written only when true) and read back by `continue_from`, so a continue regenerates the same layout even if the
     tutorial was skipped mid-run or turned back on in Settings. Saves without the key load the full cave.
   - `StageGen.analyze` now reports `path_len` (start to exit arrival) and `brief`, and rejects a brief def with fillers or loops.
   - Wood / moor / road / inn ignore the flag.

### Files touched

- `project/game/tutorial.gd` (ping `_past`, `_ping0`, wake and ping texts)
- `project/game/rogue_mode.gd` (`sense_hint_held`, held `hint_t`, `_echo_word`, rat quip, constants `RAT_QUIP`, `ECHO_WORD*`)
- `project/core/gen/stage_gen.gd` (`generate` brief argument, `analyze` path_len / brief check)
- `project/core/gen/gen_cave.gd` (brief: no fillers, `CHAIN_REACH` / `BRIEF_REACH` threaded through `_layout` / `_place`)
- `project/game/trek_flow.gd` (`brief` field, begin / continue / snapshot)
- `project/project.godot`, `project/tests/flow/test_rogue_mode.gd` (version 0.21.8)
- `AI_HANDOFF.md`, `TODO.md`, this file

### Tests

- `tests/flow/test_rogue_tutorial.gd`: `test_a_ping_during_the_waking_line_counts`, `test_a_ping_before_the_step_still_needs_one_when_none_was_made`,
  `test_ping_text_names_click_and_space`, `test_brief_cave_on_repeat_runs_only` (first run full, skip keeps the layout, next trek brief,
  checkpoint key, continue after re-enabling the tutorial, old save without the key), `test_echo_hall_says_a_word_once_on_the_guided_night`,
  `test_the_first_rat_complains`. Changed: the waking-line and "Space" checks; `test_tutorial_does_not_touch_the_sim` now starts both treks
  on the first-run layout and turns the guided night off afterwards (the flag now also picks the layout, which is a sim difference by design).
- `tests/flow/test_rogue_sense.gd`: `test_guided_night_holds_the_hint_until_the_v_line`, `test_hint_hold_ends_when_the_tutorial_is_skipped_or_resumed`.
  The two older hint tests now run on a repeat run (`_veteran`), where the hint still starts at t = 0.
- `tests/unit/test_stage_gen.gd`: `test_brief_is_a_pure_beat_chain` (25 seeds: analyze, validate, no fillers or loops, beat order, crumbs,
  prey, rest reach), `test_brief_is_shorter_and_first_run_untouched` (mean walk under 92% of the first run, determinism, brief = false
  equals the first-run def, wood ignores the flag).

Full suite at 0.21.8: {"checks":1250376,"failed":0,"failures":[],"tests":395}.

### Left for later / needs a human playtest

- Whether the held Sense hint is still noticed: on the guided night it now first lights up with the `sense_intro` line (about 10-15 s in,
  after the first drip, the ping and the rings). Needs a person to confirm.
- The wake line was not delayed past the 4 s stage card; the card and the line still overlap (the line is at the bottom, the card in
  the middle). Delaying it would shift every tutorial timing test; left as is unless playtest says otherwise.
- Tone of the three quirk lines (and whether "Rat. It wishes to complain." on every trek's first rat gets old).
- The brief cave keeps the full tutorial beats (squeeze, hall, pool, warren) because the beats are also the level; only their spacing and
  the filler side rooms go. Brief caves have about one rat fewer (filler rats). Whether repeat runs feel fast enough needs play.
- `BRIEF_REACH` 18 is close to the feasibility edge (16 fails every seed). Pass 3's second chunk variants must be checked against it;
  larger variants may need the reach raised to 20 (mean walk 157 cells) for the brief form.
- Pass 2: the free first-run revive should key off the guided night (`g.tut.rogue_active` / `tutorialDone`), not `TrekFlow.brief`.

## 0.21.9 (pass 2)

### Changes

1. **Opening order (pass-1 concern).** The waking line no longer appears under the stage card. `Tutorial.OPEN_HOLD` = 3.2 s (the 4 s card
   starts its 0.8 s fade there): for that long after `rogue_begin` no guided line shows and the step clock (`rogue_age`) stands still, so the
   card is alone, then the line fades in as the card fades out, and "wake" still gets its full 2.5 s minimum on screen (it then waits for a
   drip, which has usually come during the hold). Steps keep being chosen during the hold (so a ping during it still counts for the ping
   step); only display and step age wait. The same hold applies to a continued run (its stage card shows too). `Tutorial.opening_held()`.
   Net effect on the guided night: every step is about 3.2 s later than in 0.21.8; the Sense HUD hint, held until the V line, follows suit.
2. **Free first-night revive.** `TrekFlow.guided` (RogueMode `_sync_guided()` copies `Tutorial.rogue_active` before every trek step,
   `sleep_at_rest` and finished wait: TrekFlow still never reads the tutorial) and `TrekFlow.guided_revived`. `_die` checks
   `guided_revive_ready(why)` first: guided, unused, cause "withered", stage "hollow". It then takes the existing second-coffin path
   (refactored into `_revive`: `REVIVE_BLOOD` 30, wither timer and stake cooldown reset, back at `last_rest`, the day prompt again if the
   sun is up). The `revived` event carries `free: true`; RogueMode shows "Back in the box" / "The first night is on the house. Next time,
   drink something." instead of the Second Coffin card.
   - Tied to the guided night, not to `TrekFlow.brief` / `tutorialDone` at trek start: Tab ends it with the tutorial; turning the tutorial
     back on in Settings gives the next guided run its own one revive (that is a replay of the guided night, so it is allowed).
   - Once only, saved: optional `night.trek.guidedRevive` (written only once spent, so unused checkpoints are unchanged); `continue_from`
     reads it, so quit-and-continue cannot reuse it. Saves without the key: unused.
   - No exploit: it does not touch `deaths_avoided` (a bought Second Coffin is still there afterwards: free revive, then coffin, then death),
     pays no Soil and records no stats (only `end_run` does that, and the revive is not a run end). The blood it gives is the coffin's 30.
   - Death rules chosen: **withering only**. The sun is announced (dawn warning, bell, the tutorial's `dawn` and `mouth` lines, the day
     prompt) and is the lesson the night ends on; stakes and holy ground cannot happen in the Hollow on night 1 (`hunterBase` 0, Heat 0,
     no holy cells). Withering while lost is the one failure the cave cannot pre-teach. Past the Hollow the offer is gone even if the
     tutorial is still live.
3. **Visual noise (Hollow ink only; classic style-0 walls and the classic maps' meshes are unchanged).**
   - (a) Stalactites: `render/shaders/vault_occluder.gdshader`, an opaque, depth-writing black body drawn with the same cone mesh as the
     additive ink pass (a sixth mesh instance in the Hollow, `Game.vault_occ_mat`), pushed 0.012 cells inside along the cone normals so it
     never fights the ink; drip-bead vertices collapse onto a vertical line (no body). Walls, floor rings and the cone's own far-side lines
     behind a cone are now hidden: it reads as solid rock with ping-lit near edges. Checked side by side in a cave_tour frame (echo hall,
     frame 235) with the body on and off.
   - (b) Far strata: in `sonar_wall.gdshader` `rock_detail`, the minor courses (all but 0, 3, 6) fade out between `STRATA_THIN_NEAR` 2.5
     and `STRATA_THIN_FAR` 4 cells (with the existing odd-course cut at 4.2, a far wall keeps courses 0 and 6), and the strata alpha fade
     starts at 4.5 cells instead of 5. `sonar_vault.gdshader`: alternate bedding courses fade between 2.5 and 4 cells, alternate boss
     contour levels between 4 and 6.
   - (c) Strike vibration: for ink styles (style > 0) the shiver lasts `VIB_DUR_INK` 0.5 s instead of 0.9 (and eases out over that span),
     swings `VIB_AMP_INK` 0.6 as far, and draws at alpha x`VIB_A_INK` 0.3 instead of x0.45. The rock shiver reuses `rock_detail` at depth
     >= 4.3, so with (b) only the two bold courses quiver. Classic style 0 keeps `VIB_DUR`, its amplitude and its five lines.

### Files touched

- `project/game/tutorial.gd` (`OPEN_HOLD`, `_open_t`, `opening_held`, held display and step clock)
- `project/game/trek_flow.gd` (`guided`, `guided_revived`, `GUIDED_REVIVE_STAGE`, `guided_revive_ready`, `_revive`, save key)
- `project/game/rogue_mode.gd` (`_sync_guided`, free revive card, `GUIDED_REVIVE_TITLE` / `_SUB`)
- `project/game/game.gd` (`vault_occ_mat`, the stalactite body instance)
- `project/render/shaders/vault_occluder.gdshader` (new), `sonar_wall.gdshader`, `sonar_vault.gdshader`
- `project/project.godot`, `project/tests/flow/test_rogue_mode.gd` (version 0.21.9; two death tests mark the free revive spent)
- `AI_HANDOFF.md`, `TODO.md`, `docs/ROGUELIKE.md`, this file

### Tests

- `tests/flow/test_rogue_tutorial.gd`: `test_opening_holds_the_line_for_the_stage_card` (card up and line held at 0.3 s and just before
  3.2 s, line after, "wake" keeps its minimum, the same on continue), `test_guided_night_forgives_the_first_withering` (alive, card,
  back at the last rest, blood, no Soil or trek recorded, still guided, spent after quit and continue, second withering ends the run),
  `test_no_free_revive_once_the_guided_night_is_skipped`. Changed: step 1 and the skip test wait out the hold; the death-explanation test
  withers twice.
- `tests/flow/test_trek_flow.gd`: `test_guided_revive_withering_once` (event `free`, state, position, blood, `deaths_avoided` 0, meta stats
  and Soil unchanged, second withering is one counted death), `test_guided_revive_rules` (not guided, sun, stake / holy, past the Hollow,
  with a bought Second Coffin), `test_guided_revive_saved_with_the_checkpoint` (no key until spent, saved, restored, older save).
- `tests/unit/test_vault_mesh.gd`: the Hollow has 6 instances; the body shares the cone mesh, is opaque and depth-writing, the ink stays
  additive. `tests/unit/test_style_switch.gd`: text checks for the ink-only vibration constants, the classic `VIB_DUR` and five lines, the
  strata `minor_k`, and the vault thinning. No mesh hashes changed (the cone mesh itself is unchanged), so nothing was re-pinned.

### Left for later / needs a human playtest

- Whether 3.2 s of silence on the HUD line at the very start feels deliberate or slow (the coffin creak and the card fill it).
- The revive card's tone, and whether a first-timer understands they were saved once (the card says "first night"; the Laid to Rest
  explanation still comes on the real death).
- The stalactite body was checked in a single cave_tour frame; whether the solid cones read better across the whole cave, and whether
  0.012 cells of inset ever shows a dark rim at grazing angles, needs eyes. The far-strata thinning and the calmer shiver were looked at
  only in passing (cave_tour frames 45, 162, 300): they need a side-by-side judgement in play.
- Note for pass 3: windowed scenarios (cave_tour, style_tour) run on the real `user://` saves, and `new_trek` removes the trek checkpoint.
  Back up `%APPDATA%\Godot\app_userdata\Vampires Cant See` first and restore it afterwards (pass 2 restored `vcs_trek.json`).
- Deliberately not done: no change to the Hollow layout, chunks or generator (pass 3), no change to the HUD Sense hint, the hold is not
  applied to later stage cards (only the guided night's opening).

## 0.22.0 (pass 3)

### Changes

1. **Chunk variants, repeat runs only.** `chunks.json` gets a `variants` map and four second chunks, each keeping its beat id, zone
   names, pockets and every feature the beat tests check:
   - `coffin_nook_b` (10x8): coffin against the north wall with the coffin rest marker in the far corner, a stub pillar, ports south and
     east (the authored nook: south and west). The start stays under the coffin with the waking drip two cells ahead.
   - `drip_gallery_b` (13x9): a bent gallery, in from the west and out through the north (the authored one runs straight west-east),
     three drips, two stalagmites.
   - `echo_hall_b` (19x15): a wider, lower oval with off-centre north and south ports, three lone pillars near the middle instead of
     scattered, ten stalagmites in four clusters, the roost on the north-east ledge. 144 of the 149 cells within radius 7 are open.
   - `still_pool_b` (15x9): the pool reaches the north wall, so the direct line between the west and east ports is water and the way round
     is the south shore (the authored pool is a lake with a walkway all round). Two ripples, two shore rats, two glow-worms.

   `GenCave.variant_pick(stage_id, seed, brief)` picks, per beat, the authored chunk or its alternative (50/50, `VARIANT_CHANCE`) on its
   own rng stream (`StageGen.seed_for(seed ^ id.hash(), VARIANT_SALT)`), so the layout rng is never shifted; `with_variants` swaps the
   chunk in under the beat's name. The pick is stored as `def.gen.variants` (brief caves only). If a pick could never fit, the authored
   chunks are used (not seen in 300 seeds; the tests assert every tested seed used its own pick).
2. **Decision: variants apply to repeat runs (brief) only.** The guided first night always teaches in the authored cave: `variant_pick`
   returns `{}` for brief = false and the first-run code path is unchanged. First-run JSON hashes of seeds 1..60 compared before and after:
   identical; three are pinned in `test_stage_gen.gd` (`FIRST_RUN_HASH`). A guided night continued on a repeat-run checkpoint after the
   tutorial was turned back on in Settings can meet variants; the tutorial keys off beat ids and positions, so it still works there.
3. **Strict breadcrumbs on the new caves.** The breadcrumb pass only *prefers* a 2-wide spot past the previous beat. Over 300 seeds about
   2% of caves miss (first run: seeds 140, 146, 163, 255, 267, 274 have a crumb in a 1-wide pinch or not deeper than the one before;
   variant-free brief: 6 of 300; with variants before this fix: 8 of 300, mostly `drip_gallery_b`, whose north port sits near a corner so
   one side of the 2-wide funnel falls inside the protected chunk rect). Brief caves with variants now reject such an attempt
   (`_crumbs_clean`, fail key `r13`): 0 of 300 bad. The first-run generator is deliberately not changed (byte-identity, saved checkpoints).
4. **Old checkpoints keep their cave.** A trek checkpoint stores no layout; `continue_from` regenerates it from the seed. A repeat-run
   checkpoint saved by 0.21.8-0.21.9 would have reopened in a different cave (player in rock, wrong eaten-critter indices). New:
   `StageGen.generate(id, seed, brief, variants = true)`, `TrekFlow.variants` (true for new treks), saved as `night.trek.variants`
   (written only on brief treks); a brief checkpoint without the key continues with variants = false, which is the 0.21.9 brief cave byte
   for byte (all 60 brief hashes compared; two pinned, `BRIEF_0219_HASH`). First-run checkpoints are unaffected.
5. **Scenarios no longer touch user:// saves.** `Game.boot` gives any `--scenario=` run an in-memory save store
   (`SaveCodec.MemoryStorage`) when no test storage is set. Before, `cave_tour` / `sense_check` (`new_trek` removes the checkpoint) and
   `run_start` / `bot_play` / `vessel_view` / `warm_halo` (`begin_run` writes the classic run save) wrote to the player's saves; `perf_play`
   already swapped in a memory store; `style_tour` only adds worlds. Settings are still read; `seen.json` (classic hint list) and
   `flags.json` are still persisted by scenarios as before. Checked headless: `cave_tour` for 90 frames left every `user://*.json`
   byte-identical (the trek checkpoint included). Consequence: `cave_tour` now always tours the first-run layout on a guided night
   (fresh meta), whatever the real rogue save says.
6. **Review of passes 1 and 2 (c70008b, b27352f).** Re-read the diffs of `tutorial.gd`, `rogue_mode.gd`, `trek_flow.gd`, `gen_cave.gd`,
   `stage_gen.gd`, `game.gd`. No functional bug found in: the ping step (`_ping0` set in `rogue_begin`), the Sense-hint hold (released when
   `sense_intro` is shown or skipped through `_past`, or by the `sense` reminder; continued runs mark `sense_intro` done), the opening hold
   (`_open_t` reset per `rogue_begin`; it holds the line display and step clock only, steps are still chosen), the free revive
   (`_sync_guided` before step / sleep / finished wait; withering only, Hollow only, saved once spent, a bought Second Coffin untouched,
   no Soil or stats), the brief flag (fixed at `begin`, saved, older saves full). Fixed: the save-compatibility gap above (this pass's
   variants would have opened it) and a stale `docs/ROGUELIKE.md` tutorial line (the old "You rise" / "Space" texts).

### Numbers (300 seeds, headless)

| Cave | Mean coffin-to-exit walk | Mean / max attempts | Seeds with a weak breadcrumb |
|------|--------------------------|---------------------|------------------------------|
| First run (unchanged) | 174.2 cells | 3.16 / 12 | 6 (left as is) |
| Repeat run with variants | 158.4 cells | 2.83 / 15 | 0 |

The variant caves walk a little longer than the 0.21.8 brief cave (about 151 cells over 40 seeds then) because `echo_hall_b` and
`still_pool_b` are larger and the pool forces its detour; still clearly shorter than the first run. `BRIEF_REACH` 18 was enough for every
variant (no seed needed the authored fallback), so it was not raised.

### ASCII samples (`cave_ascii.gd --brief`)

Seed 12, repeat run, all four variants (columns 3-55, rows 3-44). 1 nook, 2 bent gallery, 3 squeeze, 4 oval hall, 5 pool with the south
detour, 6 warren, 7 mouth, 8 spur beat; X exit, * crumb, M spur mouth, A dead-air drip, a ambient anchor, s rest spot, B bat, R rat:

```
######X##########################################s###
#####...#########################################.###
####.....###########.####################.........###
####.....########..R....#################M###########
#####...########.....#...################.###########
######.########..##.......#..#...#~~~~~#.A.##########
####..7..###..#.........R.#.....~~~~a~~~....#########
###.......##....R...6......*.#..~~~~~~~~~..##########
##.........#*.#.......##..#..#..~~~~~a~~~..##########
#.............#....#...a..####...~~~~~~~...##########
##.........#..##....R....######.R...5...R.###########
###.......##.####.......########.........############
####.....###s#######.################.###############
######.########################..............########
##########################....#...............#######
######################.........................######
######################................*.........#####
####s....#############.........................######
####...1...##########...........#####.###############
#####.......##########..........####.........########
####...a.....8.A.##s........*...###..B.......B.######
####.#......####.#####..........##..............s####
#####......####..##########.#...#........#........###
########.####...###########a#...#.a...............###
####........#.#############.#...#......#..........###
####.....*..#s#########.....#............4.........##
###.........###########.#####...#.........#.......###
###.........###########.#####...#..............a..###
####...###.############.....#...#..............a..###
##########...##############3#...##..B............####
#########..a..#############.##..###.............#####
#########.........##..#.....########...........######
#########....2..a.....#.#####################.#######
#########..a.......#.*#.#############################
###########.......##..#.....#s#######################
############.....###..#####.#.#######################
####################..#####.#..######################
################.................####################
###############...................###################
###############...................###################
###############...............#.#####################
################...............######################
```

Seed 7, repeat run, `still_pool_b` (mirrored): the west and east ports open at the water's north end, the way round is the south shore
past the beat (5) and both shore rats:

```
###############.####
####...#~~~~~#...#..
###...~~~~a~~~......
####..~~~~~~~~~..#.*
####..~~~~~a~~~..#..
####...~~~~~~~...#..
#####.R...5...R.##..
######.........###..
```

`cave_ascii.gd` over brief seeds 1-12 printed one kind of warning only: "dead_end_spurs grows out of the Coffin Nook" (seeds 10 and 12;
seed 10 uses no variant). It matters for the tutorial's dead-end hint, and the tutorial is off on repeat runs, so it was left.

### Files touched

- `project/data/rogue/chunks.json` (`variants`, four `_b` chunks)
- `project/core/gen/gen_cave.gd` (`variant_pick`, `with_variants`, `_attempts`, `variants` / `strict` arguments, `_crumbs_clean`)
- `project/core/gen/stage_gen.gd` (`generate(..., variants)`)
- `project/game/trek_flow.gd` (`variants`, save key `variants`, `_load_stage`)
- `project/game/game.gd` (scenario runs on a memory save store)
- `project/tests/tools/cave_ascii.gd` (`--brief`, prints the pick), `project/tests/scenarios/cave_tour.gd`, `sense_check.gd` (comments)
- `project/project.godot`, `project/tests/flow/test_rogue_mode.gd` (version 0.22.0)
- `AI_HANDOFF.md`, `TODO.md`, `docs/ROGUELIKE.md`, this file

### Tests

`tests/unit/test_stage_gen.gd`: `test_shelter`, `test_beat_features` and `test_wayfinding_crumbs_and_spur_tells` now call per-def helpers
(`_shelter`, `_beat_features`, `_wayfinding`) so the variant caves get the same checks. New: `test_variant_chunks_are_well_formed` (beat id,
zone names, pockets, marker counts, ports on the rim and reaching the beat cell), `test_variants_only_on_repeat_runs` (no pick and no key on
the first run, pinned first-run hashes, pure pick, every seed used its own pick, every chunk appears, determinism, distinct maps),
`test_variant_caves_pass_every_check` (60 brief seeds: analyze, validate, validate_all, beat order, the squeeze cannot be bypassed, shelter,
beat features, wayfinding), `test_variant_caves_lead_to_the_exit` (12 repeat-run treks: `next_toward_exit` from the start and from every beat
reaches the exit), `test_variant_free_brief_cave_for_old_checkpoints` (pinned 0.21.9 brief hashes, the save key, continue with and without
it, first run untouched). Wider sweep: `-- --filter=test_stage_gen --variant-seeds=300` (green, 76026 checks).

Full suite at 0.22.0: {"checks":1260937,"failed":0,"failures":[],"tests":406}.

### Needs a human playtest (all three passes)

- First run (guided night): is the held Sense hint noticed when it lights up with the V line; does the 3.2 s opening hold feel deliberate;
  tone of the waking line, the echo-hall word, the complaining rat and the "Back in the box" revive card; does a first-timer understand
  they were saved once.
- Look: the stalactites' solid bodies across a whole cave (any dark rim at grazing angles), the far-strata thinning and the calmer shiver.
- Repeat runs (Settings > Long Night tutorial Off, then several new runs): does the brief cave feel fast enough; do the variants feel
  different (the oval hall's echo and pillars, the pool detour, the bent gallery, the second nook); is any variant confusing without the
  tutorial.
- Scenarios: `cave_tour` now shows the first-run layout on a guided night; check its frames still show what the tour is for.

### Left for later

- The ~2% of first-run seeds with a weak breadcrumb (listed above) keep it: fixing them changes those first-run caves and their saved
  checkpoints. A later pass can turn `_crumbs_clean` on for the first run behind a save key, as `variants` does for repeat runs.
- More variants (squeeze, rat warren, cave mouth) are cheap to add the same way: a `_b` chunk plus an entry in `variants`; the tests pick
  them up (the well-formedness test covers every listed variant).
- Scenarios still write `seen.json` (classic hint list) through `Tutorial`; not touched (it would change which classic hints scenarios show).
