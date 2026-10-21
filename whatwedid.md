# What we did: the v0.17.0 villager art upgrade

Handoff notes for another AI (or person) who wants to keep iterating on the villager figures.
Commit: `ca5f093` "v0.17.0: anatomical villager figures and figure sheet".

## The brief

Make the villagers more realistic without losing the silly, wonky look. Make sure the circulatory (vessel) overlay still lines up with the new shapes. Produce a sheet showing animations, poses and so on.

Result: the volumetric figure (`js/figure.js`) now draws anatomical outlines instead of plain tapered capsules. A new tool, `tools/figure-sheet.*`, renders every archetype, pose and circulation state through the real renderer.

## How it was done (process)

1. Read `js/figure.js`, the figure and vessel parts of `js/render.js` (`posePerson`, `drawLineFigure`, `drawPerson`, `drawVessels`), `js/data/vessels.js`, `js/data/archetypes.js`, `js/struggle.js` and `docs/DESIGN.md` 5.6.
2. Found the circulation problem. Vessel edges are drawn on ONE quadratic curve per limb: root slot, then the elbow or knee slot as the control point, then the end slot. The v0.16 volumetric limbs were two straight capsules through that control slot. So vessels sat beside the limb centreline, not on it.
3. Delegated the redesign to an Opus subagent with a written brief. The brief named the files to read, the hard constraints below and the circulation requirement. It also asked for the sheet and a unit test that proves vessels sit inside the body.
4. The agent iterated on screenshots of the sheet, ran the suite, updated docs and version.
5. Reviewed the result, ran `tests/*.test.js` myself (no failures), published the sheet as an artifact, committed.

## Architecture you need to know

- Pose slots (`PX`, `PY`, `PZ` in render.js): 0 head, 1 neck, 2/3 shoulders, 4/5 hips, 6/7 hands, 8/9 feet, 10/11 elbows, 12/13 knees, 14 torso, 15-22 accessory anchors, 23 hat top, 24/25 role-item grip and tip (volumetric only).
- `posePerson` fills the slots and a module-level `pose` object. It decides `pose.vol` (volumetric only when Effects >= 1, quality >= 1, nearer than `FIG_VOL_DEPTH`, and inside the frame budget).
- `drawPerson` then calls either `drawLineFigure` (the classic line figure) or `Figure.draw` plus `Figure.drawExtras`. The pulse sweep clips whichever one is used into height strips, so all drawing has to happen inside the draw callback.
- Vessels: nodes live on slots (`vessels.js`). `drawVessels` places dots and edges, and `Figure.drawFlush` adds the coral skin flush at Effects 2.

## What changed

### `js/figure.js`
- Every part is a closed outline stored as a polygon (`px`/`py`, up to `MAXPTS` 40 points), drawn as a smooth curve. Part count is 11 (12 with the shovel); `MAX_PARTS` is still 16.
- **Torso** (`buildTorso`): one hull running from neck base through trapezius, deltoids, ribcage, waist, pelvis and crotch. It is shaped per body type and reacts to `look.shoulder`, `look.stoop`, a child belly and a small per-person lopsidedness.
- **Limbs** (`sweep` plus the `ARM_*`, `LEG_*` and `NECK_*` profile tables): each limb is a single outline swept along the same quadratic curve the vessels use. The knee or elbow sits at the curve midpoint. Profile tables hold radius and bulge per position along the limb (thigh taper, calf bulge, forearm).
- **Head** (`buildHead`): jaw, chin and brow, with the head kinds round, egg, square and long.
- **Hand** (`buildHand`): palm, thumb and finger hints. **Foot** (`buildFoot`): shoe with heel, instep and an upturned toe. Both use small angle/curve tables (`HAND_*`, `SHOE_*`).
- **Details** (`details`): ears, nostrils, eyes with pupils, brows, and a mouth that changes with mode (`mood`). Kneecaps, elbow creases, clavicles and a waistband are drawn at close range. Hats, hair, props and role hats are kept.
- New public helpers: `contains`, `hit`, `hitAll`, `spanAt`. They are silhouette queries, and the anatomy test uses them.
- Wrap lines: Effects 1 draws one per torso, leg and arm; Effects 2 adds the lower half of each limb.

### `js/render.js`
- Pose gets `cosYaw` and `shS` fields.
- Inside `if (vol)` only: a child's shoulders and hips are up to 32% narrower. Band-front rings follow the new silhouette. Vessel dots are 0.8x (veins 1.35x) on the new bodies, through `vesselRad`.
- Tool hooks `Render.drawSolo` (draws one echo through the real `drawPerson` path) and `Render.vesselRad`.

### Tests
- `tests/figure.test.js`: updated for the new part kinds.
- `tests/figure-anatomy.test.js`: new. It poses over 3,000 figures through the real renderer: 14 archetypes x 3 seeds x 6 view angles x 14 modes, plus 5 held-victim struggle phases, plus every body type x head, outfit, item, height, build, stoop and shoulder setting. It asserts:
  - every artery node is inside its own body part;
  - points sampled along every vessel edge stay inside the body;
  - the dots fit inside the wrists and ankles;
  - the four flush ellipses sit on the skin;
  - the child has a bigger head and narrower shoulders than an adult.

### Docs and version
`docs/DESIGN.md` 5.6 updated; version 0.17.0 in `js/log.js`, DESIGN.md and README.

## The figure sheet

- `tools/figure-sheet.html` + `tools/figure-sheet.js`: loads the REAL game scripts (no copies of the drawing code) and draws cells with `Render.drawSolo`.
- Sections: game-scale lineups, archetypes x 4 views, pose modes (idle, wary, chat, walk and flee in 8 phases, startle, cower, dazed, seated, fed, held), body x head matrix with hats/hair/outfits/items/props, circulation (beat ages, blood 1/0.5/0.15, fear modes), before/after.
- Controls: Effects 0/1/2, quality, zoom, play/pause and time scrub, seed, pulse sweep, rim light, reduced motion, and overlays for skeleton slots, vessel graph and part outlines.
- URL options: `?only=`, `&zoom=`, `&fx=`, `&t=`, `&arch=`, `&cell=`, `&parts=1`, `&skel=1`, `&graph=1`.
- `tools/build-figure-sheet.mjs`: writes `tools/figure-v016.js` (the old figure, extracted from git `9460bc0`, exposed as `VCS.FigureV016` for before/after) and a single-file offline `figure-sheet-standalone.html`. The standalone page is what was published as the artifact, with the doctype and head wrappers stripped.

## Hard constraints (do not break)

- The Effects 0 line figure must stay hash-identical. `tests/figure-line-parity.test.js` and `tests/frame-parity.test.js` must pass UNCHANGED. Any pose tweak has to sit inside `if (vol)`.
- Figure functions never throw, and hot paths do not allocate (parts and scratch are preallocated). The per-frame budget guard (`figure.budgetMs`, `r.figMs`) drops High to Low for 10 s when exceeded. Per figure cost is about 0.45 ms against a 2.5 ms budget.
- Keep the monochrome stroke style with black occlusion fill at Effects 2, rim light and wrap lines.
- Keep reduced-motion behaviour.
- Version numbers: see the memory note on numbering (patch 0-9, then roll into minor).

## How to iterate

1. Open `tools/figure-sheet.html` in a browser from the repo root (it needs the `js/` files next to it).
2. Edit `js/figure.js`. Tweak the profile tables first (`ARM_R`, `LEG_R`, `TU`/torso widths, `HAND_*`, `SHOE_*`); they change the look most with the least risk.
3. Check small and large: the game draws figures about 100-250 px tall, so use Zoom 1x as well as 3-4x. Use `&parts=1&graph=1` to see whether vessels still sit inside the outlines.
4. Run the suite: `for f in tests/*.test.js; do node "$f" || echo FAIL $f; done`. At minimum, run `figure`, `figure-anatomy`, `figure-line-parity`, `frame-parity` and `render`.
5. Rebuild the single-file sheet with `node tools/build-figure-sheet.mjs` if you want an offline copy.

## Known gaps and ideas

- `tests/smoke.mjs` was not run (playwright not installed here). Run it when you can; it has lineup shots at Effects 0/1/2 and an fps check.
- The sheet could not be tested inside a sandboxed iframe. On its own page it animated at about 48 fps with no console errors.
- Before/after uses the new pose slots on both sides, so the v0.17 child-width tweak shows on the old figure too.
- The old line-figure coat crosses itself into an X when facing the camera. This is fixed only in the volumetric path, because the line path has to stay identical.
- Ideas not done: facial asymmetry per archetype, finger poses for props and the held-victim grip, cloth folds on robes and cloaks, and a shared silhouette cache for the pulse-strip clipping.

## v0.18.0 follow-up (second pass)

All inside `draw()` in `js/figure.js`, Effects >= 1 and near figures only (the Effects 0 line figure is untouched):
- Shade-side contour: a heavier (1.9x) partial stroke on the side away from the rim light, via `rimPart(c, p, -rimSide)`. Gives limbs and torso roundness.
- Cuffs: a third wrap ring per arm and leg (`sweep`, t 0.84) drawn at lod >= 1 as sleeve/trouser cuffs (skipped for robe, cloak, mail sleeves).
- Torso creases (`torsoFolds`): three fine curves fanning up from the belt line at lod 2 (skipped for robe and cloak).
Tests in `tests/` all pass unchanged. Still open: hood/arm overlap on the idle head-scratch, per-archetype faces, finger poses, robe folds.

## v0.20.0: character creator

(Version 0.19.0 was left to a parallel figure-art pass; this branch jumps to 0.20.0 to avoid a collision.)

A standalone page to play with villagers: `tools/character-creator.html` (+ `.css`, `.js`) and the pure data layer `tools/character-creator-core.js` (`VCS.Creator`). It loads the real game scripts like the figure sheet and draws only through `Render.drawSolo`, so it picks up any change to `js/figure.js` / `js/render.js` with no edits. Neither file was touched. Details: `docs/DESIGN.md` 5.7.

- **Open it:** the HTML file from the repo root folder (file:// works), or F9 dev panel > NPC Forge > "Open character creator" (the only game-side hook, in `js/devpanel.js`).
- **Preview:** big live figure with the idle clock running; pose picker (idle, wary, chat, walk, flee, startle, cower, dazed, seated, fed, held with a struggle slider); turn slider, preset views, auto-turn, drag to turn; Effects 0/1/2, quality, zoom (render scale), camera distance; rim light, circulation, skeleton, vessel graph and part-outline overlays; reduced motion; Save PNG.
- **Game scale:** four small views, a lineup between Forge villagers at depth 2.5 and a full 640 x 360 frame at four depths, rendered at the game's internal size and shown at 1x/2x/3x.
- **Editing:** every Forge look field (dropdowns, sliders, toggles) with per-field locks; `acc` is replaced by independent hat, prop and scarf controls (the renderer draws `look.hat` / `look.prop` directly). Archetype presets and seeds come from `Forge.generate`; "Random in archetype" and "Wild random".
- **Saving:** named characters in localStorage (`vcs.creator`, max 64), the draft auto-restores (`vcs.creator.draft`), export one or all as JSON, import from a file or pasted text (also a bare look object), and a Forge spawn spec view.
- **Safety:** `Creator.sanitize` clamps everything to `LOOK_RANGES` / `LOOK_ENUMS`; `tests/creator.test.js` (12 tests) covers fields, clamping, presets vs Forge, randomize and locks, pose echoes, view clamping, JSON round trips and malformed input, storage failures, Forge spec validity, and renders 26 random or extreme looks x 11 poses x Effects 0/1/2 x 3 turns through `Render.drawSolo` with no logged errors.
- **Verified** in a browser at 1440 px (two columns) and 375 px (one column, no horizontal scroll): idle, held with circulation and overlays, walk at Effects 0, wild random, save, import of bad and clamped JSON, draft restore. No console errors.
- **Ideas not done:** spawn a saved character straight into a running game (the dev panel could list `vcs.creator`), an onion-skin compare against a second character, a URL-hash share link.
