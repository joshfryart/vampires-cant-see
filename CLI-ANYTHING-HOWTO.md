# CLI-Anything: How-To (for AI agents)

Source: https://github.com/HKUDS/CLI-Anything (methodology SOP: `cli-anything-plugin/HARNESS.md`).
Check the repo for the latest; license is reported inconsistently (LICENSE file says Apache-2.0, README says MIT).

## What it is
CLI-Anything turns existing software (GIMP, Blender, LibreOffice, Inkscape, ffmpeg, OBS, ...) into a
stateful, agent-friendly command-line tool. It generates a Python Click CLI ("harness") that drives the
**real** application as its backend. Every generated CLI supports `--json` output and a REPL.

Two ways to use it:
1. **Use an existing CLI** from CLI-Hub (fastest).
2. **Generate a new CLI** for software not yet in the registry.

## 1. Use an existing CLI (CLI-Hub)
```bash
pip install cli-anything-hub
cli-hub list
cli-hub search image
cli-hub info gimp
cli-hub install gimp
cli-hub update gimp
cli-hub uninstall gimp
cli-hub launch gimp [args...]
```
The upstream application (e.g. GIMP, Blender) must also be installed on the machine.

Let an agent discover CLIs itself:
```bash
npx skills add HKUDS/CLI-Anything --skill cli-hub-meta-skill -g -y
```
Then prompt: `Find appropriate CLI software in CLI-Hub and complete the task: ...`

Using an installed harness:
```bash
cli-anything-gimp --help
cli-anything-gimp --json layer add -n "Background" --type solid --color "#1a1a2e"
cli-anything-gimp            # no subcommand -> interactive REPL
```
Prefer `--json` when parsing output. Use `info` / `list` / `status` commands to inspect before mutating.

## 2. Generate a new CLI

### Install the generator
**Claude Code**
```
/plugin marketplace add HKUDS/CLI-Anything
/plugin install cli-anything
```
Manual: `git clone https://github.com/HKUDS/CLI-Anything.git`, copy `cli-anything-plugin` to
`~/.claude/plugins/cli-anything`, then `/reload-plugins`.
If `/cli-anything` is unknown try `/cli-anything:cli-anything`; for "Unknown skill" run `/reload-plugins`.
**Windows:** Claude Code needs `bash` + `cygpath` (install Git for Windows, or use WSL).

Other agents (all start with `git clone https://github.com/HKUDS/CLI-Anything.git`):
| Agent | Install |
|---|---|
| Codex | `bash CLI-Anything/codex-skill/scripts/install.sh` (restart Codex) |
| Cursor | `bash CLI-Anything/cursor-plugin/scripts/install.sh` (Win: `.\...\install.ps1`), then "Developer: Reload Window" |
| OpenCode | copy `opencode-commands/*.md` and `cli-anything-plugin/HARNESS.md` to `~/.config/opencode/commands/` |
| Pi | `bash .pi-extension/cli-anything/install.sh`, then `/reload` |
| Copilot CLI | `copilot plugin install ./cli-anything-plugin` |
| Hermes / Reasonix / Qodercli | `hermes-skill/scripts/install.sh`, `reasonix-skill/scripts/install.sh`, `qoder-plugin/setup-qodercli.sh` |
| OpenClaw | copy `openclaw-skill/SKILL.md` to `~/.openclaw/skills/cli-anything/SKILL.md`; invoke `@cli-anything build a CLI for ./gimp` |

### Commands (Claude Code form)
| Command | Purpose |
|---|---|
| `/cli-anything ./gimp` | Build full harness (all phases) from a local source dir |
| `/cli-anything https://github.com/blender/blender` | Build from a GitHub repo |
| `/cli-anything:refine ./gimp "batch processing and filters"` | Extend/refine an existing harness |
| `/cli-anything:test <path>` | Run tests |
| `/cli-anything:validate <path>` | Validate a harness |
| `/cli-anything:list` | List tools |

OpenCode/Cursor use hyphens: `/cli-anything-refine`, `/cli-anything-test`, `/cli-anything-validate`, `/cli-anything-list`.
Codex etc. use natural language: `Use CLI-Anything to build a harness for ./gimp`.

### The pipeline (what the generator does)
1. **Analyze** – find the backend engine, map GUI actions to API calls, identify data model/file formats and any existing CLI tools.
2. **Design** – choose REPL + subcommands (recommended both); command groups per domain (project, core ops, import/export, config, session/undo); state model; human output by default, `--json` for machines.
3. **Implement** – data layer on the app's native format; `info`/probe commands; one mutation command per operation; backend wrapper (`shutil.which()` + `subprocess.run()`, clear install error if missing); export pipeline; session with undo/redo and file locking; REPL via `repl_skin.py` (`invoke_without_command=True`).
4. **Plan tests** – `tests/TEST.md` with inventory, unit plan, E2E plan, workflow scenarios.
5. **Write tests** – `test_core.py` (synthetic, no deps) and `test_full_e2e.py` (real backend; must **fail**, not skip, if software is missing).
6. **Document** – append `pytest -v --tb=no` results and coverage gaps to `TEST.md`. (6.5: generate `SKILL.md`.)
7. **Publish** – `setup.py`, PEP 420 namespace package, `pip install -e .`.

### Output layout
```
<software>/agent-harness/
├── <SOFTWARE>.md              # project-specific analysis/SOP
├── setup.py
├── cli_anything/              # namespace package: NO __init__.py here
│   └── <software>/
│       ├── __init__.py, __main__.py, README.md
│       ├── <software>_cli.py
│       ├── core/              # project.py, export.py, session.py, ...
│       ├── utils/             # <software>_backend.py, repl_skin.py
│       └── tests/             # TEST.md, test_core.py, test_full_e2e.py
└── examples/
skills/cli-anything-<software>/SKILL.md     # canonical skill
```
Names: command `cli-anything-<software>`, package `cli_anything.<software>`, skill `cli-anything-<software>`.
Install a harness: `cd <software>/agent-harness && pip install -e .`

## Rules to follow when building or extending a harness
- **Call the real software.** Never reimplement the app's functionality in Python; missing software = clear install error.
- **Use the app's native file formats** as the data layer.
- **Every command supports `--json`**; errors are unambiguous; commands idempotent where possible; `info`/`list`/`status` introspection exists.
- **Verify outputs**, not just exit codes (magic bytes, file structure, frame/pixel/audio checks, durations).
- **Tests:** unit + native E2E + true-backend E2E + subprocess E2E. Subprocess tests use an installed-command resolver and must not set `cwd`; CI sets `CLI_ANYTHING_FORCE_INSTALLED=1`.
- **Required docs:** `README.md` per software, `TEST.md` per tests dir.
- **Rendering pitfalls:** don't let a simple renderer silently drop effects; prefer native engine > translated filtergraph > generated script. Use `round()` not `int()` for timecodes (allow ±1 frame at non-integer fps).
- Session saves use exclusive file locking (open `"r+"`, lock, then truncate inside the lock).

## Notes for this project (Vampires Can't See)
This repo is a browser game (`index.html`, `js/`, `css/`) with a Godot exe and Node-style tools in `tools/`.
CLI-Anything targets desktop apps with a real backend, so good candidates here are tools the project
already depends on (e.g. Godot, Blender, GIMP/Inkscape for assets) rather than the game's JS itself.
The `/cli-anything` generator needs Python 3.10+ and the target app installed.
