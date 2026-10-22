# Plan: porting Vampires Can't See to Godot 4.4.1

Status: plan only. Nothing is built or measured yet. Written by an Opus planning pass over the JS game.
Read `HOWTO-CLI-ANYTHING-GODOT.md` first for how to drive Godot from the CLI.

All work lives in this folder. The JS game in the repo root is the reference and is not edited.

## Facts about the JS game that shape the plan

- **Walls are drawn as lines, not filled faces.** `js/render.js` `drawWalls` traces one ray per screen column,
  takes brightness from `Sonar.sample2`, and draws top and bottom edge segments plus vertical corner lines.
  It adds jitter ("boil"), a short flash when the wave arrives, and an afterglow fade. The internal frame is 640x360.
- **Brightness is a simple formula.** `sonar.js` `scan` and `sample2` light a point only once the expanding
  radius `(t-t0)*12 cells/s` passes it, and only if it is in the pulse's line of sight (`vis[]`, 720 rays).
  Brightness is `b=(1-age/fade)^2*(1-0.5d/range)*strength*vbeam`. Villager echoes (`people.js` `updateEchoes`)
  are frozen snapshots of pose and position at the moment the wave passed.
- The JS logic is pure functions, so it serves as the reference for automated comparison ("parity") tests.
  The repo already has deterministic draw-log fixture tools (`tools/frame-golden.mjs`, `tools/figure-golden.mjs`,
  `tools/forge-golden.mjs`) to build on.

## Architecture

**World and walls: 3D geometry plus one shader.**
- Build one mesh from the grid map (1 cell = 1 m; JS (x, y) becomes Godot (x, z); JS height z of 0 to 1 becomes Godot y).
- Each wall face has a face-local UV and carries its tile code and material id.
- `sonar_wall.gdshader` is unshaded and black. Per fragment it loops over up to 64 pulses and runs the same
  `sample2` maths (height 0 and 1 rows, line-of-sight lookup, beam, afterglow).
- Lines come from the UV edges (top and bottom of the face, plus corner lines where the cell or face changes),
  with constant screen-space width via `fwidth`.
- Boil is noise on the edge test, stepped in time at the JS boil rate. Flash, the colour ramp (`C_LOW`/`C_MID`/`C_HI`)
  and the depth alpha `lineAlpha` all come from the JS constants.
- Pulse data lives in a 64x2 RGBA32F texture. Line of sight lives in a 720x64 R32F texture; a row is written only
  when a pulse is emitted. The shader reads time from a game-clock uniform, not `TIME`.
- Render into a 640x360 SubViewport, scale it up, and apply grain and vignette as a canvas shader.
- Start with the Compatibility (GL3) renderer: the look is unshaded, and it keeps a web export possible.
- **Fallback (path B):** a 1:1 port of `render.js` drawing with `CanvasItem.draw_*`. It can be tested against the
  existing draw-log fixtures, but it costs more CPU in GDScript.

**Villager echoes: a 2D overlay.**
- Port `posePerson` and `drawLineFigure` (the Effects 0 line figure) to GDScript.
- Draw them on a 2D layer inside the same SubViewport, using JS's own `project()` maths.
- Hide them behind walls using a per-column depth buffer from the GDScript ray caster, exactly as JS `clippedDraw`
  does. Clip to the echo's height band.

**Logic: pure GDScript.**
- `core/*.gd` files are `RefCounted` classes or static functions that never touch nodes, so they run headless.
- Use plain 64-bit floats and `PackedFloat64Array`. Never use Vector2/3 in logic, because Godot vectors are 32-bit
  and would break exact comparison with JS.
- `jsmath.gd` reproduces JS behaviour where it differs:
  - `Math.round` becomes `floor(x+0.5)`;
  - `imul` and `>>>0` use 32-bit masks, so `mulberry32` matches bit for bit;
  - `%` maps to `fmod`.

**Audio: baked samples plus Godot effects.** JS synthesises every sound live with Web Audio.
- Bake each recipe to a few WAV variations (ping, click, footstep variants, guard step, drink, and echo voices
  crisp/hollow/tick/ring/soft plus the person thud).
- Play them through a pool of `AudioStreamPlayer3D` nodes. Use attenuation off for echoes with our own gain from
  `acoustics`, occlusion through `attenuation_filter_cutoff_hz`, and pitch and volume jitter.
- Each zone gets a reverb bus whose room size comes from the Sabine T60 in `data/sounds`.
- Echo delays are queued in an `AudioDirector` and played on frame boundaries (roughly 16 ms precision).
- How to bake, in order of preference:
  1. A Node script that runs `js/audio.js` recipes through `node-web-audio-api` (needs an npm install: **ask the user first**).
  2. A "Bake all" page in this folder's tools that imports `../js/audio.js` read-only and saves the WAVs; the user clicks it once.
  3. A Python port of the recipes.

## Folder layout

```
___VERSION__GODOT___VERSION___/
  HOWTO-CLI-ANYTHING-GODOT.md   PLAN.md
  project/                 Godot root (project.godot)
    autoload/              log.gd config.gd flags.gd clock.gd data.gd bus.gd save_store.gd audio_director.gd
    core/                  pure logic: jsmath rng raycast world sonar ripple acoustics people schedule night
                           hunger meta forge struggle barks listen save_codec coords
    data/                  *.json generated from js/data (do not hand-edit)
    render/                world_mesh_builder.gd pulse_textures.gd echo_layer.gd pose.gd figure_line.gd
                           figure_vol.gd shaders/*.gdshader
    game/                  game.tscn game.gd (integrator) player_controller.gd input_setup.gd
    ui/  audio/(wav, bus_layout.tres)
    tests/                 run_tests.gd  unit/test_*.gd  parity/test_*_parity.gd  fixtures/*.json  scenarios/*.gd
  tools/   (.gdignore)     export-data.mjs  golden/*.mjs (JS fixture generators)  bake-audio.*  run-tests.ps1  shots.ps1
  docs/    PORT.md (module map, update order)  PARITY.md (fixture list, tolerances)
  out/     screenshots, logs (gitignored)
```

**Conventions**
- Static typing everywhere. One `class_name` per core file, named after its JS module.
- Each `core` function's comment links to the JS function it ports.
- Signals are connected in `_ready`, because the harness can't edit connections.
- The input map is built in code (`input_setup.gd`).
- Materials and shaders are separate `.tres`/`.gdshader` files or assigned in code, because the harness can't edit sub-resources.
- Node trees are mostly built in code, keeping `.tscn` files minimal.
- `.gitignore` covers `.godot/`, `out/` and `.cli-anything/`.

## Testing and verification

**Test runner.**
- Plain `tests/run_tests.gd` (extends SceneTree). It finds `test_*.gd` files, runs their `test_` methods, prints a
  one-line JSON summary, and quits with exit code 1 on any failure.
- No add-ons needed. GUT or GdUnit4 would be a download, so only with the user's approval.
- Command: `Godot_v4.4.1-stable_win64.exe --headless --path project -s res://tests/run_tests.gd -- --filter=sonar`.

**Parity tests against the JS logic.**
- `tools/golden/*.mjs` loads the real `../js/*.js` modules in Node 22 and writes deterministic JSON fixtures into
  `project/tests/fixtures`:
  - ray-cast hit grids;
  - `sonar` `fillRays`, `sample2` and `scan` over a grid of points and times, plus `pickReflectors`;
  - `people` traces (seeded, 10 minutes, per-second state and position, echoes made per pulse);
  - `schedule.build`;
  - hunger, night and meta operation sequences;
  - `save` sanitize, migrate and checksum cases, including a real JS export text;
  - `Forge.generate` looks;
  - the line-figure draw log.
- GDScript tests compare to 1e-9 for exact maths and a small epsilon for long simulations. Regenerate fixtures
  whenever the JS changes.
- `export-data.mjs` converts `js/data/*.js` to JSON. The few functions inside the data (`acoustics.beam`,
  `visFactor`) are ported into `acoustics.gd`.
- For drawing, an abstract `Canvas` sink has two versions: a real one using `draw_*`, and a recording one whose log
  is compared to the JS fake-context log with a tolerance.

**Checking the shader on screen.**
- Scenario scripts take `-- --scenario=NAME`. Each sets the pose, fires a ping at a fixed time and uses the fixed time step.
- Run windowed: `--path project --rendering-driver opengl3 --write-movie out/NAME/f.png --fixed-fps 60 --quit-after N`.
  PNGs are viewed with the Read tool.
- The scenario also reads pixels back at the screen positions of known wall points and compares their brightness over
  time with GDScript `sample2`: onset time to within 1 frame, the fade curve to within 10%.
- JS reference shots: the Browser pane opens `index.html?debug=1`, and `javascript_tool` uses the debug hooks to set the
  same pose and ping time before screenshotting. Use the same four scenes as `frame-golden.mjs`: crypt start, town
  street, window wall, dawn.

**How the harness is used.**
- Run as `python -m cli_anything.godot --json -p project ...` (see the HOWTO). No pip install step is needed on this machine.
- Use it for:
  - `project new --renderer compatibility` and `project set` (window 1280x720, stretch mode, main scene);
  - simple `scene new` / `add-node` / `set-prop` / `attach-script`;
  - `script check` after every `.gd` edit;
  - `scene verify` after `.tscn` edits;
  - `run --frames 120` as a headless smoke run;
  - `script run tests/run_tests.gd` as an alternative test entry;
  - `render` as the screenshot wrapper (needs the GPU);
  - `export pack` later.
- Write `.gd` and `.gdshader` files directly, not through `script new`. Hand-written `.tscn` files with sub-resources
  must be checked with `scene verify`.
- Headless runs can't compile shaders. Every shader check needs a windowed run.

## Phase 0: scaffold

Create the project with the harness, the test runner, `jsmath`/`rng`/`coords`, the `export-data` and golden tools,
and the first fixtures (ray cast, mulberry32).

**Done when:** the test runner passes with ray-cast and RNG parity, `scene verify` passes on the main scene, and a
single `--write-movie` PNG is produced on this machine (proves the GPU screenshot loop works).

## Phase 1: vertical slice on the `test` map

The `test` map is 24x16 with doors, a coffin and a three-villager path table; the slice uses only `paths[0]`.

1. `world.gd`: a subset of `load`/`validate` covering walls, floors, `@`, `P`, materials and `isSolid`/`blocks`/`materialAt`/`tileAt`.
2. `raycast.gd`: a full port (it's 91 lines).
3. `player.gd` and `player_controller.gd`: WASD/arrows, captured mouse, `DEFAULT_CFG` speeds, the corner collision test.
4. `sonar.gd`:
   - `create`/`emit`/`emitSound` (bounces may be off in the slice), `fillRays` (720 rays);
   - `scan`/`sample2`/`visibleFrom`/`litAt`/`prune`/`echoDelay`/`pickReflectors`/`cooldownLeft`;
   - the mouth beam from `acoustics`.
5. `pulse_textures.gd` and `sonar_wall.gdshader` (walls and ceiling edges). Add a minimal floor shader with a
   wavefront ring band at radius `rr` so the travel speed reads on the ground.
6. `people.gd` subset: `create` with path walking, `updateEchoes`, `echoBrightness`/`echoAge`,
   `feedTarget`/`grab`/`drink`/`release`/`markFed`. Port `heightBandOf`.
7. `echo_layer.gd`, `pose.gd` and `figure_line.gd` (Effects 0), with depth-buffer occlusion and height-band clipping.
8. `game.gd` integrator, in the same order as JS `update` -> `simulateWorld` -> `frame` (document in `docs/PORT.md`):
   - left-click or Space pings, honouring the 0.8 s cooldown;
   - holding right-click or R grabs and drinks, following `startDrink`/`stepDrink`/`endDrink` (no `struggle.js` yet), with a blood bar;
   - E releases.
9. `AudioDirector`: ping, delayed wall echoes per reflector (material voice, pan from angle, gain from `acoustics`),
   the person-echo thud at `PERSON_ECHO_GAIN`, footsteps, drink loop, one reverb bus.

**Done when:**
- you can walk the map and ping, and the walls reveal at 12 cells/s and fade over 3 s;
- the villager shows as a fading line outline where it stood when the wave passed, and pinging again shows it moved;
- the grab and drink loop works;
- echoes are heard late for far walls and come from the correct side;
- the sonar, people-echo and ray-cast parity tests pass;
- screenshots at 0.2, 0.5, 1.5 and 3 s after a ping sit beside the JS shots;
- it holds 60 fps.

## Go/no-go checks (decided with the user after phase 1)

| Check | Pass criteria | If it fails |
|---|---|---|
| **F1. Reveal maths on screen** | Read-back brightness matches `sample2` onset (to 1 frame) and fade (within 10%). Line positions within 2 px at 640x360 vs JS. | Fix the shader; if it can't be fixed, switch to path B. |
| **F2. Hand-drawn feel** | Line weight, taper, boil, the arrival flash, the crooked door tilt and the wobble after the front passes look like the JS in a side-by-side and the user approves. | Hybrid: shader for brightness, `ImmediateMesh` ribbon lines generated per column; or path B. |
| **F3. CPU budget** | 640-column ray cast + depth buffer + 30 villagers updating + 8 line echoes + pulse texture upload <= 6 ms per frame (`Time.get_ticks_usec` benchmark). A volumetric figure must fit about 4 per frame in the JS 2.5 ms budget. | Cache figure geometry per echo, use fewer columns, drop to the line figure under load (as JS does). C# needs the .NET Godot build, which isn't installed; GDExtension is a last resort. |
| **F4. GPU** | 64 pulses at 1280x720 hold 60 fps. | Render at 640x360 only, pack pulse data more tightly. |
| **F5. Audio** | Echo timing jitter <= 1 frame. Panning and occlusion are correct. Baked vs Web Audio is indistinguishable on 5 sounds, or the user accepts the difference. | Move to `AudioStreamGenerator` for echoes only (sample-accurate timing). |
| **F6. Numeric parity** | mulberry32, ray cast and sonar match exactly. A 10-minute people simulation stays within epsilon. | Find where GDScript diverges (rounding, 32-bit floats, iteration order). |
| **F7. Tooling** | Headless tests, the harness verify and windowed `--write-movie` all work reliably from this path. | Move the project to a path without spaces. |

## Roadmap and JS -> Godot mapping

| Phase | JS source | Godot target | Done when |
|---|---|---|---|
| 2. World and data | `world.js`, `data/maps.js`, `raycast.js`, door and map-change code in `game.js`, `drawSprite`/`drawDoor`/`drawWindow`/`drawMat` in `render.js` | `core/world.gd`, `data/maps.json`, `render/world_mesh_builder.gd` (doors as separate meshes, window glow, prop sprites in the echo layer), `game/doors.gd` | `validateAll` errors match the JS fixture for every map; you can walk through doors and links between all maps; window and door screenshots reviewed. |
| 3. Full sonar and acoustics | `sonar.js` (bounces, `heightBand`, `wallArc`, `enclosure`, `strongestEcho`), `ripple.js`, `data/sounds.js`, `drawRipple`/`drawAirRings`/`drawWallVibe`/`drawFloorTexture`/`drawFloorFront`/`drawFootRings`/`drawRings`/`drawWallArcs` in `render.js`, `emitSound`/`panTo`/`occludedTo`/`stepMaterial` in `game.js` | `core/sonar.gd`, `core/ripple.gd`, `core/acoustics.gd`, shader passes (floor and ceiling texture, rings, arcs), `AudioDirector` occlusion and zone reverb | `sonar.test`-equivalent parity passes; the four golden scenes reviewed; echo audio A/B approved. |
| 4. Villagers, routines, AI | `people.js` (all), `schedule.js`, `forge.js`, `data/archetypes.js`, `barks.js`, `listen.js`, `data/voices.js`, `struggle.js` | `core/people.gd`, `core/schedule.gd`, `core/forge.gd`, `core/barks.gd`, `core/listen.gd`, `core/struggle.gd`, subtitles UI | Seeded `tools/sim.mjs`-style trace matches (positions and states each second); the night routine plays out; listening at windows works. |
| 5. Feeding, hunger, night | `hunger.js`, `data/hunger.js`, `night.js`, powers / rocks / heartbeat / blood-pool code in `game.js` | `core/hunger.gd`, `core/night.gd`, `game/feeding.gd`, `game/powers.gd` | Operation-sequence parity passes; a full night is playable from dusk to dawn, sleeping at the crypt or a safe spot. |
| 6. Runs, meta, saves | `meta.js`, `data/upgrades.js`, `save.js`, snapshot and shop code in `game.js` | `core/meta.gd`, `core/save_codec.gd` (same envelope `{app,kind,v,game,sum,data}`, checksum, sanitize and migrate), `autoload/save_store.gd` (`user://vcs.run.json`, `user://vcs.meta.json`), shop and boon UI | A JS-exported save imports into Godot and resumes the same state; the 5-night run, Essence shop and boons work; autosave works. The browser tab lock is replaced by a single-instance check. |
| 7. Figures in full and character creator | `figure.js`, `data/vessels.js`, the volumetric pose branch of `render.js`, `tools/character-creator*.js` | `render/figure_vol.gd`, `render/vessels.gd`, `ui/creator.tscn`, `core/creator.gd` (sanitize, `LOOK_RANGES`) | `figure-anatomy` assertions ported (vessels inside bodies); the line-figure draw log matches the JS fixture; the creator saves and loads JSON; the F3 budget holds. |
| 8. Interface and polish | `hud.js`, `icons.js`, `postfx.js`, `config.js`, `flags.js`, `devpanel.js`, `input.js`, `log.js`, `checks.js`, `system.js` | `ui/*`, `autoload/config.gd`, `autoload/flags.gd`, `autoload/log.gd`, the postfx shader, the F9 dev panel with tunables, F3 overlay, M map | README and MANUAL feature checklist complete; wobbly-lines toggle, reduced motion and large text work. |
| 9. Audio complete and export | rest of `audio.js` (ambience beds, voices, heartbeat, guard step), `data/sounds.js` | full baked sample library, `AudioDirector` beds | Every `sound-lab` sound has a Godot equivalent the user approved; a Windows build runs (export templates are a download: ask first). |

## Biggest risks

1. **The shader may not look hand-drawn enough (F2).** The main go/no-go; path B is the fallback.
2. **GDScript speed for the volumetric figures.** `figure.js` is 2,000 lines, and GDScript is roughly 10x slower than the browser's JS engine.
3. **Audio fidelity.** Web Audio synthesises everything live, so baking loses some variation, and frame-quantised echo timing may be audible.
4. **`game.js` is a 4,989-line integrator whose update order matters.** Port it in the exact order and document the order.
5. **Parity can break silently.** Godot's 32-bit vectors, rounding differences and later JS changes all cause drift; regenerate fixtures and keep logic in plain floats.
6. **Spaces in the path.** Always quote paths.
7. **Things only the engine does.** Shaders don't compile headless, and screenshots need the GPU and a window.

## Critical JS files

- `js/sonar.js` (the brightness maths the shader must reproduce)
- `js/render.js` (`drawWalls` look, `project`/`clippedDraw`, `drawLineFigure`)
- `js/people.js` (echo snapshots, feeding, AI)
- `js/game.js` (update order, the drink loop, sound emission)
- `tools/frame-golden.mjs` (template for the JS fixture generators)
- Also read: `README.md`, `whatwedid.md`, `claude/TODO.md`, `docs/MODULAR.md`, `js/raycast.js`, `js/player.js`,
  `js/save.js`, `js/data/maps.js`, `js/data/sounds.js`, `tests/frame-parity.test.js`, `tests/raycast.test.js`.

## Approvals needed from the user

- `npm install node-web-audio-api` (audio baking), or use option 2 or 3 instead.
- GUT / GdUnit4 (not planned).
- Export templates (phase 9).
