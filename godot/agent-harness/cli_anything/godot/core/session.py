"""Session: staged edits + persistent undo/redo history for a Godot project.

Edits are staged in memory (`stage`) and committed with `save_session`.
Each commit stores the previous on-disk content of every touched file in
`<project>/.cli-anything/history.json`, so undo/redo works across separate
one-shot invocations as well as inside the REPL.
"""

import json
import os
from pathlib import Path

HISTORY_DIR = ".cli-anything"
HISTORY_FILE = "history.json"
MAX_HISTORY = 50


def _locked_save_json(path, data, **dump_kwargs) -> None:
    """Write JSON with an exclusive lock (open r+, lock, truncate inside the lock)."""
    try:
        f = open(path, "r+", encoding="utf-8")
    except FileNotFoundError:
        os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
        f = open(path, "w", encoding="utf-8")
    with f:
        _locked = False
        try:
            import fcntl
            fcntl.flock(f.fileno(), fcntl.LOCK_EX)
            _locked = True
        except (ImportError, OSError):
            try:
                import msvcrt  # Windows: lock first byte
                f.seek(0)
                msvcrt.locking(f.fileno(), msvcrt.LK_LOCK, 1)
                _locked = "win"
            except (ImportError, OSError):
                pass
        try:
            f.seek(0)
            f.truncate()
            json.dump(data, f, **dump_kwargs)
            f.flush()
        finally:
            if _locked is True:
                import fcntl
                fcntl.flock(f.fileno(), fcntl.LOCK_UN)
            elif _locked == "win":
                import msvcrt
                f.seek(0)
                try:
                    msvcrt.locking(f.fileno(), msvcrt.LK_UNLCK, 1)
                except OSError:
                    pass


def _write_text(path: Path, text: str):
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)


class Session:
    def __init__(self):
        self.project_dir: Path | None = None
        self.project_path: str | None = None   # alias used by the auto-save hook
        self._staged: dict[str, str | None] = {}   # rel path -> new text (None = delete)
        self._modified = False
        self._label = ""

    # ── project binding ──
    def open(self, project_dir):
        d = Path(project_dir).resolve()
        if not d.is_dir():
            raise FileNotFoundError(f"Project directory not found: {project_dir}")
        self.project_dir = d
        self.project_path = str(d)
        self._staged.clear()
        self._modified = False

    def has_project(self) -> bool:
        return self.project_dir is not None

    def _require(self):
        if not self.project_dir:
            raise RuntimeError("No project open. Pass --project <dir> (a folder containing project.godot).")

    # ── file access (staged view over disk) ──
    def abs(self, rel: str) -> Path:
        self._require()
        p = (self.project_dir / rel.replace("res://", "")).resolve()
        if self.project_dir not in p.parents and p != self.project_dir:
            raise ValueError(f"Path escapes the project: {rel}")
        return p

    def rel(self, rel: str) -> str:
        return str(self.abs(rel).relative_to(self.project_dir)).replace(os.sep, "/")

    def exists(self, rel: str) -> bool:
        r = self.rel(rel)
        if r in self._staged:
            return self._staged[r] is not None
        return self.abs(r).is_file()

    def read(self, rel: str) -> str:
        r = self.rel(rel)
        if r in self._staged:
            if self._staged[r] is None:
                raise FileNotFoundError(r)
            return self._staged[r]
        p = self.abs(r)
        if not p.is_file():
            raise FileNotFoundError(f"File not found in project: {r}")
        return p.read_text(encoding="utf-8")

    def stage(self, rel: str, text: str | None, label: str = ""):
        self._staged[self.rel(rel)] = text
        self._modified = True
        if label:
            self._label = label

    def staged_files(self):
        return sorted(self._staged)

    def discard(self):
        self._staged.clear()
        self._modified = False

    # ── history ──
    def _hist_path(self) -> Path:
        return self.project_dir / HISTORY_DIR / HISTORY_FILE

    def _load_hist(self) -> dict:
        try:
            return json.loads(self._hist_path().read_text(encoding="utf-8"))
        except (OSError, ValueError):
            return {"undo": [], "redo": []}

    def _save_hist(self, hist):
        hist["undo"] = hist["undo"][-MAX_HISTORY:]
        _locked_save_json(self._hist_path(), hist, indent=1)

    def _snapshot_disk(self, rels):
        snap = {}
        for r in rels:
            p = self.abs(r)
            snap[r] = p.read_text(encoding="utf-8") if p.is_file() else None
        return snap

    def _apply(self, files: dict):
        for r, text in files.items():
            p = self.abs(r)
            if text is None:
                if p.exists():
                    p.unlink()
            else:
                _write_text(p, text)

    def save_session(self, label: str = "") -> list:
        """Commit staged files to disk and record an undo entry. Returns files written."""
        self._require()
        if not self._staged:
            self._modified = False
            return []
        rels = sorted(self._staged)
        before = self._snapshot_disk(rels)
        self._apply(self._staged)
        hist = self._load_hist()
        hist["undo"].append({"label": label or self._label or "edit", "files": before})
        hist["redo"] = []
        self._save_hist(hist)
        self._staged.clear()
        self._modified = False
        return rels

    def undo(self) -> dict:
        self._require()
        if self._staged:
            raise RuntimeError("Unsaved staged changes exist; save or discard them before undo.")
        hist = self._load_hist()
        if not hist["undo"]:
            raise RuntimeError("Nothing to undo.")
        entry = hist["undo"].pop()
        current = self._snapshot_disk(entry["files"])
        self._apply(entry["files"])
        hist["redo"].append({"label": entry["label"], "files": current})
        self._save_hist(hist)
        return {"undone": entry["label"], "files": sorted(entry["files"])}

    def redo(self) -> dict:
        self._require()
        if self._staged:
            raise RuntimeError("Unsaved staged changes exist; save or discard them before redo.")
        hist = self._load_hist()
        if not hist["redo"]:
            raise RuntimeError("Nothing to redo.")
        entry = hist["redo"].pop()
        current = self._snapshot_disk(entry["files"])
        self._apply(entry["files"])
        hist["undo"].append({"label": entry["label"], "files": current})
        self._save_hist(hist)
        return {"redone": entry["label"], "files": sorted(entry["files"])}

    def history(self) -> dict:
        self._require()
        h = self._load_hist()
        return {
            "undo": [e["label"] for e in h["undo"]],
            "redo": [e["label"] for e in h["redo"]],
        }

    def status(self) -> dict:
        h = self._load_hist() if self.project_dir else {"undo": [], "redo": []}
        return {
            "project": self.project_path,
            "modified": self._modified,
            "staged_files": self.staged_files(),
            "undo_depth": len(h["undo"]),
            "redo_depth": len(h["redo"]),
        }
