#!/usr/bin/env python3

import contextlib
import importlib.util
import io
import json
import os
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "dock_studio.py"


def load_module(music: Path):
    os.environ["BARISTA_MUSIC_DIR"] = str(music)
    spec = importlib.util.spec_from_file_location("dock_studio", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    sys.modules["dock_studio"] = module
    spec.loader.exec_module(module)
    return module


class DockStudioTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.music = Path(self.tmp.name)
        self.studio = load_module(self.music)

    def tearDown(self):
        self.tmp.cleanup()
        os.environ.pop("BARISTA_MUSIC_DIR", None)

    def test_song_pick_is_read_from_the_boxed_output(self):
        text = ("╭──── work on this next ────╮\n│                            │\n"
                "│  ▶ song 01 — untitled   [SPARK]   │\n│    Capture one idea.   │\n")
        self.assertEqual(self.studio.song_line(text), ("song 01 — untitled", "SPARK"))
        self.assertEqual(self.studio.song_line("\x1b[1m▶ demo\x1b[0m"), ("demo", ""))
        self.assertIsNone(self.studio.song_line("nothing to do"))

    def test_logic_projects_are_dated_by_their_project_data(self):
        old = self.music / "Logic/old.logicx"
        new = self.music / "Projects/Logic Projects/Keepers/new.logicx"
        for bundle, stamp in ((old, 2_000), (new, 1_000)):
            data = bundle / "Alternatives/000/ProjectData"
            data.parent.mkdir(parents=True)
            data.write_bytes(b"")
            os.utime(data, (stamp, stamp))
            os.utime(bundle, (stamp, stamp))
        # Saving edits ProjectData without touching the bundle's own date.
        os.utime(new / "Alternatives/000/ProjectData", (3_000, 3_000))
        self.assertEqual([path.name for path, _ in self.studio.logic_projects()], ["new.logicx", "old.logicx"])

    def test_rows_summarise_gear_doctor_song_session_and_now(self):
        devices = {"summary": {"audio_inputs": 6}, "devices": [
            {"display_name": "TR-1000", "connected": True}, {"display_name": "TB-303", "connected": True},
            {"display_name": "JU-06A", "connected": True}, {"display_name": "SH-4D", "connected": False}]}
        doctor = {"status": "warning", "recommended_action": {"label": "Pick your capture input"}}
        now = 100 * 86400
        rows = self.studio.status_rows(devices, doctor, ("song 01", "SPARK"),
                                       [(Path("/m/da funk.logicx"), now - 2 * 86400)], now - 20 * 86400, now)
        self.assertEqual(rows[0], {"title": "Gear · 3 connected", "detail": "TR-1000, TB-303 +1",
                                   "tone": "ok", "action": "Studio Doctor"})
        self.assertEqual(rows[1]["title"], "Pick your capture input")
        self.assertEqual(rows[1]["tone"], "warn")
        self.assertEqual(rows[2], {"title": "Next · song 01", "detail": "SPARK", "tone": "none",
                                   "action": "Next Song"})
        self.assertEqual(rows[3]["title"], "Last session · da funk")
        self.assertEqual(rows[3]["detail"], "2d ago")
        self.assertEqual(rows[4]["tone"], "warn")

    def test_missing_sources_drop_their_rows(self):
        rows = self.studio.status_rows(None, {"status": "ok"}, None, [], None, 0)
        self.assertEqual(rows, [{"title": "Studio ready", "detail": "doctor", "tone": "ok",
                                 "action": "Studio Doctor"}])

    def test_a_dangling_project_does_not_hide_the_others(self):
        good = self.music / "Logic/good.logicx"
        good.mkdir(parents=True)
        (self.music / "Logic/gone.logicx").symlink_to(self.music / "nowhere")
        self.assertEqual([path.name for path, _ in self.studio.logic_projects()], ["good.logicx"])

    def test_cli_output_of_the_wrong_shape_is_ignored(self):
        for text in (None, "", "not json", "[1, 2]", "null"):
            self.assertIsNone(self.studio.json_object(text))
        rows = self.studio.status_rows({"devices": "broken", "summary": []},
                                       {"status": "warning", "recommended_action": "fix it"}, None, [], None, 0)
        self.assertEqual(rows[0]["title"], "Gear · nothing connected")
        self.assertEqual(rows[1]["title"], "Studio ready")

    def test_ages_under_an_hour_count_minutes(self):
        self.assertEqual(self.studio.age(30), "just now")
        self.assertEqual(self.studio.age(50 * 60), "50m ago")
        self.assertEqual(self.studio.age(3 * 3600), "3h ago")

    def test_a_hung_cli_is_killed_with_everything_it_started(self):
        marker = self.music / "grandchild.pid"
        script = self.music / "slow-studio"
        script.write_text(f"#!/bin/sh\nsleep 30 &\necho $! > '{marker}'\nwait\n")
        script.chmod(0o755)
        started = time.monotonic()
        self.assertIsNone(self.studio.run_studio(str(script), [], 0.5))
        # A grandchild left alive holds stdout open, so this also proves it died.
        self.assertLess(time.monotonic() - started, 5)
        pid = int(marker.read_text())
        with self.assertRaises(ProcessLookupError):
            for _ in range(20):
                os.kill(pid, 0)
                time.sleep(0.05)

    def test_info_always_prints_rows(self):
        script = self.music / "broken-studio"
        script.write_text("#!/bin/sh\necho '[\"not\", \"an object\"]'\n")
        script.chmod(0o755)
        os.environ["BARISTA_STUDIO_BIN"] = str(script)
        self.addCleanup(os.environ.pop, "BARISTA_STUDIO_BIN", None)
        result = subprocess.run([sys.executable, str(SCRIPT), "info"], capture_output=True, text=True,
                                env=dict(os.environ), timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout)["rows"][0]["title"], "Studio status unavailable")

    def test_an_unexpected_error_still_prints_a_row(self):
        os.environ["BARISTA_STUDIO_BIN"] = "/usr/bin/true"
        self.addCleanup(os.environ.pop, "BARISTA_STUDIO_BIN", None)

        def broken(*_):
            raise KeyError("surprise")
        self.studio.status_rows = broken
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            self.assertEqual(self.studio.main(["info"]), 0)
        self.assertEqual(json.loads(output.getvalue())["rows"],
                         [{"title": "Studio status unavailable", "tone": "warn", "detail": "KeyError"}])

if __name__ == "__main__":
    unittest.main()
