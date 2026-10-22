# Vampires Can't See

A first-person browser game. You are a vampire, and you cannot see. You echolocate
like a bat: every click sends a sonar pulse through a medieval village at night,
and the walls light up for a moment and fade. People are never drawn directly.
A pulse that reaches someone leaves a fading echo of their outline where they
stood. Ping again to see where they went.

Find a villager, drink in the dark, and get back to your crypt (or a safe, dark
spot) before dawn. Survive five nights to win the run.

This repository holds two versions of the same game:

| Version | Where | How to run | Status |
|---|---|---|---|
| **Browser game** (reference) | `index.html`, `js/`, `css/` | double-click `index.html` | v0.20.1, complete |
| **Godot 4.4 port** | `___VERSION__GODOT___VERSION___/` | double-click `___VERSION__GODOT___VERSION___/play.bat` | **alpha**, feature-complete apart from the items listed in its handoff |

## Godot port (alpha): what changed

A full GDScript port of the browser game for Godot 4.4.1 (Compatibility renderer), built so the JS game stays the single source of truth:
the JS code is untouched, and the port is checked against it with Node-generated golden fixtures (about 1.1 million checks across 84 tests,
including exact draw-call hashes for every figure, sprite, floor effect, HUD element and the vessel overlay).

- **Same game:** sonar view with GPU wall/floor/ceiling shaders, echo people drawn on a canvas layer, the village routines (Forge and Schedule), conversations, barks and voices,
  listening at windows, feeding with struggle and restraint, powers, fear, blood gifts, the Essence shop and boons, 5-night runs, JS-compatible saves with export and import.
- **Look:** line and volumetric villagers (outfits, faces, hats, role items, rim light), the whole-body vessel pulse, hand-drawn HUD and icons, post effects (bloom, dusk/dawn grade,
  vignette, grain), the crypt title screen, warm-sense halos, head bob.
- **Audio:** the original synth voices re-baked to WAV (`tools/bake-audio.mjs`), ambience beds, heartbeats, breath, live villager speech.
- **Tools:** character creator, F9 developer panel with flags and tunables, M top-down map (debug builds), log buffer and error screen, boot checks.
- **Differences:** fixed 640x360 internal frame scaled to the window, no browser tab lock, file dialogs for save export/import, no adaptive-quality governor yet, no Windows export yet.

Read `___VERSION__GODOT___VERSION___/README.md` to play and test it, and `___VERSION__GODOT___VERSION___/AI_HANDOFF.md` for the architecture, the TODO list
and an honest list of what is **not** included or not yet verified (audio and look have not been judged by a person).

## The browser game

Current build (v0.20.1)

No install, no server, no build step, no network. Plain HTML and JavaScript.

## Play

1. Clone or download the repo.
2. Double-click `index.html` (Chrome, Edge or Firefox).
3. Click the title screen once: this turns on sound and locks the mouse.

Headphones are strongly recommended. Sound comes from where it happens, and it
is half the game.

## Controls

| Input | Action |
|---|---|
| Left-click / Space | Sonar pulse (works while you hold someone) |
| W A S D / arrows | Move and turn (the mouse turns too) |
| Hold right-click / R | Grab and drink from someone in front of you |
| Hold E while drinking | Restrain your victim (muffled, but half drink speed) |
| E | Open or close a door; sleep at your crypt or a safe spot |
| Hold E at a lit window | Listen to the people inside |
| G | Throw a rock (3 per run): a loud clatter that lures villagers |
| Q / Shift or C / F | Shriek / Mist / Still (unlock on nights 1, 2, 3) |
| Esc | Pause |

## What's in it

- **Echolocation.** Pulses travel at a fixed speed, so far walls answer late.
  Echoes depend on material, distance, occlusion and room size: ceiling and
  floor bounces, enclosure-driven reverb, textured ground under the wavefront.
- **A living village.** Villagers keep a night routine: fetch water, drink at
  the tavern, pray, cook and eat at home, then go to bed by 01:00. Two guards
  patrol all night. A gravedigger, a drunk and an insomniac keep odd hours.
- **Voices and eavesdropping.** Villagers talk to each other, eat at tables by
  the windows, bark when startled and struggle when grabbed. Listen at windows
  for their conversations, with optional subtitles and translation.
- **Feeding.** Drink in the dark. Struggle, restraint, blood pools, fear and a
  whole-body heartbeat pulse you can see and hear up close.
- **Runs.** Five nights per run, powers, overflow blood gifts, night boons, an
  Essence shop with three tiers per upgrade, randomised paths and sealed safe
  spots, autosave, and save export and import.
- **Quirky look.** Hand-drawn wobbling lines, a crooked title, tilted menus.
  Turn off **Wobbly lines** in Settings if you prefer. Reduced motion and large
  text options are included.

## Documentation

- [docs/MANUAL.md](docs/MANUAL.md): full rules, numbers, tables for gifts, powers, shop and boons
- [docs/DESIGN.md](docs/DESIGN.md): design notes for every module
- [docs/SPEC-echoes.md](docs/SPEC-echoes.md): the echo and acoustics spec
- [docs/MODULAR.md](docs/MODULAR.md): how the code is split
- [TROUBLESHOOTING.md](TROUBLESHOOTING.md): saves, audio and browser problems

## Development

Requires Node 22.

```
node --test tests/*.test.js
node tests/smoke.mjs
node tools/sim.mjs
```

`tests/smoke.mjs` drives the game in Chromium through Playwright (install it
outside the repo and set `NODE_PATH`). `tools/sound-lab.html` lets you audition
every sound. `tools/character-creator.html` lets you build villagers with every
look option and see them live through the game's own renderer (also linked from
the F9 dev panel).

Add `?debug=1` to the page address for logs, the F3 overlay, a top-down map
(M) and test hooks. F9 opens the dev panel, which has a "Copy error report"
button for bug reports. `?safe=1` ignores saved settings.

The code is classic scripts under `js/` with pure-logic modules kept separate
from the DOM and audio, so most of it is unit tested.
