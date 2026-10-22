---
name: "cli-anything-godot"
description: "Create and edit Godot 4 projects, scenes and GDScript from the command line, and use the real Godot engine to verify, run, render and export them. Use when an agent needs to scaffold or modify a Godot project without the editor GUI."
---

# cli-anything-godot

Stateful CLI for the Godot Engine. It edits `project.godot` and `.tscn` text files natively
and calls the **real Godot executable** for every engine task (import, script checking, scene
verification, headless runs, frame rendering, pack export). Godot is a hard dependency.

## Prerequisites
- Python 3.10+, `pip install -e .` from `godot/agent-harness` (or `pip install cli-anything-godot`)
- Godot 4.x executable. Found via, in order: `$GODOT_PATH`, `cli-anything-godot config set-path <exe>`, then `godot` / `godot4` on PATH.
  If Godot is missing the CLI exits non-zero with install instructions.

## Conventions (read first)
- `--json` (global flag, goes **before** the subcommand) makes every command print machine-readable JSON. Errors print `{"error": "..."}` and exit 1.
- `--project DIR` / `-p DIR` selects the Godot project folder (the one with `project.godot`). Env `GODOT_PROJECT` also works.
- **Auto-save:** one-shot commands commit their edits to disk when they finish. `--dry-run` runs the command but does not save.
  In the REPL nothing is saved until `session save`.
- Every committed edit is undoable across processes: `session undo` / `session redo` / `session history`.
- Scenes/scripts can be given as `main`, `main.tscn`, or `res://main.tscn`; `.tscn` / `.gd` extension is added when omitted.
- Node paths are relative to the scene root: `.` = root, `World/Player`. A path prefixed with the root node name also works.
- Property values are Godot literals (`true`, `5`, `Vector2(10, 20)`, `Color(1,0,0,1)`); anything else is quoted as a string.
- Inspect before you modify: `project info`, `scene tree`, `session status`.

## Commands

| Group | Commands |
|---|---|
| `config` | `set-path EXE`, `show` |
| `engine` | `version` |
| `project` | `new PATH [--name] [--renderer compatibility\|mobile\|forward_plus]`, `info`, `get SETTING`, `set SETTING VALUE`, `unset SETTING`, `settings [--section]`, `set-main-scene SCENE` |
| `scene` | `new PATH [--root-name] [--root-type] [--main]`, `list`, `tree PATH`, `add-node PATH NAME [--type] [--parent] [--prop K=V]...`, `remove-node PATH NODE`, `set-prop PATH NODE KEY VALUE`, `get-prop PATH NODE KEY`, `attach-script PATH NODE SCRIPT`, `verify PATH` |
| `script` | `new PATH [--extends] [--attach SCENE:NODE]`, `check PATH`, `run PATH [ARGS...]` |
| top level | `import`, `run [SCENE] [--frames N]`, `render OUTPUT [--scene] [--frames] [--fps] [--resolution WxH]` |
| `export` | `presets`, `pack PRESET OUT`, `release PRESET OUT`, `debug PRESET OUT` |
| `session` | `status`, `save`, `discard`, `undo`, `redo`, `history` |
| (none) | no subcommand starts the REPL |

Settings are written as `section/key`, e.g. `application/config/name`, `display/window/size/viewport_width`.

## Typical workflow

```bash
export GODOT_PATH="C:/path/to/Godot_v4.4.1-stable_win64.exe"

cli-anything-godot project new ./mygame --name "My Game"
G="--project ./mygame"
cli-anything-godot $G scene new main --root-type Node2D --main
cli-anything-godot $G scene add-node main World --type Node2D
cli-anything-godot $G scene add-node main Player --type CharacterBody2D --parent World --prop "position=Vector2(100, 50)"
cli-anything-godot $G script new player --extends CharacterBody2D --attach main.tscn:World/Player
cli-anything-godot $G script check player.gd           # real engine parse check
cli-anything-godot --json $G scene verify main         # engine loads + instantiates, lists nodes
cli-anything-godot $G run --frames 5                   # headless run of the main scene
cli-anything-godot $G render ./out/frame.png --frames 3   # PNG sequence (needs GPU/display)
cli-anything-godot $G export pack "Web" ./build/game.pck  # needs preset in export_presets.cfg
cli-anything-godot $G session undo                     # revert the last edit
```

## Agent guidance
- Always parse `--json` output; check `ok` on engine commands (`scene verify`, `script check`, `import`, `run`, `render`, `export *`).
- `scene verify` fails (exit 1, `ok: false`) when the engine logs load errors, even though Godot itself loads damaged scenes leniently; `engine_errors` lists them.
- `script run` runs a `SceneTree`/`MainLoop` script headless; stdout from `print()` is in `stdout`. Use this to query the engine (e.g. read `ProjectSettings`).
- `render` and `import` need the full engine; `render` cannot run `--headless` (it needs a display driver).
- `export release|debug` require Godot export templates installed in the editor; `export pack` does not.
- Editing a project that is open in the Godot editor may be overwritten by the editor; close it or reload after edits.
- Undo history lives in `<project>/.cli-anything/history.json` (add it to `.gitignore`).
- Exit codes: 0 success, 1 error/engine failure.
