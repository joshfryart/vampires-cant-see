# AI handoff: Godot port of "Vampires Can't See"

Read this first. It is written for the next AI session (or developer) picking the port up. Status: **alpha, feature-complete against the
JS game (version 0.20.2) except the items under "NOT included"**. Nothing here has been judged by a person's eyes or ears yet (see "Unverified").

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
| All tests (~9 min, 106 tests, 1.1M checks) | `Godot_v4.4.1-stable_win64.exe --headless --path project -s res://tests/run_tests.gd` |
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
