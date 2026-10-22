"""cli-anything-godot: stateful CLI for the Godot Engine.

Edits project.godot and .tscn files natively; the real Godot executable does
all importing, script checking, scene verification, rendering and exporting.
"""

import functools
import json
import os
import shlex
import sys
from pathlib import Path

import click

from cli_anything.godot.core import project as proj_mod
from cli_anything.godot.core import scene as scene_mod
from cli_anything.godot.core.session import Session
from cli_anything.godot.utils import godot_backend as backend
from cli_anything.godot.utils.repl_skin import ReplSkin

__version__ = "1.0.0"

_session = Session()
_json_output = False
_repl_mode = False


def get_session() -> Session:
    return _session


# ── output helpers ────────────────────────────────────────────────────

def emit(data, human=None):
    """Print data as JSON (--json) or via the human formatter."""
    if _json_output:
        click.echo(json.dumps(data, indent=2, default=str))
    elif human is not None:
        click.echo(human if isinstance(human, str) else human(data))
    else:
        click.echo(json.dumps(data, indent=2, default=str))


def fail(message, code=1):
    if _json_output:
        click.echo(json.dumps({"error": message}), err=False)
    else:
        click.echo(f"Error: {message}", err=True)
    if _repl_mode:
        raise click.exceptions.Exit(code)
    sys.exit(code)


def handle_error(fn):
    @functools.wraps(fn)
    def wrapper(*a, **kw):
        try:
            return fn(*a, **kw)
        except (click.exceptions.Exit, click.exceptions.Abort, click.ClickException):
            raise
        except (FileNotFoundError, ValueError, RuntimeError, scene_mod.SceneError) as e:
            fail(str(e))
    return wrapper


def _need_project() -> Session:
    s = get_session()
    s._require()
    if not proj_mod.is_project(s.project_dir) and not s._staged:
        raise RuntimeError(f"No project.godot in {s.project_dir}. Create one with: project new")
    return s


def _flush():
    """Engine commands read from disk, so commit staged edits first."""
    s = get_session()
    if s.has_project() and s._staged:
        s.save_session()


def _scene_arg(path: str) -> str:
    p = path.replace("res://", "")
    return p if p.endswith(".tscn") else p + ".tscn"


def _load_scene(s: Session, path: str) -> scene_mod.Scene:
    return scene_mod.Scene.parse(s.read(_scene_arg(path)))


def _stage_scene(s: Session, path: str, sc: scene_mod.Scene, label: str):
    s.stage(_scene_arg(path), sc.dump(), label)


def _engine_result(res: dict, ok_codes=(0,), extra=None) -> dict:
    out = {"ok": res["returncode"] in ok_codes, "returncode": res["returncode"],
           "stdout": res["stdout"], "stderr": res["stderr"]}
    if extra:
        out.update(extra)
    return out


# ── root group ────────────────────────────────────────────────────────

@click.group(invoke_without_command=True)
@click.option("--json", "use_json", is_flag=True, help="Output as JSON (machine-readable).")
@click.option("--project", "-p", "project_path", type=str, default=None,
              help="Godot project directory (contains project.godot).")
@click.option("--dry-run", "dry_run", is_flag=True, default=False,
              help="Run the command without saving staged changes to disk.")
@click.version_option(__version__, prog_name="cli-anything-godot")
@click.pass_context
def cli(ctx, use_json, project_path, dry_run):
    """Command-line interface to the Godot Engine for AI agents.

    Run with no subcommand to enter the interactive REPL.
    """
    global _json_output
    _json_output = use_json or _json_output
    if project_path:
        try:
            get_session().open(project_path)
        except FileNotFoundError as e:
            if ctx.invoked_subcommand != "project":   # `project new` creates the folder itself
                fail(str(e))
    elif os.environ.get("GODOT_PROJECT") and not get_session().has_project():
        get_session().open(os.environ["GODOT_PROJECT"])
    if ctx.invoked_subcommand is None:
        ctx.invoke(repl)


@cli.result_callback()
def auto_save_on_exit(result, use_json, project_path, dry_run, **kwargs):
    """Auto-save staged changes after one-shot commands (skipped in REPL / --dry-run)."""
    if _repl_mode or dry_run:
        return
    s = get_session()
    if s.has_project() and s._modified:
        try:
            s.save_session()
        except Exception as e:  # noqa: BLE001
            click.echo(f"Warning: Auto-save failed: {e}", err=True)


# ── config / backend ─────────────────────────────────────────────────

@cli.group()
def config():
    """Locate the Godot executable."""


@config.command("set-path")
@click.argument("path")
@handle_error
def config_set_path(path):
    """Remember the Godot executable path."""
    saved = backend.save_godot_path(path)
    emit({"godot_path": saved}, f"Saved Godot path: {saved}")


@config.command("show")
@handle_error
def config_show():
    """Show which Godot executable will be used."""
    v = backend.version()
    emit(v, lambda d: f"{d['version']}\n{d['executable']}")


@cli.group()
def backend_cmd():
    """Engine information."""


cli.add_command(backend_cmd, "engine")


@backend_cmd.command("version")
@handle_error
def engine_version():
    """Print the Godot engine version."""
    v = backend.version()
    emit(v, lambda d: d["version"])


# ── project ──────────────────────────────────────────────────────────

@cli.group()
def project():
    """Create and inspect Godot projects (project.godot)."""


@project.command("new")
@click.argument("path")
@click.option("--name", default=None, help="Project name (default: folder name).")
@click.option("--renderer", type=click.Choice(list(proj_mod.RENDERERS)), default="compatibility",
              show_default=True)
@handle_error
def project_new(path, name, renderer):
    """Create a new project at PATH."""
    d = Path(path)
    if proj_mod.is_project(d):
        raise ValueError(f"A project already exists at {d}")
    d.mkdir(parents=True, exist_ok=True)
    s = get_session()
    s.open(d)
    s.stage("project.godot", proj_mod.new_project_text(name or d.resolve().name, renderer), "project new")
    info = {"path": str(d.resolve()), "name": name or d.resolve().name, "renderer": renderer}
    emit(info, f"Created project '{info['name']}' at {info['path']}")


@project.command("info")
@handle_error
def project_info():
    """Show project name, main scene, renderer, scenes and scripts."""
    s = _need_project()
    info = proj_mod.project_info(s.project_dir, s.read("project.godot"))
    emit(info, lambda d: (
        f"{d['name']}  ({d['path']})\n"
        f"  main scene: {d['main_scene']}\n  renderer:   {d['renderer']}\n"
        f"  scenes:  {d['scene_count']}  scripts: {d['script_count']}"))


@project.command("get")
@click.argument("setting")
@handle_error
def project_get(setting):
    """Read a setting, e.g. application/config/name."""
    s = _need_project()
    sec, key = proj_mod.split_setting(setting)
    raw = proj_mod.ConfigDoc.parse(s.read("project.godot")).get(sec, key)
    if raw is None:
        raise ValueError(f"Setting not found: {setting}")
    emit({"setting": setting, "raw": raw, "value": proj_mod.from_literal(raw)}, raw)


@project.command("set")
@click.argument("setting")
@click.argument("value")
@handle_error
def project_set(setting, value):
    """Write a setting. VALUE is a Godot literal (true, 5, Vector2(1,2)) or a plain string."""
    s = _need_project()
    sec, key = proj_mod.split_setting(setting)
    doc = proj_mod.ConfigDoc.parse(s.read("project.godot"))
    raw = proj_mod.to_literal(value)
    doc.set(sec, key, raw)
    s.stage("project.godot", doc.dump(), f"project set {setting}")
    emit({"setting": setting, "raw": raw}, f"{setting} = {raw}")


@project.command("unset")
@click.argument("setting")
@handle_error
def project_unset(setting):
    """Remove a setting (revert to the engine default)."""
    s = _need_project()
    sec, key = proj_mod.split_setting(setting)
    doc = proj_mod.ConfigDoc.parse(s.read("project.godot"))
    if not doc.unset(sec, key):
        raise ValueError(f"Setting not found: {setting}")
    s.stage("project.godot", doc.dump(), f"project unset {setting}")
    emit({"setting": setting, "removed": True}, f"Removed {setting}")


@project.command("settings")
@click.option("--section", default=None, help="Only this section.")
@handle_error
def project_settings(section):
    """List all settings."""
    s = _need_project()
    rows = [{"section": sec, "key": k, "raw": v}
            for sec, k, v in proj_mod.ConfigDoc.parse(s.read("project.godot")).items()
            if section is None or sec == section]
    emit(rows, lambda d: "\n".join(f"{(r['section'] + '/') if r['section'] else ''}{r['key']} = {r['raw']}" for r in d))


@project.command("set-main-scene")
@click.argument("scene")
@handle_error
def project_set_main_scene(scene):
    """Set application/run/main_scene."""
    s = _need_project()
    rel = _scene_arg(scene)
    if not s.exists(rel):
        raise FileNotFoundError(f"Scene not found: {rel}")
    doc = proj_mod.ConfigDoc.parse(s.read("project.godot"))
    doc.set("application", "run/main_scene", f'"res://{rel}"')
    s.stage("project.godot", doc.dump(), "set main scene")
    emit({"main_scene": f"res://{rel}"}, f"Main scene: res://{rel}")


# ── scene ────────────────────────────────────────────────────────────

@cli.group()
def scene():
    """Create and edit .tscn scenes."""


@scene.command("new")
@click.argument("path")
@click.option("--root-name", default=None, help="Root node name (default: file stem).")
@click.option("--root-type", default="Node", show_default=True, help="Root node class, e.g. Node2D, Control.")
@click.option("--main", is_flag=True, help="Also set it as the project's main scene.")
@handle_error
def scene_new(path, root_name, root_type, main):
    """Create a scene file."""
    s = _need_project()
    rel = _scene_arg(path)
    if s.exists(rel):
        raise ValueError(f"Scene already exists: {rel}")
    name = root_name or Path(rel).stem.replace("-", "_").title().replace("_", "")
    s.stage(rel, scene_mod.new_scene_text(name, root_type), f"scene new {rel}")
    if main:
        doc = proj_mod.ConfigDoc.parse(s.read("project.godot"))
        doc.set("application", "run/main_scene", f'"res://{rel}"')
        s.stage("project.godot", doc.dump())
    emit({"scene": f"res://{rel}", "root": name, "root_type": root_type, "main": main},
         f"Created res://{rel} (root {name}: {root_type})")


@scene.command("list")
@handle_error
def scene_list():
    """List scenes in the project."""
    s = _need_project()
    info = proj_mod.project_info(s.project_dir, s.read("project.godot"))
    emit(info["scenes"], lambda d: "\n".join(d))


@scene.command("tree")
@click.argument("path")
@handle_error
def scene_tree(path):
    """Show the node tree of a scene."""
    s = _need_project()
    t = _load_scene(s, path).tree()
    emit(t, lambda d: "\n".join("  " * n["depth"] + f"{n['name']} [{n['type']}]" +
                                (f"  {{{', '.join(n['properties'])}}}" if n["properties"] else "") for n in d))


@scene.command("add-node")
@click.argument("path")
@click.argument("name")
@click.option("--type", "node_type", default="Node", show_default=True, help="Node class.")
@click.option("--parent", default=".", show_default=True, help="Parent node path ('.' = root).")
@click.option("--prop", "props", multiple=True, metavar="KEY=VALUE", help="Property (repeatable).")
@handle_error
def scene_add_node(path, name, node_type, parent, props):
    """Add a node to a scene."""
    s = _need_project()
    sc = _load_scene(s, path)
    kv = {}
    for p in props:
        if "=" not in p:
            raise ValueError(f"--prop must be KEY=VALUE, got '{p}'")
        k, v = p.split("=", 1)
        kv[k.strip()] = v
    node = sc.add_node(name, node_type, parent, kv)
    _stage_scene(s, path, sc, f"scene add-node {name}")
    emit({"scene": _scene_arg(path), "node": sc.node_path(node), "type": node_type},
         f"Added {sc.node_path(node)} [{node_type}]")


@scene.command("remove-node")
@click.argument("path")
@click.argument("node")
@handle_error
def scene_remove_node(path, node):
    """Remove a node and its children."""
    s = _need_project()
    sc = _load_scene(s, path)
    removed = sc.remove_node(node)
    _stage_scene(s, path, sc, f"scene remove-node {node}")
    emit({"scene": _scene_arg(path), "removed_sections": removed}, f"Removed {node} ({removed} node(s))")


@scene.command("set-prop")
@click.argument("path")
@click.argument("node")
@click.argument("key")
@click.argument("value")
@handle_error
def scene_set_prop(path, node, key, value):
    """Set a node property (VALUE: Godot literal, e.g. 'Vector2(10, 20)', or plain string)."""
    s = _need_project()
    sc = _load_scene(s, path)
    sc.set_prop(node, key, value)
    _stage_scene(s, path, sc, f"scene set-prop {node}.{key}")
    emit({"node": node, "key": key, "raw": sc.get_prop(node, key)}, f"{node}.{key} = {sc.get_prop(node, key)}")


@scene.command("get-prop")
@click.argument("path")
@click.argument("node")
@click.argument("key")
@handle_error
def scene_get_prop(path, node, key):
    """Read a node property."""
    s = _need_project()
    raw = _load_scene(s, path).get_prop(node, key)
    if raw is None:
        raise ValueError(f"Property '{key}' not set on '{node}'")
    emit({"node": node, "key": key, "raw": raw}, raw)


@scene.command("attach-script")
@click.argument("path")
@click.argument("node")
@click.argument("script")
@handle_error
def scene_attach_script(path, node, script):
    """Attach a GDScript file to a node."""
    s = _need_project()
    rel = script.replace("res://", "")
    if not s.exists(rel):
        raise FileNotFoundError(f"Script not found: {rel} (create it with: script new)")
    sc = _load_scene(s, path)
    rid = sc.attach_script(node, f"res://{rel}")
    _stage_scene(s, path, sc, f"scene attach-script {node}")
    emit({"node": node, "script": f"res://{rel}", "ext_resource_id": rid}, f"Attached res://{rel} to {node}")


@scene.command("verify")
@click.argument("path")
@handle_error
def scene_verify(path):
    """Load and instantiate the scene in the real Godot engine."""
    s = _need_project()
    _flush()
    rel = _scene_arg(path)
    if not s.exists(rel):
        raise FileNotFoundError(f"Scene not found: {rel}")
    rep = backend.verify_scene(str(s.project_dir), f"res://{rel}")
    emit(rep, lambda d: (f"OK: {d['root']} [{d['root_type']}], {d['node_count']} node(s)"
                         if d.get("ok") else f"FAILED: {d.get('error')}\n{d.get('stderr', '')}"))
    if not rep.get("ok"):
        raise click.exceptions.Exit(1)


# ── script ───────────────────────────────────────────────────────────

@cli.group()
def script():
    """Create, check and run GDScript."""


@script.command("new")
@click.argument("path")
@click.option("--extends", "extends", default="Node", show_default=True)
@click.option("--attach", metavar="SCENE:NODE", default=None, help="Attach to a scene node, e.g. main.tscn:.")
@handle_error
def script_new(path, extends, attach):
    """Create a GDScript file."""
    s = _need_project()
    rel = path.replace("res://", "")
    rel = rel if rel.endswith(".gd") else rel + ".gd"
    if s.exists(rel):
        raise ValueError(f"Script already exists: {rel}")
    s.stage(rel, scene_mod.new_script_text(extends), f"script new {rel}")
    if attach:
        scene_path, _, node = attach.partition(":")
        sc = _load_scene(s, scene_path)
        sc.attach_script(node or ".", f"res://{rel}")
        _stage_scene(s, scene_path, sc, f"attach {rel}")
    emit({"script": f"res://{rel}", "extends": extends, "attached_to": attach},
         f"Created res://{rel}" + (f" and attached to {attach}" if attach else ""))


@script.command("check")
@click.argument("path")
@handle_error
def script_check(path):
    """Parse a GDScript with the real engine (--check-only)."""
    s = _need_project()
    _flush()
    rel = path.replace("res://", "")
    res = backend.check_script(str(s.project_dir), f"res://{rel}")
    out = _engine_result(res)
    emit(out, lambda d: "OK: no parse errors" if d["ok"] else f"Parse errors:\n{d['stdout']}\n{d['stderr']}")
    if not out["ok"]:
        raise click.exceptions.Exit(1)


@script.command("run")
@click.argument("path")
@click.argument("args", nargs=-1)
@handle_error
def script_run(path, args):
    """Run a SceneTree/MainLoop script headlessly and print its output."""
    s = _need_project()
    _flush()
    rel = path.replace("res://", "")
    res = backend.run_script(str(s.project_dir), f"res://{rel}", args)
    out = _engine_result(res)
    emit(out, lambda d: d["stdout"] + (("\n" + d["stderr"]) if d["stderr"] else ""))
    if not out["ok"]:
        raise click.exceptions.Exit(res["returncode"] or 1)


# ── engine runs ──────────────────────────────────────────────────────

@cli.command("import")
@handle_error
def import_cmd():
    """Import project assets with the real editor (creates the .godot cache)."""
    s = _need_project()
    _flush()
    res = backend.import_project(str(s.project_dir))
    out = _engine_result(res)
    emit(out, lambda d: "Import finished" if d["ok"] else f"Import failed:\n{d['stdout']}\n{d['stderr']}")
    if not out["ok"]:
        raise click.exceptions.Exit(1)


@cli.command("run")
@click.argument("scene_path", required=False)
@click.option("--frames", default=2, show_default=True, help="Quit after N frames.")
@handle_error
def run_cmd(scene_path, frames):
    """Run the project (or one scene) headlessly for N frames."""
    s = _need_project()
    _flush()
    scene_res = f"res://{_scene_arg(scene_path)}" if scene_path else None
    res = backend.run_scene(str(s.project_dir), scene_res, frames)
    out = _engine_result(res)
    emit(out, lambda d: d["stdout"] or ("Ran OK" if d["ok"] else d["stderr"]))
    if not out["ok"]:
        raise click.exceptions.Exit(res["returncode"] or 1)


@cli.command("render")
@click.argument("output")
@click.option("--scene", "scene_path", default=None, help="Scene to render (default: main scene).")
@click.option("--frames", default=5, show_default=True)
@click.option("--fps", default=30, show_default=True)
@click.option("--resolution", default="320x180", show_default=True)
@handle_error
def render_cmd(output, scene_path, frames, fps, resolution):
    """Render frames with Godot's movie maker. OUTPUT ending .png writes a PNG sequence, .avi a video.

    Needs a display/GPU (the engine cannot render headless).
    """
    s = _need_project()
    _flush()
    out_path = Path(output).resolve()
    out_path.parent.mkdir(parents=True, exist_ok=True)
    scene_res = f"res://{_scene_arg(scene_path)}" if scene_path else None
    res = backend.write_movie(str(s.project_dir), str(out_path), scene_res, frames, fps, resolution)
    produced = sorted(str(p) for p in out_path.parent.glob(out_path.stem + "*" + out_path.suffix))
    out = _engine_result(res, extra={"files": produced})
    out["ok"] = out["ok"] and bool(produced)
    emit(out, lambda d: f"Rendered {len(d['files'])} file(s):\n" + "\n".join(d["files"])
         if d["ok"] else f"Render failed:\n{d['stdout']}\n{d['stderr']}")
    if not out["ok"]:
        raise click.exceptions.Exit(1)


@cli.group("export")
def export_group():
    """Export builds with presets from export_presets.cfg."""


@export_group.command("presets")
@handle_error
def export_presets():
    """List export presets defined in the project."""
    s = _need_project()
    if not s.exists("export_presets.cfg"):
        emit([], "No export_presets.cfg (create presets in the Godot editor).")
        return
    doc = proj_mod.ConfigDoc.parse(s.read("export_presets.cfg"))
    presets = [{"name": proj_mod.from_literal(doc.get(sec, "name")),
                "platform": proj_mod.from_literal(doc.get(sec, "platform")),
                "export_path": proj_mod.from_literal(doc.get(sec, "export_path"))}
               for sec, _ in doc.sections if sec.startswith("preset.") and "." not in sec[len("preset."):]]
    emit(presets, lambda d: "\n".join(f"{p['name']}  [{p['platform']}]  -> {p['export_path']}" for p in d))


def _do_export(mode, preset, output):
    s = _need_project()
    _flush()
    out_path = Path(output).resolve()
    out_path.parent.mkdir(parents=True, exist_ok=True)
    res = backend.export_project(str(s.project_dir), mode, preset, str(out_path))
    ok = res["returncode"] == 0 and out_path.exists() and out_path.stat().st_size > 0
    data = _engine_result(res, extra={"output": str(out_path), "size": out_path.stat().st_size if out_path.exists() else 0})
    data["ok"] = ok
    emit(data, lambda d: f"Exported {d['output']} ({d['size']:,} bytes)" if d["ok"]
         else f"Export failed:\n{d['stdout']}\n{d['stderr']}")
    if not ok:
        raise click.exceptions.Exit(1)


@export_group.command("pack")
@click.argument("preset")
@click.argument("output")
@handle_error
def export_pack(preset, output):
    """Export game data only (.pck / .zip)."""
    _do_export("pack", preset, output)


@export_group.command("release")
@click.argument("preset")
@click.argument("output")
@handle_error
def export_release(preset, output):
    """Export a release build (needs export templates installed)."""
    _do_export("release", preset, output)


@export_group.command("debug")
@click.argument("preset")
@click.argument("output")
@handle_error
def export_debug(preset, output):
    """Export a debug build (needs export templates installed)."""
    _do_export("debug", preset, output)


# ── session ──────────────────────────────────────────────────────────

@cli.group("session")
def session_group():
    """Undo / redo / history / save for project edits."""


@session_group.command("status")
@handle_error
def session_status():
    """Show staged changes and history depth."""
    s = get_session()
    s._require()
    emit(s.status(), lambda d: "\n".join(f"{k}: {v}" for k, v in d.items()))


@session_group.command("save")
@handle_error
def session_save():
    """Commit staged edits to disk."""
    files = get_session().save_session()
    emit({"saved": files}, f"Saved {len(files)} file(s)" if files else "Nothing to save")


@session_group.command("discard")
@handle_error
def session_discard():
    """Drop staged (unsaved) edits."""
    get_session().discard()
    emit({"discarded": True}, "Discarded staged changes")


@session_group.command("undo")
@handle_error
def session_undo():
    """Undo the last saved edit."""
    r = get_session().undo()
    emit(r, f"Undid: {r['undone']}")


@session_group.command("redo")
@handle_error
def session_redo():
    """Redo the last undone edit."""
    r = get_session().redo()
    emit(r, f"Redid: {r['redone']}")


@session_group.command("history")
@handle_error
def session_history():
    """List undo / redo stacks."""
    h = get_session().history()
    emit(h, lambda d: "undo: " + (" | ".join(d["undo"]) or "(empty)") + "\nredo: " + (" | ".join(d["redo"]) or "(empty)"))


# ── REPL ─────────────────────────────────────────────────────────────

@cli.command()
@click.option("--project", "-p", "repl_project", default=None, help="Project directory.")
def repl(repl_project):
    """Interactive REPL (default when no subcommand is given)."""
    global _repl_mode
    _repl_mode = True
    if repl_project:
        get_session().open(repl_project)
    skin = ReplSkin("godot", version=__version__)
    skin.print_banner()
    interactive = sys.stdin.isatty() and sys.stdout.isatty()
    try:
        pt = skin.create_prompt_session() if interactive else None
    except Exception:  # noqa: BLE001 - no usable console (e.g. mintty); fall back to plain input()
        pt = None
    commands = {
        "project new|info|get|set|unset|settings": "project file",
        "scene new|tree|add-node|remove-node|set-prop|verify": "scenes",
        "script new|check|run": "GDScript",
        "run / render / import / export": "engine operations",
        "session save|discard|undo|redo|history|status": "edits",
        "help / exit": "REPL",
    }
    while True:
        s = get_session()
        name = s.project_dir.name if s.has_project() else ""
        try:
            if pt is not None:
                line = skin.get_input(pt, project_name=name, modified=s._modified).strip()
            else:
                line = input(skin.prompt(project_name=name, modified=s._modified)).strip()
        except (EOFError, KeyboardInterrupt):
            break
        if not line:
            continue
        if line in ("exit", "quit", "q"):
            if s._modified:
                skin.warning("Unsaved changes discarded (use 'session save' first to keep them).")
            break
        if line == "help":
            skin.help(commands)
            continue
        try:
            args = shlex.split(line, posix=(os.name != "nt"))
        except ValueError as e:
            skin.error(str(e))
            continue
        try:
            cli.main(args=args, standalone_mode=False, prog_name="godot")
        except click.exceptions.Exit:
            pass
        except click.ClickException as e:
            skin.error(e.format_message())
        except SystemExit:
            pass
        except Exception as e:  # noqa: BLE001
            skin.error(str(e))
    skin.print_goodbye()
    _repl_mode = False


def main():
    cli()


if __name__ == "__main__":
    main()
