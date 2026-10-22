"""project.godot manipulation (Godot ConfigFile text format).

The file is parsed into sections of entries, preserving comments, blank lines
and unknown values verbatim so edits are minimal.
"""

import os
import re
from pathlib import Path

CONFIG_VERSION = 5
_SECTION = re.compile(r"^\[([^\]]+)\]\s*$")
_KEY = re.compile(r"^([^=;\s][^=]*?)\s*=\s*(.*)$")

DEFAULT_HEADER = "; Engine configuration file.\n; It's best edited using the editor UI and not directly,\n; since the parameters that go here are not all obvious.\n;\n; Format:\n;   [section] ; section goes between []\n;   param=value ; assign values to parameters\n\n"

RENDERERS = {
    "compatibility": "gl_compatibility",
    "mobile": "mobile",
    "forward_plus": "forward_plus",
}


def _balance(text: str) -> bool:
    """True when brackets and quotes are balanced (value is complete)."""
    depth, in_str, esc = 0, False, False
    for ch in text:
        if in_str:
            if esc:
                esc = False
            elif ch == "\\":
                esc = True
            elif ch == '"':
                in_str = False
        elif ch == '"':
            in_str = True
        elif ch in "([{":
            depth += 1
        elif ch in ")]}":
            depth -= 1
    return depth <= 0 and not in_str


class ConfigDoc:
    """Ordered ConfigFile document. sections: list of [name, entries]; entry = ('kv',k,v) | ('raw',line)."""

    def __init__(self, sections=None):
        self.sections = sections or [["", []]]

    @classmethod
    def parse(cls, text: str) -> "ConfigDoc":
        doc = cls()
        cur = doc.sections[0]
        lines = text.replace("\r\n", "\n").split("\n")
        i = 0
        while i < len(lines):
            line = lines[i]
            m = _SECTION.match(line)
            if m:
                cur = [m.group(1), []]
                doc.sections.append(cur)
            else:
                km = _KEY.match(line)
                if km and not line.lstrip().startswith(";"):
                    key, val = km.group(1).strip(), km.group(2)
                    while not _balance(val) and i + 1 < len(lines):
                        i += 1
                        val += "\n" + lines[i]
                    cur[1].append(("kv", key, val))
                else:
                    cur[1].append(("raw", line))
            i += 1
        return doc

    def dump(self) -> str:
        out = []
        for name, entries in self.sections:
            if name:
                out.append(f"[{name}]")
            for e in entries:
                out.append(f"{e[1]}={e[2]}" if e[0] == "kv" else e[1])
        text = "\n".join(out)
        text = re.sub(r"\n{3,}", "\n\n", text)
        return text.rstrip("\n") + "\n"

    def _section(self, name, create=False):
        for sec in self.sections:
            if sec[0] == name:
                return sec
        if create:
            sec = [name, [("raw", "")]]
            self.sections.append(sec)
            return sec
        return None

    def get(self, section, key):
        sec = self._section(section)
        if sec:
            for e in sec[1]:
                if e[0] == "kv" and e[1] == key:
                    return e[2]
        return None

    def set(self, section, key, raw):
        sec = self._section(section, create=True)
        for idx, e in enumerate(sec[1]):
            if e[0] == "kv" and e[1] == key:
                sec[1][idx] = ("kv", key, raw)
                return
        # keep trailing blank line separation: insert before trailing raw blanks
        pos = len(sec[1])
        while pos > 0 and sec[1][pos - 1][0] == "raw" and not sec[1][pos - 1][1].strip():
            pos -= 1
        sec[1].insert(pos, ("kv", key, raw))

    def unset(self, section, key) -> bool:
        sec = self._section(section)
        if not sec:
            return False
        before = len(sec[1])
        sec[1] = [e for e in sec[1] if not (e[0] == "kv" and e[1] == key)]
        return len(sec[1]) != before

    def items(self):
        for name, entries in self.sections:
            for e in entries:
                if e[0] == "kv":
                    yield name, e[1], e[2]


def to_literal(value: str) -> str:
    """Turn a CLI string into a Godot literal. Existing literals pass through untouched."""
    v = value.strip()
    if v in ("true", "false", "null"):
        return v
    if re.fullmatch(r"-?\d+(\.\d+)?([eE][-+]?\d+)?", v):
        return v
    if v.startswith('"') and v.endswith('"') and len(v) >= 2:
        return v
    if re.match(r"^(&|\^|@)?\"", v):
        return v
    if re.match(r"^[A-Z][A-Za-z0-9]*\(.*\)$", v, re.S) or v[:1] in "[{":
        return v
    return '"' + v.replace("\\", "\\\\").replace('"', '\\"') + '"'


def from_literal(raw: str):
    """Best-effort decode of a Godot literal to a Python value (strings/numbers/bools), else raw text."""
    if raw is None:
        return None
    r = raw.strip()
    if r == "true":
        return True
    if r == "false":
        return False
    if re.fullmatch(r"-?\d+", r):
        return int(r)
    if re.fullmatch(r"-?\d+\.\d+([eE][-+]?\d+)?", r):
        return float(r)
    if len(r) >= 2 and r.startswith('"') and r.endswith('"') and '"' not in r[1:-1].replace('\\"', ""):
        return r[1:-1].replace('\\"', '"').replace("\\\\", "\\")
    return r


# ── project-level operations ──────────────────────────────────────────

def project_file(project_dir) -> Path:
    return Path(project_dir) / "project.godot"


def is_project(project_dir) -> bool:
    return project_file(project_dir).is_file()


def new_project_text(name: str, renderer: str = "compatibility", feature: str = "4.4") -> str:
    if renderer not in RENDERERS:
        raise ValueError(f"Unknown renderer '{renderer}'. Choose: {', '.join(RENDERERS)}")
    doc = ConfigDoc.parse(
        DEFAULT_HEADER + f"config_version={CONFIG_VERSION}\n\n[application]\n\n"
    )
    doc.set("application", "config/name", to_literal(name))
    doc.set("application", "config/features", f'PackedStringArray("{feature}"' +
            (', "GL Compatibility"' if renderer == "compatibility" else "") + ")")
    doc.set("rendering", "renderer/rendering_method", f'"{RENDERERS[renderer]}"')
    return doc.dump()


def project_info(project_dir, text: str) -> dict:
    doc = ConfigDoc.parse(text)
    root = Path(project_dir)
    scenes = sorted(str(p.relative_to(root)).replace(os.sep, "/") for p in root.rglob("*.tscn")
                    if ".godot" not in p.parts)
    scripts = sorted(str(p.relative_to(root)).replace(os.sep, "/") for p in root.rglob("*.gd")
                     if ".godot" not in p.parts)
    return {
        "path": str(root.resolve()),
        "name": from_literal(doc.get("application", "config/name")),
        "main_scene": from_literal(doc.get("application", "run/main_scene")),
        "config_version": from_literal(doc.get("", "config_version")),
        "features": doc.get("application", "config/features"),
        "renderer": from_literal(doc.get("rendering", "renderer/rendering_method")),
        "scene_count": len(scenes),
        "script_count": len(scripts),
        "scenes": scenes,
        "scripts": scripts,
    }


def split_setting(path: str):
    """'application/config/name' -> ('application', 'config/name'); 'config_version' -> ('', ...)."""
    if "/" not in path:
        return "", path
    section, key = path.split("/", 1)
    return section, key
