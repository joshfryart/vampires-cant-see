# cli-anything-godot

Agent-friendly CLI for the [Godot Engine](https://godotengine.org) (4.x). It edits `project.godot`
and `.tscn` scenes natively and uses the **real Godot executable** for importing, script
checking, scene verification, headless runs, frame rendering and pack export.

## Install

1. Install Godot 4.x (hard dependency). Any of:
   - put `godot` on PATH,
   - `export GODOT_PATH=/path/to/Godot_v4.4.1-stable_win64.exe`,
   - `cli-anything-godot config set-path /path/to/Godot.exe` (saved in `~/.cli-anything-godot/config.json`).
2. Install the CLI (Python 3.10+):
   ```bash
   cd godot/agent-harness
   pip install -e .
   cli-anything-godot --help
   ```
   On Windows, `pip` may warn that the `Scripts` folder is not on PATH; add it or use `python -m cli_anything.godot`.

## Usage

```bash
cli-anything-godot project new ./mygame --name "My Game"
cli-anything-godot -p ./mygame scene new main --root-type Node2D --main
cli-anything-godot -p ./mygame scene add-node main Player --type Sprite2D --prop "position=Vector2(10, 20)"
cli-anything-godot -p ./mygame script new player --extends Sprite2D --attach main.tscn:Player
cli-anything-godot --json -p ./mygame scene verify main     # real engine loads the scene
cli-anything-godot -p ./mygame session undo
cli-anything-godot                                          # REPL
```

Global flags (before the subcommand): `--json`, `--project/-p DIR`, `--dry-run`.
See `skills/SKILL.md` for the complete command reference and agent guidance.

## Run the tests

```bash
cd godot/agent-harness
pip install pytest
CLI_ANYTHING_FORCE_INSTALLED=1 python -m pytest cli_anything/godot/tests -v -s
```
The E2E tests launch the real Godot (they fail, not skip, if it is missing). The render test needs a GPU/display.
