# PARITY.md: fixtures, tolerances, go/no-go results

How the Godot port is checked against the JS game. Commands are run from the port folder; all fixtures are regenerated
from the real `../js` modules with Node (`tools/golden/*.mjs`) and checked by headless GDScript tests
(`project/tests/parity/test_*_parity.gd`). Regenerate a fixture whenever the JS it covers changes.

```
node tools/golden/<name>.mjs                      # rewrite project/tests/fixtures/<name>.json
..\Godot_v4.4.1-stable_win64.exe --headless --path project -s res://tests/run_tests.gd [-- --filter=people]
```

## Fixtures

| Fixture | Generator | Covers | Tolerance |
|---|---|---|---|
| `rng.json` | `golden/rng.mjs` | mulberry32 streams (12 seeds, 4 non-uint32 seeds), stored as integer numerators | exact |
| `raycast.json` | `golden/raycast.mjs` | 1,328 single rays, axis-aligned rays, 12 column casts on `test` and `crypt` | 1e-9 |
| `world_player.json` | `golden/world_player.mjs` | tile/solid/material/blocks/light queries on all maps, door opening, arrivals, 600-step player traces | 1e-9 (light 1e-6) |
| `sonar.json` | `golden/sonar.mjs` | emit with bounces, ray tables, sample2/brightness/age on a point grid at 8 times, height band, prune | 1e-6 (float32 tables) |
| `people.json` | `golden/people.mjs` | 5 scripted runs: 10 min patrol, shuffle, sound and sight reactions, hides, echoes, grab/drink/release/fed | 1e-7 |
| `figure.json` | `golden/figure.mjs` | 482 line-figure scenes (modes x looks x ages x quality x reduced, held victim): FNV-1a hash of the canonical draw-call log | exact hash (args rounded to 1e-3) |
| `acoustics.json` | `golden/acoustics.mjs` | beam, echo levels, bounces, reverb sizing, occlusion, step scaling | 1e-9 |

Scope notes: `people.json` and `figure.json` are generated with Forge, Schedule, Struggle, Figure and Vessels **not**
loaded (that is what Phase 1 ports); they get new fixtures when those modules land.

Godot's JSON parser is not correctly rounded for doubles, so exact data is stored as integers and everything else is
compared with an epsilon.

## Go/no-go checks (PLAN.md)

| Check | Status | Notes |
|---|---|---|
| F1. Reveal maths on screen | **pass** (Phase 1) | `tests/scenarios/f1_readback.gd`, windowed. Per column, the CPU `sample2` + afterglow + lineAlpha is compared with pixels read back from the 640x360 render. Onset is identical to the frame on 9 of 10 columns; fade-curve error 1.3 to 7.4 % of the peak (limit 10 %). Column 216 reads 124 %: a vertical wall-corner line crosses that column, so it is not a shader error. |
| F2. Hand-drawn feel | **needs your review** | Side-by-side shots (Godot left, original `js/render.js` right, same scene, pose and time) are in `docs/shots/phase1/`. The villager outline is identical in pose, position and boil; the wall edge lines match. Not in yet (Phase 2/3): floor and ceiling grid texture, wall material detail, crooked door tilt, post-front wobble. Line weight in the Godot shots is slightly heavier (anti-aliased 1 px line scaled 2x in the window). Regenerate with `tools/ref-server.mjs` + `tools/js-ref.html` (see below). |
| F3. CPU budget | **average pass, tail borderline** | `tests/tools/bench.gd` (headless, town map, 14 villagers, 25 live pulses, figures drawn): average 2.7 ms per frame, p95 8.0 ms, max 12 ms against the 6 ms target. Parts: ray cast / depth buffer 1.4 ms avg (was 5.4 ms before the grid fast path), villagers + echoes 0.4 ms, pulse texture 0.1 ms, figure drawing 0.9 ms avg but 5.3 ms p95 when many echoes are alive. Figure drawing is the thing to optimise if the p95 matters; volumetric figures (Phase 7) will need caching. |
| F4. GPU | pending | 64 pulses at 1280x720 not measured yet. |
| F5. Audio | pending | Baked samples not built yet. |
| F6. Numeric parity | **pass** for ray cast, sonar, RNG, world, player, people (10 min), figures | See table above. |
| F7. Tooling | **pass** | Headless tests, harness `script check`/`scene verify`, windowed `--write-movie` all work from this path (spaces are fine when quoted). |

### F1 method details

- The shader line is anti-aliased and boiled, so the comparison uses line energy (sum of the brightest channel down
  the column over a 9 px window), not the per-pixel peak.
- The wall quads extend 3 px past their top and bottom edge (fragments there are discarded unless they carry line
  colour) so boil jitter cannot push a line out of the face; the floor plane does not write depth for the same reason.
- The arrival flash (white, brighter for 0.12 s) is part of the expected value, as in `render.js`.
- Re-run: `Godot_v4.4.1-stable_win64.exe --path project --rendering-driver opengl3 --write-movie out/F1/f.png --fixed-fps 60 --quit-after 220 -- --scenario=f1_readback` (prints `F1_REPORT` and `F1_ROWS`).

## Known gaps in the Phase 1 slice

- Blood is a plain bar (Night/Hunger are Phase 5); the drink loop follows `startDrink/stepDrink/endDrink` otherwise.
- The held victim uses the plain grapple pose; the struggle pose (`js/struggle.js`) is Phase 4.
- Audio calls are recorded by `AudioDirector` but nothing plays yet.
- Floor: one wavefront ring per pulse only (JS draws wavy dotted arcs, texture and footstep rings: Phase 3).

## JS reference shots (F2)

```
node tools/ref-server.mjs 8766          # serves the repo root and POST /save
# open  http://localhost:8766/___VERSION__GODOT___VERSION___/tools/js-ref.html?scene=villager&frames=42,60,120,192&save=1  in a browser
# PNGs land in out/jsref/. Godot side: ... --write-movie out/villager_test/f.png ... -- --scenario=villager_test
# compose: godot --headless --path project -s res://tests/tools/side_by_side.gd -- <outDir> "<godot.png>|<js.png>" ...
```
