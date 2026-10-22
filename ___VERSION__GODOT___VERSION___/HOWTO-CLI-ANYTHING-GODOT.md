# How-To: driving Godot with cli-anything-godot (for a new agent)

Read this first. It gets you from zero to editing, checking and running the Godot port.

## 0. Paths (all quoted: the repo path has spaces)

| What | Path |
|---|---|
| Repo root | `C:\Users\hello\OneDrive\Desktop\claude\Vampires Cant See` |
| Godot exe (4.4.1) | `<repo>\Godot_v4.4.1-stable_win64.exe` |
| Harness source | `<repo>\godot\agent-harness` (full docs: `GODOT.md`, `cli_anything/godot/skills/SKILL.md`, `README.md`) |
| Port folder (work here) | `<repo>\___VERSION__GODOT___VERSION___` |
| Godot project root (planned) | `<repo>\___VERSION__GODOT___VERSION___\project` (holds `project.godot`) |
| The JS game (reference, do not edit) | `<repo>\js`, `<repo>\index.html` |

## 1. Setup (already done on this machine; verify, don't redo)

The harness is pip-installed in editable mode and the exe path is saved in its config.

```bash
python -m cli_anything.godot --json engine version
```

Expect `"version": "4.4.1.stable.official..."`. Use `python -m cli_anything.godot` everywhere: the
`cli-anything-godot.exe` launcher is in `C:\Users\hello\AppData\Local\Python\pythoncore-3.15-64\Scripts`,
which is not on the shell PATH.

If it says Godot is not found:

```bash
python -m cli_anything.godot config set-path "C:/Users/hello/OneDrive/Desktop/claude/Vampires Cant See/Godot_v4.4.1-stable_win64.exe"
```

If the module is missing: `pip install -e "<repo>/godot/agent-harness"` (needs Python 3.10+).
Harness self-test: `python -m pytest <repo>/godot/agent-harness/cli_anything/godot/tests -q` (61 tests, ~50 s).

## 2. Conventions

- `--json` is a **global** flag and goes **before** the subcommand: `... --json scene verify main`.
- `-p DIR` / `--project DIR` selects the project (the folder with `project.godot`), also before the subcommand.
  Shorthand used below:

  ```bash
  G='python -m cli_anything.godot --json -p "C:/Users/hello/OneDrive/Desktop/claude/Vampires Cant See/___VERSION__GODOT___VERSION___/project"'
  eval $G project info
  ```
- One-shot commands auto-save to disk. `--dry-run` runs without saving. In the REPL nothing saves until `session save`.
- Every edit is undoable across processes: `session undo | redo | history`. History is in
  `<project>/.cli-anything/history.json` (gitignore it).
- Scenes and scripts accept `main`, `main.tscn` or `res://main.tscn`.
- Node paths are relative to the scene root: `.` is the root, `World/Player` a child.
- Property values are Godot literals: `true`, `5`, `Vector2(10, 20)`, `Color(1,0,0,1)`. Anything else is a string.
- Errors print `{"error": "..."}` and exit 1. Engine commands also return `ok`; check it.
- Close the project in the Godot editor before editing from the CLI, or the editor may overwrite your changes.

## 3. Command cheat sheet

| Task | Command |
|---|---|
| Create project | `project new PATH --name "Vampires Cant See" --renderer compatibility` |
| Inspect | `project info`, `project settings`, `scene list`, `scene tree main`, `session status` |
| Project settings | `project set display/window/size/viewport_width 1280`, `project get ...`, `project set-main-scene main` |
| New scene | `scene new main --root-type Node3D --main` |
| Add node | `scene add-node main Player --type CharacterBody3D --parent . --prop "position=Vector3(0,1,0)"` |
| Edit property | `scene set-prop main Player key value`, `scene get-prop main Player key` |
| Remove node | `scene remove-node main Player` |
| New script | `script new player --extends CharacterBody3D --attach main.tscn:Player` |
| Attach script | `scene attach-script main Player player.gd` |
| **Parse-check a script** | `script check core/sonar.gd` (real engine; run after **every** `.gd` edit) |
| **Verify a scene** | `scene verify main` (engine loads + instantiates; fails on any engine ERROR) |
| Run a headless script | `script run tests/run_tests.gd -- --filter=sonar` (SceneTree/MainLoop script; `print()` lands in `stdout`) |
| Smoke-run | `run --frames 120` (headless, main scene) |
| Import assets | `import` (run after adding WAVs/textures) |
| Screenshots | `render out/shot --scene main --frames 60 --fps 60 --resolution 1280x720` (needs GPU and a window; not headless) |
| Export | `export presets`, `export pack PRESET OUT` (no templates needed), `export release|debug PRESET OUT` (needs templates) |
| Undo | `session undo` |

## 4. Rules for this port

1. **Write `.gd` and `.gdshader` files directly** (Write/Edit tool), not via `script new`. Then `script check`.
2. **Keep `.tscn` files minimal.** The harness cannot edit sub-resources, signal connections or scene instancing.
   Build node trees, materials, input maps and signal connections in code (`_ready()`), or hand-edit the
   `.tscn` and then run `scene verify`.
3. **Shaders do not compile headless.** `script check` and `scene verify` pass even if a shader is broken.
   Verify shaders with a windowed run (see below) and read the console for `SHADER ERROR`.
4. **Logic stays pure.** `core/*.gd` must not touch nodes, so it runs headless and can be parity-tested against the JS.
   Use plain floats and `PackedFloat64Array`, not `Vector2/3` (32-bit). See `jsmath.gd` for JS-faithful rounding and RNG.
5. **Never edit `<repo>\js`.** It is the reference. Generate fixtures from it with Node (`tools/golden/*.mjs`).
6. **Quote every path.** Spaces everywhere.
7. **Do not install anything** (npm packages, GUT/GdUnit4, export templates) without asking the user first.

## 5. Verification loop (after every change)

```bash
eval $G script check core/sonar.gd                       # 1. parses?
eval $G scene verify main                                # 2. scene loads?
eval $G script run tests/run_tests.gd -- --filter=sonar  # 3. logic + parity tests
eval $G run --frames 120                                 # 4. headless smoke run
```

Visual checks (windowed; fixed timestep so frames are reproducible). Run the exe directly when you
need engine flags the harness does not wrap:

```bash
"C:/Users/hello/OneDrive/Desktop/claude/Vampires Cant See/Godot_v4.4.1-stable_win64.exe" \
  --path "C:/Users/hello/OneDrive/Desktop/claude/Vampires Cant See/___VERSION__GODOT___VERSION___/project" \
  --rendering-driver opengl3 --write-movie out/NAME/f.png --fixed-fps 60 --quit-after 180 \
  -- --scenario=NAME
```

View the resulting PNGs with the Read tool. Compare against JS reference shots taken from
`index.html?debug=1` in the browser pane.

## 6. Where things stand

The plan is in the conversation that created this folder: Phase 0 (scaffold, test runner, first parity tests),
then Phase 1 (vertical slice on the `test` map), then a go/no-go on the shader look. Nothing is built yet.
Record decisions and the JS-module-to-GDScript map in `docs/PORT.md` as you go.
