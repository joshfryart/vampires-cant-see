# TEST.md: cli-anything-godot

## Part 1: Test plan

### Inventory
- `test_core.py`: 41 unit tests collected (34 test functions, some parametrized); no Godot required
- `test_full_e2e.py`: 20 E2E tests; use the real Godot executable and fail, not skip, when it is missing

### Unit tests (`test_core.py`)
| Module | Covered |
|---|---|
| `core/project.py` | ConfigFile parse/dump round trip with comments and multi-line values, set/unset, `to_literal`/`from_literal`, `split_setting`, new-project text, unknown renderer error, `project_info` |
| `core/scene.py` | new scene text, non-scene rejection, nested add-node and paths, root-prefixed paths, duplicate/missing-parent/bad-name errors, tree ordering, subtree removal, root removal blocked, properties, script attach with ext_resource reuse and `load_steps`, round trip of sub_resource/connection sections, multi-line properties |
| `core/session.py` | staging vs disk, path-escape guard, undo/redo cycle, redo cleared by new edit, history persisted across instances, undo blocked while staged, atomic multi-file undo, history cap, valid history JSON |

### E2E plan (`test_full_e2e.py`)
- **Backend:** real `--version`; clear error for a missing `GODOT_PATH`.
- **Engine validates native files:** a scene written by the CLI is loaded and instantiated by Godot (node list compared); a damaged scene must fail verification; `script check` on good and broken GDScript; `script run` prints engine output and user args; headless run of the main scene.
- **Real backend output:** `--import` creates the `.godot` cache; `render` writes PNG frames (magic bytes checked); `export pack` produces a `.pck` (magic `GDPC`) and a `.zip` (contains `main.tscn.remap` and `project.binary`).
- **Subprocess (installed command via `_resolve_cli`):** `--help`, `--json`, project creation, auto-save and `--dry-run`, JSON error and exit code 1, undo/redo across separate processes, a setting written by the CLI then read back by the real engine.

### Workflow scenarios
1. **Level scaffolding.** Simulates an agent building a small 2D level. Chain: `scene new --main`, four `add-node`, `script new --attach`, `set-prop`, `script check`, `scene verify`, `run`. Verified: five nodes reported by the engine, script parses, run exits 0.
2. **Iterative refinement / undo stress.** Simulates trial-and-error editing. Chain: 8 adds, 8 undos, 8 redos. Verified: tree size at each stage (1, then 9) and engine node count of 9.

## Part 2: Results

Environment: Windows 11, Python 3.15, Godot 4.4.1.stable.official.49a5bc7b6. Run with `CLI_ANYTHING_FORCE_INSTALLED=1` so the installed `cli-anything-godot.EXE` is exercised. Command: `python -m pytest cli_anything/godot/tests -v -s`.

```
============================= test session starts =============================
platform win32 -- Python 3.15.0, pytest-9.1.1, pluggy-1.7.0 -- C:\Users\hello\AppData\Local\Python\pythoncore-3.15-64\python.exe
collecting ... [_resolve_cli] Using installed command: C:\Users\hello\AppData\Local\Python\pythoncore-3.15-64\Scripts\cli-anything-godot.EXE
collected 61 items

test_core.py::TestConfigDoc::test_new_project_text PASSED
test_core.py::TestConfigDoc::test_unknown_renderer PASSED
test_core.py::TestConfigDoc::test_round_trip_preserves_comments PASSED
test_core.py::TestConfigDoc::test_set_existing_and_new PASSED
test_core.py::TestConfigDoc::test_unset PASSED
test_core.py::TestConfigDoc::test_multiline_value_kept_whole PASSED
test_core.py::TestConfigDoc::test_to_literal[true-true] PASSED
test_core.py::TestConfigDoc::test_to_literal[42-42] PASSED
test_core.py::TestConfigDoc::test_to_literal[-1.5--1.5] PASSED
test_core.py::TestConfigDoc::test_to_literal[hello-"hello"] PASSED
test_core.py::TestConfigDoc::test_to_literal["quoted"-"quoted"] PASSED
test_core.py::TestConfigDoc::test_to_literal[Vector2(1, 2)-Vector2(1, 2)] PASSED
test_core.py::TestConfigDoc::test_to_literal[[1, 2]-[1, 2]] PASSED
test_core.py::TestConfigDoc::test_to_literal[say "hi"-"say \\"hi\\""] PASSED
test_core.py::TestConfigDoc::test_from_literal PASSED
test_core.py::TestConfigDoc::test_split_setting PASSED
test_core.py::TestScene::test_new_scene_text PASSED
test_core.py::TestScene::test_parse_rejects_non_scene PASSED
test_core.py::TestScene::test_add_nested_nodes_and_paths PASSED
test_core.py::TestScene::test_root_prefixed_parent_path PASSED
test_core.py::TestScene::test_duplicate_and_missing_parent PASSED
test_core.py::TestScene::test_sibling_insert_keeps_tree_order PASSED
test_core.py::TestScene::test_remove_node_removes_subtree PASSED
test_core.py::TestScene::test_cannot_remove_root PASSED
test_core.py::TestScene::test_props PASSED
test_core.py::TestScene::test_attach_script_and_load_steps PASSED
test_core.py::TestScene::test_round_trip_keeps_unknown_sections PASSED
test_core.py::TestScene::test_multiline_property_parsed_whole PASSED
test_core.py::TestSession::test_requires_project PASSED
test_core.py::TestSession::test_open_missing_dir PASSED
test_core.py::TestSession::test_stage_not_on_disk_until_save PASSED
test_core.py::TestSession::test_path_escape_blocked PASSED
test_core.py::TestSession::test_undo_redo_cycle PASSED
test_core.py::TestSession::test_new_edit_clears_redo PASSED
test_core.py::TestSession::test_history_persists_across_instances PASSED
test_core.py::TestSession::test_undo_blocked_with_staged_changes PASSED
test_core.py::TestSession::test_nothing_to_undo PASSED
test_core.py::TestSession::test_multi_file_atomic_undo PASSED
test_core.py::TestSession::test_history_cap PASSED
test_core.py::TestSession::test_history_file_is_valid_json PASSED
test_core.py::test_project_info_lists_scenes_and_scripts PASSED
test_full_e2e.py::TestBackend::test_version_is_godot4 
  Godot: 4.4.1.stable.official.49a5bc7b6 at C:/Users/hello/OneDrive/Desktop/claude/Vampires Cant See/Godot_v4.4.1-stable_win64.exe
PASSED
test_full_e2e.py::TestBackend::test_missing_executable_error PASSED
test_full_e2e.py::TestEngineValidatesNativeFiles::test_project_scene_loads_in_engine 
  scene nodes: ['.', 'Hero', 'Hero/Hat']
PASSED
test_full_e2e.py::TestEngineValidatesNativeFiles::test_verify_fails_on_broken_scene PASSED
test_full_e2e.py::TestEngineValidatesNativeFiles::test_script_check_ok_and_error PASSED
test_full_e2e.py::TestEngineValidatesNativeFiles::test_script_run_prints_output PASSED
test_full_e2e.py::TestEngineValidatesNativeFiles::test_run_main_scene_headless PASSED
test_full_e2e.py::TestImportRenderExport::test_import_creates_cache PASSED
test_full_e2e.py::TestImportRenderExport::test_render_png_frames 
  PNG: C:\Users\hello\AppData\Local\Temp\pytest-of-hello\pytest-3\test_render_png_frames0\game\out\frame00000000.png (326 bytes)

  PNG: C:\Users\hello\AppData\Local\Temp\pytest-of-hello\pytest-3\test_render_png_frames0\game\out\frame00000001.png (326 bytes)

  PNG: C:\Users\hello\AppData\Local\Temp\pytest-of-hello\pytest-3\test_render_png_frames0\game\out\frame00000002.png (326 bytes)
PASSED
test_full_e2e.py::TestImportRenderExport::test_export_pack_with_preset 
  PCK: C:\Users\hello\AppData\Local\Temp\pytest-of-hello\pytest-3\test_export_pack_with_preset0\game\build\game.pck (1,360 bytes)
PASSED
test_full_e2e.py::TestImportRenderExport::test_export_zip_pack 
  ZIP: C:\Users\hello\AppData\Local\Temp\pytest-of-hello\pytest-3\test_export_zip_pack0\game\build\game.zip (1,110 bytes)
PASSED
test_full_e2e.py::TestCLISubprocess::test_help PASSED
test_full_e2e.py::TestCLISubprocess::test_engine_version_json PASSED
test_full_e2e.py::TestCLISubprocess::test_project_new_json PASSED
test_full_e2e.py::TestCLISubprocess::test_autosave_and_dry_run PASSED
test_full_e2e.py::TestCLISubprocess::test_error_is_json_and_nonzero PASSED
test_full_e2e.py::TestCLISubprocess::test_undo_redo_across_processes PASSED
test_full_e2e.py::TestCLISubprocess::test_project_setting_roundtrip_engine_reads PASSED
test_full_e2e.py::TestWorkflows::test_build_level_scene_with_script_and_verify 
  level nodes: ['.', 'World', 'World/Ground', 'World/Player', 'World/Player/Cam']
PASSED
test_full_e2e.py::TestWorkflows::test_heavy_edit_undo_stress PASSED

============================= 61 passed in 54.42s =============================
```

### Summary
- Total 61 tests, 61 passed (100%), about 54 s.
- Artifact paths printed for manual inspection: PNG frames, `.pck`, `.zip`, level node list.

### Coverage notes / gaps
- `render` needs a GPU/display; not verified on headless CI.
- `export release|debug` are untested (need export templates); `export pack` is tested.
- The REPL was smoke-tested manually with piped stdin; no automated test.
- `sub_resource` and `[connection]` editing are not implemented (sections are preserved on round trip).
- Windows only so far.
