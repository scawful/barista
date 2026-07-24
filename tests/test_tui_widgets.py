#!/usr/bin/env python3
"""Regression tests for the Widgets tab system-info controls."""

from __future__ import annotations

import copy
import json
import os
import signal
import sys
import tempfile
import threading
import time
import unittest
from pathlib import Path
from unittest import mock

from textual.app import App, ComposeResult
from textual.containers import VerticalScroll
from textual.widgets import Input, Switch, TextArea

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from tui.config import (  # noqa: E402
    BaristaConfig,
    save_config,
    update_json_array_document,
    validate_config_document,
)
from tui.app import BaristaApp  # noqa: E402
from tui.screens.widgets import WidgetToggle, WidgetsTab  # noqa: E402


SYSTEM_INFO_KEYS = (
    "cpu",
    "mem",
    "disk",
    "net",
    "swap",
    "uptime",
    "procs",
    "actions",
)

MIXED_SYSTEM_INFO_VALUES = {
    "cpu": False,
    "mem": True,
    "disk": False,
    "net": True,
    "swap": False,
    "uptime": True,
    "procs": False,
    "actions": True,
}


class WidgetsHarness(App[None]):
    """Minimal in-memory app for mounting a WidgetsTab."""

    def __init__(self, config: BaristaConfig) -> None:
        super().__init__()
        self.config = config

    def compose(self) -> ComposeResult:
        yield WidgetsTab(self.config)


class WidgetsTabTests(unittest.IsolatedAsyncioTestCase):
    async def test_system_info_controls_are_complete_ordered_and_lossless(self) -> None:
        config = BaristaConfig.model_validate(
            {
                "system_info_items": {
                    **MIXED_SYSTEM_INFO_VALUES,
                    "docs": False,
                }
            }
        )
        app = WidgetsHarness(config)

        async with app.run_test(size=(120, 60)) as pilot:
            await pilot.pause()
            tab = app.query_one(WidgetsTab)
            system_info_toggles = [
                toggle
                for toggle in tab.query(WidgetToggle)
                if toggle.widget_id.startswith("sysinfo_")
            ]
            rendered_keys = tuple(
                toggle.widget_id.removeprefix("sysinfo_")
                for toggle in system_info_toggles
            )

            self.assertEqual(rendered_keys, SYSTEM_INFO_KEYS)
            self.assertFalse(tab.query("#sysinfo_docs"))
            self.assertEqual(
                {
                    key: tab.query_one(f"#sysinfo_{key}", Switch).value
                    for key in SYSTEM_INFO_KEYS
                },
                MIXED_SYSTEM_INFO_VALUES,
            )
            self.assertEqual(
                tab.get_values()["system_info_items"],
                MIXED_SYSTEM_INFO_VALUES,
            )

    async def test_actions_control_is_focusable_and_scrolled_into_view(self) -> None:
        app = WidgetsHarness(BaristaConfig())

        async with app.run_test(size=(80, 24)) as pilot:
            await pilot.pause()
            tab = app.query_one(WidgetsTab)
            self.assertIsInstance(tab, VerticalScroll)
            self.assertGreater(tab.max_scroll_y, 0)

            for _ in range(20):
                if app.focused is not None and app.focused.id == "sysinfo_actions":
                    break
                await pilot.press("tab")

            await pilot.pause()
            self.assertIsNotNone(app.focused)
            self.assertEqual(app.focused.id, "sysinfo_actions")
            self.assertGreater(tab.scroll_y, 0)


class BaristaAppPersistenceTests(unittest.IsolatedAsyncioTestCase):
    async def test_explicit_config_save_is_lossless_and_isolated(self) -> None:
        with tempfile.TemporaryDirectory() as tempdir:
            root = Path(tempdir)
            explicit_state = root / "explicit" / "state.json"
            default_state = root / "default" / "state.json"
            original = {
                "_version": 2,
                "widget_colors": [],
                "system_info_items": {
                    **MIXED_SYSTEM_INFO_VALUES,
                    "docs": False,
                },
                "future": {"keep": ["external", "state"]},
            }
            decoy = {"_version": 2, "decoy": True}
            explicit_state.parent.mkdir(parents=True)
            default_state.parent.mkdir(parents=True)
            explicit_state.write_text(json.dumps(original), encoding="utf-8")
            default_state.write_text(json.dumps(decoy), encoding="utf-8")
            default_bytes = default_state.read_bytes()

            with mock.patch.dict(
                os.environ,
                {"BARISTA_CONFIG_DIR": str(default_state.parent)},
                clear=False,
            ):
                app = BaristaApp(config_path=str(explicit_state))
                async with app.run_test(size=(120, 50)) as pilot:
                    await pilot.pause()
                    self.assertEqual(app.state_file, explicit_state)
                    self.assertTrue(app.query_one("#raw_json", TextArea).read_only)
                    app.query_one("#sysinfo_cpu", Switch).value = True
                    self.assertTrue(app.action_save())

            expected = copy.deepcopy(original)
            expected["system_info_items"]["cpu"] = True
            self.assertEqual(
                json.loads(explicit_state.read_text(encoding="utf-8")),
                expected,
            )
            self.assertEqual(default_state.read_bytes(), default_bytes)

    async def test_alternate_config_basename_is_save_only(self) -> None:
        with tempfile.TemporaryDirectory() as tempdir:
            config_file = Path(tempdir) / "alternate.json"
            config_file.write_text('{"_version": 2}', encoding="utf-8")
            app = BaristaApp(config_path=str(config_file))

            async with app.run_test(size=(120, 50)) as pilot:
                await pilot.pause()
                with mock.patch("tui.app.reload_sketchybar") as reload:
                    app.action_save_reload()
                reload.assert_not_called()

            self.assertEqual(
                json.loads(config_file.read_text(encoding="utf-8")),
                {"_version": 2},
            )

    async def test_failed_work_apps_sync_keeps_save_retryable(self) -> None:
        with tempfile.TemporaryDirectory() as tempdir:
            root = Path(tempdir)
            state_file = root / "state.json"
            state_file.write_text(
                json.dumps(
                    {
                        "_version": 2,
                        "menus": {
                            "work": {
                                "apps_file": "data/work_apps.local.json",
                                "workspace_domain": "old.example",
                            }
                        },
                    }
                ),
                encoding="utf-8",
            )
            app = BaristaApp(config_path=str(state_file))

            async with app.run_test(size=(120, 50)) as pilot:
                await pilot.pause()
                initial_values = copy.deepcopy(app._initial_values)
                app.query_one("#work_workspace_domain", Input).value = "new.example"
                with mock.patch(
                    "tui.app.update_json_array_document",
                    side_effect=OSError("disk full"),
                ):
                    self.assertFalse(app.action_save())

                self.assertEqual(app._initial_values, initial_values)
                app.query_one("#work_workspace_domain", Input).value = "old.example"
                with mock.patch(
                    "tui.app.update_json_array_document"
                ) as write_apps:
                    self.assertTrue(app.action_save())
                write_apps.assert_not_called()

            saved = json.loads(state_file.read_text(encoding="utf-8"))
            self.assertEqual(
                saved["menus"]["work"]["workspace_domain"],
                "old.example",
            )

    async def test_work_apps_save_preserves_unrelated_custom_rows(self) -> None:
        with tempfile.TemporaryDirectory() as tempdir:
            root = Path(tempdir)
            state_file = root / "state.json"
            apps_file = root / "data" / "work_apps.local.json"
            personal_row = {
                "id": "personal_keep",
                "label": "Personal Tool",
                "section": "personal",
                "command": "open /tmp/personal",
            }
            state_file.write_text(
                json.dumps(
                    {
                        "_version": 2,
                        "menus": {
                            "apple": {
                                "custom": [
                                    personal_row,
                                    {
                                        "id": "work_google_gmail",
                                        "label": "Stale Duplicate",
                                        "url": "https://old.example/",
                                    },
                                ],
                                "sections": {
                                    "work": {
                                        "label": "Company Links",
                                        "order": 91,
                                        "future": "keep",
                                    }
                                },
                            },
                            "work": {
                                "apps_file": "data/work_apps.local.json",
                                "workspace_domain": "old.example",
                            },
                        },
                    }
                ),
                encoding="utf-8",
            )
            apps_file.parent.mkdir(parents=True)
            apps_file.write_text(
                json.dumps(
                    [
                        {
                            "id": "company_portal",
                            "label": "Company Portal",
                            "url": "https://portal.example/",
                        },
                        {
                            "id": "work_google_old",
                            "label": "Stale Managed Row",
                        },
                    ]
                ),
                encoding="utf-8",
            )
            app = BaristaApp(config_path=str(state_file))

            async with app.run_test(size=(120, 50)) as pilot:
                await pilot.pause()
                app.query_one("#work_workspace_domain", Input).value = "new.example"
                self.assertTrue(app.action_save())

            saved = json.loads(state_file.read_text(encoding="utf-8"))
            self.assertEqual(saved["menus"]["apple"]["custom"], [personal_row])
            self.assertEqual(
                saved["menus"]["apple"]["sections"]["work"],
                {
                    "label": "Company Links",
                    "order": 91,
                    "future": "keep",
                },
            )
            self.assertEqual(len(saved["menus"]["work"]["google_apps"]), 7)
            apps = json.loads(
                apps_file.read_text(encoding="utf-8")
            )
            self.assertEqual(len(apps), 7)
            self.assertEqual(apps[0]["id"], "company_portal")
            self.assertFalse(
                any(app.get("id") == "work_google_old" for app in apps)
            )
            gmail = next(
                app for app in apps if app.get("id") == "work_google_gmail"
            )
            self.assertEqual(
                gmail["url"],
                "https://mail.google.com/a/new.example/",
            )
            self.assertEqual(saved["menus"]["work"]["google_apps"], apps)

    async def test_state_save_failure_rolls_back_work_apps_file(self) -> None:
        with tempfile.TemporaryDirectory() as tempdir:
            root = Path(tempdir)
            state_file = root / "state.json"
            apps_file = root / "data" / "work_apps.local.json"
            state_file.write_text(
                json.dumps(
                    {
                        "_version": 2,
                        "menus": {
                            "work": {
                                "apps_file": "data/work_apps.local.json",
                                "workspace_domain": "old.example",
                            }
                        },
                    }
                ),
                encoding="utf-8",
            )
            apps_file.parent.mkdir(parents=True)
            apps_file.write_text(
                '[{"id":"company_portal","label":"Keep exact bytes"}]',
                encoding="utf-8",
            )
            original_state = state_file.read_bytes()
            original_apps = apps_file.read_bytes()
            app = BaristaApp(config_path=str(state_file))

            async with app.run_test(size=(120, 50)) as pilot:
                await pilot.pause()
                app.query_one("#work_workspace_domain", Input).value = "new.example"
                with mock.patch(
                    "tui.app.save_config_if_unchanged",
                    side_effect=OSError("state write failed"),
                ):
                    self.assertFalse(app.action_save())

            self.assertEqual(state_file.read_bytes(), original_state)
            self.assertEqual(apps_file.read_bytes(), original_apps)

    async def test_invalid_latest_state_blocks_work_apps_transaction(self) -> None:
        with tempfile.TemporaryDirectory() as tempdir:
            root = Path(tempdir)
            state_file = root / "state.json"
            apps_file = root / "data" / "work_apps.local.json"
            state_file.write_text(
                json.dumps(
                    {
                        "_version": 2,
                        "appearance": {"bar_height": 28},
                        "menus": {
                            "work": {
                                "apps_file": "data/work_apps.local.json",
                                "workspace_domain": "old.example",
                            }
                        },
                    }
                ),
                encoding="utf-8",
            )
            apps_file.parent.mkdir(parents=True)
            apps_file.write_text(
                '[{"id":"company_portal"}]',
                encoding="utf-8",
            )
            original_apps = apps_file.read_bytes()
            app = BaristaApp(config_path=str(state_file))

            async with app.run_test(size=(120, 50)) as pilot:
                await pilot.pause()
                externally_invalid = json.loads(
                    state_file.read_text(encoding="utf-8")
                )
                externally_invalid["appearance"]["bar_height"] = 999
                state_file.write_text(
                    json.dumps(externally_invalid),
                    encoding="utf-8",
                )
                invalid_state_bytes = state_file.read_bytes()
                app.query_one("#work_workspace_domain", Input).value = "new.example"
                self.assertFalse(app.action_save())

            self.assertEqual(state_file.read_bytes(), invalid_state_bytes)
            self.assertEqual(apps_file.read_bytes(), original_apps)

    async def test_missing_apps_file_preserves_state_fallback_rows(self) -> None:
        with tempfile.TemporaryDirectory() as tempdir:
            root = Path(tempdir)
            state_file = root / "state.json"
            fallback_row = {
                "id": "company_portal",
                "label": "Company Portal",
                "url": "https://portal.example/",
            }
            state_file.write_text(
                json.dumps(
                    {
                        "_version": 2,
                        "menus": {
                            "work": {
                                "apps_file": "data/missing.json",
                                "workspace_domain": "old.example",
                                "google_apps": [
                                    {
                                        "id": "stale_at_mount",
                                        "label": "Must Not Win",
                                    }
                                ],
                            }
                        },
                    }
                ),
                encoding="utf-8",
            )
            app = BaristaApp(config_path=str(state_file))

            async with app.run_test(size=(120, 50)) as pilot:
                await pilot.pause()
                save_config(
                    BaristaConfig(),
                    updates={
                        "menus": {
                            "work": {"google_apps": [fallback_row]}
                        }
                    },
                    state_file=state_file,
                )
                app.query_one("#work_workspace_domain", Input).value = "new.example"
                self.assertTrue(app.action_save())

            apps = json.loads(
                (root / "data" / "missing.json").read_text(encoding="utf-8")
            )
            saved = json.loads(state_file.read_text(encoding="utf-8"))
            self.assertEqual(apps[0], fallback_row)
            self.assertEqual(len(apps), 7)
            self.assertEqual(saved["menus"]["work"]["google_apps"], apps)

    async def test_work_apps_file_cannot_alias_active_state(self) -> None:
        with tempfile.TemporaryDirectory() as tempdir:
            state_file = Path(tempdir) / "state.json"
            state_file.write_text(
                json.dumps(
                    {
                        "_version": 2,
                        "menus": {
                            "work": {
                                "apps_file": "state.json",
                                "workspace_domain": "old.example",
                            }
                        },
                    }
                ),
                encoding="utf-8",
            )
            original_bytes = state_file.read_bytes()
            app = BaristaApp(config_path=str(state_file))

            async with app.run_test(size=(120, 50)) as pilot:
                await pilot.pause()
                app.query_one("#work_workspace_domain", Input).value = "new.example"

                def timeout_handler(signum, frame):
                    raise TimeoutError("save deadlocked")

                previous_handler = signal.signal(signal.SIGALRM, timeout_handler)
                signal.setitimer(signal.ITIMER_REAL, 1.0)
                started = time.monotonic()
                try:
                    self.assertFalse(app.action_save())
                finally:
                    elapsed = time.monotonic() - started
                    signal.setitimer(signal.ITIMER_REAL, 0)
                    signal.signal(signal.SIGALRM, previous_handler)

            self.assertLess(elapsed, 0.5)
            self.assertEqual(state_file.read_bytes(), original_bytes)

    async def test_work_transaction_uses_latest_external_apps_path(self) -> None:
        with tempfile.TemporaryDirectory() as tempdir:
            root = Path(tempdir)
            state_file = root / "state.json"
            state_file.write_text(
                json.dumps(
                    {
                        "_version": 2,
                        "menus": {
                            "work": {
                                "apps_file": "data/old.json",
                                "workspace_domain": "old.example",
                            }
                        },
                    }
                ),
                encoding="utf-8",
            )
            app = BaristaApp(config_path=str(state_file))

            async with app.run_test(size=(120, 50)) as pilot:
                await pilot.pause()
                save_config(
                    BaristaConfig(),
                    updates={
                        "menus": {
                            "work": {"apps_file": "data/latest.json"}
                        }
                    },
                    state_file=state_file,
                )
                app.query_one("#work_workspace_domain", Input).value = "new.example"
                self.assertTrue(app.action_save())

            self.assertFalse((root / "data" / "old.json").exists())
            latest_apps = json.loads(
                (root / "data" / "latest.json").read_text(encoding="utf-8")
            )
            gmail = next(
                row
                for row in latest_apps
                if row.get("id") == "work_google_gmail"
            )
            self.assertEqual(
                gmail["url"],
                "https://mail.google.com/a/new.example/",
            )
            saved = json.loads(state_file.read_text(encoding="utf-8"))
            self.assertEqual(
                saved["menus"]["work"]["apps_file"],
                "data/latest.json",
            )
            self.assertEqual(
                app.config.menus["work"]["apps_file"],
                "data/latest.json",
            )

    async def test_work_transaction_uses_latest_external_domain(self) -> None:
        with tempfile.TemporaryDirectory() as tempdir:
            root = Path(tempdir)
            state_file = root / "state.json"
            state_file.write_text(
                json.dumps(
                    {
                        "_version": 2,
                        "menus": {
                            "work": {
                                "apps_file": "data/old.json",
                                "workspace_domain": "old.example",
                            }
                        },
                    }
                ),
                encoding="utf-8",
            )
            app = BaristaApp(config_path=str(state_file))

            async with app.run_test(size=(120, 50)) as pilot:
                await pilot.pause()
                save_config(
                    BaristaConfig(),
                    updates={
                        "menus": {
                            "work": {
                                "workspace_domain": "latest.example"
                            }
                        }
                    },
                    state_file=state_file,
                )
                app.query_one("#work_apps_file", Input).value = "data/new.json"
                self.assertTrue(app.action_save())

            latest_apps = json.loads(
                (root / "data" / "new.json").read_text(encoding="utf-8")
            )
            gmail = next(
                row
                for row in latest_apps
                if row.get("id") == "work_google_gmail"
            )
            self.assertEqual(
                gmail["url"],
                "https://mail.google.com/a/latest.example/",
            )
            saved = json.loads(state_file.read_text(encoding="utf-8"))
            self.assertEqual(
                saved["menus"]["work"]["workspace_domain"],
                "latest.example",
            )
            self.assertEqual(
                app.config.menus["work"]["workspace_domain"],
                "latest.example",
            )

    async def test_shared_apps_writer_serializes_with_work_save(self) -> None:
        with tempfile.TemporaryDirectory() as tempdir:
            root = Path(tempdir)
            state_file = root / "state.json"
            apps_file = root / "data" / "shared.json"
            state_file.write_text(
                json.dumps(
                    {
                        "_version": 2,
                        "menus": {
                            "work": {
                                "apps_file": "data/shared.json",
                                "workspace_domain": "old.example",
                            }
                        },
                    }
                ),
                encoding="utf-8",
            )
            apps_file.parent.mkdir(parents=True)
            apps_file.write_text(
                json.dumps([{"id": "existing_custom"}]),
                encoding="utf-8",
            )
            app = BaristaApp(config_path=str(state_file))
            merge_entered = threading.Event()
            writer_attempted = threading.Event()
            writer_errors: list[BaseException] = []
            external_row = {"id": "external_after_tui"}

            def writer() -> None:
                try:
                    if not merge_entered.wait(timeout=2):
                        raise TimeoutError("TUI merge did not start")
                    writer_attempted.set()
                    update_json_array_document(
                        apps_file,
                        lambda rows: rows + [external_row],
                    )
                except BaseException as exc:
                    writer_errors.append(exc)

            original_merge = app._merge_managed_work_apps

            def gated_merge(existing, generated):
                merge_entered.set()
                if not writer_attempted.wait(timeout=2):
                    raise TimeoutError("shared writer did not attempt save")
                time.sleep(0.05)
                return original_merge(existing, generated)

            thread = threading.Thread(target=writer)
            async with app.run_test(size=(120, 50)) as pilot:
                await pilot.pause()
                app.query_one("#work_workspace_domain", Input).value = "new.example"
                thread.start()
                with mock.patch.object(
                    app,
                    "_merge_managed_work_apps",
                    side_effect=gated_merge,
                ):
                    self.assertTrue(app.action_save())
            thread.join(timeout=3)

            self.assertFalse(thread.is_alive())
            self.assertEqual(writer_errors, [])
            apps = json.loads(apps_file.read_text(encoding="utf-8"))
            ids = [
                row.get("id")
                for row in apps
                if isinstance(row, dict)
            ]
            self.assertIn("existing_custom", ids)
            self.assertIn("work_google_gmail", ids)
            self.assertIn("external_after_tui", ids)

    async def test_invalid_appearance_values_do_not_write_or_reload(self) -> None:
        with tempfile.TemporaryDirectory() as tempdir:
            state_file = Path(tempdir) / "state.json"
            state_file.write_text(
                json.dumps(
                    {
                        "_version": 2,
                        "appearance": {
                            "bar_height": 28,
                            "bar_color": "0xC021162F",
                        },
                    }
                ),
                encoding="utf-8",
            )
            original_bytes = state_file.read_bytes()
            app = BaristaApp(config_path=str(state_file))

            async with app.run_test(size=(120, 50)) as pilot:
                await pilot.pause()
                initial_values = copy.deepcopy(app._initial_values)
                height = app.query_one("#bar_height", Input)
                color = app.query_one("#bar_color", Input)

                height.value = "999"
                with mock.patch("tui.app.reload_sketchybar") as reload:
                    app.action_save_reload()
                reload.assert_not_called()
                self.assertEqual(state_file.read_bytes(), original_bytes)
                self.assertEqual(app._initial_values, initial_values)

                color.value = "0xC021162F"
                height.value = ""
                with mock.patch("tui.app.reload_sketchybar") as reload:
                    app.action_save_reload()
                reload.assert_not_called()
                self.assertEqual(state_file.read_bytes(), original_bytes)
                self.assertEqual(app._initial_values, initial_values)

                height.value = "28"
                app.query_one("#menu_font_size_offset", Input).value = "abc"
                with mock.patch("tui.app.reload_sketchybar") as reload:
                    app.action_save_reload()
                reload.assert_not_called()
                self.assertEqual(state_file.read_bytes(), original_bytes)
                self.assertEqual(app._initial_values, initial_values)

                height.value = "28"
                app.query_one("#menu_font_size_offset", Input).value = "1"
                color.value = "not-a-color"
                with mock.patch("tui.app.reload_sketchybar") as reload:
                    app.action_save_reload()
                reload.assert_not_called()
                self.assertEqual(state_file.read_bytes(), original_bytes)
                self.assertEqual(app._initial_values, initial_values)

    async def test_non_work_save_never_merges_unvalidated_external_state(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as tempdir:
            state_file = Path(tempdir) / "state.json"
            state_file.write_text(
                json.dumps(
                    {
                        "_version": 2,
                        "appearance": {"bar_height": 28},
                        "system_info_items": {"cpu": False},
                    }
                ),
                encoding="utf-8",
            )
            app = BaristaApp(config_path=str(state_file))
            injected = False
            invalid_state_bytes = b""

            def validate_then_inject(document, path):
                nonlocal injected, invalid_state_bytes
                validated = validate_config_document(document, path)
                if not injected:
                    external = json.loads(
                        state_file.read_text(encoding="utf-8")
                    )
                    external["appearance"]["bar_height"] = 999
                    state_file.write_text(
                        json.dumps(external),
                        encoding="utf-8",
                    )
                    invalid_state_bytes = state_file.read_bytes()
                    injected = True
                return validated

            async with app.run_test(size=(120, 50)) as pilot:
                await pilot.pause()
                initial_values = copy.deepcopy(app._initial_values)
                app.query_one("#sysinfo_cpu", Switch).value = True
                with mock.patch(
                    "tui.app.validate_config_document",
                    side_effect=validate_then_inject,
                ):
                    self.assertFalse(app.action_save())
                self.assertEqual(app._initial_values, initial_values)

            self.assertTrue(injected)
            self.assertEqual(state_file.read_bytes(), invalid_state_bytes)
            saved = json.loads(state_file.read_text(encoding="utf-8"))
            self.assertEqual(saved["appearance"]["bar_height"], 999)
            self.assertFalse(saved["system_info_items"]["cpu"])

    async def test_runtime_path_save_uses_state_and_leaves_legacy_local_untouched(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as tempdir:
            root = Path(tempdir)
            state_file = root / "state.json"
            local_file = root / "local.json"
            state_file.write_text(
                json.dumps(
                    {
                        "_version": 2,
                        "paths": {"future_path": "/keep/me"},
                    }
                ),
                encoding="utf-8",
            )
            local_file.write_text(
                json.dumps(
                    {
                        "paths": {"code": "/legacy/code"},
                        "future_local": {"keep": True},
                    }
                ),
                encoding="utf-8",
            )
            local_bytes = local_file.read_bytes()
            app = BaristaApp(config_path=str(state_file))

            async with app.run_test(size=(120, 50)) as pilot:
                await pilot.pause()
                code_path = app.query_one("#path_code_dir", Input)
                self.assertEqual(code_path.value, "/legacy/code")
                code_path.value = "/new/runtime/code"
                self.assertTrue(app.action_save())

            saved = json.loads(state_file.read_text(encoding="utf-8"))
            self.assertEqual(saved["paths"]["code_dir"], "/new/runtime/code")
            self.assertEqual(saved["paths"]["future_path"], "/keep/me")
            self.assertEqual(local_file.read_bytes(), local_bytes)

    async def test_future_path_keys_use_safe_ids_and_save_losslessly(self) -> None:
        with tempfile.TemporaryDirectory() as tempdir:
            state_file = Path(tempdir) / "state.json"
            state_file.write_text(
                json.dumps(
                    {
                        "_version": 2,
                        "paths": {
                            "future.path": "/tmp/punctuation",
                            "1leading": "/tmp/leading-digit",
                        },
                    }
                ),
                encoding="utf-8",
            )
            original_bytes = state_file.read_bytes()
            app = BaristaApp(config_path=str(state_file))

            async with app.run_test(size=(120, 50)) as pilot:
                await pilot.pause()
                self.assertEqual(
                    app.query_one("#path_custom_0", Input).value,
                    "/tmp/punctuation",
                )
                self.assertEqual(
                    app.query_one("#path_custom_1", Input).value,
                    "/tmp/leading-digit",
                )
                self.assertTrue(app.action_save())

            self.assertEqual(state_file.read_bytes(), original_bytes)


if __name__ == "__main__":
    unittest.main()
