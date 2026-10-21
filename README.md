# Vampires Can't See

A first-person browser game. You are a vampire. You echolocate like a bat:
each click sends out a sonar pulse that lights up the walls around you.
At night, go out to find people and get back to your crypt or a safe dark
space before dawn, so you can sleep through the day.

Current build (v0.11.8): sonar pulse, first-person outline view, settings, people
who walk set paths through the maps, one night at a time (feed, sleep
and dawn; see Night rules below), a main menu, an upgrade shop, night boons,
random runs and saves. You never see a person directly:
when a pulse reaches them it leaves a fading echo of their outline where
they were, so repeated pulses show you where they are heading. Walls quiver
as the wavefront passes and struck people send out small rings of their own.

The look is quirky and hand-drawn: lines wobble ("boil") a few times a
second, the title is drawn letter by letter on a crooked baseline with a
little bat, and menus have uneven, slightly tilted borders. Sounds come
from where they happen: footsteps are tiny rings on the floor at the foot
that landed (left and right alternate), so they light only wall bases, while
your ping comes from head height. The audio is cartoonish (bip ping,
creaky doors, hollow tok). If the wobble bothers you, turn off
**Wobbly lines** in Settings.

## How to play

Double-click `index.html` to open the game. No install or server is needed.

- Click to start (this also locks the mouse for turning).
- Left-click or Space: send a sonar pulse (the walls around you light up
  and fade)
- E: open or close a door in front of you (walking into a closed door also
  opens it); sleep at your crypt or a safe spot (crypt and safe spots
  answer with a knock)
- Hold right-click or R: grab and drink from a person within 1.5 cells in front
  of you (even one who has noticed you or is cowering). Let go or press Esc to stop; left-click or
  Space still pings while you hold them; you drag your victim slowly while drinking (full victims resist; look is halved). With "Click to
  start/stop drinking" on in Settings, click instead of holding. Drinking with
  nobody in reach plays a soft miss sound
- Hold E while drinking: restrain your victim. Your arms pin theirs, they cannot break free and their struggling is muffled,
  but you drink at half speed while your hands are busy
- G: throw a rock where you face (3 rocks per run, 1 s between throws). It lands with a loud clatter, sending sound waves that light up the
  surroundings and startle villagers nearby: use it to lure them or cover your tracks
- Q shriek · Shift or C mist · F still: use a power (see Powers)
- M: toggle the top-down map view (debug builds only, `?debug=1`)
- W / S: move forward / back
- A / D: strafe left / right
- Mouse: turn (with the mouse not locked, drag with the left button to look)
- Up / Down arrows: move forward / back
- Left / Right arrows: turn
- Esc: pause (Esc again or Resume to continue)
- F3: toggle the debug overlay

Sound: browsers block audio until the page gets a click, so click the title
screen once to turn sound on.

## Tips

Listen for breathing: people close to you breathe audibly, so the sound tells
you where they are. The crypt bell rings every 20 to 40 seconds from the
direction of your crypt, so follow it home. Light means you can be seen:
torchlight shows you to people, so drink and hide in the dark.

## Night rules

- A night runs from 20:00 to 06:00. Real time for one night is set by
  `nightLengthMin` in the config (default 4 minutes).
- Blood starts at 10 out of 100 and drains over the night (30% faster than the base rate since v0.10.20). Drinking (hold right-click)
  fills the bar while each person's own blood pool (30 to 50) lasts; the flow
  is faster when they are full and slows as they empty, capped at 100. A drained person stays still for the night. Let go early
  and they are dazed for 3 s, then run off silently with what is left. Below 25 blood you are weak: your pulses
  get shorter and dimmer.
- Drink in the dark. Your victim's heartbeat sends out a pulse that grows as
  you drink, and anyone near it freezes and turns toward the sound. If another
  person sees you (torchlight, or within 1 cell) they flee and the drink ends.
  Grabbing someone from the front makes them gasp.
- Up close (about 2.5 cells) you hear the nearest villagers' hearts. Each beat
  lights their chest and sends a red pulse through their whole body: it
  starts at the heart and travels out to the hands and feet (arteries red,
  veins a deeper red-blue). Fear speeds it up and dims the hands and feet;
  blood loss fades the limbs first. Walls hide it; through a window it shows
  dimmer. Turn it off with `?sys=vis.vessels:off` or in the dev panel.
- At 05:00 a bell chime sounds. From 05:30 your pulses fade outdoors.
- At 06:00 dawn comes. If you are outdoors then, the run is lost. Indoors
  you can keep going, but stepping outside while it is day loses the run.
- Sleep at the crypt or a safe spot (E) to end the night. Survive five
  nights to win the run.
- The farthest safe spot in town pays +5 Essence each time you sleep there.

## Blood gifts

Drink while your blood is full and the extra fills the **overflow** bar. When
it is full, the drink ends and you pick one of three gifts (keys 1, 2, 3 or
click). The first costs 40 overflow, the second 60. Two gifts per night at
most; after that, drinking at full blood works as before. The count resets
when you sleep. Each gift adds 2 Essence at the end of the run.

| Gift | Effect |
|---|---|
| Keener Ear | Sonar range ×1.05 |
| Longer Echo | Sonar fade time ×1.05 |
| Quicker Call | Pulse cooldown ×0.95 |
| Slower Thirst | Blood drain ×0.95 |
| Deeper Draw | Drink rate ×1.08 |
| Quieter | Noise ×0.95 |
| Calm Town | Fear −2 |
| Reserve | +10 blood at the start of the next night |

## Powers

Spend blood to use a power. Each one unlocks on a night and has its own
cooldown. Costs and cooldowns never change. You cannot use a power you cannot pay for.

| Power | Key | Unlock night | Cost | Cooldown | Fear | Effect |
|---|---|---|---|---|---|---|
| Shriek | Q | 1 | 15 | 6 s | +2 | Pulse reaches twice as far; people react from 2.5× startle distance. Still does not silence it |
| Mist | Shift | 2 | 10 | 3 s | +1 | Dash 2 cells along your move direction (or facing, if idle); stops at walls. Silent, and bumps go unnoticed |
| Still | F | 3 | 10 | 12 s | +1 | For 5 s, your pings, doors and footsteps do not alert people, and bumps go unnoticed |

## Fear

Fear runs from 0 to 15. It is shown as eyes near the dawn clock, three fear
per eye, up to five eyes.

- Rises +1 the first time you grab each person in a night.
- Shriek +2, Mist +1, Still +1.
- Sleep −5 (not below 0). Calm Town gift −2.
- Higher fear makes people startle and flee sooner: startle distance rises
  4% per point (up to +60%), flee speed 1.5% per point (up to +20%), and they
  take longer to calm down (up to +60%).

## Drain ramp

Blood drains faster each night. Night N drains at 1.3 × (1 + 0.12 × (N − 1)) times
the base rate: night 1 is 1.0×, night 5 is 1.48×.

## Main menu

- **Continue**: resume the saved run (off when there is no run saved).
- **New run**: start a fresh run. If a run is in progress, click twice to
  abandon it; an abandoned run counts as a loss.
- **Shop**: spend essence on upgrades.
- **Stats**: runs, wins, nights survived, people fed, best nights and essence earned.
- **Export save** / **Import save**: download your progress as a `.json` file,
  or load one.

## Essence

Essence is the currency for the shop. A run ends with
**nights survived × 4 + people fed**, plus **15 for a win**, **2 for each
blood gift** taken, and **5 for each sleep at the far safe spot**. You get the
essence when the run ends, whether you win, lose or abandon it.

## Upgrade shop

Each upgrade has three tiers. Costs are 5, 12 and 25 essence for tiers 1 to 3.
A tier sets the effect; it does not add to earlier tiers.

| Upgrade | Effect | Tier 1 | Tier 2 | Tier 3 |
|---|---|---|---|---|
| Far Echo | Sonar range | ×1.15 | ×1.3 | ×1.45 |
| Lingering Echo | Sonar fade time | ×1.2 | ×1.4 | ×1.6 |
| Quick Call | Pulse cooldown | ×0.9 | ×0.8 | ×0.7 |
| Full Veins | Starting blood | +10 | +20 | +30 |
| Slow Thirst | Blood drain | ×0.9 | ×0.8 | ×0.7 |
| Deep Draw | Drink rate | ×1.15 | ×1.3 | ×1.45 |
| Soft Step | Startle radius | ×0.85 | ×0.7 | ×0.55 |
| Long Night | Night length | ×1.1 | ×1.2 | ×1.3 |
| Warm Sense | Warm halo radius (cells) | +3 | +5 | +7 |

## Night boons

After you sleep, pick one of three boons (click it, or press 1, 2 or 3).
Boons last for the rest of the run. Each boon can be picked once per run,
except Full Belly.

| Boon | Effect |
|---|---|
| Bat's Ear | Sonar range ×1.1 |
| Echo Memory | Sonar fade time ×1.15 |
| Quick Ping | Pulse cooldown ×0.9 |
| Cold Blood | Blood drain ×0.85 |
| Fast Fangs | Drink rate ×1.2 |
| Hush | Startle radius ×0.8 |
| Moonlit | Night length ×1.1 |
| Warm Hint | Warm halo radius +2 cells |
| Full Belly | +25 blood now (can be picked again) |

## Random runs

Each new run is different. People start at different points on their paths,
and some walk their path in reverse. On maps with two or more safe spots,
on maps with two or more safe spots, a third of them (rounded down) are sealed
for the run. In town that is one of the three. The crypt is never sealed.

## Saving

- The run saves automatically every 20 seconds of play. It also saves when
  you pause, change map, or switch away from the tab.
- If the game is open in a second tab, saving pauses in the other tab. A small
  "not saved" dot shows on screen while a save fails or is paused.
- The run is stored under `vcs.run`. Upgrades, essence and stats are stored
  under `vcs.meta`. Each has a `.bak` backup copy.
- The run save is deleted when the run ends.
- Run saves use schema v4. Older v3 run saves still continue.
- Saves live in this browser only. Use **Export save** to keep a copy.

If something goes wrong, see [TROUBLESHOOTING.md](TROUBLESHOOTING.md).

## URL flags

- `?debug=1`: verbose logging, the F3 overlay, and the M map view on from
  the start. Also enables the test hooks below.
- `?map=NAME` (only with `?debug=1`): start on a named map, for example
  `?debug=1&map=test`.
- `?safe=1`: ignore saved settings and start with defaults.
- `?sys=ID:on|off` toggles a feature flag for this load, for example
  `?sys=vis.vessels:off` turns off the whole-body heartbeat pulse (on by
  default). `?tun=sys.key:value` sets a tunable, for example
  `?tun=vessels.halo:0.3`.

## Debug hooks (debug builds only)

These are on `VCS.Game` and exist only with `?debug=1`. They are for testing
and are not part of play.

- `debugState()`: a snapshot of the game state, including the night clock,
  blood, status and fed count.
- `debugTime(h, m)`: set the night clock (20:00 to 06:00 only).
- `debugBlood(v)`: set blood (0 to 100).
- `debugFeed()`: grab and start drinking the person in front of you (held until a stop rule fires). Returns true if it started.
- `debugFeedHold(seconds)`: start a drink and hold it for up to that many simulated seconds, then let go. Returns true if it started.
- `debugPeopleState()`: the live People state of the current map.
- `debugSleep()`: sleep if you are at a crypt or safe spot. Returns true if it started.
- `debugNight()`: a copy of the night state.
- `debugPulse()`, `debugTeleport(x, y, angle)`, `debugAdvance(seconds)`,
  `debugInteract()`, `debugEchoes()`, `debugMap(name, doorId)`, `debugZone()`:
  pulse, move, step time forward, interact, read echoes, jump to a map, and
  read the current zone.

## Running the tests

Requires Node 22.

    node --test tests/*.test.js
    node tests/smoke.mjs

`tests/smoke.mjs` drives the game in Chromium through Playwright. It needs
Playwright installed and writes a screenshot to `tests/out/smoke.png`.

## Folder layout

    index.html          the page (double-click to run)
    css/style.css       layout and overlay styling
    js/                 game code, classic scripts, no build step
      log.js            logging and error reports
      config.js         settings with validation and localStorage
      checks.js         browser feature checks
      data/maps.js      map data and people paths
      data/sounds.js    sound levels (range, strength, gain, fade)
      data/upgrades.js  upgrade and boon data
      world.js          map loading and collision
      raycast.js        ray casting for walls and the sonar view
      sonar.js          pulse wavefront and echoes
      audio.js          Web Audio sounds (pings, steps, doors, night sounds)
      ripple.js         wobble helper and secondary echo rings
      people.js         walkers on paths, feeding and echo snapshots
      night.js          night clock, blood, dawn and sleep (pure state)
      meta.js           upgrades, essence and stats kept across runs
      save.js           safe storage, checksums, backups and import/export
      icons.js          hand-drawn icons, tombstone and crypt menu
      render.js         first-person view and outlines
      hud.js            blood vial, dawn clock dial, cards and fades
      input.js          keyboard and mouse input
      player.js         player movement and turning
      game.js           main loop, states, menus and overlays
      hunger.js         overflow gifts, powers and fear (pure state)
      data/hunger.js    gift, power and fear data
      data/vessels.js   vessel graph and timing for the whole-body heartbeat pulse
    tests/              node:test unit tests and the smoke test
    tools/sim.mjs       economy simulation (node tools/sim.mjs)
    docs/DESIGN.md      rules, numbers and design for all modules
