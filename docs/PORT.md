# PORT.md: JS module -> GDScript map

Update this as modules land. Plan: `PLAN.md`. Driving Godot: `HOWTO-CLI-ANYTHING-GODOT.md`.

| JS | GDScript (`project/`) | Status |
|---|---|---|
| (JS number helpers: `Math.round`, `>>> 0`, `Math.imul`, `%`) | `core/jsmath.gd` | done, unit tested |
| `mulberry32` (people.js, meta.js, hunger.js, forge.js, game.js) | `core/rng.gd` | done, bit-exact parity |
| world (x, y, z) -> Godot (x, z, y) | `core/coords.gd` | done |
| `world.js` `load` (walls, floors, doors, props, materials, spots; no validate, zones or light grid yet) | `core/world.gd` | done for slice, parity on all 3 maps |
| `world.js` `isSolid` stand-in for ray-cast tests | `core/grid_world.gd` | test helper |
| `player.js` | `core/player.gd` | done, 600-step traces match |
| `sonar.js` (create, emit, emitSound with bounces, fillRays, scan, sample2, heightBand, prune, pickReflectors...) | `core/sonar.gd` | done; strongestEcho/enclosure/wallArc/hitInfo later |
| `data/sounds.js` acoustics functions (beam, visFactor, echoLevel, gameAmp, personAmp) | `core/acoustics.gd` | subset done |
| `data/*.js` | `project/data/*.json` via `core/game_data.gd` | done |
| `raycast.js` (`cast`, `castOne`, `hitOne`, column offsets, depth columns) | `core/raycast.gd` | done, parity on `test` and `crypt` |
| `world.js` zones, light grid, props, validate | `core/world.gd`, `core/world_validate.gd` | done, parity on all maps |
| `people.js` (walkers, reactions, hides, echoes, feeding hooks, **Forge/Schedule villagers, routes, chats, spawn/despawn/alter**) | `core/people.gd` | done; `people.json` (plain, `noForge`) and `people_sched.json` (467k checks) |
| `schedule.js`, `forge.js`, `data/archetypes.js` | `core/schedule.gd`, `core/forge.gd` | done, parity (71k checks) |
| `data/voices.js` (syllable lines, subtitles, voices) + `speakLength` | `core/voice_data.gd` | done, parity |
| `barks.js` | `core/barks.gd` | done, parity over three town runs |
| `listen.js` | `core/listen.gd` | done, parity (find window, subtitles, a listening session) |
| `struggle.js` | `core/struggle.gd` (+ `render/pose.gd` branch, `Pose.use_struggle`) | done, 4,050 poses and 724 draw-log scenes match |
| `night.js`, `hunger.js` | `core/night.gd`, `core/hunger.gd` | done, parity (152k checks) |
| `meta.js`, `save.js`, `js_json` printing | `core/meta.gd`, `core/save_codec.gd`, `core/js_json.gd` | done, parity (JS-exact checksums) |
| `ripple.js` boil table and mask | `core/ripple.gd` | done; ring spawning is Phase 3 |
| `render.js` pose/figure line | `render/pose.gd`, `figure_line.gd`, `echo_layer.gd`, `draw_canvas.gd`, `recording_canvas.gd` | done, 482 + 724 scenes match |
| `render.js` sprites, markers, props, floor and ceiling canvas effects | `render/sprites.gd`, `render/floor_fx.gd` (+ GPU rings in `shaders/sonar_floor.gdshader`) | done, hash parity |
| `render.js` walls, floor, doors, windows, materials | `render/world_mesh_builder.gd`, `shaders/sonar_*.gdshader` | done for slice (see PARITY.md F1/F2) |
| `game.js` update order, drink loop, sound emission, transitions | `game/game.gd` | done (see below) |
| `game.js` runs: beginRun, endRun, boons, gifts, sleep, nextNight, stepNight, stepForge, snapshot, saves | `game/run_flow.gd` | done; `tests/flow/test_run_flow.gd` plays 5 nights to a win, the sun loss and a pause/continue round trip |
| `game.js` powers (shriek, mist, still), rocks | `game/powers.gd` | done |
| `data/vessels.js`, render.js vessel overlay, game.js `stepHeartbeats` / `victimVessel`, people.js vessel branches | `core/vessels.gd`, `render/vessel_draw.gd` (+ `FigureVolDraw.draw_flush`), `game.gd` `step_heartbeats`, `core/people.gd` (`vessels_on`, echo snapshot fields), `core/flags.gd` (`vis.vessels` + tunables) | done: `vessels.json`, `people_vessels.json`, `vessels_draw.json` (281 draw-log scenes incl. window mute and the held victim) |
| `Audio.setPingStyle` (old bip ping) | `audio/audio_director.gd` `ping_bip`, baked `pingbip_*` | done |
| `checks.js` | `core/checks.gd` (Godot equivalents), shown as notices or the error screen | done |
| `figure.js` (volumetric figure), render.js vol pose branch and drawPerson vol path | `render/figure_vol.gd` (geometry, queries), `render/figure_vol_draw.gd` (draw, details, extras, grab arms), `render/pose.gd` (vol tweaks, slots 24/25), `render/echo_layer.gd` (rim light, 2.5 ms budget, silhouette rings) | done, 555 draw-log scenes match (`figure_vol.json`). `drawFlush` and `data/vessels.js` (flag `vis.vessels`, off by default) are not ported |
| `hud.js`, `icons.js` | `render/hud_draw.gd`, `render/icons.gd`, `ui/hud_view.gd` (inside the 640x360 viewport), `ui/hud.gd` (window overlay: subtitles, debug, warm halos) | done, 515 draw-log entries match |
| `postfx.js` | `render/shaders/postfx_grade.gdshader`, `postfx_overlay.gdshader` | done (bloom, dusk/dawn grade, vignette, grain) |
| `config.js` | `core/config.gd` (schema, sanitize, `user://` file), settings panel in `ui/menus.gd` | done |
| tutorial hints | `game/tutorial.gd` | done |
| `drawWarm` (Warm Sense halos) | `ui/hud.gd` `_warm_halos` | done (window-resolution radial gradients) |
| menus (title, shop, stats, pause, boon/gift, run end, settings, guide, export/import) | `ui/menus.gd`, `ui/icon_rect.gd` (hand-drawn icons on cards) | done, plain Godot controls over the crypt title (`render/title_draw.gd`) |
| `log.js` | `core/log.gd` | done (ring buffer, report); fatal error screen in `ui/menus.gd` |
| `flags.js`, `devpanel.js` (trimmed) | `core/flags.gd`, `ui/dev_panel.gd` (F9, debug builds) | done for the flags the port has; vessels and the Forge editor are not ported |
| `Render.drawTopDown` (M) | `ui/map_view.gd` (debug builds) | done, no parity test |
| `tools/character-creator-core.js` + page | `core/creator.gd` (logic), `ui/creator.gd` (screen, title menu button) | logic parity: `creator.json` (8k checks) |
| `audio.js` samples, one-shots, ambience beds, fire, breath, heartbeat, live speech | `audio/audio_director.gd`, `audio/speech_synth.gd`, `tools/bake-audio.mjs` | done; unheard by me (F5) |

## Tools

- `node tools/golden/rng.mjs` -> `project/tests/fixtures/rng.json`
- `node tools/golden/raycast.mjs` -> `project/tests/fixtures/raycast.json`
- `node tools/golden/sonar.mjs` -> `sonar.json`; `node tools/golden/world_player.mjs` -> `world_player.json`
- `node tools/export-data.mjs` -> `project/data/*.json` (functions in data are dropped and listed; port by hand)
- Tests: `Godot_v4.4.1-stable_win64.exe --headless --path project -s res://tests/run_tests.gd -- --filter=rng`

## Gotchas found so far

- Godot's JSON parser is not correctly rounded for doubles (off by 1 ulp on some values). Store exact data as
  integers in fixtures (RNG uses `draw * 2^32`); use an epsilon (1e-9) for everything else.
- GDScript has no `trunc()`; `JsMath.u32` uses floor/ceil.
- Headless test files must `extends TestCase`; the runner runs every `test_*` method in `tests/**/test_*.gd`.
- Shell heredocs with many files failed once in Git Bash; write files with the Write tool.
- GDScript built-ins that collide with JS helper names (`hash`, `wrap`, `move_toward`, `hypot`): use `hash2`, `envelope`, `walk_toward`, `_hypot`.
- New `class_name` files need `godot --headless --path project --import` once before tests can see them.
- The Game node can be built headless for tests: `Game.manual_boot = true; var g = Game.new(); g.boot()` with `Game.test_storage` set to a `SaveCodec.MemoryStorage`.
