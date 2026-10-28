# The Hollow: three-pass improvement log

The Hollow is the first stage of The Long Night and its tutorial: the first playthrough has to teach (echolocation, drips, the squeeze,
feeding, the sun), and every later run has to get out of the way. Three sequential passes improve it, each one handing off to the next:

| Pass | Version | Scope |
|------|---------|-------|
| 1 | 0.21.8 | Calmer opening, ping step bug, quirky moments (cards only), shorter cave on repeat runs |
| 2 | 0.21.9 | Visual noise (stalactite occluding fill, far-wall strata thinning, strike vibration), a free first-run revive on the guided night |
| 3 | 0.22.0 | Second chunk variant per beat for layout variety, final review |

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
