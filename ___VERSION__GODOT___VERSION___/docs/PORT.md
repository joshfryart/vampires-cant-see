# PORT.md: JS module -> GDScript map

Update this as modules land. Plan: `../PLAN.md`. Driving Godot: `../HOWTO-CLI-ANYTHING-GODOT.md`.

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
| `raycast.js` (`cast`, `castOne`; `hitOne`/`distOne` not yet) | `core/raycast.gd` | done, parity on `test` and `crypt` |

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
