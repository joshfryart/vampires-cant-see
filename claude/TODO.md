# TODO

Each version: Opus pulls src → contract → agents → tests + smoke + screenshot review → publish → update `src/`, HANDOFF.md, TODO.md.

## Roadmap (agreed 2026-10-20)
- **0.11.2** DONE 2026-10-20 (vignette setting, floor-bounce echo, roughness speckles, person echoes on object sonar equation, echo tests; 586 unit + smoke pass; not checked by ear/eye: floor echo loudness, speckles, perf fps).
- **0.11.3** DONE 2026-10-21 (not yet played by ear/eye: villager heartbeat, scuff ellipse, echo level; unit 589 + smoke 253 pass x4 over http): `tut:light` hint, villager heartbeat (<=2 cells, nearest 2, bpm by state, `Audio.heartbeat`, level `vheart`), go-home-early at fear >= 8 (not the watch), `?debug=1` schedule readout (6 nearest), footstep scuff (alternating foot offset 0.12, flat ellipse along heading), open-path flee fix (scheduled trips no longer wrap end->start through walls; regression test), person echo voice is now a dull thud and played at half level (`PERSON_ECHO_GAIN`), smoke serves over http (`SMOKE_FILE=1` for file://) and exits cleanly, tab id from crypto, `tools/sound-lab-standalone.html` to audition every sound. Left open from the plan: notice/fear gain scaling with exposure (spotting already uses the same light value as the veil meter, so it is one source of truth; a gradual build-up is a balance change needing a playtest). Plan was: stealth feedback: notice/fear tied to veil exposure, `tut:light`, villager heartbeat, footstep scuff ellipse, V1 leftovers (debug schedule readout, go-home-early on fear, flee-through-wall bug).
- **0.12.0** eavesdropping: W2 listen at windows, W3 synth voices (few presets), V4 dinner tables by lit windows, V2 villager-to-villager conversations (meetings, turn-taking chat) as the overheard content. Subtitles (V5) after.
- Later: bigger map, items/light, animals, watch (need building mockup first).

## Next (in order)
0. [x] v0.11.1 playtested OK by user (2026-10-20).
1. [x] (superseded) Playtest v0.11.1 in browser (user played a v0.11.0 session OK, no errors in log; echo visuals/audio unchecked). Older list: v0.10.14 in browser (new: drink drag, town lights -35%; v0.10.13 items still apply; last playthrough ran 60 fps): step rings differ for sneak/run and grass/wood/stone; windows only under ripple (brief), villager footsteps sound like steps; echo timing (one sonar speed 12 cells/s, echo = round trip), far echoes from distant walls, torch glow/holders under ripple, edge glow direction + smoothness, fire hiss range, devtool ring alignment (`?debug=1`), night 4 min pace, town darkness at 3× radius.
2. [x] Smoke test runs on a real machine (2026-10-20, Windows): 249 pass. Fixed stale night-length check (360 → 240 s). Needs Playwright installed outside the repo, `NODE_PATH` set to its node_modules, then `node tests/smoke.mjs`. First run had one extra failure that did not repeat; watch for flakiness. Still run before each release.
3. [x] Perf: measured 2026-10-20, street/tavern hold 59–60 fps headless (earlier 44–52 was machine-load noise). CSS-overlay vignette tried and dropped (it dimmed the HUD; gain was noise). Update 2026-10-20: a later agent branch re-added it and it is merged on main (Render.setVignette); not re-measured, check HUD dimming.
4. [x] Drink grab (v0.10.14; v0.10.17: click/Space pings while holding, no longer lets go; light -35% playtested OK; v0.10.16: start blood 10%; v0.10.15: pools 30–50, rate 7→2.5/s ≈ 9 s per villager; smoke retuned and passing 249 on 2026-10-20; Playwright now at %TEMP%\vcs-pw\node_modules (NODE_PATH)): hold drink → victim pulled to 0.6 cells ahead, you move at 25% speed (full victim) → 55% (drained), look halved. Tune DRAG_* in game.js. Smoke needs a drag check.
5. [x] Hidden "veil" meter (requested 2026-10-18 b): eye + 5 ticks beside the vial, smoothed `playerLit`; vignette tone-down/setting, fear tie-in and `tut:light` still open below. Same pass: gulp sound, victim struggle/break-free, drag scuffle sounds (untested in browser).
6. [x] v0.10.18 (2026-10-20): villager struggle animations (`js/struggle.js`: panic flail -> push-away -> limp by blood, startle spike per break-free attempt, perspective/yaw cheat in `put`), vampire arms drawn in the held victim's echo, hold E to restrain (no break-free, muffled, half drink speed), G throws a rock (3 per run, saved in snapshot, clatter sound + sonar pulse + startles), rocks HUD pebbles right of skills, veil meter beside vial with skills shifted right, drinking 25% faster (DRINK_BOOST 1.25, ~7 s per villager). Opus brainstormed the move set; GIFs in docs/struggle-*.gif. Untested by hand in browser beyond headless screenshots: playtest restrain/rock feel, pebble placement with 3 powers unlocked, large-text HUD.
7. [x] v0.10.19 (2026-10-20) V1 night schedules: `js/schedule.js` (roles = [places, until, act] over the night fraction; 20:00 = 0, 01:00 = 0.5), town `places` + `role`/`home` per path in maps.js, people.js routes trips with a lit-street-preferring Dijkstra (`routeTo`); sitters and the test map keep their loops. Curfew: all but the watch and night owls are indoors by 01:00 (tested), then abed (seated pose via `seated`). 2 guards patrol the 8 outdoor posts all night in opposite directions (speed 1.3); insomniac + gravedigger stay out until ~0.7; drunk leaves the tavern ~0.26 and is home by ~0.45. Homes: house1 (farmer), house2 (elder, regular, mother; separate cells), barn (drunk, insomniac), shed (gravedigger), tavern (innkeeper), church (priest). Home acts: cook, eat, spin/mend/whittle, sleep (benches as beds). `People.snapshot` has `sched` {role, stop, act, next, walking, eta}. 543 unit pass. Still open: on-screen `?debug=1` readout, go-home-early on high fear, flee along a trip path can wrap through a wall and cower, hearth fires/light inside homes (V6), real beds/lying pose, guard lantern.
7b. [x] Decided: villagers first (V1 done above); v0.11 Echoes after. (was: Decide v0.11 Echoes (sonar speed decided; next = stages S1–S10) vs. v0.11 Villagers.)
7c. [x] v0.11.1 (2026-10-20) Echoes shipped to main: visuals (air rings, wall vibe, ceiling ring indoors only, shared beam curve) + audio (acoustics block, materials/normals, TL occlusion + Maekawa, Sabine T60, comb, grain, click ping, per-material voices). Opus review fixes applied (min lowpass behind+occ, render reads pu.facing, one beam curve, breath honors occ, real 96-voice cap). 574 unit tests pass.
7d. [~] 2026-10-21 UPDATE: the smoke flakiness was file:// localStorage in headless Chromium; served over http (default now) 4 runs in a row pass 253 and exit 0. Earlier note (Linux container, headless Chromium): 586 unit pass; street/tavern 60 fps median (meets >=50). Smoke on merged main is flaky here: 6 runs gave 1 failure to 6 failures, always save/localStorage related (Continue disabled after reload because vcs.run was missing, two-tab guard sees no other tab, null state after a failed section). Tab id now uses crypto (the pinned Math.random could collide) and smoke waits 700 ms before reloads; with that, 1 of 3 runs was clean (253 pass), so the cause is probably Chromium not sharing localStorage writes between pages in time, not a game bug (unproven). Still needs eyes/ears: air-ring look, reverb mix, CSS vignette HUD dimming. Original list: v0.11.1 NOT verified: smoke (253 pass was on the audio branch only, not re-run on merged main), air-ring look/tuning in a real browser, wetter reverb mix by ear, perf with new passes (street >=50 fps headless), CSS vignette HUD dimming (item 3).
7e. [~] v0.11 echo leftovers. Done in 0.11.2 (586 unit tests, smoke 253 pass): floor-bounce echo (A.floorAmp, game.floorBounce), roughness speckles (render speckle/pulseRough, gated on matDetail), person echoes on the object sonar equation (A.personAmp, +12 dB class gain, clamp 0.1..0.7 kept), missing tests (occlusionTo/firstSolid/blockMaterial, strongestEcho->gameAmp, breath occ output, floor bounce, speckle, person level). Still open: corridor flutter; high-band beam narrowing + rear body shadow; air-band shelf; struck-lit objects/people + warm tint (walls only today); TL computed from formula (tl500 is a hand table, stone/brick 60/50 vs spec caps 65/55); repetition-pitch limit 2 m vs spec 1.3 cells; comb/delay nodes per echo not voice-tracked; air rings vanish when matDetail/fps auto-off. Floor-bounce and speckles unchecked by ear/eye in a browser.
8. [x] Fix `docs/SPEC-echoes.md` lines ~333 and ~386 (still mention `delayMul`).

- [x] (fixed 2026-10-20, 4 runs x 249 pass: pinned random, state waits, closed pages, per-section try/catch; rAF-freeze hook skipped) Smoke flakiness diagnosed 2026-10-20 (Fable agent; no game regressions, suite is racy). Fix list, in order: (1) pin Math.random on the lit-walker page `lp` (tests/smoke.mjs ~899-901): struggle() at 0.7 s can break free (40%) and end the drink before the witness flees, so 'lit walker facing away' is a coin flip; also reword the check (struggle noise startles it now, not a heartbeat). (2) optional `?debug=1` hook to stop the rAF loop so time moves only via debugAdvance (real time drifts the 20:00 / blood / pulse-pixel checks). (3) replace fixed sleeps with unswallowed state waits (53 `.catch(() => {})` hide slow boots, cascading into null-state TypeErrors: getContext, .blood, nightLengthMin, essenceBonus). (4) close all 9 leaked pages per section (31 opened, 21 closed; fps drops 60 -> 30-39). (5) per-section try/catch so one error does not skip ~100 checks. (6) pin Math.random in newPg; write screenshots outside OneDrive. Logs were in the scratchpad (run1.log, run2.log).
- [ ] Smoke is flaky run to run (2026-10-20: meta-backup notice, tab-lock, occasional drink checks); pinned Math.random in the drink SETUP so break-free no longer fails drain checks. Playwright installed at %TEMP%\vcs-pw (NODE_PATH=%TEMP%\vcs-pw\node_modules).
- [ ] Ideas: visible flying rock arc; rock pickups instead of a fixed 3; struggle moves could drive sounds (kick = thud); restrain stamina/noise tradeoff tuning.
- [x] Town light radius scale 0.6 → 0.39 (-35%) (v0.10.14); world tests use light 20

## Done 2026-10-18 night session (v0.10.4 → v0.10.10)
- [x] Night default 6 → 4 min (v0.10.4)
- [x] Echo pans toward where you face, not nearest wall (v0.10.4)
- [x] Menu cursor stays visible: pointer lock only in play states (v0.10.4)
- [x] Light radius scale 0.75 → 0.15 (v0.10.5) → 0.2 (v0.10.8) → 0.6 (v0.10.9): core radius and outer halo both
- [x] Torch flames and glow drawn only under sonar ripple; holders drawn (wall sconce bracket or iron post) (v0.10.5, v0.10.6)
- [x] Fire crackle pulse removed; quiet steady fire hiss within 1.5 cells, panned (v0.10.6)
- [x] No flicker: steady flames, 0.6 Hz tip sway, window glow static (v0.10.6)
- [x] Two-zone light: core + faint outer halo at 1.8×; edge glow ramps and is biased toward the light's side (v0.10.7)
- [x] Edge glow smoothed: 8 smoothstep stops, bearing low-passed 0.15/frame, reduced motion snaps (v0.10.10)
- [x] Devtool (`?debug=1`): core + outer light rings on the floor under ripple (v0.10.9)
- [x] Town dark-route test: every door, gate and safe spot reachable under 0.6 and 0.3; tavern south door torches moved (v0.10.10)
- [x] Echo timing: one sonar speed 12 cells/s, echo delay = round trip (2d/12), delay cap 6 s, old 34 cells/s audio speed removed (v0.10.11, 3559222, 42d4ada)
- [x] W1 windows ripple-only: no always-on glow; frame + panes show only under a ripple, linger 1.5× wall afterglow; floor spill and test updated (v0.10.12)
- [x] Villager footstep sound: heel thump + scuff per floor (grass/wood/stone), feet alternate (v0.10.12). Ring shrink/scuff still open below.
- [x] Villager step ring scaled by gait (sneak/walk/run from wary/flee) and floor (grass/wood/stone) and pace; base ring shrunk 0.7→0.4 range, 0.35→0.25 strength; room indoor/outdoor still applied on top (v0.10.13)
- [x] Version numbers go up one patch at a time (0.10.12 → 0.10.13 → ...)
- [x] Version rule (confirmed 2026-10-20): patch is a single digit 0–9; after x.y.9 the next release is x.(y+1).0 (0.1.9 → 0.2.0). Bumped to 0.11.0.
- [x] `VCS.Log.VERSION` (js/log.js) was stuck at 0.10.4; now 0.10.13 and a log test checks it matches README "Current build". Bump both each release.
- [ ] Footstep ring look: flattened floor "scuff" ellipse, left/right offset (render, still open)
- [x] Itch zip + playable artifact republished at each release

## Done
- [x] Phases 1–2, P3–P5, v0.6 The Town, v0.6.1 one continuous town
- [x] v0.7 The Night: feeding, blood + drain, weak pulses, night clock, chime, wash-out, dawn loss, sleep, 5-night win, HUD vial + dial, dawn grain, title cards, run-end panel

## Playtest (still open)
- [ ] v0.8: shop prices/Essence pace, boon balance, sealed safe spots; v0.7: night length, blood drain/feed amount, dawn danger feel, HUD readability, card timing
- [ ] v0.9: gift cost 40/60 vs pool 30–50, fear pace, power costs, night 5 drain ×1.4

## v0.8 Runs and Saves (done 0.8.0)
- [x] `vcs.run` (deleted on run end) + `vcs.meta` (Essence, upgrades, unlocks, stats); use snapshot v2
- [x] Safe write (temp → verify → swap, `.bak`), checksum, size limit, key whitelist, migrations
- [x] Export / Import; menu Continue / New run / Shop / Stats
- [x] Per-run random spawns, paths, open safe spots
- [x] Essence + upgrade shop (9 upgrades, 3 tiers); night boons (pick 1 of 3)

## v0.9 The Hunger (done 0.9.0)
- [x] Overflow gifts, powers (shriek/mist/still), fear, drain ramp
- [x] 0.9.1: night 6 min + slider, ability guide, file cleanup

## Round 1 (done 0.10.0)
- [x] Perf: glow cull, grain→CSS, sample2 (street ~42–48 headless at 48% lit town)
- [x] Sound: partials, compressor, reverb, distance/occlusion/behind, materials, whimper, ambience, breathing, crypt bell
- [x] People: fair bump arc, freeze, wary, flee cap 2.55, lit refuge, sitters/loops
- [x] Town: ~40 torches, windows pass light, props, shed safe spot, hides
- [x] Controls: arrows, R drink, C mist, drag-look, toggle drink, lock retry
- [x] Saves: night/hunger validation, validateRun, keepBak, two-tab guard, crash save
- [x] Rules: far spot +5 Essence (hot crypt rule removed 0.10.2); pools 18–32, fear sleep −5, ramp 0.12
- [x] Onboarding: hints, guide Basics, reduce motion, large text

## v0.11 Echoes (proposed, awaiting go)
- [x] Per-material echo voices (stone/brick crisp, wood hollow, glass tick, iron ring, grass ~silent, people dull) + matching wave tint
- [x] Transmission by material: TL = 20·log10(m·f) − 47 dB; cutoff ≈ 6000·10^(−TL500/40) Hz (wood door ~1.4 kHz, glass ~1.1 kHz, brick ~340 Hz); iron gate ≈ open; open door = Maekawa ΔL=10·log10(3+20N)
- [x] (Sabine zone T60 done; corridor flutter and per-zone door coupling not done) Room tail from Sabine RT60 = 0.161·V/A (cap 2.5 s); corridor flutter (period 2w/c); near-object repetition pitch (<2 m)
- [x] (audio+sonar brightness done; corridor flutter, high-band narrowing and rear body shadow not done) Mouth beam: click emitted from mouth on front of head (z≈0.58), gain(θ) = 0/−1/−3/−8/−14/−18/−20 dB at 0/30/60/90/120/150/180°; high band narrower than low; slender body = small extra rear shadow; apply to sonar ray strength + echo gain (Thaler 2017 modified-cardioid; mouth ka≈0.9 @3.4 kHz → head/body do the beaming)

## Round 2 candidates
- [x] Guide Mist card "Shift or C" (0.10.3)
- [x] Doors textured + windows (crooked panes, lit glow without ring, floor spill) (0.10.3)
- [x] Harden flaky smoke checks — state-waits, pinned drink pools (0.10.3)
- [x] Light radius (see Done 2026-10-18 above)
- [x] Vignette → CSS overlay (merged 2026-10-20; street ≥50 headless not re-measured)
- [ ] Doorway detours for patrols (door test conflict)
- [ ] Key rebinding
- [ ] Re-run sim incl. light/seen model; playtest balance

## Later
- [ ] Guards (v1.0, spawn by fear), garlic, holy ground
- [ ] Sound pass, balancing

## Every version
- [ ] `node --test tests/*.test.js` + `node tests/smoke.mjs` pass
- [ ] Security grep clean; CSP intact; no network
- [ ] Forced crash shows error screen

## v0.11 Echoes (spec = Echoes Docs artifact; checked against v0.10.3 code)
Legend: NEW = not in code · UPGRADE = exists, replace/extend (don't build twice) · REUSE = already done, hook into it.

Decide first (blocks numbers):
- [x] Cell scale: 1 m per cell (user confirmed 2026-10-18). Acoustics only; movement + sonar range unchanged.
- [x] One sonarSpeed: rings and echoes arrive together at 12 cells/s (decided 2026-10-19, v0.10.11). 34 cells/s audio speed removed.

Data:
- [x] NEW `SoundData.acoustics` block (cellM, beamDb, spread, airDbPerM, mat.*, zone.t60, rp, rough) — sounds.js
- [x] (0.11 audio agent: map `materials` re-skin + `cobble`/`roughStone` names, crypt walls roughStone; no new tile chars yet) UPGRADE materials: world.materialAt exists (floor grass/stone/wood for steps) → add wall materials + `cobble`, `roughStone`

Beam + level:
- [x] NEW beam table B(θ) on outgoing rays — sonar.js
- [x] (done for echoes/pings; kept as the listener rear shadow for world sounds, not a mouth cut, so no double cut) UPGRADE `behind` (now gain ×0.7 / dull buffer) → replace with B(θ). REMOVE old, else double-cut
- [x] UPGRADE echo level: audio.echo(delay, strength, pan) exists → L_e formula (wall −20log2d, object −40logd, air)
- [x] UPGRADE raycast: has side + cellX/Y → derive normal + material per hit (no new raycast)
- [ ] (audio uses ray-normal cos incidence instead; not reused from render) REUSE wall-arc incidence (render v0.10) for the angle term; don't add a second

Through walls:
- [x] UPGRADE occlusion: yes/no → lowpass 600 Hz now → per-material TL filter + G gain, door gap, glass peak
- [x] NEW Maekawa for open doorways (diffraction)
- [ ] NOTE glass light pass-through (v0.10 world.js) is visual only; sound TL for glass is separate. No conflict

Rooms:
- [x] UPGRADE reverb: tuneReverb has 2 kinds (indoor fb 0.58 / outdoor 0.25) + setRoom → per-zone T60 → fb = 10^(−3τ/T60), clamp 0.4–2.5 s

Near + rough:
- [x] NEW repetition-pitch comb (< 1.3 cells, physical delay)
- [x] NEW diffuse grain tail on rough hits — audio.js
- [x] (0.11.2: drawFloorFront stipple count x0.5..2 and trail 0.25..0.75 by mean wall + floor roughness, grass/wood dot shape; no second pass; not eyeballed) UPGRADE visual speckles: ring stipple dots already exist (render.js, seeded) → scale count/linger by roughness, don't add a 2nd pass
- [x] (0.11.2: airOn(r) gate) REUSE matDetail/fps auto-off (render.js) as the gate for speckles

Ping:
- [x] UPGRADE ping: shorter ~8 ms 3.2 kHz click, old bip as an option (setting)
- [ ] REUSE footstep timbres (audio.js grass/wood/stone) as the base for mat.voice

Tests (extend existing files, no new): audio/sonar/render/world tests per the Docs test plan (10 items) + smoke: all materials in view, no errors, ≤96 voices.

Added 2026-10-20 (user):
- [x] (0.11.2: audio = game.floorBounce, 35 ms after the ping, grass below minAmp so silent, skipped with pingBip; texture = floor-shaped stipple dots in drawFloorFront; not heard/seen in browser yet) Floor bounce: ping always returns a floor echo shaped by floor material (grass ~silent, stone crisp, wood hollow); light floor texture shown under the ripple
- [x] (visuals done: ceiling ring gated on indoor in render.js; audio part separate) Ceiling bounce indoors only (houses, tavern, church, barn), slightly later than floor; none outdoors (sky). Today render.js drawRipple draws the ceiling ring outdoors too (gate on indoor)
- [x] (visuals done in render.js: drawAirRings + drawWallVibe; smoke not run, no Playwright) Air rings: ping reads as a train of several sequential rings expanding at head height, fading with distance; the surface a ring reaches lights at the contact and visibly vibrates (damped ~7 Hz, ~0.9 s, spreading from the contact point). CHOSEN 2026-10-20: air-vibrate variant 2. Three hollow circles (offsets 0/1.1/2.2 cells, alpha 1/.65/.35) leave the mouth (screen centre, just below horizon, ~0.5 half-height under it) and open outward across the view (~11 deg of opening per cell, dropped past ~58 deg). Each circle swells/shrinks at random (0.3x-1.8x, per-dot rhythm 1.2-5.4 Hz, also drifting with distance). A dot vanishes where its ray meets a wall/object (that surface lights and vibrates instead); dim off-axis by the beam. Struck surfaces: horizontal contour lines + edges, damped 7 Hz sine, ~0.9 s, clocked from when the front passed each point. Floor ring always, ceiling ring only indoors. Mockup: air-vibrate artifact (https://claude.ai/artifact/MTK9h8ui462Rg5p5FNqKC5), source in the session scratchpad echo-air-vibrate.html (copy in docs/mockups/echo-air-vibrate.html).
- [x] (visuals: render.js beamGain/beamReach, aim fixed per pulse; audio beam separate) Mouth beam must shape ring brightness and reach in the visuals too (not only audio): 0/-1/-3/-8/-14/-18/-20 dB at 0..180 deg

Already done, NOT in v0.11: door texture, window glow shader, glass lets light, villager redo, ripple-only vision.

## Requested 2026-10-18 (todo only)
- [x] Lights: player can't see light sources themselves — only glow under ripple; holders shown under ripple (v0.10.5–0.10.6)
  - [ ] Later: some villagers carry lanterns (moving glow + held lantern shown by ping).
- [x] Fire sound: steady quiet hiss, no periodic pulse (v0.10.6)
- [x] (v0.10.14 drag, v0.10.18 struggle/break-free) Drink grab: animation pulls the victim close. Player can move slowly while drinking to drag them into shadow. Victim resists (slows/pulls back), resistance falls as their blood drains.

## Requested 2026-10-18 (b) — design pass, todo only
### Hidden meter (light readout)
Now: lit ≥ 0.3 → warm edge vignette. Binary-feeling, easy to miss, reads as "warmth" not "seen".
- [x] (v0.10.14/v0.10.18, beside the vial) Add small "veil" meter, bottom-left by blood bar, same doodle line style.
  - Icon: closed eye (hidden) → half-lid → open eye with lashes (exposed). 3 states + smooth fill.
  - Bar: 5 ticks, value = world.lightAt at player (already computed for vignette), smoothed ~0.3 s.
  - Colours: cold blue-grey hidden → candle gold exposed (match window/door tints). No flashing; gentle 0.5 Hz breathe at full exposure only (≤3 Hz rule).
  - Text alt for screen readers + large-text scaling.
- [ ] Keep vignette but tone down (it becomes secondary); setting to turn it off.
- [ ] Tie meter to real mechanic: villager notice/fear gain scales with exposure (check people.js spotting uses same value — one source of truth).
- [ ] Tutorial hint `tut:light` first time meter > 50%.

### Villager heartbeat (circulatory)
Done (0.11.3 + 2026-10-21 commits 8fc8568..079d97f): heartbeat audio (`Audio.heartbeat`, level `vheart`), rate by state (`heartBpm`: calm 65, wary 90, startle 100, flee/cower 130, x `0.5+0.5*left/pool`), nearest 2 villagers, heard and shown within 2.5 cells, chest-high pulse per beat, brighter/longer pulse, quieter breathing. Not yet played by ear/eye.
- [x] Heartbeat audio, state-driven rate, nearest 1-2 only, chest pulse (see above).
- [ ] Occlusion: hear a hidden villager behind a door (Echoes occlusion filter). Volume setting under Ambience.

#### Whole-body circulatory pulse (proposed 2026-10-21, Opus code read + Sonnet physiology; awaiting user answers to open questions)
Goal: the whole vessel network pulses on each beat, strongest at the heart, travelling out and fading toward hands/feet. Render-side overlay on the existing `vheart` echo; no extra sonar pulses. Flag `vis.vessels` (default off), tunables `vessels.*`.
- [ ] P1 Data + pure helpers: `js/data/vessels.js`, ~15-node tree rooted at heart, each node anchored to a `drawPerson` pose slot (0 head, 1 neck, 2/3 shoulders, 4/5 hips, 6/7 hands, 8/9 feet, 10/11 elbows, 12/13 knees, 14 torso) so it follows every pose. Per node: `pathLen`, delay `pathLen*m/PWV`, weight `w`, hotspot boost. Unit tests (tree, monotonic delay/weight).
- [ ] P2 Snapshot fields `bpm`, `periphK` on the echo (people.js ~1151) from `stepHeartbeats`; cap bpm at 175 (<3 Hz); unify drink bpm formula with `drinkBeat` (game.js 770-780).
- [ ] P3 `drawVessels(r,e,X,Y,age)` in render.js behind flag, static nodes, drawn after the body outline and ignoring the chest-only strip mask (body outline stays chest-only).
- [ ] P4 Travel: per-node delay + envelope (attack ~0.06 s, decay tau ~0.25 s), extend vheart echo life to ~0.5 s so far nodes are not cut off.
- [ ] P5 Edges with travelling highlight, quality gating (q2 edges+nodes, q1 nodes, q0 chest only), reduced motion (no travel, one soft pulse, alpha <= 0.5).
- [ ] P6 State tuning, devpanel tuns, smoke check (foot lights after chest), DESIGN.md rows replacing "chest pulse".
- [ ] P7 Playtest, then flag on by default.

Physiology reference (adult ~1.7 m, game-tuned):
- Path from heart (m): neck 0.25, head 0.40, wrist 0.90, fingertip 1.05, groin 0.70, knee 0.95, ankle 1.35, toes 1.50.
- PWV default 6 m/s (child 5, old 8-9). Delays: carotid ~40 ms, head 65, wrist 150, groin 115, ankle 225, toes 250. May scale 1.5-2x (`pwvScale`) so travel reads, feet must still lag head.
- Strength falloff (fraction of heart): arch 0.9, neck 0.75, head 0.5, upper arm 0.55, wrist 0.35, hand 0.2, groin 0.6, thigh 0.5, knee 0.4, ankle 0.25, foot 0.15 (~0.8 per 0.2 m in small vessels).
- Hotspot bloom: carotid +60%, heart apex +50%, femoral +40%, radial +35%, temporal/brachial +25%, ankle/foot +20%, knee +15%.
- Beat shape: lub = big launch, dub (dicrotic) ~0.3 s later at ~30% intensity; systole ~35% of cycle at rest, diastole shrinks faster at high bpm. At 130 bpm two waves can be in the body at once.
- States: calm 65 bpm strength 1.0; wary 90 / 1.15 (neck/temple brighter); fear/flight 130-140 / 1.4-1.6, hands/feet constrict (dim), big muscle bright; sleep 50-55 / 0.8; blood loss: extremities dim first, core stays, strength ~ blood_fraction^1.5, HR rises then collapses below ~40% blood, stops at empty. Cold extremities: distal 0.05-0.1 and delayed, blue-tinted.
- Veins (optional, later): darker/bluer edge set, slow steady drift (~0.1-0.3 m/s), no sharp pulse.

Open questions for the user: (1) real-time wave vs slowed `pwvScale` for readability; (2) full-body vessels leak limbs/pose, making heartbeat a stronger hunting cue than a ping, intended?; (3) show through walls like Warm sense, or only when the pulse is visible?; (4) keep 2.5-cell range and nearest-2 cap?; (5) dots vs vessel lines, coral vs warm-tinted white; (6) suppress villager heartbeat for the drink victim (drinkBeat already beats at a different rate)?

### Footstep rings (villagers)
Now: personStep range 0.7, strength 0.35, fade 0.7 (sounds.js) → reads as big full rings.
- [x] (v0.10.13: range 0.4, strength 0.25) Shrink: range ~0.35, strength ~0.2, shorter fade.
- [ ] Restyle: small floor-only ellipse "scuff" (flattened, ground-hugging), not a full ring; alternate left/right offset per step so it reads as feet; no bounce pass.
- [ ] Keep it lighting floor only (no walls) so player pulses stay the main reveal.

## Requested 2026-10-18 (c) — windows + eavesdropping, todo only
### W1 Windows hidden (like lights)
- [x] (v0.10.12) Window frame/panes not drawn by default. Only a sonar ripple reveals them, lingering a bit longer than walls (≈1.5× afterglow) since glass rings.
- [ ] Keep the candle-gold / cold-glass tint on the revealed outline; keep floor light spill always (that's light, not the window).
- [x] (v0.10.12) Remove the always-on window glow (render.js window glow, 0.7 Hz) → glow only shows as the lit spill.
### W2 Listen at windows (mechanic)
- [ ] Stand at a lit window, hold E (or crouch) → "listening": muffled voices from the room behind.
- [ ] Glass muffles: lowpass ~1.2 kHz + TL gain (v0.11 Echoes glass row). Open/broken window = clearer.
- [ ] Reward: reveals headcount + who's inside (Warm-sense halos through the wall while listening), maybe a hint ("the baker sleeps alone").
- [ ] Cost: listening is still/slow; standing at a lit window raises exposure (Hidden meter).
### W3 Villager voices (synth)
- [ ] Formant-synth gibberish, "Charlie Brown adult" muffled-horn feel + quasi old-Bavarian flavour (oa, ü, ö, "sch", rolled r, "ja-ja", "na").
- [ ] Voices per villager (seeded pitch, speed, wobble): man, woman, elder, child.
- [ ] Conversation engine: turn-taking, pauses, overlap, laughs, questions (rising end), argument (faster, louder).
- [ ] Mood follows village state: calm chat → whispers/worried when fear high → silent if they heard you.
- [ ] Also: outdoor villagers mumble when sitting together; startle line when bumped.
### W4 Tests/data
- [ ] `data/voices.js` (syllable sets, voice presets), voices in audio.test.js (deterministic per seed, voice cap ≤ 4 concurrent), smoke: listen at a window, no errors.

## Requested 2026-10-18 (d) — living village, todo only
### V1 Night schedules (pathing)
- [x] (v0.10.19, not seeded per night; roles differ from this list) Each villager gets a role + a night schedule (seeded per night): list of stops with times, built at dusk, covering the whole night length.
  - Roles: baker, innkeeper, drunk, watchman/lamplighter, priest, mother/father/child (family home), courting pair, elder, maid, dog-walker, insomniac.
  - Stops: home, tavern, church, well, a friend's house, bed. Times scale with nightLengthMin.
- [x] (v0.10.19 `routeTo` lit-preferring Dijkstra) Paths prefer torch-lit streets (existing lightPref) and use a precomputed street graph (nodes at junctions/doors) instead of loose patrol loops; replaces the 9 hand loops.
- [ ] Schedule visible in debug overlay (`?debug=1`): who, current stop, next stop, ETA.
- [ ] Interruptions (fear, bumped, heard you) pause the schedule; they resume or go home early if fear is high.
### V2 Villager-to-villager interactions
- [ ] Meetings: two villagers on the same node stop, face, short chat (voice synth), part.
- [ ] Spouses greet at the door (hug pose + warm "Servus, Schatzl"); parent calls child in.
- [ ] Drunks: wobbly path (sine drift), slow, sing/mumble, chance to stumble; small chance to fall (sit on ground ~4 s, groan, get up). Easy prey but loud.
- [ ] Children run (speed ×1.4 vs adults), dart, stop suddenly; scared faster.
- [ ] Others to consider: watchman checks doors + carries lantern (moving light = danger); dog barks at you if close; elder walks slow with a cane tap; courting pair whispers in a dark corner; argument outside the tavern; someone smokes on a doorstep (tiny glow).
- [ ] Gossip spreads fear: villagers who meet pass on "something's out there" (fear +small) — ties to existing village fear.
### V3 Models
- [ ] Body types per role: child (short), elder (stooped), drunk (sway), plump baker, lanky watchman. Reuse Fable accessories; add poses: greet/hug, sit-at-table, stumble, fallen, drink.
- [ ] More villagers overall (target ~1.5× now), checked against FPS budget.
- [ ] Future: clothing layers (aprons, cloaks, shawls, hats) as outline doodles per role.
### V4 Dinner tables at windows (skulking)
- [ ] Interiors: tables placed by lit windows in houses + tavern; families sit and eat during the evening part of the schedule (sit pose, spoon clinks, chatter).
- [ ] This is the main eavesdrop target (ties to W2 listening).
### V5 Subtitles (overheard speech)
- [ ] When the player is close enough to make out words (distance + occlusion), show subtitles: quasi-Bavarian line + English translation underneath. Farther away = muffled voice, no subtitles (or "(muffled talking)").
- [ ] Setting: subtitles on/off, translation on/off. Large-text aware.
### Tweak
- [ ] Closed-window voices muffled more (done in the test page: glass lowpass 900 → 600 Hz, dry 0.75 → 0.55, less reverb).

## Requested 2026-10-18 (e) — village life, todo only
### Audit of the current town (facts, v0.10.3)
- Town 64×48 cells. 14 villagers.
- Buildings: tavern, church, 2 houses, cellar, barn, shed, mausoleum. Only 2 homes for 14 people → not enough beds.
- Crypt = mausoleum in a fenced graveyard top-left. Church is top-right, across the tavern. Graveyard is NOT the church's.
- No town walls or gates, no square, no shops.
### V2+ Interactions (notes)
- [ ] Weighted meetings: chance of chat / hello / ignore by role pair (spouses hug, friends chat, drunk vs priest = scolding, kids vs elder = shooed). Table in data.
- [ ] Children play in streets with medieval toys: hoop and stick, spinning top, ball, hobby horse, knucklebones, whirligig. Fallback: tag/chase.
- [ ] Child screams: louder + bigger alert radius (~1.5× adult).
- [ ] Voices emit a small sonar pulse (like ours, weaker): range ~1–1.5 cells, z at head height, lights speaker + nearby surfaces. Closer = brighter (gain by distance to player).
  - Plus "speech arcs": small floating arcs by the mouth, only within hearing. Drawn in the air.
### V3+ Models
- [ ] Height tall/medium/short for every gender and age group (child short scale applied on top).
### Perf (gate for everything)
- [ ] Target 60 fps (now ~41–49 headless). Not code size: profile the frame. Ideas: cache wall/door/window strips to offscreen canvases, sprite atlas for villagers per pose, no per-frame allocations, spatial grid for people/props/lights, LOD (far villagers = simple outline), cap pulses drawn, skip unseen rooms.
- [ ] Minify only for the itch zip (optional build step; keep source plain).
### V6 Items, light and fire
- [ ] Items: torch, candle, lantern, matches/tinderbox, basket, plus basket goods (bread, apples, cloth). Player can pick up, carry (small inventory, 3–4 slots), drop, steal, throw.
- [ ] Snuff lights (torch, candle, lantern; fireplace no). Dark spots become your hiding paths.
- [ ] Villagers react to an out light: relight it, light their own lamp/candle, or (fear high) go tell someone/the watch.
- [ ] Candles per location by use: dinner tables, bedside, church altar (many), tavern tables, shop counters, window candles. Fireplaces in every house + tavern (big glow, crackle, can't snuff).
- [ ] Villagers use light: carry candle to bed, light lantern before going out, bank the fire at bedtime (house goes dark late).
### V7 Buildings and map
- [ ] Mock up medieval village building designs first (Design artifact): timber-frame houses, bakery, smithy, inn, chapel, shops with shutters, well, square, walls + gates. Pick one, then build.
- [ ] Map bigger: ~1.5–2× area. Town walls with 2 gates, town square with well + market stalls closing up, ~8 homes (3–4 people each), bakery, smithy, shops.
- [ ] Move the crypt into the church graveyard (mausoleum by the church, side door into the church).
- [ ] Nightfall state: shops closing, last purchases, people carrying baskets home, stalls being packed.
- [ ] Baskets: villagers drop them to flee or throw stuff at you (stun/knockback light, noise).
### V8 Animals
- [ ] Livestock: pigs, goats, sheep, chickens, a cow, a horse in barn/pens. Each: outline model, idle/sleep actions, sounds, a small blood pool.
- [ ] Feed on livestock: small blood, no Essence. Found drained animals → next nights villagers get dogs, keep watch, lock doors.
- [ ] Cats (ignore you, hiss, sonar-visible on walls/roofs) and mice (tiny skitter, tiny blood snack).
- [ ] Dogs: bark at you within range, alert owners.
### V9 Watch
- [ ] Watchmen patrol both gates (outside + inside), lanterns, call the hour, respond to alarms.
