"""Unit tests: synthetic data, no Godot executable required."""

import json
import os

import pytest

from cli_anything.godot.core import project as P
from cli_anything.godot.core import scene as S
from cli_anything.godot.core.session import Session


# ── project.godot / ConfigFile ──

class TestConfigDoc:
    def test_new_project_text(self):
        text = P.new_project_text("Demo", "compatibility")
        doc = P.ConfigDoc.parse(text)
        assert doc.get("", "config_version") == "5"
        assert P.from_literal(doc.get("application", "config/name")) == "Demo"
        assert P.from_literal(doc.get("rendering", "renderer/rendering_method")) == "gl_compatibility"

    def test_unknown_renderer(self):
        with pytest.raises(ValueError):
            P.new_project_text("x", "bogus")

    def test_round_trip_preserves_comments(self):
        text = "; hello\nconfig_version=5\n\n[application]\n\nconfig/name=\"A\"\n"
        assert P.ConfigDoc.parse(text).dump() == text

    def test_set_existing_and_new(self):
        doc = P.ConfigDoc.parse(P.new_project_text("Demo"))
        doc.set("application", "config/name", '"Other"')
        doc.set("display", "window/size/viewport_width", "640")
        out = P.ConfigDoc.parse(doc.dump())
        assert P.from_literal(out.get("application", "config/name")) == "Other"
        assert P.from_literal(out.get("display", "window/size/viewport_width")) == 640

    def test_unset(self):
        doc = P.ConfigDoc.parse(P.new_project_text("Demo"))
        assert doc.unset("application", "config/name") is True
        assert doc.unset("application", "config/name") is False

    def test_multiline_value_kept_whole(self):
        text = 'config_version=5\n\n[input]\n\nui={\n"a": 1,\n"b": [1, 2]\n}\nother=2\n'
        doc = P.ConfigDoc.parse(text)
        assert doc.get("input", "ui").startswith("{") and doc.get("input", "ui").endswith("}")
        assert doc.get("input", "other") == "2"
        assert doc.dump() == text

    @pytest.mark.parametrize("given,expected", [
        ("true", "true"), ("42", "42"), ("-1.5", "-1.5"), ("hello", '"hello"'),
        ('"quoted"', '"quoted"'), ("Vector2(1, 2)", "Vector2(1, 2)"), ("[1, 2]", "[1, 2]"),
        ('say "hi"', '"say \\"hi\\""'),
    ])
    def test_to_literal(self, given, expected):
        assert P.to_literal(given) == expected

    def test_from_literal(self):
        assert P.from_literal("true") is True
        assert P.from_literal("3") == 3
        assert P.from_literal("3.5") == 3.5
        assert P.from_literal('"x"') == "x"
        assert P.from_literal("Vector2(1, 2)") == "Vector2(1, 2)"
        assert P.from_literal(None) is None

    def test_split_setting(self):
        assert P.split_setting("application/config/name") == ("application", "config/name")
        assert P.split_setting("config_version") == ("", "config_version")


# ── scenes ──

class TestScene:
    def make(self):
        return S.Scene.parse(S.new_scene_text("Main", "Node2D"))

    def test_new_scene_text(self):
        text = S.new_scene_text("Main", "Node2D")
        assert text.startswith("[gd_scene format=3]")
        assert '[node name="Main" type="Node2D"]' in text

    def test_parse_rejects_non_scene(self):
        with pytest.raises(S.SceneError):
            S.Scene.parse("[foo]\n")

    def test_add_nested_nodes_and_paths(self):
        sc = self.make()
        sc.add_node("A", "Node2D")
        sc.add_node("B", "Sprite2D", parent="A")
        paths = [t["path"] for t in sc.tree()]
        assert paths == [".", "A", "A/B"]

    def test_root_prefixed_parent_path(self):
        sc = self.make()
        sc.add_node("A", "Node2D", parent="Main")
        sc.add_node("B", "Node", parent="Main/A")
        assert sc.has("A/B")

    def test_duplicate_and_missing_parent(self):
        sc = self.make()
        sc.add_node("A", "Node")
        with pytest.raises(S.SceneError):
            sc.add_node("A", "Node")
        with pytest.raises(S.SceneError):
            sc.add_node("X", "Node", parent="Nope")
        with pytest.raises(S.SceneError):
            sc.add_node("bad/name", "Node")

    def test_sibling_insert_keeps_tree_order(self):
        sc = self.make()
        sc.add_node("A", "Node")
        sc.add_node("B", "Node")
        sc.add_node("A1", "Node", parent="A")
        assert [t["path"] for t in sc.tree()] == [".", "A", "A/A1", "B"]

    def test_remove_node_removes_subtree(self):
        sc = self.make()
        sc.add_node("A", "Node")
        sc.add_node("A1", "Node", parent="A")
        sc.add_node("B", "Node")
        assert sc.remove_node("A") == 2
        assert [t["path"] for t in sc.tree()] == [".", "B"]

    def test_cannot_remove_root(self):
        with pytest.raises(S.SceneError):
            self.make().remove_node(".")

    def test_props(self):
        sc = self.make()
        sc.add_node("P", "Sprite2D", props={"position": "Vector2(1, 2)", "name_tag": "hi"})
        assert sc.get_prop("P", "position") == "Vector2(1, 2)"
        assert sc.get_prop("P", "name_tag") == '"hi"'
        sc.set_prop("P", "visible", "false")
        assert sc.get_prop("P", "visible") == "false"
        assert sc.unset_prop("P", "visible") is True
        assert sc.unset_prop("P", "visible") is False

    def test_attach_script_and_load_steps(self):
        sc = self.make()
        sc.add_node("P", "Node")
        rid = sc.attach_script("P", "res://p.gd")
        assert sc.get_prop("P", "script") == f'ExtResource("{rid}")'
        text = sc.dump()
        assert "load_steps=2" in text
        # same script twice reuses the ext_resource
        assert sc.add_ext_resource("Script", "res://p.gd") == rid
        assert text.count("[ext_resource") == 1

    def test_round_trip_keeps_unknown_sections(self):
        text = ('[gd_scene load_steps=2 format=3]\n\n'
                '[sub_resource type="RectangleShape2D" id="RectangleShape2D_1"]\nsize = Vector2(4, 4)\n\n'
                '[node name="Main" type="Node2D"]\n\n'
                '[connection signal="ready" from="." to="." method="_on_ready"]\n')
        out = S.Scene.parse(text).dump()
        assert "[sub_resource" in out and "size = Vector2(4, 4)" in out
        assert "[connection signal=" in out

    def test_multiline_property_parsed_whole(self):
        text = ('[gd_scene format=3]\n\n[node name="Main" type="Node"]\n'
                'meta = {\n"a": 1,\n"b": 2\n}\nvisible = true\n')
        sc = S.Scene.parse(text)
        root = sc.find(".")
        assert root.props["meta"].startswith("{") and root.props["visible"] == "true"


# ── session ──

@pytest.fixture
def sess(tmp_path):
    s = Session()
    s.open(tmp_path)
    return s


class TestSession:
    def test_requires_project(self):
        with pytest.raises(RuntimeError):
            Session().read("a.txt")

    def test_open_missing_dir(self):
        with pytest.raises(FileNotFoundError):
            Session().open("/definitely/not/here")

    def test_stage_not_on_disk_until_save(self, sess, tmp_path):
        sess.stage("a.txt", "one", "make a")
        assert sess._modified and sess.read("a.txt") == "one"
        assert not (tmp_path / "a.txt").exists()
        assert sess.save_session() == ["a.txt"]
        assert (tmp_path / "a.txt").read_text() == "one"
        assert not sess._modified

    def test_path_escape_blocked(self, sess):
        with pytest.raises(ValueError):
            sess.abs("../evil.txt")

    def test_undo_redo_cycle(self, sess, tmp_path):
        sess.stage("a.txt", "v1", "v1"); sess.save_session()
        sess.stage("a.txt", "v2", "v2"); sess.save_session()
        assert sess.undo()["undone"] == "v2"
        assert (tmp_path / "a.txt").read_text() == "v1"
        sess.undo()
        assert not (tmp_path / "a.txt").exists()
        assert sess.redo()["redone"] == "v1"
        sess.redo()
        assert (tmp_path / "a.txt").read_text() == "v2"
        with pytest.raises(RuntimeError):
            sess.redo()

    def test_new_edit_clears_redo(self, sess):
        sess.stage("a.txt", "1", "1"); sess.save_session()
        sess.undo()
        sess.stage("a.txt", "2", "2"); sess.save_session()
        assert sess.history()["redo"] == []

    def test_history_persists_across_instances(self, sess, tmp_path):
        sess.stage("a.txt", "x", "first"); sess.save_session()
        other = Session(); other.open(tmp_path)
        assert other.history()["undo"] == ["first"]
        other.undo()
        assert not (tmp_path / "a.txt").exists()

    def test_undo_blocked_with_staged_changes(self, sess):
        sess.stage("a.txt", "1", "1"); sess.save_session()
        sess.stage("b.txt", "2", "2")
        with pytest.raises(RuntimeError):
            sess.undo()
        sess.discard()
        sess.undo()

    def test_nothing_to_undo(self, sess):
        with pytest.raises(RuntimeError):
            sess.undo()

    def test_multi_file_atomic_undo(self, sess, tmp_path):
        sess.stage("a.txt", "A", "pair"); sess.stage("b.txt", "B", "pair"); sess.save_session()
        sess.undo()
        assert not (tmp_path / "a.txt").exists() and not (tmp_path / "b.txt").exists()

    def test_history_cap(self, sess):
        from cli_anything.godot.core import session as sm
        for i in range(sm.MAX_HISTORY + 5):
            sess.stage("a.txt", str(i), str(i)); sess.save_session()
        assert len(sess.history()["undo"]) == sm.MAX_HISTORY

    def test_history_file_is_valid_json(self, sess, tmp_path):
        sess.stage("a.txt", "x", "x"); sess.save_session()
        data = json.loads((tmp_path / ".cli-anything" / "history.json").read_text())
        assert data["undo"][0]["label"] == "x"


def test_project_info_lists_scenes_and_scripts(tmp_path):
    (tmp_path / "project.godot").write_text(P.new_project_text("Demo"))
    (tmp_path / "a.tscn").write_text(S.new_scene_text("A"))
    (tmp_path / "sub").mkdir()
    (tmp_path / "sub" / "b.gd").write_text("extends Node\n")
    info = P.project_info(tmp_path, (tmp_path / "project.godot").read_text())
    assert info["name"] == "Demo"
    assert info["scenes"] == ["a.tscn"] and info["scripts"] == ["sub/b.gd"]
