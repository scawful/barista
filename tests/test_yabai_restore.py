#!/usr/bin/env python3
"""Exercise startup preference replay without calling a real Yabai daemon."""

import argparse
import contextlib
import copy
import io
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
import yabai_restore
import yabai_state


class RestoreTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.path = Path(self.temp.name) / "state.json"
        self.spaces = [
            {"index": 1, "id": 101, "uuid": "A", "type": "bsp", "is-native-fullscreen": False},
            {"index": 2, "id": 102, "uuid": "B", "type": "bsp", "is-native-fullscreen": False},
        ]
        self.rules = [{"label": "yaze-base", "app": "^Yaze$", "manage": False, "sub-layer": "below"}]
        self.calls = []
        self.fail_apply = False
        self.ignore_apply = False
        self.changed_identity = False
        self.pinned_spaces = set()
        self.windows = []

    def run_yabai(self, argv, **kwargs):
        self.calls.append(argv[2:])
        command = argv[2:]
        result = ""
        if command == ["query", "--spaces"]:
            result = json.dumps(self.spaces)
        elif command[:3] == ["query", "--spaces", "--space"]:
            space = next(space for space in self.spaces if str(space["index"]) == command[3])
            result = json.dumps({**space, "id": 999} if self.changed_identity else space)
        elif command == ["rule", "--list"]:
            result = json.dumps(self.rules)
        elif command == ["query", "--windows"]:
            result = json.dumps(self.windows)
        elif command[0] == "window" and command[2] == "--sub-layer":
            next(window for window in self.windows if str(window["id"]) == command[1])["sub-layer"] = command[3]
        elif command[:2] == ["rule", "--add"]:
            if self.fail_apply:
                return subprocess.CompletedProcess(argv, 1, "", "rule denied")
            record = dict(value.split("=", 1) for value in command[2:])
            if "manage" in record:
                record["manage"] = record["manage"] == "on"
            self.rules = [rule for rule in self.rules if rule["label"] != record["label"]] + [record]
        elif command[0] == "space" and command[2] == "--layout":
            if self.fail_apply:
                return subprocess.CompletedProcess(argv, 1, "", "layout denied")
            if not self.ignore_apply:
                next(space for space in self.spaces if str(space["index"]) == command[1])["type"] = command[3]
        elif command[:2] == ["config", "--space"] and command[3] == "layout":
            if self.fail_apply:
                return subprocess.CompletedProcess(argv, 1, "", "layout denied")
            if not self.ignore_apply:
                self.pinned_spaces.add(command[2])
                next(space for space in self.spaces if str(space["index"]) == command[2])["type"] = command[4]
        elif command[:2] == ["config", "layout"]:
            for space in self.spaces:
                if str(space["index"]) not in self.pinned_spaces:
                    space["type"] = command[2]
        else:
            self.fail(f"unexpected command: {command}")
        return subprocess.CompletedProcess(argv, 0, result, "")

    def restore(self, state, rules_only=False, dry_run=False, startup=False):
        self.path.write_text(json.dumps(state))
        before = self.path.read_bytes()
        args = argparse.Namespace(state_file=str(self.path), yabai_bin="fake-yabai", rules_only=rules_only, dry_run=dry_run, startup=startup)
        with patch.object(yabai_restore.subprocess, "run", side_effect=self.run_yabai), contextlib.redirect_stdout(io.StringIO()) as output, contextlib.redirect_stderr(io.StringIO()) as errors:
            yabai_restore.restore(args)
        self.assertEqual(self.path.read_bytes(), before)
        return output.getvalue(), errors.getvalue()

    def restack(self, dry_run=False):
        args = argparse.Namespace(yabai_bin="fake-yabai", dry_run=dry_run)
        with patch.object(yabai_restore.subprocess, "run", side_effect=self.run_yabai), contextlib.redirect_stdout(io.StringIO()) as output, contextlib.redirect_stderr(io.StringIO()) as errors:
            yabai_restore.restack(args)
        return output.getvalue(), errors.getvalue()

    def app_state(self):
        return {"space_modes": {"1": "float"}, "window_defaults": {"apps": {
            "Preview": {"mode": "tile", "rule_label": "barista-default-preview", "app_regex": "^Preview$", "sub_layer": "normal"}
        }}}

    def mutations(self):
        return [command for command in self.calls if command[0] in ("space", "config") or command[:2] == ["rule", "--add"]]

    def test_float_and_app_rules_restore_without_touching_base_rules(self):
        original_rule = copy.deepcopy(self.rules[0])
        output, notes = self.restore(self.app_state())
        self.assertEqual(self.spaces[0]["type"], "float")
        self.assertEqual(self.rules[0], original_rule)
        self.assertEqual(self.rules[-1]["label"], "barista-default-preview")
        self.assertIn("Restored 2", output)
        self.assertIn("legacy preference follows its index", notes)

    def test_app_levels_restore_after_defaults_as_their_sub_layers(self):
        state = self.app_state()
        state["window_levels"] = {"Cursor": {"level": "raised"}, "Yaze": {"level": "top"}}
        self.restore(state, rules_only=True)
        rules = {rule["label"]: rule for rule in self.rules}
        self.assertNotIn("sub-layer", rules["barista-default-preview"], "floating never pins stacking")
        self.assertEqual(rules["barista-level-cursor"], {"label": "barista-level-cursor", "app": "^Cursor$",
                                                         "sub-layer": "normal"})
        self.assertEqual(rules["barista-level-yaze"]["sub-layer"], "above")
        labels = [rule["label"] for rule in self.rules]
        self.assertLess(labels.index("barista-default-preview"), labels.index("barista-level-cursor"))

    def test_restack_moves_open_windows_to_their_rules_layer(self):
        self.rules = [{"label": "barista-level-base", "app": ".*", "sub-layer": "below"},
                      {"label": "", "app": "^System Settings$", "title": "", "sub-layer": "normal"},
                      {"label": "", "app": "^Safari$", "title": "^Settings$", "sub-layer": "normal"},
                      {"label": "", "app": "^Finder$", "role": "AXWindow", "subrole": "AXDialog", "sub-layer": "above"}]
        window = lambda id, app, layer, **extra: {"id": id, "app": app, "title": extra.get("title", ""),
                                                  "role": "AXWindow", "subrole": extra.get("subrole", "AXStandardWindow"),
                                                  "sub-layer": layer}
        self.windows = [window(1, "Cursor", "normal"), window(2, "System Settings", "below"),
                        window(3, "Safari", "normal", title="Start Page"), window(4, "Ghostty", "above"),
                        window(5, "Cursor", "normal", subrole="AXDialog"), window(6, "Finder", "below")]
        planned, _ = self.restack(dry_run=True)
        self.assertEqual(len(json.loads(planned)["restack"]), 3)
        self.assertFalse(any(command[0] == "window" for command in self.calls))
        output, _ = self.restack()
        layers = {window["id"]: window["sub-layer"] for window in self.windows}
        self.assertEqual(layers, {1: "below", 2: "normal", 3: "below", 4: "above", 5: "normal", 6: "below"})
        self.assertIn("Restacked 3 open window(s)", output)

    def test_restack_skips_a_window_that_closed_and_moves_the_rest(self):
        self.rules = [{"label": "barista-level-base", "app": ".*", "sub-layer": "below"}]
        self.windows = [{"id": id, "app": "Cursor", "title": "", "subrole": "AXStandardWindow", "sub-layer": "normal"}
                        for id in (1, 2)]
        run = self.run_yabai
        self.run_yabai = lambda argv, **kwargs: (subprocess.CompletedProcess(argv, 1, "", "could not locate window")
                                                 if argv[2:4] == ["window", "1"] else run(argv, **kwargs))
        output, errors = self.restack()
        self.assertEqual(self.windows[1]["sub-layer"], "below")
        self.assertIn("Restacked 1 open window(s)", output)
        self.assertIn("Could not restack window(s): 1", errors)

    def test_restack_rejects_an_invalid_window_list(self):
        self.windows = {"not": "a list"}
        with self.assertRaisesRegex(ValueError, "invalid live Yabai windows"):
            self.restack()

    def test_restore_leaves_open_windows_alone(self):
        self.windows = [{"id": 1, "app": "Yaze", "title": "", "subrole": "AXStandardWindow", "sub-layer": "normal"}]
        self.restore(self.app_state(), startup=True)
        self.assertNotIn(["query", "--windows"], self.calls)

    def test_invalid_app_level_fails_before_any_mutation(self):
        with self.assertRaisesRegex(ValueError, "invalid saved app level"):
            self.restore({"window_levels": {"Cursor": {"level": "sideways"}}})
        self.assertEqual(self.mutations(), [])

    def test_rules_only_never_queries_or_changes_spaces(self):
        self.restore(self.app_state(), rules_only=True)
        self.assertFalse(any("space" in command or "--spaces" in command for command in self.calls))
        self.assertEqual(self.spaces[0]["type"], "bsp")

    def test_dry_run_lists_changes_without_applying(self):
        output, _ = self.restore(self.app_state(), dry_run=True)
        self.assertEqual(len(json.loads(output)["actions"]), 2)
        self.assertEqual(self.mutations(), [])

    def test_startup_pins_matching_manual_before_global_default(self):
        for space in self.spaces:
            space["type"] = "float"  # A fresh Yabai process starts with float.
        state = self.app_state()
        state.update({"space_mode_uuids": {"1": "A"}, "space_modes_by_uuid": {"A": "float"}})
        self.restore(state, startup=True)
        self.assertEqual(self.pinned_spaces, {"1"})
        mutations = self.mutations()
        self.assertEqual(mutations[0][:2], ["rule", "--add"])
        self.assertEqual(mutations[1], ["config", "--space", "1", "layout", "float"])
        self.run_yabai(["fake-yabai", "-m", "config", "layout", "bsp"])
        self.assertEqual(self.spaces[0]["type"], "float")
        self.assertEqual(self.spaces[1]["type"], "bsp")

    def test_startup_pins_every_saved_layout_even_when_already_matching(self):
        self.restore({"space_modes": {"1": "bsp", "2": "stack"}}, startup=True)
        self.assertEqual(self.pinned_spaces, {"1", "2"})
        self.run_yabai(["fake-yabai", "-m", "config", "layout", "bsp"])
        self.assertEqual(self.spaces[1]["type"], "stack")

    def test_ordinary_restore_skips_matching_layout(self):
        output, _ = self.restore({"space_modes": {"1": "bsp"}}, dry_run=True)
        self.assertEqual(json.loads(output)["actions"], [])
        self.assertEqual(self.mutations(), [])

    def test_startup_rules_only_never_pins_spaces(self):
        self.restore(self.app_state(), startup=True, rules_only=True)
        self.assertFalse(any(command[0] in ("config", "space") or "--spaces" in command for command in self.calls))
        self.assertEqual(self.pinned_spaces, set())

    def test_startup_pin_checks_identity_and_reports_layout_failure(self):
        self.changed_identity = True
        with self.assertRaisesRegex(ValueError, "changed identity"):
            self.restore({"space_modes": {"1": "bsp"}}, startup=True)
        self.assertEqual(self.pinned_spaces, set())
        self.changed_identity = False
        self.ignore_apply = True
        with self.assertRaisesRegex(ValueError, "layout could not be verified"):
            self.restore({"space_modes": {"1": "float"}}, startup=True)

    def test_empty_lua_maps_are_accepted(self):
        self.restore({"space_modes": [], "space_modes_by_uuid": [], "space_mode_uuids": [], "window_defaults": {"apps": []}})
        self.assertEqual(self.calls, [])

    def test_invalid_saved_value_fails_before_any_mutation(self):
        state = self.app_state()
        state["space_modes"]["2"] = "bad"
        with self.assertRaisesRegex(ValueError, "invalid saved space"):
            self.restore(state)
        self.assertEqual(self.calls, [])

    def test_rule_label_collision_does_not_replace_another_app(self):
        self.rules.append({"label": "barista-default-preview", "app": "^Other$"})
        with self.assertRaisesRegex(ValueError, "belongs to another app"):
            self.restore(self.app_state())
        self.assertEqual(self.mutations(), [])

    def test_command_failure_is_reported(self):
        self.fail_apply = True
        with self.assertRaisesRegex(ValueError, "0 verified change.*layout denied"):
            self.restore(self.app_state())

    def test_unverified_layout_is_reported(self):
        self.ignore_apply = True
        with self.assertRaisesRegex(ValueError, "layout could not be verified"):
            self.restore({"space_modes": {"1": "float"}})

    def test_space_identity_change_is_rejected_before_mutation(self):
        self.changed_identity = True
        with self.assertRaisesRegex(ValueError, "changed identity"):
            self.restore({"space_modes": {"1": "float"}})
        self.assertEqual(self.mutations(), [])

    def test_uuid_preference_follows_space_after_reorder(self):
        self.restore({"space_modes": {"1": "float"}, "space_mode_uuids": {"1": "B"}, "space_modes_by_uuid": {"B": "float"}})
        self.assertEqual(self.spaces[0]["type"], "bsp")
        self.assertEqual(self.spaces[1]["type"], "float")
        self.assertEqual(self.mutations(), [["space", "2", "--layout", "float"]])

    def test_missing_uuid_never_falls_back_to_its_old_index(self):
        _, notes = self.restore({"space_modes": {"1": "float"}, "space_mode_uuids": {"1": "GONE"}, "space_modes_by_uuid": {"GONE": "float"}})
        self.assertEqual(self.mutations(), [])
        self.assertIn("old index was not used", notes)

    def test_uuid_preference_wins_over_conflicting_legacy_index(self):
        self.restore({"space_modes": {"2": "stack"}, "space_modes_by_uuid": {"B": "float"}})
        self.assertEqual(self.mutations(), [["space", "2", "--layout", "float"]])

    def test_writer_preserves_choices_after_reorder_and_new_save(self):
        self.path.write_text('{"unrelated":true}')
        yabai_state.update(self.path, "space-mode", ["1", "float", "A"])
        yabai_state.update(self.path, "space-mode", ["2", "stack", "B"])
        yabai_state.update(self.path, "space-mode", ["1", "bsp", "B"])
        state = json.loads(self.path.read_text())
        self.assertEqual(state["space_modes_by_uuid"], {"A": "float", "B": "bsp"})
        self.assertTrue(state["unrelated"])
        self.spaces[0]["uuid"], self.spaces[1]["uuid"] = "B", "A"
        self.restore(state)
        self.assertEqual(self.mutations(), [["space", "2", "--layout", "float"]])

    def test_shortcut_writer_preserves_other_fields_and_accepts_empty_maps(self):
        self.path.write_text('{"toggles":[],"unrelated":true}')
        yabai_state.update(self.path, "shortcuts-check", [])
        self.assertEqual(json.loads(self.path.read_text())["toggles"], [])
        yabai_state.update(self.path, "shortcuts-state", ["false"])
        self.assertEqual(json.loads(self.path.read_text()), {"toggles": {"yabai_shortcuts": False}, "unrelated": True})
        with self.assertRaisesRegex(ValueError, "true or false"):
            yabai_state.update(self.path, "shortcuts-state", ["maybe"])

    def test_space_prune_removes_orphans_and_remaps_live_uuids(self):
        self.path.write_text(json.dumps({
            "space_modes": {"1": "bsp", "2": "float", "9": "stack"},
            "space_mode_uuids": {"1": "DEAD-1", "2": "LIVE-B", "9": "DEAD-9"},
            "space_modes_by_uuid": {"DEAD-1": "bsp", "LIVE-B": "float", "DEAD-9": "stack"},
        }))
        live_payload = json.dumps([
            {"index": 1, "uuid": "LIVE-A"},
            {"index": 3, "uuid": "LIVE-B"},
        ])
        dry = yabai_state.update(self.path, "space-prune-check", [live_payload])
        self.assertEqual(dry["pruned_uuids"], ["DEAD-1", "DEAD-9"])
        self.assertEqual(dry["remapped_indices"], {"3": "float"})
        self.assertIn("DEAD-1", json.loads(self.path.read_text())["space_modes_by_uuid"])

        applied = yabai_state.update(self.path, "space-prune", [live_payload])
        self.assertEqual(applied["active_modes"], {"3": "float"})
        saved = json.loads(self.path.read_text())
        self.assertEqual(saved["space_modes"], {"3": "float"})
        self.assertEqual(saved["space_mode_uuids"], {"3": "LIVE-B"})
        self.assertEqual(saved["space_modes_by_uuid"], {"LIVE-B": "float"})

    def test_space_lock_and_policy_validators(self):
        self.path.write_text("{}")
        res = yabai_state.update(self.path, "space-lock", ["1"])
        self.assertEqual(res["locked_spaces"], ["1"])
        res = yabai_state.update(self.path, "space-unlock", ["1"])
        self.assertEqual(res["locked_spaces"], [])
        yabai_state.update(self.path, "space-policy", ["max_spaces_per_display", "6"])
        yabai_state.update(self.path, "space-policy", ["destroy_non_empty_policy", "refuse"])
        yabai_state.update(self.path, "space-policy", ["new_space_layout", "bsp"])
        yabai_state.update(self.path, "space-policy", ["window_move_policy", "adopt_destination"])
        spaces_cfg = json.loads(self.path.read_text())["spaces"]
        self.assertEqual(spaces_cfg["max_spaces_per_display"], 6)
        self.assertEqual(spaces_cfg["destroy_non_empty_policy"], "refuse")
        self.assertEqual(spaces_cfg["new_space_layout"], "bsp")
        self.assertEqual(spaces_cfg["window_move_policy"], "adopt_destination")
        with self.assertRaisesRegex(ValueError, "max_spaces_per_display"):
            yabai_state.update(self.path, "space-policy", ["max_spaces_per_display", "99"])
        with self.assertRaisesRegex(ValueError, "destroy_non_empty_policy"):
            yabai_state.update(self.path, "space-policy", ["destroy_non_empty_policy", "burn"])

    def test_feature_toggles_and_workflow_policies(self):
        self.path.write_text("{}")
        checked = yabai_state.update(self.path, "feature-check", [])
        self.assertEqual(checked["toggles"], {"stack_indicator": True})

        res = yabai_state.update(self.path, "feature-toggle", ["stack_indicator", "off"])
        self.assertEqual(res, {"stack_indicator": False})
        res = yabai_state.update(self.path, "feature-toggle", ["stack_indicator", "toggle"])
        self.assertEqual(res, {"stack_indicator": True})

        wf_defaults = yabai_state.update(self.path, "workflow-check", [])
        self.assertEqual(wf_defaults["workflow"]["scratchpad"]["width_pct"], 75)
        self.assertEqual(wf_defaults["workflow"]["files"]["picker"], "auto")

        yabai_state.update(self.path, "workflow-policy", ["scratchpad.width_pct", "85"])
        yabai_state.update(self.path, "workflow-policy", ["files.picker", "yazi"])
        saved = json.loads(self.path.read_text())["workflow"]
        self.assertEqual(saved["scratchpad"]["width_pct"], 85)
        self.assertEqual(saved["files"]["picker"], "yazi")

        with self.assertRaisesRegex(ValueError, "unsupported feature toggle"):
            yabai_state.update(self.path, "feature-toggle", ["yabai_shortcuts", "off"])
        with self.assertRaisesRegex(ValueError, "scratchpad.width_pct"):
            yabai_state.update(self.path, "workflow-policy", ["scratchpad.width_pct", "10"])


if __name__ == "__main__":
    unittest.main()
