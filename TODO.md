# TODO (0.21.1, The Long Night)

Changes in 0.21.8: Hollow pass 1 (Sense hint held until the tutorial's V line, a ping during the waking line counts, echo-hall word and complaining rat cards, brief repeat-run Hollow without filler chambers), see `AI_HANDOFF.md`, "Changes in 0.21.8" and `docs/CAVE_ITERATIONS.md`. Still to do: a person plays a first and a repeat run.

Changes in 0.21.7: Sense discoverability (tutorial `sense_intro` step after the rings, brighter pulsing HUD hint under the dawn line, How to play and pause list V, windowed `sense_check` scenario that proved V works), see `AI_HANDOFF.md`, "Changes in 0.21.7". Still to do: a person confirms the hint is noticed in play.

Changes in 0.21.6: Hollow wayfinding (panned draft, breath beads, assist ladder, Sense on V: free in the cave, 4+ blood after), see `AI_HANDOFF.md`, "Changes in 0.21.6". Still to do: a person judges the draft pan, the Sense cue and the thresholds (25 / 50 s) under real play. Full suite green at 0.21.6 with the cave wayfinding layout: {"checks":1249720,"failed":0,"failures":[],"tests":378}.

Changes in 0.21.5 (S3c): the Hollow ceiling is a real rock-vault mesh (`render/vault_mesh.gd`, `sonar_vault.gdshader`), see `AI_HANDOFF.md`, "Changes in 0.21.5". Still to do: a person judges it under real play (cone shapes, line density); other stages keep canvas ceilings.

Changes in 0.21.4 (S3b): denser rock strata, quieter vibration, no brick/plank grid floors in ink worlds, per-chamber cave ceiling plus sky / canopy / rafters (see `AI_HANDOFF.md`, "Changes in 0.21.4"). Still to do: a person judges the ceilings and strata density under real play; ceilings are a sparse band around the ping front (consider denser marks or a mesh vault).

Changes in 0.21.3 (S3): the ink wall style is on for the five trek stages (see `AI_HANDOFF.md`, "Changes in 0.21.3"). Still to do: a person judges the cave strata and the other materials under real play, crease lines, a separate gibbet look, a map-seed uniform for the strata dip.

Changes in 0.21.2 (WP13b): The Old Road (`road`) and Crossroads Inn (`inn`) are generated (`core/gen/gen_road.gd`), the trek runs hollow -> wood -> moor -> road -> inn and ends with "To be continued..." after the inn (see `AI_HANDOFF.md`, "Changes in 0.21.2"). Still to do for them: a person plays both (shrine holy ground, watchers, patrons and schedules, cellar risk), sounds for the `cart` / `bell` / `singing` ambient kinds, a horse prop, then WP13c (Hamlet and Farms onwards).

Changes in 0.21.1 (WP13a): Bramble Wood (`wood`) and Gallows Moor (`moor`) are generated (`core/gen/gen_wild.gd`, rows in `data/rogue/stages.json`), the trek runs hollow -> wood -> moor and ends with "To be continued..." after the moor (see `AI_HANDOFF.md`, "Changes in 0.21.1"). Still to do for them: a person plays both (thicket density, deer / wolf balance, pockets, the wind bed at the exit, owl / creek / cricket sounds), then WP13b (The Old Road onwards).

Done in 0.21.0 (WP9): the Hollow is playable end to end (see `AI_HANDOFF.md`, "Changes in 0.21.0"). Next, in order:
1. A person plays the Hollow: balance (drain 0.8, bat / rat catchability, Heat and hunters, wait-out-the-day length), listen to the `rg_*` sounds, check critter glyphs in play, mouse capture around the day prompt.
2. WP13b: the next stage generator (The Old Road: carts, shrine bell, travellers, first hunter); until it exists the moor exit ends the trek with "To be continued...". `TrekFlow.GENERATORS`, `StageGen.generate` (dispatch), `data/rogue/stages.json`; `core/gen/gen_wild.gd` is the template for open stages (pockets + open-air rule).
3. Trek powers unlock table (shriek / still / mist are tied to the classic night number), rest-spot hum at dawn, hidden rest spots.
4. Cut-line items (docs/ROGUELIKE.md): thrall, bat form, second coffin stage hooks, keep and nobility, holy ground, waystones.

---

# TODO (handoff snapshot, 2026-10-22)

Session goal: (1) restore everything missing in the Godot port compared with `html-version/`, (2) steady 60 fps, (3) docs and version bump.
Read `AI_HANDOFF.md` first (rules, commands, "NOT included" table, "Changes in 0.20.2"). Never edit `html-version/`.

## Done (committed on `main`, not pushed)

| Commit | What |
|---|---|
| 789f495 | Profiling tools: `tests/scenarios/perf_play.gd` (real-time, windowed), `tests/tools/fig_bench.gd`, `tests/tools/pf.gd` |
| 9fce72b | Perf: grid fast paths for sonar rays, depth columns, line of sight; row-cached pulse textures; threaded audio preload. Ping 17.9 -> 2.7 ms, footstep pulse 1.5 -> 0.15 ms, depth columns 1.2 -> 0.6 ms, strongest_echo 6.4 -> 0.9 ms |
| 227f64a | Perf: volumetric figure built once and replayed per sweep strip, fast clipping, adaptive curve flattening, single triangulation. Swept figure 40-80 -> 6 ms, lit 6.5 -> 3.9 ms |
| e83ddbc | Perf: JS adaptive quality governor and fxCap ported (`render/governor.gd`); depth buffer, HUD and title caching. EchoView 2.3 -> 1.3 ms, HUD 0.86 -> 0.26 ms |
| 1c2c17b | Gameplay parity: bark distance/occlusion muffling and voice stops, sonarCooldown fx (quick_call, quick_ping, g_quick were dead), feedToggle release, pending gifts saved, save on window close, Esc handling, gates, enter_map resets, transitionMs |
| 35aaf2a | UI parity: listening headcount "Voices inside: N", large text, Notice overlay, F3 view/sched/governor lines, menu keyboard focus and Esc, Essence now row, version label, dev panel tools, `--sys=`/`--tun=` |
| f682c69 | Render parity: wall/floor shaders follow quality, line boil, material detail, reduced motion, effects level (stone hatch, wood dashes, window glint, line taper, soft front); `EchoLayer.warm_up()` at boot |
| 87510fb | Render parity: map-transition wipe (`HudDraw.draw_wipe`), directional warm edge glow (`render/edge_glow.gd`) |

Full suite after 35aaf2a: 106 tests, 1,108,495 checks, 0 failures. Not re-run after f682c69/87510fb (their workers ran filters gameplay, flow, parity_gaps, hud, world, edge_glow: all pass).
Listening at windows: verified wired end to end (E key, gating, slow walk, muffled speech, subtitles, tutorial hint); only the headcount was missing (now restored).

## Working tree status

Nothing pending: docs and version 0.20.2 are committed (ec67654). Perf round 2 (cached per-echo figure replay) was tried, tests passed, but crowd p95 was not reliably better (see AI_HANDOFF perf notes); render edits and its scratch tools were reverted.

## Findings

Perf profile (GT 1030, NVIDIA 582.67, Win 11, 1280x720, 60 Hz; `perf_play`, windowed real time). The game is CPU-bound GDScript; GPU about 1.5 ms.

| Scenario | Before | After round 1 |
|---|---|---|
| Typical walk, vsync on | 17.0 ms avg, p95 22.5, p99 34.6, 58.7 fps, 17 frames > 33 ms | 17.1 avg, p95 17.0, p99 24, 58.4 fps, 7 > 33 ms |
| Crowd (6 villagers 1.5-6 cells), vsync on | 25.1 avg, p95 76, p99 139, 39.8 fps, 112 > 33 ms | 18.0 avg, p95 26.8, p99 32, 55.5 fps, 4 > 33 ms |
| Typical, uncapped | 10.3 ms (97 fps) | 5.2 ms (193 fps) |
| Crowd, uncapped | 11.8 ms, p95 17.8 | 7.5-9.4 ms, p95 20-30, bursts of 4 x 50 ms frames |

Remaining shortfall: crowd p95 ~27 ms with vsync (about 156 of 1100 frames over 20 ms). Cause: several volumetric figures close by (lit ~4 ms, swept ~6 ms each, GDScript path building: FigureVol.parts, rim_part, mask_root, emit_poly) plus unexplained 4-frame ~50 ms bursts after pings (unprofiled; candidates: several figures sweeping at once, people events, GC).

Gaps still not ported (decisions in the AI_HANDOFF "NOT included" table): Windows export (needs templates: ask the user), renderScale (fixed 640x360; governor replaces it), dragLook (not applicable), multi-tab lock (n/a), JS Forge editor (partial: Alter nearest), screen-reader announcements, OS reduced-motion, log persistence and uncaught-error screen, debug light radii, italic muffled subtitles, wipe golden fixture, menu styling.

## Next steps (priority order)

1. Run the full suite (about 9 min, background): `"./Godot_v4.4.1-stable_win64.exe" --headless --path project -s res://tests/run_tests.gd` and record the summary line in AI_HANDOFF.md.
2. Crowd perf if still short (round 2 figure caching did not help measurably; re-measure with a same-session baseline, runs vary a lot): profile the post-ping 50 ms bursts with PF instrumentation (`tests/tools/pf.gd`, printed by perf_play), cache figure geometry per echo, cap volumetric figures per frame by estimated cost.
3. Windowed visual check of the new shader extras (window glint, reduced-motion door pulse never seen in a screenshot), vessel figures (vessel_view shots were too dark), wipe and edge glow: `--write-movie <abs dir>\f.png --fixed-fps 60 --quit-after 120 -- --scenario=quality_modes --qmode=high|low|reduced` and `transition_test`, `edge_glow`.
4. User playtest (audio by ear, look sign-off), then the rest of the AI_HANDOFF TODO list.

Known oddities: windowed runs that quit from a scenario sometimes segfault at exit after finishing (signal 11; villager_test, perf_play): exit-time cleanup, not investigated.
