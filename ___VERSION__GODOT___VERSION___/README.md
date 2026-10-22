# Vampires Can't See: Godot port (alpha)

A Godot 4.4.1 (GDScript, Compatibility renderer) port of the browser game in `../js`. The JS game is the reference and is never edited.
Plan: [PLAN.md](PLAN.md). Module map: [docs/PORT.md](docs/PORT.md). Parity fixtures and known gaps: [docs/PARITY.md](docs/PARITY.md).

## Play

Double-click `play.bat` (or run `..\Godot_v4.4.1-stable_win64.exe --path project`). The first launch imports the audio, which takes a minute or two.

Controls (same as the web game): WASD / arrows move, mouse looks, click or Space pings, right-click or R drinks (hold E to restrain the
victim), E opens doors and sleeps at the crypt or a safe spot, Q shriek, Shift or C mist, F still, G throws a rock, hold E at a lit
window to listen, Esc pauses. F3 shows the debug text. Debug builds also have M (top-down map) and F9 (developer panel).

Menus: New run / Continue, Shop, Stats, How to play, Export / Import save, Character creator, Settings (volume, FOV, effects 0-2,
wobbly lines, reduced motion, large text, subtitles, old bip ping, and more).

Saves, settings and logs live in the Godot user folder (`%APPDATA%\Godot\app_userdata\Vampires Can't See\`): `vcs.run.json`,
`vcs.meta.json`, `config.json`, `flags.json`, `creator.json`, `vcs-log.txt` (from the pause or error screen).

## What is in it

Everything the web game has, except what is listed under "Differences": night clock, blood, feeding with the struggle animation,
powers, fear, gifts, shop, boons, 5-night runs and saves, the sonar view (walls, floor, ceiling, doors, windows, materials, rings,
arcs), line and volumetric villagers with outfits and faces, whole-body vessel pulse, Forge and schedule driven villagers with
conversations, barks and voices, listening at windows, subtitles, ambience, post effects, tutorial hints, settings, HUD and icons,
the crypt title screen, the character creator, the F9 panel, boot checks and the error screen.

## Differences from the web game

- The Godot frame is a fixed 640x360 internal image scaled to the window; `renderScale` and click-drag look do not exist.
- Vessels and the volumetric figures draw on the CPU like the JS and keep the same 2.5 ms per-frame budget (F9 tunable).
- No browser tab lock, localStorage or file download: saves are files, export and import use the system file dialog.
- Windows export is not set up (needs the export templates).

## Tests

```
..\Godot_v4.4.1-stable_win64.exe --headless --path project -s res://tests/run_tests.gd            # all (about 9 minutes)
..\Godot_v4.4.1-stable_win64.exe --headless --path project -s res://tests/run_tests.gd -- --filter=vessels
node tools/golden/<name>.mjs                                                                        # regenerate a fixture from ../js
```

Windowed scenarios (screenshots): `..\Godot_v4.4.1-stable_win64.exe --path project --rendering-driver opengl3 --write-movie <abs dir>\f.png --fixed-fps 60 --quit-after 120 -- --scenario=<name>`
(see `project/tests/scenarios/`).

## Not yet judged by a person

Audio (F5), the hand-drawn look against the JS (F2), and performance on other machines. Everything else is covered by the parity tests.
