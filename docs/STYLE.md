# Wall and line style: the Ink-Etched hybrid (spec, 0.21.x)

Scope: trek stages hollow, wood, moor, road, inn. The classic maps, the tutorial and later stages keep today's look, and the parity hash suites must not change. The style is **B's smooth contour, dark fills and one stroke family**, carrying **A's sparse, world-anchored detail in today's blue-white ramp**. The cobblestone look comes from the `code == 35` stone branch in `render/shaders/sonar_wall.gdshader`: two courses per cell, vertical joints, slanted ticks, and a vertical line at every face end (`COLOR.r/g`, FLUSH 0.35). All of it goes for natural walls.

**The wall renderer** is the 3D mesh (`WorldMeshBuilder.build` -> `MeshInstance3D` + `sonar_wall.gdshader`, `game.gd _show_map_mesh`), not the raycaster. `Raycast.depth_columns` only fills `rs.zbuf` / `rs.tch`, which clip canvas sprites, critters and figures (`EchoLayer.clipped_draw`). Sonar (`Sonar.fill_rays` -> `vis`, `vnorm`, `vmat`) is a pure grid DDA.

Ink mode is on when the current world has a non-empty `wall_style` (from the stage row's `wallStyle`, see below). Everything else stays classic.

## 1. Tokens

All values are in px at 640x360 and are multiplied by `rs.wscale` on the canvas.

| Token | Classic (unchanged) | Ink |
|---|---|---|
| Ramp (strokes) | C_LOW 5B7FD6, C_MID CFE3FF, C_HI F2F8FF (`fade_color`) | same ramp, kept for information |
| Flash colour (age < 0.12 s) | FFFFFF | bone FFFCF4, halo FFECD2 |
| Fill (`INK_FILL`) | none | #040306 for wall faces, closed props, critter bodies and figure head/torso |
| Lit body | none | C_MID x 0.06 x sqrt(b) / (1 + 0.08 d), quality >= 2 |
| Contour width | 1.0, 1.5 if d < 1.5 | `1.25 + 0.5 * clamp((2.5 - d) / 1.5, 0, 1)` (continuous, no pop) |
| Detail width (strata, cracks, grain, floor marks) | 0.7 | 0.8 (rock strata 0.7) |
| Thin / taper floor | 0.7 | 0.35 x w |
| Figure outline / limbs | lw 1.0 / 1.5 (lock 1.6), limbs x1.7 | contour width (lock 2.0), limbs x1.6 |
| Flash widening | +0.5 f | +0.5 f |
| Boil | 0.8 px walls, 0.7 sprites | 0.5 px on contours and sprites; 0 on strata; 0.3 on cracks; 0 under reduced motion |
| Halo | quality 3, a >= 0.6: 3.4 w at 0.2 a | quality 3, a >= 0.6: 3.0 w at 0.16 a; flash halo at quality >= 2 (warm, 0.35 a) |
| Alpha quantisation | 8 levels | 8 levels (keeps the etched feel) |

**Taper rule:** open strokes are drawn as three pieces. The first and last 14% of the arc length use 0.6 w and the middle uses w. In the shader the width is continuous: `w * clamp(min(t, 1 - t) / 0.14, 0.35, 1)`. Closed strokes and strokes shorter than 10 px do not taper.

**Brightness curve `ping_lit(b, d)`** (ink): `min(1, max(1.15 b^0.65, 0.2 + 0.6 b)) / (1 + 0.10 d)`, plus `0.6 (1 - age / 0.12)` during the flash. Details use 0.6 x that and are gated at b >= 0.2. Classic keeps `line_alpha`.

**Per-material parameters** (A = maximum inward displacement in cells; r = convex rounding radius; rc = concave fillet radius; lip = top-edge height as a fraction of the wall, with its jag):

| Style id / name | Tiles | A | r / rc | Noise freq | Lip | Detail (quality 3) |
|---|---|---|---|---|---|---|
| 1 rock | hollow `#` | 0.18 | 0.30 / 0.15 | 0.9 /cell, 3 oct | 1.0, jag ±0.035, freq 2.5 | strata + lip cracks |
| 2 thicket | wood `#`, road `#` hedge | 0.20 | 0.30 / 0.15 | 1.6 | 0.85-1.0, spiky peaks every 0.25 | leaf V-ticks in the upper 40%, 2 per cell; bottom edge broken 15% |
| 3 gorse | moor `#` | 0.15 | 0.30 / 0.15 | 1.6 | 0.70-0.85, spikes ±0.08 at 4 /cell | thorn ticks at 60°, 3 per cell, upper half; 10% tint toward FFE9A8 |
| 4 trunk | wood `W`, road `W` (bramble hollow) | 0.04 | 0.30 / 0.10 | 0.6 | no top edge (the trunk leaves frame) | bark: 2 wavy vertical lines per cell, 0.3-0.7 h; root flare (bottom edge lifts 0.05 at silhouettes) |
| 5 cairn | moor `B` | 0.10 | 0.30 / 0.10 | 1.2 | conical: 0.75 at the sides, 1.0 at the loop's mid-arc | 3-4 stacked lens courses, staggered, narrowing upward |
| 6 milestone | road `B` | 0 | 0.12 / 0 | - | dome 0.75 + 0.1 | one incised line at 0.6 h, three mile ticks in the centre |
| 7 fence | road `I`, moor `I` (gibbet variant) | 0 | 0 / 0 | - | no top edge | rails at 0.3 and 0.7 h, posts at face ends and the middle, finials; gibbet: one post plus an arm at 0.9 h |
| 8 timber | inn `W` | 0 | 0.05 / 0 | - | 1.0 straight | weatherboard every 0.2 h, studs every 2 cells, corner posts at convex corners only (no flush lines) |
| 9 drystone | inn `#` | 0.05 | 0.15 / 0.05 | 1.0 | 1.0, jag ±0.015 | 3 irregular courses, 1 staggered joint per 0.8 cell |
| 0 built/legacy | doors `D` `G`, windows `w`, classic maps | 0 | 0 | - | today's | today's branches, unchanged |

**Water `~`** is a floor tile (rays pass). In `sonar_floor.gdshader` it gets 2-3 short horizontal sheen dashes per cell in the bounce blue 7FA6FF. They brighten as the front passes and keep the existing ring.

**Floors:** road and inn-yard `.` cobble become true setts (3 staggered rows of rounded rects per cell, aligned with the road). The hollow floor (`stone`, drawn today as brick joints) becomes rubble (2 pebbles and 1 scratch per cell).

## 2. Smooth walls: data model

**Derivation** (`ContourField.build`, pure, headless). The method is boundary-loop offsetting. It is equivalent to marching squares on `phi = grid SDF + bounded noise`, but every vertex keeps an exact grid anchor, and the topology cannot change: no merged diagonals, no closed passages.

1. Chain the exposed faces of solid cells (out of bounds counts as solid) into closed loops with solid on the left. At a checkerboard saddle the open space connects: the loops split, and r is limited to 0.1 there.
2. Resample each loop every 0.25 cell, with a forced vertex at every grid corner. Each vertex stores an **anchor** `a` (a point exactly on the grid boundary), the **grid normal** `n_g` (the average of the two faces at a corner), and a style (the anchor's solid cell, looked up through `wall_style[tile char]`).
3. **Rounding:** a convex corner is replaced by an arc of radius r inside the rock. A concave corner becomes a fillet of radius rc, at most 0.15. That fillet is the only place the outline moves outward: by at most rc (sqrt 2 - 1) ≈ 0.062. A player of radius 0.2 keeps its centre at least 0.283 from the corner, so clearance is at least 0.22, against a camera near plane of 0.02.
4. **Displacement**, inward only: `p = a - n_g * A_style * fbm(round(a * 4) + seed_style)`. The noise is a function of integer world-lattice coordinates, `World.map_seed` (def `seed`, else the hash of the map name) and the style id. That makes it independent of loop start and traversal order. A is blended linearly over 0.5 cell where styles meet, and is 0 within 1 cell of a `D`, `G` or `w` face.
5. **Guards:** on a 1-cell-thick wall, A is capped at 0.15 per side (the wall keeps at least 0.7 thickness). On a single-cell pillar, A is capped at 0.10. Then one `[1,2,1]/4` smoothing pass over non-pinned vertices, then a re-clamp so that the Hausdorff distance to the grid boundary is at most 0.25 and face displacement is at most 0.2.
6. The visual normal is the perpendicular of the central difference. Arc length `s` is measured from the loop's lexicographically smallest anchor (y, x), plus `512 * loop_index` in canonical order. It is unique and deterministic.

**Mesh** (`WorldMeshBuilder.build`; the contour path runs only when `world.wall_style` is non-empty). There are two vertices per loop vertex (h = 0 and h = 1) and quads between them. CUSTOM attributes are avoided for Compatibility-renderer safety:

| Attribute | Content |
|---|---|
| VERTEX | the displaced position |
| NORMAL | the visual normal |
| UV | (s, v) |
| UV2 | the anchor (JS x, y) |
| COLOR.r | built faces: run-end strength 1 / 0. Natural faces: signed curvature mapped to 0..1 |
| COLOR.g | `(style * 4 + n_g code) / 255` |
| COLOR.b | tile code |
| COLOR.a | link door |

**Sonar consistency (the rules):**
- `solid_grid`, collision, `Raycast.trace`, `fill_rays` (`vis`, `vnorm`, `vmat`), `strongest_echo`, `enclosure`, `hit_info` and the audio are **unchanged and grid-based**. Echo timing, the "dead end rings short" cue and reveals stay exactly tied to collision.
- The shader samples light at **the anchor (UV2)**, not at `wpos`: `sonar_wall_light(anchor, ...)`. It also derives `cell`, the x_face test and ripple-arc distances from the anchor and `n_g`. Brightness is therefore identical to today's wall at that grid point. Sampling at `wpos` would fail the `vis + TOL (0.35)` test on recessed faces beyond 55° of incidence, giving dark speckles. The visual offset is at most 0.25 cell, which is at most 21 ms of front travel at 12 cells/s.
- The forced corner vertices keep the interpolated anchors on the faces, so a corner never samples inside rock.
- Normals: strata, the silhouette and incidence use the visual normal. Ripple arcs, vibration and the window "beyond" lookup use `n_g`.
- **Depth columns:** `rs.zbuf` must match the drawn outline, because rounded convex corners shift the edge sideways by up to about 20 px at 2 cells. `ContourField` keeps a per-cell segment index (CSR: `cell_start`, `seg_xy`). The new `Raycast.depth_columns_contour` runs the same DDA, tests the segments of every visited cell (open corner cells included), and stops at the first hit inside the current cell. If nothing is hit within 3 cells after the first solid cell, it falls back to the grid distance. Tolerance against a brute-force ray/polyline test: 0.02 cell. `rs.tch` is unchanged.

## 3. Shader plan (`sonar_wall.gdshader`)

**Branch on style (COLOR.g):**
- **Style 0:** today's code, verbatim, with `u = along(anchor) - cell`.
- **Natural (1-5):**
  - The face-end verticals and the stone, brick and wood blocks are removed.
  - **Silhouette line:** `sil = dot(N, V)`, drawn where `|sil| < w * fwidth(sil)`. This gives the ink outline of pillars and passage edges.
  - **Top and bottom edges:** the top edge is drawn at `v = lip(s)`, and fragments above it are discarded (low gorse and cairns read by their outline). The bottom edge stays at v = 0.
  - **Concave crease:** at 0.35 strength where curvature < -1.5 / cell (quality 3).
- **Built (6-9):** straight edges, and corner posts only where COLOR.r = 1.

**Strata** (rock, quality 3 and `mat_detail`):
- Group the arc length into L = 0.6 cells, `g = floor(s / L)`, seed `hash(g)`. Each group has up to 3 strata (each present when hash < 0.5).
- Segment span: `fs = 0.05 + 0.3 h1`, `fe = fs + 0.35 + 0.45 h2`.
- Height: `v = 0.12 + 0.76 h3 + slope * (s - s0)`.

**Information at a glance:**
- **Orientation:** the bedding plane is world-anchored. The dip direction and angle (8-20°) come from `hash(floor(anchor / 8), seed)`, and `slope = tan(dip) * dot(tangent, dip_dir)`. Walls running along the dip show tilted strata; walls across it show level ones. Opposite walls of a passage mirror each other, so parallel walls read as parallel.
- **Facing:** strata alpha is multiplied by `0.35 + 0.65 |dot(N, V)|`. A wall square-on to you shows full strata, which matches the strong echo of high `cosInc`. A wall running away from you thins out.
- **Distance:** strata fade with `smoothstep(7, 5, d)` and cracks with `smoothstep(5, 3.5, d)`. If you can see strata, the wall is within about 6 cells.
- **Cracks:** per group, a crack hangs from the lip with probability 0.6 on convex curvature (> 1.5 / cell), 0.25 on flat, 0.1 on concave. Concave faces get rising seeps from the floor at p = 0.4. Length is 0.12-0.32 h. Crack density reads protruding corners against recesses.
- **Material:** read from the lip shape plus the detail type (table above). Strata never boil, so they hold still while the light moves.

**Per quality** (mirrored by `LineStyle.wall_features(q, mat_detail)`):

| Feature | q3 | q2 | q1 | q0 |
|---|---|---|---|---|
| Contour geometry, silhouette, edges, lip height | yes | yes | yes | yes |
| Contour width | continuous | continuous | 1.25 | 1.0 |
| Lip jag, boil, lit body | yes | yes | no | no |
| Halo | full | flash only | no | no |
| Strata, cracks, material ticks (need `mat_detail`) | yes | no | no | no |
| Doors, windows, fence rails | yes | yes | yes | yes |
| Arcs / vibration | 4 / on | 2 / on | 0 / off | 0 / off |

No new uniforms are needed: the shader derives everything from the `quality` and `mat_detail` uniforms that `game.gd _sync_quality_uniforms` already pushes. The governor's first step (material detail off) therefore drops strata first.

**Cost** (GT 1030 reference, 5.2 ms typical uncapped):
- The wall pass is dominated by its three pulse loops (sample2, vibration, arcs), about 700 ALU per fragment with 6 pulses. Strata add about 120 ALU and the removed stone branch saves about 60, so the wall pass grows about 8% (estimate +0.15 ms).
- Mesh: about 8k to about 35k vertices per stage, negligible.
- CPU: contour build 30-80 ms once per stage load (hidden behind the stage card); `depth_columns_contour` +0.3-0.5 ms per moving frame; ink tapering +0.05 ms.
- Total about +0.7 ms, to about 6 ms, against the 16.7 ms budget. Gate: `perf_play` on the hollow, typical walk uncapped avg <= 6.5 ms.

## 4. Unification: `render/line_style.gd` (`class_name LineStyle`, static)

```
const INK_FILL := Color8(4, 3, 6)
const BONE := [255, 252, 244]
static func ink_for(rs: RenderState) -> bool          # rs.world and "wall_style" in rs.world and not empty
static func contour_width(depth: float, ink: bool, wscale := 1.0) -> float   # classic: (1.5 if depth < 1.5 else 1.0) * wscale
static func detail_width(ink: bool, wscale := 1.0) -> float
static func figure_width(depth: float, locked: bool, ink: bool, wscale := 1.0) -> float
static func limb_mul(ink: bool) -> float               # 1.7 / 1.6
static func flash_width(w: float, f: float, wscale: float) -> float
static func boil_amp(ink: bool, wscale := 1.0) -> float  # 0.7 / 0.5
static func ping_lit(b: float, depth: float, ink: bool) -> float  # classic = Sprites.line_alpha
static func taper(c: Canvas, pts: PackedVector2Array, w: float, ink: bool) -> void  # classic: one stroke
static func fill_silhouette(c: Canvas, ink: bool) -> void  # ink: fill current path with INK_FILL
static func hud_width(role: String, ink: bool) -> float    # frame / primary / detail / emphasis
static func wall_features(q: int, mat_detail: bool) -> Dictionary
```

**The classic branches return the literal values in use today, so the parity hashes are unchanged.**

Adoption:
- `sprites.gd`: lines 127-143 and 749 (lw, flash, alpha, `a_j`). Closed coffin and crypt shapes get `fill_silhouette` before the stroke.
- `critter_draw.gd`: lines 71-72. Rat tail and hare ears use `taper`; bodies are filled.
- `echo_layer.gd`: lines 161-166 use `figure_width`.
- `figure_line.gd`: line 79 uses `limb_mul`, and the head and torso are filled in ink.
- `hud_draw.gd`: a new `var ink` member; its 21 literal widths become `hud_width(role)`.
  - `primary`: 1.25 (vial, dial, cards)
  - `detail`: 1.0
  - `frame`: 0.8
  - `emphasis`: 2.0 (dial ring, was 2.4)
  - `ui/hud_view.gd` sets `ink` from `game.rogue_on()` and the world.
- `floor_fx.gd`: floor marks use `detail_width`.
- `vessel_draw` and `figure_vol_draw` stay classic in this pass.

## 5. Stage tiles (what a ping should show)

- **Cave rock:** heavy dark mass, irregular lip, 2-3 strata per wall that hold still, short cracks hanging at pillar shoulders, seeps in recesses. No vertical joints anywhere.
- **Forest:** thicket outlines with ragged spiky tops at 0.85-1.0 and broken feet. Trunks are round columns with no top edge, bark verticals and root flares. Creek water sheen.
- **Moor:** low gorse at 0.7-0.85 with thorn ticks and a faint warm tint. Cairns are conical stacked-lens piles, distinct from gorse by their smooth stepped lip. Gibbet posts with an arm.
- **Road:** cobble setts on the floor only, within 6 cells (budget unchanged). Fences are two rails with posts and no top edge. Milestones are dressed and domed with an incised line and ticks. Hedges use thicket.
- **Inn:** straight timber with weatherboard and studs, corner posts only at real corners. Windows and doors keep today's branches (warm glow). The yard wall is drystone courses.

## 6. Work packages (commit in order S1, S2, S3; S4 any time after S1)

| WP | Owner files (exclusive) | Delivers |
|---|---|---|
| **S1 Contour geometry** (inert in game) | `render/contour_field.gd` (new), `render/world_mesh_builder.gd`, `core/world.gd` (`wall_style`, `map_seed`, `contour` cache read from def `wallStyle` / `seed`), `tests/unit/test_contour.gd` (new) | `ContourField.build` / `for_world`, the contour mesh path |
| **S2 Line style** | `render/line_style.gd` (new), `render/sprites.gd`, `render/critter_draw.gd`, `render/figure_line.gd`, `render/echo_layer.gd`, `render/hud_draw.gd`, `ui/hud_view.gd`, `tests/unit/test_line_style.gd` (new) | the shared API and its adoption |
| **S3 Wall shader + switch-on** | `render/shaders/sonar_wall.gdshader`, `render/shaders/sonar_common.gdshaderinc`, `data/rogue/stages.json` (`wallStyle` per row), `tests/scenarios/style_tour.gd` (new), `tests/unit/test_style_switch.gd` (new), `project.godot` + `tests/flow/test_rogue_mode.gd` (version 0.21.3) | the visible change |
| **S4 Occlusion + floors** | `core/raycast.gd` (`depth_columns_contour`), `render/echo_view.gd`, `render/floor_fx.gd`, `render/shaders/sonar_floor.gdshader`, `tests/unit/test_contour_depth.gd` (new) | contour-correct zbuf, setts, rubble, water sheen |

`wallStyle` rows:
- hollow `{"#":"rock"}`
- wood `{"#":"thicket","W":"trunk"}`
- moor `{"#":"gorse","B":"cairn","I":"gibbet"}`
- road `{"#":"thicket","B":"milestone","I":"fence","W":"trunk"}`
- inn `{"#":"drystone","W":"timber"}`

**Acceptance:**

S1 (headless, 50 seeds x 5 stages):
- Byte-identical arrays on rebuild.
- A different seed differs.
- An added far island leaves the existing loops identical (traversal independence).
- Every anchor lies on the grid boundary, and `|p - a| <= 0.25`.
- Every vertex is in a solid cell, or within 0.063 of a concave corner.
- Sampled walkable positions keep >= 0.13 from the outline.
- Loops never self-intersect.
- Build <= 80 ms per 64x48 map.
- Classic maps produce exactly the legacy mesh.

S2:
- With classic worlds, every parity suite is green, with unchanged hashes.
- `taper` emits 3 strokes for open polylines >= 10 px and 1 otherwise.
- The width table values.
- `ink_for` is false for classic worlds.

S3:
- `wall_features` table for q0-3 x `mat_detail`.
- The shader's const block (`STRATA_Q`, `HALO_Q`, `LIP_JAG_Q`) is scanned as text and matches `LineStyle`.
- Every stage row has a `wallStyle` covering each solid tile char.
- Windowed run of `style_tour` with `--stage=hollow|wood|moor|road|inn --qmode=high|q2|q0`: ping at 0.3 s, frames 30/45/60 into `docs/shots/style/`, no shader errors. Human review checklist: no cobble read; strata still under moving light; material identifiable from the lip alone; no camera clipping hugging a pillar; figures occluded exactly at rounded corners.

S4:
- `depth_columns_contour` is within 0.02 of a brute-force ray/polyline test.
- It is >= the grid depth - 0.07.
- It equals `depth_columns` on classic worlds.
- **Sonar invariance:** `vis`, `vnorm`, `strongest_echo` and `enclosure` are bit-identical with and without `wallStyle`.
- `view_bench` depth cost <= +0.5 ms.

**Risks:**
- **Zbuf cost in GDScript:** if over budget, fall back to grid columns plus analytic corner arcs only.
- **Parity drift:** a classic literal mistyped in `LineStyle` changes the hashes. The S2 gate is the full suite (about 9 min).
- **Shaders do not compile headless:** every S3 and S4 change needs a windowed run.
- **Low lips** expose walls behind them. Those walls are unlit, because sonar `vis` is 2D and the grid blocks it, so they stay black; verify in screenshots.
- **Floor in the recess strip** shows the ring dots at the wall foot. Accepted; if they look wrong, mask the floor more than 0.25 inside solid cells.
- **Single-cell features** (trunks, cairns) depend on the r = 0.3 rounding, which makes them octagon-round. Check them at 1-2 cells.
- **Doors** keep their straight faces and the static mesh, as today.
