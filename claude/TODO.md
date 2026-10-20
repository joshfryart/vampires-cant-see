# TODO

Each version: Opus pulls src → contract → agents → tests + smoke + screenshot review → publish → update `src/`, HANDOFF.md, TODO.md.

## Next (in order)
1. [ ] Playtest v0.10.14 in browser (new: drink drag, town lights -35%; v0.10.13 items still apply; last playthrough ran 60 fps): step rings differ for sneak/run and grass/wood/stone; windows only under ripple (brief), villager footsteps sound like steps; echo timing (one sonar speed 12 cells/s, echo = round trip), far echoes from distant walls, torch glow/holders under ripple, edge glow direction + smoothness, fire hiss range, devtool ring alignment (`?debug=1`), night 4 min pace, town darkness at 3× radius.
2. [x] Smoke test runs on a real machine (2026-10-20, Windows): 249 pass. Fixed stale night-length check (360 → 240 s). Needs Playwright installed outside the repo, `NODE_PATH` set to its node_modules, then `node tests/smoke.mjs`. First run had one extra failure that did not repeat; watch for flakiness. Still run before each release.
3. [ ] Perf: street 44–52 fps headless (60 fps on real playthrough) → hold ≥50 (vignette → CSS overlay first).
4. [x] Drink grab (v0.10.14; v0.10.17: click/Space pings while holding, no longer lets go; light -35% playtested OK; v0.10.16: start blood 10%; v0.10.15: pools 30–50, rate 7→2.5/s ≈ 9 s per villager; smoke retuned and passing 249 on 2026-10-20; Playwright lives at %TEMP%audepw-tools
ode_modules (NODE_PATH)): hold drink → victim pulled to 0.6 cells ahead, you move at 25% speed (full victim) → 55% (drained), look halved. Tune DRAG_* in game.js. Smoke needs a drag check.
5. [x] Hidden "veil" meter (requested 2026-10-18 b): eye + 5 ticks beside the vial, smoothed `playerLit`; vignette tone-down/setting, fear tie-in and `tut:light` still open below. Same pass: gulp sound, victim struggle/break-free, drag scuffle sounds (untested in browser).
6. [x] v0.10.18 (2026-10-20): villager struggle animations (`js/struggle.js`: panic flail -> push-away -> limp by blood, startle spike per break-free attempt, perspective/yaw cheat in `put`), vampire arms drawn in the held victim's echo, hold E to restrain (no break-free, muffled, half drink speed), G throws a rock (3 per run, saved in snapshot, clatter sound + sonar pulse + startles), rocks HUD pebbles right of skills, veil meter beside vial with skills shifted right, drinking 25% faster (DRINK_BOOST 1.25, ~7 s per villager). Opus brainstormed the move set; GIFs in docs/struggle-*.gif. Untested by hand in browser beyond headless screenshots: playtest restrain/rock feel, pebble placement with 3 powers unlocked, large-text HUD.
7. [x] v0.10.19 (2026-10-20) V1 night schedules: `js/schedule.js` (roles = [places, until, act] over the night fraction; 20:00 = 0, 01:00 = 0.5), town `places` + `role`/`home` per path in maps.js, people.js routes trips with a lit-street-preferring Dijkstra (`routeTo`); sitters and the test map keep their loops. Curfew: all but the watch and night owls are indoors by 01:00 (tested), then abed (seated pose via `seated`). 2 guards patrol the 8 outdoor posts all night in opposite directions (speed 1.3); insomniac + gravedigger stay out until ~0.7; drunk leaves the tavern ~0.26 and is home by ~0.45. Homes: house1 (farmer), house2 (elder, regular, mother; separate cells), barn (drunk, insomniac), shed (gravedigger), tavern (innkeeper), church (priest). Home acts: cook, eat, spin/mend/whittle, sleep (benches as beds). `People.snapshot` has `sched` {role, stop, act, next, walking, eta}. 543 unit pass. Still open: on-screen `?debug=1` readout, go-home-early on high fear, flee along a trip path can wrap through a wall and cower, hearth fires/light inside homes (V6), real beds/lying pose, guard lantern.
7b. [x] Decided: villagers first (V1 done above); v0.11 Echoes after. (was: Decide v0.11 Echoes (sonar speed decided; next = stages S1–S10) vs. v0.11 Villagers.)
8. [ ] Fix `docs/SPEC-echoes.md` lines ~333 and ~386 (still mention `delayMul`).

- [ ] Smoke flakiness diagnosed 2026-10-20 (Fable agent; no game regressions, suite is racy). Fix list, in order: (1) pin Math.random on the lit-walker page `lp` (tests/smoke.mjs ~899-901): struggle() at 0.7 s can break free (40%) and end the drink before the witness flees, so 'lit walker facing away' is a coin flip; also reword the check (struggle noise startles it now, not a heartbeat). (2) optional `?debug=1` hook to stop the rAF loop so time moves only via debugAdvance (real time drifts the 20:00 / blood / pulse-pixel checks). (3) replace fixed sleeps with unswallowed state waits (53 `.catch(() => {})` hide slow boots, cascading into null-state TypeErrors: getContext, .blood, nightLengthMin, essenceBonus). (4) close all 9 leaked pages per section (31 opened, 21 closed; fps drops 60 -> 30-39). (5) per-section try/catch so one error does not skip ~100 checks. (6) pin Math.random in newPg; write screenshots outside OneDrive. Logs were in the scratchpad (run1.log, run2.log).
- [ ] Smoke is flaky run to run (2026-10-20: meta-backup notice, tab-lock, occasional drink checks); pinned Math.random in the drink SETUP so break-free no longer fails drain checks. Playwright installed at %TEMP%cs-pw (NODE_PATH=...cs-pw
ode_modules).
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
- [ ] Per-material echo voices (stone/brick crisp, wood hollow, glass tick, iron ring, grass ~silent, people dull) + matching wave tint
- [ ] Transmission by material: TL = 20·log10(m·f) − 47 dB; cutoff ≈ 6000·10^(−TL500/40) Hz (wood door ~1.4 kHz, glass ~1.1 kHz, brick ~340 Hz); iron gate ≈ open; open door = Maekawa ΔL=10·log10(3+20N)
- [ ] Room tail from Sabine RT60 = 0.161·V/A (cap 2.5 s); corridor flutter (period 2w/c); near-object repetition pitch (<2 m)
- [ ] Mouth beam: click emitted from mouth on front of head (z≈0.58), gain(θ) = 0/−1/−3/−8/−14/−18/−20 dB at 0/30/60/90/120/150/180°; high band narrower than low; slender body = small extra rear shadow; apply to sonar ray strength + echo gain (Thaler 2017 modified-cardioid; mouth ka≈0.9 @3.4 kHz → head/body do the beaming)

## Round 2 candidates
- [x] Guide Mist card "Shift or C" (0.10.3)
- [x] Doors textured + windows (crooked panes, lit glow without ring, floor spill) (0.10.3)
- [x] Harden flaky smoke checks — state-waits, pinned drink pools (0.10.3)
- [x] Light radius (see Done 2026-10-18 above)
- [ ] Vignette → CSS overlay (~1.5 ms); street ≥50 headless
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
- [ ] NEW `SoundData.acoustics` block (cellM, beamDb, spread, airDbPerM, mat.*, zone.t60, rp, rough) — sounds.js
- [ ] UPGRADE materials: world.materialAt exists (floor grass/stone/wood for steps) → add wall materials + `cobble`, `roughStone`

Beam + level:
- [ ] NEW beam table B(θ) on outgoing rays — sonar.js
- [ ] UPGRADE `behind` (now gain ×0.7 / dull buffer) → replace with B(θ). REMOVE old, else double-cut
- [ ] UPGRADE echo level: audio.echo(delay, strength, pan) exists → L_e formula (wall −20log2d, object −40logd, air)
- [ ] UPGRADE raycast: has side + cellX/Y → derive normal + material per hit (no new raycast)
- [ ] REUSE wall-arc incidence (render v0.10) for the angle term; don't add a second

Through walls:
- [ ] UPGRADE occlusion: yes/no → lowpass 600 Hz now → per-material TL filter + G gain, door gap, glass peak
- [ ] NEW Maekawa for open doorways (diffraction)
- [ ] NOTE glass light pass-through (v0.10 world.js) is visual only; sound TL for glass is separate. No conflict

Rooms:
- [ ] UPGRADE reverb: tuneReverb has 2 kinds (indoor fb 0.58 / outdoor 0.25) + setRoom → per-zone T60 → fb = 10^(−3τ/T60), clamp 0.4–2.5 s

Near + rough:
- [ ] NEW repetition-pitch comb (< 1.3 cells, physical delay)
- [ ] NEW diffuse grain tail on rough hits — audio.js
- [ ] UPGRADE visual speckles: ring stipple dots already exist (render.js, seeded) → scale count/linger by roughness, don't add a 2nd pass
- [ ] REUSE matDetail/fps auto-off (render.js) as the gate for speckles

Ping:
- [ ] UPGRADE ping: shorter ~8 ms 3.2 kHz click, old bip as an option (setting)
- [ ] REUSE footstep timbres (audio.js grass/wood/stone) as the base for mat.voice

Tests (extend existing files, no new): audio/sonar/render/world tests per the Docs test plan (10 items) + smoke: all materials in view, no errors, ≤96 voices.

Already done, NOT in v0.11: door texture, window glow shader, glass lets light, villager redo, ripple-only vision.

## Requested 2026-10-18 (todo only)
- [x] Lights: player can't see light sources themselves — only glow under ripple; holders shown under ripple (v0.10.5–0.10.6)
  - [ ] Later: some villagers carry lanterns (moving glow + held lantern shown by ping).
- [x] Fire sound: steady quiet hiss, no periodic pulse (v0.10.6)
- [ ] Drink grab: animation pulls the victim close. Player can move slowly while drinking to drag them into shadow. Victim resists (slows/pulls back), resistance falls as their blood drains.

## Requested 2026-10-18 (b) — design pass, todo only
### Hidden meter (light readout)
Now: lit ≥ 0.3 → warm edge vignette. Binary-feeling, easy to miss, reads as "warmth" not "seen".
- [ ] Add small "veil" meter, bottom-left by blood bar, same doodle line style.
  - Icon: closed eye (hidden) → half-lid → open eye with lashes (exposed). 3 states + smooth fill.
  - Bar: 5 ticks, value = world.lightAt at player (already computed for vignette), smoothed ~0.3 s.
  - Colours: cold blue-grey hidden → candle gold exposed (match window/door tints). No flashing; gentle 0.5 Hz breathe at full exposure only (≤3 Hz rule).
  - Text alt for screen readers + large-text scaling.
- [ ] Keep vignette but tone down (it becomes secondary); setting to turn it off.
- [ ] Tie meter to real mechanic: villager notice/fear gain scales with exposure (check people.js spotting uses same value — one source of truth).
- [ ] Tutorial hint `tut:light` first time meter > 50%.

### Villager heartbeat (circulatory)
- [ ] Heartbeat audio when within ~2 cells: low thump-thump (≈60 Hz sine + 120 Hz click, lowpassed ~200 Hz, "through the body" muffled). Quiet, mono-ish, panned to villager.
- [ ] Rate tracks state: calm 60–70 bpm, wary 90, fleeing/fear 130+, drinking slows as blood drains → stops at empty (dazed = faint slow).
- [ ] Visual (optional): faint warm pulse in Warm-sense halo synced to beat; ≤3 Hz always holds (130 bpm = 2.2 Hz ok).
- [ ] Only nearest 1–2 villagers audible (voice cap). Setting volume under Ambience.
- [ ] Doubles as a stealth/hunt cue: hear a hidden villager behind a door (uses Echoes occlusion filter once v0.11 lands).

### Footstep rings (villagers)
Now: personStep range 0.7, strength 0.35, fade 0.7 (sounds.js) → reads as big full rings.
- [ ] Shrink: range ~0.35, strength ~0.2, shorter fade.
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
- [ ] Each villager gets a role + a night schedule (seeded per night): list of stops with times, built at dusk, covering the whole night length.
  - Roles: baker, innkeeper, drunk, watchman/lamplighter, priest, mother/father/child (family home), courting pair, elder, maid, dog-walker, insomniac.
  - Stops: home, tavern, church, well, a friend's house, bed. Times scale with nightLengthMin.
- [ ] Paths prefer torch-lit streets (existing lightPref) and use a precomputed street graph (nodes at junctions/doors) instead of loose patrol loops; replaces the 9 hand loops.
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
