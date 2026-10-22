# AI handoff: Godot port of "Vampires Can't See"

Read this first. It is written for the next AI session (or developer) picking the port up. Status: **alpha, feature-complete against the
JS game except the items under "NOT included"**. Nothing here has been judged by a person's eyes or ears yet (see "Unverified").

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
| All tests (~9 min, 84 tests, 1.1M checks) | `Godot_v4.4.1-stable_win64.exe --headless --path project -s res://tests/run_tests.gd` |
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

## NOT included (differences from the JS game)

- **Windows/any export.** Needs the Godot export templates (a download). Ask the user first, then `export_presets.cfg` and `godot --export-release`.
- **Adaptive render quality and the figure-budget cap.** JS lowers `quality`/`matDetail` when fps is low and caps effects to Low for 10 s after repeated budget overruns (`figureFrameEnd`, `fxCap`).
  The port keeps quality 3 and only applies the per-frame 2.5 ms volumetric figure budget (extra villagers fall back to line figures). Add a frame-time monitor in `echo_view.gd` if low-end machines need it.
- **`renderScale` and `dragLook` settings** (fixed 640x360 frame, mouse always captured while playing). **Multi-tab save lock** (not applicable).
- **Forge editor and `?sys=` / `?tun=` URL flags** in the dev panel (F9 has flags, tunables, spawner, clock/blood/essence shortcuts, map jump, log tail only). **Sched lines** in the F3 overlay.
- **JS test hooks** (`Game.debug*`) and the Playwright smoke test: replaced by scenarios, the soak test and `bot_play`. **JS tools** (`sound-lab`, `figure-sheet`, `sim.mjs`) stay JS-only.
- **Notice modal** (optional check failures are shown as title labels), menu hover/focus styling beyond Godot defaults, icons beyond shop/boon/gift/guide cards.
- **GUT / GdUnit4** (not approved; tests use the in-repo runner `tests/run_tests.gd`).
- Itch.io packaging (`html-version/dist`) and the web `update.bat`.

## Unverified (needs a person)

- **Audio (go/no-go F5):** baked samples, ambience beds, heartbeats, breath, live speech: all play, none has been listened to. Echo timing is frame quantised.
- **Hand-drawn look (F2):** side-by-side with the JS is in `docs/shots/phase1/`; line weight in Godot is slightly heavier; the user has not signed off.
- **Performance on other machines:** measured on a GT 1030: canvas draw about 2.9 ms/frame average in town, GPU about 1.4 ms. F4 (64 pulses at 1280x720) was never measured.
- Effects 1, reduced motion and large text were checked by tests and a few screenshots, not by play. The bot run never fed (`fed=0`), so long feeding sessions rely on `test_gameplay`/`test_soak`.

## TODO (suggested order)

0. **PERFORMANCE (reported by the user after the alpha build): the game is very laggy in play.** Top priority. Not reproduced or profiled yet. Suspects, roughly in order:
   (a) the volumetric figures plus the vessel overlay since they went in (`echo_layer.gd`, `figure_vol_draw.gd`, `vessel_draw.gd`; each figure issues thousands of canvas calls and `DrawCanvas.fill` now triangulates polygons every frame);
   (b) `DrawCanvas` itself: ordered ops, `Geometry2D.intersect_polygons` / `triangulate_polygon` per fill, `draw_polyline` per stroke, all redrawn every frame by `EchoView` and `HudView`;
   (c) no adaptive-quality governor (see NOT included): quality stays 3 and effects 2 on weak GPUs; (d) `MapView`, `DevPanel`, `IconRect` run `_process` redraws only when visible, check anyway;
   (e) `step_heartbeats` and vessel echoes keep more echoes alive (`People.vessels_on`), and the title/menu screens redraw the crypt every frame.
   Start by measuring: F3 overlay shows fps, canvas us and figure counts; `tests/scenarios/perf_town.gd` prints per-section cost; try Effects 0/1 and `vis.vessels` off in F9 to bisect.
   Likely fixes: cache polygon triangulation or skip fills at distance, lower the vol-figure budget and depth, cap vessels to the nearest figure, drop `halo`/edges at quality 2, and port the adaptive quality governor.
1. User playtest and a bug list (after the lag is fixed). Fix what they find; add a scenario or test per bug.
2. Listen pass over every baked sound against `html-version/tools/sound-lab.html`; rebake with `tools/bake-audio.mjs` where it differs.
3. Adaptive quality / effects cap (see NOT included), then measure F4.
4. Windows export (ask for approval to download templates), then a short release checklist.
5. Menu styling toward the JS look (crooked borders, hand-drawn buttons); notice modal.
6. Forge editor in F9 (needs spawn overrides in `People.spawn`, which the JS does not have either: design first).
7. Keep fixtures fresh: whenever `html-version/js` changes, rerun `node tools/golden/*.mjs` and the full suite.
8. Repo hygiene follow-ups: the global git ignore hides `*.exe`, so a fresh clone needs the Godot binary downloaded; decide whether to vendor `godot/` (harness) and `skills/` or keep them as is.
