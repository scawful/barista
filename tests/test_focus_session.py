#!/usr/bin/env python3

import datetime as dt
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "focus_session.py"


class FocusSessionTests(unittest.TestCase):
    def run_focus(self, state_file, *arguments, env=None, expected_code=0):
        result = subprocess.run(
            [
                sys.executable,
                str(SCRIPT),
                "--state-file",
                str(state_file),
                *map(str, arguments),
            ],
            check=False,
            capture_output=True,
            text=True,
            env=env,
        )
        self.assertEqual(result.returncode, expected_code, result.stderr)
        return result

    def test_missing_start_status_and_stop(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            state_file = Path(temp_dir) / "cache with spaces" / "state.json"

            missing = json.loads(self.run_focus(state_file, "status").stdout)
            self.assertEqual(missing["state"], "idle")
            self.assertEqual(missing["health"], "missing")
            self.assertFalse(state_file.exists())

            started = json.loads(self.run_focus(state_file, "start", 25).stdout)
            self.assertEqual(started["state"], "active")
            self.assertTrue(started["active"])
            self.assertEqual(started["duration_minutes"], 25)
            self.assertGreaterEqual(started["remaining_seconds"], 1499)
            self.assertEqual(started["remaining_minutes"], 25)
            self.assertEqual(state_file.stat().st_mode & 0o777, 0o600)
            self.assertEqual(list(state_file.parent.glob(".state.json.*.tmp")), [])

            status = json.loads(self.run_focus(state_file, "status").stdout)
            self.assertEqual(status["state"], "active")
            self.assertEqual(status["health"], "ok")
            self.assertLessEqual(status["remaining_seconds"], 1500)

            stopped = json.loads(self.run_focus(state_file, "stop").stdout)
            self.assertEqual(stopped["state"], "idle")
            self.assertEqual(stopped["health"], "ok")
            stored = json.loads(state_file.read_text(encoding="utf-8"))
            self.assertEqual(stored["state"], "idle")

    def test_fifty_minute_session_replaces_an_existing_session(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            state_file = Path(temp_dir) / "state.json"
            self.run_focus(state_file, "start", 25)
            replacement = json.loads(self.run_focus(state_file, "start", 50).stdout)
            self.assertEqual(replacement["duration_minutes"], 50)
            self.assertEqual(replacement["remaining_minutes"], 50)
            stored = json.loads(state_file.read_text(encoding="utf-8"))
            self.assertEqual(stored["duration_minutes"], 50)

    def test_toggle_starts_idle_and_stops_active_session(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            state_file = Path(temp_dir) / "state.json"
            started = json.loads(self.run_focus(state_file, "toggle", 25).stdout)
            self.assertTrue(started["active"])
            self.assertEqual(started["duration_minutes"], 25)

            stopped = json.loads(self.run_focus(state_file, "toggle", 25).stdout)
            self.assertFalse(stopped["active"])
            self.assertEqual(stopped["state"], "idle")

    def test_expired_session_is_safe_and_does_not_spawn_cleanup_work(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            state_file = Path(temp_dir) / "state.json"
            started = dt.datetime.now(dt.timezone.utc) - dt.timedelta(minutes=26)
            ended = started + dt.timedelta(minutes=25)
            stored = {
                "version": 1,
                "state": "active",
                "duration_minutes": 25,
                "started_at": started.replace(microsecond=0).isoformat().replace("+00:00", "Z"),
                "ends_at": ended.replace(microsecond=0).isoformat().replace("+00:00", "Z"),
            }
            state_file.write_text(json.dumps(stored), encoding="utf-8")

            status = json.loads(self.run_focus(state_file, "status").stdout)
            self.assertEqual(status["state"], "expired")
            self.assertFalse(status["active"])
            self.assertEqual(status["remaining_seconds"], 0)
            self.assertEqual(status["remaining_minutes"], 0)
            self.assertEqual(json.loads(state_file.read_text(encoding="utf-8")), stored)

    def test_corrupt_or_oversized_state_degrades_to_idle_and_start_recovers(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            state_file = Path(temp_dir) / "state.json"
            for content in ("not json", "{" + "x" * (64 * 1024) + "}"):
                state_file.write_text(content, encoding="utf-8")
                status = json.loads(self.run_focus(state_file, "status").stdout)
                self.assertEqual(status["state"], "idle")
                self.assertEqual(status["health"], "corrupt")

            recovered = json.loads(self.run_focus(state_file, "start", 25).stdout)
            self.assertEqual(recovered["state"], "active")
            self.assertEqual(recovered["health"], "ok")

    def test_duration_is_an_allowlisted_integer_not_a_shell_command(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            state_file = root / "state.json"
            marker = root / "injected"
            result = self.run_focus(
                state_file,
                "start",
                f"25;touch {marker}",
                expected_code=2,
            )
            self.assertIn("invalid int value", result.stderr)
            self.assertFalse(marker.exists())
            self.assertFalse(state_file.exists())

    def test_environment_can_select_an_ignored_cache_path(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            config_dir = Path(temp_dir) / "barista"
            env = os.environ.copy()
            env["BARISTA_CONFIG_DIR"] = str(config_dir)
            result = subprocess.run(
                [sys.executable, str(SCRIPT), "start", "25"],
                check=False,
                capture_output=True,
                text=True,
                env=env,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            state_file = config_dir / "cache" / "focus_session" / "state.json"
            self.assertTrue(state_file.is_file())
            self.assertEqual(json.loads(result.stdout)["duration_minutes"], 25)


if __name__ == "__main__":
    unittest.main()
