"""Backend: invokes the real Godot Engine executable.

All rendering, export, import, script checking and scene verification is done
by the real engine. Nothing here reimplements Godot behaviour.

Executable discovery order:
  1. $GODOT_PATH
  2. path saved with `cli-anything-godot config set-path`
  3. `godot` / `godot4` / `Godot*` on PATH
"""

import json
import os
import re
import shutil
import subprocess
import tempfile
from pathlib import Path

CONFIG_DIR = Path(os.environ.get("CLI_ANYTHING_GODOT_HOME", Path.home() / ".cli-anything-godot"))
CONFIG_FILE = CONFIG_DIR / "config.json"

INSTALL_HELP = (
    "Godot is not installed or not found. Install it from https://godotengine.org/download\n"
    "  winget install GodotEngine.GodotEngine   # Windows\n"
    "  brew install --cask godot                # macOS\n"
    "  apt install godot3 / flatpak install org.godotengine.Godot   # Linux\n"
    "Then either put it on PATH, set GODOT_PATH, or run:\n"
    "  cli-anything-godot config set-path /path/to/Godot_v4.x.exe"
)


def _read_config() -> dict:
    try:
        return json.loads(CONFIG_FILE.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}


def save_godot_path(path: str) -> str:
    p = Path(path).expanduser()
    if not p.is_file():
        raise RuntimeError(f"Not a file: {path}")
    CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    cfg = _read_config()
    cfg["godot_path"] = str(p.resolve())
    CONFIG_FILE.write_text(json.dumps(cfg, indent=2), encoding="utf-8")
    return cfg["godot_path"]


def find_godot() -> str:
    env = os.environ.get("GODOT_PATH")
    if env:
        if Path(env).is_file():
            return env
        raise RuntimeError(f"GODOT_PATH points to a missing file: {env}")
    saved = _read_config().get("godot_path")
    if saved and Path(saved).is_file():
        return saved
    for name in ("godot", "godot4", "Godot", "godot.exe", "godot4.exe"):
        found = shutil.which(name)
        if found:
            return found
    raise RuntimeError(INSTALL_HELP)


def run_godot(args, cwd=None, timeout=300, headless=True) -> dict:
    """Run Godot with args. Returns {returncode, stdout, stderr, command}."""
    exe = find_godot()
    cmd = [exe, "--no-header"]
    if headless:
        cmd.append("--headless")
    cmd += [str(a) for a in args]
    try:
        proc = subprocess.run(
            cmd, cwd=cwd, capture_output=True, text=True,
            encoding="utf-8", errors="replace", timeout=timeout,
        )
    except subprocess.TimeoutExpired as e:
        raise RuntimeError(f"Godot timed out after {timeout}s: {' '.join(cmd)}") from e
    return {
        "returncode": proc.returncode,
        "stdout": _clean(proc.stdout),
        "stderr": _clean(proc.stderr),
        "command": cmd,
    }


_ANSI = re.compile(r"\x1b\[[0-9;]*m")


def _clean(text: str) -> str:
    return _ANSI.sub("", text or "").strip()


def version() -> dict:
    exe = find_godot()
    out = subprocess.run([exe, "--version"], capture_output=True, text=True, timeout=60)
    ver = _clean(out.stdout)
    m = re.match(r"(\d+)\.(\d+)(?:\.(\d+))?\.(\w+)", ver)
    return {
        "executable": exe,
        "version": ver,
        "major": int(m.group(1)) if m else None,
        "minor": int(m.group(2)) if m else None,
        "channel": m.group(4) if m else None,
    }


def import_project(project_dir: str, timeout=600) -> dict:
    """Run the editor importer so .import files and the .godot cache exist."""
    return run_godot(["--path", project_dir, "--import"], timeout=timeout)


def check_script(project_dir: str, script: str) -> dict:
    """Parse a GDScript with the real engine (--check-only)."""
    return run_godot(["--path", project_dir, "--script", script, "--check-only"])


def run_script(project_dir: str, script: str, user_args=(), timeout=300) -> dict:
    args = ["--path", project_dir, "--script", script]
    if user_args:
        args += ["--"] + list(user_args)
    return run_godot(args, timeout=timeout)


def run_scene(project_dir: str, scene: str = None, quit_after: int = 2, timeout=300) -> dict:
    args = ["--path", project_dir, "--quit-after", str(quit_after)]
    if scene:
        args.append(scene)
    return run_godot(args, timeout=timeout)


_VERIFY_SCRIPT = '''extends SceneTree

func _init():
	var report := {"scene": "%(scene)s", "ok": false}
	var res = ResourceLoader.load("%(scene)s")
	if res == null or not (res is PackedScene):
		report["error"] = "failed to load as PackedScene"
	else:
		var root = res.instantiate()
		if root == null:
			report["error"] = "instantiate() returned null"
		else:
			var names := []
			var stack := [root]
			while stack.size() > 0:
				var n = stack.pop_back()
				names.append(str(root.get_path_to(n)))
				for c in n.get_children():
					stack.append(c)
			names.sort()
			report["ok"] = true
			report["root"] = root.name
			report["root_type"] = root.get_class()
			report["node_count"] = names.size()
			report["nodes"] = names
			root.free()
	print("CLI_ANYTHING_JSON:" + JSON.stringify(report))
	quit(0 if report["ok"] else 1)
'''


def verify_scene(project_dir: str, scene_res_path: str) -> dict:
    """Load + instantiate a scene in the real engine and return its node list."""
    with tempfile.TemporaryDirectory(prefix="cli_godot_") as tmp:
        script = Path(tmp) / "verify_scene.gd"
        script.write_text(_VERIFY_SCRIPT % {"scene": scene_res_path}, encoding="utf-8")
        res = run_godot(["--path", project_dir, "--script", str(script)])
    for line in res["stdout"].splitlines():
        if line.startswith("CLI_ANYTHING_JSON:"):
            data = json.loads(line[len("CLI_ANYTHING_JSON:"):])
            data["engine_returncode"] = res["returncode"]
            # Godot loads damaged scenes leniently; treat logged engine errors as failure.
            errors = [l.strip() for l in (res["stdout"] + chr(10) + res["stderr"]).splitlines()
                      if "ERROR:" in l or "SCRIPT ERROR" in l]
            data["engine_errors"] = errors
            if errors and data.get("ok"):
                data["ok"] = False
                data["error"] = "engine reported errors while loading: " + errors[0]
            return data
    return {"ok": False, "scene": scene_res_path, "error": "engine produced no report",
            "engine_returncode": res["returncode"], "stdout": res["stdout"], "stderr": res["stderr"]}


def write_movie(project_dir: str, out_path: str, scene: str = None, frames: int = 5,
                fps: int = 30, resolution: str = None, timeout=300) -> dict:
    """Render frames with Godot's movie maker (needs a display/GPU, not --headless)."""
    args = ["--path", project_dir, "--write-movie", out_path, "--fixed-fps", str(fps),
            "--quit-after", str(frames)]
    if resolution:
        args += ["--resolution", resolution]
    if scene:
        args.append(scene)
    return run_godot(args, timeout=timeout, headless=False)


def export_project(project_dir: str, mode: str, preset: str, out_path: str, timeout=900) -> dict:
    flag = {"release": "--export-release", "debug": "--export-debug", "pack": "--export-pack"}[mode]
    return run_godot(["--path", project_dir, flag, preset, out_path], timeout=timeout)
