#!/usr/bin/env python3
"""Regression tests for lossless TUI state persistence."""

from __future__ import annotations

import copy
import hashlib
import json
import os
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from tui.config import (  # noqa: E402
    BaristaConfig,
    build_config_patch,
    load_config,
    reload_sketchybar,
    restore_file_snapshot,
    save_config,
    save_json_document,
)
from tui import config as config_module  # noqa: E402


def lua_shaped_state() -> dict[str, object]:
    """Return a representative state document written by the Lua runtime."""
    return {
        "_version": 2,
        "widget_colors": [],
        "widgets": {
            "clock": True,
            "battery": True,
            "volume": True,
            "network": True,
            "system_info": True,
            "task_focus": False,
            "future_widget": "keep",
        },
        "appearance": {
            "theme": "default",
            "bar_height": 28,
            "hover_animation_duration": 8,
            "future_appearance": {"keep": True},
        },
        "icons": {
            "apple": "",
            "wifi_off": "offline",
            "future_icon": "keep",
        },
        "system_info_items": {
            "cpu": False,
            "mem": True,
            "disk": True,
            "net": True,
            "swap": True,
            "uptime": True,
            "procs": True,
            "docs": True,
            "actions": False,
            "future_metric": {"keep": "nested"},
        },
        "integrations": {
            "control_center": {
                "enabled": False,
                "item_name": "control_center",
                "future_option": "keep",
            }
        },
        "debug": {"popup_debug": False},
        "future_top_level": {"keep": [1, 2, 3]},
    }


class TuiConfigPersistenceTests(unittest.TestCase):
    def setUp(self) -> None:
        self._tempdir = tempfile.TemporaryDirectory()
        self.addCleanup(self._tempdir.cleanup)
        self.root = Path(self._tempdir.name)
        self.state_file = self.root / "explicit" / "state.json"

    def write_json(
        self,
        data: dict[str, object],
        path: Path | None = None,
    ) -> Path:
        target = path or self.state_file
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(
            json.dumps(data, indent=2, ensure_ascii=False),
            encoding="utf-8",
        )
        return target

    @staticmethod
    def read_json(path: Path) -> dict[str, object]:
        return json.loads(path.read_text(encoding="utf-8"))

    def test_current_lua_state_and_unknown_keys_round_trip_exactly(self) -> None:
        original = lua_shaped_state()
        self.write_json(original)

        config = load_config(state_file=self.state_file)

        self.assertFalse(config.system_info_items.cpu)
        self.assertTrue(config.system_info_items.swap)
        self.assertTrue(config.system_info_items.uptime)
        self.assertTrue(config.system_info_items.procs)
        self.assertFalse(config.system_info_items.actions)
        self.assertEqual(
            config.model_dump()["system_info_items"]["future_metric"],
            {"keep": "nested"},
        )
        self.assertEqual(
            config.model_dump()["future_top_level"],
            {"keep": [1, 2, 3]},
        )

        save_config(config, updates={}, state_file=self.state_file)

        self.assertEqual(self.read_json(self.state_file), original)

    def test_build_patch_and_targeted_save_change_only_one_key(self) -> None:
        original = lua_shaped_state()
        self.write_json(original)
        before = load_config(state_file=self.state_file)
        after = before.model_copy(deep=True)
        after.system_info_items.cpu = True

        patch = build_config_patch(before.model_dump(), after.model_dump())

        self.assertEqual(patch, {"system_info_items": {"cpu": True}})
        save_config(after, updates=patch, state_file=self.state_file)

        expected = copy.deepcopy(original)
        expected["system_info_items"]["cpu"] = True
        self.assertEqual(self.read_json(self.state_file), expected)

    def test_external_key_written_before_save_survives(self) -> None:
        original = lua_shaped_state()
        self.write_json(original)
        before = load_config(state_file=self.state_file)
        after = before.model_copy(deep=True)
        after.system_info_items.cpu = True
        patch = build_config_patch(before.model_dump(), after.model_dump())

        concurrent = copy.deepcopy(original)
        concurrent["external_agent"] = {"arrived": True}
        concurrent["system_info_items"]["mem"] = False
        self.write_json(concurrent)

        save_config(after, updates=patch, state_file=self.state_file)

        expected = copy.deepcopy(concurrent)
        expected["system_info_items"]["cpu"] = True
        self.assertEqual(self.read_json(self.state_file), expected)

    def test_simultaneous_tui_saves_serialize_the_full_merge_cycle(self) -> None:
        self.write_json({"_version": 2})
        original_write = config_module._atomic_write_json
        active_writes = 0
        maximum_active_writes = 0
        counter_lock = threading.Lock()
        start = threading.Barrier(3)
        errors: list[BaseException] = []

        def slow_write(
            path: Path,
            data: dict[str, object],
            *,
            expected_token: str | None,
        ) -> bool:
            nonlocal active_writes, maximum_active_writes
            with counter_lock:
                active_writes += 1
                maximum_active_writes = max(maximum_active_writes, active_writes)
            try:
                time.sleep(0.05)
                return original_write(
                    path,
                    data,
                    expected_token=expected_token,
                )
            finally:
                with counter_lock:
                    active_writes -= 1

        def save_key(key: str) -> None:
            try:
                start.wait()
                save_config(
                    BaristaConfig(),
                    updates={key: {"saved": True}},
                    state_file=self.state_file,
                )
            except BaseException as exc:
                errors.append(exc)

        with mock.patch.object(config_module, "_atomic_write_json", slow_write):
            threads = [
                threading.Thread(target=save_key, args=("writer_one",)),
                threading.Thread(target=save_key, args=("writer_two",)),
            ]
            for thread in threads:
                thread.start()
            start.wait()
            for thread in threads:
                thread.join(timeout=5)

        self.assertFalse(any(thread.is_alive() for thread in threads))
        self.assertEqual(errors, [])
        self.assertEqual(maximum_active_writes, 1)
        saved = self.read_json(self.state_file)
        self.assertEqual(saved["writer_one"], {"saved": True})
        self.assertEqual(saved["writer_two"], {"saved": True})

    def test_noncooperating_writer_change_triggers_merge_retry(self) -> None:
        original = lua_shaped_state()
        self.write_json(original)
        original_write = config_module._atomic_write_json
        injected = False

        def inject_external_write(
            path: Path,
            data: dict[str, object],
            *,
            expected_token: str | None,
        ) -> bool:
            nonlocal injected
            if not injected:
                concurrent = self.read_json(path)
                concurrent["external_during_save"] = {"keep": True}
                self.write_json(concurrent, path)
                injected = True
            return original_write(
                path,
                data,
                expected_token=expected_token,
            )

        with mock.patch.object(
            config_module,
            "_atomic_write_json",
            inject_external_write,
        ):
            save_config(
                BaristaConfig(),
                updates={"system_info_items": {"cpu": True}},
                state_file=self.state_file,
            )

        saved = self.read_json(self.state_file)
        self.assertTrue(injected)
        self.assertEqual(saved["external_during_save"], {"keep": True})
        self.assertTrue(saved["system_info_items"]["cpu"])

    def test_derived_rollback_token_never_adopts_external_post_write(self) -> None:
        derived_file = self.root / "work_apps.json"
        original_content = b'[{"id":"old"}]\n'
        external_content = b'[{"id":"external"}]\n'
        derived_file.write_bytes(original_content)
        payload = [{"id": "managed"}]
        original_write = config_module._atomic_write_bytes

        def inject_post_replace_write(
            path: Path,
            data: bytes,
            *,
            expected_token: str | None,
        ) -> bool:
            wrote = original_write(
                path,
                data,
                expected_token=expected_token,
            )
            if wrote:
                path.write_bytes(external_content)
            return wrote

        with mock.patch.object(
            config_module,
            "_atomic_write_bytes",
            inject_post_replace_write,
        ):
            written_token = save_json_document(derived_file, payload)

        expected_content = (
            json.dumps(payload, indent=2, ensure_ascii=False) + "\n"
        ).encode("utf-8")
        self.assertEqual(
            written_token,
            hashlib.sha256(expected_content).hexdigest(),
        )
        self.assertFalse(
            restore_file_snapshot(
                derived_file,
                original_content,
                expected_token=written_token,
            )
        )
        self.assertEqual(derived_file.read_bytes(), external_content)

    def test_nested_lua_empty_integration_table_loads_losslessly(self) -> None:
        original = lua_shaped_state()
        original["integrations"]["yaze"] = []
        self.write_json(original)

        config = load_config(state_file=self.state_file)
        self.assertFalse(config.integrations.yaze.enabled)
        save_config(config, updates={}, state_file=self.state_file)

        self.assertEqual(self.read_json(self.state_file), original)

    def test_missing_form_value_does_not_delete_existing_state(self) -> None:
        before = {
            "appearance": {
                "bar_height": 28,
                "theme": "default",
            }
        }
        after = {"appearance": {"theme": "default"}}

        self.assertEqual(build_config_patch(before, after), {})

    def test_invalid_json_fails_closed_and_preserves_original_bytes(self) -> None:
        self.state_file.parent.mkdir(parents=True, exist_ok=True)
        invalid = b'{"system_info_items":'
        self.state_file.write_bytes(invalid)

        with self.assertRaises(ValueError):
            load_config(state_file=self.state_file)
        self.assertEqual(self.state_file.read_bytes(), invalid)

        with self.assertRaises(ValueError):
            save_config(
                BaristaConfig(),
                updates={"system_info_items": {"cpu": True}},
                state_file=self.state_file,
            )
        self.assertEqual(self.state_file.read_bytes(), invalid)

    def test_explicit_state_path_isolated_from_environment_default(self) -> None:
        explicit = lua_shaped_state()
        decoy = lua_shaped_state()
        decoy["future_top_level"] = {"decoy": True}
        self.write_json(explicit, self.state_file)

        default_dir = self.root / "environment-default"
        default_file = self.write_json(decoy, default_dir / "state.json")
        default_bytes = default_file.read_bytes()

        with mock.patch.dict(
            os.environ,
            {"BARISTA_CONFIG_DIR": str(default_dir)},
            clear=False,
        ):
            before = load_config(state_file=self.state_file)
            after = before.model_copy(deep=True)
            after.system_info_items.cpu = True
            patch = build_config_patch(before.model_dump(), after.model_dump())
            save_config(after, updates=patch, state_file=self.state_file)

        self.assertTrue(
            self.read_json(self.state_file)["system_info_items"]["cpu"]
        )
        self.assertEqual(default_file.read_bytes(), default_bytes)

    def test_new_state_document_uses_schema_version_two(self) -> None:
        new_state = self.root / "new" / "state.json"

        config = load_config(state_file=new_state)

        self.assertFalse(config.system_info_items.cpu)
        self.assertTrue(config.system_info_items.swap)
        self.assertTrue(config.system_info_items.uptime)
        self.assertTrue(config.system_info_items.procs)

        save_config(config, updates={}, state_file=new_state)

        saved = self.read_json(new_state)
        self.assertEqual(saved["_version"], 2)

    def test_reload_uses_supported_helper_in_requested_config_dir(self) -> None:
        config_dir = self.root / "runtime"
        helper = config_dir / "plugins" / "reload_sketchybar.sh"
        helper.parent.mkdir(parents=True, exist_ok=True)
        helper.write_text("#!/bin/bash\nexit 0\n", encoding="utf-8")
        helper.chmod(0o755)

        completed = subprocess.CompletedProcess([str(helper)], 0)
        with mock.patch("subprocess.run", return_value=completed) as run:
            self.assertTrue(reload_sketchybar(config_dir=config_dir))

        run.assert_called_once()
        command = run.call_args.args[0]
        resolved_dir = config_dir.resolve()
        self.assertEqual(
            command,
            [str(resolved_dir / "plugins" / "reload_sketchybar.sh")],
        )
        self.assertNotIn("--reload", command)
        self.assertTrue(run.call_args.kwargs["check"])
        environment = run.call_args.kwargs["env"]
        self.assertEqual(environment["CONFIG_DIR"], str(resolved_dir))
        self.assertEqual(environment["BARISTA_CONFIG_DIR"], str(resolved_dir))

    def test_reload_reports_supported_helper_failure(self) -> None:
        config_dir = self.root / "runtime-failure"
        helper = config_dir / "plugins" / "reload_sketchybar.sh"
        helper.parent.mkdir(parents=True, exist_ok=True)
        helper.write_text("#!/bin/bash\nexit 1\n", encoding="utf-8")
        helper.chmod(0o755)

        failure = subprocess.CalledProcessError(1, [str(helper)])
        with mock.patch("subprocess.run", side_effect=failure):
            self.assertFalse(reload_sketchybar(config_dir=config_dir))


if __name__ == "__main__":
    unittest.main()
