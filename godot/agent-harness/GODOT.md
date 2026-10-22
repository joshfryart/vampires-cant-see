# GODOT.md: Harness SOP for the Godot Engine

Analysis performed against `godotengine/godot` (shallow clone of master) and Godot 4.4.1 stable.

## Phase 1: Analysis

**Backend engine.** The `godot` executable is both editor and runtime. Features used from the command line
(`main/main.cpp`, confirmed with `--help`):

| Need | Engine flag |
|---|---|
| version | `--version` |
| no window/audio | `--headless` (= `--display-driver headless --audio-driver Dummy`) |
| select project | `--path <dir>` |
| import assets | `--import` (editor build) |
| parse GDScript | `--script <file> --check-only` |
| run a script | `--script <file> [-- user args]` (SceneTree/MainLoop subclass) |
| run N frames | `--quit-after N [scene]` |
| render frames | `--write-movie <file.png\|.avi> --fixed-fps N --quit-after N` (needs a display driver) |
| export | `--export-release/--export-debug/--export-pack <preset> <path>` (editor build) |

**GUI action to CLI mapping.** Create project/scene = write text files; Scene dock add/delete node = edit
`[node]` sections; Inspector property = `key = value` line; Attach script = `[ext_resource]` +
`script = ExtResource("id")`; Project Settings = `project.godot` entries; Run/Export = engine flags above.

**Data model / formats.**
- `project.godot`: Godot `ConfigFile` text (`[section]`, `key=value`, `config_version=5`; values are Godot Variant literals, may span lines).
- `.tscn`: text scene. `[gd_scene load_steps=N format=3]`, `[ext_resource ...]`, `[sub_resource ...]`, `[node name type parent]` (+ properties), `[connection ...]`.
  Root node has no `parent`; its children use `parent="."`; deeper nodes use the path from the root (`parent="A/B"`).
- `export_presets.cfg`: ConfigFile with `[preset.N]` sections.

**Existing CLI building blocks.** The Godot binary itself (above). No other tooling needed.

**Undo system.** The editor's UndoRedo is in-process only; the harness implements its own persistent file-snapshot undo.

## Phase 2: Design

- Interaction: REPL (default) + one-shot subcommands, all with `--json`.
- Groups: `config`, `engine`, `project`, `scene`, `script`, top-level `import/run/render`, `export`, `session`.
- State: the project directory is the state. Edits are *staged* in a `Session`, committed by auto-save (one-shot) or `session save` (REPL).
  Undo/redo history = `<project>/.cli-anything/history.json` (previous file contents, capped at 50), shared across processes.
- Native-format fidelity: unknown scene sections, comments and multi-line values round-trip untouched.

## Phase 3: Backend rule

All engine work goes through `utils/godot_backend.py`, which finds the executable (`GODOT_PATH`, saved config,
PATH) and runs it via `subprocess.run`. Scene verification uses a generated `SceneTree` script that loads and
instantiates the scene in the engine and prints a JSON report; any engine `ERROR:` line makes verification fail,
because Godot loads damaged scenes leniently.

## Known limits
- Not modelled: `sub_resource` editing, signal `[connection]` editing, scene instancing (`instance=`) creation, 3D editing helpers.
  Those sections are preserved but must be edited via `set-prop` with literals or by hand.
- `render` needs a GPU/display. `export release|debug` needs export templates.
- Close the project in the Godot editor before editing from the CLI.
