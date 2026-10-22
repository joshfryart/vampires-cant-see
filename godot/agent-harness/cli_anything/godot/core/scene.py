"""Godot text scene (.tscn) model: parse, edit, serialize.

Only the pieces the CLI edits are modelled (ext_resources, nodes and their
properties). Other sections (sub_resource, connection, editable, ...) are kept
verbatim so a round trip never loses data.
"""

import re
import secrets
import string
from collections import OrderedDict

from .project import _balance, to_literal

_HEADER_ATTR = re.compile(r'([A-Za-z_][A-Za-z0-9_]*)=("(?:[^"\\]|\\.)*"|[^\s\]]+(?:\([^)]*\))?)')


class SceneError(ValueError):
    pass


def _unquote(v: str) -> str:
    if len(v) >= 2 and v[0] == '"' and v[-1] == '"':
        return v[1:-1].replace('\\"', '"').replace("\\\\", "\\")
    return v


def _quote(v: str) -> str:
    return '"' + v.replace("\\", "\\\\").replace('"', '\\"') + '"'


class Section:
    """One [tag attr=...] block plus its property lines."""

    def __init__(self, tag, attrs=None, props=None, raw_body=None):
        self.tag = tag
        self.attrs = attrs if attrs is not None else OrderedDict()   # name -> raw token (quoted if string)
        self.props = props if props is not None else OrderedDict()   # key -> raw literal
        self.raw_body = raw_body or []                                # unparsed body (non-node sections)

    def attr(self, name, default=None):
        v = self.attrs.get(name)
        return default if v is None else _unquote(v)

    def header(self) -> str:
        parts = [self.tag] + [f"{k}={v}" for k, v in self.attrs.items()]
        return "[" + " ".join(parts) + "]"


class Scene:
    def __init__(self):
        self.sections: list[Section] = []

    # ── parse / dump ──
    @classmethod
    def parse(cls, text: str) -> "Scene":
        scene = cls()
        lines = text.replace("\r\n", "\n").split("\n")
        cur = None
        i = 0
        while i < len(lines):
            line = lines[i]
            if line.startswith("[") and line.rstrip().endswith("]") and _balance(line):
                inner = line.strip()[1:-1]
                tag, _, rest = inner.partition(" ")
                attrs = OrderedDict((m.group(1), m.group(2)) for m in _HEADER_ATTR.finditer(rest))
                cur = Section(tag, attrs)
                scene.sections.append(cur)
            elif cur is not None and line.strip():
                if cur.tag == "node" and re.match(r"^[A-Za-z_][\w/\-:.]*\s*=", line):
                    key, _, val = line.partition("=")
                    val = val.strip()
                    while not _balance(val) and i + 1 < len(lines):
                        i += 1
                        val += "\n" + lines[i]
                    cur.props[key.strip()] = val
                else:
                    cur.raw_body.append(line)
            i += 1
        if not scene.sections or scene.sections[0].tag != "gd_scene":
            raise SceneError("Not a text scene: missing [gd_scene] header")
        return scene

    def dump(self) -> str:
        self._fix_load_steps()
        blocks = []
        for s in self.sections:
            body = [f"{k} = {v}" for k, v in s.props.items()] + s.raw_body
            blocks.append(s.header() + ("\n" + "\n".join(body) if body else ""))
        return "\n\n".join(blocks) + "\n"

    def _fix_load_steps(self):
        head = self.sections[0]
        n = sum(1 for s in self.sections if s.tag in ("ext_resource", "sub_resource"))
        rest = OrderedDict((k, v) for k, v in head.attrs.items() if k != "load_steps")
        head.attrs = OrderedDict([("load_steps", str(n + 1))] + list(rest.items())) if n else rest

    # ── nodes ──
    def nodes(self):
        return [s for s in self.sections if s.tag == "node"]

    def node_path(self, node: Section) -> str:
        parent = node.attr("parent")
        if parent is None:
            return "."
        return node.attr("name") if parent == "." else f"{parent}/{node.attr('name')}"

    def find(self, path: str) -> Section:
        path = _norm_path(path, self)
        for n in self.nodes():
            if self.node_path(n) == path:
                return n
        raise SceneError(f"Node not found: '{path}'. Existing: {[self.node_path(n) for n in self.nodes()]}")

    def has(self, path: str) -> bool:
        try:
            self.find(path)
            return True
        except SceneError:
            return False

    def _insert_node_after_subtree(self, new_node: Section, parent_path: str):
        """Keep nodes in tree order: place after the parent's last descendant."""
        idxs = [i for i, s in enumerate(self.sections) if s.tag == "node"]
        parent_idx = None
        last = None
        for i in idxs:
            p = self.node_path(self.sections[i])
            if p == parent_path:
                parent_idx = i
                last = i
            elif parent_idx is not None and (p.startswith(parent_path + "/") or parent_path == "."):
                last = i
        self.sections.insert(last + 1, new_node)

    def add_node(self, name, node_type, parent=".", props=None, instance_path=None) -> Section:
        parent = _norm_path(parent, self)
        if not name or "/" in name or "." == name:
            raise SceneError(f"Invalid node name: '{name}'")
        if not self.has(parent):
            raise SceneError(f"Parent not found: '{parent}'")
        full = name if parent == "." else f"{parent}/{name}"
        if self.has(full):
            raise SceneError(f"Node already exists: '{full}'")
        attrs = OrderedDict([("name", _quote(name))])
        if node_type:
            attrs["type"] = _quote(node_type)
        attrs["parent"] = _quote(parent)
        node = Section("node", attrs)
        for k, v in (props or {}).items():
            node.props[k] = to_literal(v)
        self._insert_node_after_subtree(node, parent)
        return node

    def remove_node(self, path: str) -> int:
        target = self.find(path)
        tp = self.node_path(target)
        if tp == ".":
            raise SceneError("Cannot remove the scene root")
        before = len(self.sections)
        self.sections = [s for s in self.sections
                         if not (s.tag == "node" and (self.node_path(s) == tp or self.node_path(s).startswith(tp + "/")))]
        return before - len(self.sections)

    def set_prop(self, path, key, value):
        self.find(path).props[key] = to_literal(value)

    def unset_prop(self, path, key) -> bool:
        return self.find(path).props.pop(key, None) is not None

    def get_prop(self, path, key):
        return self.find(path).props.get(key)

    # ── resources ──
    def ext_resources(self):
        return [s for s in self.sections if s.tag == "ext_resource"]

    def add_ext_resource(self, res_type: str, res_path: str) -> str:
        for s in self.ext_resources():
            if s.attr("path") == res_path and s.attr("type") == res_type:
                return s.attr("id")
        used = {s.attr("id") for s in self.ext_resources()}
        n = len(used) + 1
        while True:
            rid = f"{n}_{''.join(secrets.choice(string.ascii_lowercase + string.digits) for _ in range(5))}"
            if rid not in used:
                break
        attrs = OrderedDict([("type", _quote(res_type)), ("path", _quote(res_path)), ("id", _quote(rid))])
        idx = max([i for i, s in enumerate(self.sections) if s.tag == "ext_resource"] or [0]) + 1
        self.sections.insert(idx, Section("ext_resource", attrs))
        return rid

    def attach_script(self, node_path: str, script_res_path: str) -> str:
        node = self.find(node_path)
        rid = self.add_ext_resource("Script", script_res_path)
        node.props["script"] = f'ExtResource("{rid}")'
        return rid

    # ── introspection ──
    def tree(self):
        out = []
        for n in self.nodes():
            p = self.node_path(n)
            out.append({
                "path": p,
                "name": n.attr("name"),
                "type": n.attr("type") or ("(instance)" if "instance" in n.attrs else None),
                "parent": n.attr("parent"),
                "properties": dict(n.props),
                "depth": 0 if p == "." else p.count("/") + 1,
            })
        return out


def _norm_path(path: str, scene: "Scene") -> str:
    """Accept '.', 'A/B', or a path prefixed with the root node name ('Root/A/B')."""
    path = (path or ".").strip().strip("/")
    if path in ("", "."):
        return "."
    nodes = scene.nodes()
    if nodes and nodes[0].attr("parent") is None:
        root = nodes[0].attr("name")
        if path == root:
            return "."
        if path.startswith(root + "/"):
            return path[len(root) + 1:]
    return path


def new_scene_text(root_name: str, root_type: str = "Node") -> str:
    s = Scene.parse("[gd_scene format=3]\n")
    root = Section("node", OrderedDict([("name", _quote(root_name)), ("type", _quote(root_type))]))
    s.sections.append(root)
    return s.dump()


def new_script_text(extends: str = "Node", with_ready: bool = True) -> str:
    body = f"extends {extends}\n\n"
    if with_ready:
        body += "\nfunc _ready() -> void:\n\tpass\n"
    return body
