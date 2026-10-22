# Vampires Can't See

You are a vampire, and you cannot see. You echolocate like a bat: every click sends a sonar pulse through a medieval village at night,
and the walls light up for a moment and fade. People are never drawn directly. A pulse that reaches someone leaves a fading echo of their
outline where they stood. Ping again to see where they went.

Find a villager, drink in the dark, and get back to your crypt (or a safe, dark spot) before dawn. Survive five nights to win the run.

**This repository is now the Godot version (alpha).** The original browser game lives in [`html-version/`](html-version/) and is kept as the
reference the port is checked against (do not edit it from port work).

> **Known problem:** the alpha is very laggy in play. It is the top item in [AI_HANDOFF.md](AI_HANDOFF.md). Try Effects 0 or 1 in Settings.

## Play

1. Install nothing: the Godot 4.4.1 binary is expected at the repo root as `Godot_v4.4.1-stable_win64.exe` (not committed: `*.exe` is git-ignored, download it from godotengine.org).
2. Double-click `play.bat` (or run `Godot_v4.4.1-stable_win64.exe --path project`). The first launch imports the audio, which takes a minute or two.

Headphones are strongly recommended: sound comes from where it happens, and it is half the game.

| Input | Action |
|---|---|
| Left-click / Space | Sonar pulse (works while you hold someone) |
| W A S D / arrows | Move and turn (the mouse turns too) |
| Hold right-click / R | Grab and drink from someone in front of you |
| Hold E while drinking | Restrain your victim (muffled, but half drink speed) |
| E | Open or close a door; sleep at your crypt or a safe spot |
| Hold E at a lit window | Listen to the people inside |
| G | Throw a rock (3 per run) |
| Q / Shift or C / F | Shriek / Mist / Still (unlock on nights 1, 2, 3) |
| Esc | Pause |
| F3 | Debug text (debug builds also: M top-down map, F9 developer panel) |

Menus: New run / Continue, Shop, Stats, How to play, Export / Import save, Character creator, Settings.
Saves, settings and logs live in `%APPDATA%\Godot\app_userdata\Vampires Cant See\` (`vcs_run.json`, `vcs_meta.json`, `settings.json`, `flags.json`, `creator.json`, `seen.json`, `vcs-log.txt`).
Full rules and numbers: [html-version/docs/MANUAL.md](html-version/docs/MANUAL.md) (the rules are identical).

## What changed from the browser version

A full GDScript port for Godot 4.4.1 (Compatibility renderer). The JS game is the single source of truth: it is untouched, and the port is checked against it
with Node-generated golden fixtures (about 1.1 million checks in 84 tests, including exact draw-call hashes for every figure, sprite, floor effect, HUD element
and the vessel overlay).

- **Same game:** sonar view with GPU wall, floor and ceiling shaders; echo people on a canvas layer; Forge and Schedule villagers with routines, conversations, barks and voices;
  listening at windows; feeding with struggle and restraint; powers, fear, blood gifts, the Essence shop, boons; 5-night runs; JS-compatible saves with export and import.
- **Look:** line and volumetric villagers (outfits, faces, hats, role items, rim light), the whole-body vessel pulse, hand-drawn HUD and icons, post effects (bloom,
  dusk/dawn grade, vignette, grain), the crypt title screen, warm-sense halos, head bob.
- **Audio:** the original synth voices re-baked to WAV (`tools/bake-audio.mjs`), ambience beds, heartbeats, breath, live villager speech.
- **Tools:** character creator, F9 developer panel with flags and tunables, M top-down map, log buffer and error screen, boot checks.
- **Differences:** fixed 640x360 internal frame scaled to the window; no browser tab lock; system file dialogs for save export and import;
  no adaptive-quality governor yet; no Windows export yet. The full list of what is not included is in [AI_HANDOFF.md](AI_HANDOFF.md).

## Repository layout

```
project/            the Godot project (project.godot): core/ game/ render/ ui/ audio/ data/ tests/
tools/              Node tools: golden fixture generators (tools/golden), audio baker, data exporter, JS reference-shot server
docs/               PORT.md (JS -> GDScript map), PARITY.md (fixtures, tolerances, go/no-go, known gaps)
PLAN.md             the original porting plan and phase list
AI_HANDOFF.md       start here if you are an AI or a new developer: rules, commands, architecture, NOT included, TODO
HOWTO-CLI-ANYTHING-GODOT.md, godot/, skills/, CLI-ANYTHING-HOWTO.md    the command-line harness used to drive Godot
html-version/       the original browser game (index.html, js/, css/, tests/, docs/, tools/, dist/): reference, do not edit
play.bat            launches the game
```

## Develop and test

```
Godot_v4.4.1-stable_win64.exe --headless --path project -s res://tests/run_tests.gd                      # everything (about 9 minutes)
Godot_v4.4.1-stable_win64.exe --headless --path project -s res://tests/run_tests.gd -- --filter=vessels  # one file
node tools/golden/<name>.mjs                                                                              # regenerate a fixture from html-version/js
```

Windowed scenarios (screenshots): `Godot_v4.4.1-stable_win64.exe --path project --rendering-driver opengl3 --write-movie <absolute dir>\f.png --fixed-fps 60 --quit-after 120 -- --scenario=<name>`
(scripts in `project/tests/scenarios/`). Parity details: [docs/PARITY.md](docs/PARITY.md). Module map: [docs/PORT.md](docs/PORT.md).

## Not yet judged by a person

Audio, the hand-drawn look against the browser version, and performance on other machines. Everything else is covered by the parity tests.
