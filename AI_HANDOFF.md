# AI handoff: Godot port of "Vampires Can't See"

Read this first. It is written for the next AI session (or developer) picking the port up. Status: **alpha, feature-complete against the
JS game (version 0.20.2) except the items under "NOT included"; version 0.21.0 adds the Godot-only roguelike mode "The Long Night" (see "Changes in 0.21.0"); 0.21.1 adds its next two stages, Bramble Wood and Gallows Moor (see "Changes in 0.21.1")**. Nothing here has been judged by a person's eyes or ears yet (see "Unverified").

## Ground rules

- Repo layout (restructured 2026-10-22): the **Godot port is the repo root** (`project/`, `tools/`, `docs/`, `PLAN.md`, this file). The original browser game was moved to
  `html-version/` and is the **reference: never edit `html-version/`** from port work (golden fixtures are generated from `html-version/js`).
- Engine: Godot **4.4.1** stable, Compatibility renderer, GDScript only. The binary is `Godot_v4.4.1-stable_win64.exe` at the repo root (git-ignored by the global `*.exe` rule: the user keeps it locally). No C#, no GUT/GdUnit4,
  no export templates (the user has not approved downloading them).
- Commit as you go; commit messages end with `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`. The user wants a tidy tree.
- Windows + Git Bash. Paths contain spaces: quote them. Git warns about CRLF; `git config core.safecrlf false` silences it.
- Plan and history: [PLAN.md](PLAN.md). Module map: [docs/PORT.md](docs/PORT.md). Fixtures, tolerances, known gaps: [docs/PARITY.md](docs/PARITY.md).
  User-facing summary: [README.md](README.md). Original game docs: `html-version/docs/MANUAL.md`, `html-version/docs/DESIGN.md`, `html-version/claude/TODO.md`.

## How to work

Git: `main` on `github.com/joshfryart/vampires-cant-see`. `.gitignore` covers `.godot/`, `out/`, `tools/node_modules/`, `.claude/`. The old folder name `___VERSION__GODOT___VERSION___` no longer exists (everything moved to the root); older commits and notes may still mention it.

| Task | Command (run from the repo root) |
|---|---|
| Play | `play.bat` or `Godot_v4.4.1-stable_win64.exe --path project` |
| Parse-check one script | `python -m cli_anything.godot --json -p project script check res://render/foo.gd` |
| All tests (~9 min, 225 tests, 1.1M checks) | `Godot_v4.4.1-stable_win64.exe --headless --path project -s res://tests/run_tests.gd` |
| One test file | same, then `-- --filter=vessels` |
| Import after adding a `class_name` file or new assets | `Godot_v4.4.1-stable_win64.exe --headless --path project --import` (1-6 min) |
| Regenerate a golden fixture | `node tools/golden/<name>.mjs` (loads the real `html-version/js` modules, writes `project/tests/fixtures/<name>.json`) |
| Rebake audio | `cd tools && node bake-audio.mjs` (uses `node-web-audio-api`, installed in `tools/` only; deletes and rewrites `project/audio/wav`, then re-import) |
| Screenshot a scene | `Godot_v4.4.1-stable_win64.exe --path project --rendering-driver opengl3 --write-movie <ABSOLUTE dir>\f.png --fixed-fps 60 --quit-after 120 -- --scenario=<name>` (dir must exist; a relative path fails; ~15% real time, run long ones in the background) |

Scenarios are scripts in `project/tests/scenarios/` (`setup(g)` / `step(g, delta)`); the harness picks them with `--scenario=`.
Headless tests can build the whole game: `Game.manual_boot = true; Game.test_storage = SaveCodec.MemoryStorage.new(); var g := Game.new(); g.boot()`.
Shaders do not compile headless; every shader change needs a windowed run.

## Architecture in one page

- `core/`: pure logic, no nodes. `world`, `raycast`, `sonar`, `acoustics`, `people` (+ `schedule`, `forge`, `barks`, `listen`, `struggle`), `night`,
  `hunger`, `meta`, `save_codec` (JS-exact envelopes and checksums), `config`, `flags`, `vessels`, `creator`, `checks`, `log`, `rng` (mulberry32, bit exact).
  Plain `float` math; world coordinates are JS (x, y, z), mapped to Godot (x, z, y) only in `coords.gd` and the mesh builder.
- `game/`: `game.gd` (state machine and integrator; update order mirrors JS `update` then `simulateWorld` then `frame`), `run_flow.gd` (runs, nights,
  boons, gifts, sleep, saves, import/export), `powers.gd`, `tutorial.gd`.
- `render/`: the sonar view is a 640x360 SubViewport. Walls, floor and ceiling are meshes with shaders (`shaders/sonar_*.gdshader`); everything the JS drew on its
  2D canvas (villagers, props, markers, air rings, floor texture, HUD, title) goes through the `Canvas` abstraction: `RecordingCanvas` (logs calls for hash parity)
  and `DrawCanvas` (draws on a CanvasItem; ordered ops, strokes, filled polygons, text). Figures: `pose.gd`, `figure_line.gd` (Effects 0), `figure_vol.gd` +
  `figure_vol_draw.gd` (volumetric, Effects 1-2), `vessel_draw.gd`, `echo_layer.gd` (drawPerson), `echo_view.gd` (frame builder), `hud_draw.gd`, `icons.gd`, `title_draw.gd`.
- `ui/`: `menus.gd` (all panels, plain Godot controls), `hud.gd` (window-resolution overlay: subtitles, debug text, warm halos), `hud_view.gd` (HUD inside the viewport),
  `creator.gd`, `dev_panel.gd` (F9), `map_view.gd` (M), `icon_rect.gd`.
- `audio/`: `audio_director.gd` plays baked WAVs (`manifest.json`) and live speech from `speech_synth.gd`; `tools/bake-audio.mjs` renders the samples from `html-version/js/audio.js`.
- `tests/`: `parity/` (JS fixtures), `flow/` (run flow, gameplay, 6-minute soak), `unit/`, `scenarios/`, `tools/`.

## Parity method (how "done" is proven)

Node scripts in `tools/golden/` run the real JS modules (`html-version/js`) and write fixtures; GDScript tests compare. Draw code is compared by **FNV-1a hash of the canonical call log**
(args rounded to 1e-3, `tools/golden/lib/render_harness.mjs` + `RecordingCanvas`). Exact hash matches exist for: line figures, struggle figures, volumetric figures (555 scenes),
sprites and props, floor effects, HUD and icons, vessel overlay (281 scenes). Logic fixtures: rng, raycast, world, player, sonar, acoustics, people (with and without Forge/Schedule/vessels),
schedule/forge, night/hunger, meta, save, barks, listen, struggle, creator, vessels. A new JS-visible behaviour should get a fixture before it is called ported.

## Gotchas learned the hard way

- New `class_name` files need `--import` before other scripts (and `script check`) can see them.
- GDScript lambdas **capture by value**: counters mutated in a lambda need an array (`var n := [0]`). Static arrays filled lazily must be initialised before first use (`Vessels.all()`).
- Built-in name clashes (`hash`, `wrap`, `move_toward`, `hypot`): use `hash2`, `envelope`, `walk_toward`, `_hypot`.
- Godot JSON is not correctly rounded: store exact numbers as integers in fixtures or compare with an epsilon. `JSON.parse_string` prints errors on bad text: use `JSON.new().parse`.
- `PackedFloat32Array` slots (`Pose.X/Y/Z`) match JS `Float32Array`; keep doubles as `Array`/`float` where JS used doubles (that is why `Vessels.point` returns `[x, y]`, not `Vector2`).
- Multi-line shell heredocs have failed in Git Bash: write files with the Write tool, or a small python script file.
- `DrawCanvas.fill` approximates nonzero winding by merging self-overlaps; it skips polygons Godot cannot triangulate.
- `People.vessels_on` is a static; `Game.boot` sets it from the flag, parity tests set it per test. `Flags.persist = false` in tests so a developer's `flags.json` cannot change results.

## Changes in 0.21.8 (Hollow pass 1: calmer opening, ping step, quirks, brief repeat-run cave)

First of three cave passes (log: `docs/CAVE_ITERATIONS.md`). Tests: `test_rogue_tutorial.gd`, `test_rogue_sense.gd`, `test_stage_gen.gd` (bottoms).

- **Calmer opening**: on the guided night the Sense HUD hint is rested (no pulse, not bright) and its clock (`RogueMode.hint_t`) stands still until the tutorial shows `sense_intro` (or the `sense` reminder); `RogueMode.sense_hint_held()`. Off the guided night (repeat runs, Tab, a continued run) nothing changes.
- **Ping step**: a ping made while the waking line shows now completes the `ping` step (`Tutorial._past("ping")`: any ping since `rogue_begin`); it used to wait for a second ping. Text "Click or Space to ping. Listen to what comes back." (click pings too). Waking line: "The lid creaks. So do your knees. You cannot see. Listen."
- **Quirks (cards only)**: the first ping within 7 cells of the echo hall beat on the guided night shows "...hello ...ello ...llo" / "You only clicked. The hall is being polite." (a short card, never over another card, once a trek); the first rat drunk each trek shows "Rat. It wishes to complain." as the +blood card's subtitle.
- **Brief Hollow (repeat runs)**: `StageGen.generate(id, seed, brief := false)`; `GenCave` with brief = true places the 7 beat chunks only (no filler chambers, so no filler loop, drips or rats) and keeps consecutive beats within `BRIEF_REACH` 18 cells instead of `CHAIN_REACH` 24: the walk from the coffin to the exit is about 15% shorter (151 vs 179 cells, mean over 40 seeds). brief = false is byte-identical to 0.21.7 (60 seeds hashed). `TrekFlow.brief` is set at `begin` from the meta's `tutorialDone` and saved as the optional `night.trek.brief` (written only when true), so a continue regenerates the same layout; older saves load the full cave. `StageGen.analyze` reports `path_len` (start to exit arrival) and rejects a brief def with fillers or loops. Other generators ignore the flag.

## Changes in 0.21.7 (Sense discoverability)

Playtest: "couldn't find a way to use that new power". V worked (verified in a real window, below), but nothing introduced it. Tests: `tests/flow/test_rogue_sense.gd` (bottom), `test_rogue_tutorial.gd`.

- **Tutorial**: new non-interrupt step `sense_intro` ("V: sense the way. Free in the cave; beyond it, the cold air costs blood.", 6.5 s) right after `rings`, before `drips`. It retires at once if the player runs past the gallery (rank >= 2) or has already sensed, and a resumed trek marks it done. The old interrupt step `sense` is now the reminder (first time lost, or after the cave mouth) and is marked done without showing once the player has used Sense.
- **HUD hint** (`ui/hud_view.gd _draw_sense_hint`, `RogueMode.sense_hint_look()`): white, 3 px larger, with a slow pulse for the first `SENSE_HINT_PULSE_S` (8 s) of a run, bright until Sense is used once or `SENSE_HINT_BRIGHT_S` (60 s) pass, then fading to the old dim line. It moved down to y 27, under the "Dawn in" line (they overlapped before). Text after the cave: `V sense (-N blood)`.
- **Menus**: How to play has a "The Long Night" section (V sense, R lunge, Q / Shift or C / F powers, Tab); the title footer and the pause menu list V.
- **Real window check**: `tests/scenarios/sense_check.gd` starts a trek, injects V via `Input.parse_input_event` and saves frames to the scratchpad (`--out=`). Findings: the V press does reach `Game._unhandled_input` -> `pressed` -> `RogueMode.step` -> `try_sense` (sense_t 2.0, cooldown 8, senses 0 -> 1) and the ring plus arrow cue draws. `parse_input_event` delivers on the next input flush, not synchronously, and `_unhandled_input` ignores input while a scenario runs, so the scenario lifts that guard for 4 frames. The scenario backs nothing up: it starts a new trek and so deletes your `vcs_trek.json`.

## Changes in 0.21.6 (wayfinding: draft, breath beads, Sense)

Version 0.21.6 makes the way out of the Hollow easier to find without touching echolocation. Tests: `tests/flow/test_rogue_sense.gd`.

- **`TrekFlow.next_toward_exit(cell, k)`**: walks `dist` downhill k steps (neighbour order E, W, S, N, strictly lower), so the result is k steps closer or the exit itself. Everything below aims at `next_toward_exit(cell, n)`.
- **Directional draft**: the wind loop plays on its own bus `Draft` (an `AudioEffectPanner`, sent to `Beds`), panned by `RogueMode.wind_pan` = sin(bearing of `next_toward_exit(cell, 6)` relative to the facing) x 0.9. Loudness is still `wind_target(distance)`, capped at `WIND_CAP` (0.5); new floor `wind_floor(level)` = 0.06 / 0.12 at assist level 1 / 2.
- **Lost tracker and assist ladder**: `lost_t` grows while `trek.dist[cell]` has no new best on the stage (resets on a new best and per stage). `RogueMode.assist_level(lost, fx, tutorial_on, stage_idx, heat)` (static, pure): level 1 at 25 s, level 2 at 50 s; thresholds x1.5 with the tutorial off or done, x2 with `far_echo` (fx `sonarRange` > 1), x2 from stage index 1 on; level 2 never at Heat >= 3. Constants `ASSIST_*` in `rogue_mode.gd`.
- **Breath beads**: ambient kind `breath` (range 2.5, strength 0.08, 40 rays, within 99) emitted by `RogueMode._step_breath` through the new `Ambient.emit_at` (shares MAX_LIVE 4 / MAX_RAYS 180 via `rays_step`; refused and counted in `skipped_budget` when full; `protect_last` keeps the player's ping) at `next_toward_exit(cell, 3)`: every 6 s at level 1, every 3 s at strength 0.12 at level 2.
- **Sense (key V)**: `RogueMode.try_sense()` returns `{ok, code: ok|off|frozen|busy|cooldown|weak, cost}`. Cooldown 8 s, cue 2 s. Free in the Hollow (stage id `hollow`); later stages cost `ceil(4 x stage drainMul)` blood (wood 4, moor 4, road 5, inn 5) and need blood >= cost + 5 else the card "Too weak to sense". Effects: a soft `rg_drip_gutter` at half gain, the draft swells toward the way out (up to the cap, panned), and `HudView` draws a line-art ring with a bright arc and arrow head at the bearing of `next_toward_exit(cell, 6)` (`RogueMode.sense_cue()`). Not in classic mode, not while the day prompt or a wait freezes input. Uses are counted in `TrekFlow.senses` (optional `senses` key in the `night.trek` extension; older saves load 0) and `stats["senses"]`.
- **Clarity**: HUD line top right "V sense (free)" in the Hollow, "V sense (-N blood)" after (dim while unusable); the first time a stage with index >= 1 starts a card shows "The cold air / Beyond the cave, sensing costs blood."; tutorial interrupt steps `sense` ("V: sense the way. Free in the cave; beyond it, the cold air costs blood.", at the first time lost or after the cave-mouth beat) and `draft` ("Feel that draft? Air wants out. So do you.", at assist level 2, once per run). Tab skips them with the rest of the tutorial; the sim is identical with the tutorial on or off (except that the assist thresholds are x1.5 with it off).
- **Unverified in a real window**: the draft pan and the Sense swell by ear, the ring and arrow in the HUD, the hint placement top right.
- **Cave wayfinding layout (W2) follow-ups, resolved**: the new cave maps broke two tests. `test_prompt_freezes_hunters_stakes_and_clock` placed the hunter 0.5 from the player, where People's own startle/flee (not the hunt) moved it; the test now builds the scenario (hunter on a cell 8 BFS steps away, plus an unfrozen control that must walk). `test_dead_end_step`: a real bug, the spur mouth can lie deeper (BFS) than the cave mouth, so the depth rule ranked the player as past the cave mouth and `_past("dead_end")` retired the hint; `tutorial.gd` now never retires dead_end while the player is at a spur. `test_contour` re-pinned the hollow classic mesh hash (layout changed) and sets `contour_enabled = false` explicitly for its classic mesh.
- **Full suite green**: `{"checks":1249720,"failed":0,"failures":[],"tests":378}`.

## Changes in 0.21.5 (S3c: the cave ceiling is a mesh)

Version 0.21.5 replaces the Hollow's canvas ceiling marks (scattered scribbles near the ping front) with real geometry. Only the hollow (`FloorFx.ceil_style == "cave"`, styled worlds); classic maps keep the flat ceiling plane, wood / moor / road / inn keep their canvas sky / canopy / rafter ceilings.

- **`render/vault_mesh.gd` (`VaultMesh`)**: a height field every 0.5 cell over the open cave plus 0.6 cell of rock beyond the grid walls. Height = `FloorFx.ceil_height` per cell (echo hall 1.4, squeeze 1.0, drip gallery 1.2, pockets 1.05, others 1.12 +/- 0.05; rock and apron cells take the mean of their open neighbours), bilinear between cells, plus bounded `ContourField.fbm` noise seeded by `World.map_seed` (0.05, zero where the base is flush). Next to a wall the height is pinned to exactly 1.0 and rises by a smoothstep over 1.3 cells of grid distance (signed distance measured against the GRID, so the visible contour, up to 0.25 inside the rock, already sits on the flat part: no gap with the wall tops; tested < 0.02 at every outline vertex). Outdoor cells fade out (indoor weight in `COLOR.r`, 2-cell ramp). `build_surface()` is the grid, `build_stalactites()` a second mesh of small cones (clusters at chamber centres, per-zone length and density, drip beads on the drip gallery), `height_at` / `dist_at` for tests.
- **`render/shaders/sonar_vault.gdshader`**: additive, unshaded, `depth_draw_never` (the walls still occlude it by depth, the sprite zbuf is CPU and untouched). Brightness is `sonar_wall_light` at the fragment's ground point (ceiling-edge value), so it is lit exactly like the walls and covers the whole lit band continuously. Ink: boss contours (relief isolines, all qualities, faded 6 to 9.5 cells), jointed cracks (broken Voronoi borders of a warped lattice) and dip-aligned dashed bedding (quality 3 + `mat_detail`, same `STRATA_Q` as the wall shader, checked as text), stalactite cones (lip ring, mid ring, silhouette, three taper lines at quality 3) and drip beads. Line density fades by cells-per-pixel so far ceilings do not moire.
- **Wiring (`game.gd _show_map_mesh`)**: `meshes[name]` is `[walls, floor, ring pass, vault surface, stalactites]` for the cave (`ceil_mat` ring pass now runs on the vault mesh, so the ceiling ring follows the real heights), `[walls, floor, plane]` otherwise. `vault_mat` gets the pulse textures and quality uniforms with the other materials; the world is tagged `set_meta("vault_mesh", true)` and `FloorFx._draw_surface_texture` then skips the cave `vault*` canvas marks (the apron's sky stars remain).
- **Vibration after a wall hit**: the rock vibration now quivers only the even strata courses (4 of 7) at alpha x0.45, so the struck wall reads as short broken scratches rather than a hatch. New tour view `vib_wall` (a wall at 2.4 cells; shots 0.1, 0.2, 0.3 s after the hit, option 6 of a VIEWS row).
- **Perf**: hollow typical walk, uncapped, 10 s windowed (GT 1030): avg 5.82 ms (p95 11.4) against the 6.5 ms gate (0.21.4: 5.98); the canvas vault marks are gone, the mesh costs less than they did.
- **Tests**: `tests/unit/test_vault_mesh.gd` (builds for all stages, finite non-degenerate triangles, height per zone, determinism by seed, seam with the wall tops, game wiring, classic untouched, STRATA_Q block).
- **Unverified / looks off**: judged only in tour frames, not in real play. Cones are wireframe (additive, they cannot hide what is behind them); the dip direction changes abruptly at the 8-cell borders (as on the walls); bosses are long sweeping isolines near the horizon.

## Changes in 0.21.4 (S3b: strata, ceilings, quieter floors)

Version 0.21.4 follows the first look at 0.21.3. Everything is gated on `world.wall_style` (styled maps only); classic maps, the parity hashes and the golden tests are unchanged.

- **Rock strata (`sonar_wall.gdshader`, `rock_detail`)**: seven layered courses per rock face (odd courses only within 4.2 cells), each with its own run length, breaks, height jitter and wobble, still tilted by the world-anchored dip (`rock_tilt`), faded by facing and distance. Minor courses are dimmer. Cracks and seeps are unchanged.
- **Struck-wall vibration**: the five evenly spaced wavy lines are gone for ink materials. Rock: the strata themselves quiver (`rock_detail` with a pixel offset, alpha x0.55). Other ink styles: three faint, broken, wandering lines (alpha x0.45). Style 0 and classic maps keep the five lines.
- **Floors (`floor_fx.gd`, `floor_kind_for`)**: in ink worlds stone / roughStone floors are always `rubble` (no brick joints), wood floors are `plank_ink` (short broken boards). Roads and the inn yard keep setts.
- **Ceilings (`floor_fx.gd`, `_draw_surface_texture` up pass)**: `ceil_style(world)` (cave, inn, wood, moor, road), `ceil_kind_styled`, `ceil_height`, `ceil_mesh_mul`. Hollow: `vault` marks (rock bosses as closed contour loops, short jointed cracks, dip-aligned bedding dashes, grain, stalactite clusters, drip beads). Echo hall (`vault_hall`) is higher (1.4 wall heights) with long sparse stalactites; the squeeze (`vault_tight`) is flush with the wall tops (1.0) with dense short ones; the drip gallery 1.2, pockets 1.05, other cells 1.12 +/- 0.05. The ceiling plane mesh of the cave sits at 1.12. Outdoor cells (and the cave apron) get sky: `canopy` (leaf V-ticks, twigs) in the wood, `stars` on the moor, road and inn yard; inn interiors get `rafter` beams. `FloorProj.hmul` carries the ceiling height (1.0 = the old projection exactly). Styled ceiling strokes are drawn at 0.7 of the floor alpha.
- **Tour**: `style_tour` gained `ceil_cave`, `ceil_hall`, `ceil_inn`, `ceil_moor` (looking up by `Game.look_shift`, a new scripted-shot horizon shift, 0 in play).
- **Perf**: hollow typical walk, uncapped, 10 s windowed: avg 5.98 ms (p95 12.9) against the 6.5 ms gate.
- **Unverified**: nobody has judged the ceilings under real play. Only the cells near the ping front are drawn, so the vault shows as a band that sweeps outward; at 3 to 5 cells the marks are sparse and read as scattered scribbles more than a continuous rock surface. The ceiling is a canvas overlay at its own height, not geometry, so it is not occluded by the lip jag of the walls.

## Changes in 0.21.3 (S3: the ink wall style is switched on)

Version 0.21.3: trek stages hollow, wood, moor, road and inn now draw with the A+B hybrid wall style specified in `docs/STYLE.md` (read it first). Classic maps (town, crypt, tutorial, later stages) are unchanged and the parity hashes do not move.

- **Switch-on:** the three generators (`gen_cave`, `gen_wild`, `gen_road`) copy the stage row's `wallStyle` into the def; `Game.boot` sets `WorldMeshBuilder.contour_enabled = true`; `_show_map_mesh` tags each cached wall mesh with meta `styled` (contour path built) and pushes the shader uniform `styled` for the visible map. The inn row also maps `B` (milestone) and `I` (fence) because its yard uses them.
- **Shader (`render/shaders/sonar_wall.gdshader`):** `styled = 0` runs today's code path unchanged. For styled maps the style id comes from `COLOR.g` (style * 4 + face code), light, cell and ripples use the anchor `UV2` and the grid normal, `UV.x` is arc length. Style 0 (doors, windows) keeps the legacy branches with `u` derived from the anchor. Styles 1..9 get: lip height per material (a discard above it), contour top/bottom edges, silhouette line from the normal, corner posts for built styles, a faint lit body (quality >= 2), and at quality 3 with material detail: rock strata (world-anchored dip, facing, distance fade) with cracks and seeps, thicket / gorse / bark / cairn / milestone / timber / drystone marks. Fence rails and posts draw at every quality. The const block `STRATA_Q`, `HALO_Q`, `LIP_JAG_Q` mirrors `LineStyle.wall_features` (checked as text by `test_style_switch.gd`).
- **Not done / deviations:** no concave crease line; gibbet and fence share style id 7 (both draw as fence); the dip seed uses the anchor cell only (no map seed uniform); root flare on trunks is not drawn.
- **Tour:** `tests/scenarios/style_tour.gd` (windowed, writes Movie Maker frames plus `shots.txt`; options `--only=`, `--qs=`, `--novib`, `--dist=`). `tests/scenarios/perf_play.gd` gained `--stage=<id>` to profile a generated stage. Hollow typical walk, uncapped: avg 5.96 ms (p95 13.1) over 10 s on the GT 1030, against a 6.5 ms gate (town, classic: 5.49 over 3 s).
- **Floor note (S4):** the Hollow floor still draws brick joints through `floor_fx` for material `stone`; S4 owns the rubble replacement.
- **Unverified:** nobody has looked at it under a moving light or on the player's own monitor; the author looked at about 20 frames only.

## Changes in 0.21.2 (WP13b: The Old Road and Crossroads Inn)

Version 0.21.2: stages 4 and 5. The trek now runs hollow -> wood -> moor -> road -> inn and ends with cause `frontier` after the inn (the hamlet has no generator). Design: `docs/ROGUELIKE.md` ("Road stages").

- **Generator:** `core/gen/gen_road.gd` (`GenRoad`, `road` and `inn`; dispatch line in `StageGen.generate`, `TrekFlow.GENERATORS` = cave, wood, moor, road, inn). Rows `road` (drainMul 1.1, 4 miles, watchers 2, pockets `wayside_crypt` / `culvert` / `bramble_hollow`, restTarget 28) and `inn` (drainMul 1.1, 3 miles, rest `cellar` 0.4 / `stable` / `woodshed`, restTarget 32) in `data/rogue/stages.json`. Open-air R = 5.
- **Holy ground:** the road's shrine sits in an alcove with a 3x3 zone of kind `holy` (`shrine_holy`). `WorldValidate._validate_zones` now accepts kind `holy` (one condition); TrekFlow already drained 8 blood/s on it. The zone is not `outdoor`, so the sun does not apply inside it, and `SoundData.room_profile` falls back to indoor.
- **People:** generated maps spawn people from `P` markers (row-major) with `paths` defs like the village; road: pilgrim pair, carter, 2 `guard` watchers; inn: innkeeper, drunk, 2 regulars, merchant on `places` schedules (`home: tavern`), 3 seated patrons. Per-person sight cones are not configurable (shared `REACT_DEFAULTS.seeCone`), so the two watchers use the default cone.
- **Outside the new files:** `StageGen.SOLID_PROPS` extended to every solid prop (shrine, haybale, scarecrow, table, chair, bench, barrel, well, brazier, gravestone), `data/rogue/ambient.json` kinds `cart`, `bell`, `singing`, `tests/unit/test_gen_wild.gd` (road is now generated).
- **Numbers (50 seeds each):** road avg 63 ms, worst 185 ms, open fraction 0.19-0.27, worst rest distance 36, 3+ pockets, open-air worst 5.00; inn avg 40 ms, worst 81 ms, open fraction 0.40-0.50, worst rest distance 41, 4 pockets, open-air worst 5.00.
- **Not verified / leftovers:** nothing seen or heard; no horse prop or sprite exists (the stable has hay and a trough bench); `cart` / `bell` / `singing` have no baked sound mapping in `RogueMode` yet (they emit sonar pulses only); inn doorways are open gaps (no `D` doors) so occupants always see in; the common room and cellar are tiny so heat from hostile occupants is untuned.
- **Tests:** `tests/unit/test_gen_road.gd` (15 tests), `test_echo_env.gd` (road and inn in `GENERATORS`), `tests/flow/test_trek_stages.gd` (TrekFlow and RogueMode walk hollow -> ... -> inn -> frontier, holy drain in `test_gen_road`), tool `tests/tools/road_probe.gd`.

## Changes in 0.21.1 (WP13a: Bramble Wood and Gallows Moor)

Version 0.21.1: two outdoor stages after the Hollow, so the trek now runs hollow -> wood -> moor and ends with cause `frontier` ("To be continued...") after the moor until the Old Road exists. Design: `docs/ROGUELIKE.md` ("Wild stages").

- **Generator:** `core/gen/gen_wild.gd` (`GenWild`, one file for both kinds; `StageGen.generate` dispatches `generator: "wood" | "moor"`). Rows in `data/rogue/stages.json` (`wood`: drainMul 0.9, `moor`: 1.0, 3 miles each, `entry` / `exit` door cfg, `fauna`, `terrain`, `shelter.kinds / maxPockets / restTarget`). Both are `kind: outdoor` (sun kills), 64x48, start at dusk on the cell in front of the west entry door (`cave` / `wood`), exit door on the east edge (`moor` / `road`); the door names follow the neighbour's `toDoor`, so `validate_all` with neighbour stubs links both ways (hollow `mouth` <-> wood `cave`, wood `moor` <-> moor `wood`, moor `road` -> `stage:road`).
- **Wood:** `#` grass thicket (cellular automaton), `W` trunks, a 2-wide meandering creek `~` across the whole height, crossable only at 2 fords (2-row gaps; `places.ford_N` = [x, y]); rabbits and deer; ambient owl / creek / wind; fireflies = `glowworm` props. **Moor:** open grass, `#` gorse blobs, `B` cairns (rough stone), `I` gibbets, 2-3 bog pools `~`; hares and wolves (wolves start >= 18 cells away); ambient wind / cricket / ripple; wisps = `glowworm` props with a 3.0 light. The crickets go silent within 3 cells of the player (`quiet` in `data/rogue/ambient.json`, honoured by `Ambient.step`).
- **Covered pockets:** indoor zones stamped into the open ground, every one with an `S` rest spot: hollow tree (ring of `W`) and fox burrow (`#` bank) in the wood, barrow (ring of `B`) and peat cut (`#` bank) on the moor. Added at the walkable cell farthest from the rest spots until it is within `restTarget` BFS cells (wood 30, moor 36; the hard rule stays `StageGen.cover_limit` = 576). A pocket is only stamped where the open cells of its surrounding ring form one arc, so it can never cut a path. 4-8 pockets per stage.
- **Open-air rule (R = 6):** obstacles (trunk, cairn, gibbet, bush) go on the walkable cell farthest from any wall until none is farther than 5.5 (chamfer distance, an upper bound); obstacles always have 8 floor neighbours. `GenWild.open_air_max(def)` is the exact Euclidean check (tests use it; echo suite `test_open_air_rule`).
- **Numbers (50 seeds each):** wood avg 43 ms, worst 86 ms, open fraction 0.64-0.80, worst rest distance 31, open-air worst 5.39; moor avg 38 ms, worst 66 ms, open fraction 0.86-0.89, worst rest distance 36, open-air worst 5.39. One attempt for nearly every seed.
- **Handoff change outside the new files:** `TrekFlow.GENERATORS` is now `["cave", "wood", "moor"]` (one line). Nothing in `game.gd` / `rogue_mode.gd` needed a fix: `RogueMode.on_exit_door` -> `reach_exit` -> `_enter_descriptor` already swaps the world, critters and ambient (verified headless by `tests/flow/test_trek_stages.gd`). Known cave-only leftovers in `RogueMode`: the wind loop bed follows the distance to the exit door in every stage (so it is a gust by the exit in the outdoor stages too), and `BEAT_HINTS` only knows cave beats (the outdoor stages have `beats: []`).
- **Tests:** `tests/unit/test_gen_wild.gd` (13 tests, 50 seeds per stage: validate_all with neighbour stubs, exit reachable, pockets and rest spots, the sun cannot reach pockets, cover distance, open air, caps, fords, determinism, time), `tests/unit/test_echo_env.gd` (`GENERATORS` now `cave, wood, moor`; new `test_open_air_rule`), `tests/flow/test_trek_stages.gd` (TrekFlow and RogueMode walk hollow -> wood -> moor -> frontier, checkpoint in the wood, sun in the open vs a pocket), tool `tests/tools/wild_probe.gd` (`-- --stage=wood --seeds=20 --dump=1` prints per-seed numbers and an ASCII map).
- **Not verified:** nothing of the outdoor stages was seen in a screenshot or heard; thicket density, fauna balance (deer 30 blood, wolves) and the pocket look are unplayed.

## Changes in 0.21.0 (The Long Night)

Version 0.21.0: the roguelike mode "The Long Night" is playable end to end for its first stage, the Hollow (cave). Design and APIs: `docs/ROGUELIKE.md` (read it first). Classic "Five Nights" is hidden from the title and only reachable with the dev flag `--classic`; its code, saves and tests are unchanged.

- **How to run:** `play.bat` or `Godot_v4.4.1-stable_win64.exe --path project`, then "The Long Night" on the title. Arguments go after `--`: `--classic` (show the classic Five Nights buttons), `--scenario=NAME`, `--map=NAME`, `--sys=` / `--tun=`. `flow.seed_param` fixes the trek seed (tests; scenarios set it). WASD move, mouse look, click or Space ping, R or right-click drink (people and critters in reach), E door / sleep at a rest spot / reopen the day prompt, Esc pause (a trek is only checkpointed at stage entry, at sleep, on quit to menu and on window close).
- **Wiring (`game/rogue_mode.gd`, `RogueMode`, `game.rogue`):** owns the `TrekFlow`, `Critters`, `Ambient`, the day choice and the hunters, and is a `Game.systems` hook (step / on_pulse / draw) while a trek is on. The Menus signals (`trek_new_requested`, `trek_continue_requested`, `rise_again_requested`, `title_requested`) are connected in `connect_ui()`; `TrekFlow.begin(menus.trek_meta, seed, flow.store)`; `RunFlow.begin_run` is never used. While `rogue.active` (`Game.rogue_on()`): `g.night` / `g.hunger` ARE the trek's (the HUD reads them), `flow.fx` = the trek's TrekMeta effects, `flow.run` is a stub `{seed, boons: []...}` (so `run_seed`, warm sense and the sonar effects work), the classic `step_night`, sleep (`flow.try_sleep`), blood gifts and run saves are bypassed (`RunFlow.run_is_active()` returns false so `save_run` never writes a classic save).
- **Per stage:** `GameData.register_map` + `Game.add_world`, `enter_map` at `descriptor.start` facing `descriptor.angle`, critters from `descriptor.critters` (the same `Critters` instance for later nights: prey never respawns), `Ambient` anchors, `TrekUi.show_stage_card`, the previous stage is dropped. A same-named stale stage (Rise Again) is evicted first.
- **Per frame:** `trek.step(dt, cell, outdoor, {player_pos, mist, hunters})`; events: `dawn_warning` (bell, hint), `dawn` (birds), `needs_choice` (prompt: Wait out the day / Keep looking; E at a rest spot within 1.5 cells sleeps via `sleep_at_rest`; E elsewhere reopens the prompt), `dusk` (Heat, new hunters), `revived` (teleport), `death` -> `end_run` -> Laid to Rest. Waiting out the day fast-forwards `WaitDay` (`step_waiting`, overlay with the Stir button, interrupts shown, then `apply_wait`). Hunters (`hunters_wanted()`) are `hunter` villagers that follow a BFS distance field to the player at 2.4 cells/s and stake within 1.2 cells (Mist stops it).
- **Critters:** `Critters.step` each frame, windowed echo snapshots (`echo_snapshot_visible(pulse, t_prev, clock)` for every live pulse), `squeak`, loud pulses frighten them (`on_pulse`), R / right-click / E drink the nearest critter within 1.2 cells (`try_feed_critter`: blood by species x stage `bloodGain`, a small struggle-sized noise, Ratspeak = silent and +25% at tier 2). They are drawn by `render/critter_draw.gd` (line glyphs per species, lit by their echoes, hidden behind closer walls) from the systems `draw` hook.
- **Audio:** `RogueMode._init_audio` registers `data/rogue/sounds_rogue.json` with the `AudioDirector` (its manifest and stream cache), so `g.audio.play("rg_...")` has pan, distance and occlusion; the wind loop at the cave mouth is a `Beds` player built like `_loop_stream`. Played: drips (`rg_drip_cave` / `rg_drip_pool` from the ambient anchors), bat / rat squeaks, flush sounds (bat flutter, rat skitter), dawn bell (at 90 s and 30 s) and birds, coffin creak at a new trek, stage stinger, soil chime and upgrade sting on a Coffin purchase (watched in `idle_step`), the death toll.
- **Tutorial hints (cave):** `Something drips. Listen.`, `Ping to steer in the squeeze.`, `A dead end rings short and bright.`, `Bats and rats are food...`, `Outside, the sun can find you.`, `Dawn: find cover, or wait it out.` (`tutorial.gd`, queued by `RogueMode`).
- **Frontier:** the stage after the last generated one (0.21.1: the moor; in 0.21.0 it was the Hollow exit) has no generator yet, so leaving it ends the trek with cause `frontier`: Laid to Rest titled "To be continued..." (`TrekUi.rest_text`), Soil paid.
- **Small edits outside the new files:** `game.gd` (rogue hooks, `rogue_on()`), `run_flow.gd` (`run_is_active` false during a trek), `tutorial.gd` (hint texts), `trek_ui.gd` / `menus.gd` (frontier cause only).
- **Full suite (0.21.0):** `{"checks":1124883,"failed":0,"failures":[],"tests":225}`.
- **Tests:** `tests/flow/test_rogue_mode.gd` (14 tests: menu start, walking the Hollow to the exit by its BFS path, feeding, echoes and glyphs, drips, dawn + sleep, wait, Stir, hunters + stake, withering + Rise Again, continue, classic after a trek), scenario `tests/scenarios/cave_tour.gd` (windowed tour; run once, it printed no script errors; the stage card, hints and dawn text were seen in screenshots).
- **Not verified:** the whole mode was only driven by tests and one scripted windowed run, never played by a person. The wind loop and the sounds were not listened to. The critter glyphs were only exercised by tests, not yet seen in a screenshot with a critter in view. Mouse capture / release around the day prompt was not exercised in a real window.

## Changes in 0.20.2 (the lag release)

Version 0.20.2 (the JS game is 0.20.1). Four commits of parity work and two perf rounds. Details are in `git log` (789f495 onwards).

- **Performance (round 1, measured):** ping 17.9 -> 2.7 ms, footstep pulse 1.5 -> 0.15 ms, depth columns 1.2 -> 0.6 ms, pulse texture sync 0.68 -> 0.2 ms, `strongest_echo` 6.4 -> 0.9 ms
  (core grid fast paths, row-cached pulse textures); audio streams preloaded on a thread (the first dog sample was a 401 ms hitch); swept volumetric figure 40-80 -> 6 ms and lit 6.5 -> 3.9 ms
  (built once per figure and replayed per strip, Liang-Barsky clipping, adaptive curve flattening, one triangulation through `canvas_item_add_triangle_array`); EchoView 2.3 -> 1.3 ms, HUD 0.86 -> 0.26 ms,
  title EchoView 2.4 -> 0.01 ms (caches). The adaptive quality governor and figure `fxCap` are ported (`render/governor.gd`, JS constants, real frame dt).
- **Restored gameplay and UI** (were missing or broken in play): listening headcount "Voices inside: N (hushed)" (listening itself was wired and is now verified end to end); bark distance fall, low-pass, occlusion,
  indoor/outdoor muffling, and voices stopped on state change, `res.stop` and map change; `sonarCooldown` fx (shop quick_call, boon quick_ping, gift g_quick); feedToggle release; pending gift choice saved and restored;
  save on window close; focus loss pauses while feeding; Esc in menu sub-views goes back, Esc ignored while sleeping; denied sleep no longer knocks; E toggles gates; `enter_map` resets; mist dash uses look settings;
  tutorial uses `unlock_hint_t`; save failure notice and a not-saved dot that clears on success; menu clicks no longer leak into play; `transitionMs` honoured; large text for subtitles and menus;
  Notice overlay (`ui/notice.gd`, "Heads up" list with OK; deviation: it auto-dismisses after 10 s while the mouse is captured); F3 view, sched (debug builds) and governor lines, refresh 0.25 s; menu keyboard focus;
  Essence now stats row; version label.
- **Dev panel (F9):** search, per-tunable reset, reset all, FPS, settings JSON copy/apply (`Flags.to_json` / `from_json`), copy error report, Alter nearest (JSON look patch, not the JS Forge editor).
  Command-line channels `--sys=` / `--tun=` (the Godot form of `?sys=` / `?tun=`).
- **Render:** wall and floor shaders follow quality, line boil, material detail, reduced motion and effects level, including the fx extras (stone hatch, wood dashes, window glint, line taper, soft gradient front);
  map-transition wipe (`HudDraw.draw_wipe`); directional warm edge glow (`render/edge_glow.gd` + `shaders/edge_glow.gdshader`); figure warm-up at boot.
- **New tools:** scenarios `perf_play.gd` (real-time profile: `--fx --vessels --vsync --secs --crowd --nomove --title`), `quality_modes.gd` (`--qmode=high|low|q2|q0|reduced --qfx --qwindow`), `edge_glow.gd`;
  tools `fig_bench.gd`, `sonar_bench.gd`, `view_bench.gd`; tests `unit/test_governor.gd`, `unit/test_ui_gaps.gd`, `unit/test_edge_glow_wipe.gd`, `flow/test_parity_gaps.gd`.

### Performance numbers

Windowed real time, GT 1030, NVIDIA 582.67, Windows 11, 1280x720, 60 Hz, `perf_play.gd`. "Crowd" = 6 villagers close.

| Case | Before | After round 1 |
|---|---|---|
| Typical walk, vsync on | avg 17.0 ms, p95 22.5, p99 34.6 (58.7 fps, 17 frames > 33 ms) | avg 17.1, p95 17.0, p99 24 (58.4 fps, 7 > 33 ms) |
| Crowd, vsync on | avg 25.1 ms, p95 76, p99 139 (39.8 fps, 112 frames > 33 ms) | avg 18.0, p95 26.8, p99 32 (55.5 fps, 4 > 33 ms) |
| Typical, uncapped | 10.3 ms (97 fps) | 5.2 ms (193 fps) |
| Crowd, uncapped | not measured | avg 7.5-9.4 ms, p95 20-30 |

Round 2 (cache each frozen echo's recorded figure across frames and replay it, budget figures by cost estimate) was tried and **reverted**: the unit filters passed, but windowed crowd runs on the GT 1030 were too noisy to show a gain. Crowd, vsync on, p95 16.95 and 24.84 ms (baseline 26.8; the second run had 25 frames > 33 ms vs 4 at baseline); crowd uncapped p95 17.1 and 30.2 ms (baseline 20-30). Typical walk unchanged (60 fps, p95 ~16.9; uncapped avg 4.9 ms). The crowd tail is still open (see TODO).

## NOT included (differences from the JS game)

| Item | Decision | Reason |
|---|---|---|
| Windows export | not ported | Needs the Godot export templates (a download the user has not approved). Ask first, then `export_presets.cfg` and `godot --export-release`. |
| Adaptive quality governor and figure `fxCap` | restored | `render/governor.gd` with the JS constants and the real frame dt. |
| `renderScale` | not ported | Fixed 640x360 viewport and the shaders hard-code that size. The governor and quality levels give the CPU relief `renderScale` gave in the browser. |
| `dragLook` | not applicable | Godot mouse capture cannot be refused. The key stays in the config for save compatibility; there is no menu row. |
| Multi-tab save lock | not applicable | Two Godot instances could still overwrite each other's `user://` saves (noted, not guarded). |
| Forge editor in F9 | adapted | "Alter nearest" applies a JSON look patch. The full Forge editor needs spawn overrides in `People.spawn`, which the JS does not have either. |
| `?sys=` / `?tun=` URL flags | adapted | Command-line `--sys=` / `--tun=` channels in `core/flags.gd`. |
| F3 sched lines | restored | Debug builds only. |
| Notice modal | adapted | `ui/notice.gd`; auto-dismisses after 10 s while the mouse is captured (deviation). |
| JS test hooks (`Game.debug*`) and the Playwright smoke test | adapted | Replaced by scenarios, the soak test and `bot_play`. |
| JS tools (`sound-lab`, `figure-sheet`, `sim.mjs`) | not ported | They stay JS-only. |
| GUT / GdUnit4 | not ported | Not approved. Tests use the in-repo runner `tests/run_tests.gd`. |
| Itch.io packaging (`html-version/dist`) and the web `update.bat` | not applicable | Web distribution only. |
| Screen-reader live-region announcements | not ported | Low priority. `DisplayServer.tts_speak` would be the route. |
| OS `prefers-reduced-motion` | not applicable | Godot has no equivalent; the in-game setting works. |
| Log persistence to storage and the uncaught-error fatal screen | not ported | GDScript has no try/catch. `Log.report` on demand exists. |
| Debug light-radius overlay (`?debug` `drawLightRadiiDebug`) | not ported | Debug-only. |
| Italic muffled subtitles | not ported | Cosmetic. |
| Wipe golden fixture | not ported | The JS uses `Date.now` for the boil frame, so no exact fixture is possible. |
| Edge-glow radial fallback | not ported | Unreachable: maps always have lights. |
| Quality 4 (`glowBlur`) | not applicable | Unreachable in the JS as well. |
| Menu styling beyond Godot defaults | not ported | Menus are still plain controls; icons exist for shop/boon/gift/guide cards only. |
| Stages after Gallows Moor (The Old Road to The Keep, docs/ROGUELIKE.md) | not built | `cave`, `wood` and `moor` generators exist (`TrekFlow.GENERATORS`); the exit of the moor ends the trek with cause `frontier` ("To be continued..."). |
| Road, settlement and city stage generators, their people, fauna sounds and hazards (WP13b-d, 14) | not built | The data (critters, ambient kinds, baked sounds) is ready; the generators, `thrall`, `bat_form`, holy ground and the King are not. |
| Rest spots humming at dawn, rest spots hidden until near | not built | The markers are drawn like the classic crypt / safe sprites when lit. |
| Powers on a trek (shriek, still, mist) | classic unlock nights | Hunger unlocks them by `night.night`, which only rises with each Heat; a trek-specific unlock table is open. |

## Unverified (needs a person)

- **Audio (go/no-go F5):** baked samples, ambience beds, heartbeats, breath, live speech, and the new bark muffling: all play, none has been listened to. Echo timing is frame quantised.
- **Hand-drawn look (F2):** side-by-side with the JS is in `docs/shots/phase1/`; line weight in Godot is slightly heavier; the user has not signed off.
- **New shader extras, wipe and edge glow:** seen only in a few screenshots (`quality_modes`, `edge_glow` scenarios), not in play.
- **Performance on other machines:** measured on one GT 1030 machine (numbers above). F4 (64 pulses at 1280x720) was never measured.
- Effects 1, reduced motion and large text were checked by tests and a few screenshots, not by play. The bot run never fed (`fed=0`), so long feeding sessions rely on `test_gameplay`/`test_soak`.

## TODO (suggested order)

0. **Performance: round 1 is done and measured (see "Changes in 0.20.2"); round 2 numbers go in the placeholder table there.** Remaining: confirm on the user's machine in play, measure F4, and watch the crowd tail (p95/p99).
   To re-measure: `tests/scenarios/perf_play.gd` (real time), `tests/tools/fig_bench.gd`, `sonar_bench.gd`, `view_bench.gd`; the F3 overlay shows fps, canvas, view, sched and governor lines.
1. **User playtest and a bug list** (next). Fix what they find; add a scenario or test per bug.
2. Listen pass over every baked sound against `html-version/tools/sound-lab.html`; rebake with `tools/bake-audio.mjs` where it differs. Check the bark muffling by ear.
3. Measure F4 (GPU, 64 pulses at 1280x720).
4. Windows export (ask for approval to download templates), then a short release checklist.
5. Menu styling toward the JS look (crooked borders, hand-drawn buttons).
6. Forge editor in F9 (needs spawn overrides in `People.spawn`, which the JS does not have either: design first).
7. Keep fixtures fresh: whenever `html-version/js` changes, rerun `node tools/golden/*.mjs` and the full suite.
8. Repo hygiene follow-ups: the global git ignore hides `*.exe`, so a fresh clone needs the Godot binary downloaded; decide whether to vendor `godot/` (harness) and `skills/` or keep them as is.
