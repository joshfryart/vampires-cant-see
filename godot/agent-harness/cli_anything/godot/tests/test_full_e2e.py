"""E2E tests. These invoke the REAL Godot executable (no skipping if it is missing).

Run against the installed command:
    CLI_ANYTHING_FORCE_INSTALLED=1 python -m pytest cli_anything/godot/tests -v -s
"""

import json
import os
import shutil
import subprocess
import sys
import zipfile

import pytest

from cli_anything.godot.core import scene as S
from cli_anything.godot.utils import godot_backend as backend


def _resolve_cli(name):
    """Resolve installed CLI command; falls back to python -m for dev.

    Set env CLI_ANYTHING_FORCE_INSTALLED=1 to require the installed command.
    """
    force = os.environ.get("CLI_ANYTHING_FORCE_INSTALLED", "").strip() == "1"
    path = shutil.which(name)
    if path:
        print(f"[_resolve_cli] Using installed command: {path}")
        return [path]
    scripts = os.path.join(os.path.dirname(sys.executable), "Scripts", name + ".exe")
    if os.path.isfile(scripts):
        print(f"[_resolve_cli] Using installed command: {scripts}")
        return [scripts]
    if force:
        raise RuntimeError(f"{name} not found in PATH. Install with: pip install -e .")
    module = name.replace("cli-anything-", "cli_anything.") + "." + name.split("-")[-1] + "_cli"
    print(f"[_resolve_cli] Falling back to: {sys.executable} -m {module}")
    return [sys.executable, "-m", module]


class CLI:
    BASE = _resolve_cli("cli-anything-godot")

    def __init__(self, project=None):
        self.project = project

    def run(self, *args, check=True, json_out=False):
        cmd = list(self.BASE)
        if json_out:
            cmd.append("--json")
        if self.project:
            cmd += ["--project", str(self.project)]
        cmd += list(args)
        r = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", timeout=600)
        if check and r.returncode != 0:
            raise AssertionError(f"{cmd} -> {r.returncode}\nSTDOUT:{r.stdout}\nSTDERR:{r.stderr}")
        if json_out:
            try:
                r.data = json.loads(r.stdout)
            except ValueError:
                r.data = None
        return r


@pytest.fixture
def game(tmp_path):
    root = tmp_path / "game"
    CLI().run("project", "new", str(root), "--name", "E2E Game")
    return CLI(root), root


# ── backend (real engine) ──

class TestBackend:
    def test_version_is_godot4(self):
        v = backend.version()
        print(f"\n  Godot: {v['version']} at {v['executable']}")
        assert v["major"] == 4 and os.path.isfile(v["executable"])

    def test_missing_executable_error(self, monkeypatch, tmp_path):
        monkeypatch.setenv("GODOT_PATH", str(tmp_path / "nope.exe"))
        with pytest.raises(RuntimeError, match="GODOT_PATH"):
            backend.find_godot()


# ── native project/scene files, validated by the real engine ──

class TestEngineValidatesNativeFiles:
    def test_project_scene_loads_in_engine(self, game):
        cli, root = game
        cli.run("scene", "new", "main", "--root-type", "Node2D", "--main")
        cli.run("scene", "add-node", "main", "Hero", "--type", "Sprite2D", "--prop", "position=Vector2(5, 6)")
        cli.run("scene", "add-node", "main", "Hat", "--type", "Node2D", "--parent", "Hero")
        r = cli.run("scene", "verify", "main", json_out=True)
        print(f"\n  scene nodes: {r.data['nodes']}")
        assert r.data["ok"] and r.data["node_count"] == 3
        assert r.data["root_type"] == "Node2D"
        assert set(r.data["nodes"]) == {".", "Hero", "Hero/Hat"}

    def test_verify_fails_on_broken_scene(self, game):
        cli, root = game
        cli.run("scene", "new", "bad")
        (root / "bad.tscn").write_text('[gd_scene format=3]\n\n[node name="X" type="NotARealClass"]\n')
        r = cli.run("scene", "verify", "bad", check=False, json_out=True)
        assert r.returncode != 0 and not r.data["ok"]

    def test_script_check_ok_and_error(self, game):
        cli, root = game
        cli.run("script", "new", "good", "--extends", "Node")
        assert cli.run("script", "check", "good.gd", json_out=True).data["ok"]
        (root / "broken.gd").write_text("extends Node\nfunc _ready(:\n\tpass\n")
        r = cli.run("script", "check", "broken.gd", check=False, json_out=True)
        assert r.returncode != 0 and not r.data["ok"]

    def test_script_run_prints_output(self, game):
        cli, root = game
        (root / "hello.gd").write_text('extends SceneTree\nfunc _init():\n\tprint("hi-from-" + "".join(OS.get_cmdline_user_args()))\n\tquit()\n')
        r = cli.run("script", "run", "hello.gd", "godot", json_out=True)
        assert "hi-from-godot" in r.data["stdout"]

    def test_run_main_scene_headless(self, game):
        cli, root = game
        cli.run("scene", "new", "main", "--main")
        r = cli.run("run", "--frames", "3", json_out=True)
        assert r.data["ok"]


# ── real backend output ──

class TestImportRenderExport:
    def test_import_creates_cache(self, game):
        cli, root = game
        cli.run("scene", "new", "main", "--main")
        assert cli.run("import", json_out=True).data["ok"]
        assert (root / ".godot").is_dir()

    def test_render_png_frames(self, game):
        cli, root = game
        cli.run("scene", "new", "main", "--root-type", "Node2D", "--main")
        out = root / "out" / "frame.png"
        r = cli.run("render", str(out), "--frames", "3", "--resolution", "160x90", json_out=True)
        assert r.data["ok"] and len(r.data["files"]) == 3
        for f in r.data["files"]:
            with open(f, "rb") as fh:
                assert fh.read(8) == b"\x89PNG\r\n\x1a\n"
            print(f"\n  PNG: {f} ({os.path.getsize(f):,} bytes)")

    def test_export_pack_with_preset(self, game):
        cli, root = game
        cli.run("scene", "new", "main", "--main")
        (root / "export_presets.cfg").write_text(
            '[preset.0]\n\nname="Pack"\nplatform="Windows Desktop"\nrunnable=true\n'
            'export_filter="all_resources"\ninclude_filter=""\nexclude_filter=""\n'
            'export_path="build/game.exe"\n\n[preset.0.options]\n\n')
        presets = cli.run("export", "presets", json_out=True).data
        assert presets[0]["name"] == "Pack"
        out = root / "build" / "game.pck"
        r = cli.run("export", "pack", "Pack", str(out), json_out=True)
        assert r.data["ok"] and out.stat().st_size > 0
        with open(out, "rb") as f:
            assert f.read(4) == b"GDPC"          # Godot pack magic
        print(f"\n  PCK: {out} ({out.stat().st_size:,} bytes)")

    def test_export_zip_pack(self, game):
        cli, root = game
        cli.run("scene", "new", "main", "--main")
        (root / "export_presets.cfg").write_text(
            '[preset.0]\n\nname="Pack"\nplatform="Windows Desktop"\nrunnable=true\n'
            'export_filter="all_resources"\ninclude_filter=""\nexclude_filter=""\n'
            'export_path="build/game.exe"\n\n[preset.0.options]\n\n')
        out = root / "build" / "game.zip"
        cli.run("export", "pack", "Pack", str(out))
        assert zipfile.is_zipfile(out)
        names = zipfile.ZipFile(out).namelist()
        assert "main.tscn.remap" in names and "project.binary" in names, names
        print(f"\n  ZIP: {out} ({out.stat().st_size:,} bytes)")


# ── CLI behaviour via subprocess ──

class TestCLISubprocess:
    def test_help(self):
        r = CLI().run("--help")
        assert "Godot" in r.stdout

    def test_engine_version_json(self):
        r = CLI().run("engine", "version", json_out=True)
        assert r.data["major"] == 4

    def test_project_new_json(self, tmp_path):
        r = CLI().run("project", "new", str(tmp_path / "p"), "--name", "P", json_out=True)
        assert r.data["name"] == "P"
        assert (tmp_path / "p" / "project.godot").is_file()

    def test_autosave_and_dry_run(self, game):
        cli, root = game
        cli.run("project", "set", "display/window/size/viewport_width", "640")
        assert "viewport_width=640" in (root / "project.godot").read_text()
        cli.run("--dry-run", "project", "set", "display/window/size/viewport_width", "999")
        assert "viewport_width=640" in (root / "project.godot").read_text()

    def test_error_is_json_and_nonzero(self, game):
        cli, root = game
        r = cli.run("scene", "tree", "missing", check=False, json_out=True)
        assert r.returncode == 1 and "error" in r.data

    def test_undo_redo_across_processes(self, game):
        cli, root = game
        cli.run("scene", "new", "main")
        cli.run("scene", "add-node", "main", "A", "--type", "Node")
        assert "A" in [n["name"] for n in cli.run("scene", "tree", "main", json_out=True).data]
        cli.run("session", "undo")
        assert "A" not in [n["name"] for n in cli.run("scene", "tree", "main", json_out=True).data]
        cli.run("session", "redo")
        assert "A" in [n["name"] for n in cli.run("scene", "tree", "main", json_out=True).data]

    def test_project_setting_roundtrip_engine_reads(self, game):
        """Workflow: set a setting via CLI, have the real engine read it back."""
        cli, root = game
        cli.run("project", "set", "application/config/name", "Round Trip")
        (root / "name.gd").write_text(
            'extends SceneTree\nfunc _init():\n\tprint("NAME=" + ProjectSettings.get_setting("application/config/name"))\n\tquit()\n')
        out = cli.run("script", "run", "name.gd", json_out=True).data["stdout"]
        assert "NAME=Round Trip" in out


# ── realistic workflows ──

class TestWorkflows:
    def test_build_level_scene_with_script_and_verify(self, game):
        """Simulates: scaffolding a small 2D level an agent then runs in the engine."""
        cli, root = game
        cli.run("scene", "new", "level", "--root-type", "Node2D", "--main")
        for name, kind, parent in [("World", "Node2D", "."), ("Ground", "StaticBody2D", "World"),
                                   ("Player", "CharacterBody2D", "World"), ("Cam", "Camera2D", "World/Player")]:
            cli.run("scene", "add-node", "level", name, "--type", kind, "--parent", parent)
        cli.run("script", "new", "player", "--extends", "CharacterBody2D", "--attach", "level.tscn:World/Player")
        cli.run("scene", "set-prop", "level", "World/Player", "position", "Vector2(100, 50)")
        assert cli.run("script", "check", "player.gd", json_out=True).data["ok"]
        rep = cli.run("scene", "verify", "level", json_out=True).data
        assert rep["ok"] and rep["node_count"] == 5
        assert cli.run("run", "--frames", "3", json_out=True).data["ok"]
        print(f"\n  level nodes: {rep['nodes']}")

    def test_heavy_edit_undo_stress(self, game):
        """Simulates: iterative refinement with many undo/redo steps."""
        cli, root = game
        cli.run("scene", "new", "main")
        for i in range(8):
            cli.run("scene", "add-node", "main", f"N{i}", "--type", "Node")
        for _ in range(8):
            cli.run("session", "undo")
        assert len(cli.run("scene", "tree", "main", json_out=True).data) == 1
        for _ in range(8):
            cli.run("session", "redo")
        assert len(cli.run("scene", "tree", "main", json_out=True).data) == 9
        assert cli.run("scene", "verify", "main", json_out=True).data["node_count"] == 9
