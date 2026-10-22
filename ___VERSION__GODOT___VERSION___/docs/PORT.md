# PORT.md: JS module -> GDScript map

Update this as modules land. Plan: `../PLAN.md`. Driving Godot: `../HOWTO-CLI-ANYTHING-GODOT.md`.

| JS | GDScript (`project/`) | Status |
|---|---|---|
| (JS number helpers: `Math.round`, `>>> 0`, `Math.imul`, `%`) | `core/jsmath.gd` | done, unit tested |
| `mulberry32` (people.js, meta.js, hunger.js, forge.js, game.js) | `core/rng.gd` | done, bit-exact parity |
| world (x, y, z) -> Godot (x, z, y) | `core/coords.gd` | done |
| `world.js` `isSolid` (closed doors, out of bounds solid) | `core/grid_world.gd` (Phase 0 stand-in) | replace with `core/world.gd` in Phase 1 |
| `raycast.js` (`cast`, `castOne`; `hitOne`/`distOne` not yet) | `core/raycast.gd` | done, parity on `test` and `crypt` |

## Tools

- `node tools/golden/rng.mjs` -> `project/tests/fixtures/rng.json`
- `node tools/golden/raycast.mjs` -> `project/tests/fixtures/raycast.json`
- `node tools/export-data.mjs` -> `project/data/*.json` (functions in data are dropped and listed; port by hand)
- Tests: `Godot_v4.4.1-stable_win64.exe --headless --path project -s res://tests/run_tests.gd -- --filter=rng`

## Gotchas found so far

- Godot's JSON parser is not correctly rounded for doubles (off by 1 ulp on some values). Store exact data as
  integers in fixtures (RNG uses `draw * 2^32`); use an epsilon (1e-9) for everything else.
- GDScript has no `trunc()`; `JsMath.u32` uses floor/ceil.
- Headless test files must `extends TestCase`; the runner runs every `test_*` method in `tests/**/test_*.gd`.
- Shell heredocs with many files failed once in Git Bash; write files with the Write tool.
